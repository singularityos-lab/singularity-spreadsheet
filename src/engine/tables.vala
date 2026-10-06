namespace Singularity.Apps.Spreadsheet {

    public class TableColumn {
        public string name;
        public string totals_function = "";
        public string totals_label = "";
        public string calculated = "";

        public TableColumn (string name) {
            this.name = name;
        }

        public TableColumn copy () {
            var c = new TableColumn (name);
            c.totals_function = totals_function;
            c.totals_label = totals_label;
            c.calculated = calculated;
            return c;
        }
    }

    public class TableDef {
        public string name;
        public Sheet sheet;
        public Area area;
        public bool header_row = true;
        public bool totals_row;
        public bool banded_rows = true;
        public bool banded_cols;
        public bool first_col;
        public bool last_col;
        public bool filter_button = true;
        public string style_name = "TableStyleMedium2";
        public Gee.ArrayList<TableColumn> columns = new Gee.ArrayList<TableColumn> ();

        public TableDef (string name, Sheet sheet, Area area) {
            this.name = name;
            this.sheet = sheet;
            this.area = area;
        }

        public TableDef copy () {
            var t = new TableDef (name, sheet, area.copy ());
            t.header_row = header_row;
            t.totals_row = totals_row;
            t.banded_rows = banded_rows;
            t.banded_cols = banded_cols;
            t.first_col = first_col;
            t.last_col = last_col;
            t.filter_button = filter_button;
            t.style_name = style_name;
            foreach (var c in columns) t.columns.add (c.copy ());
            return t;
        }

        public int data_r1 {
            get { return area.r1 + (header_row ? 1 : 0); }
        }

        public int data_r2 {
            get { return area.r2 - (totals_row ? 1 : 0); }
        }

        public int column_index (string col) {
            string k = col.casefold ();
            for (int i = 0; i < columns.size; i++) {
                if (columns[i].name.casefold () == k) return i;
            }
            return -1;
        }

        public void sync_columns () {
            var fresh = new Gee.ArrayList<TableColumn> ();
            var used = new Gee.HashSet<string> ();
            for (int c = area.c1; c <= area.c2; c++) {
                int idx = c - area.c1;
                string n = header_row ? sheet.value_at (area.r1, c).display () : "";
                if (n == "" && idx < columns.size) n = columns[idx].name;
                if (n == "") n = _("Column%d").printf (idx + 1);
                string unique = n;
                for (int k = 2; used.contains (unique.casefold ()); k++) unique = n + k.to_string ();
                used.add (unique.casefold ());
                var tc = idx < columns.size ? columns[idx].copy () : new TableColumn (unique);
                tc.name = unique;
                fresh.add (tc);
            }
            columns = fresh;
        }
    }

    public class StructRef {
        public string table = "";
        public bool this_row;
        public bool all;
        public bool data;
        public bool headers;
        public bool totals;
        public string col1 = "";
        public string col2 = "";

        public StructRef copy () {
            var r = new StructRef ();
            r.table = table;
            r.this_row = this_row;
            r.all = all;
            r.data = data;
            r.headers = headers;
            r.totals = totals;
            r.col1 = col1;
            r.col2 = col2;
            return r;
        }

        private static string unescape (string s) {
            var sb = new StringBuilder ();
            for (int i = 0; i < s.length; i++) {
                if (s[i] == '\'' && i + 1 < s.length) {
                    i++;
                }
                sb.append_c (s[i]);
            }
            return sb.str.strip ();
        }

        private static string escape (string s) {
            var sb = new StringBuilder ();
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c == '[' || c == ']' || c == '#' || c == '\'') sb.append_c ('\'');
                sb.append_c (c);
            }
            return sb.str;
        }

        private static bool plain (string s) {
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c == ' ' || c == '\t' || c == ',' || c == ':' || c == '@' || c == '[' || c == ']' || c == '#' || c == '\'' || c == '"' || c == '{' || c == '}' || c == '$' || c == '^' || c == '&' || c == '*' || c == '+' || c == '=' || c == '-' || c == '>' || c == '<' || c == '/' || c == '%' || c == '!' || c == '(' || c == ')' || c == ';' || c == '~' || c == '`') return false;
            }
            return s.length > 0;
        }

        private bool apply_item (string raw) {
            string t = raw.strip ();
            string u = t.up ();
            if (u == "#ALL") all = true;
            else if (u == "#DATA") data = true;
            else if (u == "#HEADERS") headers = true;
            else if (u == "#TOTALS") totals = true;
            else if (u == "#THIS ROW") this_row = true;
            else if (col1 == "") col1 = unescape (t);
            else if (col2 == "") col2 = unescape (t);
            else return false;
            return true;
        }

        private static string[] split_items (string body) {
            string[] parts = {};
            int depth = 0;
            int start = 0;
            for (int i = 0; i < body.length; i++) {
                char c = body[i];
                if (c == '\'' && i + 1 < body.length) {
                    i++;
                    continue;
                }
                if (c == '[') depth++;
                else if (c == ']') depth--;
                else if (depth == 0 && (c == ',' || c == ':')) {
                    parts += body.substring (start, i - start);
                    start = i + 1;
                }
            }
            parts += body.substring (start);
            return parts;
        }

        private static string strip_brackets (string s) {
            string t = s.strip ();
            if (t.has_prefix ("[") && t.has_suffix ("]")) return t.substring (1, t.length - 2);
            return t;
        }

        public static StructRef? parse (string text) {
            int b = text.index_of_char ('[');
            if (b < 0 || !text.has_suffix ("]")) return null;
            var r = new StructRef ();
            r.table = text.substring (0, b);
            string body = text.substring (b + 1, text.length - b - 2);
            if (body.strip () == "") return r;
            string bs = body.strip ();
            if (bs.has_prefix ("@")) {
                r.this_row = true;
                bs = bs.substring (1).strip ();
                if (bs == "") return r;
                if (!bs.has_prefix ("[")) {
                    r.col1 = unescape (bs);
                    return r;
                }
                body = bs;
            }
            if (!body.contains ("[")) {
                if (!r.apply_item (body)) return null;
                return r;
            }
            foreach (string part in split_items (body)) {
                string p = part.strip ();
                if (p == "") continue;
                if (p.has_prefix ("@")) {
                    r.this_row = true;
                    p = p.substring (1);
                }
                if (!r.apply_item (strip_brackets (p))) return null;
            }
            return r;
        }

        private static string col_text (string c) {
            return "[" + escape (c) + "]";
        }

        public string to_file_string () {
            if (!this_row) return to_string ();
            string[] items = { "[#This Row]" };
            if (col1 != "") items += col_text (col1) + (col2 != "" ? ":" + col_text (col2) : "");
            if (items.length == 1) return table + "[#This Row]";
            return table + "[" + string.joinv (",", items) + "]";
        }

        public string to_string () {
            int specials = (all ? 1 : 0) + (data ? 1 : 0) + (headers ? 1 : 0) + (totals ? 1 : 0);
            if (this_row && specials == 0) {
                if (col1 == "") return table + "[@]";
                if (col2 == "") return table + "[@" + (plain (col1) ? escape (col1) : col_text (col1)) + "]";
                return table + "[@" + col_text (col1) + ":" + col_text (col2) + "]";
            }
            if (!this_row && specials == 0 && col2 == "") {
                if (col1 == "") return table + "[]";
                return table + "[" + escape (col1) + "]";
            }
            if (!this_row && specials == 1 && col1 == "") {
                return table + "[" + (all ? "#All" : data ? "#Data" : headers ? "#Headers" : "#Totals") + "]";
            }
            string[] items = {};
            if (all) items += "[#All]";
            if (headers) items += "[#Headers]";
            if (data) items += "[#Data]";
            if (totals) items += "[#Totals]";
            if (this_row) items += "[#This Row]";
            string cols = "";
            if (col1 != "") cols = col_text (col1) + (col2 != "" ? ":" + col_text (col2) : "");
            if (cols != "") items += cols;
            return table + "[" + string.joinv (",", items) + "]";
        }
    }

    public class Tables {
        public static TableDef? find (Workbook book, string name) {
            string k = name.casefold ();
            foreach (var t in book.tables) if (t.name.casefold () == k) return t;
            return null;
        }

        public static TableDef? at (Workbook book, Sheet sheet, int row, int col) {
            foreach (var t in book.tables) if (t.sheet == sheet && t.area.contains (row, col)) return t;
            return null;
        }

        public static Area? resolve_name (Workbook book, string name) {
            var t = find (book, name);
            if (t == null) return null;
            if (t.data_r2 < t.data_r1) return null;
            return new Area (t.sheet, t.data_r1, t.area.c1, t.data_r2, t.area.c2);
        }

        public static Area? resolve (Workbook book, StructRef r, Sheet sheet, int row, int col) {
            TableDef? t = r.table != "" ? find (book, r.table) : at (book, sheet, row, col);
            if (t == null) return null;
            int c1 = t.area.c1, c2 = t.area.c2;
            if (r.col1 != "") {
                int i1 = t.column_index (r.col1);
                if (i1 < 0) return null;
                c1 = c2 = t.area.c1 + i1;
                if (r.col2 != "") {
                    int i2 = t.column_index (r.col2);
                    if (i2 < 0) return null;
                    c2 = t.area.c1 + i2;
                }
            }
            int r1, r2;
            if (r.this_row) {
                if (t.sheet != sheet || row < t.data_r1 || row > t.data_r2) return null;
                r1 = r2 = row;
            } else if (r.all) {
                r1 = t.area.r1;
                r2 = t.area.r2;
            } else if (r.headers && r.data) {
                if (!t.header_row) return null;
                r1 = t.area.r1;
                r2 = t.data_r2;
            } else if (r.data && r.totals) {
                r1 = t.data_r1;
                r2 = t.area.r2;
            } else if (r.headers) {
                if (!t.header_row) return null;
                r1 = r2 = t.area.r1;
            } else if (r.totals) {
                if (!t.totals_row) return null;
                r1 = r2 = t.area.r2;
            } else {
                r1 = t.data_r1;
                r2 = t.data_r2;
            }
            if (r2 < r1) return null;
            return new Area (t.sheet, r1, c1, r2, c2);
        }

        public static string unique_name (Workbook book, string base_name) {
            for (int i = 1; ; i++) {
                string n = "%s%d".printf (base_name, i);
                if (find (book, n) == null && !book.names.has_key (n)) return n;
            }
        }
    }
}

namespace Singularity.Apps.Spreadsheet {

    public class TableCommands {
        public static string[] style_names () {
            return { "TableStyleLight1", "TableStyleLight9", "TableStyleMedium2", "TableStyleMedium7", "TableStyleMedium9", "TableStyleDark1" };
        }

        public static string style_accent (string style_name) {
            switch (style_name) {
                case "TableStyleLight1": return "#595959";
                case "TableStyleLight9": return "#4472c4";
                case "TableStyleMedium7": return "#70ad47";
                case "TableStyleMedium9": return "#4472c4";
                case "TableStyleDark1": return "#262626";
                default: return "#4472c4";
            }
        }

        private static string tint (string hex, double amount) {
            string h = hex.has_prefix ("#") ? hex.substring (1) : hex;
            if (h.length != 6) return "#dddddd";
            int r = (int) ("0x" + h.substring (0, 2)).to_int64 (), g = (int) ("0x" + h.substring (2, 2)).to_int64 (), b = (int) ("0x" + h.substring (4, 2)).to_int64 ();
            r = (int) (r + (255 - r) * amount);
            g = (int) (g + (255 - g) * amount);
            b = (int) (b + (255 - b) * amount);
            return "#%02x%02x%02x".printf (r, g, b);
        }

        public static void apply_style (Workbook book, TableDef t) {
            string accent = style_accent (t.style_name);
            bool dark_header = t.style_name.has_prefix ("TableStyleMedium") || t.style_name.has_prefix ("TableStyleDark");
            for (int r = t.area.r1; r <= t.area.r2; r++) {
                bool header = t.header_row && r == t.area.r1;
                bool totals = t.totals_row && r == t.area.r2;
                int band = r - t.data_r1;
                for (int c = t.area.c1; c <= t.area.c2; c++) {
                    var cell = t.sheet.ensure (r, c);
                    var st = book.styles[cell.style].copy ();
                    st.fill = "";
                    st.top = new Border ();
                    st.bottom = new Border ();
                    if (header) {
                        st.bold = true;
                        if (dark_header) {
                            st.fill = accent;
                            st.color = "#ffffff";
                        } else {
                            st.bottom = new Border (BorderStyle.THIN, accent);
                        }
                    } else if (totals) {
                        st.bold = true;
                        st.top = new Border (BorderStyle.DOUBLE, accent);
                    } else {
                        if (st.color == "#ffffff") st.color = "";
                        if (t.banded_rows && band % 2 == 0) st.fill = tint (accent, 0.8);
                        if (t.banded_cols && (c - t.area.c1) % 2 == 0) st.fill = tint (accent, 0.8);
                        if ((t.first_col && c == t.area.c1) || (t.last_col && c == t.area.c2)) st.bold = true;
                    }
                    cell.style = book.intern (st);
                }
            }
        }

        public static void clear_style (Workbook book, TableDef t) {
            for (int r = t.area.r1; r <= t.area.r2; r++) {
                for (int c = t.area.c1; c <= t.area.c2; c++) {
                    var cell = t.sheet.get_cell (r, c);
                    if (cell == null) continue;
                    var st = book.styles[cell.style].copy ();
                    st.fill = "";
                    st.bold = false;
                    st.color = "";
                    st.top = new Border ();
                    st.bottom = new Border ();
                    cell.style = book.intern (st);
                }
            }
        }

        public static void write_totals (Workbook book, TableDef t) {
            if (!t.totals_row) return;
            int r = t.area.r2;
            for (int i = 0; i < t.columns.size; i++) {
                var col = t.columns[i];
                int c = t.area.c1 + i;
                if (col.totals_function == "" && i == 0 && col.totals_label == "") col.totals_label = _("Total");
                if (col.totals_label != "") t.sheet.set_input (r, c, col.totals_label);
                else if (col.totals_function.has_prefix ("=")) t.sheet.set_input (r, c, col.totals_function);
                else if (col.totals_function != "") {
                    var sr = new StructRef ();
                    sr.table = t.name;
                    sr.col1 = col.name;
                    t.sheet.set_input (r, c, "=SUBTOTAL(%d,%s)".printf (XlsxDynamic.subtotal_code (col.totals_function), sr.to_string ()));
                } else t.sheet.set_input (r, c, "");
            }
        }

        public static TableDef? create (Document doc, Sheet s, Area area, bool header, string style_name) {
            foreach (var other in doc.book.tables) if (other.sheet == s && other.area.intersects (area)) return null;
            doc.begin_book (_("Create Table"), s, area);
            var t = new TableDef (Tables.unique_name (doc.book, "Table"), s, area.copy ());
            if (!header) {
                doc.book.insert_rows (s, area.r1, 1);
                t.area = new Area (s, area.r1, area.c1, area.r2 + 1, area.c2);
                for (int c = area.c1; c <= area.c2; c++) s.set_input (area.r1, c, _("Column%d").printf (c - area.c1 + 1));
            }
            t.style_name = style_name;
            t.sync_columns ();
            for (int i = 0; i < t.columns.size; i++) {
                if (s.input_at (t.area.r1, t.area.c1 + i) != t.columns[i].name) s.set_input (t.area.r1, t.area.c1 + i, t.columns[i].name);
            }
            doc.book.tables.add (t);
            apply_style (doc.book, t);
            doc.book.structure_changed = true;
            doc.commit ();
            return t;
        }

        public static void update (Document doc, TableDef t, string name, bool totals, bool banded_rows, bool banded_cols, bool first_col, bool last_col, bool filter, string style_name) {
            doc.begin_book (_("Table Design"), t.sheet, t.area);
            string old = t.name;
            if (name != "" && name != old && Tables.find (doc.book, name) == null) {
                t.name = name;
                rename_refs (doc.book, old, name);
            }
            if (totals != t.totals_row) {
                if (totals) {
                    doc.book.insert_rows (t.sheet, t.area.r2 + 1, 1);
                    t.area = new Area (t.sheet, t.area.r1, t.area.c1, t.area.r2 + 1, t.area.c2);
                    t.totals_row = true;
                    for (int i = 1; i < t.columns.size; i++) {
                        if (t.columns[i].totals_function == "") {
                            if (i == t.columns.size - 1) t.columns[i].totals_function = "SUM";
                        }
                    }
                    write_totals (doc.book, t);
                } else {
                    int r = t.area.r2;
                    t.totals_row = false;
                    t.area = new Area (t.sheet, t.area.r1, t.area.c1, t.area.r2 - 1, t.area.c2);
                    doc.book.delete_rows (t.sheet, r, 1);
                }
            }
            t.banded_rows = banded_rows;
            t.banded_cols = banded_cols;
            t.first_col = first_col;
            t.last_col = last_col;
            t.filter_button = filter;
            t.style_name = style_name;
            apply_style (doc.book, t);
            doc.book.structure_changed = true;
            doc.commit ();
        }

        public static void convert_to_range (Document doc, TableDef t) {
            doc.begin_book (_("Convert to Range"), t.sheet, t.area);
            foreach (var s in doc.book.sheets) {
                foreach (var c in s.cells.values) {
                    if (c.formula == null || !has_struct (c.formula)) continue;
                    resolve_structs (doc.book, c.formula, s, c.row, c.col, t.name);
                    c.input = Formula.to_text (c.formula, s);
                }
            }
            doc.book.tables.remove (t);
            doc.book.structure_changed = true;
            doc.commit ();
        }

        public static void remove (Document doc, TableDef t) {
            doc.begin_book (_("Clear Table Style"), t.sheet, t.area);
            clear_style (doc.book, t);
            doc.book.tables.remove (t);
            doc.book.structure_changed = true;
            doc.commit ();
        }

        private static bool has_struct (Node n) {
            if (n.kind == NodeKind.STRUCT) return true;
            foreach (var a in n.args) if (has_struct (a)) return true;
            return false;
        }

        private static void resolve_structs (Workbook book, Node n, Sheet own, int row, int col, string table) {
            if (n.kind == NodeKind.STRUCT) {
                var t = n.sref.table != "" ? Tables.find (book, n.sref.table) : Tables.at (book, own, row, col);
                if (t != null && t.name.casefold () == table.casefold ()) {
                    var a = Tables.resolve (book, n.sref, own, row, col);
                    if (a != null) {
                        bool rel_row = n.sref.this_row;
                        n.kind = NodeKind.REF;
                        n.sref = null;
                        n.sheet = a.sheet != own ? a.sheet : null;
                        n.a = new RefPart (a.r1, a.c1, !rel_row, true);
                        n.b = a.is_single () ? null : new RefPart (a.r2, a.c2, !rel_row, true);
                    }
                }
                return;
            }
            foreach (var a in n.args) resolve_structs (book, a, own, row, col, table);
        }

        private static void rename_refs (Workbook book, string old_name, string name) {
            foreach (var s in book.sheets) {
                foreach (var c in s.cells.values) {
                    if (c.formula == null) continue;
                    bool touched = false;
                    rename_in (c.formula, old_name, name, ref touched);
                    if (touched) c.input = Formula.to_text (c.formula, s);
                }
            }
        }

        private static void rename_in (Node n, string old_name, string name, ref bool touched) {
            if (n.kind == NodeKind.STRUCT && n.sref.table.casefold () == old_name.casefold ()) {
                n.sref.table = name;
                touched = true;
            }
            if (n.kind == NodeKind.NAME && n.text.casefold () == old_name.casefold ()) {
                n.text = name;
                touched = true;
            }
            foreach (var a in n.args) rename_in (a, old_name, name, ref touched);
        }

        public static bool auto_expand (Document doc, Sheet s, int row, int col, string text) {
            if (text == "") return false;
            foreach (var t in doc.book.tables) {
                if (t.sheet != s || t.totals_row) continue;
                bool below = row == t.area.r2 + 1 && col >= t.area.c1 && col <= t.area.c2;
                bool right = col == t.area.c2 + 1 && row >= t.area.r1 && row <= t.area.r2;
                if (!below && !right) continue;
                doc.begin_book (_("Typing"), s, new Area.cell (s, row, col));
                s.set_input (row, col, text);
                if (below) {
                    t.area = new Area (s, t.area.r1, t.area.c1, t.area.r2 + 1, t.area.c2);
                    for (int i = 0; i < t.columns.size; i++) {
                        string calc = t.columns[i].calculated;
                        if (calc != "" && t.area.c1 + i != col) s.set_input (row, t.area.c1 + i, calc);
                    }
                } else {
                    t.area = new Area (s, t.area.r1, t.area.c1, t.area.r2, t.area.c2 + 1);
                    if (row != t.area.r1 && t.header_row) s.set_input (t.area.r1, col, _("Column%d").printf (t.area.cols));
                    t.sync_columns ();
                }
                apply_style (doc.book, t);
                doc.book.structure_changed = true;
                doc.commit ();
                return true;
            }
            return false;
        }

        public static bool fill_calculated (Document doc, Sheet s, int row, int col, string text) {
            if (!text.has_prefix ("=")) return false;
            var t = Tables.at (doc.book, s, row, col);
            if (t == null || row < t.data_r1 || row > t.data_r2 || t.data_r2 == t.data_r1) return false;
            for (int r = t.data_r1; r <= t.data_r2; r++) {
                if (r != row && s.input_at (r, col) != "") return false;
            }
            doc.begin_book (_("Calculated Column"), s, new Area (s, t.data_r1, col, t.data_r2, col));
            for (int r = t.data_r1; r <= t.data_r2; r++) s.set_input (r, col, text);
            t.columns[col - t.area.c1].calculated = text;
            doc.book.structure_changed = true;
            doc.commit ();
            return true;
        }
    }
}
