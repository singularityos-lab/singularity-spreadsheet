namespace Singularity.Apps.Spreadsheet {

    public class AnalysisData {
        public unowned Workbook? book;
        public Gee.ArrayList<PivotTable> pivots = new Gee.ArrayList<PivotTable> ();
        public Gee.ArrayList<Scenario> scenarios = new Gee.ArrayList<Scenario> ();
        public Gee.ArrayList<DataTableDef> data_tables = new Gee.ArrayList<DataTableDef> ();
        public Gee.ArrayList<QueryDef> queries = new Gee.ArrayList<QueryDef> ();
        public Gee.HashMap<string, DataTypeLink> links = new Gee.HashMap<string, DataTypeLink> ();
        public Gee.HashMap<string, LinkedRecord> records = new Gee.HashMap<string, LinkedRecord> ();
        public Gee.HashSet<string> loading = new Gee.HashSet<string> ();
        public Gee.HashMap<string, string> failures = new Gee.HashMap<string, string> ();
        public Gee.HashMap<string, Gee.List<Gee.List<string>>> histories = new Gee.HashMap<string, Gee.List<Gee.List<string>>> ();
        public Gee.HashMap<string, string> history_errors = new Gee.HashMap<string, string> ();
        private bool hooked;
        private bool busy;

        public bool is_empty () {
            return pivots.size == 0 && scenarios.size == 0 && data_tables.size == 0 && queries.size == 0 && links.size == 0 && records.size == 0;
        }

        public void attach (Workbook b) {
            book = b;
            if (hooked) return;
            hooked = true;
            b.recalculated.connect (() => {
                if (busy || data_tables.size == 0) return;
                busy = true;
                foreach (var dt in data_tables) {
                    if (b.sheets.contains (dt.sheet)) dt.compute (b);
                }
                busy = false;
            });
        }

        public bool computing {
            get { return busy; }
        }

        public void run_data_tables () {
            if (book == null || busy) return;
            busy = true;
            foreach (var dt in data_tables) if (book.sheets.contains (dt.sheet)) dt.compute (book);
            busy = false;
        }

        public void forget_sheet (Sheet s) {
            var keep = new Gee.ArrayList<PivotTable> ();
            foreach (var p in pivots) if (p.target_sheet != s) keep.add (p);
            pivots = keep;
            var dts = new Gee.ArrayList<DataTableDef> ();
            foreach (var d in data_tables) if (d.sheet != s) dts.add (d);
            data_tables = dts;
        }

        public PivotTable? pivot_at (Sheet s, int r, int c) {
            foreach (var p in pivots) {
                if (p.target_sheet != s) continue;
                if (p.last_output != null && p.last_output.contains (r, c)) return p;
                if (p.target_row == r && p.target_col == c) return p;
            }
            return null;
        }

        public string unique_pivot_name () {
            for (int i = 1; ; i++) {
                string n = "PivotTable%d".printf (i);
                bool used = false;
                foreach (var p in pivots) if (p.name == n) used = true;
                if (!used) return n;
            }
        }
    }

    public class Analysis {
        public static AnalysisData data (Workbook book) {
            book.analysis.attach (book);
            return book.analysis;
        }

        public static string area_ref (Area a, Sheet? own = null) {
            string prefix = a.sheet != null && a.sheet != own ? Address.quote_sheet (a.sheet.name) + "!" : "";
            if (a.is_single ()) return prefix + Address.cell (a.r1, a.c1, true, true);
            return prefix + Address.cell (a.r1, a.c1, true, true) + ":" + Address.cell (a.r2, a.c2, true, true);
        }

        public static Area? parse_area (Workbook book, string text, Sheet own) {
            string t = text.strip ();
            if (t.has_prefix ("=")) t = t.substring (1);
            Sheet s = own;
            int bang = t.last_index_of ("!");
            if (bang > 0) {
                string sn = t.substring (0, bang);
                if (sn.has_prefix ("'")) sn = sn.substring (1, sn.length - 2).replace ("''", "'");
                var fs = book.find_sheet (sn);
                if (fs == null) return null;
                s = fs;
                t = t.substring (bang + 1);
            }
            var a = Area.parse (t.replace ("$", ""), s);
            if (a == null) {
                var tb = Tables.find (book, t);
                if (tb != null) return new Area (tb.sheet, tb.header_row ? tb.area.r1 : tb.data_r1, tb.area.c1, tb.data_r2, tb.area.c2);
            }
            return a;
        }

        public static void clear_area (Workbook book, Area a) {
            var s = a.sheet;
            var keys = new Gee.ArrayList<int64?> ();
            foreach (var k in s.cells.keys) {
                if (a.contains (Sheet.key_row (k), Sheet.key_col (k))) keys.add (k);
            }
            foreach (var k in keys) s.cells.unset (k);
            s.recompute_extent ();
            book.structure_changed = true;
        }

        private static int styled (Workbook book, int base_style, bool bold, string fmt, string fill = "") {
            var st = book.styles[base_style].copy ();
            if (bold) st.bold = true;
            if (fmt != "") st.number_format = fmt;
            if (fill != "") st.fill = fill;
            return book.intern (st);
        }

        public static Area? write_pivot (Workbook book, PivotTable p) {
            var outp = p.compute (book);
            if (outp == null) return null;
            if (p.last_output != null && p.last_output.sheet == p.target_sheet) clear_area (book, p.last_output);
            var s = p.target_sheet;
            int rows = outp.cells.length[0], cols = outp.cells.length[1];
            int head = styled (book, 0, true, "", "#dde7f3");
            int total = styled (book, 0, true, "", "#eef3f9");
            for (int i = 0; i < rows; i++) {
                for (int j = 0; j < cols; j++) {
                    var v = outp.cells[i, j];
                    int r = p.target_row + i, c = p.target_col + j;
                    if (r >= MAX_ROWS || c >= MAX_COLS) continue;
                    WhatIf.put_value (book, s, r, c, v);
                    string fmt = outp.col_formats.has_key (j) && i >= outp.header_rows ? outp.col_formats[j] : "";
                    int st = 0;
                    if (i < outp.header_rows) st = head;
                    else if (outp.total_rows.contains (i)) st = styled (book, 0, true, fmt, "#eef3f9");
                    else if (fmt != "") st = styled (book, 0, false, fmt);
                    if (i >= outp.header_rows && outp.total_cols.contains (j) && st == 0) st = styled (book, 0, true, fmt);
                    if (st != 0 || s.get_cell (r, c) != null) s.set_style (r, c, st);
                }
            }
            p.last_output = new Area (s, p.target_row, p.target_col, int.min (p.target_row + rows - 1, MAX_ROWS - 1), int.min (p.target_col + cols - 1, MAX_COLS - 1));
            for (int j = 0; j < cols; j++) {
                int c = p.target_col + j;
                if (!s.col_widths.has_key (c)) s.col_widths[c] = j < outp.label_cols ? 130 : 110;
            }
            book.structure_changed = true;
            book.recalculate ();
            return p.last_output;
        }

        public static void refresh_all (Workbook book) {
            foreach (var p in data (book).pivots) write_pivot (book, p);
        }

        public static Chart? pivot_chart (Workbook book, PivotTable p, string kind = "column") {
            if (p.last_output == null) return null;
            int header_rows = p.cols.size == 0 ? 1 : p.cols.size + 1 + (p.values.size > 1 ? 1 : 0);
            int r1 = p.last_output.r1 + header_rows - 1;
            int r2 = p.last_output.r2;
            if (p.row_grand && p.rows.size > 0) r2--;
            int c2 = p.last_output.c2;
            if (p.col_grand && p.cols.size > 0) c2 -= int.max (p.values.size, 1);
            if (r2 <= r1 || c2 < p.last_output.c1 + 1) return null;
            int c1 = p.last_output.c1 + int.max (p.rows.size, 1) - 1;
            var ch = new Chart (new Area (p.target_sheet, r1, c1, r2, c2));
            ch.kind = kind;
            ch.title = p.values.size > 0 ? p.values[0].caption () : p.name;
            ch.first_row_labels = true;
            ch.first_col_labels = true;
            ch.x = 60 + (c2 + 2) * 20;
            ch.y = 40;
            p.target_sheet.charts.add (ch);
            return ch;
        }

        public static Area? load_query (Workbook book, QueryDef q) throws Error {
            var df = QueryEngine.run (book, q);
            q.error = "";
            q.last_refresh = new DateTime.now_local ().format ("%Y-%m-%d %H:%M");
            if (!q.load) return null;
            var s = book.find_sheet (q.dest_sheet);
            if (s == null) {
                s = book.add_sheet (book.unique_sheet_name (q.name.length > 0 && q.name.length < 28 ? q.name : _("Query")));
                q.dest_sheet = s.name;
                q.dest_row = 0;
                q.dest_col = 0;
            }
            TableDef? old_table = q.table_name != "" ? Tables.find (book, q.table_name) : null;
            if (q.last_area != null && q.last_area.sheet == s) clear_area (book, q.last_area);
            var m = df.to_matrix (true);
            int rows = m.length[0], cols = m.length[1];
            int head = styled (book, 0, true, "");
            for (int i = 0; i < rows; i++) {
                for (int j = 0; j < cols; j++) {
                    WhatIf.put_value (book, s, q.dest_row + i, q.dest_col + j, m[i, j]);
                    if (i == 0) s.set_style (q.dest_row, q.dest_col + j, head);
                    else if (m[i, j].kind == ValueKind.NUMBER && s.style_at (q.dest_row + i, q.dest_col + j).number_format == "General") {
                        double d = m[i, j].number;
                        if (d != Math.floor (d)) continue;
                    }
                }
            }
            q.last_area = new Area (s, q.dest_row, q.dest_col, q.dest_row + int.max (rows - 1, 1), q.dest_col + cols - 1);
            if (q.as_table) {
                if (old_table != null) {
                    old_table.area = q.last_area.copy ();
                    old_table.sync_columns ();
                } else {
                    string tn = Tables.unique_name (book, "Query_");
                    var t = new TableDef (tn, s, q.last_area.copy ());
                    t.sync_columns ();
                    book.tables.add (t);
                    q.table_name = tn;
                }
            }
            book.structure_changed = true;
            book.recalculate ();
            return q.last_area;
        }

        public static int refresh_queries (Workbook book, out string errors) {
            int ok = 0;
            var sb = new StringBuilder ();
            foreach (var q in data (book).queries) {
                if (!q.load) continue;
                try {
                    load_query (book, q);
                    ok++;
                } catch (Error e) {
                    q.error = e.message;
                    sb.append ("%s: %s\n".printf (q.name, e.message));
                }
            }
            errors = sb.str.strip ();
            return ok;
        }

        private static double[] column_numbers (Sheet s, int c, int r1, int r2) {
            double[] out_v = {};
            for (int r = r1; r <= r2; r++) {
                var v = s.value_at (r, c);
                if (v.kind == ValueKind.NUMBER) out_v += v.number;
            }
            return out_v;
        }

        public static double[] sort_copy (double[] x) {
            var list = new Gee.ArrayList<double?> ();
            foreach (double d in x) list.add (d);
            list.sort ((a, b) => {
                double p = a, q = b;
                return p < q ? -1 : (p > q ? 1 : 0);
            });
            var out_v = new double[x.length];
            for (int i = 0; i < x.length; i++) out_v[i] = list[i];
            return out_v;
        }

        private static double mean (double[] x) {
            double s = 0;
            foreach (double d in x) s += d;
            return x.length > 0 ? s / x.length : 0;
        }

        private static double variance (double[] x) {
            if (x.length < 2) return double.NAN;
            double m = mean (x), s = 0;
            foreach (double d in x) s += (d - m) * (d - m);
            return s / (x.length - 1);
        }

        private static void write_table (Workbook book, Sheet s, int r, int c, string[] labels, Value[,] values) {
            for (int i = 0; i < values.length[0]; i++) {
                if (i < labels.length) WhatIf.put_value (book, s, r + i, c, Value.str (labels[i]));
                for (int j = 0; j < values.length[1]; j++) WhatIf.put_value (book, s, r + i, c + 1 + j, values[i, j]);
            }
        }

        private static Sheet output_sheet (Workbook book, string name) {
            return book.add_sheet (book.unique_sheet_name (name));
        }

        private static Value n (double d) {
            if (d.is_nan () || d.is_infinity () != 0) return Value.err (ErrorKind.DIV0);
            return Value.num (d);
        }

        public static Sheet descriptive (Workbook book, Area input, bool labels) {
            var s = input.sheet;
            var out_s = output_sheet (book, _("Descriptive Statistics"));
            int head = styled (book, 0, true, "");
            string[] names = { _("Mean"), _("Standard Error"), _("Median"), _("Mode"), _("Standard Deviation"), _("Sample Variance"), _("Kurtosis"), _("Skewness"), _("Range"), _("Minimum"), _("Maximum"), _("Sum"), _("Count") };
            int r1 = labels ? input.r1 + 1 : input.r1;
            int r2 = int.min (input.r2, s.max_row);
            for (int c = input.c1; c <= int.min (input.c2, s.max_col); c++) {
                int oc = (c - input.c1) * 2;
                string title = labels ? s.value_at (input.r1, c).display () : _("Column %d").printf (c - input.c1 + 1);
                WhatIf.put_value (book, out_s, 0, oc, Value.str (title));
                out_s.set_style (0, oc, head);
                var x = column_numbers (s, c, r1, r2);
                var sorted = sort_copy (x);
                int cnt = x.length;
                double m = mean (x);
                double v = variance (x);
                double sd = Math.sqrt (v);
                double med = cnt == 0 ? double.NAN : (cnt % 2 == 1 ? sorted[cnt / 2] : (sorted[cnt / 2 - 1] + sorted[cnt / 2]) / 2);
                double mode = double.NAN;
                int best = 1;
                for (int i = 0; i < cnt; ) {
                    int j = i;
                    while (j < cnt && sorted[j] == sorted[i]) j++;
                    if (j - i > best) {
                        best = j - i;
                        mode = sorted[i];
                    }
                    i = j;
                }
                double m3 = 0, m4 = 0;
                foreach (double d in x) {
                    double z = (d - m) / sd;
                    m3 += z * z * z;
                    m4 += z * z * z * z;
                }
                double nn = cnt;
                double skew = cnt > 2 ? nn / ((nn - 1) * (nn - 2)) * m3 : double.NAN;
                double kurt = cnt > 3 ? nn * (nn + 1) / ((nn - 1) * (nn - 2) * (nn - 3)) * m4 - 3 * (nn - 1) * (nn - 1) / ((nn - 2) * (nn - 3)) : double.NAN;
                double sum = 0;
                foreach (double d in x) sum += d;
                Value[] vals = { n (m), n (sd / Math.sqrt (nn)), n (med), mode.is_nan () ? Value.err (ErrorKind.NA) : Value.num (mode), n (sd), n (v), n (kurt), n (skew),
                    n (cnt > 0 ? sorted[cnt - 1] - sorted[0] : double.NAN), n (cnt > 0 ? sorted[0] : double.NAN), n (cnt > 0 ? sorted[cnt - 1] : double.NAN), Value.num (sum), Value.num (cnt) };
                for (int i = 0; i < names.length; i++) {
                    WhatIf.put_value (book, out_s, 2 + i, oc, Value.str (names[i]));
                    WhatIf.put_value (book, out_s, 2 + i, oc + 1, vals[i]);
                }
                out_s.col_widths[oc] = 150;
            }
            book.recalculate ();
            return out_s;
        }

        public static Sheet histogram (Workbook book, Area input, Area? bins, bool labels, bool chart) {
            var s = input.sheet;
            var out_s = output_sheet (book, _("Histogram"));
            double[] x = {};
            for (int c = input.c1; c <= int.min (input.c2, s.max_col); c++) {
                foreach (double d in column_numbers (s, c, labels ? input.r1 + 1 : input.r1, int.min (input.r2, s.max_row))) x += d;
            }
            double[] edges = {};
            if (bins != null) {
                for (int r = bins.r1; r <= int.min (bins.r2, bins.sheet.max_row); r++) {
                    var v = bins.sheet.value_at (r, bins.c1);
                    if (v.kind == ValueKind.NUMBER) edges += v.number;
                }
            }
            if (edges.length == 0 && x.length > 0) {
                double lo = x[0], hi = x[0];
                foreach (double d in x) {
                    lo = double.min (lo, d);
                    hi = double.max (hi, d);
                }
                int k = int.max (1, (int) Math.ceil (Math.sqrt (x.length)));
                double w = (hi - lo) / k;
                for (int i = 0; i <= k; i++) edges += lo + w * i;
            }
            WhatIf.put_value (book, out_s, 0, 0, Value.str (_("Bin")));
            WhatIf.put_value (book, out_s, 0, 1, Value.str (_("Frequency")));
            int head = styled (book, 0, true, "");
            out_s.set_style (0, 0, head);
            out_s.set_style (0, 1, head);
            var counts = new int[edges.length + 1];
            foreach (double d in x) {
                int b = edges.length;
                for (int i = 0; i < edges.length; i++) if (d <= edges[i]) {
                    b = i;
                    break;
                }
                counts[b]++;
            }
            for (int i = 0; i < edges.length; i++) {
                WhatIf.put_value (book, out_s, 1 + i, 0, Value.num (edges[i]));
                WhatIf.put_value (book, out_s, 1 + i, 1, Value.num (counts[i]));
            }
            WhatIf.put_value (book, out_s, 1 + edges.length, 0, Value.str (_("More")));
            WhatIf.put_value (book, out_s, 1 + edges.length, 1, Value.num (counts[edges.length]));
            if (chart) {
                var ch = new Chart (new Area (out_s, 0, 0, 1 + edges.length, 1));
                ch.kind = "column";
                ch.title = _("Histogram");
                ch.x = 260;
                out_s.charts.add (ch);
            }
            book.recalculate ();
            return out_s;
        }

        public static Sheet matrix (Workbook book, Area input, bool labels, bool covariance) {
            var s = input.sheet;
            var out_s = output_sheet (book, covariance ? _("Covariance") : _("Correlation"));
            int nc = int.min (input.c2, s.max_col) - input.c1 + 1;
            var cols = new Gee.ArrayList<Gee.ArrayList<double?>> ();
            int r1 = labels ? input.r1 + 1 : input.r1;
            int r2 = int.min (input.r2, s.max_row);
            string[] names = {};
            for (int j = 0; j < nc; j++) {
                names += labels ? s.value_at (input.r1, input.c1 + j).display () : _("Column %d").printf (j + 1);
                var col = new Gee.ArrayList<double?> ();
                for (int r = r1; r <= r2; r++) {
                    var v = s.value_at (r, input.c1 + j);
                    col.add (v.kind == ValueKind.NUMBER ? v.number : double.NAN);
                }
                cols.add (col);
            }
            int head = styled (book, 0, true, "");
            for (int j = 0; j < nc; j++) {
                WhatIf.put_value (book, out_s, 0, 1 + j, Value.str (names[j]));
                out_s.set_style (0, 1 + j, head);
                WhatIf.put_value (book, out_s, 1 + j, 0, Value.str (names[j]));
                out_s.set_style (1 + j, 0, head);
            }
            for (int i = 0; i < nc; i++) {
                for (int j = 0; j <= i; j++) {
                    double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
                    int cnt = 0;
                    for (int k = 0; k < cols[i].size; k++) {
                        double a = cols[i][k], b = cols[j][k];
                        if (a.is_nan () || b.is_nan ()) continue;
                        cnt++;
                        sx += a; sy += b; sxx += a * a; syy += b * b; sxy += a * b;
                    }
                    double cov = (sxy - sx * sy / cnt) / cnt;
                    double val = covariance ? cov : cov / Math.sqrt ((sxx - sx * sx / cnt) / cnt * ((syy - sy * sy / cnt) / cnt));
                    WhatIf.put_value (book, out_s, 1 + i, 1 + j, n (val));
                }
            }
            book.recalculate ();
            return out_s;
        }

        public static double ln_gamma (double x) {
            double[] g = { 76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5 };
            double y = x, tmp = x + 5.5;
            tmp -= (x + 0.5) * Math.log (tmp);
            double ser = 1.000000000190015;
            for (int j = 0; j < 6; j++) {
                y += 1;
                ser += g[j] / y;
            }
            return -tmp + Math.log (2.5066282746310005 * ser / x);
        }

        private static double beta_cf (double a, double b, double x) {
            double qab = a + b, qap = a + 1, qam = a - 1, c = 1, d = 1 - qab * x / qap;
            if (Math.fabs (d) < 1e-30) d = 1e-30;
            d = 1 / d;
            double h = d;
            for (int m = 1; m <= 300; m++) {
                int m2 = 2 * m;
                double aa = m * (b - m) * x / ((qam + m2) * (a + m2));
                d = 1 + aa * d;
                if (Math.fabs (d) < 1e-30) d = 1e-30;
                c = 1 + aa / c;
                if (Math.fabs (c) < 1e-30) c = 1e-30;
                d = 1 / d;
                h *= d * c;
                aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
                d = 1 + aa * d;
                if (Math.fabs (d) < 1e-30) d = 1e-30;
                c = 1 + aa / c;
                if (Math.fabs (c) < 1e-30) c = 1e-30;
                d = 1 / d;
                double del = d * c;
                h *= del;
                if (Math.fabs (del - 1) < 3e-14) break;
            }
            return h;
        }

        public static double inc_beta (double a, double b, double x) {
            if (x <= 0) return 0;
            if (x >= 1) return 1;
            double bt = Math.exp (ln_gamma (a + b) - ln_gamma (a) - ln_gamma (b) + a * Math.log (x) + b * Math.log (1 - x));
            if (x < (a + 1) / (a + b + 2)) return bt * beta_cf (a, b, x) / a;
            return 1 - bt * beta_cf (b, a, 1 - x) / b;
        }

        public static double t_two_tail (double t, double df) {
            return inc_beta (df / 2, 0.5, df / (df + t * t));
        }

        public static double f_upper (double f, double d1, double d2) {
            if (f <= 0) return 1;
            return inc_beta (d2 / 2, d1 / 2, d2 / (d2 + d1 * f));
        }

        public static double t_inv_two (double p, double df) {
            double lo = 0, hi = 1000;
            for (int i = 0; i < 200; i++) {
                double mid = (lo + hi) / 2;
                if (t_two_tail (mid, df) > p) lo = mid;
                else hi = mid;
            }
            return (lo + hi) / 2;
        }

        public static double[]? least_squares (double[,] X, double[] y, out double[,] inv) {
            int nr = X.length[0], k = X.length[1];
            var A = new double[k, 2 * k];
            for (int i = 0; i < k; i++) {
                for (int j = 0; j < k; j++) {
                    double s = 0;
                    for (int r = 0; r < nr; r++) s += X[r, i] * X[r, j];
                    A[i, j] = s;
                }
                A[i, k + i] = 1;
            }
            inv = new double[k, k];
            for (int c = 0; c < k; c++) {
                int piv = c;
                for (int r = c + 1; r < k; r++) if (Math.fabs (A[r, c]) > Math.fabs (A[piv, c])) piv = r;
                if (Math.fabs (A[piv, c]) < 1e-12) return null;
                for (int j = 0; j < 2 * k; j++) {
                    double t = A[c, j]; A[c, j] = A[piv, j]; A[piv, j] = t;
                }
                double p = A[c, c];
                for (int j = 0; j < 2 * k; j++) A[c, j] /= p;
                for (int r = 0; r < k; r++) {
                    if (r == c) continue;
                    double f = A[r, c];
                    for (int j = 0; j < 2 * k; j++) A[r, j] -= f * A[c, j];
                }
            }
            for (int i = 0; i < k; i++) for (int j = 0; j < k; j++) inv[i, j] = A[i, k + j];
            var beta = new double[k];
            for (int i = 0; i < k; i++) {
                double s = 0;
                for (int j = 0; j < k; j++) {
                    double xty = 0;
                    for (int r = 0; r < nr; r++) xty += X[r, j] * y[r];
                    s += inv[i, j] * xty;
                }
                beta[i] = s;
            }
            return beta;
        }

        public static Sheet regression (Workbook book, Area yr, Area xr, bool labels, double confidence = 0.95) {
            var out_s = output_sheet (book, _("Regression"));
            int r1 = labels ? yr.r1 + 1 : yr.r1;
            int count = int.min (yr.r2, yr.sheet.max_row) - r1 + 1;
            int k = xr.cols + 1;
            var rows_y = new Gee.ArrayList<double?> ();
            var rows_x = new Gee.ArrayList<Gee.ArrayList<double?>> ();
            for (int i = 0; i < count; i++) {
                var yv = yr.sheet.value_at (r1 + i, yr.c1);
                if (yv.kind != ValueKind.NUMBER) continue;
                var xs = new Gee.ArrayList<double?> ();
                bool ok = true;
                for (int j = 0; j < xr.cols; j++) {
                    var xv = xr.sheet.value_at ((labels ? xr.r1 + 1 : xr.r1) + i, xr.c1 + j);
                    if (xv.kind != ValueKind.NUMBER) ok = false;
                    xs.add (xv.number);
                }
                if (!ok) continue;
                rows_y.add (yv.number);
                rows_x.add (xs);
            }
            int nobs = rows_y.size;
            var X = new double[nobs, k];
            var y = new double[nobs];
            for (int i = 0; i < nobs; i++) {
                X[i, 0] = 1;
                for (int j = 1; j < k; j++) X[i, j] = rows_x[i][j - 1];
                y[i] = rows_y[i];
            }
            double[,] inv;
            var beta = least_squares (X, y, out inv);
            int head = styled (book, 0, true, "");
            WhatIf.put_value (book, out_s, 0, 0, Value.str (_("Summary Output")));
            out_s.set_style (0, 0, head);
            if (beta == null || nobs <= k) {
                WhatIf.put_value (book, out_s, 1, 0, Value.str (_("The data does not allow a regression.")));
                book.recalculate ();
                return out_s;
            }
            double ym = 0;
            foreach (double d in y) ym += d;
            ym /= nobs;
            double sst = 0, sse = 0;
            for (int i = 0; i < nobs; i++) {
                double f = 0;
                for (int j = 0; j < k; j++) f += beta[j] * X[i, j];
                sse += (y[i] - f) * (y[i] - f);
                sst += (y[i] - ym) * (y[i] - ym);
            }
            double ssr = sst - sse;
            int dfr = k - 1, dfe = nobs - k;
            double r2 = sst == 0 ? 1 : ssr / sst;
            double mse = sse / dfe;
            double se = Math.sqrt (mse);
            double fstat = dfr > 0 ? (ssr / dfr) / mse : double.NAN;
            string[] stat_labels = { _("Multiple R"), _("R Square"), _("Adjusted R Square"), _("Standard Error"), _("Observations") };
            var sv = new Value[5, 1];
            sv[0, 0] = n (Math.sqrt (r2));
            sv[1, 0] = n (r2);
            sv[2, 0] = n (1 - (1 - r2) * (nobs - 1) / dfe);
            sv[3, 0] = n (se);
            sv[4, 0] = Value.num (nobs);
            WhatIf.put_value (book, out_s, 2, 0, Value.str (_("Regression Statistics")));
            out_s.set_style (2, 0, head);
            write_table (book, out_s, 3, 0, stat_labels, sv);
            int ar = 10;
            WhatIf.put_value (book, out_s, ar - 1, 0, Value.str (_("ANOVA")));
            out_s.set_style (ar - 1, 0, head);
            string[] ah = { "", "df", "SS", "MS", "F", _("Significance F") };
            for (int j = 0; j < ah.length; j++) WhatIf.put_value (book, out_s, ar, j, Value.str (ah[j]));
            var av = new Value[3, 5];
            av[0, 0] = Value.num (dfr); av[0, 1] = n (ssr); av[0, 2] = n (dfr > 0 ? ssr / dfr : double.NAN); av[0, 3] = n (fstat); av[0, 4] = n (f_upper (fstat, dfr, dfe));
            av[1, 0] = Value.num (dfe); av[1, 1] = n (sse); av[1, 2] = n (mse); av[1, 3] = Value.empty (); av[1, 4] = Value.empty ();
            av[2, 0] = Value.num (nobs - 1); av[2, 1] = n (sst); av[2, 2] = Value.empty (); av[2, 3] = Value.empty (); av[2, 4] = Value.empty ();
            write_table (book, out_s, ar + 1, 0, { _("Regression"), _("Residual"), _("Total") }, av);
            int cr = ar + 5;
            string conf = Value.format_number_general (confidence * 100) + "%";
            string[] ch = { "", _("Coefficients"), _("Standard Error"), _("t Stat"), _("P-value"), _("Lower %s").printf (conf), _("Upper %s").printf (conf) };
            for (int j = 0; j < ch.length; j++) WhatIf.put_value (book, out_s, cr, j, Value.str (ch[j]));
            double tc = t_inv_two (1 - confidence, dfe);
            string[] names = { _("Intercept") };
            for (int j = 1; j < k; j++) names += labels ? xr.sheet.value_at (xr.r1, xr.c1 + j - 1).display () : _("X Variable %d").printf (j);
            var cv = new Value[k, 6];
            for (int j = 0; j < k; j++) {
                double sej = Math.sqrt (mse * inv[j, j]);
                double t = beta[j] / sej;
                cv[j, 0] = n (beta[j]);
                cv[j, 1] = n (sej);
                cv[j, 2] = n (t);
                cv[j, 3] = n (t_two_tail (Math.fabs (t), dfe));
                cv[j, 4] = n (beta[j] - tc * sej);
                cv[j, 5] = n (beta[j] + tc * sej);
            }
            write_table (book, out_s, cr + 1, 0, names, cv);
            out_s.col_widths[0] = 150;
            book.recalculate ();
            return out_s;
        }

        public static Sheet moving_average (Workbook book, Area input, int interval, bool labels) {
            var out_s = output_sheet (book, _("Moving Average"));
            var s = input.sheet;
            int r1 = labels ? input.r1 + 1 : input.r1;
            var x = new Gee.ArrayList<Value> ();
            for (int r = r1; r <= int.min (input.r2, s.max_row); r++) x.add (s.value_at (r, input.c1));
            WhatIf.put_value (book, out_s, 0, 0, Value.str (_("Input")));
            WhatIf.put_value (book, out_s, 0, 1, Value.str (_("Moving Average")));
            for (int i = 0; i < x.size; i++) {
                WhatIf.put_value (book, out_s, 1 + i, 0, x[i]);
                if (i + 1 < interval) {
                    WhatIf.put_value (book, out_s, 1 + i, 1, Value.err (ErrorKind.NA));
                    continue;
                }
                double sum = 0;
                for (int k = i - interval + 1; k <= i; k++) sum += x[k].kind == ValueKind.NUMBER ? x[k].number : 0;
                WhatIf.put_value (book, out_s, 1 + i, 1, Value.num (sum / interval));
            }
            book.recalculate ();
            return out_s;
        }

        public static Sheet sampling (Workbook book, Area input, bool periodic, int k, uint32 seed = 0) {
            var out_s = output_sheet (book, _("Sample"));
            var s = input.sheet;
            var vals = new Gee.ArrayList<Value> ();
            for (int c = input.c1; c <= int.min (input.c2, s.max_col); c++) {
                for (int r = input.r1; r <= int.min (input.r2, s.max_row); r++) {
                    var v = s.value_at (r, c);
                    if (!v.is_empty ()) vals.add (v);
                }
            }
            int row = 0;
            if (periodic) {
                for (int i = k - 1; i < vals.size; i += int.max (k, 1)) WhatIf.put_value (book, out_s, row++, 0, vals[i]);
            } else {
                var rng = new Rand ();
                if (seed != 0) rng.set_seed (seed);
                for (int i = 0; i < k && vals.size > 0; i++) WhatIf.put_value (book, out_s, row++, 0, vals[rng.int_range (0, vals.size)]);
            }
            book.recalculate ();
            return out_s;
        }

        public enum TTest {
            PAIRED,
            EQUAL,
            UNEQUAL
        }

        public static Sheet t_test (Workbook book, Area a1, Area a2, TTest kind, bool labels, double alpha = 0.05, double hyp = 0) {
            var out_s = output_sheet (book, _("t-Test"));
            int o1 = labels ? a1.r1 + 1 : a1.r1, o2 = labels ? a2.r1 + 1 : a2.r1;
            var x = column_numbers (a1.sheet, a1.c1, o1, int.min (a1.r2, a1.sheet.max_row));
            var y = column_numbers (a2.sheet, a2.c1, o2, int.min (a2.r2, a2.sheet.max_row));
            double m1 = mean (x), m2 = mean (y), v1 = variance (x), v2 = variance (y);
            double t, df;
            string title;
            if (kind == TTest.PAIRED) {
                int nn = int.min (x.length, y.length);
                double[] d = new double[nn];
                for (int i = 0; i < nn; i++) d[i] = x[i] - y[i];
                df = nn - 1;
                t = (mean (d) - hyp) / Math.sqrt (variance (d) / nn);
                title = _("t-Test: Paired Two Sample for Means");
            } else if (kind == TTest.EQUAL) {
                df = x.length + y.length - 2;
                double sp = ((x.length - 1) * v1 + (y.length - 1) * v2) / df;
                t = (m1 - m2 - hyp) / Math.sqrt (sp * (1.0 / x.length + 1.0 / y.length));
                title = _("t-Test: Two-Sample Assuming Equal Variances");
            } else {
                double a = v1 / x.length, b = v2 / y.length;
                df = Math.round ((a + b) * (a + b) / (a * a / (x.length - 1) + b * b / (y.length - 1)));
                t = (m1 - m2 - hyp) / Math.sqrt (a + b);
                title = _("t-Test: Two-Sample Assuming Unequal Variances");
            }
            WhatIf.put_value (book, out_s, 0, 0, Value.str (title));
            out_s.set_style (0, 0, styled (book, 0, true, ""));
            WhatIf.put_value (book, out_s, 2, 1, Value.str (labels ? a1.sheet.value_at (a1.r1, a1.c1).display () : _("Variable 1")));
            WhatIf.put_value (book, out_s, 2, 2, Value.str (labels ? a2.sheet.value_at (a2.r1, a2.c1).display () : _("Variable 2")));
            string[] lab = { _("Mean"), _("Variance"), _("Observations"), _("Hypothesized Mean Difference"), "df", _("t Stat"), _("P(T<=t) one-tail"), _("t Critical one-tail"), _("P(T<=t) two-tail"), _("t Critical two-tail") };
            var v = new Value[lab.length, 2];
            for (int i = 0; i < lab.length; i++) for (int j = 0; j < 2; j++) v[i, j] = Value.empty ();
            v[0, 0] = n (m1); v[0, 1] = n (m2);
            v[1, 0] = n (v1); v[1, 1] = n (v2);
            v[2, 0] = Value.num (x.length); v[2, 1] = Value.num (y.length);
            v[3, 0] = Value.num (hyp);
            v[4, 0] = Value.num (df);
            v[5, 0] = n (t);
            double p2 = t_two_tail (Math.fabs (t), df);
            v[6, 0] = n (p2 / 2);
            v[7, 0] = n (t_inv_two (2 * alpha, df));
            v[8, 0] = n (p2);
            v[9, 0] = n (t_inv_two (alpha, df));
            write_table (book, out_s, 3, 0, lab, v);
            out_s.col_widths[0] = 210;
            book.recalculate ();
            return out_s;
        }

        public static double f_inv_upper (double p, double d1, double d2) {
            double lo = 0, hi = 1e6;
            for (int i = 0; i < 300; i++) {
                double mid = (lo + hi) / 2;
                if (f_upper (mid, d1, d2) > p) lo = mid;
                else hi = mid;
            }
            return (lo + hi) / 2;
        }

        public static Sheet f_test (Workbook book, Area a1, Area a2, bool labels, double alpha = 0.05) {
            var out_s = output_sheet (book, _("F-Test"));
            var x = column_numbers (a1.sheet, a1.c1, labels ? a1.r1 + 1 : a1.r1, int.min (a1.r2, a1.sheet.max_row));
            var y = column_numbers (a2.sheet, a2.c1, labels ? a2.r1 + 1 : a2.r1, int.min (a2.r2, a2.sheet.max_row));
            double v1 = variance (x), v2 = variance (y);
            double f = v1 / v2;
            double d1 = x.length - 1, d2 = y.length - 1;
            double p = f >= 1 ? f_upper (f, d1, d2) : 1 - f_upper (f, d1, d2);
            WhatIf.put_value (book, out_s, 0, 0, Value.str (_("F-Test Two-Sample for Variances")));
            out_s.set_style (0, 0, styled (book, 0, true, ""));
            string[] lab = { _("Mean"), _("Variance"), _("Observations"), "df", "F", _("P(F<=f) one-tail"), _("F Critical one-tail") };
            var v = new Value[lab.length, 2];
            for (int i = 0; i < lab.length; i++) for (int j = 0; j < 2; j++) v[i, j] = Value.empty ();
            v[0, 0] = n (mean (x)); v[0, 1] = n (mean (y));
            v[1, 0] = n (v1); v[1, 1] = n (v2);
            v[2, 0] = Value.num (x.length); v[2, 1] = Value.num (y.length);
            v[3, 0] = Value.num (d1); v[3, 1] = Value.num (d2);
            v[4, 0] = n (f);
            v[5, 0] = n (p);
            v[6, 0] = n (f >= 1 ? f_inv_upper (alpha, d1, d2) : 1 / f_inv_upper (alpha, d2, d1));
            write_table (book, out_s, 2, 0, lab, v);
            out_s.col_widths[0] = 190;
            book.recalculate ();
            return out_s;
        }

        public static double[] holt_winters (double[] y, int season, int horizon, out double sigma) {
            int nn = y.length;
            double best_err = double.INFINITY;
            double[] best = new double[horizon];
            sigma = 0;
            bool seasonal = season > 1 && nn >= 2 * season;
            double[] grid = { 0.1, 0.2, 0.3, 0.5, 0.7, 0.9 };
            double[] ggrid = seasonal ? grid : new double[] { 0 };
            foreach (double alpha in grid) foreach (double beta in new double[] { 0.01, 0.1, 0.2, 0.4 }) foreach (double gamma in ggrid) {
                double level = y[0];
                double trend = nn > 1 ? y[1] - y[0] : 0;
                var seas = new double[int.max (season, 1)];
                if (seasonal) {
                    double m0 = 0;
                    for (int i = 0; i < season; i++) m0 += y[i];
                    m0 /= season;
                    level = m0;
                    double m1 = 0;
                    for (int i = season; i < 2 * season; i++) m1 += y[i];
                    trend = (m1 / season - m0) / season;
                    for (int i = 0; i < season; i++) seas[i] = y[i] - m0;
                }
                double sse = 0;
                int cnt = 0;
                for (int t = 1; t < nn; t++) {
                    double s = seasonal ? seas[t % season] : 0;
                    double f = level + trend + s;
                    double e = y[t] - f;
                    sse += e * e;
                    cnt++;
                    double nl = alpha * (y[t] - s) + (1 - alpha) * (level + trend);
                    trend = beta * (nl - level) + (1 - beta) * trend;
                    if (seasonal) seas[t % season] = gamma * (y[t] - nl) + (1 - gamma) * s;
                    level = nl;
                }
                if (sse < best_err) {
                    best_err = sse;
                    sigma = cnt > 0 ? Math.sqrt (sse / cnt) : 0;
                    for (int h = 1; h <= horizon; h++) best[h - 1] = level + h * trend + (seasonal ? seas[(nn - 1 + h) % season] : 0);
                }
            }
            return best;
        }

        public static int detect_season (double[] y) {
            int nn = y.length;
            double m = mean (y);
            double denom = 0;
            foreach (double d in y) denom += (d - m) * (d - m);
            int best = 1;
            double best_r = 0.3;
            for (int lag = 2; lag <= nn / 2 && lag <= 24; lag++) {
                double num = 0;
                for (int i = lag; i < nn; i++) num += (y[i] - m) * (y[i - lag] - m);
                double r = denom > 0 ? num / denom : 0;
                if (r > best_r) {
                    best_r = r;
                    best = lag;
                }
            }
            return best;
        }

        public static Sheet forecast_sheet (Workbook book, Area timeline, Area values, int horizon, double confidence = 0.95, int season = -1) {
            var out_s = output_sheet (book, _("Forecast"));
            var ts = new Gee.ArrayList<Value> ();
            double[] y = {};
            int r2 = int.min (values.r2, values.sheet.max_row);
            for (int i = 0; values.r1 + i <= r2; i++) {
                var v = values.sheet.value_at (values.r1 + i, values.c1);
                if (v.kind != ValueKind.NUMBER) continue;
                y += v.number;
                ts.add (timeline.sheet.value_at (timeline.r1 + i, timeline.c1));
            }
            int head = styled (book, 0, true, "");
            string[] hdr = { _("Timeline"), _("Values"), _("Forecast"), _("Lower Confidence Bound"), _("Upper Confidence Bound") };
            for (int j = 0; j < hdr.length; j++) {
                WhatIf.put_value (book, out_s, 0, j, Value.str (hdr[j]));
                out_s.set_style (0, j, head);
                out_s.col_widths[j] = 150;
            }
            if (y.length < 3) {
                book.recalculate ();
                return out_s;
            }
            int period = season < 0 ? detect_season (y) : season;
            double sigma;
            var fc = holt_winters (y, period, horizon, out sigma);
            double step = 1;
            bool numeric_time = ts.size >= 2 && ts[0].kind == ValueKind.NUMBER && ts[ts.size - 1].kind == ValueKind.NUMBER;
            if (numeric_time) step = (ts[ts.size - 1].number - ts[0].number) / (ts.size - 1);
            int tfmt = styled (book, timeline.sheet.style_at (timeline.r1, timeline.c1).number_format != "General" ? 0 : 0, false, timeline.sheet.style_at (timeline.r1, timeline.c1).number_format);
            for (int i = 0; i < y.length; i++) {
                WhatIf.put_value (book, out_s, 1 + i, 0, ts[i]);
                if (tfmt != 0) out_s.set_style (1 + i, 0, tfmt);
                WhatIf.put_value (book, out_s, 1 + i, 1, Value.num (y[i]));
            }
            WhatIf.put_value (book, out_s, y.length, 2, Value.num (y[y.length - 1]));
            WhatIf.put_value (book, out_s, y.length, 3, Value.num (y[y.length - 1]));
            WhatIf.put_value (book, out_s, y.length, 4, Value.num (y[y.length - 1]));
            double z = confidence >= 0.99 ? 2.576 : confidence >= 0.95 ? 1.96 : confidence >= 0.9 ? 1.645 : 1.282;
            for (int h = 1; h <= horizon; h++) {
                int r = y.length + h;
                if (numeric_time) WhatIf.put_value (book, out_s, r, 0, Value.num (ts[ts.size - 1].number + step * h));
                else WhatIf.put_value (book, out_s, r, 0, Value.num (y.length + h));
                if (tfmt != 0) out_s.set_style (r, 0, tfmt);
                double band = z * sigma * Math.sqrt (h);
                WhatIf.put_value (book, out_s, r, 2, Value.num (fc[h - 1]));
                WhatIf.put_value (book, out_s, r, 3, Value.num (fc[h - 1] - band));
                WhatIf.put_value (book, out_s, r, 4, Value.num (fc[h - 1] + band));
            }
            var ch = new Chart (new Area (out_s, 0, 0, y.length + horizon, 4));
            ch.kind = "line";
            ch.title = _("Forecast");
            ch.x = 780;
            ch.y = 20;
            out_s.charts.add (ch);
            book.recalculate ();
            return out_s;
        }

        public static int subtotals (Workbook book, Sheet s, Area area, int group_col, string function, int[] sum_cols, bool replace, bool page_breaks, bool summary_below) {
            int code = function_code (function);
            if (replace) remove_subtotals (book, s, area);
            int r1 = area.r1 + 1;
            int r2 = int.min (area.r2, s.max_row);
            if (r2 < r1) return 0;
            var breaks = new Gee.ArrayList<int> ();
            string prev = s.value_at (r1, group_col).display ();
            int start = r1;
            var groups = new Gee.ArrayList<int> ();
            for (int r = r1 + 1; r <= r2 + 1; r++) {
                string cur = r <= r2 ? s.value_at (r, group_col).display () : "\x1f";
                if (cur != prev) {
                    groups.add (start);
                    groups.add (r - 1);
                    start = r;
                    prev = cur;
                }
            }
            int inserted = 0;
            int bold = styled (book, 0, true, "");
            var group_rows = new Gee.ArrayList<int> ();
            for (int g = groups.size - 2; g >= 0; g -= 2) {
                int gs = groups[g], ge = groups[g + 1];
                string label = s.value_at (gs, group_col).display ();
                book.insert_rows (s, ge + 1, 1);
                int tr = ge + 1;
                WhatIf.put_value (book, s, tr, group_col, Value.str (_("%s Total").printf (label)));
                s.set_style (tr, group_col, bold);
                foreach (int c in sum_cols) {
                    s.set_input (tr, c, "=SUBTOTAL(%d,%s:%s)".printf (code, Address.cell (gs, c), Address.cell (ge, c)));
                    s.set_style (tr, c, bold);
                }
                inserted++;
                for (int i = 0; i < group_rows.size; i++) group_rows[i] = group_rows[i] + 1;
                group_rows.add (gs);
                group_rows.add (ge);
                breaks.add (tr);
            }
            int last = r2 + inserted;
            int gt = last + 1;
            book.insert_rows (s, gt, 1);
            WhatIf.put_value (book, s, gt, group_col, Value.str (_("Grand Total")));
            s.set_style (gt, group_col, bold);
            foreach (int c in sum_cols) {
                s.set_input (gt, c, "=SUBTOTAL(%d,%s:%s)".printf (code, Address.cell (r1, c), Address.cell (last, c)));
                s.set_style (gt, c, bold);
            }
            s.outline.group (true, r1, last);
            int offset = 0;
            var ordered = new Gee.ArrayList<int> ();
            for (int g = 0; g < groups.size; g += 2) {
                int gs = groups[g] + offset, ge = groups[g + 1] + offset;
                ordered.add (gs);
                ordered.add (ge);
                offset++;
            }
            for (int g = 0; g < ordered.size; g += 2) s.outline.group (true, ordered[g], ordered[g + 1]);
            s.outline.summary_below = summary_below;
            book.structure_changed = true;
            book.recalculate ();
            return inserted;
        }

        public static void remove_subtotals (Workbook book, Sheet s, Area area) {
            for (int r = int.min (area.r2, s.max_row); r >= area.r1; r--) {
                bool subtotal_row = false;
                for (int c = area.c1; c <= int.min (area.c2, s.max_col); c++) {
                    var cell = s.get_cell (r, c);
                    if (cell != null && cell.formula != null && cell.formula.kind == NodeKind.CALL && cell.formula.text == "SUBTOTAL") subtotal_row = true;
                }
                if (subtotal_row) book.delete_rows (s, r, 1);
            }
            s.outline.clear (true);
            book.structure_changed = true;
        }

        public static int function_code (string f) {
            switch (f.down ()) {
                case "average": return 1;
                case "count": return 3;
                case "counta": return 3;
                case "countnums": return 2;
                case "max": return 4;
                case "min": return 5;
                case "product": return 6;
                case "stdev": return 7;
                case "stdevp": return 8;
                case "var": return 10;
                case "varp": return 11;
                default: return 9;
            }
        }

        public static Area? consolidate (Workbook book, Gee.List<Area> sources, Sheet dest, int dr, int dc, string function, bool top_labels, bool left_labels, bool links) {
            if (sources.size == 0) return null;
            var agg = PivotAgg.from_key (function == "count" ? "count" : function);
            if (!top_labels && !left_labels) {
                int rows = 0, cols = 0;
                foreach (var a in sources) {
                    rows = int.max (rows, int.min (a.r2, a.sheet.max_row) - a.r1 + 1);
                    cols = int.max (cols, int.min (a.c2, a.sheet.max_col) - a.c1 + 1);
                }
                for (int i = 0; i < rows; i++) {
                    for (int j = 0; j < cols; j++) {
                        if (links) {
                            string[] refs = {};
                            foreach (var a in sources) if (a.r1 + i <= a.r2 && a.c1 + j <= a.c2) refs += Address.quote_sheet (a.sheet.name) + "!" + Address.cell (a.r1 + i, a.c1 + j);
                            dest.set_input (dr + i, dc + j, "=%s(%s)".printf (excel_fn (agg), string.joinv (",", refs)));
                        } else {
                            var acc = new PivotAcc ();
                            foreach (var a in sources) if (a.r1 + i <= a.r2 && a.c1 + j <= a.c2) acc.add (a.sheet.value_at (a.r1 + i, a.c1 + j));
                            WhatIf.put_value (book, dest, dr + i, dc + j, acc.result (agg));
                        }
                    }
                }
                book.structure_changed = true;
                book.recalculate ();
                return new Area (dest, dr, dc, dr + rows - 1, dc + cols - 1);
            }
            var row_keys = new Gee.ArrayList<string> ();
            var col_keys = new Gee.ArrayList<string> ();
            var cells = new Gee.HashMap<string, PivotAcc> ();
            var refs_map = new Gee.HashMap<string, Gee.ArrayList<string>> ();
            foreach (var a in sources) {
                int r2 = int.min (a.r2, a.sheet.max_row), c2 = int.min (a.c2, a.sheet.max_col);
                int dr1 = top_labels ? a.r1 + 1 : a.r1;
                int dc1 = left_labels ? a.c1 + 1 : a.c1;
                for (int r = dr1; r <= r2; r++) {
                    string rk = left_labels ? a.sheet.value_at (r, a.c1).display () : (r - dr1).to_string ();
                    if (!row_keys.contains (rk)) row_keys.add (rk);
                    for (int c = dc1; c <= c2; c++) {
                        string ck = top_labels ? a.sheet.value_at (a.r1, c).display () : (c - dc1).to_string ();
                        if (!col_keys.contains (ck)) col_keys.add (ck);
                        string k = rk + "\x1f" + ck;
                        if (!cells.has_key (k)) {
                            cells[k] = new PivotAcc ();
                            refs_map[k] = new Gee.ArrayList<string> ();
                        }
                        cells[k].add (a.sheet.value_at (r, c));
                        refs_map[k].add (Address.quote_sheet (a.sheet.name) + "!" + Address.cell (r, c, true, true));
                    }
                }
            }
            int ro = top_labels ? 1 : 0;
            int co = left_labels ? 1 : 0;
            if (top_labels) for (int j = 0; j < col_keys.size; j++) WhatIf.put_value (book, dest, dr, dc + co + j, QueryEngine.parse_value (col_keys[j]));
            if (left_labels) for (int i = 0; i < row_keys.size; i++) WhatIf.put_value (book, dest, dr + ro + i, dc, QueryEngine.parse_value (row_keys[i]));
            for (int i = 0; i < row_keys.size; i++) {
                for (int j = 0; j < col_keys.size; j++) {
                    string k = row_keys[i] + "\x1f" + col_keys[j];
                    if (!cells.has_key (k)) continue;
                    if (links) dest.set_input (dr + ro + i, dc + co + j, "=%s(%s)".printf (excel_fn (agg), string.joinv (",", refs_map[k].to_array ())));
                    else WhatIf.put_value (book, dest, dr + ro + i, dc + co + j, cells[k].result (agg));
                }
            }
            book.structure_changed = true;
            book.recalculate ();
            return new Area (dest, dr, dc, dr + ro + row_keys.size - 1, dc + co + col_keys.size - 1);
        }

        private static string excel_fn (PivotAgg a) {
            switch (a) {
                case PivotAgg.COUNT: return "COUNTA";
                case PivotAgg.COUNT_NUMS: return "COUNT";
                case PivotAgg.AVERAGE: return "AVERAGE";
                case PivotAgg.MAX: return "MAX";
                case PivotAgg.MIN: return "MIN";
                case PivotAgg.PRODUCT: return "PRODUCT";
                case PivotAgg.STDEV: return "STDEV";
                case PivotAgg.STDEVP: return "STDEVP";
                case PivotAgg.VAR: return "VAR";
                case PivotAgg.VARP: return "VARP";
                default: return "SUM";
            }
        }

        private static bool criteria_cell (Evaluator ev, Workbook book, Sheet s, Value crit_v, string crit_input, Value v, int row, int col, Area list) {
            if (crit_v.is_empty () && crit_input == "") return true;
            if (crit_input.has_prefix ("=") && crit_input.length > 1) {
                return true;
            }
            if (crit_v.kind == ValueKind.TEXT) {
                string t = crit_v.text;
                bool has_op = t.has_prefix ("<") || t.has_prefix (">") || t.has_prefix ("=");
                if (!has_op && !t.contains ("*") && !t.contains ("?")) {
                    return v.kind == ValueKind.TEXT && v.text.casefold ().has_prefix (t.casefold ());
                }
            }
            return new Criteria (crit_v).matches (v);
        }

        public static int advanced_filter (Workbook book, Area list, Area criteria, Area? copy_to, bool unique) {
            var s = list.sheet;
            int lr2 = int.min (list.r2, s.max_row);
            var headers = new Gee.HashMap<string, int> ();
            for (int c = list.c1; c <= list.c2; c++) headers[s.value_at (list.r1, c).display ().casefold ()] = c;
            var cs = criteria.sheet;
            int cr2 = int.min (criteria.r2, cs.max_row);
            var matches = new Gee.ArrayList<int> ();
            var seen = new Gee.HashSet<string> ();
            var ev = new Evaluator (book, s, list.r1, list.c1);
            for (int r = list.r1 + 1; r <= lr2; r++) {
                bool any = cr2 <= criteria.r1;
                for (int cr = criteria.r1 + 1; cr <= cr2 && !any; cr++) {
                    bool all = true;
                    bool row_has = false;
                    for (int cc = criteria.c1; cc <= criteria.c2 && all; cc++) {
                        string input = cs.input_at (cr, cc);
                        var cv = cs.value_at (cr, cc);
                        if (input == "" && cv.is_empty ()) continue;
                        row_has = true;
                        string hdr = cs.value_at (criteria.r1, cc).display ();
                        if (input.has_prefix ("=") && input.length > 1) {
                            try {
                                var node = Formula.parse (input, book, cs);
                                var shifted = Formula.shifted (node, r - (list.r1 + 1), 0);
                                var fev = new Evaluator (book, s, r, list.c1);
                                var fv = fev.eval_top (shifted);
                                if (!(fv.kind == ValueKind.BOOL && fv.number != 0)) all = false;
                            } catch (FormulaError e) {
                                all = false;
                            }
                            continue;
                        }
                        if (!headers.has_key (hdr.casefold ())) {
                            all = false;
                            continue;
                        }
                        int col = headers[hdr.casefold ()];
                        if (!criteria_cell (ev, book, s, cv, input, s.value_at (r, col), r, col, list)) all = false;
                    }
                    if (all && (row_has || cr == criteria.r1 + 1)) any = true;
                }
                if (!any) continue;
                if (unique) {
                    var sb = new StringBuilder ();
                    for (int c = list.c1; c <= list.c2; c++) sb.append (s.value_at (r, c).display ().casefold ()).append_c ('\x1f');
                    if (!seen.add (sb.str)) continue;
                }
                matches.add (r);
            }
            if (copy_to != null) {
                var d = copy_to.sheet;
                for (int c = list.c1; c <= list.c2; c++) {
                    WhatIf.put_value (book, d, copy_to.r1, copy_to.c1 + c - list.c1, s.value_at (list.r1, c));
                    d.set_style (copy_to.r1, copy_to.c1 + c - list.c1, s.style_at (list.r1, c) == book.styles[0] ? 0 : s.get_cell (list.r1, c).style);
                }
                for (int i = 0; i < matches.size; i++) {
                    for (int c = list.c1; c <= list.c2; c++) {
                        WhatIf.put_value (book, d, copy_to.r1 + 1 + i, copy_to.c1 + c - list.c1, s.value_at (matches[i], c));
                        var sc = s.get_cell (matches[i], c);
                        if (sc != null && sc.style != 0) d.set_style (copy_to.r1 + 1 + i, copy_to.c1 + c - list.c1, sc.style);
                    }
                }
            } else {
                var keep = new Gee.HashSet<int> ();
                keep.add_all (matches);
                for (int r = list.r1 + 1; r <= lr2; r++) {
                    if (keep.contains (r)) s.hidden_rows.remove (r);
                    else s.hidden_rows.add (r);
                }
            }
            book.structure_changed = true;
            book.recalculate ();
            return matches.size;
        }

        public static void show_all (Workbook book, Sheet s, Area list) {
            for (int r = list.r1; r <= int.min (list.r2, s.max_row); r++) s.hidden_rows.remove (r);
            book.structure_changed = true;
        }
    }
}
