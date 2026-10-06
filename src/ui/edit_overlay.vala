using Gtk;

namespace Singularity.Apps.Spreadsheet {

    public class EditOverlay {
        private static void set_color (Cairo.Context cr, string hex, Gdk.RGBA fallback) {
            if (hex.length == 7 && hex.has_prefix ("#")) {
                cr.set_source_rgb (Xlsx.hex2 (hex, 1) / 255.0, Xlsx.hex2 (hex, 3) / 255.0, Xlsx.hex2 (hex, 5) / 255.0);
            } else {
                cr.set_source_rgba (fallback.red, fallback.green, fallback.blue, fallback.alpha);
            }
        }

        public static void draw (SheetView v, Cairo.Context cr, int r0, int r1, int c0, int c1, Gdk.RGBA accent) {
            if (v.selection_areas != null) {
                foreach (var a in v.selection_areas) {
                    if (a.sheet != v.sheet) continue;
                    if (a.r2 < r0 || a.r1 > r1 || a.c2 < c0 || a.c1 > c1) continue;
                    double x1 = v.col_x (a.c1), y1 = v.row_y (a.r1);
                    double x2 = v.col_x (a.c2) + v.col_w (a.c2), y2 = v.row_y (a.r2) + v.row_h (a.r2);
                    cr.rectangle (x1, y1, x2 - x1 - 1, y2 - y1 - 1);
                    cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.2);
                    cr.fill_preserve ();
                    cr.set_source_rgba (accent.red, accent.green, accent.blue, 0.8);
                    cr.set_line_width (1);
                    cr.stroke ();
                }
            }
            if (v.invalid_circles != null) {
                foreach (var a in v.invalid_circles) {
                    if (a.sheet != v.sheet) continue;
                    if (a.r1 < r0 || a.r1 > r1 || a.c1 < c0 || a.c1 > c1) continue;
                    var rect = v.cell_rect (a.r1, a.c1);
                    double cx = rect.origin.x + rect.size.width / 2, cy = rect.origin.y + rect.size.height / 2;
                    cr.new_path ();
                    cr.save ();
                    cr.translate (cx, cy);
                    cr.scale (rect.size.width / 2 + 4, rect.size.height / 2 + 3);
                    cr.arc (0, 0, 1, 0, 2 * Math.PI);
                    cr.restore ();
                    cr.set_source_rgb (0.86, 0.12, 0.12);
                    cr.set_line_width (1.8);
                    cr.stroke ();
                }
            }
        }

        public static void draw_rotated (Cairo.Context cr, Pango.Layout layout, Graphene.Rect rect, CellStyle st, double zoom, string color, Gdk.RGBA fg) {
            double x = rect.origin.x, y = rect.origin.y, w = rect.size.width, h = rect.size.height;
            double pad = 3 * zoom;
            cr.save ();
            cr.rectangle (x, y, w - 1, h - 1);
            cr.clip ();
            set_color (cr, color, fg);
            if (st.rotation == 255) {
                string text = layout.get_text ();
                var sb = new StringBuilder ();
                unichar c;
                int i = 0;
                while (text.get_next_char (ref i, out c)) {
                    if (sb.len > 0) sb.append_c ('\n');
                    sb.append_unichar (c);
                }
                layout.set_text (sb.str, -1);
                layout.set_alignment (Pango.Alignment.CENTER);
                int tw, th;
                layout.get_pixel_size (out tw, out th);
                double ty = st.valign == VAlign.TOP ? y + pad : (st.valign == VAlign.CENTER ? y + (h - th) / 2 : y + h - th - pad);
                cr.move_to (x + (w - tw) / 2, ty);
                Pango.cairo_show_layout (cr, layout);
                cr.restore ();
                return;
            }
            int tw, th;
            layout.get_pixel_size (out tw, out th);
            double angle = -st.rotation * Math.PI / 180.0;
            double cos_a = Math.fabs (Math.cos (angle)), sin_a = Math.fabs (Math.sin (angle));
            double bw = tw * cos_a + th * sin_a;
            double bh = tw * sin_a + th * cos_a;
            double cx;
            if (st.halign == HAlign.LEFT) cx = x + pad + bw / 2;
            else if (st.halign == HAlign.RIGHT) cx = x + w - pad - bw / 2;
            else cx = x + w / 2;
            double cy;
            if (st.valign == VAlign.TOP) cy = y + pad + bh / 2;
            else if (st.valign == VAlign.CENTER) cy = y + h / 2;
            else cy = y + h - pad - bh / 2;
            cr.translate (cx, cy);
            cr.rotate (angle);
            cr.move_to (-tw / 2.0, -th / 2.0);
            Pango.cairo_show_layout (cr, layout);
            cr.restore ();
        }

        public static void shrink (Pango.Layout layout, double avail, ref int tw, ref int th) {
            if (tw <= 0 || tw <= avail || avail <= 4) return;
            var fd = layout.get_font_description ().copy ();
            double factor = avail / tw;
            fd.set_absolute_size (fd.get_size () * factor);
            layout.set_font_description (fd);
            layout.get_pixel_size (out tw, out th);
        }
    }
}
