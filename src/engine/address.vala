namespace Singularity.Apps.Spreadsheet {

    public const int MAX_ROWS = 1048576;
    public const int MAX_COLS = 16384;

    public class Address {
        public static string column_name (int col) {
            var sb = new StringBuilder ();
            int n = col + 1;
            while (n > 0) {
                int rem = (n - 1) % 26;
                sb.prepend_c ((char) ('A' + rem));
                n = (n - 1) / 26;
            }
            return sb.str;
        }

        public static int column_index (string letters) {
            int n = 0;
            for (int i = 0; i < letters.length; i++) {
                char c = letters[i].toupper ();
                if (c < 'A' || c > 'Z') return -1;
                n = n * 26 + (c - 'A' + 1);
                if (n > MAX_COLS) return -1;
            }
            return n - 1;
        }

        public static string cell (int row, int col, bool abs_row = false, bool abs_col = false) {
            return (abs_col ? "$" : "") + column_name (col) + (abs_row ? "$" : "") + (row + 1).to_string ();
        }

        public static bool parse_cell (string s, out int row, out int col, out bool abs_row, out bool abs_col) {
            row = col = -1;
            abs_row = abs_col = false;
            int i = 0;
            if (i < s.length && s[i] == '$') {
                abs_col = true;
                i++;
            }
            int start = i;
            while (i < s.length && s[i].isalpha ()) i++;
            if (i == start || i - start > 3) return false;
            col = column_index (s.substring (start, i - start));
            if (i < s.length && s[i] == '$') {
                abs_row = true;
                i++;
            }
            int dstart = i;
            while (i < s.length && s[i].isdigit ()) i++;
            if (i == dstart || i != s.length) return false;
            int64 r = int64.parse (s.substring (dstart));
            if (col < 0 || r < 1 || r > MAX_ROWS) return false;
            row = (int) r - 1;
            return true;
        }

        public static string quote_sheet (string name) {
            bool plain = name.length > 0 && !name[0].isdigit ();
            for (int i = 0; i < name.length && plain; i++) {
                char c = name[i];
                if (!(c.isalnum () || c == '_' || c == '.' || (uchar) c >= 0x80)) plain = false;
            }
            if (plain) {
                int r, c;
                bool ar, ac;
                if (parse_cell (name, out r, out c, out ar, out ac)) plain = false;
                string u = name.up ();
                if (u == "TRUE" || u == "FALSE") plain = false;
            }
            return plain ? name : "'" + name.replace ("'", "''") + "'";
        }
    }

    public class Area {
        public Sheet? sheet;
        public int r1;
        public int c1;
        public int r2;
        public int c2;

        public Area (Sheet? sheet, int r1, int c1, int r2, int c2) {
            this.sheet = sheet;
            this.r1 = int.min (r1, r2);
            this.r2 = int.max (r1, r2);
            this.c1 = int.min (c1, c2);
            this.c2 = int.max (c1, c2);
        }

        public Area.cell (Sheet? sheet, int r, int c) {
            this (sheet, r, c, r, c);
        }

        public int rows {
            get { return r2 - r1 + 1; }
        }

        public int cols {
            get { return c2 - c1 + 1; }
        }

        public int64 size {
            get { return (int64) rows * cols; }
        }

        public bool contains (int r, int c) {
            return r >= r1 && r <= r2 && c >= c1 && c <= c2;
        }

        public bool is_single () {
            return r1 == r2 && c1 == c2;
        }

        public bool intersects (Area o) {
            return !(o.r1 > r2 || o.r2 < r1 || o.c1 > c2 || o.c2 < c1);
        }

        public Area copy () {
            return new Area (sheet, r1, c1, r2, c2);
        }

        public string to_string () {
            if (is_single ()) return Address.cell (r1, c1);
            if (c1 == 0 && c2 == MAX_COLS - 1) return "%d:%d".printf (r1 + 1, r2 + 1);
            if (r1 == 0 && r2 == MAX_ROWS - 1) return "%s:%s".printf (Address.column_name (c1), Address.column_name (c2));
            return Address.cell (r1, c1) + ":" + Address.cell (r2, c2);
        }

        public static Area? parse (string text, Sheet? sheet) {
            string s = text.strip ();
            int colon = s.index_of (":");
            int r1 = 0, c1 = 0, r2 = 0, c2 = 0;
            bool a, b;
            if (colon < 0) {
                if (!Address.parse_cell (s, out r1, out c1, out a, out b)) return null;
                return new Area.cell (sheet, r1, c1);
            }
            string left = s.substring (0, colon);
            string right = s.substring (colon + 1);
            if (Address.parse_cell (left, out r1, out c1, out a, out b) && Address.parse_cell (right, out r2, out c2, out a, out b))
                return new Area (sheet, r1, c1, r2, c2);
            int ci1 = Address.column_index (left.replace ("$", ""));
            int ci2 = Address.column_index (right.replace ("$", ""));
            if (ci1 >= 0 && ci2 >= 0 && left.replace ("$", "").length > 0) return new Area (sheet, 0, ci1, MAX_ROWS - 1, ci2);
            int64 ri1 = int64.parse (left.replace ("$", ""));
            int64 ri2 = int64.parse (right.replace ("$", ""));
            if (ri1 >= 1 && ri2 >= 1 && ri1 <= MAX_ROWS && ri2 <= MAX_ROWS) return new Area (sheet, (int) ri1 - 1, 0, (int) ri2 - 1, MAX_COLS - 1);
            return null;
        }
    }
}
