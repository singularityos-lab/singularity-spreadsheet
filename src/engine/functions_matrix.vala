namespace Singularity.Apps.Spreadsheet {

    public class MatrixFunctions {
        private static void add (string name, int min, int max, string category, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, category, syntax, summary, (owned) impl);
        }

        public static Value? numeric (Evaluator ev, Value v, out double[,] m) {
            var vm = ev.to_matrix (v);
            int r = vm.length[0], c = vm.length[1];
            m = new double[r, c];
            for (int i = 0; i < r; i++) {
                for (int j = 0; j < c; j++) {
                    var x = vm[i, j];
                    if (x.is_error ()) return x;
                    if (x.kind != ValueKind.NUMBER) return Value.err (ErrorKind.VALUE);
                    m[i, j] = x.number;
                }
            }
            return null;
        }

        private static Value to_value (double[,] m) {
            int r = m.length[0], c = m.length[1];
            var out_m = new Value[r, c];
            for (int i = 0; i < r; i++) for (int j = 0; j < c; j++) out_m[i, j] = Value.num (m[i, j]);
            return Value.matrix (out_m);
        }

        public static bool invert (double[,] a, out double[,] inv, out double det) {
            int n = a.length[0];
            var m = new double[n, 2 * n];
            for (int i = 0; i < n; i++) {
                for (int j = 0; j < n; j++) m[i, j] = a[i, j];
                m[i, n + i] = 1;
            }
            det = 1;
            inv = new double[n, n];
            for (int col = 0; col < n; col++) {
                int piv = col;
                for (int r = col + 1; r < n; r++) if (Math.fabs (m[r, col]) > Math.fabs (m[piv, col])) piv = r;
                if (m[piv, col] == 0) {
                    det = 0;
                    return false;
                }
                if (piv != col) {
                    for (int j = 0; j < 2 * n; j++) {
                        double t = m[col, j];
                        m[col, j] = m[piv, j];
                        m[piv, j] = t;
                    }
                    det = -det;
                }
                double p = m[col, col];
                det *= p;
                for (int j = 0; j < 2 * n; j++) m[col, j] /= p;
                for (int r = 0; r < n; r++) {
                    if (r == col || m[r, col] == 0) continue;
                    double f = m[r, col];
                    for (int j = 0; j < 2 * n; j++) m[r, j] -= f * m[col, j];
                }
            }
            for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) inv[i, j] = m[i, n + j];
            return true;
        }

        public static void register () {
            add ("MMULT", 2, 2, "Math", "MMULT(array1, array2)", _("The matrix product of two arrays"), (ev, a) => {
                double[,] x, y;
                var e = numeric (ev, ev.eval (a[0]), out x);
                if (e != null) return Value.err (ErrorKind.VALUE);
                e = numeric (ev, ev.eval (a[1]), out y);
                if (e != null) return Value.err (ErrorKind.VALUE);
                if (x.length[1] != y.length[0]) return Value.err (ErrorKind.VALUE);
                var r = new double[x.length[0], y.length[1]];
                for (int i = 0; i < x.length[0]; i++) {
                    for (int j = 0; j < y.length[1]; j++) {
                        double s = 0;
                        for (int k = 0; k < x.length[1]; k++) s += x[i, k] * y[k, j];
                        r[i, j] = s;
                    }
                }
                return to_value (r);
            });
            add ("MINVERSE", 1, 1, "Math", "MINVERSE(array)", _("The inverse matrix of an array"), (ev, a) => {
                double[,] x;
                var e = numeric (ev, ev.eval (a[0]), out x);
                if (e != null) return Value.err (ErrorKind.VALUE);
                if (x.length[0] != x.length[1]) return Value.err (ErrorKind.VALUE);
                double[,] inv;
                double det;
                if (!invert (x, out inv, out det) || Math.fabs (det) < 1e-300) return Value.err (ErrorKind.NUM);
                return to_value (inv);
            });
            add ("MDETERM", 1, 1, "Math", "MDETERM(array)", _("The determinant of a matrix"), (ev, a) => {
                double[,] x;
                var e = numeric (ev, ev.eval (a[0]), out x);
                if (e != null) return Value.err (ErrorKind.VALUE);
                if (x.length[0] != x.length[1]) return Value.err (ErrorKind.VALUE);
                double[,] inv;
                double det;
                invert (x, out inv, out det);
                return Value.num (det);
            });
            add ("MUNIT", 1, 1, "Math", "MUNIT(dimension)", _("The unit matrix of a dimension"), (ev, a) => {
                int n;
                var e = ev.arg_int (a[0], out n);
                if (e != null) return e;
                if (n < 1 || n > 2048) return Value.err (ErrorKind.VALUE);
                var r = new double[n, n];
                for (int i = 0; i < n; i++) r[i, i] = 1;
                return to_value (r);
            });
            add ("LINEST", 1, 4, "Statistical", "LINEST(known_y, [known_x], [const], [stats])", _("Parameters of a linear trend"), (ev, a) => estimate (ev, a, false));
            add ("LOGEST", 1, 4, "Statistical", "LOGEST(known_y, [known_x], [const], [stats])", _("Parameters of an exponential trend"), (ev, a) => estimate (ev, a, true));
            add ("TREND", 1, 4, "Statistical", "TREND(known_y, [known_x], [new_x], [const])", _("Values along a linear trend"), (ev, a) => project (ev, a, false));
            add ("GROWTH", 1, 4, "Statistical", "GROWTH(known_y, [known_x], [new_x], [const])", _("Values along an exponential trend"), (ev, a) => project (ev, a, true));
            Ets.register ();
        }

        private class Fit {
            public double[] coef;
            public double[] se;
            public bool[] dropped;
            public double intercept;
            public double se_b;
            public double r2;
            public double sey;
            public double f;
            public double df;
            public double ssreg;
            public double ssresid;
            public int k;
            public int n;
        }

        private static Value? design (Evaluator ev, Node[] a, bool exponential, out double[] y, out double[,] x, out bool vertical) {
            y = {};
            x = new double[0, 0];
            vertical = true;
            double[,] ym;
            var e = numeric (ev, ev.eval (a[0]), out ym);
            if (e != null) return e;
            int yr = ym.length[0], yc = ym.length[1];
            int n = yr * yc;
            y = new double[n];
            for (int i = 0; i < n; i++) {
                double v = ym[i / yc, i % yc];
                if (exponential) {
                    if (v <= 0) return Value.err (ErrorKind.NUM);
                    v = Math.log (v);
                }
                y[i] = v;
            }
            vertical = yc == 1;
            if (a.length > 1 && a[1].kind != NodeKind.MISSING) {
                double[,] xm;
                e = numeric (ev, ev.eval (a[1]), out xm);
                if (e != null) return e;
                int xr = xm.length[0], xc = xm.length[1];
                if (yr == 1 && yc == 1) return Value.err (ErrorKind.REF);
                if (yc == 1 || (yr != 1 && yc != 1)) {
                    if (yr != 1 && yc != 1) {
                        if (xr * xc != n) return Value.err (ErrorKind.REF);
                        x = new double[n, 1];
                        for (int i = 0; i < n; i++) x[i, 0] = xm[i / xc, i % xc];
                        return null;
                    }
                    if (xr == n) {
                        x = new double[n, xc];
                        for (int i = 0; i < n; i++) for (int j = 0; j < xc; j++) x[i, j] = xm[i, j];
                    } else if (xr * xc == n) {
                        x = new double[n, 1];
                        for (int i = 0; i < n; i++) x[i, 0] = xm[i / xc, i % xc];
                    } else {
                        return Value.err (ErrorKind.REF);
                    }
                } else {
                    if (xc == n) {
                        x = new double[n, xr];
                        for (int i = 0; i < n; i++) for (int j = 0; j < xr; j++) x[i, j] = xm[j, i];
                    } else if (xr * xc == n) {
                        x = new double[n, 1];
                        for (int i = 0; i < n; i++) x[i, 0] = xm[i / xc, i % xc];
                    } else {
                        return Value.err (ErrorKind.REF);
                    }
                }
            } else {
                x = new double[n, 1];
                for (int i = 0; i < n; i++) x[i, 0] = i + 1;
            }
            return null;
        }

        private static Fit? regress (double[] y, double[,] x, bool with_const) {
            int n = y.length, k = x.length[1];
            int p = k + (with_const ? 1 : 0);
            var fit = new Fit ();
            fit.n = n;
            fit.k = k;
            fit.coef = new double[k];
            fit.se = new double[k];
            fit.dropped = new bool[k];
            double ymean = 0;
            foreach (double v in y) ymean += v;
            ymean /= n;
            var cols = new double[p, n];
            for (int i = 0; i < n; i++) {
                for (int j = 0; j < k; j++) cols[j, i] = x[i, j];
                if (with_const) cols[k, i] = 1;
            }
            if (with_const) {
                for (int j = 0; j < k; j++) {
                    double m = 0;
                    for (int i = 0; i < n; i++) m += x[i, j];
                    m /= n;
                    double spread = 0;
                    for (int i = 0; i < n; i++) spread += (x[i, j] - m) * (x[i, j] - m);
                    if (spread <= 1e-24 * double.max (1, m * m) * n) fit.dropped[j] = true;
                }
            }
            var active = new Gee.ArrayList<int> ();
            for (int j = 0; j < p; j++) {
                if (j < k && fit.dropped[j]) continue;
                active.add (j);
                int q = active.size;
                var xtx = new double[q, q];
                for (int r = 0; r < q; r++) for (int c = 0; c < q; c++) {
                    double s = 0;
                    for (int i = 0; i < n; i++) s += cols[active[r], i] * cols[active[c], i];
                    xtx[r, c] = s;
                }
                double[,] tmp;
                double det;
                double scale = 1;
                for (int r = 0; r < q; r++) scale *= double.max (xtx[r, r], 1e-300);
                if (!invert (xtx, out tmp, out det) || Math.fabs (det) <= 1e-13 * scale) {
                    active.remove_at (q - 1);
                    if (j < k) fit.dropped[j] = true;
                }
            }
            int q = active.size;
            var xtx2 = new double[q, q];
            var xty = new double[q];
            for (int r = 0; r < q; r++) {
                for (int c = 0; c < q; c++) {
                    double s = 0;
                    for (int i = 0; i < n; i++) s += cols[active[r], i] * cols[active[c], i];
                    xtx2[r, c] = s;
                }
                double s2 = 0;
                for (int i = 0; i < n; i++) s2 += cols[active[r], i] * y[i];
                xty[r] = s2;
            }
            double[,] inv = new double[0, 0];
            double d;
            if (q > 0 && !invert (xtx2, out inv, out d)) return null;
            var beta = new double[q];
            for (int r = 0; r < q; r++) {
                double s = 0;
                for (int c = 0; c < q; c++) s += inv[r, c] * xty[c];
                beta[r] = s;
            }
            double ssresid = 0;
            for (int i = 0; i < n; i++) {
                double pred = 0;
                for (int r = 0; r < q; r++) pred += beta[r] * cols[active[r], i];
                ssresid += (y[i] - pred) * (y[i] - pred);
            }
            double sstot = 0;
            for (int i = 0; i < n; i++) sstot += with_const ? (y[i] - ymean) * (y[i] - ymean) : y[i] * y[i];
            int used_x = 0;
            for (int r = 0; r < q; r++) if (active[r] < k) used_x++;
            fit.df = n - used_x - (with_const ? 1 : 0);
            fit.ssresid = ssresid;
            fit.ssreg = sstot - ssresid;
            fit.r2 = sstot == 0 ? 1 : fit.ssreg / sstot;
            double sigma2 = fit.df > 0 ? ssresid / fit.df : 0;
            fit.sey = Math.sqrt (sigma2);
            fit.f = fit.df > 0 && ssresid > 0 && used_x > 0 ? (fit.ssreg / used_x) / sigma2 : double.NAN;
            for (int r = 0; r < q; r++) {
                int j = active[r];
                double se = Math.sqrt (double.max (0, inv[r, r] * sigma2));
                if (j < k) {
                    fit.coef[j] = beta[r];
                    fit.se[j] = se;
                } else {
                    fit.intercept = beta[r];
                    fit.se_b = se;
                }
            }
            return fit;
        }

        private static Value estimate (Evaluator ev, Node[] a, bool exponential) {
            double[] y;
            double[,] x;
            bool vertical;
            var e = design (ev, a, exponential, out y, out x, out vertical);
            if (e != null) return e;
            bool with_const = true, stats = false;
            if (a.length > 2 && a[2].kind != NodeKind.MISSING && (e = ev.arg_bool (a[2], out with_const)) != null) return e;
            if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_bool (a[3], out stats)) != null) return e;
            var fit = regress (y, x, with_const);
            if (fit == null) return Value.err (ErrorKind.NUM);
            int k = fit.k;
            int rows = stats ? 5 : 1;
            var m = new Value[rows, k + 1];
            for (int i = 0; i < rows; i++) for (int j = 0; j <= k; j++) m[i, j] = Value.err (ErrorKind.NA);
            for (int j = 0; j < k; j++) {
                double c = fit.coef[k - 1 - j];
                m[0, j] = Value.num (exponential ? Math.exp (c) : c);
                if (stats) m[1, j] = Value.num (fit.se[k - 1 - j]);
            }
            m[0, k] = Value.num (exponential ? Math.exp (with_const ? fit.intercept : 0) : (with_const ? fit.intercept : 0));
            if (stats) {
                m[1, k] = with_const ? Value.num (fit.se_b) : Value.err (ErrorKind.NA);
                m[2, 0] = Value.num (fit.r2);
                if (k >= 1) m[2, 1] = Value.num (fit.sey);
                m[3, 0] = fit.f.is_nan () ? Value.err (ErrorKind.NUM) : Value.num (fit.f);
                if (k >= 1) m[3, 1] = Value.num (fit.df);
                m[4, 0] = Value.num (fit.ssreg);
                if (k >= 1) m[4, 1] = Value.num (fit.ssresid);
            }
            return Value.matrix (m);
        }

        private static Value project (Evaluator ev, Node[] a, bool exponential) {
            double[] y;
            double[,] x;
            bool vertical;
            var e = design (ev, a, exponential, out y, out x, out vertical);
            if (e != null) return e;
            bool with_const = true;
            if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_bool (a[3], out with_const)) != null) return e;
            var fit = regress (y, x, with_const);
            if (fit == null) return Value.err (ErrorKind.NUM);
            int k = fit.k;
            double[,] nx;
            if (a.length > 2 && a[2].kind != NodeKind.MISSING) {
                e = numeric (ev, ev.eval (a[2]), out nx);
                if (e != null) return e;
            } else if (a.length > 1 && a[1].kind != NodeKind.MISSING) {
                e = numeric (ev, ev.eval (a[1]), out nx);
                if (e != null) return e;
            } else {
                int n = y.length;
                var ym = ev.to_matrix (ev.eval (a[0]));
                nx = new double[ym.length[0], ym.length[1]];
                for (int i = 0; i < n; i++) nx[i / ym.length[1], i % ym.length[1]] = i + 1;
            }
            int r = nx.length[0], c = nx.length[1];
            Value[,] out_m;
            if (k == 1) {
                out_m = new Value[r, c];
                for (int i = 0; i < r; i++) for (int j = 0; j < c; j++) {
                    double v = fit.coef[0] * nx[i, j] + (with_const ? fit.intercept : 0);
                    out_m[i, j] = Value.num (exponential ? Math.exp (v) : v);
                }
                return Value.matrix (out_m);
            }
            bool by_rows = c == k;
            int count = by_rows ? r : c;
            if (!by_rows && r != k) return Value.err (ErrorKind.REF);
            out_m = by_rows ? new Value[count, 1] : new Value[1, count];
            for (int i = 0; i < count; i++) {
                double v = with_const ? fit.intercept : 0;
                for (int j = 0; j < k; j++) v += fit.coef[j] * (by_rows ? nx[i, j] : nx[j, i]);
                if (by_rows) out_m[i, 0] = Value.num (exponential ? Math.exp (v) : v);
                else out_m[0, i] = Value.num (exponential ? Math.exp (v) : v);
            }
            return Value.matrix (out_m);
        }
    }

    public class Ets {
        public double alpha;
        public double beta;
        public double gamma;
        public int period;
        public double step;
        public double t0;
        public double[] y;
        public double sse;
        public double mae;
        public double smape;
        public double level;
        public double trend;
        public double[] season;

        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Statistical", syntax, summary, (owned) impl);
        }

        public static Value? prepare (Evaluator ev, Node values, Node timeline, int completion, int aggregation, out double[] y, out double step, out double t0) {
            y = {};
            step = 1;
            t0 = 0;
            var vm = ev.to_matrix (ev.eval (values));
            var tm = ev.to_matrix (ev.eval (timeline));
            int n = vm.length[0] * vm.length[1];
            if (n != tm.length[0] * tm.length[1]) return Value.err (ErrorKind.NA);
            var ts = new double[n];
            var vs = new double[n];
            var has = new bool[n];
            for (int i = 0; i < n; i++) {
                var t = tm[i / tm.length[1], i % tm.length[1]];
                var v = vm[i / vm.length[1], i % vm.length[1]];
                if (t.is_error ()) return t;
                if (v.is_error ()) return v;
                if (t.kind != ValueKind.NUMBER) return Value.err (ErrorKind.VALUE);
                ts[i] = t.number;
                has[i] = v.kind == ValueKind.NUMBER;
                vs[i] = v.number;
            }
            if (n < 3) return Value.err (ErrorKind.NUM);
            var order = new Gee.ArrayList<int> ();
            for (int i = 0; i < n; i++) order.add (i);
            order.sort ((a, b) => ts[a] < ts[b] ? -1 : (ts[a] > ts[b] ? 1 : 0));
            double min_step = double.INFINITY;
            for (int i = 1; i < n; i++) {
                double d = ts[order[i]] - ts[order[i - 1]];
                if (d > 0) min_step = double.min (min_step, d);
            }
            if (min_step.is_infinity () != 0) return Value.err (ErrorKind.NUM);
            step = min_step;
            t0 = ts[order[0]];
            int len = (int) Math.round ((ts[order[n - 1]] - t0) / step) + 1;
            if (len > 100000) return Value.err (ErrorKind.NUM);
            var buckets = new Gee.ArrayList<Gee.ArrayList<double?>> ();
            for (int i = 0; i < len; i++) buckets.add (new Gee.ArrayList<double?> ());
            foreach (int i in order) {
                double pos = (ts[i] - t0) / step;
                if (Math.fabs (pos - Math.round (pos)) > 1e-6) return Value.err (ErrorKind.NUM);
                if (has[i]) buckets[(int) Math.round (pos)].add (vs[i]);
            }
            var out_y = new double[len];
            var known = new bool[len];
            int missing = 0;
            for (int i = 0; i < len; i++) {
                var bk = buckets[i];
                if (bk.size == 0) {
                    missing++;
                    continue;
                }
                known[i] = true;
                out_y[i] = aggregate (bk, aggregation);
            }
            if (missing > len * 0.3 + 1e-9) return Value.err (ErrorKind.NUM);
            for (int i = 0; i < len; i++) {
                if (known[i]) continue;
                if (completion == 0) {
                    out_y[i] = 0;
                    continue;
                }
                int lo = i - 1, hi = i + 1;
                while (lo >= 0 && !known[lo]) lo--;
                while (hi < len && !known[hi]) hi++;
                if (lo < 0) out_y[i] = out_y[hi];
                else if (hi >= len) out_y[i] = out_y[lo];
                else out_y[i] = out_y[lo] + (out_y[hi] - out_y[lo]) * (i - lo) / (double) (hi - lo);
            }
            y = out_y;
            return null;
        }

        private static double aggregate (Gee.ArrayList<double?> l, int mode) {
            double s = 0, mn = double.INFINITY, mx = -double.INFINITY;
            foreach (var d in l) {
                s += d;
                mn = double.min (mn, d);
                mx = double.max (mx, d);
            }
            switch (mode) {
                case 2:
                case 3: return l.size;
                case 4: return mx;
                case 5:
                    var c = new Gee.ArrayList<double?> ();
                    c.add_all (l);
                    c.sort ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
                    int n = c.size;
                    return n % 2 == 1 ? c[n / 2] : (c[n / 2 - 1] + c[n / 2]) / 2;
                case 6: return mn;
                case 7: return s;
                default: return s / l.size;
            }
        }

        public static int detect (double[] y) {
            int n = y.length;
            if (n < 6) return 1;
            double sx = 0, sy = 0, sxx = 0, sxy = 0;
            for (int i = 0; i < n; i++) {
                sx += i;
                sy += y[i];
                sxx += (double) i * i;
                sxy += i * y[i];
            }
            double slope = (n * sxy - sx * sy) / (n * sxx - sx * sx);
            double icpt = (sy - slope * sx) / n;
            var r = new double[n];
            double mean = 0;
            for (int i = 0; i < n; i++) {
                r[i] = y[i] - (icpt + slope * i);
                mean += r[i];
            }
            mean /= n;
            double var0 = 0;
            for (int i = 0; i < n; i++) var0 += (r[i] - mean) * (r[i] - mean);
            if (var0 <= 1e-12) return 1;
            int maxlag = int.min (n / 2, 8760);
            var acf = new double[maxlag + 2];
            for (int lag = 1; lag <= maxlag + 1 && lag < n; lag++) {
                double s = 0;
                for (int i = lag; i < n; i++) s += (r[i] - mean) * (r[i - lag] - mean);
                acf[lag] = s / var0;
            }
            int best = 1;
            double best_v = 0.3;
            for (int lag = 2; lag <= maxlag; lag++) {
                bool peak = acf[lag] >= acf[lag - 1] && (lag + 1 >= acf.length || acf[lag] >= acf[lag + 1]);
                if (peak && acf[lag] > best_v + 1e-9) {
                    best_v = acf[lag];
                    best = lag;
                }
            }
            return best;
        }

        private double run (double a, double b, double g, bool keep) {
            int n = y.length;
            int m = period;
            double l, t;
            var s = new double[int.max (m, 1)];
            if (m > 1 && n >= 2 * m) {
                double m1 = 0, m2 = 0;
                for (int i = 0; i < m; i++) {
                    m1 += y[i];
                    m2 += y[i + m];
                }
                m1 /= m;
                m2 /= m;
                t = (m2 - m1) / m;
                for (int i = 0; i < m; i++) s[i] = y[i] - (m1 + (i - (m - 1) / 2.0) * t);
                l = y[0] - s[0] - t;
            } else {
                t = n > 1 ? y[1] - y[0] : 0;
                l = y[0] - t;
            }
            double err2 = 0, abs_err = 0, sm = 0;
            int count = 0;
            for (int i = 0; i < n; i++) {
                double si = m > 1 ? s[i % m] : 0;
                double pred = l + t + si;
                double e = y[i] - pred;
                if (i > 0) {
                    err2 += e * e;
                    abs_err += Math.fabs (e);
                    double den = Math.fabs (y[i]) + Math.fabs (pred);
                    if (den > 0) sm += 2 * Math.fabs (e) / den;
                    count++;
                }
                double nl = a * (y[i] - si) + (1 - a) * (l + t);
                double nt = b * (nl - l) + (1 - b) * t;
                if (m > 1) s[i % m] = g * (y[i] - nl) + (1 - g) * si;
                l = nl;
                t = nt;
            }
            if (keep) {
                level = l;
                trend = t;
                season = s;
                sse = err2;
                mae = count > 0 ? abs_err / count : 0;
                smape = count > 0 ? sm / count : 0;
            }
            return err2;
        }

        public void fit () {
            double best = double.INFINITY;
            double ba = 0.5, bb = 0.1, bg = 0.1;
            double[] grid = { 0.001, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 0.9, 0.999 };
            foreach (double a in grid) foreach (double b in grid) {
                if (b > a) continue;
                double[] gg = period > 1 ? grid : new double[] { 0 };
                foreach (double g in gg) {
                    double v = run (a, b, g, false);
                    if (v < best) {
                        best = v;
                        ba = a;
                        bb = b;
                        bg = g;
                    }
                }
            }
            double stepv = 0.05;
            for (int it = 0; it < 60 && stepv > 1e-5; it++) {
                bool improved = false;
                double[] cand = { ba + stepv, ba - stepv };
                foreach (double c in cand) {
                    if (c < 0.001 || c > 0.999) continue;
                    double v = run (c, double.min (bb, c), bg, false);
                    if (v < best) {
                        best = v;
                        ba = c;
                        bb = double.min (bb, c);
                        improved = true;
                    }
                }
                double[] candb = { bb + stepv, bb - stepv };
                foreach (double c in candb) {
                    if (c < 0.001 || c > ba) continue;
                    double v = run (ba, c, bg, false);
                    if (v < best) {
                        best = v;
                        bb = c;
                        improved = true;
                    }
                }
                if (period > 1) {
                    double[] candg = { bg + stepv, bg - stepv };
                    foreach (double c in candg) {
                        if (c < 0.001 || c > 0.999) continue;
                        double v = run (ba, bb, c, false);
                        if (v < best) {
                            best = v;
                            bg = c;
                            improved = true;
                        }
                    }
                }
                if (!improved) stepv /= 2;
            }
            alpha = ba;
            beta = bb;
            gamma = period > 1 ? bg : 0;
            run (alpha, beta, gamma, true);
        }

        private double ahead (int hh) {
            double sv = period > 1 ? season[(y.length + hh - 1) % period] : 0;
            return level + hh * trend + sv;
        }

        public double forecast_at (double h) {
            int n = y.length;
            int lo = (int) Math.floor (h);
            if (lo == h) return ahead (lo);
            double f1 = lo < 1 ? y[n - 1] : ahead (lo);
            return f1 + (ahead (lo + 1) - f1) * (h - lo);
        }

        public double confint (double h, double conf) {
            double sigma2 = y.length > 1 ? sse / (y.length - 1) : 0;
            double v = 1;
            for (int j = 1; j < (int) Math.ceil (h); j++) {
                double c = alpha * (1 + j * beta) + (period > 1 && j % period == 0 ? gamma * (1 - alpha) : 0);
                v += c * c;
            }
            return DistributionFunctions.norm_inv ((1 + conf) / 2) * Math.sqrt (sigma2 * v);
        }

        private static Value? build (Evaluator ev, Node values, Node timeline, Node[] a, int season_at, int completion_at, int aggregation_at, out Ets model) {
            model = null;
            int seasonality = 1, completion = 1, aggregation = 1;
            Value? e = null;
            if (a.length > season_at && a[season_at].kind != NodeKind.MISSING && (e = ev.arg_int (a[season_at], out seasonality)) != null) return e;
            if (a.length > completion_at && a[completion_at].kind != NodeKind.MISSING && (e = ev.arg_int (a[completion_at], out completion)) != null) return e;
            if (a.length > aggregation_at && a[aggregation_at].kind != NodeKind.MISSING && (e = ev.arg_int (a[aggregation_at], out aggregation)) != null) return e;
            if (seasonality < 0 || seasonality > 8760 || completion < 0 || completion > 1 || aggregation < 1 || aggregation > 7) return Value.err (ErrorKind.NUM);
            double[] y;
            double step, t0;
            e = prepare (ev, values, timeline, completion, aggregation, out y, out step, out t0);
            if (e != null) return e;
            var m = new Ets ();
            m.y = y;
            m.step = step;
            m.t0 = t0;
            m.period = seasonality == 1 ? detect (y) : (seasonality == 0 ? 1 : seasonality);
            if (m.period > y.length / 2 && m.period > 1) return Value.err (ErrorKind.NUM);
            m.fit ();
            model = m;
            return null;
        }

        private static Value per_target (Evaluator ev, Node target, Ets m, bool conf, double level) {
            var tv = ev.eval (target);
            var tmx = ev.to_matrix (tv.is_multi () ? tv : ev.deref (tv));
            int r = tmx.length[0], c = tmx.length[1];
            var out_m = new Value[r, c];
            double last = m.t0 + (m.y.length - 1) * m.step;
            for (int i = 0; i < r; i++) {
                for (int j = 0; j < c; j++) {
                    double t;
                    var e = Evaluator.to_number (tmx[i, j], out t);
                    if (e != null) {
                        out_m[i, j] = e;
                        continue;
                    }
                    double h = (t - last) / m.step;
                    if (h < 0) {
                        out_m[i, j] = Value.err (ErrorKind.NUM);
                        continue;
                    }
                    out_m[i, j] = Value.num (conf ? m.confint (double.max (h, 1), level) : m.forecast_at (h));
                }
            }
            if (r == 1 && c == 1) return out_m[0, 0];
            return Value.matrix (out_m);
        }

        public static void register () {
            add ("FORECAST.ETS", 3, 6, "FORECAST.ETS(target_date, values, timeline, [seasonality], [data_completion], [aggregation])", _("Forecast with exponential triple smoothing"), (ev, a) => {
                Ets m;
                var e = build (ev, a[1], a[2], a, 3, 4, 5, out m);
                if (e != null) return e;
                return per_target (ev, a[0], m, false, 0);
            });
            add ("FORECAST.ETS.CONFINT", 3, 7, "FORECAST.ETS.CONFINT(target_date, values, timeline, [confidence_level], [seasonality], [data_completion], [aggregation])", _("Confidence interval of an exponential smoothing forecast"), (ev, a) => {
                double level = 0.95;
                Value? e = null;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_number (a[3], out level)) != null) return e;
                if (level <= 0 || level >= 1) return Value.err (ErrorKind.NUM);
                Ets m;
                e = build (ev, a[1], a[2], a, 4, 5, 6, out m);
                if (e != null) return e;
                return per_target (ev, a[0], m, true, level);
            });
            add ("FORECAST.ETS.SEASONALITY", 2, 4, "FORECAST.ETS.SEASONALITY(values, timeline, [data_completion], [aggregation])", _("Length of the detected seasonal pattern"), (ev, a) => {
                Ets m;
                var e = build (ev, a[0], a[1], a, 99, 2, 3, out m);
                if (e != null) return e;
                return Value.num (m.period == 1 ? 0 : m.period);
            });
            add ("FORECAST.ETS.STAT", 3, 6, "FORECAST.ETS.STAT(values, timeline, statistic_type, [seasonality], [data_completion], [aggregation])", _("A statistic of an exponential smoothing forecast"), (ev, a) => {
                int type;
                var e = ev.arg_int (a[2], out type);
                if (e != null) return e;
                if (type < 1 || type > 8) return Value.err (ErrorKind.NUM);
                Ets m;
                e = build (ev, a[0], a[1], a, 3, 4, 5, out m);
                if (e != null) return e;
                switch (type) {
                    case 1: return Value.num (m.alpha);
                    case 2: return Value.num (m.beta);
                    case 3: return Value.num (m.gamma);
                    case 4:
                        double naive = 0;
                        int lag = m.period > 1 ? m.period : 1;
                        for (int i = lag; i < m.y.length; i++) naive += Math.fabs (m.y[i] - m.y[i - lag]);
                        naive /= int.max (1, m.y.length - lag);
                        return naive == 0 ? Value.err (ErrorKind.DIV0) : Value.num (m.mae / naive);
                    case 5: return Value.num (m.smape);
                    case 6: return Value.num (m.mae);
                    case 7: return Value.num (Math.sqrt (m.sse / int.max (1, m.y.length - 1)));
                    default: return Value.num (m.step);
                }
            });
        }
    }
}
