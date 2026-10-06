using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class EditActions {

        public delegate void Handler (SpreadsheetWindow win);

        private static void add (SpreadsheetWindow win, string name, owned Handler handler) {
            var a = new SimpleAction (name, null);
            a.activate.connect (() => {
                if (win.doc == null || win.grid == null) return;
                if (refuse (win, name)) return;
                handler (win);
            });
            win.add_action (a);
        }

        private static void rotate (SpreadsheetWindow win, int angle) {
            win.doc.edit_style (win.grid.sheet, win.grid.selection, _("Text Orientation"), (st) => st.rotation = angle);
        }

        private static GLib.Settings? _settings;
        private static bool settings_tried;

        public static GLib.Settings? settings () {
            if (settings_tried) return _settings;
            settings_tried = true;
            var src = SettingsSchemaSource.get_default ();
            if (src == null || src.lookup ("dev.sinty.spreadsheet", true) == null) return null;
            _settings = new GLib.Settings ("dev.sinty.spreadsheet");
            CustomLists.set_user_text (_settings.get_string ("custom-lists"));
            _settings.changed["custom-lists"].connect (() => CustomLists.set_user_text (_settings.get_string ("custom-lists")));
            CommentStore.author_name = _settings.get_string ("author-name");
            _settings.changed["author-name"].connect (() => CommentStore.author_name = _settings.get_string ("author-name"));
            return _settings;
        }

        public static void save_user_lists (Gee.List<string> lists) {
            CustomLists.user ().clear ();
            CustomLists.user ().add_all (lists);
            var st = settings ();
            if (st != null) st.set_string ("custom-lists", CustomLists.user_text ());
        }

        public static void install (SpreadsheetWindow win) {
            settings ();
            add (win, "protect-sheet", (w) => EditDialogs.protect_sheet (w));
            add (win, "protect-book", (w) => EditDialogs.protect_book (w));
            add (win, "edit-ranges", (w) => EditDialogs.edit_ranges (w));
            add (win, "encrypt", (w) => EditDialogs.encrypt (w));
            add (win, "toggle-locked", (w) => {
                bool on = !w.grid.sheet.style_at (w.grid.cur_row, w.grid.cur_col).locked;
                w.doc.edit_style (w.grid.sheet, w.grid.selection, _("Lock Cell"), (st) => st.locked = on);
            });
            add (win, "toggle-hidden-formula", (w) => {
                bool on = !w.grid.sheet.style_at (w.grid.cur_row, w.grid.cur_col).hidden;
                w.doc.edit_style (w.grid.sheet, w.grid.selection, _("Hide Formula"), (st) => st.hidden = on);
            });
            add (win, "validation-rules", (w) => EditDialogs.validation (w));
            add (win, "circle-invalid", (w) => {
                var list = ValidationCheck.invalid_cells (w.doc.book, w.grid.sheet);
                w.grid.invalid_circles = list;
                w.grid.queue_draw ();
                if (list.size == 0) EditDialogs.message (w, _("Circle Invalid Data"), _("All cells meet their validation rules."));
            });
            add (win, "clear-circles", (w) => {
                w.grid.invalid_circles = null;
                w.grid.queue_draw ();
            });
            add (win, "group", (w) => EditDialogs.group (w, false));
            add (win, "ungroup", (w) => EditDialogs.group (w, true));
            add (win, "auto-outline", (w) => {
                int n = EditCommands.auto_outline (w.doc, w.grid.sheet);
                w.grid.refresh ();
                if (n == 0) EditDialogs.message (w, _("Auto Outline"), _("No summary formulas were found to build an outline from."));
            });
            add (win, "clear-outline", (w) => {
                EditCommands.clear_outline (w.doc, w.grid.sheet);
                w.grid.refresh ();
            });
            add (win, "outline-settings", (w) => EditDialogs.outline_settings (w));
            add (win, "show-detail", (w) => detail (w, false));
            add (win, "hide-detail", (w) => detail (w, true));
            add (win, "text-to-columns", (w) => EditDialogs.text_to_columns (w));
            add (win, "flash-fill", (w) => {
                int n = FlashFill.fill (w.doc, w.grid.sheet, w.grid.cur_row, w.grid.cur_col);
                if (n == 0) EditDialogs.message (w, _("Flash Fill"), _("Flash Fill didn't recognize a pattern. Type a couple more examples in the column and try again."), "dialog-warning");
            });
            add (win, "cell-styles", (w) => EditDialogs.cell_styles (w));
            add (win, "themes", (w) => EditDialogs.themes (w));
            add (win, "custom-views", (w) => EditDialogs.custom_views (w));
            add (win, "goto-special", (w) => EditDialogs.goto_special (w));
            add (win, "paste-special", (w) => EditDialogs.paste_special (w));
            add (win, "rotate-up", (w) => rotate (w, 90));
            add (win, "rotate-down", (w) => rotate (w, -90));
            add (win, "rotate-ccw", (w) => rotate (w, 45));
            add (win, "rotate-cw", (w) => rotate (w, -45));
            add (win, "rotate-vertical", (w) => rotate (w, 255));
            add (win, "rotate-none", (w) => rotate (w, 0));
            add (win, "shrink-to-fit", (w) => {
                bool on = !w.grid.sheet.style_at (w.grid.cur_row, w.grid.cur_col).shrink;
                w.doc.edit_style (w.grid.sheet, w.grid.selection, _("Shrink to Fit"), (st) => st.shrink = on);
            });
            add (win, "new-window", (w) => {
                var nw = new SpreadsheetWindow ((SpreadsheetApp) w.application);
                nw.set_default_size (int.max (w.get_width () * 3 / 4, 640), int.max (w.get_height () * 3 / 4, 480));
                nw.present ();
                nw.load_document (w.doc);
                nw.grid.show_sheet (w.grid.sheet);
            });
            add (win, "split-window", (w) => w.toggle_split ());
            add (win, "filter-clear", (w) => {
                EditCommands.clear_filters (w.doc, w.grid.sheet);
                w.grid.refresh ();
            });
            add (win, "filter-reapply", (w) => {
                EditCommands.reapply_filter (w.doc, w.grid.sheet);
                w.grid.refresh ();
            });
            add (win, "fill-series", (w) => EditDialogs.fill_series (w));
            add (win, "custom-lists", (w) => EditDialogs.custom_lists (w));
        }

        private static void detail (SpreadsheetWindow w, bool hide) {
            var s = w.grid.sheet;
            bool rows = !(w.grid.selection.r1 == 0 && w.grid.selection.r2 == MAX_ROWS - 1);
            int idx = rows ? w.grid.cur_row : w.grid.cur_col;
            OutlineGroup? best = null;
            foreach (var g in s.outline.groups (rows)) {
                if ((idx >= g.start && idx <= g.end) || idx == g.summary) {
                    if (best == null || g.level > best.level) best = g;
                }
            }
            if (best == null) return;
            EditCommands.collapse (w.doc, s, rows, best, hide);
            w.grid.refresh ();
        }

        private static bool mutating (string name) {
            switch (name) {
                case "cut": case "paste": case "paste-values": case "paste-formats": case "paste-formulas": case "paste-transpose":
                case "clear-contents": case "clear-formats": case "clear-all": case "fill-down": case "fill-right": case "autosum":
                case "insert-date": case "insert-time": case "note": case "merge-center": case "merge": case "unmerge":
                case "flash-fill": case "text-to-columns": case "paste-special": case "remove-dups":
                    return true;
                default:
                    return false;
            }
        }

        private static bool formatting (string name) {
            return name.has_prefix ("fmt-") || name.has_prefix ("align-") || name.has_prefix ("rotate-") || name == "bold" || name == "italic"
                || name == "underline" || name == "strike" || name == "wrap" || name == "dec-inc" || name == "dec-dec" || name == "format-cells"
                || name == "cell-styles" || name == "shrink-to-fit" || name == "cond-format" || name == "clear-rules" || name == "toggle-locked" || name == "toggle-hidden-formula";
        }

        public delegate void Run ();

        private static bool per_area (string name) {
            return formatting (name) || name == "clear-contents" || name == "clear-formats" || name == "clear-all" || name == "merge-center" || name == "merge" || name == "unmerge";
        }

        public static bool multi (SpreadsheetWindow win, string name, Run run) {
            var g = win.grid;
            if (g == null || g.selection_areas == null || g.selection_areas.size == 0) return false;
            if (name == "copy" || name == "cut") {
                var sb = new StringBuilder ();
                foreach (var a in g.all_areas ()) {
                    var clamped = Document.clamp_area (g.sheet, a);
                    for (int r = clamped.r1; r <= int.min (clamped.r2, int.max (g.sheet.max_row, clamped.r1)); r++) {
                        for (int c = clamped.c1; c <= int.min (clamped.c2, int.max (g.sheet.max_col, clamped.c1)); c++) {
                            if (c > clamped.c1) sb.append_c ('\t');
                            sb.append (g.sheet.value_at (r, c).display ());
                        }
                        sb.append_c ('\n');
                    }
                }
                win.doc.clip = null;
                win.get_clipboard ().set_text (sb.str);
                if (name == "cut") foreach (var a in g.all_areas ()) win.doc.clear (g.sheet, a, ClearMode.CONTENTS);
                return true;
            }
            if (!per_area (name)) return false;
            var areas = g.all_areas ();
            var extra = g.selection_areas;
            foreach (var a in areas) {
                g.focus_area (a);
                run ();
                g.selection_areas = extra;
            }
            g.focus_area (areas[areas.size - 1]);
            g.selection_areas = extra;
            g.queue_draw ();
            return true;
        }

        private static bool locked_any (SpreadsheetWindow win) {
            foreach (var a in win.grid.all_areas ()) if (Protect.area_locked (win.grid.sheet, a)) return true;
            return false;
        }

        public static bool refuse (SpreadsheetWindow win, string name) {
            if (win.doc == null || win.grid == null) return false;
            var s = win.grid.sheet;
            var book = win.doc.book;
            string? why = null;
            if (s.protection != null) {
                if (mutating (name) && locked_any (win)) why = Protect.message ();
                else if (formatting (name) && !Protect.allowed (book, s, ProtectAction.FORMAT_CELLS)) why = Protect.message ();
                else if ((name == "insert-rows-above" || name == "insert-rows-below") && !Protect.allowed (book, s, ProtectAction.INSERT_ROWS)) why = Protect.message ();
                else if ((name == "insert-cols-left" || name == "insert-cols-right") && !Protect.allowed (book, s, ProtectAction.INSERT_COLUMNS)) why = Protect.message ();
                else if ((name == "delete-rows" || name == "delete-cells") && !Protect.allowed (book, s, ProtectAction.DELETE_ROWS)) why = Protect.message ();
                else if (name == "delete-cols" && !Protect.allowed (book, s, ProtectAction.DELETE_COLUMNS)) why = Protect.message ();
                else if (name == "insert-cells" && !Protect.allowed (book, s, ProtectAction.INSERT_ROWS)) why = Protect.message ();
                else if ((name == "sort-asc" || name == "sort-desc" || name == "sort-custom") && (!Protect.allowed (book, s, ProtectAction.SORT) || locked_any (win))) why = Protect.message ();
                else if (name == "filter" && !Protect.allowed (book, s, ProtectAction.AUTOFILTER)) why = Protect.message ();
                else if ((name == "col-width" || name == "hide-cols" || name == "unhide-cols" || name == "autofit-cols") && !Protect.allowed (book, s, ProtectAction.FORMAT_COLUMNS)) why = Protect.message ();
                else if ((name == "row-height" || name == "hide-rows" || name == "unhide-rows" || name == "autofit-rows") && !Protect.allowed (book, s, ProtectAction.FORMAT_ROWS)) why = Protect.message ();
                else if ((name == "insert-chart" || name == "group" || name == "ungroup" || name == "auto-outline" || name == "clear-outline" || name == "validation" || name == "validation-rules") && !Protect.allowed (book, s, ProtectAction.OBJECTS)) why = Protect.message ();
            }
            if (why == null && book.protection != null && book.protection.structure) {
                switch (name) {
                    case "insert-sheet": case "sheet-rename": case "sheet-duplicate": case "sheet-delete":
                        why = _("The workbook is protected, so sheets can't be added, deleted, renamed or moved. Unprotect the workbook from the Review menu to change its structure.");
                        break;
                }
            }
            if (why == null) return false;
            EditDialogs.message (win, _("Protected"), why, "dialog-warning");
            return true;
        }

        public static void attach (SpreadsheetWindow win, SheetView grid) {
            var pop = new Popover ();
            pop.autohide = false;
            pop.has_arrow = true;
            pop.position = PositionType.BOTTOM;
            pop.can_focus = false;
            pop.focusable = false;
            var box = new Box (Orientation.VERTICAL, 4);
            box.margin_start = box.margin_end = 10;
            box.margin_top = box.margin_bottom = 8;
            var title = new Label ("");
            title.xalign = 0;
            title.add_css_class ("heading");
            var text = new Label ("");
            text.xalign = 0;
            text.wrap = true;
            text.max_width_chars = 36;
            box.append (title);
            box.append (text);
            pop.child = box;
            pop.set_parent (grid);
            grid.destroy.connect (() => pop.unparent ());
            grid.selection_changed.connect (() => {
                var v = ValidationCheck.at (grid.sheet, grid.cur_row, grid.cur_col);
                if (v == null || !v.show_input || (v.message == "" && v.input_title == "")) {
                    pop.popdown ();
                    return;
                }
                title.label = v.input_title;
                title.visible = v.input_title != "";
                text.label = v.message;
                text.visible = v.message != "";
                var rect = grid.cell_rect (grid.cur_row, grid.cur_col);
                Gdk.Rectangle r = { (int) (rect.origin.x + rect.size.width * 0.6), (int) rect.origin.y, (int) (rect.size.width * 0.4), (int) rect.size.height };
                pop.pointing_to = r;
                pop.popup ();
                Idle.add (() => {
                    if (!grid.is_editing ()) grid.grab_focus ();
                    return Source.REMOVE;
                });
            });
            grid.edit_blocked.connect ((msg) => {
                var er = Protect.range_at (grid.sheet, grid.cur_row, grid.cur_col);
                if (er != null && er.password.is_set () && !er.unlocked) {
                    EditDialogs.unlock_range (win, er, () => grid.begin_edit (null, false));
                    return;
                }
                EditDialogs.message (win, _("Protected"), msg, "dialog-warning");
            });
            grid.entry_rejected.connect ((r, c, t, rule) => EditDialogs.rejected (win, r, c, t, rule));
        }

        private static GLib.Menu section (string[,] items) {
            var m = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) m.append (items[i, 0], items[i, 1]);
            return m;
        }

        public static void extend_menu (GLib.Menu menu, GLib.Menu edit, GLib.Menu view, GLib.Menu format, GLib.Menu data) {
            edit.append_section (null, section ({ { _("Paste Special…"), "win.paste-special" }, { _("Go To Special…"), "win.goto-special" } }));
            view.append_section (null, section ({ { _("Custom Views…"), "win.custom-views" }, { _("New Window"), "win.new-window" }, { _("Split"), "win.split-window" } }));
            var orient = section ({ { _("Angle Counterclockwise"), "win.rotate-ccw" }, { _("Angle Clockwise"), "win.rotate-cw" }, { _("Vertical Text"), "win.rotate-vertical" }, { _("Rotate Text Up"), "win.rotate-up" }, { _("Rotate Text Down"), "win.rotate-down" }, { _("Horizontal"), "win.rotate-none" } });
            var fsec = new GLib.Menu ();
            fsec.append_submenu (_("Text Orientation"), orient);
            fsec.append (_("Shrink to Fit"), "win.shrink-to-fit");
            fsec.append (_("Cell Styles…"), "win.cell-styles");
            fsec.append (_("Themes…"), "win.themes");
            format.append_section (null, fsec);
            data.append_section (null, section ({ { _("Circle Invalid Data"), "win.circle-invalid" }, { _("Clear Validation Circles"), "win.clear-circles" } }));
            data.append_section (null, section ({ { _("Clear Filter"), "win.filter-clear" }, { _("Reapply Filter"), "win.filter-reapply" } }));
            data.append_section (null, section ({ { _("Text to Columns…"), "win.text-to-columns" }, { _("Flash Fill"), "win.flash-fill" }, { _("Series…"), "win.fill-series" }, { _("Custom Lists…"), "win.custom-lists" } }));
            var outline = section ({ { _("Group…"), "win.group" }, { _("Ungroup…"), "win.ungroup" }, { _("Show Detail"), "win.show-detail" }, { _("Hide Detail"), "win.hide-detail" }, { _("Auto Outline"), "win.auto-outline" }, { _("Clear Outline"), "win.clear-outline" }, { _("Settings…"), "win.outline-settings" } });
            var osec = new GLib.Menu ();
            osec.append_submenu (_("Outline"), outline);
            data.append_section (null, osec);
            var review = new GLib.Menu ();
            review.append_section (null, section ({ { _("Protect Sheet…"), "win.protect-sheet" }, { _("Protect Workbook…"), "win.protect-book" }, { _("Allow Edit Ranges…"), "win.edit-ranges" }, { _("Encrypt with Password…"), "win.encrypt" } }));
            review.append_section (null, section ({ { _("Lock Cell"), "win.toggle-locked" }, { _("Hide Formula"), "win.toggle-hidden-formula" } }));
            review.append_section (null, section ({ { _("New Comment"), "win.comment-new" }, { _("Show Comments"), "win.comments-panel" }, { _("Delete Comment"), "win.comment-delete" } }));
            review.append_section (null, section ({ { _("Track Changes"), "win.track-changes" }, { _("Review Changes…"), "win.review-changes" }, { _("Accept All Changes"), "win.accept-all-changes" }, { _("Reject All Changes"), "win.reject-all-changes" }, { _("History Sheet"), "win.history-sheet" }, { _("Compare and Merge Workbooks…"), "win.compare-merge" } }));
            review.append_section (null, section ({ { _("Edit Together…"), "win.edit-together" } }));
            menu.append_submenu (_("Review"), review);
        }

        public static void accels (Gtk.Application app) {
            app.set_accels_for_action ("win.flash-fill", { "<Control>e" });
            app.set_accels_for_action ("win.paste-special", { "<Control><Alt>v" });
            app.set_accels_for_action ("win.group", { "<Alt><Shift>Right" });
            app.set_accels_for_action ("win.ungroup", { "<Alt><Shift>Left" });
        }
    }
}
