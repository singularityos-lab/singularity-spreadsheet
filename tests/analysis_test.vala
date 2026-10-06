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

double num (Sheet s, string addr) {
    int r, c;
    bool a, b;
    Address.parse_cell (addr, out r, out c, out a, out b);
    return s.value_at (r, c).number;
}

void expect (Sheet s, string addr, string expected) {
    string got = show (s, addr);
    if (got != expected) {
        stderr.printf ("FAIL %s!%s: expected [%s] got [%s]\n", s.name, addr, expected, got);
        Test.fail ();
    }
}

void near (string what, double got, double expected, double tol) {
    if (Math.fabs (got - expected) > tol) {
        stderr.printf ("FAIL %s: expected %.6f got %.6f\n", what, expected, got);
        Test.fail ();
    }
}

Workbook sales () {
    var book = new Workbook ();
    var s = book.add_sheet ("Data");
    string[] rows = {
        "Region,Product,Units,Date",
        "East,Apple,10,2024-01-15",
        "West,Apple,5,2024-02-10",
        "East,Pear,7,2024-04-02",
        "West,Pear,3,2024-05-20",
        "East,Apple,8,2025-01-03",
        "North,Plum,4,2025-07-09"
    };
    for (int i = 0; i < rows.length; i++) {
        var f = rows[i].split (",");
        for (int j = 0; j < f.length; j++) s.set_input (i, j, f[j]);
    }
    book.recalculate ();
    return book;
}

void test_pivot () {
    var book = sales ();
    var src = book.sheets[0];
    var out_s = book.add_sheet ("Pivot");
    var p = new PivotTable ("PivotTable1", out_s, 0, 0);
    p.source = new Area (src, 0, 0, 6, 3);
    p.rows.add (new PivotField (0, "Region"));
    p.values.add (new PivotValue (2, "Units", PivotAgg.SUM));
    Analysis.data (book).pivots.add (p);
    Analysis.write_pivot (book, p);
    expect (out_s, "A1", "Region");
    expect (out_s, "B1", "Sum of Units");
    expect (out_s, "A2", "East");
    expect (out_s, "B2", "25");
    expect (out_s, "A3", "North");
    expect (out_s, "B3", "4");
    expect (out_s, "A4", "West");
    expect (out_s, "B4", "8");
    expect (out_s, "A5", "Grand Total");
    expect (out_s, "B5", "37");

    p.cols.add (new PivotField (1, "Product"));
    Analysis.write_pivot (book, p);
    expect (out_s, "A1", "Sum of Units");
    expect (out_s, "B1", "Product");
    expect (out_s, "A2", "Region");
    expect (out_s, "B2", "Apple");
    expect (out_s, "C2", "Pear");
    expect (out_s, "D2", "Plum");
    expect (out_s, "E2", "Grand Total");
    expect (out_s, "A3", "East");
    expect (out_s, "B3", "18");
    expect (out_s, "C3", "7");
    expect (out_s, "E6", "37");
    expect (out_s, "B6", "23");

    p.cols.clear ();
    p.values[0].agg = PivotAgg.AVERAGE;
    p.values.add (new PivotValue (2, "Units", PivotAgg.COUNT));
    Analysis.write_pivot (book, p);
    expect (out_s, "B2", "8.333333333");
    expect (out_s, "C2", "3");
    expect (out_s, "C5", "6");
    expect (out_s, "F1", "");

    p.values.remove_at (1);
    p.values[0].agg = PivotAgg.SUM;
    p.values[0].show = PivotShow.PERCENT_TOTAL;
    Analysis.write_pivot (book, p);
    near ("percent east", num (out_s, "B2"), 25.0 / 37.0, 1e-9);
    near ("percent total", num (out_s, "B5"), 1, 1e-9);

    p.values[0].show = PivotShow.NORMAL;
    p.rows.clear ();
    var yf = new PivotField (3, "Date");
    yf.group = PivotGroup.YEARS;
    p.rows.add (yf);
    p.filters.add (new PivotField (0, "Region"));
    p.filters[0].hidden.add ("North");
    Analysis.write_pivot (book, p);
    expect (out_s, "A2", "2024");
    expect (out_s, "B2", "25");
    expect (out_s, "A3", "2025");
    expect (out_s, "B3", "8");
    expect (out_s, "B4", "33");

    p.filters.clear ();
    p.rows.clear ();
    p.rows.add (new PivotField (0, "Region"));
    p.rows.add (new PivotField (1, "Product"));
    Analysis.write_pivot (book, p);
    expect (out_s, "A2", "East");
    expect (out_s, "B2", "Apple");
    expect (out_s, "C2", "18");
    expect (out_s, "B3", "Pear");
    expect (out_s, "A4", "East Total");
    expect (out_s, "C4", "25");

    put (src, "H1", "=GETPIVOTDATA(\"Units\",Pivot!A1,\"Region\",\"East\",\"Product\",\"Apple\")");
    put (src, "H2", "=GETPIVOTDATA(\"Sum of Units\",Pivot!$A$1)");
    put (src, "H3", "=GETPIVOTDATA(\"Units\",Pivot!A1,\"Region\",\"Nowhere\")");
    put (src, "H4", "=GETPIVOTDATA(\"Units\",Pivot!A1,\"Region\",\"West\")");
    book.recalculate ();
    expect (src, "H1", "18");
    expect (src, "H2", "37");
    expect (src, "H3", "#REF!");
    expect (src, "H4", "8");
}

void test_data_types () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "Country");
    put (s, "B1", "Capital");
    put (s, "C1", "Population");
    put (s, "A2", "Italy");
    put (s, "B2", "Rome");
    put (s, "C2", "59");
    put (s, "A3", "France");
    put (s, "B3", "Paris");
    put (s, "C3", "68");
    var t = new TableDef ("Countries", s, new Area (s, 0, 0, 2, 2));
    t.sync_columns ();
    book.tables.add (t);
    var d = book.add_sheet ("D");
    put (d, "A1", "france");
    put (d, "A2", "Italy");
    put (d, "A3", "Spain");
    book.recalculate ();
    int n = DataTypes.convert (book, d, new Area (d, 0, 0, 2, 0), "Countries", "Country");
    if (n != 2) Test.fail ();
    put (d, "B1", "=A1.Capital");
    put (d, "B2", "=FIELDVALUE(A2,\"Population\")*2");
    put (d, "B3", "=FIELDVALUE(A3,\"Capital\")");
    put (d, "C1", "=A1.[Population]");
    put (d, "D1", "=SUM(FIELDVALUE(A1:A2,\"Population\"))");
    book.recalculate ();
    expect (d, "B1", "Paris");
    expect (d, "B2", "118");
    expect (d, "B3", "#VALUE!");
    expect (d, "C1", "68");
    expect (d, "D1", "127");
    string text = AnalysisStore.serialize (book);
    var b2 = new Workbook ();
    b2.add_sheet ("S");
    b2.add_sheet ("D");
    AnalysisStore.deserialize (b2, text);
    if (DataTypes.link_at (b2, b2.sheets[1], 0, 0) == null) Test.fail ();
}

void test_goal_seek () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "1");
    put (s, "B1", "=A1^2-2");
    book.recalculate ();
    double result, reached;
    bool ok = WhatIf.goal_seek (book, new CellRef (s, 0, 1), 0, new CellRef (s, 0, 0), out result, out reached);
    if (!ok) Test.fail ();
    near ("goal seek sqrt2", result, Math.sqrt (2), 1e-3);
    put (s, "C1", "100000");
    put (s, "D1", "0.05");
    put (s, "E1", "10");
    put (s, "F1", "=PMT(D1/12,E1*12,-C1)");
    book.recalculate ();
    ok = WhatIf.goal_seek (book, new CellRef (s, 0, 5), 1000, new CellRef (s, 0, 2), out result, out reached);
    if (!ok) Test.fail ();
    near ("goal seek pmt", num (s, "F1"), 1000, 0.01);
}

void test_data_table () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "2");
    put (s, "B1", "3");
    put (s, "D1", "=A1*10");
    put (s, "C2", "1");
    put (s, "C3", "2");
    put (s, "C4", "3");
    var dt = new DataTableDef (s, new Area (s, 0, 2, 3, 3));
    dt.col_input = new CellRef (s, 0, 0);
    Analysis.data (book).data_tables.add (dt);
    book.recalculate ();
    expect (s, "D2", "10");
    expect (s, "D3", "20");
    expect (s, "D4", "30");
    expect (s, "D1", "20");
    put (s, "F1", "=A1*B1");
    put (s, "G1", "1");
    put (s, "H1", "2");
    put (s, "F2", "5");
    put (s, "F3", "6");
    var dt2 = new DataTableDef (s, new Area (s, 0, 5, 2, 7));
    dt2.row_input = new CellRef (s, 0, 0);
    dt2.col_input = new CellRef (s, 0, 1);
    Analysis.data (book).data_tables.add (dt2);
    book.recalculate ();
    expect (s, "G2", "5");
    expect (s, "H2", "10");
    expect (s, "H3", "12");
    expect (s, "F1", "6");
    put (s, "D1", "=A1*100");
    book.recalculate ();
    expect (s, "D3", "200");
}

void test_scenarios () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "1");
    put (s, "A2", "=A1*3");
    book.recalculate ();
    var sc = new Scenario ("High", s);
    sc.cells.add (new CellRef (s, 0, 0));
    sc.values.add ("10");
    var sc2 = new Scenario ("Low", s);
    sc2.cells.add (new CellRef (s, 0, 0));
    sc2.values.add ("2");
    var list = new Gee.ArrayList<Scenario> ();
    list.add (sc);
    list.add (sc2);
    var results = new Gee.ArrayList<CellRef> ();
    results.add (new CellRef (s, 1, 0));
    var sum = Scenario.summary (book, list, results);
    expect (sum, "C8", "30");
    expect (sum, "D8", "6");
    expect (sum, "E8", "3");
    expect (s, "A1", "1");
    sc.show (book);
    expect (s, "A2", "30");
}

void test_solver_lp () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "0");
    put (s, "B1", "0");
    put (s, "C1", "=3*A1+5*B1");
    put (s, "D1", "=A1");
    put (s, "D2", "=2*B1");
    put (s, "D3", "=3*A1+2*B1");
    book.recalculate ();
    var m = new SolverModel (s);
    m.objective = "$C$1";
    m.goal = SolverGoal.MAX;
    m.variables = "$A$1:$B$1";
    put (s, "E1", "4");
    put (s, "E2", "12");
    put (s, "E3", "18");
    m.constraints.add (new SolverConstraint ("$D$1:$D$3", ConstraintOp.LE, "$E$1:$E$3"));
    var r = m.solve (book);
    if (!r.ok) {
        stderr.printf ("LP: %s\n", r.message);
        Test.fail ();
    }
    near ("lp objective", num (s, "C1"), 36, 1e-6);
    near ("lp x", num (s, "A1"), 2, 1e-6);
    near ("lp y", num (s, "B1"), 6, 1e-6);

    put (s, "A1", "0");
    put (s, "B1", "0");
    put (s, "C1", "=5*A1+4*B1");
    put (s, "D1", "=6*A1+4*B1");
    put (s, "D2", "=A1+2*B1");
    book.recalculate ();
    var m2 = new SolverModel (s);
    m2.objective = "C1";
    m2.variables = "A1:B1";
    m2.constraints.add (new SolverConstraint ("D1", ConstraintOp.LE, "24"));
    m2.constraints.add (new SolverConstraint ("D2", ConstraintOp.LE, "6"));
    m2.constraints.add (new SolverConstraint ("A1:B1", ConstraintOp.INT, ""));
    r = m2.solve (book);
    if (!r.ok) Test.fail ();
    near ("ilp objective", num (s, "C1"), 20, 1e-6);

    put (s, "C1", "=A1+B1");
    put (s, "D1", "=A1+B1");
    book.recalculate ();
    var m3 = new SolverModel (s);
    m3.objective = "C1";
    m3.goal = SolverGoal.MIN;
    m3.variables = "A1:B1";
    m3.constraints.add (new SolverConstraint ("D1", ConstraintOp.GE, "5"));
    m3.constraints.add (new SolverConstraint ("A1", ConstraintOp.EQ, "2"));
    r = m3.solve (book);
    if (!r.ok) Test.fail ();
    near ("lp min", num (s, "C1"), 5, 1e-6);
    near ("lp eq", num (s, "A1"), 2, 1e-6);

    m3.to_names ();
    var back = SolverModel.from_names (s);
    if (back == null || back.constraints.size != 2 || back.goal != SolverGoal.MIN || back.constraints[0].op != ConstraintOp.GE) Test.fail ();
}

void test_solver_nlp () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "0");
    put (s, "B1", "0");
    put (s, "C1", "=(A1-3)^2+(B1+1)^2+2");
    book.recalculate ();
    var m = new SolverModel (s);
    m.objective = "C1";
    m.goal = SolverGoal.MIN;
    m.variables = "A1:B1";
    m.nonneg = false;
    m.method = SolverMethod.NONLINEAR;
    m.multistart = 2;
    var r = m.solve (book);
    if (!r.ok) Test.fail ();
    near ("nlp objective", num (s, "C1"), 2, 1e-3);
    near ("nlp x", num (s, "A1"), 3, 1e-2);
    near ("nlp y", num (s, "B1"), -1, 1e-2);
    put (s, "D1", "=A1+B1");
    put (s, "C1", "=A1*B1");
    book.recalculate ();
    var m2 = new SolverModel (s);
    m2.objective = "C1";
    m2.goal = SolverGoal.MAX;
    m2.variables = "A1:B1";
    m2.method = SolverMethod.NONLINEAR;
    m2.multistart = 2;
    m2.constraints.add (new SolverConstraint ("D1", ConstraintOp.LE, "10"));
    r = m2.solve (book);
    near ("nlp constrained", num (s, "C1"), 25, 0.05);
    put (s, "A1", "1");
    put (s, "B1", "2");
    put (s, "E1", "3");
    put (s, "C1", "=A1*1+B1*10+E1*100");
    book.recalculate ();
    var m3 = new SolverModel (s);
    m3.objective = "C1";
    m3.goal = SolverGoal.MAX;
    m3.variables = "A1:B1,E1";
    m3.method = SolverMethod.EVOLUTIONARY;
    m3.constraints.add (new SolverConstraint ("A1:B1,E1", ConstraintOp.DIF, ""));
    r = m3.solve (book);
    near ("dif objective", num (s, "C1"), 321, 1e-6);
}

void test_query () {
    string dir;
    try {
        dir = DirUtils.make_tmp ("ss-query-XXXXXX");
    } catch (Error e) {
        Test.fail ();
        return;
    }
    string csv = Path.build_filename (dir, "sales.csv");
    string json = Path.build_filename (dir, "items.json");
    try {
        FileUtils.set_contents (csv, "Region,Product,Units\nEast,Apple,10\nWest,Apple,5\nEast,Pear,7\nWest,Pear, 3\nEast,Apple,8\n");
        FileUtils.set_contents (json, "{\"items\":[{\"code\":\"Apple\",\"info\":{\"color\":\"red\"}},{\"code\":\"Pear\",\"info\":{\"color\":\"green\"}}]}");
    } catch (Error e) {
        Test.fail ();
        return;
    }
    var book = new Workbook ();
    book.add_sheet ("S");
    var colors = new QueryDef ("Colors");
    colors.source_kind = "json";
    colors.location = json;
    Analysis.data (book).queries.add (colors);
    var q = new QueryDef ("Sales");
    q.source_kind = "csv";
    q.location = csv;
    q.steps.add (new QueryStep ("promote-headers"));
    q.steps.add (new QueryStep ("filter-rows").with ("column", "Units").with ("op", ">").with ("value", "4"));
    q.steps.add (new QueryStep ("merge").with ("query", "Colors").with ("key", "Product").with ("other-key", "code"));
    q.steps.add (new QueryStep ("group-by").with ("keys", "Region,Colors.info.color").with ("column", "Units").with ("function", "sum").with ("name", "Total"));
    q.steps.add (new QueryStep ("sort").with ("columns", "Total").with ("descending", "1"));
    q.load = true;
    Analysis.data (book).queries.add (q);
    try {
        var df = QueryEngine.run (book, q);
        if (df.columns.size != 3 || df.rows.size != 3) {
            stderr.printf ("query shape %d x %d\n", df.rows.size, df.columns.size);
            Test.fail ();
        }
        if (df.at (0, 0).display () != "East" || df.at (0, 2).number != 18) Test.fail ();
        var area = Analysis.load_query (book, q);
        var out_s = area.sheet;
        expect (out_s, "A1", "Region");
        expect (out_s, "C1", "Total");
        expect (out_s, "C2", "18");
        expect (out_s, "B2", "red");
        if (Tables.find (book, q.table_name) == null) Test.fail ();
        var u = new QueryDef ("Unp");
        u.source_kind = "range";
        u.location = q.table_name;
        u.steps.add (new QueryStep ("unpivot").with ("keep", "Region,Colors.info.color"));
        u.steps.add (new QueryStep ("remove-columns").with ("columns", "Attribute"));
        var ud = QueryEngine.run (book, u);
        if (ud.rows.size != 3 || ud.columns.size != 3) Test.fail ();
        var h = QueryEngine.parse_html_table ("<html><table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>x &amp; y</td></tr></table></html>");
        if (h.columns[0] != "A" || h.at (0, 1).display () != "x & y" || h.at (0, 0).number != 1) Test.fail ();
        var t = new QueryStep ("split-column").with ("column", "B").with ("delimiter", "&");
        var sp = QueryEngine.apply (book, h, t);
        if (sp.columns.size != 3 || sp.at (0, 2).display () != "y") Test.fail ();
    } catch (Error e) {
        stderr.printf ("query error %s\n", e.message);
        Test.fail ();
    }
    FileUtils.remove (csv);
    FileUtils.remove (json);
    DirUtils.remove (dir);
}

void test_store () {
    var book = sales ();
    var src = book.sheets[0];
    var out_s = book.add_sheet ("Pivot");
    var p = new PivotTable ("PT", out_s, 2, 1);
    p.source = new Area (src, 0, 0, 6, 3);
    p.rows.add (new PivotField (0, "Region"));
    p.values.add (new PivotValue (2, "Units", PivotAgg.MAX));
    p.values[0].show = PivotShow.PERCENT_COL;
    Analysis.data (book).pivots.add (p);
    var q = new QueryDef ("Q1");
    q.location = "/x.csv";
    q.steps.add (new QueryStep ("sort").with ("columns", "A,B").with ("descending", "0,1"));
    Analysis.data (book).queries.add (q);
    var sc = new Scenario ("Best", src);
    sc.cells.add (new CellRef (src, 1, 2));
    sc.values.add ("99");
    Analysis.data (book).scenarios.add (sc);
    string text = AnalysisStore.serialize (book);
    var book2 = sales ();
    book2.add_sheet ("Pivot");
    AnalysisStore.deserialize (book2, text);
    var d = Analysis.data (book2);
    if (d.pivots.size != 1 || d.queries.size != 1 || d.scenarios.size != 1) {
        Test.fail ();
        return;
    }
    var p2 = d.pivots[0];
    if (p2.target_sheet.name != "Pivot" || p2.target_row != 2 || p2.values[0].agg != PivotAgg.MAX || p2.values[0].show != PivotShow.PERCENT_COL || p2.rows[0].name != "Region") Test.fail ();
    if (d.queries[0].steps[0].arg ("descending") != "0,1") Test.fail ();
    if (d.scenarios[0].values[0] != "99") Test.fail ();
    string path = Path.build_filename (Environment.get_tmp_dir (), "ss-analysis-%d.xlsx".printf (Random.int_range (0, 1000000)));
    try {
        XlsxWriter.save (book, path);
        var loaded = Xlsx.load (path);
        if (Analysis.data (loaded).pivots.size != 1) {
            stderr.printf ("xlsx pivots lost\n");
            Test.fail ();
        }
        FileUtils.remove (path);
        string opath = path.replace (".xlsx", ".ods");
        Ods.save (book, opath);
        var lo = Ods.load (opath);
        if (Analysis.data (lo).pivots.size != 1 || Analysis.data (lo).queries.size != 1) {
            stderr.printf ("ods analysis lost\n");
            Test.fail ();
        }
        AnalysisStore.ignore_store = true;
        var lo2 = Ods.load (opath);
        AnalysisStore.ignore_store = false;
        var dp = Analysis.data (lo2).pivots;
        if (dp.size != 1 || dp[0].rows.size != 1 || dp[0].rows[0].name != "Region" || dp[0].values[0].agg != PivotAgg.MAX || dp[0].target_row != 2 || dp[0].target_col != 1) {
            stderr.printf ("ods data pilot round trip failed %d %s\n", dp.size, dp.size > 0 ? "%d rows %d r%d c%d".printf (dp[0].rows.size, dp[0].values.size, dp[0].target_row, dp[0].target_col) : "");
            Test.fail ();
        }
        FileUtils.remove (opath);
    } catch (Error e) {
        stderr.printf ("store io %s\n", e.message);
        Test.fail ();
    }
}

void test_excel_parts () {
    var book = sales ();
    var src = book.sheets[0];
    var out_s = book.add_sheet ("Pivot");
    var p = new PivotTable ("PT", out_s, 2, 0);
    p.source = new Area (src, 0, 0, 6, 3);
    p.rows.add (new PivotField (0, "Region"));
    p.cols.add (new PivotField (1, "Product"));
    p.rows[0].hidden.add ("North");
    p.values.add (new PivotValue (2, "Units", PivotAgg.AVERAGE));
    Analysis.data (book).pivots.add (p);
    Analysis.write_pivot (book, p);
    var l = book.add_sheet ("Loan");
    put (l, "A1", "2");
    put (l, "D1", "=A1*10");
    put (l, "C2", "1");
    put (l, "C3", "2");
    var dt = new DataTableDef (l, new Area (l, 0, 2, 2, 3));
    dt.col_input = new CellRef (l, 0, 0);
    Analysis.data (book).data_tables.add (dt);
    put (l, "G1", "=A1*B1");
    put (l, "H1", "1");
    put (l, "I1", "2");
    put (l, "G2", "5");
    var dt2 = new DataTableDef (l, new Area (l, 0, 6, 1, 8));
    dt2.row_input = new CellRef (l, 0, 0);
    dt2.col_input = new CellRef (l, 0, 1);
    Analysis.data (book).data_tables.add (dt2);
    book.recalculate ();
    string path = Path.build_filename (Environment.get_tmp_dir (), "ss-pivot-%d.xlsx".printf (Random.int_range (0, 1000000)));
    try {
        XlsxWriter.save (book, path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        var zip = new ZipReader (data);
        foreach (string part in new string[] { "xl/pivotCache/pivotCacheDefinition1.xml", "xl/pivotCache/pivotCacheRecords1.xml", "xl/pivotTables/pivotTable1.xml", "xl/pivotTables/_rels/pivotTable1.xml.rels" }) {
            if (!zip.has (part)) {
                stderr.printf ("missing %s\n", part);
                Test.fail ();
            }
        }
        string wb = zip.read_text ("xl/workbook.xml");
        if (!wb.contains ("<pivotCaches><pivotCache cacheId=\"0\"")) Test.fail ();
        string ct = zip.read_text ("[Content_Types].xml");
        if (!ct.contains ("pivotTable+xml") || !ct.contains ("pivotCacheRecords+xml")) Test.fail ();
        string sheet_rels = zip.read_text ("xl/worksheets/_rels/sheet2.xml.rels") ?? "";
        if (!sheet_rels.contains ("../pivotTables/pivotTable1.xml")) Test.fail ();
        string loan = zip.read_text ("xl/worksheets/sheet3.xml");
        if (!loan.contains ("<f t=\"dataTable\" ref=\"D2:D3\" dt2D=\"0\" dtr=\"0\" r1=\"A1\"/>")) {
            stderr.printf ("dataTable formula missing\n");
            Test.fail ();
        }
        if (!loan.contains ("dt2D=\"1\" dtr=\"1\" r1=\"A1\" r2=\"B1\"")) Test.fail ();
        AnalysisStore.ignore_store = true;
        var loaded = Xlsx.load (path);
        AnalysisStore.ignore_store = false;
        var d = Analysis.data (loaded);
        if (d.pivots.size != 1 || d.data_tables.size != 2) {
            stderr.printf ("excel parts read: pivots %d tables %d\n", d.pivots.size, d.data_tables.size);
            Test.fail ();
            return;
        }
        var q = d.pivots[0];
        if (q.rows.size != 1 || q.cols.size != 1 || q.values[0].agg != PivotAgg.AVERAGE || !q.rows[0].hidden.contains ("North") || q.target_row != 2) Test.fail ();
        var o2 = loaded.find_sheet ("Pivot");
        string before = show (out_s, "B4") + "|" + show (out_s, "E6");
        Analysis.write_pivot (loaded, q);
        string after = show (o2, "B4") + "|" + show (o2, "E6");
        if (before != after) {
            stderr.printf ("pivot after reload %s vs %s\n", before, after);
            Test.fail ();
        }
        var t2 = d.data_tables[0].two_way () ? d.data_tables[0] : d.data_tables[1];
        if (t2.row_input.col != 0 || t2.col_input.col != 1) Test.fail ();
        FileUtils.remove (path);
    } catch (Error e) {
        stderr.printf ("excel parts %s\n", e.message);
        Test.fail ();
    }
}

string pivot_dump (Sheet s, Area a) {
    var sb = new StringBuilder ();
    for (int r = a.r1; r <= a.r2; r++) {
        for (int c = a.c1; c <= a.c2; c++) sb.append (s.value_at (r, c).display ()).append_c ('|');
        sb.append_c ('\n');
    }
    return sb.str;
}

void test_grouping () {
    var book = sales ();
    var src = book.sheets[0];
    var out_s = book.add_sheet ("Pivot");
    var p = new PivotTable ("Dates", out_s, 0, 0);
    p.source = new Area (src, 0, 0, 6, 3);
    var years = new PivotField (3, "Years");
    years.group = PivotGroup.YEARS;
    var quarters = new PivotField (3, "Date");
    quarters.group = PivotGroup.QUARTERS;
    quarters.hidden.add ("Qtr3");
    p.rows.add (years);
    p.rows.add (quarters);
    p.values.add (new PivotValue (2, "Units", PivotAgg.SUM));
    Analysis.data (book).pivots.add (p);
    Analysis.write_pivot (book, p);
    expect (out_s, "A2", "2024");
    expect (out_s, "B2", "Qtr1");
    expect (out_s, "C2", "15");
    expect (out_s, "B3", "Qtr2");
    expect (out_s, "C3", "10");
    var p2 = new PivotTable ("Ranges", out_s, 0, 6);
    p2.source = new Area (src, 0, 0, 6, 3);
    var units = new PivotField (2, "Units");
    units.group = PivotGroup.INTERVAL;
    units.interval_start = 0;
    units.interval_size = 5;
    p2.rows.add (units);
    p2.values.add (new PivotValue (2, "Units", PivotAgg.COUNT));
    Analysis.data (book).pivots.add (p2);
    Analysis.write_pivot (book, p2);
    expect (out_s, "G2", "0-4");
    expect (out_s, "H2", "2");
    expect (out_s, "G3", "5-9");
    expect (out_s, "H3", "3");
    string before1 = pivot_dump (out_s, p.last_output);
    string before2 = pivot_dump (out_s, p2.last_output);
    string path = Path.build_filename (Environment.get_tmp_dir (), "ss-group-%d.xlsx".printf (Random.int_range (0, 1000000)));
    try {
        XlsxWriter.save (book, path);
        uint8[] data;
        FileUtils.get_data (path, out data);
        var zip = new ZipReader (data);
        string c1 = zip.read_text ("xl/pivotCache/pivotCacheDefinition1.xml");
        if (!c1.contains ("<fieldGroup par=\"4\" base=\"3\"><rangePr groupBy=\"quarters\" startDate=\"2024-01-15T00:00:00\" endDate=\"2025-07-10T00:00:00\"/>") || !c1.contains ("databaseField=\"0\"><fieldGroup base=\"3\"><rangePr groupBy=\"years\"") || !c1.contains ("containsDate=\"1\"") || !c1.contains ("<s v=\"Qtr1\"/>")) {
            stderr.printf ("date group xml: %s\n", c1);
            Test.fail ();
        }
        string c2 = zip.read_text ("xl/pivotCache/pivotCacheDefinition2.xml");
        if (!c2.contains ("<rangePr autoStart=\"0\" startNum=\"0\" endNum=\"10\" groupInterval=\"5\"/><groupItems count=\"5\"><s v=\"&lt;0\"/><s v=\"0-4\"/>")) {
            stderr.printf ("num group xml: %s\n", c2);
            Test.fail ();
        }
        string t1 = zip.read_text ("xl/pivotTables/pivotTable1.xml");
        if (!t1.contains ("<rowFields count=\"2\"><field x=\"4\"/><field x=\"3\"/></rowFields>") || !t1.contains ("<pivotFields count=\"5\">")) {
            stderr.printf ("pivot table xml: %s\n", t1);
            Test.fail ();
        }
        foreach (string fmt in new string[] { "xlsx", "ods" }) {
            string fpath = fmt == "xlsx" ? path : path.replace (".xlsx", ".ods");
            if (fmt == "ods") Ods.save (book, fpath);
            AnalysisStore.ignore_store = true;
            var loaded = fmt == "xlsx" ? Xlsx.load (fpath) : Ods.load (fpath);
            AnalysisStore.ignore_store = false;
            var d = Analysis.data (loaded);
            if (d.pivots.size != 2) {
                stderr.printf ("%s grouping: %d pivots\n", fmt, d.pivots.size);
                Test.fail ();
                continue;
            }
            var q = d.pivots[0];
            if (q.rows.size != 2 || q.rows[0].group != PivotGroup.YEARS || q.rows[1].group != PivotGroup.QUARTERS || q.rows[0].source_col != 3 || q.rows[1].source_col != 3) {
                stderr.printf ("%s grouping fields wrong\n", fmt);
                Test.fail ();
            }
            if (fmt == "xlsx" && !q.rows[1].hidden.contains ("Qtr3")) Test.fail ();
            var q2 = d.pivots[1];
            if (q2.rows[0].group != PivotGroup.INTERVAL || q2.rows[0].interval_size != 5 || q2.rows[0].interval_start != 0) {
                stderr.printf ("%s interval wrong\n", fmt);
                Test.fail ();
            }
            var os = loaded.find_sheet ("Pivot");
            Analysis.write_pivot (loaded, q);
            Analysis.write_pivot (loaded, q2);
            string after1 = pivot_dump (os, q.last_output);
            string after2 = pivot_dump (os, q2.last_output);
            if (fmt == "xlsx" && after1 != before1) {
                stderr.printf ("regrouped differs:\n%s\nvs\n%s\n", before1, after1);
                Test.fail ();
            }
            if (after2 != before2) {
                stderr.printf ("%s ranges differ:\n%s\nvs\n%s\n", fmt, before2, after2);
                Test.fail ();
            }
            FileUtils.remove (fpath);
        }
    } catch (Error e) {
        stderr.printf ("grouping io %s\n", e.message);
        Test.fail ();
    }
    var cities = new Workbook ();
    var cs = cities.add_sheet ("C");
    string[] names = { "City", "Zürich", "Shanghai", "São Paulo", "Zagreb", "Seoul", "sao tome" };
    for (int i = 0; i < names.length; i++) {
        cs.set_input (i, 0, names[i]);
        cs.set_input (i, 1, "1");
    }
    cities.recalculate ();
    var cp = new PivotTable ("C", cs, 0, 4);
    cp.source = new Area (cs, 0, 0, names.length - 1, 1);
    var items = cp.field_items (cities, 0);
    string[] order = {};
    foreach (var it in items) order += it.label;
    string got = string.joinv (",", order);
    if (got != "São Paulo,sao tome,Seoul,Shanghai,Zagreb,Zürich") {
        stderr.printf ("sort order %s\n", got);
        Test.fail ();
    }
}

void test_tools () {
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    double[] x = { 1, 2, 3, 4, 5 };
    double[] y = { 2.2, 4.1, 6.3, 7.9, 10.1 };
    put (s, "A1", "X");
    put (s, "B1", "Y");
    for (int i = 0; i < 5; i++) {
        s.set_input (i + 1, 0, Singularity.Apps.Spreadsheet.Value.format_number_general_full (x[i]));
        s.set_input (i + 1, 1, Singularity.Apps.Spreadsheet.Value.format_number_general_full (y[i]));
    }
    book.recalculate ();
    var d = Analysis.descriptive (book, new Area (s, 0, 0, 5, 0), true);
    expect (d, "B3", "3");
    near ("stdev", num (d, "B7"), 1.58113883, 1e-6);
    expect (d, "B15", "5");
    var reg = Analysis.regression (book, new Area (s, 0, 1, 5, 1), new Area (s, 0, 0, 5, 0), true);
    near ("slope", num (reg, "B18"), 1.96, 1e-9);
    near ("intercept", num (reg, "B17"), 0.24, 1e-9);
    near ("r2", num (reg, "B5"), 0.998, 2e-3);
    var h = Analysis.histogram (book, new Area (s, 1, 0, 5, 0), null, false, false);
    expect (h, "A1", "Bin");
    var cor = Analysis.matrix (book, new Area (s, 0, 0, 5, 1), true, false);
    near ("corr", num (cor, "B3"), 0.99899, 1e-4);
    near ("t two tail", Analysis.t_two_tail (2.0, 10), 0.07338803, 1e-6);
    var tt = Analysis.t_test (book, new Area (s, 0, 0, 5, 0), new Area (s, 0, 1, 5, 1), Analysis.TTest.PAIRED, true);
    near ("paired t", num (tt, "B9"), -4.578345, 1e-5);
    double sigma;
    double[] series = { 10, 12, 14, 16, 18, 20, 22, 24 };
    var fc = Analysis.holt_winters (series, 1, 2, out sigma);
    near ("hw linear", fc[0], 26, 0.5);
}

void test_subtotals_consolidate_filter () {
    var book = sales ();
    var s = book.sheets[0];
    int n = Analysis.subtotals (book, s, new Area (s, 0, 0, 6, 3), 0, "sum", { 2 }, false, false, true);
    if (n != 6) Test.fail ();
    expect (s, "A3", "East Total");
    expect (s, "C3", "10");
    string last = show (s, "A14");
    if (last != "Grand Total") {
        stderr.printf ("grand total at A14 is [%s]\n", last);
        Test.fail ();
    }
    expect (s, "C14", "37");
    if (s.outline.max_level (true) < 2) Test.fail ();

    var b2 = new Workbook ();
    var s1 = b2.add_sheet ("Jan");
    var s2 = b2.add_sheet ("Feb");
    var dst = b2.add_sheet ("All");
    put (s1, "A1", "Item"); put (s1, "B1", "Qty");
    put (s1, "A2", "Nut"); put (s1, "B2", "3");
    put (s1, "A3", "Bolt"); put (s1, "B3", "2");
    put (s2, "A1", "Item"); put (s2, "B1", "Qty");
    put (s2, "A2", "Bolt"); put (s2, "B2", "5");
    put (s2, "A3", "Gear"); put (s2, "B3", "1");
    b2.recalculate ();
    var srcs = new Gee.ArrayList<Area> ();
    srcs.add (new Area (s1, 0, 0, 2, 1));
    srcs.add (new Area (s2, 0, 0, 2, 1));
    Analysis.consolidate (b2, srcs, dst, 0, 0, "sum", true, true, false);
    expect (dst, "A2", "Nut");
    expect (dst, "B3", "7");
    expect (dst, "A4", "Gear");
    Analysis.consolidate (b2, srcs, dst, 10, 0, "sum", true, true, true);
    expect (dst, "B13", "7");

    var b3 = sales ();
    var d3 = b3.sheets[0];
    put (d3, "G1", "Region");
    put (d3, "H1", "Units");
    put (d3, "G2", "East");
    put (d3, "H2", ">7");
    put (d3, "G3", "North");
    b3.recalculate ();
    var dest = b3.add_sheet ("Out");
    int m = Analysis.advanced_filter (b3, new Area (d3, 0, 0, 6, 3), new Area (d3, 0, 6, 2, 7), new Area (dest, 0, 0, 0, 0), false);
    if (m != 3) {
        stderr.printf ("advanced filter matched %d\n", m);
        Test.fail ();
    }
    expect (dest, "C2", "10");
    expect (dest, "A4", "North");
    m = Analysis.advanced_filter (b3, new Area (d3, 0, 0, 6, 1), new Area (d3, 0, 6, 1, 6), null, true);
    if (m != 2) Test.fail ();
    if (!d3.hidden_rows.contains (2)) Test.fail ();
}

int main (string[] args) {
    Test.init (ref args);
    LocaleInfo.set_c ();
    Test.add_func ("/analysis/pivot", test_pivot);
    Test.add_func ("/analysis/data-types", test_data_types);
    Test.add_func ("/analysis/goal-seek", test_goal_seek);
    Test.add_func ("/analysis/data-table", test_data_table);
    Test.add_func ("/analysis/scenarios", test_scenarios);
    Test.add_func ("/analysis/solver-lp", test_solver_lp);
    Test.add_func ("/analysis/solver-nlp", test_solver_nlp);
    Test.add_func ("/analysis/query", test_query);
    Test.add_func ("/analysis/store", test_store);
    Test.add_func ("/analysis/excel-parts", test_excel_parts);
    Test.add_func ("/analysis/grouping", test_grouping);
    Test.add_func ("/analysis/tools", test_tools);
    Test.add_func ("/analysis/subtotals", test_subtotals_consolidate_filter);
    return Test.run ();
}
