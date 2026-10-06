namespace Singularity.Apps.Spreadsheet {

    public class DocTheme {
        public string name = "Office";
        public string[] colors = { "#ffffff", "#000000", "#e7e6e6", "#44546a", "#4472c4", "#ed7d31", "#a5a5a5", "#ffc000", "#5b9bd5", "#70ad47", "#0563c1", "#954f72" };
        public string major_font = "Calibri Light";
        public string minor_font = "Calibri";

        public DocTheme copy () {
            var t = new DocTheme ();
            t.name = name;
            t.colors = colors;
            t.major_font = major_font;
            t.minor_font = minor_font;
            return t;
        }

        public string accent (int n) {
            return colors[(3 + n).clamp (4, 9)];
        }

        public static DocTheme[] builtin () {
            DocTheme[] list = {};
            list += make ("Office", { "#ffffff", "#000000", "#e7e6e6", "#44546a", "#4472c4", "#ed7d31", "#a5a5a5", "#ffc000", "#5b9bd5", "#70ad47", "#0563c1", "#954f72" }, "Calibri Light", "Calibri");
            list += make ("Office 2023", { "#ffffff", "#000000", "#e8e8e8", "#0e2841", "#156082", "#e97132", "#196b24", "#0f9ed5", "#a02b93", "#4ea72e", "#467886", "#96607d" }, "Aptos Display", "Aptos");
            list += make ("Slate", { "#ffffff", "#000000", "#dadada", "#212745", "#4e67c8", "#5eccf3", "#a7ea52", "#5dceaf", "#ff8021", "#f14124", "#56c7aa", "#59a8d1" }, "Calisto MT", "Calisto MT");
            list += make ("Retrospect", { "#ffffff", "#000000", "#e3ded1", "#637052", "#e48312", "#bd582c", "#865640", "#9b8357", "#c2bc80", "#94a088", "#6b9f25", "#b26b02" }, "Calibri Light", "Calibri");
            list += make ("Ion", { "#ffffff", "#000000", "#b0ccb0", "#1e5155", "#b01513", "#ea6312", "#e6b729", "#6aac90", "#5f9c9d", "#9e5e9b", "#58c1ba", "#9dffcb" }, "Century Gothic", "Century Gothic");
            list += make ("Grayscale", { "#ffffff", "#000000", "#f8f8f8", "#000000", "#dddddd", "#b2b2b2", "#969696", "#808080", "#5f5f5f", "#4d4d4d", "#5f5f5f", "#919191" }, "Arial", "Arial");
            list += make ("Blue Warm", { "#ffffff", "#000000", "#e7e6e6", "#242852", "#4a66ac", "#629dd1", "#297fd5", "#7f8fa9", "#5aa2ae", "#9d90a0", "#9454c3", "#3eb2d2" }, "Calibri Light", "Calibri");
            list += make ("Green", { "#ffffff", "#000000", "#e7e6e6", "#455f51", "#549e39", "#8ab833", "#c0cf3a", "#029676", "#4ab5c4", "#0989b1", "#6b9f25", "#ba6906" }, "Calibri Light", "Calibri");
            return list;
        }

        private static DocTheme make (string name, string[] colors, string major, string minor) {
            var t = new DocTheme ();
            t.name = name;
            t.colors = colors;
            t.major_font = major;
            t.minor_font = minor;
            return t;
        }

        public static string tint (string hex, double t) {
            if (hex.length != 7) return hex;
            double r = Xlsx.hex2 (hex, 1), g = Xlsx.hex2 (hex, 3), b = Xlsx.hex2 (hex, 5);
            if (t >= 0) {
                r = r + (255 - r) * t;
                g = g + (255 - g) * t;
                b = b + (255 - b) * t;
            } else {
                r = r * (1 + t);
                g = g * (1 + t);
                b = b * (1 + t);
            }
            return "#%02x%02x%02x".printf ((int) Math.round (r), (int) Math.round (g), (int) Math.round (b));
        }
    }

    public class CustomView {
        public string name;
        public Gee.HashSet<int> hidden_rows = new Gee.HashSet<int> ();
        public Gee.HashSet<int> hidden_cols = new Gee.HashSet<int> ();
        public Filter? filter;
        public double zoom = 1.0;
        public int freeze_rows;
        public int freeze_cols;
        public int row;
        public int col;
        public Gee.ArrayList<int> row_breaks = new Gee.ArrayList<int> ();

        public CustomView (string name) {
            this.name = name;
        }

        public CustomView copy () {
            var v = new CustomView (name);
            v.hidden_rows.add_all (hidden_rows);
            v.hidden_cols.add_all (hidden_cols);
            v.filter = filter;
            v.zoom = zoom;
            v.freeze_rows = freeze_rows;
            v.freeze_cols = freeze_cols;
            v.row = row;
            v.col = col;
            v.row_breaks.add_all (row_breaks);
            return v;
        }

        public static CustomView capture (Sheet s, string name, double zoom, int row, int col) {
            var v = new CustomView (name);
            v.hidden_rows.add_all (s.hidden_rows);
            v.hidden_cols.add_all (s.hidden_cols);
            if (s.filter != null) {
                var f = new Filter (s.filter.area.copy ());
                foreach (var e in s.filter.hidden_values.entries) {
                    var set = new Gee.HashSet<string> ();
                    set.add_all (e.value);
                    f.hidden_values[e.key] = set;
                }
                v.filter = f;
            }
            v.zoom = zoom;
            v.freeze_rows = s.freeze_rows;
            v.freeze_cols = s.freeze_cols;
            v.row = row;
            v.col = col;
            v.row_breaks.add_all (s.page.row_breaks);
            return v;
        }

        public void apply (Sheet s) {
            s.page.row_breaks.clear ();
            s.page.row_breaks.add_all (row_breaks);
            s.hidden_rows = new Gee.HashSet<int> ();
            s.hidden_rows.add_all (hidden_rows);
            s.hidden_cols = new Gee.HashSet<int> ();
            s.hidden_cols.add_all (hidden_cols);
            s.filter = filter;
            s.freeze_rows = freeze_rows;
            s.freeze_cols = freeze_cols;
        }
    }

    public class NamedStyle {
        public static int builtin_id (string name) {
            switch (name) {
                case "Normal": return 0;
                case "Comma": return 3;
                case "Currency": return 4;
                case "Percent": return 5;
                case "Comma [0]": return 6;
                case "Currency [0]": return 7;
                case "Note": return 10;
                case "Warning Text": return 11;
                case "Title": return 15;
                case "Heading 1": return 16;
                case "Heading 2": return 17;
                case "Heading 3": return 18;
                case "Heading 4": return 19;
                case "Input": return 20;
                case "Output": return 21;
                case "Calculation": return 22;
                case "Check Cell": return 23;
                case "Linked Cell": return 24;
                case "Total": return 25;
                case "Good": return 26;
                case "Bad": return 27;
                case "Neutral": return 28;
                case "Explanatory Text": return 53;
            }
            for (int a = 1; a <= 6; a++) {
                if (name == "Accent%d".printf (a)) return 29 + (a - 1) * 4;
                if (name == "20%% - Accent%d".printf (a)) return 30 + (a - 1) * 4;
                if (name == "40%% - Accent%d".printf (a)) return 31 + (a - 1) * 4;
                if (name == "60%% - Accent%d".printf (a)) return 32 + (a - 1) * 4;
            }
            return -1;
        }

        public string name;
        public string category;
        public string fill = "";
        public string color = "";
        public bool bold;
        public bool italic;
        public double size;
        public bool heading_font;
        public string number_format = "";
        public BorderStyle outline = BorderStyle.NONE;
        public string outline_color = "";
        public BorderStyle bottom = BorderStyle.NONE;
        public string bottom_color = "";
        public BorderStyle top = BorderStyle.NONE;
        public string top_color = "";
        public bool reset;

        public NamedStyle (string name, string category) {
            this.name = name;
            this.category = category;
        }

        public void apply (CellStyle st, DocTheme theme) {
            st.style_name = reset ? "" : name;
            if (reset) {
                var base_style = new CellStyle ();
                st.bold = base_style.bold;
                st.italic = base_style.italic;
                st.fill = "";
                st.color = "";
                st.font_size = 11;
                st.font_family = "";
                st.number_format = "General";
                st.top = new Border ();
                st.bottom = new Border ();
                st.left = new Border ();
                st.right = new Border ();
                return;
            }
            if (number_format != "") {
                st.number_format = number_format;
                return;
            }
            st.fill = fill;
            st.color = color;
            st.bold = bold;
            st.italic = italic;
            st.font_size = size > 0 ? size : 11;
            st.font_family = heading_font ? theme.major_font : "";
            if (outline != BorderStyle.NONE) {
                st.top = new Border (outline, outline_color);
                st.bottom = new Border (outline, outline_color);
                st.left = new Border (outline, outline_color);
                st.right = new Border (outline, outline_color);
            } else {
                st.left = new Border ();
                st.right = new Border ();
                st.top = top != BorderStyle.NONE ? new Border (top, top_color) : new Border ();
                st.bottom = bottom != BorderStyle.NONE ? new Border (bottom, bottom_color) : new Border ();
            }
        }

        private static NamedStyle s (string name, string cat, string fill, string color, bool bold = false) {
            var n = new NamedStyle (name, cat);
            n.fill = fill;
            n.color = color;
            n.bold = bold;
            return n;
        }

        public static Gee.List<NamedStyle> gallery (DocTheme theme) {
            var l = new Gee.ArrayList<NamedStyle> ();
            var normal = new NamedStyle (_("Normal"), _("Good, Bad and Neutral"));
            normal.reset = true;
            l.add (normal);
            l.add (s (_("Bad"), _("Good, Bad and Neutral"), "#ffc7ce", "#9c0006"));
            l.add (s (_("Good"), _("Good, Bad and Neutral"), "#c6efce", "#006100"));
            l.add (s (_("Neutral"), _("Good, Bad and Neutral"), "#ffeb9c", "#9c5700"));
            string data = _("Data and Model");
            var calc = s (_("Calculation"), data, "#f2f2f2", "#fa7d00", true);
            calc.outline = BorderStyle.THIN;
            calc.outline_color = "#7f7f7f";
            l.add (calc);
            var check = s (_("Check Cell"), data, "#a5a5a5", "#ffffff", true);
            check.outline = BorderStyle.DOUBLE;
            check.outline_color = "#3f3f3f";
            l.add (check);
            var expl = s (_("Explanatory Text"), data, "", "#7f7f7f");
            expl.italic = true;
            l.add (expl);
            var input = s (_("Input"), data, "#ffcc99", "#3f3f76");
            input.outline = BorderStyle.THIN;
            input.outline_color = "#7f7f7f";
            l.add (input);
            var linked = s (_("Linked Cell"), data, "", "#fa7d00");
            linked.bottom = BorderStyle.DOUBLE;
            linked.bottom_color = "#ff8001";
            l.add (linked);
            var note = s (_("Note"), data, "#ffffcc", "");
            note.outline = BorderStyle.THIN;
            note.outline_color = "#b2b2b2";
            l.add (note);
            var output = s (_("Output"), data, "#f2f2f2", "#3f3f3f", true);
            output.outline = BorderStyle.THIN;
            output.outline_color = "#3f3f3f";
            l.add (output);
            l.add (s (_("Warning Text"), data, "", "#ff0000"));
            string titles = _("Titles and Headings");
            var h1 = s (_("Heading 1"), titles, "", theme.colors[3], true);
            h1.size = 15;
            h1.bottom = BorderStyle.THICK;
            h1.bottom_color = theme.accent (1);
            l.add (h1);
            var h2 = s (_("Heading 2"), titles, "", theme.colors[3], true);
            h2.size = 13;
            h2.bottom = BorderStyle.THICK;
            h2.bottom_color = DocTheme.tint (theme.accent (1), 0.5);
            l.add (h2);
            var h3 = s (_("Heading 3"), titles, "", theme.colors[3], true);
            h3.bottom = BorderStyle.MEDIUM;
            h3.bottom_color = DocTheme.tint (theme.accent (1), 0.4);
            l.add (h3);
            l.add (s (_("Heading 4"), titles, "", theme.colors[3], true));
            var title = s (_("Title"), titles, "", theme.colors[3], true);
            title.size = 18;
            title.heading_font = true;
            l.add (title);
            var total = s (_("Total"), titles, "", "", true);
            total.top = BorderStyle.THIN;
            total.top_color = theme.accent (1);
            total.bottom = BorderStyle.DOUBLE;
            total.bottom_color = theme.accent (1);
            l.add (total);
            string themed = _("Themed Cell Styles");
            double[] tints = { 0.8, 0.6, 0.4, 0 };
            string[] labels = { _("20%% - Accent%d"), _("40%% - Accent%d"), _("60%% - Accent%d"), _("Accent%d") };
            for (int t = 0; t < 4; t++) {
                for (int a = 1; a <= 6; a++) {
                    string fill = DocTheme.tint (theme.accent (a), tints[t]);
                    l.add (s (labels[t].printf (a), themed, fill, t >= 2 ? "#ffffff" : "#000000"));
                }
            }
            string numbers = _("Number Format");
            string[,] nf = {
                { _("Comma"), "#,##0.00" },
                { _("Comma [0]"), "#,##0" },
                { _("Currency"), "\"$\"#,##0.00" },
                { _("Currency [0]"), "\"$\"#,##0" },
                { _("Percent"), "0%" }
            };
            for (int i = 0; i < nf.length[0]; i++) {
                var n = new NamedStyle (nf[i, 0], numbers);
                n.number_format = nf[i, 1];
                l.add (n);
            }
            return l;
        }
    }
}
