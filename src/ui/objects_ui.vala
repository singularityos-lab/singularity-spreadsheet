using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class ObjectsUI {
        public static void attach (SpreadsheetWindow win) {
            win.grid.drawing_activated.connect ((d) => edit_drawing (win, d));
            win.grid.drawing_menu.connect ((d, x, y) => drawing_menu (win, d, x, y));
            ImageCache.get_default ().loaded.connect ((src) => {
                win.doc.book.recalculate ();
                win.grid.queue_draw ();
            });
            add_action (win, "insert-picture", () => insert_picture (win));
            add_action (win, "insert-shape-rect", () => insert_shape (win, DrawingKind.RECTANGLE));
            add_action (win, "insert-shape-rounded", () => insert_shape (win, DrawingKind.ROUNDED));
            add_action (win, "insert-shape-ellipse", () => insert_shape (win, DrawingKind.ELLIPSE));
            add_action (win, "insert-shape-line", () => insert_shape (win, DrawingKind.LINE));
            add_action (win, "insert-shape-arrow", () => insert_shape (win, DrawingKind.ARROW));
            add_action (win, "insert-textbox", () => insert_shape (win, DrawingKind.TEXT_BOX));
            add_action (win, "insert-sparklines", () => sparklines (win));
            add_action (win, "insert-diagram", () => insert_diagram (win));
            add_action (win, "clear-sparklines", () => win.doc.clear_sparklines (win.grid.sheet, win.grid.selection));
        }

        public delegate void Run ();

        private static void add_action (SpreadsheetWindow win, string name, owned Run run) {
            var a = new SimpleAction (name, null);
            Run r = (owned) run;
            a.activate.connect (() => r ());
            win.add_action (a);
        }

        private static void place (SpreadsheetWindow win, Drawing d) {
            var s = win.grid.sheet;
            int r = win.grid.cur_row, c = win.grid.cur_col;
            double x = (win.grid.col_x (c) - win.grid.col_x (s.freeze_cols)) / win.grid.zoom + 8;
            double y = (win.grid.row_y (r) - win.grid.row_y (s.freeze_rows)) / win.grid.zoom + 8;
            d.x = double.max (x, 8);
            d.y = double.max (y, 8);
        }

        public static void insert_shape (SpreadsheetWindow win, DrawingKind kind) {
            var d = new Drawing (kind);
            place (win, d);
            if (kind == DrawingKind.LINE || kind == DrawingKind.ARROW) {
                d.width = 160;
                d.height = 60;
                d.stroke_width = 2;
            } else if (kind == DrawingKind.TEXT_BOX) {
                d.width = 220;
                d.height = 90;
                d.text = _("Text");
            } else {
                d.width = 180;
                d.height = 110;
            }
            win.doc.add_drawing (win.grid.sheet, d);
            win.grid.queue_draw ();
        }

        public static void insert_picture (SpreadsheetWindow win) {
            var dialog = new FileDialog ();
            dialog.title = _("Insert Picture");
            var filter = new FileFilter ();
            filter.name = _("Images");
            foreach (string suf in new string[] { "png", "jpg", "jpeg", "gif", "bmp", "webp", "svg" }) filter.add_suffix (suf);
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            dialog.filters = filters;
            dialog.open.begin (win, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) insert_picture_file (win, file);
                } catch (Error e) {
                }
            });
        }

        public static void insert_picture_file (SpreadsheetWindow win, File file) {
            try {
                uint8[] data;
                file.load_contents (null, out data, null);
                var bytes = new Bytes (data);
                var tex = Gdk.Texture.from_bytes (bytes);
                var d = new Drawing (DrawingKind.IMAGE);
                d.image = bytes;
                d.mime = Drawing.mime_of (data);
                d.name = file.get_basename ();
                double w = tex.get_width (), h = tex.get_height ();
                double scale = double.min (1, double.min (480 / w, 360 / h));
                d.width = Math.round (w * scale);
                d.height = Math.round (h * scale);
                place (win, d);
                win.doc.add_drawing (win.grid.sheet, d);
                win.grid.queue_draw ();
            } catch (Error e) {
                win.show_error (_("Could Not Insert Picture"), e.message);
            }
        }

        public static void drawing_menu (SpreadsheetWindow win, Drawing d, double x, double y) {
            var menu = new ContextMenu (win.grid);
            var rect = Gdk.Rectangle ();
            rect.x = (int) x;
            rect.y = (int) y;
            rect.width = 1;
            rect.height = 1;
            menu.pointing_to = rect;
            var s = win.grid.sheet;
            menu.add_item (d.kind == DrawingKind.IMAGE ? _("Edit Picture") : (d.kind == DrawingKind.GROUP ? _("Edit Diagram") : _("Edit Shape")), "document-edit-symbolic", () => edit_drawing (win, d));
            menu.add_item (_("Duplicate"), "edit-copy-symbolic", () => {
                var copy = d.copy ();
                copy.x += 24;
                copy.y += 24;
                win.doc.add_drawing (s, copy);
            });
            menu.add_item (_("Bring to Front"), "go-top-symbolic", () => {
                var copy = d.copy ();
                win.doc.move_object (s, _("Bring to Front"));
                s.drawings.remove (d);
                s.drawings.add (copy);
                win.doc.commit ();
            });
            menu.add_item (_("Send to Back"), "go-bottom-symbolic", () => {
                var copy = d.copy ();
                win.doc.move_object (s, _("Send to Back"));
                s.drawings.remove (d);
                s.drawings.insert (0, copy);
                win.doc.commit ();
            });
            menu.add_separator ();
            menu.add_item (d.kind == DrawingKind.IMAGE ? _("Delete Picture") : _("Delete Shape"), "user-trash-symbolic", () => win.doc.remove_drawing (s, d), "destructive");
            SpreadsheetWindow.popup_menu (menu);
        }

        private static string clean_color (string t) {
            string c = t.strip ().down ();
            if (c == "") return "";
            if (!c.has_prefix ("#")) c = "#" + c;
            return c.length == 7 ? c : "";
        }

        private static TextView items_view (string[] items) {
            var view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.top_margin = view.bottom_margin = 8;
            view.left_margin = view.right_margin = 10;
            view.buffer.text = string.joinv ("\n", items);
            view.add_css_class ("ss-diagram-items");
            view.height_request = 140;
            return view;
        }

        private static string[] view_items (TextView view) {
            string[] out_items = {};
            foreach (string line in view.buffer.text.split ("\n")) if (line.strip () != "") out_items += line.strip ();
            return out_items;
        }

        public static void insert_diagram (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var dlg = Dialogs.make (win, _("Insert Diagram"), 900, 620);
            var split = new Box (Orientation.HORIZONTAL, 16);
            split.margin_start = split.margin_end = 18;
            split.margin_top = 6;
            split.vexpand = true;
            var side = new Box (Orientation.VERTICAL, 14);
            side.margin_end = 6;
            var side_scroll = new ScrolledWindow ();
            side_scroll.hscrollbar_policy = PolicyType.NEVER;
            side_scroll.width_request = 360;
            side_scroll.hexpand = false;
            side_scroll.propagate_natural_width = false;
            side_scroll.child = side;
            string kind = "process";
            string[] start = { _("Plan"), _("Build"), _("Test"), _("Launch") };
            var preview = new DrawingArea ();
            preview.hexpand = true;
            preview.vexpand = true;
            preview.add_css_class ("ss-chart-preview");
            var view = items_view (start);
            var types = new FlowBox ();
            types.selection_mode = SelectionMode.NONE;
            types.max_children_per_line = 2;
            types.min_children_per_line = 2;
            types.homogeneous = true;
            types.column_spacing = 6;
            types.row_spacing = 6;
            ToggleButton? first = null;
            foreach (string k in Diagrams.KINDS) {
                var b = new ToggleButton.with_label (Diagrams.label (k));
                b.add_css_class ("ss-chip");
                if (first == null) first = b;
                else b.group = first;
                b.active = k == kind;
                string kk = k;
                b.toggled.connect (() => {
                    if (!b.active) return;
                    kind = kk;
                    preview.queue_draw ();
                });
                types.append (b);
            }
            var tg = new PreferencesGroup (_("Layout"));
            tg.add_row (types);
            side.append (tg);
            var ig = new PreferencesGroup (_("Items"), _("One item per line"));
            var frame = new ScrolledWindow ();
            frame.child = view;
            frame.height_request = 160;
            ig.add_row (frame);
            side.append (ig);
            var ag = new PreferencesGroup (_("Accessibility"));
            var alt = new EntryRow (_("Alternative text"));
            ag.add_row (alt);
            side.append (ag);
            view.buffer.changed.connect (() => preview.queue_draw ());
            preview.set_draw_func ((da, cr, w, h) => {
                var g = Diagrams.build (kind, view_items (view));
                double scale = double.min ((w - 32) / g.width, (h - 32) / g.height);
                cr.translate ((w - g.width * scale) / 2, (h - g.height * scale) / 2);
                ChartRenderer.draw_drawing (cr, g, g.width * scale, g.height * scale, false, false);
            });
            split.append (side_scroll);
            split.append (preview);
            dlg.content_box.append (split);
            Dialogs.footer (dlg, _("Insert"), () => {
                var g = Diagrams.build (kind, view_items (view));
                g.alt_text = alt.text;
                place (win, g);
                win.doc.add_drawing (s, g);
                win.grid.queue_draw ();
            });
            dlg.open_dialog ();
        }

        public static void edit_drawing (SpreadsheetWindow win, Drawing d) {
            var s = win.grid.sheet;
            if (d.kind == DrawingKind.GROUP) {
                edit_group (win, d);
                return;
            }
            var edit = d.copy ();
            var dlg = Dialogs.make (win, d.kind == DrawingKind.IMAGE ? _("Edit Picture") : _("Edit Shape"), 520, 600);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Appearance"));
            if (d.kind != DrawingKind.IMAGE && d.kind != DrawingKind.LINE && d.kind != DrawingKind.ARROW) {
                var text = new EntryRow (_("Text"));
                text.text = edit.text;
                text.entry_changed.connect (() => edit.text = text.text);
                g.add_row (text);
                var fill = new EntryRow (_("Fill color"));
                fill.text = edit.fill;
                fill.entry_changed.connect (() => edit.fill = clean_color (fill.text));
                g.add_row (fill);
                var tc = new EntryRow (_("Text color"));
                tc.text = edit.text_color;
                tc.entry_changed.connect (() => {
                    string c = clean_color (tc.text);
                    if (c != "") edit.text_color = c;
                });
                g.add_row (tc);
                var fs = new SpinRow (_("Font size"), null, 6, 96, 1, edit.font_size);
                fs.spin_btn.value_changed.connect (() => edit.font_size = fs.value);
                g.add_row (fs);
            }
            if (d.kind != DrawingKind.IMAGE) {
                var stroke = new EntryRow (_("Line color"));
                stroke.text = edit.stroke;
                stroke.entry_changed.connect (() => edit.stroke = clean_color (stroke.text));
                g.add_row (stroke);
                var sw = new SpinRow (_("Line width"), null, 0, 20, 0.5, edit.stroke_width);
                sw.spin_btn.value_changed.connect (() => edit.stroke_width = sw.value);
                g.add_row (sw);
            }
            var name = new EntryRow (_("Name"));
            name.text = edit.name;
            name.entry_changed.connect (() => edit.name = name.text);
            g.add_row (name);
            var alt = new EntryRow (_("Alternative text"));
            alt.text = edit.alt_text;
            alt.entry_changed.connect (() => edit.alt_text = alt.text);
            g.add_row (alt);
            box.append (g);
            var sg = new PreferencesGroup (_("Size"));
            var w = new SpinRow (_("Width"), null, 0, 4000, 1, edit.width);
            w.spin_btn.value_changed.connect (() => edit.width = w.value);
            var h = new SpinRow (_("Height"), null, 0, 4000, 1, edit.height);
            h.spin_btn.value_changed.connect (() => edit.height = h.value);
            sg.add_row (w);
            sg.add_row (h);
            box.append (sg);
            Dialogs.footer (dlg, _("Apply"), () => {
                win.doc.update_drawing (s, d, edit);
                win.grid.queue_draw ();
            });
            dlg.open_dialog ();
        }

        public static void edit_group (SpreadsheetWindow win, Drawing d) {
            var s = win.grid.sheet;
            var dlg = Dialogs.make (win, _("Edit Diagram"), 560, 620);
            var box = Dialogs.body (dlg);
            string kind = d.diagram != "" ? d.diagram : "";
            string[] labels = { _("Keep Current Shapes") };
            foreach (string k in Diagrams.KINDS) labels += Diagrams.label (k);
            var layout = new SelectionRow (_("Layout"), labels, kind != "" ? Diagrams.label (kind) : labels[0]);
            layout.selected.connect ((v) => {
                kind = "";
                foreach (string k in Diagrams.KINDS) if (Diagrams.label (k) == v) kind = k;
            });
            var g = new PreferencesGroup (_("Diagram"));
            g.add_row (layout);
            box.append (g);
            var ig = new PreferencesGroup (_("Items"), _("One item per line"));
            var view = items_view (Diagrams.items_of (d));
            var frame = new ScrolledWindow ();
            frame.child = view;
            frame.height_request = 180;
            ig.add_row (frame);
            box.append (ig);
            var ag = new PreferencesGroup (_("Accessibility"));
            var alt = new EntryRow (_("Alternative text"));
            alt.text = d.alt_text;
            ag.add_row (alt);
            box.append (ag);
            Dialogs.footer (dlg, _("Apply"), () => {
                var items = view_items (view);
                Drawing updated;
                if (kind != "") {
                    updated = Diagrams.rebuild (d, kind, items);
                } else {
                    updated = d.copy ();
                    int i = 0;
                    foreach (var c in updated.children) {
                        if (c.kind == DrawingKind.LINE || c.kind == DrawingKind.ARROW || c.text.strip () == "") continue;
                        if (i < items.length) c.text = items[i];
                        i++;
                    }
                }
                updated.alt_text = alt.text;
                win.doc.update_drawing (s, d, updated);
                win.grid.queue_draw ();
            });
            dlg.open_dialog ();
        }

        public static void sparklines (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            var sel = Document.clamp_area (s, win.grid.selection);
            var dlg = Dialogs.make (win, _("Insert Sparklines"), 520, 620);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Data"));
            var data = new EntryRow (_("Data range"));
            data.text = Dialogs.area_text (sel);
            var loc = new EntryRow (_("Location range"));
            int lr = sel.rows >= sel.cols ? sel.r1 : sel.r2 + 1;
            int lc = sel.rows >= sel.cols ? sel.c2 + 1 : sel.c1;
            var default_loc = sel.rows >= sel.cols && sel.cols > 1 ? new Area (s, sel.r1, sel.c2 + 1, sel.r2, sel.c2 + 1) : new Area (s, lr, lc, lr, lc);
            if (sel.rows == 1 && sel.cols > 1) default_loc = new Area (s, sel.r1, sel.c2 + 1, sel.r1, sel.c2 + 1);
            loc.text = Dialogs.area_text (default_loc);
            g.add_row (data);
            g.add_row (loc);
            box.append (g);
            var group = new SparklineGroup ();
            var og = new PreferencesGroup (_("Style"));
            string[] kinds = { _("Line"), _("Column"), _("Win/Loss") };
            var kind = new SelectionRow (_("Type"), kinds, kinds[0]);
            kind.selected.connect ((v) => {
                for (int i = 0; i < kinds.length; i++) if (kinds[i] == v) group.kind = (SparklineKind) i;
            });
            og.add_row (kind);
            var color = new EntryRow (_("Color"));
            color.text = group.color;
            color.entry_changed.connect (() => {
                string c = clean_color (color.text);
                if (c != "") group.color = c;
            });
            og.add_row (color);
            var markers = new SwitchRow (_("Markers"), null, false);
            markers.switch_btn.notify["active"].connect (() => group.markers = markers.active);
            var high = new SwitchRow (_("High point"), null, false);
            high.switch_btn.notify["active"].connect (() => group.high = high.active);
            var low = new SwitchRow (_("Low point"), null, false);
            low.switch_btn.notify["active"].connect (() => group.low = low.active);
            var negative = new SwitchRow (_("Negative points"), null, false);
            negative.switch_btn.notify["active"].connect (() => group.negative = negative.active);
            var first = new SwitchRow (_("First point"), null, false);
            first.switch_btn.notify["active"].connect (() => group.first = first.active);
            var last = new SwitchRow (_("Last point"), null, false);
            last.switch_btn.notify["active"].connect (() => group.last = last.active);
            og.add_row (markers);
            og.add_row (high);
            og.add_row (low);
            og.add_row (negative);
            og.add_row (first);
            og.add_row (last);
            box.append (og);
            Dialogs.footer (dlg, _("Insert"), () => {
                var src = Area.parse (data.text.replace ("$", ""), s);
                var dst = Area.parse (loc.text.replace ("$", ""), s);
                if (src == null || dst == null) {
                    win.show_error (_("Invalid Range"), _("Enter a valid data range and location range."));
                    return;
                }
                bool by_rows = dst.cols == 1 && dst.rows > 1;
                bool by_cols = dst.rows == 1 && dst.cols > 1;
                int n = int.max (dst.rows, dst.cols);
                for (int i = 0; i < n; i++) {
                    int r = by_rows ? dst.r1 + i : dst.r1;
                    int c = by_cols ? dst.c1 + i : dst.c1;
                    Area part;
                    if (n == 1) part = src;
                    else if (by_rows) part = new Area (s, src.r1 + i, src.c1, src.r1 + i, src.c2);
                    else part = new Area (s, src.r1, src.c1 + i, src.r2, src.c1 + i);
                    group.items.add (new Sparkline (r, c, ChartResolve.area_ref (s, part.r1, part.c1, part.r2, part.c2)));
                }
                win.doc.add_sparklines (s, group);
                win.grid.queue_draw ();
            });
            dlg.open_dialog ();
        }
    }
}
