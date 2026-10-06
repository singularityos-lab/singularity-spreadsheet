namespace Singularity.Apps.Spreadsheet {

    public errordomain QueryError {
        SOURCE,
        STEP
    }

    public class DataFrame {
        public Gee.ArrayList<string> columns = new Gee.ArrayList<string> ();
        public Gee.ArrayList<Gee.ArrayList<Value>> rows = new Gee.ArrayList<Gee.ArrayList<Value>> ();

        public int index (string name) {
            string k = name.casefold ();
            for (int i = 0; i < columns.size; i++) if (columns[i].casefold () == k) return i;
            return -1;
        }

        public int require (string name) throws QueryError {
            int i = index (name);
            if (i < 0) throw new QueryError.STEP (_("The column \"%s\" was not found.").printf (name));
            return i;
        }

        public Value at (int r, int c) {
            var row = rows[r];
            return c < row.size ? row[c] : Value.empty ();
        }

        public void pad () {
            foreach (var r in rows) while (r.size < columns.size) r.add (Value.empty ());
        }

        public static DataFrame from_strings (Gee.List<Gee.List<string>> table, bool typed) {
            var df = new DataFrame ();
            int width = 0;
            foreach (var r in table) width = int.max (width, r.size);
            for (int i = 0; i < width; i++) df.columns.add ("Column%d".printf (i + 1));
            foreach (var r in table) {
                var row = new Gee.ArrayList<Value> ();
                foreach (string s in r) row.add (typed ? QueryEngine.parse_value (s) : (s == "" ? Value.empty () : Value.str (s)));
                df.rows.add (row);
            }
            df.pad ();
            return df;
        }

        public DataFrame copy () {
            var d = new DataFrame ();
            d.columns.add_all (columns);
            foreach (var r in rows) {
                var nr = new Gee.ArrayList<Value> ();
                nr.add_all (r);
                d.rows.add (nr);
            }
            return d;
        }

        public Value[,] to_matrix (bool header) {
            int h = header ? 1 : 0;
            var m = new Value[rows.size + h, int.max (columns.size, 1)];
            for (int j = 0; j < columns.size; j++) if (header) m[0, j] = Value.str (columns[j]);
            for (int i = 0; i < rows.size; i++) for (int j = 0; j < columns.size; j++) m[i + h, j] = at (i, j);
            for (int i = 0; i < m.length[0]; i++) for (int j = 0; j < m.length[1]; j++) if (m[i, j] == null) m[i, j] = Value.empty ();
            return m;
        }
    }

    public class QueryStep {
        public string kind;
        public Gee.HashMap<string, string> args = new Gee.HashMap<string, string> ();

        public QueryStep (string kind) {
            this.kind = kind;
        }

        public QueryStep with (string key, string value) {
            args[key] = value;
            return this;
        }

        public string arg (string key, string def = "") {
            return args.has_key (key) ? args[key] : def;
        }

        public static string[] kinds () {
            return { "promote-headers", "change-type", "filter-rows", "remove-columns", "keep-columns", "rename-column", "reorder-columns", "split-column", "replace-values", "group-by", "sort", "merge", "append", "unpivot", "remove-duplicates", "keep-top", "fill-down", "trim", "remove-blank-rows", "add-index" };
        }

        public static string kind_label (string k) {
            switch (k) {
                case "promote-headers": return _("Use First Row as Headers");
                case "change-type": return _("Change Type");
                case "filter-rows": return _("Filter Rows");
                case "remove-columns": return _("Remove Columns");
                case "keep-columns": return _("Choose Columns");
                case "rename-column": return _("Rename Column");
                case "reorder-columns": return _("Reorder Columns");
                case "split-column": return _("Split Column");
                case "replace-values": return _("Replace Values");
                case "group-by": return _("Group By");
                case "sort": return _("Sort");
                case "merge": return _("Merge Queries");
                case "append": return _("Append Queries");
                case "unpivot": return _("Unpivot Columns");
                case "remove-duplicates": return _("Remove Duplicates");
                case "keep-top": return _("Keep Top Rows");
                case "fill-down": return _("Fill Down");
                case "trim": return _("Trim Text");
                case "remove-blank-rows": return _("Remove Blank Rows");
                case "add-index": return _("Add Index Column");
                default: return k;
            }
        }

        public string describe () {
            string[] parts = {};
            var keys = new Gee.ArrayList<string> ();
            keys.add_all (args.keys);
            keys.sort ();
            foreach (var k in keys) parts += "%s: %s".printf (k, args[k]);
            return string.joinv (", ", parts);
        }
    }

    public class QueryDef {
        public string name;
        public string source_kind = "csv";
        public string location = "";
        public string delimiter = "";
        public string sql = "";
        public Gee.ArrayList<QueryStep> steps = new Gee.ArrayList<QueryStep> ();
        public string dest_sheet = "";
        public int dest_row;
        public int dest_col;
        public bool load;
        public bool as_table = true;
        public string table_name = "";
        public Area? last_area;
        public string last_refresh = "";
        public string error = "";

        public QueryDef (string name) {
            this.name = name;
        }

        public static string[] source_kinds () {
            return { "csv", "tsv", "json", "web", "sqlite", "range", "query" };
        }

        public static string source_label (string k) {
            switch (k) {
                case "csv": return _("Text or CSV File");
                case "tsv": return _("Tab-Separated File");
                case "json": return _("JSON File");
                case "web": return _("From Web");
                case "sqlite": return _("SQLite Database");
                case "range": return _("From Table or Range");
                case "query": return _("From Another Query");
                default: return k;
            }
        }
    }

    public class QueryEngine {
        public static Value parse_value (string s) {
            var p = Input.parse (s);
            Value v = p.value;
            return v;
        }

        public delegate string? Fetcher (string uri) throws Error;

        public static Fetcher? fetcher = null;

        public static string fetch_text (string location) throws Error {
            string loc = location.strip ();
            if (loc.has_prefix ("http://") || loc.has_prefix ("https://")) {
                if (fetcher != null) {
                    string? t = fetcher (loc);
                    if (t != null) return t;
                }
                var session = new Soup.Session ();
                session.timeout = 30;
                var msg = new Soup.Message ("GET", loc);
                var bytes = session.send_and_read (msg, null);
                if (msg.status_code < 200 || msg.status_code >= 300) throw new QueryError.SOURCE (_("The server answered %u %s.").printf (msg.status_code, msg.reason_phrase ?? ""));
                unowned uint8[] data = bytes.get_data ();
                return to_utf8 (data);
            }
            string path = loc.has_prefix ("file://") ? File.new_for_uri (loc).get_path () : loc;
            uint8[] data;
            FileUtils.get_data (path, out data);
            return to_utf8 (data);
        }

        private static string to_utf8 (uint8[] data) {
            var copy = new uint8[data.length + 1];
            Memory.copy (copy, data, data.length);
            copy[data.length] = 0;
            string s = (string) copy;
            if (s.has_prefix ("\xef\xbb\xbf")) s = s.substring (3);
            if (s.validate ()) return s;
            try {
                return convert (s, s.length, "UTF-8", "WINDOWS-1252");
            } catch (ConvertError e) {
                return s.make_valid ();
            }
        }

        public static DataFrame parse_csv (string text, string delimiter) {
            char sep = delimiter == "" ? Csv.detect (text) : (delimiter == "\\t" || delimiter == "tab" ? '\t' : delimiter[0]);
            var raw = Csv.parse (text, sep);
            var table = new Gee.ArrayList<Gee.List<string>> ();
            foreach (var r in raw) table.add (r);
            return DataFrame.from_strings (table, true);
        }

        private static void flatten_object (Json.Object obj, string prefix, Gee.HashMap<string, Value> out_map, Gee.ArrayList<string> order) {
            foreach (string key in obj.get_members ()) {
                var n = obj.get_member (key);
                string k = prefix == "" ? key : prefix + "." + key;
                if (n.get_node_type () == Json.NodeType.OBJECT) {
                    flatten_object (n.get_object (), k, out_map, order);
                    continue;
                }
                if (!order.contains (k)) order.add (k);
                out_map[k] = json_value (n);
            }
        }

        private static Value json_value (Json.Node n) {
            switch (n.get_node_type ()) {
                case Json.NodeType.NULL: return Value.empty ();
                case Json.NodeType.ARRAY:
                    var gen = new Json.Generator ();
                    gen.set_root (n);
                    return Value.str (gen.to_data (null));
                case Json.NodeType.OBJECT:
                    var g2 = new Json.Generator ();
                    g2.set_root (n);
                    return Value.str (g2.to_data (null));
                default:
                    var t = n.get_value_type ();
                    if (t == typeof (bool)) return Value.boolean (n.get_boolean ());
                    if (t == typeof (int64) || t == typeof (double)) return Value.num (n.get_double ());
                    return Value.str (n.get_string () ?? "");
            }
        }

        private static Json.Array? find_array (Json.Node node) {
            if (node.get_node_type () == Json.NodeType.ARRAY) return node.get_array ();
            if (node.get_node_type () == Json.NodeType.OBJECT) {
                var obj = node.get_object ();
                foreach (string key in obj.get_members ()) {
                    var a = find_array (obj.get_member (key));
                    if (a != null) return a;
                }
            }
            return null;
        }

        public static DataFrame parse_json (string text) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (text);
            var root = parser.get_root ();
            var df = new DataFrame ();
            var arr = find_array (root);
            if (arr == null) {
                if (root.get_node_type () == Json.NodeType.OBJECT) {
                    var map = new Gee.HashMap<string, Value> ();
                    var order = new Gee.ArrayList<string> ();
                    flatten_object (root.get_object (), "", map, order);
                    df.columns.add ("Name");
                    df.columns.add ("Value");
                    foreach (var k in order) {
                        var r = new Gee.ArrayList<Value> ();
                        r.add (Value.str (k));
                        r.add (map[k]);
                        df.rows.add (r);
                    }
                    return df;
                }
                df.columns.add ("Value");
                var r = new Gee.ArrayList<Value> ();
                r.add (json_value (root));
                df.rows.add (r);
                return df;
            }
            var maps = new Gee.ArrayList<Gee.HashMap<string, Value>> ();
            var order = new Gee.ArrayList<string> ();
            bool arrays = false;
            int width = 0;
            foreach (var el in arr.get_elements ()) {
                var map = new Gee.HashMap<string, Value> ();
                if (el.get_node_type () == Json.NodeType.OBJECT) {
                    flatten_object (el.get_object (), "", map, order);
                } else if (el.get_node_type () == Json.NodeType.ARRAY) {
                    arrays = true;
                    var inner = el.get_array ();
                    for (uint i = 0; i < inner.get_length (); i++) map["Column%u".printf (i + 1)] = json_value (inner.get_element (i));
                    width = int.max (width, (int) inner.get_length ());
                } else {
                    if (!order.contains ("Value")) order.add ("Value");
                    map["Value"] = json_value (el);
                }
                maps.add (map);
            }
            if (arrays) for (int i = 0; i < width; i++) if (!order.contains ("Column%d".printf (i + 1))) order.add ("Column%d".printf (i + 1));
            df.columns.add_all (order);
            foreach (var map in maps) {
                var r = new Gee.ArrayList<Value> ();
                foreach (var k in order) r.add (map.has_key (k) ? map[k] : Value.empty ());
                df.rows.add (r);
            }
            return df;
        }

        private static string strip_tags (string s) {
            try {
                var re = new Regex ("<[^>]*>");
                string t = re.replace (s, -1, 0, "");
                t = t.replace ("&nbsp;", " ").replace ("&amp;", "&").replace ("&lt;", "<").replace ("&gt;", ">").replace ("&quot;", "\"").replace ("&#39;", "'");
                return t.strip ();
            } catch (RegexError e) {
                return s;
            }
        }

        public static DataFrame parse_html_table (string html, int which = 0) throws Error {
            var re_table = new Regex ("<table[^>]*>(.*?)</table>", RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL);
            var re_row = new Regex ("<tr[^>]*>(.*?)</tr>", RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL);
            var re_cell = new Regex ("<t([hd])[^>]*>(.*?)</t[hd]>", RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL);
            MatchInfo mt;
            int idx = 0;
            string? body = null;
            if (re_table.match (html, 0, out mt)) {
                do {
                    if (idx++ == which) {
                        body = mt.fetch (1);
                        break;
                    }
                } while (mt.next ());
            }
            if (body == null) throw new QueryError.SOURCE (_("No table was found on the page."));
            var table = new Gee.ArrayList<Gee.List<string>> ();
            bool header = false;
            MatchInfo mr;
            if (re_row.match (body, 0, out mr)) {
                do {
                    var row = new Gee.ArrayList<string> ();
                    MatchInfo mc;
                    string rb = mr.fetch (1);
                    bool all_th = true;
                    if (re_cell.match (rb, 0, out mc)) {
                        do {
                            if (mc.fetch (1).down () != "h") all_th = false;
                            row.add (strip_tags (mc.fetch (2)));
                        } while (mc.next ());
                    }
                    if (row.size == 0) continue;
                    if (table.size == 0 && all_th) header = true;
                    table.add (row);
                } while (mr.next ());
            }
            var df = DataFrame.from_strings (table, true);
            if (header && df.rows.size > 0) promote (df);
            return df;
        }

        public static DataFrame read_sqlite (string path, string sql) throws Error {
            Sqlite.Database db;
            int rc = Sqlite.Database.open_v2 (path, out db, Sqlite.OPEN_READONLY);
            if (rc != Sqlite.OK) throw new QueryError.SOURCE (_("The database could not be opened."));
            string q = sql.strip ();
            if (q == "") {
                Sqlite.Statement first;
                db.prepare_v2 ("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name LIMIT 1", -1, out first);
                if (first.step () != Sqlite.ROW) throw new QueryError.SOURCE (_("The database has no tables."));
                q = "SELECT * FROM \"%s\"".printf (first.column_text (0).replace ("\"", "\"\""));
            }
            Sqlite.Statement st;
            rc = db.prepare_v2 (q, -1, out st);
            if (rc != Sqlite.OK) throw new QueryError.SOURCE (db.errmsg ());
            var df = new DataFrame ();
            for (int i = 0; i < st.column_count (); i++) df.columns.add (st.column_name (i));
            while (st.step () == Sqlite.ROW) {
                var row = new Gee.ArrayList<Value> ();
                for (int i = 0; i < st.column_count (); i++) {
                    switch (st.column_type (i)) {
                        case Sqlite.INTEGER:
                        case Sqlite.FLOAT:
                            row.add (Value.num (st.column_double (i)));
                            break;
                        case Sqlite.NULL:
                            row.add (Value.empty ());
                            break;
                        default:
                            row.add (Value.str (st.column_text (i) ?? ""));
                            break;
                    }
                }
                df.rows.add (row);
            }
            return df;
        }

        public static DataFrame from_range (Workbook book, string location) throws Error {
            var t = Tables.find (book, location);
            Area? a = null;
            if (t != null) {
                a = new Area (t.sheet, t.header_row ? t.area.r1 : t.data_r1, t.area.c1, t.data_r2, t.area.c2);
            } else {
                string loc = location.strip ();
                Sheet? s = book.sheets.size > 0 ? book.sheets[0] : null;
                int bang = loc.last_index_of ("!");
                if (bang > 0) {
                    string sn = loc.substring (0, bang);
                    if (sn.has_prefix ("'")) sn = sn.substring (1, sn.length - 2).replace ("''", "'");
                    s = book.find_sheet (sn);
                    loc = loc.substring (bang + 1);
                }
                if (s != null) a = Area.parse (loc.replace ("$", ""), s);
            }
            if (a == null) throw new QueryError.SOURCE (_("The range \"%s\" is not valid.").printf (location));
            var s2 = a.sheet;
            int r2 = int.min (a.r2, s2.max_row), c2 = int.min (a.c2, s2.max_col);
            var df = new DataFrame ();
            for (int c = a.c1; c <= c2; c++) df.columns.add ("Column%d".printf (c - a.c1 + 1));
            for (int r = a.r1; r <= r2; r++) {
                var row = new Gee.ArrayList<Value> ();
                for (int c = a.c1; c <= c2; c++) row.add (s2.value_at (r, c));
                df.rows.add (row);
            }
            if (t != null && t.header_row) promote (df);
            return df;
        }

        public static void promote (DataFrame df) {
            if (df.rows.size == 0) return;
            var first = df.rows.remove_at (0);
            var used = new Gee.HashSet<string> ();
            for (int i = 0; i < df.columns.size; i++) {
                string n = i < first.size ? first[i].display ().strip () : "";
                if (n == "") n = "Column%d".printf (i + 1);
                string u = n;
                for (int k = 2; used.contains (u.casefold ()); k++) u = "%s_%d".printf (n, k);
                used.add (u.casefold ());
                df.columns[i] = u;
            }
        }

        public static DataFrame source (Workbook book, QueryDef q, Gee.HashSet<string>? visiting = null) throws Error {
            switch (q.source_kind) {
                case "csv": return parse_csv (fetch_text (q.location), q.delimiter);
                case "tsv": return parse_csv (fetch_text (q.location), "\\t");
                case "json": return parse_json (fetch_text (q.location));
                case "web":
                    string text = fetch_text (q.location);
                    string head = text.strip ();
                    if (head.has_prefix ("{") || head.has_prefix ("[")) return parse_json (text);
                    if (head.down ().contains ("<table")) return parse_html_table (text, int.parse (q.delimiter == "" ? "0" : q.delimiter));
                    return parse_csv (text, "");
                case "sqlite": return read_sqlite (q.location, q.sql);
                case "range": return from_range (book, q.location);
                case "query":
                    var other = find (book, q.location);
                    if (other == null) throw new QueryError.SOURCE (_("The query \"%s\" does not exist.").printf (q.location));
                    return run (book, other, visiting);
            }
            throw new QueryError.SOURCE (_("Unknown source."));
        }

        public static QueryDef? find (Workbook book, string name) {
            foreach (var q in book.analysis.queries) if (q.name.casefold () == name.casefold ()) return q;
            return null;
        }

        public static DataFrame run (Workbook book, QueryDef q, Gee.HashSet<string>? visiting = null, int upto = -1) throws Error {
            var seen = visiting ?? new Gee.HashSet<string> ();
            if (!seen.add (q.name.casefold ())) throw new QueryError.STEP (_("The query \"%s\" refers to itself.").printf (q.name));
            var df = source (book, q, seen);
            int n = upto < 0 ? q.steps.size : int.min (upto, q.steps.size);
            for (int i = 0; i < n; i++) df = apply (book, df, q.steps[i], seen);
            seen.remove (q.name.casefold ());
            return df;
        }

        private static string[] list_arg (string s) {
            string[] out_l = {};
            foreach (string p in s.split (",")) if (p.strip () != "") out_l += p.strip ();
            return out_l;
        }

        private static Value convert_type (Value v, string type) {
            if (v.is_empty ()) return v;
            switch (type) {
                case "number":
                    double d;
                    var e = Evaluator.to_number (v, out d);
                    return e != null ? Value.err (ErrorKind.VALUE) : Value.num (d);
                case "text": return Value.str (v.kind == ValueKind.NUMBER ? Value.format_number_general_full (v.number) : v.display ());
                case "bool":
                    if (v.kind == ValueKind.TEXT) {
                        string u = v.text.strip ().up ();
                        if (u == "TRUE" || u == "YES" || u == "1") return Value.boolean (true);
                        if (u == "FALSE" || u == "NO" || u == "0") return Value.boolean (false);
                        return Value.err (ErrorKind.VALUE);
                    }
                    return Value.boolean (v.number != 0);
                case "date":
                    if (v.kind == ValueKind.NUMBER) return Value.num (Math.floor (v.number));
                    double dd;
                    string fmt;
                    if (Input.parse_date_time (v.display (), out dd, out fmt)) return Value.num (Math.floor (dd));
                    return Value.err (ErrorKind.VALUE);
            }
            return v;
        }

        private static bool test (Value v, string op, string arg) {
            var crit = QueryEngine.parse_value (arg);
            int c = Evaluator.compare (v, crit);
            string t = v.display ().casefold ();
            string a = arg.casefold ();
            switch (op) {
                case "=": return v.equals (crit) || t == a;
                case "<>": return !(v.equals (crit) || t == a);
                case ">": return v.kind == crit.kind && c > 0;
                case ">=": return v.kind == crit.kind && c >= 0;
                case "<": return v.kind == crit.kind && c < 0;
                case "<=": return v.kind == crit.kind && c <= 0;
                case "contains": return t.contains (a);
                case "not-contains": return !t.contains (a);
                case "begins": return t.has_prefix (a);
                case "ends": return t.has_suffix (a);
                case "blank": return v.is_empty () || t == "";
                case "not-blank": return !(v.is_empty () || t == "");
            }
            return true;
        }

        public static DataFrame apply (Workbook book, DataFrame input, QueryStep st, Gee.HashSet<string>? visiting = null) throws Error {
            var df = input.copy ();
            switch (st.kind) {
                case "promote-headers":
                    promote (df);
                    break;
                case "change-type":
                    int ci = df.require (st.arg ("column"));
                    foreach (var r in df.rows) r[ci] = convert_type (r[ci], st.arg ("type", "text"));
                    break;
                case "filter-rows":
                    int fc = df.require (st.arg ("column"));
                    var kept = new Gee.ArrayList<Gee.ArrayList<Value>> ();
                    foreach (var r in df.rows) if (test (r[fc], st.arg ("op", "="), st.arg ("value"))) kept.add (r);
                    df.rows = kept;
                    break;
                case "remove-columns":
                case "keep-columns":
                    var idx = new Gee.ArrayList<int> ();
                    foreach (string n in list_arg (st.arg ("columns"))) idx.add (df.require (n));
                    var keep_idx = new Gee.ArrayList<int> ();
                    if (st.kind == "keep-columns") keep_idx.add_all (idx);
                    else for (int i = 0; i < df.columns.size; i++) if (!idx.contains (i)) keep_idx.add (i);
                    df = select (df, keep_idx);
                    break;
                case "reorder-columns":
                    var order = new Gee.ArrayList<int> ();
                    foreach (string n in list_arg (st.arg ("columns"))) order.add (df.require (n));
                    for (int i = 0; i < df.columns.size; i++) if (!order.contains (i)) order.add (i);
                    df = select (df, order);
                    break;
                case "rename-column":
                    df.columns[df.require (st.arg ("column"))] = st.arg ("name");
                    break;
                case "split-column":
                    int sc = df.require (st.arg ("column"));
                    string delim = st.arg ("delimiter", ",");
                    if (delim == "\\t") delim = "\t";
                    int parts = 1;
                    var split_rows = new Gee.ArrayList<Gee.ArrayList<string>> ();
                    foreach (var r in df.rows) {
                        var p = new Gee.ArrayList<string> ();
                        foreach (string piece in r[sc].display ().split (delim)) p.add (piece);
                        parts = int.max (parts, p.size);
                        split_rows.add (p);
                    }
                    string base_name = df.columns[sc];
                    var nd = new DataFrame ();
                    for (int i = 0; i < df.columns.size; i++) {
                        if (i == sc) for (int k = 0; k < parts; k++) nd.columns.add ("%s.%d".printf (base_name, k + 1));
                        else nd.columns.add (df.columns[i]);
                    }
                    for (int r = 0; r < df.rows.size; r++) {
                        var row = new Gee.ArrayList<Value> ();
                        for (int i = 0; i < df.columns.size; i++) {
                            if (i == sc) {
                                var p = split_rows[r];
                                for (int k = 0; k < parts; k++) row.add (k < p.size ? QueryEngine.parse_value (p[k].strip ()) : Value.empty ());
                            } else {
                                row.add (df.at (r, i));
                            }
                        }
                        nd.rows.add (row);
                    }
                    df = nd;
                    break;
                case "replace-values":
                    int rc = df.require (st.arg ("column"));
                    string find = st.arg ("find");
                    string repl = st.arg ("replace");
                    foreach (var r in df.rows) {
                        string t = r[rc].display ();
                        if (st.arg ("whole", "0") == "1") {
                            if (t == find) r[rc] = QueryEngine.parse_value (repl);
                        } else if (find != "" && t.contains (find)) {
                            r[rc] = QueryEngine.parse_value (t.replace (find, repl));
                        }
                    }
                    break;
                case "group-by":
                    df = group_by (df, list_arg (st.arg ("keys")), st.arg ("column"), st.arg ("function", "sum"), st.arg ("name"));
                    break;
                case "sort":
                    var keys = list_arg (st.arg ("columns"));
                    var descs = list_arg (st.arg ("descending"));
                    var kidx = new int[keys.length];
                    for (int i = 0; i < keys.length; i++) kidx[i] = df.require (keys[i]);
                    df.rows.sort ((a, b) => {
                        for (int i = 0; i < kidx.length; i++) {
                            int c = Evaluator.compare (a[kidx[i]], b[kidx[i]]);
                            if (c != 0) return i < descs.length && descs[i] == "1" ? -c : c;
                        }
                        return 0;
                    });
                    break;
                case "merge":
                    var other_q = find (book, st.arg ("query"));
                    if (other_q == null) throw new QueryError.STEP (_("The query \"%s\" does not exist.").printf (st.arg ("query")));
                    var other = run (book, other_q, visiting);
                    int lk = df.require (st.arg ("key"));
                    int rk = other.require (st.arg ("other-key", st.arg ("key")));
                    bool inner = st.arg ("join", "left") == "inner";
                    var index = new Gee.HashMap<string, Gee.ArrayList<int>> ();
                    for (int i = 0; i < other.rows.size; i++) {
                        string k = other.at (i, rk).display ().casefold ();
                        if (!index.has_key (k)) index[k] = new Gee.ArrayList<int> ();
                        index[k].add (i);
                    }
                    var md = new DataFrame ();
                    md.columns.add_all (df.columns);
                    for (int j = 0; j < other.columns.size; j++) if (j != rk) md.columns.add (other_q.name + "." + other.columns[j]);
                    foreach (var r in df.rows) {
                        string k = r[lk].display ().casefold ();
                        var matches = index[k];
                        if (matches == null) {
                            if (inner) continue;
                            var row = new Gee.ArrayList<Value> ();
                            row.add_all (r);
                            for (int j = 0; j < other.columns.size; j++) if (j != rk) row.add (Value.empty ());
                            md.rows.add (row);
                            continue;
                        }
                        foreach (int m in matches) {
                            var row = new Gee.ArrayList<Value> ();
                            row.add_all (r);
                            for (int j = 0; j < other.columns.size; j++) if (j != rk) row.add (other.at (m, j));
                            md.rows.add (row);
                        }
                    }
                    df = md;
                    break;
                case "append":
                    var aq = find (book, st.arg ("query"));
                    if (aq == null) throw new QueryError.STEP (_("The query \"%s\" does not exist.").printf (st.arg ("query")));
                    var ad = run (book, aq, visiting);
                    foreach (string c in ad.columns) if (df.index (c) < 0) df.columns.add (c);
                    df.pad ();
                    foreach (var r in ad.rows) {
                        var row = new Gee.ArrayList<Value> ();
                        for (int i = 0; i < df.columns.size; i++) {
                            int j = ad.index (df.columns[i]);
                            row.add (j >= 0 && j < r.size ? r[j] : Value.empty ());
                        }
                        df.rows.add (row);
                    }
                    break;
                case "unpivot":
                    var keep = new Gee.ArrayList<int> ();
                    foreach (string n in list_arg (st.arg ("keep"))) keep.add (df.require (n));
                    var ud = new DataFrame ();
                    foreach (int k in keep) ud.columns.add (df.columns[k]);
                    ud.columns.add (st.arg ("attribute", "Attribute"));
                    ud.columns.add (st.arg ("value", "Value"));
                    foreach (var r in df.rows) {
                        for (int i = 0; i < df.columns.size; i++) {
                            if (keep.contains (i)) continue;
                            if (r[i].is_empty ()) continue;
                            var row = new Gee.ArrayList<Value> ();
                            foreach (int k in keep) row.add (r[k]);
                            row.add (Value.str (df.columns[i]));
                            row.add (r[i]);
                            ud.rows.add (row);
                        }
                    }
                    df = ud;
                    break;
                case "remove-duplicates":
                    var seen = new Gee.HashSet<string> ();
                    var cols = list_arg (st.arg ("columns"));
                    var ci2 = new Gee.ArrayList<int> ();
                    foreach (string n in cols) ci2.add (df.require (n));
                    if (ci2.size == 0) for (int i = 0; i < df.columns.size; i++) ci2.add (i);
                    var uniq = new Gee.ArrayList<Gee.ArrayList<Value>> ();
                    foreach (var r in df.rows) {
                        var sb = new StringBuilder ();
                        foreach (int i in ci2) sb.append (r[i].display ().casefold ()).append_c ('\x1f');
                        if (seen.add (sb.str)) uniq.add (r);
                    }
                    df.rows = uniq;
                    break;
                case "keep-top":
                    int n = int.parse (st.arg ("count", "10"));
                    while (df.rows.size > n && n >= 0) df.rows.remove_at (df.rows.size - 1);
                    break;
                case "fill-down":
                    int fdc = df.require (st.arg ("column"));
                    Value last = Value.empty ();
                    foreach (var r in df.rows) {
                        if (r[fdc].is_empty ()) r[fdc] = last;
                        else last = r[fdc];
                    }
                    break;
                case "trim":
                    int tc = df.require (st.arg ("column"));
                    foreach (var r in df.rows) if (r[tc].kind == ValueKind.TEXT) r[tc] = Value.str (r[tc].text.strip ());
                    break;
                case "remove-blank-rows":
                    var nb = new Gee.ArrayList<Gee.ArrayList<Value>> ();
                    foreach (var r in df.rows) {
                        bool blank = true;
                        foreach (var v in r) if (!v.is_empty () && v.display () != "") blank = false;
                        if (!blank) nb.add (r);
                    }
                    df.rows = nb;
                    break;
                case "add-index":
                    df.columns.add (st.arg ("name", "Index"));
                    int start = int.parse (st.arg ("start", "1"));
                    for (int i = 0; i < df.rows.size; i++) df.rows[i].add (Value.num (start + i));
                    break;
                default:
                    throw new QueryError.STEP (_("Unknown step."));
            }
            return df;
        }

        private static DataFrame select (DataFrame df, Gee.List<int> idx) {
            var nd = new DataFrame ();
            foreach (int i in idx) nd.columns.add (df.columns[i]);
            foreach (var r in df.rows) {
                var row = new Gee.ArrayList<Value> ();
                foreach (int i in idx) row.add (i < r.size ? r[i] : Value.empty ());
                nd.rows.add (row);
            }
            return nd;
        }

        private static DataFrame group_by (DataFrame df, string[] keys, string column, string fn, string name) throws Error {
            var kidx = new int[keys.length];
            for (int i = 0; i < keys.length; i++) kidx[i] = df.require (keys[i]);
            int vc = fn == "count" && column == "" ? -1 : df.require (column);
            var order = new Gee.ArrayList<string> ();
            var firsts = new Gee.HashMap<string, Gee.ArrayList<Value>> ();
            var accs = new Gee.HashMap<string, PivotAcc> ();
            foreach (var r in df.rows) {
                var sb = new StringBuilder ();
                foreach (int k in kidx) sb.append (r[k].display ().casefold ()).append_c ('\x1f');
                string key = sb.str;
                if (!accs.has_key (key)) {
                    order.add (key);
                    accs[key] = new PivotAcc ();
                    var f = new Gee.ArrayList<Value> ();
                    foreach (int k in kidx) f.add (r[k]);
                    firsts[key] = f;
                }
                accs[key].add (vc < 0 ? Value.num (1) : r[vc]);
            }
            PivotAgg agg = fn == "count" ? PivotAgg.COUNT : fn == "average" ? PivotAgg.AVERAGE : fn == "min" ? PivotAgg.MIN : fn == "max" ? PivotAgg.MAX : fn == "countNums" ? PivotAgg.COUNT_NUMS : PivotAgg.SUM;
            var nd = new DataFrame ();
            foreach (string k in keys) nd.columns.add (df.columns[df.require (k)]);
            nd.columns.add (name != "" ? name : (vc >= 0 ? "%s of %s".printf (agg.label (), df.columns[vc]) : _("Count")));
            foreach (string key in order) {
                var row = new Gee.ArrayList<Value> ();
                row.add_all (firsts[key]);
                row.add (accs[key].result (agg));
                nd.rows.add (row);
            }
            return nd;
        }
    }
}
