namespace Singularity.Apps.Spreadsheet {

    public class RevisionsIo {
        public const string NS_REV = "urn:dev.sinty.spreadsheet:revisions";
        private const string REL_CUSTOM = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml";
        private const string REL_PROPS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXmlProps";
        private const string TYPE_PROPS = "application/vnd.openxmlformats-officedocument.customXmlProperties+xml";

        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        private static bool empty (Workbook book) {
            return !book.revisions.tracking && book.revisions.changes.size == 0;
        }

        private static string state_code (ChangeState s) {
            switch (s) {
                case ChangeState.ACCEPTED: return "accepted";
                case ChangeState.REJECTED: return "rejected";
                default: return "pending";
            }
        }

        private static ChangeState state_of (string s) {
            switch (s) {
                case "accepted": return ChangeState.ACCEPTED;
                case "rejected": return ChangeState.REJECTED;
                default: return ChangeState.PENDING;
            }
        }

        private static string sheet_of (Change c) {
            return c.sheet != null ? c.sheet.name : c.sheet_name;
        }

        public static string serialize (Workbook book) {
            var log = book.revisions;
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
            sb.append ("<singularityRevisions xmlns=\"%s\" tracking=\"%s\" nextId=\"%d\">".printf (NS_REV, log.tracking ? "1" : "0", log.next_id));
            foreach (var c in log.changes) {
                sb.append ("<change id=\"%d\" kind=\"%s\" state=\"%s\" sheet=\"%s\" row=\"%d\" col=\"%d\" count=\"%d\" author=\"%s\" date=\"%s\" old=\"%s\" new=\"%s\"".printf (
                    c.id, c.kind.to_code (), state_code (c.state), esc (sheet_of (c)), c.row, c.col, c.count, esc (c.author), esc (c.date), esc (c.old_input), esc (c.new_input)));
                if (c.removed.size == 0) {
                    sb.append ("/>");
                    continue;
                }
                sb.append (">");
                foreach (var sc in c.removed) sb.append ("<cell row=\"%d\" col=\"%d\" input=\"%s\"/>".printf (sc.row, sc.col, esc (sc.input)));
                sb.append ("</change>");
            }
            sb.append ("</singularityRevisions>");
            return sb.str;
        }

        private static int iattr (Xml.Node* n, string name) {
            return int.parse (Xlsx.attr (n, name, "0"));
        }

        public static void deserialize (Workbook book, Xml.Node* root) {
            var log = book.revisions;
            log.changes.clear ();
            log.tracking = Xlsx.attr (root, "tracking") == "1";
            foreach (Xml.Node* n in Xlsx.list (root)) {
                if (n->name != "change") continue;
                var c = new Change (ChangeKind.from_code (Xlsx.attr (n, "kind")));
                c.id = iattr (n, "id");
                c.state = state_of (Xlsx.attr (n, "state"));
                c.sheet_name = Xlsx.attr (n, "sheet");
                c.sheet = book.find_sheet (c.sheet_name);
                c.row = iattr (n, "row");
                c.col = iattr (n, "col");
                c.count = int.max (1, iattr (n, "count"));
                c.author = Xlsx.attr (n, "author");
                c.date = Xlsx.attr (n, "date");
                c.old_input = Xlsx.attr (n, "old");
                c.new_input = Xlsx.attr (n, "new");
                foreach (Xml.Node* sc in Xlsx.list (n)) {
                    if (sc->name == "cell") c.removed.add (new SavedCell (iattr (sc, "row"), iattr (sc, "col"), Xlsx.attr (sc, "input"), 0));
                }
                log.changes.add (c);
            }
            int next = int.parse (Xlsx.attr (root, "nextId", "1"));
            foreach (var c in log.changes) next = int.max (next, c.id + 1);
            log.next_id = next;
        }

        public static void write_xlsx (XlsxWriter w) {
            if (empty (w.book)) return;
            int n = w.next_number ();
            string item = "customXml/item%d.xml".printf (n);
            string props = "customXml/itemProps%d.xml".printf (n);
            w.add_text_part (item, serialize (w.book), null);
            w.add_text_part (props, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>\n<ds:datastoreItem ds:itemID=\"%s\" xmlns:ds=\"http://schemas.openxmlformats.org/officeDocument/2006/customXml\"><ds:schemaRefs><ds:schemaRef ds:uri=\"%s\"/></ds:schemaRefs></ds:datastoreItem>".printf (CommentStore.new_id (), NS_REV), TYPE_PROPS);
            w.add_text_part ("customXml/_rels/item%d.xml.rels".printf (n), "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"%s\" Target=\"itemProps%d.xml\"/></Relationships>".printf (REL_PROPS, n), null);
            w.add_workbook_rel (REL_CUSTOM, "../" + item);
        }

        public static void read_xlsx (Xlsx x) {
            foreach (string name in x.zip.names ()) {
                if (!name.has_prefix ("customXml/item") || name.has_prefix ("customXml/itemProps") || !name.has_suffix (".xml")) continue;
                try {
                    var doc = Xlsx.parse (x.zip.read_text (name));
                    if (doc == null) continue;
                    var root = doc->get_root_element ();
                    if (root != null && root->name == "singularityRevisions" && root->ns != null && root->ns->href == NS_REV) deserialize (x.book, root);
                    delete doc;
                } catch (Error e) {
                }
            }
        }

        private static string previous_cell (Workbook book, Change c) {
            string v = c.old_input;
            if (v.has_prefix ("=") && c.sheet != null) {
                try {
                    var node = Formula.parse (v, book, c.sheet);
                    return "<table:change-track-table-cell table:formula=\"%s\"/>".printf (esc (Ods.to_of (node, c.sheet)));
                } catch (FormulaError e) {
                }
            }
            if (v == "") return "<table:change-track-table-cell/>";
            double d;
            string f;
            if (Input.parse_number (v, out d, out f) && f == "") return "<table:change-track-table-cell office:value-type=\"float\" office:value=\"%s\"><text:p>%s</text:p></table:change-track-table-cell>".printf (Value.format_number_general_full (d), esc (v));
            return "<table:change-track-table-cell office:value-type=\"string\"><text:p>%s</text:p></table:change-track-table-cell>".printf (esc (v.has_prefix ("'") ? v.substring (1) : v));
        }

        private static string info (Change c) {
            return "<office:change-info><dc:creator>%s</dc:creator><dc:date>%s</dc:date></office:change-info>".printf (esc (c.author), esc (c.date));
        }

        private static string ours (Change c) {
            return " xmlns:ss=\"%s\" ss:kind=\"%s\" ss:sheet=\"%s\" ss:old=\"%s\" ss:new=\"%s\"".printf (NS_REV, c.kind.to_code (), esc (sheet_of (c)), esc (c.old_input), esc (c.new_input));
        }

        public static void write_ods (OdsOut o) {
            var book = o.book;
            if (empty (book)) return;
            var sb = new StringBuilder ("<table:tracked-changes table:track-changes=\"%s\">".printf (book.revisions.tracking ? "true" : "false"));
            foreach (var c in book.revisions.changes) {
                int t = c.sheet != null ? book.sheets.index_of (c.sheet) : -1;
                string id = "ct%d".printf (c.id);
                string st = state_code (c.state);
                switch (c.kind) {
                    case ChangeKind.CELL:
                        if (t < 0) continue;
                        sb.append ("<table:cell-content-change table:id=\"%s\" table:acceptance-state=\"%s\"%s>".printf (id, st, ours (c)));
                        sb.append ("<table:cell-address table:column=\"%d\" table:row=\"%d\" table:table=\"%d\"/>".printf (c.col, c.row, t));
                        sb.append (info (c));
                        sb.append ("<table:previous>%s</table:previous></table:cell-content-change>".printf (previous_cell (book, c)));
                        break;
                    case ChangeKind.INSERT_ROWS:
                    case ChangeKind.INSERT_COLS:
                    case ChangeKind.INSERT_SHEET:
                        string type = c.kind == ChangeKind.INSERT_ROWS ? "row" : (c.kind == ChangeKind.INSERT_COLS ? "column" : "table");
                        int pos = c.kind == ChangeKind.INSERT_ROWS ? c.row : (c.kind == ChangeKind.INSERT_COLS ? c.col : t);
                        sb.append ("<table:insertion table:id=\"%s\" table:acceptance-state=\"%s\" table:type=\"%s\" table:position=\"%d\"%s%s%s>%s</table:insertion>".printf (
                            id, st, type, int.max (pos, 0), c.count > 1 ? " table:count=\"%d\"".printf (c.count) : "", c.kind != ChangeKind.INSERT_SHEET ? " table:table=\"%d\"".printf (int.max (t, 0)) : "", ours (c), info (c)));
                        break;
                    case ChangeKind.DELETE_ROWS:
                    case ChangeKind.DELETE_COLS:
                        if (t < 0) continue;
                        string dtype = c.kind == ChangeKind.DELETE_ROWS ? "row" : "column";
                        int dpos = c.kind == ChangeKind.DELETE_ROWS ? c.row : c.col;
                        var removed = new StringBuilder ();
                        foreach (var sc in c.removed) removed.append ("<ss:cell ss:row=\"%d\" ss:col=\"%d\" ss:input=\"%s\"/>".printf (sc.row, sc.col, esc (sc.input)));
                        sb.append ("<table:deletion table:id=\"%s\" table:acceptance-state=\"%s\" table:type=\"%s\" table:position=\"%d\" table:table=\"%d\" ss:count=\"%d\"%s>%s%s</table:deletion>".printf (
                            id, st, dtype, dpos, t, c.count, ours (c), info (c), removed.str));
                        break;
                    case ChangeKind.RENAME_SHEET:
                        sb.append ("<ss:rename table:id=\"%s\" table:acceptance-state=\"%s\"%s>%s</ss:rename>".printf (id, st, ours (c), info (c)));
                        break;
                    default:
                        sb.append ("<table:deletion table:id=\"%s\" table:acceptance-state=\"%s\" table:type=\"table\" table:position=\"0\"%s>%s</table:deletion>".printf (id, st, ours (c), info (c)));
                        break;
                }
            }
            sb.append ("</table:tracked-changes>");
            o.before_tables.prepend (sb.str);
        }

        private static string rattr (Xml.Node* n, string name) {
            return Ods.attr (n, name, NS_REV);
        }

        private static string tattr (Xml.Node* n, string name) {
            return Ods.attr (n, name, Ods.NS_TABLE);
        }

        private static string cell_text (Xml.Node* cell) {
            if (cell == null) return "";
            string f = tattr (cell, "formula");
            if (f != "") return Ods.from_of (f);
            var sb = new StringBuilder ();
            for (Xml.Node* p = cell->children; p != null; p = p->next) {
                if (p->type != Xml.ElementType.ELEMENT_NODE || p->name != "p") continue;
                if (sb.len > 0) sb.append ("\n");
                sb.append (p->get_content () ?? "");
            }
            return sb.str;
        }

        public static void read_ods (OdsIn inp) {
            var body = Ods.child (inp.content, "body");
            var ss = Ods.child (body, "spreadsheet");
            var tc = Ods.child (ss, "tracked-changes");
            if (tc == null) return;
            var book = inp.book;
            var log = book.revisions;
            log.changes.clear ();
            log.tracking = tattr (tc, "track-changes") == "true";
            int next = 1;
            for (Xml.Node* n = tc->children; n != null; n = n->next) {
                if (n->type != Xml.ElementType.ELEMENT_NODE) continue;
                Change? c = null;
                string kind = rattr (n, "kind");
                string type = tattr (n, "type");
                if (n->name == "cell-content-change") {
                    c = new Change (ChangeKind.CELL);
                    var addr = Ods.child (n, "cell-address");
                    int t = int.parse (tattr (addr, "table"));
                    c.row = int.parse (tattr (addr, "row"));
                    c.col = int.parse (tattr (addr, "column"));
                    if (t >= 0 && t < book.sheets.size) c.sheet = book.sheets[t];
                    c.old_input = kind != "" ? rattr (n, "old") : cell_text (Ods.child (Ods.child (n, "previous"), "change-track-table-cell"));
                    c.new_input = kind != "" ? rattr (n, "new") : (c.sheet != null ? c.sheet.input_at (c.row, c.col) : "");
                } else if (n->name == "rename" && kind != "") {
                    c = new Change (ChangeKind.RENAME_SHEET);
                    c.old_input = rattr (n, "old");
                    c.new_input = rattr (n, "new");
                } else if (n->name == "insertion" || n->name == "deletion") {
                    bool ins = n->name == "insertion";
                    if (kind != "") c = new Change (ChangeKind.from_code (kind));
                    else if (type == "row") c = new Change (ins ? ChangeKind.INSERT_ROWS : ChangeKind.DELETE_ROWS);
                    else if (type == "column") c = new Change (ins ? ChangeKind.INSERT_COLS : ChangeKind.DELETE_COLS);
                    else c = new Change (ins ? ChangeKind.INSERT_SHEET : ChangeKind.DELETE_SHEET);
                    int pos = int.parse (tattr (n, "position"));
                    string tcount = tattr (n, "count");
                    string scount = rattr (n, "count");
                    c.count = int.max (1, int.parse (scount != "" ? scount : (tcount != "" ? tcount : "1")));
                    if (c.kind == ChangeKind.INSERT_ROWS || c.kind == ChangeKind.DELETE_ROWS) c.row = pos;
                    else if (c.kind == ChangeKind.INSERT_COLS || c.kind == ChangeKind.DELETE_COLS) c.col = pos;
                    string tt = tattr (n, "table");
                    if (tt != "" && int.parse (tt) < book.sheets.size) c.sheet = book.sheets[int.parse (tt)];
                    else if (c.kind == ChangeKind.INSERT_SHEET && pos >= 0 && pos < book.sheets.size) c.sheet = book.sheets[pos];
                    c.old_input = rattr (n, "old");
                    c.new_input = rattr (n, "new");
                    for (Xml.Node* sc = n->children; sc != null; sc = sc->next) {
                        if (sc->type == Xml.ElementType.ELEMENT_NODE && sc->name == "cell") c.removed.add (new SavedCell (int.parse (rattr (sc, "row")), int.parse (rattr (sc, "col")), rattr (sc, "input"), 0));
                    }
                }
                if (c == null) continue;
                string sname = rattr (n, "sheet");
                if (sname != "") {
                    c.sheet_name = sname;
                    var found = book.find_sheet (sname);
                    if (found != null) c.sheet = found;
                } else if (c.sheet != null) {
                    c.sheet_name = c.sheet.name;
                }
                if (kind == "delete-sheet") c.sheet = null;
                string id = tattr (n, "id");
                c.id = id.has_prefix ("ct") ? int.parse (id.substring (2)) : next;
                next = int.max (next, c.id + 1);
                c.state = state_of (tattr (n, "acceptance-state"));
                var inf = Ods.child (n, "change-info");
                if (inf != null) {
                    for (Xml.Node* k = inf->children; k != null; k = k->next) {
                        if (k->type != Xml.ElementType.ELEMENT_NODE) continue;
                        if (k->name == "creator") c.author = k->get_content () ?? "";
                        else if (k->name == "date") c.date = k->get_content () ?? "";
                    }
                }
                log.changes.add (c);
            }
            log.next_id = next;
        }
    }
}
