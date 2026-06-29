/*
 * main.vala — QEMU98 Manager entry point
 *
 * GtkApplication subclass that owns the application lifecycle.
 * Creates the main window with menu bar and VM list sidebar.
 *
 * Phase 1: window + menu + config store
 * Phase 2: VM list + controller + start/stop lifecycle
 * Phase 3: New VM wizard, config editor, disk image wizard
 * Phase 4: Snapshot panel, media panel, runtime operations
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
    private Gtk.Notebook runtime_notebook;
    private SnapshotPanel snapshot_panel;
    private MediaPanel media_panel;

    // Currently selected VM name
    private string? current_vm = null;

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

            // VmList.refresh() auto-selects the first VM during construction,
            // but the vm_selected signal was emitted before we connected to it.
            // Manually trigger the handler for the first VM so current_vm,
            // the config editor, and action states are all properly synced.
            var names = config_store.list_vms ();
            if (names.length > 0)
                on_vm_selected (names[0]);
        }
        main_window.present ();
    }

    protected override void shutdown () {
        controllers.for_each ((name, ctrl) => {
            var controller = (VmController) ctrl;
            if (controller.state != VmController.VmState.STOPPED)
                controller.stop ();
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

    // Track action references for enable/disable
    private SimpleAction start_action;
    private SimpleAction stop_action;
    private SimpleAction delete_action;

    private Gtk.PopoverMenuBar build_menu_bar () {
        var menu_model = new GLib.Menu ();

        var machine_menu = new GLib.Menu ();
        machine_menu.append ("New VM…", "app.new-vm");
        machine_menu.append ("Import…", "app.import-vm");
        machine_menu.append_section (null, new GLib.Menu ());
        machine_menu.append ("Start VM", "app.start-vm");
        machine_menu.append ("Stop VM", "app.stop-vm");
        machine_menu.append_section (null, new GLib.Menu ());
        machine_menu.append ("Delete VM…", "app.delete-vm");
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

        start_action = new SimpleAction ("start-vm", null);
        start_action.activate.connect (on_start_vm);
        start_action.set_enabled (false);
        actions.add_action (start_action);

        stop_action = new SimpleAction ("stop-vm", null);
        stop_action.activate.connect (on_stop_vm);
        stop_action.set_enabled (false);
        actions.add_action (stop_action);

        delete_action = new SimpleAction ("delete-vm", null);
        delete_action.activate.connect (on_delete_vm);
        delete_action.set_enabled (false);
        actions.add_action (delete_action);

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
        vm_list.context_menu_requested.connect (on_vm_context_menu);
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
        config_editor.delete_requested.connect (on_delete_vm);
        main_stack.add_named (config_editor, "editor");

        // Phase 4: Runtime operations notebook (snapshots + media)
        runtime_notebook = new Gtk.Notebook ();
        runtime_notebook.hexpand = true;
        runtime_notebook.vexpand = true;

        snapshot_panel = new SnapshotPanel ();
        runtime_notebook.append_page (
            snapshot_panel,
            new Gtk.Label ("Snapshots")
        );

        media_panel = new MediaPanel ();
        runtime_notebook.append_page (
            media_panel,
            new Gtk.Label ("Media")
        );

        main_stack.add_named (runtime_notebook, "runtime");

        main_stack.visible_child = welcome_page;
        paned.end_child = main_stack;
        return paned;
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
            // Switch page based on VM state for the currently selected VM
            if (vm_name == current_vm) {
                update_main_page (new_state);
                update_action_states ();
            }
        });
        ctrl.error_occurred.connect ((msg) => {
            warning ("VM '%s' error: %s", vm_name, msg);
        });
        ctrl.qmp_event.connect ((event_name, data) => {
            debug ("VM '%s' QMP event: %s", vm_name, event_name);
        });
        ctrl.snapshot_operation_complete.connect ((op, success, msg) => {
            message ("VM '%s' snapshot %s: %s", vm_name, op, msg);
        });
        ctrl.media_operation_complete.connect ((device, success, msg) => {
            message ("VM '%s' media on %s: %s", vm_name, device, msg);
        });

        controllers[vm_name] = ctrl;
        return ctrl;
    }

    /** Update the main page based on VM state. */
    private void update_main_page (VmController.VmState state) {
        if (state == VmController.VmState.RUNNING ||
            state == VmController.VmState.PAUSED) {
            main_stack.visible_child = runtime_notebook;
        } else if (state == VmController.VmState.STOPPED ||
                   state == VmController.VmState.ERROR) {
            main_stack.visible_child = config_editor;
        }
    }

    // ---- Action handlers ----

    private void on_new_vm () {
        var wizard = new NewVmWizard (config_store);

        wizard.response.connect ((response_id) => {
            if (response_id == -5 && wizard.result_config != null && wizard.result_name != null) {
                config_store.save_config (wizard.result_name, wizard.result_config);
                vm_list.add_vm (wizard.result_name);
                message ("VM created: %s", wizard.result_name);
            }
        });

        wizard.present ();
    }

    private void on_import_vm () {
        var buttons = new string[] { "OK" };
        var dialog = new Gtk.AlertDialog ("Import VM");
        dialog.set_detail ("Import VM from file is not yet implemented.\n\nYou can manually copy .json config files into\n~/.local/share/qemu98/machines/ and use View → Refresh.");
        dialog.set_buttons (buttons);
        dialog.choose.begin (main_window, null, (obj, res) => {
            try { dialog.choose.end (res); } catch (GLib.Error e) {}
        });
    }

    private void on_delete_vm () {
        if (current_vm == null)
            return;

        var vm_to_delete = current_vm;
        var buttons = new string[] { "Cancel", "Delete" };

        var dialog = new Gtk.AlertDialog ("Delete VM");
        dialog.set_detail (@"Delete virtual machine '$(vm_to_delete)'?\n\nThis will remove the configuration file.\nDisk images will NOT be deleted.");
        dialog.set_buttons (buttons);
        dialog.choose.begin (main_window, null, (obj, res) => {
            try {
                var response_idx = dialog.choose.end (res);
                if (response_idx == 1) { // "Delete" button (index 1)
                    // Stop the VM if running
                    if (controllers.contains (vm_to_delete)) {
                        var ctrl = controllers[vm_to_delete];
                        if (ctrl.state != VmController.VmState.STOPPED)
                            ctrl.stop ();
                    }

                    config_store.delete_config (vm_to_delete);
                    vm_list.remove_vm (vm_to_delete);

                    if (current_vm == vm_to_delete) {
                        current_vm = null;
                        main_stack.visible_child = welcome_page;
                    }

                    update_action_states ();
                    message ("VM deleted: %s", vm_to_delete);
                }
            } catch (GLib.Error e) {}
        });
    }

    private void on_start_vm () {
        if (current_vm == null) {
            message ("No VM selected — select one from the sidebar first");
            return;
        }

        var ctrl = get_or_create_controller (current_vm);
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
        current_vm = vm_name;
        config_editor.load (vm_name);

        // Determine which page to show
        var ctrl = controllers[vm_name];
        if (ctrl != null && (ctrl.state == VmController.VmState.RUNNING ||
                             ctrl.state == VmController.VmState.PAUSED)) {
            // VM is running — show runtime page with live controls
            snapshot_panel.set_controller (ctrl);
            media_panel.set_controller (ctrl);
            main_stack.visible_child = runtime_notebook;
        } else {
            // VM is stopped — show config editor
            snapshot_panel.set_controller (null);
            media_panel.set_controller (null);
            main_stack.visible_child = config_editor;
        }

        update_action_states ();
    }

    /** Enable/disable actions based on current VM selection state. */
    private void update_action_states () {
        bool has_vm = current_vm != null;
        start_action.set_enabled (has_vm);
        delete_action.set_enabled (has_vm);

        bool is_running = false;
        if (has_vm && controllers.contains (current_vm)) {
            var c = controllers[current_vm];
            is_running = c.state == VmController.VmState.RUNNING ||
                         c.state == VmController.VmState.PAUSED ||
                         c.state == VmController.VmState.STARTING;
        }
        stop_action.set_enabled (is_running);
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

    /** Handle right-click context menu on VM list. */
    private void on_vm_context_menu (string vm_name, double x, double y) {
        // Select the VM in the sidebar (this triggers on_vm_selected which
        // syncs current_vm, loads config, switches pages, and updates actions)
        vm_list.select_vm (vm_name);

        // Build a simple context menu with Start, Stop, Delete
        var menu = new GLib.Menu ();
        menu.append ("Start", "app.start-vm");
        menu.append ("Stop", "app.stop-vm");
        menu.append ("Delete…", "app.delete-vm");

        var popover = new Gtk.PopoverMenu.from_model (menu);
        popover.set_parent (vm_list);
        popover.set_has_arrow (false);
        popover.set_position (Gtk.PositionType.RIGHT);
        popover.popup ();
    }

    private void on_config_saved (string vm_name, string? old_name) {
        if (old_name != null) {
            vm_list.remove_vm (old_name);
        }
        vm_list.add_vm (vm_name);
        update_action_states ();
    }

    private void on_refresh () {
        config_store.reload ();
        vm_list.refresh ();
    }

    private void on_about () {
        var authors = new string[] { "QEMU98 Contributors" };
        var dialog = new Gtk.AboutDialog () {
            modal = true,
            program_name = "QEMU98 Manager",
            version = "0.3.0",
            comments = "A VirtualBox-style VM manager for Win9x-tailored QEMU.",
            website = "https://codebuff.com/qemu98",
            authors = authors,
            license_type = Gtk.License.GPL_2_0
        };
        dialog.present ();
    }
}
