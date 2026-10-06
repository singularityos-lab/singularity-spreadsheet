namespace Singularity.Apps.Spreadsheet {

    public enum ClearMode {
        ALL,
        CONTENTS,
        FORMATS,
        NOTES
    }

    public enum FileKind {
        XLSX,
        ODS,
        CSV,
        TSV,
        XLS,
        XLSB;

        public static FileKind from_path (string path) {
            string p = path.down ();
            if (p.has_suffix (".ods") || p.has_suffix (".ots") || p.has_suffix (".fods")) return ODS;
            if (p.has_suffix (".csv") || p.has_suffix (".txt")) return CSV;
            if (p.has_suffix (".tsv") || p.has_suffix (".tab")) return TSV;
            if (p.has_suffix (".xls") || p.has_suffix (".xlt")) return XLS;
            if (p.has_suffix (".xlsb")) return XLSB;
            return XLSX;
        }

        public static bool is_template (string path) {
            string p = path.down ();
            return p.has_suffix (".xltx") || p.has_suffix (".xltm") || p.has_suffix (".ots") || p.has_suffix (".xlt");
        }

        public static string[] suffixes () {
            return { "xlsx", "xlsm", "xlsb", "xltx", "xltm", "xls", "xlt", "ods", "ots", "fods", "csv", "tsv", "txt", "tab" };
        }

        public static bool saveable (string path) {
            string p = path.down ();
            foreach (string s in new string[] { ".xlsx", ".xlsm", ".xltx", ".xltm", ".ods", ".ots", ".fods", ".xls", ".xlsb" }) {
                if (p.has_suffix (s)) return true;
            }
            return false;
        }
    }

    public class CellCopy {
        public int row;
        public int col;
        public string input;
        public Node? formula;
        public Value value;
        public int style;
        public string note;
        public string link;
        public string note_author;
        public bool legacy;
        public Area? array_area;

        public CellCopy.of (Cell c) {
            row = c.row;
            col = c.col;
            input = c.input;
            formula = c.formula != null ? c.formula.copy () : null;
            value = c.value;
            style = c.style;
            note = c.note;
            link = c.link;
            note_author = c.note_author;
            legacy = c.legacy;
            array_area = c.array_area != null ? c.array_area.copy () : null;
        }

        public Cell restore () {
            var c = new Cell ();
            c.row = row;
            c.col = col;
            c.input = input;
            c.formula = formula != null ? formula.copy () : null;
            c.value = value;
            c.style = style;
            c.note = note;
            c.link = link;
            c.note_author = note_author;
            c.legacy = legacy;
            c.array_area = array_area != null ? array_area.copy () : null;
            return c;
        }
    }

    public class SheetState {
        public Sheet sheet;
        public string name;
        public Gee.ArrayList<CellCopy> cells = new Gee.ArrayList<CellCopy> ();
        public Gee.HashMap<int, int> col_widths;
        public Gee.HashMap<int, int> row_heights;
        public Gee.HashSet<int> hidden_rows;
        public Gee.HashSet<int> hidden_cols;
        public Gee.ArrayList<Area> merges;
        public Gee.ArrayList<CondFormat> cond_formats;
        public Gee.ArrayList<Validation> validations;
        public Gee.ArrayList<Chart> charts;
        public Gee.ArrayList<Drawing> drawings;
        public Gee.ArrayList<SparklineGroup> sparklines;
        public Filter? filter;
        public int freeze_rows;
        public int freeze_cols;
        public string tab_color;
        public int visibility;
        public bool show_grid;
        public PageSetup page;
        public SheetProtection? protection;
        public Outline outline;
        public Gee.ArrayList<CustomView> views;
        public Gee.HashMap<string, string> local_names;
        public CommentStore comments;

        public SheetState (Sheet s) {
            sheet = s;
            name = s.name;
            foreach (var c in s.cells.values) cells.add (new CellCopy.of (c));
            col_widths = new Gee.HashMap<int, int> ();
            foreach (var e in s.col_widths.entries) col_widths[e.key] = e.value;
            row_heights = new Gee.HashMap<int, int> ();
            foreach (var e in s.row_heights.entries) row_heights[e.key] = e.value;
            hidden_rows = new Gee.HashSet<int> ();
            hidden_rows.add_all (s.hidden_rows);
            hidden_cols = new Gee.HashSet<int> ();
            hidden_cols.add_all (s.hidden_cols);
            merges = new Gee.ArrayList<Area> ();
            foreach (var m in s.merges) merges.add (m.copy ());
            cond_formats = new Gee.ArrayList<CondFormat> ();
            cond_formats.add_all (s.cond_formats);
            validations = new Gee.ArrayList<Validation> ();
            validations.add_all (s.validations);
            charts = new Gee.ArrayList<Chart> ();
            foreach (var ch in s.charts) charts.add (ch.copy ());
            drawings = new Gee.ArrayList<Drawing> ();
            foreach (var d in s.drawings) drawings.add (d.copy ());
            sparklines = new Gee.ArrayList<SparklineGroup> ();
            foreach (var g in s.sparklines) sparklines.add (g.copy ());
            filter = s.filter;
            freeze_rows = s.freeze_rows;
            freeze_cols = s.freeze_cols;
            tab_color = s.tab_color;
            visibility = s.visibility;
            show_grid = s.show_grid;
            page = s.page.copy ();
            protection = s.protection != null ? s.protection.copy () : null;
            outline = s.outline.copy ();
            views = new Gee.ArrayList<CustomView> ();
            views.add_all (s.views);
            local_names = new Gee.HashMap<string, string> ();
            foreach (var e in s.names.entries) local_names[e.key] = e.value;
            comments = s.comments.copy ();
        }

        public void apply () {
            var s = sheet;
            s.name = name;
            s.names = new Gee.HashMap<string, string> ();
            foreach (var e in local_names.entries) s.names[e.key] = e.value;
            s.cells.clear ();
            foreach (var c in cells) s.cells[Sheet.key (c.row, c.col)] = c.restore ();
            s.col_widths = new Gee.HashMap<int, int> ();
            foreach (var e in col_widths.entries) s.col_widths[e.key] = e.value;
            s.row_heights = new Gee.HashMap<int, int> ();
            foreach (var e in row_heights.entries) s.row_heights[e.key] = e.value;
            s.hidden_rows = new Gee.HashSet<int> ();
            s.hidden_rows.add_all (hidden_rows);
            s.hidden_cols = new Gee.HashSet<int> ();
            s.hidden_cols.add_all (hidden_cols);
            s.merges = new Gee.ArrayList<Area> ();
            foreach (var m in merges) s.merges.add (m.copy ());
            s.cond_formats = new Gee.ArrayList<CondFormat> ();
            s.cond_formats.add_all (cond_formats);
            s.validations = new Gee.ArrayList<Validation> ();
            s.validations.add_all (validations);
            s.charts = new Gee.ArrayList<Chart> ();
            foreach (var ch in charts) s.charts.add (ch.copy ());
            s.drawings = new Gee.ArrayList<Drawing> ();
            foreach (var d in drawings) s.drawings.add (d.copy ());
            s.sparklines = new Gee.ArrayList<SparklineGroup> ();
            foreach (var g in sparklines) s.sparklines.add (g.copy ());
            s.filter = filter;
            s.freeze_rows = freeze_rows;
            s.freeze_cols = freeze_cols;
            s.tab_color = tab_color;
            s.visibility = visibility;
            s.show_grid = show_grid;
            s.page = page.copy ();
            s.protection = protection != null ? protection.copy () : null;
            s.outline = outline.copy ();
            s.views = new Gee.ArrayList<CustomView> ();
            s.views.add_all (views);
            s.comments = comments.copy ();
            s.recompute_extent ();
        }
    }

    public class Snapshot {
        public Sheet? sheet;
        public Area? area;
        public Gee.ArrayList<CellCopy> cells;
        public Gee.ArrayList<Sheet>? order;
        public Gee.ArrayList<SheetState>? states;
        public Gee.HashMap<string, string>? names;
        public Gee.ArrayList<TableDef>? tables;
        public BookProtection? book_protection;
        public DocTheme? theme;

        public static Snapshot of_area (Sheet sheet, Area area) {
            var s = new Snapshot ();
            s.sheet = sheet;
            s.area = area.copy ();
            s.cells = new Gee.ArrayList<CellCopy> ();
            sheet.foreach_in (area, (r, c, cell) => s.cells.add (new CellCopy.of (cell)));
            return s;
        }

        public static Snapshot of_book (Workbook book) {
            var s = new Snapshot ();
            s.order = new Gee.ArrayList<Sheet> ();
            s.order.add_all (book.sheets);
            s.states = new Gee.ArrayList<SheetState> ();
            foreach (var sh in book.sheets) s.states.add (new SheetState (sh));
            s.names = new Gee.HashMap<string, string> ();
            foreach (var e in book.names.entries) s.names[e.key] = e.value;
            s.book_protection = book.protection != null ? book.protection.copy () : null;
            s.theme = book.theme.copy ();
            s.tables = new Gee.ArrayList<TableDef> ();
            foreach (var t in book.tables) s.tables.add (t.copy ());
            return s;
        }

        public void restore (Workbook book) {
            if (order != null) {
                book.sheets.clear ();
                book.sheets.add_all (order);
                foreach (var st in states) st.apply ();
                book.names.clear ();
                foreach (var e in names.entries) book.names[e.key] = e.value;
                if (tables != null) {
                    book.tables.clear ();
                    foreach (var t in tables) book.tables.add (t.copy ());
                }
                book.protection = book_protection != null ? book_protection.copy () : null;
                if (theme != null) book.theme = theme.copy ();
            } else {
                var keys = new Gee.ArrayList<int64?> ();
                foreach (var k in sheet.cells.keys) if (area.contains (Sheet.key_row (k), Sheet.key_col (k))) keys.add (k);
                foreach (var k in keys) sheet.cells.unset (k);
                foreach (var c in cells) sheet.cells[Sheet.key (c.row, c.col)] = c.restore ();
                sheet.recompute_extent ();
                return;
            }
            book.structure_changed = true;
        }
    }

    public class UndoStep {
        public string label;
        public Snapshot before;
        public Snapshot after;
        public Sheet? sheet;
        public Area? selection;
    }

    public class Clip {
        public Area source;
        public Sheet sheet;
        public Gee.ArrayList<CellCopy> cells = new Gee.ArrayList<CellCopy> ();
        public Gee.ArrayList<Area> merges = new Gee.ArrayList<Area> ();
        public bool cut;
        public string text = "";
    }

    public class SortKey {
        public int col;
        public bool ascending = true;

        public SortKey (int col, bool ascending) {
            this.col = col;
            this.ascending = ascending;
        }
    }

    public class Document : Object {
        public Workbook book { get; private set; }
        public XlsWriter? last_xls;
        public XlsbWriter? last_xlsb;
        public string? path { get; set; }
        public bool modified { get; set; }
        public Clip? clip;
        private Gee.ArrayList<UndoStep> undo_stack = new Gee.ArrayList<UndoStep> ();
        private Gee.ArrayList<UndoStep> redo_stack = new Gee.ArrayList<UndoStep> ();
        private UndoStep? pending;

        public signal void changed ();
        public signal void committed (UndoStep step);
        public signal void reverting (UndoStep step, bool redo);
        public signal void sheets_changed ();
        public signal void restored (Sheet? sheet, Area? selection);

        public Document () {
            book = new Workbook ();
            book.add_sheet ();
            ReviewTracker.attach (this);
        }

        public Document.with_book (Workbook book, string? path) {
            this.book = book;
            this.path = path;
            ReviewTracker.attach (this);
        }

        public static Document open (string path) throws Error {
            Workbook book;
            uint8[] head = new uint8[8];
            try {
                var stream = File.new_for_path (path).read ();
                stream.read (head);
                stream.close ();
            } catch (Error e) {
            }
            var kind = FileKind.from_path (path);
            if (Cfb.sniff_head (head) && OfficeCrypto.is_encrypted_file (path)) {
                try {
                    var d = open_with_password (path, "VelvetSweatshop");
                    d.encrypt_password = null;
                    return d;
                } catch (Error e) {
                }
                throw new CryptoError.PASSWORD_REQUIRED (_("The file is protected with a password"));
            }
            if (Cfb.sniff_head (head)) kind = FileKind.XLS;
            else if (head[0] == 'P' && head[1] == 'K' && kind == FileKind.XLS) kind = FileKind.XLSX;
            switch (kind) {
                case FileKind.ODS: book = Ods.load (path); break;
                case FileKind.CSV: case FileKind.TSV: book = Csv.load (path); break;
                case FileKind.XLS: book = Xls.load (path); break;
                case FileKind.XLSB: book = Xlsb.load (path); break;
                default: book = Xlsx.load (path); break;
            }
            book.ensure_vba ();
            bool keep = (kind == FileKind.XLSX || kind == FileKind.ODS || kind == FileKind.XLS || kind == FileKind.XLSB) && FileKind.saveable (path) && !FileKind.is_template (path);
            return new Document.with_book (book, keep ? path : null);
        }

        public string? encrypt_password;

        public static Document open_with_password (string path, string password) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            var plain = OfficeCrypto.decrypt (data, password);
            var reader = new Xlsx ();
            var d = new Document.with_book (reader.read (plain), FileKind.saveable (path) ? path : null);
            d.encrypt_password = password;
            return d;
        }

        public void save_to (string target, Sheet active) throws Error {
            switch (FileKind.from_path (target)) {
                case FileKind.ODS:
                    Ods.save (book, target);
                    break;
                case FileKind.CSV:
                    Csv.save (active, target, ',');
                    return;
                case FileKind.TSV:
                    Csv.save (active, target, '\t');
                    return;
                case FileKind.XLS:
                    last_xls = XlsWriter.save (book, target);
                    break;
                case FileKind.XLSB:
                    last_xlsb = XlsbWriter.save (book, target);
                    break;
                default:
                    XlsxWriter.save (book, target);
                    if (encrypt_password != null && encrypt_password != "") {
                        uint8[] plain;
                        FileUtils.get_data (target, out plain);
                        FileUtils.set_data (target, OfficeCrypto.encrypt (plain, encrypt_password));
                    }
                    break;
            }
            path = target;
            modified = false;
        }

        public bool can_undo {
            get { return undo_stack.size > 0; }
        }

        public bool can_redo {
            get { return redo_stack.size > 0; }
        }

        public string undo_label {
            owned get { return undo_stack.size > 0 ? undo_stack[undo_stack.size - 1].label : ""; }
        }

        public string redo_label {
            owned get { return redo_stack.size > 0 ? redo_stack[redo_stack.size - 1].label : ""; }
        }

        public void begin_area (string label, Sheet sheet, Area area, Area? selection = null) {
            pending = new UndoStep ();
            pending.label = label;
            pending.sheet = sheet;
            pending.selection = selection ?? area;
            pending.before = Snapshot.of_area (sheet, area);
        }

        public void begin_book (string label, Sheet? sheet = null, Area? selection = null) {
            pending = new UndoStep ();
            pending.label = label;
            pending.sheet = sheet;
            pending.selection = selection;
            pending.before = Snapshot.of_book (book);
        }

        public void commit () {
            if (pending == null) return;
            if (pending.before.order != null) pending.after = Snapshot.of_book (book);
            else pending.after = Snapshot.of_area (pending.sheet, pending.before.area);
            undo_stack.add (pending);
            if (undo_stack.size > 200) undo_stack.remove_at (0);
            redo_stack.clear ();
            var done_step = pending;
            pending = null;
            modified = true;
            recalc_step (done_step, done_step.before);
            committed (done_step);
            changed ();
        }

        public void undo () {
            if (undo_stack.size == 0) return;
            var step = undo_stack.remove_at (undo_stack.size - 1);
            reverting (step, false);
            step.before.restore (book);
            redo_stack.add (step);
            modified = true;
            recalc_step (step, step.before);
            if (step.before.order != null) sheets_changed ();
            restored (step.sheet, step.selection);
            changed ();
        }

        public void redo () {
            if (redo_stack.size == 0) return;
            var step = redo_stack.remove_at (redo_stack.size - 1);
            reverting (step, true);
            step.after.restore (book);
            undo_stack.add (step);
            modified = true;
            recalc_step (step, step.after);
            if (step.before.order != null) sheets_changed ();
            restored (step.sheet, step.selection);
            changed ();
        }

        private void recalc_step (UndoStep step, Snapshot snap) {
            if (snap.order != null || snap.area == null || step.sheet == null) book.structure_changed = true;
            else book.note_area (step.sheet, snap.area);
            if (!book.manual_calc) book.recalc_changed ();
        }

        public void calculate_now () {
            book.recalc_changed ();
            changed ();
        }

        public void calculate_full () {
            book.recalculate ();
            changed ();
        }

        public signal void array_locked (Sheet s, int row, int col);

        public bool in_fixed_array (Sheet s, int row, int col) {
            var anchor = s.spill_anchor_at (row, col);
            return anchor != null && anchor.array_area != null && (anchor.row != row || anchor.col != col);
        }

        public Gee.ArrayList<Sheet> group = new Gee.ArrayList<Sheet> ();

        public bool grouped (Sheet s) {
            return group.size > 1 && group.contains (s);
        }

        public void set_input (Sheet s, int row, int col, string text) {
            if (grouped (s)) {
                begin_book (_("Typing"), s, new Area.cell (s, row, col));
                foreach (var g in group) if (book.sheets.contains (g)) g.set_input (row, col, text);
                commit ();
                return;
            }
            if (s.input_at (row, col) == text) return;
            if (s.spills.size > 0 && in_fixed_array (s, row, col)) {
                array_locked (s, row, col);
                return;
            }
            if (book.tables.size > 0 && (TableCommands.auto_expand (this, s, row, col, text) || TableCommands.fill_calculated (this, s, row, col, text))) return;
            begin_area (_("Typing"), s, new Area.cell (s, row, col));
            s.set_input (row, col, text);
            commit ();
        }

        public void set_array_formula (Sheet s, Area area, string text) {
            begin_area (_("Array Formula"), s, area);
            for (int r = area.r1; r <= area.r2; r++) {
                for (int c = area.c1; c <= area.c2; c++) {
                    if (r == area.r1 && c == area.c1) continue;
                    if (s.get_cell (r, c) != null) s.set_input (r, c, "");
                }
            }
            s.set_input (area.r1, area.c1, text);
            var cell = s.get_cell (area.r1, area.c1);
            if (cell != null && cell.formula != null) cell.array_area = area.is_single () ? null : area.copy ();
            book.structure_changed = true;
            commit ();
        }

        public void fill_input (Sheet s, Area area, string text) {
            begin_area (_("Typing"), s, area);
            Node? base_node = null;
            if (text.has_prefix ("=")) {
                try {
                    base_node = Formula.parse (text, book, s);
                } catch (FormulaError e) {
                }
            }
            for (int r = area.r1; r <= area.r2; r++) {
                for (int c = area.c1; c <= area.c2; c++) {
                    if (base_node != null) s.set_input (r, c, Formula.to_text (Formula.shifted (base_node, r - area.r1, c - area.c1), s));
                    else s.set_input (r, c, text);
                }
            }
            commit ();
        }

        public static Area clamp_area (Sheet s, Area a) {
            int r2 = a.r2, c2 = a.c2;
            if (a.r2 == MAX_ROWS - 1) r2 = int.max (a.r1, int.max (s.max_row, a.r1 + 199));
            if (a.c2 == MAX_COLS - 1) c2 = int.max (a.c1, int.max (s.max_col, a.c1 + 25));
            return new Area (s, a.r1, a.c1, r2, c2);
        }

        public delegate void StyleEdit (CellStyle style);

        public void edit_style (Sheet s, Area selection, string label, StyleEdit edit) {
            var area = clamp_area (s, selection);
            if (grouped (s)) {
                begin_book (label, s, selection);
                foreach (var g in group) {
                    if (!book.sheets.contains (g)) continue;
                    var gcache = new Gee.HashMap<int, int> ();
                    for (int r = area.r1; r <= area.r2; r++) {
                        for (int c = area.c1; c <= area.c2; c++) {
                            var gcell = g.get_cell (r, c);
                            int gold = gcell != null ? gcell.style : 0;
                            if (!gcache.has_key (gold)) {
                                var gst = book.styles[gold].copy ();
                                edit (gst);
                                gcache[gold] = book.intern (gst);
                            }
                            g.set_style (r, c, gcache[gold]);
                        }
                    }
                }
                commit ();
                return;
            }
            begin_area (label, s, area, selection);
            var cache = new Gee.HashMap<int, int> ();
            for (int r = area.r1; r <= area.r2; r++) {
                for (int c = area.c1; c <= area.c2; c++) {
                    var cell = s.get_cell (r, c);
                    int old = cell != null ? cell.style : 0;
                    if (!cache.has_key (old)) {
                        var st = book.styles[old].copy ();
                        edit (st);
                        cache[old] = book.intern (st);
                    }
                    s.set_style (r, c, cache[old]);
                }
            }
            commit ();
        }

        public void edit_borders (Sheet s, Area selection, string which, BorderStyle bs, string color) {
            var area = clamp_area (s, selection);
            begin_area (_("Borders"), s, new Area (s, int.max (area.r1 - 1, 0), int.max (area.c1 - 1, 0), area.r2 + 1, area.c2 + 1), selection);
            for (int r = area.r1; r <= area.r2; r++) {
                for (int c = area.c1; c <= area.c2; c++) {
                    var cell = s.get_cell (r, c);
                    var st = book.styles[cell != null ? cell.style : 0].copy ();
                    var b = new Border (bs, color);
                    var none = new Border ();
                    bool top = r == area.r1, bottom = r == area.r2, left = c == area.c1, right = c == area.c2;
                    switch (which) {
                        case "all":
                            st.top = b; st.bottom = b; st.left = b; st.right = b;
                            break;
                        case "outer":
                            if (top) st.top = b;
                            if (bottom) st.bottom = b;
                            if (left) st.left = b;
                            if (right) st.right = b;
                            break;
                        case "inner":
                            if (!top) st.top = b;
                            if (!bottom) st.bottom = b;
                            if (!left) st.left = b;
                            if (!right) st.right = b;
                            break;
                        case "top":
                            if (top) st.top = b;
                            break;
                        case "bottom":
                            if (bottom) st.bottom = b;
                            break;
                        case "left":
                            if (left) st.left = b;
                            break;
                        case "right":
                            if (right) st.right = b;
                            break;
                        case "none":
                            st.top = none; st.bottom = none; st.left = none; st.right = none;
                            break;
                    }
                    s.set_style (r, c, book.intern (st));
                }
            }
            commit ();
        }

        public void clear (Sheet s, Area selection, ClearMode mode) {
            var area = clamp_area (s, selection);
            begin_area (_("Clear"), s, area, selection);
            var keys = new Gee.ArrayList<int64?> ();
            s.foreach_in (area, (r, c, cell) => keys.add (Sheet.key (r, c)));
            foreach (var k in keys) {
                var cell = s.cells[k];
                if (mode == ClearMode.ALL || mode == ClearMode.CONTENTS) {
                    cell.input = "";
                    cell.formula = null;
                    cell.value = Value.empty ();
                }
                if (mode == ClearMode.ALL || mode == ClearMode.FORMATS) cell.style = 0;
                if (mode == ClearMode.ALL || mode == ClearMode.NOTES) cell.note = "";
                if (mode == ClearMode.ALL || mode == ClearMode.CONTENTS) cell.link = "";
                if (cell.is_blank ()) s.cells.unset (k);
            }
            s.recompute_extent ();
            book.structure_changed = true;
            commit ();
        }

        public void copy (Sheet s, Area area, bool cut) {
            var cl = new Clip ();
            cl.sheet = s;
            cl.source = area.copy ();
            cl.cut = cut;
            s.foreach_in (area, (r, c, cell) => cl.cells.add (new CellCopy.of (cell)));
            foreach (var m in s.merges) if (area.contains (m.r1, m.c1) && area.contains (m.r2, m.c2)) cl.merges.add (m.copy ());
            var sb = new StringBuilder ();
            var a = clamp_area (s, area);
            for (int r = a.r1; r <= int.min (a.r2, s.max_row); r++) {
                if (s.hidden_rows.contains (r)) continue;
                for (int c = a.c1; c <= int.min (a.c2, s.max_col); c++) {
                    if (c > a.c1) sb.append_c ('\t');
                    string color;
                    var v = s.value_at (r, c);
                    string t = NumberFormat.format_value (v, s.style_at (r, c).number_format, out color, book.date1904);
                    if (t.contains ("\t") || t.contains ("\n") || t.contains ("\"")) t = "\"" + t.replace ("\"", "\"\"") + "\"";
                    sb.append (t);
                }
                sb.append_c ('\n');
            }
            cl.text = sb.str;
            clip = cl;
        }

        public enum PasteMode {
            ALL,
            VALUES,
            FORMATS,
            FORMULAS,
            TRANSPOSE
        }

        public Area? paste (Sheet s, int row, int col, PasteMode mode = PasteMode.ALL, Area? target = null) {
            if (clip == null) return null;
            var src = clip.source;
            bool transpose = mode == PasteMode.TRANSPOSE;
            int rows = transpose ? src.cols : src.rows;
            int cols = transpose ? src.rows : src.cols;
            if (src.r2 == MAX_ROWS - 1) rows = transpose ? rows : int.max (clip.sheet.max_row - src.r1 + 1, 1);
            if (src.c2 == MAX_COLS - 1) cols = transpose ? cols : int.max (clip.sheet.max_col - src.c1 + 1, 1);
            int rep_r = 1, rep_c = 1;
            if (target != null && !transpose) {
                if (target.rows % rows == 0) rep_r = target.rows / rows;
                if (target.cols % cols == 0) rep_c = target.cols / cols;
            }
            var dest = new Area (s, row, col, int.min (row + rows * rep_r - 1, MAX_ROWS - 1), int.min (col + cols * rep_c - 1, MAX_COLS - 1));
            if (clip.cut) {
                begin_book (_("Paste"), s, dest);
            } else {
                begin_area (_("Paste"), s, dest);
            }
            var values = new Gee.HashMap<int64?, Value> (s.cells.key_hash_func, s.cells.key_equal_func);
            if (mode == PasteMode.VALUES) {
                foreach (var cc in clip.cells) {
                    var cell = clip.sheet.get_cell (cc.row, cc.col);
                    values[Sheet.key (cc.row, cc.col)] = cell != null ? book.cell_value (clip.sheet, cell) : cc.value;
                }
            }
            if (clip.cut && clip.sheet == s) {
                foreach (var cc in clip.cells) {
                    var k = Sheet.key (cc.row, cc.col);
                    if (s.cells.has_key (k)) s.cells.unset (k);
                }
            }
            for (int rr = 0; rr < rep_r; rr++) {
                for (int rc = 0; rc < rep_c; rc++) {
                    int base_r = row + rr * rows;
                    int base_c = col + rc * cols;
                    for (int r = base_r; r < base_r + rows && r < MAX_ROWS; r++) {
                        for (int c = base_c; c < base_c + cols && c < MAX_COLS; c++) {
                            if (mode != PasteMode.FORMATS) {
                                var existing = s.get_cell (r, c);
                                if (existing != null) {
                                    existing.input = "";
                                    existing.formula = null;
                                    existing.value = Value.empty ();
                                    if (mode == PasteMode.ALL || mode == PasteMode.TRANSPOSE) existing.style = 0;
                                }
                            }
                        }
                    }
                    foreach (var cc in clip.cells) {
                        int dr = cc.row - src.r1;
                        int dc = cc.col - src.c1;
                        int r = base_r + (transpose ? dc : dr);
                        int c = base_c + (transpose ? dr : dc);
                        if (r >= MAX_ROWS || c >= MAX_COLS) continue;
                        var cell = s.ensure (r, c);
                        switch (mode) {
                            case PasteMode.VALUES:
                                var v = values[Sheet.key (cc.row, cc.col)];
                                cell.formula = null;
                                cell.value = v;
                                cell.input = v.kind == ValueKind.NUMBER ? Value.format_number_general_full (v.number) : (v.kind == ValueKind.TEXT && Input.parse (v.text).value.kind != ValueKind.TEXT ? "'" + v.text : v.display ());
                                if (cell.style == 0) cell.style = cc.style;
                                else {
                                    var st = book.styles[cell.style].copy ();
                                    st.number_format = book.styles[cc.style].number_format;
                                    cell.style = book.intern (st);
                                }
                                break;
                            case PasteMode.FORMATS:
                                cell.style = cc.style;
                                break;
                            default:
                                if (cc.formula != null) {
                                    var node = clip.cut ? cc.formula.copy () : Formula.shifted (cc.formula, r - cc.row, c - cc.col);
                                    cell.formula = node;
                                    cell.input = Formula.to_text (node, s);
                                } else {
                                    cell.formula = null;
                                    cell.input = cc.input;
                                    cell.value = cc.value;
                                }
                                if (mode != PasteMode.FORMULAS) {
                                    cell.style = cc.style;
                                    cell.note = cc.note;
                                    cell.link = cc.link;
                                }
                                break;
                        }
                        if (r > s.max_row) s.max_row = r;
                        if (c > s.max_col) s.max_col = c;
                    }
                    if (mode == PasteMode.ALL) {
                        foreach (var m in clip.merges) {
                            var nm = new Area (s, m.r1 - src.r1 + base_r, m.c1 - src.c1 + base_c, m.r2 - src.r1 + base_r, m.c2 - src.c1 + base_c);
                            s.merges.add (nm);
                        }
                    }
                }
            }
            if (clip.cut) {
                if (clip.sheet != s) {
                    foreach (var cc in clip.cells) clip.sheet.cells.unset (Sheet.key (cc.row, cc.col));
                    clip.sheet.recompute_extent ();
                }
                retarget_refs (clip.sheet, src, s, row - src.r1, col - src.c1);
                clip = null;
            }
            s.recompute_extent ();
            book.structure_changed = true;
            commit ();
            return dest;
        }

        private void retarget_refs (Sheet from, Area src, Sheet to, int dr, int dc) {
            foreach (var sh in book.sheets) {
                foreach (var cell in sh.cells.values) {
                    if (cell.formula == null) continue;
                    var own = sh;
                    bool touched = false;
                    cell.formula.foreach_ref ((n) => {
                        if (n.a == null) return;
                        Sheet target = n.sheet ?? own;
                        if (target != from) return;
                        var a = n.to_area (own);
                        if (!(src.contains (a.r1, a.c1) && src.contains (a.r2, a.c2))) return;
                        n.a.row += dr;
                        n.a.col += dc;
                        if (n.b != null) {
                            n.b.row += dr;
                            n.b.col += dc;
                        }
                        if (to != own) n.sheet = to;
                        else if (n.sheet != null && to == own) n.sheet = null;
                        touched = true;
                    });
                    if (touched) cell.input = Formula.to_text (cell.formula, sh);
                }
            }
        }

        public void paste_text (Sheet s, int row, int col, string text) {
            char sep = text.contains ("\t") ? '\t' : Csv.detect (text);
            var rows = Csv.parse (text, sep);
            int maxc = 0;
            foreach (var r in rows) maxc = int.max (maxc, r.size);
            if (rows.size == 0 || maxc == 0) return;
            var dest = new Area (s, row, col, int.min (row + rows.size - 1, MAX_ROWS - 1), int.min (col + maxc - 1, MAX_COLS - 1));
            begin_area (_("Paste"), s, dest);
            for (int i = 0; i < rows.size; i++) {
                for (int j = 0; j < rows[i].size; j++) {
                    if (row + i >= MAX_ROWS || col + j >= MAX_COLS) continue;
                    s.set_input (row + i, col + j, rows[i][j]);
                }
            }
            commit ();
        }

        private static string[] series_lists () {
            string[] lists = {};
            var months = new StringBuilder ();
            var short_months = new StringBuilder ();
            for (int m = 1; m <= 12; m++) {
                var dt = new DateTime.local (2024, m, 1, 0, 0, 0);
                months.append ((m > 1 ? "|" : "") + dt.format ("%B"));
                short_months.append ((m > 1 ? "|" : "") + dt.format ("%b"));
            }
            var days = new StringBuilder ();
            var short_days = new StringBuilder ();
            for (int d = 0; d < 7; d++) {
                var dt = new DateTime.local (2024, 1, 1 + d, 0, 0, 0);
                days.append ((d > 0 ? "|" : "") + dt.format ("%A"));
                short_days.append ((d > 0 ? "|" : "") + dt.format ("%a"));
            }
            lists += months.str;
            lists += short_months.str;
            lists += days.str;
            lists += short_days.str;
            lists += "January|February|March|April|May|June|July|August|September|October|November|December";
            lists += "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec";
            lists += "Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday";
            lists += "Mon|Tue|Wed|Thu|Fri|Sat|Sun";
            lists += "Q1|Q2|Q3|Q4";
            return lists;
        }

        private static bool split_trailing_number (string s, out string prefix, out int64 number, out int width) {
            prefix = "";
            number = 0;
            width = 0;
            int i = s.length;
            while (i > 0 && s[i - 1].isdigit ()) i--;
            if (i == s.length || i == 0) return false;
            prefix = s.substring (0, i);
            width = s.length - i;
            number = int64.parse (s.substring (i));
            return true;
        }

        public void fill_series (Sheet s, Area source, Area target) {
            begin_area (_("Fill"), s, target);
            bool vertical = target.cols == source.cols && (target.r2 > source.r2 || target.r1 < source.r1);
            bool backwards = vertical ? target.r1 < source.r1 : target.c1 < source.c1;
            int lanes = vertical ? source.cols : source.rows;
            int len = vertical ? source.rows : source.cols;
            string[] lists = series_lists ();
            foreach (string ul in CustomLists.user ()) lists += ul;
            foreach (string ul in book.custom_lists) lists += ul;
            for (int lane = 0; lane < lanes; lane++) {
                var cells = new Cell?[len];
                var vals = new Value[len];
                for (int k = 0; k < len; k++) {
                    int r = vertical ? source.r1 + k : source.r1 + lane;
                    int c = vertical ? source.c1 + lane : source.c1 + k;
                    cells[k] = s.get_cell (r, c);
                    vals[k] = cells[k] != null && cells[k].formula == null ? cells[k].value : Value.empty ();
                }
                bool all_numbers = true;
                foreach (var v in vals) if (v.kind != ValueKind.NUMBER) all_numbers = false;
                double step = 0, start_v = 0;
                bool linear = false;
                if (all_numbers && len >= 2) {
                    double n = len, sx = 0, sy = 0, sxy = 0, sxx = 0;
                    for (int k = 0; k < len; k++) {
                        sx += k;
                        sy += vals[k].number;
                        sxy += k * vals[k].number;
                        sxx += k * k;
                    }
                    step = (n * sxy - sx * sy) / (n * sxx - sx * sx);
                    start_v = (sy - step * sx) / n;
                    linear = true;
                } else if (all_numbers && len == 1) {
                    bool is_date = NumberFormat.is_date_format (book.styles[cells[0] != null ? cells[0].style : 0].number_format);
                    step = is_date ? 1 : 0;
                    start_v = vals[0].number;
                    linear = is_date;
                }
                string? list_hit = null;
                int list_index = 0;
                if (!all_numbers && cells[0] != null && vals[0].kind == ValueKind.TEXT) {
                    foreach (string l in lists) {
                        string[] items = l.split ("|");
                        for (int i = 0; i < items.length; i++) {
                            if (items[i].casefold () == vals[0].text.casefold ()) {
                                list_hit = l;
                                list_index = i;
                                break;
                            }
                        }
                        if (list_hit != null) break;
                    }
                }
                string prefix = "";
                int64 number = 0;
                int width = 0;
                bool text_number = !all_numbers && len >= 1 && vals[len - 1].kind == ValueKind.TEXT && split_trailing_number (vals[len - 1].text, out prefix, out number, out width);
                int64 text_step = 1;
                if (text_number && len >= 2 && vals[len - 2].kind == ValueKind.TEXT) {
                    string p2;
                    int64 n2;
                    int w2;
                    if (split_trailing_number (vals[len - 2].text, out p2, out n2, out w2) && p2 == prefix) text_step = number - n2;
                }
                int total = vertical ? target.rows : target.cols;
                for (int t = 0; t < total; t++) {
                    int r = vertical ? target.r1 + t : target.r1 + lane;
                    int c = vertical ? target.c1 + lane : target.c1 + t;
                    if (source.contains (r, c)) continue;
                    int offset = vertical ? r - source.r1 : c - source.c1;
                    int k = ((offset % len) + len) % len;
                    var src_cell = cells[k];
                    int src_r = vertical ? source.r1 + k : source.r1 + lane;
                    int src_c = vertical ? source.c1 + lane : source.c1 + k;
                    int style = src_cell != null ? src_cell.style : 0;
                    if (src_cell != null && src_cell.formula != null) {
                        var node = Formula.shifted (src_cell.formula, r - src_r, c - src_c);
                        var cell = s.ensure (r, c);
                        cell.formula = node;
                        cell.input = Formula.to_text (node, s);
                        cell.style = style;
                    } else if (linear) {
                        double v = start_v + step * offset;
                        var cell = s.ensure (r, c);
                        cell.formula = null;
                        cell.value = Value.num (v);
                        cell.input = Value.format_number_general_full (v);
                        cell.style = style;
                    } else if (list_hit != null && len == 1) {
                        string[] items = list_hit.split ("|");
                        int idx = ((list_index + offset) % items.length + items.length) % items.length;
                        string item = items[idx];
                        if (vals[0].text == vals[0].text.up ()) item = item.up ();
                        s.set_input (r, c, item);
                        s.ensure (r, c).style = style;
                    } else if (text_number && k == len - 1 || (text_number && len == 1)) {
                        int64 v = number + text_step * (backwards ? offset - (len - 1) : offset - (len - 1));
                        string digits = v.abs ().to_string ();
                        while (digits.length < width) digits = "0" + digits;
                        s.set_input (r, c, prefix + (v < 0 ? "-" : "") + digits);
                        s.ensure (r, c).style = style;
                    } else if (src_cell != null) {
                        var cell = s.ensure (r, c);
                        cell.formula = null;
                        cell.input = src_cell.input;
                        cell.value = src_cell.value;
                        cell.style = style;
                    } else {
                        var existing = s.get_cell (r, c);
                        if (existing != null) s.cells.unset (Sheet.key (r, c));
                    }
                    if (r > s.max_row) s.max_row = r;
                    if (c > s.max_col) s.max_col = c;
                }
            }
            book.structure_changed = true;
            commit ();
        }

        public void sort (Sheet s, Area selection, Gee.List<SortKey> keys, bool header) {
            var area = clamp_area (s, selection);
            if (area.r2 > s.max_row) area.r2 = int.max (s.max_row, area.r1);
            int first = header ? area.r1 + 1 : area.r1;
            if (first > area.r2) return;
            begin_area (_("Sort"), s, area, selection);
            var rows = new Gee.ArrayList<int> ();
            for (int r = first; r <= area.r2; r++) rows.add (r);
            var cache = new Gee.HashMap<int64?, Value> (s.cells.key_hash_func, s.cells.key_equal_func);
            foreach (int r in rows) foreach (var k in keys) cache[Sheet.key (r, k.col)] = s.value_at (r, k.col);
            rows.sort ((a, b) => {
                foreach (var k in keys) {
                    var va = cache[Sheet.key (a, k.col)];
                    var vb = cache[Sheet.key (b, k.col)];
                    bool ea = va.kind == ValueKind.EMPTY, eb = vb.kind == ValueKind.EMPTY;
                    if (ea && eb) continue;
                    if (ea) return 1;
                    if (eb) return -1;
                    int c = Evaluator.compare (va, vb);
                    if (c != 0) return k.ascending ? c : -c;
                }
                return a - b;
            });
            var moved = new Gee.ArrayList<CellCopy> ();
            for (int i = 0; i < rows.size; i++) {
                int from = rows[i];
                int to = first + i;
                for (int c = area.c1; c <= area.c2; c++) {
                    var cell = s.get_cell (from, c);
                    if (cell == null) continue;
                    var cp = new CellCopy.of (cell);
                    if (cp.formula != null) cp.formula = Formula.shifted (cp.formula, to - from, 0);
                    cp.row = to;
                    moved.add (cp);
                }
            }
            for (int r = first; r <= area.r2; r++) for (int c = area.c1; c <= area.c2; c++) s.cells.unset (Sheet.key (r, c));
            foreach (var cp in moved) {
                var cell = cp.restore ();
                if (cell.formula != null) cell.input = Formula.to_text (cell.formula, s);
                s.cells[Sheet.key (cell.row, cell.col)] = cell;
            }
            s.recompute_extent ();
            book.structure_changed = true;
            commit ();
        }

        public int remove_duplicates (Sheet s, Area selection, int[] cols, bool header) {
            var area = clamp_area (s, selection);
            if (area.r2 > s.max_row) area.r2 = int.max (s.max_row, area.r1);
            int first = header ? area.r1 + 1 : area.r1;
            begin_area (_("Remove Duplicates"), s, area, selection);
            var seen = new Gee.HashSet<string> ();
            var keep = new Gee.ArrayList<int> ();
            for (int r = first; r <= area.r2; r++) {
                var sb = new StringBuilder ();
                foreach (int c in cols) sb.append (s.value_at (r, c).display ().casefold () + "\x1f");
                if (seen.add (sb.str)) keep.add (r);
            }
            int removed = area.r2 - first + 1 - keep.size;
            var moved = new Gee.ArrayList<CellCopy> ();
            for (int i = 0; i < keep.size; i++) {
                for (int c = area.c1; c <= area.c2; c++) {
                    var cell = s.get_cell (keep[i], c);
                    if (cell == null) continue;
                    var cp = new CellCopy.of (cell);
                    cp.row = first + i;
                    if (cp.formula != null) cp.formula = Formula.shifted (cp.formula, cp.row - keep[i], 0);
                    moved.add (cp);
                }
            }
            for (int r = first; r <= area.r2; r++) for (int c = area.c1; c <= area.c2; c++) s.cells.unset (Sheet.key (r, c));
            foreach (var cp in moved) {
                var cell = cp.restore ();
                if (cell.formula != null) cell.input = Formula.to_text (cell.formula, s);
                s.cells[Sheet.key (cell.row, cell.col)] = cell;
            }
            s.recompute_extent ();
            book.structure_changed = true;
            commit ();
            return removed;
        }

        public void apply_filter (Sheet s) {
            var f = s.filter;
            if (f == null) return;
            for (int r = f.area.r1 + 1; r <= f.area.r2; r++) {
                bool hide = false;
                foreach (var e in f.hidden_values.entries) {
                    if (e.value.size == 0) continue;
                    string color;
                    var v = s.value_at (r, e.key);
                    string t = NumberFormat.format_value (v, s.style_at (r, e.key).number_format, out color, book.date1904);
                    if (e.value.contains (t)) hide = true;
                }
                if (hide) s.hidden_rows.add (r);
                else s.hidden_rows.remove (r);
            }
            FilterEngine.apply (book, s);
        }

        public void toggle_filter (Sheet s, Area selection) {
            begin_book (_("Filter"), s, selection);
            if (s.filter != null) {
                for (int r = s.filter.area.r1 + 1; r <= s.filter.area.r2; r++) s.hidden_rows.remove (r);
                s.filter = null;
            } else {
                var area = selection.is_single () ? current_region (s, selection.r1, selection.c1) : clamp_area (s, selection);
                if (area.r2 > s.max_row) area.r2 = int.max (s.max_row, area.r1);
                s.filter = new Filter (area);
            }
            commit ();
        }

        public void set_filter_values (Sheet s, int col, Gee.HashSet<string> hidden) {
            if (s.filter == null) return;
            begin_book (_("Filter"), s, s.filter.area);
            var f = s.filter.copy_to (s.filter.area);
            f.hidden_values[col] = hidden;
            s.filter = f;
            apply_filter (s);
            commit ();
        }

        public Area current_region (Sheet s, int row, int col) {
            int r1 = row, r2 = row, c1 = col, c2 = col;
            bool grew = true;
            while (grew) {
                grew = false;
                if (r1 > 0 && row_has_data (s, r1 - 1, c1, c2)) { r1--; grew = true; }
                if (r2 < MAX_ROWS - 1 && row_has_data (s, r2 + 1, c1, c2)) { r2++; grew = true; }
                if (c1 > 0 && col_has_data (s, c1 - 1, r1, r2)) { c1--; grew = true; }
                if (c2 < MAX_COLS - 1 && col_has_data (s, c2 + 1, r1, r2)) { c2++; grew = true; }
                if (r2 - r1 > 100000) break;
            }
            return new Area (s, r1, c1, r2, c2);
        }

        private static bool row_has_data (Sheet s, int r, int c1, int c2) {
            for (int c = int.max (c1 - 1, 0); c <= c2 + 1 && c <= s.max_col; c++) {
                var cell = s.get_cell (r, c);
                if (cell != null && (cell.input != "" || cell.formula != null)) return true;
            }
            return false;
        }

        private static bool col_has_data (Sheet s, int c, int r1, int r2) {
            for (int r = int.max (r1 - 1, 0); r <= r2 + 1 && r <= s.max_row; r++) {
                var cell = s.get_cell (r, c);
                if (cell != null && (cell.input != "" || cell.formula != null)) return true;
            }
            return false;
        }

        public void insert_rows (Sheet s, int at, int count) {
            begin_book (_("Insert Rows"), s, new Area (s, at, 0, at + count - 1, MAX_COLS - 1));
            book.insert_rows (s, at, count);
            shift_objects (s, true, at, count);
            commit ();
        }

        public void delete_rows (Sheet s, int at, int count) {
            begin_book (_("Delete Rows"), s, new Area (s, at, 0, at, MAX_COLS - 1));
            book.delete_rows (s, at, count);
            shift_objects (s, true, at, -count);
            commit ();
        }

        public void insert_cols (Sheet s, int at, int count) {
            begin_book (_("Insert Columns"), s, new Area (s, 0, at, MAX_ROWS - 1, at + count - 1));
            book.insert_cols (s, at, count);
            shift_objects (s, false, at, count);
            commit ();
        }

        public void delete_cols (Sheet s, int at, int count) {
            begin_book (_("Delete Columns"), s, new Area (s, 0, at, MAX_ROWS - 1, at));
            book.delete_cols (s, at, count);
            shift_objects (s, false, at, -count);
            commit ();
        }

        private void shift_objects (Sheet s, bool rows, int at, int count) {
            if (s.filter != null) {
                var a = Workbook.shift_area (s.filter.area, rows, at, count);
                s.filter = a != null ? s.filter.copy_to (a) : null;
            }
            var nv = new Gee.ArrayList<Validation> ();
            foreach (var v in s.validations) {
                var a = Workbook.shift_area (v.area, rows, at, count);
                if (a == null) continue;
                nv.add (v.copy_to (a));
            }
            s.validations = nv;
            s.outline.shift (rows, at, count);
            foreach (var ch in s.charts) {
                var a = Workbook.shift_area (ch.source, rows, at, count);
                if (a != null) ch.source = a;
            }
            ChartResolve.shift_refs (book, s, rows, at, count);
        }

        public void merge (Sheet s, Area area, bool center) {
            if (area.is_single ()) return;
            begin_book (_("Merge Cells"), s, area);
            var keep = new Gee.ArrayList<Area> ();
            foreach (var m in s.merges) if (!m.intersects (area)) keep.add (m);
            s.merges = keep;
            for (int r = area.r1; r <= area.r2; r++) {
                for (int c = area.c1; c <= area.c2; c++) {
                    if (r == area.r1 && c == area.c1) continue;
                    var cell = s.get_cell (r, c);
                    if (cell == null) continue;
                    cell.input = "";
                    cell.formula = null;
                    cell.value = Value.empty ();
                    if (cell.is_blank ()) s.cells.unset (Sheet.key (r, c));
                }
            }
            s.merges.add (area.copy ());
            if (center) {
                var cell = s.ensure (area.r1, area.c1);
                var st = book.styles[cell.style].copy ();
                st.halign = HAlign.CENTER;
                st.valign = VAlign.CENTER;
                cell.style = book.intern (st);
            }
            book.structure_changed = true;
            commit ();
        }

        public void unmerge (Sheet s, Area area) {
            begin_book (_("Unmerge Cells"), s, area);
            var keep = new Gee.ArrayList<Area> ();
            foreach (var m in s.merges) if (!m.intersects (area)) keep.add (m);
            s.merges = keep;
            commit ();
        }

        public void set_col_width (Sheet s, int c1, int c2, int width) {
            begin_book (_("Column Width"), s);
            for (int c = c1; c <= c2; c++) {
                s.col_widths[c] = width;
                s.hidden_cols.remove (c);
            }
            commit ();
        }

        public void set_row_height (Sheet s, int r1, int r2, int height) {
            begin_book (_("Row Height"), s);
            for (int r = r1; r <= r2; r++) {
                s.row_heights[r] = height;
                s.hidden_rows.remove (r);
            }
            commit ();
        }

        public void set_hidden (Sheet s, bool rows, int a, int b, bool hidden) {
            begin_book (hidden ? _("Hide") : _("Unhide"), s);
            for (int i = a; i <= b; i++) {
                if (rows) {
                    if (hidden) s.hidden_rows.add (i);
                    else s.hidden_rows.remove (i);
                } else {
                    if (hidden) s.hidden_cols.add (i);
                    else s.hidden_cols.remove (i);
                }
            }
            commit ();
        }

        public void set_freeze (Sheet s, int rows, int cols) {
            begin_book (_("Freeze Panes"), s);
            s.freeze_rows = rows;
            s.freeze_cols = cols;
            commit ();
        }

        public Sheet add_sheet (int at = -1) {
            begin_book (_("New Sheet"));
            var s = book.add_sheet (null, at);
            commit ();
            sheets_changed ();
            return s;
        }

        public Sheet duplicate_sheet (Sheet src) {
            begin_book (_("Duplicate Sheet"));
            string base_name = src.name + " (";
            string name = src.name;
            for (int i = 2; ; i++) {
                name = "%s%d)".printf (base_name, i);
                if (book.find_sheet (name) == null) break;
            }
            var s = book.add_sheet (name, book.sheets.index_of (src) + 1);
            foreach (var c in src.cells.values) {
                var cp = new CellCopy.of (c).restore ();
                if (cp.formula != null) {
                    cp.formula.foreach_ref ((n) => {
                        if (n.sheet == src) n.sheet = null;
                    });
                }
                s.cells[Sheet.key (cp.row, cp.col)] = cp;
            }
            foreach (var e in src.col_widths.entries) s.col_widths[e.key] = e.value;
            foreach (var e in src.row_heights.entries) s.row_heights[e.key] = e.value;
            foreach (var m in src.merges) s.merges.add (new Area (s, m.r1, m.c1, m.r2, m.c2));
            s.cond_formats.add_all (src.cond_formats);
            s.freeze_rows = src.freeze_rows;
            s.freeze_cols = src.freeze_cols;
            s.tab_color = src.tab_color;
            s.show_grid = src.show_grid;
            s.default_col_width = src.default_col_width;
            s.default_row_height = src.default_row_height;
            s.comments = src.comments.copy ();
            s.recompute_extent ();
            commit ();
            sheets_changed ();
            return s;
        }

        public void remove_sheet (Sheet s) {
            if (book.sheets.size <= 1) return;
            begin_book (_("Delete Sheet"));
            book.remove_sheet (s);
            commit ();
            sheets_changed ();
        }

        public void rename_sheet (Sheet s, string name) {
            string n = name.strip ();
            if (n == "" || n == s.name) return;
            var other = book.find_sheet (n);
            if (other != null && other != s) return;
            begin_book (_("Rename Sheet"));
            book.rename_sheet (s, n);
            commit ();
            sheets_changed ();
        }

        public void move_sheet (Sheet s, int to) {
            int from = book.sheets.index_of (s);
            if (from < 0 || to < 0 || to >= book.sheets.size || to == from) return;
            begin_book (_("Move Sheet"));
            book.sheets.remove_at (from);
            book.sheets.insert (to, s);
            commit ();
            sheets_changed ();
        }

        public bool set_sheet_visibility (Sheet s, int visibility) {
            if (visibility != 0) {
                int shown = 0;
                foreach (var other in book.sheets) if (other.visibility == 0 && other != s) shown++;
                if (shown == 0) return false;
            }
            begin_book (visibility == 0 ? _("Unhide Sheet") : _("Hide Sheet"), s);
            s.visibility = visibility;
            commit ();
            sheets_changed ();
            return true;
        }

        public void set_tab_color (Sheet s, string color) {
            begin_book (_("Tab Color"));
            s.tab_color = color;
            commit ();
            sheets_changed ();
        }

        public void set_note (Sheet s, int r, int c, string note) {
            begin_area (_("Note"), s, new Area.cell (s, r, c));
            var cell = s.ensure (r, c);
            if (cell.note != note) cell.note_author = "";
            cell.note = note;
            s.drop_if_blank (r, c);
            commit ();
        }

        public void set_link (Sheet s, Area area, string link, string? text) {
            begin_area (link == "" ? _("Remove Link") : _("Insert Link"), s, area);
            for (int r = area.r1; r <= area.r2 && r - area.r1 < 10000; r++) {
                for (int c = area.c1; c <= area.c2 && c - area.c1 < 1000; c++) {
                    s.ensure (r, c).link = link;
                    s.drop_if_blank (r, c);
                }
            }
            if (text != null && text != "" && link != "") s.set_input (area.r1, area.c1, text);
            commit ();
        }

        public void set_scoped_name (Sheet? scope, string name, string? formula) {
            begin_book (_("Named Range"));
            var map = scope != null ? scope.names : book.names;
            if (formula == null) map.unset (name);
            else map[name] = formula;
            commit ();
        }

        public void add_cond_format (Sheet s, CondFormat cf) {
            begin_book (_("Conditional Formatting"), s, cf.area);
            s.cond_formats.add (cf);
            commit ();
        }

        public void remove_cond_formats (Sheet s, Area area) {
            begin_book (_("Clear Rules"), s, area);
            var keep = new Gee.ArrayList<CondFormat> ();
            foreach (var cf in s.cond_formats) if (!cf.area.intersects (area)) keep.add (cf);
            s.cond_formats = keep;
            commit ();
        }

        public void set_validation (Sheet s, Area area, string? source) {
            begin_book (_("Data Validation"), s, area);
            var keep = new Gee.ArrayList<Validation> ();
            foreach (var v in s.validations) if (!v.area.intersects (area)) keep.add (v);
            s.validations = keep;
            if (source != null && source.strip () != "") {
                var v = new Validation (area.copy ());
                v.list_source = source.strip ();
                s.validations.add (v);
            }
            commit ();
        }

        public void set_name (string name, string? formula) {
            begin_book (_("Named Range"));
            if (formula == null) book.names.unset (name);
            else book.names[name] = formula;
            commit ();
        }

        public void add_chart (Sheet s, Chart chart) {
            begin_book (_("Insert Chart"), s);
            s.charts.add (chart);
            commit ();
        }

        public void update_chart (Sheet s, Chart chart, Chart updated) {
            begin_book (_("Edit Chart"), s);
            int i = s.charts.index_of (chart);
            if (i >= 0) s.charts[i] = updated;
            commit ();
        }

        public void remove_chart (Sheet s, Chart chart) {
            begin_book (_("Delete Chart"), s);
            s.charts.remove (chart);
            commit ();
        }

        public void add_drawing (Sheet s, Drawing d) {
            begin_book (d.kind == DrawingKind.IMAGE ? _("Insert Picture") : _("Insert Shape"), s);
            s.drawings.add (d);
            commit ();
        }

        public void update_drawing (Sheet s, Drawing d, Drawing updated) {
            begin_book (_("Edit Shape"), s);
            int i = s.drawings.index_of (d);
            if (i >= 0) s.drawings[i] = updated;
            commit ();
        }

        public void remove_drawing (Sheet s, Drawing d) {
            begin_book (d.kind == DrawingKind.IMAGE ? _("Delete Picture") : _("Delete Shape"), s);
            s.drawings.remove (d);
            commit ();
        }

        public void move_object (Sheet s, string label) {
            begin_book (label, s);
        }

        public void add_sparklines (Sheet s, SparklineGroup g) {
            begin_book (_("Insert Sparklines"), s);
            foreach (var item in g.items) remove_sparkline_at (s, item.row, item.col);
            s.sparklines.add (g);
            commit ();
        }

        public void clear_sparklines (Sheet s, Area area) {
            begin_book (_("Clear Sparklines"), s);
            for (int r = area.r1; r <= area.r2 && r - area.r1 < 100000; r++) {
                for (int c = area.c1; c <= area.c2 && c - area.c1 < 1000; c++) remove_sparkline_at (s, r, c);
            }
            commit ();
        }

        private static void remove_sparkline_at (Sheet s, int r, int c) {
            var empty = new Gee.ArrayList<SparklineGroup> ();
            foreach (var g in s.sparklines) {
                for (int i = g.items.size - 1; i >= 0; i--) {
                    if (g.items[i].row == r && g.items[i].col == c) g.items.remove_at (i);
                }
                if (g.items.size == 0) empty.add (g);
            }
            foreach (var g in empty) s.sparklines.remove (g);
        }

        public static SparklineGroup? sparkline_group_at (Sheet s, int r, int c, out Sparkline? item) {
            item = null;
            foreach (var g in s.sparklines) {
                foreach (var it in g.items) {
                    if (it.row == r && it.col == c) {
                        item = it;
                        return g;
                    }
                }
            }
            return null;
        }

        public void set_grid (Sheet s, bool show) {
            begin_book (_("Gridlines"), s);
            s.show_grid = show;
            commit ();
        }

        public Gee.List<string> validation_items (Sheet s, int row, int col) {
            var items = new Gee.ArrayList<string> ();
            foreach (var v in s.validations) {
                if (!v.area.contains (row, col)) continue;
                string src = v.list_source;
                if (src.has_prefix ("\"") && src.has_suffix ("\"")) {
                    foreach (string p in src.substring (1, src.length - 2).split (",")) if (p.strip () != "") items.add (p.strip ());
                    return items;
                }
                try {
                    var ev = new Evaluator (book, s, row, col);
                    var val = ev.eval (Formula.parse ("=" + (src.has_prefix ("=") ? src.substring (1) : src), book, s));
                    ev.visit_value (val, true, (x, r) => {
                        if (x.kind != ValueKind.EMPTY) items.add (x.display ());
                        return true;
                    });
                } catch (FormulaError e) {
                    foreach (string p in src.split (",")) if (p.strip () != "") items.add (p.strip ());
                }
                return items;
            }
            return items;
        }
    }
}
