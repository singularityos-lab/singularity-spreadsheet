namespace Singularity.Apps.Spreadsheet {

    public class DataTypeLink {
        public string source;
        public string key_column;
        public string key;

        public DataTypeLink (string source, string key_column, string key) {
            this.source = source;
            this.key_column = key_column;
            this.key = key;
        }
    }

    public class DataTypes {
        public static string link_key (Sheet s, int r, int c) {
            return "%s\t%d,%d".printf (s.name, r, c);
        }

        public static DataTypeLink? link_at (Workbook book, Sheet s, int r, int c) {
            return book.analysis.links[link_key (s, r, c)];
        }

        public static Area? source_area (Workbook book, string source) {
            var t = Tables.find (book, source);
            if (t != null) return new Area (t.sheet, t.header_row ? t.area.r1 : t.data_r1, t.area.c1, t.data_r2, t.area.c2);
            var q = QueryEngine.find (book, source);
            if (q != null && q.last_area != null) return q.last_area;
            return null;
        }

        public static string[] fields (Workbook book, string source) {
            string[] out_f = {};
            var a = source_area (book, source);
            if (a == null) return out_f;
            for (int c = a.c1; c <= a.c2; c++) out_f += a.sheet.value_at (a.r1, c).display ();
            return out_f;
        }

        public static int record_row (Workbook book, DataTypeLink link, out Area? area) {
            area = source_area (book, link.source);
            if (area == null) return -1;
            int kc = -1;
            for (int c = area.c1; c <= area.c2; c++) {
                if (area.sheet.value_at (area.r1, c).display ().casefold () == link.key_column.casefold ()) kc = c;
            }
            if (kc < 0) kc = area.c1;
            string key = link.key.casefold ();
            for (int r = area.r1 + 1; r <= int.min (area.r2, area.sheet.max_row); r++) {
                if (area.sheet.value_at (r, kc).display ().casefold () == key) return r;
            }
            return -1;
        }

        public static string[] fields_of (Workbook book, DataTypeLink link) {
            if (!link.source.has_prefix ("@")) return fields (book, link.source);
            string[] out_f = {};
            var rec = LinkedHub.record_for (book, link.source.substring (1), link.key);
            if (rec != null) foreach (var n in rec.order) out_f += n;
            return out_f;
        }

        public static LinkedRecord? linked_record (Workbook book, DataTypeLink link) {
            if (!link.source.has_prefix ("@")) return null;
            return LinkedHub.record_for (book, link.source.substring (1), link.key);
        }

        private static Value linked_value (Workbook book, DataTypeLink link, string field) {
            string kind = link.source.substring (1);
            string key = kind + ":" + link.key;
            var rec = LinkedHub.record_for (book, kind, link.key);
            if (rec == null) {
                if (book.analysis.loading.contains (key)) return Value.err (ErrorKind.GETTING_DATA);
                if (book.analysis.failures.has_key (key)) return Value.err (ErrorKind.NA);
                if (LinkedHub.get ().async_mode) {
                    LinkedHub.get ().fetch_async (book, kind, link.key, (r, e) => { });
                    return Value.err (ErrorKind.GETTING_DATA);
                }
                try {
                    rec = LinkedHub.fetch_or_cache (kind, link.key);
                    book.analysis.records[key] = rec;
                } catch (Error e) {
                    book.analysis.failures[key] = e.message;
                    return Value.err (ErrorKind.NA);
                }
            }
            var v = rec.field (field);
            return v ?? Value.err (ErrorKind.VALUE);
        }

        public static int convert_linked (Workbook book, Sheet s, Area sel, string kind, out string errors) {
            int n = 0;
            var sb = new StringBuilder ();
            var p = LinkedHub.provider (kind);
            for (int r = sel.r1; r <= int.min (sel.r2, s.max_row); r++) {
                for (int c = sel.c1; c <= int.min (sel.c2, s.max_col); c++) {
                    string text = s.value_at (r, c).display ().strip ();
                    if (text == "") continue;
                    try {
                        if (p == null) throw new LinkedError.NETWORK (_("This data type is turned off on this system."));
                        var list = p.search (text);
                        if (list.size == 0) throw new LinkedError.NOT_FOUND (_("\"%s\" was not found.").printf (text));
                        var rec = LinkedHub.fetch_or_cache (kind, pick (list, text).id);
                        LinkedHub.write_cache (rec);
                        LinkedHub.link (book, s, r, c, rec);
                        WhatIf.put_value (book, s, r, c, Value.str (rec.name));
                        n++;
                    } catch (Error e) {
                        sb.append ("%s: %s\n".printf (text, e.message));
                    }
                }
            }
            errors = sb.str.strip ();
            return n;
        }

        public static LinkedCandidate pick (Gee.List<LinkedCandidate> list, string text) {
            foreach (var c in list) if (c.label.casefold () == text.casefold ()) return c;
            return list[0];
        }

        public static bool is_ambiguous (Gee.List<LinkedCandidate> list, string text) {
            if (list.size <= 1) return false;
            int exact = 0;
            foreach (var c in list) if (c.label.casefold () == text.casefold ()) exact++;
            return exact != 1;
        }

        public static Value field_value (Workbook book, DataTypeLink link, string field) {
            if (link.source.has_prefix ("@")) return linked_value (book, link, field);
            Area? a;
            int r = record_row (book, link, out a);
            if (r < 0) return Value.err (ErrorKind.REF);
            string f = field.casefold ();
            for (int c = a.c1; c <= a.c2; c++) {
                if (a.sheet.value_at (a.r1, c).display ().casefold () == f) {
                    var v = a.sheet.value_at (r, c);
                    return v.is_empty () ? Value.num (0) : v;
                }
            }
            return Value.err (ErrorKind.VALUE);
        }

        public static Value field_of_ref (Evaluator ev, Value refv, string field) {
            if (refv.kind == ValueKind.RANGE) {
                var a = refv.area;
                var s = a.sheet ?? ev.sheet;
                if (a.is_single ()) {
                    var link = link_at (ev.book, s, a.r1, a.c1);
                    if (link == null) return Value.err (ErrorKind.VALUE);
                    return field_value (ev.book, link, field);
                }
                int rows = int.min (a.r2, int.max (s.max_row, a.r1)) - a.r1 + 1;
                int cols = int.min (a.c2, int.max (s.max_col, a.c1)) - a.c1 + 1;
                var m = new Value[rows, cols];
                for (int i = 0; i < rows; i++) {
                    for (int j = 0; j < cols; j++) {
                        var link = link_at (ev.book, s, a.r1 + i, a.c1 + j);
                        m[i, j] = link == null ? Value.err (ErrorKind.VALUE) : field_value (ev.book, link, field);
                    }
                }
                return Value.matrix (m);
            }
            if (refv.is_error ()) return refv;
            return Value.err (ErrorKind.VALUE);
        }

        public static Value? dot (Evaluator ev, string name) {
            int dot_at = name.index_of (".");
            if (dot_at <= 0 || dot_at == name.length - 1) return null;
            string cell = name.substring (0, dot_at).replace ("$", "");
            string field = name.substring (dot_at + 1);
            int r, c;
            bool ar, ac;
            if (!Address.parse_cell (cell, out r, out c, out ar, out ac)) return null;
            var link = link_at (ev.book, ev.sheet, r, c);
            if (link == null) return Value.err (ErrorKind.VALUE);
            return field_value (ev.book, link, field);
        }

        public static Value? dot_struct (Evaluator ev, StructRef sref) {
            if (!sref.table.has_suffix (".") || sref.col1 == "") return null;
            return dot (ev, sref.table + sref.col1);
        }

        public static int convert (Workbook book, Sheet s, Area sel, string source, string key_column) {
            int n = 0;
            for (int r = sel.r1; r <= int.min (sel.r2, s.max_row); r++) {
                for (int c = sel.c1; c <= int.min (sel.c2, s.max_col); c++) {
                    var v = s.value_at (r, c);
                    if (v.is_empty ()) continue;
                    var link = new DataTypeLink (source, key_column, v.display ());
                    Area? a;
                    if (record_row (book, link, out a) < 0) continue;
                    book.analysis.links[link_key (s, r, c)] = link;
                    n++;
                }
            }
            book.structure_changed = true;
            return n;
        }

        public static void clear (Workbook book, Sheet s, Area sel) {
            var drop = new Gee.ArrayList<string> ();
            foreach (var k in book.analysis.links.keys) {
                int tab = k.index_of ("\t");
                if (k.substring (0, tab) != s.name) continue;
                var p = k.substring (tab + 1).split (",");
                if (sel.contains (int.parse (p[0]), int.parse (p[1]))) drop.add (k);
            }
            foreach (var k in drop) book.analysis.links.unset (k);
            book.structure_changed = true;
        }
    }

    public class AnalysisFunctions {
        public static void register () {
            Functions.add ("GETPIVOTDATA", 2, -1, "Lookup", "GETPIVOTDATA(data_field, pivot_table, [field1, item1], ...)", _("Returns data stored in a PivotTable"), (ev, a) => {
                if (a.length % 2 != 0) return Value.err (ErrorKind.REF);
                Value? e;
                string data_field = ev.arg_text (a[0], out e);
                if (e != null) return e;
                var pv = ev.eval (a[1]);
                if (pv.kind != ValueKind.RANGE) return Value.err (ErrorKind.REF);
                var s = pv.area.sheet ?? ev.sheet;
                var p = ev.book.analysis.pivot_at (s, pv.area.r1, pv.area.c1);
                if (p == null) return Value.err (ErrorKind.REF);
                string[] fields = {};
                Value[] items = {};
                for (int i = 2; i + 1 < a.length; i += 2) {
                    fields += ev.arg_text (a[i], out e);
                    if (e != null) return e;
                    var it = ev.arg (a[i + 1]);
                    if (it.is_error ()) return it;
                    items += it;
                }
                return p.get_data (ev.book, data_field, fields, items);
            });
            Functions.add ("STOCKHISTORY", 2, 11, "Financial", "STOCKHISTORY(stock, start_date, [end_date], [interval], [headers], [property0], ...)", _("Returns historical prices of a stock as an array from the configured stocks service"), (ev, a) => {
                string sym;
                var sv = ev.eval (a[0]);
                DataTypeLink? link = null;
                if (sv.kind == ValueKind.RANGE && sv.area.is_single ()) link = DataTypes.link_at (ev.book, sv.area.sheet ?? ev.sheet, sv.area.r1, sv.area.c1);
                if (link != null && link.source == "@stocks") {
                    sym = link.key;
                } else {
                    var v = ev.deref (sv);
                    if (v.is_error ()) return v;
                    string t = Evaluator.to_text (v).strip ();
                    if (t == "") return Value.err (ErrorKind.VALUE);
                    sym = StooqStocks.symbol (t);
                }
                double start, end;
                var e = ev.arg_number (a[1], out start);
                if (e != null) return e;
                end = start;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING) {
                    e = ev.arg_number (a[2], out end);
                    if (e != null) return e;
                }
                if (end < start) return Value.err (ErrorKind.VALUE);
                int interval = 0, headers = 1;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING) {
                    e = ev.arg_int (a[3], out interval);
                    if (e != null) return e;
                }
                if (a.length > 4 && a[4].kind != NodeKind.MISSING) {
                    e = ev.arg_int (a[4], out headers);
                    if (e != null) return e;
                }
                if (interval < 0 || interval > 2 || headers < 0 || headers > 2) return Value.err (ErrorKind.VALUE);
                int[] props = {};
                for (int i = 5; i < a.length; i++) {
                    if (a[i].kind == NodeKind.MISSING) continue;
                    int pr;
                    e = ev.arg_int (a[i], out pr);
                    if (e != null) return e;
                    if (pr < 0 || pr > 5) return Value.err (ErrorKind.VALUE);
                    props += pr;
                }
                if (props.length == 0) props = { 0, 1 };
                return LinkedHub.history (ev, sym, start, end, interval, headers, props);
            });
            Functions.add ("FIELDVALUE", 2, 2, "Lookup", "FIELDVALUE(value, field_name)", _("Returns a field from a linked data type"), (ev, a) => {
                Value? e;
                string field = ev.arg_text (a[1], out e);
                if (e != null) return e;
                return DataTypes.field_of_ref (ev, ev.eval (a[0]), field);
            });
        }
    }
}
