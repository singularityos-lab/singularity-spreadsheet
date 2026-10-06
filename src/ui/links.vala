using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class Links {
        public static string target (Workbook book, Sheet s, int r, int c) {
            var cell = s.get_cell (r, c);
            if (cell == null) return "";
            if (cell.link != "") return cell.link;
            if (cell.formula != null && cell.formula.kind == NodeKind.CALL && cell.formula.text == "HYPERLINK" && cell.formula.args.length > 0) {
                var ev = new Evaluator (book, s, r, c);
                var v = ev.arg (cell.formula.args[0]);
                if (!v.is_error ()) return Evaluator.to_text (v);
            }
            return "";
        }

        public static string describe (string link) {
            if (link.has_prefix ("#")) return _("Go to %s").printf (link.substring (1));
            return link;
        }

        public static void follow (SpreadsheetWindow win, string link) {
            if (link == "") return;
            if (link.has_prefix ("#")) {
                jump (win, link.substring (1));
                return;
            }
            string uri = link;
            if (!uri.contains ("://") && !uri.has_prefix ("mailto:")) {
                string base_dir = win.doc.path != null ? Path.get_dirname (win.doc.path) : Environment.get_home_dir ();
                string p = Path.is_absolute (uri) ? uri : Path.build_filename (base_dir, uri);
                uri = File.new_for_path (p).get_uri ();
            }
            var launcher = new UriLauncher (uri);
            launcher.launch.begin (win, null, (obj, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    win.show_error (_("Could Not Open Link"), e.message);
                }
            });
        }

        private static void jump (SpreadsheetWindow win, string place) {
            var book = win.doc.book;
            string p = place;
            Sheet sheet = win.grid.sheet;
            int bang = p.last_index_of_char ('!');
            if (bang > 0) {
                string sn = p.substring (0, bang);
                if (sn.has_prefix ("'") && sn.has_suffix ("'")) sn = sn.substring (1, sn.length - 2).replace ("''", "'");
                var found = book.find_sheet (sn);
                if (found == null) return;
                sheet = found;
                p = p.substring (bang + 1);
            }
            var area = Area.parse (p.replace ("$", ""), sheet);
            if (area == null) {
                string? def = sheet.names[p] ?? book.names[p];
                if (def != null) {
                    try {
                        var n = Formula.parse ("=" + (def.has_prefix ("=") ? def.substring (1) : def), book, sheet);
                        if (n.kind == NodeKind.REF && n.a != null) area = n.to_area (sheet);
                    } catch (FormulaError e) {
                    }
                }
            }
            if (area == null || area.sheet == null) return;
            win.go_to (area.sheet, area.r1, area.c1);
            if (!area.is_single ()) win.grid.select_area (area);
        }

        public static void dialog (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            var area = Document.clamp_area (s, sel);
            string current = target (win.doc.book, s, area.r1, area.c1);
            var cell = s.get_cell (area.r1, area.c1);
            var dlg = Dialogs.make (win, current != "" ? _("Edit Link") : _("Insert Link"), 460, 300);
            var box = Dialogs.body (dlg);
            var group = new PreferencesGroup ();
            var addr = new EntryRow (_("Address or place in this workbook"));
            addr.text = current.has_prefix ("#") ? current.substring (1) : current;
            var text = new EntryRow (_("Text to display"));
            text.text = cell != null ? s.value_at (area.r1, area.c1).display () : "";
            group.add_row (addr);
            group.add_row (text);
            box.append (group);
            Dialogs.Apply apply = () => {
                string a = addr.text.strip ();
                if (a == "") return;
                string link = a.has_prefix ("www.") ? "https://" + a : a;
                if (!looks_external (a)) link = "#" + a;
                string shown = text.text.strip ();
                if (cell != null && cell.formula != null && shown == s.value_at (area.r1, area.c1).display ()) shown = "";
                win.doc.set_link (s, area, link, shown != "" ? shown : (cell == null || cell.input == "" ? a : null));
                win.grid.refresh ();
            };
            if (current != "" && cell != null && cell.link != "") {
                Dialogs.footer (dlg, _("Apply"), (owned) apply, _("Remove Link"), () => {
                    win.doc.set_link (s, area, "", null);
                    win.grid.refresh ();
                });
            } else {
                Dialogs.footer (dlg, _("Insert"), (owned) apply);
            }
            dlg.open_dialog ();
            addr.grab_focus ();
        }

        public static bool looks_external (string a) {
            if (a.contains ("://") || a.has_prefix ("mailto:") || a.has_prefix ("www.")) return true;
            if (a.has_prefix ("/") || a.has_prefix ("~")) return true;
            string low = a.down ();
            foreach (string ext in new string[] { ".xlsx", ".ods", ".pdf", ".docx", ".odt", ".csv", ".html", ".txt", ".png", ".jpg" }) {
                if (low.has_suffix (ext)) return true;
            }
            return false;
        }
    }
}
