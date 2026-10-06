namespace Singularity.Apps.Spreadsheet {

    public class Diagrams {
        public const string[] KINDS = { "list", "process", "cycle", "hierarchy", "pyramid", "venn" };

        public static string label (string kind) {
            switch (kind) {
                case "list": return _("Basic List");
                case "process": return _("Process");
                case "cycle": return _("Cycle");
                case "hierarchy": return _("Hierarchy");
                case "pyramid": return _("Pyramid");
                case "venn": return _("Relationship");
                default: return kind;
            }
        }

        private static string color (int i) {
            return Singularity.Charts.ChartPainter.palette_color (i, false);
        }

        private static string darker (string hex) {
            if (hex.length != 7) return hex;
            int r = (int) (Xlsx.hex2 (hex, 1) * 0.72), g = (int) (Xlsx.hex2 (hex, 3) * 0.72), b = (int) (Xlsx.hex2 (hex, 5) * 0.72);
            return "#%02x%02x%02x".printf (r, g, b);
        }

        private static Drawing box (DrawingKind k, int i, string text, double x, double y, double w, double h) {
            var d = new Drawing (k);
            d.fill = color (i);
            d.stroke = darker (d.fill);
            d.stroke_width = 1;
            d.text = text;
            d.text_color = "#ffffff";
            d.font_size = 12;
            d.x = x;
            d.y = y;
            d.width = w;
            d.height = h;
            return d;
        }

        private static Drawing connector (DrawingKind k, double x1, double y1, double x2, double y2) {
            var d = new Drawing (k);
            d.stroke = "#8a8a85";
            d.stroke_width = 2;
            d.x = double.min (x1, x2);
            d.y = double.min (y1, y2);
            d.width = Math.fabs (x2 - x1);
            d.height = Math.fabs (y2 - y1);
            d.flip_h = x2 < x1;
            d.flip_v = y2 < y1;
            return d;
        }

        public static string[] items_of (Drawing group) {
            string[] out_items = {};
            foreach (var c in group.children) {
                if (c.kind == DrawingKind.LINE || c.kind == DrawingKind.ARROW) continue;
                if (c.text.strip () != "") out_items += c.text;
            }
            return out_items;
        }

        public static Drawing build (string kind, string[] raw_items, double w = 520, double h = 300) {
            string[] items = {};
            foreach (string it in raw_items) if (it.strip () != "") items += it.strip ();
            if (items.length == 0) items = { _("Item") };
            var g = new Drawing (DrawingKind.GROUP);
            g.diagram = kind;
            g.fill = "";
            g.stroke = "";
            g.width = w;
            g.height = h;
            g.frame_w = w;
            g.frame_h = h;
            g.name = "Diagram (%s)".printf (kind);
            int n = items.length;
            double gap = 12;
            switch (kind) {
                case "process":
                    double arrow = 28;
                    double bw = (w - (n - 1) * (arrow + 2 * gap)) / n;
                    double bh = double.min (h, bw * 0.8);
                    for (int i = 0; i < n; i++) {
                        double x = i * (bw + arrow + 2 * gap);
                        g.children.add (box (DrawingKind.ROUNDED, i, items[i], x, (h - bh) / 2, bw, bh));
                        if (i < n - 1) g.children.add (connector (DrawingKind.ARROW, x + bw + gap, h / 2, x + bw + gap + arrow, h / 2));
                    }
                    break;
                case "cycle":
                    double cx = w / 2, cy = h / 2;
                    double rad = double.min (w, h) / 2 - double.min (w, h) * 0.16;
                    double ew = double.min (w, h) * 0.3, eh = ew * 0.72;
                    for (int i = 0; i < n; i++) {
                        double a = -Math.PI / 2 + 2 * Math.PI * i / n;
                        g.children.add (box (DrawingKind.ELLIPSE, i, items[i], cx + Math.cos (a) * rad - ew / 2, cy + Math.sin (a) * rad - eh / 2, ew, eh));
                    }
                    for (int i = 0; i < n && n > 1; i++) {
                        double a1 = -Math.PI / 2 + 2 * Math.PI * (i + 0.32) / n;
                        double a2 = -Math.PI / 2 + 2 * Math.PI * (i + 0.68) / n;
                        g.children.add (connector (DrawingKind.ARROW, cx + Math.cos (a1) * rad, cy + Math.sin (a1) * rad, cx + Math.cos (a2) * rad, cy + Math.sin (a2) * rad));
                    }
                    break;
                case "hierarchy":
                    double bh2 = double.min (60, (h - 40) / 2);
                    double rw = double.min (180, w * 0.4);
                    g.children.add (box (DrawingKind.ROUNDED, 0, items[0], (w - rw) / 2, 0, rw, bh2));
                    int kids = n - 1;
                    if (kids > 0) {
                        double kw = (w - (kids - 1) * gap) / kids;
                        double ky = h - bh2;
                        double mid = (bh2 + ky) / 2;
                        g.children.add (connector (DrawingKind.LINE, w / 2, bh2, w / 2, mid));
                        if (kids > 1) g.children.add (connector (DrawingKind.LINE, kw / 2, mid, w - kw / 2, mid));
                        for (int i = 0; i < kids; i++) {
                            double x = i * (kw + gap);
                            g.children.add (connector (DrawingKind.LINE, x + kw / 2, mid, x + kw / 2, ky));
                            g.children.add (box (DrawingKind.ROUNDED, i + 1, items[i + 1], x, ky, kw, bh2));
                        }
                    }
                    break;
                case "pyramid":
                    double lh = (h - (n - 1) * 4) / n;
                    for (int i = 0; i < n; i++) {
                        double lw = w * (i + 1) / n;
                        g.children.add (box (DrawingKind.RECTANGLE, i, items[i], (w - lw) / 2, i * (lh + 4), lw, lh));
                    }
                    break;
                case "venn":
                    int m = int.min (n, 4);
                    double d = double.min (h * 0.95, w / (1 + 0.6 * (m - 1)));
                    double total = d + (m - 1) * d * 0.6;
                    for (int i = 0; i < m; i++) {
                        var e = box (DrawingKind.ELLIPSE, i, "", (w - total) / 2 + i * d * 0.6, (h - d) / 2, d, d);
                        e.opacity = 0.62;
                        g.children.add (e);
                    }
                    for (int i = 0; i < m; i++) {
                        double shift = m == 1 ? 0 : (i == 0 ? -0.18 : (i == m - 1 ? 0.18 : 0));
                        double lx = (w - total) / 2 + i * d * 0.6 + d * (0.2 + shift);
                        var t = box (DrawingKind.RECTANGLE, i, items[i], lx, (h - d * 0.3) / 2, d * 0.6, d * 0.3);
                        t.fill = "";
                        t.stroke = "";
                        t.text_color = "#0b0b0b";
                        g.children.add (t);
                    }
                    break;
                default:
                    double bh3 = (h - (n - 1) * gap) / n;
                    for (int i = 0; i < n; i++) g.children.add (box (DrawingKind.ROUNDED, i, items[i], 0, i * (bh3 + gap), w, bh3));
                    break;
            }
            double common = 12;
            foreach (var c in g.children) {
                if (c.text == "") continue;
                int longest = 1;
                foreach (string word in c.text.split (" ")) longest = int.max (longest, word.char_count ());
                double fit = (c.width - 14) / (longest * 0.6 * 96.0 / 72.0);
                common = double.min (common, Math.floor (fit));
            }
            foreach (var c in g.children) if (c.text != "") c.font_size = double.max (7, common);
            return g;
        }

        public static Drawing rebuild (Drawing old, string kind, string[] items) {
            var g = build (kind, items, old.frame_w > 0 ? old.frame_w : old.width, old.frame_h > 0 ? old.frame_h : old.height);
            g.x = old.x;
            g.y = old.y;
            g.width = old.width;
            g.height = old.height;
            g.alt_text = old.alt_text;
            return g;
        }

        public static string kind_from_name (string name) {
            int a = name.last_index_of ("(");
            int b = name.last_index_of (")");
            if (a < 0 || b <= a) return "";
            string k = name.substring (a + 1, b - a - 1);
            foreach (string known in KINDS) if (known == k) return k;
            return "";
        }
    }
}
