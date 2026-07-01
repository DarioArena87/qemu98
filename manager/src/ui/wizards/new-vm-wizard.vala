/*
 * new-vm-wizard.vala — Multi-page VM creation wizard
 *
 * A dialog with Gtk.Stack-based page navigation (avoids deprecated
 * Gtk.Assistant). Pages: name/OS, hardware, storage, display/audio,
 * network, review.
 *
 * Phase 3: functional wizard using Gtk.Stack + custom nav buttons.
 */

public class NewVmWizard : Gtk.Dialog {

    public Json.Object? result_config { get; private set; default = null; }
    public string? result_name { get; private set; default = null; }

    // Navigation
    private Gtk.Stack stack;
    private Gtk.Button prev_btn;
    private Gtk.Button next_btn;
    private string[] page_keys;
    private int current_page = 0;

    // Page 0: Name + OS
    private Gtk.Entry name_entry;
    private Gtk.DropDown os_dropdown;

    // Page 1: Hardware
    private Gtk.DropDown cpu_dropdown;
    private Gtk.SpinButton ram_spin;
    private Gtk.DropDown machine_dropdown;
    private Gtk.DropDown accel_dropdown;

    // Page 2: Storage
    private Gtk.Entry disk_path_entry;
    private Gtk.DropDown disk_format_dropdown;
    private Gtk.SpinButton disk_size_spin;
    private Gtk.DropDown disk_size_unit_dropdown;
    private Gtk.Entry cdrom_entry;
    private Gtk.Entry floppy_entry;

    // Page 3: Display / Audio
    private Gtk.DropDown display_dropdown;
    private Gtk.DropDown filter_dropdown;
    private Gtk.DropDown audio_dropdown;
    private Gtk.CheckButton sb16_check;
    private Gtk.CheckButton opl3_check;
    private Gtk.CheckButton voodoo_check;
    private Gtk.CheckButton hypback_check;

    // Page 4: Network
    private Gtk.DropDown net_dropdown;

    // Page 5: Review
    private Gtk.Label review_label;

    private ConfigStore config_store;
    private AppConfig app_config;

    /**
     * @param config_store  Per-VM config persistence layer
     * @param app_config    Application-level configuration, used to
     *                      compute the default disk image location
     *                      under the user's base directory.
     */
    public NewVmWizard(ConfigStore config_store, AppConfig app_config) {
        Object(
                title: "Create New Virtual Machine",
                modal: true,
                use_header_bar: 1,
                default_width: 550,
                default_height: 450
        );
        this.config_store = config_store;
        this.app_config = app_config;
        build_ui();
    }

    private void build_ui() {
        var content = (Gtk.Box) get_content_area();
        content.margin_start = 24;
        content.margin_end = 24;
        content.margin_top = 12;
        content.margin_bottom = 12;
        content.spacing = 8;

        // Stack for pages
        stack = new Gtk.Stack () {
            transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
            hexpand = true,
            vexpand = true
        };

        stack.add_named(build_name_page(), "name");
        stack.add_named(build_hardware_page(), "hardware");
        stack.add_named(build_storage_page(), "storage");
        stack.add_named(build_display_page(), "display");
        stack.add_named(build_network_page(), "network");
        stack.add_named(build_review_page(), "review");

        page_keys = { "name", "hardware", "storage", "display", "network", "review" };
        content.append(stack);

        // Re-seed the storage default whenever the Storage page is
        // shown, so the user always sees a fresh suggestion based on
        // whatever name they've typed by that point.
        stack.notify["visible-child-name"].connect(on_stack_page_changed);

        // Navigation buttons
        var nav = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        nav.halign = Gtk.Align.END;

        prev_btn = new Gtk.Button.with_label("← Back");
        prev_btn.clicked.connect(on_prev);
        prev_btn.sensitive = false;
        nav.append(prev_btn);

        next_btn = new Gtk.Button.with_label("Next →");
        next_btn.add_css_class("suggested-action");
        next_btn.clicked.connect(on_next);
        nav.append(next_btn);

        content.append(nav);

        stack.visible_child_name = "name";
    }

    /**
     * Re-seed the storage-page default whenever the user navigates
     * to a different page. As long as the user hasn't customized the
     * disk path manually, we replace it with a fresh default derived
     * from the current VM name.
     */
    private void on_stack_page_changed() {
        if (stack.visible_child_name == "storage") {
            // Only rewrite if the entry is empty or still showing a
            // previous auto-fill; this preserves any user edits.
            var current = disk_path_entry != null
                ? disk_path_entry.text.strip() : "";
            var new_default = compute_default_disk_path();
            if (new_default != "" &&
                (current == "" || current == last_disk_default)) {
                disk_path_entry.text = new_default;
                last_disk_default = new_default;
            }
        }
    }

    // ---- Page builders ----

    private Gtk.Widget make_labeled_dropdown(out Gtk.DropDown dd, string label, string first, ...) {
        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        box.append(new Gtk.Label (label) { width_request = 120, halign = Gtk.Align.END });
        var model = new Gtk.StringList (null);
        model.append(first);
        var args = va_list();
        string? val;
        while ((val = args.arg()) != null)
        model.append(val);
        dd = new Gtk.DropDown (model, null);
        dd.selected = 0;
        dd.hexpand = true;
        box.append(dd);
        return box;
    }

    private Gtk.Box make_page_box() {
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        box.margin_top = 12;
        box.hexpand = true;
        box.vexpand = true;
        return box;
    }

    private Gtk.Label section_label(string text) {
        return new Gtk.Label (@"<b>$(text)</b>") {
            use_markup = true, halign = Gtk.Align.START, margin_top = 8
        };
    }

    private string dd_text(Gtk.DropDown dd) {
        return ((Gtk.StringList) dd.model).get_string(dd.selected);
    }

    private Gtk.Widget build_name_page() {
        var box = make_page_box();
        box.append(section_label("Name And Operating System"));
        name_entry = new Gtk.Entry() { text = "My New VM", hexpand = true };
        // Keep the storage-page default disk path in sync with the name
        // as long as the user hasn't customized it manually.
        name_entry.changed.connect(on_name_changed);
        box.append(name_entry);
        box.append(make_labeled_dropdown(
                out os_dropdown,
                "OS type:",
                "Windows 98 SE", "Windows 98", "Windows 95 OSR2", "Windows 95", "Windows ME", "MS-DOS 6.22", "Other"
        ));
        return box;
    }

    /**
     * Name entry changed handler — recomputes the suggested default
     * disk image path and updates disk_path_entry only if it still
     * shows the model's auto-generated default (the comparison is on
     * derived-from-name strings). Once the user types a custom path,
     * this auto-fill stops so we never overwrite their input.
     */
    private void on_name_changed() {
        if (disk_path_entry == null) return;
        var new_default = compute_default_disk_path();
        // We treat the user's input as "still default" while the entry
        // is empty OR while it equals our last computed default for
        // the previous name. Tracking the previous default lets us
        // update live without clobbering a user edit.
        var current = disk_path_entry.text.strip();
        if (current == "" || current == last_disk_default) {
            if (new_default != "") {
                disk_path_entry.text = new_default;
                last_disk_default = new_default;
            }
        }
    }

    /** Compute the suggested default disk path for the current vm name. */
    private string compute_default_disk_path() {
        var name = name_entry != null ? name_entry.text.strip() : "";
        if (name == "" || app_config == null) return "";
        return app_config.get_default_disk_path(name);
    }

    /** Tracks the most recently auto-filled default for live updates. */
    private string last_disk_default = "";

    private Gtk.Widget build_hardware_page() {
        var box = make_page_box();
        box.append(section_label("Hardware"));
        box.append(make_labeled_dropdown(out cpu_dropdown, "CPU:",
                "pentium3", "pentium2", "pentium", "486", "qemu32", "qemu64", "host"));
        box.append(make_labeled_dropdown(out machine_dropdown, "Machine:",
                "pc-i440fx-11.1", "pc-i440fx-7.2", "pc-q35-11.1"));
        box.append(make_labeled_dropdown(out accel_dropdown, "Accelerator:",
                "kvm", "tcg", "whpx"));

        var ram_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        ram_row.append(new Gtk.Label("RAM (MB):") { width_request = 120, halign = Gtk.Align.END });
        var adj = new Gtk.Adjustment(256, 32, 4096, 32, 64, 0);
        ram_spin = new Gtk.SpinButton(adj, 1, 0) { hexpand = true };
        ram_row.append(ram_spin);
        box.append(ram_row);
        return box;
    }

    private Gtk.Widget build_storage_page() {
        var box = make_page_box();
        box.append(section_label("Storage"));
        box.append(new Gtk.Label("Disk Image (leave empty to use the default):") { halign = Gtk.Align.START });
        var dr = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        disk_path_entry = new Gtk.Entry() {
            // Placeholder shows the resolved base directory so the user
            // understands where the auto-suggested path lands.
            placeholder_text =
                app_config != null
                    ? app_config.get_default_disk_path(vm_name_suggestion_for_placeholder)
                    : "<base>/<vm_name>/<kebab>.qcow2",
            hexpand = true
        };
        // Seed the auto-generated default so the user sees the value
        // immediately upon arrival on this page, not only after typing.
        var initial_default = compute_default_disk_path();
        if (initial_default != "") {
            disk_path_entry.text = initial_default;
            last_disk_default = initial_default;
        }
        dr.append(disk_path_entry);
        var bbtn = new Gtk.Button.with_label("Browse…");
        bbtn.clicked.connect(on_browse_disk);
        dr.append(bbtn);
        box.append(dr);
        box.append(make_labeled_dropdown(out disk_format_dropdown, "Format:", "qcow2", "raw", "vhd"));

        // Disk size (for auto-creation on Finish)
        var size_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        size_row.append(new Gtk.Label("Disk size:") { width_request = 120, halign = Gtk.Align.END });
        var size_adj = new Gtk.Adjustment(4, 0.1, 1024, 0.5, 2, 0);
        disk_size_spin = new Gtk.SpinButton(size_adj, 1, 1) { hexpand = true, value = 4 };
        size_row.append(disk_size_spin);
        var unit_model = new Gtk.StringList(null);
        unit_model.append("GB");
        unit_model.append("MB");
        disk_size_unit_dropdown = new Gtk.DropDown(unit_model, null);
        disk_size_unit_dropdown.selected = 0;
        size_row.append(disk_size_unit_dropdown);
        box.append(size_row);

        // CD-ROM image (optional boot media)
        box.append(new Gtk.Label("CD-ROM image (optional):") { halign = Gtk.Align.START, margin_top = 4 });
        var cd_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        cdrom_entry = new Gtk.Entry() { hexpand = true };
        cd_row.append(cdrom_entry);
        var cd_btn = new Gtk.Button.with_label("Browse…");
        cd_btn.clicked.connect(() => on_browse_media(cdrom_entry, "Select CD-ROM Image"));
        cd_row.append(cd_btn);
        box.append(cd_row);

        // Floppy image (optional boot media)
        box.append(new Gtk.Label("Floppy image (optional):") { halign = Gtk.Align.START, margin_top = 4 });
        var floppy_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        floppy_entry = new Gtk.Entry() { hexpand = true };
        floppy_row.append(floppy_entry);
        var floppy_btn = new Gtk.Button.with_label("Browse…");
        floppy_btn.clicked.connect(() => on_browse_media(floppy_entry, "Select Floppy Image"));
        floppy_row.append(floppy_btn);
        box.append(floppy_row);

        return box;
    }

    /**
     * Placeholder name used before the user types anything. Generates
     * the kebab form of a generic example so the placeholder hints
     * at the convention.
     */
    private const string vm_name_suggestion_for_placeholder = "My New VM";

    private Gtk.Widget build_display_page() {
        var box = make_page_box();
        box.append(section_label("Display And Audio"));
        box.append(make_labeled_dropdown(out display_dropdown, "Display:", "gtk", "sdl", "vnc"));
        box.append(make_labeled_dropdown(out filter_dropdown, "Filter:", "nearest", "linear"));
        voodoo_check = new Gtk.CheckButton.with_label ("Voodoo3 3D accelerator") { active = false };
        box.append(voodoo_check);
        hypback_check = new Gtk.CheckButton.with_label ("Hypercall backdoor (hypback)") { active = true };
        box.append(hypback_check);
        sb16_check = new Gtk.CheckButton.with_label ("Sound Blaster 16") { active = true };
        box.append(sb16_check);
        opl3_check = new Gtk.CheckButton.with_label ("OPL3 FM synthesis") { active = true };
        box.append(opl3_check);
        box.append(make_labeled_dropdown(out audio_dropdown, "Audio backend:",
                "pa", "alsa", "pipewire", "oss", "sdl"));
        return box;
    }

    private Gtk.Widget build_network_page() {
        var box = make_page_box();
        box.append(section_label("Network"));
        box.append(make_labeled_dropdown(out net_dropdown, "Type:", "user", "tap", "none"));
        return box;
    }

    private Gtk.Widget build_review_page() {
        var box = make_page_box();
        box.append(section_label("Review"));
        review_label = new Gtk.Label("");
        review_label.use_markup = true;
        review_label.halign = Gtk.Align.START;
        review_label.valign = Gtk.Align.START;
        review_label.wrap = true;
        review_label.selectable = true;
        var sc = new Gtk.ScrolledWindow() { child = review_label, vexpand = true, hexpand = true };
        sc.set_min_content_height(200);
        box.append(sc);
        return box;
    }

    // ---- Navigation ----

    private void on_prev() {
        if (current_page > 0) {
            current_page--;
            update_nav();
        }
    }

    private void on_next() {
        // Validate current page before advancing
        if (!validate_current_page())
            return;

        if (current_page == page_keys.length - 1) {
            // Finish — on the review page
            var name = name_entry.text.strip();
            if (name == "") {
                show_error_dialog("Cannot Finish", "Please enter a name for the virtual machine.");
                return;
            }

            // Auto-create disk image if the path doesn't exist yet
            var disk_path = disk_path_entry.text.strip();
            if (disk_path != "") {
                if (!create_disk_image_if_needed(disk_path))
                    return;
            }

            result_name = name;
            result_config = build_config(name);
            response(-5); // GTK_RESPONSE_OK — emits ::response, closes dialog
            this.destroy(); // force close in case response() doesn't destroy
            return;
        }

        if (current_page == page_keys.length - 2) {
            // About to show review page — build summary
            update_review();
        }

        current_page++;
        update_nav();
    }

    /**
     * Validate the fields on the current wizard page.
     * Returns true if the page is valid and navigation can proceed.
     */
    private bool validate_current_page() {
        switch (current_page) {
        case 0: // Name page
            if (name_entry.text.strip() == "") {
                show_error_dialog("Invalid Name", "Please enter a name for the virtual machine.");
                name_entry.grab_focus();
                return false;
            }
            break;
        case 2: // Storage page
            var disk_path = disk_path_entry.text.strip();
            if (disk_path != "") {
                var parent = GLib.Path.get_dirname(disk_path);
                if (parent == "" || parent == ".") {
                    show_error_dialog("Invalid Path", "Please specify a full path for the disk image, or leave it empty to use the default.");
                    return false;
                }
            }
            // Validate CD-ROM image exists if specified
            var cd_path = cdrom_entry.text.strip();
            if (cd_path != "" && !GLib.FileUtils.test(cd_path, GLib.FileTest.EXISTS)) {
                show_error_dialog("File Not Found", @"CD-ROM image does not exist:\n$(cd_path)");
                cdrom_entry.grab_focus();
                return false;
            }
            if (cd_path != "" && !GLib.FileUtils.test(cd_path, GLib.FileTest.IS_REGULAR)) {
                show_error_dialog("Invalid File", @"CD-ROM path is not a regular file:\n$(cd_path)");
                cdrom_entry.grab_focus();
                return false;
            }
            // Validate floppy image exists if specified
            var floppy_path = floppy_entry.text.strip();
            if (floppy_path != "" && !GLib.FileUtils.test(floppy_path, GLib.FileTest.EXISTS)) {
                show_error_dialog("File Not Found", @"Floppy image does not exist:\n$(floppy_path)");
                floppy_entry.grab_focus();
                return false;
            }
            if (floppy_path != "" && !GLib.FileUtils.test(floppy_path, GLib.FileTest.IS_REGULAR)) {
                show_error_dialog("Invalid File", @"Floppy path is not a regular file:\n$(floppy_path)");
                floppy_entry.grab_focus();
                return false;
            }
            break;
        }
        return true;
    }

    /**
     * Create the disk image using qemu-img if it doesn't already exist.
     * Shows feedback on the next button while the operation runs.
     * Returns true on success (or if already exists), false on failure.
     */
    private bool create_disk_image_if_needed(string disk_path) {
        var file = GLib.File.new_for_path(disk_path);
        if (file.query_exists())
            return true; // Already exists, nothing to do

        // Ensure parent directory exists
        var parent_dir = file.get_parent();
        if (parent_dir != null && !parent_dir.query_exists()) {
            try {
                parent_dir.make_directory_with_parents();
            } catch (GLib.Error e) {
                show_error_dialog("Cannot Create Disk", @"Cannot create directory for disk image:\n$(e.message)");
                return false;
            }
        }

        var format = dd_text(disk_format_dropdown);
        var size_val = disk_size_spin.value;
        var unit = disk_size_unit_dropdown.selected == 0 ? "G" : "M";
        var size_str = @"$(size_val)$(unit)";

        // Show progress feedback — flush pending events so the UI repaints
        var saved_label = next_btn.label;
        next_btn.label = "Creating disk image…";
        next_btn.sensitive = false;
        var ctx = GLib.MainContext.default();
        while (ctx.pending())
            ctx.iteration(false);

        try {
            string[] argv = { "qemu-img", "create", "-f", format, disk_path, size_str };
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

            next_btn.label = saved_label;
            next_btn.sensitive = true;

            if (exit_status != 0) {
                show_error_dialog("Cannot Create Disk", @"Failed to create disk image:\n$(stderr_str)");
                return false;
            }
        } catch (GLib.Error e) {
            next_btn.label = saved_label;
            next_btn.sensitive = true;
            show_error_dialog("Cannot Create Disk", @"Failed to run qemu-img:\n$(e.message)");
            return false;
        }

        return true;
    }

    private void update_nav() {
        stack.visible_child_name = page_keys[current_page];
        prev_btn.sensitive = current_page > 0;
        next_btn.label = current_page == page_keys.length - 1 ? "Finish" : "Next →";
        prev_btn.visible = current_page > 0;
    }

    // ---- Review builder ----

    /**
     * Escape characters that are special in Pango markup (&amp;, &lt;, &gt;).
     * Call this on any user-provided text before including it in
     * a label with use_markup=true.
     */
    private static string escape_markup(string s) {
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    private void update_review() {
        var sb = new GLib.StringBuilder ("<b>New VM Summary</b>\n\n");
        sb.append(@"<b>Name:</b> $(escape_markup(name_entry.text))\n");
        sb.append(@"<b>OS:</b> $(escape_markup(dd_text(os_dropdown)))\n\n");
        sb.append("<b>Hardware:</b>\n");
        sb.append(@"  CPU: $(escape_markup(dd_text(cpu_dropdown)))\n");
        sb.append(@"  RAM: $(ram_spin.get_value_as_int()) MB\n");
        sb.append(@"  Machine: $(escape_markup(dd_text(machine_dropdown)))\n");
        sb.append(@"  Accelerator: $(escape_markup(dd_text(accel_dropdown)))\n\n");
        sb.append("<b>Storage:</b>\n");
        var dp = disk_path_entry.text.strip();
        if (dp != "") {
            sb.append(@"  Disk: $(escape_markup(dp)) ($(escape_markup(dd_text(disk_format_dropdown))))\n");
            var size_val = disk_size_spin.value;
            var unit = disk_size_unit_dropdown.selected == 0 ? "GB" : "MB";
            sb.append(@"  Size: $(size_val) $(unit)\n");
        } else {
            sb.append("  No disk image specified\n");
        }
        var cdrom_path = cdrom_entry.text.strip();
        if (cdrom_path != "") sb.append(@"  CD-ROM: $(escape_markup(cdrom_path))\n");
        var floppy_path = floppy_entry.text.strip();
        if (floppy_path != "") sb.append(@"  Floppy: $(escape_markup(floppy_path))\n");
        sb.append("\n<b>Display &amp; Audio:</b>\n");
        sb.append(@"  Display: $(escape_markup(dd_text(display_dropdown)))\n");
        sb.append(@"  Filter: $(escape_markup(dd_text(filter_dropdown)))\n");
        if (voodoo_check.active) sb.append("  Voodoo3: yes\n");
        if (hypback_check.active) sb.append("  Hypback: yes\n");
        if (sb16_check.active) sb.append("  SB16: yes\n");
        if (opl3_check.active) sb.append("  OPL3: yes\n");
        sb.append(@"  Audio backend: $(escape_markup(dd_text(audio_dropdown)))\n\n");
        sb.append("<b>Network:</b>\n");
        sb.append(@"  Type: $(escape_markup(dd_text(net_dropdown)))\n");
        review_label.label = sb.str;
    }

    // ---- File chooser helpers ----

    private void on_browse_disk() {
        var chooser = new Gtk.FileDialog () { title = "Select or Create Disk Image" };
        chooser.save.begin(this, null, (obj, res) => {
            try {
                var f = chooser.save.end(res);
                if (f != null) disk_path_entry.text = f.get_path();
            } catch (GLib.Error e) { }
        });
    }

    /** Generic file-open chooser for CD-ROM / floppy media images. */
    private void on_browse_media(Gtk.Entry entry, string title) {
        var chooser = new Gtk.FileDialog() { title = title };
        chooser.open.begin(this, null, (obj, res) => {
            try {
                var f = chooser.open.end(res);
                if (f != null) entry.text = f.get_path();
            } catch (GLib.Error e) { }
        });
    }

    // ---- Config builder ----

    /** Show an error dialog to the user. */
    private void show_error_dialog(string title, string message) {
        var dialog = new Gtk.AlertDialog(title);
        dialog.set_detail(message);
        var buttons = new string[] { "OK" };
        dialog.set_buttons(buttons);
        dialog.choose.begin(this, null, (obj, res) => {
            try { dialog.choose.end(res); } catch (GLib.Error e) {}
        });
    }

    /**
     * Ensure the storage config has at least one controller (IDE).
     * Used by build_config() so that disk and cdrom devices share the
     * same IDE controller when both are present.
     */
    private void ensure_storage_controller(Json.Object storage) {
        var ctrl_array = storage.get_array_member("controllers");
        if (ctrl_array.get_length() > 0)
            return;
        var c = new Json.Object();
        c.set_string_member("type", "ide");
        c.set_string_member("bus", "ide.0");
        c.set_array_member("devices", new Json.Array());
        ctrl_array.add_object_element(c);
    }

    private Json.Object build_config(string vm_name) {
        var config = ConfigStore.create_default_config(vm_name);
        var machine = config.get_object_member("machine");
        machine.set_string_member("type", dd_text(machine_dropdown));
        machine.set_string_member("cpu", dd_text(cpu_dropdown));
        machine.set_int_member("ram_mb", ram_spin.get_value_as_int());
        machine.set_string_member("accelerator", dd_text(accel_dropdown));

        var display = config.get_object_member("display");
        display.set_string_member("type", dd_text(display_dropdown));
        display.set_string_member("scale_filter", dd_text(filter_dropdown));

        var audio = config.get_object_member("audio");
        audio.set_string_member("backend", dd_text(audio_dropdown));
        audio.set_boolean_member("sb16", sb16_check.active);
        audio.set_boolean_member("opl3", opl3_check.active);

        var devices = config.get_array_member("devices");
        for (var i = (int) devices.get_length() - 1; i >= 0; i--)
        devices.remove_element(i);

        var vga = new Json.Object ();
        vga.set_string_member("type", "VGA"); vga.set_int_member("vram_mb", 16);
        devices.add_object_element(vga);

        if (voodoo_check.active) {
            var vd = new Json.Object ();
            vd.set_string_member("type", "voodoo3"); vd.set_int_member("vram_mb", 64);
            devices.add_object_element(vd);
        }
        if (hypback_check.active) {
            var hb = new Json.Object ();
            hb.set_string_member("type", "hypback"); hb.set_string_member("id", "hbe0");
            devices.add_object_element(hb);
        }
        if (sb16_check.active) {
            var sb = new Json.Object ();
            sb.set_string_member("type", "sb16");
            sb.set_int_member("irq", 5); sb.set_int_member("dma", 1); sb.set_int_member("dma16", 5);
            devices.add_object_element(sb);
        }

        var storage = config.get_object_member("storage");
        var disk_path = disk_path_entry.text.strip();
        if (disk_path != "") {
            ensure_storage_controller(storage);
            var ctrl_array = storage.get_array_member("controllers");
            var ct = ctrl_array.get_object_element(0);
            var devs = ct.get_array_member("devices");
            var disk = new Json.Object ();
            disk.set_string_member("id", "hda");
            disk.set_string_member("type", "hd");
            disk.set_string_member("file", disk_path);
            disk.set_string_member("format", dd_text(disk_format_dropdown));
            devs.add_object_element(disk);
        }

        // CD-ROM drive (optional boot media)
        var cdrom_path = cdrom_entry.text.strip();
        if (cdrom_path != "") {
            ensure_storage_controller(storage);
            var ctrl_array = storage.get_array_member("controllers");
            var ct = ctrl_array.get_object_element(0);
            var devs = ct.get_array_member("devices");
            var cdrom = new Json.Object();
            cdrom.set_string_member("id", "cd0");
            cdrom.set_string_member("type", "cdrom");
            cdrom.set_string_member("file", cdrom_path);
            cdrom.set_string_member("format", "raw");
            devs.add_object_element(cdrom);
        }

        // Floppy drive (optional boot media)
        var floppy_path = floppy_entry.text.strip();
        if (floppy_path != "") {
            var floppy_array = storage.get_array_member("floppy");
            var floppy_dev = new Json.Object();
            floppy_dev.set_string_member("id", "fda0");
            floppy_dev.set_string_member("file", floppy_path);
            floppy_dev.set_string_member("format", "raw");
            floppy_array.add_object_element(floppy_dev);
        }

        config.get_object_member("networking").set_string_member("type", dd_text(net_dropdown));

        return config;
    }
}
