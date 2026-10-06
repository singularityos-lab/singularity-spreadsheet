namespace Singularity.Apps.Spreadsheet {

    public class CommentsIo {
        public const string NS_TC = "http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments";
        public const string NS_SS = "urn:singularity:spreadsheet:comments:1";
        private const string REL_TC = "http://schemas.microsoft.com/office/2017/10/relationships/threadedComment";
        private const string REL_PERSON = "http://schemas.microsoft.com/office/2017/10/relationships/person";
        private const string TYPE_TC = "application/vnd.ms-excel.threadedcomments+xml";
        private const string TYPE_PERSON = "application/vnd.ms-excel.person+xml";
        public const string LEGACY_PREFIX = "[Threaded comment]";

        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        public static string person_id (string name) {
            string h = Checksum.compute_for_string (ChecksumType.MD5, name).up ();
            return "{%s-%s-%s-%s-%s}".printf (h.substring (0, 8), h.substring (8, 4), h.substring (12, 4), h.substring (16, 4), h.substring (20, 12));
        }

        private static string excel_date (string iso) {
            string d = iso;
            int plus = d.index_of_char ('+', 10);
            if (plus > 0) d = d.substring (0, plus);
            if (d.has_suffix ("Z")) d = d.substring (0, d.length - 1);
            if (d.length == 19) d += ".00";
            return d;
        }

        public static string legacy_text (CommentThread t) {
            var sb = new StringBuilder (LEGACY_PREFIX);
            sb.append ("\n\nYour version of Excel allows you to read this threaded comment; however, any edits to it will get removed if the file is opened in a newer version of Excel. Learn more: https://go.microsoft.com/fwlink/?linkid=870924\n\n");
            for (int i = 0; i < t.posts.size; i++) {
                if (i > 0) sb.append ("\n");
                sb.append (i == 0 ? "Comment:\n    " : "Reply:\n    ");
                sb.append (t.posts[i].text);
            }
            return sb.str;
        }

        public static void add_legacy (Sheet s, Gee.ArrayList<Cell> list) {
            if (s.comments.size == 0) return;
            foreach (var t in s.comments.sorted ()) {
                if (t.posts.size == 0) continue;
                var existing = s.get_cell (t.row, t.col);
                if (existing != null && existing.note != "") continue;
                var c = new Cell ();
                c.row = t.row;
                c.col = t.col;
                c.note = legacy_text (t);
                c.note_author = "tc=" + t.id;
                list.add (c);
            }
            list.sort ((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
        }

        public static void write_workbook (XlsxWriter w) {
            var names = new Gee.TreeSet<string> ();
            foreach (var s in w.book.sheets) {
                foreach (var t in s.comments.threads.values) foreach (var p in t.posts) names.add (p.author);
            }
            if (names.size == 0) return;
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<personList xmlns=\"%s\" xmlns:x=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">".printf (NS_TC));
            foreach (string n in names) {
                sb.append ("<person displayName=\"%s\" id=\"%s\" userId=\"%s\" providerId=\"None\"/>".printf (esc (n), person_id (n), esc (n)));
            }
            sb.append ("</personList>");
            w.add_text_part ("xl/persons/person.xml", sb.str, TYPE_PERSON);
            w.add_workbook_rel (REL_PERSON, "persons/person.xml");
        }

        public static void write_sheet (XlsxSheetPart part) {
            var list = part.sheet.comments.sorted ();
            if (list.size == 0) return;
            int n = part.writer.next_number ();
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<ThreadedComments xmlns=\"%s\" xmlns:x=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">".printf (NS_TC));
            foreach (var t in list) {
                string addr = Address.cell (t.row, t.col);
                for (int i = 0; i < t.posts.size; i++) {
                    var p = t.posts[i];
                    sb.append ("<threadedComment ref=\"%s\" dT=\"%s\" personId=\"%s\" id=\"%s\"".printf (addr, esc (excel_date (p.date)), person_id (p.author), esc (p.id)));
                    if (i > 0) sb.append (" parentId=\"%s\"".printf (esc (t.id)));
                    else if (t.resolved) sb.append (" done=\"1\"");
                    sb.append ("><text>%s</text></threadedComment>".printf (esc (p.text)));
                }
            }
            sb.append ("</ThreadedComments>");
            string name = "threadedComment%d.xml".printf (n);
            part.writer.add_text_part ("xl/threadedComments/" + name, sb.str, TYPE_TC);
            part.add_rel (REL_TC, "../threadedComments/" + name);
        }

        private static Gee.HashMap<string, string> persons (Xlsx x) {
            var map = new Gee.HashMap<string, string> ();
            var targets = new Gee.HashMap<string, string> ();
            var types = new Gee.HashMap<string, string> ();
            var modes = new Gee.HashMap<string, string> ();
            XlsxExtras.rels_typed (x, "xl/workbook.xml", targets, types, modes);
            string? path = null;
            foreach (var e in types.entries) if (e.value.has_suffix ("/person")) path = targets[e.key];
            if (path == null) return map;
            try {
                var doc = Xlsx.parse (x.zip.read_text (path));
                if (doc == null) return map;
                foreach (Xml.Node* p in Xlsx.list (doc->get_root_element ())) {
                    if (p->name != "person") continue;
                    map[Xlsx.attr (p, "id")] = Xlsx.attr (p, "displayName");
                }
                delete doc;
            } catch (Error e) {
            }
            return map;
        }

        public static void read_sheet (XlsxSheetIn sin) {
            string? target = sin.target_of_type ("/threadedComment");
            if (target == null) return;
            Xml.Doc* doc = null;
            try {
                doc = Xlsx.parse (sin.reader.zip.read_text (target));
            } catch (Error e) {
                return;
            }
            if (doc == null) return;
            var people = persons (sin.reader);
            var by_id = new Gee.HashMap<string, CommentThread> ();
            foreach (Xml.Node* n in Xlsx.list (doc->get_root_element ())) {
                if (n->name != "threadedComment") continue;
                int r, c;
                bool a1, a2;
                if (!Address.parse_cell (Xlsx.attr (n, "ref"), out r, out c, out a1, out a2)) continue;
                string pid = Xlsx.attr (n, "personId");
                string author = people.has_key (pid) ? people[pid] : "";
                string id = Xlsx.attr (n, "id");
                if (id == "") id = CommentStore.new_id ();
                string date = Xlsx.attr (n, "dT");
                if (date.length > 19) date = date.substring (0, 19);
                if (date == "") date = CommentStore.now_iso ();
                var post = new CommentPost (author, Xlsx.text_of (Xlsx.child (n, "text")), id, date);
                string parent = Xlsx.attr (n, "parentId");
                CommentThread? t = parent != "" && by_id.has_key (parent) ? by_id[parent] : null;
                if (t == null) t = sin.sheet.comments.at (r, c);
                if (t == null) {
                    t = new CommentThread (r, c);
                    sin.sheet.comments.put (t);
                }
                if (parent == "") {
                    by_id[id] = t;
                    string done = Xlsx.attr (n, "done");
                    t.resolved = done == "1" || done == "true";
                }
                t.posts.add (post);
            }
            delete doc;
            foreach (var t in sin.sheet.comments.threads.values) {
                var cell = sin.sheet.get_cell (t.row, t.col);
                if (cell != null && cell.note.has_prefix (LEGACY_PREFIX)) {
                    cell.note = "";
                    cell.note_author = "";
                    sin.sheet.drop_if_blank (t.row, t.col);
                }
            }
        }

        private static string para (string text) {
            var sb = new StringBuilder ();
            foreach (string line in text.split ("\n")) sb.append ("<text:p>%s</text:p>".printf (esc (line)));
            return sb.str;
        }

        public static string thread_xml (CommentThread t) {
            var sb = new StringBuilder ("<ss:thread xmlns:ss=\"%s\" ss:resolved=\"%s\">".printf (NS_SS, t.resolved ? "true" : "false"));
            foreach (var p in t.posts) {
                sb.append ("<ss:post ss:id=\"%s\" ss:author=\"%s\" ss:date=\"%s\">%s</ss:post>".printf (esc (p.id), esc (p.author), esc (p.date), esc (p.text)));
            }
            sb.append ("</ss:thread>");
            return sb.str;
        }

        public static void write_ods (OdsOut o) {
            foreach (var s in o.book.sheets) {
                foreach (var t in s.comments.sorted ()) {
                    if (t.posts.size == 0) continue;
                    var cell = s.ensure (t.row, t.col);
                    if (cell.note != "") {
                        o.put_cell_child (s, t.row, t.col, thread_xml (t));
                        continue;
                    }
                    var sb = new StringBuilder ("<office:annotation office:display=\"false\">");
                    sb.append ("<dc:creator>%s</dc:creator><dc:date>%s</dc:date>".printf (esc (t.posts[0].author), esc (t.posts[0].date)));
                    foreach (var p in t.posts) sb.append (para (p.author + ": " + p.text));
                    if (t.resolved) sb.append (para ("(" + _("Resolved") + ")"));
                    sb.append (thread_xml (t));
                    sb.append ("</office:annotation>");
                    o.put_cell_child (s, t.row, t.col, sb.str);
                }
            }
        }

        private static Xml.Node* find_thread (Xml.Node* parent) {
            for (Xml.Node* n = parent->children; n != null; n = n->next) {
                if (n->type == Xml.ElementType.ELEMENT_NODE && n->name == "thread" && n->ns != null && n->ns->href == NS_SS) return n;
            }
            return null;
        }

        public static void read_ods_cell (Sheet sheet, Xml.Node* cell, int row, int col) {
            Xml.Node* th = find_thread (cell);
            bool in_annotation = false;
            if (th == null) {
                for (Xml.Node* n = cell->children; n != null && th == null; n = n->next) {
                    if (n->type == Xml.ElementType.ELEMENT_NODE && n->name == "annotation") {
                        th = find_thread (n);
                        in_annotation = th != null;
                    }
                }
            }
            if (th == null) return;
            var t = new CommentThread (row, col);
            t.resolved = Xlsx.attr (th, "resolved") == "true";
            for (Xml.Node* p = th->children; p != null; p = p->next) {
                if (p->type != Xml.ElementType.ELEMENT_NODE || p->name != "post") continue;
                t.posts.add (new CommentPost (Xlsx.attr (p, "author"), Xlsx.text_of (p), Xlsx.attr (p, "id"), Xlsx.attr (p, "date")));
            }
            if (t.posts.size == 0) return;
            sheet.comments.put (t);
            if (in_annotation) {
                var c = sheet.get_cell (row, col);
                if (c != null) {
                    c.note = "";
                    c.note_author = "";
                    sheet.drop_if_blank (row, col);
                }
            }
        }
    }
}
