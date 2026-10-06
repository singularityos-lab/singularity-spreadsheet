using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class ReviewUi {
        public delegate void Act ();

        private static void act (SpreadsheetWindow win, string name, owned Act handler) {
            var a = new SimpleAction (name, null);
            Act h = (owned) handler;
            a.activate.connect (() => {
                if (win.doc == null || win.grid == null) return;
                h ();
            });
            win.add_action (a);
        }

        public static void install (SpreadsheetWindow win) {
            var toggle = new SimpleAction.stateful ("track-changes", null, new Variant.boolean (false));
            toggle.activate.connect (() => {
                if (win.doc == null) return;
                var t = ReviewTracker.of (win.doc);
                t.set_tracking (!win.doc.book.revisions.tracking);
                toggle.set_state (new Variant.boolean (win.doc.book.revisions.tracking));
                win.grid.queue_draw ();
            });
            win.add_action (toggle);
            win.notify["doc"].connect (() => {
                toggle.set_state (new Variant.boolean (win.doc != null && win.doc.book.revisions.tracking));
            });
            act (win, "review-changes", () => {
                var p = panel_of (win);
                if (p == null) return;
                if (p.visible) p.visible = false;
                else p.show_panel ();
            });
            act (win, "accept-all-changes", () => {
                ReviewTracker.of (win.doc).accept_all ();
                win.grid.queue_draw ();
            });
            act (win, "reject-all-changes", () => {
                ReviewTracker.of (win.doc).reject_all ();
                win.grid.refresh ();
            });
            act (win, "history-sheet", () => {
                var s = ReviewTracker.of (win.doc).history_sheet ();
                win.go_to (s, 0, 0);
            });
            act (win, "compare-merge", () => pick_other (win));
        }

        public static ReviewPanel? panel_of (SpreadsheetWindow win) {
            return win.get_data<ReviewPanel> ("ss-review-panel");
        }

        public static Widget panel (SpreadsheetWindow win) {
            var p = new ReviewPanel (win);
            p.visible = false;
            win.set_data<ReviewPanel> ("ss-review-panel", p);
            return p;
        }

        public static string author_color (string author) {
            string[] palette = { "#1c71d8", "#c64600", "#2ec27e", "#9141ac", "#e5a50a", "#e01b24", "#0d8f8f", "#865e3c" };
            uint h = author.hash ();
            return palette[h % palette.length];
        }

        private static void rgb (Cairo.Context cr, string hex) {
            cr.set_source_rgb (Xlsx.hex2 (hex, 1) / 255.0, Xlsx.hex2 (hex, 3) / 255.0, Xlsx.hex2 (hex, 5) / 255.0);
        }

        public static void draw_change (Cairo.Context cr, Sheet sheet, int r, int c, double x, double y, double w, double h) {
            var ch = sheet.book.revisions.cell_change (sheet, r, c);
            if (ch == null) return;
            cr.save ();
            rgb (cr, author_color (ch.author));
            cr.set_line_width (1.5);
            cr.rectangle (x + 0.75, y + 0.75, w - 2.5, h - 2.5);
            cr.stroke ();
            cr.move_to (x + 1, y + 1);
            cr.line_to (x + 7, y + 1);
            cr.line_to (x + 1, y + 7);
            cr.close_path ();
            cr.fill ();
            cr.restore ();
        }

        public static string format_date (string iso) {
            var dt = new DateTime.from_iso8601 (iso, new TimeZone.local ());
            if (dt == null) return iso;
            return dt.format ("%x %H:%M");
        }

        public static string tooltip (Change c) {
            return "%s, %s: %s".printf (c.author, format_date (c.date), c.describe ());
        }

        private static void pick_other (SpreadsheetWindow win) {
            var dialog = new FileDialog ();
            dialog.title = _("Compare and Merge Workbooks");
            var filter = new FileFilter ();
            filter.name = _("Spreadsheets");
            foreach (string suf in new string[] { "xlsx", "xlsm", "xls", "ods", "fods" }) filter.add_suffix (suf);
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            dialog.filters = filters;
            dialog.open.begin (win, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null && file.get_path () != null) compare_with (win, file.get_path ());
                } catch (Error e) {
                }
            });
        }

        public static void compare_with (SpreadsheetWindow win, string path) {
            Document other;
            try {
                other = Document.open (path);
            } catch (Error e) {
                win.show_error (_("Could not open the workbook"), e.message);
                return;
            }
            var diffs = WorkbookCompare.compare (win.doc.book, other.book);
            string author = WorkbookCompare.author_of (other.book, path);
            var dlg = ToolDialogs.make (win, _("Compare with %s").printf (Path.get_basename (path)), 600, 620);
            var box = ToolDialogs.scroll_box (dlg.content_box);
            if (diffs.size == 0) {
                var empty = new StatusPage ();
                empty.icon_name = "emblem-ok-symbolic";
                empty.title = _("No Differences");
                empty.description = _("The two workbooks have the same sheets, values, formulas and formatting.");
                empty.vexpand = true;
                box.append (empty);
                ToolDialogs.close_footer (dlg);
                dlg.open_dialog ();
                return;
            }
            var head = new PreferencesGroup (null, ngettext ("%d difference found. Merged changes are recorded as tracked changes by %s.", "%d differences found. Merged changes are recorded as tracked changes by %s.", diffs.size).printf (diffs.size, author));
            var all = new Button.with_label (_("Select All"));
            all.add_css_class ("flat");
            var none = new Button.with_label (_("Select None"));
            none.add_css_class ("flat");
            head.add_header_suffix (all);
            head.add_header_suffix (none);
            box.append (head);
            var switches = new Gee.ArrayList<SwitchRow> ();
            var groups = new Gee.HashMap<string, PreferencesGroup> ();
            int shown = 0;
            foreach (var d in diffs) {
                if (shown >= 1000) break;
                shown++;
                if (!groups.has_key (d.sheet_name)) {
                    var g = new PreferencesGroup (d.sheet_name);
                    groups[d.sheet_name] = g;
                    box.append (g);
                }
                var dd = d;
                var row = new SwitchRow (d.where (), d.describe (), true);
                row.notify["active"].connect (() => dd.selected = row.active);
                switches.add (row);
                groups[d.sheet_name].add_row (row);
            }
            for (int i = shown; i < diffs.size; i++) diffs[i].selected = false;
            all.clicked.connect (() => {
                foreach (var s in switches) s.active = true;
            });
            none.clicked.connect (() => {
                foreach (var s in switches) s.active = false;
            });
            ToolDialogs.footer (dlg, _("Merge Selected"), () => {
                WorkbookCompare.merge (win.doc, diffs, author);
                win.grid.refresh ();
                var p = panel_of (win);
                if (p != null) p.show_panel ();
            });
            dlg.open_dialog ();
        }
    }

    public class ReviewPanel : Box {
        private SpreadsheetWindow win;
        private Box content;
        private Document? bound;
        private ulong handler;
        private int when_mode = 1;
        private int who_mode;
        private string who_name = "";
        private string where_text = "";
        private bool building;

        public ReviewPanel (SpreadsheetWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            add_css_class ("ss-comments-panel");
            width_request = 340;
            hexpand = false;
            var head = new Box (Orientation.HORIZONTAL, 6);
            head.margin_start = 14;
            head.margin_end = 8;
            head.margin_top = 10;
            head.margin_bottom = 6;
            var title = new Label (_("Changes"));
            title.add_css_class ("heading");
            title.hexpand = true;
            title.xalign = 0;
            head.append (title);
            var close = new Button.from_icon_name ("window-close-symbolic");
            close.add_css_class ("flat");
            close.tooltip_text = _("Hide Changes");
            close.clicked.connect (() => visible = false);
            head.append (close);
            append (head);
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            content = new Box (Orientation.VERTICAL, 12);
            content.margin_start = 12;
            content.margin_end = 12;
            content.margin_bottom = 12;
            scroll.child = content;
            append (scroll);
            notify["visible"].connect (() => {
                if (!visible) unbind ();
            });
        }

        private void unbind () {
            if (bound != null && handler != 0) bound.disconnect (handler);
            bound = null;
            handler = 0;
        }

        public void show_panel () {
            if (bound != win.doc) {
                unbind ();
                bound = win.doc;
                if (bound != null) handler = bound.changed.connect (() => {
                    if (!building) refresh ();
                });
            }
            visible = true;
            refresh ();
        }

        private ChangeFilter filter () {
            var f = new ChangeFilter ();
            if (when_mode == 2) {
                f.when_mode = 1;
                f.since = new DateTime.now_local ().format ("%Y-%m-%dT00:00:00");
            } else if (when_mode == 3) {
                f.when_mode = 1;
                f.since = new DateTime.now_local ().add_days (-7).format ("%Y-%m-%dT%H:%M:%S");
            }
            if (who_mode == 1) f.not_me = true;
            else if (who_mode >= 2) f.who = who_name;
            if (where_text.strip () != "") {
                var a = Area.parse (where_text.strip (), win.grid.sheet);
                if (a != null) f.where = a;
            }
            return f;
        }

        private DropDown pick (string[] items, int selected) {
            var d = new DropDown.from_strings (items);
            d.valign = Align.CENTER;
            d.selected = selected;
            return d;
        }

        public void refresh () {
            if (win.doc == null) return;
            building = true;
            Widget? child;
            while ((child = content.get_first_child ()) != null) content.remove (child);
            var doc = win.doc;
            var log = doc.book.revisions;
            var tracker = ReviewTracker.of (doc);
            string me = CommentStore.current_author ();
            var top = new PreferencesGroup ();
            var track = new SwitchRow (_("Track Changes"), _("Record every edit with its author and time"), log.tracking);
            track.notify["active"].connect (() => {
                if (building) return;
                tracker.set_tracking (track.active);
                win.grid.queue_draw ();
            });
            top.add_row (track);
            content.append (top);
            var fg = new PreferencesGroup (_("Show"));
            string[] whens = { _("All"), _("Not Yet Reviewed"), _("Today"), _("Last 7 Days") };
            var when_pick = pick (whens, when_mode);
            var when_row = new ActionRow (_("When"));
            when_row.add_suffix (when_pick);
            fg.add_row (when_row);
            var authors = new Gee.TreeSet<string> ();
            foreach (var c in log.changes) authors.add (c.author);
            string[] whos = { _("Everyone"), _("Everyone but Me") };
            foreach (string a in authors) whos += a;
            var who_pick = pick (whos, who_mode < whos.length ? who_mode : 0);
            var who_row = new ActionRow (_("Who"));
            who_row.add_suffix (who_pick);
            fg.add_row (who_row);
            var where_row = new EntryRow (_("Where"));
            where_row.text = where_text;
            fg.add_row (where_row);
            content.append (fg);
            when_pick.notify["selected"].connect (() => {
                if (building) return;
                when_mode = (int) when_pick.selected;
                Idle.add (() => {
                    refresh ();
                    return Source.REMOVE;
                });
            });
            who_pick.notify["selected"].connect (() => {
                if (building) return;
                who_mode = (int) who_pick.selected;
                who_name = who_mode >= 2 ? whos[who_mode] : "";
                Idle.add (() => {
                    refresh ();
                    return Source.REMOVE;
                });
            });
            where_row.entry_activated.connect (() => {
                where_text = where_row.text;
                refresh ();
            });
            var f = filter ();
            var list = new Gee.ArrayList<Change> ();
            foreach (var c in log.changes) {
                if (when_mode == 1 && c.state != ChangeState.PENDING) continue;
                if (!f.matches (c, me)) continue;
                list.add (c);
            }
            var lg = new PreferencesGroup (ngettext ("%d Change", "%d Changes", list.size).printf (list.size));
            var accept_all = new Button.with_label (_("Accept All"));
            accept_all.add_css_class ("flat");
            var reject_all = new Button.with_label (_("Reject All"));
            reject_all.add_css_class ("flat");
            accept_all.sensitive = reject_all.sensitive = list.size > 0;
            accept_all.clicked.connect (() => {
                tracker.accept_all (f);
                win.grid.queue_draw ();
            });
            reject_all.clicked.connect (() => {
                tracker.reject_all (f);
                win.grid.refresh ();
            });
            lg.add_header_suffix (accept_all);
            lg.add_header_suffix (reject_all);
            if (list.size == 0) {
                var empty = new StatusPage ();
                empty.icon_name = "document-edit-symbolic";
                empty.title = log.tracking ? _("No Changes Yet") : _("Tracking Is Off");
                empty.description = log.tracking ? _("Edits made from now on appear here for review.") : _("Turn on Track Changes to record who changed what.");
                empty.compact = true;
                content.append (lg);
                content.append (empty);
                building = false;
                return;
            }
            for (int i = list.size - 1; i >= 0 && list.size - i <= 500; i--) {
                var c = list[i];
                string state = c.state == ChangeState.ACCEPTED ? _("Accepted") : (c.state == ChangeState.REJECTED ? _("Rejected") : "");
                string sub = "%s, %s, %s".printf (c.author, ReviewUi.format_date (c.date), c.where ());
                if (state != "") sub += "\n" + state;
                var row = new ActionRow (c.describe (), sub);
                if (c.state == ChangeState.PENDING) {
                    var ok = ToolDialogs.flat ("object-select-symbolic", _("Accept"));
                    ok.clicked.connect (() => {
                        tracker.accept (c);
                        win.grid.queue_draw ();
                    });
                    row.add_suffix (ok);
                    var no = ToolDialogs.flat ("edit-undo-symbolic", _("Reject"));
                    no.sensitive = tracker.can_reject (c);
                    no.clicked.connect (() => {
                        tracker.reject (c);
                        win.grid.refresh ();
                    });
                    row.add_suffix (no);
                }
                row.activated.connect (() => {
                    if (c.sheet != null && doc.book.sheets.contains (c.sheet)) win.go_to (c.sheet, c.row, c.col);
                });
                lg.add_row (row);
            }
            content.append (lg);
            building = false;
        }
    }
}
