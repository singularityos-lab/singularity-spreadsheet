namespace Singularity.Apps.Spreadsheet {

    public class ModelRelationship {
        public string from_table;
        public string from_column;
        public string to_table;
        public string to_column;
        public bool inferred;

        public ModelRelationship (string from_table, string from_column, string to_table, string to_column) {
            this.from_table = from_table;
            this.from_column = from_column;
            this.to_table = to_table;
            this.to_column = to_column;
        }
    }

    public class ModelMeasure {
        public string name;
        public string table;
        public string column;
        public string aggregation;
        public string formula = "";

        public ModelMeasure (string name, string table, string column, string aggregation) {
            this.name = name;
            this.table = table;
            this.column = column;
            this.aggregation = aggregation;
        }
    }

    public class ModelKpi {
        public string name;
        public string value_measure;
        public string goal_measure = "";
        public double goal = double.NAN;
        public double low = 0.8;
        public double high = 1.0;
    }

    public class ModelTable {
        public TableDef def;
        public string name;
        public Gee.ArrayList<string> columns = new Gee.ArrayList<string> ();
        public Gee.ArrayList<Value> cells = new Gee.ArrayList<Value> ();
        public int rows;

        public int col (string n) {
            string k = n.casefold ();
            for (int i = 0; i < columns.size; i++) if (columns[i].casefold () == k) return i;
            return -1;
        }

        public Value at (int r, int c) {
            return cells[r * columns.size + c];
        }
    }

    public class DataModel {
        public const string NAME = "_DataModel";
        public Gee.ArrayList<ModelTable> tables = new Gee.ArrayList<ModelTable> ();
        public Gee.ArrayList<ModelRelationship> relationships = new Gee.ArrayList<ModelRelationship> ();
        public Gee.ArrayList<ModelMeasure> measures = new Gee.ArrayList<ModelMeasure> ();
        public Gee.ArrayList<ModelKpi> kpis = new Gee.ArrayList<ModelKpi> ();
        public bool infer = true;
        public Workbook? book;

        public ModelTable? table (string name) {
            string k = name.casefold ();
            foreach (var t in tables) if (t.name.casefold () == k) return t;
            return null;
        }

        public static string? stored_json (Workbook book) {
            string? f = null;
            foreach (var e in book.names.entries) if (e.key.casefold () == NAME.casefold ()) f = e.value;
            if (f == null) return null;
            string s = f.strip ();
            if (s.has_prefix ("=")) s = s.substring (1).strip ();
            if (s.has_prefix ("\"") && s.has_suffix ("\"") && s.length >= 2) s = s.substring (1, s.length - 2).replace ("\"\"", "\"");
            return s;
        }

        public static void store_json (Workbook book, string json) {
            string key = NAME;
            foreach (var k in book.names.keys) if (k.casefold () == NAME.casefold ()) key = k;
            if (json.strip () == "") book.names.unset (key);
            else book.names[key] = "=\"" + json.replace ("\"", "\"\"") + "\"";
        }

        public static DataModel build (Workbook book) {
            var m = new DataModel ();
            m.book = book;
            foreach (var t in book.tables) {
                var mt = new ModelTable ();
                mt.def = t;
                mt.name = t.name;
                foreach (var c in t.columns) mt.columns.add (c.name);
                int r1 = t.data_r1, r2 = t.data_r2;
                mt.rows = int.max (0, r2 - r1 + 1);
                for (int r = r1; r <= r2; r++) {
                    for (int c = 0; c < mt.columns.size; c++) mt.cells.add (t.sheet.value_at (r, t.area.c1 + c));
                }
                m.tables.add (mt);
            }
            string? json = stored_json (book);
            if (json != null) m.load (json);
            if (m.infer) m.infer_relationships ();
            return m;
        }

        private static string str_of (Json.Object o, string k) {
            return o.has_member (k) ? o.get_string_member (k) ?? "" : "";
        }

        public void load (string json) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json);
                var root = parser.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return;
                var o = root.get_object ();
                if (o.has_member ("infer")) infer = o.get_boolean_member ("infer");
                if (o.has_member ("relationships")) {
                    foreach (var n in o.get_array_member ("relationships").get_elements ()) {
                        var r = n.get_object ();
                        relationships.add (new ModelRelationship (str_of (r, "fromTable"), str_of (r, "fromColumn"), str_of (r, "toTable"), str_of (r, "toColumn")));
                    }
                }
                if (o.has_member ("measures")) {
                    foreach (var n in o.get_array_member ("measures").get_elements ()) {
                        var r = n.get_object ();
                        var ms = new ModelMeasure (str_of (r, "name"), str_of (r, "table"), str_of (r, "column"), str_of (r, "aggregation").up ());
                        ms.formula = str_of (r, "formula");
                        if (ms.formula != "") ms.aggregation = "FORMULA";
                        measures.add (ms);
                    }
                }
                if (o.has_member ("kpis")) {
                    foreach (var n in o.get_array_member ("kpis").get_elements ()) {
                        var r = n.get_object ();
                        var k = new ModelKpi ();
                        k.name = str_of (r, "name");
                        k.value_measure = str_of (r, "value");
                        if (r.has_member ("goal")) {
                            var g = r.get_member ("goal");
                            if (g.get_value_type () == typeof (string)) k.goal_measure = g.get_string ();
                            else k.goal = g.get_double ();
                        }
                        if (r.has_member ("low")) k.low = r.get_double_member ("low");
                        if (r.has_member ("high")) k.high = r.get_double_member ("high");
                        kpis.add (k);
                    }
                }
            } catch (Error e) {
            }
        }

        public string to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("infer");
            b.add_boolean_value (infer);
            b.set_member_name ("relationships");
            b.begin_array ();
            foreach (var r in relationships) {
                if (r.inferred) continue;
                b.begin_object ();
                b.set_member_name ("fromTable");
                b.add_string_value (r.from_table);
                b.set_member_name ("fromColumn");
                b.add_string_value (r.from_column);
                b.set_member_name ("toTable");
                b.add_string_value (r.to_table);
                b.set_member_name ("toColumn");
                b.add_string_value (r.to_column);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("measures");
            b.begin_array ();
            foreach (var ms in measures) {
                b.begin_object ();
                b.set_member_name ("name");
                b.add_string_value (ms.name);
                b.set_member_name ("table");
                b.add_string_value (ms.table);
                b.set_member_name ("column");
                b.add_string_value (ms.column);
                b.set_member_name ("aggregation");
                b.add_string_value (ms.aggregation);
                if (ms.formula != "") {
                    b.set_member_name ("formula");
                    b.add_string_value (ms.formula);
                }
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("kpis");
            b.begin_array ();
            foreach (var k in kpis) {
                b.begin_object ();
                b.set_member_name ("name");
                b.add_string_value (k.name);
                b.set_member_name ("value");
                b.add_string_value (k.value_measure);
                b.set_member_name ("goal");
                if (k.goal_measure != "") b.add_string_value (k.goal_measure);
                else b.add_double_value (k.goal.is_nan () ? 0 : k.goal);
                b.set_member_name ("low");
                b.add_double_value (k.low);
                b.set_member_name ("high");
                b.add_double_value (k.high);
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }

        public void save (Workbook book) {
            store_json (book, to_json ());
        }

        private bool declared_between (string a, string b) {
            foreach (var r in relationships) {
                if ((r.from_table.casefold () == a.casefold () && r.to_table.casefold () == b.casefold ()) || (r.from_table.casefold () == b.casefold () && r.to_table.casefold () == a.casefold ())) return true;
            }
            return false;
        }

        private static Gee.HashSet<string> keys_of (ModelTable t, int c, out bool unique) {
            var s = new Gee.HashSet<string> ();
            unique = true;
            for (int r = 0; r < t.rows; r++) {
                var v = t.at (r, c);
                if (v.is_empty ()) continue;
                string k = key (v);
                if (s.contains (k)) unique = false;
                s.add (k);
            }
            return s;
        }

        public void infer_relationships () {
            foreach (var lookup in tables) {
                for (int lc = 0; lc < lookup.columns.size; lc++) {
                    bool unique;
                    var lk = keys_of (lookup, lc, out unique);
                    if (!unique || lk.size == 0) continue;
                    foreach (var fact in tables) {
                        if (fact == lookup || declared_between (fact.name, lookup.name)) continue;
                        int fc = fact.col (lookup.columns[lc]);
                        if (fc < 0) continue;
                        bool fu;
                        var fk = keys_of (fact, fc, out fu);
                        if (fk.size == 0 || (fu && fact.rows <= lookup.rows)) continue;
                        bool contained = true;
                        foreach (var k in fk) if (!lk.contains (k)) contained = false;
                        if (!contained) continue;
                        var rel = new ModelRelationship (fact.name, fact.columns[fc], lookup.name, lookup.columns[lc]);
                        rel.inferred = true;
                        relationships.add (rel);
                    }
                }
            }
        }

        public static string key (Value v) {
            switch (v.kind) {
                case ValueKind.NUMBER: return Value.format_number_general_full (v.number);
                case ValueKind.BOOL: return v.number != 0 ? "TRUE" : "FALSE";
                case ValueKind.EMPTY: return "";
                default: return v.display ().casefold ();
            }
        }

        public Gee.ArrayList<ModelRelationship>? path (string from, string to) {
            var prev = new Gee.HashMap<string, ModelRelationship> ();
            var seen = new Gee.HashSet<string> ();
            var queue = new Gee.ArrayList<string> ();
            queue.add (from.casefold ());
            seen.add (from.casefold ());
            while (queue.size > 0) {
                string cur = queue.remove_at (0);
                if (cur == to.casefold ()) {
                    var list = new Gee.ArrayList<ModelRelationship> ();
                    string c = cur;
                    while (c != from.casefold ()) {
                        var r = prev[c];
                        list.insert (0, r);
                        c = r.from_table.casefold ();
                    }
                    return list;
                }
                foreach (var r in relationships) {
                    if (r.from_table.casefold () != cur) continue;
                    string nx = r.to_table.casefold ();
                    if (seen.contains (nx)) continue;
                    seen.add (nx);
                    prev[nx] = r;
                    queue.add (nx);
                }
            }
            return null;
        }

        public Value related (ModelTable fact, int row, string target_table, string target_column) {
            if (fact.name.casefold () == target_table.casefold ()) {
                int c = fact.col (target_column);
                return c < 0 ? Value.err (ErrorKind.NA) : fact.at (row, c);
            }
            var p = path (fact.name, target_table);
            if (p == null) return Value.err (ErrorKind.NA);
            var cur = fact;
            int r = row;
            foreach (var rel in p) {
                int fc = cur.col (rel.from_column);
                var nt = table (rel.to_table);
                if (fc < 0 || nt == null) return Value.err (ErrorKind.NA);
                string k = key (cur.at (r, fc));
                int tc = nt.col (rel.to_column);
                int found = -1;
                for (int i = 0; i < nt.rows && found < 0; i++) if (key (nt.at (i, tc)) == k) found = i;
                if (found < 0) return Value.empty ();
                cur = nt;
                r = found;
            }
            int oc = cur.col (target_column);
            return oc < 0 ? Value.err (ErrorKind.NA) : cur.at (r, oc);
        }
    }

    public enum CubeKind {
        MEMBER,
        ALL,
        MEASURE,
        KPI
    }

    public class CubeMember {
        public CubeKind kind;
        public string table = "";
        public string column = "";
        public Value? item;
        public string measure = "";
        public string agg = "";
        public int kpi_property;
        public string caption = "";

        public string unique_name () {
            if (kind == CubeKind.MEASURE || kind == CubeKind.KPI) return "[Measures].[" + measure + "]";
            if (kind == CubeKind.ALL) return "[" + table + "].[" + column + "].[All]";
            return "[" + table + "].[" + column + "].&[" + item.display () + "]";
        }
    }

    public class CubeTuple {
        public Gee.ArrayList<CubeMember> members = new Gee.ArrayList<CubeMember> ();

        public string caption () {
            return members.size > 0 ? members[members.size - 1].caption : "";
        }
    }

    public class CubeSet {
        public Gee.ArrayList<CubeTuple> tuples = new Gee.ArrayList<CubeTuple> ();
        public string caption = "";
    }

    public class Mdx {
        public static string[] parts (string s) {
            string[] out_parts = {};
            int i = 0;
            int n = s.length;
            while (i < n) {
                while (i < n && (s[i] == ' ' || s[i] == '.')) i++;
                if (i >= n) break;
                bool amp = false;
                if (s[i] == '&') {
                    amp = true;
                    i++;
                }
                if (i < n && s[i] == '[') {
                    var sb = new StringBuilder (amp ? "&" : "");
                    i++;
                    while (i < n) {
                        if (s[i] == ']') {
                            if (i + 1 < n && s[i + 1] == ']') {
                                sb.append_c (']');
                                i += 2;
                                continue;
                            }
                            i++;
                            break;
                        }
                        sb.append_c (s[i]);
                        i++;
                    }
                    out_parts += sb.str;
                } else {
                    int st = i;
                    while (i < n && s[i] != '.') i++;
                    out_parts += (amp ? "&" : "") + s.substring (st, i - st).strip ();
                }
            }
            return out_parts;
        }

        public static string[] split_top (string s) {
            string[] items = {};
            int depth = 0;
            bool br = false;
            int st = 0;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (br) {
                    if (c == ']') {
                        if (i + 1 < s.length && s[i + 1] == ']') i++;
                        else br = false;
                    }
                    continue;
                }
                if (c == '[') br = true;
                else if (c == '(' || c == '{') depth++;
                else if (c == ')' || c == '}') depth--;
                else if (c == ',' && depth == 0) {
                    items += s.substring (st, i - st).strip ();
                    st = i + 1;
                }
            }
            string last = s.substring (st).strip ();
            if (last != "") items += last;
            return items;
        }
    }

    public class Cube {
        public DataModel model;
        public string error = "";

        public Cube (DataModel model) {
            this.model = model;
        }

        private static bool is_measure_agg (string name, out string agg, out string col) {
            string[,] forms = { { "Distinct Count of ", "DISTINCTCOUNT" }, { "Sum of ", "SUM" }, { "Count of ", "COUNT" }, { "Average of ", "AVERAGE" }, { "Min of ", "MIN" }, { "Max of ", "MAX" } };
            for (int i = 0; i < forms.length[0]; i++) {
                if (name.down ().has_prefix (forms[i, 0].down ())) {
                    agg = forms[i, 1];
                    col = name.substring (forms[i, 0].length);
                    return true;
                }
            }
            agg = "";
            col = "";
            return false;
        }

        public CubeMember? member (string expr) {
            string[] p = Mdx.parts (expr.strip ());
            if (p.length == 0) {
                error = _("Empty member expression");
                return null;
            }
            var m = new CubeMember ();
            if (p[0].casefold () == "measures") {
                if (p.length < 2) return null;
                m.kind = CubeKind.MEASURE;
                m.measure = p[1];
                m.caption = p[1];
                foreach (var ms in model.measures) {
                    if (ms.name.casefold () == p[1].casefold ()) {
                        m.table = ms.table;
                        m.column = ms.column;
                        m.agg = ms.aggregation;
                        m.measure = ms.name;
                        return m;
                    }
                }
                foreach (var k in model.kpis) {
                    if (k.name.casefold () == p[1].casefold ()) {
                        m.kind = CubeKind.KPI;
                        m.measure = k.name;
                        m.kpi_property = 1;
                        return m;
                    }
                }
                string agg, col;
                if (!is_measure_agg (p[1], out agg, out col)) {
                    error = _("Unknown measure %s").printf (p[1]);
                    return null;
                }
                foreach (var t in model.tables) {
                    if (t.col (col) >= 0) {
                        m.table = t.name;
                        m.column = t.columns[t.col (col)];
                        break;
                    }
                }
                if (m.table == "") {
                    error = _("Unknown column %s").printf (col);
                    return null;
                }
                m.agg = agg;
                return m;
            }
            var t = model.table (p[0]);
            if (t == null) {
                error = _("Unknown table %s").printf (p[0]);
                return null;
            }
            m.table = t.name;
            if (p.length < 2) {
                error = _("A column is needed after %s").printf (p[0]);
                return null;
            }
            int c = t.col (p[1]);
            if (c < 0) {
                error = _("Unknown column %s").printf (p[1]);
                return null;
            }
            m.column = t.columns[c];
            int ip = 2;
            if (p.length > ip && p[ip].casefold () == "all") ip++;
            if (p.length <= ip) {
                m.kind = CubeKind.ALL;
                m.caption = _("All");
                return m;
            }
            string want = p[ip];
            bool by_key = want.has_prefix ("&");
            if (by_key) want = want.substring (1);
            for (int r = 0; r < t.rows; r++) {
                var v = t.at (r, c);
                if (v.is_empty ()) continue;
                if (DataModel.key (v) == want.casefold () || v.display ().casefold () == want.casefold ()) {
                    m.kind = CubeKind.MEMBER;
                    m.item = v;
                    m.caption = v.display ();
                    return m;
                }
            }
            error = _("No member %s in %s").printf (want, m.column);
            return null;
        }

        public CubeTuple? tuple (string expr) {
            string s = expr.strip ();
            var t = new CubeTuple ();
            if (s.has_prefix ("(") && s.has_suffix (")")) {
                foreach (string part in Mdx.split_top (s.substring (1, s.length - 2))) {
                    var m = member (part);
                    if (m == null) return null;
                    t.members.add (m);
                }
                return t.members.size > 0 ? t : null;
            }
            var m = member (s);
            if (m == null) return null;
            t.members.add (m);
            return t;
        }

        public CubeSet? set (string expr) {
            string s = expr.strip ();
            var cs = new CubeSet ();
            if (s.has_prefix ("{") && s.has_suffix ("}")) {
                foreach (string part in Mdx.split_top (s.substring (1, s.length - 2))) {
                    var inner = set (part);
                    if (inner == null) return null;
                    cs.tuples.add_all (inner.tuples);
                }
                return cs;
            }
            string low = s.down ();
            string? base_expr = null;
            if (low.has_suffix (".children")) base_expr = s.substring (0, s.length - 9);
            else if (low.has_suffix (".members")) base_expr = s.substring (0, s.length - 8);
            else if (low.has_suffix (".allmembers")) base_expr = s.substring (0, s.length - 11);
            if (base_expr != null) {
                var bm = member (base_expr);
                if (bm == null || bm.kind == CubeKind.MEASURE || bm.kind == CubeKind.KPI) {
                    if (bm != null) {
                        foreach (var ms in model.measures) {
                            var t = new CubeTuple ();
                            t.members.add (member ("[Measures].[" + ms.name + "]"));
                            cs.tuples.add (t);
                        }
                        return cs;
                    }
                    return null;
                }
                var mt = model.table (bm.table);
                int c = mt.col (bm.column);
                var seen = new Gee.HashSet<string> ();
                var vals = new Gee.ArrayList<Value> ();
                for (int r = 0; r < mt.rows; r++) {
                    var v = mt.at (r, c);
                    if (v.is_empty () || seen.contains (DataModel.key (v))) continue;
                    seen.add (DataModel.key (v));
                    vals.add (v);
                }
                vals.sort ((x, y) => ArrayFunctions.sort_cmp (x, y, false));
                foreach (var v in vals) {
                    var m = new CubeMember ();
                    m.kind = CubeKind.MEMBER;
                    m.table = bm.table;
                    m.column = bm.column;
                    m.item = v;
                    m.caption = v.display ();
                    var t = new CubeTuple ();
                    t.members.add (m);
                    cs.tuples.add (t);
                }
                return cs;
            }
            var single = tuple (s);
            if (single == null) return null;
            cs.tuples.add (single);
            return cs;
        }

        private static double[] aggregate_values (Gee.ArrayList<Value> vals, string agg, out bool empty) {
            empty = false;
            double s = 0, mn = double.INFINITY, mx = -double.INFINITY;
            int count = 0, nums = 0;
            var distinct = new Gee.HashSet<string> ();
            foreach (var v in vals) {
                if (v.is_empty ()) continue;
                count++;
                distinct.add (DataModel.key (v));
                if (v.kind == ValueKind.NUMBER) {
                    nums++;
                    s += v.number;
                    mn = double.min (mn, v.number);
                    mx = double.max (mx, v.number);
                }
            }
            switch (agg) {
                case "COUNT":
                    empty = count == 0;
                    return { count };
                case "DISTINCTCOUNT":
                    empty = count == 0;
                    return { distinct.size };
                case "AVERAGE":
                    empty = nums == 0;
                    return { nums == 0 ? 0 : s / nums };
                case "MIN":
                    empty = nums == 0;
                    return { mn };
                case "MAX":
                    empty = nums == 0;
                    return { mx };
                default:
                    empty = nums == 0;
                    return { s };
            }
        }

        public Value measure_value (string table, string column, string agg, Gee.List<CubeMember> filters) {
            var mt = model.table (table);
            if (mt == null) return Value.err (ErrorKind.NA);
            int c = mt.col (column);
            if (c < 0) return Value.err (ErrorKind.NA);
            var groups = new Gee.HashMap<string, Gee.ArrayList<CubeMember>> ();
            foreach (var f in filters) {
                if (f.kind != CubeKind.MEMBER) continue;
                string k = f.table.casefold () + "\x1f" + f.column.casefold ();
                if (!groups.has_key (k)) groups[k] = new Gee.ArrayList<CubeMember> ();
                groups[k].add (f);
            }
            var vals = new Gee.ArrayList<Value> ();
            for (int r = 0; r < mt.rows; r++) {
                bool ok = true;
                foreach (var g in groups.values) {
                    var first = g[0];
                    if (first.table.casefold () != mt.name.casefold () && model.path (mt.name, first.table) == null) continue;
                    var v = model.related (mt, r, first.table, first.column);
                    string vk = DataModel.key (v);
                    bool any = false;
                    foreach (var m in g) if (DataModel.key (m.item) == vk) any = true;
                    if (!any) {
                        ok = false;
                        break;
                    }
                }
                if (ok) vals.add (mt.at (r, c));
            }
            bool empty;
            var res = aggregate_values (vals, agg, out empty);
            if (empty && agg != "COUNT" && agg != "DISTINCTCOUNT") return Value.empty ();
            return Value.num (res[0]);
        }

        private int depth = 0;

        public Value formula_value (string name, Gee.List<CubeMember> filters) {
            ModelMeasure? def = null;
            foreach (var ms in model.measures) if (ms.name.casefold () == name.casefold ()) def = ms;
            if (def == null || model.book == null || model.book.sheets.size == 0 || depth > 16) return Value.err (ErrorKind.NA);
            depth++;
            var sb = new StringBuilder ();
            string f = def.formula.strip ();
            if (f.has_prefix ("=")) f = f.substring (1);
            Value? failure = null;
            for (int i = 0; i < f.length; i++) {
                char c = f[i];
                if (c == '"') {
                    int j = f.index_of_char ('"', i + 1);
                    if (j < 0) j = f.length - 1;
                    sb.append (f.substring (i, j - i + 1));
                    i = j;
                    continue;
                }
                if (c != '[') {
                    sb.append_c (c);
                    continue;
                }
                int close = f.index_of_char (']', i + 1);
                if (close < 0) {
                    failure = Value.err (ErrorKind.NAME);
                    break;
                }
                string ref_name = f.substring (i + 1, close - i - 1);
                i = close;
                var m = member ("[Measures].[" + ref_name + "]");
                if (m == null) {
                    failure = Value.err (ErrorKind.NAME);
                    break;
                }
                var all = new Gee.ArrayList<CubeMember> ();
                all.add_all (filters);
                all.add (m);
                var v = evaluate (all);
                if (v.is_error ()) {
                    failure = v;
                    break;
                }
                double d = v.kind == ValueKind.NUMBER ? v.number : 0;
                sb.append ("(" + Value.format_number_general_full (d) + ")");
            }
            Value result;
            if (failure != null) {
                result = failure;
            } else {
                try {
                    var node = Formula.parse ("=" + sb.str, model.book, model.book.sheets[0]);
                    result = new Evaluator (model.book, model.book.sheets[0], 0, 0).eval_top (node);
                } catch (FormulaError e) {
                    result = Value.err (ErrorKind.NAME);
                }
            }
            depth--;
            return result;
        }

        public Value evaluate (Gee.List<CubeMember> members) {
            CubeMember? measure = null;
            var filters = new Gee.ArrayList<CubeMember> ();
            foreach (var m in members) {
                if (m.kind == CubeKind.MEASURE || m.kind == CubeKind.KPI) measure = m;
                else filters.add (m);
            }
            if (measure == null) {
                if (model.measures.size > 0) measure = member ("[Measures].[" + model.measures[0].name + "]");
                else if (model.tables.size > 0) {
                    measure = new CubeMember ();
                    measure.kind = CubeKind.MEASURE;
                    measure.table = model.tables[0].name;
                    measure.column = model.tables[0].columns[0];
                    measure.agg = "COUNT";
                }
                if (measure == null) return Value.err (ErrorKind.NA);
            }
            if (measure.kind == CubeKind.KPI) return kpi_value (measure, filters);
            if (measure.agg == "FORMULA") return formula_value (measure.measure, filters);
            return measure_value (measure.table, measure.column, measure.agg, filters);
        }

        private Value with_measure (CubeMember m, Gee.List<CubeMember> filters) {
            var all = new Gee.ArrayList<CubeMember> ();
            all.add_all (filters);
            all.add (m);
            return evaluate (all);
        }

        private Value kpi_value (CubeMember m, Gee.List<CubeMember> filters) {
            ModelKpi? kpi = null;
            foreach (var k in model.kpis) if (k.name.casefold () == m.measure.casefold ()) kpi = k;
            if (kpi == null) return Value.err (ErrorKind.NA);
            var vm = member ("[Measures].[" + kpi.value_measure + "]");
            if (vm == null) return Value.err (ErrorKind.NA);
            var value = with_measure (vm, filters);
            Value goal;
            if (kpi.goal_measure != "") {
                var gm = member ("[Measures].[" + kpi.goal_measure + "]");
                if (gm == null) return Value.err (ErrorKind.NA);
                goal = with_measure (gm, filters);
            } else {
                goal = Value.num (kpi.goal);
            }
            switch (m.kpi_property) {
                case 1: return value;
                case 2: return goal;
                case 3:
                    if (value.kind != ValueKind.NUMBER || goal.kind != ValueKind.NUMBER || goal.number == 0) return Value.err (ErrorKind.NA);
                    double ratio = value.number / goal.number;
                    return Value.num (ratio >= kpi.high ? 1 : (ratio >= kpi.low ? 0 : -1));
                case 5: return Value.num (1);
                default: return Value.err (ErrorKind.NA);
            }
        }
    }

    public class CubeFunctions {
        public static string last_error = "";

        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Cube", syntax, summary, (owned) impl);
        }

        private static Value? connect (Evaluator ev, Node n, out Cube? cube) {
            cube = null;
            Value? e = null;
            string conn = ev.arg_text (n, out e);
            if (e != null) return e;
            var model = DataModel.build (ev.book);
            string c = conn.strip ();
            bool local = c.casefold () == "thisworkbookdatamodel" || model.table (c) != null;
            if (!local) {
                last_error = _("The connection %s is not in this workbook; external OLAP servers are not supported").printf (c);
                return Value.err (ErrorKind.NA);
            }
            cube = new Cube (model);
            return null;
        }

        private static bool is_cube_call (Node n, string name) {
            return n.kind == NodeKind.CALL && n.text == name;
        }

        private static Node? cube_formula (Evaluator ev, Node n, out Evaluator? at) {
            at = null;
            if (n.kind != NodeKind.REF || n.b != null || n.a == null) return null;
            var s = n.sheet ?? ev.sheet;
            var cell = s.get_cell (n.a.row, n.a.col);
            if (cell == null || cell.formula == null || cell.formula.kind != NodeKind.CALL || !cell.formula.text.has_prefix ("CUBE")) return null;
            at = new Evaluator (ev.book, s, n.a.row, n.a.col);
            return cell.formula;
        }

        public static Gee.ArrayList<CubeMember>? members_of (Evaluator ev, Cube cube, Node n, out Value? err) {
            err = null;
            Evaluator at;
            var f = cube_formula (ev, n, out at);
            if (f != null) {
                if (is_cube_call (f, "CUBEMEMBER") && f.args.length >= 2) return members_of (at, cube, f.args[1], out err);
                if (is_cube_call (f, "CUBEKPIMEMBER") && f.args.length >= 3) {
                    var km = kpi_member (at, cube, f.args, out err);
                    if (km == null) return null;
                    var one = new Gee.ArrayList<CubeMember> ();
                    one.add (km);
                    return one;
                }
                if (is_cube_call (f, "CUBERANKEDMEMBER") && f.args.length >= 3) {
                    var t = ranked (at, cube, f.args, out err);
                    if (t == null) return null;
                    var l = new Gee.ArrayList<CubeMember> ();
                    l.add_all (t.members);
                    return l;
                }
                if (is_cube_call (f, "CUBESET") && f.args.length >= 2) {
                    var cs = set_of (at, cube, f.args, out err);
                    if (cs == null) return null;
                    var l = new Gee.ArrayList<CubeMember> ();
                    foreach (var t in cs.tuples) l.add_all (t.members);
                    return l;
                }
            }
            var v = ev.eval (n);
            var list = new Gee.ArrayList<CubeMember> ();
            if (v.is_error ()) {
                err = v;
                return null;
            }
            var m = ev.to_matrix (v.kind == ValueKind.RANGE || v.kind == ValueKind.ARRAY ? v : ev.deref (v));
            for (int i = 0; i < m.length[0]; i++) for (int j = 0; j < m.length[1]; j++) {
                if (m[i, j].is_empty ()) continue;
                var t = cube.tuple (Evaluator.to_text (m[i, j]));
                if (t == null) {
                    err = Value.err (ErrorKind.NA);
                    return null;
                }
                list.add_all (t.members);
            }
            return list;
        }

        private static CubeMember? kpi_member (Evaluator ev, Cube cube, Node[] a, out Value? err) {
            err = null;
            Value? e = null;
            string name = ev.arg_text (a[1], out e);
            if (e != null) {
                err = e;
                return null;
            }
            int prop;
            if ((e = ev.arg_int (a[2], out prop)) != null) {
                err = e;
                return null;
            }
            ModelKpi? kpi = null;
            foreach (var k in cube.model.kpis) if (k.name.casefold () == name.casefold ()) kpi = k;
            if (kpi == null || prop < 1 || prop > 6) {
                err = Value.err (ErrorKind.NA);
                return null;
            }
            var m = new CubeMember ();
            m.kind = CubeKind.KPI;
            m.measure = kpi.name;
            m.kpi_property = prop;
            string[] names = { "", _("Value"), _("Goal"), _("Status"), _("Trend"), _("Weight"), _("Current Time Member") };
            m.caption = kpi.name + " " + names[prop];
            return m;
        }

        public static CubeSet? set_of (Evaluator ev, Cube cube, Node[] a, out Value? err) {
            err = null;
            Evaluator at;
            var f = cube_formula (ev, a[1], out at);
            CubeSet? cs = null;
            if (f != null && is_cube_call (f, "CUBESET") && f.args.length >= 2) {
                cs = set_of (at, cube, f.args, out err);
            } else {
                var v = ev.eval (a[1]);
                if (v.is_error ()) {
                    err = v;
                    return null;
                }
                cs = new CubeSet ();
                var m = ev.to_matrix (v.kind == ValueKind.RANGE || v.kind == ValueKind.ARRAY ? v : ev.deref (v));
                for (int i = 0; i < m.length[0]; i++) for (int j = 0; j < m.length[1]; j++) {
                    if (m[i, j].is_empty ()) continue;
                    var part = cube.set (Evaluator.to_text (m[i, j]));
                    if (part == null) {
                        err = Value.err (ErrorKind.NA);
                        return null;
                    }
                    cs.tuples.add_all (part.tuples);
                }
            }
            if (cs == null) return null;
            if (f == null || !is_cube_call (f, "CUBESET")) {
                Value? e = null;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING) {
                    cs.caption = ev.arg_text (a[2], out e);
                    if (e != null) {
                        err = e;
                        return null;
                    }
                }
                int order = 0;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_int (a[3], out order)) != null) {
                    err = e;
                    return null;
                }
                if (order < 0 || order > 6) {
                    err = Value.err (ErrorKind.VALUE);
                    return null;
                }
                if (order != 0) {
                    Gee.ArrayList<CubeMember>? by = null;
                    if (a.length > 4 && a[4].kind != NodeKind.MISSING) {
                        by = members_of (ev, cube, a[4], out err);
                        if (by == null) return null;
                    }
                    sort (cube, cs, order, by);
                }
            }
            return cs;
        }

        private static void sort (Cube cube, CubeSet cs, int order, Gee.List<CubeMember>? by) {
            var values = new Gee.HashMap<CubeTuple, Value> ();
            if (order <= 2) {
                foreach (var t in cs.tuples) {
                    var all = new Gee.ArrayList<CubeMember> ();
                    all.add_all (t.members);
                    if (by != null) all.add_all (by);
                    values[t] = cube.evaluate (all);
                }
            }
            cs.tuples.sort ((x, y) => {
                switch (order) {
                    case 1: return ArrayFunctions.sort_cmp (values[x], values[y], false);
                    case 2: return ArrayFunctions.sort_cmp (values[x], values[y], true);
                    case 3: return x.caption ().casefold ().collate (y.caption ().casefold ());
                    case 4: return y.caption ().casefold ().collate (x.caption ().casefold ());
                    case 5:
                    case 6:
                        var mx = x.members[0], my = y.members[0];
                        int c = mx.item != null && my.item != null ? ArrayFunctions.sort_cmp (mx.item, my.item, false) : 0;
                        return order == 5 ? c : -c;
                }
                return 0;
            });
        }

        private static CubeTuple? ranked (Evaluator ev, Cube cube, Node[] a, out Value? err) {
            var cs = set_of (ev, cube, { a[0], a[1] }, out err);
            if (cs == null) return null;
            int rank;
            var e = ev.arg_int (a[2], out rank);
            if (e != null) {
                err = e;
                return null;
            }
            if (rank < 1 || rank > cs.tuples.size) {
                err = Value.empty ();
                return null;
            }
            return cs.tuples[rank - 1];
        }

        private static Value caption_or (Evaluator ev, Node[] a, int i, string fallback) {
            if (a.length > i && a[i].kind != NodeKind.MISSING) {
                var v = ev.arg (a[i]);
                if (v.is_error ()) return v;
                return Value.str (Evaluator.to_text (v));
            }
            return Value.str (fallback);
        }

        public static void register () {
            add ("CUBEMEMBER", 2, 3, "CUBEMEMBER(connection, member_expression, [caption])", _("A member or tuple of the workbook data model"), (ev, a) => {
                Cube cube;
                var e = connect (ev, a[0], out cube);
                if (e != null) return e;
                Value? err;
                var ms = members_of (ev, cube, a[1], out err);
                if (ms == null || ms.size == 0) return err ?? Value.err (ErrorKind.NA);
                return caption_or (ev, a, 2, ms[ms.size - 1].caption);
            });
            add ("CUBEVALUE", 1, -1, "CUBEVALUE(connection, [member_expression1], ...)", _("An aggregated value from the workbook data model"), (ev, a) => {
                Cube cube;
                var e = connect (ev, a[0], out cube);
                if (e != null) return e;
                var all = new Gee.ArrayList<CubeMember> ();
                for (int i = 1; i < a.length; i++) {
                    if (a[i].kind == NodeKind.MISSING) continue;
                    Value? err;
                    var ms = members_of (ev, cube, a[i], out err);
                    if (ms == null) return err ?? Value.err (ErrorKind.NA);
                    all.add_all (ms);
                }
                return cube.evaluate (all);
            });
            add ("CUBESET", 2, 5, "CUBESET(connection, set_expression, [caption], [sort_order], [sort_by])", _("A set of members of the workbook data model"), (ev, a) => {
                Cube cube;
                var e = connect (ev, a[0], out cube);
                if (e != null) return e;
                Value? err;
                var cs = set_of (ev, cube, a, out err);
                if (cs == null) return err ?? Value.err (ErrorKind.NA);
                return Value.str (cs.caption);
            });
            add ("CUBESETCOUNT", 1, 1, "CUBESETCOUNT(set)", _("The number of items in a set"), (ev, a) => {
                Evaluator at;
                var f = cube_formula (ev, a[0], out at);
                if (f == null || !is_cube_call (f, "CUBESET") || f.args.length < 2) return Value.err (ErrorKind.VALUE);
                Cube cube;
                var e = connect (at, f.args[0], out cube);
                if (e != null) return e;
                Value? err;
                var cs = set_of (at, cube, f.args, out err);
                if (cs == null) return err ?? Value.err (ErrorKind.NA);
                return Value.num (cs.tuples.size);
            });
            add ("CUBERANKEDMEMBER", 3, 4, "CUBERANKEDMEMBER(connection, set_expression, rank, [caption])", _("The nth member of a set"), (ev, a) => {
                Cube cube;
                var e = connect (ev, a[0], out cube);
                if (e != null) return e;
                Value? err;
                var t = ranked (ev, cube, a, out err);
                if (t == null) return err ?? Value.err (ErrorKind.NA);
                return caption_or (ev, a, 3, t.caption ());
            });
            add ("CUBEMEMBERPROPERTY", 3, 3, "CUBEMEMBERPROPERTY(connection, member_expression, property)", _("A property of a data model member"), (ev, a) => {
                Cube cube;
                var e = connect (ev, a[0], out cube);
                if (e != null) return e;
                Value? err;
                var ms = members_of (ev, cube, a[1], out err);
                if (ms == null || ms.size == 0) return err ?? Value.err (ErrorKind.NA);
                var m = ms[ms.size - 1];
                string prop = ev.arg_text (a[2], out e);
                if (e != null) return e;
                switch (prop.up ()) {
                    case "MEMBER_CAPTION":
                    case "CAPTION":
                    case "MEMBER_NAME":
                    case "NAME":
                        return Value.str (m.caption);
                    case "MEMBER_UNIQUE_NAME":
                        return Value.str (m.unique_name ());
                    case "KEY":
                    case "MEMBER_KEY":
                        return m.item ?? Value.err (ErrorKind.NA);
                    case "LEVEL_NUMBER":
                        return Value.num (m.kind == CubeKind.MEMBER ? 1 : 0);
                }
                if (m.kind != CubeKind.MEMBER) return Value.err (ErrorKind.NA);
                string p = prop.has_prefix ("[") ? Mdx.parts (prop)[Mdx.parts (prop).length - 1] : prop;
                var mt = cube.model.table (m.table);
                int kc = mt.col (m.column), pc = mt.col (p);
                if (pc < 0) return Value.err (ErrorKind.NA);
                string k = DataModel.key (m.item);
                for (int r = 0; r < mt.rows; r++) if (DataModel.key (mt.at (r, kc)) == k) return mt.at (r, pc);
                return Value.err (ErrorKind.NA);
            });
            add ("CUBEKPIMEMBER", 3, 4, "CUBEKPIMEMBER(connection, kpi_name, kpi_property, [caption])", _("A key performance indicator of the data model"), (ev, a) => {
                Cube cube;
                var e = connect (ev, a[0], out cube);
                if (e != null) return e;
                Value? err;
                var m = kpi_member (ev, cube, a, out err);
                if (m == null) return err ?? Value.err (ErrorKind.NA);
                return caption_or (ev, a, 3, m.caption);
            });
        }
    }
}
