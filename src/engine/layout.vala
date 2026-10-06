namespace Singularity.Apps.Spreadsheet {

    public class Axis {
        private int count;
        private int default_size;
        private int[] keys = {};
        private int64[] before = {};
        private int[] sizes = {};

        public Axis (int count, int default_size, Gee.Map<int, int> overrides, Gee.Set<int> hidden) {
            this.count = count;
            this.default_size = default_size;
            var all = new Gee.TreeMap<int, int> ();
            foreach (var e in overrides.entries) if (e.key >= 0 && e.key < count) all[e.key] = e.value;
            foreach (int h in hidden) if (h >= 0 && h < count) all[h] = 0;
            int64 delta = 0;
            foreach (var e in all.entries) {
                keys += e.key;
                before += delta;
                sizes += e.value;
                delta += e.value - default_size;
            }
        }

        private int find (int index) {
            int lo = 0, hi = keys.length - 1, found = -1;
            while (lo <= hi) {
                int mid = (lo + hi) / 2;
                if (keys[mid] < index) {
                    found = mid;
                    lo = mid + 1;
                } else {
                    hi = mid - 1;
                }
            }
            return found;
        }

        public int size (int index) {
            int lo = 0, hi = keys.length - 1;
            while (lo <= hi) {
                int mid = (lo + hi) / 2;
                if (keys[mid] == index) return sizes[mid];
                if (keys[mid] < index) lo = mid + 1;
                else hi = mid - 1;
            }
            return default_size;
        }

        public int64 pos (int index) {
            int i = find (index);
            int64 delta = 0;
            if (i >= 0) delta = before[i] + sizes[i] - default_size;
            return (int64) index * default_size + delta;
        }

        public int index_at (int64 position) {
            if (position <= 0) return 0;
            int lo = 0, hi = count - 1;
            while (lo < hi) {
                int mid = lo + (hi - lo + 1) / 2;
                if (pos (mid) <= position) lo = mid;
                else hi = mid - 1;
            }
            while (lo < count - 1 && size (lo) == 0) lo++;
            return lo;
        }

        public int64 total () {
            return pos (count);
        }
    }

    public class CondStyle {
        public string fill = "";
        public string color = "";
        public bool bold;
        public bool italic;
        public bool underline;
        public bool strike;
        public double bar = -1;
        public string bar_color = "";
        public string icon_set = "";
        public int icon = -1;
        public bool hide_value;
        public bool fill_set;
        public bool color_set;
        public bool stopped;
    }

    public class CondIcons {
        public static int count (string set) {
            if (set.has_prefix ("5")) return 5;
            if (set.has_prefix ("4")) return 4;
            return 3;
        }

        public static bool date_matches (string period, double serial) {
            var now = new DateTime.now_local ();
            double today = DateSerial.from_ymd (now.get_year (), now.get_month (), now.get_day_of_month ());
            double d = Math.floor (serial);
            int dow = now.get_day_of_week () % 7;
            double week_start = today - dow;
            int y, m, dd;
            DateSerial.to_ymd (d, out y, out m, out dd);
            int ty = now.get_year (), tm = now.get_month ();
            switch (period) {
                case "today": return d == today;
                case "yesterday": return d == today - 1;
                case "tomorrow": return d == today + 1;
                case "last7Days": return d <= today && d > today - 7;
                case "thisWeek": return d >= week_start && d < week_start + 7;
                case "lastWeek": return d >= week_start - 7 && d < week_start;
                case "nextWeek": return d >= week_start + 7 && d < week_start + 14;
                case "thisMonth": return y == ty && m == tm;
                case "lastMonth": return (tm == 1 ? (y == ty - 1 && m == 12) : (y == ty && m == tm - 1));
                case "nextMonth": return (tm == 12 ? (y == ty + 1 && m == 1) : (y == ty && m == tm + 1));
                default: return false;
            }
        }
    }

    public class CondEval {
        private Workbook book;
        private Sheet sheet;
        private Gee.HashMap<CondFormat, Stats> stats = new Gee.HashMap<CondFormat, Stats> ();

        private class Stats {
            public double min = double.INFINITY;
            public double max = -double.INFINITY;
            public double mid;
            public double avg;
            public double threshold;
            public Gee.HashMap<string, int> counts = new Gee.HashMap<string, int> ();
            public Node? node;
            public Node? node_a;
            public Node? node_b;
        }

        public CondEval (Workbook book, Sheet sheet) {
            this.book = book;
            this.sheet = sheet;
        }

        private Stats stats_for (CondFormat cf) {
            var st = stats[cf];
            if (st != null) return st;
            st = new Stats ();
            var nums = new Gee.ArrayList<double?> ();
            var area = Document.clamp_area (sheet, cf.area);
            sheet.foreach_in (area, (r, c, cell) => {
                var v = book.cell_value (sheet, cell);
                if (v.kind == ValueKind.NUMBER) nums.add (v.number);
                if (v.kind != ValueKind.EMPTY) {
                    string k = v.display ().casefold ();
                    st.counts[k] = (st.counts.has_key (k) ? st.counts[k] : 0) + 1;
                }
            });
            double sum = 0;
            foreach (var d in nums) {
                st.min = double.min (st.min, d);
                st.max = double.max (st.max, d);
                sum += d;
            }
            st.avg = nums.size > 0 ? sum / nums.size : 0;
            nums.sort ((a, b) => a < b ? -1 : (a > b ? 1 : 0));
            if (nums.size > 0) {
                int n = nums.size;
                st.mid = n % 2 == 1 ? nums[n / 2] : (nums[n / 2 - 1] + nums[n / 2]) / 2;
                int want = int.parse (cf.a != "" ? cf.a : "10");
                if (cf.percent) want = (int) Math.floor (n * want / 100.0);
                int k = int.max (1, int.min (want, n));
                if (cf.kind == CondKind.TOP) st.threshold = nums[n - k];
                if (cf.kind == CondKind.BOTTOM) st.threshold = nums[k - 1];
            }
            try {
                if (cf.kind == CondKind.FORMULA) st.node = Formula.parse (cf.a.has_prefix ("=") ? cf.a : "=" + cf.a, book, sheet);
                if (cf.a.has_prefix ("=")) st.node_a = Formula.parse (cf.a, book, sheet);
                if (cf.b.has_prefix ("=")) st.node_b = Formula.parse (cf.b, book, sheet);
            } catch (FormulaError e) {
            }
            stats[cf] = st;
            return st;
        }

        private Value operand (string text, Node? node, CondFormat cf, int r, int c) {
            if (node != null) {
                var ev = new Evaluator (book, sheet, r, c);
                return ev.eval_top (Formula.shifted (node, r - cf.area.r1, c - cf.area.c1));
            }
            return Input.parse (text).value;
        }

        private static uint8 channel (string hex, int at) {
            return (uint8) Xlsx.hex2 (hex.substring (1), at);
        }

        public static string mix (string a, string b, double t) {
            if (a.length != 7 || b.length != 7) return a;
            int r = (int) Math.round (channel (a, 0) + (channel (b, 0) - channel (a, 0)) * t);
            int g = (int) Math.round (channel (a, 2) + (channel (b, 2) - channel (a, 2)) * t);
            int bl = (int) Math.round (channel (a, 4) + (channel (b, 4) - channel (a, 4)) * t);
            return "#%02x%02x%02x".printf (r, g, bl);
        }

        public CondStyle? apply (int r, int c, Value v) {
            CondStyle? out_s = null;
            foreach (var cf in sheet.cond_formats) {
                if (!cf.area.contains (r, c)) continue;
                if (out_s != null && out_s.stopped) break;
                var st = stats_for (cf);
                bool hit = false;
                switch (cf.kind) {
                    case CondKind.COLOR_SCALE:
                        if (v.kind != ValueKind.NUMBER || st.max <= st.min) {
                            if (v.kind == ValueKind.NUMBER && st.max == st.min) {
                                out_s = out_s ?? new CondStyle ();
                                out_s.fill = cf.three_colors ? cf.color2 : cf.color1;
                            }
                            continue;
                        }
                        out_s = out_s ?? new CondStyle ();
                        if (cf.three_colors) {
                            if (v.number <= st.mid) out_s.fill = mix (cf.color1, cf.color2, st.mid > st.min ? (v.number - st.min) / (st.mid - st.min) : 0);
                            else out_s.fill = mix (cf.color2, cf.color3, st.max > st.mid ? (v.number - st.mid) / (st.max - st.mid) : 1);
                        } else {
                            out_s.fill = mix (cf.color1, cf.color3, (v.number - st.min) / (st.max - st.min));
                        }
                        continue;
                    case CondKind.DATA_BAR:
                        if (v.kind != ValueKind.NUMBER) continue;
                        out_s = out_s ?? new CondStyle ();
                        double lo = double.min (st.min, 0);
                        double span = st.max - lo;
                        out_s.bar = span > 0 ? (v.number - lo) / span : 1;
                        out_s.bar_color = cf.color1;
                        continue;
                    case CondKind.GREATER:
                    case CondKind.LESS:
                    case CondKind.EQUAL:
                    case CondKind.NOT_EQUAL:
                        if (v.kind == ValueKind.EMPTY) break;
                        var a = operand (cf.a, st.node_a, cf, r, c);
                        int cmp = Evaluator.compare (v, a);
                        hit = cf.kind == CondKind.GREATER ? cmp > 0 : (cf.kind == CondKind.LESS ? cmp < 0 : (cf.kind == CondKind.EQUAL ? cmp == 0 : cmp != 0));
                        break;
                    case CondKind.BETWEEN:
                        if (v.kind == ValueKind.EMPTY) break;
                        var lo_v = operand (cf.a, st.node_a, cf, r, c);
                        var hi_v = operand (cf.b, st.node_b, cf, r, c);
                        hit = Evaluator.compare (v, lo_v) >= 0 && Evaluator.compare (v, hi_v) <= 0;
                        break;
                    case CondKind.TEXT_CONTAINS:
                        hit = cf.a != "" && v.display ().casefold ().contains (cf.a.casefold ());
                        break;
                    case CondKind.DUPLICATE:
                    case CondKind.UNIQUE:
                        if (v.kind == ValueKind.EMPTY) break;
                        string k = v.display ().casefold ();
                        int n = st.counts.has_key (k) ? st.counts[k] : 0;
                        hit = cf.kind == CondKind.DUPLICATE ? n > 1 : n == 1;
                        break;
                    case CondKind.FORMULA:
                        if (st.node == null) break;
                        var ev = new Evaluator (book, sheet, r, c);
                        var res = ev.eval_top (Formula.shifted (st.node, r - cf.area.r1, c - cf.area.c1));
                        hit = !res.is_error () && Functions.truthy (res);
                        break;
                    case CondKind.TOP:
                        hit = v.kind == ValueKind.NUMBER && v.number >= st.threshold;
                        break;
                    case CondKind.BOTTOM:
                        hit = v.kind == ValueKind.NUMBER && v.number <= st.threshold;
                        break;
                    case CondKind.ABOVE_AVERAGE:
                        hit = v.kind == ValueKind.NUMBER && v.number > st.avg;
                        break;
                    case CondKind.BELOW_AVERAGE:
                        hit = v.kind == ValueKind.NUMBER && v.number < st.avg;
                        break;
                    case CondKind.BLANK:
                        hit = v.kind == ValueKind.EMPTY || (v.kind == ValueKind.TEXT && v.text.strip () == "");
                        break;
                    case CondKind.ERRORS:
                        hit = v.is_error ();
                        break;
                    case CondKind.NO_ERRORS:
                        hit = !v.is_error ();
                        break;
                    case CondKind.NO_BLANK:
                        hit = !(v.kind == ValueKind.EMPTY || (v.kind == ValueKind.TEXT && v.text.strip () == ""));
                        break;
                    case CondKind.GREATER_EQUAL:
                    case CondKind.LESS_EQUAL:
                        if (v.kind == ValueKind.EMPTY) break;
                        int cmp2 = Evaluator.compare (v, operand (cf.a, st.node_a, cf, r, c));
                        hit = cf.kind == CondKind.GREATER_EQUAL ? cmp2 >= 0 : cmp2 <= 0;
                        break;
                    case CondKind.NOT_BETWEEN:
                        if (v.kind == ValueKind.EMPTY) break;
                        var nlo = operand (cf.a, st.node_a, cf, r, c);
                        var nhi = operand (cf.b, st.node_b, cf, r, c);
                        hit = Evaluator.compare (v, nlo) < 0 || Evaluator.compare (v, nhi) > 0;
                        break;
                    case CondKind.TEXT_BEGINS:
                        hit = cf.a != "" && v.display ().casefold ().has_prefix (cf.a.casefold ());
                        break;
                    case CondKind.TEXT_ENDS:
                        hit = cf.a != "" && v.display ().casefold ().has_suffix (cf.a.casefold ());
                        break;
                    case CondKind.TEXT_NOT_CONTAINS:
                        hit = !v.display ().casefold ().contains (cf.a.casefold ());
                        break;
                    case CondKind.DATE_OCCURRING:
                        hit = v.kind == ValueKind.NUMBER && CondIcons.date_matches (cf.date_period, v.number);
                        break;
                    case CondKind.ICON_SET:
                        if (v.kind != ValueKind.NUMBER) continue;
                        out_s = out_s ?? new CondStyle ();
                        if (out_s.icon >= 0) continue;
                        int icons = CondIcons.count (cf.icon_set);
                        double frac = st.max > st.min ? (v.number - st.min) / (st.max - st.min) : 1;
                        int idx = (int) Math.floor (frac * icons);
                        if (idx >= icons) idx = icons - 1;
                        if (cf.icon_reverse) idx = icons - 1 - idx;
                        out_s.icon_set = cf.icon_set;
                        out_s.icon = idx;
                        out_s.hide_value = !cf.show_value;
                        continue;
                }
                if (!hit) continue;
                out_s = out_s ?? new CondStyle ();
                if (cf.stop_if_true) out_s.stopped = true;
                var style = book.styles[cf.style];
                if (style.fill != "" && !out_s.fill_set) {
                    out_s.fill = style.fill;
                    out_s.fill_set = true;
                }
                if (style.color != "" && !out_s.color_set) {
                    out_s.color = style.color;
                    out_s.color_set = true;
                }
                if (style.bold) out_s.bold = true;
                if (style.italic) out_s.italic = true;
                if (style.underline) out_s.underline = true;
                if (style.strike) out_s.strike = true;
            }
            return out_s;
        }
    }
}
