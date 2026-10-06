namespace Singularity.Apps.Spreadsheet {

    public enum ChangeKind {
        CELL,
        INSERT_ROWS,
        DELETE_ROWS,
        INSERT_COLS,
        DELETE_COLS,
        RENAME_SHEET,
        INSERT_SHEET,
        DELETE_SHEET;

        public string to_code () {
            switch (this) {
                case INSERT_ROWS: return "insert-rows";
                case DELETE_ROWS: return "delete-rows";
                case INSERT_COLS: return "insert-cols";
                case DELETE_COLS: return "delete-cols";
                case RENAME_SHEET: return "rename-sheet";
                case INSERT_SHEET: return "insert-sheet";
                case DELETE_SHEET: return "delete-sheet";
                default: return "cell";
            }
        }

        public static ChangeKind from_code (string code) {
            switch (code) {
                case "insert-rows": return INSERT_ROWS;
                case "delete-rows": return DELETE_ROWS;
                case "insert-cols": return INSERT_COLS;
                case "delete-cols": return DELETE_COLS;
                case "rename-sheet": return RENAME_SHEET;
                case "insert-sheet": return INSERT_SHEET;
                case "delete-sheet": return DELETE_SHEET;
                default: return CELL;
            }
        }
    }

    public enum ChangeState {
        PENDING,
        ACCEPTED,
        REJECTED
    }

    public class SavedCell {
        public int row;
        public int col;
        public string input;
        public int style;

        public SavedCell (int row, int col, string input, int style) {
            this.row = row;
            this.col = col;
            this.input = input;
            this.style = style;
        }
    }

    public class Change {
        public int id;
        public ChangeKind kind;
        public ChangeState state = ChangeState.PENDING;
        public Sheet? sheet;
        public string sheet_name = "";
        public int row;
        public int col;
        public int count = 1;
        public string old_input = "";
        public string new_input = "";
        public string author = "";
        public string date = "";
        public Gee.ArrayList<SavedCell> removed = new Gee.ArrayList<SavedCell> ();

        public Change (ChangeKind kind) {
            this.kind = kind;
            author = CommentStore.current_author ();
            date = CommentStore.now_iso ();
        }

        public Change copy () {
            var c = new Change (kind);
            c.id = id;
            c.state = state;
            c.sheet = sheet;
            c.sheet_name = sheet_name;
            c.row = row;
            c.col = col;
            c.count = count;
            c.old_input = old_input;
            c.new_input = new_input;
            c.author = author;
            c.date = date;
            c.removed.add_all (removed);
            return c;
        }

        public string where () {
            string s = Address.quote_sheet (sheet != null ? sheet.name : sheet_name);
            switch (kind) {
                case ChangeKind.CELL: return s + "!" + Address.cell (row, col);
                case ChangeKind.INSERT_ROWS:
                case ChangeKind.DELETE_ROWS:
                    return s + "!" + "%d:%d".printf (row + 1, row + count);
                case ChangeKind.INSERT_COLS:
                case ChangeKind.DELETE_COLS:
                    return s + "!" + Address.column_name (col) + ":" + Address.column_name (col + count - 1);
                default: return s;
            }
        }

        public static string shown (string input) {
            return input == "" ? _("blank") : "\"" + input + "\"";
        }

        public string describe () {
            switch (kind) {
                case ChangeKind.CELL:
                    return _("Changed cell %s from %s to %s").printf (Address.cell (row, col), shown (old_input), shown (new_input));
                case ChangeKind.INSERT_ROWS: return ngettext ("Inserted %d row at %d", "Inserted %d rows at %d", count).printf (count, row + 1);
                case ChangeKind.DELETE_ROWS: return ngettext ("Deleted %d row at %d", "Deleted %d rows at %d", count).printf (count, row + 1);
                case ChangeKind.INSERT_COLS: return ngettext ("Inserted %d column at %s", "Inserted %d columns at %s", count).printf (count, Address.column_name (col));
                case ChangeKind.DELETE_COLS: return ngettext ("Deleted %d column at %s", "Deleted %d columns at %s", count).printf (count, Address.column_name (col));
                case ChangeKind.RENAME_SHEET: return _("Renamed sheet %s to %s").printf (shown (old_input), shown (new_input));
                case ChangeKind.INSERT_SHEET: return _("Inserted sheet %s").printf (shown (new_input));
                default: return _("Deleted sheet %s").printf (shown (old_input));
            }
        }

        public DateTime? when () {
            return new DateTime.from_iso8601 (date, new TimeZone.local ());
        }
    }

    public class RevisionLog {
        public bool tracking;
        public Gee.ArrayList<Change> changes = new Gee.ArrayList<Change> ();
        public int next_id = 1;

        public void add (Change c) {
            c.id = next_id++;
            changes.add (c);
        }

        public Gee.ArrayList<Change> pending () {
            var l = new Gee.ArrayList<Change> ();
            foreach (var c in changes) if (c.state == ChangeState.PENDING) l.add (c);
            return l;
        }

        public Change? cell_change (Sheet s, int row, int col) {
            Change? found = null;
            foreach (var c in changes) {
                if (c.state == ChangeState.PENDING && c.kind == ChangeKind.CELL && c.sheet == s && c.row == row && c.col == col) found = c;
            }
            return found;
        }

        public bool has_pending_on (Sheet s) {
            foreach (var c in changes) if (c.state == ChangeState.PENDING && c.kind == ChangeKind.CELL && c.sheet == s) return true;
            return false;
        }

        public void shift (Sheet s, bool rows, int at, int count) {
            foreach (var c in changes) {
                if (c.sheet != s || c.kind != ChangeKind.CELL || c.state != ChangeState.PENDING) continue;
                int v = rows ? c.row : c.col;
                if (count < 0 && v >= at && v < at - count) {
                    c.state = ChangeState.ACCEPTED;
                    continue;
                }
                if (v >= at) v += count;
                if (rows) c.row = v;
                else c.col = v;
            }
        }
    }

    public class ChangeFilter {
        public int when_mode;
        public string since = "";
        public string who = "";
        public bool not_me;
        public Area? where;

        public bool matches (Change c, string me) {
            if (who != "" && c.author != who) return false;
            if (not_me && c.author == me) return false;
            if (when_mode == 1 && since != "" && c.date < since) return false;
            if (where != null) {
                if (c.sheet != where.sheet) return false;
                if (c.kind == ChangeKind.CELL && !where.contains (c.row, c.col)) return false;
            }
            return true;
        }
    }

    public class ReviewTracker : Object {
        private unowned Document doc;
        private Gee.ArrayList<Change> structural = new Gee.ArrayList<Change> ();
        private Gee.ArrayList<Change> suspended = new Gee.ArrayList<Change> ();
        public bool muted;
        public string? author_override;

        public static ReviewTracker attach (Document doc) {
            var t = doc.get_data<ReviewTracker> ("ss-review-tracker");
            if (t != null) return t;
            t = new ReviewTracker ();
            t.doc = doc;
            doc.set_data<ReviewTracker> ("ss-review-tracker", t);
            doc.committed.connect (t.on_committed);
            doc.restored.connect (t.on_restored);
            doc.book.rows_cols_changed.connect (t.on_rows_cols);
            return t;
        }

        public static ReviewTracker of (Document doc) {
            return attach (doc);
        }

        private RevisionLog log {
            get { return doc.book.revisions; }
        }

        private Change stamp (Change c) {
            if (author_override != null) c.author = author_override;
            return c;
        }

        private void on_rows_cols (Sheet s, bool rows, int at, int count) {
            log.shift (s, rows, at, count);
            if (!log.tracking || muted) return;
            ChangeKind k = rows ? (count > 0 ? ChangeKind.INSERT_ROWS : ChangeKind.DELETE_ROWS) : (count > 0 ? ChangeKind.INSERT_COLS : ChangeKind.DELETE_COLS);
            var c = stamp (new Change (k));
            c.sheet = s;
            c.sheet_name = s.name;
            c.count = count.abs ();
            if (rows) c.row = at;
            else c.col = at;
            structural.add (c);
        }

        private static Gee.HashMap<int64?, CellCopy> by_key (Gee.Collection<CellCopy> cells) {
            var m = new Gee.HashMap<int64?, CellCopy> (
                (k) => { int64 v = k; return (uint) (v ^ (v >> 32)); },
                (a, b) => { int64 x = a; int64 y = b; return x == y; });
            foreach (var c in cells) m[Sheet.key (c.row, c.col)] = c;
            return m;
        }

        private void diff_cells (Sheet s, Gee.Collection<CellCopy> before, Gee.Collection<CellCopy> after) {
            var b = by_key (before);
            var a = by_key (after);
            var keys = new Gee.TreeSet<int64?> ((x, y) => {
                int64 p = x;
                int64 q = y;
                return p < q ? -1 : (p > q ? 1 : 0);
            });
            foreach (var k in b.keys) keys.add (k);
            foreach (var k in a.keys) keys.add (k);
            foreach (var k in keys) {
                string oi = b.has_key (k) ? b[k].input : "";
                string ni = a.has_key (k) ? a[k].input : "";
                if (oi == ni) continue;
                var c = stamp (new Change (ChangeKind.CELL));
                c.sheet = s;
                c.sheet_name = s.name;
                c.row = Sheet.key_row (k);
                c.col = Sheet.key_col (k);
                c.old_input = oi;
                c.new_input = ni;
                log.add (c);
            }
        }

        private void on_committed (UndoStep step) {
            var ops = structural;
            structural = new Gee.ArrayList<Change> ();
            if (!log.tracking || muted) return;
            var before = step.before;
            if (before.order == null) {
                if (step.after != null && before.area != null && step.sheet != null) diff_cells (step.sheet, before.cells, step.after.cells);
                return;
            }
            var touched = new Gee.HashSet<Sheet> ();
            foreach (var op in ops) {
                touched.add (op.sheet);
                if (op.kind == ChangeKind.DELETE_ROWS || op.kind == ChangeKind.DELETE_COLS) {
                    foreach (var st in before.states) {
                        if (st.sheet != op.sheet) continue;
                        foreach (var cc in st.cells) {
                            int v = op.kind == ChangeKind.DELETE_ROWS ? cc.row : cc.col;
                            int start = op.kind == ChangeKind.DELETE_ROWS ? op.row : op.col;
                            if (v >= start && v < start + op.count && cc.input != "") op.removed.add (new SavedCell (cc.row, cc.col, cc.input, cc.style));
                        }
                    }
                }
                log.add (op);
            }
            foreach (var st in before.states) {
                var s = st.sheet;
                if (!doc.book.sheets.contains (s)) {
                    var c = stamp (new Change (ChangeKind.DELETE_SHEET));
                    c.sheet_name = st.name;
                    c.old_input = st.name;
                    log.add (c);
                    continue;
                }
                Change? inserted = null;
                foreach (var ic in log.changes) if (ic.kind == ChangeKind.INSERT_SHEET && ic.sheet == s && ic.state == ChangeState.PENDING) inserted = ic;
                if (s.name != st.name && inserted != null) {
                    inserted.new_input = s.name;
                    inserted.sheet_name = s.name;
                } else if (s.name != st.name) {
                    var c = stamp (new Change (ChangeKind.RENAME_SHEET));
                    c.sheet = s;
                    c.sheet_name = s.name;
                    c.old_input = st.name;
                    c.new_input = s.name;
                    log.add (c);
                }
                if (touched.contains (s)) continue;
                var now = new Gee.ArrayList<CellCopy> ();
                foreach (var cell in s.cells.values) now.add (new CellCopy.of (cell));
                diff_cells (s, st.cells, now);
            }
            foreach (var s in doc.book.sheets) {
                if (before.order.contains (s)) continue;
                var c = stamp (new Change (ChangeKind.INSERT_SHEET));
                c.sheet = s;
                c.sheet_name = s.name;
                c.new_input = s.name;
                log.add (c);
            }
        }

        private void on_restored (Sheet? sheet, Area? selection) {
            var back = new Gee.ArrayList<Change> ();
            foreach (var c in suspended) {
                if (c.sheet != null && doc.book.sheets.contains (c.sheet) && c.sheet.input_at (c.row, c.col) == c.new_input) back.add (c);
            }
            foreach (var c in back) {
                suspended.remove (c);
                c.state = ChangeState.PENDING;
            }
            foreach (var c in log.changes) {
                if (c.kind != ChangeKind.CELL || c.state != ChangeState.PENDING || c.sheet == null) continue;
                if (!doc.book.sheets.contains (c.sheet)) continue;
                string cur = c.sheet.input_at (c.row, c.col);
                if (cur == c.old_input && cur != c.new_input) {
                    c.state = ChangeState.REJECTED;
                    suspended.add (c);
                }
            }
        }

        public void accept (Change c) {
            if (c.state != ChangeState.PENDING) return;
            c.state = ChangeState.ACCEPTED;
            doc.modified = true;
            doc.changed ();
        }

        public bool can_reject (Change c) {
            if (c.state != ChangeState.PENDING) return false;
            if (c.kind == ChangeKind.DELETE_SHEET) return false;
            if (c.sheet == null || !doc.book.sheets.contains (c.sheet)) return false;
            return true;
        }

        public bool reject (Change c) {
            if (!can_reject (c)) return false;
            muted = true;
            var s = c.sheet;
            switch (c.kind) {
                case ChangeKind.CELL:
                    doc.set_input (s, c.row, c.col, c.old_input);
                    break;
                case ChangeKind.INSERT_ROWS:
                    doc.delete_rows (s, c.row, c.count);
                    break;
                case ChangeKind.INSERT_COLS:
                    doc.delete_cols (s, c.col, c.count);
                    break;
                case ChangeKind.DELETE_ROWS:
                case ChangeKind.DELETE_COLS:
                    if (c.kind == ChangeKind.DELETE_ROWS) doc.insert_rows (s, c.row, c.count);
                    else doc.insert_cols (s, c.col, c.count);
                    foreach (var sc in c.removed) doc.set_input (s, sc.row, sc.col, sc.input);
                    break;
                case ChangeKind.RENAME_SHEET:
                    doc.rename_sheet (s, c.old_input);
                    break;
                case ChangeKind.INSERT_SHEET:
                    doc.remove_sheet (s);
                    break;
                default:
                    break;
            }
            muted = false;
            c.state = ChangeState.REJECTED;
            doc.changed ();
            return true;
        }

        public int accept_all (ChangeFilter? f = null) {
            int n = 0;
            string me = CommentStore.current_author ();
            foreach (var c in log.pending ()) {
                if (f != null && !f.matches (c, me)) continue;
                c.state = ChangeState.ACCEPTED;
                n++;
            }
            if (n > 0) {
                doc.modified = true;
                doc.changed ();
            }
            return n;
        }

        public int reject_all (ChangeFilter? f = null) {
            int n = 0;
            string me = CommentStore.current_author ();
            var list = log.pending ();
            for (int i = list.size - 1; i >= 0; i--) {
                if (f != null && !f.matches (list[i], me)) continue;
                if (reject (list[i])) n++;
            }
            return n;
        }

        public void set_tracking (bool on) {
            if (log.tracking == on) return;
            log.tracking = on;
            doc.modified = true;
            doc.changed ();
        }

        public Sheet history_sheet () {
            muted = true;
            string name = _("History");
            var old = doc.book.find_sheet (name);
            if (old != null && doc.book.sheets.size > 1) doc.remove_sheet (old);
            var s = doc.add_sheet ();
            doc.rename_sheet (s, name);
            string[] head = { _("Action Number"), _("Date"), _("Time"), _("Who"), _("Change"), _("Sheet"), _("Range"), _("New Value"), _("Old Value"), _("Action Type") };
            doc.begin_area (_("History"), s, new Area (s, 0, 0, log.changes.size, head.length - 1));
            for (int i = 0; i < head.length; i++) s.set_input (0, i, head[i]);
            int r = 1;
            foreach (var c in log.changes) {
                var dt = c.when ();
                s.set_input (r, 0, c.id.to_string ());
                s.set_input (r, 1, dt != null ? dt.format ("%Y-%m-%d") : c.date);
                s.set_input (r, 2, dt != null ? dt.format ("%H:%M:%S") : "");
                s.set_input (r, 3, "'" + c.author);
                s.set_input (r, 4, "'" + c.describe ());
                s.set_input (r, 5, "'" + (c.sheet != null ? c.sheet.name : c.sheet_name));
                s.set_input (r, 6, "'" + c.where ());
                s.set_input (r, 7, c.new_input == "" ? "" : "'" + c.new_input);
                s.set_input (r, 8, c.old_input == "" ? "" : "'" + c.old_input);
                string st = c.state == ChangeState.ACCEPTED ? _("Accepted") : (c.state == ChangeState.REJECTED ? _("Rejected") : _("Pending"));
                s.set_input (r, 9, st);
                r++;
            }
            doc.commit ();
            muted = false;
            return s;
        }
    }
}
