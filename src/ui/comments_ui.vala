using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class CommentsUi {
        public delegate void Act ();

        private const string CSS = """
.ss-comments-panel {
    margin: 0 12px 0 0;
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.1);
}

.ss-comment-date {
    font-size: 0.85em;
    opacity: 0.6;
}
""";

        private static bool styled;

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
            if (!styled) {
                var css = new CssProvider ();
                css.load_from_string (CSS);
                StyleContext.add_provider_for_display (Gdk.Display.get_default (), css, STYLE_PROVIDER_PRIORITY_APPLICATION);
                styled = true;
            }
            act (win, "comment-new", () => open_thread (win, win.grid.sheet, win.grid.cur_row, win.grid.cur_col));
            act (win, "comments-panel", () => {
                var p = panel_of (win);
                if (p == null) return;
                if (p.visible) p.visible = false;
                else p.show_panel ();
            });
            act (win, "comment-delete", () => {
                var s = win.grid.sheet;
                Comments.delete_thread (win.doc, s, win.grid.cur_row, win.grid.cur_col);
                win.grid.queue_draw ();
            });
        }

        public static Widget wrap (SpreadsheetWindow win, Widget inner) {
            var box = new Box (Orientation.HORIZONTAL, 0);
            box.hexpand = true;
            box.vexpand = true;
            box.append (inner);
            var panel = new CommentsPanel (win);
            panel.visible = false;
            box.append (panel);
            box.append (ReviewUi.panel (win));
            win.set_data<CommentsPanel> ("ss-comments-panel", panel);
            return box;
        }

        public static CommentsPanel? panel_of (SpreadsheetWindow win) {
            return win.get_data<CommentsPanel> ("ss-comments-panel");
        }

        public static string format_date (string iso) {
            var dt = new DateTime.from_iso8601 (iso, new TimeZone.local ());
            if (dt == null) return iso;
            return dt.format ("%x %H:%M");
        }

        public static string tooltip (CommentThread t) {
            var sb = new StringBuilder ();
            foreach (var p in t.posts) {
                if (sb.len > 0) sb.append ("\n\n");
                sb.append (p.author + "\n" + p.text);
            }
            if (t.resolved) sb.append ("\n\n" + _("Resolved"));
            return sb.str;
        }

        public static void draw_marker (Cairo.Context cr, Sheet sheet, int r, int c, double x, double y, double w) {
            var t = sheet.comments.at (r, c);
            if (t == null) return;
            var cell = sheet.get_cell (r, c);
            double right = x + w - 2 - (cell != null && cell.note != "" ? 8 : 0);
            double bw = 8, bh = 6;
            double left = right - bw, top = y + 2;
            cr.save ();
            if (t.resolved) cr.set_source_rgb (0.58, 0.58, 0.62);
            else cr.set_source_rgb (0.48, 0.30, 0.86);
            double rad = 1.5;
            cr.new_sub_path ();
            cr.arc (left + bw - rad, top + rad, rad, -Math.PI / 2, 0);
            cr.arc (left + bw - rad, top + bh - rad, rad, 0, Math.PI / 2);
            cr.line_to (left + 3.5, top + bh);
            cr.line_to (left + 1.5, top + bh + 2.5);
            cr.line_to (left + 1.8, top + bh);
            cr.arc (left + rad, top + bh - rad, rad, Math.PI / 2, Math.PI);
            cr.arc (left + rad, top + rad, rad, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
            cr.fill ();
            cr.restore ();
        }

        public static void open_thread (SpreadsheetWindow win, Sheet sheet, int row, int col) {
            var doc = win.doc;
            var s = sheet;
            string me = CommentStore.current_author ();
            var dlg = ToolDialogs.make (win, _("Comments on %s").printf (Address.cell (row, col)), 500, 640);
            dlg.modal = false;
            var box = ToolDialogs.scroll_box (dlg.content_box);
            var status = new PreferencesGroup ();
            box.append (status);
            var posts = new PreferencesGroup ();
            box.append (posts);
            var composer = new PreferencesGroup (_("Reply"));
            var view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.add_css_class ("ss-note-view");
            view.top_margin = view.bottom_margin = 6;
            view.left_margin = view.right_margin = 8;
            var frame = new ScrolledWindow ();
            frame.add_css_class ("ss-note-frame");
            frame.min_content_height = 90;
            frame.hscrollbar_policy = PolicyType.NEVER;
            frame.child = view;
            composer.add_row (frame);
            var actions = new Box (Orientation.HORIZONTAL, 8);
            actions.margin_top = 8;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            actions.append (spacer);
            var cancel_edit = new Button.with_label (_("Cancel Edit"));
            cancel_edit.visible = false;
            actions.append (cancel_edit);
            var post = new Button.with_label (_("Post"));
            post.add_css_class ("suggested-action");
            actions.append (post);
            composer.add_row (actions);
            box.append (composer);
            var bar = ToolDialogs.close_footer (dlg);
            var delete_btn = new Button.with_label (_("Delete Thread"));
            delete_btn.add_css_class ("destructive-action");
            bar.prepend (delete_btn);
            var resolve = new Button.with_label (_("Resolve"));
            bar.insert_child_after (resolve, bar.get_first_child ().get_next_sibling ());
            string editing_id = "";
            ToolDialogs.Apply rebuild = null;
            rebuild = () => {
                status.clear ();
                posts.clear ();
                var t = s.comments.at (row, col);
                bool has = t != null && t.posts.size > 0;
                delete_btn.visible = has;
                resolve.visible = has;
                status.visible = has && t.resolved;
                if (has && t.resolved) {
                    status.add_row (new ActionRow (_("Resolved"), _("This thread is closed. Reopen it to reply.")));
                }
                resolve.label = has && t.resolved ? _("Reopen") : _("Resolve");
                composer.visible = !has || !t.resolved;
                composer.title = has ? _("Reply") : _("New Comment");
                posts.visible = has;
                if (!has) return;
                foreach (var p in t.posts) {
                    var pp = p;
                    var r = new ActionRow (pp.author, pp.text);
                    var date = new Label (format_date (pp.date));
                    date.add_css_class ("ss-comment-date");
                    date.valign = Align.START;
                    r.add_suffix (date);
                    if (pp.author == me && !t.resolved) {
                        var edit = ToolDialogs.flat ("document-edit-symbolic", _("Edit"));
                        edit.clicked.connect (() => {
                            editing_id = pp.id;
                            view.buffer.text = pp.text;
                            post.label = _("Save");
                            cancel_edit.visible = true;
                            view.grab_focus ();
                        });
                        r.add_suffix (edit);
                        var del = ToolDialogs.flat ("user-trash-symbolic", _("Delete"));
                        del.clicked.connect (() => {
                            Comments.delete_post (doc, s, row, col, pp.id);
                            win.grid.queue_draw ();
                        });
                        r.add_suffix (del);
                    }
                    posts.add_row (r);
                }
            };
            ToolDialogs.Apply reset_edit = () => {
                editing_id = "";
                view.buffer.text = "";
                post.label = _("Post");
                cancel_edit.visible = false;
            };
            cancel_edit.clicked.connect (() => reset_edit ());
            ToolDialogs.Apply submit = () => {
                string text = view.buffer.text.strip ();
                if (text == "") return;
                if (editing_id != "") Comments.edit_post (doc, s, row, col, editing_id, text);
                else Comments.add_post (doc, s, row, col, text);
                reset_edit ();
                win.grid.queue_draw ();
            };
            post.clicked.connect (() => submit ());
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((val, code, state) => {
                if ((val == Gdk.Key.Return || val == Gdk.Key.KP_Enter) && (state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    submit ();
                    return true;
                }
                return false;
            });
            view.add_controller (keys);
            resolve.clicked.connect (() => {
                var t = s.comments.at (row, col);
                if (t == null) return;
                Comments.set_resolved (doc, s, row, col, !t.resolved);
                win.grid.queue_draw ();
            });
            delete_btn.clicked.connect (() => {
                Comments.delete_thread (doc, s, row, col);
                win.grid.queue_draw ();
                dlg.close ();
            });
            ulong handler = doc.changed.connect (() => rebuild ());
            dlg.close_request.connect (() => {
                doc.disconnect (handler);
                return false;
            });
            rebuild ();
            dlg.open_dialog ();
            view.grab_focus ();
        }
    }

    public class CommentsPanel : Box {
        private SpreadsheetWindow win;
        private Box content;
        private Document? bound;
        private ulong handler;

        public CommentsPanel (SpreadsheetWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            add_css_class ("ss-comments-panel");
            width_request = 320;
            hexpand = false;
            var head = new Box (Orientation.HORIZONTAL, 6);
            head.margin_start = 14;
            head.margin_end = 8;
            head.margin_top = 10;
            head.margin_bottom = 6;
            var title = new Label (_("Comments"));
            title.add_css_class ("heading");
            title.hexpand = true;
            title.xalign = 0;
            head.append (title);
            var add = new Button.from_icon_name ("sheet-comment-symbolic");
            add.add_css_class ("flat");
            add.tooltip_text = _("New Comment");
            add.clicked.connect (() => {
                if (win.grid != null) CommentsUi.open_thread (win, win.grid.sheet, win.grid.cur_row, win.grid.cur_col);
            });
            head.append (add);
            var close = new Button.from_icon_name ("window-close-symbolic");
            close.add_css_class ("flat");
            close.tooltip_text = _("Hide Comments");
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
                if (bound != null) handler = bound.changed.connect (() => refresh ());
            }
            visible = true;
            refresh ();
        }

        public void refresh () {
            Widget? child;
            while ((child = content.get_first_child ()) != null) content.remove (child);
            if (win.doc == null) return;
            int total = 0;
            foreach (var sh in win.doc.book.sheets) {
                var list = sh.comments.sorted ();
                if (list.size == 0) continue;
                var group = new PreferencesGroup (sh.name);
                foreach (var t in list) {
                    if (t.posts.size == 0) continue;
                    total++;
                    var tt = t;
                    var s = sh;
                    string first = tt.posts[0].text;
                    if (first.char_count () > 140) first = first.substring (0, first.index_of_nth_char (140)) + "...";
                    string info = tt.posts.size > 1 ? ngettext ("%d reply", "%d replies", tt.posts.size - 1).printf (tt.posts.size - 1) : "";
                    if (tt.resolved) info = info == "" ? _("Resolved") : info + ", " + _("Resolved");
                    var row = new ActionRow ("%s  %s".printf (Address.cell (tt.row, tt.col), tt.posts[0].author), info == "" ? first : first + "\n" + info);
                    row.activated.connect (() => {
                        win.go_to (s, tt.row, tt.col);
                        CommentsUi.open_thread (win, s, tt.row, tt.col);
                    });
                    group.add_row (row);
                }
                content.append (group);
            }
            if (total == 0) {
                var empty = new StatusPage ();
                empty.icon_name = "sheet-comment-symbolic";
                empty.title = _("No Comments");
                empty.description = _("Select a cell and start a conversation with New Comment.");
                empty.compact = true;
                empty.vexpand = true;
                content.append (empty);
            }
        }
    }
}
