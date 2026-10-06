namespace Singularity.Apps.Spreadsheet {

    public class MacroRecorder {
        public Document doc;
        public Sheet? current;
        private StringBuilder body = new StringBuilder ();
        private int lines;

        public MacroRecorder (Document doc, Sheet? current) {
            this.doc = doc;
            this.current = current;
        }

        public int count {
            get { return lines; }
        }

        private void emit (string line) {
            body.append ("    " + line + "\n");
            lines++;
        }

        private static string quote (string s) {
            return "\"" + s.replace ("\"", "\"\"") + "\"";
        }

        private static string area_text (Area a) {
            if (a.is_single ()) return Address.cell (a.r1, a.c1);
            return Address.cell (a.r1, a.c1) + ":" + Address.cell (a.r2, a.c2);
        }

        public void switch_sheet (Sheet s) {
            if (s == current) return;
            current = s;
            emit ("Sheets(%s).Activate".printf (quote (s.name)));
        }

        public void action (string name) {
            emit ("Run %s".printf (quote (name)));
        }

        public void record_cells (Sheet s, Gee.List<CellCopy> before, Gee.List<CellCopy> after) {
            switch_sheet (s);
            var old_in = new Gee.HashMap<int64?, CellCopy> ((k) => { int64 v = k; return (uint) (v ^ (v >> 32)); }, (a, b) => { int64 x = a; int64 y = b; return x == y; });
            foreach (var c in before) old_in[Sheet.key (c.row, c.col)] = c;
            var seen = new Gee.HashSet<int64?> ((k) => { int64 v = k; return (uint) (v ^ (v >> 32)); }, (a, b) => { int64 x = a; int64 y = b; return x == y; });
            var sorted = new Gee.ArrayList<CellCopy> ();
            sorted.add_all (after);
            sorted.sort ((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
            var style_groups = new Gee.HashMap<string, Gee.ArrayList<CellCopy>> ();
            var group_order = new Gee.ArrayList<string> ();
            foreach (var c in sorted) {
                int64 k = Sheet.key (c.row, c.col);
                seen.add (k);
                var o = old_in[k];
                string oi = o != null ? o.input : "";
                if (c.input != oi) emit ("Range(%s).Formula = %s".printf (quote (Address.cell (c.row, c.col)), quote (c.input)));
                int os = o != null ? o.style : 0;
                if (c.style != os) {
                    string props = style_changes (doc.book.styles[os], doc.book.styles[c.style]);
                    if (props == "") continue;
                    if (!style_groups.has_key (props)) {
                        style_groups[props] = new Gee.ArrayList<CellCopy> ();
                        group_order.add (props);
                    }
                    style_groups[props].add (c);
                }
                string on = o != null ? o.note : "";
                if (c.note != on) emit ("Range(%s).Note = %s".printf (quote (Address.cell (c.row, c.col)), quote (c.note)));
            }
            foreach (var o in before) {
                int64 k = Sheet.key (o.row, o.col);
                if (seen.contains (k)) continue;
                if (o.input != "") emit ("Range(%s).ClearContents".printf (quote (Address.cell (o.row, o.col))));
                if (o.style != 0) emit ("Range(%s).ClearFormats".printf (quote (Address.cell (o.row, o.col))));
            }
            foreach (string props in group_order) {
                var cells = style_groups[props];
                int r1 = int.MAX, c1 = int.MAX, r2 = -1, c2 = -1;
                foreach (var c in cells) {
                    r1 = int.min (r1, c.row);
                    c1 = int.min (c1, c.col);
                    r2 = int.max (r2, c.row);
                    c2 = int.max (c2, c.col);
                }
                bool rect = (r2 - r1 + 1) * (c2 - c1 + 1) == cells.size;
                if (rect) {
                    foreach (string p in props.split ("\n")) emit ("Range(%s).%s".printf (quote (area_text (new Area (null, r1, c1, r2, c2))), p));
                } else {
                    foreach (var c in cells) foreach (string p in props.split ("\n")) emit ("Range(%s).%s".printf (quote (Address.cell (c.row, c.col)), p));
                }
            }
        }

        private static string style_changes (CellStyle a, CellStyle b) {
            string[] out_p = {};
            if (a.bold != b.bold) out_p += "Bold = %s".printf (b.bold ? "True" : "False");
            if (a.italic != b.italic) out_p += "Italic = %s".printf (b.italic ? "True" : "False");
            if (a.underline != b.underline) out_p += "Underline = %s".printf (b.underline ? "True" : "False");
            if (a.strike != b.strike) out_p += "StrikeThrough = %s".printf (b.strike ? "True" : "False");
            if (a.wrap != b.wrap) out_p += "WrapText = %s".printf (b.wrap ? "True" : "False");
            if (a.number_format != b.number_format) out_p += "NumberFormat = %s".printf (quote (b.number_format));
            if (a.fill != b.fill) out_p += "Fill = %s".printf (quote (b.fill));
            if (a.color != b.color) out_p += "FontColor = %s".printf (quote (b.color));
            if (a.font_size != b.font_size) out_p += "FontSize = %s".printf (Value.format_number_general_full (b.font_size));
            if (a.font_family != b.font_family) out_p += "FontName = %s".printf (quote (b.font_family));
            if (a.halign != b.halign) {
                string[] h = { "General", "Left", "Center", "Right", "Left", "Left" };
                out_p += "HorizontalAlignment = %s".printf (quote (h[b.halign]));
            }
            return string.joinv ("\n", out_p);
        }

        public string finish (string name) {
            return "Sub %s ()\n%sEnd Sub\n".printf (name, body.str).replace ("Sub %s ()".printf (name), "Sub %s()".printf (name));
        }
    }
}
