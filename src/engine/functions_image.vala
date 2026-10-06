namespace Singularity.Apps.Spreadsheet {

    public class ImageCache : Object {
        private static ImageCache? _default;
        private Gee.HashMap<string, Bytes> done = new Gee.HashMap<string, Bytes> ();
        private Gee.HashSet<string> pending = new Gee.HashSet<string> ();
        private Gee.HashSet<string> failed = new Gee.HashSet<string> ();
        public bool network = true;

        public signal void loaded (string source);

        public static ImageCache get_default () {
            if (_default == null) _default = new ImageCache ();
            return _default;
        }

        public enum State {
            READY,
            LOADING,
            FAILED
        }

        public static Bytes? decode_data_uri (string uri) {
            int comma = uri.index_of_char (',');
            if (!uri.has_prefix ("data:") || comma < 0) return null;
            string meta = uri.substring (5, comma - 5);
            string payload = uri.substring (comma + 1);
            if (meta.has_suffix (";base64")) {
                var clean = new StringBuilder ();
                for (int i = 0; i < payload.length; i++) if (!payload[i].isspace ()) clean.append_c (payload[i]);
                return new Bytes (Base64.decode (clean.str));
            }
            string? raw = Uri.unescape_string (payload);
            return raw != null ? new Bytes (raw.data) : null;
        }

        public State lookup (string source, out Bytes? data) {
            data = null;
            if (done.has_key (source)) {
                data = done[source];
                return State.READY;
            }
            if (failed.contains (source)) return State.FAILED;
            if (pending.contains (source)) return State.LOADING;
            string s = source.strip ();
            if (s.has_prefix ("data:")) {
                var b = decode_data_uri (s);
                if (b == null || b.length == 0) {
                    failed.add (source);
                    return State.FAILED;
                }
                done[source] = b;
                data = b;
                return State.READY;
            }
            if (s.has_prefix ("file://") || s.has_prefix ("/")) {
                try {
                    var f = s.has_prefix ("/") ? File.new_for_path (s) : File.new_for_uri (s);
                    uint8[] contents;
                    f.load_contents (null, out contents, null);
                    var b = new Bytes (contents);
                    done[source] = b;
                    data = b;
                    return State.READY;
                } catch (Error e) {
                    failed.add (source);
                    return State.FAILED;
                }
            }
            if ((s.has_prefix ("https://") || s.has_prefix ("http://")) && network) {
                pending.add (source);
                requests++;
                fetch.begin (source);
                return State.LOADING;
            }
            failed.add (source);
            return State.FAILED;
        }

        private async void fetch (string source) {
            try {
                var session = new Soup.Session ();
                session.timeout = 30;
                session.user_agent = "Singularity-Spreadsheet";
                var msg = new Soup.Message ("GET", source);
                if (msg == null) throw new IOError.INVALID_ARGUMENT ("bad address");
                var bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
                pending.remove (source);
                if (msg.status_code >= 200 && msg.status_code < 300 && bytes.length > 0) done[source] = bytes;
                else failed.add (source);
            } catch (Error e) {
                pending.remove (source);
                failed.add (source);
            }
            loaded (source);
        }

        public void put (string source, Bytes data) {
            done[source] = data;
        }

        public void forget (string source) {
            done.unset (source);
            failed.remove (source);
        }

        public int requests { get; private set; }
    }

    public class ImageFunctions {
        public static void register () {
            Functions.add ("IMAGE", 1, 5, "Lookup", "IMAGE(source, [alt_text], [sizing], [height], [width])", _("Shows a picture from a web address in the cell"), (ev, a) => {
                Value? err;
                string source = ev.arg_text (a[0], out err);
                if (err != null) return err;
                if (source.strip () == "") return Value.err (ErrorKind.VALUE);
                string alt = "";
                if (a.length > 1 && a[1].kind != NodeKind.MISSING) {
                    alt = ev.arg_text (a[1], out err);
                    if (err != null) return err;
                }
                int sizing = 0;
                if (a.length > 2 && a[2].kind != NodeKind.MISSING) {
                    var e = ev.arg_int (a[2], out sizing);
                    if (e != null) return e;
                }
                if (sizing < 0 || sizing > 3) return Value.err (ErrorKind.VALUE);
                double height = 0, width = 0;
                if (a.length > 3 && a[3].kind != NodeKind.MISSING) {
                    var e = ev.arg_number (a[3], out height);
                    if (e != null) return e;
                }
                if (a.length > 4 && a[4].kind != NodeKind.MISSING) {
                    var e = ev.arg_number (a[4], out width);
                    if (e != null) return e;
                }
                if (sizing == 3 && height <= 0 && width <= 0) return Value.err (ErrorKind.VALUE);
                if (height < 0 || width < 0) return Value.err (ErrorKind.VALUE);
                Bytes? data;
                var state = ImageCache.get_default ().lookup (source, out data);
                if (state == ImageCache.State.LOADING) return Value.err (ErrorKind.GETTING_DATA);
                if (state == ImageCache.State.FAILED || data == null) return Value.err (ErrorKind.VALUE);
                var v = Value.str (alt);
                v.image = data;
                v.image_sizing = sizing;
                v.image_height = height;
                v.image_width = width;
                return v;
            });
        }
    }
}
