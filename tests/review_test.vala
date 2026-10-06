using Singularity.Apps.Spreadsheet;

int failures = 0;

void check (bool ok, string what) {
    if (!ok) {
        stderr.printf ("FAIL %s\n", what);
        failures++;
    }
}

string tmp_path (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "ss-rev-%d-%s".printf (Random.int_range (0, 1000000), name));
}

int count_kind (Workbook b, ChangeKind k) {
    int n = 0;
    foreach (var c in b.revisions.changes) if (c.kind == k) n++;
    return n;
}

Document tracked () {
    var doc = new Document ();
    var s = doc.book.sheets[0];
    doc.set_input (s, 0, 0, "Item");
    doc.set_input (s, 1, 0, "10");
    var t = ReviewTracker.of (doc);
    t.author_override = "Anna Rossi";
    t.set_tracking (true);
    return doc;
}

void test_record () {
    var doc = tracked ();
    var s = doc.book.sheets[0];
    check (doc.book.revisions.changes.size == 0, "nothing before tracking");
    doc.set_input (s, 1, 0, "12");
    doc.set_input (s, 2, 1, "=A2*2");
    var c = doc.book.revisions.cell_change (s, 1, 0);
    check (c != null && c.old_input == "10" && c.new_input == "12" && c.author == "Anna Rossi", "cell change recorded");
    check (c.describe () == "Changed cell A2 from \"10\" to \"12\"", "describe " + c.describe ());
    doc.insert_rows (s, 0, 2);
    check (count_kind (doc.book, ChangeKind.INSERT_ROWS) == 1, "insert rows recorded");
    check (doc.book.revisions.cell_change (s, 3, 0) != null, "cell change shifted with insert");
    check (count_kind (doc.book, ChangeKind.CELL) == 2, "insert rows did not create cell changes");
    doc.rename_sheet (s, "Budget");
    check (count_kind (doc.book, ChangeKind.RENAME_SHEET) == 1, "rename recorded");
    var s2 = doc.add_sheet ();
    check (count_kind (doc.book, ChangeKind.INSERT_SHEET) == 1, "insert sheet recorded");
    doc.remove_sheet (s2);
    check (count_kind (doc.book, ChangeKind.DELETE_SHEET) == 1, "delete sheet recorded");
    doc.set_input (s, 10, 0, "gone");
    doc.delete_rows (s, 10, 1);
    Change? del = null;
    foreach (var ch in doc.book.revisions.changes) if (ch.kind == ChangeKind.DELETE_ROWS) del = ch;
    check (del != null && del.removed.size == 1 && del.removed[0].input == "gone", "deleted row content saved");
}

void test_accept_reject () {
    var doc = tracked ();
    var s = doc.book.sheets[0];
    var t = ReviewTracker.of (doc);
    doc.set_input (s, 1, 0, "12");
    doc.set_input (s, 1, 0, "15");
    doc.set_input (s, 3, 3, "new");
    check (doc.book.revisions.pending ().size == 3, "three pending");
    var last = doc.book.revisions.cell_change (s, 3, 3);
    t.reject (last);
    check (s.input_at (3, 3) == "", "reject restores blank");
    check (last.state == ChangeState.REJECTED, "rejected state");
    int n = t.reject_all ();
    check (n == 2 && s.input_at (1, 0) == "10", "reject all restores original, got " + s.input_at (1, 0));
    check (doc.book.revisions.pending ().size == 0, "none pending after reject all");
    doc.set_input (s, 1, 0, "20");
    t.accept_all ();
    check (s.input_at (1, 0) == "20" && doc.book.revisions.pending ().size == 0, "accept keeps value");
    doc.insert_cols (s, 0, 1);
    var ins = doc.book.revisions.pending ()[0];
    t.reject (ins);
    check (s.input_at (1, 0) == "20", "reject column insert");
    doc.set_input (s, 5, 0, "keep me");
    doc.delete_rows (s, 5, 1);
    Change? del = null;
    foreach (var ch in doc.book.revisions.pending ()) if (ch.kind == ChangeKind.DELETE_ROWS) del = ch;
    t.reject (del);
    check (s.input_at (5, 0) == "keep me", "reject delete rows restores content");
    doc.set_input (s, 7, 0, "undo me");
    var u = doc.book.revisions.cell_change (s, 7, 0);
    doc.undo ();
    check (u.state == ChangeState.REJECTED, "undo drops the change");
    doc.redo ();
    check (u.state == ChangeState.PENDING, "redo restores the change");
    var filter = new ChangeFilter ();
    filter.who = "Nobody";
    check (t.accept_all (filter) == 0, "filter by author");
}

void test_history () {
    var doc = tracked ();
    var s = doc.book.sheets[0];
    var t = ReviewTracker.of (doc);
    doc.set_input (s, 1, 0, "12");
    doc.set_input (s, 2, 0, "x");
    int before = doc.book.revisions.changes.size;
    var h = t.history_sheet ();
    check (h.name == "History", "history sheet name");
    check (h.input_at (0, 0) == "Action Number", "history header");
    check (h.value_at (1, 3).display () == "Anna Rossi", "history author");
    check (h.value_at (1, 8).display () == "10", "history old value");
    check (doc.book.revisions.changes.size == before, "history not tracked");
}

void compare_logs (Workbook a, Workbook b, string label) {
    check (b.revisions.tracking == a.revisions.tracking, label + " tracking flag");
    check (a.revisions.changes.size == b.revisions.changes.size, label + " count %d vs %d".printf (a.revisions.changes.size, b.revisions.changes.size));
    for (int i = 0; i < int.min (a.revisions.changes.size, b.revisions.changes.size); i++) {
        var x = a.revisions.changes[i];
        var y = b.revisions.changes[i];
        string sx = x.sheet != null ? x.sheet.name : x.sheet_name;
        string sy = y.sheet != null ? y.sheet.name : y.sheet_name;
        check (x.kind == y.kind && x.row == y.row && x.col == y.col && x.old_input == y.old_input && x.new_input == y.new_input && x.author == y.author && x.state == y.state && sx == sy && x.count == y.count,
            label + " change %d (%s %s/%s)".printf (i, y.kind.to_code (), y.old_input, y.new_input));
    }
}

void test_files () {
    var doc = tracked ();
    var s = doc.book.sheets[0];
    var t = ReviewTracker.of (doc);
    doc.set_input (s, 1, 0, "12");
    doc.set_input (s, 2, 1, "=A2*2");
    doc.set_input (s, 3, 0, "text");
    doc.insert_rows (s, 5, 2);
    doc.rename_sheet (s, "Budget");
    doc.set_input (s, 3, 0, "");
    t.accept (doc.book.revisions.changes[0]);
    foreach (string ext in new string[] { "xlsx", "ods" }) {
        string p = tmp_path ("r." + ext);
        try {
            doc.save_to (p, s);
            var back = Document.open (p);
            compare_logs (doc.book, back.book, ext);
            var bs = back.book.sheets[0];
            var c = back.book.revisions.cell_change (bs, 2, 1);
            check (c != null && c.sheet == bs, ext + " sheet resolved");
            if (ext == "ods") {
                uint8[] data;
                FileUtils.get_data (p, out data);
                string content = new ZipReader (data).read_text ("content.xml");
                check (content.contains ("<table:tracked-changes table:track-changes=\"true\">"), "ods tracked-changes element");
                check (content.contains ("table:cell-content-change"), "ods cell-content-change");
                check (content.contains ("<table:insertion") && content.contains ("table:type=\"row\""), "ods insertion");
            } else {
                uint8[] data;
                FileUtils.get_data (p, out data);
                var zip = new ZipReader (data);
                bool found = false;
                foreach (string n in zip.names ()) if (n.has_prefix ("customXml/item") && !n.has_prefix ("customXml/itemProps") && zip.read_text (n).contains (RevisionsIo.NS_REV)) found = true;
                check (found, "xlsx customXml part");
                check (zip.read_text ("xl/_rels/workbook.xml.rels").contains ("relationships/customXml"), "xlsx customXml relationship");
            }
        } catch (Error e) {
            check (false, ext + " error " + e.message);
        }
        FileUtils.remove (p);
    }
}

void test_foreign_ods () {
    var doc = new Document ();
    var s = doc.book.sheets[0];
    s.set_input (0, 0, "7");
    string p = tmp_path ("f.ods");
    try {
        doc.save_to (p, s);
        uint8[] data;
        FileUtils.get_data (p, out data);
        var zip = new ZipReader (data);
        string content = zip.read_text ("content.xml");
        string tc = "<table:tracked-changes table:track-changes=\"true\"><table:cell-content-change table:id=\"ct3\"><table:cell-address table:column=\"0\" table:row=\"0\" table:table=\"0\"/><office:change-info><dc:creator>Libre User</dc:creator><dc:date>2024-01-02T03:04:05</dc:date></office:change-info><table:previous><table:change-track-table-cell office:value-type=\"float\" office:value=\"5\"><text:p>5</text:p></table:change-track-table-cell></table:previous></table:cell-content-change></table:tracked-changes>";
        int at = content.index_of (">", content.index_of ("<office:spreadsheet")) + 1;
        content = content.substring (0, at) + tc + content.substring (at);
        var w = new ZipWriter ();
        foreach (string n in zip.names ()) {
            if (n == "content.xml") w.add_text (n, content);
            else w.add (n, zip.read (n), n != "mimetype");
        }
        FileUtils.set_data (p, w.finish ());
        var back = Document.open (p);
        var c = back.book.revisions.cell_change (back.book.sheets[0], 0, 0);
        check (back.book.revisions.tracking, "foreign tracking flag");
        check (c != null && c.old_input == "5" && c.new_input == "7" && c.author == "Libre User", "foreign libreoffice change");
    } catch (Error e) {
        check (false, "foreign ods " + e.message);
    }
    FileUtils.remove (p);
}

void test_compare_merge () {
    var mine = new Document ();
    var ms = mine.book.sheets[0];
    ms.set_input (0, 0, "Item");
    ms.set_input (1, 0, "10");
    ms.set_input (2, 0, "=A2*2");
    ms.set_input (3, 0, "same");
    mine.book.add_sheet ("Old");
    var other = new Workbook ();
    var os = other.add_sheet (ms.name);
    os.set_input (0, 0, "Item");
    os.set_input (1, 0, "11");
    os.set_input (2, 0, "=A2*3");
    os.set_input (3, 0, "same");
    var bold = new CellStyle ();
    bold.bold = true;
    os.set_style (3, 0, other.intern (bold));
    var extra = other.add_sheet ("Notes");
    extra.set_input (0, 0, "hello");
    other.properties["creator"] = "Marco Bianchi";
    var diffs = WorkbookCompare.compare (mine.book, other);
    int values = 0, formulas = 0, formats = 0, added = 0, removed = 0;
    foreach (var d in diffs) {
        switch (d.kind) {
            case DiffKind.VALUE: values++; break;
            case DiffKind.FORMULA: formulas++; break;
            case DiffKind.FORMAT: formats++; break;
            case DiffKind.SHEET_ADDED: added++; break;
            case DiffKind.SHEET_REMOVED: removed++; break;
        }
    }
    check (values == 1 && formulas == 1 && formats == 1 && added == 1 && removed == 1, "diff kinds %d %d %d %d %d".printf (values, formulas, formats, added, removed));
    foreach (var d in diffs) if (d.kind == DiffKind.SHEET_REMOVED) d.selected = false;
    int n = WorkbookCompare.merge (mine, diffs, WorkbookCompare.author_of (other, "/x/other.xlsx"));
    check (n == 4, "merged four");
    check (ms.input_at (1, 0) == "11" && ms.input_at (2, 0) == "=A2*3", "merged values");
    check (ms.style_at (3, 0).bold, "merged format");
    var ns = mine.book.find_sheet ("Notes");
    check (ns != null && ns.input_at (0, 0) == "hello", "merged sheet");
    check (mine.book.find_sheet ("Old") != null, "unselected removal kept");
    var c = mine.book.revisions.cell_change (ms, 1, 0);
    check (mine.book.revisions.tracking && c != null && c.author == "Marco Bianchi" && c.old_input == "10", "merge recorded as tracked changes");
    check (count_kind (mine.book, ChangeKind.INSERT_SHEET) == 1 && count_kind (mine.book, ChangeKind.RENAME_SHEET) == 0, "merged sheet tracked as insertion");
}

int main (string[] args) {
    Test.init (ref args);
    LocaleInfo.set_c ();
    Test.add_func ("/review/record", test_record);
    Test.add_func ("/review/accept_reject", test_accept_reject);
    Test.add_func ("/review/history", test_history);
    Test.add_func ("/review/files", test_files);
    Test.add_func ("/review/foreign_ods", test_foreign_ods);
    Test.add_func ("/review/compare_merge", test_compare_merge);
    int r = Test.run ();
    if (failures > 0) {
        stderr.printf ("%d failures\n", failures);
        return 1;
    }
    return r;
}
