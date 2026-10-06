namespace Singularity.Apps.Spreadsheet {

    public class XlsxSheetPart {
        public const string[] ORDER = {
            "sheetCalcPr", "sheetProtection", "protectedRanges", "scenarios", "autoFilter", "sortState",
            "dataConsolidate", "customSheetViews", "mergeCells", "phoneticPr", "conditionalFormatting",
            "dataValidations", "hyperlinks", "printOptions", "pageMargins", "pageSetup", "headerFooter",
            "rowBreaks", "colBreaks", "customProperties", "cellWatches", "ignoredErrors", "smartTags",
            "drawing", "legacyDrawing", "legacyDrawingHF", "picture", "oleObjects", "controls",
            "webPublishItems", "tableParts", "extLst"
        };

        public XlsxWriter writer;
        public Sheet sheet;
        public int index;
        public Gee.HashMap<string, string> slots = new Gee.HashMap<string, string> ();
        public StringBuilder rels = new StringBuilder ();
        public StringBuilder sheet_pr = new StringBuilder ();
        public StringBuilder sheet_pr_attrs = new StringBuilder ();
        public StringBuilder format_pr_attrs = new StringBuilder ();
        public StringBuilder view_attrs = new StringBuilder ();
        public Gee.HashMap<int, string> row_attrs = new Gee.HashMap<int, string> ();
        public Gee.HashMap<int, string> col_attrs = new Gee.HashMap<int, string> ();
        private int next_rel = 1;

        public XlsxSheetPart (XlsxWriter writer, Sheet sheet, int index) {
            this.writer = writer;
            this.sheet = sheet;
            this.index = index;
        }

        public void put (string slot, string xml) {
            slots[slot] = (slots.has_key (slot) ? slots[slot] : "") + xml;
        }

        public bool has (string slot) {
            return slots.has_key (slot) && slots[slot] != "";
        }

        public string add_rel (string type, string target, bool external = false) {
            string id = "rId%d".printf (next_rel++);
            rels.append ("<Relationship Id=\"%s\" Type=\"%s\" Target=\"%s\"%s/>".printf (id, type, XlsxWriter.esc (target), external ? " TargetMode=\"External\"" : ""));
            return id;
        }

        public string tail () {
            var sb = new StringBuilder ();
            foreach (string slot in ORDER) {
                if (!has (slot)) continue;
                if (slot == "extLst" && !slots[slot].has_prefix ("<extLst")) sb.append ("<extLst>" + slots[slot] + "</extLst>");
                else sb.append (slots[slot]);
            }
            return sb.str;
        }

        public string? rels_xml () {
            if (rels.len == 0) return null;
            return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + rels.str + "</Relationships>";
        }
    }

    public class XlsxSheetIn {
        public Xlsx reader;
        public Sheet sheet;
        public int index;
        public string path;
        public Xml.Node* root;
        public Gee.HashMap<string, string> targets = new Gee.HashMap<string, string> ();
        public Gee.HashMap<string, string> types = new Gee.HashMap<string, string> ();
        public Gee.HashMap<string, string> modes = new Gee.HashMap<string, string> ();

        public string? target_of_type (string type_suffix) {
            foreach (var e in types.entries) {
                if (e.value.has_suffix (type_suffix)) return targets[e.key];
            }
            return null;
        }
    }
}
