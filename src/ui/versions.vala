using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class Versions {
        private const int KEEP = 30;

        public static string folder_for (string path) {
            string id = Checksum.compute_for_string (ChecksumType.SHA1, path).substring (0, 16);
            return Path.build_filename (Environment.get_user_data_dir (), "singularity-spreadsheet", "versions", id);
        }

        public static void keep_previous (string path) {
            if (!FileUtils.test (path, FileTest.IS_REGULAR)) return;
            string dir = folder_for (path);
            DirUtils.create_with_parents (dir, 0700);
            string ext = path.last_index_of (".") > 0 ? path.substring (path.last_index_of (".")) : "";
            var now = new DateTime.now_local ();
            string target = Path.build_filename (dir, now.format ("%Y%m%d-%H%M%S") + ext);
            try {
                File.new_for_path (path).copy (File.new_for_path (target), FileCopyFlags.OVERWRITE);
                FileUtils.set_contents (Path.build_filename (dir, "source.txt"), path);
            } catch (Error e) {
                warning ("spreadsheet versions: %s", e.message);
                return;
            }
            var all = list (path);
            for (int i = KEEP; i < all.size; i++) FileUtils.unlink (all[i]);
        }

        public static Gee.ArrayList<string> list (string path) {
            var result = new Gee.ArrayList<string> ();
            string dir = folder_for (path);
            try {
                var d = Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (name == "source.txt") continue;
                    result.add (Path.build_filename (dir, name));
                }
            } catch (FileError e) {
            }
            result.sort ((a, b) => strcmp (b, a));
            return result;
        }

        private static string label_for (string file) {
            string b = Path.get_basename (file);
            if (b.length < 15) return b;
            var dt = new DateTime.local (int.parse (b.substring (0, 4)), int.parse (b.substring (4, 2)), int.parse (b.substring (6, 2)),
                int.parse (b.substring (9, 2)), int.parse (b.substring (11, 2)), int.parse (b.substring (13, 2)));
            return dt.format ("%x %X");
        }

        public static void show (SpreadsheetWindow win) {
            var dlg = Dialogs.make (win, _("Version History"), 460, 520);
            var box = Dialogs.body (dlg);
            string? path = win.doc.path;
            var items = path != null ? list (path) : new Gee.ArrayList<string> ();
            if (items.size == 0) {
                var empty = new StatusPage ();
                empty.icon_name = "document-open-recent-symbolic";
                empty.title = _("No earlier versions");
                empty.description = _("Each time you save, the previous version is kept here.");
                box.append (empty);
            } else {
                var g = new PreferencesGroup (Path.get_basename (path), _("Open a version to compare it, or restore it to replace the current file."));
                foreach (string item in items) {
                    var row = new ActionRow (label_for (item), null);
                    string file = item;
                    var open = new Button.with_label (_("Open"));
                    open.valign = Align.CENTER;
                    open.clicked.connect (() => {
                        try {
                            var d = Document.open (file);
                            d.path = null;
                            var nw = new SpreadsheetWindow ((SpreadsheetApp) win.application);
                            nw.present ();
                            nw.load_document (d);
                            dlg.close ();
                        } catch (Error e) {
                            warning ("spreadsheet versions: %s", e.message);
                        }
                    });
                    var restore = new Button.with_label (_("Restore"));
                    restore.valign = Align.CENTER;
                    restore.clicked.connect (() => {
                        try {
                            keep_previous (path);
                            File.new_for_path (file).copy (File.new_for_path (path), FileCopyFlags.OVERWRITE);
                            var d = Document.open (path);
                            win.load_document (d);
                            dlg.close ();
                        } catch (Error e) {
                            warning ("spreadsheet versions: %s", e.message);
                        }
                    });
                    row.add_suffix (open);
                    row.add_suffix (restore);
                    g.add_row (row);
                }
                box.append (g);
            }
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
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
