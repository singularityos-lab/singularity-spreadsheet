using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class TraceArrow {
        public Area from;
        public AuditRef to;
        public bool error;

        public TraceArrow (Area from, AuditRef to, bool error) {
            this.from = from;
            this.to = to;
            this.error = error;
        }
    }

    public class GridExtras : Object {
        public SpreadsheetWindow win;
        public SheetView grid;
        public bool break_preview;
        public bool recording;
        public Gee.ArrayList<TraceArrow> arrows = new Gee.ArrayList<TraceArrow> ();
        private Gee.ArrayList<AuditRef> prec_frontier = new Gee.ArrayList<AuditRef> ();
        private Gee.ArrayList<AuditRef> dep_frontier = new Gee.ArrayList<AuditRef> ();
        private AuditRef? prec_origin;
        private AuditRef? dep_origin;
        private bool drag_rows;
        private int drag_index = -1;
        private bool drag_manual;
        private double drag_x;
        private double drag_y;
        private bool dragging;

        public GridExtras (SpreadsheetWindow win, SheetView grid) {
            this.win = win;
            this.grid = grid;
            grid.draw_overlay.connect (draw);
            var drag = new GestureDrag ();
            drag.propagation_phase = PropagationPhase.CAPTURE;
            drag.drag_begin.connect (on_drag_begin);
            drag.drag_update.connect ((dx, dy) => {
                if (!dragging) return;
                double sx, sy;
                drag.get_start_point (out sx, out sy);
                drag_x = sx + dx;
                drag_y = sy + dy;
                grid.queue_draw ();
            });
            drag.drag_end.connect ((dx, dy) => {
                if (!dragging) return;
                double sx, sy;
                drag.get_start_point (out sx, out sy);
                finish_drag (sx + dx, sy + dy);
            });
            grid.add_controller (drag);
            MacroUi.apply_shortcuts (win);
            if (MacroUi.needs_trust (win.doc)) {
                Idle.add (() => {
                    if (win.doc != null && win.grid == grid) MacroUi.confirm (win, null, true);
                    return Source.REMOVE;
                });
            }
        }

        private PrintLayout? layout () {
            var s = grid.sheet;
            if (s.max_row < 0 && s.page.print_area == "") return null;
            return PrintLayout.compute (s, s.page, s.page.page_width, s.page.page_height);
        }

        private double x_of (int c) {
            return grid.col_x (c);
        }

        private double y_of (int r) {
            return grid.row_y (r);
        }

        private double x_end (int c) {
            return grid.col_x (c) + grid.col_w (c);
        }

        private double y_end (int r) {
            return grid.row_y (r) + grid.row_h (r);
        }

        private void draw (Cairo.Context cr, double w, double h) {
            if (break_preview) draw_breaks (cr, w, h);
            if (arrows.size > 0) draw_arrows (cr);
            if (recording) draw_recording (cr, w, h);
        }

        private void draw_recording (Cairo.Context cr, double w, double h) {
            var pl = Pango.cairo_create_layout (cr);
            pl.set_font_description (Pango.FontDescription.from_string ("Sans Bold 10"));
            pl.set_text (_("Recording macro"), -1);
            int lw, lh;
            pl.get_pixel_size (out lw, out lh);
            double bw = lw + 34, bh = lh + 12;
            double x = w - bw - 16, y = h - bh - 16;
            cr.new_sub_path ();
            cr.arc (x + bh / 2, y + bh / 2, bh / 2, Math.PI / 2, 3 * Math.PI / 2);
            cr.arc (x + bw - bh / 2, y + bh / 2, bh / 2, -Math.PI / 2, Math.PI / 2);
            cr.close_path ();
            cr.set_source_rgba (0.12, 0.12, 0.14, 0.88);
            cr.fill ();
            cr.set_source_rgb (0.9, 0.2, 0.2);
            cr.arc (x + 14, y + bh / 2, 5, 0, 2 * Math.PI);
            cr.fill ();
            cr.set_source_rgb (1, 1, 1);
            cr.move_to (x + 26, y + 6);
            Pango.cairo_show_layout (cr, pl);
        }

        private void draw_breaks (Cairo.Context cr, double w, double h) {
            var l = layout ();
            cr.save ();
            cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
            cr.rectangle (0, 0, w, h);
            if (l != null) {
                foreach (var p in l.pages) cr.rectangle (x_of (p.c1), y_of (p.r1), x_end (p.c2) - x_of (p.c1), y_end (p.r2) - y_of (p.r1));
            }
            cr.set_source_rgba (0.55, 0.56, 0.6, 0.35);
            cr.fill ();
            cr.restore ();
            if (l == null) return;
            var s = grid.sheet;
            int n = 0;
            foreach (var p in l.pages) {
                n++;
                double x1 = x_of (p.c1), y1 = y_of (p.r1), x2 = x_end (p.c2), y2 = y_end (p.r2);
                if (x2 < 0 || y2 < 0 || x1 > w || y1 > h) continue;
                double vx1 = double.max (x1, 0), vy1 = double.max (y1, 0), vx2 = double.min (x2, w), vy2 = double.min (y2, h);
                var pl = Pango.cairo_create_layout (cr);
                var fd = Pango.FontDescription.from_string ("Sans Bold");
                fd.set_absolute_size (double.min (56 * grid.zoom, (vx2 - vx1) / 5) * Pango.SCALE);
                pl.set_font_description (fd);
                pl.set_text (_("Page %d").printf (l.page_number (n - 1)), -1);
                int lw, lh;
                pl.get_pixel_size (out lw, out lh);
                cr.set_source_rgba (0.45, 0.47, 0.52, 0.28);
                cr.move_to ((vx1 + vx2 - lw) / 2, (vy1 + vy2 - lh) / 2);
                Pango.cairo_show_layout (cr, pl);
                cr.set_source_rgb (0.1, 0.37, 0.8);
                cr.set_line_width (2);
                cr.set_dash ({ 7, 4 }, 0);
                cr.rectangle (x1, y1, x2 - x1, y2 - y1);
                cr.stroke ();
                cr.set_dash (null, 0);
                cr.set_line_width (3);
                if (p.manual_row_end) {
                    cr.move_to (x1, y2);
                    cr.line_to (x2, y2);
                    cr.stroke ();
                }
                if (p.manual_col_end) {
                    cr.move_to (x2, y1);
                    cr.line_to (x2, y2);
                    cr.stroke ();
                }
            }
            cr.set_source_rgb (0.1, 0.37, 0.8);
            cr.set_line_width (3);
            foreach (var a in l.areas) {
                int r2 = a.r2 == MAX_ROWS - 1 ? int.max (s.max_row, a.r1) : a.r2;
                int c2 = a.c2 == MAX_COLS - 1 ? int.max (s.max_col, a.c1) : a.c2;
                cr.rectangle (x_of (a.c1), y_of (a.r1), x_end (c2) - x_of (a.c1), y_end (r2) - y_of (a.r1));
                cr.stroke ();
            }
            if (dragging) {
                cr.set_source_rgba (0.1, 0.37, 0.8, 0.8);
                cr.set_line_width (3);
                if (drag_rows) {
                    cr.move_to (0, drag_y);
                    cr.line_to (w, drag_y);
                } else {
                    cr.move_to (drag_x, 0);
                    cr.line_to (drag_x, h);
                }
                cr.stroke ();
            }
        }

        private void on_drag_begin (GestureDrag g, double x, double y) {
            dragging = false;
            if (!break_preview) return;
            var l = layout ();
            if (l == null) return;
            foreach (var p in l.pages) {
                var a = l.areas[p.area_index];
                if (p.c1 > a.c1 && Math.fabs (x - x_of (p.c1)) < 5 && y >= y_of (p.r1) && y <= y_end (p.r2)) {
                    drag_rows = false;
                    drag_index = p.c1;
                    drag_manual = grid.sheet.page.col_breaks.contains (p.c1);
                    dragging = true;
                } else if (p.r1 > a.r1 && Math.fabs (y - y_of (p.r1)) < 5 && x >= x_of (p.c1) && x <= x_end (p.c2)) {
                    drag_rows = true;
                    drag_index = p.r1;
                    drag_manual = grid.sheet.page.row_breaks.contains (p.r1);
                    dragging = true;
                }
                if (dragging) break;
            }
            if (dragging) {
                drag_x = x;
                drag_y = y;
                g.set_state (EventSequenceState.CLAIMED);
            }
        }

        private void finish_drag (double x, double y) {
            dragging = false;
            var s = grid.sheet;
            int target = drag_rows ? grid.row_at (y + grid.row_h (grid.row_at (y)) / 2) : grid.col_at (x + grid.col_w (grid.col_at (x)) / 2);
            if (target < 0) {
                grid.queue_draw ();
                return;
            }
            win.doc.begin_book (_("Move Page Break"), s);
            var set = drag_rows ? s.page.row_breaks : s.page.col_breaks;
            if (drag_manual) set.remove (drag_index);
            if (target > 0) set.add (target);
            win.doc.commit ();
            grid.queue_draw ();
        }

        public void set_break (bool on) {
            var s = grid.sheet;
            int r = grid.cur_row, c = grid.cur_col;
            var sel = grid.selection;
            bool whole_row = sel.c1 == 0 && sel.c2 == MAX_COLS - 1;
            bool whole_col = sel.r1 == 0 && sel.r2 == MAX_ROWS - 1;
            win.doc.begin_book (on ? _("Insert Page Break") : _("Remove Page Break"), s);
            if (!whole_col && r > 0) s.page.set_break (true, r, on);
            if (!whole_row && c > 0) s.page.set_break (false, c, on);
            win.doc.commit ();
            grid.queue_draw ();
        }

        public void reset_breaks () {
            var s = grid.sheet;
            win.doc.begin_book (_("Reset All Page Breaks"), s);
            s.page.row_breaks.clear ();
            s.page.col_breaks.clear ();
            win.doc.commit ();
            grid.queue_draw ();
        }

        public void set_print_area (bool clear) {
            var s = grid.sheet;
            win.doc.begin_book (clear ? _("Clear Print Area") : _("Set Print Area"), s);
            s.page.print_area = clear ? "" : ToolDialogs.area_text (Document.clamp_area (s, grid.selection));
            win.doc.commit ();
            grid.queue_draw ();
        }

        public void add_print_area () {
            var s = grid.sheet;
            string t = ToolDialogs.area_text (Document.clamp_area (s, grid.selection));
            win.doc.begin_book (_("Add to Print Area"), s);
            s.page.print_area = s.page.print_area == "" ? t : s.page.print_area + "," + t;
            win.doc.commit ();
            grid.queue_draw ();
        }

        private void center_of (Area a, out double x, out double y) {
            x = (x_of (a.c1) + x_end (a.c2)) / 2;
            y = (y_of (a.r1) + y_end (a.r2)) / 2;
        }

        private void arrow_head (Cairo.Context cr, double x1, double y1, double x2, double y2) {
            double ang = Math.atan2 (y2 - y1, x2 - x1);
            double len = 9;
            cr.move_to (x2, y2);
            cr.line_to (x2 - len * Math.cos (ang - 0.4), y2 - len * Math.sin (ang - 0.4));
            cr.line_to (x2 - len * Math.cos (ang + 0.4), y2 - len * Math.sin (ang + 0.4));
            cr.close_path ();
            cr.fill ();
        }

        private void draw_arrows (Cairo.Context cr) {
            var s = grid.sheet;
            foreach (var ar in arrows) {
                if (ar.to.sheet != s && (ar.from.sheet ?? ar.to.sheet) != s) continue;
                if (ar.error) cr.set_source_rgb (0.85, 0.1, 0.1);
                else cr.set_source_rgb (0.1, 0.3, 0.85);
                cr.set_line_width (1.6);
                double tx, ty;
                center_of (new Area.cell (s, ar.to.row, ar.to.col), out tx, out ty);
                var from_sheet = ar.from.sheet ?? ar.to.sheet;
                if (from_sheet != ar.to.sheet) {
                    if (ar.to.sheet != s) continue;
                    double ix = tx - 60, iy = ty - 40;
                    cr.set_source_rgb (0.15, 0.15, 0.15);
                    cr.set_dash ({ 4, 3 }, 0);
                    cr.move_to (ix + 10, iy + 8);
                    cr.line_to (tx, ty);
                    cr.stroke ();
                    cr.set_dash (null, 0);
                    arrow_head (cr, ix + 10, iy + 8, tx, ty);
                    cr.set_line_width (1.2);
                    cr.rectangle (ix, iy, 20, 16);
                    cr.move_to (ix, iy + 5.5);
                    cr.line_to (ix + 20, iy + 5.5);
                    cr.move_to (ix, iy + 10.5);
                    cr.line_to (ix + 20, iy + 10.5);
                    cr.move_to (ix + 7, iy);
                    cr.line_to (ix + 7, iy + 16);
                    cr.stroke ();
                    continue;
                }
                double fx, fy;
                center_of (ar.from, out fx, out fy);
                if (!ar.from.is_single ()) {
                    cr.rectangle (x_of (ar.from.c1) + 1, y_of (ar.from.r1) + 1, x_end (ar.from.c2) - x_of (ar.from.c1) - 2, y_end (ar.from.r2) - y_of (ar.from.r1) - 2);
                    cr.stroke ();
                    fx = x_of (ar.from.c1) + 6;
                    fy = y_of (ar.from.r1) + 6;
                }
                cr.arc (fx, fy, 3, 0, 2 * Math.PI);
                cr.fill ();
                cr.move_to (fx, fy);
                cr.line_to (tx, ty);
                cr.stroke ();
                arrow_head (cr, fx, fy, tx, ty);
            }
        }

        private bool has_arrow (Area from, AuditRef to) {
            foreach (var a in arrows) {
                if (a.to.same (to) && a.from.sheet == from.sheet && a.from.r1 == from.r1 && a.from.c1 == from.c1 && a.from.r2 == from.r2 && a.from.c2 == from.c2) return true;
            }
            return false;
        }

        private static bool area_has_error (Area a) {
            var s = a.sheet;
            if (s == null) return false;
            bool err = false;
            s.foreach_in (a, (r, c, cell) => {
                if (s.value_at (r, c).is_error ()) err = true;
            });
            return err;
        }

        public int trace_precedents () {
            var s = grid.sheet;
            var here = new AuditRef (s, grid.cur_row, grid.cur_col);
            if (prec_origin == null || !prec_origin.same (here)) {
                prec_origin = here;
                prec_frontier.clear ();
                prec_frontier.add (here);
            }
            int added = 0;
            var next = new Gee.ArrayList<AuditRef> ();
            foreach (var cell in prec_frontier) {
                foreach (var a in Audit.precedents (win.doc.book, cell.sheet, cell.row, cell.col)) {
                    if (a.sheet == null) a.sheet = cell.sheet;
                    if (!has_arrow (a, cell)) {
                        arrows.add (new TraceArrow (a, cell, area_has_error (a)));
                        added++;
                    }
                    if (a.size <= 10000) next.add_all (Audit.formula_cells_in (win.doc.book, a));
                }
            }
            prec_frontier = next;
            grid.queue_draw ();
            return added;
        }

        public int trace_dependents () {
            var s = grid.sheet;
            var here = new AuditRef (s, grid.cur_row, grid.cur_col);
            if (dep_origin == null || !dep_origin.same (here)) {
                dep_origin = here;
                dep_frontier.clear ();
                dep_frontier.add (here);
            }
            int added = 0;
            var next = new Gee.ArrayList<AuditRef> ();
            foreach (var cell in dep_frontier) {
                var from = new Area.cell (cell.sheet, cell.row, cell.col);
                foreach (var d in Audit.dependents (win.doc.book, cell.sheet, cell.row, cell.col)) {
                    if (!has_arrow (from, d)) {
                        arrows.add (new TraceArrow (from, d, cell.sheet.value_at (cell.row, cell.col).is_error ()));
                        added++;
                    }
                    next.add (d);
                }
            }
            dep_frontier = next;
            grid.queue_draw ();
            return added;
        }

        public void remove_arrows () {
            arrows.clear ();
            prec_frontier.clear ();
            dep_frontier.clear ();
            prec_origin = null;
            dep_origin = null;
            grid.queue_draw ();
        }
    }

    public class AuditDialogs {
        public static void evaluate (SpreadsheetWindow win) {
            var s = win.grid.sheet;
            int r = win.grid.cur_row, c = win.grid.cur_col;
            var cell = s.get_cell (r, c);
            if (cell == null || cell.formula == null) {
                win.show_error (_("Evaluate Formula"), _("The selected cell does not contain a formula."));
                return;
            }
            var ev = new FormulaEvaluation (win.doc.book, s, r, c, cell.formula);
            var dlg = ToolDialogs.make (win, _("Evaluate Formula"), 620, 360);
            var box = ToolDialogs.scroll_box (dlg.content_box);
            var g = new PreferencesGroup (Address.quote_sheet (s.name) + "!" + Address.cell (r, c));
            var label = new Label ("");
            label.wrap = true;
            label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            label.xalign = 0;
            label.selectable = true;
            label.add_css_class ("monospace");
            label.margin_top = label.margin_bottom = 12;
            label.margin_start = label.margin_end = 12;
            g.add_row (label);
            box.append (g);
            var hint = new Label (_("The underlined part is evaluated next. Evaluate replaces it with its result."));
            hint.add_css_class ("dim-label");
            hint.wrap = true;
            hint.xalign = 0;
            box.append (hint);
            var bar = ToolDialogs.close_footer (dlg);
            var restart = new Button.with_label (_("Restart"));
            var step = new Button.with_label (_("Evaluate"));
            step.add_css_class ("suggested-action");
            bar.prepend (step);
            bar.prepend (restart);
            ToolDialogs.Apply update = () => {
                label.set_markup ("<big>" + ev.markup () + "</big>");
                step.sensitive = !ev.finished;
            };
            step.clicked.connect (() => {
                ev.step ();
                update ();
            });
            restart.clicked.connect (() => {
                ev.restart ();
                update ();
            });
            update ();
            dlg.default_widget = step;
            dlg.open_dialog ();
        }

        private static string kind_title (IssueKind k) {
            switch (k) {
                case IssueKind.ERROR_VALUE: return _("Error in Value");
                case IssueKind.NUMBER_AS_TEXT: return _("Number Stored as Text");
                case IssueKind.INCONSISTENT: return _("Inconsistent Formula");
                case IssueKind.CIRCULAR: return _("Circular Reference");
                case IssueKind.EMPTY_REFERENCE: return _("Formula Refers to Empty Cells");
                default: return _("Issue");
            }
        }

        public static void error_check (SpreadsheetWindow win) {
            var issues = Audit.check (win.doc.book);
            var dlg = ToolDialogs.make (win, _("Error Checking"), 560, 520);
            var box = ToolDialogs.scroll_box (dlg.content_box);
            if (issues.size == 0) {
                var st = new StatusPage ();
                st.icon_name = "emblem-ok-symbolic";
                st.title = _("No Errors Found");
                st.description = _("The error check is complete for the entire workbook.");
                st.vexpand = true;
                box.append (st);
                ToolDialogs.close_footer (dlg);
                dlg.open_dialog ();
                return;
            }
            var g = new PreferencesGroup (ngettext ("%d issue", "%d issues", issues.size).printf (issues.size));
            foreach (var issue in issues) {
                var it = issue;
                var row = new ActionRow (kind_title (it.kind), "%s!%s  %s".printf (Address.quote_sheet (it.sheet.name), Address.cell (it.row, it.col), it.message));
                var go = ToolDialogs.flat ("find-location-symbolic", _("Go to Cell"));
                go.clicked.connect (() => win.go_to (it.sheet, it.row, it.col));
                row.add_suffix (go);
                if (it.kind == IssueKind.NUMBER_AS_TEXT) {
                    var fix = new Button.with_label (_("Convert to Number"));
                    fix.valign = Align.CENTER;
                    fix.clicked.connect (() => {
                        string t = it.sheet.input_at (it.row, it.col);
                        win.doc.set_input (it.sheet, it.row, it.col, t.has_prefix ("'") ? t.substring (1).strip () : t.strip ());
                        g.remove_row (row);
                    });
                    row.add_suffix (fix);
                }
                if (it.kind == IssueKind.ERROR_VALUE || it.kind == IssueKind.INCONSISTENT) {
                    var trace = new Button.with_label (_("Trace"));
                    trace.valign = Align.CENTER;
                    trace.tooltip_text = _("Trace Precedents");
                    trace.clicked.connect (() => {
                        win.go_to (it.sheet, it.row, it.col);
                        win.extras.trace_precedents ();
                    });
                    row.add_suffix (trace);
                }
                var ignore = ToolDialogs.flat ("window-close-symbolic", _("Ignore"));
                ignore.clicked.connect (() => g.remove_row (row));
                row.add_suffix (ignore);
                g.add_row (row);
            }
            box.append (g);
            ToolDialogs.close_footer (dlg);
            dlg.open_dialog ();
            win.go_to (issues[0].sheet, issues[0].row, issues[0].col);
        }

        public static void circular (SpreadsheetWindow win) {
            var book = win.doc.book;
            book.recalculate ();
            var cells = new Gee.ArrayList<AuditRef> ();
            foreach (string t in book.circular) {
                int bang = t.last_index_of ("!");
                if (bang < 0) continue;
                string sn = t.substring (0, bang);
                if (sn.has_prefix ("'")) sn = sn.substring (1, sn.length - 2).replace ("''", "'");
                var s = book.find_sheet (sn);
                int r = 0, c = 0;
                bool a, b;
                if (s != null && Address.parse_cell (t.substring (bang + 1), out r, out c, out a, out b)) cells.add (new AuditRef (s, r, c));
            }
            foreach (var s in book.sheets) {
                foreach (var cl in s.cells.values) {
                    if (cl.formula == null) continue;
                    var v = book.cell_value (s, cl);
                    if (!v.is_error () || v.error != ErrorKind.CIRC) continue;
                    bool known = false;
                    foreach (var x in cells) if (x.sheet == s && x.row == cl.row && x.col == cl.col) known = true;
                    if (!known) cells.add (new AuditRef (s, cl.row, cl.col));
                }
            }
            var dlg = ToolDialogs.make (win, _("Circular References"), 460, 420);
            var box = ToolDialogs.scroll_box (dlg.content_box);
            if (cells.size == 0) {
                var st = new StatusPage ();
                st.icon_name = "emblem-ok-symbolic";
                st.title = _("No Circular References");
                st.description = _("No formula refers back to itself.");
                st.vexpand = true;
                box.append (st);
            } else {
                var g = new PreferencesGroup (null, book.iterative ? _("Iterative calculation is on, so these cells converge instead of failing.") : _("These formulas depend on their own result."));
                foreach (var x in cells) {
                    var cref = x;
                    var row = new ActionRow (cref.label (null), cref.sheet.input_at (cref.row, cref.col));
                    var go = ToolDialogs.flat ("find-location-symbolic", _("Go to Cell"));
                    go.clicked.connect (() => {
                        win.go_to (cref.sheet, cref.row, cref.col);
                        win.extras.trace_precedents ();
                    });
                    row.add_suffix (go);
                    g.add_row (row);
                }
                box.append (g);
            }
            ToolDialogs.close_footer (dlg);
            dlg.open_dialog ();
        }

        public static void watch_window (SpreadsheetWindow win) {
            var book = win.doc.book;
            var dlg = ToolDialogs.make (win, _("Watch Window"), 620, 420);
            dlg.modal = false;
            var box = ToolDialogs.scroll_box (dlg.content_box);
            var g = new PreferencesGroup (_("Watched Cells"));
            var add = new Button.with_label (_("Add Selected Cell"));
            add.add_css_class ("flat");
            g.add_header_suffix (add);
            box.append (g);
            ToolDialogs.Apply rebuild = null;
            rebuild = () => {
                g.clear ();
                if (book.watches.size == 0) {
                    g.add_row (new ActionRow (_("No watched cells"), _("Select a cell and add it to follow its value while you work elsewhere.")));
                    return;
                }
                foreach (var w in book.watches) {
                    var wt = w;
                    if (!book.sheets.contains (wt.sheet)) continue;
                    string color;
                    var v = wt.sheet.value_at (wt.row, wt.col);
                    string shown = NumberFormat.format_value (v, wt.sheet.style_at (wt.row, wt.col).number_format, out color, book.date1904);
                    var row = new ActionRow ("%s!%s = %s".printf (Address.quote_sheet (wt.sheet.name), Address.cell (wt.row, wt.col), shown), wt.sheet.input_at (wt.row, wt.col));
                    var go = ToolDialogs.flat ("find-location-symbolic", _("Go to Cell"));
                    go.clicked.connect (() => win.go_to (wt.sheet, wt.row, wt.col));
                    var del = ToolDialogs.flat ("user-trash-symbolic", _("Delete Watch"));
                    del.clicked.connect (() => {
                        book.watches.remove (wt);
                        win.doc.modified = true;
                        rebuild ();
                    });
                    row.add_suffix (go);
                    row.add_suffix (del);
                    g.add_row (row);
                }
            };
            add.clicked.connect (() => {
                var sel = win.grid.selection;
                var s = win.grid.sheet;
                int count = 0;
                for (int r = sel.r1; r <= sel.r2 && count < 200; r++) {
                    for (int c = sel.c1; c <= sel.c2 && count < 200; c++) {
                        bool dup = false;
                        foreach (var w in book.watches) if (w.sheet == s && w.row == r && w.col == c) dup = true;
                        if (!dup) book.watches.add (new CellWatch (s, r, c));
                        count++;
                    }
                }
                win.doc.modified = true;
                rebuild ();
            });
            ulong handler = win.doc.changed.connect (() => rebuild ());
            var doc = win.doc;
            dlg.close_request.connect (() => {
                doc.disconnect (handler);
                return false;
            });
            rebuild ();
            ToolDialogs.close_footer (dlg);
            dlg.open_dialog ();
        }
    }

    public class ToolActions {
        private static void add (SpreadsheetWindow win, ActionMap g, string name, owned ToolDialogs.Apply handler) {
            var a = new SimpleAction (name, null);
            ToolDialogs.Apply h = (owned) handler;
            a.activate.connect (() => {
                if (win.doc == null || win.grid == null) return;
                h ();
            });
            g.add_action (a);
        }

        public static void install (SpreadsheetWindow win, ActionMap g) {
            var preview = new SimpleAction.stateful ("page-break-preview", null, new Variant.boolean (false));
            preview.activate.connect (() => {
                if (win.extras == null) return;
                win.extras.break_preview = !win.extras.break_preview;
                preview.set_state (new Variant.boolean (win.extras.break_preview));
                win.grid.queue_draw ();
            });
            g.add_action (preview);
            add (win, g, "print-area-set", () => win.extras.set_print_area (false));
            add (win, g, "print-area-add", () => win.extras.add_print_area ());
            add (win, g, "print-area-clear", () => win.extras.set_print_area (true));
            add (win, g, "page-break-insert", () => win.extras.set_break (true));
            add (win, g, "page-break-remove", () => win.extras.set_break (false));
            add (win, g, "page-break-reset", () => win.extras.reset_breaks ());
            add (win, g, "print-titles", () => PageSetupDialog.show (win));
            add (win, g, "trace-precedents", () => win.extras.trace_precedents ());
            add (win, g, "trace-dependents", () => win.extras.trace_dependents ());
            add (win, g, "remove-arrows", () => win.extras.remove_arrows ());
            add (win, g, "evaluate-formula", () => AuditDialogs.evaluate (win));
            add (win, g, "error-checking", () => AuditDialogs.error_check (win));
            add (win, g, "watch-window", () => AuditDialogs.watch_window (win));
            add (win, g, "circular-refs", () => AuditDialogs.circular (win));
            add (win, g, "macros", () => MacroUi.macros_dialog (win));
            add (win, g, "macro-record", () => MacroUi.toggle_recording (win));
            add (win, g, "script-editor", () => MacroUi.editor (win, null));
            var run = new SimpleAction ("run-macro", VariantType.STRING);
            run.activate.connect ((p) => {
                if (win.doc == null || p == null) return;
                MacroUi.run (win, p.get_string ());
            });
            g.add_action (run);
        }
    }
}
