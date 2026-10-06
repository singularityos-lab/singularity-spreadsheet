namespace Singularity.Apps.Spreadsheet {

    public class PasswordHash {
        public string algorithm = "";
        public string hash = "";
        public string salt = "";
        public int spin_count = 100000;
        public string legacy = "";
        public string odf = "";

        public bool is_set () {
            return hash != "" || legacy != "" || odf != "";
        }

        public PasswordHash copy () {
            var p = new PasswordHash ();
            p.algorithm = algorithm;
            p.hash = hash;
            p.salt = salt;
            p.spin_count = spin_count;
            p.legacy = legacy;
            p.odf = odf;
            return p;
        }

        public static uint8[] utf16le (string password) {
            var bytes = new GLib.ByteArray ();
            unichar c;
            int i = 0;
            while (password.get_next_char (ref i, out c)) {
                if (c > 0xffff) {
                    uint v = c - 0x10000;
                    uint hi = 0xd800 + (v >> 10);
                    uint lo = 0xdc00 + (v & 0x3ff);
                    bytes.append ({ (uint8) (hi & 0xff), (uint8) (hi >> 8), (uint8) (lo & 0xff), (uint8) (lo >> 8) });
                } else {
                    bytes.append ({ (uint8) (c & 0xff), (uint8) (c >> 8) });
                }
            }
            return bytes.data;
        }

        private static ChecksumType checksum_type (string algorithm) {
            switch (algorithm.up ().replace ("-", "")) {
                case "SHA256": return ChecksumType.SHA256;
                case "SHA384": return ChecksumType.SHA384;
                case "SHA1": return ChecksumType.SHA1;
                case "MD5": return ChecksumType.MD5;
                default: return ChecksumType.SHA512;
            }
        }

        private static uint8[] digest (ChecksumType t, uint8[] data) {
            var ck = new Checksum (t);
            ck.update (data, data.length);
            size_t len = 64;
            var buf = new uint8[64];
            ck.get_digest (buf, ref len);
            buf.length = (int) len;
            return buf;
        }

        public static string iterated (string password, string algorithm, uint8[] salt, int spin) {
            var t = checksum_type (algorithm);
            var pw = utf16le (password);
            var first = new uint8[salt.length + pw.length];
            Memory.copy (first, salt, salt.length);
            Memory.copy ((uint8*) first + salt.length, pw, pw.length);
            var h = digest (t, first);
            var buf = new uint8[h.length + 4];
            for (int i = 0; i < spin; i++) {
                Memory.copy (buf, h, h.length);
                buf[h.length] = (uint8) (i & 0xff);
                buf[h.length + 1] = (uint8) ((i >> 8) & 0xff);
                buf[h.length + 2] = (uint8) ((i >> 16) & 0xff);
                buf[h.length + 3] = (uint8) ((i >> 24) & 0xff);
                buf.length = h.length + 4;
                h = digest (t, buf);
            }
            return Base64.encode (h);
        }

        public static string legacy_hash (string password) {
            if (password == "") return "";
            var chars = new Gee.ArrayList<uint> ();
            unichar c;
            int i = 0;
            while (password.get_next_char (ref i, out c)) {
                uint b = c < 0x100 ? (uint) c : (uint) (c & 0xff);
                chars.add (b);
            }
            uint hash = 0;
            for (int k = chars.size - 1; k >= 0; k--) {
                hash = ((hash >> 14) & 0x01) | ((hash << 1) & 0x7fff);
                hash ^= chars[k];
            }
            hash = ((hash >> 14) & 0x01) | ((hash << 1) & 0x7fff);
            hash ^= chars.size;
            hash ^= 0xce4b;
            return "%04X".printf (hash);
        }

        public static string odf_digest (string password, string algorithm) {
            var t = algorithm.has_suffix ("sha1") ? ChecksumType.SHA1 : ChecksumType.SHA256;
            var d = digest (t, password.data);
            return Base64.encode (d);
        }

        public static PasswordHash create (string password) {
            var p = new PasswordHash ();
            if (password == "") return p;
            var salt = new uint8[16];
            for (int i = 0; i < 16; i++) salt[i] = (uint8) Random.int_range (0, 256);
            p.algorithm = "SHA-512";
            p.salt = Base64.encode (salt);
            p.spin_count = 100000;
            p.hash = iterated (password, p.algorithm, salt, p.spin_count);
            p.legacy = legacy_hash (password);
            p.odf = odf_digest (password, "sha256");
            return p;
        }

        public bool verify (string password) {
            if (!is_set ()) return true;
            if (hash != "" && algorithm.has_prefix ("odf:")) return odf_digest (password, algorithm) == hash;
            if (hash != "" && salt != "") return iterated (password, algorithm, Base64.decode (salt), spin_count) == hash;
            if (legacy != "") return legacy_hash (password).up () == legacy.up ();
            if (odf != "") return odf_digest (password, "sha256") == odf;
            return false;
        }
    }

    public class SheetProtection {
        public PasswordHash password = new PasswordHash ();
        public bool select_locked = true;
        public bool select_unlocked = true;
        public bool format_cells;
        public bool format_columns;
        public bool format_rows;
        public bool insert_columns;
        public bool insert_rows;
        public bool insert_hyperlinks;
        public bool delete_columns;
        public bool delete_rows;
        public bool sort;
        public bool autofilter;
        public bool pivot_tables;
        public bool objects;
        public bool scenarios;
        public Gee.ArrayList<EditRange> ranges = new Gee.ArrayList<EditRange> ();

        public SheetProtection copy () {
            var p = new SheetProtection ();
            p.password = password.copy ();
            p.select_locked = select_locked;
            p.select_unlocked = select_unlocked;
            p.format_cells = format_cells;
            p.format_columns = format_columns;
            p.format_rows = format_rows;
            p.insert_columns = insert_columns;
            p.insert_rows = insert_rows;
            p.insert_hyperlinks = insert_hyperlinks;
            p.delete_columns = delete_columns;
            p.delete_rows = delete_rows;
            p.sort = sort;
            p.autofilter = autofilter;
            p.pivot_tables = pivot_tables;
            p.objects = objects;
            p.scenarios = scenarios;
            foreach (var r in ranges) p.ranges.add (r.copy ());
            return p;
        }
    }

    public class EditRange {
        public string title;
        public Area area;
        public PasswordHash password = new PasswordHash ();
        public bool unlocked;

        public EditRange (string title, Area area) {
            this.title = title;
            this.area = area;
        }

        public EditRange copy () {
            var r = new EditRange (title, area.copy ());
            r.password = password.copy ();
            r.unlocked = unlocked;
            return r;
        }
    }

    public class BookProtection {
        public PasswordHash password = new PasswordHash ();
        public bool structure = true;
        public bool windows;

        public BookProtection copy () {
            var p = new BookProtection ();
            p.password = password.copy ();
            p.structure = structure;
            p.windows = windows;
            return p;
        }
    }

    public enum ProtectAction {
        EDIT_CELL,
        FORMAT_CELLS,
        FORMAT_COLUMNS,
        FORMAT_ROWS,
        INSERT_COLUMNS,
        INSERT_ROWS,
        DELETE_COLUMNS,
        DELETE_ROWS,
        SORT,
        AUTOFILTER,
        OBJECTS,
        STRUCTURE
    }

    public class Protect {
        public static bool cell_locked (Sheet s, int r, int c) {
            if (s.protection == null) return false;
            if (!s.style_at (r, c).locked) return false;
            foreach (var er in s.protection.ranges) {
                if (er.area.contains (r, c) && (er.unlocked || !er.password.is_set ())) return false;
            }
            return true;
        }

        public static EditRange? range_at (Sheet s, int r, int c) {
            if (s.protection == null) return null;
            foreach (var er in s.protection.ranges) if (er.area.contains (r, c)) return er;
            return null;
        }

        public static bool area_locked (Sheet s, Area a) {
            if (s.protection == null) return false;
            var clamped = Document.clamp_area (s, a);
            int r2 = int.min (clamped.r2, int.max (s.max_row, clamped.r1));
            int c2 = int.min (clamped.c2, int.max (s.max_col, clamped.c1));
            if ((int64) (r2 - clamped.r1 + 1) * (c2 - clamped.c1 + 1) > 200000) return true;
            for (int r = clamped.r1; r <= r2; r++) {
                for (int c = clamped.c1; c <= c2; c++) if (cell_locked (s, r, c)) return true;
            }
            return false;
        }

        public static bool hides_formula (Sheet s, int r, int c) {
            return s.protection != null && s.style_at (r, c).hidden;
        }

        public static bool allowed (Workbook book, Sheet s, ProtectAction p) {
            if (p == ProtectAction.STRUCTURE) return book.protection == null || !book.protection.structure;
            var sp = s.protection;
            if (sp == null) return true;
            switch (p) {
                case ProtectAction.FORMAT_CELLS: return sp.format_cells;
                case ProtectAction.FORMAT_COLUMNS: return sp.format_columns;
                case ProtectAction.FORMAT_ROWS: return sp.format_rows;
                case ProtectAction.INSERT_COLUMNS: return sp.insert_columns;
                case ProtectAction.INSERT_ROWS: return sp.insert_rows;
                case ProtectAction.DELETE_COLUMNS: return sp.delete_columns;
                case ProtectAction.DELETE_ROWS: return sp.delete_rows;
                case ProtectAction.SORT: return sp.sort;
                case ProtectAction.AUTOFILTER: return sp.autofilter;
                case ProtectAction.OBJECTS: return sp.objects;
                default: return false;
            }
        }

        public static string message () {
            return _("The cell or chart you are trying to change is on a protected sheet. To make a change, unprotect the sheet from the Review menu.");
        }
    }
}
