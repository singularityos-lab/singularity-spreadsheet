namespace Singularity.Apps.Spreadsheet {

    public class BiffBuf {
        public ByteArray b = new ByteArray ();

        public uint len {
            get { return b.len; }
        }

        public void u8 (uint v) {
            uint8[] x = { (uint8) (v & 0xff) };
            b.append (x);
        }

        public void u16 (uint v) {
            uint8[] x = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff) };
            b.append (x);
        }

        public void u32 (uint64 v) {
            uint8[] x = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
            b.append (x);
        }

        public void f64 (double d) {
            uint64 bits = 0;
            Memory.copy (&bits, &d, 8);
            u32 (bits & 0xffffffff);
            u32 (bits >> 32);
        }

        public void zeros (int n) {
            for (int i = 0; i < n; i++) u8 (0);
        }

        public void bytes (uint8[] d) {
            b.append (d);
        }

        public void append (BiffBuf o) {
            b.append (o.b.data);
        }

        public void set_u16 (uint at, uint v) {
            b.data[at] = (uint8) (v & 0xff);
            b.data[at + 1] = (uint8) ((v >> 8) & 0xff);
        }

        public void set_u32 (uint at, uint64 v) {
            b.data[at] = (uint8) (v & 0xff);
            b.data[at + 1] = (uint8) ((v >> 8) & 0xff);
            b.data[at + 2] = (uint8) ((v >> 16) & 0xff);
            b.data[at + 3] = (uint8) ((v >> 24) & 0xff);
        }

        public static bool narrow (string s) {
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) if (c > 0xff) return false;
            return true;
        }

        public void chars (string s, bool wide) {
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                if (wide) u16 (c > 0xffff ? 0xfffd : c);
                else u8 (c);
            }
        }

        public void short_string (string s) {
            string t = clip (s, 255);
            bool wide = !narrow (t);
            u8 (t.char_count ());
            u8 (wide ? 1 : 0);
            chars (t, wide);
        }

        public void long_string (string s) {
            string t = clip (s, 32767);
            bool wide = !narrow (t);
            u16 (t.char_count ());
            u8 (wide ? 1 : 0);
            chars (t, wide);
        }

        public static string clip (string s, int n) {
            if (s.char_count () <= n) return s;
            return s.substring (0, s.index_of_nth_char (n));
        }

        public void record (int type, BiffBuf? body) {
            uint8[] data = body != null ? body.b.data : new uint8[0];
            int len = data.length;
            int first = int.min (len, 8224);
            u16 (type);
            u16 (first);
            if (first > 0) b.append (data[0:first]);
            int p = first;
            while (p < len) {
                int n = int.min (len - p, 8224);
                u16 (0x003C);
                u16 (n);
                b.append (data[p:p + n]);
                p += n;
            }
        }
    }

    public class XlsCfbWriter {
        public static uint8[] build (string stream_name, uint8[] stream) {
            var data = new ByteArray ();
            data.append (stream);
            while (data.len < 4096) {
                uint8[] z = { 0 };
                data.append (z);
            }
            while (data.len % 512 != 0) {
                uint8[] z = { 0 };
                data.append (z);
            }
            int n = (int) data.len / 512;
            int f = 1, d = 0;
            while (true) {
                int total = n + 1 + f + d;
                int nf = (total + 127) / 128;
                int nd = nf > 109 ? (nf - 109 + 126) / 127 : 0;
                if (nf == f && nd == d) break;
                f = nf;
                d = nd;
            }
            int fat_start = 0;
            int difat_start = f;
            int dir_sector = f + d;
            int stream_start = dir_sector + 1;
            var hdr = new BiffBuf ();
            uint8[] sig = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };
            hdr.bytes (sig);
            hdr.zeros (16);
            hdr.u16 (0x3E);
            hdr.u16 (3);
            hdr.u16 (0xFFFE);
            hdr.u16 (9);
            hdr.u16 (6);
            hdr.zeros (6);
            hdr.u32 (0);
            hdr.u32 (f);
            hdr.u32 (dir_sector);
            hdr.u32 (0);
            hdr.u32 (4096);
            hdr.u32 (0xFFFFFFFE);
            hdr.u32 (0);
            hdr.u32 (d > 0 ? difat_start : 0xFFFFFFFE);
            hdr.u32 (d);
            for (int i = 0; i < 109; i++) hdr.u32 (i < f ? fat_start + i : 0xFFFFFFFF);
            var fat = new BiffBuf ();
            for (int i = 0; i < f; i++) fat.u32 (0xFFFFFFFD);
            for (int i = 0; i < d; i++) fat.u32 (0xFFFFFFFC);
            fat.u32 (0xFFFFFFFE);
            for (int i = 0; i < n; i++) fat.u32 (i == n - 1 ? 0xFFFFFFFE : (uint64) (stream_start + i + 1));
            while (fat.len < f * 512) fat.u32 (0xFFFFFFFF);
            var difat = new BiffBuf ();
            int next_fat = 109;
            for (int k = 0; k < d; k++) {
                for (int i = 0; i < 127; i++) {
                    difat.u32 (next_fat < f ? fat_start + next_fat : 0xFFFFFFFF);
                    next_fat++;
                }
                difat.u32 (k == d - 1 ? 0xFFFFFFFE : (uint64) (difat_start + k + 1));
            }
            var dir = new BiffBuf ();
            string[] names = { "Root Entry", stream_name };
            for (int e = 0; e < 4; e++) {
                string nm = e < 2 ? names[e] : "";
                for (int i = 0; i < 32; i++) dir.u16 (i < nm.length ? nm[i] : 0);
                dir.u16 (nm.length > 0 ? (nm.length + 1) * 2 : 0);
                dir.u8 (e == 0 ? 5 : (e == 1 ? 2 : 0));
                dir.u8 (1);
                dir.u32 (0xFFFFFFFF);
                dir.u32 (0xFFFFFFFF);
                dir.u32 (e == 0 ? 1 : 0xFFFFFFFF);
                dir.zeros (36);
                dir.u32 (e == 0 ? 0xFFFFFFFE : (e == 1 ? (uint64) stream_start : 0));
                dir.u32 (e == 1 ? int.max (stream.length, 4096) : 0);
                dir.u32 (0);
            }
            var file = new ByteArray ();
            file.append (hdr.b.data);
            file.append (fat.b.data);
            file.append (difat.b.data);
            file.append (dir.b.data);
            file.append (data.data);
            return file.steal ();
        }
    }

    private class XlsFontKey {
        public string key;
        public CellStyle style;
    }

    private class XlsNote {
        public Cell cell;
        public int id;
    }

    public class XlsWriter {
        public Workbook book;
        public bool b12;
        public Gee.ArrayList<string> future_names = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> sst = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, int> sst_index = new Gee.HashMap<string, int> ();
        private int sst_total = 0;
        private string[] palette = {};
        private Gee.ArrayList<XlsFontKey> fonts = new Gee.ArrayList<XlsFontKey> ();
        private int[] style_font = {};
        private Gee.HashMap<string, int> formats = new Gee.HashMap<string, int> ();
        public Gee.ArrayList<string> xti = new Gee.ArrayList<string> ();
        public Gee.HashMap<string, int> name_index = new Gee.HashMap<string, int> ();
        private Gee.ArrayList<string> addin_names = new Gee.ArrayList<string> ();

        private const string[] ATP = {
            "ACCRINT", "ACCRINTM", "AMORDEGRC", "AMORLINC", "BESSELI", "BESSELJ", "BESSELK", "BESSELY", "BIN2DEC", "BIN2HEX",
            "BIN2OCT", "COMPLEX", "CONVERT", "COUPDAYBS", "COUPDAYS", "COUPDAYSNC", "COUPNCD", "COUPNUM", "COUPPCD", "CUMIPMT",
            "CUMPRINC", "DEC2BIN", "DEC2HEX", "DEC2OCT", "DELTA", "DISC", "DOLLARDE", "DOLLARFR", "DURATION", "EDATE", "EFFECT",
            "EOMONTH", "ERF", "ERFC", "FACTDOUBLE", "FVSCHEDULE", "GCD", "GESTEP", "HEX2BIN", "HEX2DEC", "HEX2OCT", "IMABS",
            "IMAGINARY", "IMARGUMENT", "IMCONJUGATE", "IMCOS", "IMDIV", "IMEXP", "IMLN", "IMLOG10", "IMLOG2", "IMPOWER",
            "IMPRODUCT", "IMREAL", "IMSIN", "IMSQRT", "IMSUB", "IMSUM", "INTRATE", "ISEVEN", "ISODD", "LCM", "MDURATION",
            "MROUND", "MULTINOMIAL", "NETWORKDAYS", "NOMINAL", "OCT2BIN", "OCT2DEC", "OCT2HEX", "ODDFPRICE", "ODDFYIELD",
            "ODDLPRICE", "ODDLYIELD", "PRICE", "PRICEDISC", "PRICEMAT", "QUOTIENT", "RANDBETWEEN", "RECEIVED", "SERIESSUM",
            "SQRTPI", "TBILLEQ", "TBILLPRICE", "TBILLYIELD", "WEEKNUM", "WORKDAY", "XIRR", "XNPV", "YEARFRAC", "YIELD",
            "YIELDDISC", "YIELDMAT"
        };

        private int addin_index (string fname) {
            bool atp = false;
            foreach (string a in ATP) if (a == fname) atp = true;
            string full = atp ? fname : "_xlfn." + fname;
            int i = addin_names.index_of (full);
            if (i >= 0) return i;
            addin_names.add (full);
            return addin_names.size - 1;
        }
        private int drawing_count = 0;
        private int total_shapes = 0;
        private int max_spid = 0;
        private Gee.ArrayList<int> dg_shapes = new Gee.ArrayList<int> ();
        public int formulas_written;
        public int formulas_as_values;
        public int cells_dropped;
        public Gee.HashSet<string> unsupported = new Gee.HashSet<string> ();
        private string fail_reason = "";

        public static XlsWriter save (Workbook book, string path) throws Error {
            var w = new XlsWriter ();
            w.book = book;
            var stream = w.build ();
            FileUtils.set_data (path, XlsCfbWriter.build ("Workbook", stream));
            return w;
        }

        private int color_index (string hex) {
            if (hex == "") return -1;
            string h = hex.has_prefix ("#") ? hex.substring (1).up () : hex.up ();
            for (int i = 0; i < palette.length; i++) if (palette[i] == h) return i + 8;
            int best = 8;
            int best_d = int.MAX;
            int r = Xlsx.hex2 (h, 0), g = Xlsx.hex2 (h, 2), bl = Xlsx.hex2 (h, 4);
            for (int i = 0; i < palette.length; i++) {
                int dr = Xlsx.hex2 (palette[i], 0) - r, dg = Xlsx.hex2 (palette[i], 2) - g, db = Xlsx.hex2 (palette[i], 4) - bl;
                int dist = dr * dr + dg * dg + db * db;
                if (dist < best_d) {
                    best_d = dist;
                    best = i + 8;
                }
            }
            return best;
        }

        private void build_palette () {
            string[] pal = {};
            for (int i = 8; i < 64; i++) pal += Xlsx.INDEXED[i];
            var used = new Gee.ArrayList<string> ();
            foreach (var st in book.styles) {
                foreach (string c in new string[] { st.color, st.fill, st.top.color, st.bottom.color, st.left.color, st.right.color }) {
                    if (c == "" || c.length != 7) continue;
                    string h = c.substring (1).up ();
                    bool present = false;
                    foreach (string p in pal) if (p == h) present = true;
                    if (!present && !used.contains (h)) used.add (h);
                }
            }
            foreach (var sh in book.sheets) {
                if (sh.tab_color.length != 7) continue;
                string h = sh.tab_color.substring (1).up ();
                bool present = false;
                foreach (string p in pal) if (p == h) present = true;
                if (!present && !used.contains (h)) used.add (h);
            }
            int slot = pal.length - 1;
            foreach (string h in used) {
                if (slot < 8) break;
                pal[slot--] = h;
            }
            palette = pal;
        }

        private string font_key (CellStyle s) {
            return "%d%d%d%d|%s|%s|%s".printf ((int) s.bold, (int) s.italic, (int) s.underline, (int) s.strike, Value.fixed (s.font_size, 2), s.color, s.font_family);
        }

        private void build_fonts () {
            int[] map = {};
            foreach (var st in book.styles) {
                string k = font_key (st);
                int idx = -1;
                for (int i = 0; i < fonts.size; i++) if (fonts[i].key == k) idx = i;
                if (idx < 0) {
                    var fk = new XlsFontKey ();
                    fk.key = k;
                    fk.style = st;
                    fonts.add (fk);
                    idx = fonts.size - 1;
                }
                map += idx;
            }
            style_font = map;
        }

        private int font_record_index (int i) {
            return i >= 4 ? i + 1 : i;
        }

        private void font_record (BiffBuf out_b, CellStyle s) {
            var f = new BiffBuf ();
            f.u16 ((int) Math.round (s.font_size * 20));
            f.u16 ((s.italic ? 2 : 0) | (s.strike ? 8 : 0));
            int ci = color_index (s.color);
            f.u16 (ci < 0 ? 0x7FFF : ci);
            f.u16 (s.bold ? 700 : 400);
            f.u16 (0);
            f.u8 (s.underline ? 1 : 0);
            f.u8 (2);
            f.u8 (0);
            f.u8 (0);
            f.short_string (s.font_family != "" ? s.font_family : "Calibri");
            out_b.record (0x0031, f);
        }

        private int format_index (string code) {
            if (code == "" || code == "General") return 0;
            var builtin = Xlsx.builtin_formats ();
            for (int i = 1; i < builtin.length; i++) {
                if (builtin[i] == code && i != 14 && i != 22) return i;
            }
            if (!formats.has_key (code)) formats[code] = 164 + formats.size;
            return formats[code];
        }

        private static int border_code (BorderStyle b) {
            switch (b) {
                case BorderStyle.THIN: return 1;
                case BorderStyle.MEDIUM: return 2;
                case BorderStyle.DASHED: return 3;
                case BorderStyle.DOTTED: return 4;
                case BorderStyle.THICK: return 5;
                case BorderStyle.DOUBLE: return 6;
                default: return 0;
            }
        }

        private int bcolor (Border b) {
            if (b.style == BorderStyle.NONE) return 0;
            int c = color_index (b.color);
            return c < 0 ? 64 : c;
        }

        private void xf_record (BiffBuf out_b, int ifnt, int ifmt, bool style_xf, CellStyle? s) {
            var x = new BiffBuf ();
            x.u16 (ifnt);
            x.u16 (ifmt);
            x.u16 (style_xf ? 0xFFF5 : 0x0001);
            if (s == null) {
                x.u8 (0x20);
                x.u8 (0);
                x.u8 (0);
                x.u8 (style_xf ? 0xF4 : 0);
                x.u32 (0);
                x.u32 (0);
                x.u16 (0x20C0);
                out_b.record (0x00E0, x);
                return;
            }
            int alc = 0;
            switch (s.halign) {
                case HAlign.LEFT: alc = 1; break;
                case HAlign.CENTER: alc = 2; break;
                case HAlign.RIGHT: alc = 3; break;
                case HAlign.FILL: alc = 4; break;
                case HAlign.JUSTIFY: alc = 5; break;
                default: break;
            }
            int alcv = s.valign == VAlign.TOP ? 0 : (s.valign == VAlign.CENTER ? 1 : 2);
            x.u8 (alc | (s.wrap ? 8 : 0) | (alcv << 4));
            x.u8 (0);
            x.u8 (s.indent.clamp (0, 15));
            x.u8 (0xFC);
            uint64 b1 = border_code (s.left.style) | (border_code (s.right.style) << 4) | (border_code (s.top.style) << 8) | (border_code (s.bottom.style) << 12);
            b1 |= ((uint64) bcolor (s.left) << 16) | ((uint64) bcolor (s.right) << 23);
            x.u32 (b1);
            uint64 b2 = bcolor (s.top) | (bcolor (s.bottom) << 7);
            int fill = color_index (s.fill);
            if (fill >= 0) b2 |= (uint64) 1 << 26;
            x.u32 (b2);
            x.u16 ((fill >= 0 ? fill : 64) | (65 << 7));
            out_b.record (0x00E0, x);
        }

        private int sst_add (string s) {
            sst_total++;
            if (sst_index.has_key (s)) return sst_index[s];
            sst.add (s);
            sst_index[s] = sst.size - 1;
            return sst.size - 1;
        }

        private int xti_index (int first, int last) {
            string k = "%d:%d".printf (first, last);
            int i = xti.index_of (k);
            if (i >= 0) return i;
            xti.add (k);
            return xti.size - 1;
        }

        public static int err_byte (ErrorKind e) {
            switch (e) {
                case ErrorKind.NULL: return 0x00;
                case ErrorKind.DIV0: return 0x07;
                case ErrorKind.VALUE: return 0x0F;
                case ErrorKind.REF: return 0x17;
                case ErrorKind.NAME: return 0x1D;
                case ErrorKind.NUM: return 0x24;
                case ErrorKind.NA: return 0x2A;
                default: return 0x0F;
            }
        }

        private bool fail (string why) {
            fail_reason = why;
            return false;
        }

        private static int op_ptg (string op) {
            switch (op) {
                case "+": return 0x03;
                case "-": return 0x04;
                case "*": return 0x05;
                case "/": return 0x06;
                case "^": return 0x07;
                case "&": return 0x08;
                case "<": return 0x09;
                case "<=": return 0x0A;
                case "=": return 0x0B;
                case ">=": return 0x0C;
                case ">": return 0x0D;
                case "<>": return 0x0E;
                case ":": return 0x11;
                default: return -1;
            }
        }

        private bool enc_area (BiffBuf out_b, Area src, bool ar1, bool ac1, bool ar2, bool ac2, Sheet own, Sheet target, Sheet? target2, bool force3d, int cls) {
            Area a = src;
            if (!b12) {
                if (a.r2 >= 65536 && a.r1 == 0 && a.r2 == MAX_ROWS - 1) a = new Area (a.sheet, 0, a.c1, 65535, a.c2);
                if (a.c2 >= 256 && a.c1 == 0 && a.c2 == MAX_COLS - 1) a = new Area (a.sheet, a.r1, 0, a.r2, 255);
                if (a.r2 >= 65536 || a.c2 >= 256) return fail (_("reference outside the 65536 by 256 grid"));
            }
            bool three = force3d || target != own || target2 != null;
            bool single = a.is_single ();
            int base_id = three ? (single ? 0x1A : 0x1B) : (single ? 0x04 : 0x05);
            out_b.u8 (base_id | cls);
            if (three) {
                int i1 = book.sheets.index_of (target);
                int i2 = target2 != null ? book.sheets.index_of (target2) : i1;
                out_b.u16 (xti_index (int.min (i1, i2), int.max (i1, i2)));
            }
            if (single) {
                row_field (out_b, a.r1);
                out_b.u16 (a.c1 | (ac1 ? 0 : 0x4000) | (ar1 ? 0 : 0x8000));
            } else {
                row_field (out_b, a.r1);
                row_field (out_b, a.r2);
                out_b.u16 (a.c1 | (ac1 ? 0 : 0x4000) | (ar1 ? 0 : 0x8000));
                out_b.u16 (a.c2 | (ac2 ? 0 : 0x4000) | (ar2 ? 0 : 0x8000));
            }
            return true;
        }

        private const string[] ARRAY_FUNCS = {
            "SUMPRODUCT", "MMULT", "MINVERSE", "MDETERM", "TRANSPOSE", "LINEST", "LOGEST", "TREND", "GROWTH", "FREQUENCY",
            "SUMX2MY2", "SUMX2PY2", "SUMXMY2", "CORREL", "COVAR", "PEARSON", "RSQ", "SLOPE", "INTERCEPT", "STEYX", "FORECAST",
            "TTEST", "FTEST", "CHITEST", "PROB", "NPV", "IRR", "MIRR"
        };

        private const string[] REF_FUNCS = { "OFFSET", "INDIRECT", "INDEX", "CHOOSE", "IF" };

        private const string[] REF_ARG_FUNCS = {
            "SUM", "AVERAGE", "COUNT", "COUNTA", "COUNTBLANK", "MIN", "MAX", "MINA", "MAXA", "AVERAGEA", "PRODUCT", "STDEV",
            "STDEVP", "STDEVA", "STDEVPA", "VAR", "VARP", "VARA", "VARPA", "MEDIAN", "MODE", "LARGE", "SMALL", "RANK",
            "PERCENTILE", "QUARTILE", "PERCENTRANK", "SUMIF", "COUNTIF", "SUBTOTAL", "OFFSET", "INDIRECT", "ROW", "ROWS",
            "COLUMN", "COLUMNS", "AREAS", "CELL", "ISREF", "AND", "OR", "CHOOSE", "IF", "DCOUNT", "DCOUNTA", "DSUM",
            "DAVERAGE", "DMIN", "DMAX", "DSTDEV", "DSTDEVP", "DVAR", "DVARP", "DGET", "DPRODUCT", "SUMSQ", "AVEDEV", "DEVSQ",
            "GEOMEAN", "HARMEAN", "KURT", "SKEW", "TRIMMEAN", "ZTEST", "CONCATENATE", "ADDRESS", "N", "T", "ISBLANK",
            "ISERROR", "ISNA", "ISERR", "ISNUMBER", "ISTEXT", "ISLOGICAL", "ISNONTEXT", "LOOKUP", "MATCH", "HLOOKUP",
            "VLOOKUP", "INDEX"
        };

        private const string[] RANGE_FUNCS = {
            "SUM", "AVERAGE", "AVERAGEA", "COUNT", "COUNTA", "MAX", "MAXA", "MIN", "MINA", "PRODUCT", "STDEV", "STDEVA",
            "STDEVP", "STDEVPA", "VAR", "VARA", "VARP", "VARPA", "MEDIAN", "MODE", "LARGE", "SMALL", "RANK", "PERCENTILE",
            "PERCENTRANK", "QUARTILE", "AVEDEV", "DEVSQ", "GEOMEAN", "HARMEAN", "KURT", "SKEW", "SUMSQ", "TRIMMEAN", "ROW",
            "COLUMN", "ROWS", "COLUMNS", "OFFSET", "CELL", "ISREF", "AREAS", "INDEX", "SUBTOTAL", "SUMIF", "COUNTIF",
            "COUNTBLANK", "INDIRECT", "IF", "CHOOSE", "AND", "OR", "DSUM", "DCOUNT", "DCOUNTA", "DAVERAGE", "DMIN", "DMAX",
            "DGET", "DPRODUCT", "DSTDEV", "DSTDEVP", "DVAR", "DVARP", "N", "ZTEST", "CONFIDENCE", "SUMIFS", "COUNTIFS",
            "AVERAGEIF", "AVERAGEIFS", "AGGREGATE", "HYPERLINK", "GETPIVOTDATA"
        };

        private static int func_class (int cls) {
            return cls == 0x20 ? 0x20 : (cls == 0x60 ? 0x60 : 0x40);
        }

        private static int arg_class (string fname, Node a, int parent_cls, int idx) {
            bool array_fn = false;
            foreach (string f in ARRAY_FUNCS) if (f == fname) array_fn = true;
            bool ref_params = false;
            foreach (string f in REF_ARG_FUNCS) if (f == fname) ref_params = true;
            if ((fname == "VLOOKUP" || fname == "HLOOKUP" || fname == "MATCH" || fname == "LOOKUP") && idx == 0) ref_params = false;
            bool is_ref = a.kind == NodeKind.REF || a.kind == NodeKind.STRUCT || a.kind == NodeKind.NAME;
            if (a.kind == NodeKind.ARRAY) return 0x60;
            if (is_ref) return array_fn || ref_params ? 0x20 : 0x40;
            if (array_fn) return 0x60;
            if (a.kind == NodeKind.CALL && ref_params) {
                bool returns_ref = false;
                foreach (string f in REF_FUNCS) if (f == a.text) returns_ref = true;
                if (parent_cls == 0x60) return 0x60;
                return returns_ref ? 0x20 : 0x40;
            }
            if (ref_params && parent_cls == 0x60) return 0x60;
            return 0x40;
        }

        private bool enc (BiffBuf out_b, BiffBuf extra, Node n, Sheet own, int row, int col, bool in_name, int cls) {
            switch (n.kind) {
                case NodeKind.NUMBER:
                    if (n.number >= 0 && n.number <= 65535 && n.number == Math.floor (n.number)) {
                        out_b.u8 (0x1E);
                        out_b.u16 ((int) n.number);
                    } else {
                        out_b.u8 (0x1F);
                        out_b.f64 (n.number);
                    }
                    return true;
                case NodeKind.TEXT:
                    if (n.text.char_count () > 255) return fail (_("text constant longer than 255 characters"));
                    out_b.u8 (0x17);
                    if (b12) {
                        out_b.u16 (n.text.char_count ());
                        out_b.chars (n.text, true);
                        return true;
                    }
                    bool wide = !BiffBuf.narrow (n.text);
                    out_b.u8 (n.text.char_count ());
                    out_b.u8 (wide ? 1 : 0);
                    out_b.chars (n.text, wide);
                    return true;
                case NodeKind.BOOL:
                    out_b.u8 (0x1D);
                    out_b.u8 (n.number != 0 ? 1 : 0);
                    return true;
                case NodeKind.ERROR:
                    out_b.u8 (0x1C);
                    out_b.u8 (err_byte (n.error));
                    return true;
                case NodeKind.MISSING:
                    out_b.u8 (0x16);
                    return true;
                case NodeKind.REF:
                    if (n.a == null || n.bad_sheet) {
                        out_b.u8 (0x0A | cls);
                        out_b.zeros (b12 ? 6 : 4);
                        return true;
                    }
                    Sheet target = n.sheet ?? own;
                    if (n.spill) {
                        var sa = book.spill_area (target, n.a.row, n.a.col);
                        if (sa == null) return fail (_("spill reference without a spill"));
                        return enc_area (out_b, sa, true, true, true, true, own, target, null, in_name, cls);
                    }
                    var area = new Area (target, n.a.row, n.a.col, n.b != null ? n.b.row : n.a.row, n.b != null ? n.b.col : n.a.col);
                    if (n.b != null && area.is_single ()) {
                        bool three = in_name || target != own || n.sheet2 != null;
                        out_b.u8 ((three ? 0x1B : 0x05) | cls);
                        if (three) {
                            int i1 = book.sheets.index_of (target);
                            int i2 = n.sheet2 != null ? book.sheets.index_of (n.sheet2) : i1;
                            out_b.u16 (xti_index (int.min (i1, i2), int.max (i1, i2)));
                        }
                        if (!b12 && (area.r1 >= 65536 || area.c1 >= 256)) return fail (_("reference outside the 65536 by 256 grid"));
                        row_field (out_b, area.r1);
                        row_field (out_b, area.r1);
                        out_b.u16 (area.c1 | (n.a.abs_col ? 0 : 0x4000) | (n.a.abs_row ? 0 : 0x8000));
                        out_b.u16 (area.c1 | (n.b.abs_col ? 0 : 0x4000) | (n.b.abs_row ? 0 : 0x8000));
                        return true;
                    }
                    return enc_area (out_b, area, n.a.abs_row, n.a.abs_col, n.b != null ? n.b.abs_row : n.a.abs_row, n.b != null ? n.b.abs_col : n.a.abs_col, own, target, n.sheet2, in_name, cls);
                case NodeKind.STRUCT:
                    var ta = Tables.resolve (book, n.sref, own, row, col);
                    if (ta == null) return fail (_("structured reference that cannot be resolved"));
                    return enc_area (out_b, ta, true, true, true, true, own, ta.sheet ?? own, null, in_name, cls);
                case NodeKind.NAME:
                    string key = n.text.casefold ();
                    int ni = -1;
                    int sidx = book.sheets.index_of (own);
                    if (name_index.has_key ("%d:%s".printf (sidx, key))) ni = name_index["%d:%s".printf (sidx, key)];
                    else if (name_index.has_key ("-1:" + key)) ni = name_index["-1:" + key];
                    if (ni < 0) return fail (_("name that is not a defined name"));
                    out_b.u8 (0x03 | cls);
                    out_b.u32 (ni + 1);
                    return true;
                case NodeKind.PERCENT:
                    if (!enc (out_b, extra, n.args[0], own, row, col, in_name, cls == 0x60 ? 0x60 : 0x40)) return false;
                    out_b.u8 (0x14);
                    return true;
                case NodeKind.UNARY:
                    if (n.op == "@") return enc (out_b, extra, n.args[0], own, row, col, in_name, cls);
                    if (!enc (out_b, extra, n.args[0], own, row, col, in_name, cls == 0x60 ? 0x60 : 0x40)) return false;
                    out_b.u8 (0x13);
                    return true;
                case NodeKind.BINARY:
                    int op = op_ptg (n.op);
                    if (op < 0) return fail (_("operator %s").printf (n.op));
                    int sub = n.op == ":" ? 0x20 : (cls == 0x60 ? 0x60 : 0x40);
                    if (!enc (out_b, extra, n.args[0], own, row, col, in_name, sub)) return false;
                    if (!enc (out_b, extra, n.args[1], own, row, col, in_name, sub)) return false;
                    out_b.u8 (op);
                    return true;
                case NodeKind.ARRAY:
                    int rows = n.array.length[0], cols = n.array.length[1];
                    if (b12) return fail (_("array constants in binary workbooks"));
                    if (cols > 256 || rows > 65535) return fail (_("array constant too large"));
                    out_b.u8 (0x60);
                    out_b.zeros (7);
                    extra.u8 (cols - 1);
                    extra.u16 (rows - 1);
                    for (int i = 0; i < rows; i++) {
                        for (int j = 0; j < cols; j++) {
                            var v = n.array[i, j];
                            switch (v.kind) {
                                case ValueKind.NUMBER:
                                    extra.u8 (0x01);
                                    extra.f64 (v.number);
                                    break;
                                case ValueKind.TEXT:
                                    extra.u8 (0x02);
                                    extra.long_string (BiffBuf.clip (v.text, 255));
                                    break;
                                case ValueKind.BOOL:
                                    extra.u8 (0x04);
                                    extra.u8 (v.number != 0 ? 1 : 0);
                                    extra.zeros (7);
                                    break;
                                case ValueKind.ERROR:
                                    extra.u8 (0x10);
                                    extra.u8 (err_byte (v.error));
                                    extra.zeros (7);
                                    break;
                                default:
                                    extra.u8 (0x00);
                                    extra.zeros (8);
                                    break;
                            }
                        }
                    }
                    return true;
                case NodeKind.CALL:
                    if (n.text == "IF" && (n.args.length == 2 || n.args.length == 3)) return enc_if (out_b, extra, n, own, row, col, in_name, cls);
                    int ix = XlsFunctions.index_of (n.text);
                    if (n.args.length > 29) return fail (_("more than 30 arguments"));
                    if (ix < 0) {
                        if (n.text == "LAMBDA" || n.text == "LET" || n.text.has_prefix ("_")) return fail (_("LAMBDA and dynamic array syntax"));
                        if (b12) {
                            string fut = future_name (n.text);
                            if (!name_index.has_key ("-1:" + fut.casefold ())) {
                                name_index["-1:" + fut.casefold ()] = -1000 - future_names.size;
                                future_names.add (fut);
                            }
                            out_b.u8 (0x23);
                            out_b.u32 (future_names.index_of (fut) + 1 + future_base);
                        } else {
                            out_b.u8 (0x39);
                            out_b.u16 (xti_index (-2, -2));
                            out_b.u16 (addin_index (n.text) + 1);
                            out_b.u16 (0);
                        }
                        for (int ai = 0; ai < n.args.length; ai++) {
                            if (!enc (out_b, extra, n.args[ai], own, row, col, in_name, arg_class (n.text, n.args[ai], cls, ai))) return false;
                        }
                        out_b.u8 (0x02 | func_class (cls));
                        out_b.u8 (n.args.length + 1);
                        out_b.u16 (0x00FF);
                        return true;
                    }
                    int fixed_arity = XlsFunctions.arity (ix);
                    if (n.text == "IF" && (n.args.length == 2 || n.args.length == 3) && n.args[0].kind != NodeKind.MISSING) {
                        if (!enc (out_b, extra, n.args[0], own, row, col, in_name, arg_class (n.text, n.args[0], cls, 0))) return false;
                        out_b.u8 (0x19);
                        out_b.u8 (0x02);
                        uint if_at = out_b.len;
                        out_b.u16 (0);
                        uint t_start = out_b.len;
                        if (!enc (out_b, extra, n.args[1], own, row, col, in_name, arg_class (n.text, n.args[1], cls, 1))) return false;
                        uint t_size = out_b.len - t_start;
                        out_b.u8 (0x19);
                        out_b.u8 (0x08);
                        uint skip1 = out_b.len;
                        out_b.u16 (0);
                        out_b.set_u16 (if_at, t_size + 4);
                        if (n.args.length == 3) {
                            uint f_start = out_b.len;
                            if (!enc (out_b, extra, n.args[2], own, row, col, in_name, arg_class (n.text, n.args[2], cls, 2))) return false;
                            uint f_size = out_b.len - f_start;
                            out_b.u8 (0x19);
                            out_b.u8 (0x08);
                            out_b.u16 (3);
                            out_b.set_u16 (skip1, f_size + 4 + 4 - 1);
                        } else {
                            out_b.set_u16 (skip1, 3);
                        }
                        out_b.u8 (0x02 | func_class (cls));
                        out_b.u8 (n.args.length);
                        out_b.u16 (ix);
                        return true;
                    }
                    for (int ai = 0; ai < n.args.length; ai++) {
                        if (!enc (out_b, extra, n.args[ai], own, row, col, in_name, arg_class (n.text, n.args[ai], cls, ai))) return false;
                    }
                    if (fixed_arity >= 0 && fixed_arity == n.args.length) {
                        out_b.u8 (0x01 | func_class (cls));
                        out_b.u16 (ix);
                    } else {
                        out_b.u8 (0x02 | func_class (cls));
                        out_b.u8 (n.args.length);
                        out_b.u16 (ix);
                    }
                    return true;
                default:
                    return fail (_("LAMBDA and dynamic array syntax"));
            }
        }

        public int future_base = 0;

        private void row_field (BiffBuf b, int r) {
            if (b12) b.u32 (r);
            else b.u16 (r);
        }

        private string future_name (string fname) {
            foreach (string a in ATP) if (a == fname) return fname;
            return "_xlfn." + fname;
        }

        private void attr (BiffBuf b, int kind, int value) {
            b.u8 (0x19);
            b.u8 (kind);
            b.u16 (value);
        }

        private bool enc_if (BiffBuf out_b, BiffBuf extra, Node n, Sheet own, int row, int col, bool in_name, int cls) {
            var cond = new BiffBuf ();
            var yes = new BiffBuf ();
            var no = new BiffBuf ();
            if (!enc (cond, extra, n.args[0], own, row, col, in_name, 0x40)) return false;
            if (!enc (yes, extra, n.args[1], own, row, col, in_name, arg_class ("IF", n.args[1], cls, 1))) return false;
            if (n.args.length == 3 && !enc (no, extra, n.args[2], own, row, col, in_name, arg_class ("IF", n.args[2], cls, 2))) return false;
            out_b.append (cond);
            attr (out_b, 0x02, (int) yes.len + 4);
            out_b.append (yes);
            if (n.args.length == 3) {
                attr (out_b, 0x08, (int) no.len + 4 + 4 - 1);
                out_b.append (no);
            }
            attr (out_b, 0x08, 3);
            out_b.u8 (0x02 | func_class (cls));
            out_b.u8 (n.args.length);
            out_b.u16 (1);
            return true;
        }

        private uint8[] enc_text (string f, Sheet sh, int row, int col) {
            string t = f.strip ();
            if (t == "") return new uint8[0];
            try {
                var node = Formula.parse (t.has_prefix ("=") ? t : "=" + t, book, sh);
                uint8[] rgce, extra;
                if (encode (node, sh, row, col, false, out rgce, out extra) && extra.length == 0) return rgce;
            } catch (FormulaError e) {
            }
            return new uint8[0];
        }

        private static void ref8 (BiffBuf b, Area a) {
            b.u16 (a.r1);
            b.u16 (int.min (a.r2, 65535));
            b.u16 (a.c1);
            b.u16 (int.min (a.c2, 255));
        }

        private void dxf (BiffBuf b, CellStyle st) {
            bool font = st.color != "" || st.bold || st.italic || st.underline || st.strike;
            bool pat = st.fill != "";
            uint64 flags = 0x003FFFFF;
            if (pat) flags &= ~0x70000;
            if (font) flags |= 0x04000000;
            if (pat) flags |= 0x20000000;
            b.u32 (flags);
            b.u16 (0x8002);
            if (font) {
                b.u8 (0);
                b.zeros (63);
                b.u32 (0xFFFFFFFF);
                b.u32 ((st.italic ? 2 : 0) | (st.strike ? 0x80 : 0));
                b.u16 (st.bold ? 700 : 400);
                b.u16 (0);
                b.u8 (st.underline ? 1 : 0);
                b.u8 (0);
                b.u8 (0);
                b.u8 (0);
                int ci = color_index (st.color);
                b.u32 (ci >= 0 ? ci : 0xFFFFFFFF);
                b.u32 (0);
                b.u32 ((st.italic ? 0 : 0x2) | (st.strike ? 0 : 0x80));
                b.u32 (1);
                b.u32 (st.underline ? 0 : 1);
                b.u32 (st.bold ? 0 : 1);
                b.u32 (0);
                b.u32 (0);
                b.u32 (0);
                b.u16 (1);
            }
            if (pat) {
                int fc = color_index (st.fill);
                b.u16 (1 << 10);
                b.u16 (fc | (fc << 7));
            }
        }

        private int cf_id = 0;

        private void write_cond_formats (BiffBuf s, Sheet sh) {
            foreach (var cf in sh.cond_formats) {
                var a = cf.area;
                if (a.r1 >= 65536 || a.c1 >= 256) continue;
                int ct = 1, cp = 0;
                string f1 = cf.a, f2 = "";
                string first = Address.cell (a.r1, a.c1);
                string range = Address.cell (a.r1, a.c1, true, true) + ":" + Address.cell (int.min (a.r2, 65535), int.min (a.c2, 255), true, true);
                switch (cf.kind) {
                    case CondKind.BETWEEN: cp = 1; f2 = cf.b; break;
                    case CondKind.EQUAL: cp = 3; break;
                    case CondKind.NOT_EQUAL: cp = 4; break;
                    case CondKind.GREATER: cp = 5; break;
                    case CondKind.LESS: cp = 6; break;
                    case CondKind.FORMULA: ct = 2; break;
                    case CondKind.TEXT_CONTAINS: ct = 2; f1 = "NOT(ISERROR(SEARCH(\"%s\",%s)))".printf (cf.a.replace ("\"", "\"\""), first); break;
                    case CondKind.BLANK: ct = 2; f1 = "LEN(TRIM(%s))=0".printf (first); break;
                    case CondKind.ERRORS: ct = 2; f1 = "ISERROR(%s)".printf (first); break;
                    case CondKind.DUPLICATE: ct = 2; f1 = "COUNTIF(%s,%s)>1".printf (range, first); break;
                    case CondKind.UNIQUE: ct = 2; f1 = "COUNTIF(%s,%s)=1".printf (range, first); break;
                    case CondKind.TOP: ct = 2; f1 = "%s>=LARGE(%s,%s)".printf (first, range, cf.a != "" ? cf.a : "10"); break;
                    case CondKind.BOTTOM: ct = 2; f1 = "%s<=SMALL(%s,%s)".printf (first, range, cf.a != "" ? cf.a : "10"); break;
                    case CondKind.ABOVE_AVERAGE: ct = 2; f1 = "%s>AVERAGE(%s)".printf (first, range); break;
                    case CondKind.BELOW_AVERAGE: ct = 2; f1 = "%s<AVERAGE(%s)".printf (first, range); break;
                    default:
                        unsupported.add (_("color scales and data bars in Excel 97-2003 files"));
                        continue;
                }
                uint8[] r1 = enc_text (f1, sh, a.r1, a.c1);
                uint8[] r2 = f2 != "" ? enc_text (f2, sh, a.r1, a.c1) : new uint8[0];
                if (r1.length == 0) continue;
                cf_id++;
                var head = new BiffBuf ();
                head.u16 (1);
                head.u16 (cf_id << 1);
                ref8 (head, a);
                head.u16 (1);
                ref8 (head, a);
                s.record (0x01B0, head);
                var rule = new BiffBuf ();
                rule.u8 (ct);
                rule.u8 (cp);
                rule.u16 (r1.length);
                rule.u16 (r2.length);
                dxf (rule, book.styles[cf.style.clamp (0, book.styles.size - 1)]);
                rule.bytes (r1);
                rule.bytes (r2);
                s.record (0x01B1, rule);
            }
        }

        private static void dv_string (BiffBuf b, string t) {
            if (t == "") {
                b.u16 (1);
                b.u8 (0);
                b.u8 (0);
                return;
            }
            b.long_string (BiffBuf.clip (t, 255));
        }

        private void write_validations (BiffBuf s, Sheet sh) {
            var list = new Gee.ArrayList<Validation> ();
            foreach (var v in sh.validations) if (v.area.r1 < 65536 && v.area.c1 < 256) list.add (v);
            if (list.size == 0) return;
            var dval = new BiffBuf ();
            dval.u16 (0);
            dval.u32 (0);
            dval.u32 (0);
            dval.u32 (0xFFFFFFFF);
            dval.u32 (list.size);
            s.record (0x01B2, dval);
            foreach (var v in list) {
                int type;
                switch (v.kind) {
                    case ValidationKind.WHOLE: type = 1; break;
                    case ValidationKind.DECIMAL: type = 2; break;
                    case ValidationKind.LIST: type = 3; break;
                    case ValidationKind.DATE: type = 4; break;
                    case ValidationKind.TIME: type = 5; break;
                    case ValidationKind.TEXT_LENGTH: type = 6; break;
                    case ValidationKind.CUSTOM: type = 7; break;
                    default: type = 0; break;
                }
                int op;
                switch (v.op) {
                    case ValidationOp.NOT_BETWEEN: op = 1; break;
                    case ValidationOp.EQUAL: op = 2; break;
                    case ValidationOp.NOT_EQUAL: op = 3; break;
                    case ValidationOp.GREATER: op = 4; break;
                    case ValidationOp.LESS: op = 5; break;
                    case ValidationOp.GREATER_EQUAL: op = 6; break;
                    case ValidationOp.LESS_EQUAL: op = 7; break;
                    default: op = 0; break;
                }
                int err = v.alert == ValidationAlert.WARNING ? 1 : (v.alert == ValidationAlert.INFORMATION ? 2 : 0);
                string src = type == 3 ? (v.list_source != "" ? v.list_source : v.formula1) : v.formula1;
                string st = src.strip ();
                if (st.has_prefix ("=")) st = st.substring (1);
                bool literal = type == 3 && st.has_prefix ("\"") && st.has_suffix ("\"") && st.length >= 2;
                uint64 flags = type | (err << 4) | (literal ? 0x80 : 0) | (v.allow_blank ? 0x100 : 0) | (v.dropdown ? 0 : 0x200) | (v.show_input ? 0x40000 : 0) | (v.show_error ? 0x80000 : 0) | ((uint64) op << 20);
                var b = new BiffBuf ();
                b.u32 (flags);
                dv_string (b, v.input_title);
                dv_string (b, v.error_title);
                dv_string (b, v.message);
                dv_string (b, v.error_message);
                uint8[] f1;
                if (literal) {
                    var lb = new BiffBuf ();
                    string inner = st.substring (1, st.length - 2);
                    var items = inner.split (",");
                    int total = 0;
                    for (int i = 0; i < items.length; i++) total += items[i].strip ().char_count () + (i > 0 ? 1 : 0);
                    lb.u8 (0x17);
                    lb.u8 (int.min (total, 255));
                    lb.u8 (1);
                    for (int i = 0; i < items.length; i++) {
                        if (i > 0) lb.u16 (0);
                        lb.chars (items[i].strip (), true);
                    }
                    f1 = lb.b.data;
                } else {
                    f1 = type != 0 ? enc_text (st, sh, v.area.r1, v.area.c1) : new uint8[0];
                }
                uint8[] f2 = type != 0 && type != 3 && type != 7 && (op == 0 || op == 1) ? enc_text (v.formula2, sh, v.area.r1, v.area.c1) : new uint8[0];
                b.u16 (f1.length);
                b.u16 (0);
                b.bytes (f1);
                b.u16 (f2.length);
                b.u16 (0);
                b.bytes (f2);
                b.u16 (1);
                ref8 (b, v.area);
                s.record (0x01BE, b);
            }
        }

        public bool encode (Node n, Sheet own, int row, int col, bool in_name, out uint8[] rgce, out uint8[] extra_out) {
            var body = new BiffBuf ();
            var extra = new BiffBuf ();
            fail_reason = "";
            bool ok = enc (body, extra, n, own, row, col, in_name, in_name ? 0x20 : 0x40);
            if (!ok && fail_reason != "") unsupported.add (fail_reason);
            rgce = body.b.data;
            extra_out = extra.b.data;
            return ok;
        }

        private static bool rk_of (double v, out uint32 rk) {
            rk = 0;
            if (v == Math.floor (v) && v >= -536870912 && v < 536870912) {
                rk = (((uint32) (int32) v) << 2) | 2;
                return true;
            }
            double h = v * 100;
            if (Math.fabs (h - Math.round (h)) < 1e-9 && h >= -536870912 && h < 536870912 && Math.round (h) / 100.0 == v) {
                rk = (((uint32) (int32) Math.round (h)) << 2) | 3;
                return true;
            }
            return false;
        }

        private void cell_head (BiffBuf b, int r, int c, int style) {
            b.u16 (r);
            b.u16 (c);
            b.u16 (15 + style);
        }

        private void write_value (BiffBuf s, int r, int c, int style, Value v) {
            var b = new BiffBuf ();
            cell_head (b, r, c, style);
            switch (v.kind) {
                case ValueKind.NUMBER:
                    uint32 rk;
                    if (rk_of (v.number, out rk)) {
                        b.u32 (rk);
                        s.record (0x027E, b);
                    } else {
                        b.f64 (v.number);
                        s.record (0x0203, b);
                    }
                    break;
                case ValueKind.TEXT:
                    b.u32 (sst_add (BiffBuf.clip (v.text, 32767)));
                    s.record (0x00FD, b);
                    break;
                case ValueKind.BOOL:
                    b.u8 (v.number != 0 ? 1 : 0);
                    b.u8 (0);
                    s.record (0x0205, b);
                    break;
                case ValueKind.ERROR:
                    b.u8 (err_byte (v.error));
                    b.u8 (1);
                    s.record (0x0205, b);
                    break;
                default:
                    if (style != 0) s.record (0x0201, b);
                    break;
            }
        }

        private void write_formula (BiffBuf s, Sheet sh, Cell cell) {
            var v = sh.value_at (cell.row, cell.col);
            uint8[] rgce, extra;
            if (!encode (cell.formula, sh, cell.row, cell.col, false, out rgce, out extra) || rgce.length > 1800) {
                formulas_as_values++;
                write_value (s, cell.row, cell.col, cell.style, v);
                return;
            }
            formulas_written++;
            var b = new BiffBuf ();
            cell_head (b, cell.row, cell.col, cell.style);
            bool str = false;
            switch (v.kind) {
                case ValueKind.NUMBER:
                    b.f64 (v.number);
                    break;
                case ValueKind.TEXT:
                    if (v.text == "") {
                        b.u8 (3);
                        b.zeros (5);
                    } else {
                        b.u8 (0);
                        b.zeros (5);
                        str = true;
                    }
                    b.u16 (0xFFFF);
                    break;
                case ValueKind.BOOL:
                    b.u8 (1);
                    b.u8 (0);
                    b.u8 (v.number != 0 ? 1 : 0);
                    b.zeros (3);
                    b.u16 (0xFFFF);
                    break;
                case ValueKind.ERROR:
                    b.u8 (2);
                    b.u8 (0);
                    b.u8 (err_byte (v.error));
                    b.zeros (3);
                    b.u16 (0xFFFF);
                    break;
                default:
                    b.u8 (3);
                    b.zeros (5);
                    b.u16 (0xFFFF);
                    break;
            }
            b.u16 (Functions.is_volatile (cell.formula) ? 0x0001 : 0x0000);
            b.u32 (0);
            b.u16 (rgce.length);
            b.bytes (rgce);
            b.bytes (extra);
            s.record (0x0006, b);
            if (str) {
                var sb = new BiffBuf ();
                sb.long_string (v.text);
                s.record (0x0207, sb);
            }
        }

        private static void escher (BiffBuf b, int ver, int inst, int type, uint64 len) {
            b.u16 ((ver & 0xF) | (inst << 4));
            b.u16 (type);
            b.u32 (len);
        }

        private const int NOTE_PROPS = 5;

        private void note_shape (BiffBuf b, int spid, Cell c) {
            int sp_len = 16 + (8 + 6 * NOTE_PROPS) + 26 + 8 + 8;
            escher (b, 0xF, 0, 0xF004, sp_len);
            escher (b, 2, 202, 0xF00A, 8);
            b.u32 (spid);
            b.u32 (0x0A00);
            escher (b, 3, NOTE_PROPS, 0xF00B, 6 * NOTE_PROPS);
            b.u16 (0x0181);
            b.u32 (0x08000050);
            b.u16 (0x0183);
            b.u32 (0x08000050);
            b.u16 (0x01BF);
            b.u32 (0x00100010);
            b.u16 (0x023F);
            b.u32 (0x00030003);
            b.u16 (0x03BF);
            b.u32 (0x00020002);
            escher (b, 0, 0, 0xF010, 18);
            b.u16 (3);
            int col = int.min (c.col + 1, 253);
            int row = int.max (c.row - 1, 0);
            b.u16 (col);
            b.u16 (0xF0);
            b.u16 (int.min (row, 65531));
            b.u16 (0x1E);
            b.u16 (col + 2);
            b.u16 (0xF0);
            b.u16 (int.min (row + 4, 65535));
            b.u16 (0x78);
            escher (b, 0, 0, 0xF011, 0);
        }

        private void note_objects (BiffBuf s, Sheet sh, Gee.ArrayList<XlsNote> notes) {
            drawing_count++;
            int dgid = drawing_count;
            int n = notes.size;
            int sp_len = 16 + (8 + 6 * NOTE_PROPS) + 26 + 8 + 8;
            int spgr_len = (8 + 24 + 16) + n * (8 + sp_len);
            int dg_len = 16 + 8 + spgr_len;
            int last_spid = dgid * 1024 + n;
            total_shapes += n + 1;
            max_spid = int.max (max_spid, last_spid);
            dg_shapes.add (n + 1);
            for (int i = 0; i < n; i++) {
                var md = new BiffBuf ();
                if (i == 0) {
                    escher (md, 0xF, 0, 0xF002, dg_len);
                    escher (md, 0, dgid, 0xF008, 8);
                    md.u32 (n + 1);
                    md.u32 (last_spid);
                    escher (md, 0xF, 0, 0xF003, spgr_len);
                    escher (md, 0xF, 0, 0xF004, 24 + 16);
                    escher (md, 1, 0, 0xF009, 16);
                    md.zeros (16);
                    escher (md, 2, 0, 0xF00A, 8);
                    md.u32 (dgid * 1024);
                    md.u32 (0x0005);
                }
                note_shape (md, dgid * 1024 + i + 1, notes[i].cell);
                s.record (0x00EC, md);
                var obj = new BiffBuf ();
                obj.u16 (0x15);
                obj.u16 (0x12);
                obj.u16 (0x19);
                obj.u16 (notes[i].id);
                obj.u16 (0x4011);
                obj.zeros (12);
                obj.u16 (0x0D);
                obj.u16 (0x16);
                for (int k = 0; k < 16; k++) obj.u8 ((notes[i].id * 37 + k * 11) & 0xff);
                obj.u16 (0);
                obj.u32 (0);
                obj.u32 (0);
                s.record (0x005D, obj);
                var tb = new BiffBuf ();
                escher (tb, 0, 0, 0xF00D, 0);
                s.record (0x00EC, tb);
                string text = BiffBuf.clip (notes[i].cell.note, 8000);
                bool wide = !BiffBuf.narrow (text);
                var txo = new BiffBuf ();
                txo.u16 (0x0212);
                txo.u16 (0);
                txo.zeros (6);
                txo.u16 (text.char_count ());
                txo.u16 (16);
                txo.zeros (4);
                s.record (0x01B6, txo);
                var t1 = new BiffBuf ();
                t1.u8 (wide ? 1 : 0);
                t1.chars (text, wide);
                s.record (0x003C, t1);
                var t2 = new BiffBuf ();
                t2.u16 (0);
                t2.u16 (0);
                t2.zeros (4);
                t2.u16 (text.char_count ());
                t2.u16 (0);
                t2.zeros (4);
                s.record (0x003C, t2);
            }
            foreach (var nt in notes) {
                var nb = new BiffBuf ();
                nb.u16 (nt.cell.row);
                nb.u16 (nt.cell.col);
                nb.u16 (0);
                nb.u16 (nt.id);
                string author = nt.cell.note_author != "" ? nt.cell.note_author : XlsxExtras.default_author ();
                nb.long_string (BiffBuf.clip (author, 54));
                nb.u8 (0);
                s.record (0x001C, nb);
            }
        }

        private const uint8[] HLINK_CLSID = { 0xD0, 0xC9, 0xEA, 0x79, 0xF9, 0xBA, 0xCE, 0x11, 0x8C, 0x82, 0x00, 0xAA, 0x00, 0x4B, 0xA9, 0x0B };
        private const uint8[] URL_CLSID = { 0xE0, 0xC9, 0xEA, 0x79, 0xF9, 0xBA, 0xCE, 0x11, 0x8C, 0x82, 0x00, 0xAA, 0x00, 0x4B, 0xA9, 0x0B };

        private void hlink (BiffBuf s, Cell c) {
            var b = new BiffBuf ();
            b.u16 (c.row);
            b.u16 (c.row);
            b.u16 (c.col);
            b.u16 (c.col);
            b.bytes (HLINK_CLSID);
            b.u32 (2);
            string link = c.link;
            if (link.has_prefix ("#")) {
                string loc = link.substring (1);
                b.u32 (0x08);
                b.u32 (loc.char_count () + 1);
                b.chars (loc, true);
                b.u16 (0);
            } else {
                string url = link;
                string loc = "";
                int hash = url.index_of_char ('#');
                if (hash > 0) {
                    loc = url.substring (hash + 1);
                    url = url.substring (0, hash);
                }
                b.u32 (0x03 | (loc != "" ? 0x08 : 0));
                b.bytes (URL_CLSID);
                b.u32 ((url.char_count () + 1) * 2);
                b.chars (url, true);
                b.u16 (0);
                if (loc != "") {
                    b.u32 (loc.char_count () + 1);
                    b.chars (loc, true);
                    b.u16 (0);
                }
            }
            s.record (0x01B8, b);
        }

        private uint8[] sheet_stream (Sheet sh, int index) {
            var s = new BiffBuf ();
            var bof = new BiffBuf ();
            bof.u16 (0x0600);
            bof.u16 (0x0010);
            bof.u16 (0x0DBB);
            bof.u16 (0x07CC);
            bof.u32 (0x41);
            bof.u32 (0x06);
            s.record (0x0809, bof);
            var defw = new BiffBuf ();
            defw.u16 ((int) Math.round (((sh.default_col_width / Xlsx.COL_SCALE) - 5) / 7.0));
            s.record (0x0055, defw);
            var cols = new Gee.TreeSet<int> ();
            foreach (int c in sh.col_widths.keys) if (c < 256) cols.add (c);
            foreach (int c in sh.hidden_cols) if (c < 256) cols.add (c);
            foreach (int c in cols) {
                var ci = new BiffBuf ();
                ci.u16 (c);
                ci.u16 (c);
                int px = sh.col_widths.has_key (c) ? sh.col_widths[c] : sh.default_col_width;
                ci.u16 (((int) Math.round ((px / Xlsx.COL_SCALE - 5) / 7.0 * 256)).clamp (0, 65535));
                ci.u16 (15);
                ci.u16 (sh.hidden_cols.contains (c) ? 1 : 0);
                ci.u16 (0);
                s.record (0x007D, ci);
            }
            int maxr = int.min (sh.max_row, 65535), maxc = int.min (sh.max_col, 255);
            var dim = new BiffBuf ();
            dim.u32 (0);
            dim.u32 (maxr + 1);
            dim.u16 (0);
            dim.u16 (maxc + 1);
            dim.u16 (0);
            s.record (0x0200, dim);
            var rows = new Gee.TreeSet<int> ();
            foreach (int r in sh.row_heights.keys) if (r < 65536) rows.add (r);
            foreach (int r in sh.hidden_rows) if (r < 65536) rows.add (r);
            foreach (int r in rows) {
                var rb = new BiffBuf ();
                rb.u16 (r);
                rb.u16 (0);
                rb.u16 (0);
                int px = sh.row_heights.has_key (r) ? sh.row_heights[r] : sh.default_row_height;
                rb.u16 (((int) Math.round (px / Xlsx.ROW_SCALE * 0.75 * 20)).clamp (1, 8190));
                rb.u16 (0);
                rb.u16 (0);
                rb.u16 (0x0100 | (sh.hidden_rows.contains (r) ? 0x20 : 0) | (sh.row_heights.has_key (r) ? 0x40 : 0));
                rb.u16 (15);
                s.record (0x0208, rb);
            }
            var keys = new Gee.ArrayList<int64?> ();
            foreach (var k in sh.cells.keys) keys.add (k);
            keys.sort ((a, b) => {
                int64 x = a;
                int64 y = b;
                return x < y ? -1 : (x > y ? 1 : 0);
            });
            var notes = new Gee.ArrayList<XlsNote> ();
            var links = new Gee.ArrayList<Cell> ();
            foreach (var k in keys) {
                var cell = sh.cells[k];
                if (cell.row >= 65536 || cell.col >= 256) {
                    if (cell.input != "" || cell.formula != null) cells_dropped++;
                    continue;
                }
                if (cell.formula != null) write_formula (s, sh, cell);
                else if (cell.input != "") write_value (s, cell.row, cell.col, cell.style, cell.value);
                else if (sh.spills.size > 0 && sh.spill_anchor_at (cell.row, cell.col) != null) write_value (s, cell.row, cell.col, cell.style, sh.value_at (cell.row, cell.col));
                else if (cell.style != 0) write_value (s, cell.row, cell.col, cell.style, Value.empty ());
                if (cell.note != "") {
                    var nt = new XlsNote ();
                    nt.cell = cell;
                    nt.id = notes.size + 1;
                    notes.add (nt);
                }
                if (cell.link != "") links.add (cell);
            }
            foreach (var e in sh.spills.entries) {
                var area = e.value;
                for (int r = area.r1; r <= int.min (area.r2, 65535); r++) {
                    for (int c = area.c1; c <= int.min (area.c2, 255); c++) {
                        if (r == area.r1 && c == area.c1) continue;
                        var cl = sh.get_cell (r, c);
                        if (cl != null) continue;
                        write_value (s, r, c, 0, sh.value_at (r, c));
                    }
                }
            }
            if (notes.size > 0) note_objects (s, sh, notes);
            var w2 = new BiffBuf ();
            int grbit = 0x02B6 | (index == 0 ? 0x0600 : 0);
            if (!sh.show_grid) grbit &= ~0x2;
            bool frozen = sh.freeze_rows > 0 || sh.freeze_cols > 0;
            if (frozen) grbit |= 0x0108;
            w2.u16 (grbit);
            w2.u16 (0);
            w2.u16 (0);
            w2.u32 (0x40);
            w2.u16 (0);
            w2.u16 (0);
            w2.u32 (0);
            s.record (0x023E, w2);
            if (frozen) {
                var pane = new BiffBuf ();
                pane.u16 (sh.freeze_cols);
                pane.u16 (sh.freeze_rows);
                pane.u16 (sh.freeze_rows);
                pane.u16 (sh.freeze_cols);
                pane.u8 (sh.freeze_rows > 0 && sh.freeze_cols > 0 ? 0 : (sh.freeze_rows > 0 ? 2 : 1));
                pane.u8 (0);
                s.record (0x0041, pane);
            }
            var merges = new Gee.ArrayList<Area> ();
            foreach (var m in sh.merges) if (m.r2 < 65536 && m.c2 < 256) merges.add (m);
            for (int i = 0; i < merges.size; i += 1026) {
                var mc = new BiffBuf ();
                int cnt = int.min (1026, merges.size - i);
                mc.u16 (cnt);
                for (int j = i; j < i + cnt; j++) {
                    mc.u16 (merges[j].r1);
                    mc.u16 (merges[j].r2);
                    mc.u16 (merges[j].c1);
                    mc.u16 (merges[j].c2);
                }
                s.record (0x00E5, mc);
            }
            write_cond_formats (s, sh);
            foreach (var c in links) hlink (s, c);
            write_validations (s, sh);
            int tab = color_index (sh.tab_color);
            if (tab >= 0) {
                var ext = new BiffBuf ();
                ext.u16 (0x0862);
                ext.u16 (0);
                ext.zeros (8);
                ext.u32 (0x14);
                ext.u32 (tab);
                s.record (0x0862, ext);
            }
            s.record (0x000A, null);
            return s.b.data;
        }

        private void write_sst (BiffBuf out_b, uint start, BiffBuf ext) {
            var recs = new Gee.ArrayList<BiffBuf> ();
            var cur = new BiffBuf ();
            cur.u32 (sst_total);
            cur.u32 (sst.size);
            int limit = 8224;
            uint rec_start = start;
            int bucket = int.max (8, (sst.size + 127) / 128);
            ext.u16 (bucket);
            for (int i = 0; i < sst.size; i++) {
                string s = sst[i];
                bool wide = !BiffBuf.narrow (s);
                int cch = s.char_count ();
                int csize = wide ? 2 : 1;
                if (cur.len + 3 + (cch > 0 ? csize : 0) > limit) {
                    recs.add (cur);
                    rec_start += cur.len + 4;
                    cur = new BiffBuf ();
                }
                if (i % bucket == 0) {
                    ext.u32 (rec_start + 4 + cur.len);
                    ext.u16 (cur.len + 4);
                    ext.u16 (0);
                }
                cur.u16 (cch);
                cur.u8 (wide ? 1 : 0);
                unichar c;
                int idx = 0;
                while (s.get_next_char (ref idx, out c)) {
                    if (cur.len + csize > limit) {
                        recs.add (cur);
                        rec_start += cur.len + 4;
                        cur = new BiffBuf ();
                        cur.u8 (wide ? 1 : 0);
                    }
                    if (wide) cur.u16 (c > 0xffff ? 0xfffd : c);
                    else cur.u8 (c);
                }
            }
            recs.add (cur);
            for (int i = 0; i < recs.size; i++) {
                out_b.u16 (i == 0 ? 0x00FC : 0x003C);
                out_b.u16 (recs[i].len);
                out_b.append (recs[i]);
            }
        }

        private void builtin_name (BiffBuf out_b, int code, int sheet, Gee.ArrayList<Area> areas) {
            var rg = new BiffBuf ();
            int n = 0;
            foreach (var a in areas) {
                if (a.r2 >= 65536 || a.c2 >= 256) continue;
                rg.u8 (0x3B);
                rg.u16 (xti_index (sheet, sheet));
                rg.u16 (a.r1);
                rg.u16 (a.r2);
                rg.u16 (a.c1);
                rg.u16 (a.c2);
                if (n > 0) rg.u8 (0x10);
                n++;
            }
            if (n == 0) return;
            var nb = new BiffBuf ();
            nb.u16 (0x0020);
            nb.u8 (0);
            nb.u8 (1);
            nb.u16 ((int) rg.len);
            nb.u16 (0);
            nb.u16 (sheet + 1);
            nb.zeros (4);
            nb.u8 (0);
            nb.u8 (code);
            nb.append (rg);
            out_b.record (0x0018, nb);
        }

        private uint8[] build () {
            build_palette ();
            build_fonts ();
            var name_list = new Gee.ArrayList<string> ();
            var name_defs = new Gee.ArrayList<string> ();
            var name_scope = new Gee.ArrayList<int> ();
            foreach (var e in book.names.entries) {
                name_index["-1:" + e.key.casefold ()] = name_list.size;
                name_list.add (e.key);
                name_defs.add (e.value);
                name_scope.add (-1);
            }
            for (int i = 0; i < book.sheets.size; i++) {
                foreach (var e in book.sheets[i].names.entries) {
                    name_index["%d:%s".printf (i, e.key.casefold ())] = name_list.size;
                    name_list.add (e.key);
                    name_defs.add (e.value);
                    name_scope.add (i);
                }
            }
            var sheet_data = new Gee.ArrayList<Bytes> ();
            for (int i = 0; i < book.sheets.size; i++) sheet_data.add (new Bytes (sheet_stream (book.sheets[i], i)));
            var name_recs = new BiffBuf ();
            for (int i = 0; i < name_list.size; i++) {
                string def = name_defs[i].has_prefix ("=") ? name_defs[i] : "=" + name_defs[i];
                Sheet ctx = name_scope[i] >= 0 ? book.sheets[name_scope[i]] : book.sheets[0];
                uint8[] rgce = {};
                uint8[] extra = {};
                try {
                    var node = Formula.parse (def, book, ctx);
                    if (!encode (node, ctx, 0, 0, true, out rgce, out extra)) {
                        rgce = {};
                        extra = {};
                    }
                } catch (FormulaError e) {
                }
                var nb = new BiffBuf ();
                string nm = BiffBuf.clip (name_list[i], 255);
                bool wide = !BiffBuf.narrow (nm);
                nb.u16 (0);
                nb.u8 (0);
                nb.u8 (nm.char_count ());
                nb.u16 (rgce.length);
                nb.u16 (0);
                nb.u16 (name_scope[i] >= 0 ? name_scope[i] + 1 : 0);
                nb.zeros (4);
                nb.u8 (wide ? 1 : 0);
                nb.chars (nm, wide);
                nb.bytes (rgce);
                nb.bytes (extra);
                name_recs.record (0x0018, nb);
            }
            for (int i = 0; i < book.sheets.size; i++) {
                var sh = book.sheets[i];
                var areas = sh.page.print_areas (sh);
                if (areas.size > 0) builtin_name (name_recs, 0x06, i, areas);
                var titles = new Gee.ArrayList<Area> ();
                int r1, r2, c1, c2;
                if (sh.page.title_row_range (out r1, out r2) && r2 < 65536) titles.add (new Area (sh, r1, 0, r2, 255));
                if (sh.page.title_col_range (out c1, out c2) && c2 < 256) titles.add (new Area (sh, 0, c1, 65535, c2));
                if (titles.size > 0) builtin_name (name_recs, 0x07, i, titles);
            }
            var g = new BiffBuf ();
            var bof = new BiffBuf ();
            bof.u16 (0x0600);
            bof.u16 (0x0005);
            bof.u16 (0x0DBB);
            bof.u16 (0x07CC);
            bof.u32 (0x41);
            bof.u32 (0x06);
            g.record (0x0809, bof);
            var cp = new BiffBuf ();
            cp.u16 (1200);
            g.record (0x0042, cp);
            var w1 = new BiffBuf ();
            w1.u16 (0x0168);
            w1.u16 (0x001E);
            w1.u16 (0x3A5C);
            w1.u16 (0x2328);
            w1.u16 (0x0038);
            w1.u16 (0);
            w1.u16 (0);
            w1.u16 (1);
            w1.u16 (0x0258);
            g.record (0x003D, w1);
            var dm = new BiffBuf ();
            dm.u16 (book.date1904 ? 1 : 0);
            g.record (0x0022, dm);
            for (int i = 0; i < fonts.size; i++) font_record (g, fonts[i].style);
            int[] fmts = {};
            foreach (var st in book.styles) fmts += format_index (st.number_format);
            foreach (var e in formats.entries) {
                var fb = new BiffBuf ();
                fb.u16 (e.value);
                fb.long_string (e.key);
                g.record (0x041E, fb);
            }
            for (int i = 0; i < 15; i++) xf_record (g, 0, 0, true, null);
            for (int i = 0; i < book.styles.size; i++) xf_record (g, font_record_index (style_font[i]), fmts[i], false, book.styles[i]);
            var sty = new BiffBuf ();
            sty.u16 (0x8000);
            sty.u8 (0);
            sty.u8 (0xFF);
            g.record (0x0293, sty);
            var pal = new BiffBuf ();
            pal.u16 (56);
            foreach (string h in palette) {
                pal.u8 (Xlsx.hex2 (h, 0));
                pal.u8 (Xlsx.hex2 (h, 2));
                pal.u8 (Xlsx.hex2 (h, 4));
                pal.u8 (0);
            }
            g.record (0x0092, pal);
            uint[] bs_offsets = {};
            for (int i = 0; i < book.sheets.size; i++) {
                var bs = new BiffBuf ();
                bs.u32 (0);
                bs.u8 (book.sheets[i].visibility.clamp (0, 2));
                bs.u8 (0);
                bs.short_string (BiffBuf.clip (book.sheets[i].name, 31));
                bs_offsets += g.len + 4;
                g.record (0x0085, bs);
            }
            if (xti.size > 0 || name_list.size > 0) {
                var sb = new BiffBuf ();
                sb.u16 (book.sheets.size);
                sb.u16 (0x0401);
                g.record (0x01AE, sb);
                if (addin_names.size > 0) {
                    var ab = new BiffBuf ();
                    ab.u16 (1);
                    ab.u16 (0x3A01);
                    g.record (0x01AE, ab);
                    foreach (string an in addin_names) {
                        var en = new BiffBuf ();
                        en.u16 (0);
                        en.u32 (0);
                        en.short_string (an);
                        en.u16 (2);
                        en.u8 (0x1C);
                        en.u8 (0x17);
                        g.record (0x0023, en);
                    }
                }
                var es = new BiffBuf ();
                es.u16 (xti.size);
                foreach (string k in xti) {
                    var parts = k.split (":");
                    int f1 = int.parse (parts[0]), f2 = int.parse (parts[1]);
                    es.u16 (f1 == -2 ? 1 : 0);
                    es.u16 (f1 == -2 ? 0xFFFE : f1);
                    es.u16 (f2 == -2 ? 0xFFFE : f2);
                }
                g.record (0x0017, es);
            }
            g.append (name_recs);
            if (drawing_count > 0) {
                var dgg = new BiffBuf ();
                int fdgg_len = 16 + 8 * dg_shapes.size;
                int opt_len = 18;
                int split_len = 16;
                escher (dgg, 0xF, 0, 0xF000, 8 + fdgg_len + 8 + opt_len + 8 + split_len);
                escher (dgg, 0, 0, 0xF006, fdgg_len);
                dgg.u32 (max_spid + 1);
                dgg.u32 (dg_shapes.size + 1);
                dgg.u32 (total_shapes);
                dgg.u32 (dg_shapes.size);
                for (int i = 0; i < dg_shapes.size; i++) {
                    dgg.u32 (i + 1);
                    dgg.u32 (dg_shapes[i] + 1);
                }
                escher (dgg, 3, 3, 0xF00B, opt_len);
                dgg.u16 (0x00BF);
                dgg.u32 (0x00080008);
                dgg.u16 (0x0181);
                dgg.u32 (0x08000041);
                dgg.u16 (0x01C0);
                dgg.u32 (0x08000040);
                escher (dgg, 0, 4, 0xF11E, split_len);
                dgg.u32 (0x0800000D);
                dgg.u32 (0x0800000C);
                dgg.u32 (0x08000017);
                dgg.u32 (0x100000F7);
                g.record (0x00EB, dgg);
            }
            var ext = new BiffBuf ();
            write_sst (g, g.len, ext);
            g.record (0x00FF, ext);
            g.record (0x000A, null);
            uint pos = g.len;
            for (int i = 0; i < book.sheets.size; i++) {
                g.set_u32 (bs_offsets[i], pos);
                pos += (uint) sheet_data[i].get_size ();
            }
            var all = new ByteArray ();
            all.append (g.b.data);
            foreach (var sd in sheet_data) all.append (sd.get_data ());
            return all.steal ();
        }
    }
}
