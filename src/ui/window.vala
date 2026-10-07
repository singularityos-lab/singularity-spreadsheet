using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class SpreadsheetWindow : Singularity.Widgets.Window {
        public Document? doc { get; private set; }
        public SheetView? grid { get; private set; }
        public GridExtras? extras;
        private SpreadsheetApp app;
        private Stack content_stack;
        private Box doc_page;
        private Box recent_list;
        private Label recent_empty;
        private Entry name_box;
        private Entry formula_entry;
        private ChipBar sheet_chips;
        private Gee.ArrayList<Sheet> chip_sheets = new Gee.ArrayList<Sheet> ();
        private Label status_label;
        private Button zoom_button;
        private ScrolledWindow grid_scroll;
        private bool formula_sync;
        private Gee.ArrayList<Widget> doc_bubbles = new Gee.ArrayList<Widget> ();
        private Button undo_bubble;
        private Button redo_bubble;
        private Button find_bubble;
        private Button share_bubble;
        private bool close_confirmed;
        private SheetRibbon ribbon;
        private Box doc_body;
        private Button fx_cancel;
        private Button fx_enter;

        public SpreadsheetWindow (SpreadsheetApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1240, 820);
            set_title (_("Spreadsheet"));

            content_stack = new Stack ();
            content_stack.transition_type = StackTransitionType.CROSSFADE;
            content_stack.add_named (build_welcome (), "welcome");
            doc_page = new Box (Orientation.VERTICAL, 0);
            doc_page.add_css_class ("ss-doc");
            apply_view_edge (doc_page);
            content_stack.add_named (doc_page, "document");
            build_bubbles ();
            doc_page.append (ribbon);
            doc_body = new Box (Orientation.VERTICAL, 0);
            doc_body.vexpand = true;
            doc_page.append (doc_body);
            set_content (content_stack);
            install_actions ();
            AnalysisUi.install (this);
            DataModelUi.install (this);
            TableUi.install (this);
            Proofing.install (this);
            var sat = new SimpleAction ("save-template", null);
            sat.activate.connect (() => {
                if (doc != null) save_as_template ();
            });
            add_action (sat);
            CondRules.install (this);
            CommentsUi.install (this);
            ReviewUi.install (this);
            LiveUi.install (this);
            var vh = new SimpleAction ("version-history", null);
            vh.activate.connect (() => {
                if (doc != null) Versions.show (this);
            });
            add_action (vh);
            EditActions.install (this);
            close_request.connect (on_close_request);

            var drop = new DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop.drop.connect ((value, x, y) => {
                var list = (Gdk.FileList) value.get_boxed ();
                foreach (var file in list.get_files ()) {
                    app.open_file (file, this);
                    break;
                }
                return true;
            });
            ((Widget) this).add_controller (drop);
            show_welcome ();
        }

        public bool is_empty () {
            return doc == null || (!doc.modified && doc.path == null && doc.book.sheets.size == 1 && doc.book.sheets[0].cells.size == 0);
        }

        private Widget build_welcome () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.spreadsheet";
            wp.title = _("Spreadsheet");
            wp.subtitle = _("Calculate, organize and chart your data");
            wp.add_action ("x-office-spreadsheet", _("New Spreadsheet"), _("Start from an empty workbook"), () => new_document ());
            wp.add_action ("folder-open", _("Open"), _("Excel, OpenDocument and CSV files"), () => app.choose_file (this));
            var recent_wrap = new Box (Orientation.VERTICAL, 12);
            gallery = new TemplateGallery ();
            gallery.chosen.connect ((t) => load_document (t.build ()));
            recent_wrap.append (gallery);
            var recent_title = new Label (_("Recent"));
            recent_title.add_css_class ("title-2");
            recent_title.halign = Align.START;
            recent_title.margin_top = 12;
            recent_list = new Box (Orientation.VERTICAL, 0);
            recent_list.add_css_class ("ss-recent-list");
            recent_empty = new Label (_("Spreadsheets you open appear here."));
            recent_empty.add_css_class ("dim-label");
            recent_empty.halign = Align.START;
            recent_wrap.append (recent_title);
            recent_wrap.append (recent_list);
            recent_wrap.append (recent_empty);
            wp.set_extra_widget (recent_wrap);
            return wp;
        }

        private static bool is_sheet_file (string uri) {
            string u = uri.down ();
            foreach (string s in FileKind.suffixes ()) {
                if (u.has_suffix ("." + s)) return true;
            }
            return false;
        }

        private void fill_recent () {
            Widget? child;
            while ((child = recent_list.get_first_child ()) != null) recent_list.remove (child);
            var items = new Gee.ArrayList<RecentInfo> ();
            foreach (var info in RecentManager.get_default ().get_items ()) {
                if (is_sheet_file (info.get_uri ()) && info.exists ()) items.add (info);
            }
            items.sort ((a, b) => b.get_modified ().compare (a.get_modified ()));
            int count = 0;
            foreach (var info in items) {
                if (count++ >= 8) break;
                var file = File.new_for_uri (info.get_uri ());
                var row = new Button ();
                row.add_css_class ("flat");
                row.add_css_class ("ss-recent-row");
                var box = new Box (Orientation.HORIZONTAL, 12);
                var icon = new Image.from_icon_name ("x-office-spreadsheet-symbolic");
                icon.pixel_size = 20;
                box.append (icon);
                var texts = new Box (Orientation.VERTICAL, 2);
                texts.hexpand = true;
                var name = new Label (file.get_basename ());
                name.halign = Align.START;
                name.ellipsize = Pango.EllipsizeMode.MIDDLE;
                name.add_css_class ("heading");
                var path = new Label (friendly_folder (file));
                path.halign = Align.START;
                path.ellipsize = Pango.EllipsizeMode.START;
                path.add_css_class ("caption");
                path.add_css_class ("dim-label");
                texts.append (name);
                texts.append (path);
                box.append (texts);
                row.child = box;
                row.clicked.connect (() => app.open_file (file, this));
                recent_list.append (row);
            }
            recent_list.visible = count > 0;
            recent_empty.visible = count == 0;
        }

        private static string friendly_folder (File file) {
            var parent = file.get_parent ();
            if (parent == null) return "";
            string p = parent.get_path () ?? parent.get_uri ();
            string home = Environment.get_home_dir ();
            if (p.has_prefix (home)) p = "~" + p.substring (home.length);
            return p;
        }

        private TemplateGallery? gallery;

        private void show_welcome () {
            content_stack.visible_child_name = "welcome";
            if (gallery != null) gallery.refresh ();
            foreach (var w in doc_bubbles) w.visible = false;
            fill_recent ();
            set_title (_("Spreadsheet"));
            sync_actions ();
        }

        private Widget track (Widget w) {
            doc_bubbles.add (w);
            return w;
        }

        private void anchor_to_bubble (Popover pop, Widget bubble) {
            if (pop.get_parent () == null) pop.set_parent (content_stack);
            Graphene.Rect bounds;
            if (bubble.compute_bounds (content_stack, out bounds)) {
                var rect = Gdk.Rectangle ();
                rect.x = (int) bounds.origin.x;
                rect.y = (int) bounds.origin.y;
                rect.width = (int) bounds.size.width;
                rect.height = (int) bounds.size.height;
                pop.pointing_to = rect;
            }
            pop.position = PositionType.BOTTOM;
        }

        private ContextMenu bubble_menu (Widget bubble) {
            var menu = new ContextMenu (content_stack);
            anchor_to_bubble (menu, bubble);
            return menu;
        }

        public static void popup_menu (ContextMenu menu) {
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void popup_anchored (Popover pop, Widget bubble) {
            anchor_to_bubble (pop, bubble);
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        private void build_bubbles () {
            track (add_bubble_icon ("go-previous-symbolic", _("Close Spreadsheet"), () => close_document ()));
            ribbon = new SheetRibbon (this);
            ribbon.attach (this);
            track (ribbon.tabs);
            track (add_bubble_icon ("document-open-symbolic", _("Open (Ctrl+O)"), () => app.choose_file (this)));
            var save = add_bubble_icon ("document-save-symbolic", _("Save (Ctrl+S)"), () => { });
            save.clicked.connect (() => {
                var menu = bubble_menu (save);
                menu.add_item (_("Save"), "document-save-symbolic", () => run ("save"));
                menu.add_item (_("Save As"), "document-save-as-symbolic", () => run ("save-as"));
                menu.add_item (_("Save to Online Account…"), "document-send-symbolic", () => run ("save-online"));
                menu.add_item (_("Save as Template…"), "x-office-spreadsheet-symbolic", () => run ("save-template"));
                menu.add_item (_("Version History…"), "document-open-recent-symbolic", () => run ("version-history"));
                menu.add_separator ();
                var exp = menu.add_submenu (_("Export"), "document-send-symbolic");
                exp.add_item (_("Excel Workbook (.xlsx)"), null, () => run ("export-xlsx"));
                exp.add_item (_("OpenDocument (.ods)"), null, () => run ("export-ods"));
                exp.add_item (_("CSV"), null, () => run ("export-csv"));
                exp.add_item (_("TSV"), null, () => run ("export-tsv"));
                exp.add_item (_("Web Page (.html)"), null, () => run ("export-html"));
                exp.add_item (_("PDF"), null, () => run ("export-pdf"));
                menu.add_item (_("Page Setup…"), "document-properties-symbolic", () => run ("page-setup"));
                menu.add_item (_("Print…"), "document-print-symbolic", () => run ("print"));
                if (doc != null && doc.path != null) menu.add_item (_("Share…"), "singularity-share-symbolic", () => run ("share"));
                popup_menu (menu);
            });
            track (save);
            share_bubble = add_bubble_icon ("singularity-share-symbolic", _("Share"), () => run ("share"));
            track (share_bubble);
            undo_bubble = add_bubble_icon ("edit-undo-symbolic", _("Undo (Ctrl+Z)"), () => run ("undo"));
            track (undo_bubble);
            redo_bubble = add_bubble_icon ("edit-redo-symbolic", _("Redo (Ctrl+Shift+Z)"), () => run ("redo"));
            track (redo_bubble);
            find_bubble = add_bubble_icon ("edit-find-symbolic", _("Find and Replace (Ctrl+F)"), () => { });
            find_bubble.clicked.connect (() => popup_anchored (new FindPopover (this), find_bubble));
            track (find_bubble);
        }

        private Paned? split_pane;
        private SheetView? primary_grid;

        private void track_focus (SheetView view) {
            var fc = new EventControllerFocus ();
            fc.enter.connect (() => {
                if (grid == view || doc == null) return;
                if (grid != null && grid.is_editing ()) grid.commit_edit (0, 0);
                grid = view;
                on_selection ();
                update_zoom_label ();
            });
            view.add_controller (fc);
        }

        public void toggle_split () {
            if (split_pane != null) {
                if (primary_grid != null) grid = primary_grid;
                var holder = split_pane.get_parent () as Box;
                var before = split_pane.get_prev_sibling ();
                split_pane.start_child = null;
                split_pane.end_child = null;
                if (holder != null) {
                    holder.remove (split_pane);
                    holder.insert_child_after (grid_scroll, before);
                }
                split_pane = null;
                return;
            }
            var parent = grid_scroll.get_parent () as Box;
            if (parent == null) return;
            var prev = grid_scroll.get_prev_sibling ();
            parent.remove (grid_scroll);
            var view = new SheetView (doc);
            view.hexpand = true;
            view.vexpand = true;
            view.show_sheet (grid.sheet);
            var sc = new ScrolledWindow ();
            sc.child = view;
            sc.hexpand = true;
            sc.vexpand = true;
            sc.add_css_class ("ss-grid-scroll");
            EditActions.attach (this, view);
            view.selection_changed.connect (on_selection);
            view.editing_changed.connect (on_grid_editing);
            view.context_menu.connect (show_cell_menu);
            view.filter_clicked.connect (show_filter);
            view.validation_clicked.connect (show_validation_list);
            view.chart_activated.connect ((ch) => Dialogs.chart (this, ch));
            view.link_activated.connect ((link) => Links.follow (this, link));
            view.chart_menu.connect (show_chart_menu);
            view.zoom_changed.connect (update_zoom_label);
            track_focus (view);
            view.select_cell (grid.cur_row, grid.cur_col, false);
            split_pane = new Paned (Orientation.VERTICAL);
            split_pane.start_child = grid_scroll;
            split_pane.end_child = sc;
            split_pane.vexpand = true;
            split_pane.resize_start_child = true;
            split_pane.resize_end_child = true;
            parent.insert_child_after (split_pane, prev);
            int half = int.max (grid.get_height () / 2, 120);
            split_pane.position = half;
        }

        public void new_document () {
            load_document (new Document ());
        }

        public void load_document (Document d) {
            if (doc != null) {
                doc.changed.disconnect (on_doc_changed);
                doc.sheets_changed.disconnect (rebuild_tabs);
                doc.restored.disconnect (on_restored);
            }
            doc = d;
            doc.changed.connect (on_doc_changed);
            doc.sheets_changed.connect (rebuild_tabs);
            doc.restored.connect (on_restored);
            doc.array_locked.connect (() => {
                var dlg = new ConfirmDialog.message ((Gtk.Application) application, _("Array Formula"), "dialog-information", _("You can't change part of an array. Select the whole array to edit or clear it."));
                dlg.transient_for = this;
                dlg.present ();
            });
            Widget? child;
            while ((child = doc_body.get_first_child ()) != null) doc_body.remove (child);
            doc_body.append (build_formula_bar ());
            grid = new SheetView (doc);
            grid.hexpand = true;
            grid.vexpand = true;
            grid_scroll = new ScrolledWindow ();
            grid_scroll.child = grid;
            grid_scroll.hexpand = true;
            grid_scroll.vexpand = true;
            grid_scroll.add_css_class ("ss-grid-scroll");
            doc_body.append (CommentsUi.wrap (this, AnalysisUi.wrap_grid (this, grid_scroll)));
            doc_body.append (build_bottom_bar ());
            grid.selection_changed.connect (on_selection);
            grid.editing_changed.connect (on_grid_editing);
            grid.context_menu.connect (show_cell_menu);
            grid.filter_clicked.connect (show_filter);
            grid.validation_clicked.connect (show_validation_list);
            grid.chart_activated.connect ((ch) => Dialogs.chart (this, ch));
            grid.link_activated.connect ((link) => Links.follow (this, link));
            grid.chart_menu.connect (show_chart_menu);
            grid.zoom_changed.connect (update_zoom_label);
            primary_grid = grid;
            track_focus (grid);
            extras = new GridExtras (this, grid);
            EditActions.attach (this, grid);
            ObjectsUI.attach (this);
            split_pane = null;
            content_stack.visible_child_name = "document";
            foreach (var w in doc_bubbles) w.visible = true;
            rebuild_tabs ();
            on_selection ();
            update_title ();
            update_zoom_label ();
            sync_actions ();
            grid.grab_focus ();
        }

        private void on_doc_changed () {
            update_title ();
            on_selection ();
            rebuild_tabs_state ();
        }

        private void on_restored (Sheet? sheet, Area? sel) {
            if (sheet != null && doc.book.sheets.contains (sheet) && sheet != grid.sheet) {
                grid.show_sheet (sheet);
                rebuild_tabs ();
            }
            if (!doc.book.sheets.contains (grid.sheet)) {
                grid.show_sheet (doc.book.sheets[0]);
                rebuild_tabs ();
            }
            if (sel != null && sheet == grid.sheet) grid.select_area (sel);
            grid.refresh ();
        }

        private void update_title () {
            if (doc == null) return;
            string name = doc.path != null ? Path.get_basename (doc.path) : _("Untitled Spreadsheet");
            set_title ((doc.modified ? "* " : "") + name);
            undo_bubble.sensitive = doc.can_undo;
            redo_bubble.sensitive = doc.can_redo;
            undo_bubble.tooltip_text = doc.can_undo ? _("Undo %s").printf (doc.undo_label) : _("Undo (Ctrl+Z)");
            redo_bubble.tooltip_text = doc.can_redo ? _("Redo %s").printf (doc.redo_label) : _("Redo (Ctrl+Shift+Z)");
            sync_share ();
        }

        private Button bar_button (string icon, string tip) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("flat");
            b.add_css_class ("ss-bar-button");
            b.valign = Align.CENTER;
            b.focus_on_click = false;
            b.tooltip_text = tip;
            return b;
        }

        private Widget build_formula_bar () {
            var bar = new Box (Orientation.HORIZONTAL, 2);
            bar.add_css_class ("ss-formula-bar");
            var name_wrap = new Box (Orientation.HORIZONTAL, 0);
            name_wrap.add_css_class ("ss-name-wrap");
            name_wrap.valign = Align.CENTER;
            name_box = new Entry ();
            name_box.add_css_class ("ss-name-box");
            name_box.width_chars = 9;
            name_box.max_width_chars = 9;
            name_box.tooltip_text = _("Go to a cell, a range or a name. Type a new name to name the selection.");
            name_box.activate.connect (on_name_box);
            name_wrap.append (name_box);
            var names = bar_button ("pan-down-symbolic", _("Named Ranges"));
            names.add_css_class ("ss-name-list");
            names.clicked.connect (() => show_names_menu (names));
            name_wrap.append (names);
            bar.append (name_wrap);
            var sep = new Separator (Orientation.VERTICAL);
            sep.add_css_class ("ss-formula-sep");
            bar.append (sep);
            fx_cancel = bar_button ("window-close-symbolic", _("Cancel (Esc)"));
            fx_cancel.clicked.connect (() => {
                grid.cancel_edit ();
                on_selection ();
                grid.grab_focus ();
            });
            bar.append (fx_cancel);
            fx_enter = bar_button ("object-select-symbolic", _("Enter"));
            fx_enter.clicked.connect (() => {
                if (grid.is_editing ()) grid.commit_edit (0, 0);
                grid.grab_focus ();
            });
            bar.append (fx_enter);
            var fx = bar_button ("sheet-function-symbolic", _("Insert Function (Shift+F3)"));
            fx.clicked.connect (() => show_function_picker (fx));
            bar.append (fx);
            formula_entry = new Entry ();
            formula_entry.hexpand = true;
            formula_entry.valign = Align.CENTER;
            formula_entry.add_css_class ("ss-formula-entry");
            formula_entry.input_hints = InputHints.NO_SPELLCHECK | InputHints.NO_EMOJI;
            formula_entry.changed.connect (() => {
                formula_entry.attributes = SheetView.formula_attrs (formula_entry.text);
                if (formula_sync || grid == null) return;
                if (!formula_entry.has_focus && !formula_entry.get_delegate ().has_focus) return;
                formula_sync = true;
                grid.set_edit_text (formula_entry.text);
                formula_entry.grab_focus_without_selecting ();
                formula_entry.set_position (-1);
                formula_sync = false;
                sync_edit_buttons ();
            });
            formula_entry.activate.connect (() => {
                if (grid.is_editing ()) grid.commit_edit (1, 0);
                grid.grab_focus ();
            });
            var fkeys = new EventControllerKey ();
            fkeys.key_pressed.connect ((keyval, code, state) => {
                if (keyval == Gdk.Key.Escape) {
                    grid.cancel_edit ();
                    on_selection ();
                    grid.grab_focus ();
                    return true;
                }
                if (keyval == Gdk.Key.Tab) {
                    if (grid.is_editing ()) grid.commit_edit (0, 1);
                    grid.grab_focus ();
                    return true;
                }
                return false;
            });
            formula_entry.add_controller (fkeys);
            bar.append (formula_entry);
            sync_edit_buttons ();
            return bar;
        }

        private void sync_edit_buttons () {
            bool editing = grid != null && grid.is_editing ();
            if (fx_cancel != null) fx_cancel.sensitive = editing;
            if (fx_enter != null) fx_enter.sensitive = editing;
        }

        private void show_names_menu (Widget anchor) {
            if (doc == null) return;
            var menu = new ContextMenu (anchor);
            var keys = new Gee.TreeSet<string> ((a, b) => a.collate (b));
            foreach (var e in doc.book.names.entries) keys.add (e.key);
            foreach (string k in keys) {
                string key = k;
                menu.add_item (key, null, () => {
                    name_box.text = key;
                    on_name_box ();
                });
            }
            if (keys.size > 0) menu.add_separator ();
            menu.add_item (_("Name Manager…"), "sheet-names-symbolic", () => run ("names"));
            popup_menu (menu);
        }

        public void pick_function (string category, Widget? anchor) {
            if (grid == null) return;
            show_function_picker (anchor != null && anchor.get_mapped () ? anchor : formula_entry, category);
        }

        private void on_grid_editing (string text, bool active) {
            sync_edit_buttons ();
            if (formula_sync) return;
            if (!active) {
                on_selection ();
                return;
            }
            formula_sync = true;
            formula_entry.text = text;
            formula_sync = false;
        }

        private void on_name_box () {
            string t = name_box.text.strip ();
            if (t == "" || grid == null) return;
            Sheet target = grid.sheet;
            string r = t;
            int bang = t.last_index_of ("!");
            if (bang > 0) {
                string sn = t.substring (0, bang);
                if (sn.has_prefix ("'")) sn = sn.substring (1, sn.length - 2);
                var s = doc.book.find_sheet (sn);
                if (s != null) target = s;
                r = t.substring (bang + 1);
            }
            var area = Area.parse (r.replace ("$", ""), target);
            if (area == null) {
                foreach (var e in doc.book.names.entries) {
                    if (e.key.casefold () != t.casefold ()) continue;
                    try {
                        var ev = new Evaluator (doc.book, grid.sheet, 0, 0);
                        var v = ev.eval (Formula.parse ("=" + e.value, doc.book, grid.sheet));
                        if (v.kind == ValueKind.RANGE) area = v.area;
                    } catch (FormulaError err) {
                    }
                }
            }
            if (area == null) {
                bool valid = t.length > 0 && (t[0].isalpha () || t[0] == '_') && !t.contains (" ");
                if (valid) {
                    var sel = grid.selection;
                    doc.set_name (t, Address.quote_sheet (grid.sheet.name) + "!" + Address.cell (sel.r1, sel.c1, true, true) + (sel.is_single () ? "" : ":" + Address.cell (sel.r2, sel.c2, true, true)));
                    grid.grab_focus ();
                } else {
                    name_box.add_css_class ("error");
                    Timeout.add (900, () => {
                        name_box.remove_css_class ("error");
                        return Source.REMOVE;
                    });
                }
                return;
            }
            var sheet = area.sheet ?? target;
            if (sheet != grid.sheet) {
                grid.show_sheet (sheet);
                rebuild_tabs ();
            }
            grid.select_area (new Area (sheet, area.r1, area.c1, area.r2, area.c2));
            grid.grab_focus ();
        }

        private Widget build_bottom_bar () {
            sheet_chips = new ChipBar ();
            sheet_chips.hexpand = true;
            sheet_chips.reorderable = true;
            sheet_chips.max_label_chars = 24;
            sheet_chips.close_tooltip = _("Delete Sheet");
            sheet_chips.chip_activated.connect ((id) => {
                var sheet = sheet_for_chip (id);
                if (sheet != null && grid.sheet != sheet) {
                    grid.show_sheet (sheet);
                    rebuild_tabs_state ();
                    on_selection ();
                }
                grid.grab_focus ();
            });
            sheet_chips.chip_closed.connect ((id) => {
                var sheet = sheet_for_chip (id);
                if (sheet != null && doc.book.sheets.size > 1) delete_sheet (sheet);
            });
            sheet_chips.chips_reordered.connect (on_chips_reordered);
            sheet_chips.chip_context_requested.connect ((id) => {
                var sheet = sheet_for_chip (id);
                var chip = sheet_chips.get_chip_widget (id);
                if (sheet != null && chip != null) show_tab_menu (sheet, chip);
            });
            sheet_chips.chip_double_activated.connect ((id) => sheet_chips.begin_rename (id));
            sheet_chips.chip_renamed.connect (on_chip_renamed);
            sheet_chips.chip_rename_cancelled.connect ((id) => {
                if (tabs_have_focus ()) grid.grab_focus ();
            });
            var add = new Button.from_icon_name ("list-add-symbolic");
            add.add_css_class ("flat");
            add.add_css_class ("circular");
            add.valign = Align.CENTER;
            add.margin_start = 8;
            add.tooltip_text = _("New Sheet");
            add.clicked.connect (() => {
                var s = doc.add_sheet ();
                grid.show_sheet (s);
                rebuild_tabs ();
            });
            sheet_chips.prepend (add);
            status_label = new Label ("");
            status_label.add_css_class ("ss-status");
            status_label.add_css_class ("dim-label");
            status_label.selectable = true;
            sheet_chips.append (status_label);
            zoom_button = new Button.with_label ("100%");
            zoom_button.add_css_class ("flat");
            zoom_button.add_css_class ("ss-zoom");
            zoom_button.valign = Align.CENTER;
            zoom_button.margin_end = 8;
            zoom_button.tooltip_text = _("Zoom");
            zoom_button.clicked.connect (() => {
                var menu = new ContextMenu (zoom_button);
                int[] levels = { 50, 75, 90, 100, 125, 150, 200 };
                foreach (int l in levels) {
                    int lv = l;
                    menu.add_item ("%d%%".printf (lv), null, () => grid.zoom_to (lv / 100.0));
                }
                popup_menu (menu);
            });
            sheet_chips.append (zoom_button);
            return sheet_chips;
        }

        private void update_zoom_label () {
            if (grid != null) zoom_button.label = "%d%%".printf ((int) Math.round (grid.zoom * 100));
            ribbon.sync_zoom ();
        }

        private Sheet? sheet_for_chip (string id) {
            int i = int.parse (id);
            if (i < 0 || i >= chip_sheets.size) return null;
            var sheet = chip_sheets[i];
            return doc.book.sheets.contains (sheet) ? sheet : null;
        }

        private string? chip_for_sheet (Sheet sheet) {
            int i = chip_sheets.index_of (sheet);
            return i < 0 ? null : i.to_string ();
        }

        private void on_chips_reordered (string[] ids) {
            var order = new Gee.ArrayList<Sheet> ();
            foreach (string id in ids) {
                var s = sheet_for_chip (id);
                if (s != null) order.add (s);
            }
            if (order.size != doc.book.sheets.size) {
                rebuild_tabs ();
                return;
            }
            foreach (var s in order) {
                var rest_old = new Gee.ArrayList<Sheet> ();
                rest_old.add_all (doc.book.sheets);
                rest_old.remove (s);
                var rest_new = new Gee.ArrayList<Sheet> ();
                rest_new.add_all (order);
                rest_new.remove (s);
                bool same = true;
                for (int i = 0; i < rest_old.size; i++) {
                    if (rest_old[i] != rest_new[i]) {
                        same = false;
                        break;
                    }
                }
                if (same) {
                    if (order.index_of (s) != doc.book.sheets.index_of (s)) doc.move_sheet (s, order.index_of (s));
                    return;
                }
            }
            rebuild_tabs ();
        }

        private void rebuild_tabs () {
            if (doc == null) return;
            for (int i = 0; i < chip_sheets.size; i++) sheet_chips.remove_chip (i.to_string ());
            chip_sheets.clear ();
            foreach (var vs in doc.book.sheets) if (vs.visibility == 0 || vs == grid.sheet) chip_sheets.add (vs);
            bool single = chip_sheets.size == 1;
            for (int i = 0; i < chip_sheets.size; i++) {
                var sheet = chip_sheets[i];
                string id = i.to_string ();
                sheet_chips.add_chip (id, sheet.name);
                sheet_chips.set_chip_closable (id, !single);
                var color = Gdk.RGBA ();
                if (sheet.tab_color != "" && color.parse (sheet.tab_color)) sheet_chips.set_chip_color (id, color);
                if (doc.grouped (sheet)) {
                    var link = new Image.from_icon_name ("insert-link-symbolic");
                    link.tooltip_text = _("Grouped: edits apply to every grouped sheet");
                    sheet_chips.set_chip_prefix (id, link);
                }
            }
            rebuild_tabs_state ();
        }

        private void save_as_template () {
            var dlg = Dialogs.make (this, _("Save as Template"), 440, 360);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Template"), _("Templates appear on the start screen under Your Templates."));
            var name = new EntryRow (_("Name"));
            string base_name = doc.path != null ? Path.get_basename (doc.path) : _("My Template");
            if (base_name.last_index_of (".") > 0) base_name = base_name.substring (0, base_name.last_index_of ("."));
            name.text = base_name;
            g.add_row (name);
            box.append (g);
            Dialogs.Apply save_tpl = () => {
                string n = name.text.strip ().replace ("/", "-");
                if (n == "") return;
                DirUtils.create_with_parents (SheetTemplate.user_dir (), 0700);
                string target = Path.build_filename (SheetTemplate.user_dir (), n + ".xltx");
                string? keep_path = doc.path;
                bool keep_modified = doc.modified;
                try {
                    doc.save_to (target, grid.sheet);
                } catch (Error e) {
                    show_error (_("Could Not Save"), e.message);
                }
                doc.path = keep_path;
                doc.modified = keep_modified;
                update_title ();
            };
            name.entry_activated.connect (() => {
                save_tpl ();
                dlg.close ();
            });
            Dialogs.footer (dlg, _("Save"), () => save_tpl ());
            dlg.open_dialog ();
        }

        public void hide_sheet (Sheet sheet) {
            if (!doc.set_sheet_visibility (sheet, 1)) return;
            if (grid.sheet == sheet) {
                foreach (var s in doc.book.sheets) {
                    if (s.visibility == 0) {
                        grid.show_sheet (s);
                        break;
                    }
                }
            }
            rebuild_tabs ();
        }

        public void unhide_sheets () {
            var menu = new ContextMenu (sheet_chips);
            foreach (var s in doc.book.sheets) {
                if (s.visibility != 1) continue;
                var target = s;
                menu.add_item (s.name, "view-reveal-symbolic", () => {
                    doc.set_sheet_visibility (target, 0);
                    grid.show_sheet (target);
                    rebuild_tabs ();
                });
            }
            popup_menu (menu);
        }

        public void go_to (Sheet s, int r, int c) {
            if (grid == null || !doc.book.sheets.contains (s)) return;
            if (grid.sheet != s) {
                grid.show_sheet (s);
                rebuild_tabs_state ();
            }
            grid.select_cell (r, c, false);
            grid.ensure_visible (r, c);
            grid.grab_focus ();
        }

        public void sheets_updated () {
            rebuild_tabs ();
            if (grid != null) grid.refresh ();
        }

        private void rebuild_tabs_state () {
            if (sheet_chips == null || grid == null) return;
            sheet_chips.set_active (chip_for_sheet (grid.sheet));
        }

        private void show_tab_menu (Sheet sheet, Widget tab) {
            var menu = new ContextMenu (tab);
            menu.add_item (_("Rename"), "document-edit-symbolic", () => begin_rename_sheet (sheet));
            menu.add_item (_("Duplicate"), "edit-copy-symbolic", () => {
                var s = doc.duplicate_sheet (sheet);
                grid.show_sheet (s);
                rebuild_tabs ();
            });
            menu.add_item (_("Insert Sheet"), "list-add-symbolic", () => {
                var s = doc.add_sheet (doc.book.sheets.index_of (sheet) + 1);
                grid.show_sheet (s);
                rebuild_tabs ();
            });
            menu.add_item (_("Hide"), "view-conceal-symbolic", () => hide_sheet (sheet));
            if (doc.book.sheets.size > 1) {
                if (doc.group.contains (sheet)) menu.add_item (_("Ungroup Sheets"), "edit-clear-symbolic", () => {
                    doc.group.clear ();
                    rebuild_tabs ();
                });
                else menu.add_item (_("Group with Current Sheet"), "edit-select-all-symbolic", () => {
                    if (!doc.group.contains (grid.sheet)) doc.group.add (grid.sheet);
                    doc.group.add (sheet);
                    rebuild_tabs ();
                });
                menu.add_item (_("Group All Sheets"), "edit-select-all-symbolic", () => {
                    doc.group.clear ();
                    foreach (var gs in doc.book.sheets) if (gs.visibility == 0) doc.group.add (gs);
                    rebuild_tabs ();
                });
            }
            bool any_hidden = false;
            foreach (var hs in doc.book.sheets) if (hs.visibility == 1) any_hidden = true;
            if (any_hidden) menu.add_item (_("Unhide…"), "view-reveal-symbolic", () => unhide_sheets ());
            var colors = menu.add_submenu (_("Tab Color"), "sheet-fill-symbolic");
            string[] names = { _("None"), _("Blue"), _("Green"), _("Yellow"), _("Orange"), _("Red"), _("Purple") };
            string[] values = { "", "#2a78d6", "#1baf7a", "#eda100", "#eb6834", "#e34948", "#4a3aa7" };
            for (int i = 0; i < names.length; i++) {
                string v = values[i];
                colors.add_item (names[i], null, () => doc.set_tab_color (sheet, v));
            }
            menu.add_separator ();
            int idx = doc.book.sheets.index_of (sheet);
            if (idx > 0) menu.add_item (_("Move Left"), "go-previous-symbolic", () => doc.move_sheet (sheet, idx - 1));
            if (idx < doc.book.sheets.size - 1) menu.add_item (_("Move Right"), "go-next-symbolic", () => doc.move_sheet (sheet, idx + 1));
            if (doc.book.sheets.size > 1) {
                menu.add_separator ();
                menu.add_item (_("Delete"), "user-trash-symbolic", () => delete_sheet (sheet), "destructive");
            }
            popup_menu (menu);
        }

        private void delete_sheet (Sheet sheet) {
            var dlg = new ConfirmDialog (app, _("Delete Sheet?"), "user-trash-symbolic",
                _("\"%s\" and everything on it will be deleted. You can undo this.").printf (sheet.name),
                _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                int i = doc.book.sheets.index_of (sheet);
                doc.remove_sheet (sheet);
                if (!doc.book.sheets.contains (grid.sheet)) grid.show_sheet (doc.book.sheets[int.max (0, i - 1)]);
                rebuild_tabs ();
                grid.grab_focus ();
            });
            dlg.present ();
        }

        public delegate void ActionHandler ();

        public void begin_rename_sheet (Sheet sheet) {
            string? id = chip_for_sheet (sheet);
            if (id != null) sheet_chips.begin_rename (id);
        }

        private void on_chip_renamed (string id, string name) {
            var sheet = sheet_for_chip (id);
            if (sheet == null) return;
            bool refocus = tabs_have_focus ();
            string n = name.strip ();
            if (valid_sheet_name (sheet, n)) doc.rename_sheet (sheet, n);
            if (refocus) grid.grab_focus ();
        }

        private bool tabs_have_focus () {
            var focus = get_focus ();
            return grid != null && (focus == null || focus.is_ancestor (sheet_chips));
        }

        private bool valid_sheet_name (Sheet sheet, string n) {
            var other = doc.book.find_sheet (n);
            if (n == "" || n.length > 31 || (other != null && other != sheet)) return false;
            foreach (string ch in new string[] { "[", "]", "*", "?", "/", "\\", ":" }) if (n.contains (ch)) return false;
            return true;
        }

        private void on_selection () {
            if (grid == null || doc == null) return;
            var sel = grid.selection;
            if (!formula_sync && !grid.is_editing ()) {
                formula_sync = true;
                formula_entry.text = grid.edit_text_for (grid.cur_row, grid.cur_col);
                formula_sync = false;
            }
            string name = "";
            string mine = Address.quote_sheet (grid.sheet.name) + "!" + Address.cell (sel.r1, sel.c1, true, true) + (sel.is_single () ? "" : ":" + Address.cell (sel.r2, sel.c2, true, true));
            foreach (var e in doc.book.names.entries) if (e.value == mine) name = e.key;
            if (!name_box.has_focus && !name_box.get_delegate ().has_focus) {
                if (name != "") name_box.text = name;
                else if (sel.is_single () || whole_merge (sel)) name_box.text = Address.cell (grid.cur_row, grid.cur_col);
                else name_box.text = sel.to_string ();
            }
            string stats = selection_stats (sel);
            if (doc.book.circular.size > 0) stats = (stats != "" ? stats + "    " : "") + _("Circular References: %s").printf (doc.book.circular[0]);
            else if (doc.book.manual_calc && doc.book.needs_recalc) stats = (stats != "" ? stats + "    " : "") + _("Calculate");
            if (doc.grouped (grid.sheet)) stats = (stats != "" ? stats + "    " : "") + _("Group");
            status_label.label = stats;
            sync_edit_buttons ();
            ribbon.sync ();
            var cur_v = grid.sheet.value_at (grid.cur_row, grid.cur_col);
            grid.update_property (Gtk.AccessibleProperty.LABEL, _("Cell %s").printf (Address.cell (grid.cur_row, grid.cur_col)), Gtk.AccessibleProperty.DESCRIPTION, cur_v.is_empty () ? _("Empty") : cur_v.display (), -1);
        }

        private bool whole_merge (Area sel) {
            var m = grid.sheet.merge_at (sel.r1, sel.c1);
            return m != null && m.r1 == sel.r1 && m.c1 == sel.c1 && m.r2 == sel.r2 && m.c2 == sel.c2;
        }

        private string selection_stats (Area sel) {
            if (sel.is_single () || whole_merge (sel)) return "";
            var s = grid.sheet;
            double sum = 0;
            int nums = 0, count = 0;
            double mn = double.INFINITY, mx = -double.INFINITY;
            int visited = 0;
            s.foreach_in (Document.clamp_area (s, sel), (r, c, cell) => {
                if (visited++ > 500000) return;
                if (s.hidden_rows.contains (r)) return;
                var v = doc.book.cell_value (s, cell);
                if (v.kind == ValueKind.EMPTY) return;
                count++;
                if (v.kind == ValueKind.NUMBER) {
                    nums++;
                    sum += v.number;
                    mn = double.min (mn, v.number);
                    mx = double.max (mx, v.number);
                }
            });
            if (count == 0) return "";
            if (nums == 0) return _("Count: %d").printf (count);
            string color;
            string fmt = s.style_at (sel.r1, sel.c1).number_format;
            if (NumberFormat.is_date_format (fmt) || fmt == "@") fmt = "General";
            return _("Sum: %s    Average: %s    Min: %s    Max: %s    Count: %d").printf (
                NumberFormat.format (sum, fmt, out color), NumberFormat.format (sum / nums, fmt, out color),
                NumberFormat.format (mn, fmt, out color), NumberFormat.format (mx, fmt, out color), count);
        }

        private void show_function_picker (Widget anchor, string category = "") {
            var pop = new FunctionPicker (category);
            pop.set_parent (anchor);
            pop.chosen.connect ((name) => {
                pop.popdown ();
                string current = grid.is_editing () ? formula_entry.text : "";
                if (current == "" || !current.has_prefix ("=")) current = "=";
                grid.set_edit_text (current + name + "(");
                grid.grab_editor ();
            });
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        private Gdk.Rectangle point_rect (double x, double y) {
            var rect = Gdk.Rectangle ();
            rect.x = (int) x;
            rect.y = (int) y;
            rect.width = 1;
            rect.height = 1;
            return rect;
        }

        private void show_cell_menu (double x, double y) {
            var menu = new ContextMenu (grid);
            menu.pointing_to = point_rect (x, y);
            var sel = grid.selection;
            bool whole_rows = sel.c1 == 0 && sel.c2 == MAX_COLS - 1;
            bool whole_cols = sel.r1 == 0 && sel.r2 == MAX_ROWS - 1;
            menu.add_item (_("Cut"), "edit-cut-symbolic", () => run ("cut"));
            menu.add_item (_("Copy"), "edit-copy-symbolic", () => run ("copy"));
            menu.add_item (_("Paste"), "edit-paste-symbolic", () => run ("paste"));
            var special = menu.add_submenu (_("Paste Special"), "edit-paste-symbolic");
            special.add_item (_("Values Only"), null, () => run ("paste-values"));
            special.add_item (_("Formats Only"), null, () => run ("paste-formats"));
            special.add_item (_("Formulas Only"), null, () => run ("paste-formulas"));
            special.add_item (_("Transpose"), null, () => run ("paste-transpose"));
            menu.add_separator ();
            if (whole_rows) {
                menu.add_item (_("Insert Rows Above"), "list-add-symbolic", () => run ("insert-rows-above"));
                menu.add_item (_("Delete Rows"), "list-remove-symbolic", () => run ("delete-rows"));
                menu.add_item (_("Row Height"), null, () => run ("row-height"));
                menu.add_item (_("Hide Rows"), null, () => run ("hide-rows"));
                menu.add_item (_("Unhide Rows"), null, () => run ("unhide-rows"));
            } else if (whole_cols) {
                menu.add_item (_("Insert Columns Left"), "list-add-symbolic", () => run ("insert-cols-left"));
                menu.add_item (_("Delete Columns"), "list-remove-symbolic", () => run ("delete-cols"));
                menu.add_item (_("Column Width"), null, () => run ("col-width"));
                menu.add_item (_("Hide Columns"), null, () => run ("hide-cols"));
                menu.add_item (_("Unhide Columns"), null, () => run ("unhide-cols"));
            } else {
                var ins = menu.add_submenu (_("Insert"), "list-add-symbolic");
                ins.add_item (_("Rows Above"), null, () => run ("insert-rows-above"));
                ins.add_item (_("Rows Below"), null, () => run ("insert-rows-below"));
                ins.add_item (_("Columns Left"), null, () => run ("insert-cols-left"));
                ins.add_item (_("Columns Right"), null, () => run ("insert-cols-right"));
                var del = menu.add_submenu (_("Delete"), "list-remove-symbolic");
                del.add_item (_("Rows"), null, () => run ("delete-rows"));
                del.add_item (_("Columns"), null, () => run ("delete-cols"));
            }
            menu.add_item (_("Clear Contents"), "edit-clear-symbolic", () => run ("clear-contents"));
            menu.add_separator ();
            var sort = menu.add_submenu (_("Sort"), "view-sort-ascending-symbolic");
            sort.add_item (_("Sort A to Z"), "view-sort-ascending-symbolic", () => run ("sort-asc"));
            sort.add_item (_("Sort Z to A"), "view-sort-descending-symbolic", () => run ("sort-desc"));
            sort.add_item (_("Custom Sort"), null, () => run ("sort-custom"));
            menu.add_item (grid.sheet.filter != null ? _("Remove Filter") : _("Filter"), "sheet-filter-symbolic", () => run ("filter"));
            menu.add_separator ();
            var cell = grid.sheet.get_cell (grid.cur_row, grid.cur_col);
            menu.add_item (cell != null && cell.note != "" ? _("Edit Note") : _("Insert Note"), "sheet-note-symbolic", () => run ("note"));
            menu.add_item (grid.sheet.comments.has (grid.cur_row, grid.cur_col) ? _("Show Comment") : _("New Comment"), "sheet-comment-symbolic", () => run ("comment-new"));
            string cur_link = Links.target (doc.book, grid.sheet, grid.cur_row, grid.cur_col);
            if (cur_link != "") menu.add_item (_("Open Link"), "web-browser-symbolic", () => run ("open-link"));
            menu.add_item (cell != null && cell.link != "" ? _("Edit Link") : _("Insert Link"), "insert-link-symbolic", () => run ("insert-link"));
            menu.add_item (_("Format Cells"), "sheet-format-symbolic", () => run ("format-cells"));
            if (!sel.is_single ()) {
                var m = grid.sheet.merge_at (sel.r1, sel.c1);
                if (m != null) menu.add_item (_("Unmerge Cells"), "sheet-merge-symbolic", () => run ("unmerge"));
                else menu.add_item (_("Merge Cells"), "sheet-merge-symbolic", () => run ("merge-center"));
            }
            popup_menu (menu);
        }

        private void show_chart_menu (Chart ch, double x, double y) {
            var menu = new ContextMenu (grid);
            menu.pointing_to = point_rect (x, y);
            menu.add_item (_("Edit Chart"), "document-edit-symbolic", () => Dialogs.chart (this, ch));
            menu.add_item (_("Copy as Linked Chart"), "insert-link-symbolic", () => {
                if (doc.path == null) {
                    add_toast (new Toast (_("Save the spreadsheet first, so the chart can stay linked to it")));
                    return;
                }
                ChartLink.copy (grid, doc, grid.sheet, ch);
                add_toast (new Toast (_("Chart copied. Paste it in Write or Slides to keep it linked")));
            });
            menu.add_item (_("Duplicate"), "edit-copy-symbolic", () => {
                var copy = ch.copy ();
                copy.x = ch.x + 24;
                copy.y = ch.y + 24;
                doc.add_chart (grid.sheet, copy);
            });
            menu.add_separator ();
            menu.add_item (_("Delete Chart"), "user-trash-symbolic", () => doc.remove_chart (grid.sheet, ch), "destructive");
            popup_menu (menu);
        }

        private void show_filter (int col, double x, double y) {
            var pop = new AdvancedFilterPopover (this, col, point_rect (x, y));
            pop.set_parent (grid);
            pop.pointing_to = point_rect (x, y);
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        private void show_validation_list (int r, int c, double x, double y) {
            var items = doc.validation_items (grid.sheet, r, c);
            if (items.size == 0) return;
            var menu = new ContextMenu (grid);
            menu.pointing_to = point_rect (x, y);
            foreach (string item in items) {
                string v = item;
                menu.add_item (v, null, () => doc.set_input (grid.sheet, r, c, v));
            }
            popup_menu (menu);
        }

        public void close_document () {
            if (doc == null) {
                show_welcome ();
                return;
            }
            confirm_discard (() => {
                doc = null;
                grid = null;
                Widget? child;
                while ((child = doc_body.get_first_child ()) != null) doc_body.remove (child);
                show_welcome ();
            });
        }

        private void confirm_discard (owned ActionHandler then) {
            if (doc == null || !doc.modified) {
                then ();
                return;
            }
            var dlg = new ConfirmDialog (app, _("Save Changes?"), "dialog-warning",
                _("Your changes will be lost if you do not save them."),
                _("Discard"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.set_secondary (_("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.CANCEL) return;
                if (r == ConfirmDialog.Response.SECONDARY) {
                    save.begin (false, (obj, res) => {
                        if (save.end (res)) then ();
                    });
                    return;
                }
                then ();
            });
            dlg.present ();
        }

        private bool on_close_request () {
            if (close_confirmed || doc == null || !doc.modified) return false;
            confirm_discard (() => {
                close_confirmed = true;
                close ();
            });
            return true;
        }

        public async bool save (bool save_as) {
            if (doc == null) return false;
            if (grid.is_editing ()) grid.commit_edit (0, 0);
            string? target = save_as ? null : doc.path;
            if (target == null) {
                var dialog = new FileDialog ();
                dialog.title = _("Save Spreadsheet");
                string base_name = doc.path != null ? Path.get_basename (doc.path) : _("Spreadsheet") + ".xlsx";
                if (!FileKind.saveable (base_name)) {
                    int dot = base_name.last_index_of (".");
                    base_name = (dot > 0 ? base_name.substring (0, dot) : base_name) + (doc.book.vba_project != null ? ".xlsm" : ".xlsx");
                }
                dialog.initial_name = base_name;
                var filters = new GLib.ListStore (typeof (FileFilter));
                string[,] kinds = {
                    { _("Excel Workbook (.xlsx)"), "xlsx" },
                    { _("Excel Macro-Enabled Workbook (.xlsm)"), "xlsm" },
                    { _("OpenDocument Spreadsheet (.ods)"), "ods" },
                    { _("Excel Template (.xltx)"), "xltx" },
                    { _("OpenDocument Template (.ots)"), "ots" },
                    { _("Flat OpenDocument Spreadsheet (.fods)"), "fods" },
                    { _("Excel 97-2003 Workbook (.xls)"), "xls" },
                    { _("Excel Binary Workbook (.xlsb)"), "xlsb" }
                };
                for (int k = 0; k < kinds.length[0]; k++) {
                    var ff = new FileFilter ();
                    ff.name = kinds[k, 0];
                    ff.add_suffix (kinds[k, 1]);
                    filters.append (ff);
                }
                dialog.filters = filters;
                try {
                    var file = yield dialog.save (this, null);
                    if (file == null) return false;
                    target = file.get_path ();
                    string low = target.down ();
                    if (!FileKind.saveable (low)) target += ".xlsx";
                } catch (Error e) {
                    return false;
                }
            }
            try {
                var save_kind = FileKind.from_path (target);
                if (save_kind != FileKind.CSV && save_kind != FileKind.TSV) Versions.keep_previous (target);
                doc.save_to (target, grid.sheet);
                RecentManager.get_default ().add_item (File.new_for_path (target).get_uri ());
                update_title ();
                CloudActions.sync_back (this, File.new_for_path (target));
                return true;
            } catch (Error e) {
                show_error (_("Could Not Save"), e.message);
                return false;
            }
        }

        private async void export (string suffix) {
            if (doc == null) return;
            if (grid.is_editing ()) grid.commit_edit (0, 0);
            var dialog = new FileDialog ();
            switch (suffix) {
                case "pdf": dialog.title = _("Export as PDF"); break;
                case "xlsx": dialog.title = _("Export as Excel Workbook"); break;
                case "ods": dialog.title = _("Export as OpenDocument Spreadsheet"); break;
                case "html": dialog.title = _("Export as Web Page"); break;
                case "tsv": dialog.title = _("Export as TSV"); break;
                default: dialog.title = _("Export as CSV"); break;
            }
            string base_name = doc.path != null ? Path.get_basename (doc.path) : _("Spreadsheet");
            int dot = base_name.last_index_of (".");
            if (dot > 0) base_name = base_name.substring (0, dot);
            if ((suffix == "csv" || suffix == "tsv") && doc.book.sheets.size > 1) base_name += " - " + grid.sheet.name;
            dialog.initial_name = base_name + "." + suffix;
            try {
                var file = yield dialog.save (this, null);
                if (file == null) return;
                switch (suffix) {
                    case "pdf": printer ().export_pdf (file.get_path ()); break;
                    case "xlsx": XlsxWriter.save (doc.book, file.get_path ()); break;
                    case "ods": Ods.save (doc.book, file.get_path ()); break;
                    case "html": HtmlExport.save (doc.book, file.get_path ()); break;
                    case "tsv": Csv.save (grid.sheet, file.get_path (), '\t'); break;
                    default: Csv.save (grid.sheet, file.get_path (), ','); break;
                }
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED) && !(e is IOError.CANCELLED)) show_error (_("Could Not Export"), e.message);
            }
        }

        private SheetPrinter printer () {
            var sel = grid.selection;
            var sp = new SheetPrinter (grid.sheet, sel.is_single () ? null : Document.clamp_area (grid.sheet, sel));
            if (doc.path != null) {
                sp.file_name = Path.get_basename (doc.path);
                sp.file_path = Path.get_dirname (doc.path);
            }
            return sp;
        }

        public void show_error (string title, string message) {
            var dlg = new ConfirmDialog.message (app, title, "dialog-error-symbolic", message);
            dlg.transient_for = this;
            dlg.present ();
        }

        private delegate void Act ();

        private static string? text_action (string name) {
            switch (name) {
                case "copy": return "clipboard.copy";
                case "cut": return "clipboard.cut";
                case "paste": return "clipboard.paste";
                case "select-all": return "selection.select-all";
                case "undo": return "text.undo";
                case "redo": return "text.redo";
                default: return null;
            }
        }

        private bool focus_in_text () {
            var f = get_focus ();
            return f != null && (f is Gtk.Text || f is Gtk.TextView);
        }

        private void act (ActionMap g, string name, owned Act handler, bool needs_doc = true) {
            var a = new SimpleAction (name, null);
            if (needs_doc) doc_actions += name;
            string? forward = text_action (name);
            a.activate.connect (() => {
                if (forward != null && focus_in_text ()) {
                    get_focus ().activate_action_variant (forward, null);
                    return;
                }
                if (needs_doc && (doc == null || grid == null)) return;
                if (needs_doc && EditActions.refuse (this, name)) return;
                if (needs_doc && EditActions.multi (this, name, () => handler ())) return;
                handler ();
            });
            g.add_action (a);
        }

        private void toggle (ActionMap g, string name, bool initial, owned Act handler) {
            var a = new SimpleAction.stateful (name, null, new Variant.boolean (initial));
            doc_actions += name;
            a.activate.connect (() => {
                if (doc == null || grid == null) return;
                a.set_state (new Variant.boolean (!a.get_state ().get_boolean ()));
                handler ();
            });
            g.add_action (a);
        }

        private Area sel () {
            return grid.selection;
        }

        public void set_format (string code) {
            doc.edit_style (grid.sheet, sel (), _("Number Format"), (st) => st.number_format = code);
        }

        private void adjust_decimals (int delta) {
            var st = grid.sheet.style_at (grid.cur_row, grid.cur_col);
            string code = st.number_format;
            if (code == "General" || code == "") {
                var v = grid.sheet.value_at (grid.cur_row, grid.cur_col);
                int decs = 0;
                if (v.kind == ValueKind.NUMBER) {
                    string g = Value.format_number_general (v.number);
                    int dot = g.index_of (".");
                    decs = dot >= 0 ? g.length - dot - 1 : 0;
                }
                code = "0" + (decs > 0 ? "." + string.nfill (decs, '0') : "");
            }
            string[] sections = code.split (";");
            for (int i = 0; i < sections.length; i++) {
                string s = sections[i];
                int last0 = s.last_index_of ("0");
                if (last0 < 0) continue;
                int dot = s.index_of (".");
                if (delta > 0) {
                    if (dot >= 0 && dot < last0) s = s.substring (0, last0 + 1) + "0" + s.substring (last0 + 1);
                    else s = s.substring (0, last0 + 1) + ".0" + s.substring (last0 + 1);
                } else if (dot >= 0 && dot < last0) {
                    s = s.substring (0, last0) + s.substring (last0 + 1);
                    if (s.length == dot + 1 || !(s[dot + 1] == '0' || s[dot + 1] == '#')) s = s.substring (0, dot) + s.substring (dot + 1);
                }
                sections[i] = s;
            }
            set_format (string.joinv (";", sections));
        }

        private void insert_now (bool time) {
            double now = DateSerial.now ();
            string code = time ? "h:mm" : LocaleInfo.get ().short_date_format ();
            string color;
            string text = NumberFormat.format (time ? now - Math.floor (now) : Math.floor (now), code, out color);
            if (grid.is_editing ()) grid.set_edit_text (formula_entry.text + text);
            else doc.set_input (grid.sheet, grid.cur_row, grid.cur_col, text);
        }

        private void autosum () {
            var s = grid.sheet;
            var a = sel ();
            int r = grid.cur_row, c = grid.cur_col;
            if (!a.is_single ()) {
                if (a.rows > 1) {
                    int target = a.r2 + 1;
                    doc.begin_area (_("AutoSum"), s, new Area (s, target, a.c1, target, a.c2));
                    for (int col = a.c1; col <= a.c2; col++) s.set_input (target, col, "=SUM(%s:%s)".printf (Address.cell (a.r1, col), Address.cell (a.r2, col)));
                    doc.commit ();
                    return;
                }
                doc.set_input (s, a.r1, a.c2 + 1, "=SUM(%s:%s)".printf (Address.cell (a.r1, a.c1), Address.cell (a.r1, a.c2)));
                return;
            }
            int top = r - 1;
            while (top >= 0 && s.value_at (top, c).kind == ValueKind.NUMBER) top--;
            string range;
            if (top < r - 1) {
                range = "%s:%s".printf (Address.cell (top + 1, c), Address.cell (r - 1, c));
            } else {
                int left = c - 1;
                while (left >= 0 && s.value_at (r, left).kind == ValueKind.NUMBER) left--;
                range = left < c - 1 ? "%s:%s".printf (Address.cell (r, left + 1), Address.cell (r, c - 1)) : "";
            }
            grid.begin_edit ("=SUM(" + range + ")", false);
        }

        private void fill_direction (bool down) {
            var a = sel ();
            var s = grid.sheet;
            if (down) {
                if (a.rows < 2) return;
                doc.fill_series (s, new Area (s, a.r1, a.c1, a.r1, a.c2), a);
            } else {
                if (a.cols < 2) return;
                doc.fill_series (s, new Area (s, a.r1, a.c1, a.r2, a.c1), a);
            }
        }

        private void paste (Document.PasteMode mode) {
            var clipboard = get_clipboard ();
            var s = grid.sheet;
            var a = sel ();
            if (doc.clip != null && clipboard.is_local ()) {
                var dest = doc.paste (s, a.r1, a.c1, mode, a);
                if (dest != null) grid.select_area (dest);
                return;
            }
            clipboard.read_text_async.begin (null, (obj, res) => {
                try {
                    string? text = clipboard.read_text_async.end (res);
                    if (text != null && text != "") doc.paste_text (s, a.r1, a.c1, text.has_suffix ("\n") ? text : text + "\n");
                } catch (Error e) {
                }
            });
        }

        private void install_actions () {
            ActionMap g = this;
            act (g, "save", () => save.begin (false));
            act (g, "save-as", () => save.begin (true));
            act (g, "save-online", () => CloudActions.save_document (this));
            act (g, "export-csv", () => export.begin ("csv"));
            act (g, "export-pdf", () => export.begin ("pdf"));
            act (g, "export-xlsx", () => export.begin ("xlsx"));
            act (g, "export-ods", () => export.begin ("ods"));
            act (g, "export-tsv", () => export.begin ("tsv"));
            act (g, "export-html", () => export.begin ("html"));
            act (g, "print", () => printer ().print (this));
            act (g, "page-setup", () => SheetPrinter.page_setup (this));
            Singularity.Share.add_action (g, this, () => {
                return doc != null && doc.path != null ? new Singularity.ShareContent.for_files ({ File.new_for_path (doc.path) }) : null;
            });
            act (g, "close-doc", () => close_document ());
            act (g, "undo", () => {
                if (grid.is_editing ()) grid.cancel_edit ();
                doc.undo ();
            });
            act (g, "redo", () => doc.redo ());
            act (g, "cut", () => {
                doc.copy (grid.sheet, sel (), true);
                get_clipboard ().set_text (doc.clip.text);
                grid.queue_draw ();
            });
            act (g, "copy", () => {
                doc.copy (grid.sheet, sel (), false);
                get_clipboard ().set_text (doc.clip.text);
                grid.queue_draw ();
            });
            act (g, "paste", () => paste (Document.PasteMode.ALL));
            act (g, "paste-values", () => paste (Document.PasteMode.VALUES));
            act (g, "paste-formats", () => paste (Document.PasteMode.FORMATS));
            act (g, "paste-formulas", () => paste (Document.PasteMode.FORMULAS));
            act (g, "paste-transpose", () => paste (Document.PasteMode.TRANSPOSE));
            act (g, "clear-contents", () => doc.clear (grid.sheet, sel (), ClearMode.CONTENTS));
            act (g, "clear-formats", () => doc.clear (grid.sheet, sel (), ClearMode.FORMATS));
            act (g, "clear-all", () => doc.clear (grid.sheet, sel (), ClearMode.ALL));
            act (g, "select-all", () => {
                var a = sel ();
                var region = doc.current_region (grid.sheet, grid.cur_row, grid.cur_col);
                bool same = a.r1 == region.r1 && a.c1 == region.c1 && a.r2 == region.r2 && a.c2 == region.c2;
                if (same || region.is_single ()) grid.select_area (new Area (grid.sheet, 0, 0, MAX_ROWS - 1, MAX_COLS - 1));
                else grid.select_area (region);
            });
            act (g, "find", () => find_bubble.clicked ());
            act (g, "goto", () => {
                name_box.grab_focus ();
                name_box.select_region (0, -1);
            });
            act (g, "fill-down", () => fill_direction (true));
            act (g, "fill-right", () => fill_direction (false));
            act (g, "autosum", () => autosum ());
            act (g, "insert-date", () => insert_now (false));
            act (g, "insert-time", () => insert_now (true));
            act (g, "insert-function", () => show_function_picker (formula_entry));
            act (g, "insert-rows-above", () => doc.insert_rows (grid.sheet, sel ().r1, sel ().r1 == 0 && sel ().r2 == MAX_ROWS - 1 ? 1 : int.min (sel ().rows, 1000)));
            act (g, "insert-rows-below", () => doc.insert_rows (grid.sheet, sel ().r2 + 1, int.min (sel ().rows, 1000)));
            act (g, "insert-cols-left", () => doc.insert_cols (grid.sheet, sel ().c1, sel ().c1 == 0 && sel ().c2 == MAX_COLS - 1 ? 1 : int.min (sel ().cols, 100)));
            act (g, "insert-cols-right", () => doc.insert_cols (grid.sheet, sel ().c2 + 1, int.min (sel ().cols, 100)));
            act (g, "insert-cells", () => {
                var a = sel ();
                if (a.r1 == 0 && a.r2 == MAX_ROWS - 1) doc.insert_cols (grid.sheet, a.c1, int.min (a.cols, 100));
                else doc.insert_rows (grid.sheet, a.r1, int.min (a.rows, 1000));
            });
            act (g, "delete-rows", () => {
                var a = sel ();
                doc.delete_rows (grid.sheet, a.r1, a.r1 == 0 && a.r2 == MAX_ROWS - 1 ? 1 : a.rows);
                grid.select_cell (a.r1, a.c1 == 0 && a.c2 == MAX_COLS - 1 ? grid.cur_col : a.c1, false);
            });
            act (g, "delete-cols", () => {
                var a = sel ();
                doc.delete_cols (grid.sheet, a.c1, a.c1 == 0 && a.c2 == MAX_COLS - 1 ? 1 : a.cols);
                grid.select_cell (a.r1 == 0 && a.r2 == MAX_ROWS - 1 ? grid.cur_row : a.r1, a.c1, false);
            });
            act (g, "delete-cells", () => {
                var a = sel ();
                if (a.r1 == 0 && a.r2 == MAX_ROWS - 1) doc.delete_cols (grid.sheet, a.c1, a.cols);
                else doc.delete_rows (grid.sheet, a.r1, a.rows);
            });
            act (g, "insert-sheet", () => {
                var s = doc.add_sheet (doc.book.sheets.index_of (grid.sheet) + 1);
                grid.show_sheet (s);
                rebuild_tabs ();
            });
            act (g, "insert-chart", () => Dialogs.chart (this, null));
            act (g, "note", () => Dialogs.note (this));
            act (g, "insert-link", () => Links.dialog (this));
            act (g, "open-link", () => Links.follow (this, Links.target (doc.book, grid.sheet, grid.cur_row, grid.cur_col)));
            act (g, "format-cells", () => Dialogs.format_cells (this));
            act (g, "bold", () => {
                bool on = !grid.sheet.style_at (grid.cur_row, grid.cur_col).bold;
                doc.edit_style (grid.sheet, sel (), _("Bold"), (st) => st.bold = on);
            });
            act (g, "italic", () => {
                bool on = !grid.sheet.style_at (grid.cur_row, grid.cur_col).italic;
                doc.edit_style (grid.sheet, sel (), _("Italic"), (st) => st.italic = on);
            });
            act (g, "underline", () => {
                bool on = !grid.sheet.style_at (grid.cur_row, grid.cur_col).underline;
                doc.edit_style (grid.sheet, sel (), _("Underline"), (st) => st.underline = on);
            });
            act (g, "strike", () => {
                bool on = !grid.sheet.style_at (grid.cur_row, grid.cur_col).strike;
                doc.edit_style (grid.sheet, sel (), _("Strikethrough"), (st) => st.strike = on);
            });
            act (g, "align-left", () => doc.edit_style (grid.sheet, sel (), _("Align"), (st) => st.halign = HAlign.LEFT));
            act (g, "align-center", () => doc.edit_style (grid.sheet, sel (), _("Align"), (st) => st.halign = HAlign.CENTER));
            act (g, "align-right", () => doc.edit_style (grid.sheet, sel (), _("Align"), (st) => st.halign = HAlign.RIGHT));
            act (g, "wrap", () => {
                bool on = !grid.sheet.style_at (grid.cur_row, grid.cur_col).wrap;
                doc.edit_style (grid.sheet, sel (), _("Wrap Text"), (st) => st.wrap = on);
            });
            act (g, "merge-center", () => doc.merge (grid.sheet, sel (), true));
            act (g, "merge", () => doc.merge (grid.sheet, sel (), false));
            act (g, "unmerge", () => doc.unmerge (grid.sheet, sel ()));
            act (g, "fmt-general", () => set_format ("General"));
            act (g, "fmt-number", () => set_format ("#,##0.00"));
            act (g, "fmt-currency", () => set_format (Dialogs.currency_format (2)));
            act (g, "fmt-percent", () => set_format ("0%"));
            act (g, "fmt-date", () => set_format (LocaleInfo.get ().short_date_format ()));
            act (g, "fmt-time", () => set_format ("h:mm:ss"));
            act (g, "fmt-scientific", () => set_format ("0.00E+00"));
            act (g, "fmt-text", () => set_format ("@"));
            act (g, "dec-inc", () => adjust_decimals (1));
            act (g, "dec-dec", () => adjust_decimals (-1));
            act (g, "col-width", () => Dialogs.size (this, false));
            act (g, "row-height", () => Dialogs.size (this, true));
            act (g, "autofit-cols", () => {
                var a = sel ();
                for (int c = a.c1; c <= int.min (a.c2, int.max (grid.sheet.max_col, a.c1)); c++) grid.autofit_col (c);
            });
            act (g, "autofit-rows", () => {
                var a = sel ();
                for (int r = a.r1; r <= int.min (a.r2, int.max (grid.sheet.max_row, a.r1)); r++) grid.autofit_row (r);
            });
            act (g, "hide-rows", () => doc.set_hidden (grid.sheet, true, sel ().r1, sel ().r2 == MAX_ROWS - 1 ? sel ().r1 : sel ().r2, true));
            act (g, "hide-cols", () => doc.set_hidden (grid.sheet, false, sel ().c1, sel ().c2 == MAX_COLS - 1 ? sel ().c1 : sel ().c2, true));
            act (g, "unhide-rows", () => {
                var a = sel ();
                int a2 = a.r2 == MAX_ROWS - 1 ? int.max (grid.sheet.max_row, a.r1) + 1 : a.r2 + 1;
                doc.set_hidden (grid.sheet, true, int.max (a.r1 - 1, 0), a2, false);
            });
            act (g, "unhide-cols", () => {
                var a = sel ();
                int a2 = a.c2 == MAX_COLS - 1 ? int.max (grid.sheet.max_col, a.c1) + 1 : a.c2 + 1;
                doc.set_hidden (grid.sheet, false, int.max (a.c1 - 1, 0), a2, false);
            });
            act (g, "cond-format", () => Dialogs.cond_format (this));
            act (g, "clear-rules", () => doc.remove_cond_formats (grid.sheet, sel ()));
            act (g, "sort-asc", () => quick_sort (true));
            act (g, "sort-desc", () => quick_sort (false));
            act (g, "sort-custom", () => EditDialogs.sort_advanced (this));
            act (g, "filter", () => {
                doc.toggle_filter (grid.sheet, sel ());
                grid.refresh ();
            });
            act (g, "remove-dups", () => Dialogs.remove_duplicates (this));
            act (g, "validation", () => EditDialogs.validation (this));
            act (g, "names", () => Dialogs.names (this));
            act (g, "freeze", () => {
                var s = grid.sheet;
                if (s.freeze_rows > 0 || s.freeze_cols > 0) doc.set_freeze (s, 0, 0);
                else doc.set_freeze (s, grid.cur_row, grid.cur_col);
                grid.refresh ();
            });
            act (g, "freeze-row", () => {
                doc.set_freeze (grid.sheet, 1, 0);
                grid.refresh ();
            });
            act (g, "freeze-col", () => {
                doc.set_freeze (grid.sheet, 0, 1);
                grid.refresh ();
            });
            act (g, "unfreeze", () => {
                doc.set_freeze (grid.sheet, 0, 0);
                grid.refresh ();
            });
            toggle (g, "gridlines", true, () => doc.set_grid (grid.sheet, !grid.sheet.show_grid));
            toggle (g, "show-formulas", false, () => {
                grid.show_formulas = !grid.show_formulas;
                grid.queue_draw ();
            });
            act (g, "zoom-in", () => grid.zoom_to (grid.zoom * 1.1));
            act (g, "zoom-out", () => grid.zoom_to (grid.zoom / 1.1));
            act (g, "zoom-reset", () => grid.zoom_to (1));
            act (g, "sheet-rename", () => begin_rename_sheet (grid.sheet));
            act (g, "sheet-duplicate", () => {
                var s = doc.duplicate_sheet (grid.sheet);
                grid.show_sheet (s);
                rebuild_tabs ();
            });
            act (g, "sheet-delete", () => {
                if (doc.book.sheets.size > 1) delete_sheet (grid.sheet);
            });
            act (g, "sheet-next", () => {
                int i = doc.book.sheets.index_of (grid.sheet) + 1;
                while (i < doc.book.sheets.size && doc.book.sheets[i].visibility != 0) i++;
                if (i < doc.book.sheets.size) {
                    grid.show_sheet (doc.book.sheets[i]);
                    rebuild_tabs_state ();
                }
            });
            act (g, "sheet-prev", () => {
                int i = doc.book.sheets.index_of (grid.sheet) - 1;
                while (i >= 0 && doc.book.sheets[i].visibility != 0) i--;
                if (i >= 0) {
                    grid.show_sheet (doc.book.sheets[i]);
                    rebuild_tabs_state ();
                }
            });
            act (g, "recalc", () => {
                doc.book.recalculate ();
                grid.refresh ();
            });
            act (g, "sheet-hide", () => hide_sheet (grid.sheet));
            act (g, "sheet-unhide", () => unhide_sheets ());
            act (g, "close", () => close (), false);
            ToolActions.install (this, g);
            actions = this;
            sync_actions ();
        }

        private GLib.ActionGroup actions;
        private string[] doc_actions = {};

        private void sync_actions () {
            foreach (string name in doc_actions) {
                var a = lookup_action (name) as SimpleAction;
                if (a != null) a.set_enabled (doc != null);
            }
            sync_share ();
        }

        private void sync_share () {
            var a = lookup_action ("share") as SimpleAction;
            bool can = doc != null && doc.path != null;
            if (a != null) a.set_enabled (can);
            if (share_bubble != null) share_bubble.sensitive = can;
        }

        public void run (string name) {
            if (actions != null) actions.activate_action (name, null);
        }

        private void quick_sort (bool asc) {
            var a = sel ();
            var s = grid.sheet;
            Area area = a.is_single () ? doc.current_region (s, a.r1, a.c1) : a;
            bool header = false;
            if (area.rows > 1) {
                var top = s.value_at (area.r1, grid.cur_col);
                var next = s.value_at (area.r1 + 1, grid.cur_col);
                header = top.kind == ValueKind.TEXT && next.kind != ValueKind.TEXT && next.kind != ValueKind.EMPTY;
                if (s.style_at (area.r1, area.c1).bold && !s.style_at (area.r1 + 1, area.c1).bold) header = true;
            }
            var keys = new Gee.ArrayList<SortKey> ();
            keys.add (new SortKey (grid.cur_col.clamp (area.c1, area.c2), asc));
            doc.sort (s, area, keys, header);
        }
    }
}
