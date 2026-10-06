namespace Singularity.Apps.Spreadsheet {

    public class WebFunctions {
        private static void add (string name, int min, int max, string category, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, category, syntax, summary, (owned) impl);
        }

        private static Value typed (string s) {
            double d = 0;
            string f = "";
            if (s.strip () != "" && Input.parse_number (s.strip (), out d, out f)) return Value.num (d);
            string u = s.strip ().up ();
            if (u == "TRUE" || u == "FALSE") return Value.boolean (u == "TRUE");
            return Value.str (s);
        }

        public static Value filter_xml (string xml, string xpath) {
            if (xml.strip () == "") return Value.err (ErrorKind.VALUE);
            Xml.Doc* doc = Xml.Parser.read_memory (xml, xml.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null) return Value.err (ErrorKind.VALUE);
            var ctx = new Xml.XPath.Context (doc);
            Xml.XPath.Object* res = ctx.eval_expression (xpath);
            if (res == null) {
                delete doc;
                return Value.err (ErrorKind.VALUE);
            }
            var items = new Gee.ArrayList<Value> ();
            switch (res->type) {
                case Xml.XPath.ObjectType.NODESET:
                    if (res->nodesetval != null) {
                        for (int i = 0; i < res->nodesetval->length (); i++) {
                            Xml.Node* node = res->nodesetval->item (i);
                            string content = node->get_content () ?? "";
                            items.add (typed (content));
                        }
                    }
                    break;
                case Xml.XPath.ObjectType.NUMBER:
                    items.add (Value.num (res->floatval));
                    break;
                case Xml.XPath.ObjectType.BOOLEAN:
                    items.add (Value.boolean (res->boolval != 0));
                    break;
                case Xml.XPath.ObjectType.STRING:
                    items.add (typed (res->stringval ?? ""));
                    break;
                default:
                    break;
            }
            delete res;
            delete doc;
            if (items.size == 0) return Value.err (ErrorKind.VALUE);
            if (items.size == 1) return items[0];
            var m = new Value[items.size, 1];
            for (int i = 0; i < items.size; i++) m[i, 0] = items[i];
            return Value.matrix (m);
        }

        public static Value web_service (string url) {
            string u = url.strip ();
            if (u.length > 2048) return Value.err (ErrorKind.VALUE);
            string scheme = Uri.peek_scheme (u) ?? "";
            if (scheme != "http" && scheme != "https") return Value.err (ErrorKind.VALUE);
            Bytes? bytes;
            var state = ImageCache.get_default ().lookup (u, out bytes);
            if (state == ImageCache.State.LOADING) return Value.err (ErrorKind.GETTING_DATA);
            if (state == ImageCache.State.FAILED || bytes == null) return Value.err (ErrorKind.VALUE);
            unowned uint8[] data = bytes.get_data ();
            var buf = new StringBuilder ();
            buf.append_len ((string) data, data.length);
            string text = buf.str;
            if (!text.validate () || text.char_count () > 32767) return Value.err (ErrorKind.VALUE);
            return Value.str (text);
        }

        public static void register () {
            add ("ENCODEURL", 1, 1, "Web", "ENCODEURL(text)", _("Encodes text for use in a URL"), (ev, a) => MoreMathFunctions.lift (ev, a, (v) => {
                if (v[0].is_error ()) return v[0];
                return Value.str (Uri.escape_string (Evaluator.to_text (v[0]), null, true));
            }));
            add ("FILTERXML", 2, 2, "Web", "FILTERXML(xml, xpath)", _("Extracts data from XML with an XPath"), (ev, a) => {
                Value? e;
                string xml = ev.arg_text (a[0], out e);
                if (e != null) return e;
                string xp = ev.arg_text (a[1], out e);
                if (e != null) return e;
                return filter_xml (xml, xp);
            });
            add ("WEBSERVICE", 1, 1, "Web", "WEBSERVICE(url)", _("Text returned by a web service"), (ev, a) => {
                Value? e;
                string url = ev.arg_text (a[0], out e);
                if (e != null) return e;
                return web_service (url);
            });
            CubeFunctions.register ();
            add ("RTD", 3, -1, "Lookup", "RTD(progid, server, topic1, [topic2], ...)", _("Real-time data from a COM automation server, which does not exist on this system"), (ev, a) => Value.err (ErrorKind.NA));
            add ("CALL", 1, -1, "Add-in", "CALL(register_id, [argument1], ...)", _("Calls a procedure in a Windows code library, which does not exist on this system"), (ev, a) => Value.err (ErrorKind.VALUE));
            add ("REGISTER.ID", 2, 3, "Add-in", "REGISTER.ID(module_text, procedure, [type_text])", _("Registers a procedure of a Windows code library, which does not exist on this system"), (ev, a) => Value.err (ErrorKind.VALUE));
            add ("STOCKHISTORY", 2, 11, "Financial", "STOCKHISTORY(stock, start_date, [end_date], [interval], [headers], [property0], ...)", _("Historical market data from an online financial data service, which is not available"), (ev, a) => Value.err (ErrorKind.NA));
            add ("INFO", 1, 1, "Information", "INFO(type_text)", _("Information about the operating environment"), (ev, a) => {
                Value? e;
                string t = ev.arg_text (a[0], out e).down ();
                if (e != null) return e;
                switch (t) {
                    case "directory":
                        string dir = Environment.get_current_dir ();
                        return Value.str (dir.has_suffix ("/") ? dir : dir + "/");
                    case "numfile": return Value.num (ev.book.sheets.size);
                    case "origin": return Value.str ("$A:$A$1");
                    case "osversion": return Value.str (Environment.get_os_info (OsInfoKey.PRETTY_NAME) ?? "Linux");
                    case "recalc": return Value.str (ev.book.manual_calc ? _("Manual") : _("Automatic"));
                    case "release": return Value.str ("16.0");
                    case "system": return Value.str ("pcdos");
                    case "memavail":
                    case "memused":
                    case "totmem":
                        return Value.err (ErrorKind.NA);
                }
                return Value.err (ErrorKind.VALUE);
            });
            add ("FORMULATEXT", 1, 1, "Lookup", "FORMULATEXT(reference)", _("The formula of a cell as text"), (ev, a) => {
                var v = ev.eval (a[0]);
                if (v.is_error ()) return v;
                if (v.kind != ValueKind.RANGE) return Value.err (ErrorKind.NA);
                var s = v.area.sheet ?? ev.sheet;
                var c = s.get_cell (v.area.r1, v.area.c1);
                if (c == null || c.formula == null) return Value.err (ErrorKind.NA);
                return Value.str (c.input);
            });
        }
    }
}
