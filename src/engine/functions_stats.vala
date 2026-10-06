namespace Singularity.Apps.Spreadsheet {

    public class StatFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Statistical", syntax, summary, (owned) impl);
        }

        private delegate Value ListOp (Gee.ArrayList<double?> list);

        private static void over (string name, string summary, owned ListOp op, bool a_variant = false) {
            ListOp f = (owned) op;
            add (name, 1, -1, name + "(value1, [value2], ...)", summary, (ev, a) => {
                var list = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, list, a_variant);
                if (e != null) return e;
                return f (list);
            });
        }

        private static double mean (Gee.ArrayList<double?> l) {
            double s = 0;
            foreach (var d in l) s += d;
            return s / l.size;
        }

        private static double sum_sq_dev (Gee.ArrayList<double?> l) {
            double m = mean (l);
            double s = 0;
            foreach (var d in l) s += (d - m) * (d - m);
            return s;
        }

        private static double[] sorted (Gee.ArrayList<double?> l) {
            double[] arr = new double[l.size];
            for (int i = 0; i < l.size; i++) arr[i] = l[i];
            qsort_double (arr);
            return arr;
        }

        private static void qsort_double (double[] arr) {
            var list = new Gee.ArrayList<double?> ();
            foreach (double d in arr) list.add (d);
            list.sort ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
            for (int i = 0; i < arr.length; i++) arr[i] = list[i];
        }

        private static double percentile_inc (double[] s, double p) {
            double h = (s.length - 1) * p;
            int lo = (int) Math.floor (h);
            int hi = int.min (lo + 1, s.length - 1);
            return s[lo] + (h - lo) * (s[hi] - s[lo]);
        }

        private static Value percentile_exc (double[] s, double p) {
            int n = s.length;
            double h = (n + 1) * p;
            if (h < 1 || h > n) return Value.err (ErrorKind.NUM);
            int lo = (int) Math.floor (h);
            int hi = int.min (lo + 1, n);
            return Value.num (s[lo - 1] + (h - lo) * (s[hi - 1] - s[lo - 1]));
        }

        private static Value pairs (Evaluator ev, Node x, Node y, Gee.ArrayList<double?> xs, Gee.ArrayList<double?> ys) {
            var mx = ev.to_matrix (ev.eval (x));
            var my = ev.to_matrix (ev.eval (y));
            int nx = mx.length[0] * mx.length[1];
            int ny = my.length[0] * my.length[1];
            if (nx != ny) return Value.err (ErrorKind.NA);
            for (int i = 0; i < nx; i++) {
                var a = mx[i / mx.length[1], i % mx.length[1]];
                var b = my[i / my.length[1], i % my.length[1]];
                if (a.is_error ()) return a;
                if (b.is_error ()) return b;
                if (a.kind == ValueKind.NUMBER && b.kind == ValueKind.NUMBER) {
                    xs.add (a.number);
                    ys.add (b.number);
                }
            }
            return Value.empty ();
        }

        public static double norm_cdf (double z) {
            return 0.5 * Math.erfc (-z / Math.SQRT2);
        }

        private static double erfc (double x) {
            double z = Math.fabs (x);
            double t = 1 / (1 + 0.5 * z);
            double r = t * Math.exp (-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 + t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
            return x >= 0 ? r : 2 - r;
        }

        public static double norm_inv (double p) {
            double[] a = { -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00 };
            double[] b = { -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01 };
            double[] c = { -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00 };
            double[] d = { 7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00 };
            double q, r, x;
            if (p < 0.02425) {
                q = Math.sqrt (-2 * Math.log (p));
                x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
            } else if (p > 1 - 0.02425) {
                q = Math.sqrt (-2 * Math.log (1 - p));
                x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
            } else {
                q = p - 0.5;
                r = q * q;
                x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
            }
            for (int i = 0; i < 2; i++) {
                double e = norm_cdf (x) - p;
                double u = e * Math.sqrt (2 * Math.PI) * Math.exp (x * x / 2);
                x = x - u / (1 + x * u / 2);
            }
            return x;
        }

        public static void register () {
            over ("AVERAGE", _("The average of the numbers"), (l) => l.size == 0 ? Value.err (ErrorKind.DIV0) : Value.num (mean (l)));
            over ("AVERAGEA", _("The average, counting text as zero"), (l) => l.size == 0 ? Value.err (ErrorKind.DIV0) : Value.num (mean (l)), true);
            over ("MIN", _("The smallest number"), (l) => {
                double m = double.INFINITY;
                foreach (var d in l) m = double.min (m, d);
                return Value.num (l.size == 0 ? 0 : m);
            });
            over ("MAX", _("The largest number"), (l) => {
                double m = -double.INFINITY;
                foreach (var d in l) m = double.max (m, d);
                return Value.num (l.size == 0 ? 0 : m);
            });
            over ("MINA", _("The smallest value, counting text as zero"), (l) => {
                double m = double.INFINITY;
                foreach (var d in l) m = double.min (m, d);
                return Value.num (l.size == 0 ? 0 : m);
            }, true);
            over ("MAXA", _("The largest value, counting text as zero"), (l) => {
                double m = -double.INFINITY;
                foreach (var d in l) m = double.max (m, d);
                return Value.num (l.size == 0 ? 0 : m);
            }, true);
            over ("MEDIAN", _("The middle number"), (l) => {
                if (l.size == 0) return Value.err (ErrorKind.NUM);
                var s = sorted (l);
                int n = s.length;
                return Value.num (n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2);
            });
            over ("MODE", _("The most common number"), (l) => {
                double best = 0;
                int best_n = 1;
                for (int i = 0; i < l.size; i++) {
                    int n = 0;
                    for (int j = 0; j < l.size; j++) if (l[j] == l[i]) n++;
                    if (n > best_n) {
                        best_n = n;
                        best = l[i];
                    }
                }
                return best_n > 1 ? Value.num (best) : Value.err (ErrorKind.NA);
            });
            Functions.alias ("MODE.SNGL", "MODE");
            over ("STDEV", _("Standard deviation of a sample"), (l) => l.size < 2 ? Value.err (ErrorKind.DIV0) : Value.num (Math.sqrt (sum_sq_dev (l) / (l.size - 1))));
            Functions.alias ("STDEV.S", "STDEV");
            over ("STDEVA", _("Standard deviation of a sample, counting text"), (l) => l.size < 2 ? Value.err (ErrorKind.DIV0) : Value.num (Math.sqrt (sum_sq_dev (l) / (l.size - 1))), true);
            over ("STDEVP", _("Standard deviation of a population"), (l) => l.size < 1 ? Value.err (ErrorKind.DIV0) : Value.num (Math.sqrt (sum_sq_dev (l) / l.size)));
            Functions.alias ("STDEV.P", "STDEVP");
            over ("VAR", _("Variance of a sample"), (l) => l.size < 2 ? Value.err (ErrorKind.DIV0) : Value.num (sum_sq_dev (l) / (l.size - 1)));
            Functions.alias ("VAR.S", "VAR");
            over ("VARP", _("Variance of a population"), (l) => l.size < 1 ? Value.err (ErrorKind.DIV0) : Value.num (sum_sq_dev (l) / l.size));
            Functions.alias ("VAR.P", "VARP");
            over ("DEVSQ", _("Sum of squared deviations"), (l) => l.size == 0 ? Value.err (ErrorKind.NUM) : Value.num (sum_sq_dev (l)));
            over ("AVEDEV", _("Average absolute deviation"), (l) => {
                if (l.size == 0) return Value.err (ErrorKind.NUM);
                double m = mean (l), s = 0;
                foreach (var d in l) s += Math.fabs (d - m);
                return Value.num (s / l.size);
            });
            over ("GEOMEAN", _("Geometric mean"), (l) => {
                if (l.size == 0) return Value.err (ErrorKind.NUM);
                double s = 0;
                foreach (var d in l) {
                    if (d <= 0) return Value.err (ErrorKind.NUM);
                    s += Math.log (d);
                }
                return Value.num (Math.exp (s / l.size));
            });
            over ("HARMEAN", _("Harmonic mean"), (l) => {
                if (l.size == 0) return Value.err (ErrorKind.NUM);
                double s = 0;
                foreach (var d in l) {
                    if (d <= 0) return Value.err (ErrorKind.NUM);
                    s += 1 / d;
                }
                return Value.num (l.size / s);
            });
            add ("COUNT", 1, -1, "COUNT(value1, ...)", _("Counts the numbers"), (ev, a) => {
                int n = 0;
                foreach (var node in a) {
                    ev.visit_values (node, (v, from_ref) => {
                        if (v.kind == ValueKind.NUMBER) n++;
                        else if (!from_ref && v.kind == ValueKind.BOOL) n++;
                        else if (!from_ref && v.kind == ValueKind.TEXT) {
                            double d;
                            if (Evaluator.to_number (v, out d) == null) n++;
                        }
                        return true;
                    });
                }
                return Value.num (n);
            });
            add ("COUNTA", 1, -1, "COUNTA(value1, ...)", _("Counts the cells that are not empty"), (ev, a) => {
                int n = 0;
                foreach (var node in a) {
                    if (node.kind == NodeKind.MISSING) continue;
                    ev.visit_values (node, (v, r) => {
                        if (v.kind != ValueKind.EMPTY) n++;
                        return true;
                    });
                }
                return Value.num (n);
            });
            add ("COUNTBLANK", 1, 1, "COUNTBLANK(range)", _("Counts the empty cells"), (ev, a) => {
                var v = ev.eval (a[0]);
                if (v.kind != ValueKind.RANGE) return Value.err (ErrorKind.VALUE);
                int64 filled = 0;
                var s = v.area.sheet ?? ev.sheet;
                s.foreach_in (v.area, (r, c, cl) => {
                    var cv = ev.book.cell_value (s, cl);
                    if (!(cv.kind == ValueKind.EMPTY || (cv.kind == ValueKind.TEXT && cv.text == ""))) filled++;
                });
                return Value.num (v.area.size - filled);
            });
            add ("COUNTIF", 2, 2, "COUNTIF(range, criteria)", _("Counts the cells that meet a condition"), (ev, a) => Functions.conditional (ev, a[0], a[1], a[0], 1));
            add ("COUNTIFS", 2, -1, "COUNTIFS(range1, criteria1, ...)", _("Counts the cells that meet several conditions"), (ev, a) => Functions.conditional_multi (ev, a, 1));
            add ("AVERAGEIF", 2, 3, "AVERAGEIF(range, criteria, [average_range])", _("Average of the cells that meet a condition"), (ev, a) => Functions.conditional (ev, a[0], a[1], a.length > 2 ? a[2] : a[0], 2));
            add ("AVERAGEIFS", 3, -1, "AVERAGEIFS(average_range, range1, criteria1, ...)", _("Average of the cells that meet several conditions"), (ev, a) => Functions.conditional_multi (ev, a, 2));
            add ("MINIFS", 3, -1, "MINIFS(min_range, range1, criteria1, ...)", _("Smallest number that meets conditions"), (ev, a) => Functions.conditional_multi (ev, a, 3));
            add ("MAXIFS", 3, -1, "MAXIFS(max_range, range1, criteria1, ...)", _("Largest number that meets conditions"), (ev, a) => Functions.conditional_multi (ev, a, 4));
            add ("LARGE", 2, 2, "LARGE(array, k)", _("The k-th largest number"), (ev, a) => kth (ev, a, true));
            add ("SMALL", 2, 2, "SMALL(array, k)", _("The k-th smallest number"), (ev, a) => kth (ev, a, false));
            add ("RANK", 2, 3, "RANK(number, ref, [order])", _("The rank of a number in a list"), (ev, a) => rank (ev, a, false));
            Functions.alias ("RANK.EQ", "RANK");
            add ("RANK.AVG", 2, 3, "RANK.AVG(number, ref, [order])", _("The rank, averaging ties"), (ev, a) => rank (ev, a, true));
            add ("PERCENTILE", 2, 2, "PERCENTILE(array, k)", _("The k-th percentile"), (ev, a) => pct (ev, a, false, false));
            Functions.alias ("PERCENTILE.INC", "PERCENTILE");
            add ("PERCENTILE.EXC", 2, 2, "PERCENTILE.EXC(array, k)", _("The k-th percentile, exclusive"), (ev, a) => pct (ev, a, true, false));
            add ("QUARTILE", 2, 2, "QUARTILE(array, quart)", _("A quartile of the data"), (ev, a) => pct (ev, a, false, true));
            Functions.alias ("QUARTILE.INC", "QUARTILE");
            add ("QUARTILE.EXC", 2, 2, "QUARTILE.EXC(array, quart)", _("A quartile, exclusive"), (ev, a) => pct (ev, a, true, true));
            add ("PERCENTRANK", 2, 3, "PERCENTRANK(array, x, [significance])", _("The rank of a value as a percentage"), (ev, a) => {
                var list = new Gee.ArrayList<double?> ();
                var e = ev.numbers ({ a[0] }, list);
                if (e != null) return e;
                double x;
                if ((e = ev.arg_number (a[1], out x)) != null) return e;
                int sig = 3;
                if (a.length > 2 && (e = ev.arg_int (a[2], out sig)) != null) return e;
                var s = sorted (list);
                int n = s.length;
                if (n == 0 || x < s[0] || x > s[n - 1]) return Value.err (ErrorKind.NA);
                for (int i = 0; i < n; i++) {
                    if (s[i] == x) return Value.num (Functions.round_digits ((double) i / (n - 1), sig, -1));
                    if (i + 1 < n && s[i] < x && x < s[i + 1]) {
                        double r = (i + (x - s[i]) / (s[i + 1] - s[i])) / (n - 1);
                        return Value.num (Functions.round_digits (r, sig, -1));
                    }
                }
                return Value.err (ErrorKind.NA);
            });
            Functions.alias ("PERCENTRANK.INC", "PERCENTRANK");
            add ("CORREL", 2, 2, "CORREL(array1, array2)", _("Correlation coefficient"), (ev, a) => regression (ev, a, 0));
            Functions.alias ("PEARSON", "CORREL");
            add ("RSQ", 2, 2, "RSQ(known_y, known_x)", _("Square of the correlation"), (ev, a) => regression (ev, { a[1], a[0] }, 1));
            add ("SLOPE", 2, 2, "SLOPE(known_y, known_x)", _("Slope of the regression line"), (ev, a) => regression (ev, { a[1], a[0] }, 2));
            add ("INTERCEPT", 2, 2, "INTERCEPT(known_y, known_x)", _("Intercept of the regression line"), (ev, a) => regression (ev, { a[1], a[0] }, 3));
            add ("COVAR", 2, 2, "COVAR(array1, array2)", _("Covariance of a population"), (ev, a) => regression (ev, a, 4));
            Functions.alias ("COVARIANCE.P", "COVAR");
            add ("COVARIANCE.S", 2, 2, "COVARIANCE.S(array1, array2)", _("Covariance of a sample"), (ev, a) => regression (ev, a, 5));
            add ("STEYX", 2, 2, "STEYX(known_y, known_x)", _("Standard error of the regression"), (ev, a) => regression (ev, { a[1], a[0] }, 6));
            add ("FORECAST", 3, 3, "FORECAST(x, known_y, known_x)", _("A value on the regression line"), (ev, a) => {
                double x;
                var e = ev.arg_number (a[0], out x);
                if (e != null) return e;
                var slope = regression (ev, { a[2], a[1] }, 2);
                var icpt = regression (ev, { a[2], a[1] }, 3);
                if (slope.is_error ()) return slope;
                if (icpt.is_error ()) return icpt;
                return Value.num (icpt.number + slope.number * x);
            });
            Functions.alias ("FORECAST.LINEAR", "FORECAST");
            add ("STANDARDIZE", 3, 3, "STANDARDIZE(x, mean, standard_dev)", _("A normalized value"), (ev, a) => {
                double x, m, sd;
                var e = ev.arg_number (a[0], out x);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out m)) != null) return e;
                if ((e = ev.arg_number (a[2], out sd)) != null) return e;
                if (sd <= 0) return Value.err (ErrorKind.NUM);
                return Value.num ((x - m) / sd);
            });
            add ("NORM.DIST", 4, 4, "NORM.DIST(x, mean, standard_dev, cumulative)", _("Normal distribution"), (ev, a) => {
                double x, m, sd;
                bool cum;
                var e = ev.arg_number (a[0], out x);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out m)) != null) return e;
                if ((e = ev.arg_number (a[2], out sd)) != null) return e;
                if ((e = ev.arg_bool (a[3], out cum)) != null) return e;
                if (sd <= 0) return Value.err (ErrorKind.NUM);
                double z = (x - m) / sd;
                if (cum) return Value.num (norm_cdf (z));
                return Value.num (Math.exp (-z * z / 2) / (sd * Math.sqrt (2 * Math.PI)));
            });
            Functions.alias ("NORMDIST", "NORM.DIST");
            add ("NORM.S.DIST", 1, 2, "NORM.S.DIST(z, [cumulative])", _("Standard normal distribution"), (ev, a) => {
                double z;
                bool cum = true;
                var e = ev.arg_number (a[0], out z);
                if (e != null) return e;
                if (a.length > 1 && (e = ev.arg_bool (a[1], out cum)) != null) return e;
                return Value.num (cum ? norm_cdf (z) : Math.exp (-z * z / 2) / Math.sqrt (2 * Math.PI));
            });
            Functions.alias ("NORMSDIST", "NORM.S.DIST");
            add ("NORM.INV", 3, 3, "NORM.INV(probability, mean, standard_dev)", _("Inverse of the normal distribution"), (ev, a) => {
                double p, m, sd;
                var e = ev.arg_number (a[0], out p);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out m)) != null) return e;
                if ((e = ev.arg_number (a[2], out sd)) != null) return e;
                if (p <= 0 || p >= 1 || sd <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (m + sd * norm_inv (p));
            });
            Functions.alias ("NORMINV", "NORM.INV");
            add ("NORM.S.INV", 1, 1, "NORM.S.INV(probability)", _("Inverse of the standard normal distribution"), (ev, a) => {
                double p;
                var e = ev.arg_number (a[0], out p);
                if (e != null) return e;
                if (p <= 0 || p >= 1) return Value.err (ErrorKind.NUM);
                return Value.num (norm_inv (p));
            });
            Functions.alias ("NORMSINV", "NORM.S.INV");
            add ("CONFIDENCE.NORM", 3, 3, "CONFIDENCE.NORM(alpha, standard_dev, size)", _("Confidence interval of a mean"), (ev, a) => {
                double al, sd, n;
                var e = ev.arg_number (a[0], out al);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out sd)) != null) return e;
                if ((e = ev.arg_number (a[2], out n)) != null) return e;
                if (al <= 0 || al >= 1 || sd <= 0 || n < 1) return Value.err (ErrorKind.NUM);
                return Value.num (norm_inv (1 - al / 2) * sd / Math.sqrt (Math.trunc (n)));
            });
            Functions.alias ("CONFIDENCE", "CONFIDENCE.NORM");
            add ("BINOM.DIST", 4, 4, "BINOM.DIST(successes, trials, probability, cumulative)", _("Binomial distribution"), (ev, a) => {
                double k, n, p;
                bool cum;
                var e = ev.arg_number (a[0], out k);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out n)) != null) return e;
                if ((e = ev.arg_number (a[2], out p)) != null) return e;
                if ((e = ev.arg_bool (a[3], out cum)) != null) return e;
                k = Math.trunc (k);
                n = Math.trunc (n);
                if (k < 0 || k > n || p < 0 || p > 1) return Value.err (ErrorKind.NUM);
                double total = 0;
                for (double i = cum ? 0 : k; i <= k; i++) {
                    double lc = Functions.lgamma (n + 1) - Functions.lgamma (i + 1) - Functions.lgamma (n - i + 1);
                    total += Math.exp (lc + i * Math.log (p) + (n - i) * Math.log (1 - p));
                }
                return Value.num (total);
            });
            Functions.alias ("BINOMDIST", "BINOM.DIST");
            add ("POISSON.DIST", 3, 3, "POISSON.DIST(x, mean, cumulative)", _("Poisson distribution"), (ev, a) => {
                double x, m;
                bool cum;
                var e = ev.arg_number (a[0], out x);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out m)) != null) return e;
                if ((e = ev.arg_bool (a[2], out cum)) != null) return e;
                x = Math.trunc (x);
                if (x < 0 || m < 0) return Value.err (ErrorKind.NUM);
                double total = 0;
                for (double i = cum ? 0 : x; i <= x; i++) total += Math.exp (i * Math.log (m) - m - Functions.lgamma (i + 1));
                return Value.num (total);
            });
            Functions.alias ("POISSON", "POISSON.DIST");
            add ("EXPON.DIST", 3, 3, "EXPON.DIST(x, lambda, cumulative)", _("Exponential distribution"), (ev, a) => {
                double x, l;
                bool cum;
                var e = ev.arg_number (a[0], out x);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out l)) != null) return e;
                if ((e = ev.arg_bool (a[2], out cum)) != null) return e;
                if (x < 0 || l <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (cum ? 1 - Math.exp (-l * x) : l * Math.exp (-l * x));
            });
            Functions.alias ("EXPONDIST", "EXPON.DIST");
        }

        private static Value kth (Evaluator ev, Node[] a, bool largest) {
            var list = new Gee.ArrayList<double?> ();
            var e = ev.numbers ({ a[0] }, list);
            if (e != null) return e;
            int k;
            if ((e = ev.arg_int (a[1], out k)) != null) return e;
            if (k < 1 || k > list.size) return Value.err (ErrorKind.NUM);
            var s = sorted (list);
            return Value.num (largest ? s[s.length - k] : s[k - 1]);
        }

        private static Value rank (Evaluator ev, Node[] a, bool avg) {
            double x;
            var e = ev.arg_number (a[0], out x);
            if (e != null) return e;
            var list = new Gee.ArrayList<double?> ();
            if ((e = ev.numbers ({ a[1] }, list)) != null) return e;
            int order = 0;
            if (a.length > 2 && (e = ev.arg_int (a[2], out order)) != null) return e;
            int better = 0, same = 0;
            foreach (var d in list) {
                if (d == x) same++;
                else if (order == 0 ? d > x : d < x) better++;
            }
            if (same == 0) return Value.err (ErrorKind.NA);
            return Value.num (avg ? better + (same + 1) / 2.0 : better + 1);
        }

        private static Value pct (Evaluator ev, Node[] a, bool exc, bool quart) {
            var list = new Gee.ArrayList<double?> ();
            var e = ev.numbers ({ a[0] }, list);
            if (e != null) return e;
            double k;
            if ((e = ev.arg_number (a[1], out k)) != null) return e;
            if (quart) {
                k = Math.trunc (k);
                if (k < 0 || k > 4 || (exc && (k <= 0 || k >= 4))) return Value.err (ErrorKind.NUM);
                k /= 4;
            }
            if (list.size == 0 || k < 0 || k > 1) return Value.err (ErrorKind.NUM);
            var s = sorted (list);
            if (exc) return percentile_exc (s, k);
            return Value.num (percentile_inc (s, k));
        }

        private static Value regression (Evaluator ev, Node[] a, int mode) {
            var xs = new Gee.ArrayList<double?> ();
            var ys = new Gee.ArrayList<double?> ();
            var e = pairs (ev, a[0], a[1], xs, ys);
            if (e.is_error ()) return e;
            int n = xs.size;
            if (n < 2 && mode != 4) return Value.err (ErrorKind.DIV0);
            if (n < 1) return Value.err (ErrorKind.DIV0);
            double mx = mean (xs), my = mean (ys);
            double sxy = 0, sxx = 0, syy = 0;
            for (int i = 0; i < n; i++) {
                sxy += (xs[i] - mx) * (ys[i] - my);
                sxx += (xs[i] - mx) * (xs[i] - mx);
                syy += (ys[i] - my) * (ys[i] - my);
            }
            switch (mode) {
                case 0:
                    if (sxx == 0 || syy == 0) return Value.err (ErrorKind.DIV0);
                    return Value.num (sxy / Math.sqrt (sxx * syy));
                case 1:
                    if (sxx == 0 || syy == 0) return Value.err (ErrorKind.DIV0);
                    return Value.num (sxy * sxy / (sxx * syy));
                case 2:
                    if (sxx == 0) return Value.err (ErrorKind.DIV0);
                    return Value.num (sxy / sxx);
                case 3:
                    if (sxx == 0) return Value.err (ErrorKind.DIV0);
                    return Value.num (my - sxy / sxx * mx);
                case 4:
                    return Value.num (sxy / n);
                case 5:
                    return Value.num (sxy / (n - 1));
                case 6:
                    if (sxx == 0 || n < 3) return Value.err (ErrorKind.DIV0);
                    return Value.num (Math.sqrt ((syy - sxy * sxy / sxx) / (n - 2)));
            }
            return Value.err (ErrorKind.VALUE);
        }
    }
}
