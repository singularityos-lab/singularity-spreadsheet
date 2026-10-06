using Gtk;

namespace Singularity.Apps.Spreadsheet {

    public class OutlineGutter {
        public const double STEP = 16;

        public static double size (Sheet s, bool rows, double zoom) {
            int l = s.outline.max_level (rows);
            return l > 0 ? Math.round ((l + 1) * STEP * zoom) : 0;
        }

        private static void box (Cairo.Context cr, double cx, double cy, double sz, Gdk.RGBA fg, string symbol) {
            double x = Math.round (cx - sz / 2) + 0.5, y = Math.round (cy - sz / 2) + 0.5;
            cr.rectangle (x, y, sz, sz);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.08);
            cr.fill_preserve ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.55);
            cr.set_line_width (1);
            cr.stroke ();
            cr.move_to (x + sz * 0.25, y + sz / 2);
            cr.line_to (x + sz * 0.75, y + sz / 2);
            if (symbol == "+") {
                cr.move_to (x + sz / 2, y + sz * 0.25);
                cr.line_to (x + sz / 2, y + sz * 0.75);
            }
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.85);
            cr.set_line_width (1.4);
            cr.stroke ();
        }

        private static void level_button (SheetView v, Cairo.Context cr, double x, double y, double sz, int n, Gdk.RGBA fg) {
            cr.rectangle (Math.round (x) + 0.5, Math.round (y) + 0.5, sz, sz);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.1);
            cr.fill_preserve ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.45);
            cr.set_line_width (1);
            cr.stroke ();
            var layout = v.create_pango_layout (n.to_string ());
            var font = v.get_pango_context ().get_font_description ().copy ();
            font.set_absolute_size (9 * v.zoom * Pango.SCALE);
            font.set_weight (Pango.Weight.BOLD);
            layout.set_font_description (font);
            int tw, th;
            layout.get_pixel_size (out tw, out th);
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.8);
            cr.move_to (x + (sz - tw) / 2 + 0.5, y + (sz - th) / 2 + 0.5);
            Pango.cairo_show_layout (cr, layout);
        }

        public static void draw (SheetView v, Cairo.Context cr, double w, double h, Gdk.RGBA fg) {
            var s = v.sheet;
            double z = v.zoom;
            double gw = v.gutter_w, gh = v.gutter_h;
            double hw = v.corner_w, hh = v.corner_h;
            double sz = Math.round (11 * z);
            if (gw > 0) {
                int max = s.outline.max_level (true);
                for (int n = 1; n <= max + 1; n++) level_button (v, cr, (n - 1) * STEP * z + (STEP * z - sz) / 2, hh - sz - 4 * z, sz, n, fg);
                cr.save ();
                cr.rectangle (0, hh, gw, h - hh);
                cr.clip ();
                foreach (var g in s.outline.groups (true)) {
                    double x = (g.level - 1) * STEP * z + STEP * z / 2;
                    double y1 = v.row_y (g.start), y2 = v.row_y (g.end) + v.row_h (g.end);
                    if (y2 < hh || y1 > h) continue;
                    bool after = s.outline.summary_below;
                    if (!g.collapsed && y2 - y1 > 2) {
                        cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.5);
                        cr.set_line_width (1.2);
                        cr.move_to (Math.round (x) + 0.5, after ? y1 + 3 : y2 - 3);
                        cr.line_to (Math.round (x) + 0.5, after ? y2 : y1);
                        cr.stroke ();
                        cr.move_to (Math.round (x) + 0.5, after ? y1 + 3 : y2 - 3);
                        cr.line_to (Math.round (x) + 5 * z, after ? y1 + 3 : y2 - 3);
                        cr.stroke ();
                    }
                    int summary = g.summary;
                    if (summary < 0 || summary >= MAX_ROWS) continue;
                    if (v.row_h (summary) == 0) continue;
                    double cy = v.row_y (summary) + v.row_h (summary) / 2;
                    box (cr, x, cy, sz, fg, g.collapsed ? "+" : "-");
                }
                cr.restore ();
            }
            if (gh > 0) {
                int max = s.outline.max_level (false);
                for (int n = 1; n <= max + 1; n++) level_button (v, cr, hw - sz - 4 * z, (n - 1) * STEP * z + (STEP * z - sz) / 2, sz, n, fg);
                cr.save ();
                cr.rectangle (hw, 0, w - hw, gh);
                cr.clip ();
                foreach (var g in s.outline.groups (false)) {
                    double y = (g.level - 1) * STEP * z + STEP * z / 2;
                    double x1 = v.col_x (g.start), x2 = v.col_x (g.end) + v.col_w (g.end);
                    if (x2 < hw || x1 > w) continue;
                    bool after = s.outline.summary_right;
                    if (!g.collapsed && x2 - x1 > 2) {
                        cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.5);
                        cr.set_line_width (1.2);
                        cr.move_to (after ? x1 + 3 : x2 - 3, Math.round (y) + 0.5);
                        cr.line_to (after ? x2 : x1, Math.round (y) + 0.5);
                        cr.stroke ();
                        cr.move_to (after ? x1 + 3 : x2 - 3, Math.round (y) + 0.5);
                        cr.line_to (after ? x1 + 3 : x2 - 3, Math.round (y) + 5 * z);
                        cr.stroke ();
                    }
                    int summary = g.summary;
                    if (summary < 0 || summary >= MAX_COLS) continue;
                    if (v.col_w (summary) == 0) continue;
                    double cx = v.col_x (summary) + v.col_w (summary) / 2;
                    box (cr, cx, y, sz, fg, g.collapsed ? "+" : "-");
                }
                cr.restore ();
            }
        }

        public static bool press (SheetView v, double x, double y) {
            var s = v.sheet;
            double z = v.zoom;
            double gw = v.gutter_w, gh = v.gutter_h;
            double hw = v.corner_w, hh = v.corner_h;
            double sz = Math.round (11 * z);
            if (gw > 0 && x < gw) {
                if (y < hh) {
                    int n = (int) (x / (STEP * z)) + 1;
                    if (y >= hh - sz - 6 * z && n <= s.outline.max_level (true) + 1) EditCommands.show_level (v.doc, s, true, n);
                    return true;
                }
                int lv = (int) (x / (STEP * z)) + 1;
                int r = v.row_at (y);
                if (r >= 0) {
                    var g = s.outline.group_for_summary (true, r, lv);
                    if (g != null) EditCommands.collapse (v.doc, s, true, g, !g.collapsed);
                }
                return true;
            }
            if (gh > 0 && y < gh) {
                if (x < hw) {
                    int n = (int) (y / (STEP * z)) + 1;
                    if (x >= hw - sz - 6 * z && n <= s.outline.max_level (false) + 1) EditCommands.show_level (v.doc, s, false, n);
                    return true;
                }
                int lv = (int) (y / (STEP * z)) + 1;
                int c = v.col_at (x);
                if (c >= 0) {
                    var g = s.outline.group_for_summary (false, c, lv);
                    if (g != null) EditCommands.collapse (v.doc, s, false, g, !g.collapsed);
                }
                return true;
            }
            return false;
        }
    }
}
