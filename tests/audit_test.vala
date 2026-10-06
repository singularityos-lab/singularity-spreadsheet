using Singularity.Apps.Spreadsheet;

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

void same (string what, string got, string expected) {
    if (got != expected) {
        stderr.printf ("FAIL %s: expected [%s] got [%s]\n", what, expected, got);
        Test.fail ();
    }
}

string tmp_path (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "ss-audit-%d-%s".printf (Random.int_range (0, 1000000), name));
}

void test_header_footer () {
    var ctx = new HFContext ();
    ctx.page = 3;
    ctx.pages = 7;
    ctx.sheet = "Sales";
    ctx.file = "book.xlsx";
    string l, c, r;
    HeaderFooter.split ("&L&\"Arial,Bold\"&14Left &A&CPage &P of &N&R&F &&co", out l, out c, out r);
    same ("split left", l, "&\"Arial,Bold\"&14Left &A");
    same ("split center", c, "Page &P of &N");
    same ("split right", r, "&F &&co");
    same ("expand left", HeaderFooter.plain (l, ctx), "Left Sales");
    same ("expand center", HeaderFooter.plain (c, ctx), "Page 3 of 7");
    same ("expand right", HeaderFooter.plain (r, ctx), "book.xlsx &co");
    same ("page plus", HeaderFooter.plain ("&P+10", ctx), "13");
    var runs = HeaderFooter.expand (l, ctx);
    if (runs.size < 1 || !runs[0].bold || runs[0].font != "Arial" || runs[0].size != 14) {
        stderr.printf ("FAIL runs formatting\n");
        Test.fail ();
    }
    same ("join", HeaderFooter.join ("a", "", "&P"), "&La&R&P");
    same ("no section is center", HeaderFooter.plain ("Hello", ctx), "Hello");
}

void test_layout () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    for (int r = 0; r < 200; r++) for (int c = 0; c < 20; c++) s.set_input (r, c, "x");
    var p = new PageSetup ();
    var l = PrintLayout.compute (s, p, 595.28, 841.89);
    if (l.pages.size < 4) {
        stderr.printf ("FAIL expected several pages, got %d\n", l.pages.size);
        Test.fail ();
    }
    p.fit_to_page = true;
    p.fit_width = 1;
    p.fit_height = 1;
    l = PrintLayout.compute (s, p, 595.28, 841.89);
    same ("fit to one page", l.pages.size.to_string (), "1");
    p.fit_height = 0;
    l = PrintLayout.compute (s, p, 595.28, 841.89);
    same ("fit one wide", l.pages_wide.to_string (), "1");
    var q = new PageSetup ();
    q.print_area = "A1:C30";
    q.row_breaks.add (10);
    q.row_breaks.add (20);
    l = PrintLayout.compute (s, q, 595.28, 841.89);
    same ("manual breaks", l.pages.size.to_string (), "3");
    same ("break row", l.pages[1].r1.to_string (), "10");
    var t = new PageSetup ();
    t.title_rows = "$1:$2";
    l = PrintLayout.compute (s, t, 595.28, 841.89);
    if (!l.page_has_title_rows (l.pages[1]) || l.page_has_title_rows (l.pages[0])) {
        stderr.printf ("FAIL title rows repeat\n");
        Test.fail ();
    }
    var o = new PageSetup ();
    o.over_then_down = true;
    l = PrintLayout.compute (s, o, 595.28, 841.89);
    if (l.pages.size > 1 && l.pages[1].r1 != l.pages[0].r1) {
        stderr.printf ("FAIL over then down order\n");
        Test.fail ();
    }
}

void test_precedents () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    var d = book.add_sheet ("Data");
    put (s, "A1", "1");
    put (s, "A2", "2");
    put (d, "B1", "5");
    put (s, "B1", "=SUM(A1:A2)+Data!B1");
    put (s, "C1", "=B1*2");
    put (s, "C2", "=A1");
    book.recalculate ();
    var prec = Audit.precedents (book, s, 0, 1);
    same ("precedent count", prec.size.to_string (), "2");
    same ("precedent range", prec[0].to_string (), "A1:A2");
    if (prec[1].sheet != d) {
        stderr.printf ("FAIL cross sheet precedent\n");
        Test.fail ();
    }
    var deps = Audit.dependents (book, s, 0, 0);
    string[] labels = {};
    foreach (var x in deps) labels += x.label (s);
    same ("dependents of A1", string.joinv (",", labels), "B1,C2");
    var deps2 = Audit.dependents (book, d, 0, 1);
    same ("dependents cross sheet", deps2.size.to_string (), "1");
}

void test_error_check () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "1");
    put (s, "A2", "2");
    put (s, "A3", "3");
    put (s, "B1", "=A1*2");
    put (s, "B2", "=A2+100");
    put (s, "B3", "=A3*2");
    put (s, "C1", "=1/0");
    put (s, "D1", "'42");
    book.recalculate ();
    var issues = Audit.check (book);
    bool inc = false, err = false, txt = false;
    foreach (var i in issues) {
        if (i.kind == IssueKind.INCONSISTENT && i.row == 1 && i.col == 1) inc = true;
        if (i.kind == IssueKind.ERROR_VALUE && i.col == 2) err = true;
        if (i.kind == IssueKind.NUMBER_AS_TEXT && i.col == 3) txt = true;
    }
    if (!inc || !err || !txt) {
        stderr.printf ("FAIL error check inc=%d err=%d txt=%d\n", (int) inc, (int) err, (int) txt);
        Test.fail ();
    }
}

void test_evaluate () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "2");
    put (s, "A2", "3");
    put (s, "B1", "=SUM(A1:A2)*A1+1");
    book.recalculate ();
    var ev = new FormulaEvaluation (book, s, 0, 1, s.get_cell (0, 1).formula);
    string last = "";
    int guard = 0;
    while (!ev.finished && guard++ < 50) {
        ev.step ();
        last = ev.plain ();
    }
    same ("evaluate final", last, "=11");
    ev.restart ();
    ev.step ();
    same ("evaluate first step", ev.plain (), "=SUM({2;3})*A1+1");
}

void test_script () {
    var doc = new Document ();
    var s = doc.book.sheets[0];
    var host = new ScriptHost ();
    var run = new ScriptRunner (doc, host);
    string src = """
' squares and totals
Function Square(x)
    Square = x * x
End Function

Sub Main()
    Dim total
    total = 0
    For i = 1 To 5
        Cells(i, 1).Value = Square(i)
        total = total + Cells(i, 1).Value
    Next i
    Range("B1").Formula = "=SUM(A1:A5)"
    If Range("B1").Value = total Then
        MsgBox "ok " & total
    Else
        MsgBox "bad"
    End If
    Dim names(2)
    names(0) = "a" : names(1) = "b" : names(2) = "c"
    Range("C1").Value = Join(names, "-")
    n = 0
    Do While n < 3
        n = n + 1
    Loop
    Range("C2").Value = n
    Select Case n
        Case 1, 2
            Range("C3").Value = "small"
        Case Is >= 3
            Range("C3").Value = "big"
    End Select
    Range("C4").Value = WorksheetFunction.Max(Range("A1:A5"))
    Range("A1:A5").Font.Bold = True
    Range("C5").Interior.Color = "#ff0000"
    For Each c In Range("A1:A2")
        c.Offset(0, 3).Value = c.Value * 10
    Next
    k = 0
    For j = 1 To 100
        If j > 4 Then Exit For
        k = j
    Next
    Range("C6").Value = k
    On Error Resume Next
    x = 1 / 0
    Range("C7").Value = "survived"
End Sub
""";
    try {
        run.run_source (src, "Main");
    } catch (ScriptError e) {
        stderr.printf ("FAIL script error %s\n", e.message);
        Test.fail ();
        return;
    }
    doc.book.recalculate ();
    same ("A5", show (s, "A5"), "25");
    same ("B1", show (s, "B1"), "55");
    same ("msg", host.messages.size > 0 ? host.messages[0] : "", "ok 55");
    same ("join", show (s, "C1"), "a-b-c");
    same ("do loop", show (s, "C2"), "3");
    same ("select", show (s, "C3"), "big");
    same ("wf max", show (s, "C4"), "25");
    same ("for each offset", show (s, "D2"), "40");
    same ("exit for", show (s, "C6"), "4");
    same ("resume next", show (s, "C7"), "survived");
    if (!s.style_at (0, 0).bold || s.style_at (4, 2).fill != "#ff0000") {
        stderr.printf ("FAIL style props\n");
        Test.fail ();
    }
    if (!doc.can_undo) {
        stderr.printf ("FAIL macro not undoable\n");
        Test.fail ();
    }
    doc.undo ();
    same ("undo macro", show (s, "A5"), "");
    try {
        run.run_source ("Sub Bad()\n  x = \n End Sub\n", "Bad");
        stderr.printf ("FAIL syntax error not reported\n");
        Test.fail ();
    } catch (ScriptError e) {
        if (!e.message.has_prefix ("2:")) {
            stderr.printf ("FAIL error line %s\n", e.message);
            Test.fail ();
        }
    }
    try {
        run.run_source ("Sub Loop1()\n Do\n Loop\nEnd Sub\n", "Loop1");
        Test.fail ();
    } catch (ScriptError e) {
    }
}

void test_recorder () {
    var doc = new Document ();
    var s = doc.book.sheets[0];
    var rec = new MacroRecorder (doc, s);
    doc.committed.connect ((step) => {
        if (step.before.area != null) rec.record_cells (step.sheet, step.before.cells, step.after.cells);
    });
    doc.set_input (s, 0, 0, "10");
    doc.set_input (s, 1, 0, "=A1*3");
    doc.edit_style (s, new Area (s, 0, 0, 1, 0), "Bold", (st) => st.bold = true);
    string code = rec.finish ("Recorded1");
    var doc2 = new Document ();
    var run = new ScriptRunner (doc2, new ScriptHost ());
    try {
        run.run_source (code, "Recorded1");
    } catch (ScriptError e) {
        stderr.printf ("FAIL playback %s\n%s\n", e.message, code);
        Test.fail ();
        return;
    }
    doc2.book.recalculate ();
    var s2 = doc2.book.sheets[0];
    same ("playback value", show (s2, "A2"), "30");
    if (!s2.style_at (1, 0).bold) {
        stderr.printf ("FAIL playback style\n%s\n", code);
        Test.fail ();
    }
    doc.book.scripts.module ("Recorded").source = code;
    same ("macro names", string.joinv (",", doc.book.scripts.macro_names ().to_array ()), "Recorded1");
    doc.book.scripts.remove_macro ("Recorded1");
    same ("remove", doc.book.scripts.macro_names ().size.to_string (), "0");
}

Workbook setup_book () {
    var book = new Workbook ();
    var s = book.add_sheet ("Report");
    book.add_sheet ("Other");
    for (int r = 0; r < 40; r++) for (int c = 0; c < 6; c++) s.set_input (r, c, (r * c).to_string ());
    var p = s.page;
    p.print_area = "A1:F40";
    p.title_rows = "$1:$2";
    p.title_cols = "$A:$A";
    p.landscape = true;
    p.paper = 1;
    p.margin_left = 0.5;
    p.margin_top = 1.1;
    p.fit_to_page = true;
    p.fit_width = 1;
    p.fit_height = 0;
    p.center_h = true;
    p.gridlines = true;
    p.headings = true;
    p.over_then_down = true;
    p.first_page_number = 5;
    p.header = "&L&A&CPage &P of &N";
    p.footer = "&R&D";
    p.first_different = true;
    p.first_header = "&CFirst";
    p.row_breaks.add (20);
    p.col_breaks.add (3);
    book.scripts.module ("Module1").source = "Sub Hello()\n    MsgBox \"hi\"\nEnd Sub\n";
    book.scripts.shortcuts["Hello"] = "<Control><Shift>h";
    book.watches.add (new CellWatch (s, 2, 3));
    return book;
}

void check_setup (string fmt, Workbook b) {
    var s = b.find_sheet ("Report");
    var p = s.page;
    same (fmt + " print area", p.print_area.replace ("$", ""), "A1:F40");
    same (fmt + " title rows", p.title_rows.replace ("$", ""), "1:2");
    same (fmt + " title cols", p.title_cols.replace ("$", ""), "A:A");
    same (fmt + " landscape", p.landscape.to_string (), "true");
    same (fmt + " paper", p.paper.to_string (), "1");
    same (fmt + " margin left", Singularity.Apps.Spreadsheet.Value.fixed (p.margin_left, 2), "0.50");
    same (fmt + " margin top", Singularity.Apps.Spreadsheet.Value.fixed (p.margin_top, 2), "1.10");
    same (fmt + " fit", "%s %d %d".printf (p.fit_to_page.to_string (), p.fit_width, p.fit_height), "true 1 0");
    same (fmt + " center", p.center_h.to_string (), "true");
    same (fmt + " gridlines", p.gridlines.to_string (), "true");
    same (fmt + " headings", p.headings.to_string (), "true");
    same (fmt + " order", p.over_then_down.to_string (), "true");
    same (fmt + " first page", p.first_page_number.to_string (), "5");
    same (fmt + " header", p.header, "&L&A&CPage &P of &N");
    same (fmt + " footer", p.footer, "&R&D");
    same (fmt + " first header", p.first_header, "&CFirst");
    same (fmt + " first different", p.first_different.to_string (), "true");
    same (fmt + " row breaks", p.row_breaks.contains (20).to_string (), "true");
    same (fmt + " col breaks", p.col_breaks.contains (3).to_string (), "true");
    same (fmt + " macro", b.scripts.macro_names ().size.to_string (), "1");
    same (fmt + " shortcut", b.scripts.shortcuts["Hello"] ?? "", "<Control><Shift>h");
    if (b.find_sheet ("Other").page.print_area != "") {
        stderr.printf ("FAIL %s print area leaked to other sheet\n", fmt);
        Test.fail ();
    }
}

void test_io_xlsx () {
    var book = setup_book ();
    string path = tmp_path ("setup.xlsx");
    try {
        XlsxWriter.save (book, path);
        var back = Xlsx.load (path);
        check_setup ("xlsx", back);
        same ("xlsx watch", back.watches.size.to_string (), "1");
    } catch (Error e) {
        stderr.printf ("FAIL xlsx %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

void test_io_ods () {
    var book = setup_book ();
    string path = tmp_path ("setup.ods");
    try {
        Ods.save (book, path);
        var back = Ods.load (path);
        check_setup ("ods", back);
    } catch (Error e) {
        stderr.printf ("FAIL ods %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

int main (string[] args) {
    Test.init (ref args);
    LocaleInfo.set_c ();
    Test.add_func ("/audit/header-footer", test_header_footer);
    Test.add_func ("/audit/layout", test_layout);
    Test.add_func ("/audit/precedents", test_precedents);
    Test.add_func ("/audit/error-check", test_error_check);
    Test.add_func ("/audit/evaluate", test_evaluate);
    Test.add_func ("/audit/script", test_script);
    Test.add_func ("/audit/recorder", test_recorder);
    Test.add_func ("/audit/io-xlsx", test_io_xlsx);
    Test.add_func ("/audit/io-ods", test_io_ods);
    return Test.run ();
}
