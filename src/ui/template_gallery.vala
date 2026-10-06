using Gtk;

namespace Singularity.Apps.Spreadsheet {

    public delegate Document TemplateBuilder ();

    public class SheetTemplate {
        public string id;
        public string title;
        public string description;
        public string? path;
        private TemplateBuilder builder;

        public SheetTemplate (string id, string title, string description, owned TemplateBuilder builder) {
            this.id = id;
            this.title = title;
            this.description = description;
            this.builder = (owned) builder;
        }

        public Document build () {
            return builder ();
        }

        public static string user_dir () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity-spreadsheet", "templates");
        }

        public static Gee.ArrayList<SheetTemplate> mine () {
            var list = new Gee.ArrayList<SheetTemplate> ();
            try {
                var d = Dir.open (user_dir ());
                string? name;
                var names = new Gee.ArrayList<string> ();
                while ((name = d.read_name ()) != null) {
                    if (FileKind.is_template (name)) names.add (name);
                }
                names.sort ((a, b) => a.collate (b));
                foreach (string n in names) {
                    string path = Path.build_filename (user_dir (), n);
                    string title = n.substring (0, n.last_index_of ("."));
                    var t = new SheetTemplate ("user:" + path, title, _("Your template"), () => {
                        try {
                            return Document.open (path);
                        } catch (Error e) {
                            return new Document ();
                        }
                    });
                    t.path = path;
                    list.add (t);
                }
            } catch (FileError e) {
            }
            return list;
        }

        public static Gee.ArrayList<SheetTemplate> all () {
            var list = new Gee.ArrayList<SheetTemplate> ();
            list.add (new SheetTemplate ("budget", _("Personal Budget"), _("Planned and actual spending by category"), () => Templates.budget ()));
            list.add (new SheetTemplate ("invoice", _("Invoice"), _("Items, tax and total ready to send"), () => Templates.invoice ()));
            list.add (new SheetTemplate ("tracker", _("Project Tracker"), _("Tasks with owners, dates and progress"), () => Templates.tracker ()));
            list.add (new SheetTemplate ("timesheet", _("Weekly Timesheet"), _("Daily hours, breaks and overtime"), () => MoreTemplates.timesheet ()));
            list.add (new SheetTemplate ("expenses", _("Expense Log"), _("Spending with totals per category"), () => MoreTemplates.expenses ()));
            list.add (new SheetTemplate ("inventory", _("Inventory"), _("Stock levels, value and reorder alerts"), () => MoreTemplates.inventory ()));
            list.add (new SheetTemplate ("calendar", _("Monthly Calendar"), _("This month laid out by week"), () => MoreTemplates.calendar ()));
            return list;
        }
    }

    public class SheetThumb : Widget {
        private int w;
        private int h;
        private Document doc;

        public SheetThumb (Document doc, int width, int height) {
            this.doc = doc;
            this.w = width;
            this.h = height;
            add_css_class ("ss-template-thumb");
            overflow = Overflow.HIDDEN;
        }

        public override SizeRequestMode get_request_mode () {
            return SizeRequestMode.CONSTANT_SIZE;
        }

        public override void measure (Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum = natural = orientation == Orientation.HORIZONTAL ? w : h;
            minimum_baseline = natural_baseline = -1;
        }

        private static bool parse_hex (string hex, out double r, out double g, out double b) {
            r = g = b = 0;
            string x = hex.has_prefix ("#") ? hex.substring (1) : hex;
            if (x.length != 6) return false;
            r = ("0x" + x.substring (0, 2)).to_int64 () / 255.0;
            g = ("0x" + x.substring (2, 2)).to_int64 () / 255.0;
            b = ("0x" + x.substring (4, 2)).to_int64 () / 255.0;
            return true;
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            int width = get_width ();
            int height = get_height ();
            var cr = snapshot.append_cairo ({ { 0, 0 }, { width, height } });
            var sheet = doc.book.sheets[0];
            var fg = get_color ();
            double page_w = 0;
            int last_col = 0;
            int used_cols = int.max (sheet.max_col, 2);
            for (int c = 0; c <= used_cols && c < 26; c++) {
                double cw = sheet.col_width (c);
                if (page_w + cw > 470 && c > 0) break;
                page_w += cw;
                last_col = c;
            }
            page_w = double.max (page_w, 280);
            bool dark = fg.red * 0.3 + fg.green * 0.59 + fg.blue * 0.11 > 0.5;
            if (dark) cr.set_source_rgb (0.12, 0.13, 0.19);
            else cr.set_source_rgb (1, 1, 1);
            cr.paint ();
            double scale = (width - 20) / page_w;
            cr.translate (10, 12);
            cr.scale (scale, scale);
            double limit_h = (height - 16) / scale;
            var font = new Pango.FontDescription ();
            font.set_family ("Sans");
            double y = 0;
            for (int r = 0; y < limit_h && r < 80; r++) {
                double rh = sheet.row_height (r);
                if (rh <= 0) continue;
                double x = 0;
                for (int c = 0; c <= last_col; c++) {
                    double cw = sheet.col_width (c);
                    if (cw <= 0) continue;
                    var merge = sheet.merge_at (r, c);
                    if (merge != null && (merge.r1 != r || merge.c1 != c)) {
                        x += cw;
                        continue;
                    }
                    double span = cw;
                    if (merge != null) for (int mc = c + 1; mc <= merge.c2; mc++) span += sheet.col_width (mc);
                    var st = sheet.style_at (r, c);
                    double fr = 0, fgc = 0, fb = 0;
                    if (st.fill != "" && parse_hex (st.fill, out fr, out fgc, out fb)) {
                        cr.set_source_rgb (fr, fgc, fb);
                        cr.rectangle (x, y, span, rh);
                        cr.fill ();
                    }
                    if (sheet.show_grid && r <= sheet.max_row + 1 && c <= sheet.max_col) {
                        cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.10);
                        cr.set_line_width (1);
                        cr.rectangle (x + 0.5, y + 0.5, cw, rh);
                        cr.stroke ();
                    }
                    if (st.bottom.style != BorderStyle.NONE || st.top.style != BorderStyle.NONE) {
                        cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.45);
                        cr.set_line_width (1.2);
                        if (st.top.style != BorderStyle.NONE) {
                            cr.move_to (x, y + 0.5);
                            cr.line_to (x + span, y + 0.5);
                        }
                        if (st.bottom.style != BorderStyle.NONE) {
                            cr.move_to (x, y + rh - 0.5);
                            cr.line_to (x + span, y + rh - 0.5);
                        }
                        cr.stroke ();
                    }
                    var v = sheet.value_at (r, c);
                    if (!v.is_empty ()) {
                        string color;
                        string text = NumberFormat.format_value (v, st.number_format, out color);
                        if (text != "") {
                            double tr = 0, tg = 0, tb = 0;
                            string tc = color != "" ? color : st.color;
                            if (tc != "" && parse_hex (tc, out tr, out tg, out tb)) cr.set_source_rgb (tr, tg, tb);
                            else if (st.fill != "" && !dark) cr.set_source_rgb (0.1, 0.1, 0.1);
                            else cr.set_source_rgba (fg.red, fg.green, fg.blue, fg.alpha);
                            font.set_absolute_size (st.font_size * 1.33 * Pango.SCALE);
                            font.set_weight (st.bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
                            var layout = Pango.cairo_create_layout (cr);
                            layout.set_font_description (font);
                            layout.set_text (text, -1);
                            int lw, lh;
                            layout.get_pixel_size (out lw, out lh);
                            bool right = st.halign == HAlign.RIGHT || (st.halign == HAlign.GENERAL && v.kind == ValueKind.NUMBER);
                            double tx = x + 4;
                            if (st.halign == HAlign.CENTER) tx = x + (span - lw) / 2;
                            else if (right) tx = x + span - lw - 4;
                            double ty = st.valign == VAlign.TOP ? y + 2 : y + (rh - lh) / 2;
                            cr.save ();
                            bool spill_over = v.kind == ValueKind.TEXT && merge == null && !st.wrap && sheet.value_at (r, c + 1).is_empty ();
                            cr.rectangle (x, y, spill_over ? span * 3 : span, rh);
                            cr.clip ();
                            cr.move_to (tx, ty);
                            Pango.cairo_show_layout (cr, layout);
                            cr.restore ();
                        }
                    }
                    x += cw;
                }
                y += rh;
            }
        }
    }

    public class TemplateGallery : Box {
        public signal void chosen (SheetTemplate template);
        public const int CARD_WIDTH = 132;

        public signal void removed (SheetTemplate template);

        public TemplateGallery () {
            Object (orientation: Orientation.VERTICAL, spacing: 12);
            add_css_class ("ss-template-gallery");
            refresh ();
        }

        public void refresh () {
            Widget? old;
            while ((old = get_first_child ()) != null) remove (old);
            section (_("Templates"), SheetTemplate.all ());
            var mine = SheetTemplate.mine ();
            if (mine.size > 0) section (_("Your Templates"), mine);
        }

        private void section (string heading, Gee.ArrayList<SheetTemplate> items) {
            var title = new Label (heading);
            title.add_css_class ("title-2");
            title.halign = Align.START;
            if (get_first_child () != null) title.margin_top = 12;
            append (title);
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.homogeneous = true;
            flow.min_children_per_line = 2;
            flow.max_children_per_line = 4;
            flow.column_spacing = 10;
            flow.row_spacing = 10;
            foreach (var t in items) {
                var cell = new FlowBoxChild ();
                cell.focusable = false;
                cell.child = card (t);
                flow.append (cell);
            }
            append (flow);
        }

        private Widget card (SheetTemplate t) {
            var btn = new Button ();
            btn.add_css_class ("flat");
            btn.add_css_class ("ss-template-card");
            btn.tooltip_text = t.description;
            btn.valign = Align.START;
            btn.halign = Align.START;
            var box = new Box (Orientation.VERTICAL, 4);
            var pic = new SheetThumb (t.build (), CARD_WIDTH, CARD_WIDTH * 4 / 3);
            pic.halign = Align.START;
            pic.margin_bottom = 4;
            box.append (pic);
            var name = new Label (t.title);
            name.add_css_class ("heading");
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.max_width_chars = 1;
            box.append (name);
            var desc = new Label (t.description);
            desc.add_css_class ("caption");
            desc.add_css_class ("dim-label");
            desc.xalign = 0;
            desc.wrap = true;
            desc.wrap_mode = Pango.WrapMode.WORD_CHAR;
            desc.lines = 2;
            desc.ellipsize = Pango.EllipsizeMode.END;
            desc.max_width_chars = 1;
            desc.width_request = CARD_WIDTH;
            desc.valign = Align.START;
            box.append (desc);
            box.set_size_request (CARD_WIDTH, -1);
            btn.child = box;
            btn.update_property (Gtk.AccessibleProperty.LABEL, t.title, Gtk.AccessibleProperty.DESCRIPTION, t.description, -1);
            btn.clicked.connect (() => chosen (t));
            if (t.path != null) {
                var click = new GestureClick ();
                click.button = Gdk.BUTTON_SECONDARY;
                click.pressed.connect (() => {
                    var menu = new Singularity.Widgets.ContextMenu (btn);
                    menu.add_item (_("Delete Template"), "user-trash-symbolic", () => {
                        FileUtils.unlink (t.path);
                        refresh ();
                    });
                    SpreadsheetWindow.popup_menu (menu);
                });
                btn.add_controller (click);
            }
            return btn;
        }
    }
}
