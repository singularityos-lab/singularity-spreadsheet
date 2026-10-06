using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class QueryEditor : Object {
        private SpreadsheetWindow win;
        private QueryDef query;
        private bool is_new;
        private AppDialog dlg;
        private PreferencesGroup steps_group;
        private Grid preview;
        private Label status;
        private int upto = -1;
        private DataFrame? last;

        private static Gee.ArrayList<QueryEditor> open_editors = new Gee.ArrayList<QueryEditor> ();

        public static void open (SpreadsheetWindow win, QueryDef q, bool is_new) {
            var e = new QueryEditor ();
            e.win = win;
            e.query = q;
            e.is_new = is_new;
            open_editors.add (e);
            e.build ();
        }

        private void build () {
            dlg = new AppDialog ((Gtk.Application) win.application, true);
            dlg.set_title (_("Query Editor: %s").printf (query.name));
            dlg.transient_for = win;
            dlg.set_default_size (1060, 660);
            dlg.add_css_class ("ss-dialog");
            dlg.close_request.connect (() => {
                open_editors.remove (this);
                return false;
            });
            var paned = new Box (Orientation.HORIZONTAL, 12);
            paned.margin_start = paned.margin_end = 18;
            paned.margin_top = 6;
            paned.vexpand = true;
            var left_scroll = new ScrolledWindow ();
            left_scroll.hscrollbar_policy = PolicyType.NEVER;
            left_scroll.width_request = 330;
            var left = new Box (Orientation.VERTICAL, 12);
            var src = new PreferencesGroup (_("Source"));
            var name_row = new EntryRow (_("Query name"));
            name_row.text = query.name;
            name_row.entry_changed.connect (() => query.name = name_row.text.strip ());
            src.add_row (name_row);
            src.add_row (new ActionRow (QueryDef.source_label (query.source_kind), query.location));
            left.append (src);
            steps_group = new PreferencesGroup (_("Applied Steps"));
            left.append (steps_group);
            var add = new Button.with_label (_("Add Step"));
            add.halign = Align.START;
            add.clicked.connect (() => add_menu (add));
            left.append (add);
            var load_group = new PreferencesGroup (_("Load To"));
            var load_row = new SwitchRow (_("Load to a sheet"), _("Leave off to keep it as a connection only"), query.load);
            load_row.switch_btn.notify["active"].connect (() => query.load = load_row.active);
            load_group.add_row (load_row);
            var table_row = new SwitchRow (_("As a table"), null, query.as_table);
            table_row.switch_btn.notify["active"].connect (() => query.as_table = table_row.active);
            load_group.add_row (table_row);
            left.append (load_group);
            left_scroll.child = left;
            paned.append (left_scroll);
            var right = new Box (Orientation.VERTICAL, 6);
            right.hexpand = true;
            status = new Label ("");
            status.xalign = 0;
            status.add_css_class ("dim-label");
            status.wrap = true;
            right.append (status);
            var pscroll = new ScrolledWindow ();
            pscroll.vexpand = true;
            pscroll.hexpand = true;
            pscroll.add_css_class ("ss-query-preview");
            preview = new Grid ();
            preview.column_spacing = 0;
            preview.row_spacing = 0;
            pscroll.child = preview;
            right.append (pscroll);
            paned.append (right);
            dlg.content_box.append (paned);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 8;
            var refresh = new Button.with_label (_("Refresh Preview"));
            refresh.clicked.connect (() => run_preview ());
            bar.append (refresh);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (cancel);
            bar.append (cancel);
            var ok = new Button.with_label (_("Close and Load"));
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                finish ();
            });
            bar.append (ok);
            dlg.content_box.append (bar);
            refill_steps ();
            run_preview ();
            dlg.open_dialog ();
        }

        private void finish () {
            var book = win.doc.book;
            var data = Analysis.data (book);
            win.doc.begin_book (_("Load Query"), win.grid.sheet);
            if (is_new && !data.queries.contains (query)) data.queries.add (query);
            Area? area = null;
            try {
                area = Analysis.load_query (book, query);
            } catch (Error e) {
                query.error = e.message;
            }
            win.doc.commit ();
            win.doc.modified = true;
            if (area != null) AnalysisUi.show_sheet (win, area.sheet);
            if (query.error != "") win.show_error (_("Query Failed"), query.error);
            dlg.close ();
        }

        private void refill_steps () {
            steps_group.clear ();
            var first = new ActionRow (_("Source"), QueryDef.source_label (query.source_kind));
            first.activatable = true;
            first.activated.connect (() => {
                upto = 0;
                run_preview ();
            });
            steps_group.add_row (first);
            for (int i = 0; i < query.steps.size; i++) {
                var st = query.steps[i];
                var row = new ActionRow (QueryStep.kind_label (st.kind), st.describe () != "" ? st.describe () : null);
                row.activatable = true;
                int idx = i;
                row.activated.connect (() => {
                    upto = idx + 1;
                    run_preview ();
                });
                var edit = new Button.from_icon_name ("document-edit-symbolic");
                edit.add_css_class ("flat");
                edit.valign = Align.CENTER;
                edit.tooltip_text = _("Edit Step");
                edit.clicked.connect (() => step_form (st, false));
                row.add_suffix (edit);
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.tooltip_text = _("Delete Step");
                del.clicked.connect (() => {
                    query.steps.remove (st);
                    upto = -1;
                    refill_steps ();
                    run_preview ();
                });
                row.add_suffix (del);
                steps_group.add_row (row);
            }
        }

        private void run_preview () {
            Widget? c;
            while ((c = preview.get_first_child ()) != null) preview.remove (c);
            try {
                last = QueryEngine.run (win.doc.book, query, null, upto);
                status.label = ngettext ("%d row", "%d rows", last.rows.size).printf (last.rows.size) + ", " + ngettext ("%d column", "%d columns", last.columns.size).printf (last.columns.size) + (upto >= 0 ? ", " + _("up to step %d").printf (upto) : "");
            } catch (Error e) {
                last = null;
                status.label = e.message;
                return;
            }
            for (int j = 0; j < last.columns.size; j++) preview.attach (cell (last.columns[j], true), j, 0);
            for (int i = 0; i < last.rows.size && i < 200; i++) {
                for (int j = 0; j < last.columns.size; j++) preview.attach (cell (last.at (i, j).display (), false), j, i + 1);
            }
        }

        private Widget cell (string text, bool header) {
            var l = new Label (text);
            l.xalign = 0;
            l.ellipsize = Pango.EllipsizeMode.END;
            l.max_width_chars = 22;
            l.width_chars = 10;
            l.margin_start = l.margin_end = 8;
            l.margin_top = l.margin_bottom = 4;
            if (header) l.add_css_class ("heading");
            var frame = new Box (Orientation.HORIZONTAL, 0);
            frame.add_css_class (header ? "ss-query-head" : "ss-query-cell");
            frame.append (l);
            return frame;
        }

        private void add_menu (Widget anchor) {
            var menu = new ContextMenu (anchor);
            foreach (string k in QueryStep.kinds ()) {
                string kind = k;
                menu.add_item (QueryStep.kind_label (k), null, () => {
                    var st = new QueryStep (kind);
                    if (kind == "promote-headers" || kind == "remove-blank-rows") {
                        query.steps.add (st);
                        refill_steps ();
                        run_preview ();
                        return;
                    }
                    step_form (st, true);
                });
            }
            SpreadsheetWindow.popup_menu (menu);
        }

        private string[] column_names () {
            string[] out_c = {};
            if (last != null) foreach (var c in last.columns) out_c += c;
            if (out_c.length == 0) out_c += "";
            return out_c;
        }

        private void step_form (QueryStep st, bool adding) {
            var f = new AnalysisForm (win, QueryStep.kind_label (st.kind), 420, 440);
            f.dlg.transient_for = dlg;
            f.section (null);
            var cols = column_names ();
            var fields = new Gee.HashMap<string, Object> ();
            switch (st.kind) {
                case "change-type":
                    fields["column"] = f.choice (_("Column"), cols, st.arg ("column", cols[0]));
                    fields["type"] = f.choice (_("Type"), { "number", "text", "date", "bool" }, st.arg ("type", "number"));
                    break;
                case "filter-rows":
                    fields["column"] = f.choice (_("Column"), cols, st.arg ("column", cols[0]));
                    fields["op"] = f.choice (_("Keep rows where"), { "=", "<>", ">", ">=", "<", "<=", "contains", "not-contains", "begins", "ends", "blank", "not-blank" }, st.arg ("op", "="));
                    fields["value"] = f.entry (_("Value"), st.arg ("value"));
                    break;
                case "remove-columns":
                case "keep-columns":
                case "reorder-columns":
                    fields["columns"] = f.entry (_("Columns, separated by commas"), st.arg ("columns", string.joinv (",", cols)));
                    break;
                case "rename-column":
                    fields["column"] = f.choice (_("Column"), cols, st.arg ("column", cols[0]));
                    fields["name"] = f.entry (_("New name"), st.arg ("name"));
                    break;
                case "split-column":
                    fields["column"] = f.choice (_("Column"), cols, st.arg ("column", cols[0]));
                    fields["delimiter"] = f.entry (_("Delimiter"), st.arg ("delimiter", ","));
                    break;
                case "replace-values":
                    fields["column"] = f.choice (_("Column"), cols, st.arg ("column", cols[0]));
                    fields["find"] = f.entry (_("Value to find"), st.arg ("find"));
                    fields["replace"] = f.entry (_("Replace with"), st.arg ("replace"));
                    break;
                case "group-by":
                    fields["keys"] = f.entry (_("Group by columns"), st.arg ("keys", cols[0]));
                    fields["column"] = f.choice (_("Column to aggregate"), cols, st.arg ("column", cols[cols.length - 1]));
                    fields["function"] = f.choice (_("Operation"), { "sum", "count", "average", "min", "max", "countNums" }, st.arg ("function", "sum"));
                    fields["name"] = f.entry (_("New column name"), st.arg ("name"));
                    break;
                case "sort":
                    fields["columns"] = f.entry (_("Sort by columns"), st.arg ("columns", cols[0]));
                    fields["descending"] = f.entry (_("Descending flags (1 or 0 per column)"), st.arg ("descending", "0"));
                    break;
                case "merge":
                case "append":
                    string[] names = {};
                    foreach (var q in Analysis.data (win.doc.book).queries) if (q != query) names += q.name;
                    if (names.length == 0) names += "";
                    fields["query"] = f.choice (_("Other query"), names, st.arg ("query", names[0]));
                    if (st.kind == "merge") {
                        fields["key"] = f.choice (_("Matching column"), cols, st.arg ("key", cols[0]));
                        fields["other-key"] = f.entry (_("Matching column in the other query"), st.arg ("other-key"));
                        fields["join"] = f.choice (_("Join kind"), { "left", "inner" }, st.arg ("join", "left"));
                    }
                    break;
                case "unpivot":
                    fields["keep"] = f.entry (_("Columns to keep"), st.arg ("keep", cols[0]));
                    fields["attribute"] = f.entry (_("Attribute column name"), st.arg ("attribute", "Attribute"));
                    fields["value"] = f.entry (_("Value column name"), st.arg ("value", "Value"));
                    break;
                case "remove-duplicates":
                    fields["columns"] = f.entry (_("Columns (empty for all)"), st.arg ("columns"));
                    break;
                case "keep-top":
                    fields["count"] = f.entry (_("Number of rows"), st.arg ("count", "10"));
                    break;
                case "fill-down":
                case "trim":
                    fields["column"] = f.choice (_("Column"), cols, st.arg ("column", cols[0]));
                    break;
                case "add-index":
                    fields["name"] = f.entry (_("Column name"), st.arg ("name", "Index"));
                    fields["start"] = f.entry (_("Start at"), st.arg ("start", "1"));
                    break;
            }
            f.footer (adding ? _("Add") : _("Apply"), () => {
                foreach (var e in fields.entries) {
                    string v = "";
                    if (e.value is EntryRow) v = ((EntryRow) e.value).text.strip ();
                    else if (e.value is SelectionRow) v = ((SelectionRow) e.value).current_value;
                    st.args[e.key] = v;
                }
                if (adding) query.steps.add (st);
                try {
                    QueryEngine.run (win.doc.book, query);
                } catch (Error err) {
                    if (adding) query.steps.remove (st);
                    f.fail (err.message);
                    return false;
                }
                upto = -1;
                refill_steps ();
                run_preview ();
                return true;
            });
            f.open ();
        }
    }
}
