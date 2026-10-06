using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class Dialogs {
        public delegate void Apply ();

        public static AppDialog make (SpreadsheetWindow win, string title, int width, int height) {
            var dlg = new AppDialog ((Gtk.Application) win.application, true);
            dlg.set_title (title);
            dlg.transient_for = win;
            dlg.set_default_size (width, height);
            dlg.add_css_class ("ss-dialog");
            return dlg;
        }

        public static Box body (AppDialog dlg) {
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            var box = new Box (Orientation.VERTICAL, 14);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 12;
            scroll.child = box;
            dlg.content_box.append (scroll);
            return box;
        }

        public static void footer (AppDialog dlg, string label, owned Apply apply, string? extra = null, owned Apply? extra_apply = null) {
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.add_css_class ("ss-dialog-footer");
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            if (extra != null) {
                var e = new Button.with_label (extra);
                e.add_css_class ("destructive-action");
                e.clicked.connect (() => {
                    extra_apply ();
                    dlg.close ();
                });
                bar.append (e);
            }
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (cancel);
            var ok = new Button.with_label (label);
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                apply ();
                dlg.close ();
            });
            bar.append (cancel);
            bar.append (ok);
            dlg.content_box.append (bar);
            dlg.default_widget = ok;
        }

        public static string area_text (Area a) {
            if (a.is_single ()) return Address.cell (a.r1, a.c1);
            return Address.cell (a.r1, a.c1) + ":" + Address.cell (a.r2, a.c2);
        }

        public static string currency_format (int decimals) {
            string dec = decimals > 0 ? "." + string.nfill (decimals, '0') : "";
            if (LocaleInfo.get ().decimal_sep == ',') return "#,##0" + dec + " \"€\"";
            return "$#,##0" + dec;
        }

        public static void size (SpreadsheetWindow win, bool rows) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            var dlg = make (win, rows ? _("Row Height") : _("Column Width"), 380, 240);
            var box = body (dlg);
            var group = new PreferencesGroup ();
            double current = rows ? s.row_height (sel.r1) : s.col_width (sel.c1);
            var spin = new SpinRow (rows ? _("Height in pixels") : _("Width in pixels"), null, 4, 1200, 1, current);
            group.add_row (spin);
            box.append (group);
            footer (dlg, _("Apply"), () => {
                int v = (int) spin.value;
                if (rows) win.doc.set_row_height (s, sel.r1, sel.r2 == MAX_ROWS - 1 ? sel.r1 : sel.r2, v);
                else win.doc.set_col_width (s, sel.c1, sel.c2 == MAX_COLS - 1 ? sel.c1 : sel.c2, v);
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }

        public static void note (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            int r = win.grid.cur_row, c = win.grid.cur_col;
            var cell = s.get_cell (r, c);
            var dlg = make (win, _("Note for %s").printf (Address.cell (r, c)), 420, 320);
            var box = body (dlg);
            var view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.add_css_class ("ss-note-view");
            view.vexpand = true;
            view.buffer.text = cell != null ? cell.note : "";
            var frame = new ScrolledWindow ();
            frame.add_css_class ("ss-note-frame");
            frame.vexpand = true;
            frame.child = view;
            box.append (frame);
            bool has = cell != null && cell.note != "";
            if (has) {
                footer (dlg, _("Save"), () => win.doc.set_note (s, r, c, view.buffer.text.strip ()), _("Delete Note"), () => win.doc.set_note (s, r, c, ""));
            } else {
                footer (dlg, _("Save"), () => win.doc.set_note (s, r, c, view.buffer.text.strip ()));
            }
            dlg.open_dialog ();
            view.grab_focus ();
        }

        private static string[] column_labels (Sheet s, Area a, bool header) {
            string[] out_l = {};
            for (int c = a.c1; c <= a.c2 && c <= a.c1 + 200; c++) {
                string label = _("Column %s").printf (Address.column_name (c));
                if (header) {
                    string h = s.value_at (a.r1, c).display ();
                    if (h != "") label = h;
                }
                out_l += label;
            }
            return out_l;
        }

        public static void sort (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            var area = sel.is_single () ? win.doc.current_region (s, sel.r1, sel.c1) : Document.clamp_area (s, sel);
            if (area.r2 > s.max_row) area.r2 = int.max (s.max_row, area.r1);
            var dlg = make (win, _("Sort"), 460, 480);
            var box = body (dlg);
            var g0 = new PreferencesGroup (_("Range"), _("Sorting %s").printf (area_text (area)));
            bool guess = s.value_at (area.r1, area.c1).kind == ValueKind.TEXT && area.rows > 1 && s.value_at (area.r1 + 1, area.c1).kind != ValueKind.TEXT;
            if (s.style_at (area.r1, area.c1).bold) guess = true;
            var header = new SwitchRow (_("First row is a header"), null, guess);
            g0.add_row (header);
            box.append (g0);
            var levels = new Gee.ArrayList<SelectionRow> ();
            var orders = new Gee.ArrayList<SelectionRow> ();
            string[] order_items = { _("A to Z"), _("Z to A") };
            string[] labels = column_labels (s, area, header.active);
            string[] with_none = { _("None") };
            foreach (string l in labels) with_none += l;
            for (int i = 0; i < 3; i++) {
                var g = new PreferencesGroup (i == 0 ? _("Sort by") : _("Then by"));
                var colrow = new SelectionRow (_("Column"), i == 0 ? labels : with_none, i == 0 ? labels[int.min (win.grid.cur_col - area.c1, labels.length - 1).clamp (0, labels.length - 1)] : _("None"));
                var order = new SelectionRow (_("Order"), order_items, order_items[0]);
                g.add_row (colrow);
                g.add_row (order);
                levels.add (colrow);
                orders.add (order);
                box.append (g);
            }
            header.switch_btn.notify["active"].connect (() => {
                string[] nl = column_labels (s, area, header.active);
                string[] nn = { _("None") };
                foreach (string l in nl) nn += l;
                for (int i = 0; i < 3; i++) levels[i].set_items (i == 0 ? nl : nn);
            });
            footer (dlg, _("Sort"), () => {
                var keys = new Gee.ArrayList<SortKey> ();
                string[] cur = column_labels (s, area, header.active);
                for (int i = 0; i < 3; i++) {
                    string v = levels[i].current_value;
                    for (int k = 0; k < cur.length; k++) {
                        if (cur[k] == v) {
                            keys.add (new SortKey (area.c1 + k, orders[i].current_value == order_items[0]));
                            break;
                        }
                    }
                }
                if (keys.size > 0) win.doc.sort (s, area, keys, header.active);
            });
            dlg.open_dialog ();
        }

        public static void remove_duplicates (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            var area = sel.is_single () ? win.doc.current_region (s, sel.r1, sel.c1) : Document.clamp_area (s, sel);
            if (area.r2 > s.max_row) area.r2 = int.max (s.max_row, area.r1);
            var dlg = make (win, _("Remove Duplicates"), 420, 460);
            var box = body (dlg);
            var g0 = new PreferencesGroup (_("Range"), _("Rows in %s with the same values in the chosen columns are removed, keeping the first one.").printf (area_text (area)));
            var header = new SwitchRow (_("First row is a header"), null, s.value_at (area.r1, area.c1).kind == ValueKind.TEXT);
            g0.add_row (header);
            box.append (g0);
            var g = new PreferencesGroup (_("Columns"));
            var switches = new Gee.ArrayList<SwitchRow> ();
            string[] labels = column_labels (s, area, true);
            for (int i = 0; i < labels.length; i++) {
                var row = new SwitchRow (labels[i], null, true);
                switches.add (row);
                g.add_row (row);
            }
            box.append (g);
            footer (dlg, _("Remove"), () => {
                int[] cols = {};
                for (int i = 0; i < switches.size; i++) if (switches[i].active) cols += area.c1 + i;
                if (cols.length == 0) return;
                int n = win.doc.remove_duplicates (s, area, cols, header.active);
                var done = new ConfirmDialog ((Gtk.Application) win.application, _("Duplicates Removed"), "object-select-symbolic",
                    n == 0 ? _("No duplicate rows were found.") : ngettext ("%d duplicate row was removed.", "%d duplicate rows were removed.", n).printf (n),
                    _("OK"), ConfirmDialog.ActionStyle.SUGGESTED);
                done.transient_for = win;
                done.present ();
            });
            dlg.open_dialog ();
        }

        public static void validation (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            string current = "";
            string message = "";
            foreach (var v in s.validations) {
                if (v.area.contains (sel.r1, sel.c1)) {
                    current = v.list_source;
                    message = v.message;
                }
            }
            var dlg = make (win, _("Dropdown List"), 440, 360);
            var box = body (dlg);
            var g = new PreferencesGroup (_("List"), _("Cells in %s show a list to choose from. Type the items separated by commas, or a range such as $A$1:$A$10.").printf (area_text (sel)));
            var src = new EntryRow (_("Items"));
            string shown = current.has_prefix ("\"") && current.has_suffix ("\"") ? current.substring (1, current.length - 2) : current;
            src.text = shown;
            g.add_row (src);
            box.append (g);
            Apply apply = () => {
                string t = src.text.strip ();
                if (t == "") {
                    win.doc.set_validation (s, sel, null);
                    return;
                }
                bool is_ref = t.has_prefix ("=") || Area.parse (t.replace ("$", "").replace ("=", ""), s) != null || t.contains ("!");
                win.doc.set_validation (s, sel, is_ref ? (t.has_prefix ("=") ? t.substring (1) : t) : "\"" + t + "\"");
                win.grid.queue_draw ();
            };
            if (current != "") footer (dlg, _("Apply"), (owned) apply, _("Remove List"), () => win.doc.set_validation (s, sel, null));
            else footer (dlg, _("Apply"), (owned) apply);
            dlg.open_dialog ();
        }

        public static void names (SpreadsheetWindow win) {
            var dlg = make (win, _("Named Ranges"), 520, 520);
            var box = body (dlg);
            var list = new PreferencesGroup (_("Names"));
            box.append (list);
            Apply refill = null;
            refill = () => {
                list.clear ();
                int count = 0;
                var keys = new Gee.TreeSet<string> ();
                keys.add_all (win.doc.book.names.keys);
                foreach (string k in keys) {
                    string name = k;
                    var row = new ActionRow (name, _("Workbook") + "  " + win.doc.book.names[name]);
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete");
                    del.clicked.connect (() => {
                        win.doc.set_scoped_name (null, name, null);
                        refill ();
                    });
                    row.add_suffix (del);
                    list.add_row (row);
                    count++;
                }
                foreach (var sh in win.doc.book.sheets) {
                    var skeys = new Gee.TreeSet<string> ();
                    skeys.add_all (sh.names.keys);
                    foreach (string k in skeys) {
                        string name = k;
                        var scope = sh;
                        var row = new ActionRow (name, scope.name + "  " + scope.names[name]);
                        var del = new Button.from_icon_name ("user-trash-symbolic");
                        del.add_css_class ("flat");
                        del.valign = Align.CENTER;
                        del.tooltip_text = _("Delete");
                        del.clicked.connect (() => {
                            win.doc.set_scoped_name (scope, name, null);
                            refill ();
                        });
                        row.add_suffix (del);
                        list.add_row (row);
                        count++;
                    }
                }
                if (count == 0) {
                    list.add_row (new ActionRow (_("No names yet"), _("Give a cell or a range a name to use it in formulas.")));
                }
            };
            refill ();
            var add = new PreferencesGroup (_("Add a Name"));
            var name_row = new EntryRow (_("Name"));
            var sel = win.grid.selection;
            var ref_row = new EntryRow (_("Refers to"));
            ref_row.text = Address.quote_sheet (win.grid.sheet.name) + "!" + Address.cell (sel.r1, sel.c1, true, true) + (sel.is_single () ? "" : ":" + Address.cell (sel.r2, sel.c2, true, true));
            add.add_row (name_row);
            add.add_row (ref_row);
            string[] scopes = { _("Workbook") };
            foreach (var sh in win.doc.book.sheets) scopes += sh.name;
            var scope_pick = new DropDown.from_strings (scopes);
            scope_pick.valign = Align.CENTER;
            var scope_row = new ActionRow (_("Scope"), _("Where the name can be used"));
            scope_row.add_suffix (scope_pick);
            add.add_row (scope_row);
            var add_btn = new Button.with_label (_("Add"));
            add_btn.add_css_class ("suggested-action");
            add_btn.halign = Align.END;
            add_btn.clicked.connect (() => {
                string n = name_row.text.strip ();
                if (n == "" || n.contains (" ") || !(n[0].isalpha () || n[0] == '_') || ref_row.text.strip () == "") return;
                string target = ref_row.text.strip ();
                if (target.has_prefix ("=")) target = target.substring (1);
                uint pick = scope_pick.selected;
                Sheet? scope = pick > 0 && pick - 1 < win.doc.book.sheets.size ? win.doc.book.sheets[(int) pick - 1] : null;
                win.doc.set_scoped_name (scope, n, target);
                name_row.text = "";
                refill ();
            });
            box.append (add);
            box.append (add_btn);
            var bar = new Box (Orientation.HORIZONTAL, 0);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var close = new Button.with_label (_("Done"));
            close.add_css_class ("suggested-action");
            close.halign = Align.END;
            close.hexpand = true;
            close.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (close);
            bar.append (close);
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        private struct RuleType {
            public string label;
            public CondKind kind;
            public int values;
        }

        private static RuleType[] rule_types () {
            return {
                { _("Greater than"), CondKind.GREATER, 1 },
                { _("Less than"), CondKind.LESS, 1 },
                { _("Between"), CondKind.BETWEEN, 2 },
                { _("Equal to"), CondKind.EQUAL, 1 },
                { _("Not equal to"), CondKind.NOT_EQUAL, 1 },
                { _("Text contains"), CondKind.TEXT_CONTAINS, 1 },
                { _("Duplicate values"), CondKind.DUPLICATE, 0 },
                { _("Unique values"), CondKind.UNIQUE, 0 },
                { _("Top items"), CondKind.TOP, 1 },
                { _("Bottom items"), CondKind.BOTTOM, 1 },
                { _("Above average"), CondKind.ABOVE_AVERAGE, 0 },
                { _("Below average"), CondKind.BELOW_AVERAGE, 0 },
                { _("Empty cells"), CondKind.BLANK, 0 },
                { _("Errors"), CondKind.ERRORS, 0 },
                { _("Formula is true"), CondKind.FORMULA, 1 },
                { _("Color scale"), CondKind.COLOR_SCALE, 0 },
                { _("Data bars"), CondKind.DATA_BAR, 0 },
                { _("Icon set"), CondKind.ICON_SET, 0 },
                { _("Greater than or equal to"), CondKind.GREATER_EQUAL, 1 },
                { _("Less than or equal to"), CondKind.LESS_EQUAL, 1 },
                { _("Not between"), CondKind.NOT_BETWEEN, 2 },
                { _("Text begins with"), CondKind.TEXT_BEGINS, 1 },
                { _("Text ends with"), CondKind.TEXT_ENDS, 1 },
                { _("Text does not contain"), CondKind.TEXT_NOT_CONTAINS, 1 },
                { _("Cells with a value"), CondKind.NO_BLANK, 0 },
                { _("No errors"), CondKind.NO_ERRORS, 0 },
                { _("A date occurring"), CondKind.DATE_OCCURRING, 0 }
            };
        }

        private struct Preset {
            public string label;
            public string fill;
            public string color;
            public bool bold;
        }

        private static Preset[] presets () {
            return {
                { _("Light red fill with dark red text"), "#ffc7ce", "#9c0006", false },
                { _("Yellow fill with dark yellow text"), "#ffeb9c", "#9c5700", false },
                { _("Green fill with dark green text"), "#c6efce", "#006100", false },
                { _("Light blue fill"), "#dbeafe", "", false },
                { _("Red text"), "", "#c00000", false },
                { _("Bold text"), "", "", true }
            };
        }

        public static void cond_format (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            var dlg = make (win, _("Conditional Formatting"), 500, 620);
            var box = body (dlg);
            var types = rule_types ();
            string[] type_labels = {};
            foreach (var t in types) type_labels += t.label;
            var g = new PreferencesGroup (_("New Rule"));
            var range = new EntryRow (_("Applies to"));
            range.text = area_text (sel);
            var type = new SelectionRow (_("Format cells when"), type_labels, type_labels[0]);
            var a = new EntryRow (_("Value"));
            var b = new EntryRow (_("And"));
            var ps = presets ();
            string[] preset_labels = {};
            foreach (var p in ps) preset_labels += p.label;
            var style = new SelectionRow (_("Style"), preset_labels, preset_labels[0]);
            string[] scales = { _("Red, yellow, green"), _("Green, yellow, red"), _("White to blue"), _("White to green") };
            var scale = new SelectionRow (_("Colors"), scales, scales[0]);
            g.add_row (range);
            g.add_row (type);
            g.add_row (a);
            g.add_row (b);
            g.add_row (style);
            g.add_row (scale);
            var icons = new SelectionRow (_("Icons"), CondRules.icon_labels (), CondRules.icon_labels ()[0]);
            var period = new SelectionRow (_("Date"), CondRules.period_labels (), CondRules.period_labels ()[0]);
            var percent = new SwitchRow (_("Percent of items"), null, false);
            var stop = new SwitchRow (_("Stop if true"), _("Rules below this one are not applied to matching cells"), false);
            var show_value = new SwitchRow (_("Show the value"), null, true);
            g.add_row (icons);
            g.add_row (show_value);
            g.add_row (period);
            g.add_row (percent);
            g.add_row (stop);
            box.append (g);
            Apply sync = () => {
                int idx = 0;
                for (int i = 0; i < types.length; i++) if (types[i].label == type.current_value) idx = i;
                var t = types[idx];
                a.visible = t.values >= 1;
                b.visible = t.values >= 2;
                a.title = t.kind == CondKind.FORMULA ? _("Formula") : (t.kind == CondKind.TOP || t.kind == CondKind.BOTTOM ? _("How many") : (t.kind == CondKind.BETWEEN ? _("From") : _("Value")));
                if ((t.kind == CondKind.TOP || t.kind == CondKind.BOTTOM) && a.text == "") a.text = "10";
                style.visible = t.kind != CondKind.COLOR_SCALE && t.kind != CondKind.DATA_BAR && t.kind != CondKind.ICON_SET;
                scale.visible = t.kind == CondKind.COLOR_SCALE;
                icons.visible = t.kind == CondKind.ICON_SET;
                show_value.visible = t.kind == CondKind.ICON_SET;
                period.visible = t.kind == CondKind.DATE_OCCURRING;
                percent.visible = t.kind == CondKind.TOP || t.kind == CondKind.BOTTOM;
                stop.visible = style.visible;
            };
            type.selected.connect ((v) => sync ());
            sync ();

            if (s.cond_formats.size > 0) {
                var existing = new PreferencesGroup (_("Rules on This Sheet"));
                foreach (var cf in s.cond_formats) {
                    var rule = cf;
                    string label = "";
                    foreach (var t in types) if (t.kind == rule.kind) label = t.label;
                    string detail = area_text (rule.area) + (rule.a != "" ? "  " + rule.a : "") + (rule.b != "" ? "  " + rule.b : "");
                    var row = new ActionRow (label, detail);
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete Rule");
                    del.clicked.connect (() => {
                        win.doc.begin_book (_("Delete Rule"), s);
                        s.cond_formats.remove (rule);
                        win.doc.commit ();
                        existing.remove_row (row);
                    });
                    row.add_suffix (del);
                    existing.add_row (row);
                }
                box.append (existing);
            }

            footer (dlg, _("Add Rule"), () => {
                var area = Area.parse (range.text.replace ("$", ""), s) ?? sel;
                int idx = 0;
                for (int i = 0; i < types.length; i++) if (types[i].label == type.current_value) idx = i;
                var t = types[idx];
                var cf = new CondFormat (new Area (s, area.r1, area.c1, area.r2, area.c2), t.kind);
                cf.a = a.text.strip ();
                cf.b = b.text.strip ();
                if (t.kind == CondKind.FORMULA && !cf.a.has_prefix ("=")) cf.a = "=" + cf.a;
                if (t.kind == CondKind.COLOR_SCALE) {
                    int si = 0;
                    for (int i = 0; i < scales.length; i++) if (scales[i] == scale.current_value) si = i;
                    switch (si) {
                        case 0: cf.color1 = "#f8696b"; cf.color2 = "#ffeb84"; cf.color3 = "#63be7b"; cf.three_colors = true; break;
                        case 1: cf.color1 = "#63be7b"; cf.color2 = "#ffeb84"; cf.color3 = "#f8696b"; cf.three_colors = true; break;
                        case 2: cf.color1 = "#ffffff"; cf.color3 = "#5a8ac6"; cf.three_colors = false; break;
                        default: cf.color1 = "#ffffff"; cf.color3 = "#63be7b"; cf.three_colors = false; break;
                    }
                } else if (t.kind == CondKind.DATA_BAR) {
                    cf.color1 = "#638ec6";
                } else if (t.kind == CondKind.ICON_SET) {
                    cf.icon_set = CondRules.icon_set_for (icons.current_value);
                    cf.show_value = show_value.active;
                } else {
                    cf.stop_if_true = stop.active;
                    cf.percent = percent.active;
                    cf.date_period = CondRules.period_for (period.current_value);
                    Preset p = ps[0];
                    foreach (var pp in ps) if (pp.label == style.current_value) p = pp;
                    var st = new CellStyle ();
                    st.fill = p.fill;
                    st.color = p.color;
                    st.bold = p.bold;
                    cf.style = win.doc.book.intern (st);
                }
                win.doc.add_cond_format (s, cf);
            });
            dlg.open_dialog ();
        }

        public static void chart (SpreadsheetWindow win, Chart? existing) {
            ChartDialog.open (win, existing);
        }

        private static string[] number_categories () {
            return { _("General"), _("Number"), _("Currency"), _("Percentage"), _("Scientific"), _("Fraction"), _("Date"), _("Time"), _("Text"), _("Custom") };
        }

        public static void format_cells (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            var st = s.style_at (win.grid.cur_row, win.grid.cur_col).copy ();
            var sample = s.value_at (win.grid.cur_row, win.grid.cur_col);
            if (sample.kind != ValueKind.NUMBER) sample = Value.num (-1234.5678);
            var dlg = make (win, _("Format Cells"), 560, 640);
            var seg = new SegmentedControl ();
            var stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            seg.set_stack (stack);
            seg.halign = Align.CENTER;
            seg.margin_bottom = 8;
            dlg.content_box.append (seg);

            bool touched_number = false, touched_align = false, touched_font = false, touched_fill = false;

            var num_box = new Box (Orientation.VERTICAL, 12);
            var preview = new Label ("");
            preview.add_css_class ("ss-format-preview");
            preview.halign = Align.FILL;
            preview.xalign = 0.5f;
            num_box.append (preview);
            var ng = new PreferencesGroup ();
            string[] cats = number_categories ();
            string cur_cat = guess_category (st.number_format);
            var cat = new SelectionRow (_("Category"), cats, cur_cat);
            var decimals = new SpinRow (_("Decimal places"), null, 0, 12, 1, count_decimals (st.number_format));
            var thousands = new SwitchRow (_("Thousands separator"), null, st.number_format.contains (","));
            string[] negs = { "-1234.10", "(1234.10)", _("-1234.10 in red"), _("(1234.10) in red") };
            var neg = new SelectionRow (_("Negative numbers"), negs, negs[0]);
            string[] dates = { LocaleInfo.get ().short_date_format (), "yyyy-mm-dd", "d mmmm yyyy", "dddd, d mmmm yyyy", "mmm-yy", "d-mmm", LocaleInfo.get ().short_date_format () + " h:mm" };
            var date_fmt = new SelectionRow (_("Date format"), dates, dates[0]);
            string[] times = { "h:mm", "h:mm:ss", "h:mm AM/PM", "[h]:mm:ss", "mm:ss.0" };
            var time_fmt = new SelectionRow (_("Time format"), times, times[0]);
            string[] fracs = { "# ?/?", "# ??/??", "# ?/2", "# ?/4", "# ?/8", "# ??/100" };
            var frac_fmt = new SelectionRow (_("Fraction type"), fracs, fracs[0]);
            var symbol = new EntryRow (_("Currency symbol"));
            symbol.text = LocaleInfo.get ().decimal_sep == ',' ? "€" : "$";
            var custom = new EntryRow (_("Format code"));
            custom.text = st.number_format;
            ng.add_row (cat);
            ng.add_row (decimals);
            ng.add_row (thousands);
            ng.add_row (neg);
            ng.add_row (symbol);
            ng.add_row (date_fmt);
            ng.add_row (time_fmt);
            ng.add_row (frac_fmt);
            ng.add_row (custom);
            num_box.append (ng);

            Apply rebuild = () => {
                string c = cat.current_value;
                int d = (int) decimals.value;
                string dec = d > 0 ? "." + string.nfill (d, '0') : "";
                string intp = thousands.active ? "#,##0" : "0";
                string code = st.number_format;
                decimals.visible = c == _("Number") || c == _("Currency") || c == _("Percentage") || c == _("Scientific");
                thousands.visible = c == _("Number");
                neg.visible = c == _("Number") || c == _("Currency");
                symbol.visible = c == _("Currency");
                date_fmt.visible = c == _("Date");
                time_fmt.visible = c == _("Time");
                frac_fmt.visible = c == _("Fraction");
                custom.visible = c == _("Custom");
                if (c == _("General")) code = "General";
                else if (c == _("Number") || c == _("Currency")) {
                    string base_code = c == _("Currency") ? (symbol.text.length <= 1 && symbol.text != "€" ? symbol.text + "#,##0" + dec : "#,##0" + dec + " \"" + symbol.text + "\"") : intp + dec;
                    int ni = 0;
                    for (int i = 0; i < negs.length; i++) if (negs[i] == neg.current_value) ni = i;
                    switch (ni) {
                        case 1: code = base_code + ";(" + base_code + ")"; break;
                        case 2: code = base_code + ";[Red]-" + base_code; break;
                        case 3: code = base_code + ";[Red](" + base_code + ")"; break;
                        default: code = base_code; break;
                    }
                } else if (c == _("Percentage")) code = "0" + dec + "%";
                else if (c == _("Scientific")) code = "0" + (d > 0 ? dec : ".00") + "E+00";
                else if (c == _("Fraction")) code = frac_fmt.current_value;
                else if (c == _("Date")) code = date_fmt.current_value;
                else if (c == _("Time")) code = time_fmt.current_value;
                else if (c == _("Text")) code = "@";
                else if (c == _("Custom")) code = custom.text;
                if (c != _("Custom")) custom.text = code;
                st.number_format = code;
                string color;
                preview.label = NumberFormat.format_value (c == _("Text") ? Value.str (sample.display ()) : sample, code, out color, win.doc.book.date1904);
            };
            cat.selected.connect ((v) => {
                touched_number = true;
                rebuild ();
            });
            decimals.spin_btn.value_changed.connect (() => {
                touched_number = true;
                rebuild ();
            });
            thousands.switch_btn.notify["active"].connect (() => {
                touched_number = true;
                rebuild ();
            });
            neg.selected.connect ((v) => {
                touched_number = true;
                rebuild ();
            });
            date_fmt.selected.connect ((v) => {
                touched_number = true;
                rebuild ();
            });
            time_fmt.selected.connect ((v) => {
                touched_number = true;
                rebuild ();
            });
            frac_fmt.selected.connect ((v) => {
                touched_number = true;
                rebuild ();
            });
            symbol.entry_changed.connect (() => {
                touched_number = true;
                rebuild ();
            });
            custom.entry_changed.connect (() => {
                if (cat.current_value != _("Custom")) return;
                touched_number = true;
                st.number_format = custom.text;
                string color;
                preview.label = NumberFormat.format_value (sample, custom.text, out color, win.doc.book.date1904);
            });
            rebuild ();
            stack.add_titled (scrolled (num_box), "number", _("Number"));

            var al_box = new Box (Orientation.VERTICAL, 12);
            var ag = new PreferencesGroup ();
            string[] hs = { _("General"), _("Left"), _("Center"), _("Right"), _("Fill"), _("Justify") };
            string[] vs = { _("Bottom"), _("Middle"), _("Top") };
            var h = new SelectionRow (_("Horizontal"), hs, hs[st.halign]);
            var v = new SelectionRow (_("Vertical"), vs, vs[st.valign]);
            var wrap = new SwitchRow (_("Wrap text"), null, st.wrap);
            var indent = new SpinRow (_("Indent"), null, 0, 15, 1, st.indent);
            ag.add_row (h);
            ag.add_row (v);
            ag.add_row (wrap);
            ag.add_row (indent);
            var shrink = new SwitchRow (_("Shrink to fit"), null, st.shrink);
            ag.add_row (shrink);
            al_box.append (ag);
            var og = new PreferencesGroup (_("Orientation"));
            var vertical = new SwitchRow (_("Vertical text"), null, st.rotation == 255);
            var degrees = new SpinRow (_("Degrees"), null, -90, 90, 5, st.rotation == 255 ? 0 : st.rotation);
            og.add_row (vertical);
            og.add_row (degrees);
            al_box.append (og);
            shrink.switch_btn.notify["active"].connect (() => touched_align = true);
            vertical.switch_btn.notify["active"].connect (() => touched_align = true);
            degrees.spin_btn.value_changed.connect (() => touched_align = true);
            h.selected.connect ((x) => touched_align = true);
            v.selected.connect ((x) => touched_align = true);
            wrap.switch_btn.notify["active"].connect (() => touched_align = true);
            indent.spin_btn.value_changed.connect (() => touched_align = true);
            stack.add_titled (scrolled (al_box), "alignment", _("Alignment"));

            var font_box = new Box (Orientation.VERTICAL, 12);
            var fg = new PreferencesGroup ();
            var families = new Gee.TreeSet<string> ();
            Pango.FontFamily[] fams;
            ((Pango.FontMap) Pango.CairoFontMap.get_default ()).list_families (out fams);
            foreach (var fam in fams) families.add (fam.get_name ());
            string[] fam_items = { _("Default") };
            foreach (string f in families) fam_items += f;
            var family = new SelectionRow (_("Font"), fam_items, st.font_family == "" ? fam_items[0] : st.font_family);
            var fsize = new SpinRow (_("Size"), null, 6, 96, 1, st.font_size);
            var bold = new SwitchRow (_("Bold"), null, st.bold);
            var italic = new SwitchRow (_("Italic"), null, st.italic);
            var underline = new SwitchRow (_("Underline"), null, st.underline);
            var strike = new SwitchRow (_("Strikethrough"), null, st.strike);
            var color_row = new ActionRow (_("Color"));
            Gdk.RGBA init_color = Gdk.RGBA ();
            init_color.parse (st.color != "" ? st.color : "#000000");
            var color_btn = new ColorPickerButton (init_color);
            color_btn.valign = Align.CENTER;
            string new_color = st.color;
            color_btn.color_changed.connect ((c) => {
                new_color = "#%02x%02x%02x".printf ((int) (c.red * 255), (int) (c.green * 255), (int) (c.blue * 255));
                touched_font = true;
            });
            color_row.add_suffix (color_btn);
            fg.add_row (family);
            fg.add_row (fsize);
            fg.add_row (bold);
            fg.add_row (italic);
            fg.add_row (underline);
            fg.add_row (strike);
            fg.add_row (color_row);
            font_box.append (fg);
            family.selected.connect ((x) => touched_font = true);
            fsize.spin_btn.value_changed.connect (() => touched_font = true);
            bold.switch_btn.notify["active"].connect (() => touched_font = true);
            italic.switch_btn.notify["active"].connect (() => touched_font = true);
            underline.switch_btn.notify["active"].connect (() => touched_font = true);
            strike.switch_btn.notify["active"].connect (() => touched_font = true);
            stack.add_titled (scrolled (font_box), "font", _("Font"));

            var border_box = new Box (Orientation.VERTICAL, 12);
            var bg = new PreferencesGroup ();
            string[] styles = { _("Thin"), _("Medium"), _("Thick"), _("Dashed"), _("Dotted"), _("Double") };
            BorderStyle[] style_values = { BorderStyle.THIN, BorderStyle.MEDIUM, BorderStyle.THICK, BorderStyle.DASHED, BorderStyle.DOTTED, BorderStyle.DOUBLE };
            var bstyle = new SelectionRow (_("Line"), styles, styles[0]);
            var bcolor_row = new ActionRow (_("Color"));
            var bcolor = new ColorPickerButton (Gdk.RGBA () { red = 0, green = 0, blue = 0, alpha = 1 });
            bcolor.valign = Align.CENTER;
            string border_color = "";
            bcolor.color_changed.connect ((c) => border_color = "#%02x%02x%02x".printf ((int) (c.red * 255), (int) (c.green * 255), (int) (c.blue * 255)));
            bcolor_row.add_suffix (bcolor);
            bg.add_row (bstyle);
            bg.add_row (bcolor_row);
            border_box.append (bg);
            var presets_row = new FlowBox ();
            presets_row.selection_mode = SelectionMode.NONE;
            presets_row.max_children_per_line = 4;
            presets_row.column_spacing = 8;
            presets_row.row_spacing = 8;
            string[] bkinds = { "all", "outer", "inner", "none", "top", "bottom", "left", "right" };
            string[] bnames = { _("All"), _("Outside"), _("Inside"), _("None"), _("Top"), _("Bottom"), _("Left"), _("Right") };
            for (int i = 0; i < bkinds.length; i++) {
                var b = new Button ();
                b.add_css_class ("ss-border-preset");
                var inner = new Box (Orientation.VERTICAL, 4);
                inner.append (new BorderGlyph (bkinds[i]));
                inner.append (new Label (bnames[i]));
                b.child = inner;
                string k = bkinds[i];
                b.clicked.connect (() => {
                    int si = 0;
                    for (int j = 0; j < styles.length; j++) if (styles[j] == bstyle.current_value) si = j;
                    win.doc.edit_borders (s, sel, k, k == "none" ? BorderStyle.NONE : style_values[si], border_color);
                });
                presets_row.append (b);
            }
            border_box.append (presets_row);
            var bnote = new Label (_("Borders are applied as soon as you choose them."));
            bnote.add_css_class ("dim-label");
            bnote.add_css_class ("caption");
            bnote.halign = Align.START;
            border_box.append (bnote);
            stack.add_titled (scrolled (border_box), "border", _("Border"));

            var fill_box = new Box (Orientation.VERTICAL, 12);
            var flg = new PreferencesGroup ();
            var fill_on = new SwitchRow (_("Fill color"), null, st.fill != "");
            var fill_row = new ActionRow (_("Color"));
            Gdk.RGBA init_fill = Gdk.RGBA ();
            init_fill.parse (st.fill != "" ? st.fill : "#fff4c2");
            var fill_btn = new ColorPickerButton (init_fill);
            fill_btn.valign = Align.CENTER;
            string new_fill = st.fill != "" ? st.fill : "#fff4c2";
            fill_btn.color_changed.connect ((c) => {
                new_fill = "#%02x%02x%02x".printf ((int) (c.red * 255), (int) (c.green * 255), (int) (c.blue * 255));
                touched_fill = true;
                fill_on.active = true;
            });
            fill_row.add_suffix (fill_btn);
            fill_on.switch_btn.notify["active"].connect (() => touched_fill = true);
            flg.add_row (fill_on);
            flg.add_row (fill_row);
            fill_box.append (flg);
            stack.add_titled (scrolled (fill_box), "fill", _("Fill"));
            bool touched_prot = false;
            var prot_box = new Box (Orientation.VERTICAL, 12);
            var pg = new PreferencesGroup (null, _("Locking cells or hiding formulas has no effect until the sheet is protected."));
            var locked = new SwitchRow (_("Locked"), null, st.locked);
            var hidden = new SwitchRow (_("Hidden"), _("Hides the formula in the formula bar"), st.hidden);
            pg.add_row (locked);
            pg.add_row (hidden);
            prot_box.append (pg);
            locked.switch_btn.notify["active"].connect (() => touched_prot = true);
            hidden.switch_btn.notify["active"].connect (() => touched_prot = true);
            stack.add_titled (scrolled (prot_box), "protection", _("Protection"));

            seg.add_option ("number", _("Number"));
            seg.add_option ("alignment", _("Alignment"));
            seg.add_option ("font", _("Font"));
            seg.add_option ("border", _("Border"));
            seg.add_option ("fill", _("Fill"));
            seg.add_option ("protection", _("Protection"));
            seg.set_active ("number");
            dlg.content_box.append (stack);

            footer (dlg, _("Apply"), () => {
                string code = st.number_format;
                int hi = 0, vi = 0;
                for (int i = 0; i < hs.length; i++) if (hs[i] == h.current_value) hi = i;
                for (int i = 0; i < vs.length; i++) if (vs[i] == v.current_value) vi = i;
                string fam = family.current_value == fam_items[0] ? "" : family.current_value;
                win.doc.edit_style (s, sel, _("Format Cells"), (x) => {
                    if (touched_number) x.number_format = code;
                    if (touched_align) {
                        x.halign = (HAlign) hi;
                        x.valign = (VAlign) vi;
                        x.wrap = wrap.active;
                        x.indent = (int) indent.value;
                        x.shrink = shrink.active;
                        x.rotation = vertical.active ? 255 : (int) degrees.value;
                    }
                    if (touched_prot) {
                        x.locked = locked.active;
                        x.hidden = hidden.active;
                    }
                    if (touched_font) {
                        x.font_family = fam;
                        x.font_size = fsize.value;
                        x.bold = bold.active;
                        x.italic = italic.active;
                        x.underline = underline.active;
                        x.strike = strike.active;
                        x.color = new_color;
                    }
                    if (touched_fill) x.fill = fill_on.active ? new_fill : "";
                });
            });
            dlg.open_dialog ();
        }

        private static Widget scrolled (Box content) {
            content.margin_start = content.margin_end = 18;
            content.margin_top = 4;
            content.margin_bottom = 8;
            var sc = new ScrolledWindow ();
            sc.hscrollbar_policy = PolicyType.NEVER;
            sc.vexpand = true;
            sc.child = content;
            return sc;
        }

        private static string guess_category (string code) {
            string c = code.down ();
            if (c == "general" || c == "") return _("General");
            if (c == "@") return _("Text");
            if (c.contains ("e+") || c.contains ("e-")) return _("Scientific");
            if (c.contains ("%")) return _("Percentage");
            if (c.contains ("?/")) return _("Fraction");
            if (NumberFormat.is_date_format (code)) {
                string stripped = c.replace ("am/pm", "");
                if (stripped.contains ("y") || stripped.contains ("d")) return _("Date");
                return _("Time");
            }
            if (c.contains ("$") || c.contains ("€") || c.contains ("£") || c.contains ("¥")) return _("Currency");
            if (c.contains ("0") || c.contains ("#")) return _("Number");
            return _("Custom");
        }

        private static int count_decimals (string code) {
            string first = code.split (";")[0];
            int dot = first.index_of (".");
            if (dot < 0) return code == "General" ? 2 : 0;
            int n = 0;
            for (int i = dot + 1; i < first.length && (first[i] == '0' || first[i] == '#'); i++) n++;
            return n;
        }
    }
}
