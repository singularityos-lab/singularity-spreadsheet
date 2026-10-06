namespace Singularity.Apps.Spreadsheet {

    private class XlsbRec {
        public int type;
        public uint8[] data;
    }

    private class XlsbReader {
        private uint8[] d;
        private int pos = 0;

        public XlsbReader (owned uint8[] d) {
            this.d = (owned) d;
        }

        public XlsbRec? next () {
            if (pos >= d.length) return null;
            int t = d[pos] & 0x7f;
            if ((d[pos] & 0x80) != 0 && pos + 1 < d.length) {
                pos++;
                t |= (d[pos] & 0x7f) << 7;
            }
            pos++;
            int size = 0;
            int shift = 0;
            for (int k = 0; k < 4 && pos < d.length; k++) {
                uint8 b = d[pos++];
                size |= (b & 0x7f) << shift;
                shift += 7;
                if ((b & 0x80) == 0) break;
            }
            var r = new XlsbRec ();
            r.type = t;
            int end = int.min (pos + size, d.length);
            r.data = d[pos:end];
            pos = end;
            return r;
        }
    }

    public class Xlsb {
        private ZipReader zip;
        private Workbook book;
        private string[] sst = {};
        private int[] xf_style = {};
        private string[] names = {};
        private int[] xti_first = {};
        private int[] xti_last = {};
        private string[] sheet_names = {};
        private bool allow_union = false;
        private string[] theme = { "FFFFFF", "000000", "E7E6E6", "44546A", "4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47", "0563C1", "954F72" };

        public static Workbook load (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            var x = new Xlsb ();
            x.zip = new ZipReader (data);
            x.book = new Workbook ();
            x.run ();
            return x.book;
        }

        private static uint16 u16 (uint8[] d, int o) {
            if (o < 0 || o + 1 >= d.length) return 0;
            return (uint16) (d[o] | (d[o + 1] << 8));
        }

        private static uint32 u32 (uint8[] d, int o) {
            if (o < 0 || o + 3 >= d.length) return 0;
            return (uint32) d[o] | ((uint32) d[o + 1] << 8) | ((uint32) d[o + 2] << 16) | ((uint32) d[o + 3] << 24);
        }

        private static int32 s32 (uint8[] d, int o) {
            return (int32) u32 (d, o);
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

        private static string wide (uint8[] d, int o, out int used) {
            uint32 cch = u32 (d, o);
            used = 4;
            if (cch == 0xFFFFFFFF) return "";
            var sb = new StringBuilder ();
            int p = o + 4;
            for (uint32 i = 0; i < cch && p + 1 < d.length; i++) {
                sb.append_unichar ((unichar) u16 (d, p));
                p += 2;
            }
            used = p - o;
            return sb.str;
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

        private uint8[]? part (string name) {
            try {
                if (!zip.has (name)) return null;
                return zip.read (name);
            } catch (Error e) {
                return null;
            }
        }

        private Gee.HashMap<string, string> rels (string path, Gee.HashMap<string, string>? types = null) {
            var map = new Gee.HashMap<string, string> ();
            string dir = Path.get_dirname (path);
            string rel = (dir == "." ? "" : dir + "/") + "_rels/" + Path.get_basename (path) + ".rels";
            try {
                var doc = Xlsx.parse (zip.read_text (rel));
                if (doc == null) return map;
                foreach (Xml.Node* c in Xlsx.list (doc->get_root_element ())) {
                    string id = Xlsx.attr (c, "Id");
                    string target = Xlsx.attr (c, "Target");
                    map[id] = Xlsx.attr (c, "TargetMode") == "External" ? target : Xlsx.resolve (dir == "." ? "" : dir, target);
                    if (types != null) types[id] = Xlsx.attr (c, "Type");
                }
                delete doc;
            } catch (Error e) {
            }
            return map;
        }

        private string color (uint8[] d, int o) {
            int type = (d[o] >> 1) & 0x7f;
            int idx = d[o + 1];
            if (type == 2) return "#%02x%02x%02x".printf (d[o + 4], d[o + 5], d[o + 6]);
            if (type == 1 && idx < Xlsx.INDEXED.length) return "#" + Xlsx.INDEXED[idx].down ();
            if (type == 3 && idx < theme.length) {
                string hex = theme[idx];
                int16 tint = (int16) u16 (d, o + 2);
                double t = tint / 32767.0;
                int r = Xlsx.hex2 (hex, 0), g = Xlsx.hex2 (hex, 2), b = Xlsx.hex2 (hex, 4);
                if (t < 0) {
                    r = (int) (r * (1 + t));
                    g = (int) (g * (1 + t));
                    b = (int) (b * (1 + t));
                } else if (t > 0) {
                    r = (int) (r + (255 - r) * t);
                    g = (int) (g + (255 - g) * t);
                    b = (int) (b + (255 - b) * t);
                }
                return "#%02x%02x%02x".printf (r.clamp (0, 255), g.clamp (0, 255), b.clamp (0, 255));
            }
            return "";
        }

        private void read_styles (string path) {
            var data = part (path);
            if (data == null) return;
            var rd = new XlsbReader ((owned) data);
            var formats = new Gee.HashMap<int, string> ();
            var builtin = Xlsx.builtin_formats ();
            for (int i = 0; i < builtin.length; i++) formats[i] = builtin[i];
            var fonts = new Gee.ArrayList<CellStyle> ();
            var fills = new Gee.ArrayList<string> ();
            var borders = new Gee.ArrayList<CellStyle> ();
            bool in_cell_xfs = false;
            int[] map = {};
            XlsbRec? r;
            while ((r = rd.next ()) != null) {
                var d = r.data;
                switch (r.type) {
                    case 44:
                        int u;
                        formats[u16 (d, 0)] = wide (d, 2, out u);
                        break;
                    case 43:
                        var f = new CellStyle ();
                        f.font_size = u16 (d, 0) / 20.0;
                        uint16 grbit = u16 (d, 2);
                        f.italic = (grbit & 2) != 0;
                        f.strike = (grbit & 8) != 0;
                        f.bold = u16 (d, 4) >= 700;
                        f.underline = d.length > 8 && d[8] != 0;
                        string c = d.length >= 20 ? color (d, 12) : "";
                        f.color = c == "#000000" ? "" : c;
                        int u2;
                        string nm = d.length > 21 ? wide (d, 21, out u2) : "";
                        f.font_family = nm == "Calibri" || nm == "Aptos Narrow" || nm == "Arial" ? "" : nm;
                        fonts.add (f);
                        break;
                    case 45:
                        uint32 fls = u32 (d, 0);
                        string fc = d.length >= 12 ? color (d, 4) : "";
                        fills.add (fls != 0 && fls != 17 ? fc : "");
                        break;
                    case 46:
                        var bst = new CellStyle ();
                        Border[] sides = {};
                        for (int k = 0; k < 4; k++) {
                            int o = 1 + k * 10;
                            BorderStyle bs;
                            switch (o < d.length ? d[o] : 0) {
                                case 1: case 7: bs = BorderStyle.THIN; break;
                                case 2: bs = BorderStyle.MEDIUM; break;
                                case 3: case 8: case 9: case 10: case 11: case 12: case 13: bs = BorderStyle.DASHED; break;
                                case 4: bs = BorderStyle.DOTTED; break;
                                case 5: bs = BorderStyle.THICK; break;
                                case 6: bs = BorderStyle.DOUBLE; break;
                                default: bs = BorderStyle.NONE; break;
                            }
                            string bc = bs != BorderStyle.NONE && o + 10 <= d.length ? color (d, o + 2) : "";
                            sides += new Border (bs, bc == "#000000" ? "" : bc);
                        }
                        bst.top = sides[0];
                        bst.bottom = sides[1];
                        bst.left = sides[2];
                        bst.right = sides[3];
                        borders.add (bst);
                        break;
                    case 617:
                        in_cell_xfs = true;
                        break;
                    case 618:
                        in_cell_xfs = false;
                        break;
                    case 47:
                        if (!in_cell_xfs) break;
                        var st = new CellStyle ();
                        int ifmt = u16 (d, 2), ifont = u16 (d, 4), ifill = u16 (d, 6);
                        if (ifont < fonts.size) {
                            var f = fonts[ifont];
                            st.bold = f.bold;
                            st.italic = f.italic;
                            st.underline = f.underline;
                            st.strike = f.strike;
                            st.font_size = f.font_size;
                            st.color = f.color;
                            st.font_family = f.font_family;
                        }
                        if (ifill < fills.size) st.fill = fills[ifill];
                        int ib = u16 (d, 8);
                        if (ib < borders.size) {
                            st.top = borders[ib].top;
                            st.bottom = borders[ib].bottom;
                            st.left = borders[ib].left;
                            st.right = borders[ib].right;
                        }
                        st.number_format = formats.has_key (ifmt) ? formats[ifmt] : "General";
                        st.indent = d.length > 11 ? d[11] : 0;
                        uint16 al = u16 (d, 12);
                        switch (al & 7) {
                            case 1: st.halign = HAlign.LEFT; break;
                            case 2: case 6: st.halign = HAlign.CENTER; break;
                            case 3: st.halign = HAlign.RIGHT; break;
                            case 4: st.halign = HAlign.FILL; break;
                            case 5: case 7: st.halign = HAlign.JUSTIFY; break;
                        }
                        switch ((al >> 3) & 7) {
                            case 0: st.valign = VAlign.TOP; break;
                            case 1: case 3: case 4: st.valign = VAlign.CENTER; break;
                        }
                        st.wrap = (al & 0x40) != 0;
                        map += book.intern (st);
                        break;
                }
            }
            xf_style = map;
        }

        private int style_of (uint32 cellflags) {
            int ix = (int) (cellflags & 0xFFFFFF);
            return ix < xf_style.length ? xf_style[ix] : 0;
        }

        private void read_theme () {
            try {
                var doc = Xlsx.parse (zip.read_text ("xl/theme/theme1.xml"));
                if (doc == null) return;
                string[] order = { "lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink" };
                Xml.Node* scheme = find (doc->get_root_element (), "clrScheme");
                if (scheme != null) {
                    for (int i = 0; i < order.length; i++) {
                        var c = Xlsx.child (scheme, order[i]);
                        if (c == null) continue;
                        foreach (Xml.Node* v in Xlsx.list (c)) {
                            string val = v->name == "sysClr" ? Xlsx.attr (v, "lastClr") : Xlsx.attr (v, "val");
                            if (val.length == 6) theme[i] = val;
                        }
                    }
                }
                delete doc;
            } catch (Error e) {
            }
        }

        private static Xml.Node* find (Xml.Node* n, string name) {
            for (Xml.Node* c = n; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
                if (c->children != null) {
                    var f = find (c->children, name);
                    if (f != null) return f;
                }
            }
            return null;
        }

        private void run () throws Error {
            string wb_path = "xl/workbook.bin";
            try {
                var rdoc = Xlsx.parse (zip.read_text ("_rels/.rels"));
                if (rdoc != null) {
                    foreach (Xml.Node* c in Xlsx.list (rdoc->get_root_element ())) {
                        string t = Xlsx.attr (c, "Target");
                        if (t.has_suffix (".bin")) wb_path = t.has_prefix ("/") ? t.substring (1) : t;
                    }
                    delete rdoc;
                }
            } catch (Error e) {
            }
            var wb = part (wb_path);
            if (wb == null) throw new XlsError.FORMAT ("missing workbook.bin");
            var types = new Gee.HashMap<string, string> ();
            var wrels = rels (wb_path, types);
            read_theme ();
            foreach (var e in types.entries) {
                if (e.value.has_suffix ("/styles")) read_styles (wrels[e.key]);
                if (e.value.has_suffix ("/sharedStrings")) read_sst (wrels[e.key]);
            }
            var targets = new Gee.ArrayList<string> ();
            var name_recs = new Gee.ArrayList<Bytes> ();
            var rd = new XlsbReader ((owned) wb);
            XlsbRec? r;
            string[] sn = {};
            while ((r = rd.next ()) != null) {
                var d = r.data;
                switch (r.type) {
                    case 153:
                        book.date1904 = (u32 (d, 0) & 1) != 0;
                        break;
                    case 157:
                        if (d.length >= 26) {
                            book.manual_calc = u32 (d, 4) == 0;
                            book.max_iterations = int.max (1, (int) u32 (d, 8));
                            book.max_change = f64 (d, 12);
                            book.iterative = (u16 (d, 24) & 0x0004) != 0;
                        }
                        break;
                    case 156:
                        int u1, u2;
                        string rid = wide (d, 8, out u1);
                        string name = wide (d, 8 + u1, out u2);
                        sn += name;
                        var added = book.add_sheet (name);
                        added.visibility = (int) (u32 (d, 0) & 3);
                        targets.add (wrels.has_key (rid) ? wrels[rid] : "");
                        break;
                    case 362:
                        uint32 n = u32 (d, 0);
                        int[] f1 = {}, f2 = {};
                        for (uint32 i = 0; i < n; i++) {
                            f1 += s32 (d, 4 + (int) i * 12 + 4);
                            f2 += s32 (d, 4 + (int) i * 12 + 8);
                        }
                        xti_first = f1;
                        xti_last = f2;
                        break;
                    case 39:
                        name_recs.add (new Bytes (d));
                        break;
                }
            }
            sheet_names = sn;
            string[] nm = {};
            foreach (var nb in name_recs) {
                unowned uint8[] d = nb.get_data ();
                int u;
                string name = wide (d, 9, out u);
                nm += name;
            }
            names = nm;
            foreach (var nb in name_recs) {
                unowned uint8[] d = nb.get_data ();
                uint32 flags = u32 (d, 0);
                int32 itab = s32 (d, 5);
                int u;
                string name = wide (d, 9, out u);
                if (name == "_xlnm.Print_Area" || name == "_xlnm.Print_Titles") {
                    int pp = 9 + u;
                    uint32 pc = u32 (d, pp);
                    if (pp + 4 + (int) pc <= d.length && itab >= 0) {
                        allow_union = true;
                        string? pf = decode (d[pp + 4:pp + 4 + (int) pc], 0, 0);
                        allow_union = false;
                        if (pf != null) PrintIo.apply_builtin (book, name.substring (6), itab, pf);
                    }
                    continue;
                }
                if ((flags & 0x20) != 0 || (flags & 1) != 0 || name.has_prefix ("_xlnm.")) continue;
                int p = 9 + u;
                uint32 cce = u32 (d, p);
                if (p + 4 + (int) cce > d.length) continue;
                uint8[] rgce = d[p + 4:p + 4 + (int) cce];
                string? f = decode (rgce, 0, 0);
                if (f == null) continue;
                if (itab >= 0 && itab < book.sheets.size) book.sheets[itab].names[name] = f;
                else book.names[name] = f;
            }
            for (int i = 0; i < targets.size; i++) {
                if (targets[i] != "" && targets[i].has_suffix (".bin")) read_sheet (book.sheets[i], targets[i]);
            }
            try {
                if (zip.has ("xl/vbaProject.bin")) {
                    var v = zip.read ("xl/vbaProject.bin");
                    if (v != null) book.vba_project = new Bytes (v);
                }
            } catch (Error e) {
            }
            if (book.sheets.size == 0) book.add_sheet ();
            book.recalculate ();
        }

        private void read_sst (string path) {
            var data = part (path);
            if (data == null) return;
            var rd = new XlsbReader ((owned) data);
            XlsbRec? r;
            string[] list = {};
            while ((r = rd.next ()) != null) {
                if (r.type != 19) continue;
                int u;
                list += wide (r.data, 1, out u);
            }
            sst = list;
        }

        private void set_value (Sheet sh, int row, int col, Value v, uint32 flags) {
            if (row < 0 || col < 0 || row >= MAX_ROWS || col >= MAX_COLS) return;
            var cell = sh.ensure (row, col);
            cell.value = v;
            switch (v.kind) {
                case ValueKind.NUMBER: cell.input = Value.format_number_general_full (v.number); break;
                case ValueKind.TEXT: cell.input = Input.parse (v.text).value.kind == ValueKind.TEXT && !v.text.has_prefix ("=") ? v.text : "'" + v.text; break;
                case ValueKind.BOOL: cell.input = v.number != 0 ? "TRUE" : "FALSE"; break;
                case ValueKind.ERROR: cell.input = v.error.to_string (); break;
                default: break;
            }
            int st = style_of (flags);
            if (st != 0) cell.style = st;
        }

        private void formula (Sheet sh, int row, int col, uint8[] d, int p) {
            p += 2;
            uint32 cce = u32 (d, p);
            if (cce == 0 || p + 4 + (int) cce > d.length) return;
            uint8[] rgce = d[p + 4:p + 4 + (int) cce];
            string? text = decode (rgce, row, col);
            if (text == null) return;
            try {
                var cell = sh.get_cell (row, col);
                if (cell == null) return;
                var cached = cell.value;
                var node = Formula.parse ("=" + text, book, sh);
                cell.formula = node;
                cell.input = Formula.to_text (node, sh);
                cell.value = cached;
                cell.legacy = true;
            } catch (FormulaError e) {
            }
        }

        private void read_sheet (Sheet sh, string path) {
            var data = part (path);
            if (data == null) return;
            var types = new Gee.HashMap<string, string> ();
            var srels = rels (path, types);
            var rd = new XlsbReader ((owned) data);
            XlsbRec? r;
            int row = 0;
            while ((r = rd.next ()) != null) {
                var d = r.data;
                int col = (int) u32 (d, 0);
                uint32 fl = u32 (d, 4);
                switch (r.type) {
                    case 0:
                        row = (int) u32 (d, 0);
                        int ht = u16 (d, 8);
                        uint16 rf = u16 (d, 10);
                        if ((rf & 0x1000) != 0) sh.hidden_rows.add (row);
                        if ((rf & 0x2000) != 0 && ht > 0) sh.row_heights[row] = (int) Math.round (ht / 20.0 / 0.75 * Xlsx.ROW_SCALE);
                        break;
                    case 1:
                        int bs = style_of (fl);
                        if (bs != 0) sh.set_style (row, col, bs);
                        break;
                    case 2: set_value (sh, row, col, Value.num (rk (u32 (d, 8))), fl); break;
                    case 3: set_value (sh, row, col, Value.err (err_code (d[8])), fl); break;
                    case 4: set_value (sh, row, col, Value.boolean (d[8] != 0), fl); break;
                    case 5: set_value (sh, row, col, Value.num (f64 (d, 8)), fl); break;
                    case 6:
                        int u;
                        set_value (sh, row, col, Value.str (wide (d, 8, out u)), fl);
                        break;
                    case 7:
                        uint32 isst = u32 (d, 8);
                        set_value (sh, row, col, Value.str (isst < sst.length ? sst[isst] : ""), fl);
                        break;
                    case 8:
                        int u3;
                        string sv = wide (d, 8, out u3);
                        set_value (sh, row, col, Value.str (sv), fl);
                        formula (sh, row, col, d, 8 + u3);
                        break;
                    case 9:
                        set_value (sh, row, col, Value.num (f64 (d, 8)), fl);
                        formula (sh, row, col, d, 16);
                        break;
                    case 10:
                        set_value (sh, row, col, Value.boolean (d[8] != 0), fl);
                        formula (sh, row, col, d, 9);
                        break;
                    case 11:
                        set_value (sh, row, col, Value.err (err_code (d[8])), fl);
                        formula (sh, row, col, d, 9);
                        break;
                    case 60:
                        int c1 = (int) u32 (d, 0), c2 = (int) u32 (d, 4);
                        uint32 w = u32 (d, 8);
                        bool hidden = (u16 (d, 16) & 1) != 0;
                        for (int c = c1; c <= int.min (c2, MAX_COLS - 1) && c - c1 < 1024; c++) {
                            sh.col_widths[c] = (int) Math.round ((w / 256.0 * 7 + 5) * Xlsx.COL_SCALE);
                            if (hidden) sh.hidden_cols.add (c);
                        }
                        break;
                    case 147:
                        if (d.length >= 11 && ((d[3] >> 1) & 0x7f) != 0) {
                            string tc = color (d, 3);
                            if (tc != "") sh.tab_color = tc;
                        }
                        break;
                    case 176:
                        var a = new Area (sh, (int) u32 (d, 0), (int) u32 (d, 8), (int) u32 (d, 4), (int) u32 (d, 12));
                        if (!a.is_single ()) sh.merges.add (a);
                        break;
                    case 151:
                        if (d.length > 28 && (d[28] & 1) != 0) {
                            sh.freeze_cols = (int) f64 (d, 0);
                            sh.freeze_rows = (int) f64 (d, 8);
                        }
                        break;
                    case 494:
                        int u4, u5;
                        string rid = wide (d, 16, out u4);
                        string loc = wide (d, 16 + u4, out u5);
                        string link = srels.has_key (rid) ? srels[rid] : "";
                        if (loc != "") link = link == "" ? "#" + loc : link + "#" + loc;
                        if (link == "") break;
                        int r1 = (int) u32 (d, 0), r2 = (int) u32 (d, 4), lc1 = (int) u32 (d, 8), lc2 = (int) u32 (d, 12);
                        for (int rr = r1; rr <= r2 && rr - r1 < 1000; rr++) {
                            for (int cc = lc1; cc <= lc2 && cc - lc1 < 256; cc++) sh.ensure (rr, cc).link = link;
                        }
                        break;
                }
            }
            foreach (var e in types.entries) {
                if (e.value.has_suffix ("/comments")) read_comments (sh, srels[e.key]);
            }
            sh.recompute_extent ();
        }

        private void read_comments (Sheet sh, string path) {
            var data = part (path);
            if (data == null) return;
            var rd = new XlsbReader ((owned) data);
            XlsbRec? r;
            var authors = new Gee.ArrayList<string> ();
            int cr = -1, cc = -1;
            string author = "";
            while ((r = rd.next ()) != null) {
                var d = r.data;
                switch (r.type) {
                    case 632:
                        int u;
                        authors.add (wide (d, 0, out u));
                        break;
                    case 635:
                        int ai = (int) u32 (d, 0);
                        author = ai < authors.size ? authors[ai] : "";
                        cr = (int) u32 (d, 4);
                        cc = (int) u32 (d, 12);
                        break;
                    case 637:
                        if (cr < 0) break;
                        int u2;
                        string text = wide (d, 1, out u2);
                        if (author != "" && text.has_prefix (author + ":")) text = text.substring (author.length + 1);
                        var cell = sh.ensure (cr, cc);
                        cell.note = text.strip ();
                        cell.note_author = author;
                        cr = -1;
                        break;
                }
            }
        }

        private string sheet_ref (int ixti) {
            if (ixti < 0 || ixti >= xti_first.length) return "#REF!";
            int a = xti_first[ixti], b = xti_last[ixti];
            if (a < 0 || a >= sheet_names.length) return "#REF!";
            string n1 = sheet_names[a];
            if (b == a || b < 0 || b >= sheet_names.length) return Address.quote_sheet (n1) + "!";
            string n2 = sheet_names[b];
            if (Address.quote_sheet (n1) == n1 && Address.quote_sheet (n2) == n2) return n1 + ":" + n2 + "!";
            return "'" + (n1 + ":" + n2).replace ("'", "''") + "'!";
        }

        private static string cell_text (uint32 row, int colf, int base_r, int base_c, bool relative_mode) {
            bool col_rel = (colf & 0x4000) != 0;
            bool row_rel = (colf & 0x8000) != 0;
            int col = colf & 0x3FFF;
            int r = (int) row;
            if (relative_mode) {
                if (row_rel) r = base_r + (int32) row;
                if (col_rel) {
                    int off = col >= 0x2000 ? col - 0x4000 : col;
                    col = base_c + off;
                }
            }
            if (r < 0 || col < 0 || r >= MAX_ROWS || col >= MAX_COLS) return "#REF!";
            return Address.cell (r, col, !row_rel, !col_rel);
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

        private static string binop (int id) {
            string[] ops = { "", "", "", "+", "-", "*", "/", "^", "&", "<", "<=", "=", ">=", ">", "<>", " ", ",", ":" };
            return id < ops.length ? ops[id] : "";
        }

        private static string pop_wrap (Gee.ArrayList<string> stack, Gee.ArrayList<int> precs, int need) {
            int pr = precs.remove_at (precs.size - 1);
            string t = stack.remove_at (stack.size - 1);
            return pr < need ? "(" + t + ")" : t;
        }

        private string? decode (uint8[] rgce, int base_r, int base_c) {
            var stack = new Gee.ArrayList<string> ();
            var precs = new Gee.ArrayList<int> ();
            int p = 0;
            while (p < rgce.length) {
                int id = rgce[p++];
                int bid = id >= 0x20 ? ((id & 0x1F) | 0x20) : id;
                switch (bid) {
                    case 0x03: case 0x04: case 0x05: case 0x06: case 0x07: case 0x08: case 0x09: case 0x0A:
                    case 0x0B: case 0x0C: case 0x0D: case 0x0E: case 0x10: case 0x11:
                        if (stack.size < 2) return null;
                        if (bid == 0x10 && !allow_union) return null;
                        string op = binop (bid);
                        int po = op_prec (op);
                        int pb = precs.remove_at (precs.size - 1);
                        string b = stack.remove_at (stack.size - 1);
                        string a = pop_wrap (stack, precs, po);
                        if (pb < po || (pb == po && op != ":")) b = "(" + b + ")";
                        stack.add (a + op + b);
                        precs.add (po);
                        break;
                    case 0x12:
                    case 0x13:
                        if (stack.size < 1) return null;
                        stack.add ((bid == 0x12 ? "+" : "-") + pop_wrap (stack, precs, 6));
                        precs.add (6);
                        break;
                    case 0x14:
                        if (stack.size < 1) return null;
                        stack.add (pop_wrap (stack, precs, 7) + "%");
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
                        int cch = u16 (rgce, p);
                        var sb = new StringBuilder ();
                        for (int i = 0; i < cch; i++) sb.append_unichar ((unichar) u16 (rgce, p + 2 + i * 2));
                        p += 2 + cch * 2;
                        stack.add ("\"" + sb.str.replace ("\"", "\"\"") + "\"");
                        precs.add (9);
                        break;
                    case 0x19:
                        int kind = rgce[p];
                        if ((kind & 0x04) != 0) return null;
                        p += 3;
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
                        stack.add (Value.format_number_general_full (u16 (rgce, p)));
                        precs.add (9);
                        p += 2;
                        break;
                    case 0x1F:
                        stack.add (Value.format_number_general_full (f64 (rgce, p)));
                        precs.add (9);
                        p += 8;
                        break;
                    case 0x21:
                    case 0x22:
                        int argc, iftab;
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
                        string nm = names[ni];
                        if (nm.has_prefix ("_xlfn.")) nm = nm.substring (6);
                        stack.add (nm);
                        precs.add (9);
                        break;
                    case 0x24:
                    case 0x2C:
                        stack.add (cell_text (u32 (rgce, p), u16 (rgce, p + 4), base_r, base_c, bid == 0x2C));
                        precs.add (9);
                        p += 6;
                        break;
                    case 0x25:
                    case 0x2D:
                        string ca = cell_text (u32 (rgce, p), u16 (rgce, p + 8), base_r, base_c, bid == 0x2D);
                        string cb = cell_text (u32 (rgce, p + 4), u16 (rgce, p + 10), base_r, base_c, bid == 0x2D);
                        p += 12;
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
                        p += 6;
                        stack.add ("#REF!");
                        precs.add (9);
                        break;
                    case 0x2B:
                        p += 12;
                        stack.add ("#REF!");
                        precs.add (9);
                        break;
                    case 0x3A:
                        string pre = sheet_ref (u16 (rgce, p));
                        stack.add (pre == "#REF!" ? pre : pre + cell_text (u32 (rgce, p + 2), u16 (rgce, p + 6), base_r, base_c, false));
                        precs.add (9);
                        p += 8;
                        break;
                    case 0x3B:
                        string pre2 = sheet_ref (u16 (rgce, p));
                        string a1 = cell_text (u32 (rgce, p + 2), u16 (rgce, p + 10), base_r, base_c, false);
                        string a2 = cell_text (u32 (rgce, p + 6), u16 (rgce, p + 12), base_r, base_c, false);
                        p += 14;
                        stack.add (pre2 == "#REF!" ? pre2 : pre2 + a1 + ":" + a2);
                        precs.add (9);
                        break;
                    case 0x3C:
                        p += 8;
                        stack.add ("#REF!");
                        precs.add (9);
                        break;
                    case 0x3D:
                        p += 14;
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
