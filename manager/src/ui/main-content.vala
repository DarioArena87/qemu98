/*
 * main-content.vala — Main content area (sidebar + stacked pages)
 *
 * Wraps a Gtk.Paned holding the VmList sidebar and a Gtk.Stack that
 * contains:
 *   - welcome page (no VM selected)
 *   - VmConfigEditor (VM stopped)
 *   - runtime notebook (VM running, with SnapshotPanel + MediaPanel)
 *
 * Emits domain-level signals for VM selection, activation, and
 * context-menu requests, decoupling the Qemu98Manager from the
 * internal layout details.
 */

public class MainContent {

    // ---- Public children (read-only access for the manager) ----

    public VmList         vm_list        { get; private set; }
    public VmConfigEditor config_editor  { get; private set; }
    public SnapshotPanel  snapshot_panel { get; private set; }
    public MediaPanel     media_panel    { get; private set; }

    // ---- Signals ----

    /** Emitted when the user selects (clicks) a VM in the sidebar. */
    public signal void vm_selected(string vm_name);

    /** Emitted when the user double-clicks / activates a VM entry. */
    public signal void vm_activated(string vm_name);

    /** Emitted on right-click on a VM entry. Coordinates are widget-relative. */
    public signal void vm_context_menu_requested(string vm_name, double x, double y);

    // ---- Internal ----

    private Gtk.Paned   paned;
    private Gtk.Stack   main_stack;
    private Gtk.Label   welcome_page;
    private Gtk.Notebook runtime_notebook;

    // ---- Construction ----

    /**
     * @param config_store   Per-VM config persistence
     * @param editor         Pre-built VmConfigEditor (injected so the
     *                       manager can connect to config_saved directly)
     * @param snap_panel     Pre-built SnapshotPanel
     * @param media_pnl      Pre-built MediaPanel
     */
    public MainContent(ConfigStore    config_store,
                       VmConfigEditor editor,
                       SnapshotPanel  snap_panel,
                       MediaPanel     media_pnl) {
        this.config_editor  = editor;
        this.snapshot_panel = snap_panel;
        this.media_panel    = media_pnl;

        paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL) {
            position = 220
        };

        // ---- Sidebar ----
        vm_list = new VmList(config_store);
        vm_list.vm_selected.connect((name) => { vm_selected(name); });
        vm_list.vm_activated.connect((name) => { vm_activated(name); });
        vm_list.context_menu_requested.connect((name, x, y) => {
            vm_context_menu_requested(name, x, y);
        });
        paned.start_child = vm_list;

        // ---- Main stack ----
        main_stack = new Gtk.Stack() {
            transition_type = Gtk.StackTransitionType.CROSSFADE,
            hexpand = true,
            vexpand = true
        };

        welcome_page = new Gtk.Label(
            "<span size='x-large' weight='bold'>QEMU98 Manager</span>\n\n"
            + "Win9x Virtual Machine Management\n\n"
            + "Select a VM from the sidebar or\n"
            + "click Machine → New VM to create one."
        );
        welcome_page.use_markup = true;
        welcome_page.justify = Gtk.Justification.CENTER;
        welcome_page.valign = Gtk.Align.CENTER;
        main_stack.add_named(welcome_page, "welcome");

        main_stack.add_named(config_editor, "editor");

        runtime_notebook = new Gtk.Notebook();
        runtime_notebook.hexpand = true;
        runtime_notebook.vexpand = true;
        runtime_notebook.append_page(snapshot_panel, new Gtk.Label("Snapshots"));
        runtime_notebook.append_page(media_panel,    new Gtk.Label("Media"));
        main_stack.add_named(runtime_notebook, "runtime");

        main_stack.visible_child = welcome_page;
        paned.end_child = main_stack;
    }

    /** Return the wrapped Gtk.Paned for embedding in the window. */
    public Gtk.Widget get_widget() {
        return paned;
    }

    // ---- Page switching ----

    /** Show the welcome page (no VM selected). */
    public void show_welcome() {
        main_stack.visible_child = welcome_page;
    }

    /** Show the config editor for a stopped VM. */
    public void show_editor(string vm_name) {
        snapshot_panel.set_controller(null);
        media_panel.set_controller(null);
        config_editor.load(vm_name);
        main_stack.visible_child_name = "editor";
    }

    /** Show the runtime notebook for a running/paused VM. */
    public void show_runtime(VmController ctrl) {
        snapshot_panel.set_controller(ctrl);
        media_panel.set_controller(ctrl);
        main_stack.visible_child_name = "runtime";
    }

    /** Update the page based on VM state for the currently active VM. */
    public void update_page(VmController? ctrl) {
        if (ctrl != null &&
            (ctrl.state == VmController.VmState.RUNNING ||
             ctrl.state == VmController.VmState.PAUSED)) {
            show_runtime(ctrl);
        } else {
            snapshot_panel.set_controller(null);
            media_panel.set_controller(null);
            main_stack.visible_child_name = "editor";
        }
    }

    // ---- VmList proxy methods ----

    public void set_vm_state(string vm_name, VmController.VmState state) {
        vm_list.set_vm_state(vm_name, state);
    }

    public void add_vm(string name) {
        vm_list.add_vm(name);
    }

    public void remove_vm(string name) {
        vm_list.remove_vm(name);
    }

    public void select_vm(string name) {
        vm_list.select_vm(name);
    }

    public void refresh() {
        vm_list.refresh();
    }

    public void set_config_store(ConfigStore store) {
        vm_list.set_config_store(store);
    }
}
