using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class SpellHit {
        public Sheet sheet;
        public int row;
        public int col;
        public int start;
        public string word;
    }

    public class SpellScan {
        public Gee.HashSet<string> ignored = new Gee.HashSet<string> ();

        public static Gee.ArrayList<SpellHit> words_in (Sheet s, int r, int c, string text) {
            var list = new Gee.ArrayList<SpellHit> ();
            int i = 0;
            int n = text.length;
            while (i < n) {
                unichar ch = text.get_char (i);
                if (!ch.isalpha ()) {
                    i = text.index_of_nth_char (text.char_count (i) + 1) > i ? next_char (text, i) : n;
                    continue;
                }
                int start = i;
                while (i < n) {
                    unichar cc = text.get_char (i);
                    if (!(cc.isalpha () || cc == '\'')) break;
                    i = next_char (text, i);
                }
                string w = text.substring (start, i - start);
                while (w.has_suffix ("'")) w = w.substring (0, w.length - 1);
                if (w.char_count () > 1) {
                    var h = new SpellHit ();
                    h.sheet = s;
                    h.row = r;
                    h.col = c;
                    h.start = start;
                    h.word = w;
                    list.add (h);
                }
            }
            return list;
        }

        private static int next_char (string s, int i) {
            unichar ch;
            int j = i;
            s.get_next_char (ref j, out ch);
            return j;
        }

        public SpellHit? next (Workbook book, Sheet from, int row, int col, int start_after) {
            var checker = Singularity.Text.SpellChecker.get_default ();
            if (!checker.available) return null;
            int si = book.sheets.index_of (from);
            for (int k = 0; k < book.sheets.size; k++) {
                var s = book.sheets[(si + k) % book.sheets.size];
                var keys = new Gee.ArrayList<int64?> ();
                foreach (var e in s.cells.entries) {
                    var cl = e.value;
                    if (cl.formula != null || cl.value.kind != ValueKind.TEXT) continue;
                    keys.add (e.key);
                }
                keys.sort ((a, b) => {
                    int64 x = a;
                    int64 y = b;
                    return x < y ? -1 : (x > y ? 1 : 0);
                });
                foreach (var key in keys) {
                    int r = Sheet.key_row (key), c = Sheet.key_col (key);
                    if (k == 0 && (r < row || (r == row && c < col))) continue;
                    foreach (var h in words_in (s, r, c, s.get_cell (r, c).value.text)) {
                        if (k == 0 && r == row && c == col && h.start <= start_after) continue;
                        if (ignored.contains (h.word.casefold ())) continue;
                        if (h.word.up () == h.word && h.word.char_count () <= 5) continue;
                        if (!checker.check (h.word)) return h;
                    }
                }
            }
            return null;
        }
    }

    public class A11yIssue {
        public string title;
        public string detail;
        public Sheet? sheet;
        public int row = -1;
        public int col = -1;

        public A11yIssue (string title, string detail, Sheet? sheet = null, int row = -1, int col = -1) {
            this.title = title;
            this.detail = detail;
            this.sheet = sheet;
            this.row = row;
            this.col = col;
        }
    }

    public class A11yCheck {
        private static double lum (string hex) {
            string h = hex.has_prefix ("#") ? hex.substring (1) : hex;
            if (h.length != 6) return 1;
            double[] ch = new double[3];
            for (int i = 0; i < 3; i++) {
                double v = ("0x" + h.substring (i * 2, 2)).to_int64 () / 255.0;
                ch[i] = v <= 0.03928 ? v / 12.92 : Math.pow ((v + 0.055) / 1.055, 2.4);
            }
            return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2];
        }

        public static double contrast (string fg, string bg) {
            double a = lum (fg == "" ? "#000000" : fg), b = lum (bg == "" ? "#ffffff" : bg);
            return (double.max (a, b) + 0.05) / (double.min (a, b) + 0.05);
        }

        public static Gee.ArrayList<A11yIssue> run (Workbook book) {
            var list = new Gee.ArrayList<A11yIssue> ();
            foreach (var s in book.sheets) {
                if (/^(Sheet|Foglio|Feuil|Tabelle|Hoja)[0-9]+$/.match (s.name)) list.add (new A11yIssue (_("Default sheet name"), _("Give %s a name that describes its content.").printf (s.name), s, 0, 0));
                foreach (var m in s.merges) list.add (new A11yIssue (_("Merged cells"), _("Merged cells at %s can confuse screen readers.").printf (m.to_string ()), s, m.r1, m.c1));
                foreach (var ch in s.charts) {
                    if (ch.title.strip () == "") list.add (new A11yIssue (_("Chart without a title"), _("Add a title that describes what the chart shows."), s, -1, -1));
                    if (ch.alt_text.strip () == "") list.add (new A11yIssue (_("Chart without alternative text"), _("Add alternative text that summarizes what the chart shows."), s, -1, -1));
                }
                foreach (var d in s.drawings) {
                    if ((d.kind == DrawingKind.IMAGE || d.kind == DrawingKind.GROUP) && d.alt_text.strip () == "") list.add (new A11yIssue (d.kind == DrawingKind.IMAGE ? _("Picture without alternative text") : _("Diagram without alternative text"), _("Add alternative text that describes it to screen reader users."), s, -1, -1));
                }
                var seen = new Gee.HashSet<int> ();
                foreach (var cl in s.cells.values) {
                    if (cl.style == 0 || (cl.input == "" && cl.formula == null)) continue;
                    var st = book.styles[cl.style];
                    if (st.color == "" && st.fill == "") continue;
                    if (seen.contains (cl.style)) continue;
                    if (contrast (st.color, st.fill) < 4.5) {
                        seen.add (cl.style);
                        list.add (new A11yIssue (_("Hard-to-read text"), _("Text at %s has low contrast with its fill.").printf (Address.cell (cl.row, cl.col)), s, cl.row, cl.col));
                    }
                }
                foreach (var cl in s.cells.values) {
                    if (cl.link == "") continue;
                    string t = cl.value.display ().down ().strip ();
                    if (t == "click here" || t == "here" || t == "link" || t == "clicca qui") list.add (new A11yIssue (_("Unclear link text"), _("Describe where the link at %s goes.").printf (Address.cell (cl.row, cl.col)), s, cl.row, cl.col));
                }
            }
            foreach (var t in book.tables) {
                if (!t.header_row) list.add (new A11yIssue (_("Table without a header row"), _("Turn on the header row of %s.").printf (t.name), t.sheet, t.area.r1, t.area.c1));
                else {
                    for (int c = t.area.c1; c <= t.area.c2; c++) {
                        if (t.sheet.value_at (t.area.r1, c).is_empty ()) list.add (new A11yIssue (_("Blank table header"), _("Give the column at %s a header.").printf (Address.cell (t.area.r1, c)), t.sheet, t.area.r1, c));
                    }
                }
            }
            return list;
        }
    }

    public class Proofing {
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
            act (win, "spelling", () => spelling (win));
            act (win, "check-accessibility", () => accessibility (win));
        }

        private static void message (SpreadsheetWindow win, string title, string text) {
            var dlg = new ConfirmDialog.message ((Gtk.Application) win.application, title, "dialog-information", text);
            dlg.transient_for = win;
            dlg.present ();
        }

        public static void spelling (SpreadsheetWindow win) {
            var checker = Singularity.Text.SpellChecker.get_default ();
            if (!checker.available) {
                message (win, _("Spelling"), _("No dictionary is installed for your languages."));
                return;
            }
            var scan = new SpellScan ();
            var first = scan.next (win.doc.book, win.grid.sheet, win.grid.cur_row, win.grid.cur_col, -1);
            if (first == null) {
                message (win, _("Spelling"), _("The spelling check is complete. No mistakes were found."));
                return;
            }
            var dlg = Dialogs.make (win, _("Spelling"), 460, 520);
            var box = Dialogs.body (dlg);
            var group = new PreferencesGroup ("", "");
            var change = new EntryRow (_("Change to"));
            group.add_row (change);
            box.append (group);
            var sugg = new PreferencesGroup (_("Suggestions"));
            box.append (sugg);
            SpellHit current = first;
            Act show = null;
            show = () => {
                win.go_to (current.sheet, current.row, current.col);
                group.title = current.word;
                group.description = _("Not in dictionary, in %s!%s").printf (current.sheet.name, Address.cell (current.row, current.col));
                sugg.clear ();
                string[] options = checker.suggest (current.word, 6);
                change.text = options.length > 0 ? options[0] : current.word;
                foreach (string o in options) {
                    var row = new ActionRow (o, null);
                    row.activatable = true;
                    string pick = o;
                    row.activated.connect (() => change.text = pick);
                    sugg.add_row (row);
                }
                if (options.length == 0) sugg.add_row (new ActionRow (_("No suggestions"), null));
            };
            Act advance = () => {
                var n = scan.next (win.doc.book, current.sheet, current.row, current.col, current.start);
                if (n == null) {
                    dlg.close ();
                    message (win, _("Spelling"), _("The spelling check is complete."));
                    return;
                }
                current = n;
                show ();
            };
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            var ignore = new Button.with_label (_("Ignore"));
            ignore.clicked.connect (() => advance ());
            var ignore_all = new Button.with_label (_("Ignore All"));
            ignore_all.clicked.connect (() => {
                scan.ignored.add (current.word.casefold ());
                advance ();
            });
            var add = new Button.with_label (_("Add to Dictionary"));
            add.clicked.connect (() => {
                checker.add_to_dictionary (current.word);
                advance ();
            });
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            var change_all = new Button.with_label (_("Change All"));
            change_all.clicked.connect (() => {
                string from = current.word, to = change.text;
                win.doc.begin_book (_("Spelling"), current.sheet);
                foreach (var s in win.doc.book.sheets) {
                    foreach (var cl in s.cells.values.to_array ()) {
                        if (cl.formula != null || cl.value.kind != ValueKind.TEXT || !cl.input.contains (from)) continue;
                        s.set_input (cl.row, cl.col, replace_word (cl.input, from, to));
                    }
                }
                win.doc.book.structure_changed = true;
                win.doc.commit ();
                scan.ignored.add (to.casefold ());
                advance ();
            });
            var change_one = new Button.with_label (_("Change"));
            change_one.add_css_class ("suggested-action");
            change_one.clicked.connect (() => {
                string text = current.sheet.input_at (current.row, current.col);
                string fixed_text = text.substring (0, current.start) + change.text + text.substring (current.start + current.word.length);
                win.doc.set_input (current.sheet, current.row, current.col, fixed_text);
                current.start += change.text.length - current.word.length;
                advance ();
            });
            bar.append (ignore);
            bar.append (ignore_all);
            bar.append (add);
            bar.append (spacer);
            bar.append (change_all);
            bar.append (change_one);
            dlg.content_box.append (bar);
            show ();
            dlg.open_dialog ();
        }

        private static string replace_word (string text, string from, string to) {
            try {
                var re = new Regex ("\\b" + Regex.escape_string (from) + "\\b");
                return re.replace (text, -1, 0, to.replace ("\\", "\\\\"));
            } catch (RegexError e) {
                return text.replace (from, to);
            }
        }

        public static void accessibility (SpreadsheetWindow win) {
            var issues = A11yCheck.run (win.doc.book);
            var dlg = Dialogs.make (win, _("Check Accessibility"), 480, 560);
            var box = Dialogs.body (dlg);
            if (issues.size == 0) {
                var ok = new StatusPage ();
                ok.icon_name = "object-select-symbolic";
                ok.title = _("No issues found");
                ok.description = _("People with disabilities should not have trouble reading this workbook.");
                box.append (ok);
            } else {
                var g = new PreferencesGroup (ngettext ("%d issue", "%d issues", issues.size).printf (issues.size), _("Select an issue to go to it."));
                foreach (var issue in issues) {
                    var row = new ActionRow (issue.title, issue.detail);
                    if (issue.sheet != null && issue.row >= 0) {
                        row.activatable = true;
                        var s = issue.sheet;
                        int r = issue.row, c = issue.col;
                        row.activated.connect (() => win.go_to (s, r, c));
                    }
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
