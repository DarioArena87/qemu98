/*
 * vm-config-editor.vala — Tabbed VM configuration editor
 *
 * A GtkNotebook-based editor for viewing and modifying an existing
 * VM configuration. Tabs: General, Devices, Storage, Network.
 *
 * Phase 3: read-only display + save. Inline editing can be added
 * in Phase 4.
 */

public class VmConfigEditor : Gtk.Box {

    // ---- Internal ----

    private string vm_name;
    private Json.Object config;
    private ConfigStore config_store;
    private Gtk.Notebook notebook;
    private Gtk.Label status_label;

    // General tab widgets
    private Gtk.Entry edit_name;
    private Gtk.Label label_uuid;
    private Gtk.DropDown combo_cpu;
    private Gtk.SpinButton spin_ram;
    private Gtk.DropDown combo_accel;

    // Devices tab
    private Gtk.CheckButton chk_voodoo;
    private Gtk.CheckButton chk_hypback;
    private Gtk.CheckButton chk_sb16;
    private Gtk.CheckButton chk_opl3;

    // Storage tab
    private Gtk.Entry edit_disk;
    private Gtk.Label label_disk_fmt;

    // Network tab
    private Gtk.DropDown combo_net;

    // ---- Signals ----

    /** Emitted when the user saves changes (passes old name for renames). */
    public signal void config_saved (string vm_name, string? old_name);

    // ---- Construction ----

    public VmConfigEditor (ConfigStore config_store) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

        this.config_store = config_store;

        notebook = new Gtk.Notebook ();
        notebook.hexpand = true;
        notebook.vexpand = true;

        notebook.append_page (build_general_tab (), new Gtk.Label ("General"));
        notebook.append_page (build_devices_tab (), new Gtk.Label ("Devices"));
        notebook.append_page (build_storage_tab (), new Gtk.Label ("Storage"));
        notebook.append_page (build_network_tab (), new Gtk.Label ("Network"));

        append (notebook);

        // Save bar
        var save_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        save_bar.margin_start = 12;
        save_bar.margin_end = 12;
        save_bar.margin_top = 6;
        save_bar.margin_bottom = 6;

        status_label = new Gtk.Label ("");
        status_label.hexpand = true;
        status_label.halign = Gtk.Align.START;
        save_bar.append (status_label);

        var save_btn = new Gtk.Button.with_label ("Save Config");
        save_btn.add_css_class ("suggested-action");
        save_btn.clicked.connect (on_save);
        save_bar.append (save_btn);

        append (save_bar);
    }

    // ---- Load a VM config into the editor ----

    public void load (string vm_name) {
        this.vm_name = vm_name;

        var cfg = config_store.get_config (vm_name);
        if (cfg == null) {
            warning ("Config not found: %s", vm_name);
            return;
        }

        this.config = cfg;
        load_general ();
        load_devices ();
        load_storage ();
        load_network ();
    }

    // ---- General tab ----

    private Gtk.Widget build_general_tab () {
        var grid = new Gtk.Grid ();
        grid.margin_start = 24;
        grid.margin_end = 24;
        grid.margin_top = 24;
        grid.margin_bottom = 24;
        grid.row_spacing = 12;
        grid.column_spacing = 12;

        int row = 0;

        grid.attach (new Gtk.Label ("Name:"), 0, row, 1, 1);
        edit_name = new Gtk.Entry () { hexpand = true };
        grid.attach (edit_name, 1, row, 1, 1);
        row++;

        grid.attach (new Gtk.Label ("UUID:"), 0, row, 1, 1);
        label_uuid = new Gtk.Label ("") { halign = Gtk.Align.START, selectable = true };
        grid.attach (label_uuid, 1, row, 1, 1);
        row++;

        var cpu_label = new Gtk.Label ("CPU:");
        grid.attach (cpu_label, 0, row, 1, 1);
        var cpu_model = new Gtk.StringList (null);
        foreach (var c in new string[] { "pentium3", "pentium2", "pentium", "486",
                                          "qemu32", "qemu64", "host" }) {
            cpu_model.append (c);
        }
        combo_cpu = new Gtk.DropDown (cpu_model, null);
        combo_cpu.hexpand = true;
        grid.attach (combo_cpu, 1, row, 1, 1);
        row++;

        grid.attach (new Gtk.Label ("RAM (MB):"), 0, row, 1, 1);
        var ram_adj = new Gtk.Adjustment (256, 32, 4096, 32, 64, 0);
        spin_ram = new Gtk.SpinButton (ram_adj, 1, 0);
        spin_ram.hexpand = true;
        grid.attach (spin_ram, 1, row, 1, 1);
        row++;

        var accel_label = new Gtk.Label ("Accelerator:");
        grid.attach (accel_label, 0, row, 1, 1);
        var accel_model = new Gtk.StringList (null);
        foreach (var a in new string[] { "kvm", "tcg", "whpx" }) {
            accel_model.append (a);
        }
        combo_accel = new Gtk.DropDown (accel_model, null);
        combo_accel.hexpand = true;
        grid.attach (combo_accel, 1, row, 1, 1);

        return grid;
    }

    private void load_general () {
        edit_name.text = vm_name;

        if (config.has_member ("uuid")) {
            label_uuid.label = config.get_string_member ("uuid");
        }

        var machine = config.get_object_member ("machine");
        spin_ram.value = machine.get_int_member ("ram_mb");

        // Set dropdown values by finding matching index
        var cpu_name = machine.get_string_member ("cpu");
        select_in_combo (combo_cpu, cpu_name);

        var accel_name = machine.get_string_member ("accelerator");
        select_in_combo (combo_accel, accel_name);
    }

    // ---- Devices tab ----

    private Gtk.Widget build_devices_tab () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.margin_start = 24;
        box.margin_end = 24;
        box.margin_top = 24;
        box.margin_bottom = 24;

        var title = new Gtk.Label ("<b>PCI Devices</b>");
        title.use_markup = true;
        title.halign = Gtk.Align.START;
        box.append (title);

        chk_voodoo = new Gtk.CheckButton.with_label ("Voodoo3 3D accelerator");
        box.append (chk_voodoo);

        chk_hypback = new Gtk.CheckButton.with_label ("Hypercall backdoor (hypback)");
        box.append (chk_hypback);

        chk_sb16 = new Gtk.CheckButton.with_label ("Sound Blaster 16");
        box.append (chk_sb16);

        chk_opl3 = new Gtk.CheckButton.with_label ("OPL3 FM Synthesis");
        box.append (chk_opl3);

        return box;
    }

    private void load_devices () {
        // Default all off
        chk_voodoo.active = false;
        chk_hypback.active = false;
        chk_sb16.active = false;
        chk_opl3.active = false;

        if (!config.has_member ("devices")) {
            return;
        }

        var devices = config.get_array_member ("devices");
        for (var i = 0; i < devices.get_length (); i++) {
            var dev = devices.get_object_element (i);
            var dev_type = dev.get_string_member ("type");
            switch (dev_type) {
                case "voodoo3": chk_voodoo.active = true; break;
                case "hypback": chk_hypback.active = true; break;
                case "sb16":    chk_sb16.active = true; break;
            }
        }

        // OPL3 from audio section
        if (config.has_member ("audio")) {
            var audio = config.get_object_member ("audio");
            if (audio.has_member ("opl3")) {
                chk_opl3.active = audio.get_boolean_member ("opl3");
            }
        }
    }

    // ---- Storage tab ----

    private Gtk.Widget build_storage_tab () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.margin_start = 24;
        box.margin_end = 24;
        box.margin_top = 24;
        box.margin_bottom = 24;

        var title = new Gtk.Label ("<b>Primary Disk</b>");
        title.use_markup = true;
        title.halign = Gtk.Align.START;
        box.append (title);

        var path_label = new Gtk.Label ("Path:");
        path_label.halign = Gtk.Align.START;
        box.append (path_label);

        edit_disk = new Gtk.Entry () {
            hexpand = true,
            placeholder_text = "~/qemu98-images/disk.qcow2"
        };
        box.append (edit_disk);

        var fmt_label = new Gtk.Label ("Format:");
        fmt_label.halign = Gtk.Align.START;
        fmt_label.margin_top = 8;
        box.append (fmt_label);

        label_disk_fmt = new Gtk.Label ("") { halign = Gtk.Align.START };
        box.append (label_disk_fmt);

        return box;
    }

    private void load_storage () {
        if (!config.has_member ("storage")) {
            edit_disk.text = "";
            label_disk_fmt.label = "";
            return;
        }

        var storage = config.get_object_member ("storage");
        if (storage.has_member ("controllers")) {
            var controllers = storage.get_array_member ("controllers");
            if (controllers.get_length () > 0) {
                var ctrl = controllers.get_object_element (0);
                if (ctrl.has_member ("devices")) {
                    var devs = ctrl.get_array_member ("devices");
                    if (devs.get_length () > 0) {
                        var disk = devs.get_object_element (0);
                        edit_disk.text = disk.has_member ("file") ?
                            disk.get_string_member ("file") : "";
                        label_disk_fmt.label = disk.has_member ("format") ?
                            disk.get_string_member ("format") : "raw";
                    }
                }
            }
        }
    }

    // ---- Network tab ----

    private Gtk.Widget build_network_tab () {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        box.margin_start = 24;
        box.margin_end = 24;
        box.margin_top = 24;
        box.margin_bottom = 24;

        var title = new Gtk.Label ("<b>Network</b>");
        title.use_markup = true;
        title.halign = Gtk.Align.START;
        box.append (title);

        var net_label = new Gtk.Label ("Type:");
        net_label.halign = Gtk.Align.START;
        box.append (net_label);

        var net_model = new Gtk.StringList (null);
        foreach (var n in new string[] { "user", "tap", "none" }) {
            net_model.append (n);
        }
        combo_net = new Gtk.DropDown (net_model, null);
        box.append (combo_net);

        return box;
    }

    private void load_network () {
        if (!config.has_member ("networking")) {
            combo_net.selected = 0;
            return;
        }

        var net = config.get_object_member ("networking");
        var net_type = net.get_string_member ("type");
        select_in_combo (combo_net, net_type);
    }

    // ---- Save ----

    private void on_save () {
        if (config == null) {
            return;
        }

        string? old_name = null;
        // Update name if changed
        var new_name = edit_name.text.strip ();
        if (new_name != "" && new_name != vm_name) {
            config.set_string_member ("name", new_name);
            old_name = vm_name;
            // Rename the config file
            config_store.delete_config (vm_name);
            vm_name = new_name;
        }

        // Machine
        var machine = config.get_object_member ("machine");
        machine.set_string_member ("cpu",
            ((Gtk.StringList) combo_cpu.model).get_string (combo_cpu.selected));
        machine.set_int_member ("ram_mb", spin_ram.get_value_as_int ());
        machine.set_string_member ("accelerator",
            ((Gtk.StringList) combo_accel.model).get_string (combo_accel.selected));

        // Audio (OPL3)
        if (config.has_member ("audio")) {
            var audio = config.get_object_member ("audio");
            audio.set_boolean_member ("opl3", chk_opl3.active);
        }

        // Storage
        if (config.has_member ("storage")) {
            var storage = config.get_object_member ("storage");
            if (storage.has_member ("controllers")) {
                var controllers = storage.get_array_member ("controllers");
                if (controllers.get_length () > 0) {
                    var ctrl = controllers.get_object_element (0);
                    if (ctrl.has_member ("devices")) {
                        var devs = ctrl.get_array_member ("devices");
                        if (devs.get_length () > 0) {
                            var disk = devs.get_object_element (0);
                            disk.set_string_member ("file", edit_disk.text.strip ());
                        } else {
                            var disk = new Json.Object ();
                            disk.set_string_member ("id", "hda");
                            disk.set_string_member ("type", "hd");
                            disk.set_string_member ("file", edit_disk.text.strip ());
                            disk.set_string_member ("format", label_disk_fmt.label != "" ?
                                label_disk_fmt.label : "qcow2");
                            disk.set_int_member ("boot_index", 1);
                            devs.add_object_element (disk);
                        }
                    }
                }
            }
        }

        // Network
        if (config.has_member ("networking")) {
            var networking = config.get_object_member ("networking");
            networking.set_string_member ("type",
                ((Gtk.StringList) combo_net.model).get_string (combo_net.selected));
        }

        // Devices
        if (config.has_member ("devices")) {
            var devices = config.get_array_member ("devices");
            // Remove optional devices, keep VGA (first element)
            for (var i = (int) devices.get_length () - 1; i >= 1; i--) {
                var dev = devices.get_object_element (i);
                var t = dev.get_string_member ("type");
                if (t in new string[] { "voodoo3", "hypback", "sb16" }) {
                    devices.remove_element (i);
                }
            }

            if (chk_voodoo.active) {
                var v = new Json.Object ();
                v.set_string_member ("type", "voodoo3");
                v.set_int_member ("vram_mb", 64);
                devices.add_object_element (v);
            }
            if (chk_hypback.active) {
                var h = new Json.Object ();
                h.set_string_member ("type", "hypback");
                h.set_string_member ("id", "hbe0");
                devices.add_object_element (h);
            }
            if (chk_sb16.active) {
                var s = new Json.Object ();
                s.set_string_member ("type", "sb16");
                s.set_int_member ("irq", 5);
                s.set_int_member ("dma", 1);
                s.set_int_member ("dma16", 5);
                devices.add_object_element (s);
            }
        }

        // Persist
        config_store.save_config (vm_name, config);
        status_label.label = "✓ Config saved";
        config_saved (vm_name, old_name);
    }

    // ---- Helpers ----

    private void select_in_combo (Gtk.DropDown combo, string value) {
        var model = (Gtk.StringList) combo.model;
        for (var i = 0; i < model.get_n_items (); i++) {
            if (model.get_string (i) == value) {
                combo.selected = i;
                return;
            }
        }
    }
}
