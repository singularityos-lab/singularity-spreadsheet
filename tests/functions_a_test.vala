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

Singularity.Apps.Spreadsheet.Value eval (string formula) {
    sh.set_input (999, 25, formula);
    book.recalculate ();
    return sh.value_at (999, 25);
}

void fail (string formula, string expected, string got) {
    stderr.printf ("FAIL %s: expected [%s] got [%s]\n", formula, expected, got);
    failures++;
}

void num (string formula, double expected, double tol = 1e-6) {
    var v = eval (formula);
    if (v.kind != ValueKind.NUMBER) {
        fail (formula, Singularity.Apps.Spreadsheet.Value.format_number_general_full (expected), v.display ());
        return;
    }
    double scale = double.max (1, Math.fabs (expected));
    if (Math.fabs (v.number - expected) > tol * scale) fail (formula, Singularity.Apps.Spreadsheet.Value.format_number_general_full (expected), Singularity.Apps.Spreadsheet.Value.format_number_general_full (v.number));
}

void str (string formula, string expected) {
    var v = eval (formula);
    string got = v.display ();
    if (got != expected) fail (formula, expected, got);
}

void cplx (string formula, string expected) {
    var v = eval (formula);
    Cplx want = Cplx (0, 0), got = Cplx (0, 0);
    string s1 = "", s2 = "";
    bool ok = v.kind == ValueKind.TEXT;
    if (ok) ok = EngineeringFunctions.parse_complex (v.text, out got, out s2);
    if (ok) ok = EngineeringFunctions.parse_complex (expected, out want, out s1);
    if (!ok || s1 != s2) {
        fail (formula, expected, v.display ());
        return;
    }
    double tol = 1e-9;
    if (Math.fabs (got.re - want.re) > tol * double.max (1, Math.fabs (want.re)) || Math.fabs (got.im - want.im) > tol * double.max (1, Math.fabs (want.im))) fail (formula, expected, v.display ());
}

void fresh () {
    book = new Workbook ();
    sh = book.add_sheet ("Sheet1");
}

void test_engineering () {
    fresh ();
    num ("=BIN2DEC(\"1100100\")", 100);
    num ("=BIN2DEC(\"1111111111\")", -1);
    str ("=BIN2HEX(11111011,4)", "00FB");
    str ("=BIN2HEX(1110)", "E");
    str ("=BIN2HEX(1111111111)", "FFFFFFFFFF");
    str ("=BIN2OCT(1001,3)", "011");
    str ("=BIN2OCT(1100100)", "144");
    str ("=BIN2OCT(1111111111)", "7777777777");
    str ("=DEC2BIN(9,4)", "1001");
    str ("=DEC2BIN(-100)", "1110011100");
    str ("=DEC2BIN(512)", "#NUM!");
    str ("=DEC2HEX(100,4)", "0064");
    str ("=DEC2HEX(-54)", "FFFFFFFFCA");
    str ("=DEC2HEX(28)", "1C");
    str ("=DEC2HEX(64,1)", "#NUM!");
    str ("=DEC2OCT(58,3)", "072");
    str ("=DEC2OCT(-100)", "7777777634");
    str ("=HEX2BIN(\"F\",8)", "00001111");
    str ("=HEX2BIN(\"B7\")", "10110111");
    str ("=HEX2BIN(\"FFFFFFFFFF\")", "1111111111");
    num ("=HEX2DEC(\"A5\")", 165);
    num ("=HEX2DEC(\"FFFFFFFF5B\")", -165);
    num ("=HEX2DEC(\"3DA408B9\")", 1034160313);
    str ("=HEX2OCT(\"F\",3)", "017");
    str ("=HEX2OCT(\"3B4E\")", "35516");
    str ("=HEX2OCT(\"FFFFFFFF00\")", "7777777400");
    str ("=OCT2BIN(3,3)", "011");
    str ("=OCT2BIN(7777777000)", "1000000000");
    num ("=OCT2DEC(54)", 44);
    num ("=OCT2DEC(7777777533)", -165);
    str ("=OCT2HEX(100,4)", "0040");
    str ("=OCT2HEX(7777777533)", "FFFFFFFF5B");
    str ("=BIN2DEC(\"12\")", "#NUM!");
    num ("=BITAND(1,5)", 1);
    num ("=BITAND(13,25)", 9);
    num ("=BITOR(23,10)", 31);
    num ("=BITXOR(5,3)", 6);
    num ("=BITLSHIFT(4,2)", 16);
    num ("=BITRSHIFT(13,2)", 3);
    str ("=BITAND(-1,5)", "#NUM!");
    str ("=COMPLEX(3,4)", "3+4i");
    str ("=COMPLEX(3,4,\"j\")", "3+4j");
    str ("=COMPLEX(0,1)", "i");
    str ("=COMPLEX(1,0)", "1");
    str ("=COMPLEX(1,2,\"k\")", "#VALUE!");
    num ("=IMABS(\"5+12i\")", 13);
    num ("=IMAGINARY(\"3+4i\")", 4);
    num ("=IMAGINARY(\"0-j\")", -1);
    num ("=IMAGINARY(4)", 0);
    num ("=IMARGUMENT(\"3+4i\")", 0.92729522);
    str ("=IMCONJUGATE(\"3+4i\")", "3-4i");
    cplx ("=IMCOS(\"1+i\")", "0.833730025131149-0.988897705762865i");
    str ("=IMDIV(\"-238+240i\",\"10+24i\")", "5+12i");
    cplx ("=IMEXP(\"1+i\")", "1.46869393991589+2.28735528717884i");
    cplx ("=IMLN(\"3+4i\")", "1.6094379124341+0.927295218001612i");
    cplx ("=IMLOG10(\"3+4i\")", "0.698970004336019+0.402719196273373i");
    cplx ("=IMLOG2(\"3+4i\")", "2.32192809488736+1.33780421245098i");
    cplx ("=IMPOWER(\"2+3i\",3)", "-46+9i");
    str ("=IMPRODUCT(\"3+4i\",\"5-3i\")", "27+11i");
    str ("=IMPRODUCT(\"1+2i\",30)", "30+60i");
    num ("=IMREAL(\"6-9i\")", 6);
    cplx ("=IMSIN(\"4+3i\")", "-7.61923172032141-6.548120040911i");
    cplx ("=IMSQRT(\"1+i\")", "1.09868411346781+0.455089860562227i");
    str ("=IMSUB(\"13+4i\",\"5+3i\")", "8+i");
    str ("=IMSUM(\"3+4i\",\"5-3i\")", "8+i");
    cplx ("=IMTAN(\"4+3i\")", "0.00490825806749606+1.00070953606723i");
    cplx ("=IMSINH(\"4+3i\")", "-27.0168132580039+3.85373803791938i");
    cplx ("=IMCOSH(\"4+3i\")", "-27.0349456030742+3.85115333481178i");
    cplx ("=IMSEC(\"4+3i\")", "-0.0652940278579471-0.0752249603027732i");
    cplx ("=IMCSC(\"4+3i\")", "-0.0754898329158637+0.0648774713706355i");
    cplx ("=IMCOT(\"4+3i\")", "0.0049011823943045-0.999266927805902i");
    cplx ("=IMSECH(\"4+3i\")", "-0.0362534969158689-0.00516434460775318i");
    cplx ("=IMCSCH(\"4+3i\")", "-0.036275889628626-0.0051744731840194i");
    str ("=IMSUM(\"1+i\",\"1+j\")", "#VALUE!");
    str ("=IMDIV(\"1+i\",0)", "#NUM!");
    num ("=CONVERT(1,\"lbm\",\"kg\")", 0.45359237);
    num ("=CONVERT(68,\"F\",\"C\")", 20);
    str ("=CONVERT(2.5,\"ft\",\"sec\")", "#N/A");
    num ("=CONVERT(CONVERT(100,\"ft\",\"m\"),\"ft\",\"m\")", 9.290304);
    num ("=CONVERT(6,\"tsp\",\"tbs\")", 2);
    num ("=CONVERT(6,\"mi\",\"km\")", 9.656064);
    num ("=CONVERT(6,\"in\",\"mm\")", 152.4);
    num ("=CONVERT(1,\"gal\",\"l\")", 3.785411784);
    num ("=CONVERT(1,\"kibyte\",\"bit\")", 8192);
    num ("=CONVERT(1,\"m2\",\"cm2\")", 10000);
    num ("=CONVERT(1,\"km/h\",\"m/s\")", 1 / 3.6);
    num ("=CONVERT(100,\"C\",\"K\")", 373.15);
    num ("=CONVERT(0,\"C\",\"Rank\")", 491.67);
    num ("=CONVERT(1,\"hr\",\"mn\")", 60);
    num ("=CONVERT(1,\"atm\",\"mmHg\")", 760.002100178515, 1e-6);
    num ("=CONVERT(1,\"ha\",\"m2\")", 10000);
    str ("=CONVERT(1,\"xyz\",\"m\")", "#N/A");
    num ("=DELTA(5,4)", 0);
    num ("=DELTA(5,5)", 1);
    num ("=DELTA(0.5,0)", 0);
    num ("=GESTEP(5,4)", 1);
    num ("=GESTEP(5,5)", 1);
    num ("=GESTEP(-4,-5)", 1);
    num ("=GESTEP(-1)", 0);
    num ("=ERF(0.745)", 0.70792892);
    num ("=ERF(1)", 0.84270079);
    num ("=ERF(0,1)", 0.84270079);
    num ("=ERF.PRECISE(0.745)", 0.70792892);
    num ("=ERFC(1)", 0.15729921);
    num ("=ERFC.PRECISE(1)", 0.15729921);
    num ("=BESSELI(1.5,1)", 0.981666428);
    num ("=BESSELJ(1.9,2)", 0.329925829);
    num ("=BESSELK(1.5,1)", 0.277387804);
    num ("=BESSELY(2.5,1)", 0.145918138);
    str ("=BESSELY(-1,1)", "#NUM!");
    str ("=BESSELJ(1,-1)", "#NUM!");
    num ("=SUM(DEC2BIN({1;2;3})+0)", 1 + 10 + 11);
}

void test_database () {
    fresh ();
    put ("A1", "Tree");
    put ("B1", "Height");
    put ("C1", "Age");
    put ("D1", "Yield");
    put ("E1", "Profit");
    put ("F1", "Height");
    put ("A2", "=\"=Apple\"");
    put ("B2", ">10");
    put ("F2", "<16");
    put ("A3", "=\"=Pear\"");
    string[] rows = { "Tree,Height,Age,Yield,Profit", "Apple,18,20,14,105", "Pear,12,12,10,96", "Cherry,13,14,9,105", "Apple,14,15,10,75", "Pear,9,8,8,77", "Apple,8,9,6,45" };
    for (int i = 0; i < rows.length; i++) {
        string[] f = rows[i].split (",");
        for (int j = 0; j < f.length; j++) sh.set_input (4 + i, j, f[j]);
    }
    num ("=DCOUNT(A5:E11,\"Age\",A1:F2)", 1);
    num ("=DCOUNTA(A5:E11,\"Profit\",A1:F2)", 1);
    num ("=DMAX(A5:E11,\"Profit\",A1:A3)", 105);
    num ("=DMIN(A5:E11,\"Profit\",A1:B2)", 75);
    num ("=DSUM(A5:E11,\"Profit\",A1:A2)", 225);
    num ("=DSUM(A5:E11,\"Profit\",A1:F2)", 75);
    num ("=DPRODUCT(A5:E11,\"Yield\",A1:F2)", 10);
    num ("=DAVERAGE(A5:E11,\"Yield\",A1:B2)", 12);
    num ("=DAVERAGE(A5:E11,3,A5:E11)", 13);
    num ("=DSTDEV(A5:E11,\"Yield\",A1:A3)", 2.96647939);
    num ("=DSTDEVP(A5:E11,\"Yield\",A1:A3)", 2.65329983);
    num ("=DVAR(A5:E11,\"Yield\",A1:A3)", 8.8);
    num ("=DVARP(A5:E11,\"Yield\",A1:A3)", 7.04);
    str ("=DGET(A5:E11,\"Yield\",A1:A3)", "#NUM!");
    num ("=DGET(A5:E11,\"Yield\",A1:F2)", 10);
    str ("=DSUM(A5:E11,\"Nope\",A1:A2)", "#VALUE!");
    put ("H1", "Tree");
    put ("H2", "P*");
    num ("=DSUM(A5:E11,\"Profit\",H1:H2)", 173);
    put ("I1", "Tree");
    put ("I2", "Ch");
    num ("=DSUM(A5:E11,\"Profit\",I1:I2)", 105);
    put ("J1", "Big");
    put ("J2", "=E6>100");
    num ("=DCOUNT(A5:E11,\"Profit\",J1:J2)", 2);
    num ("=DCOUNT(A5:E11,,A1:A2)", 3);
}

void test_financial () {
    fresh ();
    num ("=ACCRINT(39508,39691,39569,0.1,1000,2,0)", 16.666667);
    num ("=ACCRINT(DATE(2008,3,5),39691,39569,0.1,1000,2,0,FALSE)", 15.555556);
    num ("=ACCRINT(DATE(2008,4,5),39691,39569,0.1,1000,2,0,TRUE)", 7.2222222);
    num ("=ACCRINTM(39539,39614,0.1,1000,3)", 20.54794521);
    num ("=AMORDEGRC(2400,39679,39813,300,1,0.15,1)", 776);
    num ("=AMORLINC(2400,39679,39813,300,1,0.15,1)", 360);
    num ("=COUPDAYBS(DATE(2011,1,25),DATE(2011,11,15),2,1)", 71);
    num ("=COUPDAYS(DATE(2011,1,25),DATE(2011,11,15),2,1)", 181);
    num ("=COUPDAYSNC(DATE(2011,1,25),DATE(2011,11,15),2,1)", 110);
    num ("=COUPNCD(DATE(2011,1,25),DATE(2011,11,15),2,1)", 40678);
    num ("=COUPNUM(DATE(2007,1,25),DATE(2008,11,15),2,1)", 4);
    num ("=COUPPCD(DATE(2011,1,25),DATE(2011,11,15),2,1)", 40497);
    num ("=CUMIPMT(0.09/12,30*12,125000,13,24,0)", -11135.23213);
    num ("=CUMIPMT(0.09/12,30*12,125000,1,1,0)", -937.5);
    num ("=CUMPRINC(0.09/12,30*12,125000,13,24,0)", -934.1071234);
    num ("=CUMPRINC(0.09/12,30*12,125000,1,1,0)", -68.27827118);
    num ("=DB(1000000,100000,6,1,7)", 186083.33, 1e-7);
    num ("=DB(1000000,100000,6,2,7)", 259639.42, 1e-7);
    num ("=DB(1000000,100000,6,3,7)", 176814.44, 1e-7);
    num ("=DB(1000000,100000,6,4,7)", 120410.64, 1e-7);
    num ("=DB(1000000,100000,6,5,7)", 81999.64, 1e-7);
    num ("=DB(1000000,100000,6,6,7)", 55841.76, 1e-7);
    num ("=DB(1000000,100000,6,7,7)", 15845.10, 1e-7);
    num ("=DISC(DATE(2018,7,1),DATE(2048,1,1),97.975,100,1)", 0.00068644, 1e-4);
    num ("=DOLLARDE(1.02,16)", 1.125);
    num ("=DOLLARDE(1.1,32)", 1.3125);
    num ("=DOLLARFR(1.125,16)", 1.02);
    num ("=DOLLARFR(1.125,32)", 1.04);
    num ("=DURATION(DATE(2018,7,1),DATE(2048,1,1),0.08,0.09,2,1)", 10.9191453);
    num ("=FVSCHEDULE(1,{0.09,0.11,0.1})", 1.3308900);
    num ("=INTRATE(DATE(2008,2,15),DATE(2008,5,15),1000000,1014420,2)", 0.05768);
    num ("=ISPMT(0.1/12,1,3*12,8000000)", -64814.8148);
    num ("=ISPMT(0.1,1,3,8000000)", -533333.333);
    num ("=MDURATION(DATE(2008,1,1),DATE(2016,1,1),0.08,0.09,2,1)", 5.73567, 1e-5);
    num ("=MIRR({-120000,39000,30000,21000,37000,46000},0.1,0.12)", 0.126094, 1e-5);
    num ("=MIRR({-120000,39000,30000,21000},0.1,0.12)", -0.048044655);
    num ("=MIRR({-120000,39000,30000,21000,37000,46000},0.1,0.14)", 0.134759111);
    num ("=ODDFPRICE(DATE(2008,11,11),DATE(2021,3,1),DATE(2008,10,15),DATE(2009,3,1),0.0785,0.0625,100,2,1)", 113.597717, 1e-6);
    num ("=ODDFYIELD(DATE(2008,11,11),DATE(2021,3,1),DATE(2008,10,15),DATE(2009,3,1),0.0575,84.5,100,2,0)", 0.0772455, 1e-5);
    num ("=ODDLPRICE(DATE(2008,2,7),DATE(2008,6,15),DATE(2007,10,15),0.0375,0.0405,100,2,0)", 99.87828601);
    num ("=ODDLYIELD(DATE(2008,4,20),DATE(2008,6,15),DATE(2007,12,24),0.0375,99.875,100,2,0)", 0.045192, 1e-4);
    num ("=PDURATION(2.5%,2000,2200)", 3.859866163, 1e-6);
    num ("=PDURATION(0.025/12,1000,1200)", 87.6, 1e-3);
    num ("=PRICE(DATE(2008,2,15),DATE(2017,11,15),0.0575,0.065,100,2,0)", 94.63436, 1e-6);
    num ("=PRICEDISC(DATE(2008,2,16),DATE(2008,3,1),0.0525,100,2)", 99.79583, 1e-7);
    num ("=PRICEMAT(DATE(2008,2,15),DATE(2008,4,13),DATE(2007,11,11),0.061,0.061,0)", 99.98449888);
    num ("=RECEIVED(DATE(2008,2,15),DATE(2008,5,15),1000000,0.0575,2)", 1014584.654);
    num ("=RRI(96,10000,11000)", 0.0009933, 1e-4);
    num ("=TBILLEQ(DATE(2008,3,31),DATE(2008,6,1),0.0914)", 0.094151, 1e-5);
    num ("=TBILLPRICE(DATE(2008,3,31),DATE(2008,6,1),0.09)", 98.45);
    num ("=TBILLYIELD(DATE(2008,3,31),DATE(2008,6,1),98.45)", 0.091417, 1e-5);
    num ("=VDB(2400,300,10*365,0,1)", 1.315068493);
    num ("=VDB(2400,300,10*12,0,1)", 40);
    num ("=VDB(2400,300,10,0,1)", 480);
    num ("=VDB(2400,300,10*12,6,18)", 396.306, 1e-5);
    num ("=VDB(2400,300,10*12,6,18,1.5)", 311.8089, 1e-5);
    num ("=VDB(2400,300,10,0,0.875,1.5)", 315);
    num ("=YIELD(DATE(2008,2,15),DATE(2016,11,15),0.0575,95.04287,100,2,0)", 0.065, 1e-5);
    num ("=YIELDDISC(DATE(2008,2,16),DATE(2008,3,1),99.795,100,2)", 0.052823, 1e-5);
    num ("=YIELDMAT(DATE(2008,3,15),DATE(2008,11,3),DATE(2007,11,8),0.0625,100.0123,0)", 0.060954, 1e-5);
    num ("=EUROCONVERT(1,\"FRF\",\"DEM\")", 0.3);
    num ("=EUROCONVERT(1,\"FRF\",\"DEM\",TRUE,3)", 0.29728616);
    num ("=EUROCONVERT(1,\"EUR\",\"ITL\")", 1936);
    str ("=PRICE(DATE(2008,2,15),DATE(2017,11,15),0.0575,0.065,100,3,0)", "#NUM!");
}

void test_math () {
    fresh ();
    str ("=ROMAN(499,0)", "CDXCIX");
    str ("=ROMAN(499,1)", "LDVLIV");
    str ("=ROMAN(499,2)", "XDIX");
    str ("=ROMAN(499,3)", "VDIV");
    str ("=ROMAN(499,4)", "ID");
    str ("=ROMAN(2013,0)", "MMXIII");
    str ("=ROMAN(499,FALSE)", "ID");
    str ("=ROMAN(4000)", "#VALUE!");
    num ("=ARABIC(\"LVII\")", 57);
    num ("=ARABIC(\"mcmxii\")", 1912);
    num ("=ARABIC(\"-MMXI\")", -2011);
    num ("=ARABIC(\"\")", 0);
    str ("=ARABIC(\"ABC\")", "#VALUE!");
    str ("=BASE(7,2)", "111");
    str ("=BASE(100,16)", "64");
    str ("=BASE(15,2,10)", "0000001111");
    num ("=DECIMAL(\"FF\",16)", 255);
    num ("=DECIMAL(111,2)", 7);
    num ("=DECIMAL(\"zap\",36)", 45745);
    num ("=SUMX2MY2({2,3,9,1,8,7,5},{6,5,11,7,5,4,4})", -55);
    num ("=SUMX2PY2({2,3,9,1,8,7,5},{6,5,11,7,5,4,4})", 521);
    num ("=SUMXMY2({2,3,9,1,8,7,5},{6,5,11,7,5,4,4})", 79);
    num ("=SERIESSUM(PI()/4,0,2,{1,-0.5,0.041666666666667,-0.00138888888888889})", 0.707103, 1e-5);
    num ("=MULTINOMIAL(2,3,4)", 1260);
    num ("=FACTDOUBLE(6)", 48);
    num ("=FACTDOUBLE(7)", 105);
    num ("=SQRTPI(1)", 1.772454, 1e-6);
    num ("=SQRTPI(2)", 2.506628, 1e-6);
    num ("=COMBINA(4,3)", 20);
    num ("=COMBINA(10,3)", 220);
    num ("=PERMUTATIONA(3,2)", 9);
    num ("=PERMUTATIONA(2,2)", 4);
    num ("=SEC(45)", 1.90359, 1e-5);
    num ("=CSC(15)", 1.537780562);
    num ("=COT(30)", -0.156119952);
    num ("=COTH(2)", 1.037314721);
    num ("=CSCH(1.5)", 0.469642441);
    num ("=SECH(45)", 5.73e-20, 1e-3);
    num ("=ACOT(2)", 0.463647609);
    num ("=ACOTH(6)", 0.168236118);
    str ("=COT(0)", "#DIV/0!");
    num ("=CEILING.MATH(24.3,5)", 25);
    num ("=CEILING.MATH(6.7)", 7);
    num ("=CEILING.MATH(-8.1,2)", -8);
    num ("=CEILING.MATH(-5.5,2,-1)", -6);
    num ("=CEILING.PRECISE(4.3)", 5);
    num ("=CEILING.PRECISE(-4.3)", -4);
    num ("=CEILING.PRECISE(4.3,-2)", 6);
    num ("=CEILING.PRECISE(-4.3,-2)", -4);
    num ("=ISO.CEILING(4.3,2)", 6);
    num ("=FLOOR.MATH(24.3,5)", 20);
    num ("=FLOOR.MATH(6.7)", 6);
    num ("=FLOOR.MATH(-8.1,2)", -10);
    num ("=FLOOR.MATH(-5.5,2,-1)", -4);
    num ("=FLOOR.PRECISE(-3.2,-1)", -4);
    num ("=FLOOR.PRECISE(3.2,1)", 3);
    num ("=FLOOR.PRECISE(3.2)", 3);
    num ("=QUOTIENT(5,2)", 2);
    num ("=QUOTIENT(4.5,3.1)", 1);
    num ("=QUOTIENT(-10,3)", -3);
    str ("=QUOTIENT(1,0)", "#DIV/0!");
}

void test_info_web () {
    fresh ();
    book.add_sheet ("Sheet2");
    str ("=ENCODEURL(\"http://contoso.sharepoint.com/Finance/Profit and Loss Statement.xlsx\")", "http%3A%2F%2Fcontoso.sharepoint.com%2FFinance%2FProfit%20and%20Loss%20Statement.xlsx");
    num ("=SUM(FILTERXML(\"<r><b>1</b><b>2</b></r>\",\"//b\"))", 3);
    num ("=ROWS(FILTERXML(\"<r><b>1</b><b>2</b><b>x</b></r>\",\"//b\"))", 3);
    str ("=FILTERXML(\"<r><b>hello</b></r>\",\"//b\")", "hello");
    str ("=FILTERXML(\"<r><b>1</b></r>\",\"//c\")", "#VALUE!");
    str ("=FILTERXML(\"not xml\",\"//c\")", "#VALUE!");
    str ("=WEBSERVICE(\"ftp://example.invalid/x\")", "#VALUE!");
    str ("=WEBSERVICE(\"no url\")", "#VALUE!");
    str ("=CUBEVALUE(\"Sales\",\"[Measures].[Profit]\")", "#N/A");
    str ("=CUBEMEMBER(\"Sales\",\"[Time].[2004]\")", "#N/A");
    num ("=INFO(\"numfile\")", 2);
    str ("=INFO(\"recalc\")", "Automatic");
    str ("=INFO(\"bogus\")", "#VALUE!");
    put ("A1", "=1+2");
    put ("A2", "5");
    str ("=FORMULATEXT(A1)", "=1+2");
    str ("=FORMULATEXT(A2)", "#N/A");
    num ("=ERROR.TYPE(#SPILL!)", 9);
    num ("=ERROR.TYPE(#CALC!)", 14);
    num ("=ERROR.TYPE(#N/A)", 7);
    str ("=ISREF(Sheet1:Sheet2!A1)", "TRUE");
    str ("=CELL(\"prefix\",A2)", "");
    put ("A3", "text");
    str ("=CELL(\"prefix\",A3)", "'");
}

void test_count () {
    string? dump = Environment.get_variable ("SS_FN_DUMP");
    var names = new Gee.TreeSet<string> ();
    var defs = new Gee.HashSet<FnDef> ();
    foreach (var e in Functions.all ().entries) {
        names.add (e.key);
        defs.add (e.value);
    }
    if (dump != null) {
        var sb = new StringBuilder ();
        foreach (string n in names) sb.append (n + "\n");
        try {
            FileUtils.set_contents (dump, sb.str);
        } catch (Error e) {
        }
    }
    stdout.printf ("# registered names %d, distinct implementations %d\n", names.size, defs.size);
    foreach (var e in Functions.all ().entries) {
        var d = e.value;
        if (d.syntax == "" || d.summary == "" || d.category == "") {
            stderr.printf ("missing metadata for %s\n", e.key);
            failures++;
        }
    }
}

int main (string[] args) {
    Test.init (ref args);
    LocaleInfo.set_c ();
    Test.add_func ("/functions_a/engineering", test_engineering);
    Test.add_func ("/functions_a/database", test_database);
    Test.add_func ("/functions_a/financial", test_financial);
    Test.add_func ("/functions_a/math", test_math);
    Test.add_func ("/functions_a/info_web", test_info_web);
    Test.add_func ("/functions_a/count", test_count);
    int r = Test.run ();
    if (failures > 0) {
        stderr.printf ("%d failures\n", failures);
        return 1;
    }
    return r;
}
