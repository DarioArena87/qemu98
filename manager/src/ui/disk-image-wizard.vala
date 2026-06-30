/*
 * disk-image-wizard.vala — Disk image creation dialog
 *
 * A simple dialog that wraps `qemu-img create` for creating raw,
 * qcow2, or VHD disk images. Provides a path chooser, format picker,
 * and size entry.
 *
 * Phase 3: functional dialog. Pre-allocation and encryption deferred.
 */

public class DiskImageWizard : Gtk.Dialog {

    // ---- Widgets ----

    private Gtk.Entry path_entry;
    private Gtk.DropDown format_dropdown;
    private Gtk.SpinButton size_spin;
    private Gtk.DropDown size_unit_dropdown;
    private Gtk.Label status_label;
    private Gtk.Button create_button;

    // ---- Result ----

    public string? image_path { get; private set; default = null; }

    // ---- Construction ----

    public DiskImageWizard (Gtk.Window parent) {
        Object(
                title: "Create Disk Image",
                transient_for: parent,
                modal: true,
                use_header_bar: 1,
                default_width: 400,
                default_height: 250
        );

        build_ui();
    }

    private void build_ui() {
        var content = (Gtk.Box)get_content_area();
        content.margin_start = 24;
        content.margin_end = 24;
        content.margin_top = 24;
        content.margin_bottom = 12;
        content.spacing = 12;

        // Path
        var path_label = new Gtk.Label ("Image path:");
        path_label.halign = Gtk.Align.START;
        content.append(path_label);

        var path_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        path_entry = new Gtk.Entry() {
            placeholder_text = "~/qemu98-images/vm-disk.qcow2",
            hexpand = true
        };
        path_entry.activate.connect(() => { create_image(); });
        path_row.append(path_entry);

        var browse_btn = new Gtk.Button.with_label ("Browse…");
        browse_btn.clicked.connect(on_browse);
        path_row.append(browse_btn);
        content.append(path_row);

        // Format
        var fmt_label = new Gtk.Label("Format:");
        fmt_label.halign = Gtk.Align.START;
        content.append(fmt_label);

        var fmt_model = new Gtk.StringList(null);
        fmt_model.append("qcow2");
        fmt_model.append("raw");
        fmt_model.append("vhd");
        format_dropdown = new Gtk.DropDown(fmt_model, null);
        format_dropdown.selected = 0;
        content.append(format_dropdown);

        // Size
        var size_label = new Gtk.Label("Size:");
        size_label.halign = Gtk.Align.START;
        content.append(size_label);

        var size_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        var size_adj = new Gtk.Adjustment (4, 0.1, 1024, 0.5, 2, 0);
        size_spin = new Gtk.SpinButton (size_adj, 1, 1);
        size_spin.value = 4;
        size_spin.hexpand = true;
        size_row.append(size_spin);

        var unit_model = new Gtk.StringList(null);
        unit_model.append("GB");
        unit_model.append("MB");
        size_unit_dropdown = new Gtk.DropDown(unit_model, null);
        size_unit_dropdown.selected = 0;
        size_row.append(size_unit_dropdown);
        content.append(size_row);

        // Status
        status_label = new Gtk.Label("");
        status_label.wrap = true;
        status_label.margin_top = 6;
        content.append(status_label);

        // Buttons
        create_button = new Gtk.Button.with_label("Create Image");
        create_button.add_css_class("suggested-action");
        create_button.clicked.connect(on_create);
        create_button.halign = Gtk.Align.CENTER;
        create_button.margin_top = 12;
        content.append(create_button);
    }

    // ---- Handlers ----

    private void on_browse() {
        var chooser = new Gtk.FileDialog () {
            title = "Save Disk Image As"
        };

        chooser.save.begin(this, null, (obj, res) => {
            try {
                var file = chooser.save.end(res);
                if (file != null) {
                    path_entry.text = file.get_path();
                }
            } catch (GLib.Error e) {
                debug("File dialog cancelled: %s", e.message);
            }
        });
    }

    private void on_create() {
        var path = path_entry.text.strip();
        if (path == "") {
            show_error("Please specify an image path first.");
            return;
        }

        // Check if file already exists
        var file = GLib.File.new_for_path(path);
        if (file.query_exists()) {
            show_error(@"File already exists:\n$(path)\n\nChoose a different path.");
            return;
        }

        // Ensure parent directory exists
        var parent_dir = file.get_parent();
        if (parent_dir != null && !parent_dir.query_exists()) {
            try {
                parent_dir.make_directory_with_parents();
            } catch (GLib.Error e) {
                status_label.label = @"⚠ Cannot create directory: $(e.message)";
                return;
            }
        }

        create_image();
    }

    private void create_image() {
        var path = path_entry.text.strip();
        if (path == "") {
            show_error("Please specify an image path first.");
            return;
        }

        var format = ((Gtk.StringList) format_dropdown.model).get_string(format_dropdown.selected);
        var size_val = size_spin.value;
        var unit = size_unit_dropdown.selected == 0 ? "G" : "M";
        var size_str = @"$(size_val)$(unit)";

        status_label.label = @"Creating $(format) image ($(size_str))…";
        create_button.sensitive = false;

        try {
            string[] argv = { "qemu-img", "create", "-f", format, path, size_str };
            string stdout_str;
            string stderr_str;
            int exit_status;

            GLib.Process.spawn_sync(
                    null,
                    argv,
                    null,
                    GLib.SpawnFlags.SEARCH_PATH,
                    null,
                    out stdout_str,
                    out stderr_str,
                    out exit_status
            );

            if (exit_status == 0) {
                status_label.label = @"✓ Image created: $(path)";
                status_label.add_css_class("success");
                image_path = path;

                // Close dialog after short delay
                GLib.Timeout.add_seconds(1, () => {
                    response(-5); // GTK_RESPONSE_OK
                    return false;
                });
            } else {
                status_label.label = @"✗ qemu-img failed: $(stderr_str)";
                create_button.sensitive = true;
            }
        } catch (GLib.Error e) {
            status_label.label = @"✗ Failed to run qemu-img: $(e.message)";
            create_button.sensitive = true;
        }
    }

    /** Show an error in the status label and as an alert dialog. */
    private void show_error(string message) {
        status_label.label = @"⚠ $(message)";
        var dialog = new Gtk.AlertDialog("Cannot Create Image");
        dialog.set_detail(message);
        var buttons = new string[] { "OK" };
        dialog.set_buttons(buttons);
        dialog.choose.begin(this, null, (obj, res) => {
            try { dialog.choose.end(res); } catch (GLib.Error e) {}
        });
    }
}
