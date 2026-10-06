namespace Singularity.Apps.Spreadsheet {

    [CCode (cname = "SS_SYSCONFDIR")]
    extern const string SS_SYSCONFDIR;

    public errordomain LinkedError {
        NOT_FOUND,
        NETWORK,
        FORMAT
    }

    public class LinkedRecord {
        public string kind;
        public string id;
        public string name = "";
        public string description = "";
        public Gee.ArrayList<string> order = new Gee.ArrayList<string> ();
        public Gee.HashMap<string, Value> fields = new Gee.HashMap<string, Value> ();
        public int64 fetched;
        public string status = "";

        public LinkedRecord (string kind, string id) {
            this.kind = kind;
            this.id = id;
        }

        public string key {
            owned get { return kind + ":" + id; }
        }

        public void set_field (string name, Value v) {
            if (v.kind == ValueKind.EMPTY) return;
            if (v.kind == ValueKind.TEXT && v.text == "") return;
            if (!fields.has_key (name)) order.add (name);
            fields[name] = v;
        }

        public Value? field (string name) {
            string k = name.strip ().casefold ();
            foreach (var n in order) if (n.casefold () == k) return fields[n];
            return null;
        }

        public string updated_text () {
            if (fetched <= 0) return "";
            return new DateTime.from_unix_local (fetched).format ("%Y-%m-%d %H:%M");
        }

        public string to_keyfile () {
            var kf = new KeyFile ();
            save_into (kf, "Record");
            return kf.to_data ();
        }

        public void save_into (KeyFile kf, string g) {
            kf.set_string (g, "kind", kind);
            kf.set_string (g, "id", id);
            kf.set_string (g, "name", name);
            kf.set_string (g, "description", description);
            kf.set_int64 (g, "fetched", fetched);
            string[] list = {};
            foreach (var n in order) {
                var v = fields[n];
                string t = v.kind == ValueKind.NUMBER ? "n" : v.kind == ValueKind.BOOL ? "b" : "s";
                string val = v.kind == ValueKind.NUMBER ? Value.format_number_general_full (v.number) : v.kind == ValueKind.BOOL ? (v.number != 0 ? "1" : "0") : v.display ();
                list += t + "\t" + n + "\t" + val;
            }
            kf.set_string_list (g, "fields", list);
        }

        public static LinkedRecord? load_from (KeyFile kf, string g) {
            try {
                var r = new LinkedRecord (kf.get_string (g, "kind"), kf.get_string (g, "id"));
                r.name = kf.get_string (g, "name");
                r.description = kf.has_key (g, "description") ? kf.get_string (g, "description") : "";
                r.fetched = kf.has_key (g, "fetched") ? kf.get_int64 (g, "fetched") : 0;
                foreach (string item in kf.get_string_list (g, "fields")) {
                    var p = item.split ("\t", 3);
                    if (p.length != 3) continue;
                    if (p[0] == "n") r.set_field (p[1], Value.num (double.parse (p[2])));
                    else if (p[0] == "b") r.set_field (p[1], Value.boolean (p[2] == "1"));
                    else r.set_field (p[1], Value.str (p[2]));
                }
                return r;
            } catch (Error e) {
                return null;
            }
        }
    }

    public class LinkedCandidate {
        public string id;
        public string label;
        public string description;

        public LinkedCandidate (string id, string label, string description) {
            this.id = id;
            this.label = label;
            this.description = description;
        }
    }

    public class LinkedConfig {
        public string wikidata = "https://query.wikidata.org/sparql";
        public string language = "";
        public string stooq_quote = "https://stooq.com/q/l/?s=%s&f=sd2t2ohlcvn&h&e=csv";
        public string stooq_history = "https://stooq.com/q/d/l/?s=%s&d1=%s&d2=%s&i=%s";
        public string default_suffix = ".us";
        public bool geography = true;
        public bool stocks = true;
        public string user_agent = "SingularitySpreadsheet/1.0 (linked data types)";
        public string source = "";

        private static LinkedConfig? current = null;

        public static void reset () {
            current = null;
        }

        public static string[] search_paths () {
            string[] paths = {};
            string? env = Environment.get_variable ("SINGULARITY_DATATYPES_CONFIG");
            if (env != null && env != "") paths += env;
            paths += Path.build_filename (Environment.get_user_config_dir (), "singularity", "spreadsheet", "data-types.conf");
            paths += Path.build_filename (SS_SYSCONFDIR, "singularity", "spreadsheet", "data-types.conf");
            return paths;
        }

        public static LinkedConfig get () {
            if (current != null) return current;
            var c = new LinkedConfig ();
            foreach (string path in search_paths ()) {
                if (!FileUtils.test (path, FileTest.EXISTS)) continue;
                var kf = new KeyFile ();
                try {
                    kf.load_from_file (path, KeyFileFlags.NONE);
                    if (kf.has_group ("Geography") && kf.has_key ("Geography", "enabled")) c.geography = kf.get_boolean ("Geography", "enabled");
                    if (kf.has_group ("Geography") && kf.has_key ("Geography", "endpoint")) c.wikidata = kf.get_string ("Geography", "endpoint");
                    if (kf.has_group ("Geography") && kf.has_key ("Geography", "language")) c.language = kf.get_string ("Geography", "language");
                    if (kf.has_group ("Stocks") && kf.has_key ("Stocks", "enabled")) c.stocks = kf.get_boolean ("Stocks", "enabled");
                    if (kf.has_group ("Stocks") && kf.has_key ("Stocks", "quote")) c.stooq_quote = kf.get_string ("Stocks", "quote");
                    if (kf.has_group ("Stocks") && kf.has_key ("Stocks", "history")) c.stooq_history = kf.get_string ("Stocks", "history");
                    if (kf.has_group ("Stocks") && kf.has_key ("Stocks", "default-suffix")) c.default_suffix = kf.get_string ("Stocks", "default-suffix");
                    if (kf.has_group ("Network") && kf.has_key ("Network", "user-agent")) c.user_agent = kf.get_string ("Network", "user-agent");
                    c.source = path;
                } catch (Error e) {
                }
                break;
            }
            string? w = Environment.get_variable ("SINGULARITY_WIKIDATA_ENDPOINT");
            if (w != null && w != "") c.wikidata = w;
            string? q = Environment.get_variable ("SINGULARITY_STOCKS_QUOTE_URL");
            if (q != null && q != "") c.stooq_quote = q;
            string? h = Environment.get_variable ("SINGULARITY_STOCKS_HISTORY_URL");
            if (h != null && h != "") c.stooq_history = h;
            if (c.language == "") {
                string lang = "en";
                foreach (string l in Intl.get_language_names ()) {
                    if (l == "C" || l == "POSIX") continue;
                    lang = l.split ("_")[0].split (".")[0].split ("@")[0];
                    break;
                }
                c.language = lang;
            }
            current = c;
            return c;
        }
    }

    public class LinkedHttp {
        public static string get (string url, string accept) throws Error {
            var session = new Soup.Session ();
            session.timeout = 20;
            session.user_agent = LinkedConfig.get ().user_agent;
            var msg = new Soup.Message ("GET", url);
            if (msg == null) throw new LinkedError.NETWORK (_("The address %s is not valid.").printf (url));
            msg.request_headers.append ("Accept", accept);
            Bytes bytes;
            try {
                bytes = session.send_and_read (msg, null);
            } catch (Error e) {
                throw new LinkedError.NETWORK (e.message);
            }
            if (msg.status_code < 200 || msg.status_code >= 300) throw new LinkedError.NETWORK (_("The service answered %u %s.").printf (msg.status_code, msg.reason_phrase ?? ""));
            unowned uint8[] data = bytes.get_data ();
            var copy = new uint8[data.length + 1];
            Memory.copy (copy, data, data.length);
            copy[data.length] = 0;
            return ((string) copy).make_valid ();
        }
    }

    public interface LinkedProvider : Object {
        public abstract string kind { get; }
        public abstract Gee.List<LinkedCandidate> search (string text) throws Error;
        public abstract LinkedRecord fetch (string id) throws Error;
    }

    public class WikidataGeography : Object, LinkedProvider {
        public string kind {
            get { return "geography"; }
        }

        private static string sparql_string (string s) {
            return "\"" + s.replace ("\\", "\\\\").replace ("\"", "\\\"") + "\"";
        }

        public static Json.Array bindings (string json) throws Error {
            var parser = new Json.Parser ();
            try {
                parser.load_from_data (json);
            } catch (Error e) {
                throw new LinkedError.FORMAT (_("The geography service returned data that could not be read."));
            }
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) throw new LinkedError.FORMAT (_("The geography service returned data that could not be read."));
            var results = root.get_object ().get_object_member ("results");
            if (results == null) throw new LinkedError.FORMAT (_("The geography service returned data that could not be read."));
            return results.get_array_member ("bindings");
        }

        public static string? binding (Json.Object row, string name) {
            if (!row.has_member (name)) return null;
            var o = row.get_object_member (name);
            if (o == null || !o.has_member ("value")) return null;
            return o.get_string_member ("value");
        }

        private string run (string query) throws Error {
            var c = LinkedConfig.get ();
            string sep = c.wikidata.contains ("?") ? "&" : "?";
            string url = c.wikidata + sep + "format=json&query=" + Uri.escape_string (query, null, false);
            return LinkedHttp.get (url, "application/sparql-results+json");
        }

        public static string entity_id (string uri) {
            int slash = uri.last_index_of ("/");
            return slash >= 0 ? uri.substring (slash + 1) : uri;
        }

        public Gee.List<LinkedCandidate> search (string text) throws Error {
            var c = LinkedConfig.get ();
            string lang = c.language;
            string q = """SELECT ?item ?itemLabel ?itemDescription ?num WHERE {
  SERVICE wikibase:mwapi {
    bd:serviceParam wikibase:endpoint "www.wikidata.org"; wikibase:api "EntitySearch"; mwapi:search %s; mwapi:language "%s".
    ?item wikibase:apiOutputItem mwapi:item.
    ?num wikibase:apiOrdinal true.
  }
  ?item wdt:P31/wdt:P279? ?class.
  VALUES ?class { wd:Q6256 wd:Q3624078 wd:Q515 wd:Q1549591 wd:Q5119 wd:Q7275 wd:Q35657 wd:Q107390 wd:Q34876 wd:Q82794 wd:Q5107 wd:Q15284 wd:Q23442 wd:Q56061 wd:Q486972 wd:Q10864048 }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "%s,en". }
} ORDER BY ?num LIMIT 20""".printf (sparql_string (text.strip ()), lang, lang);
            var rows = bindings (run (q));
            var out_list = new Gee.ArrayList<LinkedCandidate> ();
            var seen = new Gee.HashSet<string> ();
            for (uint i = 0; i < rows.get_length (); i++) {
                var row = rows.get_object_element (i);
                string? item = binding (row, "item");
                if (item == null) continue;
                string id = entity_id (item);
                if (!seen.add (id)) continue;
                out_list.add (new LinkedCandidate (id, binding (row, "itemLabel") ?? id, binding (row, "itemDescription") ?? ""));
                if (out_list.size >= 8) break;
            }
            return out_list;
        }

        private static string label_optional (string prop, string v, string lang) {
            return "  OPTIONAL { ?item wdt:%s ?%s. ?%s rdfs:label ?%sLabel. FILTER(LANG(?%sLabel) IN (\"%s\", \"en\")) }\n".printf (prop, v, v, v, v, lang);
        }

        public LinkedRecord fetch (string id) throws Error {
            if (!Regex.match_simple ("^Q[0-9]+$", id)) throw new LinkedError.NOT_FOUND (_("\"%s\" is not a Wikidata item.").printf (id));
            var c = LinkedConfig.get ();
            string lang = c.language;
            var sb = new StringBuilder ();
            sb.append ("SELECT ?itemLabel ?itemDescription (SAMPLE(?population) AS ?population) (SAMPLE(?area) AS ?area) (SAMPLE(?capitalLabel) AS ?capital) (SAMPLE(?countryLabel) AS ?country) (SAMPLE(?continentLabel) AS ?continent) (SAMPLE(?coord) AS ?coord) (GROUP_CONCAT(DISTINCT ?currencyLabel; separator=\", \") AS ?currency) (GROUP_CONCAT(DISTINCT ?languageLabel; separator=\", \") AS ?languages) (SAMPLE(?flag) AS ?flag) (SAMPLE(?leaderLabel) AS ?leader) (SAMPLE(?headLabel) AS ?head) (GROUP_CONCAT(DISTINCT ?tzLabel; separator=\", \") AS ?timezones) (SAMPLE(?gdp) AS ?gdp) (SAMPLE(?iso) AS ?iso) (SAMPLE(?callingCode) AS ?calling) (SAMPLE(?elevation) AS ?elevation) (SAMPLE(?website) AS ?website) WHERE {\n");
            sb.append ("  BIND(wd:%s AS ?item)\n".printf (id));
            sb.append ("  OPTIONAL { ?item wdt:P1082 ?population. }\n");
            sb.append ("  OPTIONAL { ?item wdt:P2046 ?area. }\n");
            sb.append ("  OPTIONAL { ?item wdt:P625 ?coord. }\n");
            sb.append ("  OPTIONAL { ?item wdt:P41 ?flag. }\n");
            sb.append ("  OPTIONAL { ?item wdt:P2131 ?gdp. }\n");
            sb.append ("  OPTIONAL { ?item wdt:P297 ?iso. }\n");
            sb.append ("  OPTIONAL { ?item wdt:P474 ?callingCode. }\n");
            sb.append ("  OPTIONAL { ?item wdt:P2044 ?elevation. }\n");
            sb.append ("  OPTIONAL { ?item wdt:P856 ?website. }\n");
            sb.append (label_optional ("P36", "capital", lang));
            sb.append (label_optional ("P17", "country", lang));
            sb.append (label_optional ("P30", "continent", lang));
            sb.append (label_optional ("P38", "currency", lang));
            sb.append (label_optional ("P37", "language", lang));
            sb.append (label_optional ("P6", "leader", lang));
            sb.append (label_optional ("P35", "head", lang));
            sb.append (label_optional ("P421", "tz", lang));
            sb.append ("  SERVICE wikibase:label { bd:serviceParam wikibase:language \"%s,en\". ?item rdfs:label ?itemLabel. ?item schema:description ?itemDescription. }\n".printf (lang));
            sb.append ("} GROUP BY ?itemLabel ?itemDescription LIMIT 1");
            var rows = bindings (run (sb.str));
            if (rows.get_length () == 0) throw new LinkedError.NOT_FOUND (_("No data was found for %s.").printf (id));
            var row = rows.get_object_element (0);
            var r = new LinkedRecord ("geography", id);
            r.name = binding (row, "itemLabel") ?? id;
            r.description = binding (row, "itemDescription") ?? "";
            r.set_field (_("Name"), Value.str (r.name));
            r.set_field (_("Description"), Value.str (r.description));
            number_field (r, _("Population"), binding (row, "population"));
            number_field (r, _("Area"), binding (row, "area"));
            text_field (r, _("Capital"), binding (row, "capital"));
            text_field (r, _("Country"), binding (row, "country"));
            text_field (r, _("Continent"), binding (row, "continent"));
            string? coord = binding (row, "coord");
            if (coord != null && coord.has_prefix ("Point(")) {
                var parts = coord.substring (6, coord.length - 7).split (" ");
                if (parts.length == 2) {
                    r.set_field (_("Latitude"), Value.num (double.parse (parts[1])));
                    r.set_field (_("Longitude"), Value.num (double.parse (parts[0])));
                }
            }
            text_field (r, _("Currency"), binding (row, "currency"));
            text_field (r, _("Official language"), binding (row, "languages"));
            text_field (r, _("Leader"), binding (row, "leader") ?? binding (row, "head"));
            text_field (r, _("Time zone"), binding (row, "timezones"));
            number_field (r, _("GDP"), binding (row, "gdp"));
            text_field (r, _("ISO code"), binding (row, "iso"));
            text_field (r, _("Calling code"), binding (row, "calling"));
            number_field (r, _("Elevation"), binding (row, "elevation"));
            text_field (r, _("Website"), binding (row, "website"));
            string? flag = binding (row, "flag");
            if (flag != null) r.set_field (_("Flag"), Value.str (flag.replace ("http://", "https://")));
            r.set_field (_("Wikidata ID"), Value.str (id));
            r.fetched = new DateTime.now_utc ().to_unix ();
            return r;
        }

        private static void text_field (LinkedRecord r, string name, string? v) {
            if (v != null && v.strip () != "") r.set_field (name, Value.str (v.strip ()));
        }

        private static void number_field (LinkedRecord r, string name, string? v) {
            if (v == null) return;
            double d;
            if (double.try_parse (v, out d)) r.set_field (name, Value.num (d));
        }
    }

    public class StooqStocks : Object, LinkedProvider {
        public string kind {
            get { return "stocks"; }
        }

        public static string symbol (string text) {
            string t = text.strip ().down ();
            int colon = t.index_of (":");
            if (colon >= 0) t = t.substring (colon + 1);
            if (t.contains (".") || t.has_prefix ("^")) return t;
            return t + LinkedConfig.get ().default_suffix;
        }

        public static string exchange (string sym) {
            int dot = sym.last_index_of (".");
            if (dot < 0) return sym.has_prefix ("^") ? _("Index") : "";
            switch (sym.substring (dot + 1)) {
                case "us": return "NYSE/NASDAQ";
                case "uk": return "LSE";
                case "de": return "XETRA";
                case "jp": return "TSE";
                case "pl": return "GPW";
                case "hk": return "HKEX";
                case "hu": return "BSE";
                case "f": return _("Forex");
                default: return sym.substring (dot + 1).up ();
            }
        }

        public static Gee.List<Gee.List<string>> csv (string text) {
            var out_rows = new Gee.ArrayList<Gee.List<string>> ();
            foreach (var r in Csv.parse (text, ',')) out_rows.add (r);
            return out_rows;
        }

        private static string url (string pattern, string[] args) {
            string u = pattern;
            foreach (string a in args) {
                int i = u.index_of ("%s");
                if (i < 0) break;
                u = u.substring (0, i) + Uri.escape_string (a, null, false) + u.substring (i + 2);
            }
            return u;
        }

        public Gee.List<LinkedCandidate> search (string text) throws Error {
            var rec = fetch (symbol (text));
            var list = new Gee.ArrayList<LinkedCandidate> ();
            list.add (new LinkedCandidate (rec.id, rec.name, exchange (rec.id)));
            return list;
        }

        public static double parse_num (string s) {
            double d;
            if (double.try_parse (s.strip (), out d)) return d;
            return double.NAN;
        }

        public static Gee.List<Gee.List<string>> history_rows (string sym, double start, double end, string interval) throws Error {
            var c = LinkedConfig.get ();
            string text = LinkedHttp.get (url (c.stooq_history, { sym, ymd (start), ymd (end), interval }), "text/csv");
            var rows = csv (text);
            if (rows.size == 0 || rows[0].size < 5 || rows[0][0].down () != "date") throw new LinkedError.NOT_FOUND (_("No price history was found for %s.").printf (sym.up ()));
            return rows;
        }

        public static string ymd (double serial) {
            int y, m, d;
            DateSerial.to_ymd (Math.floor (serial), out y, out m, out d);
            return "%04d%02d%02d".printf (y, m, d);
        }

        public static double parse_date (string s) {
            var p = s.strip ().split ("-");
            if (p.length != 3) return double.NAN;
            return DateSerial.from_ymd (int.parse (p[0]), int.parse (p[1]), int.parse (p[2]));
        }

        private static string col_of (Gee.HashMap<string, int> idx, Gee.List<string> row, string name) {
            return idx.has_key (name) && idx[name] < row.size ? row[idx[name]].strip () : "";
        }

        public LinkedRecord fetch (string id) throws Error {
            string sym = symbol (id);
            var c = LinkedConfig.get ();
            string text = LinkedHttp.get (url (c.stooq_quote, { sym }), "text/csv");
            var rows = csv (text);
            if (rows.size < 2) throw new LinkedError.FORMAT (_("The stocks service returned data that could not be read."));
            var head = rows[0];
            var row = rows[1];
            var idx = new Gee.HashMap<string, int> ();
            for (int i = 0; i < head.size; i++) idx[head[i].strip ().down ()] = i;
            string close = col_of (idx, row, "close");
            if (close == "" || close.up () == "N/D") throw new LinkedError.NOT_FOUND (_("The stock %s was not found.").printf (sym.up ()));
            var r = new LinkedRecord ("stocks", sym);
            string nm = col_of (idx, row, "name");
            r.name = nm != "" && nm.up () != "N/D" ? nm : sym.up ();
            r.description = exchange (sym);
            double price = parse_num (close);
            r.set_field (_("Name"), Value.str (r.name));
            r.set_field (_("Ticker symbol"), Value.str (sym.up ()));
            r.set_field (_("Exchange"), Value.str (exchange (sym)));
            r.set_field (_("Price"), Value.num (price));
            foreach (string f in new string[] { "open", "high", "low" }) {
                double v = parse_num (col_of (idx, row, f));
                if (!v.is_nan ()) r.set_field (f == "open" ? _("Open") : f == "high" ? _("High") : _("Low"), Value.num (v));
            }
            double vol = parse_num (col_of (idx, row, "volume"));
            if (!vol.is_nan ()) r.set_field (_("Volume"), Value.num (vol));
            double day = parse_date (col_of (idx, row, "date"));
            string time = col_of (idx, row, "time");
            if (!day.is_nan ()) {
                double frac = 0;
                var tp = time.split (":");
                if (tp.length == 3) frac = (int.parse (tp[0]) * 3600 + int.parse (tp[1]) * 60 + int.parse (tp[2])) / 86400.0;
                r.set_field (_("Last trade time"), Value.num (day + frac));
            }
            if (!day.is_nan ()) {
                try {
                    var hist = history_rows (sym, day - 12, day, "d");
                    double prev = double.NAN;
                    for (int i = 1; i < hist.size; i++) {
                        if (hist[i].size < 5) continue;
                        double d = parse_date (hist[i][0]);
                        if (!d.is_nan () && d < day) prev = parse_num (hist[i][4]);
                    }
                    if (!prev.is_nan () && prev != 0) {
                        r.set_field (_("Previous close"), Value.num (prev));
                        r.set_field (_("Change"), Value.num (price - prev));
                        r.set_field (_("Change (%)"), Value.num ((price - prev) / prev));
                    }
                } catch (Error e) {
                }
            }
            r.fetched = new DateTime.now_utc ().to_unix ();
            return r;
        }
    }

    public class LinkedHub : Object {
        private static LinkedHub? instance = null;
        public bool async_mode;

        public signal void updated (Workbook book);

        public static LinkedHub get () {
            if (instance == null) instance = new LinkedHub ();
            return instance;
        }

        public static LinkedProvider? provider (string kind) {
            var c = LinkedConfig.get ();
            if (kind == "geography" && c.geography) return new WikidataGeography ();
            if (kind == "stocks" && c.stocks) return new StooqStocks ();
            return null;
        }

        public static string cache_path (string kind, string id) {
            string safe = id.replace ("/", "_").replace ("\\", "_");
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-spreadsheet", "linked", kind, safe + ".ini");
        }

        public static void write_cache (LinkedRecord r) {
            string path = cache_path (r.kind, r.id);
            DirUtils.create_with_parents (Path.get_dirname (path), 0755);
            try {
                FileUtils.set_contents (path, r.to_keyfile ());
            } catch (Error e) {
            }
        }

        public static LinkedRecord? read_cache (string kind, string id) {
            string path = cache_path (kind, id);
            if (!FileUtils.test (path, FileTest.EXISTS)) return null;
            var kf = new KeyFile ();
            try {
                kf.load_from_file (path, KeyFileFlags.NONE);
            } catch (Error e) {
                return null;
            }
            return LinkedRecord.load_from (kf, "Record");
        }

        public static LinkedRecord fetch_or_cache (string kind, string id) throws Error {
            var p = provider (kind);
            if (p == null) throw new LinkedError.NETWORK (_("This data type is turned off on this system."));
            try {
                var r = p.fetch (id);
                write_cache (r);
                return r;
            } catch (Error e) {
                var cached = read_cache (kind, id);
                if (cached != null) {
                    cached.status = _("Offline: showing data from %s").printf (cached.updated_text ());
                    return cached;
                }
                throw e;
            }
        }

        public delegate void Done (LinkedRecord? record, string error);

        public void fetch_async (Workbook book, string kind, string id, owned Done done) {
            string key = kind + ":" + id;
            book.analysis.loading.add (key);
            Done cb = (owned) done;
            new Thread<bool> ("linked-fetch", () => {
                LinkedRecord? rec = null;
                string err = "";
                try {
                    rec = fetch_or_cache (kind, id);
                } catch (Error e) {
                    err = e.message;
                }
                Idle.add (() => {
                    book.analysis.loading.remove (key);
                    if (rec != null) book.analysis.records[key] = rec;
                    else book.analysis.failures[key] = err;
                    book.structure_changed = true;
                    cb (rec, err);
                    updated (book);
                    return Source.REMOVE;
                });
                return true;
            });
        }

        public delegate void Found (Gee.List<LinkedCandidate> candidates, string error);

        public void search_async (string kind, string text, owned Found done) {
            Found cb = (owned) done;
            new Thread<bool> ("linked-search", () => {
                var list = new Gee.ArrayList<LinkedCandidate> ();
                string err = "";
                var p = provider (kind);
                if (p == null) {
                    err = _("This data type is turned off on this system.");
                } else {
                    try {
                        list.add_all (p.search (text));
                    } catch (Error e) {
                        err = e.message;
                    }
                }
                Idle.add (() => {
                    cb (list, err);
                    return Source.REMOVE;
                });
                return true;
            });
        }

        public static LinkedRecord? record_for (Workbook book, string kind, string id) {
            string key = kind + ":" + id;
            var r = book.analysis.records[key];
            if (r != null) return r;
            if (book.analysis.loading.contains (key)) return null;
            var cached = read_cache (kind, id);
            if (cached != null) {
                book.analysis.records[key] = cached;
                return cached;
            }
            return null;
        }

        public static void link (Workbook book, Sheet s, int r, int c, LinkedRecord rec) {
            book.analysis.records[rec.key] = rec;
            book.analysis.links[DataTypes.link_key (s, r, c)] = new DataTypeLink ("@" + rec.kind, "", rec.id);
            book.structure_changed = true;
        }

        public static int refresh_sync (Workbook book) {
            int n = 0;
            var keys = new Gee.HashSet<string> ();
            foreach (var l in book.analysis.links.values) if (l.source.has_prefix ("@")) keys.add (l.source.substring (1) + ":" + l.key);
            foreach (string k in keys) {
                int colon = k.index_of (":");
                try {
                    var rec = fetch_or_cache (k.substring (0, colon), k.substring (colon + 1));
                    book.analysis.records[k] = rec;
                    n++;
                } catch (Error e) {
                    book.analysis.failures[k] = e.message;
                }
            }
            book.structure_changed = true;
            return n;
        }

        public void refresh_async (Workbook book, owned Done? each = null) {
            var keys = new Gee.HashSet<string> ();
            foreach (var l in book.analysis.links.values) if (l.source.has_prefix ("@")) keys.add (l.source.substring (1) + ":" + l.key);
            foreach (string k in keys) {
                int colon = k.index_of (":");
                fetch_async (book, k.substring (0, colon), k.substring (colon + 1), (rec, err) => {
                    if (each != null) each (rec, err);
                });
            }
        }

        public static Value history (Evaluator ev, string sym, double start, double end, int interval, int headers, int[] props) {
            var book = ev.book;
            string iv = interval == 1 ? "w" : interval == 2 ? "m" : "d";
            string key = "%s|%s|%s|%s".printf (sym, StooqStocks.ymd (start), StooqStocks.ymd (end), iv);
            Gee.List<Gee.List<string>>? rows = book.analysis.histories[key];
            if (rows == null) {
                if (book.analysis.history_errors.has_key (key)) return Value.err (ErrorKind.NA);
                if (LinkedHub.get ().async_mode) {
                    if (!book.analysis.loading.contains ("history:" + key)) {
                        book.analysis.loading.add ("history:" + key);
                        new Thread<bool> ("linked-history", () => {
                            Gee.List<Gee.List<string>>? got = null;
                            string err = "";
                            try {
                                got = StooqStocks.history_rows (sym, start, end, iv);
                            } catch (Error e) {
                                err = e.message;
                            }
                            Idle.add (() => {
                                book.analysis.loading.remove ("history:" + key);
                                if (got != null) book.analysis.histories[key] = got;
                                else book.analysis.history_errors[key] = err;
                                book.structure_changed = true;
                                LinkedHub.get ().updated (book);
                                return Source.REMOVE;
                            });
                            return true;
                        });
                    }
                    return Value.err (ErrorKind.GETTING_DATA);
                }
                try {
                    rows = StooqStocks.history_rows (sym, start, end, iv);
                    book.analysis.histories[key] = rows;
                } catch (Error e) {
                    book.analysis.history_errors[key] = e.message;
                    return Value.err (ErrorKind.NA);
                }
            }
            string[] names = { _("Date"), _("Close"), _("Open"), _("High"), _("Low"), _("Volume") };
            int[] cols = { 0, 4, 1, 2, 3, 5 };
            var data = new Gee.ArrayList<Gee.List<string>> ();
            for (int i = 1; i < rows.size; i++) {
                if (rows[i].size < 5) continue;
                double d = StooqStocks.parse_date (rows[i][0]);
                if (d.is_nan () || d < Math.floor (start) || d > Math.floor (end)) continue;
                data.add (rows[i]);
            }
            if (data.size == 0) return Value.err (ErrorKind.CALC);
            int extra = headers == 2 ? 2 : headers == 1 ? 1 : 0;
            var m = new Value[data.size + extra, props.length];
            for (int j = 0; j < props.length; j++) {
                if (headers == 2) m[0, j] = j == 0 ? Value.str (sym.up ()) : Value.empty ();
                if (headers >= 1) m[extra - 1, j] = Value.str (names[props[j]]);
            }
            for (int i = 0; i < data.size; i++) {
                for (int j = 0; j < props.length; j++) {
                    int col = cols[props[j]];
                    string cell = col < data[i].size ? data[i][col] : "";
                    double v = props[j] == 0 ? StooqStocks.parse_date (cell) : StooqStocks.parse_num (cell);
                    m[extra + i, j] = v.is_nan () ? Value.err (ErrorKind.NA) : Value.num (v);
                }
            }
            return Value.matrix (m);
        }
    }
}
