namespace Singularity.Apps.Spreadsheet {

    public class TextFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Text", syntax, summary, (owned) impl);
        }

        public static string sub (string s, int start, int count) {
            int len = s.char_count ();
            if (start >= len || count <= 0) return "";
            int end = int.min (len, start + count);
            int b1 = s.index_of_nth_char (start);
            int b2 = s.index_of_nth_char (end);
            return s.substring (b1, b2 - b1);
        }

        private delegate Value TextOp (string s);

        private static void text1 (string name, string summary, owned TextOp op) {
            TextOp f = (owned) op;
            add (name, 1, 1, name + "(text)", summary, (ev, a) => {
                return ev.map1 (ev.eval (a[0]), (v) => {
                    if (v.is_error ()) return v;
                    return f (Evaluator.to_text (v));
                });
            });
        }

        public static void register () {
            add ("CONCATENATE", 1, -1, "CONCATENATE(text1, ...)", _("Joins texts together"), (ev, a) => {
                var sb = new StringBuilder ();
                foreach (var n in a) {
                    var v = ev.arg (n);
                    if (v.is_error ()) return v;
                    sb.append (Evaluator.to_text (v));
                }
                return Value.str (sb.str);
            });
            add ("CONCAT", 1, -1, "CONCAT(text1, ...)", _("Joins texts and ranges together"), (ev, a) => {
                var sb = new StringBuilder ();
                Value? err = null;
                foreach (var n in a) {
                    ev.visit_values (n, (v, r) => {
                        if (v.is_error ()) {
                            err = v;
                            return false;
                        }
                        sb.append (Evaluator.to_text (v));
                        return true;
                    });
                    if (err != null) return err;
                }
                return Value.str (sb.str);
            });
            add ("TEXTJOIN", 3, -1, "TEXTJOIN(delimiter, ignore_empty, text1, ...)", _("Joins texts with a delimiter"), (ev, a) => {
                Value? e = null;
                string delim = ev.arg_text (a[0], out e);
                if (e != null) return e;
                bool ignore;
                if ((e = ev.arg_bool (a[1], out ignore)) != null) return e;
                string[] parts = {};
                Value? err = null;
                for (int i = 2; i < a.length; i++) {
                    ev.visit_values (a[i], (v, r) => {
                        if (v.is_error ()) {
                            err = v;
                            return false;
                        }
                        string t = Evaluator.to_text (v);
                        if (!(ignore && t == "")) parts += t;
                        return true;
                    });
                    if (err != null) return err;
                }
                return Value.str (string.joinv (delim, parts));
            });
            add ("LEFT", 1, 2, "LEFT(text, [count])", _("The first characters of a text"), (ev, a) => {
                var n = a.length > 1 ? ev.eval (a[1]) : Value.num (1);
                return ev.map2 (ev.eval (a[0]), n, (t, c) => {
                    if (t.is_error ()) return t;
                    double d;
                    var e = Evaluator.to_number (c, out d);
                    if (e != null) return e;
                    if (d < 0) return Value.err (ErrorKind.VALUE);
                    return Value.str (sub (Evaluator.to_text (t), 0, (int) d));
                });
            });
            add ("RIGHT", 1, 2, "RIGHT(text, [count])", _("The last characters of a text"), (ev, a) => {
                var n = a.length > 1 ? ev.eval (a[1]) : Value.num (1);
                return ev.map2 (ev.eval (a[0]), n, (t, c) => {
                    if (t.is_error ()) return t;
                    double d;
                    var e = Evaluator.to_number (c, out d);
                    if (e != null) return e;
                    if (d < 0) return Value.err (ErrorKind.VALUE);
                    string s = Evaluator.to_text (t);
                    int len = s.char_count ();
                    int k = int.min ((int) d, len);
                    return Value.str (sub (s, len - k, k));
                });
            });
            add ("MID", 3, 3, "MID(text, start, count)", _("Characters from the middle of a text"), (ev, a) => {
                Value? e = null;
                string s = ev.arg_text (a[0], out e);
                if (e != null) return e;
                int start, count;
                if ((e = ev.arg_int (a[1], out start)) != null) return e;
                if ((e = ev.arg_int (a[2], out count)) != null) return e;
                if (start < 1 || count < 0) return Value.err (ErrorKind.VALUE);
                return Value.str (sub (s, start - 1, count));
            });
            text1 ("LEN", _("The number of characters"), (s) => Value.num (s.char_count ()));
            text1 ("UPPER", _("Text in capitals"), (s) => Value.str (s.up ()));
            text1 ("LOWER", _("Text in small letters"), (s) => Value.str (s.down ()));
            text1 ("PROPER", _("Capitalizes each word"), (s) => {
                var sb = new StringBuilder ();
                bool start = true;
                unichar c;
                int i = 0;
                while (s.get_next_char (ref i, out c)) {
                    sb.append_unichar (start ? c.toupper () : c.tolower ());
                    start = !c.isalpha ();
                }
                return Value.str (sb.str);
            });
            text1 ("TRIM", _("Removes extra spaces"), (s) => {
                var sb = new StringBuilder ();
                foreach (string w in s.split (" ")) {
                    if (w == "") continue;
                    if (sb.len > 0) sb.append_c (' ');
                    sb.append (w);
                }
                return Value.str (sb.str);
            });
            text1 ("CLEAN", _("Removes characters that cannot be printed"), (s) => {
                var sb = new StringBuilder ();
                unichar c;
                int i = 0;
                while (s.get_next_char (ref i, out c)) if (c >= 32) sb.append_unichar (c);
                return Value.str (sb.str);
            });
            add ("T", 1, 1, "T(value)", _("The text of a value, or nothing"), (ev, a) => {
                var v = ev.arg (a[0]);
                if (v.is_error ()) return v;
                return Value.str (v.kind == ValueKind.TEXT ? v.text : "");
            });
            text1 ("CODE", _("The code of the first character"), (s) => {
                if (s == "") return Value.err (ErrorKind.VALUE);
                return Value.num (s.get_char (0) < 256 ? (double) s.get_char (0) : 63);
            });
            text1 ("UNICODE", _("The Unicode number of the first character"), (s) => {
                if (s == "") return Value.err (ErrorKind.VALUE);
                return Value.num ((double) s.get_char (0));
            });
            add ("CHAR", 1, 1, "CHAR(number)", _("The character with a code"), (ev, a) => {
                int n;
                var e = ev.arg_int (a[0], out n);
                if (e != null) return e;
                if (n < 1 || n > 255) return Value.err (ErrorKind.VALUE);
                return Value.str (((unichar) n).to_string ());
            });
            add ("UNICHAR", 1, 1, "UNICHAR(number)", _("The character with a Unicode number"), (ev, a) => {
                int n;
                var e = ev.arg_int (a[0], out n);
                if (e != null) return e;
                if (n < 1 || !((unichar) n).validate ()) return Value.err (ErrorKind.VALUE);
                return Value.str (((unichar) n).to_string ());
            });
            add ("REPT", 2, 2, "REPT(text, times)", _("Repeats a text"), (ev, a) => {
                Value? e = null;
                string s = ev.arg_text (a[0], out e);
                if (e != null) return e;
                int n;
                if ((e = ev.arg_int (a[1], out n)) != null) return e;
                if (n < 0 || (int64) s.length * n > 32767) return Value.err (ErrorKind.VALUE);
                var sb = new StringBuilder ();
                for (int i = 0; i < n; i++) sb.append (s);
                return Value.str (sb.str);
            });
            add ("EXACT", 2, 2, "EXACT(text1, text2)", _("True when two texts are identical"), (ev, a) => {
                Value? e1, e2;
                string x = ev.arg_text (a[0], out e1);
                string y = ev.arg_text (a[1], out e2);
                return e1 ?? e2 ?? Value.boolean (x == y);
            });
            add ("SUBSTITUTE", 3, 4, "SUBSTITUTE(text, old, new, [instance])", _("Replaces text by content"), (ev, a) => {
                Value? e = null;
                string s = ev.arg_text (a[0], out e);
                if (e != null) return e;
                string old_t = ev.arg_text (a[1], out e);
                if (e != null) return e;
                string new_t = ev.arg_text (a[2], out e);
                if (e != null) return e;
                if (old_t == "") return Value.str (s);
                if (a.length < 4) return Value.str (s.replace (old_t, new_t));
                int inst;
                if ((e = ev.arg_int (a[3], out inst)) != null) return e;
                if (inst < 1) return Value.err (ErrorKind.VALUE);
                int at = -1;
                for (int k = 0; k < inst; k++) {
                    at = s.index_of (old_t, at + 1);
                    if (at < 0) return Value.str (s);
                }
                return Value.str (s.substring (0, at) + new_t + s.substring (at + old_t.length));
            });
            add ("REPLACE", 4, 4, "REPLACE(text, start, count, new)", _("Replaces text by position"), (ev, a) => {
                Value? e = null;
                string s = ev.arg_text (a[0], out e);
                if (e != null) return e;
                int start, count;
                if ((e = ev.arg_int (a[1], out start)) != null) return e;
                if ((e = ev.arg_int (a[2], out count)) != null) return e;
                string n = ev.arg_text (a[3], out e);
                if (e != null) return e;
                if (start < 1 || count < 0) return Value.err (ErrorKind.VALUE);
                int len = s.char_count ();
                return Value.str (sub (s, 0, start - 1) + n + sub (s, start - 1 + count, len));
            });
            add ("FIND", 2, 3, "FIND(find, within, [start])", _("Position of a text, matching case"), (ev, a) => find (ev, a, true));
            add ("SEARCH", 2, 3, "SEARCH(find, within, [start])", _("Position of a text, with wildcards"), (ev, a) => find (ev, a, false));
            add ("VALUE", 1, 1, "VALUE(text)", _("Converts text to a number"), (ev, a) => {
                return ev.map1 (ev.eval (a[0]), (v) => {
                    if (v.is_error () || v.kind == ValueKind.NUMBER) return v;
                    if (v.kind == ValueKind.EMPTY) return Value.num (0);
                    double d;
                    var e = Evaluator.to_number (Value.str (Evaluator.to_text (v)), out d);
                    return e ?? Value.num (d);
                });
            });
            add ("NUMBERVALUE", 1, 3, "NUMBERVALUE(text, [decimal], [group])", _("Converts text to a number with given separators"), (ev, a) => {
                Value? e = null;
                string s = ev.arg_text (a[0], out e);
                if (e != null) return e;
                string dec = a.length > 1 ? ev.arg_text (a[1], out e) : ".";
                string grp = a.length > 2 ? ev.arg_text (a[2], out e) : ",";
                string t = s.replace (" ", "");
                if (grp != "") t = t.replace (grp.substring (0, 1), "");
                if (dec != "" && dec != ".") t = t.replace (dec.substring (0, 1), ".");
                double pct = 1;
                while (t.has_suffix ("%")) {
                    pct /= 100;
                    t = t.substring (0, t.length - 1);
                }
                double d;
                if (t == "") return Value.num (0);
                if (!double.try_parse (t, out d)) return Value.err (ErrorKind.VALUE);
                return Value.num (d * pct);
            });
            add ("TEXT", 2, 2, "TEXT(value, format)", _("Formats a number as text"), (ev, a) => {
                var v = ev.arg (a[0]);
                if (v.is_error ()) return v;
                Value? e = null;
                string f = ev.arg_text (a[1], out e);
                if (e != null) return e;
                string color;
                if (v.kind == ValueKind.TEXT) {
                    double d;
                    if (Evaluator.to_number (v, out d) == null) return Value.str (NumberFormat.format (d, f, out color));
                    return Value.str (NumberFormat.format_value (v, f, out color));
                }
                return Value.str (NumberFormat.format_value (v.kind == ValueKind.EMPTY ? Value.num (0) : v, f, out color));
            });
            add ("FIXED", 1, 3, "FIXED(number, [decimals], [no_commas])", _("A number as text with fixed decimals"), (ev, a) => {
                double d;
                var e = ev.arg_number (a[0], out d);
                if (e != null) return e;
                int dec = 2;
                if (a.length > 1 && (e = ev.arg_int (a[1], out dec)) != null) return e;
                bool nocomma = false;
                if (a.length > 2 && (e = ev.arg_bool (a[2], out nocomma)) != null) return e;
                double r = Functions.round_digits (d, dec, 0);
                string code = (nocomma ? "0" : "#,##0") + (dec > 0 ? "." + string.nfill (dec, '0') : "");
                string color;
                return Value.str (NumberFormat.format (r, code, out color));
            });
            add ("DOLLAR", 1, 2, "DOLLAR(number, [decimals])", _("A number as currency text"), (ev, a) => {
                double d;
                var e = ev.arg_number (a[0], out d);
                if (e != null) return e;
                int dec = 2;
                if (a.length > 1 && (e = ev.arg_int (a[1], out dec)) != null) return e;
                string code = "$#,##0" + (dec > 0 ? "." + string.nfill (dec, '0') : "") + ";($#,##0" + (dec > 0 ? "." + string.nfill (dec, '0') : "") + ")";
                string color;
                return Value.str (NumberFormat.format (Functions.round_digits (d, dec, 0), code, out color));
            });
        }

        private static Value find (Evaluator ev, Node[] a, bool exact) {
            Value? e = null;
            string needle = ev.arg_text (a[0], out e);
            if (e != null) return e;
            string hay = ev.arg_text (a[1], out e);
            if (e != null) return e;
            int start = 1;
            if (a.length > 2 && (e = ev.arg_int (a[2], out start)) != null) return e;
            int len = hay.char_count ();
            if (start < 1 || start > len + 1) return Value.err (ErrorKind.VALUE);
            if (needle == "") return Value.num (start);
            if (exact) {
                int b = hay.index_of (needle, hay.index_of_nth_char (start - 1));
                if (b < 0) return Value.err (ErrorKind.VALUE);
                return Value.num (hay.substring (0, b).char_count () + 1);
            }
            Regex re;
            try {
                re = new Regex (Criteria.wildcard_pattern (needle, false), RegexCompileFlags.CASELESS | RegexCompileFlags.DOTALL);
            } catch (RegexError err) {
                return Value.err (ErrorKind.VALUE);
            }
            MatchInfo info;
            int from = hay.index_of_nth_char (start - 1);
            try {
                if (!re.match_full (hay, -1, from, 0, out info)) return Value.err (ErrorKind.VALUE);
            } catch (RegexError err) {
                return Value.err (ErrorKind.VALUE);
            }
            int mstart, mend;
            info.fetch_pos (0, out mstart, out mend);
            return Value.num (hay.substring (0, mstart).char_count () + 1);
            return Value.err (ErrorKind.VALUE);
        }
    }
}
