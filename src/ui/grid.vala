using Gtk;

namespace Singularity.Apps.Spreadsheet {

    public class SheetView : Widget, Scrollable {
        private const string[] REF_COLORS = { "#2a78d6", "#e34948", "#1baf7a", "#9085e9", "#eda100", "#e87ba4" };

        public Document doc { get; private set; }
        public Sheet sheet { get; private set; }
        public double zoom { get; private set; default = 1.0; }
        public bool show_formulas { get; set; }
        public int cur_row { get; private set; }
        public int cur_col { get; private set; }
        public Chart? selected_chart { get; private set; }
        public Drawing? selected_drawing { get; private set; }

        private int anchor_row;
        private int anchor_col;
        private Axis rows;
        private Axis cols;
        private CondEval? cond;

        private Adjustment? _hadj;
        private Adjustment? _vadj;
        public Adjustment hadjustment {
            get { return _hadj; }
            set construct {
                if (_hadj != null) _hadj.value_changed.disconnect (on_scrolled);
                _hadj = value;
                if (_hadj != null) _hadj.value_changed.connect (on_scrolled);
                update_adjustments ();
            }
        }
        public Adjustment vadjustment {
            get { return _vadj; }
            set construct {
                if (_vadj != null) _vadj.value_changed.disconnect (on_scrolled);
                _vadj = value;
                if (_vadj != null) _vadj.value_changed.connect (on_scrolled);
                update_adjustments ();
            }
        }
        public ScrollablePolicy hscroll_policy { get; set; }
        public ScrollablePolicy vscroll_policy { get; set; }

        private TextView editor;
        private ScrolledWindow editor_scroll;
        private bool editing;
        private bool enter_mode;
        private int edit_row;
        private int edit_col;
        private bool syncing;
        private int ref_start = -1;
        private int ref_end = -1;
        private Popover assist;
        private ListBox assist_list;
        private Label hint;
        private Popover hint_pop;

        private enum Drag {
            NONE,
            SELECT,
            ROWS,
            COLS,
            RESIZE_COL,
            RESIZE_ROW,
            FILL,
            REFERENCE,
            CHART_MOVE,
            CHART_RESIZE
        }

        private Drag drag = Drag.NONE;
        private GestureDrag drag_gesture;
        private int resize_index;
        private double drag_start_x;
        private double drag_start_y;
        private int fill_row;
        private int fill_col;
        private int ref_anchor_row;
        private int ref_anchor_col;
        private double chart_x0;
        private double chart_y0;
        private double chart_w0;
        private double chart_h0;
        private uint autoscroll_id;
        private double last_x;
        private double last_y;

        public signal void selection_changed ();
        public signal void editing_changed (string text, bool active);
        public signal void context_menu (double x, double y);
        public signal void filter_clicked (int col, double x, double y);
        public signal void validation_clicked (int row, int col, double x, double y);
        public signal void chart_activated (Chart chart);
        public signal void link_activated (string link);
        public signal void chart_menu (Chart chart, double x, double y);
        public signal void drawing_activated (Drawing drawing);
        public signal void drawing_menu (Drawing drawing, double x, double y);
        public signal void zoom_changed ();
        public signal void draw_overlay (Cairo.Context cr, double width, double height);
        public signal void edit_blocked (string message);
        public signal void entry_rejected (int row, int col, string text, Validation rule);
        public Gee.List<Area>? invalid_circles;
        public Gee.List<Area>? selection_areas;

        public Gee.List<Area> all_areas () {
            var list = new Gee.ArrayList<Area> ();
            if (selection_areas != null) list.add_all (selection_areas);
            list.add (selection);
            return list;
        }

        public void focus_area (Area a) {
            anchor_row = a.r1;
            anchor_col = a.c1;
            cur_row = a.r2;
            cur_col = a.c2;
        }

        public void set_areas (Gee.List<Area> areas) {
            if (areas.size == 0) return;
            select_area (areas[areas.size - 1]);
            var extra = new Gee.ArrayList<Area> ();
            for (int i = 0; i < areas.size - 1; i++) extra.add (areas[i]);
            selection_areas = extra.size > 0 ? extra : null;
            cur_row = areas[areas.size - 1].r1;
            cur_col = areas[areas.size - 1].c1;
            queue_draw ();
            selection_changed ();
        }

        public SheetView (Document doc) {
            this.doc = doc;
            this.sheet = doc.book.sheets[0];
            focusable = true;
            can_focus = true;
            overflow = Overflow.HIDDEN;
            add_css_class ("spreadsheet-grid");
            has_tooltip = true;
            rebuild_axes ();

            editor = new TextView ();
            editor.add_css_class ("spreadsheet-editor");
            editor.wrap_mode = WrapMode.NONE;
            editor.accepts_tab = false;
            editor.top_margin = 2;
            editor.left_margin = 4;
            editor.right_margin = 4;
            editor_scroll = new ScrolledWindow ();
            editor_scroll.hscrollbar_policy = PolicyType.EXTERNAL;
            editor_scroll.vscrollbar_policy = PolicyType.EXTERNAL;
            editor_scroll.child = editor;
            editor_scroll.set_parent (this);
            editor_scroll.visible = false;
            editor.buffer.changed.connect (on_editor_changed);
            editor.buffer.notify["cursor-position"].connect (update_hint);
            var ekeys = new EventControllerKey ();
            ekeys.set_propagation_phase (PropagationPhase.CAPTURE);
            ekeys.key_pressed.connect (on_editor_key);
            editor.add_controller (ekeys);

            assist_list = new ListBox ();
            assist_list.add_css_class ("spreadsheet-assist");
            assist_list.selection_mode = SelectionMode.BROWSE;
            assist_list.row_activated.connect ((row) => complete_function (row.get_data<string> ("fn")));
            var assist_scroll = new ScrolledWindow ();
            assist_scroll.hscrollbar_policy = PolicyType.NEVER;
            assist_scroll.max_content_height = 260;
            assist_scroll.min_content_width = 300;
            assist_scroll.propagate_natural_height = true;
            assist_scroll.child = assist_list;
            assist = new Popover ();
            assist.autohide = false;
            assist.has_arrow = false;
            assist.position = PositionType.BOTTOM;
            assist.child = assist_scroll;
            assist.set_parent (editor_scroll);
            assist.can_focus = false;
            hint = new Label ("");
            hint.add_css_class ("spreadsheet-hint");
            hint.use_markup = true;
            hint_pop = new Popover ();
            hint_pop.autohide = false;
            hint_pop.has_arrow = false;
            hint_pop.position = PositionType.TOP;
            hint_pop.child = hint;
            hint_pop.set_parent (editor_scroll);
            hint_pop.can_focus = false;

            drag_gesture = new GestureDrag ();
            drag_gesture.button = Gdk.BUTTON_PRIMARY;
            drag_gesture.drag_begin.connect (on_drag_begin);
            drag_gesture.drag_update.connect (on_drag_update);
            drag_gesture.drag_end.connect (on_drag_end);
            add_controller (drag_gesture);

            var click = new GestureClick ();
            click.button = 0;
            click.pressed.connect (on_click);
            add_controller (click);

            var motion = new EventControllerMotion ();
            motion.motion.connect (on_motion);
            add_controller (motion);

            var zoom_scroll = new EventControllerScroll (EventControllerScrollFlags.VERTICAL);
            zoom_scroll.set_propagation_phase (PropagationPhase.CAPTURE);
            zoom_scroll.scroll.connect ((dx, dy) => {
                var st = zoom_scroll.get_current_event_state ();
                if ((st & Gdk.ModifierType.CONTROL_MASK) == 0) return false;
                zoom_to (zoom * (dy < 0 ? 1.1 : 1 / 1.1));
                return true;
            });
            add_controller (zoom_scroll);

            var keys = new EventControllerKey ();
            keys.key_pressed.connect (on_key);
            add_controller (keys);

            query_tooltip.connect (on_tooltip);
            doc.changed.connect (() => {
                cond = null;
                rebuild_axes ();
                queue_draw ();
            });
        }

        public override void dispose () {
            if (editor_scroll != null) {
                assist.unparent ();
                hint_pop.unparent ();
                editor_scroll.unparent ();
                editor_scroll = null;
            }
            base.dispose ();
        }

        public bool get_border (out Gtk.Border border) {
            border = Gtk.Border ();
            return false;
        }

        public void show_sheet (Sheet s) {
            if (editing) commit_edit (0, 0);
            sheet = s;
            selected_chart = null;
            selected_drawing = null;
            cond = null;
            rebuild_axes ();
            if (_hadj != null) _hadj.value = 0;
            if (_vadj != null) _vadj.value = 0;
            select_cell (0, 0, false);
            queue_draw ();
        }

        public void refresh () {
            cond = null;
            rebuild_axes ();
            update_adjustments ();
            queue_draw ();
        }

        private void rebuild_axes () {
            rows = new Axis (MAX_ROWS, sheet.default_row_height, sheet.row_heights, sheet.hidden_rows);
            cols = new Axis (MAX_COLS, sheet.default_col_width, sheet.col_widths, sheet.hidden_cols);
        }

        public void zoom_to (double z) {
            double nz = z.clamp (0.4, 3.0);
            if (Math.fabs (nz - zoom) < 0.001) return;
            zoom = nz;
            update_adjustments ();
            queue_allocate ();
            queue_draw ();
            zoom_changed ();
        }

        private double hw {
            get {
                int digits = (last_visible_row () + 1).to_string ().length;
                return gutter_w + Math.round ((24 + 8 * int.max (digits, 3)) * zoom);
            }
        }

        private double hh {
            get { return gutter_h + Math.round (26 * zoom); }
        }

        public double gutter_w {
            get { return OutlineGutter.size (sheet, true, zoom); }
        }

        public double gutter_h {
            get { return OutlineGutter.size (sheet, false, zoom); }
        }

        public double corner_w {
            get { return hw; }
        }

        public double corner_h {
            get { return hh; }
        }

        private double frozen_w {
            get { return cols.pos (sheet.freeze_cols) * zoom; }
        }

        private double frozen_h {
            get { return rows.pos (sheet.freeze_rows) * zoom; }
        }

        private double hscroll {
            get { return _hadj != null ? _hadj.value : 0; }
        }

        private double vscroll {
            get { return _vadj != null ? _vadj.value : 0; }
        }

        public double col_x (int c) {
            if (c < sheet.freeze_cols) return hw + cols.pos (c) * zoom;
            return hw + frozen_w + (cols.pos (c) - cols.pos (sheet.freeze_cols)) * zoom - hscroll;
        }

        public double row_y (int r) {
            if (r < sheet.freeze_rows) return hh + rows.pos (r) * zoom;
            return hh + frozen_h + (rows.pos (r) - rows.pos (sheet.freeze_rows)) * zoom - vscroll;
        }

        public double col_w (int c) {
            return cols.size (c) * zoom;
        }

        public double row_h (int r) {
            return rows.size (r) * zoom;
        }

        public int col_at (double x) {
            if (x < hw) return -1;
            if (x < hw + frozen_w) return cols.index_at ((int64) ((x - hw) / zoom));
            return int.min (cols.index_at (cols.pos (sheet.freeze_cols) + (int64) ((x - hw - frozen_w + hscroll) / zoom)), MAX_COLS - 1);
        }

        public int row_at (double y) {
            if (y < hh) return -1;
            if (y < hh + frozen_h) return rows.index_at ((int64) ((y - hh) / zoom));
            return int.min (rows.index_at (rows.pos (sheet.freeze_rows) + (int64) ((y - hh - frozen_h + vscroll) / zoom)), MAX_ROWS - 1);
        }

        private int first_scroll_row () {
            return rows.index_at (rows.pos (sheet.freeze_rows) + (int64) (vscroll / zoom));
        }

        private int first_scroll_col () {
            return cols.index_at (cols.pos (sheet.freeze_cols) + (int64) (hscroll / zoom));
        }

        private int last_visible_row () {
            if (rows == null) return 100;
            double page = get_height () - 26 * zoom - frozen_h;
            return int.min (rows.index_at (rows.pos (sheet.freeze_rows) + (int64) ((vscroll + page) / zoom)) + 1, MAX_ROWS - 1);
        }

        private int last_visible_col () {
            double page = get_width () - hw - frozen_w;
            return int.min (cols.index_at (cols.pos (sheet.freeze_cols) + (int64) ((hscroll + page) / zoom)) + 1, MAX_COLS - 1);
        }

        private void on_scrolled () {
            update_adjustments ();
            if (editing) queue_allocate ();
            queue_draw ();
        }

        private bool updating_adj;

        private void update_adjustments () {
            if (updating_adj || rows == null) return;
            updating_adj = true;
            double page_w = double.max (get_width () - hw - frozen_w, 1);
            double page_h = double.max (get_height () - hh - frozen_h, 1);
            if (_hadj != null) {
                int far_c = int.max (int.max (sheet.max_col, cur_col), last_visible_col ()) + 20;
                double content = (cols.pos (int.min (far_c, MAX_COLS)) - cols.pos (sheet.freeze_cols)) * zoom;
                double upper = double.min (double.max (content, _hadj.value + page_w * 1.5), (cols.total () - cols.pos (sheet.freeze_cols)) * zoom);
                _hadj.configure (_hadj.value, 0, upper, 40 * zoom, page_w * 0.9, page_w);
            }
            if (_vadj != null) {
                int far_r = int.max (int.max (sheet.max_row, cur_row), last_visible_row ()) + 60;
                double content = (rows.pos (int.min (far_r, MAX_ROWS)) - rows.pos (sheet.freeze_rows)) * zoom;
                double upper = double.min (double.max (content, _vadj.value + page_h * 1.5), (rows.total () - rows.pos (sheet.freeze_rows)) * zoom);
                _vadj.configure (_vadj.value, 0, upper, 3 * sheet.default_row_height * zoom, page_h * 0.9, page_h);
            }
            updating_adj = false;
        }

        public override void measure (Orientation o, int for_size, out int minimum, out int natural, out int mb, out int nb) {
            minimum = natural = 100;
            mb = nb = -1;
        }

        public override void size_allocate (int width, int height, int baseline) {
            update_adjustments ();
            if (editing && editor_scroll != null) {
                var rect = cell_rect (edit_row, edit_col);
                int ew = (int) double.max (rect.size.width, 60);
                int eh = (int) double.max (rect.size.height, 22);
                int nat_w, nat_h, mw, mh;
                editor.measure (Orientation.HORIZONTAL, -1, out mw, out nat_w, null, null);
                editor.measure (Orientation.VERTICAL, ew, out mh, out nat_h, null, null);
                ew = int.max (ew, int.min (nat_w + 12, width - (int) rect.origin.x - 4));
                eh = int.max (eh, int.min (nat_h + 4, height - (int) rect.origin.y - 4));
                var alloc = Gtk.Allocation () { x = (int) rect.origin.x, y = (int) rect.origin.y, width = ew, height = eh };
                editor_scroll.allocate_size (alloc, -1);
            }
            if (assist != null && assist.visible) assist.present ();
            if (hint_pop != null && hint_pop.visible) hint_pop.present ();
        }

        public Graphene.Rect cell_rect (int r, int c) {
            var m = sheet.merge_at (r, c);
            int r1 = m != null ? m.r1 : r, c1 = m != null ? m.c1 : c;
            int r2 = m != null ? m.r2 : r, c2 = m != null ? m.c2 : c;
            double x = col_x (c1), y = row_y (r1);
            double w = col_x (c2) + col_w (c2) - x;
            double h = row_y (r2) + row_h (r2) - y;
            return Graphene.Rect ().init ((float) x, (float) y, (float) w, (float) h);
        }

        public Area selection {
            owned get {
                var a = new Area (sheet, anchor_row, anchor_col, cur_row, cur_col);
                return expand_merges (a);
            }
        }

        private Area expand_merges (owned Area a) {
            bool grew = true;
            while (grew) {
                grew = false;
                foreach (var m in sheet.merges) {
                    if (!m.intersects (a)) continue;
                    if (m.r1 < a.r1 || m.c1 < a.c1 || m.r2 > a.r2 || m.c2 > a.c2) {
                        a = new Area (sheet, int.min (a.r1, m.r1), int.min (a.c1, m.c1), int.max (a.r2, m.r2), int.max (a.c2, m.c2));
                        grew = true;
                    }
                }
            }
            return a;
        }

        public void select_cell (int r, int c, bool extend) {
            r = r.clamp (0, MAX_ROWS - 1);
            c = c.clamp (0, MAX_COLS - 1);
            if (!extend && !adding_area) selection_areas = null;
            if (!extend) {
                anchor_row = r;
                anchor_col = c;
            }
            cur_row = r;
            cur_col = c;
            selected_chart = null;
            selected_drawing = null;
            ensure_visible (r, c);
            queue_draw ();
            selection_changed ();
        }

        public void select_area (Area a) {
            if (!adding_area) selection_areas = null;
            anchor_row = a.r1;
            anchor_col = a.c1;
            cur_row = a.r2;
            cur_col = a.c2;
            selected_chart = null;
            selected_drawing = null;
            ensure_visible (a.r1, a.c1);
            queue_draw ();
            selection_changed ();
        }

        public void set_active_in_selection (int r, int c) {
            cur_row = r;
            cur_col = c;
        }

        public void ensure_visible (int r, int c) {
            if (_hadj == null || _vadj == null) return;
            update_adjustments ();
            if (c >= sheet.freeze_cols) {
                double x = (cols.pos (c) - cols.pos (sheet.freeze_cols)) * zoom;
                double w = col_w (c);
                double page = get_width () - hw - frozen_w;
                if (x < _hadj.value) _hadj.value = x;
                else if (x + w > _hadj.value + page && page > 0) _hadj.value = double.min (x, x + w - page);
            }
            if (r >= sheet.freeze_rows) {
                double y = (rows.pos (r) - rows.pos (sheet.freeze_rows)) * zoom;
                double h = row_h (r);
                double page = get_height () - hh - frozen_h;
                if (y < _vadj.value) _vadj.value = y;
                else if (y + h > _vadj.value + page && page > 0) {
                    update_adjustments ();
                    _vadj.value = double.min (y, y + h - page);
                }
            }
        }

        private Gdk.RGBA fg;
        private Gdk.RGBA accent;
        private bool dark;

        private void load_colors () {
            fg = get_color ();
            dark = (fg.red + fg.green + fg.blue) / 3 > 0.5;
            var ctx = get_style_context ();
            if (!ctx.lookup_color ("accent_bg_color", out accent)) accent = { 0.21f, 0.52f, 0.89f, 1 };
        }

        private static void rgba (Cairo.Context cr, Gdk.RGBA c, double alpha = 1) {
            cr.set_source_rgba (c.red, c.green, c.blue, c.alpha * alpha);
        }

        private static bool hex (Cairo.Context cr, string h, double alpha = 1) {
            if (h.length != 7 || !h.has_prefix ("#")) return false;
            cr.set_source_rgba (Xlsx.hex2 (h, 1) / 255.0, Xlsx.hex2 (h, 3) / 255.0, Xlsx.hex2 (h, 5) / 255.0, alpha);
            return true;
        }

        private string readable (string color, string fill) {
            if (!dark || fill != "" || color.length != 7) return color;
            double r = Xlsx.hex2 (color, 1) / 255.0, g = Xlsx.hex2 (color, 3) / 255.0, b = Xlsx.hex2 (color, 5) / 255.0;
            double lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            if (lum >= 0.45) return color;
            double mx = double.max (r, double.max (g, b)), mn = double.min (r, double.min (g, b));
            double l = (mx + mn) / 2;
            double target = 1 - l;
            double shift = target - l;
            int nr = (int) (((r + shift).clamp (0, 1)) * 255);
            int ng = (int) (((g + shift).clamp (0, 1)) * 255);
            int nb = (int) (((b + shift).clamp (0, 1)) * 255);
            return "#%02x%02x%02x".printf (nr, ng, nb);
        }

        private static string named_color (string name) {
            switch (name) {
                case "red": return "#d63a3a";
                case "green": return "#1e8a3c";
                case "blue": return "#2a5fd6";
                case "yellow": return "#b58900";
                case "magenta": return "#c03aa8";
                case "cyan": return "#1b9aa3";
                case "white": return "#ffffff";
                case "black": return "#000000";
                default: return "";
            }
        }

        private string paper () {
            return dark ? "#1e1f22" : "#ffffff";
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (cond == null) cond = new CondEval (doc.book, sheet);
            load_colors ();
            double w = get_width (), h = get_height ();
            var cr = snapshot.append_cairo (Graphene.Rect ().init (0, 0, (float) w, (float) h));
            hex (cr, paper ());
            cr.paint ();

            int fr = sheet.freeze_rows, fc = sheet.freeze_cols;
            int sr = first_scroll_row (), sc = first_scroll_col ();
            int er = last_visible_row (), ec = last_visible_col ();
            double cx0 = hw + frozen_w, cy0 = hh + frozen_h;

            draw_region (cr, sr, er, sc, ec, cx0, cy0, w - cx0, h - cy0);
            if (fc > 0) draw_region (cr, sr, er, 0, fc - 1, hw, cy0, frozen_w, h - cy0);
            if (fr > 0) draw_region (cr, 0, fr - 1, sc, ec, cx0, hh, w - cx0, frozen_h);
            if (fr > 0 && fc > 0) draw_region (cr, 0, fr - 1, 0, fc - 1, hw, hh, frozen_w, frozen_h);

            draw_charts (cr, cx0, cy0, w, h);
            cr.save ();
            cr.rectangle (hw, hh, w - hw, h - hh);
            cr.clip ();
            draw_overlay (cr, w, h);
            cr.restore ();
            draw_headers (cr, sr, er, sc, ec, w, h);
            OutlineGutter.draw (this, cr, w, h, fg);
            if (fr > 0) {
                cr.move_to (0, Math.round (cy0) + 0.5);
                cr.line_to (w, Math.round (cy0) + 0.5);
                rgba (cr, fg, 0.35);
                cr.set_line_width (1.5);
                cr.stroke ();
            }
            if (fc > 0) {
                cr.move_to (Math.round (cx0) + 0.5, 0);
                cr.line_to (Math.round (cx0) + 0.5, h);
                rgba (cr, fg, 0.35);
                cr.set_line_width (1.5);
                cr.stroke ();
            }
            if (editing_needs_child ()) snapshot_child (editor_scroll, snapshot);
        }

        private bool editing_needs_child () {
            return editing && editor_scroll != null && editor_scroll.visible;
        }

        private void draw_region (Cairo.Context cr, int r0, int r1, int c0, int c1, double clip_x, double clip_y, double clip_w, double clip_h) {
            if (clip_w <= 0 || clip_h <= 0 || r1 < r0 || c1 < c0) return;
            cr.save ();
            cr.rectangle (clip_x, clip_y, clip_w, clip_h);
            cr.clip ();

            if (sheet.show_grid) {
                rgba (cr, fg, dark ? 0.12 : 0.1);
                cr.set_line_width (1);
                for (int c = c0; c <= c1 + 1 && c < MAX_COLS; c++) {
                    if (col_w (c) == 0 && c <= c1) continue;
                    double x = Math.round (col_x (c)) - 0.5;
                    cr.move_to (x, clip_y);
                    cr.line_to (x, clip_y + clip_h);
                }
                for (int r = r0; r <= r1 + 1 && r < MAX_ROWS; r++) {
                    if (row_h (r) == 0 && r <= r1) continue;
                    double y = Math.round (row_y (r)) - 0.5;
                    cr.move_to (clip_x, y);
                    cr.line_to (clip_x + clip_w, y);
                }
                cr.stroke ();
            }

            var drawn_merges = new Gee.HashSet<Area> ();
            var sel = selection;
            var text_jobs = new Gee.ArrayList<TextJob> ();
            for (int r = r0; r <= r1; r++) {
                if (row_h (r) == 0) continue;
                for (int c = c0; c <= c1; c++) {
                    if (col_w (c) == 0) continue;
                    var m = sheet.merge_at (r, c);
                    if (m != null) {
                        if (drawn_merges.contains (m)) continue;
                        drawn_merges.add (m);
                        draw_cell (cr, m.r1, m.c1, cell_rect (m.r1, m.c1), text_jobs, true);
                        continue;
                    }
                    var cell = sheet.get_cell (r, c);
                    if (cell == null && sheet.cond_formats.size == 0 && (sheet.spills.size == 0 || sheet.spill_anchor_at (r, c) == null) && (sheet.comments.size == 0 || !sheet.comments.has (r, c)) && (doc.book.revisions.changes.size == 0 || doc.book.revisions.cell_change (sheet, r, c) == null)) continue;
                    draw_cell (cr, r, c, cell_rect (r, c), text_jobs, false);
                }
            }
            foreach (var m in sheet.merges) {
                if (drawn_merges.contains (m)) continue;
                if (m.r2 < r0 || m.r1 > r1 || m.c2 < c0 || m.c1 > c1) continue;
                draw_cell (cr, m.r1, m.c1, cell_rect (m.r1, m.c1), text_jobs, true);
            }
            foreach (var job in text_jobs) draw_text (cr, job, r0, r1, c0, c1);

            draw_decorations (cr, r0, r1, c0, c1);
            draw_selection (cr, sel);
            cr.restore ();
        }

        private class TextJob {
            public int row;
            public int col;
            public Graphene.Rect rect;
            public string text;
            public CellStyle style;
            public Value value;
            public string color;
            public bool bold;
            public bool italic;
            public bool underline;
            public bool strike;
            public bool merged;
        }

        private void draw_cell (Cairo.Context cr, int r, int c, Graphene.Rect rect, Gee.ArrayList<TextJob> jobs, bool merged) {
            var cell = sheet.get_cell (r, c);
            var style = doc.book.styles[cell != null ? cell.style : 0];
            var v = cell != null || sheet.spills.size > 0 ? sheet.value_at (r, c) : Value.empty ();
            CondStyle? cs = sheet.cond_formats.size > 0 ? cond.apply (r, c, v) : null;
            string fill = cs != null && cs.fill != "" ? cs.fill : style.fill;
            double x = rect.origin.x, y = rect.origin.y, w = rect.size.width, h = rect.size.height;
            if (fill != "") {
                hex (cr, fill);
                cr.rectangle (x - 1, y - 1, w + 1, h + 1);
                cr.fill ();
            } else if (merged) {
                hex (cr, paper ());
                cr.rectangle (x, y, w - 1, h - 1);
                cr.fill ();
            }
            if (cs != null && cs.bar >= 0) {
                double bw = (w - 6) * cs.bar.clamp (0, 1);
                var pat = new Cairo.Pattern.linear (x + 3, 0, x + 3 + bw, 0);
                string bc = cs.bar_color != "" ? cs.bar_color : "#638ec6";
                pat.add_color_stop_rgba (0, Xlsx.hex2 (bc, 1) / 255.0, Xlsx.hex2 (bc, 3) / 255.0, Xlsx.hex2 (bc, 5) / 255.0, 0.85);
                pat.add_color_stop_rgba (1, Xlsx.hex2 (bc, 1) / 255.0, Xlsx.hex2 (bc, 3) / 255.0, Xlsx.hex2 (bc, 5) / 255.0, 0.25);
                cr.set_source (pat);
                cr.rectangle (x + 3, y + 3, bw, h - 7);
                cr.fill ();
            }
            if (cs != null && cs.icon >= 0) CondIconPainter.draw (cr, cs.icon_set, cs.icon, x + 3, y + (h - 14) / 2, 14);
            draw_borders (cr, style, x, y, w, h);
            if (sheet.comments.size > 0) CommentsUi.draw_marker (cr, sheet, r, c, x, y, w);
            if (doc.book.revisions.changes.size > 0) ReviewUi.draw_change (cr, sheet, r, c, x, y, w, h);
            if (cell == null && v.is_empty ()) return;
            if (cell != null && cell.note != "") {
                cr.move_to (x + w - 7, y);
                cr.line_to (x + w - 1, y);
                cr.line_to (x + w - 1, y + 6);
                cr.close_path ();
                hex (cr, "#e34948");
                cr.fill ();
            }
            if (v.kind == ValueKind.EMPTY && !(show_formulas && cell != null && cell.formula != null)) return;
            if (cs != null && cs.hide_value && !show_formulas) return;
            if (editing && r == edit_row && c == edit_col) return;
            if (v.image != null && !show_formulas) return;
            var job = new TextJob ();
            job.row = r;
            job.col = c;
            job.rect = rect;
            job.style = style;
            job.value = v;
            job.merged = merged;
            string nf_color = "";
            job.text = show_formulas && cell != null && cell.formula != null ? cell.input : NumberFormat.format_value (v, style.number_format, out nf_color, doc.book.date1904);
            if (show_formulas && cell != null && cell.formula != null) nf_color = "";
            job.color = cs != null && cs.color != "" ? cs.color : (nf_color != "" ? named_color (nf_color) : style.color);
            job.color = readable (job.color, fill);
            job.bold = style.bold || (cs != null && cs.bold);
            job.italic = style.italic || (cs != null && cs.italic);
            job.underline = style.underline || (cs != null && cs.underline);
            job.strike = style.strike || (cs != null && cs.strike);
            if (!show_formulas && cell != null && (cell.link != "" || (cell.formula != null && cell.formula.kind == NodeKind.CALL && cell.formula.text == "HYPERLINK"))) {
                if (style.color == "" && (cs == null || cs.color == "")) job.color = readable ("#0563c1", fill);
                job.underline = true;
            }
            jobs.add (job);
        }

        private void draw_borders (Cairo.Context cr, CellStyle s, double x, double y, double w, double h) {
            border_line (cr, s.top, x - 1, y - 0.5, x + w, y - 0.5);
            border_line (cr, s.bottom, x - 1, y + h - 0.5, x + w, y + h - 0.5);
            border_line (cr, s.left, x - 0.5, y - 1, x - 0.5, y + h);
            border_line (cr, s.right, x + w - 0.5, y - 1, x + w - 0.5, y + h);
        }

        private void border_line (Cairo.Context cr, Border b, double x1, double y1, double x2, double y2) {
            if (b.style == BorderStyle.NONE) return;
            cr.save ();
            if (!hex (cr, readable (b.color, ""))) rgba (cr, fg, 0.9);
            switch (b.style) {
                case BorderStyle.MEDIUM: cr.set_line_width (2); break;
                case BorderStyle.THICK: cr.set_line_width (3); break;
                case BorderStyle.DASHED:
                    cr.set_line_width (1);
                    cr.set_dash ({ 4, 2 }, 0);
                    break;
                case BorderStyle.DOTTED:
                    cr.set_line_width (1);
                    cr.set_dash ({ 1, 2 }, 0);
                    break;
                default: cr.set_line_width (1); break;
            }
            if (b.style == BorderStyle.DOUBLE) {
                bool horizontal = y1 == y2;
                cr.set_line_width (1);
                cr.move_to (x1 - (horizontal ? 0 : 1), y1 - (horizontal ? 1 : 0));
                cr.line_to (x2 - (horizontal ? 0 : 1), y2 - (horizontal ? 1 : 0));
                cr.move_to (x1 + (horizontal ? 0 : 1), y1 + (horizontal ? 1 : 0));
                cr.line_to (x2 + (horizontal ? 0 : 1), y2 + (horizontal ? 1 : 0));
            } else {
                cr.move_to (x1, y1);
                cr.line_to (x2, y2);
            }
            cr.stroke ();
            cr.restore ();
        }

        private Pango.FontDescription? base_font;

        private Pango.Layout make_layout (TextJob job) {
            if (base_font == null) base_font = get_pango_context ().get_font_description ().copy ();
            var layout = create_pango_layout (null);
            var font = base_font.copy ();
            if (job.style.font_family != "") font.set_family (job.style.font_family);
            font.set_absolute_size (job.style.font_size * 96 / 72 * zoom * Pango.SCALE);
            font.set_weight (job.bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
            font.set_style (job.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL);
            layout.set_font_description (font);
            var attrs = new Pango.AttrList ();
            if (job.underline) attrs.insert (Pango.attr_underline_new (Pango.Underline.SINGLE));
            if (job.strike) attrs.insert (Pango.attr_strikethrough_new (true));
            layout.set_attributes (attrs);
            layout.set_text (job.text, -1);
            return layout;
        }

        private bool cell_free (int r, int c) {
            var cell = sheet.get_cell (r, c);
            if (cell != null && (cell.input != "" || cell.formula != null)) return false;
            return sheet.merge_at (r, c) == null;
        }

        private void draw_text (Cairo.Context cr, TextJob job, int r0, int r1, int c0, int c1) {
            var layout = make_layout (job);
            var st = job.style;
            if (st.rotation != 0 && !show_formulas) {
                EditOverlay.draw_rotated (cr, layout, job.rect, st, zoom, job.color, fg);
                return;
            }
            double pad = 4 * zoom;
            double x = job.rect.origin.x, y = job.rect.origin.y, w = job.rect.size.width, h = job.rect.size.height;
            if (has_button (job.row, job.col)) w -= double.min (18 * zoom, h - 4) + 6;
            HAlign align = st.halign;
            if (align == HAlign.GENERAL) {
                if (job.value.kind == ValueKind.NUMBER && !(show_formulas && sheet.get_cell (job.row, job.col).formula != null)) align = HAlign.RIGHT;
                else if (job.value.kind == ValueKind.BOOL || job.value.kind == ValueKind.ERROR) align = HAlign.CENTER;
                else align = HAlign.LEFT;
            }
            double indent = st.indent * 10 * zoom;
            if (st.wrap || align == HAlign.JUSTIFY) {
                layout.set_width ((int) ((w - pad * 2 - indent) * Pango.SCALE));
                layout.set_wrap (Pango.WrapMode.WORD_CHAR);
            }
            if (align == HAlign.CENTER) layout.set_alignment (Pango.Alignment.CENTER);
            else if (align == HAlign.RIGHT) layout.set_alignment (Pango.Alignment.RIGHT);
            if (align == HAlign.JUSTIFY) layout.set_justify (true);
            int tw, th;
            layout.get_pixel_size (out tw, out th);
            if (st.shrink && !st.wrap) EditOverlay.shrink (layout, w - pad * 2 - indent, ref tw, ref th);
            double clip_l = x, clip_r = x + w;
            if (!st.wrap && tw > w - pad * 2 && !job.merged) {
                if (job.value.kind == ValueKind.NUMBER && !show_formulas) {
                    job.text = string.nfill (int.max (1, (int) ((w - pad * 2) / (7 * zoom))), '#');
                    layout.set_text (job.text, -1);
                    layout.get_pixel_size (out tw, out th);
                } else if (align == HAlign.LEFT || align == HAlign.CENTER) {
                    int c = job.col + 1;
                    while (clip_r - x < tw + pad * 2 + indent && c < job.col + 30 && c < MAX_COLS && cell_free (job.row, c)) {
                        clip_r += col_w (c);
                        c++;
                    }
                    if (align == HAlign.CENTER) {
                        int lc = job.col - 1;
                        while (clip_r - clip_l < tw + pad * 2 && lc >= 0 && lc > job.col - 30 && cell_free (job.row, lc)) {
                            clip_l -= col_w (lc);
                            lc--;
                        }
                    }
                } else if (align == HAlign.RIGHT) {
                    int c = job.col - 1;
                    while (x + w - clip_l < tw + pad * 2 && c >= 0 && c > job.col - 30 && cell_free (job.row, c)) {
                        clip_l -= col_w (c);
                        c--;
                    }
                }
            }
            double tx;
            if (st.wrap || align == HAlign.JUSTIFY) tx = x + pad + indent;
            else if (align == HAlign.RIGHT) tx = x + w - pad - tw - indent;
            else if (align == HAlign.CENTER) tx = x + (w - tw) / 2;
            else tx = x + pad + indent;
            double ty;
            if (st.valign == VAlign.TOP) ty = y + 2 * zoom;
            else if (st.valign == VAlign.CENTER) ty = y + (h - th) / 2;
            else ty = y + h - th - 3 * zoom;
            if (!st.wrap && th > h) ty = y + (h - th) / 2;
            cr.save ();
            cr.rectangle (clip_l, y, clip_r - clip_l - 1, h - 1);
            cr.clip ();
            if (align == HAlign.FILL && tw > 0 && job.text != "") {
                string rep = job.text;
                while (tw * 2 <= w - pad * 2) {
                    rep += job.text;
                    layout.set_text (rep, -1);
                    layout.get_pixel_size (out tw, out th);
                }
            }
            if (!hex (cr, job.color)) rgba (cr, fg);
            cr.move_to (tx, ty);
            Pango.cairo_show_layout (cr, layout);
            cr.restore ();
        }

        private bool has_button (int r, int c) {
            if (sheet.filter != null && r == sheet.filter.area.r1 && c >= sheet.filter.area.c1 && c <= sheet.filter.area.c2) return true;
            if (r == cur_row && c == cur_col) {
                foreach (var v in sheet.validations) if (v.area.contains (r, c) && v.kind == ValidationKind.LIST && v.dropdown) return true;
            }
            return false;
        }

        private void draw_decorations (Cairo.Context cr, int r0, int r1, int c0, int c1) {
            if (sheet.filter != null) {
                var f = sheet.filter.area;
                int r = f.r1;
                if (r >= r0 && r <= r1) {
                    for (int c = int.max (f.c1, c0); c <= int.min (f.c2, c1); c++) {
                        var rect = cell_rect (r, c);
                        double s = double.min (18 * zoom, rect.size.height - 4);
                        double bx = rect.origin.x + rect.size.width - s - 3;
                        double by = rect.origin.y + (rect.size.height - s) / 2;
                        bool active = sheet.filter.hidden_values.has_key (c) && sheet.filter.hidden_values[c].size > 0;
                        rounded (cr, bx, by, s, s, 4);
                        if (active) rgba (cr, accent);
                        else rgba (cr, fg, 0.08);
                        cr.fill ();
                        Gdk.RGBA white = { 1, 1, 1, 1 };
                        chevron (cr, bx + s / 2, by + s / 2, s * 0.22, active ? white : fg);
                    }
                }
            }
            EditOverlay.draw (this, cr, r0, r1, c0, c1, accent);
            foreach (var v in sheet.validations) {
                if (!v.area.contains (cur_row, cur_col)) continue;
                if (v.kind != ValidationKind.LIST || !v.dropdown) continue;
                if (cur_row < r0 || cur_row > r1 || cur_col < c0 || cur_col > c1) continue;
                var rect = cell_rect (cur_row, cur_col);
                double s = double.min (18 * zoom, rect.size.height - 4);
                double bx = rect.origin.x + rect.size.width - s - 3;
                double by = rect.origin.y + (rect.size.height - s) / 2;
                rounded (cr, bx, by, s, s, 4);
                rgba (cr, fg, 0.1);
                cr.fill ();
                chevron (cr, bx + s / 2, by + s / 2, s * 0.22, fg);
            }
            if (doc.clip != null && doc.clip.sheet == sheet) {
                var a = Document.clamp_area (sheet, doc.clip.source);
                double x1 = col_x (a.c1), y1 = row_y (a.r1);
                double x2 = col_x (a.c2) + col_w (a.c2), y2 = row_y (a.r2) + row_h (a.r2);
                cr.save ();
                cr.rectangle (x1 + 0.5, y1 + 0.5, x2 - x1 - 2, y2 - y1 - 2);
                rgba (cr, accent);
                cr.set_line_width (1.5);
                cr.set_dash ({ 4, 3 }, 0);
                cr.stroke ();
                cr.restore ();
            }
            if (editing) draw_reference_boxes (cr);
        }

        private void rounded (Cairo.Context cr, double x, double y, double w, double h, double r) {
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        private void chevron (Cairo.Context cr, double cx, double cy, double s, Gdk.RGBA color) {
            cr.move_to (cx - s, cy - s * 0.45);
            cr.line_to (cx, cy + s * 0.55);
            cr.line_to (cx + s, cy - s * 0.45);
            rgba (cr, color, 0.85);
            cr.set_line_width (1.6);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.stroke ();
        }

        private void draw_selection (Cairo.Context cr, Area sel) {
            if (selected_chart != null || selected_drawing != null) return;
            double x1 = col_x (sel.c1), y1 = row_y (sel.r1);
            double x2 = col_x (sel.c2) + col_w (sel.c2), y2 = row_y (sel.r2) + row_h (sel.r2);
            if (sel.c2 == MAX_COLS - 1) x2 = double.max (x2, get_width () + 10);
            if (sel.r2 == MAX_ROWS - 1) y2 = double.max (y2, get_height () + 10);
            x1 = double.max (x1, -10);
            y1 = double.max (y1, -10);
            x2 = double.min (x2, get_width () + 10);
            y2 = double.min (y2, get_height () + 10);
            if (!sel.is_single ()) {
                var active = cell_rect (cur_row, cur_col);
                cr.save ();
                cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                cr.rectangle (x1, y1, x2 - x1, y2 - y1);
                cr.rectangle (active.origin.x, active.origin.y, active.size.width, active.size.height);
                rgba (cr, accent, 0.14);
                cr.fill ();
                cr.restore ();
            }
            cr.rectangle (x1 - 0.5, y1 - 0.5, x2 - x1 - 1, y2 - y1 - 1);
            rgba (cr, accent);
            cr.set_line_width (2);
            cr.stroke ();
            if (!editing && sel.r2 < MAX_ROWS - 1 && sel.c2 < MAX_COLS - 1) {
                double hs = 7;
                cr.rectangle (x2 - hs / 2 - 1, y2 - hs / 2 - 1, hs, hs);
                hex (cr, paper ());
                cr.fill_preserve ();
                rgba (cr, accent);
                cr.set_line_width (1.5);
                cr.stroke ();
            }
            if (drag == Drag.FILL) {
                var fa = fill_target ();
                if (fa != null) {
                    double fx1 = col_x (fa.c1), fy1 = row_y (fa.r1);
                    double fx2 = col_x (fa.c2) + col_w (fa.c2), fy2 = row_y (fa.r2) + row_h (fa.r2);
                    cr.save ();
                    cr.rectangle (fx1 + 0.5, fy1 + 0.5, fx2 - fx1 - 2, fy2 - fy1 - 2);
                    rgba (cr, accent);
                    cr.set_line_width (1);
                    cr.set_dash ({ 3, 2 }, 0);
                    cr.stroke ();
                    cr.restore ();
                }
            }
        }

        private void draw_headers (Cairo.Context cr, int sr, int er, int sc, int ec, double w, double h) {
            var sel = selection;
            var header_bg = dark ? "#26272b" : "#f4f4f6";
            hex (cr, header_bg);
            cr.rectangle (0, 0, w, hh);
            cr.rectangle (0, 0, hw, h);
            cr.fill ();
            var font = get_pango_context ().get_font_description ().copy ();
            font.set_absolute_size (11 * zoom * Pango.SCALE);

            int[] col_ranges = { 0, sheet.freeze_cols - 1, sc, ec };
            for (int k = 0; k < 2; k++) {
                int a = col_ranges[k * 2], b = col_ranges[k * 2 + 1];
                cr.save ();
                double clip_x = k == 0 ? hw : hw + frozen_w;
                cr.rectangle (clip_x, 0, k == 0 ? frozen_w : w - clip_x, hh);
                cr.clip ();
                for (int c = a; c <= b; c++) {
                    double cw = col_w (c);
                    if (cw == 0) continue;
                    double x = col_x (c);
                    bool in_sel = c >= sel.c1 && c <= sel.c2;
                    bool full = sel.r1 == 0 && sel.r2 == MAX_ROWS - 1;
                    if (in_sel) {
                        rgba (cr, accent, full ? 0.35 : 0.16);
                        cr.rectangle (x, gutter_h, cw, hh - gutter_h);
                        cr.fill ();
                    }
                    var layout = create_pango_layout (Address.column_name (c));
                    font.set_weight (in_sel ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
                    layout.set_font_description (font);
                    int tw, th;
                    layout.get_pixel_size (out tw, out th);
                    rgba (cr, fg, in_sel ? 0.95 : 0.6);
                    cr.move_to (x + (cw - tw) / 2, gutter_h + (hh - gutter_h - th) / 2);
                    Pango.cairo_show_layout (cr, layout);
                    cr.move_to (Math.round (x + cw) - 0.5, gutter_h + 4);
                    cr.line_to (Math.round (x + cw) - 0.5, hh - 4);
                    rgba (cr, fg, 0.12);
                    cr.set_line_width (1);
                    cr.stroke ();
                }
                cr.restore ();
            }
            int[] row_ranges = { 0, sheet.freeze_rows - 1, sr, er };
            for (int k = 0; k < 2; k++) {
                int a = row_ranges[k * 2], b = row_ranges[k * 2 + 1];
                cr.save ();
                double clip_y = k == 0 ? hh : hh + frozen_h;
                cr.rectangle (0, clip_y, hw, k == 0 ? frozen_h : h - clip_y);
                cr.clip ();
                for (int r = a; r <= b; r++) {
                    double rh = row_h (r);
                    if (rh == 0) continue;
                    double y = row_y (r);
                    bool in_sel = r >= sel.r1 && r <= sel.r2;
                    bool full = sel.c1 == 0 && sel.c2 == MAX_COLS - 1;
                    if (in_sel) {
                        rgba (cr, accent, full ? 0.35 : 0.16);
                        cr.rectangle (gutter_w, y, hw - gutter_w, rh);
                        cr.fill ();
                    }
                    var layout = create_pango_layout ((r + 1).to_string ());
                    font.set_weight (in_sel ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
                    layout.set_font_description (font);
                    int tw, th;
                    layout.get_pixel_size (out tw, out th);
                    rgba (cr, fg, in_sel ? 0.95 : 0.6);
                    cr.move_to (gutter_w + (hw - gutter_w - tw) / 2, y + (rh - th) / 2);
                    Pango.cairo_show_layout (cr, layout);
                    cr.move_to (gutter_w + 6, Math.round (y + rh) - 0.5);
                    cr.line_to (hw - 6, Math.round (y + rh) - 0.5);
                    rgba (cr, fg, 0.12);
                    cr.set_line_width (1);
                    cr.stroke ();
                }
                cr.restore ();
            }
            cr.move_to (0, Math.round (hh) - 0.5);
            cr.line_to (w, Math.round (hh) - 0.5);
            cr.move_to (Math.round (hw) - 0.5, 0);
            cr.line_to (Math.round (hw) - 0.5, h);
            rgba (cr, fg, 0.18);
            cr.set_line_width (1);
            cr.stroke ();
            cr.move_to (hw - 6, hh - 14 * zoom);
            cr.line_to (hw - 6, hh - 6);
            cr.line_to (hw - 14 * zoom, hh - 6);
            cr.close_path ();
            rgba (cr, fg, 0.25);
            cr.fill ();
        }

        private Graphene.Rect chart_rect (Chart ch) {
            double x = hw + frozen_w + ch.x * zoom - hscroll;
            double y = hh + frozen_h + ch.y * zoom - vscroll;
            return Graphene.Rect ().init ((float) x, (float) y, (float) (ch.width * zoom), (float) (ch.height * zoom));
        }

        private Graphene.Rect drawing_rect (Drawing d) {
            double x = hw + frozen_w + d.x * zoom - hscroll;
            double y = hh + frozen_h + d.y * zoom - vscroll;
            return Graphene.Rect ().init ((float) x, (float) y, (float) (d.width * zoom), (float) (d.height * zoom));
        }

        private void draw_sparklines (Cairo.Context cr, double w, double h) {
            if (sheet.sparklines.size == 0) return;
            cr.save ();
            cr.rectangle (hw, hh, w - hw, h - hh);
            cr.clip ();
            int fr = first_scroll_row (), lr = last_visible_row ();
            int fc = first_scroll_col (), lc = last_visible_col ();
            foreach (var g in sheet.sparklines) {
                foreach (var it in g.items) {
                    bool frozen_r = it.row < sheet.freeze_rows, frozen_c = it.col < sheet.freeze_cols;
                    if (!frozen_r && (it.row < fr || it.row > lr)) continue;
                    if (!frozen_c && (it.col < fc || it.col > lc)) continue;
                    double cw = col_w (it.col), ch = row_h (it.row);
                    if (cw <= 0 || ch <= 0) continue;
                    ChartRenderer.draw_sparkline (cr, doc.book, sheet, g, it, col_x (it.col), row_y (it.row), cw, ch);
                }
            }
            cr.restore ();
        }

        private void draw_cell_images (Cairo.Context cr, double w, double h) {
            if (show_formulas) return;
            int fr = first_scroll_row (), lr = last_visible_row ();
            int fc = first_scroll_col (), lc = last_visible_col ();
            cr.save ();
            cr.rectangle (hw, hh, w - hw, h - hh);
            cr.clip ();
            foreach (var cl in sheet.cells.values) {
                if (cl.formula == null) continue;
                bool fzr = cl.row < sheet.freeze_rows, fzc = cl.col < sheet.freeze_cols;
                if (!fzr && (cl.row < fr || cl.row > lr)) continue;
                if (!fzc && (cl.col < fc || cl.col > lc)) continue;
                var v = cl.value;
                if (v == null || v.image == null) continue;
                double x = col_x (cl.col), y = row_y (cl.row);
                double cw = col_w (cl.col), ch = row_h (cl.row);
                var m = sheet.merge_at (cl.row, cl.col);
                if (m != null) {
                    cw = col_x (m.c2) + col_w (m.c2) - x;
                    ch = row_y (m.r2) + row_h (m.r2) - y;
                }
                ChartRenderer.draw_cell_image (cr, v, x, y, cw, ch, zoom);
            }
            cr.restore ();
        }

        private void draw_objects (Cairo.Context cr, double cx0, double cy0, double w, double h) {
            draw_cell_images (cr, w, h);
            draw_sparklines (cr, w, h);
            if (sheet.drawings.size == 0) return;
            cr.save ();
            cr.rectangle (cx0, cy0, w - cx0, h - cy0);
            cr.clip ();
            foreach (var d in sheet.drawings) {
                var rect = drawing_rect (d);
                if (rect.origin.x > w || rect.origin.y > h || rect.origin.x + rect.size.width < cx0 - 10 || rect.origin.y + rect.size.height < cy0 - 10) continue;
                cr.save ();
                cr.translate (rect.origin.x, rect.origin.y);
                cr.scale (zoom, zoom);
                ChartRenderer.draw_drawing (cr, d, d.width, d.height, dark, d == selected_drawing);
                cr.restore ();
            }
            cr.restore ();
        }

        private Drawing? drawing_at (double x, double y, out bool on_handle) {
            on_handle = false;
            if (x < hw + frozen_w || y < hh + frozen_h) return null;
            for (int i = sheet.drawings.size - 1; i >= 0; i--) {
                var d = sheet.drawings[i];
                var rect = drawing_rect (d);
                double rx2 = rect.origin.x + rect.size.width, ry2 = rect.origin.y + rect.size.height;
                if (d == selected_drawing && Math.fabs (x - rx2) < 10 && Math.fabs (y - ry2) < 10) {
                    on_handle = true;
                    return d;
                }
                double pad = rect.size.width < 8 || rect.size.height < 8 ? 6 : 0;
                if (x >= rect.origin.x - pad && x <= rx2 + pad && y >= rect.origin.y - pad && y <= ry2 + pad) return d;
            }
            return null;
        }

        private void draw_charts (Cairo.Context cr, double cx0, double cy0, double w, double h) {
            draw_objects (cr, cx0, cy0, w, h);
            if (sheet.charts.size == 0) return;
            cr.save ();
            cr.rectangle (cx0, cy0, w - cx0, h - cy0);
            cr.clip ();
            foreach (var ch in sheet.charts) {
                var rect = chart_rect (ch);
                if (rect.origin.x > w || rect.origin.y > h || rect.origin.x + rect.size.width < cx0 || rect.origin.y + rect.size.height < cy0) continue;
                cr.save ();
                cr.translate (rect.origin.x, rect.origin.y);
                cr.scale (zoom, zoom);
                ChartRenderer.draw (cr, ch, ChartData.from (doc.book, sheet, ch), ch.width, ch.height, dark, ch == selected_chart);
                cr.restore ();
                if (ch == selected_chart) {
                    double hs = 8;
                    double[] xs = { rect.origin.x, rect.origin.x + rect.size.width };
                    double[] ys = { rect.origin.y, rect.origin.y + rect.size.height };
                    foreach (double hx in xs) foreach (double hy in ys) {
                        cr.rectangle (hx - hs / 2, hy - hs / 2, hs, hs);
                        hex (cr, paper ());
                        cr.fill_preserve ();
                        rgba (cr, accent);
                        cr.set_line_width (1.5);
                        cr.stroke ();
                    }
                }
            }
            cr.restore ();
        }

        private Chart? chart_at (double x, double y, out bool on_handle) {
            on_handle = false;
            if (x < hw + frozen_w || y < hh + frozen_h) return null;
            for (int i = sheet.charts.size - 1; i >= 0; i--) {
                var ch = sheet.charts[i];
                var rect = chart_rect (ch);
                double rx2 = rect.origin.x + rect.size.width, ry2 = rect.origin.y + rect.size.height;
                if (ch == selected_chart && Math.fabs (x - rx2) < 10 && Math.fabs (y - ry2) < 10) {
                    on_handle = true;
                    return ch;
                }
                if (x >= rect.origin.x && x <= rx2 && y >= rect.origin.y && y <= ry2) return ch;
            }
            return null;
        }

        private int border_col_at (double x, double y) {
            if (y > hh) return -1;
            int c = col_at (x);
            if (c < 0) return -1;
            double right = col_x (c) + col_w (c);
            if (Math.fabs (x - right) <= 4) return c;
            double left = col_x (c);
            if (Math.fabs (x - left) <= 4 && c > 0) {
                int p = c - 1;
                while (p > 0 && col_w (p) == 0) p--;
                return p;
            }
            return -1;
        }

        private int border_row_at (double x, double y) {
            if (x > hw) return -1;
            int r = row_at (y);
            if (r < 0) return -1;
            double bottom = row_y (r) + row_h (r);
            if (Math.fabs (y - bottom) <= 3) return r;
            double top = row_y (r);
            if (Math.fabs (y - top) <= 3 && r > 0) {
                int p = r - 1;
                while (p > 0 && row_h (p) == 0) p--;
                return p;
            }
            return -1;
        }

        private bool on_fill_handle (double x, double y) {
            if (editing) return false;
            var sel = selection;
            if (sel.r2 == MAX_ROWS - 1 || sel.c2 == MAX_COLS - 1) return false;
            double x2 = col_x (sel.c2) + col_w (sel.c2), y2 = row_y (sel.r2) + row_h (sel.r2);
            return Math.fabs (x - x2) <= 6 && Math.fabs (y - y2) <= 6;
        }

        private bool on_filter_button (double x, double y, out int col) {
            col = -1;
            if (sheet.filter == null) return false;
            int r = row_at (y);
            int c = col_at (x);
            if (r != sheet.filter.area.r1 || c < sheet.filter.area.c1 || c > sheet.filter.area.c2) return false;
            var rect = cell_rect (r, c);
            double s = double.min (18 * zoom, rect.size.height - 4);
            if (x >= rect.origin.x + rect.size.width - s - 4) {
                col = c;
                return true;
            }
            return false;
        }

        private bool on_validation_button (double x, double y) {
            foreach (var v in sheet.validations) {
                if (!v.area.contains (cur_row, cur_col)) continue;
                if (v.kind != ValidationKind.LIST || !v.dropdown) continue;
                var rect = cell_rect (cur_row, cur_col);
                double s = double.min (18 * zoom, rect.size.height - 4);
                double bx = rect.origin.x + rect.size.width - s - 3;
                double by = rect.origin.y + (rect.size.height - s) / 2;
                if (x >= bx && x <= bx + s && y >= by && y <= by + s) return true;
            }
            return false;
        }

        private void on_motion (double x, double y) {
            last_x = x;
            last_y = y;
            if (drag != Drag.NONE) return;
            bool handle;
            var ch = chart_at (x, y, out handle);
            Drawing? dr = ch == null ? drawing_at (x, y, out handle) : null;
            if (ch != null || dr != null) set_cursor_from_name (handle ? "nwse-resize" : "move");
            else if (border_col_at (x, y) >= 0) set_cursor_from_name ("col-resize");
            else if (border_row_at (x, y) >= 0) set_cursor_from_name ("row-resize");
            else if (on_fill_handle (x, y)) set_cursor_from_name ("crosshair");
            else set_cursor_from_name ("cell");
        }

        private bool point_mode () {
            if (!editing) return false;
            string t = editor.buffer.text;
            if (!t.has_prefix ("=")) return false;
            TextIter it;
            editor.buffer.get_iter_at_mark (out it, editor.buffer.get_insert ());
            int pos = it.get_offset ();
            if (ref_start >= 0 && pos == ref_end) return true;
            string before = t.substring (0, t.index_of_nth_char (pos)).strip ();
            if (before == "") return false;
            char last = before[before.length - 1];
            return "=(,;+-*/^&<>:".index_of_char (last) >= 0;
        }

        private void on_click (GestureClick g, int n, double x, double y) {
            if (!editing) grab_focus ();
            uint button = g.get_current_button ();
            if (button == Gdk.BUTTON_SECONDARY) {
                bool handle;
                var ch = chart_at (x, y, out handle);
                if (ch != null) {
                    selected_chart = ch;
                    selected_drawing = null;
                    queue_draw ();
                    chart_menu (ch, x, y);
                    return;
                }
                var dm = drawing_at (x, y, out handle);
                if (dm != null) {
                    selected_drawing = dm;
                    selected_chart = null;
                    queue_draw ();
                    drawing_menu (dm, x, y);
                    return;
                }
                int r = row_at (y), c = col_at (x);
                var sel = selection;
                if (r < 0 && c >= 0) {
                    if (!(sel.r1 == 0 && sel.r2 == MAX_ROWS - 1 && c >= sel.c1 && c <= sel.c2)) select_area (new Area (sheet, 0, c, MAX_ROWS - 1, c));
                } else if (c < 0 && r >= 0) {
                    if (!(sel.c1 == 0 && sel.c2 == MAX_COLS - 1 && r >= sel.r1 && r <= sel.r2)) select_area (new Area (sheet, r, 0, r, MAX_COLS - 1));
                } else if (r >= 0 && c >= 0 && !sel.contains (r, c)) {
                    select_cell (r, c, false);
                }
                if (editing) commit_edit (0, 0);
                context_menu (x, y);
                return;
            }
            if (button != Gdk.BUTTON_PRIMARY) return;
            if (n == 1 && ctrl (g.get_current_event_state ()) && !editing) {
                int lr = row_at (y), lc = col_at (x);
                if (lr >= 0 && lc >= 0) {
                    string link = Links.target (doc.book, sheet, lr, lc);
                    if (link != "") {
                        select_cell (lr, lc, false);
                        link_activated (link);
                        return;
                    }
                }
            }
            if (n == 2) {
                bool handle;
                var ch = chart_at (x, y, out handle);
                if (ch != null) {
                    chart_activated (ch);
                    return;
                }
                var dd = drawing_at (x, y, out handle);
                if (dd != null) {
                    drawing_activated (dd);
                    return;
                }
                int bc = border_col_at (x, y);
                if (bc >= 0) {
                    autofit_col (bc);
                    return;
                }
                int br = border_row_at (x, y);
                if (br >= 0) {
                    autofit_row (br);
                    return;
                }
                int r = row_at (y), c = col_at (x);
                if (r >= 0 && c >= 0 && !editing) begin_edit (null, false);
            }
        }

        private void on_drag_begin (double x, double y) {
            if (!editing) grab_focus ();
            drag_start_x = x;
            drag_start_y = y;
            bool handle;
            var ch = chart_at (x, y, out handle);
            if (ch != null) {
                if (editing) commit_edit (0, 0);
                selected_chart = ch;
                chart_x0 = ch.x;
                chart_y0 = ch.y;
                chart_w0 = ch.width;
                chart_h0 = ch.height;
                selected_drawing = null;
                drag = handle ? Drag.CHART_RESIZE : Drag.CHART_MOVE;
                doc.begin_book (handle ? _("Resize Chart") : _("Move Chart"), sheet);
                queue_draw ();
                return;
            }
            var dg = drawing_at (x, y, out handle);
            if (dg != null) {
                if (editing) commit_edit (0, 0);
                selected_drawing = dg;
                selected_chart = null;
                chart_x0 = dg.x;
                chart_y0 = dg.y;
                chart_w0 = dg.width;
                chart_h0 = dg.height;
                drag = handle ? Drag.CHART_RESIZE : Drag.CHART_MOVE;
                doc.begin_book (handle ? _("Resize Object") : _("Move Object"), sheet);
                queue_draw ();
                return;
            }
            if (!editing && OutlineGutter.press (this, x, y)) {
                drag = Drag.NONE;
                return;
            }
            int bc = border_col_at (x, y);
            if (bc >= 0) {
                if (editing) commit_edit (0, 0);
                drag = Drag.RESIZE_COL;
                resize_index = bc;
                return;
            }
            int br = border_row_at (x, y);
            if (br >= 0) {
                if (editing) commit_edit (0, 0);
                drag = Drag.RESIZE_ROW;
                resize_index = br;
                return;
            }
            int fcol = -1;
            if (!editing && on_filter_button (x, y, out fcol)) {
                drag = Drag.NONE;
                filter_clicked (fcol, x, y);
                return;
            }
            if (!editing && on_validation_button (x, y)) {
                drag = Drag.NONE;
                validation_clicked (cur_row, cur_col, x, y);
                return;
            }
            if (on_fill_handle (x, y)) {
                drag = Drag.FILL;
                var sel = selection;
                fill_row = sel.r2;
                fill_col = sel.c2;
                return;
            }
            var state = drag_gesture.get_current_event_state ();
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            int r = row_at (y), c = col_at (x);
            if (point_mode () && r >= 0 && c >= 0) {
                drag = Drag.REFERENCE;
                ref_anchor_row = r;
                ref_anchor_col = c;
                insert_reference (new Area (sheet, r, c, r, c));
                editor.grab_focus ();
                return;
            }
            if (editing) commit_edit (0, 0);
            if (r < 0 && c < 0) {
                select_area (new Area (sheet, 0, 0, MAX_ROWS - 1, MAX_COLS - 1));
                drag = Drag.NONE;
                return;
            }
            if (r < 0) {
                drag = Drag.COLS;
                if (shift) {
                    anchor_row = 0;
                    cur_row = MAX_ROWS - 1;
                    cur_col = c;
                } else {
                    anchor_row = 0;
                    anchor_col = c;
                    cur_row = MAX_ROWS - 1;
                    cur_col = c;
                }
                selected_chart = null;
                selected_drawing = null;
                queue_draw ();
                selection_changed ();
                return;
            }
            if (c < 0) {
                drag = Drag.ROWS;
                if (shift) {
                    anchor_col = 0;
                    cur_col = MAX_COLS - 1;
                    cur_row = r;
                } else {
                    anchor_col = 0;
                    anchor_row = r;
                    cur_col = MAX_COLS - 1;
                    cur_row = r;
                }
                selected_chart = null;
                selected_drawing = null;
                queue_draw ();
                selection_changed ();
                return;
            }
            drag = Drag.SELECT;
            if (ctrl (state) && !shift) {
                var keep = all_areas ();
                adding_area = true;
                select_cell (r, c, false);
                adding_area = false;
                selection_areas = keep;
                queue_draw ();
                return;
            }
            select_cell (r, c, shift);
        }

        private bool adding_area;

        private Area? fill_target () {
            var sel = selection;
            int r = fill_row, c = fill_col;
            int dr = r > sel.r2 ? r - sel.r2 : (r < sel.r1 ? r - sel.r1 : 0);
            int dc = c > sel.c2 ? c - sel.c2 : (c < sel.c1 ? c - sel.c1 : 0);
            if (dr == 0 && dc == 0) return null;
            if (dr.abs () >= dc.abs ()) {
                return dr > 0 ? new Area (sheet, sel.r1, sel.c1, r, sel.c2) : new Area (sheet, r, sel.c1, sel.r2, sel.c2);
            }
            return dc > 0 ? new Area (sheet, sel.r1, sel.c1, sel.r2, c) : new Area (sheet, sel.r1, c, sel.r2, sel.c2);
        }

        private void on_drag_update (GestureDrag g, double dx, double dy) {
            double x = drag_start_x + dx, y = drag_start_y + dy;
            last_x = x;
            last_y = y;
            switch (drag) {
                case Drag.RESIZE_COL:
                    double w = double.max ((x - col_x (resize_index)) / zoom, 8);
                    sheet.col_widths[resize_index] = (int) w;
                    refresh ();
                    break;
                case Drag.RESIZE_ROW:
                    double h = double.max ((y - row_y (resize_index)) / zoom, 8);
                    sheet.row_heights[resize_index] = (int) h;
                    refresh ();
                    break;
                case Drag.CHART_MOVE:
                    if (selected_drawing != null) {
                        selected_drawing.x = double.max (0, chart_x0 + dx / zoom);
                        selected_drawing.y = double.max (0, chart_y0 + dy / zoom);
                    } else if (selected_chart != null) {
                        selected_chart.x = double.max (0, chart_x0 + dx / zoom);
                        selected_chart.y = double.max (0, chart_y0 + dy / zoom);
                    }
                    queue_draw ();
                    break;
                case Drag.CHART_RESIZE:
                    if (selected_drawing != null) {
                        bool thin = selected_drawing.kind == DrawingKind.LINE || selected_drawing.kind == DrawingKind.ARROW;
                        selected_drawing.width = double.max (thin ? 0 : 16, chart_w0 + dx / zoom);
                        selected_drawing.height = double.max (thin ? 0 : 16, chart_h0 + dy / zoom);
                    } else if (selected_chart != null) {
                        selected_chart.width = double.max (160, chart_w0 + dx / zoom);
                        selected_chart.height = double.max (120, chart_h0 + dy / zoom);
                    }
                    queue_draw ();
                    break;
                default:
                    drag_select_to (x, y);
                    start_autoscroll ();
                    break;
            }
        }

        private void drag_select_to (double x, double y) {
            int r = row_at (double.max (y, hh + 1)), c = col_at (double.max (x, hw + 1));
            r = r.clamp (0, MAX_ROWS - 1);
            c = c.clamp (0, MAX_COLS - 1);
            switch (drag) {
                case Drag.SELECT:
                    if (r != cur_row || c != cur_col) {
                        cur_row = r;
                        cur_col = c;
                        queue_draw ();
                        selection_changed ();
                    }
                    break;
                case Drag.COLS:
                    cur_col = c;
                    queue_draw ();
                    selection_changed ();
                    break;
                case Drag.ROWS:
                    cur_row = r;
                    queue_draw ();
                    selection_changed ();
                    break;
                case Drag.FILL:
                    fill_row = r;
                    fill_col = c;
                    queue_draw ();
                    break;
                case Drag.REFERENCE:
                    insert_reference (new Area (sheet, ref_anchor_row, ref_anchor_col, r, c));
                    break;
                default:
                    break;
            }
        }

        private void start_autoscroll () {
            if (autoscroll_id != 0) return;
            autoscroll_id = Timeout.add (40, () => {
                if (drag == Drag.NONE || drag == Drag.RESIZE_COL || drag == Drag.RESIZE_ROW || drag == Drag.CHART_MOVE || drag == Drag.CHART_RESIZE) {
                    autoscroll_id = 0;
                    return Source.REMOVE;
                }
                double w = get_width (), h = get_height ();
                bool moved = false;
                if (last_y > h - 8 && _vadj != null) {
                    _vadj.value += 20 * zoom;
                    moved = true;
                } else if (last_y < hh + frozen_h + 4 && _vadj != null && _vadj.value > 0) {
                    _vadj.value = double.max (0, _vadj.value - 20 * zoom);
                    moved = true;
                }
                if (last_x > w - 8 && _hadj != null) {
                    _hadj.value += 30 * zoom;
                    moved = true;
                } else if (last_x < hw + frozen_w + 4 && _hadj != null && _hadj.value > 0) {
                    _hadj.value = double.max (0, _hadj.value - 30 * zoom);
                    moved = true;
                }
                if (moved) drag_select_to (last_x, last_y);
                return Source.CONTINUE;
            });
        }

        private void on_drag_end (double dx, double dy) {
            var d = drag;
            drag = Drag.NONE;
            if (autoscroll_id != 0) {
                Source.remove (autoscroll_id);
                autoscroll_id = 0;
            }
            switch (d) {
                case Drag.RESIZE_COL:
                    int w = sheet.col_widths[resize_index];
                    var sel = selection;
                    if (sel.r1 == 0 && sel.r2 == MAX_ROWS - 1 && resize_index >= sel.c1 && resize_index <= sel.c2) doc.set_col_width (sheet, sel.c1, sel.c2, w);
                    else doc.set_col_width (sheet, resize_index, resize_index, w);
                    break;
                case Drag.RESIZE_ROW:
                    int h = sheet.row_heights[resize_index];
                    var sel = selection;
                    if (sel.c1 == 0 && sel.c2 == MAX_COLS - 1 && resize_index >= sel.r1 && resize_index <= sel.r2) doc.set_row_height (sheet, sel.r1, sel.r2, h);
                    else doc.set_row_height (sheet, resize_index, resize_index, h);
                    break;
                case Drag.FILL:
                    var target = fill_target ();
                    if (target != null) {
                        var src = selection;
                        if (target.r2 < src.r2 || target.c2 < src.c2) {
                            if (target.r1 == src.r1 && target.c1 == src.c1) {
                                var clear = target.r2 < src.r2 ? new Area (sheet, target.r2 + 1, src.c1, src.r2, src.c2) : new Area (sheet, src.r1, target.c2 + 1, src.r2, src.c2);
                                doc.clear (sheet, clear, ClearMode.CONTENTS);
                                select_area (target);
                            } else {
                                doc.fill_series (sheet, src, target);
                                select_area (target);
                            }
                        } else {
                            doc.fill_series (sheet, src, target);
                            select_area (target);
                        }
                    }
                    queue_draw ();
                    break;
                case Drag.CHART_MOVE:
                case Drag.CHART_RESIZE:
                    doc.commit ();
                    break;
                default:
                    break;
            }
        }

        public void autofit_col (int c) {
            double best = 30;
            var probe = new TextJob ();
            int limit = int.min (sheet.max_row, 20000);
            for (int r = 0; r <= limit; r++) {
                var cell = sheet.get_cell (r, c);
                if (cell == null || sheet.merge_at (r, c) != null) continue;
                var v = doc.book.cell_value (sheet, cell);
                if (v.kind == ValueKind.EMPTY) continue;
                probe.style = doc.book.styles[cell.style];
                probe.bold = probe.style.bold;
                probe.italic = probe.style.italic;
                string color;
                probe.text = NumberFormat.format_value (v, probe.style.number_format, out color, doc.book.date1904);
                if (probe.style.wrap) continue;
                var l = make_layout (probe);
                int tw, th;
                l.get_pixel_size (out tw, out th);
                best = double.max (best, tw / zoom + 12);
            }
            var sel = selection;
            if (sel.r1 == 0 && sel.r2 == MAX_ROWS - 1 && c >= sel.c1 && c <= sel.c2 && sel.c1 != sel.c2) {
                for (int k = sel.c1; k <= sel.c2; k++) if (k != c) autofit_col (k);
            }
            doc.set_col_width (sheet, c, c, (int) Math.ceil (best));
        }

        public void autofit_row (int r) {
            double best = sheet.default_row_height;
            int limit = int.min (sheet.max_col, 2000);
            var probe = new TextJob ();
            for (int c = 0; c <= limit; c++) {
                var cell = sheet.get_cell (r, c);
                if (cell == null) continue;
                var v = doc.book.cell_value (sheet, cell);
                if (v.kind == ValueKind.EMPTY) continue;
                probe.style = doc.book.styles[cell.style];
                probe.bold = probe.style.bold;
                string color;
                probe.text = NumberFormat.format_value (v, probe.style.number_format, out color, doc.book.date1904);
                var l = make_layout (probe);
                if (probe.style.wrap) {
                    l.set_width ((int) ((col_w (c) - 8 * zoom) * Pango.SCALE));
                    l.set_wrap (Pango.WrapMode.WORD_CHAR);
                }
                int tw, th;
                l.get_pixel_size (out tw, out th);
                best = double.max (best, th / zoom + 8);
            }
            doc.set_row_height (sheet, r, r, (int) Math.ceil (best));
        }

        private bool on_tooltip (int x, int y, bool keyboard, Tooltip tooltip) {
            int r = row_at (y), c = col_at (x);
            if (r < 0 || c < 0) return false;
            var cell = sheet.get_cell (r, c);
            string link = Links.target (doc.book, sheet, r, c);
            var tracked = doc.book.revisions.changes.size > 0 ? doc.book.revisions.cell_change (sheet, r, c) : null;
            if (tracked != null) {
                tooltip.set_text (ReviewUi.tooltip (tracked));
                return true;
            }
            var thread = sheet.comments.at (r, c);
            if (thread != null && thread.posts.size > 0) {
                tooltip.set_text (cell != null && cell.note != "" ? cell.note + "\n\n" + CommentsUi.tooltip (thread) : CommentsUi.tooltip (thread));
                return true;
            }
            if (cell != null && cell.note != "") {
                tooltip.set_text (link != "" ? cell.note + "\n\n" + Links.describe (link) + "\n" + _("Ctrl+click to follow the link") : cell.note);
                return true;
            }
            if (link != "") {
                tooltip.set_text (Links.describe (link) + "\n" + _("Ctrl+click to follow the link"));
                return true;
            }
            var v = sheet.value_at (r, c);
            if (v.is_error ()) {
                string msg = "";
                switch (v.error) {
                    case ErrorKind.DIV0: msg = _("Division by zero"); break;
                    case ErrorKind.NA: msg = _("A value is not available"); break;
                    case ErrorKind.NAME: msg = _("Unknown function or name"); break;
                    case ErrorKind.REF: msg = _("The reference is not valid"); break;
                    case ErrorKind.VALUE: msg = _("A value has the wrong type"); break;
                    case ErrorKind.NUM: msg = _("The number is not valid"); break;
                    case ErrorKind.CIRC: msg = _("The formula refers to itself"); break;
                    default: break;
                }
                if (msg != "") {
                    tooltip.set_text (msg);
                    return true;
                }
            }
            return false;
        }

        private bool ctrl (Gdk.ModifierType s) {
            return (s & Gdk.ModifierType.CONTROL_MASK) != 0;
        }

        private int data_edge (int r, int c, int dr, int dc) {
            bool filled_here = !cell_empty (r, c);
            bool filled_next = !cell_empty (r + dr, c + dc);
            int nr = r, nc = c;
            if (filled_here && filled_next) {
                while (in_bounds (nr + dr, nc + dc) && !cell_empty (nr + dr, nc + dc)) {
                    nr += dr;
                    nc += dc;
                }
            } else {
                nr += dr;
                nc += dc;
                int limit = dr != 0 ? int.max (sheet.max_row + 1, 0) : int.max (sheet.max_col + 1, 0);
                while (in_bounds (nr, nc) && cell_empty (nr, nc) && (dr != 0 ? nr : nc) <= limit && (dr < 0 || dc < 0 ? (dr != 0 ? nr : nc) > 0 : true)) {
                    nr += dr;
                    nc += dc;
                }
                if (!in_bounds (nr, nc) || cell_empty (nr, nc)) {
                    if (dr > 0) nr = MAX_ROWS - 1;
                    if (dc > 0) nc = MAX_COLS - 1;
                    if (dr < 0) nr = 0;
                    if (dc < 0) nc = 0;
                }
            }
            return dr != 0 ? nr.clamp (0, MAX_ROWS - 1) : nc.clamp (0, MAX_COLS - 1);
        }

        private bool in_bounds (int r, int c) {
            return r >= 0 && c >= 0 && r < MAX_ROWS && c < MAX_COLS;
        }

        private bool cell_empty (int r, int c) {
            if (!in_bounds (r, c)) return true;
            var cell = sheet.get_cell (r, c);
            return cell == null || (cell.input == "" && cell.formula == null);
        }

        private int next_visible_row (int r, int step) {
            int n = r + step;
            while (n > 0 && n < MAX_ROWS - 1 && rows.size (n) == 0) n += step > 0 ? 1 : -1;
            return n.clamp (0, MAX_ROWS - 1);
        }

        private int next_visible_col (int c, int step) {
            int n = c + step;
            while (n > 0 && n < MAX_COLS - 1 && cols.size (n) == 0) n += step > 0 ? 1 : -1;
            return n.clamp (0, MAX_COLS - 1);
        }

        public void move_cursor (int dr, int dc, bool extend) {
            int r = cur_row, c = cur_col;
            var m = sheet.merge_at (r, c);
            if (m != null) {
                if (dr > 0) r = m.r2;
                if (dc > 0) c = m.c2;
                if (dr < 0) r = m.r1;
                if (dc < 0) c = m.c1;
            }
            if (dr != 0) r = next_visible_row (r, dr);
            if (dc != 0) c = next_visible_col (c, dc);
            if (!extend) {
                var tm = sheet.merge_at (r, c);
                if (tm != null) {
                    r = tm.r1;
                    c = tm.c1;
                }
            }
            select_cell (r, c, extend);
        }

        private void move_in_selection (int dr, int dc) {
            var sel = selection;
            if (sel.is_single ()) {
                move_cursor (dr, dc, false);
                return;
            }
            int r = cur_row + dr, c = cur_col + dc;
            if (r > sel.r2) {
                r = sel.r1;
                c = c + 1 > sel.c2 ? sel.c1 : c + 1;
            } else if (r < sel.r1) {
                r = sel.r2;
                c = c - 1 < sel.c1 ? sel.c2 : c - 1;
            }
            if (c > sel.c2) {
                c = sel.c1;
                r = r + 1 > sel.r2 ? sel.r1 : r + 1;
            } else if (c < sel.c1) {
                c = sel.c2;
                r = r - 1 < sel.r1 ? sel.r2 : r - 1;
            }
            int ar = anchor_row, ac = anchor_col, er = sel.r2, ec = sel.c2;
            anchor_row = sel.r1;
            anchor_col = sel.c1;
            cur_row = r;
            cur_col = c;
            var keep = new Area (sheet, sel.r1, sel.c1, er, ec);
            anchor_row = keep.r1;
            anchor_col = keep.c1;
            active_override_r2 = keep.r2;
            active_override_c2 = keep.c2;
            ar = ac = 0;
            queue_draw ();
            ensure_visible (r, c);
            selection_changed ();
        }

        private int active_override_r2 = -1;
        private int active_override_c2 = -1;

        private bool on_key (uint keyval, uint code, Gdk.ModifierType state) {
            if (editing) return false;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool c = ctrl (state);
            bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
            if (selected_drawing != null) {
                if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.BackSpace) {
                    var dd = selected_drawing;
                    selected_drawing = null;
                    doc.remove_drawing (sheet, dd);
                    return true;
                }
                if (keyval == Gdk.Key.Escape) {
                    selected_drawing = null;
                    queue_draw ();
                    return true;
                }
                if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                    drawing_activated (selected_drawing);
                    return true;
                }
            }
            if (selected_chart != null) {
                if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.BackSpace) {
                    var ch = selected_chart;
                    selected_chart = null;
                    selected_drawing = null;
                    doc.remove_chart (sheet, ch);
                    return true;
                }
                if (keyval == Gdk.Key.Escape) {
                    selected_chart = null;
                    selected_drawing = null;
                    queue_draw ();
                    return true;
                }
            }
            switch (keyval) {
                case Gdk.Key.Up:
                case Gdk.Key.KP_Up:
                    if (c) select_cell (data_edge (cur_row, cur_col, -1, 0), cur_col, shift);
                    else move_cursor (-1, 0, shift);
                    return true;
                case Gdk.Key.Down:
                case Gdk.Key.KP_Down:
                    if (alt) {
                        var items = doc.validation_items (sheet, cur_row, cur_col);
                        if (items.size > 0) {
                            var rect = cell_rect (cur_row, cur_col);
                            validation_clicked (cur_row, cur_col, rect.origin.x + rect.size.width, rect.origin.y + rect.size.height);
                            return true;
                        }
                    }
                    if (c) select_cell (data_edge (cur_row, cur_col, 1, 0), cur_col, shift);
                    else move_cursor (1, 0, shift);
                    return true;
                case Gdk.Key.Left:
                case Gdk.Key.KP_Left:
                    if (c) select_cell (cur_row, data_edge (cur_row, cur_col, 0, -1), shift);
                    else move_cursor (0, -1, shift);
                    return true;
                case Gdk.Key.Right:
                case Gdk.Key.KP_Right:
                    if (c) select_cell (cur_row, data_edge (cur_row, cur_col, 0, 1), shift);
                    else move_cursor (0, 1, shift);
                    return true;
                case Gdk.Key.Home:
                case Gdk.Key.KP_Home:
                    if (c) select_cell (0, 0, shift);
                    else select_cell (cur_row, 0, shift);
                    return true;
                case Gdk.Key.End:
                case Gdk.Key.KP_End:
                    if (c) select_cell (int.max (sheet.max_row, 0), int.max (sheet.max_col, 0), shift);
                    return true;
                case Gdk.Key.Page_Down:
                case Gdk.Key.KP_Page_Down:
                    if (c) return false;
                    if (alt) {
                        select_cell (cur_row, int.min (cur_col + int.max (1, last_visible_col () - first_scroll_col () - 1), MAX_COLS - 1), shift);
                        return true;
                    }
                    int page = int.max (1, last_visible_row () - first_scroll_row () - 1);
                    if (_vadj != null) _vadj.value += page * sheet.default_row_height * zoom;
                    select_cell (int.min (cur_row + page, MAX_ROWS - 1), cur_col, shift);
                    return true;
                case Gdk.Key.Page_Up:
                case Gdk.Key.KP_Page_Up:
                    if (c) return false;
                    if (alt) {
                        select_cell (cur_row, int.max (cur_col - int.max (1, last_visible_col () - first_scroll_col () - 1), 0), shift);
                        return true;
                    }
                    int pg = int.max (1, last_visible_row () - first_scroll_row () - 1);
                    if (_vadj != null) _vadj.value = double.max (0, _vadj.value - pg * sheet.default_row_height * zoom);
                    select_cell (int.max (cur_row - pg, 0), cur_col, shift);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if (selected_chart != null) {
                        chart_activated (selected_chart);
                        return true;
                    }
                    move_in_selection (shift ? -1 : 1, 0);
                    return true;
                case Gdk.Key.Tab:
                    move_in_selection (0, 1);
                    return true;
                case Gdk.Key.ISO_Left_Tab:
                    move_in_selection (0, -1);
                    return true;
                case Gdk.Key.F2:
                    begin_edit (null, false);
                    return true;
                case Gdk.Key.Delete:
                case Gdk.Key.KP_Delete:
                    if (Protect.area_locked (sheet, selection)) {
                        edit_blocked (Protect.message ());
                        return true;
                    }
                    if (selection_areas != null) {
                        foreach (var sa in all_areas ()) {
                            if (Protect.area_locked (sheet, sa)) {
                                edit_blocked (Protect.message ());
                                return true;
                            }
                        }
                        foreach (var sa in all_areas ()) doc.clear (sheet, sa, ClearMode.CONTENTS);
                        return true;
                    }
                    doc.clear (sheet, selection, ClearMode.CONTENTS);
                    return true;
                case Gdk.Key.BackSpace:
                    begin_edit ("", true);
                    return true;
                case Gdk.Key.space:
                    if (c && !shift) {
                        select_area (new Area (sheet, 0, selection.c1, MAX_ROWS - 1, selection.c2));
                        return true;
                    }
                    if (shift && !c) {
                        select_area (new Area (sheet, selection.r1, 0, selection.r2, MAX_COLS - 1));
                        return true;
                    }
                    break;
                case Gdk.Key.Escape:
                    if (doc.clip != null) {
                        doc.clip = null;
                        queue_draw ();
                        return true;
                    }
                    break;
            }
            if (c || alt) return false;
            unichar ch = Gdk.keyval_to_unicode (keyval);
            if (ch != 0 && !ch.iscntrl ()) {
                begin_edit (ch.to_string (), true);
                return true;
            }
            return false;
        }

        public bool is_editing () {
            return editing;
        }

        public string edit_text_for (int r, int c) {
            var cell = sheet.get_cell (r, c);
            if (cell == null) return "";
            if (Protect.hides_formula (sheet, r, c)) return "";
            if (cell.formula != null) return cell.input;
            var v = cell.value;
            var style = doc.book.styles[cell.style];
            if (v.kind == ValueKind.NUMBER && NumberFormat.is_date_format (style.number_format)) {
                string color;
                bool has_time = v.number != Math.floor (v.number);
                bool has_date = v.number >= 1;
                string code = has_date ? LocaleInfo.get ().short_date_format () : "";
                if (has_time) code += (code != "" ? " " : "") + "h:mm:ss";
                return NumberFormat.format (v.number, code, out color, doc.book.date1904);
            }
            if (v.kind == ValueKind.NUMBER && style.number_format.contains ("%")) {
                return NumberFormat.general (v.number * 100) + "%";
            }
            if (v.kind == ValueKind.NUMBER) return NumberFormat.general (v.number);
            return cell.input;
        }

        public void begin_edit (string? initial, bool enter) {
            if (editing) return;
            if (Protect.cell_locked (sheet, cur_row, cur_col)) {
                edit_blocked (Protect.message ());
                return;
            }
            var sel = selection;
            if (sel.r2 == MAX_ROWS - 1 || sel.c2 == MAX_COLS - 1) {
                anchor_row = cur_row;
                anchor_col = cur_col;
            }
            var m = sheet.merge_at (cur_row, cur_col);
            edit_row = m != null ? m.r1 : cur_row;
            edit_col = m != null ? m.c1 : cur_col;
            editing = true;
            enter_mode = enter;
            ref_start = ref_end = -1;
            ensure_visible (edit_row, edit_col);
            syncing = true;
            editor.buffer.text = initial ?? edit_text_for (edit_row, edit_col);
            syncing = false;
            var style = doc.book.styles[sheet.get_cell (edit_row, edit_col) != null ? sheet.get_cell (edit_row, edit_col).style : 0];
            var css = new CssProvider ();
            string size = Value.fixed (style.font_size * 96 / 72 * zoom, 1);
            css.load_from_string ("textview { font-size: %spx; %s%s }".printf (size, style.bold ? "font-weight: bold; " : "", style.italic ? "font-style: italic; " : ""));
            editor.get_style_context ().add_provider (css, STYLE_PROVIDER_PRIORITY_USER + 20);
            editor_scroll.visible = true;
            queue_allocate ();
            editor.grab_focus ();
            TextIter end;
            editor.buffer.get_end_iter (out end);
            editor.buffer.place_cursor (end);
            highlight_refs ();
            editing_changed (editor.buffer.text, true);
            queue_draw ();
        }

        public void set_edit_text (string text) {
            if (!editing) begin_edit (text, false);
            syncing = true;
            editor.buffer.text = text;
            syncing = false;
            highlight_refs ();
            queue_allocate ();
            queue_draw ();
        }

        public void cancel_edit () {
            if (!editing) return;
            editing = false;
            editor_scroll.visible = false;
            assist.popdown ();
            hint_pop.popdown ();
            grab_focus ();
            editing_changed ("", false);
            queue_draw ();
        }

        public void commit_edit (int dr, int dc, bool fill_selection = false) {
            if (!editing) return;
            string text = editor.buffer.text;
            if (!fill_selection || selection.is_single ()) {
                var rule = ValidationCheck.at (sheet, edit_row, edit_col);
                if (rule != null && rule.show_error && !text.has_prefix ("=") && !ValidationCheck.valid (doc.book, sheet, rule, edit_row, edit_col, ValidationCheck.candidate (text))) {
                    pending_dr = dr;
                    pending_dc = dc;
                    entry_rejected (edit_row, edit_col, text, rule);
                    return;
                }
            }
            editing = false;
            editor_scroll.visible = false;
            assist.popdown ();
            hint_pop.popdown ();
            if (text.has_prefix ("=")) text = balance_parens (text);
            var sel = selection;
            if (fill_selection && !sel.is_single ()) {
                doc.fill_input (sheet, sel, text);
            } else {
                doc.set_input (sheet, edit_row, edit_col, text);
            }
            editing_changed ("", false);
            grab_focus ();
            if (dr != 0 || dc != 0) move_in_selection (dr, dc);
            queue_draw ();
        }

        private void commit_array () {
            string text = balance_parens (editor.buffer.text);
            editing = false;
            editor_scroll.visible = false;
            assist.popdown ();
            hint_pop.popdown ();
            var sel = selection.is_single () ? new Area.cell (sheet, edit_row, edit_col) : selection;
            doc.set_array_formula (sheet, sel, text);
            editing_changed ("", false);
            grab_focus ();
            queue_draw ();
        }

        private int pending_dr;
        private int pending_dc;

        public void accept_rejected () {
            if (!editing) return;
            string text = editor.buffer.text;
            editing = false;
            editor_scroll.visible = false;
            assist.popdown ();
            hint_pop.popdown ();
            doc.set_input (sheet, edit_row, edit_col, text);
            editing_changed ("", false);
            grab_focus ();
            if (pending_dr != 0 || pending_dc != 0) move_in_selection (pending_dr, pending_dc);
            queue_draw ();
        }

        public void retry_rejected () {
            if (!editing) return;
            editor.grab_focus ();
            TextIter start, end;
            editor.buffer.get_bounds (out start, out end);
            editor.buffer.select_range (start, end);
        }

        private static string balance_parens (string t) {
            int depth = 0;
            bool q = false;
            for (int i = 0; i < t.length; i++) {
                if (t[i] == '"') q = !q;
                if (q) continue;
                if (t[i] == '(') depth++;
                else if (t[i] == ')') depth--;
            }
            string r = t;
            for (int i = 0; i < depth; i++) r += ")";
            return r;
        }

        private bool on_editor_key (uint keyval, uint code, Gdk.ModifierType state) {
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
            bool c = ctrl (state);
            if (assist.visible) {
                if (keyval == Gdk.Key.Down || keyval == Gdk.Key.Up) {
                    var row = assist_list.get_selected_row ();
                    int i = row != null ? row.get_index () : -1;
                    var next = assist_list.get_row_at_index (i + (keyval == Gdk.Key.Down ? 1 : -1));
                    if (next != null) assist_list.select_row (next);
                    return true;
                }
                if (keyval == Gdk.Key.Tab || ((keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) && !c && !alt)) {
                    var row = assist_list.get_selected_row () ?? assist_list.get_row_at_index (0);
                    if (row != null) {
                        complete_function (row.get_data<string> ("fn"));
                        return true;
                    }
                }
                if (keyval == Gdk.Key.Escape) {
                    assist.popdown ();
                    return true;
                }
            }
            switch (keyval) {
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if (alt) {
                        editor.buffer.insert_at_cursor ("\n", -1);
                        return true;
                    }
                    if (c && shift && editor.buffer.text.has_prefix ("=")) {
                        commit_array ();
                        return true;
                    }
                    commit_edit (c ? 0 : (shift ? -1 : 1), 0, c);
                    return true;
                case Gdk.Key.Tab:
                    commit_edit (0, 1);
                    return true;
                case Gdk.Key.ISO_Left_Tab:
                    commit_edit (0, -1);
                    return true;
                case Gdk.Key.Escape:
                    cancel_edit ();
                    return true;
                case Gdk.Key.F4:
                    toggle_absolute ();
                    return true;
                case Gdk.Key.F2:
                    enter_mode = !enter_mode;
                    return true;
                case Gdk.Key.Up:
                case Gdk.Key.Down:
                case Gdk.Key.Left:
                case Gdk.Key.Right:
                    if (!enter_mode) return false;
                    if (point_mode () || (ref_start >= 0 && ref_end == cursor_offset ())) {
                        int r = ref_start >= 0 ? ref_anchor_row : edit_row;
                        int col = ref_start >= 0 ? ref_anchor_col : edit_col;
                        if (keyval == Gdk.Key.Up) r = int.max (r - 1, 0);
                        if (keyval == Gdk.Key.Down) r = int.min (r + 1, MAX_ROWS - 1);
                        if (keyval == Gdk.Key.Left) col = int.max (col - 1, 0);
                        if (keyval == Gdk.Key.Right) col = int.min (col + 1, MAX_COLS - 1);
                        ref_anchor_row = r;
                        ref_anchor_col = col;
                        insert_reference (new Area (sheet, r, col, r, col));
                        return true;
                    }
                    int dr = keyval == Gdk.Key.Up ? -1 : (keyval == Gdk.Key.Down ? 1 : 0);
                    int dc = keyval == Gdk.Key.Left ? -1 : (keyval == Gdk.Key.Right ? 1 : 0);
                    commit_edit (0, 0);
                    move_cursor (dr, dc, false);
                    return true;
            }
            return false;
        }

        private int cursor_offset () {
            TextIter it;
            editor.buffer.get_iter_at_mark (out it, editor.buffer.get_insert ());
            return it.get_offset ();
        }

        private void insert_reference (Area a) {
            var buf = editor.buffer;
            string text = a.is_single () ? Address.cell (a.r1, a.c1) : Address.cell (a.r1, a.c1) + ":" + Address.cell (a.r2, a.c2);
            syncing = true;
            if (ref_start >= 0 && ref_end >= ref_start && ref_end <= buf.text.char_count ()) {
                TextIter s, e;
                buf.get_iter_at_offset (out s, ref_start);
                buf.get_iter_at_offset (out e, ref_end);
                buf.delete (ref s, ref e);
                buf.get_iter_at_offset (out s, ref_start);
                buf.insert (ref s, text, -1);
            } else {
                ref_start = cursor_offset ();
                buf.insert_at_cursor (text, -1);
            }
            ref_end = ref_start + text.char_count ();
            TextIter c;
            buf.get_iter_at_offset (out c, ref_end);
            buf.place_cursor (c);
            syncing = false;
            highlight_refs ();
            editing_changed (buf.text, true);
            queue_allocate ();
            queue_draw ();
        }

        private void toggle_absolute () {
            var buf = editor.buffer;
            string t = buf.text;
            int pos = cursor_offset ();
            int bpos = t.index_of_nth_char (pos);
            try {
                var re = new Regex ("\\$?[A-Za-z]{1,3}\\$?[0-9]+");
                MatchInfo info;
                if (re.match (t, 0, out info)) {
                    do {
                        int s, e;
                        info.fetch_pos (0, out s, out e);
                        if (bpos >= s && bpos <= e) {
                            string refs = info.fetch (0);
                            bool ac = refs.has_prefix ("$");
                            string core = refs.replace ("$", "");
                            int i = 0;
                            while (i < core.length && core[i].isalpha ()) i++;
                            string letters = core.substring (0, i), digits = core.substring (i);
                            bool ar = refs.substring (1).contains ("$");
                            string next;
                            if (!ac && !ar) next = "$" + letters + "$" + digits;
                            else if (ac && ar) next = letters + "$" + digits;
                            else if (!ac && ar) next = "$" + letters + digits;
                            else next = letters + digits;
                            syncing = true;
                            TextIter si, ei;
                            buf.get_iter_at_offset (out si, t.substring (0, s).char_count ());
                            buf.get_iter_at_offset (out ei, t.substring (0, e).char_count ());
                            buf.delete (ref si, ref ei);
                            buf.get_iter_at_offset (out si, t.substring (0, s).char_count ());
                            buf.insert (ref si, next, -1);
                            buf.place_cursor (si);
                            syncing = false;
                            highlight_refs ();
                            editing_changed (buf.text, true);
                            return;
                        }
                    } while (info.next ());
                }
            } catch (RegexError e) {
            }
        }

        private bool completing;
        private int last_edit_len;

        private void on_editor_changed () {
            if (syncing) return;
            if (!completing && enter_mode) {
                string t = editor.buffer.text;
                int len = t.char_count ();
                bool grew = len > last_edit_len;
                last_edit_len = len;
                string? full = grew ? AutoComplete.complete (sheet, edit_row, edit_col, t) : null;
                if (full != null && cursor_offset () == len) {
                    completing = true;
                    syncing = true;
                    TextIter end;
                    editor.buffer.get_end_iter (out end);
                    editor.buffer.insert (ref end, full.substring (full.index_of_nth_char (len)), -1);
                    TextIter a, b;
                    editor.buffer.get_iter_at_offset (out a, len);
                    editor.buffer.get_end_iter (out b);
                    editor.buffer.select_range (b, a);
                    syncing = false;
                    completing = false;
                }
            }
            int pos = cursor_offset ();
            if (ref_start >= 0 && pos != ref_end) ref_start = ref_end = -1;
            highlight_refs ();
            update_assist ();
            editing_changed (editor.buffer.text, true);
            queue_allocate ();
            queue_draw ();
        }

        private class RefBox {
            public Area area;
            public string color;
        }

        private Gee.ArrayList<RefBox> ref_boxes = new Gee.ArrayList<RefBox> ();

        public class RefSpan {
            public int start;
            public int end;
            public string ref_text;
            public string color;
        }

        public static Gee.List<RefSpan> ref_spans (string t) {
            var spans = new Gee.ArrayList<RefSpan> ();
            if (!t.has_prefix ("=")) return spans;
            var colors = new Gee.HashMap<string, string> ();
            try {
                var re = new Regex ("(?:'(?:[^']|'')+'|[A-Za-z_][A-Za-z0-9_.]*)?!?\\$?[A-Za-z]{1,3}\\$?[0-9]+(?::\\$?[A-Za-z]{1,3}\\$?[0-9]+)?");
                MatchInfo info;
                if (!re.match (t, 0, out info)) return spans;
                bool q = false;
                int qpos = 0;
                do {
                    int ms, me;
                    info.fetch_pos (0, out ms, out me);
                    for (; qpos < ms; qpos++) if (t[qpos] == '"') q = !q;
                    if (q) continue;
                    if (ms > 0 && (t[ms - 1].isalnum () || t[ms - 1] == '_')) continue;
                    if (me < t.length && (t[me] == '(' || t[me].isalnum ())) continue;
                    string m = info.fetch (0);
                    if (m.has_prefix ("!")) continue;
                    string key = m.replace ("$", "").up ();
                    if (!colors.has_key (key)) colors[key] = REF_COLORS[colors.size % REF_COLORS.length];
                    var sp = new RefSpan ();
                    sp.start = ms;
                    sp.end = me;
                    sp.ref_text = m;
                    sp.color = colors[key];
                    spans.add (sp);
                } while (info.next ());
            } catch (RegexError e) {
            }
            return spans;
        }

        public static Pango.AttrList formula_attrs (string t) {
            var attrs = new Pango.AttrList ();
            foreach (var sp in ref_spans (t)) {
                Gdk.RGBA c = Gdk.RGBA ();
                c.parse (sp.color);
                var fg = Pango.attr_foreground_new ((uint16) (c.red * 65535), (uint16) (c.green * 65535), (uint16) (c.blue * 65535));
                fg.start_index = sp.start;
                fg.end_index = sp.end;
                attrs.insert ((owned) fg);
                var w = Pango.attr_weight_new (Pango.Weight.SEMIBOLD);
                w.start_index = sp.start;
                w.end_index = sp.end;
                attrs.insert ((owned) w);
            }
            int depth = 0;
            bool q = false;
            string[] paren = { "#8a8a8a", "#2a78d6", "#1baf7a", "#9085e9" };
            for (int i = 0; i < t.length; i++) {
                char ch = t[i];
                if (ch == '"') {
                    int close = t.index_of_char ('"', i + 1);
                    int end = close < 0 ? t.length : close + 1;
                    Gdk.RGBA c = Gdk.RGBA ();
                    c.parse ("#1e8a3c");
                    var fg = Pango.attr_foreground_new ((uint16) (c.red * 65535), (uint16) (c.green * 65535), (uint16) (c.blue * 65535));
                    fg.start_index = i;
                    fg.end_index = end;
                    attrs.insert ((owned) fg);
                    i = end - 1;
                    continue;
                }
                if (q) continue;
                if (ch == '(' || ch == ')') {
                    if (ch == ')') depth--;
                    Gdk.RGBA c = Gdk.RGBA ();
                    c.parse (paren[int.max (depth, 0) % paren.length]);
                    var fg = Pango.attr_foreground_new ((uint16) (c.red * 65535), (uint16) (c.green * 65535), (uint16) (c.blue * 65535));
                    fg.start_index = i;
                    fg.end_index = i + 1;
                    attrs.insert ((owned) fg);
                    if (ch == '(') depth++;
                }
            }
            return attrs;
        }

        private void highlight_refs () {
            ref_boxes.clear ();
            var buf = editor.buffer;
            TextIter s, e;
            buf.get_bounds (out s, out e);
            buf.remove_all_tags (s, e);
            string t = buf.text;
            foreach (var sp in ref_spans (t)) {
                var tag = buf.create_tag (null, "foreground", sp.color, "weight", 600);
                TextIter ts, te;
                buf.get_iter_at_offset (out ts, t.substring (0, sp.start).char_count ());
                buf.get_iter_at_offset (out te, t.substring (0, sp.end).char_count ());
                buf.apply_tag (tag, ts, te);
                Sheet? target = sheet;
                string addr = sp.ref_text;
                int bang = addr.last_index_of ("!");
                if (bang > 0) {
                    string name = addr.substring (0, bang);
                    if (name.has_prefix ("'")) name = name.substring (1, name.length - 2).replace ("''", "'");
                    target = doc.book.find_sheet (name);
                    addr = addr.substring (bang + 1);
                }
                if (target != sheet) continue;
                var area = Area.parse (addr.replace ("$", ""), target);
                if (area == null) continue;
                var box = new RefBox ();
                box.area = area;
                box.color = sp.color;
                ref_boxes.add (box);
            }
        }

        private void draw_reference_boxes (Cairo.Context cr) {
            foreach (var b in ref_boxes) {
                var a = b.area;
                double x1 = col_x (a.c1), y1 = row_y (a.r1);
                double x2 = col_x (a.c2) + col_w (a.c2), y2 = row_y (a.r2) + row_h (a.r2);
                cr.rectangle (x1 + 0.5, y1 + 0.5, x2 - x1 - 2, y2 - y1 - 2);
                hex (cr, b.color, 0.12);
                cr.fill_preserve ();
                hex (cr, b.color);
                cr.set_line_width (1.5);
                cr.stroke ();
            }
        }

        private string current_word (out int start) {
            string t = editor.buffer.text;
            int pos = cursor_offset ();
            int bpos = t.index_of_nth_char (pos);
            int i = bpos;
            while (i > 0 && (t[i - 1].isalnum () || t[i - 1] == '.' || t[i - 1] == '_')) i--;
            start = t.substring (0, i).char_count ();
            return t.substring (i, bpos - i);
        }

        private void update_assist () {
            string t = editor.buffer.text;
            if (!t.has_prefix ("=")) {
                assist.popdown ();
                return;
            }
            int start;
            string word = current_word (out start);
            if (word.length < 1 || word[0].isdigit () || start == 0) {
                assist.popdown ();
                return;
            }
            string before = t.substring (0, t.index_of_nth_char (start));
            if (before.length > 0 && (before[before.length - 1] == '"' || before[before.length - 1] == '$')) {
                assist.popdown ();
                return;
            }
            string up = word.up ();
            Widget? child;
            while ((child = assist_list.get_first_child ()) != null) assist_list.remove (child);
            var names = new Gee.ArrayList<string> ();
            foreach (var e in Functions.all ().entries) if (e.key.has_prefix (up)) names.add (e.key);
            names.sort ((a, b) => a.length != b.length && (a == up || b == up) ? (a == up ? -1 : 1) : strcmp (a, b));
            int shown = 0;
            foreach (string name in names) {
                if (shown++ >= 40) break;
                var def = Functions.all ()[name];
                var box = new Box (Orientation.VERTICAL, 1);
                var nl = new Label (name);
                nl.add_css_class ("spreadsheet-assist-name");
                nl.halign = Align.START;
                var sl = new Label (def.summary);
                sl.add_css_class ("dim-label");
                sl.add_css_class ("caption");
                sl.halign = Align.START;
                sl.ellipsize = Pango.EllipsizeMode.END;
                sl.max_width_chars = 44;
                sl.width_chars = 34;
                sl.xalign = 0;
                box.append (nl);
                box.append (sl);
                var row = new ListBoxRow ();
                row.child = box;
                row.set_data<string> ("fn", name);
                assist_list.append (row);
            }
            if (shown == 0) {
                assist.popdown ();
                return;
            }
            assist_list.select_row (assist_list.get_row_at_index (0));
            if (!assist.visible) assist.popup ();
        }

        private void complete_function (string name) {
            int start;
            current_word (out start);
            var buf = editor.buffer;
            syncing = true;
            TextIter s, e;
            buf.get_iter_at_offset (out s, start);
            buf.get_iter_at_offset (out e, cursor_offset ());
            buf.delete (ref s, ref e);
            buf.get_iter_at_offset (out s, start);
            buf.insert (ref s, name + "(", -1);
            buf.place_cursor (s);
            syncing = false;
            assist.popdown ();
            highlight_refs ();
            update_hint ();
            editing_changed (buf.text, true);
            editor.grab_focus ();
        }

        private void update_hint () {
            if (!editing || hint_pop == null) return;
            string t = editor.buffer.text;
            if (!t.has_prefix ("=")) {
                hint_pop.popdown ();
                return;
            }
            int bpos = t.index_of_nth_char (cursor_offset ());
            int depth = 0;
            int arg = 0;
            bool q = false;
            string? fn = null;
            for (int i = bpos - 1; i >= 0; i--) {
                char ch = t[i];
                if (ch == '"') q = !q;
                if (q) continue;
                if (ch == ')') depth++;
                else if (ch == '(') {
                    if (depth == 0) {
                        int j = i;
                        while (j > 0 && (t[j - 1].isalnum () || t[j - 1] == '.' || t[j - 1] == '_')) j--;
                        fn = t.substring (j, i - j).up ();
                        break;
                    }
                    depth--;
                } else if ((ch == ',' || ch == ';') && depth == 0) {
                    arg++;
                }
            }
            if (fn == null || fn == "" || !Functions.all ().has_key (fn)) {
                hint_pop.popdown ();
                return;
            }
            var def = Functions.all ()[fn];
            string syntax = def.syntax;
            int open = syntax.index_of ("("), close = syntax.last_index_of (")");
            if (open > 0 && close > open) {
                string[] parts = syntax.substring (open + 1, close - open - 1).split (", ");
                var sb = new StringBuilder ("<b>" + Markup.escape_text (syntax.substring (0, open)) + "</b>(");
                for (int i = 0; i < parts.length; i++) {
                    if (i > 0) sb.append (", ");
                    bool here = i == arg || (i == parts.length - 1 && arg >= parts.length && parts[i].contains ("..."));
                    sb.append (here ? "<b>" + Markup.escape_text (parts[i]) + "</b>" : Markup.escape_text (parts[i]));
                }
                sb.append (")");
                hint.set_markup (sb.str);
            } else {
                hint.set_markup ("<b>" + Markup.escape_text (syntax) + "</b>");
            }
            if (!hint_pop.visible) hint_pop.popup ();
        }

        public void grab_editor () {
            if (editing) editor.grab_focus ();
        }
    }
}
