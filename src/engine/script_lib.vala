namespace Singularity.Apps.Spreadsheet {

    public class ScriptLib {
        private static Gee.HashMap<string, double?>? consts = null;

        public const string[] FORBIDDEN_FUNCTIONS = {
            "shell", "createobject", "getobject", "environ", "environ$", "dir", "dir$", "curdir", "curdir$", "freefile",
            "filelen", "filedatetime", "getattr", "eof", "lof", "loc", "input", "input$", "inputb", "getsetting",
            "getallsettings", "callbyname", "macscript", "shellexecute", "sendkeys"
        };

        private static void c (string name, double v) {
            consts[name] = v;
        }

        public static double? constant (string name) {
            if (consts == null) {
                consts = new Gee.HashMap<string, double?> ();
                c ("vbok", 1); c ("vbcancel", 2); c ("vbabort", 3); c ("vbretry", 4); c ("vbignore", 5); c ("vbyes", 6); c ("vbno", 7);
                c ("vbokonly", 0); c ("vbokcancel", 1); c ("vbabortretryignore", 2); c ("vbyesnocancel", 3); c ("vbyesno", 4); c ("vbretrycancel", 5);
                c ("vbcritical", 16); c ("vbquestion", 32); c ("vbexclamation", 48); c ("vbinformation", 64);
                c ("vbdefaultbutton1", 0); c ("vbdefaultbutton2", 256); c ("vbdefaultbutton3", 512); c ("vbapplicationmodal", 0); c ("vbsystemmodal", 4096);
                c ("vbsunday", 1); c ("vbmonday", 2); c ("vbtuesday", 3); c ("vbwednesday", 4); c ("vbthursday", 5); c ("vbfriday", 6); c ("vbsaturday", 7);
                c ("vbusesystemdayofweek", 0); c ("vbfirstjan1", 1);
                c ("vbbinarycompare", 0); c ("vbtextcompare", 1);
                c ("vbuppercase", 1); c ("vblowercase", 2); c ("vbpropercase", 3); c ("vbunicode", 64); c ("vbfromunicode", 128);
                c ("vbempty", 0); c ("vbnull", 1); c ("vbinteger", 2); c ("vblong", 3); c ("vbsingle", 4); c ("vbdouble", 5); c ("vbcurrency", 6);
                c ("vbdate", 7); c ("vbstring", 8); c ("vbobject", 9); c ("vberror", 10); c ("vbboolean", 11); c ("vbvariant", 12); c ("vbarray", 8192);
                c ("vbblack", 0); c ("vbred", 255); c ("vbgreen", 65280); c ("vbyellow", 65535); c ("vbblue", 16711680); c ("vbmagenta", 16711935); c ("vbcyan", 16776960); c ("vbwhite", 16777215);
                c ("vbobjecterror", -2147221504);
                c ("xlup", -4162); c ("xldown", -4121); c ("xltoleft", -4159); c ("xltoright", -4161);
                c ("xlvalues", -4163); c ("xlformulas", -4123); c ("xlcomments", -4144); c ("xlpart", 2); c ("xlwhole", 1);
                c ("xlbyrows", 1); c ("xlbycolumns", 2); c ("xlnext", 1); c ("xlprevious", 2);
                c ("xlpasteall", -4104); c ("xlpastevalues", -4163); c ("xlpasteformulas", -4123); c ("xlpasteformats", -4122);
                c ("xlpastevaluesandnumberformats", 12); c ("xlpastecolumnwidths", 8); c ("xlpastespecialoperationnone", -4142);
                c ("xlcelltypeblanks", 4); c ("xlcelltypeconstants", 2); c ("xlcelltypeformulas", -4123); c ("xlcelltypelastcell", 11); c ("xlcelltypevisible", 12);
                c ("xlcalculationautomatic", -4105); c ("xlcalculationmanual", -4135); c ("xlcalculationsemiautomatic", 2);
                c ("xlleft", -4131); c ("xlright", -4152); c ("xlcenter", -4108); c ("xlgeneral", 1); c ("xltop", -4160); c ("xlbottom", -4107); c ("xljustify", -4130);
                c ("xlshiftdown", -4121); c ("xlshifttoright", -4161); c ("xlshiftup", -4162); c ("xlshifttoleft", -4159);
                c ("xlascending", 1); c ("xldescending", 2); c ("xlyes", 1); c ("xlno", 2); c ("xlguess", 0);
                c ("xlnone", -4142); c ("xlautomatic", -4105); c ("xlsolid", 1); c ("xlcontinuous", 1); c ("xlthin", 2); c ("xlmedium", -4138); c ("xlthick", 4);
                c ("xledgeleft", 7); c ("xledgetop", 8); c ("xledgebottom", 9); c ("xledgeright", 10); c ("xlinsidevertical", 11); c ("xlinsidehorizontal", 12);
                c ("xllandscape", 2); c ("xlportrait", 1); c ("xlpaperA4", 9); c ("xlpapera4", 9); c ("xlpaperletter", 1);
                c ("xlminimized", -4140); c ("xlmaximized", -4137); c ("xlnormal", -4143);
                c ("xlsheetvisible", -1); c ("xlsheethidden", 0); c ("xlsheetveryhidden", 2);
                c ("xla1", 1); c ("xlr1c1", -4150); c ("xlerrdiv0", 2007); c ("xlerrna", 2042); c ("xlerrname", 2029); c ("xlerrnull", 2000); c ("xlerrnum", 2036); c ("xlerrref", 2023); c ("xlerrvalue", 2015);
                c ("xlworksheet", -4167); c ("xlwbatworksheet", -4167); c ("xlunderlinestylesingle", 2); c ("xlunderlinestylenone", -4142);
                c ("xlandfilter", 1); c ("xlor", 2); c ("xland", 1); c ("xltop10items", 3); c ("xlfiltervalues", 7);
                c ("xlprinttitles", 1); c ("xlpageBreakManual", -4135); c ("xlpagebreakmanual", -4135); c ("xlpagebreakautomatic", -4105);
                c ("xlvaligncenter", -4108); c ("xlvalignjustify", -4130); c ("xlvaligntop", -4160); c ("xlvalignbottom", -4107); c ("xlvaligndistributed", -4117);
                c ("xlhaligncenter", -4108); c ("xlhalignleft", -4131); c ("xlhalignright", -4152); c ("xlhalignjustify", -4130); c ("xlhalignfill", 5); c ("xlhaligngeneral", 1); c ("xlhaligndistributed", -4117); c ("xlhaligncenteracrossselection", 7);
                c ("xlhorizontal", -4128); c ("xlvertical", -4166); c ("xlupward", -4171); c ("xldownward", -4170);
                c ("xlnumber", 1); c ("xltextvalues", 2); c ("xlerrors", 16); c ("xllogical", 4);
            }
            string k = name.down ();
            return consts.has_key (k) ? consts[k] : null;
        }

        public static string? string_constant (string name) {
            switch (name.down ()) {
                case "vbcrlf": return "\r\n";
                case "vbnewline": return "\n";
                case "vbcr": return "\r";
                case "vblf": return "\n";
                case "vbtab": return "\t";
                case "vbnullstring": return "";
                case "vbnullchar": return "\0";
                case "vbback": return "\b";
                case "vbformfeed": return "\f";
                case "vbverticaltab": return "\v";
                default: return null;
            }
        }

        public static string date_text (double serial) {
            string color;
            double whole = Math.floor (serial);
            double frac = serial - whole;
            if (whole == 0 && frac > 0) return NumberFormat.format (serial, "h:mm:ss AM/PM", out color);
            if (frac == 0) return NumberFormat.format (serial, LocaleInfo.get ().short_date_format (), out color);
            return NumberFormat.format (serial, LocaleInfo.get ().short_date_format () + " h:mm:ss AM/PM", out color);
        }

        public static bool parse_date_literal (string lit, out double serial) {
            serial = 0;
            string t = lit.strip ();
            if (t == "") return false;
            var re = /^(\d{1,4})[\/\-.](\d{1,2})[\/\-.](\d{1,4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?)?$/;
            var tre = /^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([AaPp][Mm])?$/;
            MatchInfo mi;
            if (re.match (t, 0, out mi)) {
                int a = int.parse (mi.fetch (1)), b = int.parse (mi.fetch (2)), cc = int.parse (mi.fetch (3));
                int y, m, d;
                if (mi.fetch (1).length == 4) {
                    y = a;
                    m = b;
                    d = cc;
                } else {
                    m = a;
                    d = b;
                    y = cc < 100 ? (cc < 30 ? 2000 + cc : 1900 + cc) : cc;
                }
                if (m < 1 || m > 12 || d < 1 || d > 31) return false;
                serial = DateSerial.from_ymd (y, m, d);
                string hs = mi.fetch (4);
                if (hs != null && hs != "") {
                    int h = int.parse (hs), mn = int.parse (mi.fetch (5));
                    string ss = mi.fetch (6);
                    int sec = ss != null && ss != "" ? int.parse (ss) : 0;
                    string ap = mi.fetch (7);
                    if (ap != null && ap != "") {
                        if (ap.down () == "pm" && h < 12) h += 12;
                        if (ap.down () == "am" && h == 12) h = 0;
                    }
                    serial += (h * 3600 + mn * 60 + sec) / 86400.0;
                }
                return true;
            }
            if (tre.match (t, 0, out mi)) {
                int h = int.parse (mi.fetch (1)), mn = int.parse (mi.fetch (2));
                string ss = mi.fetch (3);
                int sec = ss != null && ss != "" ? int.parse (ss) : 0;
                string ap = mi.fetch (4);
                if (ap != null && ap != "") {
                    if (ap.down () == "pm" && h < 12) h += 12;
                    if (ap.down () == "am" && h == 12) h = 0;
                }
                serial = (h * 3600 + mn * 60 + sec) / 86400.0;
                return true;
            }
            double n;
            string f;
            if (Input.parse_date_time (t, out n, out f)) {
                serial = n;
                return true;
            }
            return false;
        }

        public static double bankers_round (double x, int digits = 0) {
            double m = Math.pow (10, digits);
            double v = x * m;
            double fl = Math.floor (v);
            double diff = v - fl;
            double r;
            if (Math.fabs (diff - 0.5) < 1e-9) r = ((int64) fl) % 2 == 0 ? fl : fl + 1;
            else r = Math.round (v);
            return r / m;
        }

        public static double add_months (double serial, int months) {
            int y, m, d;
            DateSerial.to_ymd (serial, out y, out m, out d);
            int total = y * 12 + (m - 1) + months;
            int ny = total / 12, nm = total % 12 + 1;
            int dim = (int) GLib.Date.get_days_in_month ((DateMonth) nm, (DateYear) ny);
            return DateSerial.from_ymd (ny, nm, int.min (d, dim)) + (serial - Math.floor (serial));
        }

        public static string vba_format (Value v, string fmt, bool d1904) {
            string color;
            string f = fmt;
            switch (fmt.down ()) {
                case "general number": f = "General"; break;
                case "currency": f = "$#,##0.00;($#,##0.00)"; break;
                case "fixed": f = "0.00"; break;
                case "standard": f = "#,##0.00"; break;
                case "percent": f = "0.00%"; break;
                case "scientific": f = "0.00E+00"; break;
                case "yes/no": return v.kind == ValueKind.NUMBER && v.number != 0 ? "Yes" : "No";
                case "true/false": return v.kind == ValueKind.NUMBER && v.number != 0 ? "True" : "False";
                case "on/off": return v.kind == ValueKind.NUMBER && v.number != 0 ? "On" : "Off";
                case "general date": f = LocaleInfo.get ().short_date_format () + " h:mm:ss AM/PM"; break;
                case "long date": f = "dddd, mmmm d, yyyy"; break;
                case "medium date": f = "dd-mmm-yy"; break;
                case "short date": f = LocaleInfo.get ().short_date_format (); break;
                case "long time": f = "h:mm:ss AM/PM"; break;
                case "medium time": f = "hh:mm AM/PM"; break;
                case "short time": f = "hh:mm"; break;
                case "": return v.kind == ValueKind.TEXT ? v.text : Evaluator.to_text (v);
                default:
                    f = fmt.replace ("nn", "mm").replace ("Nn", "mm").replace ("NN", "mm");
                    if (f.contains (":n")) f = f.replace (":n", ":m");
                    break;
            }
            return NumberFormat.format_value (v, f, out color, d1904);
        }

        public static string r1c1_to_a1 (string formula, int row, int col) {
            var sb = new StringBuilder ();
            int i = 0, n = formula.length;
            bool in_str = false;
            while (i < n) {
                char ch = formula[i];
                if (ch == '"') {
                    in_str = !in_str;
                    sb.append_c (ch);
                    i++;
                    continue;
                }
                if (in_str || (ch != 'R' && ch != 'r' && ch != 'C' && ch != 'c') || (i > 0 && (formula[i - 1].isalnum () || formula[i - 1] == '_' || formula[i - 1] == '.'))) {
                    sb.append_c (ch);
                    i++;
                    continue;
                }
                int j = i;
                bool has_r = false, has_c = false, rabs = false, cabs = false;
                int rv = 0, cv = 0;
                if (formula[j] == 'R' || formula[j] == 'r') {
                    has_r = true;
                    j++;
                    if (j < n && formula[j] == '[') {
                        int e = formula.index_of_char (']', j);
                        if (e < 0) break;
                        rv = int.parse (formula.substring (j + 1, e - j - 1));
                        j = e + 1;
                    } else if (j < n && formula[j].isdigit ()) {
                        int s0 = j;
                        while (j < n && formula[j].isdigit ()) j++;
                        rv = int.parse (formula.substring (s0, j - s0));
                        rabs = true;
                    }
                }
                if (j < n && (formula[j] == 'C' || formula[j] == 'c')) {
                    has_c = true;
                    j++;
                    if (j < n && formula[j] == '[') {
                        int e = formula.index_of_char (']', j);
                        if (e < 0) break;
                        cv = int.parse (formula.substring (j + 1, e - j - 1));
                        j = e + 1;
                    } else if (j < n && formula[j].isdigit ()) {
                        int s0 = j;
                        while (j < n && formula[j].isdigit ()) j++;
                        cv = int.parse (formula.substring (s0, j - s0));
                        cabs = true;
                    }
                }
                if (j < n && (formula[j].isalpha () || formula[j] == '(' || formula[j] == '_')) {
                    sb.append_c (ch);
                    i++;
                    continue;
                }
                if (!has_r && !has_c) {
                    sb.append_c (ch);
                    i++;
                    continue;
                }
                int r = rabs ? rv - 1 : row + rv;
                int cc = cabs ? cv - 1 : col + cv;
                if (has_r && has_c) {
                    sb.append ((cabs ? "$" : "") + Address.column_name (cc.clamp (0, MAX_COLS - 1)) + (rabs ? "$" : "") + (r.clamp (0, MAX_ROWS - 1) + 1).to_string ());
                } else if (has_r) {
                    sb.append ((rabs ? "$" : "") + (r.clamp (0, MAX_ROWS - 1) + 1).to_string () + ":" + (rabs ? "$" : "") + (r.clamp (0, MAX_ROWS - 1) + 1).to_string ());
                } else {
                    string cn = Address.column_name (cc.clamp (0, MAX_COLS - 1));
                    sb.append ((cabs ? "$" : "") + cn + ":" + (cabs ? "$" : "") + cn);
                }
                i = j;
            }
            return sb.str;
        }

        public static string a1_to_r1c1 (Node n, Sheet own, int row, int col) {
            var copy = n.copy ();
            var sb = new StringBuilder ("=");
            sb.append (render_r1c1 (copy, own, row, col));
            return sb.str;
        }

        private static string part (RefPart p, int row, int col, bool rows_only, bool cols_only) {
            string r = p.abs_row ? "R%d".printf (p.row + 1) : (p.row - row == 0 ? "R" : "R[%d]".printf (p.row - row));
            string c = p.abs_col ? "C%d".printf (p.col + 1) : (p.col - col == 0 ? "C" : "C[%d]".printf (p.col - col));
            if (rows_only) return r;
            if (cols_only) return c;
            return r + c;
        }

        private static int prec (string op) {
            switch (op) {
                case "=": case "<>": case "<": case ">": case "<=": case ">=": return 1;
                case "&": return 2;
                case "+": case "-": return 3;
                case "*": case "/": return 4;
                case "^": return 5;
                case ":": return 8;
                default: return 0;
            }
        }

        private static string render_r1c1 (Node n, Sheet own, int row, int col, int parent = 0) {
            switch (n.kind) {
                case NodeKind.REF:
                    if (n.a == null) return "#REF!";
                    string prefix = Formula.sheet_prefix (n, own);
                    string a = part (n.a, row, col, n.whole_rows, n.whole_cols);
                    if (n.b == null) return prefix + a;
                    return prefix + a + ":" + part (n.b, row, col, n.whole_rows, n.whole_cols);
                case NodeKind.BINARY:
                    int p = prec (n.op);
                    string l = render_r1c1 (n.args[0], own, row, col, p);
                    string r = render_r1c1 (n.args[1], own, row, col, p + (n.op == "^" ? 0 : 1));
                    string s = l + n.op + r;
                    return p < parent ? "(" + s + ")" : s;
                case NodeKind.UNARY:
                    return n.op + render_r1c1 (n.args[0], own, row, col, 6);
                case NodeKind.PERCENT:
                    return render_r1c1 (n.args[0], own, row, col, 7) + "%";
                case NodeKind.CALL:
                    string[] parts = {};
                    foreach (var arg in n.args) parts += render_r1c1 (arg, own, row, col, 0);
                    return n.text + "(" + string.joinv (",", parts) + ")";
                default:
                    return Formula.render (n, own, parent);
            }
        }
    }
}
