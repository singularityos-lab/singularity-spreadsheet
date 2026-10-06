namespace Singularity.Apps.Spreadsheet {

    public class SFrame {
        public Gee.HashMap<string, SVal> vars = new Gee.HashMap<string, SVal> ();
        public Gee.HashMap<string, string> types = new Gee.HashMap<string, string> ();
        public Gee.HashSet<string> consts = new Gee.HashSet<string> ();
        public SProc? proc;
        public string on_error = "";
        public bool in_handler;
        public int err_index;
    }

    public class ScriptRunner {
        public Document doc;
        public Workbook book;
        public ScriptHost host;
        public int max_steps = 50000000;
        public bool udf_mode;
        public Script? script;
        private int steps;
        private Gee.ArrayList<SFrame> frames = new Gee.ArrayList<SFrame> ();
        private SFrame globals = new SFrame ();
        private bool dirty;
        private bool in_step;
        private string label = "";
        private int depth;
        public int err_number;
        public string err_description = "";
        public string err_source = "";
        private int pending_err;
        private SVal? clipboard;
        private bool clipboard_cut;
        private Gee.HashMap<string, SVal> app_props = new Gee.HashMap<string, SVal> ();

        public ScriptRunner (Document doc, ScriptHost host) {
            this.doc = doc;
            this.book = doc.book;
            this.host = host;
            if (host.active == null || !book.sheets.contains (host.active)) {
                host.active = book.sheets[0];
                host.selected = null;
            }
        }

        public static string sources (Workbook book, bool with_vba) {
            var sb = new StringBuilder ();
            sb.append (book.scripts.all_source ());
            if (with_vba && book.vba != null) sb.append (book.vba.combined_source ());
            return sb.str;
        }

        public void load (string source) throws ScriptError {
            script = Script.parse_lenient (source);
            globals = new SFrame ();
            frames.clear ();
            steps = 0;
            try {
                exec_top (script.main);
            } catch (ExitError x) {
            }
        }

        public void run_source (string source, string? entry = null) throws ScriptError {
            var parsed = Script.parse (source);
            run_parsed (parsed, entry);
        }

        public void run_lenient (string source, string? entry) throws ScriptError {
            run_parsed (Script.parse_lenient (source), entry);
        }

        private void run_parsed (Script parsed, string? entry) throws ScriptError {
            script = parsed;
            globals = new SFrame ();
            frames.clear ();
            label = entry ?? _("Script");
            begin ();
            try {
                try {
                    exec_top (script.main);
                    if (entry != null) {
                        var p = script.procs[entry.down ()];
                        if (p == null) throw new ScriptError.RUNTIME ("0: %s", _("macro %s not found").printf (entry));
                        call_proc (p, {}, p.line, null);
                    }
                } catch (ExitError x) {
                }
            } catch (ScriptError e) {
                finish ();
                throw e;
            }
            finish ();
        }

        public void run_macro (string name) throws ScriptError {
            run_lenient (sources (book, true), name);
        }

        public SVal call_function (string name, SVal[] args) throws ScriptError {
            if (script == null) throw new ScriptError.RUNTIME ("0: %s", _("no script loaded"));
            var p = script.procs[name.down ()];
            if (p == null) throw new ScriptError.RUNTIME ("0: %s", _("%s not found").printf (name));
            steps = 0;
            try {
                return call_proc (p, args, p.line, null);
            } catch (ExitError x) {
                return SVal.empty ();
            }
        }

        public bool has_proc (string name) {
            return script != null && script.procs.has_key (name.down ());
        }

        private void begin () {
            steps = 0;
            if (udf_mode) return;
            doc.begin_book (label, host.active);
            in_step = true;
        }

        private void finish () {
            if (in_step) {
                doc.commit ();
                in_step = false;
            }
        }

        private void refresh () {
            if (dirty) {
                book.recalculate ();
                dirty = false;
            }
        }

        private void mutate (int line) throws ScriptError {
            if (udf_mode) throw rt (line, _("a function used in a cell cannot change the workbook"), 1004);
            dirty = true;
        }

        private void tick (int line) throws ScriptError {
            if (++steps > max_steps) throw new ScriptError.RUNTIME ("%d: %s", line, _("the script ran for too long"));
        }

        public ScriptError rt (int line, string msg, int number = 5) {
            pending_err = number;
            return new ScriptError.RUNTIME ("%d: %s", line, msg);
        }

        private SFrame frame () {
            return frames.size > 0 ? frames[frames.size - 1] : globals;
        }

        private SVal? lookup (string name) {
            string k = name.down ();
            var f = frame ();
            if (f.vars.has_key (k)) return f.vars[k];
            if (globals.vars.has_key (k)) return globals.vars[k];
            return null;
        }

        private SFrame owner_of (string name) {
            string k = name.down ();
            var f = frame ();
            if (f.vars.has_key (k)) return f;
            if (globals.vars.has_key (k)) return globals;
            return f;
        }

        private void assign_var (string name, SVal v, int line) throws ScriptError {
            string k = name.down ();
            var f = owner_of (name);
            if (f.consts.contains (k)) throw rt (line, _("cannot assign to constant %s").printf (name), 5);
            SVal val = v.kind == SKind.ARRAY ? v.copy () : v;
            if (f.types.has_key (k)) val = coerce (f.types[k], val, line);
            f.vars[k] = val;
        }

        public SVal coerce (string type, SVal raw, int line) throws ScriptError {
            var v = raw.kind == SKind.RANGE && type != "range" && type != "object" && type != "variant" ? deref (raw) : raw;
            switch (type) {
                case "integer":
                case "long":
                case "longlong":
                case "byte":
                case "longptr":
                    if (v.kind == SKind.ARRAY || v.is_object ()) return v;
                    double d = ScriptLib.bankers_round (num (v, line));
                    if (type == "integer" && (d < -32768 || d > 32767)) throw rt (line, _("overflow"), 6);
                    if (type == "byte" && (d < 0 || d > 255)) throw rt (line, _("overflow"), 6);
                    return SVal.n (d);
                case "double":
                case "single":
                case "currency":
                case "decimal":
                    if (v.kind == SKind.ARRAY || v.is_object ()) return v;
                    return SVal.n (num (v, line));
                case "string":
                    if (v.kind == SKind.ARRAY) {
                        var bytes = new ByteArray ();
                        foreach (var it in v.items) {
                            if (it.kind != SKind.NUM) return v;
                            uint8[] one = { (uint8) it.num };
                            bytes.append (one);
                        }
                        var sb = new StringBuilder ();
                        for (int i = 0; i + 1 < (int) bytes.len; i += 2) sb.append_unichar ((unichar) (bytes.data[i] | (bytes.data[i + 1] << 8)));
                        return SVal.s (sb.str);
                    }
                    return SVal.s (str (v));
                case "byte()":
                    if (v.kind != SKind.STR) return raw;
                    var bl = new Gee.ArrayList<SVal> ();
                    int bi = 0;
                    unichar ch;
                    while (v.str.get_next_char (ref bi, out ch)) {
                        bl.add (SVal.n (ch & 0xff));
                        bl.add (SVal.n ((ch >> 8) & 0xff));
                    }
                    return SVal.arr (bl);
                case "boolean":
                    if (v.kind == SKind.ARRAY) return v;
                    return SVal.b (truthy (v, line));
                case "date":
                    if (v.kind == SKind.STR) {
                        double serial;
                        if (!ScriptLib.parse_date_literal (v.str, out serial)) throw rt (line, _("type mismatch"), 13);
                        return SVal.date (serial);
                    }
                    if (v.kind == SKind.ARRAY || v.is_object ()) return v;
                    return SVal.date (num (v, line));
                default:
                    return raw;
            }
        }

        private static SVal default_of (string type) {
            switch (type) {
                case "integer": case "long": case "longlong": case "byte": case "double": case "single": case "currency": case "decimal": case "longptr":
                    return SVal.n (0);
                case "string": return SVal.s ("");
                case "boolean": return SVal.b (false);
                case "date": return SVal.date (0);
                case "object": case "range": case "worksheet": case "workbook": case "collection": case "dictionary": case "name":
                    return SVal.nothing ();
                default: return SVal.empty ();
            }
        }

        private void exec_top (SNode block) throws ScriptError, ExitError {
            foreach (var st in block.args) exec (st);
        }

        private void exec_block (SNode b) throws ScriptError, ExitError {
            var stmts = b.args;
            int i = 0;
            while (i < stmts.length) {
                try {
                    exec (stmts[i]);
                    i++;
                } catch (ExitError e) {
                    if (!e.message.has_prefix ("goto:")) throw e;
                    int idx = find_label (stmts, e.message.substring (5));
                    if (idx < 0) throw e;
                    i = idx + 1;
                }
            }
        }

        private void exec (SNode s) throws ScriptError, ExitError {
            tick (s.line);
            try {
                exec_inner (s);
            } catch (ScriptError e) {
                var f = frame ();
                if (f.on_error == "next" && e.code == ScriptError.RUNTIME && !e.message.contains (_("the script ran for too long"))) {
                    set_err (e);
                    return;
                }
                throw e;
            }
        }

        private void set_err (ScriptError e) {
            err_number = pending_err != 0 ? pending_err : 5;
            string m = e.message;
            int colon = m.index_of (": ");
            err_description = colon >= 0 ? m.substring (colon + 2) : m;
            err_source = "VBAProject";
            pending_err = 0;
        }

        private static void loop_exit (ExitError e, string a, string b) throws ExitError {
            if (e.message != a && e.message != b) throw e;
        }

        private int find_label (SNode[] stmts, string name) {
            for (int i = 0; i < stmts.length; i++) if (stmts[i].kind == SN.LABEL && stmts[i].name == name) return i;
            return -1;
        }

        private void run_body (SNode body, SFrame f) throws ScriptError, ExitError {
            var stmts = body.args;
            int i = 0;
            while (i < stmts.length) {
                try {
                    exec (stmts[i]);
                    i++;
                } catch (ExitError e) {
                    string m = e.message;
                    if (m.has_prefix ("goto:")) {
                        int idx = find_label (stmts, m.substring (5));
                        if (idx < 0) throw rt (stmts[i].line, _("label %s not found at procedure level").printf (m.substring (5)), 35);
                        i = idx + 1;
                        continue;
                    }
                    if (m.has_prefix ("resume:")) {
                        if (!f.in_handler) throw rt (stmts[i].line, _("Resume without error"), 20);
                        f.in_handler = false;
                        string t = m.substring (7);
                        if (t == "next") i = f.err_index + 1;
                        else if (t == "" || t == "0") i = f.err_index;
                        else {
                            int idx = find_label (stmts, t);
                            if (idx < 0) throw rt (stmts[i].line, _("label %s not found").printf (t), 35);
                            i = idx + 1;
                        }
                        err_number = 0;
                        err_description = "";
                        continue;
                    }
                    throw e;
                } catch (ScriptError e) {
                    if (e.code != ScriptError.RUNTIME || f.on_error == "" || f.on_error == "next" || f.on_error == "0" || f.in_handler || e.message.contains (_("the script ran for too long"))) throw e;
                    int idx = find_label (stmts, f.on_error);
                    if (idx < 0) throw e;
                    set_err (e);
                    f.err_index = i;
                    f.in_handler = true;
                    i = idx + 1;
                }
            }
        }

        private void declare (SNode dn) throws ScriptError {
            string k = dn.name.down ();
            var f = frame ();
            if (dn.until) {
                var target = owner_of (dn.name);
                var cur = target.vars.has_key (k) ? target.vars[k] : null;
                var fresh = make_array (dn.bounds, 0, target.types.has_key (k) ? target.types[k] : dn.type_name, dn.line);
                if (dn.preserve && cur != null && cur.kind == SKind.ARRAY) preserve_into (cur, fresh);
                target.vars[k] = fresh;
                return;
            }
            if (dn.type_name != "") f.types[k] = dn.flag ? dn.type_name + "()" : dn.type_name;
            SVal init;
            if (dn.flag) {
                init = dn.bounds.length > 0 ? make_array (dn.bounds, 0, dn.type_name, dn.line) : SVal.arr (new Gee.ArrayList<SVal> ());
            } else if (dn.b != null) {
                init = eval (dn.b);
                if (dn.type_name != "" && init.kind != SKind.ARRAY && !init.is_object ()) init = coerce (dn.type_name, init, dn.line);
            } else if (f.vars.has_key (k) && f == globals && frames.size > 0) {
                return;
            } else {
                init = default_of (dn.type_name);
            }
            f.vars[k] = init;
            if (dn.is_const) f.consts.add (k);
        }

        private SVal make_array (SNode[] bounds, int dim, string type, int line) throws ScriptError {
            var list = new Gee.ArrayList<SVal> ();
            if (dim >= bounds.length) return SVal.arr (list);
            int lo = 0, hi;
            var bnode = bounds[dim];
            if (bnode.kind == SN.BINARY && bnode.name == "to") {
                lo = (int) num (eval (bnode.a), line);
                hi = (int) num (eval (bnode.b), line);
            } else {
                hi = (int) num (eval (bnode), line);
            }
            if (hi - lo + 1 > 10000000) throw rt (line, _("out of memory"), 7);
            for (int i = lo; i <= hi; i++) {
                if (dim + 1 < bounds.length) list.add (make_array (bounds, dim + 1, type, line));
                else list.add (default_of (type));
            }
            return SVal.arr (list, lo);
        }

        private void preserve_into (SVal old, SVal fresh) {
            for (int i = 0; i < fresh.items.size; i++) {
                int idx = fresh.lbound + i - old.lbound;
                if (idx < 0 || idx >= old.items.size) continue;
                var o = old.items[idx];
                if (o.kind == SKind.ARRAY && fresh.items[i].kind == SKind.ARRAY) preserve_into (o, fresh.items[i]);
                else fresh.items[i] = o;
            }
        }

        private void exec_inner (SNode s) throws ScriptError, ExitError {
            switch (s.kind) {
                case SN.BLOCK:
                    exec_block (s);
                    return;
                case SN.LABEL:
                    return;
                case SN.DIM:
                    declare (s);
                    return;
                case SN.ASSIGN:
                    var v = eval (s.b);
                    if (!s.flag && v.kind == SKind.RANGE && v.items == null && !(s.a.kind == SN.IDENT && is_object_typed (s.a.name))) v = deref (v);
                    assign (s.a, v, s.flag);
                    return;
                case SN.EXPR:
                    eval_stmt (s.a);
                    return;
                case SN.IF:
                    if (truthy (eval (s.a), s.line)) exec (s.body);
                    else if (s.other != null) exec (s.other);
                    return;
                case SN.FOR:
                    double from = num (eval (s.a), s.line);
                    double to = num (eval (s.b), s.line);
                    double stp = s.c != null ? num (eval (s.c), s.line) : 1;
                    assign_var (s.name, SVal.n (from), s.line);
                    while (true) {
                        double v2 = num (lookup (s.name) ?? SVal.n (0), s.line);
                        if (stp >= 0 ? v2 > to : v2 < to) break;
                        try {
                            exec_block (s.body);
                        } catch (ExitError e) {
                            loop_exit (e, "for", "for");
                            break;
                        }
                        assign_var (s.name, SVal.n (num (lookup (s.name) ?? SVal.n (0), s.line) + stp), s.line);
                        tick (s.line);
                    }
                    return;
                case SN.FOREACH:
                    var items = iterate (eval (s.a), s.line);
                    foreach (var it in items) {
                        assign_var (s.name, it, s.line);
                        try {
                            exec_block (s.body);
                        } catch (ExitError e) {
                            loop_exit (e, "for", "for");
                            break;
                        }
                    }
                    return;
                case SN.WHILE:
                    while (truthy (eval (s.a), s.line)) {
                        try {
                            exec_block (s.body);
                        } catch (ExitError e) {
                            loop_exit (e, "while", "do");
                            break;
                        }
                        tick (s.line);
                    }
                    return;
                case SN.DO:
                    while (true) {
                        if (s.a != null && !s.post) {
                            bool c = truthy (eval (s.a), s.line);
                            if (s.until ? c : !c) break;
                        }
                        try {
                            exec_block (s.body);
                        } catch (ExitError e) {
                            loop_exit (e, "do", "while");
                            break;
                        }
                        if (s.a != null && s.post) {
                            bool c = truthy (eval (s.a), s.line);
                            if (s.until ? c : !c) break;
                        }
                        tick (s.line);
                    }
                    return;
                case SN.SELECT:
                    var subject = eval (s.a);
                    foreach (var cs in s.args) {
                        if (cs.flag || case_matches (subject, cs, s.line)) {
                            exec (cs.body);
                            return;
                        }
                    }
                    return;
                case SN.WITH:
                    var target = eval (s.a);
                    var f = frame ();
                    SVal? saved = f.vars.has_key ("__with") ? f.vars["__with"] : null;
                    f.vars["__with"] = target;
                    try {
                        exec_block (s.body);
                    } finally {
                        if (saved != null) f.vars["__with"] = saved;
                        else f.vars.unset ("__with");
                    }
                    return;
                case SN.EXIT:
                    throw new ExitError.EXIT (s.name);
                case SN.END:
                    throw new ExitError.EXIT ("end");
                case SN.RETURN:
                    if (s.a != null) frame ().vars["__result"] = eval (s.a);
                    throw new ExitError.EXIT ("function");
                case SN.GOTO:
                    throw new ExitError.EXIT ("goto:" + s.name);
                case SN.RESUME:
                    throw new ExitError.EXIT ("resume:" + s.name);
                case SN.ONERROR:
                    var fr = frame ();
                    fr.on_error = s.name == "0" ? "" : s.name;
                    if (s.name == "0" || s.name == "next") {
                        err_number = 0;
                        err_description = "";
                    }
                    if (s.name == "0") fr.in_handler = false;
                    return;
                case SN.ERASE:
                    foreach (var a in s.args) {
                        if (a.kind != SN.IDENT) continue;
                        var cur = lookup (a.name);
                        if (cur == null || cur.kind != SKind.ARRAY) continue;
                        foreach (var it in cur.items) {
                            if (it.kind != SKind.ARRAY) {
                                it.kind = SKind.EMPTY;
                                it.num = 0;
                                it.str = "";
                            }
                        }
                    }
                    return;
                case SN.FORBID:
                    throw rt (s.line, s.name, 70);
                default:
                    eval (s);
                    return;
            }
        }

        private bool is_object_typed (string name) {
            string k = name.down ();
            var f = owner_of (name);
            if (!f.types.has_key (k)) return false;
            string t = f.types[k];
            return t == "range" || t == "object" || t == "worksheet";
        }

        private bool case_matches (SVal subject, SNode cs, int line) throws ScriptError {
            foreach (var v in cs.args) {
                if (v.kind == SN.BINARY && v.name == "to") {
                    if (compare (subject, eval (v.a)) >= 0 && compare (subject, eval (v.b)) <= 0) return true;
                } else if (v.kind == SN.BINARY && v.a == null) {
                    if (truthy (binary (v.name, subject, eval (v.b), line), line)) return true;
                } else if (compare (subject, eval (v)) == 0) {
                    return true;
                }
            }
            return false;
        }

        private void eval_stmt (SNode n) throws ScriptError, ExitError {
            if (n.kind == SN.IDENT) {
                var p = script.procs[n.name.down ()];
                if (p != null) {
                    call_proc (p, {}, n.line, null);
                    return;
                }
                var v = lookup (n.name);
                if (v != null) return;
                call_named (n.name, {}, {}, n.line, false);
                return;
            }
            if (n.kind == SN.MEMBER) {
                var obj = eval (n.a);
                member (obj, n.name, {}, {}, n.line);
                return;
            }
            if (n.kind == SN.CALL && n.a.kind == SN.IDENT) {
                var p = script.procs[n.a.name.down ()];
                if (p != null) {
                    SVal[] args;
                    string[] names;
                    eval_args (n.args, out args, out names);
                    call_proc_named (p, args, names, n.line, n.args);
                    return;
                }
            }
            eval (n);
        }

        private void eval_args (SNode[] nodes, out SVal[] vals, out string[] names) throws ScriptError {
            SVal[] v = {};
            string[] nm = {};
            foreach (var an in nodes) {
                if (an.kind == SN.NAMED) {
                    v += eval (an.a);
                    nm += an.name;
                } else if (an.kind == SN.EMPTYV && an.name == "__missing") {
                    v += SVal.omitted ();
                    nm += "";
                } else {
                    v += eval (an);
                    nm += "";
                }
            }
            vals = v;
            names = nm;
        }

        private static SVal? arg_named (SVal[] args, string[] names, int pos, string name) {
            for (int i = 0; i < names.length; i++) if (names[i] == name.down ()) return args[i];
            if (pos < args.length && (pos >= names.length || names[pos] == "") && !args[pos].missing) return args[pos];
            return null;
        }

        public SVal eval (SNode n) throws ScriptError {
            switch (n.kind) {
                case SN.NUM: return SVal.n (n.num);
                case SN.DATE: return SVal.date (n.num);
                case SN.STR: return SVal.s (n.name);
                case SN.BOOL: return SVal.b (n.num != 0);
                case SN.NOTHING: return SVal.nothing ();
                case SN.EMPTYV: return SVal.empty ();
                case SN.NAMED: return eval (n.a);
                case SN.FORBID: throw rt (n.line, n.name, 70);
                case SN.NEW: return make_new (n.name, n.line);
                case SN.IDENT:
                    var v = lookup (n.name);
                    if (v != null) return v;
                    var p = script.procs[n.name.down ()];
                    if (p != null) {
                        try {
                            return call_proc (p, {}, n.line, null);
                        } catch (ExitError x) {
                            throw rt (n.line, _("unexpected exit"), 5);
                        }
                    }
                    if (script.enums.has_key (n.name.down ())) return SVal.n (script.enums[n.name.down ()]);
                    var mod = module_object (n.name);
                    if (mod != null) return mod;
                    return call_named (n.name, {}, {}, n.line, true);
                case SN.UNARY:
                    var u = eval (n.a);
                    if (n.name == "not") {
                        var du = deref (u);
                        if (du.kind == SKind.NUM) return SVal.n (~((int64) du.num));
                        return SVal.b (!truthy (du, n.line));
                    }
                    if (n.name == "-") {
                        var du = deref (u);
                        var r = SVal.n (-num (du, n.line));
                        return r;
                    }
                    return SVal.n (num (u, n.line));
                case SN.BINARY:
                    if (n.name == "is") {
                        var l = eval (n.a);
                        var r = eval (n.b);
                        return SVal.b (same_object (l, r));
                    }
                    return binary (n.name, eval (n.a), eval (n.b), n.line);
                case SN.MEMBER:
                    return member (eval (n.a), n.name, {}, {}, n.line);
                case SN.CALL:
                    SVal[] args;
                    string[] names;
                    if (n.a.kind == SN.IDENT) {
                        var local = lookup (n.a.name);
                        if (local != null && (local.kind == SKind.ARRAY || local.kind == SKind.RANGE || local.kind == SKind.COLL || local.kind == SKind.DICT || local.kind == SKind.SHEETS || local.kind == SKind.NAMES)) {
                            eval_args (n.args, out args, out names);
                            return index_value (local, args, n.line);
                        }
                        var proc = script.procs[n.a.name.down ()];
                        eval_args (n.args, out args, out names);
                        if (proc != null) {
                            try {
                                return call_proc_named (proc, args, names, n.line, n.args);
                            } catch (ExitError x) {
                                throw rt (n.line, _("unexpected exit"), 5);
                            }
                        }
                        return call_named (n.a.name, args, names, n.line, false);
                    }
                    eval_args (n.args, out args, out names);
                    if (n.a.kind == SN.MEMBER) return member (eval (n.a.a), n.a.name, args, names, n.line);
                    var target = eval (n.a);
                    return index_value (target, args, n.line);
                default:
                    throw rt (n.line, _("invalid expression"), 5);
            }
        }

        private const string[] WORKBOOK_MODULES = { "thisworkbook", "diesearbeitsmappe", "ceclasseur", "questacartella_di_lavoro", "estapasta_de_trabajo", "estapasta_de_trabalho", "dezewerkmap", "tentosesit", "denneprojektmappe", "tämätyökirja", "thisworkbook1" };

        public SVal? module_object (string name) {
            string k = name.down ();
            if (book.code_name != "" && book.code_name.down () == k) return SVal.obj (SKind.BOOK);
            foreach (var sh in book.sheets) if (sh.code_name != "" && sh.code_name.down () == k) return SVal.of_sheet (sh);
            if (book.vba != null) {
                var docs = new Gee.ArrayList<VbaModule> ();
                VbaModule? wb_module = null;
                foreach (var m in book.vba.modules) {
                    if (m.kind != VbaModuleKind.DOCUMENT) continue;
                    if (m.name.down () in WORKBOOK_MODULES || (book.code_name != "" && m.name.down () == book.code_name.down ())) wb_module = m;
                    else docs.add (m);
                }
                foreach (var m in book.vba.modules) {
                    if (m.name.down () != k) continue;
                    if (m.kind == VbaModuleKind.DOCUMENT) {
                        if (m == wb_module) return SVal.obj (SKind.BOOK);
                        var byname = book.find_sheet (m.name);
                        if (byname != null) return SVal.of_sheet (byname);
                        int idx = docs.index_of (m);
                        if (idx >= 0 && idx < book.sheets.size) return SVal.of_sheet (book.sheets[idx]);
                        return SVal.obj (SKind.BOOK);
                    }
                    var o = SVal.obj (SKind.APP, "module");
                    o.str = m.name;
                    return o;
                }
            }
            foreach (var m in book.scripts.modules) {
                if (m.name.down () == k) {
                    var o = SVal.obj (SKind.APP, "module");
                    o.str = m.name;
                    return o;
                }
            }
            return null;
        }

        private bool same_object (SVal a, SVal b) {
            if (b.kind == SKind.NOTHING) return a.kind == SKind.NOTHING || a.kind == SKind.EMPTY;
            if (a.kind == SKind.NOTHING) return b.kind == SKind.NOTHING;
            if (a == b) return true;
            if (a.kind == SKind.RANGE && b.kind == SKind.RANGE) return a.sheet == b.sheet && a.area.r1 == b.area.r1 && a.area.c1 == b.area.c1 && a.area.r2 == b.area.r2 && a.area.c2 == b.area.c2;
            if (a.kind == SKind.SHEET && b.kind == SKind.SHEET) return a.sheet == b.sheet;
            return a.kind == b.kind && a.kind == SKind.BOOK;
        }

        private SVal make_new (string type, int line) throws ScriptError {
            switch (type) {
                case "collection":
                case "vba.collection":
                    var c = SVal.obj (SKind.COLL);
                    c.items = new Gee.ArrayList<SVal> ();
                    c.keys = new Gee.ArrayList<string> ();
                    return c;
                case "dictionary":
                case "scripting.dictionary":
                    var d = SVal.obj (SKind.DICT);
                    d.items = new Gee.ArrayList<SVal> ();
                    d.keys = new Gee.ArrayList<string> ();
                    return d;
                default:
                    throw rt (line, _("class %s is not supported (class modules and external objects cannot be created)").printf (type), 429);
            }
        }

        private SVal index_value (SVal target, SVal[] args, int line) throws ScriptError {
            switch (target.kind) {
                case SKind.ARRAY:
                    if (args.length == 0) return target;
                    SVal cur = target;
                    foreach (var a in args) {
                        if (cur.kind != SKind.ARRAY) throw rt (line, _("subscript out of range"), 9);
                        int i = (int) num (a, line) - cur.lbound;
                        if (i < 0 || i >= cur.items.size) throw rt (line, _("subscript out of range"), 9);
                        cur = cur.items[i];
                    }
                    return cur;
                case SKind.RANGE: return range_item (target, args, line);
                case SKind.COLL: return coll_item (target, args[0], line);
                case SKind.DICT: return dict_get (target, args[0], line);
                case SKind.SHEETS: return SVal.of_sheet (sheet_of (deref (args[0]), line));
                case SKind.NAMES: return name_item (deref (args[0]), line);
                default:
                    if (args.length == 0) return target;
                    throw rt (line, _("this value cannot be indexed"), 13);
            }
        }

        public SVal range_item (SVal r, SVal[] args, int line) throws ScriptError {
            if (args.length == 0) return r;
            int i = (int) num (args[0], line);
            if (args.length == 1 || args[1].missing) {
                int cols = r.area.cols;
                int idx = i - 1;
                int rr = r.area.r1 + (cols > 0 ? idx / cols : 0), cc = r.area.c1 + (cols > 0 ? idx % cols : 0);
                if (idx < 0 && cols > 0) {
                    rr = r.area.r1 + (idx - cols + 1) / cols;
                    cc = r.area.c1 + ((idx % cols) + cols) % cols;
                }
                return cell_range (r.sheet, rr, cc, line);
            }
            int j;
            var a1 = deref (args[1]);
            if (a1.kind == SKind.STR && a1.str.length > 0 && a1.str[0].isalpha ()) j = Address.column_index (a1.str.up ()) + 1;
            else j = (int) num (a1, line);
            return cell_range (r.sheet, r.area.r1 + i - 1, r.area.c1 + j - 1, line);
        }

        private SVal cell_range (Sheet s, int r, int c, int line) throws ScriptError {
            if (r < 0 || c < 0 || r >= MAX_ROWS || c >= MAX_COLS) throw rt (line, _("application-defined or object-defined error"), 1004);
            return SVal.range (s, new Area.cell (s, r, c));
        }

        private void assign (SNode target, SVal v, bool is_set) throws ScriptError {
            switch (target.kind) {
                case SN.IDENT:
                    var p = script.procs[target.name.down ()];
                    if (p != null && p.is_function && frames.size > 0 && frame ().proc == p) {
                        frame ().vars["__result"] = v;
                        return;
                    }
                    var cur = lookup (target.name);
                    if (cur != null && cur.kind == SKind.RANGE && !is_set && v.kind != SKind.RANGE) {
                        set_property (cur, "value", v, target.line);
                        return;
                    }
                    assign_var (target.name, v, target.line);
                    return;
                case SN.MEMBER:
                    var obj = eval (target.a);
                    set_property (obj, target.name, v, target.line);
                    return;
                case SN.CALL:
                    if (target.a.kind == SN.IDENT) {
                        var arr = lookup (target.a.name);
                        if (arr != null && arr.kind == SKind.ARRAY) {
                            SVal c = arr;
                            for (int i = 0; i < target.args.length; i++) {
                                int idx = (int) num (eval (target.args[i]), target.line) - c.lbound;
                                if (c.kind != SKind.ARRAY || idx < 0 || idx >= c.items.size) throw rt (target.line, _("subscript out of range"), 9);
                                if (i == target.args.length - 1) c.items[idx] = v.kind == SKind.ARRAY ? v.copy () : v;
                                else c = c.items[idx];
                            }
                            return;
                        }
                        if (arr != null && arr.kind == SKind.DICT) {
                            dict_set (arr, eval (target.args[0]), v);
                            return;
                        }
                        if (target.a.name.down () == "mid" && target.args.length >= 2) {
                            var tn = target.args[0];
                            string orig = str (eval (tn));
                            int start = (int) num (eval (target.args[1]), target.line);
                            string rep = str (v);
                            int len = target.args.length > 2 ? (int) num (eval (target.args[2]), target.line) : rep.char_count ();
                            len = int.min (len, int.min (rep.char_count (), orig.char_count () - start + 1));
                            string res = TextFunctions.sub (orig, 0, start - 1) + TextFunctions.sub (rep, 0, len) + TextFunctions.sub (orig, start - 1 + len, orig.char_count ());
                            assign (tn, SVal.s (res), false);
                            return;
                        }
                    }
                    if (target.a.kind == SN.MEMBER && target.args.length > 0) {
                        var obj = eval (target.a.a);
                        SVal[] args;
                        string[] names;
                        eval_args (target.args, out args, out names);
                        var holder = member (obj, target.a.name, args, names, target.line);
                        if (holder.kind == SKind.RANGE) {
                            set_property (holder, "value", v, target.line);
                            return;
                        }
                        if (holder.kind == SKind.DICT) return;
                    }
                    var r = eval (target);
                    if (r.kind == SKind.RANGE) {
                        set_property (r, "value", v, target.line);
                        return;
                    }
                    throw rt (target.line, _("cannot assign to this expression"), 424);
                default:
                    throw rt (target.line, _("cannot assign to this expression"), 424);
            }
        }

        private SVal call_proc_named (SProc p, SVal[] args, string[] names, int line, SNode[]? nodes) throws ScriptError, ExitError {
            bool any_named = false;
            foreach (string n in names) if (n != "") any_named = true;
            if (!any_named) return call_proc (p, args, line, nodes);
            SVal[] ordered = new SVal[p.params.length];
            SNode[] onodes = new SNode[p.params.length];
            int positional = 0;
            for (int i = 0; i < args.length; i++) {
                if (names[i] == "") {
                    if (positional < ordered.length) {
                        ordered[positional] = args[i];
                        if (nodes != null) onodes[positional] = nodes[i];
                    }
                    positional++;
                    continue;
                }
                for (int k = 0; k < p.params.length; k++) {
                    if (p.params[k].name.down () == names[i]) {
                        ordered[k] = args[i];
                        if (nodes != null) onodes[k] = nodes[i].a;
                    }
                }
            }
            for (int k = 0; k < ordered.length; k++) if (ordered[k] == null) ordered[k] = SVal.omitted ();
            return call_proc (p, ordered, line, onodes);
        }

        public SVal call_proc (SProc p, SVal[] args, int line, SNode[]? nodes) throws ScriptError, ExitError {
            if (p.forbidden != "") throw rt (line, p.forbidden, 70);
            if (p.broken != "") throw rt (line, _("%s could not be read: %s").printf (p.name, p.broken), 35);
            if (++depth > 200) {
                depth--;
                throw rt (line, _("out of stack space"), 28);
            }
            var f = new SFrame ();
            f.proc = p;
            var byref_targets = new Gee.HashMap<int, SNode> ();
            for (int i = 0; i < p.params.length; i++) {
                var prm = p.params[i];
                string k = prm.name.down ();
                if (prm.paramarray) {
                    var rest = new Gee.ArrayList<SVal> ();
                    for (int j = i; j < args.length; j++) rest.add (args[j]);
                    f.vars[k] = SVal.arr (rest);
                    break;
                }
                SVal v;
                if (i < args.length && args[i] != null && !args[i].missing) {
                    v = args[i];
                    if (!prm.byval && nodes != null && i < nodes.length && nodes[i] != null && nodes[i].kind == SN.IDENT && lookup (nodes[i].name) != null) byref_targets[i] = nodes[i];
                    if (v.kind == SKind.ARRAY && prm.byval) v = v.copy ();
                } else if (prm.def != null) {
                    v = eval (prm.def);
                } else if (prm.optional) {
                    v = prm.type_name != "" && prm.type_name != "variant" ? default_of (prm.type_name) : SVal.omitted ();
                } else {
                    depth--;
                    throw rt (line, _("argument not optional (%s)").printf (prm.name), 449);
                }
                if (prm.type_name != "" && !v.missing) {
                    f.types[k] = prm.type_name;
                    if (v.kind != SKind.ARRAY && !v.is_object ()) v = coerce (prm.type_name, v, line);
                }
                f.vars[k] = v;
            }
            if (p.is_function) f.vars["__result"] = default_of (p.type_name);
            frames.add (f);
            try {
                run_body (p.body, f);
            } catch (ExitError e) {
                if (e.message == "end") {
                    frames.remove (f);
                    depth--;
                    throw e;
                }
                if (e.message.has_prefix ("goto:") || e.message.has_prefix ("resume:")) {
                    frames.remove (f);
                    depth--;
                    throw rt (line, _("label not found"), 35);
                }
            } catch (ScriptError e) {
                frames.remove (f);
                depth--;
                throw e;
            }
            var result = f.vars.has_key ("__result") ? f.vars["__result"] : SVal.empty ();
            frames.remove (f);
            depth--;
            foreach (var e in byref_targets.entries) {
                var prm = p.params[e.key];
                var nv = f.vars[prm.name.down ()];
                if (nv != null) {
                    try {
                        assign_var (e.value.name, nv, line);
                    } catch (ScriptError err) {
                    }
                }
            }
            return result;
        }

        public SVal deref (SVal v) {
            if (v.kind == SKind.RANGE && v.items == null) return range_value (v);
            if (v.kind == SKind.NAME) return name_value (v);
            return v;
        }

        public double num (SVal raw, int line) throws ScriptError {
            var v = deref (raw);
            switch (v.kind) {
                case SKind.NUM: return v.num;
                case SKind.BOOL: return v.num != 0 ? -1 : 0;
                case SKind.EMPTY: return 0;
                case SKind.STR:
                    string t = v.str.strip ();
                    if (t == "") throw rt (line, _("type mismatch: \"\" is not a number"), 13);
                    double d;
                    string f;
                    if (Input.parse_number (t, out d, out f)) return d;
                    if (ScriptLib.parse_date_literal (t, out d)) return d;
                    if (t.down () == "true") return -1;
                    if (t.down () == "false") return 0;
                    throw rt (line, _("type mismatch: \"%s\" is not a number").printf (v.str), 13);
                case SKind.ERRVAL:
                    throw rt (line, _("type mismatch"), 13);
                default:
                    throw rt (line, _("type mismatch: a number was expected"), 13);
            }
        }

        public string str (SVal raw) {
            var v = deref (raw);
            return v.text ();
        }

        public bool truthy (SVal raw, int line) throws ScriptError {
            var v = deref (raw);
            if (v.kind == SKind.BOOL || v.kind == SKind.NUM) return v.num != 0;
            if (v.kind == SKind.EMPTY) return false;
            if (v.kind == SKind.STR) {
                string l = v.str.down ().strip ();
                if (l == "true") return true;
                if (l == "false") return false;
                return num (v, line) != 0;
            }
            throw rt (line, _("type mismatch"), 13);
        }

        private int compare (SVal ra, SVal rb) {
            var a = deref (ra);
            var b = deref (rb);
            bool an = a.kind == SKind.NUM || a.kind == SKind.BOOL || a.kind == SKind.EMPTY;
            bool bn = b.kind == SKind.NUM || b.kind == SKind.BOOL || b.kind == SKind.EMPTY;
            if (a.kind == SKind.EMPTY && b.kind == SKind.STR) return strcmp ("", b.str);
            if (b.kind == SKind.EMPTY && a.kind == SKind.STR) return strcmp (a.str, "");
            if (an && bn) {
                double x = a.kind == SKind.EMPTY ? 0 : (a.kind == SKind.BOOL ? (a.num != 0 ? -1 : 0) : a.num);
                double y = b.kind == SKind.EMPTY ? 0 : (b.kind == SKind.BOOL ? (b.num != 0 ? -1 : 0) : b.num);
                return x < y ? -1 : (x > y ? 1 : 0);
            }
            if (an && b.kind == SKind.STR) {
                double d;
                string f;
                if (Input.parse_number (b.str.strip (), out d, out f)) {
                    double x = a.kind == SKind.EMPTY ? 0 : a.num;
                    return x < d ? -1 : (x > d ? 1 : 0);
                }
                return -1;
            }
            if (bn && a.kind == SKind.STR) return -compare (rb, ra);
            int c = strcmp (a.text (), b.text ());
            return c < 0 ? -1 : (c > 0 ? 1 : 0);
        }

        private SVal binary (string op, SVal ra, SVal rb, int line) throws ScriptError {
            var a = deref (ra);
            var b = deref (rb);
            switch (op) {
                case "&": return SVal.s (a.text () + b.text ());
                case "=": return SVal.b (compare (a, b) == 0);
                case "<>": return SVal.b (compare (a, b) != 0);
                case "<": return SVal.b (compare (a, b) < 0);
                case ">": return SVal.b (compare (a, b) > 0);
                case "<=": return SVal.b (compare (a, b) <= 0);
                case ">=": return SVal.b (compare (a, b) >= 0);
                case "like":
                    return SVal.b (like (a.text (), b.text ()));
            }
            if (op == "and" || op == "or" || op == "xor" || op == "eqv" || op == "imp") {
                if (a.kind == SKind.NUM && b.kind == SKind.NUM && (a.num != Math.floor (a.num) || b.num != Math.floor (b.num) || (a.num != 0 && a.num != -1) || (b.num != 0 && b.num != -1))) {
                    int64 x = (int64) a.num, y = (int64) b.num;
                    switch (op) {
                        case "and": return SVal.n (x & y);
                        case "or": return SVal.n (x | y);
                        case "xor": return SVal.n (x ^ y);
                        case "eqv": return SVal.n (~(x ^ y));
                        default: return SVal.n ((~x) | y);
                    }
                }
                bool x2 = truthy (a, line), y2 = truthy (b, line);
                switch (op) {
                    case "and": return SVal.b (x2 && y2);
                    case "or": return SVal.b (x2 || y2);
                    case "xor": return SVal.b (x2 != y2);
                    case "eqv": return SVal.b (x2 == y2);
                    default: return SVal.b (!x2 || y2);
                }
            }
            if (op == "+" && a.kind == SKind.STR && b.kind == SKind.STR) return SVal.s (a.str + b.str);
            if (op == "+" && ((a.kind == SKind.STR && b.kind == SKind.EMPTY) || (b.kind == SKind.STR && a.kind == SKind.EMPTY))) return SVal.s (a.text () + b.text ());
            double x = num (a, line), y = num (b, line);
            bool date_result = (a.is_date != b.is_date) && (op == "+" || op == "-");
            SVal res;
            switch (op) {
                case "+": res = SVal.n (x + y); break;
                case "-": res = SVal.n (x - y); break;
                case "*": res = SVal.n (x * y); break;
                case "/":
                    if (y == 0) throw rt (line, _("division by zero"), 11);
                    res = SVal.n (x / y);
                    break;
                case "\\":
                    double yy = ScriptLib.bankers_round (y);
                    if (yy == 0) throw rt (line, _("division by zero"), 11);
                    res = SVal.n (Math.trunc (ScriptLib.bankers_round (x) / yy));
                    break;
                case "mod":
                    double my = ScriptLib.bankers_round (y);
                    if (my == 0) throw rt (line, _("division by zero"), 11);
                    res = SVal.n (Math.fmod (ScriptLib.bankers_round (x), my));
                    break;
                case "^": res = SVal.n (Math.pow (x, y)); break;
                default: throw rt (line, _("unknown operator %s").printf (op), 5);
            }
            if (res.num.is_nan () || res.num.is_infinity () != 0) throw rt (line, _("overflow"), 6);
            res.is_date = date_result;
            return res;
        }

        private static bool like (string text, string pattern) {
            var sb = new StringBuilder ("^");
            for (int i = 0; i < pattern.length; i++) {
                char c = pattern[i];
                if (c == '*') sb.append (".*");
                else if (c == '?') sb.append (".");
                else if (c == '#') sb.append ("[0-9]");
                else if (c == '[') {
                    int end = pattern.index_of_char (']', i);
                    if (end < 0) {
                        sb.append ("\\[");
                        continue;
                    }
                    string cls = pattern.substring (i + 1, end - i - 1);
                    if (cls.has_prefix ("!")) cls = "^" + cls.substring (1);
                    sb.append ("[" + cls.replace ("\\", "\\\\") + "]");
                    i = end;
                } else {
                    sb.append (Regex.escape_string (c.to_string ()));
                }
            }
            sb.append ("$");
            try {
                return new Regex (sb.str, RegexCompileFlags.DOTALL).match (text);
            } catch (RegexError e) {
                return false;
            }
        }

        private Gee.ArrayList<SVal> iterate (SVal coll, int line) throws ScriptError {
            var list = new Gee.ArrayList<SVal> ();
            switch (coll.kind) {
                case SKind.ARRAY:
                    foreach (var it in coll.items) {
                        if (it.kind == SKind.ARRAY) list.add_all (iterate (it, line));
                        else list.add (it);
                    }
                    break;
                case SKind.RANGE:
                    foreach (var part in areas_of (coll)) {
                        var a = clamp (part);
                        for (int r = a.r1; r <= a.r2; r++) for (int c = a.c1; c <= a.c2; c++) list.add (SVal.range (part.sheet, new Area.cell (part.sheet, r, c)));
                    }
                    break;
                case SKind.SHEETS:
                    foreach (var s in book.sheets) list.add (SVal.of_sheet (s));
                    break;
                case SKind.COLL:
                    list.add_all (coll.items);
                    break;
                case SKind.DICT:
                    foreach (string k in coll.keys) list.add (SVal.s (k));
                    break;
                case SKind.NAMES:
                    foreach (string n in sorted_names ()) list.add (name_obj (n));
                    break;
                default:
                    throw rt (line, _("For Each needs a collection or an array"), 451);
            }
            return list;
        }

        private Gee.ArrayList<SVal> areas_of (SVal r) {
            var list = new Gee.ArrayList<SVal> ();
            if (r.items != null) list.add_all (r.items);
            else list.add (r);
            return list;
        }

        public static Gee.ArrayList<Area> merge_areas (Gee.List<Area> input) {
            var list = new Gee.ArrayList<Area> ();
            foreach (var a in input) {
                bool inside = false;
                foreach (var b in input) {
                    if (a == b) continue;
                    if (b.sheet == a.sheet && b.r1 <= a.r1 && b.c1 <= a.c1 && b.r2 >= a.r2 && b.c2 >= a.c2 && !(b.r1 == a.r1 && b.c1 == a.c1 && b.r2 == a.r2 && b.c2 == a.c2)) inside = true;
                }
                bool dup = false;
                foreach (var x in list) if (x.r1 == a.r1 && x.c1 == a.c1 && x.r2 == a.r2 && x.c2 == a.c2) dup = true;
                if (!inside && !dup) list.add (a.copy ());
            }
            bool changed = true;
            while (changed) {
                changed = false;
                for (int i = 0; i < list.size && !changed; i++) {
                    for (int j = 0; j < list.size && !changed; j++) {
                        if (i == j) continue;
                        var a = list[i], b = list[j];
                        if (a.sheet != b.sheet) continue;
                        Area? m = null;
                        if (a.r1 == b.r1 && a.r2 == b.r2 && b.c1 <= a.c2 + 1 && a.c1 <= b.c2 + 1) m = new Area (a.sheet, a.r1, int.min (a.c1, b.c1), a.r2, int.max (a.c2, b.c2));
                        else if (a.c1 == b.c1 && a.c2 == b.c2 && b.r1 <= a.r2 + 1 && a.r1 <= b.r2 + 1) m = new Area (a.sheet, int.min (a.r1, b.r1), a.c1, int.max (a.r2, b.r2), a.c2);
                        if (m != null) {
                            list[i] = m;
                            list.remove_at (j);
                            changed = true;
                        }
                    }
                }
            }
            return list;
        }

        private SVal multi (Sheet s, Gee.List<Area> areas) {
            if (areas.size == 0) return SVal.nothing ();
            if (areas.size == 1) return SVal.range (areas[0].sheet ?? s, areas[0]);
            var parts = new Gee.ArrayList<SVal> ();
            foreach (var a in areas) parts.add (SVal.range (a.sheet ?? s, a));
            var m = SVal.range (parts[0].sheet, parts[0].area);
            m.items = parts;
            return m;
        }

        public Area clamp (SVal r) {
            var a = r.area;
            int r2 = a.r2, c2 = a.c2;
            if (r2 == MAX_ROWS - 1) r2 = int.max (r.sheet.max_row, a.r1);
            if (c2 == MAX_COLS - 1) c2 = int.max (r.sheet.max_col, a.c1);
            return new Area (r.sheet, a.r1, a.c1, r2, c2);
        }

        private SVal from_cell (Sheet s, int r, int c) {
            var v = s.value_at (r, c);
            switch (v.kind) {
                case ValueKind.NUMBER:
                    if (NumberFormat.is_date_format (s.style_at (r, c).number_format)) return SVal.date (v.number);
                    return SVal.n (v.number);
                case ValueKind.TEXT: return SVal.s (v.text);
                case ValueKind.BOOL: return SVal.b (v.number != 0);
                case ValueKind.ERROR:
                    var e = new SVal (SKind.ERRVAL);
                    e.num = error_code (v.error);
                    e.str = v.error.to_string ();
                    return e;
                default: return SVal.empty ();
            }
        }

        private static int error_code (ErrorKind e) {
            switch (e) {
                case ErrorKind.NULL: return 2000;
                case ErrorKind.DIV0: return 2007;
                case ErrorKind.VALUE: return 2015;
                case ErrorKind.REF: return 2023;
                case ErrorKind.NAME: return 2029;
                case ErrorKind.NUM: return 2036;
                case ErrorKind.NA: return 2042;
                default: return 2015;
            }
        }

        public static SVal from_value (Value v) {
            switch (v.kind) {
                case ValueKind.NUMBER: return SVal.n (v.number);
                case ValueKind.TEXT: return SVal.s (v.text);
                case ValueKind.BOOL: return SVal.b (v.number != 0);
                case ValueKind.ERROR:
                    var e = new SVal (SKind.ERRVAL);
                    e.num = error_code (v.error);
                    e.str = v.error.to_string ();
                    return e;
                default: return SVal.empty ();
            }
        }

        public Value to_value (SVal raw) {
            var v = deref (raw);
            switch (v.kind) {
                case SKind.NUM: return Value.num (v.num);
                case SKind.STR: return Value.str (v.str);
                case SKind.BOOL: return Value.boolean (v.num != 0);
                case SKind.ERRVAL: return Value.err (ErrorKind.parse (v.str));
                case SKind.ARRAY:
                    int rows = v.items.size;
                    int cols = 1;
                    bool nested = false;
                    foreach (var it in v.items) if (it.kind == SKind.ARRAY) {
                        cols = int.max (cols, it.items.size);
                        nested = true;
                    }
                    if (!nested) {
                        var m1 = new Value[1, int.max (rows, 1)];
                        for (int j = 0; j < rows; j++) m1[0, j] = to_value (v.items[j]);
                        if (rows == 0) m1[0, 0] = Value.empty ();
                        return Value.matrix (m1);
                    }
                    var m = new Value[rows, cols];
                    for (int i = 0; i < rows; i++) {
                        for (int j = 0; j < cols; j++) {
                            var it = v.items[i];
                            if (it.kind == SKind.ARRAY) m[i, j] = j < it.items.size ? to_value (it.items[j]) : Value.empty ();
                            else m[i, j] = j == 0 ? to_value (it) : Value.empty ();
                        }
                    }
                    return Value.matrix (m);
                default: return Value.empty ();
            }
        }

        private static void undate (SVal v) {
            if (v.kind == SKind.NUM) v.is_date = false;
            if (v.kind == SKind.ARRAY) foreach (var it in v.items) undate (it);
        }

        public SVal range_value (SVal r) {
            refresh ();
            var a = r.area;
            if (a.is_single ()) return from_cell (r.sheet, a.r1, a.c1);
            var ca = clamp (r);
            var rows = new Gee.ArrayList<SVal> ();
            for (int i = ca.r1; i <= ca.r2; i++) {
                var row = new Gee.ArrayList<SVal> ();
                for (int j = ca.c1; j <= ca.c2; j++) row.add (from_cell (r.sheet, i, j));
                rows.add (SVal.arr (row, 1));
            }
            return SVal.arr (rows, 1);
        }

        private string input_text (SVal v) {
            switch (v.kind) {
                case SKind.NUM: return Value.format_number_general_full (v.num);
                case SKind.BOOL: return v.num != 0 ? "TRUE" : "FALSE";
                case SKind.ERRVAL: return v.str != "" ? v.str : "#VALUE!";
                default: return v.text ();
            }
        }

        private void put_cell (Sheet s, int r, int c, SVal item) {
            if (item.kind == SKind.STR && item.str.has_prefix ("'")) {
                s.set_input (r, c, item.str);
                return;
            }
            s.set_input (r, c, input_text (item));
            if (item.kind == SKind.NUM && item.is_date) {
                var st = s.style_at (r, c);
                if (!NumberFormat.is_date_format (st.number_format)) {
                    var ns = st.copy ();
                    ns.number_format = item.num == Math.floor (item.num) ? LocaleInfo.get ().short_date_format () : LocaleInfo.get ().short_date_format () + " h:mm";
                    s.set_style (r, c, book.intern (ns));
                }
            }
        }

        private SVal element (SVal v, int ri, int ci, Area a) {
            if (v.kind != SKind.ARRAY) return v;
            bool flat = v.items.size > 0 && v.items[0].kind != SKind.ARRAY;
            if (flat) {
                if (a.rows == 1) return ci < v.items.size ? v.items[ci] : SVal.s ("#N/A");
                if (a.cols == 1 && v.items.size == a.rows && a.rows > 1) return ri < v.items.size ? v.items[ri] : SVal.s ("#N/A");
                return ci < v.items.size ? v.items[ci] : SVal.s ("#N/A");
            }
            if (ri >= v.items.size) return SVal.s ("#N/A");
            var row = v.items[ri];
            if (row.kind == SKind.ARRAY) return ci < row.items.size ? row.items[ci] : SVal.s ("#N/A");
            return ci == 0 ? row : SVal.s ("#N/A");
        }

        private void set_cells (SVal r, SVal raw, bool formula, bool r1c1, int line) throws ScriptError {
            mutate (line);
            var v = raw.kind == SKind.RANGE ? range_value (raw) : raw;
            foreach (var part in areas_of (r)) {
                var a = part.area;
                var s = part.sheet;
                int maxr = a.r2 == MAX_ROWS - 1 && v.kind != SKind.ARRAY ? int.max (s.max_row, a.r1) : a.r2;
                int maxc = a.c2;
                if ((int64) (maxr - a.r1 + 1) * (maxc - a.c1 + 1) > 5000000) throw rt (line, _("the range is too large to fill"), 1004);
                Node? base_node = null;
                string text0 = v.kind != SKind.ARRAY ? input_text (v) : "";
                if (v.kind != SKind.ARRAY && text0.has_prefix ("=") && !r1c1 && (maxr > a.r1 || maxc > a.c1)) {
                    try {
                        base_node = Formula.parse (text0, book, s);
                    } catch (FormulaError e) {
                        base_node = null;
                    }
                }
                for (int i = a.r1; i <= maxr; i++) {
                    for (int j = a.c1; j <= maxc; j++) {
                        SVal item = element (v, i - a.r1, j - a.c1, new Area (s, a.r1, a.c1, maxr, maxc));
                        if (r1c1 && item.kind == SKind.STR && item.str.has_prefix ("=")) {
                            s.set_input (i, j, ScriptLib.r1c1_to_a1 (item.str, i, j));
                        } else if (base_node != null) {
                            s.set_input (i, j, Formula.to_text (Formula.shifted (base_node, i - a.r1, j - a.c1), s));
                        } else {
                            put_cell (s, i, j, item);
                        }
                    }
                }
            }
        }

        private delegate void StyleEdit (CellStyle st);

        private void edit_style (SVal r, StyleEdit edit, int line) throws ScriptError {
            mutate (line);
            foreach (var part in areas_of (r)) {
                var a = clamp (part);
                var s = part.sheet;
                if ((int64) a.rows * a.cols > 2000000) throw rt (line, _("the range is too large to format"), 1004);
                for (int i = a.r1; i <= a.r2; i++) {
                    for (int j = a.c1; j <= a.c2; j++) {
                        var st = s.style_at (i, j).copy ();
                        edit (st);
                        s.set_style (i, j, book.intern (st));
                    }
                }
            }
        }

        private static string rgb_hex (int n) {
            return "#%02x%02x%02x".printf (n & 0xff, (n >> 8) & 0xff, (n >> 16) & 0xff);
        }

        private static int hex_rgb (string hex) {
            string h = hex.has_prefix ("#") ? hex.substring (1) : hex;
            if (h.length != 6) return 0;
            int64 v = int64.parse ("0x" + h);
            int r = (int) ((v >> 16) & 0xff), g = (int) ((v >> 8) & 0xff), b = (int) (v & 0xff);
            return r | (g << 8) | (b << 16);
        }

        private string color_text (SVal v, int line) throws ScriptError {
            var d = deref (v);
            if (d.kind == SKind.NUM) return rgb_hex ((int) d.num);
            return d.text ();
        }

        private static string[] PALETTE = {
            "#000000", "#ffffff", "#ff0000", "#00ff00", "#0000ff", "#ffff00", "#ff00ff", "#00ffff", "#800000", "#008000", "#000080", "#808000", "#800080", "#008080", "#c0c0c0", "#808080",
            "#9999ff", "#993366", "#ffffcc", "#ccffff", "#660066", "#ff8080", "#0066cc", "#ccccff", "#000080", "#ff00ff", "#ffff00", "#00ffff", "#800080", "#800000", "#008080", "#0000ff",
            "#00ccff", "#ccffff", "#ccffcc", "#ffff99", "#99ccff", "#ff99cc", "#cc99ff", "#ffcc99", "#3366ff", "#33cccc", "#99cc00", "#ffcc00", "#ff9900", "#ff6600", "#666699", "#969696",
            "#003366", "#339966", "#003300", "#333300", "#993300", "#993366", "#333399", "#333333"
        };

        private void set_border (SVal r, string facet, string prop, SVal v, int line) throws ScriptError {
            int idx = facet.length > 8 ? int.parse (facet.substring (8)) : 0;
            BorderStyle bs = BorderStyle.THIN;
            string color = "";
            var d = deref (v);
            if (prop == "linestyle") {
                int n = (int) num (d, line);
                bs = n == -4142 ? BorderStyle.NONE : (n == -4118 ? BorderStyle.DOTTED : (n == -4115 ? BorderStyle.DASHED : (n == -4119 ? BorderStyle.DOUBLE : BorderStyle.THIN)));
            } else if (prop == "weight") {
                int n = (int) num (d, line);
                bs = n == -4138 ? BorderStyle.MEDIUM : (n == 4 ? BorderStyle.THICK : BorderStyle.THIN);
            } else if (prop == "color") {
                color = color_text (d, line);
            } else if (prop == "colorindex") {
                int ci = (int) num (d, line);
                color = ci >= 1 && ci <= 56 ? PALETTE[ci - 1] : "";
            } else {
                return;
            }
            foreach (var part in areas_of (r)) {
                var a = clamp (part);
                var s = part.sheet;
                mutate (line);
                for (int i = a.r1; i <= a.r2; i++) {
                    for (int j = a.c1; j <= a.c2; j++) {
                        var st = s.style_at (i, j).copy ();
                        bool all = idx == 0;
                        if (all || (idx == 7 && j == a.c1) || (idx == 11 && j > a.c1)) st.left = new Border (prop == "color" || prop == "colorindex" ? (st.left.style == BorderStyle.NONE ? BorderStyle.THIN : st.left.style) : bs, color != "" ? color : st.left.color);
                        if (all || (idx == 10 && j == a.c2) || (idx == 11 && j < a.c2)) st.right = new Border (prop == "color" || prop == "colorindex" ? (st.right.style == BorderStyle.NONE ? BorderStyle.THIN : st.right.style) : bs, color != "" ? color : st.right.color);
                        if (all || (idx == 8 && i == a.r1) || (idx == 12 && i > a.r1)) st.top = new Border (prop == "color" || prop == "colorindex" ? (st.top.style == BorderStyle.NONE ? BorderStyle.THIN : st.top.style) : bs, color != "" ? color : st.top.color);
                        if (all || (idx == 9 && i == a.r2) || (idx == 12 && i < a.r2)) st.bottom = new Border (prop == "color" || prop == "colorindex" ? (st.bottom.style == BorderStyle.NONE ? BorderStyle.THIN : st.bottom.style) : bs, color != "" ? color : st.bottom.color);
                        s.set_style (i, j, book.intern (st));
                    }
                }
            }
        }

        private void set_hidden (SVal r, bool rows, bool hide, int line) throws ScriptError {
            mutate (line);
            foreach (var part in areas_of (r)) {
                var a = part.area;
                var s = part.sheet;
                int from = rows ? a.r1 : a.c1;
                int to = rows ? a.r2 : a.c2;
                if (to - from > 100000) to = from + 100000;
                for (int k = from; k <= to; k++) {
                    var set = rows ? s.hidden_rows : s.hidden_cols;
                    if (hide) set.add (k);
                    else set.remove (k);
                }
            }
        }

        public void set_property (SVal obj, string name, SVal v, int line) throws ScriptError {
            string p = name.down ();
            if ((obj.kind == SKind.BOOK || obj.kind == SKind.SHEET || (obj.kind == SKind.APP && obj.facet == "module")) && globals.vars.has_key (p) && !builtin_member (obj, p)) {
                globals.vars[p] = v;
                return;
            }
            switch (obj.kind) {
                case SKind.SHEET:
                    var s = obj.sheet;
                    switch (p) {
                        case "name":
                            mutate (line);
                            string nn = str (v);
                            if (nn == "" || nn.length > 31) throw rt (line, _("invalid sheet name"), 1004);
                            var other = book.find_sheet (nn);
                            if (other != null && other != s) throw rt (line, _("a sheet named %s already exists").printf (nn), 1004);
                            book.rename_sheet (s, nn);
                            return;
                        case "visible":
                            mutate (line);
                            var dv = deref (v);
                            int vis = dv.kind == SKind.BOOL ? (dv.num != 0 ? 0 : 1) : ((int) num (dv, line) == -1 ? 0 : ((int) num (dv, line) == 2 ? 2 : 1));
                            s.visibility = vis;
                            return;
                        case "tabcolor":
                            s.tab_color = color_text (v, line);
                            return;
                        case "displaygridlines":
                        case "showgridlines":
                            s.show_grid = truthy (v, line);
                            return;
                        case "enableselection":
                        case "scrollarea":
                        case "enablecalculation":
                        case "enableautofilter":
                        case "enableoutlining":
                            return;
                    }
                    break;
                case SKind.APP:
                case SKind.BOOK:
                    switch (p) {
                        case "calculation":
                            book.manual_calc = (int) num (v, line) == -4135;
                            return;
                        case "screenupdating":
                        case "displayalerts":
                        case "enableevents":
                        case "cutcopymode":
                        case "statusbar":
                        case "interactive":
                        case "displaystatusbar":
                        case "windowstate":
                        case "cursor":
                        case "askToUpdateLinks":
                        case "asktoupdatelinks":
                        case "displayformulabar":
                        case "iteration":
                        case "maxiterations":
                        case "caption":
                        case "saved":
                        case "calculatebeforesave":
                            if (p == "iteration") book.iterative = truthy (v, line);
                            if (p == "maxiterations") book.max_iterations = (int) num (v, line);
                            if (p == "cutcopymode" && !truthy (v, line)) clipboard = null;
                            app_props[p] = deref (v);
                            return;
                    }
                    if (obj.kind == SKind.APP) {
                        app_props[p] = deref (v);
                        return;
                    }
                    break;
                case SKind.WINDOW:
                    switch (p) {
                        case "displaygridlines":
                            host.active.show_grid = truthy (v, line);
                            return;
                        case "freezepanes":
                            var sel = host.selected ?? new Area.cell (host.active, 0, 0);
                            if (truthy (v, line)) {
                                host.active.freeze_rows = sel.r1;
                                host.active.freeze_cols = sel.c1;
                            } else {
                                host.active.freeze_rows = 0;
                                host.active.freeze_cols = 0;
                            }
                            return;
                        case "splitrow":
                            host.active.freeze_rows = (int) num (v, line);
                            return;
                        case "splitcolumn":
                            host.active.freeze_cols = (int) num (v, line);
                            return;
                        default:
                            app_props["window." + p] = deref (v);
                            return;
                    }
                case SKind.PAGESETUP:
                    set_page_setup (obj.sheet, p, v, line);
                    return;
                case SKind.NAME:
                    string key = obj.str;
                    switch (p) {
                        case "refersto":
                        case "referstolocal":
                            book.names[key] = normalize_refers (v, line);
                            dirty = true;
                            return;
                        case "referstor1c1":
                            string t = str (v);
                            book.names[key] = ScriptLib.r1c1_to_a1 (t, 0, 0);
                            dirty = true;
                            return;
                        case "name":
                            string def = book.names[key];
                            book.names.unset (key);
                            book.names[str (v)] = def;
                            obj.str = str (v);
                            return;
                        case "visible":
                        case "comment":
                            return;
                    }
                    break;
                case SKind.ERR:
                    if (p == "number") err_number = (int) num (v, line);
                    else if (p == "description") err_description = str (v);
                    else if (p == "source") err_source = str (v);
                    return;
                case SKind.RANGE:
                    set_range_property (obj, p, v, line);
                    return;
                case SKind.DICT:
                    if (p == "comparemode") return;
                    if (p == "item") return;
                    break;
                default:
                    break;
            }
            throw rt (line, _("property %s cannot be set here").printf (name), 438);
        }

        private string normalize_refers (SVal v, int line) throws ScriptError {
            if (v.kind == SKind.RANGE) return "=" + qualified_address (v, true);
            string t = str (v);
            return t.has_prefix ("=") ? t : "=" + t;
        }

        private void set_range_property (SVal obj, string p, SVal v, int line) throws ScriptError {
            if (obj.facet.has_prefix ("borders")) {
                set_border (obj, obj.facet, p, v, line);
                return;
            }
            if (obj.facet == "interior" && (p == "color" || p == "colorindex" || p == "pattern")) {
                if (p == "pattern") {
                    if ((int) num (v, line) == -4142) edit_style (obj, (st) => st.fill = "", line);
                    return;
                }
                string fill = p == "color" ? color_text (v, line) : ((int) num (v, line) >= 1 && (int) num (v, line) <= 56 ? PALETTE[(int) num (v, line) - 1] : "");
                edit_style (obj, (st) => st.fill = fill, line);
                return;
            }
            if (obj.facet == "font") {
                switch (p) {
                    case "bold": bool b = truthy (v, line); edit_style (obj, (st) => st.bold = b, line); return;
                    case "italic": bool i = truthy (v, line); edit_style (obj, (st) => st.italic = i, line); return;
                    case "underline":
                        var du = deref (v);
                        bool u = du.kind == SKind.BOOL ? du.num != 0 : (int) num (du, line) != -4142;
                        edit_style (obj, (st) => st.underline = u, line);
                        return;
                    case "strikethrough": bool k = truthy (v, line); edit_style (obj, (st) => st.strike = k, line); return;
                    case "size": double sz = num (v, line); edit_style (obj, (st) => st.font_size = sz, line); return;
                    case "name": string fn = str (v); edit_style (obj, (st) => st.font_family = fn, line); return;
                    case "color": string c = color_text (v, line); edit_style (obj, (st) => st.color = c, line); return;
                    case "colorindex":
                        int ci = (int) num (v, line);
                        string pc = ci >= 1 && ci <= 56 ? PALETTE[ci - 1] : "";
                        edit_style (obj, (st) => st.color = pc, line);
                        return;
                    case "fontstyle":
                        string fs = str (v).down ();
                        edit_style (obj, (st) => {
                            st.bold = fs.contains ("bold");
                            st.italic = fs.contains ("italic");
                        }, line);
                        return;
                }
            }
            switch (p) {
                case "value":
                case "value2":
                    set_cells (obj, v, false, false, line);
                    return;
                case "formula":
                case "formulalocal":
                case "formulaarray":
                case "formula2":
                    set_cells (obj, v, true, false, line);
                    return;
                case "formular1c1":
                case "formular1c1local":
                case "formula2r1c1":
                    set_cells (obj, v, true, true, line);
                    return;
                case "numberformat":
                case "numberformatlocal":
                    string f = str (v);
                    edit_style (obj, (st) => st.number_format = f, line);
                    return;
                case "bold": bool b2 = truthy (v, line); edit_style (obj, (st) => st.bold = b2, line); return;
                case "italic": bool i2 = truthy (v, line); edit_style (obj, (st) => st.italic = i2, line); return;
                case "wraptext": bool wr = truthy (v, line); edit_style (obj, (st) => st.wrap = wr, line); return;
                case "fontsize": double sz2 = num (v, line); edit_style (obj, (st) => st.font_size = sz2, line); return;
                case "fontname": string fn2 = str (v); edit_style (obj, (st) => st.font_family = fn2, line); return;
                case "fontcolor": string c2 = color_text (v, line); edit_style (obj, (st) => st.color = c2, line); return;
                case "fill": string fill2 = color_text (v, line); edit_style (obj, (st) => st.fill = fill2, line); return;
                case "indentlevel": int ind = (int) num (v, line); edit_style (obj, (st) => st.indent = ind, line); return;
                case "locked": bool lk = truthy (v, line); edit_style (obj, (st) => st.locked = lk, line); return;
                case "formulahidden": bool fh = truthy (v, line); edit_style (obj, (st) => st.hidden = fh, line); return;
                case "shrinktofit": bool sh = truthy (v, line); edit_style (obj, (st) => st.shrink = sh, line); return;
                case "horizontalalignment":
                    var dv = deref (v);
                    HAlign h = HAlign.GENERAL;
                    if (dv.kind == SKind.STR) {
                        string al = dv.str.down ();
                        h = al == "left" ? HAlign.LEFT : (al == "center" ? HAlign.CENTER : (al == "right" ? HAlign.RIGHT : HAlign.GENERAL));
                    } else {
                        int n = (int) num (dv, line);
                        h = n == -4131 ? HAlign.LEFT : (n == -4108 || n == 7 ? HAlign.CENTER : (n == -4152 ? HAlign.RIGHT : (n == -4130 ? HAlign.JUSTIFY : (n == 5 ? HAlign.FILL : HAlign.GENERAL))));
                    }
                    edit_style (obj, (st) => st.halign = h, line);
                    return;
                case "verticalalignment":
                    int vn = (int) num (v, line);
                    VAlign va = vn == -4160 ? VAlign.TOP : (vn == -4108 || vn == -4130 || vn == -4117 ? VAlign.CENTER : VAlign.BOTTOM);
                    edit_style (obj, (st) => st.valign = va, line);
                    return;
                case "note":
                case "comment":
                    mutate (line);
                    obj.sheet.ensure (obj.area.r1, obj.area.c1).note = str (v);
                    return;
                case "columnwidth":
                    mutate (line);
                    int w = (int) Math.round (num (v, line) * 7 + 5);
                    foreach (var part in areas_of (obj)) for (int c = part.area.c1; c <= part.area.c2 && c < part.area.c1 + 16384; c++) part.sheet.col_widths[c] = w;
                    return;
                case "rowheight":
                    mutate (line);
                    int h2 = (int) Math.round (num (v, line) / 0.75);
                    foreach (var part in areas_of (obj)) for (int r = part.area.r1; r <= part.area.r2 && r < part.area.r1 + 100000; r++) part.sheet.row_heights[r] = h2;
                    return;
                case "hidden":
                    bool hide = truthy (v, line);
                    bool rows = obj.count_mode == 1 || (obj.area.c1 == 0 && obj.area.c2 == MAX_COLS - 1);
                    bool cols = obj.count_mode == 2 || (obj.area.r1 == 0 && obj.area.r2 == MAX_ROWS - 1);
                    if (!rows && !cols) throw rt (line, _("unable to set the Hidden property: use EntireRow, EntireColumn, Rows or Columns"), 1004);
                    set_hidden (obj, rows, hide, line);
                    return;
                case "orientation":
                    var ov = deref (v);
                    int on = (int) num (ov, line);
                    int rot = on == -4128 ? 0 : (on == -4171 ? 90 : (on == -4170 ? 180 : (on == -4166 ? 255 : (on >= 0 ? on : 90 - on))));
                    edit_style (obj, (st) => st.rotation = rot, line);
                    return;
                case "name":
                    book.names[str (v)] = "=" + qualified_address (obj, true);
                    dirty = true;
                    return;
                case "mergecells":
                    if (truthy (v, line)) range_member (obj, "merge", {}, {}, line);
                    else range_member (obj, "unmerge", {}, {}, line);
                    return;
                case "color":
                    string cf = color_text (v, line);
                    edit_style (obj, (st) => st.fill = cf, line);
                    return;
                case "interiorcolor":
                case "backcolor":
                    string bc = color_text (v, line);
                    edit_style (obj, (st) => st.fill = bc, line);
                    return;
                case "underline":
                    bool un = truthy (v, line);
                    edit_style (obj, (st) => st.underline = un, line);
                    return;
                case "strikethrough":
                    bool sk = truthy (v, line);
                    edit_style (obj, (st) => st.strike = sk, line);
                    return;
                case "align":
                    set_range_property (obj, "horizontalalignment", v, line);
                    return;
                case "style":
                    return;
            }
            throw rt (line, _("range property %s cannot be set").printf (p), 438);
        }

        public string qualified_address (SVal r, bool abs) {
            string[] parts = {};
            foreach (var part in areas_of (r)) parts += Address.quote_sheet (part.sheet.name) + "!" + address_of (part.area, abs, abs);
            return string.joinv (",", parts);
        }

        private static string address_of (Area a, bool abs_r, bool abs_c) {
            if (a.c1 == 0 && a.c2 == MAX_COLS - 1) return "%s%d:%s%d".printf (abs_r ? "$" : "", a.r1 + 1, abs_r ? "$" : "", a.r2 + 1);
            if (a.r1 == 0 && a.r2 == MAX_ROWS - 1) return "%s%s:%s%s".printf (abs_c ? "$" : "", Address.column_name (a.c1), abs_c ? "$" : "", Address.column_name (a.c2));
            string s = Address.cell (a.r1, a.c1, abs_r, abs_c);
            if (!a.is_single ()) s += ":" + Address.cell (a.r2, a.c2, abs_r, abs_c);
            return s;
        }

        private static string r1c1_address (Area a) {
            if (a.c1 == 0 && a.c2 == MAX_COLS - 1) return a.r1 == a.r2 ? "R%d".printf (a.r1 + 1) : "R%d:R%d".printf (a.r1 + 1, a.r2 + 1);
            if (a.r1 == 0 && a.r2 == MAX_ROWS - 1) return a.c1 == a.c2 ? "C%d".printf (a.c1 + 1) : "C%d:C%d".printf (a.c1 + 1, a.c2 + 1);
            if (a.is_single ()) return "R%dC%d".printf (a.r1 + 1, a.c1 + 1);
            return "R%dC%d:R%dC%d".printf (a.r1 + 1, a.c1 + 1, a.r2 + 1, a.c2 + 1);
        }

        private Area? parse_address (Sheet s, string addr) {
            string t = addr.strip ().replace ("$", "");
            int bang = t.last_index_of ("!");
            if (bang >= 0) t = t.substring (bang + 1);
            var a = Area.parse (t, s);
            if (a != null) return a;
            if (t.up () == t && t.length > 0 && t[0].isdigit ()) {
                var whole = Area.parse (t + ":" + t, s);
                if (whole != null) return whole;
            }
            string? def = null;
            foreach (var e in s.names.entries) if (e.key.casefold () == t.casefold ()) def = e.value;
            foreach (var e in book.names.entries) if (def == null && e.key.casefold () == t.casefold ()) def = e.value;
            if (def != null) {
                string d = def.has_prefix ("=") ? def.substring (1) : def;
                d = d.split (",")[0];
                int b2 = d.last_index_of ("!");
                if (b2 >= 0) {
                    string sn = d.substring (0, b2);
                    if (sn.has_prefix ("'")) sn = sn.substring (1, sn.length - 2).replace ("''", "'");
                    var other = book.find_sheet (sn);
                    if (other != null) return Area.parse (d.substring (b2 + 1).replace ("$", ""), other);
                }
                return Area.parse (d.replace ("$", ""), s);
            }
            var table = Tables.resolve_name (book, t);
            if (table != null) return table;
            return null;
        }

        public SVal make_range (Sheet s, string addr, int line) throws ScriptError {
            if (addr.contains (",")) {
                var parts = new Gee.ArrayList<SVal> ();
                foreach (string piece in addr.split (",")) parts.add (make_range (s, piece, line));
                if (parts.size == 1) return parts[0];
                var multi = SVal.range (parts[0].sheet, parts[0].area);
                multi.items = parts;
                return multi;
            }
            string t = addr.strip ();
            try {
                t = new Regex ("\\s*:\\s*").replace (t, -1, 0, ":");
                t = new Regex ("!\\s+").replace (t, -1, 0, "!");
            } catch (RegexError e) {
            }
            bool quoted = t.has_prefix ("'");
            if (!quoted && t.contains (" ")) throw rt (line, _("method Range failed: \"%s\" is not a valid range").printf (addr), 1004);
            int bang = t.last_index_of ("!");
            Sheet target = s;
            if (bang > 0) {
                string sn = t.substring (0, bang);
                if (sn.has_prefix ("'")) sn = sn.substring (1, sn.length - 2).replace ("''", "'");
                var other = book.find_sheet (sn);
                if (other == null) throw rt (line, _("no sheet named %s").printf (sn), 9);
                target = other;
            }
            var a = parse_address (target, t);
            if (a == null) throw rt (line, _("method Range failed: \"%s\" is not a valid range").printf (addr), 1004);
            return SVal.range (a.sheet ?? target, a);
        }

        private Sheet sheet_of (SVal v, int line) throws ScriptError {
            if (v.kind == SKind.SHEET) return v.sheet;
            if (v.kind == SKind.NUM) {
                int i = (int) v.num - 1;
                if (i < 0 || i >= book.sheets.size) throw rt (line, _("subscript out of range: there is no sheet %d").printf (i + 1), 9);
                return book.sheets[i];
            }
            var s = book.find_sheet (v.text ());
            if (s == null) throw rt (line, _("subscript out of range: there is no sheet named %s").printf (v.text ()), 9);
            return s;
        }

        private SVal cells_of (Sheet s, SVal[] args, int line) throws ScriptError {
            if (args.length == 0) return SVal.range (s, new Area (s, 0, 0, MAX_ROWS - 1, MAX_COLS - 1));
            var all = SVal.range (s, new Area (s, 0, 0, MAX_ROWS - 1, MAX_COLS - 1));
            return range_item (all, args, line);
        }

        private SVal rows_of (Sheet s, SVal[] args, int line) throws ScriptError {
            if (args.length == 0) {
                var r = SVal.range (s, new Area (s, 0, 0, MAX_ROWS - 1, MAX_COLS - 1));
                r.count_mode = 1;
                return r;
            }
            var d = deref (args[0]);
            if (d.kind == SKind.STR && d.str.contains (":")) {
                var ps = d.str.replace ("$", "").split (":");
                return SVal.range (s, new Area (s, int.parse (ps[0]) - 1, 0, int.parse (ps[1]) - 1, MAX_COLS - 1));
            }
            int r1 = (int) num (d, line) - 1;
            if (r1 < 0 || r1 >= MAX_ROWS) throw rt (line, _("row out of range"), 1004);
            return SVal.range (s, new Area (s, r1, 0, r1, MAX_COLS - 1));
        }

        private SVal cols_of (Sheet s, SVal[] args, int line) throws ScriptError {
            if (args.length == 0) {
                var r = SVal.range (s, new Area (s, 0, 0, MAX_ROWS - 1, MAX_COLS - 1));
                r.count_mode = 2;
                return r;
            }
            var d = deref (args[0]);
            if (d.kind == SKind.STR) {
                if (d.str.strip () == "") throw rt (line, _("column out of range"), 1004);
                var ps = d.str.replace ("$", "").up ().split (":");
                int c1 = Address.column_index (ps[0]);
                int c2 = ps.length > 1 ? Address.column_index (ps[1]) : c1;
                if (c1 < 0 || c2 < 0) throw rt (line, _("column out of range"), 1004);
                return SVal.range (s, new Area (s, 0, c1, MAX_ROWS - 1, c2));
            }
            int ci = (int) num (d, line) - 1;
            if (ci < 0 || ci >= MAX_COLS) throw rt (line, _("column out of range"), 1004);
            return SVal.range (s, new Area (s, 0, ci, MAX_ROWS - 1, ci));
        }

        private Gee.ArrayList<string> sorted_names () {
            var list = new Gee.ArrayList<string> ();
            list.add_all (book.names.keys);
            list.sort ((a, b) => a.casefold ().collate (b.casefold ()));
            return list;
        }

        private SVal name_obj (string key) {
            var o = SVal.obj (SKind.NAME);
            o.str = key;
            return o;
        }

        private SVal name_item (SVal key, int line) throws ScriptError {
            var names = sorted_names ();
            if (key.kind == SKind.NUM) {
                int i = (int) key.num - 1;
                if (i < 0 || i >= names.size) throw rt (line, _("subscript out of range"), 9);
                return name_obj (names[i]);
            }
            foreach (string n in names) if (n.casefold () == key.text ().casefold ()) return name_obj (n);
            throw rt (line, _("subscript out of range: no name %s").printf (key.text ()), 9);
        }

        private SVal name_value (SVal n) {
            if (!book.names.has_key (n.str)) return SVal.empty ();
            return SVal.s (book.names[n.str]);
        }

        private SVal? name_range (string key) {
            if (!book.names.has_key (key)) return null;
            try {
                string d = book.names[key];
                return make_range (host.active, d.has_prefix ("=") ? d.substring (1) : d, 0);
            } catch (ScriptError e) {
                return null;
            }
        }

        private SVal coll_item (SVal c, SVal raw, int line) throws ScriptError {
            var key = deref (raw);
            if (key.kind == SKind.STR) {
                for (int i = 0; i < c.keys.size; i++) if (c.keys[i] != "" && c.keys[i].casefold () == key.str.casefold ()) return c.items[i];
                throw rt (line, _("invalid procedure call or argument: no item %s").printf (key.str), 5);
            }
            int idx = (int) num (key, line) - 1;
            if (idx < 0 || idx >= c.items.size) throw rt (line, _("subscript out of range"), 9);
            return c.items[idx];
        }

        private static string dict_key (SVal k) {
            return (k.kind == SKind.NUM ? "n:" : "s:") + k.text ();
        }

        private SVal dict_get (SVal d, SVal raw, int line) {
            var k = deref (raw);
            string key = dict_key (k);
            int i = d.keys.index_of (key);
            if (i >= 0) return d.items[i];
            d.keys.add (key);
            var e = SVal.empty ();
            d.items.add (e);
            return e;
        }

        private void dict_set (SVal d, SVal raw, SVal v) {
            var k = deref (raw);
            string key = dict_key (k);
            int i = d.keys.index_of (key);
            if (i >= 0) d.items[i] = v;
            else {
                d.keys.add (key);
                d.items.add (v);
            }
        }

        private static SVal dict_key_value (string key) {
            if (key.has_prefix ("n:")) return SVal.n (double.parse (key.substring (2)));
            return SVal.s (key.substring (2));
        }

        private SVal member (SVal obj, string name, SVal[] args, string[] names, int line) throws ScriptError {
            if ((obj.kind == SKind.BOOK || obj.kind == SKind.SHEET || obj.kind == SKind.APP) && args.length == 0 && globals.vars.has_key (name.down ()) && !builtin_member (obj, name.down ())) return globals.vars[name.down ()];
            if (obj.kind == SKind.APP && obj.facet == "module" || ((obj.kind == SKind.BOOK || obj.kind == SKind.SHEET || obj.kind == SKind.APP) && script != null && script.procs.has_key (name.down ()) && !builtin_member (obj, name.down ()))) {
                var proc = script.procs[name.down ()];
                if (proc == null) throw rt (line, _("%s is not defined in module %s").printf (name, obj.str), 438);
                try {
                    return call_proc_named (proc, args, names, line, null);
                } catch (ExitError x) {
                    return SVal.empty ();
                }
            }
            return member_inner (obj, name, args, names, line);
        }

        private static bool builtin_member (SVal obj, string p) {
            string[] common = { "name", "range", "cells", "rows", "columns", "activate", "select", "delete", "calculate", "copy", "paste", "visible", "index", "run", "sheets", "worksheets", "names", "evaluate" };
            return p in common;
        }

        private SVal member_inner (SVal obj, string name, SVal[] args, string[] names, int line) throws ScriptError {
            string p = name.down ();
            switch (obj.kind) {
                case SKind.FUNCS:
                    return worksheet_function (name, args, line, true);
                case SKind.DEBUG:
                    if (p == "print") {
                        string[] parts = {};
                        foreach (var a in args) parts += str (a);
                        host.log (string.joinv (" ", parts));
                        return SVal.empty ();
                    }
                    if (p == "assert") {
                        if (args.length > 0 && !truthy (args[0], line)) throw rt (line, _("Debug.Assert failed"), 5);
                        return SVal.empty ();
                    }
                    break;
                case SKind.ERR:
                    switch (p) {
                        case "number": return SVal.n (err_number);
                        case "description": return SVal.s (err_description);
                        case "source": return SVal.s (err_source);
                        case "clear":
                            err_number = 0;
                            err_description = "";
                            return SVal.empty ();
                        case "raise":
                            int n = args.length > 0 ? (int) num (args[0], line) : 5;
                            var desc = arg_named (args, names, 2, "description");
                            var src = arg_named (args, names, 1, "source");
                            if (src != null) err_source = str (src);
                            throw rt (line, desc != null ? str (desc) : _("application-defined or object-defined error"), n);
                        case "helpcontext":
                        case "lastdllerror": return SVal.n (0);
                        case "helpfile": return SVal.s ("");
                    }
                    break;
                case SKind.APP:
                    return app_member (p, name, args, names, line);
                case SKind.BOOK:
                    switch (p) {
                        case "sheets":
                        case "worksheets":
                            if (args.length == 0) return SVal.obj (SKind.SHEETS);
                            return SVal.of_sheet (sheet_of (deref (args[0]), line));
                        case "activesheet": return SVal.of_sheet (host.active);
                        case "name": return SVal.s (doc.path != null ? Path.get_basename (doc.path) : _("Untitled Spreadsheet"));
                        case "fullname": return SVal.s (doc.path ?? _("Untitled Spreadsheet"));
                        case "path": return SVal.s (doc.path != null ? Path.get_dirname (doc.path) : "");
                        case "names":
                            if (args.length == 0) return SVal.obj (SKind.NAMES);
                            return name_item (deref (args[0]), line);
                        case "calculate": book.recalculate (); return SVal.empty ();
                        case "activate": return SVal.empty ();
                        case "application": case "parent": return SVal.obj (SKind.APP);
                        case "saved": return SVal.b (!doc.modified);
                        case "readonly": return SVal.b (false);
                        case "save": case "saveas": case "savecopyas": case "close": case "printout": case "printpreview": case "sendmail":
                            throw rt (line, _("Workbook.%s is not allowed: macros cannot save, close or send files").printf (name), 70);
                        case "worksheetfunction": return SVal.obj (SKind.FUNCS);
                    }
                    break;
                case SKind.SHEETS:
                    switch (p) {
                        case "count": return SVal.n (book.sheets.size);
                        case "item": return SVal.of_sheet (sheet_of (deref (args[0]), line));
                        case "add":
                            mutate (line);
                            var before = arg_named (args, names, 0, "before");
                            var after = arg_named (args, names, 1, "after");
                            int at = book.sheets.index_of (host.active);
                            if (before != null && before.kind == SKind.SHEET) at = book.sheets.index_of (before.sheet);
                            else if (after != null && after.kind == SKind.SHEET) at = book.sheets.index_of (after.sheet) + 1;
                            var ns = book.add_sheet (null, at);
                            host.activate_sheet (ns);
                            return SVal.of_sheet (ns);
                        case "select":
                        case "visible":
                            return SVal.empty ();
                    }
                    break;
                case SKind.NAMES:
                    switch (p) {
                        case "count": return SVal.n (book.names.size);
                        case "item": return name_item (deref (args[0]), line);
                        case "add":
                            var nm = arg_named (args, names, 0, "name");
                            var refers = arg_named (args, names, 1, "refersto");
                            var refr1 = arg_named (args, names, 7, "referstor1c1");
                            if (nm == null) throw rt (line, _("Names.Add needs a name"), 5);
                            string nkey = str (nm);
                            if (refers != null) book.names[nkey] = normalize_refers (refers, line);
                            else if (refr1 != null) book.names[nkey] = ScriptLib.r1c1_to_a1 (str (refr1), 0, 0);
                            else book.names[nkey] = "=" + qualified_address (SVal.range (host.active, host.selected ?? new Area.cell (host.active, 0, 0)), true);
                            dirty = true;
                            return name_obj (nkey);
                    }
                    break;
                case SKind.NAME:
                    string key = obj.str;
                    switch (p) {
                        case "name": case "namelocal": return SVal.s (key);
                        case "refersto": case "referstolocal": case "value":
                            if (!book.names.has_key (key)) return SVal.s ("");
                            string def = book.names[key];
                            if (!def.has_prefix ("=")) def = "=" + def;
                            return SVal.s (def);
                        case "referstor1c1": case "referstor1c1local":
                            var rr = name_range (key);
                            if (rr == null) return SVal.s ("");
                            string[] parts = {};
                            foreach (var part in areas_of (rr)) parts += Address.quote_sheet (part.sheet.name) + "!" + r1c1_address (part.area);
                            return SVal.s ("=" + string.joinv (",", parts));
                        case "referstorange":
                            var r2 = name_range (key);
                            if (r2 == null) throw rt (line, _("the name does not refer to a range"), 1004);
                            return r2;
                        case "delete":
                            book.names.unset (key);
                            dirty = true;
                            return SVal.empty ();
                        case "visible": return SVal.b (true);
                        case "index": return SVal.n (sorted_names ().index_of (key) + 1);
                    }
                    break;
                case SKind.COLL:
                    switch (p) {
                        case "count": return SVal.n (obj.items.size);
                        case "item": return coll_item (obj, args[0], line);
                        case "add":
                            var item = args.length > 0 ? args[0] : SVal.empty ();
                            var k = arg_named (args, names, 1, "key");
                            string ks = k != null && !k.missing ? str (k) : "";
                            if (ks != "") foreach (string e in obj.keys) if (e.casefold () == ks.casefold ()) throw rt (line, _("this key is already associated with an element of this collection"), 457);
                            var bef = arg_named (args, names, 2, "before");
                            var aft = arg_named (args, names, 3, "after");
                            int pos = obj.items.size;
                            if (bef != null && !bef.missing) pos = (int) num (bef, line) - 1;
                            else if (aft != null && !aft.missing) pos = (int) num (aft, line);
                            pos = pos.clamp (0, obj.items.size);
                            obj.items.insert (pos, item);
                            obj.keys.insert (pos, ks);
                            return SVal.empty ();
                        case "remove":
                            var key2 = deref (args[0]);
                            int idx = -1;
                            if (key2.kind == SKind.STR) {
                                for (int i = 0; i < obj.keys.size; i++) if (obj.keys[i].casefold () == key2.str.casefold ()) idx = i;
                            } else {
                                idx = (int) num (key2, line) - 1;
                            }
                            if (idx < 0 || idx >= obj.items.size) throw rt (line, _("subscript out of range"), 9);
                            obj.items.remove_at (idx);
                            obj.keys.remove_at (idx);
                            return SVal.empty ();
                    }
                    break;
                case SKind.DICT:
                    switch (p) {
                        case "count": return SVal.n (obj.items.size);
                        case "item": return dict_get (obj, args[0], line);
                        case "exists": return SVal.b (obj.keys.index_of (dict_key (deref (args[0]))) >= 0);
                        case "add":
                            string dk = dict_key (deref (args[0]));
                            if (obj.keys.index_of (dk) >= 0) throw rt (line, _("this key is already associated with an element of this collection"), 457);
                            obj.keys.add (dk);
                            obj.items.add (args.length > 1 ? args[1] : SVal.empty ());
                            return SVal.empty ();
                        case "remove":
                            int di = obj.keys.index_of (dict_key (deref (args[0])));
                            if (di < 0) throw rt (line, _("the key was not found"), 32811);
                            obj.keys.remove_at (di);
                            obj.items.remove_at (di);
                            return SVal.empty ();
                        case "removeall":
                            obj.keys.clear ();
                            obj.items.clear ();
                            return SVal.empty ();
                        case "keys":
                            var kl = new Gee.ArrayList<SVal> ();
                            foreach (string k2 in obj.keys) kl.add (dict_key_value (k2));
                            return SVal.arr (kl);
                        case "items":
                            var il = new Gee.ArrayList<SVal> ();
                            il.add_all (obj.items);
                            return SVal.arr (il);
                        case "comparemode": return SVal.n (0);
                    }
                    break;
                case SKind.SHEET:
                    return sheet_member (obj, p, name, args, names, line);
                case SKind.RANGE:
                    return range_member (obj, p, args, names, line);
                case SKind.PAGESETUP:
                    return page_setup_get (obj.sheet, p, line);
                case SKind.BREAKS:
                    var pg = obj.sheet.page;
                    bool horiz = obj.facet.has_prefix ("h");
                    var set = horiz ? pg.row_breaks : pg.col_breaks;
                    var every = all_breaks (obj.sheet, horiz);
                    switch (p) {
                        case "count": return SVal.n (every.size);
                        case "add":
                            var bbef = arg_named (args, names, 0, "before");
                            if (bbef == null || bbef.kind != SKind.RANGE) throw rt (line, _("Add needs Before:=Range"), 5);
                            set.add (horiz ? bbef.area.r1 : bbef.area.c1);
                            return SVal.empty ();
                        case "item":
                            int bi = (int) num (args[0], line) - 1;
                            if (bi < 0 || bi >= every.size) throw rt (line, _("subscript out of range"), 9);
                            var br = SVal.obj (SKind.BREAKS, (horiz ? "h" : "v") + ":" + every[bi].to_string ());
                            br.sheet = obj.sheet;
                            return br;
                        case "delete":
                            string[] fp = obj.facet.split (":");
                            if (fp.length > 1) set.remove (int.parse (fp[1]));
                            return SVal.empty ();
                        case "location":
                            string[] lp = obj.facet.split (":");
                            if (lp.length < 2) break;
                            int at = int.parse (lp[1]);
                            return horiz ? SVal.range (obj.sheet, new Area (obj.sheet, at, 0, at, MAX_COLS - 1)) : SVal.range (obj.sheet, new Area (obj.sheet, 0, at, MAX_ROWS - 1, at));
                        case "type":
                            string[] tp = obj.facet.split (":");
                            return SVal.n (tp.length > 1 && set.contains (int.parse (tp[1])) ? -4135 : -4105);
                    }
                    break;
                case SKind.WINDOW:
                    switch (p) {
                        case "displaygridlines": return SVal.b (host.active.show_grid);
                        case "freezepanes": return SVal.b (host.active.freeze_rows > 0 || host.active.freeze_cols > 0);
                        case "activesheet": return SVal.of_sheet (host.active);
                        case "activecell": return active_cell ();
                        case "selection": return selection ();
                        case "zoom": return app_props.has_key ("window.zoom") ? app_props["window.zoom"] : SVal.n (100);
                        case "scrollrow": return app_props.has_key ("window.scrollrow") ? app_props["window.scrollrow"] : SVal.n (1);
                        case "scrollcolumn": return app_props.has_key ("window.scrollcolumn") ? app_props["window.scrollcolumn"] : SVal.n (1);
                        case "splitrow": return SVal.n (host.active.freeze_rows);
                        case "splitcolumn": return SVal.n (host.active.freeze_cols);
                        case "smallscroll": case "largescroll": case "activate": case "close": return SVal.empty ();
                        default:
                            if (app_props.has_key ("window." + p)) return app_props["window." + p];
                            return SVal.empty ();
                    }
                case SKind.NOTHING:
                case SKind.EMPTY:
                    throw rt (line, _("object variable not set (%s)").printf (name), 91);
                case SKind.ARRAY:
                case SKind.NUM:
                case SKind.STR:
                case SKind.BOOL:
                    throw rt (line, _("object required: %s is not an object").printf (name), 424);
                default:
                    break;
            }
            throw rt (line, _("object does not support %s").printf (name), 438);
        }

        private SVal active_cell () {
            var sel = host.selected ?? new Area.cell (host.active, 0, 0);
            return SVal.range (host.active, new Area.cell (host.active, sel.r1, sel.c1));
        }

        private SVal selection () {
            return SVal.range (host.active, host.selected ?? new Area.cell (host.active, 0, 0));
        }

        private SVal app_member (string p, string name, SVal[] args, string[] names, int line) throws ScriptError {
            switch (p) {
                case "worksheetfunction": return SVal.obj (SKind.FUNCS);
                case "activesheet": return SVal.of_sheet (host.active);
                case "activecell": return active_cell ();
                case "selection": return selection ();
                case "activeworkbook":
                case "thisworkbook": return SVal.obj (SKind.BOOK);
                case "workbooks":
                    if (args.length == 0) {
                        var wb = SVal.obj (SKind.COLL);
                        wb.items = new Gee.ArrayList<SVal> ();
                        wb.items.add (SVal.obj (SKind.BOOK));
                        wb.keys = new Gee.ArrayList<string> ();
                        wb.keys.add ("");
                        return wb;
                    }
                    return SVal.obj (SKind.BOOK);
                case "sheets":
                case "worksheets":
                    if (args.length == 0) return SVal.obj (SKind.SHEETS);
                    return SVal.of_sheet (sheet_of (deref (args[0]), line));
                case "range": return call_named ("range", args, names, line, false);
                case "cells": return cells_of (host.active, args, line);
                case "rows": return rows_of (host.active, args, line);
                case "columns": return cols_of (host.active, args, line);
                case "activewindow": return SVal.obj (SKind.WINDOW);
                case "name": return SVal.s ("Microsoft Excel");
                case "version": return SVal.s ("16.0");
                case "build": return SVal.n (0);
                case "username": return SVal.s (Environment.get_real_name ());
                case "operatingsystem": return SVal.s ("Linux");
                case "decimalseparator": return SVal.s (LocaleInfo.get ().decimal_sep.to_string ());
                case "thousandsseparator": return SVal.s (",");
                case "pathseparator": return SVal.s ("/");
                case "calculation": return SVal.n (book.manual_calc ? -4135 : -4105);
                case "calculate":
                case "calculatefull":
                    book.recalculate ();
                    return SVal.empty ();
                case "volatile":
                case "wait":
                case "doevents":
                case "goto":
                case "screenrefresh":
                case "undo":
                    if (p == "goto" && args.length > 0 && args[0].kind == SKind.RANGE) host.select (args[0].sheet, args[0].area);
                    return SVal.empty ();
                case "run":
                    string macro = args.length > 0 ? str (args[0]) : "";
                    int bang = macro.last_index_of ("!");
                    if (bang >= 0) macro = macro.substring (bang + 1);
                    var proc = script.procs[macro.down ()];
                    if (proc == null) throw rt (line, _("cannot run the macro %s").printf (macro), 1004);
                    SVal[] rest = args.length > 1 ? args[1:args.length] : new SVal[0];
                    try {
                        return call_proc (proc, rest, line, null);
                    } catch (ExitError x) {
                        return SVal.empty ();
                    }
                case "inputbox":
                    var prompt = arg_named (args, names, 0, "prompt");
                    var title = arg_named (args, names, 1, "title");
                    var def = arg_named (args, names, 2, "default");
                    var type = arg_named (args, names, 7, "type");
                    string? got = host.input (prompt != null ? str (prompt) : "", title != null ? str (title) : _("Input"), def != null ? str (def) : "");
                    if (got == null) return SVal.b (false);
                    if (type != null && ((int) num (type, line) & 1) != 0) {
                        double d;
                        string f;
                        if (Input.parse_number (got.strip (), out d, out f)) return SVal.n (d);
                        throw rt (line, _("the number is not valid"), 13);
                    }
                    if (type != null && ((int) num (type, line) & 8) != 0) return make_range (host.active, got, line);
                    return SVal.s (got);
                case "evaluate": return call_named ("evaluate", args, names, line, false);
                case "intersect":
                    Gee.ArrayList<Area>? acc = null;
                    Sheet? isheet = null;
                    foreach (var a in args) {
                        if (a.missing) continue;
                        if (a.kind != SKind.RANGE) throw rt (line, _("Intersect needs ranges"), 13);
                        var cur = new Gee.ArrayList<Area> ();
                        foreach (var part in areas_of (a)) cur.add (part.area);
                        if (acc == null) {
                            acc = cur;
                            isheet = a.sheet;
                            continue;
                        }
                        if (a.sheet != isheet) throw rt (line, _("method Intersect failed: the ranges are on different sheets"), 1004);
                        var next = new Gee.ArrayList<Area> ();
                        foreach (var x in acc) foreach (var y in cur) {
                            if (!x.intersects (y)) continue;
                            next.add (new Area (isheet, int.max (x.r1, y.r1), int.max (x.c1, y.c1), int.min (x.r2, y.r2), int.min (x.c2, y.c2)));
                        }
                        acc = next;
                    }
                    if (acc == null || acc.size == 0) return SVal.nothing ();
                    return multi (isheet, merge_areas (acc));
                case "union":
                    var parts = new Gee.ArrayList<SVal> ();
                    foreach (var a in args) {
                        if (a.missing) continue;
                        if (a.kind != SKind.RANGE) throw rt (line, _("Union needs ranges"), 13);
                        parts.add_all (areas_of (a));
                    }
                    if (parts.size == 0) return SVal.nothing ();
                    var ul = new Gee.ArrayList<Area> ();
                    foreach (var part in parts) ul.add (part.area);
                    return multi (parts[0].sheet, merge_areas (ul));
                case "quit":
                case "getopenfilename":
                case "getsaveasfilename":
                case "filedialog":
                case "ontime":
                case "onkey":
                case "sendkeys":
                case "executeexcel4macro":
                case "shell":
                    if (p == "onkey") return SVal.empty ();
                    throw rt (line, _("Application.%s is not allowed in the macro sandbox").printf (name), 70);
                case "application":
                case "parent": return SVal.obj (SKind.APP);
                case "screenupdating":
                case "displayalerts":
                case "enableevents":
                case "cutcopymode":
                case "statusbar":
                case "interactive":
                    return app_props.has_key (p) ? app_props[p] : SVal.b (true);
                case "caller": return SVal.empty ();
                case "international": return SVal.n (0);
                case "visible": return app_props.has_key (p) ? app_props[p] : SVal.b (true);
                case "commandbars":
                case "vbe":
                case "assistant":
                case "help":
                    throw rt (line, _("Application.%s (toolbars, the VBA editor and help) is not available here").printf (name), 438);
            }
            if (app_props.has_key (p)) return app_props[p];
            if (Functions.all ().has_key (name.up ())) return worksheet_function (name, args, line, false);
            throw rt (line, _("Application does not support %s").printf (name), 438);
        }

        private SVal sheet_member (SVal obj, string p, string name, SVal[] args, string[] names, int line) throws ScriptError {
            var s = obj.sheet;
            switch (p) {
                case "name": case "codename": return SVal.s (s.name);
                case "index": return SVal.n (book.sheets.index_of (s) + 1);
                case "range":
                    if (args.length == 0) throw rt (line, _("Range needs an address"), 450);
                    if (args.length >= 2 && args[0].kind == SKind.RANGE && args[1].kind == SKind.RANGE) return span (args[0], args[1]);
                    if (args[0].kind == SKind.RANGE) return args[0];
                    return make_range (s, str (args[0]), line);
                case "cells": return cells_of (s, args, line);
                case "rows": return rows_of (s, args, line);
                case "columns": return cols_of (s, args, line);
                case "usedrange": return SVal.range (s, s.used_area ());
                case "activate":
                case "select":
                    host.activate_sheet (s);
                    return SVal.empty ();
                case "delete":
                    mutate (line);
                    if (book.sheets.size > 1) {
                        book.remove_sheet (s);
                        if (host.active == s) host.active = book.sheets[0];
                    }
                    return SVal.empty ();
                case "calculate":
                    book.recalculate ();
                    return SVal.empty ();
                case "copy":
                    mutate (line);
                    var before = arg_named (args, names, 0, "before");
                    var after = arg_named (args, names, 1, "after");
                    var copy = doc_duplicate (s);
                    if (before != null && before.kind == SKind.SHEET) {
                        book.sheets.remove (copy);
                        book.sheets.insert (book.sheets.index_of (before.sheet), copy);
                    } else if (after != null && after.kind == SKind.SHEET) {
                        book.sheets.remove (copy);
                        book.sheets.insert (book.sheets.index_of (after.sheet) + 1, copy);
                    }
                    host.activate_sheet (copy);
                    return SVal.of_sheet (copy);
                case "move":
                    var mb = arg_named (args, names, 0, "before");
                    var ma = arg_named (args, names, 1, "after");
                    book.sheets.remove (s);
                    if (mb != null && mb.kind == SKind.SHEET) book.sheets.insert (book.sheets.index_of (mb.sheet), s);
                    else if (ma != null && ma.kind == SKind.SHEET) book.sheets.insert (book.sheets.index_of (ma.sheet) + 1, s);
                    else book.sheets.add (s);
                    return SVal.empty ();
                case "visible": return SVal.n (s.visibility == 0 ? -1 : (s.visibility == 2 ? 2 : 0));
                case "tabcolor": return SVal.n (hex_rgb (s.tab_color));
                case "tab": return obj;
                case "protect":
                    var pw = arg_named (args, names, 0, "password");
                    s.protection = new SheetProtection ();
                    if (pw != null && !pw.missing && str (pw) != "") s.protection.password = PasswordHash.create (str (pw));
                    return SVal.empty ();
                case "unprotect":
                    var upw = arg_named (args, names, 0, "password");
                    if (s.protection != null && s.protection.password.is_set () && (upw == null || !s.protection.password.verify (str (upw)))) throw rt (line, _("the password you supplied is not correct"), 1004);
                    s.protection = null;
                    return SVal.empty ();
                case "protectcontents": return SVal.b (s.protection != null);
                case "pagesetup":
                    var ps = SVal.obj (SKind.PAGESETUP);
                    ps.sheet = s;
                    return ps;
                case "hpagebreaks":
                case "vpagebreaks":
                    var br = SVal.obj (SKind.BREAKS, p == "hpagebreaks" ? "h" : "v");
                    br.sheet = s;
                    if (args.length > 0) return member (br, "item", args, names, line);
                    return br;
                case "resetallpagebreaks":
                    s.page.row_breaks.clear ();
                    s.page.col_breaks.clear ();
                    return SVal.empty ();
                case "names": return SVal.obj (SKind.NAMES);
                case "parent": return SVal.obj (SKind.BOOK);
                case "application": return SVal.obj (SKind.APP);
                case "next":
                    int ni = book.sheets.index_of (s) + 1;
                    return ni < book.sheets.size ? SVal.of_sheet (book.sheets[ni]) : SVal.nothing ();
                case "previous":
                    int pi = book.sheets.index_of (s) - 1;
                    return pi >= 0 ? SVal.of_sheet (book.sheets[pi]) : SVal.nothing ();
                case "paste":
                    var dest = arg_named (args, names, 0, "destination");
                    var target = dest != null && dest.kind == SKind.RANGE ? dest : selection ();
                    paste_to (target, -4104, line);
                    return SVal.empty ();
                case "evaluate":
                    string etext = args.length > 0 ? str (args[0]) : "";
                    if (parse_address (s, etext) != null) return make_range (s, etext, line);
                    var saved_active = host.active;
                    host.active = s;
                    try {
                        return call_named ("evaluate", args, names, line, false);
                    } finally {
                        host.active = saved_active;
                    }
                case "showalldata":
                    s.hidden_rows.clear ();
                    return SVal.empty ();
                case "autofiltermode": return SVal.b (s.filter != null);
                case "displaypagebreaks": return SVal.b (false);
                case "exportasfixedformat":
                case "exportpdf":
                    var fname = arg_named (args, names, 1, "filename");
                    string target_path = fname != null ? str (fname) : "";
                    if (target_path == "") throw rt (line, _("ExportAsFixedFormat needs a file name"), 5);
                    refresh ();
                    if (!host.export_pdf (s, target_path)) throw rt (line, _("PDF export is not available here"), 70);
                    return SVal.empty ();
                case "printout":
                case "printpreview":
                case "saveas":
                    throw rt (line, _("Worksheet.%s is not allowed in the macro sandbox").printf (name), 70);
                case "shapes":
                case "chartobjects":
                case "listobjects":
                case "pivottables":
                case "oleobjects":
                    throw rt (line, _("Worksheet.%s is not supported by the macro runtime").printf (name), 438);
            }
            throw rt (line, _("Worksheet does not support %s").printf (name), 438);
        }

        private Sheet doc_duplicate (Sheet src) {
            var copy = book.add_sheet (book.unique_sheet_name (src.name + " "), book.sheets.index_of (src) + 1);
            foreach (var c in src.cells.values) {
                var n = copy.ensure (c.row, c.col);
                n.style = c.style;
                n.note = c.note;
                if (c.formula != null || c.input != "") copy.set_input (c.row, c.col, c.input);
            }
            foreach (var e in src.col_widths.entries) copy.col_widths[e.key] = e.value;
            foreach (var e in src.row_heights.entries) copy.row_heights[e.key] = e.value;
            foreach (var m in src.merges) copy.merges.add (new Area (copy, m.r1, m.c1, m.r2, m.c2));
            copy.page = src.page.copy ();
            copy.tab_color = src.tab_color;
            return copy;
        }

        private SVal span (SVal a, SVal b) {
            return SVal.range (a.sheet, new Area (a.sheet, int.min (a.area.r1, b.area.r1), int.min (a.area.c1, b.area.c1), int.max (a.area.r2, b.area.r2), int.max (a.area.c2, b.area.c2)));
        }

        private SVal page_setup_get (Sheet s, string p, int line) throws ScriptError {
            var pg = s.page;
            switch (p) {
                case "printarea": return SVal.s (pg.print_area == "" ? "" : "$" + pg.print_area.replace (":", ":$").replace (",", ",$"));
                case "printtitlerows": return SVal.s (pg.title_rows);
                case "printtitlecolumns": return SVal.s (pg.title_cols);
                case "orientation": return SVal.n (pg.landscape ? 2 : 1);
                case "zoom": return pg.fit_to_page ? SVal.b (false) : SVal.n (pg.scale);
                case "fittopageswide": return SVal.n (pg.fit_width);
                case "fittopagestall": return SVal.n (pg.fit_height);
                case "papersize": return SVal.n (pg.paper);
                case "leftmargin": return SVal.n (pg.margin_left * 72);
                case "rightmargin": return SVal.n (pg.margin_right * 72);
                case "topmargin": return SVal.n (pg.margin_top * 72);
                case "bottommargin": return SVal.n (pg.margin_bottom * 72);
                case "headermargin": return SVal.n (pg.margin_header * 72);
                case "footermargin": return SVal.n (pg.margin_footer * 72);
                case "centerhorizontally": return SVal.b (pg.center_h);
                case "centervertically": return SVal.b (pg.center_v);
                case "printgridlines": return SVal.b (pg.gridlines);
                case "printheadings": return SVal.b (pg.headings);
                case "firstpagenumber": return SVal.n (pg.first_page_number > 0 ? pg.first_page_number : -4105);
                case "order": return SVal.n (pg.over_then_down ? 2 : 1);
                case "blackandwhite": return SVal.b (pg.black_and_white);
                case "leftheader": case "centerheader": case "rightheader":
                case "leftfooter": case "centerfooter": case "rightfooter":
                    string l, c, r;
                    HeaderFooter.split (p.has_suffix ("header") ? pg.header : pg.footer, out l, out c, out r);
                    return SVal.s (p.has_prefix ("left") ? l : (p.has_prefix ("center") ? c : r));
            }
            throw rt (line, _("PageSetup does not support %s").printf (p), 438);
        }

        private void set_page_setup (Sheet s, string p, SVal v, int line) throws ScriptError {
            var pg = s.page;
            switch (p) {
                case "printarea":
                    var d = deref (v);
                    pg.print_area = d.kind == SKind.BOOL && d.num == 0 ? "" : str (d).replace ("$", "");
                    return;
                case "printtitlerows": pg.title_rows = str (v); return;
                case "printtitlecolumns": pg.title_cols = str (v); return;
                case "orientation": pg.landscape = (int) num (v, line) == 2; return;
                case "zoom":
                    var z = deref (v);
                    if (z.kind == SKind.BOOL) pg.fit_to_page = z.num == 0;
                    else {
                        pg.fit_to_page = false;
                        pg.scale = ((int) num (z, line)).clamp (10, 400);
                    }
                    return;
                case "fittopageswide":
                    var fw = deref (v);
                    pg.fit_width = fw.kind == SKind.BOOL ? 0 : (int) num (fw, line);
                    pg.fit_to_page = true;
                    return;
                case "fittopagestall":
                    var ft = deref (v);
                    pg.fit_height = ft.kind == SKind.BOOL ? 0 : (int) num (ft, line);
                    pg.fit_to_page = true;
                    return;
                case "papersize": pg.paper = (int) num (v, line); return;
                case "leftmargin": pg.margin_left = num (v, line) / 72; return;
                case "rightmargin": pg.margin_right = num (v, line) / 72; return;
                case "topmargin": pg.margin_top = num (v, line) / 72; return;
                case "bottommargin": pg.margin_bottom = num (v, line) / 72; return;
                case "headermargin": pg.margin_header = num (v, line) / 72; return;
                case "footermargin": pg.margin_footer = num (v, line) / 72; return;
                case "centerhorizontally": pg.center_h = truthy (v, line); return;
                case "centervertically": pg.center_v = truthy (v, line); return;
                case "printgridlines": pg.gridlines = truthy (v, line); return;
                case "printheadings": pg.headings = truthy (v, line); return;
                case "blackandwhite": pg.black_and_white = truthy (v, line); return;
                case "order": pg.over_then_down = (int) num (v, line) == 2; return;
                case "firstpagenumber":
                    int fp = (int) num (v, line);
                    pg.first_page_number = fp == -4105 ? 0 : fp;
                    return;
                case "leftheader": case "centerheader": case "rightheader":
                case "leftfooter": case "centerfooter": case "rightfooter":
                    bool header = p.has_suffix ("header");
                    string l, c, r;
                    HeaderFooter.split (header ? pg.header : pg.footer, out l, out c, out r);
                    string val = str (v);
                    if (p.has_prefix ("left")) l = val;
                    else if (p.has_prefix ("center")) c = val;
                    else r = val;
                    if (header) pg.header = HeaderFooter.join (l, c, r);
                    else pg.footer = HeaderFooter.join (l, c, r);
                    return;
                case "printquality":
                case "draft":
                case "printcomments":
                case "printerrors":
                case "differentfirstpageheaderfooter":
                case "oddandevenpagesheaderfooter":
                    if (p == "differentfirstpageheaderfooter") pg.first_different = truthy (v, line);
                    if (p == "oddandevenpagesheaderfooter") pg.odd_even = truthy (v, line);
                    return;
            }
            throw rt (line, _("PageSetup.%s cannot be set").printf (p), 438);
        }

        private static bool filled (Sheet s, int x, int y) {
            return x >= 0 && y >= 0 && x < MAX_ROWS && y < MAX_COLS && !s.value_at (x, y).is_empty ();
        }

        private static bool at_limit (int dr, int dc, int rr, int cc, int limit_r, int limit_c) {
            return (dr != 0 && rr == limit_r) || (dc != 0 && cc == limit_c);
        }

        private Area edge (Sheet s, int r, int c, int dir) {
            int dr = dir == -4162 ? -1 : (dir == -4121 ? 1 : 0);
            int dc = dir == -4159 ? -1 : (dir == -4161 ? 1 : 0);
            if (dr == 0 && dc == 0) dr = 1;
            int limit_r = dr > 0 ? MAX_ROWS - 1 : 0;
            int limit_c = dc > 0 ? MAX_COLS - 1 : 0;
            int rr = r, cc = c;
            if (at_limit (dr, dc, rr, cc, limit_r, limit_c)) return new Area.cell (s, rr, cc);
            if (filled (s, rr, cc) && filled (s, rr + dr, cc + dc)) {
                while (!at_limit (dr, dc, rr, cc, limit_r, limit_c) && filled (s, rr + dr, cc + dc)) {
                    rr += dr;
                    cc += dc;
                }
                return new Area.cell (s, rr, cc);
            }
            rr += dr;
            cc += dc;
            int max_r = int.max (s.max_row, 0), max_c = int.max (s.max_col, 0);
            while (!filled (s, rr, cc)) {
                if (at_limit (dr, dc, rr, cc, limit_r, limit_c)) break;
                if (dr > 0 && rr > max_r) {
                    rr = limit_r;
                    break;
                }
                if (dc > 0 && cc > max_c) {
                    cc = limit_c;
                    break;
                }
                if (dr < 0 && rr > max_r) {
                    rr = max_r;
                    continue;
                }
                if (dc < 0 && cc > max_c) {
                    cc = max_c;
                    continue;
                }
                rr += dr;
                cc += dc;
            }
            return new Area.cell (s, rr, cc);
        }

        private void paste_to (SVal dest, int mode, int line) throws ScriptError {
            if (clipboard == null) throw rt (line, _("nothing to paste: copy a range first"), 1004);
            copy_range (clipboard, dest, mode, line);
            if (clipboard_cut) {
                foreach (var part in areas_of (clipboard)) {
                    var a = clamp (part);
                    for (int i = a.r1; i <= a.r2; i++) for (int j = a.c1; j <= a.c2; j++) {
                        if (dest.sheet == part.sheet && dest.area.contains (i, j)) continue;
                        part.sheet.set_input (i, j, "");
                        part.sheet.set_style (i, j, 0);
                    }
                }
                clipboard = null;
            }
        }

        private void copy_range (SVal src, SVal dst, int mode, int line) throws ScriptError {
            mutate (line);
            var ca = clamp (src);
            var s = src.sheet;
            int rows = ca.rows, cols = ca.cols;
            int reps_r = 1, reps_c = 1;
            if (!dst.area.is_single ()) {
                reps_r = int.max (1, dst.area.rows / rows);
                reps_c = int.max (1, dst.area.cols / cols);
            }
            refresh ();
            var snapshot = new Gee.ArrayList<CellCopy?> ();
            for (int i = 0; i < rows; i++) {
                for (int j = 0; j < cols; j++) {
                    var cell = s.get_cell (ca.r1 + i, ca.c1 + j);
                    snapshot.add (cell != null ? new CellCopy.of (cell) : null);
                }
            }
            var vals = new Gee.ArrayList<SVal> ();
            for (int i = 0; i < rows; i++) for (int j = 0; j < cols; j++) vals.add (from_cell (s, ca.r1 + i, ca.c1 + j));
            for (int ri = 0; ri < reps_r; ri++) {
                for (int cj = 0; cj < reps_c; cj++) {
                    for (int i = 0; i < rows; i++) {
                        for (int j = 0; j < cols; j++) {
                            var src_cell = snapshot[i * cols + j];
                            int tr = dst.area.r1 + ri * rows + i, tc = dst.area.c1 + cj * cols + j;
                            if (tr >= MAX_ROWS || tc >= MAX_COLS) continue;
                            bool values = mode == -4163 || mode == 12;
                            bool formats = mode == -4122;
                            if (!formats) {
                                if (src_cell == null) dst.sheet.set_input (tr, tc, "");
                                else if (values) put_cell (dst.sheet, tr, tc, vals[i * cols + j]);
                                else if (src_cell.formula != null) dst.sheet.set_input (tr, tc, Formula.to_text (Formula.shifted (src_cell.formula, tr - src_cell.row, tc - src_cell.col), dst.sheet));
                                else dst.sheet.set_input (tr, tc, src_cell.input);
                            }
                            if (mode == -4104 || formats || mode == 12) {
                                if (formats || mode == -4104) dst.sheet.set_style (tr, tc, src_cell != null ? src_cell.style : 0);
                                else if (src_cell != null) {
                                    var st = dst.sheet.style_at (tr, tc).copy ();
                                    st.number_format = book.styles[src_cell.style].number_format;
                                    dst.sheet.set_style (tr, tc, book.intern (st));
                                }
                            }
                        }
                    }
                }
            }
        }

        private SVal range_member (SVal obj, string p, SVal[] args, string[] names, int line) throws ScriptError {
            var a = obj.area;
            var s = obj.sheet;
            if (obj.facet.has_prefix ("borders")) {
                if (p == "item" || p == "borders") {
                    var b = SVal.range (s, a);
                    b.facet = "borders:" + ((int) num (args[0], line)).to_string ();
                    b.items = obj.items;
                    return b;
                }
                return SVal.n (0);
            }
            if (obj.facet == "font" || obj.facet == "interior") {
                var st = s.style_at (a.r1, a.c1);
                switch (p) {
                    case "bold": return SVal.b (st.bold);
                    case "italic": return SVal.b (st.italic);
                    case "underline": return st.underline ? SVal.n (2) : SVal.n (-4142);
                    case "strikethrough": return SVal.b (st.strike);
                    case "size": return SVal.n (st.font_size);
                    case "name": return SVal.s (st.font_family != "" ? st.font_family : "Calibri");
                    case "color": return SVal.n (hex_rgb (obj.facet == "interior" ? (st.fill != "" ? st.fill : "#ffffff") : (st.color != "" ? st.color : "#000000")));
                    case "colorindex":
                        string col = obj.facet == "interior" ? st.fill : st.color;
                        if (col == "") return SVal.n (-4142);
                        for (int i = 0; i < PALETTE.length; i++) if (PALETTE[i] == col.down ()) return SVal.n (i + 1);
                        return SVal.n (-4142);
                    case "pattern": return SVal.n (st.fill != "" ? 1 : -4142);
                    case "fontstyle": return SVal.s (st.bold && st.italic ? "Bold Italic" : (st.bold ? "Bold" : (st.italic ? "Italic" : "Regular")));
                }
            }
            switch (p) {
                case "value":
                    return range_value (obj);
                case "value2":
                    var rv2 = range_value (obj);
                    undate (rv2);
                    return rv2;
                case "formula":
                case "formulalocal":
                case "formula2":
                    if (a.is_single ()) {
                        string inp = s.input_at (a.r1, a.c1);
                        var cv = s.get_cell (a.r1, a.c1);
                        if (cv != null && cv.formula == null && cv.value.kind == ValueKind.NUMBER) return SVal.s (Value.format_number_general_full (cv.value.number));
                        return SVal.s (inp);
                    }
                    var rows = new Gee.ArrayList<SVal> ();
                    var ca = clamp (obj);
                    for (int i = ca.r1; i <= ca.r2; i++) {
                        var row = new Gee.ArrayList<SVal> ();
                        for (int j = ca.c1; j <= ca.c2; j++) row.add (SVal.s (s.input_at (i, j)));
                        rows.add (SVal.arr (row, 1));
                    }
                    return SVal.arr (rows, 1);
                case "formular1c1":
                case "formular1c1local":
                    var cell = s.get_cell (a.r1, a.c1);
                    if (cell == null) return SVal.s ("");
                    if (cell.formula == null) return SVal.s (cell.input);
                    return SVal.s (ScriptLib.a1_to_r1c1 (cell.formula, s, a.r1, a.c1));
                case "hasformula":
                    bool any = false, all = true;
                    var ch = clamp (obj);
                    for (int i = ch.r1; i <= ch.r2; i++) for (int j = ch.c1; j <= ch.c2; j++) {
                        var cl = s.get_cell (i, j);
                        if (cl != null && cl.formula != null) any = true;
                        else all = false;
                    }
                    return any && all ? SVal.b (true) : (any ? SVal.empty () : SVal.b (false));
                case "text":
                    refresh ();
                    string color;
                    return SVal.s (NumberFormat.format_value (s.value_at (a.r1, a.c1), s.style_at (a.r1, a.c1).number_format, out color, book.date1904));
                case "numberformat":
                case "numberformatlocal": return SVal.s (s.style_at (a.r1, a.c1).number_format);
                case "font":
                case "interior":
                    var fc = SVal.range (s, a);
                    fc.facet = p;
                    fc.items = obj.items;
                    return fc;
                case "borders":
                    var bd = SVal.range (s, a);
                    bd.facet = "borders";
                    bd.items = obj.items;
                    if (args.length > 0) bd.facet = "borders:" + ((int) num (args[0], line)).to_string ();
                    return bd;
                case "bold": return SVal.b (s.style_at (a.r1, a.c1).bold);
                case "italic": return SVal.b (s.style_at (a.r1, a.c1).italic);
                case "wraptext": return SVal.b (s.style_at (a.r1, a.c1).wrap);
                case "horizontalalignment":
                    var hal = s.style_at (a.r1, a.c1).halign;
                    return SVal.n (hal == HAlign.LEFT ? -4131 : (hal == HAlign.CENTER ? -4108 : (hal == HAlign.RIGHT ? -4152 : 1)));
                case "verticalalignment":
                    var val = s.style_at (a.r1, a.c1).valign;
                    return SVal.n (val == VAlign.TOP ? -4160 : (val == VAlign.CENTER ? -4108 : -4107));
                case "note":
                case "comment":
                    var nc = s.get_cell (a.r1, a.c1);
                    if (p == "comment" && (nc == null || nc.note == "")) return SVal.nothing ();
                    return SVal.s (nc != null ? nc.note : "");
                case "addcomment":
                    mutate (line);
                    s.ensure (a.r1, a.c1).note = args.length > 0 ? str (args[0]) : "";
                    return SVal.s (s.get_cell (a.r1, a.c1).note);
                case "clearcomments":
                    mutate (line);
                    for (int i = a.r1; i <= int.min (a.r2, s.max_row); i++) for (int j = a.c1; j <= int.min (a.c2, s.max_col); j++) {
                        var cc2 = s.get_cell (i, j);
                        if (cc2 != null) cc2.note = "";
                    }
                    return SVal.empty ();
                case "row": return SVal.n (a.r1 + 1);
                case "column": return SVal.n (a.c1 + 1);
                case "address":
                case "addresslocal":
                    var ra = arg_named (args, names, 0, "rowabsolute");
                    var ca2 = arg_named (args, names, 1, "columnabsolute");
                    var style = arg_named (args, names, 2, "referencestyle");
                    var ext = arg_named (args, names, 3, "external");
                    bool abs_r = ra == null || ra.missing || truthy (ra, line);
                    bool abs_c = ca2 == null || ca2.missing || truthy (ca2, line);
                    string[] parts = {};
                    foreach (var part in areas_of (obj)) {
                        string t = style != null && !style.missing && (int) num (style, line) == -4150 ? r1c1_address (part.area) : address_of (part.area, abs_r, abs_c);
                        if (ext != null && !ext.missing && truthy (ext, line) && parts.length == 0) t = "[" + (doc.path != null ? Path.get_basename (doc.path) : "Book1") + "]" + Address.quote_sheet (part.sheet.name) + "!" + t;
                        parts += t;
                    }
                    return SVal.s (string.joinv (",", parts));
                case "count":
                case "countlarge":
                    if (obj.count_mode == 1) return SVal.n (a.rows);
                    if (obj.count_mode == 2) return SVal.n (a.cols);
                    double total = 0;
                    foreach (var part in areas_of (obj)) total += (double) part.area.size;
                    return SVal.n (total);
                case "rows":
                    if (args.length > 0) {
                        var ra0 = deref (args[0]);
                        int from_r, to_r;
                        if (ra0.kind == SKind.STR) {
                            var rp = ra0.str.replace ("$", "").split (":");
                            from_r = int.parse (rp[0]);
                            to_r = rp.length > 1 ? int.parse (rp[1]) : from_r;
                        } else {
                            from_r = to_r = (int) num (ra0, line);
                        }
                        int nr1 = a.r1 + from_r - 1, nr2 = a.r1 + to_r - 1;
                        if (nr1 < 0 || nr2 >= MAX_ROWS) throw rt (line, _("application-defined or object-defined error"), 1004);
                        var rsub = SVal.range (s, new Area (s, nr1, a.c1, nr2, a.c2));
                        rsub.count_mode = 1;
                        return rsub;
                    }
                    var rr = SVal.range (s, a);
                    rr.count_mode = 1;
                    rr.items = obj.items;
                    return rr;
                case "columns":
                    if (args.length > 0) {
                        var ca0 = deref (args[0]);
                        int from_c, to_c;
                        if (ca0.kind == SKind.STR) {
                            var cp = ca0.str.replace ("$", "").up ().split (":");
                            from_c = Address.column_index (cp[0]) + 1;
                            to_c = cp.length > 1 ? Address.column_index (cp[1]) + 1 : from_c;
                            if (from_c < 1 || to_c < 1) throw rt (line, _("type mismatch"), 13);
                        } else {
                            from_c = to_c = (int) num (ca0, line);
                        }
                        int nc1 = a.c1 + from_c - 1, nc2 = a.c1 + to_c - 1;
                        if (nc1 < 0 || nc2 >= MAX_COLS) throw rt (line, _("application-defined or object-defined error"), 1004);
                        var csub = SVal.range (s, new Area (s, a.r1, nc1, a.r2, nc2));
                        csub.count_mode = 2;
                        return csub;
                    }
                    var cc = SVal.range (s, a);
                    cc.count_mode = 2;
                    cc.items = obj.items;
                    return cc;
                case "cells": return args.length == 0 ? obj : range_item (obj, args, line);
                case "item": return range_item (obj, args, line);
                case "areas":
                    if (args.length > 0) {
                        int ai = (int) num (args[0], line) - 1;
                        var ars = areas_of (obj);
                        if (ai < 0 || ai >= ars.size) throw rt (line, _("subscript out of range"), 9);
                        return ars[ai];
                    }
                    var coll = SVal.obj (SKind.COLL);
                    coll.items = areas_of (obj);
                    coll.keys = new Gee.ArrayList<string> ();
                    foreach (var x in coll.items) coll.keys.add ("");
                    return coll;
                case "worksheet":
                case "parent": return SVal.of_sheet (s);
                case "application": return SVal.obj (SKind.APP);
                case "offset":
                    var dro = arg_named (args, names, 0, "rowoffset");
                    var dco = arg_named (args, names, 1, "columnoffset");
                    int dr = dro != null && !dro.missing ? (int) num (dro, line) : 0;
                    int dc = dco != null && !dco.missing ? (int) num (dco, line) : 0;
                    if (a.r1 + dr < 0 || a.c1 + dc < 0 || a.r2 + dr >= MAX_ROWS || a.c2 + dc >= MAX_COLS) throw rt (line, _("application-defined or object-defined error"), 1004);
                    return SVal.range (s, new Area (s, a.r1 + dr, a.c1 + dc, a.r2 + dr, a.c2 + dc));
                case "resize":
                    var rs = arg_named (args, names, 0, "rowsize");
                    var cs = arg_named (args, names, 1, "columnsize");
                    int nr = rs != null && !rs.missing ? (int) num (rs, line) : a.rows;
                    int nc = cs != null && !cs.missing ? (int) num (cs, line) : a.cols;
                    if (nr < 1 || nc < 1) throw rt (line, _("application-defined or object-defined error"), 1004);
                    return SVal.range (s, new Area (s, a.r1, a.c1, int.min (a.r1 + nr - 1, MAX_ROWS - 1), int.min (a.c1 + nc - 1, MAX_COLS - 1)));
                case "entirerow":
                    var er = new Gee.ArrayList<SVal> ();
                    foreach (var part in areas_of (obj)) er.add (SVal.range (s, new Area (s, part.area.r1, 0, part.area.r2, MAX_COLS - 1)));
                    if (er.size == 1) return er[0];
                    var erm = SVal.range (s, er[0].area);
                    erm.items = er;
                    return erm;
                case "entirecolumn":
                    var ec = new Gee.ArrayList<SVal> ();
                    foreach (var part in areas_of (obj)) ec.add (SVal.range (s, new Area (s, 0, part.area.c1, MAX_ROWS - 1, part.area.c2)));
                    if (ec.size == 1) return ec[0];
                    var ecm = SVal.range (s, ec[0].area);
                    ecm.items = ec;
                    return ecm;
                case "currentregion": return SVal.range (s, doc.current_region (s, a.r1, a.c1));
                case "end":
                    int dir = args.length > 0 ? (int) num (args[0], line) : -4121;
                    return SVal.range (s, edge (s, a.r1, a.c1, dir));
                case "select":
                case "activate":
                case "show":
                    host.select (s, a);
                    return SVal.empty ();
                case "clear":
                case "clearcontents":
                case "clearformats":
                case "delete":
                    if (p == "delete") {
                        mutate (line);
                        bool rows_whole = a.c1 == 0 && a.c2 == MAX_COLS - 1;
                        bool cols_whole = a.r1 == 0 && a.r2 == MAX_ROWS - 1;
                        var shift = arg_named (args, names, 0, "shift");
                        if (rows_whole || (!cols_whole && (shift == null || shift.missing || (int) num (shift, line) == -4162) && a.cols >= int.max (s.max_col + 1, 1))) {
                            book.delete_rows (s, a.r1, a.rows);
                            return SVal.empty ();
                        }
                        if (cols_whole || (shift != null && !shift.missing && (int) num (shift, line) == -4159)) {
                            book.delete_cols (s, a.c1, a.cols);
                            return SVal.empty ();
                        }
                    }
                    mutate (line);
                    foreach (var part in areas_of (obj)) {
                        var cr = clamp (part);
                        for (int i = cr.r1; i <= cr.r2; i++) {
                            for (int j = cr.c1; j <= cr.c2; j++) {
                                if (p != "clearformats") part.sheet.set_input (i, j, "");
                                if (p != "clearcontents") part.sheet.set_style (i, j, 0);
                                if (p == "clear" || p == "delete") {
                                    var c = part.sheet.get_cell (i, j);
                                    if (c != null) c.note = "";
                                    part.sheet.drop_if_blank (i, j);
                                }
                            }
                        }
                    }
                    return SVal.empty ();
                case "insert":
                    mutate (line);
                    if (a.c1 == 0 && a.c2 == MAX_COLS - 1) book.insert_rows (s, a.r1, a.rows);
                    else if (a.r1 == 0 && a.r2 == MAX_ROWS - 1) book.insert_cols (s, a.c1, a.cols);
                    else {
                        var shift = arg_named (args, names, 0, "shift");
                        if (shift != null && !shift.missing && (int) num (shift, line) == -4161) book.insert_cols (s, a.c1, a.cols);
                        else book.insert_rows (s, a.r1, a.rows);
                    }
                    return SVal.empty ();
                case "copy":
                case "cut":
                    var dest = arg_named (args, names, 0, "destination");
                    if (dest != null && dest.kind == SKind.RANGE) {
                        copy_range (obj, dest, -4104, line);
                        if (p == "cut") {
                            var cc3 = clamp (obj);
                            for (int i = cc3.r1; i <= cc3.r2; i++) for (int j = cc3.c1; j <= cc3.c2; j++) {
                                if (dest.sheet == s && dest.area.contains (i, j)) continue;
                                s.set_input (i, j, "");
                                s.set_style (i, j, 0);
                            }
                        }
                        return SVal.empty ();
                    }
                    clipboard = obj;
                    clipboard_cut = p == "cut";
                    return SVal.b (true);
                case "pastespecial":
                    var paste = arg_named (args, names, 0, "paste");
                    paste_to (obj, paste != null && !paste.missing ? (int) num (paste, line) : -4104, line);
                    return SVal.empty ();
                case "merge":
                    mutate (line);
                    var keep = new Gee.ArrayList<Area> ();
                    foreach (var m in s.merges) if (!m.intersects (a)) keep.add (m);
                    keep.add (new Area (s, a.r1, a.c1, a.r2, a.c2));
                    s.merges = keep;
                    return SVal.empty ();
                case "unmerge":
                    mutate (line);
                    var keep2 = new Gee.ArrayList<Area> ();
                    foreach (var m in s.merges) if (!m.intersects (a)) keep2.add (m);
                    s.merges = keep2;
                    return SVal.empty ();
                case "mergecells":
                    return SVal.b (s.merge_at (a.r1, a.c1) != null);
                case "mergearea":
                    var ma = s.merge_at (a.r1, a.c1);
                    return SVal.range (s, ma ?? a);
                case "hidden":
                    bool rowsw = obj.count_mode == 1 || (a.c1 == 0 && a.c2 == MAX_COLS - 1);
                    bool colsw = obj.count_mode == 2 || (a.r1 == 0 && a.r2 == MAX_ROWS - 1);
                    if (!rowsw && !colsw) throw rt (line, _("unable to get the Hidden property: use EntireRow, EntireColumn, Rows or Columns"), 1004);
                    bool all_hidden = true;
                    if (rowsw) {
                        for (int i = a.r1; i <= int.min (a.r2, a.r1 + 100000); i++) if (!s.hidden_rows.contains (i)) all_hidden = false;
                    } else {
                        for (int j = a.c1; j <= a.c2; j++) if (!s.hidden_cols.contains (j)) all_hidden = false;
                    }
                    return SVal.b (all_hidden);
                case "orientation":
                    int rr2 = s.style_at (a.r1, a.c1).rotation;
                    return SVal.n (rr2 == 0 ? -4128 : (rr2 == 90 ? -4171 : (rr2 == 180 ? -4170 : (rr2 == 255 ? -4166 : (rr2 > 90 ? 90 - rr2 : rr2)))));
                case "rowheight": return SVal.n (Math.round (s.row_height (a.r1) * 0.75 * 100) / 100);
                case "columnwidth": return SVal.n (Math.round ((s.col_width (a.c1) - 5) / 7.0 * 100) / 100);
                case "height":
                    double hh = 0;
                    for (int i = a.r1; i <= int.min (a.r2, a.r1 + 100000); i++) hh += s.row_height (i) * 0.75;
                    return SVal.n (hh);
                case "width":
                    double ww = 0;
                    for (int j = a.c1; j <= int.min (a.c2, a.c1 + 16384); j++) ww += s.col_width (j) * 0.75;
                    return SVal.n (ww);
                case "autofit":
                case "calculate":
                    if (p == "calculate") book.recalculate ();
                    return SVal.empty ();
                case "name":
                    foreach (var e in book.names.entries) {
                        var nr2 = name_range (e.key);
                        if (nr2 != null && same_object (nr2, obj)) return name_obj (e.key);
                    }
                    throw rt (line, _("the range has no name"), 1004);
                case "find":
                case "findnext":
                case "findprevious":
                    return find (obj, p, args, names, line);
                case "replace":
                    var what2 = arg_named (args, names, 0, "what");
                    var repl = arg_named (args, names, 1, "replacement");
                    var lookat2 = arg_named (args, names, 2, "lookat");
                    var mcase2 = arg_named (args, names, 4, "matchcase");
                    if (what2 == null || repl == null) throw rt (line, _("Replace needs What and Replacement"), 449);
                    mutate (line);
                    bool whole2 = lookat2 != null && !lookat2.missing && (int) num (lookat2, line) == 1;
                    bool case2 = mcase2 != null && !mcase2.missing && truthy (mcase2, line);
                    Regex re2;
                    try {
                        string pat = Criteria.wildcard_pattern (str (what2), whole2);
                        re2 = new Regex (pat, case2 ? 0 : RegexCompileFlags.CASELESS);
                    } catch (RegexError e) {
                        throw rt (line, _("invalid search text"), 5);
                    }
                    var rr3 = clamp (obj);
                    string rtext = str (repl);
                    bool any_rep = false;
                    for (int i = rr3.r1; i <= rr3.r2; i++) for (int j = rr3.c1; j <= rr3.c2; j++) {
                        string input = s.input_at (i, j);
                        if (input == "") continue;
                        try {
                            string outp = re2.replace_literal (input, -1, 0, rtext);
                            if (outp != input) {
                                s.set_input (i, j, outp);
                                any_rep = true;
                            }
                        } catch (RegexError e) {
                        }
                    }
                    return SVal.b (any_rep);
                case "specialcells":
                    int type = args.length > 0 ? (int) num (args[0], line) : 4;
                    var matches = new Gee.ArrayList<SVal> ();
                    var sa = clamp (obj);
                    for (int i = sa.r1; i <= sa.r2; i++) {
                        int run = -1;
                        for (int j = sa.c1; j <= sa.c2 + 1; j++) {
                            bool m = false;
                            if (j <= sa.c2) {
                                var cl = s.get_cell (i, j);
                                bool blank = cl == null || (cl.input == "" && cl.formula == null);
                                m = type == 4 ? blank : (type == 2 ? (!blank && cl.formula == null) : (type == -4123 ? (cl != null && cl.formula != null) : (type == 12 ? !s.hidden_rows.contains (i) && !s.hidden_cols.contains (j) : false)));
                            }
                            if (m && run < 0) run = j;
                            if (!m && run >= 0) {
                                matches.add (SVal.range (s, new Area (s, i, run, i, j - 1)));
                                run = -1;
                            }
                        }
                    }
                    if (type == 11) return SVal.range (s, new Area.cell (s, int.max (s.max_row, 0), int.max (s.max_col, 0)));
                    if (matches.size == 0) throw rt (line, _("no cells were found"), 1004);
                    var ml = new Gee.ArrayList<Area> ();
                    foreach (var mm in matches) ml.add (mm.area);
                    return multi (s, merge_areas (ml));
                case "sort":
                    var key1 = arg_named (args, names, 0, "key1");
                    var order1 = arg_named (args, names, 1, "order1");
                    var header = arg_named (args, names, 14, "header");
                    int kc = key1 != null && key1.kind == SKind.RANGE ? key1.area.c1 : a.c1;
                    bool desc = order1 != null && !order1.missing && (int) num (order1, line) == 2;
                    bool has_header = header != null && !header.missing && (int) num (header, line) == 1;
                    sort_rows (s, clamp (obj), kc, desc, has_header, line);
                    return SVal.empty ();
                case "sum":
                case "average":
                case "min":
                case "max":
                    return worksheet_function (p, { obj }, line, true);
                case "autofilter":
                    autofilter (obj, args, names, line);
                    return SVal.empty ();
                case "hyperlinks":
                case "validation":
                case "formatconditions":
                case "characters":
                case "chart":
                    throw rt (line, _("Range.%s is not supported by the macro runtime").printf (p), 438);
            }
            throw rt (line, _("Range does not support %s").printf (p), 438);
        }

        private Gee.ArrayList<int> all_breaks (Sheet s, bool horiz) {
            var set = new Gee.TreeSet<int> ();
            set.add_all (horiz ? s.page.row_breaks : s.page.col_breaks);
            if (s.max_row >= 0) {
                var l = PrintLayout.compute (s, s.page, s.page.page_width, s.page.page_height);
                foreach (var pg in l.pages) {
                    var a = l.areas[pg.area_index];
                    int v = horiz ? pg.r1 : pg.c1;
                    if (v > (horiz ? a.r1 : a.c1)) set.add (v);
                }
            }
            var list = new Gee.ArrayList<int> ();
            list.add_all (set);
            return list;
        }

        private Gee.HashMap<Sheet, Gee.HashMap<int, Gee.ArrayList<SVal>>> filters = new Gee.HashMap<Sheet, Gee.HashMap<int, Gee.ArrayList<SVal>>> ();

        private bool crit_match (Value v, SVal crit) {
            if (crit.kind == SKind.ARRAY) {
                foreach (var it in crit.items) if (crit_match (v, it)) return true;
                return false;
            }
            string t = crit.text ();
            if (t == "") return true;
            var c = new Criteria (Value.str (t));
            return c.matches (v);
        }

        private void autofilter (SVal obj, SVal[] args, string[] names, int line) throws ScriptError {
            mutate (line);
            var s = obj.sheet;
            var a = s.filter != null ? s.filter.area : clamp (obj);
            if (obj.area.is_single () && s.filter == null) a = doc.current_region (s, obj.area.r1, obj.area.c1);
            var field = arg_named (args, names, 0, "field");
            if (field == null || field.missing) {
                if (s.filter != null) {
                    for (int r = a.r1 + 1; r <= a.r2; r++) s.hidden_rows.remove (r);
                    s.filter = null;
                    filters.unset (s);
                } else {
                    s.filter = new Filter (a);
                }
                return;
            }
            if (s.filter == null) s.filter = new Filter (a);
            if (!filters.has_key (s)) filters[s] = new Gee.HashMap<int, Gee.ArrayList<SVal>> ();
            int f = (int) num (field, line) - 1;
            var c1 = arg_named (args, names, 1, "criteria1");
            var op = arg_named (args, names, 2, "operator");
            var c2 = arg_named (args, names, 3, "criteria2");
            var spec = new Gee.ArrayList<SVal> ();
            spec.add (c1 != null && !c1.missing ? deref (c1) : SVal.s (""));
            spec.add (op != null && !op.missing ? deref (op) : SVal.n (1));
            spec.add (c2 != null && !c2.missing ? deref (c2) : SVal.s (""));
            if (c1 == null || c1.missing) filters[s].unset (f);
            else filters[s][f] = spec;
            for (int r = a.r1 + 1; r <= a.r2; r++) {
                bool show = true;
                foreach (var e in filters[s].entries) {
                    var v = s.value_at (r, a.c1 + e.key);
                    var sp = e.value;
                    bool m1 = crit_match (v, sp[0]);
                    int oper = (int) num (sp[1], line);
                    bool ok = m1;
                    var crit2 = sp[2];
                    if (crit2.kind == SKind.ARRAY) crit2 = crit2.items.size > 0 ? crit2.items[crit2.items.size - 1] : SVal.s ("");
                    if (sp[0].kind != SKind.ARRAY && crit2.text () != "" && (oper == 1 || oper == 2)) {
                        bool m2 = crit_match (v, crit2);
                        ok = oper == 2 ? (m1 || m2) : (m1 && m2);
                    }
                    if (!ok) show = false;
                }
                if (show) s.hidden_rows.remove (r);
                else s.hidden_rows.add (r);
            }
        }

        private SVal? last_find;
        private string last_find_what = "";
        private bool last_find_whole;
        private bool last_find_case;

        private SVal find (SVal obj, string p, SVal[] args, string[] names, int line) throws ScriptError {
            var s = obj.sheet;
            refresh ();
            string what;
            SVal? after;
            bool whole, mcase, backward, by_cols;
            if (p == "find") {
                var w = arg_named (args, names, 0, "what");
                if (w == null) throw rt (line, _("Find needs What"), 449);
                what = str (w);
                after = arg_named (args, names, 1, "after");
                var lookat = arg_named (args, names, 3, "lookat");
                var order = arg_named (args, names, 4, "searchorder");
                var dir = arg_named (args, names, 5, "searchdirection");
                var mc = arg_named (args, names, 6, "matchcase");
                whole = lookat != null && !lookat.missing && (int) num (lookat, line) == 1;
                mcase = mc != null && !mc.missing && truthy (mc, line);
                backward = dir != null && !dir.missing && (int) num (dir, line) == 2;
                by_cols = order != null && !order.missing && (int) num (order, line) == 2;
                last_find_what = what;
                last_find_whole = whole;
                last_find_case = mcase;
            } else {
                what = last_find_what;
                whole = last_find_whole;
                mcase = last_find_case;
                backward = p == "findprevious";
                by_cols = false;
                after = args.length > 0 && !args[0].missing ? args[0] : last_find;
            }
            var a = obj.area;
            int r2 = a.r2 == MAX_ROWS - 1 ? int.max (s.max_row + 1, a.r1) : a.r2;
            int c2 = a.c2 == MAX_COLS - 1 ? int.max (s.max_col + 1, a.c1) : a.c2;
            int rows = r2 - a.r1 + 1, cols = c2 - a.c1 + 1;
            int64 total = (int64) rows * cols;
            if (total > 20000000) throw rt (line, _("the search range is too large"), 1004);
            int64 start;
            if (after != null && !after.missing && after.kind == SKind.RANGE && a.contains (after.area.r1, after.area.c1)) {
                int ar = after.area.r1 - a.r1, ac = after.area.c1 - a.c1;
                start = by_cols ? (int64) ac * rows + ar : (int64) ar * cols + ac;
            } else {
                start = backward ? 0 : total - 1;
            }
            Regex? re = null;
            if (what != "") {
                try {
                    re = new Regex (Criteria.wildcard_pattern (what, whole), mcase ? 0 : RegexCompileFlags.CASELESS);
                } catch (RegexError e) {
                    throw rt (line, _("invalid search text"), 5);
                }
            }
            for (int64 k = 1; k <= total; k++) {
                int64 idx = backward ? ((start - k) % total + total) % total : (start + k) % total;
                int i, j;
                if (by_cols) {
                    j = (int) (idx / rows);
                    i = (int) (idx % rows);
                } else {
                    i = (int) (idx / cols);
                    j = (int) (idx % cols);
                }
                int rr = a.r1 + i, cc = a.c1 + j;
                var v = s.value_at (rr, cc);
                bool hit;
                if (what == "") hit = v.is_empty ();
                else {
                    if (v.is_empty ()) continue;
                    hit = re.match (v.display ());
                }
                if (hit) {
                    last_find = SVal.range (s, new Area.cell (s, rr, cc));
                    return last_find;
                }
            }
            return SVal.nothing ();
        }

        private void sort_rows (Sheet s, Area a, int key_col, bool desc, bool header, int line) throws ScriptError {
            mutate (line);
            int start = header ? a.r1 + 1 : a.r1;
            var rows = new Gee.ArrayList<int> ();
            for (int r = start; r <= a.r2; r++) rows.add (r);
            var keys = new Gee.HashMap<int, Value> ();
            foreach (int r in rows) keys[r] = s.value_at (r, key_col);
            rows.sort ((x, y) => {
                int c = Evaluator.compare (keys[x], keys[y]);
                return desc ? -c : c;
            });
            var saved = new Gee.HashMap<int64?, CellCopy?> ((k) => { int64 v = k; return (uint) (v ^ (v >> 32)); }, (p, q) => { int64 x = p; int64 y = q; return x == y; });
            for (int r = start; r <= a.r2; r++) {
                for (int c = a.c1; c <= a.c2; c++) {
                    var cell = s.get_cell (r, c);
                    saved[Sheet.key (r, c)] = cell != null ? new CellCopy.of (cell) : null;
                }
            }
            for (int i = 0; i < rows.size; i++) {
                int from = rows[i], to = start + i;
                for (int c = a.c1; c <= a.c2; c++) {
                    var cc = saved[Sheet.key (from, c)];
                    if (cc == null) {
                        s.set_input (to, c, "");
                        s.set_style (to, c, 0);
                        continue;
                    }
                    if (cc.formula != null) s.set_input (to, c, Formula.to_text (Formula.shifted (cc.formula, to - from, 0), s));
                    else s.set_input (to, c, cc.input);
                    s.set_style (to, c, cc.style);
                }
            }
        }

        public SVal worksheet_function (string name, SVal[] args, int line, bool raise) throws ScriptError {
            refresh ();
            var call = new Node (NodeKind.CALL);
            call.text = name.up ();
            if (!Functions.all ().has_key (call.text)) throw rt (line, _("unknown worksheet function %s").printf (name), 438);
            Node[] cargs = {};
            foreach (var a in args) {
                var vn = new Node (NodeKind.VALUE);
                if (a.missing) {
                    vn = new Node (NodeKind.MISSING);
                } else if (a.kind == SKind.RANGE) {
                    if (a.items != null) {
                        Area[] list = {};
                        foreach (var part in a.items) list += clamp (part);
                        vn.value = Value.refs (list);
                    } else {
                        vn.value = Value.range (clamp (a));
                    }
                } else {
                    vn.value = to_value (a);
                }
                cargs += vn;
            }
            call.args = cargs;
            var ev = new Evaluator (book, host.active, 0, 0);
            var r = ev.eval (call);
            if (r.kind == ValueKind.RANGE) {
                if (r.area.is_single ()) return from_cell (r.area.sheet ?? host.active, r.area.r1, r.area.c1);
                return SVal.range (r.area.sheet ?? host.active, r.area);
            }
            if (r.kind == ValueKind.ARRAY) {
                var rows = new Gee.ArrayList<SVal> ();
                int nr = r.array.length[0], nc = r.array.length[1];
                if (nr == 1) {
                    var flat = new Gee.ArrayList<SVal> ();
                    for (int j = 0; j < nc; j++) flat.add (from_value (r.array[0, j]));
                    return SVal.arr (flat, 1);
                }
                for (int i = 0; i < nr; i++) {
                    var row = new Gee.ArrayList<SVal> ();
                    for (int j = 0; j < nc; j++) row.add (from_value (r.array[i, j]));
                    rows.add (SVal.arr (row, 1));
                }
                return SVal.arr (rows, 1);
            }
            if (r.is_error ()) {
                if (raise) throw rt (line, _("unable to get the %s property of the WorksheetFunction class (%s)").printf (name, r.error.to_string ()), 1004);
                return from_value (r);
            }
            return from_value (r);
        }

        private SVal need (SVal[] args, int i, int line, string fname) throws ScriptError {
            if (i >= args.length || args[i].missing) throw rt (line, _("argument not optional in %s").printf (fname), 449);
            return deref (args[i]);
        }

        private SVal opt (SVal[] args, int i) {
            if (i >= args.length || args[i].missing) return SVal.omitted ();
            return deref (args[i]);
        }

        private int ubound_of (SVal arr, int dim, int line) throws ScriptError {
            if (arr.kind != SKind.ARRAY) throw rt (line, _("type mismatch: an array was expected"), 13);
            SVal cur = arr;
            for (int d = 1; d < dim; d++) {
                if (cur.items.size == 0 || cur.items[0].kind != SKind.ARRAY) throw rt (line, _("subscript out of range"), 9);
                cur = cur.items[0];
            }
            return cur.lbound + cur.items.size - 1;
        }

        private int lbound_of (SVal arr, int dim, int line) throws ScriptError {
            if (arr.kind != SKind.ARRAY) throw rt (line, _("type mismatch: an array was expected"), 13);
            SVal cur = arr;
            for (int d = 1; d < dim; d++) {
                if (cur.items.size == 0 || cur.items[0].kind != SKind.ARRAY) throw rt (line, _("subscript out of range"), 9);
                cur = cur.items[0];
            }
            return cur.lbound;
        }

        private double date_add (string interval, double n, double d) {
            switch (interval.down ()) {
                case "yyyy": return ScriptLib.add_months (d, (int) n * 12);
                case "q": return ScriptLib.add_months (d, (int) n * 3);
                case "m": return ScriptLib.add_months (d, (int) n);
                case "ww": return d + n * 7;
                case "h": return d + n / 24.0;
                case "n": return d + n / 1440.0;
                case "s": return d + n / 86400.0;
                default: return d + n;
            }
        }

        private double date_diff (string interval, double a, double b) {
            int y1, m1, d1, y2, m2, d2;
            DateSerial.to_ymd (a, out y1, out m1, out d1);
            DateSerial.to_ymd (b, out y2, out m2, out d2);
            switch (interval.down ()) {
                case "yyyy": return y2 - y1;
                case "q": return (y2 * 4 + (m2 - 1) / 3) - (y1 * 4 + (m1 - 1) / 3);
                case "m": return (y2 * 12 + m2) - (y1 * 12 + m1);
                case "ww": case "w": return Math.floor ((Math.floor (b) - Math.floor (a)) / 7);
                case "h": return Math.floor ((b - a) * 24 + 1e-9);
                case "n": return Math.floor ((b - a) * 1440 + 1e-9);
                case "s": return Math.round ((b - a) * 86400);
                default: return Math.floor (b) - Math.floor (a);
            }
        }

        private SVal typename (SVal v) {
            switch (v.kind) {
                case SKind.EMPTY: return SVal.s (v.missing ? "Error" : "Empty");
                case SKind.NUM: return SVal.s (v.is_date ? "Date" : (v.num == Math.floor (v.num) && Math.fabs (v.num) < 2147483648 ? "Long" : "Double"));
                case SKind.STR: return SVal.s ("String");
                case SKind.BOOL: return SVal.s ("Boolean");
                case SKind.ARRAY: return SVal.s ("Variant()");
                case SKind.RANGE: return SVal.s ("Range");
                case SKind.SHEET: return SVal.s ("Worksheet");
                case SKind.BOOK: return SVal.s ("Workbook");
                case SKind.APP: return SVal.s ("Application");
                case SKind.COLL: return SVal.s ("Collection");
                case SKind.DICT: return SVal.s ("Dictionary");
                case SKind.NOTHING: return SVal.s ("Nothing");
                case SKind.NAME: return SVal.s ("Name");
                case SKind.SHEETS: return SVal.s ("Sheets");
                case SKind.ERRVAL: return SVal.s ("Error");
                default: return SVal.s ("Object");
            }
        }

        private int vartype (SVal v) {
            switch (v.kind) {
                case SKind.EMPTY: return v.missing ? 10 : 0;
                case SKind.NUM: return v.is_date ? 7 : (v.num == Math.floor (v.num) && Math.fabs (v.num) < 2147483648 ? 3 : 5);
                case SKind.STR: return 8;
                case SKind.BOOL: return 11;
                case SKind.ARRAY: return 8204;
                case SKind.ERRVAL: return 10;
                default: return 9;
            }
        }

        private string format_value (SVal v, string fmt) {
            var val = to_value (v);
            if (v.kind == SKind.STR) {
                double d;
                string f;
                if (Input.parse_number (v.str.strip (), out d, out f)) val = Value.num (d);
                else if (ScriptLib.parse_date_literal (v.str, out d)) val = Value.num (d);
            }
            if (fmt == "" && v.is_date) return v.text ();
            return ScriptLib.vba_format (val, fmt, book.date1904);
        }

        public SVal call_named (string name, SVal[] args, string[] names, int line, bool bare) throws ScriptError {
            string n = name.down ();
            if (n.has_suffix ("$")) n = n.substring (0, n.length - 1);
            if (bare) {
                var cnum = ScriptLib.constant (n);
                if (cnum != null) return SVal.n (cnum);
                var cstr = ScriptLib.string_constant (n);
                if (cstr != null) return SVal.s (cstr);
            }
            if (n in ScriptLib.FORBIDDEN_FUNCTIONS) {
                if (n == "createobject" && args.length > 0) {
                    string prog = str (args[0]).down ();
                    if (prog == "scripting.dictionary") return make_new ("dictionary", line);
                    if (prog == "vba.collection") return make_new ("collection", line);
                }
                throw rt (line, _("%s is not allowed: macros cannot run programs, create external objects or touch files").printf (name), 70);
            }
            switch (n) {
                case "__typeof":
                    var tv = args[0];
                    string want = str (args[1]);
                    string have = typename (tv).str.down ();
                    return SVal.b (have == want || want == "object" && tv.is_object ());
                case "msgbox":
                    var prompt = arg_named (args, names, 0, "prompt");
                    var buttons = arg_named (args, names, 1, "buttons");
                    var title = arg_named (args, names, 2, "title");
                    int b = buttons != null && !buttons.missing ? (int) num (buttons, line) : 0;
                    int res = host.ask (prompt != null ? str (prompt) : "", title != null && !title.missing ? str (title) : "Microsoft Excel", b);
                    return SVal.n (res);
                case "inputbox":
                    var ip = arg_named (args, names, 0, "prompt");
                    var it = arg_named (args, names, 1, "title");
                    var idf = arg_named (args, names, 2, "default");
                    string? got = host.input (ip != null ? str (ip) : "", it != null && !it.missing ? str (it) : "Microsoft Excel", idf != null && !idf.missing ? str (idf) : "");
                    return SVal.s (got ?? "");
                case "print":
                    string[] parts = {};
                    foreach (var a in args) parts += str (a);
                    host.log (string.joinv (" ", parts));
                    return SVal.empty ();
                case "intersect":
                case "union":
                case "inputbox_app":
                    return app_member (n, name, args, names, line);
                case "debug": return SVal.obj (SKind.DEBUG);
                case "err": return SVal.obj (SKind.ERR);
                case "me":
                case "activesheet": return SVal.of_sheet (host.active);
                case "activecell": return active_cell ();
                case "selection": return selection ();
                case "activewindow": return SVal.obj (SKind.WINDOW);
                case "range":
                    if (args.length >= 2 && args[0].kind == SKind.RANGE && args[1].kind == SKind.RANGE) return span (args[0], args[1]);
                    if (args.length == 1 && args[0].kind == SKind.RANGE) return args[0];
                    return make_range (host.active, need (args, 0, line, "Range").text (), line);
                case "cells": return cells_of (host.active, args, line);
                case "rows": return rows_of (host.active, args, line);
                case "columns": return cols_of (host.active, args, line);
                case "sheets":
                case "worksheets":
                    if (args.length == 0) return SVal.obj (SKind.SHEETS);
                    return SVal.of_sheet (sheet_of (deref (args[0]), line));
                case "names": return args.length == 0 ? SVal.obj (SKind.NAMES) : name_item (deref (args[0]), line);
                case "workbook":
                case "activeworkbook":
                case "thisworkbook":
                    return SVal.obj (SKind.BOOK);
                case "workbooks":
                case "application":
                case "excel":
                    if (n == "workbooks") return app_member ("workbooks", name, args, names, line);
                    return SVal.obj (SKind.APP);
                case "worksheetfunction":
                case "wf":
                    return SVal.obj (SKind.FUNCS);
                case "evaluate":
                    refresh ();
                    string f = need (args, 0, line, "Evaluate").text ();
                    if (!f.has_prefix ("=") && parse_address (host.active, f) != null) return make_range (host.active, f, line);
                    try {
                        var node = Formula.parse (f.has_prefix ("=") ? f : "=" + f, book, host.active);
                        var ev = new Evaluator (book, host.active, 0, 0);
                        var r = ev.eval (node);
                        if (r.kind == ValueKind.RANGE && !r.area.is_single ()) return SVal.range (r.area.sheet ?? host.active, r.area);
                        if (r.kind == ValueKind.RANGE) return SVal.range (r.area.sheet ?? host.active, r.area);
                        return from_value (ev.eval_top (node));
                    } catch (FormulaError e) {
                        var ev2 = SVal.obj (SKind.ERRVAL);
                        ev2.num = 2029;
                        ev2.str = "#NAME?";
                        return ev2;
                    }
                case "run":
                    string an = need (args, 0, line, "Run").text ();
                    var proc = script.procs[an.down ()];
                    if (proc != null) {
                        try {
                            return call_proc (proc, args.length > 1 ? args[1:args.length] : new SVal[0], line, null);
                        } catch (ExitError x) {
                            return SVal.empty ();
                        }
                    }
                    finish ();
                    bool ok = host.run_action (an);
                    if (!udf_mode) {
                        doc.begin_book (label, host.active);
                        in_step = true;
                    }
                    if (!ok) throw rt (line, _("unknown command %s").printf (an), 1004);
                    return SVal.empty ();
                case "calculate":
                    book.recalculate ();
                    return SVal.empty ();
                case "doevents":
                case "beep":
                case "randomize":
                    return SVal.empty ();
                case "array":
                    var list = new Gee.ArrayList<SVal> ();
                    foreach (var a in args) list.add (deref (a));
                    return SVal.arr (list);
                case "len":
                    var lv = need (args, 0, line, name);
                    return SVal.n (lv.kind == SKind.EMPTY ? 0 : lv.text ().char_count ());
                case "lenb": return SVal.n (need (args, 0, line, name).text ().char_count () * 2);
                case "left":
                    string ls = need (args, 0, line, name).text ();
                    int ln = (int) num (need (args, 1, line, name), line);
                    if (ln < 0) throw rt (line, _("invalid procedure call or argument"), 5);
                    return SVal.s (TextFunctions.sub (ls, 0, ln));
                case "right":
                    string rs = need (args, 0, line, name).text ();
                    int rn = (int) num (need (args, 1, line, name), line);
                    if (rn < 0) throw rt (line, _("invalid procedure call or argument"), 5);
                    int rl = rs.char_count ();
                    return SVal.s (TextFunctions.sub (rs, int.max (0, rl - rn), rn));
                case "mid":
                    string ms = need (args, 0, line, name).text ();
                    int st = (int) num (need (args, 1, line, name), line);
                    if (st < 1) throw rt (line, _("invalid procedure call or argument"), 5);
                    var mc = opt (args, 2);
                    int cnt = mc.missing ? ms.char_count () : (int) num (mc, line);
                    return SVal.s (TextFunctions.sub (ms, st - 1, cnt));
                case "ucase": return SVal.s (need (args, 0, line, name).text ().up ());
                case "lcase": return SVal.s (need (args, 0, line, name).text ().down ());
                case "trim": return SVal.s (need (args, 0, line, name).text ().strip ());
                case "ltrim": return SVal.s (need (args, 0, line, name).text ().chug ());
                case "rtrim": return SVal.s (need (args, 0, line, name).text ().chomp ());
                case "instr":
                case "instrb":
                    int start = 1;
                    int k = 0;
                    if (args.length > 2 && deref (args[0]).kind == SKind.NUM) {
                        start = (int) num (args[0], line);
                        k = 1;
                    }
                    string hay = need (args, k, line, name).text ();
                    string ndl = need (args, k + 1, line, name).text ();
                    var cmp = opt (args, k + 2);
                    bool text_cmp = !cmp.missing && (int) num (cmp, line) == 1;
                    if (text_cmp) {
                        hay = hay.casefold ();
                        ndl = ndl.casefold ();
                    }
                    if (start > hay.char_count () + 1) return SVal.n (0);
                    if (ndl == "") return SVal.n (start);
                    int off = hay.index_of_nth_char (int.max (start - 1, 0));
                    int idx = hay.index_of (ndl, off);
                    return SVal.n (idx < 0 ? 0 : hay.substring (0, idx).char_count () + 1);
                case "instrrev":
                    string h2 = need (args, 0, line, name).text ();
                    string n2 = need (args, 1, line, name).text ();
                    var sv = opt (args, 2);
                    int st2 = sv.missing || (int) num (sv, line) == -1 ? h2.char_count () : (int) num (sv, line);
                    string head = TextFunctions.sub (h2, 0, st2);
                    int li = head.last_index_of (n2);
                    return SVal.n (li < 0 ? 0 : head.substring (0, li).char_count () + 1);
                case "replace":
                    string src = need (args, 0, line, name).text ();
                    string fnd = need (args, 1, line, name).text ();
                    string rep = need (args, 2, line, name).text ();
                    var rstart = opt (args, 3);
                    var rcount = opt (args, 4);
                    var rcmp = opt (args, 5);
                    int s0 = rstart.missing ? 1 : (int) num (rstart, line);
                    int limit = rcount.missing ? -1 : (int) num (rcount, line);
                    string tail = TextFunctions.sub (src, s0 - 1, src.char_count ());
                    if (fnd == "") return SVal.s (tail);
                    bool ci = !rcmp.missing && (int) num (rcmp, line) == 1;
                    var sb = new StringBuilder ();
                    int done = 0;
                    int from = 0;
                    string hay2 = ci ? tail.casefold () : tail;
                    string nd2 = ci ? fnd.casefold () : fnd;
                    while (limit < 0 || done < limit) {
                        int at = hay2.index_of (nd2, from);
                        if (at < 0) break;
                        sb.append (tail.substring (from, at - from));
                        sb.append (rep);
                        from = at + fnd.length;
                        done++;
                    }
                    sb.append (tail.substring (from));
                    return SVal.s (sb.str);
                case "split":
                    string whole = need (args, 0, line, name).text ();
                    var dl = opt (args, 1);
                    string sep = dl.missing ? " " : dl.text ();
                    var sl = new Gee.ArrayList<SVal> ();
                    if (whole == "") return SVal.arr (sl);
                    var lim = opt (args, 2);
                    int max = lim.missing ? -1 : (int) num (lim, line);
                    if (sep == "") {
                        sl.add (SVal.s (whole));
                        return SVal.arr (sl);
                    }
                    string[] pieces = max > 0 ? whole.split (sep, max) : whole.split (sep);
                    foreach (string part in pieces) sl.add (SVal.s (part));
                    return SVal.arr (sl);
                case "join":
                    var arr = need (args, 0, line, name);
                    if (arr.kind != SKind.ARRAY) throw rt (line, _("type mismatch: Join needs an array"), 13);
                    string[] jp = {};
                    foreach (var itm in arr.items) jp += str (itm);
                    var jd = opt (args, 1);
                    return SVal.s (string.joinv (jd.missing ? " " : jd.text (), jp));
                case "filter":
                    var fa = need (args, 0, line, name);
                    string match = need (args, 1, line, name).text ();
                    var inc = opt (args, 2);
                    bool include = inc.missing || truthy (inc, line);
                    var fl = new Gee.ArrayList<SVal> ();
                    if (fa.kind == SKind.ARRAY) foreach (var itm in fa.items) if (str (itm).contains (match) == include) fl.add (itm);
                    return SVal.arr (fl);
                case "ubound": return SVal.n (ubound_of (need (args, 0, line, name), args.length > 1 ? (int) num (args[1], line) : 1, line));
                case "lbound": return SVal.n (lbound_of (need (args, 0, line, name), args.length > 1 ? (int) num (args[1], line) : 1, line));
                case "str":
                    var sv2 = need (args, 0, line, name);
                    double sd = num (sv2, line);
                    return SVal.s ((sd >= 0 ? " " : "") + SVal.num_text (sd));
                case "cstr":
                    var cv = need (args, 0, line, name);
                    if (cv.kind == SKind.BOOL) return SVal.s (cv.num != 0 ? "True" : "False");
                    return SVal.s (cv.text ());
                case "val":
                    string vs = need (args, 0, line, name).text ().strip ().replace (" ", "");
                    int vi = 0;
                    while (vi < vs.length && (vs[vi].isdigit () || vs[vi] == '.' || (vi == 0 && (vs[vi] == '-' || vs[vi] == '+')) || ((vs[vi] == 'e' || vs[vi] == 'E') && vi > 0))) vi++;
                    return SVal.n (double.parse (vs.substring (0, vi)));
                case "cdbl":
                case "csng":
                case "ccur":
                case "cdec":
                case "cvar":
                    if (n == "cvar") return need (args, 0, line, name);
                    return SVal.n (num (need (args, 0, line, name), line));
                case "cint":
                case "clng":
                case "clnglng":
                case "clngptr":
                case "cbyte":
                    double cd = ScriptLib.bankers_round (num (need (args, 0, line, name), line));
                    if (n == "cint" && (cd < -32768 || cd > 32767)) throw rt (line, _("overflow"), 6);
                    if (n == "cbyte" && (cd < 0 || cd > 255)) throw rt (line, _("overflow"), 6);
                    return SVal.n (cd);
                case "cbool": return SVal.b (truthy (need (args, 0, line, name), line));
                case "cdate":
                case "datevalue":
                    var dv = need (args, 0, line, name);
                    if (dv.kind == SKind.STR) {
                        double serial;
                        if (!ScriptLib.parse_date_literal (dv.str, out serial)) throw rt (line, _("type mismatch: \"%s\" is not a date").printf (dv.str), 13);
                        return SVal.date (n == "datevalue" ? Math.floor (serial) : serial);
                    }
                    return SVal.date (num (dv, line));
                case "timevalue":
                    double tvs;
                    if (!ScriptLib.parse_date_literal (need (args, 0, line, name).text (), out tvs)) throw rt (line, _("type mismatch"), 13);
                    return SVal.date (tvs - Math.floor (tvs));
                case "cverr":
                    var ce = SVal.obj (SKind.ERRVAL);
                    ce.num = num (need (args, 0, line, name), line);
                    switch ((int) ce.num) {
                        case 2000: ce.str = "#NULL!"; break;
                        case 2007: ce.str = "#DIV/0!"; break;
                        case 2015: ce.str = "#VALUE!"; break;
                        case 2023: ce.str = "#REF!"; break;
                        case 2029: ce.str = "#NAME?"; break;
                        case 2036: ce.str = "#NUM!"; break;
                        default: ce.str = "#N/A"; break;
                    }
                    return ce;
                case "int": return SVal.n (Math.floor (num (need (args, 0, line, name), line)));
                case "fix": return SVal.n (Math.trunc (num (need (args, 0, line, name), line)));
                case "abs": return SVal.n (Math.fabs (num (need (args, 0, line, name), line)));
                case "sqr":
                case "sqrt":
                    double sq = num (need (args, 0, line, name), line);
                    if (sq < 0) throw rt (line, _("invalid procedure call or argument"), 5);
                    return SVal.n (Math.sqrt (sq));
                case "exp": return SVal.n (Math.exp (num (need (args, 0, line, name), line)));
                case "log":
                    double lg = num (need (args, 0, line, name), line);
                    if (lg <= 0) throw rt (line, _("invalid procedure call or argument"), 5);
                    return SVal.n (Math.log (lg));
                case "sin": return SVal.n (Math.sin (num (need (args, 0, line, name), line)));
                case "cos": return SVal.n (Math.cos (num (need (args, 0, line, name), line)));
                case "tan": return SVal.n (Math.tan (num (need (args, 0, line, name), line)));
                case "atn": return SVal.n (Math.atan (num (need (args, 0, line, name), line)));
                case "sgn":
                    double sg = num (need (args, 0, line, name), line);
                    return SVal.n (sg > 0 ? 1 : (sg < 0 ? -1 : 0));
                case "round":
                    double rv = num (need (args, 0, line, name), line);
                    var rdv = opt (args, 1);
                    return SVal.n (ScriptLib.bankers_round (rv, rdv.missing ? 0 : (int) num (rdv, line)));
                case "rnd": return SVal.n (Random.next_double ());
                case "now": return SVal.date (DateSerial.now ());
                case "date": return SVal.date (Math.floor (DateSerial.now ()));
                case "time":
                    double nw = DateSerial.now ();
                    return SVal.date (nw - Math.floor (nw));
                case "timer":
                    var dt = new DateTime.now_local ();
                    return SVal.n (dt.get_hour () * 3600 + dt.get_minute () * 60 + dt.get_seconds ());
                case "dateserial":
                    int yy = (int) num (need (args, 0, line, name), line), mm = (int) num (need (args, 1, line, name), line), dd = (int) num (need (args, 2, line, name), line);
                    if (yy < 100) yy += yy < 30 ? 2000 : 1900;
                    double base_d = ScriptLib.add_months (DateSerial.from_ymd (yy, 1, 1), mm - 1);
                    return SVal.date (base_d + dd - 1);
                case "timeserial":
                    double hs = num (need (args, 0, line, name), line), mns = num (need (args, 1, line, name), line), ss = num (need (args, 2, line, name), line);
                    return SVal.date ((hs * 3600 + mns * 60 + ss) / 86400.0);
                case "year":
                case "month":
                case "day":
                    int y, m, d;
                    DateSerial.to_ymd (num (need (args, 0, line, name), line), out y, out m, out d);
                    return SVal.n (n == "year" ? y : (n == "month" ? m : d));
                case "hour":
                case "minute":
                case "second":
                    int h, mi, sec;
                    double frac;
                    DateSerial.to_hms (num (need (args, 0, line, name), line), out h, out mi, out sec, out frac);
                    return SVal.n (n == "hour" ? h : (n == "minute" ? mi : sec));
                case "weekday":
                    var wfirst = opt (args, 1);
                    int first = wfirst.missing ? 1 : (int) num (wfirst, line);
                    int wd = DateSerial.weekday (num (need (args, 0, line, name), line)) + 1;
                    if (first == 0) first = 1;
                    return SVal.n (((wd - first) % 7 + 7) % 7 + 1);
                case "weekdayname":
                    int wdi = (int) num (need (args, 0, line, name), line);
                    var abbr = opt (args, 1);
                    string[] wnames = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
                    string wn = wnames[((wdi - 1) % 7 + 7) % 7];
                    return SVal.s (!abbr.missing && truthy (abbr, line) ? wn.substring (0, 3) : wn);
                case "monthname":
                    int mni = (int) num (need (args, 0, line, name), line);
                    if (mni < 1 || mni > 12) throw rt (line, _("invalid procedure call or argument"), 5);
                    var mab = opt (args, 1);
                    string[] mnames = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
                    return SVal.s (!mab.missing && truthy (mab, line) ? mnames[mni - 1].substring (0, 3) : mnames[mni - 1]);
                case "dateadd":
                    return SVal.date (date_add (need (args, 0, line, name).text (), num (need (args, 1, line, name), line), num (need (args, 2, line, name), line)));
                case "datediff":
                    return SVal.n (date_diff (need (args, 0, line, name).text (), num (need (args, 1, line, name), line), num (need (args, 2, line, name), line)));
                case "datepart":
                    string iv = need (args, 0, line, name).text ().down ();
                    double dp = num (need (args, 1, line, name), line);
                    int py, pm, pd, ph, pmi, ps;
                    double pf;
                    DateSerial.to_ymd (dp, out py, out pm, out pd);
                    DateSerial.to_hms (dp, out ph, out pmi, out ps, out pf);
                    switch (iv) {
                        case "yyyy": return SVal.n (py);
                        case "q": return SVal.n ((pm - 1) / 3 + 1);
                        case "m": return SVal.n (pm);
                        case "d": return SVal.n (pd);
                        case "y": return SVal.n (Math.floor (dp) - DateSerial.from_ymd (py, 1, 1) + 1);
                        case "w": return SVal.n (DateSerial.weekday (dp) + 1);
                        case "ww": return SVal.n (Math.floor ((Math.floor (dp) - DateSerial.from_ymd (py, 1, 1) + DateSerial.weekday (DateSerial.from_ymd (py, 1, 1))) / 7) + 1);
                        case "h": return SVal.n (ph);
                        case "n": return SVal.n (pmi);
                        case "s": return SVal.n (ps);
                    }
                    throw rt (line, _("invalid procedure call or argument"), 5);
                case "format":
                    var fv = need (args, 0, line, name);
                    var ff = opt (args, 1);
                    return SVal.s (format_value (fv, ff.missing ? "" : ff.text ()));
                case "formatnumber":
                case "formatcurrency":
                case "formatpercent":
                    double fn = num (need (args, 0, line, name), line);
                    var fdig = opt (args, 1);
                    int dg = fdig.missing || (int) num (fdig, line) < 0 ? 2 : (int) num (fdig, line);
                    string dec = dg > 0 ? "." + string.nfill (dg, '0') : "";
                    string fcode = n == "formatpercent" ? "0" + dec + "%" : (n == "formatcurrency" ? "$#,##0" + dec : "#,##0" + dec);
                    return SVal.s (ScriptLib.vba_format (Value.num (fn), fcode, book.date1904));
                case "formatdatetime":
                    double fdt = num (need (args, 0, line, name), line);
                    var fmode = opt (args, 1);
                    int mode = fmode.missing ? 0 : (int) num (fmode, line);
                    string[] fmts = { "general date", "long date", "short date", "long time", "short time" };
                    return SVal.s (ScriptLib.vba_format (Value.num (fdt), fmts[mode.clamp (0, 4)], book.date1904));
                case "isnumeric":
                    var nv = need (args, 0, line, name);
                    if (nv.kind == SKind.NUM || nv.kind == SKind.BOOL || nv.kind == SKind.EMPTY) return SVal.b (true);
                    double dd2;
                    string ff2;
                    return SVal.b (nv.kind == SKind.STR && Input.parse_number (nv.str.strip (), out dd2, out ff2));
                case "isdate":
                    var idv = need (args, 0, line, name);
                    if (idv.kind == SKind.NUM) return SVal.b (idv.is_date);
                    double ids;
                    return SVal.b (idv.kind == SKind.STR && ScriptLib.parse_date_literal (idv.str, out ids));
                case "isempty":
                    var ie = args.length > 0 ? deref (args[0]) : SVal.empty ();
                    return SVal.b (ie.kind == SKind.EMPTY && !ie.missing);
                case "isnull": return SVal.b (false);
                case "isarray": return SVal.b (args.length > 0 && deref (args[0]).kind == SKind.ARRAY);
                case "isobject": return SVal.b (args.length > 0 && args[0].is_object ());
                case "ismissing": return SVal.b (args.length > 0 && args[0].missing);
                case "iserror": return SVal.b (args.length > 0 && deref (args[0]).kind == SKind.ERRVAL);
                case "chr":
                case "chrw":
                case "chrb":
                    int code = (int) num (need (args, 0, line, name), line);
                    if (code < 0 || code > 0x10FFFF) throw rt (line, _("invalid procedure call or argument"), 5);
                    if (code == 0) return SVal.s ("");
                    return SVal.s (((unichar) code).to_string ());
                case "asc":
                case "ascw":
                case "ascb":
                    string at = need (args, 0, line, name).text ();
                    if (at == "") throw rt (line, _("invalid procedure call or argument"), 5);
                    return SVal.n (at.get_char (0));
                case "space": return SVal.s (string.nfill ((int) num (need (args, 0, line, name), line), ' '));
                case "string":
                    int count = (int) num (need (args, 0, line, name), line);
                    var chv = need (args, 1, line, name);
                    string chs = chv.kind == SKind.NUM ? ((unichar) (int) chv.num).to_string () : chv.text ();
                    var sbs = new StringBuilder ();
                    unichar first_ch = chs.get_char (0);
                    for (int i = 0; i < count; i++) sbs.append_unichar (first_ch);
                    return SVal.s (sbs.str);
                case "strreverse": return SVal.s (need (args, 0, line, name).text ().reverse ());
                case "strcomp":
                    string sa = need (args, 0, line, name).text (), sb2 = need (args, 1, line, name).text ();
                    var sc = opt (args, 2);
                    if (!sc.missing && (int) num (sc, line) == 1) {
                        sa = sa.casefold ();
                        sb2 = sb2.casefold ();
                    }
                    int c = strcmp (sa, sb2);
                    return SVal.n (c < 0 ? -1 : (c > 0 ? 1 : 0));
                case "strconv":
                    string cs = need (args, 0, line, name).text ();
                    int conv = (int) num (need (args, 1, line, name), line);
                    if (conv == 1) return SVal.s (cs.up ());
                    if (conv == 2) return SVal.s (cs.down ());
                    if (conv == 3) {
                        var pc = new StringBuilder ();
                        bool up = true;
                        int ci2 = 0;
                        unichar ch;
                        while (cs.get_next_char (ref ci2, out ch)) {
                            pc.append_unichar (up ? ch.toupper () : ch.tolower ());
                            up = !ch.isalnum ();
                        }
                        return SVal.s (pc.str);
                    }
                    return SVal.s (cs);
                case "hex":
                    int64 hv = (int64) ScriptLib.bankers_round (num (need (args, 0, line, name), line));
                    return SVal.s (hv < 0 ? "%X".printf ((uint32) hv) : "%llX".printf (hv));
                case "oct":
                    int64 ov = (int64) ScriptLib.bankers_round (num (need (args, 0, line, name), line));
                    return SVal.s ("%llo".printf (ov));
                case "iif": return truthy (need (args, 0, line, name), line) ? opt (args, 1) : opt (args, 2);
                case "choose":
                    int idx2 = (int) num (need (args, 0, line, name), line);
                    if (idx2 < 1 || idx2 >= args.length) return SVal.empty ();
                    return deref (args[idx2]);
                case "switch":
                    for (int i = 0; i + 1 < args.length; i += 2) if (truthy (args[i], line)) return deref (args[i + 1]);
                    return SVal.empty ();
                case "typename": return typename (args.length > 0 ? args[0] : SVal.empty ());
                case "vartype": return SVal.n (vartype (args.length > 0 ? deref (args[0]) : SVal.empty ()));
                case "rgb":
                    int rr = (int) num (need (args, 0, line, name), line), gg = (int) num (need (args, 1, line, name), line), bb = (int) num (need (args, 2, line, name), line);
                    return SVal.n (rr.clamp (0, 255) | (gg.clamp (0, 255) << 8) | (bb.clamp (0, 255) << 16));
                case "qbcolor":
                    int[] qb = { 0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0, 0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF };
                    int qi = (int) num (need (args, 0, line, name), line);
                    return SVal.n (qb[qi.clamp (0, 15)]);
                case "nz":
                    var nzv = need (args, 0, line, name);
                    return nzv.kind == SKind.EMPTY ? (args.length > 1 ? deref (args[1]) : SVal.n (0)) : nzv;
                case "sheetname": return SVal.s (host.active.name);
            }
            if (Functions.all ().has_key (name.up ())) return worksheet_function (name, args, line, false);
            if (bare) return SVal.empty ();
            throw rt (line, _("sub or function not defined: %s").printf (name), 35);
        }
    }
}
