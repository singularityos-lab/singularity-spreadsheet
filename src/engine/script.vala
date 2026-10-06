namespace Singularity.Apps.Spreadsheet {

    public enum SKind {
        EMPTY,
        NUM,
        STR,
        BOOL,
        ARRAY,
        RANGE,
        SHEET,
        BOOK,
        FUNCS,
        SHEETS,
        APP,
        COLL,
        DICT,
        ERR,
        NAMES,
        NAME,
        PAGESETUP,
        NOTHING,
        DEBUG,
        WINDOW,
        BREAKS,
        ERRVAL
    }

    public class SVal {
        public SKind kind;
        public double num;
        public string str = "";
        public Gee.ArrayList<SVal>? items;
        public Gee.ArrayList<string>? keys;
        public Sheet? sheet;
        public Area? area;
        public int count_mode;
        public string facet = "";
        public int lbound;
        public bool is_date;
        public bool missing;

        public SVal (SKind kind) {
            this.kind = kind;
        }

        public static SVal n (double d) {
            var v = new SVal (SKind.NUM);
            v.num = d;
            return v;
        }

        public static SVal date (double d) {
            var v = n (d);
            v.is_date = true;
            return v;
        }

        public static SVal s (string t) {
            var v = new SVal (SKind.STR);
            v.str = t;
            return v;
        }

        public static SVal b (bool x) {
            var v = new SVal (SKind.BOOL);
            v.num = x ? 1 : 0;
            return v;
        }

        public static SVal empty () {
            return new SVal (SKind.EMPTY);
        }

        public static SVal nothing () {
            return new SVal (SKind.NOTHING);
        }

        public static SVal omitted () {
            var v = new SVal (SKind.EMPTY);
            v.missing = true;
            return v;
        }

        public static SVal arr (Gee.ArrayList<SVal> list, int lbound = 0) {
            var v = new SVal (SKind.ARRAY);
            v.items = list;
            v.lbound = lbound;
            return v;
        }

        public static SVal range (Sheet s, Area a) {
            var v = new SVal (SKind.RANGE);
            v.sheet = s;
            v.area = new Area (s, a.r1, a.c1, a.r2, a.c2);
            return v;
        }

        public static SVal of_sheet (Sheet s) {
            var v = new SVal (SKind.SHEET);
            v.sheet = s;
            return v;
        }

        public static SVal obj (SKind k, string facet = "") {
            var v = new SVal (k);
            v.facet = facet;
            return v;
        }

        public bool is_object () {
            return kind != SKind.EMPTY && kind != SKind.NUM && kind != SKind.STR && kind != SKind.BOOL && kind != SKind.ARRAY && kind != SKind.ERRVAL;
        }

        public SVal copy () {
            if (kind != SKind.ARRAY) return this;
            var list = new Gee.ArrayList<SVal> ();
            foreach (var i in items) list.add (i.copy ());
            return arr (list, lbound);
        }

        public static string num_text (double d) {
            if (d == Math.floor (d) && Math.fabs (d) < 1e15) return "%.0f".printf (d);
            string t = Value.ascii (d, "%.15g");
            if (t.contains ("e")) {
                int e = t.index_of ("e");
                string mant = t.substring (0, e);
                int ev = int.parse (t.substring (e + 1));
                return "%sE%s%02d".printf (mant, ev < 0 ? "-" : "+", ev.abs ());
            }
            return t;
        }

        public string text () {
            switch (kind) {
                case SKind.NUM:
                    if (is_date) return ScriptLib.date_text (num);
                    return num_text (num);
                case SKind.STR: return str;
                case SKind.BOOL: return num != 0 ? "True" : "False";
                case SKind.ARRAY:
                    string[] parts = {};
                    foreach (var i in items) parts += i.text ();
                    return string.joinv (", ", parts);
                case SKind.RANGE: return area.to_string ();
                case SKind.SHEET: return sheet.name;
                case SKind.ERRVAL: return "Error %s".printf (num_text (num));
                default: return "";
            }
        }
    }

    public enum STok {
        NUM,
        STR,
        IDENT,
        OP,
        NL,
        END
    }

    public class SToken {
        public STok kind;
        public string text;
        public string low;
        public double num;
        public int line;
        public bool colon;
        public bool date;
        public bool bracket;

        public SToken (STok kind, string text, int line) {
            this.kind = kind;
            this.text = text;
            this.low = text.down ();
            this.line = line;
        }
    }

    public enum SN {
        NUM,
        STR,
        BOOL,
        IDENT,
        CALL,
        MEMBER,
        UNARY,
        BINARY,
        ASSIGN,
        EXPR,
        IF,
        FOR,
        FOREACH,
        WHILE,
        DO,
        EXIT,
        RETURN,
        DIM,
        SELECT,
        ONERROR,
        BLOCK,
        NOTHING,
        WITH,
        GOTO,
        LABEL,
        RESUME,
        FORBID,
        NEW,
        NAMED,
        ERASE,
        END,
        DATE,
        EMPTYV
    }

    public class SNode {
        public SN kind;
        public int line;
        public string name = "";
        public double num;
        public SNode[] args = {};
        public SNode? a;
        public SNode? b;
        public SNode? c;
        public SNode? body;
        public SNode? other;
        public bool flag;
        public bool until;
        public bool post;
        public bool parens;
        public bool is_const;
        public bool preserve;
        public string type_name = "";
        public SNode[] bounds = {};

        public SNode (SN kind, int line) {
            this.kind = kind;
            this.line = line;
        }
    }

    public class SParam {
        public string name;
        public bool byval;
        public bool optional;
        public bool paramarray;
        public SNode? def;
        public string type_name = "";

        public SParam (string name) {
            this.name = name;
        }
    }

    public class SProc {
        public string name;
        public SParam[] params = {};
        public bool is_function;
        public SNode body;
        public int line;
        public string module = "";
        public string broken = "";
        public string forbidden = "";
        public string type_name = "";
    }

    public class Script {
        private SToken[] toks = {};
        private int pos;
        public Gee.HashMap<string, SProc> procs = new Gee.HashMap<string, SProc> ();
        public SNode main;
        public Gee.ArrayList<string> problems = new Gee.ArrayList<string> ();
        public Gee.HashMap<string, double?> enums = new Gee.HashMap<string, double?> ();
        public string module_name = "";

        private const string[] FORBIDDEN_STATEMENTS = { "open", "close", "kill", "mkdir", "rmdir", "chdir", "chdrive", "filecopy", "setattr", "lock", "unlock", "put", "get", "seek", "write", "input", "line", "reset", "sendkeys", "appactivate", "savesetting", "deletesetting", "print" };

        public static Gee.ArrayList<string> list_subs (string source) {
            var list = new Gee.ArrayList<string> ();
            foreach (string raw in source.split ("\n")) {
                string l = raw.strip ();
                string low = l.down ();
                foreach (string mod in new string[] { "public ", "private ", "friend ", "static " }) {
                    if (low.has_prefix (mod)) {
                        if (mod == "private ") {
                            l = "";
                            break;
                        }
                        l = l.substring (mod.length).strip ();
                        low = l.down ();
                    }
                }
                if (low.has_prefix ("sub ")) {
                    string rest = l.substring (4).strip ();
                    int p = rest.index_of ("(");
                    string name = (p >= 0 ? rest.substring (0, p) : rest).strip ();
                    if (p >= 0) {
                        string args = rest.substring (p);
                        int close = args.index_of (")");
                        if (close < 0 || args.substring (1, close - 1).strip () != "") continue;
                    }
                    if (name != "") list.add (name);
                }
            }
            return list;
        }

        public static string remove_sub (string source, string name) {
            var sb = new StringBuilder ();
            bool skip = false;
            foreach (string raw in source.split ("\n")) {
                string low = raw.strip ().down ();
                string plain = low.has_prefix ("public ") ? low.substring (7) : low;
                if (!skip && plain.has_prefix ("sub ")) {
                    string rest = raw.strip ().substring (raw.strip ().length - plain.length + 4).strip ();
                    int p = rest.index_of ("(");
                    string n = (p >= 0 ? rest.substring (0, p) : rest).strip ();
                    if (n.casefold () == name.casefold ()) {
                        skip = true;
                        continue;
                    }
                }
                if (skip) {
                    if (low == "end sub") skip = false;
                    continue;
                }
                sb.append (raw);
                sb.append ("\n");
            }
            string r = sb.str;
            while (r.has_suffix ("\n\n")) r = r.substring (0, r.length - 1);
            return r.strip () == "" ? "" : r;
        }

        public static Script parse (string source) throws ScriptError {
            var s = new Script ();
            s.tokenize (source);
            s.parse_program (false);
            return s;
        }

        public static Script parse_lenient (string source) throws ScriptError {
            var s = new Script ();
            s.tokenize (source);
            s.parse_program (true);
            return s;
        }

        private bool value_before () {
            if (toks.length == 0) return false;
            var t = toks[toks.length - 1];
            return t.kind == STok.NUM || t.kind == STok.STR || t.kind == STok.IDENT || (t.kind == STok.OP && t.text == ")");
        }

        private void tokenize (string src) throws ScriptError {
            int i = 0, n = src.length, line = 1;
            while (i < n) {
                char c = src[i];
                if (c == ' ' || c == '\t' || c == '\r') {
                    i++;
                    continue;
                }
                if (c == '_' && i > 0 && (src[i - 1] == ' ' || src[i - 1] == '\t')) {
                    int j = i + 1;
                    while (j < n && (src[j] == ' ' || src[j] == '\t' || src[j] == '\r')) j++;
                    if (j >= n || src[j] == '\n') {
                        i = j + 1;
                        line++;
                        continue;
                    }
                }
                if (c == '\'') {
                    while (i < n && src[i] != '\n') i++;
                    continue;
                }
                if (c == ':' && i + 1 < n && src[i + 1] == '=') {
                    toks += new SToken (STok.OP, ":=", line);
                    i += 2;
                    continue;
                }
                if (c == '\n' || c == ':') {
                    var t = new SToken (STok.NL, "\n", line);
                    t.colon = c == ':';
                    toks += t;
                    if (c == '\n') line++;
                    i++;
                    continue;
                }
                if (c == '"') {
                    var sb = new StringBuilder ();
                    i++;
                    while (true) {
                        if (i >= n || src[i] == '\n') throw new ScriptError.SYNTAX ("%d: %s", line, _("unterminated string"));
                        if (src[i] == '"') {
                            if (i + 1 < n && src[i + 1] == '"') {
                                sb.append_c ('"');
                                i += 2;
                                continue;
                            }
                            i++;
                            break;
                        }
                        sb.append_c (src[i]);
                        i++;
                    }
                    toks += new SToken (STok.STR, sb.str, line);
                    continue;
                }
                if (c == '#' && !value_before ()) {
                    int end = src.index_of_char ('#', i + 1);
                    int nl = src.index_of_char ('\n', i + 1);
                    if (end > i && (nl < 0 || end < nl)) {
                        string lit = src.substring (i + 1, end - i - 1);
                        double serial;
                        if (ScriptLib.parse_date_literal (lit, out serial)) {
                            var t = new SToken (STok.NUM, lit, line);
                            t.num = serial;
                            t.date = true;
                            toks += t;
                            i = end + 1;
                            continue;
                        }
                    }
                    toks += new SToken (STok.OP, "#", line);
                    i++;
                    continue;
                }
                if (c == '&' && i + 1 < n && (src[i + 1] == 'H' || src[i + 1] == 'h' || src[i + 1] == 'O' || src[i + 1] == 'o') && !value_before ()) {
                    bool hex = src[i + 1] == 'H' || src[i + 1] == 'h';
                    int st = i + 2;
                    int j = st;
                    while (j < n && (hex ? src[j].isxdigit () : (src[j] >= '0' && src[j] <= '7'))) j++;
                    if (j > st) {
                        var t = new SToken (STok.NUM, src.substring (i, j - i), line);
                        t.num = (double) int64.parse ((hex ? "0x" : "0") + src.substring (st, j - st));
                        if (j < n && src[j] == '&') j++;
                        toks += t;
                        i = j;
                        continue;
                    }
                }
                if (c.isdigit () || (c == '.' && i + 1 < n && src[i + 1].isdigit () && !value_before ())) {
                    int st = i;
                    while (i < n && (src[i].isdigit () || src[i] == '.')) i++;
                    if (i < n && (src[i] == 'e' || src[i] == 'E') && i + 1 < n && (src[i + 1].isdigit () || ((src[i + 1] == '-' || src[i + 1] == '+') && i + 2 < n && src[i + 2].isdigit ()))) {
                        i += 2;
                        while (i < n && src[i].isdigit ()) i++;
                    }
                    var t = new SToken (STok.NUM, src.substring (st, i - st), line);
                    t.num = double.parse (t.text);
                    if (i < n && "%&!#@".index_of_char (src[i]) >= 0 && (i + 1 >= n || !src[i + 1].isalnum ())) i++;
                    toks += t;
                    continue;
                }
                if (c.isalpha () || c == '_' || (uchar) c >= 0x80 || c == '[') {
                    if (c == '[') {
                        int end = src.index_of_char (']', i);
                        if (end > i) {
                            var bt = new SToken (STok.IDENT, src.substring (i + 1, end - i - 1), line);
                            bt.bracket = true;
                            toks += bt;
                            i = end + 1;
                            continue;
                        }
                    }
                    int st = i;
                    while (i < n && (src[i].isalnum () || src[i] == '_' || (uchar) src[i] >= 0x80)) i++;
                    string w = src.substring (st, i - st);
                    if (i < n && (src[i] == '$' || src[i] == '%') ) i++;
                    else if (i < n && (src[i] == '!' || src[i] == '#' || src[i] == '@') && (i + 1 >= n || src[i + 1] == ' ' || src[i + 1] == ')' || src[i + 1] == ',' || src[i + 1] == '\n' || src[i + 1] == '\r')) i++;
                    if (w.down () == "rem") {
                        while (i < n && src[i] != '\n') i++;
                        continue;
                    }
                    toks += new SToken (STok.IDENT, w, line);
                    continue;
                }
                if (i + 1 < n) {
                    string two = src.substring (i, 2);
                    if (two == "<>" || two == "<=" || two == ">=" || two == "=<" || two == "=>") {
                        string norm = two == "=<" ? "<=" : (two == "=>" ? ">=" : two);
                        toks += new SToken (STok.OP, norm, line);
                        i += 2;
                        continue;
                    }
                }
                if ("+-*/\\^&=<>(),.;!#".index_of_char (c) >= 0) {
                    toks += new SToken (STok.OP, c.to_string (), line);
                    i++;
                    continue;
                }
                throw new ScriptError.SYNTAX ("%d: %s", line, _("unexpected character %s").printf (c.to_string ()));
            }
            toks += new SToken (STok.NL, "\n", line);
            toks += new SToken (STok.END, "", line);
        }

        private SToken peek (int ahead = 0) {
            int p = int.min (pos + ahead, toks.length - 1);
            return toks[p];
        }

        private SToken next () {
            var t = toks[pos];
            if (pos < toks.length - 1) pos++;
            return t;
        }

        private bool is_kw (string w, int ahead = 0) {
            var t = peek (ahead);
            return t.kind == STok.IDENT && t.low == w;
        }

        private bool is_op (string o) {
            var t = peek ();
            return t.kind == STok.OP && t.text == o;
        }

        private void expect_op (string o) throws ScriptError {
            if (!is_op (o)) fail (_("expected %s").printf (o));
            next ();
        }

        private void expect_kw (string w) throws ScriptError {
            if (!is_kw (w)) fail (_("expected %s").printf (w));
            next ();
        }

        private void fail (string msg) throws ScriptError {
            var t = peek ();
            throw new ScriptError.SYNTAX ("%d: %s", t.line, msg + (t.text != "" && t.text != "\n" ? " (" + t.text + ")" : ""));
        }

        private void skip_nl () {
            while (peek ().kind == STok.NL) next ();
        }

        private bool at_end_of_stmt () {
            var t = peek ();
            return t.kind == STok.NL || t.kind == STok.END || is_kw ("else");
        }

        private void end_stmt () throws ScriptError {
            if (is_kw ("else")) return;
            if (peek ().kind == STok.NL) {
                next ();
                return;
            }
            if (peek ().kind == STok.END) return;
            fail (_("expected end of line"));
        }

        private void skip_line () {
            while (peek ().kind != STok.NL && peek ().kind != STok.END) next ();
            if (peek ().kind == STok.NL) next ();
        }

        private void skip_to_line_start_pair (string a, string b) {
            while (peek ().kind != STok.END) {
                bool line_start = pos == 0 || toks[pos - 1].kind == STok.NL;
                if (line_start && is_kw (a) && is_kw (b, 1)) {
                    next ();
                    next ();
                    skip_line ();
                    return;
                }
                next ();
            }
        }

        private void skip_modifiers () {
            while (is_kw ("public") || is_kw ("private") || is_kw ("friend") || is_kw ("global") || (is_kw ("static") && (is_kw ("sub", 1) || is_kw ("function", 1) || is_kw ("property", 1)))) next ();
        }

        private SParam[] parse_params () throws ScriptError {
            SParam[] ps = {};
            if (!is_op ("(")) return ps;
            next ();
            while (!is_op (")")) {
                bool optional = false, byval = false, paramarray = false;
                while (is_kw ("byval") || is_kw ("byref") || is_kw ("optional") || is_kw ("paramarray")) {
                    var k = next ();
                    if (k.low == "optional") optional = true;
                    else if (k.low == "byval") byval = true;
                    else if (k.low == "paramarray") paramarray = true;
                }
                var pt = next ();
                if (pt.kind != STok.IDENT) fail (_("expected a parameter name"));
                var p = new SParam (pt.text);
                p.optional = optional;
                p.byval = byval;
                p.paramarray = paramarray;
                if (is_op ("(")) {
                    next ();
                    expect_op (")");
                }
                if (is_kw ("as")) {
                    next ();
                    p.type_name = parse_type ();
                }
                if (is_op ("=")) {
                    next ();
                    p.def = parse_expr ();
                }
                ps += p;
                if (is_op (",")) next ();
                else if (!is_op (")")) fail (_("expected , or )"));
            }
            next ();
            return ps;
        }

        private string parse_type () throws ScriptError {
            if (is_kw ("new")) next ();
            var t = next ();
            string name = t.text;
            while (is_op (".")) {
                next ();
                name += "." + next ().text;
            }
            if (is_op ("*")) {
                next ();
                next ();
            }
            return name.down ();
        }

        private void parse_program (bool lenient) throws ScriptError {
            var top = new SNode (SN.BLOCK, 1);
            SNode[] stmts = {};
            skip_nl ();
            while (peek ().kind != STok.END) {
                int start = pos;
                try {
                    if (is_kw ("option") || is_kw ("attribute") || is_kw ("implements") || is_kw ("defint") || is_kw ("deflng") || is_kw ("defstr") || is_kw ("defdbl") || is_kw ("defvar") || is_kw ("defbool") || ((is_kw ("public") || is_kw ("private")) && is_kw ("event", 1)) || is_kw ("event")) {
                        skip_line ();
                        skip_nl ();
                        continue;
                    }
                    int mark = pos;
                    skip_modifiers ();
                    if (is_kw ("declare")) {
                        next ();
                        if (is_kw ("ptrsafe")) next ();
                        next ();
                        var p = new SProc ();
                        p.line = peek ().line;
                        p.name = next ().text;
                        p.forbidden = _("calls to the Windows API (Declare %s) are not allowed").printf (p.name);
                        p.body = new SNode (SN.BLOCK, p.line);
                        p.module = module_name;
                        procs[p.name.down ()] = p;
                        skip_line ();
                    } else if (is_kw ("type")) {
                        int line = next ().line;
                        string tname = next ().text;
                        problems.add (_("line %d: user-defined type %s is not supported").printf (line, tname));
                        skip_to_line_start_pair ("end", "type");
                    } else if (is_kw ("enum")) {
                        next ();
                        next ();
                        skip_line ();
                        double v = 0;
                        while (!(is_kw ("end") && is_kw ("enum", 1)) && peek ().kind != STok.END) {
                            skip_nl ();
                            if (is_kw ("end") && is_kw ("enum", 1)) break;
                            string ename = next ().text;
                            if (is_op ("=")) {
                                next ();
                                var e = parse_expr ();
                                v = const_value (e);
                            }
                            enums[ename.down ()] = v;
                            v++;
                            skip_line ();
                        }
                        next ();
                        next ();
                        skip_line ();
                    } else if (is_kw ("sub") || is_kw ("function") || is_kw ("property")) {
                        parse_proc (lenient);
                    } else {
                        if (pos != mark && !is_kw ("dim") && !is_kw ("const") && !is_kw ("static")) {
                            stmts += parse_dim (false);
                        } else {
                            stmts += parse_stmt ();
                        }
                    }
                } catch (ScriptError e) {
                    if (!lenient) throw e;
                    problems.add (e.message);
                    if (pos == start) next ();
                    skip_line ();
                }
                skip_nl ();
            }
            top.args = stmts;
            main = top;
        }

        private double const_value (SNode e) {
            if (e.kind == SN.NUM) return e.num;
            if (e.kind == SN.UNARY && e.name == "-" && e.a.kind == SN.NUM) return -e.a.num;
            if (e.kind == SN.IDENT && enums.has_key (e.name.down ())) return enums[e.name.down ()];
            return 0;
        }

        private void parse_proc (bool lenient) throws ScriptError {
            bool prop = is_kw ("property");
            string kind = next ().low;
            string accessor = "";
            if (prop) {
                accessor = next ().low;
                kind = "property";
            }
            var p = new SProc ();
            p.line = peek ().line;
            p.module = module_name;
            p.is_function = kind == "function" || (prop && accessor == "get");
            var nt = next ();
            if (nt.kind != STok.IDENT) fail (_("expected a name"));
            p.name = nt.text;
            string ender = kind == "property" ? "property" : kind;
            try {
                p.params = parse_params ();
                if (is_kw ("as")) {
                    next ();
                    p.type_name = parse_type ();
                }
                end_stmt ();
                p.body = parse_block ({ "end " + ender });
                expect_kw ("end");
                expect_kw (ender);
                end_stmt ();
            } catch (ScriptError e) {
                if (!lenient) throw e;
                p.broken = e.message;
                p.body = new SNode (SN.BLOCK, p.line);
                problems.add (_("%s: %s").printf (p.name, e.message));
                skip_to_line_start_pair ("end", ender);
            }
            if (prop && accessor != "get") return;
            procs[p.name.down ()] = p;
        }

        private bool at_any (string[] words) {
            foreach (string w in words) {
                if (w.contains (" ")) {
                    string[] p = w.split (" ");
                    if (is_kw (p[0]) && is_kw (p[1], 1)) return true;
                } else if (is_kw (w)) {
                    return true;
                }
            }
            return false;
        }

        private SNode parse_block (string[] enders) throws ScriptError {
            var b = new SNode (SN.BLOCK, peek ().line);
            SNode[] stmts = {};
            skip_nl ();
            while (!at_any (enders)) {
                if (peek ().kind == STok.END) fail (_("unexpected end of script, expected %s").printf (enders[0]));
                if (is_kw ("end") && (is_kw ("sub", 1) || is_kw ("function", 1) || is_kw ("property", 1))) fail (_("expected %s").printf (enders[0]));
                stmts += parse_stmt ();
                skip_nl ();
            }
            b.args = stmts;
            return b;
        }

        private SNode parse_dim (bool is_const) throws ScriptError {
            int line = peek ().line;
            var d = new SNode (SN.BLOCK, line);
            SNode[] decls = {};
            while (true) {
                if (is_kw ("withevents")) next ();
                var nt = next ();
                if (nt.kind != STok.IDENT) fail (_("expected a name"));
                var dn = new SNode (SN.DIM, line);
                dn.name = nt.text;
                dn.is_const = is_const;
                if (is_op ("(")) {
                    next ();
                    dn.flag = true;
                    SNode[] bounds = {};
                    while (!is_op (")")) {
                        var lo = parse_expr ();
                        if (is_kw ("to")) {
                            next ();
                            var hi = parse_expr ();
                            var pair = new SNode (SN.BINARY, line);
                            pair.name = "to";
                            pair.a = lo;
                            pair.b = hi;
                            bounds += pair;
                        } else {
                            bounds += lo;
                        }
                        if (is_op (",")) next ();
                        else if (!is_op (")")) fail (_("expected , or )"));
                    }
                    next ();
                    dn.bounds = bounds;
                }
                if (is_kw ("as")) {
                    next ();
                    if (is_kw ("new")) {
                        next ();
                        dn.type_name = parse_type ();
                        var nn = new SNode (SN.NEW, line);
                        nn.name = dn.type_name;
                        dn.b = nn;
                    } else {
                        dn.type_name = parse_type ();
                    }
                }
                if (is_op ("=")) {
                    next ();
                    dn.b = parse_expr ();
                }
                decls += dn;
                if (!is_op (",")) break;
                next ();
            }
            end_stmt ();
            d.args = decls;
            return d;
        }

        private SNode forbid (int line, string what) {
            var f = new SNode (SN.FORBID, line);
            f.name = what;
            skip_line ();
            return f;
        }

        private SNode parse_stmt () throws ScriptError {
            var t = peek ();
            int line = t.line;
            bool at_line_start = pos == 0 || (toks[pos - 1].kind == STok.NL && !toks[pos - 1].colon);
            if (at_line_start && t.kind == STok.IDENT && peek (1).kind == STok.NL && peek (1).colon && !is_kw ("else") && !is_kw ("end") && !is_kw ("next") && !is_kw ("loop") && !is_kw ("wend")) {
                next ();
                next ();
                var lab = new SNode (SN.LABEL, line);
                lab.name = t.low;
                return lab;
            }
            if (t.kind == STok.NUM && (peek (1).kind == STok.IDENT || peek (1).kind == STok.NL)) {
                bool line_start = pos == 0 || toks[pos - 1].kind == STok.NL;
                if (line_start) {
                    next ();
                    if (peek ().kind == STok.NL && peek ().colon) next ();
                    var lab = new SNode (SN.LABEL, line);
                    lab.name = Value.format_number_general_full (t.num);
                    return lab;
                }
            }
            bool is_set = t.kind == STok.IDENT && t.low == "set";
            if (t.kind == STok.IDENT) {
                switch (t.low) {
                    case "if": return parse_if ();
                    case "for": return parse_for ();
                    case "while":
                        next ();
                        var w = new SNode (SN.WHILE, line);
                        w.a = parse_expr ();
                        end_stmt ();
                        w.body = parse_block ({ "wend", "end while" });
                        if (is_kw ("wend")) next ();
                        else {
                            next ();
                            next ();
                        }
                        end_stmt ();
                        return w;
                    case "do": return parse_do ();
                    case "select": return parse_select ();
                    case "with":
                        next ();
                        var wn = new SNode (SN.WITH, line);
                        wn.a = parse_expr ();
                        end_stmt ();
                        wn.body = parse_block ({ "end with" });
                        next ();
                        next ();
                        end_stmt ();
                        return wn;
                    case "exit":
                        next ();
                        var e = new SNode (SN.EXIT, line);
                        e.name = next ().low;
                        end_stmt ();
                        return e;
                    case "end":
                        if (peek (1).kind == STok.NL || peek (1).kind == STok.END) {
                            next ();
                            end_stmt ();
                            return new SNode (SN.END, line);
                        }
                        break;
                    case "stop":
                    case "doevents":
                    case "beep":
                    case "randomize":
                        if (t.low != "doevents" || peek (1).kind == STok.NL) {
                            next ();
                            if (t.low == "randomize" && !at_end_of_stmt ()) parse_expr ();
                            end_stmt ();
                            return new SNode (SN.BLOCK, line);
                        }
                        break;
                    case "return":
                        next ();
                        var r = new SNode (SN.RETURN, line);
                        if (!at_end_of_stmt ()) r.a = parse_expr ();
                        end_stmt ();
                        return r;
                    case "goto":
                        next ();
                        var g = new SNode (SN.GOTO, line);
                        g.name = next ().text.down ();
                        end_stmt ();
                        return g;
                    case "gosub":
                        return forbid (line, _("GoSub is not supported"));
                    case "resume":
                        next ();
                        var rs = new SNode (SN.RESUME, line);
                        if (is_kw ("next")) {
                            next ();
                            rs.name = "next";
                        } else if (!at_end_of_stmt ()) {
                            rs.name = next ().text.down ();
                        }
                        end_stmt ();
                        return rs;
                    case "erase":
                        next ();
                        var er = new SNode (SN.ERASE, line);
                        SNode[] names = {};
                        while (true) {
                            names += parse_postfix ();
                            if (!is_op (",")) break;
                            next ();
                        }
                        er.args = names;
                        end_stmt ();
                        return er;
                    case "dim":
                    case "static":
                        next ();
                        return parse_dim (false);
                    case "const":
                        next ();
                        return parse_dim (true);
                    case "public":
                    case "private":
                    case "global":
                        next ();
                        if (is_kw ("const")) {
                            next ();
                            return parse_dim (true);
                        }
                        if (is_kw ("dim")) next ();
                        return parse_dim (false);
                    case "redim":
                        next ();
                        bool preserve = false;
                        if (is_kw ("preserve")) {
                            next ();
                            preserve = true;
                        }
                        var rd = parse_dim (false);
                        foreach (var dn in rd.args) {
                            dn.preserve = preserve;
                            dn.until = true;
                        }
                        return rd;
                    case "on":
                        next ();
                        if (!is_kw ("error")) return forbid (line, _("On ... GoTo/GoSub is not supported"));
                        next ();
                        var oe = new SNode (SN.ONERROR, line);
                        if (is_kw ("resume")) {
                            next ();
                            expect_kw ("next");
                            oe.name = "next";
                        } else {
                            if (is_kw ("goto")) next ();
                            var target = next ();
                            oe.name = target.kind == STok.NUM && target.num == 0 ? "0" : target.text.down ();
                            if (is_op ("-")) {
                                next ();
                                next ();
                                oe.name = "0";
                            }
                        }
                        end_stmt ();
                        return oe;
                    case "call":
                        next ();
                        var ce = new SNode (SN.EXPR, line);
                        ce.a = parse_postfix ();
                        end_stmt ();
                        return ce;
                    case "set":
                    case "let":
                    case "lset":
                    case "rset":
                        next ();
                        break;
                    case "print":
                        if (peek (1).kind == STok.OP && peek (1).text == "#") return forbid (line, _("file output is not allowed"));
                        break;
                    case "mid":
                        break;
                    default:
                        bool hash_next = peek (1).kind == STok.OP && peek (1).text == "#";
                        if (t.low in FORBIDDEN_STATEMENTS) {
                            bool always = t.low == "open" || t.low == "kill" || t.low == "mkdir" || t.low == "rmdir" || t.low == "chdir" || t.low == "chdrive" || t.low == "filecopy" || t.low == "setattr" || t.low == "sendkeys" || t.low == "appactivate" || t.low == "savesetting" || t.low == "deletesetting";
                            bool bare_close = (t.low == "close" || t.low == "reset") && (peek (1).kind == STok.NL || peek (1).kind == STok.END);
                            bool line_input = t.low == "line" && is_kw ("input", 1);
                            if ((always && !(peek (1).kind == STok.OP && (peek (1).text == "=" || peek (1).text == "."))) || hash_next || bare_close || line_input)
                                return forbid (line, _("%s touches files or the system and is not allowed").printf (t.text));
                        }
                        break;
                }
            }
            var target = parse_postfix ();
            if (is_op ("=")) {
                next ();
                var asg = new SNode (SN.ASSIGN, line);
                asg.a = target;
                asg.flag = is_set;
                asg.b = parse_expr ();
                end_stmt ();
                return asg;
            }
            var st = new SNode (SN.EXPR, line);
            if (!at_end_of_stmt ()) {
                SNode[] args = {};
                if (target.kind == SN.CALL && target.parens && target.args.length == 1 && !target.a.name.has_prefix ("__")) {
                    SNode first = target.args[0];
                    if (!is_op (",")) first = parse_expr_from (first);
                    target = target.a;
                    args += first;
                    if (is_op (",")) next ();
                }
                while (!at_end_of_stmt ()) {
                    if (is_op (",")) {
                        args += missing_arg ();
                        next ();
                        continue;
                    }
                    args += parse_arg ();
                    if (!is_op (",")) break;
                    next ();
                    if (at_end_of_stmt ()) args += missing_arg ();
                }
                var call = new SNode (SN.CALL, line);
                call.a = target;
                call.args = args;
                st.a = call;
            } else {
                st.a = target;
            }
            end_stmt ();
            return st;
        }

        private SNode missing_arg () {
            var m = new SNode (SN.EMPTYV, peek ().line);
            m.name = "__missing";
            return m;
        }

        private SNode parse_arg () throws ScriptError {
            if (peek ().kind == STok.IDENT && peek (1).kind == STok.OP && peek (1).text == ":=") {
                var t = next ();
                next ();
                var named = new SNode (SN.NAMED, t.line);
                named.name = t.low;
                named.a = parse_expr ();
                return named;
            }
            if (is_kw ("byval")) next ();
            return parse_expr ();
        }

        private SNode parse_expr_from (SNode left) throws ScriptError {
            var n = left;
            while (true) {
                var t = peek ();
                if (t.kind == STok.OP && (t.text == "+" || t.text == "-" || t.text == "*" || t.text == "/" || t.text == "\\" || t.text == "^" || t.text == "&" || t.text == "=" || t.text == "<>" || t.text == "<" || t.text == ">" || t.text == "<=" || t.text == ">=")) {
                    next ();
                    n = bin (t.text, n, parse_concat (), t.line);
                    continue;
                }
                if (t.kind == STok.IDENT && (t.low == "and" || t.low == "or" || t.low == "mod" || t.low == "xor" || t.low == "is" || t.low == "like")) {
                    next ();
                    n = bin (t.low, n, parse_compare (), t.line);
                    continue;
                }
                break;
            }
            return n;
        }

        private SNode single_line_block (int line) throws ScriptError {
            var b = new SNode (SN.BLOCK, line);
            SNode[] stmts = {};
            while (true) {
                bool colon_before = false;
                stmts += parse_stmt_inline (out colon_before);
                if (!colon_before || is_kw ("else") || peek ().kind == STok.END) break;
                if (peek ().kind == STok.NL) break;
            }
            b.args = stmts;
            return b;
        }

        private SNode parse_stmt_inline (out bool continued) throws ScriptError {
            int before = pos;
            var s = parse_stmt ();
            continued = pos > before && pos - 1 < toks.length && toks[pos - 1].kind == STok.NL && toks[pos - 1].colon;
            return s;
        }

        private SNode parse_if () throws ScriptError {
            int line = next ().line;
            var node = new SNode (SN.IF, line);
            node.a = parse_expr ();
            expect_kw ("then");
            if (peek ().kind != STok.NL || peek ().colon) {
                if (peek ().kind == STok.NL && peek ().colon) next ();
                node.body = single_line_block (line);
                if (is_kw ("else")) {
                    next ();
                    node.other = single_line_block (line);
                }
                return node;
            }
            end_stmt ();
            return finish_if (node);
        }

        private SNode finish_if (SNode node) throws ScriptError {
            node.body = parse_block ({ "elseif", "else", "end if" });
            if (is_kw ("elseif")) {
                int line = next ().line;
                var nested = new SNode (SN.IF, line);
                nested.a = parse_expr ();
                expect_kw ("then");
                end_stmt ();
                node.other = finish_if (nested);
                return node;
            }
            if (is_kw ("else")) {
                next ();
                if (is_kw ("if")) {
                    next ();
                    var nested = new SNode (SN.IF, peek ().line);
                    nested.a = parse_expr ();
                    expect_kw ("then");
                    end_stmt ();
                    node.other = finish_if (nested);
                    return node;
                }
                end_stmt ();
                node.other = parse_block ({ "end if" });
            }
            expect_kw ("end");
            expect_kw ("if");
            end_stmt ();
            return node;
        }

        private void end_next () throws ScriptError {
            next ();
            if (peek ().kind == STok.IDENT) {
                next ();
                if (is_op (",")) {
                    toks[pos] = new SToken (STok.IDENT, "next", toks[pos].line);
                    return;
                }
            }
            end_stmt ();
        }

        private SNode parse_for () throws ScriptError {
            int line = next ().line;
            if (is_kw ("each")) {
                next ();
                var fe = new SNode (SN.FOREACH, line);
                fe.name = next ().text;
                expect_kw ("in");
                fe.a = parse_expr ();
                end_stmt ();
                fe.body = parse_block ({ "next" });
                end_next ();
                return fe;
            }
            var f = new SNode (SN.FOR, line);
            var nt = next ();
            if (nt.kind != STok.IDENT) fail (_("expected a variable"));
            f.name = nt.text;
            expect_op ("=");
            f.a = parse_expr ();
            expect_kw ("to");
            f.b = parse_expr ();
            if (is_kw ("step")) {
                next ();
                f.c = parse_expr ();
            }
            end_stmt ();
            f.body = parse_block ({ "next" });
            end_next ();
            return f;
        }

        private SNode parse_do () throws ScriptError {
            int line = next ().line;
            var d = new SNode (SN.DO, line);
            if (is_kw ("while") || is_kw ("until")) {
                d.until = next ().low == "until";
                d.a = parse_expr ();
            }
            end_stmt ();
            d.body = parse_block ({ "loop" });
            next ();
            if (is_kw ("while") || is_kw ("until")) {
                d.until = next ().low == "until";
                d.post = true;
                d.a = parse_expr ();
            }
            end_stmt ();
            return d;
        }

        private SNode parse_select () throws ScriptError {
            int line = next ().line;
            expect_kw ("case");
            var s = new SNode (SN.SELECT, line);
            s.a = parse_expr ();
            end_stmt ();
            skip_nl ();
            SNode[] cases = {};
            while (is_kw ("case")) {
                next ();
                var cn = new SNode (SN.BLOCK, peek ().line);
                if (is_kw ("else")) {
                    next ();
                    cn.flag = true;
                } else {
                    SNode[] vals = {};
                    while (true) {
                        if (is_kw ("is")) {
                            next ();
                            var op = next ();
                            var cmp = new SNode (SN.BINARY, op.line);
                            cmp.name = op.text;
                            cmp.b = parse_expr ();
                            vals += cmp;
                        } else {
                            var v = parse_expr ();
                            if (is_kw ("to")) {
                                next ();
                                var rng = new SNode (SN.BINARY, v.line);
                                rng.name = "to";
                                rng.a = v;
                                rng.b = parse_expr ();
                                vals += rng;
                            } else {
                                vals += v;
                            }
                        }
                        if (!is_op (",")) break;
                        next ();
                    }
                    cn.args = vals;
                }
                if (peek ().kind == STok.NL) next ();
                cn.body = parse_block ({ "case", "end select" });
                cases += cn;
            }
            expect_kw ("end");
            expect_kw ("select");
            end_stmt ();
            s.args = cases;
            return s;
        }

        private SNode parse_expr () throws ScriptError {
            return parse_imp ();
        }

        private SNode bin (string op, SNode l, SNode r, int line) {
            var b = new SNode (SN.BINARY, line);
            b.name = op;
            b.a = l;
            b.b = r;
            return b;
        }

        private SNode parse_imp () throws ScriptError {
            var l = parse_or ();
            while (is_kw ("imp") || is_kw ("eqv")) {
                var t = next ();
                l = bin (t.low, l, parse_or (), t.line);
            }
            return l;
        }

        private SNode parse_or () throws ScriptError {
            var l = parse_and ();
            while (is_kw ("or") || is_kw ("xor") || is_kw ("orelse")) {
                var t = next ();
                l = bin (t.low == "orelse" ? "or" : t.low, l, parse_and (), t.line);
            }
            return l;
        }

        private SNode parse_and () throws ScriptError {
            var l = parse_not ();
            while (is_kw ("and") || is_kw ("andalso")) {
                var t = next ();
                l = bin ("and", l, parse_not (), t.line);
            }
            return l;
        }

        private SNode parse_not () throws ScriptError {
            if (is_kw ("not")) {
                var t = next ();
                var u = new SNode (SN.UNARY, t.line);
                u.name = "not";
                u.a = parse_not ();
                return u;
            }
            return parse_compare ();
        }

        private SNode parse_compare () throws ScriptError {
            var l = parse_concat ();
            while (is_op ("=") || is_op ("<>") || is_op ("<") || is_op (">") || is_op ("<=") || is_op (">=") || is_kw ("like") || is_kw ("is")) {
                var t = next ();
                l = bin (t.low, l, parse_concat (), t.line);
            }
            return l;
        }

        private SNode parse_concat () throws ScriptError {
            var l = parse_add ();
            while (is_op ("&")) {
                var t = next ();
                l = bin ("&", l, parse_add (), t.line);
            }
            return l;
        }

        private SNode parse_add () throws ScriptError {
            var l = parse_mod ();
            while (is_op ("+") || is_op ("-")) {
                var t = next ();
                l = bin (t.text, l, parse_mod (), t.line);
            }
            return l;
        }

        private SNode parse_mod () throws ScriptError {
            var l = parse_idiv ();
            while (is_kw ("mod")) {
                var t = next ();
                l = bin ("mod", l, parse_idiv (), t.line);
            }
            return l;
        }

        private SNode parse_idiv () throws ScriptError {
            var l = parse_mul ();
            while (is_op ("\\")) {
                var t = next ();
                l = bin ("\\", l, parse_mul (), t.line);
            }
            return l;
        }

        private SNode parse_mul () throws ScriptError {
            var l = parse_unary ();
            while (is_op ("*") || is_op ("/")) {
                var t = next ();
                l = bin (t.text, l, parse_unary (), t.line);
            }
            return l;
        }

        private SNode parse_unary () throws ScriptError {
            if (is_op ("-") || is_op ("+")) {
                var t = next ();
                var u = new SNode (SN.UNARY, t.line);
                u.name = t.text;
                u.a = parse_unary ();
                return u;
            }
            return parse_pow ();
        }

        private SNode parse_pow () throws ScriptError {
            var l = parse_postfix ();
            while (is_op ("^")) {
                var t = next ();
                SNode r;
                if (is_op ("-") || is_op ("+")) {
                    var ut = next ();
                    r = new SNode (SN.UNARY, ut.line);
                    r.name = ut.text;
                    r.a = parse_postfix ();
                } else {
                    r = parse_postfix ();
                }
                l = bin ("^", l, r, t.line);
            }
            return l;
        }

        private SNode[] parse_args () throws ScriptError {
            SNode[] args = {};
            expect_op ("(");
            while (!is_op (")")) {
                if (is_op (",")) {
                    args += missing_arg ();
                    next ();
                    if (is_op (")")) args += missing_arg ();
                    continue;
                }
                args += parse_arg ();
                if (is_op (",")) {
                    next ();
                    if (is_op (")")) args += missing_arg ();
                } else if (!is_op (")")) {
                    fail (_("expected , or )"));
                }
            }
            next ();
            return args;
        }

        private SNode parse_postfix () throws ScriptError {
            var n = parse_primary ();
            while (true) {
                if (is_op ("(")) {
                    var c = new SNode (SN.CALL, peek ().line);
                    c.a = n;
                    c.args = parse_args ();
                    c.parens = true;
                    n = c;
                    continue;
                }
                if (is_op (".") || is_op ("!")) {
                    bool bang = next ().text == "!";
                    var nt = next ();
                    if (nt.kind != STok.IDENT && nt.kind != STok.NUM) fail (_("expected a member name"));
                    if (nt.bracket) {
                        var bc = new SNode (SN.CALL, nt.line);
                        var bm = new SNode (SN.MEMBER, nt.line);
                        bm.a = n;
                        bm.name = "evaluate";
                        bc.a = bm;
                        var bs = new SNode (SN.STR, nt.line);
                        bs.name = nt.text;
                        bc.args = { bs };
                        n = bc;
                        continue;
                    }
                    if (bang) {
                        var c = new SNode (SN.CALL, nt.line);
                        c.a = n;
                        var key = new SNode (SN.STR, nt.line);
                        key.name = nt.text;
                        c.args = { key };
                        n = c;
                        continue;
                    }
                    var m = new SNode (SN.MEMBER, nt.line);
                    m.a = n;
                    m.name = nt.text;
                    n = m;
                    continue;
                }
                break;
            }
            return n;
        }

        private SNode parse_primary () throws ScriptError {
            var t = next ();
            switch (t.kind) {
                case STok.NUM:
                    var nn = new SNode (t.date ? SN.DATE : SN.NUM, t.line);
                    nn.num = t.num;
                    return nn;
                case STok.STR:
                    var sn = new SNode (SN.STR, t.line);
                    sn.name = t.text;
                    return sn;
                case STok.IDENT:
                    if (t.bracket) {
                        var bc = new SNode (SN.CALL, t.line);
                        var callee = new SNode (SN.IDENT, t.line);
                        callee.name = "evaluate";
                        bc.a = callee;
                        var bs = new SNode (SN.STR, t.line);
                        bs.name = t.text;
                        bc.args = { bs };
                        return bc;
                    }
                    if (t.low == "true" || t.low == "false") {
                        var bn = new SNode (SN.BOOL, t.line);
                        bn.num = t.low == "true" ? 1 : 0;
                        return bn;
                    }
                    if (t.low == "nothing") return new SNode (SN.NOTHING, t.line);
                    if (t.low == "empty" || t.low == "null") return new SNode (SN.EMPTYV, t.line);
                    if (t.low == "new") {
                        var nw = new SNode (SN.NEW, t.line);
                        nw.name = parse_type ();
                        return nw;
                    }
                    if (t.low == "addressof") {
                        next ();
                        var f = new SNode (SN.FORBID, t.line);
                        f.name = _("AddressOf is not supported");
                        return f;
                    }
                    if (t.low == "typeof") {
                        var obj = parse_postfix ();
                        expect_kw ("is");
                        var tt = new SNode (SN.CALL, t.line);
                        var callee = new SNode (SN.IDENT, t.line);
                        callee.name = "__typeof";
                        tt.a = callee;
                        var tn = new SNode (SN.STR, t.line);
                        tn.name = parse_type ();
                        tt.args = { obj, tn };
                        return tt;
                    }
                    if (enums.has_key (t.low)) {
                        var en = new SNode (SN.NUM, t.line);
                        en.num = enums[t.low];
                        return en;
                    }
                    var id = new SNode (SN.IDENT, t.line);
                    id.name = t.text;
                    return id;
                case STok.OP:
                    if (t.text == "(") {
                        var e = parse_expr ();
                        expect_op (")");
                        return e;
                    }
                    if (t.text == "." || t.text == "!") {
                        var nt = next ();
                        var with_ref = new SNode (SN.IDENT, nt.line);
                        with_ref.name = "__with";
                        if (t.text == "!") {
                            var c = new SNode (SN.CALL, nt.line);
                            c.a = with_ref;
                            var key = new SNode (SN.STR, nt.line);
                            key.name = nt.text;
                            c.args = { key };
                            return c;
                        }
                        var m = new SNode (SN.MEMBER, nt.line);
                        m.a = with_ref;
                        m.name = nt.text;
                        return m;
                    }
                    break;
                default:
                    break;
            }
            pos--;
            fail (_("unexpected token"));
            return new SNode (SN.NOTHING, t.line);
        }
    }

    public errordomain ExitError {
        EXIT
    }
}
