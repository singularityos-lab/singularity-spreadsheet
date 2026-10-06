using Singularity.Apps.Spreadsheet;

Workbook book;
Sheet sh;

void put (Sheet s, string addr, string input) {
    int r, c;
    bool a, b;
    Address.parse_cell (addr, out r, out c, out a, out b);
    s.set_input (r, c, input);
}

string show (Sheet s, string addr) {
    int r, c;
    bool a, b;
    Address.parse_cell (addr, out r, out c, out a, out b);
    return s.value_at (r, c).display ();
}

void expect (Sheet s, string addr, string expected) {
    string got = show (s, addr);
    if (got != expected) {
        stderr.printf ("FAIL %s!%s: expected [%s] got [%s] (%s)\n", s.name, addr, expected, got, s.input_at (0, 0));
        Test.fail ();
    }
}

void fresh () {
    book = new Workbook ();
    sh = book.add_sheet ("Sheet1");
}

void test_lambda () {
    fresh ();
    put (sh, "A1", "=LAMBDA(x,y,x*y)(3,4)");
    put (sh, "A2", "=LET(a,2,b,a+3,a*b)");
    put (sh, "A3", "=LET(f,LAMBDA(n,n+1),f(41))");
    put (sh, "A4", "=REDUCE(0,{1,2,3,4},LAMBDA(acc,v,acc+v))");
    put (sh, "A5", "=LAMBDA(x,x)");
    put (sh, "A6", "=LET(x,{1,2,3},SUM(x))");
    put (sh, "A7", "=LAMBDA(a,[b],IF(ISOMITTED(b),a,a+b))(5)");
    book.names["Double"] = "=LAMBDA(v,v*2)";
    put (sh, "A8", "=Double(21)");
    book.recalculate ();
    expect (sh, "A1", "12");
    expect (sh, "A2", "10");
    expect (sh, "A3", "42");
    expect (sh, "A4", "10");
    expect (sh, "A5", "#CALC!");
    expect (sh, "A6", "6");
    expect (sh, "A7", "5");
    expect (sh, "A8", "42");
}

void test_spill () {
    fresh ();
    put (sh, "A1", "={1,2;3,4}");
    put (sh, "D1", "=SUM(A1#)");
    put (sh, "D2", "=B2");
    put (sh, "E1", "=MAP({1,2,3},LAMBDA(v,v*10))");
    put (sh, "D3", "=G1");
    book.recalculate ();
    expect (sh, "A1", "1");
    expect (sh, "B1", "2");
    expect (sh, "B2", "4");
    expect (sh, "D1", "10");
    expect (sh, "D2", "4");
    expect (sh, "G1", "30");
    expect (sh, "D3", "30");
    put (sh, "B1", "x");
    book.recalculate ();
    expect (sh, "A1", "#SPILL!");
    expect (sh, "B2", "");
    put (sh, "B1", "");
    book.recalculate ();
    expect (sh, "A1", "1");
    expect (sh, "B2", "4");
    put (sh, "H1", "=BYROW({1,2;3,4},LAMBDA(r,SUM(r)))");
    put (sh, "I1", "=MAKEARRAY(2,2,LAMBDA(r,c,r*c))");
    put (sh, "K1", "=SCAN(0,{1,2,3},LAMBDA(a,b,a+b))");
    put (sh, "K3", "=BYCOL({1,2;3,4},SUM)");
    book.recalculate ();
    expect (sh, "H2", "7");
    expect (sh, "J2", "4");
    expect (sh, "M1", "6");
    expect (sh, "L3", "6");
}

void test_3d () {
    fresh ();
    var s2 = book.add_sheet ("Sheet2");
    var s3 = book.add_sheet ("Sheet 3");
    put (sh, "A1", "1");
    put (s2, "A1", "2");
    put (s3, "A1", "3");
    var out_sheet = book.add_sheet ("Out");
    put (out_sheet, "A1", "=SUM(Sheet1:Sheet2!A1)");
    put (out_sheet, "A2", "=SUM('Sheet1:Sheet 3'!A1)");
    put (out_sheet, "A3", "=COUNT(Sheet1:Out!A1:A2)");
    book.recalculate ();
    expect (out_sheet, "A1", "3");
    expect (out_sheet, "A2", "6");
    book.remove_sheet (s3);
    book.recalculate ();
    expect (out_sheet, "A2", "3");
    if (out_sheet.input_at (1, 0) != "=SUM(Sheet1:Sheet2!A1)") {
        stderr.printf ("3d after delete %s\n", out_sheet.input_at (1, 0));
        Test.fail ();
    }
    try {
        var n = Formula.parse ("=SUM(Sheet1:Sheet2!A1:B2)", book, out_sheet);
        string t = Formula.to_text (n, out_sheet);
        if (t != "=SUM(Sheet1:Sheet2!A1:B2)") {
            stderr.printf ("3d render %s\n", t);
            Test.fail ();
        }
    } catch (FormulaError e) {
        Test.fail ();
    }
}

void test_tables () {
    fresh ();
    put (sh, "A1", "Item");
    put (sh, "B1", "Qty");
    put (sh, "C1", "Price");
    put (sh, "A2", "a");
    put (sh, "B2", "2");
    put (sh, "C2", "10");
    put (sh, "A3", "b");
    put (sh, "B3", "3");
    put (sh, "C3", "5");
    put (sh, "D1", "Total");
    var t = new TableDef ("Sales", sh, new Area (sh, 0, 0, 2, 3));
    t.sync_columns ();
    book.tables.add (t);
    put (sh, "D2", "=[@Qty]*[@Price]");
    put (sh, "D3", "=Sales[@Qty]*Sales[@Price]");
    put (sh, "F1", "=SUM(Sales[Qty])");
    put (sh, "F2", "=ROWS(Sales[#All])");
    put (sh, "F3", "=INDEX(Sales[[#Headers],[Price]],1)");
    put (sh, "F4", "=SUM(Sales[[Qty]:[Price]])");
    put (sh, "F5", "=ROWS(Sales)");
    book.recalculate ();
    expect (sh, "D2", "20");
    expect (sh, "D3", "15");
    expect (sh, "F1", "5");
    expect (sh, "F2", "3");
    expect (sh, "F3", "Price");
    expect (sh, "F4", "20");
    expect (sh, "F5", "2");
    string[] cases = { "=Sales[Qty]", "=Sales[@Qty]", "=Sales[#All]", "=Sales[[#Headers],[Price]]", "=Sales[[Qty]:[Price]]", "=[@Qty]", "=Sales[@[Unit Price]]" };
    foreach (string c in cases) {
        try {
            var n = Formula.parse (c, book, sh);
            string back = Formula.to_text (n, sh);
            if (back != c) {
                stderr.printf ("struct render %s -> %s\n", c, back);
                Test.fail ();
            }
        } catch (FormulaError e) {
            stderr.printf ("struct parse %s: %s\n", c, e.message);
            Test.fail ();
        }
    }
}

void test_incremental () {
    var doc = new Document ();
    book = doc.book;
    sh = book.sheets[0];
    for (int i = 0; i < 2000; i++) sh.set_input (i, 0, (i + 1).to_string ());
    for (int i = 0; i < 2000; i++) sh.set_input (i, 1, "=A%d*2".printf (i + 1));
    sh.set_input (0, 2, "=SUM(B1:B2000)");
    sh.set_input (1, 2, "=C1+1");
    sh.set_input (2, 2, "=NOW()>0");
    book.recalculate ();
    expect (sh, "C1", "4002000");
    doc.set_input (sh, 4, 0, "105");
    expect (sh, "B5", "210");
    expect (sh, "C1", "4002200");
    expect (sh, "C2", "4002201");
    if (book.last_recalc_cells > 10) {
        stderr.printf ("incremental recalculated %d cells\n", book.last_recalc_cells);
        Test.fail ();
    }
    doc.undo ();
    expect (sh, "B5", "10");
    expect (sh, "C1", "4002000");
    doc.redo ();
    expect (sh, "C2", "4002201");
    doc.set_input (sh, 5, 1, "=A6*3");
    expect (sh, "B6", "18");
    expect (sh, "C1", "4002206");
    doc.set_input (sh, 0, 3, "={1;2;3}");
    doc.set_input (sh, 5, 3, "=SUM(D1:D3)");
    expect (sh, "D6", "6");
    doc.set_input (sh, 0, 3, "={10;20;30}");
    expect (sh, "D6", "60");
    doc.set_input (sh, 0, 3, "5");
    expect (sh, "D6", "5");
    expect (sh, "D2", "");
}

void test_circular () {
    fresh ();
    put (sh, "A1", "=B1+1");
    put (sh, "B1", "=A1");
    put (sh, "C1", "=A1*2");
    book.recalculate ();
    expect (sh, "A1", "#CIRC!");
    if (book.circular.size != 2) {
        stderr.printf ("circular %d\n", book.circular.size);
        Test.fail ();
    }
    fresh ();
    book.iterative = true;
    book.max_iterations = 100;
    book.max_change = 0.0001;
    put (sh, "A1", "=0.5*B1+1");
    put (sh, "B1", "=A1");
    book.recalculate ();
    double v = sh.value_at (0, 0).number;
    if (Math.fabs (v - 2) > 0.001) {
        stderr.printf ("iterative %g\n", v);
        Test.fail ();
    }
}

void test_perf () {
    fresh ();
    var doc = new Document.with_book (book, null);
    for (int i = 0; i < 50000; i++) sh.set_input (i, 0, i.to_string ());
    for (int i = 0; i < 50000; i++) sh.set_input (i, 1, "=A%d+1".printf (i + 1));
    sh.set_input (0, 2, "=SUM(B1:B50000)");
    var t0 = get_monotonic_time ();
    book.recalculate ();
    var t1 = get_monotonic_time ();
    doc.set_input (sh, 100, 0, "7");
    var t2 = get_monotonic_time ();
    stdout.printf ("# full %.3f s, edit %.4f s, cells %d\n", (t1 - t0) / 1e6, (t2 - t1) / 1e6, book.last_recalc_cells);
    if ((t2 - t1) > 50000) Test.fail ();
}

void test_xlsx_roundtrip () {
    fresh ();
    put (sh, "A1", "Item");
    put (sh, "B1", "Qty");
    put (sh, "A2", "a");
    put (sh, "B2", "2");
    put (sh, "A3", "b");
    put (sh, "B3", "5");
    var t = new TableDef ("Stock", sh, new Area (sh, 0, 0, 2, 1));
    t.sync_columns ();
    book.tables.add (t);
    put (sh, "D1", "=SUM(Stock[Qty])");
    put (sh, "E1", "=SEQUENCE(3)");
    put (sh, "F1", "=SUM(E1#)");
    put (sh, "G1", "=LAMBDA(x,x*2)(21)");
    put (sh, "H1", "=@A1:A3");
    var hidden_sheet = book.add_sheet ("Secret");
    hidden_sheet.visibility = 1;
    book.iterative = true;
    book.max_iterations = 50;
    book.recalculate ();
    string path = Path.build_filename (Environment.get_tmp_dir (), "calc-rt-%d.xlsx".printf (Random.int_range (0, 1000000)));
    try {
        XlsxWriter.save (book, path);
        var back = Xlsx.load (path);
        FileUtils.unlink (path);
        var s2 = back.sheets[0];
        back.recalculate ();
        string[,] want = { { "D1", "7" }, { "E3", "3" }, { "F1", "6" }, { "G1", "42" }, { "H1", "Item" } };
        for (int i = 0; i < want.length[0]; i++) expect (s2, want[i, 0], want[i, 1]);
        if (back.sheets.size != 2 || back.sheets[1].visibility != 1) {
            stderr.printf ("hidden sheet lost\n");
            Test.fail ();
        }
        if (!back.iterative || back.max_iterations != 50) {
            stderr.printf ("calc settings lost\n");
            Test.fail ();
        }
        if (back.tables.size != 1 || back.tables[0].name != "Stock") {
            stderr.printf ("tables after load %d\n", back.tables.size);
            Test.fail ();
        }
        if (s2.input_at (0, 5) != "=SUM(E1#)" || s2.input_at (0, 3) != "=SUM(Stock[Qty])") {
            stderr.printf ("formulas after load [%s] [%s]\n", s2.input_at (0, 5), s2.input_at (0, 3));
            Test.fail ();
        }
        if (s2.get_cell (1, 4) != null && s2.get_cell (1, 4).input != "") {
            stderr.printf ("spilled cell became real input\n");
            Test.fail ();
        }
    } catch (Error e) {
        stderr.printf ("xlsx %s\n", e.message);
        Test.fail ();
    }
}

void test_legacy () {
    fresh ();
    put (sh, "A1", "1");
    put (sh, "A2", "4");
    put (sh, "A3", "9");
    put (sh, "B2", "=SQRT(A1:A3)");
    put (sh, "C2", "=SUMPRODUCT(A1:A3*2)");
    put (sh, "D2", "=SQRT(A1:A3)");
    sh.get_cell (1, 1).legacy = true;
    sh.get_cell (1, 2).legacy = true;
    book.recalculate ();
    expect (sh, "B2", "2");
    expect (sh, "B3", "");
    expect (sh, "C2", "28");
    expect (sh, "D3", "2");
}

void test_cse () {
    var doc = new Document ();
    book = doc.book;
    sh = book.sheets[0];
    doc.set_array_formula (sh, new Area (sh, 0, 0, 3, 0), "={1;2;3}*2");
    expect (sh, "A1", "2");
    expect (sh, "A3", "6");
    expect (sh, "A4", "#N/A");
    doc.set_input (sh, 1, 0, "99");
    expect (sh, "A2", "4");
    doc.set_input (sh, 5, 0, "=SUM(A1:A3)");
    expect (sh, "A6", "12");
}

void test_group () {
    var doc = new Document ();
    book = doc.book;
    var a = book.sheets[0];
    var b = doc.add_sheet ();
    doc.group.add (a);
    doc.group.add (b);
    doc.set_input (a, 0, 0, "42");
    expect (b, "A1", "42");
    doc.edit_style (a, new Area.cell (a, 0, 0), "Bold", (st) => st.bold = true);
    if (!b.style_at (0, 0).bold) Test.fail ();
    doc.undo ();
    doc.undo ();
    expect (b, "A1", "");
}

void test_cond () {
    fresh ();
    for (int i = 0; i < 10; i++) sh.set_input (i, 0, (i + 1).to_string ());
    var icons = new CondFormat (new Area (sh, 0, 0, 9, 0), CondKind.ICON_SET);
    icons.icon_set = "3TrafficLights1";
    sh.cond_formats.add (icons);
    var ge = new CondFormat (new Area (sh, 0, 0, 9, 0), CondKind.GREATER_EQUAL);
    ge.a = "5";
    ge.stop_if_true = true;
    var red = new CellStyle ();
    red.fill = "#ff0000";
    ge.style = book.intern (red);
    sh.cond_formats.add (ge);
    var ge2 = new CondFormat (new Area (sh, 0, 0, 9, 0), CondKind.GREATER);
    ge2.a = "0";
    var blue = new CellStyle ();
    blue.fill = "#0000ff";
    ge2.style = book.intern (blue);
    sh.cond_formats.add (ge2);
    var top = new CondFormat (new Area (sh, 0, 0, 9, 0), CondKind.TOP);
    top.a = "20";
    top.percent = true;
    sh.cond_formats.add (top);
    var begins = new CondFormat (new Area (sh, 0, 1, 9, 1), CondKind.TEXT_BEGINS);
    begins.a = "ab";
    sh.cond_formats.add (begins);
    book.recalculate ();
    var ev = new CondEval (book, sh);
    var s9 = ev.apply (9, 0, sh.value_at (9, 0));
    var s0 = ev.apply (0, 0, sh.value_at (0, 0));
    if (s9 == null || s9.fill != "#ff0000" || s9.icon != 2 || s0 == null || s0.fill != "#0000ff" || s0.icon != 0) {
        stderr.printf ("cond eval wrong\n");
        Test.fail ();
    }
    string path = Path.build_filename (Environment.get_tmp_dir (), "cond-rt-%d.xlsx".printf (Random.int_range (0, 1000000)));
    try {
        XlsxWriter.save (book, path);
        var back = Xlsx.load (path);
        FileUtils.unlink (path);
        var b = back.sheets[0];
        if (b.cond_formats.size != 5 || b.cond_formats[0].kind != CondKind.ICON_SET || b.cond_formats[0].icon_set != "3TrafficLights1" || b.cond_formats[1].kind != CondKind.GREATER_EQUAL || !b.cond_formats[1].stop_if_true || !b.cond_formats[3].percent || b.cond_formats[4].kind != CondKind.TEXT_BEGINS) {
            stderr.printf ("cond roundtrip wrong %d\n", b.cond_formats.size);
            Test.fail ();
        }
        string opath = Path.build_filename (Environment.get_tmp_dir (), "cond-rt-%d.ods".printf (Random.int_range (0, 1000000)));
        Ods.save (book, opath);
        var oback = Ods.load (opath);
        FileUtils.unlink (opath);
        var ob = oback.sheets[0];
        if (ob.cond_formats.size != 5 || ob.cond_formats[0].kind != CondKind.ICON_SET || ob.cond_formats[1].kind != CondKind.GREATER_EQUAL || !ob.cond_formats[3].percent || ob.cond_formats[4].kind != CondKind.TEXT_BEGINS) {
            stderr.printf ("ods cond roundtrip wrong %d\n", ob.cond_formats.size);
            Test.fail ();
        }
    } catch (Error e) {
        stderr.printf ("%s\n", e.message);
        Test.fail ();
    }
}

void test_html () {
    fresh ();
    put (sh, "A1", "Name");
    put (sh, "B1", "<b>");
    put (sh, "A2", "=1+1");
    sh.merges.add (new Area (sh, 2, 0, 2, 1));
    put (sh, "A3", "wide");
    string path = Path.build_filename (Environment.get_tmp_dir (), "html-%d.html".printf (Random.int_range (0, 1000000)));
    try {
        book.recalculate ();
        HtmlExport.save (book, path);
        string text;
        FileUtils.get_contents (path, out text);
        FileUtils.unlink (path);
        if (!text.contains ("<td>Name</td>") || !text.contains ("&lt;b&gt;") || !text.contains (">2</td>") || !text.contains ("colspan=\"2\"")) {
            stderr.printf ("html export wrong\n%s\n", text);
            Test.fail ();
        }
    } catch (Error e) {
        Test.fail ();
    }
}

void probe (string path) {
    try {
        var b = Xlsx.load (path);
        b.recalculate ();
        var s = b.sheets[0];
        foreach (string addr in new string[] { "H2", "H3", "H4", "H6", "I6", "J6" }) {
            int r, c;
            bool x, y;
            Address.parse_cell (addr, out r, out c, out x, out y);
            var cell = s.get_cell (r, c);
            stdout.printf ("# %s = %s legacy=%s input=%s spills=%d\n", addr, s.value_at (r, c).display (), cell != null && cell.legacy ? "y" : "n", cell != null ? cell.input : "-", s.spills.size);
        }
    } catch (Error e) {
        stdout.printf ("# %s\n", e.message);
    }
}

int main (string[] args) {
    Test.init (ref args);
    if (Environment.get_variable ("CALC_COUNT") != null) {
        var distinct = new Gee.HashSet<FnDef> ();
        distinct.add_all (Functions.all ().values);
        stdout.printf ("names %d distinct %d\n", Functions.all ().size, distinct.size);
        if (Environment.get_variable ("CALC_COUNT") == "list") foreach (var k in Functions.all ().keys) stdout.printf ("%s\n", k);
        return 0;
    }
    string? probe_path = Environment.get_variable ("CALC_PROBE");
    if (probe_path != null) {
        probe (probe_path);
        return 0;
    }
    LocaleInfo.set_c ();
    Test.add_func ("/calc/lambda", test_lambda);
    Test.add_func ("/calc/spill", test_spill);
    Test.add_func ("/calc/3d", test_3d);
    Test.add_func ("/calc/tables", test_tables);
    Test.add_func ("/calc/incremental", test_incremental);
    Test.add_func ("/calc/circular", test_circular);
    Test.add_func ("/calc/perf", test_perf);
    Test.add_func ("/calc/xlsx", test_xlsx_roundtrip);
    Test.add_func ("/calc/legacy", test_legacy);
    Test.add_func ("/calc/cse", test_cse);
    Test.add_func ("/calc/group", test_group);
    Test.add_func ("/calc/cond", test_cond);
    Test.add_func ("/calc/html", test_html);
    return Test.run ();
}
