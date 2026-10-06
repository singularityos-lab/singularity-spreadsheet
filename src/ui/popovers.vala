using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class BorderGlyph : DrawingArea {
        private string kind;

        public BorderGlyph (string kind) {
            this.kind = kind;
            set_size_request (18, 18);
            set_draw_func (draw);
        }

        private void draw (DrawingArea da, Cairo.Context cr, int w, int h) {
            var c = get_color ();
            double x0 = 2.5, y0 = 2.5, x1 = w - 2.5, y1 = h - 2.5, mx = w / 2.0, my = h / 2.0;
            cr.set_line_width (1);
            cr.set_source_rgba (c.red, c.green, c.blue, 0.3);
            cr.set_dash ({ 1, 2 }, 0);
            cr.rectangle (x0, y0, x1 - x0, y1 - y0);
            cr.move_to (mx, y0);
            cr.line_to (mx, y1);
            cr.move_to (x0, my);
            cr.line_to (x1, my);
            cr.stroke ();
            cr.set_dash (null, 0);
            cr.set_source_rgba (c.red, c.green, c.blue, 1);
            cr.set_line_width (1.6);
            switch (kind) {
                case "all":
                    cr.rectangle (x0, y0, x1 - x0, y1 - y0);
                    cr.move_to (mx, y0);
                    cr.line_to (mx, y1);
                    cr.move_to (x0, my);
                    cr.line_to (x1, my);
                    break;
                case "outer":
                    cr.rectangle (x0, y0, x1 - x0, y1 - y0);
                    break;
                case "inner":
                    cr.move_to (mx, y0);
                    cr.line_to (mx, y1);
                    cr.move_to (x0, my);
                    cr.line_to (x1, my);
                    break;
                case "top":
                    cr.move_to (x0, y0);
                    cr.line_to (x1, y0);
                    break;
                case "bottom":
                    cr.move_to (x0, y1);
                    cr.line_to (x1, y1);
                    break;
                case "left":
                    cr.move_to (x0, y0);
                    cr.line_to (x0, y1);
                    break;
                case "right":
                    cr.move_to (x1, y0);
                    cr.line_to (x1, y1);
                    break;
            }
            cr.stroke ();
        }
    }

    public class FindPopover : Popover {
        private SpreadsheetWindow win;
        private Entry find_entry;
        private Entry replace_entry;
        private CheckButton match_case;
        private CheckButton whole;
        private CheckButton in_formulas;
        private CheckButton all_sheets;
        private Label status;

        public FindPopover (SpreadsheetWindow win) {
            this.win = win;
            has_arrow = false;
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_top = box.margin_bottom = box.margin_start = box.margin_end = 10;
            box.width_request = 320;
            find_entry = new Entry ();
            find_entry.placeholder_text = _("Find");
            find_entry.primary_icon_name = "edit-find-symbolic";
            find_entry.activate.connect (() => find (true));
            replace_entry = new Entry ();
            replace_entry.placeholder_text = _("Replace with");
            replace_entry.activate.connect (() => replace_one ());
            box.append (find_entry);
            box.append (replace_entry);
            var opts = new Box (Orientation.HORIZONTAL, 10);
            match_case = new CheckButton.with_label (_("Match case"));
            whole = new CheckButton.with_label (_("Entire cell"));
            opts.append (match_case);
            opts.append (whole);
            box.append (opts);
            var opts2 = new Box (Orientation.HORIZONTAL, 10);
            in_formulas = new CheckButton.with_label (_("In formulas"));
            all_sheets = new CheckButton.with_label (_("All sheets"));
            opts2.append (in_formulas);
            opts2.append (all_sheets);
            box.append (opts2);
            var buttons = new Box (Orientation.HORIZONTAL, 6);
            var prev = new Button.from_icon_name ("go-up-symbolic");
            prev.tooltip_text = _("Previous");
            prev.clicked.connect (() => find (false));
            var next = new Button.from_icon_name ("go-down-symbolic");
            next.tooltip_text = _("Next");
            next.clicked.connect (() => find (true));
            var rep = new Button.with_label (_("Replace"));
            rep.clicked.connect (() => replace_one ());
            var rep_all = new Button.with_label (_("Replace All"));
            rep_all.add_css_class ("suggested-action");
            rep_all.clicked.connect (() => replace_all ());
            buttons.append (prev);
            buttons.append (next);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            buttons.append (spacer);
            buttons.append (rep);
            buttons.append (rep_all);
            box.append (buttons);
            status = new Label ("");
            status.add_css_class ("dim-label");
            status.add_css_class ("caption");
            status.halign = Align.START;
            box.append (status);
            child = box;
            map.connect (() => find_entry.grab_focus ());
        }

        private bool matches (Sheet s, Cell cell) {
            string needle = find_entry.text;
            if (needle == "") return false;
            string hay;
            if (in_formulas.active) hay = cell.input;
            else {
                string color;
                hay = NumberFormat.format_value (win.doc.book.cell_value (s, cell), win.doc.book.styles[cell.style].number_format, out color);
            }
            if (!match_case.active) {
                hay = hay.casefold ();
                needle = needle.casefold ();
            }
            return whole.active ? hay == needle : hay.contains (needle);
        }

        private Gee.List<Cell> hits (Sheet s) {
            var list = new Gee.ArrayList<Cell> ();
            foreach (var c in s.cells.values) if (matches (s, c)) list.add (c);
            list.sort ((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
            return list;
        }

        private void find (bool forward) {
            var sheets = new Gee.ArrayList<Sheet> ();
            if (all_sheets.active) {
                int start = win.doc.book.sheets.index_of (win.grid.sheet);
                for (int i = 0; i < win.doc.book.sheets.size; i++) sheets.add (win.doc.book.sheets[(start + i) % win.doc.book.sheets.size]);
            } else {
                sheets.add (win.grid.sheet);
            }
            int total = 0;
            foreach (var s in sheets) total += hits (s).size;
            if (total == 0) {
                status.label = _("No matches");
                return;
            }
            status.label = ngettext ("%d match", "%d matches", total).printf (total);
            var cur = hits (win.grid.sheet);
            int r = win.grid.cur_row, c = win.grid.cur_col;
            Cell? found = null;
            if (forward) {
                foreach (var cell in cur) {
                    if (cell.row > r || (cell.row == r && cell.col > c)) {
                        found = cell;
                        break;
                    }
                }
            } else {
                for (int i = cur.size - 1; i >= 0; i--) {
                    var cell = cur[i];
                    if (cell.row < r || (cell.row == r && cell.col < c)) {
                        found = cell;
                        break;
                    }
                }
            }
            if (found != null) {
                win.grid.select_cell (found.row, found.col, false);
                return;
            }
            for (int i = 1; i < sheets.size; i++) {
                var hs = hits (sheets[i]);
                if (hs.size == 0) continue;
                win.grid.show_sheet (sheets[i]);
                var cell = forward ? hs[0] : hs[hs.size - 1];
                win.grid.select_cell (cell.row, cell.col, false);
                return;
            }
            if (cur.size > 0) {
                var cell = forward ? cur[0] : cur[cur.size - 1];
                win.grid.select_cell (cell.row, cell.col, false);
            }
        }

        private string replaced (string input) {
            string needle = find_entry.text;
            string with = replace_entry.text;
            if (whole.active) return with;
            if (match_case.active) return input.replace (needle, with);
            try {
                var re = new Regex (Regex.escape_string (needle), RegexCompileFlags.CASELESS);
                return re.replace_literal (input, -1, 0, with);
            } catch (RegexError e) {
                return input;
            }
        }

        private void replace_one () {
            var s = win.grid.sheet;
            var cell = s.get_cell (win.grid.cur_row, win.grid.cur_col);
            if (cell != null && matches (s, cell)) {
                win.doc.set_input (s, cell.row, cell.col, replaced (cell.input));
            }
            find (true);
        }

        private void replace_all () {
            int n = 0;
            var sheets = all_sheets.active ? win.doc.book.sheets : new Gee.ArrayList<Sheet>.wrap ({ win.grid.sheet });
            win.doc.begin_book (_("Replace All"), win.grid.sheet);
            foreach (var s in sheets) {
                foreach (var cell in hits (s)) {
                    if (cell.formula != null && !in_formulas.active) continue;
                    s.set_input (cell.row, cell.col, replaced (cell.input));
                    n++;
                }
            }
            win.doc.commit ();
            status.label = ngettext ("Replaced %d cell", "Replaced %d cells", n).printf (n);
        }
    }

    public class FunctionPicker : Popover {
        public signal void chosen (string name);
        private ListBox list;
        private Gtk.SearchEntry search;
        private string category = "";
        private Label detail;

        public FunctionPicker (string initial = "") {
            category = initial;
            has_arrow = false;
            add_css_class ("ss-function-picker");
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_top = box.margin_bottom = box.margin_start = box.margin_end = 10;
            box.width_request = 420;
            search = new Gtk.SearchEntry ();
            search.placeholder_text = _("Search functions");
            search.search_changed.connect (fill);
            search.activate.connect (() => {
                var row = list.get_row_at_index (0);
                if (row != null) chosen (row.get_data<string> ("fn"));
            });
            box.append (search);
            var cats = new Box (Orientation.HORIZONTAL, 4);
            string[] keys = { "", "Math", "Statistical", "Logical", "Text", "Date", "Lookup", "Financial", "Information", "Engineering", "Database", "Cube", "Web", "Compatibility" };
            string[] labels = { _("All"), _("Math"), _("Statistics"), _("Logic"), _("Text"), _("Date"), _("Lookup"), _("Finance"), _("Info"), _("Engineering"), _("Database"), _("Cube"), _("Web"), _("Compatibility") };
            ToggleButton? first = null;
            for (int i = 0; i < keys.length; i++) {
                var b = new ToggleButton.with_label (labels[i]);
                b.add_css_class ("ss-chip");
                if (first == null) first = b;
                else b.group = first;
                b.active = keys[i] == category;
                string k = keys[i];
                b.toggled.connect (() => {
                    if (!b.active) return;
                    category = k;
                    fill ();
                });
                cats.append (b);
            }
            var cat_scroll = new ScrolledWindow ();
            cat_scroll.vscrollbar_policy = PolicyType.NEVER;
            cat_scroll.child = cats;
            box.append (cat_scroll);
            list = new ListBox ();
            list.add_css_class ("ss-function-list");
            list.row_activated.connect ((row) => chosen (row.get_data<string> ("fn")));
            list.row_selected.connect ((row) => {
                if (row == null) return;
                var def = Functions.all ()[row.get_data<string> ("fn")];
                detail.set_markup ("<b>%s</b>\n%s".printf (Markup.escape_text (def.syntax), Markup.escape_text (def.summary)));
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.min_content_height = 280;
            scroll.child = list;
            box.append (scroll);
            detail = new Label ("");
            detail.wrap = true;
            detail.xalign = 0;
            detail.add_css_class ("ss-function-detail");
            box.append (detail);
            child = box;
            fill ();
            map.connect (() => search.grab_focus ());
        }

        private void fill () {
            Widget? c;
            while ((c = list.get_first_child ()) != null) list.remove (c);
            string q = search.text.strip ().up ();
            var names = new Gee.TreeSet<string> ();
            foreach (var e in Functions.all ().entries) {
                if (category != "" && e.value.category != category) continue;
                if (q != "" && !e.key.contains (q) && !e.value.summary.up ().contains (q)) continue;
                names.add (e.key);
            }
            foreach (string n in names) {
                var def = Functions.all ()[n];
                var row = new ListBoxRow ();
                var b = new Box (Orientation.HORIZONTAL, 10);
                b.margin_top = b.margin_bottom = 4;
                b.margin_start = b.margin_end = 6;
                var nl = new Label (n);
                nl.add_css_class ("ss-function-name");
                nl.halign = Align.START;
                nl.width_chars = 16;
                nl.xalign = 0;
                var sl = new Label (def.summary);
                sl.add_css_class ("dim-label");
                sl.ellipsize = Pango.EllipsizeMode.END;
                sl.halign = Align.START;
                sl.hexpand = true;
                b.append (nl);
                b.append (sl);
                row.child = b;
                row.set_data<string> ("fn", n);
                list.append (row);
            }
            var first = list.get_row_at_index (0);
            if (first != null) list.select_row (first);
        }
    }

    public class FilterPopover : Popover {
        private SpreadsheetWindow win;
        private int col;
        private Gee.HashMap<string, CheckButton> checks = new Gee.HashMap<string, CheckButton> ();

        public FilterPopover (SpreadsheetWindow win, int col) {
            this.win = win;
            this.col = col;
            var s = win.grid.sheet;
            var f = s.filter;
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_top = box.margin_bottom = box.margin_start = box.margin_end = 10;
            box.width_request = 260;
            var asc = new MenuRow (_("Sort A to Z"), "view-sort-ascending-symbolic");
            asc.clicked.connect (() => sort (true));
            var desc = new MenuRow (_("Sort Z to A"), "view-sort-descending-symbolic");
            desc.clicked.connect (() => sort (false));
            box.append (asc);
            box.append (desc);
            box.append (new Separator (Orientation.HORIZONTAL));
            var search = new Gtk.SearchEntry ();
            search.placeholder_text = _("Search values");
            box.append (search);
            var hidden = f.hidden_values.has_key (col) ? f.hidden_values[col] : new Gee.HashSet<string> ();
            var values = new Gee.TreeMap<string, int> ((a, b) => a.collate (b));
            for (int r = f.area.r1 + 1; r <= f.area.r2; r++) {
                string color;
                var v = s.value_at (r, col);
                string t = NumberFormat.format_value (v, s.style_at (r, col).number_format, out color, win.doc.book.date1904);
                values[t] = (values.has_key (t) ? values[t] : 0) + 1;
            }
            var list = new Box (Orientation.VERTICAL, 2);
            var all = new CheckButton.with_label (_("Select All"));
            all.active = hidden.size == 0;
            list.append (all);
            foreach (var e in values.entries) {
                var cb = new CheckButton.with_label (e.key == "" ? _("(Blanks)") : e.key);
                cb.active = !hidden.contains (e.key);
                checks[e.key] = cb;
                list.append (cb);
            }
            all.toggled.connect (() => {
                foreach (var cb in checks.values) cb.active = all.active;
            });
            search.search_changed.connect (() => {
                string q = search.text.casefold ();
                foreach (var e in checks.entries) e.value.visible = q == "" || e.key.casefold ().contains (q);
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.max_content_height = 260;
            scroll.propagate_natural_height = true;
            scroll.child = list;
            box.append (scroll);
            var buttons = new Box (Orientation.HORIZONTAL, 6);
            buttons.halign = Align.END;
            var clear = new Button.with_label (_("Clear"));
            clear.clicked.connect (() => {
                win.doc.set_filter_values (s, col, new Gee.HashSet<string> ());
                popdown ();
            });
            var ok = new Button.with_label (_("Apply"));
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                var hide = new Gee.HashSet<string> ();
                foreach (var e in checks.entries) if (!e.value.active) hide.add (e.key);
                win.doc.set_filter_values (s, col, hide);
                win.grid.refresh ();
                if (s.hidden_rows.contains (win.grid.cur_row)) win.grid.select_cell (s.filter.area.r1, col, false);
                popdown ();
            });
            buttons.append (clear);
            buttons.append (ok);
            box.append (buttons);
            child = box;
        }

        private void sort (bool asc) {
            var s = win.grid.sheet;
            var keys = new Gee.ArrayList<SortKey> ();
            keys.add (new SortKey (col, asc));
            win.doc.sort (s, s.filter.area, keys, true);
            popdown ();
        }
    }
}
