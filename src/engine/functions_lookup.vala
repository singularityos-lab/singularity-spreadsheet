namespace Singularity.Apps.Spreadsheet {

    public class LookupFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Lookup", syntax, summary, (owned) impl);
        }

        private static Value[] vector (Value[,] m) {
            int r = m.length[0], c = m.length[1];
            Value[] out_v = new Value[r * c];
            if (r == 1) {
                for (int j = 0; j < c; j++) out_v[j] = m[0, j];
            } else {
                for (int i = 0; i < r; i++) for (int j = 0; j < c; j++) out_v[i * c + j] = m[i, j];
            }
            return out_v;
        }

        private static bool loose_equal (Value a, Value b) {
            if (a.kind == ValueKind.TEXT && b.kind == ValueKind.TEXT) return a.text.casefold () == b.text.casefold ();
            if (a.kind != b.kind) return false;
            return Evaluator.compare (a, b) == 0;
        }

        public static int match (Value needle, Value[] hay, int type, bool wildcards = true) {
            if (type == 0) {
                if (wildcards && needle.kind == ValueKind.TEXT && (needle.text.contains ("*") || needle.text.contains ("?") || needle.text.contains ("~"))) {
                    var c = new Criteria (Value.str ("=" + needle.text));
                    for (int i = 0; i < hay.length; i++) if (c.matches (hay[i])) return i;
                    return -1;
                }
                for (int i = 0; i < hay.length; i++) if (loose_equal (hay[i], needle)) return i;
                return -1;
            }
            int lo = 0, hi = hay.length - 1, found = -1;
            while (lo <= hi) {
                int mid = (lo + hi) / 2;
                var v = hay[mid];
                if (v.kind == ValueKind.EMPTY) {
                    hi = mid - 1;
                    continue;
                }
                int cmp = Evaluator.compare (v, needle);
                bool comparable = (v.kind == ValueKind.TEXT) == (needle.kind == ValueKind.TEXT);
                if (type > 0) {
                    if (cmp <= 0) {
                        if (comparable) found = mid;
                        lo = mid + 1;
                    } else {
                        hi = mid - 1;
                    }
                } else {
                    if (cmp >= 0) {
                        if (comparable) found = mid;
                        lo = mid + 1;
                    } else {
                        hi = mid - 1;
                    }
                }
            }
            return found;
        }

        public static void register () {
            add ("VLOOKUP", 3, 4, "VLOOKUP(value, table, column, [approximate])", _("Looks down the first column of a table"), (ev, a) => table_lookup (ev, a, true));
            add ("HLOOKUP", 3, 4, "HLOOKUP(value, table, row, [approximate])", _("Looks across the first row of a table"), (ev, a) => table_lookup (ev, a, false));
            add ("MATCH", 2, 3, "MATCH(value, range, [type])", _("The position of a value in a range"), (ev, a) => {
                int type = 1;
                Value? e = null;
                if (a.length > 2 && (e = ev.arg_int (a[2], out type)) != null) return e;
                var m = ev.to_matrix (ev.eval (a[1]));
                if (m.length[0] > 1 && m.length[1] > 1) return Value.err (ErrorKind.NA);
                var hay = vector (m);
                return ev.map1 (ev.eval (a[0]), (needle) => {
                    if (needle.is_error ()) return needle;
                    int i = match (needle, hay, type.clamp (-1, 1));
                    return i < 0 ? Value.err (ErrorKind.NA) : Value.num (i + 1);
                });
            });
            add ("XMATCH", 2, 4, "XMATCH(value, range, [match_mode], [search_mode])", _("The position of a value, searching in any direction"), (ev, a) => {
                int mode = 0, search = 1;
                Value? e = null;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING && (e = ev.arg_int (a[2], out mode)) != null) return e;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_int (a[3], out search)) != null) return e;
                var hay = vector (ev.to_matrix (ev.eval (a[1])));
                return ev.map1 (ev.eval (a[0]), (needle) => {
                    if (needle.is_error ()) return needle;
                    int i = xmatch (needle, hay, mode, search);
                    return i < 0 ? Value.err (ErrorKind.NA) : Value.num (i + 1);
                });
            });
            add ("XLOOKUP", 3, 6, "XLOOKUP(value, lookup_array, return_array, [if_not_found], [match_mode], [search_mode])", _("Finds a value and returns the matching item"), (ev, a) => {
                var nv = ev.eval (a[0]);
                if (nv.is_multi ()) {
                    return ev.map1 (nv, (x) => {
                        var inner = new Node (NodeKind.VALUE);
                        inner.value = x;
                        Node[] args = { inner };
                        for (int k = 1; k < a.length; k++) args += a[k];
                        var r = Functions.all ()["XLOOKUP"].impl (ev, args);
                        if (r.kind == ValueKind.ARRAY) return r.array[0, 0];
                        if (r.kind == ValueKind.RANGE) return ev.cell (r.area.sheet, r.area.r1, r.area.c1);
                        return r;
                    });
                }
                var needle = ev.deref (nv);
                if (needle.is_error ()) return needle;
                int mode = 0, search = 1;
                Value? e = null;
                if (a.length > 4 && a[4].kind != NodeKind.MISSING && (e = ev.arg_int (a[4], out mode)) != null) return e;
                if (a.length > 5 && a[5].kind != NodeKind.MISSING && (e = ev.arg_int (a[5], out search)) != null) return e;
                var lm = ev.to_matrix (ev.eval (a[1]));
                var rv = ev.eval (a[2]);
                var rm = ev.to_matrix (rv);
                bool vertical = lm.length[1] == 1;
                int i = xmatch (needle, vector (lm), mode, search);
                if (i < 0) {
                    if (a.length > 3 && a[3].kind != NodeKind.MISSING) return ev.eval (a[3]);
                    return Value.err (ErrorKind.NA);
                }
                if (vertical) {
                    if (i >= rm.length[0]) return Value.err (ErrorKind.VALUE);
                    if (rm.length[1] == 1) return rm[i, 0];
                    var row = new Value[1, rm.length[1]];
                    for (int j = 0; j < rm.length[1]; j++) row[0, j] = rm[i, j];
                    return Value.matrix (row);
                }
                if (i >= rm.length[1]) return Value.err (ErrorKind.VALUE);
                if (rm.length[0] == 1) return rm[0, i];
                var colv = new Value[rm.length[0], 1];
                for (int j = 0; j < rm.length[0]; j++) colv[j, 0] = rm[j, i];
                return Value.matrix (colv);
            });
            add ("LOOKUP", 2, 3, "LOOKUP(value, lookup_vector, [result_vector])", _("Finds a value in a sorted vector"), (ev, a) => {
                var needle = ev.arg (a[0]);
                if (needle.is_error ()) return needle;
                var lm = ev.to_matrix (ev.eval (a[1]));
                Value[] hay;
                Value[] res;
                if (a.length > 2) {
                    hay = vector (lm);
                    res = vector (ev.to_matrix (ev.eval (a[2])));
                } else if (lm.length[0] >= lm.length[1]) {
                    hay = new Value[lm.length[0]];
                    res = new Value[lm.length[0]];
                    for (int i = 0; i < lm.length[0]; i++) {
                        hay[i] = lm[i, 0];
                        res[i] = lm[i, lm.length[1] - 1];
                    }
                } else {
                    hay = new Value[lm.length[1]];
                    res = new Value[lm.length[1]];
                    for (int j = 0; j < lm.length[1]; j++) {
                        hay[j] = lm[0, j];
                        res[j] = lm[lm.length[0] - 1, j];
                    }
                }
                int i = match (needle, hay, 1);
                if (i < 0 || i >= res.length) return Value.err (ErrorKind.NA);
                return res[i];
            });
            add ("INDEX", 2, 4, "INDEX(range, row, [column], [area])", _("The value at a position in a range"), (ev, a) => {
                var v = ev.eval (a[0]);
                int r = 0, c = 0;
                Value? e = null;
                if (a[1].kind != NodeKind.MISSING && (e = ev.arg_int (a[1], out r)) != null) return e;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING && (e = ev.arg_int (a[2], out c)) != null) return e;
                if (r < 0 || c < 0) return Value.err (ErrorKind.VALUE);
                if (v.kind == ValueKind.RANGE) {
                    var ar = v.area;
                    if (a.length == 2 && ar.rows == 1) {
                        c = r;
                        r = 1;
                    }
                    if (r > ar.rows || c > ar.cols) return Value.err (ErrorKind.REF);
                    int r1 = r == 0 ? ar.r1 : ar.r1 + r - 1;
                    int r2 = r == 0 ? ar.r2 : r1;
                    int c1 = c == 0 ? ar.c1 : ar.c1 + c - 1;
                    int c2 = c == 0 ? ar.c2 : c1;
                    if (ar.cols == 1 && c == 0) {
                        c1 = c2 = ar.c1;
                    }
                    return Value.range (new Area (ar.sheet, r1, c1, r2, c2));
                }
                var m = ev.to_matrix (v);
                if (a.length == 2 && m.length[0] == 1) {
                    c = r;
                    r = 1;
                }
                if (m.length[1] == 1 && c == 0) c = 1;
                if (m.length[0] == 1 && r == 0) r = 1;
                if (r > m.length[0] || c > m.length[1]) return Value.err (ErrorKind.REF);
                if (r == 0 || c == 0) {
                    int rr = r == 0 ? m.length[0] : 1, cc = c == 0 ? m.length[1] : 1;
                    var part = new Value[rr, cc];
                    for (int i = 0; i < rr; i++) for (int j = 0; j < cc; j++) part[i, j] = m[r == 0 ? i : r - 1, c == 0 ? j : c - 1];
                    return Value.matrix (part);
                }
                return m[r - 1, c - 1];
            });
            add ("CHOOSE", 2, -1, "CHOOSE(index, value1, value2, ...)", _("A value from a list by position"), (ev, a) => {
                int i;
                var e = ev.arg_int (a[0], out i);
                if (e != null) return e;
                if (i < 1 || i >= a.length) return Value.err (ErrorKind.VALUE);
                return ev.eval (a[i]);
            });
            add ("ROW", 0, 1, "ROW([reference])", _("The row number of a reference"), (ev, a) => {
                if (a.length == 0) return Value.num (ev.row + 1);
                var v = ev.eval (a[0]);
                if (v.kind != ValueKind.RANGE) return Value.err (ErrorKind.VALUE);
                if (v.area.rows == 1 || v.area.rows > 1048575) return Value.num (v.area.r1 + 1);
                var m = new Value[v.area.rows, 1];
                for (int i = 0; i < v.area.rows; i++) m[i, 0] = Value.num (v.area.r1 + i + 1);
                return Value.matrix (m);
            });
            add ("COLUMN", 0, 1, "COLUMN([reference])", _("The column number of a reference"), (ev, a) => {
                if (a.length == 0) return Value.num (ev.col + 1);
                var v = ev.eval (a[0]);
                if (v.kind != ValueKind.RANGE) return Value.err (ErrorKind.VALUE);
                if (v.area.cols == 1 || v.area.cols >= MAX_COLS) return Value.num (v.area.c1 + 1);
                var m = new Value[1, v.area.cols];
                for (int j = 0; j < v.area.cols; j++) m[0, j] = Value.num (v.area.c1 + j + 1);
                return Value.matrix (m);
            });
            add ("ROWS", 1, 1, "ROWS(range)", _("The number of rows"), (ev, a) => {
                var v = ev.eval (a[0]);
                if (v.kind == ValueKind.RANGE) return Value.num (v.area.rows);
                if (v.kind == ValueKind.ARRAY) return Value.num (v.array.length[0]);
                return v.is_error () ? v : Value.num (1);
            });
            add ("COLUMNS", 1, 1, "COLUMNS(range)", _("The number of columns"), (ev, a) => {
                var v = ev.eval (a[0]);
                if (v.kind == ValueKind.RANGE) return Value.num (v.area.cols);
                if (v.kind == ValueKind.ARRAY) return Value.num (v.array.length[1]);
                return v.is_error () ? v : Value.num (1);
            });
            add ("AREAS", 1, 1, "AREAS(reference)", _("The number of areas"), (ev, a) => Value.num (1));
            add ("ADDRESS", 2, 5, "ADDRESS(row, column, [abs], [a1], [sheet])", _("A cell address as text"), (ev, a) => {
                int r, c, abs = 1;
                var e = ev.arg_int (a[0], out r);
                if (e != null) return e;
                if ((e = ev.arg_int (a[1], out c)) != null) return e;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING && (e = ev.arg_int (a[2], out abs)) != null) return e;
                bool a1 = true;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_bool (a[3], out a1)) != null) return e;
                if (r < 1 || c < 1 || r > MAX_ROWS || c > MAX_COLS || abs < 1 || abs > 4) return Value.err (ErrorKind.VALUE);
                string t;
                if (a1) {
                    t = Address.cell (r - 1, c - 1, abs == 1 || abs == 2, abs == 1 || abs == 3);
                } else {
                    t = "R" + ((abs == 1 || abs == 2) ? r.to_string () : "[" + r.to_string () + "]") + "C" + ((abs == 1 || abs == 3) ? c.to_string () : "[" + c.to_string () + "]");
                }
                if (a.length > 4) {
                    Value? se = null;
                    string sheet = ev.arg_text (a[4], out se);
                    if (se != null) return se;
                    t = Address.quote_sheet (sheet) + "!" + t;
                }
                return Value.str (t);
            });
            add ("OFFSET", 3, 5, "OFFSET(reference, rows, cols, [height], [width])", _("A reference shifted from a starting point"), (ev, a) => {
                var v = ev.eval (a[0]);
                if (v.kind != ValueKind.RANGE) return Value.err (ErrorKind.VALUE);
                int dr, dc, h = v.area.rows, w = v.area.cols;
                var e = ev.arg_int (a[1], out dr);
                if (e != null) return e;
                if ((e = ev.arg_int (a[2], out dc)) != null) return e;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_int (a[3], out h)) != null) return e;
                if (a.length > 4 && a[4].kind != NodeKind.MISSING && (e = ev.arg_int (a[4], out w)) != null) return e;
                int r1 = v.area.r1 + dr, c1 = v.area.c1 + dc;
                if (h == 0 || w == 0) return Value.err (ErrorKind.REF);
                int r2 = r1 + h + (h > 0 ? -1 : 1), c2 = c1 + w + (w > 0 ? -1 : 1);
                if (int.min (r1, r2) < 0 || int.min (c1, c2) < 0 || int.max (r1, r2) >= MAX_ROWS || int.max (c1, c2) >= MAX_COLS) return Value.err (ErrorKind.REF);
                return Value.range (new Area (v.area.sheet, r1, c1, r2, c2));
            });
            add ("INDIRECT", 1, 2, "INDIRECT(text, [a1])", _("A reference from its text"), (ev, a) => {
                Value? e = null;
                string t = ev.arg_text (a[0], out e);
                if (e != null) return e;
                Sheet? s = null;
                int bang = t.last_index_of ("!");
                string r = t;
                if (bang > 0) {
                    string name = t.substring (0, bang);
                    if (name.has_prefix ("'") && name.has_suffix ("'")) name = name.substring (1, name.length - 2).replace ("''", "'");
                    s = ev.book.find_sheet (name);
                    if (s == null) return Value.err (ErrorKind.REF);
                    r = t.substring (bang + 1);
                }
                var area = Area.parse (r.replace ("$", ""), s);
                if (area == null) {
                    foreach (var entry in ev.book.names.entries) {
                        if (entry.key.casefold () == t.casefold ()) {
                            try {
                                return ev.eval (Formula.parse (entry.value, ev.book, ev.sheet));
                            } catch (FormulaError fe) {
                                return Value.err (ErrorKind.REF);
                            }
                        }
                    }
                    return Value.err (ErrorKind.REF);
                }
                return Value.range (area);
            });
            add ("TRANSPOSE", 1, 1, "TRANSPOSE(array)", _("Swaps rows and columns"), (ev, a) => {
                var m = ev.to_matrix (ev.eval (a[0]));
                var t = new Value[m.length[1], m.length[0]];
                for (int i = 0; i < m.length[0]; i++) for (int j = 0; j < m.length[1]; j++) t[j, i] = m[i, j];
                return Value.matrix (t);
            });
            add ("HYPERLINK", 1, 2, "HYPERLINK(link, [name])", _("A link that opens a web page or file"), (ev, a) => {
                if (a.length > 1) return ev.arg (a[1]);
                return ev.arg (a[0]);
            });
        }

        private static int xmatch (Value needle, Value[] hay, int mode, int search) {
            int n = hay.length;
            if (mode == 2 || mode == 0) {
                bool wild = mode == 2;
                if (search >= 0) {
                    for (int i = 0; i < n; i++) if (xeq (needle, hay[i], wild)) return i;
                } else {
                    for (int i = n - 1; i >= 0; i--) if (xeq (needle, hay[i], wild)) return i;
                }
                return -1;
            }
            int best = -1;
            for (int i = 0; i < n; i++) {
                var v = hay[i];
                if (v.kind == ValueKind.EMPTY) continue;
                if ((v.kind == ValueKind.TEXT) != (needle.kind == ValueKind.TEXT)) continue;
                int cmp = Evaluator.compare (v, needle);
                if (cmp == 0) return i;
                if (mode == -1 && cmp < 0 && (best < 0 || Evaluator.compare (v, hay[best]) > 0)) best = i;
                if (mode == 1 && cmp > 0 && (best < 0 || Evaluator.compare (v, hay[best]) < 0)) best = i;
            }
            return best;
        }

        private static bool xeq (Value needle, Value v, bool wild) {
            if (wild && needle.kind == ValueKind.TEXT) return new Criteria (Value.str ("=" + needle.text)).matches (v);
            return loose_equal (v, needle);
        }

        private static Value table_lookup (Evaluator ev, Node[] a, bool vertical) {
            var needle = ev.arg (a[0]);
            if (needle.is_error ()) return needle;
            int idx;
            var e = ev.arg_int (a[2], out idx);
            if (e != null) return e;
            bool approx = true;
            if (a.length > 3 && a[3].kind != NodeKind.MISSING && (e = ev.arg_bool (a[3], out approx)) != null) return e;
            var tv = ev.eval (a[1]);
            if (tv.is_error ()) return tv;
            var m = ev.to_matrix (tv);
            int rows = m.length[0], cols = m.length[1];
            if (idx < 1 || idx > (vertical ? cols : rows)) return Value.err (idx < 1 ? ErrorKind.VALUE : ErrorKind.REF);
            int n = vertical ? rows : cols;
            Value[] key = new Value[n];
            for (int i = 0; i < n; i++) key[i] = vertical ? m[i, 0] : m[0, i];
            int found = match (needle, key, approx ? 1 : 0);
            if (found < 0) return Value.err (ErrorKind.NA);
            var r = vertical ? m[found, idx - 1] : m[idx - 1, found];
            return r;
        }
    }
}
