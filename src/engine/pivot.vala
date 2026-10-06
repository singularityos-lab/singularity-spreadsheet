namespace Singularity.Apps.Spreadsheet {

    public enum PivotAgg {
        SUM,
        COUNT,
        AVERAGE,
        MAX,
        MIN,
        PRODUCT,
        COUNT_NUMS,
        STDEV,
        STDEVP,
        VAR,
        VARP;

        public string label () {
            switch (this) {
                case COUNT: return _("Count");
                case AVERAGE: return _("Average");
                case MAX: return _("Max");
                case MIN: return _("Min");
                case PRODUCT: return _("Product");
                case COUNT_NUMS: return _("Count Numbers");
                case STDEV: return _("StdDev");
                case STDEVP: return _("StdDevp");
                case VAR: return _("Var");
                case VARP: return _("Varp");
                default: return _("Sum");
            }
        }

        public string key () {
            switch (this) {
                case COUNT: return "count";
                case AVERAGE: return "average";
                case MAX: return "max";
                case MIN: return "min";
                case PRODUCT: return "product";
                case COUNT_NUMS: return "countNums";
                case STDEV: return "stdDev";
                case STDEVP: return "stdDevp";
                case VAR: return "var";
                case VARP: return "varp";
                default: return "sum";
            }
        }

        public static PivotAgg from_key (string k) {
            foreach (var a in all ()) if (a.key () == k) return a;
            return SUM;
        }

        public static PivotAgg[] all () {
            return { SUM, COUNT, AVERAGE, MAX, MIN, PRODUCT, COUNT_NUMS, STDEV, STDEVP, VAR, VARP };
        }
    }

    public enum PivotShow {
        NORMAL,
        PERCENT_TOTAL,
        PERCENT_ROW,
        PERCENT_COL,
        RUNNING_TOTAL,
        DIFFERENCE,
        PERCENT_DIFFERENCE,
        RANK;

        public string label () {
            switch (this) {
                case PERCENT_TOTAL: return _("% of Grand Total");
                case PERCENT_ROW: return _("% of Row Total");
                case PERCENT_COL: return _("% of Column Total");
                case RUNNING_TOTAL: return _("Running Total");
                case DIFFERENCE: return _("Difference From Previous");
                case PERCENT_DIFFERENCE: return _("% Difference From Previous");
                case RANK: return _("Rank Largest to Smallest");
                default: return _("No Calculation");
            }
        }

        public static PivotShow[] all () {
            return { NORMAL, PERCENT_TOTAL, PERCENT_ROW, PERCENT_COL, RUNNING_TOTAL, DIFFERENCE, PERCENT_DIFFERENCE, RANK };
        }
    }

    public enum PivotGroup {
        NONE,
        YEARS,
        QUARTERS,
        MONTHS,
        DAYS,
        INTERVAL;

        public string label () {
            switch (this) {
                case YEARS: return _("Years");
                case QUARTERS: return _("Quarters");
                case MONTHS: return _("Months");
                case DAYS: return _("Days");
                case INTERVAL: return _("Number Interval");
                default: return _("No Grouping");
            }
        }

        public static PivotGroup[] all () {
            return { NONE, YEARS, QUARTERS, MONTHS, DAYS, INTERVAL };
        }
    }

    public class PivotField {
        public int source_col;
        public string name;
        public PivotGroup group = PivotGroup.NONE;
        public double interval_start = 0;
        public double interval_size = 10;
        public bool descending;
        public Gee.HashSet<string> hidden = new Gee.HashSet<string> ();

        public PivotField (int source_col, string name) {
            this.source_col = source_col;
            this.name = name;
        }

        public PivotField copy () {
            var f = new PivotField (source_col, name);
            f.group = group;
            f.interval_start = interval_start;
            f.interval_size = interval_size;
            f.descending = descending;
            foreach (var h in hidden) f.hidden.add (h);
            return f;
        }
    }

    public class PivotValue {
        public int source_col;
        public string name;
        public PivotAgg agg = PivotAgg.SUM;
        public PivotShow show = PivotShow.NORMAL;
        public string number_format = "";

        public PivotValue (int source_col, string name, PivotAgg agg) {
            this.source_col = source_col;
            this.name = name;
            this.agg = agg;
        }

        public string caption () {
            string c = _("%s of %s").printf (agg.label (), name);
            if (show != PivotShow.NORMAL) c += " (" + show.label () + ")";
            return c;
        }

        public PivotValue copy () {
            var v = new PivotValue (source_col, name, agg);
            v.show = show;
            v.number_format = number_format;
            return v;
        }
    }

    public class PivotItem {
        public string label;
        public double sort_num;
        public bool numeric;

        public PivotItem (string label, double sort_num, bool numeric) {
            this.label = label;
            this.sort_num = sort_num;
            this.numeric = numeric;
        }

        public static int compare (PivotItem a, PivotItem b) {
            if (a.numeric && b.numeric) return a.sort_num < b.sort_num ? -1 : (a.sort_num > b.sort_num ? 1 : 0);
            if (a.numeric != b.numeric) return a.numeric ? -1 : 1;
            if (a.label == "") return 1;
            if (b.label == "") return -1;
            int primary = strcmp (sort_key (a.label), sort_key (b.label));
            if (primary != 0) return primary;
            return a.label.collate (b.label);
        }

        public static string sort_key (string label) {
            string n = label.normalize (-1, NormalizeMode.ALL).casefold ();
            var sb = new StringBuilder ();
            int i = 0;
            unichar c;
            while (n.get_next_char (ref i, out c)) {
                var t = c.type ();
                if (t == UnicodeType.NON_SPACING_MARK || t == UnicodeType.SPACING_MARK || t == UnicodeType.ENCLOSING_MARK) continue;
                if (c == 0x00DF) {
                    sb.append ("ss");
                    continue;
                }
                sb.append_unichar (c);
            }
            return sb.str;
        }
    }

    public class PivotAcc {
        public int count;
        public int nums;
        public double sum;
        public double sumsq;
        public double min = double.INFINITY;
        public double max = -double.INFINITY;
        public double product = 1;

        public void add (Value v) {
            if (v.kind == ValueKind.EMPTY) return;
            count++;
            if (v.kind != ValueKind.NUMBER) return;
            double d = v.number;
            nums++;
            sum += d;
            sumsq += d * d;
            if (d < min) min = d;
            if (d > max) max = d;
            product *= d;
        }

        public Value result (PivotAgg agg) {
            switch (agg) {
                case PivotAgg.COUNT: return Value.num (count);
                case PivotAgg.COUNT_NUMS: return Value.num (nums);
                case PivotAgg.AVERAGE: return nums == 0 ? Value.err (ErrorKind.DIV0) : Value.num (sum / nums);
                case PivotAgg.MAX: return Value.num (nums == 0 ? 0 : max);
                case PivotAgg.MIN: return Value.num (nums == 0 ? 0 : min);
                case PivotAgg.PRODUCT: return Value.num (nums == 0 ? 0 : product);
                case PivotAgg.STDEV:
                case PivotAgg.VAR:
                    if (nums < 2) return Value.err (ErrorKind.DIV0);
                    double vs = (sumsq - sum * sum / nums) / (nums - 1);
                    if (vs < 0) vs = 0;
                    return Value.num (agg == PivotAgg.VAR ? vs : Math.sqrt (vs));
                case PivotAgg.STDEVP:
                case PivotAgg.VARP:
                    if (nums < 1) return Value.err (ErrorKind.DIV0);
                    double vp = (sumsq - sum * sum / nums) / nums;
                    if (vp < 0) vp = 0;
                    return Value.num (agg == PivotAgg.VARP ? vp : Math.sqrt (vp));
                default: return Value.num (sum);
            }
        }
    }

    public class PivotOutput {
        public Value[,] cells;
        public int header_rows;
        public int label_cols;
        public Gee.HashSet<int> total_rows = new Gee.HashSet<int> ();
        public Gee.HashSet<int> total_cols = new Gee.HashSet<int> ();
        public Gee.HashMap<int, string> col_formats = new Gee.HashMap<int, string> ();
    }

    public class PivotTable {
        public string name;
        public Sheet? source_sheet;
        public Area? source;
        public string source_table = "";
        public Sheet target_sheet;
        public int target_row;
        public int target_col;
        public Gee.ArrayList<PivotField> rows = new Gee.ArrayList<PivotField> ();
        public Gee.ArrayList<PivotField> cols = new Gee.ArrayList<PivotField> ();
        public Gee.ArrayList<PivotValue> values = new Gee.ArrayList<PivotValue> ();
        public Gee.ArrayList<PivotField> filters = new Gee.ArrayList<PivotField> ();
        public bool row_grand = true;
        public bool col_grand = true;
        public bool subtotals = true;
        public Area? last_output;
        public string error = "";

        public PivotTable (string name, Sheet target_sheet, int target_row, int target_col) {
            this.name = name;
            this.target_sheet = target_sheet;
            this.target_row = target_row;
            this.target_col = target_col;
        }

        public Area? source_area (Workbook book) {
            if (source_table != "") {
                var t = Tables.find (book, source_table);
                if (t != null) {
                    int r1 = t.header_row ? t.area.r1 : t.data_r1;
                    return new Area (t.sheet, r1, t.area.c1, t.data_r2, t.area.c2);
                }
            }
            if (source == null) return null;
            var s = source.sheet ?? source_sheet;
            int r2 = source.r2;
            int c2 = source.c2;
            if (s != null) {
                if (r2 > s.max_row) r2 = int.max (s.max_row, source.r1);
                if (c2 > s.max_col) c2 = int.max (s.max_col, source.c1);
            }
            return new Area (s, source.r1, source.c1, r2, c2);
        }

        public string[] headers (Workbook book) {
            string[] h = {};
            var a = source_area (book);
            if (a == null) return h;
            for (int c = a.c1; c <= a.c2; c++) {
                string t = a.sheet.value_at (a.r1, c).display ();
                h += t != "" ? t : _("Column %s").printf (Address.column_name (c));
            }
            return h;
        }

        public Gee.ArrayList<PivotItem> field_items (Workbook book, int source_col, PivotGroup group = PivotGroup.NONE, double istart = 0, double isize = 10) {
            var f = new PivotField (source_col, "");
            f.group = group;
            f.interval_start = istart;
            f.interval_size = isize;
            var seen = new Gee.HashMap<string, PivotItem> ();
            var a = source_area (book);
            if (a != null) {
                for (int r = a.r1 + 1; r <= a.r2; r++) {
                    var it = item_of (f, a.sheet.value_at (r, a.c1 + source_col), book);
                    if (!seen.has_key (it.label)) seen[it.label] = it;
                }
            }
            var list = new Gee.ArrayList<PivotItem> ();
            list.add_all (seen.values);
            list.sort ((x, y) => PivotItem.compare (x, y));
            return list;
        }

        public static string[] month_names () {
            return { _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun"), _("Jul"), _("Aug"), _("Sep"), _("Oct"), _("Nov"), _("Dec") };
        }

        public static PivotItem item_of (PivotField f, Value v, Workbook book) {
            if (v.kind == ValueKind.EMPTY) return new PivotItem (_("(blank)"), double.MAX, false);
            if (f.group != PivotGroup.NONE && v.kind == ValueKind.NUMBER) {
                double d = v.number;
                if (f.group == PivotGroup.INTERVAL) {
                    double size = f.interval_size > 0 ? f.interval_size : 1;
                    double lo = f.interval_start + Math.floor ((d - f.interval_start) / size) * size;
                    string label = "%s-%s".printf (Value.format_number_general (lo), Value.format_number_general (lo + size - (size >= 1 && Math.floor (size) == size ? 1 : 0)));
                    return new PivotItem (label, lo, true);
                }
                int y, m, dd;
                DateSerial.to_ymd (d, out y, out m, out dd);
                switch (f.group) {
                    case PivotGroup.YEARS: return new PivotItem (y.to_string (), y, true);
                    case PivotGroup.QUARTERS: return new PivotItem ("Qtr%d".printf ((m - 1) / 3 + 1), (m - 1) / 3 + 1, true);
                    case PivotGroup.MONTHS: return new PivotItem (month_names ()[(m - 1).clamp (0, 11)], m, true);
                    default: return new PivotItem ("%d-%s".printf (dd, month_names ()[(m - 1).clamp (0, 11)]), m * 100 + dd, true);
                }
            }
            if (v.kind == ValueKind.NUMBER) return new PivotItem (Value.format_number_general (v.number), v.number, true);
            return new PivotItem (v.display (), 0, false);
        }

        private class Record {
            public PivotItem[] row_items;
            public PivotItem[] col_items;
            public Value[] vals;
        }

        private class KeyNode {
            public PivotItem? item;
            public string path;
            public Gee.ArrayList<KeyNode> children = new Gee.ArrayList<KeyNode> ();
            public Gee.HashMap<string, KeyNode> index = new Gee.HashMap<string, KeyNode> ();

            public KeyNode child_for (PivotItem it, string prefix) {
                var n = index[it.label];
                if (n == null) {
                    n = new KeyNode ();
                    n.item = it;
                    n.path = prefix + "\x1f" + it.label;
                    index[it.label] = n;
                    children.add (n);
                }
                return n;
            }

            public void sort (Gee.List<PivotField> fields, int level) {
                if (level >= fields.size) return;
                bool desc = fields[level].descending;
                children.sort ((a, b) => desc ? PivotItem.compare (b.item, a.item) : PivotItem.compare (a.item, b.item));
                foreach (var c in children) c.sort (fields, level + 1);
            }
        }

        private class Line {
            public string path;
            public int level;
            public bool total;
            public bool grand;
            public PivotItem[] items;
        }

        private static void flatten (KeyNode node, int level, int depth, bool subtotals, PivotItem[] prefix, Gee.ArrayList<Line> out_lines) {
            foreach (var c in node.children) {
                PivotItem[] items = prefix;
                items += c.item;
                if (level + 1 == depth) {
                    var l = new Line ();
                    l.path = c.path;
                    l.level = level;
                    l.items = items;
                    out_lines.add (l);
                } else {
                    flatten (c, level + 1, depth, subtotals, items, out_lines);
                    if (subtotals) {
                        var t = new Line ();
                        t.path = c.path;
                        t.level = level;
                        t.total = true;
                        t.items = items;
                        out_lines.add (t);
                    }
                }
            }
        }

        public PivotOutput? compute (Workbook book) {
            error = "";
            var a = source_area (book);
            if (a == null || a.rows < 1) {
                error = _("The source range is not valid.");
                return null;
            }
            var records = new Gee.ArrayList<Record> ();
            var rtree = new KeyNode ();
            rtree.path = "";
            var ctree = new KeyNode ();
            ctree.path = "";
            var s = a.sheet;
            for (int r = a.r1 + 1; r <= a.r2; r++) {
                bool keep = true;
                bool blank_row = true;
                for (int c = a.c1; c <= a.c2 && blank_row; c++) if (!s.value_at (r, c).is_empty ()) blank_row = false;
                if (blank_row) continue;
                foreach (var f in filters) {
                    if (f.hidden.contains (item_of (f, s.value_at (r, a.c1 + f.source_col), book).label)) keep = false;
                }
                if (!keep) continue;
                var rec = new Record ();
                PivotItem[] ri = {};
                foreach (var f in rows) {
                    var it = item_of (f, s.value_at (r, a.c1 + f.source_col), book);
                    if (f.hidden.contains (it.label)) keep = false;
                    ri += it;
                }
                PivotItem[] ci = {};
                foreach (var f in cols) {
                    var it = item_of (f, s.value_at (r, a.c1 + f.source_col), book);
                    if (f.hidden.contains (it.label)) keep = false;
                    ci += it;
                }
                if (!keep) continue;
                rec.row_items = ri;
                rec.col_items = ci;
                Value[] vals = {};
                foreach (var v in values) vals += s.value_at (r, a.c1 + v.source_col);
                rec.vals = vals;
                records.add (rec);
                var node = rtree;
                foreach (var it in ri) node = node.child_for (it, node.path);
                node = ctree;
                foreach (var it in ci) node = node.child_for (it, node.path);
            }
            rtree.sort (rows, 0);
            ctree.sort (cols, 0);
            var accs = new Gee.HashMap<string, PivotAcc> ();
            foreach (var rec in records) {
                string[] rpaths = { "" };
                string p = "";
                foreach (var it in rec.row_items) {
                    p += "\x1f" + it.label;
                    rpaths += p;
                }
                string[] cpaths = { "" };
                p = "";
                foreach (var it in rec.col_items) {
                    p += "\x1f" + it.label;
                    cpaths += p;
                }
                foreach (string rp in rpaths) {
                    foreach (string cp in cpaths) {
                        for (int vi = 0; vi < values.size; vi++) {
                            string k = "%s\x1e%s\x1e%d".printf (rp, cp, vi);
                            var acc = accs[k];
                            if (acc == null) {
                                acc = new PivotAcc ();
                                accs[k] = acc;
                            }
                            acc.add (rec.vals[vi]);
                        }
                    }
                }
            }
            var rlines = new Gee.ArrayList<Line> ();
            if (rows.size > 0) flatten (rtree, 0, rows.size, subtotals, {}, rlines);
            if (rows.size == 0 || row_grand) {
                var g = new Line ();
                g.path = "";
                g.grand = true;
                g.total = true;
                g.items = {};
                rlines.add (g);
            }
            var clines = new Gee.ArrayList<Line> ();
            if (cols.size > 0) flatten (ctree, 0, cols.size, subtotals, {}, clines);
            if (cols.size == 0 || col_grand) {
                var g = new Line ();
                g.path = "";
                g.grand = true;
                g.total = true;
                g.items = {};
                clines.add (g);
            }
            int nv = int.max (values.size, 1);
            int label_cols = int.max (rows.size, 1);
            int header_rows = cols.size == 0 ? 1 : cols.size + 1 + (nv > 1 ? 1 : 0);
            int data_cols = clines.size * nv;
            var outp = new PivotOutput ();
            outp.header_rows = header_rows;
            outp.label_cols = label_cols;
            int total_r = header_rows + rlines.size;
            int total_c = label_cols + data_cols;
            var m = new Value[total_r, total_c];
            for (int i = 0; i < total_r; i++) for (int j = 0; j < total_c; j++) m[i, j] = Value.empty ();
            for (int i = 0; i < rows.size; i++) m[header_rows - 1, i] = Value.str (rows[i].name);
            if (cols.size > 0) {
                m[0, 0] = Value.str (values.size == 1 ? values[0].caption () : _("Values"));
                string[] cn = {};
                foreach (var cf in cols) cn += cf.name;
                m[0, label_cols] = Value.str (string.joinv (", ", cn));
            }
            for (int ci = 0; ci < clines.size; ci++) {
                var cl = clines[ci];
                for (int vi = 0; vi < nv; vi++) {
                    int col = label_cols + ci * nv + vi;
                    if (cl.total && cols.size > 0) outp.total_cols.add (col);
                    if (values.size > vi && values[vi].number_format != "") outp.col_formats[col] = values[vi].number_format;
                    if (cols.size > 0 && vi == 0) {
                        if (cl.grand) {
                            m[1, col] = Value.str (_("Grand Total"));
                        } else if (cl.total) {
                            m[cl.level + 1, col] = Value.str (_("%s Total").printf (cl.items[cl.level].label));
                        } else {
                            for (int lv = 0; lv < cl.items.length; lv++) {
                                bool same = ci > 0 && !clines[ci - 1].total && clines[ci - 1].items.length > lv;
                                if (same) for (int k = 0; k <= lv; k++) if (clines[ci - 1].items[k].label != cl.items[k].label) same = false;
                                if (same && lv < cl.items.length - 1) continue;
                                var it = cl.items[lv];
                                m[lv + 1, col] = it.numeric && cols[lv].group == PivotGroup.NONE ? Value.num (it.sort_num) : Value.str (it.label);
                            }
                        }
                    }
                    if (values.size > vi && (nv > 1 || cols.size == 0)) m[header_rows - 1, col] = Value.str (values[vi].caption ());
                }
            }
            PivotItem[]? prev = null;
            for (int ri = 0; ri < rlines.size; ri++) {
                var rl = rlines[ri];
                int row = header_rows + ri;
                if (rl.grand) {
                    m[row, 0] = Value.str (_("Grand Total"));
                    outp.total_rows.add (row);
                } else if (rl.total) {
                    m[row, rl.level] = Value.str (_("%s Total").printf (rl.items[rl.level].label));
                    outp.total_rows.add (row);
                } else {
                    for (int lv = 0; lv < rl.items.length; lv++) {
                        bool same = prev != null && prev.length > lv;
                        if (same) for (int k = 0; k <= lv; k++) if (prev[k].label != rl.items[k].label) same = false;
                        if (!same || lv == rl.items.length - 1) {
                            var it = rl.items[lv];
                            m[row, lv] = it.numeric && rows[lv].group == PivotGroup.NONE ? Value.num (it.sort_num) : Value.str (it.label);
                        }
                    }
                    prev = rl.items;
                }
                if (rl.total) prev = null;
                for (int ci = 0; ci < clines.size; ci++) {
                    for (int vi = 0; vi < values.size; vi++) {
                        string k = "%s\x1e%s\x1e%d".printf (rl.path, clines[ci].path, vi);
                        var acc = accs[k];
                        m[row, label_cols + ci * nv + vi] = acc != null ? acc.result (values[vi].agg) : Value.empty ();
                    }
                }
            }
            apply_show (m, rlines, clines, header_rows, label_cols, nv);
            outp.cells = m;
            return outp;
        }

        public Value get_data (Workbook book, string data_field, string[] fields, Value[] items) {
            PivotValue? pv = null;
            string df = data_field.strip ().casefold ();
            foreach (var v in values) if (v.name.casefold () == df || v.caption ().casefold () == df) pv = v;
            if (pv == null) return Value.err (ErrorKind.REF);
            var a = source_area (book);
            if (a == null) return Value.err (ErrorKind.REF);
            var used = new Gee.ArrayList<PivotField> ();
            used.add_all (rows);
            used.add_all (cols);
            var match = new PivotField[fields.length];
            for (int i = 0; i < fields.length; i++) {
                foreach (var f in used) if (f.name.casefold () == fields[i].strip ().casefold ()) match[i] = f;
                if (match[i] == null) return Value.err (ErrorKind.REF);
            }
            var acc = new PivotAcc ();
            bool any = false;
            var s = a.sheet;
            for (int r = a.r1 + 1; r <= a.r2; r++) {
                bool keep = true;
                foreach (var f in filters) if (f.hidden.contains (item_of (f, s.value_at (r, a.c1 + f.source_col), book).label)) keep = false;
                foreach (var f in used) if (keep && f.hidden.size > 0 && f.hidden.contains (item_of (f, s.value_at (r, a.c1 + f.source_col), book).label)) keep = false;
                for (int i = 0; i < fields.length && keep; i++) {
                    var it = item_of (match[i], s.value_at (r, a.c1 + match[i].source_col), book);
                    var want = items[i];
                    bool eq = it.label.casefold () == want.display ().casefold ();
                    if (!eq && want.kind == ValueKind.NUMBER && it.numeric) eq = it.sort_num == want.number;
                    if (!eq) keep = false;
                }
                if (!keep) continue;
                any = true;
                acc.add (s.value_at (r, a.c1 + pv.source_col));
            }
            if (!any) return Value.err (ErrorKind.REF);
            return acc.result (pv.agg);
        }

        private void apply_show (Value[,] m, Gee.ArrayList<Line> rlines, Gee.ArrayList<Line> clines, int hr, int lc, int nv) {
            for (int vi = 0; vi < values.size; vi++) {
                var show = values[vi].show;
                if (show == PivotShow.NORMAL) continue;
                int gr = -1, gc = -1;
                for (int i = 0; i < rlines.size; i++) if (rlines[i].grand) gr = hr + i;
                for (int j = 0; j < clines.size; j++) if (clines[j].grand) gc = lc + j * nv + vi;
                var orig = new double[rlines.size, clines.size];
                var has = new bool[rlines.size, clines.size];
                for (int i = 0; i < rlines.size; i++) {
                    for (int j = 0; j < clines.size; j++) {
                        var v = m[hr + i, lc + j * nv + vi];
                        has[i, j] = v.kind == ValueKind.NUMBER;
                        orig[i, j] = has[i, j] ? v.number : 0;
                    }
                }
                double grand = 0;
                if (gr >= 0 && gc >= 0 && m[gr, gc].kind == ValueKind.NUMBER) grand = m[gr, gc].number;
                for (int j = 0; j < clines.size; j++) {
                    double running = 0;
                    int prev_i = -1;
                    for (int i = 0; i < rlines.size; i++) {
                        if (!has[i, j]) continue;
                        int col = lc + j * nv + vi;
                        double v = orig[i, j];
                        switch (show) {
                            case PivotShow.PERCENT_TOTAL:
                                m[hr + i, col] = grand == 0 ? Value.err (ErrorKind.DIV0) : Value.num (v / grand);
                                break;
                            case PivotShow.PERCENT_ROW:
                                double rt = gc >= 0 ? orig[i, (gc - lc - vi) / nv] : 0;
                                m[hr + i, col] = rt == 0 ? Value.err (ErrorKind.DIV0) : Value.num (v / rt);
                                break;
                            case PivotShow.PERCENT_COL:
                                double ct = gr >= 0 ? orig[gr - hr, j] : 0;
                                m[hr + i, col] = ct == 0 ? Value.err (ErrorKind.DIV0) : Value.num (v / ct);
                                break;
                            case PivotShow.RUNNING_TOTAL:
                                if (rlines[i].total) break;
                                running += v;
                                m[hr + i, col] = Value.num (running);
                                break;
                            case PivotShow.DIFFERENCE:
                            case PivotShow.PERCENT_DIFFERENCE:
                                if (rlines[i].total) break;
                                if (prev_i < 0) m[hr + i, col] = Value.empty ();
                                else if (show == PivotShow.DIFFERENCE) m[hr + i, col] = Value.num (v - orig[prev_i, j]);
                                else m[hr + i, col] = orig[prev_i, j] == 0 ? Value.err (ErrorKind.DIV0) : Value.num ((v - orig[prev_i, j]) / orig[prev_i, j]);
                                prev_i = i;
                                break;
                            case PivotShow.RANK:
                                if (rlines[i].total) {
                                    m[hr + i, col] = Value.empty ();
                                    break;
                                }
                                int rank = 1;
                                for (int k = 0; k < rlines.size; k++) if (!rlines[k].total && has[k, j] && orig[k, j] > v) rank++;
                                m[hr + i, col] = Value.num (rank);
                                break;
                            default:
                                break;
                        }
                    }
                }
                if (show == PivotShow.PERCENT_TOTAL || show == PivotShow.PERCENT_ROW || show == PivotShow.PERCENT_COL || show == PivotShow.PERCENT_DIFFERENCE) {
                    if (values[vi].number_format == "") values[vi].number_format = "0.00%";
                }
            }
        }
    }
}
