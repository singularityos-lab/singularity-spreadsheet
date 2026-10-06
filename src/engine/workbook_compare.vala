namespace Singularity.Apps.Spreadsheet {

    public enum DiffKind {
        VALUE,
        FORMULA,
        FORMAT,
        SHEET_ADDED,
        SHEET_REMOVED
    }

    public class WorkbookDiff {
        public DiffKind kind;
        public string sheet_name;
        public int row;
        public int col;
        public string mine = "";
        public string theirs = "";
        public CellStyle? theirs_style;
        public Sheet? source;
        public bool selected = true;

        public WorkbookDiff (DiffKind kind, string sheet_name) {
            this.kind = kind;
            this.sheet_name = sheet_name;
        }

        public string where () {
            if (kind == DiffKind.SHEET_ADDED || kind == DiffKind.SHEET_REMOVED) return Address.quote_sheet (sheet_name);
            return Address.quote_sheet (sheet_name) + "!" + Address.cell (row, col);
        }

        public string describe () {
            switch (kind) {
                case DiffKind.VALUE: return _("Value %s in this workbook, %s in the other").printf (Change.shown (mine), Change.shown (theirs));
                case DiffKind.FORMULA: return _("Formula %s in this workbook, %s in the other").printf (Change.shown (mine), Change.shown (theirs));
                case DiffKind.FORMAT: return _("Formatting differs");
                case DiffKind.SHEET_ADDED: return _("Sheet only in the other workbook");
                default: return _("Sheet only in this workbook");
            }
        }
    }

    public class WorkbookCompare {
        private static string style_key (Workbook b, Cell? c) {
            return b.styles[c != null ? c.style : 0].key ();
        }

        public static Gee.ArrayList<WorkbookDiff> compare (Workbook mine, Workbook other) {
            var list = new Gee.ArrayList<WorkbookDiff> ();
            foreach (var os in other.sheets) {
                var ms = mine.find_sheet (os.name);
                if (ms == null) {
                    var d = new WorkbookDiff (DiffKind.SHEET_ADDED, os.name);
                    d.source = os;
                    list.add (d);
                    continue;
                }
                var keys = new Gee.TreeSet<int64?> ((x, y) => {
                    int64 p = x;
                    int64 q = y;
                    return p < q ? -1 : (p > q ? 1 : 0);
                });
                foreach (var k in ms.cells.keys) keys.add (k);
                foreach (var k in os.cells.keys) keys.add (k);
                foreach (var k in keys) {
                    int r = Sheet.key_row (k), c = Sheet.key_col (k);
                    var mc = ms.get_cell (r, c);
                    var oc = os.get_cell (r, c);
                    string mi = mc != null ? mc.input : "";
                    string oi = oc != null ? oc.input : "";
                    WorkbookDiff? d = null;
                    if (mi != oi) {
                        d = new WorkbookDiff (mi.has_prefix ("=") || oi.has_prefix ("=") ? DiffKind.FORMULA : DiffKind.VALUE, ms.name);
                        d.mine = mi;
                        d.theirs = oi;
                    } else if (style_key (mine, mc) != style_key (other, oc)) {
                        d = new WorkbookDiff (DiffKind.FORMAT, ms.name);
                        d.mine = mi;
                        d.theirs = oi;
                        d.theirs_style = other.styles[oc != null ? oc.style : 0].copy ();
                    }
                    if (d == null) continue;
                    d.row = r;
                    d.col = c;
                    list.add (d);
                }
            }
            foreach (var ms in mine.sheets) {
                if (other.find_sheet (ms.name) == null) list.add (new WorkbookDiff (DiffKind.SHEET_REMOVED, ms.name));
            }
            return list;
        }

        public static string author_of (Workbook other, string path) {
            if (other.properties.has_key ("creator") && other.properties["creator"] != "") return other.properties["creator"];
            return Path.get_basename (path);
        }

        public static int merge (Document doc, Gee.List<WorkbookDiff> diffs, string author) {
            var tracker = ReviewTracker.of (doc);
            tracker.set_tracking (true);
            tracker.author_override = author;
            int n = 0;
            foreach (var d in diffs) {
                if (!d.selected) continue;
                switch (d.kind) {
                    case DiffKind.VALUE:
                    case DiffKind.FORMULA:
                        var s = doc.book.find_sheet (d.sheet_name);
                        if (s == null) continue;
                        doc.set_input (s, d.row, d.col, d.theirs);
                        break;
                    case DiffKind.FORMAT:
                        var fs = doc.book.find_sheet (d.sheet_name);
                        if (fs == null || d.theirs_style == null) continue;
                        doc.begin_area (_("Merge Formatting"), fs, new Area.cell (fs, d.row, d.col));
                        fs.set_style (d.row, d.col, doc.book.intern (d.theirs_style.copy ()));
                        doc.commit ();
                        break;
                    case DiffKind.SHEET_ADDED:
                        if (d.source == null || doc.book.find_sheet (d.sheet_name) != null) continue;
                        var ns = doc.add_sheet ();
                        doc.rename_sheet (ns, d.sheet_name);
                        var src = d.source;
                        doc.begin_area (_("Merge Sheet"), ns, new Area (ns, 0, 0, int.max (src.max_row, 0), int.max (src.max_col, 0)));
                        foreach (var cell in src.cells.values) {
                            if (cell.input != "") ns.set_input (cell.row, cell.col, cell.input);
                            if (cell.style != 0) ns.set_style (cell.row, cell.col, doc.book.intern (src.book.styles[cell.style].copy ()));
                        }
                        doc.commit ();
                        break;
                    case DiffKind.SHEET_REMOVED:
                        var rs = doc.book.find_sheet (d.sheet_name);
                        if (rs == null || doc.book.sheets.size <= 1) continue;
                        doc.remove_sheet (rs);
                        break;
                }
                n++;
            }
            tracker.author_override = null;
            return n;
        }
    }
}
