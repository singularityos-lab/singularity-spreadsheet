namespace Singularity.Apps.Spreadsheet {

    public enum SolverGoal {
        MAX,
        MIN,
        VALUE
    }

    public enum SolverMethod {
        SIMPLEX,
        NONLINEAR,
        EVOLUTIONARY
    }

    public enum ConstraintOp {
        LE,
        GE,
        EQ,
        INT,
        BIN,
        DIF;

        public string symbol () {
            switch (this) {
                case GE: return ">=";
                case EQ: return "=";
                case INT: return "int";
                case BIN: return "bin";
                case DIF: return "dif";
                default: return "<=";
            }
        }

        public static ConstraintOp parse (string s) {
            switch (s) {
                case ">=": return GE;
                case "=": return EQ;
                case "int": return INT;
                case "bin": return BIN;
                case "dif": return DIF;
                default: return LE;
            }
        }

        public int excel_code () {
            switch (this) {
                case LE: return 1;
                case EQ: return 2;
                case GE: return 3;
                case INT: return 4;
                case BIN: return 5;
                default: return 6;
            }
        }

        public static ConstraintOp from_excel (int c) {
            switch (c) {
                case 2: return EQ;
                case 3: return GE;
                case 4: return INT;
                case 5: return BIN;
                case 6: return DIF;
                default: return LE;
            }
        }
    }

    public class SolverConstraint {
        public string lhs;
        public ConstraintOp op;
        public string rhs;

        public SolverConstraint (string lhs, ConstraintOp op, string rhs) {
            this.lhs = lhs;
            this.op = op;
            this.rhs = rhs;
        }
    }

    public class SolverResult {
        public bool ok;
        public string message = "";
        public double objective;
        public double[] values = {};
        public double[] original = {};
        public double original_objective;
        public int iterations;
    }

    public class SolverModel {
        public Sheet sheet;
        public string objective = "";
        public SolverGoal goal = SolverGoal.MAX;
        public double target;
        public string variables = "";
        public Gee.ArrayList<SolverConstraint> constraints = new Gee.ArrayList<SolverConstraint> ();
        public SolverMethod method = SolverMethod.SIMPLEX;
        public bool nonneg = true;
        public int max_iterations = 1000;
        public double precision = 1e-6;
        public double int_tolerance = 0;
        public int multistart = 8;

        private Workbook book;
        private Gee.ArrayList<CellRef> vars;
        private CellRef? obj_cell;
        private int evals;

        public SolverModel (Sheet sheet) {
            this.sheet = sheet;
        }

        private Gee.ArrayList<CellRef> cells_of (string refs) {
            var list = new Gee.ArrayList<CellRef> ();
            foreach (string part in refs.split (",")) {
                string p = part.strip ();
                if (p.has_prefix ("=")) p = p.substring (1);
                if (p == "") continue;
                Sheet s = sheet;
                int bang = p.last_index_of ("!");
                if (bang > 0) {
                    string sn = p.substring (0, bang);
                    if (sn.has_prefix ("'")) sn = sn.substring (1, sn.length - 2).replace ("''", "'");
                    var fs = book.find_sheet (sn);
                    if (fs != null) s = fs;
                    p = p.substring (bang + 1);
                }
                var a = Area.parse (p.replace ("$", ""), s);
                if (a == null) {
                    string? def = book.names[p];
                    if (def != null) {
                        foreach (var c in cells_of (def)) list.add (c);
                    }
                    continue;
                }
                for (int r = a.r1; r <= a.r2; r++) for (int c = a.c1; c <= a.c2; c++) list.add (new CellRef (s, r, c));
            }
            return list;
        }

        private double[] values_of (string refs, out bool numeric) {
            numeric = true;
            string t = refs.strip ();
            if (t.has_prefix ("=")) t = t.substring (1);
            double d;
            string fmt;
            if (Input.parse_number (t, out d, out fmt) || double.try_parse (t, out d)) return { d };
            try {
                var node = Formula.parse ("=" + t, book, sheet);
                var ev = new Evaluator (book, sheet, 0, 0);
                var v = ev.eval (node);
                var m = ev.to_matrix (v);
                double[] out_v = {};
                for (int i = 0; i < m.length[0]; i++) for (int j = 0; j < m.length[1]; j++) {
                    var x = m[i, j];
                    out_v += x.kind == ValueKind.NUMBER || x.kind == ValueKind.BOOL ? x.number : 0;
                    if (x.kind == ValueKind.ERROR) numeric = false;
                }
                return out_v;
            } catch (FormulaError e) {
                numeric = false;
                return { 0 };
            }
        }

        private void assign (double[] x) {
            for (int i = 0; i < vars.size; i++) WhatIf.set_number (book, vars[i].sheet, vars[i].row, vars[i].col, x[i]);
            book.recalculate ();
            evals++;
        }

        private double objective_value () {
            var v = obj_cell.value ();
            if (v.kind != ValueKind.NUMBER && v.kind != ValueKind.BOOL) return double.NAN;
            return v.number;
        }

        private double score () {
            double f = objective_value ();
            if (f.is_nan ()) return double.INFINITY;
            switch (goal) {
                case SolverGoal.MAX: return -f;
                case SolverGoal.MIN: return f;
                default: return (f - target) * (f - target);
            }
        }

        private double violation () {
            double v = 0;
            foreach (var c in constraints) {
                if (c.op == ConstraintOp.INT || c.op == ConstraintOp.BIN || c.op == ConstraintOp.DIF) continue;
                bool ok;
                var lhs = values_of (c.lhs, out ok);
                var rhs = values_of (c.rhs, out ok);
                for (int i = 0; i < lhs.length; i++) {
                    double r = rhs[rhs.length == 1 ? 0 : int.min (i, rhs.length - 1)];
                    double d = 0;
                    switch (c.op) {
                        case ConstraintOp.LE: d = double.max (0, lhs[i] - r); break;
                        case ConstraintOp.GE: d = double.max (0, r - lhs[i]); break;
                        default: d = Math.fabs (lhs[i] - r); break;
                    }
                    v += d * d;
                }
            }
            return v;
        }

        private bool[] int_flags (out bool[] bin_flags, out Gee.ArrayList<Gee.ArrayList<int>> dif_groups) {
            var flags = new bool[vars.size];
            var bins = new bool[vars.size];
            dif_groups = new Gee.ArrayList<Gee.ArrayList<int>> ();
            foreach (var c in constraints) {
                if (c.op != ConstraintOp.INT && c.op != ConstraintOp.BIN && c.op != ConstraintOp.DIF) continue;
                var group = new Gee.ArrayList<int> ();
                foreach (var cell in cells_of (c.lhs)) {
                    for (int i = 0; i < vars.size; i++) {
                        if (vars[i].sheet == cell.sheet && vars[i].row == cell.row && vars[i].col == cell.col) {
                            flags[i] = true;
                            if (c.op == ConstraintOp.BIN) bins[i] = true;
                            group.add (i);
                        }
                    }
                }
                if (c.op == ConstraintOp.DIF) dif_groups.add (group);
            }
            bin_flags = bins;
            return flags;
        }

        public SolverResult solve (Workbook b, bool keep = true) {
            book = b;
            evals = 0;
            var res = new SolverResult ();
            vars = cells_of (variables);
            obj_cell = CellRef.parse (book, objective, sheet);
            if (obj_cell == null || vars.size == 0) {
                res.message = _("Set an objective cell and at least one variable cell.");
                return res;
            }
            if (vars.size > 400) {
                res.message = _("Too many variable cells (the limit is 400).");
                return res;
            }
            var inputs = new string[vars.size];
            var saved = new Value[vars.size];
            res.original = new double[vars.size];
            for (int i = 0; i < vars.size; i++) {
                inputs[i] = vars[i].input ();
                saved[i] = vars[i].value ();
                res.original[i] = vars[i].number ();
            }
            res.original_objective = objective_value ();
            bool[] bins;
            Gee.ArrayList<Gee.ArrayList<int>> difs;
            var ints = int_flags (out bins, out difs);
            double[] x;
            string message;
            bool ok;
            if (difs.size > 0 || method == SolverMethod.EVOLUTIONARY) {
                ok = solve_search (res.original, ints, bins, difs, out x, out message);
            } else if (method == SolverMethod.SIMPLEX) {
                ok = solve_linear (ints, bins, out x, out message);
            } else {
                ok = solve_nonlinear (res.original, ints, bins, out x, out message);
            }
            res.ok = ok;
            res.message = message;
            if (x != null && x.length == vars.size) {
                assign (x);
                res.values = x;
                res.objective = objective_value ();
            }
            res.iterations = evals;
            if (!keep || !ok) {
                if (!keep) {
                    for (int i = 0; i < vars.size; i++) WhatIf.restore_input (book, vars[i].sheet, vars[i].row, vars[i].col, inputs[i], saved[i]);
                    book.recalculate ();
                }
            }
            return res;
        }

        public Gee.ArrayList<CellRef> variable_cells (Workbook b) {
            book = b;
            return cells_of (variables);
        }

        private bool solve_linear (bool[] ints, bool[] bins, out double[] x, out string message) {
            int n = vars.size;
            x = null;
            var zero = new double[n];
            assign (zero);
            double f0 = objective_value ();
            var cons0 = constraint_values ();
            if (f0.is_nan ()) {
                message = _("The objective cell does not contain a number.");
                return false;
            }
            var cobj = new double[n];
            var cols = new Gee.ArrayList<Gee.ArrayList<double?>> ();
            for (int j = 0; j < n; j++) {
                var e = new double[n];
                e[j] = 1;
                assign (e);
                cobj[j] = objective_value () - f0;
                var cv = constraint_values ();
                var col = new Gee.ArrayList<double?> ();
                for (int k = 0; k < cv.size; k++) col.add (cv[k] - cons0[k]);
                cols.add (col);
            }
            var probe = new double[n];
            for (int j = 0; j < n; j++) probe[j] = 1.5 + j * 0.37;
            assign (probe);
            double fp = objective_value ();
            double pred = f0;
            for (int j = 0; j < n; j++) pred += cobj[j] * probe[j];
            bool linear = Math.fabs (fp - pred) <= 1e-6 * (1 + Math.fabs (fp));
            var cvp = constraint_values ();
            for (int k = 0; k < cvp.size && linear; k++) {
                double p = cons0[k];
                for (int j = 0; j < n; j++) p += cols[j][k] * probe[j];
                if (Math.fabs (cvp[k] - p) > 1e-6 * (1 + Math.fabs (cvp[k]))) linear = false;
            }
            if (!linear) {
                message = _("The linearity conditions required by the Simplex method are not satisfied.");
                return false;
            }
            var rows = new Gee.ArrayList<LpRow> ();
            int k = 0;
            foreach (var c in constraints) {
                if (c.op == ConstraintOp.INT || c.op == ConstraintOp.BIN || c.op == ConstraintOp.DIF) continue;
                bool okr;
                var rhs = values_of (c.rhs, out okr);
                int count = values_of (c.lhs, out okr).length;
                for (int i = 0; i < count; i++) {
                    var row = new LpRow ();
                    row.a = new double[n];
                    for (int j = 0; j < n; j++) row.a[j] = cols[j][k];
                    row.op = c.op;
                    row.b = rhs[rhs.length == 1 ? 0 : int.min (i, rhs.length - 1)] - cons0[k];
                    rows.add (row);
                    k++;
                }
            }
            for (int j = 0; j < n; j++) {
                if (!bins[j]) continue;
                var row = new LpRow ();
                row.a = new double[n];
                row.a[j] = 1;
                row.op = ConstraintOp.LE;
                row.b = 1;
                rows.add (row);
            }
            double sign = goal == SolverGoal.MIN ? -1 : 1;
            var c_max = new double[n];
            for (int j = 0; j < n; j++) c_max[j] = sign * cobj[j];
            if (goal == SolverGoal.VALUE) {
                var row = new LpRow ();
                row.a = cobj;
                row.op = ConstraintOp.EQ;
                row.b = target - f0;
                rows.add (row);
                for (int j = 0; j < n; j++) c_max[j] = 0;
            }
            double best_obj = -double.INFINITY;
            double[]? best = null;
            bool any_int = false;
            foreach (bool f in ints) if (f) any_int = true;
            var stack = new Gee.ArrayList<Gee.ArrayList<LpRow>> ();
            stack.add (new Gee.ArrayList<LpRow> ());
            int nodes = 0;
            double tol = 1e-7;
            while (stack.size > 0 && nodes < 20000) {
                var extra = stack.remove_at (stack.size - 1);
                nodes++;
                var all = new Gee.ArrayList<LpRow> ();
                all.add_all (rows);
                all.add_all (extra);
                double[] sol;
                double val;
                int st = Simplex.solve (c_max, all, !nonneg, out sol, out val);
                if (st == 2 && !any_int) {
                    message = _("The objective cell values do not converge.");
                    return false;
                }
                if (st != 0) continue;
                if (val <= best_obj + tol * (1 + Math.fabs (best_obj)) && best != null) continue;
                int frac = -1;
                double worst = 0;
                for (int j = 0; j < n; j++) {
                    if (!ints[j]) continue;
                    double d = Math.fabs (sol[j] - Math.round (sol[j]));
                    if (d > 1e-6 && d > worst) {
                        worst = d;
                        frac = j;
                    }
                }
                if (frac < 0) {
                    best = sol;
                    best_obj = val;
                    continue;
                }
                var down = new Gee.ArrayList<LpRow> ();
                down.add_all (extra);
                var rd = new LpRow ();
                rd.a = new double[n];
                rd.a[frac] = 1;
                rd.op = ConstraintOp.LE;
                rd.b = Math.floor (sol[frac]);
                down.add (rd);
                var up = new Gee.ArrayList<LpRow> ();
                up.add_all (extra);
                var ru = new LpRow ();
                ru.a = new double[n];
                ru.a[frac] = 1;
                ru.op = ConstraintOp.GE;
                ru.b = Math.ceil (sol[frac]);
                up.add (ru);
                stack.add (down);
                stack.add (up);
            }
            if (best == null) {
                message = _("Solver could not find a feasible solution.");
                return false;
            }
            for (int j = 0; j < n; j++) if (ints[j]) best[j] = Math.round (best[j]);
            x = best;
            message = _("Solver found a solution. All constraints and optimality conditions are satisfied.");
            return true;
        }

        private Gee.ArrayList<double?> constraint_values () {
            var list = new Gee.ArrayList<double?> ();
            foreach (var c in constraints) {
                if (c.op == ConstraintOp.INT || c.op == ConstraintOp.BIN || c.op == ConstraintOp.DIF) continue;
                bool ok;
                var lhs = values_of (c.lhs, out ok);
                for (int i = 0; i < lhs.length; i++) list.add (lhs[i]);
            }
            return list;
        }

        private double penalized (double[] x, double mu, bool[] ints, bool[] bins) {
            var y = project (x, bins);
            assign (y);
            double s = score ();
            if (s.is_infinity () != 0) return double.MAX / 4;
            return s + mu * violation ();
        }

        private double[] project (double[] x, bool[] bins) {
            var y = new double[x.length];
            for (int i = 0; i < x.length; i++) {
                y[i] = x[i];
                if (nonneg && y[i] < 0) y[i] = 0;
                if (bins[i]) y[i] = y[i].clamp (0, 1);
            }
            return y;
        }

        private double[] local_min (double[] start, double mu, bool[] ints, bool[] bins, int budget) {
            int n = start.length;
            var x = project (start, bins);
            double fx = penalized (x, mu, ints, bins);
            double step = 1;
            for (int it = 0; it < budget; it++) {
                var g = new double[n];
                double gn = 0;
                for (int j = 0; j < n; j++) {
                    double h = 1e-6 * double.max (1, Math.fabs (x[j]));
                    var xp = x;
                    xp[j] += h;
                    double fp = penalized (xp, mu, ints, bins);
                    g[j] = (fp - fx) / h;
                    gn += g[j] * g[j];
                }
                gn = Math.sqrt (gn);
                if (gn < precision) break;
                bool moved = false;
                double t = step;
                for (int ls = 0; ls < 40; ls++) {
                    var xn = new double[n];
                    for (int j = 0; j < n; j++) xn[j] = x[j] - t * g[j] / gn;
                    xn = project (xn, bins);
                    double fn = penalized (xn, mu, ints, bins);
                    if (fn < fx - 1e-4 * t * gn * 0.0 - 1e-15) {
                        x = xn;
                        fx = fn;
                        moved = true;
                        step = t * 2;
                        break;
                    }
                    t /= 2;
                }
                if (!moved) break;
            }
            return x;
        }

        private double[] nelder_mead (double[] start, double mu, bool[] ints, bool[] bins, int budget) {
            int n = start.length;
            var pts = new Gee.ArrayList<Gee.ArrayList<double?>> ();
            var fs = new double[n + 1];
            for (int i = 0; i <= n; i++) {
                var p = new Gee.ArrayList<double?> ();
                for (int j = 0; j < n; j++) p.add (start[j] + (i == j + 1 ? double.max (1, Math.fabs (start[j]) * 0.1) : 0));
                pts.add (p);
            }
            for (int i = 0; i <= n; i++) fs[i] = penalized (arr (pts[i]), mu, ints, bins);
            for (int it = 0; it < budget; it++) {
                int[] order = new int[n + 1];
                for (int i = 0; i <= n; i++) order[i] = i;
                for (int i = 0; i <= n; i++) for (int j = i + 1; j <= n; j++) if (fs[order[j]] < fs[order[i]]) {
                    int t = order[i]; order[i] = order[j]; order[j] = t;
                }
                int best = order[0], worst = order[n], second = order[n - 1];
                if (Math.fabs (fs[worst] - fs[best]) < precision * (1 + Math.fabs (fs[best]))) break;
                var centroid = new double[n];
                for (int i = 0; i <= n; i++) if (i != worst) for (int j = 0; j < n; j++) centroid[j] += pts[i][j] / n;
                var xr = new double[n];
                for (int j = 0; j < n; j++) xr[j] = centroid[j] + (centroid[j] - pts[worst][j]);
                double fr = penalized (xr, mu, ints, bins);
                if (fr < fs[best]) {
                    var xe = new double[n];
                    for (int j = 0; j < n; j++) xe[j] = centroid[j] + 2 * (centroid[j] - pts[worst][j]);
                    double fe = penalized (xe, mu, ints, bins);
                    if (fe < fr) set_pt (pts[worst], xe, out fs[worst], fe);
                    else set_pt (pts[worst], xr, out fs[worst], fr);
                } else if (fr < fs[second]) {
                    set_pt (pts[worst], xr, out fs[worst], fr);
                } else {
                    var xc = new double[n];
                    for (int j = 0; j < n; j++) xc[j] = centroid[j] + 0.5 * (pts[worst][j] - centroid[j]);
                    double fc = penalized (xc, mu, ints, bins);
                    if (fc < fs[worst]) {
                        set_pt (pts[worst], xc, out fs[worst], fc);
                    } else {
                        for (int i = 0; i <= n; i++) {
                            if (i == best) continue;
                            var xs = new double[n];
                            for (int j = 0; j < n; j++) xs[j] = pts[best][j] + 0.5 * (pts[i][j] - pts[best][j]);
                            set_pt (pts[i], xs, out fs[i], penalized (xs, mu, ints, bins));
                        }
                    }
                }
            }
            int bi = 0;
            for (int i = 1; i <= n; i++) if (fs[i] < fs[bi]) bi = i;
            return project (arr (pts[bi]), bins);
        }

        private static void set_pt (Gee.ArrayList<double?> p, double[] x, out double f, double fv) {
            for (int j = 0; j < x.length; j++) p[j] = x[j];
            f = fv;
        }

        private static double[] arr (Gee.ArrayList<double?> p) {
            var a = new double[p.size];
            for (int i = 0; i < p.size; i++) a[i] = p[i];
            return a;
        }

        private bool finish_nonlinear (double[] x, bool[] ints, bool[] bins, out string message) {
            assign (x);
            double v = violation ();
            if (v > 1e-6) {
                message = _("Solver could not find a feasible solution.");
                return false;
            }
            message = _("Solver found a solution. All constraints and optimality conditions are satisfied.");
            return true;
        }

        private double[] round_ints (double[] x, bool[] ints, bool[] bins) {
            var y = project (x, bins);
            for (int j = 0; j < y.length; j++) if (ints[j]) y[j] = Math.round (y[j]);
            return y;
        }

        private double[] improve_ints (double[] x, double mu, bool[] ints, bool[] bins) {
            var best = round_ints (x, ints, bins);
            double fb = penalized (best, mu, ints, bins);
            bool improved = true;
            int rounds = 0;
            while (improved && rounds++ < 50) {
                improved = false;
                for (int j = 0; j < best.length; j++) {
                    if (!ints[j]) continue;
                    foreach (double d in new double[] { -1, 1 }) {
                        var y = best;
                        y[j] += d;
                        y = project (y, bins);
                        double fy = penalized (y, mu, ints, bins);
                        if (fy < fb - 1e-12) {
                            best = y;
                            fb = fy;
                            improved = true;
                        }
                    }
                }
            }
            return best;
        }

        private bool solve_nonlinear (double[] start, bool[] ints, bool[] bins, out double[] x, out string message) {
            int n = start.length;
            double[] best = start;
            double best_f = double.INFINITY;
            int starts = int.max (1, multistart);
            var rng = new Rand.with_seed (12345);
            for (int s = 0; s < starts; s++) {
                var x0 = new double[n];
                for (int j = 0; j < n; j++) {
                    if (s == 0) x0[j] = start[j];
                    else x0[j] = start[j] + rng.double_range (-1, 1) * double.max (10, Math.fabs (start[j]) * 2);
                }
                double mu = 10;
                var cur = x0;
                for (int outer = 0; outer < 8; outer++) {
                    cur = local_min (cur, mu, ints, bins, int.min (max_iterations, 200));
                    cur = nelder_mead (cur, mu, ints, bins, int.min (max_iterations, 400));
                    assign (cur);
                    if (violation () < 1e-9) break;
                    mu *= 10;
                }
                bool has_int = false;
                foreach (bool f in ints) if (f) has_int = true;
                if (has_int) cur = improve_ints (cur, mu, ints, bins);
                double f = penalized (cur, 1e6, ints, bins);
                if (f < best_f) {
                    best_f = f;
                    best = cur;
                }
            }
            x = best;
            return finish_nonlinear (best, ints, bins, out message);
        }

        private bool solve_search (double[] start, bool[] ints, bool[] bins, Gee.ArrayList<Gee.ArrayList<int>> difs, out double[] x, out string message) {
            int n = start.length;
            var rng = new Rand.with_seed (4242);
            var in_dif = new bool[n];
            foreach (var g in difs) foreach (int i in g) in_dif[i] = true;
            double mu = 1e4;
            double[] best = null;
            double best_f = double.INFINITY;
            int restarts = int.max (4, multistart);
            for (int s = 0; s < restarts; s++) {
                var cur = new double[n];
                for (int j = 0; j < n; j++) cur[j] = s == 0 ? start[j] : start[j] + rng.double_range (-1, 1) * double.max (10, Math.fabs (start[j]));
                foreach (var g in difs) {
                    var perm = new int[g.size];
                    for (int i = 0; i < g.size; i++) perm[i] = i + 1;
                    if (s > 0) for (int i = g.size - 1; i > 0; i--) {
                        int k = rng.int_range (0, i + 1);
                        int t = perm[i]; perm[i] = perm[k]; perm[k] = t;
                    }
                    for (int i = 0; i < g.size; i++) cur[g[i]] = perm[i];
                }
                cur = round_ints (cur, ints, bins);
                double fc = penalized (cur, mu, ints, bins);
                bool improved = true;
                int guard = 0;
                while (improved && guard++ < 200) {
                    improved = false;
                    foreach (var g in difs) {
                        for (int a = 0; a < g.size; a++) for (int b = a + 1; b < g.size; b++) {
                            var y = cur;
                            double t = y[g[a]]; y[g[a]] = y[g[b]]; y[g[b]] = t;
                            double fy = penalized (y, mu, ints, bins);
                            if (fy < fc - 1e-12) {
                                cur = y;
                                fc = fy;
                                improved = true;
                            }
                        }
                    }
                    for (int j = 0; j < n; j++) {
                        if (in_dif[j]) continue;
                        double step = ints[j] ? 1 : double.max (0.01, Math.fabs (cur[j]) * 0.1);
                        foreach (double d in new double[] { -step, step }) {
                            var y = cur;
                            y[j] += d;
                            y = project (y, bins);
                            double fy = penalized (y, mu, ints, bins);
                            if (fy < fc - 1e-12) {
                                cur = y;
                                fc = fy;
                                improved = true;
                            }
                        }
                    }
                }
                if (fc < best_f) {
                    best_f = fc;
                    best = cur;
                }
            }
            x = best;
            return finish_nonlinear (best, ints, bins, out message);
        }

        public Sheet answer_report (Workbook b, SolverResult r) {
            book = b;
            var vars_l = cells_of (variables);
            var rep = book.add_sheet (book.unique_sheet_name (_("Answer Report")));
            int row = 0;
            rep.set_input (row++, 0, _("Answer Report"));
            rep.set_input (row++, 0, r.message);
            row++;
            rep.set_input (row++, 0, _("Objective Cell (%s)").printf (goal == SolverGoal.MAX ? _("Max") : goal == SolverGoal.MIN ? _("Min") : _("Value Of")));
            rep.set_input (row, 0, _("Cell"));
            rep.set_input (row, 1, _("Original Value"));
            rep.set_input (row++, 2, _("Final Value"));
            rep.set_input (row, 0, objective);
            WhatIf.put_value (book, rep, row, 1, Value.num (r.original_objective));
            WhatIf.put_value (book, rep, row++, 2, Value.num (r.objective));
            row++;
            rep.set_input (row++, 0, _("Variable Cells"));
            rep.set_input (row, 0, _("Cell"));
            rep.set_input (row, 1, _("Original Value"));
            rep.set_input (row++, 2, _("Final Value"));
            for (int i = 0; i < vars_l.size; i++) {
                rep.set_input (row, 0, vars_l[i].label (sheet));
                WhatIf.put_value (book, rep, row, 1, Value.num (i < r.original.length ? r.original[i] : 0));
                WhatIf.put_value (book, rep, row++, 2, vars_l[i].value ());
            }
            row++;
            rep.set_input (row++, 0, _("Constraints"));
            rep.set_input (row, 0, _("Constraint"));
            rep.set_input (row, 1, _("Cell Value"));
            rep.set_input (row, 2, _("Status"));
            rep.set_input (row++, 3, _("Slack"));
            foreach (var c in constraints) {
                bool ok;
                var lhs = values_of (c.lhs, out ok);
                var rhs = values_of (c.rhs, out ok);
                rep.set_input (row, 0, "%s %s %s".printf (c.lhs, c.op.symbol (), c.op == ConstraintOp.INT || c.op == ConstraintOp.BIN || c.op == ConstraintOp.DIF ? "" : c.rhs).strip ());
                if (lhs.length == 1) WhatIf.put_value (book, rep, row, 1, Value.num (lhs[0]));
                if (c.op != ConstraintOp.INT && c.op != ConstraintOp.BIN && c.op != ConstraintOp.DIF && lhs.length >= 1) {
                    double slack = Math.fabs (lhs[0] - rhs[0]);
                    rep.set_input (row, 2, slack < 1e-7 ? _("Binding") : _("Not Binding"));
                    WhatIf.put_value (book, rep, row, 3, Value.num (slack < 1e-9 ? 0 : slack));
                } else {
                    rep.set_input (row, 2, _("Binding"));
                }
                row++;
            }
            book.recalculate ();
            return rep;
        }

        public void to_names () {
            var n = sheet.names;
            n["solver_opt"] = objective;
            n["solver_typ"] = goal == SolverGoal.MAX ? "1" : goal == SolverGoal.MIN ? "2" : "3";
            n["solver_val"] = Value.format_number_general_full (target);
            n["solver_adj"] = variables;
            n["solver_neg"] = nonneg ? "1" : "2";
            n["solver_eng"] = method == SolverMethod.SIMPLEX ? "2" : method == SolverMethod.NONLINEAR ? "1" : "3";
            n["solver_num"] = constraints.size.to_string ();
            for (int i = 0; i < constraints.size; i++) {
                n["solver_lhs%d".printf (i + 1)] = constraints[i].lhs;
                n["solver_rel%d".printf (i + 1)] = constraints[i].op.excel_code ().to_string ();
                n["solver_rhs%d".printf (i + 1)] = constraints[i].op == ConstraintOp.INT ? "integer" : constraints[i].op == ConstraintOp.BIN ? "binary" : constraints[i].op == ConstraintOp.DIF ? "AllDifferent" : constraints[i].rhs;
            }
            n["solver_ver"] = "3";
        }

        private static string strip_eq (string s) {
            string t = s.strip ();
            return t.has_prefix ("=") ? t.substring (1) : t;
        }

        public static SolverModel? from_names (Sheet sheet) {
            var n = sheet.names;
            if (!n.has_key ("solver_opt") && !n.has_key ("solver_adj")) return null;
            var m = new SolverModel (sheet);
            m.objective = strip_eq (n["solver_opt"] ?? "");
            string typ = strip_eq (n["solver_typ"] ?? "1");
            m.goal = typ == "2" ? SolverGoal.MIN : typ == "3" ? SolverGoal.VALUE : SolverGoal.MAX;
            m.target = double.parse (strip_eq (n["solver_val"] ?? "0"));
            m.variables = strip_eq (n["solver_adj"] ?? "");
            m.nonneg = strip_eq (n["solver_neg"] ?? "1") != "2";
            string eng = strip_eq (n["solver_eng"] ?? "2");
            m.method = eng == "1" ? SolverMethod.NONLINEAR : eng == "3" ? SolverMethod.EVOLUTIONARY : SolverMethod.SIMPLEX;
            int count = int.parse (strip_eq (n["solver_num"] ?? "0"));
            for (int i = 1; i <= count; i++) {
                var op = ConstraintOp.from_excel (int.parse (strip_eq (n["solver_rel%d".printf (i)] ?? "1")));
                m.constraints.add (new SolverConstraint (strip_eq (n["solver_lhs%d".printf (i)] ?? ""), op, strip_eq (n["solver_rhs%d".printf (i)] ?? "0")));
            }
            return m;
        }
    }

    public class LpRow {
        public double[] a;
        public ConstraintOp op;
        public double b;
    }

    public class Simplex {
        public static int solve (double[] c, Gee.List<LpRow> rows_in, bool free_vars, out double[] x, out double value) {
            int n0 = c.length;
            int n = free_vars ? n0 * 2 : n0;
            int m = rows_in.size;
            var A = new double[m, n];
            var b = new double[m];
            var ops = new int[m];
            int idx = 0;
            foreach (var r in rows_in) {
                for (int j = 0; j < n0; j++) {
                    A[idx, j] = r.a[j];
                    if (free_vars) A[idx, n0 + j] = -r.a[j];
                }
                b[idx] = r.b;
                ops[idx] = r.op == ConstraintOp.LE ? 0 : r.op == ConstraintOp.GE ? 1 : 2;
                if (b[idx] < 0) {
                    for (int j = 0; j < n; j++) A[idx, j] = -A[idx, j];
                    b[idx] = -b[idx];
                    if (ops[idx] == 0) ops[idx] = 1;
                    else if (ops[idx] == 1) ops[idx] = 0;
                }
                idx++;
            }
            int slack = 0, art = 0;
            for (int i = 0; i < m; i++) {
                if (ops[i] != 2) slack++;
                if (ops[i] != 0) art++;
            }
            int total = n + slack + art;
            var T = new double[m + 1, total + 1];
            var basis = new int[m];
            int sc = n, ac = n + slack;
            var is_art = new bool[total];
            for (int i = 0; i < m; i++) {
                for (int j = 0; j < n; j++) T[i, j] = A[i, j];
                T[i, total] = b[i];
                if (ops[i] == 0) {
                    T[i, sc] = 1;
                    basis[i] = sc;
                    sc++;
                } else if (ops[i] == 1) {
                    T[i, sc] = -1;
                    sc++;
                    T[i, ac] = 1;
                    is_art[ac] = true;
                    basis[i] = ac;
                    ac++;
                } else {
                    T[i, ac] = 1;
                    is_art[ac] = true;
                    basis[i] = ac;
                    ac++;
                }
            }
            x = new double[n0];
            value = 0;
            if (art > 0) {
                for (int j = 0; j <= total; j++) T[m, j] = 0;
                for (int i = 0; i < m; i++) {
                    if (!is_art[basis[i]]) continue;
                    for (int j = 0; j <= total; j++) T[m, j] -= T[i, j];
                }
                for (int j = 0; j < total; j++) if (is_art[j]) T[m, j] = 0;
                if (!pivot_loop (T, basis, m, total, null)) return 2;
                if (-T[m, total] > 1e-7 * (1 + Math.fabs (T[m, total]))) return 1;
                for (int i = 0; i < m; i++) {
                    if (!is_art[basis[i]]) continue;
                    for (int j = 0; j < total; j++) {
                        if (!is_art[j] && Math.fabs (T[i, j]) > 1e-9) {
                            do_pivot (T, basis, m, total, i, j);
                            break;
                        }
                    }
                }
            }
            for (int j = 0; j <= total; j++) T[m, j] = 0;
            for (int j = 0; j < n; j++) T[m, j] = -(free_vars ? (j < n0 ? c[j] : -c[j - n0]) : c[j]);
            for (int i = 0; i < m; i++) {
                double coef = T[m, basis[i]];
                if (coef == 0) continue;
                for (int j = 0; j <= total; j++) T[m, j] -= coef * T[i, j];
            }
            if (!pivot_loop (T, basis, m, total, is_art)) return 2;
            var full = new double[n];
            for (int i = 0; i < m; i++) if (basis[i] < n) full[basis[i]] = T[i, total];
            for (int j = 0; j < n0; j++) x[j] = free_vars ? full[j] - full[n0 + j] : full[j];
            value = 0;
            for (int j = 0; j < n0; j++) value += c[j] * x[j];
            return 0;
        }

        private static void do_pivot (double[,] T, int[] basis, int m, int total, int pr, int pc) {
            double p = T[pr, pc];
            for (int j = 0; j <= total; j++) T[pr, j] /= p;
            for (int i = 0; i <= m; i++) {
                if (i == pr) continue;
                double f = T[i, pc];
                if (f == 0) continue;
                for (int j = 0; j <= total; j++) T[i, j] -= f * T[pr, j];
            }
            basis[pr] = pc;
        }

        private static bool pivot_loop (double[,] T, int[] basis, int m, int total, bool[]? skip) {
            for (int iter = 0; iter < 50000; iter++) {
                int pc = -1;
                for (int j = 0; j < total; j++) {
                    if (skip != null && skip[j]) continue;
                    if (T[m, j] < -1e-9) {
                        pc = j;
                        break;
                    }
                }
                if (pc < 0) return true;
                int pr = -1;
                double best = double.INFINITY;
                for (int i = 0; i < m; i++) {
                    if (T[i, pc] > 1e-9) {
                        double ratio = T[i, total] / T[i, pc];
                        if (ratio < best - 1e-12 || (Math.fabs (ratio - best) <= 1e-12 && pr >= 0 && basis[i] < basis[pr])) {
                            best = ratio;
                            pr = i;
                        }
                    }
                }
                if (pr < 0) return false;
                do_pivot (T, basis, m, total, pr, pc);
            }
            return true;
        }
    }
}
