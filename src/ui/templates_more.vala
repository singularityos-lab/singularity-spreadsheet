namespace Singularity.Apps.Spreadsheet {

    public class MoreTemplates {
        private static int style (Document d, bool bold, string fill, string color, string fmt = "General", HAlign align = HAlign.GENERAL) {
            var st = new CellStyle ();
            st.bold = bold;
            st.fill = fill;
            st.color = color;
            st.number_format = fmt;
            st.halign = align;
            return d.book.intern (st);
        }

        private static int title_style (Document d, string color) {
            var st = new CellStyle ();
            st.bold = true;
            st.font_size = 18;
            st.color = color;
            return d.book.intern (st);
        }

        private static int total_style (Document d, string fmt) {
            var st = new CellStyle ();
            st.bold = true;
            st.number_format = fmt;
            st.top = new Border (BorderStyle.THIN, "");
            st.bottom = new Border (BorderStyle.DOUBLE, "");
            return d.book.intern (st);
        }

        private static void header (Document d, Sheet s, int row, string[] cells, string fill) {
            int h = style (d, true, fill, "#ffffff", "General", HAlign.CENTER);
            for (int c = 0; c < cells.length; c++) {
                s.set_input (row, c, cells[c]);
                s.set_style (row, c, h);
            }
        }

        private static Document finish (Document d) {
            d.book.recalculate ();
            d.modified = false;
            return d;
        }

        public static Document timesheet () {
            var d = new Document ();
            var s = d.book.sheets[0];
            s.name = _("Timesheet");
            s.set_input (0, 0, _("Weekly Timesheet"));
            s.set_style (0, 0, title_style (d, "#1f7a8c"));
            s.row_heights[0] = 36;
            int label = style (d, true, "", "#52514e");
            s.set_input (1, 0, _("Employee"));
            s.set_input (1, 1, _("Your name"));
            s.set_input (2, 0, _("Week of"));
            s.set_input (2, 1, "=TODAY()-WEEKDAY(TODAY(),3)");
            s.set_style (1, 0, label);
            s.set_style (2, 0, label);
            s.set_style (2, 1, style (d, false, "", "", LocaleInfo.get ().short_date_format (), HAlign.LEFT));
            header (d, s, 4, { _("Day"), _("Date"), _("Start"), _("End"), _("Break (min)"), _("Hours") }, "#1f7a8c");
            string[] days = { _("Monday"), _("Tuesday"), _("Wednesday"), _("Thursday"), _("Friday"), _("Saturday"), _("Sunday") };
            string[] starts = { "9:00", "9:00", "8:30", "9:00", "9:00", "", "" };
            string[] ends = { "17:30", "18:00", "17:00", "17:30", "16:00", "", "" };
            string[] breaks = { "30", "45", "30", "30", "30", "", "" };
            int date = style (d, false, "", "", LocaleInfo.get ().short_date_format ());
            int time = style (d, false, "", "", "h:mm");
            int hours = style (d, false, "", "", "0.00");
            for (int i = 0; i < days.length; i++) {
                int r = 5 + i;
                s.set_input (r, 0, days[i]);
                s.set_input (r, 1, "=$B$3+%d".printf (i));
                if (starts[i] != "") {
                    s.set_input (r, 2, starts[i]);
                    s.set_input (r, 3, ends[i]);
                    s.set_input (r, 4, breaks[i]);
                }
                s.set_input (r, 5, "=IF(OR(C%d=\"\",D%d=\"\"),0,(D%d-C%d)*24-E%d/60)".printf (r + 1, r + 1, r + 1, r + 1, r + 1));
                s.set_style (r, 1, date);
                s.set_style (r, 2, time);
                s.set_style (r, 3, time);
                s.set_style (r, 5, hours);
            }
            s.set_input (12, 4, _("Total hours"));
            s.set_input (12, 5, "=SUM(F6:F12)");
            s.set_style (12, 4, total_style (d, "General"));
            s.set_style (12, 5, total_style (d, "0.00"));
            s.set_input (13, 4, _("Overtime"));
            s.set_input (13, 5, "=MAX(0,F13-40)");
            s.set_style (13, 5, hours);
            s.col_widths[0] = 130;
            s.col_widths[4] = 110;
            s.show_grid = false;
            return finish (d);
        }

        public static Document expenses () {
            var d = new Document ();
            var s = d.book.sheets[0];
            s.name = _("Expenses");
            header (d, s, 0, { _("Date"), _("Description"), _("Category"), _("Payment"), _("Amount") }, "#c0504d");
            string money_fmt = Dialogs.currency_format (2);
            int date = style (d, false, "", "", LocaleInfo.get ().short_date_format ());
            int money = style (d, false, "", "", money_fmt);
            string[] what = { _("Train ticket"), _("Lunch with client"), _("Office supplies"), _("Hotel, two nights"), _("Taxi"), _("Software subscription") };
            string[] cat = { _("Travel"), _("Meals"), _("Office"), _("Travel"), _("Travel"), _("Office") };
            string[] pay = { _("Card"), _("Cash"), _("Card"), _("Card"), _("Cash"), _("Card") };
            double[] amount = { 48.5, 36.2, 21.9, 212, 18.4, 12.99 };
            for (int i = 0; i < what.length; i++) {
                int r = i + 1;
                s.set_input (r, 0, "=TODAY()-%d".printf ((what.length - i) * 3));
                s.set_input (r, 1, what[i]);
                s.set_input (r, 2, cat[i]);
                s.set_input (r, 3, pay[i]);
                s.set_input (r, 4, Value.format_number_general_full (amount[i]));
                s.set_style (r, 0, date);
                s.set_style (r, 4, money);
            }
            var v = new Validation (new Area (s, 1, 2, 500, 2));
            v.list_source = "\"%s,%s,%s,%s\"".printf (_("Travel"), _("Meals"), _("Office"), _("Other"));
            s.validations.add (v);
            s.set_input (0, 6, _("Category"));
            s.set_input (0, 7, _("Total"));
            s.set_style (0, 6, style (d, true, "#f2dcdb", "", "General", HAlign.CENTER));
            s.set_style (0, 7, style (d, true, "#f2dcdb", "", "General", HAlign.CENTER));
            string[] cats = { _("Travel"), _("Meals"), _("Office"), _("Other") };
            for (int i = 0; i < cats.length; i++) {
                s.set_input (i + 1, 6, cats[i]);
                s.set_input (i + 1, 7, "=SUMIF($C$2:$C$500,G%d,$E$2:$E$500)".printf (i + 2));
                s.set_style (i + 1, 7, money);
            }
            s.set_input (5, 6, _("Total"));
            s.set_input (5, 7, "=SUM(H2:H5)");
            s.set_style (5, 6, total_style (d, "General"));
            s.set_style (5, 7, total_style (d, money_fmt));
            s.col_widths[1] = 190;
            s.col_widths[2] = 100;
            s.col_widths[5] = 30;
            s.freeze_rows = 1;
            return finish (d);
        }

        public static Document inventory () {
            var d = new Document ();
            var s = d.book.sheets[0];
            s.name = _("Inventory");
            header (d, s, 0, { _("SKU"), _("Item"), _("In Stock"), _("Reorder At"), _("Unit Cost"), _("Stock Value"), _("Status") }, "#5b6c8f");
            string money_fmt = Dialogs.currency_format (2);
            int money = style (d, false, "", "", money_fmt);
            string[] items = { _("Notebook A5"), _("Ballpoint pen, blue"), _("Stapler"), _("Printer paper, 500 sheets"), _("Sticky notes"), _("USB drive 32 GB") };
            int[] stock = { 120, 35, 8, 14, 60, 4 };
            int[] reorder = { 40, 50, 5, 20, 30, 10 };
            double[] cost = { 1.8, 0.35, 6.9, 4.5, 1.2, 7.5 };
            for (int i = 0; i < items.length; i++) {
                int r = i + 1;
                s.set_input (r, 0, "SKU-%03d".printf (i + 101));
                s.set_input (r, 1, items[i]);
                s.set_input (r, 2, stock[i].to_string ());
                s.set_input (r, 3, reorder[i].to_string ());
                s.set_input (r, 4, Value.format_number_general_full (cost[i]));
                s.set_input (r, 5, "=C%d*E%d".printf (r + 1, r + 1));
                s.set_input (r, 6, "=IF(C%d<=D%d,\"%s\",\"%s\")".printf (r + 1, r + 1, _("Reorder"), _("OK")));
                s.set_style (r, 4, money);
                s.set_style (r, 5, money);
            }
            int t = items.length + 1;
            s.set_input (t, 4, _("Total"));
            s.set_input (t, 5, "=SUM(F2:F%d)".printf (t));
            s.set_style (t, 4, total_style (d, "General"));
            s.set_style (t, 5, total_style (d, money_fmt));
            var low = new CondFormat (new Area (s, 1, 6, items.length, 6), CondKind.EQUAL);
            low.a = _("Reorder");
            var red = new CellStyle ();
            red.fill = "#ffc7ce";
            red.color = "#9c0006";
            low.style = d.book.intern (red);
            s.cond_formats.add (low);
            s.col_widths[1] = 210;
            s.col_widths[3] = 110;
            s.col_widths[5] = 110;
            s.freeze_rows = 1;
            s.filter = new Filter (new Area (s, 0, 0, items.length, 6));
            return finish (d);
        }

        public static Document calendar () {
            var d = new Document ();
            var s = d.book.sheets[0];
            s.name = _("Calendar");
            s.set_input (0, 0, "=DATE(YEAR(TODAY()),MONTH(TODAY()),1)");
            var ts = new CellStyle ();
            ts.bold = true;
            ts.font_size = 20;
            ts.color = "#2a78d6";
            ts.number_format = "mmmm yyyy";
            ts.halign = HAlign.LEFT;
            s.set_style (0, 0, d.book.intern (ts));
            s.merges.add (new Area (s, 0, 0, 0, 6));
            s.row_heights[0] = 44;
            var names = new string[7];
            var monday = new DateTime.local (2024, 1, 1, 0, 0, 0);
            for (int i = 0; i < 7; i++) names[i] = monday.add_days (i).format ("%a");
            header (d, s, 1, names, "#2a78d6");
            var day = new CellStyle ();
            day.number_format = "d";
            day.valign = VAlign.TOP;
            day.halign = HAlign.RIGHT;
            day.bold = true;
            day.top = new Border (BorderStyle.THIN, "#bfbfbf");
            day.bottom = new Border (BorderStyle.THIN, "#bfbfbf");
            day.left = new Border (BorderStyle.THIN, "#bfbfbf");
            day.right = new Border (BorderStyle.THIN, "#bfbfbf");
            int day_style = d.book.intern (day);
            for (int w = 0; w < 6; w++) {
                int r = 2 + w;
                for (int c = 0; c < 7; c++) {
                    int offset = w * 7 + c;
                    s.set_input (r, c, "=IF(MONTH($A$1-WEEKDAY($A$1,3)+%d)=MONTH($A$1),$A$1-WEEKDAY($A$1,3)+%d,\"\")".printf (offset, offset));
                    s.set_style (r, c, day_style);
                }
                s.row_heights[r] = 64;
            }
            var today = new CondFormat (new Area (s, 2, 0, 7, 6), CondKind.FORMULA);
            today.a = "=A3=TODAY()";
            var hl = new CellStyle ();
            hl.fill = "#dbe8fb";
            hl.color = "#1f5fb0";
            today.style = d.book.intern (hl);
            s.cond_formats.add (today);
            for (int c = 0; c < 7; c++) s.col_widths[c] = 110;
            s.show_grid = false;
            return finish (d);
        }
    }
}
