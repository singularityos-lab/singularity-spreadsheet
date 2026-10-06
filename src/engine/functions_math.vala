namespace Singularity.Apps.Spreadsheet {

    public delegate Value ScalarFn (Value[] v);

    public class MoreMathFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Math", syntax, summary, (owned) impl);
        }

        public static Value lift (Evaluator ev, Node[] a, ScalarFn f) {
            int n = a.length;
            Value[] raw = new Value[n];
            bool multi = false;
            for (int i = 0; i < n; i++) {
                raw[i] = a[i].kind == NodeKind.MISSING ? Value.missing () : ev.eval (a[i]);
                if (raw[i].kind == ValueKind.ARRAY || (raw[i].kind == ValueKind.RANGE && !raw[i].area.is_single ())) multi = true;
            }
            if (!multi) {
                Value[] s = new Value[n];
                for (int i = 0; i < n; i++) s[i] = raw[i].omitted ? raw[i] : ev.deref (raw[i]);
                return f (s);
            }
            var mats = new Gee.ArrayList<Value> ();
            int rows = 1, cols = 1;
            for (int i = 0; i < n; i++) {
                bool m = raw[i].kind == ValueKind.ARRAY || (raw[i].kind == ValueKind.RANGE && !raw[i].area.is_single ());
                if (m) {
                    var mm = ev.to_matrix (raw[i]);
                    mats.add (Value.matrix (mm));
                    rows = int.max (rows, mm.length[0]);
                    cols = int.max (cols, mm.length[1]);
                } else {
                    var one = new Value[1, 1];
                    one[0, 0] = raw[i].omitted ? raw[i] : ev.deref (raw[i]);
                    mats.add (Value.matrix (one));
                }
            }
            var out_m = new Value[rows, cols];
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c < cols; c++) {
                    Value[] args = new Value[n];
                    bool bad = false;
                    for (int i = 0; i < n; i++) {
                        var m = mats[i].array;
                        int ii = m.length[0] == 1 ? 0 : r;
                        int jj = m.length[1] == 1 ? 0 : c;
                        if (ii >= m.length[0] || jj >= m.length[1]) {
                            bad = true;
                            break;
                        }
                        args[i] = m[ii, jj];
                    }
                    out_m[r, c] = bad ? Value.err (ErrorKind.NA) : f (args);
                }
            }
            return Value.matrix (out_m);
        }

        public static bool given (Value v) {
            return !v.omitted;
        }

        public static Value? num (Value v, out double d) {
            return Evaluator.to_number (v, out d);
        }

        public static Value? num_or (Value v, double def, out double d) {
            if (v.omitted) {
                d = def;
                return null;
            }
            return Evaluator.to_number (v, out d);
        }

        public static Value? flag (Value v, bool def, out bool b) {
            b = def;
            if (v.omitted || v.kind == ValueKind.EMPTY) return null;
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

        public delegate Value? Unary (double x);

        private static void unary (string name, string summary, owned Unary f) {
            Unary fn = (owned) f;
            add (name, 1, 1, name + "(number)", summary, (ev, a) => lift (ev, a, (v) => {
                double x;
                var e = num (v[0], out x);
                if (e != null) return e;
                var r = fn (x);
                return r;
            }));
        }

        public static void numbers_of (Evaluator ev, Node n, Gee.ArrayList<double?> nums_out, Gee.ArrayList<bool> ok_out) {
            var m = ev.to_matrix (ev.eval (n));
            for (int i = 0; i < m.length[0]; i++) {
                for (int j = 0; j < m.length[1]; j++) {
                    var v = m[i, j];
                    nums_out.add (v.kind == ValueKind.NUMBER ? v.number : 0);
                    ok_out.add (v.kind == ValueKind.NUMBER);
                }
            }
        }

        private delegate double PairOp (double x, double y);

        private static void pair_sum (string name, string summary, owned PairOp f) {
            PairOp op = (owned) f;
            add (name, 2, 2, name + "(array_x, array_y)", summary, (ev, a) => {
                var vx = ev.eval (a[0]);
                var vy = ev.eval (a[1]);
                var mx = ev.to_matrix (vx);
                var my = ev.to_matrix (vy);
                if (mx.length[0] * mx.length[1] != my.length[0] * my.length[1]) return Value.err (ErrorKind.NA);
                int cx = mx.length[1], cy = my.length[1];
                int total = mx.length[0] * cx;
                double s = 0;
                int pairs = 0;
                for (int k = 0; k < total; k++) {
                    var x = mx[k / cx, k % cx];
                    var y = my[k / cy, k % cy];
                    if (x.is_error ()) return x;
                    if (y.is_error ()) return y;
                    if (x.kind != ValueKind.NUMBER || y.kind != ValueKind.NUMBER) continue;
                    s += op (x.number, y.number);
                    pairs++;
                }
                if (pairs == 0) return Value.err (ErrorKind.DIV0);
                return Value.num (s);
            });
        }

        public static string roman (int value, int mode) {
            unichar[] chars = { 'M', 'D', 'C', 'L', 'X', 'V', 'I' };
            int[] values = { 1000, 500, 100, 50, 10, 5, 1 };
            int max_index = 6;
            var sb = new StringBuilder ();
            int val = value;
            for (int i = 0; i <= max_index / 2; i++) {
                int index = 2 * i;
                int digit = val / values[index];
                if (digit % 5 == 4) {
                    int index2 = digit == 4 ? index - 1 : index - 2;
                    int steps = 0;
                    while (steps < mode && index < max_index) {
                        steps++;
                        if (values[index2] - values[index + 1] <= val) index++;
                        else steps = mode;
                    }
                    sb.append_unichar (chars[index]);
                    sb.append_unichar (chars[index2]);
                    val = val + values[index] - values[index2];
                } else {
                    if (digit > 4) sb.append_unichar (chars[index - 1]);
                    for (int k = 0; k < digit % 5; k++) sb.append_unichar (chars[index]);
                    val %= values[index];
                }
            }
            return sb.str;
        }

        private static int roman_digit (char c) {
            switch (c.toupper ()) {
                case 'I': return 1;
                case 'V': return 5;
                case 'X': return 10;
                case 'L': return 50;
                case 'C': return 100;
                case 'D': return 500;
                case 'M': return 1000;
                default: return 0;
            }
        }

        public static double factorial (double n) {
            double r = 1;
            for (int i = 2; i <= (int) n; i++) r *= i;
            return r;
        }

        public static double combin (double n, double k) {
            if (k < 0 || n < k) return double.NAN;
            return Math.round (Math.exp (Functions.lgamma (n + 1) - Functions.lgamma (k + 1) - Functions.lgamma (n - k + 1)));
        }

        public static void register () {
            unary ("SEC", _("Secant of an angle"), (x) => {
                if (Math.fabs (x) >= 134217728) return Value.err (ErrorKind.NUM);
                double c = Math.cos (x);
                return c == 0 ? Value.err (ErrorKind.DIV0) : Value.num (1 / c);
            });
            unary ("CSC", _("Cosecant of an angle"), (x) => {
                if (Math.fabs (x) >= 134217728) return Value.err (ErrorKind.NUM);
                double s = Math.sin (x);
                return s == 0 ? Value.err (ErrorKind.DIV0) : Value.num (1 / s);
            });
            unary ("COT", _("Cotangent of an angle"), (x) => {
                if (Math.fabs (x) >= 134217728) return Value.err (ErrorKind.NUM);
                double t = Math.tan (x);
                return t == 0 ? Value.err (ErrorKind.DIV0) : Value.num (1 / t);
            });
            unary ("SECH", _("Hyperbolic secant"), (x) => {
                if (Math.fabs (x) >= 134217728) return Value.err (ErrorKind.NUM);
                return Value.num (1 / Math.cosh (x));
            });
            unary ("CSCH", _("Hyperbolic cosecant"), (x) => {
                if (Math.fabs (x) >= 134217728) return Value.err (ErrorKind.NUM);
                double s = Math.sinh (x);
                return s == 0 ? Value.err (ErrorKind.DIV0) : Value.num (1 / s);
            });
            unary ("COTH", _("Hyperbolic cotangent"), (x) => {
                if (Math.fabs (x) >= 134217728) return Value.err (ErrorKind.NUM);
                double t = Math.tanh (x);
                return t == 0 ? Value.err (ErrorKind.DIV0) : Value.num (1 / t);
            });
            unary ("ACOT", _("Arccotangent"), (x) => Value.num (Math.PI / 2 - Math.atan (x)));
            unary ("ACOTH", _("Inverse hyperbolic cotangent"), (x) => {
                if (Math.fabs (x) <= 1) return Value.err (ErrorKind.NUM);
                return Value.num (0.5 * Math.log ((x + 1) / (x - 1)));
            });
            unary ("SQRTPI", _("Square root of a number times pi"), (x) => {
                if (x < 0) return Value.err (ErrorKind.NUM);
                return Value.num (Math.sqrt (x * Math.PI));
            });
            unary ("FACTDOUBLE", _("Double factorial"), (x) => {
                double n = Math.trunc (x);
                if (n < -1) return Value.err (ErrorKind.NUM);
                double r = 1;
                for (double k = n; k > 1; k -= 2) r *= k;
                return Value.num (r);
            });
            unary ("ROUNDBAHTDOWN", _("Rounds down to the nearest quarter Baht"), (x) => Value.num (Math.floor (x * 4 + 1e-9) / 4));
            unary ("ROUNDBAHTUP", _("Rounds up to the nearest quarter Baht"), (x) => Value.num (Math.ceil (x * 4 - 1e-9) / 4));
            add ("QUOTIENT", 2, 2, "QUOTIENT(numerator, denominator)", _("Integer part of a division"), (ev, a) => lift (ev, a, (v) => {
                double x, y;
                var e = num (v[0], out x);
                if (e != null) return e;
                if ((e = num (v[1], out y)) != null) return e;
                if (y == 0) return Value.err (ErrorKind.DIV0);
                return Value.num (Math.trunc (x / y));
            }));
            add ("CEILING.MATH", 1, 3, "CEILING.MATH(number, [significance], [mode])", _("Rounds up to a multiple, with a mode for negatives"), (ev, a) => lift (ev, a, (v) => {
                double n, s, m;
                var e = num (v[0], out n);
                if (e != null) return e;
                if ((e = num_or (v.length > 1 ? v[1] : Value.missing (), 1, out s)) != null) return e;
                if ((e = num_or (v.length > 2 ? v[2] : Value.missing (), 0, out m)) != null) return e;
                s = Math.fabs (s);
                if (s == 0 || n == 0) return Value.num (0);
                if (n < 0 && m != 0) return Value.num (-Math.ceil (-n / s - 1e-12) * s);
                return Value.num (Math.ceil (n / s - 1e-12) * s);
            }));
            add ("CEILING.PRECISE", 1, 2, "CEILING.PRECISE(number, [significance])", _("Rounds up to a multiple regardless of sign"), (ev, a) => lift (ev, a, (v) => {
                double n, s;
                var e = num (v[0], out n);
                if (e != null) return e;
                if ((e = num_or (v.length > 1 ? v[1] : Value.missing (), 1, out s)) != null) return e;
                s = Math.fabs (s);
                if (s == 0) return Value.num (0);
                return Value.num (Math.ceil (n / s - 1e-12) * s);
            }));
            Functions.alias ("ISO.CEILING", "CEILING.PRECISE");
            add ("FLOOR.MATH", 1, 3, "FLOOR.MATH(number, [significance], [mode])", _("Rounds down to a multiple, with a mode for negatives"), (ev, a) => lift (ev, a, (v) => {
                double n, s, m;
                var e = num (v[0], out n);
                if (e != null) return e;
                if ((e = num_or (v.length > 1 ? v[1] : Value.missing (), 1, out s)) != null) return e;
                if ((e = num_or (v.length > 2 ? v[2] : Value.missing (), 0, out m)) != null) return e;
                s = Math.fabs (s);
                if (s == 0 || n == 0) return Value.num (0);
                if (n < 0 && m != 0) return Value.num (-Math.floor (-n / s + 1e-12) * s);
                return Value.num (Math.floor (n / s + 1e-12) * s);
            }));
            add ("FLOOR.PRECISE", 1, 2, "FLOOR.PRECISE(number, [significance])", _("Rounds down to a multiple regardless of sign"), (ev, a) => lift (ev, a, (v) => {
                double n, s;
                var e = num (v[0], out n);
                if (e != null) return e;
                if ((e = num_or (v.length > 1 ? v[1] : Value.missing (), 1, out s)) != null) return e;
                s = Math.fabs (s);
                if (s == 0) return Value.num (0);
                return Value.num (Math.floor (n / s + 1e-12) * s);
            }));
            add ("ROMAN", 1, 2, "ROMAN(number, [form])", _("Converts a number to Roman numerals"), (ev, a) => lift (ev, a, (v) => {
                double n;
                var e = num (v[0], out n);
                if (e != null) return e;
                int mode = 0;
                if (v.length > 1 && given (v[1]) && v[1].kind != ValueKind.EMPTY) {
                    if (v[1].kind == ValueKind.BOOL) mode = v[1].number != 0 ? 0 : 4;
                    else {
                        double m;
                        if ((e = num (v[1], out m)) != null) return e;
                        mode = (int) Math.trunc (m);
                    }
                }
                if (mode < 0 || mode > 4) return Value.err (ErrorKind.VALUE);
                int iv = (int) Math.trunc (n);
                if (iv < 0 || iv > 3999) return Value.err (ErrorKind.VALUE);
                return Value.str (roman (iv, mode));
            }));
            add ("ARABIC", 1, 1, "ARABIC(text)", _("Converts a Roman numeral to a number"), (ev, a) => lift (ev, a, (v) => {
                if (v[0].is_error ()) return v[0];
                string t = Evaluator.to_text (v[0]).strip ();
                if (t.length > 255) return Value.err (ErrorKind.VALUE);
                bool neg = false;
                if (t.has_prefix ("-")) {
                    neg = true;
                    t = t.substring (1);
                }
                int total = 0;
                for (int i = 0; i < t.length; i++) {
                    int d = roman_digit (t[i]);
                    if (d == 0) return Value.err (ErrorKind.VALUE);
                    int nx = i + 1 < t.length ? roman_digit (t[i + 1]) : 0;
                    if (i + 1 < t.length && nx == 0) return Value.err (ErrorKind.VALUE);
                    total += d < nx ? -d : d;
                }
                return Value.num (neg ? -total : total);
            }));
            add ("BASE", 2, 3, "BASE(number, radix, [min_length])", _("Converts a number to text in another base"), (ev, a) => lift (ev, a, (v) => {
                double n, r, ml;
                var e = num (v[0], out n);
                if (e != null) return e;
                if ((e = num (v[1], out r)) != null) return e;
                if ((e = num_or (v.length > 2 ? v[2] : Value.missing (), 0, out ml)) != null) return e;
                n = Math.trunc (n);
                int radix = (int) Math.trunc (r);
                int minlen = (int) Math.trunc (ml);
                if (n < 0 || n >= 9007199254740992.0 || radix < 2 || radix > 36 || minlen < 0 || minlen > 255) return Value.err (ErrorKind.NUM);
                string digits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
                var sb = new StringBuilder ();
                uint64 x = (uint64) n;
                do {
                    sb.prepend_c (digits[(int) (x % radix)]);
                    x /= radix;
                } while (x > 0);
                while (sb.len < minlen) sb.prepend_c ('0');
                return Value.str (sb.str);
            }));
            add ("DECIMAL", 2, 2, "DECIMAL(text, radix)", _("Converts text in a base to a number"), (ev, a) => lift (ev, a, (v) => {
                if (v[0].is_error ()) return v[0];
                double r;
                var e = num (v[1], out r);
                if (e != null) return e;
                int radix = (int) Math.trunc (r);
                if (radix < 2 || radix > 36) return Value.err (ErrorKind.NUM);
                string t = Evaluator.to_text (v[0]).strip ();
                if (t.length > 255) return Value.err (ErrorKind.VALUE);
                double total = 0;
                for (int i = 0; i < t.length; i++) {
                    char c = t[i].toupper ();
                    int d = c.isdigit () ? c - '0' : (c >= 'A' && c <= 'Z' ? c - 'A' + 10 : 99);
                    if (d >= radix) return Value.err (ErrorKind.NUM);
                    total = total * radix + d;
                }
                if (total >= 9007199254740992.0) return Value.err (ErrorKind.NUM);
                return Value.num (total);
            }));
            pair_sum ("SUMX2MY2", _("Sum of the differences of squares"), (x, y) => x * x - y * y);
            pair_sum ("SUMX2PY2", _("Sum of the sums of squares"), (x, y) => x * x + y * y);
            pair_sum ("SUMXMY2", _("Sum of squares of differences"), (x, y) => (x - y) * (x - y));
            add ("SERIESSUM", 4, 4, "SERIESSUM(x, n, m, coefficients)", _("Sum of a power series"), (ev, a) => {
                double x, n, m;
                var e = ev.arg_number (a[0], out x);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out n)) != null) return e;
                if ((e = ev.arg_number (a[2], out m)) != null) return e;
                var coef = ev.to_matrix (ev.eval (a[3]));
                double s = 0;
                int i = 0;
                for (int r = 0; r < coef.length[0]; r++) {
                    for (int c = 0; c < coef.length[1]; c++) {
                        var cv = coef[r, c];
                        if (cv.is_error ()) return cv;
                        if (cv.kind != ValueKind.NUMBER) return Value.err (ErrorKind.VALUE);
                        s += cv.number * Math.pow (x, n + i * m);
                        i++;
                    }
                }
                return Value.num (s);
            });
            add ("MULTINOMIAL", 1, -1, "MULTINOMIAL(number1, [number2], ...)", _("Multinomial coefficient of the numbers"), (ev, a) => {
                var list = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, list);
                if (e != null) return e;
                double sum = 0, logden = 0;
                foreach (var d in list) {
                    double k = Math.trunc (d);
                    if (k < 0) return Value.err (ErrorKind.NUM);
                    sum += k;
                    logden += Functions.lgamma (k + 1);
                }
                return Value.num (Math.round (Math.exp (Functions.lgamma (sum + 1) - logden)));
            });
            add ("COMBINA", 2, 2, "COMBINA(number, number_chosen)", _("Combinations with repetitions"), (ev, a) => lift (ev, a, (v) => {
                double n, k;
                var e = num (v[0], out n);
                if (e != null) return e;
                if ((e = num (v[1], out k)) != null) return e;
                n = Math.trunc (n);
                k = Math.trunc (k);
                if (n < 0 || k < 0 || (n == 0 && k > 0)) return Value.err (ErrorKind.NUM);
                if (k == 0) return Value.num (1);
                return Value.num (combin (n + k - 1, k));
            }));
            add ("PERMUTATIONA", 2, 2, "PERMUTATIONA(number, number_chosen)", _("Permutations with repetitions"), (ev, a) => lift (ev, a, (v) => {
                double n, k;
                var e = num (v[0], out n);
                if (e != null) return e;
                if ((e = num (v[1], out k)) != null) return e;
                n = Math.trunc (n);
                k = Math.trunc (k);
                if (n < 0 || k < 0) return Value.err (ErrorKind.NUM);
                return Value.num (Math.pow (n, k));
            }));
        }
    }
}
