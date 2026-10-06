namespace Singularity.Apps.Spreadsheet {

    public enum SortBy {
        VALUE,
        CELL_COLOR,
        FONT_COLOR,
        ICON
    }

    public class SortLevel {
        public int index;
        public bool ascending = true;
        public SortBy by = SortBy.VALUE;
        public string color = "";
        public int icon = -1;
        public string icon_set = "";
        public string custom_list = "";

        public SortLevel (int index, bool ascending) {
            this.index = index;
            this.ascending = ascending;
        }

        public SortLevel copy () {
            var l = new SortLevel (index, ascending);
            l.by = by;
            l.color = color;
            l.icon = icon;
            l.icon_set = icon_set;
            l.custom_list = custom_list;
            return l;
        }
    }

    public class SortSpec {
        public Area area;
        public bool header = true;
        public bool columns;
        public bool case_sensitive;
        public Gee.ArrayList<SortLevel> levels = new Gee.ArrayList<SortLevel> ();

        public SortSpec (Area area) {
            this.area = area;
        }

        public SortSpec copy () {
            var s = new SortSpec (area.copy ());
            s.header = header;
            s.columns = columns;
            s.case_sensitive = case_sensitive;
            foreach (var l in levels) s.levels.add (l.copy ());
            return s;
        }
    }

    public const int MAX_SORT_LEVELS = 64;

    public class CustomLists {
        public static string[] builtin () {
            return {
                "Sun|Mon|Tue|Wed|Thu|Fri|Sat",
                "Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday",
                "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec",
                "January|February|March|April|May|June|July|August|September|October|November|December"
            };
        }

        private static Gee.ArrayList<string>? _user;

        public static Gee.ArrayList<string> user () {
            if (_user == null) _user = new Gee.ArrayList<string> ();
            return _user;
        }

        public static void set_user_text (string text) {
            user ().clear ();
            foreach (string part in text.split (";")) {
                string l = normalize (part);
                if (l != "" && !user ().contains (l)) user ().add (l);
            }
        }

        public static string user_text () {
            string[] out_l = {};
            foreach (string l in user ()) out_l += l.replace ("|", ", ");
            return string.joinv ("; ", out_l);
        }

        public static Gee.List<string> all (Workbook book) {
            var l = new Gee.ArrayList<string> ();
            foreach (string s in builtin ()) l.add (s);
            foreach (string s in user ()) if (!l.contains (s)) l.add (s);
            foreach (string s in book.custom_lists) if (!l.contains (s)) l.add (s);
            return l;
        }

        public static string encode (Gee.List<string> lists) {
            return string.joinv (";", lists.to_array ());
        }

        public static void decode (string text, Gee.List<string> into) {
            foreach (string l in text.split (";")) if (l.strip () != "") into.add (l);
        }

        public static int position (string list, string item) {
            string[] items = list.split ("|");
            string k = item.casefold ();
            for (int i = 0; i < items.length; i++) if (items[i].casefold () == k) return i;
            return -1;
        }

        public static string normalize (string text) {
            string[] items = {};
            foreach (string line in text.split_set ("\n,")) {
                string t = line.strip ();
                if (t != "") items += t.replace ("|", "/").replace (";", " ").replace ("\"", "'");
            }
            return string.joinv ("|", items);
        }
    }

    public class SortEngine {
        private static string fill_of (Workbook book, Sheet s, CondEval ce, int r, int c) {
            var cs = s.cond_formats.size > 0 ? ce.apply (r, c, s.value_at (r, c)) : null;
            if (cs != null && cs.fill != "") return cs.fill.down ();
            return s.style_at (r, c).fill.down ();
        }

        private static string font_of (Sheet s, CondEval ce, int r, int c) {
            var cs = s.cond_formats.size > 0 ? ce.apply (r, c, s.value_at (r, c)) : null;
            if (cs != null && cs.color != "") return cs.color.down ();
            return s.style_at (r, c).color.down ();
        }

        private static int icon_of (Sheet s, CondEval ce, int r, int c, out string set) {
            set = "";
            var cs = s.cond_formats.size > 0 ? ce.apply (r, c, s.value_at (r, c)) : null;
            if (cs == null) return -1;
            set = cs.icon_set;
            return cs.icon;
        }

        private static int compare_values (Value a, Value b, bool case_sensitive) {
            if (case_sensitive && a.kind == ValueKind.TEXT && b.kind == ValueKind.TEXT) {
                int c = a.text.casefold ().collate (b.text.casefold ());
                if (c != 0) return c;
                bool la = a.text.length > 0 && a.text.get_char (0).islower ();
                bool lb = b.text.length > 0 && b.text.get_char (0).islower ();
                if (la != lb) return la ? -1 : 1;
                return strcmp (b.text, a.text);
            }
            return Evaluator.compare (a, b);
        }

        public static int key_compare (Workbook book, Sheet s, CondEval ce, SortSpec spec, SortLevel lv, int ia, int ib) {
            int ra = spec.columns ? lv.index : ia, ca = spec.columns ? ia : lv.index;
            int rb = spec.columns ? lv.index : ib, cb = spec.columns ? ib : lv.index;
            switch (lv.by) {
                case SortBy.CELL_COLOR:
                case SortBy.FONT_COLOR:
                    string want = lv.color.down ();
                    string xa = lv.by == SortBy.CELL_COLOR ? fill_of (book, s, ce, ra, ca) : font_of (s, ce, ra, ca);
                    string xb = lv.by == SortBy.CELL_COLOR ? fill_of (book, s, ce, rb, cb) : font_of (s, ce, rb, cb);
                    bool ma = xa == want, mb = xb == want;
                    if (ma == mb) return 0;
                    return (ma ? -1 : 1) * (lv.ascending ? 1 : -1);
                case SortBy.ICON:
                    string sa, sb;
                    bool ma = icon_of (s, ce, ra, ca, out sa) == lv.icon;
                    bool mb = icon_of (s, ce, rb, cb, out sb) == lv.icon;
                    if (ma == mb) return 0;
                    return (ma ? -1 : 1) * (lv.ascending ? 1 : -1);
                default:
                    var va = s.value_at (ra, ca);
                    var vb = s.value_at (rb, cb);
                    bool ea = va.kind == ValueKind.EMPTY, eb = vb.kind == ValueKind.EMPTY;
                    if (ea && eb) return 0;
                    if (ea) return 1;
                    if (eb) return -1;
                    int c;
                    if (lv.custom_list != "") {
                        int pa = CustomLists.position (lv.custom_list, Evaluator.to_text (va));
                        int pb = CustomLists.position (lv.custom_list, Evaluator.to_text (vb));
                        if (pa < 0) pa = int.MAX;
                        if (pb < 0) pb = int.MAX;
                        c = pa == pb ? compare_values (va, vb, spec.case_sensitive) : (pa < pb ? -1 : 1);
                    } else {
                        c = compare_values (va, vb, spec.case_sensitive);
                    }
                    return lv.ascending ? c : -c;
            }
        }

        public static void sort (Document doc, Sheet s, SortSpec spec) {
            var area = Document.clamp_area (s, spec.area);
            if (area.r2 > s.max_row) area.r2 = int.max (s.max_row, area.r1);
            if (area.c2 > s.max_col) area.c2 = int.max (s.max_col, area.c1);
            int first = spec.columns ? (spec.header ? area.c1 + 1 : area.c1) : (spec.header ? area.r1 + 1 : area.r1);
            int last = spec.columns ? area.c2 : area.r2;
            if (first > last || spec.levels.size == 0) return;
            doc.begin_area (_("Sort"), s, area, spec.area);
            var ce = new CondEval (doc.book, s);
            var order = new Gee.ArrayList<int> ();
            for (int i = first; i <= last; i++) order.add (i);
            order.sort ((a, b) => {
                int n = 0;
                foreach (var lv in spec.levels) {
                    if (n++ >= MAX_SORT_LEVELS) break;
                    int c = key_compare (doc.book, s, ce, spec, lv, a, b);
                    if (c != 0) return c;
                }
                return a - b;
            });
            var moved = new Gee.ArrayList<CellCopy> ();
            for (int i = 0; i < order.size; i++) {
                int from = order[i];
                int to = first + i;
                int o1 = spec.columns ? area.r1 : area.c1;
                int o2 = spec.columns ? area.r2 : area.c2;
                for (int o = o1; o <= o2; o++) {
                    var cell = spec.columns ? s.get_cell (o, from) : s.get_cell (from, o);
                    if (cell == null) continue;
                    var cp = new CellCopy.of (cell);
                    if (spec.columns) {
                        if (cp.formula != null) cp.formula = Formula.shifted (cp.formula, 0, to - from);
                        cp.col = to;
                    } else {
                        if (cp.formula != null) cp.formula = Formula.shifted (cp.formula, to - from, 0);
                        cp.row = to;
                    }
                    moved.add (cp);
                }
            }
            for (int i = first; i <= last; i++) {
                int o1 = spec.columns ? area.r1 : area.c1;
                int o2 = spec.columns ? area.r2 : area.c2;
                for (int o = o1; o <= o2; o++) {
                    if (spec.columns) s.cells.unset (Sheet.key (o, i));
                    else s.cells.unset (Sheet.key (i, o));
                }
            }
            foreach (var cp in moved) {
                var cell = cp.restore ();
                if (cell.formula != null) cell.input = Formula.to_text (cell.formula, s);
                s.cells[Sheet.key (cell.row, cell.col)] = cell;
            }
            s.sort_state = spec.copy ();
            s.recompute_extent ();
            doc.book.structure_changed = true;
            doc.commit ();
        }
    }

    public enum FilterKind {
        VALUES,
        CUSTOM,
        TOP10,
        DYNAMIC,
        CELL_COLOR,
        FONT_COLOR,
        ICON
    }

    public class FilterRule {
        public FilterKind kind = FilterKind.VALUES;
        public string op1 = "";
        public string v1 = "";
        public string op2 = "";
        public string v2 = "";
        public bool and_join = true;
        public double top = 10;
        public bool percent;
        public bool bottom;
        public string dyn_type = "";
        public string color = "";
        public string icon_set = "";
        public int icon = -1;
        public Gee.HashSet<string> dates = new Gee.HashSet<string> ();
        public bool blanks = true;

        public FilterRule copy () {
            var r = new FilterRule ();
            r.kind = kind;
            r.op1 = op1;
            r.v1 = v1;
            r.op2 = op2;
            r.v2 = v2;
            r.and_join = and_join;
            r.top = top;
            r.percent = percent;
            r.bottom = bottom;
            r.dyn_type = dyn_type;
            r.color = color;
            r.icon_set = icon_set;
            r.icon = icon;
            r.dates.add_all (dates);
            r.blanks = blanks;
            return r;
        }
    }

    public class FilterEngine {
        public static string wildcard_of (string op, string v) {
            switch (op) {
                case "begins": return v + "*";
                case "ends": return "*" + v;
                case "contains": return "*" + v + "*";
                case "notcontains": return "*" + v + "*";
                default: return v;
            }
        }

        private static bool test_one (string op, string v, Value val) {
            if (op == "") return true;
            string pattern = wildcard_of (op, v);
            string cmp;
            switch (op) {
                case "notequal": case "notcontains": cmp = "<>"; break;
                case "greater": cmp = ">"; break;
                case "less": cmp = "<"; break;
                case "greaterequal": cmp = ">="; break;
                case "lessequal": cmp = "<="; break;
                default: cmp = "="; break;
            }
            var crit = new Criteria (Value.str (cmp + pattern));
            if (val.kind == ValueKind.EMPTY) return crit.matches (Value.str (""));
            return crit.matches (val);
        }

        private static double today () {
            return Math.floor (DateSerial.now ());
        }

        public static bool dynamic_range (string kind, out double from, out double to) {
            double t = today ();
            int y, m, d;
            DateSerial.to_ymd (t, out y, out m, out d);
            int ds = DateSerial.weekday (t);
            from = to = 0;
            int q = (m - 1) / 3;
            switch (kind) {
                case "today": from = t; to = t + 1; return true;
                case "yesterday": from = t - 1; to = t; return true;
                case "tomorrow": from = t + 1; to = t + 2; return true;
                case "thisWeek": from = t - ds; to = from + 7; return true;
                case "lastWeek": from = t - ds - 7; to = from + 7; return true;
                case "nextWeek": from = t - ds + 7; to = from + 7; return true;
                case "thisMonth": from = DateSerial.from_ymd (y, m, 1); to = DateSerial.from_ymd (y, m + 1, 1); return true;
                case "lastMonth": from = DateSerial.from_ymd (y, m - 1, 1); to = DateSerial.from_ymd (y, m, 1); return true;
                case "nextMonth": from = DateSerial.from_ymd (y, m + 1, 1); to = DateSerial.from_ymd (y, m + 2, 1); return true;
                case "thisQuarter": from = DateSerial.from_ymd (y, q * 3 + 1, 1); to = DateSerial.from_ymd (y, q * 3 + 4, 1); return true;
                case "lastQuarter": from = DateSerial.from_ymd (y, q * 3 - 2, 1); to = DateSerial.from_ymd (y, q * 3 + 1, 1); return true;
                case "nextQuarter": from = DateSerial.from_ymd (y, q * 3 + 4, 1); to = DateSerial.from_ymd (y, q * 3 + 7, 1); return true;
                case "thisYear": from = DateSerial.from_ymd (y, 1, 1); to = DateSerial.from_ymd (y + 1, 1, 1); return true;
                case "lastYear": from = DateSerial.from_ymd (y - 1, 1, 1); to = DateSerial.from_ymd (y, 1, 1); return true;
                case "nextYear": from = DateSerial.from_ymd (y + 1, 1, 1); to = DateSerial.from_ymd (y + 2, 1, 1); return true;
                case "yearToDate": from = DateSerial.from_ymd (y, 1, 1); to = t + 1; return true;
            }
            return false;
        }

        public static string date_key (double serial, int level) {
            int y, m, d;
            DateSerial.to_ymd (serial, out y, out m, out d);
            if (level == 0) return "%04d".printf (y);
            if (level == 1) return "%04d-%02d".printf (y, m);
            return "%04d-%02d-%02d".printf (y, m, d);
        }

        private static bool is_date (Sheet s, int r, int c, Value v) {
            return v.kind == ValueKind.NUMBER && NumberFormat.is_date_format (s.style_at (r, c).number_format);
        }

        public static bool keeps (Workbook book, Sheet s, Filter f, int col, FilterRule rule, int r, CondEval ce, Gee.List<double?> column) {
            var v = s.value_at (r, col);
            switch (rule.kind) {
                case FilterKind.CUSTOM:
                    bool a = test_one (rule.op1, rule.v1, v);
                    if (rule.op2 == "") return a;
                    bool b = test_one (rule.op2, rule.v2, v);
                    return rule.and_join ? a && b : a || b;
                case FilterKind.TOP10:
                    if (v.kind != ValueKind.NUMBER) return false;
                    var sorted = new Gee.ArrayList<double?> ();
                    sorted.add_all (column);
                    sorted.sort ((x, y) => {
                        double p = x, q = y;
                        return p < q ? 1 : (p > q ? -1 : 0);
                    });
                    if (rule.bottom) sorted.sort ((x, y) => {
                        double p = x, q = y;
                        return p < q ? -1 : (p > q ? 1 : 0);
                    });
                    int n = rule.percent ? (int) Math.ceil (sorted.size * rule.top / 100.0) : (int) rule.top;
                    n = n.clamp (1, int.max (sorted.size, 1));
                    if (sorted.size == 0) return false;
                    double edge = sorted[n - 1];
                    return rule.bottom ? v.number <= edge : v.number >= edge;
                case FilterKind.DYNAMIC:
                    if (rule.dyn_type == "aboveAverage" || rule.dyn_type == "belowAverage") {
                        if (v.kind != ValueKind.NUMBER || column.size == 0) return false;
                        double sum = 0;
                        foreach (var x in column) sum += x;
                        double avg = sum / column.size;
                        return rule.dyn_type == "aboveAverage" ? v.number > avg : v.number < avg;
                    }
                    if (v.kind != ValueKind.NUMBER) return false;
                    if (rule.dyn_type.has_prefix ("M") && rule.dyn_type.length <= 3) {
                        int y, m, d;
                        DateSerial.to_ymd (v.number, out y, out m, out d);
                        return m == int.parse (rule.dyn_type.substring (1));
                    }
                    if (rule.dyn_type.has_prefix ("Q") && rule.dyn_type.length == 2) {
                        int y, m, d;
                        DateSerial.to_ymd (v.number, out y, out m, out d);
                        return (m - 1) / 3 + 1 == int.parse (rule.dyn_type.substring (1));
                    }
                    double from, to;
                    if (!dynamic_range (rule.dyn_type, out from, out to)) return true;
                    return v.number >= from && v.number < to;
                case FilterKind.CELL_COLOR:
                    var cs = s.cond_formats.size > 0 ? ce.apply (r, col, v) : null;
                    string fill = cs != null && cs.fill != "" ? cs.fill : s.style_at (r, col).fill;
                    return fill.down () == rule.color.down ();
                case FilterKind.FONT_COLOR:
                    var cs2 = s.cond_formats.size > 0 ? ce.apply (r, col, v) : null;
                    string color = cs2 != null && cs2.color != "" ? cs2.color : s.style_at (r, col).color;
                    return color.down () == rule.color.down ();
                case FilterKind.ICON:
                    var cs3 = s.cond_formats.size > 0 ? ce.apply (r, col, v) : null;
                    return cs3 != null && cs3.icon == rule.icon;
                default:
                    if (rule.dates.size == 0) return true;
                    if (v.kind == ValueKind.EMPTY) return rule.blanks;
                    if (!is_date (s, r, col, v)) return true;
                    return rule.dates.contains (date_key (v.number, 0)) || rule.dates.contains (date_key (v.number, 1)) || rule.dates.contains (date_key (v.number, 2));
            }
        }

        public static void apply (Workbook book, Sheet s) {
            var f = s.filter;
            if (f == null || f.rules.size == 0) return;
            var ce = new CondEval (book, s);
            var columns = new Gee.HashMap<int, Gee.ArrayList<double?>> ();
            foreach (int col in f.rules.keys) {
                var nums = new Gee.ArrayList<double?> ();
                for (int r = f.area.r1 + 1; r <= f.area.r2; r++) {
                    var v = s.value_at (r, col);
                    if (v.kind == ValueKind.NUMBER) nums.add (v.number);
                }
                columns[col] = nums;
            }
            for (int r = f.area.r1 + 1; r <= f.area.r2; r++) {
                if (s.hidden_rows.contains (r)) continue;
                foreach (var e in f.rules.entries) {
                    if (!keeps (book, s, f, e.key, e.value, r, ce, columns[e.key])) {
                        s.hidden_rows.add (r);
                        break;
                    }
                }
            }
        }
    }

    public enum SeriesType {
        LINEAR,
        GROWTH,
        DATE,
        AUTOFILL
    }

    public enum DateUnit {
        DAY,
        WEEKDAY,
        MONTH,
        YEAR
    }

    public class SeriesFill {
        private static double add_date (double serial, DateUnit unit, double step, bool d1904) {
            int y, m, d;
            switch (unit) {
                case DateUnit.WEEKDAY:
                    double t = serial;
                    int n = (int) step;
                    int dir = n >= 0 ? 1 : -1;
                    for (int i = 0; i < n.abs (); i++) {
                        t += dir;
                        while (DateSerial.weekday (t) == 0 || DateSerial.weekday (t) == 6) t += dir;
                    }
                    return t;
                case DateUnit.MONTH:
                    DateSerial.to_ymd (serial, out y, out m, out d, d1904);
                    int nm = m + (int) step;
                    double last = DateSerial.from_ymd (y, nm + 1, 1, d1904) - 1;
                    int ly, lm, ld;
                    DateSerial.to_ymd (last, out ly, out lm, out ld, d1904);
                    return DateSerial.from_ymd (y, nm, int.min (d, ld), d1904) + (serial - Math.floor (serial));
                case DateUnit.YEAR:
                    DateSerial.to_ymd (serial, out y, out m, out d, d1904);
                    double end = DateSerial.from_ymd (y + (int) step, m + 1, 1, d1904) - 1;
                    int ey, em, ed;
                    DateSerial.to_ymd (end, out ey, out em, out ed, d1904);
                    return DateSerial.from_ymd (y + (int) step, m, int.min (d, ed), d1904) + (serial - Math.floor (serial));
                default:
                    return serial + step;
            }
        }

        public static int fill (Document doc, Sheet s, Area sel, bool rows, SeriesType type, DateUnit unit, double step, double? stop, bool trend) {
            var area = Document.clamp_area (s, sel);
            int lanes = rows ? area.rows : area.cols;
            int len = rows ? area.cols : area.rows;
            if (len < 1) return 0;
            doc.begin_area (_("Series"), s, area);
            int written = 0;
            for (int lane = 0; lane < lanes; lane++) {
                int r0 = rows ? area.r1 + lane : area.r1;
                int c0 = rows ? area.c1 : area.c1 + lane;
                var known = new Gee.ArrayList<double?> ();
                for (int k = 0; k < len; k++) {
                    var v = s.value_at (rows ? r0 : r0 + k, rows ? c0 + k : c0);
                    if (v.kind != ValueKind.NUMBER) break;
                    known.add (v.number);
                }
                if (known.size == 0) continue;
                double a = known[0], b = step;
                bool geometric = type == SeriesType.GROWTH;
                if (trend && known.size >= 2) {
                    int n = known.size;
                    if (!geometric) {
                        double sx = 0, sy = 0, sxy = 0, sxx = 0;
                        for (int i = 0; i < n; i++) {
                            sx += i;
                            sy += known[i];
                            sxy += i * known[i];
                            sxx += i * i;
                        }
                        b = (n * sxy - sx * sy) / (n * sxx - sx * sx);
                        a = (sy - b * sx) / n;
                    } else {
                        double sx = 0, sy = 0, sxy = 0, sxx = 0;
                        for (int i = 0; i < n; i++) {
                            double ly = Math.log (known[i]);
                            sx += i;
                            sy += ly;
                            sxy += i * ly;
                            sxx += i * i;
                        }
                        double lb = (n * sxy - sx * sy) / (n * sxx - sx * sx);
                        double la = (sy - lb * sx) / n;
                        a = Math.exp (la);
                        b = Math.exp (lb);
                    }
                }
                int start = trend ? 0 : 1;
                double cur = known[0];
                for (int k = start; k < len; k++) {
                    double val;
                    if (trend) val = geometric ? a * Math.pow (b, k) : a + b * k;
                    else if (type == SeriesType.DATE) val = add_date (cur, unit, step, doc.book.date1904);
                    else if (geometric) val = cur * step;
                    else val = cur + step;
                    if (stop != null && ((step >= 0 && val > stop) || (step < 0 && val < stop))) break;
                    int r = rows ? r0 : r0 + k, c = rows ? c0 + k : c0;
                    var cell = s.ensure (r, c);
                    int style = s.get_cell (r0, c0) != null ? s.get_cell (r0, c0).style : 0;
                    s.set_input (r, c, Value.format_number_general_full (val));
                    if (cell.style == 0) cell.style = style;
                    cur = val;
                    written++;
                }
            }
            s.recompute_extent ();
            doc.commit ();
            return written;
        }
    }
}
