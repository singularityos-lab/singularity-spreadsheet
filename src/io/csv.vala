namespace Singularity.Apps.Spreadsheet {

    public class Csv {
        public static char detect (string text) {
            char[] candidates = { ',', ';', '\t', '|' };
            char best = ',';
            int best_score = -1;
            string[] lines = text.split ("\n", 20);
            foreach (char c in candidates) {
                int first = -1;
                int score = 0;
                bool consistent = true;
                foreach (string line in lines) {
                    if (line.strip () == "") continue;
                    int n = 0;
                    bool q = false;
                    for (int i = 0; i < line.length; i++) {
                        if (line[i] == '"') q = !q;
                        else if (!q && line[i] == c) n++;
                    }
                    if (first < 0) first = n;
                    else if (n != first) consistent = false;
                    score += n;
                }
                if (first > 0 && consistent) score *= 4;
                if (score > best_score) {
                    best_score = score;
                    best = c;
                }
            }
            return best;
        }

        public static Gee.ArrayList<Gee.ArrayList<string>> parse (string text, char sep) {
            var rows = new Gee.ArrayList<Gee.ArrayList<string>> ();
            var row = new Gee.ArrayList<string> ();
            var field = new StringBuilder ();
            bool quoted = false;
            bool started = false;
            int i = 0;
            int n = text.length;
            if (text.has_prefix ("\xef\xbb\xbf")) i = 3;
            while (i < n) {
                char c = text[i];
                if (quoted) {
                    if (c == '"') {
                        if (i + 1 < n && text[i + 1] == '"') {
                            field.append_c ('"');
                            i += 2;
                            continue;
                        }
                        quoted = false;
                        i++;
                        continue;
                    }
                    field.append_c (c);
                    i++;
                    continue;
                }
                if (c == '"' && field.len == 0) {
                    quoted = true;
                    started = true;
                    i++;
                    continue;
                }
                if (c == sep) {
                    row.add (field.str);
                    field.truncate ();
                    started = true;
                    i++;
                    continue;
                }
                if (c == '\r' || c == '\n') {
                    if (started || field.len > 0 || row.size > 0) {
                        row.add (field.str);
                        rows.add (row);
                    }
                    row = new Gee.ArrayList<string> ();
                    field.truncate ();
                    started = false;
                    if (c == '\r' && i + 1 < n && text[i + 1] == '\n') i++;
                    i++;
                    continue;
                }
                field.append_c (c);
                started = true;
                i++;
            }
            if (started || field.len > 0 || row.size > 0) {
                row.add (field.str);
                rows.add (row);
            }
            return rows;
        }

        public static Workbook load (string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            if (!text.validate ()) {
                text = convert (text, -1, "UTF-8", "WINDOWS-1252");
            }
            var book = new Workbook ();
            string name = Path.get_basename (path);
            int dot = name.last_index_of (".");
            var sheet = book.add_sheet (dot > 0 ? name.substring (0, dot) : name);
            char sep = path.down ().has_suffix (".tsv") ? '\t' : detect (text);
            var rows = parse (text, sep);
            for (int r = 0; r < rows.size && r < MAX_ROWS; r++) {
                var row = rows[r];
                for (int c = 0; c < row.size && c < MAX_COLS; c++) {
                    string v = row[c];
                    if (v == "") continue;
                    sheet.set_input (r, c, v.has_prefix ("=") ? "'" + v : v);
                }
            }
            book.recalculate ();
            return book;
        }

        public static string quote (string s, char sep) {
            if (s.index_of_char (sep) >= 0 || s.contains ("\"") || s.contains ("\n") || s.contains ("\r") || s != s.strip ()) {
                return "\"" + s.replace ("\"", "\"\"") + "\"";
            }
            return s;
        }

        public static string export (Sheet sheet, char sep) {
            var sb = new StringBuilder ();
            for (int r = 0; r <= sheet.max_row; r++) {
                int last = -1;
                for (int c = 0; c <= sheet.max_col; c++) {
                    var v = sheet.value_at (r, c);
                    if (v.kind != ValueKind.EMPTY) last = c;
                }
                for (int c = 0; c <= last; c++) {
                    if (c > 0) sb.append_c (sep);
                    var v = sheet.value_at (r, c);
                    string color;
                    string text = NumberFormat.format_value (v, sheet.style_at (r, c).number_format, out color, sheet.book.date1904);
                    sb.append (quote (text, sep));
                }
                sb.append ("\n");
            }
            return sb.str;
        }

        public static void save (Sheet sheet, string path, char sep = ',') throws Error {
            FileUtils.set_contents (path, export (sheet, sep));
        }
    }
}
