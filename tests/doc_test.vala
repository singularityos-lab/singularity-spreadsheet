using Singularity.Apps.Spreadsheet;

Document doc;
Sheet sh;

void put (int r, int c, string v) {
    sh.set_input (r, c, v);
}

string at (int r, int c) {
    return sh.value_at (r, c).display ();
}

void setup () {
    LocaleInfo.set_c ();
    doc = new Document ();
    sh = doc.book.sheets[0];
}

void test_undo () {
    setup ();
    doc.set_input (sh, 0, 0, "5");
    doc.set_input (sh, 0, 1, "=A1*2");
    assert (at (0, 1) == "10");
    doc.set_input (sh, 0, 0, "7");
    assert (at (0, 1) == "14");
    doc.undo ();
    assert (at (0, 0) == "5" && at (0, 1) == "10");
    doc.redo ();
    assert (at (0, 0) == "7");
    doc.edit_style (sh, new Area (sh, 0, 0, 0, 1), "Bold", (st) => st.bold = true);
    assert (sh.style_at (0, 1).bold);
    doc.undo ();
    assert (!sh.style_at (0, 1).bold);
    doc.insert_rows (sh, 0, 1);
    assert (sh.input_at (1, 1) == "=A2*2");
    doc.undo ();
    assert (sh.input_at (0, 1) == "=A1*2" && at (0, 1) == "14");
}

void test_paste () {
    setup ();
    put (0, 0, "1");
    put (1, 0, "2");
    put (0, 1, "=A1*10");
    doc.book.recalculate ();
    doc.copy (sh, new Area (sh, 0, 1, 0, 1), false);
    doc.paste (sh, 1, 1);
    assert (sh.input_at (1, 1) == "=A2*10" && at (1, 1) == "20");
    doc.copy (sh, new Area (sh, 0, 0, 1, 0), true);
    doc.paste (sh, 0, 3);
    assert (sh.get_cell (0, 0) == null);
    assert (at (0, 3) == "1");
    assert (sh.input_at (0, 1) == "=D1*10");
    doc.copy (sh, new Area (sh, 0, 3, 1, 3), false);
    doc.paste (sh, 5, 0, Document.PasteMode.TRANSPOSE);
    assert (at (5, 0) == "1" && at (5, 1) == "2");
    doc.paste_text (sh, 10, 0, "a\tb\n1\t2\n");
    assert (at (10, 1) == "b" && at (11, 1) == "2");
    assert (sh.value_at (11, 1).kind == ValueKind.NUMBER);
}

void test_fill () {
    setup ();
    put (0, 0, "1");
    put (1, 0, "3");
    doc.fill_series (sh, new Area (sh, 0, 0, 1, 0), new Area (sh, 0, 0, 4, 0));
    assert (at (4, 0) == "9");
    put (0, 1, "Item 1");
    doc.fill_series (sh, new Area (sh, 0, 1, 0, 1), new Area (sh, 0, 1, 2, 1));
    assert (at (2, 1) == "Item 3");
    put (0, 2, "Jan");
    doc.fill_series (sh, new Area (sh, 0, 2, 0, 2), new Area (sh, 0, 2, 12, 2));
    assert (at (1, 2) == "Feb" && at (12, 2) == "Jan");
    put (0, 3, "=A1*2");
    doc.fill_series (sh, new Area (sh, 0, 3, 0, 3), new Area (sh, 0, 3, 3, 3));
    assert (sh.input_at (3, 3) == "=A4*2" && at (3, 3) == "14");
    put (0, 4, "2024-01-30");
    doc.fill_series (sh, new Area (sh, 0, 4, 0, 4), new Area (sh, 0, 4, 2, 4));
    string color;
    assert (NumberFormat.format (sh.value_at (2, 4).number, sh.style_at (2, 4).number_format, out color) == "2024-02-01");
    put (0, 5, "x");
    doc.fill_series (sh, new Area (sh, 0, 5, 0, 5), new Area (sh, 0, 5, 0, 7));
    assert (at (0, 7) == "x");
}

void test_sort_dedupe () {
    setup ();
    string[] names = { "Name", "pear", "apple", "fig", "apple" };
    string[] qty = { "Qty", "3", "10", "7", "1" };
    for (int i = 0; i < names.length; i++) {
        put (i, 0, names[i]);
        put (i, 1, qty[i]);
        if (i > 0) put (i, 2, "=B%d*2".printf (i + 1));
    }
    doc.book.recalculate ();
    var keys = new Gee.ArrayList<SortKey> ();
    keys.add (new SortKey (0, true));
    keys.add (new SortKey (1, false));
    doc.sort (sh, new Area (sh, 0, 0, 4, 2), keys, true);
    assert (at (0, 0) == "Name");
    assert (at (1, 0) == "apple" && at (1, 1) == "10" && at (1, 2) == "20");
    assert (at (2, 0) == "apple" && at (2, 1) == "1");
    assert (at (4, 0) == "pear" && at (4, 2) == "6");
    assert (sh.input_at (4, 2) == "=B5*2");
    int removed = doc.remove_duplicates (sh, new Area (sh, 0, 0, 4, 2), { 0 }, true);
    assert (removed == 1 && at (2, 0) == "fig" && at (3, 0) == "pear" && at (4, 0) == "");
    doc.undo ();
    assert (at (4, 0) == "pear");
}

void test_sheets_and_filter () {
    setup ();
    put (0, 0, "Fruit");
    put (1, 0, "apple");
    put (2, 0, "pear");
    put (3, 0, "apple");
    var s2 = doc.add_sheet ();
    s2.set_input (0, 0, "=Sheet1!A2");
    doc.rename_sheet (sh, "Fruits");
    assert (s2.input_at (0, 0) == "=Fruits!A2");
    doc.book.recalculate ();
    assert (s2.value_at (0, 0).display () == "apple");
    var dup = doc.duplicate_sheet (s2);
    assert (dup.name == "Sheet2 (2)" && dup.input_at (0, 0) == "=Fruits!A2");
    doc.remove_sheet (sh);
    assert (s2.input_at (0, 0) == "=#REF!");
    doc.undo ();
    assert (doc.book.sheets.size == 3 && s2.input_at (0, 0) == "=Fruits!A2");
    doc.toggle_filter (sh, new Area.cell (sh, 0, 0));
    assert (sh.filter != null && sh.filter.area.to_string () == "A1:A4");
    var hide = new Gee.HashSet<string> ();
    hide.add ("apple");
    doc.set_filter_values (sh, 0, hide);
    assert (sh.hidden_rows.contains (1) && !sh.hidden_rows.contains (2) && sh.hidden_rows.contains (3));
    doc.toggle_filter (sh, new Area.cell (sh, 0, 0));
    assert (sh.hidden_rows.size == 0);
    doc.merge (sh, new Area (sh, 5, 0, 5, 2), true);
    assert (sh.merge_at (5, 1) != null && sh.style_at (5, 0).halign == HAlign.CENTER);
    doc.undo ();
    assert (sh.merge_at (5, 1) == null);
}

void test_layout () {
    setup ();
    var w = new Gee.HashMap<int, int> ();
    w[2] = 50;
    w[5] = 10;
    var hidden = new Gee.HashSet<int> ();
    hidden.add (3);
    var ax = new Axis (MAX_COLS, 20, w, hidden);
    assert (ax.pos (0) == 0 && ax.pos (2) == 40 && ax.pos (3) == 90 && ax.pos (4) == 90);
    assert (ax.pos (6) == 90 + 20 + 10);
    assert (ax.index_at (45) == 2 && ax.index_at (90) == 4 && ax.index_at (119) == 5);
    assert (ax.size (3) == 0 && ax.size (5) == 10 && ax.size (7) == 20);
    assert (ax.total () == (int64) MAX_COLS * 20 + 30 - 20 - 10);
    for (int i = 0; i < 5; i++) put (i, 0, (i * 10).to_string ());
    put (5, 0, "10");
    var scale = new CondFormat (new Area (sh, 0, 0, 5, 0), CondKind.COLOR_SCALE);
    scale.three_colors = false;
    scale.color1 = "#000000";
    scale.color3 = "#ffffff";
    sh.cond_formats.add (scale);
    var dup = new CondFormat (new Area (sh, 0, 0, 5, 0), CondKind.DUPLICATE);
    var red = new CellStyle ();
    red.color = "#ff0000";
    dup.style = doc.book.intern (red);
    sh.cond_formats.add (dup);
    var gt = new CondFormat (new Area (sh, 0, 0, 5, 0), CondKind.FORMULA);
    gt.a = "=A1>25";
    var bold = new CellStyle ();
    bold.bold = true;
    gt.style = doc.book.intern (bold);
    sh.cond_formats.add (gt);
    doc.book.recalculate ();
    var ce = new CondEval (doc.book, sh);
    assert (ce.apply (0, 0, sh.value_at (0, 0)).fill == "#000000");
    assert (ce.apply (4, 0, sh.value_at (4, 0)).fill == "#ffffff");
    assert (ce.apply (2, 0, sh.value_at (2, 0)).fill == "#808080");
    assert (ce.apply (1, 0, sh.value_at (1, 0)).color == "#ff0000");
    assert (ce.apply (2, 0, sh.value_at (2, 0)).color == "");
    assert (ce.apply (3, 0, sh.value_at (3, 0)).bold && !ce.apply (2, 0, sh.value_at (2, 0)).bold);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Test.init (ref args);
    Test.add_func ("/doc/undo", test_undo);
    Test.add_func ("/doc/paste", test_paste);
    Test.add_func ("/doc/fill", test_fill);
    Test.add_func ("/doc/sort-dedupe", test_sort_dedupe);
    Test.add_func ("/doc/sheets-filter", test_sheets_and_filter);
    Test.add_func ("/doc/layout", test_layout);
    return Test.run ();
}
