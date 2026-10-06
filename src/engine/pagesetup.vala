namespace Singularity.Apps.Spreadsheet {

    public class PaperSize {
        public int code;
        public string name;
        public double width;
        public double height;

        public PaperSize (int code, string name, double width, double height) {
            this.code = code;
            this.name = name;
            this.width = width;
            this.height = height;
        }

        private static PaperSize[]? table = null;

        public static PaperSize[] all () {
            if (table == null) {
                table = {
                    new PaperSize (9, "A4", 595.28, 841.89),
                    new PaperSize (1, "Letter", 612, 792),
                    new PaperSize (5, "Legal", 612, 1008),
                    new PaperSize (8, "A3", 841.89, 1190.55),
                    new PaperSize (11, "A5", 419.53, 595.28),
                    new PaperSize (3, "Tabloid", 792, 1224),
                    new PaperSize (7, "Executive", 522, 756),
                    new PaperSize (13, "B5", 515.91, 728.5),
                    new PaperSize (20, "Envelope #10", 297, 684),
                    new PaperSize (27, "Envelope DL", 311.81, 623.62)
                };
            }
            return table;
        }

        public static PaperSize find (int code) {
            foreach (var p in all ()) if (p.code == code) return p;
            return all ()[0];
        }

        public static PaperSize? by_size (double w, double h) {
            double a = double.min (w, h), b = double.max (w, h);
            foreach (var p in all ()) if (Math.fabs (p.width - a) < 4 && Math.fabs (p.height - b) < 4) return p;
            return null;
        }
    }

    public class PageSetup {
        public string print_area = "";
        public string title_rows = "";
        public string title_cols = "";
        public bool landscape;
        public int paper = 9;
        public double margin_left = 0.7;
        public double margin_right = 0.7;
        public double margin_top = 0.75;
        public double margin_bottom = 0.75;
        public double margin_header = 0.3;
        public double margin_footer = 0.3;
        public int scale = 100;
        public bool fit_to_page;
        public int fit_width = 1;
        public int fit_height = 1;
        public bool center_h;
        public bool center_v;
        public bool gridlines;
        public bool headings;
        public bool over_then_down;
        public bool black_and_white;
        public int first_page_number;
        public string header = "";
        public string footer = "";
        public string even_header = "";
        public string even_footer = "";
        public string first_header = "";
        public string first_footer = "";
        public bool odd_even;
        public bool first_different;
        public bool scale_with_doc = true;
        public bool align_with_margins = true;
        public Gee.TreeSet<int> row_breaks = new Gee.TreeSet<int> ();
        public Gee.TreeSet<int> col_breaks = new Gee.TreeSet<int> ();

        public PageSetup copy () {
            var p = new PageSetup ();
            p.print_area = print_area;
            p.title_rows = title_rows;
            p.title_cols = title_cols;
            p.landscape = landscape;
            p.paper = paper;
            p.margin_left = margin_left;
            p.margin_right = margin_right;
            p.margin_top = margin_top;
            p.margin_bottom = margin_bottom;
            p.margin_header = margin_header;
            p.margin_footer = margin_footer;
            p.scale = scale;
            p.fit_to_page = fit_to_page;
            p.fit_width = fit_width;
            p.fit_height = fit_height;
            p.center_h = center_h;
            p.center_v = center_v;
            p.gridlines = gridlines;
            p.headings = headings;
            p.over_then_down = over_then_down;
            p.black_and_white = black_and_white;
            p.first_page_number = first_page_number;
            p.header = header;
            p.footer = footer;
            p.even_header = even_header;
            p.even_footer = even_footer;
            p.first_header = first_header;
            p.first_footer = first_footer;
            p.odd_even = odd_even;
            p.first_different = first_different;
            p.scale_with_doc = scale_with_doc;
            p.align_with_margins = align_with_margins;
            p.row_breaks.add_all (row_breaks);
            p.col_breaks.add_all (col_breaks);
            return p;
        }

        public bool is_default () {
            return print_area == "" && title_rows == "" && title_cols == "" && !landscape && paper == 9
                && margin_left == 0.7 && margin_right == 0.7 && margin_top == 0.75 && margin_bottom == 0.75
                && margin_header == 0.3 && margin_footer == 0.3 && scale == 100 && !fit_to_page && !center_h && !center_v
                && !gridlines && !headings && !over_then_down && !black_and_white && first_page_number == 0
                && header == "" && footer == "" && even_header == "" && even_footer == "" && first_header == "" && first_footer == ""
                && !odd_even && !first_different && row_breaks.size == 0 && col_breaks.size == 0;
        }

        public double page_width {
            get {
                var p = PaperSize.find (paper);
                return landscape ? p.height : p.width;
            }
        }

        public double page_height {
            get {
                var p = PaperSize.find (paper);
                return landscape ? p.width : p.height;
            }
        }

        public Gee.ArrayList<Area> print_areas (Sheet s) {
            var list = new Gee.ArrayList<Area> ();
            foreach (string part in print_area.split (",")) {
                string t = strip_sheet (part.strip ()).replace ("$", "");
                if (t == "") continue;
                var a = Area.parse (t, s);
                if (a != null) list.add (a);
            }
            return list;
        }

        public static string strip_sheet (string t) {
            int bang = t.last_index_of ("!");
            return bang >= 0 ? t.substring (bang + 1) : t;
        }

        public bool title_row_range (out int r1, out int r2) {
            r1 = r2 = -1;
            string t = strip_sheet (title_rows.strip ()).replace ("$", "");
            if (t == "") return false;
            string[] p = t.split (":");
            r1 = int.parse (p[0]) - 1;
            r2 = p.length > 1 ? int.parse (p[1]) - 1 : r1;
            if (r1 < 0 || r2 < r1) return false;
            return true;
        }

        public bool title_col_range (out int c1, out int c2) {
            c1 = c2 = -1;
            string t = strip_sheet (title_cols.strip ()).replace ("$", "");
            if (t == "") return false;
            string[] p = t.split (":");
            c1 = Address.column_index (p[0]);
            c2 = p.length > 1 ? Address.column_index (p[1]) : c1;
            if (c1 < 0 || c2 < c1) return false;
            return true;
        }

        public static string rows_text (int r1, int r2) {
            return "$%d:$%d".printf (r1 + 1, r2 + 1);
        }

        public static string cols_text (int c1, int c2) {
            return "$%s:$%s".printf (Address.column_name (c1), Address.column_name (c2));
        }

        public string header_for (int page_index, int number) {
            if (first_different && page_index == 0) return first_header;
            if (odd_even && number % 2 == 0) return even_header;
            return header;
        }

        public string footer_for (int page_index, int number) {
            if (first_different && page_index == 0) return first_footer;
            if (odd_even && number % 2 == 0) return even_footer;
            return footer;
        }

        public void set_break (bool rows, int at, bool on) {
            var set = rows ? row_breaks : col_breaks;
            if (on) set.add (at);
            else set.remove (at);
        }
    }

    public class HFContext {
        public int page = 1;
        public int pages = 1;
        public string sheet = "";
        public string file = "";
        public string path = "";
        public DateTime now;

        public HFContext () {
            now = new DateTime.now_local ();
        }
    }

    public class HFRun {
        public string text = "";
        public bool bold;
        public bool italic;
        public bool underline;
        public bool strike;
        public bool superscript;
        public bool subscript;
        public double size;
        public string font = "";
        public string color = "";
    }

    public class HeaderFooter {
        public static void split (string code, out string left, out string center, out string right) {
            var l = new StringBuilder ();
            var c = new StringBuilder ();
            var r = new StringBuilder ();
            unowned StringBuilder cur = c;
            int i = 0;
            while (i < code.length) {
                if (code[i] == '&' && i + 1 < code.length) {
                    char n = code[i + 1];
                    if (n == 'L') {
                        cur = l;
                        i += 2;
                        continue;
                    }
                    if (n == 'C') {
                        cur = c;
                        i += 2;
                        continue;
                    }
                    if (n == 'R') {
                        cur = r;
                        i += 2;
                        continue;
                    }
                    cur.append_c ('&');
                    cur.append_c (n);
                    i += 2;
                    if (n == '"') {
                        while (i < code.length && code[i] != '"') {
                            cur.append_c (code[i]);
                            i++;
                        }
                        if (i < code.length) {
                            cur.append_c ('"');
                            i++;
                        }
                    }
                    continue;
                }
                cur.append_c (code[i]);
                i++;
            }
            left = l.str;
            center = c.str;
            right = r.str;
        }

        public static string join (string left, string center, string right) {
            var sb = new StringBuilder ();
            if (left != "") sb.append ("&L" + left);
            if (center != "") sb.append ("&C" + center);
            if (right != "") sb.append ("&R" + right);
            return sb.str;
        }

        public static Gee.ArrayList<HFRun> expand (string section, HFContext ctx) {
            var runs = new Gee.ArrayList<HFRun> ();
            var cur = new HFRun ();
            var text = new StringBuilder ();
            int i = 0;
            int n = section.length;
            while (i < n) {
                char c = section[i];
                if (c != '&' || i + 1 >= n) {
                    text.append_c (c);
                    i++;
                    continue;
                }
                char k = section[i + 1];
                i += 2;
                switch (k) {
                    case '&':
                        text.append_c ('&');
                        continue;
                    case 'P':
                    case 'N':
                        int v = k == 'P' ? ctx.page : ctx.pages;
                        if (k == 'P' && i < n && (section[i] == '+' || section[i] == '-')) {
                            int j = i + 1;
                            while (j < n && section[j].isdigit ()) j++;
                            if (j > i + 1) {
                                int d = int.parse (section.substring (i + 1, j - i - 1));
                                v += section[i] == '+' ? d : -d;
                                i = j;
                            }
                        }
                        text.append (v.to_string ());
                        continue;
                    case 'D':
                        text.append (ctx.now.format ("%x"));
                        continue;
                    case 'T':
                        text.append (ctx.now.format ("%X"));
                        continue;
                    case 'F':
                        text.append (ctx.file);
                        continue;
                    case 'Z':
                        text.append (ctx.path);
                        continue;
                    case 'A':
                        text.append (ctx.sheet);
                        continue;
                    case 'G':
                        continue;
                }
                if (text.len > 0) {
                    cur.text = text.str;
                    runs.add (cur);
                    cur = clone (cur);
                    text.truncate ();
                }
                if (k.isdigit ()) {
                    int j = i - 1;
                    while (j < n && section[j].isdigit ()) j++;
                    cur.size = double.parse (section.substring (i - 1, j - i + 1));
                    i = j;
                    continue;
                }
                switch (k) {
                    case 'B': cur.bold = !cur.bold; break;
                    case 'I': cur.italic = !cur.italic; break;
                    case 'U': case 'E': cur.underline = !cur.underline; break;
                    case 'S': cur.strike = !cur.strike; break;
                    case 'X': cur.superscript = !cur.superscript; break;
                    case 'Y': cur.subscript = !cur.subscript; break;
                    case 'K':
                        if (i + 6 <= n) {
                            cur.color = "#" + section.substring (i, 6);
                            i += 6;
                        }
                        break;
                    case '"':
                        int end = section.index_of_char ('"', i);
                        if (end < 0) end = n;
                        string spec = section.substring (i, end - i);
                        i = int.min (end + 1, n);
                        string[] fp = spec.split (",");
                        if (fp[0] != "-" && fp[0] != "") cur.font = fp[0];
                        if (fp.length > 1) {
                            string style = fp[1].down ();
                            cur.bold = style.contains ("bold");
                            cur.italic = style.contains ("italic") || style.contains ("oblique");
                        }
                        break;
                }
            }
            if (text.len > 0) {
                cur.text = text.str;
                runs.add (cur);
            }
            return runs;
        }

        private static HFRun clone (HFRun r) {
            var c = new HFRun ();
            c.bold = r.bold;
            c.italic = r.italic;
            c.underline = r.underline;
            c.strike = r.strike;
            c.superscript = r.superscript;
            c.subscript = r.subscript;
            c.size = r.size;
            c.font = r.font;
            c.color = r.color;
            return c;
        }

        public static string plain (string section, HFContext ctx) {
            var sb = new StringBuilder ();
            foreach (var r in expand (section, ctx)) sb.append (r.text);
            return sb.str;
        }

        public static string markup (string section, HFContext ctx, double base_size) {
            var sb = new StringBuilder ();
            foreach (var r in expand (section, ctx)) {
                sb.append ("<span");
                if (r.bold) sb.append (" weight=\"bold\"");
                if (r.italic) sb.append (" style=\"italic\"");
                if (r.underline) sb.append (" underline=\"single\"");
                if (r.strike) sb.append (" strikethrough=\"true\"");
                if (r.font != "") sb.append (" font_family=\"%s\"".printf (Markup.escape_text (r.font)));
                double size = r.size > 0 ? r.size : base_size;
                if (r.superscript || r.subscript) size *= 0.7;
                sb.append (" size=\"%d\"".printf ((int) Math.round (size * 1024)));
                if (r.superscript) sb.append (" rise=\"%d\"".printf ((int) (size * 0.4 * 1024)));
                if (r.subscript) sb.append (" rise=\"-%d\"".printf ((int) (size * 0.2 * 1024)));
                if (r.color != "") sb.append (" foreground=\"%s\"".printf (r.color));
                sb.append (">");
                sb.append (Markup.escape_text (r.text));
                sb.append ("</span>");
            }
            return sb.str;
        }
    }

    public class PrintPage {
        public int area_index;
        public int r1;
        public int r2;
        public int c1;
        public int c2;
        public bool manual_row_end;
        public bool manual_col_end;
    }

    public class PrintLayout {
        public const double PX_TO_PT = 0.75;
        public const double HEADING_W = 34;
        public const double HEADING_H = 18;

        public Sheet sheet;
        public PageSetup setup;
        public double scale = PX_TO_PT;
        public double content_w;
        public double content_h;
        public Gee.ArrayList<Area> areas = new Gee.ArrayList<Area> ();
        public Gee.ArrayList<PrintPage> pages = new Gee.ArrayList<PrintPage> ();
        public int title_r1 = -1;
        public int title_r2 = -1;
        public int title_c1 = -1;
        public int title_c2 = -1;
        public int pages_wide;
        public int pages_tall;

        public PrintLayout (Sheet sheet, PageSetup setup) {
            this.sheet = sheet;
            this.setup = setup;
        }

        public static Area used (Sheet s) {
            return new Area (s, 0, 0, int.max (s.max_row, 0), int.max (s.max_col, 0));
        }

        public static PrintLayout compute (Sheet s, PageSetup p, double page_w, double page_h, Area? only = null) {
            var l = new PrintLayout (s, p);
            if (only != null) {
                l.areas.add (only);
            } else {
                var list = p.print_areas (s);
                if (list.size == 0) list.add (used (s));
                l.areas.add_all (list);
            }
            int tr1, tr2, tc1, tc2;
            if (p.title_row_range (out tr1, out tr2)) {
                l.title_r1 = tr1;
                l.title_r2 = tr2;
            }
            if (p.title_col_range (out tc1, out tc2)) {
                l.title_c1 = tc1;
                l.title_c2 = tc2;
            }
            l.content_w = page_w - (p.margin_left + p.margin_right) * 72;
            l.content_h = page_h - (p.margin_top + p.margin_bottom) * 72;
            if (p.fit_to_page) {
                double lo = 0.1, hi = 1.0;
                l.scale = PX_TO_PT;
                l.paginate ();
                if (!l.fits ()) {
                    for (int it = 0; it < 24; it++) {
                        double mid = (lo + hi) / 2;
                        l.scale = PX_TO_PT * mid;
                        l.paginate ();
                        if (l.fits ()) lo = mid;
                        else hi = mid;
                    }
                    l.scale = PX_TO_PT * lo;
                }
            } else {
                l.scale = PX_TO_PT * p.scale.clamp (10, 400) / 100.0;
            }
            l.paginate ();
            return l;
        }

        private bool fits () {
            if (setup.fit_width > 0 && pages_wide > setup.fit_width) return false;
            if (setup.fit_height > 0 && pages_tall > setup.fit_height) return false;
            return true;
        }

        public double title_rows_height () {
            if (title_r1 < 0) return 0;
            double h = 0;
            for (int r = title_r1; r <= title_r2; r++) h += sheet.row_height (r);
            return h * scale;
        }

        public double title_cols_width () {
            if (title_c1 < 0) return 0;
            double w = 0;
            for (int c = title_c1; c <= title_c2; c++) w += sheet.col_width (c);
            return w * scale;
        }

        public double avail_w {
            get { return content_w - (setup.headings ? HEADING_W * scale : 0); }
        }

        public double avail_h {
            get { return content_h - (setup.headings ? HEADING_H * scale : 0); }
        }

        private Gee.ArrayList<int> bands (bool rows, int a, int b, out Gee.ArrayList<bool> manual) {
            var starts = new Gee.ArrayList<int> ();
            manual = new Gee.ArrayList<bool> ();
            starts.add (a);
            double acc = 0;
            for (int i = a; i <= b; i++) {
                int band_start = starts[starts.size - 1];
                double reserve = rows ? (title_r1 >= 0 && band_start > title_r2 ? title_rows_height () : 0) : (title_c1 >= 0 && band_start > title_c2 ? title_cols_width () : 0);
                double limit = (rows ? avail_h : avail_w) - reserve;
                double size = (rows ? sheet.row_height (i) : sheet.col_width (i)) * scale;
                bool forced = i > a && (rows ? setup.row_breaks.contains (i) : setup.col_breaks.contains (i));
                if (forced || (acc + size > limit && acc > 0)) {
                    manual.add (forced);
                    starts.add (i);
                    acc = 0;
                }
                acc += size;
            }
            manual.add (false);
            return starts;
        }

        public void paginate () {
            pages.clear ();
            pages_wide = 0;
            pages_tall = 0;
            for (int ai = 0; ai < areas.size; ai++) {
                var a = areas[ai];
                int r2 = a.r2, c2 = a.c2;
                if (r2 == MAX_ROWS - 1) r2 = int.max (sheet.max_row, a.r1);
                if (c2 == MAX_COLS - 1) c2 = int.max (sheet.max_col, a.c1);
                Gee.ArrayList<bool> rm, cm;
                var rs = bands (true, a.r1, r2, out rm);
                var cs = bands (false, a.c1, c2, out cm);
                pages_wide = int.max (pages_wide, cs.size);
                pages_tall = int.max (pages_tall, rs.size);
                int outer = setup.over_then_down ? rs.size : cs.size;
                int inner = setup.over_then_down ? cs.size : rs.size;
                for (int o = 0; o < outer; o++) {
                    for (int i = 0; i < inner; i++) {
                        int ri = setup.over_then_down ? o : i;
                        int ci = setup.over_then_down ? i : o;
                        var pg = new PrintPage ();
                        pg.area_index = ai;
                        pg.r1 = rs[ri];
                        pg.r2 = ri + 1 < rs.size ? rs[ri + 1] - 1 : r2;
                        pg.c1 = cs[ci];
                        pg.c2 = ci + 1 < cs.size ? cs[ci + 1] - 1 : c2;
                        pg.manual_row_end = rm[ri];
                        pg.manual_col_end = cm[ci];
                        pages.add (pg);
                    }
                }
            }
        }

        public bool page_has_title_rows (PrintPage p) {
            return title_r1 >= 0 && p.r1 > title_r2;
        }

        public bool page_has_title_cols (PrintPage p) {
            return title_c1 >= 0 && p.c1 > title_c2;
        }

        public int page_number (int index) {
            return (setup.first_page_number > 0 ? setup.first_page_number : 1) + index;
        }
    }
}
