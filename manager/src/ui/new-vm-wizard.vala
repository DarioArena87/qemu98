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

    public NewVmWizard (ConfigStore config_store) {
        Object (
            title: "Create New Virtual Machine",
            modal: true,
            use_header_bar: 1,
            default_width: 550,
            default_height: 450
        );
        this.config_store = config_store;
        build_ui ();
    }

    private void build_ui () {
        var content = (Gtk.Box) get_content_area ();
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

        stack.add_named (build_name_page (), "name");
        stack.add_named (build_hardware_page (), "hardware");
        stack.add_named (build_storage_page (), "storage");
        stack.add_named (build_display_page (), "display");
        stack.add_named (build_network_page (), "network");
        stack.add_named (build_review_page (), "review");

        page_keys = { "name", "hardware", "storage", "display", "network", "review" };
        content.append (stack);

        // Navigation buttons
        var nav = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        nav.halign = Gtk.Align.END;

        prev_btn = new Gtk.Button.with_label ("← Back");
        prev_btn.clicked.connect (on_prev);
        prev_btn.sensitive = false;
        nav.append (prev_btn);

        next_btn = new Gtk.Button.with_label ("Next →");
        next_btn.add_css_class ("suggested-action");
        next_btn.clicked.connect (on_next);
        nav.append (next_btn);

        content.append (nav);

        stack.visible_child_name = "name";
    }

    // ---- Page builders ----

    private Gtk.Widget make_labeled_dropdown (out Gtk.DropDown dd, string label, string first, ...) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        box.append (new Gtk.Label (label) { width_request = 120, halign = Gtk.Align.END });
        var model = new Gtk.StringList (null);
        model.append (first);
        var args = va_list ();
        string? val;
        while ((val = args.arg ()) != null)
            model.append (val);
        dd = new Gtk.DropDown (model, null);
        dd.selected = 0;
        dd.hexpand = true;
        box.append (dd);
        return box;
    }

    private Gtk.Box make_page_box () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.margin_top = 12;
        box.hexpand = true;
        box.vexpand = true;
        return box;
    }

    private Gtk.Label section_label (string text) {
        return new Gtk.Label (@"<b>$(text)</b>") {
            use_markup = true, halign = Gtk.Align.START, margin_top = 8
        };
    }

    private string dd_text (Gtk.DropDown dd) {
        return ((Gtk.StringList) dd.model).get_string (dd.selected);
    }

    private Gtk.Widget build_name_page () {
        var box = make_page_box ();
        box.append (section_label ("Name & Operating System"));
        name_entry = new Gtk.Entry () { placeholder_text = "My Windows 98 VM", hexpand = true };
        box.append (name_entry);
        box.append (make_labeled_dropdown (out os_dropdown, "OS type:",
            "Windows 98 SE", "Windows 98", "Windows 95 OSR2", "Windows 95", "Windows ME", "MS-DOS 6.22", "Other"));
        return box;
    }

    private Gtk.Widget build_hardware_page () {
        var box = make_page_box ();
        box.append (section_label ("Hardware"));
        box.append (make_labeled_dropdown (out cpu_dropdown, "CPU:",
            "pentium3", "pentium2", "pentium", "486", "qemu32", "qemu64", "host"));
        box.append (make_labeled_dropdown (out machine_dropdown, "Machine:",
            "pc-i440fx-11.1", "pc-i440fx-7.2", "pc-q35-11.1"));
        box.append (make_labeled_dropdown (out accel_dropdown, "Accelerator:",
            "kvm", "tcg", "whpx"));

        var ram_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        ram_row.append (new Gtk.Label ("RAM (MB):") { width_request = 120, halign = Gtk.Align.END });
        var adj = new Gtk.Adjustment (256, 32, 4096, 32, 64, 0);
        ram_spin = new Gtk.SpinButton (adj, 1, 0) { hexpand = true };
        ram_row.append (ram_spin);
        box.append (ram_row);
        return box;
    }

    private Gtk.Widget build_storage_page () {
        var box = make_page_box ();
        box.append (section_label ("Storage"));
        box.append (new Gtk.Label ("Disk Image (leave empty to skip):") { halign = Gtk.Align.START });
        var dr = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        disk_path_entry = new Gtk.Entry () { placeholder_text = "~/qemu98-images/vm-disk.qcow2", hexpand = true };
        dr.append (disk_path_entry);
        var bbtn = new Gtk.Button.with_label ("Browse…");
        bbtn.clicked.connect (on_browse_disk);
        dr.append (bbtn);
        box.append (dr);
        box.append (make_labeled_dropdown (out disk_format_dropdown, "Format:", "qcow2", "raw", "vhd"));
        return box;
    }

    private Gtk.Widget build_display_page () {
        var box = make_page_box ();
        box.append (section_label ("Display & Audio"));
        box.append (make_labeled_dropdown (out display_dropdown, "Display:", "gtk", "sdl", "vnc"));
        box.append (make_labeled_dropdown (out filter_dropdown, "Filter:", "nearest", "linear"));
        voodoo_check = new Gtk.CheckButton.with_label ("Voodoo3 3D accelerator") { active = true };
        box.append (voodoo_check);
        hypback_check = new Gtk.CheckButton.with_label ("Hypercall backdoor (hypback)") { active = true };
        box.append (hypback_check);
        sb16_check = new Gtk.CheckButton.with_label ("Sound Blaster 16") { active = true };
        box.append (sb16_check);
        opl3_check = new Gtk.CheckButton.with_label ("OPL3 FM synthesis") { active = true };
        box.append (opl3_check);
        box.append (make_labeled_dropdown (out audio_dropdown, "Audio backend:",
            "pa", "alsa", "pipewire", "oss", "sdl"));
        return box;
    }

    private Gtk.Widget build_network_page () {
        var box = make_page_box ();
        box.append (section_label ("Network"));
        box.append (make_labeled_dropdown (out net_dropdown, "Type:", "user", "tap", "none"));
        return box;
    }

    private Gtk.Widget build_review_page () {
        var box = make_page_box ();
        box.append (section_label ("Review"));
        review_label = new Gtk.Label ("");
        review_label.use_markup = true;
        review_label.halign = Gtk.Align.START;
        review_label.valign = Gtk.Align.START;
        review_label.wrap = true;
        review_label.selectable = true;
        var sc = new Gtk.ScrolledWindow () { child = review_label, vexpand = true, hexpand = true };
        box.append (sc);
        return box;
    }

    // ---- Navigation ----

    private void on_prev () {
        if (current_page > 0) {
            current_page--;
            update_nav ();
        }
    }

    private void on_next () {
        if (current_page == page_keys.length - 1) {
            // Finish — on the review page
            var name = name_entry.text.strip ();
            if (name == "") {
                show_error_dialog ("Please enter a name for the virtual machine.");
                return;
            }
            result_name = name;
            result_config = build_config (name);
            response (-5); // GTK_RESPONSE_OK — emits ::response, closes dialog
            this.destroy (); // force close in case response() doesn't destroy
            return;
        }

        if (current_page == page_keys.length - 2) {
            // About to show review page — build summary
            update_review ();
        }

        current_page++;
        update_nav ();
    }

    private void update_nav () {
        stack.visible_child_name = page_keys[current_page];
        prev_btn.sensitive = current_page > 0;
        next_btn.label = current_page == page_keys.length - 1 ? "Finish" : "Next →";
        prev_btn.visible = current_page > 0;
    }

    // ---- Review builder ----

    private void update_review () {
        var sb = new GLib.StringBuilder ("<b>New VM Summary</b>\n\n");
        sb.append (@"<b>Name:</b> $(name_entry.text)\n");
        sb.append (@"<b>OS:</b> $(dd_text (os_dropdown))\n\n");
        sb.append ("<b>Hardware:</b>\n");
        sb.append (@"  CPU: $(dd_text (cpu_dropdown))\n");
        sb.append (@"  RAM: $(ram_spin.get_value_as_int ()) MB\n");
        sb.append (@"  Machine: $(dd_text (machine_dropdown))\n");
        sb.append (@"  Accelerator: $(dd_text (accel_dropdown))\n\n");
        sb.append ("<b>Storage:</b>\n");
        var dp = disk_path_entry.text.strip ();
        sb.append (dp != "" ? @"  Disk: $(dp) ($(dd_text (disk_format_dropdown)))\n" : "  No disk image specified\n");
        sb.append ("\n<b>Display & Audio:</b>\n");
        sb.append (@"  Display: $(dd_text (display_dropdown))\n");
        sb.append (@"  Filter: $(dd_text (filter_dropdown))\n");
        if (voodoo_check.active) sb.append ("  Voodoo3: yes\n");
        if (hypback_check.active) sb.append ("  Hypback: yes\n");
        if (sb16_check.active) sb.append ("  SB16: yes\n");
        if (opl3_check.active) sb.append ("  OPL3: yes\n");
        sb.append (@"  Audio backend: $(dd_text (audio_dropdown))\n\n");
        sb.append ("<b>Network:</b>\n");
        sb.append (@"  Type: $(dd_text (net_dropdown))\n");
        review_label.label = sb.str;
    }

    // ---- Disk browse ----

    private void on_browse_disk () {
        var chooser = new Gtk.FileDialog () { title = "Select or Create Disk Image" };
        chooser.save.begin (this, null, (obj, res) => {
            try {
                var f = chooser.save.end (res);
                if (f != null) disk_path_entry.text = f.get_path ();
            } catch (GLib.Error e) { }
        });
    }

    // ---- Config builder ----

    /** Show an error dialog to the user. */
    private void show_error_dialog (string message) {
        var dialog = new Gtk.AlertDialog ("Cannot Finish");
        dialog.set_detail (message);
        var buttons = new string[] { "OK" };
        dialog.set_buttons (buttons);
        dialog.choose.begin (this, null, (obj, res) => {
            try { dialog.choose.end (res); } catch (GLib.Error e) {}
        });
    }

    private Json.Object build_config (string vm_name) {
        var config = ConfigStore.create_default_config (vm_name);
        var machine = config.get_object_member ("machine");
        machine.set_string_member ("type", dd_text (machine_dropdown));
        machine.set_string_member ("cpu", dd_text (cpu_dropdown));
        machine.set_int_member ("ram_mb", ram_spin.get_value_as_int ());
        machine.set_string_member ("accelerator", dd_text (accel_dropdown));

        var display = config.get_object_member ("display");
        display.set_string_member ("type", dd_text (display_dropdown));
        display.set_string_member ("scale_filter", dd_text (filter_dropdown));

        var audio = config.get_object_member ("audio");
        audio.set_string_member ("backend", dd_text (audio_dropdown));
        audio.set_boolean_member ("sb16", sb16_check.active);
        audio.set_boolean_member ("opl3", opl3_check.active);

        var devices = config.get_array_member ("devices");
        for (var i = (int) devices.get_length () - 1; i >= 0; i--)
            devices.remove_element (i);

        var vga = new Json.Object ();
        vga.set_string_member ("type", "VGA"); vga.set_int_member ("vram_mb", 16);
        devices.add_object_element (vga);

        if (voodoo_check.active) {
            var vd = new Json.Object ();
            vd.set_string_member ("type", "voodoo3"); vd.set_int_member ("vram_mb", 64);
            devices.add_object_element (vd);
        }
        if (hypback_check.active) {
            var hb = new Json.Object ();
            hb.set_string_member ("type", "hypback"); hb.set_string_member ("id", "hbe0");
            devices.add_object_element (hb);
        }
        if (sb16_check.active) {
            var sb = new Json.Object ();
            sb.set_string_member ("type", "sb16");
            sb.set_int_member ("irq", 5); sb.set_int_member ("dma", 1); sb.set_int_member ("dma16", 5);
            devices.add_object_element (sb);
        }

        var storage = config.get_object_member ("storage");
        var disk_path = disk_path_entry.text.strip ();
        if (disk_path != "") {
            var ctrl_array = storage.get_array_member ("controllers");
            if (ctrl_array.get_length () == 0) {
                var c = new Json.Object ();
                c.set_string_member ("type", "ide");
                c.set_string_member ("bus", "ide.0");
                c.set_array_member ("devices", new Json.Array ());
                ctrl_array.add_object_element (c);
            }
            var ct = ctrl_array.get_object_element (0);
            var devs = ct.get_array_member ("devices");
            var disk = new Json.Object ();
            disk.set_string_member ("id", "hda");
            disk.set_string_member ("type", "hd");
            disk.set_string_member ("file", disk_path);
            disk.set_string_member ("format", dd_text (disk_format_dropdown));
            disk.set_int_member ("boot_index", 1);
            devs.add_object_element (disk);
        }

        config.get_object_member ("networking")
            .set_string_member ("type", dd_text (net_dropdown));

        return config;
    }
}
