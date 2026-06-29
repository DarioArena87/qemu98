/*
 * qmp-client.vala — Async QMP client over Unix domain socket
 *
 * Connects to a QEMU QMP socket via GIO async I/O, handles the greeting
 * handshake (qmp_capabilities), sends JSON-RPC commands, and dispatches
 * incoming events to registered handlers.
 *
 * Phase 2: connect, greet, command dispatch. Block device and snapshot
 * commands deferred.
 */

public class QmpClient : GLib.Object {

    // ---- State ----

    /** Connection state. */
    public enum State {
        DISCONNECTED,
        CONNECTING,
        NEGOTIATING,
        READY,
        ERROR
    }

    /** Current connection state. */
    public State state { get; private set; default = State.DISCONNECTED; }

    // ---- Signals ----

    /** Emitted when a QMP event is received (e.g., SHUTDOWN, STOP, RESUME). */
    public signal void event_received (string event_name, Json.Object? data);

    /** Emitted when the connection state changes. */
    public signal void state_changed (State new_state);

    // ---- Internal ----

    private string socket_path;
    private GLib.SocketConnection? connection = null;
    private GLib.DataInputStream? input_stream = null;
    private GLib.OutputStream? output_stream = null;
    private uint next_command_id = 0;
    private GLib.HashTable<uint?, PendingCommand> pending;
    private GLib.Source? read_source = null;
    private bool greeting_received = false;

    /** Tracks an in-flight command waiting for a response. */
    private class PendingCommand {
        public uint64 id;
        public string command;
        public GLib.DateTime sent_at;

        public PendingCommand (uint64 id, string command) {
            this.id = id;
            this.command = command;
            this.sent_at = new GLib.DateTime.now_local ();
        }
    }

    // ---- Construction ----

    public QmpClient (string socket_path) {
        this.socket_path = socket_path;
        this.pending = new GLib.HashTable<uint?, PendingCommand> (
            GLib.int_hash, GLib.int_equal
        );
    }

    // ---- Connection ----

    /** Connect to the QMP socket asynchronously. */
    public new async bool connect (GLib.Cancellable? cancellable = null) throws GLib.Error {
        if (state != State.DISCONNECTED) {
            warning ("QmpClient: already connected or connecting");
            return false;
        }

        qmp_set_state (State.CONNECTING);

        try {
            var address = new GLib.UnixSocketAddress (socket_path);
            var client = new GLib.SocketClient ();
            connection = yield client.connect_async (address, cancellable);

            input_stream = new GLib.DataInputStream (
                connection.get_input_stream ()
            );
            input_stream.set_newline_type (GLib.DataStreamNewlineType.LF);

            output_stream = connection.get_output_stream ();

            // Start reading the QMP greeting
            qmp_set_state (State.NEGOTIATING);
            read_response.begin ();

            message ("QmpClient: connected to %s", socket_path);
            return true;
        } catch (GLib.Error e) {
            qmp_set_state (State.ERROR);
            warning ("QmpClient: connection failed: %s", e.message);
            throw e;
        }
    }

    /** Disconnect from the QMP socket. */
    public new void disconnect () {
        if (read_source != null) {
            read_source.destroy ();
            read_source = null;
        }

        if (connection != null) {
            try {
                connection.close ();
            } catch (GLib.Error e) {
                debug ("QmpClient: error closing connection: %s", e.message);
            }
            connection = null;
        }

        input_stream = null;
        output_stream = null;
        pending.remove_all ();
        greeting_received = false;
        qmp_set_state (State.DISCONNECTED);
        message ("QmpClient: disconnected");
    }

    // ---- Command dispatch ----

    /**
     * Send a QMP command and wait for the response.
     *
     * @param command   The QMP command name (e.g., "query-status")
     * @param args      Optional command arguments as a Json.Object
     * @return          The parsed response Json.Object, or null on error
     */
    public async Json.Object? send_command (
        string command,
        Json.Object? args = null
    ) throws GLib.Error {
        if (state != State.READY) {
            warning ("QmpClient: not ready to send commands (state=%s)",
                     state.to_string ());
            return null;
        }

        var id = next_command_id;
        next_command_id++;

        var cmd_obj = new Json.Object ();
        cmd_obj.set_string_member ("execute", command);
        cmd_obj.set_int_member ("id", (int64) id);

        if (args != null) {
            cmd_obj.set_object_member ("arguments", args);
        }

        var gen = new Json.Generator ();
        gen.root = new Json.Node.alloc ().init_object (cmd_obj);
        var json_str = gen.to_data (null) + "\n";

        // Track this command
        pending[id] = new PendingCommand (id, command);

        // Send
        var bytes = json_str.data;
        yield output_stream.write_async (bytes, GLib.Priority.DEFAULT, null);

        debug ("QmpClient: sent command [%lu] %s", (ulong) id, command);

        // Wait for response (simplified: return immediately, response
        // handled via read_response loop and signals)
        // In Phase 2, we just send; the response will arrive via the
        // read loop and be dispatched via signals.

        return null; // Response arrives asynchronously via read loop
    }

    /**
     * Send a QMP command synchronously (non-async wrapper).
     * Use this for fire-and-forget commands.
     */
    public void send_command_sync (string command, Json.Object? args = null) {
        if (state != State.READY) {
            return;
        }

        var id = next_command_id;
        next_command_id++;

        var cmd_obj = new Json.Object ();
        cmd_obj.set_string_member ("execute", command);
        cmd_obj.set_int_member ("id", (int64) id);

        if (args != null) {
            cmd_obj.set_object_member ("arguments", args);
        }

        var gen = new Json.Generator ();
        gen.root = new Json.Node.alloc ().init_object (cmd_obj);
        var json_str = gen.to_data (null) + "\n";

        try {
            output_stream.write (json_str.data);
            pending[id] = new PendingCommand (id, command);
            debug ("QmpClient: sent command [%lu] %s (sync)", (ulong) id, command);
        } catch (GLib.Error e) {
            warning ("QmpClient: failed to send command: %s", e.message);
        }
    }

    // ---- Response reader ----

    /** Async loop that reads QMP responses and events from the socket. */
    private async void read_response () {
        while (connection != null && !connection.is_closed ()) {
            try {
                var line = yield input_stream.read_line_async (
                    GLib.Priority.DEFAULT, null
                );

                if (line == null) {
                    // EOF — connection closed
                    message ("QmpClient: connection closed by peer");
                    break;
                }

                if (line.strip () == "") {
                    continue; // skip empty lines
                }

                process_message (line);
            } catch (GLib.Error e) {
                if (e is GLib.IOError.CLOSED) {
                    message ("QmpClient: read stream closed");
                } else {
                    warning ("QmpClient: read error: %s", e.message);
                }
                break;
            }
        }

        // Connection lost
        qmp_set_state (State.ERROR);
        disconnect ();
    }

    /** Process a single JSON message from QEMU. */
    private void process_message (string line) {
        var parser = new Json.Parser ();
        try {
            parser.load_from_data (line);
        } catch (GLib.Error e) {
            warning ("QmpClient: failed to parse JSON: %s", e.message);
            return;
        }

        var root = parser.get_root ();
        if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
            return;
        }

        var obj = root.get_object ();

        // Check for QMP greeting
        if (!greeting_received && obj.has_member ("QMP")) {
            handle_greeting (obj);
            return;
        }

        // Check for event
        if (obj.has_member ("event")) {
            handle_event (obj);
            return;
        }

        // Check for command return/error
        if (obj.has_member ("return") || obj.has_member ("error")) {
            handle_response (obj);
            return;
        }
    }

    /** Handle the QMP greeting handshake. */
    private void handle_greeting (Json.Object obj) {
        var qmp = obj.get_object_member ("QMP");
        var version = qmp.get_object_member ("version");
        var qemu_ver = version.get_object_member ("qemu");

        var major = qemu_ver.get_int_member ("major");
        var minor = qemu_ver.get_int_member ("minor");
        var micro = qemu_ver.get_int_member ("micro");

        message ("QmpClient: QEMU %s.%s.%s QMP greeting received",
                 major.to_string (), minor.to_string (), micro.to_string ());

        greeting_received = true;

        // Send qmp_capabilities to complete negotiation
        send_command_sync ("qmp_capabilities", null);

        qmp_set_state (State.READY);
        message ("QmpClient: negotiation complete — ready");
    }

    /** Handle an async QMP event. */
    private void handle_event (Json.Object obj) {
        var event_name = obj.get_string_member ("event");
        Json.Object? event_data = null;

        if (obj.has_member ("data")) {
            event_data = obj.get_object_member ("data");
        }

        message ("QmpClient: event received: %s", event_name);
        event_received (event_name, event_data);
    }

    /** Handle a command response. */
    private void handle_response (Json.Object obj) {
        var id = (uint) obj.get_int_member ("id");

        if (pending.contains (id)) {
            pending.remove (id);
        }

        if (obj.has_member ("error")) {
            var error = obj.get_object_member ("error");
            warning ("QmpClient: command error: %s",
                     error.get_string_member ("desc"));
        }
    }

    // ---- Helpers ----

    private void qmp_set_state (State new_state) {
        if (state != new_state) {
            state = new_state;
            state_changed (new_state);
        }
    }
}
