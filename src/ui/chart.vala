namespace Singularity.Apps.Spreadsheet {

    public class ChartData {
        public Singularity.Charts.ChartSpec spec;
        public Workbook book;

        public static ChartData from (Workbook book, Sheet own, Chart chart) {
            var d = new ChartData ();
            d.book = book;
            d.spec = ChartResolve.resolve (book, own, chart);
            return d;
        }
    }

    public class ChartRenderer {
        public static string series_color (int i, bool dark) {
            return Singularity.Charts.ChartPainter.palette_color (i, dark);
        }

        public static Singularity.Charts.ChartPainter painter (Workbook book, bool dark, bool selected) {
            var p = new Singularity.Charts.ChartPainter ();
            p.dark = dark;
            p.selected = selected;
            bool d1904 = book.date1904;
            p.set_formatter ((v, fmt) => {
                string color;
                return NumberFormat.format_value (Value.num (v), fmt, out color, d1904);
            });
            return p;
        }

        public static void draw (Cairo.Context cr, Chart chart, ChartData data, double w, double h, bool dark, bool selected) {
            painter (data.book, dark, selected).draw (cr, data.spec, w, h);
        }

        private static void rgb (Cairo.Context cr, string hex, double alpha = 1) {
            if (hex.length != 7) {
                cr.set_source_rgba (0.5, 0.5, 0.5, alpha);
                return;
            }
            cr.set_source_rgba (Xlsx.hex2 (hex, 1) / 255.0, Xlsx.hex2 (hex, 3) / 255.0, Xlsx.hex2 (hex, 5) / 255.0, alpha);
        }

        private static Gee.HashMap<Bytes, Gdk.Texture>? textures;

        private static Gdk.Texture? texture_of (Bytes data) {
            if (textures == null) textures = new Gee.HashMap<Bytes, Gdk.Texture> ();
            if (textures.has_key (data)) return textures[data];
            try {
                var t = Gdk.Texture.from_bytes (data);
                textures[data] = t;
                return t;
            } catch (Error e) {
                return null;
            }
        }

        private static Cairo.ImageSurface? surface_of (Gdk.Texture t) {
            int w = t.get_width (), h = t.get_height ();
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            surf.flush ();
            unowned uchar[] pixels = surf.get_data ();
            pixels.length = surf.get_stride () * h;
            t.download (pixels, surf.get_stride ());
            surf.mark_dirty ();
            return surf;
        }

        private static Gee.HashMap<Bytes, Cairo.ImageSurface>? surfaces;

        public static void draw_drawing (Cairo.Context cr, Drawing d, double w, double h, bool dark, bool selected) {
            cr.save ();
            switch (d.kind) {
                case DrawingKind.GROUP:
                    double fw = d.frame_w > 0 ? d.frame_w : w, fh = d.frame_h > 0 ? d.frame_h : h;
                    cr.scale (fw > 0 ? w / fw : 1, fh > 0 ? h / fh : 1);
                    foreach (var child in d.children) {
                        cr.save ();
                        cr.translate (child.x, child.y);
                        draw_drawing (cr, child, child.width, child.height, dark, false);
                        cr.restore ();
                    }
                    break;
                case DrawingKind.IMAGE:
                    Cairo.ImageSurface? surf = null;
                    if (d.image != null) {
                        if (surfaces == null) surfaces = new Gee.HashMap<Bytes, Cairo.ImageSurface> ();
                        surf = surfaces[d.image];
                        if (surf == null) {
                            var t = texture_of (d.image);
                            if (t != null) {
                                surf = surface_of (t);
                                surfaces[d.image] = surf;
                            }
                        }
                    }
                    if (surf != null && surf.get_width () > 0 && surf.get_height () > 0) {
                        cr.rectangle (0, 0, w, h);
                        cr.clip ();
                        cr.scale (w / surf.get_width (), h / surf.get_height ());
                        cr.set_source_surface (surf, 0, 0);
                        cr.get_source ().set_filter (Cairo.Filter.GOOD);
                        cr.paint ();
                    } else {
                        cr.rectangle (0.5, 0.5, w - 1, h - 1);
                        rgb (cr, dark ? "#34332f" : "#e6e5e0");
                        cr.fill ();
                    }
                    break;
                case DrawingKind.LINE:
                case DrawingKind.ARROW:
                    double x1 = d.flip_h ? w : 0, x2 = d.flip_h ? 0 : w;
                    double y1 = d.flip_v ? h : 0, y2 = d.flip_v ? 0 : h;
                    cr.move_to (x1, y1);
                    cr.line_to (x2, y2);
                    rgb (cr, d.stroke);
                    cr.set_line_width (double.max (d.stroke_width, 1));
                    cr.set_line_cap (Cairo.LineCap.ROUND);
                    cr.stroke ();
                    if (d.kind == DrawingKind.ARROW) {
                        double ang = Math.atan2 (y2 - y1, x2 - x1);
                        double len = 10 + d.stroke_width * 2;
                        cr.move_to (x2, y2);
                        cr.line_to (x2 - len * Math.cos (ang - 0.45), y2 - len * Math.sin (ang - 0.45));
                        cr.line_to (x2 - len * Math.cos (ang + 0.45), y2 - len * Math.sin (ang + 0.45));
                        cr.close_path ();
                        rgb (cr, d.stroke);
                        cr.fill ();
                    }
                    break;
                default:
                    double inset = d.stroke != "" ? d.stroke_width / 2 : 0;
                    cr.new_path ();
                    if (d.kind == DrawingKind.ELLIPSE) {
                        cr.save ();
                        cr.translate (w / 2, h / 2);
                        cr.scale (double.max (w / 2 - inset, 1), double.max (h / 2 - inset, 1));
                        cr.arc (0, 0, 1, 0, 2 * Math.PI);
                        cr.restore ();
                    } else {
                        double r = d.kind == DrawingKind.ROUNDED ? double.min (w, h) * 0.16 : 0;
                        double x = inset, y = inset, ww = w - 2 * inset, hh = h - 2 * inset;
                        if (r <= 0) {
                            cr.rectangle (x, y, ww, hh);
                        } else {
                            cr.new_sub_path ();
                            cr.arc (x + ww - r, y + r, r, -Math.PI / 2, 0);
                            cr.arc (x + ww - r, y + hh - r, r, 0, Math.PI / 2);
                            cr.arc (x + r, y + hh - r, r, Math.PI / 2, Math.PI);
                            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
                            cr.close_path ();
                        }
                    }
                    if (d.fill != "") {
                        rgb (cr, d.fill, d.opacity);
                        cr.fill_preserve ();
                    }
                    if (d.stroke != "" && d.stroke_width > 0) {
                        rgb (cr, d.stroke, d.opacity < 1 ? double.max (d.opacity, 0.8) : 1);
                        cr.set_line_width (d.stroke_width);
                        cr.stroke ();
                    }
                    cr.new_path ();
                    if (d.text != "") {
                        var layout = Pango.cairo_create_layout (cr);
                        var font = Pango.FontDescription.from_string ("Sans");
                        font.set_absolute_size (d.font_size * Pango.SCALE * 96.0 / 72.0);
                        layout.set_font_description (font);
                        layout.set_width ((int) ((w - 12) * Pango.SCALE));
                        layout.set_wrap (Pango.WrapMode.WORD_CHAR);
                        layout.set_alignment (d.kind == DrawingKind.TEXT_BOX ? Pango.Alignment.LEFT : Pango.Alignment.CENTER);
                        layout.set_text (d.text, -1);
                        int tw, th;
                        layout.get_pixel_size (out tw, out th);
                        cr.rectangle (0, 0, w, h);
                        cr.clip ();
                        cr.move_to (6, d.kind == DrawingKind.TEXT_BOX ? 6 : (h - th) / 2);
                        rgb (cr, d.text_color);
                        Pango.cairo_show_layout (cr, layout);
                    }
                    break;
            }
            cr.restore ();
            if (selected) {
                cr.save ();
                cr.rectangle (-1.5, -1.5, w + 3, h + 3);
                rgb (cr, series_color (0, dark));
                cr.set_line_width (1.5);
                double[] dash = { 4, 3 };
                cr.set_dash (dash, 0);
                cr.stroke ();
                cr.set_dash (null, 0);
                double[,] pts = { { 0, 0 }, { w, 0 }, { 0, h }, { w, h } };
                for (int i = 0; i < 4; i++) {
                    cr.arc (pts[i, 0], pts[i, 1], 4, 0, 2 * Math.PI);
                    cr.set_source_rgb (1, 1, 1);
                    cr.fill_preserve ();
                    rgb (cr, series_color (0, dark));
                    cr.set_line_width (1.5);
                    cr.stroke ();
                }
                cr.restore ();
            }
        }

        private static Cairo.ImageSurface? cached_surface (Bytes data) {
            if (surfaces == null) surfaces = new Gee.HashMap<Bytes, Cairo.ImageSurface> ();
            var surf = surfaces[data];
            if (surf == null) {
                var t = texture_of (data);
                if (t == null) return null;
                surf = surface_of (t);
                surfaces[data] = surf;
            }
            return surf;
        }

        public static void draw_cell_image (Cairo.Context cr, Value v, double x, double y, double cw, double ch, double zoom) {
            var surf = cached_surface (v.image);
            if (surf == null) return;
            double iw = surf.get_width (), ih = surf.get_height ();
            if (iw <= 0 || ih <= 0) return;
            double pad = 2;
            double aw = cw - 2 * pad, ah = ch - 2 * pad;
            if (aw <= 1 || ah <= 1) return;
            double dw, dh;
            switch (v.image_sizing) {
                case 1:
                    dw = aw;
                    dh = ah;
                    break;
                case 2:
                    dw = iw * zoom;
                    dh = ih * zoom;
                    break;
                case 3:
                    double hh = v.image_height > 0 ? v.image_height * zoom * 96.0 / 72.0 : 0;
                    double ww = v.image_width > 0 ? v.image_width * zoom * 96.0 / 72.0 : 0;
                    if (hh <= 0) hh = ww * ih / iw;
                    if (ww <= 0) ww = hh * iw / ih;
                    dw = ww;
                    dh = hh;
                    break;
                default:
                    double sc = double.min (aw / iw, ah / ih);
                    dw = iw * sc;
                    dh = ih * sc;
                    break;
            }
            cr.save ();
            cr.rectangle (x, y, cw, ch);
            cr.clip ();
            cr.translate (x + pad + (aw - dw) / 2, y + pad + (ah - dh) / 2);
            cr.scale (dw / iw, dh / ih);
            cr.set_source_surface (surf, 0, 0);
            cr.get_source ().set_filter (Cairo.Filter.GOOD);
            cr.paint ();
            cr.restore ();
        }

        public static double[] sparkline_values (Workbook book, Sheet sheet, Sparkline item) {
            var v = ChartResolve.eval_ref (book, sheet, item.source);
            double[] out_v = {};
            if (v == null) return out_v;
            if (v.kind == ValueKind.RANGE) {
                var a = v.area;
                var s = a.sheet ?? sheet;
                for (int r = a.r1; r <= a.r2 && out_v.length < 10000; r++) {
                    for (int c = a.c1; c <= a.c2; c++) {
                        var cv = s.value_at (r, c);
                        out_v += cv.kind == ValueKind.NUMBER ? cv.number : double.NAN;
                    }
                }
            } else if (v.kind == ValueKind.NUMBER) {
                out_v += v.number;
            }
            return out_v;
        }

        public static void draw_sparkline (Cairo.Context cr, Workbook book, Sheet sheet, SparklineGroup g, Sparkline item, double x, double y, double w, double h) {
            var vals = sparkline_values (book, sheet, item);
            if (vals.length == 0) return;
            double lo = double.INFINITY, hi = -double.INFINITY;
            int ilo = -1, ihi = -1, ifirst = -1, ilast = -1;
            for (int i = 0; i < vals.length; i++) {
                if (vals[i].is_nan ()) continue;
                if (ifirst < 0) ifirst = i;
                ilast = i;
                if (vals[i] < lo) {
                    lo = vals[i];
                    ilo = i;
                }
                if (vals[i] > hi) {
                    hi = vals[i];
                    ihi = i;
                }
            }
            if (ifirst < 0) return;
            double pad = 3;
            double px = x + pad, py = y + pad, pw = w - 2 * pad, ph = h - 2 * pad;
            if (pw < 4 || ph < 4) return;
            cr.save ();
            cr.rectangle (x, y, w, h);
            cr.clip ();
            int n = vals.length;
            if (g.kind == SparklineKind.LINE) {
                if (hi == lo) {
                    hi += 1;
                    lo -= 1;
                }
                cr.new_path ();
                bool started = false;
                for (int i = 0; i < n; i++) {
                    if (vals[i].is_nan ()) continue;
                    double cx = n == 1 ? px + pw / 2 : px + pw * i / (n - 1);
                    double cy = py + ph - (vals[i] - lo) / (hi - lo) * ph;
                    if (!started) cr.move_to (cx, cy);
                    else cr.line_to (cx, cy);
                    started = true;
                }
                rgb (cr, g.color);
                cr.set_line_width (g.line_weight * 1.33);
                cr.set_line_join (Cairo.LineJoin.ROUND);
                cr.stroke ();
                for (int i = 0; i < n; i++) {
                    if (vals[i].is_nan ()) continue;
                    string? mc = null;
                    if (g.markers) mc = g.marker_color;
                    if (g.negative && vals[i] < 0) mc = g.negative_color;
                    if (g.first && i == ifirst) mc = g.marker_color;
                    if (g.last && i == ilast) mc = g.marker_color;
                    if (g.low && i == ilo) mc = g.low_color;
                    if (g.high && i == ihi) mc = g.high_color;
                    if (mc == null) continue;
                    double cx = n == 1 ? px + pw / 2 : px + pw * i / (n - 1);
                    double cy = py + ph - (vals[i] - lo) / (hi - lo) * ph;
                    cr.arc (cx, cy, 2.2, 0, 2 * Math.PI);
                    rgb (cr, mc);
                    cr.fill ();
                }
            } else {
                double band = pw / n;
                double bw = double.max (band * 0.7, 1);
                bool winloss = g.kind == SparklineKind.WIN_LOSS;
                double top = winloss ? 1 : double.max (hi, 0);
                double bottom = winloss ? -1 : double.min (lo, 0);
                if (top == bottom) top = bottom + 1;
                double zero = py + ph * top / (top - bottom);
                for (int i = 0; i < n; i++) {
                    double v = vals[i];
                    if (v.is_nan () || (winloss && v == 0)) continue;
                    double vv = winloss ? (v > 0 ? 1 : -1) : v;
                    double yv = py + ph * (top - vv) / (top - bottom);
                    string c = g.color;
                    if (v < 0 && (g.negative || winloss)) c = g.negative_color;
                    if (g.high && i == ihi) c = g.high_color;
                    if (g.low && i == ilo) c = g.low_color;
                    if (g.first && i == ifirst) c = g.marker_color;
                    if (g.last && i == ilast) c = g.marker_color;
                    cr.rectangle (px + band * i + (band - bw) / 2, double.min (yv, zero), bw, double.max (Math.fabs (zero - yv), 1));
                    rgb (cr, c);
                    cr.fill ();
                }
            }
            cr.restore ();
        }
    }
}
