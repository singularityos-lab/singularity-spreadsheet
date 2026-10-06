namespace Singularity.Apps.Spreadsheet {

    public class XlsxExtras {
        private const string REL_COMMENTS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments";
        private const string REL_VML = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing";
        private const string REL_LINK = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink";
        private const string REL_VBA = "http://schemas.microsoft.com/office/2006/relationships/vbaProject";
        private const string NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        public static string default_author () {
            string n = Environment.get_real_name ();
            if (n == "" || n == "Unknown") n = Environment.get_user_name ();
            return n != "" ? n : "Author";
        }

        public static void write_workbook (XlsxWriter w) {
            AnalysisStore.write_xlsx (w);
            CommentsIo.write_workbook (w);
            RevisionsIo.write_xlsx (w);
            var book = w.book;
            for (int i = 0; i < book.sheets.size; i++) {
                foreach (var e in book.sheets[i].names.entries) w.add_defined_name (e.key, i, XlsxWriter.strip_eq (e.value));
            }
            bool macro = w.main_type.contains ("macroEnabled");
            if (macro && book.vba_project != null) {
                w.add_binary_part ("xl/vbaProject.bin", book.vba_project, "application/vnd.ms-office.vbaProject");
                w.add_workbook_rel (REL_VBA, "vbaProject.bin");
            }
        }

        public static void write_sheet (XlsxSheetPart part) {
            write_links (part);
            write_notes (part);
            CommentsIo.write_sheet (part);
            XlsxDrawing.write_sheet (part);
        }

        private static Gee.ArrayList<Cell> sorted_cells (Sheet s, bool notes) {
            var list = new Gee.ArrayList<Cell> ();
            foreach (var c in s.cells.values) {
                if (notes ? c.note != "" : c.link != "") list.add (c);
            }
            list.sort ((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
            return list;
        }

        private static void write_links (XlsxSheetPart part) {
            var list = sorted_cells (part.sheet, false);
            if (list.size == 0) return;
            var sb = new StringBuilder ("<hyperlinks>");
            foreach (var c in list) {
                string addr = Address.cell (c.row, c.col);
                if (c.link.has_prefix ("#")) {
                    sb.append ("<hyperlink ref=\"%s\" location=\"%s\" display=\"%s\"/>".printf (addr, esc (c.link.substring (1)), esc (c.link.substring (1))));
                } else {
                    string id = part.add_rel (REL_LINK, c.link, true);
                    sb.append ("<hyperlink ref=\"%s\" r:id=\"%s\"/>".printf (addr, id));
                }
            }
            sb.append ("</hyperlinks>");
            part.put ("hyperlinks", sb.str);
        }

        private static void write_notes (XlsxSheetPart part) {
            var list = sorted_cells (part.sheet, true);
            CommentsIo.add_legacy (part.sheet, list);
            if (list.size == 0) return;
            int n = part.writer.next_number ();
            var authors = new Gee.ArrayList<string> ();
            var cx = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<comments xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">");
            var body = new StringBuilder ();
            foreach (var c in list) {
                string author = c.note_author != "" ? c.note_author : default_author ();
                int ai = authors.index_of (author);
                if (ai < 0) {
                    authors.add (author);
                    ai = authors.size - 1;
                }
                body.append ("<comment ref=\"%s\" authorId=\"%d\"><text><r><rPr><sz val=\"9\"/><color indexed=\"81\"/><rFont val=\"Tahoma\"/><family val=\"2\"/></rPr><t xml:space=\"preserve\">%s</t></r></text></comment>".printf (
                    Address.cell (c.row, c.col), ai, esc (c.note)));
            }
            cx.append ("<authors>");
            foreach (string a in authors) cx.append ("<author>%s</author>".printf (esc (a)));
            cx.append ("</authors><commentList>");
            cx.append (body.str);
            cx.append ("</commentList></comments>");
            var vml = new StringBuilder ("<xml xmlns:v=\"urn:schemas-microsoft-com:vml\" xmlns:o=\"urn:schemas-microsoft-com:office:office\" xmlns:x=\"urn:schemas-microsoft-com:office:excel\">");
            vml.append ("<o:shapelayout v:ext=\"edit\"><o:idmap v:ext=\"edit\" data=\"%d\"/></o:shapelayout>".printf (part.index));
            vml.append ("<v:shapetype id=\"_x0000_t202\" coordsize=\"21600,21600\" o:spt=\"202\" path=\"m,l,21600r21600,l21600,xe\"><v:stroke joinstyle=\"miter\"/><v:path gradientshapeok=\"t\" o:connecttype=\"rect\"/></v:shapetype>");
            int sid = part.index * 1024 + 1;
            foreach (var c in list) {
                vml.append ("<v:shape id=\"_x0000_s%d\" type=\"#_x0000_t202\" style=\"position:absolute;margin-left:59.25pt;margin-top:1.5pt;width:108pt;height:59.25pt;z-index:%d;visibility:hidden\" fillcolor=\"#ffffe1\" o:insetmode=\"auto\">".printf (sid++, sid - part.index * 1024));
                vml.append ("<v:fill color2=\"#ffffe1\"/><v:shadow on=\"t\" color=\"black\" obscured=\"t\"/><v:path o:connecttype=\"none\"/><v:textbox style=\"mso-direction-alt:auto\"><div style=\"text-align:left\"></div></v:textbox>");
                vml.append ("<x:ClientData ObjectType=\"Note\"><x:MoveWithCells/><x:SizeWithCells/><x:Anchor>%d, 15, %d, 2, %d, 15, %d, 16</x:Anchor><x:AutoFill>False</x:AutoFill><x:Row>%d</x:Row><x:Column>%d</x:Column></x:ClientData></v:shape>".printf (
                    c.col + 1, int.max (c.row - 1, 0), c.col + 3, int.max (c.row - 1, 0) + 4, c.row, c.col));
            }
            vml.append ("</xml>");
            string cname = "xl/comments%d.xml".printf (n);
            string vname = "xl/drawings/vmlDrawing%d.vml".printf (n);
            part.writer.add_text_part (cname, cx.str, "application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml");
            part.writer.add_text_part (vname, vml.str, null);
            part.writer.defaults["vml"] = "application/vnd.openxmlformats-officedocument.vmlDrawing";
            part.add_rel (REL_COMMENTS, "../comments%d.xml".printf (n));
            string vid = part.add_rel (REL_VML, "../drawings/vmlDrawing%d.vml".printf (n));
            part.put ("legacyDrawing", "<legacyDrawing r:id=\"%s\"/>".printf (vid));
        }

        public static string core_xml (Workbook book) {
            var now = new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%SZ");
            var p = book.properties;
            string created = p.has_key ("created") ? p["created"] : now;
            string creator = p.has_key ("creator") ? p["creator"] : default_author ();
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:dcmitype=\"http://purl.org/dc/dcmitype/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">");
            if (p.has_key ("title")) sb.append ("<dc:title>%s</dc:title>".printf (esc (p["title"])));
            if (p.has_key ("subject")) sb.append ("<dc:subject>%s</dc:subject>".printf (esc (p["subject"])));
            sb.append ("<dc:creator>%s</dc:creator>".printf (esc (creator)));
            if (p.has_key ("keywords")) sb.append ("<cp:keywords>%s</cp:keywords>".printf (esc (p["keywords"])));
            if (p.has_key ("description")) sb.append ("<dc:description>%s</dc:description>".printf (esc (p["description"])));
            sb.append ("<cp:lastModifiedBy>%s</cp:lastModifiedBy>".printf (esc (default_author ())));
            if (p.has_key ("category")) sb.append ("<cp:category>%s</cp:category>".printf (esc (p["category"])));
            sb.append ("<dcterms:created xsi:type=\"dcterms:W3CDTF\">%s</dcterms:created><dcterms:modified xsi:type=\"dcterms:W3CDTF\">%s</dcterms:modified></cp:coreProperties>".printf (esc (created), now));
            return sb.str;
        }

        public static string app_xml (Workbook book) {
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><Application>Singularity Spreadsheet</Application><DocSecurity>0</DocSecurity><ScaleCrop>false</ScaleCrop>");
            sb.append ("<HeadingPairs><vt:vector size=\"2\" baseType=\"variant\"><vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant><vt:variant><vt:i4>%d</vt:i4></vt:variant></vt:vector></HeadingPairs>".printf (book.sheets.size));
            sb.append ("<TitlesOfParts><vt:vector size=\"%d\" baseType=\"lpstr\">".printf (book.sheets.size));
            foreach (var s in book.sheets) sb.append ("<vt:lpstr>%s</vt:lpstr>".printf (esc (s.name)));
            sb.append ("</vt:vector></TitlesOfParts>");
            if (book.properties.has_key ("company")) sb.append ("<Company>%s</Company>".printf (esc (book.properties["company"])));
            if (book.properties.has_key ("manager")) sb.append ("<Manager>%s</Manager>".printf (esc (book.properties["manager"])));
            sb.append ("<LinksUpToDate>false</LinksUpToDate><SharedDoc>false</SharedDoc><HyperlinksChanged>false</HyperlinksChanged><AppVersion>16.0300</AppVersion></Properties>");
            return sb.str;
        }

        public static void rels_typed (Xlsx x, string path, Gee.HashMap<string, string> targets, Gee.HashMap<string, string> types, Gee.HashMap<string, string> modes) {
            string dir = Path.get_dirname (path);
            string rel = (dir == "." ? "" : dir + "/") + "_rels/" + Path.get_basename (path) + ".rels";
            string? text = null;
            try {
                text = x.zip.read_text (rel);
            } catch (Error e) {
                return;
            }
            var doc = Xlsx.parse (text);
            if (doc == null) return;
            foreach (Xml.Node* c in Xlsx.list (doc->get_root_element ())) {
                string id = Xlsx.attr (c, "Id");
                string mode = Xlsx.attr (c, "TargetMode");
                string target = Xlsx.attr (c, "Target");
                targets[id] = mode == "External" ? target : Xlsx.resolve (dir == "." ? "" : dir, target);
                types[id] = Xlsx.attr (c, "Type");
                modes[id] = mode;
            }
            delete doc;
        }

        public static XlsxSheetIn sheet_in (Xlsx x, Sheet sh, int index, string path, Xml.Node* root) {
            var sin = new XlsxSheetIn ();
            sin.reader = x;
            sin.sheet = sh;
            sin.index = index;
            sin.path = path;
            sin.root = root;
            rels_typed (x, path, sin.targets, sin.types, sin.modes);
            return sin;
        }

        public static void read_workbook (Xlsx x, Gee.HashMap<string, string> wb_rels) {
            AnalysisStore.read_xlsx (x, wb_rels);
            RevisionsIo.read_xlsx (x);
            try {
                if (x.zip.has ("xl/vbaProject.bin")) {
                    var data = x.zip.read ("xl/vbaProject.bin");
                    if (data != null) x.book.vba_project = new Bytes (data);
                }
                read_core (x);
            } catch (Error e) {
            }
        }

        private static void read_core (Xlsx x) throws Error {
            var doc = Xlsx.parse (x.zip.read_text ("docProps/core.xml"));
            if (doc != null) {
                foreach (Xml.Node* n in Xlsx.list (doc->get_root_element ())) {
                    string v = Xlsx.text_of (n).strip ();
                    if (v == "") continue;
                    switch (n->name) {
                        case "title": case "subject": case "creator": case "keywords": case "description": case "category": case "created":
                            x.book.properties[n->name] = v;
                            break;
                    }
                }
                delete doc;
            }
            var app = Xlsx.parse (x.zip.read_text ("docProps/app.xml"));
            if (app != null) {
                foreach (Xml.Node* n in Xlsx.list (app->get_root_element ())) {
                    string v = Xlsx.text_of (n).strip ();
                    if (v == "") continue;
                    if (n->name == "Company") x.book.properties["company"] = v;
                    else if (n->name == "Manager") x.book.properties["manager"] = v;
                }
                delete app;
            }
        }

        public static void read_sheet (XlsxSheetIn sin) {
            try {
                read_links (sin);
                read_notes (sin);
                CommentsIo.read_sheet (sin);
                XlsxDrawing.read_sheet (sin);
            } catch (Error e) {
            }
        }

        private static void read_links (XlsxSheetIn sin) {
            var hl = Xlsx.child (sin.root, "hyperlinks");
            if (hl == null) return;
            foreach (Xml.Node* h in Xlsx.list (hl)) {
                var area = Area.parse (Xlsx.attr (h, "ref"), sin.sheet);
                if (area == null) continue;
                string rid = h->get_ns_prop ("id", NS_REL) ?? "";
                string link = "";
                if (rid != "" && sin.targets.has_key (rid)) {
                    link = sin.targets[rid];
                    string loc = Xlsx.attr (h, "location");
                    if (loc != "") link += "#" + loc;
                } else if (Xlsx.attr (h, "location") != "") {
                    link = "#" + Xlsx.attr (h, "location");
                }
                if (link == "") continue;
                for (int r = area.r1; r <= area.r2 && r - area.r1 < 1000; r++) {
                    for (int c = area.c1; c <= area.c2 && c - area.c1 < 100; c++) sin.sheet.ensure (r, c).link = link;
                }
            }
        }

        private static void read_notes (XlsxSheetIn sin) throws Error {
            string? target = sin.target_of_type ("/comments");
            if (target == null) return;
            var doc = Xlsx.parse (sin.reader.zip.read_text (target));
            if (doc == null) return;
            var root = doc->get_root_element ();
            var authors = new Gee.ArrayList<string> ();
            foreach (Xml.Node* a in Xlsx.list (Xlsx.child (root, "authors"))) authors.add (Xlsx.text_of (a));
            foreach (Xml.Node* c in Xlsx.list (Xlsx.child (root, "commentList"))) {
                int r, col;
                bool a1, a2;
                if (!Address.parse_cell (Xlsx.attr (c, "ref"), out r, out col, out a1, out a2)) continue;
                var t = Xlsx.child (c, "text");
                string text = t != null ? Xlsx.rich_text (t) : "";
                int ai = int.parse (Xlsx.attr (c, "authorId", "0"));
                string author = ai >= 0 && ai < authors.size ? authors[ai] : "";
                if (author != "" && text.has_prefix (author + ":")) {
                    text = text.substring (author.length + 1);
                    if (text.has_prefix ("\n")) text = text.substring (1);
                }
                if (author.has_prefix ("tc=")) author = "";
                var cell = sin.sheet.ensure (r, col);
                cell.note = text.strip ();
                cell.note_author = author;
            }
            delete doc;
        }
    }
}
