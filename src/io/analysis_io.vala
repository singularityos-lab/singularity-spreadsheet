namespace Singularity.Apps.Spreadsheet {

    public class AnalysisStore {
        public const string XLSX_PART = "customXml/singularityAnalysis.xml";
        public const string ODS_PART = "Singularity/analysis.ini";
        public static bool ignore_store = false;

        private static string area_text (Area? a) {
            if (a == null || a.sheet == null) return "";
            return a.sheet.name + "\t" + "%d,%d,%d,%d".printf (a.r1, a.c1, a.r2, a.c2);
        }

        private static Area? area_parse (Workbook book, string t) {
            int sep = t.index_of ("\t");
            if (sep < 0) return null;
            var s = book.find_sheet (t.substring (0, sep));
            if (s == null) return null;
            var p = t.substring (sep + 1).split (",");
            if (p.length != 4) return null;
            return new Area (s, int.parse (p[0]), int.parse (p[1]), int.parse (p[2]), int.parse (p[3]));
        }

        private static string cellref_text (CellRef? c) {
            if (c == null) return "";
            return c.sheet.name + "\t%d,%d".printf (c.row, c.col);
        }

        private static CellRef? cellref_parse (Workbook book, string t) {
            int sep = t.index_of ("\t");
            if (sep < 0) return null;
            var s = book.find_sheet (t.substring (0, sep));
            if (s == null) return null;
            var p = t.substring (sep + 1).split (",");
            if (p.length != 2) return null;
            return new CellRef (s, int.parse (p[0]), int.parse (p[1]));
        }

        private static void put_fields (KeyFile kf, string g, string key, Gee.List<PivotField> fields) {
            kf.set_integer (g, key + ".count", fields.size);
            for (int i = 0; i < fields.size; i++) {
                var f = fields[i];
                string k = "%s.%d".printf (key, i);
                kf.set_integer (g, k + ".col", f.source_col);
                kf.set_string (g, k + ".name", f.name);
                kf.set_integer (g, k + ".group", (int) f.group);
                kf.set_double (g, k + ".istart", f.interval_start);
                kf.set_double (g, k + ".isize", f.interval_size);
                kf.set_boolean (g, k + ".desc", f.descending);
                string[] hidden = {};
                foreach (var h in f.hidden) hidden += h;
                kf.set_string_list (g, k + ".hidden", hidden);
            }
        }

        private static void get_fields (KeyFile kf, string g, string key, Gee.List<PivotField> fields) throws Error {
            int n = kf.has_key (g, key + ".count") ? kf.get_integer (g, key + ".count") : 0;
            for (int i = 0; i < n; i++) {
                string k = "%s.%d".printf (key, i);
                var f = new PivotField (kf.get_integer (g, k + ".col"), kf.get_string (g, k + ".name"));
                f.group = (PivotGroup) kf.get_integer (g, k + ".group");
                f.interval_start = kf.get_double (g, k + ".istart");
                f.interval_size = kf.get_double (g, k + ".isize");
                f.descending = kf.get_boolean (g, k + ".desc");
                foreach (string h in kf.get_string_list (g, k + ".hidden")) f.hidden.add (h);
                fields.add (f);
            }
        }

        public static string serialize (Workbook book) {
            var d = book.analysis;
            var kf = new KeyFile ();
            kf.set_integer ("Analysis", "version", 1);
            for (int i = 0; i < d.pivots.size; i++) {
                var p = d.pivots[i];
                string g = "Pivot %d".printf (i);
                kf.set_string (g, "name", p.name);
                kf.set_string (g, "source", area_text (p.source));
                kf.set_string (g, "table", p.source_table);
                kf.set_string (g, "target", cellref_text (new CellRef (p.target_sheet, p.target_row, p.target_col)));
                kf.set_string (g, "output", area_text (p.last_output));
                kf.set_boolean (g, "row-grand", p.row_grand);
                kf.set_boolean (g, "col-grand", p.col_grand);
                kf.set_boolean (g, "subtotals", p.subtotals);
                put_fields (kf, g, "rows", p.rows);
                put_fields (kf, g, "cols", p.cols);
                put_fields (kf, g, "filters", p.filters);
                kf.set_integer (g, "values.count", p.values.size);
                for (int j = 0; j < p.values.size; j++) {
                    var v = p.values[j];
                    string k = "values.%d".printf (j);
                    kf.set_integer (g, k + ".col", v.source_col);
                    kf.set_string (g, k + ".name", v.name);
                    kf.set_string (g, k + ".agg", v.agg.key ());
                    kf.set_integer (g, k + ".show", (int) v.show);
                    kf.set_string (g, k + ".format", v.number_format);
                }
            }
            for (int i = 0; i < d.scenarios.size; i++) {
                var sc = d.scenarios[i];
                string g = "Scenario %d".printf (i);
                kf.set_string (g, "name", sc.name);
                kf.set_string (g, "comment", sc.comment);
                kf.set_string (g, "sheet", sc.sheet.name);
                string[] cells = {};
                foreach (var c in sc.cells) cells += cellref_text (c);
                kf.set_string_list (g, "cells", cells);
                kf.set_string_list (g, "values", sc.values.to_array ());
            }
            for (int i = 0; i < d.data_tables.size; i++) {
                var dt = d.data_tables[i];
                string g = "DataTable %d".printf (i);
                kf.set_string (g, "area", area_text (dt.area));
                kf.set_string (g, "row-input", cellref_text (dt.row_input));
                kf.set_string (g, "col-input", cellref_text (dt.col_input));
            }
            for (int i = 0; i < d.queries.size; i++) {
                var q = d.queries[i];
                string g = "Query %d".printf (i);
                kf.set_string (g, "name", q.name);
                kf.set_string (g, "source", q.source_kind);
                kf.set_string (g, "location", q.location);
                kf.set_string (g, "delimiter", q.delimiter);
                kf.set_string (g, "sql", q.sql);
                kf.set_string (g, "dest-sheet", q.dest_sheet);
                kf.set_integer (g, "dest-row", q.dest_row);
                kf.set_integer (g, "dest-col", q.dest_col);
                kf.set_boolean (g, "load", q.load);
                kf.set_boolean (g, "as-table", q.as_table);
                kf.set_string (g, "table", q.table_name);
                kf.set_string (g, "output", area_text (q.last_area));
                kf.set_string (g, "refreshed", q.last_refresh);
                kf.set_integer (g, "steps", q.steps.size);
                for (int j = 0; j < q.steps.size; j++) {
                    var st = q.steps[j];
                    kf.set_string (g, "step.%d.kind".printf (j), st.kind);
                    string[] pairs = {};
                    foreach (var e in st.args.entries) pairs += e.key + "=" + e.value;
                    kf.set_string_list (g, "step.%d.args".printf (j), pairs);
                }
            }
            int ri = 0;
            foreach (var rec in d.records.values) rec.save_into (kf, "Linked %d".printf (ri++));
            int li = 0;
            foreach (var e in d.links.entries) {
                string g = "Link %d".printf (li++);
                kf.set_string (g, "cell", e.key);
                kf.set_string (g, "source", e.value.source);
                kf.set_string (g, "key-column", e.value.key_column);
                kf.set_string (g, "key", e.value.key);
            }
            return kf.to_data ();
        }

        public static void deserialize (Workbook book, string text) {
            var d = Analysis.data (book);
            var kf = new KeyFile ();
            try {
                kf.load_from_data (text, text.length, KeyFileFlags.NONE);
            } catch (Error e) {
                return;
            }
            foreach (string g in kf.get_groups ()) {
                try {
                    if (g.has_prefix ("Pivot ")) {
                        var target = cellref_parse (book, kf.get_string (g, "target"));
                        if (target == null) continue;
                        var p = new PivotTable (kf.get_string (g, "name"), target.sheet, target.row, target.col);
                        p.source = area_parse (book, kf.get_string (g, "source"));
                        p.source_table = kf.get_string (g, "table");
                        p.last_output = area_parse (book, kf.get_string (g, "output"));
                        p.row_grand = kf.get_boolean (g, "row-grand");
                        p.col_grand = kf.get_boolean (g, "col-grand");
                        p.subtotals = kf.get_boolean (g, "subtotals");
                        get_fields (kf, g, "rows", p.rows);
                        get_fields (kf, g, "cols", p.cols);
                        get_fields (kf, g, "filters", p.filters);
                        int nv = kf.get_integer (g, "values.count");
                        for (int j = 0; j < nv; j++) {
                            string k = "values.%d".printf (j);
                            var v = new PivotValue (kf.get_integer (g, k + ".col"), kf.get_string (g, k + ".name"), PivotAgg.from_key (kf.get_string (g, k + ".agg")));
                            v.show = (PivotShow) kf.get_integer (g, k + ".show");
                            v.number_format = kf.get_string (g, k + ".format");
                            p.values.add (v);
                        }
                        d.pivots.add (p);
                    } else if (g.has_prefix ("Scenario ")) {
                        var s = book.find_sheet (kf.get_string (g, "sheet"));
                        if (s == null) continue;
                        var sc = new Scenario (kf.get_string (g, "name"), s);
                        sc.comment = kf.get_string (g, "comment");
                        foreach (string c in kf.get_string_list (g, "cells")) {
                            var cr = cellref_parse (book, c);
                            if (cr != null) sc.cells.add (cr);
                        }
                        foreach (string v in kf.get_string_list (g, "values")) sc.values.add (v);
                        d.scenarios.add (sc);
                    } else if (g.has_prefix ("DataTable ")) {
                        var a = area_parse (book, kf.get_string (g, "area"));
                        if (a == null) continue;
                        var dt = new DataTableDef (a.sheet, a);
                        dt.row_input = cellref_parse (book, kf.get_string (g, "row-input"));
                        dt.col_input = cellref_parse (book, kf.get_string (g, "col-input"));
                        d.data_tables.add (dt);
                    } else if (g.has_prefix ("Linked ")) {
                        var rec = LinkedRecord.load_from (kf, g);
                        if (rec != null) d.records[rec.key] = rec;
                    } else if (g.has_prefix ("Link ")) {
                        d.links[kf.get_string (g, "cell")] = new DataTypeLink (kf.get_string (g, "source"), kf.get_string (g, "key-column"), kf.get_string (g, "key"));
                    } else if (g.has_prefix ("Query ")) {
                        var q = new QueryDef (kf.get_string (g, "name"));
                        q.source_kind = kf.get_string (g, "source");
                        q.location = kf.get_string (g, "location");
                        q.delimiter = kf.get_string (g, "delimiter");
                        q.sql = kf.get_string (g, "sql");
                        q.dest_sheet = kf.get_string (g, "dest-sheet");
                        q.dest_row = kf.get_integer (g, "dest-row");
                        q.dest_col = kf.get_integer (g, "dest-col");
                        q.load = kf.get_boolean (g, "load");
                        q.as_table = kf.get_boolean (g, "as-table");
                        q.table_name = kf.get_string (g, "table");
                        q.last_area = area_parse (book, kf.get_string (g, "output"));
                        q.last_refresh = kf.get_string (g, "refreshed");
                        int ns = kf.get_integer (g, "steps");
                        for (int j = 0; j < ns; j++) {
                            var st = new QueryStep (kf.get_string (g, "step.%d.kind".printf (j)));
                            foreach (string pair in kf.get_string_list (g, "step.%d.args".printf (j))) {
                                int eq = pair.index_of ("=");
                                if (eq > 0) st.args[pair.substring (0, eq)] = pair.substring (eq + 1);
                            }
                            q.steps.add (st);
                        }
                        d.queries.add (q);
                    }
                } catch (Error e) {
                }
            }
        }

        public static void write_xlsx (XlsxWriter w) {
            if (w.book.analysis.is_empty ()) return;
            PivotXlsx.write (w);
            string text = serialize (w.book);
            w.add_text_part (XLSX_PART, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<singularityAnalysis xmlns=\"urn:dev.sinty.spreadsheet:analysis\">" + XlsxWriter.esc (text) + "</singularityAnalysis>", null);
        }

        public static void read_xlsx (Xlsx x, Gee.HashMap<string, string> wb_rels) {
            try {
                if (x.zip.has (XLSX_PART) && !ignore_store) {
                    var doc = Xlsx.parse (x.zip.read_text (XLSX_PART));
                    if (doc != null) {
                        string text = doc->get_root_element ()->get_content () ?? "";
                        delete doc;
                        deserialize (x.book, text);
                    }
                }
                if (x.book.analysis.pivots.size == 0 || ignore_store) ExcelPivots.read (x, wb_rels);
                if (x.book.analysis.data_tables.size == 0 || ignore_store) PivotXlsx.read_data_tables (x, wb_rels);
            } catch (Error e) {
            }
        }

        public static void write_ods (OdsOut o) {
            var d = o.book.analysis;
            if (d.is_empty ()) return;
            o.add_file (ODS_PART, new Bytes (serialize (o.book).data), "text/plain");
            if (d.pivots.size > 0) o.after_tables.append (OdsPivots.write (o.book));
        }

        public static void read_ods (OdsIn inp) {
            try {
                if (inp.zip != null && inp.zip.has (ODS_PART) && !ignore_store) {
                    string? text = inp.zip.read_text (ODS_PART);
                    if (text != null) deserialize (inp.book, text);
                }
            } catch (Error e) {
            }
            if (inp.book.analysis.pivots.size == 0 || ignore_store) OdsPivots.read (inp);
        }
    }

    public class ExcelPivots {

        private static string show_as (PivotShow s) {
            switch (s) {
                case PivotShow.PERCENT_TOTAL: return "percentOfTotal";
                case PivotShow.PERCENT_ROW: return "percentOfRow";
                case PivotShow.PERCENT_COL: return "percentOfCol";
                case PivotShow.RUNNING_TOTAL: return "runTotal";
                case PivotShow.DIFFERENCE: return "difference";
                case PivotShow.PERCENT_DIFFERENCE: return "percentDiff";
                default: return "normal";
            }
        }

        private static PivotShow show_from (string s) {
            switch (s) {
                case "percentOfTotal": return PivotShow.PERCENT_TOTAL;
                case "percentOfRow": return PivotShow.PERCENT_ROW;
                case "percentOfCol": return PivotShow.PERCENT_COL;
                case "runTotal": return PivotShow.RUNNING_TOTAL;
                case "difference": return PivotShow.DIFFERENCE;
                case "percentDiff": return PivotShow.PERCENT_DIFFERENCE;
                default: return PivotShow.NORMAL;
            }
        }

        private static Gee.HashMap<string, string> rels_of (ZipReader zip, string path) throws Error {
            var map = new Gee.HashMap<string, string> ();
            string dir = Path.get_dirname (path);
            string rel = dir + "/_rels/" + Path.get_basename (path) + ".rels";
            if (!zip.has (rel)) return map;
            var doc = Xlsx.parse (zip.read_text (rel));
            if (doc == null) return map;
            for (Xml.Node* c = doc->get_root_element ()->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                string target = Xlsx.attr (c, "Target");
                string full = target.has_prefix ("/") ? target.substring (1) : normalize (dir + "/" + target);
                map[Xlsx.attr (c, "Type")] = full;
                map[Xlsx.attr (c, "Id")] = full;
            }
            delete doc;
            return map;
        }

        private static string normalize (string p) {
            var stack = new Gee.ArrayList<string> ();
            foreach (string part in p.split ("/")) {
                if (part == "" || part == ".") continue;
                if (part == "..") {
                    if (stack.size > 0) stack.remove_at (stack.size - 1);
                    continue;
                }
                stack.add (part);
            }
            return string.joinv ("/", stack.to_array ());
        }

        public static void read (Xlsx x, Gee.HashMap<string, string> wb_rels) throws Error {
            var wdoc = Xlsx.parse (x.zip.read_text ("xl/workbook.xml"));
            if (wdoc == null) return;
            var sheets_node = Xlsx.child (wdoc->get_root_element (), "sheets");
            var paths = new Gee.ArrayList<string> ();
            for (Xml.Node* s = sheets_node != null ? sheets_node->children : null; s != null; s = s->next) {
                if (s->type != Xml.ElementType.ELEMENT_NODE) continue;
                string rid = s->get_ns_prop ("id", "http://schemas.openxmlformats.org/officeDocument/2006/relationships") ?? "";
                paths.add (wb_rels.has_key (rid) ? wb_rels[rid] : "");
            }
            delete wdoc;
            for (int i = 0; i < paths.size && i < x.book.sheets.size; i++) {
                if (paths[i] == "") continue;
                string rel = Path.get_dirname (paths[i]) + "/_rels/" + Path.get_basename (paths[i]) + ".rels";
                if (!x.zip.has (rel)) continue;
                var rdoc = Xlsx.parse (x.zip.read_text (rel));
                if (rdoc == null) continue;
                for (Xml.Node* c = rdoc->get_root_element ()->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                    if (!Xlsx.attr (c, "Type").has_suffix ("/pivotTable")) continue;
                    string target = normalize (Path.get_dirname (paths[i]) + "/" + Xlsx.attr (c, "Target"));
                    read_pivot (x, x.book.sheets[i], target);
                }
                delete rdoc;
            }
        }

        private static void read_pivot (Xlsx x, Sheet target, string path) throws Error {
            var doc = Xlsx.parse (x.zip.read_text (path));
            if (doc == null) return;
            var root = doc->get_root_element ();
            var loc = Xlsx.child (root, "location");
            var area = Area.parse (Xlsx.attr (loc, "ref"), target);
            var rels = rels_of (x.zip, path);
            string cache_path = "";
            foreach (var e in rels.entries) if (e.key.has_suffix ("/pivotCacheDefinition")) cache_path = e.value;
            if (area == null || cache_path == "" || !x.zip.has (cache_path)) {
                delete doc;
                return;
            }
            var cdoc = Xlsx.parse (x.zip.read_text (cache_path));
            var croot = cdoc->get_root_element ();
            var ws = Xlsx.child (Xlsx.child (croot, "cacheSource"), "worksheetSource");
            var names = new Gee.ArrayList<string> ();
            var cf = Xlsx.child (croot, "cacheFields");
            var shared = new Gee.ArrayList<Gee.ArrayList<Value>> ();
            var group_base = new Gee.HashMap<int, int> ();
            var group_kind = new Gee.HashMap<int, PivotGroup> ();
            var group_items = new Gee.HashMap<int, Gee.ArrayList<string>> ();
            var group_start = new Gee.HashMap<int, double?> ();
            var group_end = new Gee.HashMap<int, double?> ();
            var group_size = new Gee.HashMap<int, double?> ();
            for (Xml.Node* f = cf != null ? cf->children : null; f != null; f = f->next) {
                if (f->type != Xml.ElementType.ELEMENT_NODE) continue;
                names.add (Xlsx.attr (f, "name"));
                var list = new Gee.ArrayList<Value> ();
                var si = Xlsx.child (f, "sharedItems");
                for (Xml.Node* it = si != null ? si->children : null; it != null; it = it->next) {
                    if (it->type != Xml.ElementType.ELEMENT_NODE) continue;
                    string v = Xlsx.attr (it, "v");
                    switch (it->name) {
                        case "n": list.add (Value.num (double.parse (v))); break;
                        case "b": list.add (Value.boolean (v == "1" || v == "true")); break;
                        case "m": list.add (Value.empty ()); break;
                        case "d":
                            int y = int.parse (v.substring (0, 4)), mo = int.parse (v.substring (5, 2)), dd = int.parse (v.substring (8, 2));
                            list.add (Value.num (DateSerial.from_ymd (y, mo, dd)));
                            break;
                        default: list.add (Value.str (v)); break;
                    }
                }
                shared.add (list);
                int ci = names.size - 1;
                var fg = Xlsx.child (f, "fieldGroup");
                var rp = Xlsx.child (fg, "rangePr");
                if (fg != null) {
                    int base_col = int.parse (Xlsx.attr (fg, "base", ci.to_string ()));
                    group_base[ci] = base_col;
                    var gi = new Gee.ArrayList<string> ();
                    var gnode = Xlsx.child (fg, "groupItems");
                    for (Xml.Node* it = gnode != null ? gnode->children : null; it != null; it = it->next) {
                        if (it->type == Xml.ElementType.ELEMENT_NODE) gi.add (Xlsx.attr (it, "v"));
                    }
                    group_items[ci] = gi;
                    if (rp != null) {
                        var g = PivotXlsx.group_from (Xlsx.attr (rp, "groupBy", "range"));
                        group_kind[ci] = g;
                        if (g == PivotGroup.INTERVAL) {
                            group_start[ci] = double.parse (Xlsx.attr (rp, "startNum", "0"));
                            group_size[ci] = double.parse (Xlsx.attr (rp, "groupInterval", "1"));
                        } else {
                            group_start[ci] = PivotXlsx.from_iso (Xlsx.attr (rp, "startDate"));
                            group_end[ci] = PivotXlsx.from_iso (Xlsx.attr (rp, "endDate"));
                        }
                    }
                }
            }
            var p = new PivotTable (Xlsx.attr (root, "name", "PivotTable1"), target, area.r1, area.c1);
            if (ws != null) {
                string tname = Xlsx.attr (ws, "name");
                string sname = Xlsx.attr (ws, "sheet");
                var src_sheet = sname != "" ? x.book.find_sheet (sname) : null;
                if (tname != "" && src_sheet == null) {
                    p.source_table = tname;
                } else if (src_sheet != null) {
                    p.source = Area.parse (Xlsx.attr (ws, "ref").replace ("$", ""), src_sheet);
                    p.source_sheet = src_sheet;
                }
            }
            delete cdoc;
            p.row_grand = Xlsx.attr (root, "rowGrandTotals", "1") != "0";
            p.col_grand = Xlsx.attr (root, "colGrandTotals", "1") != "0";
            var fields_node = Xlsx.child (root, "pivotFields");
            var hidden = new Gee.HashMap<int, Gee.HashSet<int>> ();
            var descending = new Gee.HashSet<int> ();
            int idx = 0;
            for (Xml.Node* f = fields_node != null ? fields_node->children : null; f != null; f = f->next) {
                if (f->type != Xml.ElementType.ELEMENT_NODE) continue;
                var items = Xlsx.child (f, "items");
                for (Xml.Node* it = items != null ? items->children : null; it != null; it = it->next) {
                    if (it->type != Xml.ElementType.ELEMENT_NODE) continue;
                    if (Xlsx.attr (it, "h") == "1") {
                        if (!hidden.has_key (idx)) hidden[idx] = new Gee.HashSet<int> ();
                        hidden[idx].add (int.parse (Xlsx.attr (it, "x")));
                    }
                }
                if (Xlsx.attr (f, "defaultSubtotal", "1") == "0") p.subtotals = false;
                if (Xlsx.attr (f, "sortType") == "descending") descending.add (idx);
                idx++;
            }
            foreach (string axis in new string[] { "rowFields", "colFields", "pageFields" }) {
                var node = Xlsx.child (root, axis);
                for (Xml.Node* f = node != null ? node->children : null; f != null; f = f->next) {
                    if (f->type != Xml.ElementType.ELEMENT_NODE) continue;
                    int fi = int.parse (Xlsx.attr (f, axis == "pageFields" ? "fld" : "x"));
                    if (fi < 0 || fi >= names.size) continue;
                    int src_col = group_base.has_key (fi) ? group_base[fi] : fi;
                    var pf = new PivotField (src_col, names[fi]);
                    if (group_kind.has_key (fi)) {
                        pf.group = group_kind[fi];
                        if (pf.group == PivotGroup.INTERVAL) {
                            pf.interval_start = group_start[fi];
                            pf.interval_size = group_size[fi];
                        }
                        if (hidden.has_key (fi)) {
                            string[] labels;
                            if (pf.group == PivotGroup.INTERVAL) {
                                labels = group_items[fi].to_array ();
                            } else {
                                string[] ex;
                                PivotXlsx.date_group_items (pf.group, group_start[fi], group_end[fi], out ex, out labels);
                            }
                            foreach (int hx in hidden[fi]) if (hx >= 0 && hx < labels.length) pf.hidden.add (labels[hx]);
                        }
                    } else if (hidden.has_key (fi) && fi < shared.size) {
                        foreach (int hx in hidden[fi]) if (hx >= 0 && hx < shared[fi].size) pf.hidden.add (PivotTable.item_of (pf, shared[fi][hx], x.book).label);
                    }
                    if (descending.contains (fi)) pf.descending = true;
                    if (axis == "rowFields") p.rows.add (pf);
                    else if (axis == "colFields") p.cols.add (pf);
                    else p.filters.add (pf);
                }
            }
            var data = Xlsx.child (root, "dataFields");
            for (Xml.Node* f = data != null ? data->children : null; f != null; f = f->next) {
                if (f->type != Xml.ElementType.ELEMENT_NODE) continue;
                int fi = int.parse (Xlsx.attr (f, "fld"));
                if (fi < 0 || fi >= names.size) continue;
                var pv = new PivotValue (fi, names[fi], PivotAgg.from_key (Xlsx.attr (f, "subtotal", "sum")));
                pv.show = show_from (Xlsx.attr (f, "showDataAs", "normal"));
                p.values.add (pv);
            }
            p.last_output = area;
            target.book.analysis.pivots.add (p);
            delete doc;
        }
    }

    public class OdsPivots {
        private static string addr (Area a) {
            string q = "'" + a.sheet.name.replace ("'", "''") + "'";
            return "%s.%s:%s.%s".printf (q, Address.cell (a.r1, a.c1, true, true), q, Address.cell (a.r2, a.c2, true, true));
        }

        private static string fn (PivotAgg a) {
            switch (a) {
                case PivotAgg.COUNT: return "count";
                case PivotAgg.COUNT_NUMS: return "countnums";
                case PivotAgg.AVERAGE: return "average";
                case PivotAgg.MAX: return "max";
                case PivotAgg.MIN: return "min";
                case PivotAgg.PRODUCT: return "product";
                case PivotAgg.STDEV: return "stdev";
                case PivotAgg.STDEVP: return "stdevp";
                case PivotAgg.VAR: return "var";
                case PivotAgg.VARP: return "varp";
                default: return "sum";
            }
        }

        private static PivotAgg agg_of (string f) {
            string s = f.down ();
            if (s.has_prefix ("net:")) s = s.substring (4);
            switch (s) {
                case "count": return PivotAgg.COUNT;
                case "countnums": return PivotAgg.COUNT_NUMS;
                case "average": return PivotAgg.AVERAGE;
                case "max": return PivotAgg.MAX;
                case "min": return PivotAgg.MIN;
                case "product": return PivotAgg.PRODUCT;
                case "stdev": return PivotAgg.STDEV;
                case "stdevp": return PivotAgg.STDEVP;
                case "var": return PivotAgg.VAR;
                case "varp": return PivotAgg.VARP;
                default: return PivotAgg.SUM;
            }
        }

        public static string write (Workbook book) {
            var sb = new StringBuilder ("<table:data-pilot-tables>");
            foreach (var p in book.analysis.pivots) {
                var src = p.source_area (book);
                if (src == null) continue;
                var out_area = p.last_output ?? new Area.cell (p.target_sheet, p.target_row, p.target_col);
                string grand = p.row_grand && p.col_grand ? "both" : p.row_grand ? "column" : p.col_grand ? "row" : "none";
                sb.append ("<table:data-pilot-table table:name=\"%s\" table:target-range-address=\"%s\" table:grand-total=\"%s\">".printf (XlsxWriter.esc (p.name), XlsxWriter.esc (addr (out_area)), grand));
                sb.append ("<table:source-cell-range table:cell-range-address=\"%s\"/>".printf (XlsxWriter.esc (addr (src))));
                var headers = p.headers (book);
                string[] orient = { "row", "column", "page" };
                Gee.List<PivotField>[] lists = { p.rows, p.cols, p.filters };
                var finest = new Gee.HashMap<int, PivotField> ();
                for (int k = 0; k < 3; k++) {
                    foreach (var f in lists[k]) {
                        if (PivotXlsx.granularity (f.group) < 0) continue;
                        if (!finest.has_key (f.source_col) || PivotXlsx.granularity (f.group) < PivotXlsx.granularity (finest[f.source_col].group)) finest[f.source_col] = f;
                    }
                }
                for (int k = 0; k < 3; k++) {
                    foreach (var f in lists[k]) {
                        string header = f.source_col < headers.length ? headers[f.source_col] : f.name;
                        string name = header;
                        string groups = "";
                        if (f.group == PivotGroup.INTERVAL) {
                            groups = "<table:data-pilot-groups table:is-group-field=\"true\" table:start=\"%s\" table:end=\"auto\" table:step=\"%s\"/>".printf (Value.format_number_general_full (f.interval_start), Value.format_number_general_full (f.interval_size));
                        } else if (PivotXlsx.granularity (f.group) >= 0) {
                            bool is_base = finest[f.source_col] == f;
                            if (!is_base) name = f.name != header ? f.name : f.group.label ();
                            groups = "<table:data-pilot-groups table:is-group-field=\"true\"%s table:grouped-by=\"%s\" table:start=\"auto\" table:end=\"auto\" table:step=\"0\"/>".printf (
                                is_base ? "" : " table:source-field-name=\"%s\"".printf (XlsxWriter.esc (header)), PivotXlsx.group_by (f.group));
                        }
                        sb.append ("<table:data-pilot-field table:source-field-name=\"%s\" table:orientation=\"%s\">".printf (XlsxWriter.esc (name), orient[k]));
                        sb.append ("<table:data-pilot-level table:show-empty=\"false\">");
                        if (p.subtotals && k < 2) sb.append ("<table:data-pilot-subtotals><table:data-pilot-subtotal table:function=\"auto\"/></table:data-pilot-subtotals>");
                        if (f.hidden.size > 0 && f.group == PivotGroup.NONE) {
                            sb.append ("<table:data-pilot-members>");
                            foreach (var h in f.hidden) sb.append ("<table:data-pilot-member table:name=\"%s\" table:display=\"false\"/>".printf (XlsxWriter.esc (h)));
                            sb.append ("</table:data-pilot-members>");
                        }
                        sb.append ("</table:data-pilot-level>" + groups + "</table:data-pilot-field>");
                    }
                }
                foreach (var v in p.values) {
                    string name = v.source_col < headers.length ? headers[v.source_col] : v.name;
                    sb.append ("<table:data-pilot-field table:source-field-name=\"%s\" table:orientation=\"data\" table:function=\"%s\"/>".printf (XlsxWriter.esc (name), fn (v.agg)));
                }
                sb.append ("</table:data-pilot-table>");
            }
            sb.append ("</table:data-pilot-tables>");
            return sb.str;
        }

        private static Area? parse_addr (Workbook book, string text) {
            string t = text.strip ();
            int colon = -1;
            bool q = false;
            for (int i = 0; i < t.length; i++) {
                if (t[i] == '\'') q = !q;
                else if (t[i] == ':' && !q) {
                    colon = i;
                    break;
                }
            }
            string left = colon >= 0 ? t.substring (0, colon) : t;
            string right = colon >= 0 ? t.substring (colon + 1) : t;
            int dot = left.last_index_of (".");
            if (dot < 0) return null;
            string sn = left.substring (0, dot).replace ("$", "");
            if (sn.has_prefix ("'")) sn = sn.substring (1, sn.length - 2).replace ("''", "'");
            var s = book.find_sheet (sn);
            if (s == null) return null;
            string c1 = left.substring (dot + 1).replace ("$", "");
            int rdot = right.last_index_of (".");
            string c2 = (rdot >= 0 ? right.substring (rdot + 1) : right).replace ("$", "");
            return Area.parse (c1 + ":" + c2, s);
        }

        private static Xml.Node* find (Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == name) return c;
                var d = find (c, name);
                if (d != null) return d;
            }
            return null;
        }

        private static string tattr (Xml.Node* n, string name) {
            return n->get_ns_prop (name, "urn:oasis:names:tc:opendocument:xmlns:table:1.0") ?? "";
        }

        public static void read (OdsIn inp) {
            var tables = find (inp.content, "data-pilot-tables");
            if (tables == null) return;
            var book = inp.book;
            for (Xml.Node* t = tables->children; t != null; t = t->next) {
                if (t->type != Xml.ElementType.ELEMENT_NODE || t->name != "data-pilot-table") continue;
                var target = parse_addr (book, tattr (t, "target-range-address"));
                if (target == null) continue;
                var p = new PivotTable (tattr (t, "name"), target.sheet, target.r1, target.c1);
                string grand = tattr (t, "grand-total");
                if (grand == "none") p.row_grand = p.col_grand = false;
                else if (grand == "row") p.row_grand = false;
                else if (grand == "column") p.col_grand = false;
                for (Xml.Node* c = t->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                    if (c->name == "source-cell-range") {
                        p.source = parse_addr (book, tattr (c, "cell-range-address"));
                        if (p.source != null) p.source_sheet = p.source.sheet;
                    }
                }
                if (p.source == null) continue;
                var headers = p.headers (book);
                bool any_subtotals = false;
                for (Xml.Node* c = t->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "data-pilot-field") continue;
                    if (tattr (c, "is-data-layout-field") == "true") continue;
                    string name = tattr (c, "source-field-name");
                    Xml.Node* groups = null;
                    for (Xml.Node* gch = c->children; gch != null; gch = gch->next) if (gch->type == Xml.ElementType.ELEMENT_NODE && gch->name == "data-pilot-groups") groups = gch;
                    string lookup = groups != null && tattr (groups, "source-field-name") != "" ? tattr (groups, "source-field-name") : name;
                    int col = -1;
                    for (int i = 0; i < headers.length; i++) if (headers[i] == lookup) col = i;
                    if (col < 0) continue;
                    string o = tattr (c, "orientation");
                    if (o == "data") {
                        p.values.add (new PivotValue (col, name, agg_of (tattr (c, "function"))));
                        continue;
                    }
                    var f = new PivotField (col, name);
                    if (groups != null) {
                        string by = tattr (groups, "grouped-by");
                        if (by == "years" || by == "quarters" || by == "months" || by == "days") {
                            f.group = PivotXlsx.group_from (by);
                        } else if (by == "") {
                            double step = double.parse (tattr (groups, "step"));
                            if (step > 0) {
                                f.group = PivotGroup.INTERVAL;
                                f.interval_size = step;
                                string st = tattr (groups, "start");
                                if (st != "" && st != "auto") {
                                    f.interval_start = double.parse (st);
                                } else {
                                    var items = p.field_items (book, col);
                                    f.interval_start = items.size > 0 && items[0].numeric ? items[0].sort_num : 0;
                                }
                            }
                        }
                    }
                    var members = find (c, "data-pilot-members");
                    for (Xml.Node* m = members != null ? members->children : null; m != null; m = m->next) {
                        if (m->type == Xml.ElementType.ELEMENT_NODE && tattr (m, "display") == "false" && f.group == PivotGroup.NONE) f.hidden.add (tattr (m, "name") == "" ? _("(blank)") : tattr (m, "name"));
                    }
                    if (find (c, "data-pilot-subtotals") != null) any_subtotals = true;
                    string selected = tattr (c, "selected-page");
                    if (o == "page" && selected != "") {
                        foreach (var it in p.field_items (book, col, f.group, f.interval_start, f.interval_size)) if (it.label != selected) f.hidden.add (it.label);
                    }
                    if (o == "row") p.rows.add (f);
                    else if (o == "column") p.cols.add (f);
                    else if (o == "page") p.filters.add (f);
                }
                p.subtotals = any_subtotals;
                p.last_output = target;
                book.analysis.pivots.add (p);
            }
        }
    }
}
