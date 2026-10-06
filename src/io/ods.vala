namespace Singularity.Apps.Spreadsheet {

    public class OdsOut {
        public Workbook book;
        public bool flat;
        public StringBuilder auto_styles = new StringBuilder ();
        public StringBuilder common_styles = new StringBuilder ();
        public StringBuilder styles_auto = new StringBuilder ();
        public StringBuilder master_styles = new StringBuilder ();
        public StringBuilder before_tables = new StringBuilder ();
        public StringBuilder after_tables = new StringBuilder ();
        public StringBuilder settings_view = new StringBuilder ();
        public StringBuilder manifest = new StringBuilder ();
        public Gee.HashMap<Sheet, string> table_attrs = new Gee.HashMap<Sheet, string> ();
        public Gee.HashMap<Sheet, string> table_start = new Gee.HashMap<Sheet, string> ();
        public Gee.HashMap<Sheet, string> table_end = new Gee.HashMap<Sheet, string> ();
        public Gee.HashMap<Sheet, string> table_settings = new Gee.HashMap<Sheet, string> ();
        public Gee.HashMap<string, string> cell_attrs = new Gee.HashMap<string, string> ();
        public Gee.HashMap<string, string> cell_children = new Gee.HashMap<string, string> ();
        public Gee.HashMap<string, Bytes> files = new Gee.HashMap<string, Bytes> ();
        private int counter = 0;

        public OdsOut (Workbook book) {
            this.book = book;
        }

        public int next () {
            return ++counter;
        }

        private static void append (Gee.HashMap<Sheet, string> map, Sheet s, string xml) {
            map[s] = (map.has_key (s) ? map[s] : "") + xml;
        }

        public void put_table_attr (Sheet s, string xml) {
            append (table_attrs, s, xml);
        }

        public void put_table_start (Sheet s, string xml) {
            append (table_start, s, xml);
        }

        public void put_table_end (Sheet s, string xml) {
            append (table_end, s, xml);
        }

        public void put_table_setting (Sheet s, string xml) {
            append (table_settings, s, xml);
        }

        public string get_slot (Gee.HashMap<Sheet, string> map, Sheet s) {
            return map.has_key (s) ? map[s] : "";
        }

        public static string cell_key (Sheet s, int r, int c) {
            return "%p:%d:%d".printf (s, r, c);
        }

        public void put_cell_attr (Sheet s, int r, int c, string xml) {
            string k = cell_key (s, r, c);
            cell_attrs[k] = (cell_attrs.has_key (k) ? cell_attrs[k] : "") + xml;
        }

        public void put_cell_child (Sheet s, int r, int c, string xml) {
            string k = cell_key (s, r, c);
            cell_children[k] = (cell_children.has_key (k) ? cell_children[k] : "") + xml;
        }

        public void add_file (string path, Bytes data, string media_type) {
            files[path] = data;
            manifest.append ("<manifest:file-entry manifest:full-path=\"%s\" manifest:media-type=\"%s\"/>".printf (XlsxWriter.esc (path), media_type));
        }
    }

    public class OdsIn {
        public Workbook book;
        public ZipReader? zip;
        public Xml.Node* content;
        public Xml.Node* styles;
        public Xml.Node* settings;
        public Xml.Node* meta;
        public Gee.ArrayList<Xml.Node*> tables = new Gee.ArrayList<Xml.Node*> ();
        public Gee.HashMap<string, Xml.Node*> style_nodes = new Gee.HashMap<string, Xml.Node*> ();
    }

    public class Ods {
        public const string NS_TABLE = "urn:oasis:names:tc:opendocument:xmlns:table:1.0";
        public const string NS_OFFICE = "urn:oasis:names:tc:opendocument:xmlns:office:1.0";
        public const string NS_TEXT = "urn:oasis:names:tc:opendocument:xmlns:text:1.0";
        public const string NS_STYLE = "urn:oasis:names:tc:opendocument:xmlns:style:1.0";
        public const string NS_FO = "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0";
        public const string NS_XLINK = "http://www.w3.org/1999/xlink";
        public const string NS_DC = "http://purl.org/dc/elements/1.1/";
        public const string NS_META = "urn:oasis:names:tc:opendocument:xmlns:meta:1.0";
        public const string NS_NUMBER = "urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0";
        public const string NS_CONFIG = "urn:oasis:names:tc:opendocument:xmlns:config:1.0";
        public const string NS_CALCEXT = "urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0";
        public const string NS_TABLEOOO = "http://openoffice.org/2009/table";
        public const string NAMESPACES = "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:meta=\"urn:oasis:names:tc:opendocument:xmlns:meta:1.0\" xmlns:number=\"urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0\" xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\" xmlns:chart=\"urn:oasis:names:tc:opendocument:xmlns:chart:1.0\" xmlns:config=\"urn:oasis:names:tc:opendocument:xmlns:config:1.0\" xmlns:of=\"urn:oasis:names:tc:opendocument:xmlns:of:1.2\" xmlns:calcext=\"urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0\" xmlns:loext=\"urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0\" xmlns:tableooo=\"http://openoffice.org/2009/table\" xmlns:ss=\"urn:singularity:spreadsheet\"";

        private const string[] MS_ONLY = {
            "XLOOKUP", "XMATCH", "IFS", "SWITCH", "TEXTJOIN", "CONCAT", "MAXIFS", "MINIFS", "LET", "LAMBDA",
            "FILTER", "SORT", "SORTBY", "UNIQUE", "SEQUENCE", "RANDARRAY", "TEXTBEFORE", "TEXTAFTER", "TEXTSPLIT",
            "VSTACK", "HSTACK", "TAKE", "DROP", "CHOOSEROWS", "CHOOSECOLS", "TOCOL", "TOROW", "WRAPROWS", "WRAPCOLS",
            "EXPAND", "MAP", "REDUCE", "SCAN", "BYROW", "BYCOL", "MAKEARRAY", "ISOMITTED", "FORECAST.LINEAR",
            "STDEV.S", "STDEV.P", "VAR.S", "VAR.P", "MODE.SNGL", "PERCENTILE.INC", "PERCENTILE.EXC", "QUARTILE.INC",
            "QUARTILE.EXC", "RANK.EQ", "RANK.AVG", "NORM.DIST", "NORM.S.DIST", "NORM.INV", "NORM.S.INV", "BINOM.DIST",
            "POISSON.DIST", "EXPON.DIST", "CONFIDENCE.NORM", "COVARIANCE.P", "COVARIANCE.S", "CEILING.MATH",
            "FLOOR.MATH", "CEILING.PRECISE", "FLOOR.PRECISE", "AGGREGATE", "PERCENTRANK.INC", "NETWORKDAYS.INTL",
            "WORKDAY.INTL", "REGEXTEST", "REGEXEXTRACT", "REGEXREPLACE", "GROUPBY", "PIVOTBY"
        };

        public static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        public static string attr (Xml.Node* n, string name, string ns) {
            if (n == null) return "";
            string? v = n->get_ns_prop (name, ns);
            return v ?? "";
        }

        public static Xml.Node* child (Xml.Node* n, string name) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        public static string from_of (string f) {
            string s = f;
            if (s.has_prefix ("of:")) s = s.substring (3);
            else if (s.has_prefix ("msoxl:")) s = s.substring (6);
            else if (s.has_prefix ("oooc:")) s = s.substring (5);
            if (!s.has_prefix ("=")) s = "=" + s;
            var sb = new StringBuilder ();
            bool q = false;
            int brace = 0;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c == '"') q = !q;
                if (!q && c == '{') brace++;
                if (!q && c == '}') brace--;
                if (!q && brace > 0 && c == ';') {
                    sb.append_c (',');
                    continue;
                }
                if (!q && brace > 0 && c == '|') {
                    sb.append_c (';');
                    continue;
                }
                if (!q && c == '[') {
                    int close = s.index_of_char (']', i);
                    if (close < 0) {
                        sb.append_c (c);
                        continue;
                    }
                    string inner = s.substring (i + 1, close - i - 1);
                    var parts = split_range (inner);
                    string[] conv = {};
                    string sheet1 = "", sheet2 = "";
                    foreach (string p in parts) {
                        string x = p;
                        int dot = last_dot (x);
                        string sh = dot > 0 ? x.substring (0, dot) : "";
                        string cell = dot >= 0 ? x.substring (dot + 1) : x;
                        if (sh.has_prefix ("$")) sh = sh.substring (1);
                        if (sh.has_prefix ("'")) sh = sh.substring (1, sh.length - 2).replace ("''", "'");
                        if (sh != "") {
                            if (sheet1 == "") sheet1 = sh;
                            else if (sh != sheet1) sheet2 = sh;
                        }
                        conv += cell;
                    }
                    if (sheet1 != "" && sheet2 != "") {
                        string both = sheet1 + ":" + sheet2;
                        bool plain = Address.quote_sheet (sheet1) == sheet1 && Address.quote_sheet (sheet2) == sheet2;
                        sb.append (plain ? both + "!" : "'" + both.replace ("'", "''") + "'!");
                    } else if (sheet1 != "") {
                        sb.append (Address.quote_sheet (sheet1) + "!");
                    }
                    sb.append (string.joinv (":", conv));
                    i = close;
                    continue;
                }
                if (!q && c.isalpha ()) {
                    int j = i;
                    while (j < s.length && (s[j].isalnum () || s[j] == '.' || s[j] == '_')) j++;
                    string word = s.substring (i, j - i);
                    string up = word.up ();
                    if (j < s.length && s[j] == '(') {
                        foreach (string pre in new string[] { "COM.MICROSOFT.", "ORG.OPENOFFICE.", "ORG.LIBREOFFICE.", "_XLFN." }) {
                            if (up.has_prefix (pre)) {
                                word = word.substring (pre.length);
                                break;
                            }
                        }
                    }
                    sb.append (word);
                    i = j - 1;
                    continue;
                }
                sb.append_c (c);
            }
            return sb.str;
        }

        private static int last_dot (string x) {
            bool q = false;
            int last = -1;
            for (int i = 0; i < x.length; i++) {
                if (x[i] == '\'') q = !q;
                else if (x[i] == '.' && !q) last = i;
            }
            return last;
        }

        private static string[] split_range (string inner) {
            string[] parts = {};
            bool q = false;
            int start = 0;
            for (int i = 0; i < inner.length; i++) {
                if (inner[i] == '\'') q = !q;
                else if (inner[i] == ':' && !q) {
                    parts += inner.substring (start, i - start);
                    start = i + 1;
                }
            }
            parts += inner.substring (start);
            return parts;
        }

        public static string to_of (Node n, Sheet own, int row = -1, int col = -1) {
            return "of:=" + render_of (n, own, row, col);
        }

        private static string of_sheet (string name) {
            bool plain = true;
            for (int i = 0; i < name.length; i++) {
                char c = name[i];
                if (!(c.isalnum () || c == '_' || (uchar) c >= 0x80)) plain = false;
            }
            if (name.length > 0 && name[0].isdigit ()) plain = false;
            return plain ? name : "'" + name.replace ("'", "''") + "'";
        }

        public static string range_address (Area a, bool abs = true) {
            string sh = a.sheet != null ? "$" + of_sheet (a.sheet.name) : "";
            string c1 = Address.cell (a.r1, a.c1, abs, abs);
            if (a.is_single ()) return sh + "." + c1;
            return sh + "." + c1 + ":" + sh + "." + Address.cell (a.r2, a.c2, abs, abs);
        }

        public static string plain_range (Area a) {
            string sh = a.sheet != null ? of_sheet (a.sheet.name) : "";
            if (a.is_single ()) return sh + "." + Address.cell (a.r1, a.c1);
            return sh + "." + Address.cell (a.r1, a.c1) + ":" + sh + "." + Address.cell (a.r2, a.c2);
        }

        private static string render_of (Node n, Sheet own, int row, int col) {
            switch (n.kind) {
                case NodeKind.STRUCT:
                    Area? ta = own.book != null ? Tables.resolve (own.book, n.sref, own, int.max (row, 0), int.max (col, 0)) : null;
                    if (ta == null) return "[.#REF!]";
                    return "[" + range_address (ta) + "]";
                case NodeKind.VALUE:
                    return n.value != null ? Formula.literal_text (n.value) : "";
                case NodeKind.APPLY:
                    string[] aparts = {};
                    for (int i = 1; i < n.args.length; i++) aparts += render_of (n.args[i], own, row, col);
                    return render_of (n.args[0], own, row, col) + "(" + string.joinv (";", aparts) + ")";
                case NodeKind.REF:
                    if (n.a == null || n.bad_sheet) return "[.#REF!]";
                    if (n.spill && own.book != null) {
                        var target = n.sheet ?? own;
                        var sa = own.book.spill_area (target, n.a.row, n.a.col);
                        if (sa != null) return "[" + range_address (new Area (target, sa.r1, sa.c1, sa.r2, sa.c2), false) + "]";
                    }
                    string sheet = n.sheet != null && (n.sheet != own || n.is_3d ()) ? "$" + of_sheet (n.sheet.name) : "";
                    string sheet2 = sheet;
                    if (n.is_3d () && n.sheet2 != null) sheet2 = "$" + of_sheet (n.sheet2.name);
                    string a = Address.cell (n.a.row, n.a.col, n.a.abs_row, n.a.abs_col);
                    if (n.b == null && !n.is_3d ()) return "[" + sheet + "." + a + "]";
                    string b = n.b != null ? Address.cell (n.b.row, n.b.col, n.b.abs_row, n.b.abs_col) : a;
                    return "[" + sheet + "." + a + ":" + sheet2 + "." + b + "]";
                case NodeKind.CALL:
                    string[] parts = {};
                    foreach (var c in n.args) parts += render_of (c, own, row, col);
                    string name = n.text;
                    foreach (string m in MS_ONLY) {
                        if (m == name) {
                            name = "COM.MICROSOFT." + name;
                            break;
                        }
                    }
                    return name + "(" + string.joinv (";", parts) + ")";
                case NodeKind.BINARY:
                    if (n.op == ":") return render_of (n.args[0], own, row, col) + ":" + render_of (n.args[1], own, row, col);
                    return "(" + render_of (n.args[0], own, row, col) + n.op + render_of (n.args[1], own, row, col) + ")";
                case NodeKind.UNARY:
                    if (n.op == "@") return render_of (n.args[0], own, row, col);
                    return "-" + render_of (n.args[0], own, row, col);
                case NodeKind.PERCENT:
                    return render_of (n.args[0], own, row, col) + "%";
                case NodeKind.ARRAY:
                    var sb = new StringBuilder ("{");
                    for (int i = 0; i < n.array.length[0]; i++) {
                        if (i > 0) sb.append ("|");
                        for (int j = 0; j < n.array.length[1]; j++) {
                            if (j > 0) sb.append (";");
                            sb.append (Formula.literal_text (n.array[i, j]));
                        }
                    }
                    sb.append ("}");
                    return sb.str;
                default:
                    return Formula.render (n, own, 0);
            }
        }

        public static bool is_ods_path (string path) {
            string p = path.down ();
            return p.has_suffix (".ods") || p.has_suffix (".ots") || p.has_suffix (".fods");
        }

        public static Workbook load (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            return load_data (data, path.down ().has_suffix (".fods"));
        }

        private static Xml.Doc* parse_text (string? text) {
            if (text == null) return null;
            return Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.HUGE);
        }

        public static Workbook load_data (uint8[] data, bool flat) throws Error {
            var inp = new OdsIn ();
            inp.book = new Workbook ();
            Xml.Doc*[] docs = {};
            bool is_flat = flat || (data.length > 5 && data[0] == '<');
            if (is_flat) {
                string text = (string) data;
                var doc = parse_text (text.substring (0, int.min (text.length, data.length)));
                if (doc == null) throw new ZipError.FORMAT ("bad flat document");
                docs += doc;
                var root = doc->get_root_element ();
                inp.content = root;
                inp.styles = root;
                inp.settings = child (root, "settings");
                inp.meta = child (root, "meta");
            } else {
                inp.zip = new ZipReader (data);
                var content = parse_text (inp.zip.read_text ("content.xml"));
                if (content == null) throw new ZipError.FORMAT ("missing content.xml");
                docs += content;
                inp.content = content->get_root_element ();
                var styles = parse_text (inp.zip.read_text ("styles.xml"));
                if (styles != null) {
                    docs += styles;
                    inp.styles = styles->get_root_element ();
                }
                var settings = parse_text (inp.zip.read_text ("settings.xml"));
                if (settings != null) {
                    docs += settings;
                    inp.settings = child (settings->get_root_element (), "settings");
                }
                var meta = parse_text (inp.zip.read_text ("meta.xml"));
                if (meta != null) {
                    docs += meta;
                    inp.meta = child (meta->get_root_element (), "meta");
                }
            }
            var reader = new OdsReader (inp);
            reader.run ();
            foreach (var d in docs) delete d;
            if (inp.book.sheets.size == 0) inp.book.add_sheet ();
            inp.book.recalculate ();
            return inp.book;
        }

        public static void save (Workbook book, string path) throws Error {
            string p = path.down ();
            var w = new OdsWriter (book);
            if (p.has_suffix (".fods")) {
                FileUtils.set_contents (path, w.flat ());
                return;
            }
            FileUtils.set_data (path, w.package (p.has_suffix (".ots")));
        }
    }

    public class OdsReader {
        private OdsIn inp;
        private Workbook book;
        private Gee.HashMap<string, Xml.Node*> styles = new Gee.HashMap<string, Xml.Node*> ();
        private Gee.HashMap<string, Xml.Node*> data_styles = new Gee.HashMap<string, Xml.Node*> ();
        private Gee.HashMap<string, int> style_cache = new Gee.HashMap<string, int> ();
        private Gee.HashMap<string, string> fonts = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, Validation> validations = new Gee.HashMap<string, Validation> ();
        private Gee.HashMap<string, Gee.ArrayList<Area>> validation_cells = new Gee.HashMap<string, Gee.ArrayList<Area>> ();

        public OdsReader (OdsIn inp) {
            this.inp = inp;
            this.book = inp.book;
        }

        private static string attr (Xml.Node* n, string name, string ns) {
            return Ods.attr (n, name, ns);
        }

        private static Gee.ArrayList<Xml.Node*> kids (Xml.Node* n) {
            var l = new Gee.ArrayList<Xml.Node*> ();
            for (Xml.Node* c = n != null ? n->children : null; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE) l.add (c);
            }
            return l;
        }

        private void index_styles (Xml.Node* container) {
            foreach (Xml.Node* s in kids (container)) {
                string name = attr (s, "name", Ods.NS_STYLE);
                if (name == "") continue;
                if (s->name == "style") {
                    string fam = attr (s, "family", Ods.NS_STYLE);
                    styles[fam + ":" + name] = s;
                } else if (s->name.has_suffix ("-style")) {
                    data_styles[name] = s;
                }
            }
        }

        private void index_fonts (Xml.Node* root) {
            foreach (Xml.Node* f in kids (Ods.child (root, "font-face-decls"))) {
                string fam = attr (f, "font-family", "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0").replace ("'", "");
                fonts[attr (f, "name", Ods.NS_STYLE)] = fam != "" ? fam : attr (f, "name", Ods.NS_STYLE);
            }
        }

        public void run () {
            if (inp.styles != null) {
                index_fonts (inp.styles);
                index_styles (Ods.child (inp.styles, "styles"));
                index_styles (Ods.child (inp.styles, "automatic-styles"));
            }
            index_fonts (inp.content);
            index_styles (Ods.child (inp.content, "automatic-styles"));
            inp.style_nodes = styles;
            read_meta ();
            var body = Ods.child (inp.content, "body");
            var ss = Ods.child (body, "spreadsheet");
            if (ss == null) return;
            foreach (Xml.Node* n in kids (ss)) {
                if (n->name == "table") inp.tables.add (n);
            }
            foreach (Xml.Node* t in inp.tables) book.add_sheet (attr (t, "name", Ods.NS_TABLE));
            read_validations (Ods.child (ss, "content-validations"));
            var calc = Ods.child (ss, "calculation-settings");
            if (calc != null) {
                var it = Ods.child (calc, "iteration");
                if (it != null) {
                    book.iterative = attr (it, "status", Ods.NS_TABLE) == "enable";
                    string steps = attr (it, "steps", Ods.NS_TABLE);
                    if (steps != "") book.max_iterations = int.max (1, int.parse (steps));
                    string md = attr (it, "minimum-difference", Ods.NS_TABLE);
                    if (md != "") book.max_change = double.parse (md);
                }
                var nd = Ods.child (calc, "null-date");
                if (nd != null && attr (nd, "date-value", Ods.NS_TABLE).has_prefix ("1904")) book.date1904 = true;
            }
            for (int i = 0; i < inp.tables.size; i++) read_table (book.sheets[i], inp.tables[i]);
            read_names (Ods.child (ss, "named-expressions"), null);
            read_database_ranges (Ods.child (ss, "database-ranges"));
            for (int i = 0; i < inp.tables.size; i++) read_names (Ods.child (inp.tables[i], "named-expressions"), book.sheets[i]);
            foreach (var e in validation_cells.entries) {
                var v = validations[e.key];
                if (v == null) continue;
                foreach (var a in e.value) book.sheets.contains (a.sheet);
                foreach (var a in merge_areas (e.value)) a.sheet.validations.add (v.copy_to (a));
            }
            read_settings ();
            OdsExtras.read (inp);
        }

        private static Gee.ArrayList<Area> merge_areas (Gee.ArrayList<Area> cells) {
            var rows = new Gee.ArrayList<Area> ();
            cells.sort ((a, b) => a.c1 != b.c1 ? a.c1 - b.c1 : a.r1 - b.r1);
            foreach (var a in cells) {
                if (rows.size > 0) {
                    var last = rows[rows.size - 1];
                    if (last.sheet == a.sheet && last.c1 == a.c1 && last.c2 == a.c2 && last.r2 + 1 == a.r1) {
                        rows[rows.size - 1] = new Area (a.sheet, last.r1, last.c1, a.r2, last.c2);
                        continue;
                    }
                }
                rows.add (a);
            }
            return rows;
        }

        private void read_database_ranges (Xml.Node* container) {
            foreach (Xml.Node* d in kids (container)) {
                if (d->name != "database-range") continue;
                var area = parse_range (book, attr (d, "target-range-address", Ods.NS_TABLE));
                if (area == null || area.sheet == null) continue;
                string name = attr (d, "name", Ods.NS_TABLE);
                bool buttons = attr (d, "display-filter-buttons", Ods.NS_TABLE) == "true";
                if (name.has_prefix ("__Anonymous_Sheet_DB__") || name == "") {
                    if (buttons) area.sheet.filter = new Filter (area);
                    EditOds.read_filter (book, area.sheet, d);
                    continue;
                }
                var t = new TableDef (name, area.sheet, area);
                t.header_row = attr (d, "contains-header", Ods.NS_TABLE) != "false";
                t.totals_row = attr (d, "contains-footer", Ods.NS_TABLE) == "true";
                t.filter_button = buttons;
                t.sync_columns ();
                book.tables.add (t);
                if (buttons) area.sheet.filter = new Filter (area);
            }
        }

        private void read_meta () {
            if (inp.meta == null) return;
            foreach (Xml.Node* n in kids (inp.meta)) {
                string v = (n->get_content () ?? "").strip ();
                if (v == "") continue;
                switch (n->name) {
                    case "title": case "subject": case "description": book.properties[n->name] = v; break;
                    case "initial-creator": book.properties["creator"] = v; break;
                    case "keyword": book.properties["keywords"] = v; break;
                    case "creation-date": book.properties["created"] = v; break;
                }
            }
        }

        private void read_settings () {
            if (inp.settings == null) return;
            foreach (Xml.Node* set in kids (inp.settings)) {
                if (attr (set, "name", Ods.NS_CONFIG) == "ooo:configuration-settings") {
                    foreach (Xml.Node* ci in kids (set)) {
                        if (attr (ci, "name", Ods.NS_CONFIG) == "AutoCalculate") book.manual_calc = (ci->get_content () ?? "").strip () == "false";
                    }
                    continue;
                }
                if (attr (set, "name", Ods.NS_CONFIG) != "ooo:view-settings") continue;
                Xml.Node* views = null;
                foreach (Xml.Node* v in kids (set)) if (attr (v, "name", Ods.NS_CONFIG) == "Views") views = v;
                if (views == null) continue;
                foreach (Xml.Node* entry in kids (views)) {
                    bool global_grid = true;
                    foreach (Xml.Node* item in kids (entry)) {
                        string nm = attr (item, "name", Ods.NS_CONFIG);
                        if (nm == "ShowGrid") global_grid = (item->get_content () ?? "") != "false";
                        if (nm != "Tables") continue;
                        foreach (Xml.Node* tbl in kids (item)) {
                            var sheet = book.find_sheet (attr (tbl, "name", Ods.NS_CONFIG));
                            if (sheet == null) continue;
                            var vals = new Gee.HashMap<string, string> ();
                            foreach (Xml.Node* ci in kids (tbl)) vals[attr (ci, "name", Ods.NS_CONFIG)] = (ci->get_content () ?? "").strip ();
                            if (vals["HorizontalSplitMode"] == "2") sheet.freeze_cols = int.parse (vals["HorizontalSplitPosition"] ?? "0");
                            if (vals["VerticalSplitMode"] == "2") sheet.freeze_rows = int.parse (vals["VerticalSplitPosition"] ?? "0");
                            if (vals.has_key ("ShowGrid")) sheet.show_grid = vals["ShowGrid"] != "false";
                            else if (!global_grid) sheet.show_grid = false;
                            OdsExtras.read_table_settings (sheet, vals);
                        }
                    }
                }
            }
        }

        private void read_names (Xml.Node* container, Sheet? scope) {
            foreach (Xml.Node* n in kids (container)) {
                string name = attr (n, "name", Ods.NS_TABLE);
                if (name == "") continue;
                string value;
                if (n->name == "named-range") {
                    value = "=" + Ods.from_of ("[" + attr (n, "cell-range-address", Ods.NS_TABLE) + "]").substring (1);
                } else if (n->name == "named-expression") {
                    value = Ods.from_of (attr (n, "expression", Ods.NS_TABLE));
                } else {
                    continue;
                }
                if (value.has_prefix ("=")) value = value.substring (1);
                if (scope != null) scope.names[name] = value;
                else book.names[name] = value;
            }
        }

        private void read_validations (Xml.Node* container) {
            foreach (Xml.Node* v in kids (container)) {
                string name = attr (v, "name", Ods.NS_TABLE);
                string cond = attr (v, "condition", Ods.NS_TABLE);
                var val = new Validation (new Area.cell (null, 0, 0));
                if (!OdsExtras.read_validation_condition (val, cond)) continue;
                val.allow_blank = attr (v, "allow-empty-cell", Ods.NS_TABLE) != "false";
                val.dropdown = attr (v, "display-list", Ods.NS_TABLE) != "no";
                var help = Ods.child (v, "help-message");
                if (help != null) {
                    val.show_input = attr (help, "display", Ods.NS_TABLE) != "false";
                    val.input_title = attr (help, "title", Ods.NS_TABLE);
                    val.message = paragraphs (help);
                }
                var err = Ods.child (v, "error-message");
                if (err != null) {
                    val.show_error = attr (err, "display", Ods.NS_TABLE) != "false";
                    val.error_title = attr (err, "title", Ods.NS_TABLE);
                    val.error_message = paragraphs (err);
                    switch (attr (err, "message-type", Ods.NS_TABLE)) {
                        case "warning": val.alert = ValidationAlert.WARNING; break;
                        case "information": val.alert = ValidationAlert.INFORMATION; break;
                        default: val.alert = ValidationAlert.STOP; break;
                    }
                }
                validations[name] = val;
            }
        }

        private static string paragraphs (Xml.Node* n) {
            var sb = new StringBuilder ();
            foreach (Xml.Node* p in kids (n)) {
                if (p->name != "p") continue;
                if (sb.len > 0) sb.append ("\n");
                sb.append (paragraph_text (p));
            }
            return sb.str;
        }

        public static string paragraph_text (Xml.Node* p) {
            var sb = new StringBuilder ();
            for (Xml.Node* c = p->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.TEXT_NODE || c->type == Xml.ElementType.CDATA_SECTION_NODE) {
                    sb.append (c->content ?? "");
                } else if (c->type == Xml.ElementType.ELEMENT_NODE) {
                    switch (c->name) {
                        case "s":
                            int count = int.max (1, int.parse (Ods.attr (c, "c", Ods.NS_TEXT)));
                            for (int i = 0; i < count; i++) sb.append_c (' ');
                            break;
                        case "tab": sb.append_c ('\t'); break;
                        case "line-break": sb.append_c ('\n'); break;
                        case "annotation": break;
                        default: sb.append (paragraph_text (c)); break;
                    }
                }
            }
            return sb.str;
        }

        private static string find_link (Xml.Node* n) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE || c->name == "annotation") continue;
                if (c->name == "a") return Ods.attr (c, "href", Ods.NS_XLINK);
                string inner = find_link (c);
                if (inner != "") return inner;
            }
            return "";
        }

        private string text_prop (Xml.Node* s, string name, string ns) {
            for (Xml.Node* cur = s; cur != null; cur = parent_of (cur)) {
                foreach (Xml.Node* p in kids (cur)) {
                    string v = attr (p, name, ns);
                    if (v != "") return v;
                }
            }
            return "";
        }

        private Xml.Node* parent_of (Xml.Node* s) {
            string parent = attr (s, "parent-style-name", Ods.NS_STYLE);
            if (parent == "") {
                if (attr (s, "name", Ods.NS_STYLE) == "Default") return null;
                return styles.has_key ("table-cell:Default") && s != styles["table-cell:Default"] ? styles["table-cell:Default"] : null;
            }
            return styles.has_key ("table-cell:" + parent) ? styles["table-cell:" + parent] : null;
        }

        private static double length_pt (string w) {
            string t = w.strip ();
            if (t.has_suffix ("pt")) return double.parse (t.substring (0, t.length - 2));
            if (t.has_suffix ("cm")) return double.parse (t.substring (0, t.length - 2)) * 28.3465;
            if (t.has_suffix ("mm")) return double.parse (t.substring (0, t.length - 2)) * 2.83465;
            if (t.has_suffix ("in")) return double.parse (t.substring (0, t.length - 2)) * 72;
            if (t.has_suffix ("px")) return double.parse (t.substring (0, t.length - 2)) * 0.75;
            return 0;
        }

        public static Border parse_border (string spec) {
            string s = spec.strip ().down ();
            if (s == "" || s == "none" || s.has_prefix ("0pt") || s.has_prefix ("hidden")) return new Border ();
            string color = "";
            double width = 0.75;
            BorderStyle style = BorderStyle.THIN;
            foreach (string part in s.split (" ")) {
                if (part.has_prefix ("#")) color = part;
                else if (part == "dashed" || part == "dash-dot" || part == "dash-dot-dot" || part == "long-dash" || part == "fine-dashed") style = BorderStyle.DASHED;
                else if (part == "dotted") style = BorderStyle.DOTTED;
                else if (part == "double" || part == "double-thin") style = BorderStyle.DOUBLE;
                else if (part == "none") return new Border ();
                else if (part.length > 0 && (part[0].isdigit () || part[0] == '.')) width = length_pt (part);
            }
            if (style == BorderStyle.THIN) {
                if (width > 2.2) style = BorderStyle.THICK;
                else if (width > 1.2) style = BorderStyle.MEDIUM;
            }
            return new Border (style, color == "#000000" ? "" : color);
        }

        private int cell_style (string name) {
            if (name == "") return 0;
            if (style_cache.has_key (name)) return style_cache[name];
            Xml.Node* s = styles["table-cell:" + name];
            if (s == null) {
                style_cache[name] = 0;
                return 0;
            }
            var st = new CellStyle ();
            string fill = text_prop (s, "background-color", Ods.NS_FO);
            if (fill != "" && fill != "transparent") st.fill = fill;
            string fw = text_prop (s, "font-weight", Ods.NS_FO);
            st.bold = fw == "bold" || (fw.length > 0 && fw[0].isdigit () && int.parse (fw) >= 600);
            st.italic = text_prop (s, "font-style", Ods.NS_FO) == "italic";
            string ul = text_prop (s, "text-underline-style", Ods.NS_STYLE);
            st.underline = ul != "" && ul != "none";
            string lt = text_prop (s, "text-line-through-style", Ods.NS_STYLE);
            st.strike = lt != "" && lt != "none";
            string color = text_prop (s, "color", Ods.NS_FO);
            if (color != "" && color != "#000000") st.color = color;
            string size = text_prop (s, "font-size", Ods.NS_FO);
            if (size.has_suffix ("pt")) st.font_size = double.parse (size.substring (0, size.length - 2));
            string fname = text_prop (s, "font-name", Ods.NS_STYLE);
            string family = fname != "" && fonts.has_key (fname) ? fonts[fname] : text_prop (s, "font-family", Ods.NS_FO).replace ("'", "");
            if (family == "" && fname != "") family = fname;
            if (family != "" && family != "Liberation Sans" && family != "Arial" && family != "Calibri" && family != "Carlito") st.font_family = family;
            switch (text_prop (s, "text-align", Ods.NS_FO)) {
                case "start": case "left": st.halign = HAlign.LEFT; break;
                case "center": st.halign = HAlign.CENTER; break;
                case "end": case "right": st.halign = HAlign.RIGHT; break;
                case "justify": st.halign = HAlign.JUSTIFY; break;
            }
            if (text_prop (s, "repeat-content", Ods.NS_STYLE) == "true") st.halign = HAlign.FILL;
            switch (text_prop (s, "vertical-align", Ods.NS_STYLE)) {
                case "top": st.valign = VAlign.TOP; break;
                case "middle": st.valign = VAlign.CENTER; break;
            }
            st.wrap = text_prop (s, "wrap-option", Ods.NS_FO) == "wrap";
            string ml = text_prop (s, "margin-left", Ods.NS_FO);
            if (ml != "" && st.halign != HAlign.CENTER) st.indent = (int) Math.round (length_pt (ml) / 10);
            string all = text_prop (s, "border", Ods.NS_FO);
            if (all != "") {
                var b = parse_border (all);
                st.left = new Border (b.style, b.color);
                st.right = new Border (b.style, b.color);
                st.top = new Border (b.style, b.color);
                st.bottom = new Border (b.style, b.color);
            }
            string bl = text_prop (s, "border-left", Ods.NS_FO);
            if (bl != "") st.left = parse_border (bl);
            string br = text_prop (s, "border-right", Ods.NS_FO);
            if (br != "") st.right = parse_border (br);
            string bt = text_prop (s, "border-top", Ods.NS_FO);
            if (bt != "") st.top = parse_border (bt);
            string bb = text_prop (s, "border-bottom", Ods.NS_FO);
            if (bb != "") st.bottom = parse_border (bb);
            string ds = "";
            for (Xml.Node* cur = s; cur != null && ds == ""; cur = parent_of (cur)) ds = attr (cur, "data-style-name", Ods.NS_STYLE);
            if (ds != "" && data_styles.has_key (ds)) {
                string code = OdsFormat.to_code (data_styles[ds], data_styles);
                if (code != "") st.number_format = code;
            }
            OdsExtras.read_cell_style (st, s);
            int idx = book.intern (st);
            style_cache[name] = idx;
            return idx;
        }

        private void read_table (Sheet sheet, Xml.Node* table) {
            string ts = attr (table, "style-name", Ods.NS_TABLE);
            Xml.Node* tstyle = styles["table:" + ts];
            if (tstyle != null) {
                var tp = Ods.child (tstyle, "table-properties");
                if (attr (tp, "display", Ods.NS_TABLE) == "false") sheet.visibility = 1;
                string tab = attr (tp, "tab-color", Ods.NS_TABLEOOO);
                if (tab == "") tab = attr (tp, "tab-color", "urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0");
                if (tab != "") sheet.tab_color = tab;
            }
            var col_defaults = new Gee.ArrayList<string> ();
            int col_index = 0;
            int r = 0;
            read_container (sheet, table, ref col_index, ref r, col_defaults);
            var cf = Ods.child (table, "conditional-formats");
            if (cf != null) read_cond_formats (sheet, cf);
            OdsExtras.read_table (inp, sheet, table);
            sheet.recompute_extent ();
        }

        private void read_container (Sheet sheet, Xml.Node* container, ref int col_index, ref int r, Gee.ArrayList<string> col_defaults) {
            foreach (Xml.Node* n in kids (container)) {
                switch (n->name) {
                    case "table-column":
                        int rep = int.max (1, int.parse (attr (n, "number-columns-repeated", Ods.NS_TABLE)));
                        string cs = attr (n, "style-name", Ods.NS_TABLE);
                        string dcs = attr (n, "default-cell-style-name", Ods.NS_TABLE);
                        double px = 0;
                        Xml.Node* cstyle = styles["table-column:" + cs];
                        if (cstyle != null) {
                            string w = attr (Ods.child (cstyle, "table-column-properties"), "column-width", Ods.NS_STYLE);
                            px = length_pt (w) / 0.75;
                        }
                        bool hidden = attr (n, "visibility", Ods.NS_TABLE) == "collapse";
                        for (int k = 0; k < rep && col_index < MAX_COLS; k++) {
                            if (k < 1024) {
                                if (px > 0) {
                                    int wpx = (int) Math.round (px * Xlsx.COL_SCALE);
                                    if ((wpx - sheet.default_col_width).abs () > 1) sheet.col_widths[col_index] = wpx;
                                }
                                if (hidden) sheet.hidden_cols.add (col_index);
                                col_defaults.add (dcs == "Default" ? "" : dcs);
                            }
                            col_index++;
                        }
                        break;
                    case "table-columns":
                    case "table-header-columns":
                    case "table-column-group":
                    case "table-rows":
                    case "table-header-rows":
                    case "table-row-group":
                        read_container (sheet, n, ref col_index, ref r, col_defaults);
                        break;
                    case "table-row":
                        r = read_row (sheet, n, r, col_defaults);
                        break;
                }
            }
        }

        private int read_row (Sheet sheet, Xml.Node* row, int r, Gee.ArrayList<string> col_defaults) {
            int rep = int.max (1, int.parse (attr (row, "number-rows-repeated", Ods.NS_TABLE)));
            string rs = attr (row, "style-name", Ods.NS_TABLE);
            string row_default = attr (row, "default-cell-style-name", Ods.NS_TABLE);
            if (row_default == "Default") row_default = "";
            int height = 0;
            Xml.Node* rstyle = styles["table-row:" + rs];
            if (rstyle != null) {
                var rp = Ods.child (rstyle, "table-row-properties");
                if (attr (rp, "use-optimal-row-height", Ods.NS_STYLE) == "false") {
                    height = (int) Math.round (length_pt (attr (rp, "row-height", Ods.NS_STYLE)) / 0.75 * Xlsx.ROW_SCALE);
                }
            }
            bool hidden = attr (row, "visibility", Ods.NS_TABLE) == "collapse" || attr (row, "visibility", Ods.NS_TABLE) == "filter";
            bool any = false;
            foreach (Xml.Node* c in kids (row)) {
                if (c->children != null || attr (c, "value-type", Ods.NS_OFFICE) != "" || attr (c, "number-columns-spanned", Ods.NS_TABLE) != "" || attr (c, "content-validation-name", Ods.NS_TABLE) != "") any = true;
                else if (attr (c, "style-name", Ods.NS_TABLE) != "" && cell_style (attr (c, "style-name", Ods.NS_TABLE)) != 0 && rep < 64) any = true;
            }
            int limit = any ? int.min (rep, 4096) : rep;
            for (int k = 0; k < rep && r < MAX_ROWS; k++) {
                if (k < 1024 || rep < 4096) {
                    if (height > 0 && k < 1024) sheet.row_heights[r] = height;
                    if (hidden && k < 1024) sheet.hidden_rows.add (r);
                }
                if (any && k < limit) {
                    int col = 0;
                    foreach (Xml.Node* c in kids (row)) {
                        if (c->name != "table-cell" && c->name != "covered-table-cell") continue;
                        int crep = int.max (1, int.parse (attr (c, "number-columns-repeated", Ods.NS_TABLE)));
                        if (c->name == "table-cell") {
                            bool content = c->children != null || attr (c, "value-type", Ods.NS_OFFICE) != "" || attr (c, "formula", Ods.NS_TABLE) != "";
                            string sname = attr (c, "style-name", Ods.NS_TABLE);
                            if (sname == "") sname = row_default;
                            int styled = content || crep <= 256 ? crep : 0;
                            for (int j = 0; j < styled && col + j < MAX_COLS && j < 1024; j++) {
                                string eff = sname != "" ? sname : (col + j < col_defaults.size ? col_defaults[col + j] : "");
                                read_cell (sheet, c, r, col + j, eff);
                            }
                            int cs = int.parse (attr (c, "number-columns-spanned", Ods.NS_TABLE));
                            int rsp = int.parse (attr (c, "number-rows-spanned", Ods.NS_TABLE));
                            if (cs > 1 || rsp > 1) sheet.merges.add (new Area (sheet, r, col, r + int.max (rsp, 1) - 1, col + int.max (cs, 1) - 1));
                            string vname = attr (c, "content-validation-name", Ods.NS_TABLE);
                            if (vname != "") {
                                if (!validation_cells.has_key (vname)) validation_cells[vname] = new Gee.ArrayList<Area> ();
                                validation_cells[vname].add (new Area (sheet, r, col, r, int.min (col + crep - 1, MAX_COLS - 1)));
                            }
                        }
                        col += crep;
                    }
                }
                r++;
            }
            return r;
        }

        private Gee.ArrayList<Area> matrices = new Gee.ArrayList<Area> ();

        private bool inside_matrix (Sheet sheet, int r, int col) {
            foreach (var m in matrices) {
                if (m.sheet == sheet && m.contains (r, col) && !(m.r1 == r && m.c1 == col)) return true;
            }
            return false;
        }

        private void read_cell (Sheet sheet, Xml.Node* c, int r, int col, string style_name) {
            int style = cell_style (style_name);
            if (matrices.size > 0 && attr (c, "formula", Ods.NS_TABLE) == "" && inside_matrix (sheet, r, col)) {
                if (style != 0) sheet.ensure (r, col).style = style;
                return;
            }
            string type = attr (c, "value-type", Ods.NS_OFFICE);
            if (type == "") type = attr (c, "value-type", Ods.NS_CALCEXT);
            string formula = attr (c, "formula", Ods.NS_TABLE);
            var ann = Ods.child (c, "annotation");
            string link = find_link (c);
            if (formula != "") {
                sheet.set_input (r, col, Ods.from_of (formula));
                var fc = sheet.get_cell (r, col);
                if (fc != null) {
                    string mc = attr (c, "number-matrix-columns-spanned", Ods.NS_TABLE);
                    string mr = attr (c, "number-matrix-rows-spanned", Ods.NS_TABLE);
                    if (mc != "" && mr != "" && (int.parse (mc) > 1 || int.parse (mr) > 1)) {
                        fc.array_area = new Area (sheet, r, col, r + int.parse (mr) - 1, col + int.parse (mc) - 1);
                        matrices.add (fc.array_area);
                    }
                    if (fc.array_area == null) fc.legacy = true;
                }
            } else {
                switch (type) {
                    case "float":
                    case "percentage":
                    case "currency":
                        double v = double.parse (attr (c, "value", Ods.NS_OFFICE));
                        var cell = sheet.ensure (r, col);
                        cell.value = Value.num (v);
                        cell.input = Value.format_number_general_full (v);
                        break;
                    case "date":
                        double d;
                        string f;
                        string dv = attr (c, "date-value", Ods.NS_OFFICE).replace ("T", " ");
                        if (Input.parse_date_time (dv, out d, out f)) {
                            if (book.date1904) d -= 1462;
                            var cell = sheet.ensure (r, col);
                            cell.value = Value.num (d);
                            cell.input = Value.format_number_general_full (d);
                            if (book.styles[style].number_format == "General") {
                                var st = book.styles[style].copy ();
                                st.number_format = dv.contains (":") ? "yyyy-mm-dd hh:mm" : "yyyy-mm-dd";
                                style = book.intern (st);
                            }
                        }
                        break;
                    case "time":
                        string tv = attr (c, "time-value", Ods.NS_OFFICE);
                        double secs = 0;
                        MatchInfo info;
                        if (/PT(\d+)H(\d+)M([\d.]+)S/.match (tv, 0, out info)) {
                            secs = int.parse (info.fetch (1)) * 3600 + int.parse (info.fetch (2)) * 60 + double.parse (info.fetch (3));
                        }
                        var tcell = sheet.ensure (r, col);
                        tcell.value = Value.num (secs / 86400);
                        tcell.input = Value.format_number_general_full (secs / 86400);
                        if (book.styles[style].number_format == "General") {
                            var st = book.styles[style].copy ();
                            st.number_format = "h:mm:ss";
                            style = book.intern (st);
                        }
                        break;
                    case "boolean":
                        sheet.set_input (r, col, attr (c, "boolean-value", Ods.NS_OFFICE) == "true" ? "TRUE" : "FALSE");
                        break;
                    case "error":
                        string etext = cell_paragraphs (c);
                        var ek = ErrorKind.parse (etext);
                        if (ek != ErrorKind.NONE) {
                            var ecell = sheet.ensure (r, col);
                            ecell.value = Value.err (ek);
                            ecell.input = etext;
                        }
                        break;
                    default:
                        string text = type == "string" ? attr (c, "string-value", Ods.NS_OFFICE) : "";
                        if (text == "") text = cell_paragraphs (c);
                        if (text != "") {
                            var cell = sheet.ensure (r, col);
                            cell.value = Value.str (text);
                            cell.input = Input.parse (text).value.kind == ValueKind.TEXT ? text : "'" + text;
                        }
                        break;
                }
            }
            if (style != 0) sheet.ensure (r, col).style = style;
            if (ann != null) {
                var cell = sheet.ensure (r, col);
                cell.note = paragraphs (ann);
                foreach (Xml.Node* a in kids (ann)) {
                    if (a->name == "creator") cell.note_author = a->get_content () ?? "";
                }
            }
            if (link != "") {
                string l = link;
                if (l.has_prefix ("#")) {
                    int dot = l.last_index_of_char ('.');
                    if (dot > 1) {
                        string sh = l.substring (1, dot - 1);
                        if (sh.has_prefix ("'")) sh = sh.substring (1, sh.length - 2).replace ("''", "'");
                        if (sh.has_prefix ("$")) sh = sh.substring (1);
                        l = "#" + Address.quote_sheet (sh) + "!" + l.substring (dot + 1).replace ("$", "");
                    }
                }
                sheet.ensure (r, col).link = l;
            }
            OdsExtras.read_cell (inp, sheet, c, r, col);
        }

        private static string cell_paragraphs (Xml.Node* c) {
            var sb = new StringBuilder ();
            foreach (Xml.Node* p in kids (c)) {
                if (p->name != "p") continue;
                if (sb.len > 0) sb.append ("\n");
                sb.append (paragraph_text (p));
            }
            return sb.str;
        }

        private int apply_style (string name) {
            if (name == "") return 0;
            Xml.Node* s = styles["table-cell:" + name];
            if (s == null) return 0;
            return cell_style (name);
        }

        private static Area? parse_range (Workbook book, string addr) {
            string f = Ods.from_of ("[" + addr.strip () + "]");
            try {
                var n = Formula.parse (f, book, null);
                if (n.kind != NodeKind.REF || n.a == null) return null;
                return n.to_area (n.sheet);
            } catch (FormulaError e) {
                return null;
            }
        }

        private void read_cond_formats (Sheet sheet, Xml.Node* container) {
            foreach (Xml.Node* f in kids (container)) {
                if (f->name != "conditional-format") continue;
                string target = attr (f, "target-range-address", Ods.NS_CALCEXT);
                var areas = new Gee.ArrayList<Area> ();
                foreach (string part in target.split (" ")) {
                    var a = parse_range (book, part);
                    if (a != null) {
                        a.sheet = sheet;
                        areas.add (a);
                    }
                }
                foreach (var area in areas) {
                    foreach (Xml.Node* c in kids (f)) {
                        CondFormat? cf = null;
                        if (c->name == "condition") {
                            cf = condition (area, attr (c, "value", Ods.NS_CALCEXT));
                            if (cf != null) cf.style = apply_style (attr (c, "apply-style-name", Ods.NS_CALCEXT));
                        } else if (c->name == "color-scale") {
                            cf = new CondFormat (area, CondKind.COLOR_SCALE);
                            var entries = kids (c);
                            cf.three_colors = entries.size >= 3;
                            if (entries.size >= 2) {
                                cf.color1 = attr (entries[0], "color", Ods.NS_CALCEXT);
                                if (entries.size >= 3) {
                                    cf.color2 = attr (entries[1], "color", Ods.NS_CALCEXT);
                                    cf.color3 = attr (entries[2], "color", Ods.NS_CALCEXT);
                                } else {
                                    cf.color3 = attr (entries[1], "color", Ods.NS_CALCEXT);
                                }
                            }
                        } else if (c->name == "icon-set") {
                            cf = new CondFormat (area, CondKind.ICON_SET);
                            string ist = attr (c, "icon-set-type", Ods.NS_CALCEXT);
                            if (ist != "") cf.icon_set = ist;
                            cf.show_value = attr (c, "show-value", Ods.NS_CALCEXT) != "false";
                        } else if (c->name == "date-is") {
                            cf = new CondFormat (area, CondKind.DATE_OCCURRING);
                            cf.date_period = attr (c, "date", Ods.NS_CALCEXT).replace ("last-7-days", "last7Days").replace ("this-week", "thisWeek").replace ("last-week", "lastWeek").replace ("next-week", "nextWeek").replace ("this-month", "thisMonth").replace ("last-month", "lastMonth").replace ("next-month", "nextMonth");
                            cf.style = apply_style (attr (c, "style", Ods.NS_CALCEXT));
                        } else if (c->name == "data-bar") {
                            cf = new CondFormat (area, CondKind.DATA_BAR);
                            string pc = attr (c, "positive-color", Ods.NS_CALCEXT);
                            if (pc != "") cf.color1 = pc;
                        }
                        if (cf != null) sheet.cond_formats.add (cf);
                    }
                }
            }
        }

        private static string inner (string v, string prefix) {
            string rest = v.substring (prefix.length);
            if (rest.has_suffix (")")) rest = rest.substring (0, rest.length - 1);
            return rest;
        }

        private static string unquote (string s) {
            string t = s.strip ();
            if (t.has_prefix ("\"") && t.has_suffix ("\"") && t.length >= 2) return t.substring (1, t.length - 2).replace ("\"\"", "\"");
            return t;
        }

        private static string xl_value (string v) {
            string f = Ods.from_of (v.strip ());
            return f.has_prefix ("=") ? f.substring (1) : f;
        }

        private CondFormat? condition (Area area, string value) {
            string v = value.strip ();
            CondFormat cf;
            if (v.has_prefix ("between(")) {
                cf = new CondFormat (area, CondKind.BETWEEN);
                var parts = split_args (inner (v, "between("));
                if (parts.length != 2) return null;
                cf.a = xl_value (parts[0]);
                cf.b = xl_value (parts[1]);
                return cf;
            }
            if (v == "duplicate") return new CondFormat (area, CondKind.DUPLICATE);
            if (v == "unique") return new CondFormat (area, CondKind.UNIQUE);
            if (v == "above-average") return new CondFormat (area, CondKind.ABOVE_AVERAGE);
            if (v == "below-average") return new CondFormat (area, CondKind.BELOW_AVERAGE);
            if (v == "is-error") return new CondFormat (area, CondKind.ERRORS);
            if (v == "is-no-error") return new CondFormat (area, CondKind.NO_ERRORS);
            if (v.has_prefix ("not-between(")) {
                cf = new CondFormat (area, CondKind.NOT_BETWEEN);
                var nparts = split_args (inner (v, "not-between("));
                if (nparts.length != 2) return null;
                cf.a = xl_value (nparts[0]);
                cf.b = xl_value (nparts[1]);
                return cf;
            }
            if (v.has_prefix ("top-percent(") || v.has_prefix ("bottom-percent(")) {
                bool tp = v.has_prefix ("top");
                cf = new CondFormat (area, tp ? CondKind.TOP : CondKind.BOTTOM);
                cf.a = inner (v, tp ? "top-percent(" : "bottom-percent(");
                cf.percent = true;
                return cf;
            }
            if (v.has_prefix ("begins-with(")) {
                cf = new CondFormat (area, CondKind.TEXT_BEGINS);
                cf.a = unquote (inner (v, "begins-with("));
                return cf;
            }
            if (v.has_prefix ("ends-with(")) {
                cf = new CondFormat (area, CondKind.TEXT_ENDS);
                cf.a = unquote (inner (v, "ends-with("));
                return cf;
            }
            if (v.has_prefix ("not-contains-text(")) {
                cf = new CondFormat (area, CondKind.TEXT_NOT_CONTAINS);
                cf.a = unquote (inner (v, "not-contains-text("));
                return cf;
            }
            if (v == "is-blank" || v == "is-empty") return new CondFormat (area, CondKind.BLANK);
            if (v.has_prefix ("top-elements(") || v.has_prefix ("bottom-elements(")) {
                bool top = v.has_prefix ("top");
                cf = new CondFormat (area, top ? CondKind.TOP : CondKind.BOTTOM);
                cf.a = inner (v, top ? "top-elements(" : "bottom-elements(");
                return cf;
            }
            if (v.has_prefix ("contains-text(")) {
                cf = new CondFormat (area, CondKind.TEXT_CONTAINS);
                cf.a = unquote (inner (v, "contains-text("));
                return cf;
            }
            if (v.has_prefix ("formula-is(")) {
                cf = new CondFormat (area, CondKind.FORMULA);
                cf.a = "=" + xl_value (inner (v, "formula-is("));
                return cf;
            }
            string[] ops = { "!=", ">=", "<=", ">", "<", "=" };
            foreach (string op in ops) {
                if (!v.has_prefix (op)) continue;
                string rest = xl_value (v.substring (op.length));
                switch (op) {
                    case "!=": cf = new CondFormat (area, CondKind.NOT_EQUAL); break;
                    case ">": cf = new CondFormat (area, CondKind.GREATER); break;
                    case ">=": cf = new CondFormat (area, CondKind.GREATER_EQUAL); break;
                    case "<": cf = new CondFormat (area, CondKind.LESS); break;
                    case "<=": cf = new CondFormat (area, CondKind.LESS_EQUAL); break;
                    default: cf = new CondFormat (area, CondKind.EQUAL); break;
                }
                cf.a = rest;
                return cf;
            }
            return null;
        }

        public static string[] split_args (string s) {
            string[] parts = {};
            int depth = 0;
            bool q = false;
            int start = 0;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (c == '"') q = !q;
                if (q) continue;
                if (c == '(' || c == '[' || c == '{') depth++;
                else if (c == ')' || c == ']' || c == '}') depth--;
                else if ((c == ',' || c == ';') && depth == 0) {
                    parts += s.substring (start, i - start);
                    start = i + 1;
                }
            }
            parts += s.substring (start);
            return parts;
        }
    }

    public class OdsWriter {
        private Workbook book;
        private OdsOut o;
        private Gee.HashMap<string, string> data_style_names = new Gee.HashMap<string, string> ();
        private Gee.HashMap<int, string> cell_styles = new Gee.HashMap<int, string> ();
        private Gee.HashMap<int, string> cf_styles = new Gee.HashMap<int, string> ();
        private Gee.HashMap<string, string> col_styles = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> row_styles = new Gee.HashMap<string, string> ();

        public OdsWriter (Workbook book) {
            this.book = book;
            this.o = new OdsOut (book);
        }

        private static string esc (string s) {
            return XlsxWriter.esc (s);
        }

        private string data_style (string code) {
            if (code == "" || code == "General") return "";
            if (data_style_names.has_key (code)) return data_style_names[code];
            string name = "N%d".printf (data_style_names.size + 100);
            string family;
            o.auto_styles.append (OdsFormat.data_style (name, code, out family));
            data_style_names[code] = name;
            return name;
        }

        private static string border_spec (Border b) {
            string w;
            string kind = "solid";
            switch (b.style) {
                case BorderStyle.THIN: w = "0.74pt"; break;
                case BorderStyle.MEDIUM: w = "1.76pt"; break;
                case BorderStyle.THICK: w = "2.49pt"; break;
                case BorderStyle.DASHED: w = "0.74pt"; kind = "dashed"; break;
                case BorderStyle.DOTTED: w = "0.74pt"; kind = "dotted"; break;
                case BorderStyle.DOUBLE: w = "2.01pt"; kind = "double"; break;
                default: return "none";
            }
            return "%s %s %s".printf (w, kind, b.color != "" ? b.color : "#000000");
        }

        private string style_props (CellStyle s, string data_name) {
            var sb = new StringBuilder ();
            sb.append ("<style:table-cell-properties");
            if (s.fill != "") sb.append (" fo:background-color=\"%s\"".printf (s.fill));
            if (s.wrap) sb.append (" fo:wrap-option=\"wrap\"");
            if (s.valign != VAlign.BOTTOM) sb.append (" style:vertical-align=\"%s\"".printf (s.valign == VAlign.TOP ? "top" : "middle"));
            else sb.append (" style:vertical-align=\"bottom\"");
            if (s.halign == HAlign.FILL) sb.append (" style:repeat-content=\"true\"");
            if (s.halign != HAlign.GENERAL) sb.append (" style:text-align-source=\"fix\"");
            string bl = border_spec (s.left), br = border_spec (s.right), bt = border_spec (s.top), bb = border_spec (s.bottom);
            if (bl == br && br == bt && bt == bb) {
                if (bl != "none") sb.append (" fo:border=\"%s\"".printf (bl));
            } else {
                sb.append (" fo:border-left=\"%s\" fo:border-right=\"%s\" fo:border-top=\"%s\" fo:border-bottom=\"%s\"".printf (bl, br, bt, bb));
            }
            sb.append (OdsExtras.cell_properties (s));
            sb.append ("/>");
            if (s.halign != HAlign.GENERAL || s.indent > 0) {
                string[] h = { "start", "start", "center", "end", "start", "justify" };
                sb.append ("<style:paragraph-properties fo:text-align=\"%s\"".printf (h[s.halign]));
                if (s.indent > 0) sb.append (" fo:margin-left=\"%dpt\"".printf (s.indent * 10));
                sb.append ("/>");
            }
            sb.append ("<style:text-properties");
            if (s.bold) sb.append (" fo:font-weight=\"bold\" style:font-weight-asian=\"bold\" style:font-weight-complex=\"bold\"");
            if (s.italic) sb.append (" fo:font-style=\"italic\" style:font-style-asian=\"italic\" style:font-style-complex=\"italic\"");
            if (s.underline) sb.append (" style:text-underline-style=\"solid\" style:text-underline-width=\"auto\" style:text-underline-color=\"font-color\"");
            if (s.strike) sb.append (" style:text-line-through-style=\"solid\"");
            if (s.color != "") sb.append (" fo:color=\"%s\"".printf (s.color));
            if (s.font_size != 11) sb.append (" fo:font-size=\"%spt\"".printf (Value.format_number_general_full (s.font_size)));
            if (s.font_family != "") sb.append (" fo:font-family=\"%s\"".printf (esc (s.font_family)));
            sb.append ("/>");
            return sb.str;
        }

        private string cell_style_name (int idx) {
            if (idx == 0) return "";
            if (cell_styles.has_key (idx)) return cell_styles[idx];
            var s = book.styles[idx];
            string name = "ce%d".printf (idx);
            string ds = data_style (s.number_format);
            o.auto_styles.append ("<style:style style:name=\"%s\" style:family=\"table-cell\" style:parent-style-name=\"%s\"%s>".printf (name, EditOds.parent_style (o, s), ds != "" ? " style:data-style-name=\"%s\"".printf (ds) : ""));
            o.auto_styles.append (style_props (s, ds));
            o.auto_styles.append ("</style:style>");
            cell_styles[idx] = name;
            return name;
        }

        private string cf_style_name (int idx) {
            if (cf_styles.has_key (idx)) return cf_styles[idx];
            var s = book.styles[idx];
            string name = "ss_cf_%d".printf (idx);
            string ds = data_style (s.number_format);
            o.common_styles.append ("<style:style style:name=\"%s\" style:family=\"table-cell\" style:parent-style-name=\"Default\"%s>".printf (name, ds != "" ? " style:data-style-name=\"%s\"".printf (ds) : ""));
            o.common_styles.append (style_props (s, ds));
            o.common_styles.append ("</style:style>");
            cf_styles[idx] = name;
            return name;
        }

        private string col_style (Sheet sheet, int c) {
            double cm = sheet.col_width (c) / Xlsx.COL_SCALE / 37.795;
            if (sheet.hidden_cols.contains (c)) cm = (sheet.col_widths.has_key (c) ? sheet.col_widths[c] : sheet.default_col_width) / Xlsx.COL_SCALE / 37.795;
            string w = Value.fixed (cm, 3);
            if (col_styles.has_key (w)) return col_styles[w];
            string name = "co%d".printf (col_styles.size + 1);
            o.auto_styles.append ("<style:style style:name=\"%s\" style:family=\"table-column\"><style:table-column-properties fo:break-before=\"auto\" style:column-width=\"%scm\"/></style:style>".printf (name, w));
            col_styles[w] = name;
            return name;
        }

        private string row_style (Sheet sheet, int r) {
            bool custom = sheet.row_heights.has_key (r);
            int px = custom ? sheet.row_heights[r] : sheet.default_row_height;
            string h = Value.fixed (px / Xlsx.ROW_SCALE / 37.795, 3);
            string key = h + (custom ? "c" : "o");
            if (row_styles.has_key (key)) return row_styles[key];
            string name = "ro%d".printf (row_styles.size + 1);
            o.auto_styles.append ("<style:style style:name=\"%s\" style:family=\"table-row\"><style:table-row-properties style:row-height=\"%scm\" fo:break-before=\"auto\" style:use-optimal-row-height=\"%s\"/></style:style>".printf (name, h, custom ? "false" : "true"));
            row_styles[key] = name;
            return name;
        }

        private static string para (string text) {
            var sb = new StringBuilder ();
            foreach (string line in text.split ("\n")) {
                sb.append ("<text:p>");
                sb.append (spaces (line));
                sb.append ("</text:p>");
            }
            return sb.str;
        }

        private static string spaces (string line) {
            var sb = new StringBuilder ();
            int i = 0;
            int n = line.length;
            while (i < n) {
                char c = line[i];
                if (c == ' ') {
                    int j = i;
                    while (j < n && line[j] == ' ') j++;
                    int count = j - i;
                    bool lead = i == 0;
                    if (lead) sb.append (count == 1 ? "<text:s/>" : "<text:s text:c=\"%d\"/>".printf (count));
                    else {
                        sb.append_c (' ');
                        if (count > 1) sb.append (count == 2 ? "<text:s/>" : "<text:s text:c=\"%d\"/>".printf (count - 1));
                    }
                    i = j;
                    continue;
                }
                if (c == '\t') {
                    sb.append ("<text:tab/>");
                    i++;
                    continue;
                }
                int k = i;
                while (k < n && line[k] != ' ' && line[k] != '\t') k++;
                sb.append (esc (line.substring (i, k - i)));
                i = k;
            }
            return sb.str;
        }

        private static string odf_link (string link) {
            if (!link.has_prefix ("#")) return link;
            string rest = link.substring (1);
            int bang = rest.last_index_of_char ('!');
            if (bang < 0) return link;
            string sh = rest.substring (0, bang);
            if (sh.has_prefix ("'")) sh = sh.substring (1, sh.length - 2).replace ("''", "'");
            return "#" + sh + "." + rest.substring (bang + 1);
        }

        private string validation_block (Gee.HashMap<Validation, string> names) {
            var sb = new StringBuilder ();
            int n = 1;
            foreach (var sheet in book.sheets) {
                foreach (var v in sheet.validations) {
                    string cond = OdsExtras.validation_condition (v);
                    if (cond == "") continue;
                    string name = "val%d".printf (n++);
                    names[v] = name;
                    sb.append ("<table:content-validation table:name=\"%s\" table:condition=\"%s\" table:allow-empty-cell=\"%s\" table:display-list=\"%s\" table:base-cell-address=\"%s\">".printf (
                        name, esc (cond), v.allow_blank ? "true" : "false", v.dropdown ? "unsorted" : "no", esc (Ods.plain_range (new Area.cell (sheet, v.area.r1, v.area.c1)))));
                    if (v.message != "" || v.input_title != "") {
                        sb.append ("<table:help-message table:title=\"%s\" table:display=\"%s\">%s</table:help-message>".printf (esc (v.input_title), v.show_input ? "true" : "false", para (v.message)));
                    }
                    string mt = v.alert == ValidationAlert.WARNING ? "warning" : (v.alert == ValidationAlert.INFORMATION ? "information" : "stop");
                    sb.append ("<table:error-message table:message-type=\"%s\" table:title=\"%s\" table:display=\"%s\">%s</table:error-message>".printf (mt, esc (v.error_title), v.show_error ? "true" : "false", para (v.error_message)));
                    sb.append ("</table:content-validation>");
                }
            }
            if (sb.len == 0) return "";
            return "<table:content-validations>" + sb.str + "</table:content-validations>";
        }

        private string of_value (string v, Sheet sheet) {
            string t = v.strip ();
            if (t == "") return "\"\"";
            try {
                var n = Formula.parse ("=" + (t.has_prefix ("=") ? t.substring (1) : t), book, sheet);
                return Ods.to_of (n, sheet).substring (4);
            } catch (FormulaError e) {
                return "\"" + t.replace ("\"", "\"\"") + "\"";
            }
        }

        private string cond_formats (Sheet sheet) {
            if (sheet.cond_formats.size == 0) return "";
            var sb = new StringBuilder ("<calcext:conditional-formats>");
            foreach (var cf in sheet.cond_formats) {
                string target = Ods.plain_range (new Area (sheet, cf.area.r1, cf.area.c1, cf.area.r2, cf.area.c2));
                string bca = Ods.plain_range (new Area.cell (sheet, cf.area.r1, cf.area.c1));
                sb.append ("<calcext:conditional-format calcext:target-range-address=\"%s\">".printf (esc (target)));
                if (cf.kind == CondKind.COLOR_SCALE) {
                    sb.append ("<calcext:color-scale><calcext:color-scale-entry calcext:value=\"0\" calcext:type=\"minimum\" calcext:color=\"%s\"/>".printf (cf.color1));
                    if (cf.three_colors) sb.append ("<calcext:color-scale-entry calcext:value=\"50\" calcext:type=\"percentile\" calcext:color=\"%s\"/>".printf (cf.color2));
                    sb.append ("<calcext:color-scale-entry calcext:value=\"0\" calcext:type=\"maximum\" calcext:color=\"%s\"/></calcext:color-scale>".printf (cf.color3));
                } else if (cf.kind == CondKind.ICON_SET) {
                    int icount = CondIcons.count (cf.icon_set);
                    sb.append ("<calcext:icon-set calcext:icon-set-type=\"%s\"%s>".printf (cf.icon_set, cf.show_value ? "" : " calcext:show-value=\"false\""));
                    for (int ii = 0; ii < icount; ii++) sb.append ("<calcext:formatting-entry calcext:value=\"%d\" calcext:type=\"percent\"/>".printf (ii * 100 / icount));
                    sb.append ("</calcext:icon-set>");
                } else if (cf.kind == CondKind.DATE_OCCURRING) {
                    string period = cf.date_period.replace ("last7Days", "last-7-days").replace ("thisWeek", "this-week").replace ("lastWeek", "last-week").replace ("nextWeek", "next-week").replace ("thisMonth", "this-month").replace ("lastMonth", "last-month").replace ("nextMonth", "next-month");
                    sb.append ("<calcext:date-is calcext:style=\"%s\" calcext:date=\"%s\"/>".printf (cf_style_name (cf.style), period));
                } else if (cf.kind == CondKind.DATA_BAR) {
                    sb.append ("<calcext:data-bar calcext:positive-color=\"%s\" calcext:negative-color=\"#ff0000\" calcext:axis-color=\"#000000\"><calcext:formatting-entry calcext:value=\"0\" calcext:type=\"auto-minimum\"/><calcext:formatting-entry calcext:value=\"0\" calcext:type=\"auto-maximum\"/></calcext:data-bar>".printf (cf.color1));
                } else {
                    string val;
                    switch (cf.kind) {
                        case CondKind.GREATER: val = ">" + of_value (cf.a, sheet); break;
                        case CondKind.LESS: val = "<" + of_value (cf.a, sheet); break;
                        case CondKind.EQUAL: val = "=" + of_value (cf.a, sheet); break;
                        case CondKind.NOT_EQUAL: val = "!=" + of_value (cf.a, sheet); break;
                        case CondKind.BETWEEN: val = "between(%s,%s)".printf (of_value (cf.a, sheet), of_value (cf.b, sheet)); break;
                        case CondKind.TEXT_CONTAINS: val = "contains-text(\"%s\")".printf (cf.a.replace ("\"", "\"\"")); break;
                        case CondKind.DUPLICATE: val = "duplicate"; break;
                        case CondKind.UNIQUE: val = "unique"; break;
                        case CondKind.FORMULA: val = "formula-is(%s)".printf (of_value (cf.a, sheet)); break;
                        case CondKind.ABOVE_AVERAGE: val = "above-average"; break;
                        case CondKind.BELOW_AVERAGE: val = "below-average"; break;
                        case CondKind.BLANK: val = "is-blank"; break;
                        case CondKind.GREATER_EQUAL: val = ">=" + of_value (cf.a, sheet); break;
                        case CondKind.LESS_EQUAL: val = "<=" + of_value (cf.a, sheet); break;
                        case CondKind.NOT_BETWEEN: val = "not-between(%s,%s)".printf (of_value (cf.a, sheet), of_value (cf.b, sheet)); break;
                        case CondKind.TEXT_BEGINS: val = "begins-with(\"%s\")".printf (cf.a.replace ("\"", "\"\"")); break;
                        case CondKind.TEXT_ENDS: val = "ends-with(\"%s\")".printf (cf.a.replace ("\"", "\"\"")); break;
                        case CondKind.TEXT_NOT_CONTAINS: val = "not-contains-text(\"%s\")".printf (cf.a.replace ("\"", "\"\"")); break;
                        case CondKind.NO_ERRORS: val = "is-no-error"; break;
                        case CondKind.NO_BLANK: val = "formula-is(LEN(TRIM(%s))>0)".printf ("[." + Address.cell (cf.area.r1, cf.area.c1) + "]"); break;
                        case CondKind.TOP: val = cf.percent ? "top-percent(%s)".printf (cf.a) : "top-elements(%s)".printf (cf.a != "" ? cf.a : "10"); break;
                        case CondKind.BOTTOM: val = cf.percent ? "bottom-percent(%s)".printf (cf.a) : "bottom-elements(%s)".printf (cf.a != "" ? cf.a : "10"); break;
                        default: val = "is-error"; break;
                    }
                    sb.append ("<calcext:condition calcext:apply-style-name=\"%s\" calcext:value=\"%s\" calcext:base-cell-address=\"%s\"/>".printf (cf_style_name (cf.style), esc (val), esc (bca)));
                }
                sb.append ("</calcext:conditional-format>");
            }
            sb.append ("</calcext:conditional-formats>");
            return sb.str;
        }

        private string named (Gee.HashMap<string, string> names, Sheet? scope) {
            if (names.size == 0) return "";
            var sb = new StringBuilder ("<table:named-expressions>");
            foreach (var e in names.entries) {
                string def = e.value.has_prefix ("=") ? e.value : "=" + e.value;
                Sheet ctx = scope ?? book.sheets[0];
                try {
                    var n = Formula.parse (def, book, ctx);
                    string base_addr = "$" + Ods.plain_range (new Area.cell (ctx, 0, 0)).replace (".", ".$").replace ("$A1", "$A$1");
                    if (n.kind == NodeKind.REF && n.a != null && n.sheet != null && !n.is_3d ()) {
                        var a = n.to_area (n.sheet);
                        sb.append ("<table:named-range table:name=\"%s\" table:base-cell-address=\"%s\" table:cell-range-address=\"%s\"/>".printf (esc (e.key), esc (base_addr), esc (Ods.range_address (a))));
                    } else {
                        sb.append ("<table:named-expression table:name=\"%s\" table:base-cell-address=\"%s\" table:expression=\"%s\"/>".printf (esc (e.key), esc (base_addr), esc (Ods.to_of (n, ctx))));
                    }
                } catch (FormulaError err) {
                }
            }
            sb.append ("</table:named-expressions>");
            return sb.str;
        }

        private void body (StringBuilder out_sb) {
            var vnames = new Gee.HashMap<Validation, string> ();
            string vblock = validation_block (vnames);
            OdsExtras.write (o);
            out_sb.append (calculation_settings ());
            out_sb.append (o.before_tables.str);
            out_sb.append (vblock);
            int tn = 1;
            foreach (var sheet in book.sheets) {
                string tstyle = "ta%d".printf (tn++);
                o.auto_styles.append ("<style:style style:name=\"%s\" style:family=\"table\" style:master-page-name=\"%s\"><style:table-properties table:display=\"%s\" style:writing-mode=\"lr-tb\"%s/></style:style>".printf (
                    tstyle, PrintIo.master_name (book, sheet), sheet.visibility == 0 ? "true" : "false", sheet.tab_color != "" ? " tableooo:tab-color=\"%s\"".printf (sheet.tab_color) : ""));
                out_sb.append ("<table:table table:name=\"%s\" table:style-name=\"%s\"%s>".printf (esc (sheet.name), tstyle, o.get_slot (o.table_attrs, sheet)));
                out_sb.append (o.get_slot (o.table_start, sheet));
                var vcells = new Gee.HashMap<string, string> ();
                foreach (var v in sheet.validations) {
                    if (!vnames.has_key (v)) continue;
                    for (int r = v.area.r1; r <= int.min (v.area.r2, v.area.r1 + 10000); r++) {
                        for (int c = v.area.c1; c <= int.min (v.area.c2, v.area.c1 + 256); c++) vcells["%d:%d".printf (r, c)] = vnames[v];
                    }
                }
                int max_col = sheet.max_col;
                int max_row = sheet.max_row;
                foreach (var m in sheet.merges) {
                    max_col = int.max (max_col, m.c2);
                    max_row = int.max (max_row, m.r2);
                }
                foreach (var k in sheet.cells.keys) {
                    var cl = sheet.cells[k];
                    if (cl.style != 0 || cl.note != "" || cl.link != "") {
                        max_col = int.max (max_col, cl.col);
                        max_row = int.max (max_row, cl.row);
                    }
                }
                foreach (int c in sheet.col_widths.keys) max_col = int.max (max_col, int.min (c, 1023));
                foreach (int c in sheet.hidden_cols) max_col = int.max (max_col, int.min (c, 1023));
                foreach (int r in sheet.row_heights.keys) max_row = int.max (max_row, int.min (r, 65535));
                foreach (var sp in sheet.spills.values) {
                    max_row = int.max (max_row, int.min (sp.r2, 65535));
                    max_col = int.max (max_col, int.min (sp.c2, 1023));
                }
                foreach (int r in sheet.hidden_rows) max_row = int.max (max_row, int.min (r, 65535));
                foreach (var e in vcells.keys) {
                    var parts = e.split (":");
                    max_row = int.max (max_row, int.parse (parts[0]));
                    max_col = int.max (max_col, int.parse (parts[1]));
                }
                int cols = int.max (max_col + 1, 1);
                foreach (int c in sheet.outline.col_levels.keys) cols = int.max (cols, int.min (c + 2, 1024));
                foreach (int r in sheet.outline.row_levels.keys) max_row = int.max (max_row, int.min (r + 1, 65535));
                int hr1, hr2, hc1, hc2;
                if (!sheet.page.title_row_range (out hr1, out hr2) || hr2 > 65535 || !EditOds.same_level (sheet, true, hr1, hr2)) hr1 = hr2 = -1;
                if (!sheet.page.title_col_range (out hc1, out hc2) || hc2 > 1022 || !EditOds.same_level (sheet, false, hc1, hc2)) hc1 = hc2 = -1;
                if (hr2 >= 0) max_row = int.max (max_row, hr2);
                if (hc2 >= 0) cols = int.max (cols, hc2 + 1);
                int c0 = 0;
                int cgl = 0;
                while (c0 < cols) {
                    string cs = col_style (sheet, c0);
                    bool hid = sheet.hidden_cols.contains (c0);
                    int c1 = c0 + 1;
                    while (c1 < cols && c1 != hc1 && c1 != hc2 + 1 && col_style (sheet, c1) == cs && sheet.hidden_cols.contains (c1) == hid && EditOds.same_level (sheet, false, c0, c1)) c1++;
                    cgl = EditOds.transition (out_sb, sheet, false, cgl, c0);
                    if (c0 == hc1) out_sb.append ("<table:table-header-columns>");
                    out_sb.append ("<table:table-column table:style-name=\"%s\"%s%s table:default-cell-style-name=\"Default\"/>".printf (cs,
                        c1 - c0 > 1 ? " table:number-columns-repeated=\"%d\"".printf (c1 - c0) : "", hid ? " table:visibility=\"collapse\"" : ""));
                    if (hc1 >= 0 && c1 - 1 == hc2) out_sb.append ("</table:table-header-columns>");
                    c0 = c1;
                }
                EditOds.transition (out_sb, sheet, false, cgl, -1);
                out_sb.append ("<table:table-column table:style-name=\"%s\" table:number-columns-repeated=\"%d\" table:default-cell-style-name=\"Default\"/>".printf (col_style (sheet, MAX_COLS - 1), 1024 - int.min (cols, 1023)));
                int r = 0;
                int rgl = 0;
                while (r <= max_row) {
                    rgl = EditOds.transition (out_sb, sheet, true, rgl, r);
                    if (r == hr1) out_sb.append ("<table:table-header-rows>");
                    bool empty = true;
                    for (int c = 0; c < cols && empty; c++) {
                        if (sheet.get_cell (r, c) != null || sheet.merge_at (r, c) != null || vcells.has_key ("%d:%d".printf (r, c))) empty = false;
                    }
                    foreach (var sp in sheet.spills.values) if (r >= sp.r1 && r <= sp.r2) empty = false;
                    string rs = row_style (sheet, r);
                    bool hid = sheet.hidden_rows.contains (r);
                    if (empty) {
                        int r1 = r + 1;
                        while (r1 <= max_row && r1 != hr1 && r1 != hr2 + 1 && row_style (sheet, r1) == rs && sheet.hidden_rows.contains (r1) == hid && EditOds.same_level (sheet, true, r, r1)) {
                            bool e2 = true;
                            for (int c = 0; c < cols && e2; c++) {
                                if (sheet.get_cell (r1, c) != null || sheet.merge_at (r1, c) != null || vcells.has_key ("%d:%d".printf (r1, c))) e2 = false;
                            }
                            foreach (var sp in sheet.spills.values) if (r1 >= sp.r1 && r1 <= sp.r2) e2 = false;
                            if (!e2) break;
                            r1++;
                        }
                        out_sb.append ("<table:table-row table:style-name=\"%s\"%s%s><table:table-cell table:number-columns-repeated=\"%d\"/></table:table-row>".printf (rs,
                            r1 - r > 1 ? " table:number-rows-repeated=\"%d\"".printf (r1 - r) : "", hid ? " table:visibility=\"collapse\"" : "", cols));
                        if (hr1 >= 0 && r1 - 1 == hr2) out_sb.append ("</table:table-header-rows>");
                        r = r1;
                        continue;
                    }
                    out_sb.append ("<table:table-row table:style-name=\"%s\"%s>".printf (rs, hid ? " table:visibility=\"collapse\"" : ""));
                    for (int c = 0; c < cols; c++) cell_xml (out_sb, sheet, r, c, vcells);
                    out_sb.append ("</table:table-row>");
                    if (r == hr2) out_sb.append ("</table:table-header-rows>");
                    r++;
                }
                EditOds.transition (out_sb, sheet, true, rgl, -1);
                out_sb.append ("<table:table-row table:style-name=\"%s\" table:number-rows-repeated=\"%d\"><table:table-cell table:number-columns-repeated=\"%d\"/></table:table-row>".printf (row_style (sheet, MAX_ROWS - 1), 1048576 - (max_row + 1), cols));
                out_sb.append (named (sheet.names, sheet));
                out_sb.append (cond_formats (sheet));
                out_sb.append (o.get_slot (o.table_end, sheet));
                out_sb.append ("</table:table>");
            }
            out_sb.append (named (book.names, null));
            out_sb.append (database_ranges ());
            out_sb.append (o.after_tables.str);
        }

        private string calculation_settings () {
            if (!book.iterative && !book.date1904 && book.max_iterations == 100 && book.max_change == 0.001) return "";
            var sb = new StringBuilder ("<table:calculation-settings table:automatic-find-labels=\"false\" table:use-regular-expressions=\"false\" table:use-wildcards=\"true\">");
            if (book.date1904) sb.append ("<table:null-date table:date-value=\"1904-01-01\"/>");
            sb.append ("<table:iteration table:status=\"%s\" table:steps=\"%d\" table:minimum-difference=\"%s\"/>".printf (book.iterative ? "enable" : "disable", book.max_iterations, Value.format_number_general_full (book.max_change)));
            sb.append ("</table:calculation-settings>");
            return sb.str;
        }

        private string database_ranges () {
            var sb = new StringBuilder ();
            int anon = 0;
            foreach (var sheet in book.sheets) {
                if (sheet.filter == null) {
                    if (sheet.sort_state != null) {
                        var sa = sheet.sort_state.area;
                        sb.append ("<table:database-range table:name=\"__Anonymous_Sheet_DB__%d\" table:target-range-address=\"%s\"%s>%s</table:database-range>".printf (anon++, esc (Ods.plain_range (new Area (sheet, sa.r1, sa.c1, sa.r2, sa.c2))), EditOds.filter_attrs (sheet), EditOds.filter_children (sheet)));
                    }
                    continue;
                }
                bool is_table = false;
                foreach (var t in book.tables) if (t.sheet == sheet && t.area.r1 == sheet.filter.area.r1 && t.area.c1 == sheet.filter.area.c1) is_table = true;
                if (is_table) continue;
                sb.append ("<table:database-range table:name=\"__Anonymous_Sheet_DB__%d\" table:target-range-address=\"%s\" table:display-filter-buttons=\"true\"%s>%s</table:database-range>".printf (anon++, esc (Ods.plain_range (new Area (sheet, sheet.filter.area.r1, sheet.filter.area.c1, sheet.filter.area.r2, sheet.filter.area.c2))), EditOds.filter_attrs (sheet), EditOds.filter_children (sheet)));
            }
            foreach (var t in book.tables) {
                sb.append ("<table:database-range table:name=\"%s\" table:target-range-address=\"%s\" table:contains-header=\"%s\" table:display-filter-buttons=\"%s\"%s/>".printf (
                    esc (t.name), esc (Ods.plain_range (new Area (t.sheet, t.area.r1, t.area.c1, t.area.r2, t.area.c2))), t.header_row ? "true" : "false", t.filter_button ? "true" : "false",
                    t.totals_row ? " table:contains-footer=\"true\"" : ""));
            }
            if (sb.len == 0) return "";
            return "<table:database-ranges>" + sb.str + "</table:database-ranges>";
        }

        private void cell_xml (StringBuilder sb, Sheet sheet, int r, int c, Gee.HashMap<string, string> vcells) {
            var cell = sheet.get_cell (r, c);
            var merge = sheet.merge_at (r, c);
            string key = OdsOut.cell_key (sheet, r, c);
            string extra_attr = o.cell_attrs.has_key (key) ? o.cell_attrs[key] : "";
            string extra_child = o.cell_children.has_key (key) ? o.cell_children[key] : "";
            string vattr = vcells.has_key ("%d:%d".printf (r, c)) ? " table:content-validation-name=\"%s\"".printf (vcells["%d:%d".printf (r, c)]) : "";
            if (merge != null && (merge.r1 != r || merge.c1 != c)) {
                string st = cell != null && cell.style > 0 ? " table:style-name=\"%s\"".printf (cell_style_name (cell.style)) : "";
                sb.append ("<table:covered-table-cell%s%s%s/>".printf (st, vattr, extra_attr));
                return;
            }
            if ((cell == null || (cell.formula == null && cell.input == "")) && merge == null && extra_child == "" && sheet.spills.size > 0 && sheet.spill_anchor_at (r, c) != null) {
                var sv = sheet.value_at (r, c);
                string sst = cell != null && cell.style > 0 ? " table:style-name=\"%s\"".printf (cell_style_name (cell.style)) : "";
                string scol;
                string stext = NumberFormat.format_value (sv, book.styles[cell != null ? cell.style : 0].number_format, out scol, book.date1904);
                switch (sv.kind) {
                    case ValueKind.NUMBER:
                        sb.append ("<table:table-cell%s%s office:value-type=\"float\" office:value=\"%s\" calcext:value-type=\"float\">%s</table:table-cell>".printf (sst, vattr, Value.format_number_general_full (sv.number), para (stext)));
                        return;
                    case ValueKind.BOOL:
                        sb.append ("<table:table-cell%s%s office:value-type=\"boolean\" office:boolean-value=\"%s\">%s</table:table-cell>".printf (sst, vattr, sv.number != 0 ? "true" : "false", para (stext)));
                        return;
                    case ValueKind.TEXT:
                    case ValueKind.ERROR:
                        sb.append ("<table:table-cell%s%s office:value-type=\"string\">%s</table:table-cell>".printf (sst, vattr, para (stext)));
                        return;
                    default:
                        break;
                }
            }
            if (cell == null && merge == null && extra_child == "") {
                sb.append ("<table:table-cell%s%s/>".printf (vattr, extra_attr));
                return;
            }
            sb.append ("<table:table-cell");
            if (cell != null && cell.style > 0) sb.append (" table:style-name=\"%s\"".printf (cell_style_name (cell.style)));
            if (merge != null) sb.append (" table:number-columns-spanned=\"%d\" table:number-rows-spanned=\"%d\"".printf (merge.cols, merge.rows));
            sb.append (vattr);
            sb.append (extra_attr);
            string text = "";
            bool has_value = false;
            if (cell != null) {
                if (cell.formula != null) {
                    sb.append (" table:formula=\"%s\"".printf (esc (Ods.to_of (cell.formula, sheet, r, c))));
                    Area? matrix = cell.array_area;
                    if (matrix == null && sheet.spills.has_key (Sheet.key (r, c))) matrix = sheet.spills[Sheet.key (r, c)];
                    if (matrix != null && !matrix.is_single ()) sb.append (" table:number-matrix-columns-spanned=\"%d\" table:number-matrix-rows-spanned=\"%d\"".printf (matrix.cols, matrix.rows));
                }
                var v = cell.formula != null || cell.input != "" ? sheet.value_at (r, c) : Value.empty ();
                var st = book.styles[cell.style];
                string color;
                text = NumberFormat.format_value (v, st.number_format, out color, book.date1904);
                has_value = true;
                switch (v.kind) {
                    case ValueKind.NUMBER:
                        string code = st.number_format;
                        if (NumberFormat.is_date_format (code) && v.number >= 61 && !code.contains ("[h") && !code.contains ("[m") && !code.contains ("[s")) {
                            int y, mo, d, h, mi, se;
                            double fr;
                            if (DateSerial.to_ymd (v.number, out y, out mo, out d, book.date1904)) {
                                DateSerial.to_hms (v.number, out h, out mi, out se, out fr);
                                string iso = "%04d-%02d-%02d".printf (y, mo, d);
                                if (h != 0 || mi != 0 || se != 0) iso += "T%02d:%02d:%02d".printf (h, mi, se);
                                sb.append (" office:value-type=\"date\" office:date-value=\"%s\" calcext:value-type=\"date\"".printf (iso));
                            } else {
                                sb.append (" office:value-type=\"float\" office:value=\"%s\"".printf (Value.format_number_general_full (v.number)));
                            }
                        } else if (code.contains ("%") && !code.contains ("\"%")) {
                            sb.append (" office:value-type=\"percentage\" office:value=\"%s\" calcext:value-type=\"percentage\"".printf (Value.format_number_general_full (v.number)));
                        } else {
                            sb.append (" office:value-type=\"float\" office:value=\"%s\" calcext:value-type=\"float\"".printf (Value.format_number_general_full (v.number)));
                        }
                        break;
                    case ValueKind.BOOL:
                        sb.append (" office:value-type=\"boolean\" office:boolean-value=\"%s\" calcext:value-type=\"boolean\"".printf (v.number != 0 ? "true" : "false"));
                        break;
                    case ValueKind.ERROR:
                        sb.append (" office:value-type=\"string\" office:string-value=\"\" calcext:value-type=\"error\"");
                        break;
                    case ValueKind.TEXT:
                        sb.append (" office:value-type=\"string\" calcext:value-type=\"string\"");
                        break;
                    default:
                        has_value = false;
                        break;
                }
            }
            sb.append (">");
            if (cell != null && cell.note != "") {
                sb.append ("<office:annotation office:display=\"false\"><dc:creator>%s</dc:creator>%s</office:annotation>".printf (
                    esc (cell.note_author != "" ? cell.note_author : XlsxExtras.default_author ()), para (cell.note)));
            }
            sb.append (extra_child);
            if (has_value) {
                if (cell.link != "") {
                    var lines = text.split ("\n");
                    for (int i = 0; i < lines.length; i++) sb.append ("<text:p><text:a xlink:href=\"%s\" xlink:type=\"simple\">%s</text:a></text:p>".printf (esc (odf_link (cell.link)), spaces (lines[i])));
                } else {
                    sb.append (para (text));
                }
            }
            sb.append ("</table:table-cell>");
        }

        private string content_xml () {
            var b = new StringBuilder ();
            body (b);
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-content " + Ods.NAMESPACES + " office:version=\"1.3\"><office:automatic-styles>" + o.auto_styles.str + "</office:automatic-styles><office:body><office:spreadsheet" + EditOds.spreadsheet_attrs (book) + ">" + b.str + "</office:spreadsheet></office:body></office:document-content>";
        }

        private string default_styles () {
            return "<style:default-style style:family=\"table-cell\"><style:paragraph-properties style:tab-stop-distance=\"1.25cm\"/><style:text-properties style:font-name=\"Liberation Sans\" fo:font-size=\"11pt\"/></style:default-style><style:style style:name=\"Default\" style:family=\"table-cell\"/>";
        }

        private string styles_xml () {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-styles " + Ods.NAMESPACES + " office:version=\"1.3\"><office:font-face-decls><style:font-face style:name=\"Liberation Sans\" svg:font-family=\"&apos;Liberation Sans&apos;\" style:font-family-generic=\"swiss\" style:font-pitch=\"variable\"/></office:font-face-decls><office:styles>" + default_styles () + o.common_styles.str + "</office:styles><office:automatic-styles>" + o.styles_auto.str + "</office:automatic-styles><office:master-styles>" + master () + "</office:master-styles></office:document-styles>";
        }

        private string master () {
            if (o.master_styles.len > 0) return o.master_styles.str;
            return "<style:master-page style:name=\"Default\"/>";
        }

        private string settings_xml () {
            var sb = new StringBuilder ("<config:config-item-set config:name=\"ooo:view-settings\"><config:config-item-map-indexed config:name=\"Views\"><config:config-item-map-entry><config:config-item config:name=\"ViewId\" config:type=\"string\">view1</config:config-item><config:config-item-map-named config:name=\"Tables\">");
            foreach (var s in book.sheets) {
                sb.append ("<config:config-item-map-entry config:name=\"%s\">".printf (esc (s.name)));
                if (s.freeze_cols > 0) {
                    sb.append ("<config:config-item config:name=\"HorizontalSplitMode\" config:type=\"short\">2</config:config-item><config:config-item config:name=\"HorizontalSplitPosition\" config:type=\"int\">%d</config:config-item><config:config-item config:name=\"PositionRight\" config:type=\"int\">%d</config:config-item>".printf (s.freeze_cols, s.freeze_cols));
                } else {
                    sb.append ("<config:config-item config:name=\"HorizontalSplitMode\" config:type=\"short\">0</config:config-item><config:config-item config:name=\"HorizontalSplitPosition\" config:type=\"int\">0</config:config-item><config:config-item config:name=\"PositionRight\" config:type=\"int\">0</config:config-item>");
                }
                if (s.freeze_rows > 0) {
                    sb.append ("<config:config-item config:name=\"VerticalSplitMode\" config:type=\"short\">2</config:config-item><config:config-item config:name=\"VerticalSplitPosition\" config:type=\"int\">%d</config:config-item><config:config-item config:name=\"PositionBottom\" config:type=\"int\">%d</config:config-item>".printf (s.freeze_rows, s.freeze_rows));
                } else {
                    sb.append ("<config:config-item config:name=\"VerticalSplitMode\" config:type=\"short\">0</config:config-item><config:config-item config:name=\"VerticalSplitPosition\" config:type=\"int\">0</config:config-item><config:config-item config:name=\"PositionBottom\" config:type=\"int\">0</config:config-item>");
                }
                sb.append ("<config:config-item config:name=\"ActiveSplitRange\" config:type=\"short\">%d</config:config-item>".printf (s.freeze_rows > 0 ? (s.freeze_cols > 0 ? 3 : 2) : (s.freeze_cols > 0 ? 3 : 2)));
                sb.append ("<config:config-item config:name=\"PositionLeft\" config:type=\"int\">0</config:config-item><config:config-item config:name=\"PositionTop\" config:type=\"int\">0</config:config-item>");
                sb.append ("<config:config-item config:name=\"ShowGrid\" config:type=\"boolean\">%s</config:config-item>".printf (s.show_grid ? "true" : "false"));
                sb.append (o.get_slot (o.table_settings, s));
                sb.append ("</config:config-item-map-entry>");
            }
            sb.append ("</config:config-item-map-named><config:config-item config:name=\"ActiveTable\" config:type=\"string\">%s</config:config-item>".printf (esc (book.sheets.size > 0 ? book.sheets[0].name : "")));
            bool all_grid = true;
            foreach (var s in book.sheets) if (!s.show_grid) all_grid = false;
            sb.append ("<config:config-item config:name=\"ShowGrid\" config:type=\"boolean\">%s</config:config-item>".printf (all_grid ? "true" : "false"));
            sb.append (o.settings_view.str);
            sb.append ("</config:config-item-map-entry></config:config-item-map-indexed></config:config-item-set>");
            sb.append ("<config:config-item-set config:name=\"ooo:configuration-settings\"><config:config-item config:name=\"AutoCalculate\" config:type=\"boolean\">%s</config:config-item></config:config-item-set>".printf (book.manual_calc ? "false" : "true"));
            return sb.str;
        }

        private string meta_xml () {
            var p = book.properties;
            var now = new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%S");
            var sb = new StringBuilder ("<meta:generator>Singularity Spreadsheet</meta:generator>");
            if (p.has_key ("title")) sb.append ("<dc:title>%s</dc:title>".printf (esc (p["title"])));
            if (p.has_key ("subject")) sb.append ("<dc:subject>%s</dc:subject>".printf (esc (p["subject"])));
            if (p.has_key ("description")) sb.append ("<dc:description>%s</dc:description>".printf (esc (p["description"])));
            if (p.has_key ("keywords")) sb.append ("<meta:keyword>%s</meta:keyword>".printf (esc (p["keywords"])));
            sb.append ("<meta:initial-creator>%s</meta:initial-creator>".printf (esc (p.has_key ("creator") ? p["creator"] : XlsxExtras.default_author ())));
            sb.append ("<dc:creator>%s</dc:creator>".printf (esc (XlsxExtras.default_author ())));
            sb.append ("<meta:creation-date>%s</meta:creation-date><dc:date>%s</dc:date>".printf (esc (p.has_key ("created") ? p["created"] : now), now));
            return sb.str;
        }

        public string flat () {
            var b = new StringBuilder ();
            o.flat = true;
            body (b);
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document " + Ods.NAMESPACES + " office:version=\"1.3\" office:mimetype=\"application/vnd.oasis.opendocument.spreadsheet\"><office:meta>" + meta_xml () + "</office:meta><office:settings>" + settings_xml () + "</office:settings><office:font-face-decls><style:font-face style:name=\"Liberation Sans\" svg:font-family=\"&apos;Liberation Sans&apos;\" style:font-family-generic=\"swiss\" style:font-pitch=\"variable\"/></office:font-face-decls><office:styles>" + default_styles () + o.common_styles.str + "</office:styles><office:automatic-styles>" + o.auto_styles.str + o.styles_auto.str + "</office:automatic-styles><office:master-styles>" + master () + "</office:master-styles><office:body><office:spreadsheet" + EditOds.spreadsheet_attrs (book) + ">" + b.str + "</office:spreadsheet></office:body></office:document>";
        }

        public uint8[] package (bool template) throws Error {
            string mime = template ? "application/vnd.oasis.opendocument.spreadsheet-template" : "application/vnd.oasis.opendocument.spreadsheet";
            string content = content_xml ();
            string styles = styles_xml ();
            var zip = new ZipWriter ();
            zip.add_text ("mimetype", mime, false);
            zip.add_text ("META-INF/manifest.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.3\"><manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.3\" manifest:media-type=\"%s\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"styles.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"meta.xml\" manifest:media-type=\"text/xml\"/><manifest:file-entry manifest:full-path=\"settings.xml\" manifest:media-type=\"text/xml\"/>%s</manifest:manifest>".printf (mime, o.manifest.str));
            zip.add_text ("content.xml", content);
            zip.add_text ("styles.xml", styles);
            zip.add_text ("meta.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-meta " + Ods.NAMESPACES + " office:version=\"1.3\"><office:meta>" + meta_xml () + "</office:meta></office:document-meta>");
            zip.add_text ("settings.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-settings " + Ods.NAMESPACES + " office:version=\"1.3\"><office:settings>" + settings_xml () + "</office:settings></office:document-settings>");
            foreach (var e in o.files.entries) zip.add (e.key, e.value.get_data ());
            return zip.finish ();
        }
    }
}
