namespace Singularity.Apps.Spreadsheet {

    public errordomain ScriptError {
        SYNTAX,
        RUNTIME
    }

    public class ScriptModule {
        public string name;
        public string source;

        public ScriptModule (string name, string source) {
            this.name = name;
            this.source = source;
        }
    }

    public class ScriptStore {
        public Gee.ArrayList<ScriptModule> modules = new Gee.ArrayList<ScriptModule> ();
        public Gee.HashMap<string, string> shortcuts = new Gee.HashMap<string, string> ();
        public bool from_file;

        public bool is_empty () {
            return modules.size == 0;
        }

        public ScriptModule module (string name) {
            foreach (var m in modules) if (m.name.casefold () == name.casefold ()) return m;
            var m = new ScriptModule (name, "");
            modules.add (m);
            return m;
        }

        public string all_source () {
            var sb = new StringBuilder ();
            foreach (var m in modules) {
                sb.append (m.source);
                if (!m.source.has_suffix ("\n")) sb.append ("\n");
            }
            return sb.str;
        }

        public Gee.ArrayList<string> macro_names () {
            var list = new Gee.ArrayList<string> ();
            foreach (var m in modules) {
                foreach (string name in Script.list_subs (m.source)) list.add (name);
            }
            return list;
        }

        public ScriptModule? module_of (string macro) {
            foreach (var m in modules) {
                foreach (string name in Script.list_subs (m.source)) if (name.casefold () == macro.casefold ()) return m;
            }
            return null;
        }

        public void remove_macro (string macro) {
            var m = module_of (macro);
            if (m == null) return;
            m.source = Script.remove_sub (m.source, macro);
            shortcuts.unset (macro);
            if (m.source.strip () == "") modules.remove (m);
        }

        public ScriptStore copy () {
            var s = new ScriptStore ();
            foreach (var m in modules) s.modules.add (new ScriptModule (m.name, m.source));
            foreach (var e in shortcuts.entries) s.shortcuts[e.key] = e.value;
            return s;
        }
    }

    public class ScriptHost : Object {
        public Sheet? active;
        public Area? selected;
        public Gee.ArrayList<string> messages = new Gee.ArrayList<string> ();
        public Gee.ArrayList<string> output = new Gee.ArrayList<string> ();
        public Gee.ArrayList<string> inputs = new Gee.ArrayList<string> ();

        public virtual void message (string text, string title) {
            messages.add (text);
        }

        public virtual string? input (string prompt, string title, string def) {
            if (inputs.size > 0) return inputs.remove_at (0);
            return def;
        }

        public virtual void select (Sheet s, Area a) {
            active = s;
            selected = a;
        }

        public virtual void activate_sheet (Sheet s) {
            active = s;
        }

        public virtual bool run_action (string name) {
            return false;
        }

        public virtual void log (string text) {
            output.add (text);
        }

        public virtual bool export_pdf (Sheet s, string path) {
            return false;
        }

        public virtual int ask (string text, string title, int buttons) {
            messages.add (text);
            if (answers.size > 0) return answers.remove_at (0);
            return buttons % 8 == 4 || buttons % 8 == 3 ? 6 : 1;
        }

        public Gee.ArrayList<int> answers = new Gee.ArrayList<int> ();
    }

    public interface UdfProvider : Object {
        public abstract Value? call_udf (string name, Value[] args);
    }

    public class MacroUdf : Object, UdfProvider {
        private ScriptRunner runner;
        private bool busy;

        public MacroUdf (Document doc) throws ScriptError {
            var host = new ScriptHost ();
            host.active = doc.book.sheets[0];
            runner = new ScriptRunner (doc, host);
            runner.udf_mode = true;
            runner.load (ScriptRunner.sources (doc.book, true));
        }

        public Value? call_udf (string name, Value[] args) {
            if (busy || !runner.has_proc (name)) return null;
            busy = true;
            SVal[] sargs = {};
            foreach (var v in args) {
                if (v.kind == ValueKind.RANGE) sargs += SVal.range (v.area.sheet ?? runner.host.active, v.area);
                else if (v.kind == ValueKind.ARRAY) {
                    var rows = new Gee.ArrayList<SVal> ();
                    for (int i = 0; i < v.array.length[0]; i++) {
                        var row = new Gee.ArrayList<SVal> ();
                        for (int j = 0; j < v.array.length[1]; j++) row.add (ScriptRunner.from_value (v.array[i, j]));
                        rows.add (SVal.arr (row, 1));
                    }
                    sargs += SVal.arr (rows, 1);
                } else if (v.omitted) sargs += SVal.omitted ();
                else sargs += ScriptRunner.from_value (v);
            }
            Value result;
            try {
                var r = runner.call_function (name, sargs);
                result = runner.to_value (r);
                if (result.kind == ValueKind.EMPTY) result = Value.num (0);
            } catch (ScriptError e) {
                result = Value.err (ErrorKind.VALUE);
            }
            busy = false;
            return result;
        }
    }
}
