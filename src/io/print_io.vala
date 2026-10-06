namespace Singularity.Apps.Spreadsheet {

    public class PrintIo {
        private const string NS_SS = "urn:singularity:spreadsheet";
        private const string NS_SCRIPTS = "urn:singularity:spreadsheet:scripts";
        private const string REL_CUSTOM = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml";
        private const string SCRIPTS_ODS = "Scripts/singularity/scripts.xml";

        private static string num (double d) {
            return Value.format_number_general_full (Math.round (d * 10000) / 10000);
        }

        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        private static string qsheet (Sheet s) {
            return Address.quote_sheet (s.name);
        }

        private static string abs_area (Area a) {
            if (a.c1 == 0 && a.c2 == MAX_COLS - 1) return "$%d:$%d".printf (a.r1 + 1, a.r2 + 1);
            if (a.r1 == 0 && a.r2 == MAX_ROWS - 1) return "$%s:$%s".printf (Address.column_name (a.c1), Address.column_name (a.c2));
            if (a.is_single ()) return Address.cell (a.r1, a.c1, true, true);
            return Address.cell (a.r1, a.c1, true, true) + ":" + Address.cell (a.r2, a.c2, true, true);
        }

        public static string scripts_xml (Workbook book) {
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<scripts xmlns=\"%s\" language=\"SpreadsheetScript\">".printf (NS_SCRIPTS));
            foreach (var m in book.scripts.modules) sb.append ("<module name=\"%s\">%s</module>".printf (esc (m.name), esc (m.source)));
            foreach (var e in book.scripts.shortcuts.entries) sb.append ("<shortcut macro=\"%s\" keys=\"%s\"/>".printf (esc (e.key), esc (e.value)));
            sb.append ("</scripts>");
            return sb.str;
        }

        public static bool read_scripts_xml (Workbook book, string? text) {
            if (text == null) return false;
            var doc = Xlsx.parse (text);
            if (doc == null) return false;
            var root = doc->get_root_element ();
            bool ok = root != null && root->name == "scripts" && root->ns != null && root->ns->href == NS_SCRIPTS;
            if (ok) {
                foreach (Xml.Node* n in Xlsx.list (root)) {
                    if (n->name == "module") book.scripts.modules.add (new ScriptModule (Xlsx.attr (n, "name", "Module1"), n->get_content ()));
                    else if (n->name == "shortcut") book.scripts.shortcuts[Xlsx.attr (n, "macro")] = Xlsx.attr (n, "keys");
                }
                book.scripts.from_file = book.scripts.modules.size > 0;
            }
            delete doc;
            return ok;
        }

        public static void write_xlsx_workbook (XlsxWriter w) {
            var book = w.book;
            if (book.code_name != "") w.put_workbook ("workbookPr.attrs", " codeName=\"%s\"".printf (esc (book.code_name)));
            for (int i = 0; i < book.sheets.size; i++) {
                var s = book.sheets[i];
                var p = s.page;
                var areas = p.print_areas (s);
                if (areas.size > 0) {
                    string[] parts = {};
                    foreach (var a in areas) parts += qsheet (s) + "!" + abs_area (a);
                    w.add_defined_name ("_xlnm.Print_Area", i, string.joinv (",", parts));
                }
                string[] titles = {};
                int c1, c2, r1, r2;
                if (p.title_col_range (out c1, out c2)) titles += qsheet (s) + "!" + PageSetup.cols_text (c1, c2);
                if (p.title_row_range (out r1, out r2)) titles += qsheet (s) + "!" + PageSetup.rows_text (r1, r2);
                if (titles.length > 0) w.add_defined_name ("_xlnm.Print_Titles", i, string.joinv (",", titles));
            }
            if (!book.scripts.is_empty ()) {
                int n = w.next_number ();
                string path = "customXml/item%d.xml".printf (n);
                w.add_text_part (path, scripts_xml (book), "application/xml");
                w.add_workbook_rel (REL_CUSTOM, "../" + path);
            }
        }

        public static void write_xlsx_sheet (XlsxSheetPart part) {
            var s = part.sheet;
            var p = s.page;
            if (s.book != null) {
                var watches = new StringBuilder ();
                foreach (var wt in s.book.watches) if (wt.sheet == s) watches.append ("<cellWatch r=\"%s\"/>".printf (Address.cell (wt.row, wt.col)));
                if (watches.len > 0) part.put ("cellWatches", "<cellWatches>" + watches.str + "</cellWatches>");
            }
            if (s.code_name != "") part.sheet_pr_attrs.append (" codeName=\"%s\"".printf (esc (s.code_name)));
            if (p.fit_to_page) part.sheet_pr.append ("<pageSetUpPr fitToPage=\"1\"/>");
            if (p.center_h || p.center_v || p.gridlines || p.headings) {
                part.put ("printOptions", "<printOptions%s%s%s%s/>".printf (
                    p.center_h ? " horizontalCentered=\"1\"" : "", p.center_v ? " verticalCentered=\"1\"" : "",
                    p.headings ? " headings=\"1\"" : "", p.gridlines ? " gridLines=\"1\"" : ""));
            }
            part.put ("pageMargins", "<pageMargins left=\"%s\" right=\"%s\" top=\"%s\" bottom=\"%s\" header=\"%s\" footer=\"%s\"/>".printf (
                num (p.margin_left), num (p.margin_right), num (p.margin_top), num (p.margin_bottom), num (p.margin_header), num (p.margin_footer)));
            var ps = new StringBuilder ("<pageSetup paperSize=\"%d\"".printf (p.paper));
            if (p.scale != 100) ps.append (" scale=\"%d\"".printf (p.scale));
            if (p.first_page_number > 0) ps.append (" firstPageNumber=\"%d\"".printf (p.first_page_number));
            if (p.fit_width != 1) ps.append (" fitToWidth=\"%d\"".printf (p.fit_width));
            if (p.fit_height != 1) ps.append (" fitToHeight=\"%d\"".printf (p.fit_height));
            if (p.over_then_down) ps.append (" pageOrder=\"overThenDown\"");
            ps.append (" orientation=\"%s\"".printf (p.landscape ? "landscape" : "portrait"));
            if (p.black_and_white) ps.append (" blackAndWhite=\"1\"");
            if (p.first_page_number > 0) ps.append (" useFirstPageNumber=\"1\"");
            ps.append ("/>");
            part.put ("pageSetup", ps.str);
            bool any_hf = p.header != "" || p.footer != "" || p.even_header != "" || p.even_footer != "" || p.first_header != "" || p.first_footer != "" || p.odd_even || p.first_different || !p.scale_with_doc || !p.align_with_margins;
            if (any_hf) {
                var hf = new StringBuilder ("<headerFooter");
                if (p.odd_even) hf.append (" differentOddEven=\"1\"");
                if (p.first_different) hf.append (" differentFirst=\"1\"");
                if (!p.scale_with_doc) hf.append (" scaleWithDoc=\"0\"");
                if (!p.align_with_margins) hf.append (" alignWithMargins=\"0\"");
                hf.append (">");
                if (p.header != "") hf.append ("<oddHeader>%s</oddHeader>".printf (esc (p.header)));
                if (p.footer != "") hf.append ("<oddFooter>%s</oddFooter>".printf (esc (p.footer)));
                if (p.even_header != "") hf.append ("<evenHeader>%s</evenHeader>".printf (esc (p.even_header)));
                if (p.even_footer != "") hf.append ("<evenFooter>%s</evenFooter>".printf (esc (p.even_footer)));
                if (p.first_header != "") hf.append ("<firstHeader>%s</firstHeader>".printf (esc (p.first_header)));
                if (p.first_footer != "") hf.append ("<firstFooter>%s</firstFooter>".printf (esc (p.first_footer)));
                hf.append ("</headerFooter>");
                part.put ("headerFooter", hf.str);
            }
            if (p.row_breaks.size > 0) {
                var rb = new StringBuilder ("<rowBreaks count=\"%d\" manualBreakCount=\"%d\">".printf (p.row_breaks.size, p.row_breaks.size));
                foreach (int r in p.row_breaks) rb.append ("<brk id=\"%d\" max=\"16383\" man=\"1\"/>".printf (r));
                rb.append ("</rowBreaks>");
                part.put ("rowBreaks", rb.str);
            }
            if (p.col_breaks.size > 0) {
                var cb = new StringBuilder ("<colBreaks count=\"%d\" manualBreakCount=\"%d\">".printf (p.col_breaks.size, p.col_breaks.size));
                foreach (int c in p.col_breaks) cb.append ("<brk id=\"%d\" max=\"1048575\" man=\"1\"/>".printf (c));
                cb.append ("</colBreaks>");
                part.put ("colBreaks", cb.str);
            }
        }

        private static bool flag (Xml.Node* n, string name) {
            string v = Xlsx.attr (n, name);
            return v == "1" || v == "true";
        }

        public static void apply_builtin (Workbook book, string name, int local, string value) {
            if (local < 0 || local >= book.sheets.size) return;
            var s = book.sheets[local];
            if (name == "Print_Area") {
                string[] parts = {};
                foreach (string part in value.split (",")) {
                    string t = PageSetup.strip_sheet (part.strip ());
                    if (t != "") parts += t;
                }
                s.page.print_area = string.joinv (",", parts);
            } else if (name == "Print_Titles") {
                foreach (string part in value.split (",")) {
                    string t = PageSetup.strip_sheet (part.strip ());
                    string plain = t.replace ("$", "");
                    if (plain == "") continue;
                    if (plain[0].isdigit ()) s.page.title_rows = t;
                    else s.page.title_cols = t;
                }
            }
        }

        public static void read_xlsx_workbook (Xlsx x) {
            foreach (var bn in x.builtin_names) apply_builtin (x.book, bn.name, bn.local_sheet, bn.value);
            try {
                var wdoc = Xlsx.parse (x.zip.read_text ("xl/workbook.xml"));
                if (wdoc != null) {
                    var wpr = Xlsx.child (wdoc->get_root_element (), "workbookPr");
                    if (wpr != null) x.book.code_name = Xlsx.attr (wpr, "codeName");
                    delete wdoc;
                }
            } catch (Error e) {
            }
            try {
                for (int i = 1; i <= 64; i++) {
                    string path = "customXml/item%d.xml".printf (i);
                    if (!x.zip.has (path)) continue;
                    if (read_scripts_xml (x.book, x.zip.read_text (path))) break;
                }
            } catch (Error e) {
            }
        }

        public static void read_xlsx_sheet (XlsxSheetIn sin) {
            var root = sin.root;
            var s = sin.sheet;
            var p = s.page;
            var pr = Xlsx.child (root, "sheetPr");
            if (pr != null && Xlsx.attr (pr, "codeName") != "") s.code_name = Xlsx.attr (pr, "codeName");
            if (pr != null) {
                var psp = Xlsx.child (pr, "pageSetUpPr");
                if (psp != null && flag (psp, "fitToPage")) p.fit_to_page = true;
            }
            var po = Xlsx.child (root, "printOptions");
            if (po != null) {
                p.center_h = flag (po, "horizontalCentered");
                p.center_v = flag (po, "verticalCentered");
                p.headings = flag (po, "headings");
                p.gridlines = flag (po, "gridLines");
            }
            var pm = Xlsx.child (root, "pageMargins");
            if (pm != null) {
                p.margin_left = double.parse (Xlsx.attr (pm, "left", "0.7"));
                p.margin_right = double.parse (Xlsx.attr (pm, "right", "0.7"));
                p.margin_top = double.parse (Xlsx.attr (pm, "top", "0.75"));
                p.margin_bottom = double.parse (Xlsx.attr (pm, "bottom", "0.75"));
                p.margin_header = double.parse (Xlsx.attr (pm, "header", "0.3"));
                p.margin_footer = double.parse (Xlsx.attr (pm, "footer", "0.3"));
            }
            var ps = Xlsx.child (root, "pageSetup");
            if (ps != null) {
                int paper = int.parse (Xlsx.attr (ps, "paperSize", "1"));
                foreach (var ppr in PaperSize.all ()) if (ppr.code == paper) p.paper = paper;
                p.scale = int.parse (Xlsx.attr (ps, "scale", "100")).clamp (10, 400);
                p.fit_width = int.parse (Xlsx.attr (ps, "fitToWidth", "1"));
                p.fit_height = int.parse (Xlsx.attr (ps, "fitToHeight", "1"));
                p.over_then_down = Xlsx.attr (ps, "pageOrder") == "overThenDown";
                p.landscape = Xlsx.attr (ps, "orientation") == "landscape";
                p.black_and_white = flag (ps, "blackAndWhite");
                if (flag (ps, "useFirstPageNumber")) p.first_page_number = int.parse (Xlsx.attr (ps, "firstPageNumber", "1"));
            }
            var hf = Xlsx.child (root, "headerFooter");
            if (hf != null) {
                p.odd_even = flag (hf, "differentOddEven");
                p.first_different = flag (hf, "differentFirst");
                p.scale_with_doc = Xlsx.attr (hf, "scaleWithDoc", "1") != "0" && Xlsx.attr (hf, "scaleWithDoc") != "false";
                p.align_with_margins = Xlsx.attr (hf, "alignWithMargins", "1") != "0" && Xlsx.attr (hf, "alignWithMargins") != "false";
                foreach (Xml.Node* n in Xlsx.list (hf)) {
                    string t = n->get_content ();
                    switch (n->name) {
                        case "oddHeader": p.header = t; break;
                        case "oddFooter": p.footer = t; break;
                        case "evenHeader": p.even_header = t; break;
                        case "evenFooter": p.even_footer = t; break;
                        case "firstHeader": p.first_header = t; break;
                        case "firstFooter": p.first_footer = t; break;
                    }
                }
            }
            foreach (Xml.Node* b in Xlsx.list (Xlsx.child (root, "rowBreaks"))) {
                int id = int.parse (Xlsx.attr (b, "id"));
                if (id > 0 && Xlsx.attr (b, "man", "1") != "0") p.row_breaks.add (id);
            }
            foreach (Xml.Node* b in Xlsx.list (Xlsx.child (root, "colBreaks"))) {
                int id = int.parse (Xlsx.attr (b, "id"));
                if (id > 0 && Xlsx.attr (b, "man", "1") != "0") p.col_breaks.add (id);
            }
            foreach (Xml.Node* wt in Xlsx.list (Xlsx.child (root, "cellWatches"))) {
                int r, c;
                bool a1, a2;
                if (Address.parse_cell (Xlsx.attr (wt, "r"), out r, out c, out a1, out a2)) s.book.watches.add (new CellWatch (s, r, c));
            }
        }

        private static string cm (double inches) {
            return Value.fixed (inches * 2.54, 3) + "cm";
        }

        private static double inches (string len) {
            string t = len.strip ();
            if (t.has_suffix ("cm")) return double.parse (t.substring (0, t.length - 2)) / 2.54;
            if (t.has_suffix ("mm")) return double.parse (t.substring (0, t.length - 2)) / 25.4;
            if (t.has_suffix ("in")) return double.parse (t.substring (0, t.length - 2));
            if (t.has_suffix ("pt")) return double.parse (t.substring (0, t.length - 2)) / 72;
            return double.parse (t);
        }

        public static string master_name (Workbook book, Sheet s) {
            return "Page%d".printf (book.sheets.index_of (s) + 1);
        }

        private static string region_xml (string tag, string code) {
            string l, c, r;
            HeaderFooter.split (code, out l, out c, out r);
            var sb = new StringBuilder ("<style:%s ss:code=\"%s\">".printf (tag, esc (code)));
            string[] names = { "region-left", "region-center", "region-right" };
            string[] parts = { l, c, r };
            for (int i = 0; i < 3; i++) {
                if (parts[i] == "") continue;
                sb.append ("<style:%s><text:p>%s</text:p></style:%s>".printf (names[i], fields_xml (parts[i]), names[i]));
            }
            sb.append ("</style:%s>".printf (tag));
            return sb.str;
        }

        private static string fields_xml (string section) {
            var sb = new StringBuilder ();
            var text = new StringBuilder ();
            int i = 0, n = section.length;
            while (i < n) {
                char ch = section[i];
                if (ch != '&' || i + 1 >= n) {
                    text.append_c (ch);
                    i++;
                    continue;
                }
                char k = section[i + 1];
                i += 2;
                string? field = null;
                switch (k) {
                    case '&': text.append_c ('&'); continue;
                    case 'P': field = "<text:page-number>1</text:page-number>"; break;
                    case 'N': field = "<text:page-count>1</text:page-count>"; break;
                    case 'D': field = "<text:date/>"; break;
                    case 'T': field = "<text:time/>"; break;
                    case 'F': field = "<text:file-name text:display=\"name-and-extension\"/>"; break;
                    case 'Z': field = "<text:file-name text:display=\"path\"/>"; break;
                    case 'A': field = "<text:sheet-name/>"; break;
                    case '"':
                        int end = section.index_of_char ('"', i);
                        i = end < 0 ? n : end + 1;
                        continue;
                    case 'K':
                        i = int.min (i + 6, n);
                        continue;
                    default:
                        while (i < n && section[i - 1].isdigit () && section[i].isdigit ()) i++;
                        continue;
                }
                sb.append (esc (text.str));
                text.truncate ();
                sb.append (field);
            }
            sb.append (esc (text.str));
            return sb.str;
        }

        public static void write_ods (OdsOut o) {
            var book = o.book;
            foreach (var s in book.sheets) {
                var p = s.page;
                string mname = master_name (book, s);
                string lname = "pm%d".printf (book.sheets.index_of (s) + 1);
                var pl = new StringBuilder ("<style:page-layout style:name=\"%s\"><style:page-layout-properties".printf (lname));
                pl.append (" fo:page-width=\"%s\" fo:page-height=\"%s\"".printf (cm (p.page_width / 72), cm (p.page_height / 72)));
                pl.append (" style:print-orientation=\"%s\"".printf (p.landscape ? "landscape" : "portrait"));
                pl.append (" fo:margin-top=\"%s\" fo:margin-bottom=\"%s\" fo:margin-left=\"%s\" fo:margin-right=\"%s\"".printf (cm (p.margin_top), cm (p.margin_bottom), cm (p.margin_left), cm (p.margin_right)));
                string[] print = { "charts", "drawings", "objects", "zero-values" };
                if (p.gridlines) print += "grid";
                if (p.headings) print += "headers";
                pl.append (" style:print=\"%s\"".printf (string.joinv (" ", print)));
                pl.append (" style:print-page-order=\"%s\"".printf (p.over_then_down ? "ltr" : "ttb"));
                pl.append (" style:first-page-number=\"%s\"".printf (p.first_page_number > 0 ? p.first_page_number.to_string () : "continue"));
                if (p.fit_to_page) {
                    pl.append (" style:scale-to-X=\"%d\" style:scale-to-Y=\"%d\"".printf (p.fit_width, p.fit_height));
                } else {
                    pl.append (" style:scale-to=\"%d%%\"".printf (p.scale));
                }
                string centering = p.center_h && p.center_v ? "both" : (p.center_h ? "horizontal" : (p.center_v ? "vertical" : "none"));
                pl.append (" style:table-centering=\"%s\"".printf (centering));
                pl.append (" ss:paper=\"%d\" ss:margin-header=\"%s\" ss:margin-footer=\"%s\"%s%s%s/>".printf (p.paper, num (p.margin_header), num (p.margin_footer),
                    p.black_and_white ? " ss:black-and-white=\"1\"" : "", p.scale_with_doc ? "" : " ss:scale-with-doc=\"0\"", p.align_with_margins ? "" : " ss:align-with-margins=\"0\""));
                pl.append ("<style:header-style><style:header-footer-properties fo:min-height=\"%s\"/></style:header-style>".printf (cm (double.max (p.margin_top - p.margin_header, 0))));
                pl.append ("<style:footer-style><style:header-footer-properties fo:min-height=\"%s\"/></style:footer-style>".printf (cm (double.max (p.margin_bottom - p.margin_footer, 0))));
                pl.append ("</style:page-layout>");
                o.styles_auto.append (pl.str);
                var mp = new StringBuilder ("<style:master-page style:name=\"%s\" style:page-layout-name=\"%s\">".printf (mname, lname));
                if (p.header != "") mp.append (region_xml ("header", p.header));
                else mp.append ("<style:header style:display=\"false\"/>");
                if (p.odd_even && p.even_header != "") mp.append (region_xml ("header-left", p.even_header));
                if (p.first_different && p.first_header != "") mp.append (region_xml ("header-first", p.first_header));
                if (p.footer != "") mp.append (region_xml ("footer", p.footer));
                else mp.append ("<style:footer style:display=\"false\"/>");
                if (p.odd_even && p.even_footer != "") mp.append (region_xml ("footer-left", p.even_footer));
                if (p.first_different && p.first_footer != "") mp.append (region_xml ("footer-first", p.first_footer));
                mp.append ("</style:master-page>");
                o.master_styles.append (mp.str);
                var ta = new StringBuilder ();
                var areas = p.print_areas (s);
                if (areas.size > 0) {
                    string[] parts = {};
                    foreach (var a in areas) {
                        var full = new Area (s, a.r1, a.c1, a.r2, a.c2);
                        parts += Ods.range_address (full);
                    }
                    ta.append (" table:print-ranges=\"%s\"".printf (esc (string.joinv (" ", parts))));
                }
                if (p.row_breaks.size > 0) {
                    string[] rb = {};
                    foreach (int r in p.row_breaks) rb += r.to_string ();
                    ta.append (" ss:row-breaks=\"%s\"".printf (string.joinv (" ", rb)));
                }
                if (p.col_breaks.size > 0) {
                    string[] cb = {};
                    foreach (int c in p.col_breaks) cb += c.to_string ();
                    ta.append (" ss:col-breaks=\"%s\"".printf (string.joinv (" ", cb)));
                }
                if (ta.len > 0) o.put_table_attr (s, ta.str);
            }
            if (o.master_styles.str.index_of ("style:name=\"Default\"") < 0) o.master_styles.append ("<style:master-page style:name=\"Default\"/>");
            if (!book.scripts.is_empty () && !o.flat) o.add_file (SCRIPTS_ODS, new Bytes (scripts_xml (book).data), "text/xml");
        }

        private static string ss_attr (Xml.Node* n, string name) {
            string? v = n->get_ns_prop (name, NS_SS);
            return v ?? "";
        }

        private static Xml.Node* find_named (Xml.Node* root, string container, string element, string name) {
            if (root == null) return null;
            for (Xml.Node* c = root->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == container) {
                    for (Xml.Node* e = c->children; e != null; e = e->next) {
                        if (e->type == Xml.ElementType.ELEMENT_NODE && e->name == element && Ods.attr (e, "name", Ods.NS_STYLE) == name) return e;
                    }
                }
            }
            return null;
        }

        private static string region_code (Xml.Node* region) {
            string code = ss_attr (region, "code");
            if (code != "") return code;
            string[] names = { "region-left", "region-center", "region-right" };
            string[] tags = { "&L", "&C", "&R" };
            var sb = new StringBuilder ();
            bool any_region = false;
            for (int i = 0; i < 3; i++) {
                var rn = Ods.child (region, names[i]);
                if (rn == null) continue;
                any_region = true;
                string t = odf_text (rn);
                if (t != "") sb.append (tags[i] + t);
            }
            if (!any_region) {
                string t = odf_text (region);
                if (t != "") sb.append ("&C" + t);
            }
            return sb.str;
        }

        private static string odf_text (Xml.Node* n) {
            var sb = new StringBuilder ();
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.TEXT_NODE) {
                    sb.append (c->content.replace ("&", "&&"));
                    continue;
                }
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "page-number": sb.append ("&P"); break;
                    case "page-count": sb.append ("&N"); break;
                    case "date": sb.append ("&D"); break;
                    case "time": sb.append ("&T"); break;
                    case "sheet-name": sb.append ("&A"); break;
                    case "title": sb.append ("&F"); break;
                    case "file-name":
                        sb.append (Ods.attr (c, "display", Ods.NS_TEXT) == "path" ? "&Z" : "&F");
                        break;
                    case "p":
                        if (sb.len > 0) sb.append ("\n");
                        sb.append (odf_text (c));
                        break;
                    default:
                        sb.append (odf_text (c));
                        break;
                }
            }
            return sb.str;
        }

        private static void read_layout (PageSetup p, Xml.Node* layout) {
            var props = Ods.child (layout, "page-layout-properties");
            if (props == null) return;
            double w = inches (Ods.attr (props, "page-width", Ods.NS_FO)) * 72;
            double h = inches (Ods.attr (props, "page-height", Ods.NS_FO)) * 72;
            p.landscape = Ods.attr (props, "print-orientation", Ods.NS_STYLE) == "landscape" || (w > h && w > 0);
            string paper = ss_attr (props, "paper");
            if (paper != "") {
                p.paper = int.parse (paper);
            } else if (w > 0 && h > 0) {
                var ps = PaperSize.by_size (w, h);
                if (ps != null) p.paper = ps.code;
            }
            string mt = Ods.attr (props, "margin-top", Ods.NS_FO);
            if (mt != "") p.margin_top = inches (mt);
            string mb = Ods.attr (props, "margin-bottom", Ods.NS_FO);
            if (mb != "") p.margin_bottom = inches (mb);
            string ml = Ods.attr (props, "margin-left", Ods.NS_FO);
            if (ml != "") p.margin_left = inches (ml);
            string mr = Ods.attr (props, "margin-right", Ods.NS_FO);
            if (mr != "") p.margin_right = inches (mr);
            string mh = ss_attr (props, "margin-header");
            if (mh != "") p.margin_header = double.parse (mh);
            string mf = ss_attr (props, "margin-footer");
            if (mf != "") p.margin_footer = double.parse (mf);
            p.black_and_white = ss_attr (props, "black-and-white") == "1";
            p.scale_with_doc = ss_attr (props, "scale-with-doc") != "0";
            p.align_with_margins = ss_attr (props, "align-with-margins") != "0";
            string print = Ods.attr (props, "print", Ods.NS_STYLE);
            p.gridlines = print.contains ("grid");
            p.headings = print.contains ("headers");
            p.over_then_down = Ods.attr (props, "print-page-order", Ods.NS_STYLE) == "ltr";
            string fp = Ods.attr (props, "first-page-number", Ods.NS_STYLE);
            p.first_page_number = fp != "" && fp != "continue" ? int.parse (fp) : 0;
            string sx = Ods.attr (props, "scale-to-X", Ods.NS_STYLE);
            string sy = Ods.attr (props, "scale-to-Y", Ods.NS_STYLE);
            string pages = Ods.attr (props, "scale-to-pages", Ods.NS_STYLE);
            if (sx != "" || sy != "") {
                p.fit_to_page = true;
                p.fit_width = sx != "" ? int.parse (sx) : 0;
                p.fit_height = sy != "" ? int.parse (sy) : 0;
            } else if (pages != "") {
                p.fit_to_page = true;
                p.fit_width = int.parse (pages);
                p.fit_height = int.parse (pages);
            }
            string sc = Ods.attr (props, "scale-to", Ods.NS_STYLE);
            if (sc != "") p.scale = ((int) Math.round (double.parse (sc.replace ("%", "")))).clamp (10, 400);
            string cen = Ods.attr (props, "table-centering", Ods.NS_STYLE);
            p.center_h = cen == "horizontal" || cen == "both";
            p.center_v = cen == "vertical" || cen == "both";
        }

        private static void read_master (PageSetup p, Xml.Node* master) {
            for (Xml.Node* c = master->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (Ods.attr (c, "display", Ods.NS_STYLE) == "false") continue;
                switch (c->name) {
                    case "header": p.header = region_code (c); break;
                    case "footer": p.footer = region_code (c); break;
                    case "header-left":
                        p.even_header = region_code (c);
                        p.odd_even = true;
                        break;
                    case "footer-left":
                        p.even_footer = region_code (c);
                        p.odd_even = true;
                        break;
                    case "header-first":
                        p.first_header = region_code (c);
                        p.first_different = true;
                        break;
                    case "footer-first":
                        p.first_footer = region_code (c);
                        p.first_different = true;
                        break;
                }
            }
        }

        private static void parse_breaks (Gee.TreeSet<int> set, string list) {
            foreach (string t in list.split (" ")) {
                if (t.strip () == "") continue;
                int v = int.parse (t);
                if (v > 0) set.add (v);
            }
        }

        private static bool breaks_before (OdsIn inp, string style, bool rows) {
            string key = (rows ? "table-row:" : "table-column:") + style;
            if (style == "" || !inp.style_nodes.has_key (key)) return false;
            var st = inp.style_nodes[key];
            var props = Ods.child (st, rows ? "table-row-properties" : "table-column-properties");
            return props != null && Ods.attr (props, "break-before", Ods.NS_FO) == "page";
        }

        private static void scan_rows (OdsIn inp, Sheet s, Xml.Node* container, ref int r, ref int c, bool header, ref int hr1, ref int hr2, ref int hc1, ref int hc2) {
            for (Xml.Node* n = container->children; n != null; n = n->next) {
                if (n->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (n->name) {
                    case "table-row":
                        int rep = int.max (1, int.parse (Ods.attr (n, "number-rows-repeated", Ods.NS_TABLE)));
                        if (r > 0 && r < MAX_ROWS && breaks_before (inp, Ods.attr (n, "style-name", Ods.NS_TABLE), true)) s.page.row_breaks.add (r);
                        if (header) {
                            if (hr1 < 0) hr1 = r;
                            hr2 = r + int.min (rep, 1000) - 1;
                        }
                        r += rep;
                        break;
                    case "table-column":
                        int crep = int.max (1, int.parse (Ods.attr (n, "number-columns-repeated", Ods.NS_TABLE)));
                        if (c > 0 && c < MAX_COLS && breaks_before (inp, Ods.attr (n, "style-name", Ods.NS_TABLE), false)) s.page.col_breaks.add (c);
                        if (header) {
                            if (hc1 < 0) hc1 = c;
                            hc2 = c + int.min (crep, 1000) - 1;
                        }
                        c += crep;
                        break;
                    case "table-header-rows":
                    case "table-header-columns":
                        scan_rows (inp, s, n, ref r, ref c, true, ref hr1, ref hr2, ref hc1, ref hc2);
                        break;
                    case "table-rows":
                    case "table-row-group":
                    case "table-columns":
                    case "table-column-group":
                        scan_rows (inp, s, n, ref r, ref c, header, ref hr1, ref hr2, ref hc1, ref hc2);
                        break;
                }
            }
        }

        public static void read_ods_table (OdsIn inp, Sheet s, Xml.Node* table) {
            var p = s.page;
            string tstyle = Ods.attr (table, "style-name", Ods.NS_TABLE);
            Xml.Node* ts = inp.style_nodes.has_key ("table:" + tstyle) ? inp.style_nodes["table:" + tstyle] : null;
            string master = ts != null ? Ods.attr (ts, "master-page-name", Ods.NS_STYLE) : "";
            if (master == "") master = "Default";
            Xml.Node* mnode = null;
            Xml.Node* auto_styles = null;
            if (inp.styles != null) {
                mnode = find_named (inp.styles, "master-styles", "master-page", master);
                auto_styles = inp.styles;
            }
            if (mnode != null) {
                string lname = Ods.attr (mnode, "page-layout-name", Ods.NS_STYLE);
                var layout = find_named (auto_styles, "automatic-styles", "page-layout", lname);
                if (layout == null) layout = find_named (auto_styles, "styles", "page-layout", lname);
                if (layout != null) read_layout (p, layout);
                read_master (p, mnode);
            }
            string pr = Ods.attr (table, "print-ranges", Ods.NS_TABLE);
            if (pr != "") {
                string[] parts = {};
                foreach (string part in pr.split (" ")) {
                    string t = part.strip ().replace ("$", "");
                    if (t == "") continue;
                    string[] ends = t.split (":");
                    string a = ends[0].substring (ends[0].last_index_of (".") + 1);
                    string b = ends.length > 1 ? ends[1].substring (ends[1].last_index_of (".") + 1) : "";
                    parts += b != "" ? a + ":" + b : a;
                }
                p.print_area = string.joinv (",", parts);
            }
            int r = 0, c = 0, hr1 = -1, hr2 = -1, hc1 = -1, hc2 = -1;
            scan_rows (inp, s, table, ref r, ref c, false, ref hr1, ref hr2, ref hc1, ref hc2);
            if (hr1 >= 0) p.title_rows = PageSetup.rows_text (hr1, hr2);
            if (hc1 >= 0) p.title_cols = PageSetup.cols_text (hc1, hc2);
            string tr = ss_attr (table, "print-title-rows");
            if (tr != "") p.title_rows = tr;
            string tc = ss_attr (table, "print-title-cols");
            if (tc != "") p.title_cols = tc;
            string rb = ss_attr (table, "row-breaks");
            if (rb != "") parse_breaks (p.row_breaks, rb);
            string cb = ss_attr (table, "col-breaks");
            if (cb != "") parse_breaks (p.col_breaks, cb);
        }

        public static void read_ods (OdsIn inp) {
            if (inp.zip == null) return;
            try {
                if (inp.zip.has (SCRIPTS_ODS)) read_scripts_xml (inp.book, inp.zip.read_text (SCRIPTS_ODS));
            } catch (Error e) {
            }
        }
    }
}
