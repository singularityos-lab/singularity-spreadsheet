using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class ToolDialogs {
        public delegate void Apply ();

        public static AppDialog make (SpreadsheetWindow win, string title, int width, int height) {
            var dlg = new AppDialog ((Gtk.Application) win.application, true);
            dlg.set_title (title);
            dlg.transient_for = win;
            dlg.set_default_size (width, height);
            dlg.add_css_class ("ss-dialog");
            return dlg;
        }

        public static Box scroll_box (Widget parent_box) {
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.hexpand = true;
            var box = new Box (Orientation.VERTICAL, 14);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 12;
            scroll.child = box;
            ((Box) parent_box).append (scroll);
            return box;
        }

        public static Box footer (AppDialog dlg, string label, owned Apply apply, bool close_after = true) {
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.add_css_class ("ss-dialog-footer");
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (cancel);
            var ok = new Button.with_label (label);
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                apply ();
                if (close_after) dlg.close ();
            });
            bar.append (cancel);
            bar.append (ok);
            dlg.content_box.append (bar);
            dlg.default_widget = ok;
            return bar;
        }

        public static Box close_footer (AppDialog dlg) {
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.add_css_class ("ss-dialog-footer");
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var close = new Button.with_label (_("Close"));
            close.add_css_class ("suggested-action");
            close.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (close);
            bar.append (close);
            dlg.content_box.append (bar);
            return bar;
        }

        public static Button flat (string icon, string tip) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("flat");
            b.valign = Align.CENTER;
            b.tooltip_text = tip;
            return b;
        }

        public static string area_text (Area a) {
            if (a.is_single ()) return Address.cell (a.r1, a.c1);
            return Address.cell (a.r1, a.c1) + ":" + Address.cell (a.r2, a.c2);
        }
    }

    public class PageSetupDialog : Object {
        private SpreadsheetWindow win;
        private Sheet sheet;
        private PageSetup work;
        private DrawingArea preview;
        private Label page_label;
        private int preview_page;
        private string[] hf_targets;
        private int hf_index;
        private EntryRow hf_left;
        private EntryRow hf_center;
        private EntryRow hf_right;
        private bool loading;

        private const double CM = 2.54;

        public static void show (SpreadsheetWindow win) {
            var d = new PageSetupDialog (win);
            d.open ();
        }

        public PageSetupDialog (SpreadsheetWindow win) {
            this.win = win;
            this.sheet = win.grid.sheet;
            this.work = sheet.page.copy ();
        }

        private static string[] presets () {
            return { _("None"), _("Page 1"), _("Page 1 of 5"), _("Sheet Name"), _("File Name"), _("Sheet Name and Page"), _("Date and Time"), _("Custom") };
        }

        private static string preset_code (int i) {
            switch (i) {
                case 1: return "&C" + _("Page") + " &P";
                case 2: return "&C" + _("Page") + " &P " + _("of") + " &N";
                case 3: return "&C&A";
                case 4: return "&C&F";
                case 5: return "&L&A&R" + _("Page") + " &P";
                case 6: return "&L&D&R&T";
                default: return "";
            }
        }

        private static int preset_of (string code) {
            if (code == "") return 0;
            for (int i = 1; i < 7; i++) if (preset_code (i) == code) return i;
            return 7;
        }

        private SpinRow spin (PreferencesGroup g, string title, string? sub, double min, double max, double step, double val) {
            var r = new SpinRow (title, sub, min, max, step, val);
            g.add_row (r);
            return r;
        }

        private SwitchRow sw (PreferencesGroup g, string title, bool on) {
            var r = new SwitchRow (title, null, on);
            g.add_row (r);
            return r;
        }

        private string hf_get (int i) {
            switch (i) {
                case 0: return work.header;
                case 1: return work.footer;
                case 2: return work.first_header;
                case 3: return work.first_footer;
                case 4: return work.even_header;
                default: return work.even_footer;
            }
        }

        private void hf_set (int i, string v) {
            switch (i) {
                case 0: work.header = v; break;
                case 1: work.footer = v; break;
                case 2: work.first_header = v; break;
                case 3: work.first_footer = v; break;
                case 4: work.even_header = v; break;
                default: work.even_footer = v; break;
            }
        }

        private void load_hf () {
            loading = true;
            string l, c, r;
            HeaderFooter.split (hf_get (hf_index), out l, out c, out r);
            hf_left.text = l;
            hf_center.text = c;
            hf_right.text = r;
            loading = false;
        }

        private void store_hf () {
            if (loading) return;
            hf_set (hf_index, HeaderFooter.join (hf_left.text, hf_center.text, hf_right.text));
            refresh ();
        }

        private void refresh () {
            if (preview != null) preview.queue_draw ();
        }

        public void open () {
            var dlg = ToolDialogs.make (win, _("Page Setup"), 900, 640);
            var outer = new Box (Orientation.HORIZONTAL, 0);
            outer.vexpand = true;
            var left = new Box (Orientation.VERTICAL, 8);
            left.hexpand = true;
            var stack = new Stack ();
            stack.vexpand = true;
            var switcher = new BubbleSwitcher ();
            switcher.add_option ("page", _("Page"));
            switcher.add_option ("margins", _("Margins"));
            switcher.add_option ("headers", _("Header and Footer"));
            switcher.add_option ("sheet", _("Sheet"));
            switcher.selected.connect ((name) => stack.visible_child_name = name);
            switcher.add_css_class ("singularity-hover-btn");
            switcher.margin_top = 4;
            left.append (switcher);
            left.append (stack);
            outer.append (left);

            var page_box = new Box (Orientation.VERTICAL, 0);
            var pb = ToolDialogs.scroll_box (page_box);
            var g1 = new PreferencesGroup (_("Paper"));
            string[] orients = { _("Portrait"), _("Landscape") };
            var orient = new SelectionRow (_("Orientation"), orients, work.landscape ? orients[1] : orients[0]);
            g1.add_row (orient);
            string[] papers = {};
            foreach (var p in PaperSize.all ()) papers += p.name;
            var paper = new SelectionRow (_("Paper Size"), papers, PaperSize.find (work.paper).name);
            g1.add_row (paper);
            pb.append (g1);
            var g2 = new PreferencesGroup (_("Scaling"));
            string[] modes = { _("Adjust to a percentage"), _("Fit to pages") };
            var mode = new SelectionRow (_("Scaling"), modes, work.fit_to_page ? modes[1] : modes[0]);
            g2.add_row (mode);
            var pct = spin (g2, _("Percentage of normal size"), null, 10, 400, 5, work.scale);
            var fw = spin (g2, _("Pages wide"), _("0 means automatic"), 0, 999, 1, work.fit_width);
            var fh = spin (g2, _("Pages tall"), _("0 means automatic"), 0, 999, 1, work.fit_height);
            var first = spin (g2, _("First page number"), _("0 means automatic"), 0, 99999, 1, work.first_page_number);
            pb.append (g2);
            ToolDialogs.Apply sync_mode = () => {
                bool fit = mode.current_value == modes[1];
                pct.visible = !fit;
                fw.visible = fit;
                fh.visible = fit;
            };
            sync_mode ();
            orient.selected.connect ((v) => {
                work.landscape = v == orients[1];
                refresh ();
            });
            paper.selected.connect ((v) => {
                foreach (var p in PaperSize.all ()) if (p.name == v) work.paper = p.code;
                refresh ();
            });
            mode.selected.connect ((v) => {
                work.fit_to_page = v == modes[1];
                sync_mode ();
                refresh ();
            });
            pct.spin_btn.value_changed.connect (() => {
                work.scale = (int) pct.value;
                refresh ();
            });
            fw.spin_btn.value_changed.connect (() => {
                work.fit_width = (int) fw.value;
                refresh ();
            });
            fh.spin_btn.value_changed.connect (() => {
                work.fit_height = (int) fh.value;
                refresh ();
            });
            first.spin_btn.value_changed.connect (() => {
                work.first_page_number = (int) first.value;
                refresh ();
            });
            stack.add_titled (page_box, "page", _("Page"));

            var margin_box = new Box (Orientation.VERTICAL, 0);
            var mb = ToolDialogs.scroll_box (margin_box);
            var gm = new PreferencesGroup (_("Margins in Centimeters"));
            var mt = spin (gm, _("Top"), null, 0, 20, 0.1, work.margin_top * CM);
            var mbt = spin (gm, _("Bottom"), null, 0, 20, 0.1, work.margin_bottom * CM);
            var ml = spin (gm, _("Left"), null, 0, 20, 0.1, work.margin_left * CM);
            var mr = spin (gm, _("Right"), null, 0, 20, 0.1, work.margin_right * CM);
            var mhd = spin (gm, _("Header"), null, 0, 20, 0.1, work.margin_header * CM);
            var mft = spin (gm, _("Footer"), null, 0, 20, 0.1, work.margin_footer * CM);
            foreach (var r in new SpinRow[] { mt, mbt, ml, mr, mhd, mft }) r.spin_btn.digits = 2;
            mb.append (gm);
            var gc = new PreferencesGroup (_("Center on Page"));
            var ch = sw (gc, _("Horizontally"), work.center_h);
            var cv = sw (gc, _("Vertically"), work.center_v);
            mb.append (gc);
            mt.spin_btn.value_changed.connect (() => { work.margin_top = mt.value / CM; refresh (); });
            mbt.spin_btn.value_changed.connect (() => { work.margin_bottom = mbt.value / CM; refresh (); });
            ml.spin_btn.value_changed.connect (() => { work.margin_left = ml.value / CM; refresh (); });
            mr.spin_btn.value_changed.connect (() => { work.margin_right = mr.value / CM; refresh (); });
            mhd.spin_btn.value_changed.connect (() => { work.margin_header = mhd.value / CM; refresh (); });
            mft.spin_btn.value_changed.connect (() => { work.margin_footer = mft.value / CM; refresh (); });
            ch.notify["active"].connect (() => { work.center_h = ch.active; refresh (); });
            cv.notify["active"].connect (() => { work.center_v = cv.active; refresh (); });
            stack.add_titled (margin_box, "margins", _("Margins"));

            var hf_box = new Box (Orientation.VERTICAL, 0);
            var hb = ToolDialogs.scroll_box (hf_box);
            var gp = new PreferencesGroup (_("Quick Choices"));
            string[] ps = presets ();
            var hpre = new SelectionRow (_("Header"), ps, ps[preset_of (work.header)]);
            var fpre = new SelectionRow (_("Footer"), ps, ps[preset_of (work.footer)]);
            gp.add_row (hpre);
            gp.add_row (fpre);
            var dfirst = sw (gp, _("Different first page"), work.first_different);
            var dodd = sw (gp, _("Different odd and even pages"), work.odd_even);
            var scale_doc = sw (gp, _("Scale with document"), work.scale_with_doc);
            var align_m = sw (gp, _("Align with page margins"), work.align_with_margins);
            hb.append (gp);
            var ge = new PreferencesGroup (_("Custom Text"), _("Codes: &P page, &N pages, &D date, &T time, &F file, &Z folder, &A sheet, &B bold, &I italic, &U underline, &\"Font,Bold\" font, &12 size"));
            hf_targets = { _("Header"), _("Footer"), _("First page header"), _("First page footer"), _("Even page header"), _("Even page footer") };
            var target = new SelectionRow (_("Editing"), hf_targets, hf_targets[0]);
            ge.add_row (target);
            hf_left = new EntryRow (_("Left section"));
            hf_center = new EntryRow (_("Center section"));
            hf_right = new EntryRow (_("Right section"));
            ge.add_row (hf_left);
            ge.add_row (hf_center);
            ge.add_row (hf_right);
            hb.append (ge);
            load_hf ();
            hf_left.entry_changed.connect (() => store_hf ());
            hf_center.entry_changed.connect (() => store_hf ());
            hf_right.entry_changed.connect (() => store_hf ());
            target.selected.connect ((v) => {
                for (int i = 0; i < hf_targets.length; i++) if (hf_targets[i] == v) hf_index = i;
                load_hf ();
            });
            hpre.selected.connect ((v) => {
                for (int i = 0; i < 7; i++) if (ps[i] == v) work.header = preset_code (i);
                if (hf_index == 0) load_hf ();
                refresh ();
            });
            fpre.selected.connect ((v) => {
                for (int i = 0; i < 7; i++) if (ps[i] == v) work.footer = preset_code (i);
                if (hf_index == 1) load_hf ();
                refresh ();
            });
            dfirst.notify["active"].connect (() => { work.first_different = dfirst.active; refresh (); });
            dodd.notify["active"].connect (() => { work.odd_even = dodd.active; refresh (); });
            scale_doc.notify["active"].connect (() => { work.scale_with_doc = scale_doc.active; refresh (); });
            align_m.notify["active"].connect (() => { work.align_with_margins = align_m.active; refresh (); });
            stack.add_titled (hf_box, "headers", _("Header and Footer"));

            var sheet_box = new Box (Orientation.VERTICAL, 0);
            var sb = ToolDialogs.scroll_box (sheet_box);
            var ga = new PreferencesGroup (_("Areas"));
            var area = new EntryRow (_("Print area"));
            area.text = work.print_area;
            var trows = new EntryRow (_("Rows to repeat at top"));
            trows.text = work.title_rows;
            var tcols = new EntryRow (_("Columns to repeat at left"));
            tcols.text = work.title_cols;
            ga.add_row (area);
            ga.add_row (trows);
            ga.add_row (tcols);
            var use_sel = new ActionRow (_("Use Selection as Print Area"), ToolDialogs.area_text (Document.clamp_area (sheet, win.grid.selection)));
            var use_btn = new Button.with_label (_("Use"));
            use_btn.valign = Align.CENTER;
            use_btn.clicked.connect (() => area.text = ToolDialogs.area_text (Document.clamp_area (sheet, win.grid.selection)));
            use_sel.add_suffix (use_btn);
            ga.add_row (use_sel);
            sb.append (ga);
            var gprint = new PreferencesGroup (_("Print"));
            var grid_sw = sw (gprint, _("Gridlines"), work.gridlines);
            var head_sw = sw (gprint, _("Row and column headings"), work.headings);
            var bw_sw = sw (gprint, _("Black and white"), work.black_and_white);
            string[] orders = { _("Down, then over"), _("Over, then down") };
            var order = new SelectionRow (_("Page order"), orders, work.over_then_down ? orders[1] : orders[0]);
            gprint.add_row (order);
            sb.append (gprint);
            var gbreaks = new PreferencesGroup (_("Page Breaks"));
            var breaks_row = new ActionRow (_("Manual breaks"), _("%d row breaks, %d column breaks").printf (work.row_breaks.size, work.col_breaks.size));
            var reset = new Button.with_label (_("Reset All"));
            reset.valign = Align.CENTER;
            reset.clicked.connect (() => {
                work.row_breaks.clear ();
                work.col_breaks.clear ();
                breaks_row.subtitle = _("%d row breaks, %d column breaks").printf (0, 0);
                refresh ();
            });
            breaks_row.add_suffix (reset);
            gbreaks.add_row (breaks_row);
            sb.append (gbreaks);
            area.entry_changed.connect (() => { work.print_area = area.text.strip (); refresh (); });
            trows.entry_changed.connect (() => { work.title_rows = normalize_rows (trows.text); refresh (); });
            tcols.entry_changed.connect (() => { work.title_cols = normalize_cols (tcols.text); refresh (); });
            grid_sw.notify["active"].connect (() => { work.gridlines = grid_sw.active; refresh (); });
            head_sw.notify["active"].connect (() => { work.headings = head_sw.active; refresh (); });
            bw_sw.notify["active"].connect (() => { work.black_and_white = bw_sw.active; refresh (); });
            order.selected.connect ((v) => { work.over_then_down = v == orders[1]; refresh (); });
            stack.add_titled (sheet_box, "sheet", _("Sheet"));

            var right = new Box (Orientation.VERTICAL, 8);
            right.margin_end = 18;
            right.margin_top = 12;
            right.margin_start = 6;
            preview = new DrawingArea ();
            preview.set_size_request (300, 400);
            preview.vexpand = true;
            preview.set_draw_func (draw_preview);
            right.append (preview);
            var nav = new Box (Orientation.HORIZONTAL, 6);
            nav.halign = Align.CENTER;
            var prev = ToolDialogs.flat ("go-previous-symbolic", _("Previous Page"));
            var next = ToolDialogs.flat ("go-next-symbolic", _("Next Page"));
            page_label = new Label ("");
            page_label.add_css_class ("dim-label");
            prev.clicked.connect (() => {
                if (preview_page > 0) preview_page--;
                refresh ();
            });
            next.clicked.connect (() => {
                preview_page++;
                refresh ();
            });
            nav.append (prev);
            nav.append (page_label);
            nav.append (next);
            right.append (nav);
            outer.append (right);
            dlg.content_box.append (outer);

            ToolDialogs.footer (dlg, _("Apply"), () => {
                win.doc.begin_book (_("Page Setup"), sheet);
                sheet.page = work.copy ();
                win.doc.commit ();
                win.grid.queue_draw ();
            });
            dlg.open_dialog ();
        }

        private static string normalize_rows (string t) {
            string s = PageSetup.strip_sheet (t.strip ()).replace ("$", "");
            if (s == "") return "";
            string[] p = s.split (":");
            int a = int.parse (p[0]), b = p.length > 1 ? int.parse (p[1]) : a;
            if (a < 1 || b < a) return "";
            return PageSetup.rows_text (a - 1, b - 1);
        }

        private static string normalize_cols (string t) {
            string s = PageSetup.strip_sheet (t.strip ()).replace ("$", "").up ();
            if (s == "") return "";
            string[] p = s.split (":");
            int a = Address.column_index (p[0]), b = p.length > 1 ? Address.column_index (p[1]) : a;
            if (a < 0 || b < a) return "";
            return PageSetup.cols_text (a, b);
        }

        private void draw_preview (DrawingArea area, Cairo.Context cr, int w, int h) {
            var printer = new SheetPrinter.with_setup (sheet, work);
            if (win.doc.path != null) printer.file_name = Path.get_basename (win.doc.path);
            int n = printer.paginate_own ();
            if (preview_page >= n) preview_page = n - 1;
            if (preview_page < 0) preview_page = 0;
            page_label.label = _("Page %d of %d").printf (preview_page + 1, n);
            double pw = work.page_width, ph = work.page_height;
            double s = double.min ((w - 16) / pw, (h - 16) / ph);
            double ox = (w - pw * s) / 2, oy = (h - ph * s) / 2;
            cr.set_source_rgba (0, 0, 0, 0.18);
            cr.rectangle (ox + 3, oy + 3, pw * s, ph * s);
            cr.fill ();
            cr.set_source_rgb (1, 1, 1);
            cr.rectangle (ox, oy, pw * s, ph * s);
            cr.fill ();
            var fo = new Cairo.FontOptions ();
            fo.set_antialias (Cairo.Antialias.GRAY);
            fo.set_hint_style (Cairo.HintStyle.NONE);
            cr.set_font_options (fo);
            cr.save ();
            cr.translate (ox, oy);
            cr.scale (s, s);
            cr.rectangle (0, 0, pw, ph);
            cr.clip ();
            printer.render (cr, preview_page);
            cr.set_source_rgba (0.2, 0.45, 0.85, 0.35);
            cr.set_line_width (0.8 / s);
            cr.set_dash ({ 3 / s, 3 / s }, 0);
            cr.rectangle (work.margin_left * 72, work.margin_top * 72, pw - (work.margin_left + work.margin_right) * 72, ph - (work.margin_top + work.margin_bottom) * 72);
            cr.stroke ();
            cr.restore ();
        }
    }
}
