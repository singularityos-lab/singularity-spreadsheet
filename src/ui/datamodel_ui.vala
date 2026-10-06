using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class DataModelUi {
        public static void install (SpreadsheetWindow win) {
            var a = new SimpleAction ("data-model", null);
            a.activate.connect (() => {
                if (win.doc == null || win.grid == null) return;
                open (win);
            });
            win.add_action (a);
        }

        public static void extend_menu (GLib.Menu data) {
            var section = new GLib.Menu ();
            section.append (_("Data Model…"), "win.data-model");
            data.append_section (null, section);
        }

        private static void save (SpreadsheetWindow win, DataModel model) {
            win.doc.begin_book (_("Data Model"), win.grid.sheet);
            model.save (win.doc.book);
            win.doc.commit ();
        }

        private static DropDown pick (string[] items) {
            var dd = new DropDown.from_strings (items);
            dd.valign = Align.CENTER;
            return dd;
        }

        private static string[] table_names (DataModel m) {
            string[] r = {};
            foreach (var t in m.tables) r += t.name;
            return r;
        }

        private static string[] column_names (DataModel m, uint index) {
            string[] r = {};
            if (index < m.tables.size) foreach (var c in m.tables[(int) index].columns) r += c;
            return r;
        }

        private static void link_columns (DataModel m, DropDown tables, DropDown columns) {
            tables.notify["selected"].connect (() => {
                columns.model = new StringList (column_names (m, tables.selected));
                columns.selected = 0;
            });
        }

        private static string picked (DropDown dd) {
            var item = dd.selected_item as StringObject;
            return item != null ? item.string : "";
        }

        private static Button remove_button () {
            var del = new Button.from_icon_name ("user-trash-symbolic");
            del.add_css_class ("flat");
            del.valign = Align.CENTER;
            del.tooltip_text = _("Remove");
            return del;
        }

        private static Button add_button () {
            var b = new Button.with_label (_("Add"));
            b.add_css_class ("suggested-action");
            b.halign = Align.END;
            return b;
        }

        private static string aggregation_label (string agg) {
            switch (agg) {
                case "COUNT": return _("Count");
                case "AVERAGE": return _("Average");
                case "MIN": return _("Minimum");
                case "MAX": return _("Maximum");
                case "DISTINCTCOUNT": return _("Distinct Count");
                case "FORMULA": return _("Formula");
                default: return _("Sum");
            }
        }

        public static void open (SpreadsheetWindow win) {
            var dlg = Dialogs.make (win, _("Data Model"), 620, 700);
            var box = Dialogs.body (dlg);
            var holder = new Box (Orientation.VERTICAL, 14);
            box.append (holder);
            Dialogs.Apply refill = null;
            refill = () => {
                Widget? child;
                while ((child = holder.get_first_child ()) != null) holder.remove (child);
                var model = DataModel.build (win.doc.book);
                string[] tnames = table_names (model);

                var tables = new PreferencesGroup (_("Tables"), _("Structured tables form the model. Use it in cells with CUBEVALUE(\"ThisWorkbookDataModel\", ...)."));
                foreach (var t in model.tables) {
                    tables.add_row (new ActionRow (t.name, _("%d rows").printf (t.rows) + "  " + string.joinv (", ", t.columns.to_array ())));
                }
                if (model.tables.size == 0) tables.add_row (new ActionRow (_("No tables yet"), _("Format a range as a table to add it to the data model.")));
                holder.append (tables);

                var rels = new PreferencesGroup (_("Relationships"));
                var infer = new SwitchRow (_("Detect Relationships"), _("Link tables that share a column whose values are unique in one of them"), model.infer);
                infer.switch_btn.notify["active"].connect (() => {
                    if (infer.active == model.infer) return;
                    model.infer = infer.active;
                    save (win, model);
                    refill ();
                });
                rels.add_row (infer);
                foreach (var r in model.relationships) {
                    var rel = r;
                    var row = new ActionRow (_("%s[%s] to %s[%s]").printf (r.from_table, r.from_column, r.to_table, r.to_column), r.inferred ? _("Detected") : _("Declared"));
                    if (!r.inferred) {
                        var del = remove_button ();
                        del.clicked.connect (() => {
                            model.relationships.remove (rel);
                            save (win, model);
                            refill ();
                        });
                        row.add_suffix (del);
                    }
                    rels.add_row (row);
                }
                holder.append (rels);
                if (model.tables.size > 1) {
                    var add_rel = new PreferencesGroup (_("Add a Relationship"), _("Each row of the first table points to one row of the second table."));
                    var ft = pick (tnames);
                    var fc = pick (column_names (model, 0));
                    link_columns (model, ft, fc);
                    var from_row = new ActionRow (_("From"), _("Table and column with repeated keys"));
                    from_row.add_suffix (ft);
                    from_row.add_suffix (fc);
                    add_rel.add_row (from_row);
                    var tt = pick (tnames);
                    tt.selected = 1;
                    var tc = pick (column_names (model, 1));
                    link_columns (model, tt, tc);
                    var to_row = new ActionRow (_("To"), _("Table and column with unique keys"));
                    to_row.add_suffix (tt);
                    to_row.add_suffix (tc);
                    add_rel.add_row (to_row);
                    holder.append (add_rel);
                    var add = add_button ();
                    add.clicked.connect (() => {
                        if (ft.selected == tt.selected) return;
                        model.relationships.add (new ModelRelationship (picked (ft), picked (fc), picked (tt), picked (tc)));
                        save (win, model);
                        refill ();
                    });
                    holder.append (add);
                }

                var measures = new PreferencesGroup (_("Measures"), _("Sum of, Count of, Average of, Min of, Max of and Distinct Count of any column are always available."));
                foreach (var ms in model.measures) {
                    var m = ms;
                    string detail = ms.aggregation == "FORMULA" ? ms.formula : "%s  %s[%s]".printf (aggregation_label (ms.aggregation), ms.table, ms.column);
                    var row = new ActionRow (ms.name, detail);
                    var del = remove_button ();
                    del.clicked.connect (() => {
                        model.measures.remove (m);
                        save (win, model);
                        refill ();
                    });
                    row.add_suffix (del);
                    measures.add_row (row);
                }
                if (model.measures.size == 0) measures.add_row (new ActionRow (_("No measures yet"), _("Name a calculation to reuse it in cube formulas and KPIs.")));
                holder.append (measures);
                if (model.tables.size > 0) {
                    var add_m = new PreferencesGroup (_("Add a Measure"));
                    var name_row = new EntryRow (_("Name"));
                    add_m.add_row (name_row);
                    string[] aggs = { "SUM", "COUNT", "AVERAGE", "MIN", "MAX", "DISTINCTCOUNT", "FORMULA" };
                    string[] agg_labels = {};
                    foreach (string g in aggs) agg_labels += aggregation_label (g);
                    var agg = pick (agg_labels);
                    var agg_row = new ActionRow (_("Calculation"));
                    agg_row.add_suffix (agg);
                    add_m.add_row (agg_row);
                    var mt = pick (tnames);
                    var mc = pick (column_names (model, 0));
                    link_columns (model, mt, mc);
                    var col_row = new ActionRow (_("Column"));
                    col_row.add_suffix (mt);
                    col_row.add_suffix (mc);
                    add_m.add_row (col_row);
                    var formula_row = new EntryRow (_("Formula, for example [Revenue]/[Count of Amount]"));
                    formula_row.visible = false;
                    add_m.add_row (formula_row);
                    agg.notify["selected"].connect (() => {
                        bool is_formula = aggs[agg.selected] == "FORMULA";
                        formula_row.visible = is_formula;
                        col_row.visible = !is_formula;
                    });
                    holder.append (add_m);
                    var add = add_button ();
                    add.clicked.connect (() => {
                        string n = name_row.text.strip ();
                        if (n == "" || n.contains ("[") || n.contains ("]")) return;
                        var ms = new ModelMeasure (n, picked (mt), picked (mc), aggs[agg.selected]);
                        if (ms.aggregation == "FORMULA") {
                            ms.formula = formula_row.text.strip ();
                            ms.table = "";
                            ms.column = "";
                            if (ms.formula == "") return;
                        }
                        model.measures.add (ms);
                        save (win, model);
                        refill ();
                    });
                    holder.append (add);
                }

                var kpis = new PreferencesGroup (_("KPIs"), _("Compare a measure with a goal. The status is 1 at or above the upper threshold, 0 between thresholds and -1 below."));
                foreach (var k in model.kpis) {
                    var kp = k;
                    string goal = k.goal_measure != "" ? k.goal_measure : Value.format_number_general (k.goal);
                    var row = new ActionRow (k.name, _("%s against %s, thresholds %s and %s").printf (k.value_measure, goal, Value.format_number_general (k.low), Value.format_number_general (k.high)));
                    var del = remove_button ();
                    del.clicked.connect (() => {
                        model.kpis.remove (kp);
                        save (win, model);
                        refill ();
                    });
                    row.add_suffix (del);
                    kpis.add_row (row);
                }
                if (model.kpis.size == 0) kpis.add_row (new ActionRow (_("No KPIs yet"), _("Add a measure first, then track it against a goal.")));
                holder.append (kpis);
                if (model.measures.size > 0) {
                    var add_k = new PreferencesGroup (_("Add a KPI"));
                    var kname = new EntryRow (_("Name"));
                    add_k.add_row (kname);
                    string[] mnames = {};
                    foreach (var ms in model.measures) mnames += ms.name;
                    var kmeasure = pick (mnames);
                    var kmeasure_row = new ActionRow (_("Measure"));
                    kmeasure_row.add_suffix (kmeasure);
                    add_k.add_row (kmeasure_row);
                    var kgoal = new EntryRow (_("Goal, a number or a measure name"));
                    add_k.add_row (kgoal);
                    var klow = new EntryRow (_("Lower threshold as a share of the goal"));
                    klow.text = "0.8";
                    add_k.add_row (klow);
                    var khigh = new EntryRow (_("Upper threshold as a share of the goal"));
                    khigh.text = "1";
                    add_k.add_row (khigh);
                    holder.append (add_k);
                    var add = add_button ();
                    add.clicked.connect (() => {
                        string n = kname.text.strip ();
                        string g = kgoal.text.strip ();
                        if (n == "" || g == "") return;
                        var k = new ModelKpi ();
                        k.name = n;
                        k.value_measure = picked (kmeasure);
                        double d;
                        string f;
                        if (Input.parse_number (g, out d, out f)) k.goal = d;
                        else k.goal_measure = g;
                        if (Input.parse_number (klow.text.strip (), out d, out f)) k.low = d;
                        if (Input.parse_number (khigh.text.strip (), out d, out f)) k.high = d;
                        model.kpis.add (k);
                        save (win, model);
                        refill ();
                    });
                    holder.append (add);
                }
            };
            refill ();
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
    }
}
