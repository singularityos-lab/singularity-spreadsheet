namespace Singularity.Apps.Spreadsheet {

    public class DistributionFunctions {
        public delegate Value ScalarN (double[] x);
        public delegate double Cdf (double x);

        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Statistical", syntax, summary, (owned) impl);
        }

        public static Value lift (Evaluator ev, Value[] vals, ScalarN f) {
            int rows = 1, cols = 1;
            bool multi = false;
            foreach (var v in vals) {
                if (v.kind == ValueKind.REFS) return Value.err (ErrorKind.VALUE);
                if (v.is_multi ()) {
                    var m = ev.to_matrix (v);
                    rows = int.max (rows, m.length[0]);
                    cols = int.max (cols, m.length[1]);
                    multi = true;
                }
            }
            if (!multi) {
                double[] xs = new double[vals.length];
                for (int i = 0; i < vals.length; i++) {
                    var e = Evaluator.to_number (ev.deref (vals[i]), out xs[i]);
                    if (e != null) return e;
                }
                return f (xs);
            }
            var mats = new Gee.ArrayList<Value> ();
            foreach (var v in vals) mats.add (Value.matrix (ev.to_matrix (v.is_multi () ? v : ev.deref (v))));
            var out_m = new Value[rows, cols];
            for (int i = 0; i < rows; i++) {
                for (int j = 0; j < cols; j++) {
                    double[] xs = new double[vals.length];
                    Value? err = null;
                    for (int k = 0; k < vals.length && err == null; k++) {
                        var m = mats[k].array;
                        int ii = m.length[0] == 1 ? 0 : i, jj = m.length[1] == 1 ? 0 : j;
                        if (ii >= m.length[0] || jj >= m.length[1]) {
                            err = Value.err (ErrorKind.NA);
                            break;
                        }
                        err = Evaluator.to_number (m[ii, jj], out xs[k]);
                    }
                    out_m[i, j] = err ?? f (xs);
                }
            }
            return Value.matrix (out_m);
        }

        public static void scalar (string name, int min, string syntax, string summary, double[] defaults, owned ScalarN f, string category = "Statistical") {
            ScalarN fn = (owned) f;
            int max = defaults.length;
            double[] defs = defaults;
            Functions.add (name, min, max, category, syntax, summary, (ev, a) => {
                Value[] vals = {};
                for (int i = 0; i < max; i++) {
                    if (i < a.length && a[i].kind != NodeKind.MISSING) vals += ev.eval (a[i]);
                    else if (defs[i].is_nan ()) return Value.err (ErrorKind.VALUE);
                    else vals += Value.num (defs[i]);
                }
                return lift (ev, vals, fn);
            });
        }

        public static double lgam (double x) {
            return Math.lgamma (x);
        }

        public static double norm_cdf (double z) {
            return 0.5 * Math.erfc (-z / Math.SQRT2);
        }

        public static double norm_pdf (double z) {
            return Math.exp (-z * z / 2) / Math.sqrt (2 * Math.PI);
        }

        public static double norm_inv (double p) {
            double x = StatFunctions.norm_inv (p);
            for (int i = 0; i < 3; i++) {
                double e = norm_cdf (x) - p;
                double d = norm_pdf (x);
                if (d <= 0) break;
                double u = e / d;
                x = x - u / (1 + x * u / 2);
            }
            return x;
        }

        public static void gamma_pq (double a, double x, out double p, out double q) {
            p = 0;
            q = 1;
            if (x <= 0) return;
            double gln = lgam (a);
            if (x < a + 1) {
                double ap = a, sum = 1 / a, del = sum;
                for (int n = 0; n < 10000; n++) {
                    ap += 1;
                    del *= x / ap;
                    sum += del;
                    if (Math.fabs (del) < Math.fabs (sum) * 1e-16) break;
                }
                p = sum * Math.exp (-x + a * Math.log (x) - gln);
                q = 1 - p;
                return;
            }
            double tiny = 1e-300;
            double b = x + 1 - a, c = 1 / tiny, d = 1 / b, h = d;
            for (int i = 1; i < 10000; i++) {
                double an = -i * (i - a);
                b += 2;
                d = an * d + b;
                if (Math.fabs (d) < tiny) d = tiny;
                c = b + an / c;
                if (Math.fabs (c) < tiny) c = tiny;
                d = 1 / d;
                double del = d * c;
                h *= del;
                if (Math.fabs (del - 1) < 1e-16) break;
            }
            q = Math.exp (-x + a * Math.log (x) - gln) * h;
            p = 1 - q;
        }

        private static double betacf (double a, double b, double x) {
            double tiny = 1e-300;
            double qab = a + b, qap = a + 1, qam = a - 1;
            double c = 1, d = 1 - qab * x / qap;
            if (Math.fabs (d) < tiny) d = tiny;
            d = 1 / d;
            double h = d;
            for (int m = 1; m < 10000; m++) {
                int m2 = 2 * m;
                double aa = m * (b - m) * x / ((qam + m2) * (a + m2));
                d = 1 + aa * d;
                if (Math.fabs (d) < tiny) d = tiny;
                c = 1 + aa / c;
                if (Math.fabs (c) < tiny) c = tiny;
                d = 1 / d;
                h *= d * c;
                aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
                d = 1 + aa * d;
                if (Math.fabs (d) < tiny) d = tiny;
                c = 1 + aa / c;
                if (Math.fabs (c) < tiny) c = tiny;
                d = 1 / d;
                double del = d * c;
                h *= del;
                if (Math.fabs (del - 1) < 1e-16) break;
            }
            return h;
        }

        public static double betai (double a, double b, double x) {
            if (x <= 0) return 0;
            if (x >= 1) return 1;
            double bt = Math.exp (lgam (a + b) - lgam (a) - lgam (b) + a * Math.log (x) + b * Math.log (1 - x));
            if (x < (a + 1) / (a + b + 2)) return bt * betacf (a, b, x) / a;
            return 1 - bt * betacf (b, a, 1 - x) / b;
        }

        public static double t_cdf (double t, double v) {
            double x = v / (v + t * t);
            double tail = 0.5 * betai (v / 2, 0.5, x);
            return t > 0 ? 1 - tail : tail;
        }

        public static double t_right (double t, double v) {
            double x = v / (v + t * t);
            double tail = 0.5 * betai (v / 2, 0.5, x);
            return t > 0 ? tail : 1 - tail;
        }

        public static double t_pdf (double t, double v) {
            return Math.exp (lgam ((v + 1) / 2) - lgam (v / 2)) / Math.sqrt (v * Math.PI) * Math.pow (1 + t * t / v, -(v + 1) / 2);
        }

        public static double chi_cdf (double x, double k) {
            double p, q;
            gamma_pq (k / 2, x / 2, out p, out q);
            return p;
        }

        public static double chi_right (double x, double k) {
            double p, q;
            gamma_pq (k / 2, x / 2, out p, out q);
            return q;
        }

        public static double f_cdf (double x, double d1, double d2) {
            if (x <= 0) return 0;
            return betai (d1 / 2, d2 / 2, d1 * x / (d1 * x + d2));
        }

        public static double f_right (double x, double d1, double d2) {
            if (x <= 0) return 1;
            return betai (d2 / 2, d1 / 2, d2 / (d2 + d1 * x));
        }

        public static double invert (Cdf cdf, double p, double lo, double hi, bool increasing = true) {
            if (hi.is_infinity () != 0 || hi > 1e300) {
                hi = lo > 0 ? lo * 2 : 1;
                for (int i = 0; i < 2000; i++) {
                    double v = cdf (hi);
                    if (increasing ? v >= p : v <= p) break;
                    hi = hi * 2 + 1;
                }
            }
            if (lo.is_infinity () != 0 || lo < -1e300) {
                lo = hi < 0 ? hi * 2 : -1;
                for (int i = 0; i < 2000; i++) {
                    double v = cdf (lo);
                    if (increasing ? v <= p : v >= p) break;
                    lo = lo * 2 - 1;
                }
            }
            for (int i = 0; i < 300; i++) {
                double mid = (lo + hi) / 2;
                if (mid == lo || mid == hi) break;
                double v = cdf (mid);
                if (increasing ? v < p : v > p) lo = mid;
                else hi = mid;
            }
            return (lo + hi) / 2;
        }

        public static double ln_choose (double n, double k) {
            return lgam (n + 1) - lgam (k + 1) - lgam (n - k + 1);
        }

        public static double binom_pmf (double k, double n, double p) {
            if (k < 0 || k > n) return 0;
            if (p == 0) return k == 0 ? 1 : 0;
            if (p == 1) return k == n ? 1 : 0;
            return Math.exp (ln_choose (n, k) + k * Math.log (p) + (n - k) * Math.log (1 - p));
        }

        private static double hypgeom_pmf (double k, double n, double K, double N) {
            if (k < 0 || k > n || k > K || n - k > N - K) return 0;
            return Math.exp (ln_choose (K, k) + ln_choose (N - K, n - k) - ln_choose (N, n));
        }

        private static bool b (double x) {
            return x != 0;
        }

        private static Value num (double x) {
            return Value.num (x);
        }

        private static Value bad () {
            return Value.err (ErrorKind.NUM);
        }

        public static Gee.ArrayList<double?>? list_of (Evaluator ev, Node n, out Value? err) {
            var l = new Gee.ArrayList<double?> ();
            err = ev.numbers ({ n }, l);
            return err == null ? l : null;
        }

        private static double mean_of (Gee.ArrayList<double?> l) {
            double s = 0;
            foreach (var d in l) s += d;
            return s / l.size;
        }

        private static double var_of (Gee.ArrayList<double?> l) {
            double m = mean_of (l), s = 0;
            foreach (var d in l) s += (d - m) * (d - m);
            return s / (l.size - 1);
        }

        private static Value variance_a (Evaluator ev, Node[] a, bool sample, bool root) {
            var l = new Gee.ArrayList<double?> ();
            var e = ev.numbers (a, l, true);
            if (e != null) return e;
            int n = l.size;
            if (n < (sample ? 2 : 1)) return Value.err (ErrorKind.DIV0);
            double m = mean_of (l), s = 0;
            foreach (var d in l) s += (d - m) * (d - m);
            double v = s / (sample ? n - 1 : n);
            return num (root ? Math.sqrt (v) : v);
        }

        public static void register () {
            register_t ();
            register_chi ();
            register_f ();
            register_gamma_beta ();
            register_discrete ();
            register_misc ();
            register_tests ();
        }

        private static void register_t () {
            scalar ("T.DIST", 3, "T.DIST(x, deg_freedom, cumulative)", _("Student's left-tailed t-distribution"), { double.NAN, double.NAN, double.NAN }, (x) => {
                double v = Math.trunc (x[1]);
                if (v < 1) return bad ();
                if (!b (x[2]) && v < 1) return Value.err (ErrorKind.DIV0);
                return num (b (x[2]) ? t_cdf (x[0], v) : t_pdf (x[0], v));
            });
            scalar ("T.DIST.2T", 2, "T.DIST.2T(x, deg_freedom)", _("Student's two-tailed t-distribution"), { double.NAN, double.NAN }, (x) => {
                double v = Math.trunc (x[1]);
                if (v < 1 || x[0] < 0) return bad ();
                return num (2 * t_right (x[0], v));
            });
            scalar ("T.DIST.RT", 2, "T.DIST.RT(x, deg_freedom)", _("Student's right-tailed t-distribution"), { double.NAN, double.NAN }, (x) => {
                double v = Math.trunc (x[1]);
                if (v < 1) return bad ();
                return num (t_right (x[0], v));
            });
            scalar ("TDIST", 3, "TDIST(x, deg_freedom, tails)", _("Student's t-distribution"), { double.NAN, double.NAN, double.NAN }, (x) => {
                double v = Math.trunc (x[1]);
                double tails = Math.trunc (x[2]);
                if (v < 1 || x[0] < 0 || (tails != 1 && tails != 2)) return bad ();
                return num (tails * t_right (x[0], v));
            }, "Compatibility");
            scalar ("T.INV", 2, "T.INV(probability, deg_freedom)", _("Left-tailed inverse of the t-distribution"), { double.NAN, double.NAN }, (x) => {
                double p = x[0], v = Math.trunc (x[1]);
                if (p <= 0 || p >= 1 || v < 1) return bad ();
                return num (invert ((t) => t_cdf (t, v), p, -double.INFINITY, double.INFINITY));
            });
            scalar ("T.INV.2T", 2, "T.INV.2T(probability, deg_freedom)", _("Two-tailed inverse of the t-distribution"), { double.NAN, double.NAN }, (x) => {
                double p = x[0], v = Math.trunc (x[1]);
                if (p <= 0 || p > 1 || v < 1) return bad ();
                return num (invert ((t) => 2 * t_right (t, v), p, 0, double.INFINITY, false));
            });
            Functions.alias ("TINV", "T.INV.2T");
            add ("CONFIDENCE.T", 3, 3, "CONFIDENCE.T(alpha, standard_dev, size)", _("Confidence interval of a mean using the t-distribution"), (ev, a) => {
                return lift (ev, { ev.eval (a[0]), ev.eval (a[1]), ev.eval (a[2]) }, (x) => {
                    double n = Math.trunc (x[2]);
                    if (x[0] <= 0 || x[0] >= 1 || x[1] <= 0 || n < 1) return bad ();
                    if (n == 1) return Value.err (ErrorKind.DIV0);
                    double t = invert ((t) => 2 * t_right (t, n - 1), x[0], 0, double.INFINITY, false);
                    return num (t * x[1] / Math.sqrt (n));
                });
            });
        }

        private static void register_chi () {
            scalar ("CHISQ.DIST", 3, "CHISQ.DIST(x, deg_freedom, cumulative)", _("Left-tailed chi-squared distribution"), { double.NAN, double.NAN, double.NAN }, (x) => {
                double k = Math.trunc (x[1]);
                if (x[0] < 0 || k < 1 || k > 1e10) return bad ();
                if (b (x[2])) return num (chi_cdf (x[0], k));
                if (x[0] == 0) return k == 2 ? num (0.5) : (k < 2 ? bad () : num (0));
                return num (Math.exp ((k / 2 - 1) * Math.log (x[0]) - x[0] / 2 - (k / 2) * Math.LN2 - lgam (k / 2)));
            });
            scalar ("CHISQ.DIST.RT", 2, "CHISQ.DIST.RT(x, deg_freedom)", _("Right-tailed chi-squared distribution"), { double.NAN, double.NAN }, (x) => {
                double k = Math.trunc (x[1]);
                if (x[0] < 0 || k < 1 || k > 1e10) return bad ();
                return num (chi_right (x[0], k));
            });
            Functions.alias ("CHIDIST", "CHISQ.DIST.RT");
            scalar ("CHISQ.INV", 2, "CHISQ.INV(probability, deg_freedom)", _("Left-tailed inverse of the chi-squared distribution"), { double.NAN, double.NAN }, (x) => {
                double k = Math.trunc (x[1]);
                if (x[0] < 0 || x[0] >= 1 || k < 1 || k > 1e10) return bad ();
                if (x[0] == 0) return num (0);
                return num (invert ((t) => chi_cdf (t, k), x[0], 0, double.INFINITY));
            });
            scalar ("CHISQ.INV.RT", 2, "CHISQ.INV.RT(probability, deg_freedom)", _("Right-tailed inverse of the chi-squared distribution"), { double.NAN, double.NAN }, (x) => {
                double k = Math.trunc (x[1]);
                if (x[0] <= 0 || x[0] > 1 || k < 1 || k > 1e10) return bad ();
                if (x[0] == 1) return num (0);
                return num (invert ((t) => chi_right (t, k), x[0], 0, double.INFINITY, false));
            });
            Functions.alias ("CHIINV", "CHISQ.INV.RT");
            add ("CHISQ.TEST", 2, 2, "CHISQ.TEST(actual_range, expected_range)", _("The test for independence"), (ev, a) => {
                var am = ev.to_matrix (ev.eval (a[0]));
                var em = ev.to_matrix (ev.eval (a[1]));
                int r = am.length[0], c = am.length[1];
                if (r != em.length[0] || c != em.length[1]) return Value.err (ErrorKind.NA);
                double chi = 0;
                int count = 0;
                for (int i = 0; i < r; i++) {
                    for (int j = 0; j < c; j++) {
                        var x = am[i, j];
                        var y = em[i, j];
                        if (x.is_error ()) return x;
                        if (y.is_error ()) return y;
                        if (x.kind != ValueKind.NUMBER || y.kind != ValueKind.NUMBER) continue;
                        if (y.number == 0) return Value.err (ErrorKind.DIV0);
                        chi += (x.number - y.number) * (x.number - y.number) / y.number;
                        count++;
                    }
                }
                double df = r > 1 && c > 1 ? (r - 1) * (c - 1) : (double) (r * c - 1);
                if (df < 1 || count == 0) return Value.err (ErrorKind.NA);
                return num (chi_right (chi, df));
            });
            Functions.alias ("CHITEST", "CHISQ.TEST");
        }

        private static void register_f () {
            scalar ("F.DIST", 4, "F.DIST(x, deg_freedom1, deg_freedom2, cumulative)", _("Left-tailed F probability distribution"), { double.NAN, double.NAN, double.NAN, double.NAN }, (x) => {
                double d1 = Math.trunc (x[1]), d2 = Math.trunc (x[2]);
                if (x[0] < 0 || d1 < 1 || d2 < 1) return bad ();
                if (b (x[3])) return num (f_cdf (x[0], d1, d2));
                if (x[0] == 0) return num (d1 == 2 ? 1 : 0);
                double lp = 0.5 * (d1 * Math.log (d1 * x[0]) + d2 * Math.log (d2) - (d1 + d2) * Math.log (d1 * x[0] + d2)) - Math.log (x[0]) - (lgam (d1 / 2) + lgam (d2 / 2) - lgam ((d1 + d2) / 2));
                return num (Math.exp (lp));
            });
            scalar ("F.DIST.RT", 3, "F.DIST.RT(x, deg_freedom1, deg_freedom2)", _("Right-tailed F probability distribution"), { double.NAN, double.NAN, double.NAN }, (x) => {
                double d1 = Math.trunc (x[1]), d2 = Math.trunc (x[2]);
                if (x[0] < 0 || d1 < 1 || d2 < 1) return bad ();
                return num (f_right (x[0], d1, d2));
            });
            Functions.alias ("FDIST", "F.DIST.RT");
            scalar ("F.INV", 3, "F.INV(probability, deg_freedom1, deg_freedom2)", _("Inverse of the left-tailed F distribution"), { double.NAN, double.NAN, double.NAN }, (x) => {
                double d1 = Math.trunc (x[1]), d2 = Math.trunc (x[2]);
                if (x[0] < 0 || x[0] > 1 || d1 < 1 || d2 < 1) return bad ();
                if (x[0] == 0) return num (0);
                return num (invert ((t) => f_cdf (t, d1, d2), x[0], 0, double.INFINITY));
            });
            scalar ("F.INV.RT", 3, "F.INV.RT(probability, deg_freedom1, deg_freedom2)", _("Inverse of the right-tailed F distribution"), { double.NAN, double.NAN, double.NAN }, (x) => {
                double d1 = Math.trunc (x[1]), d2 = Math.trunc (x[2]);
                if (x[0] <= 0 || x[0] > 1 || d1 < 1 || d2 < 1) return bad ();
                if (x[0] == 1) return num (0);
                return num (invert ((t) => f_right (t, d1, d2), x[0], 0, double.INFINITY, false));
            });
            Functions.alias ("FINV", "F.INV.RT");
            add ("F.TEST", 2, 2, "F.TEST(array1, array2)", _("Two-tailed probability that the variances are not different"), (ev, a) => {
                Value? e = null;
                var l1 = list_of (ev, a[0], out e);
                if (e != null) return e;
                var l2 = list_of (ev, a[1], out e);
                if (e != null) return e;
                if (l1.size < 2 || l2.size < 2) return Value.err (ErrorKind.DIV0);
                double v1 = var_of (l1), v2 = var_of (l2);
                if (v1 == 0 || v2 == 0) return Value.err (ErrorKind.DIV0);
                double f = v1 / v2;
                double p = f_cdf (f, l1.size - 1, l2.size - 1);
                return num (2 * double.min (p, 1 - p));
            });
            Functions.alias ("FTEST", "F.TEST");
        }

        private static double beta_scaled_cdf (double x, double al, double be, double lo, double hi) {
            return betai (al, be, (x - lo) / (hi - lo));
        }

        private static void register_gamma_beta () {
            scalar ("GAMMA", 1, "GAMMA(number)", _("The gamma function value"), { double.NAN }, (x) => {
                if (x[0] <= 0 && x[0] == Math.floor (x[0])) return bad ();
                double g = Math.tgamma (x[0]);
                return num (g);
            });
            scalar ("GAMMALN", 1, "GAMMALN(x)", _("Natural logarithm of the gamma function"), { double.NAN }, (x) => {
                if (x[0] <= 0) return bad ();
                return num (lgam (x[0]));
            });
            Functions.alias ("GAMMALN.PRECISE", "GAMMALN");
            scalar ("GAMMA.DIST", 4, "GAMMA.DIST(x, alpha, beta, cumulative)", _("The gamma distribution"), { double.NAN, double.NAN, double.NAN, double.NAN }, (x) => {
                double al = x[1], be = x[2];
                if (x[0] < 0 || al <= 0 || be <= 0) return bad ();
                if (b (x[3])) {
                    double p, q;
                    gamma_pq (al, x[0] / be, out p, out q);
                    return num (p);
                }
                if (x[0] == 0) return al == 1 ? num (1 / be) : (al < 1 ? bad () : num (0));
                return num (Math.exp ((al - 1) * Math.log (x[0]) - x[0] / be - lgam (al) - al * Math.log (be)));
            });
            Functions.alias ("GAMMADIST", "GAMMA.DIST");
            scalar ("GAMMA.INV", 3, "GAMMA.INV(probability, alpha, beta)", _("Inverse of the gamma distribution"), { double.NAN, double.NAN, double.NAN }, (x) => {
                double al = x[1], be = x[2];
                if (x[0] < 0 || x[0] >= 1 || al <= 0 || be <= 0) return bad ();
                if (x[0] == 0) return num (0);
                return num (invert ((t) => {
                    double p, q;
                    gamma_pq (al, t / be, out p, out q);
                    return p;
                }, x[0], 0, double.INFINITY));
            });
            Functions.alias ("GAMMAINV", "GAMMA.INV");
            scalar ("BETA.DIST", 4, "BETA.DIST(x, alpha, beta, cumulative, [A], [B])", _("The beta distribution"), { double.NAN, double.NAN, double.NAN, double.NAN, 0, 1 }, (x) => {
                double al = x[1], be = x[2], lo = x[4], hi = x[5];
                if (al <= 0 || be <= 0 || x[0] < lo || x[0] > hi || lo == hi) return bad ();
                if (b (x[3])) return num (beta_scaled_cdf (x[0], al, be, lo, hi));
                double z = (x[0] - lo) / (hi - lo);
                if ((z == 0 && al < 1) || (z == 1 && be < 1)) return bad ();
                double lp = (al - 1) * Math.log (z) + (be - 1) * Math.log (1 - z) - (lgam (al) + lgam (be) - lgam (al + be));
                return num (Math.exp (lp) / (hi - lo));
            });
            scalar ("BETADIST", 3, "BETADIST(x, alpha, beta, [A], [B])", _("The cumulative beta distribution"), { double.NAN, double.NAN, double.NAN, 0, 1 }, (x) => {
                double al = x[1], be = x[2], lo = x[3], hi = x[4];
                if (al <= 0 || be <= 0 || x[0] < lo || x[0] > hi || lo == hi) return bad ();
                return num (beta_scaled_cdf (x[0], al, be, lo, hi));
            }, "Compatibility");
            scalar ("BETA.INV", 3, "BETA.INV(probability, alpha, beta, [A], [B])", _("Inverse of the beta distribution"), { double.NAN, double.NAN, double.NAN, 0, 1 }, (x) => {
                double al = x[1], be = x[2], lo = x[3], hi = x[4];
                if (x[0] <= 0 || x[0] > 1 || al <= 0 || be <= 0 || lo >= hi) return bad ();
                double z = invert ((t) => betai (al, be, t), x[0], 0, 1);
                return num (lo + z * (hi - lo));
            });
            Functions.alias ("BETAINV", "BETA.INV");
            scalar ("LOGNORM.DIST", 4, "LOGNORM.DIST(x, mean, standard_dev, cumulative)", _("The lognormal distribution"), { double.NAN, double.NAN, double.NAN, double.NAN }, (x) => {
                if (x[0] <= 0 || x[2] <= 0) return bad ();
                double z = (Math.log (x[0]) - x[1]) / x[2];
                if (b (x[3])) return num (norm_cdf (z));
                return num (norm_pdf (z) / (x[0] * x[2]));
            });
            scalar ("LOGNORMDIST", 3, "LOGNORMDIST(x, mean, standard_dev)", _("The cumulative lognormal distribution"), { double.NAN, double.NAN, double.NAN }, (x) => {
                if (x[0] <= 0 || x[2] <= 0) return bad ();
                return num (norm_cdf ((Math.log (x[0]) - x[1]) / x[2]));
            }, "Compatibility");
            scalar ("LOGNORM.INV", 3, "LOGNORM.INV(probability, mean, standard_dev)", _("Inverse of the lognormal distribution"), { double.NAN, double.NAN, double.NAN }, (x) => {
                if (x[0] <= 0 || x[0] >= 1 || x[2] <= 0) return bad ();
                return num (Math.exp (x[1] + x[2] * norm_inv (x[0])));
            });
            Functions.alias ("LOGINV", "LOGNORM.INV");
            scalar ("WEIBULL.DIST", 4, "WEIBULL.DIST(x, alpha, beta, cumulative)", _("The Weibull distribution"), { double.NAN, double.NAN, double.NAN, double.NAN }, (x) => {
                double al = x[1], be = x[2];
                if (x[0] < 0 || al <= 0 || be <= 0) return bad ();
                double t = Math.pow (x[0] / be, al);
                if (b (x[3])) return num (1 - Math.exp (-t));
                return num (al / Math.pow (be, al) * Math.pow (x[0], al - 1) * Math.exp (-t));
            });
            Functions.alias ("WEIBULL", "WEIBULL.DIST");
            scalar ("PHI", 1, "PHI(x)", _("Density of the standard normal distribution"), { double.NAN }, (x) => num (norm_pdf (x[0])));
            scalar ("GAUSS", 1, "GAUSS(z)", _("Probability between the mean and z standard deviations"), { double.NAN }, (x) => num (norm_cdf (x[0]) - 0.5));
            scalar ("FISHER", 1, "FISHER(x)", _("The Fisher transformation"), { double.NAN }, (x) => {
                if (x[0] <= -1 || x[0] >= 1) return bad ();
                return num (0.5 * Math.log ((1 + x[0]) / (1 - x[0])));
            });
            scalar ("FISHERINV", 1, "FISHERINV(y)", _("Inverse of the Fisher transformation"), { double.NAN }, (x) => num (Math.tanh (x[0])));
        }

        private static void register_discrete () {
            scalar ("HYPGEOM.DIST", 5, "HYPGEOM.DIST(sample_s, number_sample, population_s, number_pop, cumulative)", _("The hypergeometric distribution"), { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN }, (x) => {
                double k = Math.trunc (x[0]), n = Math.trunc (x[1]), K = Math.trunc (x[2]), N = Math.trunc (x[3]);
                if (k < 0 || k > n || k > K || n <= 0 || n > N || K <= 0 || K > N || N <= 0 || k < n - N + K) return bad ();
                if (!b (x[4])) return num (hypgeom_pmf (k, n, K, N));
                double s = 0;
                for (double i = double.max (0, n - N + K); i <= k; i++) s += hypgeom_pmf (i, n, K, N);
                return num (double.min (s, 1));
            });
            scalar ("HYPGEOMDIST", 4, "HYPGEOMDIST(sample_s, number_sample, population_s, number_pop)", _("The hypergeometric probability"), { double.NAN, double.NAN, double.NAN, double.NAN }, (x) => {
                double k = Math.trunc (x[0]), n = Math.trunc (x[1]), K = Math.trunc (x[2]), N = Math.trunc (x[3]);
                if (k < 0 || k > n || k > K || n <= 0 || n > N || K <= 0 || K > N || N <= 0 || k < n - N + K) return bad ();
                return num (hypgeom_pmf (k, n, K, N));
            }, "Compatibility");
            scalar ("NEGBINOM.DIST", 4, "NEGBINOM.DIST(number_f, number_s, probability_s, cumulative)", _("The negative binomial distribution"), { double.NAN, double.NAN, double.NAN, double.NAN }, (x) => {
                double f = Math.trunc (x[0]), s = Math.trunc (x[1]), p = x[2];
                if (f < 0 || s < 1 || p < 0 || p > 1) return bad ();
                if (b (x[3])) return num (betai (s, f + 1, p));
                return num (Math.exp (ln_choose (f + s - 1, s - 1) + s * Math.log (p) + f * Math.log (1 - p)));
            });
            scalar ("NEGBINOMDIST", 3, "NEGBINOMDIST(number_f, number_s, probability_s)", _("The negative binomial probability"), { double.NAN, double.NAN, double.NAN }, (x) => {
                double f = Math.trunc (x[0]), s = Math.trunc (x[1]), p = x[2];
                if (f < 0 || s < 1 || p < 0 || p > 1) return bad ();
                return num (Math.exp (ln_choose (f + s - 1, s - 1) + s * Math.log (p) + f * Math.log (1 - p)));
            }, "Compatibility");
            add ("BINOM.DIST.RANGE", 3, 4, "BINOM.DIST.RANGE(trials, probability_s, number_s, [number_s2])", _("Probability of a trial result range"), (ev, a) => {
                Value[] vals = { ev.eval (a[0]), ev.eval (a[1]), ev.eval (a[2]) };
                vals += a.length > 3 && a[3].kind != NodeKind.MISSING ? ev.eval (a[3]) : vals[2];
                return lift (ev, vals, (x) => {
                    double n = Math.trunc (x[0]), p = x[1], s1 = Math.trunc (x[2]), s2 = Math.trunc (x[3]);
                    if (n < 0 || p < 0 || p > 1 || s1 < 0 || s1 > n || s2 < s1 || s2 > n) return bad ();
                    double sum = 0;
                    for (double k = s1; k <= s2; k++) sum += binom_pmf (k, n, p);
                    return num (sum);
                });
            });
            scalar ("BINOM.INV", 3, "BINOM.INV(trials, probability_s, alpha)", _("Smallest value whose cumulative binomial is at least alpha"), { double.NAN, double.NAN, double.NAN }, (x) => {
                double n = Math.trunc (x[0]), p = x[1], al = x[2];
                if (n < 0 || p < 0 || p > 1 || al < 0 || al > 1) return bad ();
                double sum = 0;
                for (double k = 0; k <= n; k++) {
                    sum += binom_pmf (k, n, p);
                    if (sum >= al * (1 - 1e-14)) return num (k);
                }
                return num (n);
            });
            Functions.alias ("CRITBINOM", "BINOM.INV");
            scalar ("PERMUTATIONA", 2, "PERMUTATIONA(number, number_chosen)", _("Permutations with repetitions"), { double.NAN, double.NAN }, (x) => {
                double n = Math.trunc (x[0]), k = Math.trunc (x[1]);
                if (n < 0 || k < 0) return bad ();
                return num (Math.pow (n, k));
            });
        }

        private static void register_misc () {
            add ("KURT", 1, -1, "KURT(number1, [number2], ...)", _("Kurtosis of a data set"), (ev, a) => {
                var l = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, l);
                if (e != null) return e;
                int n = l.size;
                if (n < 4) return Value.err (ErrorKind.DIV0);
                double m = mean_of (l), sd = Math.sqrt (var_of (l));
                if (sd == 0) return Value.err (ErrorKind.DIV0);
                double s = 0;
                foreach (var d in l) s += Math.pow ((d - m) / sd, 4);
                return num ((double) n * (n + 1) / ((n - 1.0) * (n - 2) * (n - 3)) * s - 3.0 * (n - 1) * (n - 1) / ((n - 2.0) * (n - 3)));
            });
            add ("SKEW", 1, -1, "SKEW(number1, [number2], ...)", _("Skewness of a sample"), (ev, a) => {
                var l = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, l);
                if (e != null) return e;
                int n = l.size;
                if (n < 3) return Value.err (ErrorKind.DIV0);
                double m = mean_of (l), sd = Math.sqrt (var_of (l));
                if (sd == 0) return Value.err (ErrorKind.DIV0);
                double s = 0;
                foreach (var d in l) s += Math.pow ((d - m) / sd, 3);
                return num ((double) n / ((n - 1.0) * (n - 2)) * s);
            });
            add ("SKEW.P", 1, -1, "SKEW.P(number1, [number2], ...)", _("Skewness of a population"), (ev, a) => {
                var l = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, l);
                if (e != null) return e;
                int n = l.size;
                if (n < 1) return Value.err (ErrorKind.DIV0);
                double m = mean_of (l), ss = 0;
                foreach (var d in l) ss += (d - m) * (d - m);
                double sd = Math.sqrt (ss / n);
                if (sd == 0) return Value.err (ErrorKind.DIV0);
                double s = 0;
                foreach (var d in l) s += Math.pow ((d - m) / sd, 3);
                return num (s / n);
            });
            add ("STDEVPA", 1, -1, "STDEVPA(value1, [value2], ...)", _("Standard deviation of a population, counting text and logicals"), (ev, a) => variance_a (ev, a, false, true));
            add ("VARA", 1, -1, "VARA(value1, [value2], ...)", _("Variance of a sample, counting text and logicals"), (ev, a) => variance_a (ev, a, true, false));
            add ("VARPA", 1, -1, "VARPA(value1, [value2], ...)", _("Variance of a population, counting text and logicals"), (ev, a) => variance_a (ev, a, false, false));
            add ("TRIMMEAN", 2, 2, "TRIMMEAN(array, percent)", _("Mean of the interior of a data set"), (ev, a) => {
                Value? e = null;
                var l = list_of (ev, a[0], out e);
                if (e != null) return e;
                double pc;
                if ((e = ev.arg_number (a[1], out pc)) != null) return e;
                if (pc < 0 || pc >= 1 || l.size == 0) return bad ();
                l.sort ((x, y) => x < y ? -1 : (x > y ? 1 : 0));
                int cut = (int) Math.floor (l.size * pc / 2);
                double s = 0;
                for (int i = cut; i < l.size - cut; i++) s += l[i];
                return num (s / (l.size - 2 * cut));
            });
            add ("MODE.MULT", 1, -1, "MODE.MULT(number1, [number2], ...)", _("Vertical array of the most frequent values"), (ev, a) => {
                var l = new Gee.ArrayList<double?> ();
                var e = ev.numbers (a, l);
                if (e != null) return e;
                var counts = new Gee.HashMap<string, int> ();
                var order = new Gee.ArrayList<double?> ();
                int best = 1;
                foreach (var d in l) {
                    string k = Value.format_number_general_full (d);
                    if (!counts.has_key (k)) {
                        counts[k] = 0;
                        order.add (d);
                    }
                    counts[k] = counts[k] + 1;
                    best = int.max (best, counts[k]);
                }
                if (best < 2) return Value.err (ErrorKind.NA);
                var modes = new Gee.ArrayList<double?> ();
                foreach (var d in order) if (counts[Value.format_number_general_full (d)] == best) modes.add (d);
                var m = new Value[modes.size, 1];
                for (int i = 0; i < modes.size; i++) m[i, 0] = num (modes[i]);
                return Value.matrix (m);
            });
            add ("PERCENTRANK.EXC", 2, 3, "PERCENTRANK.EXC(array, x, [significance])", _("Rank of a value as a percentage, exclusive"), (ev, a) => percentrank_exc (ev, a));
            add ("PROB", 3, 4, "PROB(x_range, prob_range, lower_limit, [upper_limit])", _("Probability that values are between two limits"), (ev, a) => {
                var xm = ev.to_matrix (ev.eval (a[0]));
                var pm = ev.to_matrix (ev.eval (a[1]));
                int n = xm.length[0] * xm.length[1];
                if (n != pm.length[0] * pm.length[1]) return Value.err (ErrorKind.NA);
                double lo, hi;
                var e = ev.arg_number (a[2], out lo);
                if (e != null) return e;
                hi = lo;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_number (a[3], out hi)) != null) return e;
                double total = 0, s = 0;
                for (int i = 0; i < n; i++) {
                    var x = xm[i / xm.length[1], i % xm.length[1]];
                    var p = pm[i / pm.length[1], i % pm.length[1]];
                    if (x.is_error ()) return x;
                    if (p.is_error ()) return p;
                    if (p.kind != ValueKind.NUMBER || x.kind != ValueKind.NUMBER) continue;
                    if (p.number < 0 || p.number > 1) return bad ();
                    total += p.number;
                    if (x.number >= lo && x.number <= hi) s += p.number;
                }
                if (Math.fabs (total - 1) > 1e-9) return bad ();
                return num (s);
            });
            add ("FREQUENCY", 2, 2, "FREQUENCY(data_array, bins_array)", _("How often values occur within ranges"), (ev, a) => {
                Value? e = null;
                var data = list_of (ev, a[0], out e);
                if (e != null) return e;
                var bins = list_of (ev, a[1], out e);
                if (e != null) return e;
                var sorted_bins = new Gee.ArrayList<double?> ();
                sorted_bins.add_all (bins);
                sorted_bins.sort ((x, y) => x < y ? -1 : (x > y ? 1 : 0));
                var counts = new int[bins.size + 1];
                foreach (var d in data) {
                    int idx = bins.size;
                    double best = double.INFINITY;
                    for (int i = 0; i < bins.size; i++) {
                        if (d <= bins[i] && bins[i] < best) {
                            best = bins[i];
                            idx = i;
                        }
                    }
                    counts[idx]++;
                }
                var m = new Value[bins.size + 1, 1];
                for (int i = 0; i <= bins.size; i++) m[i, 0] = num (counts[i]);
                return Value.matrix (m);
            });
        }

        private static Value percentrank_exc (Evaluator ev, Node[] a) {
            Value? e = null;
            var l = list_of (ev, a[0], out e);
            if (e != null) return e;
            double x;
            if ((e = ev.arg_number (a[1], out x)) != null) return e;
            int sig = 3;
            if (a.length > 2 && a[2].kind != NodeKind.MISSING && (e = ev.arg_int (a[2], out sig)) != null) return e;
            if (sig < 1 || l.size == 0) return bad ();
            l.sort ((p, q) => p < q ? -1 : (p > q ? 1 : 0));
            int n = l.size;
            if (x < l[0] || x > l[n - 1]) return Value.err (ErrorKind.NA);
            double rank = 0;
            for (int i = 0; i < n; i++) {
                if (l[i] == x) {
                    rank = i + 1;
                    break;
                }
                if (i + 1 < n && l[i] < x && x < l[i + 1]) {
                    rank = i + 1 + (x - l[i]) / (l[i + 1] - l[i]);
                    break;
                }
            }
            double r = rank / (n + 1);
            double f = Math.pow (10, sig);
            return num (Math.floor (r * f + 1e-9) / f);
        }

        private static void register_tests () {
            add ("T.TEST", 4, 4, "T.TEST(array1, array2, tails, type)", _("Probability associated with a Student's t-test"), (ev, a) => ttest (ev, a));
            Functions.alias ("TTEST", "T.TEST");
            add ("Z.TEST", 2, 3, "Z.TEST(array, x, [sigma])", _("One-tailed probability of a z-test"), (ev, a) => {
                Value? e = null;
                var l = list_of (ev, a[0], out e);
                if (e != null) return e;
                double x;
                if ((e = ev.arg_number (a[1], out x)) != null) return e;
                if (l.size == 0) return Value.err (ErrorKind.NA);
                double sigma;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING) {
                    if ((e = ev.arg_number (a[2], out sigma)) != null) return e;
                } else {
                    if (l.size < 2) return Value.err (ErrorKind.DIV0);
                    sigma = Math.sqrt (var_of (l));
                }
                if (sigma == 0) return Value.err (ErrorKind.DIV0);
                return num (1 - norm_cdf ((mean_of (l) - x) / (sigma / Math.sqrt (l.size))));
            });
            Functions.alias ("ZTEST", "Z.TEST");
        }

        private static Value ttest (Evaluator ev, Node[] a) {
            double tails_d, type_d;
            var e = ev.arg_number (a[2], out tails_d);
            if (e != null) return e;
            if ((e = ev.arg_number (a[3], out type_d)) != null) return e;
            int tails = (int) Math.trunc (tails_d), type = (int) Math.trunc (type_d);
            if ((tails != 1 && tails != 2) || type < 1 || type > 3) return bad ();
            double t, df;
            if (type == 1) {
                var m1 = ev.to_matrix (ev.eval (a[0]));
                var m2 = ev.to_matrix (ev.eval (a[1]));
                int n = m1.length[0] * m1.length[1];
                if (n != m2.length[0] * m2.length[1]) return Value.err (ErrorKind.NA);
                var diffs = new Gee.ArrayList<double?> ();
                for (int i = 0; i < n; i++) {
                    var x = m1[i / m1.length[1], i % m1.length[1]];
                    var y = m2[i / m2.length[1], i % m2.length[1]];
                    if (x.is_error ()) return x;
                    if (y.is_error ()) return y;
                    if (x.kind == ValueKind.NUMBER && y.kind == ValueKind.NUMBER) diffs.add (x.number - y.number);
                }
                if (diffs.size < 2) return Value.err (ErrorKind.DIV0);
                double sd = Math.sqrt (var_of (diffs));
                if (sd == 0) return Value.err (ErrorKind.DIV0);
                t = mean_of (diffs) / (sd / Math.sqrt (diffs.size));
                df = diffs.size - 1;
            } else {
                Value? e2;
                var l1 = list_of (ev, a[0], out e2);
                if (e2 != null) return e2;
                var l2 = list_of (ev, a[1], out e2);
                if (e2 != null) return e2;
                int n1 = l1.size, n2 = l2.size;
                if (n1 < 2 || n2 < 2) return Value.err (ErrorKind.DIV0);
                double v1 = var_of (l1), v2 = var_of (l2);
                double diff = mean_of (l1) - mean_of (l2);
                if (type == 2) {
                    double sp = ((n1 - 1) * v1 + (n2 - 1) * v2) / (n1 + n2 - 2);
                    if (sp == 0) return Value.err (ErrorKind.DIV0);
                    t = diff / Math.sqrt (sp * (1.0 / n1 + 1.0 / n2));
                    df = n1 + n2 - 2;
                } else {
                    double s1 = v1 / n1, s2 = v2 / n2;
                    if (s1 + s2 == 0) return Value.err (ErrorKind.DIV0);
                    t = diff / Math.sqrt (s1 + s2);
                    df = (s1 + s2) * (s1 + s2) / (s1 * s1 / (n1 - 1) + s2 * s2 / (n2 - 1));
                }
            }
            return num (tails * t_right (Math.fabs (t), df));
        }
    }
}
