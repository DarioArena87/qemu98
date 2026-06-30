/*
 * snapshot-panel.vala — Snapshot list and management UI
 *
 * A Gtk.Box showing a ColumnView of VM snapshots with Take,
 * Restore, Delete, and Refresh buttons. Requires a running VM
 * (VmController) for QMP operations and a disk image path for
 * qemu-img listing.
 *
 * Phase 4: snapshot list + take/restore/delete operations.
 */

public class SnapshotPanel : Gtk.Box {

    // ---- Internal ----

    private SnapshotManager snapshot_manager;
    private VmController? controller = null;
    private string? disk_path = null;

    // ColumnView model
    private GLib.ListStore list_store;
    private Gtk.SingleSelection selection;
    private Gtk.ColumnView column_view;

    // Buttons
    private Gtk.Button take_btn;
    private Gtk.Button restore_btn;
    private Gtk.Button delete_btn;
    private Gtk.Button refresh_btn;
    private Gtk.Label status_label;
    private Gtk.Entry snapshot_name_entry;

    // Delegate type for confirm dialog callback
    private delegate void ConfirmCallback();

    // Model item class
    private class SnapshotRow : GLib.Object {
        public string snapshot_id { get; set; }
        public string snapshot_name { get; set; }
        public string snapshot_size { get; set; }
        public string snapshot_date { get; set; }
        public string snapshot_clock { get; set; }

        public SnapshotRow (SnapshotInfo info) {
            this.snapshot_id = info.id;
            this.snapshot_name = info.name;
            this.snapshot_size = info.size_str;
            this.snapshot_date = info.date;
            this.snapshot_clock = info.vm_clock;
        }
    }

    // ---- Construction ----

    public SnapshotPanel () {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);

        this.snapshot_manager = new SnapshotManager();
        this.list_store = new GLib.ListStore (typeof (SnapshotRow));
        this.selection = new Gtk.SingleSelection (list_store);

        build_ui();
    }

    // ---- Public API ----

    /** Set the active VM controller (may be null). Triggers a refresh. */
    public void set_controller(VmController? ctrl) {
        if (controller != null) {
            controller.snapshot_operation_complete.disconnect(on_snapshot_result);
        }

        controller = ctrl;

        if (controller != null) {
            disk_path = controller.get_disk_image_path();
            controller.snapshot_operation_complete.connect(on_snapshot_result);
            refresh();
        } else {
            disk_path = null;
            list_store.remove_all();
        }

        update_sensitivity();
    }

    /** Refresh the snapshot list from disk. */
    public void refresh() {
        if (disk_path == null || disk_path == "") {
            list_store.remove_all();
            status_label.label = "No disk image configured";
            return;
        }

        if (!GLib.FileUtils.test(disk_path, GLib.FileTest.EXISTS)) {
            list_store.remove_all();
            status_label.label = "Disk image not found: %s".printf(disk_path);
            return;
        }

        try {
            var snapshots = snapshot_manager.list_snapshots(disk_path);
            list_store.remove_all();
            if (snapshots != null) {
                foreach (var s in snapshots) {
                    list_store.append(new SnapshotRow (s));
                }
            }
            status_label.label = snapshots != null && snapshots.length > 0
            ? "%u snapshot(s)".printf(snapshots.length)
            : "No snapshots";
        } catch (GLib.Error e) {
            warning("SnapshotPanel: failed to list snapshots: %s", e.message);
            status_label.label = "Snapshot listing failed";
        }
    }

    // ---- UI construction ----

    private void build_ui() {
        // Header
        var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        header.margin_start = 12;
        header.margin_end = 12;
        header.margin_top = 12;

        var title = new Gtk.Label ("<b>Snapshots</b>");
        title.use_markup = true;
        title.hexpand = true;
        title.halign = Gtk.Align.START;
        header.append(title);

        // Snapshot name entry
        snapshot_name_entry = new Gtk.Entry () {
            placeholder_text = "Snapshot name",
            width_chars = 20
        };
        header.append(snapshot_name_entry);

        take_btn = new Gtk.Button.with_label ("Take");
        take_btn.add_css_class("suggested-action");
        take_btn.clicked.connect(on_take);
        header.append(take_btn);

        refresh_btn = new Gtk.Button.with_label ("Refresh");
        refresh_btn.clicked.connect(() => { refresh(); });
        header.append(refresh_btn);

        append(header);

        // ColumnView
        column_view = new Gtk.ColumnView (selection);
        column_view.hexpand = true;
        column_view.vexpand = true;

        // ID column
        var id_factory = new Gtk.SignalListItemFactory ();
        id_factory.setup.connect((obj) => {
            var item = (Gtk.ListItem) obj;
            var label = new Gtk.Label (null);
            label.halign = Gtk.Align.START;
            label.margin_start = 4;
            label.margin_end = 4;
            item.child = label;
        });
        id_factory.bind.connect((obj) => {
            var item = (Gtk.ListItem) obj;
            var label = (Gtk.Label) item.child;
            var row = (SnapshotRow) item.item;
            label.label = row.snapshot_id;
        });
        var id_col = new Gtk.ColumnViewColumn ("ID", id_factory);
        id_col.fixed_width = 60;
        column_view.append_column(id_col);

        // Name column
        var name_factory = new Gtk.SignalListItemFactory ();
        name_factory.setup.connect((obj) => {
            var item = (Gtk.ListItem) obj;
            var label = new Gtk.Label (null);
            label.halign = Gtk.Align.START;
            label.ellipsize = Pango.EllipsizeMode.END;
            label.margin_start = 4;
            label.margin_end = 4;
            item.child = label;
        });
        name_factory.bind.connect((obj) => {
            var item = (Gtk.ListItem) obj;
            var label = (Gtk.Label) item.child;
            var row = (SnapshotRow) item.item;
            label.label = row.snapshot_name;
        });
        var name_col = new Gtk.ColumnViewColumn ("Name", name_factory);
        name_col.expand = true;
        column_view.append_column(name_col);

        // Date column
        var date_factory = new Gtk.SignalListItemFactory ();
        date_factory.setup.connect((obj) => {
            var item = (Gtk.ListItem) obj;
            var label = new Gtk.Label (null);
            label.halign = Gtk.Align.START;
            label.margin_start = 4;
            label.margin_end = 4;
            item.child = label;
        });
        date_factory.bind.connect((obj) => {
            var item = (Gtk.ListItem) obj;
            var label = (Gtk.Label) item.child;
            var row = (SnapshotRow) item.item;
            label.label = row.snapshot_date;
        });
        var date_col = new Gtk.ColumnViewColumn ("Date", date_factory);
        date_col.fixed_width = 160;
        column_view.append_column(date_col);

        // Size column
        var size_factory = new Gtk.SignalListItemFactory ();
        size_factory.setup.connect((obj) => {
            var item = (Gtk.ListItem) obj;
            var label = new Gtk.Label (null);
            label.halign = Gtk.Align.END;
            label.margin_start = 4;
            label.margin_end = 4;
            item.child = label;
        });
        size_factory.bind.connect((obj) => {
            var item = (Gtk.ListItem) obj;
            var label = (Gtk.Label) item.child;
            var row = (SnapshotRow) item.item;
            label.label = row.snapshot_size;
        });
        var size_col = new Gtk.ColumnViewColumn ("Size", size_factory);
        size_col.fixed_width = 80;
        column_view.append_column(size_col);

        // Scrolled window
        var scrolled = new Gtk.ScrolledWindow ();
        scrolled.child = column_view;
        append(scrolled);

        // Action bar
        var action_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        action_bar.margin_start = 12;
        action_bar.margin_end = 12;
        action_bar.margin_bottom = 12;

        restore_btn = new Gtk.Button.with_label ("Restore");
        restore_btn.clicked.connect(on_restore);
        restore_btn.sensitive = false;
        action_bar.append(restore_btn);

        delete_btn = new Gtk.Button.with_label ("Delete");
        delete_btn.add_css_class("destructive-action");
        delete_btn.clicked.connect(on_delete);
        delete_btn.sensitive = false;
        action_bar.append(delete_btn);

        status_label = new Gtk.Label ("");
        status_label.hexpand = true;
        status_label.halign = Gtk.Align.START;
        status_label.margin_start = 12;
        action_bar.append(status_label);

        append(action_bar);

        // Enable/disable restore/delete based on selection
        selection.notify["selected"].connect(() => {
            update_sensitivity();
        });
    }

    // ---- Action handlers ----

    private void on_take() {
        if (controller == null)
        return;

        var name = snapshot_name_entry.text.strip();
        if (name == "") {
            status_label.label = "Enter a snapshot name first";
            return;
        }

        controller.take_snapshot(name);
    }

    private void on_restore() {
        if (controller == null)
        return;

        var selected = selection.selected;
        if (selected == Gtk.INVALID_LIST_POSITION)
        return;

        var row = (SnapshotRow) list_store.get_item(selected);
        var msg = @"Restore snapshot '$(row.snapshot_name)'?\nVM state will be lost.";
        show_confirm_dialog("Restore Snapshot", msg, () => {
            controller.restore_snapshot(row.snapshot_name);
        });
    }

    private void on_delete() {
        if (controller == null)
        return;

        var selected = selection.selected;
        if (selected == Gtk.INVALID_LIST_POSITION)
        return;

        var row = (SnapshotRow) list_store.get_item(selected);
        var msg = @"Delete snapshot '$(row.snapshot_name)'?\nThis cannot be undone.";
        show_confirm_dialog("Delete Snapshot", msg, () => {
            controller.delete_snapshot(row.snapshot_name);
        });
    }

    private void on_snapshot_result(string op, bool success, string message) {
        status_label.label = message;
        // Refresh the list after any operation
        if (op == "take" || op == "delete" || op == "restore") {
            GLib.Timeout.add(500, () => {
                refresh();
                return false;
            });
        }
    }

    // ---- Helpers ----

    private void update_sensitivity() {
        var has_vm = controller != null;
        take_btn.sensitive = has_vm;

        var has_selection = selection.selected != Gtk.INVALID_LIST_POSITION;
        restore_btn.sensitive = has_vm && has_selection;
        delete_btn.sensitive = has_vm && has_selection;
        refresh_btn.sensitive = disk_path != null && disk_path != "";
    }

    /** Show a simple confirmation dialog with OK/Cancel. */
    private void show_confirm_dialog(string title_text, string message_text, ConfirmCallback on_ok) {
        var dialog = new Gtk.AlertDialog (title_text);
        dialog.set_detail(message_text);
        var buttons = new string[] { "Cancel", "OK" };
        dialog.set_buttons(buttons);

        unowned var main_window = (Gtk.ApplicationWindow) get_root();
        dialog.choose.begin(main_window, null, (obj, res) => {
            try {
                var response = dialog.choose.end(res);
                if (response == 1 && on_ok != null) {
                    on_ok();
                }
            } catch (GLib.Error e) {
                warning("SnapshotPanel: dialog error: %s", e.message);
            }
        });
    }
}
