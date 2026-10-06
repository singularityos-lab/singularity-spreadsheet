using Singularity.Apps.Spreadsheet;

Workbook book;
Sheet sh;
int failures = 0;

void put (string addr, string input) {
    int r, c;
    bool a, b;
    Address.parse_cell (addr, out r, out c, out a, out b);
    sh.set_input (r, c, input);
}

void column (string col, int start, string[] values) {
    for (int i = 0; i < values.length; i++) put (col + (start + i).to_string (), values[i]);
}

string at (string addr) {
    int r, c;
    bool a, b;
    Address.parse_cell (addr, out r, out c, out a, out b);
    return sh.value_at (r, c).display ();
}

bool close_enough (string got, string expected) {
    if (got == expected) return true;
    double g = 0, e = 0;
    string f;
    if (!Input.parse_number (got, out g, out f) || !Input.parse_number (expected, out e, out f)) return false;
    int dot = expected.index_of (".");
    int decimals = dot < 0 ? 0 : expected.length - dot - 1;
    double tol = 0.5 * Math.pow (10, -decimals) + 1e-12;
    if (expected.contains ("E")) tol = Math.fabs (e) * 1e-6;
    return Math.fabs (g - e) <= tol * 1.0000001;
}

void check_cell (string addr, string expected, string what) {
    string got = at (addr);
    if (!close_enough (got, expected)) {
        stderr.printf ("FAIL %s at %s: expected [%s] got [%s]\n", what, addr, expected, got);
        failures++;
    }
}

void check (string formula, string expected) {
    put ("Z1", formula);
    book.recalculate ();
    check_cell ("Z1", expected, formula);
}

void spill (string formula, string[] cells, string[] expected) {
    put ("Z1", formula);
    book.recalculate ();
    for (int i = 0; i < cells.length; i++) check_cell (cells[i], expected[i], formula);
    put ("Z1", "");
    book.recalculate ();
}

void fresh () {
    book = new Workbook ();
    sh = book.add_sheet ("Sheet1");
}

void finish () {
    if (failures > 0) {
        Test.message ("%d failures", failures);
        failures = 0;
        Test.fail ();
    }
}

void test_distributions () {
    fresh ();
    check ("=T.DIST(60,1,TRUE)", "0.99469533");
    check ("=T.DIST(8,3,FALSE)", "0.00073691");
    check ("=T.DIST.2T(1.959999998,60)", "0.054644930");
    check ("=T.DIST.RT(1.959999998,60)", "0.027322465");
    check ("=TDIST(1.959999998,60,2)", "0.054644930");
    check ("=TDIST(1.959999998,60,1)", "0.027322465");
    check ("=T.INV(0.75,2)", "0.8164966");
    check ("=T.INV.2T(0.546449,60)", "0.606533");
    check ("=TINV(0.546449,60)", "0.606533");
    check ("=CHISQ.DIST(0.5,1,TRUE)", "0.52049988");
    check ("=CHISQ.DIST(2,3,FALSE)", "0.20755375");
    check ("=CHISQ.DIST.RT(18.307,10)", "0.0500006");
    check ("=CHIDIST(18.307,10)", "0.0500006");
    check ("=CHISQ.INV(0.93,1)", "3.283020287");
    check ("=CHISQ.INV(0.6,2)", "1.832581464");
    check ("=CHISQ.INV.RT(0.050001,10)", "18.30697346");
    check ("=CHIINV(0.050001,10)", "18.30697346");
    check ("=F.DIST(15.2069,6,4,TRUE)", "0.99");
    check ("=F.DIST(15.2069,6,4,FALSE)", "0.0012238");
    check ("=F.DIST.RT(15.2068649,6,4)", "0.01");
    check ("=FDIST(15.2068649,6,4)", "0.01");
    check ("=F.INV(0.01,6,4)", "0.10930991");
    check ("=F.INV.RT(0.01,6,4)", "15.20686");
    check ("=FINV(0.01,6,4)", "15.20686");
    check ("=GAMMA(2.5)", "1.329");
    check ("=GAMMA(-3.75)", "0.268");
    check ("=GAMMA(0)", "#NUM!");
    check ("=GAMMALN(4)", "1.7917595");
    check ("=GAMMALN.PRECISE(4)", "1.7917595");
    check ("=GAMMA.DIST(10.00001131,9,2,FALSE)", "0.032639");
    check ("=GAMMA.DIST(10.00001131,9,2,TRUE)", "0.068094");
    check ("=GAMMA.INV(0.068094,9,2)", "10.0000112");
    check ("=BETA.DIST(2,8,10,TRUE,1,3)", "0.6854706");
    check ("=BETA.DIST(2,8,10,FALSE,1,3)", "1.4837646");
    check ("=BETADIST(2,8,10,1,3)", "0.6854706");
    check ("=BETA.INV(0.685470581,8,10,1,3)", "2");
    check ("=LOGNORM.DIST(4,3.5,1.2,TRUE)", "0.0390836");
    check ("=LOGNORM.DIST(4,3.5,1.2,FALSE)", "0.0176176");
    check ("=LOGNORMDIST(4,3.5,1.2)", "0.0390836");
    check ("=LOGNORM.INV(0.039084,3.5,1.2)", "4.0000252");
    check ("=WEIBULL.DIST(105,20,100,TRUE)", "0.929581");
    check ("=WEIBULL.DIST(105,20,100,FALSE)", "0.035589");
    check ("=HYPGEOM.DIST(1,4,8,20,TRUE)", "0.4654");
    check ("=HYPGEOM.DIST(1,4,8,20,FALSE)", "0.3633");
    check ("=HYPGEOMDIST(1,4,8,20)", "0.3633");
    check ("=NEGBINOM.DIST(10,5,0.25,TRUE)", "0.3135141");
    check ("=NEGBINOM.DIST(10,5,0.25,FALSE)", "0.0550487");
    check ("=BINOM.DIST.RANGE(60,0.75,48)", "0.084");
    check ("=BINOM.DIST.RANGE(60,0.75,45,50)", "0.524");
    check ("=BINOM.INV(6,0.5,0.75)", "4");
    check ("=CRITBINOM(6,0.5,0.75)", "4");
    check ("=PHI(0.75)", "0.301137432");
    check ("=GAUSS(2)", "0.47725");
    check ("=CONFIDENCE.T(0.05,1,50)", "0.284196855");
    check ("=NORM.S.DIST(1.333333,TRUE)", "0.908788726");
    check ("=FISHER(0.75)", "0.9729551");
    check ("=FISHERINV(0.972955)", "0.75");
    check ("=PERMUTATIONA(3,2)", "9");
    check ("=PERMUTATIONA(2,2)", "4");
    finish ();
}

void test_descriptive () {
    fresh ();
    column ("A", 1, { "3", "4", "5", "2", "3", "4", "5", "6", "4", "7" });
    check ("=KURT(A1:A10)", "-0.151799637");
    check ("=SKEW(A1:A10)", "0.359543071");
    check ("=SKEW.P(A1:A10)", "0.303193");
    column ("B", 1, { "4", "5", "6", "7", "2", "3", "4", "5", "1", "2", "3" });
    check ("=TRIMMEAN(B1:B11,0.2)", "3.777777778");
    column ("C", 1, { "1", "2", "3", "6", "6", "6", "7", "8", "9" });
    check ("=PERCENTRANK.EXC(C1:C9,7)", "0.7");
    check ("=PERCENTRANK.EXC(C1:C9,5.43)", "0.381");
    check ("=PERCENTRANK.EXC(C1:C9,5.43,1)", "0.3");
    column ("D", 1, { "1", "2", "3", "4", "3", "2", "1", "2", "3", "5", "6", "1" });
    spill ("=MODE.MULT(D1:D12)", { "Z1", "Z2", "Z3", "Z4" }, { "1", "2", "3", "" });
    column ("E", 1, { "79", "85", "78", "85", "50", "81", "95", "88", "97" });
    column ("F", 1, { "70", "79", "89" });
    spill ("=FREQUENCY(E1:E9,F1:F3)", { "Z1", "Z2", "Z3", "Z4" }, { "1", "2", "4", "2" });
    column ("G", 1, { "0", "1", "2", "3" });
    column ("H", 1, { "0.2", "0.3", "0.1", "0.4" });
    check ("=PROB(G1:G4,H1:H4,2)", "0.1");
    check ("=PROB(G1:G4,H1:H4,1,3)", "0.8");
    column ("I", 1, { "1", "TRUE", "2" });
    check ("=VARA(I1:I3)", "0.333333333");
    check ("=VARPA(I1:I3)", "0.222222222");
    check ("=STDEVPA(I1:I3)", "0.471404521");
    finish ();
}

void test_tests () {
    fresh ();
    column ("A", 1, { "3", "4", "5", "8", "9", "1", "2", "4", "5" });
    column ("B", 1, { "6", "19", "3", "2", "14", "4", "5", "17", "1" });
    check ("=T.TEST(A1:A9,B1:B9,2,1)", "0.196016");
    check ("=TTEST(A1:A9,B1:B9,2,1)", "0.196016");
    column ("C", 1, { "6", "7", "9", "15", "21" });
    column ("D", 1, { "20", "28", "31", "38", "40" });
    check ("=F.TEST(C1:C5,D1:D5)", "0.64831785");
    column ("E", 1, { "3", "6", "7", "8", "6", "5", "4", "2", "1", "9" });
    check ("=Z.TEST(E1:E10,4)", "0.090574");
    check ("=Z.TEST(E1:E10,6)", "0.863043");
    put ("F1", "58");
    put ("G1", "35");
    put ("F2", "11");
    put ("G2", "25");
    put ("F3", "10");
    put ("G3", "23");
    put ("H1", "45.35");
    put ("I1", "47.65");
    put ("H2", "17.56");
    put ("I2", "18.44");
    put ("H3", "16.09");
    put ("I3", "16.91");
    check ("=CHISQ.TEST(F1:G3,H1:I3)", "0.0003082");
    finish ();
}

void test_regression () {
    fresh ();
    column ("A", 1, { "1", "9", "5", "7" });
    column ("B", 1, { "0", "4", "2", "3" });
    spill ("=LINEST(A1:A4,B1:B4)", { "Z1", "AA1" }, { "2", "1" });
    column ("C", 1, { "11", "12", "13", "14", "15", "16" });
    column ("D", 1, { "33100", "47300", "69000", "102000", "150000", "220000" });
    spill ("=LOGEST(D1:D6,C1:C6)", { "Z1", "AA1" }, { "1.463275628", "495.3047702" });
    spill ("=GROWTH(D1:D6,C1:C6,{17;18})", { "Z1", "Z2" }, { "320196.72", "468536.05" });
    spill ("=TREND(A1:A4,B1:B4,{5;6})", { "Z1", "Z2" }, { "11", "13" });
    column ("E", 1, { "2310", "2333", "2356", "2379", "2402", "2425", "2448", "2471", "2494", "2517", "2540" });
    column ("F", 1, { "2", "2", "3", "3", "2", "4", "2", "2", "3", "4", "2" });
    column ("G", 1, { "2", "2", "1.5", "2", "3", "2", "1.5", "2", "3", "4", "3" });
    column ("H", 1, { "20", "12", "33", "43", "53", "23", "99", "34", "23", "55", "22" });
    column ("I", 1, { "142000", "144000", "151000", "150000", "139000", "169000", "126000", "142900", "163000", "169000", "149000" });
    spill ("=LINEST(I1:I11,E1:H11,TRUE,TRUE)", { "Z1", "AA1", "AB1", "AC1", "AD1", "Z3", "AA3", "Z4", "AA4" }, { "-234.2371645", "2553.21066", "12529.76817", "27.64138737", "52317.83051", "0.996747993", "970.5784629", "459.7536742", "6" });
    column ("J", 1, { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12" });
    column ("K", 1, { "10", "20", "30", "40", "50", "60", "70", "80", "90", "100", "110", "120" });
    check ("=FORECAST.ETS(13,K1:K12,J1:J12)", "130");
    check ("=FORECAST.ETS.STAT(K1:K12,J1:J12,8)", "1");
    column ("L", 1, { "5", "9", "5", "1", "5", "9", "5", "1", "5", "9", "5", "1", "5", "9", "5", "1" });
    column ("M", 1, { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16" });
    check ("=FORECAST.ETS.SEASONALITY(L1:L16,M1:M16)", "4");
    check ("=FORECAST.ETS(18,L1:L16,M1:M16,4)", "9");
    finish ();
}

void test_matrix () {
    fresh ();
    spill ("=MMULT({1,3;7,2},{2,0;0,2})", { "Z1", "AA1", "Z2", "AA2" }, { "2", "6", "14", "4" });
    spill ("=MINVERSE({4,-1;2,0})", { "Z1", "AA1", "Z2", "AA2" }, { "0", "0.5", "-1", "2" });
    check ("=MDETERM({1,3,8,5;1,3,6,1;1,1,1,0;7,3,10,2})", "88");
    check ("=MDETERM({3,6,1;1,1,0;3,10,2})", "1");
    check ("=MINVERSE({1,2;2,4})", "#NUM!");
    spill ("=MUNIT(3)", { "Z1", "AA2", "AB3", "AA1" }, { "1", "1", "1", "0" });
    check ("=MMULT({1,2},{3,4})", "#VALUE!");
    finish ();
}

void test_text () {
    fresh ();
    check ("=REGEXTEST(\"alpha-123\",\"[0-9]+\")", "TRUE");
    check ("=REGEXTEST(\"ABC\",\"abc\")", "FALSE");
    check ("=REGEXTEST(\"ABC\",\"abc\",1)", "TRUE");
    check ("=REGEXEXTRACT(\"DylanWilliams\",\"[A-Z][a-z]+\")", "Dylan");
    spill ("=REGEXEXTRACT(\"DylanWilliams\",\"[A-Z][a-z]+\",1)", { "Z1", "Z2" }, { "Dylan", "Williams" });
    spill ("=REGEXEXTRACT(\"Tel 555-1234\",\"(\\d+)-(\\d+)\",2)", { "Z1", "AA1" }, { "555", "1234" });
    check ("=REGEXREPLACE(\"555-1234\",\"[0-9]\",\"X\")", "XXX-XXXX");
    check ("=REGEXREPLACE(\"Sonia Rees\",\"([A-Z][a-z]+) ([A-Z][a-z]+)\",\"$2, $1\")", "Rees, Sonia");
    check ("=REGEXREPLACE(\"a1b2c3\",\"[0-9]\",\"#\",2)", "a1b#c3");
    spill ("=TEXTSPLIT(\"Dakota Lennon Sanchez\",\" \")", { "Z1", "AA1", "AB1" }, { "Dakota", "Lennon", "Sanchez" });
    spill ("=TEXTSPLIT(\"1,2,3;4,5,6\",\",\",\";\")", { "Z1", "AB1", "Z2", "AB2" }, { "1", "3", "4", "6" });
    spill ("=TEXTSPLIT(\"a,b;c\",\",\",\";\")", { "Z2", "AA2" }, { "c", "#N/A" });
    spill ("=TEXTSPLIT(\"Do. Or do not. There is no try.\",{\".\",\",\"})", { "Z1", "AA1", "AB1" }, { "Do", " Or do not", " There is no try" });
    spill ("=TEXTSPLIT(\"a,,b\",\",\",,TRUE)", { "Z1", "AA1" }, { "a", "b" });
    check ("=TEXTBEFORE(\"Little Red Riding Hood's red hood\",\"Red\")", "Little ");
    check ("=TEXTBEFORE(\"Little Red Riding Hood's red hood\",\"red\",-1)", "Little Red Riding Hood's ");
    check ("=TEXTBEFORE(\"Little Red Riding Hood's red hood\",\"red\",1,1)", "Little ");
    check ("=TEXTBEFORE(\"Little Red Riding Hood's red hood\",\"x\",1,0,0,\"none\")", "none");
    check ("=TEXTAFTER(\"Little Red Riding Hood's red hood\",\"hood\")", "");
    check ("=TEXTAFTER(\"Little Red Riding Hood's red hood\",\"hood\",1,1)", "'s red hood");
    check ("=TEXTAFTER(\"Little Red Riding Hood's red hood\",\"red\",2)", "#N/A");
    check ("=TEXTAFTER(\"Little Red Riding Hood's red hood\",\"red\",2,1)", " hood");
    check ("=TEXTAFTER(\"abc\",\"x\")", "#N/A");
    check ("=TEXTBEFORE(\"abc\",\"x\",1,0,1)", "abc");
    check ("=VALUETOTEXT(\"Seattle\",1)", "\"Seattle\"");
    check ("=VALUETOTEXT(1234.01234)", "1234.01234");
    check ("=ARRAYTOTEXT({TRUE,\"a\";1.5,\"Seattle\"})", "TRUE, a, 1.5, Seattle");
    check ("=ARRAYTOTEXT({TRUE,\"a\";1.5,\"Seattle\"},1)", "{TRUE,\"a\";1.5,\"Seattle\"}");
    check ("=ASC(\"ＥＸＣＥＬ\")", "EXCEL");
    check ("=DBCS(\"EXCEL\")", "ＥＸＣＥＬ");
    check ("=BAHTTEXT(1234)", "หนึ่งพันสองร้อยสามสิบสี่บาทถ้วน");
    check ("=BAHTTEXT(21.25)", "ยี่สิบเอ็ดบาทยี่สิบห้าสตางค์");
    check ("=LENB(\"abc\")", "3");
    finish ();
}

void test_arrays () {
    fresh ();
    column ("A", 1, { "East", "West", "East", "North", "West" });
    column ("B", 1, { "10", "20", "30", "40", "50" });
    spill ("=FILTER(A1:B5,B1:B5>25)", { "Z1", "AA1", "Z2", "Z3", "AA3", "Z4" }, { "East", "30", "North", "West", "50", "" });
    check ("=FILTER(A1:A5,B1:B5>100)", "#CALC!");
    check ("=FILTER(A1:A5,B1:B5>100,\"none\")", "none");
    spill ("=SORT(B1:B5,,-1)", { "Z1", "Z5" }, { "50", "10" });
    spill ("=SORT(A1:B5,{1,2},{1,-1})", { "Z1", "AA1", "Z2", "AA2", "Z5" }, { "East", "30", "East", "10", "West" });
    spill ("=SORTBY(A1:A5,B1:B5,-1)", { "Z1", "Z2" }, { "West", "North" });
    spill ("=UNIQUE(A1:A5)", { "Z1", "Z2", "Z3", "Z4" }, { "East", "West", "North", "" });
    spill ("=UNIQUE(A1:A5,,TRUE)", { "Z1", "Z2" }, { "North", "" });
    spill ("=SEQUENCE(2,3,10,5)", { "Z1", "AB1", "Z2", "AB2" }, { "10", "20", "25", "35" });
    put ("Z1", "=RANDARRAY(3,2,1,6,TRUE)");
    book.recalculate ();
    double d;
    string f;
    if (!Input.parse_number (at ("AA3"), out d, out f) || d < 1 || d > 6 || d != Math.floor (d)) {
        stderr.printf ("FAIL RANDARRAY %s\n", at ("AA3"));
        failures++;
    }
    put ("Z1", "");
    spill ("=VSTACK({1,2},{3,4,5})", { "Z1", "AB1", "Z2", "AB2" }, { "1", "#N/A", "3", "5" });
    spill ("=HSTACK({1;2},{3})", { "Z1", "AA1", "AA2" }, { "1", "3", "#N/A" });
    spill ("=TAKE(SEQUENCE(5),-2)", { "Z1", "Z2", "Z3" }, { "4", "5", "" });
    spill ("=DROP(SEQUENCE(3,3),1,1)", { "Z1", "AA1", "Z2" }, { "5", "6", "8" });
    spill ("=CHOOSEROWS(SEQUENCE(5),1,-1)", { "Z1", "Z2" }, { "1", "5" });
    spill ("=CHOOSECOLS(SEQUENCE(2,4),2,4)", { "Z1", "AA1", "Z2" }, { "2", "4", "6" });
    spill ("=EXPAND({1,2},2,3,0)", { "Z1", "AB1", "Z2" }, { "1", "0", "0" });
    spill ("=TOCOL({1,2;3,4})", { "Z1", "Z2", "Z3", "Z4" }, { "1", "2", "3", "4" });
    spill ("=TOCOL({1,2;3,4},0,TRUE)", { "Z2" }, { "3" });
    spill ("=TOROW({1,2;3,4})", { "AC1" }, { "4" });
    spill ("=WRAPROWS(SEQUENCE(5),2)", { "Z1", "AA1", "Z3", "AA3" }, { "1", "2", "5", "#N/A" });
    spill ("=WRAPCOLS(SEQUENCE(5),2,0)", { "Z1", "Z2", "AA1", "AB2" }, { "1", "2", "3", "0" });
    spill ("=TRANSPOSE({1,2,3})", { "Z1", "Z2", "Z3" }, { "1", "2", "3" });
    spill ("=INDEX({1,2;3,4},0,2)", { "Z1", "Z2" }, { "2", "4" });
    spill ("=ROW(A1:A3)", { "Z1", "Z3" }, { "1", "3" });
    spill ("=XMATCH({\"West\",\"North\"},A1:A5)", { "Z1", "AA1" }, { "2", "4" });
    spill ("=XLOOKUP(\"North\",A1:A5,A1:B5)", { "Z1", "AA1" }, { "North", "40" });
    check ("=ROWS(TRIMRANGE(A1:A100))", "5");
    check ("=PERCENTOF(B1:B2,B1:B5)", "0.2");
    put ("Y1", "=1+1");
    check ("=FORMULATEXT(Y1)", "=1+1");
    finish ();
}

void test_groupby () {
    fresh ();
    column ("A", 1, { "Region", "East", "West", "East", "North", "West" });
    column ("B", 1, { "Sales", "10", "20", "30", "40", "50" });
    column ("C", 1, { "Year", "2023", "2024", "2024", "2023", "2023" });
    spill ("=GROUPBY(A1:A6,B1:B6,SUM)", { "Z1", "AA1", "Z2", "AA2", "Z3", "AA3", "Z4", "AA4", "Z5", "AA5" }, { "Region", "Sales", "East", "40", "North", "40", "West", "70", "Total", "150" });
    spill ("=GROUPBY(A2:A6,B2:B6,SUM,0,0,-2)", { "Z1", "AA1", "Z3", "Z4" }, { "West", "70", "North", "" });
    spill ("=GROUPBY(A2:A6,B2:B6,PERCENTOF,0,0)", { "Z1", "AA1" }, { "East", "0.266666667" });
    spill ("=GROUPBY(A2:A6,B2:B6,LAMBDA(x,COUNT(x)),0,1,,B2:B6>15)", { "Z1", "AA1", "Z3", "AA3" }, { "East", "1", "West", "2" });
    spill ("=PIVOTBY(A2:A6,C2:C6,B2:B6,SUM,0)", { "AA1", "AB1", "AC1", "Z2", "AA2", "AB2", "AC2", "Z5", "AC5" }, { "2023", "2024", "Total", "East", "10", "30", "40", "Total", "150" });
    finish ();
}

void test_cube () {
    fresh ();
    column ("A", 1, { "Region", "East", "West", "East", "North", "West" });
    column ("B", 1, { "Product", "Apple", "Pear", "Pear", "Apple", "Apple" });
    column ("C", 1, { "Amount", "10", "20", "30", "40", "50" });
    column ("E", 1, { "Product", "Apple", "Pear" });
    column ("F", 1, { "Category", "Fruit A", "Fruit B" });
    var sales = new TableDef ("Sales", sh, new Area (sh, 0, 0, 5, 2));
    sales.sync_columns ();
    book.tables.add (sales);
    var products = new TableDef ("Products", sh, new Area (sh, 0, 4, 2, 5));
    products.sync_columns ();
    book.tables.add (products);
    string c = "\"ThisWorkbookDataModel\"";
    check ("=CUBEVALUE(" + c + ",\"[Measures].[Sum of Amount]\")", "150");
    check ("=CUBEVALUE(" + c + ",\"[Sales].[Region].[East]\",\"[Measures].[Sum of Amount]\")", "40");
    check ("=CUBEVALUE(" + c + ",\"([Sales].[Region].[West],[Products].[Category].&[Fruit A])\",\"[Measures].[Sum of Amount]\")", "50");
    check ("=CUBEVALUE(" + c + ",\"[Products].[Category].[Fruit B]\",\"[Measures].[Count of Amount]\")", "2");
    check ("=CUBEVALUE(" + c + ",\"[Measures].[Average of Amount]\")", "30");
    check ("=CUBEVALUE(" + c + ",\"[Measures].[Max of Amount]\",\"[Sales].[Region].[East]\")", "30");
    check ("=CUBEVALUE(" + c + ",\"[Measures].[Distinct Count of Region]\")", "3");
    check ("=CUBEVALUE(\"Server1\",\"[Measures].[Sum of Amount]\")", "#N/A");
    check ("=CUBEMEMBER(" + c + ",\"[Sales].[Region].[Nowhere]\")", "#N/A");
    put ("H1", "=CUBEMEMBER(" + c + ",\"[Sales].[Region].[East]\")");
    check ("=H1", "East");
    check ("=CUBEVALUE(" + c + ",H1,\"[Measures].[Sum of Amount]\")", "40");
    put ("H2", "=CUBESET(" + c + ",\"[Sales].[Region].Children\",\"Regions\",2,\"[Measures].[Sum of Amount]\")");
    check ("=H2", "Regions");
    check ("=CUBESETCOUNT(H2)", "3");
    check ("=CUBERANKEDMEMBER(" + c + ",H2,1)", "West");
    check ("=CUBERANKEDMEMBER(" + c + ",H2,2)", "East");
    put ("H3", "=CUBESET(" + c + ",\"{[Sales].[Region].[East],[Sales].[Region].[North]}\")");
    check ("=CUBEVALUE(" + c + ",H3,\"[Measures].[Sum of Amount]\")", "80");
    put ("H6", "=CUBESET(" + c + ",\"[Sales].[Region].Children\",,4)");
    check ("=CUBERANKEDMEMBER(" + c + ",H6,1)", "West");
    check ("=CUBEMEMBERPROPERTY(" + c + ",\"[Products].[Product].[Pear]\",\"Category\")", "Fruit B");
    check ("=CUBEMEMBERPROPERTY(" + c + ",\"[Sales].[Region].&[East]\",\"MEMBER_UNIQUE_NAME\")", "[Sales].[Region].&[East]");
    DataModel.store_json (book, "{\"infer\":false,\"relationships\":[{\"fromTable\":\"Sales\",\"fromColumn\":\"Product\",\"toTable\":\"Products\",\"toColumn\":\"Product\"}],\"measures\":[{\"name\":\"Revenue\",\"table\":\"Sales\",\"column\":\"Amount\",\"aggregation\":\"SUM\"},{\"name\":\"Avg Ticket\",\"formula\":\"[Revenue]/[Count of Amount]\"}],\"kpis\":[{\"name\":\"RevenueKPI\",\"value\":\"Revenue\",\"goal\":100,\"low\":0.8,\"high\":1}]}");
    check ("=CUBEVALUE(" + c + ",\"[Measures].[Revenue]\",\"[Sales].[Region].[West]\")", "70");
    check ("=CUBEVALUE(" + c + ",\"[Measures].[Revenue]\",\"[Products].[Category].[Fruit B]\")", "50");
    check ("=CUBEVALUE(" + c + ",\"[Measures].[Avg Ticket]\",\"[Sales].[Region].[West]\")", "35");
    put ("H4", "=CUBEKPIMEMBER(" + c + ",\"RevenueKPI\",1)");
    check ("=CUBEVALUE(" + c + ",H4)", "150");
    put ("H5", "=CUBEKPIMEMBER(" + c + ",\"RevenueKPI\",3)");
    check ("=CUBEVALUE(" + c + ",H5)", "1");
    check ("=CUBEVALUE(" + c + ",H5,\"[Sales].[Region].[West]\")", "-1");
    check ("=CUBEVALUE(\"Sales\",\"[Measures].[Revenue]\")", "150");
    var model = DataModel.build (book);
    var again = new DataModel ();
    again.load (model.to_json ());
    if (again.measures.size != 2 || again.measures[1].formula == "" || again.kpis.size != 1 || again.relationships.size != 1 || again.infer) {
        stderr.printf ("FAIL data model json round trip\n");
        failures++;
    }
    finish ();
}

int main (string[] args) {
    Test.init (ref args);
    Test.set_nonfatal_assertions ();
    LocaleInfo.set_c ();
    if (Environment.get_variable ("SS_LIST_FUNCTIONS") != null) {
        var names = new Gee.ArrayList<string> ();
        names.add_all (Functions.all ().keys);
        names.sort ();
        foreach (var n in names) stdout.printf ("%s\n", n);
        return 0;
    }
    Test.add_func ("/functions_b/distributions", test_distributions);
    Test.add_func ("/functions_b/descriptive", test_descriptive);
    Test.add_func ("/functions_b/tests", test_tests);
    Test.add_func ("/functions_b/regression", test_regression);
    Test.add_func ("/functions_b/matrix", test_matrix);
    Test.add_func ("/functions_b/text", test_text);
    Test.add_func ("/functions_b/arrays", test_arrays);
    Test.add_func ("/functions_b/groupby", test_groupby);
    Test.add_func ("/functions_b/cube", test_cube);
    return Test.run ();
}
