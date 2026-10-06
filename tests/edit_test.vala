using Singularity.Apps.Spreadsheet;

Singularity.Apps.Spreadsheet.Value vnum (double d) {
    return Singularity.Apps.Spreadsheet.Value.num (d);
}

Singularity.Apps.Spreadsheet.Value vstr (string t) {
    return Singularity.Apps.Spreadsheet.Value.str (t);
}

Singularity.Apps.Spreadsheet.Value vempty () {
    return Singularity.Apps.Spreadsheet.Value.empty ();
}

string tmp_path (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "ss-edit-%d-%s".printf (Random.int_range (0, 1000000), name));
}

void put (Sheet s, string addr, string input) {
    int r, c;
    bool a, b;
    Address.parse_cell (addr, out r, out c, out a, out b);
    s.set_input (r, c, input);
}

void expect_str (string what, string got, string want) {
    if (got != want) {
        stderr.printf ("FAIL %s: expected [%s] got [%s]\n", what, want, got);
        Test.fail ();
    }
}

void expect_true (string what, bool v) {
    if (!v) {
        stderr.printf ("FAIL %s\n", what);
        Test.fail ();
    }
}

void test_hashes () {
    expect_str ("legacy password", PasswordHash.legacy_hash ("password"), "83AF");
    expect_str ("legacy test", PasswordHash.legacy_hash ("test"), "CBEB");
    expect_str ("legacy secret", PasswordHash.legacy_hash ("secret"), "DAA7");
    var salt = new uint8[16];
    for (int i = 0; i < 16; i++) salt[i] = (uint8) i;
    expect_str ("sha512 spin", PasswordHash.iterated ("password", "SHA-512", salt, 100000), "x01qKaF9y9cQwPxHrE46zKhOLAHXLgmWjpZRPwqjkl6tpT1Lq9JXlHzPvHxsy/q0gWkWsUumW+mgF2sVqd4VXQ==");
    expect_str ("odf sha256", PasswordHash.odf_digest ("password", "sha256"), "XohImNooBHFR0OVvjcYpJ3NgPQ1qq73WKhHvch0VQtg=");
    var p = PasswordHash.create ("Secr3t!");
    expect_true ("verify ok", p.verify ("Secr3t!"));
    expect_true ("verify bad", !p.verify ("secr3t!"));
    var legacy = new PasswordHash ();
    legacy.legacy = "83AF";
    expect_true ("legacy verify", legacy.verify ("password"));
}

void test_protection () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "1");
    put (s, "B1", "2");
    var open_style = new CellStyle ();
    open_style.locked = false;
    s.set_style (0, 1, book.intern (open_style));
    expect_true ("no protection unlocked", !Protect.cell_locked (s, 0, 0));
    s.protection = new SheetProtection ();
    s.protection.password = PasswordHash.create ("pw");
    s.protection.format_cells = true;
    expect_true ("A1 locked", Protect.cell_locked (s, 0, 0));
    expect_true ("B1 unlocked", !Protect.cell_locked (s, 0, 1));
    expect_true ("format allowed", Protect.allowed (book, s, ProtectAction.FORMAT_CELLS));
    expect_true ("insert rows refused", !Protect.allowed (book, s, ProtectAction.INSERT_ROWS));
    s.protection.ranges.add (new EditRange ("Open", new Area (s, 5, 0, 6, 0)));
    expect_true ("edit range without password unlocked", !Protect.cell_locked (s, 5, 0));
    book.protection = new BookProtection ();
    book.protection.password = PasswordHash.create ("book");
    foreach (string ext in new string[] { "xlsx", "ods" }) {
        string path = tmp_path ("prot." + ext);
        var doc = new Document.with_book (book, null);
        try {
            doc.save_to (path, s);
            var back = Document.open (path).book;
            var bs = back.sheets[0];
            expect_true (ext + " sheet protected", bs.protection != null);
            if (bs.protection != null) {
                expect_true (ext + " password kept", bs.protection.password.verify ("pw") && !bs.protection.password.verify ("x"));
                expect_true (ext + " A1 locked", Protect.cell_locked (bs, 0, 0));
                expect_true (ext + " B1 unlocked", !Protect.cell_locked (bs, 0, 1));
                if (ext == "xlsx") {
                    expect_true ("xlsx format flag", bs.protection.format_cells);
                    expect_true ("xlsx range", bs.protection.ranges.size == 1);
                }
            }
            expect_true (ext + " book protected", back.protection != null && back.protection.structure);
            if (back.protection != null) expect_true (ext + " book password", back.protection.password.verify ("book"));
        } catch (Error e) {
            stderr.printf ("%s: %s\n", ext, e.message);
            Test.fail ();
        }
        FileUtils.remove (path);
    }
}

void test_validation () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    var v = new Validation (new Area (s, 0, 0, 9, 0));
    v.kind = ValidationKind.WHOLE;
    v.op = ValidationOp.BETWEEN;
    v.formula1 = "1";
    v.formula2 = "10";
    v.allow_blank = true;
    expect_true ("whole 5", ValidationCheck.valid (book, s, v, 0, 0, vnum (5)));
    expect_true ("whole 5.5", !ValidationCheck.valid (book, s, v, 0, 0, vnum (5.5)));
    expect_true ("whole 11", !ValidationCheck.valid (book, s, v, 0, 0, vnum (11)));
    expect_true ("blank ok", ValidationCheck.valid (book, s, v, 0, 0, vempty ()));
    expect_true ("text bad", !ValidationCheck.valid (book, s, v, 0, 0, vstr ("x")));
    v.kind = ValidationKind.DECIMAL;
    v.op = ValidationOp.GREATER;
    v.formula1 = "=B1*2";
    put (s, "B1", "3");
    put (s, "B2", "4");
    book.recalculate ();
    expect_true ("decimal > B1*2 row1", ValidationCheck.valid (book, s, v, 0, 0, vnum (6.5)));
    expect_true ("decimal relative row2", !ValidationCheck.valid (book, s, v, 1, 0, vnum (6.5)));
    v.kind = ValidationKind.TEXT_LENGTH;
    v.op = ValidationOp.LESS_EQUAL;
    v.formula1 = "3";
    expect_true ("len abc", ValidationCheck.valid (book, s, v, 0, 0, vstr ("abc")));
    expect_true ("len abcd", !ValidationCheck.valid (book, s, v, 0, 0, vstr ("abcd")));
    v.kind = ValidationKind.LIST;
    v.list_source = "\"Red,Green,Blue\"";
    expect_true ("list green", ValidationCheck.valid (book, s, v, 0, 0, vstr ("green")));
    expect_true ("list pink", !ValidationCheck.valid (book, s, v, 0, 0, vstr ("pink")));
    v.kind = ValidationKind.CUSTOM;
    v.formula1 = "ISEVEN(B1+1)";
    expect_true ("custom row1", ValidationCheck.valid (book, s, v, 0, 0, vnum (1)));
    expect_true ("custom row2", !ValidationCheck.valid (book, s, v, 1, 0, vnum (1)));
    v.kind = ValidationKind.DATE;
    v.op = ValidationOp.GREATER_EQUAL;
    v.formula1 = "DATE(2024,1,1)";
    expect_true ("date after", ValidationCheck.valid (book, s, v, 0, 0, ValidationCheck.candidate ("2024-03-05")));
    expect_true ("date before", !ValidationCheck.valid (book, s, v, 0, 0, ValidationCheck.candidate ("2023-03-05")));
    var w = new Validation (new Area (s, 0, 2, 4, 2));
    w.kind = ValidationKind.DECIMAL;
    w.op = ValidationOp.NOT_BETWEEN;
    w.formula1 = "0";
    w.formula2 = "1";
    w.input_title = "Ratio";
    w.message = "Outside 0..1";
    w.alert = ValidationAlert.WARNING;
    w.error_title = "Careful";
    w.error_message = "Unusual value";
    s.validations.add (w);
    put (s, "C1", "0.5");
    put (s, "C2", "5");
    book.recalculate ();
    var circles = ValidationCheck.invalid_cells (book, s);
    expect_true ("one invalid", circles.size == 1 && circles[0].r1 == 0 && circles[0].c1 == 2);
    foreach (string ext in new string[] { "xlsx", "ods" }) {
        string path = tmp_path ("val." + ext);
        try {
            new Document.with_book (book, null).save_to (path, s);
            var bs = Document.open (path).book.sheets[0];
            Validation? got = null;
            foreach (var x in bs.validations) if (x.area.c1 == 2) got = x;
            expect_true (ext + " validation back", got != null);
            if (got != null) {
                expect_true (ext + " kind", got.kind == ValidationKind.DECIMAL && got.op == ValidationOp.NOT_BETWEEN);
                expect_str (ext + " f2", got.formula2, "1");
                expect_str (ext + " title", got.input_title, "Ratio");
                expect_str (ext + " prompt", got.message, "Outside 0..1");
                expect_str (ext + " error", got.error_message, "Unusual value");
                expect_true (ext + " alert", got.alert == ValidationAlert.WARNING);
            }
        } catch (Error e) {
            stderr.printf ("%s: %s\n", ext, e.message);
            Test.fail ();
        }
        FileUtils.remove (path);
    }
}

void test_outline () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    for (int r = 0; r < 4; r++) put (s, "A%d".printf (r + 1), (r + 1).to_string ());
    put (s, "A5", "=SUM(A1:A4)");
    for (int r = 5; r < 7; r++) put (s, "A%d".printf (r + 1), "2");
    put (s, "A8", "=SUM(A6:A7)");
    put (s, "A9", "=SUM(A1:A8)");
    int n = AutoOutline.apply (s, true);
    expect_true ("auto groups", n == 3);
    expect_true ("level A1", s.outline.level_of (true, 0) == 2);
    expect_true ("level A5", s.outline.level_of (true, 4) == 1);
    expect_true ("level A9", s.outline.level_of (true, 8) == 0);
    var g = s.outline.group_for_summary (true, 4);
    expect_true ("group for A5", g != null && g.start == 0 && g.end == 3 && g.level == 2);
    s.outline.set_collapsed (s, true, g, true);
    expect_true ("collapsed hides", s.hidden_rows.contains (0) && s.hidden_rows.contains (3) && !s.hidden_rows.contains (4));
    s.outline.show_level (s, true, 1);
    expect_true ("level 1 hides all detail", s.hidden_rows.contains (4) && s.hidden_rows.contains (7) && !s.hidden_rows.contains (8));
    s.outline.show_level (s, true, 3);
    expect_true ("level 3 shows all", s.hidden_rows.size == 0);
    s.outline.group (false, 1, 2);
    s.outline.summary_right = false;
    s.outline.set_collapsed (s, true, s.outline.group_for_summary (true, 4), true);
    foreach (string ext in new string[] { "xlsx", "ods" }) {
        string path = tmp_path ("outline." + ext);
        try {
            new Document.with_book (book, null).save_to (path, s);
            var bs = Document.open (path).book.sheets[0];
            expect_true (ext + " row levels", bs.outline.level_of (true, 0) == 2 && bs.outline.level_of (true, 5) == 2 && bs.outline.level_of (true, 4) == 1 && bs.outline.level_of (true, 8) == 0);
            expect_true (ext + " col levels", bs.outline.level_of (false, 1) == 1 && bs.outline.level_of (false, 2) == 1 && bs.outline.level_of (false, 0) == 0);
            expect_true (ext + " collapsed", bs.outline.collapsed_rows.contains (4));
            expect_true (ext + " hidden kept", bs.hidden_rows.contains (1));
            if (ext == "xlsx") expect_true ("xlsx summary right", !bs.outline.summary_right);
        } catch (Error e) {
            stderr.printf ("%s: %s\n", ext, e.message);
            Test.fail ();
        }
        FileUtils.remove (path);
    }
}

void test_text_to_columns () {
    var o = new SplitOptions ();
    o.tab = false;
    o.comma = true;
    var p = TextToColumns.split ("a,\"b,c\",d", o);
    expect_true ("qualified", p.size == 3 && p[1] == "b,c");
    o.comma = false;
    o.space = true;
    o.consecutive = true;
    p = TextToColumns.split ("John   Smith  Jr", o);
    expect_true ("consecutive", p.size == 3 && p[2] == "Jr");
    o.consecutive = false;
    p = TextToColumns.split ("a  b", o);
    expect_true ("not consecutive", p.size == 3 && p[1] == "");
    var f = new SplitOptions ();
    f.fixed_width = true;
    f.breaks = { 3, 5 };
    p = TextToColumns.split ("ABCDEFGH", f);
    expect_true ("fixed", p.size == 3 && p[0] == "ABC" && p[1] == "DE" && p[2] == "FGH");
    expect_str ("date dmy", TextToColumns.convert ("05/03/2024", ColumnFormat.DATE_DMY), "2024-03-05");
    expect_str ("text keep", TextToColumns.convert ("007", ColumnFormat.TEXT), "'007");
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "x;1;2");
    put (s, "A2", "y;3;4");
    var doc = new Document.with_book (book, null);
    var so = new SplitOptions ();
    so.tab = false;
    so.semicolon = true;
    TextToColumns.apply (doc, s, new Area (s, 0, 0, 1, 0), so, 0, 0);
    expect_str ("t2c B2", s.value_at (1, 1).display (), "3");
    expect_str ("t2c C1", s.value_at (0, 2).display (), "2");
    expect_str ("t2c A2", s.value_at (1, 0).display (), "y");
}

string learn_apply (string[] ins, string[] outs, string[] target) {
    var li = new Gee.ArrayList<FillRow> ();
    var lo = new Gee.ArrayList<string> ();
    for (int i = 0; i < outs.length; i++) {
        li.add (new FillRow ({ ins[i] }));
        lo.add (outs[i]);
    }
    var prog = FlashFill.learn (li, lo);
    if (prog == null) return "<none>";
    return FlashFill.apply (prog, target) ?? "<fail>";
}

void test_flash_fill () {
    expect_str ("first name", learn_apply ({ "John Smith" }, { "John" }, { "Mary Jones" }), "Mary");
    expect_str ("last name", learn_apply ({ "John Smith", "Anna Lee Brown" }, { "Smith", "Brown" }, { "Mary Ann Jones" }), "Jones");
    expect_str ("initials", learn_apply ({ "john smith", "ada lovelace" }, { "J.S.", "A.L." }, { "grace hopper" }), "G.H.");
    expect_str ("swap", learn_apply ({ "Smith, John", "Lee, Anna" }, { "John Smith", "Anna Lee" }, { "Jones, Mary" }), "Mary Jones");
    expect_str ("upper", learn_apply ({ "abc-12", "xyz-7" }, { "ABC", "XYZ" }, { "qrs-99" }), "QRS");
    expect_str ("digits", learn_apply ({ "Order 1234 shipped", "Order 77 shipped" }, { "1234", "77" }, { "Order 505 shipped" }), "505");
    expect_str ("date reorder", learn_apply ({ "2024-03-05", "1999-12-31" }, { "05/03/2024", "31/12/1999" }, { "2010-07-04" }), "04/07/2010");
    expect_str ("email user", learn_apply ({ "ann@example.com", "bob.k@test.org" }, { "ann", "bob.k" }, { "carl@mail.net" }), "carl");
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "Full Name");
    put (s, "B1", "First");
    put (s, "A2", "Ada Lovelace");
    put (s, "B2", "Ada");
    put (s, "A3", "Alan Turing");
    put (s, "A4", "Grace Hopper");
    var doc = new Document.with_book (book, null);
    int n = FlashFill.fill (doc, s, 2, 1);
    expect_true ("filled two", n == 2);
    expect_str ("B3", s.value_at (2, 1).display (), "Alan");
    expect_str ("B4", s.value_at (3, 1).display (), "Grace");
}

void test_autocomplete () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "Apple");
    put (s, "A2", "Banana");
    put (s, "A3", "Apricot");
    expect_str ("unique Ban", AutoComplete.complete (s, 3, 0, "ban") ?? "", "Banana");
    expect_true ("ambiguous Ap", AutoComplete.complete (s, 3, 0, "Ap") == null);
    expect_str ("Apr", AutoComplete.complete (s, 3, 0, "Apr") ?? "", "Apricot");
    expect_true ("numbers ignored", AutoComplete.complete (s, 3, 0, "12") == null);
}

void test_goto_and_paste () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "1");
    put (s, "A2", "=A1*2");
    put (s, "A3", "=1/0");
    put (s, "B1", "text");
    book.recalculate ();
    var doc = new Document.with_book (book, null);
    var f = GoToSpecial.find (doc, s, new Area.cell (s, 0, 0), SpecialKind.FORMULAS, 0, 0);
    expect_true ("formulas", f.size == 1 && f[0].r1 == 1 && f[0].r2 == 2);
    var e = GoToSpecial.find (doc, s, new Area.cell (s, 0, 0), SpecialKind.ERRORS, 0, 0);
    expect_true ("errors", e.size == 1 && e[0].r1 == 2);
    var b = GoToSpecial.find (doc, s, new Area.cell (s, 0, 0), SpecialKind.BLANKS, 0, 0);
    expect_true ("blanks", b.size == 1 && b[0].c1 == 1 && b[0].r1 == 1 && b[0].r2 == 2);
    put (s, "D1", "10");
    put (s, "D2", "20");
    put (s, "E1", "1");
    doc.copy (s, new Area.cell (s, 0, 4), false);
    EditCommands.paste_special (doc, s, 0, 3, true, false, PasteOp.ADD, false, false, false, false);
    expect_str ("add", s.value_at (0, 3).display (), "11");
    doc.copy (s, new Area (s, 0, 3, 1, 3), false);
    EditCommands.paste_special (doc, s, 0, 6, true, false, PasteOp.NONE, false, true, false, false);
    expect_str ("transpose H1", s.value_at (0, 7).display (), "20");
    EditCommands.paste_special (doc, s, 5, 0, false, false, PasteOp.NONE, false, false, true, false);
    book.recalculate ();
    expect_str ("link", s.input_at (5, 0), "=$D$1");
    doc.undo ();
    expect_str ("undo link", s.input_at (5, 0), "");
}

void test_style_io () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "rotated");
    put (s, "A2", "vertical");
    put (s, "A3", "shrunk");
    var st = new CellStyle ();
    st.rotation = 45;
    s.set_style (0, 0, book.intern (st));
    var st2 = new CellStyle ();
    st2.rotation = 255;
    st2.hidden = true;
    s.set_style (1, 0, book.intern (st2));
    var st3 = new CellStyle ();
    st3.shrink = true;
    st3.locked = false;
    st3.rotation = -30;
    s.set_style (2, 0, book.intern (st3));
    foreach (string ext in new string[] { "xlsx", "ods" }) {
        string path = tmp_path ("style." + ext);
        try {
            new Document.with_book (book, null).save_to (path, s);
            var bs = Document.open (path).book.sheets[0];
            expect_true (ext + " rot 45", bs.style_at (0, 0).rotation == 45);
            expect_true (ext + " vertical", bs.style_at (1, 0).rotation == 255 && bs.style_at (1, 0).hidden);
            expect_true (ext + " shrink", bs.style_at (2, 0).shrink && !bs.style_at (2, 0).locked && bs.style_at (2, 0).rotation == -30);
            expect_true (ext + " default locked", bs.style_at (5, 5).locked);
        } catch (Error e) {
            stderr.printf ("%s: %s\n", ext, e.message);
            Test.fail ();
        }
        FileUtils.remove (path);
    }
}

void test_styles_theme_views () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "x");
    var doc = new Document.with_book (book, null);
    NamedStyle? good = null;
    foreach (var ns in NamedStyle.gallery (book.theme)) if (ns.name == "Good") good = ns;
    expect_true ("gallery has Good", good != null);
    EditCommands.apply_named_style (doc, s, new Area.cell (s, 0, 0), good);
    expect_str ("good fill", s.style_at (0, 0).fill, "#c6efce");
    var accent = NamedStyle.gallery (book.theme);
    NamedStyle? a1 = null;
    foreach (var ns in accent) if (ns.name == "Accent1") a1 = ns;
    EditCommands.apply_named_style (doc, s, new Area.cell (s, 1, 0), a1);
    expect_str ("accent1 office", s.style_at (1, 0).fill, "#4472c4");
    DocTheme? slate = null;
    foreach (var t in DocTheme.builtin ()) if (t.name == "Slate") slate = t;
    EditCommands.set_theme (doc, slate);
    expect_str ("theme remaps accent", s.style_at (1, 0).fill, "#4e67c8");
    doc.undo ();
    expect_str ("undo theme", book.theme.name, "Office");
    s.hidden_rows.add (3);
    var v = CustomView.capture (s, "Hide4", 1.5, 0, 0);
    EditCommands.save_view (doc, s, v);
    s.hidden_rows.clear ();
    EditCommands.show_view (doc, s, s.views[0]);
    expect_true ("view restores hidden", s.hidden_rows.contains (3));
}

void test_encryption () {
    var key = new uint8[32];
    for (int i = 0; i < 32; i++) key[i] = (uint8) i;
    var block = new uint8[16];
    for (int i = 0; i < 16; i++) block[i] = (uint8) (i * 0x11);
    new Aes (key).encrypt_block (block);
    var sb = new StringBuilder ();
    foreach (var b in block) sb.append ("%02x".printf (b));
    expect_str ("fips197 aes256", sb.str, "8ea2b7ca516745bfeafc49904b496089");
    var book = new Workbook ();
    var s = book.add_sheet ("Secret");
    put (s, "A1", "classified");
    put (s, "B2", "=6*7");
    for (int r = 3; r < 400; r++) put (s, "A%d".printf (r), "row %d with some padding text".printf (r));
    book.recalculate ();
    string path = tmp_path ("enc.xlsx");
    try {
        var doc = new Document.with_book (book, null);
        doc.encrypt_password = "Pässword1";
        doc.save_to (path, s);
        uint8[] raw;
        FileUtils.get_data (path, out raw);
        expect_true ("cfb container", Cfb.sniff (raw) && OfficeCrypto.is_encrypted (raw));
        var cfb = new Cfb (raw);
        expect_true ("dataspaces", cfb.streams.has_key ("\x06Primary") && cfb.streams.has_key ("DataSpaceMap") && cfb.streams.has_key ("Version"));
        bool required = false;
        try {
            Document.open (path);
        } catch (Error e) {
            required = e is CryptoError.PASSWORD_REQUIRED;
        }
        expect_true ("password required", required);
        bool wrong = false;
        try {
            Document.open_with_password (path, "nope");
        } catch (Error e) {
            wrong = e is CryptoError.WRONG_PASSWORD;
        }
        expect_true ("wrong password", wrong);
        var back = Document.open_with_password (path, "Pässword1");
        expect_str ("decrypted A1", back.book.sheets[0].value_at (0, 0).display (), "classified");
        expect_str ("decrypted B2", back.book.sheets[0].value_at (1, 1).display (), "42");
        expect_str ("decrypted A399", back.book.sheets[0].value_at (398, 0).display (), "row 399 with some padding text");
    } catch (Error e) {
        stderr.printf ("enc: %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

void test_views_and_named_styles_io () {
    var book = new Workbook ();
    var s = book.add_sheet ("Data");
    for (int r = 0; r < 10; r++) put (s, "A%d".printf (r + 1), (r * 3).to_string ());
    var doc = new Document.with_book (book, null);
    NamedStyle? good = null;
    NamedStyle? h1 = null;
    foreach (var ns in NamedStyle.gallery (book.theme)) {
        if (ns.name == "Good") good = ns;
        if (ns.name == "Heading 1") h1 = ns;
    }
    EditCommands.apply_named_style (doc, s, new Area (s, 0, 0, 1, 0), good);
    EditCommands.apply_named_style (doc, s, new Area.cell (s, 2, 0), h1);
    s.hidden_rows.add (4);
    s.hidden_rows.add (5);
    s.hidden_cols.add (3);
    s.freeze_rows = 1;
    s.filter = new Filter (new Area (s, 0, 0, 9, 0));
    s.page.row_breaks.add (7);
    EditCommands.save_view (doc, s, CustomView.capture (s, "Summary View", 1.25, 2, 1));
    s.hidden_rows.clear ();
    s.hidden_cols.clear ();
    s.page.row_breaks.clear ();
    s.freeze_rows = 0;
    s.filter = null;
    EditCommands.save_view (doc, s, CustomView.capture (s, "Everything", 1.0, 0, 0));
    foreach (string ext in new string[] { "xlsx", "ods" }) {
        string path = tmp_path ("views." + ext);
        try {
            new Document.with_book (book, null).save_to (path, s);
            var bs = Document.open (path).book.sheets[0];
            expect_str (ext + " style A1", bs.style_at (0, 0).style_name, "Good");
            expect_str (ext + " style A3", bs.style_at (2, 0).style_name, "Heading 1");
            expect_str (ext + " unstyled", bs.style_at (5, 0).style_name, "");
            expect_str (ext + " good fill kept", bs.style_at (1, 0).fill, "#c6efce");
            expect_true (ext + " two views", bs.views.size == 2);
            CustomView? v = null;
            foreach (var x in bs.views) if (x.name == "Summary View") v = x;
            expect_true (ext + " view found", v != null);
            if (v != null) {
                expect_true (ext + " view hidden rows", v.hidden_rows.contains (4) && v.hidden_rows.contains (5) && v.hidden_rows.size == 2);
                expect_true (ext + " view hidden cols", v.hidden_cols.contains (3));
                expect_true (ext + " view zoom", Math.fabs (v.zoom - 1.25) < 0.001);
                expect_true (ext + " view freeze", v.freeze_rows == 1 && v.freeze_cols == 0);
                expect_true (ext + " view selection", v.row == 2 && v.col == 1);
                expect_true (ext + " view filter", v.filter != null && v.filter.area.r2 == 9);
                expect_true (ext + " view breaks", v.row_breaks.contains (7));
                v.apply (bs);
                expect_true (ext + " apply", bs.hidden_rows.contains (5) && bs.freeze_rows == 1 && bs.page.row_breaks.contains (7));
            }
        } catch (Error e) {
            stderr.printf ("%s: %s\n", ext, e.message);
            Test.fail ();
        }
        FileUtils.remove (path);
    }
    string path = tmp_path ("styles.xlsx");
    try {
        new Document.with_book (book, null).save_to (path, s);
        uint8[] raw;
        FileUtils.get_data (path, out raw);
        var zr = new ZipReader (raw);
        string styles = zr.read_text ("xl/styles.xml");
        expect_true ("cellStyles Good builtin", styles.contains ("<cellStyle name=\"Good\" xfId=\"1\" builtinId=\"26\"/>") || styles.contains ("name=\"Good\""));
        expect_true ("cellStyleXfs count", styles.contains ("<cellStyleXfs count=\"3\">"));
        string sheet = zr.read_text ("xl/worksheets/sheet1.xml");
        expect_true ("customSheetViews", sheet.contains ("<customSheetViews>") && sheet.contains ("scale=\"125\""));
        string wb = zr.read_text ("xl/workbook.xml");
        expect_true ("customWorkbookViews", wb.contains ("<customWorkbookView name=\"Summary View\""));
    } catch (Error e) {
        stderr.printf ("zip: %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (path);
}

string col_text (Sheet s, int c, int r1, int r2) {
    string[] parts = {};
    for (int r = r1; r <= r2; r++) parts += s.value_at (r, c).display ();
    return string.joinv (",", parts);
}

void test_sort_advanced () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    string[] months = { "Mar", "Jan", "Dec", "Feb", "jan" };
    string[] vals = { "b", "B", "a", "A", "c" };
    put (s, "A1", "Month");
    put (s, "B1", "Val");
    for (int i = 0; i < months.length; i++) {
        put (s, "A%d".printf (i + 2), months[i]);
        put (s, "B%d".printf (i + 2), vals[i]);
    }
    var doc = new Document.with_book (book, null);
    var spec = new SortSpec (new Area (s, 0, 0, 5, 1));
    var lv = new SortLevel (0, true);
    lv.custom_list = CustomLists.builtin ()[2];
    spec.levels.add (lv);
    SortEngine.sort (doc, s, spec);
    expect_str ("custom list order", col_text (s, 0, 1, 5), "Jan,jan,Feb,Mar,Dec");
    var spec2 = new SortSpec (new Area (s, 0, 0, 5, 1));
    spec2.case_sensitive = true;
    spec2.levels.add (new SortLevel (1, true));
    SortEngine.sort (doc, s, spec2);
    expect_str ("case sensitive", col_text (s, 1, 1, 5), "a,A,b,B,c");
    var red = new CellStyle ();
    red.fill = "#ff0000";
    int ri = book.intern (red);
    s.set_style (4, 1, ri);
    var spec3 = new SortSpec (new Area (s, 0, 0, 5, 1));
    var cl = new SortLevel (1, true);
    cl.by = SortBy.CELL_COLOR;
    cl.color = "#ff0000";
    spec3.levels.add (cl);
    SortEngine.sort (doc, s, spec3);
    expect_str ("color on top", s.value_at (1, 1).display (), "B");
    var t = book.add_sheet ("T");
    put (t, "A1", "3");
    put (t, "B1", "1");
    put (t, "C1", "2");
    put (t, "A2", "c");
    put (t, "B2", "a");
    put (t, "C2", "b");
    var spec4 = new SortSpec (new Area (t, 0, 0, 1, 2));
    spec4.header = false;
    spec4.columns = true;
    spec4.levels.add (new SortLevel (0, true));
    SortEngine.sort (doc, t, spec4);
    expect_str ("left to right", t.value_at (1, 0).display () + t.value_at (1, 1).display () + t.value_at (1, 2).display (), "abc");
    var many = new SortSpec (new Area (s, 0, 0, 5, 1));
    for (int i = 0; i < 64; i++) many.levels.add (new SortLevel (i % 2, true));
    SortEngine.sort (doc, s, many);
    expect_true ("64 levels", s.sort_state != null && s.sort_state.levels.size == 64);
    s.sort_state = spec.copy ();
    foreach (string ext in new string[] { "xlsx", "ods" }) {
        string path = tmp_path ("sort." + ext);
        try {
            new Document.with_book (book, null).save_to (path, s);
            var bs = Document.open (path).book.sheets[0];
            if (ext == "ods") {
                s.filter = null;
            }
            expect_true (ext + " sort state", bs.sort_state != null && bs.sort_state.levels.size == 1 && bs.sort_state.levels[0].custom_list.has_prefix ("Jan|Feb"));
        } catch (Error e) {
            stderr.printf ("%s: %s\n", ext, e.message);
            Test.fail ();
        }
        FileUtils.remove (path);
    }
}

void test_filters () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "Name");
    put (s, "B1", "Score");
    put (s, "C1", "Date");
    string[] names = { "Alpha", "Beta", "Gamma", "Alpine", "Delta", "Omega" };
    int[] scores = { 10, 50, 30, 90, 70, 20 };
    string[] dates = { "2023-12-31", "2024-01-15", "2024-02-10", "2024-02-20", "2024-03-01", "2025-06-01" };
    for (int i = 0; i < names.length; i++) {
        put (s, "A%d".printf (i + 2), names[i]);
        put (s, "B%d".printf (i + 2), scores[i].to_string ());
        put (s, "C%d".printf (i + 2), dates[i]);
    }
    book.recalculate ();
    var doc = new Document.with_book (book, null);
    doc.toggle_filter (s, new Area (s, 0, 0, 6, 2));
    var r = new FilterRule ();
    r.kind = FilterKind.CUSTOM;
    r.op1 = "begins";
    r.v1 = "Al";
    EditCommands.set_filter_rule (doc, s, 0, r);
    expect_true ("begins with", !s.hidden_rows.contains (1) && s.hidden_rows.contains (2) && !s.hidden_rows.contains (4));
    r.op1 = "contains";
    r.v1 = "eg";
    r.op2 = "ends";
    r.v2 = "ta";
    r.and_join = false;
    EditCommands.set_filter_rule (doc, s, 0, r);
    expect_true ("or contains/ends", !s.hidden_rows.contains (2) && !s.hidden_rows.contains (6) && !s.hidden_rows.contains (5) && s.hidden_rows.contains (1));
    r.op1 = "equal";
    r.v1 = "?amma";
    r.op2 = "";
    EditCommands.set_filter_rule (doc, s, 0, r);
    expect_true ("wildcard", !s.hidden_rows.contains (3) && s.hidden_rows.contains (1));
    EditCommands.set_filter_rule (doc, s, 0, null);
    var top = new FilterRule ();
    top.kind = FilterKind.TOP10;
    top.top = 2;
    EditCommands.set_filter_rule (doc, s, 1, top);
    expect_true ("top 2", !s.hidden_rows.contains (4) && !s.hidden_rows.contains (5) && s.hidden_rows.contains (2));
    top.percent = true;
    top.bottom = true;
    top.top = 50;
    EditCommands.set_filter_rule (doc, s, 1, top);
    expect_true ("bottom 50%", !s.hidden_rows.contains (1) && !s.hidden_rows.contains (6) && !s.hidden_rows.contains (3) && s.hidden_rows.contains (4));
    var avg = new FilterRule ();
    avg.kind = FilterKind.DYNAMIC;
    avg.dyn_type = "aboveAverage";
    EditCommands.set_filter_rule (doc, s, 1, avg);
    expect_true ("above average", !s.hidden_rows.contains (4) && !s.hidden_rows.contains (5) && s.hidden_rows.contains (1));
    EditCommands.set_filter_rule (doc, s, 1, null);
    var q1 = new FilterRule ();
    q1.kind = FilterKind.DYNAMIC;
    q1.dyn_type = "Q1";
    EditCommands.set_filter_rule (doc, s, 2, q1);
    expect_true ("Q1", !s.hidden_rows.contains (2) && s.hidden_rows.contains (1) && s.hidden_rows.contains (6));
    var tree = new FilterRule ();
    tree.dates.add ("2024-02");
    tree.dates.add ("2025");
    EditCommands.set_filter_rule (doc, s, 2, tree);
    expect_true ("date tree", !s.hidden_rows.contains (3) && !s.hidden_rows.contains (4) && !s.hidden_rows.contains (6) && s.hidden_rows.contains (2));
    double from, to;
    expect_true ("today range", FilterEngine.dynamic_range ("today", out from, out to) && to - from == 1);
    expect_true ("this week spans 7", FilterEngine.dynamic_range ("thisWeek", out from, out to) && to - from == 7);
    var red = new CellStyle ();
    red.fill = "#ff0000";
    s.set_style (3, 1, book.intern (red));
    var col = new FilterRule ();
    col.kind = FilterKind.CELL_COLOR;
    col.color = "#ff0000";
    EditCommands.set_filter_rule (doc, s, 2, null);
    EditCommands.set_filter_rule (doc, s, 1, col);
    expect_true ("cell color", !s.hidden_rows.contains (3) && s.hidden_rows.contains (1));
    var cust = new FilterRule ();
    cust.kind = FilterKind.CUSTOM;
    cust.op1 = "greaterequal";
    cust.v1 = "30";
    cust.op2 = "lessequal";
    cust.v2 = "70";
    var vis = new FilterRule ();
    vis.dates.add ("2024");
    foreach (string ext in new string[] { "xlsx", "ods" }) {
        EditCommands.set_filter_rule (doc, s, 1, cust);
        EditCommands.set_filter_rule (doc, s, 2, ext == "xlsx" ? vis : null);
        EditCommands.set_filter_rule (doc, s, 0, ext == "xlsx" ? col : null);
        string path = tmp_path ("filter." + ext);
        try {
            new Document.with_book (book, null).save_to (path, s);
            var bs = Document.open (path).book.sheets[0];
            expect_true (ext + " filter", bs.filter != null);
            if (bs.filter != null) {
                var got = bs.filter.rules.has_key (1) ? bs.filter.rules[1] : null;
                expect_true (ext + " custom rule", got != null && got.kind == FilterKind.CUSTOM && got.op1 == "greaterequal" && got.v1 == "30" && got.op2 == "lessequal" && got.and_join);
                if (ext == "xlsx") {
                    var d = bs.filter.rules.has_key (2) ? bs.filter.rules[2] : null;
                    expect_true ("xlsx date group", d != null && d.dates.contains ("2024"));
                    var c = bs.filter.rules.has_key (0) ? bs.filter.rules[0] : null;
                    expect_true ("xlsx color filter", c != null && c.kind == FilterKind.CELL_COLOR && c.color == "#ff0000");
                }
            }
        } catch (Error e) {
            stderr.printf ("%s: %s\n", ext, e.message);
            Test.fail ();
        }
        FileUtils.remove (path);
    }
    var tops = new FilterRule ();
    tops.kind = FilterKind.TOP10;
    tops.top = 3;
    tops.percent = true;
    var dyn = new FilterRule ();
    dyn.kind = FilterKind.DYNAMIC;
    dyn.dyn_type = "thisMonth";
    EditCommands.set_filter_rule (doc, s, 0, null);
    EditCommands.set_filter_rule (doc, s, 1, tops);
    EditCommands.set_filter_rule (doc, s, 2, dyn);
    string path = tmp_path ("filter2.xlsx");
    try {
        new Document.with_book (book, null).save_to (path, s);
        var bs = Document.open (path).book.sheets[0];
        expect_true ("xlsx top10", bs.filter.rules.has_key (1) && bs.filter.rules[1].kind == FilterKind.TOP10 && bs.filter.rules[1].percent && bs.filter.rules[1].top == 3);
        expect_true ("xlsx dynamic", bs.filter.rules.has_key (2) && bs.filter.rules[2].dyn_type == "thisMonth");
    } catch (Error e) {
        Test.fail ();
    }
    FileUtils.remove (path);
    var tree2 = new FilterRule ();
    tree2.dates.add ("2024-02");
    tree2.dates.add ("2025");
    var fontc = new FilterRule ();
    fontc.kind = FilterKind.FONT_COLOR;
    fontc.color = "#006100";
    var cellc = new FilterRule ();
    cellc.kind = FilterKind.CELL_COLOR;
    cellc.color = "#ff0000";
    EditCommands.set_filter_rule (doc, s, 2, tree2);
    EditCommands.set_filter_rule (doc, s, 1, cellc);
    EditCommands.set_filter_rule (doc, s, 0, fontc);
    string opath = tmp_path ("filter3.ods");
    try {
        new Document.with_book (book, null).save_to (opath, s);
        uint8[] raw;
        FileUtils.get_data (opath, out raw);
        string content = new ZipReader (raw).read_text ("content.xml");
        expect_true ("ods standard range", content.contains ("table:operator=\"&gt;=\"") && content.contains ("table:filter-or"));
        expect_true ("ods loext color", content.contains ("loext:data-type=\"background-color\"") && content.contains ("loext:data-type=\"text-color\""));
        EditOds.ignore_own_rules = true;
        var bs = Document.open (opath).book.sheets[0];
        EditOds.ignore_own_rules = false;
        var d = bs.filter.rules.has_key (2) ? bs.filter.rules[2] : null;
        expect_true ("ods std dates", d != null && d.dates.contains ("2024-02") && d.dates.contains ("2025") && d.dates.size == 2);
        var cc = bs.filter.rules.has_key (1) ? bs.filter.rules[1] : null;
        expect_true ("ods std cell color", cc != null && cc.kind == FilterKind.CELL_COLOR && cc.color == "#ff0000");
        var fc = bs.filter.rules.has_key (0) ? bs.filter.rules[0] : null;
        expect_true ("ods std font color", fc != null && fc.kind == FilterKind.FONT_COLOR && fc.color == "#006100");
        var tm = new FilterRule ();
        tm.kind = FilterKind.DYNAMIC;
        tm.dyn_type = "thisMonth";
        EditCommands.set_filter_rule (doc, s, 2, tm);
        EditCommands.set_filter_rule (doc, s, 1, null);
        EditCommands.set_filter_rule (doc, s, 0, null);
        new Document.with_book (book, null).save_to (opath, s);
        EditOds.ignore_own_rules = true;
        var bs2 = Document.open (opath).book.sheets[0];
        EditOds.ignore_own_rules = false;
        var now = new DateTime.now_local ();
        var tmr = bs2.filter.rules.has_key (2) ? bs2.filter.rules[2] : null;
        expect_true ("ods this month as range", tmr != null && tmr.dates.contains ("%04d-%02d".printf (now.get_year (), now.get_month ())));
        var bs3 = Document.open (opath).book.sheets[0];
        expect_true ("ods own dynamic kept", bs3.filter.rules.has_key (2) && bs3.filter.rules[2].dyn_type == "thisMonth");
    } catch (Error e) {
        stderr.printf ("ods3: %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (opath);
    EditCommands.clear_filters (doc, s);
    expect_true ("clear", s.hidden_rows.size == 0 && s.filter.rules.size == 0);
}

void test_series_and_lists () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    var doc = new Document.with_book (book, null);
    put (s, "A1", "2");
    SeriesFill.fill (doc, s, new Area (s, 0, 0, 5, 0), false, SeriesType.GROWTH, DateUnit.DAY, 3, null, false);
    expect_str ("growth", col_text (s, 0, 0, 3), "2,6,18,54");
    put (s, "B1", "1");
    SeriesFill.fill (doc, s, new Area (s, 0, 1, 9, 1), false, SeriesType.LINEAR, DateUnit.DAY, 2.5, 8, false);
    expect_str ("linear stop", col_text (s, 1, 0, 4), "1,3.5,6,,");
    put (s, "C1", "2024-01-31");
    SeriesFill.fill (doc, s, new Area (s, 0, 2, 2, 2), false, SeriesType.DATE, DateUnit.MONTH, 1, null, false);
    int y, m, d;
    DateSerial.to_ymd (s.value_at (1, 2).number, out y, out m, out d);
    expect_true ("month end clamp", y == 2024 && m == 2 && d == 29);
    put (s, "D1", "2024-03-01");
    SeriesFill.fill (doc, s, new Area (s, 0, 3, 1, 3), false, SeriesType.DATE, DateUnit.WEEKDAY, 1, null, false);
    DateSerial.to_ymd (s.value_at (1, 3).number, out y, out m, out d);
    expect_true ("weekday skips weekend", m == 3 && d == 4);
    put (s, "E1", "1");
    put (s, "E2", "3");
    put (s, "E3", "4");
    SeriesFill.fill (doc, s, new Area (s, 0, 4, 4, 4), false, SeriesType.LINEAR, DateUnit.DAY, 1, null, true);
    expect_true ("trend", Math.fabs (s.value_at (4, 4).number - 43.0 / 6.0) < 1e-9 && Math.fabs (s.value_at (0, 4).number - 7.0 / 6.0) < 1e-9);
    CustomLists.set_user_text ("Low, Medium, High; Bronze,Silver,Gold");
    expect_true ("user lists parsed", CustomLists.user ().size == 2 && CustomLists.user ()[1] == "Bronze|Silver|Gold");
    expect_str ("user lists text", CustomLists.user_text (), "Low, Medium, High; Bronze, Silver, Gold");
    put (s, "G1", "Silver");
    doc.fill_series (s, new Area.cell (s, 0, 6), new Area (s, 0, 6, 2, 6));
    expect_str ("user list fill", col_text (s, 6, 0, 2), "Silver,Gold,Bronze");
    expect_true ("all merges", CustomLists.all (book).size == 6);
    CustomLists.set_user_text ("");
    book.custom_lists.add ("North|East|South|West");
    put (s, "F1", "East");
    doc.fill_series (s, new Area.cell (s, 0, 5), new Area (s, 0, 5, 3, 5));
    expect_str ("custom list fill", col_text (s, 5, 0, 3), "East,South,West,North");
    foreach (string ext in new string[] { "xlsx", "ods" }) {
        string path = tmp_path ("lists." + ext);
        try {
            new Document.with_book (book, null).save_to (path, s);
            var bb = Document.open (path).book;
            expect_true (ext + " lists", bb.custom_lists.size == 1 && bb.custom_lists[0] == "North|East|South|West" && !bb.names.has_key ("_ssCustomLists"));
        } catch (Error e) {
            Test.fail ();
        }
        FileUtils.remove (path);
    }
}

int main (string[] args) {
    Test.init (ref args);
    LocaleInfo.set_c ();
    Test.add_func ("/edit/hashes", test_hashes);
    Test.add_func ("/edit/protection", test_protection);
    Test.add_func ("/edit/validation", test_validation);
    Test.add_func ("/edit/outline", test_outline);
    Test.add_func ("/edit/text-to-columns", test_text_to_columns);
    Test.add_func ("/edit/flash-fill", test_flash_fill);
    Test.add_func ("/edit/autocomplete", test_autocomplete);
    Test.add_func ("/edit/goto-paste", test_goto_and_paste);
    Test.add_func ("/edit/style-io", test_style_io);
    Test.add_func ("/edit/styles-theme-views", test_styles_theme_views);
    Test.add_func ("/edit/encryption", test_encryption);
    Test.add_func ("/edit/views-named-styles", test_views_and_named_styles_io);
    Test.add_func ("/edit/sort-advanced", test_sort_advanced);
    Test.add_func ("/edit/filters", test_filters);
    Test.add_func ("/edit/series-lists", test_series_and_lists);
    return Test.run ();
}
