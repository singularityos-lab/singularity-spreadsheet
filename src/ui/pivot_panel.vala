using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class PivotPanel : Box {
        private SpreadsheetWindow win;
        private PivotTable? pivot;
        private Box content;
        private Label title_label;

        public PivotPanel (SpreadsheetWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            add_css_class ("ss-pivot-panel");
            width_request = 320;
            hexpand = false;
            var head = new Box (Orientation.HORIZONTAL, 6);
            head.margin_start = 14;
            head.margin_end = 8;
            head.margin_top = 10;
            head.margin_bottom = 6;
            title_label = new Label (_("PivotTable Fields"));
            title_label.add_css_class ("heading");
            title_label.hexpand = true;
            title_label.xalign = 0;
            title_label.ellipsize = Pango.EllipsizeMode.END;
            head.append (title_label);
            var close = new Button.from_icon_name ("window-close-symbolic");
            close.add_css_class ("flat");
            close.tooltip_text = _("Hide Field List");
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
        }

        public void toggle_for (PivotTable? p) {
            if (visible && (p == null || p == pivot)) {
                visible = false;
                return;
            }
            if (p == null) {
                var list = Analysis.data (win.doc.book).pivots;
                foreach (var q in list) if (q.target_sheet == win.grid.sheet) p = q;
            }
            if (p == null) {
                win.show_error (_("No PivotTable"), _("Select a cell inside a PivotTable, or create one from the Data menu."));
                return;
            }
            show_for (p);
        }

        public void show_for (PivotTable p) {
            pivot = p;
            visible = true;
            rebuild ();
        }

        private void apply (string label) {
            if (pivot == null) return;
            var book = win.doc.book;
            win.doc.begin_book (label, pivot.target_sheet);
            Analysis.write_pivot (book, pivot);
            win.doc.commit ();
            win.grid.refresh ();
            rebuild ();
        }

        private bool in_area (int col) {
            foreach (var f in pivot.rows) if (f.source_col == col) return true;
            foreach (var f in pivot.cols) if (f.source_col == col) return true;
            foreach (var f in pivot.filters) if (f.source_col == col) return true;
            foreach (var v in pivot.values) if (v.source_col == col) return true;
            return false;
        }

        private void remove_field (int col) {
            foreach (var list in new Gee.ArrayList<PivotField>[] { pivot.rows, pivot.cols, pivot.filters }) {
                var drop = new Gee.ArrayList<PivotField> ();
                foreach (var f in list) if (f.source_col == col) drop.add (f);
                list.remove_all (drop);
            }
            var dv = new Gee.ArrayList<PivotValue> ();
            foreach (var v in pivot.values) if (v.source_col == col) dv.add (v);
            pivot.values.remove_all (dv);
        }

        private bool numeric_column (int col) {
            var a = pivot.source_area (win.doc.book);
            if (a == null) return false;
            int nums = 0, texts = 0;
            for (int r = a.r1 + 1; r <= int.min (a.r2, a.r1 + 50); r++) {
                var v = a.sheet.value_at (r, a.c1 + col);
                if (v.kind == ValueKind.NUMBER) nums++;
                else if (v.kind == ValueKind.TEXT) texts++;
            }
            return nums > texts;
        }

        private bool is_date_column (int col) {
            var a = pivot.source_area (win.doc.book);
            if (a == null || a.r2 <= a.r1) return false;
            string fmt = a.sheet.style_at (a.r1 + 1, a.c1 + col).number_format;
            return NumberFormat.is_date_format (fmt);
        }

        private void rebuild () {
            Widget? c;
            while ((c = content.get_first_child ()) != null) content.remove (c);
            if (pivot == null) return;
            title_label.label = pivot.name;
            var headers = pivot.headers (win.doc.book);
            var fields = new PreferencesGroup (_("Fields"), _("Check a field to add it: numbers go to Values, the rest to Rows."));
            for (int i = 0; i < headers.length; i++) {
                var row = new SwitchRow (headers[i], null, in_area (i));
                int col = i;
                string name = headers[i];
                row.switch_btn.notify["active"].connect (() => {
                    if (row.switch_btn.active == in_area (col)) return;
                    if (row.switch_btn.active) {
                        if (numeric_column (col)) pivot.values.add (new PivotValue (col, name, PivotAgg.SUM));
                        else {
                            var f = new PivotField (col, name);
                            if (is_date_column (col)) f.group = PivotGroup.YEARS;
                            pivot.rows.add (f);
                        }
                    } else {
                        remove_field (col);
                    }
                    Idle.add (() => {
                        apply (_("PivotTable Fields"));
                        return Source.REMOVE;
                    });
                });
                fields.add_row (row);
            }
            content.append (fields);
            add_area (_("Filters"), pivot.filters, 2);
            add_area (_("Columns"), pivot.cols, 1);
            add_area (_("Rows"), pivot.rows, 0);
            var values = new PreferencesGroup (_("Values"));
            if (pivot.values.size == 0) values.add_row (new ActionRow (_("Drop fields here"), _("Check a numeric field above")));
            foreach (var v in pivot.values) {
                var row = new ActionRow (v.caption ());
                var more = new Button.from_icon_name ("view-more-symbolic");
                more.add_css_class ("flat");
                more.valign = Align.CENTER;
                more.tooltip_text = _("Value Field Settings");
                var vv = v;
                more.clicked.connect (() => value_menu (more, vv));
                row.add_suffix (more);
                values.add_row (row);
            }
            content.append (values);
            var opts = new PreferencesGroup (_("Layout"));
            var rg = new SwitchRow (_("Grand totals for rows"), null, pivot.row_grand);
            rg.switch_btn.notify["active"].connect (() => {
                if (pivot.row_grand == rg.active) return;
                pivot.row_grand = rg.active;
                Idle.add (() => { apply (_("PivotTable Layout")); return Source.REMOVE; });
            });
            opts.add_row (rg);
            var cg = new SwitchRow (_("Grand totals for columns"), null, pivot.col_grand);
            cg.switch_btn.notify["active"].connect (() => {
                if (pivot.col_grand == cg.active) return;
                pivot.col_grand = cg.active;
                Idle.add (() => { apply (_("PivotTable Layout")); return Source.REMOVE; });
            });
            opts.add_row (cg);
            var st = new SwitchRow (_("Subtotals"), null, pivot.subtotals);
            st.switch_btn.notify["active"].connect (() => {
                if (pivot.subtotals == st.active) return;
                pivot.subtotals = st.active;
                Idle.add (() => { apply (_("PivotTable Layout")); return Source.REMOVE; });
            });
            opts.add_row (st);
            content.append (opts);
            var actions = new Box (Orientation.HORIZONTAL, 8);
            actions.homogeneous = true;
            var refresh = new Button.with_label (_("Refresh"));
            refresh.clicked.connect (() => apply (_("Refresh PivotTable")));
            actions.append (refresh);
            var chart = new Button.with_label (_("PivotChart"));
            chart.clicked.connect (() => {
                win.doc.begin_book (_("Insert PivotChart"), pivot.target_sheet);
                Analysis.pivot_chart (win.doc.book, pivot);
                win.doc.commit ();
                win.grid.refresh ();
            });
            actions.append (chart);
            var del = new Button.with_label (_("Delete"));
            del.add_css_class ("destructive-action");
            del.clicked.connect (() => {
                var book = win.doc.book;
                win.doc.begin_book (_("Delete PivotTable"), pivot.target_sheet);
                if (pivot.last_output != null) Analysis.clear_area (book, pivot.last_output);
                Analysis.data (book).pivots.remove (pivot);
                book.recalculate ();
                win.doc.commit ();
                win.grid.refresh ();
                pivot = null;
                visible = false;
            });
            actions.append (del);
            content.append (actions);
        }

        private void add_area (string title, Gee.ArrayList<PivotField> list, int kind) {
            var g = new PreferencesGroup (title);
            if (list.size == 0) g.add_row (new ActionRow (_("No fields")));
            foreach (var f in list) {
                string sub = f.group != PivotGroup.NONE ? f.group.label () : (f.hidden.size > 0 ? ngettext ("%d item hidden", "%d items hidden", f.hidden.size).printf (f.hidden.size) : "");
                var row = new ActionRow (f.name, sub != "" ? sub : null);
                var more = new Button.from_icon_name ("view-more-symbolic");
                more.add_css_class ("flat");
                more.valign = Align.CENTER;
                more.tooltip_text = _("Field Settings");
                var ff = f;
                more.clicked.connect (() => field_menu (more, ff, list, kind));
                row.add_suffix (more);
                g.add_row (row);
            }
            content.append (g);
        }

        private void move_to (PivotField f, Gee.ArrayList<PivotField> from, Gee.ArrayList<PivotField> to) {
            from.remove (f);
            to.add (f);
            apply (_("Move Field"));
        }

        private void field_menu (Widget anchor, PivotField f, Gee.ArrayList<PivotField> list, int kind) {
            var menu = new ContextMenu (anchor);
            if (kind != 0) menu.add_item (_("Move to Rows"), null, () => move_to (f, list, pivot.rows));
            if (kind != 1) menu.add_item (_("Move to Columns"), null, () => move_to (f, list, pivot.cols));
            if (kind != 2) menu.add_item (_("Move to Filters"), null, () => move_to (f, list, pivot.filters));
            int idx = list.index_of (f);
            if (idx > 0) menu.add_item (_("Move Up"), null, () => {
                list.remove (f);
                list.insert (idx - 1, f);
                apply (_("Move Field"));
            });
            if (idx < list.size - 1) menu.add_item (_("Move Down"), null, () => {
                list.remove (f);
                list.insert (idx + 1, f);
                apply (_("Move Field"));
            });
            menu.add_separator ();
            menu.add_item (f.descending ? _("Sort A to Z") : _("Sort Z to A"), null, () => {
                f.descending = !f.descending;
                apply (_("Sort Field"));
            });
            var group = menu.add_submenu (_("Group"), null);
            foreach (var g in PivotGroup.all ()) {
                var gg = g;
                group.add_item (g.label () + (f.group == g ? "  ✓" : ""), null, () => {
                    f.group = gg;
                    if (gg == PivotGroup.INTERVAL) interval_dialog (f);
                    else apply (_("Group Field"));
                });
            }
            menu.add_item (_("Filter Items…"), "sheet-filter-symbolic", () => items_dialog (f));
            menu.add_separator ();
            menu.add_item (_("Remove Field"), "user-trash-symbolic", () => {
                list.remove (f);
                apply (_("Remove Field"));
            });
            SpreadsheetWindow.popup_menu (menu);
        }

        private void value_menu (Widget anchor, PivotValue v) {
            var menu = new ContextMenu (anchor);
            var summarize = menu.add_submenu (_("Summarize Values By"), null);
            foreach (var a in PivotAgg.all ()) {
                var aa = a;
                summarize.add_item (a.label () + (v.agg == a ? "  ✓" : ""), null, () => {
                    v.agg = aa;
                    apply (_("Summarize Values"));
                });
            }
            var show = menu.add_submenu (_("Show Values As"), null);
            foreach (var s in PivotShow.all ()) {
                var ss = s;
                show.add_item (s.label () + (v.show == s ? "  ✓" : ""), null, () => {
                    v.show = ss;
                    if (ss == PivotShow.NORMAL || ss == PivotShow.RUNNING_TOTAL || ss == PivotShow.DIFFERENCE || ss == PivotShow.RANK) v.number_format = "";
                    apply (_("Show Values As"));
                });
            }
            menu.add_separator ();
            int idx = pivot.values.index_of (v);
            if (idx > 0) menu.add_item (_("Move Up"), null, () => {
                pivot.values.remove (v);
                pivot.values.insert (idx - 1, v);
                apply (_("Move Field"));
            });
            menu.add_item (_("Remove Field"), "user-trash-symbolic", () => {
                pivot.values.remove (v);
                apply (_("Remove Field"));
            });
            SpreadsheetWindow.popup_menu (menu);
        }

        private void interval_dialog (PivotField f) {
            var form = new AnalysisForm (win, _("Grouping"), 380, 320);
            form.section (f.name);
            var start = form.entry (_("Starting at"), Value.format_number_general (f.interval_start));
            var size = form.entry (_("By"), Value.format_number_general (f.interval_size));
            form.footer (_("Apply"), () => {
                double a = 0, b = 0;
                string fmt;
                if (!Input.parse_number (start.text.strip (), out a, out fmt) || !Input.parse_number (size.text.strip (), out b, out fmt) || b <= 0) {
                    form.fail (_("Type a start value and a positive interval."));
                    return false;
                }
                f.interval_start = a;
                f.interval_size = b;
                apply (_("Group Field"));
                return true;
            });
            form.open ();
        }

        private void items_dialog (PivotField f) {
            var form = new AnalysisForm (win, _("Filter %s").printf (f.name), 380, 520);
            var g = form.section (_("Items"));
            var items = pivot.field_items (win.doc.book, f.source_col, f.group, f.interval_start, f.interval_size);
            var rows = new Gee.ArrayList<SwitchRow> ();
            foreach (var it in items) {
                var r = new SwitchRow (it.label, null, !f.hidden.contains (it.label));
                g.add_row (r);
                rows.add (r);
            }
            form.footer (_("Apply"), () => {
                f.hidden.clear ();
                for (int i = 0; i < rows.size; i++) if (!rows[i].active) f.hidden.add (items[i].label);
                apply (_("Filter Items"));
                return true;
            }, _("Select All"), () => {
                foreach (var r in rows) r.active = true;
                return false;
            });
            form.open ();
        }
    }
}
