namespace Singularity.Apps.Spreadsheet {

    public class DateFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Date", syntax, summary, (owned) impl);
        }

        private delegate Value DatePart (int y, int m, int d, double serial);

        private static void part (string name, string summary, owned DatePart f) {
            DatePart fn = (owned) f;
            add (name, 1, 1, name + "(date)", summary, (ev, a) => {
                return ev.map1 (ev.eval (a[0]), (v) => {
                    double s;
                    var e = Evaluator.to_number (v, out s);
                    if (e != null) return e;
                    int y, m, d;
                    if (!DateSerial.to_ymd (s, out y, out m, out d, ev.book.date1904)) return Value.err (ErrorKind.NUM);
                    return fn (y, m, d, s);
                });
            });
        }

        private static Value? arg_date (Evaluator ev, Node n, out double serial) {
            var v = ev.arg (n);
            var e = Evaluator.to_number (v, out serial);
            if (e != null) return e;
            if (serial < 0) return Value.err (ErrorKind.NUM);
            serial = Math.floor (serial);
            return null;
        }

        private static int days_in_month (int y, int m) {
            return GLib.Date.get_days_in_month ((DateMonth) m, (DateYear) y);
        }

        private static double add_months (double serial, int months, bool end_of_month, bool d1904) {
            int y, m, d;
            DateSerial.to_ymd (serial, out y, out m, out d, d1904);
            int total = y * 12 + (m - 1) + months;
            int ny = total / 12;
            int nm = total % 12 + 1;
            int dim = days_in_month (ny, nm);
            int nd = end_of_month ? dim : int.min (d, dim);
            return DateSerial.from_ymd (ny, nm, nd, d1904);
        }

        private static Gee.HashSet<int> holidays (Evaluator ev, Node? n) {
            var set = new Gee.HashSet<int> ();
            if (n == null) return set;
            ev.visit_values (n, (v, r) => {
                if (v.kind == ValueKind.NUMBER) set.add ((int) Math.floor (v.number));
                return true;
            });
            return set;
        }

        private static bool is_workday (int serial, Gee.HashSet<int> hol, bool[] weekend) {
            int wd = DateSerial.weekday (serial);
            return !weekend[wd] && !hol.contains (serial);
        }

        private static bool[]? weekend_mask (Evaluator ev, Node? n) {
            bool[] w = { true, false, false, false, false, false, true };
            if (n == null || n.kind == NodeKind.MISSING) return w;
            var v = ev.arg (n);
            if (v.kind == ValueKind.TEXT) {
                if (v.text.length != 7) return null;
                bool[] mask = new bool[7];
                for (int i = 0; i < 7; i++) {
                    if (v.text[i] != '0' && v.text[i] != '1') return null;
                    mask[(i + 1) % 7] = v.text[i] == '1';
                }
                return mask;
            }
            int code = (int) v.number;
            bool[] m = new bool[7];
            if (code >= 1 && code <= 7) {
                int first = (code + 5) % 7;
                m[first] = true;
                m[(first + 1) % 7] = true;
                return m;
            }
            if (code >= 11 && code <= 17) {
                m[(code - 10) % 7] = true;
                return m;
            }
            return null;
        }

        public static void register () {
            add ("TODAY", 0, 0, "TODAY()", _("Today's date"), (ev, a) => Value.num (Math.floor (DateSerial.now ())));
            add ("NOW", 0, 0, "NOW()", _("The current date and time"), (ev, a) => Value.num (DateSerial.now ()));
            add ("DATE", 3, 3, "DATE(year, month, day)", _("A date from its parts"), (ev, a) => {
                int y, m, d;
                var e = ev.arg_int (a[0], out y);
                if (e != null) return e;
                if ((e = ev.arg_int (a[1], out m)) != null) return e;
                if ((e = ev.arg_int (a[2], out d)) != null) return e;
                if (y < 1900 && y >= 0) y += 1900;
                double s = DateSerial.from_ymd (y, m, d, ev.book.date1904);
                return s < 0 ? Value.err (ErrorKind.NUM) : Value.num (s);
            });
            add ("TIME", 3, 3, "TIME(hour, minute, second)", _("A time from its parts"), (ev, a) => {
                double h, m, s;
                var e = ev.arg_number (a[0], out h);
                if (e != null) return e;
                if ((e = ev.arg_number (a[1], out m)) != null) return e;
                if ((e = ev.arg_number (a[2], out s)) != null) return e;
                double t = (Math.trunc (h) * 3600 + Math.trunc (m) * 60 + Math.trunc (s)) / 86400.0;
                if (t < 0) return Value.err (ErrorKind.NUM);
                return Value.num (t - Math.floor (t));
            });
            part ("YEAR", _("The year of a date"), (y, m, d, s) => Value.num (y));
            part ("MONTH", _("The month of a date"), (y, m, d, s) => Value.num (m));
            part ("DAY", _("The day of a date"), (y, m, d, s) => Value.num (d));
            add ("HOUR", 1, 1, "HOUR(time)", _("The hour of a time"), (ev, a) => time_part (ev, a, 0));
            add ("MINUTE", 1, 1, "MINUTE(time)", _("The minute of a time"), (ev, a) => time_part (ev, a, 1));
            add ("SECOND", 1, 1, "SECOND(time)", _("The second of a time"), (ev, a) => time_part (ev, a, 2));
            add ("WEEKDAY", 1, 2, "WEEKDAY(date, [type])", _("The day of the week"), (ev, a) => {
                double s;
                var e = arg_date (ev, a[0], out s);
                if (e != null) return e;
                int type = 1;
                if (a.length > 1 && (e = ev.arg_int (a[1], out type)) != null) return e;
                int wd = DateSerial.weekday (s);
                switch (type) {
                    case 1: case 17: return Value.num (wd + 1);
                    case 2: case 11: return Value.num ((wd + 6) % 7 + 1);
                    case 3: return Value.num ((wd + 6) % 7);
                    case 12: return Value.num ((wd + 5) % 7 + 1);
                    case 13: return Value.num ((wd + 4) % 7 + 1);
                    case 14: return Value.num ((wd + 3) % 7 + 1);
                    case 15: return Value.num ((wd + 2) % 7 + 1);
                    case 16: return Value.num ((wd + 1) % 7 + 1);
                }
                return Value.err (ErrorKind.NUM);
            });
            add ("WEEKNUM", 1, 2, "WEEKNUM(date, [type])", _("The week of the year"), (ev, a) => {
                double s;
                var e = arg_date (ev, a[0], out s);
                if (e != null) return e;
                int type = 1;
                if (a.length > 1 && (e = ev.arg_int (a[1], out type)) != null) return e;
                if (type == 21) return Value.num (iso_week (s, ev.book.date1904));
                int start = type == 2 || type == 11 ? 1 : (type >= 12 && type <= 17 ? type - 10 : 0);
                int y, m, d;
                DateSerial.to_ymd (s, out y, out m, out d, ev.book.date1904);
                double jan1 = DateSerial.from_ymd (y, 1, 1, ev.book.date1904);
                int offset = (DateSerial.weekday (jan1) - start + 7) % 7;
                return Value.num (Math.floor ((s - jan1 + offset) / 7) + 1);
            });
            add ("ISOWEEKNUM", 1, 1, "ISOWEEKNUM(date)", _("The ISO week of the year"), (ev, a) => {
                double s;
                var e = arg_date (ev, a[0], out s);
                return e ?? Value.num (iso_week (s, ev.book.date1904));
            });
            add ("EDATE", 2, 2, "EDATE(start, months)", _("A date some months away"), (ev, a) => {
                double s;
                int months;
                var e = arg_date (ev, a[0], out s);
                if (e != null) return e;
                if ((e = ev.arg_int (a[1], out months)) != null) return e;
                return Value.num (add_months (s, months, false, ev.book.date1904));
            });
            add ("EOMONTH", 2, 2, "EOMONTH(start, months)", _("The last day of a month"), (ev, a) => {
                double s;
                int months;
                var e = arg_date (ev, a[0], out s);
                if (e != null) return e;
                if ((e = ev.arg_int (a[1], out months)) != null) return e;
                return Value.num (add_months (s, months, true, ev.book.date1904));
            });
            add ("DAYS", 2, 2, "DAYS(end, start)", _("Days between two dates"), (ev, a) => {
                double e1, s1;
                var e = arg_date (ev, a[0], out e1);
                if (e != null) return e;
                if ((e = arg_date (ev, a[1], out s1)) != null) return e;
                return Value.num (e1 - s1);
            });
            add ("DAYS360", 2, 3, "DAYS360(start, end, [european])", _("Days between dates in a 360-day year"), (ev, a) => {
                double s, en;
                var e = arg_date (ev, a[0], out s);
                if (e != null) return e;
                if ((e = arg_date (ev, a[1], out en)) != null) return e;
                bool eu = false;
                if (a.length > 2 && (e = ev.arg_bool (a[2], out eu)) != null) return e;
                int y1, m1, d1, y2, m2, d2;
                DateSerial.to_ymd (s, out y1, out m1, out d1, ev.book.date1904);
                DateSerial.to_ymd (en, out y2, out m2, out d2, ev.book.date1904);
                if (eu) {
                    if (d1 == 31) d1 = 30;
                    if (d2 == 31) d2 = 30;
                } else {
                    if (d1 == 31 || (m1 == 2 && d1 == days_in_month (y1, 2))) d1 = 30;
                    if (d2 == 31 && d1 >= 30) d2 = 30;
                }
                return Value.num ((y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1));
            });
            add ("DATEDIF", 3, 3, "DATEDIF(start, end, unit)", _("The difference between two dates"), (ev, a) => {
                double s, en;
                var e = arg_date (ev, a[0], out s);
                if (e != null) return e;
                if ((e = arg_date (ev, a[1], out en)) != null) return e;
                Value? te = null;
                string unit = ev.arg_text (a[2], out te).up ();
                if (te != null) return te;
                if (en < s) return Value.err (ErrorKind.NUM);
                int y1, m1, d1, y2, m2, d2;
                DateSerial.to_ymd (s, out y1, out m1, out d1, ev.book.date1904);
                DateSerial.to_ymd (en, out y2, out m2, out d2, ev.book.date1904);
                int months = (y2 - y1) * 12 + (m2 - m1) - (d2 < d1 ? 1 : 0);
                switch (unit) {
                    case "D": return Value.num (en - s);
                    case "M": return Value.num (months);
                    case "Y": return Value.num (months / 12);
                    case "YM": return Value.num (months % 12);
                    case "MD":
                        int dd = d2 - d1;
                        if (dd < 0) {
                            int pm = m2 == 1 ? 12 : m2 - 1;
                            int py = m2 == 1 ? y2 - 1 : y2;
                            dd += days_in_month (py, pm);
                        }
                        return Value.num (dd);
                    case "YD":
                        double anchor = DateSerial.from_ymd (y2, m1, d1, ev.book.date1904);
                        if (anchor > en) anchor = DateSerial.from_ymd (y2 - 1, m1, d1, ev.book.date1904);
                        return Value.num (en - anchor);
                }
                return Value.err (ErrorKind.NUM);
            });
            add ("DATEVALUE", 1, 1, "DATEVALUE(text)", _("A date from its text"), (ev, a) => {
                Value? e = null;
                string t = ev.arg_text (a[0], out e);
                if (e != null) return e;
                double d;
                string f;
                if (!Input.parse_date_time (t, out d, out f)) return Value.err (ErrorKind.VALUE);
                return Value.num (Math.floor (d));
            });
            add ("TIMEVALUE", 1, 1, "TIMEVALUE(text)", _("A time from its text"), (ev, a) => {
                Value? e = null;
                string t = ev.arg_text (a[0], out e);
                if (e != null) return e;
                double d;
                string f;
                if (!Input.parse_date_time (t, out d, out f)) return Value.err (ErrorKind.VALUE);
                return Value.num (d - Math.floor (d));
            });
            add ("NETWORKDAYS", 2, 3, "NETWORKDAYS(start, end, [holidays])", _("Working days between two dates"), (ev, a) => networkdays (ev, a[0], a[1], null, a.length > 2 ? a[2] : null));
            add ("NETWORKDAYS.INTL", 2, 4, "NETWORKDAYS.INTL(start, end, [weekend], [holidays])", _("Working days with custom weekends"), (ev, a) => networkdays (ev, a[0], a[1], a.length > 2 ? a[2] : null, a.length > 3 ? a[3] : null));
            add ("WORKDAY", 2, 3, "WORKDAY(start, days, [holidays])", _("A date some working days away"), (ev, a) => workday (ev, a[0], a[1], null, a.length > 2 ? a[2] : null));
            add ("WORKDAY.INTL", 2, 4, "WORKDAY.INTL(start, days, [weekend], [holidays])", _("A working day with custom weekends"), (ev, a) => workday (ev, a[0], a[1], a.length > 2 ? a[2] : null, a.length > 3 ? a[3] : null));
            add ("YEARFRAC", 2, 3, "YEARFRAC(start, end, [basis])", _("The fraction of a year between dates"), (ev, a) => {
                double s, en;
                var e = arg_date (ev, a[0], out s);
                if (e != null) return e;
                if ((e = arg_date (ev, a[1], out en)) != null) return e;
                int basis = 0;
                if (a.length > 2 && (e = ev.arg_int (a[2], out basis)) != null) return e;
                if (en < s) {
                    double t = s;
                    s = en;
                    en = t;
                }
                int y1, m1, d1, y2, m2, d2;
                DateSerial.to_ymd (s, out y1, out m1, out d1, ev.book.date1904);
                DateSerial.to_ymd (en, out y2, out m2, out d2, ev.book.date1904);
                switch (basis) {
                    case 0:
                        if (d1 == 31) d1 = 30;
                        if (d2 == 31 && d1 == 30) d2 = 30;
                        return Value.num (((y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1)) / 360.0);
                    case 1:
                        double days_year = ((DateYear) y1).is_leap_year () ? 366 : 365;
                        if (y2 != y1) {
                            double total = 0;
                            for (int y = y1; y <= y2; y++) total += ((DateYear) y).is_leap_year () ? 366 : 365;
                            days_year = total / (y2 - y1 + 1);
                        }
                        return Value.num ((en - s) / days_year);
                    case 2: return Value.num ((en - s) / 360);
                    case 3: return Value.num ((en - s) / 365);
                    case 4:
                        if (d1 == 31) d1 = 30;
                        if (d2 == 31) d2 = 30;
                        return Value.num (((y2 - y1) * 360 + (m2 - m1) * 30 + (d2 - d1)) / 360.0);
                }
                return Value.err (ErrorKind.NUM);
            });
        }

        private static int iso_week (double serial, bool d1904) {
            int wd = (DateSerial.weekday (serial) + 6) % 7;
            double thursday = Math.floor (serial) - wd + 3;
            int y, m, d;
            DateSerial.to_ymd (thursday, out y, out m, out d, d1904);
            double jan1 = DateSerial.from_ymd (y, 1, 1, d1904);
            return (int) Math.floor ((thursday - jan1) / 7) + 1;
        }

        private static Value time_part (Evaluator ev, Node[] a, int which) {
            return ev.map1 (ev.eval (a[0]), (v) => {
                double s;
                var e = Evaluator.to_number (v, out s);
                if (e != null) return e;
                if (s < 0) return Value.err (ErrorKind.NUM);
                int h, m, sec;
                double frac;
                DateSerial.to_hms (s, out h, out m, out sec, out frac);
                return Value.num (which == 0 ? h : (which == 1 ? m : sec));
            });
        }

        private static Value networkdays (Evaluator ev, Node sn, Node en, Node? wn, Node? hn) {
            double s, e1;
            var e = arg_date (ev, sn, out s);
            if (e != null) return e;
            if ((e = arg_date (ev, en, out e1)) != null) return e;
            var mask = weekend_mask (ev, wn);
            if (mask == null) return Value.err (ErrorKind.VALUE);
            var hol = holidays (ev, hn);
            int sign = e1 >= s ? 1 : -1;
            int from = (int) double.min (s, e1), to = (int) double.max (s, e1);
            int count = 0;
            for (int d = from; d <= to; d++) if (is_workday (d, hol, mask)) count++;
            return Value.num (sign * count);
        }

        private static Value workday (Evaluator ev, Node sn, Node dn, Node? wn, Node? hn) {
            double s;
            var e = arg_date (ev, sn, out s);
            if (e != null) return e;
            int days;
            if ((e = ev.arg_int (dn, out days)) != null) return e;
            var mask = weekend_mask (ev, wn);
            if (mask == null) return Value.err (ErrorKind.VALUE);
            var hol = holidays (ev, hn);
            int d = (int) s;
            int step = days >= 0 ? 1 : -1;
            int left = days.abs ();
            while (left > 0) {
                d += step;
                if (is_workday (d, hol, mask)) left--;
            }
            return Value.num (d);
        }
    }

    public class FinanceFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Financial", syntax, summary, (owned) impl);
        }

        private static Value? nums (Evaluator ev, Node[] a, int from, int count, double[] out_v, double[] defaults) {
            for (int i = 0; i < count; i++) {
                int k = from + i;
                if (k < a.length && a[k].kind != NodeKind.MISSING) {
                    double d;
                    var e = ev.arg_number (a[k], out d);
                    if (e != null) return e;
                    out_v[i] = d;
                } else {
                    out_v[i] = defaults[i];
                }
            }
            return null;
        }

        public static double fv (double rate, double nper, double pmt, double pv, double type) {
            if (rate == 0) return -(pv + pmt * nper);
            double f = Math.pow (1 + rate, nper);
            return -(pv * f + pmt * (1 + rate * type) * (f - 1) / rate);
        }

        public static double pmt (double rate, double nper, double pv, double fv_v, double type) {
            if (rate == 0) return -(pv + fv_v) / nper;
            double f = Math.pow (1 + rate, nper);
            return -(rate * (pv * f + fv_v)) / ((1 + rate * type) * (f - 1));
        }

        private static double ipmt (double rate, double per, double nper, double pv, double fv_v, double type) {
            double p = pmt (rate, nper, pv, fv_v, type);
            double interest = fv (rate, per - 1, p, pv, type) * rate;
            if (type == 1) {
                if (per == 1) return 0;
                interest = (fv (rate, per - 2, p, pv, type) - p) * rate;
            }
            return interest;
        }

        public static void register () {
            add ("PMT", 3, 5, "PMT(rate, periods, present, [future], [type])", _("The payment of a loan"), (ev, a) => {
                double[] v = new double[5];
                var e = nums (ev, a, 0, 5, v, { 0, 0, 0, 0, 0 });
                if (e != null) return e;
                if (v[1] == 0) return Value.err (ErrorKind.NUM);
                return Value.num (pmt (v[0], v[1], v[2], v[3], v[4] != 0 ? 1 : 0));
            });
            add ("FV", 3, 5, "FV(rate, periods, payment, [present], [type])", _("The future value of an investment"), (ev, a) => {
                double[] v = new double[5];
                var e = nums (ev, a, 0, 5, v, { 0, 0, 0, 0, 0 });
                if (e != null) return e;
                return Value.num (fv (v[0], v[1], v[2], v[3], v[4] != 0 ? 1 : 0));
            });
            add ("PV", 3, 5, "PV(rate, periods, payment, [future], [type])", _("The present value of an investment"), (ev, a) => {
                double[] v = new double[5];
                var e = nums (ev, a, 0, 5, v, { 0, 0, 0, 0, 0 });
                if (e != null) return e;
                double rate = v[0], n = v[1], p = v[2], f = v[3], t = v[4] != 0 ? 1 : 0;
                if (rate == 0) return Value.num (-(f + p * n));
                double g = Math.pow (1 + rate, n);
                return Value.num (-(f + p * (1 + rate * t) * (g - 1) / rate) / g);
            });
            add ("NPER", 3, 5, "NPER(rate, payment, present, [future], [type])", _("The number of payment periods"), (ev, a) => {
                double[] v = new double[5];
                var e = nums (ev, a, 0, 5, v, { 0, 0, 0, 0, 0 });
                if (e != null) return e;
                double rate = v[0], p = v[1], pv = v[2], f = v[3], t = v[4] != 0 ? 1 : 0;
                if (rate == 0) {
                    if (p == 0) return Value.err (ErrorKind.NUM);
                    return Value.num (-(pv + f) / p);
                }
                double num = p * (1 + rate * t) - f * rate;
                double den = pv * rate + p * (1 + rate * t);
                if (num / den <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (Math.log (num / den) / Math.log (1 + rate));
            });
            add ("RATE", 3, 6, "RATE(periods, payment, present, [future], [type], [guess])", _("The interest rate per period"), (ev, a) => {
                double[] v = new double[6];
                var e = nums (ev, a, 0, 6, v, { 0, 0, 0, 0, 0, 0.1 });
                if (e != null) return e;
                double n = v[0], p = v[1], pv = v[2], f = v[3], t = v[4] != 0 ? 1 : 0, r = v[5];
                for (int i = 0; i < 100; i++) {
                    double y = f - fv (r, n, p, pv, t);
                    double h = 1e-7;
                    double dy = ((f - fv (r + h, n, p, pv, t)) - y) / h;
                    if (dy == 0 || y.is_nan ()) break;
                    double nr = r - y / dy;
                    if (Math.fabs (nr - r) < 1e-10) return Value.num (nr);
                    r = nr;
                }
                return Value.err (ErrorKind.NUM);
            });
            add ("IPMT", 4, 6, "IPMT(rate, period, periods, present, [future], [type])", _("The interest part of a payment"), (ev, a) => {
                double[] v = new double[6];
                var e = nums (ev, a, 0, 6, v, { 0, 0, 0, 0, 0, 0 });
                if (e != null) return e;
                if (v[1] < 1 || v[1] > v[2]) return Value.err (ErrorKind.NUM);
                return Value.num (ipmt (v[0], v[1], v[2], v[3], v[4], v[5] != 0 ? 1 : 0));
            });
            add ("PPMT", 4, 6, "PPMT(rate, period, periods, present, [future], [type])", _("The principal part of a payment"), (ev, a) => {
                double[] v = new double[6];
                var e = nums (ev, a, 0, 6, v, { 0, 0, 0, 0, 0, 0 });
                if (e != null) return e;
                if (v[1] < 1 || v[1] > v[2]) return Value.err (ErrorKind.NUM);
                double t = v[5] != 0 ? 1 : 0;
                return Value.num (pmt (v[0], v[2], v[3], v[4], t) - ipmt (v[0], v[1], v[2], v[3], v[4], t));
            });
            add ("NPV", 2, -1, "NPV(rate, value1, ...)", _("The net present value of cash flows"), (ev, a) => {
                double rate;
                var e = ev.arg_number (a[0], out rate);
                if (e != null) return e;
                var list = new Gee.ArrayList<double?> ();
                if ((e = ev.numbers (a[1:a.length], list)) != null) return e;
                double total = 0;
                for (int i = 0; i < list.size; i++) total += list[i] / Math.pow (1 + rate, i + 1);
                return Value.num (total);
            });
            add ("IRR", 1, 2, "IRR(values, [guess])", _("The internal rate of return"), (ev, a) => {
                var list = new Gee.ArrayList<double?> ();
                var e = ev.numbers ({ a[0] }, list);
                if (e != null) return e;
                double r = 0.1;
                if (a.length > 1 && (e = ev.arg_number (a[1], out r)) != null) return e;
                for (int it = 0; it < 100; it++) {
                    double f = 0, df = 0;
                    for (int i = 0; i < list.size; i++) {
                        double p = Math.pow (1 + r, i);
                        f += list[i] / p;
                        df -= i * list[i] / (p * (1 + r));
                    }
                    if (df == 0) break;
                    double nr = r - f / df;
                    if (Math.fabs (nr - r) < 1e-10) return Value.num (nr);
                    r = nr;
                }
                return Value.err (ErrorKind.NUM);
            });
            add ("XNPV", 3, 3, "XNPV(rate, values, dates)", _("The net present value of dated cash flows"), (ev, a) => {
                double rate;
                var e = ev.arg_number (a[0], out rate);
                if (e != null) return e;
                var vals = new Gee.ArrayList<double?> ();
                var dates = new Gee.ArrayList<double?> ();
                if ((e = ev.numbers ({ a[1] }, vals)) != null) return e;
                if ((e = ev.numbers ({ a[2] }, dates)) != null) return e;
                if (vals.size != dates.size || vals.size == 0) return Value.err (ErrorKind.NUM);
                double total = 0;
                for (int i = 0; i < vals.size; i++) total += vals[i] / Math.pow (1 + rate, (dates[i] - dates[0]) / 365);
                return Value.num (total);
            });
            add ("XIRR", 2, 3, "XIRR(values, dates, [guess])", _("The internal rate of return of dated cash flows"), (ev, a) => {
                var vals = new Gee.ArrayList<double?> ();
                var dates = new Gee.ArrayList<double?> ();
                var e = ev.numbers ({ a[0] }, vals);
                if (e != null) return e;
                if ((e = ev.numbers ({ a[1] }, dates)) != null) return e;
                if (vals.size != dates.size || vals.size == 0) return Value.err (ErrorKind.NUM);
                double r = 0.1;
                if (a.length > 2 && (e = ev.arg_number (a[2], out r)) != null) return e;
                for (int it = 0; it < 100; it++) {
                    double f = 0, df = 0;
                    for (int i = 0; i < vals.size; i++) {
                        double t = (dates[i] - dates[0]) / 365;
                        double p = Math.pow (1 + r, t);
                        f += vals[i] / p;
                        df -= t * vals[i] / (p * (1 + r));
                    }
                    if (df == 0) break;
                    double nr = r - f / df;
                    if (Math.fabs (nr - r) < 1e-10) return Value.num (nr);
                    r = nr;
                }
                return Value.err (ErrorKind.NUM);
            });
            add ("SLN", 3, 3, "SLN(cost, salvage, life)", _("Straight-line depreciation"), (ev, a) => {
                double[] v = new double[3];
                var e = nums (ev, a, 0, 3, v, { 0, 0, 0 });
                if (e != null) return e;
                if (v[2] == 0) return Value.err (ErrorKind.DIV0);
                return Value.num ((v[0] - v[1]) / v[2]);
            });
            add ("SYD", 4, 4, "SYD(cost, salvage, life, period)", _("Sum-of-years depreciation"), (ev, a) => {
                double[] v = new double[4];
                var e = nums (ev, a, 0, 4, v, { 0, 0, 0, 0 });
                if (e != null) return e;
                if (v[2] <= 0 || v[3] < 1 || v[3] > v[2]) return Value.err (ErrorKind.NUM);
                return Value.num ((v[0] - v[1]) * (v[2] - v[3] + 1) * 2 / (v[2] * (v[2] + 1)));
            });
            add ("DDB", 4, 5, "DDB(cost, salvage, life, period, [factor])", _("Double-declining balance depreciation"), (ev, a) => {
                double[] v = new double[5];
                var e = nums (ev, a, 0, 5, v, { 0, 0, 0, 0, 2 });
                if (e != null) return e;
                double cost = v[0], salvage = v[1], life = v[2], period = v[3], factor = v[4];
                if (life <= 0 || period < 1 || period > life) return Value.err (ErrorKind.NUM);
                double book = cost, dep = 0;
                for (int p = 1; p <= (int) period; p++) {
                    dep = double.min (book * factor / life, double.max (book - salvage, 0));
                    book -= dep;
                }
                return Value.num (dep);
            });
            add ("EFFECT", 2, 2, "EFFECT(nominal_rate, periods)", _("The effective annual interest rate"), (ev, a) => {
                double[] v = new double[2];
                var e = nums (ev, a, 0, 2, v, { 0, 0 });
                if (e != null) return e;
                double n = Math.trunc (v[1]);
                if (v[0] <= 0 || n < 1) return Value.err (ErrorKind.NUM);
                return Value.num (Math.pow (1 + v[0] / n, n) - 1);
            });
            add ("NOMINAL", 2, 2, "NOMINAL(effect_rate, periods)", _("The nominal annual interest rate"), (ev, a) => {
                double[] v = new double[2];
                var e = nums (ev, a, 0, 2, v, { 0, 0 });
                if (e != null) return e;
                double n = Math.trunc (v[1]);
                if (v[0] <= 0 || n < 1) return Value.err (ErrorKind.NUM);
                return Value.num ((Math.pow (1 + v[0], 1 / n) - 1) * n);
            });
        }
    }
}
