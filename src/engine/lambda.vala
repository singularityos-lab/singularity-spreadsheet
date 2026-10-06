namespace Singularity.Apps.Spreadsheet {

    public class Scope {
        public Scope? parent;
        public Gee.HashMap<string, Value> vars = new Gee.HashMap<string, Value> ();

        public Scope (Scope? parent) {
            this.parent = parent;
        }

        public void bind (string name, Value v) {
            vars[name.casefold ()] = v;
        }

        public Value? lookup (string name) {
            string k = name.casefold ();
            for (Scope? s = this; s != null; s = s.parent) {
                if (s.vars.has_key (k)) return s.vars[k];
            }
            return null;
        }
    }

    public class Lambda {
        public string[] params = {};
        public Node body;
        public Scope? scope;
        public Sheet sheet;
        public int row;
        public int col;
        public string builtin = "";

        public Lambda (string[] params, Node body, Scope? scope, Sheet sheet, int row, int col) {
            this.params = params;
            this.body = body;
            this.scope = scope;
            this.sheet = sheet;
            this.row = row;
            this.col = col;
        }

        public int arity {
            get { return params.length; }
        }
    }
}
