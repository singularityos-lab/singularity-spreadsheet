namespace Singularity.Apps.Spreadsheet {

    public enum NodeKind {
        NUMBER,
        TEXT,
        BOOL,
        ERROR,
        REF,
        NAME,
        UNARY,
        BINARY,
        PERCENT,
        CALL,
        ARRAY,
        MISSING,
        APPLY,
        VALUE,
        STRUCT
    }

    public class RefPart {
        public int row;
        public int col;
        public bool abs_row;
        public bool abs_col;

        public RefPart (int row, int col, bool abs_row, bool abs_col) {
            this.row = row;
            this.col = col;
            this.abs_row = abs_row;
            this.abs_col = abs_col;
        }

        public RefPart copy () {
            return new RefPart (row, col, abs_row, abs_col);
        }
    }

    public class Node {
        public NodeKind kind;
        public double number;
        public string text = "";
        public ErrorKind error;
        public string op = "";
        public Node[] args = {};
        public Value[,]? array;

        public Sheet? sheet;
        public string sheet_name = "";
        public bool bad_sheet;
        public RefPart? a;
        public RefPart? b;
        public bool whole_cols;
        public bool whole_rows;
        public bool spill;
        public Sheet? sheet2;
        public string sheet_name2 = "";
        public Value? value;
        public StructRef? sref;

        public Node (NodeKind kind) {
            this.kind = kind;
        }

        public bool is_area () {
            return b != null;
        }

        public Area to_area (Sheet? own) {
            Sheet? s = sheet ?? own;
            if (b == null) return new Area.cell (s, a.row, a.col);
            return new Area (s, a.row, a.col, b.row, b.col);
        }

        public Node copy () {
            var n = new Node (kind);
            n.number = number;
            n.text = text;
            n.error = error;
            n.op = op;
            n.array = array;
            n.sheet = sheet;
            n.sheet_name = sheet_name;
            n.bad_sheet = bad_sheet;
            n.a = a != null ? a.copy () : null;
            n.b = b != null ? b.copy () : null;
            n.whole_cols = whole_cols;
            n.whole_rows = whole_rows;
            n.spill = spill;
            n.sheet2 = sheet2;
            n.sheet_name2 = sheet_name2;
            n.value = value;
            n.sref = sref != null ? sref.copy () : null;
            Node[] cargs = {};
            foreach (var c in args) cargs += c.copy ();
            n.args = cargs;
            return n;
        }

        public bool is_3d () {
            return sheet2 != null || sheet_name2 != "";
        }

        public void @foreach_ref (RefVisitor visit) {
            if (kind == NodeKind.REF) visit (this);
            foreach (var c in args) c.foreach_ref (visit);
        }

        public bool has_call (string name) {
            if (kind == NodeKind.CALL && text == name) return true;
            foreach (var c in args) if (c.has_call (name)) return true;
            return false;
        }
    }

    public delegate void RefVisitor (Node n);

    public errordomain FormulaError {
        SYNTAX
    }

    private enum Tok {
        NUMBER,
        TEXT,
        ERROR,
        REF,
        IDENT,
        OP,
        LPAREN,
        RPAREN,
        LBRACE,
        RBRACE,
        STRUCT,
        SEP,
        ROWSEP,
        END
    }

    private class FormulaToken {
        public Tok kind;
        public string text;
        public double number;

        public FormulaToken (Tok kind, string text) {
            this.kind = kind;
            this.text = text;
        }
    }

    public class Formula {
        private FormulaToken[] toks = {};
        private int pos = 0;
        private Workbook? book;
        private Sheet? own;
        private int brace_depth = 0;

        public static Node parse (string text, Workbook? book, Sheet? own) throws FormulaError {
            var f = new Formula ();
            f.book = book;
            f.own = own;
            string src = text.has_prefix ("=") ? text.substring (1) : text;
            f.tokenize (src);
            var node = f.parse_compare ();
            if (f.peek ().kind != Tok.END) throw new FormulaError.SYNTAX ("unexpected %s", f.peek ().text);
            return node;
        }

        private FormulaToken peek () {
            return toks[pos];
        }

        private FormulaToken next () {
            return toks[pos++];
        }

        private bool is_op (string op) {
            return toks[pos].kind == Tok.OP && toks[pos].text == op;
        }

        private void tokenize (string s) throws FormulaError {
            int i = 0;
            int n = s.length;
            while (i < n) {
                char c = s[i];
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                    i++;
                    continue;
                }
                if (c == '"') {
                    var sb = new StringBuilder ();
                    i++;
                    while (true) {
                        if (i >= n) throw new FormulaError.SYNTAX ("unterminated string");
                        if (s[i] == '"') {
                            if (i + 1 < n && s[i + 1] == '"') {
                                sb.append_c ('"');
                                i += 2;
                                continue;
                            }
                            i++;
                            break;
                        }
                        sb.append_c (s[i]);
                        i++;
                    }
                    toks += new FormulaToken (Tok.TEXT, sb.str);
                    continue;
                }
                if (c == '#' && toks.length > 0 && (toks[toks.length - 1].kind == Tok.REF || toks[toks.length - 1].kind == Tok.RPAREN) && !(i + 1 < n && (s[i + 1].isalpha () || s[i + 1] == '/'))) {
                    toks += new FormulaToken (Tok.OP, "#");
                    i++;
                    continue;
                }
                if (c == '[') {
                    int end = scan_struct (s, i);
                    if (end < 0) throw new FormulaError.SYNTAX ("bad structured reference");
                    toks += new FormulaToken (Tok.STRUCT, s.substring (i, end - i));
                    i = end;
                    continue;
                }
                if (c == '#') {
                    string[] errs = { "#NULL!", "#DIV/0!", "#VALUE!", "#REF!", "#NAME?", "#NUM!", "#N/A", "#CIRC!", "#SPILL!", "#CALC!", "#GETTING_DATA" };
                    bool found = false;
                    foreach (string e in errs) {
                        if (s.substring (i).up ().has_prefix (e)) {
                            toks += new FormulaToken (Tok.ERROR, e);
                            i += e.length;
                            found = true;
                            break;
                        }
                    }
                    if (!found) throw new FormulaError.SYNTAX ("bad error literal");
                    continue;
                }
                if (c.isdigit () || (c == '.' && i + 1 < n && s[i + 1].isdigit ())) {
                    int start = i;
                    while (i < n && s[i].isdigit ()) i++;
                    if (i < n && s[i] == ':' && !prev_is_value ()) {
                        int j = i + 1;
                        if (j < n && s[j] == '$') j++;
                        int k = j;
                        while (k < n && s[k].isdigit ()) k++;
                        if (k > j) {
                            toks += new FormulaToken (Tok.REF, s.substring (start, k - start));
                            i = k;
                            continue;
                        }
                    }
                    if (i < n && s[i] == '.') {
                        i++;
                        while (i < n && s[i].isdigit ()) i++;
                    }
                    if (i < n && (s[i] == 'e' || s[i] == 'E')) {
                        int j = i + 1;
                        if (j < n && (s[j] == '+' || s[j] == '-')) j++;
                        if (j < n && s[j].isdigit ()) {
                            i = j;
                            while (i < n && s[i].isdigit ()) i++;
                        }
                    }
                    var t = new FormulaToken (Tok.NUMBER, s.substring (start, i - start));
                    t.number = double.parse (t.text);
                    toks += t;
                    continue;
                }
                if (c == '\'' ) {
                    int j = i + 1;
                    var sb = new StringBuilder ();
                    while (true) {
                        if (j >= n) throw new FormulaError.SYNTAX ("unterminated sheet name");
                        if (s[j] == '\'') {
                            if (j + 1 < n && s[j + 1] == '\'') {
                                sb.append_c ('\'');
                                j += 2;
                                continue;
                            }
                            j++;
                            break;
                        }
                        sb.append_c (s[j]);
                        j++;
                    }
                    if (j < n && s[j] == ':' && !sb.str.contains (":")) {
                        int w = j + 1;
                        while (w < n && (s[w].isalnum () || s[w] == '_' || s[w] == '.' || (uchar) s[w] >= 0x80)) w++;
                        if (w < n && s[w] == '!' && w > j + 1) {
                            sb.append (":");
                            sb.append (s.substring (j + 1, w - j - 1));
                            j = w;
                        }
                    }
                    if (j >= n || s[j] != '!') throw new FormulaError.SYNTAX ("sheet name without reference");
                    j++;
                    int end = scan_ref (s, j);
                    if (end == j) throw new FormulaError.SYNTAX ("missing reference");
                    toks += new FormulaToken (Tok.REF, "'" + sb.str.replace ("'", "''") + "'!" + s.substring (j, end - j));
                    i = end;
                    continue;
                }
                if (c.isalpha () || c == '_' || c == '$' || c == '\\' || (uchar) c >= 0x80) {
                    int start = i;
                    while (i < n && (s[i].isalnum () || s[i] == '_' || s[i] == '.' || s[i] == '$' || (uchar) s[i] >= 0x80)) i++;
                    string word = s.substring (start, i - start);
                    if (i < n && s[i] == ':' && i + 1 < n && (s[i + 1].isalpha () || s[i + 1] == '_' || (uchar) s[i + 1] >= 0x80)) {
                        int w = i + 1;
                        while (w < n && (s[w].isalnum () || s[w] == '_' || s[w] == '.' || (uchar) s[w] >= 0x80)) w++;
                        if (w < n && s[w] == '!') {
                            int end3 = scan_ref (s, w + 1);
                            if (end3 > w + 1) {
                                toks += new FormulaToken (Tok.REF, s.substring (start, w - start) + "!" + s.substring (w + 1, end3 - w - 1));
                                i = end3;
                                continue;
                            }
                        }
                    }
                    if (i < n && s[i] == '[') {
                        int end2 = scan_struct (s, i);
                        if (end2 < 0) throw new FormulaError.SYNTAX ("bad structured reference");
                        toks += new FormulaToken (Tok.STRUCT, s.substring (start, end2 - start));
                        i = end2;
                        continue;
                    }
                    if (i < n && s[i] == '!') {
                        int j = i + 1;
                        int end = scan_ref (s, j);
                        if (end == j) throw new FormulaError.SYNTAX ("missing reference");
                        toks += new FormulaToken (Tok.REF, word + "!" + s.substring (j, end - j));
                        i = end;
                        continue;
                    }
                    int end = scan_ref (s, start);
                    if (end > start && end >= i && !(end < n && s[end] == '(')) {
                        toks += new FormulaToken (Tok.REF, s.substring (start, end - start));
                        i = end;
                        continue;
                    }
                    toks += new FormulaToken (Tok.IDENT, word);
                    continue;
                }
                switch (c) {
                    case '(':
                        toks += new FormulaToken (Tok.LPAREN, "(");
                        i++;
                        continue;
                    case ')':
                        toks += new FormulaToken (Tok.RPAREN, ")");
                        i++;
                        continue;
                    case '{':
                        brace_depth++;
                        toks += new FormulaToken (Tok.LBRACE, "{");
                        i++;
                        continue;
                    case '}':
                        brace_depth--;
                        toks += new FormulaToken (Tok.RBRACE, "}");
                        i++;
                        continue;
                    case ',':
                        toks += new FormulaToken (Tok.SEP, ",");
                        i++;
                        continue;
                    case ';':
                        toks += new FormulaToken (brace_depth > 0 ? Tok.ROWSEP : Tok.SEP, ";");
                        i++;
                        continue;
                }
                if (i + 1 < n) {
                    string two = s.substring (i, 2);
                    if (two == "<>" || two == "<=" || two == ">=") {
                        toks += new FormulaToken (Tok.OP, two);
                        i += 2;
                        continue;
                    }
                }
                if ("+-*/^&=<>%:@".index_of_char (c) >= 0) {
                    toks += new FormulaToken (Tok.OP, c.to_string ());
                    i++;
                    continue;
                }
                throw new FormulaError.SYNTAX ("unexpected character %c", c);
            }
            toks += new FormulaToken (Tok.END, "");
        }

        private bool prev_is_value () {
            if (toks.length == 0) return false;
            var t = toks[toks.length - 1];
            return t.kind == Tok.NUMBER || t.kind == Tok.REF || t.kind == Tok.RPAREN || t.kind == Tok.TEXT;
        }

        private static int scan_part (string s, int i, out bool is_col, out bool is_row) {
            is_col = is_row = false;
            int n = s.length;
            int j = i;
            if (j < n && s[j] == '$') j++;
            int ls = j;
            while (j < n && s[j].isalpha ()) j++;
            int letters = j - ls;
            if (letters > 0 && letters <= 3) {
                int k = j;
                if (k < n && s[k] == '$') k++;
                int ds = k;
                while (k < n && s[k].isdigit ()) k++;
                if (k > ds) {
                    if (k < n && (s[k].isalnum () || s[k] == '_' || s[k] == '.')) return i;
                    return k;
                }
                if (j < n && (s[j].isalnum () || s[j] == '_' || s[j] == '.' || s[j] == '(')) return i;
                is_col = true;
                return j;
            }
            if (letters == 0) {
                int k = j;
                while (k < n && s[k].isdigit ()) k++;
                if (k > j) {
                    is_row = true;
                    return k;
                }
            }
            return i;
        }

        private static int scan_struct (string s, int i) {
            int depth = 0;
            int n = s.length;
            for (int j = i; j < n; j++) {
                if (s[j] == '\'' && j + 1 < n) {
                    j++;
                    continue;
                }
                if (s[j] == '[') depth++;
                else if (s[j] == ']') {
                    depth--;
                    if (depth == 0) return j + 1;
                }
            }
            return -1;
        }

        private static int scan_ref (string s, int i) {
            bool c1, r1, c2, r2;
            int e1 = scan_part (s, i, out c1, out r1);
            if (e1 == i) return i;
            if (e1 < s.length && s[e1] == ':') {
                int e2 = scan_part (s, e1 + 1, out c2, out r2);
                if (e2 > e1 + 1 && c1 == c2 && r1 == r2) return e2;
            }
            if (c1 || r1) return i;
            return e1;
        }

        private Node parse_compare () throws FormulaError {
            var left = parse_concat ();
            while (is_op ("=") || is_op ("<>") || is_op ("<") || is_op (">") || is_op ("<=") || is_op (">=")) {
                string op = next ().text;
                left = binary (op, left, parse_concat ());
            }
            return left;
        }

        private Node parse_concat () throws FormulaError {
            var left = parse_additive ();
            while (is_op ("&")) {
                next ();
                left = binary ("&", left, parse_additive ());
            }
            return left;
        }

        private Node parse_additive () throws FormulaError {
            var left = parse_term ();
            while (is_op ("+") || is_op ("-")) {
                string op = next ().text;
                left = binary (op, left, parse_term ());
            }
            return left;
        }

        private Node parse_term () throws FormulaError {
            var left = parse_power ();
            while (is_op ("*") || is_op ("/")) {
                string op = next ().text;
                left = binary (op, left, parse_power ());
            }
            return left;
        }

        private Node parse_power () throws FormulaError {
            var left = parse_percent ();
            while (is_op ("^")) {
                next ();
                left = binary ("^", left, parse_percent ());
            }
            return left;
        }

        private Node parse_percent () throws FormulaError {
            var node = parse_unary ();
            while (is_op ("%")) {
                next ();
                var p = new Node (NodeKind.PERCENT);
                p.args = { node };
                node = p;
            }
            return node;
        }

        private Node parse_unary () throws FormulaError {
            if (is_op ("@")) {
                next ();
                var inner = parse_unary ();
                var at = new Node (NodeKind.UNARY);
                at.op = "@";
                at.args = { inner };
                return at;
            }
            if (is_op ("-") || is_op ("+")) {
                string op = next ().text;
                var operand = parse_unary ();
                if (op == "+") return operand;
                var u = new Node (NodeKind.UNARY);
                u.op = "-";
                u.args = { operand };
                return u;
            }
            return parse_range ();
        }

        private Node parse_range () throws FormulaError {
            var left = parse_postfix ();
            while (is_op (":")) {
                next ();
                left = binary (":", left, parse_postfix ());
            }
            return left;
        }

        private Node parse_postfix () throws FormulaError {
            var node = parse_primary ();
            while (true) {
                if (is_op ("#") && node.kind == NodeKind.REF) {
                    next ();
                    node.spill = true;
                    continue;
                }
                if (peek ().kind == Tok.LPAREN && (node.kind == NodeKind.CALL || node.kind == NodeKind.APPLY)) {
                    next ();
                    var app = new Node (NodeKind.APPLY);
                    Node[] args = { node };
                    if (peek ().kind == Tok.RPAREN) {
                        next ();
                    } else {
                        while (true) {
                            if (peek ().kind == Tok.SEP || peek ().kind == Tok.RPAREN) args += new Node (NodeKind.MISSING);
                            else args += parse_compare ();
                            var sep = next ();
                            if (sep.kind == Tok.RPAREN) break;
                            if (sep.kind != Tok.SEP) throw new FormulaError.SYNTAX ("expected , or )");
                        }
                    }
                    app.args = args;
                    node = app;
                    continue;
                }
                break;
            }
            return node;
        }

        private static Node binary (string op, Node l, Node r) {
            var b = new Node (NodeKind.BINARY);
            b.op = op;
            b.args = { l, r };
            return b;
        }

        private Node parse_primary () throws FormulaError {
            var t = next ();
            switch (t.kind) {
                case Tok.NUMBER:
                    var n = new Node (NodeKind.NUMBER);
                    n.number = t.number;
                    return n;
                case Tok.TEXT:
                    var s = new Node (NodeKind.TEXT);
                    s.text = t.text;
                    return s;
                case Tok.ERROR:
                    var e = new Node (NodeKind.ERROR);
                    e.error = ErrorKind.parse (t.text);
                    return e;
                case Tok.REF:
                    return make_ref (t.text);
                case Tok.STRUCT:
                    var st = new Node (NodeKind.STRUCT);
                    st.sref = StructRef.parse (t.text);
                    if (st.sref == null) throw new FormulaError.SYNTAX ("bad structured reference");
                    return st;
                case Tok.LPAREN:
                    var inner = parse_compare ();
                    if (next ().kind != Tok.RPAREN) throw new FormulaError.SYNTAX ("missing )");
                    return inner;
                case Tok.LBRACE:
                    return parse_array ();
                case Tok.IDENT:
                    string up = t.text.up ();
                    if (peek ().kind == Tok.LPAREN) {
                        next ();
                        var call = new Node (NodeKind.CALL);
                        call.text = up.has_prefix ("_XLFN.") ? up.substring (6) : up;
                        if (call.text.has_prefix ("_XLWS.")) call.text = call.text.substring (6);
                        Node[] args = {};
                        if (peek ().kind == Tok.RPAREN) {
                            next ();
                            call.args = args;
                            return call;
                        }
                        while (true) {
                            if (peek ().kind == Tok.SEP || peek ().kind == Tok.RPAREN) {
                                args += new Node (NodeKind.MISSING);
                            } else {
                                args += parse_compare ();
                            }
                            var sep = next ();
                            if (sep.kind == Tok.RPAREN) break;
                            if (sep.kind != Tok.SEP) throw new FormulaError.SYNTAX ("expected , or )");
                        }
                        call.args = args;
                        if (call.text == "ANCHORARRAY" && args.length == 1 && args[0].kind == NodeKind.REF) {
                            args[0].spill = true;
                            return args[0];
                        }
                        if (call.text == "SINGLE" && args.length == 1) {
                            var at = new Node (NodeKind.UNARY);
                            at.op = "@";
                            at.args = { args[0] };
                            return at;
                        }
                        return call;
                    }
                    if (up == "TRUE" || up == "FALSE") {
                        var bnode = new Node (NodeKind.BOOL);
                        bnode.number = up == "TRUE" ? 1 : 0;
                        return bnode;
                    }
                    var name = new Node (NodeKind.NAME);
                    name.text = up.has_prefix ("_XLPM.") ? t.text.substring (6) : t.text;
                    return name;
                default:
                    throw new FormulaError.SYNTAX ("unexpected %s", t.text == "" ? "end" : t.text);
            }
        }

        private Node parse_array () throws FormulaError {
            var rows = new Gee.ArrayList<Gee.ArrayList<Value>> ();
            var row = new Gee.ArrayList<Value> ();
            while (true) {
                bool neg = false;
                if (is_op ("-")) {
                    next ();
                    neg = true;
                }
                var t = next ();
                switch (t.kind) {
                    case Tok.NUMBER: row.add (Value.num (neg ? -t.number : t.number)); break;
                    case Tok.TEXT: row.add (Value.str (t.text)); break;
                    case Tok.ERROR: row.add (Value.err (ErrorKind.parse (t.text))); break;
                    case Tok.IDENT:
                        string up = t.text.up ();
                        if (up != "TRUE" && up != "FALSE") throw new FormulaError.SYNTAX ("bad array item");
                        row.add (Value.boolean (up == "TRUE"));
                        break;
                    default:
                        throw new FormulaError.SYNTAX ("bad array item");
                }
                var sep = next ();
                if (sep.kind == Tok.SEP) continue;
                rows.add (row);
                if (sep.kind == Tok.ROWSEP) {
                    row = new Gee.ArrayList<Value> ();
                    continue;
                }
                if (sep.kind == Tok.RBRACE) break;
                throw new FormulaError.SYNTAX ("bad array");
            }
            int cols = rows[0].size;
            foreach (var r in rows) if (r.size != cols) throw new FormulaError.SYNTAX ("ragged array");
            var m = new Value[rows.size, cols];
            for (int i = 0; i < rows.size; i++) for (int j = 0; j < cols; j++) m[i, j] = rows[i][j];
            var node = new Node (NodeKind.ARRAY);
            node.array = m;
            return node;
        }

        private Node make_ref (string text) throws FormulaError {
            var node = new Node (NodeKind.REF);
            string r = text;
            int bang = r.last_index_of ("!");
            if (bang > 0) {
                string sname = r.substring (0, bang);
                if (sname.has_prefix ("'")) sname = sname.substring (1, sname.length - 2).replace ("''", "'");
                int sc = sname.index_of (":");
                if (sc > 0) {
                    node.sheet_name2 = sname.substring (sc + 1);
                    sname = sname.substring (0, sc);
                    node.sheet2 = book != null ? book.find_sheet (node.sheet_name2) : null;
                }
                node.sheet_name = sname;
                node.sheet = book != null ? book.find_sheet (sname) : null;
                node.bad_sheet = book != null && (node.sheet == null || (node.sheet_name2 != "" && node.sheet2 == null));
                r = r.substring (bang + 1);
            }
            int colon = r.index_of (":");
            string p1 = colon >= 0 ? r.substring (0, colon) : r;
            string p2 = colon >= 0 ? r.substring (colon + 1) : "";
            int row, col;
            bool ar, ac;
            if (Address.parse_cell (p1, out row, out col, out ar, out ac)) {
                node.a = new RefPart (row, col, ar, ac);
                if (colon >= 0) {
                    if (!Address.parse_cell (p2, out row, out col, out ar, out ac)) throw new FormulaError.SYNTAX ("bad range");
                    node.b = new RefPart (row, col, ar, ac);
                    normalize (node);
                }
                return node;
            }
            if (colon < 0) throw new FormulaError.SYNTAX ("bad reference");
            string q1 = p1.replace ("$", "");
            string q2 = p2.replace ("$", "");
            int c1 = Address.column_index (q1);
            int c2 = Address.column_index (q2);
            if (c1 >= 0 && c2 >= 0 && q1.length > 0 && !q1[0].isdigit ()) {
                node.whole_cols = true;
                node.a = new RefPart (0, c1, true, p1.has_prefix ("$"));
                node.b = new RefPart (MAX_ROWS - 1, c2, true, p2.has_prefix ("$"));
                normalize (node);
                return node;
            }
            int64 r1 = int64.parse (q1);
            int64 r2 = int64.parse (q2);
            if (r1 < 1 || r2 < 1 || r1 > MAX_ROWS || r2 > MAX_ROWS) throw new FormulaError.SYNTAX ("bad row range");
            node.whole_rows = true;
            node.a = new RefPart ((int) r1 - 1, 0, p1.has_prefix ("$"), true);
            node.b = new RefPart ((int) r2 - 1, MAX_COLS - 1, p2.has_prefix ("$"), true);
            normalize (node);
            return node;
        }

        private static void normalize (Node node) {
            if (node.a.row > node.b.row) {
                int t = node.a.row;
                node.a.row = node.b.row;
                node.b.row = t;
                bool bt = node.a.abs_row;
                node.a.abs_row = node.b.abs_row;
                node.b.abs_row = bt;
            }
            if (node.a.col > node.b.col) {
                int t = node.a.col;
                node.a.col = node.b.col;
                node.b.col = t;
                bool bt = node.a.abs_col;
                node.a.abs_col = node.b.abs_col;
                node.b.abs_col = bt;
            }
        }

        public static string to_text (Node n, Sheet? own) {
            return "=" + render (n, own, 0);
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

        public static string render (Node n, Sheet? own, int parent) {
            switch (n.kind) {
                case NodeKind.NUMBER:
                    return Value.format_number_general_full (n.number);
                case NodeKind.TEXT:
                    return "\"" + n.text.replace ("\"", "\"\"") + "\"";
                case NodeKind.BOOL:
                    return n.number != 0 ? "TRUE" : "FALSE";
                case NodeKind.ERROR:
                    return n.error.to_string ();
                case NodeKind.MISSING:
                    return "";
                case NodeKind.NAME:
                    return n.text;
                case NodeKind.REF:
                    return ref_text (n, own);
                case NodeKind.PERCENT:
                    return render (n.args[0], own, 7) + "%";
                case NodeKind.UNARY:
                    return n.op + render (n.args[0], own, 6);
                case NodeKind.APPLY:
                    string[] aparts = {};
                    for (int i = 1; i < n.args.length; i++) aparts += render (n.args[i], own, 0);
                    return render (n.args[0], own, 9) + "(" + string.joinv (",", aparts) + ")";
                case NodeKind.VALUE:
                    return n.value != null ? literal_text (n.value) : "";
                case NodeKind.STRUCT:
                    return n.sref.to_string ();
                case NodeKind.BINARY:
                    int p = prec (n.op);
                    string l = render (n.args[0], own, p);
                    string r = render (n.args[1], own, p + (n.op == "^" ? 0 : 1));
                    string s = n.op == ":" ? l + ":" + r : l + n.op + r;
                    return p < parent ? "(" + s + ")" : s;
                case NodeKind.CALL:
                    string[] parts = {};
                    foreach (var a in n.args) parts += render (a, own, 0);
                    return n.text + "(" + string.joinv (",", parts) + ")";
                case NodeKind.ARRAY:
                    var sb = new StringBuilder ("{");
                    for (int i = 0; i < n.array.length[0]; i++) {
                        if (i > 0) sb.append (";");
                        for (int j = 0; j < n.array.length[1]; j++) {
                            if (j > 0) sb.append (",");
                            var v = n.array[i, j];
                            if (v.kind == ValueKind.TEXT) sb.append ("\"" + v.text.replace ("\"", "\"\"") + "\"");
                            else if (v.kind == ValueKind.NUMBER) sb.append (Value.format_number_general_full (v.number));
                            else sb.append (v.display ());
                        }
                    }
                    sb.append ("}");
                    return sb.str;
            }
            return "";
        }

        public static string literal_text (Value v) {
            switch (v.kind) {
                case ValueKind.TEXT: return "\"" + v.text.replace ("\"", "\"\"") + "\"";
                case ValueKind.NUMBER: return Value.format_number_general_full (v.number);
                case ValueKind.ARRAY:
                    var sb = new StringBuilder ("{");
                    for (int i = 0; i < v.array.length[0]; i++) {
                        if (i > 0) sb.append (";");
                        for (int j = 0; j < v.array.length[1]; j++) {
                            if (j > 0) sb.append (",");
                            sb.append (literal_text (v.array[i, j]));
                        }
                    }
                    sb.append ("}");
                    return sb.str;
                case ValueKind.RANGE: return v.area.to_string ();
                default: return v.display ();
            }
        }

        public static string sheet_prefix (Node n, Sheet? own) {
            string n1 = n.bad_sheet || n.sheet == null ? n.sheet_name : n.sheet.name;
            if (n.is_3d ()) {
                string n2 = n.sheet2 != null ? n.sheet2.name : n.sheet_name2;
                if (Address.quote_sheet (n1) == n1 && Address.quote_sheet (n2) == n2) return n1 + ":" + n2 + "!";
                return "'" + (n1 + ":" + n2).replace ("'", "''") + "'!";
            }
            if (n.bad_sheet) return Address.quote_sheet (n.sheet_name) + "!";
            if (n.sheet != null && n.sheet != own) return Address.quote_sheet (n.sheet.name) + "!";
            return "";
        }

        public static string ref_text (Node n, Sheet? own) {
            string prefix = sheet_prefix (n, own);
            if (n.spill && n.a != null) return prefix + Address.cell (n.a.row, n.a.col, n.a.abs_row, n.a.abs_col) + "#";
            if (n.a == null) return prefix + "#REF!";
            if (n.whole_cols) {
                return prefix + (n.a.abs_col ? "$" : "") + Address.column_name (n.a.col) + ":" + (n.b.abs_col ? "$" : "") + Address.column_name (n.b.col);
            }
            if (n.whole_rows) {
                return prefix + (n.a.abs_row ? "$" : "") + (n.a.row + 1).to_string () + ":" + (n.b.abs_row ? "$" : "") + (n.b.row + 1).to_string ();
            }
            string t = Address.cell (n.a.row, n.a.col, n.a.abs_row, n.a.abs_col);
            if (n.b != null) t += ":" + Address.cell (n.b.row, n.b.col, n.b.abs_row, n.b.abs_col);
            return prefix + t;
        }

        public static Node shifted (Node src, int drow, int dcol) {
            var n = src.copy ();
            n.foreach_ref ((r) => {
                if (r.a == null) return;
                bool bad = false;
                if (!r.whole_cols) {
                    if (!r.a.abs_row) r.a.row += drow;
                    if (r.b != null && !r.b.abs_row) r.b.row += drow;
                }
                if (!r.whole_rows) {
                    if (!r.a.abs_col) r.a.col += dcol;
                    if (r.b != null && !r.b.abs_col) r.b.col += dcol;
                }
                if (r.a.row < 0 || r.a.col < 0 || r.a.row >= MAX_ROWS || r.a.col >= MAX_COLS) bad = true;
                if (r.b != null && (r.b.row < 0 || r.b.col < 0 || r.b.row >= MAX_ROWS || r.b.col >= MAX_COLS)) bad = true;
                if (bad) {
                    r.a = null;
                    r.b = null;
                }
            });
            return n;
        }
    }
}
