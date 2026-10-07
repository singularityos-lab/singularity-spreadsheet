using Singularity.Apps.Spreadsheet;
using Singularity.Charts;

string tmp_path (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "ss-charts-%d-%s".printf (Random.int_range (0, 1000000), name));
}

int failures = 0;

void fail (string msg) {
    stderr.printf ("FAIL %s\n", msg);
    failures++;
}

Bytes tiny_png () {
    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 8, 6);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (0.2, 0.5, 0.8);
    cr.paint ();
    string p = tmp_path ("img.png");
    surf.write_to_png (p);
    uint8[] data;
    try {
        FileUtils.get_data (p, out data);
    } catch (Error e) {
        data = {};
    }
    FileUtils.remove (p);
    return new Bytes (data);
}

Workbook sample (Bytes png) {
    var book = new Workbook ();
    var s = book.add_sheet ("Data Sheet");
    string[] months = { "Jan", "Feb", "Mar", "Apr", "May" };
    s.set_input (0, 0, "Month");
    s.set_input (0, 1, "Sales");
    s.set_input (0, 2, "Margin");
    for (int i = 0; i < months.length; i++) {
        s.set_input (i + 1, 0, months[i]);
        s.set_input (i + 1, 1, "%d".printf (100 + i * 25));
        s.set_input (i + 1, 2, "0.%d".printf (10 + i * 3));
    }
    var ch = new Chart (new Area (s, 0, 0, 5, 2));
    ch.kind = "combo";
    ch.title = "Sales and margin";
    ch.x = 300;
    ch.y = 30;
    ch.width = 420;
    ch.height = 260;
    var s0 = new Series ();
    s0.trendline = new Trendline ();
    s0.trendline.kind = TrendType.LINEAR;
    s0.trendline.show_equation = true;
    s0.trendline.show_r2 = true;
    var s1 = new Series ();
    s1.has_type = true;
    s1.kind = ChartType.LINE;
    s1.secondary = true;
    ch.style.series.add (s0);
    ch.style.series.add (s1);
    ch.style.y_axis.title = "Sales";
    ch.style.y2_axis.title = "Margin";
    s.charts.add (ch);
    var pie = new Chart (new Area (s, 0, 0, 5, 1));
    pie.kind = "doughnut";
    pie.title = "Share";
    pie.x = 20;
    pie.y = 200;
    s.charts.add (pie);
    var wf = new Chart (new Area (s, 0, 0, 5, 1));
    wf.kind = "waterfall";
    wf.x = 20;
    wf.y = 500;
    s.charts.add (wf);
    var img = new Drawing (DrawingKind.IMAGE);
    img.image = png;
    img.mime = "image/png";
    img.x = 10;
    img.y = 10;
    img.width = 80;
    img.height = 60;
    s.drawings.add (img);
    var rect = new Drawing (DrawingKind.ROUNDED);
    rect.text = "Note box";
    rect.fill = "#ff8800";
    rect.x = 100;
    rect.y = 400;
    s.drawings.add (rect);
    var arrow = new Drawing (DrawingKind.ARROW);
    arrow.stroke = "#112233";
    arrow.x = 50;
    arrow.y = 450;
    arrow.width = 120;
    arrow.height = 40;
    s.drawings.add (arrow);
    var tb = new Drawing (DrawingKind.TEXT_BOX);
    tb.text = "Hello box";
    s.drawings.add (tb);
    var g = new SparklineGroup ();
    g.kind = SparklineKind.COLUMN;
    g.high = true;
    g.items.add (new Sparkline (1, 4, "'Data Sheet'!B2:C2"));
    g.items.add (new Sparkline (2, 4, "'Data Sheet'!B3:C3"));
    s.sparklines.add (g);
    book.recalculate ();
    return book;
}

void check_book (string label, Workbook b, Bytes png) {
    var s = b.sheets[0];
    if (s.charts.size != 3) {
        fail ("%s charts=%d".printf (label, s.charts.size));
        return;
    }
    var ch = s.charts[0];
    var spec = ChartResolve.resolve (b, s, ch);
    if (ch.title != "Sales and margin") fail ("%s title [%s]".printf (label, ch.title));
    if (spec.series.size != 2) fail ("%s series=%d".printf (label, spec.series.size));
    else {
        if (!spec.series[1].secondary) fail (label + " secondary lost");
        if (spec.type_of (spec.series[1]) != ChartType.LINE) fail (label + " combo line lost");
        if (spec.series[0].trendline == null || spec.series[0].trendline.kind != TrendType.LINEAR) fail (label + " trendline lost");
        if (spec.series[0].values.length != 5 || spec.series[0].values[4] != 200) fail (label + " values wrong");
        if (spec.series[0].name != "Sales") fail (label + " name [%s]".printf (spec.series[0].name));
        var cats = spec.category_labels ();
        if (cats.length != 5 || cats[1] != "Feb") fail (label + " categories wrong");
    }
    if (spec.y2_axis.title != "Margin") fail (label + " y2 title [%s]".printf (spec.y2_axis.title));
    if (s.charts[1].kind != "doughnut") fail (label + " doughnut kind [%s]".printf (s.charts[1].kind));
    if (s.charts[2].kind != "waterfall") fail (label + " waterfall kind [%s]".printf (s.charts[2].kind));
    if (Math.fabs (ch.x - 300) > 2 || Math.fabs (ch.width - 420) > 2 || Math.fabs (ch.height - 260) > 2) fail ("%s geometry %g %g %g".printf (label, ch.x, ch.width, ch.height));
    if (s.drawings.size != 4) {
        fail ("%s drawings=%d".printf (label, s.drawings.size));
    } else {
        var img = s.drawings[0];
        if (img.kind != DrawingKind.IMAGE || img.image == null || img.image.compare (png) != 0) fail (label + " image bytes");
        if (s.drawings[1].kind != DrawingKind.ROUNDED || s.drawings[1].text != "Note box" || s.drawings[1].fill != "#ff8800") fail ("%s shape %d [%s] %s".printf (label, (int) s.drawings[1].kind, s.drawings[1].text, s.drawings[1].fill));
        if (s.drawings[2].kind != DrawingKind.ARROW) fail ("%s arrow kind %d".printf (label, (int) s.drawings[2].kind));
        if (s.drawings[3].kind != DrawingKind.TEXT_BOX || s.drawings[3].text != "Hello box") fail (label + " textbox");
    }
    if (s.sparklines.size != 1 || s.sparklines[0].items.size != 2 || s.sparklines[0].kind != SparklineKind.COLUMN || !s.sparklines[0].high) fail (label + " sparklines");
}

void test_xlsx_roundtrip () {
    LocaleInfo.set_c ();
    var png = tiny_png ();
    var book = sample (png);
    string p = tmp_path ("rt.xlsx");
    try {
        XlsxWriter.save (book, p);
        var back = Xlsx.load (p);
        check_book ("xlsx", back, png);
    } catch (Error e) {
        fail ("xlsx " + e.message);
    }
    FileUtils.remove (p);
}

void test_linked_chart () {
    LocaleInfo.set_c ();
    var book = sample (tiny_png ());
    string p = tmp_path ("link.xlsx");
    try {
        XlsxWriter.save (book, p);
        string before = ChartLookup.xml_for (p, "Data Sheet", "#0");
        if (!before.contains ("100") || before.contains ("987")) fail ("linked chart initial values");
        book.sheets[0].set_input (1, 1, "987");
        XlsxWriter.save (book, p);
        string after = ChartLookup.xml_for (p, "Data Sheet", "#0");
        if (!after.contains ("987")) fail ("linked chart did not pick up the new value");
        try {
            ChartLookup.xml_for (p, "Missing", "#0");
            fail ("linked chart missing sheet");
        } catch (Error e) {
        }
        try {
            ChartLookup.xml_for (p, "Data Sheet", "#9");
            fail ("linked chart missing chart");
        } catch (Error e) {
        }
    } catch (Error e) {
        fail ("linked chart " + e.message);
    }
    FileUtils.remove (p);
}

void test_ods_roundtrip () {
    LocaleInfo.set_c ();
    var png = tiny_png ();
    var book = sample (png);
    foreach (string ext in new string[] { "ods", "fods" }) {
        string p = tmp_path ("rt." + ext);
        try {
            var doc = new Document.with_book (book, null);
            doc.save_to (p, book.sheets[0]);
            var back = Document.open (p).book;
            check_book (ext, back, png);
        } catch (Error e) {
            fail (ext + " " + e.message);
        }
        FileUtils.remove (p);
    }
}

void test_drawingml_types () {
    foreach (string id in Chart.KINDS) {
        var book = new Workbook ();
        var s = book.add_sheet ("S");
        s.set_input (0, 0, "k");
        s.set_input (0, 1, "a");
        s.set_input (0, 2, "b");
        s.set_input (0, 3, "c");
        s.set_input (0, 4, "d");
        for (int r = 1; r <= 6; r++) {
            s.set_input (r, 0, "p%d".printf (r));
            for (int c = 1; c <= 4; c++) s.set_input (r, c, "%d".printf (r * c + c));
        }
        book.recalculate ();
        var ch = new Chart (new Area (s, 0, 0, 6, 4));
        ch.kind = id;
        var spec = ChartResolve.resolve (book, s, ch);
        bool ext;
        string xml = DrawingML.write_any (spec, out ext);
        var back = DrawingML.read_chart (xml);
        if (back == null) {
            fail ("drawingml parse " + id);
            continue;
        }
        var ch2 = new Chart (new Area (s, 0, 0, 0, 0));
        ch2.style = back;
        ch2.kind = Chart.kind_of_spec (back);
        string expect = id;
        if (id == "combo") expect = "combo";
        if (ch2.kind != expect) fail ("drawingml kind %s -> %s".printf (id, ch2.kind));
        if (back.series.size == 0 || back.series[0].values_ref == "") fail ("drawingml refs " + id);
        string odf = OdfChart.write_content (spec);
        var oback = OdfChart.read_content (odf);
        if (oback == null || oback.series.size != spec.series.size) fail ("odf " + id);
        else if (Chart.kind_of_spec (oback) != expect) fail ("odf kind %s -> %s".printf (id, Chart.kind_of_spec (oback)));
        var p = new ChartPainter ();
        var surf = p.render_image (spec, 360, 240);
        surf.flush ();
        unowned uchar[] px = surf.get_data ();
        int stride = surf.get_stride ();
        int colored = 0;
        for (int y = 0; y < 240; y += 3) {
            for (int x = 0; x < 360; x += 3) {
                int o = y * stride + x * 4;
                int b = px[o], g = px[o + 1], r = px[o + 2];
                if ((r - g).abs () > 40 || (b - g).abs () > 40) colored++;
            }
        }
        if (colored < 20) fail ("painter blank " + id);
    }
}

void test_trend_fit () {
    double[] xs = { 1, 2, 3, 4, 5 };
    double[] ys = { 2.2, 4.1, 6.3, 7.9, 10.1 };
    var f = TrendFit.fit (TrendType.LINEAR, xs, ys);
    if (!f.valid || Math.fabs (f.coeffs[1] - 1.96) > 1e-9 || Math.fabs (f.coeffs[0] - 0.24) > 1e-9) fail ("linear fit %g %g".printf (f.coeffs[0], f.coeffs[1]));
    if (Math.fabs (f.r2 - 0.998129) > 1e-5) fail ("linear r2 %g".printf (f.r2));
    double[] ye = { 2.7, 7.4, 20.1, 54.6, 148.4 };
    var e = TrendFit.fit (TrendType.EXPONENTIAL, xs, ye);
    if (!e.valid || Math.fabs (e.coeffs[1] - 1.0) > 0.01 || Math.fabs (e.coeffs[0] - 1.0) > 0.02) fail ("exp fit %g %g".printf (e.coeffs[0], e.coeffs[1]));
    double[] yp = { 1, 4, 9, 16, 25 };
    var p = TrendFit.fit (TrendType.POLYNOMIAL, xs, yp, 2);
    if (!p.valid || Math.fabs (p.coeffs[2] - 1) > 1e-9 || Math.fabs (p.r2 - 1) > 1e-12) fail ("poly fit");
    var pw = TrendFit.fit (TrendType.POWER, xs, yp);
    if (!pw.valid || Math.fabs (pw.coeffs[1] - 2) > 1e-9) fail ("power fit");
    var ma = TrendFit.moving_average (ys, 2);
    if (!ma[0].is_nan () || Math.fabs (ma[1] - 3.15) > 1e-9) fail ("moving average");
}

void test_table_model () {
    var t = new DataTable (3, 3);
    t.set_text (0, 1, "A");
    t.set_text (0, 2, "B");
    t.set_text (1, 0, "x");
    t.set_text (2, 0, "y");
    t.set_number (1, 1, 1);
    t.set_number (2, 1, 2);
    t.set_number (1, 2, 3);
    t.set_number (2, 2, 4);
    var spec = t.to_spec (null);
    if (spec.series.size != 2 || spec.series[1].name != "B" || spec.series[1].values[1] != 4 || spec.categories[1] != "y") fail ("table to_spec");
    var back = DataTable.from_spec (spec);
    if (back.get_number (2, 2) != 4 || back.get_text (0, 1) != "A") fail ("table from_spec");
}

void test_fixtures () {
    string? dir = Environment.get_variable ("CHARTS_FIXTURES");
    if (dir == null) return;
    LocaleInfo.set_c ();
    try {
        var d = Dir.open (dir);
        string? name;
        var names = new Gee.ArrayList<string> ();
        while ((name = d.read_name ()) != null) if (name.has_suffix (".xlsx") || name.has_suffix (".ods")) names.add (name);
        names.sort ();
        foreach (string n in names) {
            string p = Path.build_filename (dir, n);
            Workbook b;
            try {
                b = Document.open (p).book;
            } catch (Error e) {
                print ("%s: load error %s\n", n, e.message);
                continue;
            }
            int charts = 0, drawings = 0, sparks = 0;
            foreach (var s in b.sheets) {
                charts += s.charts.size;
                drawings += s.drawings.size;
                foreach (var g in s.sparklines) sparks += g.items.size;
                foreach (var ch in s.charts) {
                    var spec = ChartResolve.resolve (b, s, ch);
                    string first = spec.series.size > 0 ? "%s=%s [%d vals, first %g] cats=%d".printf (spec.series[0].name, spec.series[0].values_ref, spec.series[0].values.length, spec.series[0].values.length > 0 ? spec.series[0].values[0] : double.NAN, spec.category_labels ().length) : "";
                    print ("%s: chart kind=%s title=[%s] series=%d %s combo=%s sec=%s trend=%s\n", n, ch.kind, ch.title, spec.series.size, first,
                        spec.is_combo () ? "y" : "n", spec.has_secondary () ? "y" : "n", spec.series.size > 0 && spec.series[0].trendline != null ? spec.series[0].trendline.kind.to_id () : "-");
                }
                foreach (var dr in s.drawings) print ("%s: drawing %s %gx%g text=[%s]\n", n, dr.kind.to_id (), dr.width, dr.height, dr.text);
            }
            foreach (string ext in new string[] { "xlsx", "ods" }) {
                string out_p = tmp_path ("fx." + ext);
                try {
                    var doc = new Document.with_book (b, null);
                    doc.save_to (out_p, b.sheets[0]);
                    var b2 = Document.open (out_p).book;
                    int c2 = 0, d2 = 0, s2 = 0;
                    foreach (var s in b2.sheets) {
                        c2 += s.charts.size;
                        d2 += s.drawings.size;
                        foreach (var g in s.sparklines) s2 += g.items.size;
                    }
                    print ("%s: %s roundtrip charts %d->%d drawings %d->%d sparklines %d->%d%s\n", n, ext, charts, c2, drawings, d2, sparks, s2, (charts == c2 && drawings == d2 && sparks == s2) ? " OK" : " MISMATCH");
                    if (charts != c2 || drawings != d2 || sparks != s2) fail (n + " fixture roundtrip");
                } catch (Error e) {
                    fail ("%s: %s save error %s".printf (n, ext, e.message));
                }
                if (Environment.get_variable ("CHARTS_KEEP") != null) print ("kept %s\n", out_p);
                else FileUtils.remove (out_p);
            }
        }
    } catch (Error e) {
        print ("fixtures: %s\n", e.message);
    }
}

Bytes demo_png () {
    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 320, 200);
    var cr = new Cairo.Context (surf);
    var grad = new Cairo.Pattern.linear (0, 0, 320, 200);
    grad.add_color_stop_rgb (0, 0.16, 0.47, 0.84);
    grad.add_color_stop_rgb (1, 0.11, 0.69, 0.48);
    cr.set_source (grad);
    cr.paint ();
    cr.set_source_rgba (1, 1, 1, 0.85);
    cr.arc (230, 70, 34, 0, 2 * Math.PI);
    cr.fill ();
    cr.move_to (0, 200);
    cr.line_to (110, 90);
    cr.line_to (190, 160);
    cr.line_to (250, 120);
    cr.line_to (320, 200);
    cr.close_path ();
    cr.set_source_rgba (0.05, 0.2, 0.3, 0.8);
    cr.fill ();
    string p = tmp_path ("demo.png");
    surf.write_to_png (p);
    uint8[] data;
    try {
        FileUtils.get_data (p, out data);
    } catch (Error e) {
        data = {};
    }
    FileUtils.remove (p);
    return new Bytes (data);
}

void write_demo (string path) {
    var book = new Workbook ();
    var s = book.add_sheet ("Combo");
    string[] months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug" };
    double[] sales = { 120, 135, 128, 160, 172, 169, 190, 214 };
    double[] margin = { 0.12, 0.14, 0.13, 0.17, 0.18, 0.16, 0.21, 0.23 };
    s.set_input (0, 0, "Month");
    s.set_input (0, 1, "Sales");
    s.set_input (0, 2, "Margin");
    for (int i = 0; i < months.length; i++) {
        s.set_input (i + 1, 0, months[i]);
        s.set_input (i + 1, 1, Singularity.Apps.Spreadsheet.Value.format_number_general_full (sales[i]));
        s.set_input (i + 1, 2, Singularity.Apps.Spreadsheet.Value.format_number_general_full (margin[i]));
    }
    var ch = new Chart (new Area (s, 0, 0, 8, 2));
    ch.kind = "combo";
    ch.title = "Sales and margin";
    ch.x = 290;
    ch.y = 10;
    ch.width = 620;
    ch.height = 380;
    var s0 = new Series ();
    s0.trendline = new Trendline ();
    s0.trendline.kind = TrendType.LINEAR;
    s0.trendline.show_equation = true;
    s0.trendline.show_r2 = true;
    var s1 = new Series ();
    s1.has_type = true;
    s1.kind = ChartType.LINE;
    s1.secondary = true;
    ch.style.series.add (s0);
    ch.style.series.add (s1);
    ch.style.y_axis.title = "Sales";
    ch.style.y2_axis.title = "Margin";
    ch.style.y2_axis.number_format = "0%";
    ch.style.legend = LegendPosition.BOTTOM;
    s.charts.add (ch);
    var t = book.add_sheet ("Types");
    string[] cats = { "North", "South", "East", "West", "Central", "Online" };
    t.set_input (0, 0, "Region");
    t.set_input (0, 1, "Q1");
    t.set_input (0, 2, "Q2");
    t.set_input (0, 3, "Q3");
    double[,] vals = { { 42, 38, 51 }, { 30, 44, 36 }, { -12, 25, 31 }, { 27, 19, 22 }, { 18, 35, 29 }, { 55, 61, 70 } };
    for (int i = 0; i < cats.length; i++) {
        t.set_input (i + 1, 0, cats[i]);
        for (int j = 0; j < 3; j++) t.set_input (i + 1, j + 1, Singularity.Apps.Spreadsheet.Value.format_number_general_full (vals[i, j]));
    }
    string[] kinds = { "waterfall", "treemap", "radar-filled", "funnel", "box", "histogram", "bubble", "doughnut", "area-stacked" };
    for (int k = 0; k < kinds.length; k++) {
        var c = new Chart (new Area (t, 0, 0, 6, kinds[k] == "waterfall" || kinds[k] == "treemap" || kinds[k] == "funnel" || kinds[k] == "doughnut" ? 1 : 3));
        c.kind = kinds[k];
        c.title = Chart.kind_label (kinds[k]);
        c.x = 380 + (k % 3) * 330;
        c.y = 10 + (k / 3) * 250;
        c.width = 320;
        c.height = 240;
        t.charts.add (c);
    }
    var o = book.add_sheet ("Objects");
    o.set_input (0, 0, "Product");
    string[] prods = { "Alpha", "Beta", "Gamma", "Delta" };
    for (int i = 0; i < 6; i++) o.set_input (0, i + 1, "W%d".printf (i + 1));
    o.set_input (0, 7, "Trend");
    double[,] pv = { { 5, 7, 6, 9, 11, 13 }, { 9, 8, 6, 5, 4, 3 }, { 2, -1, 3, -2, 4, 5 }, { 4, 4, 6, 5, 8, 7 } };
    for (int i = 0; i < prods.length; i++) {
        o.set_input (i + 1, 0, prods[i]);
        for (int j = 0; j < 6; j++) o.set_input (i + 1, j + 1, Singularity.Apps.Spreadsheet.Value.format_number_general_full (pv[i, j]));
    }
    o.col_widths[7] = 150;
    var g = new SparklineGroup ();
    g.markers = true;
    g.high = true;
    g.low = true;
    for (int i = 0; i < 2; i++) g.items.add (new Sparkline (i + 1, 7, "Objects!B%d:G%d".printf (i + 2, i + 2)));
    o.sparklines.add (g);
    var g2 = new SparklineGroup ();
    g2.kind = SparklineKind.WIN_LOSS;
    g2.items.add (new Sparkline (3, 7, "Objects!B4:G4"));
    o.sparklines.add (g2);
    var g3 = new SparklineGroup ();
    g3.kind = SparklineKind.COLUMN;
    g3.high = true;
    g3.items.add (new Sparkline (4, 7, "Objects!B5:G5"));
    o.sparklines.add (g3);
    var img = new Drawing (DrawingKind.IMAGE);
    img.image = demo_png ();
    img.x = 20;
    img.y = 170;
    img.width = 320;
    img.height = 200;
    img.name = "Landscape";
    o.drawings.add (img);
    var r = new Drawing (DrawingKind.ROUNDED);
    r.text = "Quarterly review";
    r.x = 380;
    r.y = 170;
    r.width = 220;
    r.height = 90;
    o.drawings.add (r);
    var e = new Drawing (DrawingKind.ELLIPSE);
    e.fill = "#1baf7a";
    e.stroke = "#137a55";
    e.text = "Goal";
    e.x = 650;
    e.y = 170;
    e.width = 140;
    e.height = 90;
    o.drawings.add (e);
    var a = new Drawing (DrawingKind.ARROW);
    a.stroke = "#eb6834";
    a.stroke_width = 3;
    a.x = 600;
    a.y = 215;
    a.width = 50;
    a.height = 0;
    o.drawings.add (a);
    var tb = new Drawing (DrawingKind.TEXT_BOX);
    tb.text = "Notes: figures are provisional\nand rounded to the nearest unit.";
    tb.x = 380;
    tb.y = 290;
    tb.width = 300;
    tb.height = 80;
    o.drawings.add (tb);
    var pics = book.add_sheet ("Pictures");
    string uri = "data:image/png;base64," + Base64.encode (demo_png ().get_data ());
    pics.set_input (0, 0, "Sizing");
    pics.set_input (0, 1, "Picture");
    pics.set_input (1, 0, "0 fit");
    pics.set_input (2, 0, "1 fill");
    pics.set_input (3, 0, "2 original");
    pics.set_input (4, 0, "3 custom");
    pics.set_input (1, 1, "=IMAGE(\"" + uri + "\",\"Landscape\",0)");
    pics.set_input (2, 1, "=IMAGE(\"" + uri + "\",\"Landscape\",1)");
    pics.set_input (3, 1, "=IMAGE(\"" + uri + "\",\"Landscape\",2)");
    pics.set_input (4, 1, "=IMAGE(\"" + uri + "\",\"Landscape\",3,40,90)");
    pics.col_widths[1] = 360;
    for (int pr = 1; pr <= 4; pr++) pics.row_heights[pr] = pr == 3 ? 210 : 90;
    var dg = book.add_sheet ("Diagrams");
    string[] dk = { "process", "cycle", "hierarchy", "pyramid", "venn", "list" };
    string[,] items = { { "Plan", "Build", "Test", "Launch" }, { "Plan", "Do", "Check", "Act" }, { "Director", "Sales", "Finance", "Support" }, { "Vision", "Strategy", "Tactics", "Tasks" }, { "Design", "Code", "Users", "" }, { "Research", "Prototype", "Review", "Ship" } };
    for (int k = 0; k < dk.length; k++) {
        string[] its = {};
        for (int j = 0; j < 4; j++) if (items[k, j] != "") its += items[k, j];
        var dgr = Diagrams.build (dk[k], its, 380, 220);
        dgr.x = 20 + (k % 3) * 410;
        dgr.y = 20 + (k / 3) * 250;
        dgr.alt_text = Diagrams.label (dk[k]);
        dg.drawings.add (dgr);
    }
    book.recalculate ();
    string[] names = { "Combo", "Types", "Objects", "Pictures", "Diagrams" };
    foreach (string n in names) {
        var first = book.find_sheet (n);
        book.sheets.remove (first);
        book.sheets.insert (0, first);
        try {
            new Document.with_book (book, null).save_to (Path.build_filename (path, n.down () + ".xlsx"), first);
        } catch (Error err) {
            stderr.printf ("demo: %s\n", err.message);
        }
    }
}

void test_image_function () {
    LocaleInfo.set_c ();
    ImageCache.get_default ().network = false;
    var png = tiny_png ();
    string uri = "data:image/png;base64," + Base64.encode (png.get_data ());
    string file = tmp_path ("cellimg.png");
    try {
        FileUtils.set_data (file, png.get_data ());
    } catch (Error e) {
        fail ("write png");
    }
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    s.set_input (0, 0, uri);
    s.set_input (0, 1, "=IMAGE(A1,\"Logo\",1)");
    s.set_input (1, 1, "=IMAGE(\"" + File.new_for_path (file).get_uri () + "\")");
    s.set_input (2, 1, "=IMAGE(A1,,5)");
    s.set_input (3, 1, "=IMAGE(\"https://example.invalid/x.png\")");
    s.set_input (4, 1, "=LEN(B1)");
    s.set_input (5, 1, "=IMAGE(A1,\"x\",3,20,30)");
    book.recalculate ();
    var v = s.value_at (0, 1);
    if (v.image == null || v.image.compare (png) != 0 || v.display () != "Logo" || v.image_sizing != 1) fail ("IMAGE data uri");
    if (s.value_at (1, 1).image == null) fail ("IMAGE file uri");
    if (s.value_at (2, 1).display () != "#VALUE!") fail ("IMAGE bad sizing");
    if (s.value_at (3, 1).display () != "#VALUE!") fail ("IMAGE offline network");
    if (s.value_at (4, 1).display () != "4") fail ("IMAGE as text");
    var c = s.value_at (5, 1);
    if (c.image == null || c.image_height != 20 || c.image_width != 30) fail ("IMAGE custom size");
    string p = tmp_path ("img.xlsx");
    try {
        XlsxWriter.save (book, p);
        var back = Xlsx.load (p);
        var bs = back.sheets[0];
        if (!bs.input_at (0, 1).has_prefix ("=IMAGE(")) fail ("IMAGE formula lost [%s]".printf (bs.input_at (0, 1)));
        if (bs.value_at (0, 1).image == null) fail ("IMAGE not recomputed after load");
    } catch (Error e) {
        fail ("IMAGE xlsx " + e.message);
    }
    FileUtils.remove (p);
    FileUtils.remove (file);
}

Workbook alt_book () {
    var book = new Workbook ();
    var s = book.add_sheet ("A");
    s.set_input (0, 0, "k");
    s.set_input (0, 1, "v");
    s.set_input (1, 0, "a");
    s.set_input (1, 1, "3");
    s.set_input (2, 0, "b");
    s.set_input (2, 1, "5");
    var ch = new Chart (new Area (s, 0, 0, 2, 1));
    ch.alt_text = "Chart of values";
    s.charts.add (ch);
    var img = new Drawing (DrawingKind.IMAGE);
    img.image = tiny_png ();
    img.alt_text = "Company logo";
    s.drawings.add (img);
    int k = 0;
    foreach (string kind in Diagrams.KINDS) {
        var g = Diagrams.build (kind, { "One", "Two", "Three" });
        g.x = 20 + k * 30;
        g.y = 200 + k * 40;
        g.alt_text = "Diagram " + kind;
        s.drawings.add (g);
        k++;
    }
    book.recalculate ();
    return book;
}

void check_alt (string label, Workbook b) {
    var s = b.sheets[0];
    if (s.charts.size != 1 || s.charts[0].alt_text != "Chart of values") fail (label + " chart alt");
    if (s.drawings.size != 1 + Diagrams.KINDS.length) {
        fail ("%s drawings %d".printf (label, s.drawings.size));
        return;
    }
    if (s.drawings[0].alt_text != "Company logo") fail (label + " image alt [%s]".printf (s.drawings[0].alt_text));
    for (int i = 0; i < Diagrams.KINDS.length; i++) {
        var g = s.drawings[i + 1];
        string kind = Diagrams.KINDS[i];
        var ref_g = Diagrams.build (kind, { "One", "Two", "Three" });
        if (g.kind != DrawingKind.GROUP) {
            fail ("%s %s not a group".printf (label, kind));
            continue;
        }
        if (g.diagram != kind) fail ("%s %s kind [%s]".printf (label, kind, g.diagram));
        if (g.alt_text != "Diagram " + kind) fail ("%s %s alt".printf (label, kind));
        if (g.children.size != ref_g.children.size) fail ("%s %s children %d/%d".printf (label, kind, g.children.size, ref_g.children.size));
        var items = Diagrams.items_of (g);
        if (items.length != 3 || items[2] != "Three") fail ("%s %s items".printf (label, kind));
        if (label == "xlsx" && (Math.fabs (g.width - ref_g.width) > 3 || Math.fabs (g.height - ref_g.height) > 3)) fail ("%s %s size %g %g".printf (label, kind, g.width, g.height));
        double ox = 20 + i * 30, oy = 200 + i * 40;
        for (int j = 0; j < g.children.size && j < ref_g.children.size; j++) {
            var a = g.children[j];
            var r = ref_g.children[j];
            double fx = g.frame_w > 0 ? g.width / g.frame_w : 1;
            double fy = g.frame_h > 0 ? g.height / g.frame_h : 1;
            double ax = g.x + a.x * fx, ay = g.y + a.y * fy;
            if (Math.fabs (ax - (ox + r.x)) > 3 || Math.fabs (ay - (oy + r.y)) > 3 || Math.fabs (a.width * fx - r.width) > 3 || Math.fabs (a.height * fy - r.height) > 3) fail ("%s %s child %d geometry %g/%g %g/%g".printf (label, kind, j, ax, ox + r.x, ay, oy + r.y));
            if (kind == "venn" && Math.fabs (a.opacity - r.opacity) > 0.02) fail ("%s venn opacity %g".printf (label, a.opacity));
        }
    }
}

void test_alt_and_diagrams () {
    LocaleInfo.set_c ();
    foreach (string ext in new string[] { "xlsx", "ods", "fods" }) {
        var book = alt_book ();
        string p = tmp_path ("alt." + ext);
        try {
            new Document.with_book (book, null).save_to (p, book.sheets[0]);
            check_alt (ext, Document.open (p).book);
        } catch (Error e) {
            fail (ext + " " + e.message);
        }
        if (Environment.get_variable ("CHARTS_KEEP") != null) print ("kept %s\n", p);
        else FileUtils.remove (p);
    }
    var g = Diagrams.build ("process", { "a", "b" });
    var r = Diagrams.rebuild (g, "cycle", { "x", "y", "z" });
    if (r.diagram != "cycle" || Diagrams.items_of (r).length != 3) fail ("diagram rebuild");
    var copy = r.copy ();
    copy.children[0].text = "changed";
    if (r.children[0].text == "changed") fail ("group copy is shallow");
}

class FakeServer : Object {
    public uint16 port;
    public Bytes png;
    public int hits_png;
    public int hits_text;
    public int hits_slow;
    public int hits_missing;
    private ThreadedSocketService service;

    public FakeServer (Bytes png) {
        this.png = png;
        service = new ThreadedSocketService (4);
        try {
            port = service.add_any_inet_port (null);
        } catch (Error e) {
            port = 0;
        }
        service.run.connect ((conn) => {
            handle (conn);
            return true;
        });
        service.start ();
    }

    private void handle (SocketConnection conn) {
        try {
            var input = new DataInputStream (conn.input_stream);
            string? line = input.read_line (null);
            if (line == null) return;
            string[] parts = line.split (" ");
            string path = parts.length > 1 ? parts[1] : "/";
            string? h;
            while ((h = input.read_line (null)) != null && h.strip () != "") {
            }
            int status = 200;
            string type = "text/plain";
            Bytes body;
            switch (path) {
                case "/img.png":
                    AtomicInt.inc (ref hits_png);
                    type = "image/png";
                    body = png;
                    break;
                case "/text":
                    AtomicInt.inc (ref hits_text);
                    body = new Bytes ("hello world".data);
                    break;
                case "/slow":
                    AtomicInt.inc (ref hits_slow);
                    Thread.usleep (1500000);
                    body = new Bytes ("late answer".data);
                    break;
                default:
                    AtomicInt.inc (ref hits_missing);
                    status = 404;
                    body = new Bytes ("missing".data);
                    break;
            }
            string head = "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n".printf (status, status == 200 ? "OK" : "Not Found", type, body.length);
            conn.output_stream.write_all (head.data, null);
            conn.output_stream.write_all (body.get_data (), null);
            conn.close (null);
        } catch (Error e) {
        }
    }

    public void stop () {
        service.stop ();
        service.close ();
    }
}

bool pump_until (owned SourceFunc cond, int ms) {
    int64 end = get_monotonic_time () + ms * 1000;
    while (get_monotonic_time () < end) {
        if (cond ()) return true;
        MainContext.default ().iteration (false);
        Thread.usleep (2000);
    }
    return cond ();
}

void test_network_fetch () {
    LocaleInfo.set_c ();
    var png = tiny_png ();
    var server = new FakeServer (png);
    if (server.port == 0) {
        fail ("fake server port");
        return;
    }
    var cache = ImageCache.get_default ();
    cache.network = true;
    string base_url = "http://127.0.0.1:%u".printf (server.port);
    var book = new Workbook ();
    var s = book.add_sheet ("Net");
    int loads = 0;
    ulong hid = cache.loaded.connect ((src) => {
        loads++;
        book.recalculate ();
    });
    s.set_input (0, 0, "=IMAGE(\"" + base_url + "/img.png\",\"Remote\")");
    s.set_input (0, 1, "=LEN(A1)");
    s.set_input (1, 0, "=WEBSERVICE(\"" + base_url + "/text\")");
    s.set_input (1, 1, "=UPPER(A2)");
    s.set_input (2, 0, "=IMAGE(\"" + base_url + "/missing.png\")");
    s.set_input (3, 0, "=WEBSERVICE(\"" + base_url + "/nothing\")");
    s.set_input (4, 0, "=WEBSERVICE(\"" + base_url + "/slow\")");
    book.recalculate ();
    string[] pending = { "A1", "A2", "A3", "A4", "A5" };
    int[] rows = { 0, 1, 2, 3, 4 };
    for (int i = 0; i < rows.length; i++) {
        if (s.value_at (rows[i], 0).display () != "#GETTING_DATA") fail ("%s not pending: %s".printf (pending[i], s.value_at (rows[i], 0).display ()));
    }
    if (!pump_until (() => s.value_at (1, 0).display () == "hello world" && s.value_at (0, 0).image != null && s.value_at (2, 0).display () == "#VALUE!" && s.value_at (3, 0).display () == "#VALUE!", 5000)) {
        fail ("fast fetches did not complete: %s %s %s".printf (s.value_at (1, 0).display (), s.value_at (2, 0).display (), s.value_at (3, 0).display ()));
    }
    if (s.value_at (4, 0).display () != "#GETTING_DATA") fail ("slow response not pending while fast ones done");
    var img = s.value_at (0, 0);
    if (img.image == null || img.image.compare (png) != 0 || img.display () != "Remote") fail ("remote image bytes");
    if (s.value_at (0, 1).display () != "6") fail ("dependent of IMAGE not recalculated");
    if (s.value_at (1, 1).display () != "HELLO WORLD") fail ("dependent of WEBSERVICE not recalculated");
    if (!pump_until (() => s.value_at (4, 0).display () == "late answer", 5000)) fail ("slow fetch did not complete: %s".printf (s.value_at (4, 0).display ()));
    int png_hits = server.hits_png, text_hits = server.hits_text, req = cache.requests;
    s.set_input (5, 0, "=IMAGE(\"" + base_url + "/img.png\")");
    s.set_input (6, 0, "=WEBSERVICE(\"" + base_url + "/text\")");
    book.recalculate ();
    if (s.value_at (5, 0).image == null || s.value_at (6, 0).display () != "hello world") fail ("cache hit did not answer immediately");
    if (server.hits_png != png_hits || server.hits_text != text_hits || cache.requests != req) fail ("cache hit went to the network");
    if (server.hits_png != 1 || server.hits_text != 1 || server.hits_slow != 1 || server.hits_missing != 2) fail ("request counts %d %d %d %d".printf (server.hits_png, server.hits_text, server.hits_slow, server.hits_missing));
    if (loads != 5) fail ("loaded signals %d".printf (loads));
    cache.disconnect (hid);
    cache.network = false;
    server.stop ();
}

int main (string[] args) {
    string? net = Environment.get_variable ("CHARTS_NETDEMO");
    if (net != null) {
        LocaleInfo.set_c ();
        string[] parts = net.split ("|");
        var nb = new Workbook ();
        var ns = nb.add_sheet ("Network");
        ns.set_input (0, 0, "Source");
        ns.set_input (0, 1, "Picture");
        ns.set_input (0, 2, "Length");
        ns.set_input (1, 0, parts[1] + "/landscape.png");
        ns.set_input (1, 1, "=IMAGE(A2,\"Landscape from the local server\",0)");
        ns.set_input (1, 2, "=LEN(B2)");
        ns.set_input (2, 0, parts[1] + "/missing.png");
        ns.set_input (2, 1, "=IMAGE(A3)");
        ns.set_input (3, 0, parts[1] + "/hello.txt");
        ns.set_input (3, 1, "=WEBSERVICE(A4)");
        ns.set_input (3, 2, "=LEN(B4)");
        ns.col_widths[0] = 300;
        ns.col_widths[1] = 320;
        ns.row_heights[1] = 200;
        try {
            new Document.with_book (nb, null).save_to (parts[0], ns);
        } catch (Error e) {
            return 1;
        }
        return 0;
    }
    string? demo = Environment.get_variable ("CHARTS_DEMO");
    if (demo != null) {
        LocaleInfo.set_c ();
        write_demo (demo);
        return 0;
    }
    Test.init (ref args);
    Test.add_func ("/charts/trend", test_trend_fit);
    Test.add_func ("/charts/table", test_table_model);
    Test.add_func ("/charts/types", test_drawingml_types);
    Test.add_func ("/charts/xlsx", test_xlsx_roundtrip);
    Test.add_func ("/charts/ods", test_ods_roundtrip);
    Test.add_func ("/charts/linked", test_linked_chart);
    Test.add_func ("/charts/fixtures", test_fixtures);
    Test.add_func ("/charts/image-function", test_image_function);
    Test.add_func ("/charts/alt-diagrams", test_alt_and_diagrams);
    Test.add_func ("/charts/network-fetch", test_network_fetch);
    int rc = Test.run ();
    if (failures > 0) {
        stderr.printf ("%d failures\n", failures);
        return 1;
    }
    return rc;
}
