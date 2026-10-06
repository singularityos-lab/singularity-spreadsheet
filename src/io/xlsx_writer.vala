namespace Singularity.Apps.Spreadsheet {

    public class XlsxWriter {
        private const string[] FUTURE = {
            "XLOOKUP", "XMATCH", "IFS", "SWITCH", "TEXTJOIN", "CONCAT", "MAXIFS", "MINIFS", "IFNA",
            "STDEV.S", "STDEV.P", "VAR.S", "VAR.P", "MODE.SNGL", "PERCENTILE.INC", "PERCENTILE.EXC",
            "QUARTILE.INC", "QUARTILE.EXC", "RANK.EQ", "RANK.AVG", "NORM.DIST", "NORM.S.DIST", "NORM.INV",
            "NORM.S.INV", "BINOM.DIST", "POISSON.DIST", "EXPON.DIST", "CONFIDENCE.NORM", "COVARIANCE.P",
            "COVARIANCE.S", "CEILING.MATH", "FLOOR.MATH", "CEILING.PRECISE", "FLOOR.PRECISE", "DAYS",
            "ISOWEEKNUM", "NETWORKDAYS.INTL", "WORKDAY.INTL", "NUMBERVALUE", "UNICHAR", "UNICODE", "XOR",
            "SHEET", "SHEETS", "ISFORMULA", "FORECAST.LINEAR", "TEXTBEFORE", "TEXTAFTER", "LET",
            "AGGREGATE", "PERCENTRANK.INC", "IMAGE"
        };

        private NamedXfs named_xfs = new NamedXfs ();
        public Workbook book;
        public string target_path = "";
        public string main_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml";
        public Gee.HashMap<string, string> defaults = new Gee.HashMap<string, string> ();
        public Gee.HashMap<string, string> overrides = new Gee.HashMap<string, string> ();
        public Gee.HashMap<string, string> extra_text = new Gee.HashMap<string, string> ();
        public Gee.HashMap<string, Bytes> extra_bin = new Gee.HashMap<string, Bytes> ();
        public StringBuilder workbook_rels_extra = new StringBuilder ();
        public StringBuilder defined_names = new StringBuilder ();
        public Gee.HashMap<string, string> workbook_slots = new Gee.HashMap<string, string> ();
        public Gee.ArrayList<XlsxSheetPart> parts = new Gee.ArrayList<XlsxSheetPart> ();
        private int workbook_rel_next = 1000;
        private int part_counter = 0;
        private Gee.ArrayList<string> strings = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, int> string_index = new Gee.HashMap<string, int> ();
        private Gee.ArrayList<CellStyle> dxf_styles = new Gee.ArrayList<CellStyle> ();

        public static void save (Workbook book, string path) throws Error {
            var w = new XlsxWriter ();
            w.book = book;
            w.target_path = path;
            string lower = path.down ();
            if (lower.has_suffix (".xlsm")) w.main_type = "application/vnd.ms-excel.sheet.macroEnabled.main+xml";
            else if (lower.has_suffix (".xltx")) w.main_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.template.main+xml";
            else if (lower.has_suffix (".xltm")) w.main_type = "application/vnd.ms-excel.template.macroEnabled.main+xml";
            var bytes = w.build ();
            FileUtils.set_data (path, bytes);
        }

        public static string esc (string s) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                switch (c) {
                    case '&': sb.append ("&amp;"); break;
                    case '<': sb.append ("&lt;"); break;
                    case '>': sb.append ("&gt;"); break;
                    case '"': sb.append ("&quot;"); break;
                    default:
                        if (c < 0x20 && c != '\t' && c != '\n' && c != '\r') continue;
                        sb.append_unichar (c);
                        break;
                }
            }
            return sb.str;
        }

        public static string xl_formula (Node n, Sheet own, int row = -1, int col = -1) {
            return XlsxDynamic.to_file (n, own, row, col);
        }

        private static void prefix_future (Node n) {
            if (n.kind == NodeKind.CALL) {
                foreach (string f in FUTURE) {
                    if (n.text == f) {
                        n.text = "_xlfn." + f;
                        break;
                    }
                }
            }
            foreach (var c in n.args) prefix_future (c);
        }

        private static string argb (string color) {
            string c = color.has_prefix ("#") ? color.substring (1) : color;
            if (c.length != 6) c = "000000";
            return "FF" + c.up ();
        }

        public int next_number () {
            return ++part_counter;
        }

        public void put_workbook (string slot, string xml) {
            workbook_slots[slot] = (workbook_slots.has_key (slot) ? workbook_slots[slot] : "") + xml;
        }

        private string workbook_slot (string slot) {
            return workbook_slots.has_key (slot) ? workbook_slots[slot] : "";
        }

        public string add_workbook_rel (string type, string target) {
            string id = "rId%d".printf (workbook_rel_next++);
            workbook_rels_extra.append ("<Relationship Id=\"%s\" Type=\"%s\" Target=\"%s\"/>".printf (id, type, esc (target)));
            return id;
        }

        public void add_defined_name (string name, int local_sheet, string value, bool hidden = false) {
            defined_names.append ("<definedName name=\"%s\"%s%s>%s</definedName>".printf (esc (name),
                local_sheet >= 0 ? " localSheetId=\"%d\"".printf (local_sheet) : "", hidden ? " hidden=\"1\"" : "", esc (value)));
        }

        public void add_text_part (string name, string text, string? content_type) {
            extra_text[name] = text;
            if (content_type != null) overrides["/" + name] = content_type;
        }

        public void add_binary_part (string name, Bytes data, string? content_type) {
            extra_bin[name] = data;
            if (content_type != null) overrides["/" + name] = content_type;
        }

        private int shared_string (string s) {
            if (string_index.has_key (s)) return string_index[s];
            strings.add (s);
            string_index[s] = strings.size - 1;
            return strings.size - 1;
        }

        public uint8[] build () throws Error {
            var zip = new ZipWriter ();
            var sheets_xml = new Gee.ArrayList<string> ();
            for (int i = 0; i < book.sheets.size; i++) {
                var part = new XlsxSheetPart (this, book.sheets[i], i + 1);
                parts.add (part);
                sheets_xml.add (sheet_xml (part, i == 0));
            }
            XlsxExtras.write_workbook (this);
            PrintIo.write_xlsx_workbook (this);
            EditIo.write_workbook (this);
            XlsxDynamic.write_workbook (this);
            string wb_xml = workbook_xml ();
            zip.add_text ("[Content_Types].xml", content_types ());
            zip.add_text ("_rels/.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>""");
            zip.add_text ("docProps/core.xml", XlsxExtras.core_xml (book));
            zip.add_text ("docProps/app.xml", XlsxExtras.app_xml (book));
            zip.add_text ("xl/workbook.xml", wb_xml);
            zip.add_text ("xl/_rels/workbook.xml.rels", workbook_rels ());
            zip.add_text ("xl/styles.xml", styles_xml ());
            zip.add_text ("xl/sharedStrings.xml", shared_xml ());
            for (int i = 0; i < sheets_xml.size; i++) {
                zip.add_text ("xl/worksheets/sheet%d.xml".printf (i + 1), sheets_xml[i]);
                string? r = parts[i].rels_xml ();
                if (r != null) zip.add_text ("xl/worksheets/_rels/sheet%d.xml.rels".printf (i + 1), r);
            }
            foreach (var e in extra_text.entries) zip.add_text (e.key, e.value);
            foreach (var e in extra_bin.entries) zip.add (e.key, e.value.get_data ());
            return zip.finish ();
        }

        private string content_types () {
            var sb = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>""");
            sb.append ("<Override PartName=\"/xl/workbook.xml\" ContentType=\"%s\"/>".printf (main_type));
            for (int i = 0; i < book.sheets.size; i++) {
                sb.append ("<Override PartName=\"/xl/worksheets/sheet%d.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>".printf (i + 1));
            }
            foreach (var e in defaults.entries) sb.append ("<Default Extension=\"%s\" ContentType=\"%s\"/>".printf (e.key, e.value));
            foreach (var e in overrides.entries) sb.append ("<Override PartName=\"%s\" ContentType=\"%s\"/>".printf (esc (e.key), e.value));
            sb.append ("</Types>");
            return sb.str;
        }

        private string workbook_xml () {
            var sb = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">""");
            sb.append ("<workbookPr%s%s/>".printf (book.date1904 ? " date1904=\"1\"" : "", workbook_slot ("workbookPr.attrs")));
            sb.append (workbook_slot ("workbookProtection"));
            sb.append ("<bookViews><workbookView%s/></bookViews><sheets>".printf (workbook_slot ("workbookView.attrs")));
            for (int i = 0; i < book.sheets.size; i++) {
                sb.append ("<sheet name=\"%s\" sheetId=\"%d\" r:id=\"rId%d\"%s/>".printf (esc (book.sheets[i].name), i + 1, i + 1, workbook_slot ("sheet%d.attrs".printf (i))));
            }
            sb.append ("</sheets>");
            sb.append (workbook_slot ("functionGroups"));
            sb.append (workbook_slot ("externalReferences"));
            bool any = book.names.size > 0 || defined_names.len > 0;
            foreach (var s in book.sheets) if (s.filter != null) any = true;
            if (any) {
                sb.append ("<definedNames>");
                for (int i = 0; i < book.sheets.size; i++) {
                    var s = book.sheets[i];
                    if (s.filter == null) continue;
                    var f = s.filter.area;
                    sb.append ("<definedName name=\"_xlnm._FilterDatabase\" localSheetId=\"%d\" hidden=\"1\">%s!%s</definedName>".printf (
                        i, esc (Address.quote_sheet (s.name)), Address.cell (f.r1, f.c1, true, true) + ":" + Address.cell (f.r2, f.c2, true, true)));
                }
                foreach (var e in book.names.entries) sb.append ("<definedName name=\"%s\">%s</definedName>".printf (esc (e.key), esc (strip_eq (e.value))));
                sb.append (defined_names.str);
                sb.append ("</definedNames>");
            }
            sb.append ("<calcPr calcId=\"191029\" fullCalcOnLoad=\"1\"%s/>".printf (workbook_slot ("calcPr.attrs")));
            sb.append (workbook_slot ("oleSize"));
            sb.append (workbook_slot ("customWorkbookViews"));
            sb.append (workbook_slot ("pivotCaches"));
            sb.append (workbook_slot ("webPublishing"));
            sb.append (workbook_slot ("extLst"));
            sb.append ("</workbook>");
            return sb.str;
        }

        private string workbook_rels () {
            var sb = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">""");
            int n = book.sheets.size;
            for (int i = 0; i < n; i++) {
                sb.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet%d.xml\"/>".printf (i + 1, i + 1));
            }
            sb.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>".printf (n + 1));
            sb.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.xml\"/>".printf (n + 2));
            sb.append (workbook_rels_extra.str);
            sb.append ("</Relationships>");
            return sb.str;
        }

        private string shared_xml () {
            var sb = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
""");
            sb.append ("<sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" count=\"%d\" uniqueCount=\"%d\">".printf (strings.size, strings.size));
            foreach (string s in strings) {
                bool pre = s != s.strip () || s.contains ("\n");
                sb.append ("<si><t%s>%s</t></si>".printf (pre ? " xml:space=\"preserve\"" : "", esc (s)));
            }
            sb.append ("</sst>");
            return sb.str;
        }

        private static string border_name (BorderStyle s) {
            switch (s) {
                case BorderStyle.THIN: return "thin";
                case BorderStyle.MEDIUM: return "medium";
                case BorderStyle.THICK: return "thick";
                case BorderStyle.DASHED: return "dashed";
                case BorderStyle.DOTTED: return "dotted";
                case BorderStyle.DOUBLE: return "double";
                default: return "";
            }
        }

        private static string font_xml (CellStyle s) {
            var sb = new StringBuilder ("<font>");
            if (s.bold) sb.append ("<b/>");
            if (s.italic) sb.append ("<i/>");
            if (s.strike) sb.append ("<strike/>");
            if (s.underline) sb.append ("<u/>");
            sb.append ("<sz val=\"%s\"/>".printf (Value.format_number_general_full (s.font_size)));
            if (s.color != "") sb.append ("<color rgb=\"%s\"/>".printf (argb (s.color)));
            else sb.append ("<color theme=\"1\"/>");
            sb.append ("<name val=\"%s\"/><family val=\"2\"/>".printf (esc (s.font_family != "" ? s.font_family : "Calibri")));
            sb.append ("</font>");
            return sb.str;
        }

        private static string border_side (string name, Border b) {
            string st = border_name (b.style);
            if (st == "") return "<%s/>".printf (name);
            string c = b.color != "" ? "<color rgb=\"%s\"/>".printf (argb (b.color)) : "<color auto=\"1\"/>";
            return "<%s style=\"%s\">%s</%s>".printf (name, st, c, name);
        }

        private static string border_xml (CellStyle s) {
            return "<border>" + border_side ("left", s.left) + border_side ("right", s.right) + border_side ("top", s.top) + border_side ("bottom", s.bottom) + "<diagonal/></border>";
        }

        private string styles_xml () {
            var builtin = new Gee.HashMap<string, int> ();
            string[] codes = { "General", "0", "0.00", "#,##0", "#,##0.00" };
            for (int i = 0; i < codes.length; i++) builtin[codes[i]] = i;
            builtin["0%"] = 9;
            builtin["0.00%"] = 10;
            builtin["0.00E+00"] = 11;
            builtin["# ?/?"] = 12;
            builtin["# ??/??"] = 13;
            builtin["h:mm"] = 20;
            builtin["h:mm:ss"] = 21;
            builtin["@"] = 49;
            var custom = new Gee.HashMap<string, int> ();
            var fonts = new Gee.ArrayList<string> ();
            var fills = new Gee.ArrayList<string> ();
            var borders = new Gee.ArrayList<string> ();
            fills.add ("<fill><patternFill patternType=\"none\"/></fill>");
            fills.add ("<fill><patternFill patternType=\"gray125\"/></fill>");
            var xfs = new StringBuilder ();
            foreach (var s in book.styles) {
                int fmt;
                if (builtin.has_key (s.number_format)) fmt = builtin[s.number_format];
                else if (custom.has_key (s.number_format)) fmt = custom[s.number_format];
                else {
                    fmt = 164 + custom.size;
                    custom[s.number_format] = fmt;
                }
                string f = font_xml (s);
                int fi = fonts.index_of (f);
                if (fi < 0) {
                    fonts.add (f);
                    fi = fonts.size - 1;
                }
                int fl = 0;
                if (s.fill != "") {
                    string fx = "<fill><patternFill patternType=\"solid\"><fgColor rgb=\"%s\"/><bgColor indexed=\"64\"/></patternFill></fill>".printf (argb (s.fill));
                    fl = fills.index_of (fx);
                    if (fl < 0) {
                        fills.add (fx);
                        fl = fills.size - 1;
                    }
                }
                string b = border_xml (s);
                int bi = borders.index_of (b);
                if (bi < 0) {
                    borders.add (b);
                    bi = borders.size - 1;
                }
                xfs.append ("<xf numFmtId=\"%d\" fontId=\"%d\" fillId=\"%d\" borderId=\"%d\" xfId=\"%d\"".printf (fmt, fi, fl, bi, named_xfs.xf_id (s, fmt, fi, fl, bi)));
                if (fmt != 0) xfs.append (" applyNumberFormat=\"1\"");
                if (fi != 0) xfs.append (" applyFont=\"1\"");
                if (fl != 0) xfs.append (" applyFill=\"1\"");
                if (bi != 0) xfs.append (" applyBorder=\"1\"");
                bool align = s.halign != HAlign.GENERAL || s.valign != VAlign.BOTTOM || s.wrap || s.indent > 0 || s.rotation != 0 || s.shrink;
                string prot = EditIo.xf_protection (s);
                if (prot != "") xfs.append (" applyProtection=\"1\"");
                if (align) {
                    xfs.append (" applyAlignment=\"1\"><alignment");
                    string[] h = { "", "left", "center", "right", "fill", "justify" };
                    string[] v = { "", "center", "top" };
                    if (s.halign != HAlign.GENERAL) xfs.append (" horizontal=\"%s\"".printf (h[s.halign]));
                    if (s.valign != VAlign.BOTTOM) xfs.append (" vertical=\"%s\"".printf (v[s.valign]));
                    if (s.wrap) xfs.append (" wrapText=\"1\"");
                    if (s.indent > 0) xfs.append (" indent=\"%d\"".printf (s.indent));
                    xfs.append (EditIo.xf_alignment_attrs (s));
                    xfs.append ("/>" + prot + "</xf>");
                } else if (prot != "") {
                    xfs.append (">" + prot + "</xf>");
                } else {
                    xfs.append ("/>");
                }
            }
            var sb = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">""");
            if (custom.size > 0) {
                sb.append ("<numFmts count=\"%d\">".printf (custom.size));
                foreach (var e in custom.entries) sb.append ("<numFmt numFmtId=\"%d\" formatCode=\"%s\"/>".printf (e.value, esc (e.key)));
                sb.append ("</numFmts>");
            }
            sb.append ("<fonts count=\"%d\">".printf (fonts.size));
            foreach (var f in fonts) sb.append (f);
            sb.append ("</fonts><fills count=\"%d\">".printf (fills.size));
            foreach (var f in fills) sb.append (f);
            sb.append ("</fills><borders count=\"%d\">".printf (borders.size));
            foreach (var b in borders) sb.append (b);
            sb.append ("</borders>" + named_xfs.style_xfs ());
            sb.append ("<cellXfs count=\"%d\">".printf (book.styles.size));
            sb.append (xfs.str);
            sb.append ("</cellXfs>" + named_xfs.cell_styles ());
            sb.append ("<dxfs count=\"%d\">".printf (dxf_styles.size));
            foreach (var d in dxf_styles) {
                sb.append ("<dxf>");
                if (d.bold || d.italic || d.color != "") {
                    sb.append ("<font>");
                    if (d.bold) sb.append ("<b/>");
                    if (d.italic) sb.append ("<i/>");
                    if (d.color != "") sb.append ("<color rgb=\"%s\"/>".printf (argb (d.color)));
                    sb.append ("</font>");
                }
                if (d.fill != "") sb.append ("<fill><patternFill><bgColor rgb=\"%s\"/></patternFill></fill>".printf (argb (d.fill)));
                sb.append ("</dxf>");
            }
            sb.append ("</dxfs></styleSheet>");
            return sb.str;
        }

        public int dxf_style (CellStyle st) {
            dxf_styles.add (st);
            return dxf_styles.size - 1;
        }

        private int dxf_for (int style) {
            var st = book.styles[style];
            dxf_styles.add (st);
            return dxf_styles.size - 1;
        }

        private static string area_ref (Area a) {
            if (a.is_single ()) return Address.cell (a.r1, a.c1);
            return Address.cell (a.r1, a.c1) + ":" + Address.cell (a.r2, a.c2);
        }

        public static string strip_eq (string f) {
            return f.has_prefix ("=") ? f.substring (1) : f;
        }

        private string sheet_xml (XlsxSheetPart part, bool first) {
            var s = part.sheet;
            if (s.merges.size > 0) {
                var mc = new StringBuilder ("<mergeCells count=\"%d\">".printf (s.merges.size));
                foreach (var m in s.merges) mc.append ("<mergeCell ref=\"%s\"/>".printf (area_ref (m)));
                mc.append ("</mergeCells>");
                part.put ("mergeCells", mc.str);
            }
            if (s.filter != null) part.put ("autoFilter", EditIo.auto_filter (this, s));
            if (s.sort_state != null) part.put ("sortState", EditIo.sort_state (this, s.sort_state));
            int priority = 1;
            foreach (var cf in s.cond_formats) part.put ("conditionalFormatting", cond_xml (cf, ref priority));
            EditIo.write_sheet (part);
            XlsxExtras.write_sheet (part);
            PrintIo.write_xlsx_sheet (part);
            XlsxDynamic.write_sheet (part);
            if (!part.has ("pageMargins")) part.put ("pageMargins", "<pageMargins left=\"0.7\" right=\"0.7\" top=\"0.75\" bottom=\"0.75\" header=\"0.3\" footer=\"0.3\"/>");
            var sb = new StringBuilder ("""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" xmlns:x14ac="http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac" xmlns:xr="http://schemas.microsoft.com/office/spreadsheetml/2014/revision" mc:Ignorable="x14ac xr">""");
            string tab = s.tab_color != "" ? "<tabColor rgb=\"%s\"/>".printf (argb (s.tab_color)) : "";
            if (tab != "" || part.sheet_pr.len > 0 || part.sheet_pr_attrs.len > 0) sb.append ("<sheetPr%s>%s%s</sheetPr>".printf (part.sheet_pr_attrs.str, tab, part.sheet_pr.str));
            sb.append ("<dimension ref=\"%s\"/>".printf (s.max_row >= 0 ? area_ref (s.used_area ()) : "A1"));
            sb.append ("<sheetViews><sheetView workbookViewId=\"0\"");
            sb.append (part.view_attrs.str);
            if (!s.show_grid) sb.append (" showGridLines=\"0\"");
            if (first) sb.append (" tabSelected=\"1\"");
            if (s.freeze_rows > 0 || s.freeze_cols > 0) {
                string pane = s.freeze_rows > 0 && s.freeze_cols > 0 ? "bottomRight" : (s.freeze_rows > 0 ? "bottomLeft" : "topRight");
                sb.append ("><pane");
                if (s.freeze_cols > 0) sb.append (" xSplit=\"%d\"".printf (s.freeze_cols));
                if (s.freeze_rows > 0) sb.append (" ySplit=\"%d\"".printf (s.freeze_rows));
                sb.append (" topLeftCell=\"%s\" activePane=\"%s\" state=\"frozen\"/></sheetView>".printf (Address.cell (s.freeze_rows, s.freeze_cols), pane));
            } else {
                sb.append ("/>");
            }
            sb.append ("</sheetViews>");
            sb.append ("<sheetFormatPr defaultRowHeight=\"%s\"%s/>".printf (Value.fixed (s.default_row_height / Xlsx.ROW_SCALE * 0.75, 2), part.format_pr_attrs.str));
            var cols = new Gee.TreeSet<int> ();
            foreach (int c in s.col_widths.keys) cols.add (c);
            foreach (int c in s.hidden_cols) cols.add (c);
            foreach (int c in part.col_attrs.keys) cols.add (c);
            if (cols.size > 0) {
                sb.append ("<cols>");
                foreach (int c in cols) {
                    int px = s.col_widths.has_key (c) ? s.col_widths[c] : s.default_col_width;
                    double w = double.max ((px / Xlsx.COL_SCALE - 5) / 7.0, 0);
                    sb.append ("<col min=\"%d\" max=\"%d\" width=\"%s\" customWidth=\"1\"%s%s/>".printf (c + 1, c + 1, Value.fixed (w, 2), s.hidden_cols.contains (c) ? " hidden=\"1\"" : "", part.col_attrs.has_key (c) ? part.col_attrs[c] : ""));
                }
                sb.append ("</cols>");
            }
            var rows = new Gee.TreeMap<int, Gee.TreeMap<int, Cell>> ();
            foreach (var k in s.cells.keys) {
                int r = Sheet.key_row (k);
                if (!rows.has_key (r)) rows[r] = new Gee.TreeMap<int, Cell> ();
                rows[r][Sheet.key_col (k)] = s.cells[k];
            }
            foreach (int r in s.row_heights.keys) if (!rows.has_key (r)) rows[r] = new Gee.TreeMap<int, Cell> ();
            foreach (int r in s.hidden_rows) if (!rows.has_key (r)) rows[r] = new Gee.TreeMap<int, Cell> ();
            foreach (int r in part.row_attrs.keys) if (!rows.has_key (r)) rows[r] = new Gee.TreeMap<int, Cell> ();
            sb.append ("<sheetData>");
            XlsxDynamic.add_spilled_cells (s, rows);
            foreach (var re in rows.entries) {
                int r = re.key;
                sb.append ("<row r=\"%d\"".printf (r + 1));
                if (s.row_heights.has_key (r)) sb.append (" ht=\"%s\" customHeight=\"1\"".printf (Value.fixed (s.row_heights[r] / Xlsx.ROW_SCALE * 0.75, 2)));
                if (s.hidden_rows.contains (r)) sb.append (" hidden=\"1\"");
                if (part.row_attrs.has_key (r)) sb.append (part.row_attrs[r]);
                sb.append (">");
                foreach (var ce in re.value.entries) cell_xml (sb, s, r, ce.key, ce.value);
                sb.append ("</row>");
            }
            sb.append ("</sheetData>");
            sb.append (part.tail ());
            sb.append ("</worksheet>");
            return sb.str;
        }

        private string cond_xml (CondFormat cf, ref int priority) {
            var sb = new StringBuilder ("<conditionalFormatting sqref=\"%s\">".printf (area_ref (cf.area)));
            string dxf = "";
            if (cf.kind != CondKind.COLOR_SCALE && cf.kind != CondKind.DATA_BAR && cf.kind != CondKind.ICON_SET) dxf = " dxfId=\"%d\"".printf (dxf_for (cf.style));
            string head = "<cfRule priority=\"%d\"%s%s".printf (priority++, dxf, cf.stop_if_true ? " stopIfTrue=\"1\"" : "");
            string? extra = CondXml.rule (cf, head);
            if (extra != null) {
                sb.append (extra);
                sb.append ("</conditionalFormatting>");
                return sb.str;
            }
            switch (cf.kind) {
                case CondKind.GREATER:
                case CondKind.LESS:
                case CondKind.EQUAL:
                case CondKind.NOT_EQUAL:
                    string[] ops = { "greaterThan", "lessThan", "", "equal", "notEqual" };
                    int idx = cf.kind == CondKind.GREATER ? 0 : (cf.kind == CondKind.LESS ? 1 : (cf.kind == CondKind.EQUAL ? 3 : 4));
                    sb.append (head + " type=\"cellIs\" operator=\"%s\"><formula>%s</formula></cfRule>".printf (ops[idx], esc (cf.a)));
                    break;
                case CondKind.BETWEEN:
                    sb.append (head + " type=\"cellIs\" operator=\"between\"><formula>%s</formula><formula>%s</formula></cfRule>".printf (esc (cf.a), esc (cf.b)));
                    break;
                case CondKind.TEXT_CONTAINS:
                    string first = Address.cell (cf.area.r1, cf.area.c1);
                    sb.append (head + " type=\"containsText\" operator=\"containsText\" text=\"%s\"><formula>NOT(ISERROR(SEARCH(\"%s\",%s)))</formula></cfRule>".printf (esc (cf.a), esc (cf.a.replace ("\"", "\"\"")), first));
                    break;
                case CondKind.DUPLICATE:
                    sb.append (head + " type=\"duplicateValues\"/>");
                    break;
                case CondKind.UNIQUE:
                    sb.append (head + " type=\"uniqueValues\"/>");
                    break;
                case CondKind.FORMULA:
                    string f = cf.a.has_prefix ("=") ? cf.a.substring (1) : cf.a;
                    sb.append (head + " type=\"expression\"><formula>%s</formula></cfRule>".printf (esc (f)));
                    break;
                case CondKind.BLANK:
                    sb.append (head + " type=\"containsBlanks\"><formula>LEN(TRIM(%s))=0</formula></cfRule>".printf (Address.cell (cf.area.r1, cf.area.c1)));
                    break;
                case CondKind.ERRORS:
                    sb.append (head + " type=\"containsErrors\"><formula>ISERROR(%s)</formula></cfRule>".printf (Address.cell (cf.area.r1, cf.area.c1)));
                    break;
                case CondKind.TOP:
                case CondKind.BOTTOM:
                    sb.append (head + " type=\"top10\" rank=\"%s\"%s%s/>".printf (cf.a != "" ? cf.a : "10", cf.kind == CondKind.BOTTOM ? " bottom=\"1\"" : "", cf.percent ? " percent=\"1\"" : ""));
                    break;
                case CondKind.ABOVE_AVERAGE:
                    sb.append (head + " type=\"aboveAverage\"/>");
                    break;
                case CondKind.BELOW_AVERAGE:
                    sb.append (head + " type=\"aboveAverage\" aboveAverage=\"0\"/>");
                    break;
                case CondKind.COLOR_SCALE:
                    sb.append (head + " type=\"colorScale\"><colorScale><cfvo type=\"min\"/>");
                    if (cf.three_colors) sb.append ("<cfvo type=\"percentile\" val=\"50\"/>");
                    sb.append ("<cfvo type=\"max\"/><color rgb=\"%s\"/>".printf (argb (cf.color1)));
                    if (cf.three_colors) sb.append ("<color rgb=\"%s\"/>".printf (argb (cf.color2)));
                    sb.append ("<color rgb=\"%s\"/></colorScale></cfRule>".printf (argb (cf.color3)));
                    break;
                case CondKind.DATA_BAR:
                    sb.append (head + " type=\"dataBar\"><dataBar><cfvo type=\"min\"/><cfvo type=\"max\"/><color rgb=\"%s\"/></dataBar></cfRule>".printf (argb (cf.color1)));
                    break;
            }
            sb.append ("</conditionalFormatting>");
            return sb.str;
        }

        private void cell_xml (StringBuilder sb, Sheet s, int r, int c, Cell cell) {
            string addr = Address.cell (r, c);
            string st = cell.style > 0 ? " s=\"%d\"".printf (cell.style) : "";
            if (cell.formula != null) {
                var v = book.cell_value (s, cell);
                string t = "";
                string vtext = "";
                switch (v.kind) {
                    case ValueKind.TEXT: t = " t=\"str\""; vtext = esc (v.text); break;
                    case ValueKind.BOOL: t = " t=\"b\""; vtext = v.number != 0 ? "1" : "0"; break;
                    case ValueKind.ERROR: t = " t=\"e\""; vtext = v.error == ErrorKind.CIRC || v.error == ErrorKind.CALC || v.error == ErrorKind.SPILL || v.error == ErrorKind.GETTING_DATA ? "#VALUE!" : v.error.to_string (); break;
                    case ValueKind.NUMBER: vtext = Value.format_number_general_full (v.number); break;
                    default: vtext = "0"; break;
                }
                bool is_dyn;
                string fattrs = XlsxDynamic.array_attrs (s, cell, out is_dyn);
                sb.append ("<c r=\"%s\"%s%s%s><f%s>%s</f><v>%s</v></c>".printf (addr, st, t, is_dyn ? " cm=\"1\"" : "", fattrs, esc (xl_formula (cell.formula, s, r, c)), vtext));
                return;
            }
            var v = cell.value;
            switch (v.kind) {
                case ValueKind.NUMBER:
                    sb.append ("<c r=\"%s\"%s>%s<v>%s</v></c>".printf (addr, st, PivotXlsx.data_table_formula (book, s, r, c), Value.format_number_general_full (v.number)));
                    break;
                case ValueKind.TEXT:
                    sb.append ("<c r=\"%s\"%s t=\"s\"><v>%d</v></c>".printf (addr, st, shared_string (v.text)));
                    break;
                case ValueKind.BOOL:
                    sb.append ("<c r=\"%s\"%s t=\"b\"><v>%s</v></c>".printf (addr, st, v.number != 0 ? "1" : "0"));
                    break;
                case ValueKind.ERROR:
                    sb.append ("<c r=\"%s\"%s t=\"e\"><v>%s</v></c>".printf (addr, st, v.error.to_string ()));
                    break;
                default:
                    if (cell.style > 0) sb.append ("<c r=\"%s\"%s/>".printf (addr, st));
                    break;
            }
        }
    }
}
