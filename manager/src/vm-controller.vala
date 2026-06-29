/*
 * vm-controller.vala — Per-VM lifecycle state machine
 *
 * Owns the ProcessManager and QmpClient for a single VM. Coordinates
 * the full lifecycle: config load → process spawn → QMP connect →
 * negotiation → ready → running. Handles shutdown and crash recovery.
 *
 * Phase 2: start, stop, state machine. Pause/resume and snapshot
 * management deferred.
 */

public class VmController : GLib.Object {

    // ---- VM State ----

    /** VM lifecycle states. */
    public enum VmState {
        STOPPED,
        STARTING,
        RUNNING,
        PAUSED,
        STOPPING,
        ERROR
    }

    /** Current VM state. */
    public VmState state { get; private set; default = VmState.STOPPED; }

    // ---- Properties ----

    /** The VM name (from config). */
    public string vm_name { get; private set; }

    /** PID of the QEMU process (0 when stopped). */
    public int pid {
        get { return process_manager != null ? process_manager.pid : 0; }
    }

    /** Whether the QMP connection is ready. */
    public bool qmp_connected {
        get { return qmp_client != null && qmp_client.state == QmpClient.State.READY; }
    }

    /** The VM configuration. */
    public Json.Object config { get; private set; }

    // ---- Signals ----

    /** Emitted when the VM state changes. */
    public signal void state_changed (VmState old_state, VmState new_state);

    /** Emitted when a QMP event is received. */
    public signal void qmp_event (string event_name, Json.Object? data);

    /** Emitted on errors (launch failure, QMP failure, crash). */
    public signal void error_occurred (string message);

    // ---- Internal ----

    private ProcessManager? process_manager = null;
    private QmpClient? qmp_client = null;
    private string qemu_binary;
    private uint retry_connect_source = 0;

    // ---- Construction ----

    /**
     * @param qemu_binary  Full path to qemu-system-i386
     * @param config       VM configuration from ConfigStore
     */
    public VmController (string qemu_binary, Json.Object config) {
        this.qemu_binary = qemu_binary;
        this.config = config;
        this.vm_name = config.get_string_member ("name");
    }

    // ---- Lifecycle ----

    /** Start the VM: spawn QEMU → connect QMP → negotiate → ready. */
    public void start () {
        if (state != VmState.STOPPED) {
            warning ("VmController[%s]: cannot start — state is %s",
                     vm_name, state.to_string ());
            return;
        }

        set_vmc_state (VmState.STARTING);

        process_manager = new ProcessManager (qemu_binary, config);

        // Wire process signals
        process_manager.exited.connect (on_process_exited);
        process_manager.launch_failed.connect (on_launch_failed);

        // Spawn QEMU
        try {
            process_manager.start ();
        } catch (GLib.Error e) {
            set_vmc_state (VmState.ERROR);
            error_occurred (@"Failed to start QEMU: $(e.message)");
            return;
        }

        // Create QMP client
        qmp_client = new QmpClient (process_manager.qmp_socket_path);
        qmp_client.event_received.connect (on_qmp_event);
        qmp_client.state_changed.connect (on_qmp_state_changed);

        // Connect to QMP (with retry — QEMU needs time to create the socket)
        connect_qmp_with_retry ();
    }

    /** Retry QMP connection until the socket appears. */
    private void connect_qmp_with_retry () {
        retry_connect_source = GLib.Timeout.add (200, () => {
            if (state == VmState.ERROR || state == VmState.STOPPED) {
                retry_connect_source = 0;
                return false;
            }

            var socket_file = GLib.File.new_for_path (
                process_manager.qmp_socket_path
            );

            if (!socket_file.query_exists ()) {
                return true; // keep retrying
            }

            // Socket exists — connect
            qmp_client.connect.begin (null, (obj, res) => {
                try {
                    qmp_client.connect.end (res);
                } catch (GLib.Error e) {
                    warning ("VmController[%s]: QMP connect failed: %s",
                             vm_name, e.message);
                    // Don't fail — QMP is optional for basic operation
                }
            });

            retry_connect_source = 0;
            return false; // stop timeout
        });
    }

    /** Stop the VM: graceful shutdown via ACPI, then SIGTERM, then SIGKILL. */
    public void stop () {
        if (state == VmState.STOPPED || state == VmState.STOPPING) {
            return;
        }

        set_vmc_state (VmState.STOPPING);

        // Try graceful shutdown via ACPI powerdown if QMP is available
        if (qmp_client != null && qmp_client.state == QmpClient.State.READY) {
            message ("VmController[%s]: sending system_powerdown", vm_name);
            qmp_client.send_command_sync ("system_powerdown", null);
        } else {
            // No QMP — fall back to SIGTERM immediately
            if (process_manager != null) {
                process_manager.stop ();
            }
            return;
        }

        // Give the guest 10 seconds to shut down gracefully via ACPI,
        // then escalate to SIGTERM if still running.
        GLib.Timeout.add_seconds (10, () => {
            if (process_manager != null && process_manager.running) {
                message ("VmController[%s]: graceful shutdown timeout — sending SIGTERM", vm_name);
                process_manager.stop ();
            } else if (process_manager == null) {
                debug ("VmController[%s]: process already cleaned up — shutdown complete", vm_name);
            }
            return false;
        });
    }

    /** Force-kill the VM immediately. */
    public void force_stop () {
        if (process_manager != null) {
            process_manager.force_kill ();
        }
    }

    /** Pause the VM via QMP. */
    public void pause () {
        if (state != VmState.RUNNING) {
            return;
        }

        if (qmp_client != null && qmp_client.state == QmpClient.State.READY) {
            qmp_client.send_command_sync ("stop", null);
            set_vmc_state (VmState.PAUSED);
        }
    }

    /** Resume the VM via QMP. */
    public void resume () {
        if (state != VmState.PAUSED) {
            return;
        }

        if (qmp_client != null && qmp_client.state == QmpClient.State.READY) {
            qmp_client.send_command_sync ("cont", null);
            set_vmc_state (VmState.RUNNING);
        }
    }

    // ---- Signal handlers ----

    private void on_process_exited (int exit_code) {
        var was_stopping = state == VmState.STOPPING;

        // Cleanup
        if (qmp_client != null) {
            qmp_client.disconnect ();
        }
        process_manager.cleanup_socket ();

        set_vmc_state (VmState.STOPPED);

        if (exit_code != 0 && !was_stopping) {
            error_occurred (@"QEMU exited unexpectedly with code $(exit_code)");
        }

        debug ("VmController[%s]: process exited", vm_name);
    }

    private void on_launch_failed (string reason) {
        set_vmc_state (VmState.ERROR);
        error_occurred (@"Failed to launch QEMU: $(reason)");
    }

    private void on_qmp_event (string event_name, Json.Object? data) {
        qmp_event (event_name, data);

        // Handle lifecycle events
        switch (event_name) {
            case "SHUTDOWN":
                // VM is shutting down — QEMU will exit shortly
                debug ("VmController[%s]: SHUTDOWN event", vm_name);
                break;

            case "STOP":
                set_vmc_state (VmState.PAUSED);
                break;

            case "RESUME":
                set_vmc_state (VmState.RUNNING);
                break;

            case "RESET":
                debug ("VmController[%s]: RESET event", vm_name);
                break;
        }
    }

    private void on_qmp_state_changed (QmpClient.State qmp_state) {
        if (qmp_state == QmpClient.State.READY && state == VmState.STARTING) {
            set_vmc_state (VmState.RUNNING);
            message ("VmController[%s]: running (PID %d)", vm_name, pid);
        } else if (qmp_state == QmpClient.State.ERROR) {
            if (state == VmState.RUNNING || state == VmState.STARTING) {
                warning ("VmController[%s]: QMP connection lost", vm_name);
                // Don't change state — VM is still running without QMP
            }
        }
    }

    // ---- Helpers ----

    private void set_vmc_state (VmState new_state) {
        if (state != new_state) {
            var old = state;
            state = new_state;
            state_changed (old, new_state);
        }
    }

    /** Clean up all resources. */
    public void dispose_resources () {
        if (retry_connect_source != 0) {
            GLib.Source.remove (retry_connect_source);
            retry_connect_source = 0;
        }

        // Disconnect signals before nulling references to avoid
        // callbacks dereferencing stale pointers.
        if (process_manager != null) {
            process_manager.exited.disconnect (on_process_exited);
            process_manager.launch_failed.disconnect (on_launch_failed);

            if (process_manager.running) {
                process_manager.force_kill ();
            }
            process_manager.cleanup_socket ();
            process_manager = null;
        }

        if (qmp_client != null) {
            qmp_client.event_received.disconnect (on_qmp_event);
            qmp_client.state_changed.disconnect (on_qmp_state_changed);
            qmp_client.disconnect ();
            qmp_client = null;
        }
    }
}
