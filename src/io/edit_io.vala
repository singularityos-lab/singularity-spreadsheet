namespace Singularity.Apps.Spreadsheet {

    public class NamedXfs {
        private Gee.ArrayList<string> names = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, string> xf = new Gee.HashMap<string, string> ();

        public int xf_id (CellStyle s, int fmt, int font, int fill, int border) {
            if (s.style_name == "") return 0;
            int i = names.index_of (s.style_name);
            if (i < 0) {
                names.add (s.style_name);
                xf[s.style_name] = "<xf numFmtId=\"%d\" fontId=\"%d\" fillId=\"%d\" borderId=\"%d\"/>".printf (fmt, font, fill, border);
                i = names.size - 1;
            }
            return i + 1;
        }

        public string style_xfs () {
            var sb = new StringBuilder ("<cellStyleXfs count=\"%d\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/>".printf (names.size + 1));
            foreach (string n in names) sb.append (xf[n]);
            sb.append ("</cellStyleXfs>");
            return sb.str;
        }

        public string cell_styles () {
            var sb = new StringBuilder ("<cellStyles count=\"%d\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/>".printf (names.size + 1));
            for (int i = 0; i < names.size; i++) {
                int b = NamedStyle.builtin_id (names[i]);
                sb.append ("<cellStyle name=\"%s\" xfId=\"%d\"%s/>".printf (XlsxWriter.esc (names[i]), i + 1, b > 0 ? " builtinId=\"%d\"".printf (b) : " customBuiltin=\"0\""));
            }
            sb.append ("</cellStyles>");
            return sb.str;
        }
    }

    public class EditIo {
        private static Gee.HashMap<int, string>? style_names;

        public static void read_style_names (Xml.Node* root) {
            style_names = new Gee.HashMap<int, string> ();
            foreach (Xml.Node* cs in kids (child (root, "cellStyles"), "cellStyle")) {
                string n = attr (cs, "name");
                if (n != "" && n != "Normal") style_names[int.parse (attr (cs, "xfId", "0"))] = n;
            }
        }

        private static Xml.Node* child (Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        private static Gee.ArrayList<Xml.Node*> kids (Xml.Node* n, string? name = null) {
            var l = new Gee.ArrayList<Xml.Node*> ();
            if (n == null) return l;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && (name == null || c->name == name)) l.add (c);
            }
            return l;
        }

        private static string attr (Xml.Node* n, string name, string def = "") {
            if (n == null) return def;
            string? v = n->get_prop (name);
            return v ?? def;
        }

        private static bool flag (Xml.Node* n, string name, bool def) {
            string v = attr (n, name);
            if (v == "") return def;
            return v == "1" || v == "true";
        }

        private static string text_of (Xml.Node* n) {
            if (n == null) return "";
            string? t = n->get_content ();
            return t ?? "";
        }

        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        public static void read_xf (CellStyle st, Xml.Node* xf) {
            int xid = int.parse (attr (xf, "xfId", "0"));
            if (style_names != null && style_names.has_key (xid)) st.style_name = style_names[xid];
            var al = child (xf, "alignment");
            if (al != null) {
                string rot = attr (al, "textRotation");
                if (rot != "") {
                    int v = int.parse (rot);
                    st.rotation = v > 90 && v <= 180 ? 90 - v : v;
                }
                st.shrink = flag (al, "shrinkToFit", false);
            }
            var pr = child (xf, "protection");
            if (pr != null) {
                st.locked = flag (pr, "locked", true);
                st.hidden = flag (pr, "hidden", false);
            }
        }

        public static string xf_alignment_attrs (CellStyle s) {
            var sb = new StringBuilder ();
            if (s.rotation != 0) {
                int v = s.rotation == 255 ? 255 : (s.rotation < 0 ? 90 - s.rotation : s.rotation);
                sb.append (" textRotation=\"%d\"".printf (v));
            }
            if (s.shrink) sb.append (" shrinkToFit=\"1\"");
            return sb.str;
        }

        public static string xf_protection (CellStyle s) {
            if (s.locked && !s.hidden) return "";
            var sb = new StringBuilder ("<protection");
            if (!s.locked) sb.append (" locked=\"0\"");
            if (s.hidden) sb.append (" hidden=\"1\"");
            sb.append ("/>");
            return sb.str;
        }

        private static PasswordHash read_hash (Xml.Node* n, string prefix) {
            var p = new PasswordHash ();
            string alg = prefix == "" ? "algorithmName" : prefix + "AlgorithmName";
            string hv = prefix == "" ? "hashValue" : prefix + "HashValue";
            string sv = prefix == "" ? "saltValue" : prefix + "SaltValue";
            string sc = prefix == "" ? "spinCount" : prefix + "SpinCount";
            string pw = prefix == "" ? "password" : prefix + "Password";
            p.algorithm = attr (n, alg);
            p.hash = attr (n, hv);
            p.salt = attr (n, sv);
            p.spin_count = int.parse (attr (n, sc, "100000"));
            p.legacy = attr (n, pw);
            return p;
        }

        private static string write_hash (PasswordHash p, string prefix) {
            if (!p.is_set ()) return "";
            var sb = new StringBuilder ();
            string alg = prefix == "" ? "algorithmName" : prefix + "AlgorithmName";
            string hv = prefix == "" ? "hashValue" : prefix + "HashValue";
            string sv = prefix == "" ? "saltValue" : prefix + "SaltValue";
            string sc = prefix == "" ? "spinCount" : prefix + "SpinCount";
            string pw = prefix == "" ? "password" : prefix + "Password";
            if (p.hash != "" && !p.algorithm.has_prefix ("odf:")) {
                sb.append (" %s=\"%s\" %s=\"%s\" %s=\"%s\" %s=\"%d\"".printf (alg, esc (p.algorithm), hv, esc (p.hash), sv, esc (p.salt), sc, p.spin_count));
            } else if (p.legacy != "") {
                sb.append (" %s=\"%s\"".printf (pw, esc (p.legacy)));
            }
            return sb.str;
        }

        public static void read_workbook (Workbook book, Xml.Node* root) {
            view_names = new Gee.HashMap<string, string> ();
            foreach (Xml.Node* wv in kids (child (root, "customWorkbookViews"), "customWorkbookView")) view_names[attr (wv, "guid").up ()] = attr (wv, "name");
            var wp = child (root, "workbookProtection");
            if (wp == null) return;
            var p = new BookProtection ();
            p.structure = flag (wp, "lockStructure", false);
            p.windows = flag (wp, "lockWindows", false);
            p.password = read_hash (wp, "workbook");
            if (p.structure || p.windows || p.password.is_set ()) book.protection = p;
        }

        public static string workbook_protection (Workbook book) {
            var p = book.protection;
            if (p == null) return "";
            return "<workbookProtection%s%s%s/>".printf (write_hash (p.password, "workbook"), p.structure ? " lockStructure=\"1\"" : "", p.windows ? " lockWindows=\"1\"" : "");
        }

        public static void read_theme (Workbook book, string? xml) {
            if (xml == null) return;
            var doc = Xml.Parser.read_memory (xml, xml.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOBLANKS);
            if (doc == null) return;
            var root = doc->get_root_element ();
            var t = book.theme.copy ();
            Xml.Node* scheme = find (root, "clrScheme");
            string[] order = { "lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink" };
            if (scheme != null) {
                t.name = attr (scheme, "name", t.name);
                string[] cols = t.colors;
                for (int i = 0; i < order.length; i++) {
                    var c = child (scheme, order[i]);
                    foreach (var v in kids (c)) {
                        string val = v->name == "sysClr" ? attr (v, "lastClr") : attr (v, "val");
                        if (val.length == 6) cols[i] = "#" + val.down ();
                    }
                }
                t.colors = cols;
            }
            Xml.Node* fonts = find (root, "fontScheme");
            if (fonts != null) {
                var major = child (child (fonts, "majorFont"), "latin");
                var minor = child (child (fonts, "minorFont"), "latin");
                if (major != null && attr (major, "typeface") != "") t.major_font = attr (major, "typeface");
                if (minor != null && attr (minor, "typeface") != "") t.minor_font = attr (minor, "typeface");
            }
            book.theme = t;
            delete doc;
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

        public static void read_sheet (Sheet sh, Xml.Node* root) {
            var book = sh.book;
            if (book.names.has_key (LISTS_NAME)) {
                string v = book.names[LISTS_NAME];
                if (v.has_prefix ("=")) v = v.substring (1);
                if (v.has_prefix ("\"") && v.has_suffix ("\"") && v.length >= 2) v = v.substring (1, v.length - 2);
                book.custom_lists.clear ();
                CustomLists.decode (v, book.custom_lists);
                book.names.unset (LISTS_NAME);
            }
            var props = child (root, "sheetPr");
            var op = child (props, "outlinePr");
            if (op != null) {
                sh.outline.summary_below = flag (op, "summaryBelow", true);
                sh.outline.summary_right = flag (op, "summaryRight", true);
            }
            foreach (Xml.Node* col in kids (child (root, "cols"), "col")) {
                int lv = int.parse (attr (col, "outlineLevel", "0"));
                bool collapsed = flag (col, "collapsed", false);
                int min = int.parse (attr (col, "min")) - 1;
                int max = int.min (int.parse (attr (col, "max")) - 1, MAX_COLS - 1);
                if (min < 0 || max - min > 16384) continue;
                for (int c = min; c <= max; c++) {
                    if (lv > 0) sh.outline.col_levels[c] = lv.clamp (1, MAX_OUTLINE);
                    if (collapsed) sh.outline.collapsed_cols.add (c);
                }
            }
            foreach (Xml.Node* row in kids (child (root, "sheetData"), "row")) {
                int r = int.parse (attr (row, "r")) - 1;
                if (r < 0) continue;
                int lv = int.parse (attr (row, "outlineLevel", "0"));
                if (lv > 0) sh.outline.row_levels[r] = lv.clamp (1, MAX_OUTLINE);
                if (flag (row, "collapsed", false)) sh.outline.collapsed_rows.add (r);
            }
            var sp = child (root, "sheetProtection");
            if (sp != null && flag (sp, "sheet", false)) {
                var p = new SheetProtection ();
                p.password = read_hash (sp, "");
                p.objects = !flag (sp, "objects", false);
                p.scenarios = !flag (sp, "scenarios", false);
                p.format_cells = !flag (sp, "formatCells", true);
                p.format_columns = !flag (sp, "formatColumns", true);
                p.format_rows = !flag (sp, "formatRows", true);
                p.insert_columns = !flag (sp, "insertColumns", true);
                p.insert_rows = !flag (sp, "insertRows", true);
                p.insert_hyperlinks = !flag (sp, "insertHyperlinks", true);
                p.delete_columns = !flag (sp, "deleteColumns", true);
                p.delete_rows = !flag (sp, "deleteRows", true);
                p.select_locked = !flag (sp, "selectLockedCells", false);
                p.select_unlocked = !flag (sp, "selectUnlockedCells", false);
                p.sort = !flag (sp, "sort", true);
                p.autofilter = !flag (sp, "autoFilter", true);
                p.pivot_tables = !flag (sp, "pivotTables", true);
                foreach (Xml.Node* pr in kids (child (root, "protectedRanges"), "protectedRange")) {
                    foreach (string part in attr (pr, "sqref").split (" ")) {
                        var a = Area.parse (part, sh);
                        if (a == null) continue;
                        var er = new EditRange (attr (pr, "name"), a);
                        er.password = read_hash (pr, "");
                        p.ranges.add (er);
                    }
                }
                sh.protection = p;
            }
            read_views (sh, root);
            var dvs = child (root, "dataValidations");
            if (dvs != null) {
                sh.validations.clear ();
                foreach (Xml.Node* dv in kids (dvs, "dataValidation")) read_validation (sh, dv);
            }
        }

        private static void read_validation (Sheet sh, Xml.Node* dv) {
            string sqref = attr (dv, "sqref");
            var f1 = child (dv, "formula1");
            var f2 = child (dv, "formula2");
            if (sqref == "") {
                var xm = child (dv, "sqref");
                if (xm != null) sqref = text_of (xm);
                if (f1 != null && child (f1, "f") != null) f1 = child (f1, "f");
                if (f2 != null && child (f2, "f") != null) f2 = child (f2, "f");
            }
            foreach (string part in sqref.split (" ")) {
                var a = Area.parse (part, sh);
                if (a == null) continue;
                var v = new Validation (a);
                v.kind = ValidationKind.from_xlsx (attr (dv, "type", "none"));
                v.op = ValidationOp.from_xlsx (attr (dv, "operator", "between"));
                v.formula1 = text_of (f1);
                v.formula2 = text_of (f2);
                if (v.kind == ValidationKind.LIST) v.list_source = v.formula1;
                v.allow_blank = flag (dv, "allowBlank", false);
                v.dropdown = !flag (dv, "showDropDown", false);
                v.show_input = flag (dv, "showInputMessage", false);
                v.show_error = flag (dv, "showErrorMessage", false);
                v.input_title = attr (dv, "promptTitle");
                v.message = attr (dv, "prompt");
                v.error_title = attr (dv, "errorTitle");
                v.error_message = attr (dv, "error");
                v.alert = ValidationAlert.from_xlsx (attr (dv, "errorStyle", "stop"));
                sh.validations.add (v);
            }
        }

        public static void read_ext_validations (Sheet sh, Xml.Node* root) {
            var ext = child (root, "extLst");
            foreach (Xml.Node* e in kids (ext, "ext")) {
                foreach (Xml.Node* dvs in kids (e, "dataValidations")) {
                    foreach (Xml.Node* dv in kids (dvs, "dataValidation")) read_validation (sh, dv);
                }
            }
        }

        public static string sheet_pr_inner (Sheet s) {
            if (s.outline.summary_below && s.outline.summary_right) return "";
            return "<outlinePr%s%s/>".printf (s.outline.summary_below ? "" : " summaryBelow=\"0\"", s.outline.summary_right ? "" : " summaryRight=\"0\"");
        }

        public static string format_pr_attrs (Sheet s) {
            var sb = new StringBuilder ();
            int rl = s.outline.max_level (true), cl = s.outline.max_level (false);
            if (rl > 0) sb.append (" outlineLevelRow=\"%d\"".printf (rl));
            if (cl > 0) sb.append (" outlineLevelCol=\"%d\"".printf (cl));
            return sb.str;
        }

        public static string row_attrs (Sheet s, int r) {
            var sb = new StringBuilder ();
            int lv = s.outline.level_of (true, r);
            if (lv > 0) sb.append (" outlineLevel=\"%d\"".printf (lv));
            if (s.outline.collapsed_rows.contains (r)) sb.append (" collapsed=\"1\"");
            return sb.str;
        }

        public static string col_attrs (Sheet s, int c) {
            var sb = new StringBuilder ();
            int lv = s.outline.level_of (false, c);
            if (lv > 0) sb.append (" outlineLevel=\"%d\"".printf (lv));
            if (s.outline.collapsed_cols.contains (c)) sb.append (" collapsed=\"1\"");
            return sb.str;
        }

        public const string VIEW_EXT = "{8E1C5B4A-3F0D-4C1E-9D3B-5A7F2E6C9B10}";

        public static string view_guid (string name) {
            string h = Checksum.compute_for_string (ChecksumType.MD5, name.casefold ()).up ();
            return "{%s-%s-%s-%s-%s}".printf (h.substring (0, 8), h.substring (8, 4), h.substring (12, 4), h.substring (16, 4), h.substring (20, 12));
        }

        private static string op_xlsx (string op) {
            switch (op) {
                case "notequal": case "notcontains": return "notEqual";
                case "greater": return "greaterThan";
                case "less": return "lessThan";
                case "greaterequal": return "greaterThanOrEqual";
                case "lessequal": return "lessThanOrEqual";
                default: return "";
            }
        }

        private static void op_from_xlsx (string op, string val, out string our_op, out string our_val) {
            our_val = val;
            switch (op) {
                case "notEqual":
                    if (val.has_prefix ("*") && val.has_suffix ("*") && val.length > 2) {
                        our_op = "notcontains";
                        our_val = val.substring (1, val.length - 2);
                    } else {
                        our_op = "notequal";
                    }
                    return;
                case "greaterThan": our_op = "greater"; return;
                case "lessThan": our_op = "less"; return;
                case "greaterThanOrEqual": our_op = "greaterequal"; return;
                case "lessThanOrEqual": our_op = "lessequal"; return;
            }
            if (val.length > 2 && val.has_prefix ("*") && val.has_suffix ("*")) {
                our_op = "contains";
                our_val = val.substring (1, val.length - 2);
            } else if (val.length > 1 && val.has_suffix ("*") && !val.has_suffix ("~*")) {
                our_op = "begins";
                our_val = val.substring (0, val.length - 1);
            } else if (val.length > 1 && val.has_prefix ("*")) {
                our_op = "ends";
                our_val = val.substring (1);
            } else {
                our_op = "equal";
            }
        }

        private static int color_dxf (XlsxWriter w, string color, bool fill) {
            var st = new CellStyle ();
            if (fill) st.fill = color;
            else st.color = color;
            return w.dxf_style (st);
        }

        public static string auto_filter (XlsxWriter w, Sheet s) {
            var f = s.filter;
            var sb = new StringBuilder ("<autoFilter ref=\"%s\"".printf (area_ref (f.area)));
            var cols = new Gee.TreeSet<int> ();
            cols.add_all (f.rules.keys);
            foreach (var e in f.hidden_values.entries) if (e.value.size > 0) cols.add (e.key);
            if (cols.size == 0) return sb.str + "/>";
            sb.append (">");
            foreach (int col in cols) {
                if (col < f.area.c1 || col > f.area.c2) continue;
                sb.append ("<filterColumn colId=\"%d\">".printf (col - f.area.c1));
                var rule = f.rules.has_key (col) ? f.rules[col] : null;
                if (rule == null || rule.kind == FilterKind.VALUES) {
                    var hidden = f.hidden_values.has_key (col) ? f.hidden_values[col] : new Gee.HashSet<string> ();
                    var shown = new Gee.TreeSet<string> ();
                    bool blank = false;
                    for (int r = f.area.r1 + 1; r <= f.area.r2; r++) {
                        string color;
                        var v = s.value_at (r, col);
                        string t = NumberFormat.format_value (v, s.style_at (r, col).number_format, out color, w.book.date1904);
                        if (hidden.contains (t)) continue;
                        if (rule != null && rule.dates.size > 0 && v.kind == ValueKind.NUMBER && NumberFormat.is_date_format (s.style_at (r, col).number_format)) continue;
                        if (t == "") blank = true;
                        else shown.add (t);
                    }
                    sb.append ("<filters%s>".printf (blank && (rule == null || rule.blanks) ? " blank=\"1\"" : ""));
                    foreach (string t in shown) sb.append ("<filter val=\"%s\"/>".printf (esc (t)));
                    if (rule != null) {
                        foreach (string key in rule.dates) {
                            if (key == "0000") continue;
                            var parts = key.split ("-");
                            string grouping = parts.length == 1 ? "year" : (parts.length == 2 ? "month" : "day");
                            sb.append ("<dateGroupItem year=\"%s\"".printf (parts[0]));
                            if (parts.length > 1) sb.append (" month=\"%d\"".printf (int.parse (parts[1])));
                            if (parts.length > 2) sb.append (" day=\"%d\"".printf (int.parse (parts[2])));
                            sb.append (" dateTimeGrouping=\"%s\"/>".printf (grouping));
                        }
                    }
                    sb.append ("</filters>");
                } else {
                    switch (rule.kind) {
                        case FilterKind.CUSTOM:
                            sb.append ("<customFilters%s>".printf (rule.and_join && rule.op2 != "" ? " and=\"1\"" : ""));
                            string[] ops = { rule.op1, rule.op2 };
                            string[] vals = { rule.v1, rule.v2 };
                            for (int i = 0; i < 2; i++) {
                                if (ops[i] == "") continue;
                                string xo = op_xlsx (ops[i]);
                                sb.append ("<customFilter%s val=\"%s\"/>".printf (xo != "" ? " operator=\"%s\"".printf (xo) : "", esc (FilterEngine.wildcard_of (ops[i], vals[i]))));
                            }
                            sb.append ("</customFilters>");
                            break;
                        case FilterKind.TOP10:
                            sb.append ("<top10%s%s val=\"%s\"/>".printf (rule.bottom ? " top=\"0\"" : "", rule.percent ? " percent=\"1\"" : "", Value.format_number_general_full (rule.top)));
                            break;
                        case FilterKind.DYNAMIC:
                            sb.append ("<dynamicFilter type=\"%s\"/>".printf (rule.dyn_type));
                            break;
                        case FilterKind.CELL_COLOR:
                        case FilterKind.FONT_COLOR:
                            bool fill = rule.kind == FilterKind.CELL_COLOR;
                            sb.append ("<colorFilter dxfId=\"%d\"%s/>".printf (color_dxf (w, rule.color, fill), fill ? "" : " cellColor=\"0\""));
                            break;
                        case FilterKind.ICON:
                            sb.append ("<iconFilter iconSet=\"%s\" iconId=\"%d\"/>".printf (rule.icon_set != "" ? rule.icon_set : "3TrafficLights1", rule.icon));
                            break;
                        default:
                            break;
                    }
                }
                sb.append ("</filterColumn>");
            }
            sb.append ("</autoFilter>");
            return sb.str;
        }

        public static string sort_state (XlsxWriter w, SortSpec spec) {
            var a = spec.area;
            int first = spec.columns ? (spec.header ? a.c1 + 1 : a.c1) : (spec.header ? a.r1 + 1 : a.r1);
            var body = spec.columns ? new Area (a.sheet, a.r1, first, a.r2, a.c2) : new Area (a.sheet, first, a.c1, a.r2, a.c2);
            var sb = new StringBuilder ("<sortState ref=\"%s\"%s%s>".printf (area_ref (body), spec.case_sensitive ? " caseSensitive=\"1\"" : "", spec.columns ? " columnSort=\"1\"" : ""));
            foreach (var lv in spec.levels) {
                var key = spec.columns ? new Area (a.sheet, lv.index, body.c1, lv.index, body.c2) : new Area (a.sheet, body.r1, lv.index, body.r2, lv.index);
                sb.append ("<sortCondition%s ref=\"%s\"".printf (lv.ascending ? "" : " descending=\"1\"", area_ref (key)));
                if (lv.by == SortBy.CELL_COLOR) sb.append (" sortBy=\"cellColor\" dxfId=\"%d\"".printf (color_dxf (w, lv.color, true)));
                else if (lv.by == SortBy.FONT_COLOR) sb.append (" sortBy=\"fontColor\" dxfId=\"%d\"".printf (color_dxf (w, lv.color, false)));
                else if (lv.by == SortBy.ICON) sb.append (" sortBy=\"icon\" iconSet=\"%s\" iconId=\"%d\"".printf (lv.icon_set != "" ? lv.icon_set : "3TrafficLights1", lv.icon));
                if (lv.custom_list != "") sb.append (" customList=\"%s\"".printf (esc (lv.custom_list.replace ("|", ","))));
                sb.append ("/>");
            }
            sb.append ("</sortState>");
            return sb.str;
        }

        private static string dxf_color (CellStyle[] dxfs, string id, bool fill) {
            int i = int.parse (id);
            if (id == "" || i < 0 || i >= dxfs.length) return "";
            return fill ? dxfs[i].fill : dxfs[i].color;
        }

        public static void read_filter (Workbook book, Sheet sh, Xml.Node* af, CellStyle[] dxfs) {
            var f = sh.filter;
            foreach (Xml.Node* fc in kids (af, "filterColumn")) {
                int col = f.area.c1 + int.parse (attr (fc, "colId", "0"));
                var filters = child (fc, "filters");
                if (filters != null) {
                    var shown = new Gee.HashSet<string> ();
                    foreach (Xml.Node* fl in kids (filters, "filter")) shown.add (attr (fl, "val"));
                    bool blank = flag (filters, "blank", false);
                    var rule = new FilterRule ();
                    rule.blanks = blank;
                    foreach (Xml.Node* dg in kids (filters, "dateGroupItem")) {
                        string g = attr (dg, "dateTimeGrouping", "day");
                        string key = attr (dg, "year");
                        if (g != "year") key += "-%02d".printf (int.parse (attr (dg, "month", "1")));
                        if (g != "year" && g != "month") key += "-%02d".printf (int.parse (attr (dg, "day", "1")));
                        rule.dates.add (key);
                    }
                    var hidden = new Gee.HashSet<string> ();
                    for (int r = f.area.r1 + 1; r <= f.area.r2; r++) {
                        string color;
                        var v = sh.value_at (r, col);
                        if (rule.dates.size > 0 && v.kind == ValueKind.NUMBER && NumberFormat.is_date_format (sh.style_at (r, col).number_format)) continue;
                        string t = NumberFormat.format_value (v, sh.style_at (r, col).number_format, out color, book.date1904);
                        if (t == "" ? !blank : !shown.contains (t)) hidden.add (t);
                    }
                    f.hidden_values[col] = hidden;
                    if (rule.dates.size > 0) f.rules[col] = rule;
                    continue;
                }
                var rule = new FilterRule ();
                var cfs = child (fc, "customFilters");
                var top = child (fc, "top10");
                var dyn = child (fc, "dynamicFilter");
                var colf = child (fc, "colorFilter");
                var icon = child (fc, "iconFilter");
                if (cfs != null) {
                    rule.kind = FilterKind.CUSTOM;
                    rule.and_join = flag (cfs, "and", false);
                    var list = kids (cfs, "customFilter");
                    if (list.size > 0) op_from_xlsx (attr (list[0], "operator"), attr (list[0], "val"), out rule.op1, out rule.v1);
                    if (list.size > 1) op_from_xlsx (attr (list[1], "operator"), attr (list[1], "val"), out rule.op2, out rule.v2);
                } else if (top != null) {
                    rule.kind = FilterKind.TOP10;
                    rule.bottom = !flag (top, "top", true);
                    rule.percent = flag (top, "percent", false);
                    rule.top = double.parse (attr (top, "val", "10"));
                } else if (dyn != null) {
                    rule.kind = FilterKind.DYNAMIC;
                    rule.dyn_type = attr (dyn, "type");
                } else if (colf != null) {
                    bool fill = flag (colf, "cellColor", true);
                    rule.kind = fill ? FilterKind.CELL_COLOR : FilterKind.FONT_COLOR;
                    rule.color = dxf_color (dxfs, attr (colf, "dxfId"), fill);
                } else if (icon != null) {
                    rule.kind = FilterKind.ICON;
                    rule.icon_set = attr (icon, "iconSet");
                    rule.icon = int.parse (attr (icon, "iconId", "0"));
                } else {
                    continue;
                }
                f.rules[col] = rule;
            }
        }

        public static void read_sort_state (Workbook book, Sheet sh, Xml.Node* ss, CellStyle[] dxfs) {
            if (ss == null) return;
            var body = Area.parse (attr (ss, "ref"), sh);
            if (body == null) return;
            bool columns = flag (ss, "columnSort", false);
            var spec = new SortSpec (body);
            spec.header = false;
            spec.columns = columns;
            spec.case_sensitive = flag (ss, "caseSensitive", false);
            foreach (Xml.Node* sc in kids (ss, "sortCondition")) {
                var key = Area.parse (attr (sc, "ref"), sh);
                if (key == null) continue;
                var lv = new SortLevel (columns ? key.r1 : key.c1, !flag (sc, "descending", false));
                switch (attr (sc, "sortBy")) {
                    case "cellColor": lv.by = SortBy.CELL_COLOR; lv.color = dxf_color (dxfs, attr (sc, "dxfId"), true); break;
                    case "fontColor": lv.by = SortBy.FONT_COLOR; lv.color = dxf_color (dxfs, attr (sc, "dxfId"), false); break;
                    case "icon": lv.by = SortBy.ICON; lv.icon_set = attr (sc, "iconSet"); lv.icon = int.parse (attr (sc, "iconId", "0")); break;
                }
                string cl = attr (sc, "customList");
                if (cl != "") lv.custom_list = cl.replace (",", "|");
                spec.levels.add (lv);
            }
            sh.sort_state = spec;
        }

        public const string LISTS_NAME = "_ssCustomLists";

        public static void write_workbook (XlsxWriter w) {
            if (w.book.custom_lists.size > 0) w.add_defined_name (LISTS_NAME, -1, "\"" + CustomLists.encode (w.book.custom_lists) + "\"", true);
            string p = workbook_protection (w.book);
            if (p != "") w.put_workbook ("workbookProtection", p);
            var names = new Gee.ArrayList<string> ();
            var active = new Gee.HashMap<string, int> ();
            for (int i = 0; i < w.book.sheets.size; i++) {
                foreach (var v in w.book.sheets[i].views) {
                    if (!names.contains (v.name)) {
                        names.add (v.name);
                        active[v.name] = i + 1;
                    }
                }
            }
            if (names.size == 0) return;
            var sb = new StringBuilder ("<customWorkbookViews>");
            foreach (string n in names) sb.append ("<customWorkbookView name=\"%s\" guid=\"%s\" windowWidth=\"1240\" windowHeight=\"820\" activeSheetId=\"%d\"/>".printf (esc (n), view_guid (n), active[n]));
            sb.append ("</customWorkbookViews>");
            w.put_workbook ("customWorkbookViews", sb.str);
        }

        private static string int_list (Gee.Collection<int> items) {
            var sorted = new Gee.ArrayList<int> ();
            sorted.add_all (items);
            sorted.sort ((a, b) => a - b);
            string[] parts = {};
            foreach (int i in sorted) parts += i.to_string ();
            return string.joinv (" ", parts);
        }

        public static string custom_views (Sheet s) {
            if (s.views.size == 0) return "";
            var sb = new StringBuilder ("<customSheetViews>");
            foreach (var v in s.views) {
                sb.append ("<customSheetView guid=\"%s\" scale=\"%d\"".printf (view_guid (v.name), (int) Math.round (v.zoom * 100)));
                if (v.hidden_rows.size > 0) sb.append (" hiddenRows=\"1\"");
                if (v.hidden_cols.size > 0) sb.append (" hiddenColumns=\"1\"");
                if (v.filter != null) sb.append (" filter=\"1\" showAutoFilter=\"1\"");
                sb.append (" topLeftCell=\"%s\">".printf (Address.cell (v.freeze_rows, v.freeze_cols)));
                if (v.freeze_rows > 0 || v.freeze_cols > 0) {
                    string pane = v.freeze_rows > 0 && v.freeze_cols > 0 ? "bottomRight" : (v.freeze_rows > 0 ? "bottomLeft" : "topRight");
                    sb.append ("<pane%s%s topLeftCell=\"%s\" activePane=\"%s\" state=\"frozen\"/>".printf (
                        v.freeze_cols > 0 ? " xSplit=\"%d\"".printf (v.freeze_cols) : "", v.freeze_rows > 0 ? " ySplit=\"%d\"".printf (v.freeze_rows) : "",
                        Address.cell (v.freeze_rows, v.freeze_cols), pane));
                }
                string cellref = Address.cell (v.row, v.col);
                sb.append ("<selection activeCell=\"%s\" sqref=\"%s\"/>".printf (cellref, cellref));
                if (v.row_breaks.size > 0) {
                    sb.append ("<rowBreaks count=\"%d\" manualBreakCount=\"%d\">".printf (v.row_breaks.size, v.row_breaks.size));
                    foreach (int b in v.row_breaks) sb.append ("<brk id=\"%d\" max=\"16383\" man=\"1\"/>".printf (b));
                    sb.append ("</rowBreaks>");
                }
                if (v.filter != null) sb.append ("<autoFilter ref=\"%s\"/>".printf (area_ref (v.filter.area)));
                sb.append ("<extLst><ext uri=\"%s\" xmlns:ss=\"urn:singularity:spreadsheet\"><ss:view name=\"%s\" hiddenRows=\"%s\" hiddenCols=\"%s\"/></ext></extLst>".printf (
                    VIEW_EXT, esc (v.name), int_list (v.hidden_rows), int_list (v.hidden_cols)));
                sb.append ("</customSheetView>");
            }
            sb.append ("</customSheetViews>");
            return sb.str;
        }

        private static Gee.HashMap<string, string>? view_names;

        private static void read_int_list (string text, Gee.Collection<int> into) {
            foreach (string p in text.split (" ")) if (p.strip () != "") into.add (int.parse (p));
        }

        public static void read_views (Sheet sh, Xml.Node* root) {
            foreach (Xml.Node* cv in kids (child (root, "customSheetViews"), "customSheetView")) {
                string guid = attr (cv, "guid").up ();
                string name = view_names != null && view_names.has_key (guid) ? view_names[guid] : guid;
                var v = new CustomView (name);
                v.zoom = double.parse (attr (cv, "scale", "100")) / 100.0;
                var pane = child (cv, "pane");
                if (pane != null && attr (pane, "state").has_prefix ("frozen")) {
                    v.freeze_cols = (int) double.parse (attr (pane, "xSplit", "0"));
                    v.freeze_rows = (int) double.parse (attr (pane, "ySplit", "0"));
                }
                var sel = child (cv, "selection");
                if (sel != null) {
                    bool a, b;
                    int r, c;
                    if (Address.parse_cell (attr (sel, "activeCell"), out r, out c, out a, out b)) {
                        v.row = r;
                        v.col = c;
                    }
                }
                foreach (Xml.Node* brk in kids (child (cv, "rowBreaks"), "brk")) v.row_breaks.add (int.parse (attr (brk, "id")));
                var af = child (cv, "autoFilter");
                if (af != null) {
                    var ar = Area.parse (attr (af, "ref"), sh);
                    if (ar != null) v.filter = new Filter (ar);
                }
                foreach (Xml.Node* e in kids (child (cv, "extLst"), "ext")) {
                    if (attr (e, "uri") != VIEW_EXT) continue;
                    foreach (Xml.Node* sv in kids (e, "view")) {
                        if (attr (sv, "name") != "") v.name = attr (sv, "name");
                        read_int_list (attr (sv, "hiddenRows"), v.hidden_rows);
                        read_int_list (attr (sv, "hiddenCols"), v.hidden_cols);
                    }
                }
                sh.views.add (v);
            }
        }

        private static void add_attr (Gee.HashMap<int, string> map, int k, string v) {
            if (v == "") return;
            map[k] = (map.has_key (k) ? map[k] : "") + v;
        }

        public static void write_sheet (XlsxSheetPart part) {
            var s = part.sheet;
            string prot = sheet_protection (s);
            if (prot != "") part.put ("sheetProtection", prot);
            string dv = data_validations (s);
            if (dv != "") part.put ("dataValidations", dv);
            string cv = custom_views (s);
            if (cv != "") part.put ("customSheetViews", cv);
            part.sheet_pr.append (sheet_pr_inner (s));
            part.format_pr_attrs.append (format_pr_attrs (s));
            var rows = new Gee.HashSet<int> ();
            rows.add_all (s.outline.row_levels.keys);
            rows.add_all (s.outline.collapsed_rows);
            foreach (int r in rows) add_attr (part.row_attrs, r, row_attrs (s, r));
            var cols = new Gee.HashSet<int> ();
            cols.add_all (s.outline.col_levels.keys);
            cols.add_all (s.outline.collapsed_cols);
            foreach (int c in cols) add_attr (part.col_attrs, c, col_attrs (s, c));
        }

        private static string area_ref (Area a) {
            if (a.is_single ()) return Address.cell (a.r1, a.c1);
            return Address.cell (a.r1, a.c1) + ":" + Address.cell (a.r2, a.c2);
        }

        public static string sheet_protection (Sheet s) {
            var p = s.protection;
            if (p == null) return "";
            var sb = new StringBuilder ("<sheetProtection");
            sb.append (write_hash (p.password, ""));
            sb.append (" sheet=\"1\"");
            if (!p.objects) sb.append (" objects=\"1\"");
            if (!p.scenarios) sb.append (" scenarios=\"1\"");
            if (p.format_cells) sb.append (" formatCells=\"0\"");
            if (p.format_columns) sb.append (" formatColumns=\"0\"");
            if (p.format_rows) sb.append (" formatRows=\"0\"");
            if (p.insert_columns) sb.append (" insertColumns=\"0\"");
            if (p.insert_rows) sb.append (" insertRows=\"0\"");
            if (p.insert_hyperlinks) sb.append (" insertHyperlinks=\"0\"");
            if (p.delete_columns) sb.append (" deleteColumns=\"0\"");
            if (p.delete_rows) sb.append (" deleteRows=\"0\"");
            if (!p.select_locked) sb.append (" selectLockedCells=\"1\"");
            if (!p.select_unlocked) sb.append (" selectUnlockedCells=\"1\"");
            if (p.sort) sb.append (" sort=\"0\"");
            if (p.autofilter) sb.append (" autoFilter=\"0\"");
            if (p.pivot_tables) sb.append (" pivotTables=\"0\"");
            sb.append ("/>");
            if (p.ranges.size > 0) {
                sb.append ("<protectedRanges>");
                foreach (var er in p.ranges) {
                    sb.append ("<protectedRange%s sqref=\"%s\" name=\"%s\"/>".printf (write_hash (er.password, ""), area_ref (er.area), esc (er.title)));
                }
                sb.append ("</protectedRanges>");
            }
            return sb.str;
        }

        public static string data_validations (Sheet s) {
            if (s.validations.size == 0) return "";
            var sb = new StringBuilder ("<dataValidations count=\"%d\">".printf (s.validations.size));
            foreach (var v in s.validations) {
                sb.append ("<dataValidation type=\"%s\"".printf (v.kind.xlsx_name ()));
                if (v.alert != ValidationAlert.STOP) sb.append (" errorStyle=\"%s\"".printf (v.alert.xlsx_name ()));
                bool uses_op = v.kind != ValidationKind.LIST && v.kind != ValidationKind.CUSTOM && v.kind != ValidationKind.ANY;
                if (uses_op && v.op != ValidationOp.BETWEEN) sb.append (" operator=\"%s\"".printf (v.op.xlsx_name ()));
                if (v.allow_blank) sb.append (" allowBlank=\"1\"");
                if (v.kind == ValidationKind.LIST && !v.dropdown) sb.append (" showDropDown=\"1\"");
                if (v.show_input) sb.append (" showInputMessage=\"1\"");
                if (v.show_error) sb.append (" showErrorMessage=\"1\"");
                if (v.error_title != "") sb.append (" errorTitle=\"%s\"".printf (esc (v.error_title)));
                if (v.error_message != "") sb.append (" error=\"%s\"".printf (esc (v.error_message)));
                if (v.input_title != "") sb.append (" promptTitle=\"%s\"".printf (esc (v.input_title)));
                if (v.message != "") sb.append (" prompt=\"%s\"".printf (esc (v.message)));
                sb.append (" sqref=\"%s\">".printf (area_ref (v.area)));
                string f1 = v.kind == ValidationKind.LIST && v.list_source != "" ? v.list_source : v.formula1;
                if (f1.has_prefix ("=")) f1 = f1.substring (1);
                string f2 = v.formula2.has_prefix ("=") ? v.formula2.substring (1) : v.formula2;
                if (v.kind != ValidationKind.ANY && f1 != "") sb.append ("<formula1>%s</formula1>".printf (esc (f1)));
                if (uses_op && v.op.two_values () && f2 != "") sb.append ("<formula2>%s</formula2>".printf (esc (f2)));
                sb.append ("</dataValidation>");
            }
            sb.append ("</dataValidations>");
            return sb.str;
        }
    }
}
