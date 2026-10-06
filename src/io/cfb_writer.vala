namespace Singularity.Apps.Spreadsheet {

    public class CfbWriter {
        private class Entry {
            public string name;
            public bool storage;
            public uint8[]? data;
            public Gee.ArrayList<Entry> children = new Gee.ArrayList<Entry> ();
            public int id;
            public int left = -1;
            public int right = -1;
            public int child = -1;
            public uint32 start = (uint32) 0xFFFFFFFEu;
        }

        private Entry root;
        private const int SECTOR = 512;
        private const int MINI = 64;
        private const uint32 END = 0xFFFFFFFEu;
        private const uint32 FREE = 0xFFFFFFFFu;
        private const uint32 FATSECT = 0xFFFFFFFDu;

        public CfbWriter () {
            root = new Entry ();
            root.name = "Root Entry";
            root.storage = true;
        }

        public void add (string path, uint8[] data) {
            string[] parts = path.split ("/");
            var cur = root;
            for (int i = 0; i < parts.length - 1; i++) {
                Entry? next = null;
                foreach (var c in cur.children) if (c.storage && c.name == parts[i]) next = c;
                if (next == null) {
                    next = new Entry ();
                    next.name = parts[i];
                    next.storage = true;
                    cur.children.add (next);
                }
                cur = next;
            }
            var e = new Entry ();
            e.name = parts[parts.length - 1];
            e.data = data;
            cur.children.add (e);
        }

        private static int compare_names (string a, string b) {
            long la = a.char_count (), lb = b.char_count ();
            if (la != lb) return la < lb ? -1 : 1;
            return strcmp (a.up (), b.up ());
        }

        private void number (Entry e, Gee.ArrayList<Entry> list) {
            e.id = list.size;
            list.add (e);
            e.children.sort ((x, y) => compare_names (x.name, y.name));
            foreach (var c in e.children) number (c, list);
        }

        private int balance (Gee.ArrayList<Entry> sorted, int lo, int hi) {
            if (lo > hi) return -1;
            int mid = (lo + hi) / 2;
            var e = sorted[mid];
            e.left = balance (sorted, lo, mid - 1);
            e.right = balance (sorted, mid + 1, hi);
            return e.id;
        }

        private void link (Entry e) {
            if (e.children.size > 0) e.child = balance (e.children, 0, e.children.size - 1);
            foreach (var c in e.children) link (c);
        }

        private static void put32 (uint8[] b, int o, uint32 v) {
            b[o] = (uint8) (v & 0xff);
            b[o + 1] = (uint8) ((v >> 8) & 0xff);
            b[o + 2] = (uint8) ((v >> 16) & 0xff);
            b[o + 3] = (uint8) ((v >> 24) & 0xff);
        }

        private static void put16 (uint8[] b, int o, uint16 v) {
            b[o] = (uint8) (v & 0xff);
            b[o + 1] = (uint8) ((v >> 8) & 0xff);
        }

        public uint8[] build () {
            var list = new Gee.ArrayList<Entry> ();
            number (root, list);
            link (root);
            var mini = new ByteArray ();
            var minifat = new Gee.ArrayList<uint32> ();
            var bigs = new Gee.ArrayList<Entry> ();
            foreach (var e in list) {
                if (e.storage || e.data == null) continue;
                if (e.data.length < 4096) {
                    if (e.data.length == 0) {
                        e.start = END;
                        continue;
                    }
                    int first = (int) (mini.len / MINI);
                    int n = (e.data.length + MINI - 1) / MINI;
                    e.start = first;
                    for (int i = 0; i < n; i++) minifat.add (i == n - 1 ? END : (uint32) (first + i + 1));
                    mini.append (e.data);
                    int pad = n * MINI - e.data.length;
                    if (pad > 0) mini.append (new uint8[pad]);
                } else {
                    bigs.add (e);
                }
            }
            int dir_sectors = (list.size * 128 + SECTOR - 1) / SECTOR;
            int minifat_sectors = (minifat.size * 4 + SECTOR - 1) / SECTOR;
            int mini_sectors = (int) ((mini.len + SECTOR - 1) / SECTOR);
            int big_sectors = 0;
            foreach (var e in bigs) big_sectors += (e.data.length + SECTOR - 1) / SECTOR;
            int content = dir_sectors + minifat_sectors + mini_sectors + big_sectors;
            int fat_sectors = 1;
            while (fat_sectors * (SECTOR / 4) < content + fat_sectors) fat_sectors++;
            int total = fat_sectors + content;
            var fat = new uint32[fat_sectors * (SECTOR / 4)];
            for (int i = 0; i < fat.length; i++) fat[i] = FREE;
            int next = 0;
            for (int i = 0; i < fat_sectors; i++) fat[next++] = FATSECT;
            int dir_start = next;
            for (int i = 0; i < dir_sectors; i++, next++) fat[next] = i == dir_sectors - 1 ? END : (uint32) (next + 1);
            int minifat_start = minifat_sectors > 0 ? next : -1;
            for (int i = 0; i < minifat_sectors; i++, next++) fat[next] = i == minifat_sectors - 1 ? END : (uint32) (next + 1);
            int mini_start = mini_sectors > 0 ? next : -1;
            for (int i = 0; i < mini_sectors; i++, next++) fat[next] = i == mini_sectors - 1 ? END : (uint32) (next + 1);
            foreach (var e in bigs) {
                int n = (e.data.length + SECTOR - 1) / SECTOR;
                e.start = next;
                for (int i = 0; i < n; i++, next++) fat[next] = i == n - 1 ? END : (uint32) (next + 1);
            }
            var out_b = new uint8[SECTOR * (total + 1)];
            uint8[] sig = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };
            for (int i = 0; i < 8; i++) out_b[i] = sig[i];
            put16 (out_b, 0x18, 0x003E);
            put16 (out_b, 0x1A, 0x0003);
            put16 (out_b, 0x1C, 0xFFFE);
            put16 (out_b, 0x1E, 9);
            put16 (out_b, 0x20, 6);
            put32 (out_b, 0x2C, fat_sectors);
            put32 (out_b, 0x30, dir_start);
            put32 (out_b, 0x38, 4096);
            put32 (out_b, 0x3C, minifat_start >= 0 ? (uint32) minifat_start : END);
            put32 (out_b, 0x40, minifat_sectors);
            put32 (out_b, 0x44, END);
            put32 (out_b, 0x48, 0);
            for (int i = 0; i < 109; i++) put32 (out_b, 0x4C + i * 4, i < fat_sectors ? (uint32) i : FREE);
            for (int i = 0; i < fat.length; i++) put32 (out_b, SECTOR + i * 4, fat[i]);
            int dir_off = SECTOR * (dir_start + 1);
            for (int k = 0; k < dir_sectors * (SECTOR / 128); k++) {
                int o = dir_off + k * 128;
                if (k >= list.size) {
                    put32 (out_b, o + 68, FREE);
                    put32 (out_b, o + 72, FREE);
                    put32 (out_b, o + 76, FREE);
                    continue;
                }
                var e = list[k];
                string name = e.name.length > 31 ? e.name.substring (0, 31) : e.name;
                int ci = 0;
                int idx = 0;
                unichar ch;
                while (name.get_next_char (ref idx, out ch) && ci < 31) {
                    put16 (out_b, o + ci * 2, (uint16) ch);
                    ci++;
                }
                put16 (out_b, o + 64, (uint16) ((ci + 1) * 2));
                out_b[o + 66] = e == root ? 5 : (e.storage ? 1 : 2);
                out_b[o + 67] = 1;
                put32 (out_b, o + 68, e.left >= 0 ? (uint32) e.left : FREE);
                put32 (out_b, o + 72, e.right >= 0 ? (uint32) e.right : FREE);
                put32 (out_b, o + 76, e.child >= 0 ? (uint32) e.child : FREE);
                if (e == root) {
                    put32 (out_b, o + 116, mini_start >= 0 ? (uint32) mini_start : END);
                    put32 (out_b, o + 120, (uint32) mini.len);
                } else if (!e.storage) {
                    put32 (out_b, o + 116, e.start);
                    put32 (out_b, o + 120, e.data != null ? e.data.length : 0);
                }
            }
            if (minifat_start >= 0) {
                int o = SECTOR * (minifat_start + 1);
                for (int i = 0; i < minifat_sectors * (SECTOR / 4); i++) put32 (out_b, o + i * 4, i < minifat.size ? minifat[i] : FREE);
            }
            if (mini_start >= 0) {
                int o = SECTOR * (mini_start + 1);
                for (int i = 0; i < (int) mini.len; i++) out_b[o + i] = mini.data[i];
            }
            foreach (var e in bigs) {
                int o = SECTOR * ((int) e.start + 1);
                for (int i = 0; i < e.data.length; i++) out_b[o + i] = e.data[i];
            }
            return out_b;
        }

        public static Bytes? vba_from_host (Cfb host, string storage) {
            var w = new CfbWriter ();
            int count = 0;
            string prefix = storage + "/";
            foreach (var e in host.by_path.entries) {
                if (!e.key.has_prefix (prefix)) continue;
                w.add (e.key.substring (prefix.length), e.value.get_data ());
                count++;
            }
            if (count == 0) return null;
            return new Bytes (w.build ());
        }
    }
}
