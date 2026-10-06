using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class CondRules {
        private const string[] PERIODS = { "today", "yesterday", "tomorrow", "last7Days", "thisWeek", "lastWeek", "nextWeek", "thisMonth", "lastMonth", "nextMonth" };

        public static string[] icon_labels () {
            return { _("3 arrows"), _("3 gray arrows"), _("3 traffic lights"), _("3 symbols"), _("3 flags"), _("3 stars"),
                _("4 arrows"), _("4 traffic lights"), _("4 ratings"), _("5 arrows"), _("5 ratings"), _("5 quarters") };
        }

        public static string icon_set_for (string label) {
            var labels = icon_labels ();
            for (int i = 0; i < labels.length; i++) if (labels[i] == label) return CondIconPainter.SETS[i];
            return "3Arrows";
        }

        public static string[] period_labels () {
            return { _("Today"), _("Yesterday"), _("Tomorrow"), _("In the last 7 days"), _("This week"), _("Last week"), _("Next week"), _("This month"), _("Last month"), _("Next month") };
        }

        public static string period_for (string label) {
            var labels = period_labels ();
            for (int i = 0; i < labels.length; i++) if (labels[i] == label) return PERIODS[i];
            return "today";
        }

        private static string describe (CondFormat cf) {
            switch (cf.kind) {
                case CondKind.GREATER: return _("Greater than %s").printf (cf.a);
                case CondKind.GREATER_EQUAL: return _("Greater than or equal to %s").printf (cf.a);
                case CondKind.LESS: return _("Less than %s").printf (cf.a);
                case CondKind.LESS_EQUAL: return _("Less than or equal to %s").printf (cf.a);
                case CondKind.BETWEEN: return _("Between %s and %s").printf (cf.a, cf.b);
                case CondKind.NOT_BETWEEN: return _("Not between %s and %s").printf (cf.a, cf.b);
                case CondKind.EQUAL: return _("Equal to %s").printf (cf.a);
                case CondKind.NOT_EQUAL: return _("Not equal to %s").printf (cf.a);
                case CondKind.TEXT_CONTAINS: return _("Text contains %s").printf (cf.a);
                case CondKind.TEXT_NOT_CONTAINS: return _("Text does not contain %s").printf (cf.a);
                case CondKind.TEXT_BEGINS: return _("Text begins with %s").printf (cf.a);
                case CondKind.TEXT_ENDS: return _("Text ends with %s").printf (cf.a);
                case CondKind.DUPLICATE: return _("Duplicate values");
                case CondKind.UNIQUE: return _("Unique values");
                case CondKind.FORMULA: return _("Formula %s").printf (cf.a);
                case CondKind.COLOR_SCALE: return _("Color scale");
                case CondKind.DATA_BAR: return _("Data bars");
                case CondKind.ICON_SET: return _("Icon set");
                case CondKind.TOP: return cf.percent ? _("Top %s%%").printf (cf.a) : _("Top %s").printf (cf.a);
                case CondKind.BOTTOM: return cf.percent ? _("Bottom %s%%").printf (cf.a) : _("Bottom %s").printf (cf.a);
                case CondKind.ABOVE_AVERAGE: return _("Above average");
                case CondKind.BELOW_AVERAGE: return _("Below average");
                case CondKind.BLANK: return _("Empty cells");
                case CondKind.NO_BLANK: return _("Cells with a value");
                case CondKind.ERRORS: return _("Errors");
                case CondKind.NO_ERRORS: return _("No errors");
                case CondKind.DATE_OCCURRING: return _("A date occurring");
            }
            return "";
        }

        public static void install (SpreadsheetWindow win) {
            var a = new SimpleAction ("cond-manage", null);
            a.activate.connect (() => {
                if (win.doc != null && win.grid != null) manage (win);
            });
            win.add_action (a);
        }

        public static void manage (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var dlg = Dialogs.make (win, _("Manage Rules"), 520, 600);
            var box = Dialogs.body (dlg);
            var group = new PreferencesGroup (_("Rules on %s").printf (s.name), _("Rules higher in the list win when they format the same cell."));
            box.append (group);
            Dialogs.Apply refill = null;
            refill = () => {
                group.clear ();
                if (s.cond_formats.size == 0) group.add_row (new ActionRow (_("No rules on this sheet"), null));
                for (int i = 0; i < s.cond_formats.size; i++) {
                    var cf = s.cond_formats[i];
                    int at = i;
                    var row = new ActionRow (describe (cf), Dialogs.area_text (cf.area) + (cf.stop_if_true ? "  " + _("Stop if true") : ""));
                    var up = new Button.from_icon_name ("go-up-symbolic");
                    up.add_css_class ("flat");
                    up.valign = Align.CENTER;
                    up.tooltip_text = _("Move Up");
                    up.sensitive = at > 0;
                    up.clicked.connect (() => {
                        win.doc.begin_book (_("Reorder Rules"), s);
                        var item = s.cond_formats.remove_at (at);
                        s.cond_formats.insert (at - 1, item);
                        win.doc.commit ();
                        refill ();
                        win.grid.refresh ();
                    });
                    var down = new Button.from_icon_name ("go-down-symbolic");
                    down.add_css_class ("flat");
                    down.valign = Align.CENTER;
                    down.tooltip_text = _("Move Down");
                    down.sensitive = at < s.cond_formats.size - 1;
                    down.clicked.connect (() => {
                        win.doc.begin_book (_("Reorder Rules"), s);
                        var item = s.cond_formats.remove_at (at);
                        s.cond_formats.insert (at + 1, item);
                        win.doc.commit ();
                        refill ();
                        win.grid.refresh ();
                    });
                    var stop = new Button.from_icon_name ("media-playback-stop-symbolic");
                    stop.add_css_class ("flat");
                    stop.valign = Align.CENTER;
                    stop.tooltip_text = cf.stop_if_true ? _("Continue after this rule") : _("Stop if true");
                    stop.clicked.connect (() => {
                        win.doc.begin_book (_("Stop if True"), s);
                        cf.stop_if_true = !cf.stop_if_true;
                        win.doc.commit ();
                        refill ();
                        win.grid.refresh ();
                    });
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete Rule");
                    del.clicked.connect (() => {
                        win.doc.begin_book (_("Delete Rule"), s);
                        s.cond_formats.remove (cf);
                        win.doc.commit ();
                        refill ();
                        win.grid.refresh ();
                    });
                    row.add_suffix (up);
                    row.add_suffix (down);
                    row.add_suffix (stop);
                    row.add_suffix (del);
                    group.add_row (row);
                }
            };
            refill ();
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var add = new Button.with_label (_("New Rule…"));
            add.clicked.connect (() => {
                dlg.close ();
                Dialogs.cond_format (win);
            });
            bar.append (add);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var close = new Button.with_label (_("Close"));
            close.add_css_class ("suggested-action");
            close.clicked.connect (() => dlg.close ());
            bar.append (close);
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }
    }
}
