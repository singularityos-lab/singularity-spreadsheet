namespace Singularity.Apps.Spreadsheet {

    public class ChartLookup : Object {
        public static string id_of (Sheet sheet, Chart chart) {
            if (chart.name != "") return chart.name;
            return "#%d".printf (sheet.charts.index_of (chart));
        }

        public static Chart? find (Sheet sheet, string id) {
            if (id.has_prefix ("#")) {
                int i = int.parse (id.substring (1));
                return i >= 0 && i < sheet.charts.size ? sheet.charts[i] : null;
            }
            foreach (var c in sheet.charts) if (c.name == id) return c;
            return null;
        }

        public static string xml_for (string path, string sheet_name, string id) throws Error {
            var doc = Document.open (path);
            doc.book.recalculate ();
            var sheet = doc.book.find_sheet (sheet_name);
            if (sheet == null) throw new IOError.NOT_FOUND (_("The sheet %s is no longer in %s").printf (sheet_name, Path.get_basename (path)));
            var chart = find (sheet, id);
            if (chart == null) throw new IOError.NOT_FOUND (_("The chart is no longer in %s").printf (sheet_name));
            return Singularity.Charts.DrawingML.write_chart (ChartResolve.resolve (doc.book, sheet, chart));
        }
    }
}
