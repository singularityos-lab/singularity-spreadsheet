namespace Singularity.Apps.Spreadsheet {

    public class MoreTextFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Text", syntax, summary, (owned) impl);
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

        private static Regex? compile (string pattern, bool caseless, out Value? err) {
            err = null;
            try {
                var flags = RegexCompileFlags.OPTIMIZE;
                if (caseless) flags |= RegexCompileFlags.CASELESS;
                return new Regex (pattern, flags);
            } catch (RegexError e) {
                err = Value.err (ErrorKind.VALUE);
                return null;
            }
        }

        private static string[] texts_of (Evaluator ev, Value v, out Value? err) {
            err = null;
            string[] r = {};
            if (v.kind == ValueKind.RANGE || v.kind == ValueKind.ARRAY) {
                var m = ev.to_matrix (v);
                for (int i = 0; i < m.length[0]; i++) for (int j = 0; j < m.length[1]; j++) {
                    if (m[i, j].is_error ()) {
                        err = m[i, j];
                        return r;
                    }
                    r += Evaluator.to_text (m[i, j]);
                }
                return r;
            }
            if (v.is_error ()) {
                err = v;
                return r;
            }
            r += Evaluator.to_text (v);
            return r;
        }

        private static Regex? delimiter_regex (string[] delims, bool caseless) {
            var list = new Gee.ArrayList<string> ();
            foreach (string d in delims) if (d != "") list.add (d);
            if (list.size == 0) return null;
            list.sort ((a, b) => b.length - a.length);
            string[] parts = {};
            foreach (string d in list) parts += Regex.escape_string (d);
            try {
                return new Regex (string.joinv ("|", parts), caseless ? RegexCompileFlags.CASELESS : 0);
            } catch (RegexError e) {
                return null;
            }
        }

        private static void matches (Regex? re, string s, Gee.ArrayList<int> starts, Gee.ArrayList<int> ends) {
            if (re == null) return;
            MatchInfo mi;
            if (!re.match (s, 0, out mi)) return;
            while (mi.matches ()) {
                int st, en;
                mi.fetch_pos (0, out st, out en);
                if (en > st) {
                    starts.add (st);
                    ends.add (en);
                }
                try {
                    if (!mi.next ()) break;
                } catch (RegexError e) {
                    break;
                }
            }
        }

        private static string[] split_by (string s, Regex? re) {
            string[] r = {};
            var st = new Gee.ArrayList<int> ();
            var en = new Gee.ArrayList<int> ();
            matches (re, s, st, en);
            int prev = 0;
            for (int i = 0; i < st.size; i++) {
                r += s.substring (prev, st[i] - prev);
                prev = en[i];
            }
            r += s.substring (prev);
            return r;
        }

        private static Value around (Evaluator ev, Node[] a, bool before) {
            Value? err;
            var dv = ev.eval (a[1]);
            var delims = texts_of (ev, dv, out err);
            if (err != null) return err;
            int inst, mode, match_end;
            Value? e = null;
            if ((e = opt_int (ev, a, 2, 1, out inst)) != null) return e;
            if ((e = opt_int (ev, a, 3, 0, out mode)) != null) return e;
            if ((e = opt_int (ev, a, 4, 0, out match_end)) != null) return e;
            bool has_default = a.length > 5 && a[5].kind != NodeKind.MISSING;
            var fallback = has_default ? ev.arg (a[5]) : Value.err (ErrorKind.NA);
            bool empty_delim = false;
            foreach (string d in delims) if (d == "") empty_delim = true;
            var re = delimiter_regex (delims, mode == 1);
            return ev.map1 (ev.eval (a[0]), (v) => {
                if (v.is_error ()) return v;
                string s = Evaluator.to_text (v);
                int len = s.length;
                if (inst == 0 || inst.abs () > int.max (len, 1)) return Value.err (ErrorKind.VALUE);
                var st = new Gee.ArrayList<int> ();
                var en = new Gee.ArrayList<int> ();
                if (empty_delim) {
                    if (inst > 0) {
                        st.add (0);
                        en.add (0);
                    } else {
                        st.add (len);
                        en.add (len);
                    }
                } else {
                    matches (re, s, st, en);
                }
                if (match_end != 0) {
                    if (inst > 0) {
                        st.add (len);
                        en.add (len);
                    } else {
                        st.insert (0, 0);
                        en.insert (0, 0);
                    }
                }
                int idx = inst > 0 ? inst - 1 : st.size + inst;
                if (idx < 0 || idx >= st.size) return fallback;
                return Value.str (before ? s.substring (0, st[idx]) : s.substring (en[idx]));
            });
        }

        private static string strict_text (Value v) {
            if (v.kind == ValueKind.TEXT) return "\"" + v.text.replace ("\"", "\"\"") + "\"";
            return Evaluator.to_text (v);
        }

        private static unichar half_width (unichar c) {
            if (c >= 0xFF01 && c <= 0xFF5E) return c - 0xFEE0;
            if (c == 0x3000) return ' ';
            return c;
        }

        private static unichar full_width (unichar c) {
            if (c >= 0x21 && c <= 0x7E) return c + 0xFEE0;
            if (c == ' ') return 0x3000;
            return c;
        }

        private static string map_chars (string s, bool to_half) {
            var sb = new StringBuilder ();
            int i = 0;
            unichar c;
            while (s.get_next_char (ref i, out c)) sb.append_unichar (to_half ? half_width (c) : full_width (c));
            return sb.str;
        }

        private const string[] THAI_DIGITS = { "ศูนย์", "หนึ่ง", "สอง", "สาม", "สี่", "ห้า", "หก", "เจ็ด", "แปด", "เก้า" };
        private const string[] THAI_PLACES = { "", "สิบ", "ร้อย", "พัน", "หมื่น", "แสน" };

        private static string thai (int64 n, bool higher) {
            if (n == 0) return "";
            if (n >= 1000000) return thai (n / 1000000, false) + "ล้าน" + thai (n % 1000000, true);
            var sb = new StringBuilder ();
            string digits = n.to_string ();
            int len = digits.length;
            for (int i = 0; i < len; i++) {
                int d = digits[i] - '0';
                int place = len - 1 - i;
                if (d == 0) continue;
                if (place == 1 && d == 1) sb.append ("สิบ");
                else if (place == 1 && d == 2) sb.append ("ยี่สิบ");
                else if (place == 0 && d == 1 && (len > 1 || higher)) sb.append ("เอ็ด");
                else {
                    sb.append (THAI_DIGITS[d]);
                    sb.append (THAI_PLACES[place]);
                }
            }
            return sb.str;
        }

        public static string bahttext (double x) {
            bool neg = x < 0;
            double ax = Math.round (Math.fabs (x) * 100) / 100;
            int64 baht = (int64) Math.floor (ax);
            int64 satang = (int64) Math.round ((ax - baht) * 100);
            if (satang == 100) {
                baht++;
                satang = 0;
            }
            var sb = new StringBuilder (neg ? "ลบ" : "");
            if (baht == 0 && satang == 0) return "ศูนย์บาทถ้วน";
            if (baht > 0) sb.append (thai (baht, false) + "บาท");
            if (satang == 0) sb.append ("ถ้วน");
            else sb.append (thai (satang, false) + "สตางค์");
            return sb.str;
        }

        public static void register () {
            add ("REGEXTEST", 2, 3, "REGEXTEST(text, pattern, [case_sensitivity])", _("Whether text matches a regular expression"), (ev, a) => {
                Value? e = null;
                string pat = ev.arg_text (a[1], out e);
                if (e != null) return e;
                int cs;
                if ((e = opt_int (ev, a, 2, 0, out cs)) != null) return e;
                var re = compile (pat, cs == 1, out e);
                if (e != null) return e;
                return ev.map1 (ev.eval (a[0]), (v) => {
                    if (v.is_error ()) return v;
                    return Value.boolean (re.match (Evaluator.to_text (v)));
                });
            });
            add ("REGEXEXTRACT", 2, 4, "REGEXEXTRACT(text, pattern, [return_mode], [case_sensitivity])", _("Extracts text that matches a regular expression"), (ev, a) => {
                Value? e = null;
                string pat = ev.arg_text (a[1], out e);
                if (e != null) return e;
                int mode, cs;
                if ((e = opt_int (ev, a, 2, 0, out mode)) != null) return e;
                if ((e = opt_int (ev, a, 3, 0, out cs)) != null) return e;
                if (mode < 0 || mode > 2) return Value.err (ErrorKind.VALUE);
                var re = compile (pat, cs == 1, out e);
                if (e != null) return e;
                var tv = ev.eval (a[0]);
                if (mode == 0) {
                    return ev.map1 (tv, (v) => {
                        if (v.is_error ()) return v;
                        string subject = Evaluator.to_text (v);
                        MatchInfo mi;
                        if (!re.match (subject, 0, out mi)) return Value.err (ErrorKind.NA);
                        return Value.str (mi.fetch (0));
                    });
                }
                string s = Evaluator.to_text (ev.deref (tv));
                MatchInfo mi;
                if (!re.match (s, 0, out mi)) return Value.err (ErrorKind.NA);
                if (mode == 2) {
                    int groups = mi.get_match_count () - 1;
                    if (groups < 1) return Value.str (mi.fetch (0));
                    var m = new Value[1, groups];
                    for (int g = 1; g <= groups; g++) m[0, g - 1] = Value.str (mi.fetch (g) ?? "");
                    return Value.matrix (m);
                }
                var found = new Gee.ArrayList<string> ();
                while (mi.matches ()) {
                    found.add (mi.fetch (0));
                    try {
                        if (!mi.next ()) break;
                    } catch (RegexError err) {
                        break;
                    }
                }
                var m = new Value[found.size, 1];
                for (int i = 0; i < found.size; i++) m[i, 0] = Value.str (found[i]);
                return Value.matrix (m);
            });
            add ("REGEXREPLACE", 3, 5, "REGEXREPLACE(text, pattern, replacement, [occurrence], [case_sensitivity])", _("Replaces text that matches a regular expression"), (ev, a) => {
                Value? e = null;
                string pat = ev.arg_text (a[1], out e);
                if (e != null) return e;
                string rep = ev.arg_text (a[2], out e);
                if (e != null) return e;
                int occ, cs;
                if ((e = opt_int (ev, a, 3, 0, out occ)) != null) return e;
                if ((e = opt_int (ev, a, 4, 0, out cs)) != null) return e;
                var re = compile (pat, cs == 1, out e);
                if (e != null) return e;
                return ev.map1 (ev.eval (a[0]), (v) => {
                    if (v.is_error ()) return v;
                    string s = Evaluator.to_text (v);
                    var st = new Gee.ArrayList<int> ();
                    var en = new Gee.ArrayList<int> ();
                    var groups = new Gee.ArrayList<Gee.ArrayList<string>> ();
                    MatchInfo mi;
                    if (re.match (s, 0, out mi)) {
                        while (mi.matches ()) {
                            int p, q;
                            mi.fetch_pos (0, out p, out q);
                            st.add (p);
                            en.add (q);
                            var g = new Gee.ArrayList<string> ();
                            for (int k = 0; k < mi.get_match_count (); k++) g.add (mi.fetch (k) ?? "");
                            groups.add (g);
                            try {
                                if (!mi.next ()) break;
                            } catch (RegexError err) {
                                break;
                            }
                        }
                    }
                    int target = occ > 0 ? occ - 1 : (occ < 0 ? st.size + occ : -1);
                    var sb = new StringBuilder ();
                    int prev = 0;
                    for (int i = 0; i < st.size; i++) {
                        if (target >= 0 && i != target) continue;
                        sb.append (s.substring (prev, st[i] - prev));
                        sb.append (expand (rep, groups[i]));
                        prev = en[i];
                    }
                    sb.append (s.substring (prev));
                    return Value.str (sb.str);
                });
            });
            add ("TEXTSPLIT", 2, 6, "TEXTSPLIT(text, col_delimiter, [row_delimiter], [ignore_empty], [match_mode], [pad_with])", _("Splits text into rows and columns"), (ev, a) => {
                Value? e = null;
                string s = ev.arg_text (a[0], out e);
                if (e != null) return e;
                string[] cols = {};
                string[] rows = {};
                if (a[1].kind != NodeKind.MISSING) {
                    cols = texts_of (ev, ev.eval (a[1]), out e);
                    if (e != null) return e;
                }
                if (a.length > 2 && a[2].kind != NodeKind.MISSING) {
                    rows = texts_of (ev, ev.eval (a[2]), out e);
                    if (e != null) return e;
                }
                if (cols.length == 0 && rows.length == 0) return Value.err (ErrorKind.VALUE);
                bool ignore;
                int mode;
                if ((e = opt_bool (ev, a, 3, false, out ignore)) != null) return e;
                if ((e = opt_int (ev, a, 4, 0, out mode)) != null) return e;
                var pad = a.length > 5 && a[5].kind != NodeKind.MISSING ? ev.arg (a[5]) : Value.err (ErrorKind.NA);
                var rre = delimiter_regex (rows, mode == 1);
                var cre = delimiter_regex (cols, mode == 1);
                var table = new Gee.ArrayList<Gee.ArrayList<string>> ();
                int width = 0;
                foreach (string line in split_by (s, rre)) {
                    if (ignore && line == "" && rows.length > 0) continue;
                    var cells = new Gee.ArrayList<string> ();
                    foreach (string cell in split_by (line, cre)) {
                        if (ignore && cell == "") continue;
                        cells.add (cell);
                    }
                    if (ignore && cells.size == 0) continue;
                    table.add (cells);
                    width = int.max (width, cells.size);
                }
                if (table.size == 0 || width == 0) return Value.err (ErrorKind.CALC);
                var m = new Value[table.size, width];
                for (int i = 0; i < table.size; i++) {
                    for (int j = 0; j < width; j++) m[i, j] = j < table[i].size ? Value.str (table[i][j]) : pad;
                }
                return Value.matrix (m);
            });
            add ("TEXTBEFORE", 2, 6, "TEXTBEFORE(text, delimiter, [instance_num], [match_mode], [match_end], [if_not_found])", _("The text before a delimiter"), (ev, a) => around (ev, a, true));
            add ("TEXTAFTER", 2, 6, "TEXTAFTER(text, delimiter, [instance_num], [match_mode], [match_end], [if_not_found])", _("The text after a delimiter"), (ev, a) => around (ev, a, false));
            add ("VALUETOTEXT", 1, 2, "VALUETOTEXT(value, [format])", _("A value as text"), (ev, a) => {
                int fmt;
                var e = opt_int (ev, a, 1, 0, out fmt);
                if (e != null) return e;
                if (fmt < 0 || fmt > 1) return Value.err (ErrorKind.VALUE);
                return ev.map1 (ev.eval (a[0]), (v) => Value.str (fmt == 1 ? strict_text (v) : Evaluator.to_text (v)));
            });
            add ("ARRAYTOTEXT", 1, 2, "ARRAYTOTEXT(array, [format])", _("An array as text"), (ev, a) => {
                int fmt;
                var e = opt_int (ev, a, 1, 0, out fmt);
                if (e != null) return e;
                if (fmt < 0 || fmt > 1) return Value.err (ErrorKind.VALUE);
                var m = ev.to_matrix (ev.eval (a[0]));
                var sb = new StringBuilder (fmt == 1 ? "{" : "");
                for (int i = 0; i < m.length[0]; i++) {
                    if (i > 0) sb.append (fmt == 1 ? ";" : ", ");
                    for (int j = 0; j < m.length[1]; j++) {
                        if (j > 0) sb.append (fmt == 1 ? "," : ", ");
                        sb.append (fmt == 1 ? strict_text (m[i, j]) : Evaluator.to_text (m[i, j]));
                    }
                }
                if (fmt == 1) sb.append ("}");
                return Value.str (sb.str);
            });
            add ("ASC", 1, 1, "ASC(text)", _("Changes full-width characters to half-width"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => v.is_error () ? v : Value.str (map_chars (Evaluator.to_text (v), true))));
            add ("DBCS", 1, 1, "DBCS(text)", _("Changes half-width characters to full-width"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => v.is_error () ? v : Value.str (map_chars (Evaluator.to_text (v), false))));
            Functions.alias ("JIS", "DBCS");
            add ("BAHTTEXT", 1, 1, "BAHTTEXT(number)", _("A number as Thai text with Baht"), (ev, a) => ev.map1 (ev.eval (a[0]), (v) => {
                double d;
                var e = Evaluator.to_number (v, out d);
                if (e != null) return e;
                return Value.str (bahttext (d));
            }));
            add ("PHONETIC", 1, 1, "PHONETIC(reference)", _("The phonetic characters of a text"), (ev, a) => {
                var v = ev.eval (a[0]);
                if (v.kind == ValueKind.RANGE) return Value.str (Evaluator.to_text (ev.cell (v.area.sheet, v.area.r1, v.area.c1)));
                if (v.is_error ()) return v;
                return Value.err (ErrorKind.NA);
            });
            string[,] bytes = { { "LENB", "LEN" }, { "LEFTB", "LEFT" }, { "RIGHTB", "RIGHT" }, { "MIDB", "MID" }, { "FINDB", "FIND" }, { "SEARCHB", "SEARCH" }, { "REPLACEB", "REPLACE" } };
            for (int i = 0; i < bytes.length[0]; i++) {
                if (Functions.all ().has_key (bytes[i, 1])) Functions.alias (bytes[i, 0], bytes[i, 1]);
            }
            add ("TRANSLATE", 1, 3, "TRANSLATE(text, [source_language], [target_language])", _("Translates text with an online service, not available offline"), (ev, a) => Value.err (ErrorKind.VALUE));
            add ("DETECTLANGUAGE", 1, 1, "DETECTLANGUAGE(text)", _("Detects the language of text with an online service, not available offline"), (ev, a) => Value.err (ErrorKind.VALUE));
        }

        private static string expand (string rep, Gee.ArrayList<string> groups) {
            var sb = new StringBuilder ();
            for (int i = 0; i < rep.length; i++) {
                char c = rep[i];
                if (c == '$' && i + 1 < rep.length) {
                    char d = rep[i + 1];
                    if (d == '$') {
                        sb.append_c ('$');
                        i++;
                        continue;
                    }
                    if (d.isdigit ()) {
                        int j = i + 1;
                        while (j < rep.length && rep[j].isdigit () && j < i + 3) j++;
                        int g = int.parse (rep.substring (i + 1, j - i - 1));
                        if (g < groups.size) sb.append (groups[g]);
                        i = j - 1;
                        continue;
                    }
                    if (d == '{') {
                        int close = rep.index_of_char ('}', i + 2);
                        if (close > 0) {
                            int g = int.parse (rep.substring (i + 2, close - i - 2));
                            if (g < groups.size) sb.append (groups[g]);
                            i = close;
                            continue;
                        }
                    }
                }
                sb.append_c (c);
            }
            return sb.str;
        }
    }
}
