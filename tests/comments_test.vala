using Singularity.Apps.Spreadsheet;

int failures = 0;

void check (bool ok, string what) {
    if (!ok) {
        stderr.printf ("FAIL %s\n", what);
        failures++;
    }
}

string tmp_path (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "ss-cmt-%d-%s".printf (Random.int_range (0, 1000000), name));
}

Document sample () {
    var doc = new Document ();
    var s = doc.book.sheets[0];
    s.set_input (0, 0, "Revenue");
    s.set_input (1, 0, "1200");
    Comments.add_post (doc, s, 1, 0, "Is this the final figure?", "Anna Rossi");
    Comments.add_post (doc, s, 1, 0, "Yes, confirmed by finance.", "Marco Bianchi");
    Comments.add_post (doc, s, 1, 0, "Thanks, closing this.", "Anna Rossi");
    Comments.set_resolved (doc, s, 1, 0, true);
    Comments.add_post (doc, s, 4, 2, "Empty cell comment\nwith two lines", "Marco Bianchi");
    s.set_input (6, 1, "noted");
    doc.set_note (s, 6, 1, "Plain note");
    Comments.add_post (doc, s, 6, 1, "Thread next to a note", "Anna Rossi");
    return doc;
}

void test_model () {
    var doc = sample ();
    var s = doc.book.sheets[0];
    var t = s.comments.at (1, 0);
    check (t != null && t.posts.size == 3, "three posts");
    check (t.resolved, "resolved");
    check (t.posts[1].author == "Marco Bianchi", "reply author");
    check (t.id.has_prefix ("{") && t.id.length == 38, "guid id");
    Comments.edit_post (doc, s, 1, 0, t.posts[1].id, "Yes, confirmed.");
    check (s.comments.at (1, 0).posts[1].text == "Yes, confirmed.", "edit post");
    Comments.delete_post (doc, s, 1, 0, s.comments.at (1, 0).posts[2].id);
    check (s.comments.at (1, 0).posts.size == 2, "delete reply");
    doc.insert_rows (s, 0, 2);
    check (s.comments.at (3, 0) != null && s.comments.at (1, 0) == null, "shift on insert rows");
    doc.delete_cols (s, 0, 1);
    check (s.comments.at (3, 0) == null && s.comments.at (6, 1) != null, "delete column drops thread and shifts others");
}

void test_undo () {
    var doc = new Document ();
    var s = doc.book.sheets[0];
    Comments.add_post (doc, s, 2, 2, "First", "A");
    Comments.add_post (doc, s, 2, 2, "Reply", "B");
    Comments.set_resolved (doc, s, 2, 2, true);
    check (s.comments.at (2, 2).resolved, "resolved before undo");
    doc.undo ();
    check (!s.comments.at (2, 2).resolved, "undo resolve");
    doc.undo ();
    check (s.comments.at (2, 2).posts.size == 1, "undo reply");
    doc.undo ();
    check (s.comments.at (2, 2) == null, "undo new comment");
    doc.redo ();
    check (s.comments.at (2, 2) != null && s.comments.at (2, 2).posts[0].text == "First", "redo");
    Comments.delete_thread (doc, s, 2, 2);
    check (s.comments.at (2, 2) == null, "delete thread");
    doc.undo ();
    check (s.comments.at (2, 2) != null, "undo delete thread");
}

void compare (Sheet s, string label) {
    var t = s.comments.at (1, 0);
    check (t != null, label + " thread A2");
    if (t == null) return;
    check (t.posts.size == 3, label + " posts %d".printf (t.posts.size));
    check (t.resolved, label + " resolved");
    check (t.posts[0].author == "Anna Rossi" && t.posts[1].author == "Marco Bianchi", label + " authors");
    check (t.posts[1].text == "Yes, confirmed by finance.", label + " reply text");
    var e = s.comments.at (4, 2);
    check (e != null && e.posts[0].text == "Empty cell comment\nwith two lines" && !e.resolved, label + " empty cell thread");
    var n = s.comments.at (6, 1);
    check (n != null && n.posts[0].text == "Thread next to a note", label + " thread beside note");
    var nc = s.get_cell (6, 1);
    check (nc != null && nc.note == "Plain note", label + " note kept");
    var a2 = s.get_cell (1, 0);
    check (a2 == null || a2.note == "", label + " no placeholder note");
}

void test_xlsx () {
    var doc = sample ();
    var s = doc.book.sheets[0];
    string p = tmp_path ("c.xlsx");
    try {
        doc.save_to (p, s);
        uint8[] data;
        FileUtils.get_data (p, out data);
        var zip = new ZipReader (data);
        check (zip.has ("xl/threadedComments/threadedComment1.xml") || zip.has ("xl/threadedComments/threadedComment2.xml") || zip.has ("xl/threadedComments/threadedComment3.xml"), "threaded part");
        check (zip.has ("xl/persons/person.xml"), "persons part");
        bool legacy = false;
        bool tc_author = false;
        foreach (string name in zip.names ()) {
            if (name.has_prefix ("xl/comments")) {
                string text = zip.read_text (name);
                if (text.contains (CommentsIo.LEGACY_PREFIX)) legacy = true;
                if (text.contains ("<author>tc={")) tc_author = true;
            }
        }
        check (legacy && tc_author, "legacy placeholder");
        string ct = zip.read_text ("[Content_Types].xml");
        check (ct.contains ("application/vnd.ms-excel.threadedcomments+xml") && ct.contains ("application/vnd.ms-excel.person+xml"), "content types");
        string wr = zip.read_text ("xl/_rels/workbook.xml.rels");
        check (wr.contains ("2017/10/relationships/person"), "person rel");
        var back = Document.open (p);
        compare (back.book.sheets[0], "xlsx");
    } catch (Error e) {
        check (false, "xlsx error " + e.message);
    }
    FileUtils.remove (p);
}

void test_ods () {
    var doc = sample ();
    var s = doc.book.sheets[0];
    string p = tmp_path ("c.ods");
    try {
        doc.save_to (p, s);
        uint8[] data;
        FileUtils.get_data (p, out data);
        var zip = new ZipReader (data);
        string content = zip.read_text ("content.xml");
        check (content.contains ("<text:p>Anna Rossi: Is this the final figure?</text:p>"), "ods visible annotation");
        check (content.contains (CommentsIo.NS_SS), "ods marker");
        var back = Document.open (p);
        compare (back.book.sheets[0], "ods");
    } catch (Error e) {
        check (false, "ods error " + e.message);
    }
    FileUtils.remove (p);
}

void test_foreign_annotation () {
    var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<ThreadedComments xmlns=\"http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments\"><threadedComment ref=\"B2\" dT=\"2023-05-04T10:11:12.00\" personId=\"{1}\" id=\"{A}\" done=\"1\"><text>Root</text></threadedComment><threadedComment ref=\"B2\" dT=\"2023-05-04T10:12:12.00\" personId=\"{2}\" id=\"{B}\" parentId=\"{A}\"><text>Child</text></threadedComment></ThreadedComments>";
    var doc = Xlsx.parse (xml);
    check (doc != null, "parse threaded xml");
    delete doc;
}

int main (string[] args) {
    Test.init (ref args);
    LocaleInfo.set_c ();
    Test.add_func ("/comments/model", test_model);
    Test.add_func ("/comments/undo", test_undo);
    Test.add_func ("/comments/xlsx", test_xlsx);
    Test.add_func ("/comments/ods", test_ods);
    Test.add_func ("/comments/parse", test_foreign_annotation);
    int r = Test.run ();
    if (failures > 0) {
        stderr.printf ("%d failures\n", failures);
        return 1;
    }
    return r;
}
