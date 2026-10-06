namespace Singularity.Apps.Spreadsheet {

    public enum ValueKind {
        EMPTY,
        NUMBER,
        TEXT,
        BOOL,
        ERROR,
        RANGE,
        ARRAY,
        LAMBDA,
        REFS
    }

    public enum ErrorKind {
        NONE,
        NULL,
        DIV0,
        VALUE,
        REF,
        NAME,
        NUM,
        NA,
        CIRC,
        SPILL,
        CALC,
        GETTING_DATA;

        public string to_string () {
            switch (this) {
                case NULL: return "#NULL!";
                case DIV0: return "#DIV/0!";
                case VALUE: return "#VALUE!";
                case REF: return "#REF!";
                case NAME: return "#NAME?";
                case NUM: return "#NUM!";
                case NA: return "#N/A";
                case CIRC: return "#CIRC!";
                case SPILL: return "#SPILL!";
                case CALC: return "#CALC!";
                case GETTING_DATA: return "#GETTING_DATA";
                default: return "";
            }
        }

        public static ErrorKind parse (string s) {
            switch (s.up ()) {
                case "#NULL!": return NULL;
                case "#DIV/0!": return DIV0;
                case "#VALUE!": return VALUE;
                case "#REF!": return REF;
                case "#NAME?": return NAME;
                case "#NUM!": return NUM;
                case "#N/A": return NA;
                case "#CIRC!": return CIRC;
                case "#SPILL!": return SPILL;
                case "#CALC!": return CALC;
                case "#GETTING_DATA": return GETTING_DATA;
                default: return NONE;
            }
        }
    }

    public class Value {
        public ValueKind kind;
        public double number;
        public string text;
        public ErrorKind error;
        public Area? area;
        public Value[,]? array;
        public Lambda? fn;
        public Area[]? areas;
        public bool omitted;
        public Bytes? image;
        public int image_sizing;
        public double image_height;
        public double image_width;

        private static Value? _empty = null;
        private static Value? _omitted = null;

        public Value (ValueKind kind) {
            this.kind = kind;
            this.text = "";
        }

        public static Value empty () {
            if (_empty == null) _empty = new Value (ValueKind.EMPTY);
            return _empty;
        }

        public static Value missing () {
            if (_omitted == null) {
                _omitted = new Value (ValueKind.EMPTY);
                _omitted.omitted = true;
            }
            return _omitted;
        }

        public static Value lambda (Lambda f) {
            var v = new Value (ValueKind.LAMBDA);
            v.fn = f;
            return v;
        }

        public static Value refs (Area[] list) {
            if (list.length == 1) return range (list[0]);
            var v = new Value (ValueKind.REFS);
            v.areas = list;
            return v;
        }

        public static Value num (double n) {
            if (n.is_nan () || n.is_infinity () != 0) return err (ErrorKind.NUM);
            var v = new Value (ValueKind.NUMBER);
            v.number = n;
            return v;
        }

        public static Value str (string s) {
            var v = new Value (ValueKind.TEXT);
            v.text = s;
            return v;
        }

        public static Value boolean (bool b) {
            var v = new Value (ValueKind.BOOL);
            v.number = b ? 1 : 0;
            return v;
        }

        public static Value err (ErrorKind e) {
            var v = new Value (ValueKind.ERROR);
            v.error = e;
            return v;
        }

        public static Value range (Area a) {
            var v = new Value (ValueKind.RANGE);
            v.area = a;
            return v;
        }

        public static Value matrix (Value[,] m) {
            var v = new Value (ValueKind.ARRAY);
            v.array = m;
            return v;
        }

        public bool is_error () {
            return kind == ValueKind.ERROR;
        }

        public bool is_empty () {
            return kind == ValueKind.EMPTY;
        }

        public bool is_multi () {
            if (kind == ValueKind.ARRAY) return array.length[0] * array.length[1] > 1;
            if (kind == ValueKind.RANGE) return !area.is_single ();
            return false;
        }

        public bool as_bool () {
            return number != 0;
        }

        public string display () {
            switch (kind) {
                case ValueKind.NUMBER: return format_number_general (number);
                case ValueKind.TEXT: return text;
                case ValueKind.BOOL: return number != 0 ? "TRUE" : "FALSE";
                case ValueKind.ERROR: return error.to_string ();
                default: return "";
            }
        }

        public bool equals (Value other) {
            if (kind != other.kind) {
                if (is_empty () && other.kind == ValueKind.NUMBER) return other.number == 0;
                if (other.is_empty () && kind == ValueKind.NUMBER) return number == 0;
                if (is_empty () && other.kind == ValueKind.TEXT) return other.text == "";
                if (other.is_empty () && kind == ValueKind.TEXT) return text == "";
                return false;
            }
            switch (kind) {
                case ValueKind.NUMBER:
                case ValueKind.BOOL:
                    return number == other.number;
                case ValueKind.TEXT:
                    return text.casefold () == other.text.casefold ();
                case ValueKind.ERROR:
                    return error == other.error;
                default:
                    return true;
            }
        }

        public static string ascii (double n, string fmt) {
            char[] buf = new char[64];
            return n.format (buf, fmt);
        }

        public static string fixed (double n, int decimals) {
            return ascii (n, "%." + decimals.to_string () + "f");
        }

        public static string trim_zeros (string s) {
            if (!s.contains (".")) return s;
            string r = s;
            while (r.has_suffix ("0")) r = r.substring (0, r.length - 1);
            if (r.has_suffix (".")) r = r.substring (0, r.length - 1);
            return r;
        }

        public static string format_number_general_full (double n) {
            string s = ascii (n, "%.15g");
            if (double.parse (s) != n) s = ascii (n, "%.17g");
            if (s.contains ("e")) {
                int e = s.index_of ("e");
                string mant = s.substring (0, e);
                int ev = int.parse (s.substring (e + 1));
                return "%sE%s%d".printf (mant, ev < 0 ? "-" : "+", ev.abs ());
            }
            return s;
        }

        public static string format_number_general (double n) {
            if (n == 0) return "0";
            double a = Math.fabs (n);
            if (a >= 1e11 || a < 1e-9) {
                string s = ascii (n, "%.5E");
                int e = s.index_of ("E");
                string mant = trim_zeros (s.substring (0, e));
                int ev = int.parse (s.substring (e + 1));
                return "%sE%s%02d".printf (mant, ev < 0 ? "-" : "+", ev.abs ());
            }
            int int_digits = a < 1 ? 1 : (int) Math.floor (Math.log10 (a)) + 1;
            int digits = (10 - int_digits).clamp (0, 15);
            string s = trim_zeros (fixed (n, digits));
            return s == "-0" ? "0" : s;
        }
    }
}
