using Singularity.Apps.Spreadsheet;

string tmp_path (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "ss-io-%d-%s".printf (Random.int_range (0, 1000000), name));
}

Workbook sample () {
    var book = new Workbook ();
    var s = book.add_sheet ("Sales");
    var d = book.add_sheet ("Other Data");
    s.set_input (0, 0, "Item");
    s.set_input (0, 1, "Qty");
    s.set_input (0, 2, "Price");
    s.set_input (0, 3, "Total");
    string[] items = { "Apple", "Pear", "Plum \"red\"", "Kiwi, green" };
    for (int i = 0; i < items.length; i++) {
        s.set_input (i + 1, 0, items[i]);
        s.set_input (i + 1, 1, (i + 2).to_string ());
        s.set_input (i + 1, 2, "1.5");
        s.set_input (i + 1, 3, "=B%d*C%d".printf (i + 2, i + 2));
    }
    s.set_input (5, 3, "=SUM(D2:D5)");
    s.set_input (6, 0, "2024-03-05");
    s.set_input (6, 1, "25%");
    s.set_input (6, 2, "=XLOOKUP(\"Pear\",A2:A5,B2:B5)");
    s.set_input (6, 3, "='Other Data'!A1*2");
    d.set_input (0, 0, "21");
    var st = new CellStyle ();
    st.bold = true;
    st.fill = "#ffcc00";
    st.halign = HAlign.CENTER;
    st.bottom = new Border (BorderStyle.THIN, "#333333");
    int bold = book.intern (st);
    for (int c = 0; c < 4; c++) s.set_style (0, c, bold);
    var money = new CellStyle ();
    money.number_format = "#,##0.00 \"EUR\"";
    int mi = book.intern (money);
    s.set_style (5, 3, mi);
    s.merges.add (new Area (s, 8, 0, 8, 3));
    s.set_input (8, 0, "Merged");
    s.col_widths[0] = 160;
    s.row_heights[8] = 40;
    s.freeze_rows = 1;
    s.hidden_rows.add (7);
    var cf = new CondFormat (new Area (s, 1, 3, 4, 3), CondKind.GREATER);
    cf.a = "4";
    var hl = new CellStyle ();
    hl.fill = "#ff0000";
    cf.style = book.intern (hl);
    s.cond_formats.add (cf);
    book.names["Rate"] = "Sales!$C$2";
    s.set_input (9, 0, "=Rate*2");
    book.recalculate ();
    return book;
}

void check_sample (Workbook b, bool full) {
    var s = b.find_sheet ("Sales");
    assert (s != null);
    assert (b.sheets.size == 2 && b.sheets[1].name == "Other Data");
    assert (s.value_at (0, 0).display () == "Item");
    assert (s.value_at (3, 0).display () == "Plum \"red\"");
    assert (s.value_at (5, 3).display () == "21");
    assert (s.input_at (5, 3) == "=SUM(D2:D5)");
    assert (s.value_at (6, 2).display () == "3");
    assert (s.value_at (6, 3).display () == "42");
    assert (s.input_at (6, 3) == "='Other Data'!A1*2");
    assert (s.value_at (6, 0).display () == "45356");
    if (!full) return;
    assert (s.input_at (6, 2) == "=XLOOKUP(\"Pear\",A2:A5,B2:B5)");
    assert (s.style_at (6, 0).number_format == "yyyy-mm-dd");
    assert (s.style_at (6, 1).number_format == "0%");
    var h = s.style_at (0, 1);
    assert (h.bold && h.fill == "#ffcc00" && h.halign == HAlign.CENTER);
    assert (h.bottom.style == BorderStyle.THIN && h.bottom.color == "#333333");
    assert (s.style_at (5, 3).number_format == "#,##0.00 \"EUR\"");
    assert (s.merges.size == 1 && s.merges[0].to_string () == "A9:D9");
    assert ((s.col_widths[0] - 160).abs () <= 2);
    assert ((s.row_heights[8] - 40).abs () <= 2);
    assert (s.freeze_rows == 1);
    assert (s.hidden_rows.contains (7));
    assert (s.cond_formats.size == 1 && s.cond_formats[0].kind == CondKind.GREATER && s.cond_formats[0].a == "4");
    assert (b.styles[s.cond_formats[0].style].fill == "#ff0000");
    assert (s.value_at (9, 0).display () == "3");
}

void test_xlsx () {
    LocaleInfo.set_c ();
    var book = sample ();
    string path = tmp_path ("a.xlsx");
    try {
        XlsxWriter.save (book, path);
        var back = Xlsx.load (path);
        check_sample (back, true);
        string path2 = tmp_path ("b.xlsx");
        XlsxWriter.save (back, path2);
        check_sample (Xlsx.load (path2), true);
        FileUtils.remove (path2);
    } catch (Error e) {
        stderr.printf ("%s\n", e.message);
        assert_not_reached ();
    }
    FileUtils.remove (path);
}

void test_ods () {
    LocaleInfo.set_c ();
    var book = sample ();
    string path = tmp_path ("a.ods");
    try {
        Ods.save (book, path);
        var back = Ods.load (path);
        check_sample (back, false);
        assert (back.find_sheet ("Sales").merges.size == 1);
    } catch (Error e) {
        stderr.printf ("%s\n", e.message);
        assert_not_reached ();
    }
    FileUtils.remove (path);
}

void test_csv () {
    LocaleInfo.set_c ();
    var book = sample ();
    string text = Csv.export (book.sheets[0], ',');
    assert (text.has_prefix ("Item,Qty,Price,Total\n"));
    assert (text.contains ("\"Plum \"\"red\"\"\",4,1.5,6\n"));
    assert (text.contains ("\"Kiwi, green\",5,1.5,7.5\n"));
    var rows = Csv.parse ("a;\"b;c\";d\r\n1;2;\"multi\nline\"\n", Csv.detect ("a;\"b;c\";d\r\n1;2;3\n"));
    assert (rows.size == 2 && rows[0][1] == "b;c" && rows[1][2] == "multi\nline");
    assert (Csv.detect ("a\tb\tc\n1\t2\t3") == '\t');
}

void test_zip () {
    try {
        var w = new ZipWriter ();
        w.add_text ("a.txt", "hello hello hello hello");
        w.add_text ("dir/b.txt", "stored", false);
        var r = new ZipReader (w.finish ());
        assert (r.read_text ("a.txt") == "hello hello hello hello");
        assert (r.read_text ("dir/b.txt") == "stored");
        assert (r.read ("missing") == null);
    } catch (Error e) {
        assert_not_reached ();
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Test.init (ref args);
    Test.add_func ("/io/zip", test_zip);
    Test.add_func ("/io/xlsx", test_xlsx);
    Test.add_func ("/io/ods", test_ods);
    Test.add_func ("/io/csv", test_csv);
    return Test.run ();
}
