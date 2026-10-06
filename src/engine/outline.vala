namespace Singularity.Apps.Spreadsheet {

    public const int MAX_OUTLINE = 7;

    public class OutlineGroup {
        public int start;
        public int end;
        public int level;
        public int summary;
        public bool collapsed;

        public OutlineGroup (int start, int end, int level, int summary, bool collapsed) {
            this.start = start;
            this.end = end;
            this.level = level;
            this.summary = summary;
            this.collapsed = collapsed;
        }
    }

    public class Outline {
        public Gee.HashMap<int, int> row_levels = new Gee.HashMap<int, int> ();
        public Gee.HashMap<int, int> col_levels = new Gee.HashMap<int, int> ();
        public Gee.HashSet<int> collapsed_rows = new Gee.HashSet<int> ();
        public Gee.HashSet<int> collapsed_cols = new Gee.HashSet<int> ();
        public bool summary_below = true;
        public bool summary_right = true;

        public Outline copy () {
            var o = new Outline ();
            foreach (var e in row_levels.entries) o.row_levels[e.key] = e.value;
            foreach (var e in col_levels.entries) o.col_levels[e.key] = e.value;
            o.collapsed_rows.add_all (collapsed_rows);
            o.collapsed_cols.add_all (collapsed_cols);
            o.summary_below = summary_below;
            o.summary_right = summary_right;
            return o;
        }

        public Gee.HashMap<int, int> levels (bool rows) {
            return rows ? row_levels : col_levels;
        }

        public Gee.HashSet<int> collapsed (bool rows) {
            return rows ? collapsed_rows : collapsed_cols;
        }

        public bool summary_after (bool rows) {
            return rows ? summary_below : summary_right;
        }

        public int level_of (bool rows, int i) {
            var m = levels (rows);
            return m.has_key (i) ? m[i] : 0;
        }

        public int max_level (bool rows) {
            int mx = 0;
            foreach (int v in levels (rows).values) mx = int.max (mx, v);
            return mx;
        }

        public bool is_empty () {
            return row_levels.size == 0 && col_levels.size == 0;
        }

        public void group (bool rows, int a, int b) {
            var m = levels (rows);
            for (int i = a; i <= b; i++) {
                int l = level_of (rows, i);
                if (l < MAX_OUTLINE) m[i] = l + 1;
            }
        }

        public void ungroup (bool rows, int a, int b) {
            var m = levels (rows);
            for (int i = a; i <= b; i++) {
                int l = level_of (rows, i);
                if (l <= 1) m.unset (i);
                else m[i] = l - 1;
            }
            var c = collapsed (rows);
            var drop = new Gee.ArrayList<int> ();
            foreach (int k in c) {
                bool still = false;
                foreach (var g in groups (rows)) if (g.summary == k) still = true;
                if (!still) drop.add (k);
            }
            foreach (int k in drop) c.remove (k);
        }

        public void clear (bool rows) {
            levels (rows).clear ();
            collapsed (rows).clear ();
        }

        public Gee.List<OutlineGroup> groups (bool rows) {
            var result = new Gee.ArrayList<OutlineGroup> ();
            var m = levels (rows);
            if (m.size == 0) return result;
            var keys = new Gee.ArrayList<int> ();
            keys.add_all (m.keys);
            keys.sort ((x, y) => x - y);
            int mx = max_level (rows);
            bool after = summary_after (rows);
            for (int lv = 1; lv <= mx; lv++) {
                int start = -1, prev = -2;
                foreach (int k in keys) {
                    if (m[k] >= lv) {
                        if (start < 0 || k != prev + 1) {
                            if (start >= 0) result.add (make (rows, start, prev, lv, after));
                            start = k;
                        }
                        prev = k;
                    }
                }
                if (start >= 0) result.add (make (rows, start, prev, lv, after));
            }
            return result;
        }

        private OutlineGroup make (bool rows, int a, int b, int lv, bool after) {
            int summary = after ? b + 1 : a - 1;
            return new OutlineGroup (a, b, lv, summary, collapsed (rows).contains (summary));
        }

        public OutlineGroup? group_for_summary (bool rows, int summary, int lv = -1) {
            OutlineGroup? best = null;
            foreach (var g in groups (rows)) {
                if (g.summary != summary) continue;
                if (lv >= 0 && g.level != lv) continue;
                if (best == null || g.level > best.level) best = g;
            }
            return best;
        }

        public void shift (bool rows, int at, int count) {
            var m = levels (rows);
            var nm = new Gee.HashMap<int, int> ();
            foreach (var e in m.entries) {
                int v = e.key;
                if (count < 0 && v >= at && v < at - count) continue;
                nm[v >= at ? v + count : v] = e.value;
            }
            m.clear ();
            foreach (var e in nm.entries) m[e.key] = e.value;
            var c = collapsed (rows);
            var nc = new Gee.HashSet<int> ();
            foreach (int v in c) {
                if (count < 0 && v >= at && v < at - count) continue;
                nc.add (v >= at ? v + count : v);
            }
            c.clear ();
            c.add_all (nc);
        }

        public void set_collapsed (Sheet s, bool rows, OutlineGroup g, bool collapse) {
            var hidden = rows ? s.hidden_rows : s.hidden_cols;
            var c = collapsed (rows);
            if (collapse) {
                for (int i = g.start; i <= g.end; i++) hidden.add (i);
                c.add (g.summary);
                return;
            }
            c.remove (g.summary);
            for (int i = g.start; i <= g.end; i++) hidden.remove (i);
            foreach (var inner in groups (rows)) {
                if (inner.level <= g.level || inner.start < g.start || inner.end > g.end) continue;
                if (!inner.collapsed) continue;
                for (int i = inner.start; i <= inner.end; i++) hidden.add (i);
            }
        }

        public void show_level (Sheet s, bool rows, int lv) {
            var hidden = rows ? s.hidden_rows : s.hidden_cols;
            var c = collapsed (rows);
            c.clear ();
            foreach (var e in levels (rows).entries) {
                if (e.value >= lv) hidden.add (e.key);
                else hidden.remove (e.key);
            }
            foreach (var g in groups (rows)) if (g.level >= lv) c.add (g.summary);
        }
    }

    public class AutoOutline {
        private static bool is_summary_formula (Node? n, bool rows, int index, out int from, out int to) {
            from = to = -1;
            if (n == null || n.kind != NodeKind.CALL) return false;
            if (n.text != "SUM" && n.text != "SUBTOTAL" && n.text != "AVERAGE" && n.text != "COUNT" && n.text != "MAX" && n.text != "MIN") return false;
            foreach (var a in n.args) {
                if (a.kind != NodeKind.REF || a.b == null || a.sheet != null) continue;
                if (rows && a.a.col == a.b.col && a.b.row < index) {
                    from = a.a.row;
                    to = a.b.row;
                    return true;
                }
                if (!rows && a.a.row == a.b.row && a.b.col < index) {
                    from = a.a.col;
                    to = a.b.col;
                    return true;
                }
            }
            return false;
        }

        public static int apply (Sheet s, bool rows) {
            var found = new Gee.HashSet<string> ();
            foreach (var cell in s.cells.values) {
                int f, t;
                int idx = rows ? cell.row : cell.col;
                if (is_summary_formula (cell.formula, rows, idx, out f, out t) && t == idx - 1 && f <= t) found.add ("%d:%d".printf (f, t));
            }
            foreach (string k in found) {
                var parts = k.split (":");
                s.outline.group (rows, int.parse (parts[0]), int.parse (parts[1]));
            }
            return found.size;
        }
    }
}
