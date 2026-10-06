using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class AnalysisForm : Object {
        public delegate bool Submit ();
        public AppDialog dlg;
        public Box body;
        private PreferencesGroup? group;
        private Label error_label;
        private Button? ok_button;

        public AnalysisForm (SpreadsheetWindow win, string title, int width = 460, int height = 520) {
            dlg = new AppDialog ((Gtk.Application) win.application, true);
            dlg.set_title (title);
            dlg.transient_for = win;
            dlg.set_default_size (width, height);
            dlg.add_css_class ("ss-dialog");
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.propagate_natural_height = true;
            scroll.min_content_height = int.max (160, height - 170);
            scroll.max_content_height = 640;
            body = new Box (Orientation.VERTICAL, 14);
            body.margin_start = body.margin_end = 18;
            body.margin_top = 6;
            body.margin_bottom = 12;
            scroll.child = body;
            dlg.content_box.append (scroll);
            error_label = new Label ("");
            error_label.add_css_class ("error");
            error_label.wrap = true;
            error_label.xalign = 0;
            error_label.margin_start = error_label.margin_end = 18;
            error_label.visible = false;
            dlg.content_box.append (error_label);
        }

        public PreferencesGroup section (string? title, string? description = null) {
            group = new PreferencesGroup (title, description);
            body.append (group);
            return group;
        }

        private PreferencesGroup current () {
            if (group == null) section (null);
            return group;
        }

        public EntryRow entry (string title, string text = "") {
            var r = new EntryRow (title);
            r.text = text;
            r.entry_activated.connect (() => {
                if (ok_button != null) ok_button.clicked ();
            });
            current ().add_row (r);
            return r;
        }

        public SelectionRow choice (string title, string[] items, string current_item) {
            var r = new SelectionRow (title, items, current_item);
            r.selected.connect ((it) => r.current_value = it);
            current ().add_row (r);
            return r;
        }

        public SwitchRow toggle (string title, bool active, string? subtitle = null) {
            var r = new SwitchRow (title, subtitle, active);
            current ().add_row (r);
            return r;
        }

        public SpinRow spin (string title, double min, double max, double step, double value) {
            var r = new SpinRow (title, null, min, max, step, value);
            current ().add_row (r);
            return r;
        }

        public void fail (string message) {
            error_label.label = message;
            error_label.visible = true;
        }

        public void footer (string label, owned Submit submit, string? extra = null, owned Submit? extra_action = null) {
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.add_css_class ("ss-dialog-footer");
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            if (extra != null) {
                var e = new Button.with_label (extra);
                e.clicked.connect (() => {
                    if (extra_action ()) dlg.close ();
                });
                bar.append (e);
            }
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var ok = new Button.with_label (label);
            ok_button = ok;
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                if (submit ()) dlg.close ();
            });
            if (label != _("Close")) {
                var cancel = new Button.with_label (_("Cancel"));
                cancel.clicked.connect (() => dlg.close ());
                dlg.set_cancel_button (cancel);
                bar.append (cancel);
            } else {
                dlg.set_cancel_button (ok);
            }
            bar.append (ok);
            dlg.content_box.append (bar);
            dlg.default_widget = ok;
        }

        public void open () {
            dlg.open_dialog ();
        }
    }
}
