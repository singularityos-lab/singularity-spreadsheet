using Gtk;

namespace Singularity.Apps.Spreadsheet {

    public class Templates {
        private static int style (Document d, bool bold, string fill, string color, string fmt = "General", HAlign align = HAlign.GENERAL) {
            var st = new CellStyle ();
            st.bold = bold;
            st.fill = fill;
            st.color = color;
            st.number_format = fmt;
            st.halign = align;
            return d.book.intern (st);
        }

        private static int total_style (Document d, string fmt) {
            var st = new CellStyle ();
            st.bold = true;
            st.number_format = fmt;
            st.top = new Border (BorderStyle.THIN, "");
            st.bottom = new Border (BorderStyle.DOUBLE, "");
            return d.book.intern (st);
        }

        private static void header (Document d, Sheet s, int row, string[] cells, string fill) {
            int h = style (d, true, fill, "#ffffff", "General", HAlign.CENTER);
            for (int c = 0; c < cells.length; c++) {
                s.set_input (row, c, cells[c]);
                s.set_style (row, c, h);
            }
        }

        private static Document finish (Document d) {
            d.book.recalculate ();
            d.modified = false;
            return d;
        }

        public static Document budget () {
            var d = new Document ();
            var s = d.book.sheets[0];
            s.name = _("Budget");
            string[] cats = { _("Rent"), _("Groceries"), _("Utilities"), _("Transport"), _("Health"), _("Leisure"), _("Savings") };
            double[] planned = { 900, 400, 150, 120, 80, 150, 300 };
            double[] actual = { 900, 436.5, 162.3, 95, 40, 188.9, 300 };
            header (d, s, 0, { _("Category"), _("Planned"), _("Actual"), _("Difference") }, "#1baf7a");
            string money_fmt = Dialogs.currency_format (2);
            int money = style (d, false, "", "", money_fmt);
            for (int i = 0; i < cats.length; i++) {
                s.set_input (i + 1, 0, cats[i]);
                s.set_input (i + 1, 1, Value.format_number_general_full (planned[i]));
                s.set_input (i + 1, 2, Value.format_number_general_full (actual[i]));
                s.set_input (i + 1, 3, "=B%d-C%d".printf (i + 2, i + 2));
                for (int c = 1; c < 4; c++) s.set_style (i + 1, c, money);
            }
            int t = cats.length + 1;
            s.set_input (t, 0, _("Total"));
            s.set_style (t, 0, total_style (d, "General"));
            int tot = total_style (d, money_fmt);
            for (int c = 1; c < 4; c++) {
                string col = Address.column_name (c);
                s.set_input (t, c, "=SUM(%s2:%s%d)".printf (col, col, t));
                s.set_style (t, c, tot);
            }
            s.col_widths[0] = 150;
            for (int c = 1; c < 4; c++) s.col_widths[c] = 120;
            s.freeze_rows = 1;
            var neg = new CondFormat (new Area (s, 1, 3, cats.length, 3), CondKind.LESS);
            neg.a = "0";
            var red = new CellStyle ();
            red.fill = "#ffc7ce";
            red.color = "#9c0006";
            neg.style = d.book.intern (red);
            s.cond_formats.add (neg);
            var ch = new Chart (new Area (s, 0, 0, cats.length, 2));
            ch.title = _("Planned and Actual");
            ch.x = 540;
            ch.y = 12;
            ch.width = 520;
            ch.height = 300;
            s.charts.add (ch);
            return finish (d);
        }

        public static Document invoice () {
            var d = new Document ();
            var s = d.book.sheets[0];
            s.name = _("Invoice");
            var title = new CellStyle ();
            title.bold = true;
            title.font_size = 22;
            title.color = "#2a78d6";
            s.set_input (0, 0, _("INVOICE"));
            s.set_style (0, 0, d.book.intern (title));
            s.row_heights[0] = 44;
            int label = style (d, true, "", "#52514e");
            s.set_input (2, 0, _("Invoice number"));
            s.set_input (2, 1, "2026-001");
            s.set_input (3, 0, _("Date"));
            s.set_input (3, 1, "=TODAY()");
            s.set_style (3, 1, style (d, false, "", "", LocaleInfo.get ().short_date_format (), HAlign.LEFT));
            s.set_input (4, 0, _("Due"));
            s.set_input (4, 1, "=B4+30");
            s.set_style (4, 1, style (d, false, "", "", LocaleInfo.get ().short_date_format (), HAlign.LEFT));
            s.set_input (2, 3, _("Bill to"));
            s.set_input (3, 3, _("Customer name"));
            s.set_input (4, 3, _("Street and city"));
            for (int r = 2; r <= 4; r++) s.set_style (r, 0, label);
            s.set_style (2, 3, label);
            header (d, s, 6, { _("Description"), _("Quantity"), _("Unit Price"), _("Amount") }, "#2a78d6");
            string money_fmt = Dialogs.currency_format (2);
            int money = style (d, false, "", "", money_fmt);
            string[] items = { _("Design work"), _("Development"), _("Hosting, one year") };
            double[] qty = { 12, 30, 1 };
            double[] price = { 60, 55, 240 };
            for (int i = 0; i < 8; i++) {
                int r = 7 + i;
                if (i < items.length) {
                    s.set_input (r, 0, items[i]);
                    s.set_input (r, 1, Value.format_number_general_full (qty[i]));
                    s.set_input (r, 2, Value.format_number_general_full (price[i]));
                }
                s.set_input (r, 3, "=IF(B%d=\"\",\"\",B%d*C%d)".printf (r + 1, r + 1, r + 1));
                s.set_style (r, 2, money);
                s.set_style (r, 3, money);
            }
            s.set_input (16, 2, _("Subtotal"));
            s.set_input (16, 3, "=SUM(D8:D15)");
            s.set_input (17, 2, _("Tax"));
            s.set_input (17, 1, "22%");
            s.set_input (17, 3, "=D17*B18");
            s.set_input (18, 2, _("Total"));
            s.set_input (18, 3, "=D17+D18");
            s.set_style (16, 3, money);
            s.set_style (17, 3, money);
            s.set_style (18, 2, total_style (d, "General"));
            s.set_style (18, 3, total_style (d, money_fmt));
            s.col_widths[0] = 220;
            s.col_widths[1] = 90;
            s.col_widths[2] = 110;
            s.col_widths[3] = 130;
            s.show_grid = false;
            return finish (d);
        }

        public static Document tracker () {
            var d = new Document ();
            var s = d.book.sheets[0];
            s.name = _("Tasks");
            header (d, s, 0, { _("Task"), _("Owner"), _("Status"), _("Start"), _("Due"), _("Days Left"), _("Progress") }, "#4a3aa7");
            string date_fmt = LocaleInfo.get ().short_date_format ();
            int date = style (d, false, "", "", date_fmt);
            int pct = style (d, false, "", "", "0%");
            string[] tasks = { _("Plan the project"), _("Research"), _("First draft"), _("Review"), _("Launch") };
            string[] owners = { "Ada", "Luca", "Ada", "Sara", "Luca" };
            string[] status = { _("Done"), _("Done"), _("In progress"), _("Not started"), _("Not started") };
            double[] progress = { 1, 1, 0.45, 0, 0 };
            for (int i = 0; i < tasks.length; i++) {
                int r = i + 1;
                s.set_input (r, 0, tasks[i]);
                s.set_input (r, 1, owners[i]);
                s.set_input (r, 2, status[i]);
                s.set_input (r, 3, "=TODAY()+%d".printf (i * 7 - 14));
                s.set_input (r, 4, "=D%d+10".printf (r + 1));
                s.set_input (r, 5, "=MAX(0,E%d-TODAY())".printf (r + 1));
                s.set_input (r, 6, Value.format_number_general_full (progress[i]));
                s.set_style (r, 3, date);
                s.set_style (r, 4, date);
                s.set_style (r, 6, pct);
            }
            var v = new Validation (new Area (s, 1, 2, 200, 2));
            v.list_source = "\"%s,%s,%s,%s\"".printf (_("Not started"), _("In progress"), _("Blocked"), _("Done"));
            s.validations.add (v);
            var bar = new CondFormat (new Area (s, 1, 6, 200, 6), CondKind.DATA_BAR);
            bar.color1 = "#4a3aa7";
            s.cond_formats.add (bar);
            var done = new CondFormat (new Area (s, 1, 2, 200, 2), CondKind.EQUAL);
            done.a = _("Done");
            var green = new CellStyle ();
            green.fill = "#c6efce";
            green.color = "#006100";
            done.style = d.book.intern (green);
            s.cond_formats.add (done);
            s.col_widths[0] = 200;
            s.col_widths[2] = 120;
            s.freeze_rows = 1;
            s.filter = new Filter (new Area (s, 0, 0, tasks.length, 6));
            return finish (d);
        }
    }

    public class SpreadsheetApp : Singularity.Application {

        public SpreadsheetApp () {
            Object (application_id: "dev.sinty.spreadsheet", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("new", 0, OptionFlags.NONE, OptionArg.NONE, _("Start a new spreadsheet"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            if (!options.contains ("new")) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("spreadsheet: %s", e.message);
                return 1;
            }
            activate_action ("new", null);
            return get_is_remote () ? 0 : -1;
        }

        protected override void startup () {
            base.startup ();
            IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/dev/sinty/spreadsheet/icons");
            Singularity.Application.add_app_css (CSS);
            var new_action = new SimpleAction ("new", null);
            new_action.activate.connect (() => {
                var w = get_active_window () as SpreadsheetWindow;
                if (w != null && w.doc == null) w.new_document ();
                else {
                    var nw = new SpreadsheetWindow (this);
                    nw.present ();
                    nw.new_document ();
                }
            });
            add_action (new_action);
            var open_action = new SimpleAction ("open", null);
            open_action.activate.connect (() => {
                var w = get_active_window () as SpreadsheetWindow;
                if (w == null) {
                    w = new SpreadsheetWindow (this);
                    w.present ();
                }
                choose_file (w);
            });
            add_action (open_action);
            var open_online = new SimpleAction ("open-online", null);
            open_online.activate.connect (() => {
                var w = get_active_window () as SpreadsheetWindow;
                if (w == null) {
                    w = new SpreadsheetWindow (this);
                    w.present ();
                }
                CloudActions.open.begin (w, (f) => open_file (f, w));
            });
            add_action (open_online);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ()) w.close ();
            });
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.spreadsheet");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            build_menu ();
            string[,] accels = {
                { "app.quit", "<Control>q" }, { "app.new", "<Control>n" }, { "app.open", "<Control>o" },
                { "win.save", "<Control>s" }, { "win.save-as", "<Control><Shift>s" }, { "win.print", "<Control>p" },
                { "win.close-doc", "<Control>w" }, { "win.close", "<Control><Shift>w" }, { "app.settings", "<Control>comma" }, { "win.undo", "<Control>z" },
                { "win.cut", "<Control>x" }, { "win.copy", "<Control>c" }, { "win.paste", "<Control>v" },
                { "win.paste-values", "<Control><Shift>v" }, { "win.select-all", "<Control>a" }, { "win.find", "<Control>f" },
                { "win.goto", "<Control>g" }, { "win.fill-down", "<Control>d" }, { "win.fill-right", "<Control>r" },
                { "win.bold", "<Control>b" }, { "win.italic", "<Control>i" }, { "win.underline", "<Control>u" },
                { "win.strike", "<Control>5" }, { "win.format-cells", "<Control>1" }, { "win.autosum", "<Alt>equal" },
                { "win.insert-date", "<Control>semicolon" }, { "win.insert-time", "<Control><Shift>colon" },
                { "win.insert-cells", "<Control>plus" }, { "win.delete-cells", "<Control>minus" },
                { "win.sheet-next", "<Control>Page_Down" }, { "win.sheet-prev", "<Control>Page_Up" },
                { "win.filter", "<Control><Shift>l" }, { "win.insert-function", "<Shift>F3" }, { "win.recalc", "F9" },
                { "win.show-formulas", "<Control>grave" }, { "win.note", "<Shift>F2" }, { "win.insert-link", "<Control>k" }, { "win.insert-sheet", "<Shift>F11" },
                { "win.insert-chart", "<Alt>F1" }, { "win.insert-table", "<Control>t" }, { "win.spelling", "F7" }, { "win.hide-rows", "<Control>9" }, { "win.hide-cols", "<Control>0" },
                { "win.fmt-currency", "<Control><Shift>dollar" }, { "win.fmt-percent", "<Control><Shift>percent" },
                { "win.fmt-number", "<Control><Shift>exclam" }, { "win.fmt-date", "<Control><Shift>numbersign" },
                { "win.fmt-general", "<Control><Shift>asciitilde" }, { "win.zoom-reset", "<Control><Alt>0" }
            };
            for (int i = 0; i < accels.length[0]; i++) set_accels_for_action (accels[i, 0], { accels[i, 1] });
            set_accels_for_action ("win.redo", { "<Control><Shift>z", "<Control>y" });
            EditActions.accels (this);
            set_accels_for_action ("win.goto", { "<Control>g", "F5" });
            set_accels_for_action ("win.zoom-in", { "<Control><Alt>plus", "<Control><Alt>equal" });
            set_accels_for_action ("win.zoom-out", { "<Control><Alt>minus" });
            set_accels_for_action ("win.macros", { "<Alt>F8" });
            set_accels_for_action ("win.comment-new", { "<Control><Alt>m" });
            set_accels_for_action ("win.script-editor", { "<Alt>F11" });
        }

        private static GLib.Menu section (string[,] items) {
            var m = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) m.append (items[i, 0], items[i, 1]);
            return m;
        }

        private void build_menu () {
            var menu = new GLib.Menu ();

            var file = new GLib.Menu ();
            file.append_section (null, section ({ { _("New"), "app.new" }, { _("Open…"), "app.open" }, { _("Open from Online Account…"), "app.open-online" } }));
            file.append_section (null, section ({ { _("Save"), "win.save" }, { _("Save As…"), "win.save-as" }, { _("Save to Online Account…"), "win.save-online" }, { _("Version History…"), "win.version-history" }, { _("Save as Template…"), "win.save-template" } }));
            file.append_section (null, section ({ { _("Export as Excel Workbook…"), "win.export-xlsx" }, { _("Export as OpenDocument…"), "win.export-ods" }, { _("Export as CSV…"), "win.export-csv" }, { _("Export as TSV…"), "win.export-tsv" }, { _("Export as Web Page…"), "win.export-html" }, { _("Export as PDF…"), "win.export-pdf" }, { _("Page Setup…"), "win.page-setup" }, { _("Print…"), "win.print" }, { _("Share…"), "win.share" } }));
            file.append_section (null, section ({ { _("Close Spreadsheet"), "win.close-doc" } }));
            file.append_section (null, section ({ { _("Close Window"), "win.close" }, { _("Quit"), "app.quit" } }));
            menu.append_submenu (_("File"), file);

            var edit = new GLib.Menu ();
            edit.append_section (null, section ({ { _("Undo"), "win.undo" }, { _("Redo"), "win.redo" } }));
            edit.append_section (null, section ({ { _("Cut"), "win.cut" }, { _("Copy"), "win.copy" }, { _("Paste"), "win.paste" } }));
            var special = section ({ { _("Values Only"), "win.paste-values" }, { _("Formats Only"), "win.paste-formats" }, { _("Formulas Only"), "win.paste-formulas" }, { _("Transpose"), "win.paste-transpose" } });
            var special_section = new GLib.Menu ();
            special_section.append_submenu (_("Paste Special"), special);
            edit.append_section (null, special_section);
            var clear = section ({ { _("All"), "win.clear-all" }, { _("Contents"), "win.clear-contents" }, { _("Formats"), "win.clear-formats" } });
            var clear_section = new GLib.Menu ();
            clear_section.append_submenu (_("Clear"), clear);
            clear_section.append (_("Fill Down"), "win.fill-down");
            clear_section.append (_("Fill Right"), "win.fill-right");
            edit.append_section (null, clear_section);
            edit.append_section (null, section ({ { _("Delete Rows"), "win.delete-rows" }, { _("Delete Columns"), "win.delete-cols" } }));
            edit.append_section (null, section ({ { _("Select All"), "win.select-all" }, { _("Find and Replace"), "win.find" }, { _("Go To"), "win.goto" } }));
            edit.append_section (null, section ({ { _("Spelling…"), "win.spelling" }, { _("Check Accessibility…"), "win.check-accessibility" } }));
            edit.append_section (null, section ({ { _("Settings"), "app.settings" } }));
            menu.append_submenu (_("Edit"), edit);

            var view = new GLib.Menu ();
            var freeze = section ({ { _("Freeze at Selection"), "win.freeze" }, { _("Freeze Top Row"), "win.freeze-row" }, { _("Freeze First Column"), "win.freeze-col" }, { _("Unfreeze"), "win.unfreeze" } });
            var freeze_section = new GLib.Menu ();
            freeze_section.append_submenu (_("Freeze Panes"), freeze);
            view.append_section (null, freeze_section);
            view.append_section (null, section ({ { _("Gridlines"), "win.gridlines" }, { _("Show Formulas"), "win.show-formulas" } }));
            view.append_section (null, section ({ { _("Zoom In"), "win.zoom-in" }, { _("Zoom Out"), "win.zoom-out" }, { _("Actual Size"), "win.zoom-reset" } }));
            view.append_section (null, section ({ { _("Recalculate"), "win.recalc" }, { _("Calculation Options…"), "win.calc-options" } }));
            view.append_section (null, section ({ { _("Page Break Preview"), "win.page-break-preview" } }));
            menu.append_submenu (_("View"), view);

            var layout = new GLib.Menu ();
            layout.append_section (null, section ({ { _("Page Setup…"), "win.page-setup" }, { _("Print Titles…"), "win.print-titles" } }));
            layout.append_section (null, section ({ { _("Set Print Area"), "win.print-area-set" }, { _("Add to Print Area"), "win.print-area-add" }, { _("Clear Print Area"), "win.print-area-clear" } }));
            layout.append_section (null, section ({ { _("Insert Page Break"), "win.page-break-insert" }, { _("Remove Page Break"), "win.page-break-remove" }, { _("Reset All Page Breaks"), "win.page-break-reset" } }));
            menu.append_submenu (_("Page Layout"), layout);

            var formulas = new GLib.Menu ();
            formulas.append_section (null, section ({ { _("Trace Precedents"), "win.trace-precedents" }, { _("Trace Dependents"), "win.trace-dependents" }, { _("Remove Arrows"), "win.remove-arrows" } }));
            formulas.append_section (null, section ({ { _("Evaluate Formula…"), "win.evaluate-formula" }, { _("Error Checking…"), "win.error-checking" }, { _("Circular References…"), "win.circular-refs" }, { _("Watch Window"), "win.watch-window" } }));
            formulas.append_section (null, section ({ { _("Show Formulas"), "win.show-formulas" } }));
            menu.append_submenu (_("Formulas"), formulas);

            var tools = new GLib.Menu ();
            tools.append_section (null, section ({ { _("Macros…"), "win.macros" }, { _("Record Macro"), "win.macro-record" }, { _("Script Editor"), "win.script-editor" } }));
            menu.append_submenu (_("Macros"), tools);

            var insert = new GLib.Menu ();
            insert.append_section (null, section ({ { _("Rows Above"), "win.insert-rows-above" }, { _("Rows Below"), "win.insert-rows-below" }, { _("Columns Left"), "win.insert-cols-left" }, { _("Columns Right"), "win.insert-cols-right" } }));
            insert.append_section (null, section ({ { _("Sheet"), "win.insert-sheet" }, { _("Chart…"), "win.insert-chart" }, { _("Picture…"), "win.insert-picture" }, { _("Text Box"), "win.insert-textbox" }, { _("Sparklines…"), "win.insert-sparklines" }, { _("Diagram…"), "win.insert-diagram" }, { _("Table…"), "win.insert-table" } }));
            insert.append_section (null, section ({ { _("Function…"), "win.insert-function" }, { _("AutoSum"), "win.autosum" }, { _("Note…"), "win.note" }, { _("Comment…"), "win.comment-new" }, { _("Link…"), "win.insert-link" }, { _("Today's Date"), "win.insert-date" }, { _("Current Time"), "win.insert-time" } }));
            insert.append_submenu (_("Shape"), section ({ { _("Rectangle"), "win.insert-shape-rect" }, { _("Rounded Rectangle"), "win.insert-shape-rounded" }, { _("Oval"), "win.insert-shape-ellipse" }, { _("Line"), "win.insert-shape-line" }, { _("Arrow"), "win.insert-shape-arrow" } }));
            menu.append_submenu (_("Insert"), insert);

            var format = new GLib.Menu ();
            format.append_section (null, section ({ { _("Format Cells…"), "win.format-cells" } }));
            var text = section ({ { _("Bold"), "win.bold" }, { _("Italic"), "win.italic" }, { _("Underline"), "win.underline" }, { _("Strikethrough"), "win.strike" } });
            var number = section ({ { _("General"), "win.fmt-general" }, { _("Number"), "win.fmt-number" }, { _("Currency"), "win.fmt-currency" }, { _("Percentage"), "win.fmt-percent" }, { _("Scientific"), "win.fmt-scientific" }, { _("Date"), "win.fmt-date" }, { _("Time"), "win.fmt-time" }, { _("Text"), "win.fmt-text" }, { _("More Decimals"), "win.dec-inc" }, { _("Fewer Decimals"), "win.dec-dec" } });
            var align = section ({ { _("Left"), "win.align-left" }, { _("Center"), "win.align-center" }, { _("Right"), "win.align-right" }, { _("Wrap Text"), "win.wrap" } });
            var merge = section ({ { _("Merge and Center"), "win.merge-center" }, { _("Merge Cells"), "win.merge" }, { _("Unmerge Cells"), "win.unmerge" } });
            var subs = new GLib.Menu ();
            subs.append_submenu (_("Text"), text);
            subs.append_submenu (_("Number"), number);
            subs.append_submenu (_("Alignment"), align);
            subs.append_submenu (_("Merge"), merge);
            format.append_section (null, subs);
            var rows_cols = section ({ { _("Row Height…"), "win.row-height" }, { _("Column Width…"), "win.col-width" }, { _("Autofit Rows"), "win.autofit-rows" }, { _("Autofit Columns"), "win.autofit-cols" }, { _("Hide Rows"), "win.hide-rows" }, { _("Hide Columns"), "win.hide-cols" }, { _("Unhide Rows"), "win.unhide-rows" }, { _("Unhide Columns"), "win.unhide-cols" } });
            var rc_section = new GLib.Menu ();
            rc_section.append_submenu (_("Rows and Columns"), rows_cols);
            format.append_section (null, rc_section);
            format.append_section (null, section ({ { _("Conditional Formatting…"), "win.cond-format" }, { _("Manage Rules…"), "win.cond-manage" }, { _("Clear Rules"), "win.clear-rules" }, { _("Clear Formatting"), "win.clear-formats" } }));
            menu.append_submenu (_("Format"), format);

            var data = new GLib.Menu ();
            data.append_section (null, section ({ { _("Sort A to Z"), "win.sort-asc" }, { _("Sort Z to A"), "win.sort-desc" }, { _("Custom Sort…"), "win.sort-custom" } }));
            data.append_section (null, section ({ { _("Filter"), "win.filter" }, { _("Remove Duplicates"), "win.remove-dups" }, { _("Data Validation…"), "win.validation" }, { _("Named Ranges…"), "win.names" } }));
            AnalysisUi.extend_menu (data);
            DataModelUi.extend_menu (data);
            menu.append_submenu (_("Data"), data);

            var sheet = new GLib.Menu ();
            sheet.append_section (null, section ({ { _("New Sheet"), "win.insert-sheet" }, { _("Duplicate Sheet"), "win.sheet-duplicate" }, { _("Rename Sheet"), "win.sheet-rename" }, { _("Delete Sheet"), "win.sheet-delete" } }));
            sheet.append_section (null, section ({ { _("Hide Sheet"), "win.sheet-hide" }, { _("Unhide Sheet…"), "win.sheet-unhide" } }));
            sheet.append_section (null, section ({ { _("Next Sheet"), "win.sheet-next" }, { _("Previous Sheet"), "win.sheet-prev" } }));
            menu.append_submenu (_("Sheet"), sheet);

            EditActions.extend_menu (menu, edit, view, format, data);
            set_menubar (menu);
        }

        public override void activate () {
            var w = get_active_window ();
            if (w == null) w = new SpreadsheetWindow (this);
            w.present ();
        }

        public override void open (File[] files, string hint) {
            foreach (var f in files) open_file (f, null);
        }

        public void open_file (File file, SpreadsheetWindow? target) {
            string? path = file.get_path ();
            if (path == null) return;
            foreach (var w in get_windows ()) {
                var sw = w as SpreadsheetWindow;
                if (sw != null && sw.doc != null && sw.doc.path == path) {
                    sw.present ();
                    return;
                }
            }
            SpreadsheetWindow win = target != null && target.is_empty () ? target : null;
            if (win == null) {
                foreach (var w in get_windows ()) {
                    var sw = w as SpreadsheetWindow;
                    if (sw != null && sw.is_empty ()) win = sw;
                }
            }
            if (win == null) win = new SpreadsheetWindow (this);
            win.present ();
            try {
                var d = Document.open (path);
                win.load_document (d);
                RecentManager.get_default ().add_item (file.get_uri ());
            } catch (Error e) {
                if (e is CryptoError.PASSWORD_REQUIRED) {
                    EditDialogs.open_encrypted (win, file);
                    return;
                }
                win.show_error (_("Could Not Open"), _("\"%s\" could not be opened: %s").printf (file.get_basename (), e.message));
            }
        }

        public void choose_file (SpreadsheetWindow parent) {
            var dialog = new FileDialog ();
            dialog.title = _("Open Spreadsheet");
            var filter = new FileFilter ();
            filter.name = _("Spreadsheets");
            foreach (string s in FileKind.suffixes ()) filter.add_suffix (s);
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            dialog.filters = filters;
            dialog.open.begin (parent, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) open_file (file, parent);
                } catch (Error e) {
                }
            });
        }

        private const string CSS = """
.ss-formula-bar {
    padding: 5px 18px;
}

.ss-formula-bar entry,
.ss-name-wrap {
    min-height: 26px;
    border-radius: 8px;
}

.ss-formula-bar entry {
    padding: 0 8px;
    font-size: 13px;
}

.ss-name-wrap {
    background-color: @card_bg;
    border: 1px solid @border_color;
}

.ss-name-wrap:focus-within {
    border-color: @focus_ring_color;
    box-shadow: 0 0 0 1px @focus_ring_color;
}

.ss-name-wrap entry.ss-name-box,
.ss-name-wrap entry.ss-name-box:focus-within {
    background: none;
    border: none;
    box-shadow: none;
    min-height: 26px;
    font-feature-settings: "tnum";
}

.ss-name-wrap button.ss-name-list {
    min-width: 22px;
    min-height: 22px;
    margin: 0 2px;
    padding: 0;
    border-radius: 4px;
}

.ss-formula-sep {
    margin: 4px 6px;
}

.ss-formula-bar button.ss-bar-button {
    min-width: 26px;
    min-height: 26px;
    padding: 0;
    border-radius: 8px;
}

.ss-formula-entry {
    font-family: monospace;
}

.ss-grid-scroll {
    margin: 0 12px;
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.1);
}

.spreadsheet-grid {
    color: @window_fg_color;
}

.spreadsheet-editor,
.spreadsheet-editor text {
    background-color: @window_bg_color;
    color: @window_fg_color;
    font-feature-settings: "tnum";
}

.spreadsheet-editor {
    box-shadow: 0 0 0 2px @accent_bg_color, 0 6px 18px alpha(black, 0.18);
    border-radius: 2px;
}

.spreadsheet-hint {
    padding: 4px 8px;
    font-family: monospace;
}

.spreadsheet-assist row {
    padding: 4px 8px;
    border-radius: 8px;
}

.spreadsheet-assist-name {
    font-family: monospace;
    font-weight: 700;
}

.ss-status {
    font-feature-settings: "tnum";
    font-size: 12px;
    margin: 0 8px;
}

.ss-zoom {
    border-radius: 99px;
    font-feature-settings: "tnum";
    font-size: 12px;
    min-height: 26px;
    padding: 0 10px;
}

.ss-recent-list {
    border-radius: 14px;
}

.ss-template-card {
    padding: 6px;
    border-radius: 12px;
}
.ss-template-thumb {
    border-radius: 6px;
    background-color: @card_bg_color;
    box-shadow: 0 0 0 1px alpha(@borders, 0.7), 0 1px 4px alpha(@shadow_color, 0.25);
}
.ss-recent-row {
    border-radius: 10px;
    padding: 8px 10px;
}

.ss-chip {
    border-radius: 99px;
    padding: 2px 12px;
    min-height: 28px;
    font-size: 13px;
}

.ss-chip:checked {
    background-color: @accent_bg_color;
    color: @accent_fg_color;
}

.ss-swatch {
    padding: 2px;
    min-width: 0;
    min-height: 0;
    border-radius: 99px;
    background: transparent;
    box-shadow: none;
}

.ss-swatch:hover {
    background-color: alpha(@window_fg_color, 0.1);
}

.ss-border-preset {
    border-radius: 12px;
    padding: 10px 14px;
}

.ss-function-list {
    background: transparent;
}

.ss-function-list row {
    border-radius: 8px;
}

.ss-function-name {
    font-family: monospace;
    font-weight: 700;
}

.ss-function-detail {
    padding: 10px 12px;
    border-radius: 12px;
    background-color: alpha(@window_fg_color, 0.05);
}

.ss-function-detail {
    font-size: 13px;
}

.ss-format-preview {
    padding: 18px;
    border-radius: 14px;
    background-color: alpha(@window_fg_color, 0.05);
    font-size: 20px;
    font-feature-settings: "tnum";
}

.ss-chart-preview {
    min-height: 320px;
}

.ss-note-frame {
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.14);
}

.ss-note-view,
.ss-note-view text {
    background: transparent;
    padding: 8px;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-spreadsheet", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-spreadsheet", "UTF-8");
        Intl.textdomain ("singularity-spreadsheet");
        return new SpreadsheetApp ().run (args);
    }
}
