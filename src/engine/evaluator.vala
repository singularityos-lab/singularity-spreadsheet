namespace Singularity.Apps.Spreadsheet {

    public class Evaluator {
        public Workbook book;
        public Sheet sheet;
        public int row;
        public int col;
        public Scope? scope;
        public bool legacy;
        public int array_ctx;

        public Evaluator (Workbook book, Sheet sheet, int row, int col) {
            this.book = book;
            this.sheet = sheet;
            this.row = row;
            this.col = col;
        }

        public Value eval_top (Node node) {
            var v = eval (node);
            if (v.kind == ValueKind.RANGE) v = implicit (v.area);
            if (v.kind == ValueKind.ARRAY) v = v.array[0, 0];
            return scalar_result (v);
        }

        public static Value scalar_result (Value v) {
            if (v.kind == ValueKind.EMPTY) return Value.num (0);
            if (v.kind == ValueKind.LAMBDA) return Value.err (ErrorKind.CALC);
            if (v.kind == ValueKind.REFS || v.kind == ValueKind.RANGE || v.kind == ValueKind.ARRAY) return Value.err (ErrorKind.VALUE);
            return v;
        }

        public Value eval_spill (Node node) {
            var v = eval (node);
            if (v.kind == ValueKind.RANGE) {
                if (v.area.is_single ()) return scalar_result (cell (v.area.sheet, v.area.r1, v.area.c1));
                return Value.matrix (to_matrix (v));
            }
            if (v.kind == ValueKind.ARRAY) {
                if (v.array.length[0] == 0 || v.array.length[1] == 0) return Value.err (ErrorKind.CALC);
                if (v.array.length[0] == 1 && v.array.length[1] == 1) return scalar_result (v.array[0, 0]);
                var m = v.array;
                int r = m.length[0], c = m.length[1];
                var out_m = new Value[r, c];
                for (int i = 0; i < r; i++) for (int j = 0; j < c; j++) {
                    var e = m[i, j];
                    out_m[i, j] = e.kind == ValueKind.EMPTY ? Value.num (0) : (e.kind == ValueKind.NUMBER || e.kind == ValueKind.TEXT || e.kind == ValueKind.BOOL || e.kind == ValueKind.ERROR ? e : scalar_result (e));
                }
                return Value.matrix (out_m);
            }
            return scalar_result (v);
        }

        public Value implicit (Area a) {
            if (a.is_single ()) return cell (a.sheet, a.r1, a.c1);
            if (a.c1 == a.c2 && row >= a.r1 && row <= a.r2) return cell (a.sheet, row, a.c1);
            if (a.r1 == a.r2 && col >= a.c1 && col <= a.c2) return cell (a.sheet, a.r1, col);
            return Value.err (ErrorKind.VALUE);
        }

        public Value cell (Sheet? s, int r, int c) {
            var target = s ?? sheet;
            return target.value_at (r, c);
        }

        public Value eval (Node n) {
            switch (n.kind) {
                case NodeKind.NUMBER:
                    return Value.num (n.number);
                case NodeKind.TEXT:
                    return Value.str (n.text);
                case NodeKind.BOOL:
                    return Value.boolean (n.number != 0);
                case NodeKind.ERROR:
                    return Value.err (n.error);
                case NodeKind.MISSING:
                    return Value.empty ();
                case NodeKind.ARRAY:
                    return Value.matrix (n.array);
                case NodeKind.REF:
                    if (n.a == null || n.bad_sheet) return Value.err (ErrorKind.REF);
                    if (n.is_3d ()) return eval_3d (n);
                    if (n.spill) {
                        var anchor_sheet = n.sheet ?? sheet;
                        var sa = book.spill_area (anchor_sheet, n.a.row, n.a.col);
                        if (sa == null) return Value.err (ErrorKind.REF);
                        return Value.range (sa);
                    }
                    return Value.range (n.to_area (sheet));
                case NodeKind.NAME:
                    return eval_name (n.text);
                case NodeKind.VALUE:
                    return n.value ?? Value.empty ();
                case NodeKind.STRUCT:
                    var ta = Tables.resolve (book, n.sref, sheet, row, col);
                    if (ta == null) {
                        var dsv = DataTypes.dot_struct (this, n.sref);
                        if (dsv != null) return dsv;
                        return Value.err (ErrorKind.REF);
                    }
                    return Value.range (ta);
                case NodeKind.APPLY:
                    var callee = eval (n.args[0]);
                    if (callee.is_error ()) return callee;
                    if (callee.kind != ValueKind.LAMBDA) return Value.err (ErrorKind.VALUE);
                    Value[] avals = {};
                    for (int i = 1; i < n.args.length; i++) avals += n.args[i].kind == NodeKind.MISSING ? Value.missing () : eval (n.args[i]);
                    return call_lambda (callee.fn, avals);
                case NodeKind.PERCENT:
                    return map1 (eval (n.args[0]), (v) => {
                        double d;
                        var e = to_number (v, out d);
                        return e != null ? e : Value.num (d / 100);
                    });
                case NodeKind.UNARY:
                    if (n.op == "@") {
                        var iv = eval (n.args[0]);
                        if (iv.kind == ValueKind.RANGE) return implicit (iv.area);
                        if (iv.kind == ValueKind.ARRAY) return iv.array[0, 0];
                        return iv;
                    }
                    return map1 (eval (n.args[0]), (v) => {
                        double d;
                        var e = to_number (v, out d);
                        return e != null ? e : Value.num (-d);
                    });
                case NodeKind.BINARY:
                    return eval_binary (n);
                case NodeKind.CALL:
                    return Functions.call (this, n);
            }
            return Value.err (ErrorKind.VALUE);
        }

        private int name_depth = 0;

        private Value eval_3d (Node n) {
            int i1 = book.sheets.index_of (n.sheet);
            int i2 = book.sheets.index_of (n.sheet2);
            if (i1 < 0 || i2 < 0) return Value.err (ErrorKind.REF);
            if (i1 > i2) {
                int t = i1;
                i1 = i2;
                i2 = t;
            }
            Area[] list = {};
            for (int i = i1; i <= i2; i++) {
                var sh = book.sheets[i];
                if (n.b == null) list += new Area.cell (sh, n.a.row, n.a.col);
                else list += new Area (sh, n.a.row, n.a.col, n.b.row, n.b.col);
            }
            return Value.refs (list);
        }

        public string? find_name (string name) {
            string k = name.casefold ();
            foreach (var e in sheet.names.entries) {
                if (e.key.casefold () == k) return e.value;
            }
            foreach (var e in book.names.entries) {
                if (e.key.casefold () == k) return e.value;
            }
            return null;
        }

        public Value call_lambda (Lambda f, Value[] args) {
            if (f.builtin != "") {
                var call = new Node (NodeKind.CALL);
                call.text = f.builtin;
                Node[] cargs = {};
                foreach (var v in args) {
                    var vn = new Node (NodeKind.VALUE);
                    vn.value = v;
                    cargs += vn;
                }
                call.args = cargs;
                return Functions.call (this, call);
            }
            if (args.length > f.params.length) return Value.err (ErrorKind.VALUE);
            if (lambda_depth > 200) return Value.err (ErrorKind.NUM);
            var local = new Scope (f.scope);
            for (int i = 0; i < f.params.length; i++) {
                string p = f.params[i];
                bool optional = p.has_prefix ("[") && p.has_suffix ("]");
                string pname = optional ? p.substring (1, p.length - 2) : p;
                if (i < args.length) local.bind (pname, args[i]);
                else if (optional) local.bind (pname, Value.missing ());
                else return Value.err (ErrorKind.VALUE);
            }
            var saved_scope = scope;
            var saved_sheet = sheet;
            scope = local;
            sheet = f.sheet;
            lambda_depth++;
            var r = eval (f.body);
            lambda_depth--;
            scope = saved_scope;
            sheet = saved_sheet;
            return r;
        }

        private int lambda_depth = 0;

        public Value? resolve_callable (string name) {
            if (scope != null) {
                var v = scope.lookup (name);
                if (v != null) return v;
            }
            string? def = find_name (name);
            if (def == null) return null;
            var nv = eval_name (name);
            return nv;
        }

        private Value eval_name (string name) {
            if (scope != null) {
                var sv = scope.lookup (name);
                if (sv != null) return sv;
            }
            string? def = find_name (name);
            if (def == null) {
                var table_area = Tables.resolve_name (book, name);
                if (table_area != null) return Value.range (table_area);
                if (Functions.all ().has_key (name.up ())) {
                    var f = new Lambda ({}, new Node (NodeKind.MISSING), null, sheet, row, col);
                    f.builtin = name.up ();
                    return Value.lambda (f);
                }
            }
            if (def == null) {
                var dv = DataTypes.dot (this, name);
                if (dv != null) return dv;
            }
            if (def == null || name_depth > 20) return Value.err (ErrorKind.NAME);
            try {
                name_depth++;
                var node = Formula.parse (def, book, sheet);
                var v = eval (node);
                name_depth--;
                return v;
            } catch (FormulaError e) {
                name_depth--;
                return Value.err (ErrorKind.NAME);
            }
        }

        private Value eval_binary (Node n) {
            if (n.op == ":") {
                var l = eval (n.args[0]);
                var r = eval (n.args[1]);
                if (l.kind != ValueKind.RANGE || r.kind != ValueKind.RANGE) return Value.err (ErrorKind.VALUE);
                if (l.area.sheet != r.area.sheet) return Value.err (ErrorKind.REF);
                return Value.range (new Area (l.area.sheet,
                    int.min (l.area.r1, r.area.r1), int.min (l.area.c1, r.area.c1),
                    int.max (l.area.r2, r.area.r2), int.max (l.area.c2, r.area.c2)));
            }
            var a = eval (n.args[0]);
            var b = eval (n.args[1]);
            string op = n.op;
            return map2 (a, b, (x, y) => binary_scalar (op, x, y));
        }

        public delegate Value Map1 (Value v);
        public delegate Value Map2 (Value a, Value b);

        public Value[,] to_matrix (Value v) {
            if (v.kind == ValueKind.ARRAY) return v.array;
            if (v.kind == ValueKind.REFS) {
                var bad = new Value[1, 1];
                bad[0, 0] = Value.err (ErrorKind.VALUE);
                return bad;
            }
            if (v.kind == ValueKind.RANGE) {
                var a = v.area;
                var s = a.sheet ?? sheet;
                int rows = a.rows;
                int cols = a.cols;
                if (a.r2 == MAX_ROWS - 1) rows = int.max (int.min (rows, s.max_row - a.r1 + 1), 1);
                if (a.c2 == MAX_COLS - 1) cols = int.max (int.min (cols, s.max_col - a.c1 + 1), 1);
                if ((int64) rows * cols > 4000000) rows = int.max (1, 4000000 / cols);
                var m = new Value[rows, cols];
                for (int i = 0; i < rows; i++) for (int j = 0; j < cols; j++) m[i, j] = cell (s, a.r1 + i, a.c1 + j);
                return m;
            }
            var one = new Value[1, 1];
            one[0, 0] = v;
            return one;
        }

        public Value map1 (Value v, Map1 f) {
            if (v.kind == ValueKind.RANGE && (v.area.is_single () || (legacy && array_ctx == 0))) return f (deref (v));
            if (v.kind != ValueKind.RANGE && v.kind != ValueKind.ARRAY) return f (v);
            var m = to_matrix (v);
            int r = m.length[0], c = m.length[1];
            var out_m = new Value[r, c];
            for (int i = 0; i < r; i++) for (int j = 0; j < c; j++) out_m[i, j] = f (m[i, j]);
            return Value.matrix (out_m);
        }

        public Value map2 (Value a, Value b, Map2 f) {
            bool lift_ranges = !legacy || array_ctx > 0;
            bool am = (a.kind == ValueKind.RANGE && !a.area.is_single () && lift_ranges) || a.kind == ValueKind.ARRAY;
            bool bm = (b.kind == ValueKind.RANGE && !b.area.is_single () && lift_ranges) || b.kind == ValueKind.ARRAY;
            if (!am && !bm) return f (deref (a), deref (b));
            var ma = to_matrix (am ? a : deref (a));
            var mb = to_matrix (bm ? b : deref (b));
            int r = int.max (ma.length[0], mb.length[0]);
            int c = int.max (ma.length[1], mb.length[1]);
            var out_m = new Value[r, c];
            for (int i = 0; i < r; i++) {
                for (int j = 0; j < c; j++) {
                    Value? x = pick (ma, i, j);
                    Value? y = pick (mb, i, j);
                    out_m[i, j] = x == null || y == null ? Value.err (ErrorKind.NA) : f (x, y);
                }
            }
            return Value.matrix (out_m);
        }

        private static Value? pick (Value[,] m, int i, int j) {
            int r = m.length[0], c = m.length[1];
            int ii = r == 1 ? 0 : i;
            int jj = c == 1 ? 0 : j;
            if (ii >= r || jj >= c) return null;
            return m[ii, jj];
        }

        public Value deref (Value v) {
            if (v.kind == ValueKind.RANGE) return implicit (v.area);
            if (v.kind == ValueKind.ARRAY) return v.array[0, 0];
            if (v.kind == ValueKind.REFS || v.kind == ValueKind.LAMBDA) return Value.err (ErrorKind.VALUE);
            return v;
        }

        public static Value? to_number (Value v, out double d) {
            d = 0;
            switch (v.kind) {
                case ValueKind.NUMBER:
                case ValueKind.BOOL:
                    d = v.number;
                    return null;
                case ValueKind.EMPTY:
                    return null;
                case ValueKind.ERROR:
                    return v;
                case ValueKind.TEXT:
                    if (v.text.strip () == "") return Value.err (ErrorKind.VALUE);
                    string fmt;
                    if (Input.parse_number (v.text, out d, out fmt)) return null;
                    if (Input.parse_date_time (v.text, out d, out fmt)) return null;
                    return Value.err (ErrorKind.VALUE);
            }
            return Value.err (ErrorKind.VALUE);
        }

        public static string to_text (Value v) {
            switch (v.kind) {
                case ValueKind.TEXT: return v.text;
                case ValueKind.NUMBER: return Value.format_number_general (v.number);
                case ValueKind.BOOL: return v.number != 0 ? "TRUE" : "FALSE";
                case ValueKind.ERROR: return v.error.to_string ();
                default: return "";
            }
        }

        public static int compare (Value a, Value b) {
            int ra = rank (a), rb = rank (b);
            if (a.kind == ValueKind.EMPTY) {
                if (b.kind == ValueKind.TEXT) return b.text == "" ? 0 : -1;
                if (b.kind == ValueKind.BOOL) return b.number == 0 ? 0 : -1;
                if (b.kind == ValueKind.NUMBER) return 0 < b.number ? -1 : (0 > b.number ? 1 : 0);
                return 0;
            }
            if (b.kind == ValueKind.EMPTY) return -compare (b, a);
            if (ra != rb) return ra < rb ? -1 : 1;
            if (a.kind == ValueKind.TEXT) return a.text.casefold ().collate (b.text.casefold ());
            return a.number < b.number ? -1 : (a.number > b.number ? 1 : 0);
        }

        private static int rank (Value v) {
            switch (v.kind) {
                case ValueKind.NUMBER: return 0;
                case ValueKind.TEXT: return 1;
                case ValueKind.BOOL: return 2;
                default: return 3;
            }
        }

        public static Value binary_scalar (string op, Value a, Value b) {
            if (a.is_error ()) return a;
            if (b.is_error ()) return b;
            switch (op) {
                case "&":
                    return Value.str (to_text (a) + to_text (b));
                case "=":
                    return Value.boolean (compare (a, b) == 0);
                case "<>":
                    return Value.boolean (compare (a, b) != 0);
                case "<":
                    return Value.boolean (compare (a, b) < 0);
                case ">":
                    return Value.boolean (compare (a, b) > 0);
                case "<=":
                    return Value.boolean (compare (a, b) <= 0);
                case ">=":
                    return Value.boolean (compare (a, b) >= 0);
            }
            double x, y;
            var e = to_number (a, out x);
            if (e != null) return e;
            e = to_number (b, out y);
            if (e != null) return e;
            switch (op) {
                case "+": return Value.num (x + y);
                case "-": return Value.num (x - y);
                case "*": return Value.num (x * y);
                case "/": return y == 0 ? Value.err (ErrorKind.DIV0) : Value.num (x / y);
                case "^":
                    if (x == 0 && y == 0) return Value.err (ErrorKind.NUM);
                    if (x == 0 && y < 0) return Value.err (ErrorKind.DIV0);
                    return Value.num (Math.pow (x, y));
            }
            return Value.err (ErrorKind.VALUE);
        }

        public Value arg (Node n) {
            return deref (eval (n));
        }

        public Value? arg_number (Node n, out double d) {
            d = 0;
            var v = arg (n);
            return to_number (v, out d);
        }

        public Value? arg_int (Node n, out int i) {
            double d;
            i = 0;
            var e = arg_number (n, out d);
            if (e != null) return e;
            i = (int) Math.trunc (d);
            return null;
        }

        public Value? arg_bool (Node n, out bool b) {
            b = false;
            var v = arg (n);
            if (v.is_error ()) return v;
            if (v.kind == ValueKind.TEXT) {
                string u = v.text.up ();
                if (u == "TRUE" || u == "FALSE") {
                    b = u == "TRUE";
                    return null;
                }
                return Value.err (ErrorKind.VALUE);
            }
            b = v.number != 0;
            return null;
        }

        public string arg_text (Node n, out Value? error) {
            var v = arg (n);
            error = v.is_error () ? v : null;
            return to_text (v);
        }

        public delegate bool ValueVisit (Value v, bool from_ref);

        public void visit_values (Node n, ValueVisit visit) {
            var v = eval (n);
            visit_value (v, n.kind == NodeKind.REF || n.kind == NodeKind.NAME || v.kind == ValueKind.RANGE, visit);
        }

        public void visit_value (Value v, bool from_ref, ValueVisit visit) {
            if (v.kind == ValueKind.REFS) {
                bool go = true;
                foreach (var ar in v.areas) {
                    if (!go) break;
                    visit_value (Value.range (ar), true, (x, fr) => {
                        if (!visit (x, fr)) {
                            go = false;
                            return false;
                        }
                        return true;
                    });
                }
                return;
            }
            if (v.kind == ValueKind.RANGE) {
                var a = v.area;
                var s = a.sheet ?? sheet;
                bool go = true;
                if (s.spills.size > 0) {
                    bool any = false;
                    foreach (var sa in s.spills.values) if (sa.intersects (a)) any = true;
                    if (any) {
                        var keys = new Gee.TreeSet<int64?> ((x, y) => {
                            int64 p = x;
                            int64 q = y;
                            return p < q ? -1 : (p > q ? 1 : 0);
                        });
                        s.foreach_in (a, (r, c, cl) => {
                            if (cl.formula != null || cl.input != "") keys.add (Sheet.key (r, c));
                        });
                        foreach (var sa in s.spills.values) {
                            if (!sa.intersects (a)) continue;
                            for (int r = int.max (sa.r1, a.r1); r <= int.min (sa.r2, a.r2); r++) {
                                for (int c = int.max (sa.c1, a.c1); c <= int.min (sa.c2, a.c2); c++) keys.add (Sheet.key (r, c));
                            }
                        }
                        foreach (var k in keys) {
                            var cv = s.value_at (Sheet.key_row (k), Sheet.key_col (k));
                            if (cv.is_empty ()) continue;
                            if (!visit (cv, true)) return;
                        }
                        return;
                    }
                }
                s.foreach_in (a, (r, c, cl) => {
                    if (!go) return;
                    if (cl.formula == null && cl.input == "") return;
                    var cv = book.cell_value (s, cl);
                    if (!visit (cv, true)) go = false;
                });
                return;
            }
            if (v.kind == ValueKind.ARRAY) {
                for (int i = 0; i < v.array.length[0]; i++) {
                    for (int j = 0; j < v.array.length[1]; j++) {
                        if (!visit (v.array[i, j], true)) return;
                    }
                }
                return;
            }
            visit (v, from_ref);
        }

        public Value? numbers (Node[] args, Gee.ArrayList<double?> out_list, bool count_bool_text_in_refs = false) {
            Value? err = null;
            foreach (var n in args) {
                if (n.kind == NodeKind.MISSING) continue;
                visit_values (n, (v, from_ref) => {
                    switch (v.kind) {
                        case ValueKind.NUMBER:
                            out_list.add (v.number);
                            break;
                        case ValueKind.BOOL:
                            if (!from_ref || count_bool_text_in_refs) out_list.add (v.number);
                            break;
                        case ValueKind.TEXT:
                            if (!from_ref) {
                                double d;
                                if (to_number (v, out d) == null) out_list.add (d);
                                else {
                                    err = Value.err (ErrorKind.VALUE);
                                    return false;
                                }
                            } else if (count_bool_text_in_refs) {
                                out_list.add (0);
                            }
                            break;
                        case ValueKind.ERROR:
                            err = v;
                            return false;
                        default:
                            break;
                    }
                    return true;
                });
                if (err != null) return err;
            }
            return null;
        }
    }
}
