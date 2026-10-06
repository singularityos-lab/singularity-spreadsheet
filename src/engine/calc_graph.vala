namespace Singularity.Apps.Spreadsheet {

    public class CalcGraph {
        private const int ROW_BLOCK = 256;
        private const int COL_BLOCK = 16;
        private const int MAX_BUCKETS = 16384;

        public class AreaDep {
            public Area area;
            public Reg reg;
        }

        public class SheetIndex {
            public Gee.HashMap<int64?, Gee.ArrayList<Reg>> single;
            public Gee.HashMap<int64?, Gee.ArrayList<AreaDep>> buckets;
            public Gee.ArrayList<AreaDep> big = new Gee.ArrayList<AreaDep> ();
            public Gee.HashMap<int64?, Reg> regs;

            public SheetIndex () {
                Gee.HashDataFunc<int64?> h = (k) => { int64 v = k; return (uint) (v ^ (v >> 32)); };
                Gee.EqualDataFunc<int64?> e = (a, b) => { int64 x = a; int64 y = b; return x == y; };
                single = new Gee.HashMap<int64?, Gee.ArrayList<Reg>> (h, e);
                buckets = new Gee.HashMap<int64?, Gee.ArrayList<AreaDep>> (h, e);
                regs = new Gee.HashMap<int64?, Reg> (h, e);
            }
        }

        public class Entry {
            public SheetIndex idx;
            public int64 key;
            public AreaDep? dep;
            public bool big;
        }

        public class Reg {
            public Sheet sheet;
            public Cell cell;
            public bool is_volatile;
            public Gee.ArrayList<Entry> entries = new Gee.ArrayList<Entry> ();
            public int mark;
            public int indeg;
            public Gee.ArrayList<Reg>? outs;
            public int low;
            public int index;
            public bool on_stack;
        }

        private unowned Workbook book;
        private Gee.HashMap<Sheet, SheetIndex> index = new Gee.HashMap<Sheet, SheetIndex> ();
        private Gee.HashSet<Reg> volatiles = new Gee.HashSet<Reg> ();

        public CalcGraph (Workbook book) {
            this.book = book;
        }

        private SheetIndex idx_for (Sheet s) {
            var i = index[s];
            if (i == null) {
                i = new SheetIndex ();
                index[s] = i;
            }
            return i;
        }

        private static int64 bucket_key (int rb, int cb) {
            return ((int64) rb << 20) | cb;
        }

        public void build () {
            index.clear ();
            volatiles.clear ();
            foreach (var s in book.sheets) {
                foreach (var c in s.cells.values) {
                    if (c.formula != null) register (s, c);
                }
            }
        }

        public Gee.ArrayList<Reg> all_regs () {
            var list = new Gee.ArrayList<Reg> ();
            foreach (var i in index.values) list.add_all (i.regs.values);
            return list;
        }

        public Reg? reg_at (Sheet s, int row, int col) {
            var i = index[s];
            if (i == null) return null;
            return i.regs[Sheet.key (row, col)];
        }

        public void unregister_at (Sheet s, int row, int col) {
            var i = index[s];
            if (i == null) return;
            int64 k = Sheet.key (row, col);
            var r = i.regs[k];
            if (r == null) return;
            i.regs.unset (k);
            volatiles.remove (r);
            foreach (var e in r.entries) {
                if (e.dep == null) {
                    var list = e.idx.single[e.key];
                    if (list != null) {
                        list.remove (r);
                        if (list.size == 0) e.idx.single.unset (e.key);
                    }
                } else if (e.big) {
                    e.idx.big.remove (e.dep);
                } else {
                    var list = e.idx.buckets[e.key];
                    if (list != null) {
                        list.remove (e.dep);
                        if (list.size == 0) e.idx.buckets.unset (e.key);
                    }
                }
            }
        }

        public void register (Sheet s, Cell c) {
            unregister_at (s, c.row, c.col);
            if (c.formula == null) return;
            var r = new Reg ();
            r.sheet = s;
            r.cell = c;
            idx_for (s).regs[Sheet.key (c.row, c.col)] = r;
            var seen = new Gee.HashSet<string> ();
            collect (r, c.formula, s, seen, 0);
            if (r.is_volatile) volatiles.add (r);
        }

        private void collect (Reg r, Node n, Sheet own, Gee.HashSet<string> seen, int depth) {
            if (depth > 16) {
                r.is_volatile = true;
                return;
            }
            switch (n.kind) {
                case NodeKind.REF:
                    if (n.a == null || n.bad_sheet) break;
                    if (n.is_3d ()) {
                        int i1 = book.sheets.index_of (n.sheet);
                        int i2 = book.sheets.index_of (n.sheet2);
                        if (i1 < 0 || i2 < 0) break;
                        for (int i = int.min (i1, i2); i <= int.max (i1, i2); i++) {
                            var sh = book.sheets[i];
                            add_area (r, sh, n.b == null ? new Area.cell (sh, n.a.row, n.a.col) : new Area (sh, n.a.row, n.a.col, n.b.row, n.b.col));
                        }
                        break;
                    }
                    var target = n.sheet ?? own;
                    if (n.spill) {
                        add_area (r, target, new Area.cell (target, n.a.row, n.a.col));
                        break;
                    }
                    add_area (r, target, n.to_area (own));
                    break;
                case NodeKind.STRUCT:
                    var sa = Tables.resolve (book, n.sref, own, r.cell.row, r.cell.col);
                    if (sa != null) {
                        add_area (r, sa.sheet, sa);
                        break;
                    }
                    var t = n.sref.table != "" ? Tables.find (book, n.sref.table) : Tables.at (book, own, r.cell.row, r.cell.col);
                    if (t != null) add_area (r, t.sheet, t.area);
                    break;
                case NodeKind.NAME:
                    string key = n.text.casefold ();
                    if (seen.contains (key)) break;
                    seen.add (key);
                    string? def = null;
                    foreach (var e in own.names.entries) if (e.key.casefold () == key) def = e.value;
                    if (def == null) foreach (var e in book.names.entries) if (e.key.casefold () == key) def = e.value;
                    if (def != null) {
                        try {
                            var node = Formula.parse (def, book, own);
                            collect (r, node, own, seen, depth + 1);
                        } catch (FormulaError e) {
                            r.is_volatile = true;
                        }
                    } else {
                        var ta = Tables.find (book, n.text);
                        if (ta != null) add_area (r, ta.sheet, ta.area);
                    }
                    break;
                case NodeKind.CALL:
                    if (Functions.is_volatile_name (n.text)) r.is_volatile = true;
                    else if (!Functions.all ().has_key (n.text)) {
                        var nn = new Node (NodeKind.NAME);
                        nn.text = n.text;
                        collect (r, nn, own, seen, depth + 1);
                    }
                    break;
                default:
                    break;
            }
            foreach (var a in n.args) collect (r, a, own, seen, depth);
        }

        private void add_area (Reg r, Sheet s, Area area) {
            var i = idx_for (s);
            if (area.is_single ()) {
                int64 k = Sheet.key (area.r1, area.c1);
                var list = i.single[k];
                if (list == null) {
                    list = new Gee.ArrayList<Reg> ();
                    i.single[k] = list;
                }
                list.add (r);
                var e = new Entry ();
                e.idx = i;
                e.key = k;
                r.entries.add (e);
                return;
            }
            var dep = new AreaDep ();
            dep.area = area;
            dep.reg = r;
            int rb1 = area.r1 / ROW_BLOCK, rb2 = area.r2 / ROW_BLOCK;
            int cb1 = area.c1 / COL_BLOCK, cb2 = area.c2 / COL_BLOCK;
            int64 count = (int64) (rb2 - rb1 + 1) * (cb2 - cb1 + 1);
            if (count > MAX_BUCKETS) {
                i.big.add (dep);
                var e = new Entry ();
                e.idx = i;
                e.dep = dep;
                e.big = true;
                r.entries.add (e);
                return;
            }
            for (int rb = rb1; rb <= rb2; rb++) {
                for (int cb = cb1; cb <= cb2; cb++) {
                    int64 k = bucket_key (rb, cb);
                    var list = i.buckets[k];
                    if (list == null) {
                        list = new Gee.ArrayList<AreaDep> ();
                        i.buckets[k] = list;
                    }
                    list.add (dep);
                    var e = new Entry ();
                    e.idx = i;
                    e.key = k;
                    e.dep = dep;
                    r.entries.add (e);
                }
            }
        }

        public void dependents_of (Sheet s, int row, int col, Gee.Collection<Reg> into) {
            var i = index[s];
            if (i == null) return;
            var list = i.single[Sheet.key (row, col)];
            if (list != null) into.add_all (list);
            var bl = i.buckets[bucket_key (row / ROW_BLOCK, col / COL_BLOCK)];
            if (bl != null) {
                foreach (var d in bl) if (d.area.contains (row, col)) into.add (d.reg);
            }
            foreach (var d in i.big) if (d.area.contains (row, col)) into.add (d.reg);
        }

        public bool dependents_of_area (Sheet s, Area a, Gee.Collection<Reg> into) {
            var i = index[s];
            if (i == null) return true;
            if (a.size <= 64) {
                for (int r = a.r1; r <= a.r2; r++) for (int c = a.c1; c <= a.c2; c++) dependents_of (s, r, c, into);
                return true;
            }
            foreach (var e in i.single.entries) {
                int64 k = e.key;
                if (a.contains (Sheet.key_row (k), Sheet.key_col (k))) into.add_all (e.value);
            }
            int rb1 = a.r1 / ROW_BLOCK, rb2 = a.r2 / ROW_BLOCK;
            int cb1 = a.c1 / COL_BLOCK, cb2 = a.c2 / COL_BLOCK;
            if ((int64) (rb2 - rb1 + 1) * (cb2 - cb1 + 1) > i.buckets.size) {
                foreach (var list in i.buckets.values) foreach (var d in list) if (d.area.intersects (a)) into.add (d.reg);
            } else {
                for (int rb = rb1; rb <= rb2; rb++) {
                    for (int cb = cb1; cb <= cb2; cb++) {
                        var list = i.buckets[bucket_key (rb, cb)];
                        if (list == null) continue;
                        foreach (var d in list) if (d.area.intersects (a)) into.add (d.reg);
                    }
                }
            }
            foreach (var d in i.big) if (d.area.intersects (a)) into.add (d.reg);
            return true;
        }

        public Gee.Collection<Reg> volatile_regs () {
            return volatiles;
        }

        private void positions_in (Sheet s, Area a, Gee.Collection<int64?> into) {
            var i = idx_for (s);
            if (a.size <= 4096) {
                for (int r = a.r1; r <= a.r2; r++) for (int c = a.c1; c <= a.c2; c++) into.add (Sheet.key (r, c));
                return;
            }
            foreach (var k in s.cells.keys) if (a.contains (Sheet.key_row (k), Sheet.key_col (k))) into.add (k);
            foreach (var k in i.regs.keys) if (a.contains (Sheet.key_row (k), Sheet.key_col (k))) into.add (k);
        }

        public void update_area (Sheet s, Area a) {
            var positions = new Gee.HashSet<int64?> ((k) => { int64 v = k; return (uint) (v ^ (v >> 32)); }, (x, y) => { int64 p = x; int64 q = y; return p == q; });
            positions_in (s, a, positions);
            foreach (var k in positions) {
                int r = Sheet.key_row (k), c = Sheet.key_col (k);
                var cell = s.cells[k];
                if (cell != null && cell.formula != null) register (s, cell);
                else unregister_at (s, r, c);
            }
        }

        public void regs_in_area (Sheet s, Area a, Gee.Collection<Reg> into) {
            var i = index[s];
            if (i == null) return;
            if (a.size <= 4096) {
                for (int r = a.r1; r <= a.r2; r++) {
                    for (int c = a.c1; c <= a.c2; c++) {
                        var reg = i.regs[Sheet.key (r, c)];
                        if (reg != null) into.add (reg);
                    }
                }
                return;
            }
            foreach (var reg in i.regs.values) if (a.contains (reg.cell.row, reg.cell.col)) into.add (reg);
        }
    }
}
