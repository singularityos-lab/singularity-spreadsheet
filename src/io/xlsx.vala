namespace Singularity.Apps.Spreadsheet {

    public class XlsxBuiltinName {
        public string name;
        public int local_sheet;
        public string value;

        public XlsxBuiltinName (string name, int local_sheet, string value) {
            this.name = name;
            this.local_sheet = local_sheet;
            this.value = value;
        }
    }

    public class Xlsx {
        public const double COL_SCALE = 1.4;
        public const double ROW_SCALE = 1.2;

        private const string NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        private const string NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

        public static string[] builtin_formats () {
            string[] f = new string[50];
            for (int i = 0; i < 50; i++) f[i] = "General";
            f[1] = "0";
            f[2] = "0.00";
            f[3] = "#,##0";
            f[4] = "#,##0.00";
            f[5] = "$#,##0;($#,##0)";
            f[6] = "$#,##0;[Red]($#,##0)";
            f[7] = "$#,##0.00;($#,##0.00)";
            f[8] = "$#,##0.00;[Red]($#,##0.00)";
            f[9] = "0%";
            f[10] = "0.00%";
            f[11] = "0.00E+00";
            f[12] = "# ?/?";
            f[13] = "# ??/??";
            f[14] = LocaleInfo.get ().short_date_format ();
            f[15] = "d-mmm-yy";
            f[16] = "d-mmm";
            f[17] = "mmm-yy";
            f[18] = "h:mm AM/PM";
            f[19] = "h:mm:ss AM/PM";
            f[20] = "h:mm";
            f[21] = "h:mm:ss";
            f[22] = LocaleInfo.get ().short_date_format () + " h:mm";
            f[37] = "#,##0;(#,##0)";
            f[38] = "#,##0;[Red](#,##0)";
            f[39] = "#,##0.00;(#,##0.00)";
            f[40] = "#,##0.00;[Red](#,##0.00)";
            f[45] = "mm:ss";
            f[46] = "[h]:mm:ss";
            f[47] = "mm:ss.0";
            f[48] = "##0.0E+0";
            f[49] = "@";
            return f;
        }

        public const string[] INDEXED = {
            "000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF",
            "000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF",
            "800000", "008000", "000080", "808000", "800080", "008080", "C0C0C0", "808080",
            "9999FF", "993366", "FFFFCC", "CCFFFF", "660066", "FF8080", "0066CC", "CCCCFF",
            "000080", "FF00FF", "FFFF00", "00FFFF", "800080", "800000", "008080", "0000FF",
            "00CCFF", "CCFFFF", "CCFFCC", "FFFF99", "99CCFF", "FF99CC", "CC99FF", "FFCC99",
            "3366FF", "33CCCC", "99CC00", "FFCC00", "FF9900", "FF6600", "666699", "969696",
            "003366", "339966", "003300", "333300", "993300", "993366", "333399", "333333"
        };

        private string[] theme = { "FFFFFF", "000000", "E7E6E6", "44546A", "4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47", "0563C1", "954F72" };

        public Workbook book;
        public ZipReader zip;
        public Gee.ArrayList<XlsxBuiltinName> builtin_names = new Gee.ArrayList<XlsxBuiltinName> ();
        private string[] shared = {};
        private int[] xf_map = {};
        private CellStyle[] dxfs = {};
        private Gee.HashMap<string, Gee.HashMap<string, int>> table_styles = new Gee.HashMap<string, Gee.HashMap<string, int>> ();

        public static Workbook load (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            var x = new Xlsx ();
            return x.read (data);
        }

        public static Xml.Doc* parse (string? text) {
            if (text == null) return null;
            return Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOBLANKS | Xml.ParserOption.HUGE);
        }

        public static Xml.Node* child (Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        public static string attr (Xml.Node* n, string name, string def = "") {
            if (n == null) return def;
            string? v = n->get_prop (name);
            return v ?? def;
        }

        public static string text_of (Xml.Node* n) {
            if (n == null) return "";
            string? c = n->get_content ();
            return c ?? "";
        }

        public static string resolve (string base_dir, string target) {
            if (target.has_prefix ("/")) return target.substring (1);
            string[] parts = (base_dir + "/" + target).split ("/");
            var stack = new Gee.ArrayList<string> ();
            foreach (string p in parts) {
                if (p == "" || p == ".") continue;
                if (p == "..") {
                    if (stack.size > 0) stack.remove_at (stack.size - 1);
                    continue;
                }
                stack.add (p);
            }
            return string.joinv ("/", stack.to_array ());
        }

        private Gee.HashMap<string, string> rels (string path) throws Error {
            var map = new Gee.HashMap<string, string> ();
            string dir = Path.get_dirname (path);
            string rel = (dir == "." ? "" : dir + "/") + "_rels/" + Path.get_basename (path) + ".rels";
            var doc = parse (zip.read_text (rel));
            if (doc == null) return map;
            for (Xml.Node* c = doc->get_root_element ()->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                map[attr (c, "Id")] = resolve (dir == "." ? "" : dir, attr (c, "Target"));
            }
            delete doc;
            return map;
        }

        public Workbook read (uint8[] data) throws Error {
            zip = new ZipReader (data);
            book = new Workbook ();
            var wb_rels = rels ("xl/workbook.xml");
            var doc = parse (zip.read_text ("xl/workbook.xml"));
            if (doc == null) throw new ZipError.FORMAT ("missing workbook");
            read_theme ();
            EditIo.read_theme (book, zip.read_text ("xl/theme/theme1.xml"));
            read_shared ();
            read_styles ();
            var root = doc->get_root_element ();
            XlsxDynamic.read_calc (book, child (root, "calcPr"));
            var pr = child (root, "workbookPr");
            if (pr != null) book.date1904 = attr (pr, "date1904") == "1" || attr (pr, "date1904") == "true";
            EditIo.read_workbook (book, root);
            var targets = new Gee.ArrayList<string> ();
            var sheets_node = child (root, "sheets");
            for (Xml.Node* s = sheets_node != null ? sheets_node->children : null; s != null; s = s->next) {
                if (s->type != Xml.ElementType.ELEMENT_NODE) continue;
                string rid = s->get_ns_prop ("id", NS_REL) ?? attr (s, "id");
                var added = book.add_sheet (attr (s, "name"));
                string state = attr (s, "state");
                added.visibility = state == "hidden" ? 1 : (state == "veryHidden" ? 2 : 0);
                targets.add (wb_rels[rid] ?? "");
            }
            var names = child (root, "definedNames");
            for (Xml.Node* n = names != null ? names->children : null; n != null; n = n->next) {
                if (n->type != Xml.ElementType.ELEMENT_NODE) continue;
                string name = attr (n, "name");
                string local = attr (n, "localSheetId");
                if (name.has_prefix ("_xlnm.")) {
                    if (name != "_xlnm._FilterDatabase") builtin_names.add (new XlsxBuiltinName (name.substring (6), local != "" ? int.parse (local) : -1, text_of (n)));
                    continue;
                }
                if (local != "" && int.parse (local) < book.sheets.size) book.sheets[int.parse (local)].names[name] = text_of (n);
                else book.names[name] = text_of (n);
            }
            delete doc;
            XlsxExtras.read_workbook (this, wb_rels);
            PrintIo.read_xlsx_workbook (this);
            for (int i = 0; i < targets.size; i++) {
                if (targets[i] != "") read_sheet (book.sheets[i], targets[i], i);
            }
            if (book.sheets.size == 0) book.add_sheet ();
            book.recalculate ();
            return book;
        }

        private void read_theme () throws Error {
            var doc = parse (zip.read_text ("xl/theme/theme1.xml"));
            if (doc == null) return;
            string[] order = { "lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink" };
            Xml.Node* scheme = null;
            find_node (doc->get_root_element (), "clrScheme", ref scheme);
            if (scheme != null) {
                for (int i = 0; i < order.length; i++) {
                    var c = child (scheme, order[i]);
                    if (c == null) continue;
                    for (Xml.Node* v = c->children; v != null; v = v->next) {
                        if (v->type != Xml.ElementType.ELEMENT_NODE) continue;
                        string val = v->name == "sysClr" ? attr (v, "lastClr") : attr (v, "val");
                        if (val.length == 6) theme[i] = val;
                    }
                }
            }
            delete doc;
        }

        private static void find_node (Xml.Node* n, string name, ref Xml.Node* found) {
            for (Xml.Node* c = n; c != null && found == null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) {
                    found = c;
                    return;
                }
                if (c->children != null) find_node (c->children, name, ref found);
            }
        }

        private void read_shared () throws Error {
            var doc = parse (zip.read_text ("xl/sharedStrings.xml"));
            if (doc == null) return;
            string[] list = {};
            for (Xml.Node* si = doc->get_root_element ()->children; si != null; si = si->next) {
                if (si->type != Xml.ElementType.ELEMENT_NODE || si->name != "si") continue;
                list += rich_text (si);
            }
            shared = list;
            delete doc;
        }

        public static string rich_text (Xml.Node* si) {
            var sb = new StringBuilder ();
            for (Xml.Node* c = si->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "t") sb.append (text_of (c));
                else if (c->name == "r") sb.append (text_of (child (c, "t")));
            }
            return sb.str;
        }

        public string color (Xml.Node* n) {
            if (n == null) return "";
            string rgb = attr (n, "rgb");
            if (rgb.length == 8) return "#" + rgb.substring (2).down ();
            if (rgb.length == 6) return "#" + rgb.down ();
            string base_hex = "";
            string th = attr (n, "theme");
            if (th != "") {
                int t = int.parse (th);
                if (t >= 0 && t < theme.length) base_hex = theme[t];
            }
            string ix = attr (n, "indexed");
            if (ix != "") {
                int k = int.parse (ix);
                if (k >= 0 && k < INDEXED.length) base_hex = INDEXED[k];
                else return "";
            }
            if (base_hex == "") return "";
            double tint = double.parse (attr (n, "tint", "0"));
            int r = hex2 (base_hex, 0);
            int g = hex2 (base_hex, 2);
            int b = hex2 (base_hex, 4);
            if (tint < 0) {
                r = (int) (r * (1 + tint));
                g = (int) (g * (1 + tint));
                b = (int) (b * (1 + tint));
            } else if (tint > 0) {
                r = (int) (r + (255 - r) * tint);
                g = (int) (g + (255 - g) * tint);
                b = (int) (b + (255 - b) * tint);
            }
            return "#%02x%02x%02x".printf (r.clamp (0, 255), g.clamp (0, 255), b.clamp (0, 255));
        }

        public static int hex2 (string hex, int at) {
            int v = 0;
            for (int i = at; i < at + 2 && i < hex.length; i++) {
                char c = hex[i].tolower ();
                v = v * 16 + (c.isdigit () ? c - '0' : (c >= 'a' && c <= 'f' ? c - 'a' + 10 : 0));
            }
            return v;
        }

        private static BorderStyle border_style (string s) {
            switch (s) {
                case "thin": case "hair": return BorderStyle.THIN;
                case "medium": return BorderStyle.MEDIUM;
                case "thick": return BorderStyle.THICK;
                case "dashed": case "mediumDashed": case "dashDot": case "mediumDashDot": case "dashDotDot": case "mediumDashDotDot": case "slantDashDot": return BorderStyle.DASHED;
                case "dotted": return BorderStyle.DOTTED;
                case "double": return BorderStyle.DOUBLE;
                default: return BorderStyle.NONE;
            }
        }

        private void apply_font (CellStyle st, Xml.Node* f) {
            if (f == null) return;
            var b = child (f, "b");
            st.bold = b != null && attr (b, "val", "1") != "0" && attr (b, "val", "1") != "false";
            var i = child (f, "i");
            st.italic = i != null && attr (i, "val", "1") != "0" && attr (i, "val", "1") != "false";
            var u = child (f, "u");
            st.underline = u != null && attr (u, "val", "single") != "none";
            var s = child (f, "strike");
            st.strike = s != null && attr (s, "val", "1") != "0" && attr (s, "val", "1") != "false";
            var sz = child (f, "sz");
            if (sz != null) st.font_size = double.parse (attr (sz, "val", "11"));
            var name = child (f, "name");
            if (name != null) {
                string fam = attr (name, "val");
                st.font_family = fam == "Calibri" || fam == "Aptos Narrow" || fam == "Arial" ? "" : fam;
            }
            string c = color (child (f, "color"));
            st.color = c == "#000000" ? "" : c;
        }

        private void apply_fill (CellStyle st, Xml.Node* fill) {
            if (fill == null) return;
            var p = child (fill, "patternFill");
            if (p != null && attr (p, "patternType") != "" && attr (p, "patternType") != "none") {
                string c = color (child (p, "fgColor"));
                if (c == "") c = color (child (p, "bgColor"));
                st.fill = c;
            }
            var g = child (fill, "gradientFill");
            if (g != null) {
                Xml.Node* stop = child (g, "stop");
                if (stop != null) st.fill = color (child (stop, "color"));
            }
        }

        private void apply_border (CellStyle st, Xml.Node* b) {
            if (b == null) return;
            string[] sides = { "left", "right", "top", "bottom" };
            foreach (string side in sides) {
                var n = child (b, side);
                if (n == null) continue;
                var br = new Border (border_style (attr (n, "style")), color (child (n, "color")));
                switch (side) {
                    case "left": st.left = br; break;
                    case "right": st.right = br; break;
                    case "top": st.top = br; break;
                    default: st.bottom = br; break;
                }
            }
        }

        private static void apply_alignment (CellStyle st, Xml.Node* a) {
            if (a == null) return;
            switch (attr (a, "horizontal")) {
                case "left": st.halign = HAlign.LEFT; break;
                case "center": case "centerContinuous": st.halign = HAlign.CENTER; break;
                case "right": st.halign = HAlign.RIGHT; break;
                case "fill": st.halign = HAlign.FILL; break;
                case "justify": case "distributed": st.halign = HAlign.JUSTIFY; break;
            }
            switch (attr (a, "vertical")) {
                case "top": st.valign = VAlign.TOP; break;
                case "center": case "justify": case "distributed": st.valign = VAlign.CENTER; break;
            }
            string w = attr (a, "wrapText");
            st.wrap = w == "1" || w == "true";
            st.indent = int.parse (attr (a, "indent", "0"));
        }

        private void read_styles () throws Error {
            var doc = parse (zip.read_text ("xl/styles.xml"));
            if (doc == null) return;
            var root = doc->get_root_element ();
            var formats = new Gee.HashMap<int, string> ();
            var builtin = builtin_formats ();
            for (int i = 0; i < builtin.length; i++) formats[i] = builtin[i];
            var nf = child (root, "numFmts");
            for (Xml.Node* n = nf != null ? nf->children : null; n != null; n = n->next) {
                if (n->type == Xml.ElementType.ELEMENT_NODE) formats[int.parse (attr (n, "numFmtId"))] = attr (n, "formatCode");
            }
            var fonts = list (child (root, "fonts"));
            var fills = list (child (root, "fills"));
            var borders = list (child (root, "borders"));
            int[] map = {};
            EditIo.read_style_names (root);
            var xfs = list (child (root, "cellXfs"));
            foreach (var xf in xfs) {
                var st = new CellStyle ();
                int font = int.parse (attr (xf, "fontId", "0"));
                int fill = int.parse (attr (xf, "fillId", "0"));
                int border = int.parse (attr (xf, "borderId", "0"));
                int fmt = int.parse (attr (xf, "numFmtId", "0"));
                if (font < fonts.size) apply_font (st, fonts[font]);
                if (fill < fills.size) apply_fill (st, fills[fill]);
                if (border < borders.size) apply_border (st, borders[border]);
                st.number_format = formats.has_key (fmt) ? formats[fmt] : "General";
                apply_alignment (st, child (xf, "alignment"));
                EditIo.read_xf (st, xf);
                map += book.intern (st);
            }
            xf_map = map;
            CellStyle[] dx = {};
            foreach (Xml.Node* d in list (child (root, "dxfs"))) {
                var st = new CellStyle ();
                var font = child (d, "font");
                if (font != null) {
                    var b = child (font, "b");
                    st.bold = b != null && attr (b, "val", "1") != "0";
                    var it = child (font, "i");
                    st.italic = it != null && attr (it, "val", "1") != "0";
                    st.color = color (child (font, "color"));
                }
                var fill = child (d, "fill");
                if (fill != null) {
                    var p = child (fill, "patternFill");
                    if (p != null) {
                        string c = color (child (p, "bgColor"));
                        if (c == "") c = color (child (p, "fgColor"));
                        st.fill = c;
                    }
                }
                apply_border (st, child (d, "border"));
                dx += st;
            }
            dxfs = dx;
            foreach (Xml.Node* ts in list (child (root, "tableStyles"))) {
                var elements = new Gee.HashMap<string, int> ();
                foreach (Xml.Node* el in list (ts)) elements[attr (el, "type")] = int.parse (attr (el, "dxfId", "-1"));
                table_styles[attr (ts, "name")] = elements;
            }
            delete doc;
        }

        public static Gee.ArrayList<Xml.Node*> list (Xml.Node* parent) {
            var l = new Gee.ArrayList<Xml.Node*> ();
            for (Xml.Node* n = parent != null ? parent->children : null; n != null; n = n->next) {
                if (n->type == Xml.ElementType.ELEMENT_NODE) l.add (n);
            }
            return l;
        }

        private class SharedFormula {
            public Node node;
            public int row;
            public int col;
        }

        private void read_sheet (Sheet sh, string path, int index) throws Error {
            var doc = parse (zip.read_text (path));
            if (doc == null) return;
            var root = doc->get_root_element ();
            var fmt = child (root, "sheetFormatPr");
            if (fmt != null && attr (fmt, "defaultRowHeight") != "") {
                sh.default_row_height = (int) Math.round (double.parse (attr (fmt, "defaultRowHeight")) / 0.75 * ROW_SCALE);
            }
            if (fmt != null && attr (fmt, "defaultColWidth") != "") {
                sh.default_col_width = (int) Math.round ((double.parse (attr (fmt, "defaultColWidth")) * 7 + 5) * COL_SCALE);
            }
            var views = child (root, "sheetViews");
            var view = views != null ? child (views, "sheetView") : null;
            if (view != null) {
                if (attr (view, "showGridLines") == "0" || attr (view, "showGridLines") == "false") sh.show_grid = false;
                var pane = child (view, "pane");
                if (pane != null && (attr (pane, "state") == "frozen" || attr (pane, "state") == "frozenSplit")) {
                    sh.freeze_cols = (int) double.parse (attr (pane, "xSplit", "0"));
                    sh.freeze_rows = (int) double.parse (attr (pane, "ySplit", "0"));
                }
            }
            var props = child (root, "sheetPr");
            if (props != null) {
                string tc = color (child (props, "tabColor"));
                if (tc != "") sh.tab_color = tc;
            }
            foreach (Xml.Node* col in list (child (root, "cols"))) {
                int min = int.parse (attr (col, "min")) - 1;
                int max = int.min (int.parse (attr (col, "max")) - 1, MAX_COLS - 1);
                bool hidden = attr (col, "hidden") == "1" || attr (col, "hidden") == "true";
                string w = attr (col, "width");
                if (max - min > 200 && !hidden && w == "") continue;
                for (int c = min; c <= max && c - min <= 1024; c++) {
                    if (w != "") sh.col_widths[c] = (int) Math.round ((double.parse (w) * 7 + 5) * COL_SCALE);
                    if (hidden) sh.hidden_cols.add (c);
                }
            }
            var shared_f = new Gee.HashMap<string, SharedFormula> ();
            var data = child (root, "sheetData");
            for (Xml.Node* row = data != null ? data->children : null; row != null; row = row->next) {
                if (row->type != Xml.ElementType.ELEMENT_NODE) continue;
                int r = int.parse (attr (row, "r")) - 1;
                string ht = attr (row, "ht");
                if (ht != "" && (attr (row, "customHeight") == "1" || attr (row, "customHeight") == "true")) {
                    sh.row_heights[r] = (int) Math.round (double.parse (ht) / 0.75 * ROW_SCALE);
                }
                if (attr (row, "hidden") == "1" || attr (row, "hidden") == "true") sh.hidden_rows.add (r);
                int next_col = 0;
                for (Xml.Node* c = row->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "c") continue;
                    int rr = r, cc = next_col;
                    string ref_s = attr (c, "r");
                    if (ref_s != "") {
                        bool a1, a2;
                        Address.parse_cell (ref_s, out rr, out cc, out a1, out a2);
                    }
                    if (r < 0) r = rr;
                    next_col = cc + 1;
                    read_cell (sh, c, rr, cc, shared_f);
                }
            }
            foreach (Xml.Node* m in list (child (root, "mergeCells"))) {
                var a = Area.parse (attr (m, "ref"), sh);
                if (a != null && !a.is_single ()) sh.merges.add (a);
            }
            foreach (Xml.Node* cf in list_all (root, "conditionalFormatting")) read_cond (sh, cf);
            EditIo.read_sheet (sh, root);
            EditIo.read_ext_validations (sh, root);
            var af = child (root, "autoFilter");
            if (af != null) {
                var a = Area.parse (attr (af, "ref"), sh);
                if (a != null) {
                    sh.filter = new Filter (a);
                    EditIo.read_filter (book, sh, af, dxfs);
                }
            }
            EditIo.read_sort_state (book, sh, child (root, "sortState"), dxfs);
            var parts = child (root, "tableParts");
            if (parts != null) {
                var sheet_rels = rels (path);
                foreach (Xml.Node* tp in list (parts)) {
                    string rid = tp->get_ns_prop ("id", NS_REL) ?? attr (tp, "id");
                    if (sheet_rels.has_key (rid)) read_table (sh, sheet_rels[rid]);
                }
            }
            var sin = XlsxExtras.sheet_in (this, sh, index, path, root);
            XlsxDynamic.finish_sheet (sh);
            XlsxExtras.read_sheet (sin);
            PrintIo.read_xlsx_sheet (sin);
            sh.recompute_extent ();
            delete doc;
        }

        private string accent_hex (int n) {
            int idx = n <= 0 ? 1 : 3 + n;
            return "#" + theme[idx.clamp (0, theme.length - 1)].down ();
        }

        private static string tint (string hex, double t) {
            int r = hex2 (hex, 1), g = hex2 (hex, 3), b = hex2 (hex, 5);
            r = (int) (r + (255 - r) * t);
            g = (int) (g + (255 - g) * t);
            b = (int) (b + (255 - b) * t);
            return "#%02x%02x%02x".printf (r, g, b);
        }

        private static bool is_dark (string hex) {
            if (hex.length != 7) return false;
            return 0.299 * hex2 (hex, 1) + 0.587 * hex2 (hex, 3) + 0.114 * hex2 (hex, 5) < 150;
        }

        private Gee.HashMap<string, CellStyle> builtin_table (string name) {
            var m = new Gee.HashMap<string, CellStyle> ();
            MatchInfo info;
            if (!/^TableStyle(Light|Medium|Dark)([0-9]+)$/.match (name, 0, out info)) return m;
            string kind = info.fetch (1);
            int n = int.parse (info.fetch (2));
            string accent = accent_hex ((n - 1) % 7);
            var header = new CellStyle ();
            header.bold = true;
            var stripe = new CellStyle ();
            var whole = new CellStyle ();
            if (kind == "Medium") {
                header.fill = accent;
                header.color = "#ffffff";
                stripe.fill = tint (accent, 0.8);
            } else if (kind == "Dark") {
                header.fill = "#000000";
                header.color = "#ffffff";
                whole.fill = accent;
                whole.color = "#ffffff";
                stripe.fill = tint (accent, 0.25);
            } else {
                header.bottom = new Border (BorderStyle.THIN, accent);
                stripe.fill = tint (accent, 0.8);
                whole.top = new Border (BorderStyle.THIN, accent);
                whole.bottom = new Border (BorderStyle.THIN, accent);
            }
            m["headerRow"] = header;
            m["firstRowStripe"] = stripe;
            m["wholeTable"] = whole;
            return m;
        }

        private static void overlay (CellStyle target, CellStyle layer, bool own_fill) {
            if (layer.fill != "" && !own_fill) target.fill = layer.fill;
            if (layer.color != "" && target.color == "") target.color = layer.color;
            if (layer.bold) target.bold = true;
            if (layer.italic) target.italic = true;
            if (layer.top.style != BorderStyle.NONE && target.top.style == BorderStyle.NONE) target.top = layer.top;
            if (layer.bottom.style != BorderStyle.NONE && target.bottom.style == BorderStyle.NONE) target.bottom = layer.bottom;
            if (layer.left.style != BorderStyle.NONE && target.left.style == BorderStyle.NONE) target.left = layer.left;
            if (layer.right.style != BorderStyle.NONE && target.right.style == BorderStyle.NONE) target.right = layer.right;
        }

        private void read_table (Sheet sh, string path) throws Error {
            var doc = parse (zip.read_text (path));
            if (doc == null) return;
            var root = doc->get_root_element ();
            XlsxDynamic.read_table (book, sh, root);
            var area = Area.parse (attr (root, "ref"), sh);
            var info = child (root, "tableStyleInfo");
            bool header_row = attr (root, "headerRowCount", "1") != "0";
            if (area == null || info == null) {
                delete doc;
                return;
            }
            string name = attr (info, "name");
            bool stripes = attr (info, "showRowStripes", "1") != "0";
            var layers = new Gee.HashMap<string, CellStyle> ();
            if (table_styles.has_key (name)) {
                foreach (var e in table_styles[name].entries) {
                    if (e.value >= 0 && e.value < dxfs.length) layers[e.key] = dxfs[e.value];
                }
            } else {
                layers = builtin_table (name);
            }
            if (attr (root, "autoFilter") != "0" && child (root, "autoFilter") != null && sh.filter == null) sh.filter = new Filter (area);
            var cache = new Gee.HashMap<string, int> ();
            for (int r = area.r1; r <= area.r2; r++) {
                bool is_header = header_row && r == area.r1;
                int data_index = r - area.r1 - (header_row ? 1 : 0);
                for (int c = area.c1; c <= area.c2; c++) {
                    var cell = sh.ensure (r, c);
                    var base_style = book.styles[cell.style];
                    bool own_fill = base_style.fill != "";
                    string key = "%d|%d|%d".printf (cell.style, is_header ? -1 : (stripes ? data_index % 2 : 9), (r == area.r2 ? 1 : 0) + (c == area.c1 ? 2 : 0) + (c == area.c2 ? 4 : 0) + (r == area.r1 ? 8 : 0));
                    if (!cache.has_key (key)) {
                        var st = base_style.copy ();
                        var whole = layers["wholeTable"];
                        CellStyle? row_layer = null;
                        if (is_header) row_layer = layers["headerRow"];
                        else if (stripes) row_layer = layers[data_index % 2 == 0 ? "firstRowStripe" : "secondRowStripe"];
                        if (row_layer != null) overlay (st, row_layer, own_fill);
                        if (whole != null) {
                            var edge = whole.copy ();
                            if (r != area.r1) edge.top = new Border ();
                            if (r != area.r2) edge.bottom = new Border ();
                            if (c != area.c1) edge.left = new Border ();
                            if (c != area.c2) edge.right = new Border ();
                            overlay (st, edge, own_fill);
                        }
                        if (st.color == "" && is_dark (st.fill)) st.color = "#ffffff";
                        cache[key] = book.intern (st);
                    }
                    cell.style = cache[key];
                }
            }
            delete doc;
        }

        private static Gee.ArrayList<Xml.Node*> list_all (Xml.Node* parent, string name) {
            var l = new Gee.ArrayList<Xml.Node*> ();
            for (Xml.Node* n = parent->children; n != null; n = n->next) {
                if (n->type == Xml.ElementType.ELEMENT_NODE && n->name == name) l.add (n);
            }
            return l;
        }

        private void read_cond (Sheet sh, Xml.Node* cf) {
            string sqref = attr (cf, "sqref");
            foreach (Xml.Node* rule in list (cf)) {
                if (rule->name != "cfRule") continue;
                foreach (string part in sqref.split (" ")) {
                    var area = Area.parse (part, sh);
                    if (area == null) continue;
                    CondFormat? f = null;
                    string type = attr (rule, "type");
                    var formulas = new Gee.ArrayList<string> ();
                    foreach (Xml.Node* fnode in list (rule)) if (fnode->name == "formula") formulas.add (text_of (fnode));
                    switch (type) {
                        case "cellIs":
                            string op = attr (rule, "operator");
                            CondKind k = CondKind.EQUAL;
                            switch (op) {
                                case "greaterThan": k = CondKind.GREATER; break;
                                case "greaterThanOrEqual": k = CondKind.GREATER_EQUAL; break;
                                case "lessThan": k = CondKind.LESS; break;
                                case "lessThanOrEqual": k = CondKind.LESS_EQUAL; break;
                                case "between": k = CondKind.BETWEEN; break;
                                case "notBetween": k = CondKind.NOT_BETWEEN; break;
                                case "notEqual": k = CondKind.NOT_EQUAL; break;
                            }
                            f = new CondFormat (area, k);
                            if (formulas.size > 0) f.a = formulas[0];
                            if (formulas.size > 1) f.b = formulas[1];
                            break;
                        case "iconSet":
                            break;
                        case "containsText":
                            f = new CondFormat (area, CondKind.TEXT_CONTAINS);
                            f.a = attr (rule, "text");
                            break;
                        case "duplicateValues":
                            f = new CondFormat (area, CondKind.DUPLICATE);
                            break;
                        case "uniqueValues":
                            f = new CondFormat (area, CondKind.UNIQUE);
                            break;
                        case "expression":
                            f = new CondFormat (area, CondKind.FORMULA);
                            if (formulas.size > 0) f.a = formulas[0];
                            break;
                        case "containsBlanks":
                            f = new CondFormat (area, CondKind.BLANK);
                            break;
                        case "containsErrors":
                            f = new CondFormat (area, CondKind.ERRORS);
                            break;
                        case "top10":
                            bool bottom = attr (rule, "bottom") == "1";
                            f = new CondFormat (area, bottom ? CondKind.BOTTOM : CondKind.TOP);
                            f.a = attr (rule, "rank", "10");
                            break;
                        case "aboveAverage":
                            bool below = attr (rule, "aboveAverage") == "0";
                            f = new CondFormat (area, below ? CondKind.BELOW_AVERAGE : CondKind.ABOVE_AVERAGE);
                            break;
                        case "colorScale":
                            f = new CondFormat (area, CondKind.COLOR_SCALE);
                            var scale = child (rule, "colorScale");
                            var colors = new Gee.ArrayList<string> ();
                            foreach (Xml.Node* cn in list (scale)) if (cn->name == "color") colors.add (color (cn));
                            f.three_colors = colors.size >= 3;
                            if (colors.size >= 2) {
                                f.color1 = colors[0];
                                f.color3 = colors[colors.size - 1];
                                if (colors.size >= 3) f.color2 = colors[1];
                            }
                            break;
                        case "dataBar":
                            f = new CondFormat (area, CondKind.DATA_BAR);
                            var bar = child (rule, "dataBar");
                            string bc = color (child (bar, "color"));
                            if (bc != "") f.color1 = bc;
                            break;
                    }
                    if (f == null) f = CondXml.read (area, rule, type, attr (rule, "operator"), formulas);
                    if (f == null) continue;
                    f.stop_if_true = attr (rule, "stopIfTrue") == "1";
                    if (type == "top10") f.percent = attr (rule, "percent") == "1";
                    string dxf = attr (rule, "dxfId");
                    if (dxf != "") {
                        int k = int.parse (dxf);
                        if (k >= 0 && k < dxfs.length) f.style = book.intern (dxfs[k]);
                    }
                    sh.cond_formats.add (f);
                }
            }
        }

        private void read_cell (Sheet sh, Xml.Node* c, int r, int col, Gee.HashMap<string, SharedFormula> shared_f) {
            string t = attr (c, "t", "n");
            int s = int.parse (attr (c, "s", "0"));
            var fnode = child (c, "f");
            var vnode = child (c, "v");
            string v = text_of (vnode);
            Node? formula = null;
            if (fnode != null) {
                string ftext = text_of (fnode);
                string ftype = attr (fnode, "t");
                string si = attr (fnode, "si");
                try {
                    if (ftype == "shared" && ftext == "" && shared_f.has_key (si)) {
                        var master = shared_f[si];
                        formula = Formula.shifted (master.node, r - master.row, col - master.col);
                    } else if (ftext != "") {
                        formula = Formula.parse ("=" + ftext, book, sh);
                        if (ftype == "shared" && si != "") {
                            var m = new SharedFormula ();
                            m.node = formula;
                            m.row = r;
                            m.col = col;
                            shared_f[si] = m;
                        }
                    }
                } catch (FormulaError e) {
                    formula = null;
                }
            }
            if (formula == null && vnode == null && t != "inlineStr" && s == 0) return;
            var cell = sh.ensure (r, col);
            if (s > 0 && s < xf_map.length) cell.style = xf_map[s];
            if (formula != null) {
                cell.formula = formula;
                cell.input = Formula.to_text (formula, sh);
                if (attr (fnode, "t") == "array" && attr (fnode, "ref") != "") XlsxDynamic.note_array (sh, cell, attr (fnode, "ref"), attr (c, "cm") != "");
                else cell.legacy = true;
            }
            Value value = Value.empty ();
            switch (t) {
                case "s":
                    int k = int.parse (v);
                    value = Value.str (k >= 0 && k < shared.length ? shared[k] : "");
                    break;
                case "inlineStr":
                    var is_node = child (c, "is");
                    value = Value.str (is_node != null ? rich_text (is_node) : "");
                    break;
                case "str":
                    value = Value.str (v);
                    break;
                case "b":
                    value = Value.boolean (v == "1" || v == "true");
                    break;
                case "e":
                    value = Value.err (ErrorKind.parse (v));
                    break;
                case "d":
                    double dd;
                    string ff;
                    value = Input.parse_date_time (v.replace ("T", " ").replace ("Z", ""), out dd, out ff) ? Value.num (dd) : Value.str (v);
                    break;
                default:
                    if (v != "") value = Value.num (double.parse (v));
                    break;
            }
            cell.value = value;
            if (formula == null) {
                switch (value.kind) {
                    case ValueKind.NUMBER: cell.input = Value.format_number_general_full (value.number); break;
                    case ValueKind.TEXT:
                        var probe = Input.parse (value.text);
                        cell.input = probe.value.kind == ValueKind.TEXT || value.text == "" ? value.text : "'" + value.text;
                        break;
                    case ValueKind.BOOL: cell.input = value.number != 0 ? "TRUE" : "FALSE"; break;
                    case ValueKind.ERROR: cell.input = value.error.to_string (); break;
                    default: break;
                }
            }
        }
    }
}
