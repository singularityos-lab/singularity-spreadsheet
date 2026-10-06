namespace Singularity.Apps.Spreadsheet {

    public class FinancialFunctions {
        private static bool d1904;

        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            FnImpl f = (owned) impl;
            Functions.add (name, min, max, "Financial", syntax, summary, (ev, a) => {
                d1904 = ev.book.date1904;
                return f (ev, a);
            });
        }

        private static Value lift (Evaluator ev, Node[] a, ScalarFn f) {
            return MoreMathFunctions.lift (ev, a, f);
        }

        private static Value opt (Value[] v, int i) {
            return i < v.length ? v[i] : Value.missing ();
        }

        private static Value? nums (Value[] v, int count, double[] out_v, double[] defaults) {
            for (int i = 0; i < count; i++) {
                var x = opt (v, i);
                if (!x.omitted && !(x.kind == ValueKind.EMPTY && i < defaults.length && !defaults[i].is_nan ())) {
                    double d;
                    var e = Evaluator.to_number (x, out d);
                    if (e != null) return e;
                    out_v[i] = d;
                } else {
                    if (i >= defaults.length || defaults[i].is_nan ()) return Value.err (ErrorKind.VALUE);
                    out_v[i] = defaults[i];
                }
            }
            return null;
        }

        private static void ymd (double serial, out int y, out int m, out int d) {
            DateSerial.to_ymd (serial, out y, out m, out d, d1904);
        }

        private static double serial (int y, int m, int d) {
            return DateSerial.from_ymd (y, m, d, d1904);
        }

        private static int dim (int y, int m) {
            return GLib.Date.get_days_in_month ((DateMonth) m, (DateYear) y);
        }

        private static bool leap (int y) {
            return ((DateYear) y).is_leap_year ();
        }

        private static bool last_of_feb (int y, int m, int d) {
            return m == 2 && d == dim (y, m);
        }

        public static double days360 (double s, double e, bool european) {
            int y1, m1, d1, y2, m2, d2;
            ymd (s, out y1, out m1, out d1);
            ymd (e, out y2, out m2, out d2);
            if (european) {
                if (d1 == 31) d1 = 30;
                if (d2 == 31) d2 = 30;
            } else {
                if (last_of_feb (y1, m1, d1) && last_of_feb (y2, m2, d2)) d2 = 30;
                if (last_of_feb (y1, m1, d1)) d1 = 30;
                if (d2 == 31 && d1 >= 30) d2 = 30;
                if (d1 == 31) d1 = 30;
            }
            return (y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1);
        }

        public static double day_count (double s, double e, int basis) {
            switch (basis) {
                case 0: return days360 (s, e, false);
                case 4: return days360 (s, e, true);
                default: return e - s;
            }
        }

        public static double year_days (double s, double e, int basis) {
            switch (basis) {
                case 1:
                    int y1, m1, d1, y2, m2, d2;
                    ymd (s, out y1, out m1, out d1);
                    ymd (e, out y2, out m2, out d2);
                    if (y1 == y2) return leap (y1) ? 366 : 365;
                    bool within_year = (y2 == y1 + 1) && (m2 < m1 || (m2 == m1 && d2 <= d1));
                    if (within_year) {
                        bool has_leap = (leap (y1) && (m1 < 3)) || (leap (y2) && (m2 > 2 || (m2 == 2 && d2 == 29)));
                        return has_leap ? 366 : 365;
                    }
                    double total = 0;
                    for (int y = y1; y <= y2; y++) total += leap (y) ? 366 : 365;
                    return total / (y2 - y1 + 1);
                case 3: return 365;
                default: return 360;
            }
        }

        public static double yearfrac (double s, double e, int basis) {
            if (e < s) {
                double t = s;
                s = e;
                e = t;
            }
            if (basis == 0) {
                int y1, m1, d1, y2, m2, d2;
                ymd (s, out y1, out m1, out d1);
                ymd (e, out y2, out m2, out d2);
                if (d1 == 31 && d2 == 31) {
                    d1 = 30;
                    d2 = 30;
                } else if (d1 == 31) {
                    d1 = 30;
                } else if (d1 == 30 && d2 == 31) {
                    d2 = 30;
                } else if (last_of_feb (y1, m1, d1) && last_of_feb (y2, m2, d2)) {
                    d1 = 30;
                    d2 = 30;
                } else if (last_of_feb (y1, m1, d1)) {
                    d1 = 30;
                }
                return ((y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1)) / 360.0;
            }
            return day_count (s, e, basis) / year_days (s, e, basis);
        }

        private static double add_months (double s, int months, bool eom) {
            int y, m, d;
            ymd (s, out y, out m, out d);
            int total = y * 12 + (m - 1) + months;
            int ny = total / 12;
            int nm = total % 12 + 1;
            int nd = eom ? dim (ny, nm) : int.min (d, dim (ny, nm));
            return serial (ny, nm, nd);
        }

        private static bool is_eom (double s) {
            int y, m, d;
            ymd (s, out y, out m, out d);
            return d == dim (y, m);
        }

        public static double coup_pcd (double settle, double mat, int freq) {
            int step = 12 / freq;
            bool eom = is_eom (mat);
            int k = 0;
            double d = mat;
            while (d > settle) {
                k++;
                d = add_months (mat, -step * k, eom);
            }
            return d;
        }

        public static double coup_ncd (double settle, double mat, int freq) {
            int step = 12 / freq;
            bool eom = is_eom (mat);
            double pcd = coup_pcd (settle, mat, freq);
            int y, m, d, y2, m2, d2;
            ymd (pcd, out y, out m, out d);
            ymd (mat, out y2, out m2, out d2);
            int months = (y2 - y) * 12 + (m2 - m) - step;
            return add_months (mat, -months, eom);
        }

        public static double coup_num (double settle, double mat, int freq) {
            double pcd = coup_pcd (settle, mat, freq);
            int y1, m1, d1, y2, m2, d2;
            ymd (pcd, out y1, out m1, out d1);
            ymd (mat, out y2, out m2, out d2);
            int months = (y2 - y1) * 12 + (m2 - m1);
            return Math.round (months * freq / 12.0);
        }

        public static double coup_days (double settle, double mat, int freq, int basis) {
            if (basis == 1) return coup_ncd (settle, mat, freq) - coup_pcd (settle, mat, freq);
            return (basis == 3 ? 365.0 : 360.0) / freq;
        }

        public static double coup_daybs (double settle, double mat, int freq, int basis) {
            return day_count (coup_pcd (settle, mat, freq), settle, basis);
        }

        public static double coup_daysnc (double settle, double mat, int freq, int basis) {
            if (basis == 0 || basis == 4) return coup_days (settle, mat, freq, basis) - coup_daybs (settle, mat, freq, basis);
            return coup_ncd (settle, mat, freq) - settle;
        }

        private static Value? bond_args (double settle, double mat, double freq, double basis, out int f, out int b) {
            f = (int) Math.trunc (freq);
            b = (int) Math.trunc (basis);
            if (f != 1 && f != 2 && f != 4) return Value.err (ErrorKind.NUM);
            if (b < 0 || b > 4) return Value.err (ErrorKind.NUM);
            if (settle >= mat) return Value.err (ErrorKind.NUM);
            return null;
        }

        private static Value? basis_arg (double basis, out int b) {
            b = (int) Math.trunc (basis);
            if (b < 0 || b > 4) return Value.err (ErrorKind.NUM);
            return null;
        }

        public static double price (double settle, double mat, double rate, double yld, double red, int freq, int basis) {
            double n = coup_num (settle, mat, freq);
            double e = coup_days (settle, mat, freq, basis);
            double a = coup_daybs (settle, mat, freq, basis);
            double dsc = coup_daysnc (settle, mat, freq, basis);
            double coupon = 100 * rate / freq;
            if (n == 1) {
                return (red + coupon) / (1 + dsc / e * yld / freq) - a / e * coupon;
            }
            double p = red / Math.pow (1 + yld / freq, n - 1 + dsc / e);
            for (int k = 1; k <= (int) n; k++) p += coupon / Math.pow (1 + yld / freq, k - 1 + dsc / e);
            p -= coupon * a / e;
            return p;
        }

        public delegate double Fx (double x);

        public static double solve (Fx f, double guess, out bool ok) {
            ok = false;
            double x = guess;
            for (int i = 0; i < 200; i++) {
                double fx = f (x);
                if (fx.is_nan ()) break;
                if (Math.fabs (fx) < 1e-11) {
                    ok = true;
                    return x;
                }
                double h = Math.fabs (x) * 1e-7 + 1e-9;
                double d = (f (x + h) - fx) / h;
                if (d == 0 || d.is_nan ()) break;
                double nx = x - fx / d;
                if (Math.fabs (nx - x) < 1e-13) {
                    ok = true;
                    return nx;
                }
                x = nx;
            }
            double lo = -0.999, hi = 10;
            double flo = f (lo), fhi = f (hi);
            if (flo.is_nan () || fhi.is_nan () || flo * fhi > 0) return x;
            for (int i = 0; i < 300; i++) {
                double mid = (lo + hi) / 2;
                double fm = f (mid);
                if (Math.fabs (fm) < 1e-11 || hi - lo < 1e-14) {
                    ok = true;
                    return mid;
                }
                if (flo * fm < 0) {
                    hi = mid;
                } else {
                    lo = mid;
                    flo = fm;
                }
            }
            ok = true;
            return (lo + hi) / 2;
        }

        public static double duration (double settle, double mat, double coupon, double yld, int freq, int basis) {
            double n = coup_num (settle, mat, freq);
            double dsc_e = coup_daysnc (settle, mat, freq, basis) / coup_days (settle, mat, freq, basis);
            double cp = coupon * 100 / freq;
            double y = 1 + yld / freq;
            double dur = 0, p = 0;
            for (int k = 1; k <= (int) n; k++) {
                double t = k - 1 + dsc_e;
                double cf = cp + (k == (int) n ? 100 : 0);
                double pv = cf / Math.pow (y, t);
                dur += t * pv;
                p += pv;
            }
            return dur / p / freq;
        }

        private static double oddf_price (double settle, double mat, double issue, double first, double rate, double yld, double red, int freq, int basis) {
            int step = 12 / freq;
            double coupon = 100 * rate / freq;
            double n = coup_num (first, mat, freq) + 1;
            double pcd_first = add_months (first, -step, is_eom (mat));
            double p;
            if (issue >= pcd_first) {
                double e = basis == 1 ? first - pcd_first : (basis == 3 ? 365.0 : 360.0) / freq;
                double dfc = day_count (issue, first, basis);
                double dsc = day_count (settle, first, basis);
                double a = day_count (issue, settle, basis);
                double v = 1 + yld / freq;
                p = red / Math.pow (v, n - 1 + dsc / e);
                p += coupon * dfc / e / Math.pow (v, dsc / e);
                for (int k = 2; k <= (int) n; k++) p += coupon / Math.pow (v, k - 1 + dsc / e);
                p -= coupon * a / e;
                return p;
            }
            var starts = new Gee.ArrayList<double?> ();
            double q = pcd_first;
            starts.add (q);
            int k2 = 1;
            while (q > issue) {
                k2++;
                q = add_months (first, -step * k2, is_eom (mat));
                starts.insert (0, q);
            }
            int nc = starts.size;
            double dc_sum = 0, a_sum = 0;
            int nq = 0;
            double dsc2 = 0, e2 = 0;
            for (int i = 0; i < nc; i++) {
                double qs = starts[i];
                double qe = i + 1 < nc ? starts[i + 1] : first;
                double nl = basis == 1 ? qe - qs : (basis == 3 ? 365.0 : 360.0) / freq;
                double from = double.max (qs, issue);
                dc_sum += day_count (from, qe, basis) / nl;
                if (settle > from) a_sum += day_count (from, double.min (settle, qe), basis) / nl;
                if (settle < qe && settle >= qs) {
                    dsc2 = day_count (settle, qe, basis);
                    e2 = nl;
                }
                if (qs > settle) nq++;
            }
            double v2 = 1 + yld / freq;
            double nn = n - 1;
            p = red / Math.pow (v2, nn + nq + dsc2 / e2);
            p += coupon * dc_sum / Math.pow (v2, nq + dsc2 / e2);
            for (int k = 1; k <= (int) nn; k++) p += coupon / Math.pow (v2, k + nq + dsc2 / e2);
            p -= coupon * a_sum;
            return p;
        }

        private static double vdb_period (double cost, double salvage, double life, double factor, bool no_switch, int period) {
            double book = cost;
            double dep = 0;
            bool sl = false;
            double sl_amount = 0;
            for (int t = 1; t <= period; t++) {
                if (sl) {
                    dep = sl_amount;
                } else {
                    double ddb = book * factor / life;
                    if (book - ddb < salvage) ddb = book - salvage;
                    if (ddb < 0) ddb = 0;
                    double remaining = life - (t - 1);
                    double sld = remaining > 0 ? (book - salvage) / remaining : 0;
                    if (!no_switch && sld > ddb) {
                        sl = true;
                        sl_amount = sld;
                        dep = sld;
                    } else {
                        dep = ddb;
                    }
                }
                if (t > Math.ceil (life)) dep = 0;
                book -= dep;
            }
            return dep;
        }

        private static double vdb_cumulative (double cost, double salvage, double life, double factor, bool no_switch, double t) {
            int whole = (int) Math.floor (t);
            double total = 0;
            for (int p = 1; p <= whole; p++) total += vdb_period (cost, salvage, life, factor, no_switch, p);
            double frac = t - whole;
            if (frac > 0) total += frac * vdb_period (cost, salvage, life, factor, no_switch, whole + 1);
            return total;
        }

        private static double npv_from (double rate, Gee.ArrayList<double?> vals, bool positive) {
            double s = 0;
            for (int i = 0; i < vals.size; i++) {
                double v = vals[i];
                if ((positive && v > 0) || (!positive && v < 0)) s += v / Math.pow (1 + rate, i + 1);
            }
            return s;
        }

        private static Value? dates2 (Value[] v, int i, out double s, out double e) {
            s = 0;
            e = 0;
            var r = Evaluator.to_number (opt (v, i), out s);
            if (r != null) return r;
            if ((r = Evaluator.to_number (opt (v, i + 1), out e)) != null) return r;
            s = Math.trunc (s);
            e = Math.trunc (e);
            if (s < 0 || e < 0) return Value.err (ErrorKind.NUM);
            return null;
        }

        private delegate Value CoupOp (double settle, double mat, int freq, int basis);

        private static void coup (string name, string summary, owned CoupOp f) {
            CoupOp op = (owned) f;
            add (name, 3, 4, name + "(settlement, maturity, frequency, [basis])", summary, (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[4];
                var e = nums (v, 4, x, { double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int fq, b;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if ((e = bond_args (s, m, x[2], x[3], out fq, out b)) != null) return e;
                return op (s, m, fq, b);
            }));
        }

        private static double euro_rate (string code) {
            switch (code.up ()) {
                case "EUR": return 1;
                case "BEF": return 40.3399;
                case "LUF": return 40.3399;
                case "DEM": return 1.95583;
                case "ESP": return 166.386;
                case "FRF": return 6.55957;
                case "IEP": return 0.787564;
                case "ITL": return 1936.27;
                case "NLG": return 2.20371;
                case "ATS": return 13.7603;
                case "PTE": return 200.482;
                case "FIM": return 5.94573;
                case "GRD": return 340.750;
                case "SIT": return 239.640;
                case "CYP": return 0.585274;
                case "MTL": return 0.429300;
                case "SKK": return 30.1260;
                case "EEK": return 15.6466;
                case "LVL": return 0.702804;
                case "LTL": return 3.45280;
                case "HRK": return 7.53450;
                default: return 0;
            }
        }

        private static int euro_precision (string code) {
            switch (code.up ()) {
                case "BEF": case "LUF": case "ESP": case "ITL": case "GRD": return 0;
                case "PTE": return 1;
                default: return 2;
            }
        }

        public static void register () {
            coup ("COUPDAYBS", _("Days from the coupon period start to settlement"), (s, m, f, b) => Value.num (coup_daybs (s, m, f, b)));
            coup ("COUPDAYS", _("Days in the coupon period of the settlement"), (s, m, f, b) => Value.num (coup_days (s, m, f, b)));
            coup ("COUPDAYSNC", _("Days from settlement to the next coupon date"), (s, m, f, b) => Value.num (coup_daysnc (s, m, f, b)));
            coup ("COUPNCD", _("The next coupon date after settlement"), (s, m, f, b) => Value.num (coup_ncd (s, m, f)));
            coup ("COUPPCD", _("The previous coupon date before settlement"), (s, m, f, b) => Value.num (coup_pcd (s, m, f)));
            coup ("COUPNUM", _("The number of coupons payable until maturity"), (s, m, f, b) => Value.num (coup_num (s, m, f)));
            add ("PRICE", 6, 7, "PRICE(settlement, maturity, rate, yld, redemption, frequency, [basis])", _("Price per 100 face value of a periodic coupon security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[7];
                var e = nums (v, 7, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int f, b;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if ((e = bond_args (s, m, x[5], x[6], out f, out b)) != null) return e;
                if (x[2] < 0 || x[3] < 0 || x[4] <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (price (s, m, x[2], x[3], x[4], f, b));
            }));
            add ("YIELD", 6, 7, "YIELD(settlement, maturity, rate, pr, redemption, frequency, [basis])", _("Yield of a periodic coupon security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[7];
                var e = nums (v, 7, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int f, b;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if ((e = bond_args (s, m, x[5], x[6], out f, out b)) != null) return e;
                double rate = x[2], pr = x[3], red = x[4];
                if (rate < 0 || pr <= 0 || red <= 0) return Value.err (ErrorKind.NUM);
                double n = coup_num (s, m, f);
                if (n <= 1) {
                    double ee = coup_days (s, m, f, b);
                    double aa = coup_daybs (s, m, f, b);
                    double dsr = ee - aa;
                    double num1 = (red / 100 + rate / f) - (pr / 100 + aa / ee * rate / f);
                    double den = pr / 100 + aa / ee * rate / f;
                    return Value.num (num1 / den * f * ee / dsr);
                }
                bool ok;
                double y = solve ((yy) => price (s, m, rate, yy, red, f, b) - pr, rate > 0 ? rate : 0.05, out ok);
                return ok ? Value.num (y) : Value.err (ErrorKind.NUM);
            }));
            add ("DURATION", 5, 6, "DURATION(settlement, maturity, coupon, yld, frequency, [basis])", _("Macaulay duration of a security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[6];
                var e = nums (v, 6, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int f, b;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if ((e = bond_args (s, m, x[4], x[5], out f, out b)) != null) return e;
                if (x[2] < 0 || x[3] < 0) return Value.err (ErrorKind.NUM);
                return Value.num (duration (s, m, x[2], x[3], f, b));
            }));
            add ("MDURATION", 5, 6, "MDURATION(settlement, maturity, coupon, yld, frequency, [basis])", _("Modified Macaulay duration of a security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[6];
                var e = nums (v, 6, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int f, b;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if ((e = bond_args (s, m, x[4], x[5], out f, out b)) != null) return e;
                if (x[2] < 0 || x[3] < 0) return Value.err (ErrorKind.NUM);
                return Value.num (duration (s, m, x[2], x[3], f, b) / (1 + x[3] / f));
            }));
            add ("ACCRINT", 6, 8, "ACCRINT(issue, first_interest, settlement, rate, par, frequency, [basis], [calc_method])", _("Accrued interest of a periodic interest security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[7];
                var e = nums (v, 7, x, { double.NAN, double.NAN, double.NAN, double.NAN, 1000, double.NAN, 0 });
                if (e != null) return e;
                bool from_issue;
                if ((e = MoreMathFunctions.flag (opt (v, 7), true, out from_issue)) != null) return e;
                double issue = Math.trunc (x[0]), first = Math.trunc (x[1]), settle = Math.trunc (x[2]);
                int f = (int) Math.trunc (x[5]);
                int b;
                if ((e = basis_arg (x[6], out b)) != null) return e;
                if (x[3] <= 0 || x[4] <= 0 || (f != 1 && f != 2 && f != 4) || issue >= settle) return Value.err (ErrorKind.NUM);
                double start = (!from_issue && settle > first) ? first : issue;
                return Value.num (x[4] * x[3] * yearfrac (start, settle, b));
            }));
            add ("ACCRINTM", 3, 5, "ACCRINTM(issue, settlement, rate, [par], [basis])", _("Accrued interest of a security paying at maturity"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[5];
                var e = nums (v, 5, x, { double.NAN, double.NAN, double.NAN, 1000, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[4], out b)) != null) return e;
                double issue = Math.trunc (x[0]), settle = Math.trunc (x[1]);
                if (x[2] <= 0 || x[3] <= 0 || issue >= settle) return Value.err (ErrorKind.NUM);
                return Value.num (x[3] * x[2] * yearfrac (issue, settle, b));
            }));
            add ("AMORLINC", 6, 7, "AMORLINC(cost, date_purchased, first_period, salvage, period, rate, [basis])", _("Depreciation for each accounting period, French system"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[7];
                var e = nums (v, 7, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[6], out b)) != null) return e;
                double cost = x[0], salvage = x[3], rate = x[5];
                int per = (int) Math.trunc (x[4]);
                if (cost < 0 || salvage < 0 || salvage > cost || rate <= 0 || per < 0) return Value.err (ErrorKind.NUM);
                double one = cost * rate;
                double delta = cost - salvage;
                double r0 = yearfrac (Math.trunc (x[1]), Math.trunc (x[2]), b) * rate * cost;
                int full = (int) ((cost - salvage - r0) / one);
                if (per == 0) return Value.num (r0);
                if (per <= full) return Value.num (one);
                if (per == full + 1) return Value.num (delta - one * full - r0);
                return Value.num (0);
            }));
            add ("AMORDEGRC", 6, 7, "AMORDEGRC(cost, date_purchased, first_period, salvage, period, rate, [basis])", _("Depreciation with a coefficient, French system"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[7];
                var e = nums (v, 7, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[6], out b)) != null) return e;
                double cost = x[0], salvage = x[3], rate = x[5];
                int per = (int) Math.trunc (x[4]);
                if (cost < 0 || salvage < 0 || salvage > cost || rate <= 0 || per < 0) return Value.err (ErrorKind.NUM);
                double use_per = 1 / rate;
                double coeff = use_per < 3 ? 1 : (use_per < 5 ? 1.5 : (use_per <= 6 ? 2 : 2.5));
                rate *= coeff;
                double nrate = Math.round (yearfrac (Math.trunc (x[1]), Math.trunc (x[2]), b) * rate * cost);
                cost -= nrate;
                double rest = cost - salvage;
                for (int n = 0; n < per; n++) {
                    nrate = Math.round (rate * cost);
                    rest -= nrate;
                    if (rest < 0) {
                        switch (per - n) {
                            case 0:
                            case 1:
                                return Value.num (Math.round (cost * 0.5));
                            default:
                                return Value.num (0);
                        }
                    }
                    cost -= nrate;
                }
                return Value.num (nrate);
            }));
            add ("CUMIPMT", 6, 6, "CUMIPMT(rate, nper, pv, start_period, end_period, type)", _("Cumulative interest paid between two periods"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[6];
                var e = nums (v, 6, x, {});
                if (e != null) return e;
                double rate = x[0], nper = Math.trunc (x[1]), pv = x[2];
                int start = (int) Math.trunc (x[3]), end = (int) Math.trunc (x[4]), type = (int) Math.trunc (x[5]);
                if (rate <= 0 || nper <= 0 || pv <= 0 || start < 1 || end < start || end > nper || (type != 0 && type != 1)) return Value.err (ErrorKind.NUM);
                double pmt = FinanceFunctions.pmt (rate, nper, pv, 0, type);
                double ip = 0;
                if (start == 1) {
                    if (type == 0) ip = -pv;
                    start++;
                }
                for (int i = start; i <= end; i++) {
                    if (type == 1) ip += FinanceFunctions.fv (rate, i - 2, pmt, pv, 1) - pmt;
                    else ip += FinanceFunctions.fv (rate, i - 1, pmt, pv, 0);
                }
                return Value.num (ip * rate);
            }));
            add ("CUMPRINC", 6, 6, "CUMPRINC(rate, nper, pv, start_period, end_period, type)", _("Cumulative principal paid between two periods"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[6];
                var e = nums (v, 6, x, {});
                if (e != null) return e;
                double rate = x[0], nper = Math.trunc (x[1]), pv = x[2];
                int start = (int) Math.trunc (x[3]), end = (int) Math.trunc (x[4]), type = (int) Math.trunc (x[5]);
                if (rate <= 0 || nper <= 0 || pv <= 0 || start < 1 || end < start || end > nper || (type != 0 && type != 1)) return Value.err (ErrorKind.NUM);
                double pmt = FinanceFunctions.pmt (rate, nper, pv, 0, type);
                double pp = 0;
                if (start == 1) {
                    pp = type == 0 ? pmt + pv * rate : pmt;
                    start++;
                }
                for (int i = start; i <= end; i++) {
                    if (type == 1) pp += pmt - (FinanceFunctions.fv (rate, i - 2, pmt, pv, 1) - pmt) * rate;
                    else pp += pmt - FinanceFunctions.fv (rate, i - 1, pmt, pv, 0) * rate;
                }
                return Value.num (pp);
            }));
            add ("DB", 4, 5, "DB(cost, salvage, life, period, [month])", _("Fixed-declining balance depreciation"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[5];
                var e = nums (v, 5, x, { double.NAN, double.NAN, double.NAN, double.NAN, 12 });
                if (e != null) return e;
                double cost = x[0], salvage = x[1], life = x[2], per = Math.trunc (x[3]), month = Math.trunc (x[4]);
                if (cost < 0 || salvage < 0 || life <= 0 || per <= 0 || month < 1 || month > 12 || per > life + (month < 12 ? 1 : 0)) return Value.err (ErrorKind.NUM);
                if (cost == 0) return Value.num (0);
                double rate = Math.round ((1 - Math.pow (salvage / cost, 1 / life)) * 1000) / 1000;
                double total = cost * rate * month / 12;
                if (per == 1) return Value.num (total);
                double dep = 0;
                for (int p = 2; p <= (int) per; p++) {
                    if (p == (int) life + 1) dep = (cost - total) * rate * (12 - month) / 12;
                    else dep = (cost - total) * rate;
                    total += dep;
                }
                return Value.num (dep);
            }));
            add ("DISC", 4, 5, "DISC(settlement, maturity, pr, redemption, [basis])", _("Discount rate of a security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[5];
                var e = nums (v, 5, x, { double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[4], out b)) != null) return e;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if (x[2] <= 0 || x[3] <= 0 || s >= m) return Value.err (ErrorKind.NUM);
                return Value.num ((x[3] - x[2]) / x[3] / yearfrac (s, m, b));
            }));
            add ("DOLLARDE", 2, 2, "DOLLARDE(fractional_dollar, fraction)", _("Converts a fractional dollar price to a decimal"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[2];
                var e = nums (v, 2, x, {});
                if (e != null) return e;
                double fr = Math.trunc (x[1]);
                if (fr < 0) return Value.err (ErrorKind.NUM);
                if (fr == 0) return Value.err (ErrorKind.DIV0);
                double ip = Math.trunc (x[0]);
                double fp = x[0] - ip;
                double p = Math.pow (10, Math.ceil (Math.log10 (fr)));
                return Value.num (ip + fp * p / fr);
            }));
            add ("DOLLARFR", 2, 2, "DOLLARFR(decimal_dollar, fraction)", _("Converts a decimal dollar price to a fraction"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[2];
                var e = nums (v, 2, x, {});
                if (e != null) return e;
                double fr = Math.trunc (x[1]);
                if (fr < 0) return Value.err (ErrorKind.NUM);
                if (fr == 0) return Value.err (ErrorKind.DIV0);
                double ip = Math.trunc (x[0]);
                double fp = x[0] - ip;
                double p = Math.pow (10, Math.ceil (Math.log10 (fr)));
                return Value.num (ip + fp * fr / p);
            }));
            add ("FVSCHEDULE", 2, 2, "FVSCHEDULE(principal, schedule)", _("Future value after a series of interest rates"), (ev, a) => {
                double p;
                var e = ev.arg_number (a[0], out p);
                if (e != null) return e;
                var m = ev.to_matrix (ev.eval (a[1]));
                for (int i = 0; i < m.length[0]; i++) {
                    for (int j = 0; j < m.length[1]; j++) {
                        var r = m[i, j];
                        if (r.is_error ()) return r;
                        if (r.kind == ValueKind.EMPTY) continue;
                        if (r.kind != ValueKind.NUMBER) return Value.err (ErrorKind.VALUE);
                        p *= 1 + r.number;
                    }
                }
                return Value.num (p);
            });
            add ("INTRATE", 4, 5, "INTRATE(settlement, maturity, investment, redemption, [basis])", _("Interest rate of a fully invested security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[5];
                var e = nums (v, 5, x, { double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[4], out b)) != null) return e;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if (x[2] <= 0 || x[3] <= 0 || s >= m) return Value.err (ErrorKind.NUM);
                return Value.num ((x[3] - x[2]) / x[2] / yearfrac (s, m, b));
            }));
            add ("ISPMT", 4, 4, "ISPMT(rate, per, nper, pv)", _("Interest paid in a period of a straight-line loan"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[4];
                var e = nums (v, 4, x, {});
                if (e != null) return e;
                if (x[2] == 0) return Value.err (ErrorKind.DIV0);
                return Value.num (x[3] * x[0] * (x[1] / x[2] - 1));
            }));
            add ("MIRR", 3, 3, "MIRR(values, finance_rate, reinvest_rate)", _("Modified internal rate of return"), (ev, a) => {
                double fr, rr;
                var e = ev.arg_number (a[1], out fr);
                if (e != null) return e;
                if ((e = ev.arg_number (a[2], out rr)) != null) return e;
                var vals = new Gee.ArrayList<double?> ();
                var m = ev.to_matrix (ev.eval (a[0]));
                for (int i = 0; i < m.length[0]; i++) {
                    for (int j = 0; j < m.length[1]; j++) {
                        var x = m[i, j];
                        if (x.is_error ()) return x;
                        if (x.kind == ValueKind.NUMBER) vals.add (x.number);
                    }
                }
                int n = vals.size;
                double pos = npv_from (rr, vals, true);
                double neg = npv_from (fr, vals, false);
                if (pos == 0 || neg == 0 || n < 2) return Value.err (ErrorKind.DIV0);
                double r = Math.pow ((-pos * Math.pow (1 + rr, n)) / (neg * (1 + fr)), 1.0 / (n - 1)) - 1;
                return Value.num (r);
            });
            add ("ODDFPRICE", 8, 9, "ODDFPRICE(settlement, maturity, issue, first_coupon, rate, yld, redemption, frequency, [basis])", _("Price of a security with an odd first period"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[9];
                var e = nums (v, 9, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int f, b;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]), iss = Math.trunc (x[2]), fc = Math.trunc (x[3]);
                if ((e = bond_args (s, m, x[7], x[8], out f, out b)) != null) return e;
                if (!(iss < s && s < fc && fc <= m) || x[4] < 0 || x[5] < 0 || x[6] <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (oddf_price (s, m, iss, fc, x[4], x[5], x[6], f, b));
            }));
            add ("ODDFYIELD", 8, 9, "ODDFYIELD(settlement, maturity, issue, first_coupon, rate, pr, redemption, frequency, [basis])", _("Yield of a security with an odd first period"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[9];
                var e = nums (v, 9, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int f, b;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]), iss = Math.trunc (x[2]), fc = Math.trunc (x[3]);
                if ((e = bond_args (s, m, x[7], x[8], out f, out b)) != null) return e;
                if (!(iss < s && s < fc && fc <= m) || x[4] < 0 || x[5] <= 0 || x[6] <= 0) return Value.err (ErrorKind.NUM);
                double rate = x[4], pr = x[5], red = x[6];
                bool ok;
                double y = solve ((yy) => oddf_price (s, m, iss, fc, rate, yy, red, f, b) - pr, rate > 0 ? rate : 0.05, out ok);
                return ok ? Value.num (y) : Value.err (ErrorKind.NUM);
            }));
            add ("ODDLPRICE", 7, 8, "ODDLPRICE(settlement, maturity, last_interest, rate, yld, redemption, frequency, [basis])", _("Price of a security with an odd last period"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[8];
                var e = nums (v, 8, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int f, b;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]), li = Math.trunc (x[2]);
                if ((e = bond_args (s, m, x[6], x[7], out f, out b)) != null) return e;
                if (li >= s || x[3] < 0 || x[4] < 0 || x[5] <= 0) return Value.err (ErrorKind.NUM);
                double dci = yearfrac (li, m, b) * f;
                double dsci = yearfrac (s, m, b) * f;
                double ai = yearfrac (li, s, b) * f;
                double p = x[5] + dci * 100 * x[3] / f;
                p /= dsci * x[4] / f + 1;
                p -= ai * 100 * x[3] / f;
                return Value.num (p);
            }));
            add ("ODDLYIELD", 7, 8, "ODDLYIELD(settlement, maturity, last_interest, rate, pr, redemption, frequency, [basis])", _("Yield of a security with an odd last period"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[8];
                var e = nums (v, 8, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int f, b;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]), li = Math.trunc (x[2]);
                if ((e = bond_args (s, m, x[6], x[7], out f, out b)) != null) return e;
                if (li >= s || x[3] < 0 || x[4] <= 0 || x[5] <= 0) return Value.err (ErrorKind.NUM);
                double dci = yearfrac (li, m, b) * f;
                double dsci = yearfrac (s, m, b) * f;
                double ai = yearfrac (li, s, b) * f;
                double y = x[5] + dci * 100 * x[3] / f;
                y /= x[4] + ai * 100 * x[3] / f;
                y -= 1;
                y *= f / dsci;
                return Value.num (y);
            }));
            add ("PDURATION", 3, 3, "PDURATION(rate, pv, fv)", _("Periods needed to reach a value"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[3];
                var e = nums (v, 3, x, {});
                if (e != null) return e;
                if (x[0] <= 0 || x[1] <= 0 || x[2] <= 0) return Value.err (ErrorKind.NUM);
                return Value.num ((Math.log (x[2]) - Math.log (x[1])) / Math.log (1 + x[0]));
            }));
            add ("PRICEDISC", 4, 5, "PRICEDISC(settlement, maturity, discount, redemption, [basis])", _("Price per 100 face value of a discounted security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[5];
                var e = nums (v, 5, x, { double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[4], out b)) != null) return e;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if (x[2] <= 0 || x[3] <= 0 || s >= m) return Value.err (ErrorKind.NUM);
                return Value.num (x[3] * (1 - x[2] * yearfrac (s, m, b)));
            }));
            add ("PRICEMAT", 5, 6, "PRICEMAT(settlement, maturity, issue, rate, yld, [basis])", _("Price per 100 face value of a security paying at maturity"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[6];
                var e = nums (v, 6, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[5], out b)) != null) return e;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]), iss = Math.trunc (x[2]);
                if (x[3] < 0 || x[4] < 0 || s >= m) return Value.err (ErrorKind.NUM);
                double im = yearfrac (iss, m, b), is_ = yearfrac (iss, s, b), sm = yearfrac (s, m, b);
                double p = (1 + im * x[3]) / (1 + sm * x[4]) - is_ * x[3];
                return Value.num (p * 100);
            }));
            add ("RECEIVED", 4, 5, "RECEIVED(settlement, maturity, investment, discount, [basis])", _("Amount received at maturity of a fully invested security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[5];
                var e = nums (v, 5, x, { double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[4], out b)) != null) return e;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if (x[2] <= 0 || x[3] <= 0 || s >= m) return Value.err (ErrorKind.NUM);
                double d = 1 - x[3] * yearfrac (s, m, b);
                if (d <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (x[2] / d);
            }));
            add ("RRI", 3, 3, "RRI(nper, pv, fv)", _("Equivalent interest rate for the growth of an investment"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[3];
                var e = nums (v, 3, x, {});
                if (e != null) return e;
                if (x[0] <= 0 || x[1] == 0) return Value.err (ErrorKind.NUM);
                double r = Math.pow (x[2] / x[1], 1 / x[0]) - 1;
                return Value.num (r);
            }));
            add ("TBILLEQ", 3, 3, "TBILLEQ(settlement, maturity, discount)", _("Bond-equivalent yield of a Treasury bill"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[3];
                var e = nums (v, 3, x, {});
                if (e != null) return e;
                double dsm = Math.trunc (x[1]) - Math.trunc (x[0]);
                if (x[2] <= 0 || dsm <= 0 || dsm > 365) return Value.err (ErrorKind.NUM);
                if (dsm <= 182) return Value.num (365 * x[2] / (360 - x[2] * dsm));
                double pr = 100 * (1 - x[2] * dsm / 360);
                double t = dsm / 365;
                double r = (-t + Math.sqrt (t * t - (2 * t - 1) * (1 - 100 / pr))) / (t - 0.5);
                return Value.num (r);
            }));
            add ("TBILLPRICE", 3, 3, "TBILLPRICE(settlement, maturity, discount)", _("Price per 100 face value of a Treasury bill"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[3];
                var e = nums (v, 3, x, {});
                if (e != null) return e;
                double dsm = Math.trunc (x[1]) - Math.trunc (x[0]);
                if (x[2] <= 0 || dsm <= 0 || dsm > 365) return Value.err (ErrorKind.NUM);
                double p = 100 * (1 - x[2] * dsm / 360);
                if (p <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (p);
            }));
            add ("TBILLYIELD", 3, 3, "TBILLYIELD(settlement, maturity, pr)", _("Yield of a Treasury bill"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[3];
                var e = nums (v, 3, x, {});
                if (e != null) return e;
                double dsm = Math.trunc (x[1]) - Math.trunc (x[0]);
                if (x[2] <= 0 || dsm <= 0 || dsm > 365) return Value.err (ErrorKind.NUM);
                return Value.num ((100 - x[2]) / x[2] * 360 / dsm);
            }));
            add ("VDB", 5, 7, "VDB(cost, salvage, life, start_period, end_period, [factor], [no_switch])", _("Declining balance depreciation for any period"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[6];
                var e = nums (v, 6, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 2 });
                if (e != null) return e;
                bool no_switch;
                if ((e = MoreMathFunctions.flag (opt (v, 6), false, out no_switch)) != null) return e;
                double cost = x[0], salvage = x[1], life = x[2], st = x[3], en = x[4], factor = x[5];
                if (cost < 0 || salvage < 0 || life <= 0 || st < 0 || en < st || en > life || factor <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (vdb_cumulative (cost, salvage, life, factor, no_switch, en) - vdb_cumulative (cost, salvage, life, factor, no_switch, st));
            }));
            add ("YIELDDISC", 4, 5, "YIELDDISC(settlement, maturity, pr, redemption, [basis])", _("Annual yield of a discounted security"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[5];
                var e = nums (v, 5, x, { double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[4], out b)) != null) return e;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]);
                if (x[2] <= 0 || x[3] <= 0 || s >= m) return Value.err (ErrorKind.NUM);
                return Value.num ((x[3] - x[2]) / x[2] / yearfrac (s, m, b));
            }));
            add ("YIELDMAT", 5, 6, "YIELDMAT(settlement, maturity, issue, rate, pr, [basis])", _("Annual yield of a security paying at maturity"), (ev, a) => lift (ev, a, (v) => {
                double[] x = new double[6];
                var e = nums (v, 6, x, { double.NAN, double.NAN, double.NAN, double.NAN, double.NAN, 0 });
                if (e != null) return e;
                int b;
                if ((e = basis_arg (x[5], out b)) != null) return e;
                double s = Math.trunc (x[0]), m = Math.trunc (x[1]), iss = Math.trunc (x[2]);
                if (x[3] < 0 || x[4] <= 0 || s >= m) return Value.err (ErrorKind.NUM);
                double im = yearfrac (iss, m, b), is_ = yearfrac (iss, s, b), sm = yearfrac (s, m, b);
                double y = (1 + im * x[3]) / (x[4] / 100 + is_ * x[3]) - 1;
                return Value.num (y / sm);
            }));
            add ("EUROCONVERT", 3, 5, "EUROCONVERT(number, source, target, [full_precision], [triangulation_precision])", _("Converts between euro and former euro area currencies"), (ev, a) => lift (ev, a, (v) => {
                double x;
                var e = Evaluator.to_number (v[0], out x);
                if (e != null) return e;
                if (v[1].is_error ()) return v[1];
                if (v[2].is_error ()) return v[2];
                string src = Evaluator.to_text (v[1]).up ();
                string dst = Evaluator.to_text (v[2]).up ();
                double rs = euro_rate (src), rd = euro_rate (dst);
                if (rs == 0 || rd == 0) return Value.err (ErrorKind.VALUE);
                bool full;
                if ((e = MoreMathFunctions.flag (opt (v, 3), false, out full)) != null) return e;
                double tri = -1;
                var tv = opt (v, 4);
                if (MoreMathFunctions.given (tv) && tv.kind != ValueKind.EMPTY) {
                    if ((e = Evaluator.to_number (tv, out tri)) != null) return e;
                    if (tri < 3) return Value.err (ErrorKind.VALUE);
                }
                double euros = x / rs;
                if (tri >= 3 && src != "EUR" && dst != "EUR") euros = Functions.round_digits (euros, (int) tri, 0);
                double r = euros * rd;
                if (!full) r = Functions.round_digits (r, euro_precision (dst), 0);
                return Value.num (r);
            }));
        }
    }
}
