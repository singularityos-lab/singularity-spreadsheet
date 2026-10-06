namespace Singularity.Apps.Spreadsheet {

    public enum ValidationKind {
        ANY,
        WHOLE,
        DECIMAL,
        LIST,
        DATE,
        TIME,
        TEXT_LENGTH,
        CUSTOM;

        public string xlsx_name () {
            switch (this) {
                case ANY: return "none";
                case WHOLE: return "whole";
                case DECIMAL: return "decimal";
                case LIST: return "list";
                case DATE: return "date";
                case TIME: return "time";
                case TEXT_LENGTH: return "textLength";
                default: return "custom";
            }
        }

        public static ValidationKind from_xlsx (string s) {
            switch (s) {
                case "whole": return WHOLE;
                case "decimal": return DECIMAL;
                case "list": return LIST;
                case "date": return DATE;
                case "time": return TIME;
                case "textLength": return TEXT_LENGTH;
                case "custom": return CUSTOM;
                default: return ANY;
            }
        }
    }

    public enum ValidationOp {
        BETWEEN,
        NOT_BETWEEN,
        EQUAL,
        NOT_EQUAL,
        GREATER,
        LESS,
        GREATER_EQUAL,
        LESS_EQUAL;

        public string xlsx_name () {
            switch (this) {
                case NOT_BETWEEN: return "notBetween";
                case EQUAL: return "equal";
                case NOT_EQUAL: return "notEqual";
                case GREATER: return "greaterThan";
                case LESS: return "lessThan";
                case GREATER_EQUAL: return "greaterThanOrEqual";
                case LESS_EQUAL: return "lessThanOrEqual";
                default: return "between";
            }
        }

        public static ValidationOp from_xlsx (string s) {
            switch (s) {
                case "notBetween": return NOT_BETWEEN;
                case "equal": return EQUAL;
                case "notEqual": return NOT_EQUAL;
                case "greaterThan": return GREATER;
                case "lessThan": return LESS;
                case "greaterThanOrEqual": return GREATER_EQUAL;
                case "lessThanOrEqual": return LESS_EQUAL;
                default: return BETWEEN;
            }
        }

        public bool two_values () {
            return this == BETWEEN || this == NOT_BETWEEN;
        }
    }

    public enum ValidationAlert {
        STOP,
        WARNING,
        INFORMATION;

        public string xlsx_name () {
            switch (this) {
                case WARNING: return "warning";
                case INFORMATION: return "information";
                default: return "stop";
            }
        }

        public static ValidationAlert from_xlsx (string s) {
            switch (s) {
                case "warning": return WARNING;
                case "information": return INFORMATION;
                default: return STOP;
            }
        }
    }

    public class ValidationCheck {
        public static Validation? at (Sheet s, int r, int c) {
            for (int i = s.validations.size - 1; i >= 0; i--) {
                if (s.validations[i].area.contains (r, c)) return s.validations[i];
            }
            return null;
        }

        private static Value eval_at (Workbook book, Sheet s, Validation v, string formula, int r, int c) {
            string f = formula.strip ();
            if (f == "") return Value.empty ();
            if (f.has_prefix ("=")) f = f.substring (1);
            try {
                var node = Formula.parse ("=" + f, book, s);
                var shifted = Formula.shifted (node, r - v.area.r1, c - v.area.c1);
                var ev = new Evaluator (book, s, r, c);
                return ev.eval_top (shifted);
            } catch (FormulaError e) {
                var parsed = Input.parse (f);
                return parsed.value;
            }
        }

        private static bool compare (ValidationOp op, double x, double a, double b) {
            switch (op) {
                case ValidationOp.BETWEEN: return x >= double.min (a, b) && x <= double.max (a, b);
                case ValidationOp.NOT_BETWEEN: return x < double.min (a, b) || x > double.max (a, b);
                case ValidationOp.EQUAL: return x == a;
                case ValidationOp.NOT_EQUAL: return x != a;
                case ValidationOp.GREATER: return x > a;
                case ValidationOp.LESS: return x < a;
                case ValidationOp.GREATER_EQUAL: return x >= a;
                default: return x <= a;
            }
        }

        public static bool is_blank (Value v) {
            return v.kind == ValueKind.EMPTY || (v.kind == ValueKind.TEXT && v.text == "");
        }

        public static bool valid (Workbook book, Sheet s, Validation v, int r, int c, Value value) {
            if (v.kind == ValidationKind.ANY) return true;
            if (is_blank (value)) return v.allow_blank;
            if (value.is_error ()) return v.kind == ValidationKind.CUSTOM ? custom_ok (book, s, v, r, c) : false;
            switch (v.kind) {
                case ValidationKind.LIST:
                    var items = list_items (book, s, v, r, c);
                    string t = Evaluator.to_text (value);
                    foreach (string item in items) {
                        if (item.casefold () == t.casefold ()) return true;
                    }
                    double d;
                    if (Evaluator.to_number (value, out d) == null) {
                        foreach (string item in items) {
                            double id;
                            string fmt;
                            if (Input.parse_number (item, out id, out fmt) && id == d) return true;
                        }
                    }
                    return false;
                case ValidationKind.CUSTOM:
                    return custom_ok (book, s, v, r, c);
                case ValidationKind.TEXT_LENGTH:
                    double la, lb;
                    if (!bounds (book, s, v, r, c, out la, out lb)) return false;
                    return compare (v.op, Evaluator.to_text (value).char_count (), la, lb);
                default:
                    if (value.kind != ValueKind.NUMBER) return false;
                    double x = value.number;
                    if (v.kind == ValidationKind.WHOLE && x != Math.floor (x)) return false;
                    if (v.kind == ValidationKind.TIME) x = x - Math.floor (x);
                    double a, b;
                    if (!bounds (book, s, v, r, c, out a, out b)) return false;
                    if (v.kind == ValidationKind.TIME) {
                        a = a - Math.floor (a);
                        b = b - Math.floor (b);
                    }
                    return compare (v.op, x, a, b);
            }
        }

        private static bool custom_ok (Workbook book, Sheet s, Validation v, int r, int c) {
            var res = eval_at (book, s, v, v.formula1, r, c);
            if (res.is_error ()) return false;
            if (res.kind == ValueKind.TEXT) return res.text.up () == "TRUE";
            return res.number != 0;
        }

        private static bool bounds (Workbook book, Sheet s, Validation v, int r, int c, out double a, out double b) {
            a = b = 0;
            var va = eval_at (book, s, v, v.formula1, r, c);
            if (Evaluator.to_number (va, out a) != null) return false;
            if (v.op.two_values ()) {
                var vb = eval_at (book, s, v, v.formula2, r, c);
                if (Evaluator.to_number (vb, out b) != null) return false;
            }
            return true;
        }

        public static Gee.List<string> list_items (Workbook book, Sheet s, Validation v, int r, int c) {
            var items = new Gee.ArrayList<string> ();
            string src = v.list_source != "" ? v.list_source : v.formula1;
            src = src.strip ();
            if (src.has_prefix ("\"") && src.has_suffix ("\"") && src.length >= 2) {
                foreach (string p in src.substring (1, src.length - 2).split (",")) if (p.strip () != "") items.add (p.strip ());
                return items;
            }
            try {
                var ev = new Evaluator (book, s, r, c);
                var val = ev.eval (Formula.parse ("=" + (src.has_prefix ("=") ? src.substring (1) : src), book, s));
                if (val.kind == ValueKind.TEXT && !src.contains ("!") && !src.contains (":")) {
                    foreach (string p in val.text.split (",")) if (p.strip () != "") items.add (p.strip ());
                    return items;
                }
                ev.visit_value (val, true, (x, fr) => {
                    if (x.kind != ValueKind.EMPTY) items.add (x.display ());
                    return true;
                });
            } catch (FormulaError e) {
                foreach (string p in src.split (",")) if (p.strip () != "") items.add (p.strip ());
            }
            return items;
        }

        public static Value candidate (string text) {
            if (text.has_prefix ("=")) return Value.empty ();
            return Input.parse (text).value;
        }

        public static Gee.List<Area> invalid_cells (Workbook book, Sheet s) {
            var result = new Gee.ArrayList<Area> ();
            foreach (var v in s.validations) {
                var a = Document.clamp_area (s, v.area);
                int r2 = int.min (a.r2, int.max (s.max_row, a.r1));
                int c2 = int.min (a.c2, int.max (s.max_col, a.c1));
                for (int r = a.r1; r <= r2; r++) {
                    for (int c = a.c1; c <= c2; c++) {
                        var val = s.value_at (r, c);
                        if (is_blank (val)) continue;
                        if (!valid (book, s, v, r, c, val)) result.add (new Area.cell (s, r, c));
                        if (result.size > 5000) return result;
                    }
                }
            }
            return result;
        }

        public static string default_error (Validation v) {
            switch (v.kind) {
                case ValidationKind.WHOLE: return _("The value must be a whole number that meets the rule for this cell.");
                case ValidationKind.DECIMAL: return _("The value must be a number that meets the rule for this cell.");
                case ValidationKind.LIST: return _("The value must be one of the items in the list.");
                case ValidationKind.DATE: return _("The value must be a date that meets the rule for this cell.");
                case ValidationKind.TIME: return _("The value must be a time that meets the rule for this cell.");
                case ValidationKind.TEXT_LENGTH: return _("The text length does not meet the rule for this cell.");
                default: return _("This value doesn't match the data validation restrictions defined for this cell.");
            }
        }
    }
}
