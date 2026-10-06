namespace Singularity.Apps.Spreadsheet {

    public class LocaleInfo {
        public char decimal_sep = '.';
        public char thousands_sep = ',';
        public string date_order = "MDY";
        public char date_sep = '/';
        private static LocaleInfo? instance;

        public static LocaleInfo get () {
            if (instance == null) {
                instance = new LocaleInfo ();
                instance.detect ();
            }
            return instance;
        }

        public static void set_c () {
            instance = new LocaleInfo ();
        }

        private void detect () {
            string probe = "%.1f".printf (1.5);
            if (probe.length == 3) decimal_sep = probe[1];
            thousands_sep = decimal_sep == ',' ? '.' : ',';
            var dt = new DateTime.local (2003, 11, 22, 0, 0, 0);
            string x = dt.format ("%x");
            int d = x.index_of ("22");
            int m = x.index_of ("11");
            int y = x.index_of ("03");
            if (d >= 0 && m >= 0 && y >= 0) {
                if (y < m && m < d) date_order = "YMD";
                else if (d < m) date_order = "DMY";
                else date_order = "MDY";
                for (int i = 0; i < x.length; i++) {
                    if (!x[i].isdigit ()) {
                        date_sep = x[i];
                        break;
                    }
                }
            }
        }

        public string short_date_format () {
            string s = date_sep.to_string ();
            switch (date_order) {
                case "DMY": return "dd" + s + "mm" + s + "yyyy";
                case "YMD": return "yyyy" + s + "mm" + s + "dd";
                default: return "m" + s + "d" + s + "yyyy";
            }
        }
    }

    public class DateSerial {
        private static uint32 epoch_julian () {
            var d = GLib.Date ();
            d.set_dmy (30, 12, 1899);
            return d.get_julian ();
        }

        public static double from_ymd (int y, int m, int d, bool d1904 = false) {
            if (y < 100 && y >= 0) y += 1900;
            while (m > 12) {
                m -= 12;
                y++;
            }
            while (m < 1) {
                m += 12;
                y--;
            }
            if (y < 1 || y > 9999) return -1;
            if (!d1904 && y == 1900 && m <= 2) {
                double early = (m - 1) * 31 + d;
                if (early >= 0) return early;
            }
            var date = GLib.Date ();
            date.set_dmy (1, (DateMonth) m, (DateYear) y);
            if (d > 1) date.add_days (d - 1);
            else if (d < 1) date.subtract_days (1 - d);
            double serial = (double) date.get_julian () - epoch_julian ();
            if (!d1904 && serial < 61) serial -= 1;
            if (d1904) serial -= 1462;
            return serial;
        }

        public static bool to_ymd (double serial, out int y, out int m, out int d, bool d1904 = false) {
            y = m = d = 0;
            double s = Math.floor (serial);
            if (d1904) s += 1462;
            if (s < 0 || s > 2958465) return false;
            if (!d1904 && s == 60) {
                y = 1900;
                m = 2;
                d = 29;
                return true;
            }
            if (s < 1 && !d1904) {
                y = 1900;
                m = 1;
                d = 0;
                return true;
            }
            if (!d1904 && s < 60) s += 1;
            var date = GLib.Date ();
            date.set_julian ((uint32) (epoch_julian () + s));
            y = date.get_year ();
            m = date.get_month ();
            d = date.get_day ();
            return true;
        }

        public static int weekday (double serial) {
            int s = (int) Math.floor (serial);
            if (s >= 60) return ((s - 1) % 7 + 7) % 7;
            return (s % 7 + 7) % 7;
        }

        public static void to_hms (double serial, out int h, out int mi, out int sec, out double frac) {
            double day = serial - Math.floor (serial);
            double total = day * 86400.0;
            double rounded = Math.round (total * 1000) / 1000;
            int whole = (int) Math.floor (rounded);
            frac = rounded - whole;
            if (whole >= 86400) whole = 86399;
            h = whole / 3600;
            mi = (whole % 3600) / 60;
            sec = whole % 60;
        }

        public static double now () {
            var t = new DateTime.now_local ();
            return from_ymd (t.get_year (), t.get_month (), t.get_day_of_month ()) + (t.get_hour () * 3600 + t.get_minute () * 60 + t.get_seconds ()) / 86400.0;
        }
    }

    public class ParsedInput {
        public Value value;
        public string format = "";
    }

    public class Input {
        public static ParsedInput parse (string raw) {
            var r = new ParsedInput ();
            string t = raw.strip ();
            if (raw == "") {
                r.value = Value.empty ();
                return r;
            }
            if (raw.has_prefix ("'")) {
                r.value = Value.str (raw.substring (1));
                return r;
            }
            string up = t.up ();
            if (up == "TRUE" || up == "FALSE") {
                r.value = Value.boolean (up == "TRUE");
                return r;
            }
            var e = ErrorKind.parse (up);
            if (e != ErrorKind.NONE) {
                r.value = Value.err (e);
                return r;
            }
            double n;
            string fmt;
            if (parse_number (t, out n, out fmt)) {
                r.value = Value.num (n);
                r.format = fmt;
                return r;
            }
            if (parse_date_time (t, out n, out fmt)) {
                r.value = Value.num (n);
                r.format = fmt;
                return r;
            }
            r.value = Value.str (raw);
            return r;
        }

        public static bool parse_number (string text, out double n, out string fmt) {
            n = 0;
            fmt = "";
            var loc = LocaleInfo.get ();
            string t = text.strip ();
            if (t == "") return false;
            bool neg = false;
            if (t.has_prefix ("(") && t.has_suffix (")")) {
                neg = true;
                t = t.substring (1, t.length - 2).strip ();
            }
            string currency = "";
            bool currency_after = false;
            string[] symbols = { "$", "€", "£", "¥", "₹", "CHF" };
            foreach (string sym in symbols) {
                if (t.has_prefix (sym)) {
                    currency = sym;
                    t = t.substring (sym.length).strip ();
                    break;
                }
                if (t.has_prefix ("-" + sym)) {
                    currency = sym;
                    neg = !neg;
                    t = t.substring (sym.length + 1).strip ();
                    break;
                }
                if (t.has_suffix (sym)) {
                    currency = sym;
                    currency_after = true;
                    t = t.substring (0, t.length - sym.length).strip ();
                    break;
                }
            }
            bool percent = false;
            if (t.has_suffix ("%")) {
                percent = true;
                t = t.substring (0, t.length - 1).strip ();
            }
            if (t.has_prefix ("-")) {
                neg = !neg;
                t = t.substring (1);
            } else if (t.has_prefix ("+")) {
                t = t.substring (1);
            }
            if (t == "") return false;
            var sb = new StringBuilder ();
            bool seen_dec = false;
            bool seen_thousands = false;
            bool seen_exp = false;
            int decimals = 0;
            int digits_since_group = 0;
            bool any_digit = false;
            for (int i = 0; i < t.length; i++) {
                char c = t[i];
                if (c.isdigit ()) {
                    sb.append_c (c);
                    any_digit = true;
                    if (seen_dec && !seen_exp) decimals++;
                    digits_since_group++;
                    continue;
                }
                if (!seen_exp && !seen_dec && c == loc.thousands_sep && any_digit && !(c == '.' && loc.decimal_sep == '.')) {
                    if (seen_thousands && digits_since_group != 3) return false;
                    seen_thousands = true;
                    digits_since_group = 0;
                    continue;
                }
                if (!seen_exp && !seen_dec && (c == loc.decimal_sep || (c == '.' && loc.decimal_sep != '.' && !seen_thousands && t.index_of_char (loc.decimal_sep) < 0 && loc.thousands_sep != '.'))) {
                    if (seen_thousands && digits_since_group != 3) return false;
                    seen_dec = true;
                    sb.append_c ('.');
                    continue;
                }
                if ((c == 'e' || c == 'E') && any_digit && !seen_exp) {
                    seen_exp = true;
                    sb.append_c ('e');
                    if (i + 1 < t.length && (t[i + 1] == '+' || t[i + 1] == '-')) {
                        sb.append_c (t[i + 1]);
                        i++;
                    }
                    continue;
                }
                return false;
            }
            if (!any_digit) return false;
            if (seen_thousands && !seen_dec && digits_since_group != 3) return false;
            string num = sb.str;
            if (num.has_suffix ("e") || num.has_suffix ("+") || num.has_suffix ("-")) return false;
            n = double.parse (num);
            if (neg) n = -n;
            string dec = decimals > 0 ? "." + string.nfill (decimals, '0') : "";
            if (percent) {
                n /= 100;
                fmt = "0" + dec + "%";
            } else if (currency != "") {
                string d2 = decimals > 0 ? dec : ".00";
                fmt = currency_after ? "#,##0" + d2 + " " + currency : currency + "#,##0" + d2;
            } else if (seen_exp) {
                fmt = "0" + (decimals > 0 ? dec : ".00") + "E+00";
            } else if (seen_thousands) {
                fmt = "#,##0" + dec;
            }
            return true;
        }

        public static bool parse_date_time (string text, out double n, out string fmt) {
            n = 0;
            fmt = "";
            string t = text.strip ();
            double date_part = 0;
            double time_part = 0;
            bool has_date = false;
            bool has_time = false;
            string rest = t;
            int sp = t.index_of_char (' ');
            int tpos = t.index_of_char ('T');
            string dstr = t;
            string tstr = "";
            if (t.contains (":")) {
                if (sp > 0 && (t.index_of_char (':') > sp)) {
                    dstr = t.substring (0, sp);
                    tstr = t.substring (sp + 1).strip ();
                } else if (tpos == 10) {
                    dstr = t.substring (0, 10);
                    tstr = t.substring (11);
                } else {
                    dstr = "";
                    tstr = t;
                }
            }
            if (dstr != "") {
                if (!parse_date (dstr, out date_part, out fmt)) return false;
                has_date = true;
            }
            if (tstr != "") {
                string tfmt;
                if (!parse_time (tstr, out time_part, out tfmt)) return false;
                has_time = true;
                fmt = has_date ? fmt + " " + tfmt : tfmt;
            }

            n = date_part + time_part;
            return has_date || has_time;
        }

        private static bool parse_date (string s, out double serial, out string fmt) {
            serial = 0;
            fmt = "";
            var loc = LocaleInfo.get ();
            char sep = 0;
            foreach (char c in new char[] { '-', '/', '.' }) {
                if (s.index_of_char (c) > 0) {
                    sep = c;
                    break;
                }
            }
            if (sep == 0) return false;
            string[] parts = s.split (sep.to_string ());
            if (parts.length < 2 || parts.length > 3) return false;
            int[] v = {};
            foreach (string p in parts) {
                if (p == "" || p.length > 4) return false;
                for (int i = 0; i < p.length; i++) if (!p[i].isdigit ()) return false;
                v += int.parse (p);
            }
            int y, m, d;
            if (parts[0].length == 4) {
                if (parts.length != 3) return false;
                y = v[0];
                m = v[1];
                d = v[2];
                fmt = "yyyy-mm-dd";
            } else if (parts.length == 2) {
                var now = new DateTime.now_local ();
                y = now.get_year ();
                if (loc.date_order == "DMY") {
                    d = v[0];
                    m = v[1];
                    fmt = "d-mmm";
                } else {
                    m = v[0];
                    d = v[1];
                    fmt = "mmm-d";
                }
                if (sep == '.' && loc.date_order != "DMY") return false;
            } else {
                y = v[2];
                if (parts[2].length == 2) y += y < 30 ? 2000 : 1900;
                else if (parts[2].length != 4) return false;
                if (loc.date_order == "DMY" || sep == '.') {
                    d = v[0];
                    m = v[1];
                } else {
                    m = v[0];
                    d = v[1];
                }
                fmt = loc.short_date_format ();
            }
            if (m < 1 || m > 12 || d < 1 || d > 31) return false;
            if (!GLib.Date.valid_dmy ((DateDay) d, (DateMonth) m, (DateYear) y)) return false;
            serial = DateSerial.from_ymd (y, m, d);
            return serial >= 0;
        }

        private static bool parse_time (string s, out double frac, out string fmt) {
            frac = 0;
            fmt = "";
            string t = s.strip ().up ();
            bool pm = false;
            bool ampm = false;
            if (t.has_suffix ("AM") || t.has_suffix ("PM")) {
                ampm = true;
                pm = t.has_suffix ("PM");
                t = t.substring (0, t.length - 2).strip ();
            }
            string[] parts = t.split (":");
            if (parts.length < 2 || parts.length > 3) return false;
            double[] v = {};
            foreach (string p in parts) {
                if (p == "") return false;
                for (int i = 0; i < p.length; i++) if (!p[i].isdigit () && p[i] != '.') return false;
                v += double.parse (p);
            }
            double h = v[0];
            if (ampm) {
                if (h < 1 || h > 12) return false;
                if (h == 12) h = 0;
                if (pm) h += 12;
            }
            if (v[1] >= 60 || (v.length == 3 && v[2] >= 60)) return false;
            double secs = h * 3600 + v[1] * 60 + (v.length == 3 ? v[2] : 0);
            frac = secs / 86400.0;
            fmt = (v.length == 3 ? "h:mm:ss" : "h:mm") + (ampm ? " AM/PM" : "");
            return true;
        }
    }

    public class NumberFormat {
        private class Section {
            public string code = "";
            public string color = "";
            public string cond_op = "";
            public double cond_value;
        }

        public static bool is_date_format (string code) {
            string c = strip_literals (code).down ();
            if (c.contains ("general")) return false;
            return c.contains ("y") || c.contains ("d") || c.contains ("h") || c.contains ("s") || (c.contains ("m") && !c.contains ("0") && !c.contains ("#"));
        }

        private static string strip_literals (string code) {
            var sb = new StringBuilder ();
            bool quote = false;
            bool bracket = false;
            for (int i = 0; i < code.length; i++) {
                char c = code[i];
                if (quote) {
                    if (c == '"') quote = false;
                    continue;
                }
                if (bracket) {
                    if (c == ']') bracket = false;
                    continue;
                }
                if (c == '"') {
                    quote = true;
                    continue;
                }
                if (c == '[') {
                    string rest = code.substring (i).down ();
                    if (rest.has_prefix ("[h") || rest.has_prefix ("[m") || rest.has_prefix ("[s")) {
                        sb.append ("h");
                    }
                    bracket = true;
                    continue;
                }
                if (c == '\\' || c == '_' || c == '*') {
                    i++;
                    continue;
                }
                sb.append_c (c);
            }
            return sb.str;
        }

        private static Section[] sections (string code) {
            Section[] out_s = {};
            var sb = new StringBuilder ();
            bool quote = false;
            for (int i = 0; i < code.length; i++) {
                char c = code[i];
                if (c == '"') quote = !quote;
                if (c == '\\' && i + 1 < code.length) {
                    sb.append_c (c);
                    sb.append_c (code[++i]);
                    continue;
                }
                if (c == ';' && !quote) {
                    out_s += make_section (sb.str);
                    sb.truncate ();
                    continue;
                }
                sb.append_c (c);
            }
            out_s += make_section (sb.str);
            return out_s;
        }

        private static Section make_section (string raw) {
            var s = new Section ();
            string rest = raw;
            var sb = new StringBuilder ();
            int i = 0;
            while (i < rest.length) {
                if (rest[i] == '[') {
                    int close = rest.index_of_char (']', i);
                    if (close < 0) break;
                    string inner = rest.substring (i + 1, close - i - 1);
                    string low = inner.down ();
                    string[] colors = { "black", "white", "red", "green", "blue", "yellow", "magenta", "cyan" };
                    bool handled = false;
                    foreach (string col in colors) {
                        if (low == col) {
                            s.color = col;
                            handled = true;
                        }
                    }
                    if (!handled && low.has_prefix ("color")) {
                        s.color = "color" + low.substring (5);
                        handled = true;
                    }
                    if (!handled && (inner.has_prefix (">") || inner.has_prefix ("<") || inner.has_prefix ("="))) {
                        int k = 0;
                        while (k < inner.length && "<>=".index_of_char (inner[k]) >= 0) k++;
                        s.cond_op = inner.substring (0, k);
                        s.cond_value = double.parse (inner.substring (k));
                        handled = true;
                    }
                    if (!handled && inner.has_prefix ("$")) {
                        int dash = inner.index_of_char ('-');
                        string sym = dash > 0 ? inner.substring (1, dash - 1) : inner.substring (1);
                        sb.append ("\"" + sym + "\"");
                        handled = true;
                    }
                    if (!handled) sb.append ("[" + inner + "]");
                    i = close + 1;
                    continue;
                }
                sb.append_c (rest[i]);
                i++;
            }
            s.code = sb.str;
            return s;
        }

        private static bool cond_matches (Section s, double v) {
            switch (s.cond_op) {
                case ">": return v > s.cond_value;
                case ">=": return v >= s.cond_value;
                case "<": return v < s.cond_value;
                case "<=": return v <= s.cond_value;
                case "=": return v == s.cond_value;
                case "<>": return v != s.cond_value;
                default: return true;
            }
        }

        public static string format_value (Value v, string code, out string color, bool d1904 = false) {
            color = "";
            switch (v.kind) {
                case ValueKind.NUMBER:
                    return format (v.number, code, out color, d1904);
                case ValueKind.TEXT:
                    var secs = sections (code);
                    if (secs.length >= 4 || (secs.length == 1 && secs[0].code.contains ("@"))) {
                        var s = secs.length >= 4 ? secs[3] : secs[0];
                        color = s.color;
                        return literal_text (s.code, v.text);
                    }
                    return v.text;
                case ValueKind.BOOL:
                    return v.number != 0 ? "TRUE" : "FALSE";
                case ValueKind.ERROR:
                    return v.error.to_string ();
                default:
                    return "";
            }
        }

        private static string literal_text (string code, string text) {
            var sb = new StringBuilder ();
            for (int i = 0; i < code.length; i++) {
                char c = code[i];
                if (c == '@') sb.append (text);
                else if (c == '"') {
                    int close = code.index_of_char ('"', i + 1);
                    if (close < 0) break;
                    sb.append (code.substring (i + 1, close - i - 1));
                    i = close;
                } else if (c == '\\' && i + 1 < code.length) {
                    sb.append_c (code[++i]);
                } else if (c == '_' && i + 1 < code.length) {
                    sb.append_c (' ');
                    i++;
                } else if (c == '*' && i + 1 < code.length) {
                    i++;
                } else {
                    sb.append_c (c);
                }
            }
            return sb.str;
        }

        public static string format (double value, string code, out string color, bool d1904 = false) {
            color = "";
            if (code == "" || code.down () == "general") return general (value);
            var secs = sections (code);
            Section s = secs[0];
            double v = value;
            bool has_cond = false;
            foreach (var sec in secs) if (sec.cond_op != "") has_cond = true;
            if (has_cond) {
                if (secs[0].cond_op != "" && cond_matches (secs[0], v)) s = secs[0];
                else if (secs.length > 1 && secs[1].cond_op != "" && cond_matches (secs[1], v)) s = secs[1];
                else if (secs.length > 2) s = secs[2];
                else if (secs.length > 1 && secs[1].cond_op == "") s = secs[1];
                else s = secs[0];
                if (s != secs[0] && v < 0 && s.cond_op == "") v = -v;
            } else if (v < 0 && secs.length >= 2) {
                s = secs[1];
                v = -v;
            } else if (v == 0 && secs.length >= 3) {
                s = secs[2];
            }
            color = s.color;
            if (s.code.down () == "general") return (value < 0 && s != secs[0] ? "-" : "") + general (v);
            if (is_date_format (s.code)) return format_date (v, s.code, d1904);
            return format_numeric (v, s.code, s == secs[0] && value < 0 && secs.length < 2);
        }

        public static string general (double value) {
            string s = Value.format_number_general (value);
            var loc = LocaleInfo.get ();
            if (loc.decimal_sep != '.') s = s.replace (".", loc.decimal_sep.to_string ());
            return s;
        }

        private static string format_numeric (double value, string code, bool add_minus) {
            var loc = LocaleInfo.get ();
            string c = code;
            int percent = 0;
            bool in_quote = false;
            for (int i = 0; i < c.length; i++) {
                if (c[i] == '"') in_quote = !in_quote;
                else if (c[i] == '\\') i++;
                else if (!in_quote && c[i] == '%') percent++;
            }
            double v = value;
            for (int i = 0; i < percent; i++) v *= 100;

            int first = -1;
            int last = -1;
            in_quote = false;
            for (int i = 0; i < c.length; i++) {
                char ch = c[i];
                if (ch == '"') {
                    in_quote = !in_quote;
                    continue;
                }
                if (in_quote) continue;
                if (ch == '\\' || ch == '_' || ch == '*') {
                    i++;
                    continue;
                }
                if (ch == '0' || ch == '#' || ch == '?' || ch == '.' || (ch == ',' && first >= 0)) {
                    if (first < 0) first = i;
                    last = i;
                }
                if ((ch == 'E' || ch == 'e') && first >= 0 && i + 1 < c.length && (c[i + 1] == '+' || c[i + 1] == '-')) {
                    int j = i + 2;
                    while (j < c.length && (c[j] == '0' || c[j] == '#')) j++;
                    last = j - 1;
                    i = j - 1;
                }
                if (ch == '/' && first >= 0) {
                    int j = i + 1;
                    while (j < c.length && (c[j] == '?' || c[j] == '#' || c[j].isdigit ())) j++;
                    last = j - 1;
                    i = j - 1;
                }
            }
            if (first < 0) {
                string lit = literal_text (c, "");
                return (add_minus && value < 0 ? "-" : "") + lit;
            }
            string prefix = literal_text (c.substring (0, first), "");
            string suffix = literal_text (c.substring (last + 1), "");
            string num = c.substring (first, last - first + 1);
            string body;
            if (num.contains ("/")) {
                body = fraction (v, num);
            } else if (num.contains ("E") || num.contains ("e")) {
                body = scientific (v, num, loc);
            } else {
                while (num.has_suffix (",")) {
                    v /= 1000;
                    num = num.substring (0, num.length - 1);
                }
                body = digits (v, num, loc);
            }
            bool neg = add_minus && value < 0 && body.replace ("0", "").replace (loc.decimal_sep.to_string (), "").replace (loc.thousands_sep.to_string (), "").strip () != "";
            return (neg ? "-" : "") + prefix + body + suffix;
        }

        private static string digits (double value, string pattern, LocaleInfo loc) {
            double v = Math.fabs (value);
            int dot = pattern.index_of_char ('.');
            string ipat = dot >= 0 ? pattern.substring (0, dot) : pattern;
            string fpat = dot >= 0 ? pattern.substring (dot + 1) : "";
            bool grouping = ipat.contains (",");
            ipat = ipat.replace (",", "");
            int fmax = 0;
            int fmin = 0;
            for (int i = 0; i < fpat.length; i++) {
                if (fpat[i] == '0' || fpat[i] == '#' || fpat[i] == '?') fmax++;
                if (fpat[i] == '0') fmin = fmax;
            }
            string fixed_s = Value.fixed (v, fmax);
            int d = fixed_s.index_of_char ('.');
            string ip = d >= 0 ? fixed_s.substring (0, d) : fixed_s;
            string fp = d >= 0 ? fixed_s.substring (d + 1) : "";
            while (fp.length > fmin && fp.has_suffix ("0")) fp = fp.substring (0, fp.length - 1);
            int imin = 0;
            for (int i = 0; i < ipat.length; i++) if (ipat[i] == '0') imin = ipat.length - i;
            if (ip == "0" && imin == 0) ip = "";
            while (ip.length < imin) ip = "0" + ip;
            if (grouping && ip.length > 3) {
                var sb = new StringBuilder ();
                int lead = ip.length % 3;
                for (int i = 0; i < ip.length; i++) {
                    if (i > 0 && (i - lead) % 3 == 0) sb.append_c (loc.thousands_sep);
                    sb.append_c (ip[i]);
                }
                ip = sb.str;
            }
            if (fpat.contains ("?")) {
                int pad = fmax - fp.length;
                fp += string.nfill (pad > 0 ? pad : 0, ' ');
            }
            if (dot >= 0 && (fp.length > 0 || fmin > 0)) return ip + loc.decimal_sep.to_string () + fp;
            if (dot >= 0 && fmax > 0) return ip + loc.decimal_sep.to_string ();
            return ip;
        }

        private static string scientific (double value, string pattern, LocaleInfo loc) {
            int e = pattern.index_of_char ('E');
            if (e < 0) e = pattern.index_of_char ('e');
            string mpat = pattern.substring (0, e);
            string epat = pattern.substring (e + 2);
            bool plus = pattern[e + 1] == '+';
            double v = Math.fabs (value);
            int exp = v == 0 ? 0 : (int) Math.floor (Math.log10 (v));
            int ilen = 0;
            int dot = mpat.index_of_char ('.');
            string ipart = dot >= 0 ? mpat.substring (0, dot) : mpat;
            for (int i = 0; i < ipart.length; i++) if (ipart[i] == '0' || ipart[i] == '#') ilen++;
            if (ilen > 1) exp = (int) Math.floor ((double) exp / ilen) * ilen;
            double mant = v / Math.pow (10, exp);
            string m = digits (mant, mpat, loc);
            int fdigits = dot >= 0 ? mpat.length - dot - 1 : 0;
            if (Value.fixed (mant, fdigits).has_prefix ("10") && ilen <= 1) {
                exp++;
                m = digits (v / Math.pow (10, exp), mpat, loc);
            }
            string es = exp.abs ().to_string ();
            while (es.length < epat.length) es = "0" + es;
            return m + "E" + (exp < 0 ? "-" : (plus ? "+" : "")) + es;
        }

        private static string fraction (double value, string pattern) {
            double v = Math.fabs (value);
            int slash = pattern.index_of_char ('/');
            string left = pattern.substring (0, slash).strip ();
            string den_pat = pattern.substring (slash + 1);
            bool whole = left.contains (" ");
            double ip = whole ? Math.floor (v) : 0;
            double f = v - ip;
            int best_n = 0;
            int best_d = 1;
            if (den_pat.length > 0 && den_pat[0].isdigit ()) {
                best_d = int.parse (den_pat);
                best_n = (int) Math.round (f * best_d);
            } else {
                int max_d = (int) Math.pow (10, den_pat.length) - 1;
                double best_err = 2;
                for (int d = 1; d <= max_d; d++) {
                    int n = (int) Math.round (f * d);
                    double err = Math.fabs (f - (double) n / d);
                    if (err < best_err - 1e-12) {
                        best_err = err;
                        best_n = n;
                        best_d = d;
                    }
                }
            }
            if (best_n == best_d && whole) {
                ip += 1;
                best_n = 0;
            }
            string frac = best_n == 0 ? string.nfill (den_pat.length * 2 + 1, ' ') : "%d/%d".printf (best_n, best_d);
            if (whole) return (ip > 0 || best_n == 0 ? Value.fixed (ip, 0) : "") + (best_n == 0 ? "" : " " + frac);
            return best_n == 0 ? "0" : frac;
        }

        private static string format_date (double serial, string code, bool d1904) {
            int y, m, d, h, mi, sec;
            double frac;
            if (!DateSerial.to_ymd (serial, out y, out m, out d, d1904)) return string.nfill (8, '#');
            DateSerial.to_hms (serial, out h, out mi, out sec, out frac);
            bool ampm = code.up ().contains ("AM/PM") || code.up ().contains ("A/P");
            var sb = new StringBuilder ();
            string low = code;
            int i = 0;
            bool last_was_hour = false;
            while (i < low.length) {
                char c = low[i];
                char lc = c.tolower ();
                if (c == '"') {
                    int close = low.index_of_char ('"', i + 1);
                    if (close < 0) break;
                    sb.append (low.substring (i + 1, close - i - 1));
                    i = close + 1;
                    continue;
                }
                if (c == '\\' && i + 1 < low.length) {
                    sb.append_c (low[i + 1]);
                    i += 2;
                    continue;
                }
                if (c == '_' || c == '*') {
                    if (c == '_') sb.append_c (' ');
                    i += 2;
                    continue;
                }
                if (c == '[') {
                    int close = low.index_of_char (']', i);
                    string inner = low.substring (i + 1, close - i - 1).down ();
                    double total = serial * 24;
                    if (inner.has_prefix ("h")) sb.append (((int) Math.floor (serial * 24 + 1e-9)).to_string ());
                    else if (inner.has_prefix ("m")) sb.append (((int) Math.floor (serial * 1440 + 1e-9)).to_string ());
                    else if (inner.has_prefix ("s")) sb.append (((int) Math.floor (serial * 86400 + 0.5)).to_string ());
                    if (inner.has_prefix ("h")) last_was_hour = true;
                    total = 0;
                    i = close + 1;
                    continue;
                }
                int run = 1;
                while (i + run < low.length && low[i + run].tolower () == lc) run++;
                if (low.substring (i).up ().has_prefix ("AM/PM")) {
                    sb.append (h >= 12 ? "PM" : "AM");
                    i += 5;
                    continue;
                }
                if (low.substring (i).up ().has_prefix ("A/P")) {
                    sb.append (h >= 12 ? "P" : "A");
                    i += 3;
                    continue;
                }
                switch (lc) {
                    case 'y':
                        sb.append (run <= 2 ? "%02d".printf (y % 100) : "%04d".printf (y));
                        break;
                    case 'd':
                        if (run == 1) sb.append (d.to_string ());
                        else if (run == 2) sb.append ("%02d".printf (d));
                        else {
                            var dt = new DateTime.local (y, m, int.max (d, 1), 0, 0, 0);
                            sb.append (dt.format (run == 3 ? "%a" : "%A"));
                        }
                        break;
                    case 'm':
                        bool minutes = last_was_hour || next_is_seconds (low, i + run);
                        if (minutes && run <= 2) {
                            sb.append (run == 1 ? mi.to_string () : "%02d".printf (mi));
                        } else if (run == 1) {
                            sb.append (m.to_string ());
                        } else if (run == 2) {
                            sb.append ("%02d".printf (m));
                        } else {
                            var dt = new DateTime.local (y, m, 1, 0, 0, 0);
                            string name = dt.format (run == 3 ? "%b" : "%B");
                            if (run == 5) name = name.substring (0, name.index_of_nth_char (1));
                            sb.append (name);
                        }
                        break;
                    case 'h':
                        int hh = h;
                        if (ampm) {
                            hh = h % 12;
                            if (hh == 0) hh = 12;
                        }
                        sb.append (run == 1 ? hh.to_string () : "%02d".printf (hh));
                        last_was_hour = true;
                        i += run;
                        continue;
                    case 's':
                        sb.append (run == 1 ? sec.to_string () : "%02d".printf (sec));
                        if (i + run < low.length && low[i + run] == '.') {
                            int z = 0;
                            int j = i + run + 1;
                            while (j < low.length && low[j] == '0') {
                                z++;
                                j++;
                            }
                            if (z > 0) {
                                string f = Value.fixed (frac, z);
                                sb.append (LocaleInfo.get ().decimal_sep.to_string () + f.substring (2));
                                i = j;
                                last_was_hour = false;
                                continue;
                            }
                        }
                        break;
                    default:
                        sb.append (low.substring (i, run));
                        break;
                }
                if (lc != ' ' && lc != ':' && lc != '/' && lc != '-' && lc != '.') last_was_hour = false;
                i += run;
            }
            return sb.str;
        }

        private static bool next_is_seconds (string code, int from) {
            for (int i = from; i < code.length; i++) {
                char c = code[i].tolower ();
                if (c == 's') return true;
                if (c == 'h' || c == 'd' || c == 'y' || c == 'm') return false;
            }
            return false;
        }
    }
}
