/*
 * main.vala — QEMU98 Manager entry point
 *
 * GtkApplication subclass that owns the application lifecycle.
 * Creates the main window with menu bar and VM list sidebar.
 *
 * Phase 1: window + menu + config store
 * Phase 2: VM list + controller + start/stop lifecycle
 * Phase 3: New VM wizard, config editor, disk image wizard
 */

public class Qemu98Manager : Gtk.Application {

    private Gtk.ApplicationWindow? main_window = null;
    private ConfigStore config_store;
    private VmList vm_list;
    private GLib.HashTable<string, VmController> controllers;

    // Main area widgets (swapped based on selection)
    private Gtk.Stack main_stack;
    private Gtk.Label welcome_page;
    private VmConfigEditor config_editor;

    /** Path to qemu-system-i386. Searches PATH at runtime. */
    private const string QEMU_BINARY = "qemu-system-i386";

    public Qemu98Manager () {
        Object (
            application_id: "com.qemu98.manager",
            flags: ApplicationFlags.DEFAULT_FLAGS
        );
    }

    public static int main (string[] args) {
        var app = new Qemu98Manager ();
        return app.run (args);
    }

    protected override void activate () {
        if (main_window == null) {
            config_store = new ConfigStore ();
            controllers = new GLib.HashTable<string, VmController> (
                GLib.str_hash, GLib.str_equal
            );
            create_main_window ();
            populate_vm_list ();
        }
        main_window.present ();
    }

    protected override void shutdown () {
        controllers.for_each ((name, ctrl) => {
            var controller = (VmController) ctrl;
            if (controller.state != VmController.VmState.STOPPED) {
                controller.stop ();
            }
            controller.dispose_resources ();
        });
        base.shutdown ();
    }

    private void create_main_window () {
        main_window = new Gtk.ApplicationWindow (this) {
            title = "QEMU98 Manager",
            default_width = 900,
            default_height = 600
        };

        var menu_bar = build_menu_bar ();
        var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        main_box.append (menu_bar);
        main_box.append (build_content ());
        main_window.child = main_box;
    }

    private Gtk.PopoverMenuBar build_menu_bar () {
        var menu_model = new GLib.Menu ();

        var machine_menu = new GLib.Menu ();
        machine_menu.append ("New VM…", "app.new-vm");
        machine_menu.append ("Import…", "app.import-vm");
        machine_menu.append_section (null, new GLib.Menu ());
        machine_menu.append ("Start VM", "app.start-vm");
        machine_menu.append ("Stop VM", "app.stop-vm");
        machine_menu.append_section (null, new GLib.Menu ());
        machine_menu.append ("Quit", "app.quit");
        menu_model.append_submenu ("Machine", machine_menu);

        var view_menu = new GLib.Menu ();
        view_menu.append ("Refresh", "app.refresh");
        view_menu.append ("Create Disk Image…", "app.create-disk");
        menu_model.append_submenu ("View", view_menu);

        var help_menu = new GLib.Menu ();
        help_menu.append ("About", "app.about");
        menu_model.append_submenu ("Help", help_menu);

        var actions = new SimpleActionGroup ();

        var new_vm_action = new SimpleAction ("new-vm", null);
        new_vm_action.activate.connect (on_new_vm);
        actions.add_action (new_vm_action);

        var import_vm_action = new SimpleAction ("import-vm", null);
        import_vm_action.activate.connect (on_import_vm);
        actions.add_action (import_vm_action);

        var start_action = new SimpleAction ("start-vm", null);
        start_action.activate.connect (on_start_vm);
        actions.add_action (start_action);

        var stop_action = new SimpleAction ("stop-vm", null);
        stop_action.activate.connect (on_stop_vm);
        actions.add_action (stop_action);

        var create_disk_action = new SimpleAction ("create-disk", null);
        create_disk_action.activate.connect (on_create_disk);
        actions.add_action (create_disk_action);

        var refresh_action = new SimpleAction ("refresh", null);
        refresh_action.activate.connect (on_refresh);
        actions.add_action (refresh_action);

        var about_action = new SimpleAction ("about", null);
        about_action.activate.connect (on_about);
        actions.add_action (about_action);

        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect (() => { main_window.close (); });
        actions.add_action (quit_action);

        main_window.insert_action_group ("app", actions);
        return new Gtk.PopoverMenuBar.from_model (menu_model);
    }

    private Gtk.Widget build_content () {
        var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
            position = 220
        };

        // Sidebar
        vm_list = new VmList (config_store);
        vm_list.vm_selected.connect (on_vm_selected);
        vm_list.vm_activated.connect (on_vm_activated);
        paned.start_child = vm_list;

        // Main area: stack of pages
        main_stack = new Gtk.Stack () {
            transition_type = Gtk.StackTransitionType.CROSSFADE,
            hexpand = true,
            vexpand = true
        };

        welcome_page = new Gtk.Label (
            "<span size='x-large' weight='bold'>QEMU98 Manager</span>\n\n" +
            "Win9x Virtual Machine Management\n\n" +
            "Select a VM from the sidebar or\n" +
            "click Machine → New VM to create one."
        );
        welcome_page.use_markup = true;
        welcome_page.justify = Gtk.Justification.CENTER;
        welcome_page.valign = Gtk.Align.CENTER;
        main_stack.add_named (welcome_page, "welcome");

        config_editor = new VmConfigEditor (config_store);
        config_editor.config_saved.connect (on_config_saved);
        main_stack.add_named (config_editor, "editor");

        main_stack.visible_child = welcome_page;
        paned.end_child = main_stack;
        return paned;
    }

    // ---- VM list ----

    private void populate_vm_list () {
        foreach (var name in config_store.list_vms ()) {
            vm_list.add_vm (name);
        }
    }

    // ---- VM lifecycle ----

    private VmController? get_or_create_controller (string vm_name) {
        if (controllers.contains (vm_name))
            return controllers[vm_name];

        var config = config_store.get_config (vm_name);
        if (config == null) {
            warning ("No config found for VM: %s", vm_name);
            return null;
        }

        var ctrl = new VmController (QEMU_BINARY, config);
        ctrl.state_changed.connect ((old_state, new_state) => {
            vm_list.set_vm_state (vm_name, new_state);
        });
        ctrl.error_occurred.connect ((msg) => {
            warning ("VM '%s' error: %s", vm_name, msg);
        });
        ctrl.qmp_event.connect ((event_name, data) => {
            debug ("VM '%s' QMP event: %s", vm_name, event_name);
        });

        controllers[vm_name] = ctrl;
        return ctrl;
    }

    // ---- Action handlers ----

    private void on_new_vm () {
        var wizard = new NewVmWizard (config_store);

        wizard.close.connect (() => {
            if (wizard.result_config != null && wizard.result_name != null) {
                config_store.save_config (wizard.result_name, wizard.result_config);
                vm_list.add_vm (wizard.result_name);
                message ("VM created: %s", wizard.result_name);
            }
        });

        wizard.present ();
    }

    private void on_import_vm () {
        message ("Import VM: not yet implemented");
    }

    private void on_start_vm () {
        var names = config_store.list_vms ();
        if (names.length == 0) {
            message ("No VMs configured — create one first");
            return;
        }

        var ctrl = get_or_create_controller (names[0]);
        if (ctrl != null)
            ctrl.start ();
    }

    private void on_stop_vm () {
        controllers.for_each ((name, ctrl) => {
            var c = (VmController) ctrl;
            if (c.state != VmController.VmState.STOPPED)
                c.stop ();
        });
    }

    private void on_create_disk () {
        var dialog = new DiskImageWizard (main_window);
        dialog.present ();
        dialog.response.connect ((id) => {
            if (id == -5 && dialog.image_path != null) {
                message ("Disk image created: %s", dialog.image_path);
            }
        });
    }

    private void on_vm_selected (string vm_name) {
        config_editor.load (vm_name);
        main_stack.visible_child = config_editor;
    }

    private void on_vm_activated (string vm_name) {
        var ctrl = get_or_create_controller (vm_name);
        if (ctrl == null) return;

        if (ctrl.state == VmController.VmState.STOPPED) {
            ctrl.start ();
        } else if (ctrl.state == VmController.VmState.RUNNING ||
                   ctrl.state == VmController.VmState.PAUSED) {
            ctrl.stop ();
        }
    }

    private void on_config_saved (string vm_name, string? old_name) {
        if (old_name != null) {
            vm_list.remove_vm (old_name);
        }
        vm_list.add_vm (vm_name);
    }

    private void on_refresh () {
        config_store.reload ();
        vm_list.refresh ();
    }

    private void on_about () {
        var dialog = new Gtk.AboutDialog () {
            modal = true,
            program_name = "QEMU98 Manager",
            version = "0.2.0",
            comments = "A VirtualBox-style VM manager for Win9x-tailored QEMU.",
            website = "https://codebuff.com/qemu98",
            authors = { "QEMU98 Contributors" },
            license_type = Gtk.License.GPL_2_0
        };
        dialog.present ();
    }
}
