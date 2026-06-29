/*
 * media-panel.vala — Live CD-ROM and floppy media management
 *
 * A Gtk.Box showing CD-ROM and floppy insert/eject controls.
 * Uses Gtk.FileDialog for file selection (ISO/CUE/BIN/IMG filters)
 * and VmController for QMP blockdev-change-medium / eject commands.
 *
 * Phase 4: CD-ROM and floppy insert/eject with CUE/BIN support.
 */

public class MediaPanel : Gtk.Box {

    // ---- Internal ----

    private VmController? controller = null;

    // CD-ROM widgets
    private Gtk.Label cdrom_path_label;
    private Gtk.Button cdrom_insert_btn;
    private Gtk.Button cdrom_eject_btn;

    // Floppy widgets
    private Gtk.Label floppy_path_label;
    private Gtk.Button floppy_insert_btn;
    private Gtk.Button floppy_eject_btn;

    // Status
    private Gtk.Label status_label;

    // Default QEMU device IDs
    private const string CDROM_DEVICE = "ide0-cd0";
    private const string FLOPPY_DEVICE = "floppy0";

    // Current media paths
    private string? cdrom_current = null;
    private string? floppy_current = null;

    // ---- Construction ----

    public MediaPanel () {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 8);

        build_ui ();
    }

    // ---- Public API ----

    /** Set the active VM controller (may be null). */
    public void set_controller (VmController? ctrl) {
        if (controller != null) {
            controller.media_operation_complete.disconnect (on_media_result);
        }

        controller = ctrl;

        if (controller != null) {
            controller.media_operation_complete.connect (on_media_result);
        }

        // Clear current paths when switching VMs
        cdrom_current = null;
        floppy_current = null;
        update_sensitivity ();
    }

    // ---- UI construction ----

    private void build_ui () {
        // Title
        var title = new Gtk.Label ("<b>Removable Media</b>");
        title.use_markup = true;
        title.halign = Gtk.Align.START;
        title.margin_start = 12;
        title.margin_end = 12;
        title.margin_top = 12;
        append (title);

        // CD-ROM section
        var cdrom_frame = new Gtk.Frame (null);
        var cdrom_box = build_media_section (
            "CD-ROM / DVD",
            out cdrom_path_label,
            out cdrom_insert_btn,
            out cdrom_eject_btn,
            CDROM_DEVICE
        );
        cdrom_frame.child = cdrom_box;
        cdrom_frame.margin_start = 12;
        cdrom_frame.margin_end = 12;
        cdrom_frame.margin_top = 6;
        append (cdrom_frame);

        // Floppy section
        var floppy_frame = new Gtk.Frame (null);
        var floppy_box = build_media_section (
            "Floppy",
            out floppy_path_label,
            out floppy_insert_btn,
            out floppy_eject_btn,
            FLOPPY_DEVICE
        );
        floppy_frame.child = floppy_box;
        floppy_frame.margin_start = 12;
        floppy_frame.margin_end = 12;
        floppy_frame.margin_top = 6;
        append (floppy_frame);

        // Status bar
        var status_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        status_bar.margin_start = 12;
        status_bar.margin_end = 12;
        status_bar.margin_bottom = 12;

        status_label = new Gtk.Label ("");
        status_label.hexpand = true;
        status_label.halign = Gtk.Align.START;
        status_bar.append (status_label);

        append (status_bar);
    }

    /**
     * Build a reusable media section (CD-ROM or floppy).
     *
     * Each section has a label showing the current path, and
     * Insert/Eject buttons.
     */
    private Gtk.Widget build_media_section (
        string section_title,
        out Gtk.Label path_label,
        out Gtk.Button insert_btn,
        out Gtk.Button eject_btn,
        string device_id
    ) {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        box.margin_start = 12;
        box.margin_end = 12;
        box.margin_top = 10;
        box.margin_bottom = 10;

        // Header row with label
        var label = new Gtk.Label ("<b>%s</b>".printf (section_title));
        label.use_markup = true;
        label.halign = Gtk.Align.START;
        box.append (label);

        // Path display
        path_label = new Gtk.Label ("(no media)");
        path_label.halign = Gtk.Align.START;
        path_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        path_label.margin_start = 12;
        box.append (path_label);

        // Button row
        var btn_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        btn_row.margin_start = 12;

        insert_btn = new Gtk.Button.with_label ("Insert…");
        insert_btn.clicked.connect (() => { on_insert (device_id); });
        btn_row.append (insert_btn);

        eject_btn = new Gtk.Button.with_label ("Eject");
        eject_btn.clicked.connect (() => { on_eject (device_id); });
        btn_row.append (eject_btn);

        box.append (btn_row);

        return box;
    }

    // ---- Action handlers ----

    /** Open file dialog to insert media. */
    private void on_insert (string device_id) {
        if (controller == null) {
            status_label.label = "No VM selected";
            return;
        }

        var filters = build_media_filters ();
        var dialog = new Gtk.FileDialog ();
        dialog.title = "Select Media Image";
        dialog.set_filters (filters);
        dialog.accept_label = "Insert";

        unowned var main_window = (Gtk.ApplicationWindow) get_root ();
        dialog.open.begin (main_window, null, (obj, res) => {
            try {
                var file = dialog.open.end (res);
                if (file != null) {
                    var path = file.get_path ();
                    controller.change_media (device_id, path);
                    update_path_label (device_id, path);
                }
            } catch (GLib.Error e) {
                if (!(e is GLib.IOError.CANCELLED)) {
                    warning ("MediaPanel: file dialog error: %s", e.message);
                }
            }
        });
    }

    /** Eject media from the specified device. */
    private void on_eject (string device_id) {
        if (controller == null) {
            status_label.label = "No VM selected";
            return;
        }

        controller.eject_media (device_id);
        update_path_label (device_id, null);
    }

    /** Handle media operation completion feedback. */
    private void on_media_result (string device, bool success, string message) {
        status_label.label = message;
        update_sensitivity ();
    }

    // ---- Helpers ----

    /** Build Gtk.FileFilter list for ISO, CUE, BIN, IMG files. */
    private GLib.ListStore build_media_filters () {
        var filters = new GLib.ListStore (typeof (Gtk.FileFilter));

        // ISO filter
        var iso_filter = new Gtk.FileFilter ();
        iso_filter.name = "CD/DVD Images (*.iso, *.cue)";
        iso_filter.add_suffix ("iso");
        iso_filter.add_suffix ("cue");
        filters.append (iso_filter);

        // BIN filter
        var bin_filter = new Gtk.FileFilter ();
        bin_filter.name = "Binary Images (*.bin, *.img)";
        bin_filter.add_suffix ("bin");
        bin_filter.add_suffix ("img");
        filters.append (bin_filter);

        // All files
        var all_filter = new Gtk.FileFilter ();
        all_filter.name = "All files";
        all_filter.add_pattern ("*");
        filters.append (all_filter);

        return filters;
    }

    /** Update the path label for a device after insert/eject. */
    private void update_path_label (string device_id, string? path) {
        var basename = path != null
            ? GLib.Path.get_basename (path)
            : "(no media)";

        if (device_id == CDROM_DEVICE) {
            cdrom_current = path;
            cdrom_path_label.label = basename;
        } else if (device_id == FLOPPY_DEVICE) {
            floppy_current = path;
            floppy_path_label.label = basename;
        }
    }

    /** Update button sensitivity based on VM state. */
    private void update_sensitivity () {
        var has_vm = controller != null;
        cdrom_insert_btn.sensitive = has_vm;
        cdrom_eject_btn.sensitive = has_vm;
        floppy_insert_btn.sensitive = has_vm;
        floppy_eject_btn.sensitive = has_vm;
    }
}
