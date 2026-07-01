/*
 * main.vala — QEMU98 Manager entry point
 *
 * GtkApplication subclass that orchestrates the UI components
 * (MenuBar, MissingBinaryBar, MainContent) and manages the VM
 * controller lifecycle. Application actions are created by MenuBar;
 * Qemu98Manager connects their handlers and coordinates between
 * the UI and backend services (ConfigStore, VmController).
 */

public class Qemu98Manager : Gtk.Application {

    private Gtk.ApplicationWindow? main_window = null;

    // Application services
    private AppConfig   app_config;
    private ConfigStore config_store;

    // UI components
    private MenuBar          menu_bar;
    private MissingBinaryBar missing_binary_bar;
    private MainContent      main_content;

    // Action references (owned by MenuBar, stored for enable/disable)
    private SimpleAction start_action;
    private SimpleAction stop_action;
    private SimpleAction delete_action;

    // VM controllers
    private GLib.HashTable<string, VmController> controllers;

    // Currently selected VM
    private string? current_vm = null;

    public Qemu98Manager() {
        Object(application_id: "com.qemu98.manager",
               flags: ApplicationFlags.DEFAULT_FLAGS);
    }

    public static int main(string[] args) {
        var app = new Qemu98Manager();
        return app.run(args);
    }

    // ---- Application lifecycle ----

    protected override void activate() {
        if (main_window == null) {
            app_config   = AppConfig.load();
            config_store = new ConfigStore(app_config.get_effective_base_dir());
            controllers  = new GLib.HashTable<string, VmController>(
                GLib.str_hash, GLib.str_equal);

            create_main_window();
            on_binary_validated();

            // VmList.refresh() auto-selects the first VM, but the
            // vm_selected signal fires before we connected to it.
            var names = config_store.list_vms();
            if (names.length > 0)
                on_vm_selected(names[0]);
        }
        main_window.present();
    }

    protected override void shutdown() {
        controllers.for_each((name, ctrl) => {
            var controller = (VmController) ctrl;
            if (controller.state != VmController.VmState.STOPPED)
                controller.stop();
            controller.dispose_resources();
        });
        base.shutdown();
    }

    // ---- Window construction ----

    private void create_main_window() {
        main_window = new Gtk.ApplicationWindow(this) {
            title = "QEMU98 Manager",
            default_width = 900,
            default_height = 600
        };

        // --- Menu bar ---
        menu_bar = new MenuBar();
        var popover_bar = menu_bar.build(main_window);

        // Capture action references for enable/disable
        start_action  = menu_bar.start_action;
        stop_action   = menu_bar.stop_action;
        delete_action = menu_bar.delete_action;

        wire_menu_actions();

        // --- Missing-binary banner ---
        missing_binary_bar = new MissingBinaryBar();

        // --- Main content ---
        var config_editor  = new VmConfigEditor(config_store);
        var snapshot_panel = new SnapshotPanel();
        var media_panel    = new MediaPanel();

        main_content = new MainContent(
            config_store, config_editor, snapshot_panel, media_panel);
        wire_content_signals(config_editor);

        // --- Assemble ---
        var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        main_box.append(popover_bar);
        main_box.append(missing_binary_bar.get_widget());
        main_box.append(main_content.get_widget());
        main_window.child = main_box;
    }

    // ---- Action wiring ----

    /** Connect activate handlers to each SimpleAction created by MenuBar. */
    private void wire_menu_actions() {
        menu_bar.new_vm_action.activate.connect((param) => { on_new_vm(); });
        menu_bar.import_vm_action.activate.connect((param) => { on_import_vm(); });
        menu_bar.start_action.activate.connect((param) => { on_start_vm(); });
        menu_bar.stop_action.activate.connect((param) => { on_stop_vm(); });
        menu_bar.delete_action.activate.connect((param) => { on_delete_vm(); });
        menu_bar.create_disk_action.activate.connect((param) => { on_create_disk(); });
        menu_bar.refresh_action.activate.connect((param) => { on_refresh(); });
        menu_bar.preferences_action.activate.connect((param) => { on_preferences(); });
        menu_bar.about_action.activate.connect((param) => { on_about(); });
        menu_bar.quit_action.activate.connect((param) => { main_window.close(); });
    }

    // ---- Content signal wiring ----

    private void wire_content_signals(VmConfigEditor config_editor) {
        main_content.vm_selected.connect(on_vm_selected);
        main_content.vm_activated.connect(on_vm_activated);
        main_content.vm_context_menu_requested.connect(on_vm_context_menu);
        config_editor.config_saved.connect(on_config_saved);
        config_editor.delete_requested.connect(on_delete_vm);
        config_editor.power_action_requested.connect(on_editor_power_action);
        main_content.runtime_stop_requested.connect(on_stop_current_vm);
    }

    // ---- Binary validation ----

    /**
     * Reconcile the missing-binary banner and action states with the
     * current AppConfig. Call on startup and after preferences change.
     */
    private void on_binary_validated() {
        missing_binary_bar.validate(app_config);
        update_action_states();
    }

    // ---- Action handlers ----

    private void on_new_vm() {
        var wizard = new NewVmWizard(config_store, app_config);

        wizard.response.connect((response_id) => {
            if (response_id == -5
                && wizard.result_config != null
                && wizard.result_name != null) {
                config_store.save_config(wizard.result_name,
                                         wizard.result_config);
                main_content.add_vm(wizard.result_name);
                main_content.select_vm(wizard.result_name);
                on_vm_selected(wizard.result_name);
                message("VM created: %s", wizard.result_name);
            }
        });

        wizard.present();
    }

    private void on_import_vm() {
        var buttons = new string[] { "OK" };
        var dialog = new Gtk.AlertDialog("Import VM");
        dialog.set_detail(
            "Import VM from file is not yet implemented.\n\n"
            + "You can manually copy .json config files into\n"
            + app_config.get_effective_base_dir()
            + "/<vm_name>/ and use View → Refresh.");
        dialog.set_buttons(buttons);
        dialog.choose.begin(main_window, null, (obj, res) => {
            try { dialog.choose.end(res); } catch (GLib.Error e) {}
        });
    }

    private void on_delete_vm() {
        if (current_vm == null) return;

        var vm_to_delete = current_vm;
        var buttons = new string[] { "Cancel", "Delete" };

        var dialog = new Gtk.AlertDialog("Delete VM");
        dialog.set_detail(@"Delete virtual machine '$(vm_to_delete)'?\n\n"
                         + "This will remove the configuration file.\n"
                         + "Disk images will NOT be deleted.");
        dialog.set_buttons(buttons);
        dialog.choose.begin(main_window, null, (obj, res) => {
            try {
                var response_idx = dialog.choose.end(res);
                if (response_idx == 1) {
                    // Stop if running
                    if (controllers.contains(vm_to_delete)) {
                        var ctrl = controllers[vm_to_delete];
                        if (ctrl.state != VmController.VmState.STOPPED)
                            ctrl.stop();
                    }

                    config_store.delete_config(vm_to_delete);
                    main_content.remove_vm(vm_to_delete);

                    if (current_vm == vm_to_delete) {
                        current_vm = null;
                        var names = config_store.list_vms();
                        if (names.length > 0) {
                            main_content.select_vm(names[0]);
                            on_vm_selected(names[0]);
                        } else {
                            main_content.show_welcome();
                        }
                    }

                    update_action_states();
                    message("VM deleted: %s", vm_to_delete);
                }
            } catch (GLib.Error e) {}
        });
    }

    private void on_start_vm() {
        if (current_vm == null) {
            message("No VM selected — select one from the sidebar first");
            return;
        }

        if (!app_config.qemu_binary_available) {
            warning("Cannot start: qemu binary is not available. "
                  + "Open Preferences to set a custom path.");
            return;
        }

        var ctrl = get_or_create_controller(current_vm);
        if (ctrl != null)
            ctrl.start();
    }

    private void on_stop_vm() {
        controllers.for_each((name, ctrl) => {
            var c = (VmController) ctrl;
            if (c.state != VmController.VmState.STOPPED)
                c.stop();
        });
    }

    private void on_create_disk() {
        var default_dir = GLib.Path.build_filename(
            app_config.get_effective_base_dir(), "images");
        var dialog = new DiskImageWizard(main_window, default_dir);
        dialog.present();
        dialog.response.connect((id) => {
            if (id == -5 && dialog.image_path != null) {
                message("Disk image created: %s", dialog.image_path);
            }
        });
    }

    private void on_preferences() {
        var pref_dialog = new PrefsDialog(main_window, app_config);
        pref_dialog.saved.connect(() => {
            app_config = AppConfig.load();
            invalidate_controllers();
            rebuild_config_store();

            current_vm = null;
            var names = config_store.list_vms();
            if (names.length > 0)
                on_vm_selected(names[0]);
            else
                main_content.show_welcome();

            on_binary_validated();
        });
        pref_dialog.present();
    }

    private void on_refresh() {
        config_store.reload();
        main_content.refresh();
    }

    private void on_about() {
        var authors = new string[] { "QEMU98 Contributors" };
        var dialog = new Gtk.AboutDialog() {
            modal = true,
            program_name = "QEMU98 Manager",
            version = "0.3.0",
            comments = "A VirtualBox-style VM manager for Win9x-tailored QEMU.",
            website = "https://codebuff.com/qemu98",
            authors = authors,
            license_type = Gtk.License.GPL_2_0
        };
        dialog.present();
    }

    // ---- VM selection ----

    private void on_vm_selected(string vm_name) {
        current_vm = vm_name;

        var ctrl = controllers[vm_name];
        bool is_running = ctrl != null &&
            (ctrl.state == VmController.VmState.RUNNING ||
             ctrl.state == VmController.VmState.PAUSED);

        if (is_running) {
            main_content.show_runtime(ctrl);
        } else {
            main_content.show_editor(vm_name);
        }

        main_content.config_editor.set_vm_power_state(is_running, vm_name);
        update_action_states();
    }

    /** Handle Start/Stop button in the config editor. */
    private void on_editor_power_action(string vm_name) {
        if (current_vm != vm_name) {
            main_content.select_vm(vm_name);
            current_vm = vm_name;
        }
        on_vm_activated(vm_name);
    }

    /** Handle runtime Stop button — stops the current VM. */
    private void on_stop_current_vm() {
        if (current_vm != null && controllers.contains(current_vm)) {
            var c = controllers[current_vm];
            if (c.state != VmController.VmState.STOPPED)
                c.stop();
        }
    }

    private void on_vm_activated(string vm_name) {
        var ctrl = get_or_create_controller(vm_name);
        if (ctrl == null) return;

        if (!app_config.qemu_binary_available) {
            warning("Cannot start: qemu binary is not available. "
                  + "Open Preferences to set a custom path.");
            return;
        }

        if (ctrl.state == VmController.VmState.STOPPED) {
            ctrl.start();
        } else if (ctrl.state == VmController.VmState.RUNNING
                   || ctrl.state == VmController.VmState.PAUSED
                   || ctrl.state == VmController.VmState.STARTING) {
            ctrl.stop();
        }
    }

    private void on_vm_context_menu(string vm_name, double x, double y) {
        main_content.select_vm(vm_name);

        var menu = new GLib.Menu();
        menu.append("Start",     "app.start-vm");
        menu.append("Stop",      "app.stop-vm");
        menu.append("Delete…",   "app.delete-vm");

        var popover = new Gtk.PopoverMenu.from_model(menu);
        popover.set_parent(main_content.vm_list);
        popover.set_has_arrow(false);
        popover.set_position(Gtk.PositionType.RIGHT);
        popover.popup();
    }

    private void on_config_saved(string vm_name, string? old_name) {
        if (old_name != null)
            main_content.remove_vm(old_name);
        main_content.add_vm(vm_name);
        update_action_states();
    }

    // ---- Action state management ----

    private void update_action_states() {
        bool has_vm = current_vm != null
            && config_store.get_config(current_vm) != null;
        bool binary_ok = app_config.qemu_binary_available;

        if (start_action != null)
            start_action.set_enabled(has_vm && binary_ok);
        if (delete_action != null)
            delete_action.set_enabled(has_vm);

        bool is_running = false;
        if (has_vm && controllers.contains(current_vm)) {
            var c = controllers[current_vm];
            is_running = c.state == VmController.VmState.RUNNING
                      || c.state == VmController.VmState.PAUSED
                      || c.state == VmController.VmState.STARTING;
        }
        if (stop_action != null)
            stop_action.set_enabled(is_running);
    }

    // ---- Controller lifecycle ----

    private VmController? get_or_create_controller(string vm_name) {
        if (controllers.contains(vm_name))
            return controllers[vm_name];

        var config = config_store.get_config(vm_name);
        if (config == null) {
            warning("No config found for VM: %s", vm_name);
            return null;
        }

        var binary = app_config.get_effective_qemu_binary();
        if (binary == null) {
            warning("VmController[%s] created without a usable qemu binary — start() will refuse.", vm_name);
            binary = "";
        }
        var ctrl = new VmController(binary, config);

        ctrl.state_changed.connect((old_state, new_state) => {
            main_content.set_vm_state(vm_name, new_state);
            if (vm_name == current_vm) {
                main_content.update_page(ctrl);
                bool running = new_state == VmController.VmState.RUNNING
                            || new_state == VmController.VmState.PAUSED
                            || new_state == VmController.VmState.STARTING;
                main_content.config_editor.set_vm_power_state(running, vm_name);
                update_action_states();
            }
        });

        ctrl.error_occurred.connect((msg) => {
            warning("VM '%s' error: %s", vm_name, msg);
        });

        ctrl.qmp_event.connect((event_name, data) => {
            debug("VM '%s' QMP event: %s", vm_name, event_name);
        });

        ctrl.snapshot_operation_complete.connect((op, success, msg) => {
            message("VM '%s' snapshot %s: %s", vm_name, op, msg);
        });

        ctrl.media_operation_complete.connect((device, success, msg) => {
            message("VM '%s' media on %s: %s", vm_name, device, msg);
        });

        controllers[vm_name] = ctrl;
        return ctrl;
    }

    private void invalidate_controllers() {
        var names = new string[controllers.size()];
        int i = 0;
        controllers.for_each((k, v) => {
            names[i++] = (string) k;
        });
        foreach (var name in names) {
            var c = controllers[name];
            if (c.state != VmController.VmState.STOPPED
                && c.state != VmController.VmState.ERROR)
                c.stop();
            c.dispose_resources();
            controllers.remove(name);
        }
    }

    private void rebuild_config_store() {
        config_store = new ConfigStore(app_config.get_effective_base_dir());
        if (main_content != null)
            main_content.set_config_store(config_store);
    }
}
