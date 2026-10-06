namespace Singularity.Apps.Spreadsheet {

    public class AuditRef {
        public Sheet sheet;
        public int row;
        public int col;

        public AuditRef (Sheet sheet, int row, int col) {
            this.sheet = sheet;
            this.row = row;
            this.col = col;
        }

        public string label (Sheet? own) {
            string a = Address.cell (row, col);
            return own == sheet ? a : Address.quote_sheet (sheet.name) + "!" + a;
        }

        public bool same (AuditRef o) {
            return o.sheet == sheet && o.row == row && o.col == col;
        }
    }

    public class CellWatch {
        public Sheet sheet;
        public int row;
        public int col;

        public CellWatch (Sheet sheet, int row, int col) {
            this.sheet = sheet;
            this.row = row;
            this.col = col;
        }
    }

    public enum IssueKind {
        ERROR_VALUE,
        NUMBER_AS_TEXT,
        INCONSISTENT,
        CIRCULAR,
        TWO_DIGIT_YEAR,
        EMPTY_REFERENCE
    }

    public class AuditIssue {
        public Sheet sheet;
        public int row;
        public int col;
        public IssueKind kind;
        public string message;

        public AuditIssue (Sheet sheet, int row, int col, IssueKind kind, string message) {
            this.sheet = sheet;
            this.row = row;
            this.col = col;
            this.kind = kind;
            this.message = message;
        }
    }

    public class Audit {
        private static void add_area (Gee.ArrayList<Area> list, Area a) {
            foreach (var x in list) {
                if (x.sheet == a.sheet && x.r1 == a.r1 && x.c1 == a.c1 && x.r2 == a.r2 && x.c2 == a.c2) return;
            }
            list.add (a);
        }

        private static void collect (Workbook book, Sheet own, Node n, int row, int col, Gee.ArrayList<Area> out_list, int depth) {
            switch (n.kind) {
                case NodeKind.REF:
                    if (n.a == null || n.bad_sheet) return;
                    if (n.is_3d ()) {
                        int i1 = book.sheets.index_of (n.sheet), i2 = book.sheets.index_of (n.sheet2);
                        if (i1 < 0 || i2 < 0) return;
                        for (int i = int.min (i1, i2); i <= int.max (i1, i2); i++) {
                            var copy = n.copy ();
                            copy.sheet = book.sheets[i];
                            copy.sheet2 = null;
                            copy.sheet_name2 = "";
                            add_area (out_list, copy.to_area (own));
                        }
                        return;
                    }
                    if (n.spill) {
                        var sa = book.spill_area (n.sheet ?? own, n.a.row, n.a.col);
                        if (sa != null) add_area (out_list, sa);
                        return;
                    }
                    var a = n.to_area (own);
                    if (a.sheet == null) a.sheet = own;
                    add_area (out_list, a);
                    return;
                case NodeKind.STRUCT:
                    var ta = Tables.resolve (book, n.sref, own, row, col);
                    if (ta != null) add_area (out_list, ta);
                    return;
                case NodeKind.NAME:
                    if (depth > 10) return;
                    string? def = null;
                    foreach (var e in own.names.entries) if (e.key.casefold () == n.text.casefold ()) def = e.value;
                    if (def == null) foreach (var e in book.names.entries) if (e.key.casefold () == n.text.casefold ()) def = e.value;
                    if (def == null) {
                        var tr = Tables.resolve_name (book, n.text);
                        if (tr != null) add_area (out_list, tr);
                        return;
                    }
                    try {
                        var node = Formula.parse (def.has_prefix ("=") ? def : "=" + def, book, own);
                        collect (book, own, node, row, col, out_list, depth + 1);
                    } catch (FormulaError e) {
                    }
                    return;
                default:
                    foreach (var c in n.args) collect (book, own, c, row, col, out_list, depth);
                    return;
            }
        }

        public static Gee.ArrayList<Area> precedents (Workbook book, Sheet sheet, int row, int col) {
            var list = new Gee.ArrayList<Area> ();
            var cell = sheet.get_cell (row, col);
            if (cell == null || cell.formula == null) return list;
            collect (book, sheet, cell.formula, row, col, list, 0);
            return list;
        }

        public static Gee.ArrayList<AuditRef> dependents (Workbook book, Sheet sheet, int row, int col) {
            var list = new Gee.ArrayList<AuditRef> ();
            foreach (var s in book.sheets) {
                foreach (var c in s.cells.values) {
                    if (c.formula == null) continue;
                    var refs = new Gee.ArrayList<Area> ();
                    collect (book, s, c.formula, c.row, c.col, refs, 0);
                    foreach (var a in refs) {
                        var target = a.sheet ?? s;
                        if (target == sheet && a.contains (row, col)) {
                            list.add (new AuditRef (s, c.row, c.col));
                            break;
                        }
                    }
                }
            }
            list.sort ((x, y) => {
                int sx = book.sheets.index_of (x.sheet), sy = book.sheets.index_of (y.sheet);
                if (sx != sy) return sx - sy;
                if (x.row != y.row) return x.row - y.row;
                return x.col - y.col;
            });
            return list;
        }

        public static Gee.ArrayList<AuditRef> formula_cells_in (Workbook book, Area a) {
            var list = new Gee.ArrayList<AuditRef> ();
            var s = a.sheet;
            if (s == null) return list;
            s.foreach_in (a, (r, c, cell) => {
                if (cell.formula != null) list.add (new AuditRef (s, r, c));
            });
            return list;
        }

        private static bool looks_numeric (string t) {
            string s = t.strip ();
            if (s == "") return false;
            double d;
            string f;
            return Input.parse_number (s, out d, out f);
        }

        private static string pattern (Node n, int row, int col, Sheet s) {
            return Formula.to_text (Formula.shifted (n, -row, -col), s);
        }

        public static Gee.ArrayList<AuditIssue> check (Workbook book, Sheet? only = null) {
            var issues = new Gee.ArrayList<AuditIssue> ();
            foreach (var s in book.sheets) {
                if (only != null && s != only) continue;
                var keys = new Gee.ArrayList<int64?> ();
                foreach (var k in s.cells.keys) keys.add (k);
                keys.sort ((a, b) => {
                    int64 x = a;
                    int64 y = b;
                    return x < y ? -1 : (x > y ? 1 : 0);
                });
                foreach (var k in keys) {
                    var c = s.cells[k];
                    if (c.formula != null) {
                        var v = book.cell_value (s, c);
                        if (v.is_error ()) {
                            if (v.error == ErrorKind.CIRC) issues.add (new AuditIssue (s, c.row, c.col, IssueKind.CIRCULAR, _("Circular reference")));
                            else issues.add (new AuditIssue (s, c.row, c.col, IssueKind.ERROR_VALUE, _("The formula returns %s").printf (v.error.to_string ())));
                            continue;
                        }
                        var above = s.get_cell (c.row - 1, c.col);
                        var below = s.get_cell (c.row + 1, c.col);
                        if (c.row > 0 && above != null && below != null && above.formula != null && below.formula != null) {
                            string pa = pattern (above.formula, c.row - 1, c.col, s);
                            string pb = pattern (below.formula, c.row + 1, c.col, s);
                            string pc = pattern (c.formula, c.row, c.col, s);
                            if (pa == pb && pc != pa) {
                                issues.add (new AuditIssue (s, c.row, c.col, IssueKind.INCONSISTENT, _("The formula differs from the formulas around it")));
                                continue;
                            }
                        }
                        foreach (var a in precedents (book, s, c.row, c.col)) {
                            if (!a.is_single ()) continue;
                            var target = a.sheet ?? s;
                            var pc2 = target.get_cell (a.r1, a.c1);
                            if (pc2 == null || (pc2.input == "" && pc2.formula == null)) {
                                issues.add (new AuditIssue (s, c.row, c.col, IssueKind.EMPTY_REFERENCE, _("The formula refers to the empty cell %s").printf (Address.cell (a.r1, a.c1))));
                                break;
                            }
                        }
                        continue;
                    }
                    if (c.value.kind == ValueKind.TEXT && c.input != "" && looks_numeric (c.input.has_prefix ("'") ? c.input.substring (1) : c.input)) {
                        issues.add (new AuditIssue (s, c.row, c.col, IssueKind.NUMBER_AS_TEXT, _("Number stored as text")));
                    }
                }
            }
            return issues;
        }
    }

    public class EvalStep {
        public Node node;
        public Value value;

        public EvalStep (Node node, Value value) {
            this.node = node;
            this.value = value;
        }
    }

    public class FormulaEvaluation {
        public Workbook book;
        public Sheet sheet;
        public int row;
        public int col;
        public Node root;
        public Gee.ArrayList<EvalStep> steps = new Gee.ArrayList<EvalStep> ();
        public int done;
        private Gee.HashMap<Node, Value> values = new Gee.HashMap<Node, Value> ();

        public FormulaEvaluation (Workbook book, Sheet sheet, int row, int col, Node root) {
            this.book = book;
            this.sheet = sheet;
            this.row = row;
            this.col = col;
            this.root = root;
            var ev = new Evaluator (book, sheet, row, col);
            plan (ev, root);
        }

        private static bool leaf_literal (Node n) {
            return n.kind == NodeKind.NUMBER || n.kind == NodeKind.TEXT || n.kind == NodeKind.BOOL || n.kind == NodeKind.ERROR || n.kind == NodeKind.MISSING || n.kind == NodeKind.ARRAY || n.kind == NodeKind.VALUE;
        }

        private void plan (Evaluator ev, Node n) {
            if (leaf_literal (n)) return;
            if (n.kind == NodeKind.CALL && (n.text == "LAMBDA" || n.text == "LET")) {
                steps.add (new EvalStep (n, ev.eval (n)));
                return;
            }
            if (n.kind == NodeKind.BINARY && n.op == ":") {
                steps.add (new EvalStep (n, ev.eval (n)));
                return;
            }
            foreach (var c in n.args) plan (ev, c);
            steps.add (new EvalStep (n, ev.eval (n)));
        }

        public bool finished {
            get { return done >= steps.size; }
        }

        public Node? current {
            get { return done < steps.size ? steps[done].node : null; }
        }

        public void step () {
            if (done >= steps.size) return;
            values[steps[done].node] = steps[done].value;
            done++;
        }

        public void restart () {
            done = 0;
            values.clear ();
        }

        public string value_text (Value v) {
            var ev = new Evaluator (book, sheet, row, col);
            if (v.kind == ValueKind.RANGE) {
                if (v.area.is_single ()) return value_text (ev.cell (v.area.sheet, v.area.r1, v.area.c1));
                if (v.area.size > 400) return v.area.to_string ();
                return Formula.literal_text (Value.matrix (ev.to_matrix (v)));
            }
            if (v.kind == ValueKind.ARRAY) {
                if (v.array.length[0] * v.array.length[1] > 400) return "{...}";
                return Formula.literal_text (v);
            }
            if (v.kind == ValueKind.LAMBDA) return "LAMBDA";
            if (v.kind == ValueKind.REFS) return "#VALUE!";
            if (v.kind == ValueKind.EMPTY) return "0";
            if (v.kind == ValueKind.BOOL) return v.number != 0 ? "TRUE" : "FALSE";
            return Formula.literal_text (v);
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

        public string markup () {
            return "=" + render (root, 0, true);
        }

        public string plain () {
            return "=" + render (root, 0, false);
        }

        private string render (Node n, int parent, bool mark) {
            string s;
            if (values.has_key (n)) {
                s = Markup.escape_text (value_text (values[n]));
                if (!mark) s = value_text (values[n]);
            } else {
                s = inner (n, parent, mark);
            }
            if (mark && current == n) return "<u><b>" + s + "</b></u>";
            return s;
        }

        private string esc (string t, bool mark) {
            return mark ? Markup.escape_text (t) : t;
        }

        private string inner (Node n, int parent, bool mark) {
            switch (n.kind) {
                case NodeKind.PERCENT:
                    return render (n.args[0], 7, mark) + "%";
                case NodeKind.UNARY:
                    return esc (n.op, mark) + render (n.args[0], 6, mark);
                case NodeKind.BINARY:
                    int p = prec (n.op);
                    string l = render (n.args[0], p, mark);
                    string r = render (n.args[1], p + (n.op == "^" ? 0 : 1), mark);
                    string s = l + esc (n.op, mark) + r;
                    return p < parent ? "(" + s + ")" : s;
                case NodeKind.CALL:
                    string[] parts = {};
                    foreach (var a in n.args) parts += render (a, 0, mark);
                    return esc (n.text, mark) + "(" + string.joinv (",", parts) + ")";
                case NodeKind.APPLY:
                    string[] aparts = {};
                    for (int i = 1; i < n.args.length; i++) aparts += render (n.args[i], 0, mark);
                    return render (n.args[0], 9, mark) + "(" + string.joinv (",", aparts) + ")";
                default:
                    return esc (Formula.render (n, sheet, parent), mark);
            }
        }
    }
}
