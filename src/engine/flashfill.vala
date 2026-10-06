namespace Singularity.Apps.Spreadsheet {

    public enum CaseOp {
        KEEP,
        UPPER,
        LOWER,
        TITLE
    }

    public enum TokenClass {
        WORD,
        LETTERS,
        DIGITS
    }

    public class FillAtom {
        public int kind;
        public string text = "";
        public int col;
        public TokenClass cls;
        public int index;
        public bool from_end;
        public CaseOp op;
        public int start;
        public int length;

        public string eval (string[] inputs) {
            switch (kind) {
                case 0:
                    return text;
                case 1:
                    if (col >= inputs.length) return "\x01";
                    return apply_case (inputs[col], op);
                case 2:
                case 3:
                    if (col >= inputs.length) return "\x01";
                    var toks = FlashFill.tokens (inputs[col], cls);
                    int i = from_end ? toks.size - 1 - index : index;
                    if (i < 0 || i >= toks.size) return "\x01";
                    string t = toks[i];
                    if (kind == 3) t = t.substring (0, t.index_of_nth_char (1));
                    return apply_case (t, op);
                case 5:
                    if (col >= inputs.length) return "\x01";
                    var parts = inputs[col].split (text);
                    int pi = from_end ? parts.length - 1 - index : index;
                    if (parts.length < 2 || pi < 0 || pi >= parts.length) return "\x01";
                    return apply_case (parts[pi], op);
                case 4:
                    if (col >= inputs.length) return "\x01";
                    string src = inputs[col];
                    int n = src.char_count ();
                    int st = from_end ? n - start - length : start;
                    if (st < 0 || st + length > n) return "\x01";
                    return apply_case (src.substring (src.index_of_nth_char (st), src.index_of_nth_char (st + length) - src.index_of_nth_char (st)), op);
            }
            return "\x01";
        }

        public static string apply_case (string s, CaseOp op) {
            switch (op) {
                case CaseOp.UPPER: return s.up ();
                case CaseOp.LOWER: return s.down ();
                case CaseOp.TITLE:
                    var sb = new StringBuilder ();
                    bool start = true;
                    unichar c;
                    int i = 0;
                    while (s.get_next_char (ref i, out c)) {
                        sb.append_unichar (start ? c.totitle () : c.tolower ());
                        start = !c.isalnum ();
                    }
                    return sb.str;
                default: return s;
            }
        }

        public int cost () {
            int extra = op == CaseOp.KEEP ? 0 : 1;
            switch (kind) {
                case 0:
                    int c = 2;
                    unichar ch;
                    int i = 0;
                    while (text.get_next_char (ref i, out ch)) c += ch.isalnum () ? 5 : 1;
                    return c;
                case 1: return 1 + extra;
                case 2: return 2 + extra;
                case 3: return 2 + extra;
                case 5: return 2 + extra;
                default: return 7 + extra * 2;
            }
        }
    }

    public class FillRow {
        public string[] values;

        public FillRow (string[] values) {
            this.values = values;
        }
    }

    public class FlashFill {
        public static Gee.List<string> tokens (string s, TokenClass cls) {
            var list = new Gee.ArrayList<string> ();
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                bool member;
                switch (cls) {
                    case TokenClass.LETTERS: member = c.isalpha (); break;
                    case TokenClass.DIGITS: member = c.isdigit (); break;
                    default: member = c.isalnum () || c == '\'' ; break;
                }
                if (member) sb.append_unichar (c);
                else if (sb.len > 0) {
                    list.add (sb.str);
                    sb.truncate (0);
                }
            }
            if (sb.len > 0) list.add (sb.str);
            return list;
        }

        private static Gee.List<FillAtom> atoms_for (string[] inputs, string piece) {
            var out_l = new Gee.ArrayList<FillAtom> ();
            CaseOp[] ops = { CaseOp.KEEP, CaseOp.UPPER, CaseOp.LOWER, CaseOp.TITLE };
            TokenClass[] classes = { TokenClass.WORD, TokenClass.LETTERS, TokenClass.DIGITS };
            for (int col = 0; col < inputs.length; col++) {
                foreach (var op in ops) {
                    if (FillAtom.apply_case (inputs[col], op) == piece) {
                        var a = new FillAtom ();
                        a.kind = 1;
                        a.col = col;
                        a.op = op;
                        out_l.add (a);
                        break;
                    }
                }
                foreach (var cls in classes) {
                    var toks = tokens (inputs[col], cls);
                    for (int t = 0; t < toks.size; t++) {
                        foreach (var op in ops) {
                            string cased = FillAtom.apply_case (toks[t], op);
                            if (cased == piece) {
                                var a = new FillAtom ();
                                a.kind = 2;
                                a.col = col;
                                a.cls = cls;
                                a.index = t;
                                a.op = op;
                                out_l.add (a);
                                var b = new FillAtom ();
                                b.kind = 2;
                                b.col = col;
                                b.cls = cls;
                                b.index = toks.size - 1 - t;
                                b.from_end = true;
                                b.op = op;
                                out_l.add (b);
                                break;
                            }
                            if (piece.char_count () == 1 && cased.substring (0, cased.index_of_nth_char (1)) == piece) {
                                var a = new FillAtom ();
                                a.kind = 3;
                                a.col = col;
                                a.cls = cls;
                                a.index = t;
                                a.op = op;
                                out_l.add (a);
                                var b = new FillAtom ();
                                b.kind = 3;
                                b.col = col;
                                b.cls = cls;
                                b.index = toks.size - 1 - t;
                                b.from_end = true;
                                b.op = op;
                                out_l.add (b);
                                break;
                            }
                        }
                    }
                }
                var delims = new Gee.HashSet<string> ();
                unichar dc;
                int di = 0;
                while (inputs[col].get_next_char (ref di, out dc)) if (!dc.isalnum () && dc != ' ') delims.add (dc.to_string ());
                foreach (string d in delims) {
                    var parts = inputs[col].split (d);
                    if (parts.length < 2) continue;
                    for (int pi = 0; pi < parts.length; pi++) {
                        foreach (var op in ops) {
                            if (parts[pi] != "" && FillAtom.apply_case (parts[pi], op) == piece) {
                                var a = new FillAtom ();
                                a.kind = 5;
                                a.col = col;
                                a.text = d;
                                a.index = pi;
                                a.op = op;
                                out_l.add (a);
                                var b = new FillAtom ();
                                b.kind = 5;
                                b.col = col;
                                b.text = d;
                                b.index = parts.length - 1 - pi;
                                b.from_end = true;
                                b.op = op;
                                out_l.add (b);
                                break;
                            }
                        }
                    }
                }
                string src = inputs[col];
                int n = src.char_count ();
                int plen = piece.char_count ();
                if (plen > 0 && plen <= n) {
                    for (int st = 0; st + plen <= n; st++) {
                        int b1 = src.index_of_nth_char (st), b2 = src.index_of_nth_char (st + plen);
                        string sub = src.substring (b1, b2 - b1);
                        foreach (var op in ops) {
                            if (FillAtom.apply_case (sub, op) == piece) {
                                var a = new FillAtom ();
                                a.kind = 4;
                                a.col = col;
                                a.start = st;
                                a.length = plen;
                                a.op = op;
                                out_l.add (a);
                                var b = new FillAtom ();
                                b.kind = 4;
                                b.col = col;
                                b.start = n - st - plen;
                                b.length = plen;
                                b.from_end = true;
                                b.op = op;
                                out_l.add (b);
                                break;
                            }
                        }
                    }
                }
            }
            return out_l;
        }

        private static string run (Gee.List<FillAtom> prog, string[] inputs) {
            var sb = new StringBuilder ();
            foreach (var a in prog) {
                string v = a.eval (inputs);
                if (v == "\x01") return "\x01";
                sb.append (v);
            }
            return sb.str;
        }

        private class Search {
            public Gee.List<FillRow> inputs;
            public Gee.List<string> outputs;
            public string target;
            public Gee.HashMap<int, Gee.List<FillAtom>> cache = new Gee.HashMap<int, Gee.List<FillAtom>> ();
            public int budget;
            public int[] char_offsets;
            public Gee.List<FillAtom>? best;
            public int best_cost = int.MAX;
        }

        private static void consider (Search s, Gee.List<FillAtom> path) {
            var prog = merge_constants (path);
            for (int k = 1; k < s.inputs.size; k++) {
                if (run (prog, s.inputs[k].values) != s.outputs[k]) return;
            }
            int c = prog_cost (prog);
            if (c < s.best_cost) {
                s.best_cost = c;
                s.best = prog;
            }
        }

        private static void dfs (Search s, int pos, Gee.ArrayList<FillAtom> path, int max_segments) {
            if (s.budget-- <= 0) return;
            int n = s.char_offsets.length - 1;
            if (pos == n) {
                consider (s, path);
                return;
            }
            if (path.size >= max_segments) return;
            for (int end = n; end > pos; end--) {
                string piece = s.target.substring (s.char_offsets[pos], s.char_offsets[end] - s.char_offsets[pos]);
                int key = pos * 100000 + end;
                Gee.List<FillAtom> atoms;
                if (s.cache.has_key (key)) atoms = s.cache[key];
                else {
                    atoms = atoms_for (s.inputs[0].values, piece);
                    s.cache[key] = atoms;
                }
                foreach (var a in atoms) {
                    path.add (a);
                    dfs (s, end, path, max_segments);
                    path.remove_at (path.size - 1);
                    if (s.budget <= 0) return;
                }
                if (end > pos + 1 && !has_alnum (piece)) {
                    var cst = new FillAtom ();
                    cst.kind = 0;
                    cst.text = piece;
                    path.add (cst);
                    dfs (s, end, path, max_segments);
                    path.remove_at (path.size - 1);
                }
            }
            var c = new FillAtom ();
            c.kind = 0;
            c.text = s.target.substring (s.char_offsets[pos], s.char_offsets[pos + 1] - s.char_offsets[pos]);
            path.add (c);
            dfs (s, pos + 1, path, max_segments);
            path.remove_at (path.size - 1);
        }

        private static bool has_alnum (string t) {
            unichar c;
            int i = 0;
            while (t.get_next_char (ref i, out c)) if (c.isalnum ()) return true;
            return false;
        }

        private static Gee.ArrayList<FillAtom> merge_constants (Gee.List<FillAtom> prog) {
            var out_l = new Gee.ArrayList<FillAtom> ();
            foreach (var a in prog) {
                if (a.kind == 0 && out_l.size > 0 && out_l[out_l.size - 1].kind == 0) {
                    var prev = out_l[out_l.size - 1];
                    var m = new FillAtom ();
                    m.kind = 0;
                    m.text = prev.text + a.text;
                    out_l[out_l.size - 1] = m;
                } else {
                    out_l.add (a);
                }
            }
            return out_l;
        }

        private static int prog_cost (Gee.List<FillAtom> p) {
            int c = 0;
            foreach (var a in p) c += a.cost ();
            return c;
        }

        public static Gee.List<FillAtom>? learn (Gee.List<FillRow> inputs, Gee.List<string> outputs) {
            if (inputs.size == 0 || outputs.size == 0) return null;
            var s = new Search ();
            s.inputs = inputs;
            s.outputs = outputs;
            s.target = outputs[0];
            int n = s.target.char_count ();
            if (n == 0) return null;
            var offs = new int[n + 1];
            for (int i = 0; i < n + 1; i++) offs[i] = s.target.index_of_nth_char (i);
            s.char_offsets = offs;
            int found_at = -1;
            for (int depth = 1; depth <= int.min (n, 12); depth++) {
                s.budget = 30000;
                dfs (s, 0, new Gee.ArrayList<FillAtom> (), depth);
                if (s.best != null && found_at < 0) found_at = depth;
                if (found_at > 0 && depth >= found_at + 3) break;
            }
            return s.best;
        }

        public static string? apply (Gee.List<FillAtom> prog, string[] inputs) {
            string r = run (prog, inputs);
            return r == "\x01" ? null : r;
        }

        public static int fill (Document doc, Sheet s, int row, int col) {
            var region = doc.current_region (s, row, col);
            int[] input_cols = {};
            for (int c = region.c1; c <= region.c2; c++) if (c != col) input_cols += c;
            if (input_cols.length == 0) return 0;
            int last = region.r2;
            int first = region.r1;
            var ins = new Gee.ArrayList<FillRow> ();
            var outs = new Gee.ArrayList<string> ();
            var targets = new Gee.ArrayList<int> ();
            for (int r = first; r <= last; r++) {
                string[] vals = {};
                bool any = false;
                foreach (int c in input_cols) {
                    string t = s.value_at (r, c).display ();
                    if (t != "") any = true;
                    vals += t;
                }
                string outv = s.value_at (r, col).display ();
                if (outv != "") {
                    if (any) {
                        ins.add (new FillRow (vals));
                        outs.add (outv);
                    }
                } else if (any) {
                    targets.add (r);
                }
            }
            if (outs.size == 0 || targets.size == 0) return 0;
            int skip = 0;
            if (ins.size > 1) {
                var probe = learn (ins, outs);
                if (probe == null) skip = 1;
            }
            var use_in = new Gee.ArrayList<FillRow> ();
            var use_out = new Gee.ArrayList<string> ();
            for (int i = skip; i < ins.size; i++) {
                use_in.add (ins[i]);
                use_out.add (outs[i]);
            }
            var prog = learn (use_in, use_out);
            if (prog == null) return 0;
            int r1 = targets[0], r2 = targets[targets.size - 1];
            doc.begin_area (_("Flash Fill"), s, new Area (s, r1, col, r2, col));
            int n = 0;
            foreach (int r in targets) {
                string[] vals = {};
                foreach (int c in input_cols) vals += s.value_at (r, c).display ();
                string? v = apply (prog, vals);
                if (v == null) continue;
                s.set_input (r, col, v.has_prefix ("=") ? "'" + v : v);
                n++;
            }
            doc.commit ();
            return n;
        }
    }
}
