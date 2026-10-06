using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class FilterUi {
        public static string[] text_ops () {
            return { _("equals"), _("does not equal"), _("is greater than"), _("is greater than or equal to"), _("is less than"), _("is less than or equal to"), _("begins with"), _("ends with"), _("contains"), _("does not contain") };
        }

        public static string[] op_ids () {
            return { "equal", "notequal", "greater", "greaterequal", "less", "lessequal", "begins", "ends", "contains", "notcontains" };
        }

        private static int op_index (string id) {
            string[] ids = op_ids ();
            for (int i = 0; i < ids.length; i++) if (ids[i] == id) return i;
            return 0;
        }

        public static void custom (SpreadsheetWindow win, int col, string op1, string v1 = "", string op2 = "", string v2 = "", bool and_join = true) {
            var s = win.grid.sheet;
            var dlg = Dialogs.make (win, _("Custom AutoFilter"), 460, 440);
            var box = Dialogs.body (dlg);
            string[] labels = text_ops ();
            string[] with_none = { _("(none)") };
            foreach (string l in labels) with_none += l;
            var g1 = new PreferencesGroup (_("Show rows where"), _("Use ? for any single character and * for any series of characters."));
            var o1 = new SelectionRow (_("Condition"), labels, labels[op_index (op1)]);
            var e1 = new EntryRow (_("Value"));
            e1.text = v1;
            g1.add_row (o1);
            g1.add_row (e1);
            box.append (g1);
            string[] joins = { _("And"), _("Or") };
            var g2 = new PreferencesGroup (_("Second Condition"));
            var join = new SelectionRow (_("Combine"), joins, and_join ? joins[0] : joins[1]);
            var o2 = new SelectionRow (_("Condition"), with_none, op2 == "" ? with_none[0] : labels[op_index (op2)]);
            var e2 = new EntryRow (_("Value"));
            e2.text = v2;
            g2.add_row (join);
            g2.add_row (o2);
            g2.add_row (e2);
            box.append (g2);
            Dialogs.footer (dlg, _("Apply"), () => {
                var r = new FilterRule ();
                r.kind = FilterKind.CUSTOM;
                string[] ids = op_ids ();
                for (int i = 0; i < labels.length; i++) if (labels[i] == o1.current_value) r.op1 = ids[i];
                r.v1 = e1.text;
                r.op2 = "";
                for (int i = 0; i < labels.length; i++) if (labels[i] == o2.current_value) r.op2 = ids[i];
                r.v2 = e2.text;
                r.and_join = join.current_value == joins[0];
                EditCommands.set_filter_rule (win.doc, s, col, r);
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }

        public static void top10 (SpreadsheetWindow win, int col) {
            var s = win.grid.sheet;
            var dlg = Dialogs.make (win, _("Top 10 AutoFilter"), 420, 320);
            var box = Dialogs.body (dlg);
            string[] which = { _("Top"), _("Bottom") };
            string[] units = { _("Items"), _("Percent") };
            var g = new PreferencesGroup (_("Show"));
            var w = new SelectionRow (_("Show"), which, which[0]);
            var n = new SpinRow (_("Count"), null, 1, 500, 1, 10);
            var u = new SelectionRow (_("Unit"), units, units[0]);
            g.add_row (w);
            g.add_row (n);
            g.add_row (u);
            box.append (g);
            Dialogs.footer (dlg, _("Apply"), () => {
                var r = new FilterRule ();
                r.kind = FilterKind.TOP10;
                r.bottom = w.current_value == which[1];
                r.top = n.value;
                r.percent = u.current_value == units[1];
                EditCommands.set_filter_rule (win.doc, s, col, r);
                win.grid.refresh ();
            });
            dlg.open_dialog ();
        }

        private static void dyn_filter (SpreadsheetWindow win, int col, string kind) {
            var r = new FilterRule ();
            r.kind = FilterKind.DYNAMIC;
            r.dyn_type = kind;
            EditCommands.set_filter_rule (win.doc, win.grid.sheet, col, r);
            win.grid.refresh ();
        }

        private static void by_color (SpreadsheetWindow win, int col, string color, bool fill) {
            var r = new FilterRule ();
            r.kind = fill ? FilterKind.CELL_COLOR : FilterKind.FONT_COLOR;
            r.color = color;
            EditCommands.set_filter_rule (win.doc, win.grid.sheet, col, r);
            win.grid.refresh ();
        }

        private static void by_icon (SpreadsheetWindow win, int col, string set, int icon) {
            var r = new FilterRule ();
            r.kind = FilterKind.ICON;
            r.icon_set = set;
            r.icon = icon;
            EditCommands.set_filter_rule (win.doc, win.grid.sheet, col, r);
            win.grid.refresh ();
        }

        public static void colors_in (SpreadsheetWindow win, int col, Gee.Set<string> fills, Gee.Set<string> fonts, Gee.Map<string, int> icons) {
            colors_in_area (win, win.grid.sheet.filter.area, col, fills, fonts, icons);
        }

        public static void colors_in_area (SpreadsheetWindow win, Area area, int col, Gee.Set<string> fills, Gee.Set<string> fonts, Gee.Map<string, int> icons) {
            var s = win.grid.sheet;
            var ce = new CondEval (win.doc.book, s);
            for (int r = area.r1 + 1; r <= int.min (area.r2, area.r1 + 20000); r++) {
                var v = s.value_at (r, col);
                var cs = s.cond_formats.size > 0 ? ce.apply (r, col, v) : null;
                string fill = cs != null && cs.fill != "" ? cs.fill : s.style_at (r, col).fill;
                string font = cs != null && cs.color != "" ? cs.color : s.style_at (r, col).color;
                if (fill != "") fills.add (fill.down ());
                if (font != "") fonts.add (font.down ());
                if (cs != null && cs.icon >= 0) icons["%s:%d".printf (cs.icon_set, cs.icon)] = cs.icon;
            }
        }

        public static void sort_color (SpreadsheetWindow win, int col, string color, bool fill) {
            var s = win.grid.sheet;
            var spec = new SortSpec (s.filter.area.copy ());
            spec.header = true;
            var lv = new SortLevel (col, true);
            lv.by = fill ? SortBy.CELL_COLOR : SortBy.FONT_COLOR;
            lv.color = color;
            spec.levels.add (lv);
            SortEngine.sort (win.doc, s, spec);
            win.grid.refresh ();
        }

        public static void show_menu (SpreadsheetWindow win, Widget anchor, Gdk.Rectangle rect, int col, string kind) {
            var menu = new ContextMenu (anchor);
            menu.pointing_to = rect;
            var s = win.grid.sheet;
            var fills = new Gee.TreeSet<string> ();
            var fonts = new Gee.TreeSet<string> ();
            var icons = new Gee.TreeMap<string, int> ();
            colors_in (win, col, fills, fonts, icons);
            switch (kind) {
                case "text":
                    menu.add_item (_("Equals…"), null, () => custom (win, col, "equal"));
                    menu.add_item (_("Does Not Equal…"), null, () => custom (win, col, "notequal"));
                    menu.add_item (_("Begins With…"), null, () => custom (win, col, "begins"));
                    menu.add_item (_("Ends With…"), null, () => custom (win, col, "ends"));
                    menu.add_item (_("Contains…"), null, () => custom (win, col, "contains"));
                    menu.add_item (_("Does Not Contain…"), null, () => custom (win, col, "notcontains"));
                    menu.add_separator ();
                    menu.add_item (_("Custom Filter…"), null, () => custom (win, col, "equal"));
                    break;
                case "number":
                    menu.add_item (_("Equals…"), null, () => custom (win, col, "equal"));
                    menu.add_item (_("Does Not Equal…"), null, () => custom (win, col, "notequal"));
                    menu.add_item (_("Greater Than…"), null, () => custom (win, col, "greater"));
                    menu.add_item (_("Greater Than Or Equal To…"), null, () => custom (win, col, "greaterequal"));
                    menu.add_item (_("Less Than…"), null, () => custom (win, col, "less"));
                    menu.add_item (_("Less Than Or Equal To…"), null, () => custom (win, col, "lessequal"));
                    menu.add_item (_("Between…"), null, () => custom (win, col, "greaterequal", "", "lessequal", "", true));
                    menu.add_item (_("Top 10…"), null, () => top10 (win, col));
                    menu.add_item (_("Above Average"), null, () => dyn_filter (win, col, "aboveAverage"));
                    menu.add_item (_("Below Average"), null, () => dyn_filter (win, col, "belowAverage"));
                    menu.add_separator ();
                    menu.add_item (_("Custom Filter…"), null, () => custom (win, col, "equal"));
                    break;
                case "date":
                    menu.add_item (_("Before…"), null, () => custom (win, col, "less"));
                    menu.add_item (_("After…"), null, () => custom (win, col, "greater"));
                    menu.add_item (_("Between…"), null, () => custom (win, col, "greaterequal", "", "lessequal", "", true));
                    menu.add_separator ();
                    string[,] dyn = {
                        { _("Tomorrow"), "tomorrow" }, { _("Today"), "today" }, { _("Yesterday"), "yesterday" },
                        { _("Next Week"), "nextWeek" }, { _("This Week"), "thisWeek" }, { _("Last Week"), "lastWeek" },
                        { _("Next Month"), "nextMonth" }, { _("This Month"), "thisMonth" }, { _("Last Month"), "lastMonth" },
                        { _("Next Quarter"), "nextQuarter" }, { _("This Quarter"), "thisQuarter" }, { _("Last Quarter"), "lastQuarter" },
                        { _("Next Year"), "nextYear" }, { _("This Year"), "thisYear" }, { _("Last Year"), "lastYear" },
                        { _("Year to Date"), "yearToDate" }
                    };
                    for (int i = 0; i < dyn.length[0]; i++) {
                        string id = dyn[i, 1];
                        menu.add_item (dyn[i, 0], null, () => dyn_filter (win, col, id));
                    }
                    var period = menu.add_submenu (_("All Dates in the Period"), null);
                    for (int q = 1; q <= 4; q++) {
                        string id = "Q%d".printf (q);
                        period.add_item (_("Quarter %d").printf (q), null, () => dyn_filter (win, col, id));
                    }
                    for (int m = 1; m <= 12; m++) {
                        string id = "M%d".printf (m);
                        var dt = new DateTime.local (2024, m, 1, 0, 0, 0);
                        period.add_item (dt.format ("%B"), null, () => dyn_filter (win, col, id));
                    }
                    break;
                case "filtercolor":
                    foreach (string c in fills) {
                        string cc = c;
                        menu.add_item (_("Cell Color %s").printf (cc), null, () => by_color (win, col, cc, true));
                    }
                    foreach (string c in fonts) {
                        string cc = c;
                        menu.add_item (_("Font Color %s").printf (cc), null, () => by_color (win, col, cc, false));
                    }
                    foreach (var e in icons.entries) {
                        string set = e.key.split (":")[0];
                        int icon = e.value;
                        menu.add_item (_("Icon %d of %s").printf (icon + 1, set), null, () => by_icon (win, col, set, icon));
                    }
                    break;
                case "sortcolor":
                    foreach (string c in fills) {
                        string cc = c;
                        menu.add_item (_("Cell Color %s on Top").printf (cc), null, () => sort_color (win, col, cc, true));
                    }
                    foreach (string c in fonts) {
                        string cc = c;
                        menu.add_item (_("Font Color %s on Top").printf (cc), null, () => sort_color (win, col, cc, false));
                    }
                    break;
            }
            SpreadsheetWindow.popup_menu (menu);
        }
    }

    public class AdvancedFilterPopover : Popover {
        private SpreadsheetWindow win;
        private int col;
        private Gee.HashMap<string, CheckButton> checks = new Gee.HashMap<string, CheckButton> ();
        private Gee.HashMap<string, CheckButton> date_checks = new Gee.HashMap<string, CheckButton> ();
        private CheckButton? blanks_check;

        private MenuRow row (string label, string? icon) {
            var r = new MenuRow (label, icon);
            return r;
        }

        public AdvancedFilterPopover (SpreadsheetWindow win, int col, Gdk.Rectangle rect) {
            this.win = win;
            this.col = col;
            var s = win.grid.sheet;
            var f = s.filter;
            var box = new Box (Orientation.VERTICAL, 4);
            box.margin_top = box.margin_bottom = box.margin_start = box.margin_end = 10;
            box.width_request = 280;
            var asc = row (_("Sort A to Z"), "view-sort-ascending-symbolic");
            asc.clicked.connect (() => sort (true));
            var desc = row (_("Sort Z to A"), "view-sort-descending-symbolic");
            desc.clicked.connect (() => sort (false));
            var sort_color = row (_("Sort by Color"), null);
            sort_color.clicked.connect (() => {
                popdown ();
                FilterUi.show_menu (win, win.grid, rect, col, "sortcolor");
            });
            box.append (asc);
            box.append (desc);
            box.append (sort_color);
            box.append (new Separator (Orientation.HORIZONTAL));
            bool active = f.rules.has_key (col) || (f.hidden_values.has_key (col) && f.hidden_values[col].size > 0);
            var clear_row = row (_("Clear Filter"), "edit-clear-symbolic");
            clear_row.sensitive = active;
            clear_row.clicked.connect (() => {
                EditCommands.set_filter_rule (win.doc, s, col, null);
                win.grid.refresh ();
                popdown ();
            });
            box.append (clear_row);
            var by_color = row (_("Filter by Color"), null);
            by_color.clicked.connect (() => {
                popdown ();
                FilterUi.show_menu (win, win.grid, rect, col, "filtercolor");
            });
            box.append (by_color);
            int nums = 0, dates = 0, texts = 0;
            var values = new Gee.TreeMap<string, int> ((a, b) => {
                double x, y;
                string fx, fy;
                bool na = Input.parse_number (a, out x, out fx), nb = Input.parse_number (b, out y, out fy);
                if (na && nb) return x < y ? -1 : (x > y ? 1 : strcmp (a, b));
                if (na != nb) return na ? -1 : 1;
                return a.collate (b);
            });
            var date_tree = new Gee.TreeMap<string, Gee.TreeMap<string, Gee.TreeSet<string>>> ();
            bool has_blank = false;
            for (int r = f.area.r1 + 1; r <= f.area.r2; r++) {
                string color;
                var v = s.value_at (r, col);
                bool is_date = v.kind == ValueKind.NUMBER && NumberFormat.is_date_format (s.style_at (r, col).number_format);
                if (v.kind == ValueKind.EMPTY) {
                    has_blank = true;
                    continue;
                }
                if (is_date) {
                    dates++;
                    string y = FilterEngine.date_key (v.number, 0), m = FilterEngine.date_key (v.number, 1), d = FilterEngine.date_key (v.number, 2);
                    if (!date_tree.has_key (y)) date_tree[y] = new Gee.TreeMap<string, Gee.TreeSet<string>> ();
                    if (!date_tree[y].has_key (m)) date_tree[y][m] = new Gee.TreeSet<string> ();
                    date_tree[y][m].add (d);
                    continue;
                }
                if (v.kind == ValueKind.NUMBER) nums++;
                else texts++;
                string t = NumberFormat.format_value (v, s.style_at (r, col).number_format, out color, win.doc.book.date1904);
                values[t] = (values.has_key (t) ? values[t] : 0) + 1;
            }
            string kind = dates > nums && dates > texts ? "date" : (nums > texts ? "number" : "text");
            string label = kind == "date" ? _("Date Filters") : (kind == "number" ? _("Number Filters") : _("Text Filters"));
            var typed = row (label, null);
            typed.clicked.connect (() => {
                popdown ();
                FilterUi.show_menu (win, win.grid, rect, col, kind);
            });
            box.append (typed);
            box.append (new Separator (Orientation.HORIZONTAL));
            var search = new Gtk.SearchEntry ();
            search.placeholder_text = _("Search values");
            box.append (search);
            var hidden = f.hidden_values.has_key (col) ? f.hidden_values[col] : new Gee.HashSet<string> ();
            var rule = f.rules.has_key (col) ? f.rules[col] : null;
            var list = new Box (Orientation.VERTICAL, 2);
            var all = new CheckButton.with_label (_("Select All"));
            all.active = !active;
            list.append (all);
            foreach (var y in date_tree.entries) {
                var ycheck = new CheckButton.with_label (y.key);
                date_checks[y.key] = ycheck;
                var yexp = new Expander (null);
                yexp.label_widget = ycheck;
                var ybox = new Box (Orientation.VERTICAL, 2);
                ybox.margin_start = 18;
                foreach (var m in y.value.entries) {
                    int mn = int.parse (m.key.substring (5));
                    var mcheck = new CheckButton.with_label (new DateTime.local (2024, mn, 1, 0, 0, 0).format ("%B"));
                    date_checks[m.key] = mcheck;
                    var mexp = new Expander (null);
                    mexp.label_widget = mcheck;
                    var mbox = new Box (Orientation.VERTICAL, 2);
                    mbox.margin_start = 18;
                    foreach (string d in m.value) {
                        var dcheck = new CheckButton.with_label (d.substring (8));
                        bool on = rule == null || rule.dates.size == 0 || rule.dates.contains (d) || rule.dates.contains (m.key) || rule.dates.contains (y.key);
                        dcheck.active = on;
                        date_checks[d] = dcheck;
                        mbox.append (dcheck);
                        mcheck.toggled.connect (() => dcheck.active = mcheck.active);
                    }
                    mexp.child = mbox;
                    ybox.append (mexp);
                    mcheck.active = true;
                    foreach (string d in m.value) if (!date_checks[d].active) mcheck.active = false;
                    ycheck.toggled.connect (() => mcheck.active = ycheck.active);
                }
                yexp.child = ybox;
                list.append (yexp);
                ycheck.active = true;
                foreach (var m in y.value.keys) if (!date_checks[m].active) ycheck.active = false;
            }
            foreach (var e in values.entries) {
                var cb = new CheckButton.with_label (e.key);
                cb.active = !hidden.contains (e.key);
                checks[e.key] = cb;
                list.append (cb);
            }
            if (has_blank) {
                blanks_check = new CheckButton.with_label (_("(Blanks)"));
                blanks_check.active = !hidden.contains ("") && (rule == null || rule.blanks);
                list.append (blanks_check);
            }
            all.toggled.connect (() => {
                foreach (var cb in checks.values) cb.active = all.active;
                foreach (var cb in date_checks.values) cb.active = all.active;
                if (blanks_check != null) blanks_check.active = all.active;
            });
            search.search_changed.connect (() => {
                string q = search.text.casefold ();
                foreach (var e in checks.entries) e.value.visible = q == "" || e.key.casefold ().contains (q);
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.max_content_height = 240;
            scroll.propagate_natural_height = true;
            scroll.child = list;
            box.append (scroll);
            var buttons = new Box (Orientation.HORIZONTAL, 6);
            buttons.halign = Align.END;
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => popdown ());
            var ok = new Button.with_label (_("Apply"));
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => apply_values (date_tree));
            buttons.append (cancel);
            buttons.append (ok);
            box.append (buttons);
            child = box;
        }

        private void apply_values (Gee.TreeMap<string, Gee.TreeMap<string, Gee.TreeSet<string>>> tree) {
            var s = win.grid.sheet;
            var hide = new Gee.HashSet<string> ();
            foreach (var e in checks.entries) if (!e.value.active) hide.add (e.key);
            if (blanks_check != null && !blanks_check.active) hide.add ("");
            var rule = new FilterRule ();
            rule.blanks = blanks_check == null || blanks_check.active;
            bool all_dates = true;
            foreach (var y in tree.entries) {
                if (date_checks[y.key].active && all_of (y.value)) {
                    rule.dates.add (y.key);
                    continue;
                }
                all_dates = false;
                foreach (var m in y.value.entries) {
                    bool full = true;
                    foreach (string d in m.value) if (!date_checks[d].active) full = false;
                    if (full) {
                        rule.dates.add (m.key);
                        continue;
                    }
                    foreach (string d in m.value) if (date_checks[d].active) rule.dates.add (d);
                }
            }
            if (all_dates) rule.dates.clear ();
            win.doc.begin_book (_("Filter"), s, s.filter.area);
            var f = s.filter.copy_to (s.filter.area);
            f.hidden_values[col] = hide;
            if (rule.dates.size > 0 || (tree.size > 0 && !all_dates)) {
                if (rule.dates.size == 0) rule.dates.add ("0000");
                f.rules[col] = rule;
            } else {
                f.rules.unset (col);
            }
            s.filter = f;
            win.doc.apply_filter (s);
            win.doc.commit ();
            win.grid.refresh ();
            if (s.hidden_rows.contains (win.grid.cur_row)) win.grid.select_cell (s.filter.area.r1, col, false);
            popdown ();
        }

        private bool all_of (Gee.TreeMap<string, Gee.TreeSet<string>> months) {
            foreach (var m in months.entries) foreach (string d in m.value) if (!date_checks[d].active) return false;
            return true;
        }

        private void sort (bool asc) {
            var s = win.grid.sheet;
            var spec = new SortSpec (s.filter.area.copy ());
            spec.header = true;
            spec.levels.add (new SortLevel (col, asc));
            SortEngine.sort (win.doc, s, spec);
            win.grid.refresh ();
            popdown ();
        }
    }
}
