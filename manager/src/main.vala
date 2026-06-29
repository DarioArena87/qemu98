/*
 * main.vala — QEMU98 Manager entry point
 *
 * GtkApplication subclass that owns the application lifecycle.
 * Creates the main window with menu bar and VM list sidebar.
 *
 * Phase 1: window + menu + config store
 * Phase 2: VM list + controller + start/stop lifecycle
 */

public class Qemu98Manager : Gtk.Application {

    private Gtk.ApplicationWindow? main_window = null;
    private ConfigStore config_store;
    private VmList vm_list;
    private GLib.HashTable<string, VmController> controllers;

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
        // Stop all running VMs
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

        // ---- Menu Bar ----
        var menu_bar = build_menu_bar ();
        var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        main_box.append (menu_bar);

        // ---- Content area ----
        var content = build_content ();
        main_box.append (content);

        main_window.child = main_box;
    }

    private Gtk.PopoverMenuBar build_menu_bar () {
        var menu_model = new GLib.Menu ();

        // Machine menu
        var machine_menu = new GLib.Menu ();
        machine_menu.append ("New VM…", "app.new-vm");
        machine_menu.append ("Import…", "app.import-vm");
        machine_menu.append_section (null, new GLib.Menu ());
        machine_menu.append ("Start VM", "app.start-vm");
        machine_menu.append ("Stop VM", "app.stop-vm");
        machine_menu.append_section (null, new GLib.Menu ());
        machine_menu.append ("Quit", "app.quit");
        menu_model.append_submenu ("Machine", machine_menu);

        // View menu
        var view_menu = new GLib.Menu ();
        view_menu.append ("Refresh", "app.refresh");
        menu_model.append_submenu ("View", view_menu);

        // Help menu
        var help_menu = new GLib.Menu ();
        help_menu.append ("About", "app.about");
        menu_model.append_submenu ("Help", help_menu);

        // Actions
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

        var quit_action = new SimpleAction ("quit", null);
        quit_action.activate.connect (() => {
            main_window.close ();
        });
        actions.add_action (quit_action);

        var refresh_action = new SimpleAction ("refresh", null);
        refresh_action.activate.connect (on_refresh);
        actions.add_action (refresh_action);

        var about_action = new SimpleAction ("about", null);
        about_action.activate.connect (on_about);
        actions.add_action (about_action);

        main_window.insert_action_group ("app", actions);

        var menu_bar = new Gtk.PopoverMenuBar.from_model (menu_model);
        return menu_bar;
    }

    private Gtk.Widget build_content () {
        var paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL) {
            position = 220
        };

        // Sidebar: VM list widget (Phase 2)
        vm_list = new VmList (config_store);
        vm_list.vm_selected.connect (on_vm_selected);
        vm_list.vm_activated.connect (on_vm_activated);
        paned.start_child = vm_list;

        // Main area: welcome / editor area (deferred to Phase 3)
        var main_area = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

        var welcome = new Gtk.Label ("<span size='x-large' weight='bold'>QEMU98 Manager</span>\n\nWin9x Virtual Machine Management");
        welcome.use_markup = true;
        welcome.justify = Gtk.Justification.CENTER;
        welcome.valign = Gtk.Align.CENTER;
        welcome.vexpand = true;
        main_area.append (welcome);

        paned.end_child = main_area;

        return paned;
    }

    // ---- VM list population ----

    private void populate_vm_list () {
        var names = config_store.list_vms ();
        foreach (var name in names) {
            vm_list.add_vm (name);
        }
    }

    // ---- VM lifecycle helpers ----

    private VmController? get_or_create_controller (string vm_name) {
        if (controllers.contains (vm_name)) {
            return controllers[vm_name];
        }

        var config = config_store.get_config (vm_name);
        if (config == null) {
            warning ("No config found for VM: %s", vm_name);
            return null;
        }

        var ctrl = new VmController (QEMU_BINARY, config);

        // Wire state changes to update the list widget
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
        // Phase 3: launch the New VM wizard
        message ("New VM action triggered (Phase 3: wizard)");

        // Create a quick demo VM for testing Phase 2
        var demo_name = "Win98-Demo";
        if (config_store.get_config (demo_name) != null) {
            message ("Demo VM already exists");
            return;
        }

        var config = ConfigStore.create_default_config (demo_name);
        config_store.save_config (demo_name, config);
        vm_list.add_vm (demo_name);
    }

    private void on_import_vm () {
        message ("Import VM action triggered (not yet implemented)");
    }

    private void on_start_vm () {
        // Start the first configured VM (simplified for Phase 2)
        var names = config_store.list_vms ();
        if (names.length == 0) {
            message ("No VMs configured — create one first");
            return;
        }

        string selected_name = names[0];
        var ctrl = get_or_create_controller (selected_name);
        if (ctrl != null) {
            ctrl.start ();
        }
    }

    private void on_stop_vm () {
        // Stop the first running VM (simplified for Phase 2)
        controllers.for_each ((name, ctrl) => {
            var controller = (VmController) ctrl;
            if (controller.state != VmController.VmState.STOPPED) {
                controller.stop ();
            }
        });
    }

    private void on_vm_selected (string vm_name) {
        debug ("VM selected: %s", vm_name);
    }

    private void on_vm_activated (string vm_name) {
        // Double-click/Enter on a VM toggles start/stop
        var ctrl = get_or_create_controller (vm_name);
        if (ctrl == null) {
            return;
        }

        if (ctrl.state == VmController.VmState.STOPPED) {
            ctrl.start ();
        } else if (ctrl.state == VmController.VmState.RUNNING ||
                   ctrl.state == VmController.VmState.PAUSED) {
            ctrl.stop ();
        }
    }

    private void on_refresh () {
        config_store.reload ();
        vm_list.refresh ();
        message ("VM list refreshed");
    }

    private void on_about () {
        var dialog = new Gtk.AboutDialog () {
            modal = true,
            program_name = "QEMU98 Manager",
            version = "0.1.0",
            comments = "A VirtualBox-style VM manager for Win9x-tailored QEMU.",
            website = "https://codebuff.com/qemu98",
            authors = { "QEMU98 Contributors" },
            license_type = Gtk.License.GPL_2_0
        };
        dialog.present ();
    }
}
