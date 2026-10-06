namespace Singularity.Apps.Spreadsheet {

    public delegate Value FnImpl (Evaluator ev, Node[] a);

    public class FnDef {
        public string name;
        public int min;
        public int max;
        public string category;
        public string syntax;
        public string summary;
        public FnImpl impl;

        public FnDef (string name, int min, int max, string category, string syntax, string summary, owned FnImpl impl) {
            this.name = name;
            this.min = min;
            this.max = max;
            this.category = category;
            this.syntax = syntax;
            this.summary = summary;
            this.impl = (owned) impl;
        }
    }

    public class Criteria {
        private string op = "=";
        private Value target;
        private bool wildcard;
        private Regex? regex;

        public Criteria (Value crit) {
            if (crit.kind != ValueKind.TEXT) {
                target = crit.kind == ValueKind.EMPTY ? Value.str ("") : crit;
                return;
            }
            string t = crit.text;
            string[] ops = { ">=", "<=", "<>", ">", "<", "=" };
            foreach (string o in ops) {
                if (t.has_prefix (o)) {
                    op = o;
                    t = t.substring (o.length);
                    break;
                }
            }
            var parsed = Input.parse (t);
            target = t == "" ? Value.str ("") : parsed.value;
            if (target.kind == ValueKind.TEXT && (op == "=" || op == "<>") && (t.contains ("*") || t.contains ("?"))) {
                wildcard = true;
                try {
                    regex = new Regex (wildcard_pattern (t, true), RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL);
                } catch (RegexError e) {
                    wildcard = false;
                }
            }
        }

        public static string wildcard_pattern (string t, bool anchored) {
            var sb = new StringBuilder (anchored ? "^" : "");
            for (int i = 0; i < t.length; i++) {
                char c = t[i];
                if (c == '~' && i + 1 < t.length && (t[i + 1] == '*' || t[i + 1] == '?' || t[i + 1] == '~')) {
                    sb.append (Regex.escape_string (t[i + 1].to_string ()));
                    i++;
                } else if (c == '*') {
                    sb.append (anchored ? ".*" : ".*?");
                } else if (c == '?') {
                    sb.append (".");
                } else {
                    int j = i;
                    while (j < t.length && t[j] != '*' && t[j] != '?' && t[j] != '~') j++;
                    sb.append (Regex.escape_string (t.substring (i, j - i)));
                    i = j - 1;
                }
            }
            if (anchored) sb.append ("$");
            return sb.str;
        }

        public bool matches (Value v) {
            if (wildcard) {
                bool m = v.kind == ValueKind.TEXT && regex.match (v.text);
                return op == "=" ? m : !m;
            }
            if (target.kind == ValueKind.TEXT && target.text == "") {
                bool blank = v.kind == ValueKind.EMPTY || (v.kind == ValueKind.TEXT && v.text == "");
                if (op == "=") return blank;
                if (op == "<>") return !blank;
            }
            if (op == "=" || op == "<>") {
                bool eq;
                if (target.kind == ValueKind.NUMBER && v.kind == ValueKind.TEXT) {
                    double d;
                    string f;
                    eq = Input.parse_number (v.text, out d, out f) && d == target.number;
                } else if (v.kind == ValueKind.EMPTY) {
                    eq = false;
                } else if (v.kind == ValueKind.ERROR && target.kind == ValueKind.ERROR) {
                    eq = v.error == target.error;
                } else {
                    eq = v.kind == target.kind && Evaluator.compare (v, target) == 0;
                }
                return op == "=" ? eq : !eq;
            }
            if (v.kind == ValueKind.EMPTY) return false;
            if ((target.kind == ValueKind.NUMBER) != (v.kind == ValueKind.NUMBER)) return false;
            int c = Evaluator.compare (v, target);
            switch (op) {
                case ">": return c > 0;
                case "<": return c < 0;
                case ">=": return c >= 0;
                case "<=": return c <= 0;
            }
            return false;
        }
    }

    public class Functions {
        private static Gee.HashMap<string, FnDef>? table;

        public static Gee.HashMap<string, FnDef> all () {
            if (table == null) {
                table = new Gee.HashMap<string, FnDef> ();
                register_math ();
                register_logic ();
                register_info ();
                TextFunctions.register ();
                StatFunctions.register ();
                LookupFunctions.register ();
                DateFunctions.register ();
                FinanceFunctions.register ();
                LambdaFunctions.register ();
                ImageFunctions.register ();
                EngineeringFunctions.register ();
                DatabaseFunctions.register ();
                FinancialFunctions.register ();
                MoreMathFunctions.register ();
                WebFunctions.register ();
                DistributionFunctions.register ();
                MoreTextFunctions.register ();
                ArrayFunctions.register ();
                MatrixFunctions.register ();
                AnalysisFunctions.register ();
            }
            return table;
        }

        public static void add (string name, int min, int max, string category, string syntax, string summary, owned FnImpl impl) {
            table[name] = new FnDef (name, min, max, category, syntax, summary, (owned) impl);
        }

        public static void alias (string name, string target) {
            var d = table[target];
            table[name] = d;
        }

        public static Value call (Evaluator ev, Node n) {
            var def = all ()[n.text];
            if (def == null) {
                var callee = ev.resolve_callable (n.text);
                if (callee == null && ev.book.udf != null) {
                    Value[] uvals = {};
                    foreach (var arg in n.args) uvals += arg.kind == NodeKind.MISSING ? Value.missing () : ev.eval (arg);
                    var ur = ev.book.udf.call_udf (n.text, uvals);
                    if (ur != null) return ur;
                }
                if (callee == null || callee.is_error ()) return Value.err (ErrorKind.NAME);
                if (callee.kind != ValueKind.LAMBDA) return Value.err (ErrorKind.VALUE);
                Value[] vals = {};
                foreach (var arg in n.args) vals += arg.kind == NodeKind.MISSING ? Value.missing () : ev.eval (arg);
                return ev.call_lambda (callee.fn, vals);
            }
            if (n.args.length < def.min || (def.max >= 0 && n.args.length > def.max)) return Value.err (ErrorKind.VALUE);
            if (ev.legacy && takes_arrays (n.text)) {
                ev.array_ctx++;
                var r = def.impl (ev, n.args);
                ev.array_ctx--;
                return r;
            }
            return def.impl (ev, n.args);
        }

        public static bool takes_arrays (string name) {
            switch (name) {
                case "SUMPRODUCT": case "MMULT": case "MDETERM": case "MINVERSE": case "TRANSPOSE": case "INDEX": case "LOOKUP":
                case "MATCH": case "FREQUENCY": case "LINEST": case "LOGEST": case "TREND": case "GROWTH": case "SUMX2MY2":
                case "SUMX2PY2": case "SUMXMY2": case "AGGREGATE": case "CORREL": case "COVAR": case "PEARSON": case "RSQ":
                case "SLOPE": case "INTERCEPT": case "STEYX": case "FORECAST": case "TTEST": case "T.TEST": case "CHITEST":
                case "CHISQ.TEST": case "FTEST": case "F.TEST": case "PROB": case "IRR": case "NPV": case "MIRR": case "XNPV": case "XIRR":
                case "PERCENTILE": case "QUARTILE": case "LARGE": case "SMALL": case "RANK": case "MODE": case "MEDIAN":
                    return true;
                default:
                    return false;
            }
        }

        public static bool is_volatile_name (string name) {
            switch (name) {
                case "NOW": case "TODAY": case "RAND": case "RANDBETWEEN": case "RANDARRAY": case "INDIRECT": case "OFFSET": case "CELL": case "INFO":
                    return true;
                default:
                    return false;
            }
        }

        public static bool is_volatile (Node n) {
            return n.has_call ("NOW") || n.has_call ("TODAY") || n.has_call ("RAND") || n.has_call ("RANDBETWEEN") || n.has_call ("INDIRECT") || n.has_call ("OFFSET");
        }

        public delegate double Unary (double x);

        public static void math1 (string name, string summary, owned Unary f, bool positive = false, bool nonneg = false) {
            Unary fn = (owned) f;
            add (name, 1, 1, "Math", name + "(number)", summary, (ev, a) => {
                return ev.map1 (ev.eval (a[0]), (v) => {
                    double d;
                    var e = Evaluator.to_number (v, out d);
                    if (e != null) return e;
                    if (positive && d <= 0) return Value.err (ErrorKind.NUM);
                    if (nonneg && d < 0) return Value.err (ErrorKind.NUM);
                    return Value.num (fn (d));
                });
            });
        }

        public delegate double Binary (double x, double y);

        public static void math2 (string name, string syntax, string summary, owned Binary f, double default_y = double.NAN) {
            Binary fn = (owned) f;
            double def = default_y;
            add (name, def.is_nan () ? 2 : 1, 2, "Math", syntax, summary, (ev, a) => {
                var vy = a.length > 1 ? ev.eval (a[1]) : Value.num (def);
                return ev.map2 (ev.eval (a[0]), vy, (x, y) => {
                    double dx, dy;
                    var e = Evaluator.to_number (x, out dx);
                    if (e != null) return e;
                    e = Evaluator.to_number (y, out dy);
                    if (e != null) return e;
                    return Value.num (fn (dx, dy));
                });
            });
        }

        private static void register_math () {
            add ("SUM", 1, -1, "Math", "SUM(number1, [number2], ...)", _("Adds all the numbers"), (ev, a) => {
                var list = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, list);
                if (e != null) return e;
                double s = 0;
                foreach (var d in list) s += d;
                return Value.num (s);
            });
            add ("PRODUCT", 1, -1, "Math", "PRODUCT(number1, [number2], ...)", _("Multiplies all the numbers"), (ev, a) => {
                var list = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, list);
                if (e != null) return e;
                if (list.size == 0) return Value.num (0);
                double s = 1;
                foreach (var d in list) s *= d;
                return Value.num (s);
            });
            add ("SUMSQ", 1, -1, "Math", "SUMSQ(number1, ...)", _("Sum of the squares"), (ev, a) => {
                var list = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, list);
                if (e != null) return e;
                double s = 0;
                foreach (var d in list) s += d * d;
                return Value.num (s);
            });
            math1 ("ABS", _("Absolute value"), (x) => Math.fabs (x));
            math1 ("SQRT", _("Square root"), (x) => Math.sqrt (x), false, true);
            math1 ("EXP", _("e raised to a power"), (x) => Math.exp (x));
            math1 ("LN", _("Natural logarithm"), (x) => Math.log (x), true);
            math1 ("LOG10", _("Base-10 logarithm"), (x) => Math.log10 (x), true);
            math1 ("SIN", _("Sine"), (x) => Math.sin (x));
            math1 ("COS", _("Cosine"), (x) => Math.cos (x));
            math1 ("TAN", _("Tangent"), (x) => Math.tan (x));
            math1 ("ASIN", _("Arcsine"), (x) => Math.asin (x));
            math1 ("ACOS", _("Arccosine"), (x) => Math.acos (x));
            math1 ("ATAN", _("Arctangent"), (x) => Math.atan (x));
            math1 ("SINH", _("Hyperbolic sine"), (x) => Math.sinh (x));
            math1 ("COSH", _("Hyperbolic cosine"), (x) => Math.cosh (x));
            math1 ("TANH", _("Hyperbolic tangent"), (x) => Math.tanh (x));
            math1 ("ASINH", _("Inverse hyperbolic sine"), (x) => Math.asinh (x));
            math1 ("ACOSH", _("Inverse hyperbolic cosine"), (x) => Math.acosh (x));
            math1 ("ATANH", _("Inverse hyperbolic tangent"), (x) => Math.atanh (x));
            math1 ("DEGREES", _("Radians to degrees"), (x) => x * 180 / Math.PI);
            math1 ("RADIANS", _("Degrees to radians"), (x) => x * Math.PI / 180);
            math1 ("INT", _("Rounds down to an integer"), (x) => Math.floor (x));
            math1 ("SIGN", _("Sign of a number"), (x) => x > 0 ? 1 : (x < 0 ? -1 : 0));
            math1 ("EVEN", _("Rounds up to an even integer"), (x) => {
                double r = Math.ceil (Math.fabs (x) / 2) * 2;
                return x < 0 ? -r : r;
            });
            math1 ("ODD", _("Rounds up to an odd integer"), (x) => {
                double r = Math.ceil ((Math.fabs (x) - 1) / 2) * 2 + 1;
                if (r < 1) r = 1;
                return x < 0 ? -r : r;
            });
            math1 ("FACT", _("Factorial"), (x) => {
                double r = 1;
                for (int i = 2; i <= (int) Math.floor (x); i++) r *= i;
                return r;
            }, false, true);
            add ("ATAN2", 2, 2, "Math", "ATAN2(x, y)", _("Arctangent of x and y"), (ev, a) => {
                return ev.map2 (ev.eval (a[0]), ev.eval (a[1]), (x, y) => {
                    double dx, dy;
                    var e = Evaluator.to_number (x, out dx);
                    if (e != null) return e;
                    e = Evaluator.to_number (y, out dy);
                    if (e != null) return e;
                    if (dx == 0 && dy == 0) return Value.err (ErrorKind.DIV0);
                    return Value.num (Math.atan2 (dy, dx));
                });
            });
            math2 ("POWER", "POWER(number, power)", _("A number raised to a power"), (x, y) => Math.pow (x, y));
            math2 ("LOG", "LOG(number, [base])", _("Logarithm in a base"), (x, y) => Math.log (x) / Math.log (y), 10);
            math2 ("ROUND", "ROUND(number, digits)", _("Rounds to a number of digits"), (x, y) => round_digits (x, (int) y, 0));
            math2 ("ROUNDUP", "ROUNDUP(number, digits)", _("Rounds away from zero"), (x, y) => round_digits (x, (int) y, 1));
            math2 ("ROUNDDOWN", "ROUNDDOWN(number, digits)", _("Rounds toward zero"), (x, y) => round_digits (x, (int) y, -1));
            math2 ("TRUNC", "TRUNC(number, [digits])", _("Cuts off the decimals"), (x, y) => round_digits (x, (int) y, -1), 0);
            math2 ("QUOTIENT", "QUOTIENT(numerator, denominator)", _("Integer part of a division"), (x, y) => Math.trunc (x / y));
            add ("MOD", 2, 2, "Math", "MOD(number, divisor)", _("Remainder of a division"), (ev, a) => {
                return ev.map2 (ev.eval (a[0]), ev.eval (a[1]), (x, y) => {
                    double n, d;
                    var e = Evaluator.to_number (x, out n);
                    if (e != null) return e;
                    e = Evaluator.to_number (y, out d);
                    if (e != null) return e;
                    if (d == 0) return Value.err (ErrorKind.DIV0);
                    return Value.num (n - d * Math.floor (n / d));
                });
            });
            add ("MROUND", 2, 2, "Math", "MROUND(number, multiple)", _("Rounds to a multiple"), (ev, a) => {
                double n, m;
                var e = ev.arg_number (a[0], out n);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out m)) != null) return e;
                if (m == 0) return Value.num (0);
                if ((n > 0 && m < 0) || (n < 0 && m > 0)) return Value.err (ErrorKind.NUM);
                return Value.num (round_digits (n / m, 0, 0) * m);
            });
            add ("CEILING", 1, 2, "Math", "CEILING(number, [significance])", _("Rounds up to a multiple"), (ev, a) => {
                double n, s = 1;
                var e = ev.arg_number (a[0], out n);
                if (e != null) return e;
                if (a.length > 1 && (e = ev.arg_number (a[1], out s)) != null) return e;
                if (s == 0) return Value.num (0);
                if (n > 0 && s < 0) return Value.err (ErrorKind.NUM);
                return Value.num (Math.ceil (n / s - 1e-12) * s);
            });
            alias ("CEILING.MATH", "CEILING");
            alias ("CEILING.PRECISE", "CEILING");
            add ("FLOOR", 1, 2, "Math", "FLOOR(number, [significance])", _("Rounds down to a multiple"), (ev, a) => {
                double n, s = 1;
                var e = ev.arg_number (a[0], out n);
                if (e != null) return e;
                if (a.length > 1 && (e = ev.arg_number (a[1], out s)) != null) return e;
                if (n == 0) return Value.num (0);
                if (s == 0) return Value.err (ErrorKind.DIV0);
                if (n > 0 && s < 0) return Value.err (ErrorKind.NUM);
                return Value.num (Math.floor (n / s + 1e-12) * s);
            });
            alias ("FLOOR.MATH", "FLOOR");
            alias ("FLOOR.PRECISE", "FLOOR");
            add ("PI", 0, 0, "Math", "PI()", _("The number pi"), (ev, a) => Value.num (Math.PI));
            add ("RAND", 0, 0, "Math", "RAND()", _("A random number between 0 and 1"), (ev, a) => Value.num (Random.next_double ()));
            add ("RANDBETWEEN", 2, 2, "Math", "RANDBETWEEN(bottom, top)", _("A random integer in a range"), (ev, a) => {
                double lo, hi;
                var e = ev.arg_number (a[0], out lo);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out hi)) != null) return e;
                lo = Math.ceil (lo);
                hi = Math.floor (hi);
                if (hi < lo) return Value.err (ErrorKind.NUM);
                return Value.num (lo + Math.floor (Random.next_double () * (hi - lo + 1)));
            });
            add ("GCD", 1, -1, "Math", "GCD(number1, ...)", _("Greatest common divisor"), (ev, a) => {
                var list = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, list);
                if (e != null) return e;
                int64 g = 0;
                foreach (var d in list) {
                    if (d < 0) return Value.err (ErrorKind.NUM);
                    g = gcd (g, (int64) d);
                }
                return Value.num (g);
            });
            add ("LCM", 1, -1, "Math", "LCM(number1, ...)", _("Least common multiple"), (ev, a) => {
                var list = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, list);
                if (e != null) return e;
                int64 l = 1;
                foreach (var d in list) {
                    if (d < 0) return Value.err (ErrorKind.NUM);
                    int64 x = (int64) d;
                    if (x == 0) return Value.num (0);
                    l = l / gcd (l, x) * x;
                }
                return Value.num (l);
            });
            add ("COMBIN", 2, 2, "Math", "COMBIN(n, k)", _("Number of combinations"), (ev, a) => {
                double n, k;
                var e = ev.arg_number (a[0], out n);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out k)) != null) return e;
                n = Math.trunc (n);
                k = Math.trunc (k);
                if (n < 0 || k < 0 || k > n) return Value.err (ErrorKind.NUM);
                return Value.num (Math.round (Math.exp (lgamma (n + 1) - lgamma (k + 1) - lgamma (n - k + 1))));
            });
            add ("PERMUT", 2, 2, "Math", "PERMUT(n, k)", _("Number of permutations"), (ev, a) => {
                double n, k;
                var e = ev.arg_number (a[0], out n);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out k)) != null) return e;
                n = Math.trunc (n);
                k = Math.trunc (k);
                if (n < 0 || k < 0 || k > n) return Value.err (ErrorKind.NUM);
                return Value.num (Math.round (Math.exp (lgamma (n + 1) - lgamma (n - k + 1))));
            });
            add ("SUMIF", 2, 3, "Math", "SUMIF(range, criteria, [sum_range])", _("Adds the cells that meet a condition"), (ev, a) => {
                return conditional (ev, a[0], a[1], a.length > 2 ? a[2] : a[0], 0);
            });
            add ("SUMIFS", 3, -1, "Math", "SUMIFS(sum_range, range1, criteria1, ...)", _("Adds the cells that meet several conditions"), (ev, a) => {
                return conditional_multi (ev, a, 0);
            });
            add ("SUMPRODUCT", 1, -1, "Math", "SUMPRODUCT(array1, [array2], ...)", _("Sum of the products of matching items"), (ev, a) => {
                Value[,]? first = null;
                var mats = new Gee.ArrayList<Value> ();
                foreach (var n in a) {
                    var v = ev.eval (n);
                    if (v.is_error ()) return v;
                    mats.add (v);
                }
                first = ev.to_matrix (mats[0]);
                int rows = first.length[0], cols = first.length[1];
                var ms = new Gee.ArrayList<Value> ();
                foreach (var v in mats) {
                    var m = ev.to_matrix (v);
                    if (m.length[0] != rows || m.length[1] != cols) return Value.err (ErrorKind.VALUE);
                    ms.add (Value.matrix (m));
                }
                double total = 0;
                for (int i = 0; i < rows; i++) {
                    for (int j = 0; j < cols; j++) {
                        double p = 1;
                        foreach (var mv in ms) {
                            var x = mv.array[i, j];
                            if (x.is_error ()) return x;
                            p *= x.kind == ValueKind.NUMBER ? x.number : 0;
                        }
                        total += p;
                    }
                }
                return Value.num (total);
            });
            add ("SUBTOTAL", 2, -1, "Math", "SUBTOTAL(function, range1, ...)", _("A subtotal that ignores other subtotals"), (ev, a) => {
                int f;
                var e = ev.arg_int (a[0], out f);
                if (e != null) return e;
                string[] names = { "", "AVERAGE", "COUNT", "COUNTA", "MAX", "MIN", "PRODUCT", "STDEV", "STDEVP", "SUM", "VAR", "VARP" };
                int k = f > 100 ? f - 100 : f;
                if (k < 1 || k > 11) return Value.err (ErrorKind.VALUE);
                var call = new Node (NodeKind.CALL);
                call.text = names[k];
                call.args = a[1:a.length];
                return call_filtered (ev, call, f > 100);
            });
            add ("AGGREGATE", 3, -1, "Math", "AGGREGATE(function, options, range)", _("An aggregate that can skip errors"), (ev, a) => {
                int f;
                var e = ev.arg_int (a[0], out f);
                if (e != null) return e;
                string[] names = { "", "AVERAGE", "COUNT", "COUNTA", "MAX", "MIN", "PRODUCT", "STDEV", "STDEVP", "SUM", "VAR", "VARP", "MEDIAN", "MODE", "LARGE", "SMALL" };
                if (f < 1 || f >= names.length) return Value.err (ErrorKind.VALUE);
                var list = new Gee.ArrayList<double?> ();
                ev.visit_values (a[2], (v, r) => {
                    if (v.kind == ValueKind.NUMBER) list.add (v.number);
                    return true;
                });
                var arr = new Value[list.size, 1];
                for (int i = 0; i < list.size; i++) arr[i, 0] = Value.num (list[i]);
                var node = new Node (NodeKind.ARRAY);
                node.array = arr;
                var call = new Node (NodeKind.CALL);
                call.text = names[f];
                call.args = a.length > 3 ? new Node[] { node, a[3] } : new Node[] { node };
                return Functions.call (ev, call);
            });
        }

        private static Value call_filtered (Evaluator ev, Node call, bool skip_hidden) {
            Node[] filtered = {};
            foreach (var n in call.args) {
                var v = ev.eval (n);
                if (v.kind != ValueKind.RANGE) {
                    filtered += n;
                    continue;
                }
                var s = v.area.sheet ?? ev.sheet;
                var vals = new Gee.ArrayList<Value> ();
                s.foreach_in (v.area, (r, c, cl) => {
                    if (skip_hidden && s.hidden_rows.contains (r)) return;
                    if (cl.formula != null && (cl.formula.has_call ("SUBTOTAL") || cl.formula.has_call ("AGGREGATE"))) return;
                    if (cl.formula == null && cl.input == "") return;
                    vals.add (ev.book.cell_value (s, cl));
                });
                var arr = new Value[int.max (vals.size, 1), 1];
                if (vals.size == 0) arr[0, 0] = Value.empty ();
                for (int i = 0; i < vals.size; i++) arr[i, 0] = vals[i];
                var node = new Node (NodeKind.ARRAY);
                node.array = arr;
                filtered += node;
            }
            var c = new Node (NodeKind.CALL);
            c.text = call.text;
            c.args = filtered;
            return Functions.call (ev, c);
        }

        public static double lgamma (double x) {
            if (x < 0.5) return Math.log (Math.PI / Math.fabs (Math.sin (Math.PI * x))) - lgamma (1 - x);
            double[] g = { 0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
                           -176.61503916999185, 12.507343278686905, -0.13857109526572012,
                           9.9843695780195716e-6, 1.5056327351493116e-7 };
            x -= 1;
            double s = g[0];
            for (int i = 1; i < 9; i++) s += g[i] / (x + i);
            double t = x + 7.5;
            return 0.5 * Math.log (2 * Math.PI) + (x + 0.5) * Math.log (t) - t + Math.log (s);
        }

        private static int64 gcd (int64 a, int64 b) {
            while (b != 0) {
                int64 t = a % b;
                a = b;
                b = t;
            }
            return a.abs ();
        }

        public static double round_digits (double x, int digits, int mode) {
            double m = Math.pow (10, digits);
            double v = double.parse (Value.ascii (Math.fabs (x) * m, "%.15g"));
            double r = mode == 0 ? Math.floor (v + 0.5) : (mode > 0 ? Math.ceil (v) : Math.floor (v));
            r /= m;
            return x < 0 ? -r : r;
        }

        public static Value conditional (Evaluator ev, Node range_node, Node crit_node, Node target_node, int mode) {
            var rv = ev.eval (range_node);
            var crit = new Criteria (ev.arg (crit_node));
            var tv = ev.eval (target_node);
            var rm = ev.to_matrix (rv);
            Value[,]? tm = null;
            if (tv.kind == ValueKind.RANGE && rv.kind == ValueKind.RANGE) {
                var ta = tv.area;
                var area = new Area (ta.sheet, ta.r1, ta.c1, ta.r1 + rm.length[0] - 1, ta.c1 + rm.length[1] - 1);
                tm = ev.to_matrix (Value.range (area));
            } else {
                tm = ev.to_matrix (tv);
            }
            double sum = 0;
            int count = 0;
            for (int i = 0; i < rm.length[0]; i++) {
                for (int j = 0; j < rm.length[1]; j++) {
                    if (!crit.matches (rm[i, j])) continue;
                    count++;
                    if (mode == 1) continue;
                    if (i >= tm.length[0] || j >= tm.length[1]) continue;
                    var t = tm[i, j];
                    if (t.is_error ()) return t;
                    if (t.kind == ValueKind.NUMBER) sum += t.number;
                    else if (mode == 2) count--;
                }
            }
            if (mode == 1) return Value.num (count);
            if (mode == 2) return count == 0 ? Value.err (ErrorKind.DIV0) : Value.num (sum / count);
            return Value.num (sum);
        }

        public static Value conditional_multi (Evaluator ev, Node[] a, int mode) {
            int offset = mode == 1 ? 0 : 1;
            if ((a.length - offset) % 2 != 0) return Value.err (ErrorKind.VALUE);
            Value[,]? target = mode == 1 ? null : ev.to_matrix (ev.eval (a[0]));
            var ranges = new Gee.ArrayList<Value> ();
            var crits = new Gee.ArrayList<Criteria> ();
            int rows = -1, cols = -1;
            for (int i = offset; i < a.length; i += 2) {
                var m = ev.to_matrix (ev.eval (a[i]));
                if (rows < 0) {
                    rows = m.length[0];
                    cols = m.length[1];
                } else if (m.length[0] != rows || m.length[1] != cols) {
                    return Value.err (ErrorKind.VALUE);
                }
                ranges.add (Value.matrix (m));
                crits.add (new Criteria (ev.arg (a[i + 1])));
            }
            if (target != null && (target.length[0] != rows || target.length[1] != cols)) return Value.err (ErrorKind.VALUE);
            double sum = 0;
            int count = 0;
            double best = mode == 3 ? double.INFINITY : -double.INFINITY;
            bool any = false;
            for (int i = 0; i < rows; i++) {
                for (int j = 0; j < cols; j++) {
                    bool ok = true;
                    for (int k = 0; k < ranges.size && ok; k++) ok = crits[k].matches (ranges[k].array[i, j]);
                    if (!ok) continue;
                    if (mode == 1) {
                        count++;
                        continue;
                    }
                    var t = target[i, j];
                    if (t.is_error ()) return t;
                    if (t.kind != ValueKind.NUMBER) continue;
                    count++;
                    sum += t.number;
                    any = true;
                    if (mode == 3) best = double.min (best, t.number);
                    if (mode == 4) best = double.max (best, t.number);
                }
            }
            switch (mode) {
                case 1: return Value.num (count);
                case 2: return count == 0 ? Value.err (ErrorKind.DIV0) : Value.num (sum / count);
                case 3:
                case 4: return Value.num (any ? best : 0);
                default: return Value.num (sum);
            }
        }

        private static void register_logic () {
            add ("IF", 1, 3, "Logical", "IF(test, [if_true], [if_false])", _("One value if a test is true, another if false"), (ev, a) => {
                var t = ev.eval (a[0]);
                if (t.kind == ValueKind.ARRAY || (t.kind == ValueKind.RANGE && !t.area.is_single ())) {
                    var tv = t;
                    var yes = a.length > 1 ? ev.eval (a[1]) : Value.boolean (true);
                    var no = a.length > 2 ? ev.eval (a[2]) : Value.boolean (false);
                    var cond = ev.map1 (tv, (x) => x);
                    var both = ev.map2 (cond, yes, (c, y) => {
                        if (c.is_error ()) return c;
                        return truthy (c) ? y : Value.err (ErrorKind.NULL);
                    });
                    return ev.map2 (both, no, (b, n) => b.kind == ValueKind.ERROR && b.error == ErrorKind.NULL ? n : b);
                }
                var cond = ev.deref (t);
                if (cond.is_error ()) return cond;
                if (cond.kind == ValueKind.TEXT) {
                    string u = cond.text.up ();
                    if (u != "TRUE" && u != "FALSE") return Value.err (ErrorKind.VALUE);
                    cond = Value.boolean (u == "TRUE");
                }
                if (truthy (cond)) return a.length > 1 ? (a[1].kind == NodeKind.MISSING ? Value.num (0) : ev.eval (a[1])) : Value.boolean (true);
                return a.length > 2 ? (a[2].kind == NodeKind.MISSING ? Value.num (0) : ev.eval (a[2])) : Value.boolean (false);
            });
            add ("IFS", 2, -1, "Logical", "IFS(test1, value1, [test2, value2], ...)", _("The value of the first true test"), (ev, a) => {
                if (a.length % 2 != 0) return Value.err (ErrorKind.VALUE);
                for (int i = 0; i < a.length; i += 2) {
                    bool b;
                    var e = ev.arg_bool (a[i], out b);
                    if (e != null) return e;
                    if (b) return ev.eval (a[i + 1]);
                }
                return Value.err (ErrorKind.NA);
            });
            add ("IFERROR", 2, 2, "Logical", "IFERROR(value, value_if_error)", _("A fallback when a value is an error"), (ev, a) => {
                var v = ev.eval (a[0]);
                return ev.map2 (v, ev.eval (a[1]), (x, y) => x.is_error () ? y : x);
            });
            add ("IFNA", 2, 2, "Logical", "IFNA(value, value_if_na)", _("A fallback when a value is #N/A"), (ev, a) => {
                var v = ev.eval (a[0]);
                return ev.map2 (v, ev.eval (a[1]), (x, y) => x.is_error () && x.error == ErrorKind.NA ? y : x);
            });
            add ("AND", 1, -1, "Logical", "AND(logical1, ...)", _("True when all arguments are true"), (ev, a) => logical (ev, a, 0));
            add ("OR", 1, -1, "Logical", "OR(logical1, ...)", _("True when any argument is true"), (ev, a) => logical (ev, a, 1));
            add ("XOR", 1, -1, "Logical", "XOR(logical1, ...)", _("True when an odd number of arguments are true"), (ev, a) => logical (ev, a, 2));
            add ("NOT", 1, 1, "Logical", "NOT(logical)", _("Reverses a logical value"), (ev, a) => {
                return ev.map1 (ev.eval (a[0]), (v) => {
                    double d;
                    var e = Evaluator.to_number (v, out d);
                    if (e != null) return e;
                    return Value.boolean (d == 0);
                });
            });
            add ("TRUE", 0, 0, "Logical", "TRUE()", _("The logical value TRUE"), (ev, a) => Value.boolean (true));
            add ("FALSE", 0, 0, "Logical", "FALSE()", _("The logical value FALSE"), (ev, a) => Value.boolean (false));
            add ("SWITCH", 3, -1, "Logical", "SWITCH(expression, value1, result1, ..., [default])", _("The result matching a value"), (ev, a) => {
                var v = ev.arg (a[0]);
                if (v.is_error ()) return v;
                int i = 1;
                for (; i + 1 < a.length; i += 2) {
                    var c = ev.arg (a[i]);
                    if (Evaluator.compare (v, c) == 0 && v.kind == c.kind) return ev.eval (a[i + 1]);
                }
                if (i < a.length) return ev.eval (a[i]);
                return Value.err (ErrorKind.NA);
            });
        }

        private static string literal (Value v) {
            switch (v.kind) {
                case ValueKind.NUMBER: return Value.format_number_general_full (v.number);
                case ValueKind.TEXT: return "\"" + v.text.replace ("\"", "\"\"") + "\"";
                case ValueKind.BOOL: return v.number != 0 ? "TRUE" : "FALSE";
                case ValueKind.ERROR: return v.error.to_string ();
                default: return "0";
            }
        }

        public static bool truthy (Value v) {
            if (v.kind == ValueKind.TEXT) return v.text.up () == "TRUE";
            return v.number != 0;
        }

        private static Value logical (Evaluator ev, Node[] a, int mode) {
            int trues = 0, total = 0;
            Value? err = null;
            foreach (var n in a) {
                ev.visit_values (n, (v, from_ref) => {
                    if (v.is_error ()) {
                        err = v;
                        return false;
                    }
                    if (v.kind == ValueKind.TEXT) {
                        if (from_ref) return true;
                        string u = v.text.up ();
                        if (u != "TRUE" && u != "FALSE") return true;
                        total++;
                        if (u == "TRUE") trues++;
                        return true;
                    }
                    if (v.kind == ValueKind.EMPTY) return true;
                    total++;
                    if (v.number != 0) trues++;
                    return true;
                });
                if (err != null) return err;
            }
            if (total == 0) return Value.err (ErrorKind.VALUE);
            if (mode == 0) return Value.boolean (trues == total);
            if (mode == 1) return Value.boolean (trues > 0);
            return Value.boolean (trues % 2 == 1);
        }

        private static void register_info () {
            add ("ISBLANK", 1, 1, "Information", "ISBLANK(value)", _("True for an empty cell"), (ev, a) => Value.boolean (ev.arg (a[0]).kind == ValueKind.EMPTY));
            add ("ISNUMBER", 1, 1, "Information", "ISNUMBER(value)", _("True for a number"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => Value.boolean (v.kind == ValueKind.NUMBER)));
            add ("ISTEXT", 1, 1, "Information", "ISTEXT(value)", _("True for text"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => Value.boolean (v.kind == ValueKind.TEXT)));
            add ("ISNONTEXT", 1, 1, "Information", "ISNONTEXT(value)", _("True for anything but text"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => Value.boolean (v.kind != ValueKind.TEXT)));
            add ("ISLOGICAL", 1, 1, "Information", "ISLOGICAL(value)", _("True for a logical value"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => Value.boolean (v.kind == ValueKind.BOOL)));
            add ("ISERROR", 1, 1, "Information", "ISERROR(value)", _("True for any error"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => Value.boolean (v.is_error ())));
            add ("ISERR", 1, 1, "Information", "ISERR(value)", _("True for any error but #N/A"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => Value.boolean (v.is_error () && v.error != ErrorKind.NA)));
            add ("ISNA", 1, 1, "Information", "ISNA(value)", _("True for #N/A"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => Value.boolean (v.is_error () && v.error == ErrorKind.NA)));
            add ("ISREF", 1, 1, "Information", "ISREF(value)", _("True for a reference"), (ev, a) => {
                var k = ev.eval (a[0]).kind;
                return Value.boolean (k == ValueKind.RANGE || k == ValueKind.REFS);
            });
            add ("ISFORMULA", 1, 1, "Information", "ISFORMULA(reference)", _("True when a cell holds a formula"), (ev, a) => {
                var v = ev.eval (a[0]);
                if (v.kind != ValueKind.RANGE) return Value.err (ErrorKind.VALUE);
                var s = v.area.sheet ?? ev.sheet;
                var c = s.get_cell (v.area.r1, v.area.c1);
                return Value.boolean (c != null && c.formula != null);
            });
            add ("ISEVEN", 1, 1, "Information", "ISEVEN(number)", _("True for an even number"), (ev, a) => {
                double d;
                var e = ev.arg_number (a[0], out d);
                return e ?? Value.boolean (((int64) Math.trunc (d)) % 2 == 0);
            });
            add ("ISODD", 1, 1, "Information", "ISODD(number)", _("True for an odd number"), (ev, a) => {
                double d;
                var e = ev.arg_number (a[0], out d);
                return e ?? Value.boolean (((int64) Math.trunc (d)) % 2 != 0);
            });
            add ("NA", 0, 0, "Information", "NA()", _("The #N/A error"), (ev, a) => Value.err (ErrorKind.NA));
            add ("N", 1, 1, "Information", "N(value)", _("A value converted to a number"), (ev, a) => {
                var v = ev.arg (a[0]);
                if (v.is_error ()) return v;
                return Value.num (v.kind == ValueKind.NUMBER || v.kind == ValueKind.BOOL ? v.number : 0);
            });
            add ("TYPE", 1, 1, "Information", "TYPE(value)", _("The type of a value"), (ev, a) => {
                var raw = ev.eval (a[0]);
                if (raw.kind == ValueKind.ARRAY || (raw.kind == ValueKind.RANGE && !raw.area.is_single ())) return Value.num (64);
                var v = ev.deref (raw);
                switch (v.kind) {
                    case ValueKind.TEXT: return Value.num (2);
                    case ValueKind.BOOL: return Value.num (4);
                    case ValueKind.ERROR: return Value.num (16);
                    default: return Value.num (1);
                }
            });
            add ("ERROR.TYPE", 1, 1, "Information", "ERROR.TYPE(error)", _("The number of an error"), (ev, a) => {
                var v = ev.arg (a[0]);
                if (!v.is_error ()) return Value.err (ErrorKind.NA);
                switch (v.error) {
                    case ErrorKind.GETTING_DATA: return Value.num (8);
                    case ErrorKind.SPILL: return Value.num (9);
                    case ErrorKind.CALC: return Value.num (14);
                    case ErrorKind.CIRC: return Value.num (4);
                    default: return Value.num ((int) v.error);
                }
            });
            add ("CELL", 1, 2, "Information", "CELL(info, [reference])", _("Information about a cell"), (ev, a) => {
                Value? e = null;
                string what = ev.arg_text (a[0], out e).down ();
                if (e != null) return e;
                int r = ev.row, c = ev.col;
                Sheet s = ev.sheet;
                if (a.length > 1) {
                    var rv = ev.eval (a[1]);
                    if (rv.kind != ValueKind.RANGE) return Value.err (ErrorKind.VALUE);
                    r = rv.area.r1;
                    c = rv.area.c1;
                    s = rv.area.sheet ?? ev.sheet;
                }
                switch (what) {
                    case "row": return Value.num (r + 1);
                    case "col": return Value.num (c + 1);
                    case "address": return Value.str (Address.cell (r, c, true, true));
                    case "contents": return ev.cell (s, r, c);
                    case "type":
                        var v = ev.cell (s, r, c);
                        return Value.str (v.kind == ValueKind.EMPTY ? "b" : (v.kind == ValueKind.TEXT ? "l" : "v"));
                    case "width": return Value.num (Math.round (s.col_width (c) / 7.0));
                    case "format": return Value.str (s.style_at (r, c).number_format);
                    case "filename": return Value.str ("");
                    case "color": return Value.num (s.style_at (r, c).number_format.contains ("[Red]") ? 1 : 0);
                    case "parentheses": return Value.num (s.style_at (r, c).number_format.split (";")[0].contains ("(") ? 1 : 0);
                    case "prefix":
                        var pv = ev.cell (s, r, c);
                        if (pv.kind != ValueKind.TEXT) return Value.str ("");
                        switch (s.style_at (r, c).halign) {
                            case HAlign.RIGHT: return Value.str ("\"");
                            case HAlign.CENTER: return Value.str ("^");
                            case HAlign.FILL: return Value.str ("\\");
                            default: return Value.str ("'");
                        }
                    case "protect": return Value.num (s.style_at (r, c).locked ? 1 : 0);
                }
                return Value.err (ErrorKind.VALUE);
            });
            add ("SHEET", 0, 1, "Information", "SHEET([reference])", _("The number of a sheet"), (ev, a) => {
                Sheet s = ev.sheet;
                if (a.length > 0) {
                    var v = ev.eval (a[0]);
                    if (v.kind == ValueKind.RANGE) s = v.area.sheet ?? ev.sheet;
                    else if (v.kind == ValueKind.TEXT) {
                        var f = ev.book.find_sheet (v.text);
                        if (f == null) return Value.err (ErrorKind.NA);
                        s = f;
                    }
                }
                return Value.num (ev.book.sheets.index_of (s) + 1);
            });
            add ("SHEETS", 0, 1, "Information", "SHEETS([reference])", _("The number of sheets"), (ev, a) => Value.num (a.length > 0 ? 1 : ev.book.sheets.size));
        }
    }
}
