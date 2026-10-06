namespace Singularity.Apps.Spreadsheet {

    public class LambdaFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Logical", syntax, summary, (owned) impl);
        }

        public static Value? to_lambda (Evaluator ev, Node n, out Lambda? f) {
            f = null;
            var v = ev.eval (n);
            if (v.is_error ()) return v;
            if (v.kind != ValueKind.LAMBDA) return Value.err (ErrorKind.VALUE);
            f = v.fn;
            return null;
        }

        private static Value cell_of (Value[,] m, int i, int j) {
            return m[i, j];
        }

        private static Value row_of (Value[,] m, int i) {
            int c = m.length[1];
            var r = new Value[1, c];
            for (int j = 0; j < c; j++) r[0, j] = m[i, j];
            return Value.matrix (r);
        }

        private static Value col_of (Value[,] m, int j) {
            int rr = m.length[0];
            var r = new Value[rr, 1];
            for (int i = 0; i < rr; i++) r[i, 0] = m[i, j];
            return Value.matrix (r);
        }

        private static Value scalar (Evaluator ev, Value v) {
            if (v.kind == ValueKind.RANGE) {
                if (v.area.is_single ()) return ev.cell (v.area.sheet, v.area.r1, v.area.c1);
                return Value.err (ErrorKind.CALC);
            }
            if (v.kind == ValueKind.ARRAY) {
                if (v.array.length[0] == 1 && v.array.length[1] == 1) return v.array[0, 0];
                return Value.err (ErrorKind.CALC);
            }
            if (v.kind == ValueKind.LAMBDA || v.kind == ValueKind.REFS) return Value.err (ErrorKind.CALC);
            return v;
        }

        public static void register () {
            add ("LAMBDA", 1, 254, "LAMBDA([parameter1, ...], calculation)", _("Creates a reusable custom function"), (ev, a) => {
                string[] ps = {};
                var seen = new Gee.HashSet<string> ();
                for (int i = 0; i < a.length - 1; i++) {
                    string p;
                    if (a[i].kind == NodeKind.NAME) p = a[i].text;
                    else if (a[i].kind == NodeKind.STRUCT && a[i].sref.table == "" && a[i].sref.col1 != "" && a[i].sref.col2 == "" && !a[i].sref.this_row) p = "[" + a[i].sref.col1 + "]";
                    else return Value.err (ErrorKind.VALUE);
                    if (seen.contains (p.casefold ())) return Value.err (ErrorKind.VALUE);
                    seen.add (p.casefold ());
                    ps += p;
                }
                var f = new Lambda (ps, a[a.length - 1], ev.scope, ev.sheet, ev.row, ev.col);
                return Value.lambda (f);
            });
            add ("LET", 3, -1, "LET(name1, value1, calculation)", _("Names intermediate results"), (ev, a) => {
                if (a.length % 2 == 0) return Value.err (ErrorKind.VALUE);
                var saved = ev.scope;
                ev.scope = new Scope (saved);
                for (int i = 0; i + 1 < a.length; i += 2) {
                    if (a[i].kind != NodeKind.NAME) {
                        ev.scope = saved;
                        return Value.err (ErrorKind.VALUE);
                    }
                    var v = ev.eval (a[i + 1]);
                    ev.scope.bind (a[i].text, v);
                }
                var result = ev.eval (a[a.length - 1]);
                ev.scope = saved;
                return result;
            });
            add ("ISOMITTED", 1, 1, "ISOMITTED(argument)", _("Whether a LAMBDA argument is missing"), (ev, a) => {
                var v = ev.eval (a[0]);
                return Value.boolean (v.omitted || a[0].kind == NodeKind.MISSING);
            });
            add ("MAP", 2, -1, "MAP(array1, [array2, ...], lambda)", _("Applies a LAMBDA to each value"), (ev, a) => {
                Lambda f;
                var e = to_lambda (ev, a[a.length - 1], out f);
                if (e != null) return e;
                var arrays = new Gee.ArrayList<Value> ();
                int rows = 0, cols = 0;
                for (int i = 0; i < a.length - 1; i++) {
                    var m = ev.to_matrix (ev.eval (a[i]));
                    arrays.add (Value.matrix (m));
                    rows = int.max (rows, m.length[0]);
                    cols = int.max (cols, m.length[1]);
                }
                var out_m = new Value[rows, cols];
                for (int i = 0; i < rows; i++) {
                    for (int j = 0; j < cols; j++) {
                        Value[] args = {};
                        foreach (var mv in arrays) {
                            var m = mv.array;
                            int ii = m.length[0] == 1 ? 0 : i, jj = m.length[1] == 1 ? 0 : j;
                            args += ii < m.length[0] && jj < m.length[1] ? cell_of (m, ii, jj) : Value.err (ErrorKind.NA);
                        }
                        out_m[i, j] = scalar (ev, ev.call_lambda (f, args));
                    }
                }
                return Value.matrix (out_m);
            });
            add ("REDUCE", 3, 3, "REDUCE([initial_value], array, lambda)", _("Reduces an array to an accumulated value"), (ev, a) => {
                Lambda f;
                var e = to_lambda (ev, a[2], out f);
                if (e != null) return e;
                Value acc = a[0].kind == NodeKind.MISSING ? Value.num (0) : ev.eval (a[0]);
                var m = ev.to_matrix (ev.eval (a[1]));
                for (int i = 0; i < m.length[0]; i++) {
                    for (int j = 0; j < m.length[1]; j++) {
                        acc = ev.call_lambda (f, { acc, m[i, j] });
                    }
                }
                return acc;
            });
            add ("SCAN", 3, 3, "SCAN([initial_value], array, lambda)", _("Returns each intermediate accumulated value"), (ev, a) => {
                Lambda f;
                var e = to_lambda (ev, a[2], out f);
                if (e != null) return e;
                Value acc = a[0].kind == NodeKind.MISSING ? Value.num (0) : ev.eval (a[0]);
                var m = ev.to_matrix (ev.eval (a[1]));
                var out_m = new Value[m.length[0], m.length[1]];
                for (int i = 0; i < m.length[0]; i++) {
                    for (int j = 0; j < m.length[1]; j++) {
                        acc = scalar (ev, ev.call_lambda (f, { acc, m[i, j] }));
                        out_m[i, j] = acc;
                    }
                }
                return Value.matrix (out_m);
            });
            add ("BYROW", 2, 2, "BYROW(array, lambda)", _("Applies a LAMBDA to each row"), (ev, a) => {
                Lambda f;
                var e = to_lambda (ev, a[1], out f);
                if (e != null) return e;
                var m = ev.to_matrix (ev.eval (a[0]));
                var out_m = new Value[m.length[0], 1];
                for (int i = 0; i < m.length[0]; i++) out_m[i, 0] = scalar (ev, ev.call_lambda (f, { row_of (m, i) }));
                return Value.matrix (out_m);
            });
            add ("BYCOL", 2, 2, "BYCOL(array, lambda)", _("Applies a LAMBDA to each column"), (ev, a) => {
                Lambda f;
                var e = to_lambda (ev, a[1], out f);
                if (e != null) return e;
                var m = ev.to_matrix (ev.eval (a[0]));
                var out_m = new Value[1, m.length[1]];
                for (int j = 0; j < m.length[1]; j++) out_m[0, j] = scalar (ev, ev.call_lambda (f, { col_of (m, j) }));
                return Value.matrix (out_m);
            });
            add ("MAKEARRAY", 3, 3, "MAKEARRAY(rows, columns, lambda)", _("Builds an array from a LAMBDA"), (ev, a) => {
                int rows, cols;
                var e = ev.arg_int (a[0], out rows);
                if (e != null) return e;
                e = ev.arg_int (a[1], out cols);
                if (e != null) return e;
                if (rows < 1 || cols < 1 || (int64) rows * cols > 4000000) return Value.err (ErrorKind.VALUE);
                Lambda f;
                e = to_lambda (ev, a[2], out f);
                if (e != null) return e;
                var out_m = new Value[rows, cols];
                for (int i = 0; i < rows; i++) {
                    for (int j = 0; j < cols; j++) out_m[i, j] = scalar (ev, ev.call_lambda (f, { Value.num (i + 1), Value.num (j + 1) }));
                }
                return Value.matrix (out_m);
            });
        }
    }
}
