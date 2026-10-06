namespace Singularity.Apps.Spreadsheet {

    public class PivotXlsx {
        private const string REL_CACHE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/pivotCacheDefinition";
        private const string REL_RECORDS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/pivotCacheRecords";
        private const string REL_TABLE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/pivotTable";
        private const string CT_CACHE = "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheDefinition+xml";
        private const string CT_RECORDS = "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotCacheRecords+xml";
        private const string CT_TABLE = "application/vnd.openxmlformats-officedocument.spreadsheetml.pivotTable+xml";
        private const string NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        private const string NS_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        private static string num (double d) {
            return Value.format_number_general_full (d);
        }

        private static string rels (string type, string target) {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"%s\" Target=\"%s\"/></Relationships>".printf (type, esc (target));
        }

        private class Field {
            public string name;
            public bool axis;
            public Gee.ArrayList<Value> items = new Gee.ArrayList<Value> ();
            public Gee.HashMap<string, int> index = new Gee.HashMap<string, int> ();
            public bool has_text;
            public bool has_number;
            public bool has_blank;
            public bool has_bool;
            public bool all_int = true;
            public bool dates;
            public double min = double.INFINITY;
            public double max = -double.INFINITY;

            public static string key (Value v) {
                switch (v.kind) {
                    case ValueKind.NUMBER: return "n" + num (v.number);
                    case ValueKind.BOOL: return "b" + (v.number != 0 ? "1" : "0");
                    case ValueKind.EMPTY: return "m";
                    case ValueKind.ERROR: return "e" + v.error.to_string ();
                    default: return "s" + v.display ();
                }
            }

            public void observe (Value v) {
                switch (v.kind) {
                    case ValueKind.NUMBER:
                        has_number = true;
                        if (v.number != Math.floor (v.number)) all_int = false;
                        min = double.min (min, v.number);
                        max = double.max (max, v.number);
                        break;
                    case ValueKind.EMPTY: has_blank = true; break;
                    case ValueKind.BOOL: has_bool = true; break;
                    default: has_text = true; break;
                }
                if (!axis) return;
                string k = key (v);
                if (!index.has_key (k)) {
                    index[k] = items.size;
                    items.add (v);
                }
            }

            public string shared_items () {
                var sb = new StringBuilder ("<sharedItems");
                if (dates && has_number && !has_text && !has_bool) {
                    sb.append (" containsSemiMixedTypes=\"0\" containsNonDate=\"0\" containsDate=\"1\" containsString=\"0\"");
                    if (has_blank) sb.append (" containsBlank=\"1\"");
                    sb.append (" minDate=\"%s\" maxDate=\"%s\"".printf (iso (min), iso (max)));
                    if (!axis) {
                        sb.append ("/>");
                        return sb.str;
                    }
                    sb.append (" count=\"%d\">".printf (items.size));
                    foreach (var v in items) sb.append (item_xml (v, true));
                    sb.append ("</sharedItems>");
                    return sb.str;
                }
                if (has_number && !has_text && !has_bool) {
                    sb.append (" containsSemiMixedTypes=\"0\" containsString=\"0\"");
                } else if (has_number) {
                    sb.append (" containsMixedTypes=\"1\"");
                }
                if (has_number) {
                    sb.append (" containsNumber=\"1\"");
                    if (all_int) sb.append (" containsInteger=\"1\"");
                    sb.append (" minValue=\"%s\" maxValue=\"%s\"".printf (num (min), num (max)));
                }
                if (has_blank) sb.append (" containsBlank=\"1\"");
                if (!axis) {
                    sb.append ("/>");
                    return sb.str;
                }
                sb.append (" count=\"%d\">".printf (items.size));
                foreach (var v in items) sb.append (item_xml (v, false));
                sb.append ("</sharedItems>");
                return sb.str;
            }

            public static string item_xml (Value v, bool date) {
                switch (v.kind) {
                    case ValueKind.NUMBER: return date ? "<d v=\"%s\"/>".printf (iso (v.number)) : "<n v=\"%s\"/>".printf (num (v.number));
                    case ValueKind.BOOL: return "<b v=\"%s\"/>".printf (v.number != 0 ? "1" : "0");
                    case ValueKind.EMPTY: return "<m/>";
                    case ValueKind.ERROR: return "<e v=\"%s\"/>".printf (esc (v.error.to_string ()));
                    default: return "<s v=\"%s\"/>".printf (esc (v.display ()));
                }
            }
        }

        private static string agg_attr (PivotAgg a) {
            return a == PivotAgg.SUM ? "" : " subtotal=\"%s\"".printf (a.key ());
        }

        private static string show_attr (PivotShow s) {
            switch (s) {
                case PivotShow.PERCENT_TOTAL: return " showDataAs=\"percentOfTotal\"";
                case PivotShow.PERCENT_ROW: return " showDataAs=\"percentOfRow\"";
                case PivotShow.PERCENT_COL: return " showDataAs=\"percentOfCol\"";
                case PivotShow.RUNNING_TOTAL: return " showDataAs=\"runTotal\"";
                case PivotShow.DIFFERENCE: return " showDataAs=\"difference\" baseItem=\"1048828\"";
                case PivotShow.PERCENT_DIFFERENCE: return " showDataAs=\"percentDiff\" baseItem=\"1048828\"";
                default: return "";
            }
        }

        public static void write (XlsxWriter w) {
            var book = w.book;
            var pivots = book.analysis.pivots;
            if (pivots.size == 0) return;
            var caches = new StringBuilder ();
            int k = 0;
            foreach (var p in pivots) {
                var a = p.source_area (book);
                int ti = book.sheets.index_of (p.target_sheet);
                if (a == null || a.rows < 2 || ti < 0 || p.last_output == null) continue;
                k++;
                string xml_cache, xml_records, xml_table;
                build (book, p, a, k - 1, out xml_cache, out xml_records, out xml_table);
                string cache_name = "xl/pivotCache/pivotCacheDefinition%d.xml".printf (k);
                string rec_name = "xl/pivotCache/pivotCacheRecords%d.xml".printf (k);
                string table_name = "xl/pivotTables/pivotTable%d.xml".printf (k);
                w.add_text_part (cache_name, xml_cache, CT_CACHE);
                w.add_text_part ("xl/pivotCache/_rels/pivotCacheDefinition%d.xml.rels".printf (k), rels (REL_RECORDS, "pivotCacheRecords%d.xml".printf (k)), null);
                w.add_text_part (rec_name, xml_records, CT_RECORDS);
                w.add_text_part (table_name, xml_table, CT_TABLE);
                w.add_text_part ("xl/pivotTables/_rels/pivotTable%d.xml.rels".printf (k), rels (REL_CACHE, "../pivotCache/pivotCacheDefinition%d.xml".printf (k)), null);
                string rid = w.add_workbook_rel (REL_CACHE, "pivotCache/pivotCacheDefinition%d.xml".printf (k));
                caches.append ("<pivotCache cacheId=\"%d\" r:id=\"%s\"/>".printf (k - 1, rid));
                if (ti < w.parts.size) w.parts[ti].add_rel (REL_TABLE, "../pivotTables/pivotTable%d.xml".printf (k));
            }
            if (caches.len > 0) w.put_workbook ("pivotCaches", "<pivotCaches>" + caches.str + "</pivotCaches>");
        }

        private class Slot {
            public int col;
            public PivotGroup group;
            public int index;
            public PivotField? field;
            public string axis = "";
            public string[] group_items = {};
            public string[] our_labels = {};
            public string range = "";
        }

        public static int granularity (PivotGroup g) {
            switch (g) {
                case PivotGroup.DAYS: return 0;
                case PivotGroup.MONTHS: return 1;
                case PivotGroup.QUARTERS: return 2;
                case PivotGroup.YEARS: return 3;
                default: return -1;
            }
        }

        public static string group_by (PivotGroup g) {
            switch (g) {
                case PivotGroup.DAYS: return "days";
                case PivotGroup.MONTHS: return "months";
                case PivotGroup.QUARTERS: return "quarters";
                case PivotGroup.YEARS: return "years";
                default: return "range";
            }
        }

        public static PivotGroup group_from (string g) {
            switch (g) {
                case "days": return PivotGroup.DAYS;
                case "months": return PivotGroup.MONTHS;
                case "quarters": return PivotGroup.QUARTERS;
                case "years": return PivotGroup.YEARS;
                default: return PivotGroup.INTERVAL;
            }
        }

        public static string iso (double serial) {
            int y, m, d;
            DateSerial.to_ymd (Math.floor (serial), out y, out m, out d);
            return "%04d-%02d-%02dT00:00:00".printf (y, m, d);
        }

        public static double from_iso (string v) {
            if (v.length < 10) return 0;
            return DateSerial.from_ymd (int.parse (v.substring (0, 4)), int.parse (v.substring (5, 2)), int.parse (v.substring (8, 2)));
        }

        private static string us_date (double serial) {
            int y, m, d;
            DateSerial.to_ymd (Math.floor (serial), out y, out m, out d);
            return "%d/%d/%d".printf (m, d, y);
        }

        public static void date_group_items (PivotGroup g, double start, double end, out string[] excel, out string[] ours) {
            string[] e = { "<" + us_date (start) };
            string[] o = { "<" + us_date (start) };
            var months = PivotTable.month_names ();
            string[] en = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
            switch (g) {
                case PivotGroup.YEARS:
                    int y1, y2, m, d;
                    DateSerial.to_ymd (start, out y1, out m, out d);
                    DateSerial.to_ymd (end, out y2, out m, out d);
                    for (int y = y1; y <= y2; y++) {
                        e += y.to_string ();
                        o += y.to_string ();
                    }
                    break;
                case PivotGroup.QUARTERS:
                    for (int q = 1; q <= 4; q++) {
                        e += "Qtr%d".printf (q);
                        o += "Qtr%d".printf (q);
                    }
                    break;
                case PivotGroup.MONTHS:
                    for (int i = 0; i < 12; i++) {
                        e += en[i];
                        o += months[i];
                    }
                    break;
                default:
                    int[] len = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
                    for (int mo = 0; mo < 12; mo++) {
                        for (int day = 1; day <= len[mo]; day++) {
                            e += "%d-%s".printf (day, en[mo]);
                            o += "%d-%s".printf (day, months[mo]);
                        }
                    }
                    break;
            }
            e += ">" + us_date (end);
            o += ">" + us_date (end);
            excel = e;
            ours = o;
        }

        public static void interval_items (double start, double size, double max, out string[] excel) {
            double step = size > 0 ? size : 1;
            bool whole = Math.floor (step) == step;
            string[] e = { "<" + Value.format_number_general (start) };
            double lo = start;
            int guard = 0;
            for (; lo <= max && guard < 10000; lo += step, guard++) e += "%s-%s".printf (Value.format_number_general (lo), Value.format_number_general (lo + step - (whole ? 1 : 0)));
            e += ">" + Value.format_number_general (lo);
            excel = e;
        }

        private static void build (Workbook book, PivotTable p, Area a, int cache_id, out string cache, out string records, out string table) {
            var s = a.sheet;
            int nc = a.cols;
            var fields = new Field[nc];
            var axis_fields = new Gee.ArrayList<PivotField> ();
            var axis_names = new Gee.HashMap<PivotField, string> ();
            foreach (var f in p.rows) { axis_fields.add (f); axis_names[f] = "axisRow"; }
            foreach (var f in p.cols) { axis_fields.add (f); axis_names[f] = "axisCol"; }
            foreach (var f in p.filters) { axis_fields.add (f); axis_names[f] = "axisPage"; }
            var axis_cols = new Gee.HashSet<int> ();
            foreach (var f in axis_fields) axis_cols.add (f.source_col);
            for (int j = 0; j < nc; j++) {
                fields[j] = new Field ();
                string h = s.value_at (a.r1, a.c1 + j).display ();
                fields[j].name = h != "" ? h : "Column%d".printf (j + 1);
                fields[j].axis = axis_cols.contains (j);
            }
            var slots = new Gee.ArrayList<Slot> ();
            var base_group = new Gee.HashMap<int, Slot> ();
            var extras_of = new Gee.HashMap<int, Gee.ArrayList<Slot>> ();
            for (int j = 0; j < nc; j++) {
                var dates = new Gee.ArrayList<PivotField> ();
                PivotField? interval = null;
                foreach (var f in axis_fields) {
                    if (f.source_col != j) continue;
                    if (granularity (f.group) >= 0) {
                        bool dup = false;
                        foreach (var g in dates) if (g.group == f.group) dup = true;
                        if (!dup) dates.add (f);
                    } else if (f.group == PivotGroup.INTERVAL) {
                        interval = f;
                    }
                }
                if (dates.size > 0) {
                    dates.sort ((x, y) => granularity (x.group) - granularity (y.group));
                    fields[j].dates = true;
                    var b = new Slot ();
                    b.col = j;
                    b.group = dates[0].group;
                    b.index = j;
                    b.field = dates[0];
                    base_group[j] = b;
                    var ex = new Gee.ArrayList<Slot> ();
                    for (int i = 1; i < dates.size; i++) {
                        var e = new Slot ();
                        e.col = j;
                        e.group = dates[i].group;
                        e.field = dates[i];
                        ex.add (e);
                    }
                    extras_of[j] = ex;
                } else if (interval != null) {
                    var b = new Slot ();
                    b.col = j;
                    b.group = PivotGroup.INTERVAL;
                    b.index = j;
                    b.field = interval;
                    base_group[j] = b;
                }
            }
            int next_index = nc;
            for (int j = 0; j < nc; j++) {
                if (!extras_of.has_key (j)) continue;
                foreach (var e in extras_of[j]) {
                    e.index = next_index++;
                    slots.add (e);
                }
            }
            var rec = new StringBuilder ();
            int count = 0;
            for (int r = a.r1 + 1; r <= a.r2; r++) {
                bool blank = true;
                for (int j = 0; j < nc && blank; j++) if (!s.value_at (r, a.c1 + j).is_empty ()) blank = false;
                if (blank) continue;
                count++;
                rec.append ("<r>");
                for (int j = 0; j < nc; j++) {
                    var v = s.value_at (r, a.c1 + j);
                    fields[j].observe (v);
                    if (fields[j].axis) rec.append ("<x v=\"%d\"/>".printf (fields[j].index[Field.key (v)]));
                    else rec.append (Field.item_xml (v, fields[j].dates));
                }
                rec.append ("</r>");
            }
            foreach (var e in base_group.values) prepare_slot (e, fields[e.col]);
            foreach (var e in slots) prepare_slot (e, fields[e.col]);
            records = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<pivotCacheRecords xmlns=\"%s\" xmlns:r=\"%s\" count=\"%d\">%s</pivotCacheRecords>".printf (NS, NS_R, count, rec.str);
            string src = p.source_table != "" && Tables.find (book, p.source_table) != null
                ? "<worksheetSource name=\"%s\"/>".printf (esc (p.source_table))
                : "<worksheetSource ref=\"%s\" sheet=\"%s\"/>".printf (a.to_string (), esc (s.name));
            var cf = new StringBuilder ();
            for (int j = 0; j < nc; j++) {
                var f = fields[j];
                string group_xml = "";
                if (base_group.has_key (j)) {
                    var b = base_group[j];
                    string par = "";
                    if (extras_of.has_key (j) && extras_of[j].size > 0) par = " par=\"%d\"".printf (extras_of[j][extras_of[j].size - 1].index);
                    group_xml = "<fieldGroup%s base=\"%d\">%s%s</fieldGroup>".printf (par, j, b.range, items_xml (b.group_items));
                }
                cf.append ("<cacheField name=\"%s\" numFmtId=\"%s\">%s%s</cacheField>".printf (esc (f.name), f.dates ? "14" : "0", f.shared_items (), group_xml));
            }
            foreach (var e in slots) {
                string name = e.field.name != fields[e.col].name ? e.field.name : e.group.label ();
                cf.append ("<cacheField name=\"%s\" numFmtId=\"0\" databaseField=\"0\"><fieldGroup base=\"%d\">%s%s</fieldGroup></cacheField>".printf (esc (name), e.col, e.range, items_xml (e.group_items)));
            }
            int total_fields = nc + slots.size;
            cache = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<pivotCacheDefinition xmlns=\"%s\" xmlns:r=\"%s\" r:id=\"rId1\" refreshOnLoad=\"1\" refreshedBy=\"%s\" createdVersion=\"8\" refreshedVersion=\"8\" minRefreshableVersion=\"3\" recordCount=\"%d\"><cacheSource type=\"worksheet\">%s</cacheSource><cacheFields count=\"%d\">%s</cacheFields></pivotCacheDefinition>".printf (
                NS, NS_R, esc (XlsxExtras.default_author ()), count, src, total_fields, cf.str);
            var index_of = new Gee.HashMap<PivotField, int> ();
            foreach (var f in axis_fields) {
                int idx = f.source_col;
                if (extras_of.has_key (f.source_col)) foreach (var e in extras_of[f.source_col]) if (e.group == f.group) idx = e.index;
                index_of[f] = idx;
            }
            var pf = new StringBuilder ("<pivotFields count=\"%d\">".printf (total_fields));
            for (int j = 0; j < total_fields; j++) {
                PivotField? axis_field = null;
                foreach (var f in axis_fields) if (index_of[f] == j && axis_field == null) axis_field = f;
                bool is_data = false;
                if (j < nc) foreach (var v in p.values) if (v.source_col == j) is_data = true;
                pf.append ("<pivotField");
                if (axis_field != null) pf.append (" axis=\"%s\"".printf (axis_names[axis_field]));
                if (is_data) pf.append (" dataField=\"1\"");
                if (j < nc && fields[j].dates) pf.append (" numFmtId=\"14\"");
                pf.append (" showAll=\"0\"");
                if (axis_field != null) pf.append (" compact=\"0\" outline=\"0\"");
                if (axis_field != null && axis_field.descending) pf.append (" sortType=\"descending\"");
                if (axis_field != null && !p.subtotals) pf.append (" defaultSubtotal=\"0\"");
                if (axis_field == null) {
                    pf.append ("/>");
                    continue;
                }
                Slot? slot = null;
                if (j < nc && base_group.has_key (j)) slot = base_group[j];
                foreach (var e in slots) if (e.index == j) slot = e;
                var items = new StringBuilder ();
                int n_items;
                if (slot != null) {
                    n_items = slot.group_items.length;
                    for (int i = 0; i < n_items; i++) {
                        bool hidden = axis_field.hidden.contains (slot.our_labels[i]);
                        items.append ("<item%s x=\"%d\"/>".printf (hidden ? " h=\"1\"" : "", i));
                    }
                } else {
                    var f = fields[j];
                    var order = new Gee.ArrayList<int> ();
                    for (int i = 0; i < f.items.size; i++) order.add (i);
                    order.sort ((x, y) => PivotItem.compare (PivotTable.item_of (new PivotField (0, ""), f.items[x], book), PivotTable.item_of (new PivotField (0, ""), f.items[y], book)));
                    n_items = f.items.size;
                    foreach (int i in order) {
                        string label = PivotTable.item_of (axis_field, f.items[i], book).label;
                        bool hidden = axis_field.group == PivotGroup.NONE && axis_field.hidden.contains (label);
                        items.append ("<item%s x=\"%d\"/>".printf (hidden ? " h=\"1\"" : "", i));
                    }
                }
                if (p.subtotals) {
                    items.append ("<item t=\"default\"/>");
                    n_items++;
                }
                pf.append ("><items count=\"%d\">%s</items></pivotField>".printf (n_items, items.str));
            }
            pf.append ("</pivotFields>");
            var t = new StringBuilder ();
            var loc = p.last_output;
            int header_rows = p.cols.size == 0 ? 1 : p.cols.size + 1 + (p.values.size > 1 ? 1 : 0);
            t.append ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<pivotTableDefinition xmlns=\"%s\" name=\"%s\" cacheId=\"%d\" applyNumberFormats=\"0\" applyBorderFormats=\"0\" applyFontFormats=\"0\" applyPatternFormats=\"0\" applyAlignmentFormats=\"0\" applyWidthHeightFormats=\"1\" dataCaption=\"%s\" updatedVersion=\"8\" minRefreshableVersion=\"3\" useAutoFormatting=\"1\"%s%s itemPrintTitles=\"1\" createdVersion=\"8\" indent=\"0\" compact=\"0\" compactData=\"0\" outline=\"1\" outlineData=\"1\" gridDropZones=\"1\">".printf (
                NS, esc (p.name), cache_id, esc (_("Values")), p.row_grand ? "" : " rowGrandTotals=\"0\"", p.col_grand ? "" : " colGrandTotals=\"0\""));
            t.append ("<location ref=\"%s\" firstHeaderRow=\"1\" firstDataRow=\"%d\" firstDataCol=\"%d\"%s/>".printf (
                new Area (null, loc.r1, loc.c1, loc.r2, loc.c2).to_string (), header_rows, int.max (1, p.rows.size),
                p.filters.size > 0 ? " rowPageCount=\"%d\" colPageCount=\"1\"".printf (p.filters.size) : ""));
            t.append (pf.str);
            if (p.rows.size > 0) {
                t.append ("<rowFields count=\"%d\">".printf (p.rows.size));
                foreach (var f in p.rows) t.append ("<field x=\"%d\"/>".printf (index_of[f]));
                t.append ("</rowFields>");
            }
            int ncols = p.cols.size + (p.values.size > 1 ? 1 : 0);
            if (ncols > 0) {
                t.append ("<colFields count=\"%d\">".printf (ncols));
                foreach (var f in p.cols) t.append ("<field x=\"%d\"/>".printf (index_of[f]));
                if (p.values.size > 1) t.append ("<field x=\"-2\"/>");
                t.append ("</colFields>");
            }
            if (p.filters.size > 0) {
                t.append ("<pageFields count=\"%d\">".printf (p.filters.size));
                foreach (var f in p.filters) t.append ("<pageField fld=\"%d\" hier=\"-1\"/>".printf (index_of[f]));
                t.append ("</pageFields>");
            }
            if (p.values.size > 0) {
                t.append ("<dataFields count=\"%d\">".printf (p.values.size));
                foreach (var v in p.values) {
                    t.append ("<dataField name=\"%s\" fld=\"%d\"%s%s%s/>".printf (esc (v.caption ()), v.source_col, agg_attr (v.agg), show_attr (v.show),
                        v.show == PivotShow.DIFFERENCE || v.show == PivotShow.PERCENT_DIFFERENCE ? " baseField=\"%d\"".printf (p.rows.size > 0 ? index_of[p.rows[0]] : 0) : " baseField=\"0\" baseItem=\"0\""));
                }
                t.append ("</dataFields>");
            }
            t.append ("<pivotTableStyleInfo name=\"PivotStyleLight16\" showRowHeaders=\"1\" showColHeaders=\"1\" showRowStripes=\"0\" showColStripes=\"0\" showLastColumn=\"1\"/>");
            t.append ("</pivotTableDefinition>");
            table = t.str;
        }

        private static string items_xml (string[] items) {
            var sb = new StringBuilder ("<groupItems count=\"%d\">".printf (items.length));
            foreach (string it in items) sb.append ("<s v=\"%s\"/>".printf (esc (it)));
            sb.append ("</groupItems>");
            return sb.str;
        }

        private static void prepare_slot (Slot e, Field f) {
            double min = f.min.is_infinity () != 0 ? 0 : f.min;
            double max = f.max.is_infinity () != 0 ? 0 : f.max;
            if (e.group == PivotGroup.INTERVAL) {
                double start = e.field.interval_start;
                double size = e.field.interval_size > 0 ? e.field.interval_size : 1;
                string[] ex;
                interval_items (start, size, max, out ex);
                e.group_items = ex;
                e.our_labels = ex;
                e.range = "<rangePr autoStart=\"0\" startNum=\"%s\" endNum=\"%s\" groupInterval=\"%s\"/>".printf (num (start), num (max), num (size));
                return;
            }
            double start = Math.floor (min);
            double end = Math.floor (max) + 1;
            string[] ex, ours;
            date_group_items (e.group, start, end, out ex, out ours);
            e.group_items = ex;
            e.our_labels = ours;
            e.range = "<rangePr groupBy=\"%s\" startDate=\"%s\" endDate=\"%s\"/>".printf (group_by (e.group), iso (start), iso (end));
        }

        public static string data_table_formula (Workbook book, Sheet s, int r, int c) {
            foreach (var dt in book.analysis.data_tables) {
                if (dt.sheet != s || dt.area.r1 + 1 != r || dt.area.c1 + 1 != c) continue;
                var inner = dt.interior;
                string rf = new Area (null, inner.r1, inner.c1, inner.r2, inner.c2).to_string ();
                if (dt.two_way ()) {
                    return "<f t=\"dataTable\" ref=\"%s\" dt2D=\"1\" dtr=\"1\" r1=\"%s\" r2=\"%s\"/>".printf (rf, Address.cell (dt.row_input.row, dt.row_input.col), Address.cell (dt.col_input.row, dt.col_input.col));
                }
                if (dt.row_input != null) return "<f t=\"dataTable\" ref=\"%s\" dt2D=\"0\" dtr=\"1\" r1=\"%s\"/>".printf (rf, Address.cell (dt.row_input.row, dt.row_input.col));
                if (dt.col_input != null) return "<f t=\"dataTable\" ref=\"%s\" dt2D=\"0\" dtr=\"0\" r1=\"%s\"/>".printf (rf, Address.cell (dt.col_input.row, dt.col_input.col));
            }
            return "";
        }

        public static void read_data_tables (Xlsx x, Gee.HashMap<string, string> wb_rels) throws Error {
            var wdoc = Xlsx.parse (x.zip.read_text ("xl/workbook.xml"));
            if (wdoc == null) return;
            var sheets_node = Xlsx.child (wdoc->get_root_element (), "sheets");
            var paths = new Gee.ArrayList<string> ();
            for (Xml.Node* sn = sheets_node != null ? sheets_node->children : null; sn != null; sn = sn->next) {
                if (sn->type != Xml.ElementType.ELEMENT_NODE) continue;
                string rid = sn->get_ns_prop ("id", NS_R) ?? "";
                paths.add (wb_rels.has_key (rid) ? wb_rels[rid] : "");
            }
            delete wdoc;
            for (int i = 0; i < paths.size && i < x.book.sheets.size; i++) {
                if (paths[i] == "" || !x.zip.has (paths[i])) continue;
                string? text = x.zip.read_text (paths[i]);
                if (text == null || !text.contains ("dataTable")) continue;
                var doc = Xlsx.parse (text);
                if (doc == null) continue;
                var data = Xlsx.child (doc->get_root_element (), "sheetData");
                var sheet = x.book.sheets[i];
                for (Xml.Node* row = data != null ? data->children : null; row != null; row = row->next) {
                    for (Xml.Node* c = row->children; c != null; c = c->next) {
                        if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                        var f = Xlsx.child (c, "f");
                        if (f == null || Xlsx.attr (f, "t") != "dataTable") continue;
                        var inner = Area.parse (Xlsx.attr (f, "ref"), sheet);
                        if (inner == null || inner.r1 < 1 || inner.c1 < 1) continue;
                        var dt = new DataTableDef (sheet, new Area (sheet, inner.r1 - 1, inner.c1 - 1, inner.r2, inner.c2));
                        int rr, cc;
                        bool ar, ac;
                        bool two = Xlsx.attr (f, "dt2D") == "1" || Xlsx.attr (f, "dt2D") == "true";
                        bool row_oriented = Xlsx.attr (f, "dtr") == "1" || Xlsx.attr (f, "dtr") == "true";
                        if (Address.parse_cell (Xlsx.attr (f, "r1").replace ("$", ""), out rr, out cc, out ar, out ac)) {
                            if (two || row_oriented) dt.row_input = new CellRef (sheet, rr, cc);
                            else dt.col_input = new CellRef (sheet, rr, cc);
                        }
                        if (two && Address.parse_cell (Xlsx.attr (f, "r2").replace ("$", ""), out rr, out cc, out ar, out ac)) dt.col_input = new CellRef (sheet, rr, cc);
                        if (dt.row_input != null || dt.col_input != null) x.book.analysis.data_tables.add (dt);
                    }
                }
                delete doc;
            }
        }
    }
}
