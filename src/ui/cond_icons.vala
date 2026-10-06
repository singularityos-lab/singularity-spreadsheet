namespace Singularity.Apps.Spreadsheet {

    public class CondIconPainter {
        public const string[] SETS = {
            "3Arrows", "3ArrowsGray", "3TrafficLights1", "3Symbols", "3Flags", "3Stars",
            "4Arrows", "4TrafficLights", "4Rating", "5Arrows", "5Rating", "5Quarters"
        };

        private static void rgb (Cairo.Context cr, string hex) {
            string h = hex.substring (1);
            cr.set_source_rgb (("0x" + h.substring (0, 2)).to_int64 () / 255.0, ("0x" + h.substring (2, 2)).to_int64 () / 255.0, ("0x" + h.substring (4, 2)).to_int64 () / 255.0);
        }

        private static string level_color (int idx, int count) {
            if (count == 3) return idx == 0 ? "#e34948" : (idx == 1 ? "#eda100" : "#1baf7a");
            if (count == 4) {
                string[] c4 = { "#e34948", "#eda100", "#8fbf3f", "#1baf7a" };
                return c4[idx];
            }
            string[] c5 = { "#e34948", "#eb6834", "#eda100", "#8fbf3f", "#1baf7a" };
            return c5[idx];
        }

        private static void arrow (Cairo.Context cr, double cx, double cy, double s, double angle) {
            cr.save ();
            cr.translate (cx, cy);
            cr.rotate (angle);
            cr.move_to (0, -s * 0.45);
            cr.line_to (s * 0.4, 0);
            cr.line_to (s * 0.15, 0);
            cr.line_to (s * 0.15, s * 0.45);
            cr.line_to (-s * 0.15, s * 0.45);
            cr.line_to (-s * 0.15, 0);
            cr.line_to (-s * 0.4, 0);
            cr.close_path ();
            cr.fill ();
            cr.restore ();
        }

        private static void star (Cairo.Context cr, double cx, double cy, double r, double fill_ratio) {
            cr.save ();
            for (int i = 0; i < 10; i++) {
                double a = -Math.PI / 2 + i * Math.PI / 5;
                double rr = i % 2 == 0 ? r : r * 0.45;
                if (i == 0) cr.move_to (cx + rr * Math.cos (a), cy + rr * Math.sin (a));
                else cr.line_to (cx + rr * Math.cos (a), cy + rr * Math.sin (a));
            }
            cr.close_path ();
            cr.set_source_rgb (0.93, 0.63, 0.0);
            if (fill_ratio >= 1) cr.fill_preserve ();
            else if (fill_ratio > 0) {
                cr.save ();
                cr.clip_preserve ();
                cr.rectangle (cx - r, cy - r, r * 2 * fill_ratio, r * 2);
                cr.fill ();
                cr.restore ();
            }
            cr.set_line_width (1);
            cr.stroke ();
            cr.restore ();
        }

        public static void draw (Cairo.Context cr, string set, int idx, double x, double y, double size) {
            int count = CondIcons.count (set);
            double cx = x + size / 2, cy = y + size / 2;
            string col = level_color (idx.clamp (0, count - 1), count);
            if (set.has_suffix ("ArrowsGray")) col = "#7f7f7f";
            if (set.contains ("Arrows")) {
                rgb (cr, col);
                double angle;
                if (count == 3) angle = idx == 0 ? Math.PI : (idx == 1 ? Math.PI / 2 : 0);
                else if (count == 4) {
                    double[] a4 = { Math.PI, Math.PI * 0.75, Math.PI * 0.25, 0 };
                    angle = a4[idx];
                } else {
                    double[] a5 = { Math.PI, Math.PI * 0.75, Math.PI / 2, Math.PI * 0.25, 0 };
                    angle = a5[idx];
                }
                arrow (cr, cx, cy, size * 0.9, angle);
                return;
            }
            if (set.contains ("TrafficLights")) {
                rgb (cr, count == 4 && idx == 0 ? "#3a3a3a" : col);
                cr.arc (cx, cy, size * 0.38, 0, Math.PI * 2);
                cr.fill ();
                return;
            }
            if (set == "3Symbols") {
                rgb (cr, col);
                cr.arc (cx, cy, size * 0.42, 0, Math.PI * 2);
                cr.fill ();
                cr.set_source_rgb (1, 1, 1);
                cr.set_line_width (size * 0.12);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                if (idx == 2) {
                    cr.move_to (cx - size * 0.2, cy);
                    cr.line_to (cx - size * 0.05, cy + size * 0.15);
                    cr.line_to (cx + size * 0.2, cy - size * 0.15);
                } else if (idx == 1) {
                    cr.move_to (cx, cy - size * 0.2);
                    cr.line_to (cx, cy + size * 0.05);
                    cr.move_to (cx, cy + size * 0.18);
                    cr.line_to (cx, cy + size * 0.19);
                } else {
                    cr.move_to (cx - size * 0.15, cy - size * 0.15);
                    cr.line_to (cx + size * 0.15, cy + size * 0.15);
                    cr.move_to (cx + size * 0.15, cy - size * 0.15);
                    cr.line_to (cx - size * 0.15, cy + size * 0.15);
                }
                cr.stroke ();
                return;
            }
            if (set == "3Flags") {
                rgb (cr, "#52514e");
                cr.set_line_width (1.2);
                cr.move_to (x + size * 0.25, y + size * 0.1);
                cr.line_to (x + size * 0.25, y + size * 0.9);
                cr.stroke ();
                rgb (cr, col);
                cr.move_to (x + size * 0.28, y + size * 0.12);
                cr.line_to (x + size * 0.85, y + size * 0.3);
                cr.line_to (x + size * 0.28, y + size * 0.5);
                cr.close_path ();
                cr.fill ();
                return;
            }
            if (set == "3Stars") {
                star (cr, cx, cy, size * 0.45, idx / 2.0);
                return;
            }
            if (set.has_suffix ("Rating")) {
                double bw = size / (count + 1);
                for (int i = 0; i < count - 1; i++) {
                    double h = size * (i + 1) / count;
                    if (i < idx) cr.set_source_rgb (0.16, 0.47, 0.84);
                    else cr.set_source_rgba (0.5, 0.5, 0.5, 0.35);
                    cr.rectangle (x + bw * (i + 0.5) + i, y + size - h, bw, h);
                    cr.fill ();
                }
                return;
            }
            if (set == "5Quarters") {
                cr.set_source_rgb (0.35, 0.35, 0.35);
                cr.set_line_width (1);
                cr.arc (cx, cy, size * 0.4, 0, Math.PI * 2);
                cr.stroke ();
                if (idx > 0) {
                    cr.move_to (cx, cy);
                    cr.arc (cx, cy, size * 0.4, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * idx / 4.0);
                    cr.close_path ();
                    cr.fill ();
                }
            }
        }
    }
}
