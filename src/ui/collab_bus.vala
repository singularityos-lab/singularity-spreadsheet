namespace Singularity.Apps.Spreadsheet {

    [DBus (name = "dev.sinty.Collab.Sheet1")]
    public class SheetCollabBus : Object {
        private unowned SpreadsheetApp app;

        public SheetCollabBus (SpreadsheetApp app) {
            this.app = app;
        }

        public void receive (string title, string payload, string from) throws Error {
            var state = LiveSession.decode_text (payload);
            if (state == null) throw new IOError.INVALID_DATA ("not a spreadsheet");
            int64 clock;
            int sv;
            var book = LiveSheetSync.book_from (state, out clock, out sv);
            var w = new SpreadsheetWindow (app);
            w.present ();
            w.load_document (new Document.with_book (book, null));
        }

        public void join (string session, string title, string snapshot, string role, string from) throws Error {
            var w = new SpreadsheetWindow (app);
            w.present ();
            LiveUi.join_collab (w, session, snapshot, from);
        }
    }
}
