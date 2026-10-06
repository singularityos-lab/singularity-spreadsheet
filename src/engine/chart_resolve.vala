namespace Singularity.Apps.Spreadsheet {

    public class ChartResolve {
        public static string area_ref (Sheet s, int r1, int c1, int r2, int c2) {
            string t = Address.quote_sheet (s.name) + "!" + Address.cell (r1, c1, true, true);
            if (r1 != r2 || c1 != c2) t += ":" + Address.cell (r2, c2, true, true);
            return t;
        }

        public static string cell_text (Workbook book, Sheet s, int r, int c) {
            var v = s.value_at (r, c);
            string color;
            return NumberFormat.format_value (v, s.style_at (r, c).number_format, out color, book.date1904);
        }

        private static double cell_number (Sheet s, int r, int c) {
            var v = s.value_at (r, c);
            return v.kind == ValueKind.NUMBER ? v.number : double.NAN;
        }

        public static Value? eval_ref (Workbook book, Sheet own, string text) {
            if (text.strip () == "") return null;
            try {
                var node = Formula.parse ("=" + text, book, own);
                var ev = new Evaluator (book, own, 0, 0);
                var v = ev.eval (node);
                if (v.is_error ()) return null;
                return v;
            } catch (FormulaError e) {
                return null;
            }
        }

        private static Value[] flatten (Workbook book, Sheet own, Value v, out string[] texts) {
            Value[] out_v = {};
            string[] out_t = {};
            if (v.kind == ValueKind.RANGE) {
                var a = v.area;
                var s = a.sheet ?? own;
                int r2 = int.min (a.r2, int.max (s.max_row, a.r1));
                int c2 = int.min (a.c2, int.max (s.max_col, a.c1));
                for (int r = a.r1; r <= r2 && out_v.length < 100000; r++) {
                    for (int c = a.c1; c <= c2; c++) {
                        out_v += s.value_at (r, c);
                        out_t += cell_text (book, s, r, c);
                    }
                }
            } else if (v.kind == ValueKind.ARRAY) {
                for (int i = 0; i < v.array.length[0]; i++) {
                    for (int j = 0; j < v.array.length[1]; j++) {
                        out_v += v.array[i, j];
                        out_t += v.array[i, j].display ();
                    }
                }
            } else if (v.kind == ValueKind.REFS) {
                foreach (var a in v.areas) {
                    string[] t;
                    var part = flatten (book, own, Value.range (a), out t);
                    foreach (var p in part) out_v += p;
                    foreach (var p in t) out_t += p;
                }
            } else {
                out_v += v;
                out_t += v.display ();
            }
            texts = out_t;
            return out_v;
        }

        private static double[] numbers_of (Value[] vals) {
            double[] d = new double[vals.length];
            for (int i = 0; i < vals.length; i++) d[i] = vals[i].kind == ValueKind.NUMBER ? vals[i].number : double.NAN;
            return d;
        }

        private static string[] category_texts (Workbook book, Sheet own, Area a) {
            string[] out_c = {};
            var s = a.sheet ?? own;
            int r2 = int.min (a.r2, int.max (s.max_row, a.r1));
            int c2 = int.min (a.c2, int.max (s.max_col, a.c1));
            if (a.cols > 1 && a.rows > 1) {
                bool vertical = a.rows >= a.cols;
                int outer = vertical ? r2 - a.r1 + 1 : c2 - a.c1 + 1;
                int levels = vertical ? c2 - a.c1 + 1 : r2 - a.r1 + 1;
                string[] last = new string[levels];
                for (int k = 0; k < levels; k++) last[k] = "";
                for (int i = 0; i < outer; i++) {
                    string[] parts = {};
                    for (int k = 0; k < levels; k++) {
                        int r = vertical ? a.r1 + i : a.r1 + k;
                        int c = vertical ? a.c1 + k : a.c1 + i;
                        string t = cell_text (book, s, r, c);
                        if (t != "") last[k] = t;
                        parts += t != "" ? t : last[k];
                    }
                    out_c += string.joinv ("\x1f", parts);
                }
                return out_c;
            }
            for (int r = a.r1; r <= r2; r++) {
                for (int c = a.c1; c <= c2; c++) out_c += cell_text (book, s, r, c);
            }
            return out_c;
        }

        public static Singularity.Charts.ChartSpec resolve (Workbook book, Sheet own, Chart chart) {
            var spec = chart.style.copy ();
            chart.apply_kind (spec);
            spec.title = chart.title;
            if (chart.explicit_series) resolve_explicit (book, own, spec);
            else derive_series (book, own, chart, spec);
            if (chart.kind == "combo" && spec.series.size >= 2) {
                bool any = false;
                foreach (var s in spec.series) if (s.has_type || s.secondary) any = true;
                if (!any) {
                    var last = spec.series[spec.series.size - 1];
                    last.has_type = true;
                    last.kind = Singularity.Charts.ChartType.LINE;
                    last.secondary = true;
                }
            }
            return spec;
        }

        private static void resolve_explicit (Workbook book, Sheet own, Singularity.Charts.ChartSpec spec) {
            string[] shared_cats = {};
            foreach (var s in spec.series) {
                string[] texts;
                if (s.name_ref != "") {
                    var v = eval_ref (book, own, s.name_ref);
                    if (v != null) {
                        var vals = flatten (book, own, v, out texts);
                        if (texts.length > 0) s.name = string.joinv (" ", texts);
                    }
                }
                if (s.values_ref != "") {
                    var v = eval_ref (book, own, s.values_ref);
                    if (v != null) s.values = numbers_of (flatten (book, own, v, out texts));
                }
                if (s.categories_ref != "") {
                    var v = eval_ref (book, own, s.categories_ref);
                    if (v != null && v.kind == ValueKind.RANGE) s.categories = category_texts (book, own, v.area);
                    else if (v != null) {
                        flatten (book, own, v, out texts);
                        s.categories = texts;
                    }
                }
                if (s.x_ref != "") {
                    var v = eval_ref (book, own, s.x_ref);
                    if (v != null) {
                        var vals = flatten (book, own, v, out texts);
                        s.xvalues = numbers_of (vals);
                        bool numeric = false;
                        foreach (double d in s.xvalues) if (!d.is_nan ()) numeric = true;
                        if (!numeric) {
                            s.categories = texts;
                            double[] seq = new double[texts.length];
                            for (int i = 0; i < seq.length; i++) seq[i] = i + 1;
                            s.xvalues = seq;
                        }
                    }
                }
                if (s.sizes_ref != "") {
                    var v = eval_ref (book, own, s.sizes_ref);
                    if (v != null) s.sizes = numbers_of (flatten (book, own, v, out texts));
                }
                if (shared_cats.length == 0 && s.categories.length > 0) shared_cats = s.categories;
            }
            spec.categories = shared_cats;
        }

        private static void copy_style (Singularity.Charts.Series from, Singularity.Charts.Series to) {
            to.has_type = from.has_type;
            to.kind = from.kind;
            to.secondary = from.secondary;
            to.smooth = from.smooth;
            to.marker = from.marker;
            to.color = from.color;
            to.line_width = from.line_width;
            to.labels = from.labels;
            to.trendline = from.trendline != null ? from.trendline.copy () : null;
            to.error_bars = from.error_bars != null ? from.error_bars.copy () : null;
        }

        public static void derive_series (Workbook book, Sheet own, Chart chart, Singularity.Charts.ChartSpec spec) {
            var templates = new Gee.ArrayList<Singularity.Charts.Series> ();
            foreach (var t in spec.series) templates.add (t);
            spec.series.clear ();
            var s = chart.source.sheet ?? own;
            var a = Document.clamp_area (s, chart.source);
            if (a.r2 > s.max_row) a.r2 = int.max (s.max_row, a.r1);
            if (a.c2 > s.max_col) a.c2 = int.max (s.max_col, a.c1);
            bool rows = chart.series_in_rows;
            int outer = rows ? a.rows : a.cols;
            int inner = rows ? a.cols : a.rows;
            bool header = chart.first_row_labels && inner > 1;
            bool labels = chart.first_col_labels && outer > 1;
            if (rows) {
                header = chart.first_col_labels && inner > 1;
                labels = chart.first_row_labels && outer > 1;
            }
            int label_levels = labels ? 1 : 0;
            var kind = spec.kind;
            bool hierarchical = kind == Singularity.Charts.ChartType.TREEMAP || kind == Singularity.Charts.ChartType.SUNBURST;
            if (hierarchical && labels && !rows) {
                int probe = a.r1 + (header ? 1 : 0);
                while (label_levels < outer - 1 && s.value_at (probe, a.c1 + label_levels).kind == ValueKind.TEXT) label_levels++;
                label_levels = int.max (label_levels, 1);
            }
            int start_inner = header ? 1 : 0;
            int start_outer = labels ? label_levels : 0;
            string cat_ref = "";
            string[] cats = {};
            if (labels) {
                Area ca = rows ? new Area (s, a.r1, a.c1 + start_inner, a.r1, a.c2) : new Area (s, a.r1 + start_inner, a.c1, a.r2, a.c1 + label_levels - 1);
                if (inner > start_inner) {
                    cat_ref = area_ref (s, ca.r1, ca.c1, ca.r2, ca.c2);
                    cats = category_texts (book, own, ca);
                }
            } else {
                for (int j = start_inner; j < inner; j++) cats += (j - start_inner + 1).to_string ();
            }
            spec.categories = cats;
            bool xy = kind == Singularity.Charts.ChartType.SCATTER || kind == Singularity.Charts.ChartType.BUBBLE;
            string x_ref = "";
            double[] xs = {};
            int first = start_outer;
            if (xy) {
                if (labels) {
                    x_ref = cat_ref;
                    for (int j = start_inner; j < inner; j++) xs += rows ? cell_number (s, a.r1, a.c1 + j) : cell_number (s, a.r1 + j, a.c1);
                } else if (outer - first >= 2) {
                    int i = first;
                    x_ref = rows ? area_ref (s, a.r1 + i, a.c1 + start_inner, a.r1 + i, a.c2) : area_ref (s, a.r1 + start_inner, a.c1 + i, a.r2, a.c1 + i);
                    for (int j = start_inner; j < inner; j++) xs += rows ? cell_number (s, a.r1 + i, a.c1 + j) : cell_number (s, a.r1 + j, a.c1 + i);
                    first++;
                } else {
                    for (int j = start_inner; j < inner; j++) xs += j - start_inner + 1;
                }
            }
            if (xy) {
                bool any_x = false;
                foreach (double xv in xs) if (!xv.is_nan ()) any_x = true;
                if (!any_x) {
                    for (int j = 0; j < xs.length; j++) xs[j] = j + 1;
                    if (labels) x_ref = "";
                }
            }
            int step = kind == Singularity.Charts.ChartType.BUBBLE ? 2 : 1;
            int idx = 0;
            for (int i = first; i < outer; i += step) {
                var ser = new Singularity.Charts.Series ();
                if (idx < templates.size) copy_style (templates[idx], ser);
                if (header) {
                    int hr = rows ? a.r1 + i : a.r1;
                    int hc = rows ? a.c1 : a.c1 + i;
                    ser.name = cell_text (book, s, hr, hc);
                    ser.name_ref = area_ref (s, hr, hc, hr, hc);
                } else {
                    ser.name = _("Series %d").printf (idx + 1);
                }
                if (inner > start_inner) ser.values_ref = rows ? area_ref (s, a.r1 + i, a.c1 + start_inner, a.r1 + i, a.c2) : area_ref (s, a.r1 + start_inner, a.c1 + i, a.r2, a.c1 + i);
                double[] vals = {};
                for (int j = start_inner; j < inner; j++) vals += rows ? cell_number (s, a.r1 + i, a.c1 + j) : cell_number (s, a.r1 + j, a.c1 + i);
                ser.values = vals;
                if (xy) {
                    ser.x_ref = x_ref;
                    ser.xvalues = xs;
                } else {
                    ser.categories_ref = cat_ref;
                }
                if (step == 2 && i + 1 < outer) {
                    int k = i + 1;
                    ser.sizes_ref = rows ? area_ref (s, a.r1 + k, a.c1 + start_inner, a.r1 + k, a.c2) : area_ref (s, a.r1 + start_inner, a.c1 + k, a.r2, a.c1 + k);
                    double[] sz = {};
                    for (int j = start_inner; j < inner; j++) sz += rows ? cell_number (s, a.r1 + k, a.c1 + j) : cell_number (s, a.r1 + j, a.c1 + k);
                    ser.sizes = sz;
                }
                spec.series.add (ser);
                idx++;
            }
        }

        public static string shift_ref (Workbook book, Sheet own, string text, Sheet target, bool rows, int at, int count) {
            if (text == "") return text;
            var a = area_of_ref (book, own, text);
            if (a == null || (a.sheet ?? own) != target) return text;
            var moved = Workbook.shift_area (a, rows, at, count);
            if (moved == null) return text;
            return area_ref (target, moved.r1, moved.c1, moved.r2, moved.c2);
        }

        public static void shift_refs (Workbook book, Sheet target, bool rows, int at, int count) {
            foreach (var sh in book.sheets) {
                foreach (var ch in sh.charts) {
                    if (!ch.explicit_series) continue;
                    foreach (var s in ch.style.series) {
                        s.name_ref = shift_ref (book, sh, s.name_ref, target, rows, at, count);
                        s.values_ref = shift_ref (book, sh, s.values_ref, target, rows, at, count);
                        s.categories_ref = shift_ref (book, sh, s.categories_ref, target, rows, at, count);
                        s.x_ref = shift_ref (book, sh, s.x_ref, target, rows, at, count);
                        s.sizes_ref = shift_ref (book, sh, s.sizes_ref, target, rows, at, count);
                    }
                }
                foreach (var g in sh.sparklines) {
                    var keep = new Gee.ArrayList<Sparkline> ();
                    foreach (var it in g.items) {
                        it.source = shift_ref (book, sh, it.source, target, rows, at, count);
                        if (sh == target) {
                            int v = rows ? it.row : it.col;
                            if (count < 0 && v >= at && v < at - count) continue;
                            if (v >= at) {
                                if (rows) it.row += count;
                                else it.col += count;
                            }
                        }
                        keep.add (it);
                    }
                    g.items = keep;
                }
            }
        }

        public static Area? area_of_ref (Workbook book, Sheet own, string text) {
            var v = eval_ref (book, own, text);
            if (v == null || v.kind != ValueKind.RANGE) return null;
            return v.area;
        }

        public static void adopt_source (Workbook book, Sheet own, Chart chart) {
            var st = chart.style;
            if (st.series.size == 0) return;
            Area? bound = null;
            bool contiguous = true;
            Sheet? sheet = null;
            bool vertical = true;
            foreach (var s in st.series) {
                var va = area_of_ref (book, own, s.values_ref);
                if (va == null) {
                    contiguous = false;
                    break;
                }
                if (sheet == null) sheet = va.sheet;
                if (va.sheet != sheet) contiguous = false;
                if (va.cols > 1 && va.rows == 1) vertical = false;
                bound = bound == null ? va.copy () : new Area (sheet, int.min (bound.r1, va.r1), int.min (bound.c1, va.c1), int.max (bound.r2, va.r2), int.max (bound.c2, va.c2));
            }
            if (bound == null) return;
            chart.source = bound;
            chart.series_in_rows = !vertical;
            chart.explicit_series = true;
            chart.first_row_labels = false;
            chart.first_col_labels = false;
        }
    }
}
