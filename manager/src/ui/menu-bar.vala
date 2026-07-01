/*
 * menu-bar.vala — Application menu bar
 *
 * Builds the GLib.Menu model and creates all SimpleAction instances
 * under the "app" action group. Exposes the action references that
 * need to be enabled/disabled externally (start, stop, delete).
 *
 * The caller attaches the returned PopoverMenuBar to the window and
 * connects action handlers via the exposed action properties.
 */

public class MenuBar {

    // ---- Public action references ----

    public SimpleAction start_action       { get; private set; }
    public SimpleAction stop_action        { get; private set; }
    public SimpleAction delete_action      { get; private set; }
    public SimpleAction new_vm_action      { get; private set; }
    public SimpleAction import_vm_action   { get; private set; }
    public SimpleAction create_disk_action { get; private set; }
    public SimpleAction refresh_action     { get; private set; }
    public SimpleAction preferences_action { get; private set; }
    public SimpleAction about_action       { get; private set; }
    public SimpleAction quit_action        { get; private set; }

    private SimpleActionGroup action_group;

    // ---- Construction ----

    public MenuBar() {
        this.action_group = new SimpleActionGroup();
    }

    // ---- Build ----

    /**
     * Build the menu model, create all actions, insert the action
     * group into @window, and return the PopoverMenuBar widget.
     */
    public Gtk.PopoverMenuBar build(Gtk.ApplicationWindow window) {
        var menu_model = build_menu_model();
        create_actions();
        window.insert_action_group("app", action_group);
        return new Gtk.PopoverMenuBar.from_model(menu_model);
    }

    private GLib.Menu build_menu_model() {
        var menu_model = new GLib.Menu();

        var machine_menu = new GLib.Menu();
        machine_menu.append("New VM…",      "app.new-vm");
        machine_menu.append("Import…",      "app.import-vm");
        machine_menu.append_section(null, new GLib.Menu());
        machine_menu.append("Start VM",     "app.start-vm");
        machine_menu.append("Stop VM",      "app.stop-vm");
        machine_menu.append_section(null, new GLib.Menu());
        machine_menu.append("Delete VM…",   "app.delete-vm");
        machine_menu.append_section(null, new GLib.Menu());
        machine_menu.append("Quit",         "app.quit");
        menu_model.append_submenu("Machine", machine_menu);

        var edit_menu = new GLib.Menu();
        edit_menu.append("Preferences…",    "app.preferences");
        menu_model.append_submenu("Edit", edit_menu);

        var view_menu = new GLib.Menu();
        view_menu.append("Refresh",                "app.refresh");
        view_menu.append("Create Disk Image…",     "app.create-disk");
        menu_model.append_submenu("View", view_menu);

        var help_menu = new GLib.Menu();
        help_menu.append("About", "app.about");
        menu_model.append_submenu("Help", help_menu);

        return menu_model;
    }

    /**
     * Create all SimpleAction instances and add them to the
     * internal SimpleActionGroup. The caller wires activate
     * handlers after build() returns.
     */
    private void create_actions() {
        new_vm_action = new SimpleAction("new-vm", null);
        action_group.add_action(new_vm_action);

        import_vm_action = new SimpleAction("import-vm", null);
        action_group.add_action(import_vm_action);

        start_action = new SimpleAction("start-vm", null);
        start_action.set_enabled(false);
        action_group.add_action(start_action);

        stop_action = new SimpleAction("stop-vm", null);
        stop_action.set_enabled(false);
        action_group.add_action(stop_action);

        delete_action = new SimpleAction("delete-vm", null);
        delete_action.set_enabled(false);
        action_group.add_action(delete_action);

        create_disk_action = new SimpleAction("create-disk", null);
        action_group.add_action(create_disk_action);

        refresh_action = new SimpleAction("refresh", null);
        action_group.add_action(refresh_action);

        preferences_action = new SimpleAction("preferences", null);
        action_group.add_action(preferences_action);

        about_action = new SimpleAction("about", null);
        action_group.add_action(about_action);

        quit_action = new SimpleAction("quit", null);
        action_group.add_action(quit_action);
    }
}
