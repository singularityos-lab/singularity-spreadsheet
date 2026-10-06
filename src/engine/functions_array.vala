namespace Singularity.Apps.Spreadsheet {

    public class ArrayFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Lookup", syntax, summary, (owned) impl);
        }

        private static Value[,] mat (Evaluator ev, Node n) {
            return ev.to_matrix (ev.eval (n));
        }

        private static Value? opt_int (Evaluator ev, Node[] a, int i, int def, out int v) {
            v = def;
            if (a.length > i && a[i].kind != NodeKind.MISSING) return ev.arg_int (a[i], out v);
            return null;
        }

        private static Value? opt_bool (Evaluator ev, Node[] a, int i, bool def, out bool v) {
            v = def;
            if (a.length > i && a[i].kind != NodeKind.MISSING) {
                double d;
                var e = ev.arg_number (a[i], out d);
                v = d != 0;
                return e;
            }
            return null;
        }

        private static Value calc_err () {
            return Value.err (ErrorKind.CALC);
        }

        private static Value blank_zero (Value v) {
            return v;
        }

        public static string key_of (Value v) {
            switch (v.kind) {
                case ValueKind.NUMBER: return "n" + Value.format_number_general_full (v.number);
                case ValueKind.TEXT: return "t" + v.text.casefold ();
                case ValueKind.BOOL: return "b" + v.number.to_string ();
                case ValueKind.ERROR: return "e" + v.error.to_string ();
                default: return "z";
            }
        }

        public static int sort_cmp (Value x, Value y, bool descending) {
            bool xe = x.kind == ValueKind.EMPTY, ye = y.kind == ValueKind.EMPTY;
            if (xe || ye) return xe == ye ? 0 : (xe ? 1 : -1);
            int rx = rank (x), ry = rank (y);
            int c;
            if (rx != ry) c = rx < ry ? -1 : 1;
            else if (x.kind == ValueKind.TEXT) c = x.text.casefold ().collate (y.text.casefold ());
            else if (x.kind == ValueKind.ERROR) c = 0;
            else c = x.number < y.number ? -1 : (x.number > y.number ? 1 : 0);
            return descending ? -c : c;
        }

        private static int rank (Value v) {
            switch (v.kind) {
                case ValueKind.NUMBER: return 0;
                case ValueKind.TEXT: return 1;
                case ValueKind.BOOL: return 2;
                default: return 3;
            }
        }

        private static Value[,] transpose (Value[,] m) {
            var t = new Value[m.length[1], m.length[0]];
            for (int i = 0; i < m.length[0]; i++) for (int j = 0; j < m.length[1]; j++) t[j, i] = m[i, j];
            return t;
        }

        private static Value pick_rows (Value[,] m, Gee.List<int> rows) {
            if (rows.size == 0) return calc_err ();
            int c = m.length[1];
            var out_m = new Value[rows.size, c];
            for (int i = 0; i < rows.size; i++) for (int j = 0; j < c; j++) out_m[i, j] = m[rows[i], j];
            return Value.matrix (out_m);
        }

        private static bool truthy (Value v, out Value? err) {
            err = null;
            switch (v.kind) {
                case ValueKind.NUMBER:
                case ValueKind.BOOL:
                    return v.number != 0;
                case ValueKind.EMPTY:
                    return false;
                case ValueKind.ERROR:
                    err = v;
                    return false;
                default:
                    err = Value.err (ErrorKind.VALUE);
                    return false;
            }
        }

        private static Value? int_list (Evaluator ev, Node n, Gee.ArrayList<int> out_list) {
            var m = mat (ev, n);
            for (int i = 0; i < m.length[0]; i++) for (int j = 0; j < m.length[1]; j++) {
                double d;
                var e = Evaluator.to_number (m[i, j], out d);
                if (e != null) return e;
                out_list.add ((int) Math.trunc (d));
            }
            return null;
        }

        private static Value sort_matrix (Value[,] src, Gee.ArrayList<int> idx, Gee.ArrayList<bool> desc, bool by_col) {
            var m = by_col ? transpose (src) : src;
            int r = m.length[0], c = m.length[1];
            foreach (int k in idx) if (k < 1 || k > c) return Value.err (ErrorKind.VALUE);
            var order = new Gee.ArrayList<int> ();
            for (int i = 0; i < r; i++) order.add (i);
            order.sort ((p, q) => {
                for (int k = 0; k < idx.size; k++) {
                    int cmp = sort_cmp (m[p, idx[k] - 1], m[q, idx[k] - 1], desc[k]);
                    if (cmp != 0) return cmp;
                }
                return p - q;
            });
            var out_m = new Value[r, c];
            for (int i = 0; i < r; i++) for (int j = 0; j < c; j++) out_m[i, j] = m[order[i], j];
            return Value.matrix (by_col ? transpose (out_m) : out_m);
        }

        private static Value stack (Evaluator ev, Node[] a, bool vertical) {
            var parts = new Gee.ArrayList<Value> ();
            int total = 0, span = 0;
            foreach (var n in a) {
                var v = ev.eval (n);
                if (v.kind == ValueKind.REFS) {
                    foreach (var ar in v.areas) {
                        var mm = ev.to_matrix (Value.range (ar));
                        parts.add (Value.matrix (mm));
                    }
                    continue;
                }
                parts.add (Value.matrix (ev.to_matrix (v)));
            }
            foreach (var p in parts) {
                total += vertical ? p.array.length[0] : p.array.length[1];
                span = int.max (span, vertical ? p.array.length[1] : p.array.length[0]);
            }
            var out_m = vertical ? new Value[total, span] : new Value[span, total];
            int at = 0;
            foreach (var p in parts) {
                var m = p.array;
                int pr = m.length[0], pc = m.length[1];
                if (vertical) {
                    for (int i = 0; i < pr; i++) for (int j = 0; j < span; j++) out_m[at + i, j] = j < pc ? empty_zero (m[i, j]) : Value.err (ErrorKind.NA);
                    at += pr;
                } else {
                    for (int i = 0; i < span; i++) for (int j = 0; j < pc; j++) out_m[i, at + j] = i < pr ? empty_zero (m[i, j]) : Value.err (ErrorKind.NA);
                    at += pc;
                }
            }
            return Value.matrix (out_m);
        }

        private static Value empty_zero (Value v) {
            return v.kind == ValueKind.EMPTY ? Value.num (0) : v;
        }

        private static Value take_drop (Evaluator ev, Node[] a, bool take) {
            var m = mat (ev, a[0]);
            int r = m.length[0], c = m.length[1];
            int nr = take ? r : 0, nc = take ? c : 0;
            Value? e = null;
            bool has_r = a.length > 1 && a[1].kind != NodeKind.MISSING;
            bool has_c = a.length > 2 && a[2].kind != NodeKind.MISSING;
            if (has_r && (e = ev.arg_int (a[1], out nr)) != null) return e;
            if (has_c && (e = ev.arg_int (a[2], out nc)) != null) return e;
            int r1 = 0, r2 = r, c1 = 0, c2 = c;
            if (take) {
                if (has_r) {
                    if (nr == 0) return calc_err ();
                    if (nr > 0) r2 = int.min (r, nr);
                    else r1 = int.max (0, r + nr);
                }
                if (has_c) {
                    if (nc == 0) return calc_err ();
                    if (nc > 0) c2 = int.min (c, nc);
                    else c1 = int.max (0, c + nc);
                }
            } else {
                if (nr > 0) r1 = int.min (r, nr);
                else if (nr < 0) r2 = int.max (0, r + nr);
                if (nc > 0) c1 = int.min (c, nc);
                else if (nc < 0) c2 = int.max (0, c + nc);
            }
            if (r2 <= r1 || c2 <= c1) return calc_err ();
            var out_m = new Value[r2 - r1, c2 - c1];
            for (int i = r1; i < r2; i++) for (int j = c1; j < c2; j++) out_m[i - r1, j - c1] = m[i, j];
            return Value.matrix (out_m);
        }

        private static Value choose (Evaluator ev, Node[] a, bool rows) {
            var m = mat (ev, a[0]);
            int len = rows ? m.length[0] : m.length[1];
            var picks = new Gee.ArrayList<int> ();
            for (int k = 1; k < a.length; k++) {
                var e = int_list (ev, a[k], picks);
                if (e != null) return e;
            }
            var fixed = new Gee.ArrayList<int> ();
            foreach (int p in picks) {
                if (p == 0 || p.abs () > len) return Value.err (ErrorKind.VALUE);
                fixed.add (p > 0 ? p - 1 : len + p);
            }
            if (rows) return pick_rows (m, fixed);
            var t = transpose (m);
            var r = pick_rows (t, fixed);
            if (r.is_error ()) return r;
            return Value.matrix (transpose (r.array));
        }

        private static Value flatten (Evaluator ev, Node[] a, bool to_col) {
            var m = mat (ev, a[0]);
            int ignore;
            bool by_col;
            Value? e = null;
            if ((e = opt_int (ev, a, 1, 0, out ignore)) != null) return e;
            if ((e = opt_bool (ev, a, 2, false, out by_col)) != null) return e;
            if (ignore < 0 || ignore > 3) return Value.err (ErrorKind.VALUE);
            var list = new Gee.ArrayList<Value> ();
            int r = m.length[0], c = m.length[1];
            for (int o = 0; o < (by_col ? c : r); o++) {
                for (int i = 0; i < (by_col ? r : c); i++) {
                    var v = by_col ? m[i, o] : m[o, i];
                    if ((ignore & 1) != 0 && v.kind == ValueKind.EMPTY) continue;
                    if ((ignore & 2) != 0 && v.is_error ()) continue;
                    list.add (empty_zero (v));
                }
            }
            if (list.size == 0) return calc_err ();
            var out_m = to_col ? new Value[list.size, 1] : new Value[1, list.size];
            for (int i = 0; i < list.size; i++) {
                if (to_col) out_m[i, 0] = list[i];
                else out_m[0, i] = list[i];
            }
            return Value.matrix (out_m);
        }

        private static Value wrap (Evaluator ev, Node[] a, bool rows) {
            var m = mat (ev, a[0]);
            if (m.length[0] > 1 && m.length[1] > 1) return Value.err (ErrorKind.VALUE);
            int count;
            var e = ev.arg_int (a[1], out count);
            if (e != null) return e;
            if (count < 1) return Value.err (ErrorKind.NUM);
            var pad = a.length > 2 && a[2].kind != NodeKind.MISSING ? ev.arg (a[2]) : Value.err (ErrorKind.NA);
            int n = m.length[0] * m.length[1];
            int groups = (n + count - 1) / count;
            var out_m = rows ? new Value[groups, count] : new Value[count, groups];
            for (int g = 0; g < groups; g++) {
                for (int i = 0; i < count; i++) {
                    int k = g * count + i;
                    var v = k < n ? empty_zero (m[k / m.length[1], k % m.length[1]]) : pad;
                    if (rows) out_m[g, i] = v;
                    else out_m[i, g] = v;
                }
            }
            return Value.matrix (out_m);
        }

        public static void register () {
            add ("FILTER", 2, 3, "FILTER(array, include, [if_empty])", _("Filters a range by conditions"), (ev, a) => {
                var m = mat (ev, a[0]);
                var inc = mat (ev, a[1]);
                int r = m.length[0], c = m.length[1];
                bool by_rows = inc.length[1] == 1 && inc.length[0] == r;
                bool by_cols = inc.length[0] == 1 && inc.length[1] == c;
                if (!by_rows && !by_cols) return Value.err (ErrorKind.VALUE);
                if (by_rows && by_cols && r == 1 && c > 1) by_rows = false;
                var keep = new Gee.ArrayList<int> ();
                int len = by_rows ? r : c;
                for (int i = 0; i < len; i++) {
                    Value? err;
                    bool t = truthy (by_rows ? inc[i, 0] : inc[0, i], out err);
                    if (err != null) return err;
                    if (t) keep.add (i);
                }
                if (keep.size == 0) {
                    if (a.length > 2 && a[2].kind != NodeKind.MISSING) return ev.eval (a[2]);
                    return calc_err ();
                }
                if (by_rows) return pick_rows (m, keep);
                var picked = pick_rows (transpose (m), keep);
                return Value.matrix (transpose (picked.array));
            });
            add ("SORT", 1, 4, "SORT(array, [sort_index], [sort_order], [by_col])", _("Sorts the contents of a range"), (ev, a) => {
                var m = mat (ev, a[0]);
                var idx = new Gee.ArrayList<int> ();
                var ord = new Gee.ArrayList<int> ();
                Value? e = null;
                if (a.length > 1 && a[1].kind != NodeKind.MISSING && (e = int_list (ev, a[1], idx)) != null) return e;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING && (e = int_list (ev, a[2], ord)) != null) return e;
                bool by_col;
                if ((e = opt_bool (ev, a, 3, false, out by_col)) != null) return e;
                if (idx.size == 0) idx.add (1);
                var desc = new Gee.ArrayList<bool> ();
                for (int k = 0; k < idx.size; k++) {
                    int o = ord.size == 0 ? 1 : ord[int.min (k, ord.size - 1)];
                    if (o != 1 && o != -1) return Value.err (ErrorKind.VALUE);
                    desc.add (o == -1);
                }
                return sort_matrix (m, idx, desc, by_col);
            });
            add ("SORTBY", 2, -1, "SORTBY(array, by_array1, [sort_order1], ...)", _("Sorts a range by the values of other ranges"), (ev, a) => {
                var m = mat (ev, a[0]);
                int r = m.length[0], c = m.length[1];
                var keys = new Gee.ArrayList<Value> ();
                var desc = new Gee.ArrayList<bool> ();
                bool? by_row = null;
                for (int k = 1; k < a.length; k += 2) {
                    var km = mat (ev, a[k]);
                    bool vert = km.length[1] == 1 && km.length[0] == r;
                    bool horiz = km.length[0] == 1 && km.length[1] == c;
                    if (vert && horiz) vert = r > 1 || c == 1;
                    if (!vert && !horiz) return Value.err (ErrorKind.VALUE);
                    if (by_row != null && by_row != vert) return Value.err (ErrorKind.VALUE);
                    by_row = vert;
                    keys.add (Value.matrix (km));
                    int o = 1;
                    if (k + 1 < a.length && a[k + 1].kind != NodeKind.MISSING) {
                        var e = ev.arg_int (a[k + 1], out o);
                        if (e != null) return e;
                    }
                    if (o != 1 && o != -1) return Value.err (ErrorKind.VALUE);
                    desc.add (o == -1);
                }
                bool rows_mode = by_row ?? true;
                int len = rows_mode ? r : c;
                var order = new Gee.ArrayList<int> ();
                for (int i = 0; i < len; i++) order.add (i);
                order.sort ((p, q) => {
                    for (int k = 0; k < keys.size; k++) {
                        var km = keys[k].array;
                        var x = rows_mode ? km[p, 0] : km[0, p];
                        var y = rows_mode ? km[q, 0] : km[0, q];
                        int cmp = sort_cmp (x, y, desc[k]);
                        if (cmp != 0) return cmp;
                    }
                    return p - q;
                });
                if (rows_mode) return pick_rows (m, order);
                var picked = pick_rows (transpose (m), order);
                return Value.matrix (transpose (picked.array));
            });
            add ("UNIQUE", 1, 3, "UNIQUE(array, [by_col], [exactly_once])", _("The unique values of a range"), (ev, a) => {
                var m = mat (ev, a[0]);
                bool by_col, once;
                Value? e = null;
                if ((e = opt_bool (ev, a, 1, false, out by_col)) != null) return e;
                if ((e = opt_bool (ev, a, 2, false, out once)) != null) return e;
                var src = by_col ? transpose (m) : m;
                int r = src.length[0], c = src.length[1];
                var counts = new Gee.HashMap<string, int> ();
                var first = new Gee.ArrayList<int> ();
                var keys = new string[r];
                for (int i = 0; i < r; i++) {
                    var sb = new StringBuilder ();
                    for (int j = 0; j < c; j++) {
                        sb.append (key_of (src[i, j]));
                        sb.append_c ('\x1f');
                    }
                    keys[i] = sb.str;
                    if (!counts.has_key (keys[i])) {
                        counts[keys[i]] = 0;
                        first.add (i);
                    }
                    counts[keys[i]] = counts[keys[i]] + 1;
                }
                var keep = new Gee.ArrayList<int> ();
                foreach (int i in first) if (!once || counts[keys[i]] == 1) keep.add (i);
                if (keep.size == 0) return calc_err ();
                var res = pick_rows (src, keep);
                var rm = res.array;
                for (int i = 0; i < rm.length[0]; i++) for (int j = 0; j < rm.length[1]; j++) rm[i, j] = empty_zero (rm[i, j]);
                return by_col ? Value.matrix (transpose (rm)) : res;
            });
            Functions.add ("SEQUENCE", 1, 4, "Math", "SEQUENCE(rows, [columns], [start], [step])", _("A list of sequential numbers"), (ev, a) => {
                double rows_d = 1, cols_d = 1, start = 1, step = 1;
                Value? e = null;
                if (a[0].kind != NodeKind.MISSING && (e = ev.arg_number (a[0], out rows_d)) != null) return e;
                if (a.length > 1 && a[1].kind != NodeKind.MISSING && (e = ev.arg_number (a[1], out cols_d)) != null) return e;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING && (e = ev.arg_number (a[2], out start)) != null) return e;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_number (a[3], out step)) != null) return e;
                int rows = (int) Math.trunc (rows_d), cols = (int) Math.trunc (cols_d);
                if (rows == 0 || cols == 0) return calc_err ();
                if (rows < 0 || cols < 0 || (int64) rows * cols > 4000000) return Value.err (ErrorKind.VALUE);
                var m = new Value[rows, cols];
                for (int i = 0; i < rows; i++) for (int j = 0; j < cols; j++) m[i, j] = Value.num (start + step * (i * cols + j));
                return Value.matrix (m);
            });
            Functions.add ("RANDARRAY", 0, 5, "Math", "RANDARRAY([rows], [columns], [min], [max], [integer])", _("An array of random numbers"), (ev, a) => {
                double rows_d = 1, cols_d = 1, lo = 0, hi = 1;
                bool integer = false;
                Value? e = null;
                if (a.length > 0 && a[0].kind != NodeKind.MISSING && (e = ev.arg_number (a[0], out rows_d)) != null) return e;
                if (a.length > 1 && a[1].kind != NodeKind.MISSING && (e = ev.arg_number (a[1], out cols_d)) != null) return e;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING && (e = ev.arg_number (a[2], out lo)) != null) return e;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_number (a[3], out hi)) != null) return e;
                if ((e = opt_bool (ev, a, 4, false, out integer)) != null) return e;
                int rows = (int) Math.trunc (rows_d), cols = (int) Math.trunc (cols_d);
                if (rows == 0 || cols == 0) return calc_err ();
                if (rows < 0 || cols < 0 || hi < lo || (int64) rows * cols > 4000000) return Value.err (ErrorKind.VALUE);
                if (integer && (lo != Math.floor (lo) || hi != Math.floor (hi))) return Value.err (ErrorKind.VALUE);
                var m = new Value[rows, cols];
                for (int i = 0; i < rows; i++) for (int j = 0; j < cols; j++) {
                    double v = integer ? Math.floor (lo + Random.next_double () * (hi - lo + 1)) : lo + Random.next_double () * (hi - lo);
                    if (integer && v > hi) v = hi;
                    m[i, j] = Value.num (v);
                }
                return Value.matrix (m);
            });
            add ("VSTACK", 1, -1, "VSTACK(array1, [array2], ...)", _("Stacks arrays vertically"), (ev, a) => stack (ev, a, true));
            add ("HSTACK", 1, -1, "HSTACK(array1, [array2], ...)", _("Stacks arrays horizontally"), (ev, a) => stack (ev, a, false));
            add ("TAKE", 2, 3, "TAKE(array, rows, [columns])", _("Rows or columns from the start or end of an array"), (ev, a) => take_drop (ev, a, true));
            add ("DROP", 2, 3, "DROP(array, rows, [columns])", _("Removes rows or columns from the start or end of an array"), (ev, a) => take_drop (ev, a, false));
            add ("CHOOSEROWS", 2, -1, "CHOOSEROWS(array, row_num1, [row_num2], ...)", _("The specified rows of an array"), (ev, a) => choose (ev, a, true));
            add ("CHOOSECOLS", 2, -1, "CHOOSECOLS(array, col_num1, [col_num2], ...)", _("The specified columns of an array"), (ev, a) => choose (ev, a, false));
            add ("EXPAND", 2, 4, "EXPAND(array, rows, [columns], [pad_with])", _("Expands an array to given dimensions"), (ev, a) => {
                var m = mat (ev, a[0]);
                int r = m.length[0], c = m.length[1];
                int nr = r, nc = c;
                Value? e = null;
                if (a[1].kind != NodeKind.MISSING && (e = ev.arg_int (a[1], out nr)) != null) return e;
                if ((e = opt_int (ev, a, 2, c, out nc)) != null) return e;
                if (nr < r || nc < c) return Value.err (ErrorKind.VALUE);
                if ((int64) nr * nc > 4000000) return Value.err (ErrorKind.NUM);
                var pad = a.length > 3 && a[3].kind != NodeKind.MISSING ? ev.arg (a[3]) : Value.err (ErrorKind.NA);
                var out_m = new Value[nr, nc];
                for (int i = 0; i < nr; i++) for (int j = 0; j < nc; j++) out_m[i, j] = i < r && j < c ? m[i, j] : pad;
                return Value.matrix (out_m);
            });
            add ("TOCOL", 1, 3, "TOCOL(array, [ignore], [scan_by_column])", _("An array as a single column"), (ev, a) => flatten (ev, a, true));
            add ("TOROW", 1, 3, "TOROW(array, [ignore], [scan_by_column])", _("An array as a single row"), (ev, a) => flatten (ev, a, false));
            add ("WRAPROWS", 2, 3, "WRAPROWS(vector, wrap_count, [pad_with])", _("Wraps a vector into rows"), (ev, a) => wrap (ev, a, true));
            add ("WRAPCOLS", 2, 3, "WRAPCOLS(vector, wrap_count, [pad_with])", _("Wraps a vector into columns"), (ev, a) => wrap (ev, a, false));
            add ("TRIMRANGE", 1, 3, "TRIMRANGE(range, [trim_rows], [trim_cols])", _("A range without its empty outer rows and columns"), (ev, a) => {
                var v = ev.eval (a[0]);
                int tr, tc;
                Value? e = null;
                if ((e = opt_int (ev, a, 1, 3, out tr)) != null) return e;
                if ((e = opt_int (ev, a, 2, 3, out tc)) != null) return e;
                if (tr < 0 || tr > 3 || tc < 0 || tc > 3) return Value.err (ErrorKind.VALUE);
                if (v.kind != ValueKind.RANGE) return v.kind == ValueKind.ARRAY ? v : Value.err (ErrorKind.VALUE);
                var ar = v.area;
                var s = ar.sheet ?? ev.sheet;
                int r1 = int.max (ar.r1, 0), r2 = int.min (ar.r2, s.max_row), c1 = ar.c1, c2 = int.min (ar.c2, s.max_col);
                int min_r = int.MAX, max_r = -1, min_c = int.MAX, max_c = -1;
                for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) {
                    if (s.value_at (r, c).is_empty ()) continue;
                    min_r = int.min (min_r, r);
                    max_r = int.max (max_r, r);
                    min_c = int.min (min_c, c);
                    max_c = int.max (max_c, c);
                }
                if (max_r < 0) return Value.err (ErrorKind.REF);
                int nr1 = (tr & 1) != 0 ? min_r : ar.r1;
                int nr2 = (tr & 2) != 0 ? max_r : ar.r2;
                int nc1 = (tc & 1) != 0 ? min_c : ar.c1;
                int nc2 = (tc & 2) != 0 ? max_c : ar.c2;
                return Value.range (new Area (ar.sheet, nr1, nc1, nr2, nc2));
            });
            Functions.add ("PERCENTOF", 2, 2, "Math", "PERCENTOF(data_subset, data_all)", _("The share of a subset in the total"), (ev, a) => {
                var sub = new Gee.ArrayList<double?> ();
                var all = new Gee.ArrayList<double?> ();
                var e = ev.numbers ({ a[0] }, sub);
                if (e != null) return e;
                if ((e = ev.numbers ({ a[1] }, all)) != null) return e;
                double s1 = 0, s2 = 0;
                foreach (var d in sub) s1 += d;
                foreach (var d in all) s2 += d;
                if (s2 == 0) return Value.err (ErrorKind.DIV0);
                return Value.num (s1 / s2);
            });
            add ("FORMULATEXT", 1, 1, "FORMULATEXT(reference)", _("The formula of a cell as text"), (ev, a) => {
                var v = ev.eval (a[0]);
                if (v.kind != ValueKind.RANGE) return Value.err (ErrorKind.NA);
                var s = v.area.sheet ?? ev.sheet;
                var cell = s.get_cell (v.area.r1, v.area.c1);
                if (cell == null || cell.formula == null) return Value.err (ErrorKind.NA);
                return Value.str (cell.input);
            });
            add ("GROUPBY", 3, 8, "GROUPBY(row_fields, values, function, [field_headers], [total_depth], [sort_order], [filter_array], [field_relationship])", _("Groups rows and aggregates their values"), (ev, a) => Grouping.groupby (ev, a));
            add ("PIVOTBY", 4, 11, "PIVOTBY(row_fields, col_fields, values, function, [field_headers], [row_total_depth], [row_sort_order], [col_total_depth], [col_sort_order], [filter_array], [relative_to])", _("Summarizes values by rows and columns"), (ev, a) => Grouping.pivotby (ev, a));
        }
    }

    public class Grouping {
        private static Value? get_fn (Evaluator ev, Node n, out Lambda? f) {
            return LambdaFunctions.to_lambda (ev, n, out f);
        }

        private static int arity (Lambda f) {
            if (f.builtin == "PERCENTOF") return 2;
            if (f.builtin != "") return 1;
            return f.arity;
        }

        private static Value column (Gee.List<Value> vals) {
            if (vals.size == 0) return Value.matrix (new Value[1, 1] { { Value.empty () } });
            var m = new Value[vals.size, 1];
            for (int i = 0; i < vals.size; i++) m[i, 0] = vals[i];
            return Value.matrix (m);
        }

        private static Value apply (Evaluator ev, Lambda f, Gee.List<Value> subset, Gee.List<Value> all) {
            Value r = arity (f) >= 2 ? ev.call_lambda (f, { column (subset), column (all) }) : ev.call_lambda (f, { column (subset) });
            if (r.kind == ValueKind.RANGE) {
                if (!r.area.is_single ()) return Value.err (ErrorKind.CALC);
                r = ev.cell (r.area.sheet, r.area.r1, r.area.c1);
            }
            if (r.kind == ValueKind.ARRAY) {
                if (r.array.length[0] * r.array.length[1] != 1) return Value.err (ErrorKind.CALC);
                r = r.array[0, 0];
            }
            return r;
        }

        private static int detect_headers (Value[,] vals) {
            if (vals.length[0] < 2) return 0;
            for (int j = 0; j < vals.length[1]; j++) {
                if (vals[0, j].kind != ValueKind.TEXT) return 0;
                if (vals[1, j].kind == ValueKind.TEXT) return 0;
            }
            return 3;
        }

        private class Row {
            public Value[] cells;

            public Row (Value[] cells) {
                this.cells = cells;
            }
        }

        private class Group {
            public Value[] fields;
            public string key;
            public Gee.ArrayList<int> rows = new Gee.ArrayList<int> ();
        }

        private static string tuple_key (Value[] f, int upto) {
            var sb = new StringBuilder ();
            for (int i = 0; i < upto; i++) {
                sb.append (ArrayFunctions.key_of (f[i]));
                sb.append_c ('\x1f');
            }
            return sb.str;
        }

        private static Gee.ArrayList<Group> groups_of (Value[,] fields, Gee.List<int> rows) {
            var map = new Gee.HashMap<string, Group> ();
            var list = new Gee.ArrayList<Group> ();
            int k = fields.length[1];
            foreach (int r in rows) {
                Value[] f = new Value[k];
                for (int j = 0; j < k; j++) f[j] = fields[r, j];
                string key = tuple_key (f, k);
                var g = map[key];
                if (g == null) {
                    g = new Group ();
                    g.fields = f;
                    g.key = key;
                    map[key] = g;
                    list.add (g);
                }
                g.rows.add (r);
            }
            return list;
        }

        private static void sort_groups (Gee.ArrayList<Group> groups, int order_index, bool desc) {
            groups.sort ((x, y) => {
                int k = x.fields.length;
                if (order_index >= 0 && order_index < k) {
                    int c = ArrayFunctions.sort_cmp (x.fields[order_index], y.fields[order_index], desc);
                    if (c != 0) return c;
                }
                for (int i = 0; i < k; i++) {
                    int c = ArrayFunctions.sort_cmp (x.fields[i], y.fields[i], false);
                    if (c != 0) return c;
                }
                return 0;
            });
        }

        private static Gee.ArrayList<Value> values_at (Value[,] vals, int col, Gee.List<int> rows) {
            var l = new Gee.ArrayList<Value> ();
            foreach (int r in rows) l.add (vals[r, col]);
            return l;
        }

        private static Value? filtered_rows (Evaluator ev, Node[] a, int filter_at, int start, int n, Gee.ArrayList<int> rows) {
            Value[,]? filt = null;
            if (a.length > filter_at && a[filter_at].kind != NodeKind.MISSING) filt = ev.to_matrix (ev.eval (a[filter_at]));
            for (int r = start; r < n; r++) {
                if (filt != null) {
                    int fi = filt.length[0] == n ? r : r - start;
                    if (fi < 0 || fi >= filt.length[0]) return Value.err (ErrorKind.VALUE);
                    var fv = filt[fi, 0];
                    if (fv.is_error ()) return fv;
                    if (!(fv.kind == ValueKind.BOOL || fv.kind == ValueKind.NUMBER) || fv.number == 0) continue;
                }
                rows.add (r);
            }
            return null;
        }

        public static Value groupby (Evaluator ev, Node[] a) {
            var fields = ev.to_matrix (ev.eval (a[0]));
            var vals = ev.to_matrix (ev.eval (a[1]));
            int n = fields.length[0];
            if (vals.length[0] != n) return Value.err (ErrorKind.VALUE);
            Lambda f;
            var e = get_fn (ev, a[2], out f);
            if (e != null) return e;
            int headers = -1, depth = 1, order = 1;
            if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_int (a[3], out headers)) != null) return e;
            if (headers < 0) headers = detect_headers (vals);
            if (a.length > 4 && a[4].kind != NodeKind.MISSING && (e = ev.arg_int (a[4], out depth)) != null) return e;
            if (a.length > 5 && a[5].kind != NodeKind.MISSING && (e = ev.arg_int (a[5], out order)) != null) return e;
            bool has_head = headers == 1 || headers == 3;
            bool show_head = headers == 2 || headers == 3;
            int kr = fields.length[1], kv = vals.length[1];
            var rows = new Gee.ArrayList<int> ();
            e = filtered_rows (ev, a, 6, has_head ? 1 : 0, n, rows);
            if (e != null) return e;
            var groups = groups_of (fields, rows);
            int oi = order.abs () - 1;
            var out_rows = new Gee.ArrayList<Row> ();
            var gmap = new Gee.HashMap<string, Group> ();
            foreach (var g in groups) gmap[g.key] = g;
            if (oi >= kr && oi < kr + kv) {
                var aggs = new Gee.HashMap<string, Value> ();
                foreach (var g in groups) aggs[g.key] = apply (ev, f, values_at (vals, oi - kr, g.rows), values_at (vals, oi - kr, rows));
                groups.sort ((x, y) => ArrayFunctions.sort_cmp (aggs[x.key], aggs[y.key], order < 0));
            } else {
                sort_groups (groups, oi, order < 0);
            }
            if (show_head) {
                Value[] h = new Value[kr + kv];
                for (int j = 0; j < kr; j++) h[j] = has_head ? fields[0, j] : Value.str (_("Row Field %d").printf (j + 1));
                for (int j = 0; j < kv; j++) h[kr + j] = has_head ? vals[0, j] : Value.str (_("Value %d").printf (j + 1));
                out_rows.add (new Row (h));
            }
            var body = new Gee.ArrayList<Row> ();
            string? prev = null;
            var sub_rows = new Gee.ArrayList<int> ();
            bool subtotals = depth.abs () >= 2 && kr >= 2;
            for (int gi = 0; gi < groups.size; gi++) {
                var g = groups[gi];
                string top = ArrayFunctions.key_of (g.fields[0]);
                if (subtotals && prev != null && top != prev) {
                    body.add (new Row (subtotal_row (ev, f, groups[gi - 1].fields[0], kr, kv, vals, sub_rows, rows)));
                    sub_rows = new Gee.ArrayList<int> ();
                }
                prev = top;
                sub_rows.add_all (g.rows);
                Value[] row = new Value[kr + kv];
                for (int j = 0; j < kr; j++) row[j] = g.fields[j];
                for (int j = 0; j < kv; j++) row[kr + j] = apply (ev, f, values_at (vals, j, g.rows), values_at (vals, j, rows));
                body.add (new Row (row));
            }
            if (subtotals && groups.size > 0) body.add (new Row (subtotal_row (ev, f, groups[groups.size - 1].fields[0], kr, kv, vals, sub_rows, rows)));
            Value[]? total = null;
            if (depth != 0) {
                total = new Value[kr + kv];
                total[0] = Value.str (_("Total"));
                for (int j = 1; j < kr; j++) total[j] = Value.empty ();
                for (int j = 0; j < kv; j++) total[kr + j] = apply (ev, f, values_at (vals, j, rows), values_at (vals, j, rows));
            }
            if (total != null && depth < 0) out_rows.add (new Row (total));
            out_rows.add_all (body);
            if (total != null && depth > 0) out_rows.add (new Row (total));
            if (out_rows.size == 0) return Value.err (ErrorKind.CALC);
            var m = new Value[out_rows.size, kr + kv];
            for (int i = 0; i < out_rows.size; i++) for (int j = 0; j < kr + kv; j++) m[i, j] = out_rows[i].cells[j];
            return Value.matrix (m);
        }

        private static Value[] subtotal_row (Evaluator ev, Lambda f, Value label, int kr, int kv, Value[,] vals, Gee.List<int> sub, Gee.List<int> all) {
            Value[] row = new Value[kr + kv];
            row[0] = label;
            for (int j = 1; j < kr; j++) row[j] = Value.empty ();
            for (int j = 0; j < kv; j++) row[kr + j] = apply (ev, f, values_at (vals, j, sub), values_at (vals, j, all));
            return row;
        }

        public static Value pivotby (Evaluator ev, Node[] a) {
            var rf = ev.to_matrix (ev.eval (a[0]));
            var cf = ev.to_matrix (ev.eval (a[1]));
            var vals = ev.to_matrix (ev.eval (a[2]));
            int n = rf.length[0];
            if (cf.length[0] != n || vals.length[0] != n) return Value.err (ErrorKind.VALUE);
            Lambda f;
            var e = get_fn (ev, a[3], out f);
            if (e != null) return e;
            int headers = -1, rdepth = 1, rorder = 1, cdepth = 1, corder = 1, relative = 0;
            if (a.length > 4 && a[4].kind != NodeKind.MISSING && (e = ev.arg_int (a[4], out headers)) != null) return e;
            if (headers < 0) headers = detect_headers (vals);
            if (a.length > 5 && a[5].kind != NodeKind.MISSING && (e = ev.arg_int (a[5], out rdepth)) != null) return e;
            if (a.length > 6 && a[6].kind != NodeKind.MISSING && (e = ev.arg_int (a[6], out rorder)) != null) return e;
            if (a.length > 7 && a[7].kind != NodeKind.MISSING && (e = ev.arg_int (a[7], out cdepth)) != null) return e;
            if (a.length > 8 && a[8].kind != NodeKind.MISSING && (e = ev.arg_int (a[8], out corder)) != null) return e;
            if (a.length > 10 && a[10].kind != NodeKind.MISSING && (e = ev.arg_int (a[10], out relative)) != null) return e;
            bool has_head = headers == 1 || headers == 3;
            bool show_head = headers == 2 || headers == 3;
            int kr = rf.length[1], kc = cf.length[1], kv = vals.length[1];
            var rows = new Gee.ArrayList<int> ();
            e = filtered_rows (ev, a, 9, has_head ? 1 : 0, n, rows);
            if (e != null) return e;
            var rgroups = groups_of (rf, rows);
            var cgroups = groups_of (cf, rows);
            sort_groups (rgroups, rorder.abs () - 1, rorder < 0);
            sort_groups (cgroups, corder.abs () - 1, corder < 0);
            var rset = new Gee.HashMap<string, Gee.HashSet<int>> ();
            foreach (var g in rgroups) {
                var hs = new Gee.HashSet<int> ();
                hs.add_all (g.rows);
                rset[g.key] = hs;
            }
            int head_rows = kc + (kv > 1 || show_head ? 1 : 0);
            int ncols_data = (cgroups.size + (cdepth != 0 ? 1 : 0)) * kv;
            int nrows_data = rgroups.size + (rdepth != 0 ? 1 : 0);
            int width = kr + ncols_data, height = head_rows + nrows_data;
            var m = new Value[height, width];
            for (int i = 0; i < height; i++) for (int j = 0; j < width; j++) m[i, j] = Value.empty ();
            var col_sets = new Gee.ArrayList<Gee.ArrayList<int>> ();
            var col_labels = new Gee.ArrayList<Row> ();
            foreach (var g in cgroups) {
                col_sets.add (g.rows);
                col_labels.add (new Row (g.fields));
            }
            if (cdepth != 0) {
                Value[] tl = new Value[kc];
                tl[0] = Value.str (_("Total"));
                for (int j = 1; j < kc; j++) tl[j] = Value.empty ();
                if (cdepth > 0) {
                    col_sets.add (rows);
                    col_labels.add (new Row (tl));
                } else {
                    col_sets.insert (0, rows);
                    col_labels.insert (0, new Row (tl));
                }
            }
            var row_sets = new Gee.ArrayList<Gee.ArrayList<int>> ();
            var row_labels = new Gee.ArrayList<Row> ();
            foreach (var g in rgroups) {
                row_sets.add (g.rows);
                row_labels.add (new Row (g.fields));
            }
            if (rdepth != 0) {
                Value[] tl = new Value[kr];
                tl[0] = Value.str (_("Total"));
                for (int j = 1; j < kr; j++) tl[j] = Value.empty ();
                if (rdepth > 0) {
                    row_sets.add (rows);
                    row_labels.add (new Row (tl));
                } else {
                    row_sets.insert (0, rows);
                    row_labels.insert (0, new Row (tl));
                }
            }
            for (int ci = 0; ci < col_sets.size; ci++) {
                for (int v = 0; v < kv; v++) {
                    int col = kr + ci * kv + v;
                    for (int l = 0; l < kc; l++) m[l, col] = col_labels[ci].cells[l];
                    if (head_rows > kc) m[kc, col] = has_head ? vals[0, v] : Value.str (_("Value %d").printf (v + 1));
                }
            }
            if (show_head && head_rows > 0) {
                for (int j = 0; j < kr; j++) m[head_rows - 1, j] = has_head ? rf[0, j] : Value.str (_("Row Field %d").printf (j + 1));
            }
            for (int ri = 0; ri < row_sets.size; ri++) {
                int row = head_rows + ri;
                for (int j = 0; j < kr; j++) m[row, j] = row_labels[ri].cells[j];
                var rs = new Gee.HashSet<int> ();
                rs.add_all (row_sets[ri]);
                for (int ci = 0; ci < col_sets.size; ci++) {
                    var cell_rows = new Gee.ArrayList<int> ();
                    foreach (int r in col_sets[ci]) if (rs.contains (r)) cell_rows.add (r);
                    for (int v = 0; v < kv; v++) {
                        int col = kr + ci * kv + v;
                        if (cell_rows.size == 0) continue;
                        Gee.List<int> rel = relative == 1 || relative == 4 ? row_sets[ri] : (relative == 2 ? rows : col_sets[ci]);
                        m[row, col] = apply (ev, f, values_at (vals, v, cell_rows), values_at (vals, v, rel));
                    }
                }
            }
            return Value.matrix (m);
        }
    }
}
