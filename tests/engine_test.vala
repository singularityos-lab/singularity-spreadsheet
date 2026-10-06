using Singularity.Apps.Spreadsheet;

Workbook book;
Sheet sh;

void set (string addr, string input) {
    int r, c;
    bool a, b;
    Address.parse_cell (addr, out r, out c, out a, out b);
    sh.set_input (r, c, input);
}

string val (string formula) {
    set ("Z1000", formula);
    book.recalculate ();
    var v = sh.value_at (999, 25);
    return v.display ();
}

void check (string formula, string expected) {
    string got = val (formula);
    if (got != expected) {
        stderr.printf ("FAIL %s: expected [%s] got [%s]\n", formula, expected, got);
        Test.fail ();
    }
}

void test_parse_render () {
    string[] cases = {
        "=1+2*3", "=(1+2)*3", "=-2^2", "=SUM(A1:B2)", "=$A$1+A$2+$B3", "=Sheet2!A1", "='My Sheet'!A1:B3",
        "=A:A", "=1:3", "=IF(A1>1,\"yes\",\"no\")", "=\"a\"\"b\"", "=50%", "={1,2;3,4}", "=SUM(A1,,B1)", "=A1&\" \"&B1",
        "=1E+20", "=0.5", "=NOT(TRUE)", "=#N/A", "=A1:INDEX(B1:B5,2)"
    };
    book = new Workbook ();
    sh = book.add_sheet ("Sheet1");
    book.add_sheet ("Sheet2");
    book.add_sheet ("My Sheet");
    foreach (string c in cases) {
        try {
            var n = Formula.parse (c, book, sh);
            string back = Formula.to_text (n, sh);
            if (back != c) {
                stderr.printf ("render %s -> %s\n", c, back);
                Test.fail ();
            }
        } catch (FormulaError e) {
            stderr.printf ("parse %s: %s\n", c, e.message);
            Test.fail ();
        }
    }
}

void test_eval () {
    LocaleInfo.set_c ();
    book = new Workbook ();
    sh = book.add_sheet ("Sheet1");
    var s2 = book.add_sheet ("Data");
    set ("A1", "1");
    set ("A2", "2");
    set ("A3", "3");
    set ("A4", "text");
    set ("A5", "TRUE");
    set ("B1", "=A1*10");
    set ("B2", "=B1+A2");
    set ("C1", "apple");
    set ("C2", "banana");
    set ("C3", "cherry");
    set ("D1", "10");
    set ("D2", "20");
    set ("D3", "30");
    s2.set_input (0, 0, "42");
    check ("=1+2*3", "7");
    check ("=-2^2", "4");
    check ("=2^3^2", "64");
    check ("=10/4", "2.5");
    check ("=1/0", "#DIV/0!");
    check ("=\"a\"&1&TRUE", "a1TRUE");
    check ("=A1+A2+A3", "6");
    check ("=B2", "12");
    check ("=SUM(A1:A5)", "6");
    check ("=SUM(A1:A3,10,TRUE)", "17");
    check ("=AVERAGE(A1:A3)", "2");
    check ("=COUNT(A1:A5)", "3");
    check ("=COUNTA(A1:A5)", "5");
    check ("=COUNTBLANK(A1:A10)", "5");
    check ("=MAX(A1:A3)*MIN(D1:D3)", "30");
    check ("=Data!A1*2", "84");
    check ("=SUM(A:A)", "6");
    check ("=IF(A1>0,\"pos\",\"neg\")", "pos");
    check ("=IF(A1>5,1)", "FALSE");
    check ("=IFERROR(1/0,\"x\")", "x");
    check ("=AND(TRUE,A1=1)", "TRUE");
    check ("=OR(FALSE,A1=2)", "FALSE");
    check ("=VLOOKUP(\"banana\",C1:D3,2,FALSE)", "20");
    check ("=VLOOKUP(2.5,A1:B3,2)", "12");
    check ("=HLOOKUP(1,A1:D1,4,FALSE)", "#REF!");
    check ("=HLOOKUP(9,A1:D1,1,FALSE)", "#N/A");
    check ("=INDEX(D1:D3,2)", "20");
    check ("=MATCH(\"cherry\",C1:C3,0)", "3");
    check ("=MATCH(\"b*\",C1:C3,0)", "2");
    check ("=XLOOKUP(\"cherry\",C1:C3,D1:D3)", "30");
    check ("=XLOOKUP(\"kiwi\",C1:C3,D1:D3,\"none\")", "none");
    check ("=SUMIF(C1:C3,\"<>apple\",D1:D3)", "50");
    check ("=SUMIF(D1:D3,\">15\")", "50");
    check ("=COUNTIF(C1:C3,\"*e*\")", "2");
    check ("=SUMIFS(D1:D3,C1:C3,\"?a*\",D1:D3,\">10\")", "20");
    check ("=AVERAGEIF(D1:D3,\">=20\")", "25");
    check ("=SUMPRODUCT(A1:A3,D1:D3)", "140");
    check ("=SUM(A1:A3*D1:D3)", "140");
    check ("=ROUND(2.675,2)", "2.68");
    check ("=ROUND(-1.5,0)", "-2");
    check ("=ROUNDUP(1.21,1)", "1.3");
    check ("=ROUNDDOWN(-1.29,1)", "-1.2");
    check ("=MOD(-3,2)", "1");
    check ("=INT(-1.5)", "-2");
    check ("=CEILING(4.1,0.5)", "4.5");
    check ("=FLOOR(4.9,2)", "4");
    check ("=LEFT(\"héllo\",2)", "hé");
    check ("=RIGHT(\"hello\",3)", "llo");
    check ("=MID(\"hello\",2,3)", "ell");
    check ("=LEN(\"héllo\")", "5");
    check ("=UPPER(\"abc\")&LOWER(\"DEF\")", "ABCdef");
    check ("=PROPER(\"hello wORLD\")", "Hello World");
    check ("=TRIM(\"  a   b  \")", "a b");
    check ("=SUBSTITUTE(\"a-b-c\",\"-\",\"+\")", "a+b+c");
    check ("=SUBSTITUTE(\"a-b-c\",\"-\",\"+\",2)", "a-b+c");
    check ("=FIND(\"l\",\"hello\")", "3");
    check ("=SEARCH(\"L*O\",\"hello\")", "3");
    check ("=TEXTJOIN(\",\",TRUE,C1:C3)", "apple,banana,cherry");
    check ("=CONCAT(C1:C2)", "applebanana");
    check ("=REPT(\"ab\",3)", "ababab");
    check ("=VALUE(\"12.5\")", "12.5");
    check ("=TEXT(1234.567,\"#,##0.00\")", "1,234.57");
    check ("=TEXT(0.256,\"0.0%\")", "25.6%");
    check ("=TEXT(DATE(2024,3,5),\"yyyy-mm-dd\")", "2024-03-05");
    check ("=TEXT(DATE(2024,3,5),\"d mmm yyyy\")", "5 Mar 2024");
    check ("=DATE(2024,1,1)", "45292");
    check ("=DATE(1900,3,1)", "61");
    check ("=YEAR(45292)&\"-\"&MONTH(45292)&\"-\"&DAY(45292)", "2024-1-1");
    check ("=WEEKDAY(DATE(2024,1,1))", "2");
    check ("=EOMONTH(DATE(2024,1,15),1)", "45351");
    check ("=EDATE(DATE(2024,1,31),1)", "45351");
    check ("=DATEDIF(DATE(2020,5,15),DATE(2024,3,10),\"Y\")", "3");
    check ("=NETWORKDAYS(DATE(2024,1,1),DATE(2024,1,31))", "23");
    check ("=WORKDAY(DATE(2024,1,5),1)", "45299");
    check ("=HOUR(0.75)", "18");
    check ("=TIME(12,30,0)", "0.520833333");
    check ("=1234.56789012", "1234.56789");
    check ("=1/3", "0.333333333");
    check ("=-2/3", "-0.666666667");
    check ("=ISOWEEKNUM(DATE(2024,12,30))", "1");
    check ("=ROUND(PMT(0.05/12,360,200000),2)", "-1073.64");
    check ("=ROUND(FV(0.06/12,10,-200,-500,1),2)", "2581.4");
    check ("=ROUND(RATE(48,-200,8000),6)", "0.007701");
    check ("=ROUND(NPV(0.1,-10000,3000,4200,6800),2)", "1188.44");
    check ("=ROUND(IRR({-70000,12000,15000,18000,21000,26000}),6)", "0.086631");
    check ("=MEDIAN(1,3,2,4)", "2.5");
    check ("=ROUND(STDEV(2,4,4,4,5,5,7,9),6)", "2.13809");
    check ("=STDEVP(2,4,4,4,5,5,7,9)", "2");
    check ("=LARGE(D1:D3,1)+SMALL(D1:D3,1)", "40");
    check ("=RANK(20,D1:D3)", "2");
    check ("=PERCENTILE(D1:D3,0.25)", "15");
    check ("=QUARTILE({1,2,3,4,5},3)", "4");
    check ("=CORREL(A1:A3,D1:D3)", "1");
    check ("=SLOPE(D1:D3,A1:A3)", "10");
    check ("=ROUND(NORM.S.DIST(1.96,TRUE),4)", "0.975");
    check ("=ROUND(NORM.S.INV(0.975),4)", "1.96");
    check ("=CHOOSE(2,\"a\",\"b\",\"c\")", "b");
    check ("=ROWS(A1:B5)*COLUMNS(A1:B5)", "10");
    check ("=ADDRESS(2,3)", "$C$2");
    check ("=SUM(OFFSET(A1,1,0,2,1))", "5");
    check ("=INDIRECT(\"D\"&2)", "20");
    check ("=SUM(INDIRECT(\"Data!A1\"))", "42");
    check ("=ISNUMBER(A1)&ISTEXT(A4)&ISBLANK(A9)", "TRUETRUETRUE");
    check ("=NA()", "#N/A");
    check ("=SWITCH(2,1,\"one\",2,\"two\",\"other\")", "two");
    check ("=IFS(A1>5,\"big\",A1>0,\"small\")", "small");
    check ("=1+\"2\"", "3");
    check ("=\"x\"+1", "#VALUE!");
    check ("=A4*2", "#VALUE!");
    check ("=FOO(1)", "#NAME?");
    check ("=SUBTOTAL(9,D1:D3)", "60");
    check ("=GCD(12,18)&\"/\"&LCM(4,6)", "6/12");
    check ("=COMBIN(5,2)", "10");
    check ("={1,2;3,4}", "1");
    check ("=SUM({1,2;3,4})", "10");
    check ("=MAXIFS(D1:D3,C1:C3,\"<>banana\")", "30");
    check ("=XMATCH(25,D1:D3,-1)", "2");
    check ("=LOOKUP(2.5,A1:A3,D1:D3)", "20");
    check ("=TEXTBEFORE(\"a.b.c\",\".\",2)", "a.b");
    check ("=FIXED(1234.5,1)", "1,234.5");
}

void test_cycles () {
    book = new Workbook ();
    sh = book.add_sheet ("Sheet1");
    set ("A1", "=B1+1");
    set ("B1", "=A1+1");
    book.recalculate ();
    assert (sh.value_at (0, 0).display () == "#CIRC!");
}

void test_chain () {
    book = new Workbook ();
    sh = book.add_sheet ("Sheet1");
    sh.set_input (0, 0, "1");
    for (int i = 1; i < 20000; i++) sh.set_input (i, 0, "=A%d+1".printf (i));
    var t = get_monotonic_time ();
    book.recalculate ();
    assert (sh.value_at (19999, 0).display () == "20000");
    int64 ms = (get_monotonic_time () - t) / 1000;
    if (ms > 3000) {
        stderr.printf ("chain recalc slow: %lld ms\n", ms);
        Test.fail ();
    }
}

void test_insert_delete () {
    book = new Workbook ();
    sh = book.add_sheet ("Sheet1");
    set ("A1", "1");
    set ("A2", "2");
    set ("A3", "=SUM(A1:A2)");
    set ("B1", "=$A$2*2");
    book.insert_rows (sh, 1, 2);
    book.recalculate ();
    assert (sh.input_at (4, 0) == "=SUM(A1:A4)");
    assert (sh.input_at (0, 1) == "=$A$4*2");
    assert (sh.value_at (4, 0).display () == "3");
    book.delete_rows (sh, 3, 1);
    book.recalculate ();
    assert (sh.input_at (0, 1) == "=#REF!*2");
    assert (sh.input_at (3, 0) == "=SUM(A1:A3)");
    book.insert_cols (sh, 0, 1);
    assert (sh.input_at (3, 1) == "=SUM(B1:B3)");
}

void test_shift () {
    book = new Workbook ();
    sh = book.add_sheet ("Sheet1");
    try {
        var n = Formula.parse ("=A1+$B$1+C$1+$D1+SUM(A1:A3)", book, sh);
        var m = Formula.shifted (n, 2, 1);
        assert (Formula.to_text (m, sh) == "=B3+$B$1+D$1+$D3+SUM(B3:B5)");
        var bad = Formula.shifted (n, -1, 0);
        assert (Formula.to_text (bad, sh).has_prefix ("=#REF!"));
    } catch (FormulaError e) {
        assert_not_reached ();
    }
}

void test_input_and_format () {
    LocaleInfo.set_c ();
    string color;
    var p = Input.parse ("1,234.5");
    assert (p.value.number == 1234.5 && p.format == "#,##0.0");
    p = Input.parse ("12%");
    assert (p.value.number == 0.12 && p.format == "0%");
    p = Input.parse ("$1,000");
    assert (p.value.number == 1000 && p.format == "$#,##0.00");
    p = Input.parse ("2024-03-05");
    assert (p.value.number == 45356 && p.format == "yyyy-mm-dd");
    p = Input.parse ("13:45");
    assert (Math.fabs (p.value.number - 0.5729166667) < 1e-9);
    p = Input.parse ("'007");
    assert (p.value.kind == ValueKind.TEXT && p.value.text == "007");
    p = Input.parse ("1.2.3");
    assert (p.value.kind == ValueKind.TEXT);
    assert (NumberFormat.format (1234.5, "#,##0.00", out color) == "1,234.50");
    assert (NumberFormat.format (-1234.5, "#,##0.00;[Red](#,##0.00)", out color) == "(1,234.50)" && color == "red");
    assert (NumberFormat.format (0, "0.0;-0.0;\"zero\"", out color) == "zero");
    assert (NumberFormat.format (0.5, "0%", out color) == "50%");
    assert (NumberFormat.format (12345.678, "0.00E+00", out color) == "1.23E+04");
    assert (NumberFormat.format (1.5, "# ?/?", out color) == "1 1/2");
    assert (NumberFormat.format (45356.75, "dd/mm/yyyy hh:mm", out color) == "05/03/2024 18:00");
    assert (NumberFormat.format (45356, "dddd", out color) == "Tuesday");
    assert (NumberFormat.format (1.5, "[h]:mm", out color) == "36:00");
    assert (NumberFormat.format (0.5, "h:mm AM/PM", out color) == "12:00 PM");
    assert (NumberFormat.format (1234567, "#,##0,\"K\"", out color) == "1,235K");
    assert (NumberFormat.format (-5, "0", out color) == "-5");
    assert (NumberFormat.format (42, "\"Total: \"0", out color) == "Total: 42");
    assert (NumberFormat.format (0.1 + 0.2, "General", out color) == "0.3");
    assert (NumberFormat.format (123456789012.0, "General", out color) == "1.23457E+11");
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Environment.set_variable ("LC_ALL", "C", true);
    Test.init (ref args);
    Test.add_func ("/engine/parse-render", test_parse_render);
    Test.add_func ("/engine/eval", test_eval);
    Test.add_func ("/engine/cycles", test_cycles);
    Test.add_func ("/engine/chain", test_chain);
    Test.add_func ("/engine/insert-delete", test_insert_delete);
    Test.add_func ("/engine/shift", test_shift);
    Test.add_func ("/engine/input-format", test_input_and_format);
    return Test.run ();
}
