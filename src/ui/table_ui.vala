using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class TableUi {
        private static string[] style_labels () {
            return { _("Light gray"), _("Light blue"), _("Blue"), _("Green"), _("Blue banded"), _("Dark") };
        }

        private static string style_label (string name) {
            var names = TableCommands.style_names ();
            var labels = style_labels ();
            for (int i = 0; i < names.length; i++) if (names[i] == name) return labels[i];
            return labels[2];
        }

        private static string style_name (string label) {
            var names = TableCommands.style_names ();
            var labels = style_labels ();
            for (int i = 0; i < labels.length; i++) if (labels[i] == label) return names[i];
            return "TableStyleMedium2";
        }

        private delegate void Act ();

        private static void act (SpreadsheetWindow win, string name, owned Act handler) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => {
                if (win.doc == null || win.grid == null) return;
                handler ();
            });
            win.add_action (a);
        }

        public static void install (SpreadsheetWindow win) {
            act (win, "insert-table", () => {
                var t = Tables.at (win.doc.book, win.grid.sheet, win.grid.cur_row, win.grid.cur_col);
                if (t != null) design (win, t);
                else insert (win);
            });
            act (win, "calc-options", () => calc_options (win));
        }

        private static void message (SpreadsheetWindow win, string title, string text) {
            var dlg = new ConfirmDialog.message ((Gtk.Application) win.application, title, "dialog-information", text);
            dlg.transient_for = win;
            dlg.present ();
        }

        public static void insert (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            if (sel.is_single ()) sel = win.doc.current_region (s, sel.r1, sel.c1);
            var dlg = Dialogs.make (win, _("Create Table"), 460, 470);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Table"), _("Tables grow as you type below them and can be used in formulas by name, such as Table1[Amount]."));
            var range = new EntryRow (_("Range"));
            range.text = Dialogs.area_text (sel);
            var header = new SwitchRow (_("My table has headers"), null, s.value_at (sel.r1, sel.c1).kind == ValueKind.TEXT);
            var labels = style_labels ();
            var st = new SelectionRow (_("Style"), labels, labels[2]);
            g.add_row (range);
            g.add_row (header);
            g.add_row (st);
            box.append (g);
            Dialogs.footer (dlg, _("Create"), () => {
                var a = Area.parse (range.text.replace ("$", ""), s) ?? sel;
                var t = TableCommands.create (win.doc, s, a, header.active, style_name (st.current_value));
                if (t == null) message (win, _("Create Table"), _("Tables cannot overlap another table."));
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }

        public static void design (SpreadsheetWindow win, TableDef t) {
            var dlg = Dialogs.make (win, _("Table Design"), 460, 560);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (t.name, _("%s on %s").printf (Dialogs.area_text (t.area), t.sheet.name));
            var name = new EntryRow (_("Name"));
            name.text = t.name;
            var labels = style_labels ();
            var st = new SelectionRow (_("Style"), labels, style_label (t.style_name));
            g.add_row (name);
            g.add_row (st);
            box.append (g);
            var opts = new PreferencesGroup (_("Options"));
            var totals = new SwitchRow (_("Total row"), _("Adds a row with totals at the bottom"), t.totals_row);
            var banded = new SwitchRow (_("Banded rows"), null, t.banded_rows);
            var banded_c = new SwitchRow (_("Banded columns"), null, t.banded_cols);
            var first = new SwitchRow (_("First column"), null, t.first_col);
            var last = new SwitchRow (_("Last column"), null, t.last_col);
            var filter = new SwitchRow (_("Filter buttons"), null, t.filter_button);
            opts.add_row (totals);
            opts.add_row (banded);
            opts.add_row (banded_c);
            opts.add_row (first);
            opts.add_row (last);
            opts.add_row (filter);
            box.append (opts);
            Dialogs.footer (dlg, _("Apply"), () => {
                string n = name.text.strip ();
                if (!valid_name (n)) n = t.name;
                TableCommands.update (win.doc, t, n, totals.active, banded.active, banded_c.active, first.active, last.active, filter.active, style_name (st.current_value));
                win.grid.refresh ();
            }, _("Convert to Range"), () => {
                TableCommands.convert_to_range (win.doc, t);
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }

        private static bool valid_name (string n) {
            if (n == "" || !(n[0].isalpha () || n[0] == '_')) return false;
            for (int i = 0; i < n.length; i++) if (!(n[i].isalnum () || n[i] == '_' || n[i] == '.')) return false;
            int r, c;
            bool a, b;
            return !Address.parse_cell (n, out r, out c, out a, out b);
        }

        public static void calc_options (SpreadsheetWindow win) {
            var book = win.doc.book;
            var dlg = Dialogs.make (win, _("Calculation"), 460, 460);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Workbook"));
            var auto = new SwitchRow (_("Automatic"), _("Recalculate after every change. When off, press F9 to calculate."), !book.manual_calc);
            var iter = new SwitchRow (_("Iterative calculation"), _("Allows circular references to converge"), book.iterative);
            var max_it = new SpinRow (_("Maximum iterations"), null, 1, 32767, 1, book.max_iterations);
            var max_ch = new EntryRow (_("Maximum change"));
            max_ch.text = Value.format_number_general_full (book.max_change);
            g.add_row (auto);
            g.add_row (iter);
            g.add_row (max_it);
            g.add_row (max_ch);
            box.append (g);
            if (book.circular.size > 0) {
                var circ = new PreferencesGroup (_("Circular References"));
                foreach (string c in book.circular) {
                    var row = new ActionRow (c, null);
                    circ.add_row (row);
                }
                box.append (circ);
            }
            Dialogs.footer (dlg, _("Apply"), () => {
                book.manual_calc = !auto.active;
                book.iterative = iter.active;
                book.max_iterations = (int) max_it.value;
                double d = double.parse (max_ch.text.replace (",", "."));
                if (d > 0) book.max_change = d;
                win.doc.modified = true;
                win.doc.calculate_full ();
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }
    }
}
