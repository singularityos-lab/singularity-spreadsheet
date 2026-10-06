namespace Singularity.Apps.Spreadsheet {

    public enum HAlign {
        GENERAL,
        LEFT,
        CENTER,
        RIGHT,
        FILL,
        JUSTIFY
    }

    public enum VAlign {
        BOTTOM,
        CENTER,
        TOP
    }

    public enum BorderStyle {
        NONE,
        THIN,
        MEDIUM,
        THICK,
        DASHED,
        DOTTED,
        DOUBLE
    }

    public class Border {
        public BorderStyle style;
        public string color;

        public Border (BorderStyle style = BorderStyle.NONE, string color = "") {
            this.style = style;
            this.color = color;
        }

        public string key () {
            return "%d/%s".printf ((int) style, color);
        }
    }

    public class CellStyle {
        public bool bold;
        public bool italic;
        public bool underline;
        public bool strike;
        public double font_size = 11;
        public string font_family = "";
        public string color = "";
        public string fill = "";
        public HAlign halign = HAlign.GENERAL;
        public VAlign valign = VAlign.BOTTOM;
        public bool wrap;
        public int indent;
        public string number_format = "General";
        public Border top = new Border ();
        public Border bottom = new Border ();
        public Border left = new Border ();
        public Border right = new Border ();
        public int rotation;
        public bool shrink;
        public bool locked = true;
        public bool hidden;
        public string style_name = "";

        public CellStyle copy () {
            var s = new CellStyle ();
            s.bold = bold;
            s.italic = italic;
            s.underline = underline;
            s.strike = strike;
            s.font_size = font_size;
            s.font_family = font_family;
            s.color = color;
            s.fill = fill;
            s.halign = halign;
            s.valign = valign;
            s.wrap = wrap;
            s.indent = indent;
            s.number_format = number_format;
            s.top = new Border (top.style, top.color);
            s.bottom = new Border (bottom.style, bottom.color);
            s.left = new Border (left.style, left.color);
            s.right = new Border (right.style, right.color);
            s.rotation = rotation;
            s.shrink = shrink;
            s.locked = locked;
            s.hidden = hidden;
            s.style_name = style_name;
            return s;
        }

        public string key () {
            return "%d%d%d%d|%s|%s|%s|%s|%d|%d|%d|%d|%s|%s|%s|%s|%s".printf (
                (int) bold, (int) italic, (int) underline, (int) strike,
                Value.fixed (font_size, 2), font_family, color, fill,
                (int) halign, (int) valign, (int) wrap, indent, number_format,
                top.key (), bottom.key (), left.key (), right.key ()) + "|%d|%d|%d|%d|%s".printf (rotation, (int) shrink, (int) locked, (int) hidden, style_name);
        }
    }

    public class Cell {
        public string input = "";
        public Node? formula;
        public Value value;
        public int style;
        public string note = "";
        public string link = "";
        public string note_author = "";
        public int row;
        public int col;
        public uint gen;
        public int state;
        public Value[,]? spill_values;
        public Area? array_area;
        public bool legacy;

        public Cell () {
            value = Value.empty ();
        }

        public bool is_blank () {
            return input == "" && formula == null && style == 0 && note == "" && link == "";
        }
    }

    public enum CondKind {
        GREATER,
        LESS,
        BETWEEN,
        EQUAL,
        NOT_EQUAL,
        TEXT_CONTAINS,
        DUPLICATE,
        UNIQUE,
        FORMULA,
        COLOR_SCALE,
        DATA_BAR,
        TOP,
        BOTTOM,
        ABOVE_AVERAGE,
        BELOW_AVERAGE,
        BLANK,
        ERRORS,
        GREATER_EQUAL,
        LESS_EQUAL,
        NOT_BETWEEN,
        TEXT_BEGINS,
        TEXT_ENDS,
        TEXT_NOT_CONTAINS,
        NO_BLANK,
        NO_ERRORS,
        DATE_OCCURRING,
        ICON_SET
    }

    public class CondFormat {
        public Area area;
        public CondKind kind;
        public string a = "";
        public string b = "";
        public int style;
        public string color1 = "#f8696b";
        public string color2 = "#ffeb84";
        public string color3 = "#63be7b";
        public bool three_colors = true;
        public bool stop_if_true;
        public bool percent;
        public string icon_set = "3Arrows";
        public bool icon_reverse;
        public bool show_value = true;
        public string date_period = "today";

        public CondFormat (Area area, CondKind kind) {
            this.area = area;
            this.kind = kind;
        }
    }

    public class Validation {
        public Area area;
        public string list_source = "";
        public string message = "";
        public ValidationKind kind = ValidationKind.LIST;
        public ValidationOp op = ValidationOp.BETWEEN;
        public string formula1 = "";
        public string formula2 = "";
        public bool allow_blank = true;
        public bool dropdown = true;
        public bool show_input = true;
        public string input_title = "";
        public bool show_error = true;
        public ValidationAlert alert = ValidationAlert.STOP;
        public string error_title = "";
        public string error_message = "";

        public Validation (Area area) {
            this.area = area;
        }

        public Validation copy_to (Area a) {
            var v = new Validation (a);
            v.list_source = list_source;
            v.message = message;
            v.kind = kind;
            v.op = op;
            v.formula1 = formula1;
            v.formula2 = formula2;
            v.allow_blank = allow_blank;
            v.dropdown = dropdown;
            v.show_input = show_input;
            v.input_title = input_title;
            v.show_error = show_error;
            v.alert = alert;
            v.error_title = error_title;
            v.error_message = error_message;
            return v;
        }
    }

    public class Filter {
        public Area area;
        public Gee.HashMap<int, Gee.HashSet<string>> hidden_values = new Gee.HashMap<int, Gee.HashSet<string>> ();
        public Gee.HashMap<int, FilterRule> rules = new Gee.HashMap<int, FilterRule> ();

        public Filter (Area area) {
            this.area = area;
        }

        public Filter copy_to (Area a) {
            var f = new Filter (a);
            foreach (var e in hidden_values.entries) {
                var set = new Gee.HashSet<string> ();
                set.add_all (e.value);
                f.hidden_values[e.key] = set;
            }
            foreach (var e in rules.entries) f.rules[e.key] = e.value.copy ();
            return f;
        }
    }

    public class Sheet {
        public unowned Workbook book;
        public string name;
        public Gee.HashMap<int64?, Cell> cells;
        public Gee.HashMap<int, int> col_widths = new Gee.HashMap<int, int> ();
        public Gee.HashMap<int, int> row_heights = new Gee.HashMap<int, int> ();
        public Gee.HashSet<int> hidden_rows = new Gee.HashSet<int> ();
        public Gee.HashSet<int> hidden_cols = new Gee.HashSet<int> ();
        public Gee.ArrayList<Area> merges = new Gee.ArrayList<Area> ();
        public Gee.ArrayList<CondFormat> cond_formats = new Gee.ArrayList<CondFormat> ();
        public Gee.ArrayList<Validation> validations = new Gee.ArrayList<Validation> ();
        public Gee.ArrayList<Chart> charts = new Gee.ArrayList<Chart> ();
        public Gee.ArrayList<Drawing> drawings = new Gee.ArrayList<Drawing> ();
        public Gee.ArrayList<SparklineGroup> sparklines = new Gee.ArrayList<SparklineGroup> ();
        public Filter? filter;
        public PageSetup page = new PageSetup ();
        public Gee.HashMap<string, string> names = new Gee.HashMap<string, string> ();
        public Gee.HashMap<int64?, Area> spills;
        public SheetProtection? protection;
        public SortSpec? sort_state;
        public Outline outline = new Outline ();
        public Gee.ArrayList<CustomView> views = new Gee.ArrayList<CustomView> ();
        public CommentStore comments = new CommentStore ();
        public int freeze_rows;
        public int freeze_cols;
        public string tab_color = "";
        public int visibility;
        public string code_name = "";
        public bool show_grid = true;
        public int default_col_width = 90;
        public int default_row_height = 24;
        public int max_row = -1;
        public int max_col = -1;

        public Sheet (Workbook book, string name) {
            this.book = book;
            this.name = name;
            cells = new Gee.HashMap<int64?, Cell> (
                (k) => { int64 v = k; return (uint) (v ^ (v >> 32)); },
                (a, b) => { int64 x = a; int64 y = b; return x == y; });
            spills = new Gee.HashMap<int64?, Area> (cells.key_hash_func, cells.key_equal_func);
        }

        public Cell? spill_anchor_at (int row, int col) {
            foreach (var e in spills.entries) {
                if (e.value.contains (row, col)) {
                    int64 k = e.key;
                    return cells[k];
                }
            }
            return null;
        }

        public static int64 key (int row, int col) {
            return ((int64) row << 16) | col;
        }

        public static int key_row (int64 k) {
            return (int) (k >> 16);
        }

        public static int key_col (int64 k) {
            return (int) (k & 0xffff);
        }

        public Cell? get_cell (int row, int col) {
            return cells[key (row, col)];
        }

        public Cell ensure (int row, int col) {
            int64 k = key (row, col);
            var c = cells[k];
            if (c == null) {
                c = new Cell ();
                c.row = row;
                c.col = col;
                cells[k] = c;
                if (row > max_row) max_row = row;
                if (col > max_col) max_col = col;
            }
            return c;
        }

        public void drop_if_blank (int row, int col) {
            var c = get_cell (row, col);
            if (c != null && c.is_blank ()) cells.unset (key (row, col));
        }

        public void recompute_extent () {
            max_row = -1;
            max_col = -1;
            foreach (var k in cells.keys) {
                var c = cells[k];
                if (c.input == "" && c.formula == null) continue;
                max_row = int.max (max_row, key_row (k));
                max_col = int.max (max_col, key_col (k));
            }
        }

        public string input_at (int row, int col) {
            var c = get_cell (row, col);
            return c != null ? c.input : "";
        }

        public Value value_at (int row, int col) {
            var c = get_cell (row, col);
            if (c != null && (c.formula != null || c.input != "")) return book.cell_value (this, c);
            if (spills.size > 0) {
                var anchor = spill_anchor_at (row, col);
                if (anchor != null && anchor != c) {
                    book.cell_value (this, anchor);
                    var sv = anchor.spill_values;
                    var area = spills[key (anchor.row, anchor.col)];
                    if (sv != null && area != null && area.contains (row, col)) {
                        int i = row - anchor.row, j = col - anchor.col;
                        if (i < sv.length[0] && j < sv.length[1]) return sv[i, j];
                        return Value.err (ErrorKind.NA);
                    }
                }
            }
            if (c == null) return Value.empty ();
            return book.cell_value (this, c);
        }

        public CellStyle style_at (int row, int col) {
            var c = get_cell (row, col);
            return book.styles[c != null ? c.style : 0];
        }

        public void set_input (int row, int col, string text) {
            var c = ensure (row, col);
            c.formula = null;
            c.legacy = false;
            c.value = Value.empty ();
            string t = text;
            if (t.has_prefix ("=") && t.length > 1) {
                try {
                    c.formula = Formula.parse (t, book, this);
                    c.input = Formula.to_text (c.formula, this);
                } catch (FormulaError e) {
                    c.formula = null;
                    c.input = t;
                    c.value = Value.err (ErrorKind.NAME);
                    c.state = -1;
                }
            } else {
                c.input = t;
                var parsed = Input.parse (t);
                c.value = parsed.value;
                if (parsed.format != "" && book.styles[c.style].number_format == "General") {
                    var st = book.styles[c.style].copy ();
                    st.number_format = parsed.format;
                    c.style = book.intern (st);
                }
            }
            if (t == "") drop_if_blank (row, col);
            else {
                if (row > max_row) max_row = row;
                if (col > max_col) max_col = col;
            }
            book.note_edit (this, row, col);
        }

        public void set_style (int row, int col, int style) {
            if (style == 0 && get_cell (row, col) == null) return;
            ensure (row, col).style = style;
            if (style == 0) drop_if_blank (row, col);
        }

        public int col_width (int col) {
            if (hidden_cols.contains (col)) return 0;
            return col_widths.has_key (col) ? col_widths[col] : default_col_width;
        }

        public int row_height (int row) {
            if (hidden_rows.contains (row)) return 0;
            return row_heights.has_key (row) ? row_heights[row] : default_row_height;
        }

        public Area? merge_at (int row, int col) {
            foreach (var m in merges) if (m.contains (row, col)) return m;
            return null;
        }

        public void @foreach_in (Area area, CellVisitor visit) {
            if (area.size <= cells.size * 2) {
                for (int r = area.r1; r <= int.min (area.r2, max_row); r++) {
                    for (int c = area.c1; c <= int.min (area.c2, max_col); c++) {
                        var cell = cells[key (r, c)];
                        if (cell != null) visit (r, c, cell);
                    }
                }
                return;
            }
            var keys = new Gee.ArrayList<int64?> ();
            foreach (var k in cells.keys) {
                if (area.contains (key_row (k), key_col (k))) keys.add (k);
            }
            keys.sort ((a, b) => {
                int64 x = a;
                int64 y = b;
                return x < y ? -1 : (x > y ? 1 : 0);
            });
            foreach (var k in keys) visit (key_row (k), key_col (k), cells[k]);
        }

        public Area used_area () {
            return new Area (this, 0, 0, int.max (max_row, 0), int.max (max_col, 0));
        }
    }

    public delegate void CellVisitor (int row, int col, Cell cell);

    public class Workbook {
        public Gee.ArrayList<Sheet> sheets = new Gee.ArrayList<Sheet> ();
        public Gee.ArrayList<CellStyle> styles = new Gee.ArrayList<CellStyle> ();
        public Gee.HashMap<string, string> names = new Gee.HashMap<string, string> ();
        public Gee.ArrayList<TableDef> tables = new Gee.ArrayList<TableDef> ();
        public RevisionLog revisions = new RevisionLog ();
        public signal void rows_cols_changed (Sheet s, bool rows, int at, int count);
        public ScriptStore scripts = new ScriptStore ();
        public Gee.ArrayList<CellWatch> watches = new Gee.ArrayList<CellWatch> ();
        public AnalysisData analysis = new AnalysisData ();
        public bool iterative;
        public int max_iterations = 100;
        public double max_change = 0.001;
        public bool manual_calc;
        public Gee.ArrayList<string> circular = new Gee.ArrayList<string> ();
        public bool date1904;
        public Gee.HashMap<string, string> properties = new Gee.HashMap<string, string> ();
        public Bytes? vba_project;
        public VbaProject? vba;
        public UdfProvider? udf;
        public string code_name = "";

        public void ensure_vba () {
            if (vba == null && vba_project != null) vba = VbaProject.from_bin (vba_project);
        }
        public BookProtection? protection;
        public Gee.ArrayList<string> custom_lists = new Gee.ArrayList<string> ();
        public DocTheme theme = new DocTheme ();
        public bool structure_changed = true;
        private Gee.HashMap<string, int> style_index = new Gee.HashMap<string, int> ();
        private uint gen = 1;
        private int depth = 0;

        public signal void recalculated ();

        public uint generation {
            get { return gen; }
        }

        public Workbook () {
            intern (new CellStyle ());
        }

        public int intern (CellStyle style) {
            string k = style.key ();
            if (style_index.has_key (k)) return style_index[k];
            styles.add (style);
            style_index[k] = styles.size - 1;
            return styles.size - 1;
        }

        public Sheet add_sheet (string? name = null, int at = -1) {
            string n = name ?? unique_sheet_name (_("Sheet"));
            var s = new Sheet (this, n);
            if (at < 0 || at > sheets.size) sheets.add (s);
            else sheets.insert (at, s);
            structure_changed = true;
            return s;
        }

        public string unique_sheet_name (string base_name) {
            for (int i = 1; ; i++) {
                string n = "%s%d".printf (base_name, i);
                if (find_sheet (n) == null) return n;
            }
        }

        public Sheet? find_sheet (string name) {
            foreach (var s in sheets) if (s.name.casefold () == name.casefold ()) return s;
            return null;
        }

        public void remove_sheet (Sheet sheet) {
            int gone = sheets.index_of (sheet);
            foreach (var s in sheets) {
                if (s == sheet) continue;
                foreach (var c in s.cells.values) {
                    if (c.formula == null) continue;
                    c.formula.foreach_ref ((r) => {
                        if (!r.is_3d () || r.sheet2 == null || r.sheet == null) return;
                        int i1 = sheets.index_of (r.sheet), i2 = sheets.index_of (r.sheet2);
                        if (i1 == i2) return;
                        int step = i1 < i2 ? 1 : -1;
                        if (i1 == gone) r.sheet = sheets[i1 + step];
                        else if (i2 == gone) r.sheet2 = sheets[i2 - step];
                        if (r.sheet == r.sheet2) {
                            r.sheet2 = null;
                            r.sheet_name2 = "";
                        }
                    });
                }
            }
            sheets.remove (sheet);
            foreach (var t in tables.to_array ()) if (t.sheet == sheet) tables.remove (t);
            foreach (var s in sheets) {
                foreach (var c in s.cells.values) {
                    if (c.formula == null) continue;
                    c.formula.foreach_ref ((r) => {
                        if (r.sheet == sheet) {
                            r.sheet = null;
                            r.a = null;
                            r.b = null;
                        }
                    });
                    c.input = Formula.to_text (c.formula, s);
                }
            }
            structure_changed = true;
        }

        public void rename_sheet (Sheet sheet, string name) {
            sheet.name = name;
            foreach (var s in sheets) {
                foreach (var c in s.cells.values) {
                    if (c.formula != null) c.input = Formula.to_text (c.formula, s);
                }
            }
        }

        public void invalidate () {
            gen++;
        }

        public Value cell_value (Sheet sheet, Cell c) {
            if (c.formula == null) return c.value;
            if (c.gen == gen) return c.value;
            if (c.state == 1) return iterating ? c.value : Value.err (ErrorKind.CIRC);
            if (depth > 400) return c.value;
            c.state = 1;
            depth++;
            var ev = new Evaluator (this, sheet, c.row, c.col);
            Value v;
            if (c.legacy && c.array_area == null) {
                ev.legacy = true;
                v = ev.eval_top (c.formula);
            } else {
                v = ev.eval_spill (c.formula);
            }
            depth--;
            c.state = 0;
            if (v.kind == ValueKind.ARRAY || c.array_area != null) v = place_array (sheet, c, v);
            else if (c.spill_values != null) clear_spill (sheet, c);
            c.value = v;
            c.gen = gen;
            return v;
        }

        public signal void spill_changed (Sheet sheet, Area area);

        public Area? spill_area (Sheet sheet, int row, int col) {
            var c = sheet.get_cell (row, col);
            if (c == null || c.formula == null) return null;
            cell_value (sheet, c);
            var a = sheet.spills[Sheet.key (row, col)];
            if (a != null) return a;
            if (c.value.is_error () && c.value.error == ErrorKind.SPILL) return null;
            return new Area.cell (sheet, row, col);
        }

        private void clear_spill (Sheet sheet, Cell c) {
            int64 k = Sheet.key (c.row, c.col);
            var old = sheet.spills[k];
            c.spill_values = null;
            if (old != null) {
                sheet.spills.unset (k);
                spill_moves.add (old);
                spill_changed (sheet, old);
            }
        }

        private Value place_array (Sheet sheet, Cell c, Value v) {
            Value[,] m;
            if (v.kind == ValueKind.ARRAY) {
                m = v.array;
            } else {
                m = new Value[1, 1];
                m[0, 0] = v;
            }
            int rows = m.length[0], cols = m.length[1];
            Area area;
            if (c.array_area != null) {
                area = c.array_area;
                var fixed_m = new Value[area.rows, area.cols];
                for (int i = 0; i < area.rows; i++) {
                    for (int j = 0; j < area.cols; j++) {
                        int ii = rows == 1 ? 0 : i, jj = cols == 1 ? 0 : j;
                        fixed_m[i, j] = ii < rows && jj < cols ? m[ii, jj] : Value.err (ErrorKind.NA);
                    }
                }
                m = fixed_m;
            } else {
                if (c.row + rows > MAX_ROWS || c.col + cols > MAX_COLS) {
                    clear_spill (sheet, c);
                    return Value.err (ErrorKind.SPILL);
                }
                area = new Area (sheet, c.row, c.col, c.row + rows - 1, c.col + cols - 1);
                bool blocked = false;
                sheet.foreach_in (area, (r, cc, cell) => {
                    if (cell != c && (cell.formula != null || cell.input != "")) blocked = true;
                });
                if (!blocked) {
                    foreach (var e in sheet.spills.entries) {
                        int64 ek = e.key;
                        if (ek != Sheet.key (c.row, c.col) && e.value.intersects (area)) blocked = true;
                    }
                }
                if (!blocked) {
                    foreach (var mg in sheet.merges) if (mg.intersects (area)) blocked = true;
                }
                if (blocked) {
                    clear_spill (sheet, c);
                    return Value.err (ErrorKind.SPILL);
                }
            }
            int64 k = Sheet.key (c.row, c.col);
            var old = sheet.spills[k];
            c.spill_values = m;
            sheet.spills[k] = area;
            if (old == null || old.r2 != area.r2 || old.c2 != area.c2) {
                var moved = old == null ? area : new Area (sheet, area.r1, area.c1, int.max (old.r2, area.r2), int.max (old.c2, area.c2));
                spill_moves.add (moved);
                spill_changed (sheet, moved);
            }
            return m[0, 0];
        }

        private CalcGraph? graph;
        private Gee.ArrayList<Area> edits = new Gee.ArrayList<Area> ();
        private bool iterating;
        private Gee.ArrayList<Area> spill_moves = new Gee.ArrayList<Area> ();
        public int last_recalc_cells;

        public void note_edit (Sheet s, int row, int col) {
            if (graph != null && !structure_changed) edits.add (new Area.cell (s, row, col));
        }

        public void note_area (Sheet s, Area a) {
            if (graph != null && !structure_changed) edits.add (new Area (s, a.r1, a.c1, a.r2, a.c2));
        }

        public bool needs_recalc {
            get { return structure_changed || graph == null || edits.size > 0; }
        }

        private void drop_stale_spills (Sheet s, Area? within, Gee.Collection<CalcGraph.Reg>? seeds) {
            var stale = new Gee.ArrayList<int64?> ();
            foreach (var e in s.spills.entries) {
                int64 k = e.key;
                if (within != null && !within.contains (Sheet.key_row (k), Sheet.key_col (k))) continue;
                var c = s.cells[k];
                if (c == null || c.formula == null) stale.add (k);
            }
            foreach (var k in stale) {
                var area = s.spills[k];
                s.spills.unset (k);
                var c = s.cells[k];
                if (c != null) c.spill_values = null;
                if (seeds != null && graph != null) graph.dependents_of_area (s, area, seeds);
            }
        }

        public void recalculate () {
            foreach (var s in sheets) drop_stale_spills (s, null, null);
            gen++;
            graph = new CalcGraph (this);
            graph.build ();
            edits.clear ();
            structure_changed = false;
            run (graph.all_regs ());
            recalculated ();
        }

        public void recalc_changed () {
            if (graph == null || structure_changed) {
                recalculate ();
                return;
            }
            var seeds = new Gee.HashSet<CalcGraph.Reg> ();
            foreach (var a in edits) {
                drop_stale_spills (a.sheet, a, seeds);
                graph.update_area (a.sheet, a);
                graph.regs_in_area (a.sheet, a, seeds);
                graph.dependents_of_area (a.sheet, a, seeds);
                foreach (var e in a.sheet.spills.entries) {
                    if (!e.value.intersects (a)) continue;
                    int64 k = e.key;
                    var reg = graph.reg_at (a.sheet, Sheet.key_row (k), Sheet.key_col (k));
                    if (reg != null) seeds.add (reg);
                }
            }
            edits.clear ();
            seeds.add_all (graph.volatile_regs ());
            run (seeds);
            recalculated ();
        }

        private void run (Gee.Collection<CalcGraph.Reg> seeds) {
            circular.clear ();
            var current = seeds;
            int total = 0;
            for (int pass = 0; pass < 6 && current.size > 0; pass++) {
                spill_moves.clear ();
                total += run_pass (current);
                if (spill_moves.size == 0) break;
                var next = new Gee.HashSet<CalcGraph.Reg> ();
                foreach (var a in spill_moves) graph.dependents_of_area (a.sheet, a, next);
                current = next;
            }
            last_recalc_cells = total;
        }

        private int run_pass (Gee.Collection<CalcGraph.Reg> seeds) {
            var queue = new Gee.ArrayList<CalcGraph.Reg> ();
            foreach (var r in seeds) {
                if (r.mark != 0) continue;
                r.mark = 1;
                queue.add (r);
            }
            var deps = new Gee.HashSet<CalcGraph.Reg> ();
            for (int qi = 0; qi < queue.size; qi++) {
                var r = queue[qi];
                r.outs = new Gee.ArrayList<CalcGraph.Reg> ();
                deps.clear ();
                graph.dependents_of (r.sheet, r.cell.row, r.cell.col, deps);
                var sa = r.sheet.spills[Sheet.key (r.cell.row, r.cell.col)];
                if (sa != null) graph.dependents_of_area (r.sheet, sa, deps);
                foreach (var d in deps) {
                    r.outs.add (d);
                    d.indeg++;
                    if (d.mark == 0) {
                        d.mark = 1;
                        queue.add (d);
                    }
                }
            }
            foreach (var r in queue) r.cell.gen = 0;
            var ready = new Gee.ArrayList<CalcGraph.Reg> ();
            foreach (var r in queue) if (r.indeg == 0) ready.add (r);
            int done = 0;
            for (int ri = 0; ri < ready.size; ri++) {
                var r = ready[ri];
                cell_value (r.sheet, r.cell);
                done++;
                foreach (var o in r.outs) {
                    o.indeg--;
                    if (o.indeg == 0) ready.add (o);
                }
            }
            if (done < queue.size) {
                var left = new Gee.ArrayList<CalcGraph.Reg> ();
                foreach (var r in queue) if (r.indeg > 0) left.add (r);
                mark_cycles (left);
                if (iterative) {
                    iterating = true;
                    for (int it = 0; it < max_iterations; it++) {
                        double delta = 0;
                        var before = new Gee.ArrayList<Value> ();
                        foreach (var r in left) before.add (r.cell.value);
                        foreach (var r in left) r.cell.gen = 0;
                        foreach (var r in left) cell_value (r.sheet, r.cell);
                        for (int i = 0; i < left.size; i++) {
                            var v0 = before[i];
                            var v1 = left[i].cell.value;
                            if (v0.kind == ValueKind.NUMBER && v1.kind == ValueKind.NUMBER) delta = double.max (delta, Math.fabs (v1.number - v0.number));
                            else if (!v0.equals (v1)) delta = double.MAX;
                        }
                        if (delta < max_change) break;
                    }
                    iterating = false;
                } else {
                    foreach (var r in left) cell_value (r.sheet, r.cell);
                }
                done += left.size;
            }
            foreach (var r in queue) {
                r.mark = 0;
                r.indeg = 0;
                r.outs = null;
            }
            return done;
        }

        private void mark_cycles (Gee.ArrayList<CalcGraph.Reg> left) {
            var members = new Gee.HashSet<CalcGraph.Reg> ();
            members.add_all (left);
            int counter = 0;
            var stack = new Gee.ArrayList<CalcGraph.Reg> ();
            foreach (var r in left) {
                r.index = -1;
                r.on_stack = false;
            }
            foreach (var root in left) {
                if (root.index >= 0) continue;
                var work = new Gee.ArrayList<CalcGraph.Reg> ();
                var pos = new Gee.ArrayList<int> ();
                work.add (root);
                pos.add (0);
                root.index = root.low = counter++;
                stack.add (root);
                root.on_stack = true;
                while (work.size > 0) {
                    var v = work[work.size - 1];
                    int i = pos[pos.size - 1];
                    if (i < v.outs.size) {
                        pos[pos.size - 1] = i + 1;
                        var w = v.outs[i];
                        if (!members.contains (w)) continue;
                        if (w.index < 0) {
                            w.index = w.low = counter++;
                            stack.add (w);
                            w.on_stack = true;
                            work.add (w);
                            pos.add (0);
                        } else if (w.on_stack) {
                            v.low = int.min (v.low, w.index);
                        }
                        continue;
                    }
                    work.remove_at (work.size - 1);
                    pos.remove_at (pos.size - 1);
                    if (work.size > 0) {
                        var parent = work[work.size - 1];
                        parent.low = int.min (parent.low, v.low);
                    }
                    if (v.low == v.index) {
                        var comp = new Gee.ArrayList<CalcGraph.Reg> ();
                        while (true) {
                            var w = stack.remove_at (stack.size - 1);
                            w.on_stack = false;
                            comp.add (w);
                            if (w == v) break;
                        }
                        bool self_loop = false;
                        foreach (var o in v.outs) if (o == v) self_loop = true;
                        if (comp.size > 1 || self_loop) {
                            foreach (var w in comp) circular.add (Address.quote_sheet (w.sheet.name) + "!" + Address.cell (w.cell.row, w.cell.col));
                        }
                    }
                }
            }
        }

        public void adjust_refs (Sheet target, bool rows, int at, int count) {
            foreach (var s in sheets) {
                foreach (var c in s.cells.values) {
                    if (c.formula == null) continue;
                    var own = s;
                    c.formula.foreach_ref ((r) => {
                        if (r.a == null) return;
                        Sheet rs = r.sheet ?? own;
                        if (rs != target) return;
                        if (rows && r.whole_rows == false && r.whole_cols) return;
                        if (!rows && r.whole_cols == false && r.whole_rows) return;
                        shift_ref (r, rows, at, count);
                    });
                    c.input = Formula.to_text (c.formula, s);
                }
            }
        }

        private static void shift_ref (Node r, bool rows, int at, int count) {
            int a1 = rows ? r.a.row : r.a.col;
            int a2 = r.b != null ? (rows ? r.b.row : r.b.col) : a1;
            int limit = rows ? MAX_ROWS : MAX_COLS;
            if (count > 0) {
                if (a1 >= at) a1 += count;
                if (a2 >= at) a2 += count;
                if (a2 >= limit) a2 = limit - 1;
                if (a1 >= limit) {
                    r.a = null;
                    r.b = null;
                    return;
                }
            } else {
                int del = -count;
                int d_end = at + del - 1;
                if (a1 >= at && a2 <= d_end) {
                    r.a = null;
                    r.b = null;
                    return;
                }
                if (a1 > d_end) a1 -= del;
                else if (a1 >= at) a1 = at;
                if (a2 > d_end) a2 -= del;
                else if (a2 >= at) a2 = at - 1;
            }
            if (rows) {
                r.a.row = a1;
                if (r.b != null) r.b.row = a2;
            } else {
                r.a.col = a1;
                if (r.b != null) r.b.col = a2;
            }
        }

        public void insert_rows (Sheet s, int at, int count) {
            move_cells (s, true, at, count);
            adjust_refs (s, true, at, count);
            structure_changed = true;
            rows_cols_changed (s, true, at, count);
        }

        public void delete_rows (Sheet s, int at, int count) {
            move_cells (s, true, at, -count);
            adjust_refs (s, true, at, -count);
            structure_changed = true;
            rows_cols_changed (s, true, at, -count);
        }

        public void insert_cols (Sheet s, int at, int count) {
            move_cells (s, false, at, count);
            adjust_refs (s, false, at, count);
            structure_changed = true;
            rows_cols_changed (s, false, at, count);
        }

        public void delete_cols (Sheet s, int at, int count) {
            move_cells (s, false, at, -count);
            adjust_refs (s, false, at, -count);
            structure_changed = true;
            rows_cols_changed (s, false, at, -count);
        }

        private void move_cells (Sheet s, bool rows, int at, int count) {
            s.comments.shift (rows, at, count);
            var moved = new Gee.HashMap<int64?, Cell> (s.cells.key_hash_func, s.cells.key_equal_func);
            foreach (var k in s.cells.keys) {
                int r = Sheet.key_row (k);
                int c = Sheet.key_col (k);
                int v = rows ? r : c;
                if (count < 0 && v >= at && v < at - count) continue;
                if (v >= at) v += count;
                if (v < 0 || v >= (rows ? MAX_ROWS : MAX_COLS)) continue;
                var cell = s.cells[k];
                if (rows) cell.row = v;
                else cell.col = v;
                moved[Sheet.key (cell.row, cell.col)] = cell;
            }
            s.cells = moved;
            var sizes = rows ? s.row_heights : s.col_widths;
            var nsizes = new Gee.HashMap<int, int> ();
            foreach (var e in sizes.entries) {
                int v = e.key;
                if (count < 0 && v >= at && v < at - count) continue;
                nsizes[v >= at ? v + count : v] = e.value;
            }
            if (rows) s.row_heights = nsizes;
            else s.col_widths = nsizes;
            var hidden = rows ? s.hidden_rows : s.hidden_cols;
            var nhidden = new Gee.HashSet<int> ();
            foreach (int v in hidden) {
                if (count < 0 && v >= at && v < at - count) continue;
                nhidden.add (v >= at ? v + count : v);
            }
            if (rows) s.hidden_rows = nhidden;
            else s.hidden_cols = nhidden;
            var nmerges = new Gee.ArrayList<Area> ();
            foreach (var m in s.merges) {
                var shifted = shift_area (m, rows, at, count);
                if (shifted != null && !shifted.is_single ()) nmerges.add (shifted);
            }
            s.merges = nmerges;
            foreach (var cf in s.cond_formats) {
                var a = shift_area (cf.area, rows, at, count);
                if (a != null) cf.area = a;
            }
            var gone = new Gee.ArrayList<TableDef> ();
            foreach (var t in tables) {
                if (t.sheet != s) continue;
                var a = shift_area (t.area, rows, at, count);
                if (a == null || a.rows < (t.header_row ? 2 : 1)) gone.add (t);
                else {
                    int old_cols = t.area.cols;
                    t.area = a;
                    if (a.cols != old_cols) t.sync_columns ();
                }
            }
            tables.remove_all (gone);
            s.spills = new Gee.HashMap<int64?, Area> (s.spills.key_hash_func, s.spills.key_equal_func);
            s.recompute_extent ();
        }

        public static Area? shift_area (Area m, bool rows, int at, int count) {
            int a1 = rows ? m.r1 : m.c1;
            int a2 = rows ? m.r2 : m.c2;
            if (count > 0) {
                if (a1 >= at) a1 += count;
                if (a2 >= at) a2 += count;
            } else {
                int del = -count;
                int d_end = at + del - 1;
                if (a1 >= at && a2 <= d_end) return null;
                if (a1 > d_end) a1 -= del;
                else if (a1 >= at) a1 = at;
                if (a2 > d_end) a2 -= del;
                else if (a2 >= at) a2 = at - 1;
            }
            return rows ? new Area (m.sheet, a1, m.c1, a2, m.c2) : new Area (m.sheet, m.r1, a1, m.r2, a2);
        }
    }
}
