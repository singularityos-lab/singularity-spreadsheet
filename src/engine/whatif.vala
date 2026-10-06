namespace Singularity.Apps.Spreadsheet {

    public class CellRef {
        public Sheet sheet;
        public int row;
        public int col;

        public CellRef (Sheet sheet, int row, int col) {
            this.sheet = sheet;
            this.row = row;
            this.col = col;
        }

        public Value value () {
            return sheet.value_at (row, col);
        }

        public double number () {
            var v = value ();
            return v.kind == ValueKind.NUMBER || v.kind == ValueKind.BOOL ? v.number : 0;
        }

        public string input () {
            return sheet.input_at (row, col);
        }

        public string label (Sheet? own = null) {
            string a = Address.cell (row, col, true, true);
            return own == sheet ? a : Address.quote_sheet (sheet.name) + "!" + a;
        }

        public static CellRef? parse (Workbook book, string text, Sheet own) {
            string t = text.strip ();
            if (t.has_prefix ("=")) t = t.substring (1);
            Sheet s = own;
            int bang = t.last_index_of ("!");
            if (bang > 0) {
                string sn = t.substring (0, bang);
                if (sn.has_prefix ("'")) sn = sn.substring (1, sn.length - 2).replace ("''", "'");
                s = book.find_sheet (sn);
                if (s == null) return null;
                t = t.substring (bang + 1);
            }
            int r, c;
            bool ar, ac;
            if (!Address.parse_cell (t, out r, out c, out ar, out ac)) return null;
            return new CellRef (s, r, c);
        }
    }

    public class WhatIf {
        public static void set_number (Workbook book, Sheet s, int r, int c, double x) {
            var cell = s.ensure (r, c);
            cell.formula = null;
            cell.value = Value.num (x);
            cell.input = Value.format_number_general_full (x);
            cell.gen = 0;
            if (r > s.max_row) s.max_row = r;
            if (c > s.max_col) s.max_col = c;
            book.structure_changed = true;
        }

        public static void restore_input (Workbook book, Sheet s, int r, int c, string input, Value value) {
            var cell = s.ensure (r, c);
            if (input.has_prefix ("=")) {
                s.set_input (r, c, input);
            } else {
                cell.formula = null;
                cell.input = input;
                cell.value = input == "" ? Value.empty () : value;
                if (input == "") s.drop_if_blank (r, c);
            }
            book.structure_changed = true;
        }

        public static void put_value (Workbook book, Sheet s, int r, int c, Value v) {
            if (v.kind == ValueKind.EMPTY) {
                var old = s.get_cell (r, c);
                if (old != null) {
                    old.formula = null;
                    old.input = "";
                    old.value = Value.empty ();
                    s.drop_if_blank (r, c);
                }
                book.structure_changed = true;
                return;
            }
            var cell = s.ensure (r, c);
            cell.formula = null;
            cell.value = v;
            switch (v.kind) {
                case ValueKind.NUMBER: cell.input = Value.format_number_general_full (v.number); break;
                case ValueKind.TEXT: cell.input = QueryEngine.parse_value (v.text).kind != ValueKind.TEXT && v.text != "" ? "'" + v.text : v.text; break;
                default: cell.input = v.display (); break;
            }
            if (r > s.max_row) s.max_row = r;
            if (c > s.max_col) s.max_col = c;
            book.structure_changed = true;
        }

        public static double eval_at (Workbook book, CellRef input, CellRef target, double x) {
            set_number (book, input.sheet, input.row, input.col, x);
            book.recalculate ();
            var v = target.value ();
            if (v.kind == ValueKind.NUMBER || v.kind == ValueKind.BOOL) return v.number;
            return double.NAN;
        }

        public static bool goal_seek (Workbook book, CellRef target, double goal, CellRef changing, out double result, out double reached, int max_iter = 100, double tol = 0.001) {
            double x0 = changing.number ();
            result = x0;
            reached = double.NAN;
            double f0 = eval_at (book, changing, target, x0) - goal;
            if (f0.is_nan ()) return false;
            if (Math.fabs (f0) <= tol) {
                reached = f0 + goal;
                return true;
            }
            double x1 = x0 == 0 ? 0.01 : x0 * 1.01;
            double f1 = eval_at (book, changing, target, x1) - goal;
            double a = double.NAN, fa = 0, b = double.NAN, fb = 0;
            if (!f1.is_nan () && f0 * f1 < 0) {
                a = x0; fa = f0; b = x1; fb = f1;
            }
            for (int i = 0; i < max_iter && a.is_nan (); i++) {
                if (f1.is_nan () || f1 == f0) {
                    double step = Math.fabs (x1 - x0) * 2 + 1;
                    x1 = x0 + ((i % 2 == 0) ? step : -step) * (i + 1);
                    f1 = eval_at (book, changing, target, x1) - goal;
                    if (!f1.is_nan () && f0 * f1 < 0) {
                        a = x0; fa = f0; b = x1; fb = f1;
                    }
                    continue;
                }
                double x2 = x1 - f1 * (x1 - x0) / (f1 - f0);
                if (x2.is_nan () || x2.is_infinity () != 0) x2 = x1 * 2 + 1;
                double f2 = eval_at (book, changing, target, x2) - goal;
                if (!f2.is_nan () && Math.fabs (f2) <= tol) {
                    result = x2;
                    reached = f2 + goal;
                    return true;
                }
                if (!f2.is_nan () && f1 * f2 < 0) {
                    a = x1; fa = f1; b = x2; fb = f2;
                    break;
                }
                x0 = x1; f0 = f1; x1 = x2; f1 = f2;
            }
            if (a.is_nan ()) {
                result = x1;
                reached = f1 + goal;
                set_number (book, changing.sheet, changing.row, changing.col, x1);
                book.recalculate ();
                return !f1.is_nan () && Math.fabs (f1) <= tol;
            }
            double c = a, fc = fa;
            bool mflag = true;
            double d = 0;
            for (int i = 0; i < max_iter * 2; i++) {
                double s;
                if (fa != fc && fb != fc) {
                    s = a * fb * fc / ((fa - fb) * (fa - fc)) + b * fa * fc / ((fb - fa) * (fb - fc)) + c * fa * fb / ((fc - fa) * (fc - fb));
                } else {
                    s = b - fb * (b - a) / (fb - fa);
                }
                double lo = (3 * a + b) / 4;
                bool cond1 = !((s > double.min (lo, b)) && (s < double.max (lo, b)));
                bool cond2 = mflag && Math.fabs (s - b) >= Math.fabs (b - c) / 2;
                bool cond3 = !mflag && Math.fabs (s - b) >= Math.fabs (c - d) / 2;
                if (cond1 || cond2 || cond3) {
                    s = (a + b) / 2;
                    mflag = true;
                } else {
                    mflag = false;
                }
                double fs = eval_at (book, changing, target, s) - goal;
                if (fs.is_nan ()) fs = fb;
                d = c;
                c = b;
                fc = fb;
                if (fa * fs < 0) {
                    b = s;
                    fb = fs;
                } else {
                    a = s;
                    fa = fs;
                }
                if (Math.fabs (fa) < Math.fabs (fb)) {
                    double t = a; a = b; b = t;
                    t = fa; fa = fb; fb = t;
                }
                if (Math.fabs (fb) <= tol || Math.fabs (b - a) < 1e-12) break;
            }
            result = b;
            reached = eval_at (book, changing, target, b);
            return Math.fabs (reached - goal) <= tol * 10;
        }
    }

    public class Scenario {
        public string name;
        public string comment = "";
        public Sheet sheet;
        public Gee.ArrayList<CellRef> cells = new Gee.ArrayList<CellRef> ();
        public Gee.ArrayList<string> values = new Gee.ArrayList<string> ();

        public Scenario (string name, Sheet sheet) {
            this.name = name;
            this.sheet = sheet;
        }

        public void show (Workbook book) {
            for (int i = 0; i < cells.size && i < values.size; i++) {
                var c = cells[i];
                string v = values[i];
                c.sheet.set_input (c.row, c.col, v);
            }
            book.structure_changed = true;
            book.recalculate ();
        }

        public static Sheet summary (Workbook book, Gee.List<Scenario> list, Gee.List<CellRef> results) {
            var out_sheet = book.add_sheet (book.unique_sheet_name (_("Scenario Summary")));
            if (list.size == 0) return out_sheet;
            var changing = new Gee.ArrayList<CellRef> ();
            var keys = new Gee.HashSet<string> ();
            foreach (var sc in list) foreach (var c in sc.cells) {
                string k = c.label (null);
                if (keys.add (k)) changing.add (c);
            }
            var saved_inputs = new Gee.ArrayList<string> ();
            var saved_values = new Gee.ArrayList<Value> ();
            foreach (var c in changing) {
                saved_inputs.add (c.input ());
                saved_values.add (c.value ());
            }
            out_sheet.set_input (0, 0, _("Scenario Summary"));
            out_sheet.set_input (2, 1, _("Current Values:"));
            for (int j = 0; j < list.size; j++) out_sheet.set_input (2, 2 + j, list[j].name);
            out_sheet.set_input (3, 0, _("Changing Cells:"));
            int row = 4;
            for (int i = 0; i < changing.size; i++) {
                out_sheet.set_input (row + i, 1, changing[i].label (null));
                WhatIf.put_value (book, out_sheet, row + i, 2 + list.size, saved_values[i]);
            }
            int rrow = row + changing.size + 1;
            out_sheet.set_input (rrow - 0, 0, _("Result Cells:"));
            for (int i = 0; i < results.size; i++) out_sheet.set_input (rrow + 1 + i, 1, results[i].label (null));
            for (int i = 0; i < results.size; i++) WhatIf.put_value (book, out_sheet, rrow + 1 + i, 2 + list.size, results[i].value ());
            out_sheet.set_input (2, 2 + list.size, _("Current Values"));
            for (int j = 0; j < list.size; j++) {
                list[j].show (book);
                for (int i = 0; i < changing.size; i++) WhatIf.put_value (book, out_sheet, row + i, 2 + j, changing[i].value ());
                for (int i = 0; i < results.size; i++) WhatIf.put_value (book, out_sheet, rrow + 1 + i, 2 + j, results[i].value ());
            }
            for (int i = 0; i < changing.size; i++) WhatIf.restore_input (book, changing[i].sheet, changing[i].row, changing[i].col, saved_inputs[i], saved_values[i]);
            book.recalculate ();
            return out_sheet;
        }
    }

    public class DataTableDef {
        public Sheet sheet;
        public Area area;
        public CellRef? row_input;
        public CellRef? col_input;

        public DataTableDef (Sheet sheet, Area area) {
            this.sheet = sheet;
            this.area = area;
        }

        public Area interior {
            owned get { return new Area (sheet, area.r1 + 1, area.c1 + 1, area.r2, area.c2); }
        }

        public bool two_way () {
            return row_input != null && col_input != null;
        }

        public void compute (Workbook book) {
            if (area.rows < 2 || area.cols < 2) return;
            var results = new Gee.HashMap<int64?, Value> ((k) => { int64 v = k; return (uint) (v ^ (v >> 32)); }, (a, b) => { int64 x = a; int64 y = b; return x == y; });
            string[] saved_in = {};
            Value[] saved_v = {};
            CellRef[] inputs = {};
            if (row_input != null) inputs += row_input;
            if (col_input != null) inputs += col_input;
            foreach (var c in inputs) {
                saved_in += c.input ();
                saved_v += c.value ();
            }
            if (two_way ()) {
                for (int r = area.r1 + 1; r <= area.r2; r++) {
                    for (int c = area.c1 + 1; c <= area.c2; c++) {
                        apply_input (book, row_input, sheet.value_at (area.r1, c));
                        apply_input (book, col_input, sheet.value_at (r, area.c1));
                        book.recalculate ();
                        results[Sheet.key (r, c)] = sheet.value_at (area.r1, area.c1);
                    }
                }
            } else if (col_input != null) {
                for (int r = area.r1 + 1; r <= area.r2; r++) {
                    apply_input (book, col_input, sheet.value_at (r, area.c1));
                    book.recalculate ();
                    for (int c = area.c1 + 1; c <= area.c2; c++) results[Sheet.key (r, c)] = sheet.value_at (area.r1, c);
                }
            } else if (row_input != null) {
                for (int c = area.c1 + 1; c <= area.c2; c++) {
                    apply_input (book, row_input, sheet.value_at (area.r1, c));
                    book.recalculate ();
                    for (int r = area.r1 + 1; r <= area.r2; r++) results[Sheet.key (r, c)] = sheet.value_at (r, area.c1);
                }
            }
            for (int i = 0; i < inputs.length; i++) WhatIf.restore_input (book, inputs[i].sheet, inputs[i].row, inputs[i].col, saved_in[i], saved_v[i]);
            foreach (var e in results.entries) {
                int64 k = e.key;
                WhatIf.put_value (book, sheet, Sheet.key_row (k), Sheet.key_col (k), e.value);
            }
            book.recalculate ();
        }

        private static void apply_input (Workbook book, CellRef input, Value v) {
            if (v.kind == ValueKind.NUMBER) WhatIf.set_number (book, input.sheet, input.row, input.col, v.number);
            else WhatIf.put_value (book, input.sheet, input.row, input.col, v);
        }
    }
}
