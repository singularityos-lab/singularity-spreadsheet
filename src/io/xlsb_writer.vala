namespace Singularity.Apps.Spreadsheet {

    public class XlsbWriter {
        private Workbook book;
        private XlsWriter enc;
        private Gee.ArrayList<string> sst = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, int> sst_index = new Gee.HashMap<string, int> ();
        private int sst_total = 0;
        private Gee.ArrayList<string> fonts = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> fills = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> borders = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, int> formats = new Gee.HashMap<string, int> ();
        private int[] xf_font = {};
        private int[] xf_fill = {};
        private int[] xf_border = {};
        private int[] xf_fmt = {};
        public int formulas_written;
        public int formulas_as_values;

        public static XlsbWriter save (Workbook book, string path) throws Error {
            var w = new XlsbWriter ();
            w.book = book;
            w.enc = new XlsWriter ();
            w.enc.book = book;
            w.enc.b12 = true;
            FileUtils.set_data (path, w.build ());
            return w;
        }

        private static void rec (BiffBuf out_b, int type, BiffBuf? body) {
            if (type >= 0x80) {
                out_b.u8 ((type & 0x7f) | 0x80);
                out_b.u8 (type >> 7);
            } else {
                out_b.u8 (type);
            }
            uint len = body != null ? body.len : 0;
            do {
                uint b = len & 0x7f;
                len >>= 7;
                if (len > 0) b |= 0x80;
                out_b.u8 (b);
            } while (len > 0);
            if (body != null) out_b.append (body);
        }

        private static void wide (BiffBuf b, string s) {
            b.u32 (s.char_count ());
            b.chars (s, true);
        }

        private int sst_add (string s) {
            sst_total++;
            if (sst_index.has_key (s)) return sst_index[s];
            sst.add (s);
            sst_index[s] = sst.size - 1;
            return sst.size - 1;
        }

        private static void color (BiffBuf b, string hex) {
            if (hex == "") {
                b.u8 (0x01);
                b.u8 (0x40);
                b.u16 (0);
                b.u32 (0);
                return;
            }
            b.u8 (0x05);
            b.u8 (0xFF);
            b.u16 (0);
            b.u8 (Xlsx.hex2 (hex, 1));
            b.u8 (Xlsx.hex2 (hex, 3));
            b.u8 (Xlsx.hex2 (hex, 5));
            b.u8 (0xFF);
        }

        private static int dg (BorderStyle s) {
            switch (s) {
                case BorderStyle.THIN: return 1;
                case BorderStyle.MEDIUM: return 2;
                case BorderStyle.DASHED: return 3;
                case BorderStyle.DOTTED: return 4;
                case BorderStyle.THICK: return 5;
                case BorderStyle.DOUBLE: return 6;
                default: return 0;
            }
        }

        private int intern (Gee.ArrayList<string> list, string key) {
            int i = list.index_of (key);
            if (i >= 0) return i;
            list.add (key);
            return list.size - 1;
        }

        private void build_styles () {
            fonts.add ("0000|11.00||");
            fills.add ("");
            fills.add ("gray");
            borders.add ("0|0|0|0");
            var builtin = Xlsx.builtin_formats ();
            foreach (var st in book.styles) {
                xf_font += intern (fonts, "%d%d%d%d|%s|%s|%s".printf ((int) st.bold, (int) st.italic, (int) st.underline, (int) st.strike, Value.fixed (st.font_size, 2), st.color, st.font_family));
                xf_fill += st.fill != "" ? intern (fills, st.fill) : 0;
                xf_border += intern (borders, "%d%s|%d%s|%d%s|%d%s".printf (dg (st.top.style), st.top.color, dg (st.bottom.style), st.bottom.color, dg (st.left.style), st.left.color, dg (st.right.style), st.right.color));
                int fmt = 0;
                if (st.number_format != "" && st.number_format != "General") {
                    fmt = -1;
                    for (int i = 1; i < builtin.length; i++) if (builtin[i] == st.number_format && i != 14 && i != 22) fmt = i;
                    if (fmt < 0) {
                        if (!formats.has_key (st.number_format)) formats[st.number_format] = 164 + formats.size;
                        fmt = formats[st.number_format];
                    }
                }
                xf_fmt += fmt;
            }
        }

        private uint8[] styles_bin () {
            var b = new BiffBuf ();
            rec (b, 278, null);
            var c = new BiffBuf ();
            c.u32 (formats.size);
            rec (b, 615, c);
            foreach (var e in formats.entries) {
                var f = new BiffBuf ();
                f.u16 (e.value);
                wide (f, e.key);
                rec (b, 44, f);
            }
            rec (b, 616, null);
            c = new BiffBuf ();
            c.u32 (fonts.size);
            rec (b, 611, c);
            foreach (string key in fonts) {
                var parts = key.split ("|");
                string flags = parts[0];
                var f = new BiffBuf ();
                f.u16 ((int) Math.round (double.parse (parts[1]) * 20));
                f.u16 ((flags[1] == '1' ? 2 : 0) | (flags[3] == '1' ? 8 : 0));
                f.u16 (flags[0] == '1' ? 700 : 400);
                f.u16 (0);
                f.u8 (flags[2] == '1' ? 1 : 0);
                f.u8 (2);
                f.u8 (0);
                f.u8 (0);
                color (f, parts[2]);
                f.u8 (0);
                wide (f, parts[3] != "" ? parts[3] : "Calibri");
                rec (b, 43, f);
            }
            rec (b, 612, null);
            c = new BiffBuf ();
            c.u32 (fills.size);
            rec (b, 603, c);
            for (int i = 0; i < fills.size; i++) {
                var f = new BiffBuf ();
                f.u32 (i == 0 ? 0 : (i == 1 ? 17 : 1));
                color (f, i >= 2 ? fills[i] : "");
                color (f, "");
                f.u32 (0);
                f.f64 (0);
                f.f64 (0);
                f.f64 (0);
                f.f64 (0);
                f.f64 (0);
                f.u32 (0);
                rec (b, 45, f);
            }
            rec (b, 604, null);
            c = new BiffBuf ();
            c.u32 (borders.size);
            rec (b, 613, c);
            foreach (string key in borders) {
                var f = new BiffBuf ();
                f.u8 (0);
                var sides = key.split ("|");
                foreach (int idx in new int[] { 0, 1, 2, 3 }) {
                    string side = sides[idx];
                    int d = int.parse (side.substring (0, 1));
                    f.u8 (d);
                    f.u8 (0);
                    color (f, side.length > 1 ? side.substring (1) : "");
                }
                f.u8 (0);
                f.u8 (0);
                color (f, "");
                rec (b, 46, f);
            }
            rec (b, 614, null);
            c = new BiffBuf ();
            c.u32 (1);
            rec (b, 626, c);
            var sx = new BiffBuf ();
            sx.u16 (0xFFFF);
            sx.u16 (0);
            sx.u16 (0);
            sx.u16 (0);
            sx.u16 (0);
            sx.u8 (0);
            sx.u8 (0);
            sx.u16 (0x1010);
            sx.u16 (0);
            rec (b, 47, sx);
            rec (b, 627, null);
            c = new BiffBuf ();
            c.u32 (book.styles.size);
            rec (b, 617, c);
            for (int i = 0; i < book.styles.size; i++) {
                var st = book.styles[i];
                var x = new BiffBuf ();
                x.u16 (0);
                x.u16 (xf_fmt[i]);
                x.u16 (xf_font[i]);
                x.u16 (xf_fill[i]);
                x.u16 (xf_border[i]);
                x.u8 (0);
                x.u8 (st.indent.clamp (0, 250));
                int alc = 0;
                switch (st.halign) {
                    case HAlign.LEFT: alc = 1; break;
                    case HAlign.CENTER: alc = 2; break;
                    case HAlign.RIGHT: alc = 3; break;
                    case HAlign.FILL: alc = 4; break;
                    case HAlign.JUSTIFY: alc = 5; break;
                    default: break;
                }
                int alcv = st.valign == VAlign.TOP ? 0 : (st.valign == VAlign.CENTER ? 1 : 2);
                x.u16 (alc | (alcv << 3) | (st.wrap ? 0x40 : 0) | 0x1000);
                x.u8 (0);
                x.u8 (0);
                rec (b, 47, x);
            }
            rec (b, 618, null);
            c = new BiffBuf ();
            c.u32 (1);
            rec (b, 619, c);
            var sty = new BiffBuf ();
            sty.u32 (0);
            sty.u16 (1);
            sty.u8 (0);
            sty.u8 (0xFF);
            wide (sty, "Normal");
            rec (b, 48, sty);
            rec (b, 620, null);
            rec (b, 279, null);
            return b.b.data;
        }

        private void cell_head (BiffBuf b, int col, int style) {
            b.u32 (col);
            b.u32 (style & 0xFFFFFF);
        }

        private void value_cell (BiffBuf s, int col, int style, Value v) {
            var b = new BiffBuf ();
            cell_head (b, col, style);
            switch (v.kind) {
                case ValueKind.NUMBER:
                    b.f64 (v.number);
                    rec (s, 5, b);
                    break;
                case ValueKind.TEXT:
                    b.u32 (sst_add (v.text));
                    rec (s, 7, b);
                    break;
                case ValueKind.BOOL:
                    b.u8 (v.number != 0 ? 1 : 0);
                    rec (s, 4, b);
                    break;
                case ValueKind.ERROR:
                    b.u8 (XlsWriter.err_byte (v.error));
                    rec (s, 3, b);
                    break;
                default:
                    if (style != 0) rec (s, 1, b);
                    break;
            }
        }

        private void formula_cell (BiffBuf s, Sheet sh, Cell cell) {
            var v = sh.value_at (cell.row, cell.col);
            uint8[] rgce, extra;
            if (!enc.encode (cell.formula, sh, cell.row, cell.col, false, out rgce, out extra)) {
                formulas_as_values++;
                value_cell (s, cell.col, cell.style, v);
                return;
            }
            formulas_written++;
            var b = new BiffBuf ();
            cell_head (b, cell.col, cell.style);
            int type;
            switch (v.kind) {
                case ValueKind.TEXT:
                    wide (b, v.text);
                    type = 8;
                    break;
                case ValueKind.BOOL:
                    b.u8 (v.number != 0 ? 1 : 0);
                    type = 10;
                    break;
                case ValueKind.ERROR:
                    b.u8 (XlsWriter.err_byte (v.error));
                    type = 11;
                    break;
                default:
                    b.f64 (v.kind == ValueKind.NUMBER ? v.number : 0);
                    type = 9;
                    break;
            }
            b.u16 (0);
            b.u32 (rgce.length);
            b.bytes (rgce);
            b.u32 (extra.length);
            b.bytes (extra);
            rec (s, type, b);
        }

        private uint8[] sheet_bin (Sheet sh, int index, out bool has_comments, out Gee.ArrayList<string> links) {
            var s = new BiffBuf ();
            rec (s, 129, null);
            var wsprop = new BiffBuf ();
            wsprop.u8 (0xc9);
            wsprop.u8 (0x04);
            wsprop.u8 (0x02);
            if (sh.tab_color.length == 7) {
                color (wsprop, sh.tab_color);
            } else {
                wsprop.u8 (0x00);
                wsprop.u8 (0x40);
                wsprop.u16 (0);
                wsprop.u16 (0);
                wsprop.u8 (0);
                wsprop.u8 (0xFF);
            }
            wsprop.u32 (0xFFFFFFFF);
            wsprop.u32 (0xFFFFFFFF);
            wsprop.u32 (0);
            rec (s, 147, wsprop);
            var dim = new BiffBuf ();
            dim.u32 (0);
            dim.u32 (int.max (sh.max_row, 0));
            dim.u32 (0);
            dim.u32 (int.max (sh.max_col, 0));
            rec (s, 148, dim);
            rec (s, 133, null);
            var view = new BiffBuf ();
            view.u16 ((sh.show_grid ? 0x03dc : 0x03d8) & (index == 0 ? 0xFFFF : ~0x40));
            view.u32 (0);
            view.u32 (0);
            view.u32 (0);
            view.u8 (0x40);
            view.u8 (0);
            view.u16 (0);
            view.u16 (100);
            view.u16 (0);
            view.u16 (0);
            view.u16 (0);
            view.u32 (0);
            rec (s, 137, view);
            if (sh.freeze_rows > 0 || sh.freeze_cols > 0) {
                var pane = new BiffBuf ();
                pane.f64 (sh.freeze_cols);
                pane.f64 (sh.freeze_rows);
                pane.u32 (sh.freeze_rows);
                pane.u32 (sh.freeze_cols);
                pane.u32 (sh.freeze_rows > 0 && sh.freeze_cols > 0 ? 0 : (sh.freeze_rows > 0 ? 2 : 1));
                pane.u8 (0x03);
                rec (s, 151, pane);
            }
            rec (s, 138, null);
            rec (s, 134, null);
            var cols = new Gee.TreeSet<int> ();
            foreach (int c in sh.col_widths.keys) cols.add (c);
            foreach (int c in sh.hidden_cols) cols.add (c);
            if (cols.size > 0) {
                rec (s, 390, null);
                foreach (int c in cols) {
                    var ci = new BiffBuf ();
                    ci.u32 (c);
                    ci.u32 (c);
                    int px = sh.col_widths.has_key (c) ? sh.col_widths[c] : sh.default_col_width;
                    ci.u32 (((int) Math.round ((px / Xlsx.COL_SCALE - 5) / 7.0 * 256)).clamp (0, 65535));
                    ci.u32 (0);
                    ci.u16 ((sh.hidden_cols.contains (c) ? 1 : 0) | 2);
                    rec (s, 60, ci);
                }
                rec (s, 391, null);
            }
            rec (s, 145, null);
            var rows = new Gee.TreeMap<int, Gee.TreeMap<int, Cell>> ();
            foreach (var cl in sh.cells.values) {
                if (!rows.has_key (cl.row)) rows[cl.row] = new Gee.TreeMap<int, Cell> ();
                rows[cl.row][cl.col] = cl;
            }
            foreach (int r in sh.row_heights.keys) if (!rows.has_key (r)) rows[r] = new Gee.TreeMap<int, Cell> ();
            foreach (int r in sh.hidden_rows) if (!rows.has_key (r)) rows[r] = new Gee.TreeMap<int, Cell> ();
            var spill_vals = new Gee.HashMap<string, Value> ();
            foreach (var e in sh.spills.entries) {
                var area = e.value;
                for (int r = area.r1; r <= area.r2 && r - area.r1 < 100000; r++) {
                    for (int c = area.c1; c <= area.c2 && c - area.c1 < 1000; c++) {
                        if (r == area.r1 && c == area.c1) continue;
                        var cl = sh.get_cell (r, c);
                        if (cl != null && (cl.input != "" || cl.formula != null)) continue;
                        spill_vals["%d:%d".printf (r, c)] = sh.value_at (r, c);
                        if (!rows.has_key (r)) rows[r] = new Gee.TreeMap<int, Cell> ();
                        if (!rows[r].has_key (c)) {
                            var ph = new Cell ();
                            ph.row = r;
                            ph.col = c;
                            rows[r][c] = ph;
                        }
                    }
                }
            }
            has_comments = false;
            links = new Gee.ArrayList<string> ();
            var link_cells = new Gee.ArrayList<Cell> ();
            foreach (var re in rows.entries) {
                int r = re.key;
                var rh = new BiffBuf ();
                rh.u32 (r);
                rh.u32 (0);
                int px = sh.row_heights.has_key (r) ? sh.row_heights[r] : sh.default_row_height;
                rh.u16 (((int) Math.round (px / Xlsx.ROW_SCALE * 0.75 * 20)).clamp (1, 8190));
                rh.u16 ((sh.hidden_rows.contains (r) ? 0x1000 : 0) | (sh.row_heights.has_key (r) ? 0x2000 : 0));
                rh.u8 (0);
                if (re.value.size > 0) {
                    rh.u32 (1);
                    rh.u32 (re.value.ascending_keys.first ());
                    rh.u32 (re.value.ascending_keys.last ());
                } else {
                    rh.u32 (0);
                }
                rec (s, 0, rh);
                foreach (var ce in re.value.entries) {
                    var cell = ce.value;
                    string k = "%d:%d".printf (r, ce.key);
                    if (cell.formula != null) formula_cell (s, sh, cell);
                    else if (cell.input != "") value_cell (s, ce.key, cell.style, cell.value);
                    else if (spill_vals.has_key (k)) value_cell (s, ce.key, cell.style, spill_vals[k]);
                    else if (cell.style != 0) value_cell (s, ce.key, cell.style, Value.empty ());
                    if (cell.note != "") has_comments = true;
                    if (cell.link != "") link_cells.add (cell);
                }
            }
            rec (s, 146, null);
            if (sh.merges.size > 0) {
                var c = new BiffBuf ();
                c.u32 (sh.merges.size);
                rec (s, 177, c);
                foreach (var m in sh.merges) {
                    var mb = new BiffBuf ();
                    mb.u32 (m.r1);
                    mb.u32 (m.r2);
                    mb.u32 (m.c1);
                    mb.u32 (m.c2);
                    rec (s, 176, mb);
                }
                rec (s, 178, null);
            }
            int rid = 1;
            foreach (var cell in link_cells) {
                var h = new BiffBuf ();
                h.u32 (cell.row);
                h.u32 (cell.row);
                h.u32 (cell.col);
                h.u32 (cell.col);
                if (cell.link.has_prefix ("#")) {
                    wide (h, "");
                    wide (h, cell.link.substring (1));
                } else {
                    string url = cell.link;
                    string loc = "";
                    int hash = url.index_of_char ('#');
                    if (hash > 0) {
                        loc = url.substring (hash + 1);
                        url = url.substring (0, hash);
                    }
                    string id = "rId%d".printf (rid++);
                    links.add (id + "\t" + url);
                    wide (h, id);
                    wide (h, loc);
                }
                wide (h, "");
                wide (h, "");
                rec (s, 494, h);
            }
            if (has_comments) {
                var ld = new BiffBuf ();
                wide (ld, "rIdVml");
                rec (s, 551, ld);
            }
            rec (s, 130, null);
            return s.b.data;
        }

        private uint8[] comments_bin (Sheet sh) {
            var list = new Gee.ArrayList<Cell> ();
            foreach (var c in sh.cells.values) if (c.note != "") list.add (c);
            list.sort ((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
            var authors = new Gee.ArrayList<string> ();
            foreach (var c in list) {
                string a = c.note_author != "" ? c.note_author : XlsxExtras.default_author ();
                if (!authors.contains (a)) authors.add (a);
            }
            var b = new BiffBuf ();
            rec (b, 628, null);
            rec (b, 630, null);
            foreach (string a in authors) {
                var ab = new BiffBuf ();
                wide (ab, a);
                rec (b, 632, ab);
            }
            rec (b, 631, null);
            rec (b, 633, null);
            foreach (var c in list) {
                string a = c.note_author != "" ? c.note_author : XlsxExtras.default_author ();
                var cb = new BiffBuf ();
                cb.u32 (authors.index_of (a));
                cb.u32 (c.row);
                cb.u32 (c.row);
                cb.u32 (c.col);
                cb.u32 (c.col);
                cb.zeros (16);
                rec (b, 635, cb);
                var tb = new BiffBuf ();
                tb.u8 (0);
                wide (tb, c.note);
                rec (b, 637, tb);
                rec (b, 636, null);
            }
            rec (b, 634, null);
            rec (b, 629, null);
            return b.b.data;
        }

        private string vml (Sheet sh, int index) {
            var list = new Gee.ArrayList<Cell> ();
            foreach (var c in sh.cells.values) if (c.note != "") list.add (c);
            var sb = new StringBuilder ("<xml xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:x=\"urn:schemas-microsoft-com:office:excel\">");
            sb.append ("<o:shapelayout v:ext=\"edit\"><o:idmap v:ext=\"edit\" data=\"%d\"/></o:shapelayout>".printf (index));
            sb.append ("<v:shapetype id=\"_x0000_t202\" coordsize=\"21600,21600\" o:spt=\"202\" path=\"m,l,21600r21600,l21600,xe\"><v:stroke joinstyle=\"miter\"/><v:path gradientshapeok=\"t\" o:connecttype=\"rect\"/></v:shapetype>");
            int sid = index * 1024 + 1;
            foreach (var c in list) {
                sb.append ("<v:shape id=\"_x0000_s%d\" type=\"#_x0000_t202\" style=\"position:absolute;margin-left:59.25pt;margin-top:1.5pt;width:108pt;height:59.25pt;z-index:1;visibility:hidden\" fillcolor=\"#ffffe1\" o:insetmode=\"auto\"><v:fill color2=\"#ffffe1\"/><v:shadow on=\"t\" color=\"black\" obscured=\"t\"/><v:path o:connecttype=\"none\"/><v:textbox style=\"mso-direction-alt:auto\"><div style=\"text-align:left\"></div></v:textbox>".printf (sid++));
                sb.append ("<x:ClientData ObjectType=\"Note\"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>%d, 15, %d, 2, %d, 15, %d, 16</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>%d</x:Row><x:Column>%d</x:Column></x:ClientData></v:shape>".printf (c.col + 1, int.max (c.row - 1, 0), c.col + 3, int.max (c.row - 1, 0) + 4, c.row, c.col));
            }
            sb.append ("</xml>");
            return sb.str;
        }

        private void name_rec (BiffBuf b, string name, int flags, int itab, uint8[] rgce, uint8[] extra) {
            var nb = new BiffBuf ();
            nb.u32 (flags);
            nb.u8 (0);
            nb.u32 (itab < 0 ? 0xFFFFFFFF : (uint64) itab);
            wide (nb, name);
            nb.u32 (rgce.length);
            nb.bytes (rgce);
            nb.u32 (extra.length);
            nb.bytes (extra);
            nb.u32 (0xFFFFFFFF);
            rec (b, 39, nb);
        }

        private uint8[] build () throws Error {
            build_styles ();
            var names = new Gee.ArrayList<string> ();
            var defs = new Gee.ArrayList<string> ();
            var scopes = new Gee.ArrayList<int> ();
            foreach (var e in book.names.entries) {
                enc.name_index["-1:" + e.key.casefold ()] = names.size;
                names.add (e.key);
                defs.add (e.value);
                scopes.add (-1);
            }
            for (int i = 0; i < book.sheets.size; i++) {
                foreach (var e in book.sheets[i].names.entries) {
                    enc.name_index["%d:%s".printf (i, e.key.casefold ())] = names.size;
                    names.add (e.key);
                    defs.add (e.value);
                    scopes.add (i);
                }
            }
            enc.future_base = names.size;
            var sheet_bins = new Gee.ArrayList<Bytes> ();
            var zip = new ZipWriter ();
            var ct = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"bin\" ContentType=\"application/vnd.ms-excel.sheet.binary.macroEnabled.main\"/><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"vml\" ContentType=\"application/vnd.openxmlformats-officedocument.vmlDrawing\"/>");
            ct.append ("<Override PartName=\"/xl/styles.bin\" ContentType=\"application/vnd.ms-excel.styles\"/><Override PartName=\"/xl/sharedStrings.bin\" ContentType=\"application/vnd.ms-excel.sharedStrings\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/><Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>");
            int comment_n = 0;
            for (int i = 0; i < book.sheets.size; i++) {
                var sh = book.sheets[i];
                bool has_comments;
                Gee.ArrayList<string> links;
                var data = sheet_bin (sh, i, out has_comments, out links);
                string sheet_path = "xl/worksheets/sheet%d.bin".printf (i + 1);
                zip.add (sheet_path, data);
                ct.append ("<Override PartName=\"/%s\" ContentType=\"application/vnd.ms-excel.worksheet\"/>".printf (sheet_path));
                var rels = new StringBuilder ();
                foreach (string l in links) {
                    var parts = l.split ("\t", 2);
                    rels.append ("<Relationship Id=\"%s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"%s\" TargetMode=\"External\"/>".printf (parts[0], XlsxWriter.esc (parts[1])));
                }
                if (has_comments) {
                    comment_n++;
                    zip.add ("xl/comments%d.bin".printf (comment_n), comments_bin (sh));
                    zip.add_text ("xl/drawings/vmlDrawing%d.vml".printf (comment_n), vml (sh, i + 1));
                    ct.append ("<Override PartName=\"/xl/comments%d.bin\" ContentType=\"application/vnd.ms-excel.comments\"/>".printf (comment_n));
                    rels.append ("<Relationship Id=\"rIdCmt\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments\" Target=\"../comments%d.bin\"/>".printf (comment_n));
                    rels.append ("<Relationship Id=\"rIdVml\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing\" Target=\"../drawings/vmlDrawing%d.vml\"/>".printf (comment_n));
                }
                if (rels.len > 0) zip.add_text ("xl/worksheets/_rels/sheet%d.bin.rels".printf (i + 1), "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + rels.str + "</Relationships>");
            }
            var name_bytes = new BiffBuf ();
            for (int i = 0; i < names.size; i++) {
                string def = defs[i].has_prefix ("=") ? defs[i] : "=" + defs[i];
                Sheet ctx = scopes[i] >= 0 ? book.sheets[scopes[i]] : book.sheets[0];
                uint8[] rgce = {};
                uint8[] extra = {};
                try {
                    var node = Formula.parse (def, book, ctx);
                    if (!enc.encode (node, ctx, 0, 0, true, out rgce, out extra)) {
                        rgce = {};
                        extra = {};
                    }
                } catch (FormulaError e) {
                }
                name_rec (name_bytes, names[i], 0, scopes[i], rgce, extra);
            }
            foreach (string fut in enc.future_names) name_rec (name_bytes, fut, fut.has_prefix ("_xlfn.") ? 0x20003 : 0x3, -1, new uint8[0], new uint8[0]);
            for (int i = 0; i < book.sheets.size; i++) {
                var sh = book.sheets[i];
                var areas = sh.page.print_areas (sh);
                if (areas.size == 0) continue;
                var rg = new BiffBuf ();
                int n = 0;
                foreach (var a in areas) {
                    rg.u8 (0x3B);
                    rg.u16 (xti (i));
                    rg.u32 (a.r1);
                    rg.u32 (a.r2);
                    rg.u16 (a.c1);
                    rg.u16 (a.c2);
                    if (n++ > 0) rg.u8 (0x10);
                }
                name_rec (name_bytes, "_xlnm.Print_Area", 0x20, i, rg.b.data, new uint8[0]);
            }
            var wb = new BiffBuf ();
            rec (wb, 131, null);
            var prop = new BiffBuf ();
            prop.u32 (0x00010020 | (book.date1904 ? 1 : 0));
            prop.u32 (0x0001e542);
            wide (prop, "");
            rec (wb, 153, prop);
            rec (wb, 135, null);
            var bv = new BiffBuf ();
            bv.u32 (0x78);
            bv.u32 (0x78);
            bv.u32 (0x3b22);
            bv.u32 (0x2454);
            bv.u32 (0x258);
            bv.u32 (0);
            bv.u32 (0);
            bv.u8 (0x78);
            rec (wb, 158, bv);
            rec (wb, 136, null);
            rec (wb, 143, null);
            var wrels = new StringBuilder ();
            for (int i = 0; i < book.sheets.size; i++) {
                var bs = new BiffBuf ();
                bs.u32 (book.sheets[i].visibility.clamp (0, 2));
                bs.u32 (i + 1);
                wide (bs, "rId%d".printf (i + 1));
                wide (bs, book.sheets[i].name);
                rec (wb, 156, bs);
                wrels.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet%d.bin\"/>".printf (i + 1, i + 1));
            }
            rec (wb, 144, null);
            if (enc.xti.size > 0) {
                rec (wb, 353, null);
                rec (wb, 357, null);
                var es = new BiffBuf ();
                es.u32 (enc.xti.size);
                foreach (string k in enc.xti) {
                    var parts = k.split (":");
                    es.u32 (0);
                    es.u32 (int.parse (parts[0]));
                    es.u32 (int.parse (parts[1]));
                }
                rec (wb, 362, es);
                rec (wb, 354, null);
            }
            wb.append (name_bytes);
            var calc = new BiffBuf ();
            calc.u32 (191029);
            calc.u32 (book.manual_calc ? 0 : 1);
            calc.u32 (book.max_iterations);
            calc.f64 (book.max_change);
            calc.u32 (1);
            calc.u16 (0x006B | (book.iterative ? 0x0004 : 0));
            rec (wb, 157, calc);
            rec (wb, 132, null);
            int n = book.sheets.size;
            wrels.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.bin\"/>".printf (n + 1));
            wrels.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.bin\"/>".printf (n + 2));
            var sstb = new BiffBuf ();
            var hdr = new BiffBuf ();
            hdr.u32 (sst_total);
            hdr.u32 (sst.size);
            rec (sstb, 159, hdr);
            foreach (string str in sst) {
                var it = new BiffBuf ();
                it.u8 (0);
                wide (it, str);
                rec (sstb, 19, it);
            }
            rec (sstb, 160, null);
            ct.append ("<Override PartName=\"/xl/workbook.bin\" ContentType=\"application/vnd.ms-excel.sheet.binary.macroEnabled.main\"/></Types>");
            zip.add_text ("[Content_Types].xml", ct.str);
            zip.add_text ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.bin\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/></Relationships>");
            zip.add_text ("docProps/core.xml", XlsxExtras.core_xml (book));
            zip.add_text ("docProps/app.xml", XlsxExtras.app_xml (book));
            zip.add ("xl/workbook.bin", wb.b.data);
            zip.add_text ("xl/_rels/workbook.bin.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + wrels.str + "</Relationships>");
            zip.add ("xl/styles.bin", styles_bin ());
            zip.add ("xl/sharedStrings.bin", sstb.b.data);
            return zip.finish ();
        }

        private int xti (int sheet) {
            string k = "%d:%d".printf (sheet, sheet);
            int i = enc.xti.index_of (k);
            if (i >= 0) return i;
            enc.xti.add (k);
            return enc.xti.size - 1;
        }
    }
}
