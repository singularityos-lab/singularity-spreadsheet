using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class LiveState : Object {
        public LiveSession? session;
        public LiveSheetSync? sync;
        public Button chip;
        public Box dots;
        public Label count;
        public SheetView? drawn;
        public ulong overlay_handler;
        public ulong selection_handler;
    }

    public class LiveUi {
        public delegate void Act ();

        public static LiveState state_of (SpreadsheetWindow win) {
            var st = win.get_data<LiveState> ("ss-live");
            if (st == null) {
                st = new LiveState ();
                win.set_data<LiveState> ("ss-live", st);
            }
            return st;
        }

        public static bool active (SpreadsheetWindow win) {
            return state_of (win).session != null;
        }

        public static void install (SpreadsheetWindow win) {
            var st = state_of (win);
            var a = new SimpleAction ("edit-together", null);
            a.activate.connect (() => {
                if (win.doc != null) dialog (win);
            });
            win.add_action (a);
            var box = new Box (Orientation.HORIZONTAL, 6);
            st.dots = new Box (Orientation.HORIZONTAL, 3);
            st.count = new Label ("");
            box.append (st.dots);
            box.append (st.count);
            st.chip = new Button ();
            st.chip.child = box;
            st.chip.add_css_class ("flat");
            st.chip.tooltip_text = _("People editing this spreadsheet");
            st.chip.clicked.connect (() => dialog (win));
            st.chip.visible = false;
            win.add_bubble_widget (st.chip);
            win.notify["grid"].connect (() => attach_grid (win));
            win.notify["doc"].connect (() => {
                var s = state_of (win);
                if (s.sync != null && s.sync.doc != win.doc) stop (win, false);
            });
        }

        private static void attach_grid (SpreadsheetWindow win) {
            var st = state_of (win);
            if (st.drawn != null) {
                if (st.overlay_handler != 0) st.drawn.disconnect (st.overlay_handler);
                if (st.selection_handler != 0) st.drawn.disconnect (st.selection_handler);
            }
            st.drawn = win.grid;
            st.overlay_handler = st.selection_handler = 0;
            if (win.grid == null) return;
            st.overlay_handler = win.grid.draw_overlay.connect ((cr, w, h) => draw (win, cr));
            st.selection_handler = win.grid.selection_changed.connect (() => send_presence (win));
        }

        private static void rgb (Cairo.Context cr, string hex, double alpha) {
            cr.set_source_rgba (Xlsx.hex2 (hex, 1) / 255.0, Xlsx.hex2 (hex, 3) / 255.0, Xlsx.hex2 (hex, 5) / 255.0, alpha);
        }

        private static void draw (SpreadsheetWindow win, Cairo.Context cr) {
            var st = state_of (win);
            if (st.session == null || win.grid == null) return;
            var grid = win.grid;
            foreach (var p in st.session.peers.values) {
                if (p.info == null || !p.info.has_member ("sheet")) continue;
                if (p.info.get_string_member ("sheet") != grid.sheet.name) continue;
                int r = (int) p.info.get_int_member ("r"), c = (int) p.info.get_int_member ("c");
                int r1 = (int) p.info.get_int_member ("r1"), c1 = (int) p.info.get_int_member ("c1");
                int r2 = (int) p.info.get_int_member ("r2"), c2 = (int) p.info.get_int_member ("c2");
                r2 = int.min (r2, r1 + 2000);
                c2 = int.min (c2, c1 + 500);
                var a = grid.cell_rect (r1, c1);
                var b = grid.cell_rect (r2, c2);
                double x = a.origin.x, y = a.origin.y;
                double w = b.origin.x + b.size.width - x, h = b.origin.y + b.size.height - y;
                cr.save ();
                if (r1 != r2 || c1 != c2) {
                    rgb (cr, p.color, 0.12);
                    cr.rectangle (x, y, w, h);
                    cr.fill ();
                }
                var cur = grid.cell_rect (r, c);
                rgb (cr, p.color, 1);
                cr.set_line_width (2);
                cr.rectangle (cur.origin.x + 1, cur.origin.y + 1, cur.size.width - 2, cur.size.height - 2);
                cr.stroke ();
                var layout = grid.create_pango_layout (p.name);
                var fd = Pango.FontDescription.from_string ("Sans Bold 8");
                layout.set_font_description (fd);
                int tw, th;
                layout.get_pixel_size (out tw, out th);
                double lx = cur.origin.x, ly = cur.origin.y - th - 4;
                if (ly < 0) ly = cur.origin.y + cur.size.height;
                rgb (cr, p.color, 1);
                cr.rectangle (lx, ly, tw + 8, th + 4);
                cr.fill ();
                cr.set_source_rgb (1, 1, 1);
                cr.move_to (lx + 4, ly + 2);
                Pango.cairo_show_layout (cr, layout);
                cr.restore ();
            }
        }

        private static void send_presence (SpreadsheetWindow win) {
            var st = state_of (win);
            if (st.session == null || win.grid == null) return;
            var sel = win.grid.selection;
            var o = new Json.Object ();
            o.set_string_member ("sheet", win.grid.sheet.name);
            o.set_int_member ("r", win.grid.cur_row);
            o.set_int_member ("c", win.grid.cur_col);
            o.set_int_member ("r1", sel.r1);
            o.set_int_member ("c1", sel.c1);
            o.set_int_member ("r2", sel.r2);
            o.set_int_member ("c2", sel.c2);
            st.session.presence (o);
        }

        private static void update_chip (SpreadsheetWindow win) {
            var st = state_of (win);
            Widget? child;
            while ((child = st.dots.get_first_child ()) != null) st.dots.remove (child);
            if (st.session == null) {
                st.chip.visible = false;
                return;
            }
            var colors = new Gee.ArrayList<string> ();
            colors.add (st.session.color);
            foreach (var p in st.session.peers.values) colors.add (p.color);
            int shown = 0;
            foreach (string col in colors) {
                if (shown++ >= 5) break;
                var dot = new DrawingArea ();
                dot.set_size_request (12, 12);
                dot.valign = Align.CENTER;
                string cc = col;
                dot.set_draw_func ((d, cr, w, h) => {
                    rgb (cr, cc, 1);
                    cr.arc (w / 2.0, h / 2.0, 5, 0, 2 * Math.PI);
                    cr.fill ();
                });
                st.dots.append (dot);
            }
            int n = colors.size;
            st.count.label = ngettext ("%d person", "%d people", n).printf (n);
            st.chip.visible = true;
        }

        private static void toast (SpreadsheetWindow win, string text) {
            win.add_toast (new Toast (text));
        }

        private static void wire (SpreadsheetWindow win, LiveSession s) {
            var st = state_of (win);
            st.session = s;
            s.peers_changed.connect (() => {
                update_chip (win);
                if (win.grid != null) win.grid.queue_draw ();
            });
            s.peer_joined.connect ((p) => toast (win, _("%s joined").printf (p.name)));
            s.peer_left.connect ((p) => toast (win, _("%s left").printf (p.name)));
            s.ended.connect ((reason) => {
                toast (win, reason);
                stop (win, false);
            });
            s.message.connect ((m) => {
                var sy = state_of (win).sync;
                if (sy != null) sy.receive (m);
            });
            s.state_requested.connect (() => {
                var sy = state_of (win).sync;
                if (sy == null) return;
                try {
                    s.publish_state (sy.snapshot ());
                } catch (Error e) {
                }
            });
            update_chip (win);
        }

        private static void attach_sync (SpreadsheetWindow win, int64 clock, int sv) {
            var st = state_of (win);
            var sy = new LiveSheetSync (win.doc, st.session.my_id);
            sy.clock = clock;
            sy.base_sv = sv;
            sy.outgoing.connect ((m) => {
                if (st.session != null) st.session.send (m);
            });
            sy.applied.connect ((sheets) => {
                if (sheets) win.doc.sheets_changed ();
                win.doc.changed ();
                if (win.grid != null) win.grid.refresh ();
            });
            st.sync = sy;
            attach_grid (win);
            send_presence (win);
        }

        private static string me () {
            return CommentStore.current_author ();
        }

        public static void start_host (SpreadsheetWindow win) throws Error {
            var s = new LiveSession (me (), "sheet-live", "/sheet");
            wire (win, s);
            var sy = new LiveSheetSync (win.doc, s.my_id);
            state_of (win).sync = sy;
            s.host_secure (sy.snapshot ());
            sy.detach ();
            attach_sync (win, 0, 0);
        }

        public static void join (SpreadsheetWindow win, string link) {
            var s = new LiveSession (me (), "sheet-live", "/sheet");
            wire (win, s);
            s.welcome.connect ((state) => {
                try {
                    int64 clock;
                    int sv;
                    var book = LiveSheetSync.book_from (state, out clock, out sv);
                    var st = state_of (win);
                    var keep = st.session;
                    st.session = null;
                    win.load_document (new Document.with_book (book, null));
                    st.session = keep;
                    attach_sync (win, clock, sv);
                    update_chip (win);
                    toast (win, _("Joined the live spreadsheet."));
                } catch (Error e) {
                    toast (win, e.message);
                    stop (win, true);
                }
            });
            s.join.begin (link, (o, res) => {
                try {
                    s.join.end (res);
                } catch (Error e) {
                    toast (win, e.message);
                    stop (win, false);
                }
            });
        }

        public static void start_folder (SpreadsheetWindow win, string dir, bool create) throws Error {
            var s = new LiveSession (me (), "sheet-live", "/sheet");
            wire (win, s);
            if (create) {
                var sy = new LiveSheetSync (win.doc, s.my_id);
                var snap = sy.snapshot ();
                sy.detach ();
                s.start_folder (dir, snap);
                attach_sync (win, 0, 0);
                return;
            }
            bool loaded = false;
            s.welcome.connect ((state) => {
                try {
                    int64 clock;
                    int sv;
                    var book = LiveSheetSync.book_from (state, out clock, out sv);
                    var st = state_of (win);
                    var keep = st.session;
                    st.session = null;
                    win.load_document (new Document.with_book (book, null));
                    st.session = keep;
                    attach_sync (win, clock, sv);
                    loaded = true;
                } catch (Error e) {
                    toast (win, e.message);
                }
            });
            s.start_folder (dir, null);
            if (!loaded) throw new IOError.FAILED (_("The shared folder could not be read."));
            update_chip (win);
        }

        public static void stop (SpreadsheetWindow win, bool quiet) {
            var st = state_of (win);
            if (st.sync != null) st.sync.detach ();
            st.sync = null;
            if (st.session != null) {
                var s = st.session;
                st.session = null;
                s.leave ();
                if (!quiet) toast (win, _("You left the live session."));
            }
            update_chip (win);
            if (win.grid != null) win.grid.queue_draw ();
        }

        public static void dialog (SpreadsheetWindow win) {
            var st = state_of (win);
            var dlg = ToolDialogs.make (win, _("Edit Together"), 500, 580);
            var box = ToolDialogs.scroll_box (dlg.content_box);
            if (st.session != null) {
                var s = st.session;
                var g = new PreferencesGroup (s.mode == LiveMode.FOLDER ? _("Shared through a folder") : _("Live session"));
                if (s.mode == LiveMode.HOST) {
                    var link = new ActionRow (_("Link"), s.link);
                    var copy = ToolDialogs.flat ("edit-copy-symbolic", _("Copy Link"));
                    copy.clicked.connect (() => {
                        copy.get_clipboard ().set_text (s.link);
                        toast (win, _("Link copied."));
                    });
                    link.add_suffix (copy);
                    g.add_row (link);
                } else {
                    g.add_row (new ActionRow (s.mode == LiveMode.FOLDER ? _("Folder") : _("Link"), s.link));
                }
                box.append (g);
                var pg = new PreferencesGroup (_("People"));
                pg.add_row (new ActionRow (s.name, _("You")));
                foreach (var p in s.peers.values) {
                    string where = p.info != null && p.info.has_member ("sheet") ? "%s!%s".printf (Address.quote_sheet (p.info.get_string_member ("sheet")), Address.cell ((int) p.info.get_int_member ("r"), (int) p.info.get_int_member ("c"))) : "";
                    pg.add_row (new ActionRow (p.name, where));
                }
                box.append (pg);
                var bar = ToolDialogs.close_footer (dlg);
                var stop_btn = new Button.with_label (_("Stop Sharing"));
                stop_btn.add_css_class ("destructive-action");
                stop_btn.clicked.connect (() => {
                    stop (win, false);
                    dlg.close ();
                });
                bar.prepend (stop_btn);
                dlg.open_dialog ();
                return;
            }
            var hg = new PreferencesGroup (_("On this network"), _("Others join with the link and its key. Every edit merges cell by cell, and everyone sees each other's selection."));
            var start = new ActionRow (_("Start a Live Session"), _("Creates a link to share"));
            start.activated.connect (() => {
                try {
                    start_host (win);
                    dlg.close ();
                    dialog (win);
                } catch (Error e) {
                    toast (win, e.message);
                }
            });
            hg.add_row (start);
            var join_row = new EntryRow (_("Join with a Link"));
            var jb = new Button.with_label (_("Join"));
            jb.valign = Align.CENTER;
            jb.clicked.connect (() => {
                string l = join_row.text.strip ();
                if (l == "") return;
                dlg.close ();
                join (win, l);
            });
            join_row.entry_activated.connect (() => jb.clicked ());
            join_row.add_suffix (jb);
            hg.add_row (join_row);
            box.append (hg);
            var cg = new PreferencesGroup (_("Through a cloud folder"), _("Choose a folder of an online account that everyone can open. The session is kept in it, so it also works across networks."));
            var fstart = new ActionRow (_("Share in a Folder"), _("Start editing together in a folder"));
            var fjoin = new ActionRow (_("Join from a Folder"), _("Open a spreadsheet someone shared in a folder"));
            cg.add_row (fstart);
            cg.add_row (fjoin);
            box.append (cg);
            foreach (var row in new ActionRow[] { fstart, fjoin }) {
                bool create = row == fstart;
                row.activated.connect (() => {
                    var fd = new FileDialog ();
                    fd.title = create ? _("Choose a Shared Folder") : _("Choose the Shared Folder");
                    string cloud = Path.build_filename (Environment.get_home_dir (), "Cloud");
                    if (FileUtils.test (cloud, FileTest.IS_DIR)) fd.initial_folder = File.new_for_path (cloud);
                    fd.select_folder.begin (win, null, (o, res) => {
                        try {
                            var folder = fd.select_folder.end (res);
                            if (folder == null || folder.get_path () == null) return;
                            start_folder (win, Path.build_filename (folder.get_path (), ".sheet-live"), create);
                            dlg.close ();
                            toast (win, create ? _("The spreadsheet is shared in the folder.") : _("Joined the shared spreadsheet."));
                        } catch (Error e) {
                            if (!(e is DialogError.DISMISSED)) toast (win, e.message);
                        }
                    });
                });
            }
            ToolDialogs.close_footer (dlg);
            dlg.open_dialog ();
        }
    }
}
