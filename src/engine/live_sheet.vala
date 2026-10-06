namespace Singularity.Apps.Spreadsheet {

    public class LiveStamp {
        public int64 clock;
        public string peer;

        public LiveStamp (int64 clock, string peer) {
            this.clock = clock;
            this.peer = peer;
        }

        public bool newer_than (int64 c, string p) {
            return clock > c || (clock == c && strcmp (peer, p) > 0);
        }
    }

    public class LiveSheetSync : Object {
        public signal void outgoing (Json.Object message);
        public signal void applied (bool sheets);

        public unowned Document doc;
        public string peer;
        public int64 clock;
        public int base_sv;
        public Gee.ArrayList<Json.Object> structs = new Gee.ArrayList<Json.Object> ();
        public int conflicts_lost;
        private Gee.HashMap<string, LiveStamp> stamps = new Gee.HashMap<string, LiveStamp> ();
        private Gee.HashMap<string, int64?> remote_touch = new Gee.HashMap<string, int64?> ();
        private Gee.HashMap<UndoStep, int64?> step_clock = new Gee.HashMap<UndoStep, int64?> ();
        private Gee.ArrayList<Json.Object> local_structs = new Gee.ArrayList<Json.Object> ();
        private bool applying;
        private UndoStep? reverting_step;
        private bool reverting_redo;
        private Gee.ArrayList<CellCopy> protected_cells = new Gee.ArrayList<CellCopy> ();
        private ulong h_commit;
        private ulong h_revert;
        private ulong h_restored;

        public LiveSheetSync (Document doc, string peer) {
            this.doc = doc;
            this.peer = peer;
            h_commit = doc.committed.connect (on_committed);
            doc.book.rows_cols_changed.connect ((sh, rows, at, count) => {
                if (h_commit != 0) on_rows_cols (sh, rows, at, count);
            });
            h_revert = doc.reverting.connect (on_reverting);
            h_restored = doc.restored.connect (on_restored);
        }

        public void detach () {
            if (h_commit != 0) doc.disconnect (h_commit);
            if (h_revert != 0) doc.disconnect (h_revert);
            if (h_restored != 0) doc.disconnect (h_restored);
            h_commit = h_revert = h_restored = 0;
        }

        public int sv {
            get { return base_sv + structs.size; }
        }

        private static string key (string sheet, int r, int c) {
            return "%s\x1f%d\x1f%d".printf (sheet, r, c);
        }

        public static Json.Object style_json (CellStyle s) {
            var o = new Json.Object ();
            if (s.bold) o.set_boolean_member ("b", true);
            if (s.italic) o.set_boolean_member ("i", true);
            if (s.underline) o.set_boolean_member ("u", true);
            if (s.strike) o.set_boolean_member ("s", true);
            if (s.font_size != 11) o.set_double_member ("fs", s.font_size);
            if (s.font_family != "") o.set_string_member ("ff", s.font_family);
            if (s.color != "") o.set_string_member ("fg", s.color);
            if (s.fill != "") o.set_string_member ("bg", s.fill);
            if (s.halign != HAlign.GENERAL) o.set_int_member ("ha", (int) s.halign);
            if (s.valign != VAlign.BOTTOM) o.set_int_member ("va", (int) s.valign);
            if (s.wrap) o.set_boolean_member ("w", true);
            if (s.indent != 0) o.set_int_member ("in", s.indent);
            if (s.number_format != "General") o.set_string_member ("nf", s.number_format);
            string[] sides = { "bt", "bb", "bl", "br" };
            Border[] borders = { s.top, s.bottom, s.left, s.right };
            for (int i = 0; i < 4; i++) {
                if (borders[i].style != BorderStyle.NONE) o.set_string_member (sides[i], "%d/%s".printf ((int) borders[i].style, borders[i].color));
            }
            if (s.rotation != 0) o.set_int_member ("rot", s.rotation);
            if (s.shrink) o.set_boolean_member ("sh", true);
            if (!s.locked) o.set_boolean_member ("ul", true);
            if (s.hidden) o.set_boolean_member ("hf", true);
            return o;
        }

        private static Border border_of (Json.Object o, string k) {
            if (!o.has_member (k)) return new Border ();
            string[] p = o.get_string_member (k).split ("/", 2);
            return new Border ((BorderStyle) int.parse (p[0]), p.length > 1 ? p[1] : "");
        }

        public static CellStyle style_from (Json.Object o) {
            var s = new CellStyle ();
            s.bold = o.has_member ("b");
            s.italic = o.has_member ("i");
            s.underline = o.has_member ("u");
            s.strike = o.has_member ("s");
            if (o.has_member ("fs")) s.font_size = o.get_double_member ("fs");
            if (o.has_member ("ff")) s.font_family = o.get_string_member ("ff");
            if (o.has_member ("fg")) s.color = o.get_string_member ("fg");
            if (o.has_member ("bg")) s.fill = o.get_string_member ("bg");
            if (o.has_member ("ha")) s.halign = (HAlign) o.get_int_member ("ha");
            if (o.has_member ("va")) s.valign = (VAlign) o.get_int_member ("va");
            s.wrap = o.has_member ("w");
            if (o.has_member ("in")) s.indent = (int) o.get_int_member ("in");
            if (o.has_member ("nf")) s.number_format = o.get_string_member ("nf");
            s.top = border_of (o, "bt");
            s.bottom = border_of (o, "bb");
            s.left = border_of (o, "bl");
            s.right = border_of (o, "br");
            if (o.has_member ("rot")) s.rotation = (int) o.get_int_member ("rot");
            s.shrink = o.has_member ("sh");
            s.locked = !o.has_member ("ul");
            s.hidden = o.has_member ("hf");
            return s;
        }

        private Json.Object cell_op (Sheet s, int r, int c) {
            var o = new Json.Object ();
            o.set_string_member ("op", "cell");
            o.set_string_member ("sheet", s.name);
            o.set_int_member ("r", r);
            o.set_int_member ("c", c);
            var cell = s.get_cell (r, c);
            o.set_string_member ("in", cell != null ? cell.input : "");
            if (cell != null && cell.style != 0) o.set_object_member ("st", style_json (doc.book.styles[cell.style]));
            o.set_int_member ("k", ++clock);
            stamps[key (s.name, r, c)] = new LiveStamp (clock, peer);
            return o;
        }

        private Json.Object message (Json.Array ops, int sv_at) {
            var m = new Json.Object ();
            m.set_string_member ("t", "ops");
            m.set_int_member ("sv", sv_at);
            m.set_array_member ("ops", ops);
            return m;
        }

        private static string cell_sig (Workbook b, string input, int style) {
            return input + "\x1f" + b.styles[style].key ();
        }

        private void diff_sheet (Sheet s, Gee.Collection<CellCopy> before, Json.Array ops) {
            var old = new Gee.HashMap<string, string> ();
            foreach (var cc in before) old["%d:%d".printf (cc.row, cc.col)] = cell_sig (doc.book, cc.input, cc.style);
            var seen = new Gee.HashSet<string> ();
            foreach (var cell in s.cells.values) {
                string k = "%d:%d".printf (cell.row, cell.col);
                seen.add (k);
                string now = cell_sig (doc.book, cell.input, cell.style);
                if (old.has_key (k) && old[k] == now) continue;
                if (!old.has_key (k) && cell.input == "" && cell.style == 0) continue;
                ops.add_object_element (cell_op (s, cell.row, cell.col));
            }
            foreach (var cc in before) {
                string k = "%d:%d".printf (cc.row, cc.col);
                if (seen.contains (k)) continue;
                if (cc.input == "" && cc.style == 0) continue;
                ops.add_object_element (cell_op (s, cc.row, cc.col));
            }
        }

        private void diff_area (Sheet s, Area area, Gee.Collection<CellCopy> before, Json.Array ops) {
            var old = new Gee.HashMap<string, string> ();
            foreach (var cc in before) old["%d:%d".printf (cc.row, cc.col)] = cell_sig (doc.book, cc.input, cc.style);
            var seen = new Gee.HashSet<string> ();
            var now = new Gee.ArrayList<Cell> ();
            s.foreach_in (area, (r, c, cell) => now.add (cell));
            foreach (var cell in now) {
                string k = "%d:%d".printf (cell.row, cell.col);
                seen.add (k);
                string sig = cell_sig (doc.book, cell.input, cell.style);
                if (old.has_key (k) && old[k] == sig) continue;
                if (!old.has_key (k) && cell.input == "" && cell.style == 0) continue;
                ops.add_object_element (cell_op (s, cell.row, cell.col));
            }
            foreach (var cc in before) {
                string k = "%d:%d".printf (cc.row, cc.col);
                if (seen.contains (k) || (cc.input == "" && cc.style == 0)) continue;
                ops.add_object_element (cell_op (s, cc.row, cc.col));
            }
        }

        private Json.Object layout_op (Sheet s) {
            var o = new Json.Object ();
            o.set_string_member ("op", "layout");
            o.set_string_member ("sheet", s.name);
            var w = new Json.Object ();
            foreach (var e in s.col_widths.entries) w.set_int_member (e.key.to_string (), e.value);
            o.set_object_member ("cw", w);
            var h = new Json.Object ();
            foreach (var e in s.row_heights.entries) h.set_int_member (e.key.to_string (), e.value);
            o.set_object_member ("rh", h);
            var hr = new Json.Array ();
            foreach (int r in s.hidden_rows) hr.add_int_element (r);
            o.set_array_member ("hr", hr);
            var hc = new Json.Array ();
            foreach (int c in s.hidden_cols) hc.add_int_element (c);
            o.set_array_member ("hc", hc);
            var mg = new Json.Array ();
            foreach (var m in s.merges) mg.add_string_element ("%d,%d,%d,%d".printf (m.r1, m.c1, m.r2, m.c2));
            o.set_array_member ("mg", mg);
            o.set_int_member ("fr", s.freeze_rows);
            o.set_int_member ("fc", s.freeze_cols);
            o.set_int_member ("k", ++clock);
            stamps[key (s.name, -1, -1)] = new LiveStamp (clock, peer);
            return o;
        }

        private static string layout_sig (SheetState st) {
            var sb = new StringBuilder ();
            var cw = new Gee.TreeMap<int, int> ();
            foreach (var e in st.col_widths.entries) cw[e.key] = e.value;
            foreach (var e in cw.entries) sb.append ("%d=%d,".printf (e.key, e.value));
            sb.append ("|");
            var rh = new Gee.TreeMap<int, int> ();
            foreach (var e in st.row_heights.entries) rh[e.key] = e.value;
            foreach (var e in rh.entries) sb.append ("%d=%d,".printf (e.key, e.value));
            sb.append ("|%d|%d|%d|%d|%d".printf (st.hidden_rows.size, st.hidden_cols.size, st.merges.size, st.freeze_rows, st.freeze_cols));
            foreach (var m in st.merges) sb.append ("%d,%d,%d,%d;".printf (m.r1, m.c1, m.r2, m.c2));
            return sb.str;
        }

        private void on_rows_cols (Sheet s, bool rows, int at, int count) {
            if (applying) return;
            var o = new Json.Object ();
            o.set_string_member ("op", rows ? "rows" : "cols");
            o.set_string_member ("sheet", s.name);
            o.set_int_member ("at", at);
            o.set_int_member ("n", count);
            o.set_int_member ("k", ++clock);
            o.set_string_member ("from", peer);
            shift_stamps (s.name, rows, at, count);
            local_structs.add (o);
        }

        private void on_committed (UndoStep step) {
            if (applying) return;
            int sv_at = sv;
            var ops = new Json.Array ();
            foreach (var st in local_structs) {
                ops.add_object_element (st);
                structs.add (st);
            }
            local_structs.clear ();
            var before = step.before;
            if (before.order == null) {
                if (step.sheet != null && before.area != null) diff_area (step.sheet, before.area, before.cells, ops);
            } else {
                foreach (var st in before.states) {
                    if (!doc.book.sheets.contains (st.sheet)) {
                        var o = new Json.Object ();
                        o.set_string_member ("op", "del-sheet");
                        o.set_string_member ("sheet", st.name);
                        ops.add_object_element (o);
                    } else if (st.sheet.name != st.name) {
                        var o = new Json.Object ();
                        o.set_string_member ("op", "rename-sheet");
                        o.set_string_member ("sheet", st.name);
                        o.set_string_member ("to", st.sheet.name);
                        ops.add_object_element (o);
                    }
                }
                foreach (var s in doc.book.sheets) {
                    if (before.order.contains (s)) continue;
                    var o = new Json.Object ();
                    o.set_string_member ("op", "add-sheet");
                    o.set_string_member ("sheet", s.name);
                    o.set_int_member ("at", doc.book.sheets.index_of (s));
                    ops.add_object_element (o);
                }
                var structured = new Gee.HashSet<string> ();
                for (int i = 0; i < ops.get_length (); i++) {
                    var o = ops.get_object_element (i);
                    string op = o.get_string_member ("op");
                    if (op == "rows" || op == "cols") structured.add (o.get_string_member ("sheet"));
                }
                foreach (var st in before.states) {
                    var s = st.sheet;
                    if (!doc.book.sheets.contains (s)) continue;
                    if (!structured.contains (s.name)) diff_sheet (s, st.cells, ops);
                    var now = new SheetState (s);
                    if (layout_sig (now) != layout_sig (st)) ops.add_object_element (layout_op (s));
                }
                foreach (var s in doc.book.sheets) {
                    if (before.order.contains (s)) continue;
                    foreach (var cell in s.cells.values) ops.add_object_element (cell_op (s, cell.row, cell.col));
                }
            }
            step_clock[step] = clock;
            if (ops.get_length () > 0) outgoing (message (ops, sv_at));
        }

        private void on_reverting (UndoStep step, bool redo) {
            if (applying) return;
            reverting_step = step;
            reverting_redo = redo;
            protected_cells.clear ();
            int64 at = step_clock.has_key (step) ? step_clock[step] : int64.MAX;
            if (step.before.order != null || step.sheet == null || step.before.area == null) return;
            var s = step.sheet;
            var a = step.before.area;
            foreach (var e in remote_touch.entries) {
                if (e.value <= at) continue;
                string[] p = e.key.split ("\x1f");
                if (p.length != 3 || p[0] != s.name) continue;
                int r = int.parse (p[1]), c = int.parse (p[2]);
                if (!a.contains (r, c)) continue;
                var cell = s.get_cell (r, c);
                var cc = cell != null ? new CellCopy.of (cell) : null;
                if (cc == null) {
                    cc = new CellCopy.of (new Cell ());
                    cc.row = r;
                    cc.col = c;
                }
                protected_cells.add (cc);
            }
        }

        private void on_restored (Sheet? sheet, Area? selection) {
            if (applying || reverting_step == null) return;
            var step = reverting_step;
            reverting_step = null;
            var ops = new Json.Array ();
            if (step.before.order == null && step.sheet != null && step.before.area != null) {
                var s = step.sheet;
                foreach (var cc in protected_cells) {
                    s.set_input (cc.row, cc.col, cc.input);
                    s.set_style (cc.row, cc.col, cc.style);
                }
                if (protected_cells.size > 0) {
                    doc.book.structure_changed = true;
                    doc.book.recalc_changed ();
                }
                var keys = new Gee.HashSet<string> ();
                foreach (var cc in step.before.cells) keys.add ("%d:%d".printf (cc.row, cc.col));
                if (step.after != null) foreach (var cc in step.after.cells) keys.add ("%d:%d".printf (cc.row, cc.col));
                foreach (var cc in protected_cells) keys.remove ("%d:%d".printf (cc.row, cc.col));
                foreach (string k in keys) {
                    string[] p = k.split (":");
                    ops.add_object_element (cell_op (s, int.parse (p[0]), int.parse (p[1])));
                }
            } else {
                var names = new Json.Array ();
                foreach (var s in doc.book.sheets) names.add_string_element (s.name);
                var so = new Json.Object ();
                so.set_string_member ("op", "sheets");
                so.set_array_member ("names", names);
                ops.add_object_element (so);
                foreach (var s in doc.book.sheets) ops.add_object_element (reset_op (s));
            }
            protected_cells.clear ();
            if (ops.get_length () > 0) outgoing (message (ops, sv));
        }

        private Json.Object reset_op (Sheet s) {
            var o = new Json.Object ();
            o.set_string_member ("op", "reset");
            o.set_string_member ("sheet", s.name);
            var cells = new Json.Array ();
            foreach (var cell in s.cells.values) {
                if (cell.input == "" && cell.style == 0) continue;
                var c = new Json.Object ();
                c.set_int_member ("r", cell.row);
                c.set_int_member ("c", cell.col);
                c.set_string_member ("in", cell.input);
                if (cell.style != 0) c.set_object_member ("st", style_json (doc.book.styles[cell.style]));
                cells.add_object_element (c);
            }
            o.set_array_member ("cells", cells);
            o.set_object_member ("layout", layout_op (s));
            o.set_int_member ("k", clock);
            return o;
        }

        private void shift_stamps (string sheet, bool rows, int at, int count) {
            var moved = new Gee.HashMap<string, LiveStamp> ();
            var moved_touch = new Gee.HashMap<string, int64?> ();
            foreach (var e in stamps.entries) {
                string[] p = e.key.split ("\x1f");
                if (p.length != 3 || p[0] != sheet || p[1] == "-1") {
                    moved[e.key] = e.value;
                    continue;
                }
                int r = int.parse (p[1]), c = int.parse (p[2]);
                if (!shift_point (rows, at, count, ref r, ref c)) continue;
                moved[key (sheet, r, c)] = e.value;
            }
            foreach (var e in remote_touch.entries) {
                string[] p = e.key.split ("\x1f");
                if (p.length != 3 || p[0] != sheet) {
                    moved_touch[e.key] = e.value;
                    continue;
                }
                int r = int.parse (p[1]), c = int.parse (p[2]);
                if (!shift_point (rows, at, count, ref r, ref c)) continue;
                moved_touch[key (sheet, r, c)] = e.value;
            }
            stamps = moved;
            remote_touch = moved_touch;
        }

        public static bool shift_point (bool rows, int at, int count, ref int r, ref int c) {
            int v = rows ? r : c;
            if (count < 0 && v >= at && v < at - count) return false;
            if (v >= at) v += count;
            if (rows) r = v;
            else c = v;
            return true;
        }

        private void rekey_sheet (string from, string to) {
            var moved = new Gee.HashMap<string, LiveStamp> ();
            foreach (var e in stamps.entries) {
                if (e.key.has_prefix (from + "\x1f")) moved[to + e.key.substring (from.length)] = e.value;
                else moved[e.key] = e.value;
            }
            stamps = moved;
            foreach (var s in structs) if (s.get_string_member ("sheet") == from) s.set_string_member ("sheet", to);
        }

        private bool transform (Json.Object op, Gee.List<Json.Object> missed) {
            string op_kind = op.get_string_member ("op");
            if (!op.has_member ("sheet")) return true;
            string sheet = op.get_string_member ("sheet");
            foreach (var m in missed) {
                if (m.get_string_member ("sheet") != sheet) continue;
                bool rows = m.get_string_member ("op") == "rows";
                int at = (int) m.get_int_member ("at");
                int n = (int) m.get_int_member ("n");
                if (op_kind == "cell") {
                    int r = (int) op.get_int_member ("r"), c = (int) op.get_int_member ("c");
                    if (!shift_point (rows, at, n, ref r, ref c)) return false;
                    op.set_int_member ("r", r);
                    op.set_int_member ("c", c);
                } else if (op_kind == "rows" || op_kind == "cols") {
                    if ((op_kind == "rows") != rows) continue;
                    int oat = (int) op.get_int_member ("at");
                    if (n > 0 && oat >= at) oat += n;
                    else if (n < 0 && oat >= at - n) oat += n;
                    else if (n < 0 && oat >= at) oat = at;
                    op.set_int_member ("at", oat);
                }
            }
            return true;
        }

        private void apply_cell (Sheet s, int r, int c, string input, Json.Object? st) {
            var cur = s.get_cell (r, c);
            if (cur == null || cur.input != input) s.set_input (r, c, input);
            int style = st != null ? doc.book.intern (style_from (st)) : 0;
            s.set_style (r, c, style);
            if (input == "") s.drop_if_blank (r, c);
        }

        private void apply_layout (Sheet s, Json.Object o) {
            s.col_widths.clear ();
            var cw = o.get_object_member ("cw");
            foreach (string k in cw.get_members ()) s.col_widths[int.parse (k)] = (int) cw.get_int_member (k);
            s.row_heights.clear ();
            var rh = o.get_object_member ("rh");
            foreach (string k in rh.get_members ()) s.row_heights[int.parse (k)] = (int) rh.get_int_member (k);
            s.hidden_rows.clear ();
            foreach (var n in o.get_array_member ("hr").get_elements ()) s.hidden_rows.add ((int) n.get_int ());
            s.hidden_cols.clear ();
            foreach (var n in o.get_array_member ("hc").get_elements ()) s.hidden_cols.add ((int) n.get_int ());
            s.merges.clear ();
            foreach (var n in o.get_array_member ("mg").get_elements ()) {
                string[] p = n.get_string ().split (",");
                if (p.length == 4) s.merges.add (new Area (s, int.parse (p[0]), int.parse (p[1]), int.parse (p[2]), int.parse (p[3])));
            }
            s.freeze_rows = (int) o.get_int_member ("fr");
            s.freeze_cols = (int) o.get_int_member ("fc");
        }

        public void receive (Json.Object m) {
            if (!m.has_member ("ops")) return;
            string from = m.has_member ("peer") ? m.get_string_member ("peer") : "";
            int msv = m.has_member ("sv") ? (int) m.get_int_member ("sv") : sv;
            var missed = new Gee.ArrayList<Json.Object> ();
            for (int i = int.max (0, msv - base_sv); i < structs.size; i++) {
                var s = structs[i];
                if (s.has_member ("from") && s.get_string_member ("from") == from) continue;
                missed.add (s);
            }
            bool sheets = false;
            bool any = false;
            applying = true;
            var book = doc.book;
            foreach (var node in m.get_array_member ("ops").get_elements ()) {
                var op = node.get_object ();
                if (op.has_member ("k")) clock = int64.max (clock, op.get_int_member ("k"));
                string kind = op.get_string_member ("op");
                if (!transform (op, missed)) {
                    conflicts_lost++;
                    continue;
                }
                string sname = op.has_member ("sheet") ? op.get_string_member ("sheet") : "";
                var s = sname != "" ? book.find_sheet (sname) : null;
                int64 k = op.has_member ("k") ? op.get_int_member ("k") : clock;
                switch (kind) {
                    case "cell":
                        if (s == null) break;
                        int r = (int) op.get_int_member ("r"), c = (int) op.get_int_member ("c");
                        string ck = key (sname, r, c);
                        var stamp = stamps[ck];
                        if (stamp != null && stamp.newer_than (k, from)) {
                            conflicts_lost++;
                            break;
                        }
                        stamps[ck] = new LiveStamp (k, from);
                        remote_touch[ck] = clock;
                        apply_cell (s, r, c, op.get_string_member ("in"), op.has_member ("st") ? op.get_object_member ("st") : null);
                        any = true;
                        break;
                    case "rows":
                    case "cols":
                        if (s == null) break;
                        int at = (int) op.get_int_member ("at");
                        int n = (int) op.get_int_member ("n");
                        bool rows = kind == "rows";
                        if (rows) {
                            if (n > 0) book.insert_rows (s, at, n);
                            else book.delete_rows (s, at, -n);
                        } else {
                            if (n > 0) book.insert_cols (s, at, n);
                            else book.delete_cols (s, at, -n);
                        }
                        shift_stamps (sname, rows, at, n);
                        if (!op.has_member ("from")) op.set_string_member ("from", from);
                        structs.add (op);
                        any = true;
                        break;
                    case "layout":
                        if (s == null) break;
                        string lk = key (sname, -1, -1);
                        var ls = stamps[lk];
                        if (ls != null && ls.newer_than (k, from)) break;
                        stamps[lk] = new LiveStamp (k, from);
                        apply_layout (s, op);
                        any = true;
                        break;
                    case "add-sheet":
                        if (s != null) break;
                        book.add_sheet (sname, (int) op.get_int_member ("at"));
                        sheets = true;
                        break;
                    case "del-sheet":
                        if (s == null || book.sheets.size <= 1) break;
                        book.remove_sheet (s);
                        sheets = true;
                        break;
                    case "rename-sheet":
                        if (s == null) break;
                        string to = op.get_string_member ("to");
                        if (book.find_sheet (to) != null) break;
                        book.rename_sheet (s, to);
                        rekey_sheet (sname, to);
                        sheets = true;
                        break;
                    case "sheets":
                        var names = new Gee.ArrayList<string> ();
                        foreach (var nn in op.get_array_member ("names").get_elements ()) names.add (nn.get_string ());
                        foreach (var ex in book.sheets.to_array ()) if (!names.contains (ex.name) && book.sheets.size > 1) book.remove_sheet (ex);
                        for (int i = 0; i < names.size; i++) {
                            var ex = book.find_sheet (names[i]);
                            if (ex == null) ex = book.add_sheet (names[i], i);
                            else if (book.sheets.index_of (ex) != i && i < book.sheets.size) {
                                book.sheets.remove (ex);
                                book.sheets.insert (i, ex);
                            }
                        }
                        sheets = true;
                        break;
                    case "reset":
                        if (s == null) break;
                        s.cells.clear ();
                        s.spills.clear ();
                        foreach (var cn in op.get_array_member ("cells").get_elements ()) {
                            var co = cn.get_object ();
                            int rr = (int) co.get_int_member ("r"), cc2 = (int) co.get_int_member ("c");
                            apply_cell (s, rr, cc2, co.get_string_member ("in"), co.has_member ("st") ? co.get_object_member ("st") : null);
                            stamps[key (sname, rr, cc2)] = new LiveStamp (k, from);
                            remote_touch[key (sname, rr, cc2)] = clock;
                        }
                        apply_layout (s, op.get_object_member ("layout"));
                        s.recompute_extent ();
                        any = true;
                        break;
                }
            }
            applying = false;
            if (any || sheets) {
                book.structure_changed = true;
                book.recalc_changed ();
                doc.modified = true;
                applied (sheets);
            }
        }

        public Json.Object snapshot () throws Error {
            string path = Path.build_filename (Environment.get_tmp_dir (), "ss-live-%s.xlsx".printf (Uuid.string_random ()));
            XlsxWriter.save (doc.book, path);
            uint8[] data;
            FileUtils.get_data (path, out data);
            FileUtils.remove (path);
            var o = new Json.Object ();
            o.set_string_member ("xlsx", Base64.encode (data));
            o.set_int_member ("clock", clock);
            o.set_int_member ("sv", sv);
            return o;
        }

        public static Workbook book_from (Json.Object state, out int64 clock, out int sv) throws Error {
            clock = state.has_member ("clock") ? state.get_int_member ("clock") : 0;
            sv = state.has_member ("sv") ? (int) state.get_int_member ("sv") : 0;
            var data = Base64.decode (state.get_string_member ("xlsx"));
            return new Xlsx ().read (data);
        }
    }
}
