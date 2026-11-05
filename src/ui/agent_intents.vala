namespace Singularity.Apps.Spreadsheet {

    internal class SheetIntents : Object {
        private const int READ_LIMIT = 5000;
        private const string RANGE = "{\"type\":\"object\",\"properties\":{\"range\":{\"type\":\"string\"},\"sheet\":{\"type\":\"string\"}},\"required\":[\"range\"]}";

        private static string text (Json.Object args, string key) {
            return args.has_member (key) && args.get_member (key).get_value_type () == typeof (string) ? args.get_string_member (key) : "";
        }

        private static bool flag (Json.Object args, string key, out bool value) {
            value = false;
            if (!args.has_member (key) || args.get_member (key).get_value_type () != typeof (bool)) return false;
            value = args.get_boolean_member (key);
            return true;
        }

        private static SpreadsheetWindow window (SpreadsheetApp app) throws Error {
            var w = app.get_active_window () as SpreadsheetWindow;
            if (w == null || w.doc == null) {
                foreach (var x in app.get_windows ()) {
                    if (x is SpreadsheetWindow && ((SpreadsheetWindow) x).doc != null) {
                        w = (SpreadsheetWindow) x;
                        break;
                    }
                }
            }
            if (w == null) {
                foreach (var x in app.get_windows ()) {
                    if (x is SpreadsheetWindow) {
                        w = (SpreadsheetWindow) x;
                        break;
                    }
                }
            }
            if (w == null) {
                app.activate ();
                w = app.get_active_window () as SpreadsheetWindow;
                if (w == null) foreach (var x in app.get_windows ()) if (x is SpreadsheetWindow) w = (SpreadsheetWindow) x;
                if (w == null) throw new IOError.FAILED ("the window did not open");
            }
            if (w.doc == null) w.new_document ();
            if (w.doc == null || w.grid == null) throw new IOError.FAILED ("Spreadsheet has no open workbook");
            return w;
        }

        private static Sheet sheet_of (SpreadsheetWindow w, Json.Object args) throws Error {
            string name = text (args, "sheet");
            if (name == "") return w.grid.sheet;
            foreach (var s in w.doc.book.sheets) if (s.name == name) return s;
            throw new IOError.NOT_FOUND ("no sheet named %s", name);
        }

        private static Area area_of (SpreadsheetWindow w, Json.Object args) throws Error {
            var s = sheet_of (w, args);
            string r = text (args, "range");
            if (r == "") throw new IOError.INVALID_ARGUMENT ("give a range such as A1:C10");
            var a = Area.parse (r, s);
            if (a == null) throw new IOError.INVALID_ARGUMENT ("%s is not a range such as A1:C10", r);
            if (a.sheet == null) a.sheet = s;
            return a;
        }

        private static void show (SpreadsheetWindow w, Area a) {
            if (a.sheet != null && a.sheet != w.grid.sheet) {
                w.grid.show_sheet (a.sheet);
                w.doc.sheets_changed ();
            }
            w.grid.select_area (a);
        }

        private static Json.Node cells (Area a) {
            var s = a.sheet;
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("sheet").add_string_value (s.name);
            b.set_member_name ("range").add_string_value (a.to_string ());
            int r2 = int.min (a.r2, s.max_row);
            int c2 = int.min (a.c2, s.max_col);
            b.set_member_name ("rows");
            b.begin_array ();
            int count = 0;
            bool cut = false;
            for (int r = a.r1; r <= r2 && !cut; r++) {
                b.begin_array ();
                for (int c = a.c1; c <= c2; c++) {
                    if (++count > READ_LIMIT) {
                        cut = true;
                        break;
                    }
                    string input = s.input_at (r, c);
                    string shown = s.value_at (r, c).display ();
                    if (input != "" && input.has_prefix ("=")) {
                        b.begin_object ();
                        b.set_member_name ("formula").add_string_value (input);
                        b.set_member_name ("value").add_string_value (shown);
                        b.end_object ();
                    } else {
                        b.add_string_value (shown);
                    }
                }
                b.end_array ();
            }
            b.end_array ();
            if (cut) b.set_member_name ("truncated").add_boolean_value (true);
            b.end_object ();
            return b.get_root ();
        }

        private static string cell_text (Json.Node node) {
            var t = node.get_value_type ();
            if (t == typeof (string)) return node.get_string ();
            if (t == typeof (bool)) return node.get_boolean () ? "TRUE" : "FALSE";
            if (t == typeof (int64)) return node.get_int ().to_string ();
            if (t == typeof (double)) return Value.format_number_general_full (node.get_double ());
            return "";
        }

        private static Json.Node verified (Json.Node n, bool ok) {
            n.get_object ().set_boolean_member ("verified", ok);
            return n;
        }

        private static int header_index (Sheet s, Area a, string name) {
            for (int c = a.c1; c <= a.c2; c++) if (s.value_at (a.r1, c).display ().down () == name.down ()) return c - a.c1;
            int col = Address.column_index (name.up ());
            if (col >= a.c1 && col <= a.c2) return col - a.c1;
            return -1;
        }

        internal static void install (SpreadsheetApp app) {
            var agent = app.agent;

            agent.add_intent ("sheet_context", "Read the open workbook: its sheets, the active sheet, the selected range and the used range of every sheet.",
                "{\"type\":\"object\",\"properties\":{}}",
                Singularity.AppIntentRisk.READ, (args) => {
                    var w = window (app);
                    var b = new Json.Builder ();
                    b.begin_object ();
                    b.set_member_name ("file").add_string_value (w.doc.path ?? "");
                    b.set_member_name ("active_sheet").add_string_value (w.grid.sheet.name);
                    b.set_member_name ("selection").add_string_value (w.grid.selection.to_string ());
                    b.set_member_name ("sheets");
                    b.begin_array ();
                    foreach (var s in w.doc.book.sheets) {
                        b.begin_object ();
                        b.set_member_name ("name").add_string_value (s.name);
                        string used = s.max_row >= 0 && s.max_col >= 0 ? new Area (s, 0, 0, s.max_row, s.max_col).to_string () : "";
                        b.set_member_name ("used_range").add_string_value (used);
                        b.end_object ();
                    }
                    b.end_array ();
                    b.end_object ();
                    return b.get_root ();
                });

            agent.add_intent ("sheet_read_range", "Read the values of a range such as A1:D20, row by row; formula cells come with their formula and calculated value.",
                RANGE, Singularity.AppIntentRisk.READ, (args) => cells (area_of (window (app), args)));

            agent.add_intent ("sheet_write_range", "Write values or formulas into the sheet starting at the top-left cell of range, one inner array per row (formulas start with =). One undo step. Answers with the calculated values read back.",
                "{\"type\":\"object\",\"properties\":{\"range\":{\"type\":\"string\"},\"sheet\":{\"type\":\"string\"},\"values\":{\"type\":\"array\",\"items\":{\"type\":\"array\",\"items\":{\"type\":[\"string\",\"number\",\"boolean\"]}}}},\"required\":[\"range\",\"values\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var start = area_of (w, args);
                    var rows = args.get_array_member ("values");
                    if (rows.get_length () == 0) throw new IOError.INVALID_ARGUMENT ("values is empty");
                    int width = 0;
                    for (uint i = 0; i < rows.get_length (); i++) width = int.max (width, (int) rows.get_array_element (i).get_length ());
                    var target = new Area (start.sheet, start.r1, start.c1, start.r1 + (int) rows.get_length () - 1, start.c1 + int.max (width, 1) - 1);
                    var s = target.sheet;
                    var expected = new Gee.ArrayList<string> ();
                    w.doc.begin_area (_("Typing"), s, target);
                    for (uint i = 0; i < rows.get_length (); i++) {
                        var row = rows.get_array_element (i);
                        for (uint j = 0; j < row.get_length (); j++) {
                            var node = row.get_element (j);
                            string v = cell_text (node);
                            s.set_input (target.r1 + (int) i, target.c1 + (int) j, v);
                            expected.add (v);
                        }
                    }
                    w.doc.commit ();
                    w.doc.calculate_now ();
                    show (w, target);
                    bool ok = true;
                    int k = 0;
                    for (uint i = 0; i < rows.get_length (); i++) {
                        var row = rows.get_array_element (i);
                        for (uint j = 0; j < row.get_length (); j++) {
                            if (s.input_at (target.r1 + (int) i, target.c1 + (int) j) != expected[k]) ok = false;
                            k++;
                        }
                    }
                    return verified (cells (target), ok);
                });

            agent.add_intent ("sheet_format_range", "Format a range: bold, italic, underline, color and fill (#rrggbb), number_format (such as 0.00, #,##0, 0%, dd/mm/yyyy, € #,##0.00), halign (left, center, right), wrap, font_size, and borders (all, outer, inner, top, bottom, left, right, none).",
                "{\"type\":\"object\",\"properties\":{\"range\":{\"type\":\"string\"},\"sheet\":{\"type\":\"string\"},\"bold\":{\"type\":\"boolean\"},\"italic\":{\"type\":\"boolean\"},\"underline\":{\"type\":\"boolean\"},\"wrap\":{\"type\":\"boolean\"},\"color\":{\"type\":\"string\"},\"fill\":{\"type\":\"string\"},\"number_format\":{\"type\":\"string\"},\"halign\":{\"type\":\"string\"},\"font_size\":{\"type\":\"number\"},\"borders\":{\"type\":\"string\"}},\"required\":[\"range\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var a = area_of (w, args);
                    bool bold, italic, underline, wrap;
                    bool has_bold = flag (args, "bold", out bold);
                    bool has_italic = flag (args, "italic", out italic);
                    bool has_underline = flag (args, "underline", out underline);
                    bool has_wrap = flag (args, "wrap", out wrap);
                    string color = text (args, "color"), fill = text (args, "fill"), fmt = text (args, "number_format"), align = text (args, "halign");
                    double size = args.has_member ("font_size") ? args.get_double_member ("font_size") : 0;
                    w.doc.edit_style (a.sheet, a, _("Format Cells"), (st) => {
                        if (has_bold) st.bold = bold;
                        if (has_italic) st.italic = italic;
                        if (has_underline) st.underline = underline;
                        if (has_wrap) st.wrap = wrap;
                        if (color != "") st.color = color;
                        if (fill != "") st.fill = fill;
                        if (fmt != "") st.number_format = fmt;
                        if (size > 0) st.font_size = size;
                        if (align == "left") st.halign = HAlign.LEFT;
                        else if (align == "center") st.halign = HAlign.CENTER;
                        else if (align == "right") st.halign = HAlign.RIGHT;
                    });
                    string borders = text (args, "borders");
                    if (borders != "") w.doc.edit_borders (a.sheet, a, borders, borders == "none" ? BorderStyle.NONE : BorderStyle.THIN, "");
                    show (w, a);
                    var n = cells (a);
                    var st = a.sheet.style_at (a.r1, a.c1);
                    bool ok = (!has_bold || st.bold == bold) && (fmt == "" || st.number_format == fmt) && (fill == "" || st.fill == fill);
                    return verified (n, ok);
                });

            agent.add_intent ("sheet_sort", "Sort a range by one or more columns, given by header text or column letter. header says the first row holds headers and stays on top.",
                "{\"type\":\"object\",\"properties\":{\"range\":{\"type\":\"string\"},\"sheet\":{\"type\":\"string\"},\"header\":{\"type\":\"boolean\"},\"keys\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"column\":{\"type\":\"string\"},\"descending\":{\"type\":\"boolean\"}},\"required\":[\"column\"]}}},\"required\":[\"range\",\"keys\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var a = area_of (w, args);
                    bool header;
                    flag (args, "header", out header);
                    var keys = new Gee.ArrayList<SortKey> ();
                    var list = args.get_array_member ("keys");
                    for (uint i = 0; i < list.get_length (); i++) {
                        var k = list.get_object_element (i);
                        int idx = header_index (a.sheet, a, k.get_string_member ("column"));
                        if (idx < 0) throw new IOError.NOT_FOUND ("no column %s in %s", k.get_string_member ("column"), a.to_string ());
                        bool desc = k.has_member ("descending") && k.get_boolean_member ("descending");
                        keys.add (new SortKey (a.c1 + idx, !desc));
                    }
                    w.doc.sort (a.sheet, a, keys, header);
                    show (w, a);
                    return cells (a);
                });

            agent.add_intent ("sheet_filter", "Turn the filter buttons on or off for a range with a header row.",
                RANGE, Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var a = area_of (w, args);
                    w.doc.toggle_filter (a.sheet, a);
                    show (w, a);
                    return cells (a);
                });

            agent.add_intent ("sheet_chart_create", "Insert a chart drawn from a range with labels in the first row and column. kind is column, bar, line, area, pie, doughnut, scatter or radar.",
                "{\"type\":\"object\",\"properties\":{\"range\":{\"type\":\"string\"},\"sheet\":{\"type\":\"string\"},\"kind\":{\"type\":\"string\"},\"title\":{\"type\":\"string\"}},\"required\":[\"range\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var a = area_of (w, args);
                    var ch = new Chart (a);
                    string kind = text (args, "kind");
                    if (kind != "") {
                        if (!(kind in Chart.KINDS)) throw new IOError.INVALID_ARGUMENT ("kind must be one of %s", string.joinv (", ", Chart.KINDS));
                        ch.kind = kind;
                    }
                    ch.title = text (args, "title");
                    ch.x = 60 + (a.c2 + 2) * 20;
                    w.doc.add_chart (a.sheet, ch);
                    show (w, a);
                    var b = new Json.Builder ();
                    b.begin_object ();
                    b.set_member_name ("sheet").add_string_value (a.sheet.name);
                    b.set_member_name ("source").add_string_value (a.to_string ());
                    b.set_member_name ("kind").add_string_value (ch.kind);
                    b.set_member_name ("charts_on_sheet").add_int_value (a.sheet.charts.size);
                    b.end_object ();
                    return verified (b.get_root (), a.sheet.charts.contains (ch));
                });

            agent.add_intent ("sheet_pivot_create", "Build a pivot table on a new sheet from a range with a header row. rows and cols name header fields; values name the field and agg (sum, count, average, max, min).",
                "{\"type\":\"object\",\"properties\":{\"range\":{\"type\":\"string\"},\"sheet\":{\"type\":\"string\"},\"rows\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"cols\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}},\"values\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"properties\":{\"field\":{\"type\":\"string\"},\"agg\":{\"type\":\"string\"}},\"required\":[\"field\"]}}},\"required\":[\"range\",\"values\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var a = area_of (w, args);
                    if (a.rows < 2) throw new IOError.INVALID_ARGUMENT ("the range needs a header row and at least one row of data");
                    var book = w.doc.book;
                    w.doc.begin_book (_("Insert PivotTable"), a.sheet);
                    var ts = book.add_sheet (book.unique_sheet_name (_("Pivot")), book.sheets.index_of (a.sheet));
                    var p = new PivotTable (Analysis.data (book).unique_pivot_name (), ts, 2, 0);
                    p.source = a;
                    p.source_sheet = a.sheet;
                    string[] groups = { "rows", "cols" };
                    foreach (string g in groups) {
                        if (!args.has_member (g)) continue;
                        var arr = args.get_array_member (g);
                        for (uint i = 0; i < arr.get_length (); i++) {
                            string name = arr.get_string_element (i);
                            int idx = header_index (a.sheet, a, name);
                            if (idx < 0) {
                                w.doc.commit ();
                                throw new IOError.NOT_FOUND ("no column %s in the header row", name);
                            }
                            var f = new PivotField (idx, a.sheet.value_at (a.r1, a.c1 + idx).display ());
                            if (g == "rows") p.rows.add (f);
                            else p.cols.add (f);
                        }
                    }
                    var vals = args.get_array_member ("values");
                    for (uint i = 0; i < vals.get_length (); i++) {
                        var v = vals.get_object_element (i);
                        string name = v.get_string_member ("field");
                        int idx = header_index (a.sheet, a, name);
                        if (idx < 0) {
                            w.doc.commit ();
                            throw new IOError.NOT_FOUND ("no column %s in the header row", name);
                        }
                        string agg = v.has_member ("agg") ? v.get_string_member ("agg").down () : "sum";
                        p.values.add (new PivotValue (idx, a.sheet.value_at (a.r1, a.c1 + idx).display (), PivotAgg.from_key (agg)));
                    }
                    Analysis.data (book).pivots.add (p);
                    var output = Analysis.write_pivot (book, p);
                    w.doc.commit ();
                    w.doc.sheets_changed ();
                    if (output == null) throw new IOError.FAILED (p.error != "" ? p.error : "the pivot table came out empty");
                    show (w, output);
                    return verified (cells (output), true);
                });

            agent.add_intent ("sheet_add", "Add a new sheet with a name and make it the active one.",
                "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var book = w.doc.book;
                    string name = text (args, "name");
                    if (name == "") name = book.unique_sheet_name (_("Sheet"));
                    foreach (var s in book.sheets) if (s.name == name) throw new IOError.EXISTS ("a sheet named %s already exists", name);
                    w.doc.begin_book (_("Insert Sheet"), w.grid.sheet);
                    var ns = book.add_sheet (name, book.sheets.size);
                    w.doc.commit ();
                    w.grid.show_sheet (ns);
                    w.doc.sheets_changed ();
                    var b = new Json.Builder ();
                    b.begin_object ();
                    b.set_member_name ("sheet").add_string_value (ns.name);
                    b.end_object ();
                    return verified (b.get_root (), book.sheets.contains (ns));
                });

            agent.add_intent ("sheet_save", "Save the workbook without asking. path is optional: absolute, or a file name placed in Documents; its extension picks the format (xlsx, ods, csv). Without path it saves to its own file, or to Documents when it has none.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    var w = window (app);
                    string saved = w.save_quietly (text (args, "path"));
                    var b = new Json.Builder ();
                    b.begin_object ();
                    b.set_member_name ("path").add_string_value (saved);
                    b.end_object ();
                    return verified (b.get_root (), FileUtils.test (saved, FileTest.EXISTS));
                });
        }
    }
}
