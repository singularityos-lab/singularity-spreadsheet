using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class EditDialogs {
        public static void message (SpreadsheetWindow win, string title, string text, string icon = "dialog-information") {
            var dlg = new ConfirmDialog.message ((Gtk.Application) win.application, title, icon, text);
            dlg.transient_for = win;
            dlg.present ();
        }

        private static PasswordHash? ask_new_password (SpreadsheetWindow win, PasswordRow pw, PasswordRow confirm) {
            if (pw.text != confirm.text) {
                message (win, _("Passwords Don't Match"), _("The confirmation password is not identical. Type the same password in both fields."), "dialog-warning");
                return null;
            }
            return PasswordHash.create (pw.text);
        }

        public static void protect_sheet (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            if (s.protection != null) {
                unprotect_sheet (win);
                return;
            }
            var dlg = Dialogs.make (win, _("Protect Sheet"), 460, 640);
            var box = Dialogs.body (dlg);
            var g0 = new PreferencesGroup (_("Password"), _("Cells stay locked unless their Locked option is turned off. The password is optional."));
            var pw = new PasswordRow (_("Password to unprotect"));
            var confirm = new PasswordRow (_("Confirm password"));
            g0.add_row (pw);
            g0.add_row (confirm);
            box.append (g0);
            var g = new PreferencesGroup (_("Allow Everyone To"));
            string[] labels = { _("Select locked cells"), _("Select unlocked cells"), _("Format cells"), _("Format columns"), _("Format rows"),
                _("Insert columns"), _("Insert rows"), _("Insert hyperlinks"), _("Delete columns"), _("Delete rows"), _("Sort"), _("Use AutoFilter"),
                _("Use PivotTables"), _("Edit objects"), _("Edit scenarios") };
            bool[] defaults = { true, true, false, false, false, false, false, false, false, false, false, false, false, false, false };
            var rows = new Gee.ArrayList<SwitchRow> ();
            for (int i = 0; i < labels.length; i++) {
                var row = new SwitchRow (labels[i], null, defaults[i]);
                rows.add (row);
                g.add_row (row);
            }
            box.append (g);
            Dialogs.footer (dlg, _("Protect"), () => {
                var hash = ask_new_password (win, pw, confirm);
                if (hash == null) return;
                var p = new SheetProtection ();
                p.password = hash;
                p.select_locked = rows[0].active;
                p.select_unlocked = rows[1].active;
                p.format_cells = rows[2].active;
                p.format_columns = rows[3].active;
                p.format_rows = rows[4].active;
                p.insert_columns = rows[5].active;
                p.insert_rows = rows[6].active;
                p.insert_hyperlinks = rows[7].active;
                p.delete_columns = rows[8].active;
                p.delete_rows = rows[9].active;
                p.sort = rows[10].active;
                p.autofilter = rows[11].active;
                p.pivot_tables = rows[12].active;
                p.objects = rows[13].active;
                p.scenarios = rows[14].active;
                if (pending_ranges ().has_key (s)) {
                    p.ranges.add_all (pending_ranges ()[s]);
                    pending_ranges ().unset (s);
                }
                EditCommands.protect_sheet (win.doc, s, p);
                win.grid.queue_draw ();
            });
            dlg.open_dialog ();
        }

        private static void ask_password (SpreadsheetWindow win, string title, PasswordHash hash, owned Dialogs.Apply then) {
            if (!hash.is_set ()) {
                then ();
                return;
            }
            var dlg = Dialogs.make (win, title, 400, 220);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup ();
            var pw = new PasswordRow (_("Password"));
            g.add_row (pw);
            box.append (g);
            Dialogs.footer (dlg, _("Unprotect"), () => {
                if (hash.verify (pw.text)) then ();
                else message (win, _("Wrong Password"), _("The password you supplied is not correct. Verify that the Caps Lock key is off and be sure to use the correct capitalization."), "dialog-error");
            });
            dlg.open_dialog ();
            pw.grab_focus ();
        }

        public static void unprotect_sheet (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            if (s.protection == null) return;
            ask_password (win, _("Unprotect Sheet"), s.protection.password, () => {
                EditCommands.protect_sheet (win.doc, s, null);
                win.grid.queue_draw ();
            });
        }

        public static void protect_book (SpreadsheetWindow win) {
            var book = win.doc.book;
            if (book.protection != null) {
                ask_password (win, _("Unprotect Workbook"), book.protection.password, () => EditCommands.protect_book (win.doc, null));
                return;
            }
            var dlg = Dialogs.make (win, _("Protect Workbook"), 440, 380);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Structure"), _("Sheets can't be added, deleted, renamed, moved or hidden while the workbook is protected."));
            var structure = new SwitchRow (_("Protect structure"), null, true);
            g.add_row (structure);
            box.append (g);
            var g2 = new PreferencesGroup (_("Password"));
            var pw = new PasswordRow (_("Password to unprotect"));
            var confirm = new PasswordRow (_("Confirm password"));
            g2.add_row (pw);
            g2.add_row (confirm);
            box.append (g2);
            Dialogs.footer (dlg, _("Protect"), () => {
                var hash = ask_new_password (win, pw, confirm);
                if (hash == null) return;
                var p = new BookProtection ();
                p.structure = structure.active;
                p.password = hash;
                EditCommands.protect_book (win.doc, p);
            });
            dlg.open_dialog ();
        }

        public static void edit_ranges (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            var dlg = Dialogs.make (win, _("Allow Edit Ranges"), 460, 480);
            var box = Dialogs.body (dlg);
            var list = new PreferencesGroup (_("Ranges"), _("Ranges unlocked by a password when the sheet is protected."));
            box.append (list);
            var current = new Gee.ArrayList<EditRange> ();
            if (s.protection != null) foreach (var er in s.protection.ranges) current.add (er.copy ());
            else if (pending_ranges ().has_key (s)) current.add_all (pending_ranges ()[s]);
            Dialogs.Apply refill = null;
            refill = () => {
                list.clear ();
                foreach (var er in current) {
                    var row = new ActionRow (er.title, Dialogs.area_text (er.area));
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    var target = er;
                    del.clicked.connect (() => {
                        current.remove (target);
                        refill ();
                    });
                    row.add_suffix (del);
                    list.add_row (row);
                }
                if (current.size == 0) list.add_row (new ActionRow (_("No ranges yet"), null));
            };
            refill ();
            var g = new PreferencesGroup (_("New Range"), _("Adds %s.").printf (Dialogs.area_text (sel)));
            var title = new EntryRow (_("Title"));
            title.text = _("Range%d").printf (current.size + 1);
            var pw = new PasswordRow (_("Range password"));
            g.add_row (title);
            g.add_row (pw);
            var add = new Button.with_label (_("Add Range"));
            add.halign = Align.END;
            add.clicked.connect (() => {
                var er = new EditRange (title.text.strip () != "" ? title.text.strip () : _("Range"), sel.copy ());
                er.password = PasswordHash.create (pw.text);
                current.add (er);
                pw.text = "";
                refill ();
            });
            box.append (g);
            box.append (add);
            Dialogs.footer (dlg, _("Apply"), () => {
                var p = s.protection != null ? s.protection.copy () : null;
                if (p == null) {
                    pending_ranges ()[s] = current;
                    message (win, _("Allow Edit Ranges"), _("The ranges take effect when the sheet is protected."));
                    return;
                }
                p.ranges.clear ();
                p.ranges.add_all (current);
                EditCommands.protect_sheet (win.doc, s, p);
            });
            dlg.open_dialog ();
        }

        private static Gee.HashMap<Sheet, Gee.ArrayList<EditRange>>? _pending;

        public static Gee.HashMap<Sheet, Gee.ArrayList<EditRange>> pending_ranges () {
            if (_pending == null) _pending = new Gee.HashMap<Sheet, Gee.ArrayList<EditRange>> ();
            return _pending;
        }

        public static void unlock_range (SpreadsheetWindow win, EditRange er, owned Dialogs.Apply then) {
            ask_password (win, _("Unlock Range"), er.password, () => {
                er.unlocked = true;
                then ();
            });
        }

        private static string[] kind_labels () {
            return { _("Any value"), _("Whole number"), _("Decimal"), _("List"), _("Date"), _("Time"), _("Text length"), _("Custom") };
        }

        private static string[] op_labels () {
            return { _("between"), _("not between"), _("equal to"), _("not equal to"), _("greater than"), _("less than"), _("greater than or equal to"), _("less than or equal to") };
        }

        private static string[] alert_labels () {
            return { _("Stop"), _("Warning"), _("Information") };
        }

        private static int index_of (string[] items, string v) {
            for (int i = 0; i < items.length; i++) if (items[i] == v) return i;
            return 0;
        }

        public static void validation (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            var existing = ValidationCheck.at (s, win.grid.cur_row, win.grid.cur_col);
            var v = existing != null ? existing.copy_to (sel) : new Validation (sel);
            if (existing == null) v.kind = ValidationKind.ANY;
            var dlg = Dialogs.make (win, _("Data Validation"), 480, 720);
            var box = Dialogs.body (dlg);
            string[] kinds = kind_labels ();
            string[] ops = op_labels ();
            var g = new PreferencesGroup (_("Settings"), _("Rule for %s").printf (Dialogs.area_text (sel)));
            var kind = new SelectionRow (_("Allow"), kinds, kinds[(int) v.kind]);
            var op = new SelectionRow (_("Data"), ops, ops[(int) v.op]);
            var v1 = new EntryRow (_("Minimum"));
            var v2 = new EntryRow (_("Maximum"));
            var source = new EntryRow (_("Source"));
            var formula = new EntryRow (_("Formula"));
            var blank = new SwitchRow (_("Ignore blank"), null, v.allow_blank);
            var dropdown = new SwitchRow (_("In-cell dropdown"), null, v.dropdown);
            string src_shown = v.list_source.has_prefix ("\"") && v.list_source.has_suffix ("\"") && v.list_source.length >= 2 ? v.list_source.substring (1, v.list_source.length - 2) : v.list_source;
            source.text = src_shown;
            v1.text = v.kind == ValidationKind.CUSTOM ? "" : v.formula1;
            v2.text = v.formula2;
            formula.text = v.kind == ValidationKind.CUSTOM ? (v.formula1.has_prefix ("=") ? v.formula1 : "=" + v.formula1) : "";
            g.add_row (kind);
            g.add_row (op);
            g.add_row (v1);
            g.add_row (v2);
            g.add_row (source);
            g.add_row (formula);
            g.add_row (blank);
            g.add_row (dropdown);
            box.append (g);
            var gi = new PreferencesGroup (_("Input Message"), _("Shown when a cell of the range is selected."));
            var show_in = new SwitchRow (_("Show input message"), null, v.show_input);
            var in_title = new EntryRow (_("Title"));
            in_title.text = v.input_title;
            var in_msg = new EntryRow (_("Input message"));
            in_msg.text = v.message;
            gi.add_row (show_in);
            gi.add_row (in_title);
            gi.add_row (in_msg);
            box.append (gi);
            var ge = new PreferencesGroup (_("Error Alert"), _("Shown when invalid data is entered."));
            var show_err = new SwitchRow (_("Show error alert"), null, v.show_error);
            string[] alerts = alert_labels ();
            var style = new SelectionRow (_("Style"), alerts, alerts[(int) v.alert]);
            var err_title = new EntryRow (_("Title"));
            err_title.text = v.error_title;
            var err_msg = new EntryRow (_("Error message"));
            err_msg.text = v.error_message;
            ge.add_row (show_err);
            ge.add_row (style);
            ge.add_row (err_title);
            ge.add_row (err_msg);
            box.append (ge);
            Dialogs.Apply sync = () => {
                int k = index_of (kinds, kind.current_value);
                int o = index_of (ops, op.current_value);
                bool numeric = k == 1 || k == 2 || k == 4 || k == 5 || k == 6;
                op.visible = numeric;
                bool two = o <= 1;
                v1.visible = numeric;
                v2.visible = numeric && two;
                v1.title = two ? _("Minimum") : _("Value");
                source.visible = k == 3;
                dropdown.visible = k == 3;
                formula.visible = k == 7;
                blank.visible = k != 0;
            };
            sync ();
            kind.selected.connect (() => sync ());
            op.selected.connect (() => sync ());
            Dialogs.footer (dlg, _("Apply"), () => {
                int k = index_of (kinds, kind.current_value);
                var nv = new Validation (sel);
                nv.kind = (ValidationKind) k;
                nv.op = (ValidationOp) index_of (ops, op.current_value);
                nv.allow_blank = blank.active;
                nv.dropdown = dropdown.active;
                nv.show_input = show_in.active;
                nv.input_title = in_title.text;
                nv.message = in_msg.text;
                nv.show_error = show_err.active;
                nv.alert = (ValidationAlert) index_of (alerts, style.current_value);
                nv.error_title = err_title.text;
                nv.error_message = err_msg.text;
                if (nv.kind == ValidationKind.LIST) {
                    string t = source.text.strip ();
                    if (t == "") return;
                    bool is_ref = t.has_prefix ("=") || t.contains ("!") || Area.parse (t.replace ("$", ""), s) != null;
                    nv.list_source = is_ref ? (t.has_prefix ("=") ? t.substring (1) : t) : "\"" + t + "\"";
                    nv.formula1 = nv.list_source;
                } else if (nv.kind == ValidationKind.CUSTOM) {
                    string f = formula.text.strip ();
                    nv.formula1 = f.has_prefix ("=") ? f.substring (1) : f;
                } else {
                    nv.formula1 = v1.text.strip ();
                    nv.formula2 = v2.text.strip ();
                }
                EditCommands.set_validation (win.doc, s, sel, nv);
                win.grid.queue_draw ();
            }, _("Clear All"), () => {
                EditCommands.set_validation (win.doc, s, sel, null);
                win.grid.queue_draw ();
            });
            dlg.open_dialog ();
        }

        public static void rejected (SpreadsheetWindow win, int row, int col, string text, Validation rule) {
            string title = rule.error_title != "" ? rule.error_title : _("Spreadsheet");
            string body = rule.error_message != "" ? rule.error_message : ValidationCheck.default_error (rule);
            ConfirmDialog dlg;
            switch (rule.alert) {
                case ValidationAlert.WARNING:
                    dlg = new ConfirmDialog ((Gtk.Application) win.application, title, "dialog-warning", body + "\n\n" + _("Continue?"), _("Yes"), ConfirmDialog.ActionStyle.SUGGESTED);
                    dlg.set_secondary (_("No"));
                    break;
                case ValidationAlert.INFORMATION:
                    dlg = new ConfirmDialog ((Gtk.Application) win.application, title, "dialog-information", body, _("OK"), ConfirmDialog.ActionStyle.SUGGESTED);
                    break;
                default:
                    dlg = new ConfirmDialog ((Gtk.Application) win.application, title, "dialog-error", body, _("Retry"), ConfirmDialog.ActionStyle.SUGGESTED);
                    break;
            }
            var alert = rule.alert;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) {
                    if (alert == ValidationAlert.STOP) win.grid.retry_rejected ();
                    else win.grid.accept_rejected ();
                } else if (r == ConfirmDialog.Response.SECONDARY) {
                    win.grid.retry_rejected ();
                } else {
                    win.grid.cancel_edit ();
                }
            });
            dlg.transient_for = win;
            dlg.present ();
        }

        public static void text_to_columns (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            if (sel.r2 > s.max_row) sel.r2 = int.max (s.max_row, sel.r1);
            if (sel.cols > 1) {
                message (win, _("Text to Columns"), _("Select a single column of data to split."), "dialog-warning");
                return;
            }
            var dlg = Dialogs.make (win, _("Text to Columns"), 520, 720);
            var box = Dialogs.body (dlg);
            string[] modes = { _("Delimited"), _("Fixed width") };
            var g = new PreferencesGroup (_("Data"), _("Splits %s into several columns.").printf (Dialogs.area_text (sel)));
            string sample = s.value_at (sel.r1, sel.c1).display ();
            bool guess_comma = sample.contains (",");
            bool guess_semi = sample.contains (";");
            bool guess_tab = sample.contains ("\t");
            bool guess_space = !guess_comma && !guess_semi && !guess_tab;
            var mode = new SelectionRow (_("Original data type"), modes, modes[0]);
            g.add_row (mode);
            box.append (g);
            var gd = new PreferencesGroup (_("Delimiters"));
            var tab = new SwitchRow (_("Tab"), null, guess_tab);
            var semi = new SwitchRow (_("Semicolon"), null, guess_semi);
            var comma = new SwitchRow (_("Comma"), null, guess_comma);
            var space = new SwitchRow (_("Space"), null, guess_space);
            var other = new EntryRow (_("Other"));
            var consecutive = new SwitchRow (_("Treat consecutive delimiters as one"), null, false);
            string[] quals = { "\"", "'", _("None") };
            var qual = new SelectionRow (_("Text qualifier"), quals, quals[0]);
            gd.add_row (tab);
            gd.add_row (semi);
            gd.add_row (comma);
            gd.add_row (space);
            gd.add_row (other);
            gd.add_row (consecutive);
            gd.add_row (qual);
            box.append (gd);
            var gf = new PreferencesGroup (_("Column Breaks"), _("Character positions where the text is cut, separated by commas."));
            var breaks = new EntryRow (_("Break positions"));
            gf.add_row (breaks);
            box.append (gf);
            var gc = new PreferencesGroup (_("Column Data Format"));
            box.append (gc);
            var gdst = new PreferencesGroup (_("Destination"));
            var dest = new EntryRow (_("Destination"));
            dest.text = Address.cell (sel.r1, sel.c1, true, true);
            gdst.add_row (dest);
            box.append (gdst);
            var preview = new Label ("");
            preview.xalign = 0;
            preview.selectable = true;
            preview.add_css_class ("monospace");
            preview.wrap = true;
            box.append (preview);
            string[] fmts = { _("General"), _("Text"), _("Date (DMY)"), _("Date (MDY)"), _("Date (YMD)"), _("Do not import") };
            var fmt_rows = new Gee.ArrayList<SelectionRow> ();
            SplitOptions opts = new SplitOptions ();
            Dialogs.Apply build = () => {
                opts = new SplitOptions ();
                opts.fixed_width = mode.current_value == modes[1];
                opts.tab = tab.active;
                opts.semicolon = semi.active;
                opts.comma = comma.active;
                opts.space = space.active;
                opts.other = other.text;
                opts.consecutive = consecutive.active;
                opts.qualifier = qual.current_value == quals[0] ? '"' : (qual.current_value == quals[1] ? '\'' : (char) 0);
                int[] bk = {};
                foreach (string p in breaks.text.split (",")) if (p.strip () != "") bk += int.parse (p.strip ());
                opts.breaks = bk;
                for (int i = 0; i < fmt_rows.size; i++) opts.formats[i] = (ColumnFormat) index_of (fmts, fmt_rows[i].current_value);
            };
            Dialogs.Apply refresh = null;
            refresh = () => {
                build ();
                gd.visible = !opts.fixed_width;
                gf.visible = opts.fixed_width;
                var sb = new StringBuilder ();
                int width = 0;
                for (int r = sel.r1; r <= int.min (sel.r2, sel.r1 + 5); r++) {
                    var parts = TextToColumns.split (s.value_at (r, sel.c1).display (), opts);
                    width = int.max (width, parts.size);
                    sb.append (string.joinv (" | ", parts.to_array ()));
                    sb.append ("\n");
                }
                preview.label = sb.str;
                if (fmt_rows.size != int.min (width, 12)) {
                    gc.clear ();
                    fmt_rows.clear ();
                    for (int i = 0; i < int.min (width, 12); i++) {
                        var fr = new SelectionRow (_("Column %d").printf (i + 1), fmts, fmts[0]);
                        fmt_rows.add (fr);
                        gc.add_row (fr);
                    }
                }
            };
            refresh ();
            mode.selected.connect (() => refresh ());
            foreach (var sw in new SwitchRow[] { tab, semi, comma, space, consecutive }) sw.switch_btn.notify["active"].connect (() => refresh ());
            other.entry_changed.connect (() => refresh ());
            breaks.entry_changed.connect (() => refresh ());
            qual.selected.connect (() => refresh ());
            Dialogs.footer (dlg, _("Finish"), () => {
                build ();
                int dr = sel.r1, dc = sel.c1;
                bool a, b;
                Address.parse_cell (dest.text.strip ().replace ("$", ""), out dr, out dc, out a, out b);
                if (dr < 0 || dc < 0) {
                    dr = sel.r1;
                    dc = sel.c1;
                }
                TextToColumns.apply (win.doc, s, sel, opts, dr, dc);
            });
            dlg.open_dialog ();
        }

        public static void cell_styles (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            var dlg = Dialogs.make (win, _("Cell Styles"), 620, 640);
            var box = Dialogs.body (dlg);
            var styles = NamedStyle.gallery (win.doc.book.theme);
            string cat = "";
            FlowBox? flow = null;
            foreach (var ns in styles) {
                if (ns.category != cat) {
                    cat = ns.category;
                    var head = new Label (cat);
                    head.xalign = 0;
                    head.add_css_class ("heading");
                    box.append (head);
                    flow = new FlowBox ();
                    flow.selection_mode = SelectionMode.NONE;
                    flow.max_children_per_line = 6;
                    flow.min_children_per_line = 3;
                    flow.column_spacing = 6;
                    flow.row_spacing = 6;
                    box.append (flow);
                }
                var preview = new CellStyle ();
                ns.apply (preview, win.doc.book.theme);
                var b = new Button.with_label (ns.name);
                b.add_css_class ("ss-cell-style");
                var css = new CssProvider ();
                var sb = new StringBuilder ("button.ss-cell-style { border-radius: 4px; min-height: 30px; padding: 2px 8px; ");
                sb.append ("background: %s; ".printf (preview.fill != "" ? preview.fill : "#ffffff"));
                sb.append ("color: %s; ".printf (preview.color != "" ? preview.color : "#1e1f22"));
                if (preview.bold) sb.append ("font-weight: bold; ");
                if (preview.italic) sb.append ("font-style: italic; ");
                if (preview.bottom.style != BorderStyle.NONE) sb.append ("border-bottom: %dpx solid %s; ".printf (preview.bottom.style == BorderStyle.THICK ? 3 : (preview.bottom.style == BorderStyle.MEDIUM ? 2 : 1), preview.bottom.color != "" ? preview.bottom.color : "#000"));
                if (preview.left.style != BorderStyle.NONE) sb.append ("border: 1px solid %s; ".printf (preview.left.color != "" ? preview.left.color : "#000"));
                sb.append ("}");
                css.load_from_string (sb.str);
                b.get_style_context ().add_provider (css, STYLE_PROVIDER_PRIORITY_USER + 5);
                var chosen = ns;
                b.clicked.connect (() => {
                    EditCommands.apply_named_style (win.doc, s, sel, chosen);
                    dlg.close_dialog ();
                });
                flow.append (b);
            }
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.halign = Align.END;
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dlg.close_dialog ());
            dlg.set_cancel_button (cancel);
            bar.append (cancel);
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        public static void themes (SpreadsheetWindow win) {
            var dlg = Dialogs.make (win, _("Themes"), 460, 560);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Document Theme"), _("Theme colors and fonts used by the cell styles and palette."));
            foreach (var t in DocTheme.builtin ()) {
                var row = new ActionRow (t.name, "%s, %s".printf (t.major_font, t.minor_font));
                var swatches = new Box (Orientation.HORIZONTAL, 2);
                swatches.valign = Align.CENTER;
                for (int i = 4; i < 10; i++) {
                    var sw = new DrawingArea ();
                    sw.set_size_request (14, 14);
                    string col = t.colors[i];
                    sw.set_draw_func ((area, cr, w, h) => {
                        cr.set_source_rgb (Xlsx.hex2 (col, 1) / 255.0, Xlsx.hex2 (col, 3) / 255.0, Xlsx.hex2 (col, 5) / 255.0);
                        cr.rectangle (0, 0, w, h);
                        cr.fill ();
                    });
                    swatches.append (sw);
                }
                row.add_suffix (swatches);
                if (t.name == win.doc.book.theme.name) row.add_suffix (new Image.from_icon_name ("object-select-symbolic"));
                row.activatable = true;
                var chosen = t;
                row.activated.connect (() => {
                    EditCommands.set_theme (win.doc, chosen);
                    win.grid.refresh ();
                    dlg.close_dialog ();
                });
                g.add_row (row);
            }
            box.append (g);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.halign = Align.END;
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dlg.close_dialog ());
            dlg.set_cancel_button (cancel);
            bar.append (cancel);
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        public static void custom_views (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var dlg = Dialogs.make (win, _("Custom Views"), 440, 480);
            var box = Dialogs.body (dlg);
            var list = new PreferencesGroup (_("Views"), _("A view remembers hidden rows and columns, filters, frozen panes and zoom."));
            foreach (var v in s.views) {
                var row = new ActionRow (v.name, "%d%%".printf ((int) Math.round (v.zoom * 100)));
                var show = new Button.with_label (_("Show"));
                show.valign = Align.CENTER;
                var target = v;
                show.clicked.connect (() => {
                    EditCommands.show_view (win.doc, s, target);
                    win.grid.zoom_to (target.zoom);
                    win.grid.refresh ();
                    win.grid.select_cell (target.row, target.col, false);
                    dlg.close_dialog ();
                });
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.clicked.connect (() => {
                    EditCommands.delete_view (win.doc, s, target);
                    dlg.close_dialog ();
                });
                row.add_suffix (show);
                row.add_suffix (del);
                list.add_row (row);
            }
            if (s.views.size == 0) list.add_row (new ActionRow (_("No views yet"), null));
            box.append (list);
            var g = new PreferencesGroup (_("Add View"));
            var name = new EntryRow (_("Name"));
            g.add_row (name);
            box.append (g);
            Dialogs.footer (dlg, _("Add"), () => {
                string n = name.text.strip ();
                if (n == "") return;
                EditCommands.save_view (win.doc, s, CustomView.capture (s, n, win.grid.zoom, win.grid.cur_row, win.grid.cur_col));
            });
            dlg.open_dialog ();
        }

        public static void goto_special (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var dlg = Dialogs.make (win, _("Go To Special"), 420, 360);
            var box = Dialogs.body (dlg);
            string[] labels = { _("Blanks"), _("Constants"), _("Formulas"), _("Errors"), _("Notes"), _("Visible cells only"), _("Current region"), _("Last cell"), _("Data validation"), _("Conditional formats") };
            var g = new PreferencesGroup (_("Select"));
            var kind = new SelectionRow (_("Cells"), labels, labels[0]);
            g.add_row (kind);
            box.append (g);
            Dialogs.footer (dlg, _("Select"), () => {
                var k = (SpecialKind) index_of (labels, kind.current_value);
                var found = GoToSpecial.find (win.doc, s, win.grid.selection, k, win.grid.cur_row, win.grid.cur_col);
                if (found.size == 0) {
                    message (win, _("Go To Special"), _("No cells were found."));
                    return;
                }
                win.grid.set_areas (found);
            });
            dlg.open_dialog ();
        }

        public static void paste_special (SpreadsheetWindow win) {
            if (win.doc.clip == null) {
                message (win, _("Paste Special"), _("Copy cells first."));
                return;
            }
            var dlg = Dialogs.make (win, _("Paste Special"), 440, 520);
            var box = Dialogs.body (dlg);
            string[] what = { _("All"), _("Values"), _("Formats"), _("Values and formats"), _("Column widths"), _("Link to source") };
            string[] ops = { _("None"), _("Add"), _("Subtract"), _("Multiply"), _("Divide") };
            var g = new PreferencesGroup (_("Paste"));
            var paste = new SelectionRow (_("Paste"), what, what[0]);
            var op = new SelectionRow (_("Operation"), ops, ops[0]);
            var skip = new SwitchRow (_("Skip blanks"), null, false);
            var transpose = new SwitchRow (_("Transpose"), null, false);
            g.add_row (paste);
            g.add_row (op);
            g.add_row (skip);
            g.add_row (transpose);
            box.append (g);
            Dialogs.footer (dlg, _("Paste"), () => {
                int w = index_of (what, paste.current_value);
                var o = (PasteOp) index_of (ops, op.current_value);
                var s = win.grid.sheet;
                int r = win.grid.selection.r1, c = win.grid.selection.c1;
                Area? dest;
                if (w == 0 && o == PasteOp.NONE && !skip.active) {
                    dest = win.doc.paste (s, r, c, transpose.active ? Document.PasteMode.TRANSPOSE : Document.PasteMode.ALL, win.grid.selection);
                } else {
                    bool values = w == 0 || w == 1 || w == 3;
                    bool formats = w == 0 || w == 2 || w == 3;
                    dest = EditCommands.paste_special (win.doc, s, r, c, values, formats, o, skip.active, transpose.active, w == 5, w == 4);
                }
                if (dest != null) win.grid.select_area (dest);
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }

        public static void group (SpreadsheetWindow win, bool ungroup) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            bool whole_rows = sel.c1 == 0 && sel.c2 == MAX_COLS - 1;
            bool whole_cols = sel.r1 == 0 && sel.r2 == MAX_ROWS - 1;
            if (whole_rows || whole_cols) {
                if (whole_rows) EditCommands.group (win.doc, s, true, sel.r1, sel.r2, ungroup);
                else EditCommands.group (win.doc, s, false, sel.c1, sel.c2, ungroup);
                win.grid.refresh ();
                return;
            }
            var dlg = Dialogs.make (win, ungroup ? _("Ungroup") : _("Group"), 380, 240);
            var box = Dialogs.body (dlg);
            string[] items = { _("Rows"), _("Columns") };
            var g = new PreferencesGroup ();
            var which = new SelectionRow (ungroup ? _("Ungroup") : _("Group"), items, sel.rows >= sel.cols ? items[0] : items[1]);
            g.add_row (which);
            box.append (g);
            Dialogs.footer (dlg, _("Apply"), () => {
                bool rows = which.current_value == items[0];
                if (rows) EditCommands.group (win.doc, s, true, sel.r1, sel.r2, ungroup);
                else EditCommands.group (win.doc, s, false, sel.c1, sel.c2, ungroup);
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }

        public static void open_encrypted (SpreadsheetWindow win, File file) {
            var dlg = Dialogs.make (win, _("Password"), 420, 240);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (null, _("\"%s\" is protected.").printf (file.get_basename ()));
            var pw = new PasswordRow (_("Password"));
            g.add_row (pw);
            box.append (g);
            Dialogs.footer (dlg, _("Open"), () => {
                try {
                    var d = Document.open_with_password (file.get_path (), pw.text);
                    win.load_document (d);
                    RecentManager.get_default ().add_item (file.get_uri ());
                } catch (Error e) {
                    if (e is CryptoError.WRONG_PASSWORD) message (win, _("Wrong Password"), _("The password you supplied is not correct."), "dialog-error");
                    else win.show_error (_("Could Not Open"), _("\"%s\" could not be opened: %s").printf (file.get_basename (), e.message));
                }
            });
            dlg.open_dialog ();
            pw.grab_focus ();
        }

        public static void encrypt (SpreadsheetWindow win) {
            var doc = win.doc;
            var dlg = Dialogs.make (win, _("Encrypt with Password"), 440, 320);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Password"), _("The Excel file is encrypted when it is saved. A lost password can't be recovered. Leave both fields empty to remove the encryption."));
            var pw = new PasswordRow (_("Password"));
            var confirm = new PasswordRow (_("Confirm password"));
            g.add_row (pw);
            g.add_row (confirm);
            box.append (g);
            Dialogs.footer (dlg, _("Apply"), () => {
                if (pw.text != confirm.text) {
                    message (win, _("Passwords Don't Match"), _("The confirmation password is not identical. Type the same password in both fields."), "dialog-warning");
                    return;
                }
                doc.encrypt_password = pw.text != "" ? pw.text : null;
                doc.modified = true;
            });
            dlg.open_dialog ();
        }

        private class SortLevelRows {
            public PreferencesGroup group;
            public SelectionRow key;
            public SelectionRow on;
            public SelectionRow order;
            public SelectionRow color;
        }

        public static void sort_advanced (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            var area = sel.is_single () ? win.doc.current_region (s, sel.r1, sel.c1) : Document.clamp_area (s, sel);
            if (area.r2 > s.max_row) area.r2 = int.max (s.max_row, area.r1);
            if (area.c2 > s.max_col) area.c2 = int.max (s.max_col, area.c1);
            var dlg = Dialogs.make (win, _("Sort"), 520, 700);
            var box = Dialogs.body (dlg);
            var g0 = new PreferencesGroup (_("Options"), _("Sorting %s").printf (Dialogs.area_text (area)));
            bool guess = s.value_at (area.r1, area.c1).kind == ValueKind.TEXT && area.rows > 1 && s.value_at (area.r1 + 1, area.c1).kind != ValueKind.TEXT;
            if (s.style_at (area.r1, area.c1).bold) guess = true;
            var header = new SwitchRow (_("My data has headers"), null, guess);
            string[] dirs = { _("Top to bottom"), _("Left to right") };
            var dir = new SelectionRow (_("Orientation"), dirs, dirs[0]);
            var cs = new SwitchRow (_("Case sensitive"), null, false);
            g0.add_row (header);
            g0.add_row (dir);
            g0.add_row (cs);
            box.append (g0);
            var levels_box = new Box (Orientation.VERTICAL, 14);
            box.append (levels_box);
            var levels = new Gee.ArrayList<SortLevelRows> ();
            string[] ons = { _("Cell Values"), _("Cell Color"), _("Font Color"), _("Conditional Formatting Icon") };
            Dialogs.Apply rebuild_keys = null;
            string[] key_labels () {
                string[] out_l = {};
                bool cols = dir.current_value == dirs[1];
                if (!cols) {
                    for (int c = area.c1; c <= area.c2 && c <= area.c1 + 500; c++) {
                        string l = _("Column %s").printf (Address.column_name (c));
                        if (header.active) {
                            string h = s.value_at (area.r1, c).display ();
                            if (h != "") l = h;
                        }
                        out_l += l;
                    }
                } else {
                    for (int r = area.r1; r <= area.r2 && r <= area.r1 + 500; r++) {
                        string l = _("Row %d").printf (r + 1);
                        if (header.active) {
                            string h = s.value_at (r, area.c1).display ();
                            if (h != "") l = h;
                        }
                        out_l += l;
                    }
                }
                return out_l;
            }
            string[] order_labels (int on, int key_index) {
                if (on == 0) {
                    string[] o = { _("A to Z"), _("Z to A") };
                    foreach (string l in CustomLists.all (win.doc.book)) o += l.replace ("|", ", ");
                    return o;
                }
                return { _("On Top"), _("On Bottom") };
            }
            string[] color_labels (int on, int idx) {
                var fills = new Gee.TreeSet<string> ();
                var fonts = new Gee.TreeSet<string> ();
                var icons = new Gee.TreeMap<string, int> ();
                bool cols = dir.current_value == dirs[1];
                if (!cols) FilterUi.colors_in_area (win, area, area.c1 + idx, fills, fonts, icons);
                string[] out_l = {};
                if (on == 1) foreach (string c in fills) out_l += c;
                else if (on == 2) foreach (string c in fonts) out_l += c;
                else if (on == 3) foreach (var e in icons.keys) out_l += e;
                if (out_l.length == 0) out_l += _("(none)");
                return out_l;
            }
            Dialogs.Apply add_level = () => {
                if (levels.size >= MAX_SORT_LEVELS) return;
                var lr = new SortLevelRows ();
                string[] keys = key_labels ();
                lr.group = new PreferencesGroup (levels.size == 0 ? _("Sort by") : _("Then by"));
                int start = int.min (levels.size == 0 ? (win.grid.cur_col - area.c1).clamp (0, keys.length - 1) : 0, keys.length - 1);
                lr.key = new SelectionRow (dir.current_value == dirs[1] ? _("Row") : _("Column"), keys, keys[start]);
                lr.on = new SelectionRow (_("Sort On"), ons, ons[0]);
                lr.order = new SelectionRow (_("Order"), order_labels (0, 0), order_labels (0, 0)[0]);
                lr.color = new SelectionRow (_("Color"), { _("(none)") }, _("(none)"));
                lr.color.visible = false;
                lr.group.add_row (lr.key);
                lr.group.add_row (lr.on);
                lr.group.add_row (lr.color);
                lr.group.add_row (lr.order);
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.tooltip_text = _("Delete Level");
                var me = lr;
                del.clicked.connect (() => {
                    if (levels.size <= 1) return;
                    levels.remove (me);
                    levels_box.remove (me.group);
                });
                lr.group.add_header_suffix (del);
                Dialogs.Apply refresh = () => {
                    int on = index_of (ons, me.on.current_value);
                    int ki = index_of (key_labels (), me.key.current_value);
                    string[] ol = order_labels (on, ki);
                    me.order.set_items (ol);
                    me.color.visible = on > 0;
                    if (on > 0) me.color.set_items (color_labels (on, ki));
                };
                lr.on.selected.connect (() => refresh ());
                lr.key.selected.connect (() => refresh ());
                levels.add (lr);
                levels_box.append (lr.group);
            };
            add_level ();
            rebuild_keys = () => {
                string[] keys = key_labels ();
                foreach (var lr in levels) {
                    lr.key.set_items (keys);
                    lr.key.title = dir.current_value == dirs[1] ? _("Row") : _("Column");
                }
            };
            header.switch_btn.notify["active"].connect (() => rebuild_keys ());
            dir.selected.connect (() => rebuild_keys ());
            var add = new Button.with_label (_("Add Level"));
            add.halign = Align.START;
            add.clicked.connect (() => add_level ());
            box.append (add);
            Dialogs.footer (dlg, _("Sort"), () => {
                var spec = new SortSpec (area.copy ());
                spec.header = header.active;
                spec.columns = dir.current_value == dirs[1];
                spec.case_sensitive = cs.active;
                string[] keys = key_labels ();
                foreach (var lr in levels) {
                    int ki = index_of (keys, lr.key.current_value);
                    int idx = (spec.columns ? area.r1 : area.c1) + ki;
                    int on = index_of (ons, lr.on.current_value);
                    string[] ol = order_labels (on, ki);
                    int oi = index_of (ol, lr.order.current_value);
                    var lv = new SortLevel (idx, oi != 1);
                    lv.by = (SortBy) on;
                    if (on == 0 && oi >= 2) {
                        var lists = CustomLists.all (win.doc.book);
                        lv.custom_list = lists[oi - 2];
                        lv.ascending = true;
                    }
                    if (on == 1 || on == 2) lv.color = lr.color.current_value;
                    if (on == 3) {
                        string v = lr.color.current_value;
                        int colon = v.last_index_of (":");
                        if (colon > 0) {
                            lv.icon_set = v.substring (0, colon);
                            lv.icon = int.parse (v.substring (colon + 1));
                        }
                    }
                    spec.levels.add (lv);
                }
                SortEngine.sort (win.doc, s, spec);
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }

        public static void fill_series (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            var dlg = Dialogs.make (win, _("Series"), 460, 560);
            var box = Dialogs.body (dlg);
            string[] ins = { _("Columns"), _("Rows") };
            string[] types = { _("Linear"), _("Growth"), _("Date"), _("AutoFill") };
            string[] units = { _("Day"), _("Weekday"), _("Month"), _("Year") };
            var g = new PreferencesGroup (null, _("Fills %s from its first values.").printf (Dialogs.area_text (sel)));
            var inr = new SelectionRow (_("Series in"), ins, sel.cols > sel.rows ? ins[1] : ins[0]);
            var type = new SelectionRow (_("Type"), types, types[0]);
            var unit = new SelectionRow (_("Date unit"), units, units[0]);
            var step = new EntryRow (_("Step value"));
            step.text = "1";
            var stop = new EntryRow (_("Stop value"));
            var trend = new SwitchRow (_("Trend"), _("Fits a best line or curve to the selected values"), false);
            g.add_row (inr);
            g.add_row (type);
            g.add_row (unit);
            g.add_row (step);
            g.add_row (stop);
            g.add_row (trend);
            box.append (g);
            unit.visible = false;
            type.selected.connect ((x) => unit.visible = x == types[2]);
            Dialogs.footer (dlg, _("Fill"), () => {
                bool rows = inr.current_value == ins[1];
                var t = (SeriesType) index_of (types, type.current_value);
                if (t == SeriesType.AUTOFILL) {
                    if (rows) win.doc.fill_series (s, new Area (s, sel.r1, sel.c1, sel.r2, sel.c1), sel);
                    else win.doc.fill_series (s, new Area (s, sel.r1, sel.c1, sel.r1, sel.c2), sel);
                    return;
                }
                double st = 1, sp = 0;
                string fmt;
                if (!Input.parse_number (step.text.strip (), out st, out fmt)) st = 1;
                double? stop_v = null;
                if (stop.text.strip () != "") {
                    if (Input.parse_number (stop.text.strip (), out sp, out fmt) || Input.parse_date_time (stop.text.strip (), out sp, out fmt)) stop_v = sp;
                }
                SeriesFill.fill (win.doc, s, sel, rows, t, (DateUnit) index_of (units, unit.current_value), st, stop_v, trend.active);
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }

        public static void custom_lists (SpreadsheetWindow win) {
            var book = win.doc.book;
            var dlg = Dialogs.make (win, _("Custom Lists"), 480, 600);
            var box = Dialogs.body (dlg);
            var builtin = new PreferencesGroup (_("Built-in Lists"), _("Used by the fill handle and by sorting."));
            foreach (string l in CustomLists.builtin ()) builtin.add_row (new ActionRow (l.replace ("|", ", "), null));
            box.append (builtin);
            var yours = new PreferencesGroup (_("Your Lists"), _("Available in every workbook, also editable in Settings."));
            box.append (yours);
            var mine = new PreferencesGroup (_("Lists in This Workbook"), _("Saved with the file."));
            box.append (mine);
            var user_lists = new Gee.ArrayList<string> ();
            user_lists.add_all (CustomLists.user ());
            var current = new Gee.ArrayList<string> ();
            current.add_all (book.custom_lists);
            Dialogs.Apply refill = null;
            refill = () => {
                mine.clear ();
                yours.clear ();
                Gee.ArrayList<string>[] sets = { user_lists, current };
                PreferencesGroup[] groups = { yours, mine };
                for (int gi = 0; gi < 2; gi++) {
                    var set = sets[gi];
                    foreach (string l in set) {
                        var r = new ActionRow (l.replace ("|", ", "), null);
                        var del = new Button.from_icon_name ("user-trash-symbolic");
                        del.add_css_class ("flat");
                        del.valign = Align.CENTER;
                        string target = l;
                        del.clicked.connect (() => {
                            set.remove (target);
                            refill ();
                        });
                        r.add_suffix (del);
                        groups[gi].add_row (r);
                    }
                    if (set.size == 0) groups[gi].add_row (new ActionRow (_("No lists yet"), null));
                }
            };
            refill ();
            string[] targets = { _("Your lists"), _("This workbook") };
            var where = new SelectionRow (_("Add to"), targets, targets[0]);
            var g = new PreferencesGroup (_("New List"), _("Type the entries separated by commas, or import them from the selected cells."));
            var entries = new EntryRow (_("Entries"));
            g.add_row (where);
            g.add_row (entries);
            box.append (g);
            var buttons = new Box (Orientation.HORIZONTAL, 8);
            var add = new Button.with_label (_("Add"));
            add.clicked.connect (() => {
                string l = CustomLists.normalize (entries.text);
                var dest = where.current_value == targets[0] ? user_lists : current;
                if (l != "" && !dest.contains (l)) dest.add (l);
                entries.text = "";
                refill ();
            });
            var import = new Button.with_label (_("Import from Selection"));
            import.clicked.connect (() => {
                var s = win.grid.sheet;
                var a = Document.clamp_area (s, win.grid.selection);
                string[] items = {};
                for (int r = a.r1; r <= int.min (a.r2, int.max (s.max_row, a.r1)); r++) {
                    for (int c = a.c1; c <= int.min (a.c2, int.max (s.max_col, a.c1)); c++) {
                        string t = s.value_at (r, c).display ();
                        if (t != "") items += t;
                    }
                }
                string l = CustomLists.normalize (string.joinv (",", items));
                var dest = where.current_value == targets[0] ? user_lists : current;
                if (l != "" && !dest.contains (l)) dest.add (l);
                refill ();
            });
            buttons.append (add);
            buttons.append (import);
            box.append (buttons);
            Dialogs.footer (dlg, _("Save"), () => {
                EditCommands.set_custom_lists (win.doc, current);
                EditActions.save_user_lists (user_lists);
            });
            dlg.open_dialog ();
        }

        public static void outline_settings (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var dlg = Dialogs.make (win, _("Outline Settings"), 400, 280);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Direction"));
            var below = new SwitchRow (_("Summary rows below detail"), null, s.outline.summary_below);
            var right = new SwitchRow (_("Summary columns right of detail"), null, s.outline.summary_right);
            g.add_row (below);
            g.add_row (right);
            box.append (g);
            Dialogs.footer (dlg, _("Apply"), () => {
                EditCommands.set_summary (win.doc, s, below.active, right.active);
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }
    }
}
