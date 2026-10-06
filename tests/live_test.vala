using Singularity.Apps.Spreadsheet;

int failures = 0;

void check (bool ok, string what) {
    if (!ok) {
        stderr.printf ("FAIL %s\n", what);
        failures++;
    }
}

class Pair {
    public Document a;
    public Document b;
    public LiveSheetSync sa;
    public LiveSheetSync sb;
    public Gee.ArrayList<Json.Object> to_a = new Gee.ArrayList<Json.Object> ();
    public Gee.ArrayList<Json.Object> to_b = new Gee.ArrayList<Json.Object> ();
    public bool hold;

    public Pair () {
        a = new Document ();
        sa = new LiveSheetSync (a, "pa");
        try {
            var state = sa.snapshot ();
            int64 clock;
            int sv;
            var book = LiveSheetSync.book_from (state, out clock, out sv);
            b = new Document.with_book (book, null);
            sb = new LiveSheetSync (b, "pb");
            sb.clock = clock;
            sb.base_sv = sv;
        } catch (Error e) {
            check (false, "snapshot " + e.message);
        }
        sa.outgoing.connect ((m) => {
            m.set_string_member ("peer", "pa");
            to_b.add (m);
            if (!hold) flush ();
        });
        sb.outgoing.connect ((m) => {
            m.set_string_member ("peer", "pb");
            to_a.add (m);
            if (!hold) flush ();
        });
    }

    public void flush () {
        while (to_a.size > 0 || to_b.size > 0) {
            if (to_b.size > 0) sb.receive (to_b.remove_at (0));
            if (to_a.size > 0) sa.receive (to_a.remove_at (0));
        }
    }
}

string dump (Workbook book) {
    var sb = new StringBuilder ();
    foreach (var s in book.sheets) {
        sb.append ("[" + s.name + "]");
        var keys = new Gee.TreeSet<int64?> ((x, y) => {
            int64 p = x;
            int64 q = y;
            return p < q ? -1 : (p > q ? 1 : 0);
        });
        foreach (var k in s.cells.keys) keys.add (k);
        foreach (var k in keys) {
            var c = s.cells[k];
            if (c.input == "" && c.style == 0) continue;
            sb.append ("%d,%d=%s/%s;".printf (c.row, c.col, c.input, book.styles[c.style].bold ? "b" : ""));
        }
    }
    return sb.str;
}

void converge (Pair p, string what) {
    string x = dump (p.a.book), y = dump (p.b.book);
    if (x != y) {
        stderr.printf ("  A: %s\n  B: %s\n", x, y);
        check (false, what + " converge");
    }
}

void test_basic () {
    var p = new Pair ();
    var sa = p.a.book.sheets[0];
    var sb = p.b.book.sheets[0];
    p.a.set_input (sa, 2, 2, "42");
    check (sb.input_at (2, 2) == "42", "value propagates");
    p.b.set_input (sb, 3, 0, "=C3*2");
    check (sa.value_at (3, 0).display () == "84", "formula propagates and computes");
    p.a.edit_style (sa, new Area.cell (sa, 2, 2), "Bold", (st) => st.bold = true);
    check (sb.style_at (2, 2).bold, "formatting propagates");
    p.a.set_input (sa, 2, 2, "");
    check (sb.input_at (2, 2) == "", "clear propagates");
    converge (p, "basic");
}

void test_lww () {
    var p = new Pair ();
    var sa = p.a.book.sheets[0];
    var sb = p.b.book.sheets[0];
    p.hold = true;
    p.a.set_input (sa, 0, 0, "from A");
    p.b.set_input (sb, 0, 0, "from B");
    p.b.set_input (sb, 0, 0, "from B again");
    p.hold = false;
    p.flush ();
    check (sa.input_at (0, 0) == sb.input_at (0, 0), "concurrent edit converges");
    check (sa.input_at (0, 0) == "from B again", "higher clock wins, got " + sa.input_at (0, 0));
    p.hold = true;
    p.a.set_input (sa, 1, 1, "A1");
    p.b.set_input (sb, 1, 1, "B1");
    p.hold = false;
    p.flush ();
    check (sa.input_at (1, 1) == "B1", "equal clocks: higher peer id wins");
    converge (p, "lww");
}

void test_structure () {
    var p = new Pair ();
    var sa = p.a.book.sheets[0];
    var sb = p.b.book.sheets[0];
    p.a.set_input (sa, 4, 1, "keep");
    p.hold = true;
    p.a.insert_rows (sa, 1, 2);
    p.b.set_input (sb, 4, 1, "edited by B");
    p.b.set_input (sb, 8, 3, "far");
    p.hold = false;
    p.flush ();
    check (sa.input_at (6, 1) == "edited by B", "concurrent edit follows inserted rows on A");
    check (sb.input_at (6, 1) == "edited by B", "B moved its own edit");
    check (sa.input_at (10, 3) == "far", "second edit shifted");
    converge (p, "insert rows");
    p.hold = true;
    p.b.delete_cols (sb, 0, 1);
    p.a.set_input (sa, 0, 0, "gone");
    p.a.set_input (sa, 0, 2, "stays");
    p.hold = false;
    p.flush ();
    check (sb.input_at (0, 1) == "stays", "edit shifted left by concurrent delete");
    converge (p, "delete cols");
    var ns = p.a.add_sheet ();
    p.a.rename_sheet (ns, "Summary");
    check (p.b.book.find_sheet ("Summary") != null, "sheet add and rename propagate");
    p.a.set_input (p.a.book.find_sheet ("Summary"), 0, 0, "total");
    check (p.b.book.find_sheet ("Summary").input_at (0, 0) == "total", "edit on new sheet");
    p.b.remove_sheet (p.b.book.find_sheet ("Summary"));
    check (p.a.book.find_sheet ("Summary") == null, "sheet removal propagates");
    p.a.set_col_width (sa, 2, 2, 200);
    check (sb.col_width (2) == 200, "column width propagates");
    converge (p, "sheets");
}

void test_undo () {
    var p = new Pair ();
    var sa = p.a.book.sheets[0];
    var sb = p.b.book.sheets[0];
    p.a.set_input (sa, 0, 0, "mine");
    p.b.set_input (sb, 0, 0, "theirs");
    p.a.set_input (sa, 5, 5, "local only");
    p.a.undo ();
    check (sa.input_at (5, 5) == "" && sb.input_at (5, 5) == "", "undo of own edit propagates");
    p.a.undo ();
    check (sa.input_at (0, 0) == "theirs", "undo keeps the later remote edit, got " + sa.input_at (0, 0));
    check (sb.input_at (0, 0) == "theirs", "remote side unchanged by undo");
    p.a.redo ();
    check (sa.input_at (0, 0) == "theirs" && sb.input_at (0, 0) == "theirs", "redo keeps the later remote edit");
    p.a.insert_rows (sa, 0, 1);
    p.a.set_input (sa, 0, 0, "header");
    p.a.undo ();
    p.a.undo ();
    check (sb.input_at (0, 0) == sa.input_at (0, 0) && sb.input_at (1, 0) == sa.input_at (1, 0), "book level undo resynced");
    converge (p, "undo");
}

void test_session () {
    var loop = new MainLoop ();
    var host = new Singularity.LiveSession ("Anna", "sheet-live", "/sheet");
    var guest = new Singularity.LiveSession ("Marco", "sheet-live", "/sheet");
    var state = new Json.Object ();
    state.set_string_member ("hello", "world");
    bool welcomed = false, got_op = false, joined = false, left = false;
    try {
        host.host (state, 0, "127.0.0.1");
    } catch (Error e) {
        check (false, "host " + e.message);
        return;
    }
    check (host.link.has_prefix ("sheet-live://127.0.0.1:"), "link format " + host.link);
    host.peer_joined.connect ((pe) => joined = pe.name == "Marco");
    host.peer_left.connect ((pe) => left = true);
    host.message.connect ((m) => {
        got_op = m.get_string_member ("v") == "1";
        guest.leave ();
    });
    guest.welcome.connect ((st) => {
        welcomed = st.get_string_member ("hello") == "world";
        guest.presence (null);
        var o = new Json.Object ();
        o.set_string_member ("v", "1");
        guest.send (o);
    });
    guest.join.begin (host.link, (obj, res) => {
        try {
            guest.join.end (res);
        } catch (Error e) {
            check (false, "join " + e.message);
            loop.quit ();
        }
    });
    Timeout.add (100, () => {
        if (left || (!welcomed && get_monotonic_time () < 0)) {
            loop.quit ();
            return Source.REMOVE;
        }
        return Source.CONTINUE;
    });
    Timeout.add_seconds (8, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    check (welcomed, "guest got the welcome state");
    check (joined, "host saw the guest join");
    check (got_op, "host received the guest operation");
    check (left, "host saw the guest leave");
    host.leave ();
}

void test_folder () {
    string dir = Path.build_filename (Environment.get_tmp_dir (), "ss-live-folder-%d".printf (Random.int_range (0, 1000000)));
    var loop = new MainLoop ();
    var a = new Singularity.LiveSession ("Anna", "sheet-live", "/sheet");
    var b = new Singularity.LiveSession ("Marco", "sheet-live", "/sheet");
    var state = new Json.Object ();
    state.set_string_member ("s", "1");
    bool welcomed = false, got = false, seen = false;
    try {
        a.start_folder (dir, state);
        b.welcome.connect ((st) => welcomed = st.get_string_member ("s") == "1");
        b.start_folder (dir, null);
    } catch (Error e) {
        check (false, "folder " + e.message);
        return;
    }
    a.peer_joined.connect ((pe) => seen = pe.name == "Marco");
    a.message.connect ((m) => {
        got = m.get_string_member ("v") == "2";
        loop.quit ();
    });
    b.presence (null);
    var o = new Json.Object ();
    o.set_string_member ("v", "2");
    b.send (o);
    Timeout.add_seconds (6, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    check (welcomed, "folder join read the state");
    check (got, "folder operation delivered");
    check (seen, "folder presence seen");
    a.leave ();
    b.leave ();
    try {
        var d = Dir.open (dir);
        string? n;
        while ((n = d.read_name ()) != null) FileUtils.remove (Path.build_filename (dir, n));
        DirUtils.remove (dir);
    } catch (Error e) {
    }
}

int main (string[] args) {
    Test.init (ref args);
    LocaleInfo.set_c ();
    Test.add_func ("/live/basic", test_basic);
    Test.add_func ("/live/lww", test_lww);
    Test.add_func ("/live/structure", test_structure);
    Test.add_func ("/live/undo", test_undo);
    Test.add_func ("/live/session", test_session);
    Test.add_func ("/live/folder", test_folder);
    int r = Test.run ();
    if (failures > 0) {
        stderr.printf ("%d failures\n", failures);
        return 1;
    }
    return r;
}
