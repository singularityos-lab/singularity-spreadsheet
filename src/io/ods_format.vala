namespace Singularity.Apps.Spreadsheet {

    public class OdsFormat {
        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        public static string[] sections (string code) {
            string[] parts = {};
            var sb = new StringBuilder ();
            bool q = false;
            for (int i = 0; i < code.length; i++) {
                char c = code[i];
                if (c == '"') q = !q;
                if (c == '\\' && i + 1 < code.length && !q) {
                    sb.append_c (c);
                    sb.append_c (code[++i]);
                    continue;
                }
                if (c == ';' && !q) {
                    parts += sb.str;
                    sb.truncate ();
                    continue;
                }
                sb.append_c (c);
            }
            parts += sb.str;
            return parts;
        }

        private class Tok {
            public string kind;
            public string text;

            public Tok (string kind, string text) {
                this.kind = kind;
                this.text = text;
            }
        }

        private static Gee.ArrayList<Tok> tokens (string sec, out string color, out string condition, out string currency) {
            var list = new Gee.ArrayList<Tok> ();
            color = "";
            condition = "";
            currency = "";
            int i = 0;
            int n = sec.length;
            while (i < n) {
                char c = sec[i];
                if (c == '"') {
                    int j = sec.index_of_char ('"', i + 1);
                    if (j < 0) j = n;
                    list.add (new Tok ("text", sec.substring (i + 1, j - i - 1)));
                    i = j + 1;
                    continue;
                }
                if (c == '\\' && i + 1 < n) {
                    list.add (new Tok ("text", sec.substring (i + 1, 1)));
                    i += 2;
                    continue;
                }
                if (c == '_' && i + 1 < n) {
                    list.add (new Tok ("text", " "));
                    i += 2;
                    continue;
                }
                if (c == '*' && i + 1 < n) {
                    i += 2;
                    continue;
                }
                if (c == '[') {
                    int j = sec.index_of_char (']', i);
                    if (j < 0) j = n - 1;
                    string inner = sec.substring (i + 1, j - i - 1);
                    string up = inner.up ();
                    if (inner.has_prefix ("$")) {
                        int dash = inner.index_of_char ('-');
                        currency = dash > 0 ? inner.substring (1, dash - 1) : inner.substring (1);
                        list.add (new Tok ("currency", currency));
                    } else if (up == "H" || up == "HH" || up == "M" || up == "MM" || up == "S" || up == "SS") {
                        list.add (new Tok ("elapsed", inner.down ()));
                    } else if (inner.has_prefix ("<") || inner.has_prefix (">") || inner.has_prefix ("=")) {
                        condition = inner;
                    } else {
                        color = inner;
                    }
                    i = j + 1;
                    continue;
                }
                if (sec.substring (i).up ().has_prefix ("AM/PM")) {
                    list.add (new Tok ("ampm", "AM/PM"));
                    i += 5;
                    continue;
                }
                if (sec.substring (i).up ().has_prefix ("A/P")) {
                    list.add (new Tok ("ampm", "A/P"));
                    i += 3;
                    continue;
                }
                char l = c.tolower ();
                if (l == 'y' || l == 'm' || l == 'd' || l == 'h' || l == 's' || l == 'e') {
                    int j = i;
                    while (j < n && sec[j].tolower () == l) j++;
                    if (l == 'e' && (j < n && (sec[j] == '+' || sec[j] == '-'))) {
                        int k = j + 1;
                        while (k < n && (sec[k] == '0' || sec[k] == '#')) k++;
                        list.add (new Tok ("exp", sec.substring (i, k - i)));
                        i = k;
                        continue;
                    }
                    if (l == 'e') {
                        list.add (new Tok ("y", "yyyy"));
                        i = j;
                        continue;
                    }
                    list.add (new Tok (l.to_string (), sec.substring (i, j - i).down ()));
                    i = j;
                    continue;
                }
                if (c == '0' || c == '#' || c == '?' || c == ',' || c == '.') {
                    int j = i;
                    while (j < n && (sec[j] == '0' || sec[j] == '#' || sec[j] == '?' || sec[j] == ',' || sec[j] == '.' || (sec[j] == ' ' && j + 1 < n && (sec[j + 1] == '#' || sec[j + 1] == '?' || sec[j + 1] == '0') && j > i))) j++;
                    list.add (new Tok ("num", sec.substring (i, j - i)));
                    i = j;
                    continue;
                }
                if (c == '/') {
                    list.add (new Tok ("slash", "/"));
                    i++;
                    continue;
                }
                if (c == '%') {
                    list.add (new Tok ("pct", "%"));
                    i++;
                    continue;
                }
                if (c == '@') {
                    list.add (new Tok ("at", "@"));
                    i++;
                    continue;
                }
                int cl = sec.index_of_nth_char (sec.char_count (i) + 1) - i;
                if (cl <= 0) cl = 1;
                list.add (new Tok ("text", sec.substring (i, cl)));
                i += cl;
            }
            for (int k = 0; k < list.size; k++) {
                if (list[k].kind != "m") continue;
                bool time = false;
                for (int b = k - 1; b >= 0; b--) {
                    if (list[b].kind == "text") continue;
                    if (list[b].kind == "h" || list[b].kind == "elapsed") time = true;
                    break;
                }
                for (int f = k + 1; f < list.size && !time; f++) {
                    if (list[f].kind == "text") continue;
                    if (list[f].kind == "s") time = true;
                    break;
                }
                if (time) list[k].kind = "min";
            }
            return list;
        }

        private static string color_hex (string name) {
            switch (name.down ()) {
                case "red": return "#ff0000";
                case "blue": return "#0000ff";
                case "green": return "#00ff00";
                case "yellow": return "#ffff00";
                case "magenta": return "#ff00ff";
                case "cyan": return "#00ffff";
                case "white": return "#ffffff";
                case "black": return "#000000";
                default: return "";
            }
        }

        private static string color_name (string hex) {
            switch (hex.down ()) {
                case "#ff0000": return "Red";
                case "#0000ff": return "Blue";
                case "#00ff00": return "Green";
                case "#ffff00": return "Yellow";
                case "#ff00ff": return "Magenta";
                case "#00ffff": return "Cyan";
                case "#ffffff": return "White";
                case "#000000": return "Black";
                default: return "";
            }
        }

        private static string number_el (string spec, bool grouping_hint) {
            string intpart = spec;
            string dec = "";
            int dot = spec.index_of_char ('.');
            if (dot >= 0) {
                intpart = spec.substring (0, dot);
                dec = spec.substring (dot + 1);
            }
            bool grouping = intpart.contains (",");
            int scale = 0;
            while (intpart.has_suffix (",")) {
                intpart = intpart.substring (0, intpart.length - 1);
                scale++;
            }
            if (scale > 0 && intpart.contains (",")) grouping = true;
            else if (scale > 0) grouping = false;
            int min_int = 0;
            foreach (char ch in intpart.to_utf8 ()) if (ch == '0') min_int++;
            int decimals = 0, min_dec = 0;
            foreach (char ch in dec.replace (",", "").to_utf8 ()) {
                decimals++;
                if (ch == '0') min_dec++;
            }
            var sb = new StringBuilder ("<number:number number:decimal-places=\"%d\" number:min-decimal-places=\"%d\" number:min-integer-digits=\"%d\"".printf (decimals, min_dec, min_int));
            if (grouping || grouping_hint) sb.append (" number:grouping=\"true\"");
            if (scale > 0) sb.append (" number:display-factor=\"%s\"".printf (Value.format_number_general_full (Math.pow (1000, scale))));
            sb.append ("/>");
            return sb.str;
        }

        private static string style_of_section (string name, string sec, bool neg_default, out string family) {
            string color, cond, currency;
            var toks = tokens (sec, out color, out cond, out currency);
            bool is_date = false, is_time = false, pct = false, exp = false, frac = false, text = false, cur = currency != "";
            foreach (var t in toks) {
                switch (t.kind) {
                    case "y": case "d": is_date = true; break;
                    case "m": is_date = true; break;
                    case "h": case "min": case "s": case "elapsed": case "ampm": is_time = true; break;
                    case "pct": pct = true; break;
                    case "exp": exp = true; break;
                    case "slash": frac = true; break;
                    case "at": text = true; break;
                    case "text":
                        if (t.text == "$" || t.text == "€" || t.text == "£" || t.text == "¥") cur = true;
                        break;
                }
            }
            var body = new StringBuilder ();
            if (is_date || is_time) {
                family = is_date ? "date-style" : "time-style";
                foreach (var t in toks) {
                    switch (t.kind) {
                        case "y": body.append (t.text.length > 2 ? "<number:year number:style=\"long\"/>" : "<number:year/>"); break;
                        case "m":
                            if (t.text.length >= 4) body.append ("<number:month number:style=\"long\" number:textual=\"true\"/>");
                            else if (t.text.length == 3) body.append ("<number:month number:textual=\"true\"/>");
                            else body.append (t.text.length == 2 ? "<number:month number:style=\"long\"/>" : "<number:month/>");
                            break;
                        case "d":
                            if (t.text.length >= 4) body.append ("<number:day-of-week number:style=\"long\"/>");
                            else if (t.text.length == 3) body.append ("<number:day-of-week/>");
                            else body.append (t.text.length == 2 ? "<number:day number:style=\"long\"/>" : "<number:day/>");
                            break;
                        case "h": body.append (t.text.length >= 2 ? "<number:hours number:style=\"long\"/>" : "<number:hours/>"); break;
                        case "min": body.append (t.text.length >= 2 ? "<number:minutes number:style=\"long\"/>" : "<number:minutes/>"); break;
                        case "s": body.append (t.text.length >= 2 ? "<number:seconds number:style=\"long\"/>" : "<number:seconds/>"); break;
                        case "elapsed":
                            if (t.text[0] == 'h') body.append (t.text.length >= 2 ? "<number:hours number:style=\"long\"/>" : "<number:hours/>");
                            else if (t.text[0] == 'm') body.append (t.text.length >= 2 ? "<number:minutes number:style=\"long\"/>" : "<number:minutes/>");
                            else body.append (t.text.length >= 2 ? "<number:seconds number:style=\"long\"/>" : "<number:seconds/>");
                            break;
                        case "ampm": body.append ("<number:am-pm/>"); break;
                        case "num":
                            if (t.text.has_prefix (".")) {
                                body.append ("<number:text>.</number:text>");
                            } else {
                                body.append ("<number:text>%s</number:text>".printf (esc (t.text)));
                            }
                            break;
                        default: body.append ("<number:text>%s</number:text>".printf (esc (t.text))); break;
                    }
                }
                string extra = "";
                foreach (var t in toks) if (t.kind == "elapsed") extra = " number:truncate-on-overflow=\"false\"";
                return "<number:%s style:name=\"%s\"%s>%s%s</number:%s>".printf (family, name, extra, color_props (color), body.str, family);
            }
            if (text && !toks.any_match ((t) => t.kind == "num")) {
                family = "text-style";
                foreach (var t in toks) {
                    if (t.kind == "at") body.append ("<number:text-content/>");
                    else body.append ("<number:text>%s</number:text>".printf (esc (t.text)));
                }
                return "<number:text-style style:name=\"%s\">%s%s</number:text-style>".printf (name, color_props (color), body.str);
            }
            family = pct ? "percentage-style" : (cur ? "currency-style" : "number-style");
            for (int k = 0; k < toks.size; k++) {
                var t = toks[k];
                switch (t.kind) {
                    case "num":
                        if (frac && k + 2 < toks.size && toks[k + 1].kind == "slash") {
                            string whole = "";
                            string numer = t.text;
                            int sp = t.text.last_index_of_char (' ');
                            if (sp > 0) {
                                whole = t.text.substring (0, sp);
                                numer = t.text.substring (sp + 1);
                            }
                            string denom = toks[k + 2].text;
                            int min_int = 0;
                            foreach (char ch in whole.to_utf8 ()) if (ch == '0') min_int++;
                            bool fixed_den = denom.length > 0 && denom[0].isdigit () && denom != "0";
                            string whole_attr = whole != "" ? " number:min-integer-digits=\"%d\"".printf (min_int) : "";
                            if (fixed_den) {
                                body.append ("<number:fraction%s number:min-numerator-digits=\"%d\" number:denominator-value=\"%s\"/>".printf (whole_attr, numer.length, denom));
                            } else {
                                body.append ("<number:fraction%s number:min-numerator-digits=\"%d\" number:min-denominator-digits=\"%d\"/>".printf (whole_attr, numer.length, denom.length));
                            }
                            k += 2;
                        } else if (k + 1 < toks.size && toks[k + 1].kind == "exp") {
                            string spec = t.text;
                            int dot = spec.index_of_char ('.');
                            int decimals = dot >= 0 ? spec.length - dot - 1 : 0;
                            int min_int = 0;
                            foreach (char ch in (dot >= 0 ? spec.substring (0, dot) : spec).to_utf8 ()) if (ch == '0') min_int++;
                            string e = toks[k + 1].text;
                            int ed = 0;
                            foreach (char ch in e.to_utf8 ()) if (ch == '0') ed++;
                            body.append ("<number:scientific-number number:decimal-places=\"%d\" number:min-integer-digits=\"%d\" number:min-exponent-digits=\"%d\"/>".printf (decimals, min_int, ed));
                            k++;
                        } else {
                            body.append (number_el (t.text, false));
                        }
                        break;
                    case "pct": body.append ("<number:text>%</number:text>"); break;
                    case "currency": body.append ("<number:currency-symbol>%s</number:currency-symbol>".printf (esc (t.text))); break;
                    case "at": body.append ("<number:text-content/>"); break;
                    case "text":
                        if (cur && (t.text == "$" || t.text == "€" || t.text == "£" || t.text == "¥")) body.append ("<number:currency-symbol>%s</number:currency-symbol>".printf (esc (t.text)));
                        else body.append ("<number:text>%s</number:text>".printf (esc (t.text)));
                        break;
                    default:
                        body.append ("<number:text>%s</number:text>".printf (esc (t.text)));
                        break;
                }
            }
            return "<number:%s style:name=\"%s\">%s%s</number:%s>".printf (family, name, color_props (color), body.str, family);
        }

        private static string color_props (string color) {
            string hex = color_hex (color);
            if (hex == "") return "";
            return "<style:text-properties fo:color=\"%s\"/>".printf (hex);
        }

        public static string data_style (string name, string code, out string family) {
            var secs = sections (code);
            family = "number-style";
            if (secs.length == 1) return insert_source (style_of_section (name, secs[0], false, out family), code);
            var sb = new StringBuilder ();
            string[] conds = { "value()&gt;=0", "value()&lt;0", "value()=0" };
            if (secs.length >= 3) conds = { "value()&gt;0", "value()&lt;0", "value()=0" };
            int main = secs.length >= 4 ? 3 : secs.length - 1;
            string mfam;
            var maps = new StringBuilder ();
            for (int i = 0; i < secs.length; i++) {
                if (i == main) continue;
                string sub = "%sP%d".printf (name, i);
                string f;
                sb.append (style_of_section (sub, secs[i], i == 1, out f));
                if (i < 3) maps.append ("<style:map style:condition=\"%s\" style:apply-style-name=\"%s\"/>".printf (conds[i], sub));
            }
            string main_xml = style_of_section (name, secs[main], main == 1, out mfam);
            family = mfam;
            int close = main_xml.last_index_of ("</number:");
            main_xml = main_xml.substring (0, close) + maps.str + main_xml.substring (close);
            sb.append (insert_source (main_xml, code));
            return sb.str;
        }

        private static string insert_source (string xml, string code) {
            int head = xml.last_index_of (" style:name=\"");
            if (head < 0) return xml;
            return xml.substring (0, head) + " ss:format-code=\"%s\"".printf (esc (code)) + xml.substring (head);
        }

        private static string attr (Xml.Node* n, string name) {
            for (Xml.Attr* a = n->properties; a != null; a = a->next) {
                if (a->name == name) return a->children != null ? a->children->content : "";
            }
            return "";
        }

        public static string to_code (Xml.Node* style, Gee.HashMap<string, Xml.Node*> all) {
            string src = attr (style, "format-code");
            if (src != "") return src;
            string main = section_code (style);
            var conds = new Gee.ArrayList<string> ();
            var codes = new Gee.ArrayList<string> ();
            for (Xml.Node* c = style->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "map") continue;
                string target = attr (c, "apply-style-name");
                if (!all.has_key (target)) continue;
                conds.add (attr (c, "condition").replace (" ", ""));
                codes.add (section_code (all[target]));
            }
            if (codes.size == 0) return main;
            if (codes.size == 1 && (conds[0] == "value()>=0" || conds[0] == "value()>0")) return codes[0] + ";" + main;
            if (codes.size == 2) return codes[0] + ";" + codes[1] + ";" + main;
            return codes[0] + ";" + main;
        }

        private static string quote_text (string t) {
            if (t == "") return "";
            if (t == " " || t == "-" || t == "(" || t == ")" || t == ":" || t == "/" || t == "," || t == "." || t == "$" || t == "€") return t;
            return "\"" + t.replace ("\"", "") + "\"";
        }

        private static string section_code (Xml.Node* style) {
            var sb = new StringBuilder ();
            bool long_date = false;
            for (Xml.Node* c = style->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                string ls = attr (c, "style");
                bool lng = ls == "long";
                switch (c->name) {
                    case "text-properties":
                        string cn = color_name (attr (c, "color"));
                        if (cn != "") sb.prepend ("[" + cn + "]");
                        break;
                    case "number":
                        int dp = int.parse (attr (c, "decimal-places"));
                        string mds = attr (c, "min-decimal-places");
                        int md = mds != "" ? int.parse (mds) : dp;
                        int mi = int.parse (attr (c, "min-integer-digits"));
                        bool grp = attr (c, "grouping") == "true";
                        string ip = mi > 0 ? string.nfill (mi, '0') : "#";
                        if (grp) {
                            while (ip.length < 4) ip = "#" + ip;
                            ip = ip.substring (0, ip.length - 3) + "," + ip.substring (ip.length - 3);
                        }
                        sb.append (ip);
                        if (dp > 0) sb.append ("." + string.nfill (md, '0') + string.nfill (dp - md, '#'));
                        string df = attr (c, "display-factor");
                        if (df != "") {
                            double f = double.parse (df);
                            while (f >= 1000) {
                                sb.append (",");
                                f /= 1000;
                            }
                        }
                        break;
                    case "scientific-number":
                        int sdp = int.parse (attr (c, "decimal-places"));
                        int smi = int.max (1, int.parse (attr (c, "min-integer-digits")));
                        int med = int.max (1, int.parse (attr (c, "min-exponent-digits")));
                        sb.append (string.nfill (smi, '0'));
                        if (sdp > 0) sb.append ("." + string.nfill (sdp, '0'));
                        sb.append ("E+" + string.nfill (med, '0'));
                        break;
                    case "fraction":
                        int fmi = int.parse (attr (c, "min-integer-digits"));
                        int nd = int.max (1, int.parse (attr (c, "min-numerator-digits")));
                        string dv = attr (c, "denominator-value");
                        if (attr (c, "min-integer-digits") != "") sb.append (fmi > 0 ? string.nfill (fmi, '0') + " " : "# ");
                        sb.append (string.nfill (nd, '?') + "/");
                        sb.append (dv != "" ? dv : string.nfill (int.max (1, int.parse (attr (c, "min-denominator-digits"))), '?'));
                        break;
                    case "currency-symbol":
                        string sym = c->get_content () ?? "";
                        sb.append (sym == "$" || sym == "€" || sym == "£" ? sym : "[$" + sym + "]");
                        break;
                    case "text":
                        string tx = c->get_content () ?? "";
                        sb.append (tx == "%" ? "%" : quote_text (tx));
                        break;
                    case "text-content":
                        sb.append ("@");
                        break;
                    case "year": sb.append (lng ? "yyyy" : "yy"); long_date = true; break;
                    case "month":
                        bool textual = attr (c, "textual") == "true";
                        sb.append (textual ? (lng ? "mmmm" : "mmm") : (lng ? "mm" : "m"));
                        break;
                    case "day": sb.append (lng ? "dd" : "d"); break;
                    case "day-of-week": sb.append (lng ? "dddd" : "ddd"); break;
                    case "hours":
                        bool trunc = attr (style, "truncate-on-overflow") == "false";
                        sb.append (trunc ? (lng ? "[hh]" : "[h]") : (lng ? "hh" : "h"));
                        break;
                    case "minutes": sb.append (lng ? "mm" : "m"); break;
                    case "seconds":
                        sb.append (lng ? "ss" : "s");
                        int sd = int.parse (attr (c, "decimal-places"));
                        if (sd > 0) sb.append ("." + string.nfill (sd, '0'));
                        break;
                    case "am-pm": sb.append ("AM/PM"); break;
                    case "boolean": sb.append ("\"TRUE\";\"TRUE\";\"FALSE\""); break;
                }
            }
            if (style->name == "percentage-style" && !sb.str.contains ("%")) sb.append ("%");
            if (sb.len == 0) return "General";
            return sb.str;
        }
    }
}
