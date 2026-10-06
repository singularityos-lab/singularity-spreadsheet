namespace Singularity.Apps.Spreadsheet {

    public struct Cplx {
        public double re;
        public double im;

        public Cplx (double re, double im) {
            this.re = re;
            this.im = im;
        }

        public double abs () {
            return Math.hypot (re, im);
        }

        public double arg () {
            return Math.atan2 (im, re);
        }

        public Cplx add (Cplx o) {
            return Cplx (re + o.re, im + o.im);
        }

        public Cplx sub (Cplx o) {
            return Cplx (re - o.re, im - o.im);
        }

        public Cplx mul (Cplx o) {
            return Cplx (re * o.re - im * o.im, re * o.im + im * o.re);
        }

        public Cplx div (Cplx o) {
            double d = o.re * o.re + o.im * o.im;
            return Cplx ((re * o.re + im * o.im) / d, (im * o.re - re * o.im) / d);
        }

        public Cplx exp () {
            double e = Math.exp (re);
            return Cplx (e * Math.cos (im), e * Math.sin (im));
        }

        public Cplx ln () {
            return Cplx (Math.log (abs ()), arg ());
        }

        public Cplx sin () {
            return Cplx (Math.sin (re) * Math.cosh (im), Math.cos (re) * Math.sinh (im));
        }

        public Cplx cos () {
            return Cplx (Math.cos (re) * Math.cosh (im), -Math.sin (re) * Math.sinh (im));
        }

        public Cplx sinh () {
            return Cplx (Math.sinh (re) * Math.cos (im), Math.cosh (re) * Math.sin (im));
        }

        public Cplx cosh () {
            return Cplx (Math.cosh (re) * Math.cos (im), Math.sinh (re) * Math.sin (im));
        }

        public Cplx pow (double n) {
            if (re == 0 && im == 0) return Cplx (0, 0);
            double r = Math.pow (abs (), n);
            double t = arg () * n;
            return Cplx (r * Math.cos (t), r * Math.sin (t));
        }
    }

    public class EngineeringFunctions {
        private static void add (string name, int min, int max, string syntax, string summary, owned FnImpl impl) {
            Functions.add (name, min, max, "Engineering", syntax, summary, (owned) impl);
        }

        private static Value lift (Evaluator ev, Node[] a, ScalarFn f) {
            return MoreMathFunctions.lift (ev, a, f);
        }

        private static Value? num (Value v, out double d) {
            return Evaluator.to_number (v, out d);
        }

        private static Value? num_or (Value v, double def, out double d) {
            return MoreMathFunctions.num_or (v, def, out d);
        }

        private static Value opt (Value[] v, int i) {
            return i < v.length ? v[i] : Value.missing ();
        }

        private static int bits_of (int radix) {
            return radix == 2 ? 10 : (radix == 8 ? 30 : 40);
        }

        private static Value? parse_radix (Value v, int radix, out double result) {
            result = 0;
            if (v.is_error ()) return v;
            if (v.kind == ValueKind.BOOL) return Value.err (ErrorKind.VALUE);
            string t = Evaluator.to_text (v).strip ().up ();
            if (t.length > 10) return Value.err (ErrorKind.NUM);
            double n = 0;
            for (int i = 0; i < t.length; i++) {
                char c = t[i];
                int d = c.isdigit () ? c - '0' : (c >= 'A' && c <= 'F' ? c - 'A' + 10 : 99);
                if (d >= radix) return Value.err (ErrorKind.NUM);
                n = n * radix + d;
            }
            int bits = bits_of (radix);
            double full = Math.pow (2, bits);
            if (t.length == 10 && n >= full / 2) n -= full;
            result = n;
            return null;
        }

        private static Value format_radix (double n, int radix, Value places_v) {
            int bits = bits_of (radix);
            double half = Math.pow (2, bits - 1);
            n = Math.trunc (n);
            if (n < -half || n >= half) return Value.err (ErrorKind.NUM);
            string digits = "0123456789ABCDEF";
            if (n < 0) {
                uint64 x = (uint64) (n + 2 * half);
                var sb = new StringBuilder ();
                for (int i = 0; i < 10; i++) {
                    sb.prepend_c (digits[(int) (x % radix)]);
                    x /= radix;
                }
                return Value.str (sb.str);
            }
            var sb2 = new StringBuilder ();
            uint64 y = (uint64) n;
            do {
                sb2.prepend_c (digits[(int) (y % radix)]);
                y /= radix;
            } while (y > 0);
            if (MoreMathFunctions.given (places_v) && places_v.kind != ValueKind.EMPTY) {
                double p;
                var e = num (places_v, out p);
                if (e != null) return e;
                int places = (int) Math.trunc (p);
                if (places <= 0 || places > 10 || places < sb2.len) return Value.err (ErrorKind.NUM);
                while (sb2.len < places) sb2.prepend_c ('0');
            }
            return Value.str (sb2.str);
        }

        private static void base_fn (string name, int from, int to) {
            string[] names = { "", "", "BIN", "", "", "", "", "", "OCT", "", "DEC", "", "", "", "", "", "HEX" };
            string argname = from == 10 ? "number" : "number";
            bool has_places = to != 10;
            string syntax = has_places ? name + "(" + argname + ", [places])" : name + "(" + argname + ")";
            string summary = _("Converts a %s number to %s").printf (names[from].down (), names[to].down ());
            add (name, 1, has_places ? 2 : 1, syntax, summary, (ev, a) => lift (ev, a, (v) => {
                double n;
                if (from == 10) {
                    var e = num (v[0], out n);
                    if (e != null) return e;
                } else {
                    var e = parse_radix (v[0], from, out n);
                    if (e != null) return e;
                }
                if (to == 10) return Value.num (n);
                return format_radix (n, to, opt (v, 1));
            }));
        }

        private delegate uint64 BitOp (uint64 x, uint64 y);

        private static Value? bit_arg (Value v, out uint64 r) {
            r = 0;
            double d;
            var e = num (v, out d);
            if (e != null) return e;
            if (d < 0 || d != Math.floor (d) || d >= 281474976710656.0) return Value.err (ErrorKind.NUM);
            r = (uint64) d;
            return null;
        }

        private static void bit_fn (string name, string summary, owned BitOp f) {
            BitOp op = (owned) f;
            add (name, 2, 2, name + "(number1, number2)", summary, (ev, a) => lift (ev, a, (v) => {
                uint64 x, y;
                var e = bit_arg (v[0], out x);
                if (e != null) return e;
                if ((e = bit_arg (v[1], out y)) != null) return e;
                return Value.num ((double) op (x, y));
            }));
        }

        private static void shift_fn (string name, string summary, bool left) {
            add (name, 2, 2, name + "(number, shift_amount)", summary, (ev, a) => lift (ev, a, (v) => {
                uint64 x;
                double s;
                var e = bit_arg (v[0], out x);
                if (e != null) return e;
                if ((e = num (v[1], out s)) != null) return e;
                int sh = (int) Math.trunc (s);
                if (sh.abs () > 53) return Value.err (ErrorKind.NUM);
                if (!left) sh = -sh;
                double r = sh >= 0 ? (double) x * Math.pow (2, sh) : Math.floor ((double) x / Math.pow (2, -sh));
                if (r >= 281474976710656.0) return Value.err (ErrorKind.NUM);
                return Value.num (r);
            }));
        }

        public static bool parse_complex (string text, out Cplx z, out string suffix) {
            z = Cplx (0, 0);
            suffix = "i";
            string s = text.strip ();
            if (s == "") return true;
            if (s.has_suffix ("i") || s.has_suffix ("j")) {
                suffix = s.substring (s.length - 1);
                string body = s.substring (0, s.length - 1);
                int split = -1;
                for (int k = body.length - 1; k > 0; k--) {
                    if ((body[k] == '+' || body[k] == '-') && body[k - 1] != 'e' && body[k - 1] != 'E') {
                        split = k;
                        break;
                    }
                }
                string re_s = split > 0 ? body.substring (0, split) : "";
                string im_s = split > 0 ? body.substring (split) : body;
                double re = 0, im;
                if (re_s != "" && !parse_real (re_s, out re)) return false;
                if (im_s == "" || im_s == "+") im = 1;
                else if (im_s == "-") im = -1;
                else if (!parse_real (im_s, out im)) return false;
                z = Cplx (re, im);
                return true;
            }
            double r;
            if (!parse_real (s, out r)) return false;
            z = Cplx (r, 0);
            return true;
        }

        private static bool parse_real (string s, out double d) {
            d = 0;
            if (s == "" || s.contains (" ")) return false;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (!(c.isdigit () || c == '.' || c == '+' || c == '-' || c == 'e' || c == 'E')) return false;
            }
            return double.try_parse (s, out d);
        }

        public static string fmt (double x) {
            if (x == 0) return "0";
            string s = Value.ascii (x, "%.15g");
            if (s.contains ("e")) {
                int e = s.index_of ("e");
                string mant = s.substring (0, e);
                int ev = int.parse (s.substring (e + 1));
                return "%sE%s%d".printf (mant, ev < 0 ? "-" : "+", ev.abs ());
            }
            return s;
        }

        public static string format_complex (Cplx z, string suffix) {
            double re = Math.fabs (z.re) < 1e-300 ? 0 : z.re;
            double im = Math.fabs (z.im) < 1e-300 ? 0 : z.im;
            if (im == 0) return fmt (re);
            string ims;
            if (im == 1) ims = suffix;
            else if (im == -1) ims = "-" + suffix;
            else ims = fmt (im) + suffix;
            if (re == 0) return ims;
            return fmt (re) + (im > 0 ? "+" : "") + ims;
        }

        private static Value? to_complex (Value v, out Cplx z, ref string suffix) {
            z = Cplx (0, 0);
            if (v.is_error ()) return v;
            if (v.kind == ValueKind.BOOL) return Value.err (ErrorKind.VALUE);
            if (v.kind == ValueKind.NUMBER || v.kind == ValueKind.EMPTY) {
                z = Cplx (v.number, 0);
                return null;
            }
            string sfx;
            if (!parse_complex (v.text, out z, out sfx)) return Value.err (ErrorKind.NUM);
            if (v.text.strip ().has_suffix ("i") || v.text.strip ().has_suffix ("j")) {
                if (suffix != "" && suffix != sfx) return Value.err (ErrorKind.VALUE);
                suffix = sfx;
            }
            return null;
        }

        private delegate Value ComplexOp (Cplx z, string suffix);

        private static void im1 (string name, string summary, owned ComplexOp f) {
            ComplexOp op = (owned) f;
            add (name, 1, 1, name + "(inumber)", summary, (ev, a) => lift (ev, a, (v) => {
                Cplx z;
                string sfx = "";
                var e = to_complex (v[0], out z, ref sfx);
                if (e != null) return e;
                return op (z, sfx == "" ? "i" : sfx);
            }));
        }

        private static Value cx (Cplx z, string sfx) {
            if (z.re.is_nan () || z.im.is_nan () || z.re.is_infinity () != 0 || z.im.is_infinity () != 0) return Value.err (ErrorKind.NUM);
            return Value.str (format_complex (z, sfx));
        }

        private static void im_fold (string name, string summary, bool product) {
            add (name, 1, 255, name + "(inumber1, [inumber2], ...)", summary, (ev, a) => {
                Cplx acc = product ? Cplx (1, 0) : Cplx (0, 0);
                string sfx = "";
                foreach (var n in a) {
                    if (n.kind == NodeKind.MISSING) continue;
                    var m = ev.to_matrix (ev.eval (n));
                    for (int i = 0; i < m.length[0]; i++) {
                        for (int j = 0; j < m.length[1]; j++) {
                            Cplx z;
                            var e = to_complex (m[i, j], out z, ref sfx);
                            if (e != null) return e;
                            acc = product ? acc.mul (z) : acc.add (z);
                        }
                    }
                }
                return cx (acc, sfx == "" ? "i" : sfx);
            });
        }

        private static void im2 (string name, string syntax, string summary, bool divide) {
            add (name, 2, 2, syntax, summary, (ev, a) => lift (ev, a, (v) => {
                Cplx x, y;
                string sfx = "";
                var e = to_complex (v[0], out x, ref sfx);
                if (e != null) return e;
                if ((e = to_complex (v[1], out y, ref sfx)) != null) return e;
                if (divide) {
                    if (y.re == 0 && y.im == 0) return Value.err (ErrorKind.NUM);
                    return cx (x.div (y), sfx == "" ? "i" : sfx);
                }
                return cx (x.sub (y), sfx == "" ? "i" : sfx);
            }));
        }

        private class Unit {
            public string category;
            public double factor;
            public bool prefix;
            public bool binary;
            public int power;

            public Unit (string category, double factor, bool prefix, int power = 1, bool binary = false) {
                this.category = category;
                this.factor = factor;
                this.prefix = prefix;
                this.power = power;
                this.binary = binary;
            }
        }

        private static Gee.HashMap<string, Unit>? units;

        private static void u (string names, string cat, double factor, bool prefix, int power = 1, bool binary = false) {
            foreach (string n in names.split ("|")) units[n] = new Unit (cat, factor, prefix, power, binary);
        }

        private static void build_units () {
            units = new Gee.HashMap<string, Unit> ();
            u ("g", "mass", 1, true);
            u ("sg", "mass", 14593.9029372064, false);
            u ("lbm", "mass", 453.59237, false);
            u ("u", "mass", 1.660538782e-24, true);
            u ("ozm", "mass", 28.349523125, false);
            u ("grain", "mass", 0.06479891, false);
            u ("cwt|shweight", "mass", 45359.237, false);
            u ("uk_cwt|lcwt|hweight", "mass", 50802.34544, false);
            u ("stone", "mass", 6350.29318, false);
            u ("ton", "mass", 907184.74, false);
            u ("uk_ton|LTON|brton", "mass", 1016046.9088, false);
            u ("m", "distance", 1, true);
            u ("mi", "distance", 1609.344, false);
            u ("Nmi", "distance", 1852, false);
            u ("in", "distance", 0.0254, false);
            u ("ft", "distance", 0.3048, false);
            u ("yd", "distance", 0.9144, false);
            u ("ang", "distance", 1e-10, true);
            u ("ell", "distance", 1.143, false);
            u ("ly", "distance", 9460730472580800.0, false);
            u ("parsec|pc", "distance", 30856775812815500.0, false);
            u ("Picapt|Pica", "distance", 0.0254 / 72, false);
            u ("pica", "distance", 0.0254 / 6, false);
            u ("survey_mi", "distance", 1609.3472186944373, false);
            u ("yr", "time", 31557600, false);
            u ("day|d", "time", 86400, false);
            u ("hr", "time", 3600, false);
            u ("mn|min", "time", 60, false);
            u ("sec|s", "time", 1, true);
            u ("Pa|p", "pressure", 1, true);
            u ("atm|at", "pressure", 101325, true);
            u ("mmHg", "pressure", 133.322, true);
            u ("psi", "pressure", 6894.75729316836, false);
            u ("Torr", "pressure", 133.322368421053, false);
            u ("N", "force", 1, true);
            u ("dyn|dy", "force", 1e-5, true);
            u ("lbf", "force", 4.4482216152605, false);
            u ("pond", "force", 0.00980665, true);
            u ("J", "energy", 1, true);
            u ("e", "energy", 1e-7, true);
            u ("c", "energy", 4.184, true);
            u ("cal", "energy", 4.1868, true);
            u ("eV|ev", "energy", 1.602176487e-19, true);
            u ("HPh|hh", "energy", 2684519.53769617, false);
            u ("Wh|wh", "energy", 3600, true);
            u ("flb", "energy", 0.0421401100938048, false);
            u ("BTU|btu", "energy", 1055.05585262, false);
            u ("HP|h", "power", 745.69987158227, false);
            u ("PS", "power", 735.49875, false);
            u ("W|w", "power", 1, true);
            u ("T", "magnetism", 1, true);
            u ("ga", "magnetism", 1e-4, true);
            u ("C|cel", "temperature", 1, false);
            u ("F|fah", "temperature", 1, false);
            u ("K|kel", "temperature", 1, true);
            u ("Rank", "temperature", 1, false);
            u ("Reau", "temperature", 1, false);
            u ("tsp", "volume", 4.92892159375e-6, false);
            u ("tspm", "volume", 5e-6, false);
            u ("tbs", "volume", 1.478676478125e-5, false);
            u ("oz", "volume", 2.95735295625e-5, false);
            u ("cup", "volume", 2.365882365e-4, false);
            u ("pt|us_pt", "volume", 4.73176473e-4, false);
            u ("uk_pt", "volume", 5.6826125e-4, false);
            u ("qt", "volume", 9.46352946e-4, false);
            u ("uk_qt", "volume", 1.1365225e-3, false);
            u ("gal", "volume", 3.785411784e-3, false);
            u ("uk_gal", "volume", 4.54609e-3, false);
            u ("l|L|lt", "volume", 1e-3, true);
            u ("ang3|ang^3", "volume", 1e-10, true, 3);
            u ("barrel", "volume", 0.158987294928, false);
            u ("bushel", "volume", 0.03523907016688, false);
            u ("ft3|ft^3", "volume", 0.3048, false, 3);
            u ("in3|in^3", "volume", 0.0254, false, 3);
            u ("ly3|ly^3", "volume", 9460730472580800.0, false, 3);
            u ("m3|m^3", "volume", 1, true, 3);
            u ("mi3|mi^3", "volume", 1609.344, false, 3);
            u ("yd3|yd^3", "volume", 0.9144, false, 3);
            u ("Nmi3|Nmi^3", "volume", 1852, false, 3);
            u ("Picapt3|Picapt^3|Pica3|Pica^3", "volume", 0.0254 / 72, false, 3);
            u ("GRT|regton", "volume", 2.8316846592, false);
            u ("MTON", "volume", 1.13267386368, false);
            u ("uk_acre", "area", 4046.8564224, false);
            u ("us_acre", "area", 4046.87260987425, false);
            u ("ang2|ang^2", "area", 1e-10, true, 2);
            u ("ar", "area", 100, true);
            u ("ft2|ft^2", "area", 0.3048, false, 2);
            u ("ha", "area", 10000, false);
            u ("in2|in^2", "area", 0.0254, false, 2);
            u ("ly2|ly^2", "area", 9460730472580800.0, false, 2);
            u ("m2|m^2", "area", 1, true, 2);
            u ("Morgen", "area", 2500, false);
            u ("mi2|mi^2", "area", 1609.344, false, 2);
            u ("Nmi2|Nmi^2", "area", 1852, false, 2);
            u ("Picapt2|Pica2|Pica^2|Picapt^2", "area", 0.0254 / 72, false, 2);
            u ("yd2|yd^2", "area", 0.9144, false, 2);
            u ("bit", "information", 1, true, 1, true);
            u ("byte", "information", 8, true, 1, true);
            u ("admkn", "speed", 0.514773333333333, false);
            u ("kn", "speed", 1852.0 / 3600, false);
            u ("m/h|m/hr", "speed", 1.0 / 3600, true);
            u ("m/s|m/sec", "speed", 1, true);
            u ("mph", "speed", 0.44704, false);
        }

        private static bool lookup_unit (string name, out Unit? unit, out double factor) {
            unit = null;
            factor = 1;
            if (units == null) build_units ();
            if (units.has_key (name)) {
                unit = units[name];
                factor = Math.pow (unit.factor, unit.power);
                return true;
            }
            string[] bin = { "ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi", "Yi" };
            for (int i = 0; i < bin.length; i++) {
                if (name.has_prefix (bin[i]) && units.has_key (name.substring (2))) {
                    var bu = units[name.substring (2)];
                    if (!bu.binary) continue;
                    unit = bu;
                    factor = bu.factor * Math.pow (2, 10 * (i + 1));
                    return true;
                }
            }
            string[] pre = { "da", "Y", "Z", "E", "P", "T", "G", "M", "k", "h", "e", "d", "c", "m", "u", "n", "p", "f", "a", "z", "y" };
            double[] mul = { 1e1, 1e24, 1e21, 1e18, 1e15, 1e12, 1e9, 1e6, 1e3, 1e2, 1e1, 1e-1, 1e-2, 1e-3, 1e-6, 1e-9, 1e-12, 1e-15, 1e-18, 1e-21, 1e-24 };
            for (int i = 0; i < pre.length; i++) {
                if (!name.has_prefix (pre[i])) continue;
                string rest = name.substring (pre[i].length);
                if (!units.has_key (rest)) continue;
                var pu = units[rest];
                if (!pu.prefix) continue;
                unit = pu;
                factor = Math.pow (pu.factor * mul[i], pu.power);
                return true;
            }
            return false;
        }

        private static double to_kelvin (string n, double x) {
            switch (n) {
                case "C": case "cel": return x + 273.15;
                case "F": case "fah": return (x - 32) * 5 / 9 + 273.15;
                case "Rank": return x * 5 / 9;
                case "Reau": return x * 1.25 + 273.15;
                default: return x;
            }
        }

        private static double from_kelvin (string n, double k) {
            switch (n) {
                case "C": case "cel": return k - 273.15;
                case "F": case "fah": return (k - 273.15) * 9 / 5 + 32;
                case "Rank": return k * 9 / 5;
                case "Reau": return (k - 273.15) * 0.8;
                default: return k;
            }
        }

        public static Value convert (double x, string from, string to) {
            Unit? fu, tu;
            double ff, tf;
            bool ok1 = lookup_unit (from, out fu, out ff);
            bool ok2 = lookup_unit (to, out tu, out tf);
            if (!ok1 || !ok2) return Value.err (ErrorKind.NA);
            if (fu.category != tu.category) return Value.err (ErrorKind.NA);
            if (fu.category == "temperature") {
                bool fk = units.has_key (from) ? (from == "K" || from == "kel") : true;
                bool tk = units.has_key (to) ? (to == "K" || to == "kel") : true;
                double k = fk ? x * ff : to_kelvin (from, x);
                return Value.num (tk ? k / tf : from_kelvin (to, k));
            }
            return Value.num (x * ff / tf);
        }

        private static double bessel_i (double x, int n) {
            double sum = 0;
            double term = Math.pow (x / 2, n) / MoreMathFunctions.factorial (n);
            for (int k = 0; k < 500; k++) {
                sum += term;
                term *= (x * x / 4) / ((k + 1) * (k + 1 + n));
                if (Math.fabs (term) < 1e-17 * Math.fabs (sum)) break;
            }
            return sum;
        }

        private static double bessel_k0 (double x) {
            if (x <= 2) {
                double y = x * x / 4;
                return (-Math.log (x / 2) * bessel_i (x, 0)) + (-0.57721566 + y * (0.42278420 + y * (0.23069756 + y * (0.3488590e-1 + y * (0.262698e-2 + y * (0.10750e-3 + y * 0.74e-5))))));
            }
            double z = 2 / x;
            return (Math.exp (-x) / Math.sqrt (x)) * (1.25331414 + z * (-0.7832358e-1 + z * (0.2189568e-1 + z * (-0.1062446e-1 + z * (0.587872e-2 + z * (-0.251540e-2 + z * 0.53208e-3))))));
        }

        private static double bessel_k1 (double x) {
            if (x <= 2) {
                double y = x * x / 4;
                return (Math.log (x / 2) * bessel_i (x, 1)) + (1 / x) * (1 + y * (0.15443144 + y * (-0.67278579 + y * (-0.18156897 + y * (-0.1919402e-1 + y * (-0.110404e-2 + y * (-0.4686e-4)))))));
            }
            double z = 2 / x;
            return (Math.exp (-x) / Math.sqrt (x)) * (1.25331414 + z * (0.23498619 + z * (-0.3655620e-1 + z * (0.1504268e-1 + z * (-0.780353e-2 + z * (0.325614e-2 + z * (-0.68245e-3)))))));
        }

        private static double bessel_k (double x, int n) {
            if (n == 0) return bessel_k0 (x);
            double bkm = bessel_k0 (x);
            double bk = bessel_k1 (x);
            for (int j = 1; j < n; j++) {
                double bkp = bkm + j * 2 / x * bk;
                bkm = bk;
                bk = bkp;
            }
            return bk;
        }

        private delegate Value BesselOp (double x, int n);

        private static void bessel (string name, string summary, owned BesselOp f) {
            BesselOp op = (owned) f;
            add (name, 2, 2, name + "(x, n)", summary, (ev, a) => lift (ev, a, (v) => {
                double x, n;
                if (v[0].kind == ValueKind.BOOL || v[1].kind == ValueKind.BOOL) return Value.err (ErrorKind.VALUE);
                var e = num (v[0], out x);
                if (e != null) return e;
                if ((e = num (v[1], out n)) != null) return e;
                int ni = (int) Math.trunc (n);
                if (ni < 0) return Value.err (ErrorKind.NUM);
                return op (x, ni);
            }));
        }

        public static void register () {
            base_fn ("BIN2DEC", 2, 10);
            base_fn ("BIN2HEX", 2, 16);
            base_fn ("BIN2OCT", 2, 8);
            base_fn ("DEC2BIN", 10, 2);
            base_fn ("DEC2HEX", 10, 16);
            base_fn ("DEC2OCT", 10, 8);
            base_fn ("HEX2BIN", 16, 2);
            base_fn ("HEX2DEC", 16, 10);
            base_fn ("HEX2OCT", 16, 8);
            base_fn ("OCT2BIN", 8, 2);
            base_fn ("OCT2DEC", 8, 10);
            base_fn ("OCT2HEX", 8, 16);
            bit_fn ("BITAND", _("Bitwise AND of two numbers"), (x, y) => x & y);
            bit_fn ("BITOR", _("Bitwise OR of two numbers"), (x, y) => x | y);
            bit_fn ("BITXOR", _("Bitwise exclusive OR of two numbers"), (x, y) => x ^ y);
            shift_fn ("BITLSHIFT", _("A number shifted left by some bits"), true);
            shift_fn ("BITRSHIFT", _("A number shifted right by some bits"), false);
            add ("DELTA", 1, 2, "DELTA(number1, [number2])", _("Tests whether two numbers are equal"), (ev, a) => lift (ev, a, (v) => {
                double x, y;
                var e = num (v[0], out x);
                if (e != null) return e;
                if ((e = num_or (opt (v, 1), 0, out y)) != null) return e;
                return Value.num (x == y ? 1 : 0);
            }));
            add ("GESTEP", 1, 2, "GESTEP(number, [step])", _("Tests whether a number is at least a threshold"), (ev, a) => lift (ev, a, (v) => {
                double x, y;
                var e = num (v[0], out x);
                if (e != null) return e;
                if ((e = num_or (opt (v, 1), 0, out y)) != null) return e;
                return Value.num (x >= y ? 1 : 0);
            }));
            add ("ERF", 1, 2, "ERF(lower_limit, [upper_limit])", _("The error function"), (ev, a) => lift (ev, a, (v) => {
                double lo, hi;
                var e = num (v[0], out lo);
                if (e != null) return e;
                if (MoreMathFunctions.given (opt (v, 1))) {
                    if ((e = num (v[1], out hi)) != null) return e;
                    return Value.num (Math.erf (hi) - Math.erf (lo));
                }
                return Value.num (Math.erf (lo));
            }));
            add ("ERF.PRECISE", 1, 1, "ERF.PRECISE(x)", _("The error function"), (ev, a) => lift (ev, a, (v) => {
                double x;
                var e = num (v[0], out x);
                return e ?? Value.num (Math.erf (x));
            }));
            add ("ERFC", 1, 1, "ERFC(x)", _("The complementary error function"), (ev, a) => lift (ev, a, (v) => {
                double x;
                var e = num (v[0], out x);
                return e ?? Value.num (Math.erfc (x));
            }));
            Functions.alias ("ERFC.PRECISE", "ERFC");
            bessel ("BESSELJ", _("The Bessel function Jn(x)"), (x, n) => Value.num (Math.jn (n, x)));
            bessel ("BESSELY", _("The Bessel function Yn(x)"), (x, n) => {
                if (x <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (Math.yn (n, x));
            });
            bessel ("BESSELI", _("The modified Bessel function In(x)"), (x, n) => Value.num (bessel_i (x, n)));
            bessel ("BESSELK", _("The modified Bessel function Kn(x)"), (x, n) => {
                if (x <= 0) return Value.err (ErrorKind.NUM);
                return Value.num (bessel_k (x, n));
            });
            add ("CONVERT", 3, 3, "CONVERT(number, from_unit, to_unit)", _("Converts a number between measurement units"), (ev, a) => lift (ev, a, (v) => {
                double x;
                var e = num (v[0], out x);
                if (e != null) return e;
                if (v[1].is_error ()) return v[1];
                if (v[2].is_error ()) return v[2];
                return convert (x, Evaluator.to_text (v[1]), Evaluator.to_text (v[2]));
            }));
            add ("COMPLEX", 2, 3, "COMPLEX(real_num, i_num, [suffix])", _("Builds a complex number"), (ev, a) => lift (ev, a, (v) => {
                double re, im;
                var e = num (v[0], out re);
                if (e != null) return e;
                if ((e = num (v[1], out im)) != null) return e;
                string sfx = "i";
                var sv = opt (v, 2);
                if (MoreMathFunctions.given (sv) && sv.kind != ValueKind.EMPTY) {
                    if (sv.is_error ()) return sv;
                    sfx = Evaluator.to_text (sv);
                    if (sfx == "") sfx = "i";
                    if (sfx != "i" && sfx != "j") return Value.err (ErrorKind.VALUE);
                }
                return Value.str (format_complex (Cplx (re, im), sfx));
            }));
            im1 ("IMABS", _("Absolute value of a complex number"), (z, s) => Value.num (z.abs ()));
            im1 ("IMREAL", _("Real part of a complex number"), (z, s) => Value.num (z.re));
            im1 ("IMAGINARY", _("Imaginary part of a complex number"), (z, s) => Value.num (z.im));
            im1 ("IMARGUMENT", _("Argument of a complex number in radians"), (z, s) => {
                if (z.re == 0 && z.im == 0) return Value.err (ErrorKind.DIV0);
                return Value.num (z.arg ());
            });
            im1 ("IMCONJUGATE", _("Complex conjugate"), (z, s) => cx (Cplx (z.re, -z.im), s));
            im1 ("IMEXP", _("Exponential of a complex number"), (z, s) => cx (z.exp (), s));
            im1 ("IMLN", _("Natural logarithm of a complex number"), (z, s) => {
                if (z.re == 0 && z.im == 0) return Value.err (ErrorKind.NUM);
                return cx (z.ln (), s);
            });
            im1 ("IMLOG10", _("Base-10 logarithm of a complex number"), (z, s) => {
                if (z.re == 0 && z.im == 0) return Value.err (ErrorKind.NUM);
                var l = z.ln ();
                return cx (Cplx (l.re / Math.LN10, l.im / Math.LN10), s);
            });
            im1 ("IMLOG2", _("Base-2 logarithm of a complex number"), (z, s) => {
                if (z.re == 0 && z.im == 0) return Value.err (ErrorKind.NUM);
                var l = z.ln ();
                return cx (Cplx (l.re / Math.LN2, l.im / Math.LN2), s);
            });
            im1 ("IMSQRT", _("Square root of a complex number"), (z, s) => cx (z.pow (0.5), s));
            im1 ("IMSIN", _("Sine of a complex number"), (z, s) => cx (z.sin (), s));
            im1 ("IMCOS", _("Cosine of a complex number"), (z, s) => cx (z.cos (), s));
            im1 ("IMTAN", _("Tangent of a complex number"), (z, s) => cx (z.sin ().div (z.cos ()), s));
            im1 ("IMCOT", _("Cotangent of a complex number"), (z, s) => {
                if (z.re == 0 && z.im == 0) return Value.err (ErrorKind.NUM);
                return cx (z.cos ().div (z.sin ()), s);
            });
            im1 ("IMSEC", _("Secant of a complex number"), (z, s) => cx (Cplx (1, 0).div (z.cos ()), s));
            im1 ("IMCSC", _("Cosecant of a complex number"), (z, s) => {
                if (z.re == 0 && z.im == 0) return Value.err (ErrorKind.NUM);
                return cx (Cplx (1, 0).div (z.sin ()), s);
            });
            im1 ("IMSINH", _("Hyperbolic sine of a complex number"), (z, s) => cx (z.sinh (), s));
            im1 ("IMCOSH", _("Hyperbolic cosine of a complex number"), (z, s) => cx (z.cosh (), s));
            im1 ("IMSECH", _("Hyperbolic secant of a complex number"), (z, s) => cx (Cplx (1, 0).div (z.cosh ()), s));
            im1 ("IMCSCH", _("Hyperbolic cosecant of a complex number"), (z, s) => {
                if (z.re == 0 && z.im == 0) return Value.err (ErrorKind.NUM);
                return cx (Cplx (1, 0).div (z.sinh ()), s);
            });
            add ("IMPOWER", 2, 2, "IMPOWER(inumber, number)", _("A complex number raised to a power"), (ev, a) => lift (ev, a, (v) => {
                Cplx z;
                string sfx = "";
                var e = to_complex (v[0], out z, ref sfx);
                if (e != null) return e;
                double n;
                if ((e = num (v[1], out n)) != null) return e;
                if (z.re == 0 && z.im == 0 && n <= 0) return Value.err (ErrorKind.NUM);
                return cx (z.pow (n), sfx == "" ? "i" : sfx);
            }));
            im2 ("IMDIV", "IMDIV(inumber1, inumber2)", _("Quotient of two complex numbers"), true);
            im2 ("IMSUB", "IMSUB(inumber1, inumber2)", _("Difference of two complex numbers"), false);
            im_fold ("IMSUM", _("Sum of complex numbers"), false);
            im_fold ("IMPRODUCT", _("Product of complex numbers"), true);
        }
    }
}
