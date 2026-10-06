using Singularity.Apps.Spreadsheet;

string tmp_path (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "ss-fid-%d-%s".printf (Random.int_range (0, 1000000), name));
}

void same (string what, string expected, string got) {
    if (expected != got) {
        stderr.printf ("FAIL %s: expected [%s] got [%s]\n", what, expected, got);
        Test.fail ();
    }
}

Workbook sample () {
    var book = new Workbook ();
    var s = book.add_sheet ("Data");
    var o = book.add_sheet ("Other Sheet");
    s.set_input (0, 0, "Name");
    s.set_input (0, 1, "Amount");
    s.set_input (1, 0, "Alpha  beta");
    s.set_input (1, 1, "1234.5");
    s.set_input (2, 0, "Gamma");
    s.set_input (2, 1, "-42");
    s.set_input (3, 1, "=SUM(B2:B3)");
    s.set_input (4, 0, "Link");
    s.set_input (5, 0, "Inside");
    o.set_input (0, 0, "7");
    s.ensure (1, 0).note = "First note\nsecond line";
    s.ensure (1, 0).note_author = "Ada";
    s.ensure (6, 3).note = "note on empty cell";
    s.get_cell (4, 0).link = "https://example.com/a?b=1&c=2";
    s.get_cell (5, 0).link = "#'Other Sheet'!A1";
    var money = new CellStyle ();
    money.number_format = "#,##0.00;[Red]-#,##0.00";
    money.bold = true;
    money.italic = true;
    money.underline = true;
    money.color = "#1f4e79";
    money.fill = "#ffe699";
    money.font_size = 14;
    money.font_family = "DejaVu Serif";
    money.halign = HAlign.RIGHT;
    money.valign = VAlign.TOP;
    money.wrap = true;
    money.top = new Border (BorderStyle.THIN, "#ff0000");
    money.bottom = new Border (BorderStyle.DOUBLE, "");
    money.left = new Border (BorderStyle.DASHED, "#00ff00");
    money.right = new Border (BorderStyle.THICK, "");
    int mi = book.intern (money);
    s.set_style (1, 1, mi);
    s.set_style (2, 1, mi);
    string[] codes = { "0.00%", "yyyy-mm-dd", "h:mm:ss", "0.00E+00", "# ?/?", "[$€-410] #,##0.00", "@", "d mmmm yyyy", "#,##0" };
    for (int i = 0; i < codes.length; i++) {
        var st = new CellStyle ();
        st.number_format = codes[i];
        s.set_input (10 + i, 0, "0.25");
        s.set_style (10 + i, 0, book.intern (st));
    }
    s.col_widths[0] = 200;
    s.row_heights[2] = 50;
    s.hidden_cols.add (5);
    s.hidden_rows.add (8);
    s.merges.add (new Area (s, 20, 0, 21, 2));
    s.set_input (20, 0, "Merged");
    s.freeze_rows = 1;
    s.freeze_cols = 1;
    s.tab_color = "#ff8800";
    var cf = new CondFormat (new Area (s, 1, 1, 3, 1), CondKind.GREATER);
    cf.a = "100";
    cf.style = mi;
    s.cond_formats.add (cf);
    s.cond_formats.add (new CondFormat (new Area (s, 1, 1, 3, 1), CondKind.DATA_BAR));
    var cs = new CondFormat (new Area (s, 10, 0, 18, 0), CondKind.COLOR_SCALE);
    s.cond_formats.add (cs);
    var bt = new CondFormat (new Area (s, 1, 1, 3, 1), CondKind.BETWEEN);
    bt.a = "1";
    bt.b = "5";
    bt.style = mi;
    s.cond_formats.add (bt);
    var v = new Validation (new Area (s, 1, 2, 4, 2));
    v.list_source = "\"red,green,blue\"";
    v.message = "Pick a colour";
    s.validations.add (v);
    var w = new Validation (new Area (s, 1, 3, 2, 3));
    w.kind = ValidationKind.WHOLE;
    w.op = ValidationOp.BETWEEN;
    w.formula1 = "1";
    w.formula2 = "10";
    w.error_message = "Too big";
    s.validations.add (w);
    book.names["Total"] = "Data!$B$4";
    s.names["Local"] = "Data!$A$2";
    book.properties["title"] = "Quarterly";
    book.properties["subject"] = "Tests";
    book.recalculate ();
    return book;
}

void check_book (string fmt, Workbook back) {
    var s = back.find_sheet ("Data");
    if (s == null) {
        stderr.printf ("FAIL %s: no Data sheet\n", fmt);
        Test.fail ();
        return;
    }
    same (fmt + " note", "First note\nsecond line", s.get_cell (1, 0).note);
    same (fmt + " note author", "Ada", s.get_cell (1, 0).note_author);
    var empty_note = s.get_cell (6, 3);
    same (fmt + " empty note", "note on empty cell", empty_note != null ? empty_note.note : "");
    same (fmt + " text spaces", "Alpha  beta", s.value_at (1, 0).display ());
    same (fmt + " link", "https://example.com/a?b=1&c=2", s.get_cell (4, 0).link);
    same (fmt + " internal link", "#'Other Sheet'!A1", s.get_cell (5, 0).link);
    same (fmt + " sum", "1192.5", s.value_at (3, 1).display ());
    var st = back.styles[s.get_cell (1, 1).style];
    same (fmt + " numfmt", "#,##0.00;[Red]-#,##0.00", st.number_format);
    same (fmt + " bold", "true", st.bold.to_string ());
    same (fmt + " italic", "true", st.italic.to_string ());
    same (fmt + " underline", "true", st.underline.to_string ());
    same (fmt + " color", "#1f4e79", st.color);
    same (fmt + " fill", "#ffe699", st.fill);
    same (fmt + " size", "14", Singularity.Apps.Spreadsheet.Value.format_number_general_full (st.font_size));
    same (fmt + " family", "DejaVu Serif", st.font_family);
    same (fmt + " halign", "%d".printf (HAlign.RIGHT), "%d".printf (st.halign));
    same (fmt + " valign", "%d".printf (VAlign.TOP), "%d".printf (st.valign));
    same (fmt + " wrap", "true", st.wrap.to_string ());
    same (fmt + " top", "%d#ff0000".printf (BorderStyle.THIN), "%d%s".printf (st.top.style, st.top.color));
    same (fmt + " bottom", "%d".printf (BorderStyle.DOUBLE), "%d".printf (st.bottom.style));
    same (fmt + " left", "%d#00ff00".printf (BorderStyle.DASHED), "%d%s".printf (st.left.style, st.left.color));
    same (fmt + " right", "%d".printf (BorderStyle.THICK), "%d".printf (st.right.style));
    string[] codes = { "0.00%", "yyyy-mm-dd", "h:mm:ss", "0.00E+00", "# ?/?", "[$€-410] #,##0.00", "@", "d mmmm yyyy", "#,##0" };
    for (int i = 0; i < codes.length; i++) {
        var c = s.get_cell (10 + i, 0);
        same (fmt + " code " + codes[i], codes[i], c != null ? back.styles[c.style].number_format : "");
        same (fmt + " value " + codes[i], "0.25", c != null ? Singularity.Apps.Spreadsheet.Value.format_number_general_full (c.value.number) : "");
    }
    same (fmt + " col width", "true", ((s.col_widths[0] - 200).abs () <= 2).to_string ());
    same (fmt + " row height", "true", (s.row_heights.has_key (2) && (s.row_heights[2] - 50).abs () <= 2).to_string ());
    same (fmt + " hidden col", "true", s.hidden_cols.contains (5).to_string ());
    same (fmt + " hidden row", "true", s.hidden_rows.contains (8).to_string ());
    same (fmt + " merges", "1", s.merges.size.to_string ());
    if (s.merges.size == 1) same (fmt + " merge", "A21:C22", s.merges[0].to_string ());
    same (fmt + " freeze", "1/1", "%d/%d".printf (s.freeze_rows, s.freeze_cols));
    same (fmt + " tab", "#ff8800", s.tab_color);
    same (fmt + " cf count", "4", s.cond_formats.size.to_string ());
    if (s.cond_formats.size == 4) {
        same (fmt + " cf kind", "%d100".printf (CondKind.GREATER), "%d%s".printf (s.cond_formats[0].kind, s.cond_formats[0].a));
        same (fmt + " cf style", "true", back.styles[s.cond_formats[0].style].fill == "#ffe699" ? "true" : "false");
        same (fmt + " cf bar", "%d".printf (CondKind.DATA_BAR), "%d".printf (s.cond_formats[1].kind));
        same (fmt + " cf scale", "%d".printf (CondKind.COLOR_SCALE), "%d".printf (s.cond_formats[2].kind));
        same (fmt + " cf between", "%d1/5".printf (CondKind.BETWEEN), "%d%s/%s".printf (s.cond_formats[3].kind, s.cond_formats[3].a, s.cond_formats[3].b));
        same (fmt + " cf area", "B2:B4", s.cond_formats[0].area.to_string ());
    }
    same (fmt + " validations", "2", s.validations.size.to_string ());
    foreach (var v in s.validations) {
        if (v.kind == ValidationKind.LIST) {
            same (fmt + " list", "\"red,green,blue\"", v.list_source);
            same (fmt + " list area", "C2:C5", v.area.to_string ());
            same (fmt + " list msg", "Pick a colour", v.message);
        } else {
            same (fmt + " whole", "%d 1 10".printf (ValidationKind.WHOLE), "%d %s %s".printf (v.kind, v.formula1, v.formula2));
            same (fmt + " whole err", "Too big", v.error_message);
        }
    }
    same (fmt + " name", "Data!$B$4", back.names.has_key ("Total") ? back.names["Total"].replace ("=", "") : "");
    same (fmt + " local name", "Data!$A$2", s.names.has_key ("Local") ? s.names["Local"].replace ("=", "") : "");
    same (fmt + " title", "Quarterly", back.properties["title"] ?? "");
}

void roundtrip (string ext) {
    LocaleInfo.set_c ();
    var book = sample ();
    string path = tmp_path ("book." + ext);
    try {
        if (ext == "xlsx") XlsxWriter.save (book, path);
        else Ods.save (book, path);
        var back = ext == "xlsx" ? Xlsx.load (path) : Ods.load (path);
        check_book (ext, back);
        string path2 = tmp_path ("again." + ext);
        if (ext == "xlsx") XlsxWriter.save (back, path2);
        else Ods.save (back, path2);
        check_book (ext + " second", ext == "xlsx" ? Xlsx.load (path2) : Ods.load (path2));
        FileUtils.remove (path2);
    } catch (Error e) {
        stderr.printf ("%s error: %s\n", ext, e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

void test_xlsx () {
    roundtrip ("xlsx");
}

void test_ods () {
    roundtrip ("ods");
}

void test_fods () {
    roundtrip ("fods");
}

void test_xlsm_keeps_macros () {
    var book = sample ();
    uint8[] fake = { 0xd0, 0xcf, 0x11, 0xe0, 1, 2, 3, 4 };
    book.vba_project = new Bytes (fake);
    string path = tmp_path ("macro.xlsm");
    try {
        XlsxWriter.save (book, path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        var zip = new ZipReader (data);
        string ct = zip.read_text ("[Content_Types].xml");
        same ("xlsm main type", "true", ct.contains ("macroEnabled.main+xml").to_string ());
        same ("xlsm rel", "true", zip.read_text ("xl/_rels/workbook.xml.rels").contains ("vbaProject.bin").to_string ());
        var back = Xlsx.load (path);
        same ("xlsm vba bytes", "8", back.vba_project != null ? back.vba_project.length.to_string () : "0");
        string plain = tmp_path ("plain.xlsx");
        XlsxWriter.save (back, plain);
        FileUtils.get_data (plain, out data);
        same ("xlsx drops vba", "false", new ZipReader (data).has ("xl/vbaProject.bin").to_string ());
        FileUtils.remove (plain);
    } catch (Error e) {
        stderr.printf ("xlsm error: %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

void test_excel_comment_xml () {
    var book = sample ();
    string path = tmp_path ("c.xlsx");
    try {
        XlsxWriter.save (book, path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        var zip = new ZipReader (data);
        string sheet = zip.read_text ("xl/worksheets/sheet1.xml");
        same ("legacyDrawing", "true", sheet.contains ("<legacyDrawing r:id=").to_string ());
        same ("hyperlinks order", "true", (sheet.index_of ("<hyperlinks>") < sheet.index_of ("<pageMargins") && sheet.index_of ("<pageMargins") < sheet.index_of ("<legacyDrawing")).to_string ());
        string vml = zip.read_text ("xl/drawings/vmlDrawing1.vml");
        same ("vml note", "true", vml.contains ("ObjectType=\"Note\"").to_string ());
        string cm = zip.read_text ("xl/comments1.xml");
        same ("comment author", "true", cm.contains ("<author>Ada</author>").to_string ());
        same ("core title", "true", zip.read_text ("docProps/core.xml").contains ("<dc:title>Quarterly</dc:title>").to_string ());
    } catch (Error e) {
        stderr.printf ("xml error: %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

void test_of_formulas () {
    var book = new Workbook ();
    var s = book.add_sheet ("A");
    book.add_sheet ("B b");
    string[] cases = { "=SUM(A1:B2)", "='B b'!A1+1", "=XLOOKUP(1,A1:A3,B1:B3)", "=SUM({1,2;3,4})", "=IF(A1>1,\"x;y\",\"z\")" };
    foreach (string c in cases) {
        try {
            var n = Formula.parse (c, book, s);
            string of = Ods.to_of (n, s);
            string back = Ods.from_of (of);
            var n2 = Formula.parse (back, book, s);
            same ("of " + c, c, Formula.to_text (n2, s));
        } catch (FormulaError e) {
            stderr.printf ("of parse %s: %s\n", c, e.message);
            Test.fail ();
        }
    }
}

void test_ods_tables_spill () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    s.set_input (0, 0, "Item");
    s.set_input (0, 1, "Qty");
    s.set_input (1, 0, "a");
    s.set_input (1, 1, "2");
    s.set_input (2, 0, "b");
    s.set_input (2, 1, "3");
    var t = new TableDef ("Stock", s, new Area (s, 0, 0, 2, 1));
    t.sync_columns ();
    book.tables.add (t);
    s.set_input (0, 3, "=SUM(Stock[Qty])");
    s.set_input (0, 5, "={1,2;3,4}");
    s.set_input (4, 0, "=SUM(F1#)");
    book.recalculate ();
    string path = tmp_path ("tables.ods");
    try {
        Ods.save (book, path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        string content = new ZipReader (data).read_text ("content.xml");
        same ("ods struct ref", "true", content.contains ("of:=SUM([$S.$B$2:$S.$B$3])").to_string ());
        same ("ods matrix span", "true", content.contains ("table:number-matrix-columns-spanned=\"2\"").to_string ());
        same ("ods database range", "true", content.contains ("table:database-range table:name=\"Stock\"").to_string ());
        var back = Ods.load (path);
        var bs = back.sheets[0];
        same ("ods table back", "1", back.tables.size.to_string ());
        if (back.tables.size == 1) same ("ods table cols", "Item,Qty", back.tables[0].columns[0].name + "," + back.tables[0].columns[1].name);
        same ("ods spill value", "4", bs.value_at (1, 6).display ());
        same ("ods sum spill", "10", bs.value_at (4, 0).display ());
        same ("ods struct sum", "5", bs.value_at (0, 3).display ());
    } catch (Error e) {
        stderr.printf ("ods tables error: %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

void test_ods_native_formats () {
    var book = sample ();
    string path = tmp_path ("native.ods");
    try {
        Ods.save (book, path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        var zip = new ZipReader (data);
        string content = /ss:format-code="[^"]*"/.replace (zip.read_text ("content.xml"), -1, 0, "");
        var w = new ZipWriter ();
        w.add_text ("mimetype", "application/vnd.oasis.opendocument.spreadsheet", false);
        w.add_text ("content.xml", content);
        w.add_text ("styles.xml", zip.read_text ("styles.xml"));
        FileUtils.set_data (path, w.finish ());
        var back = Ods.load (path);
        var s = back.find_sheet ("Data");
        string[] codes = { "0.00%", "yyyy-mm-dd", "h:mm:ss", "0.00E+00", "# ?/?", "€ #,##0.00", "@", "d mmmm yyyy", "#,##0" };
        for (int i = 0; i < codes.length; i++) {
            var c = s.get_cell (10 + i, 0);
            same ("native code " + codes[i], codes[i], c != null ? back.styles[c.style].number_format : "");
        }
        same ("native neg", "#,##0.00;[Red]-#,##0.00", back.styles[s.get_cell (1, 1).style].number_format);
    } catch (Error e) {
        stderr.printf ("native error: %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

void u16w (ByteArray b, int v) {
    uint8[] x = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff) };
    b.append (x);
}

void u32w (ByteArray b, uint64 v) {
    uint8[] x = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
    b.append (x);
}

void rec (ByteArray out_b, int type, ByteArray body) {
    u16w (out_b, type);
    u16w (out_b, (int) body.len);
    out_b.append (body.data);
}

ByteArray bytes_of (uint8[] d) {
    var b = new ByteArray ();
    b.append (d);
    return b;
}

ByteArray biff_sheet_body () {
    var s = new ByteArray ();
    var bof = new ByteArray ();
    u16w (bof, 0x0600);
    u16w (bof, 0x0010);
    u32w (bof, 0);
    u32w (bof, 0);
    u32w (bof, 0);
    rec (s, 0x0809, bof);
    var lbl = new ByteArray ();
    u16w (lbl, 0);
    u16w (lbl, 0);
    u16w (lbl, 15);
    u32w (lbl, 0);
    rec (s, 0x00FD, lbl);
    var num = new ByteArray ();
    u16w (num, 1);
    u16w (num, 0);
    u16w (num, 15);
    double d = 2.5;
    uint64 bits = 0;
    Memory.copy (&bits, &d, 8);
    for (int i = 0; i < 8; i++) {
        uint8[] one = { (uint8) ((bits >> (8 * i)) & 0xff) };
        num.append (one);
    }
    rec (s, 0x0203, num);
    var rk = new ByteArray ();
    u16w (rk, 2);
    u16w (rk, 0);
    u16w (rk, 15);
    u32w (rk, (7 << 2) | 2);
    rec (s, 0x027E, rk);
    var f = new ByteArray ();
    u16w (f, 3);
    u16w (f, 0);
    u16w (f, 15);
    u32w (f, 0);
    u32w (f, 0);
    u16w (f, 0);
    u32w (f, 0);
    var rgce = new ByteArray ();
    uint8[] ref1 = { 0x24 };
    rgce.append (ref1);
    u16w (rgce, 1);
    u16w (rgce, 0xC000);
    rgce.append (ref1);
    u16w (rgce, 2);
    u16w (rgce, 0xC000);
    uint8[] add = { 0x03, 0x1E };
    rgce.append (add);
    u16w (rgce, 10);
    uint8[] mul = { 0x05 };
    rgce.append (mul);
    u16w (f, (int) rgce.len);
    f.append (rgce.data);
    rec (s, 0x0006, f);
    var sum = new ByteArray ();
    u16w (sum, 4);
    u16w (sum, 0);
    u16w (sum, 15);
    u32w (sum, 0);
    u32w (sum, 0);
    u16w (sum, 0);
    u32w (sum, 0);
    var r2 = new ByteArray ();
    uint8[] area = { 0x25 };
    r2.append (area);
    u16w (r2, 1);
    u16w (r2, 2);
    u16w (r2, 0xC000);
    u16w (r2, 0xC000);
    uint8[] fv = { 0x22, 1 };
    r2.append (fv);
    u16w (r2, 4);
    u16w (sum, (int) r2.len);
    sum.append (r2.data);
    rec (s, 0x0006, sum);
    var mc = new ByteArray ();
    u16w (mc, 1);
    u16w (mc, 6);
    u16w (mc, 6);
    u16w (mc, 0);
    u16w (mc, 2);
    rec (s, 0x00E5, mc);
    var obj = new ByteArray ();
    u16w (obj, 0x15);
    u16w (obj, 18);
    u16w (obj, 0x19);
    u16w (obj, 5);
    for (int i = 0; i < 14; i++) {
        uint8[] z = { 0 };
        obj.append (z);
    }
    rec (s, 0x005D, obj);
    var txo = new ByteArray ();
    for (int i = 0; i < 10; i++) {
        uint8[] z = { 0 };
        txo.append (z);
    }
    u16w (txo, 5);
    u16w (txo, 16);
    u32w (txo, 0);
    rec (s, 0x01B6, txo);
    var cont = new ByteArray ();
    uint8[] flag = { 0 };
    cont.append (flag);
    cont.append ("Hello".data);
    rec (s, 0x003C, cont);
    var note = new ByteArray ();
    u16w (note, 0);
    u16w (note, 0);
    u16w (note, 0);
    u16w (note, 5);
    u16w (note, 3);
    uint8[] nf = { 0 };
    note.append (nf);
    note.append ("Ann".data);
    rec (s, 0x001C, note);
    rec (s, 0x000A, new ByteArray ());
    return s;
}

uint8[] synthetic_xls () {
    var g = new ByteArray ();
    var bof = new ByteArray ();
    u16w (bof, 0x0600);
    u16w (bof, 0x0005);
    u32w (bof, 0);
    u32w (bof, 0);
    u32w (bof, 0);
    rec (g, 0x0809, bof);
    var font = new ByteArray ();
    u16w (font, 200);
    u16w (font, 0);
    u16w (font, 0x7FFF);
    u16w (font, 700);
    u16w (font, 0);
    uint8[] fz = { 0, 0, 0, 0 };
    font.append (fz);
    uint8[] fname = { 5, 0 };
    font.append (fname);
    font.append ("Arial".data);
    for (int i = 0; i < 5; i++) rec (g, 0x0031, font);
    for (int i = 0; i < 16; i++) {
        var xf = new ByteArray ();
        u16w (xf, i == 15 ? 0 : 0);
        u16w (xf, 0);
        u16w (xf, 0);
        for (int k = 0; k < 14; k++) {
            uint8[] z = { 0 };
            xf.append (z);
        }
        rec (g, 0x00E0, xf);
    }
    var sheet = biff_sheet_body ();
    var bs = new ByteArray ();
    int bs_pos_offset = (int) g.len + 4;
    u32w (bs, 0);
    uint8[] vis = { 0, 0, 6, 0 };
    bs.append (vis);
    bs.append ("Data B".data);
    rec (g, 0x0085, bs);
    var sst = new ByteArray ();
    u32w (sst, 1);
    u32w (sst, 1);
    u16w (sst, 5);
    uint8[] sf = { 0 };
    sst.append (sf);
    sst.append ("Hello".data);
    rec (g, 0x00FC, sst);
    rec (g, 0x000A, new ByteArray ());
    uint32 pos = g.len;
    g.data[bs_pos_offset] = (uint8) (pos & 0xff);
    g.data[bs_pos_offset + 1] = (uint8) ((pos >> 8) & 0xff);
    g.append (sheet.data);
    while (g.len < 4096 + 512) {
        uint8[] z = { 0 };
        g.append (z);
    }
    while (g.len % 512 != 0) {
        uint8[] z = { 0 };
        g.append (z);
    }
    int nsec = (int) g.len / 512;
    var file = new ByteArray ();
    uint8[] sig = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };
    file.append (sig);
    for (int i = 0; i < 16; i++) {
        uint8[] z = { 0 };
        file.append (z);
    }
    u16w (file, 0x3E);
    u16w (file, 3);
    u16w (file, 0xFFFE);
    u16w (file, 9);
    u16w (file, 6);
    for (int i = 0; i < 6; i++) {
        uint8[] z = { 0 };
        file.append (z);
    }
    u32w (file, 0);
    u32w (file, 1);
    u32w (file, 1);
    u32w (file, 0);
    u32w (file, 4096);
    u32w (file, 0xFFFFFFFE);
    u32w (file, 0);
    u32w (file, 0xFFFFFFFE);
    u32w (file, 0);
    u32w (file, 0);
    for (int i = 1; i < 109; i++) u32w (file, 0xFFFFFFFF);
    var fat = new ByteArray ();
    u32w (fat, 0xFFFFFFFD);
    u32w (fat, 0xFFFFFFFE);
    for (int i = 0; i < nsec; i++) u32w (fat, i == nsec - 1 ? 0xFFFFFFFE : (uint32) (i + 3));
    while (fat.len < 512) u32w (fat, 0xFFFFFFFF);
    file.append (fat.data);
    var dir = new ByteArray ();
    string[] names = { "Root Entry", "Workbook" };
    for (int e = 0; e < 4; e++) {
        var ent = new ByteArray ();
        string nm = e < 2 ? names[e] : "";
        for (int i = 0; i < 32; i++) u16w (ent, i < nm.length ? nm[i] : 0);
        u16w (ent, nm.length > 0 ? (nm.length + 1) * 2 : 0);
        uint8[] tb = { (uint8) (e == 0 ? 5 : (e == 1 ? 2 : 0)), 1 };
        ent.append (tb);
        u32w (ent, 0xFFFFFFFF);
        u32w (ent, 0xFFFFFFFF);
        u32w (ent, e == 0 ? 1 : 0xFFFFFFFF);
        for (int i = 0; i < 36; i++) {
            uint8[] z = { 0 };
            ent.append (z);
        }
        u32w (ent, e == 0 ? 0xFFFFFFFE : (e == 1 ? 2 : 0));
        u32w (ent, e == 1 ? g.len : 0);
        u32w (ent, 0);
        dir.append (ent.data);
    }
    file.append (dir.data);
    file.append (g.data);
    return file.steal ();
}

void test_xls_import () {
    LocaleInfo.set_c ();
    string path = tmp_path ("legacy.xls");
    try {
        FileUtils.set_data (path, synthetic_xls ());
        var doc = Document.open (path);
        var b = doc.book;
        same ("xls path kept", "true", (doc.path == path).to_string ());
        same ("xls sheet", "Data B", b.sheets[0].name);
        var s = b.sheets[0];
        same ("xls sst", "Hello", s.value_at (0, 0).display ());
        same ("xls number", "2.5", s.value_at (1, 0).display ());
        same ("xls rk", "7", s.value_at (2, 0).display ());
        same ("xls formula", "=(A2+A3)*10", s.get_cell (3, 0) != null ? s.get_cell (3, 0).input : "");
        same ("xls formula value", "95", s.value_at (3, 0).display ());
        same ("xls sum", "=SUM(A2:A3)", s.get_cell (4, 0) != null ? s.get_cell (4, 0).input : "");
        same ("xls merge", "1", s.merges.size.to_string ());
        same ("xls note", "Hello", s.get_cell (0, 0).note);
        same ("xls note author", "Ann", s.get_cell (0, 0).note_author);
        same ("xls bold font", "true", b.styles[s.get_cell (0, 0).style].bold.to_string ());
    } catch (Error e) {
        stderr.printf ("xls error: %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

void test_ods_calc_and_titles () {
    var book = new Workbook ();
    var s = book.add_sheet ("P");
    for (int r = 0; r < 20; r++) for (int c = 0; c < 5; c++) s.set_input (r, c, "%d".printf (r * 10 + c));
    s.page.title_rows = "$1:$2";
    s.page.title_cols = "$A:$A";
    book.iterative = true;
    book.max_iterations = 50;
    book.max_change = 0.0001;
    book.manual_calc = true;
    book.add_sheet ("Secret").visibility = 1;
    string path = tmp_path ("calc.ods");
    try {
        Ods.save (book, path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        string content = new ZipReader (data).read_text ("content.xml");
        same ("ods header rows", "true", content.contains ("<table:table-header-rows>").to_string ());
        same ("ods header cols", "true", content.contains ("<table:table-header-columns>").to_string ());
        same ("ods no private titles", "false", content.contains ("print-title-rows").to_string ());
        same ("ods iteration", "true", content.contains ("table:iteration table:status=\"enable\" table:steps=\"50\"").to_string ());
        var back = Ods.load (path);
        var bs = back.sheets[0];
        same ("ods titles back", "$1:$2 $A:$A", bs.page.title_rows + " " + bs.page.title_cols);
        same ("ods cells after header", "31", bs.value_at (3, 1).display ());
        same ("ods hidden sheet", "0 1", "%d %d".printf (back.sheets[0].visibility, back.sheets[1].visibility));
        same ("ods iterative back", "true 50 0.0001 true", "%s %d %s %s".printf (back.iterative.to_string (), back.max_iterations, Singularity.Apps.Spreadsheet.Value.format_number_general_full (back.max_change), back.manual_calc.to_string ()));
    } catch (Error e) {
        stderr.printf ("calc ods error: %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

void brec (ByteArray out_b, int type, ByteArray body) {
    int t = type;
    if (t >= 0x80) {
        uint8[] tb = { (uint8) ((t & 0x7f) | 0x80), (uint8) (t >> 7) };
        out_b.append (tb);
    } else {
        uint8[] tb = { (uint8) t };
        out_b.append (tb);
    }
    uint len = body.len;
    do {
        uint8 b = (uint8) (len & 0x7f);
        len >>= 7;
        if (len > 0) b |= 0x80;
        uint8[] one = { b };
        out_b.append (one);
    } while (len > 0);
    out_b.append (body.data);
}

void wstr (ByteArray b, string s) {
    u32w (b, s.length);
    for (int i = 0; i < s.length; i++) u16w (b, s[i]);
}

void test_xlsb_import () {
    LocaleInfo.set_c ();
    var wb = new ByteArray ();
    var bundle = new ByteArray ();
    u32w (bundle, 1);
    u32w (bundle, 1);
    wstr (bundle, "rId1");
    wstr (bundle, "Binary");
    brec (wb, 156, bundle);
    var sst = new ByteArray ();
    var item = new ByteArray ();
    uint8[] z1 = { 0 };
    item.append (z1);
    wstr (item, "Hello xlsb");
    brec (sst, 19, item);
    var sh = new ByteArray ();
    for (int r = 0; r < 3; r++) {
        var row = new ByteArray ();
        u32w (row, r);
        u32w (row, 0);
        u16w (row, 300);
        u16w (row, 0x2000);
        brec (sh, 0, row);
        if (r == 0) {
            var c = new ByteArray ();
            u32w (c, 0);
            u32w (c, 0);
            u32w (c, 0);
            brec (sh, 7, c);
            var rkc = new ByteArray ();
            u32w (rkc, 1);
            u32w (rkc, 0);
            u32w (rkc, (21 << 2) | 2);
            brec (sh, 2, rkc);
        } else if (r == 1) {
            var c = new ByteArray ();
            u32w (c, 1);
            u32w (c, 0);
            double d = 1.5;
            uint64 bits = 0;
            Memory.copy (&bits, &d, 8);
            u32w (c, bits & 0xffffffff);
            u32w (c, bits >> 32);
            brec (sh, 5, c);
        } else {
            var f = new ByteArray ();
            u32w (f, 1);
            u32w (f, 0);
            double d = 45;
            uint64 bits = 0;
            Memory.copy (&bits, &d, 8);
            u32w (f, bits & 0xffffffff);
            u32w (f, bits >> 32);
            u16w (f, 0);
            var rg = new ByteArray ();
            uint8[] ref1 = { 0x44 };
            rg.append (ref1);
            u32w (rg, 0);
            u16w (rg, 0xC001);
            rg.append (ref1);
            u32w (rg, 1);
            u16w (rg, 0xC001);
            uint8[] add = { 0x03, 0x1E };
            rg.append (add);
            u16w (rg, 2);
            uint8[] mul = { 0x05 };
            rg.append (mul);
            u32w (f, rg.len);
            f.append (rg.data);
            u32w (f, 0);
            brec (sh, 9, f);
        }
    }
    var mc = new ByteArray ();
    u32w (mc, 4);
    u32w (mc, 5);
    u32w (mc, 0);
    u32w (mc, 1);
    brec (sh, 176, mc);
    var zw = new ZipWriter ();
    try {
        zw.add_text ("_rels/.rels", "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.bin\"/></Relationships>");
        zw.add_text ("xl/_rels/workbook.bin.rels", "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.bin\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings\" Target=\"sharedStrings.bin\"/></Relationships>");
        zw.add ("xl/workbook.bin", wb.data);
        zw.add ("xl/sharedStrings.bin", sst.data);
        zw.add ("xl/worksheets/sheet1.bin", sh.data);
        string path = tmp_path ("binary.xlsb");
        FileUtils.set_data (path, zw.finish ());
        var doc = Document.open (path);
        var s = doc.book.sheets[0];
        same ("xlsb sheet", "Binary", s.name);
        same ("xlsb hidden", "1", s.visibility.to_string ());
        same ("xlsb sst", "Hello xlsb", s.value_at (0, 0).display ());
        same ("xlsb rk", "21", s.value_at (0, 1).display ());
        same ("xlsb real", "1.5", s.value_at (1, 1).display ());
        same ("xlsb formula", "=(B1+B2)*2", s.get_cell (2, 1) != null ? s.get_cell (2, 1).input : "");
        same ("xlsb formula value", "45", s.value_at (2, 1).display ());
        same ("xlsb row height", "true", s.row_heights.has_key (0).to_string ());
        same ("xlsb merge", "A5:B6", s.merges.size > 0 ? s.merges[0].to_string () : "");
        same ("xlsb path kept", "true", (doc.path == path).to_string ());
        FileUtils.remove (path);
    } catch (Error e) {
        stderr.printf ("xlsb error: %s\n", e.message);
        Test.fail ();
    }
}

void test_xls_roundtrip () {
    LocaleInfo.set_c ();
    var book = sample ();
    var s0 = book.find_sheet ("Data");
    s0.set_input (7, 1, "=IF(B2>100,\"big\",\"small\")&\" \"&TEXT(B2,\"0.0\")");
    s0.set_input (7, 2, "='Other Sheet'!A1*2+SUM(Data!B2:B3)");
    s0.set_input (7, 3, "=Total/2");
    s0.set_input (7, 4, "=VLOOKUP(\"Gamma\",A2:B3,2,FALSE)");
    s0.set_input (7, 5, "=SUM({1,2;3,4})");
    s0.set_input (7, 6, "=XLOOKUP(1,B2:B3,A2:A3)");
    s0.set_input (7, 7, "=EOMONTH(40000,1)");
    s0.set_input (7, 8, "=IF(B2>0,SUMPRODUCT(B2:B3,B2:B3),0)");
    s0.page.print_area = "A1:D10";
    s0.page.title_rows = "$1:$2";
    book.recalculate ();
    string path = tmp_path ("save.xls");
    try {
        var w = XlsWriter.save (book, path);
        var back = Xls.load (path);
        var s = back.find_sheet ("Data");
        same ("xlsw note", "First note\nsecond line", s.get_cell (1, 0).note);
        same ("xlsw note author", "Ada", s.get_cell (1, 0).note_author);
        same ("xlsw text", "Alpha  beta", s.value_at (1, 0).display ());
        same ("xlsw link", "https://example.com/a?b=1&c=2", s.get_cell (4, 0).link);
        same ("xlsw internal link", "#'Other Sheet'!A1", s.get_cell (5, 0).link);
        same ("xlsw sum formula", "=SUM(B2:B3)", s.get_cell (3, 1).input);
        same ("xlsw sum", "1192.5", s.value_at (3, 1).display ());
        same ("xlsw if", "=IF(B2>100,\"big\",\"small\")&\" \"&TEXT(B2,\"0.0\")", s.get_cell (7, 1).input);
        same ("xlsw if value", "big 1234.5", s.value_at (7, 1).display ());
        same ("xlsw 3d", "='Other Sheet'!A1*2+SUM(B2:B3)", s.get_cell (7, 2).input);
        same ("xlsw 3d value", "1206.5", s.value_at (7, 2).display ());
        same ("xlsw name ref", "=Total/2", s.get_cell (7, 3).input);
        same ("xlsw name value", "596.25", s.value_at (7, 3).display ());
        same ("xlsw vlookup", "-42", s.value_at (7, 4).display ());
        same ("xlsw array", "10", s.value_at (7, 5).display ());
        same ("xlsw newer function kept", "=XLOOKUP(1,B2:B3,A2:A3)", s.get_cell (7, 6).input);
        same ("xlsw atp function", "=EOMONTH(40000,1)", s.get_cell (7, 7).input);
        same ("xlsw if sumproduct", "1525754.25", s.value_at (7, 8).display ());
        same ("xlsw as values", "0", w.formulas_as_values.to_string ());
        same ("xlsw print area", "A1:D10", s.page.print_area.replace ("$", ""));
        same ("xlsw print titles", "$1:$2", s.page.title_rows);
        var st = back.styles[s.get_cell (1, 1).style];
        same ("xlsw numfmt", "#,##0.00;[Red]-#,##0.00", st.number_format);
        same ("xlsw bold italic underline", "true true true", "%s %s %s".printf (st.bold.to_string (), st.italic.to_string (), st.underline.to_string ()));
        same ("xlsw color", "#1f4e79", st.color);
        same ("xlsw fill", "#ffe699", st.fill);
        same ("xlsw size family", "14 DejaVu Serif", Singularity.Apps.Spreadsheet.Value.format_number_general_full (st.font_size) + " " + st.font_family);
        same ("xlsw align wrap", "%d %d true".printf (HAlign.RIGHT, VAlign.TOP), "%d %d %s".printf (st.halign, st.valign, st.wrap.to_string ()));
        same ("xlsw borders", "%d#ff0000 %d".printf (BorderStyle.THIN, BorderStyle.DOUBLE), "%d%s %d".printf (st.top.style, st.top.color, st.bottom.style));
        string[] codes = { "0.00%", "yyyy-mm-dd", "h:mm:ss", "0.00E+00", "# ?/?", "[$€-410] #,##0.00", "@", "d mmmm yyyy", "#,##0" };
        for (int i = 0; i < codes.length; i++) {
            var c = s.get_cell (10 + i, 0);
            same ("xlsw code " + codes[i], codes[i], c != null ? back.styles[c.style].number_format : "");
        }
        same ("xlsw col width", "true", ((s.col_widths[0] - 200).abs () <= 8).to_string ());
        same ("xlsw row height", "true", (s.row_heights.has_key (2) && (s.row_heights[2] - 50).abs () <= 2).to_string ());
        same ("xlsw hidden", "true true", "%s %s".printf (s.hidden_cols.contains (5).to_string (), s.hidden_rows.contains (8).to_string ()));
        same ("xlsw merge", "A21:C22", s.merges.size == 1 ? s.merges[0].to_string () : "");
        same ("xlsw freeze", "1/1", "%d/%d".printf (s.freeze_rows, s.freeze_cols));
        same ("xlsw names", "Data!$B$4", back.names.has_key ("Total") ? back.names["Total"] : "");
        same ("xlsw local name", "Data!$A$2", s.names.has_key ("Local") ? s.names["Local"] : "");
        same ("xlsw sheets", "Data,Other Sheet", back.sheets[0].name + "," + back.sheets[1].name);
        same ("xlsw tab color", "#ff8800", s.tab_color);
        same ("xlsw cf count", "2", s.cond_formats.size.to_string ());
        if (s.cond_formats.size == 2) {
            same ("xlsw cf greater", "%d 100 B2:B4".printf (CondKind.GREATER), "%d %s %s".printf (s.cond_formats[0].kind, s.cond_formats[0].a, s.cond_formats[0].area.to_string ()));
            var cst = back.styles[s.cond_formats[0].style];
            same ("xlsw cf style", "#ffe699 true #1f4e79", "%s %s %s".printf (cst.fill, cst.bold.to_string (), cst.color));
            same ("xlsw cf between", "%d 1 5".printf (CondKind.BETWEEN), "%d %s %s".printf (s.cond_formats[1].kind, s.cond_formats[1].a, s.cond_formats[1].b));
        }
        same ("xlsw dv count", "2", s.validations.size.to_string ());
        foreach (var v in s.validations) {
            if (v.kind == ValidationKind.LIST) {
                same ("xlsw dv list", "\"red,green,blue\" C2:C5 Pick a colour", "%s %s %s".printf (v.list_source, v.area.to_string (), v.message));
            } else {
                same ("xlsw dv whole", "%d %d 1 10 Too big".printf (ValidationKind.WHOLE, ValidationOp.BETWEEN), "%d %d %s %s %s".printf (v.kind, v.op, v.formula1, v.formula2, v.error_message));
            }
        }
    } catch (Error e) {
        stderr.printf ("xls write error: %s\n", e.message);
        Test.fail ();
    }
}

void test_xlsb_roundtrip () {
    LocaleInfo.set_c ();
    var book = sample ();
    var s0 = book.find_sheet ("Data");
    s0.set_input (7, 1, "=IF(B2>100,\"big\",\"small\")&\" \"&TEXT(B2,\"0.0\")");
    s0.set_input (7, 2, "='Other Sheet'!A1*2+SUM(Data!B2:B3)");
    s0.set_input (7, 3, "=Total/2");
    s0.set_input (7, 6, "=XLOOKUP(\"Gamma\",A2:A3,B2:B3)");
    s0.set_input (7, 7, "=EOMONTH(40000,1)");
    s0.set_input (70000, 2, "=SUM(C1:C2)+1");
    s0.page.print_area = "A1:D10";
    book.iterative = true;
    book.max_iterations = 42;
    book.recalculate ();
    string path = tmp_path ("save.xlsb");
    try {
        var w = XlsbWriter.save (book, path);
        var doc = Document.open (path);
        var back = doc.book;
        var s = back.find_sheet ("Data");
        same ("xlsbw path kept", "true", (doc.path == path).to_string ());
        same ("xlsbw note", "First note\nsecond line", s.get_cell (1, 0).note);
        same ("xlsbw note author", "Ada", s.get_cell (1, 0).note_author);
        same ("xlsbw text", "Alpha  beta", s.value_at (1, 0).display ());
        same ("xlsbw link", "https://example.com/a?b=1&c=2", s.get_cell (4, 0).link);
        same ("xlsbw internal link", "#'Other Sheet'!A1", s.get_cell (5, 0).link);
        same ("xlsbw sum", "=SUM(B2:B3)", s.get_cell (3, 1).input);
        same ("xlsbw if", "big 1234.5", s.value_at (7, 1).display ());
        same ("xlsbw 3d", "='Other Sheet'!A1*2+SUM(B2:B3)", s.get_cell (7, 2).input);
        same ("xlsbw 3d value", "1206.5", s.value_at (7, 2).display ());
        same ("xlsbw name", "=Total/2", s.get_cell (7, 3).input);
        same ("xlsbw future", "=XLOOKUP(\"Gamma\",A2:A3,B2:B3)", s.get_cell (7, 6).input);
        same ("xlsbw future value", "-42", s.value_at (7, 6).display ());
        same ("xlsbw atp", "=EOMONTH(40000,1)", s.get_cell (7, 7).input);
        same ("xlsbw big row", "=SUM(C1:C2)+1", s.get_cell (70000, 2) != null ? s.get_cell (70000, 2).input : "");
        same ("xlsbw as values", "0", w.formulas_as_values.to_string ());
        var st = back.styles[s.get_cell (1, 1).style];
        same ("xlsbw numfmt", "#,##0.00;[Red]-#,##0.00", st.number_format);
        same ("xlsbw font", "true true true 14 DejaVu Serif #1f4e79", "%s %s %s %s %s %s".printf (st.bold.to_string (), st.italic.to_string (), st.underline.to_string (), Singularity.Apps.Spreadsheet.Value.format_number_general_full (st.font_size), st.font_family, st.color));
        same ("xlsbw fill", "#ffe699", st.fill);
        same ("xlsbw align", "%d %d true".printf (HAlign.RIGHT, VAlign.TOP), "%d %d %s".printf (st.halign, st.valign, st.wrap.to_string ()));
        same ("xlsbw borders", "%d#ff0000 %d".printf (BorderStyle.THIN, BorderStyle.DOUBLE), "%d%s %d".printf (st.top.style, st.top.color, st.bottom.style));
        same ("xlsbw col width", "true", ((s.col_widths[0] - 200).abs () <= 8).to_string ());
        same ("xlsbw hidden", "true true", "%s %s".printf (s.hidden_cols.contains (5).to_string (), s.hidden_rows.contains (8).to_string ()));
        same ("xlsbw merge", "A21:C22", s.merges.size == 1 ? s.merges[0].to_string () : "");
        same ("xlsbw freeze", "1/1", "%d/%d".printf (s.freeze_rows, s.freeze_cols));
        same ("xlsbw names", "Data!$B$4", back.names.has_key ("Total") ? back.names["Total"] : "");
        same ("xlsbw local name", "Data!$A$2", s.names.has_key ("Local") ? s.names["Local"] : "");
        same ("xlsbw print area", "A1:D10", s.page.print_area.replace ("$", ""));
        same ("xlsbw tab color", "#ff8800", s.tab_color);
        same ("xlsbw calc", "true 42", "%s %d".printf (back.iterative.to_string (), back.max_iterations));
    } catch (Error e) {
        stderr.printf ("xlsb write error: %s\n", e.message);
        Test.fail ();
    }
}

int main (string[] args) {
    Test.init (ref args);
    LocaleInfo.set_c ();
    Test.add_func ("/fidelity/xlsx", test_xlsx);
    Test.add_func ("/fidelity/ods", test_ods);
    Test.add_func ("/fidelity/fods", test_fods);
    Test.add_func ("/fidelity/xlsm", test_xlsm_keeps_macros);
    Test.add_func ("/fidelity/comment-xml", test_excel_comment_xml);
    Test.add_func ("/fidelity/openformula", test_of_formulas);
    Test.add_func ("/fidelity/ods-tables-spill", test_ods_tables_spill);
    Test.add_func ("/fidelity/ods-native-formats", test_ods_native_formats);
    Test.add_func ("/fidelity/xls-import", test_xls_import);
    Test.add_func ("/fidelity/ods-calc-titles", test_ods_calc_and_titles);
    Test.add_func ("/fidelity/xlsb-import", test_xlsb_import);
    Test.add_func ("/fidelity/xls-roundtrip", test_xls_roundtrip);
    Test.add_func ("/fidelity/xlsb-roundtrip", test_xlsb_roundtrip);
    return Test.run ();
}
