namespace Singularity.Apps.Spreadsheet {

    public class XlsxDynamic {
        private const string REL_TABLE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/table";
        private const string REL_META = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/sheetMetadata";
        private const string CT_TABLE = "application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml";
        private const string CT_META = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheetMetadata+xml";

        private const string[] XLFN = {
            "ACOT", "ACOTH", "AGGREGATE", "ARABIC", "ARRAYTOTEXT", "BASE", "BETA.DIST", "BETA.INV", "BINOM.DIST",
            "BINOM.DIST.RANGE", "BINOM.INV", "BITAND", "BITLSHIFT", "BITOR", "BITRSHIFT", "BITXOR", "BYCOL", "BYROW",
            "CEILING.MATH", "CEILING.PRECISE", "CHISQ.DIST", "CHISQ.DIST.RT", "CHISQ.INV", "CHISQ.INV.RT", "CHISQ.TEST",
            "CHOOSECOLS", "CHOOSEROWS", "COMBINA", "CONCAT", "CONFIDENCE.NORM", "CONFIDENCE.T", "COT", "COTH",
            "COVARIANCE.P", "COVARIANCE.S", "CSC", "CSCH", "DAYS", "DECIMAL", "DROP", "ENCODEURL", "ERF.PRECISE",
            "ERFC.PRECISE", "EXPAND", "EXPON.DIST", "F.DIST", "F.DIST.RT", "F.INV", "F.INV.RT", "F.TEST", "FILTERXML",
            "FLOOR.MATH", "FLOOR.PRECISE", "FORECAST.ETS", "FORECAST.ETS.CONFINT", "FORECAST.ETS.SEASONALITY",
            "FORECAST.ETS.STAT", "FORECAST.LINEAR", "FORMULATEXT", "GAMMA", "GAMMA.DIST", "GAMMA.INV", "GAMMALN.PRECISE",
            "GAUSS", "GROUPBY", "HSTACK", "HYPGEOM.DIST", "IFNA", "IFS", "IMAGE", "IMCOSH", "IMCOT", "IMCSC", "IMCSCH",
            "IMSEC", "IMSECH", "IMSINH", "IMTAN", "ISFORMULA", "ISOMITTED", "ISOWEEKNUM", "LAMBDA", "LET",
            "LOGNORM.DIST", "LOGNORM.INV", "MAKEARRAY", "MAP", "MAXIFS", "MINIFS", "MODE.MULT", "MODE.SNGL", "MUNIT",
            "NEGBINOM.DIST", "NETWORKDAYS.INTL", "NORM.DIST", "NORM.INV", "NORM.S.DIST", "NORM.S.INV", "NUMBERVALUE",
            "PDURATION", "PERCENTILE.EXC", "PERCENTILE.INC", "PERCENTOF", "PERCENTRANK.EXC", "PERCENTRANK.INC",
            "PERMUTATIONA", "PHI", "PIVOTBY", "POISSON.DIST", "QUARTILE.EXC", "QUARTILE.INC", "RANDARRAY", "RANK.AVG",
            "RANK.EQ", "REDUCE", "REGEXEXTRACT", "REGEXREPLACE", "REGEXTEST", "RRI", "SCAN", "SEC", "SECH", "SEQUENCE",
            "SHEET", "SHEETS", "SKEW.P", "SORTBY", "STDEV.P", "STDEV.S", "SWITCH", "T.DIST", "T.DIST.2T", "T.DIST.RT",
            "T.INV", "T.INV.2T", "T.TEST", "TAKE", "TEXTAFTER", "TEXTBEFORE", "TEXTJOIN", "TEXTSPLIT", "TOCOL", "TOROW",
            "TRIMRANGE", "UNICHAR", "UNICODE", "UNIQUE", "VALUETOTEXT", "VAR.P", "VAR.S", "VSTACK", "WEBSERVICE",
            "WEIBULL.DIST", "WRAPCOLS", "WRAPROWS", "XLOOKUP", "XMATCH", "XOR", "Z.TEST"
        };

        private static Gee.HashSet<string>? xlfn_set;

        private static bool is_xlfn (string name) {
            if (xlfn_set == null) {
                xlfn_set = new Gee.HashSet<string> ();
                foreach (string f in XLFN) xlfn_set.add (f);
            }
            return xlfn_set.contains (name);
        }

        public static string to_file (Node n, Sheet own, int row = -1, int col = -1) {
            var copy = n.copy ();
            var scope = new Gee.HashSet<string> ();
            var outer = transform (copy, own, row, col, scope);
            return Formula.render (outer, own, 0);
        }

        private static Node transform (Node n, Sheet own, int row, int col, Gee.HashSet<string> lambda_params) {
            switch (n.kind) {
                case NodeKind.UNARY:
                    if (n.op == "@") {
                        var call = new Node (NodeKind.CALL);
                        call.text = "_xlfn.SINGLE";
                        call.args = { transform (n.args[0], own, row, col, lambda_params) };
                        return call;
                    }
                    break;
                case NodeKind.REF:
                    if (n.spill) {
                        var r = n.copy ();
                        r.spill = false;
                        var call = new Node (NodeKind.CALL);
                        call.text = "_xlfn.ANCHORARRAY";
                        call.args = { r };
                        return call;
                    }
                    return n;
                case NodeKind.STRUCT:
                    var sr = n.sref.copy ();
                    if (sr.table == "") {
                        var t = Tables.at (own.book, own, row, col);
                        if (t != null) sr.table = t.name;
                    }
                    var fixed_node = new Node (NodeKind.NAME);
                    fixed_node.text = sr.to_file_string ();
                    return fixed_node;
                case NodeKind.NAME:
                    if (lambda_params.contains (n.text.casefold ())) {
                        var p = new Node (NodeKind.NAME);
                        p.text = "_xlpm." + n.text;
                        return p;
                    }
                    return n;
                case NodeKind.CALL:
                    var inner = new Gee.HashSet<string> ();
                    inner.add_all (lambda_params);
                    if (n.text == "LAMBDA") {
                        for (int i = 0; i < n.args.length - 1; i++) {
                            if (n.args[i].kind == NodeKind.NAME) inner.add (n.args[i].text.casefold ());
                            else if (n.args[i].kind == NodeKind.STRUCT && n.args[i].sref.table == "") inner.add (n.args[i].sref.col1.casefold ());
                        }
                    } else if (n.text == "LET") {
                        for (int i = 0; i + 1 < n.args.length; i += 2) {
                            if (n.args[i].kind == NodeKind.NAME) inner.add (n.args[i].text.casefold ());
                        }
                    }
                    Node[] args = {};
                    foreach (var a in n.args) {
                        if (n.text == "LAMBDA" && a.kind == NodeKind.STRUCT && a.sref.table == "" && a != n.args[n.args.length - 1]) {
                            var opt = new Node (NodeKind.NAME);
                            opt.text = "[_xlpm." + a.sref.col1 + "]";
                            args += opt;
                            continue;
                        }
                        args += transform (a, own, row, col, inner);
                    }
                    n.args = args;
                    if (n.text == "FILTER" || n.text == "SORT") n.text = "_xlfn._xlws." + n.text;
                    else if (is_xlfn (n.text)) n.text = "_xlfn." + n.text;
                    return n;
                default:
                    break;
            }
            Node[] rest = {};
            foreach (var a in n.args) rest += transform (a, own, row, col, lambda_params);
            n.args = rest;
            return n;
        }

        public static bool has_multi_ref (Node n) {
            if (n.kind == NodeKind.REF && (n.b != null || n.spill || n.is_3d ())) return true;
            if (n.kind == NodeKind.STRUCT || n.kind == NodeKind.NAME) return true;
            foreach (var a in n.args) if (has_multi_ref (a)) return true;
            return false;
        }

        public static bool is_dynamic_anchor (Sheet s, Cell c) {
            return c.formula != null && c.array_area == null && s.spills.has_key (Sheet.key (c.row, c.col));
        }

        public static string array_attrs (Sheet s, Cell c, out bool is_dyn) {
            is_dyn = false;
            if (c.formula == null) return "";
            if (c.array_area != null) return " t=\"array\" ref=\"%s\"".printf (c.array_area.to_string ());
            var area = s.spills[Sheet.key (c.row, c.col)];
            if (area == null) {
                if (c.legacy || !has_multi_ref (c.formula)) return "";
                area = new Area.cell (s, c.row, c.col);
            }
            is_dyn = true;
            return " t=\"array\" ref=\"%s\"".printf (area.to_string ());
        }

        public static void add_spilled_cells (Sheet s, Gee.TreeMap<int, Gee.TreeMap<int, Cell>> rows) {
            foreach (var e in s.spills.entries) {
                int64 k = e.key;
                var anchor = s.cells[k];
                if (anchor == null || anchor.spill_values == null) continue;
                var area = e.value;
                var m = anchor.spill_values;
                for (int r = area.r1; r <= area.r2; r++) {
                    for (int c = area.c1; c <= area.c2; c++) {
                        if (r == anchor.row && c == anchor.col) continue;
                        int i = r - anchor.row, j = c - anchor.col;
                        if (i >= m.length[0] || j >= m.length[1]) continue;
                        var existing = s.cells[Sheet.key (r, c)];
                        var ghost = new Cell ();
                        ghost.row = r;
                        ghost.col = c;
                        ghost.style = existing != null ? existing.style : 0;
                        ghost.value = m[i, j];
                        if (!rows.has_key (r)) rows[r] = new Gee.TreeMap<int, Cell> ();
                        rows[r][c] = ghost;
                    }
                }
            }
        }

        public static void read_calc (Workbook book, Xml.Node* calc) {
            if (calc == null) return;
            book.iterative = (xattr (calc, "iterate") ?? "0") == "1" || xattr (calc, "iterate") == "true";
            string? count = xattr (calc, "iterateCount");
            if (count != null) book.max_iterations = int.max (1, int.parse (count));
            string? delta = xattr (calc, "iterateDelta");
            if (delta != null && double.parse (delta) > 0) book.max_change = double.parse (delta);
            book.manual_calc = xattr (calc, "calcMode") == "manual";
        }

        public static void write_workbook (XlsxWriter w) {
            for (int i = 0; i < w.book.sheets.size; i++) {
                int vis = w.book.sheets[i].visibility;
                if (vis != 0) w.put_workbook ("sheet%d.attrs".printf (i), vis == 2 ? " state=\"veryHidden\"" : " state=\"hidden\"");
            }
            if (w.book.sheets.size > 0 && w.book.sheets[0].visibility != 0) {
                for (int i = 1; i < w.book.sheets.size; i++) {
                    if (w.book.sheets[i].visibility == 0) {
                        w.put_workbook ("workbookView.attrs", " activeTab=\"%d\" firstSheet=\"%d\"".printf (i, i));
                        break;
                    }
                }
            }
            var calc = new StringBuilder ();
            if (w.book.iterative) calc.append (" iterate=\"1\" iterateCount=\"%d\" iterateDelta=\"%s\"".printf (w.book.max_iterations, Value.format_number_general_full (w.book.max_change)));
            if (w.book.manual_calc) calc.append (" calcMode=\"manual\"");
            if (calc.len > 0) w.put_workbook ("calcPr.attrs", calc.str);
            bool any = false;
            foreach (var s in w.book.sheets) {
                foreach (var c in s.cells.values) {
                    if (c.formula == null || c.array_area != null) continue;
                    if (s.spills.has_key (Sheet.key (c.row, c.col)) || (!c.legacy && has_multi_ref (c.formula))) {
                        any = true;
                        break;
                    }
                }
                if (any) break;
            }
            if (!any) return;
            w.add_text_part ("xl/metadata.xml", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<metadata xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:xda="http://schemas.microsoft.com/office/spreadsheetml/2017/dynamicarray"><metadataTypes count="1"><metadataType name="XLDAPR" minSupportedVersion="120000" copy="1" pasteAll="1" pasteValues="1" merge="1" splitFirst="1" rowColShift="1" clearFormats="1" clearComments="1" assign="1" coerce="1" cellMeta="1"/></metadataTypes><futureMetadata name="XLDAPR" count="1"><bk><extLst><ext uri="{bdbb8cdc-fa1e-496e-a857-3c3f30c029c3}"><xda:dynamicArrayProperties fDynamic="1" fCollapsed="0"/></ext></extLst></bk></futureMetadata><cellMetadata count="1"><bk><rc t="1" v="0"/></bk></cellMetadata></metadata>""", CT_META);
            w.add_workbook_rel (REL_META, "metadata.xml");
        }

        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        private static string totals_code (string f) {
            switch (f.up ()) {
                case "SUM": return "sum";
                case "AVERAGE": return "average";
                case "COUNT": return "countNums";
                case "COUNTA": return "count";
                case "MAX": return "max";
                case "MIN": return "min";
                case "STDEV": return "stdDev";
                case "VAR": return "var";
                case "": return "";
                default: return "custom";
            }
        }

        public static string totals_name (string code) {
            switch (code) {
                case "sum": return "SUM";
                case "average": return "AVERAGE";
                case "countNums": return "COUNT";
                case "count": return "COUNTA";
                case "max": return "MAX";
                case "min": return "MIN";
                case "stdDev": return "STDEV";
                case "var": return "VAR";
                default: return "";
            }
        }

        public static int subtotal_code (string f) {
            switch (f.up ()) {
                case "AVERAGE": return 101;
                case "COUNT": return 102;
                case "COUNTA": return 103;
                case "MAX": return 104;
                case "MIN": return 105;
                case "STDEV": return 107;
                case "VAR": return 110;
                default: return 109;
            }
        }

        public static void write_sheet (XlsxSheetPart part) {
            var book = part.sheet.book;
            var parts_xml = new StringBuilder ();
            int count = 0;
            foreach (var t in book.tables) {
                if (t.sheet != part.sheet) continue;
                int id = book.tables.index_of (t) + 1;
                int n = part.writer.next_number ();
                var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
                sb.append ("<table xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" id=\"%d\" name=\"%s\" displayName=\"%s\" ref=\"%s\"".printf (id, esc (t.name), esc (t.name), t.area.to_string ()));
                if (!t.header_row) sb.append (" headerRowCount=\"0\"");
                if (t.totals_row) sb.append (" totalsRowCount=\"1\"");
                else sb.append (" totalsRowShown=\"0\"");
                sb.append (">");
                if (t.header_row && t.filter_button) {
                    var fa = new Area (t.sheet, t.area.r1, t.area.c1, t.data_r2, t.area.c2);
                    sb.append ("<autoFilter ref=\"%s\"/>".printf (fa.to_string ()));
                }
                sb.append ("<tableColumns count=\"%d\">".printf (t.columns.size));
                for (int i = 0; i < t.columns.size; i++) {
                    var tc = t.columns[i];
                    sb.append ("<tableColumn id=\"%d\" name=\"%s\"".printf (i + 1, esc (tc.name)));
                    if (t.totals_row && tc.totals_label != "") sb.append (" totalsRowLabel=\"%s\"".printf (esc (tc.totals_label)));
                    string code = t.totals_row ? totals_code (tc.totals_function) : "";
                    if (code != "") sb.append (" totalsRowFunction=\"%s\"".printf (code));
                    if (tc.calculated == "" && code != "custom") {
                        sb.append ("/>");
                        continue;
                    }
                    sb.append (">");
                    if (tc.calculated != "") {
                        string f = tc.calculated;
                        try {
                            var node = Formula.parse (f, book, t.sheet);
                            f = to_file (node, t.sheet, t.data_r1, t.area.c1 + i);
                        } catch (FormulaError e) {
                            f = XlsxWriter.strip_eq (f);
                        }
                        sb.append ("<calculatedColumnFormula>%s</calculatedColumnFormula>".printf (esc (f)));
                    }
                    if (code == "custom") sb.append ("<totalsRowFormula>%s</totalsRowFormula>".printf (esc (XlsxWriter.strip_eq (tc.totals_function))));
                    sb.append ("</tableColumn>");
                }
                sb.append ("</tableColumns>");
                sb.append ("<tableStyleInfo name=\"%s\" showFirstColumn=\"%d\" showLastColumn=\"%d\" showRowStripes=\"%d\" showColumnStripes=\"%d\"/>".printf (
                    esc (t.style_name), (int) t.first_col, (int) t.last_col, (int) t.banded_rows, (int) t.banded_cols));
                sb.append ("</table>");
                string pname = "xl/tables/table%d.xml".printf (n);
                part.writer.add_text_part (pname, sb.str, CT_TABLE);
                string rid = part.add_rel (REL_TABLE, "../tables/table%d.xml".printf (n));
                parts_xml.append ("<tablePart r:id=\"%s\"/>".printf (rid));
                count++;
            }
            if (count > 0) part.put ("tableParts", "<tableParts count=\"%d\">%s</tableParts>".printf (count, parts_xml.str));
        }

        private static string? xattr (Xml.Node* n, string name) {
            if (n == null) return null;
            return n->get_prop (name);
        }

        public static TableDef? read_table (Workbook book, Sheet sh, Xml.Node* root) {
            string? rf = xattr (root, "ref");
            if (rf == null) return null;
            var area = Area.parse (rf, sh);
            if (area == null) return null;
            string name = xattr (root, "displayName") ?? xattr (root, "name") ?? Tables.unique_name (book, "Table");
            var t = new TableDef (name, sh, area);
            t.header_row = (xattr (root, "headerRowCount") ?? "1") != "0";
            t.totals_row = (xattr (root, "totalsRowCount") ?? "0") != "0";
            t.filter_button = false;
            for (Xml.Node* ch = root->children; ch != null; ch = ch->next) {
                if (ch->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (ch->name == "autoFilter") t.filter_button = true;
                if (ch->name == "tableStyleInfo") {
                    t.style_name = xattr (ch, "name") ?? "";
                    t.first_col = (xattr (ch, "showFirstColumn") ?? "0") == "1";
                    t.last_col = (xattr (ch, "showLastColumn") ?? "0") == "1";
                    t.banded_rows = (xattr (ch, "showRowStripes") ?? "1") == "1";
                    t.banded_cols = (xattr (ch, "showColumnStripes") ?? "0") == "1";
                }
                if (ch->name == "tableColumns") {
                    for (Xml.Node* tc = ch->children; tc != null; tc = tc->next) {
                        if (tc->type != Xml.ElementType.ELEMENT_NODE || tc->name != "tableColumn") continue;
                        var col = new TableColumn (xattr (tc, "name") ?? "");
                        col.totals_label = xattr (tc, "totalsRowLabel") ?? "";
                        string code = xattr (tc, "totalsRowFunction") ?? "";
                        col.totals_function = totals_name (code);
                        for (Xml.Node* f = tc->children; f != null; f = f->next) {
                            if (f->type != Xml.ElementType.ELEMENT_NODE) continue;
                            if (f->name == "calculatedColumnFormula") col.calculated = "=" + f->get_content ();
                            if (f->name == "totalsRowFormula") col.totals_function = "=" + f->get_content ();
                        }
                        t.columns.add (col);
                    }
                }
            }
            if (t.columns.size != area.cols) t.sync_columns ();
            if (Tables.find (book, t.name) != null) t.name = Tables.unique_name (book, t.name);
            book.tables.add (t);
            return t;
        }

        private class PendingArray {
            public Sheet sheet;
            public Cell anchor;
            public string ref_text;
            public bool is_dyn;
        }

        private static Gee.ArrayList<PendingArray>? pending;

        public static void note_array (Sheet sh, Cell anchor, string ref_text, bool is_dyn) {
            if (pending == null) pending = new Gee.ArrayList<PendingArray> ();
            var p = new PendingArray ();
            p.sheet = sh;
            p.anchor = anchor;
            p.ref_text = ref_text;
            p.is_dyn = is_dyn;
            pending.add (p);
        }

        public static void finish_sheet (Sheet sh) {
            if (pending == null) return;
            var rest = new Gee.ArrayList<PendingArray> ();
            foreach (var p in pending) {
                if (p.sheet == sh) finish_array (sh, p.anchor, p.ref_text, p.is_dyn);
                else rest.add (p);
            }
            pending = rest;
        }

        public static void finish_array (Sheet sh, Cell anchor, string ref_text, bool is_dyn) {
            var area = Area.parse (ref_text, sh);
            if (area == null) return;
            if (!is_dyn) {
                if (area.is_single ()) return;
                anchor.array_area = area;
            }
            for (int r = area.r1; r <= area.r2; r++) {
                for (int c = area.c1; c <= area.c2; c++) {
                    if (r == anchor.row && c == anchor.col) continue;
                    var cell = sh.get_cell (r, c);
                    if (cell == null || cell.formula != null) continue;
                    cell.input = "";
                    cell.value = Value.empty ();
                    sh.drop_if_blank (r, c);
                }
            }
        }
    }
}
