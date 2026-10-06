namespace Singularity.Apps.Spreadsheet {

    public class CommentPost {
        public string id;
        public string author;
        public string text;
        public string date;

        public CommentPost (string author, string text, string? id = null, string? date = null) {
            this.author = author;
            this.text = text;
            this.id = id ?? CommentStore.new_id ();
            this.date = date ?? CommentStore.now_iso ();
        }

        public CommentPost copy () {
            return new CommentPost (author, text, id, date);
        }
    }

    public class CommentThread {
        public int row;
        public int col;
        public bool resolved;
        public Gee.ArrayList<CommentPost> posts = new Gee.ArrayList<CommentPost> ();

        public CommentThread (int row, int col) {
            this.row = row;
            this.col = col;
        }

        public string id {
            get { return posts.size > 0 ? posts[0].id : ""; }
        }

        public CommentThread copy () {
            var t = new CommentThread (row, col);
            t.resolved = resolved;
            foreach (var p in posts) t.posts.add (p.copy ());
            return t;
        }

        public string summary () {
            var sb = new StringBuilder ();
            for (int i = 0; i < posts.size; i++) {
                if (i > 0) sb.append ("\n");
                sb.append (posts[i].author + ": " + posts[i].text);
            }
            return sb.str;
        }
    }

    public class CommentStore {
        public Gee.HashMap<int64?, CommentThread> threads;

        public CommentStore () {
            threads = new Gee.HashMap<int64?, CommentThread> (
                (k) => { int64 v = k; return (uint) (v ^ (v >> 32)); },
                (a, b) => { int64 x = a; int64 y = b; return x == y; });
        }

        public static string new_id () {
            return "{" + Uuid.string_random ().up () + "}";
        }

        public static string now_iso () {
            return new DateTime.now_local ().format ("%Y-%m-%dT%H:%M:%S");
        }

        public static string author_name = "";

        public static string current_author () {
            if (author_name.strip () != "") return author_name.strip ();
            string n = Environment.get_real_name ();
            if (n == "" || n == "Unknown") n = Environment.get_user_name ();
            return n != "" ? n : "Author";
        }

        public int size {
            get { return threads.size; }
        }

        public CommentThread? at (int row, int col) {
            return threads[Sheet.key (row, col)];
        }

        public bool has (int row, int col) {
            return threads.has_key (Sheet.key (row, col));
        }

        public void put (CommentThread t) {
            threads[Sheet.key (t.row, t.col)] = t;
        }

        public void remove (int row, int col) {
            threads.unset (Sheet.key (row, col));
        }

        public Gee.ArrayList<CommentThread> sorted () {
            var list = new Gee.ArrayList<CommentThread> ();
            list.add_all (threads.values);
            list.sort ((a, b) => a.row != b.row ? a.row - b.row : a.col - b.col);
            return list;
        }

        public CommentStore copy () {
            var s = new CommentStore ();
            foreach (var t in threads.values) s.put (t.copy ());
            return s;
        }

        public void shift (bool rows, int at, int count) {
            var list = sorted ();
            threads.clear ();
            foreach (var t in list) {
                int v = rows ? t.row : t.col;
                if (count < 0 && v >= at && v < at - count) continue;
                if (v >= at) v += count;
                if (v < 0 || v >= (rows ? MAX_ROWS : MAX_COLS)) continue;
                if (rows) t.row = v;
                else t.col = v;
                put (t);
            }
        }
    }

    public class Comments {
        public static CommentThread add_post (Document doc, Sheet s, int row, int col, string text, string? author = null) {
            doc.begin_book (s.comments.has (row, col) ? _("Reply") : _("New Comment"), s, new Area.cell (s, row, col));
            var t = s.comments.at (row, col);
            if (t == null) {
                t = new CommentThread (row, col);
                s.comments.put (t);
            }
            t.posts.add (new CommentPost (author ?? CommentStore.current_author (), text));
            doc.commit ();
            return s.comments.at (row, col);
        }

        public static void edit_post (Document doc, Sheet s, int row, int col, string post_id, string text) {
            var t = s.comments.at (row, col);
            if (t == null) return;
            doc.begin_book (_("Edit Comment"), s, new Area.cell (s, row, col));
            t = s.comments.at (row, col);
            foreach (var p in t.posts) if (p.id == post_id) p.text = text;
            doc.commit ();
        }

        public static void delete_post (Document doc, Sheet s, int row, int col, string post_id) {
            var t = s.comments.at (row, col);
            if (t == null) return;
            doc.begin_book (_("Delete Comment"), s, new Area.cell (s, row, col));
            t = s.comments.at (row, col);
            if (t.posts.size > 0 && t.posts[0].id == post_id) {
                s.comments.remove (row, col);
            } else {
                CommentPost? found = null;
                foreach (var p in t.posts) if (p.id == post_id) found = p;
                if (found != null) t.posts.remove (found);
            }
            doc.commit ();
        }

        public static void delete_thread (Document doc, Sheet s, int row, int col) {
            if (!s.comments.has (row, col)) return;
            doc.begin_book (_("Delete Thread"), s, new Area.cell (s, row, col));
            s.comments.remove (row, col);
            doc.commit ();
        }

        public static void set_resolved (Document doc, Sheet s, int row, int col, bool resolved) {
            var t = s.comments.at (row, col);
            if (t == null || t.resolved == resolved) return;
            doc.begin_book (resolved ? _("Resolve Thread") : _("Reopen Thread"), s, new Area.cell (s, row, col));
            s.comments.at (row, col).resolved = resolved;
            doc.commit ();
        }
    }
}
