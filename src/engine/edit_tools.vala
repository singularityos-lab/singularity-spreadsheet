namespace Singularity.Apps.Spreadsheet {

    public enum ColumnFormat {
        GENERAL,
        TEXT,
        DATE_DMY,
        DATE_MDY,
        DATE_YMD,
        SKIP
    }

    public class SplitOptions {
        public bool fixed_width;
        public int[] breaks = {};
        public bool tab = true;
        public bool semicolon;
        public bool comma;
        public bool space;
        public string other = "";
        public bool consecutive;
        public char qualifier = '"';
        public Gee.HashMap<int, ColumnFormat> formats = new Gee.HashMap<int, ColumnFormat> ();

        public bool is_delim (unichar c) {
            if (tab && c == '\t') return true;
            if (semicolon && c == ';') return true;
            if (comma && c == ',') return true;
            if (space && c == ' ') return true;
            if (other != "" && other.index_of_char (c) >= 0) return true;
            return false;
        }
    }

    public class TextToColumns {
        public static Gee.List<string> split (string text, SplitOptions o) {
            var parts = new Gee.ArrayList<string> ();
            if (o.fixed_width) {
                int n = text.char_count ();
                int prev = 0;
                foreach (int b in o.breaks) {
                    if (b <= prev) continue;
                    int e = int.min (b, n);
                    parts.add (prev < n ? text.substring (text.index_of_nth_char (prev), text.index_of_nth_char (e) - text.index_of_nth_char (prev)) : "");
                    prev = e;
                }
                parts.add (prev < n ? text.substring (text.index_of_nth_char (prev)) : "");
                return parts;
            }
            var sb = new StringBuilder ();
            bool quoted = false;
            bool last_delim = false;
            unichar c;
            int i = 0;
            while (text.get_next_char (ref i, out c)) {
                if (o.qualifier != 0 && c == o.qualifier) {
                    if (quoted && i < text.length && text[i] == o.qualifier) {
                        sb.append_unichar (c);
                        i++;
                        continue;
                    }
                    quoted = !quoted;
                    last_delim = false;
                    continue;
                }
                if (!quoted && o.is_delim (c)) {
                    if (o.consecutive && last_delim) continue;
                    parts.add (sb.str);
                    sb.truncate (0);
                    last_delim = true;
                    continue;
                }
                last_delim = false;
                sb.append_unichar (c);
            }
            parts.add (sb.str);
            return parts;
        }

        public static string convert (string part, ColumnFormat f) {
            if (f == ColumnFormat.TEXT) return part == "" ? "" : "'" + part;
            if (f == ColumnFormat.DATE_DMY || f == ColumnFormat.DATE_MDY || f == ColumnFormat.DATE_YMD) {
                var bits = new Gee.ArrayList<int> ();
                foreach (string b in part.strip ().split_set ("/-. ")) if (b != "") bits.add (int.parse (b));
                if (bits.size == 3) {
                    int d, m, y;
                    if (f == ColumnFormat.DATE_DMY) { d = bits[0]; m = bits[1]; y = bits[2]; }
                    else if (f == ColumnFormat.DATE_MDY) { m = bits[0]; d = bits[1]; y = bits[2]; }
                    else { y = bits[0]; m = bits[1]; d = bits[2]; }
                    if (y < 100) y += y < 30 ? 2000 : 1900;
                    if (m >= 1 && m <= 12 && d >= 1 && d <= 31) return "%04d-%02d-%02d".printf (y, m, d);
                }
            }
            return part;
        }

        public static int apply (Document doc, Sheet s, Area sel, SplitOptions o, int dest_row, int dest_col) {
            int col = sel.c1;
            int r2 = int.min (sel.r2, int.max (s.max_row, sel.r1));
            var rows = new Gee.ArrayList<Gee.List<string>> ();
            int width = 1;
            for (int r = sel.r1; r <= r2; r++) {
                var parts = split (s.value_at (r, col).display (), o);
                rows.add (parts);
                width = int.max (width, parts.size);
            }
            var dest = new Area (s, dest_row, dest_col, dest_row + rows.size - 1, int.min (dest_col + width - 1, MAX_COLS - 1));
            doc.begin_area (_("Text to Columns"), s, new Area (s, int.min (sel.r1, dest.r1), int.min (col, dest.c1), int.max (r2, dest.r2), int.max (col, dest.c2)));
            for (int i = 0; i < rows.size; i++) {
                int out_c = dest_col;
                for (int j = 0; j < rows[i].size; j++) {
                    var f = o.formats.has_key (j) ? o.formats[j] : ColumnFormat.GENERAL;
                    if (f == ColumnFormat.SKIP) continue;
                    if (out_c >= MAX_COLS) break;
                    s.set_input (dest_row + i, out_c, convert (rows[i][j], f));
                    out_c++;
                }
            }
            doc.commit ();
            return width;
        }
    }

    public class AutoComplete {
        public static string? complete (Sheet s, int row, int col, string prefix) {
            if (prefix == "" || prefix.has_prefix ("=")) return null;
            bool has_letter = false;
            unichar ch;
            int k = 0;
            while (prefix.get_next_char (ref k, out ch)) if (ch.isalpha ()) has_letter = true;
            if (!has_letter) return null;
            string p = prefix.casefold ();
            string? found = null;
            int[] dirs = { -1, 1 };
            foreach (int d in dirs) {
                int r = row + d;
                int blanks = 0;
                while (r >= 0 && r < MAX_ROWS && r <= s.max_row + 1 && blanks < 1) {
                    var v = s.value_at (r, col);
                    if (v.kind == ValueKind.EMPTY) {
                        blanks++;
                        r += d;
                        continue;
                    }
                    if (v.kind == ValueKind.TEXT) {
                        string t = v.text;
                        if (t.casefold ().has_prefix (p) && t.length > prefix.length) {
                            if (found == null) found = t;
                            else if (found.casefold () != t.casefold ()) return null;
                        }
                    }
                    r += d;
                }
            }
            return found;
        }
    }

    public enum SpecialKind {
        BLANKS,
        CONSTANTS,
        FORMULAS,
        ERRORS,
        NOTES,
        VISIBLE,
        CURRENT_REGION,
        LAST_CELL,
        VALIDATION,
        CONDITIONAL
    }

    public class GoToSpecial {
        public static Gee.List<Area> find (Document doc, Sheet s, Area scope, SpecialKind kind, int row, int col) {
            var result = new Gee.ArrayList<Area> ();
            if (kind == SpecialKind.CURRENT_REGION) {
                result.add (doc.current_region (s, row, col));
                return result;
            }
            if (kind == SpecialKind.LAST_CELL) {
                result.add (new Area.cell (s, int.max (s.max_row, 0), int.max (s.max_col, 0)));
                return result;
            }
            Area a = scope.is_single () ? s.used_area () : Document.clamp_area (s, scope);
            int r2 = int.min (a.r2, int.max (s.max_row, a.r1));
            int c2 = int.min (a.c2, int.max (s.max_col, a.c1));
            if (kind == SpecialKind.VISIBLE) {
                for (int r = a.r1; r <= r2; r++) {
                    if (s.hidden_rows.contains (r)) continue;
                    int start = -1;
                    for (int c = a.c1; c <= c2 + 1; c++) {
                        bool vis = c <= c2 && !s.hidden_cols.contains (c);
                        if (vis && start < 0) start = c;
                        if (!vis && start >= 0) {
                            result.add (new Area (s, r, start, r, c - 1));
                            start = -1;
                        }
                    }
                }
                return merge_rows (s, result);
            }
            for (int r = a.r1; r <= r2; r++) {
                for (int c = a.c1; c <= c2; c++) {
                    var cell = s.get_cell (r, c);
                    bool hit = false;
                    switch (kind) {
                        case SpecialKind.BLANKS:
                            hit = cell == null || (cell.input == "" && cell.formula == null);
                            break;
                        case SpecialKind.CONSTANTS:
                            hit = cell != null && cell.formula == null && cell.input != "";
                            break;
                        case SpecialKind.FORMULAS:
                            hit = cell != null && cell.formula != null;
                            break;
                        case SpecialKind.ERRORS:
                            hit = cell != null && s.value_at (r, c).is_error ();
                            break;
                        case SpecialKind.NOTES:
                            hit = cell != null && cell.note != "";
                            break;
                        case SpecialKind.VALIDATION:
                            hit = ValidationCheck.at (s, r, c) != null;
                            break;
                        case SpecialKind.CONDITIONAL:
                            foreach (var cf in s.cond_formats) if (cf.area.contains (r, c)) hit = true;
                            break;
                        default:
                            break;
                    }
                    if (hit) result.add (new Area.cell (s, r, c));
                }
                if (result.size > 20000) break;
            }
            return merge_rows (s, result);
        }

        private static Gee.List<Area> merge_rows (Sheet s, Gee.List<Area> cells) {
            var runs = new Gee.ArrayList<Area> ();
            foreach (var a in cells) {
                if (runs.size > 0) {
                    var last = runs[runs.size - 1];
                    if (last.r1 == a.r1 && last.r2 == a.r2 && last.c2 + 1 == a.c1) {
                        runs[runs.size - 1] = new Area (s, last.r1, last.c1, a.r2, a.c2);
                        continue;
                    }
                }
                runs.add (a);
            }
            var merged = new Gee.ArrayList<Area> ();
            foreach (var a in runs) {
                bool done = false;
                for (int i = merged.size - 1; i >= 0 && !done; i--) {
                    var m = merged[i];
                    if (m.c1 == a.c1 && m.c2 == a.c2 && m.r2 + 1 == a.r1) {
                        merged[i] = new Area (s, m.r1, m.c1, a.r2, a.c2);
                        done = true;
                    }
                    if (m.r2 + 1 < a.r1) break;
                }
                if (!done) merged.add (a);
            }
            return merged;
        }
    }

    public enum PasteOp {
        NONE,
        ADD,
        SUBTRACT,
        MULTIPLY,
        DIVIDE
    }

    public class EditCommands {
        public static void set_filter_rule (Document doc, Sheet s, int col, FilterRule? rule) {
            if (s.filter == null) return;
            doc.begin_book (_("Filter"), s, s.filter.area);
            var f = s.filter.copy_to (s.filter.area);
            if (rule == null) {
                f.rules.unset (col);
                f.hidden_values.unset (col);
            } else {
                f.rules[col] = rule.copy ();
                if (rule.kind != FilterKind.VALUES) f.hidden_values.unset (col);
            }
            s.filter = f;
            doc.apply_filter (s);
            doc.commit ();
        }

        public static void clear_filters (Document doc, Sheet s) {
            if (s.filter == null) return;
            doc.begin_book (_("Clear Filter"), s, s.filter.area);
            s.filter = new Filter (s.filter.area.copy ());
            for (int r = s.filter.area.r1 + 1; r <= s.filter.area.r2; r++) s.hidden_rows.remove (r);
            doc.commit ();
        }

        public static void reapply_filter (Document doc, Sheet s) {
            if (s.filter == null) return;
            doc.begin_book (_("Reapply"), s, s.filter.area);
            for (int r = s.filter.area.r1 + 1; r <= s.filter.area.r2; r++) s.hidden_rows.remove (r);
            doc.apply_filter (s);
            doc.commit ();
        }

        public static void set_custom_lists (Document doc, Gee.List<string> lists) {
            doc.book.custom_lists.clear ();
            doc.book.custom_lists.add_all (lists);
            doc.modified = true;
        }

        public static void protect_sheet (Document doc, Sheet s, SheetProtection? p) {
            doc.begin_book (p != null ? _("Protect Sheet") : _("Unprotect Sheet"), s);
            s.protection = p;
            doc.commit ();
        }

        public static void protect_book (Document doc, BookProtection? p) {
            doc.begin_book (p != null ? _("Protect Workbook") : _("Unprotect Workbook"));
            doc.book.protection = p;
            doc.commit ();
        }

        public static void set_validation (Document doc, Sheet s, Area area, Validation? v) {
            doc.begin_book (_("Data Validation"), s, area);
            var keep = new Gee.ArrayList<Validation> ();
            foreach (var old in s.validations) {
                if (!old.area.intersects (area)) {
                    keep.add (old);
                    continue;
                }
                foreach (var piece in subtract (old.area, area)) keep.add (old.copy_to (piece));
            }
            s.validations = keep;
            if (v != null) s.validations.add (v.copy_to (area.copy ()));
            doc.commit ();
        }

        public static Gee.List<Area> subtract (Area a, Area b) {
            var out_l = new Gee.ArrayList<Area> ();
            if (!a.intersects (b)) {
                out_l.add (a);
                return out_l;
            }
            if (a.r1 < b.r1) out_l.add (new Area (a.sheet, a.r1, a.c1, b.r1 - 1, a.c2));
            if (a.r2 > b.r2) out_l.add (new Area (a.sheet, b.r2 + 1, a.c1, a.r2, a.c2));
            int r1 = int.max (a.r1, b.r1), r2 = int.min (a.r2, b.r2);
            if (a.c1 < b.c1) out_l.add (new Area (a.sheet, r1, a.c1, r2, b.c1 - 1));
            if (a.c2 > b.c2) out_l.add (new Area (a.sheet, r1, b.c2 + 1, r2, a.c2));
            return out_l;
        }

        public static void group (Document doc, Sheet s, bool rows, int a, int b, bool ungroup) {
            doc.begin_book (ungroup ? _("Ungroup") : _("Group"), s);
            if (ungroup) {
                s.outline.ungroup (rows, a, b);
                var hidden = rows ? s.hidden_rows : s.hidden_cols;
                for (int i = a; i <= b; i++) if (s.outline.level_of (rows, i) == 0) hidden.remove (i);
            } else {
                s.outline.group (rows, a, b);
            }
            doc.commit ();
        }

        public static void collapse (Document doc, Sheet s, bool rows, OutlineGroup g, bool collapse) {
            doc.begin_book (collapse ? _("Hide Detail") : _("Show Detail"), s);
            s.outline.set_collapsed (s, rows, g, collapse);
            doc.commit ();
        }

        public static void show_level (Document doc, Sheet s, bool rows, int lv) {
            doc.begin_book (_("Outline Level"), s);
            s.outline.show_level (s, rows, lv);
            doc.commit ();
        }

        public static int auto_outline (Document doc, Sheet s) {
            doc.begin_book (_("Auto Outline"), s);
            s.outline.clear (true);
            s.outline.clear (false);
            int n = AutoOutline.apply (s, true) + AutoOutline.apply (s, false);
            doc.commit ();
            return n;
        }

        public static void clear_outline (Document doc, Sheet s) {
            doc.begin_book (_("Clear Outline"), s);
            s.outline.clear (true);
            s.outline.clear (false);
            doc.commit ();
        }

        public static void set_summary (Document doc, Sheet s, bool below, bool right) {
            doc.begin_book (_("Outline Settings"), s);
            s.outline.summary_below = below;
            s.outline.summary_right = right;
            doc.commit ();
        }

        public static void apply_named_style (Document doc, Sheet s, Area sel, NamedStyle ns) {
            var theme = doc.book.theme;
            doc.edit_style (s, sel, _("Cell Style"), (st) => ns.apply (st, theme));
        }

        public static void set_theme (Document doc, DocTheme theme) {
            doc.begin_book (_("Theme"));
            var old = doc.book.theme;
            var map = new Gee.HashMap<string, string> ();
            for (int i = 0; i < old.colors.length && i < theme.colors.length; i++) map[old.colors[i].down ()] = theme.colors[i];
            var remap = new Gee.HashMap<int, int> ();
            for (int i = 0; i < doc.book.styles.size; i++) {
                var st = doc.book.styles[i];
                bool changed = false;
                var ns = st.copy ();
                if (map.has_key (st.fill.down ())) { ns.fill = map[st.fill.down ()]; changed = true; }
                if (map.has_key (st.color.down ())) { ns.color = map[st.color.down ()]; changed = true; }
                if (st.font_family == old.major_font && old.major_font != theme.major_font) { ns.font_family = theme.major_font; changed = true; }
                if (st.font_family == old.minor_font && old.minor_font != theme.minor_font) { ns.font_family = theme.minor_font; changed = true; }
                if (changed) remap[i] = doc.book.intern (ns);
            }
            foreach (var sh in doc.book.sheets) {
                foreach (var cell in sh.cells.values) if (remap.has_key (cell.style)) cell.style = remap[cell.style];
            }
            doc.book.theme = theme.copy ();
            doc.commit ();
        }

        public static void save_view (Document doc, Sheet s, CustomView v) {
            doc.begin_book (_("Custom View"), s);
            var keep = new Gee.ArrayList<CustomView> ();
            foreach (var old in s.views) if (old.name.casefold () != v.name.casefold ()) keep.add (old);
            keep.add (v);
            s.views = keep;
            doc.commit ();
        }

        public static void delete_view (Document doc, Sheet s, CustomView v) {
            doc.begin_book (_("Delete View"), s);
            var keep = new Gee.ArrayList<CustomView> ();
            foreach (var old in s.views) if (old != v) keep.add (old);
            s.views = keep;
            doc.commit ();
        }

        public static void show_view (Document doc, Sheet s, CustomView v) {
            doc.begin_book (_("Show View"), s);
            v.apply (s);
            doc.commit ();
        }

        public static Value combine (PasteOp op, Value dest, Value src) {
            double a = 0, b = 0;
            if (dest.kind == ValueKind.NUMBER) a = dest.number;
            else if (dest.kind != ValueKind.EMPTY) return dest;
            if (src.kind == ValueKind.NUMBER) b = src.number;
            else if (src.kind != ValueKind.EMPTY) return dest.kind == ValueKind.EMPTY ? src : dest;
            switch (op) {
                case PasteOp.ADD: return Value.num (a + b);
                case PasteOp.SUBTRACT: return Value.num (a - b);
                case PasteOp.MULTIPLY: return Value.num (a * b);
                case PasteOp.DIVIDE: return b == 0 ? Value.err (ErrorKind.DIV0) : Value.num (a / b);
                default: return src;
            }
        }

        private static string op_symbol (PasteOp op) {
            switch (op) {
                case PasteOp.ADD: return "+";
                case PasteOp.SUBTRACT: return "-";
                case PasteOp.MULTIPLY: return "*";
                case PasteOp.DIVIDE: return "/";
                default: return "";
            }
        }

        public static Area? paste_special (Document doc, Sheet s, int row, int col, bool values, bool formats, PasteOp op, bool skip_blanks, bool transpose, bool link, bool widths) {
            var clip = doc.clip;
            if (clip == null) return null;
            var src = clip.source;
            int rows = transpose ? src.cols : src.rows;
            int cols = transpose ? src.rows : src.cols;
            if (src.r2 == MAX_ROWS - 1) rows = int.max (clip.sheet.max_row - src.r1 + 1, 1);
            if (src.c2 == MAX_COLS - 1) cols = int.max (clip.sheet.max_col - src.c1 + 1, 1);
            var dest = new Area (s, row, col, int.min (row + rows - 1, MAX_ROWS - 1), int.min (col + cols - 1, MAX_COLS - 1));
            if (widths) {
                doc.begin_book (_("Paste Column Widths"), s, dest);
                for (int c = 0; c < cols; c++) {
                    int from = src.c1 + c;
                    if (clip.sheet.col_widths.has_key (from)) s.col_widths[col + c] = clip.sheet.col_widths[from];
                    else s.col_widths.unset (col + c);
                }
                doc.commit ();
                return dest;
            }
            doc.begin_area (_("Paste Special"), s, dest);
            var cells = new Gee.HashMap<int64?, CellCopy> (
                (k) => { int64 v = k; return (uint) (v ^ (v >> 32)); },
                (x, y) => { int64 p = x; int64 q = y; return p == q; });
            foreach (var cc in clip.cells) cells[Sheet.key (cc.row, cc.col)] = cc;
            for (int i = 0; i < src.rows && i < 1048576; i++) {
                int sr = src.r1 + i;
                if (sr > clip.sheet.max_row && src.r2 == MAX_ROWS - 1) break;
                for (int j = 0; j < src.cols && j < 16384; j++) {
                    int sc = src.c1 + j;
                    if (sc > clip.sheet.max_col && src.c2 == MAX_COLS - 1) break;
                    int r = row + (transpose ? j : i);
                    int c = col + (transpose ? i : j);
                    if (r >= MAX_ROWS || c >= MAX_COLS) continue;
                    var cc = cells[Sheet.key (sr, sc)];
                    var sv = clip.sheet.value_at (sr, sc);
                    bool blank = cc == null || (cc.input == "" && cc.formula == null);
                    if (link) {
                        string target = (clip.sheet != s ? Address.quote_sheet (clip.sheet.name) + "!" : "") + Address.cell (sr, sc, true, true);
                        s.set_input (r, c, "=" + target);
                        continue;
                    }
                    if (skip_blanks && blank) continue;
                    if (formats && cc != null) s.ensure (r, c).style = cc.style;
                    if (!values) continue;
                    if (op != PasteOp.NONE) {
                        var cell = s.get_cell (r, c);
                        if (cell != null && cell.formula != null) {
                            string f = cell.input.substring (1);
                            s.set_input (r, c, "=(" + f + ")" + op_symbol (op) + (sv.kind == ValueKind.NUMBER ? Value.format_number_general_full (sv.number) : "0"));
                            continue;
                        }
                        var dv = s.value_at (r, c);
                        var res = combine (op, dv, sv);
                        if (res.kind == ValueKind.NUMBER) s.set_input (r, c, Value.format_number_general_full (res.number));
                        else if (res.kind == ValueKind.ERROR) s.set_input (r, c, "=" + res.error.to_string ());
                        continue;
                    }
                    if (blank) {
                        s.set_input (r, c, "");
                        continue;
                    }
                    if (sv.kind == ValueKind.NUMBER) s.set_input (r, c, Value.format_number_general_full (sv.number));
                    else if (sv.kind == ValueKind.BOOL) s.set_input (r, c, sv.number != 0 ? "TRUE" : "FALSE");
                    else if (sv.kind == ValueKind.TEXT) s.set_input (r, c, Input.parse (sv.text).value.kind != ValueKind.TEXT || sv.text.has_prefix ("=") ? "'" + sv.text : sv.text);
                    else s.set_input (r, c, sv.display ());
                }
            }
            s.recompute_extent ();
            doc.commit ();
            return dest;
        }

        public static bool can_edit (Document doc, Sheet s, Area a, out string reason) {
            reason = "";
            if (Protect.area_locked (s, a)) {
                reason = Protect.message ();
                return false;
            }
            return true;
        }
    }
}
