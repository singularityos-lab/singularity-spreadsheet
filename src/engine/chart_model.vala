namespace Singularity.Apps.Spreadsheet {

    public class Chart {
        public string kind = "column";
        public string title = "";
        public Area source;
        public bool series_in_rows;
        public bool first_row_labels = true;
        public bool first_col_labels = true;
        public double x = 40;
        public double y = 40;
        public double width = 480;
        public double height = 300;
        public string name = "";
        public string alt_text = "";
        public bool explicit_series;
        public Singularity.Charts.ChartSpec style = new Singularity.Charts.ChartSpec ();

        public const string[] KINDS = {
            "column", "column-stacked", "column-percent", "bar", "bar-stacked", "bar-percent",
            "line", "line-plain", "line-stacked", "area", "area-stacked", "area-percent",
            "pie", "doughnut", "scatter", "scatter-lines", "bubble", "radar", "radar-filled", "stock",
            "combo", "histogram", "pareto", "box", "waterfall", "funnel", "treemap", "sunburst"
        };

        public Chart (Area source) {
            this.source = source;
        }

        public Chart copy () {
            var c = new Chart (source.copy ());
            c.kind = kind;
            c.title = title;
            c.series_in_rows = series_in_rows;
            c.first_row_labels = first_row_labels;
            c.first_col_labels = first_col_labels;
            c.x = x;
            c.y = y;
            c.width = width;
            c.height = height;
            c.name = name;
            c.alt_text = alt_text;
            c.explicit_series = explicit_series;
            c.style = style.copy ();
            return c;
        }

        public static string kind_label (string id) {
            switch (id) {
                case "column": return _("Column");
                case "column-stacked": return _("Stacked Column");
                case "column-percent": return _("100% Stacked Column");
                case "bar": return _("Bar");
                case "bar-stacked": return _("Stacked Bar");
                case "bar-percent": return _("100% Stacked Bar");
                case "line": return _("Line with Markers");
                case "line-plain": return _("Line");
                case "line-stacked": return _("Stacked Line");
                case "area": return _("Area");
                case "area-stacked": return _("Stacked Area");
                case "area-percent": return _("100% Stacked Area");
                case "pie": return _("Pie");
                case "doughnut": return _("Doughnut");
                case "scatter": return _("Scatter");
                case "scatter-lines": return _("Scatter with Lines");
                case "bubble": return _("Bubble");
                case "radar": return _("Radar");
                case "radar-filled": return _("Filled Radar");
                case "stock": return _("Stock");
                case "combo": return _("Combo");
                case "histogram": return _("Histogram");
                case "pareto": return _("Pareto");
                case "box": return _("Box and Whisker");
                case "waterfall": return _("Waterfall");
                case "funnel": return _("Funnel");
                case "treemap": return _("Treemap");
                case "sunburst": return _("Sunburst");
                default: return id;
            }
        }

        public void apply_kind (Singularity.Charts.ChartSpec spec) {
            string base_id = kind;
            var g = Singularity.Charts.Grouping.CLUSTERED;
            if (kind.has_suffix ("-stacked")) {
                g = Singularity.Charts.Grouping.STACKED;
                base_id = kind.substring (0, kind.length - 8);
            } else if (kind.has_suffix ("-percent")) {
                g = Singularity.Charts.Grouping.PERCENT;
                base_id = kind.substring (0, kind.length - 8);
            }
            spec.grouping = g;
            switch (base_id) {
                case "line":
                    spec.kind = Singularity.Charts.ChartType.LINE;
                    spec.markers = kind == "line";
                    break;
                case "line-plain":
                    spec.kind = Singularity.Charts.ChartType.LINE;
                    spec.markers = false;
                    break;
                case "scatter-lines":
                    spec.kind = Singularity.Charts.ChartType.SCATTER;
                    spec.lines_on_scatter = true;
                    break;
                case "scatter":
                    spec.kind = Singularity.Charts.ChartType.SCATTER;
                    spec.lines_on_scatter = false;
                    break;
                case "radar-filled":
                    spec.kind = Singularity.Charts.ChartType.RADAR;
                    spec.filled_radar = true;
                    break;
                case "radar":
                    spec.kind = Singularity.Charts.ChartType.RADAR;
                    spec.filled_radar = false;
                    break;
                case "combo":
                    spec.kind = Singularity.Charts.ChartType.COLUMN;
                    break;
                default:
                    spec.kind = Singularity.Charts.ChartType.from_id (base_id);
                    break;
            }
        }

        public static string kind_of_spec (Singularity.Charts.ChartSpec spec) {
            string suffix = spec.grouping == Singularity.Charts.Grouping.STACKED ? "-stacked" : (spec.grouping == Singularity.Charts.Grouping.PERCENT ? "-percent" : "");
            switch (spec.kind) {
                case Singularity.Charts.ChartType.COLUMN:
                    if (spec.is_combo () || spec.has_secondary ()) return "combo";
                    return "column" + suffix;
                case Singularity.Charts.ChartType.BAR: return "bar" + suffix;
                case Singularity.Charts.ChartType.AREA: return "area" + suffix;
                case Singularity.Charts.ChartType.LINE:
                    if (suffix != "") return "line-stacked";
                    return spec.markers ? "line" : "line-plain";
                case Singularity.Charts.ChartType.SCATTER: return spec.lines_on_scatter ? "scatter-lines" : "scatter";
                case Singularity.Charts.ChartType.RADAR: return spec.filled_radar ? "radar-filled" : "radar";
                default: return spec.kind.to_id ();
            }
        }
    }

    public enum DrawingKind {
        IMAGE,
        RECTANGLE,
        ROUNDED,
        ELLIPSE,
        LINE,
        ARROW,
        TEXT_BOX,
        GROUP;

        public string to_id () {
            switch (this) {
                case IMAGE: return "image";
                case ROUNDED: return "roundRect";
                case ELLIPSE: return "ellipse";
                case LINE: return "line";
                case ARROW: return "arrow";
                case TEXT_BOX: return "textbox";
                case GROUP: return "group";
                default: return "rect";
            }
        }

        public static DrawingKind from_id (string id) {
            switch (id) {
                case "image": return IMAGE;
                case "roundRect": return ROUNDED;
                case "ellipse": return ELLIPSE;
                case "line": case "straightConnector1": return LINE;
                case "arrow": return ARROW;
                case "textbox": return TEXT_BOX;
                case "group": return GROUP;
                default: return RECTANGLE;
            }
        }
    }

    public class Drawing {
        public DrawingKind kind;
        public double x = 40;
        public double y = 40;
        public double width = 200;
        public double height = 120;
        public string name = "";
        public string fill = "#4a90d9";
        public string stroke = "#2a5f99";
        public double stroke_width = 1.5;
        public string text = "";
        public string text_color = "#ffffff";
        public double font_size = 12;
        public bool flip_h;
        public bool flip_v;
        public Bytes? image;
        public string mime = "image/png";
        public string alt_text = "";
        public double opacity = 1;
        public double frame_w;
        public double frame_h;
        public string diagram = "";
        public Gee.ArrayList<Drawing> children = new Gee.ArrayList<Drawing> ();

        public Drawing (DrawingKind kind) {
            this.kind = kind;
            if (kind == DrawingKind.TEXT_BOX) {
                fill = "#ffffff";
                stroke = "#8a8a85";
                text_color = "#1a1a19";
            }
            if (kind == DrawingKind.LINE || kind == DrawingKind.ARROW) {
                fill = "";
                height = 0;
            }
        }

        public Drawing copy () {
            var d = new Drawing (kind);
            d.x = x;
            d.y = y;
            d.width = width;
            d.height = height;
            d.name = name;
            d.fill = fill;
            d.stroke = stroke;
            d.stroke_width = stroke_width;
            d.text = text;
            d.text_color = text_color;
            d.font_size = font_size;
            d.flip_h = flip_h;
            d.flip_v = flip_v;
            d.image = image;
            d.mime = mime;
            d.alt_text = alt_text;
            d.opacity = opacity;
            d.frame_w = frame_w;
            d.frame_h = frame_h;
            d.diagram = diagram;
            foreach (var c in children) d.children.add (c.copy ());
            return d;
        }

        public static string mime_of (uint8[] data) {
            if (data.length > 8 && data[0] == 0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G') return "image/png";
            if (data.length > 3 && data[0] == 0xff && data[1] == 0xd8) return "image/jpeg";
            if (data.length > 6 && data[0] == 'G' && data[1] == 'I' && data[2] == 'F') return "image/gif";
            if (data.length > 2 && data[0] == 'B' && data[1] == 'M') return "image/bmp";
            if (data.length > 12 && data[8] == 'W' && data[9] == 'E' && data[10] == 'B' && data[11] == 'P') return "image/webp";
            string head = (string) data[0:int.min (data.length, 200)];
            if (head != null && (head.contains ("<svg") || head.contains ("<?xml"))) return "image/svg+xml";
            return "image/png";
        }

        public static string ext_of (string mime) {
            switch (mime) {
                case "image/jpeg": return "jpeg";
                case "image/gif": return "gif";
                case "image/bmp": return "bmp";
                case "image/webp": return "webp";
                case "image/svg+xml": return "svg";
                default: return "png";
            }
        }
    }

    public enum SparklineKind {
        LINE,
        COLUMN,
        WIN_LOSS;

        public string to_id () {
            switch (this) {
                case COLUMN: return "column";
                case WIN_LOSS: return "stacked";
                default: return "line";
            }
        }

        public static SparklineKind from_id (string id) {
            switch (id) {
                case "column": return COLUMN;
                case "stacked": case "winloss": return WIN_LOSS;
                default: return LINE;
            }
        }
    }

    public class Sparkline {
        public int row;
        public int col;
        public string source;

        public Sparkline (int row, int col, string source) {
            this.row = row;
            this.col = col;
            this.source = source;
        }
    }

    public class SparklineGroup {
        public SparklineKind kind = SparklineKind.LINE;
        public string color = "#2a78d6";
        public string negative_color = "#e34948";
        public string marker_color = "#2a78d6";
        public string high_color = "#1baf7a";
        public string low_color = "#e34948";
        public bool markers;
        public bool high;
        public bool low;
        public bool first;
        public bool last;
        public bool negative;
        public double line_weight = 1.25;
        public Gee.ArrayList<Sparkline> items = new Gee.ArrayList<Sparkline> ();

        public SparklineGroup copy () {
            var g = new SparklineGroup ();
            g.kind = kind;
            g.color = color;
            g.negative_color = negative_color;
            g.marker_color = marker_color;
            g.high_color = high_color;
            g.low_color = low_color;
            g.markers = markers;
            g.high = high;
            g.low = low;
            g.first = first;
            g.last = last;
            g.negative = negative;
            g.line_weight = line_weight;
            foreach (var s in items) g.items.add (new Sparkline (s.row, s.col, s.source));
            return g;
        }
    }

    public class SheetGeometry {
        public static double col_pos (Sheet s, int c) {
            double x = 0;
            int limit = int.min (c, MAX_COLS);
            if (s.col_widths.size == 0 && s.hidden_cols.size == 0) return (double) limit * s.default_col_width;
            for (int i = 0; i < limit; i++) x += s.col_width (i);
            return x;
        }

        public static double row_pos (Sheet s, int r) {
            int limit = int.min (r, MAX_ROWS);
            if (s.row_heights.size == 0 && s.hidden_rows.size == 0) return (double) limit * s.default_row_height;
            double y = (double) limit * s.default_row_height;
            foreach (var e in s.row_heights.entries) if (e.key < limit && !s.hidden_rows.contains (e.key)) y += e.value - s.default_row_height;
            foreach (int h in s.hidden_rows) if (h < limit) y -= s.row_heights.has_key (h) ? s.row_heights[h] : s.default_row_height;
            return y;
        }

        public static void locate_col (Sheet s, double px, out int col, out double offset) {
            double x = 0;
            for (int c = 0; c < MAX_COLS; c++) {
                double w = s.col_width (c);
                if (px < x + w || c == MAX_COLS - 1) {
                    col = c;
                    offset = double.max (px - x, 0);
                    return;
                }
                x += w;
            }
            col = 0;
            offset = 0;
        }

        public static void locate_row (Sheet s, double px, out int row, out double offset) {
            double y = 0;
            for (int r = 0; r < MAX_ROWS; r++) {
                double h = s.row_height (r);
                if (px < y + h || r == MAX_ROWS - 1) {
                    row = r;
                    offset = double.max (px - y, 0);
                    return;
                }
                y += h;
            }
            row = 0;
            offset = 0;
        }

        public static double to_abs_x (Sheet s, double x) {
            return x + col_pos (s, s.freeze_cols);
        }

        public static double to_abs_y (Sheet s, double y) {
            return y + row_pos (s, s.freeze_rows);
        }

        public static double from_abs_x (Sheet s, double x) {
            return x - col_pos (s, s.freeze_cols);
        }

        public static double from_abs_y (Sheet s, double y) {
            return y - row_pos (s, s.freeze_rows);
        }
    }
}
