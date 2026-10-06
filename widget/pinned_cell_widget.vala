using Gtk;
using GLib;
using Singularity;
using Singularity.Apps.Spreadsheet;

namespace SingularitySpreadsheetWidget {

    public class PinnedCellProvider : Object, OverviewWidgetProvider {
        public string id           { get { return "spreadsheet.pinned-cell"; } }
        public string provider_id  { get { return "dev.sinty.spreadsheet"; } }
        public string display_name { get { return _("Pinned Cell"); } }
        public string icon_name    { get { return "dev.sinty.spreadsheet"; } }
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) {
                    _sizes = new WidgetSize[2];
                    _sizes[0] = WidgetSize(2, 1);
                    _sizes[1] = WidgetSize(2, 2);
                }
                return _sizes;
            }
        }
        private WidgetSize[] _sizes;

        public Gtk.Widget create_instance(string instance_id, WidgetSize size, Variant? config) {
            var instance = new PinnedCellInstance(PinnedCell.from_variant(config));
            instance.configure_requested.connect(() => configure_instance(instance_id));
            return instance;
        }

        public bool can_configure(string instance_id) {
            return true;
        }

        public void configure_instance(string instance_id) {
            var registry = OverviewWidgetRegistry.get_default();
            var current = PinnedCell.from_variant(registry.get_instance_config(instance_id));
            var dialog = new PinnedCellDialog(current);
            dialog.chosen.connect((pin) => registry.save_instance_config(instance_id, pin.to_variant()));
            dialog.open_dialog();
        }
    }

    public class PinnedCell : Object {
        public string path = "";
        public string cell = "";
        public string label = "";

        public bool is_set {
            get { return path != "" && cell != ""; }
        }

        public static PinnedCell from_variant(Variant? config) {
            var pin = new PinnedCell();
            if (config == null || !config.is_of_type(new VariantType("a{sv}"))) return pin;
            var dict = new VariantDict(config);
            dict.lookup("path", "s", out pin.path);
            dict.lookup("cell", "s", out pin.cell);
            dict.lookup("label", "s", out pin.label);
            return pin;
        }

        public Variant to_variant() {
            var dict = new VariantDict();
            dict.insert_value("path", new Variant.string(path));
            dict.insert_value("cell", new Variant.string(cell));
            dict.insert_value("label", new Variant.string(label));
            return dict.end();
        }

        public static bool split(string reference, out string sheet, out int row, out int col) {
            sheet = "";
            string text = reference.strip();
            int bang = text.last_index_of("!");
            if (bang >= 0) {
                sheet = text.substring(0, bang);
                if (sheet.has_prefix("'") && sheet.has_suffix("'") && sheet.length >= 2)
                    sheet = sheet.substring(1, sheet.length - 2).replace("''", "'");
                text = text.substring(bang + 1);
            }
            bool abs_row, abs_col;
            return Address.parse_cell(text.up(), out row, out col, out abs_row, out abs_col);
        }
    }

    public class PinnedCellInstance : Gtk.Box {
        private static Mutex load_lock;
        public signal void configure_requested();
        private PinnedCell pin;
        private Gtk.Label header;
        private Gtk.Label value_lbl;
        private Gtk.Label source_lbl;
        private FileMonitor? monitor = null;
        private uint reload_id = 0;
        private bool alive = true;

        public PinnedCellInstance(PinnedCell pin) {
            Object(orientation: Orientation.VERTICAL, spacing: 2);
            this.pin = pin;
            add_css_class("overview-widget-card");
            overflow = Overflow.HIDDEN;
            hexpand = true; vexpand = true;

            header = new Gtk.Label("");
            header.add_css_class("caption-heading");
            header.opacity = 0.7;
            header.halign = Align.START;
            header.ellipsize = Pango.EllipsizeMode.END;
            header.margin_start = 14; header.margin_end = 14; header.margin_top = 10;
            append(header);

            value_lbl = new Gtk.Label("");
            value_lbl.add_css_class("title-1");
            value_lbl.halign = Align.START;
            value_lbl.valign = Align.CENTER;
            value_lbl.vexpand = true;
            value_lbl.ellipsize = Pango.EllipsizeMode.END;
            value_lbl.margin_start = 14; value_lbl.margin_end = 14;
            append(value_lbl);

            source_lbl = new Gtk.Label("");
            source_lbl.add_css_class("caption");
            source_lbl.add_css_class("dim-label");
            source_lbl.halign = Align.START;
            source_lbl.ellipsize = Pango.EllipsizeMode.MIDDLE;
            source_lbl.margin_start = 14; source_lbl.margin_end = 14; source_lbl.margin_bottom = 10;
            append(source_lbl);

            var click = new GestureClick();
            click.released.connect(() => {
                if (!pin.is_set) configure_requested();
                else open_file();
            });
            add_controller(click);

            if (!pin.is_set) {
                header.label = _("Pinned Cell");
                value_lbl.label = _("Choose a Cell");
                value_lbl.remove_css_class("title-1");
                value_lbl.add_css_class("title-3");
                source_lbl.label = _("Click to pick a spreadsheet and a cell");
                return;
            }

            header.label = pin.label != "" ? pin.label : pin.cell.up();
            source_lbl.label = "%s · %s".printf(Path.get_basename(pin.path), pin.cell.up());
            tooltip_text = _("Open %s").printf(Path.get_basename(pin.path));
            try {
                monitor = File.new_for_path(pin.path).monitor_file(FileMonitorFlags.WATCH_MOVES, null);
                monitor.changed.connect(() => schedule_reload());
            } catch (Error e) {
                warning("pinned cell: cannot watch %s: %s", pin.path, e.message);
            }
            reload();
            destroy.connect(() => {
                alive = false;
                if (reload_id != 0) { GLib.Source.remove(reload_id); reload_id = 0; }
                if (monitor != null) monitor.cancel();
            });
        }

        private void schedule_reload() {
            if (reload_id != 0) GLib.Source.remove(reload_id);
            reload_id = GLib.Timeout.add(600, () => {
                reload_id = 0;
                reload();
                return GLib.Source.REMOVE;
            });
        }

        private void open_file() {
            try {
                var info = new DesktopAppInfo("dev.sinty.spreadsheet.desktop");
                var uris = new List<string>();
                uris.append(File.new_for_path(pin.path).get_uri());
                if (info != null) info.launch_uris(uris, Gdk.Display.get_default().get_app_launch_context());
            } catch (Error e) {
                warning("pinned cell: cannot open %s: %s", pin.path, e.message);
            }
        }

        private void reload() {
            string path = pin.path;
            string cell = pin.cell;
            new Thread<bool>("pinned-cell", () => {
                string text;
                bool ok = read_cell(path, cell, out text);
                Idle.add(() => {
                    if (!alive) return GLib.Source.REMOVE;
                    value_lbl.label = text;
                    value_lbl.opacity = ok ? 1.0 : 0.6;
                    if (ok) {
                        value_lbl.remove_css_class("title-3");
                        value_lbl.add_css_class("title-1");
                    } else {
                        value_lbl.remove_css_class("title-1");
                        value_lbl.add_css_class("title-3");
                    }
                    return GLib.Source.REMOVE;
                });
                return ok;
            });
        }

        private static bool read_cell(string path, string cell, out string text) {
            load_lock.lock();
            bool ok = false;
            text = "";
            try {
                string sheet_name;
                int row, col;
                if (!PinnedCell.split(cell, out sheet_name, out row, out col)) {
                    text = _("Not a cell");
                } else if (!FileUtils.test(path, FileTest.EXISTS)) {
                    text = _("File not found");
                } else {
                    var doc = Document.open(path);
                    var book = doc.book;
                    book.recalculate();
                    Sheet? sheet = sheet_name != "" ? book.find_sheet(sheet_name) : (book.sheets.size > 0 ? book.sheets[0] : null);
                    if (sheet == null) {
                        text = _("No sheet named %s").printf(sheet_name);
                    } else {
                        string color;
                        text = NumberFormat.format_value(sheet.value_at(row, col), sheet.style_at(row, col).number_format, out color, book.date1904);
                        if (text == "") text = _("Empty");
                        ok = true;
                    }
                }
            } catch (Error e) {
                text = _("Could not read the file");
            }
            load_lock.unlock();
            return ok;
        }
    }

    public class PinnedCellDialog : Singularity.Shell.ShellDialog {
        public signal void chosen(PinnedCell pin);
        private Gee.HashMap<string, string> paths = new Gee.HashMap<string, string>();
        private string chosen_path;
        private Singularity.Widgets.EntryRow cell_row;
        private Singularity.Widgets.EntryRow label_row;
        private Gtk.Label error_lbl;
        private Gtk.Button save_btn;

        public PinnedCellDialog(PinnedCell current) {
            Object(application: GLib.Application.get_default() as Gtk.Application,
                   anchor_top: true, anchor_bottom: true, anchor_left: true, anchor_right: true);
            chosen_path = current.path;

            var box = new Box(Orientation.VERTICAL, 16);
            box.set_size_request(420, -1);
            box.margin_top = 24; box.margin_bottom = 24;
            box.margin_start = 24; box.margin_end = 24;

            var group = new Singularity.Widgets.PreferencesGroup();
            group.title = _("Pinned Cell");
            group.description = _("Show the value of one cell of a spreadsheet you opened recently.");

            string[] names = {};
            string[] folders = {};
            string current_name = "";
            foreach (string path in recent_sheets(current.path)) {
                string name = Path.get_basename(path);
                string folder = friendly_folder(path);
                if (paths.has_key(name)) name = "%s (%s)".printf(name, folder);
                paths[name] = path;
                names += name;
                folders += folder;
                if (path == current.path) current_name = name;
            }
            if (names.length == 0) {
                var none = new Singularity.Widgets.ActionRow(_("No Recent Spreadsheets"),
                    _("Open a spreadsheet in Spreadsheet first, then pin one of its cells."));
                group.add_row(none);
            } else {
                if (current_name == "") {
                    current_name = names[0];
                    chosen_path = paths[names[0]];
                }
                var file_row = new Singularity.Widgets.SelectionRow.with_details(_("Spreadsheet"), names, folders, null, current_name);
                file_row.selected.connect((item) => {
                    if (paths.has_key(item)) chosen_path = paths[item];
                    validate();
                });
                group.add_row(file_row);
            }

            cell_row = new Singularity.Widgets.EntryRow(_("Cell, such as B7 or Budget!C4"));
            cell_row.text = current.cell;
            cell_row.entry_changed.connect(() => validate());
            cell_row.entry_activated.connect(() => save());
            group.add_row(cell_row);

            label_row = new Singularity.Widgets.EntryRow(_("Label (optional)"));
            label_row.text = current.label;
            label_row.entry_activated.connect(() => save());
            group.add_row(label_row);
            box.append(group);

            error_lbl = new Gtk.Label("");
            error_lbl.add_css_class("caption");
            error_lbl.add_css_class("error");
            error_lbl.halign = Align.START;
            error_lbl.visible = false;
            box.append(error_lbl);

            var buttons = new Box(Orientation.HORIZONTAL, 8);
            buttons.halign = Align.END;
            var cancel_btn = new Button.with_label(_("Cancel"));
            cancel_btn.clicked.connect(() => close_dialog());
            save_btn = new Button.with_label(_("Pin"));
            save_btn.add_css_class("suggested-action");
            save_btn.clicked.connect(() => save());
            buttons.append(cancel_btn);
            buttons.append(save_btn);
            box.append(buttons);

            content_box.append(box);
            validate();
        }

        private bool validate() {
            string sheet;
            int row, col;
            bool has_file = chosen_path != "";
            bool has_cell = cell_row.text.strip() != "";
            bool valid_cell = has_cell && PinnedCell.split(cell_row.text, out sheet, out row, out col);
            error_lbl.visible = has_cell && !valid_cell;
            error_lbl.label = _("Write a cell like B7, or a sheet and a cell like Budget!C4.");
            save_btn.sensitive = has_file && valid_cell;
            return save_btn.sensitive;
        }

        private void save() {
            if (!validate()) return;
            var pin = new PinnedCell();
            pin.path = chosen_path;
            pin.cell = cell_row.text.strip();
            pin.label = label_row.text.strip();
            chosen(pin);
            close_dialog();
        }

        public override void close_dialog() {
            base.close_dialog();
            destroy();
        }

        private static string[] recent_sheets(string current) {
            var items = new Gee.ArrayList<RecentInfo>();
            foreach (var info in RecentManager.get_default().get_items()) {
                string uri = info.get_uri().down();
                bool sheet = uri.has_suffix(".xlsx") || uri.has_suffix(".xlsm") || uri.has_suffix(".ods")
                    || uri.has_suffix(".csv") || uri.has_suffix(".tsv");
                if (sheet && info.is_local() && info.exists()) items.add(info);
            }
            items.sort((a, b) => b.get_modified().compare(a.get_modified()));
            string[] result = {};
            if (current != "" && FileUtils.test(current, FileTest.EXISTS)) result += current;
            foreach (var info in items) {
                if (result.length >= 12) break;
                string? path = File.new_for_uri(info.get_uri()).get_path();
                if (path == null || path in result) continue;
                result += path;
            }
            return result;
        }

        private static string friendly_folder(string path) {
            string dir = Path.get_dirname(path);
            string home = Environment.get_home_dir();
            if (dir.has_prefix(home)) dir = "~" + dir.substring(home.length);
            return dir;
        }
    }

    [CCode (cname = "singularity_spreadsheet_widget_new")]
    public static Object singularity_spreadsheet_widget_new() {
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link("/proc/self/exe");
            locale_dir = Path.build_filename(Path.get_dirname(Path.get_dirname(exe)), "share", "locale");
        } catch (Error e) { }
        Intl.bindtextdomain("singularity-spreadsheet", locale_dir);
        Intl.bind_textdomain_codeset("singularity-spreadsheet", "UTF-8");
        return new PinnedCellProvider();
    }
}
