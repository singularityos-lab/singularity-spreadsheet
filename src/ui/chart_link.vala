namespace Singularity.Apps.Spreadsheet {

    public class ChartLink : Object {
        public const string MIME = "application/x-singularity-chart-link";

        public static void copy (Gtk.Widget widget, Document doc, Sheet sheet, Chart chart) {
            var spec = ChartResolve.resolve (doc.book, sheet, chart);
            string payload = "%s\t%s\t%s\n%s".printf (doc.path, sheet.name, ChartLookup.id_of (sheet, chart), Singularity.Charts.DrawingML.write_chart (spec));
            var painter = new Singularity.Charts.ChartPainter ();
            var surface = painter.render_image (spec, (int) chart.width, (int) chart.height, 2);
            Gdk.ContentProvider[] providers = { new Gdk.ContentProvider.for_bytes (MIME, new Bytes (payload.data)) };
            var mem = new MemoryOutputStream.resizable ();
            if (surface.write_to_png_stream ((data) => {
                try {
                    size_t n;
                    mem.write_all (data, out n);
                } catch (Error e) {
                    return Cairo.Status.WRITE_ERROR;
                }
                return Cairo.Status.SUCCESS;
            }) == Cairo.Status.SUCCESS) {
                try {
                    mem.close ();
                    providers += new Gdk.ContentProvider.for_bytes ("image/png", mem.steal_as_bytes ());
                } catch (Error e) {
                }
            }
            widget.get_clipboard ().set_content (new Gdk.ContentProvider.union (providers));
        }
    }

    [DBus (name = "dev.sinty.Spreadsheet1")]
    public class ChartBus : Object {
        private unowned GLib.Application app;

        public ChartBus (GLib.Application app) {
            this.app = app;
        }

        public string chart_xml (string path, string sheet, string chart) throws Error {
            app.hold ();
            try {
                return ChartLookup.xml_for (path, sheet, chart);
            } finally {
                app.release ();
            }
        }
    }
}
