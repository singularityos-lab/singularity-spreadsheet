using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class ChartDialog {
        private static string num_text (double v) {
            return v.is_nan () ? "" : Value.format_number_general_full (v);
        }

        private static double parse_num (string t) {
            string s = t.strip ();
            if (s == "") return double.NAN;
            double d;
            if (double.try_parse (s, out d)) return d;
            return double.NAN;
        }

        private static string[] trend_names () {
            return { _("None"), _("Linear"), _("Exponential"), _("Logarithmic"), _("Polynomial"), _("Power"), _("Moving Average") };
        }

        private static string[] error_names () {
            return { _("None"), _("Fixed Value"), _("Percentage"), _("Standard Deviation"), _("Standard Error") };
        }

        private static string[] legend_names () {
            return { _("None"), _("Top"), _("Bottom"), _("Left"), _("Right") };
        }

        private static string[] series_type_names () {
            return { _("Same as Chart"), _("Column"), _("Line"), _("Area") };
        }

        public static void open (SpreadsheetWindow win, Chart? existing) {
            var s = win.grid.sheet;
            var sel = win.grid.selection;
            Chart chart;
            if (existing != null) {
                chart = existing.copy ();
            } else {
                Area source = sel.is_single () ? win.doc.current_region (s, sel.r1, sel.c1) : Document.clamp_area (s, sel);
                if (source.r2 > s.max_row) source.r2 = int.max (s.max_row, source.r1);
                if (source.c2 > s.max_col) source.c2 = int.max (s.max_col, source.c1);
                chart = new Chart (source);
                chart.first_row_labels = source.rows > 1 && s.value_at (source.r1, source.c2).kind == ValueKind.TEXT;
                chart.first_col_labels = source.cols > 1 && s.value_at (source.r2, source.c1).kind != ValueKind.NUMBER;
                chart.x = win.grid.col_x (source.c2 + 1) - win.grid.col_x (s.freeze_cols) + 24;
                chart.y = 24 + (win.grid.row_y (source.r1) - win.grid.row_y (s.freeze_rows));
                chart.x = double.max (chart.x / win.grid.zoom, 20);
                chart.y = double.max (chart.y / win.grid.zoom, 20);
                bool moved = true;
                while (moved) {
                    moved = false;
                    foreach (var other in s.charts) {
                        bool overlap = chart.x < other.x + other.width && other.x < chart.x + chart.width && chart.y < other.y + other.height && other.y < chart.y + chart.height;
                        if (overlap) {
                            chart.y = other.y + other.height + 20;
                            moved = true;
                        }
                    }
                }
            }
            var st = chart.style;
            var dlg = Dialogs.make (win, existing != null ? _("Edit Chart") : _("Insert Chart"), 1080, 700);
            var split = new Box (Orientation.HORIZONTAL, 16);
            split.margin_start = split.margin_end = 18;
            split.margin_top = 6;
            split.vexpand = true;
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.width_request = 400;
            scroll.hexpand = false;
            scroll.propagate_natural_width = false;
            var side = new Box (Orientation.VERTICAL, 14);
            side.margin_end = 6;
            side.margin_bottom = 12;
            scroll.child = side;
            var preview = new DrawingArea ();
            preview.hexpand = true;
            preview.vexpand = true;
            preview.add_css_class ("ss-chart-preview");

            var types = new FlowBox ();
            types.selection_mode = SelectionMode.NONE;
            types.max_children_per_line = 2;
            types.min_children_per_line = 2;
            types.column_spacing = 6;
            types.row_spacing = 6;
            types.homogeneous = true;
            ToggleButton? first = null;
            foreach (string k in Chart.KINDS) {
                var b = new ToggleButton.with_label (Chart.kind_label (k));
                b.add_css_class ("ss-chip");
                b.tooltip_text = Chart.kind_label (k);
                if (first == null) first = b;
                else b.group = first;
                b.active = k == chart.kind;
                string kind = k;
                b.toggled.connect (() => {
                    if (!b.active) return;
                    chart.kind = kind;
                    preview.queue_draw ();
                });
                types.append (b);
            }
            var tg = new PreferencesGroup (_("Chart Type"));
            tg.add_row (types);
            side.append (tg);

            var dg = new PreferencesGroup (_("Data"));
            var title = new EntryRow (_("Title"));
            title.text = chart.title;
            title.entry_changed.connect (() => {
                chart.title = title.text;
                preview.queue_draw ();
            });
            var range = new EntryRow (_("Data"));
            range.text = Dialogs.area_text (chart.source);
            range.entry_changed.connect (() => {
                var a = Area.parse (range.text.replace ("$", ""), s);
                if (a != null) {
                    chart.source = new Area (s, a.r1, a.c1, a.r2, a.c2);
                    chart.explicit_series = false;
                    preview.queue_draw ();
                }
            });
            string[] series_items = { _("Columns"), _("Rows") };
            var series_in = new SelectionRow (_("Series in"), series_items, chart.series_in_rows ? series_items[1] : series_items[0]);
            series_in.selected.connect ((v) => {
                chart.series_in_rows = v == series_items[1];
                chart.explicit_series = false;
                preview.queue_draw ();
            });
            var header = new SwitchRow (_("First row has names"), null, chart.first_row_labels);
            header.switch_btn.notify["active"].connect (() => {
                chart.first_row_labels = header.active;
                chart.explicit_series = false;
                preview.queue_draw ();
            });
            var labels = new SwitchRow (_("First column has labels"), null, chart.first_col_labels);
            labels.switch_btn.notify["active"].connect (() => {
                chart.first_col_labels = labels.active;
                chart.explicit_series = false;
                preview.queue_draw ();
            });
            var alt = new EntryRow (_("Alternative text"));
            alt.text = chart.alt_text;
            alt.entry_changed.connect (() => chart.alt_text = alt.text);
            dg.add_row (title);
            dg.add_row (alt);
            dg.add_row (range);
            dg.add_row (series_in);
            dg.add_row (header);
            dg.add_row (labels);
            side.append (dg);

            var lg = new PreferencesGroup (_("Layout"));
            var legend_items = legend_names ();
            var legend = new SelectionRow (_("Legend"), legend_items, legend_items[(int) st.legend]);
            legend.selected.connect ((v) => {
                for (int i = 0; i < legend_items.length; i++) if (legend_items[i] == v) st.legend = (Singularity.Charts.LegendPosition) i;
                preview.queue_draw ();
            });
            var data_labels = new SwitchRow (_("Data labels"), null, st.data_labels);
            data_labels.switch_btn.notify["active"].connect (() => {
                st.data_labels = data_labels.active;
                preview.queue_draw ();
            });
            var smooth = new SwitchRow (_("Smooth lines"), null, st.smooth);
            smooth.switch_btn.notify["active"].connect (() => {
                st.smooth = smooth.active;
                preview.queue_draw ();
            });
            var gap = new SpinRow (_("Gap width"), null, 0, 500, 10, st.gap_width);
            gap.spin_btn.value_changed.connect (() => {
                st.gap_width = (int) gap.value;
                preview.queue_draw ();
            });
            var bins = new SpinRow (_("Histogram bins"), _("0 chooses automatically"), 0, 200, 1, st.bins);
            bins.spin_btn.value_changed.connect (() => {
                st.bins = (int) bins.value;
                preview.queue_draw ();
            });
            lg.add_row (legend);
            lg.add_row (data_labels);
            lg.add_row (smooth);
            lg.add_row (gap);
            lg.add_row (bins);
            side.append (lg);

            var ag = new PreferencesGroup (_("Axes"));
            var xt = new EntryRow (_("Horizontal axis title"));
            xt.text = st.x_axis.title;
            xt.entry_changed.connect (() => {
                st.x_axis.title = xt.text;
                preview.queue_draw ();
            });
            var yt = new EntryRow (_("Vertical axis title"));
            yt.text = st.y_axis.title;
            yt.entry_changed.connect (() => {
                st.y_axis.title = yt.text;
                preview.queue_draw ();
            });
            var ymin = new EntryRow (_("Minimum"));
            ymin.text = num_text (st.y_axis.min);
            ymin.entry_changed.connect (() => {
                st.y_axis.min = parse_num (ymin.text);
                preview.queue_draw ();
            });
            var ymax = new EntryRow (_("Maximum"));
            ymax.text = num_text (st.y_axis.max);
            ymax.entry_changed.connect (() => {
                st.y_axis.max = parse_num (ymax.text);
                preview.queue_draw ();
            });
            var unit = new EntryRow (_("Major unit"));
            unit.text = num_text (st.y_axis.major_unit);
            unit.entry_changed.connect (() => {
                st.y_axis.major_unit = parse_num (unit.text);
                preview.queue_draw ();
            });
            var fmt = new EntryRow (_("Number format"));
            fmt.text = st.y_axis.number_format;
            fmt.entry_changed.connect (() => {
                st.y_axis.number_format = fmt.text.strip ();
                preview.queue_draw ();
            });
            var logscale = new SwitchRow (_("Logarithmic scale"), null, st.y_axis.log_base > 1);
            logscale.switch_btn.notify["active"].connect (() => {
                st.y_axis.log_base = logscale.active ? 10 : 0;
                preview.queue_draw ();
            });
            var gridlines = new SwitchRow (_("Gridlines"), null, st.y_axis.gridlines);
            gridlines.switch_btn.notify["active"].connect (() => {
                st.y_axis.gridlines = gridlines.active;
                preview.queue_draw ();
            });
            var y2t = new EntryRow (_("Secondary axis title"));
            y2t.text = st.y2_axis.title;
            y2t.entry_changed.connect (() => {
                st.y2_axis.title = y2t.text;
                preview.queue_draw ();
            });
            ag.add_row (xt);
            ag.add_row (yt);
            ag.add_row (ymin);
            ag.add_row (ymax);
            ag.add_row (unit);
            ag.add_row (fmt);
            ag.add_row (logscale);
            ag.add_row (gridlines);
            ag.add_row (y2t);
            side.append (ag);

            var sg = new PreferencesGroup (_("Series"));
            side.append (sg);
            int current = 0;
            SelectionRow? picker = null;
            var rows = new Gee.ArrayList<Widget> ();
            Singularity.Charts.Series? template = null;
            Singularity.Charts.ChartSpec? resolved = null;

            SwitchRow secondary = new SwitchRow (_("Plot on secondary axis"), null, false);
            var type_items = series_type_names ();
            SelectionRow stype = new SelectionRow (_("Series type"), type_items, type_items[0]);
            var trend_items = trend_names ();
            SelectionRow trend = new SelectionRow (_("Trendline"), trend_items, trend_items[0]);
            SwitchRow eq = new SwitchRow (_("Show equation"), null, false);
            SwitchRow r2 = new SwitchRow (_("Show R squared"), null, false);
            SpinRow order = new SpinRow (_("Order or period"), null, 2, 6, 1, 2);
            var err_items = error_names ();
            SelectionRow errs = new SelectionRow (_("Error bars"), err_items, err_items[0]);
            SpinRow amount = new SpinRow (_("Error amount"), null, 0, 1000, 0.5, 1);
            EntryRow color = new EntryRow (_("Color"));
            SwitchRow slabels = new SwitchRow (_("Data labels for this series"), null, false);
            bool loading = false;

            Singularity.Charts.Series ensure_template (int i) {
                while (st.series.size <= i) st.series.add (new Singularity.Charts.Series ());
                return st.series[i];
            }

            void load () {
                loading = true;
                template = ensure_template (current);
                secondary.active = template.secondary;
                string tname = type_items[0];
                if (template.has_type) {
                    if (template.kind == Singularity.Charts.ChartType.COLUMN) tname = type_items[1];
                    else if (template.kind == Singularity.Charts.ChartType.LINE) tname = type_items[2];
                    else if (template.kind == Singularity.Charts.ChartType.AREA) tname = type_items[3];
                }
                stype.current_value = tname;
                var t = template.trendline;
                trend.current_value = trend_items[t != null ? (int) t.kind : 0];
                eq.active = t != null && t.show_equation;
                r2.active = t != null && t.show_r2;
                order.value = t != null ? (t.kind == Singularity.Charts.TrendType.MOVING_AVERAGE ? t.period : t.order) : 2;
                var e = template.error_bars;
                errs.current_value = err_items[e != null ? (int) e.kind : 0];
                amount.value = e != null ? e.amount : 1;
                color.text = template.color;
                slabels.active = template.labels;
                loading = false;
            }

            void changed () {
                if (loading || template == null) return;
                preview.queue_draw ();
            }

            void rebuild_series () {
                foreach (var w in rows) sg.remove_row (w);
                rows.clear ();
                resolved = ChartResolve.resolve (win.doc.book, s, chart);
                string[] names = {};
                for (int i = 0; i < resolved.series.size; i++) names += "%d. %s".printf (i + 1, resolved.series[i].name != "" ? resolved.series[i].name : _("Series %d").printf (i + 1));
                if (names.length == 0) return;
                current = current.clamp (0, names.length - 1);
                picker = new SelectionRow (_("Series"), names, names[current]);
                picker.selected.connect ((v) => {
                    for (int i = 0; i < names.length; i++) if (names[i] == v) current = i;
                    load ();
                });
                Widget[] all = { picker, stype, secondary, color, slabels, trend, order, eq, r2, errs, amount };
                foreach (var w in all) {
                    sg.add_row (w);
                    rows.add (w);
                }
                load ();
            }

            secondary.switch_btn.notify["active"].connect (() => {
                if (loading || template == null) return;
                template.secondary = secondary.active;
                changed ();
            });
            stype.selected.connect ((v) => {
                if (loading || template == null) return;
                template.has_type = v != type_items[0];
                if (v == type_items[1]) template.kind = Singularity.Charts.ChartType.COLUMN;
                else if (v == type_items[2]) template.kind = Singularity.Charts.ChartType.LINE;
                else if (v == type_items[3]) template.kind = Singularity.Charts.ChartType.AREA;
                changed ();
            });
            color.entry_changed.connect (() => {
                if (loading || template == null) return;
                string c = color.text.strip ().down ();
                if (c != "" && !c.has_prefix ("#")) c = "#" + c;
                template.color = c.length == 7 ? c : "";
                changed ();
            });
            slabels.switch_btn.notify["active"].connect (() => {
                if (loading || template == null) return;
                template.labels = slabels.active;
                changed ();
            });
            trend.selected.connect ((v) => {
                if (loading || template == null) return;
                int idx = 0;
                for (int i = 0; i < trend_items.length; i++) if (trend_items[i] == v) idx = i;
                if (idx == 0) {
                    template.trendline = null;
                } else {
                    if (template.trendline == null) template.trendline = new Singularity.Charts.Trendline ();
                    template.trendline.kind = (Singularity.Charts.TrendType) idx;
                    template.trendline.show_equation = eq.active;
                    template.trendline.show_r2 = r2.active;
                    template.trendline.order = (int) order.value;
                    template.trendline.period = (int) order.value;
                }
                changed ();
            });
            eq.switch_btn.notify["active"].connect (() => {
                if (loading || template == null || template.trendline == null) return;
                template.trendline.show_equation = eq.active;
                changed ();
            });
            r2.switch_btn.notify["active"].connect (() => {
                if (loading || template == null || template.trendline == null) return;
                template.trendline.show_r2 = r2.active;
                changed ();
            });
            order.spin_btn.value_changed.connect (() => {
                if (loading || template == null || template.trendline == null) return;
                template.trendline.order = (int) order.value;
                template.trendline.period = (int) order.value;
                changed ();
            });
            errs.selected.connect ((v) => {
                if (loading || template == null) return;
                int idx = 0;
                for (int i = 0; i < err_items.length; i++) if (err_items[i] == v) idx = i;
                if (idx == 0) {
                    template.error_bars = null;
                } else {
                    if (template.error_bars == null) template.error_bars = new Singularity.Charts.ErrorBars ();
                    template.error_bars.kind = (Singularity.Charts.ErrorBarType) idx;
                    template.error_bars.amount = amount.value;
                }
                changed ();
            });
            amount.spin_btn.value_changed.connect (() => {
                if (loading || template == null || template.error_bars == null) return;
                template.error_bars.amount = amount.value;
                changed ();
            });
            rebuild_series ();
            range.entry_changed.connect (() => rebuild_series ());
            series_in.selected.connect ((v) => rebuild_series ());

            split.append (scroll);
            preview.set_draw_func ((da, cr, w, h) => {
                var c = da.get_color ();
                bool dark = (c.red + c.green + c.blue) / 3 > 0.5;
                ChartRenderer.draw (cr, chart, ChartData.from (win.doc.book, s, chart), w, h, dark, false);
            });
            split.append (preview);
            dlg.content_box.append (split);
            Dialogs.footer (dlg, existing != null ? _("Apply") : _("Insert"), () => {
                if (existing != null) win.doc.update_chart (s, existing, chart);
                else win.doc.add_chart (s, chart);
                win.grid.queue_draw ();
            });
            dlg.open_dialog ();
        }
    }
}
