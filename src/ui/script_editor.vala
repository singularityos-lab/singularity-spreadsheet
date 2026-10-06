using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Spreadsheet {

    public class WindowScriptHost : ScriptHost {
        private SpreadsheetWindow win;

        public WindowScriptHost (SpreadsheetWindow win) {
            this.win = win;
            active = win.grid.sheet;
            selected = win.grid.selection;
        }

        private void wait_for (Gtk.Window dlg) {
            var loop = new MainLoop ();
            dlg.close_request.connect (() => {
                if (loop.is_running ()) loop.quit ();
                return false;
            });
            dlg.present ();
            loop.run ();
        }

        public override void message (string text, string title) {
            messages.add (text);
            var dlg = new ConfirmDialog.message ((Gtk.Application) win.application, title, null, text);
            dlg.transient_for = win;
            dlg.modal = true;
            var loop = new MainLoop ();
            dlg.response.connect (() => {
                if (loop.is_running ()) loop.quit ();
            });
            dlg.close_request.connect (() => {
                if (loop.is_running ()) loop.quit ();
                return false;
            });
            dlg.present ();
            loop.run ();
            dlg.close ();
        }

        public override int ask (string text, string title, int buttons) {
            int kind = buttons & 7;
            if (kind == 0) {
                message (text, title);
                return 1;
            }
            messages.add (text);
            string primary = kind == 3 || kind == 4 ? _("Yes") : (kind == 2 || kind == 5 ? _("Retry") : _("OK"));
            var dlg = new ConfirmDialog ((Gtk.Application) win.application, title, null, text, primary, ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = win;
            dlg.modal = true;
            if (kind == 4) {
                dlg.has_cancel = false;
                dlg.set_secondary (_("No"));
            } else if (kind == 3) {
                dlg.set_secondary (_("No"));
            } else if (kind == 2) {
                dlg.set_secondary (_("Ignore"));
            }
            var loop = new MainLoop ();
            int result = 2;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) result = kind == 3 || kind == 4 ? 6 : (kind == 2 || kind == 5 ? 4 : 1);
                else if (r == ConfirmDialog.Response.SECONDARY) result = kind == 2 ? 5 : 7;
                else result = kind == 4 ? 7 : (kind == 2 ? 3 : 2);
                if (loop.is_running ()) loop.quit ();
            });
            dlg.present ();
            loop.run ();
            return result;
        }

        public override string? input (string prompt, string title, string def) {
            var dlg = ToolDialogs.make (win, title, 420, 220);
            dlg.modal = true;
            var box = ToolDialogs.scroll_box (dlg.content_box);
            var g = new PreferencesGroup ();
            var entry = new EntryRow (prompt);
            entry.text = def;
            g.add_row (entry);
            box.append (g);
            string? result = null;
            ToolDialogs.footer (dlg, _("OK"), () => result = entry.text);
            entry.entry_activated.connect (() => {
                result = entry.text;
                dlg.close ();
            });
            wait_for (dlg);
            return result;
        }

        public override void select (Sheet s, Area a) {
            base.select (s, a);
            win.go_to (s, a.r1, a.c1);
            win.grid.select_area (a);
        }

        public override void activate_sheet (Sheet s) {
            base.activate_sheet (s);
            win.go_to (s, 0, 0);
        }

        public override bool export_pdf (Sheet s, string path) {
            var sp = new SheetPrinter (s, null);
            if (win.doc.path != null) {
                sp.file_name = Path.get_basename (win.doc.path);
                sp.file_path = Path.get_dirname (win.doc.path);
            }
            sp.export_pdf (path);
            return true;
        }

        public override bool run_action (string name) {
            if (win.lookup_action (name) == null) return false;
            win.run (name);
            active = win.grid.sheet;
            selected = win.grid.selection;
            return true;
        }
    }

    public class MacroSession : Object {
        public MacroRecorder recorder;
        public ulong committed_handler;
        public Gee.ArrayList<ulong> action_handlers = new Gee.ArrayList<ulong> ();
        public Gee.ArrayList<SimpleAction> actions = new Gee.ArrayList<SimpleAction> ();
        public bool pending_book;
        public Document doc;
    }

    public class MacroUi {
        private static Gee.HashMap<SpreadsheetWindow, MacroSession>? sessions;

        public static bool is_recording (SpreadsheetWindow win) {
            return sessions != null && sessions.has_key (win);
        }

        private static Gee.HashSet<Document>? trusted;
        private static Gee.HashSet<Document>? declined;

        public static bool needs_trust (Document doc) {
            if (trusted != null && trusted.contains (doc)) return false;
            return doc.book.vba != null || doc.book.scripts.from_file;
        }

        private static void enable (SpreadsheetWindow win, Document doc) {
            if (trusted == null) trusted = new Gee.HashSet<Document> ();
            trusted.add (doc);
            try {
                doc.book.udf = new MacroUdf (doc);
            } catch (ScriptError e) {
                doc.book.udf = null;
            }
            doc.book.recalculate ();
            if (win.grid != null) win.grid.refresh ();
        }

        public delegate void Then ();

        public static void confirm (SpreadsheetWindow win, owned Then? then, bool on_open = false) {
            var doc = win.doc;
            if (!needs_trust (doc)) {
                if (then != null) then ();
                return;
            }
            if (on_open && declined != null && declined.contains (doc)) return;
            int count = 0;
            if (doc.book.vba != null) foreach (var m in doc.book.vba.modules) count += Script.list_subs (m.code ()).size;
            count += doc.book.scripts.macro_names ().size;
            string body = _("This file contains macros (%d). Macros can change the workbook, but they run in a sandbox without access to your files, programs or the network. Excel VBA code is interpreted by Spreadsheet; nothing runs automatically, not even Workbook_Open. Enable them only if you trust where the file comes from.").printf (count);
            var dlg = new ConfirmDialog ((Gtk.Application) win.application, _("This File Contains Macros"), "dev.sinty.spreadsheet", body, _("Enable Macros"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = win;
            dlg.modal = true;
            dlg.has_cancel = false;
            dlg.set_secondary (_("Keep Disabled"));
            Then? next = (owned) then;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) {
                    enable (win, doc);
                    if (next != null) next ();
                } else {
                    if (declined == null) declined = new Gee.HashSet<Document> ();
                    declined.add (doc);
                }
            });
            dlg.present ();
        }

        public static void run (SpreadsheetWindow win, string name) {
            if (needs_trust (win.doc)) {
                confirm (win, () => run (win, name));
                return;
            }
            var host = new WindowScriptHost (win);
            var runner = new ScriptRunner (win.doc, host);
            try {
                runner.run_macro (name);
            } catch (ScriptError e) {
                win.show_error (_("Macro Error"), _("\"%s\" stopped at line %s").printf (name, e.message));
            }
            win.sheets_updated ();
        }

        public static void apply_shortcuts (SpreadsheetWindow win) {
            var app = win.application as Gtk.Application;
            if (app == null || win.doc == null) return;
            foreach (var e in win.doc.book.scripts.shortcuts.entries) {
                if (e.value == "") continue;
                app.set_accels_for_action ("win.run-macro(%s)".printf (new Variant.string (e.key).print (false)), { e.value });
            }
        }

        private static string unique_name (ScriptStore st, string base_name) {
            var names = st.macro_names ();
            for (int i = 1; ; i++) {
                string n = "%s%d".printf (base_name, i);
                bool used = false;
                foreach (string x in names) if (x.casefold () == n.casefold ()) used = true;
                if (!used) return n;
            }
        }

        private static bool valid_name (string n) {
            if (n == "" || !(n[0].isalpha () || n[0] == '_')) return false;
            for (int i = 0; i < n.length; i++) if (!(n[i].isalnum () || n[i] == '_')) return false;
            return true;
        }

        public static void toggle_recording (SpreadsheetWindow win) {
            if (sessions == null) sessions = new Gee.HashMap<SpreadsheetWindow, MacroSession> ();
            if (sessions.has_key (win)) {
                stop_recording (win);
                return;
            }
            var ses = new MacroSession ();
            ses.doc = win.doc;
            ses.recorder = new MacroRecorder (win.doc, win.grid.sheet);
            ses.committed_handler = win.doc.committed.connect ((step) => {
                if (step.before.area != null && step.sheet != null) {
                    ses.recorder.record_cells (step.sheet, step.before.cells, step.after.cells);
                } else {
                    ses.pending_book = true;
                }
            });
            string[] skip = { "undo", "redo", "macro-record", "macros", "script-editor", "run-macro", "save", "save-as", "print", "export-pdf", "export-csv", "close", "close-doc", "find", "goto", "copy" };
            foreach (string name in win.list_actions ()) {
                if (name in skip) continue;
                var a = win.lookup_action (name) as SimpleAction;
                if (a == null || a.parameter_type != null) continue;
                string an = name;
                ulong h = a.activate.connect (() => {
                    if (ses.pending_book) {
                        ses.recorder.action (an);
                        ses.pending_book = false;
                    }
                });
                ses.actions.add (a);
                ses.action_handlers.add (h);
            }
            sessions[win] = ses;
            if (win.extras != null) {
                win.extras.recording = true;
                win.grid.queue_draw ();
            }
        }

        private static void stop_recording (SpreadsheetWindow win) {
            var ses = sessions[win];
            sessions.unset (win);
            ses.doc.disconnect (ses.committed_handler);
            for (int i = 0; i < ses.actions.size; i++) ses.actions[i].disconnect (ses.action_handlers[i]);
            if (win.extras != null) {
                win.extras.recording = false;
                win.grid.queue_draw ();
            }
            if (ses.doc != win.doc) return;
            var book = win.doc.book;
            var dlg = ToolDialogs.make (win, _("Save Recorded Macro"), 460, 380);
            var box = ToolDialogs.scroll_box (dlg.content_box);
            var g = new PreferencesGroup (null, ngettext ("%d step recorded", "%d steps recorded", ses.recorder.count).printf (ses.recorder.count));
            var name = new EntryRow (_("Macro name"));
            name.text = unique_name (book.scripts, "Macro");
            var key = new EntryRow (_("Shortcut letter with Ctrl+Shift (optional)"));
            g.add_row (name);
            g.add_row (key);
            box.append (g);
            ToolDialogs.footer (dlg, _("Save"), () => {
                string n = name.text.strip ().replace (" ", "_");
                if (!valid_name (n)) n = unique_name (book.scripts, "Macro");
                var m = book.scripts.module ("Recorded");
                m.source = (m.source.strip () == "" ? "" : m.source.strip () + "\n\n") + ses.recorder.finish (n);
                string k = key.text.strip ().down ();
                if (k.length == 1 && k[0].isalpha ()) book.scripts.shortcuts[n] = "<Control><Shift>" + k;
                win.doc.modified = true;
                apply_shortcuts (win);
            });
            dlg.open_dialog ();
        }

        public static void macros_dialog (SpreadsheetWindow win) {
            var book = win.doc.book;
            var dlg = ToolDialogs.make (win, _("Macros"), 560, 560);
            var box = ToolDialogs.scroll_box (dlg.content_box);
            var intro = new PreferencesGroup (null, _("Macros are written in Visual Basic. Spreadsheet runs Excel VBA macros and its own modules in a sandbox: they work with ranges, sheets and every worksheet function but cannot touch files, programs or the network."));
            var rec = new ActionRow (is_recording (win) ? _("Stop Recording") : _("Record New Macro"), _("Turns what you do in the sheet into a macro"));
            var rec_btn = new Button.with_label (is_recording (win) ? _("Stop") : _("Record"));
            rec_btn.valign = Align.CENTER;
            rec_btn.clicked.connect (() => {
                dlg.close ();
                toggle_recording (win);
            });
            rec.add_suffix (rec_btn);
            intro.add_row (rec);
            var ed = new ActionRow (_("Script Editor"), _("Write and edit macros and functions"));
            var ed_btn = new Button.with_label (_("Open"));
            ed_btn.valign = Align.CENTER;
            ed_btn.clicked.connect (() => {
                dlg.close ();
                editor (win, null);
            });
            ed.add_suffix (ed_btn);
            intro.add_row (ed);
            if (book.vba != null) {
                string state = needs_trust (win.doc) ? _("Macros are disabled for this file until you enable them.") : _("Macros are enabled for this file in this session.");
                intro.add_row (new ActionRow (_("Excel VBA project (%d modules)").printf (book.vba.modules.size), _("Kept unchanged when saved as .xlsm. ") + state));
            }
            box.append (intro);
            var g = new PreferencesGroup (_("Macros in This Workbook"));
            var names = book.scripts.macro_names ();
            var vba_names = new Gee.HashMap<string, string> ();
            if (book.vba != null) {
                foreach (var m in book.vba.modules) {
                    if (m.kind == VbaModuleKind.CLASS) continue;
                    foreach (string sub in Script.list_subs (m.code ())) {
                        names.add (sub);
                        vba_names[sub] = m.name;
                    }
                }
            }
            if (names.size == 0) g.add_row (new ActionRow (_("No macros yet"), _("Record one or write one in the script editor.")));
            foreach (string n in names) {
                string mn = n;
                string sc = book.scripts.shortcuts[mn] ?? "";
                string sub_text = sc != "" ? _("Shortcut: %s").printf (accel_label (sc)) : "";
                if (vba_names.has_key (mn)) sub_text = (sub_text != "" ? sub_text + "  " : "") + _("Excel VBA, module %s").printf (vba_names[mn]);
                var row = new ActionRow (mn, sub_text);
                var run_btn = ToolDialogs.flat ("media-playback-start-symbolic", _("Run"));
                run_btn.clicked.connect (() => {
                    dlg.close ();
                    run (win, mn);
                });
                var edit_btn = ToolDialogs.flat ("document-edit-symbolic", _("Edit"));
                edit_btn.clicked.connect (() => {
                    dlg.close ();
                    editor (win, mn);
                });
                var key_btn = ToolDialogs.flat ("input-keyboard-symbolic", _("Shortcut"));
                key_btn.clicked.connect (() => {
                    dlg.close ();
                    shortcut_dialog (win, mn);
                });
                var del_btn = ToolDialogs.flat ("user-trash-symbolic", _("Delete"));
                del_btn.sensitive = !vba_names.has_key (mn);
                del_btn.clicked.connect (() => {
                    book.scripts.remove_macro (mn);
                    win.doc.modified = true;
                    g.remove_row (row);
                });
                row.add_suffix (run_btn);
                row.add_suffix (edit_btn);
                row.add_suffix (key_btn);
                row.add_suffix (del_btn);
                g.add_row (row);
            }
            box.append (g);
            ToolDialogs.close_footer (dlg);
            dlg.open_dialog ();
        }

        private static string accel_label (string accel) {
            uint key;
            Gdk.ModifierType mods;
            if (!Gtk.accelerator_parse (accel, out key, out mods)) return accel;
            return Gtk.accelerator_get_label (key, mods);
        }

        private static void shortcut_dialog (SpreadsheetWindow win, string macro) {
            var book = win.doc.book;
            var dlg = ToolDialogs.make (win, _("Shortcut for %s").printf (macro), 420, 240);
            var box = ToolDialogs.scroll_box (dlg.content_box);
            var g = new PreferencesGroup (null, _("The macro runs with Ctrl+Shift and this letter. Leave empty to remove the shortcut."));
            var key = new EntryRow (_("Letter"));
            string cur = book.scripts.shortcuts[macro] ?? "";
            key.text = cur.has_prefix ("<Control><Shift>") ? cur.substring (16) : "";
            g.add_row (key);
            box.append (g);
            ToolDialogs.footer (dlg, _("Save"), () => {
                string k = key.text.strip ().down ();
                var app = win.application as Gtk.Application;
                if (app != null && cur != "") app.set_accels_for_action ("win.run-macro(%s)".printf (new Variant.string (macro).print (false)), {});
                if (k.length == 1 && k[0].isalpha ()) book.scripts.shortcuts[macro] = "<Control><Shift>" + k;
                else book.scripts.shortcuts.unset (macro);
                win.doc.modified = true;
                apply_shortcuts (win);
            });
            dlg.open_dialog ();
        }

        public static void editor (SpreadsheetWindow win, string? macro) {
            var book = win.doc.book;
            if (book.scripts.modules.size == 0 && book.vba == null) book.scripts.module ("Module1").source = "Sub Hello()\n    MsgBox \"Hello from \" & ActiveSheet.Name\nEnd Sub\n";
            ScriptModule? module = null;
            VbaModule? vmod = null;
            if (macro != null) module = book.scripts.module_of (macro);
            if (module == null && macro != null && book.vba != null) {
                foreach (var m in book.vba.modules) if (m.kind != VbaModuleKind.CLASS && macro in Script.list_subs (m.code ())) vmod = m;
            }
            if (module == null && vmod == null) {
                if (book.scripts.modules.size > 0) module = book.scripts.modules[0];
                else if (book.vba != null) {
                    foreach (var m in book.vba.modules) if (vmod == null && m.kind == VbaModuleKind.STANDARD) vmod = m;
                    if (vmod == null) vmod = book.vba.modules[0];
                }
            }
            var dlg = ToolDialogs.make (win, _("Script Editor"), 900, 640);
            dlg.modal = false;
            var top = new Box (Orientation.VERTICAL, 8);
            top.margin_start = top.margin_end = 18;
            top.margin_top = 6;
            string[] mods = {};
            var vba_by_label = new Gee.HashMap<string, VbaModule> ();
            foreach (var m in book.scripts.modules) mods += m.name;
            if (book.vba != null) {
                foreach (var m in book.vba.modules) {
                    string kind = m.kind == VbaModuleKind.CLASS ? _("class") : (m.kind == VbaModuleKind.DOCUMENT ? _("document") : _("module"));
                    string lbl = _("%s (Excel VBA %s)").printf (m.name, kind);
                    mods += lbl;
                    vba_by_label[lbl] = m;
                }
            }
            string current_label = module != null ? module.name : "";
            foreach (var e in vba_by_label.entries) if (e.value == vmod) current_label = e.key;
            var g = new PreferencesGroup ();
            var mod_row = new SelectionRow (_("Module"), mods, current_label);
            g.add_row (mod_row);
            top.append (g);
            dlg.content_box.append (top);

            var buffer = new TextBuffer (null);
            var err_tag = buffer.create_tag ("error-line", "background", "#f6c7c7", "paragraph-background", "#f6c7c7");
            var view = new TextView.with_buffer (buffer);
            view.monospace = true;
            view.left_margin = 8;
            view.top_margin = 6;
            view.hexpand = true;
            view.vexpand = true;
            view.wrap_mode = WrapMode.NONE;
            view.accepts_tab = true;
            var numbers = new Label ("1");
            numbers.add_css_class ("monospace");
            numbers.add_css_class ("dim-label");
            numbers.yalign = 0;
            numbers.xalign = 1;
            numbers.margin_top = 6;
            numbers.margin_start = 8;
            numbers.margin_end = 6;
            var row_box = new Box (Orientation.HORIZONTAL, 0);
            row_box.append (numbers);
            row_box.append (view);
            var scroll = new ScrolledWindow ();
            scroll.child = row_box;
            scroll.vexpand = true;
            scroll.margin_start = scroll.margin_end = 18;
            scroll.margin_top = 8;
            scroll.add_css_class ("ss-note-frame");
            dlg.content_box.append (scroll);
            var status = new Label ("");
            status.xalign = 0;
            status.wrap = true;
            status.margin_start = status.margin_end = 18;
            status.margin_top = 6;
            dlg.content_box.append (status);

            bool loading = false;
            ToolDialogs.Apply update_numbers = () => {
                var sb = new StringBuilder ();
                int n = buffer.get_line_count ();
                for (int i = 1; i <= n; i++) {
                    sb.append (i.to_string ());
                    if (i < n) sb.append ("\n");
                }
                numbers.label = sb.str;
            };
            var copy_btn = new Button.with_label (_("Copy to Editable Module"));
            ToolDialogs.Apply show_current = () => {
                loading = true;
                if (vmod != null) {
                    buffer.text = vmod.code ();
                    view.editable = false;
                    copy_btn.visible = true;
                    status.remove_css_class ("error");
                    status.label = vmod.kind == VbaModuleKind.CLASS ? _("Excel VBA class module: shown for reference, class modules are not run.") : _("Excel VBA module, read only: it is saved back unchanged in .xlsm files. Copy it to an editable module to change it.");
                } else if (module != null) {
                    buffer.text = module.source;
                    view.editable = true;
                    copy_btn.visible = false;
                    status.label = "";
                }
                update_numbers ();
                loading = false;
            };
            show_current ();
            buffer.changed.connect (() => {
                update_numbers ();
                if (loading) return;
                TextIter s, e;
                buffer.get_bounds (out s, out e);
                buffer.remove_tag (err_tag, s, e);
                if (module != null && vmod == null) {
                    module.source = buffer.text;
                    win.doc.modified = true;
                }
            });
            if (macro != null) {
                string text = buffer.text;
                int idx = text.down ().index_of ("sub " + macro.down ());
                if (idx >= 0) {
                    TextIter it;
                    buffer.get_iter_at_offset (out it, text.substring (0, idx).char_count ());
                    buffer.place_cursor (it);
                }
            }
            mod_row.selected.connect ((v) => {
                if (vba_by_label.has_key (v)) {
                    vmod = vba_by_label[v];
                    module = null;
                } else {
                    vmod = null;
                    foreach (var m in book.scripts.modules) if (m.name == v) module = m;
                }
                show_current ();
            });
            copy_btn.clicked.connect (() => {
                if (vmod == null) return;
                string base_name = vmod.name + "_Copy";
                string name = base_name;
                for (int i = 2; ; i++) {
                    bool used = false;
                    foreach (var m in book.scripts.modules) if (m.name.casefold () == name.casefold ()) used = true;
                    if (!used) break;
                    name = base_name + i.to_string ();
                }
                book.scripts.module (name).source = vmod.code ();
                win.doc.modified = true;
                dlg.close ();
                editor (win, null);
            });

            ToolDialogs.Apply show_error_line = null;
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.add_css_class ("ss-dialog-footer");
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 8;
            var new_mod = new Button.with_label (_("New Module"));
            new_mod.clicked.connect (() => {
                int i = book.scripts.modules.size + 1;
                while (true) {
                    bool used = false;
                    foreach (var m in book.scripts.modules) if (m.name == "Module%d".printf (i)) used = true;
                    if (!used) break;
                    i++;
                }
                book.scripts.module ("Module%d".printf (i)).source = "Sub NewMacro()\n    \nEnd Sub\n";
                dlg.close ();
                editor (win, "NewMacro");
            });
            bar.append (new_mod);
            bar.append (copy_btn);
            var check = new Button.with_label (_("Check Syntax"));
            bar.append (check);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var close = new Button.with_label (_("Close"));
            close.clicked.connect (() => dlg.close ());
            dlg.set_cancel_button (close);
            var run_btn = new Button.with_label (_("Run Macro"));
            run_btn.add_css_class ("suggested-action");
            bar.append (close);
            bar.append (run_btn);
            dlg.content_box.append (bar);
            copy_btn.visible = vmod != null;

            int error_line = 0;
            show_error_line = () => {
                if (error_line <= 0 || error_line > buffer.get_line_count ()) return;
                TextIter s, e;
                buffer.get_iter_at_line (out s, error_line - 1);
                e = s;
                e.forward_to_line_end ();
                buffer.apply_tag (err_tag, s, e);
                buffer.place_cursor (s);
                view.scroll_to_iter (s, 0.1, false, 0, 0);
            };
            check.clicked.connect (() => {
                try {
                    var sc = Script.parse_lenient (buffer.text);
                    if (sc.problems.size > 0) {
                        status.add_css_class ("error");
                        status.label = string.joinv ("\n", sc.problems.to_array ());
                        error_line = int.parse (sc.problems[0]);
                        show_error_line ();
                        return;
                    }
                    status.remove_css_class ("error");
                    status.label = _("No syntax errors. Macros: %s").printf (string.joinv (", ", Script.list_subs (buffer.text).to_array ()));
                } catch (ScriptError e) {
                    status.add_css_class ("error");
                    status.label = _("Line %s").printf (e.message);
                    error_line = int.parse (e.message);
                    show_error_line ();
                }
            });
            run_btn.clicked.connect (() => {
                TextIter cur;
                buffer.get_iter_at_mark (out cur, buffer.get_insert ());
                int line = cur.get_line ();
                string? target = null;
                string[] lines = buffer.text.split ("\n");
                for (int i = int.min (line, lines.length - 1); i >= 0; i--) {
                    var subs = Script.list_subs (lines[i]);
                    if (subs.size > 0) {
                        target = subs[0];
                        break;
                    }
                }
                if (target == null) {
                    var all = Script.list_subs (buffer.text);
                    if (all.size > 0) target = all[0];
                }
                if (target == null) {
                    status.add_css_class ("error");
                    status.label = _("Write a Sub without parameters to run it.");
                    return;
                }
                string t = target;
                ToolDialogs.Apply go = () => {
                    var host = new WindowScriptHost (win);
                    var runner = new ScriptRunner (win.doc, host);
                    try {
                        runner.run_lenient (ScriptRunner.sources (book, true), t);
                        status.remove_css_class ("error");
                        status.label = host.output.size > 0 ? string.joinv ("\n", host.output.to_array ()) : _("%s ran successfully.").printf (t);
                    } catch (ScriptError e) {
                        status.add_css_class ("error");
                        status.label = _("%s stopped at line %s").printf (t, e.message);
                        int global_line = int.parse (e.message);
                        int offset = 0;
                        bool found = false;
                        foreach (var m in book.scripts.modules) {
                            if (m == module && vmod == null) {
                                found = true;
                                break;
                            }
                            offset += m.source.split ("\n").length - (m.source.has_suffix ("\n") ? 1 : 0);
                        }
                        if (!found && book.vba != null) {
                            foreach (var m in book.vba.modules) {
                                if (m.kind == VbaModuleKind.CLASS) continue;
                                if (m == vmod) break;
                                offset += m.code ().split ("\n").length - 1;
                            }
                        }
                        error_line = global_line - offset;
                        show_error_line ();
                    }
                    win.sheets_updated ();
                };
                if (needs_trust (win.doc)) confirm (win, () => go ());
                else go ();
            });
            dlg.open_dialog ();
            view.grab_focus ();
        }
    }
}
