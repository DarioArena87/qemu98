/*
 * vm-list.vala — Sidebar VM list widget
 *
 * Displays configured VMs with status indicators (stopped, running,
 * paused, error). Uses a Gtk.ListView backed by a Gio.ListStore.
 *
 * Phase 2: name + status indicator. Config editor and context actions
 * deferred to Phase 3.
 */

public class VmList : Gtk.Box {

    // ---- Data model ----

    /** Represents a single VM entry in the list. */
    public class VmEntry : GLib.Object {
        public string name { get; set; }
        public VmController.VmState state { get; set; }
        public bool selected { get; set; default = false; }

        public VmEntry (string name, VmController.VmState state = VmController.VmState.STOPPED) {
            this.name = name;
            this.state = state;
        }
    }

    // ---- Internal ----

    private GLib.ListStore model;
    private Gtk.SingleSelection selection;
    private Gtk.ListView list_view;
    private GLib.HashTable<string, VmEntry> entries;
    private ConfigStore config_store;

    // ---- Signals ----

    /** Emitted when the user selects a VM. */
    public signal void vm_selected (string vm_name);

    /** Emitted when the user double-clicks or activates a VM. */
    public signal void vm_activated (string vm_name);

    // ---- Construction ----

    public VmList (ConfigStore config_store) {
        Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);

        this.config_store = config_store;
        this.entries = new GLib.HashTable<string, VmEntry> (
            GLib.str_hash, GLib.str_equal
        );

        add_css_class ("sidebar");
        width_request = 200;

        // Title
        var title = new Gtk.Label ("VM List");
        title.add_css_class ("title-4");
        title.margin_start = 12;
        title.margin_top = 12;
        title.margin_bottom = 8;
        title.halign = Gtk.Align.START;
        append (title);

        // List model
        model = new GLib.ListStore (typeof (VmEntry));

        // Selection
        selection = new Gtk.SingleSelection (model);
        selection.selection_changed.connect (on_selection_changed);

        // List view
        list_view = new Gtk.ListView (selection, null);

        // Factory for list items
        var factory = new Gtk.SignalListItemFactory ();
        factory.setup.connect (on_list_item_setup);
        factory.bind.connect (on_list_item_bind);
        factory.unbind.connect (on_list_item_unbind);
        list_view.factory = factory;

        // Activate on double-click or Enter
        list_view.activate.connect (on_list_activate);

        var scroller = new Gtk.ScrolledWindow () {
            child = list_view,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vexpand = true
        };
        append (scroller);

        // Note: GTK4 ListView does not have a "child" property for
        // empty-state placeholders. We handle the empty state by
        // checking model size in consumers. A dedicated placeholder
        // widget will be added in Phase 3 alongside the config editor.

        // Populate from config store
        refresh ();
    }

    // ---- Public API ----

    /** Reload the VM list from the config store. */
    public void refresh () {
        entries.remove_all ();
        model.remove_all ();

        var vm_names = config_store.list_vms ();

        for (var i = 0; i < vm_names.length; i++) {
            var entry = new VmEntry (vm_names[i]);
            entries[vm_names[i]] = entry;
            model.append (entry);
        }
    }

    /** Add a VM entry to the list. */
    public void add_vm (string name) {
        if (entries.contains (name)) {
            return;
        }

        var entry = new VmEntry (name);
        entries[name] = entry;
        model.append (entry);
    }

    /** Remove a VM entry from the list. */
    public void remove_vm (string name) {
        if (!entries.contains (name)) {
            return;
        }

        var entry = entries[name];
        entries.remove (name);

        // Find and remove from model
        for (var i = 0; i < model.get_n_items (); i++) {
            if (model.get_item (i) == entry) {
                model.remove (i);
                break;
            }
        }
    }

    /** Update the status indicator for a VM. */
    public void set_vm_state (string vm_name, VmController.VmState state) {
        if (!entries.contains (vm_name)) {
            return;
        }

        var entry = entries[vm_name];
        entry.state = state;

        // Notify the model that the item changed
        for (var i = 0; i < model.get_n_items (); i++) {
            if (model.get_item (i) == entry) {
                model.items_changed (i, 0, 0); // notify without add/remove
                break;
            }
        }
    }

    // ---- List item factory callbacks ----

    private void on_list_item_setup (GLib.Object item) {
        var list_item = (Gtk.ListItem) item;

        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        row.margin_start = 8;
        row.margin_end = 8;
        row.margin_top = 4;
        row.margin_bottom = 4;

        // Status dot
        var dot = new Gtk.DrawingArea () {
            width_request = 10,
            height_request = 10,
            valign = Gtk.Align.CENTER
        };
        dot.set_draw_func (draw_status_dot);
        dot.set_data<string> ("state", "stopped");
        row.append (dot);

        // VM name
        var label = new Gtk.Label ("");
        label.halign = Gtk.Align.START;
        label.hexpand = true;
        label.ellipsize = Pango.EllipsizeMode.END;
        row.append (label);

        list_item.child = row;
    }

    private void on_list_item_bind (GLib.Object item) {
        var list_item = (Gtk.ListItem) item;
        var entry = (VmEntry) list_item.item;
        var row = (Gtk.Box) list_item.child;
        // dot is at index 0
        var dot = (Gtk.DrawingArea) row.get_first_child ();
        // label is at index 1
        var label = (Gtk.Label) dot.get_next_sibling ();

        label.label = entry.name;
        dot.set_data<string> ("state",
            entry.state == VmController.VmState.RUNNING ? "running" :
            entry.state == VmController.VmState.PAUSED ? "paused" :
            entry.state == VmController.VmState.ERROR ? "error" :
            "stopped"
        );
        dot.queue_draw ();
    }

    private void on_list_item_unbind (GLib.Object item) {
        var list_item = (Gtk.ListItem) item;
        var row = (Gtk.Box) list_item.child;
        var label = (Gtk.Label) row.get_last_child ();
        label.label = "";
    }

    /** Draw a colored dot indicating VM state. */
    private void draw_status_dot (
        Gtk.DrawingArea area,
        Cairo.Context cr,
        int width,
        int height
    ) {
        var state = area.get_data<string> ("state");
        var color = Gdk.RGBA ();

        switch (state) {
            case "running":
                color.parse ("#4CAF50"); // green
                break;
            case "paused":
                color.parse ("#FFC107"); // amber
                break;
            case "error":
                color.parse ("#F44336"); // red
                break;
            default: // stopped
                color.parse ("#9E9E9E"); // grey
                break;
        }

        cr.set_source_rgba (color.red, color.green, color.blue, color.alpha);
        cr.arc (width / 2.0, height / 2.0, 4.0, 0, 2 * Math.PI);
        cr.fill ();
    }

    // ---- Selection / activation ----

    private void on_selection_changed () {
        var selected = (VmEntry?) selection.selected_item;
        if (selected != null) {
            vm_selected (selected.name);
        }
    }

    private void on_list_activate (uint position) {
        var entry = (VmEntry?) model.get_item (position);
        if (entry != null) {
            vm_activated (entry.name);
        }
    }
}
