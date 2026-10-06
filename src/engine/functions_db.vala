namespace Singularity.Apps.Spreadsheet {

    public class DatabaseFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Database", syntax, summary, (owned) impl);
        }

        private class CritCell {
            public int col = -1;
            public Criteria? crit;
            public Node? formula;
            public Sheet? sheet;
            public int row;
            public int column;
        }

        private static Value? field_index (Evaluator ev, Area db, Node n, out int col) {
            col = -1;
            var v = ev.arg (n);
            if (v.is_error ()) return v;
            if (v.kind == ValueKind.NUMBER || v.kind == ValueKind.BOOL) {
                int k = (int) Math.trunc (v.number);
                if (k < 1 || k > db.cols) return Value.err (ErrorKind.VALUE);
                col = db.c1 + k - 1;
                return null;
            }
            string name = Evaluator.to_text (v).strip ().casefold ();
            for (int c = db.c1; c <= db.c2; c++) {
                if (Evaluator.to_text (ev.cell (db.sheet, db.r1, c)).strip ().casefold () == name) {
                    col = c;
                    return null;
                }
            }
            return Value.err (ErrorKind.VALUE);
        }

        private static Criteria make_criteria (Value v) {
            if (v.kind == ValueKind.TEXT) {
                string t = v.text;
                bool has_op = t.has_prefix ("=") || t.has_prefix ("<") || t.has_prefix (">");
                if (!has_op) {
                    double d;
                    string f;
                    if (!Input.parse_number (t, out d, out f)) return new Criteria (Value.str (t + "*"));
                }
            }
            return new Criteria (v);
        }

        private static Value? matching_rows (Evaluator ev, Area db, Area crit, Gee.ArrayList<int> rows) {
            var header = new Gee.HashMap<string, int> ();
            for (int c = db.c1; c <= db.c2; c++) {
                string h = Evaluator.to_text (ev.cell (db.sheet, db.r1, c)).strip ().casefold ();
                if (h != "" && !header.has_key (h)) header[h] = c;
            }
            var ors = new Gee.ArrayList<Gee.ArrayList<CritCell>> ();
            var csheet = crit.sheet ?? ev.sheet;
            for (int r = crit.r1 + 1; r <= crit.r2; r++) {
                var ands = new Gee.ArrayList<CritCell> ();
                for (int c = crit.c1; c <= crit.c2; c++) {
                    var cv = ev.cell (csheet, r, c);
                    if (cv.kind == ValueKind.EMPTY) continue;
                    if (cv.is_error ()) return cv;
                    string h = Evaluator.to_text (ev.cell (csheet, crit.r1, c)).strip ().casefold ();
                    var cc = new CritCell ();
                    var cell = csheet.get_cell (r, c);
                    if (header.has_key (h)) {
                        cc.col = header[h];
                        cc.crit = make_criteria (cv);
                    } else if (cell != null && cell.formula != null) {
                        cc.formula = cell.formula;
                        cc.sheet = csheet;
                        cc.row = r;
                        cc.column = c;
                    } else {
                        return Value.err (ErrorKind.VALUE);
                    }
                    ands.add (cc);
                }
                ors.add (ands);
            }
            for (int r = db.r1 + 1; r <= db.r2; r++) {
                bool any = ors.size == 0;
                foreach (var ands in ors) {
                    bool all = true;
                    foreach (var cc in ands) {
                        bool ok;
                        if (cc.crit != null) {
                            ok = cc.crit.matches (ev.cell (db.sheet, r, cc.col));
                        } else {
                            var shifted = Formula.shifted (cc.formula, r - (db.r1 + 1), 0);
                            var sub = new Evaluator (ev.book, cc.sheet, cc.row, cc.column);
                            var res = sub.eval_top (shifted);
                            ok = !res.is_error () && res.kind != ValueKind.TEXT && res.number != 0;
                        }
                        if (!ok) {
                            all = false;
                            break;
                        }
                    }
                    if (all) {
                        any = true;
                        break;
                    }
                }
                if (any) rows.add (r);
            }
            return null;
        }

        private delegate Value DbOp (Gee.ArrayList<Value> values);

        private static void dfn (string name, string summary, owned DbOp f, bool field_optional = false) {
            DbOp op = (owned) f;
            add (name, field_optional ? 2 : 3, 3, name + "(database, field, criteria)", summary, (ev, a) => {
                var dv = ev.eval (a[0]);
                if (dv.is_error ()) return dv;
                if (dv.kind != ValueKind.RANGE) return Value.err (ErrorKind.VALUE);
                var db = dv.area;
                if (db.sheet == null) db = new Area (ev.sheet, db.r1, db.c1, db.r2, db.c2);
                Node crit_node = a[a.length - 1];
                var cv = ev.eval (crit_node);
                if (cv.is_error ()) return cv;
                if (cv.kind != ValueKind.RANGE || cv.area.rows < 2) return Value.err (ErrorKind.VALUE);
                int col = -1;
                bool has_field = a.length == 3 && a[1].kind != NodeKind.MISSING;
                if (has_field) {
                    var e = field_index (ev, db, a[1], out col);
                    if (e != null) return e;
                } else if (!field_optional) {
                    return Value.err (ErrorKind.VALUE);
                }
                var rows = new Gee.ArrayList<int> ();
                var e2 = matching_rows (ev, db, cv.area, rows);
                if (e2 != null) return e2;
                var vals = new Gee.ArrayList<Value> ();
                foreach (int r in rows) vals.add (col >= 0 ? ev.cell (db.sheet, r, col) : Value.num (1));
                return op (vals);
            });
        }

        private static Value? nums (Gee.ArrayList<Value> vals, Gee.ArrayList<double?> out_list) {
            foreach (var v in vals) {
                if (v.is_error ()) return v;
                if (v.kind == ValueKind.NUMBER) out_list.add (v.number);
            }
            return null;
        }

        private static Value variance (Gee.ArrayList<Value> vals, bool sample, bool root) {
            var l = new Gee.ArrayList<double?> ();
            var e = nums (vals, l);
            if (e != null) return e;
            int n = l.size;
            if (n < (sample ? 2 : 1)) return Value.err (ErrorKind.DIV0);
            double m = 0;
            foreach (var d in l) m += d;
            m /= n;
            double s = 0;
            foreach (var d in l) s += (d - m) * (d - m);
            double r = s / (sample ? n - 1 : n);
            return Value.num (root ? Math.sqrt (r) : r);
        }

        public static void register () {
            dfn ("DSUM", _("Sums the field of matching records"), (vals) => {
                var l = new Gee.ArrayList<double?> ();
                var e = nums (vals, l);
                if (e != null) return e;
                double s = 0;
                foreach (var d in l) s += d;
                return Value.num (s);
            });
            dfn ("DAVERAGE", _("Averages the field of matching records"), (vals) => {
                var l = new Gee.ArrayList<double?> ();
                var e = nums (vals, l);
                if (e != null) return e;
                if (l.size == 0) return Value.err (ErrorKind.DIV0);
                double s = 0;
                foreach (var d in l) s += d;
                return Value.num (s / l.size);
            });
            dfn ("DCOUNT", _("Counts numbers in the field of matching records"), (vals) => {
                int n = 0;
                foreach (var v in vals) if (v.kind == ValueKind.NUMBER) n++;
                return Value.num (n);
            }, true);
            dfn ("DCOUNTA", _("Counts nonblank cells in the field of matching records"), (vals) => {
                int n = 0;
                foreach (var v in vals) if (v.kind != ValueKind.EMPTY) n++;
                return Value.num (n);
            }, true);
            dfn ("DGET", _("The single value of the field that matches"), (vals) => {
                if (vals.size == 0) return Value.err (ErrorKind.VALUE);
                if (vals.size > 1) return Value.err (ErrorKind.NUM);
                return vals[0].kind == ValueKind.EMPTY ? Value.num (0) : vals[0];
            });
            dfn ("DMAX", _("The largest value of the field in matching records"), (vals) => {
                var l = new Gee.ArrayList<double?> ();
                var e = nums (vals, l);
                if (e != null) return e;
                if (l.size == 0) return Value.num (0);
                double m = -double.MAX;
                foreach (var d in l) m = double.max (m, d);
                return Value.num (m);
            });
            dfn ("DMIN", _("The smallest value of the field in matching records"), (vals) => {
                var l = new Gee.ArrayList<double?> ();
                var e = nums (vals, l);
                if (e != null) return e;
                if (l.size == 0) return Value.num (0);
                double m = double.MAX;
                foreach (var d in l) m = double.min (m, d);
                return Value.num (m);
            });
            dfn ("DPRODUCT", _("Multiplies the field of matching records"), (vals) => {
                var l = new Gee.ArrayList<double?> ();
                var e = nums (vals, l);
                if (e != null) return e;
                if (l.size == 0) return Value.num (0);
                double p = 1;
                foreach (var d in l) p *= d;
                return Value.num (p);
            });
            dfn ("DSTDEV", _("Sample standard deviation of matching records"), (vals) => variance (vals, true, true));
            dfn ("DSTDEVP", _("Population standard deviation of matching records"), (vals) => variance (vals, false, true));
            dfn ("DVAR", _("Sample variance of matching records"), (vals) => variance (vals, true, false));
            dfn ("DVARP", _("Population variance of matching records"), (vals) => variance (vals, false, false));
        }
    }
}
