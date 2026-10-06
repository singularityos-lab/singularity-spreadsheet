using Singularity.Apps.Spreadsheet;

string base_url;
int hits = 0;

const string ITALY_JSON = """{"head":{"vars":["itemLabel","itemDescription","population","area","capital","country","continent","coord","currency","languages","flag","leader","head","timezones","gdp","iso"]},"results":{"bindings":[{"itemLabel":{"type":"literal","value":"Italy"},"itemDescription":{"type":"literal","value":"country in southern Europe"},"population":{"type":"literal","datatype":"http://www.w3.org/2001/XMLSchema#decimal","value":"58993475"},"area":{"type":"literal","value":"301339.905"},"capital":{"type":"literal","value":"Rome"},"country":{"type":"literal","value":"Italy"},"continent":{"type":"literal","value":"Europe"},"coord":{"type":"literal","value":"Point(12.8 42.5)"},"currency":{"type":"literal","value":"euro"},"languages":{"type":"literal","value":"Italian"},"flag":{"type":"uri","value":"http://commons.wikimedia.org/wiki/Special:FilePath/Flag%20of%20Italy.svg"},"leader":{"type":"literal","value":"Giorgia Meloni"},"timezones":{"type":"literal","value":"UTC+01:00, UTC+02:00"},"gdp":{"type":"literal","value":"2254851185929"},"iso":{"type":"literal","value":"IT"}}]}}""";

const string PARIS_FR_JSON = """{"head":{"vars":["itemLabel"]},"results":{"bindings":[{"itemLabel":{"type":"literal","value":"Paris"},"itemDescription":{"type":"literal","value":"capital city of France"},"population":{"type":"literal","value":"2102650"},"country":{"type":"literal","value":"France"}}]}}""";

string search_json (string text) {
    if (text == "Italy") return """{"head":{"vars":["item","itemLabel","itemDescription","num"]},"results":{"bindings":[{"item":{"type":"uri","value":"http://www.wikidata.org/entity/Q38"},"itemLabel":{"type":"literal","value":"Italy"},"itemDescription":{"type":"literal","value":"country in southern Europe"},"num":{"type":"literal","value":"0"}}]}}""";
    if (text == "Paris") return """{"head":{"vars":["item","itemLabel","itemDescription","num"]},"results":{"bindings":[{"item":{"type":"uri","value":"http://www.wikidata.org/entity/Q90"},"itemLabel":{"type":"literal","value":"Paris"},"itemDescription":{"type":"literal","value":"capital city of France"}},{"item":{"type":"uri","value":"http://www.wikidata.org/entity/Q830149"},"itemLabel":{"type":"literal","value":"Paris"},"itemDescription":{"type":"literal","value":"city in Texas, United States"}}]}}""";
    return """{"head":{"vars":["item"]},"results":{"bindings":[]}}""";
}

void handle (Soup.Server server, Soup.ServerMessage msg, string path, HashTable<string, string>? query) {
    hits++;
    string body = "";
    string type = "text/plain";
    if (path == "/sparql") {
        type = "application/sparql-results+json";
        string q = query != null ? (query.lookup ("query") ?? "") : "";
        if (q.contains ("EntitySearch")) {
            int i = q.index_of ("mwapi:search \"");
            string rest = q.substring (i + 14);
            body = search_json (rest.substring (0, rest.index_of ("\"")));
        } else if (q.contains ("BIND(wd:Q38 ")) {
            body = ITALY_JSON;
        } else if (q.contains ("BIND(wd:Q90 ")) {
            body = PARIS_FR_JSON;
        } else {
            body = """{"head":{"vars":[]},"results":{"bindings":[]}}""";
        }
    } else if (path == "/q/l/") {
        type = "text/csv";
        string s = query != null ? (query.lookup ("s") ?? "") : "";
        if (s == "aapl.us") body = "Symbol,Date,Time,Open,High,Low,Close,Volume,Name\r\nAAPL.US,2025-09-26,22:00:09,254.1,257.6,253.78,255.46,46045600,APPLE\r\n";
        else body = "Symbol,Date,Time,Open,High,Low,Close,Volume,Name\r\n%s,N/D,N/D,N/D,N/D,N/D,N/D,N/D,N/D\r\n".printf (s.up ());
    } else if (path == "/q/d/l/") {
        type = "text/csv";
        string s = query != null ? (query.lookup ("s") ?? "") : "";
        string iv = query != null ? (query.lookup ("i") ?? "d") : "d";
        if (s == "aapl.us" && iv == "d") body = "Date,Open,High,Low,Close,Volume\r\n2025-09-22,248.3,256.64,248.12,256.08,105517400\r\n2025-09-23,255.88,257.34,253.58,254.43,60275200\r\n2025-09-24,255.22,255.74,251.04,252.31,42303700\r\n2025-09-25,253.21,257.17,251.71,256.87,55202100\r\n2025-09-26,254.1,257.6,253.78,255.46,46045600\r\n";
        else if (s == "aapl.us" && iv == "w") body = "Date,Open,High,Low,Close,Volume\r\n2025-09-19,237.0,246.3,236.1,245.5,300000000\r\n2025-09-26,248.3,257.6,248.12,255.46,309344000\r\n";
        else body = "No data";
    } else {
        msg.set_status (404, null);
        return;
    }
    msg.set_status (200, null);
    msg.set_response (type, Soup.MemoryUse.COPY, body.data);
}

void start_server () {
    var ready = new Mutex ();
    var cond = new Cond ();
    bool up = false;
    new Thread<bool> ("fake-server", () => {
        var ctx = new MainContext ();
        ctx.push_thread_default ();
        var server = new Soup.Server ("server-header", "fake");
        server.add_handler (null, handle);
        try {
            server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY);
        } catch (Error e) {
            error ("listen: %s", e.message);
        }
        var uri = server.get_uris ().data;
        ready.lock ();
        base_url = "http://127.0.0.1:%d".printf (uri.get_port ());
        up = true;
        cond.signal ();
        ready.unlock ();
        new MainLoop (ctx).run ();
        return true;
    });
    ready.lock ();
    while (!up) cond.wait (ready);
    ready.unlock ();
}

void point_to (string url) {
    Environment.set_variable ("SINGULARITY_WIKIDATA_ENDPOINT", url + "/sparql", true);
    Environment.set_variable ("SINGULARITY_STOCKS_QUOTE_URL", url + "/q/l/?s=%s&f=sd2t2ohlcvn&h&e=csv", true);
    Environment.set_variable ("SINGULARITY_STOCKS_HISTORY_URL", url + "/q/d/l/?s=%s&d1=%s&d2=%s&i=%s", true);
    LinkedConfig.reset ();
}

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

void expect (Sheet s, string addr, string expected) {
    string got = show (s, addr);
    if (got != expected) {
        stderr.printf ("FAIL %s: expected [%s] got [%s]\n", addr, expected, got);
        Test.fail ();
    }
}

void test_geography () {
    point_to (base_url);
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "Italy");
    put (s, "A2", "Paris");
    put (s, "A3", "Atlantis");
    book.recalculate ();
    string errors;
    int n = DataTypes.convert_linked (book, s, new Area (s, 0, 0, 2, 0), "geography", out errors);
    if (n != 2 || !errors.contains ("Atlantis")) {
        stderr.printf ("converted %d errors %s\n", n, errors);
        Test.fail ();
    }
    put (s, "B1", "=A1.Population");
    put (s, "B2", "=A2.Country");
    put (s, "B3", "=FIELDVALUE(A1,\"Capital\")");
    put (s, "B4", "=A1.[Official language]");
    put (s, "B5", "=A1.Latitude");
    put (s, "B6", "=A1.Nonexistent");
    put (s, "B7", "=A3.Population");
    book.recalculate ();
    expect (s, "A1", "Italy");
    expect (s, "B1", "58993475");
    expect (s, "B2", "France");
    expect (s, "B3", "Rome");
    expect (s, "B4", "Italian");
    expect (s, "B5", "42.5");
    expect (s, "B6", "#VALUE!");
    expect (s, "B7", "#VALUE!");
    try {
        var paris = new WikidataGeography ().search ("Paris");
        if (!DataTypes.is_ambiguous (paris, "Paris") || paris.size != 2 || paris[1].description != "city in Texas, United States") Test.fail ();
        var italy = new WikidataGeography ().search ("Italy");
        if (DataTypes.is_ambiguous (italy, "Italy")) Test.fail ();
    } catch (Error e) {
        Test.fail ();
    }
    string xpath = Path.build_filename (Environment.get_tmp_dir (), "ss-linked-%d.xlsx".printf (Random.int_range (0, 1000000)));
    try {
        XlsxWriter.save (book, xpath);
        uint8[] data;
        FileUtils.get_data (xpath, out data);
        var zip = new ZipReader (data);
        string sheet = zip.read_text ("xl/worksheets/sheet1.xml");
        if (!sheet.contains ("<v>58993475</v>")) {
            stderr.printf ("excel does not see the population value\n");
            Test.fail ();
        }
        point_to ("http://127.0.0.1:9");
        foreach (string ext in new string[] { "xlsx", "ods" }) {
            string fp = ext == "xlsx" ? xpath : xpath.replace (".xlsx", ".ods");
            if (ext == "ods") Ods.save (book, fp);
            var loaded = ext == "xlsx" ? Xlsx.load (fp) : Ods.load (fp);
            var ls = loaded.sheets[0];
            ls.set_input (5, 1, "=A1.Capital");
            loaded.recalculate ();
            if (ls.value_at (5, 1).display () != "Rome" || ls.value_at (0, 1).display () != "58993475") {
                stderr.printf ("%s reload lost linked record\n", ext);
                Test.fail ();
            }
            FileUtils.remove (fp);
        }
        point_to (base_url);
    } catch (Error e) {
        stderr.printf ("linked io %s\n", e.message);
        Test.fail ();
    }
    string text = AnalysisStore.serialize (book);
    var b2 = new Workbook ();
    var s2 = b2.add_sheet ("S");
    s2.set_input (0, 0, "Italy");
    point_to ("http://127.0.0.1:9");
    AnalysisStore.deserialize (b2, text);
    s2.set_input (0, 1, "=A1.Population");
    b2.recalculate ();
    expect (s2, "B1", "58993475");
}

void test_stocks () {
    point_to (base_url);
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    put (s, "A1", "AAPL");
    put (s, "A2", "ZZZZ");
    book.recalculate ();
    string errors;
    int n = DataTypes.convert_linked (book, s, new Area (s, 0, 0, 1, 0), "stocks", out errors);
    if (n != 1 || !errors.contains ("ZZZZ")) {
        stderr.printf ("stocks converted %d errors %s\n", n, errors);
        Test.fail ();
    }
    put (s, "B1", "=A1.Price");
    put (s, "B2", "=A1.[Previous close]");
    put (s, "B3", "=ROUND(A1.Change,2)");
    put (s, "B4", "=A1.Volume");
    put (s, "B5", "=A1.Exchange");
    put (s, "B6", "=TEXT(A1.[Last trade time],\"yyyy-mm-dd hh:mm\")");
    put (s, "B7", "=A1.Name");
    book.recalculate ();
    expect (s, "A1", "APPLE");
    expect (s, "B1", "255.46");
    expect (s, "B2", "256.87");
    expect (s, "B3", "-1.41");
    expect (s, "B4", "46045600");
    expect (s, "B5", "NYSE/NASDAQ");
    expect (s, "B6", "2025-09-26 22:00");
    put (s, "D1", "=STOCKHISTORY(\"AAPL\",DATE(2025,9,23),DATE(2025,9,25))");
    put (s, "G1", "=STOCKHISTORY(A1,DATE(2025,9,22),DATE(2025,9,26),0,0,1,5)");
    put (s, "J1", "=STOCKHISTORY(\"AAPL\",DATE(2025,9,19),DATE(2025,9,26),1,2,0,1)");
    put (s, "M1", "=STOCKHISTORY(\"ZZZZ\",DATE(2025,9,19))");
    book.recalculate ();
    expect (s, "D1", "Date");
    expect (s, "E1", "Close");
    expect (s, "E2", "254.43");
    expect (s, "E4", "256.87");
    expect (s, "D5", "");
    expect (s, "G1", "256.08");
    expect (s, "H5", "46045600");
    expect (s, "J1", "AAPL.US");
    expect (s, "J2", "Date");
    expect (s, "K4", "255.46");
    expect (s, "M1", "#N/A");
}

void test_offline_cache () {
    point_to (base_url);
    int before = hits;
    try {
        var r = LinkedHub.fetch_or_cache ("geography", "Q38");
        if (hits == before || r.status != "") Test.fail ();
    } catch (Error e) {
        Test.fail ();
    }
    point_to ("http://127.0.0.1:9");
    try {
        var c = LinkedHub.fetch_or_cache ("geography", "Q38");
        if (!c.status.has_prefix ("Offline") || c.field ("Population").number != 58993475) Test.fail ();
    } catch (Error e) {
        stderr.printf ("offline cache failed %s\n", e.message);
        Test.fail ();
    }
    try {
        LinkedHub.fetch_or_cache ("geography", "Q999999");
        Test.fail ();
    } catch (Error e) {
    }
    var book = new Workbook ();
    var s = book.add_sheet ("S");
    s.set_input (0, 0, "Nowhere");
    book.analysis.links[DataTypes.link_key (s, 0, 0)] = new DataTypeLink ("@geography", "", "Q999998");
    LinkedHub.get ().async_mode = true;
    s.set_input (0, 1, "=A1.Population");
    book.recalculate ();
    expect (s, "B1", "#GETTING_DATA");
    var loop = new MainLoop ();
    ulong h = LinkedHub.get ().updated.connect ((b) => loop.quit ());
    Timeout.add_seconds (20, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    LinkedHub.get ().disconnect (h);
    book.recalculate ();
    expect (s, "B1", "#N/A");
    if (!book.analysis.failures.has_key ("geography:Q999998")) Test.fail ();
    var hb = new Workbook ();
    var hs = hb.add_sheet ("H");
    hs.set_input (0, 0, "=STOCKHISTORY(\"AAPL\",DATE(2025,9,22),DATE(2025,9,26))");
    point_to (base_url);
    hb.recalculate ();
    expect (hs, "A1", "#GETTING_DATA");
    var loop2 = new MainLoop ();
    ulong h2 = LinkedHub.get ().updated.connect ((b) => loop2.quit ());
    Timeout.add_seconds (20, () => {
        loop2.quit ();
        return Source.REMOVE;
    });
    loop2.run ();
    LinkedHub.get ().disconnect (h2);
    hb.recalculate ();
    expect (hs, "A1", "Date");
    expect (hs, "B2", "256.08");
    expect (hs, "B6", "255.46");
    LinkedHub.get ().async_mode = false;
}

void test_config () {
    string dir = Path.build_filename (Environment.get_tmp_dir (), "ss-linked-conf-%d".printf (Random.int_range (0, 1000000)));
    DirUtils.create_with_parents (dir, 0700);
    string path = Path.build_filename (dir, "data-types.conf");
    try {
        FileUtils.set_contents (path, "[Geography]\nenabled=false\n[Stocks]\ndefault-suffix=.uk\n");
    } catch (Error e) {
        Test.fail ();
    }
    Environment.unset_variable ("SINGULARITY_WIKIDATA_ENDPOINT");
    Environment.set_variable ("SINGULARITY_DATATYPES_CONFIG", path, true);
    LinkedConfig.reset ();
    var c = LinkedConfig.get ();
    if (c.geography || c.default_suffix != ".uk" || c.source != path) {
        stderr.printf ("config geo=%s suffix=%s source=%s\n", c.geography.to_string (), c.default_suffix, c.source);
        Test.fail ();
    }
    if (LinkedHub.provider ("geography") != null) Test.fail ();
    if (StooqStocks.symbol ("VOD") != "vod.uk" || StooqStocks.symbol ("XNAS:MSFT") != "msft.uk" || StooqStocks.symbol ("^spx") != "^spx") {
        stderr.printf ("symbols %s %s %s\n", StooqStocks.symbol ("VOD"), StooqStocks.symbol ("XNAS:MSFT"), StooqStocks.symbol ("^spx"));
        Test.fail ();
    }
    Environment.unset_variable ("SINGULARITY_DATATYPES_CONFIG");
    FileUtils.remove (path);
    DirUtils.remove (dir);
    point_to (base_url);
}

int main (string[] args) {
    string cache = Path.build_filename (Environment.get_tmp_dir (), "ss-linked-cache-%d".printf (Random.int_range (0, 1000000)));
    Environment.set_variable ("XDG_CACHE_HOME", cache, true);
    Environment.set_variable ("XDG_CONFIG_HOME", cache + "-config", true);
    Test.init (ref args);
    LocaleInfo.set_c ();
    start_server ();
    Test.add_func ("/linked/geography", test_geography);
    Test.add_func ("/linked/stocks", test_stocks);
    Test.add_func ("/linked/offline", test_offline_cache);
    Test.add_func ("/linked/config", test_config);
    return Test.run ();
}
