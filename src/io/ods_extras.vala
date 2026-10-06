namespace Singularity.Apps.Spreadsheet {

    public class OdsExtras {
        public static void write (OdsOut o) {
            AnalysisStore.write_ods (o);
            EditOds.write (o);
            PrintIo.write_ods (o);
            OdsDrawing.write (o);
            CommentsIo.write_ods (o);
            RevisionsIo.write_ods (o);
        }

        public static void read (OdsIn inp) {
            RevisionsIo.read_ods (inp);
            AnalysisStore.read_ods (inp);
            EditOds.read (inp);
            PrintIo.read_ods (inp);
            OdsDrawing.read (inp);
        }

        public static void read_table (OdsIn inp, Sheet sheet, Xml.Node* table) {
            EditOds.read_table (sheet, table);
            PrintIo.read_ods_table (inp, sheet, table);
        }

        public static void read_cell (OdsIn inp, Sheet sheet, Xml.Node* cell, int row, int col) {
            CommentsIo.read_ods_cell (sheet, cell, row, col);
        }

        public static void read_cell_style (CellStyle st, Xml.Node* style) {
            EditOds.read_cell_style (st, style);
        }

        public static string cell_properties (CellStyle st) {
            return EditOds.cell_properties (st);
        }

        public static void read_table_settings (Sheet sheet, Gee.HashMap<string, string> values) {
            EditOds.read_views (sheet, values);
        }

        private static string expr (string v) {
            string t = v.strip ();
            if (t.has_prefix ("=")) t = t.substring (1);
            if (t == "") return "0";
            try {
                var n = Formula.parse ("=" + t, null, null);
                return Ods.to_of (n, new Sheet (new Workbook (), "")).substring (4);
            } catch (FormulaError e) {
                return t;
            }
        }

        private static string list_expr (string src) {
            string s = src.strip ();
            if (s.has_prefix ("=")) s = s.substring (1);
            if (s.has_prefix ("\"") && s.has_suffix ("\"") && s.length >= 2) {
                string inner = s.substring (1, s.length - 2);
                string[] items = {};
                foreach (string it in inner.split (",")) items += "\"" + it.strip ().replace ("\"", "\"\"") + "\"";
                return string.joinv (";", items);
            }
            return expr (s);
        }

        private static string compare (ValidationOp op, string a, string b, string subject) {
            switch (op) {
                case ValidationOp.BETWEEN: return "%s-is-between(%s;%s)".printf (subject, expr (a), expr (b));
                case ValidationOp.NOT_BETWEEN: return "%s-is-not-between(%s;%s)".printf (subject, expr (a), expr (b));
                case ValidationOp.EQUAL: return "%s()=%s".printf (subject, expr (a));
                case ValidationOp.NOT_EQUAL: return "%s()!=%s".printf (subject, expr (a));
                case ValidationOp.GREATER: return "%s()>%s".printf (subject, expr (a));
                case ValidationOp.LESS: return "%s()<%s".printf (subject, expr (a));
                case ValidationOp.GREATER_EQUAL: return "%s()>=%s".printf (subject, expr (a));
                default: return "%s()<=%s".printf (subject, expr (a));
            }
        }

        public static string validation_condition (Validation v) {
            switch (v.kind) {
                case ValidationKind.LIST:
                    string src = v.list_source != "" ? v.list_source : v.formula1;
                    if (src == "") return "";
                    return "of:cell-content-is-in-list(%s)".printf (list_expr (src));
                case ValidationKind.WHOLE:
                    return "of:cell-content-is-whole-number() and " + compare (v.op, v.formula1, v.formula2, "cell-content");
                case ValidationKind.DECIMAL:
                    return "of:cell-content-is-decimal-number() and " + compare (v.op, v.formula1, v.formula2, "cell-content");
                case ValidationKind.DATE:
                    return "of:cell-content-is-date() and " + compare (v.op, v.formula1, v.formula2, "cell-content");
                case ValidationKind.TIME:
                    return "of:cell-content-is-time() and " + compare (v.op, v.formula1, v.formula2, "cell-content");
                case ValidationKind.TEXT_LENGTH:
                    string c = compare (v.op, v.formula1, v.formula2, "cell-content-text-length");
                    return "of:" + c;
                case ValidationKind.CUSTOM:
                    return "of:is-true-formula(%s)".printf (expr (v.formula1));
                default:
                    return v.message != "" || v.input_title != "" ? "of:is-true-formula(1)" : "";
            }
        }

        private static string xl (string of_text) {
            string f = Ods.from_of (of_text.strip ());
            return f.has_prefix ("=") ? f.substring (1) : f;
        }

        private static bool parse_compare (Validation v, string text, string subject) {
            string t = text.strip ();
            if (t.has_prefix (subject + "-is-between(") || t.has_prefix (subject + "-is-not-between(")) {
                bool not = t.has_prefix (subject + "-is-not-between(");
                string inner = t.substring (t.index_of_char ('(') + 1);
                if (inner.has_suffix (")")) inner = inner.substring (0, inner.length - 1);
                var parts = OdsReader.split_args (inner);
                if (parts.length != 2) return false;
                v.op = not ? ValidationOp.NOT_BETWEEN : ValidationOp.BETWEEN;
                v.formula1 = xl (parts[0]);
                v.formula2 = xl (parts[1]);
                return true;
            }
            string head = subject + "()";
            if (!t.has_prefix (head)) return false;
            string rest = t.substring (head.length);
            string[] ops = { "!=", ">=", "<=", ">", "<", "=" };
            ValidationOp[] kinds = { ValidationOp.NOT_EQUAL, ValidationOp.GREATER_EQUAL, ValidationOp.LESS_EQUAL, ValidationOp.GREATER, ValidationOp.LESS, ValidationOp.EQUAL };
            for (int i = 0; i < ops.length; i++) {
                if (rest.has_prefix (ops[i])) {
                    v.op = kinds[i];
                    v.formula1 = xl (rest.substring (ops[i].length));
                    return true;
                }
            }
            return false;
        }

        public static bool read_validation_condition (Validation v, string cond) {
            string c = cond.strip ();
            foreach (string pre in new string[] { "of:", "oooc:", "msoxl:" }) {
                if (c.has_prefix (pre)) c = c.substring (pre.length);
            }
            if (c.has_prefix ("cell-content-is-in-list(")) {
                string inner = c.substring ("cell-content-is-in-list(".length);
                if (inner.has_suffix (")")) inner = inner.substring (0, inner.length - 1);
                v.kind = ValidationKind.LIST;
                var parts = OdsReader.split_args (inner);
                bool literal = true;
                foreach (string p in parts) if (!p.strip ().has_prefix ("\"")) literal = false;
                if (literal) {
                    string[] items = {};
                    foreach (string p in parts) {
                        string t = p.strip ();
                        items += t.substring (1, t.length - 2).replace ("\"\"", "\"");
                    }
                    v.list_source = "\"" + string.joinv (",", items) + "\"";
                } else {
                    v.list_source = xl (inner);
                }
                v.formula1 = v.list_source;
                return true;
            }
            if (c.has_prefix ("is-true-formula(")) {
                string inner = c.substring ("is-true-formula(".length);
                if (inner.has_suffix (")")) inner = inner.substring (0, inner.length - 1);
                v.kind = ValidationKind.CUSTOM;
                v.formula1 = xl (inner);
                return true;
            }
            string[] heads = { "cell-content-is-whole-number() and ", "cell-content-is-decimal-number() and ", "cell-content-is-date() and ", "cell-content-is-time() and " };
            ValidationKind[] kinds = { ValidationKind.WHOLE, ValidationKind.DECIMAL, ValidationKind.DATE, ValidationKind.TIME };
            for (int i = 0; i < heads.length; i++) {
                if (c.has_prefix (heads[i])) {
                    v.kind = kinds[i];
                    return parse_compare (v, c.substring (heads[i].length), "cell-content");
                }
            }
            if (c.has_prefix ("cell-content-text-length")) {
                v.kind = ValidationKind.TEXT_LENGTH;
                return parse_compare (v, c, "cell-content-text-length");
            }
            if (c.has_prefix ("cell-content")) {
                v.kind = ValidationKind.DECIMAL;
                return parse_compare (v, c, "cell-content");
            }
            return false;
        }
    }
}
