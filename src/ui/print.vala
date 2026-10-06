using Gtk;

namespace Singularity.Apps.Spreadsheet {

    public class SheetPrinter : Object {
        private Sheet sheet;
        private PageSetup setup;
        private Area? selected;
        private PrintLayout layout;
        private double page_w = 595.28;
        private double page_h = 841.89;
        public string file_name = "";
        public string file_path = "";

        public SheetPrinter (Sheet sheet, Area? selection) {
            this.sheet = sheet;
            this.setup = sheet.page;
            if (selection != null && !selection.is_single ()) selected = Document.clamp_area (sheet, selection);
        }

        public SheetPrinter.with_setup (Sheet sheet, PageSetup setup) {
            this.sheet = sheet;
            this.setup = setup;
        }

        public int pages {
            get { return layout != null ? layout.pages.size : 0; }
        }

        public int paginate (double width, double height, bool only_selection = false) {
            page_w = width;
            page_h = height;
            layout = PrintLayout.compute (sheet, setup, width, height, only_selection ? selected : null);
            return int.max (layout.pages.size, 1);
        }

        public int paginate_format (Singularity.Print.PageFormat format, bool only_selection) {
            return paginate (format.width, format.height, only_selection && selected != null);
        }

        public int paginate_own () {
            return paginate (setup.page_width, setup.page_height);
        }

        private double col_w (int c) {
            return sheet.col_width (c) * layout.scale;
        }

        private double row_h (int r) {
            return sheet.row_height (r) * layout.scale;
        }

        private double span_w (int c1, int c2) {
            double w = 0;
            for (int c = c1; c <= c2; c++) w += col_w (c);
            return w;
        }

        private double span_h (int r1, int r2) {
            double h = 0;
            for (int r = r1; r <= r2; r++) h += row_h (r);
            return h;
        }

        private void draw_hf (Cairo.Context cr, string code, double y, bool bottom, int index) {
            if (code == "") return;
            string l, c, r;
            HeaderFooter.split (code, out l, out c, out r);
            var ctx = new HFContext ();
            ctx.page = layout.page_number (index);
            ctx.pages = layout.pages.size + (setup.first_page_number > 0 ? setup.first_page_number - 1 : 0);
            ctx.sheet = sheet.name;
            ctx.file = file_name;
            ctx.path = file_path;
            double left = setup.align_with_margins ? setup.margin_left * 72 : 36;
            double right = page_w - (setup.align_with_margins ? setup.margin_right * 72 : 36);
            double base_size = setup.scale_with_doc ? 11 * layout.scale / PrintLayout.PX_TO_PT * 0.8 : 9;
            string[] parts = { l, c, r };
            for (int i = 0; i < 3; i++) {
                if (parts[i] == "") continue;
                var pl = Pango.cairo_create_layout (cr);
                pl.set_font_description (Pango.FontDescription.from_string ("Sans"));
                pl.set_markup (HeaderFooter.markup (parts[i], ctx, base_size), -1);
                int lw, lh;
                pl.get_pixel_size (out lw, out lh);
                double x = i == 0 ? left : (i == 1 ? (left + right - lw) / 2 : right - lw);
                double ty = bottom ? y - lh : y;
                cr.set_source_rgb (0, 0, 0);
                cr.move_to (x, ty);
                Pango.cairo_show_layout (cr, pl);
            }
        }

        public void render (Cairo.Context cr, int page, Pango.Context? pctx = null) {
            if (layout == null || layout.pages.size == 0) return;
            var pg = layout.pages[page.clamp (0, layout.pages.size - 1)];
            int number = layout.page_number (page);
            draw_hf (cr, setup.header_for (page, number), setup.margin_header * 72, false, page);
            draw_hf (cr, setup.footer_for (page, number), page_h - setup.margin_footer * 72, true, page);
            bool trows = layout.page_has_title_rows (pg);
            bool tcols = layout.page_has_title_cols (pg);
            double head_w = setup.headings ? PrintLayout.HEADING_W * layout.scale : 0;
            double head_h = setup.headings ? PrintLayout.HEADING_H * layout.scale : 0;
            double tw = tcols ? span_w (layout.title_c1, layout.title_c2) : 0;
            double th = trows ? span_h (layout.title_r1, layout.title_r2) : 0;
            double body_w = span_w (pg.c1, pg.c2);
            double body_h = span_h (pg.r1, pg.r2);
            double total_w = head_w + tw + body_w;
            double total_h = head_h + th + body_h;
            double x0 = setup.margin_left * 72;
            double y0 = setup.margin_top * 72;
            if (setup.center_h) x0 += double.max (0, (layout.content_w - total_w) / 2);
            if (setup.center_v) y0 += double.max (0, (layout.content_h - total_h) / 2);
            double bx = x0 + head_w + tw;
            double by = y0 + head_h + th;
            if (trows && tcols) block (cr, layout.title_r1, layout.title_r2, layout.title_c1, layout.title_c2, x0 + head_w, y0 + head_h);
            if (trows) block (cr, layout.title_r1, layout.title_r2, pg.c1, pg.c2, bx, y0 + head_h);
            if (tcols) block (cr, pg.r1, pg.r2, layout.title_c1, layout.title_c2, x0 + head_w, by);
            block (cr, pg.r1, pg.r2, pg.c1, pg.c2, bx, by);
            if (setup.headings) {
                var hl = Pango.cairo_create_layout (cr);
                var fd = Pango.FontDescription.from_string ("Sans");
                fd.set_absolute_size (9 * 96 / 72 * layout.scale * Pango.SCALE);
                hl.set_font_description (fd);
                cr.set_line_width (0.5);
                double x = x0 + head_w;
                int[] cols = {};
                if (tcols) for (int c = layout.title_c1; c <= layout.title_c2; c++) cols += c;
                for (int c = pg.c1; c <= pg.c2; c++) cols += c;
                foreach (int c in cols) {
                    double w = col_w (c);
                    if (w <= 0) continue;
                    heading_cell (cr, hl, Address.column_name (c), x, y0, w, head_h);
                    x += w;
                }
                double y = y0 + head_h;
                int[] rows = {};
                if (trows) for (int r = layout.title_r1; r <= layout.title_r2; r++) rows += r;
                for (int r = pg.r1; r <= pg.r2; r++) rows += r;
                foreach (int r in rows) {
                    double h = row_h (r);
                    if (h <= 0) continue;
                    heading_cell (cr, hl, (r + 1).to_string (), x0, y, head_w, h);
                    y += h;
                }
            }
        }

        private void heading_cell (Cairo.Context cr, Pango.Layout hl, string text, double x, double y, double w, double h) {
            cr.rectangle (x, y, w, h);
            cr.set_source_rgb (0.93, 0.93, 0.93);
            cr.fill_preserve ();
            cr.set_source_rgb (0.6, 0.6, 0.6);
            cr.stroke ();
            hl.set_text (text, -1);
            int lw, lh;
            hl.get_pixel_size (out lw, out lh);
            cr.set_source_rgb (0.2, 0.2, 0.2);
            cr.move_to (x + (w - lw) / 2, y + (h - lh) / 2);
            Pango.cairo_show_layout (cr, hl);
        }

        private void block (Cairo.Context cr, int r1, int r2, int c1, int c2, double x0, double y0) {
            var xs = new Gee.HashMap<int, double?> ();
            var ys = new Gee.HashMap<int, double?> ();
            double x = x0;
            for (int c = c1; c <= c2 + 1; c++) {
                xs[c] = x;
                if (c <= c2) x += col_w (c);
            }
            double y = y0;
            for (int r = r1; r <= r2 + 1; r++) {
                ys[r] = y;
                if (r <= r2) y += row_h (r);
            }
            var layout_t = Pango.cairo_create_layout (cr);
            for (int r = r1; r <= r2; r++) {
                for (int c = c1; c <= c2; c++) {
                    var cell = sheet.get_cell (r, c);
                    if (cell == null) continue;
                    var st = sheet.book.styles[cell.style];
                    if (st.fill == "" || setup.black_and_white) continue;
                    var col = Gdk.RGBA ();
                    if (!col.parse (st.fill)) continue;
                    cr.rectangle (xs[c], ys[r], xs[c + 1] - xs[c], ys[r + 1] - ys[r]);
                    cr.set_source_rgb (col.red, col.green, col.blue);
                    cr.fill ();
                }
            }
            if (setup.gridlines) {
                cr.set_source_rgb (0.75, 0.76, 0.78);
                cr.set_line_width (0.5);
                for (int c = c1; c <= c2 + 1; c++) {
                    cr.move_to (xs[c], y0);
                    cr.line_to (xs[c], ys[r2 + 1]);
                }
                for (int r = r1; r <= r2 + 1; r++) {
                    cr.move_to (x0, ys[r]);
                    cr.line_to (xs[c2 + 1], ys[r]);
                }
                cr.stroke ();
            }
            for (int r = r1; r <= r2; r++) {
                if (sheet.row_height (r) == 0) continue;
                for (int c = c1; c <= c2; c++) {
                    if (sheet.col_width (c) == 0) continue;
                    var cell = sheet.get_cell (r, c);
                    var v = sheet.value_at (r, c);
                    if (cell == null && v.is_empty ()) continue;
                    var m = sheet.merge_at (r, c);
                    if (m != null && (m.r1 != r || m.c1 != c)) continue;
                    var st = sheet.book.styles[cell != null ? cell.style : 0];
                    string color;
                    string text = NumberFormat.format_value (v, st.number_format, out color, sheet.book.date1904);
                    double cx1 = xs[c], cy1 = ys[r];
                    int mc2 = m != null ? int.min (m.c2, c2) : c;
                    int mr2 = m != null ? int.min (m.r2, r2) : r;
                    double cw = xs[mc2 + 1] - cx1, ch = ys[mr2 + 1] - cy1;
                    if (text != "") {
                        var fd = Pango.FontDescription.from_string (st.font_family != "" ? st.font_family : "Sans");
                        fd.set_absolute_size (st.font_size * 96 / 72 * layout.scale * Pango.SCALE);
                        fd.set_weight (st.bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
                        fd.set_style (st.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL);
                        layout_t.set_font_description (fd);
                        var attrs = new Pango.AttrList ();
                        if (st.underline) attrs.insert (Pango.attr_underline_new (Pango.Underline.SINGLE));
                        if (st.strike) attrs.insert (Pango.attr_strikethrough_new (true));
                        layout_t.set_attributes (attrs);
                        layout_t.set_width (st.wrap ? (int) ((cw - 4) * Pango.SCALE) : -1);
                        layout_t.set_wrap (Pango.WrapMode.WORD_CHAR);
                        layout_t.set_text (st.wrap ? text : text.replace ("\n", " "), -1);
                        int lw, lh;
                        layout_t.get_pixel_size (out lw, out lh);
                        HAlign ha = st.halign;
                        if (ha == HAlign.GENERAL) ha = v.kind == ValueKind.NUMBER ? HAlign.RIGHT : (v.kind == ValueKind.TEXT ? HAlign.LEFT : HAlign.CENTER);
                        double pad = 2.2 * layout.scale / PrintLayout.PX_TO_PT;
                        double tx = ha == HAlign.RIGHT ? cx1 + cw - pad - lw : (ha == HAlign.CENTER ? cx1 + (cw - lw) / 2 : cx1 + pad + st.indent * 6 * layout.scale);
                        double ty = st.valign == VAlign.TOP ? cy1 + 1 : (st.valign == VAlign.CENTER ? cy1 + (ch - lh) / 2 : cy1 + ch - lh - 1);
                        cr.save ();
                        double clip_w = cw;
                        if (!st.wrap && v.kind == ValueKind.TEXT && ha == HAlign.LEFT && m == null) {
                            int cc = c + 1;
                            while (clip_w < lw + pad * 2 && cc <= c2 && sheet.value_at (r, cc).is_empty ()) {
                                clip_w += xs[cc + 1] - xs[cc];
                                cc++;
                            }
                        }
                        cr.rectangle (cx1, cy1, clip_w, ch);
                        cr.clip ();
                        var tc = Gdk.RGBA ();
                        if (setup.black_and_white || st.color == "" || !tc.parse (st.color)) tc.parse ("#000000");
                        if (v.kind == ValueKind.ERROR && !setup.black_and_white) tc.parse ("#c01c28");
                        cr.set_source_rgb (tc.red, tc.green, tc.blue);
                        cr.move_to (tx, ty);
                        Pango.cairo_show_layout (cr, layout_t);
                        cr.restore ();
                    }
                    draw_side (cr, st.top, cx1, cy1, cx1 + cw, cy1);
                    draw_side (cr, st.bottom, cx1, cy1 + ch, cx1 + cw, cy1 + ch);
                    draw_side (cr, st.left, cx1, cy1, cx1, cy1 + ch);
                    draw_side (cr, st.right, cx1 + cw, cy1, cx1 + cw, cy1 + ch);
                }
            }
        }

        private static void draw_side (Cairo.Context cr, Border b, double x1, double y1, double x2, double y2) {
            if (b.style == BorderStyle.NONE) return;
            var c = Gdk.RGBA ();
            if (b.color == "" || !c.parse (b.color)) c.parse ("#000000");
            cr.set_source_rgb (c.red, c.green, c.blue);
            cr.set_line_width (b.style == BorderStyle.MEDIUM ? 1.2 : (b.style == BorderStyle.THICK ? 2 : 0.6));
            if (b.style == BorderStyle.DASHED) cr.set_dash ({ 3, 1.5 }, 0);
            if (b.style == BorderStyle.DOTTED) cr.set_dash ({ 0.8, 1.5 }, 0);
            cr.move_to (x1, y1);
            cr.line_to (x2, y2);
            cr.stroke ();
            cr.set_dash (null, 0);
        }

        public void export_pdf (string path) {
            int n = paginate_own ();
            var surface = new Cairo.PdfSurface (path, page_w, page_h);
            var cr = new Cairo.Context (surface);
            for (int p = 0; p < n; p++) {
                render (cr, p);
                cr.show_page ();
            }
            surface.finish ();
        }

        public void print (Gtk.Window parent) {
            var source = new SheetPageSource (this, sheet.name);
            source.has_selection = selected != null;
            var app = GLib.Application.get_default ();
            string app_id = app != null && app.application_id != null ? app.application_id : "dev.sinty.spreadsheet";
            var last = Singularity.Print.PresetStore.get_default ().last_used (app_id);
            var opts = last != null ? last.copy () : new Singularity.Print.JobOptions ();
            opts.landscape = setup.landscape;
            opts.media = media_name (setup.paper);
            Singularity.Print.run_source.begin (parent, source, opts);
        }

        private static string media_name (int paper) {
            switch (paper) {
                case 1: return "na_letter_8.5x11in";
                case 5: return "na_legal_8.5x14in";
                case 8: return "iso_a3_297x420mm";
                case 11: return "iso_a5_148x210mm";
                case 3: return "na_ledger_11x17in";
                case 7: return "na_executive_7.25x10.5in";
                case 13: return "jis_b5_182x257mm";
                case 20: return "na_number-10_4.125x9.5in";
                case 27: return "iso_dl_110x220mm";
                default: return "iso_a4_210x297mm";
            }
        }

        public static void page_setup (Gtk.Window parent) {
            var win = parent as SpreadsheetWindow;
            if (win != null && win.grid != null) {
                PageSetupDialog.show (win);
                return;
            }
            Singularity.Print.page_setup.begin (parent);
        }
    }

    public class SheetPageSource : Singularity.Print.PageSource {
        private SheetPrinter printer;

        public SheetPageSource (SheetPrinter printer, string title) {
            this.printer = printer;
            this.title = title;
        }

        public override async int paginate (Singularity.Print.PageFormat format) throws Error {
            page_width = format.width;
            page_height = format.height;
            return printer.paginate_format (format, print_selection);
        }

        public override void render_page (Cairo.Context cr, int index) {
            printer.render (cr, index);
        }
    }
}
