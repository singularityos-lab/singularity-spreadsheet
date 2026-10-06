namespace Singularity.Apps.Spreadsheet {

    public class HtmlExport {
        private static string esc (string s) {
            return s.replace ("&", "&amp;").replace ("<", "&lt;").replace (">", "&gt;").replace ("\"", "&quot;");
        }

        private static string css (CellStyle st, Value v) {
            var sb = new StringBuilder ();
            if (st.bold) sb.append ("font-weight:bold;");
            if (st.italic) sb.append ("font-style:italic;");
            if (st.underline || st.strike) sb.append ("text-decoration:%s;".printf (st.underline && st.strike ? "underline line-through" : (st.underline ? "underline" : "line-through")));
            if (st.color != "") sb.append ("color:%s;".printf (st.color));
            if (st.fill != "") sb.append ("background:%s;".printf (st.fill));
            if (st.font_size != 11) sb.append ("font-size:%spt;".printf (Value.fixed (st.font_size, 1)));
            string align = "";
            switch (st.halign) {
                case HAlign.LEFT: align = "left"; break;
                case HAlign.CENTER: align = "center"; break;
                case HAlign.RIGHT: align = "right"; break;
                case HAlign.JUSTIFY: align = "justify"; break;
                default: align = v.kind == ValueKind.NUMBER ? "right" : ""; break;
            }
            if (align != "") sb.append ("text-align:%s;".printf (align));
            if (st.wrap) sb.append ("white-space:pre-wrap;");
            string[] sides = { "top", "bottom", "left", "right" };
            Border[] bs = { st.top, st.bottom, st.left, st.right };
            for (int i = 0; i < 4; i++) {
                if (bs[i].style == BorderStyle.NONE) continue;
                string kind = bs[i].style == BorderStyle.DOUBLE ? "3px double" : (bs[i].style == BorderStyle.DASHED ? "1px dashed" : (bs[i].style == BorderStyle.DOTTED ? "1px dotted" : (bs[i].style == BorderStyle.THIN ? "1px solid" : "2px solid")));
                sb.append ("border-%s:%s %s;".printf (sides[i], kind, bs[i].color != "" ? bs[i].color : "#000"));
            }
            return sb.str;
        }

        public static string sheet_html (Sheet s) {
            var book = s.book;
            var sb = new StringBuilder ();
            sb.append ("<h2>%s</h2>\n<table>\n".printf (esc (s.name)));
            int cols = s.max_col + 1;
            sb.append ("<colgroup>");
            for (int c = 0; c < cols; c++) {
                if (s.hidden_cols.contains (c)) continue;
                sb.append ("<col style=\"width:%dpx\">".printf (s.col_width (c)));
            }
            sb.append ("</colgroup>\n");
            var covered = new Gee.HashSet<int64?> ((k) => { int64 v = k; return (uint) (v ^ (v >> 32)); }, (a, b) => { int64 x = a; int64 y = b; return x == y; });
            for (int r = 0; r <= s.max_row; r++) {
                if (s.hidden_rows.contains (r)) continue;
                sb.append ("<tr>");
                for (int c = 0; c < cols; c++) {
                    if (s.hidden_cols.contains (c) || covered.contains (Sheet.key (r, c))) continue;
                    var m = s.merge_at (r, c);
                    string span = "";
                    if (m != null) {
                        for (int mr = m.r1; mr <= m.r2; mr++) for (int mc = m.c1; mc <= m.c2; mc++) covered.add (Sheet.key (mr, mc));
                        if (m.rows > 1) span += " rowspan=\"%d\"".printf (m.rows);
                        if (m.cols > 1) span += " colspan=\"%d\"".printf (m.cols);
                    }
                    var v = s.value_at (r, c);
                    var st = s.style_at (r, c);
                    string color;
                    string text = v.is_empty () ? "" : NumberFormat.format_value (v, st.number_format, out color, book.date1904);
                    string style = css (st, v);
                    var cell = s.get_cell (r, c);
                    string content = esc (text);
                    if (cell != null && cell.link != "") content = "<a href=\"%s\">%s</a>".printf (esc (cell.link), content);
                    sb.append ("<td%s%s>%s</td>".printf (span, style != "" ? " style=\"%s\"".printf (style) : "", content));
                }
                sb.append ("</tr>\n");
            }
            sb.append ("</table>\n");
            return sb.str;
        }

        public static void save (Workbook book, string path, Sheet? only = null) throws Error {
            var sb = new StringBuilder ("<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n");
            sb.append ("<title>%s</title>\n".printf (esc (Path.get_basename (path))));
            sb.append ("<style>body{font-family:sans-serif;font-size:11pt}table{border-collapse:collapse;margin-bottom:24px}td{padding:2px 6px;vertical-align:bottom}</style>\n</head>\n<body>\n");
            foreach (var s in book.sheets) {
                if (only != null && s != only) continue;
                if (s.visibility != 0) continue;
                sb.append (sheet_html (s));
            }
            sb.append ("</body>\n</html>\n");
            FileUtils.set_contents (path, sb.str);
        }
    }
}
