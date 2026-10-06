namespace Singularity.Apps.Spreadsheet {

    public enum VbaModuleKind {
        STANDARD,
        CLASS,
        DOCUMENT
    }

    public class VbaModule {
        public string name;
        public string stream;
        public VbaModuleKind kind;
        public string source = "";

        public VbaModule (string name, string stream, VbaModuleKind kind) {
            this.name = name;
            this.stream = stream;
            this.kind = kind;
        }

        public string code () {
            var sb = new StringBuilder ();
            foreach (string line in source.split ("\n")) {
                string l = line.chomp ();
                string low = l.strip ().down ();
                if (low.has_prefix ("attribute ") && low.contains ("vb_")) continue;
                sb.append (l);
                sb.append ("\n");
            }
            return sb.str.strip () + "\n";
        }
    }

    public class VbaProject {
        public Gee.ArrayList<VbaModule> modules = new Gee.ArrayList<VbaModule> ();
        public string name = "";
        public int code_page = 1252;

        public static uint8[] decompress (uint8[] data, int start = 0) {
            var out_a = new ByteArray ();
            if (start >= data.length || data[start] != 0x01) return out_a.steal ();
            int pos = start + 1;
            while (pos + 1 < data.length) {
                int header = data[pos] | (data[pos + 1] << 8);
                int chunk_size = (header & 0x0FFF) + 3;
                bool compressed = (header & 0x8000) != 0;
                int chunk_end = int.min (pos + chunk_size, data.length);
                pos += 2;
                uint decomp_start = out_a.len;
                if (!compressed) {
                    int n = int.min (4096, data.length - pos);
                    out_a.append (data[pos:pos + n]);
                    pos += n;
                    continue;
                }
                while (pos < chunk_end) {
                    uint8 flags = data[pos++];
                    for (int bit = 0; bit < 8 && pos < chunk_end; bit++) {
                        if ((flags & (1 << bit)) == 0) {
                            uint8[] one = { data[pos++] };
                            out_a.append (one);
                            continue;
                        }
                        if (pos + 1 >= data.length) {
                            pos = chunk_end;
                            break;
                        }
                        int token = data[pos] | (data[pos + 1] << 8);
                        pos += 2;
                        uint diff = out_a.len - decomp_start;
                        int bit_count = 4;
                        while ((1u << bit_count) < diff) bit_count++;
                        int length_mask = 0xFFFF >> bit_count;
                        int length = (token & length_mask) + 3;
                        int offset = (token >> (16 - bit_count)) + 1;
                        if (offset > (int) out_a.len) {
                            pos = chunk_end;
                            break;
                        }
                        uint src = out_a.len - offset;
                        for (int k = 0; k < length; k++) {
                            uint8[] b = { out_a.data[src + k] };
                            out_a.append (b);
                        }
                    }
                }
                pos = chunk_end;
            }
            return out_a.steal ();
        }

        private static string decode (uint8[] bytes, int code_page) {
            string cs = code_page == 65001 ? "UTF-8" : "CP%d".printf (code_page);
            try {
                size_t r, w;
                return convert ((string) bytes, bytes.length, "UTF-8", cs, out r, out w);
            } catch (ConvertError e) {
                try {
                    size_t r, w;
                    return convert ((string) bytes, bytes.length, "UTF-8", "CP1252", out r, out w);
                } catch (ConvertError e2) {
                    return ((string) bytes).make_valid ();
                }
            }
        }

        private static string latin (uint8[] bytes) {
            var sb = new StringBuilder ();
            foreach (uint8 b in bytes) sb.append_unichar ((unichar) b);
            return sb.str;
        }

        private static string utf16 (uint8[] b) {
            var sb = new StringBuilder ();
            for (int i = 0; i + 1 < b.length; i += 2) sb.append_unichar ((unichar) (b[i] | (b[i + 1] << 8)));
            return sb.str;
        }

        public static VbaProject? parse (Gee.Map<string, Bytes> streams) {
            if (!streams.has_key ("dir")) return null;
            var dir = decompress (streams["dir"].get_data ());
            if (dir.length == 0) return null;
            var p = new VbaProject ();
            VbaModule? cur = null;
            var offsets = new Gee.HashMap<VbaModule, uint32> ();
            int pos = 0;
            while (pos + 6 <= dir.length) {
                int id = dir[pos] | (dir[pos + 1] << 8);
                uint32 size = (uint32) dir[pos + 2] | ((uint32) dir[pos + 3] << 8) | ((uint32) dir[pos + 4] << 16) | ((uint32) dir[pos + 5] << 24);
                pos += 6;
                if (id == 0x0009) {
                    pos += 6;
                    continue;
                }
                if (pos + (int) size > dir.length) break;
                var body = dir[pos:pos + (int) size];
                pos += (int) size;
                switch (id) {
                    case 0x0003:
                        if (body.length >= 2) p.code_page = body[0] | (body[1] << 8);
                        break;
                    case 0x0004:
                        p.name = decode (body, p.code_page);
                        break;
                    case 0x0019:
                        cur = new VbaModule (decode (body, p.code_page), decode (body, p.code_page), VbaModuleKind.STANDARD);
                        p.modules.add (cur);
                        break;
                    case 0x0047:
                        if (cur != null && body.length > 0) cur.name = utf16 (body);
                        break;
                    case 0x001A:
                        if (cur != null) cur.stream = decode (body, p.code_page);
                        break;
                    case 0x0032:
                        if (cur != null && body.length > 0) cur.stream = utf16 (body);
                        break;
                    case 0x0031:
                        if (cur != null && body.length >= 4) offsets[cur] = (uint32) body[0] | ((uint32) body[1] << 8) | ((uint32) body[2] << 16) | ((uint32) body[3] << 24);
                        break;
                    case 0x0022:
                        if (cur != null) cur.kind = VbaModuleKind.CLASS;
                        break;
                    case 0x002B:
                        cur = null;
                        break;
                }
            }
            if (streams.has_key ("PROJECT")) {
                string proj = latin (streams["PROJECT"].get_data ());
                foreach (string line in proj.split ("\n")) {
                    string l = line.strip ();
                    if (l.has_prefix ("Document=")) {
                        string n = l.substring (9);
                        int slash = n.index_of ("/");
                        if (slash >= 0) n = n.substring (0, slash);
                        foreach (var m in p.modules) if (m.name == n || m.stream == n) m.kind = VbaModuleKind.DOCUMENT;
                    } else if (l.has_prefix ("Class=")) {
                        string n = l.substring (6);
                        foreach (var m in p.modules) if (m.name == n || m.stream == n) m.kind = VbaModuleKind.CLASS;
                    }
                }
            }
            foreach (var m in p.modules) {
                Bytes? raw = streams.has_key (m.stream) ? streams[m.stream] : null;
                if (raw == null) {
                    foreach (var e in streams.entries) if (e.key.casefold () == m.stream.casefold ()) raw = e.value;
                }
                if (raw == null) continue;
                uint32 off = offsets.has_key (m) ? offsets[m] : 0;
                var text = decompress (raw.get_data (), (int) off);
                m.source = decode (text, p.code_page).replace ("\r\n", "\n").replace ("\r", "\n");
            }
            return p;
        }

        public static VbaProject? from_bin (Bytes bin) {
            try {
                var cfb = new Cfb (bin.get_data ());
                return parse (cfb.streams);
            } catch (Error e) {
                return null;
            }
        }

        public static VbaProject? from_cfb (Cfb cfb) {
            return parse (cfb.streams);
        }

        public string combined_source () {
            var sb = new StringBuilder ();
            foreach (var m in modules) {
                if (m.kind == VbaModuleKind.CLASS) continue;
                sb.append (m.code ());
            }
            return sb.str;
        }
    }
}
