/*
 * process-manager.vala — QEMU process lifecycle
 *
 * Translates VM configuration (Json.Object) into QEMU CLI arguments,
 * spawns qemu-system-i386 via GLib.Subprocess, and monitors the child
 * process via SIGCHLD. Handles graceful and forced shutdown.
 *
 * Phase 2: spawn, monitor, shutdown. Snapshot/media management deferred.
 */

public class ProcessManager : GLib.Object {

    // ---- Properties ----

    /** The spawned QEMU process, or null when not running. */
    public GLib.Subprocess? process { get; private set; default = null; }

    /** PID of the spawned process, or 0 when not running. */
    public int pid { get; private set; default = 0; }

    /** Whether the process is currently running. */
    public bool running { get; private set; default = false; }

    /** Path to the QMP control socket. */
    public string qmp_socket_path { get; private set; }

    // ---- Signals ----

    /** Emitted when the QEMU process exits (normal or crash). */
    public signal void exited (int exit_code);

    /** Emitted when the process encounters a launch failure. */
    public signal void launch_failed (string reason);

    // ---- Internal ----

    private Json.Object config;
    private string qemu_binary;
    private string? pidfile_path = null;

    // ---- Construction ----

    /**
     * @param qemu_binary  Full path to qemu-system-i386
     * @param config       VM configuration (see VM_MANAGER.md §4.1)
     */
    public ProcessManager (string qemu_binary, Json.Object config) {
        this.qemu_binary = qemu_binary;
        this.config = config;
        this.qmp_socket_path = build_qmp_socket_path ();
    }

    /** Build the QMP Unix socket path from the VM UUID. */
    private string build_qmp_socket_path () {
        var uuid = config.get_string_member ("uuid");
        var runtime_dir = GLib.Environment.get_user_cache_dir ();
        var dir = GLib.Path.build_filename (runtime_dir, "qemu98");
        GLib.DirUtils.create_with_parents (dir, 0700);
        return GLib.Path.build_filename (dir, @"qmp-$(uuid).sock");
    }

    // ---- CLI builder ----

    /** Build the full QEMU command-line argument array. */
    private string[] build_arguments () {
        var args = new GLib.GenericArray<string> ();

        args.add (qemu_binary);

        // Machine
        var machine = config.get_object_member ("machine");
        var accel = machine.get_string_member ("accelerator");
        args.add ("-machine");
        args.add (@"$(machine.get_string_member ("type")),accel=$(accel)");

        args.add ("-cpu");
        args.add (machine.get_string_member ("cpu"));

        args.add ("-m");
        args.add (machine.get_int_member ("ram_mb").to_string ());

        // UUID and name
        if (config.has_member ("uuid")) {
            args.add ("-uuid");
            args.add (config.get_string_member ("uuid"));
        }
        args.add ("-name");
        args.add (config.get_string_member ("name"));

        // Display
        if (config.has_member ("display")) {
            var display = config.get_object_member ("display");
            var display_type = display.get_string_member ("type");
            var display_str = display_type;
            if (display.has_member ("scale_filter")) {
                display_str += @",filter=$(display.get_string_member ("scale_filter"))";
            }
            args.add ("-display");
            args.add (display_str);

            if (display_type == "vnc") {
                args.add ("-vnc");
                args.add ("127.0.0.1:0");
            }
        }

        // Audio
        if (config.has_member ("audio")) {
            var audio = config.get_object_member ("audio");
            if (audio.get_boolean_member ("sb16")) {
                var backend = audio.get_string_member ("backend");
                args.add ("-audiodev");
                args.add (@"$(backend),id=audio0");
            }
        }

        // Devices (VGA, voodoo3, hypback, sb16, network)
        if (config.has_member ("devices")) {
            var devices = config.get_array_member ("devices");
            for (var i = 0; i < devices.get_length (); i++) {
                var dev = devices.get_object_element (i);
                var dev_type = dev.get_string_member ("type");

                switch (dev_type) {
                    case "VGA":
                        args.add ("-vga");
                        args.add ("std");
                        break;

                    case "voodoo3":
                        args.add ("-device");
                        var vram = dev.has_member ("vram_mb") ?
                            dev.get_int_member ("vram_mb").to_string () : "64";
                        args.add (@"voodoo3,vram=$(vram)");
                        break;

                    case "hypback":
                        args.add ("-device");
                        var hid = dev.has_member ("id") ?
                            dev.get_string_member ("id") : "hbe0";
                        args.add (@"hypback,id=$(hid)");
                        break;

                    case "sb16":
                        args.add ("-device");
                        var sb_str = "sb16";
                        if (dev.has_member ("irq"))
                            sb_str += @",irq=$(dev.get_int_member ("irq"))";
                        if (dev.has_member ("dma"))
                            sb_str += @",dma=$(dev.get_int_member ("dma"))";
                        if (dev.has_member ("dma16"))
                            sb_str += @",dma16=$(dev.get_int_member ("dma16"))";
                        sb_str += ",audiodev=audio0";
                        args.add (sb_str);
                        break;

                    case "ne2k_pci":
                        var netdev_id = dev.has_member ("netdev") ?
                            dev.get_string_member ("netdev") : "net0";
                        args.add ("-device");
                        args.add (@"ne2k_pci,netdev=$(netdev_id)");
                        break;

                    case "e1000":
                        var netdev_id2 = dev.has_member ("netdev") ?
                            dev.get_string_member ("netdev") : "net0";
                        args.add ("-device");
                        args.add (@"e1000,netdev=$(netdev_id2)");
                        break;

                    default:
                        warning ("Unknown device type: %s", dev_type);
                        break;
                }
            }
        }

        // Storage
        if (config.has_member ("storage")) {
            var storage = config.get_object_member ("storage");
            if (storage.has_member ("controllers")) {
                var controllers = storage.get_array_member ("controllers");
                for (var i = 0; i < controllers.get_length (); i++) {
                    var ctrl = controllers.get_object_element (i);
                    var ctrl_type = ctrl.get_string_member ("type");

                    if (ctrl.has_member ("devices")) {
                        var ctrl_devices = ctrl.get_array_member ("devices");
                        for (var j = 0; j < ctrl_devices.get_length (); j++) {
                            var disk = ctrl_devices.get_object_element (j);
                            var disk_type = disk.get_string_member ("type");
                            var disk_file = disk.has_member ("file") ?
                                disk.get_string_member ("file") : "";
                            var disk_format = disk.has_member ("format") ?
                                disk.get_string_member ("format") : "raw";

                            args.add ("-drive");
                            var drive_str = @"file=$(disk_file),format=$(disk_format)";

                            // IDE/SCSI attachment
                            if (ctrl_type == "ide") {
                                var disk_id = disk.has_member ("id") ?
                                    disk.get_string_member ("id") : "drive0";
                                drive_str += @",if=ide,id=$(disk_id)";
                            } else if (ctrl_type == "scsi") {
                                drive_str += ",if=scsi";
                            } else {
                                drive_str += @",if=$(ctrl_type)";
                            }

                            if (disk_type == "cdrom") {
                                drive_str += ",media=cdrom,readonly=on";
                            }

                            if (disk.has_member ("boot_index")) {
                                drive_str += @",boot-index=$(disk.get_int_member ("boot_index"))";
                            }

                            args.add (drive_str);
                        }
                    }
                }
            }

            // Floppy
            if (storage.has_member ("floppy")) {
                var floppy = storage.get_array_member ("floppy");
                for (var i = 0; i < floppy.get_length () && i < 2; i++) {
                    var flop = floppy.get_object_element (i);
                    if (flop.has_member ("file")) {
                        var flop_file = flop.get_string_member ("file");
                        var flop_id = flop.has_member ("id") ?
                            flop.get_string_member ("id") : @"fda$(i)";
                        args.add ("-drive");
                        args.add (@"file=$(flop_file),format=raw,if=floppy,id=$(flop_id)");
                    }
                }
            }
        }

        // Networking
        if (config.has_member ("networking")) {
            var net = config.get_object_member ("networking");
            var net_type = net.get_string_member ("type");
            if (net_type != "none") {
                args.add ("-netdev");
                var netdev_str = @"$(net_type),id=net0";
                if (net.has_member ("hostfwd")) {
                    var fwds = net.get_array_member ("hostfwd");
                    for (var i = 0; i < fwds.get_length (); i++) {
                        var fwd = fwds.get_object_element (i);
                        netdev_str += @",hostfwd=$(fwd.get_string_member ("proto"))::";
                        netdev_str += @"$(fwd.get_int_member ("host_port"))-:";
                        netdev_str += fwd.get_int_member ("guest_port").to_string ();
                    }
                }
                args.add (netdev_str);
            }
        }

        // QMP control socket
        args.add ("-qmp");
        args.add (@"unix:$(qmp_socket_path),server=on,wait=off");

        // Disable the text monitor (only QMP is needed)
        args.add ("-monitor");
        args.add ("none");

        // PID file
        pidfile_path = GLib.Path.build_filename (
            GLib.Environment.get_user_cache_dir (), "qemu98",
            @"pid-$(config.get_string_member ("uuid")).pid"
        );
        args.add ("-pidfile");
        args.add (pidfile_path);

        // BIOS (optional)
        if (machine.has_member ("bios")) {
            var bios = machine.get_string_member ("bios");
            if (bios != null && bios != "") {
                args.add ("-bios");
                args.add (bios);
            }
        }

        return args.steal ();
    }

    // ---- Process lifecycle ----

    /** Spawn the QEMU process and begin monitoring. */
    public bool start () throws GLib.Error {
        if (running) {
            warning ("ProcessManager: already running");
            return false;
        }

        var argv = build_arguments ();

        message ("Launching QEMU: %s", string.joinv (" ", argv));

        process = new GLib.Subprocess.newv (
            argv,
            GLib.SubprocessFlags.NONE
        );

        pid = int.parse (process.get_identifier () ?? "0");
        running = true;

        // Monitor child exit
        process.wait_async.begin (null, on_process_exited);

        message ("QEMU started (PID %d), QMP socket: %s", pid, qmp_socket_path);
        debug ("QEMU command: %s", string.joinv (" ", argv));

        return true;
    }

    /** Callback when the QEMU process exits. */
    private void on_process_exited (GLib.Object? source, GLib.AsyncResult result) {
        try {
            process.wait_async.end (result); // returns bool (wait succeeded)
            running = false;
            var exit_code = process.get_exit_status ();

            message ("QEMU process exited with status %d", exit_code);
            exited (exit_code);
        } catch (GLib.Error e) {
            running = false;
            warning ("QEMU process wait failed: %s", e.message);
            exited (-1);
        }
    }

    /** Graceful shutdown: send SIGTERM, wait, then SIGKILL if needed. */
    public void stop () {
        if (!running || process == null) {
            return;
        }

        message ("Sending SIGTERM to QEMU (PID %d)...", pid);
        process.send_signal (15); // SIGTERM

        // Start a timeout for forced kill
        GLib.Timeout.add_seconds (10, () => {
            if (running) {
                warning ("QEMU did not exit after SIGTERM, sending SIGKILL");
                process.send_signal (9);  // SIGKILL
            }
            return false; // stop the timeout
        });
    }

    /** Force-kill the QEMU process immediately. */
    public void force_kill () {
        if (!running || process == null) {
            return;
        }

        warning ("Force-killing QEMU (PID %d)", pid);
        process.send_signal (9); // SIGKILL
    }

    /** Clean up the QMP socket file. */
    public void cleanup_socket () {
        var file = GLib.File.new_for_path (qmp_socket_path);
        if (file.query_exists ()) {
            try {
                file.delete ();
            } catch (GLib.Error e) {
                debug ("Failed to remove QMP socket: %s", e.message);
            }
        }
    }
}
