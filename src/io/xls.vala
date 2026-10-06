namespace Singularity.Apps.Spreadsheet {

    public errordomain XlsError {
        FORMAT,
        ENCRYPTED
    }

    public class Cfb {
        private uint8[] data;
        private int sector_size;
        private int mini_size = 64;
        private uint32 mini_cutoff = 4096;
        private uint32[] fat = {};
        private uint32[] minifat = {};
        private uint8[] ministream = {};
        public Gee.HashMap<string, Bytes> streams = new Gee.HashMap<string, Bytes> ();

        private uint16 u16 (int o) {
            return (uint16) (data[o] | (data[o + 1] << 8));
        }

        private uint32 u32 (int o) {
            return (uint32) data[o] | ((uint32) data[o + 1] << 8) | ((uint32) data[o + 2] << 16) | ((uint32) data[o + 3] << 24);
        }

        public static bool sniff_head (uint8[] d) {
            uint8[] sig = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };
            if (d.length < 8) return false;
            for (int i = 0; i < 8; i++) if (d[i] != sig[i]) return false;
            return true;
        }

        public static bool sniff (uint8[] d) {
            uint8[] sig = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };
            if (d.length < 512) return false;
            for (int i = 0; i < 8; i++) if (d[i] != sig[i]) return false;
            return true;
        }

        public Cfb (owned uint8[] d) throws XlsError {
            data = (owned) d;
            if (!sniff (data)) throw new XlsError.FORMAT ("not a compound file");
            sector_size = 1 << u16 (0x1E);
            mini_size = 1 << u16 (0x20);
            mini_cutoff = u32 (0x38);
            uint32 first_dir = u32 (0x30);
            uint32 first_minifat = u32 (0x3C);
            uint32 first_difat = u32 (0x44);
            uint32 num_difat = u32 (0x48);
            var fat_sectors = new Gee.ArrayList<uint32> ();
            for (int i = 0; i < 109; i++) {
                uint32 s = u32 (0x4C + i * 4);
                if (s < 0xFFFFFFFA) fat_sectors.add (s);
            }
            uint32 d_sec = first_difat;
            for (uint32 k = 0; k < num_difat && d_sec < 0xFFFFFFFA; k++) {
                int off = sector_offset (d_sec);
                if (off < 0) break;
                int per = sector_size / 4 - 1;
                for (int i = 0; i < per; i++) {
                    uint32 s = u32 (off + i * 4);
                    if (s < 0xFFFFFFFA) fat_sectors.add (s);
                }
                d_sec = u32 (off + per * 4);
            }
            uint32[] f = {};
            foreach (uint32 s in fat_sectors) {
                int off = sector_offset (s);
                if (off < 0) continue;
                for (int i = 0; i < sector_size / 4; i++) f += u32 (off + i * 4);
            }
            fat = f;
            var dir = chain (first_dir, -1);
            var mf = chain (first_minifat, -1);
            uint32[] m = {};
            for (int i = 0; i + 3 < mf.length; i += 4) m += (uint32) mf[i] | ((uint32) mf[i + 1] << 8) | ((uint32) mf[i + 2] << 16) | ((uint32) mf[i + 3] << 24);
            minifat = m;
            for (int e = 0; e + 128 <= dir.length; e += 128) {
                int nlen = dir[e + 64] | (dir[e + 65] << 8);
                int type = dir[e + 66];
                if (nlen < 2 || type == 0) continue;
                var sb = new StringBuilder ();
                for (int i = 0; i < nlen - 2; i += 2) sb.append_unichar ((unichar) (dir[e + i] | (dir[e + i + 1] << 8)));
                uint32 start = (uint32) dir[e + 116] | ((uint32) dir[e + 117] << 8) | ((uint32) dir[e + 118] << 16) | ((uint32) dir[e + 119] << 24);
                uint32 size = (uint32) dir[e + 120] | ((uint32) dir[e + 121] << 8) | ((uint32) dir[e + 122] << 16) | ((uint32) dir[e + 123] << 24);
                if (type == 5) {
                    ministream = chain (start, (int) size);
                } else if (type == 2) {
                    if (size < mini_cutoff) streams[sb.str] = new Bytes (mini_chain (start, (int) size));
                    else streams[sb.str] = new Bytes (chain (start, (int) size));
                }
            }
            index_paths (dir);
        }

        public Gee.HashMap<string, Bytes> by_path = new Gee.HashMap<string, Bytes> ();

        private static uint32 u32_at (uint8[] d, int o) {
            return (uint32) d[o] | ((uint32) d[o + 1] << 8) | ((uint32) d[o + 2] << 16) | ((uint32) d[o + 3] << 24);
        }

        private void index_paths (uint8[] dir) {
            int count = dir.length / 128;
            if (count == 0) return;
            var visited = new Gee.HashSet<uint32> ();
            walk (dir, u32_at (dir, 76), "", visited, count);
        }

        private void walk (uint8[] dir, uint32 id, string prefix, Gee.HashSet<uint32> visited, int count) {
            if (id >= count || visited.contains (id)) return;
            visited.add (id);
            int e = (int) id * 128;
            int nlen = dir[e + 64] | (dir[e + 65] << 8);
            int type = dir[e + 66];
            var sb = new StringBuilder ();
            for (int i = 0; i < nlen - 2 && i < 62; i += 2) sb.append_unichar ((unichar) (dir[e + i] | (dir[e + i + 1] << 8)));
            string path = prefix + sb.str;
            walk (dir, u32_at (dir, e + 68), prefix, visited, count);
            walk (dir, u32_at (dir, e + 72), prefix, visited, count);
            if (type == 1) {
                walk (dir, u32_at (dir, e + 76), path + "/", visited, count);
            } else if (type == 2) {
                uint32 start = u32_at (dir, e + 116);
                uint32 size = u32_at (dir, e + 120);
                by_path[path] = new Bytes (size < mini_cutoff ? mini_chain (start, (int) size) : chain (start, (int) size));
            }
        }

        private int sector_offset (uint32 s) {
            int64 off = ((int64) s + 1) * sector_size;
            if (off + sector_size > data.length) return -1;
            return (int) off;
        }

        private uint8[] chain (uint32 start, int size) {
            var out_a = new ByteArray ();
            uint32 s = start;
            int guard = 0;
            while (s < 0xFFFFFFFA && s < fat.length && guard++ < 1000000) {
                int off = sector_offset (s);
                if (off < 0) {
                    int64 part = ((int64) s + 1) * sector_size;
                    if (part < data.length) out_a.append (data[(int) part:data.length]);
                    break;
                }
                out_a.append (data[off:off + sector_size]);
                if (size >= 0 && out_a.len >= size) break;
                s = fat[s];
            }
            if (size >= 0 && out_a.len > size) out_a.set_size (size);
            return out_a.steal ();
        }

        private uint8[] mini_chain (uint32 start, int size) {
            var out_a = new ByteArray ();
            uint32 s = start;
            int guard = 0;
            while (s < 0xFFFFFFFA && s < minifat.length && guard++ < 1000000) {
                int off = (int) s * mini_size;
                if (off + mini_size > ministream.length) break;
                out_a.append (ministream[off:off + mini_size]);
                if (out_a.len >= size) break;
                s = minifat[s];
            }
            if (out_a.len > size) out_a.set_size (size);
            return out_a.steal ();
        }
    }

    private class XlsFont {
        public bool bold;
        public bool italic;
        public bool underline;
        public bool strike;
        public double size = 10;
        public int color = 0x7FFF;
        public string name = "";
    }

    private class XlsRec {
        public int type;
        public uint8[] data;
    }

    private class XlsShared {
        public int r1;
        public int r2;
        public int c1;
        public int c2;
        public uint8[] rgce;
    }

    public class Xls {
        private uint8[] stream;
        private Workbook book;
        private string[] sst = {};
        private XlsFont[] fonts = {};
        private Gee.HashMap<int, string> formats = new Gee.HashMap<int, string> ();
        private int[] xf_style = {};
        private string[] palette = {};
        private int[] xti_first = {};
        private int[] xti_last = {};
        private int[] xti_book = {};
        private string[] names = {};
        private Gee.ArrayList<Gee.ArrayList<string>> extern_names = new Gee.ArrayList<Gee.ArrayList<string>> ();
        private Gee.ArrayList<int> sheet_pos = new Gee.ArrayList<int> ();
        private Gee.ArrayList<string> sheet_names = new Gee.ArrayList<string> ();
        private int internal_book = 0;
        private bool allow_union = false;
        private Gee.ArrayList<int> sheet_states = new Gee.ArrayList<int> ();
        private Gee.ArrayList<XlsShared> shared = new Gee.ArrayList<XlsShared> ();
        private Gee.HashMap<int, string> obj_text = new Gee.HashMap<int, string> ();
        private Gee.HashMap<string, string> array_texts = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, Area> array_areas = new Gee.HashMap<string, Area> ();
        public int formulas_decoded;
        public int formulas_kept_value;
        public static bool collect_cached;
        public static Gee.HashMap<Cell, Value> cached_values = new Gee.HashMap<Cell, Value> ();

        public static Workbook load (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            return load_data ((owned) data);
        }

        public static Workbook load_data (owned uint8[] data) throws Error {
            var cfb = new Cfb ((owned) data);
            uint8[]? s = null;
            foreach (var e in cfb.streams.entries) {
                if (e.key == "Workbook" || e.key == "Book") s = e.value.get_data ();
            }
            if (s == null && cfb.streams.has_key ("EncryptedPackage")) throw new XlsError.ENCRYPTED ("the workbook is protected with a password");
            if (s == null) throw new XlsError.FORMAT ("no Workbook stream");
            var x = new Xls ();
            x.stream = s;
            x.book = new Workbook ();
            x.run ();
            x.book.vba = VbaProject.from_cfb (cfb);
            if (x.book.vba != null) x.book.vba_project = CfbWriter.vba_from_host (cfb, "_VBA_PROJECT_CUR");
            return x.book;
        }

        private static uint16 u16 (uint8[] d, int o) {
            if (o + 1 >= d.length) return 0;
            return (uint16) (d[o] | (d[o + 1] << 8));
        }

        private static int16 s16 (uint8[] d, int o) {
            return (int16) u16 (d, o);
        }

        private static uint32 u32 (uint8[] d, int o) {
            if (o + 3 >= d.length) return 0;
            return (uint32) d[o] | ((uint32) d[o + 1] << 8) | ((uint32) d[o + 2] << 16) | ((uint32) d[o + 3] << 24);
        }

        private static double f64 (uint8[] d, int o) {
            uint64 bits = 0;
            for (int i = 7; i >= 0; i--) bits = (bits << 8) | (o + i < d.length ? d[o + i] : 0);
            double v = 0;
            Memory.copy (&v, &bits, 8);
            return v;
        }

        private static double rk (uint32 v) {
            double d = 0;
            if ((v & 2) != 0) {
                d = (double) ((int32) v >> 2);
            } else {
                uint64 bits = ((uint64) (v & 0xFFFFFFFC)) << 32;
                Memory.copy (&d, &bits, 8);
            }
            if ((v & 1) != 0) d /= 100;
            return d;
        }

        private XlsRec? read_rec (ref int pos) {
            if (pos + 4 > stream.length) return null;
            var r = new XlsRec ();
            r.type = u16 (stream, pos);
            int len = u16 (stream, pos + 2);
            int end = int.min (pos + 4 + len, stream.length);
            r.data = stream[pos + 4:end];
            pos = end;
            return r;
        }

        private Gee.ArrayList<Bytes> continues (ref int pos) {
            var list = new Gee.ArrayList<Bytes> ();
            while (pos + 4 <= stream.length && u16 (stream, pos) == 0x003C) {
                var r = read_rec (ref pos);
                list.add (new Bytes (r.data));
            }
            return list;
        }

        private static string chars (uint8[] d, int o, int cch, bool wide, out int used) {
            var sb = new StringBuilder ();
            int p = o;
            for (int i = 0; i < cch && p < d.length; i++) {
                if (wide) {
                    sb.append_unichar ((unichar) u16 (d, p));
                    p += 2;
                } else {
                    sb.append_unichar ((unichar) d[p]);
                    p += 1;
                }
            }
            used = p - o;
            return sb.str;
        }

        private static string short_string (uint8[] d, int o, out int used) {
            int cch = d[o];
            int u;
            string s = chars (d, o + 2, cch, (d[o + 1] & 1) != 0, out u);
            used = 2 + u;
            return s;
        }

        private static string long_string (uint8[] d, int o, out int used) {
            int cch = u16 (d, o);
            uint8 flags = o + 2 < d.length ? d[o + 2] : 0;
            int p = o + 3;
            int runs = 0, ext = 0;
            if ((flags & 8) != 0) {
                runs = u16 (d, p);
                p += 2;
            }
            if ((flags & 4) != 0) {
                ext = (int) u32 (d, p);
                p += 4;
            }
            int u;
            string s = chars (d, p, cch, (flags & 1) != 0, out u);
            p += u + runs * 4 + ext;
            used = p - o;
            return s;
        }

        private void read_sst (uint8[] first, Gee.ArrayList<Bytes> conts) {
            var blocks = new Gee.ArrayList<Bytes> ();
            blocks.add (new Bytes (first));
            blocks.add_all (conts);
            int bi = 0;
            int p = 8;
            uint32 total = u32 (first, 4);
            string[] list = {};
            for (uint32 k = 0; k < total; k++) {
                unowned uint8[] d = blocks[bi].get_data ();
                if (p >= d.length) {
                    bi++;
                    if (bi >= blocks.size) break;
                    d = blocks[bi].get_data ();
                    p = 0;
                }
                int cch = u16 (d, p);
                uint8 flags = d[p + 2];
                p += 3;
                int runs = 0, ext = 0;
                if ((flags & 8) != 0) {
                    runs = u16 (d, p);
                    p += 2;
                }
                if ((flags & 4) != 0) {
                    ext = (int) u32 (d, p);
                    p += 4;
                }
                bool wide = (flags & 1) != 0;
                var sb = new StringBuilder ();
                int got = 0;
                while (got < cch) {
                    if (p >= d.length) {
                        bi++;
                        if (bi >= blocks.size) break;
                        d = blocks[bi].get_data ();
                        wide = (d[0] & 1) != 0;
                        p = 1;
                    }
                    if (wide) {
                        sb.append_unichar ((unichar) u16 (d, p));
                        p += 2;
                    } else {
                        sb.append_unichar ((unichar) d[p]);
                        p += 1;
                    }
                    got++;
                }
                int skip = runs * 4 + ext;
                while (skip > 0 && bi < blocks.size) {
                    int avail = (int) blocks[bi].get_size () - p;
                    if (skip <= avail) {
                        p += skip;
                        skip = 0;
                    } else {
                        skip -= avail;
                        bi++;
                        p = 0;
                    }
                }
                list += sb.str;
            }
            sst = list;
        }

        private string color (int icv) {
            if (icv >= 8 && icv - 8 < palette.length) return "#" + palette[icv - 8].down ();
            if (icv >= 0 && icv < Xlsx.INDEXED.length) return "#" + Xlsx.INDEXED[icv].down ();
            return "";
        }

        private static BorderStyle border (int dg) {
            switch (dg) {
                case 1: case 7: return BorderStyle.THIN;
                case 2: return BorderStyle.MEDIUM;
                case 3: case 8: case 9: case 10: case 11: case 12: case 13: return BorderStyle.DASHED;
                case 4: return BorderStyle.DOTTED;
                case 5: return BorderStyle.THICK;
                case 6: return BorderStyle.DOUBLE;
                default: return BorderStyle.NONE;
            }
        }

        private Gee.ArrayList<Bytes> xf_records = new Gee.ArrayList<Bytes> ();

        private void build_styles () {
            var builtin = Xlsx.builtin_formats ();
            int[] map = {};
            foreach (var xb in xf_records) {
                unowned uint8[] d = xb.get_data ();
                var st = new CellStyle ();
                int ifnt = u16 (d, 0);
                int ifmt = u16 (d, 2);
                int fi = ifnt >= 4 ? ifnt - 1 : ifnt;
                if (fi >= 0 && fi < fonts.length) {
                    var f = fonts[fi];
                    st.bold = f.bold;
                    st.italic = f.italic;
                    st.underline = f.underline;
                    st.strike = f.strike;
                    st.font_size = f.size;
                    string c = f.color == 0x7FFF || f.color == 8 ? "" : color (f.color);
                    st.color = c == "#000000" ? "" : c;
                    st.font_family = f.name == "Arial" || f.name == "Calibri" ? "" : f.name;
                }
                if (formats.has_key (ifmt)) st.number_format = formats[ifmt];
                else if (ifmt < builtin.length) st.number_format = builtin[ifmt];
                uint8 al = d.length > 6 ? d[6] : 0;
                switch (al & 7) {
                    case 1: st.halign = HAlign.LEFT; break;
                    case 2: case 6: st.halign = HAlign.CENTER; break;
                    case 3: st.halign = HAlign.RIGHT; break;
                    case 4: st.halign = HAlign.FILL; break;
                    case 5: case 7: st.halign = HAlign.JUSTIFY; break;
                }
                st.wrap = (al & 8) != 0;
                switch ((al >> 4) & 7) {
                    case 0: st.valign = VAlign.TOP; break;
                    case 1: case 3: case 4: st.valign = VAlign.CENTER; break;
                }
                if (d.length > 8) st.indent = d[8] & 0x0F;
                if (d.length >= 20) {
                    uint32 b1 = u32 (d, 10);
                    uint32 b2 = u32 (d, 14);
                    st.left = new Border (border ((int) (b1 & 0xF)), color ((int) ((b1 >> 16) & 0x7F)));
                    st.right = new Border (border ((int) ((b1 >> 4) & 0xF)), color ((int) ((b1 >> 23) & 0x7F)));
                    st.top = new Border (border ((int) ((b1 >> 8) & 0xF)), color ((int) (b2 & 0x7F)));
                    st.bottom = new Border (border ((int) ((b1 >> 12) & 0xF)), color ((int) ((b2 >> 7) & 0x7F)));
                    foreach (var b in new Border[] { st.left, st.right, st.top, st.bottom }) {
                        if (b.style == BorderStyle.NONE || b.color == "#000000") b.color = "";
                    }
                    int fls = (int) ((b2 >> 26) & 0x3F);
                    uint16 icv = u16 (d, 18);
                    if (fls != 0) {
                        string fc = color (icv & 0x7F);
                        if (fls == 1 && fc != "" && fc != "#ffffff") st.fill = fc;
                        else if (fls > 1) st.fill = fc != "" ? fc : color ((icv >> 7) & 0x7F);
                    }
                }
                map += book.intern (st);
            }
            xf_style = map;
        }

        private int style_of (int ixfe) {
            return ixfe >= 0 && ixfe < xf_style.length ? xf_style[ixfe] : 0;
        }

        private void run () throws Error {
            string[] pal = {};
            for (int i = 8; i < Xlsx.INDEXED.length; i++) pal += Xlsx.INDEXED[i];
            palette = pal;
            int pos = 0;
            var bof = read_rec (ref pos);
            if (bof == null || (bof.type != 0x0809)) throw new XlsError.FORMAT ("unsupported Excel version (only Excel 97-2003 BIFF8 files are supported)");
            if (u16 (bof.data, 0) != 0x0600) throw new XlsError.FORMAT ("unsupported Excel version (only Excel 97-2003 BIFF8 files are supported)");
            var names_raw = new Gee.ArrayList<Bytes> ();
            while (true) {
                var r = read_rec (ref pos);
                if (r == null || r.type == 0x000A) break;
                var d = r.data;
                switch (r.type) {
                    case 0x002F: throw new XlsError.ENCRYPTED ("the workbook is protected with a password");
                    case 0x0022: book.date1904 = u16 (d, 0) == 1; break;
                    case 0x0085:
                        int used;
                        sheet_pos.add ((int) u32 (d, 0));
                        sheet_names.add (d[5] == 0 ? short_string (d, 6, out used) : "\x01");
                        sheet_states.add (d[4] & 3);
                        break;
                    case 0x00FC: read_sst (d, continues (ref pos)); break;
                    case 0x041E:
                        int u2;
                        formats[u16 (d, 0)] = long_string (d, 2, out u2);
                        break;
                    case 0x0031:
                        var f = new XlsFont ();
                        f.size = u16 (d, 0) / 20.0;
                        uint16 grbit = u16 (d, 2);
                        f.italic = (grbit & 2) != 0;
                        f.strike = (grbit & 8) != 0;
                        f.color = u16 (d, 4);
                        f.bold = u16 (d, 6) >= 700;
                        f.underline = d.length > 10 && d[10] != 0;
                        int u3;
                        if (d.length > 14) f.name = short_string (d, 14, out u3);
                        fonts += f;
                        break;
                    case 0x00E0: xf_records.add (new Bytes (d)); break;
                    case 0x0092:
                        int n = u16 (d, 0);
                        string[] p = {};
                        for (int i = 0; i < n; i++) p += "%02X%02X%02X".printf (d[2 + i * 4], d[3 + i * 4], d[4 + i * 4]);
                        palette = p;
                        break;
                    case 0x01AE:
                        extern_names.add (new Gee.ArrayList<string> ());
                        if (d.length >= 4 && u16 (d, 2) == 0x0401) internal_book = extern_names.size - 1;
                        break;
                    case 0x0023:
                        if (extern_names.size == 0) extern_names.add (new Gee.ArrayList<string> ());
                        int u4;
                        string en = d.length > 6 ? short_string (d, 6, out u4) : "";
                        extern_names[extern_names.size - 1].add (en);
                        break;
                    case 0x0017:
                        int cnt = u16 (d, 0);
                        int[] f1 = {}, f2 = {}, fb = {};
                        for (int i = 0; i < cnt; i++) {
                            fb += u16 (d, 2 + i * 6);
                            f1 += s16 (d, 4 + i * 6);
                            f2 += s16 (d, 6 + i * 6);
                        }
                        xti_first = f1;
                        xti_last = f2;
                        xti_book = fb;
                        break;
                    case 0x0018:
                        names_raw.add (new Bytes (d));
                        break;
                }
            }
            build_styles ();
            var real_sheets = new Gee.ArrayList<int> ();
            for (int i = 0; i < sheet_names.size; i++) {
                if (sheet_names[i] == "\x01") continue;
                var added = book.add_sheet (sheet_names[i]);
                added.visibility = sheet_states[i];
                real_sheets.add (i);
            }
            string[] nm = {};
            foreach (var nb in names_raw) {
                unowned uint8[] d = nb.get_data ();
                int cch = d[3];
                int cce = u16 (d, 4);
                int itab = u16 (d, 8);
                bool builtin_name = (u16 (d, 0) & 0x20) != 0;
                int u5;
                string name = chars (d, 15, cch, (d[14] & 1) != 0, out u5);
                nm += builtin_name ? "_xlnm." + name : name;
                if (builtin_name && itab > 0 && cch == 1 && (d[15] == 0x06 || d[15] == 0x07)) {
                    string bname = d[15] == 0x06 ? "Print_Area" : "Print_Titles";
                    allow_union = true;
                    string? bf = decode (d[15 + u5:int.min (15 + u5 + cce, d.length)], 0, 0, null, false);
                    allow_union = false;
                    if (bf != null) {
                        try {
                            var rows_re = new Regex ("\\$A\\$(\\d+):\\$IV\\$(\\d+)");
                            var cols_re = new Regex ("\\$([A-Z]+)\\$1:\\$([A-Z]+)\\$65536");
                            bf = rows_re.replace (bf, -1, 0, "$\\1:$\\2");
                            bf = cols_re.replace (bf, -1, 0, "$\\1:$\\2");
                        } catch (RegexError e) {
                        }
                        PrintIo.apply_builtin (book, bname, itab - 1, bf);
                    }
                    continue;
                }
                if (builtin_name || (u16 (d, 0) & 1) != 0) continue;
                uint8[] rgce = d[15 + u5:int.min (15 + u5 + cce, d.length)];
                string? f = decode (rgce, 0, 0, null, false);
                if (f == null) continue;
                if (itab > 0 && itab - 1 < book.sheets.size) book.sheets[itab - 1].names[name] = f;
                else book.names[name] = f;
            }
            names = nm;
            for (int k = 0; k < real_sheets.size; k++) {
                read_sheet (book.sheets[k], sheet_pos[real_sheets[k]]);
            }
            if (book.sheets.size == 0) book.add_sheet ();
            book.recalculate ();
        }

        private void set_value (Sheet sh, int r, int c, Value v, int ixfe) {
            var cell = sh.ensure (r, c);
            cell.value = v;
            switch (v.kind) {
                case ValueKind.NUMBER: cell.input = Value.format_number_general_full (v.number); break;
                case ValueKind.TEXT: cell.input = Input.parse (v.text).value.kind == ValueKind.TEXT && !v.text.has_prefix ("=") ? v.text : "'" + v.text; break;
                case ValueKind.BOOL: cell.input = v.number != 0 ? "TRUE" : "FALSE"; break;
                case ValueKind.ERROR: cell.input = v.error.to_string (); break;
                default: break;
            }
            cell.style = style_of (ixfe);
        }

        private static ErrorKind err_code (int e) {
            switch (e) {
                case 0x00: return ErrorKind.NULL;
                case 0x07: return ErrorKind.DIV0;
                case 0x0F: return ErrorKind.VALUE;
                case 0x17: return ErrorKind.REF;
                case 0x1D: return ErrorKind.NAME;
                case 0x24: return ErrorKind.NUM;
                default: return ErrorKind.NA;
            }
        }

        private void read_sheet (Sheet sh, int start) {
            array_texts.clear ();
            array_areas.clear ();
            shared.clear ();
            int pos = start;
            var bof = read_rec (ref pos);
            if (bof == null || bof.type != 0x0809) return;
            int depth = 0;
            bool frozen = false;
            int last_obj = -1;
            int pending_r = -1, pending_c = -1, pending_x = 0;
            string pending_formula = "";
            var notes = new Gee.ArrayList<Bytes> ();
            while (true) {
                var r = read_rec (ref pos);
                if (r == null) break;
                var d = r.data;
                if (r.type == 0x0809) {
                    depth++;
                    continue;
                }
                if (r.type == 0x000A) {
                    if (depth == 0) break;
                    depth--;
                    continue;
                }
                if (depth > 0) continue;
                switch (r.type) {
                    case 0x00FD:
                        int isst = (int) u32 (d, 6);
                        set_value (sh, u16 (d, 0), u16 (d, 2), Value.str (isst < sst.length ? sst[isst] : ""), u16 (d, 4));
                        break;
                    case 0x0204:
                        int u;
                        set_value (sh, u16 (d, 0), u16 (d, 2), Value.str (long_string (d, 6, out u)), u16 (d, 4));
                        break;
                    case 0x0203:
                        set_value (sh, u16 (d, 0), u16 (d, 2), Value.num (f64 (d, 6)), u16 (d, 4));
                        break;
                    case 0x027E:
                        set_value (sh, u16 (d, 0), u16 (d, 2), Value.num (rk (u32 (d, 6))), u16 (d, 4));
                        break;
                    case 0x00BD:
                        int row = u16 (d, 0);
                        int col = u16 (d, 2);
                        for (int p = 4; p + 6 <= d.length - 2; p += 6) set_value (sh, row, col++, Value.num (rk (u32 (d, p + 2))), u16 (d, p));
                        break;
                    case 0x0201:
                        int bs = style_of (u16 (d, 4));
                        if (bs != 0) sh.set_style (u16 (d, 0), u16 (d, 2), bs);
                        break;
                    case 0x00BE:
                        int brow = u16 (d, 0);
                        int bcol = u16 (d, 2);
                        for (int p = 4; p + 2 <= d.length - 2; p += 2) {
                            int st = style_of (u16 (d, p));
                            if (st != 0) sh.set_style (brow, bcol, st);
                            bcol++;
                        }
                        break;
                    case 0x0205:
                        if (d[7] == 0) set_value (sh, u16 (d, 0), u16 (d, 2), Value.boolean (d[6] != 0), u16 (d, 4));
                        else set_value (sh, u16 (d, 0), u16 (d, 2), Value.err (err_code (d[6])), u16 (d, 4));
                        break;
                    case 0x0006:
                        int fr = u16 (d, 0), fc = u16 (d, 2), fx = u16 (d, 4);
                        Value cached;
                        bool str_follows = false;
                        if (d[12] == 0xFF && d[13] == 0xFF) {
                            switch (d[6]) {
                                case 0: cached = Value.str (""); str_follows = true; break;
                                case 1: cached = Value.boolean (d[8] != 0); break;
                                case 2: cached = Value.err (err_code (d[8])); break;
                                default: cached = Value.str (""); break;
                            }
                        } else {
                            cached = Value.num (f64 (d, 6));
                        }
                        int cce = u16 (d, 20);
                        uint8[] rgce = d[22:int.min (22 + cce, d.length)];
                        uint8[] extra = 22 + cce < d.length ? d[22 + cce:d.length] : new uint8[0];
                        if (rgce.length > 0 && rgce[0] == 0x01 && pos + 4 <= stream.length && u16 (stream, pos) == 0x04BC) {
                            int peek = pos;
                            var sr = read_rec (ref peek);
                            var sh_f = new XlsShared ();
                            sh_f.r1 = u16 (sr.data, 0);
                            sh_f.r2 = u16 (sr.data, 2);
                            sh_f.c1 = sr.data[4];
                            sh_f.c2 = sr.data[5];
                            int scce = u16 (sr.data, 8);
                            sh_f.rgce = sr.data[10:int.min (10 + scce, sr.data.length)];
                            shared.add (sh_f);
                        }
                        Area? array_ref = null;
                        if (rgce.length > 0 && rgce[0] == 0x01 && pos + 4 <= stream.length && u16 (stream, pos) == 0x0221) {
                            int peek2 = pos;
                            var ar = read_rec (ref peek2);
                            int ar1 = u16 (ar.data, 0), ar2 = u16 (ar.data, 2), ac1 = ar.data[4], ac2 = ar.data[5];
                            int acce = u16 (ar.data, 12);
                            uint8[] argce = ar.data[14:int.min (14 + acce, ar.data.length)];
                            uint8[] aextra = 14 + acce < ar.data.length ? ar.data[14 + acce:ar.data.length] : new uint8[0];
                            string? atext = decode (argce, fr, fc, aextra, true);
                            if (atext != null) {
                                array_texts["%d:%d".printf (ar1, ac1)] = atext;
                                array_areas["%d:%d".printf (ar1, ac1)] = new Area (sh, ar1, ac1, ar2, ac2);
                            }
                        }
                        if (rgce.length >= 5 && rgce[0] == 0x01) {
                            string ak = "%d:%d".printf (u16 (rgce, 1), u16 (rgce, 3));
                            if (array_areas.has_key (ak)) {
                                if (ak == "%d:%d".printf (fr, fc)) array_ref = array_areas[ak];
                                else {
                                    set_value (sh, fr, fc, cached, fx);
                                    break;
                                }
                            }
                        }
                        string? text = array_ref != null ? array_texts["%d:%d".printf (fr, fc)] : decode (rgce, fr, fc, extra, true);
                        set_value (sh, fr, fc, cached, fx);
                        if (text != null) {
                            try {
                                var node = Formula.parse ("=" + text, book, sh);
                                var cell = sh.ensure (fr, fc);
                                cell.formula = node;
                                cell.input = Formula.to_text (node, sh);
                                if (array_ref != null) cell.array_area = array_ref;
                                else cell.legacy = true;
                                cell.value = cached;
                                if (collect_cached) cached_values[cell] = cached;
                                formulas_decoded++;
                            } catch (FormulaError e) {
                                formulas_kept_value++;
                            }
                        } else {
                            formulas_kept_value++;
                        }
                        if (str_follows) {
                            pending_r = fr;
                            pending_c = fc;
                            pending_x = fx;
                            pending_formula = text ?? "";
                        }
                        break;
                    case 0x0207:
                        if (pending_r >= 0) {
                            int u;
                            string sv = long_string (d, 0, out u);
                            var cell = sh.get_cell (pending_r, pending_c);
                            if (cell != null) {
                                cell.value = Value.str (sv);
                                if (collect_cached && cached_values.has_key (cell)) cached_values[cell] = cell.value;
                                if (cell.formula == null) cell.input = sv;
                            }
                            pending_r = -1;
                        }
                        break;
                    case 0x0208:
                        int rw = u16 (d, 0);
                        int height = u16 (d, 6);
                        uint32 flags = u32 (d, 12);
                        if ((flags & 0x20) != 0) sh.hidden_rows.add (rw);
                        if ((flags & 0x40) != 0 && (height & 0x8000) == 0) sh.row_heights[rw] = (int) Math.round (height / 20.0 / 0.75 * Xlsx.ROW_SCALE);
                        break;
                    case 0x007D:
                        int c1 = u16 (d, 0), c2 = u16 (d, 2);
                        int w = u16 (d, 4);
                        bool hidden = (u16 (d, 8) & 1) != 0;
                        for (int c = c1; c <= int.min (c2, 255); c++) {
                            sh.col_widths[c] = (int) Math.round ((w / 256.0 * 7 + 5) * Xlsx.COL_SCALE);
                            if (hidden) sh.hidden_cols.add (c);
                        }
                        break;
                    case 0x0055:
                        sh.default_col_width = (int) Math.round ((u16 (d, 0) * 7 + 5) * Xlsx.COL_SCALE);
                        break;
                    case 0x00E5:
                        int n = u16 (d, 0);
                        for (int i = 0; i < n; i++) {
                            int o = 2 + i * 8;
                            var a = new Area (sh, u16 (d, o), u16 (d, o + 4), u16 (d, o + 2), u16 (d, o + 6));
                            if (!a.is_single ()) sh.merges.add (a);
                        }
                        break;
                    case 0x023E:
                        uint16 g = u16 (d, 0);
                        if ((g & 2) == 0) sh.show_grid = false;
                        frozen = (g & 8) != 0;
                        break;
                    case 0x0041:
                        if (frozen) {
                            sh.freeze_cols = u16 (d, 0);
                            sh.freeze_rows = u16 (d, 2);
                        }
                        break;
                    case 0x005D:
                        if (d.length >= 6 && u16 (d, 0) == 0x15) last_obj = u16 (d, 6);
                        break;
                    case 0x01B6:
                        int cch = u16 (d, 10);
                        var parts = continues (ref pos);
                        var sb = new StringBuilder ();
                        int got = 0;
                        foreach (var cb in parts) {
                            unowned uint8[] cd = cb.get_data ();
                            if (got >= cch) break;
                            bool wide = cd.length > 0 && (cd[0] & 1) != 0;
                            int u;
                            string piece = chars (cd, 1, cch - got, wide, out u);
                            sb.append (piece);
                            got += piece.char_count ();
                        }
                        if (last_obj >= 0) obj_text[last_obj] = sb.str.replace ("\r\n", "\n").replace ("\r", "\n");
                        break;
                    case 0x001C:
                        notes.add (new Bytes (d));
                        break;
                    case 0x01B8:
                        read_hlink (sh, d);
                        break;
                    case 0x01B0:
                        cf_areas.clear ();
                        int cref = u16 (d, 12);
                        for (int i = 0; i < cref; i++) {
                            int o = 14 + i * 8;
                            cf_areas.add (new Area (sh, u16 (d, o), u16 (d, o + 4), u16 (d, o + 2), u16 (d, o + 6)));
                        }
                        break;
                    case 0x01B1:
                        read_cf (sh, d);
                        break;
                    case 0x01BE:
                        read_dv (sh, d);
                        break;
                    case 0x0862:
                        if (d.length >= 20) {
                            string tc = color ((int) (u32 (d, 16) & 0x7F));
                            if (tc != "" && (u32 (d, 16) & 0x7F) != 0x7F) sh.tab_color = tc;
                        }
                        break;
                }
            }
            foreach (var ntb in notes) {
                unowned uint8[] d = ntb.get_data ();
                int nr = u16 (d, 0), nc = u16 (d, 2);
                int id = u16 (d, 6);
                int u;
                string author = d.length > 8 ? long_string (d, 8, out u) : "";
                var cell = sh.ensure (nr, nc);
                string text = obj_text.has_key (id) ? obj_text[id] : "";
                if (author != "" && text.has_prefix (author + ":")) text = text.substring (author.length + 1);
                cell.note = text.strip ();
                cell.note_author = author;
            }
            sh.recompute_extent ();
        }

        private static string utf16 (uint8[] d, int o, int chars_n) {
            var sb = new StringBuilder ();
            for (int i = 0; i < chars_n && o + i * 2 + 1 < d.length; i++) {
                unichar ch = (unichar) u16 (d, o + i * 2);
                if (ch == 0) break;
                sb.append_unichar (ch);
            }
            return sb.str;
        }

        private void read_hlink (Sheet sh, uint8[] d) {
            int r1 = u16 (d, 0), r2 = u16 (d, 2), c1 = u16 (d, 4), c2 = u16 (d, 6);
            int p = 8 + 16 + 4;
            uint32 flags = u32 (d, p);
            p += 4;
            if ((flags & 0x10) != 0) {
                int n = (int) u32 (d, p);
                p += 4 + n * 2;
            }
            if ((flags & 0x80) != 0) {
                int n = (int) u32 (d, p);
                p += 4 + n * 2;
            }
            string url = "";
            if ((flags & 0x01) != 0 && (flags & 0x100) == 0) {
                bool is_url = d.length > p + 16 && d[p] == 0xE0 && d[p + 1] == 0xC9;
                bool is_file = d.length > p + 16 && d[p] == 0x03 && d[p + 1] == 0x03;
                p += 16;
                if (is_url) {
                    int bytes = (int) u32 (d, p);
                    p += 4;
                    url = utf16 (d, p, bytes / 2);
                    p += bytes;
                } else if (is_file) {
                    p += 2;
                    int n = (int) u32 (d, p);
                    p += 4;
                    var sb = new StringBuilder ();
                    for (int i = 0; i < n - 1 && p + i < d.length; i++) sb.append_c ((char) d[p + i]);
                    url = sb.str;
                    p += n + 24;
                    int ext = (int) u32 (d, p);
                    p += 4;
                    if (ext > 0) p += ext;
                } else {
                    return;
                }
            } else if ((flags & 0x100) != 0) {
                int n = (int) u32 (d, p);
                p += 4;
                url = utf16 (d, p, n);
                p += n * 2;
            }
            if ((flags & 0x08) != 0) {
                int n = (int) u32 (d, p);
                p += 4;
                string loc = utf16 (d, p, n);
                url = url == "" ? "#" + loc : url + "#" + loc;
            }
            if (url == "") return;
            for (int r = r1; r <= r2 && r - r1 < 1000; r++) {
                for (int c = c1; c <= c2 && c - c1 < 256; c++) sh.ensure (r, c).link = url;
            }
        }

        private Gee.ArrayList<Area> cf_areas = new Gee.ArrayList<Area> ();

        private void read_cf (Sheet sh, uint8[] d) {
            if (cf_areas.size == 0 || d.length < 12) return;
            int ct = d[0], cp = d[1];
            int cce1 = u16 (d, 2), cce2 = u16 (d, 4);
            uint32 flags = u32 (d, 6);
            int p = 12;
            var st = new CellStyle ();
            if ((flags & 0x04000000) != 0 && p + 118 <= d.length) {
                int icv = (int) u32 (d, p + 80);
                if (icv >= 0 && icv < 0x7FFF) st.color = color (icv);
                if (u32 (d, p + 100) == 0) st.bold = u16 (d, p + 72) >= 700;
                uint32 tsn = u32 (d, p + 88);
                uint32 ts = u32 (d, p + 68);
                if ((tsn & 0x2) == 0) st.italic = (ts & 0x2) != 0;
                if ((tsn & 0x80) == 0) st.strike = (ts & 0x80) != 0;
                if (u32 (d, p + 96) == 0) st.underline = d[p + 76] != 0;
                p += 118;
            }
            if ((flags & 0x08000000) != 0) p += 8;
            if ((flags & 0x10000000) != 0) p += 8;
            if ((flags & 0x20000000) != 0 && p + 4 <= d.length) {
                int fls = u16 (d, p) >> 10;
                int icvs = u16 (d, p + 2);
                int fore = icvs & 0x7F, back = (icvs >> 7) & 0x7F;
                if (fls != 0) st.fill = color (fls == 1 ? (back != 64 && back != 65 ? back : fore) : back);
                p += 4;
            }
            if ((flags & 0x40000000) != 0) p += 2;
            if (p + cce1 + cce2 > d.length) return;
            var base_area = cf_areas[0];
            string? f1 = cce1 > 0 ? decode (d[p:p + cce1], base_area.r1, base_area.c1, null, true) : "";
            string? f2 = cce2 > 0 ? decode (d[p + cce1:p + cce1 + cce2], base_area.r1, base_area.c1, null, true) : "";
            if (f1 == null || f2 == null) return;
            CondKind kind;
            if (ct == 2) kind = CondKind.FORMULA;
            else {
                switch (cp) {
                    case 1: kind = CondKind.BETWEEN; break;
                    case 3: kind = CondKind.EQUAL; break;
                    case 4: kind = CondKind.NOT_EQUAL; break;
                    case 5: case 7: kind = CondKind.GREATER; break;
                    case 6: case 8: kind = CondKind.LESS; break;
                    default: return;
                }
            }
            int style = book.intern (st);
            foreach (var a in cf_areas) {
                var cf = new CondFormat (a, kind);
                cf.a = kind == CondKind.FORMULA ? "=" + f1 : f1;
                cf.b = f2;
                cf.style = style;
                sh.cond_formats.add (cf);
            }
        }

        private static string dv_str (uint8[] d, ref int p) {
            int u;
            string t = long_string (d, p, out u);
            p += u;
            return t;
        }

        private void read_dv (Sheet sh, uint8[] d) {
            if (d.length < 4) return;
            uint32 flags = u32 (d, 0);
            int p = 4;
            string ptitle = dv_str (d, ref p);
            string etitle = dv_str (d, ref p);
            string prompt = dv_str (d, ref p);
            string error = dv_str (d, ref p);
            if (p + 4 > d.length) return;
            int c1 = u16 (d, p);
            uint8[] r1 = d[p + 4:int.min (p + 4 + c1, d.length)];
            p += 4 + c1;
            int c2 = u16 (d, p);
            uint8[] r2 = d[int.min (p + 4, d.length):int.min (p + 4 + c2, d.length)];
            p += 4 + c2;
            int cref = u16 (d, p);
            p += 2;
            var areas = new Gee.ArrayList<Area> ();
            for (int i = 0; i < cref && p + 8 <= d.length; i++, p += 8) areas.add (new Area (sh, u16 (d, p), u16 (d, p + 4), u16 (d, p + 2), u16 (d, p + 6)));
            if (areas.size == 0) return;
            int type = (int) (flags & 0xF);
            ValidationKind[] kinds = { ValidationKind.ANY, ValidationKind.WHOLE, ValidationKind.DECIMAL, ValidationKind.LIST, ValidationKind.DATE, ValidationKind.TIME, ValidationKind.TEXT_LENGTH, ValidationKind.CUSTOM };
            ValidationOp[] ops = { ValidationOp.BETWEEN, ValidationOp.NOT_BETWEEN, ValidationOp.EQUAL, ValidationOp.NOT_EQUAL, ValidationOp.GREATER, ValidationOp.LESS, ValidationOp.GREATER_EQUAL, ValidationOp.LESS_EQUAL };
            string f1 = "", f2 = "";
            if ((flags & 0x80) != 0 && r1.length > 3 && r1[0] == 0x17) {
                int cch = r1[1];
                bool wide = (r1[2] & 1) != 0;
                var sb = new StringBuilder ();
                int q = 3;
                for (int i = 0; i < cch && q < r1.length; i++) {
                    unichar ch = wide ? (unichar) u16 (r1, q) : (unichar) r1[q];
                    q += wide ? 2 : 1;
                    if (ch == 0) sb.append_c (',');
                    else sb.append_unichar (ch);
                }
                f1 = "\"" + sb.str + "\"";
            } else if (r1.length > 0) {
                f1 = decode (r1, areas[0].r1, areas[0].c1, null, true) ?? "";
            }
            if (r2.length > 0) f2 = decode (r2, areas[0].r1, areas[0].c1, null, true) ?? "";
            foreach (var a in areas) {
                var v = new Validation (a);
                v.kind = type < kinds.length ? kinds[type] : ValidationKind.ANY;
                v.op = ops[(flags >> 20) & 7];
                v.formula1 = f1;
                v.formula2 = f2;
                if (v.kind == ValidationKind.LIST) v.list_source = f1;
                v.alert = ((flags >> 4) & 7) == 1 ? ValidationAlert.WARNING : (((flags >> 4) & 7) == 2 ? ValidationAlert.INFORMATION : ValidationAlert.STOP);
                v.allow_blank = (flags & 0x100) != 0;
                v.dropdown = (flags & 0x200) == 0;
                v.show_input = (flags & 0x40000) != 0;
                v.show_error = (flags & 0x80000) != 0;
                v.input_title = ptitle;
                v.error_title = etitle;
                v.message = prompt;
                v.error_message = error;
                sh.validations.add (v);
            }
        }

        private string sheet_ref (int ixti) {
            if (ixti < 0 || ixti >= xti_first.length) return "#REF!";
            if (ixti < xti_book.length && xti_book[ixti] != internal_book) return "#REF!";
            int a = xti_first[ixti], b = xti_last[ixti];
            if (a < 0 || a >= sheet_names.size) return "#REF!";
            string n1 = sheet_name_at (a);
            if (b == a || b < 0 || b >= sheet_names.size) return Address.quote_sheet (n1) + "!";
            string n2 = sheet_name_at (b);
            if (Address.quote_sheet (n1) == n1 && Address.quote_sheet (n2) == n2) return n1 + ":" + n2 + "!";
            return "'" + (n1 + ":" + n2).replace ("'", "''") + "'!";
        }

        private string sheet_name_at (int idx) {
            return sheet_names[idx];
        }

        private static string cell_text (int row, int colf, int base_r, int base_c, bool relative_mode) {
            bool col_rel = (colf & 0x4000) != 0;
            bool row_rel = (colf & 0x8000) != 0;
            int col = colf & 0x3FFF;
            int r = row;
            if (relative_mode) {
                if (row_rel) r = base_r + (int16) row;
                if (col_rel) col = base_c + (int8) (col & 0xFF);
            }
            if (r < 0 || col < 0 || r >= MAX_ROWS || col >= MAX_COLS) return "#REF!";
            return Address.cell (r, col, !row_rel, !col_rel);
        }

        private static string binop (int id) {
            switch (id) {
                case 0x03: return "+";
                case 0x04: return "-";
                case 0x05: return "*";
                case 0x06: return "/";
                case 0x07: return "^";
                case 0x08: return "&";
                case 0x09: return "<";
                case 0x0A: return "<=";
                case 0x0B: return "=";
                case 0x0C: return ">=";
                case 0x0D: return ">";
                case 0x0E: return "<>";
                case 0x0F: return " ";
                case 0x10: return ",";
                case 0x11: return ":";
                default: return "";
            }
        }

        private static int op_prec (string op) {
            switch (op) {
                case ":": return 8;
                case "^": return 5;
                case "*": case "/": return 4;
                case "+": case "-": return 3;
                case "&": return 2;
                default: return 1;
            }
        }

        private static string wrap (Gee.ArrayList<string> stack, Gee.ArrayList<int> precs, int need) {
            int pr = precs.remove_at (precs.size - 1);
            string t = stack.remove_at (stack.size - 1);
            return pr < need ? "(" + t + ")" : t;
        }

        private static string num_text (double v) {
            return Value.format_number_general_full (v);
        }

        private static string xl_string (string s) {
            return "\"" + s.replace ("\"", "\"\"") + "\"";
        }

        private string? decode (uint8[] rgce, int base_r, int base_c, uint8[]? extra, bool cell_formula) {
            var stack = new Gee.ArrayList<string> ();
            var precs = new Gee.ArrayList<int> ();
            int p = 0;
            int ep = 0;
            while (p < rgce.length) {
                int id = rgce[p++];
                int bid = id >= 0x20 ? ((id & 0x1F) | 0x20) : id;
                switch (bid) {
                    case 0x01:
                        int sr = u16 (rgce, p), sc = u16 (rgce, p + 2);
                        p += 4;
                        foreach (var s in shared) {
                            if (s.r1 == sr && s.c1 == sc) return decode (s.rgce, base_r, base_c, extra, true);
                        }
                        foreach (var s in shared) {
                            if (base_r >= s.r1 && base_r <= s.r2 && base_c >= s.c1 && base_c <= s.c2) return decode (s.rgce, base_r, base_c, extra, true);
                        }
                        return null;
                    case 0x03: case 0x04: case 0x05: case 0x06: case 0x07: case 0x08: case 0x09: case 0x0A:
                    case 0x0B: case 0x0C: case 0x0D: case 0x0E: case 0x0F: case 0x10: case 0x11:
                        if (stack.size < 2) return null;
                        int pb = precs.remove_at (precs.size - 1);
                        string b = stack.remove_at (stack.size - 1);
                        int pa = precs.remove_at (precs.size - 1);
                        string a = stack.remove_at (stack.size - 1);
                        string op = binop (bid);
                        if (op == " " || (op == "," && !allow_union)) return null;
                        int po = op_prec (op);
                        if (pa < po) a = "(" + a + ")";
                        if (pb < po || (pb == po && op != ":")) b = "(" + b + ")";
                        stack.add (a + op + b);
                        precs.add (po);
                        break;
                    case 0x12:
                        if (stack.size < 1) return null;
                        stack.add ("+" + wrap (stack, precs, 6));
                        precs.add (6);
                        break;
                    case 0x13:
                        if (stack.size < 1) return null;
                        stack.add ("-" + wrap (stack, precs, 6));
                        precs.add (6);
                        break;
                    case 0x14:
                        if (stack.size < 1) return null;
                        stack.add (wrap (stack, precs, 7) + "%");
                        precs.add (7);
                        break;
                    case 0x15:
                        if (stack.size < 1) return null;
                        precs.remove_at (precs.size - 1);
                        stack.add ("(" + stack.remove_at (stack.size - 1) + ")");
                        precs.add (9);
                        break;
                    case 0x16:
                        stack.add ("");
                        precs.add (9);
                        break;
                    case 0x17:
                        int cch = rgce[p];
                        int u;
                        string s = chars (rgce, p + 2, cch, (rgce[p + 1] & 1) != 0, out u);
                        p += 2 + u;
                        stack.add (xl_string (s));
                        precs.add (9);
                        break;
                    case 0x18:
                        return null;
                    case 0x19:
                        int kind = rgce[p];
                        if ((kind & 0x04) != 0) {
                            int count = u16 (rgce, p + 1);
                            p += 3 + (count + 1) * 2;
                        } else {
                            p += 3;
                        }
                        if ((kind & 0x10) != 0) {
                            if (stack.size < 1) return null;
                            precs.remove_at (precs.size - 1);
                            stack.add ("SUM(" + stack.remove_at (stack.size - 1) + ")");
                            precs.add (9);
                        }
                        break;
                    case 0x1C:
                        stack.add (err_code (rgce[p++]).to_string ());
                        precs.add (9);
                        break;
                    case 0x1D:
                        stack.add (rgce[p++] != 0 ? "TRUE" : "FALSE");
                        precs.add (9);
                        break;
                    case 0x1E:
                        stack.add (num_text (u16 (rgce, p)));
                        precs.add (9);
                        p += 2;
                        break;
                    case 0x1F:
                        stack.add (num_text (f64 (rgce, p)));
                        precs.add (9);
                        p += 8;
                        break;
                    case 0x20:
                        p += 7;
                        if (extra == null) return null;
                        int cols = extra[ep] + 1;
                        int rows = u16 (extra, ep + 1) + 1;
                        ep += 3;
                        var sb = new StringBuilder ("{");
                        for (int i = 0; i < rows; i++) {
                            if (i > 0) sb.append (";");
                            for (int j = 0; j < cols; j++) {
                                if (j > 0) sb.append (",");
                                int t = extra[ep++];
                                switch (t) {
                                    case 0x01: sb.append (num_text (f64 (extra, ep))); ep += 8; break;
                                    case 0x02:
                                        int u2;
                                        sb.append (xl_string (long_string (extra, ep, out u2)));
                                        ep += u2;
                                        break;
                                    case 0x04: sb.append (extra[ep] != 0 ? "TRUE" : "FALSE"); ep += 8; break;
                                    case 0x10: sb.append (err_code (extra[ep]).to_string ()); ep += 8; break;
                                    default: sb.append ("0"); ep += 8; break;
                                }
                            }
                        }
                        sb.append ("}");
                        stack.add (sb.str);
                        precs.add (9);
                        break;
                    case 0x21:
                    case 0x22:
                        int argc;
                        int iftab;
                        if (bid == 0x21) {
                            iftab = u16 (rgce, p);
                            p += 2;
                            argc = XlsFunctions.arity (iftab);
                            if (argc < 0) return null;
                        } else {
                            argc = rgce[p] & 0x7F;
                            iftab = u16 (rgce, p + 1) & 0x7FFF;
                            p += 3;
                        }
                        if (stack.size < argc) return null;
                        string[] args = new string[argc];
                        for (int i = argc - 1; i >= 0; i--) {
                            args[i] = stack.remove_at (stack.size - 1);
                            precs.remove_at (precs.size - 1);
                        }
                        string fname;
                        if (iftab == 255) {
                            if (argc < 1) return null;
                            fname = args[0];
                            args = args[1:args.length];
                        } else {
                            fname = XlsFunctions.name (iftab);
                            if (fname == "") return null;
                        }
                        stack.add (fname + "(" + string.joinv (",", args) + ")");
                        precs.add (9);
                        break;
                    case 0x23:
                        int ni = (int) u32 (rgce, p) - 1;
                        p += 4;
                        if (ni < 0 || ni >= names.length) return null;
                        stack.add (names[ni]);
                        precs.add (9);
                        break;
                    case 0x24:
                    case 0x2C:
                        stack.add (cell_text (u16 (rgce, p), u16 (rgce, p + 2), base_r, base_c, bid == 0x2C));
                        precs.add (9);
                        p += 4;
                        break;
                    case 0x25:
                    case 0x2D:
                        string ca = cell_text (u16 (rgce, p), u16 (rgce, p + 4), base_r, base_c, bid == 0x2D);
                        string cb = cell_text (u16 (rgce, p + 2), u16 (rgce, p + 6), base_r, base_c, bid == 0x2D);
                        p += 8;
                        stack.add (ca + ":" + cb);
                        precs.add (9);
                        break;
                    case 0x26:
                    case 0x27:
                        p += 6;
                        break;
                    case 0x28:
                    case 0x29:
                        p += 2;
                        break;
                    case 0x2A:
                        p += 4;
                        stack.add ("#REF!");
                        precs.add (9);
                        break;
                    case 0x2B:
                        p += 8;
                        stack.add ("#REF!");
                        precs.add (9);
                        break;
                    case 0x39:
                        int ixti = u16 (rgce, p);
                        int iname = (int) u32 (rgce, p + 2) - 1;
                        p += 6;
                        string xn = "";
                        if (ixti < xti_book.length) {
                            int sb_i = xti_book[ixti];
                            if (sb_i < extern_names.size && iname >= 0 && iname < extern_names[sb_i].size) xn = extern_names[sb_i][iname];
                        }
                        if (xn == "") return null;
                        if (xn.has_prefix ("_xlfn.")) xn = xn.substring (6);
                        stack.add (xn);
                        precs.add (9);
                        break;
                    case 0x3A:
                        string pre = sheet_ref (u16 (rgce, p));
                        stack.add (pre == "#REF!" ? pre : pre + cell_text (u16 (rgce, p + 2), u16 (rgce, p + 4), base_r, base_c, false));
                        precs.add (9);
                        p += 6;
                        break;
                    case 0x3B:
                        string pre2 = sheet_ref (u16 (rgce, p));
                        string a1 = cell_text (u16 (rgce, p + 2), u16 (rgce, p + 6), base_r, base_c, false);
                        string a2 = cell_text (u16 (rgce, p + 4), u16 (rgce, p + 8), base_r, base_c, false);
                        p += 10;
                        stack.add (pre2 == "#REF!" ? pre2 : pre2 + a1 + ":" + a2);
                        precs.add (9);
                        break;
                    case 0x3C:
                        p += 6;
                        stack.add ("#REF!");
                        precs.add (9);
                        break;
                    case 0x3D:
                        p += 10;
                        stack.add ("#REF!");
                        precs.add (9);
                        break;
                    default:
                        return null;
                }
            }
            if (stack.size != 1) return null;
            return stack[0];
        }
    }
}
