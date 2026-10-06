namespace Singularity.Apps.Spreadsheet {

    public class EditOds {
        public const string SHA256 = "http://www.w3.org/2000/09/xmldsig#sha256";
        public const string NS_LOEXT = "urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0";

        private static string key_attrs (PasswordHash p) {
            if (p.odf == "") return "";
            return " table:protection-key=\"%s\" table:protection-key-digest-algorithm=\"%s\"".printf (Ods.esc (p.odf), SHA256);
        }

        private static PasswordHash read_key (Xml.Node* n) {
            var p = new PasswordHash ();
            string key = Ods.attr (n, "protection-key", Ods.NS_TABLE);
            if (key == "") return p;
            string alg = Ods.attr (n, "protection-key-digest-algorithm", Ods.NS_TABLE);
            if (alg == "") alg = "http://www.w3.org/2000/09/xmldsig#sha1";
            p.algorithm = "odf:" + alg;
            p.hash = key;
            p.odf = alg == SHA256 ? key : "";
            return p;
        }

        public static string spreadsheet_attrs (Workbook book) {
            var p = book.protection;
            if (p == null || !p.structure) return "";
            return " table:structure-protected=\"true\"" + key_attrs (p.password);
        }

        private static string ints (Gee.Collection<int> items) {
            string[] parts = {};
            foreach (int i in items) parts += i.to_string ();
            return string.joinv (",", parts);
        }

        private static void parse_ints (string t, Gee.Collection<int> into) {
            foreach (string p in t.split (",")) if (p.strip () != "") into.add (int.parse (p));
        }

        public static string encode_views (Sheet s) {
            string[] entries = {};
            foreach (var v in s.views) {
                string f = v.filter != null ? Address.cell (v.filter.area.r1, v.filter.area.c1) + ":" + Address.cell (v.filter.area.r2, v.filter.area.c2) : "";
                entries += "name=%s&zoom=%s&fr=%d&fc=%d&row=%d&col=%d&hr=%s&hc=%s&rb=%s&filter=%s".printf (
                    Uri.escape_string (v.name, null, true), Value.format_number_general_full (v.zoom), v.freeze_rows, v.freeze_cols, v.row, v.col,
                    ints (v.hidden_rows), ints (v.hidden_cols), ints (v.row_breaks), Uri.escape_string (f, null, true));
            }
            return string.joinv ("|", entries);
        }

        public static void read_views (Sheet sheet, Gee.HashMap<string, string> values) {
            string? lists = values["SsCustomLists"];
            if (lists != null && lists != "") {
                sheet.book.custom_lists.clear ();
                CustomLists.decode (lists, sheet.book.custom_lists);
            }
            string? t = values["SsCustomViews"];
            if (t == null || t == "") return;
            foreach (string entry in t.split ("|")) {
                var map = new Gee.HashMap<string, string> ();
                foreach (string kv in entry.split ("&")) {
                    int eq = kv.index_of_char ('=');
                    if (eq > 0) map[kv.substring (0, eq)] = Uri.unescape_string (kv.substring (eq + 1)) ?? "";
                }
                if (!map.has_key ("name")) continue;
                var v = new CustomView (map["name"]);
                v.zoom = double.parse (map["zoom"] ?? "1");
                v.freeze_rows = int.parse (map["fr"] ?? "0");
                v.freeze_cols = int.parse (map["fc"] ?? "0");
                v.row = int.parse (map["row"] ?? "0");
                v.col = int.parse (map["col"] ?? "0");
                parse_ints (map["hr"] ?? "", v.hidden_rows);
                parse_ints (map["hc"] ?? "", v.hidden_cols);
                parse_ints (map["rb"] ?? "", v.row_breaks);
                string f = map["filter"] ?? "";
                if (f != "") {
                    var ar = Area.parse (f, sheet);
                    if (ar != null) v.filter = new Filter (ar);
                }
                sheet.views.add (v);
            }
        }

        private static string enc_rule (int col, FilterRule r) {
            return "col=%d&kind=%d&op1=%s&v1=%s&op2=%s&v2=%s&and=%d&top=%s&pct=%d&bot=%d&dyn=%s&color=%s&iset=%s&icon=%d&dates=%s&blanks=%d".printf (
                col, (int) r.kind, r.op1, Uri.escape_string (r.v1, null, true), r.op2, Uri.escape_string (r.v2, null, true), (int) r.and_join,
                Value.format_number_general_full (r.top), (int) r.percent, (int) r.bottom, r.dyn_type, Uri.escape_string (r.color, null, true),
                r.icon_set, r.icon, Uri.escape_string (string.joinv (",", r.dates.to_array ()), null, true), (int) r.blanks);
        }

        private static Gee.HashMap<string, string> dec (string entry) {
            var map = new Gee.HashMap<string, string> ();
            foreach (string kv in entry.split ("&")) {
                int eq = kv.index_of_char ('=');
                if (eq > 0) map[kv.substring (0, eq)] = Uri.unescape_string (kv.substring (eq + 1)) ?? "";
            }
            return map;
        }

        private static string of_op (string op) {
            switch (op) {
                case "notequal": return "!=";
                case "greater": return ">";
                case "less": return "<";
                case "greaterequal": return ">=";
                case "lessequal": return "<=";
                case "begins": return "begins with";
                case "ends": return "ends with";
                case "contains": return "contains";
                case "notcontains": return "does not contain";
                default: return "=";
            }
        }

        public static string filter_attrs (Sheet s) {
            var sb = new StringBuilder ();
            var f = s.filter;
            if (f != null && f.rules.size > 0) {
                string[] parts = {};
                foreach (var e in f.rules.entries) parts += enc_rule (e.key, e.value);
                sb.append (" ss:filter-rules=\"%s\"".printf (Ods.esc (string.joinv ("|", parts))));
            }
            if (s.sort_state != null) {
                var sp = s.sort_state;
                string[] parts = {};
                foreach (var lv in sp.levels) {
                    parts += "idx=%d&asc=%d&by=%d&color=%s&iset=%s&icon=%d&list=%s".printf (lv.index, (int) lv.ascending, (int) lv.by,
                        Uri.escape_string (lv.color, null, true), lv.icon_set, lv.icon, Uri.escape_string (lv.custom_list, null, true));
                }
                sb.append (" ss:sort=\"%s\" ss:sort-range=\"%s\" ss:sort-flags=\"%d,%d,%d\"".printf (Ods.esc (string.joinv ("|", parts)),
                    Address.cell (sp.area.r1, sp.area.c1) + ":" + Address.cell (sp.area.r2, sp.area.c2), (int) sp.header, (int) sp.columns, (int) sp.case_sensitive));
            }
            return sb.str;
        }

        public static bool ignore_own_rules;

        private static string range_xml (int field, double from, double to) {
            return "<table:filter-and><table:filter-condition table:field-number=\"%d\" table:operator=\"&gt;=\" table:value=\"%s\" table:data-type=\"number\"/><table:filter-condition table:field-number=\"%d\" table:operator=\"&lt;\" table:value=\"%s\" table:data-type=\"number\"/></table:filter-and>".printf (
                field, Value.format_number_general_full (from), field, Value.format_number_general_full (to));
        }

        private static bool key_range (string key, out double from, out double to) {
            from = to = 0;
            var p = key.split ("-");
            int y = int.parse (p[0]);
            if (y <= 0) return false;
            if (p.length == 1) {
                from = DateSerial.from_ymd (y, 1, 1);
                to = DateSerial.from_ymd (y + 1, 1, 1);
            } else if (p.length == 2) {
                int m = int.parse (p[1]);
                from = DateSerial.from_ymd (y, m, 1);
                to = DateSerial.from_ymd (y, m + 1, 1);
            } else {
                from = DateSerial.from_ymd (y, int.parse (p[1]), int.parse (p[2]));
                to = from + 1;
            }
            return true;
        }

        private static string range_key (double from, double to) {
            int y, m, d, y2, m2, d2;
            DateSerial.to_ymd (from, out y, out m, out d);
            DateSerial.to_ymd (to, out y2, out m2, out d2);
            if (to - from == 1) return "%04d-%02d-%02d".printf (y, m, d);
            if (d == 1 && d2 == 1 && m == 1 && m2 == 1 && y2 == y + 1) return "%04d".printf (y);
            if (d == 1 && d2 == 1 && ((m2 == m + 1 && y2 == y) || (m == 12 && m2 == 1 && y2 == y + 1))) return "%04d-%02d".printf (y, m);
            return "";
        }

        public static string filter_children (Sheet s) {
            var sb = new StringBuilder ();
            var sp = s.sort_state;
            var f = s.filter;
            if (sp != null && !sp.columns) {
                var base_area = f != null ? f.area : sp.area;
                var sort = new StringBuilder ();
                foreach (var lv in sp.levels) {
                    if (lv.by != SortBy.VALUE || lv.index < base_area.c1 || lv.index > base_area.c2) continue;
                    sort.append ("<table:sort-by table:field-number=\"%d\" table:order=\"%s\"/>".printf (lv.index - base_area.c1, lv.ascending ? "ascending" : "descending"));
                }
                if (sort.len > 0) sb.append ("<table:sort%s>%s</table:sort>".printf (sp.case_sensitive ? " table:case-sensitive=\"true\"" : "", sort.str));
            }
            if (f == null) return sb.str;
            var conds = new StringBuilder ();
            int n = 0;
            foreach (var e in f.rules.entries) {
                var r = e.value;
                int field = e.key - f.area.c1;
                if (r.kind == FilterKind.CUSTOM) {
                    string c1 = "<table:filter-condition table:field-number=\"%d\" table:operator=\"%s\" table:value=\"%s\"/>".printf (field, Ods.esc (of_op (r.op1)), Ods.esc (r.v1));
                    if (r.op2 != "") {
                        string c2 = "<table:filter-condition table:field-number=\"%d\" table:operator=\"%s\" table:value=\"%s\"/>".printf (field, Ods.esc (of_op (r.op2)), Ods.esc (r.v2));
                        conds.append (r.and_join ? "<table:filter-and>" + c1 + c2 + "</table:filter-and>" : "<table:filter-or>" + c1 + c2 + "</table:filter-or>");
                    } else {
                        conds.append (c1);
                    }
                    n++;
                } else if (r.kind == FilterKind.TOP10) {
                    string op = (r.bottom ? "bottom " : "top ") + (r.percent ? "percent" : "values");
                    conds.append ("<table:filter-condition table:field-number=\"%d\" table:operator=\"%s\" table:value=\"%s\" table:data-type=\"number\"/>".printf (field, op, Value.format_number_general_full (r.top)));
                    n++;
                } else if (r.kind == FilterKind.DYNAMIC) {
                    double from, to;
                    if (FilterEngine.dynamic_range (r.dyn_type, out from, out to)) {
                        conds.append (range_xml (field, from, to));
                        n++;
                    } else if (r.dyn_type == "aboveAverage" || r.dyn_type == "belowAverage") {
                        double sum = 0;
                        int cnt = 0;
                        for (int row = f.area.r1 + 1; row <= f.area.r2; row++) {
                            var v = s.value_at (row, e.key);
                            if (v.kind == ValueKind.NUMBER) {
                                sum += v.number;
                                cnt++;
                            }
                        }
                        if (cnt > 0) {
                            conds.append ("<table:filter-condition table:field-number=\"%d\" table:operator=\"%s\" table:value=\"%s\" table:data-type=\"number\"/>".printf (field, r.dyn_type == "aboveAverage" ? "&gt;" : "&lt;", Value.format_number_general_full (sum / cnt)));
                            n++;
                        }
                    }
                } else if (r.kind == FilterKind.VALUES && r.dates.size > 0) {
                    var ors = new StringBuilder ();
                    int k = 0;
                    foreach (string key in r.dates) {
                        double from, to;
                        if (!key_range (key, out from, out to)) continue;
                        ors.append (range_xml (field, from, to));
                        k++;
                    }
                    if (k == 1) conds.append (ors.str);
                    else if (k > 1) conds.append ("<table:filter-or>" + ors.str + "</table:filter-or>");
                    if (k > 0) n++;
                } else if (r.kind == FilterKind.CELL_COLOR || r.kind == FilterKind.FONT_COLOR) {
                    conds.append ("<table:filter-condition table:field-number=\"%d\" table:operator=\"=\" table:value=\"%s\" loext:data-type=\"%s\"/>".printf (field, Ods.esc (r.color), r.kind == FilterKind.CELL_COLOR ? "background-color" : "text-color"));
                    n++;
                }
            }
            foreach (var e in f.hidden_values.entries) {
                if (e.value.size == 0 || f.rules.has_key (e.key)) continue;
                var shown = new Gee.TreeSet<string> ();
                for (int r = f.area.r1 + 1; r <= f.area.r2; r++) {
                    string color;
                    string t = NumberFormat.format_value (s.value_at (r, e.key), s.style_at (r, e.key).number_format, out color, s.book.date1904);
                    if (!e.value.contains (t)) shown.add (t);
                }
                var items = new StringBuilder ();
                foreach (string t in shown) items.append ("<table:filter-set-item table:value=\"%s\"/>".printf (Ods.esc (t)));
                conds.append ("<table:filter-condition table:field-number=\"%d\" table:operator=\"=\" table:value=\"%s\">%s</table:filter-condition>".printf (e.key - f.area.c1, shown.size > 0 ? Ods.esc (shown.first ()) : "", items.str));
                n++;
            }
            if (n == 0) return sb.str;
            sb.append (n > 1 ? "<table:filter><table:filter-and>" + conds.str + "</table:filter-and></table:filter>" : "<table:filter>" + conds.str + "</table:filter>");
            return sb.str;
        }

        public static void read_filter (Workbook book, Sheet sheet, Xml.Node* d) {
            var f = sheet.filter;
            string rules = ignore_own_rules ? "" : (d->get_ns_prop ("filter-rules", "urn:singularity:spreadsheet") ?? "");
            if (f == null) rules = "";
            foreach (string entry in rules.split ("|")) {
                if (entry == "") continue;
                var m = dec (entry);
                var r = new FilterRule ();
                r.kind = (FilterKind) int.parse (m["kind"] ?? "0");
                r.op1 = m["op1"] ?? "";
                r.v1 = m["v1"] ?? "";
                r.op2 = m["op2"] ?? "";
                r.v2 = m["v2"] ?? "";
                r.and_join = (m["and"] ?? "1") == "1";
                r.top = double.parse (m["top"] ?? "10");
                r.percent = (m["pct"] ?? "0") == "1";
                r.bottom = (m["bot"] ?? "0") == "1";
                r.dyn_type = m["dyn"] ?? "";
                r.color = m["color"] ?? "";
                r.icon_set = m["iset"] ?? "";
                r.icon = int.parse (m["icon"] ?? "-1");
                r.blanks = (m["blanks"] ?? "1") == "1";
                foreach (string k in (m["dates"] ?? "").split (",")) if (k != "") r.dates.add (k);
                f.rules[int.parse (m["col"] ?? "0")] = r;
            }
            string sort = d->get_ns_prop ("sort", "urn:singularity:spreadsheet") ?? "";
            string srange = d->get_ns_prop ("sort-range", "urn:singularity:spreadsheet") ?? "";
            var sa = srange != "" ? Area.parse (srange, sheet) : null;
            if (sort != "" && sa != null) {
                var spec = new SortSpec (sa);
                string[] flags = (d->get_ns_prop ("sort-flags", "urn:singularity:spreadsheet") ?? "1,0,0").split (",");
                if (flags.length == 3) {
                    spec.header = flags[0] == "1";
                    spec.columns = flags[1] == "1";
                    spec.case_sensitive = flags[2] == "1";
                }
                foreach (string entry in sort.split ("|")) {
                    if (entry == "") continue;
                    var m = dec (entry);
                    var lv = new SortLevel (int.parse (m["idx"] ?? "0"), (m["asc"] ?? "1") == "1");
                    lv.by = (SortBy) int.parse (m["by"] ?? "0");
                    lv.color = m["color"] ?? "";
                    lv.icon_set = m["iset"] ?? "";
                    lv.icon = int.parse (m["icon"] ?? "-1");
                    lv.custom_list = m["list"] ?? "";
                    spec.levels.add (lv);
                }
                sheet.sort_state = spec;
            }
            if ((rules != "" && !ignore_own_rules) || f == null) return;
            f.rules.clear ();
            Xml.Node* filter = null;
            for (Xml.Node* c = d->children; c != null; c = c->next) if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == "filter") filter = c;
            if (filter == null) return;
            read_conditions (book, sheet, filter, true);
        }

        private static bool range_of (Xml.Node* and_node, out int field, out double from, out double to) {
            field = -1;
            from = to = 0;
            var conds = new Gee.ArrayList<Xml.Node*> ();
            for (Xml.Node* k = and_node->children; k != null; k = k->next) {
                if (k->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (k->name != "filter-condition") return false;
                conds.add (k);
            }
            if (conds.size != 2) return false;
            string f0 = Ods.attr (conds[0], "field-number", Ods.NS_TABLE), f1 = Ods.attr (conds[1], "field-number", Ods.NS_TABLE);
            if (f0 != f1 || Ods.attr (conds[0], "operator", Ods.NS_TABLE) != ">=" || Ods.attr (conds[1], "operator", Ods.NS_TABLE) != "<") return false;
            field = int.parse (f0);
            from = double.parse (Ods.attr (conds[0], "value", Ods.NS_TABLE));
            to = double.parse (Ods.attr (conds[1], "value", Ods.NS_TABLE));
            return true;
        }

        private static void add_date_key (Sheet sheet, int field, double from, double to) {
            var f = sheet.filter;
            int col = f.area.c1 + field;
            string key = range_key (from, to);
            if (key == "") {
                var r = new FilterRule ();
                r.kind = FilterKind.CUSTOM;
                r.op1 = "greaterequal";
                r.v1 = Value.format_number_general_full (from);
                r.op2 = "less";
                r.v2 = Value.format_number_general_full (to);
                r.and_join = true;
                f.rules[col] = r;
                return;
            }
            FilterRule r = f.rules.has_key (col) && f.rules[col].kind == FilterKind.VALUES ? f.rules[col] : new FilterRule ();
            r.dates.add (key);
            f.rules[col] = r;
        }

        private static void read_conditions (Workbook book, Sheet sheet, Xml.Node* n, bool and_join) {
            var f = sheet.filter;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                int rf = -1;
                double rfrom = 0, rto = 0;
                if (c->name == "filter-and" && range_of (c, out rf, out rfrom, out rto)) {
                    add_date_key (sheet, rf, rfrom, rto);
                    continue;
                }
                if (c->name == "filter-and" || c->name == "filter-or") {
                    var conds = new Gee.ArrayList<Xml.Node*> ();
                    bool nested = false;
                    for (Xml.Node* k = c->children; k != null; k = k->next) {
                        if (k->type != Xml.ElementType.ELEMENT_NODE) continue;
                        if (k->name == "filter-condition") conds.add (k);
                        else nested = true;
                    }
                    if (c->name == "filter-or" && conds.size == 2 && !nested && Ods.attr (conds[0], "field-number", Ods.NS_TABLE) == Ods.attr (conds[1], "field-number", Ods.NS_TABLE)) {
                        read_condition (book, sheet, conds[0], conds[1], false);
                        continue;
                    }
                    read_conditions (book, sheet, c, c->name == "filter-and");
                    continue;
                }
                if (c->name == "filter-condition") read_condition (book, sheet, c, null, and_join);
            }
        }

        private static string our_op (string op) {
            switch (op) {
                case "!=": return "notequal";
                case ">": return "greater";
                case "<": return "less";
                case ">=": return "greaterequal";
                case "<=": return "lessequal";
                case "begins with": return "begins";
                case "ends with": return "ends";
                case "contains": return "contains";
                case "does not contain": return "notcontains";
                default: return "equal";
            }
        }

        private static void read_condition (Workbook book, Sheet sheet, Xml.Node* c, Xml.Node* c2, bool and_join) {
            var f = sheet.filter;
            int col = f.area.c1 + int.parse (Ods.attr (c, "field-number", Ods.NS_TABLE));
            string op = Ods.attr (c, "operator", Ods.NS_TABLE);
            string val = Ods.attr (c, "value", Ods.NS_TABLE);
            string ltype = c->get_ns_prop ("data-type", NS_LOEXT) ?? "";
            if (ltype == "background-color" || ltype == "text-color") {
                var cr = new FilterRule ();
                cr.kind = ltype == "background-color" ? FilterKind.CELL_COLOR : FilterKind.FONT_COLOR;
                cr.color = val.down ();
                f.rules[col] = cr;
                return;
            }
            if (op.has_prefix ("top ") || op.has_prefix ("bottom ")) {
                var r = new FilterRule ();
                r.kind = FilterKind.TOP10;
                r.bottom = op.has_prefix ("bottom");
                r.percent = op.has_suffix ("percent");
                r.top = double.parse (val);
                f.rules[col] = r;
                return;
            }
            var items = new Gee.HashSet<string> ();
            for (Xml.Node* k = c->children; k != null; k = k->next) {
                if (k->type == Xml.ElementType.ELEMENT_NODE && k->name == "filter-set-item") items.add (Ods.attr (k, "value", Ods.NS_TABLE));
            }
            if (op == "=" && c2 == null && !val.contains ("*") && !val.contains ("?")) {
                if (items.size == 0) items.add (val);
                var hidden = new Gee.HashSet<string> ();
                for (int r = f.area.r1 + 1; r <= f.area.r2; r++) {
                    string color;
                    string t = NumberFormat.format_value (sheet.value_at (r, col), sheet.style_at (r, col).number_format, out color, book.date1904);
                    if (!items.contains (t)) hidden.add (t);
                }
                f.hidden_values[col] = hidden;
                return;
            }
            var rule = new FilterRule ();
            rule.kind = FilterKind.CUSTOM;
            rule.op1 = our_op (op);
            rule.v1 = val;
            if (c2 != null) {
                rule.op2 = our_op (Ods.attr (c2, "operator", Ods.NS_TABLE));
                rule.v2 = Ods.attr (c2, "value", Ods.NS_TABLE);
                rule.and_join = and_join;
            }
            f.rules[col] = rule;
        }

        public static void write (OdsOut o) {
            if (o.book.custom_lists.size > 0 && o.book.sheets.size > 0) o.put_table_setting (o.book.sheets[0], "<config:config-item config:name=\"SsCustomLists\" config:type=\"string\">%s</config:config-item>".printf (Ods.esc (CustomLists.encode (o.book.custom_lists))));
            foreach (var s in o.book.sheets) {
                if (s.views.size > 0) o.put_table_setting (s, "<config:config-item config:name=\"SsCustomViews\" config:type=\"string\">%s</config:config-item>".printf (Ods.esc (encode_views (s))));
            }
            foreach (var s in o.book.sheets) {
                var p = s.protection;
                if (p == null) continue;
                o.put_table_attr (s, " table:protected=\"true\"" + key_attrs (p.password));
                o.put_table_start (s, "<loext:table-protection%s%s%s%s/>".printf (
                    p.select_locked ? "" : " loext:select-protected-cells=\"false\"",
                    p.select_unlocked ? "" : " loext:select-unprotected-cells=\"false\"",
                    p.insert_columns ? " loext:insert-columns=\"true\"" : "",
                    p.insert_rows ? " loext:insert-rows=\"true\"" : ""));
            }
        }

        public static void read (OdsIn inp) {
            var body = Ods.child (inp.content, "body");
            var ss = Ods.child (body, "spreadsheet");
            if (ss == null) return;
            if (Ods.attr (ss, "structure-protected", Ods.NS_TABLE) == "true") {
                var bp = new BookProtection ();
                bp.structure = true;
                bp.password = read_key (ss);
                inp.book.protection = bp;
            }
        }

        public static void read_table (Sheet sheet, Xml.Node* table) {
            if (Ods.attr (table, "protected", Ods.NS_TABLE) == "true") {
                var p = new SheetProtection ();
                p.password = read_key (table);
                for (Xml.Node* c = table->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "table-protection") continue;
                    p.select_locked = c->get_ns_prop ("select-protected-cells", NS_LOEXT) != "false";
                    p.select_unlocked = c->get_ns_prop ("select-unprotected-cells", NS_LOEXT) != "false";
                    p.insert_columns = c->get_ns_prop ("insert-columns", NS_LOEXT) == "true";
                    p.insert_rows = c->get_ns_prop ("insert-rows", NS_LOEXT) == "true";
                    p.delete_columns = c->get_ns_prop ("delete-columns", NS_LOEXT) == "true";
                    p.delete_rows = c->get_ns_prop ("delete-rows", NS_LOEXT) == "true";
                }
                sheet.protection = p;
            }
            int r = 0, c = 0;
            walk (sheet, table, 0, 0, ref r, ref c);
        }

        private static void walk (Sheet sheet, Xml.Node* n, int row_level, int col_level, ref int r, ref int c) {
            for (Xml.Node* k = n->children; k != null; k = k->next) {
                if (k->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (k->name) {
                    case "table-row-group":
                        int start = r;
                        walk (sheet, k, row_level + 1, col_level, ref r, ref c);
                        if (Ods.attr (k, "display", Ods.NS_TABLE) == "false" && r > start) {
                            int summary = sheet.outline.summary_below ? r : start - 1;
                            if (summary >= 0) sheet.outline.collapsed_rows.add (summary);
                        }
                        break;
                    case "table-column-group":
                        int cstart = c;
                        walk (sheet, k, row_level, col_level + 1, ref r, ref c);
                        if (Ods.attr (k, "display", Ods.NS_TABLE) == "false" && c > cstart) {
                            int summary = sheet.outline.summary_right ? c : cstart - 1;
                            if (summary >= 0) sheet.outline.collapsed_cols.add (summary);
                        }
                        break;
                    case "table-rows":
                    case "table-header-rows":
                    case "table-columns":
                    case "table-header-columns":
                        walk (sheet, k, row_level, col_level, ref r, ref c);
                        break;
                    case "table-row":
                        int rep = int.max (1, int.parse (Ods.attr (k, "number-rows-repeated", Ods.NS_TABLE)));
                        if (row_level > 0) for (int i = 0; i < int.min (rep, 100000); i++) sheet.outline.row_levels[r + i] = int.min (row_level, MAX_OUTLINE);
                        r += rep;
                        break;
                    case "table-column":
                        int crep = int.max (1, int.parse (Ods.attr (k, "number-columns-repeated", Ods.NS_TABLE)));
                        if (col_level > 0) for (int i = 0; i < int.min (crep, 16384); i++) sheet.outline.col_levels[c + i] = int.min (col_level, MAX_OUTLINE);
                        c += crep;
                        break;
                }
            }
        }

        public static int transition (StringBuilder sb, Sheet sheet, bool rows, int current, int index) {
            int lv = index < 0 ? 0 : sheet.outline.level_of (rows, index);
            string tag = rows ? "table:table-row-group" : "table:table-column-group";
            while (current > lv) {
                sb.append ("</%s>".printf (tag));
                current--;
            }
            while (current < lv) {
                current++;
                bool collapsed = false;
                foreach (var g in sheet.outline.groups (rows)) {
                    if (g.level == current && g.start <= index && g.end >= index) collapsed = g.collapsed;
                }
                sb.append ("<%s%s>".printf (tag, collapsed ? " table:display=\"false\"" : ""));
            }
            return current;
        }

        public static bool same_level (Sheet sheet, bool rows, int a, int b) {
            return sheet.outline.level_of (rows, a) == sheet.outline.level_of (rows, b);
        }

        public static string encode_name (string n) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (n.get_next_char (ref i, out c)) {
                if (c.isalnum () && c < 0x80) sb.append_unichar (c);
                else if (c < 0x100) sb.append ("_%02x_".printf ((uint) c));
                else sb.append_unichar (c);
            }
            return sb.str;
        }

        public static string decode_name (string n) {
            var sb = new StringBuilder ();
            int i = 0;
            while (i < n.length) {
                if (n[i] == '_' && i + 3 < n.length && n[i + 3] == '_' && n[i + 1].isxdigit () && n[i + 2].isxdigit ()) {
                    sb.append_c ((char) (n[i + 1].xdigit_value () * 16 + n[i + 2].xdigit_value ()));
                    i += 4;
                    continue;
                }
                sb.append_c (n[i]);
                i++;
            }
            return sb.str;
        }

        public static string parent_style (OdsOut o, CellStyle s) {
            if (s.style_name == "") return "Default";
            string enc = encode_name (s.style_name);
            if (!o.common_styles.str.contains ("style:name=\"%s\"".printf (enc))) {
                o.common_styles.append ("<style:style style:name=\"%s\" style:display-name=\"%s\" style:family=\"table-cell\" style:parent-style-name=\"Default\"/>".printf (enc, Ods.esc (s.style_name)));
            }
            return enc;
        }

        public static void read_cell_style (CellStyle st, Xml.Node* style) {
            string parent = Ods.attr (style, "parent-style-name", Ods.NS_STYLE);
            if (parent != "" && parent != "Default") st.style_name = decode_name (parent);
            for (Xml.Node* p = style->children; p != null; p = p->next) {
                if (p->type != Xml.ElementType.ELEMENT_NODE || p->name != "table-cell-properties") continue;
                string prot = Ods.attr (p, "cell-protect", Ods.NS_STYLE);
                if (prot != "") {
                    st.locked = prot.contains ("protected");
                    st.hidden = prot.contains ("hidden");
                }
                string rot = Ods.attr (p, "rotation-angle", Ods.NS_STYLE);
                if (rot != "") {
                    int a = (int) double.parse (rot.replace ("deg", ""));
                    a = ((a % 360) + 360) % 360;
                    st.rotation = a <= 90 ? a : (a >= 270 ? a - 360 : 0);
                }
                if (Ods.attr (p, "direction", Ods.NS_STYLE) == "ttb") st.rotation = 255;
                if (Ods.attr (p, "shrink-to-fit", Ods.NS_STYLE) == "true") st.shrink = true;
            }
        }

        public static string cell_properties (CellStyle st) {
            var sb = new StringBuilder ();
            if (!st.locked || st.hidden) {
                string v = !st.locked ? (st.hidden ? "formula-hidden" : "none") : "protected formula-hidden";
                sb.append (" style:cell-protect=\"%s\"".printf (v));
            }
            if (st.rotation == 255) sb.append (" style:direction=\"ttb\"");
            else if (st.rotation != 0) sb.append (" style:rotation-angle=\"%d\" style:rotation-align=\"none\"".printf (st.rotation < 0 ? 360 + st.rotation : st.rotation));
            if (st.shrink) sb.append (" style:shrink-to-fit=\"true\"");
            return sb.str;
        }
    }
}
