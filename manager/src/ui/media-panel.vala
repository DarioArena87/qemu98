/*
 * media-panel.vala — Live CD-ROM and floppy media management
 *
 * A Gtk.Box showing CD-ROM and floppy insert/eject controls.
 * Reads the VM config to discover all removable-media drives and
 * their currently inserted images. Uses VmController for QMP
 * blockdev-change-medium / eject commands.
 *
 * Phase 4: CD-ROM and floppy insert/eject with CUE/BIN support.
 */

public class MediaPanel : Gtk.Box {

    // ---- Internal ----

    private VmController? controller = null;

    // Container boxes holding dynamically-generated device rows
    private Gtk.Box cdrom_list;
    private Gtk.Box floppy_list;
    private Gtk.Label cdrom_placeholder;
    private Gtk.Label floppy_placeholder;

    // Status
    private Gtk.Label status_label;

    // Track per-device state for QMP operations
    private GLib.GenericArray<MediaSlot> cdrom_slots;
    private GLib.GenericArray<MediaSlot> floppy_slots;

    // Lightweight per-drive state class
    private class MediaSlot : GLib.Object {
        public string device_id;   // config device ID (e.g., "cd0")
        public string qmp_id;      // QMP block device ID
        public string? media_path; // current image path, or null
        public Gtk.Widget row;     // the row widget in the list
        public Gtk.Label path_label;
        public Gtk.Button insert_btn;
        public Gtk.Button eject_btn;
    }

    // ---- Construction ----

    public MediaPanel() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);

        cdrom_slots = new GLib.GenericArray<MediaSlot>();
        floppy_slots = new GLib.GenericArray<MediaSlot>();

        build_ui();
    }

    // ---- Public API ----

    /** Set the active VM controller (may be null). */
    public void set_controller(VmController? ctrl) {
        if (controller != null) {
            controller.media_operation_complete.disconnect(on_media_result);
        }

        controller = ctrl;

        if (controller != null) {
            controller.media_operation_complete.connect(on_media_result);
        }

        rebuild_media_list();
        update_sensitivity();
    }

    // ---- UI construction ----

    private void build_ui() {
        // Title
        var title = new Gtk.Label("<b>Removable Media</b>");
        title.use_markup = true;
        title.halign = Gtk.Align.START;
        title.margin_start = 12;
        title.margin_end = 12;
        title.margin_top = 12;
        append(title);

        // CD-ROM section
        var cdrom_frame = new Gtk.Frame(null);
        var cdrom_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        cdrom_box.margin_start = 12;
        cdrom_box.margin_end = 12;
        cdrom_box.margin_top = 10;
        cdrom_box.margin_bottom = 10;

        var cdrom_header = new Gtk.Label("<b>CD-ROM / DVD</b>");
        cdrom_header.use_markup = true;
        cdrom_header.halign = Gtk.Align.START;
        cdrom_box.append(cdrom_header);

        cdrom_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        cdrom_list.margin_start = 12;
        cdrom_box.append(cdrom_list);

        cdrom_placeholder = new Gtk.Label("(no drives configured)");
        cdrom_placeholder.halign = Gtk.Align.START;
        cdrom_placeholder.margin_start = 12;
        cdrom_placeholder.sensitive = false;
        cdrom_list.append(cdrom_placeholder);

        cdrom_frame.child = cdrom_box;
        cdrom_frame.margin_start = 12;
        cdrom_frame.margin_end = 12;
        cdrom_frame.margin_top = 6;
        append(cdrom_frame);

        // Floppy section
        var floppy_frame = new Gtk.Frame(null);
        var floppy_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
        floppy_box.margin_start = 12;
        floppy_box.margin_end = 12;
        floppy_box.margin_top = 10;
        floppy_box.margin_bottom = 10;

        var floppy_header = new Gtk.Label("<b>Floppy</b>");
        floppy_header.use_markup = true;
        floppy_header.halign = Gtk.Align.START;
        floppy_box.append(floppy_header);

        floppy_list = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        floppy_list.margin_start = 12;
        floppy_box.append(floppy_list);

        floppy_placeholder = new Gtk.Label("(no drives configured)");
        floppy_placeholder.halign = Gtk.Align.START;
        floppy_placeholder.margin_start = 12;
        floppy_placeholder.sensitive = false;
        floppy_list.append(floppy_placeholder);

        floppy_frame.child = floppy_box;
        floppy_frame.margin_start = 12;
        floppy_frame.margin_end = 12;
        floppy_frame.margin_top = 6;
        append(floppy_frame);

        // Status bar
        var status_bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        status_bar.margin_start = 12;
        status_bar.margin_end = 12;
        status_bar.margin_bottom = 12;

        status_label = new Gtk.Label("");
        status_label.hexpand = true;
        status_label.halign = Gtk.Align.START;
        status_bar.append(status_label);

        append(status_bar);
    }

    // ---- Device scanning & UI rebuild ----

    /**
     * Scan the VM config for all CD-ROM and floppy devices and
     * rebuild the dynamic UI sections.
     */
    private void rebuild_media_list() {
        // Clear existing dynamic rows
        clear_device_rows();

        if (controller == null)
            return;

        var config = controller.config;
        if (config == null || !config.has_member("storage"))
            return;

        var storage = config.get_object_member("storage");

        // Scan controller devices for CD-ROM drives
        if (storage.has_member("controllers")) {
            var controllers = storage.get_array_member("controllers");
            for (var ci = 0; ci < controllers.get_length(); ci++) {
                var ctrl = controllers.get_object_element(ci);
                if (!ctrl.has_member("devices")) continue;
                var devs = ctrl.get_array_member("devices");
                for (var di = 0; di < devs.get_length(); di++) {
                    var dev = devs.get_object_element(di);
                    var dtype = dev.has_member("type")
                        ? dev.get_string_member("type") : "hd";
                    if (dtype != "cdrom") continue;

                    var did = dev.has_member("id")
                        ? dev.get_string_member("id") : "cd%d".printf((int) cdrom_slots.length);
                    var path = dev.has_member("file")
                        ? dev.get_string_member("file") : null;

                    add_cdrom_row(did, path);
                }
            }
        }

        // Scan floppy drives
        if (storage.has_member("floppy")) {
            var floppies = storage.get_array_member("floppy");
            for (var i = 0; i < floppies.get_length(); i++) {
                var floppy = floppies.get_object_element(i);
                var did = floppy.has_member("id")
                    ? floppy.get_string_member("id") : "fda%d".printf(i);
                var path = floppy.has_member("file")
                    ? floppy.get_string_member("file") : null;

                add_floppy_row(did, path);
            }
        }
    }

    /** Remove all dynamically-added device rows. */
    private void clear_device_rows() {
        while (cdrom_slots.length > 0) {
            var slot = cdrom_slots.get(0);
            cdrom_list.remove(slot.row);
            cdrom_slots.remove_index(0);
        }
        while (floppy_slots.length > 0) {
            var slot = floppy_slots.get(0);
            floppy_list.remove(slot.row);
            floppy_slots.remove_index(0);
        }
        cdrom_placeholder.visible = true;
        floppy_placeholder.visible = true;
    }

    /**
     * Add a CD-ROM device row.
     *
     * The QMP device ID uses the config device ID directly — QEMU
     * exposes `-drive id=xxx` as a block device named `xxx`.
     */
    private void add_cdrom_row(string device_id, string? media_path) {
        cdrom_placeholder.visible = false;

        var slot = new MediaSlot() {
            device_id = device_id,
            qmp_id = device_id,
            media_path = media_path
        };
        build_device_row(slot);

        cdrom_list.append(slot.row);
        cdrom_slots.add(slot);
    }

    /** Add a floppy device row. */
    private void add_floppy_row(string device_id, string? media_path) {
        floppy_placeholder.visible = false;

        var slot = new MediaSlot() {
            device_id = device_id,
            qmp_id = device_id,
            media_path = media_path
        };
        build_device_row(slot);

        floppy_list.append(slot.row);
        floppy_slots.add(slot);
    }

    /**
     * Build a single device row: label showing device + current media,
     * and Insert/Eject buttons. Stores the row widget and button
     * references on the slot for later lookup.
     */
    private void build_device_row(MediaSlot slot) {
        var row = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);

        // Label: device ID and current media path
        var basename = slot.media_path != null
            ? GLib.Path.get_basename(slot.media_path)
            : "(no media)";

        var label = new Gtk.Label(@"<b>$(slot.device_id)</b>  —  $(basename)");
        label.use_markup = true;
        label.halign = Gtk.Align.START;
        label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        slot.path_label = label;
        row.append(label);

        // Button row
        var btn_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);

        var insert_btn = new Gtk.Button.with_label("Insert…");
        insert_btn.clicked.connect(() => { on_insert(slot); });
        slot.insert_btn = insert_btn;
        btn_row.append(insert_btn);

        var eject_btn = new Gtk.Button.with_label("Eject");
        eject_btn.clicked.connect(() => { on_eject(slot); });
        slot.eject_btn = eject_btn;
        btn_row.append(eject_btn);

        row.append(btn_row);

        slot.row = row;
    }

    // ---- Action handlers ----

    /** Open file dialog to insert media. */
    private void on_insert(MediaSlot slot) {
        if (controller == null) {
            status_label.label = "No VM selected";
            return;
        }

        var filters = build_media_filters();
        var dialog = new Gtk.FileDialog();
        dialog.title = @"Insert media in $(slot.device_id)";
        dialog.set_filters(filters);
        dialog.accept_label = "Insert";

        unowned var main_window = (Gtk.ApplicationWindow) get_root();
        dialog.open.begin(main_window, null, (obj, res) => {
            try {
                var file = dialog.open.end(res);
                if (file != null) {
                    var path = file.get_path();
                    controller.change_media(slot.qmp_id, path);
                    update_slot_path(slot, path);
                }
            } catch (GLib.Error e) {
                if (!(e is GLib.IOError.CANCELLED)) {
                    warning("MediaPanel: file dialog error: %s", e.message);
                }
            }
        });
    }

    /** Eject media from the specified device. */
    private void on_eject(MediaSlot slot) {
        if (controller == null) {
            status_label.label = "No VM selected";
            return;
        }

        controller.eject_media(slot.qmp_id);
        update_slot_path(slot, null);
    }

    /** Handle media operation completion feedback. */
    private void on_media_result(string device, bool success, string message) {
        status_label.label = message;
        update_sensitivity();
    }

    // ---- Helpers ----

    /** Build Gtk.FileFilter list for ISO, CUE, BIN, IMG files. */
    private GLib.ListStore build_media_filters() {
        var filters = new GLib.ListStore(typeof(Gtk.FileFilter));

        var iso_filter = new Gtk.FileFilter();
        iso_filter.name = "CD/DVD Images (*.iso, *.cue)";
        iso_filter.add_suffix("iso");
        iso_filter.add_suffix("cue");
        filters.append(iso_filter);

        var bin_filter = new Gtk.FileFilter();
        bin_filter.name = "Binary Images (*.bin, *.img)";
        bin_filter.add_suffix("bin");
        bin_filter.add_suffix("img");
        filters.append(bin_filter);

        var all_filter = new Gtk.FileFilter();
        all_filter.name = "All files";
        all_filter.add_pattern("*");
        filters.append(all_filter);

        return filters;
    }

    /** Update the path label and stored path for a slot. */
    private void update_slot_path(MediaSlot slot, string? path) {
        slot.media_path = path;
        var basename = path != null
            ? GLib.Path.get_basename(path)
            : "(no media)";
        slot.path_label.label = @"<b>$(slot.device_id)</b>  —  $(basename)";
    }

    /** Update button sensitivity based on VM state. */
    private void update_sensitivity() {
        var has_vm = controller != null;
        for (var i = 0; i < cdrom_slots.length; i++) {
            var s = cdrom_slots.get(i);
            s.insert_btn.sensitive = has_vm;
            s.eject_btn.sensitive = has_vm;
        }
        for (var i = 0; i < floppy_slots.length; i++) {
            var s = floppy_slots.get(i);
            s.insert_btn.sensitive = has_vm;
            s.eject_btn.sensitive = has_vm;
        }
    }
}
