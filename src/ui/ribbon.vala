using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class SheetRibbon : ContextRibbon {
        private weak SpreadsheetWindow win;
        private bool syncing;
        private RibbonSelector font_selector;
        private RibbonSelector size_selector;
        private RibbonSelector number_selector;
        private RibbonSelector zoom_selector;
        private RibbonMenu valign_menu;
        private Gee.HashMap<string, RibbonToggle> cell_toggles = new Gee.HashMap<string, RibbonToggle> ();

        private const string[] FONTS = { "Calibri", "Arial", "Cambria", "Times New Roman", "Courier New", "Liberation Sans", "Liberation Serif", "Noto Sans", "Noto Serif", "DejaVu Sans Mono" };
        private const int[] SIZES = { 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48, 72 };
        private const int[] ZOOMS = { 50, 75, 90, 100, 125, 150, 200, 300 };
        private const string[] SWATCHES = {
            "#000000", "#52514e", "#a5a39d", "#ffffff", "#e34948", "#eb6834", "#eda100", "#1baf7a", "#008300",
            "#2a78d6", "#4a3aa7", "#e87ba4", "#fde2e1", "#fdebd0", "#fff4c2", "#dff5ea", "#dbeafe", "#ece8fb"
        };

        public SheetRibbon (SpreadsheetWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            add_css_class ("ss-ribbon");
            build_home (add_context ("home", _("Home"), "go-home-symbolic"));
            build_insert (add_context ("insert", _("Insert"), "list-add-symbolic"));
            build_layout (add_context ("layout", _("Page Layout"), "document-page-setup-symbolic"));
            build_formulas (add_context ("formulas", _("Formulas"), "sheet-function-symbolic"));
            build_data (add_context ("data", _("Data"), "sheet-get-data-symbolic"));
            build_review (add_context ("review", _("Review"), "tools-check-spelling-symbolic"));
            build_view (add_context ("view", _("View"), "view-reveal-symbolic"));
        }

        private RibbonButton button (RibbonContext c, string? icon, string label, string action, bool labelled = false, string? tip = null) {
            var b = c.add_button (icon, label, tip, "win." + action);
            b.label_in_compact = labelled;
            return b;
        }

        private RibbonMenu menu (RibbonContext c, string icon, string label, bool labelled, owned RibbonMenuBuilder build) {
            var m = c.add_menu (icon, label);
            m.label_in_compact = labelled;
            m.set_builder ((owned) build);
            return m;
        }

        private void item (ContextMenu m, string label, string? icon, string action) {
            m.add_item (label, icon, () => win.run (action));
        }

        private delegate void CellEdit ();

        private RibbonToggle cell_toggle (RibbonContext c, string key, string icon, string label, string? shortcut, owned CellEdit edit) {
            var t = c.add_toggle (icon, label);
            t.shortcut = shortcut;
            t.toggled.connect (() => {
                if (syncing || win.doc == null || win.grid == null) return;
                edit ();
                sync ();
            });
            cell_toggles[key] = t;
            return t;
        }

        private RibbonToggle action_toggle (RibbonContext c, string key, string icon, string label, string action, string? shortcut = null) {
            return cell_toggle (c, key, icon, label, shortcut ?? accel_label (action), () => win.run (action));
        }

        private static string? accel_label (string action) {
            var app = GLib.Application.get_default () as Gtk.Application;
            if (app == null) return null;
            string[] accels = app.get_accels_for_action ("win." + action);
            if (accels.length == 0) return null;
            uint key;
            Gdk.ModifierType mods;
            if (!Gtk.accelerator_parse (accels[0], out key, out mods)) return null;
            return Gtk.accelerator_get_label (key, mods);
        }

        private void valign (VAlign v) {
            win.doc.edit_style (win.grid.sheet, win.grid.selection, _("Align"), (st) => st.valign = v);
        }

        private void build_home (RibbonContext c) {
            menu (c, "edit-paste-symbolic", _("Paste"), false, (m) => {
                item (m, _("Paste"), "edit-paste-symbolic", "paste");
                item (m, _("Cut"), "edit-cut-symbolic", "cut");
                item (m, _("Copy"), "edit-copy-symbolic", "copy");
                m.add_separator ();
                item (m, _("Values Only"), null, "paste-values");
                item (m, _("Formats Only"), null, "paste-formats");
                item (m, _("Formulas Only"), null, "paste-formulas");
                item (m, _("Transpose"), null, "paste-transpose");
                m.add_separator ();
                item (m, _("Paste Special…"), null, "paste-special");
            });
            c.add_separator ();

            font_selector = c.add_selector (_("Font"), 9);
            font_selector.add_option ("", _("Default"));
            font_selector.add_separator ();
            foreach (string f in FONTS) font_selector.add_option (f, f);
            font_selector.add_extra ((m) => m.add_item (_("Other Font…"), null, () => choose_font ()));
            font_selector.changed.connect ((id) => set_font (id));
            size_selector = c.add_selector (_("Font Size"), 3);
            foreach (int s in SIZES) size_selector.add_option (s.to_string (), s.to_string ());
            size_selector.changed.connect ((id) => {
                if (win.grid == null) return;
                double v = double.parse (id);
                win.doc.edit_style (win.grid.sheet, win.grid.selection, _("Font Size"), (st) => st.font_size = v);
            });
            action_toggle (c, "bold", "format-text-bold-symbolic", _("Bold"), "bold");
            action_toggle (c, "italic", "format-text-italic-symbolic", _("Italic"), "italic");
            action_toggle (c, "underline", "format-text-underline-symbolic", _("Underline"), "underline");
            action_toggle (c, "strike", "format-text-strikethrough-symbolic", _("Strikethrough"), "strike");
            menu (c, "sheet-borders-symbolic", _("Borders"), false, (m) => {
                border_item (m, _("All Borders"), "all", BorderStyle.THIN);
                border_item (m, _("Outside Borders"), "outer", BorderStyle.THIN);
                border_item (m, _("Inside Borders"), "inner", BorderStyle.THIN);
                border_item (m, _("Top Border"), "top", BorderStyle.THIN);
                border_item (m, _("Bottom Border"), "bottom", BorderStyle.THIN);
                border_item (m, _("Left Border"), "left", BorderStyle.THIN);
                border_item (m, _("Right Border"), "right", BorderStyle.THIN);
                border_item (m, _("No Border"), "none", BorderStyle.NONE);
                m.add_separator ();
                border_item (m, _("Thick Outside Borders"), "outer", BorderStyle.THICK);
                border_item (m, _("Double Bottom Border"), "bottom", BorderStyle.DOUBLE);
                m.add_separator ();
                item (m, _("More Borders…"), null, "format-cells");
            });
            menu (c, "sheet-fill-symbolic", _("Fill Color"), false, (m) => color_menu (m, false));
            menu (c, "sheet-text-color-symbolic", _("Font Color"), false, (m) => color_menu (m, true));
            c.add_separator ();

            valign_menu = menu (c, "sheet-valign-bottom-symbolic", _("Vertical Alignment"), false, (m) => {
                var cur = win.grid != null ? win.grid.sheet.style_at (win.grid.cur_row, win.grid.cur_col).valign : VAlign.BOTTOM;
                m.add_item (_("Top Align"), "sheet-valign-top-symbolic", () => valign (VAlign.TOP), cur == VAlign.TOP ? "checked" : null);
                m.add_item (_("Middle Align"), "sheet-valign-center-symbolic", () => valign (VAlign.CENTER), cur == VAlign.CENTER ? "checked" : null);
                m.add_item (_("Bottom Align"), "sheet-valign-bottom-symbolic", () => valign (VAlign.BOTTOM), cur == VAlign.BOTTOM ? "checked" : null);
            });
            action_toggle (c, "align-left", "format-justify-left-symbolic", _("Align Left"), "align-left");
            action_toggle (c, "align-center", "format-justify-center-symbolic", _("Center"), "align-center");
            action_toggle (c, "align-right", "format-justify-right-symbolic", _("Align Right"), "align-right");
            menu (c, "object-rotate-left-symbolic", _("Orientation"), false, (m) => {
                item (m, _("Angle Counterclockwise"), null, "rotate-ccw");
                item (m, _("Angle Clockwise"), null, "rotate-cw");
                item (m, _("Vertical Text"), null, "rotate-vertical");
                item (m, _("Rotate Text Up"), null, "rotate-up");
                item (m, _("Rotate Text Down"), null, "rotate-down");
                item (m, _("Horizontal"), null, "rotate-none");
                m.add_separator ();
                item (m, _("Shrink to Fit"), null, "shrink-to-fit");
            });
            action_toggle (c, "wrap", "sheet-wrap-symbolic", _("Wrap Text"), "wrap");
            menu (c, "sheet-merge-symbolic", _("Merge"), false, (m) => {
                item (m, _("Merge and Center"), "sheet-merge-symbolic", "merge-center");
                item (m, _("Merge Cells"), null, "merge");
                item (m, _("Unmerge Cells"), null, "unmerge");
            });
            c.add_separator ();

            number_selector = c.add_selector (_("Number Format"), 9);
            number_selector.add_option ("fmt-general", _("General"));
            number_selector.add_option ("fmt-number", _("Number"));
            number_selector.add_option ("fmt-currency", _("Currency"));
            number_selector.add_option ("fmt-percent", _("Percentage"));
            number_selector.add_option ("fmt-scientific", _("Scientific"));
            number_selector.add_option ("fmt-date", _("Date"));
            number_selector.add_option ("fmt-time", _("Time"));
            number_selector.add_option ("fmt-text", _("Text"));
            number_selector.add_separator ();
            number_selector.add_extra ((m) => item (m, _("More Number Formats…"), null, "format-cells"));
            number_selector.text = _("General");
            number_selector.changed.connect ((id) => win.run (id));
            button (c, "sheet-decimals-more-symbolic", _("Increase Decimal"), "dec-inc");
            button (c, "sheet-decimals-less-symbolic", _("Decrease Decimal"), "dec-dec");
            c.add_separator ();

            menu (c, "sheet-cond-format-symbolic", _("Conditional Formatting"), false, (m) => {
                item (m, _("New Rule…"), "list-add-symbolic", "cond-format");
                item (m, _("Manage Rules…"), null, "cond-manage");
                m.add_separator ();
                item (m, _("Clear Rules from Selection"), "edit-clear-symbolic", "clear-rules");
            });
            button (c, "sheet-cell-styles-symbolic", _("Cell Styles"), "cell-styles");
            c.add_separator ();

            menu (c, "sheet-insert-cells-symbolic", _("Insert"), false, (m) => {
                item (m, _("Insert Cells"), null, "insert-cells");
                item (m, _("Insert Rows Above"), null, "insert-rows-above");
                item (m, _("Insert Rows Below"), null, "insert-rows-below");
                item (m, _("Insert Columns Left"), null, "insert-cols-left");
                item (m, _("Insert Columns Right"), null, "insert-cols-right");
                m.add_separator ();
                item (m, _("Insert Sheet"), "list-add-symbolic", "insert-sheet");
            });
            menu (c, "sheet-delete-cells-symbolic", _("Delete"), false, (m) => {
                item (m, _("Delete Cells"), null, "delete-cells");
                item (m, _("Delete Rows"), null, "delete-rows");
                item (m, _("Delete Columns"), null, "delete-cols");
                m.add_separator ();
                item (m, _("Delete Sheet"), "user-trash-symbolic", "sheet-delete");
            });
            menu (c, "sheet-format-symbolic", _("Format"), false, (m) => {
                item (m, _("Row Height…"), null, "row-height");
                item (m, _("Autofit Row Height"), null, "autofit-rows");
                item (m, _("Column Width…"), null, "col-width");
                item (m, _("Autofit Column Width"), null, "autofit-cols");
                m.add_separator ();
                var vis = m.add_submenu (_("Hide and Unhide"), "view-conceal-symbolic");
                item (vis, _("Hide Rows"), null, "hide-rows");
                item (vis, _("Hide Columns"), null, "hide-cols");
                item (vis, _("Unhide Rows"), null, "unhide-rows");
                item (vis, _("Unhide Columns"), null, "unhide-cols");
                vis.add_separator ();
                item (vis, _("Hide Sheet"), null, "sheet-hide");
                item (vis, _("Unhide Sheet…"), null, "sheet-unhide");
                item (m, _("Rename Sheet"), "document-edit-symbolic", "sheet-rename");
                item (m, _("Duplicate Sheet"), "edit-copy-symbolic", "sheet-duplicate");
                m.add_separator ();
                item (m, _("Lock Cell"), "changes-prevent-symbolic", "toggle-locked");
                item (m, _("Format Cells…"), "sheet-format-symbolic", "format-cells");
            });
            c.add_separator ();

            button (c, "sheet-autosum-symbolic", _("AutoSum"), "autosum");
            menu (c, "sheet-fill-down-symbolic", _("Fill"), false, (m) => {
                item (m, _("Down"), null, "fill-down");
                item (m, _("Right"), null, "fill-right");
                item (m, _("Series…"), null, "fill-series");
                item (m, _("Flash Fill"), "sheet-flash-fill-symbolic", "flash-fill");
            });
            menu (c, "edit-clear-all-symbolic", _("Clear"), false, (m) => {
                item (m, _("Clear All"), null, "clear-all");
                item (m, _("Clear Formats"), null, "clear-formats");
                item (m, _("Clear Contents"), null, "clear-contents");
            });
            menu (c, "view-sort-ascending-symbolic", _("Sort and Filter"), false, (m) => {
                item (m, _("Sort A to Z"), "view-sort-ascending-symbolic", "sort-asc");
                item (m, _("Sort Z to A"), "view-sort-descending-symbolic", "sort-desc");
                item (m, _("Custom Sort…"), null, "sort-custom");
                m.add_separator ();
                item (m, _("Filter"), "sheet-filter-symbolic", "filter");
                item (m, _("Clear Filter"), null, "filter-clear");
                item (m, _("Reapply Filter"), null, "filter-reapply");
            });
            menu (c, "edit-find-symbolic", _("Find and Select"), false, (m) => {
                item (m, _("Find and Replace…"), "edit-find-replace-symbolic", "find");
                item (m, _("Go To…"), "go-jump-symbolic", "goto");
                item (m, _("Go To Special…"), null, "goto-special");
                m.add_separator ();
                item (m, _("Select All"), "edit-select-all-symbolic", "select-all");
            });
        }

        private void build_insert (RibbonContext c) {
            menu (c, "sheet-pivot-symbolic", _("PivotTable"), true, (m) => {
                item (m, _("New PivotTable…"), "sheet-pivot-symbolic", "pivot-insert");
                item (m, _("PivotTable Fields"), null, "pivot-panel");
                item (m, _("Refresh Pivot Tables"), "view-refresh-symbolic", "pivot-refresh");
            });
            button (c, "sheet-table-symbolic", _("Table"), "insert-table", true);
            c.add_separator ();
            button (c, "insert-image-symbolic", _("Picture"), "insert-picture", true);
            menu (c, "sheet-shapes-symbolic", _("Shapes"), true, (m) => {
                item (m, _("Rectangle"), null, "insert-shape-rect");
                item (m, _("Rounded Rectangle"), null, "insert-shape-rounded");
                item (m, _("Oval"), null, "insert-shape-ellipse");
                item (m, _("Line"), null, "insert-shape-line");
                item (m, _("Arrow"), null, "insert-shape-arrow");
            });
            button (c, "insert-text-symbolic", _("Text Box"), "insert-textbox");
            button (c, "sheet-diagram-symbolic", _("Diagram"), "insert-diagram");
            c.add_separator ();
            button (c, "sheet-chart-symbolic", _("Chart"), "insert-chart", true);
            menu (c, "sheet-sparkline-symbolic", _("Sparklines"), false, (m) => {
                item (m, _("Insert Sparklines…"), "sheet-sparkline-symbolic", "insert-sparklines");
                item (m, _("Clear Sparklines"), "edit-clear-symbolic", "clear-sparklines");
            });
            c.add_separator ();
            button (c, "insert-link-symbolic", _("Link"), "insert-link");
            button (c, "sheet-comment-symbolic", _("Comment"), "comment-new");
            button (c, "sheet-note-symbolic", _("Note"), "note");
            c.add_separator ();
            button (c, "sheet-function-symbolic", _("Function"), "insert-function");
            menu (c, "x-office-calendar-symbolic", _("Date and Time"), false, (m) => {
                item (m, _("Today's Date"), null, "insert-date");
                item (m, _("Current Time"), null, "insert-time");
            });
            button (c, "list-add-symbolic", _("New Sheet"), "insert-sheet");
        }

        private void build_layout (RibbonContext c) {
            button (c, "preferences-color-symbolic", _("Themes"), "themes", true);
            c.add_separator ();
            button (c, "document-page-setup-symbolic", _("Page Setup"), "page-setup", true);
            menu (c, "sheet-print-area-symbolic", _("Print Area"), false, (m) => {
                item (m, _("Set Print Area"), null, "print-area-set");
                item (m, _("Add to Print Area"), null, "print-area-add");
                item (m, _("Clear Print Area"), null, "print-area-clear");
            });
            menu (c, "sheet-page-break-symbolic", _("Breaks"), false, (m) => {
                item (m, _("Insert Page Break"), null, "page-break-insert");
                item (m, _("Remove Page Break"), null, "page-break-remove");
                item (m, _("Reset All Page Breaks"), null, "page-break-reset");
            });
            button (c, "sheet-print-titles-symbolic", _("Print Titles"), "print-titles");
            c.add_separator ();
            c.add_toggle ("view-grid-symbolic", _("Gridlines"), null, "win.gridlines");
            c.add_toggle ("view-paged-symbolic", _("Page Break Preview"), null, "win.page-break-preview");
            c.add_separator ();
            button (c, "document-print-symbolic", _("Print"), "print", true);
            button (c, "x-office-document-symbolic", _("Export as PDF"), "export-pdf");
        }

        private void build_formulas (RibbonContext c) {
            button (c, "sheet-function-symbolic", _("Insert Function"), "insert-function", true);
            button (c, "sheet-autosum-symbolic", _("AutoSum"), "autosum");
            c.add_separator ();
            category (c, "sheet-fn-financial-symbolic", _("Financial"), "Financial");
            category (c, "dialog-question-symbolic", _("Logical"), "Logical");
            category (c, "insert-text-symbolic", _("Text"), "Text");
            category (c, "x-office-calendar-symbolic", _("Date and Time"), "Date");
            category (c, "edit-find-symbolic", _("Lookup"), "Lookup", _("Lookup and Reference Functions"));
            category (c, "accessories-calculator-symbolic", _("Math and Trig"), "Math");
            var more = menu (c, "view-more-symbolic", _("More Functions"), true, (m) => {
                string[] keys = { "Statistical", "Engineering", "Information", "Database", "Cube", "Web", "Compatibility" };
                string[] labels = { _("Statistical"), _("Engineering"), _("Information"), _("Database"), _("Cube"), _("Web"), _("Compatibility") };
                for (int i = 0; i < keys.length; i++) {
                    string k = keys[i];
                    m.add_item (labels[i], null, () => win.pick_function (k, null));
                }
            });
            more.tooltip = _("Statistical, engineering and other functions");
            c.add_separator ();
            button (c, "sheet-names-symbolic", _("Name Manager"), "names", true);
            button (c, "document-edit-symbolic", _("Define Name"), "goto", false, _("Define Name: type a name in the name box to name the selection"));
            c.add_separator ();
            button (c, "sheet-trace-precedents-symbolic", _("Trace Precedents"), "trace-precedents");
            button (c, "sheet-trace-dependents-symbolic", _("Trace Dependents"), "trace-dependents");
            button (c, "sheet-remove-arrows-symbolic", _("Remove Arrows"), "remove-arrows");
            c.add_toggle ("sheet-show-formulas-symbolic", _("Show Formulas"), null, "win.show-formulas");
            menu (c, "dialog-warning-symbolic", _("Error Checking"), false, (m) => {
                item (m, _("Error Checking…"), "dialog-warning-symbolic", "error-checking");
                item (m, _("Circular References…"), null, "circular-refs");
            });
            button (c, "sheet-evaluate-symbolic", _("Evaluate Formula"), "evaluate-formula");
            button (c, "view-reveal-symbolic", _("Watch Window"), "watch-window");
            c.add_separator ();
            button (c, "document-properties-symbolic", _("Calculation Options"), "calc-options");
            button (c, "view-refresh-symbolic", _("Calculate Now"), "recalc");
        }

        private void category (RibbonContext c, string icon, string label, string key, string? tip = null) {
            var b = c.add_button (icon, label, tip ?? _("%s Functions").printf (label));
            b.label_in_compact = true;
            b.activated.connect (() => win.pick_function (key, b.button));
        }

        private void build_data (RibbonContext c) {
            button (c, "sheet-get-data-symbolic", _("Get Data"), "get-data", true);
            button (c, "view-list-symbolic", _("Queries and Connections"), "queries");
            button (c, "view-refresh-symbolic", _("Refresh All"), "refresh-all");
            button (c, "view-dual-symbolic", _("Data Model"), "data-model");
            c.add_separator ();
            menu (c, "sheet-data-types-symbolic", _("Data Types"), true, (m) => {
                item (m, _("Geography"), "find-location-symbolic", "data-type-geography");
                item (m, _("Stocks"), "sheet-chart-line-symbolic", "data-type-stocks");
                item (m, _("From a Table or Query…"), null, "data-type-convert");
                m.add_separator ();
                item (m, _("Refresh Data Types"), "view-refresh-symbolic", "data-type-refresh");
                item (m, _("Show Data Card"), null, "data-type-card");
                item (m, _("Insert Data Field…"), null, "data-type-field");
            });
            c.add_separator ();
            button (c, "view-sort-ascending-symbolic", _("Sort A to Z"), "sort-asc");
            button (c, "view-sort-descending-symbolic", _("Sort Z to A"), "sort-desc");
            button (c, null, _("Sort"), "sort-custom", false, _("Custom Sort"));
            action_toggle (c, "filter", "sheet-filter-symbolic", _("Filter"), "filter");
            button (c, "edit-clear-symbolic", _("Clear Filter"), "filter-clear");
            button (c, "view-refresh-symbolic", _("Reapply Filter"), "filter-reapply");
            button (c, "sheet-filter-advanced-symbolic", _("Advanced Filter"), "advanced-filter");
            c.add_separator ();
            button (c, "sheet-text-columns-symbolic", _("Text to Columns"), "text-to-columns");
            button (c, "sheet-flash-fill-symbolic", _("Flash Fill"), "flash-fill");
            button (c, "sheet-remove-dups-symbolic", _("Remove Duplicates"), "remove-dups");
            menu (c, "sheet-validation-symbolic", _("Data Validation"), false, (m) => {
                item (m, _("Data Validation…"), "sheet-validation-symbolic", "validation");
                item (m, _("Circle Invalid Data"), null, "circle-invalid");
                item (m, _("Clear Validation Circles"), null, "clear-circles");
            });
            button (c, "sheet-consolidate-symbolic", _("Consolidate"), "consolidate");
            c.add_separator ();
            menu (c, "dialog-question-symbolic", _("What-If Analysis"), true, (m) => {
                item (m, _("Goal Seek…"), null, "goal-seek");
                item (m, _("Scenario Manager…"), null, "scenarios");
                item (m, _("Data Table…"), null, "data-table");
            });
            button (c, "sheet-chart-line-symbolic", _("Forecast Sheet"), "forecast-sheet");
            button (c, "sheet-solver-symbolic", _("Solver"), "solver");
            button (c, "sheet-chart-column-symbolic", _("Data Analysis"), "data-analysis");
            c.add_separator ();
            button (c, "sheet-group-symbolic", _("Group"), "group");
            button (c, "sheet-ungroup-symbolic", _("Ungroup"), "ungroup");
            button (c, "sheet-subtotal-symbolic", _("Subtotal"), "subtotals");
            menu (c, "view-list-bullet-symbolic", _("Outline"), false, (m) => {
                item (m, _("Show Detail"), null, "show-detail");
                item (m, _("Hide Detail"), null, "hide-detail");
                m.add_separator ();
                item (m, _("Auto Outline"), null, "auto-outline");
                item (m, _("Clear Outline"), null, "clear-outline");
                item (m, _("Outline Settings…"), null, "outline-settings");
            });
        }

        private void build_review (RibbonContext c) {
            button (c, "tools-check-spelling-symbolic", _("Spelling"), "spelling", true);
            button (c, "preferences-desktop-accessibility-symbolic", _("Check Accessibility"), "check-accessibility");
            c.add_separator ();
            button (c, "sheet-comment-symbolic", _("New Comment"), "comment-new", true);
            button (c, "user-trash-symbolic", _("Delete Comment"), "comment-delete");
            button (c, "sidebar-show-right-symbolic", _("Show Comments"), "comments-panel");
            button (c, "sheet-note-symbolic", _("Note"), "note");
            c.add_separator ();
            button (c, "changes-prevent-symbolic", _("Protect Sheet"), "protect-sheet", true);
            button (c, "security-high-symbolic", _("Protect Workbook"), "protect-book");
            button (c, "changes-allow-symbolic", _("Allow Edit Ranges"), "edit-ranges");
            button (c, "dialog-password-symbolic", _("Encrypt with Password"), "encrypt");
            action_toggle (c, "locked", "changes-prevent-symbolic", _("Lock Cell"), "toggle-locked");
            action_toggle (c, "hidden", "view-conceal-symbolic", _("Hide Formula"), "toggle-hidden-formula");
            c.add_separator ();
            var track = c.add_toggle ("document-edit-symbolic", _("Track Changes"), null, "win.track-changes");
            track.label_in_compact = true;
            menu (c, "object-select-symbolic", _("Changes"), false, (m) => {
                item (m, _("Review Changes…"), null, "review-changes");
                item (m, _("Accept All Changes"), "object-select-symbolic", "accept-all-changes");
                item (m, _("Reject All Changes"), "edit-undo-symbolic", "reject-all-changes");
                m.add_separator ();
                item (m, _("History Sheet"), null, "history-sheet");
                item (m, _("Compare and Merge Workbooks…"), null, "compare-merge");
            });
            c.add_separator ();
            button (c, "system-users-symbolic", _("Edit Together"), "edit-together", true);
            button (c, "document-open-recent-symbolic", _("Version History"), "version-history");
        }

        private void build_view (RibbonContext c) {
            var preview = c.add_toggle ("view-paged-symbolic", _("Page Break Preview"), null, "win.page-break-preview");
            preview.label_in_compact = true;
            button (c, "view-grid-symbolic", _("Custom Views"), "custom-views");
            c.add_separator ();
            c.add_toggle ("view-grid-symbolic", _("Gridlines"), null, "win.gridlines");
            c.add_toggle ("sheet-show-formulas-symbolic", _("Show Formulas"), null, "win.show-formulas");
            c.add_separator ();
            button (c, "zoom-out-symbolic", _("Zoom Out"), "zoom-out");
            zoom_selector = c.add_selector (_("Zoom"), 5);
            foreach (int z in ZOOMS) zoom_selector.add_option (z.to_string (), "%d%%".printf (z));
            zoom_selector.text = "100%";
            zoom_selector.changed.connect ((id) => {
                if (win.grid != null) win.grid.zoom_to (int.parse (id) / 100.0);
            });
            button (c, "zoom-in-symbolic", _("Zoom In"), "zoom-in");
            button (c, "zoom-original-symbolic", _("Actual Size"), "zoom-reset");
            c.add_separator ();
            button (c, "window-new-symbolic", _("New Window"), "new-window");
            button (c, "sheet-split-symbolic", _("Split"), "split-window");
            menu (c, "sheet-freeze-symbolic", _("Freeze Panes"), true, (m) => {
                item (m, _("Freeze at Selection"), null, "freeze");
                item (m, _("Freeze Top Row"), null, "freeze-row");
                item (m, _("Freeze First Column"), null, "freeze-col");
                m.add_separator ();
                item (m, _("Unfreeze Panes"), null, "unfreeze");
            });
            c.add_separator ();
            menu (c, "text-x-script-symbolic", _("Macros"), true, (m) => {
                item (m, _("View Macros…"), "media-playback-start-symbolic", "macros");
                item (m, _("Record Macro"), "media-record-symbolic", "macro-record");
                item (m, _("Script Editor"), "text-x-script-symbolic", "script-editor");
            });
        }

        private void border_item (ContextMenu m, string label, string which, BorderStyle style) {
            string icon = "sheet-border-%s-symbolic".printf (which == "outer" ? "outer" : which);
            m.add_item (label, icon, () => {
                if (win.grid == null) return;
                win.doc.edit_borders (win.grid.sheet, win.grid.selection, which, style, "");
            });
        }

        private void apply_color (bool text, string color) {
            if (win.grid == null) return;
            if (text) win.doc.edit_style (win.grid.sheet, win.grid.selection, _("Font Color"), (s) => s.color = color);
            else win.doc.edit_style (win.grid.sheet, win.grid.selection, _("Fill Color"), (s) => s.fill = color);
        }

        private void color_menu (ContextMenu m, bool text) {
            m.add_item (text ? _("Automatic") : _("No Fill"), text ? "sheet-text-color-symbolic" : "sheet-fill-symbolic", () => apply_color (text, ""));
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.max_children_per_line = 9;
            flow.min_children_per_line = 9;
            flow.column_spacing = 2;
            flow.row_spacing = 2;
            flow.homogeneous = true;
            flow.margin_start = flow.margin_end = 6;
            flow.margin_top = flow.margin_bottom = 4;
            foreach (string col in SWATCHES) {
                string cc = col;
                var b = new Button ();
                b.add_css_class ("ss-swatch");
                b.tooltip_text = col;
                var dot = new DrawingArea ();
                dot.set_size_request (18, 18);
                dot.set_draw_func ((a, cr, w, h) => {
                    var rgba = Gdk.RGBA ();
                    rgba.parse (cc);
                    cr.arc (w / 2.0, h / 2.0, 8, 0, 2 * Math.PI);
                    cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, 1);
                    cr.fill_preserve ();
                    var fg = a.get_color ();
                    cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.22);
                    cr.set_line_width (1);
                    cr.stroke ();
                });
                b.child = dot;
                b.clicked.connect (() => {
                    m.popdown ();
                    apply_color (text, cc);
                });
                flow.append (b);
            }
            m.add_widget (flow);
            m.add_item (_("Other Color…"), "preferences-color-symbolic", () => {
                var d = new ColorDialog ();
                d.with_alpha = false;
                d.choose_rgba.begin (win, null, null, (o, r) => {
                    try {
                        var c = d.choose_rgba.end (r);
                        apply_color (text, "#%02x%02x%02x".printf ((int) (c.red * 255), (int) (c.green * 255), (int) (c.blue * 255)));
                    } catch (Error e) {
                    }
                });
            });
        }

        private void set_font (string family) {
            if (win.grid == null) return;
            win.doc.edit_style (win.grid.sheet, win.grid.selection, _("Font"), (st) => st.font_family = family);
        }

        private void choose_font () {
            var d = new FontDialog ();
            d.choose_family.begin (win, null, null, (o, r) => {
                try {
                    var fam = d.choose_family.end (r);
                    if (fam != null) set_font (fam.get_name ());
                } catch (Error e) {
                }
            });
        }

        private static string number_label (string code) {
            if (code == "" || code == "General") return _("General");
            if (code == "@") return _("Text");
            if (code.contains ("E+") || code.contains ("e+")) return _("Scientific");
            if (code.strip ().has_suffix ("%")) return _("Percentage");
            if (NumberFormat.is_date_format (code)) {
                string low = code.down ();
                return (low.contains ("d") || low.contains ("y")) ? _("Date") : _("Time");
            }
            if (code.contains ("$") || code.contains ("€") || code.contains ("£") || code.contains ("¥") || code.contains ("[$")) return _("Currency");
            foreach (string part in code.split (";")) {
                for (int i = 0; i < part.length; i++) {
                    char ch = part[i];
                    if (ch != '0' && ch != '#' && ch != ',' && ch != '.' && ch != '?' && ch != ' ') return _("Custom");
                }
            }
            return _("Number");
        }

        private void set_cell_toggle (string key, bool on) {
            var t = cell_toggles[key];
            if (t != null) t.active = on;
        }

        public void sync () {
            if (win == null || win.grid == null || win.doc == null) return;
            syncing = true;
            var st = win.grid.sheet.style_at (win.grid.cur_row, win.grid.cur_col);
            set_cell_toggle ("bold", st.bold);
            set_cell_toggle ("italic", st.italic);
            set_cell_toggle ("underline", st.underline);
            set_cell_toggle ("strike", st.strike);
            valign_menu.icon_name = st.valign == VAlign.TOP ? "sheet-valign-top-symbolic" : st.valign == VAlign.CENTER ? "sheet-valign-center-symbolic" : "sheet-valign-bottom-symbolic";
            set_cell_toggle ("align-left", st.halign == HAlign.LEFT);
            set_cell_toggle ("align-center", st.halign == HAlign.CENTER);
            set_cell_toggle ("align-right", st.halign == HAlign.RIGHT);
            set_cell_toggle ("wrap", st.wrap);
            set_cell_toggle ("locked", st.locked);
            set_cell_toggle ("hidden", st.hidden);
            set_cell_toggle ("filter", win.grid.sheet.filter != null);
            font_selector.selected = st.font_family;
            if (st.font_family == "") font_selector.text = _("Default");
            else font_selector.text = st.font_family;
            string size = "%g".printf (st.font_size);
            size_selector.selected = size;
            size_selector.text = size;
            number_selector.text = number_label (st.number_format);
            var grid_lines = win.lookup_action ("gridlines") as SimpleAction;
            if (grid_lines != null) grid_lines.set_state (new Variant.boolean (win.grid.sheet.show_grid));
            var formulas = win.lookup_action ("show-formulas") as SimpleAction;
            if (formulas != null) formulas.set_state (new Variant.boolean (win.grid.show_formulas));
            sync_zoom ();
            syncing = false;
        }

        public void sync_zoom () {
            if (win == null || win.grid == null) return;
            int z = (int) Math.round (win.grid.zoom * 100);
            zoom_selector.selected = z.to_string ();
            zoom_selector.text = "%d%%".printf (z);
        }
    }
}
