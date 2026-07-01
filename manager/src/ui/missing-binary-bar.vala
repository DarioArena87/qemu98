/*
 * missing-binary-bar.vala — Missing QEMU binary warning banner
 *
 * Wraps a Gtk.InfoBar shown above the main content when the
 * qemu-system-i386 binary cannot be located. Displays a diagnostic
 * message and an "Open Preferences…" button bound to the
 * `app.preferences` action.
 *
 * Stateless: call validate() with an AppConfig to update visibility
 * and message text.
 */

public class MissingBinaryBar {

    private Gtk.InfoBar bar;
    private Gtk.Label  message_label;

    // ---- Construction ----

    public MissingBinaryBar() {
        bar = new Gtk.InfoBar() {
            message_type = Gtk.MessageType.WARNING,
            revealed = false,
            show_close_button = false
        };

        message_label = new Gtk.Label("");
        message_label.wrap = true;
        message_label.xalign = 0.0f;
        message_label.margin_top = 4;
        message_label.margin_bottom = 4;
        bar.add_child(message_label);

        var settings_btn = bar.add_button("Open Preferences…", 0);
        settings_btn.set_action_name("app.preferences");

        bar.response.connect((response_id) => {
            bar.revealed = false;
        });
    }

    // ---- Public API ----

    /** Return the wrapped InfoBar widget for embedding in the window. */
    public Gtk.Widget get_widget() {
        return bar;
    }

    /**
     * Reconcile the banner with the current AppConfig.
     *
     * Returns true if the binary is available.
     */
    public bool validate(AppConfig app_config) {
        if (app_config.qemu_binary_available) {
            bar.revealed = false;
            return true;
        }

        message_label.label =
            "QEMU binary could not be located: "
            + app_config.qemu_binary_diagnostic
            + ".\nOpen Preferences to set a custom path.";
        bar.revealed = true;
        return false;
    }
}
