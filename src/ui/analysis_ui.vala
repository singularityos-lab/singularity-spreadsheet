using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class StructRefPlain {
        public static bool is_plain (string s) {
            if (s.length == 0 || !(s[0].isalpha () || s[0] == '_')) return false;
            for (int i = 0; i < s.length; i++) if (!(s[i].isalnum () || s[i] == '_' || (uchar) s[i] >= 0x80)) return false;
            return true;
        }
    }

    public class AnalysisUi {
        public delegate void Act ();

        private static void act (SpreadsheetWindow win, string name, owned Act handler) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => {
                if (win.doc == null || win.grid == null) return;
                handler ();
            });
            win.add_action (a);
        }

        private static bool styled;

        private const string CSS = """
.ss-pivot-panel {
    margin: 0 12px 0 0;
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.1);
}

.ss-query-preview {
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.1);
}

.ss-query-head {
    background: alpha(@window_fg_color, 0.06);
    border-bottom: 1px solid alpha(@window_fg_color, 0.12);
    border-right: 1px solid alpha(@window_fg_color, 0.06);
}

.ss-query-cell {
    border-bottom: 1px solid alpha(@window_fg_color, 0.05);
    border-right: 1px solid alpha(@window_fg_color, 0.05);
}
""";

        public static void install (SpreadsheetWindow win) {
            if (!styled) {
                styled = true;
                var provider = new CssProvider ();
                provider.load_from_string (CSS);
                StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_APPLICATION);
            }
            act (win, "pivot-insert", () => create_pivot (win));
            act (win, "pivot-refresh", () => {
                win.doc.begin_book (_("Refresh Pivot Tables"), win.grid.sheet);
                Analysis.refresh_all (win.doc.book);
                win.doc.commit ();
            });
            act (win, "goal-seek", () => goal_seek (win));
            act (win, "scenarios", () => scenarios (win));
            act (win, "data-table", () => data_table (win));
            act (win, "solver", () => solver (win));
            act (win, "get-data", () => get_data (win));
            act (win, "queries", () => queries (win));
            act (win, "refresh-all", () => refresh_all (win));
            act (win, "data-analysis", () => data_analysis (win));
            act (win, "forecast-sheet", () => forecast (win));
            act (win, "subtotals", () => subtotals (win));
            act (win, "consolidate", () => consolidate (win));
            act (win, "advanced-filter", () => advanced_filter (win));
            act (win, "data-type-convert", () => data_type_convert (win));
            act (win, "data-type-geography", () => convert_linked (win, "geography"));
            act (win, "data-type-stocks", () => convert_linked (win, "stocks"));
            act (win, "data-type-refresh", () => refresh_linked (win));
            LinkedHub.get ().async_mode = true;
            LinkedHub.get ().updated.connect ((b) => {
                if (win.doc == null || win.doc.book != b) return;
                b.recalculate ();
                if (win.grid != null) win.grid.refresh ();
            });
            act (win, "data-type-card", () => data_type_card (win));
            act (win, "data-type-field", () => data_type_field (win));
            act (win, "pivot-panel", () => {
                var panel = panel_of (win);
                if (panel != null) panel.toggle_for (Analysis.data (win.doc.book).pivot_at (win.grid.sheet, win.grid.cur_row, win.grid.cur_col));
            });
        }

        public static void extend_menu (GLib.Menu data) {
            var tools = new GLib.Menu ();
            tools.append (_("PivotTable…"), "win.pivot-insert");
            tools.append (_("PivotTable Fields"), "win.pivot-panel");
            tools.append (_("Refresh Pivot Tables"), "win.pivot-refresh");
            data.append_section (null, tools);
            var types = new GLib.Menu ();
            types.append (_("Geography"), "win.data-type-geography");
            types.append (_("Stocks"), "win.data-type-stocks");
            types.append (_("From a Table or Query…"), "win.data-type-convert");
            types.append (_("Refresh Data Types"), "win.data-type-refresh");
            types.append (_("Show Data Card"), "win.data-type-card");
            types.append (_("Insert Data Field…"), "win.data-type-field");
            var types_section = new GLib.Menu ();
            types_section.append_submenu (_("Data Types"), types);
            data.append_section (null, types_section);
            var get = new GLib.Menu ();
            get.append (_("Get Data…"), "win.get-data");
            get.append (_("Queries and Connections…"), "win.queries");
            get.append (_("Refresh All"), "win.refresh-all");
            data.append_section (null, get);
            var whatif = new GLib.Menu ();
            whatif.append (_("Goal Seek…"), "win.goal-seek");
            whatif.append (_("Scenario Manager…"), "win.scenarios");
            whatif.append (_("Data Table…"), "win.data-table");
            var wi_section = new GLib.Menu ();
            wi_section.append_submenu (_("What-If Analysis"), whatif);
            wi_section.append (_("Solver…"), "win.solver");
            wi_section.append (_("Forecast Sheet…"), "win.forecast-sheet");
            wi_section.append (_("Data Analysis…"), "win.data-analysis");
            data.append_section (null, wi_section);
            var outline = new GLib.Menu ();
            outline.append (_("Subtotal…"), "win.subtotals");
            outline.append (_("Consolidate…"), "win.consolidate");
            outline.append (_("Advanced Filter…"), "win.advanced-filter");
            data.append_section (null, outline);
        }

        public static Widget wrap_grid (SpreadsheetWindow win, Widget grid_scroll) {
            var box = new Box (Orientation.HORIZONTAL, 0);
            box.hexpand = true;
            box.vexpand = true;
            box.append (grid_scroll);
            var panel = new PivotPanel (win);
            panel.visible = false;
            box.append (panel);
            win.set_data<PivotPanel> ("ss-pivot-panel", panel);
            return box;
        }

        public static PivotPanel? panel_of (SpreadsheetWindow win) {
            return win.get_data<PivotPanel> ("ss-pivot-panel");
        }

        public static string sel_text (SpreadsheetWindow win, Area? a = null) {
            var area = a ?? win.grid.selection;
            return Analysis.area_ref (area, null);
        }

        private static string cur_cell (SpreadsheetWindow win) {
            return Address.quote_sheet (win.grid.sheet.name) + "!" + Address.cell (win.grid.cur_row, win.grid.cur_col, true, true);
        }

        private static Area region (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            var a = sel.is_single () ? win.doc.current_region (s, sel.r1, sel.c1) : Document.clamp_area (s, sel);
            if (a.r2 > s.max_row) a.r2 = int.max (s.max_row, a.r1);
            if (a.c2 > s.max_col) a.c2 = int.max (s.max_col, a.c1);
            return a;
        }

        public static void show_sheet (SpreadsheetWindow win, Sheet s) {
            win.grid.show_sheet (s);
            win.doc.sheets_changed ();
            win.grid.refresh ();
        }

        private static void info (SpreadsheetWindow win, string title, string message) {
            var done = new ConfirmDialog ((Gtk.Application) win.application, title, "object-select-symbolic", message, _("OK"), ConfirmDialog.ActionStyle.SUGGESTED);
            done.transient_for = win;
            done.present ();
        }

        public static void create_pivot (SpreadsheetWindow win) {
            var book = win.doc.book;
            var existing = Analysis.data (book).pivot_at (win.grid.sheet, win.grid.cur_row, win.grid.cur_col);
            if (existing != null) {
                panel_of (win).show_for (existing);
                return;
            }
            var f = new AnalysisForm (win, _("Create PivotTable"), 460, 520);
            f.section (_("Data"), _("A range with a header row, or the name of a table."));
            var src = f.entry (_("Table or range"), sel_text (win, region (win)));
            f.section (_("Place the PivotTable"));
            string[] places = { _("New Sheet"), _("Existing Sheet") };
            var place = f.choice (_("Location"), places, places[0]);
            var dest = f.entry (_("Destination cell"), "");
            f.footer (_("Create"), () => {
                var a = Analysis.parse_area (book, src.text, win.grid.sheet);
                if (a == null || a.rows < 2) {
                    f.fail (_("Choose a range with a header row and at least one row of data."));
                    return false;
                }
                win.doc.begin_book (_("Insert PivotTable"), win.grid.sheet);
                Sheet ts;
                int tr = 0, tc = 0;
                if (place.current_value == places[1]) {
                    var cr = CellRef.parse (book, dest.text, win.grid.sheet);
                    if (cr == null) {
                        win.doc.commit ();
                        f.fail (_("Type a destination cell such as $H$2."));
                        return false;
                    }
                    ts = cr.sheet;
                    tr = cr.row;
                    tc = cr.col;
                } else {
                    ts = book.add_sheet (book.unique_sheet_name (_("Pivot")), book.sheets.index_of (a.sheet));
                    tr = 2;
                    tc = 0;
                }
                var p = new PivotTable (Analysis.data (book).unique_pivot_name (), ts, tr, tc);
                var t = Tables.at (book, a.sheet, a.r1, a.c1);
                if (t != null && t.area.r1 == a.r1 && t.area.c1 == a.c1 && t.area.c2 == a.c2) p.source_table = t.name;
                else p.source = a;
                p.source_sheet = a.sheet;
                Analysis.data (book).pivots.add (p);
                Analysis.write_pivot (book, p);
                win.doc.commit ();
                show_sheet (win, ts);
                win.grid.select_area (new Area.cell (ts, tr, tc));
                panel_of (win).show_for (p);
                return true;
            });
            f.open ();
        }

        public static void goal_seek (SpreadsheetWindow win) {
            var book = win.doc.book;
            var f = new AnalysisForm (win, _("Goal Seek"), 440, 500);
            f.section (null, _("Finds the input value that makes a formula reach a result."));
            var set_cell = f.entry (_("Set cell"), cur_cell (win));
            var to_value = f.entry (_("To value"), "");
            var by_cell = f.entry (_("By changing cell"), "");
            f.footer (_("Find"), () => {
                var target = CellRef.parse (book, set_cell.text, win.grid.sheet);
                var changing = CellRef.parse (book, by_cell.text, win.grid.sheet);
                double goal;
                string fmt;
                if (target == null || changing == null) {
                    f.fail (_("Type cell references such as $B$4."));
                    return false;
                }
                if (!Input.parse_number (to_value.text.strip (), out goal, out fmt)) {
                    f.fail (_("Type the value to reach."));
                    return false;
                }
                var tc = target.sheet.get_cell (target.row, target.col);
                if (tc == null || tc.formula == null) {
                    f.fail (_("The cell to set must contain a formula."));
                    return false;
                }
                var cc = changing.sheet.get_cell (changing.row, changing.col);
                if (cc != null && cc.formula != null) {
                    f.fail (_("The changing cell must contain a value, not a formula."));
                    return false;
                }
                string old_input = changing.input ();
                var old_value = changing.value ();
                win.doc.begin_area (_("Goal Seek"), changing.sheet, new Area.cell (changing.sheet, changing.row, changing.col));
                double result, reached;
                bool ok = WhatIf.goal_seek (book, target, goal, changing, out result, out reached);
                win.doc.commit ();
                win.grid.refresh ();
                var confirm = new ConfirmDialog ((Gtk.Application) win.application, _("Goal Seek Status"), ok ? "object-select-symbolic" : "dialog-warning-symbolic",
                    (ok ? _("Goal Seeking with cell %s found a solution.") : _("Goal Seeking with cell %s may not have found a solution.")).printf (target.label (win.grid.sheet)) + "\n" +
                    _("Target value: %s\nCurrent value: %s").printf (Value.format_number_general (goal), Value.format_number_general (reached)),
                    _("Keep"), ConfirmDialog.ActionStyle.SUGGESTED);
                confirm.transient_for = win;
                confirm.set_secondary (_("Restore Original Values"));
                confirm.response.connect ((r) => {
                    if (r != ConfirmDialog.Response.PRIMARY) {
                        win.doc.undo ();
                        win.grid.refresh ();
                    }
                });
                confirm.present ();
                return true;
            });
            f.open ();
        }

        public static void scenarios (SpreadsheetWindow win) {
            var book = win.doc.book;
            var data = Analysis.data (book);
            var f = new AnalysisForm (win, _("Scenario Manager"), 480, 540);
            var list = f.section (_("Scenarios"));
            AnalysisForm.Submit refill = null;
            refill = () => {
                list.clear ();
                int count = 0;
                foreach (var sc in data.scenarios) {
                    if (sc.sheet != win.grid.sheet) continue;
                    count++;
                    string[] cells = {};
                    foreach (var c in sc.cells) cells += c.label (win.grid.sheet);
                    var row = new ActionRow (sc.name, _("Changing cells: %s").printf (string.joinv (", ", cells)));
                    var show = new Button.with_label (_("Show"));
                    show.valign = Align.CENTER;
                    var scenario = sc;
                    show.clicked.connect (() => {
                        win.doc.begin_book (_("Show Scenario"), win.grid.sheet);
                        scenario.show (book);
                        win.doc.commit ();
                        win.grid.refresh ();
                    });
                    row.add_suffix (show);
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete Scenario");
                    del.clicked.connect (() => {
                        data.scenarios.remove (scenario);
                        win.doc.modified = true;
                        refill ();
                    });
                    row.add_suffix (del);
                    list.add_row (row);
                }
                if (count == 0) list.add_row (new ActionRow (_("No scenarios yet"), _("Add one with the changing cells and their values.")));
                return true;
            };
            refill ();
            f.section (_("Add Scenario"));
            var name = f.entry (_("Scenario name"), _("Scenario %d").printf (data.scenarios.size + 1));
            var cells_e = f.entry (_("Changing cells"), sel_text (win));
            var values_e = f.entry (_("Values, separated by semicolons"), "");
            var add = new Button.with_label (_("Add Scenario"));
            add.halign = Align.END;
            add.clicked.connect (() => {
                var a = Analysis.parse_area (book, cells_e.text, win.grid.sheet);
                if (a == null || name.text.strip () == "") {
                    f.fail (_("Type a name and the changing cells."));
                    return;
                }
                var sc = new Scenario (name.text.strip (), win.grid.sheet);
                string[] vals = values_e.text.split (";");
                int i = 0;
                for (int r = a.r1; r <= a.r2; r++) for (int c = a.c1; c <= a.c2; c++) {
                    sc.cells.add (new CellRef (a.sheet, r, c));
                    sc.values.add (i < vals.length && vals[i].strip () != "" ? vals[i].strip () : a.sheet.input_at (r, c));
                    i++;
                }
                data.scenarios.add (sc);
                win.doc.modified = true;
                name.text = _("Scenario %d").printf (data.scenarios.size + 1);
                values_e.text = "";
                refill ();
            });
            f.body.append (add);
            f.section (_("Summary"));
            var results = f.entry (_("Result cells"), cur_cell (win));
            f.footer (_("Close"), () => true, _("Summary"), () => {
                var list_sc = new Gee.ArrayList<Scenario> ();
                foreach (var sc in data.scenarios) if (sc.sheet == win.grid.sheet) list_sc.add (sc);
                var res = new Gee.ArrayList<CellRef> ();
                var ra = Analysis.parse_area (book, results.text, win.grid.sheet);
                if (ra != null) for (int r = ra.r1; r <= ra.r2; r++) for (int c = ra.c1; c <= ra.c2; c++) res.add (new CellRef (ra.sheet, r, c));
                if (list_sc.size == 0) {
                    f.fail (_("Add at least one scenario first."));
                    return false;
                }
                win.doc.begin_book (_("Scenario Summary"), win.grid.sheet);
                var s = Scenario.summary (book, list_sc, res);
                win.doc.commit ();
                show_sheet (win, s);
                return true;
            });
            f.open ();
        }

        public static void data_table (SpreadsheetWindow win) {
            var book = win.doc.book;
            var sel = Document.clamp_area (win.grid.sheet, win.grid.selection);
            var f = new AnalysisForm (win, _("Data Table"), 440, 460);
            f.section (_("Table %s").printf (sel_text (win, sel)), _("Select the whole table: the formulas and the input values along the top row and the left column."));
            var row_in = f.entry (_("Row input cell"), "");
            var col_in = f.entry (_("Column input cell"), "");
            f.footer (_("Create"), () => {
                var r = row_in.text.strip () == "" ? null : CellRef.parse (book, row_in.text, win.grid.sheet);
                var c = col_in.text.strip () == "" ? null : CellRef.parse (book, col_in.text, win.grid.sheet);
                if (r == null && c == null) {
                    f.fail (_("Type a row input cell, a column input cell or both."));
                    return false;
                }
                if (sel.rows < 2 || sel.cols < 2) {
                    f.fail (_("Select at least two rows and two columns."));
                    return false;
                }
                win.doc.begin_book (_("Data Table"), win.grid.sheet);
                var dt = new DataTableDef (win.grid.sheet, sel);
                dt.row_input = r;
                dt.col_input = c;
                Analysis.data (book).data_tables.add (dt);
                dt.compute (book);
                win.doc.commit ();
                win.grid.refresh ();
                return true;
            });
            f.open ();
        }

        private static string[] goal_items () {
            return { _("Max"), _("Min"), _("Value Of") };
        }

        private static string[] method_items () {
            return { _("Simplex LP"), _("GRG Nonlinear"), _("Evolutionary") };
        }

        private static string[] op_items () {
            return { "<=", ">=", "=", "int", "bin", "dif" };
        }

        public static void solver (SpreadsheetWindow win) {
            var book = win.doc.book;
            var sheet = win.grid.sheet;
            var model = SolverModel.from_names (sheet) ?? new SolverModel (sheet);
            if (model.objective == "") model.objective = Address.cell (win.grid.cur_row, win.grid.cur_col, true, true);
            var f = new AnalysisForm (win, _("Solver Parameters"), 520, 640);
            f.section (_("Objective"));
            var obj = f.entry (_("Set objective"), model.objective);
            var goal = f.choice (_("To"), goal_items (), goal_items ()[(int) model.goal]);
            var target = f.entry (_("Value of"), Value.format_number_general (model.target));
            var vars = f.entry (_("By changing variable cells"), model.variables);
            var cons_group = f.section (_("Subject to the constraints"));
            var cons = new Gee.ArrayList<SolverConstraint> ();
            cons.add_all (model.constraints);
            AnalysisForm.Submit refill = null;
            refill = () => {
                cons_group.clear ();
                if (cons.size == 0) cons_group.add_row (new ActionRow (_("No constraints")));
                foreach (var c in cons) {
                    string rhs = c.op == ConstraintOp.INT || c.op == ConstraintOp.BIN || c.op == ConstraintOp.DIF ? "" : " " + c.rhs;
                    var row = new ActionRow ("%s %s%s".printf (c.lhs, c.op.symbol (), rhs));
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete Constraint");
                    var cc = c;
                    del.clicked.connect (() => {
                        cons.remove (cc);
                        refill ();
                    });
                    row.add_suffix (del);
                    cons_group.add_row (row);
                }
                return true;
            };
            refill ();
            f.section (_("Add Constraint"));
            var lhs = f.entry (_("Cell reference"), "");
            var op = f.choice (_("Relation"), op_items (), "<=");
            var rhs = f.entry (_("Constraint"), "");
            var add = new Button.with_label (_("Add Constraint"));
            add.halign = Align.END;
            add.clicked.connect (() => {
                if (lhs.text.strip () == "") return;
                var cop = ConstraintOp.parse (op.current_value);
                bool needs_rhs = cop != ConstraintOp.INT && cop != ConstraintOp.BIN && cop != ConstraintOp.DIF;
                if (needs_rhs && rhs.text.strip () == "") {
                    f.fail (_("Type the constraint value or cell."));
                    return;
                }
                cons.add (new SolverConstraint (lhs.text.strip (), cop, needs_rhs ? rhs.text.strip () : ""));
                lhs.text = "";
                rhs.text = "";
                refill ();
            });
            f.body.append (add);
            f.section (_("Options"));
            var nonneg = f.toggle (_("Make unconstrained variables non-negative"), model.nonneg);
            var method = f.choice (_("Solving method"), method_items (), method_items ()[(int) model.method]);
            var report = f.toggle (_("Answer report"), false, _("Adds a sheet with the result, the variables and the constraints"));
            f.footer (_("Solve"), () => {
                model.objective = obj.text.strip ();
                string[] gi = goal_items ();
                model.goal = goal.current_value == gi[1] ? SolverGoal.MIN : goal.current_value == gi[2] ? SolverGoal.VALUE : SolverGoal.MAX;
                double tv;
                string fmt;
                model.target = Input.parse_number (target.text.strip (), out tv, out fmt) ? tv : 0;
                model.variables = vars.text.strip ();
                model.constraints.clear ();
                model.constraints.add_all (cons);
                model.nonneg = nonneg.active;
                string[] mi = method_items ();
                model.method = method.current_value == mi[1] ? SolverMethod.NONLINEAR : method.current_value == mi[2] ? SolverMethod.EVOLUTIONARY : SolverMethod.SIMPLEX;
                if (model.objective == "" || model.variables == "") {
                    f.fail (_("Set an objective cell and the variable cells."));
                    return false;
                }
                win.doc.begin_book (_("Solver"), sheet);
                model.to_names ();
                var res = model.solve (book, true);
                Sheet? rep = null;
                if (res.ok && report.active) rep = model.answer_report (book, res);
                win.doc.commit ();
                win.grid.refresh ();
                if (rep != null) show_sheet (win, rep);
                var confirm = new ConfirmDialog ((Gtk.Application) win.application, _("Solver Results"), res.ok ? "object-select-symbolic" : "dialog-warning-symbolic",
                    res.message + (res.ok ? "\n" + _("Objective: %s").printf (Value.format_number_general (res.objective)) : ""),
                    _("Keep Solver Solution"), ConfirmDialog.ActionStyle.SUGGESTED);
                confirm.transient_for = win;
                confirm.set_secondary (_("Restore Original Values"));
                confirm.response.connect ((r) => {
                    if (r != ConfirmDialog.Response.PRIMARY) {
                        win.doc.undo ();
                        win.grid.refresh ();
                    }
                });
                confirm.present ();
                return true;
            }, _("Reset All"), () => {
                obj.text = "";
                vars.text = "";
                cons.clear ();
                refill ();
                return false;
            });
            f.open ();
        }

        public static void get_data (SpreadsheetWindow win) {
            var book = win.doc.book;
            var f = new AnalysisForm (win, _("Get Data"), 480, 480);
            string[] kinds = QueryDef.source_kinds ();
            string[] labels = {};
            foreach (string k in kinds) labels += QueryDef.source_label (k);
            f.section (_("Source"));
            var kind = f.choice (_("Source"), labels, labels[0]);
            var loc = f.entry (_("File, address, range or query"), "");
            var browse = new Button.with_label (_("Choose File…"));
            browse.halign = Align.END;
            browse.clicked.connect (() => {
                var dialog = new FileDialog ();
                dialog.title = _("Choose a Data File");
                dialog.open.begin (win, null, (obj, res) => {
                    try {
                        var file = dialog.open.end (res);
                        if (file != null) loc.text = file.get_path () ?? file.get_uri ();
                    } catch (Error e) {
                    }
                });
            });
            f.body.append (browse);
            f.section (_("Options"));
            var extra = f.entry (_("Delimiter, SQL query or table number"), "");
            var name = f.entry (_("Query name"), _("Query%d").printf (Analysis.data (book).queries.size + 1));
            f.footer (_("Transform Data"), () => {
                string k = kinds[0];
                for (int i = 0; i < labels.length; i++) if (labels[i] == kind.current_value) k = kinds[i];
                if (loc.text.strip () == "") {
                    f.fail (_("Choose where the data comes from."));
                    return false;
                }
                var q = new QueryDef (name.text.strip () == "" ? _("Query") : name.text.strip ());
                q.source_kind = k;
                q.location = loc.text.strip ();
                if (k == "sqlite") q.sql = extra.text.strip ();
                else q.delimiter = extra.text.strip ();
                if (k == "csv" || k == "tsv") q.steps.add (new QueryStep ("promote-headers"));
                if (k == "range" && Tables.find (book, q.location) == null) q.steps.add (new QueryStep ("promote-headers"));
                q.load = true;
                QueryEditor.open (win, q, true);
                return true;
            });
            f.open ();
        }

        public static void queries (SpreadsheetWindow win) {
            var book = win.doc.book;
            var data = Analysis.data (book);
            var f = new AnalysisForm (win, _("Queries and Connections"), 480, 480);
            var group = f.section (_("Queries"));
            AnalysisForm.Submit refill = null;
            refill = () => {
                group.clear ();
                if (data.queries.size == 0) group.add_row (new ActionRow (_("No queries yet"), _("Use Get Data to import from a file, the web or a database.")));
                foreach (var q in data.queries) {
                    string sub = QueryDef.source_label (q.source_kind) + (q.last_refresh != "" ? ", " + _("refreshed %s").printf (q.last_refresh) : "");
                    if (q.error != "") sub = q.error;
                    var row = new ActionRow (q.name, sub);
                    var query = q;
                    var edit = new Button.from_icon_name ("document-edit-symbolic");
                    edit.add_css_class ("flat");
                    edit.valign = Align.CENTER;
                    edit.tooltip_text = _("Edit");
                    edit.clicked.connect (() => {
                        f.dlg.close ();
                        QueryEditor.open (win, query, false);
                    });
                    row.add_suffix (edit);
                    var refresh = new Button.from_icon_name ("view-refresh-symbolic");
                    refresh.add_css_class ("flat");
                    refresh.valign = Align.CENTER;
                    refresh.tooltip_text = _("Refresh");
                    refresh.clicked.connect (() => {
                        win.doc.begin_book (_("Refresh Query"), win.grid.sheet);
                        try {
                            Analysis.load_query (book, query);
                        } catch (Error e) {
                            query.error = e.message;
                        }
                        win.doc.commit ();
                        win.doc.sheets_changed ();
                        refill ();
                    });
                    row.add_suffix (refresh);
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Delete");
                    del.clicked.connect (() => {
                        data.queries.remove (query);
                        win.doc.modified = true;
                        refill ();
                    });
                    row.add_suffix (del);
                    group.add_row (row);
                }
                return true;
            };
            refill ();
            f.footer (_("Close"), () => true, _("Refresh All"), () => {
                refresh_all (win);
                refill ();
                return false;
            });
            f.open ();
        }

        public static void refresh_all (SpreadsheetWindow win) {
            var book = win.doc.book;
            win.doc.begin_book (_("Refresh All"), win.grid.sheet);
            string errors;
            Analysis.refresh_queries (book, out errors);
            Analysis.refresh_all (book);
            Analysis.data (book).run_data_tables ();
            LinkedHub.get ().refresh_async (book);
            win.doc.commit ();
            win.doc.sheets_changed ();
            win.grid.refresh ();
            if (errors != "") win.show_error (_("Some Queries Failed"), errors);
        }

        private static string[] tool_items () {
            return { _("Descriptive Statistics"), _("Histogram"), _("Correlation"), _("Covariance"), _("Regression"), _("Moving Average"), _("Sampling"),
                _("t-Test: Paired Two Sample for Means"), _("t-Test: Two-Sample Assuming Equal Variances"), _("t-Test: Two-Sample Assuming Unequal Variances"), _("F-Test Two-Sample for Variances") };
        }

        public static void data_analysis (SpreadsheetWindow win) {
            var book = win.doc.book;
            string[] tools = tool_items ();
            var f = new AnalysisForm (win, _("Data Analysis"), 480, 560);
            f.section (_("Tool"));
            var tool = f.choice (_("Analysis tool"), tools, tools[0]);
            f.section (_("Input"), _("Results go to a new sheet."));
            var in1 = f.entry (_("Input range (or Y range)"), sel_text (win, region (win)));
            var in2 = f.entry (_("Second range (X range, bins or variable 2)"), "");
            var labels = f.toggle (_("Labels in first row"), true);
            var param = f.entry (_("Interval, sample size or alpha"), "");
            var chart = f.toggle (_("Chart output"), false);
            f.footer (_("Run"), () => {
                var a1 = Analysis.parse_area (book, in1.text, win.grid.sheet);
                var a2 = in2.text.strip () == "" ? null : Analysis.parse_area (book, in2.text, win.grid.sheet);
                if (a1 == null) {
                    f.fail (_("Type a valid input range."));
                    return false;
                }
                double pv;
                string fmt;
                bool has_param = Input.parse_number (param.text.strip (), out pv, out fmt);
                int idx = 0;
                for (int i = 0; i < tools.length; i++) if (tools[i] == tool.current_value) idx = i;
                if ((idx == 4 || idx >= 7) && a2 == null) {
                    f.fail (_("This tool needs a second range."));
                    return false;
                }
                win.doc.begin_book (tools[idx], win.grid.sheet);
                Sheet out_s;
                switch (idx) {
                    case 1: out_s = Analysis.histogram (book, a1, a2, labels.active, chart.active); break;
                    case 2: out_s = Analysis.matrix (book, a1, labels.active, false); break;
                    case 3: out_s = Analysis.matrix (book, a1, labels.active, true); break;
                    case 4: out_s = Analysis.regression (book, a1, a2, labels.active, has_param ? 1 - pv : 0.95); break;
                    case 5: out_s = Analysis.moving_average (book, a1, has_param ? int.max (1, (int) pv) : 3, labels.active); break;
                    case 6: out_s = Analysis.sampling (book, a1, false, has_param ? int.max (1, (int) pv) : 10); break;
                    case 7: out_s = Analysis.t_test (book, a1, a2, Analysis.TTest.PAIRED, labels.active, has_param ? pv : 0.05); break;
                    case 8: out_s = Analysis.t_test (book, a1, a2, Analysis.TTest.EQUAL, labels.active, has_param ? pv : 0.05); break;
                    case 9: out_s = Analysis.t_test (book, a1, a2, Analysis.TTest.UNEQUAL, labels.active, has_param ? pv : 0.05); break;
                    case 10: out_s = Analysis.f_test (book, a1, a2, labels.active, has_param ? pv : 0.05); break;
                    default: out_s = Analysis.descriptive (book, a1, labels.active); break;
                }
                win.doc.commit ();
                show_sheet (win, out_s);
                return true;
            });
            f.open ();
        }

        public static void forecast (SpreadsheetWindow win) {
            var book = win.doc.book;
            var a = region (win);
            var f = new AnalysisForm (win, _("Create Forecast Worksheet"), 460, 440);
            f.section (_("Data"), _("A timeline column and a values column, with headers."));
            var tl = f.entry (_("Timeline range"), a.cols >= 2 ? Analysis.area_ref (new Area (a.sheet, a.r1 + 1, a.c1, a.r2, a.c1)) : "");
            var vals = f.entry (_("Values range"), a.cols >= 2 ? Analysis.area_ref (new Area (a.sheet, a.r1 + 1, a.c1 + 1, a.r2, a.c1 + 1)) : sel_text (win));
            f.section (_("Options"));
            var horizon = f.spin (_("Periods to forecast"), 1, 1000, 1, 6);
            var conf = f.spin (_("Confidence interval (%)"), 50, 99, 1, 95);
            var season = f.spin (_("Seasonality (0 detects it)"), 0, 366, 1, 0);
            f.footer (_("Create"), () => {
                var ta = Analysis.parse_area (book, tl.text, win.grid.sheet);
                var va = Analysis.parse_area (book, vals.text, win.grid.sheet);
                if (va == null) {
                    f.fail (_("Type the values range."));
                    return false;
                }
                if (ta == null) ta = va;
                win.doc.begin_book (_("Forecast Sheet"), win.grid.sheet);
                var s = Analysis.forecast_sheet (book, ta, va, (int) horizon.value, conf.value / 100, (int) season.value == 0 ? -1 : (int) season.value);
                win.doc.commit ();
                show_sheet (win, s);
                return true;
            });
            f.open ();
        }

        private static string[] fn_items () {
            return { _("Sum"), _("Count"), _("Average"), _("Max"), _("Min"), _("Product"), _("Count Numbers"), _("StdDev"), _("StdDevp"), _("Var"), _("Varp") };
        }

        private static string fn_key (string label) {
            string[] keys = { "sum", "count", "average", "max", "min", "product", "countNums", "stdDev", "stdDevp", "var", "varp" };
            string[] items = fn_items ();
            for (int i = 0; i < items.length; i++) if (items[i] == label) return keys[i];
            return "sum";
        }

        public static void subtotals (SpreadsheetWindow win) {
            var book = win.doc.book;
            var s = win.grid.sheet;
            var a = region (win);
            string[] cols = {};
            for (int c = a.c1; c <= a.c2; c++) {
                string h = s.value_at (a.r1, c).display ();
                cols += h != "" ? h : _("Column %s").printf (Address.column_name (c));
            }
            var f = new AnalysisForm (win, _("Subtotal"), 460, 560);
            f.section (_("Range %s").printf (sel_text (win, a)), _("Sort the data by the grouping column first."));
            var at = f.choice (_("At each change in"), cols, cols[0]);
            var fn = f.choice (_("Use function"), fn_items (), fn_items ()[0]);
            var add_group = f.section (_("Add subtotal to"));
            var switches = new Gee.ArrayList<SwitchRow> ();
            for (int i = 0; i < cols.length; i++) {
                bool numeric = s.value_at (a.r1 + 1, a.c1 + i).kind == ValueKind.NUMBER;
                var sw = new SwitchRow (cols[i], null, numeric && i == cols.length - 1);
                add_group.add_row (sw);
                switches.add (sw);
            }
            f.section (_("Options"));
            var replace = f.toggle (_("Replace current subtotals"), true);
            var below = f.toggle (_("Summary below data"), true);
            f.footer (_("Apply"), () => {
                int gc = a.c1;
                for (int i = 0; i < cols.length; i++) if (cols[i] == at.current_value) gc = a.c1 + i;
                int[] sums = {};
                for (int i = 0; i < switches.size; i++) if (switches[i].active) sums += a.c1 + i;
                if (sums.length == 0) {
                    f.fail (_("Choose at least one column to subtotal."));
                    return false;
                }
                win.doc.begin_book (_("Subtotal"), s);
                Analysis.subtotals (book, s, a, gc, fn_key (fn.current_value), sums, replace.active, false, below.active);
                win.doc.commit ();
                win.grid.refresh ();
                return true;
            }, _("Remove All"), () => {
                win.doc.begin_book (_("Remove Subtotals"), s);
                Analysis.remove_subtotals (book, s, a);
                win.doc.commit ();
                win.grid.refresh ();
                return true;
            });
            f.open ();
        }

        public static void consolidate (SpreadsheetWindow win) {
            var book = win.doc.book;
            var f = new AnalysisForm (win, _("Consolidate"), 480, 560);
            f.section (_("Function"));
            var fn = f.choice (_("Function"), fn_items (), fn_items ()[0]);
            var refs_group = f.section (_("All references"));
            var refs = new Gee.ArrayList<string> ();
            AnalysisForm.Submit refill = null;
            refill = () => {
                refs_group.clear ();
                if (refs.size == 0) refs_group.add_row (new ActionRow (_("No references"), _("Add each range to combine.")));
                foreach (var r in refs) {
                    var row = new ActionRow (r);
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    string rr = r;
                    del.clicked.connect (() => {
                        refs.remove (rr);
                        refill ();
                    });
                    row.add_suffix (del);
                    refs_group.add_row (row);
                }
                return true;
            };
            refill ();
            f.section (null);
            var reference = f.entry (_("Reference"), sel_text (win, region (win)));
            var add = new Button.with_label (_("Add"));
            add.halign = Align.END;
            add.clicked.connect (() => {
                if (Analysis.parse_area (book, reference.text, win.grid.sheet) == null) {
                    f.fail (_("Type a valid range."));
                    return;
                }
                refs.add (reference.text.strip ());
                refill ();
            });
            f.body.append (add);
            f.section (_("Use labels in"));
            var top = f.toggle (_("Top row"), true);
            var left = f.toggle (_("Left column"), true);
            var links = f.toggle (_("Create links to source data"), false);
            f.section (_("Destination"));
            var dest = f.entry (_("Destination cell"), cur_cell (win));
            f.footer (_("Consolidate"), () => {
                var list = new Gee.ArrayList<Area> ();
                foreach (var r in refs) {
                    var a = Analysis.parse_area (book, r, win.grid.sheet);
                    if (a != null) list.add (a);
                }
                var d = CellRef.parse (book, dest.text, win.grid.sheet);
                if (list.size == 0 || d == null) {
                    f.fail (_("Add at least one reference and a destination cell."));
                    return false;
                }
                win.doc.begin_book (_("Consolidate"), d.sheet);
                Analysis.consolidate (book, list, d.sheet, d.row, d.col, fn_key (fn.current_value), top.active, left.active, links.active);
                win.doc.commit ();
                win.grid.refresh ();
                return true;
            });
            f.open ();
        }

        private static string[] type_sources (Workbook book) {
            string[] out_s = {};
            foreach (var t in book.tables) out_s += t.name;
            foreach (var q in Analysis.data (book).queries) if (q.last_area != null && Tables.find (book, q.name) == null) out_s += q.name;
            return out_s;
        }

        public static void data_type_convert (SpreadsheetWindow win) {
            var book = win.doc.book;
            var sources = type_sources (book);
            if (sources.length == 0) {
                win.show_error (_("No Data Source"), _("Create a table or load a query first: its rows become the records of the data type."));
                return;
            }
            var f = new AnalysisForm (win, _("Convert to Data Type"), 440, 380);
            f.section (null, _("Each selected cell is linked to the record whose key matches its text. Linked cells show a card and their fields can be used in formulas as A2.Field or FIELDVALUE(A2, \"Field\")."));
            var src = f.choice (_("Records from"), sources, sources[0]);
            var fields = DataTypes.fields (book, sources[0]);
            var key = f.choice (_("Key column"), fields.length > 0 ? fields : new string[] { "" }, fields.length > 0 ? fields[0] : "");
            src.selected.connect ((it) => {
                var nf = DataTypes.fields (book, it);
                if (nf.length > 0) {
                    key.set_items (nf);
                    key.current_value = nf[0];
                }
            });
            f.footer (_("Convert"), () => {
                var sel = Document.clamp_area (win.grid.sheet, win.grid.selection);
                win.doc.begin_area (_("Convert to Data Type"), win.grid.sheet, sel);
                int n = DataTypes.convert (book, win.grid.sheet, sel, src.current_value, key.current_value);
                win.doc.commit ();
                win.grid.refresh ();
                info (win, _("Data Type"), ngettext ("%d cell was linked.", "%d cells were linked.", n).printf (n));
                return true;
            }, _("Unlink"), () => {
                var sel = Document.clamp_area (win.grid.sheet, win.grid.selection);
                DataTypes.clear (book, win.grid.sheet, sel);
                win.doc.modified = true;
                return true;
            });
            f.open ();
        }

        public static void convert_linked (SpreadsheetWindow win, string kind) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            var cells = new Gee.ArrayList<int> ();
            for (int r = sel.r1; r <= int.min (sel.r2, s.max_row); r++) {
                for (int c = sel.c1; c <= int.min (sel.c2, s.max_col); c++) {
                    if (s.value_at (r, c).display ().strip () != "") {
                        cells.add (r);
                        cells.add (c);
                    }
                }
            }
            if (cells.size == 0) {
                win.show_error (_("Nothing to Convert"), _("Select cells with the names of places or stock symbols first."));
                return;
            }
            var failures = new Gee.ArrayList<string> ();
            int pending = cells.size / 2;
            for (int i = 0; i < cells.size; i += 2) {
                int row = cells[i], col = cells[i + 1];
                string text = s.value_at (row, col).display ().strip ();
                LinkedHub.get ().search_async (kind, text, (list, err) => {
                    if (err != "" || list.size == 0) failures.add (err != "" ? "%s: %s".printf (text, err) : _("\"%s\" did not match any %s.").printf (text, kind == "stocks" ? _("stock") : _("place")));
                    else if (DataTypes.is_ambiguous (list, text)) choose_match (win, kind, text, list, s, row, col);
                    else fetch_link (win, kind, DataTypes.pick (list, text).id, s, row, col);
                    pending--;
                    if (pending == 0 && failures.size > 0) {
                        var sb = new StringBuilder ();
                        foreach (var f in failures) sb.append (f).append_c ('\n');
                        win.show_error (_("Some Cells Were Not Converted"), sb.str.strip ());
                    }
                });
            }
        }

        private static void fetch_link (SpreadsheetWindow win, string kind, string id, Sheet s, int r, int c) {
            var book = win.doc.book;
            LinkedHub.get ().fetch_async (book, kind, id, (rec, err) => {
                if (rec == null) {
                    win.show_error (_("Data Type Not Available"), err);
                    return;
                }
                win.doc.begin_area (_("Convert to Data Type"), s, new Area.cell (s, r, c));
                LinkedHub.link (book, s, r, c, rec);
                WhatIf.put_value (book, s, r, c, Value.str (rec.name));
                win.doc.commit ();
                win.grid.refresh ();
            });
        }

        private static void choose_match (SpreadsheetWindow win, string kind, string text, Gee.List<LinkedCandidate> list, Sheet s, int r, int c) {
            var f = new AnalysisForm (win, _("Data Selector"), 440, 480);
            var g = f.section (_("Matches for \"%s\"").printf (text), _("More than one result matches. Choose the right one."));
            foreach (var cand in list) {
                var row = new ActionRow (cand.label, cand.description != "" ? cand.description : null);
                row.activatable = true;
                var select = new Button.with_label (_("Select"));
                select.valign = Align.CENTER;
                string id = cand.id;
                select.clicked.connect (() => {
                    f.dlg.close ();
                    fetch_link (win, kind, id, s, r, c);
                });
                row.activated.connect (() => select.clicked ());
                row.add_suffix (select);
                g.add_row (row);
            }
            f.footer (_("Close"), () => true);
            f.open ();
        }

        public static void refresh_linked (SpreadsheetWindow win) {
            LinkedHub.get ().refresh_async (win.doc.book, (rec, err) => {
                if (rec == null && err != "") win.show_error (_("Data Types Not Refreshed"), err);
            });
            win.doc.book.recalculate ();
            win.grid.refresh ();
        }

        private static string card_text (string field, Value v) {
            if (v.kind != ValueKind.NUMBER) return v.display ();
            string fmt = "#,##0.##";
            if (field == _("Last trade time")) fmt = "yyyy-mm-dd hh:mm";
            else if (field == _("Change (%)")) fmt = "0.00%";
            else if (field == _("Latitude") || field == _("Longitude")) fmt = "0.0000";
            string color;
            return NumberFormat.format (v.number, fmt, out color);
        }

        private static void load_flag (Picture pic, string url) {
            string path = Path.build_filename (Environment.get_user_cache_dir (), "singularity-spreadsheet", "linked", "images", Checksum.compute_for_string (ChecksumType.SHA1, url));
            if (FileUtils.test (path, FileTest.EXISTS)) {
                pic.set_filename (path);
                return;
            }
            var session = new Soup.Session ();
            session.user_agent = LinkedConfig.get ().user_agent;
            var msg = new Soup.Message ("GET", url);
            if (msg == null) return;
            session.send_and_read_async.begin (msg, Priority.DEFAULT, null, (obj, res) => {
                try {
                    var bytes = session.send_and_read_async.end (res);
                    if (msg.status_code != 200) return;
                    DirUtils.create_with_parents (Path.get_dirname (path), 0755);
                    FileUtils.set_data (path, bytes.get_data ());
                    pic.set_filename (path);
                } catch (Error e) {
                }
            });
        }

        public static void data_type_card (SpreadsheetWindow win) {
            var book = win.doc.book;
            var link = DataTypes.link_at (book, win.grid.sheet, win.grid.cur_row, win.grid.cur_col);
            if (link == null) {
                win.show_error (_("Not a Data Type"), _("Select a cell converted with Data Types, Convert to Data Type."));
                return;
            }
            if (link.source.has_prefix ("@")) {
                linked_card (win, link);
                return;
            }
            var f = new AnalysisForm (win, link.key, 400, 520);
            var g = f.section (link.source);
            foreach (string field in DataTypes.fields (book, link.source)) {
                var v = DataTypes.field_value (book, link, field);
                var row = new ActionRow (field, v.display ());
                var ins = new Button.from_icon_name ("list-add-symbolic");
                ins.add_css_class ("flat");
                ins.valign = Align.CENTER;
                ins.tooltip_text = _("Insert this field in the next empty column");
                string fname = field;
                ins.clicked.connect (() => insert_field (win, fname));
                row.add_suffix (ins);
                g.add_row (row);
            }
            f.footer (_("Close"), () => true);
            f.open ();
        }

        private static void linked_card (SpreadsheetWindow win, DataTypeLink link) {
            var book = win.doc.book;
            var rec = DataTypes.linked_record (book, link);
            string key = link.source.substring (1) + ":" + link.key;
            if (rec == null) {
                string msg = book.analysis.loading.contains (key) ? _("The data is still loading.") : (book.analysis.failures[key] ?? _("The data is not available."));
                win.show_error (_("Data Type"), msg);
                return;
            }
            var f = new AnalysisForm (win, rec.name, 420, 620);
            string sub = rec.description;
            string updated = rec.updated_text ();
            if (updated != "") sub = (sub != "" ? sub + "\n" : "") + _("Updated %s").printf (updated);
            if (rec.status != "") sub = (sub != "" ? sub + "\n" : "") + rec.status;
            var flag = rec.field (_("Flag"));
            if (flag != null) {
                var pic = new Picture ();
                pic.content_fit = ContentFit.CONTAIN;
                pic.height_request = 96;
                pic.halign = Align.CENTER;
                pic.can_shrink = true;
                f.body.append (pic);
                load_flag (pic, flag.display ());
            }
            var g = f.section (rec.kind == "stocks" ? _("Stock") : _("Geography"), sub);
            foreach (string field in rec.order) {
                if (field == _("Flag") || field == _("Name") || field == _("Description")) continue;
                var row = new ActionRow (field, card_text (field, rec.fields[field]));
                var ins = new Button.from_icon_name ("list-add-symbolic");
                ins.add_css_class ("flat");
                ins.valign = Align.CENTER;
                ins.tooltip_text = _("Insert this field in the next empty column");
                string fname = field;
                ins.clicked.connect (() => insert_field (win, fname));
                row.add_suffix (ins);
                g.add_row (row);
            }
            f.footer (_("Close"), () => true, _("Refresh"), () => {
                LinkedHub.get ().fetch_async (book, rec.kind, rec.id, (r, e) => {
                    if (r == null) win.show_error (_("Data Types Not Refreshed"), e);
                });
                return true;
            });
            f.open ();
        }

        private static void insert_field (SpreadsheetWindow win, string field) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            int target = sel.c2 + 1;
            bool busy = true;
            while (busy) {
                busy = false;
                for (int r = sel.r1; r <= sel.r2; r++) if (s.input_at (r, target) != "") busy = true;
                if (busy) target++;
            }
            win.doc.begin_area (_("Insert Data Field"), s, new Area (s, sel.r1, target, sel.r2, target));
            bool plain = StructRefPlain.is_plain (field);
            for (int r = sel.r1; r <= sel.r2; r++) {
                if (DataTypes.link_at (win.doc.book, s, r, sel.c1) == null) continue;
                string cell = Address.cell (r, sel.c1);
                s.set_input (r, target, plain ? "=%s.%s".printf (cell, field) : "=FIELDVALUE(%s,\"%s\")".printf (cell, field.replace ("\"", "\"\"")));
            }
            win.doc.commit ();
            win.grid.refresh ();
        }

        public static void data_type_field (SpreadsheetWindow win) {
            var book = win.doc.book;
            var link = DataTypes.link_at (book, win.grid.sheet, win.grid.cur_row, win.grid.cur_col);
            if (link == null) {
                win.show_error (_("Not a Data Type"), _("Select cells converted with Data Types, Convert to Data Type."));
                return;
            }
            var fields = DataTypes.fields_of (book, link);
            if (fields.length == 0) return;
            var f = new AnalysisForm (win, _("Insert Data Field"), 400, 300);
            f.section (null);
            var field = f.choice (_("Field"), fields, fields.length > 1 ? fields[1] : fields[0]);
            f.footer (_("Insert"), () => {
                insert_field (win, field.current_value);
                return true;
            });
            f.open ();
        }

        public static void advanced_filter (SpreadsheetWindow win) {
            var book = win.doc.book;
            var f = new AnalysisForm (win, _("Advanced Filter"), 460, 460);
            f.section (null, _("The criteria range has the column headers on top; values on the same row must all match, separate rows are alternatives."));
            var list = f.entry (_("List range"), sel_text (win, region (win)));
            var crit = f.entry (_("Criteria range"), "");
            string[] actions = { _("Filter the list in place"), _("Copy to another location") };
            var action = f.choice (_("Action"), actions, actions[0]);
            var copy_to = f.entry (_("Copy to"), "");
            var unique = f.toggle (_("Unique records only"), false);
            f.footer (_("Filter"), () => {
                var la = Analysis.parse_area (book, list.text, win.grid.sheet);
                var ca = Analysis.parse_area (book, crit.text, win.grid.sheet);
                if (la == null || ca == null) {
                    f.fail (_("Type the list range and the criteria range."));
                    return false;
                }
                Area? dest = null;
                if (action.current_value == actions[1]) {
                    var d = CellRef.parse (book, copy_to.text, win.grid.sheet);
                    if (d == null) {
                        f.fail (_("Type the cell to copy to."));
                        return false;
                    }
                    dest = new Area.cell (d.sheet, d.row, d.col);
                }
                win.doc.begin_book (_("Advanced Filter"), win.grid.sheet);
                int n = Analysis.advanced_filter (book, la, ca, dest, unique.active);
                win.doc.commit ();
                win.grid.refresh ();
                info (win, _("Advanced Filter"), ngettext ("%d record found.", "%d records found.", n).printf (n));
                return true;
            }, _("Show All"), () => {
                var la = Analysis.parse_area (book, list.text, win.grid.sheet);
                if (la == null) return false;
                win.doc.begin_book (_("Show All"), win.grid.sheet);
                Analysis.show_all (book, la.sheet, la);
                win.doc.commit ();
                win.grid.refresh ();
                return true;
            });
            f.open ();
        }
    }
}
