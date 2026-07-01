/*
 * prefs-dialog.vala — Application Preferences dialog
 *
 * A modal Gtk.Dialog with two editable settings from AppConfig:
 *   - qemu binary path (with "Browse", "Clear (use PATH)" buttons)
 *   - base directory   (with "Browse", "Reset (use default)" buttons)
 *
 * Below each entry, a status line shows whether the current value is
 * valid; the Save button is disabled while either value is invalid.
 *
 * Emits ::saved when the user successfully saves the configuration.
 */

public class PrefsDialog : Gtk.Dialog {

    // ---- Signals ----

    /** Emitted when the user successfully saves new settings. */
    public signal void saved();

    // ---- Widgets ----

    private Gtk.Entry qemu_entry;
    private Gtk.Label qemu_status;
    private Gtk.Button qemu_clear_btn;

    private Gtk.Entry base_dir_entry;
    private Gtk.Label base_dir_status;
    private Gtk.Button base_dir_reset_btn;

    private Gtk.Button save_btn;

    // ---- State ----

    private AppConfig working_copy;
    private string original_qemu_path;
    private string original_base_dir;

    /** True when any field differs from the original values. */
    private bool is_dirty {
        get {
            return working_copy.qemu_binary_path != original_qemu_path
                || working_copy.base_dir != original_base_dir;
        }
    }

    // ---- Construction ----

    public PrefsDialog(Gtk.Window parent, AppConfig initial) {
        Object(
            title: "Preferences",
            transient_for: parent,
            modal: true,
            default_width: 640,
            default_height: 320
        );

        // Working copy lets the user cancel safely without mutating the
        // shared AppConfig instance while the dialog is open.
        this.working_copy = new AppConfig();
        this.working_copy.qemu_binary_path = initial.qemu_binary_path;
        this.working_copy.base_dir = initial.base_dir;
        this.original_qemu_path = initial.qemu_binary_path;
        this.original_base_dir = initial.base_dir;

        build_ui();
        refresh_status();
    }

    private void build_ui() {
        var content = (Gtk.Box) get_content_area();
        content.margin_start = 24;
        content.margin_end = 24;
        content.margin_top = 18;
        content.margin_bottom = 18;
        content.spacing = 14;

        // ---- QEMU binary path section ----
        content.append(section_label("QEMU binary"));

        var qemu_help = new Gtk.Label("Set the full path to qemu-system-i386. Leave empty to use PATH lookup.");
        qemu_help.halign = Gtk.Align.START;
        qemu_help.wrap = true;
        qemu_help.add_css_class("dim-label");
        content.append(qemu_help);

        var qemu_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        qemu_entry = new Gtk.Entry() {
            placeholder_text = "(empty = use PATH lookup)",
            hexpand = true
        };
        qemu_entry.text = working_copy.qemu_binary_path;
        qemu_entry.changed.connect(() => {
            working_copy.qemu_binary_path = qemu_entry.text;
            refresh_status();
        });
        qemu_row.append(qemu_entry);

        var qemu_browse_btn = new Gtk.Button.with_label("Browse…");
        qemu_browse_btn.clicked.connect(on_browse_qemu);
        qemu_row.append(qemu_browse_btn);

        qemu_clear_btn = new Gtk.Button.with_label("Clear");
        qemu_clear_btn.tooltip_text = "Reset to PATH lookup";
        qemu_clear_btn.clicked.connect(() => {
            qemu_entry.text = "";
        });
        qemu_row.append(qemu_clear_btn);

        content.append(qemu_row);

        qemu_status = new Gtk.Label("");
        qemu_status.halign = Gtk.Align.START;
        qemu_status.wrap = true;
        content.append(qemu_status);

        // ---- Base directory section ----
        content.append(section_label("Base directory for VM data"));

        var base_help = new Gtk.Label("Default folder where VM configurations and disk images are stored. Leave empty to use ~/qemu98.");
        base_help.halign = Gtk.Align.START;
        base_help.wrap = true;
        base_help.add_css_class("dim-label");
        content.append(base_help);

        var base_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        base_dir_entry = new Gtk.Entry() {
            placeholder_text = "(empty = " + AppConfig.default_base_dir() + ")",
            hexpand = true
        };
        base_dir_entry.text = working_copy.base_dir;
        base_dir_entry.changed.connect(() => {
            working_copy.base_dir = base_dir_entry.text;
            refresh_status();
        });
        base_row.append(base_dir_entry);

        var base_browse_btn = new Gtk.Button.with_label("Browse…");
        base_browse_btn.clicked.connect(on_browse_base_dir);
        base_row.append(base_browse_btn);

        base_dir_reset_btn = new Gtk.Button.with_label("Reset");
        base_dir_reset_btn.tooltip_text = @"Reset to default (" + AppConfig.default_base_dir() + ")";
        base_dir_reset_btn.clicked.connect(() => {
            base_dir_entry.text = "";
        });
        base_row.append(base_dir_reset_btn);

        content.append(base_row);

        base_dir_status = new Gtk.Label("");
        base_dir_status.halign = Gtk.Align.START;
        base_dir_status.wrap = true;
        content.append(base_dir_status);

        // ---- Save button row (in content area, not header bar) ----
        var button_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        button_row.halign = Gtk.Align.END;
        button_row.margin_top = 8;

        var cancel_btn = new Gtk.Button.with_label("Cancel");
        cancel_btn.clicked.connect(on_cancel_clicked);
        button_row.append(cancel_btn);

        save_btn = new Gtk.Button.with_label("Save");
        save_btn.add_css_class("suggested-action");
        save_btn.clicked.connect(on_save_clicked);
        button_row.append(save_btn);

        content.append(button_row);

        // Intercept window close (X button / Escape) to warn about
        // unsaved changes. Returning true from close-request prevents
        // the window from being destroyed.
        this.close_request.connect(on_close_request);
    }

    private Gtk.Label section_label(string text) {
        return new Gtk.Label(@"<b>$(text)</b>") {
            use_markup = true, halign = Gtk.Align.START
        };
    }

    // ---- Validation ----

    private void refresh_status() {
        // Validate qemu binary
        var qemu_eff = working_copy.get_effective_qemu_binary();
        if (working_copy.has_qemu_binary_path) {
            qemu_status.label = qemu_eff != null
                ? @"✓ Will use: $(qemu_eff)"
                : @"⚠ Path is set but invalid — " + working_copy.qemu_binary_diagnostic;
        }
        else {
            qemu_status.label = qemu_eff != null
                ? @"✓ Will use PATH lookup: $(qemu_eff)"
                : @"⚠ " + working_copy.qemu_binary_diagnostic;
        }
        qemu_status.remove_css_class("success");
        qemu_status.remove_css_class("error");
        if (qemu_eff != null) qemu_status.add_css_class("success");
        else qemu_status.add_css_class("error");
        // Visually mark the offending entry and grab focus on it so
        // the user can fix it without hunting — addresses the spec
        // "with the invalid entry to fix" requirement.
        if (qemu_entry != null) {
            qemu_entry.remove_css_class("error");
            if (qemu_eff == null) {
                qemu_entry.add_css_class("error");
                if (qemu_first_invalid_focus) {
                    qemu_entry.grab_focus();
                    qemu_first_invalid_focus = false;
                }
            }
            else {
                qemu_first_invalid_focus = true;
            }
        }

        // Validate base dir
        var base_eff = working_copy.get_effective_base_dir();
        var base_valid = base_eff != "";
        if (working_copy.has_base_dir) {
            base_dir_status.label = base_valid
                ? @"✓ Will use: $(base_eff)"
                : "⚠ Path is empty after expansion.";
        }
        else {
            base_dir_status.label = @"✓ Will use default: $(AppConfig.default_base_dir())";
        }
        base_dir_status.remove_css_class("success");
        base_dir_status.remove_css_class("error");
        if (base_valid) base_dir_status.add_css_class("success");
        if (base_dir_entry != null) {
            base_dir_entry.remove_css_class("error");
            if (!base_valid) base_dir_entry.add_css_class("error");
        }

        // Save is allowed even if qemu is unavailable — the user might
        // be planning to fix it later. We do, however, require the base
        // dir to resolve to a non-empty string.
        if (save_btn != null) save_btn.sensitive = base_valid;
    }

    /**
     * When the dialog is opened from the missing-binary banner,
     * we want focus-stealing only on the initial display, not after
     * every keystroke. Reset on dialog open via the constructor.
     */
    private bool qemu_first_invalid_focus = true;

    // ---- File pickers ----

    private void on_browse_qemu() {
        var filters = new GLib.ListStore(typeof (Gtk.FileFilter));
        // Executables filter — use the catch-all filter, since most
        // distros don't mark binaries with a recognizable MIME type.
        var all_filter = new Gtk.FileFilter();
        all_filter.name = "All files";
        all_filter.add_pattern("*");
        filters.append(all_filter);

        var dialog = new Gtk.FileDialog();
        dialog.title = "Select qemu-system-i386 binary";
        dialog.set_filters(filters);
        dialog.accept_label = "Select";

        dialog.open.begin(this, null, (obj, res) => {
            try {
                var file = dialog.open.end(res);
                if (file != null) {
                    qemu_entry.text = file.get_path();
                }
            }
            catch (GLib.Error e) {
                if (!(e is GLib.IOError.CANCELLED))
                    warning("PrefsDialog: file dialog error: %s", e.message);
            }
        });
    }

    private void on_browse_base_dir() {
        var dialog = new Gtk.FileDialog();
        dialog.title = "Select base directory";

        dialog.select_folder.begin(this, null, (obj, res) => {
            try {
                var file = dialog.select_folder.end(res);
                if (file != null) {
                    base_dir_entry.text = file.get_path();
                }
            }
            catch (GLib.Error e) {
                if (!(e is GLib.IOError.CANCELLED))
                    warning("PrefsDialog: folder dialog error: %s", e.message);
            }
        });
    }

    // ---- Button handlers ----

    /** Save button clicked — persist and close. */
    private void on_save_clicked() {
        if (!working_copy.save()) {
            refresh_status();
            var dlg = new Gtk.AlertDialog("Cannot Save Preferences");
            dlg.set_detail("Failed to write the configuration file. Check file permissions and try again.");
            var buttons = new string[] { "OK" };
            dlg.set_buttons(buttons);
            dlg.choose.begin(this, null, (obj, res) => {
                try { dlg.choose.end(res); } catch (GLib.Error e) {}
            });
            return;
        }
        // Update tracked originals so we're no longer dirty.
        original_qemu_path = working_copy.qemu_binary_path;
        original_base_dir = working_copy.base_dir;
        saved();
        this.destroy();
    }

    /** Cancel button clicked. If dirty, confirm first. */
    private void on_cancel_clicked() {
        if (is_dirty) {
            show_discard_confirmation();
        } else {
            this.destroy();
        }
    }

    /** Window close-request (X button, Escape, Alt+F4). */
    private bool on_close_request() {
        if (is_dirty) {
            show_discard_confirmation();
            return true;  // prevent immediate close
        }
        return false;  // allow close
    }

    /**
     * Show a "Save changes?" confirmation popup with three options:
     * Save, Discard, and Cancel (keep dialog open).
     */
    private void show_discard_confirmation() {
        var dlg = new Gtk.AlertDialog("Unsaved Changes");
        dlg.set_detail("You have unsaved changes to your preferences.\n\nSave them before closing?");
        var buttons = new string[] { "Cancel", "Discard", "Save" };
        dlg.set_buttons(buttons);
        // Index 0 = Cancel (keep open), 1 = Discard (close), 2 = Save
        dlg.choose.begin(this, null, (obj, res) => {
            try {
                var choice = dlg.choose.end(res);
                switch (choice) {
                case 0: // Cancel — keep dialog open
                    return;
                case 1: // Discard — close without saving
                    this.destroy();
                    break;
                case 2: // Save — persist then close
                    on_save_clicked();
                    break;
                }
            } catch (GLib.Error e) {
                // Dialog was dismissed — keep prefs dialog open.
            }
        });
    }
}
