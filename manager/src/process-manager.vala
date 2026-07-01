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
        this.qmp_socket_path = build_qmp_socket_path();
    }

    /** Build the QMP Unix socket path from the VM UUID. */
    private string build_qmp_socket_path() {
        var uuid = config.get_string_member ("uuid");
        var runtime_dir = GLib.Environment.get_user_cache_dir ();
        var dir = GLib.Path.build_filename (runtime_dir, "qemu98");
        GLib.DirUtils.create_with_parents (dir, 0700);
        return GLib.Path.build_filename (dir, @"qmp-$(uuid).sock");
    }

    // ---- CLI builder ----

    /** Build the full QEMU command-line argument array. */
    private string[] build_arguments() {
        var args = new GLib.GenericArray<string>();

        args.add(qemu_binary);
        append_machine_args(ref args);
        append_display_args(ref args);
        append_audio_args(ref args);
        append_device_args(ref args);
        append_storage_args(ref args);
        append_network_args(ref args);
        append_control_args(ref args);

        return args.steal();
    }

    /** Append -machine, -cpu, -m, -uuid, -name, optional -bios, and -boot. */
    private void append_machine_args (ref GLib.GenericArray<string> args) {
        var machine = config.get_object_member("machine");
        var accel = machine.get_string_member("accelerator");
        args.add ("-machine");
        args.add (@"$(machine.get_string_member("type")),accel=$(accel)");

        args.add ("-cpu");
        args.add (machine.get_string_member("cpu"));

        args.add ("-m");
        args.add (machine.get_int_member("ram_mb").to_string());

        if (config.has_member ("uuid")) {
            args.add ("-uuid");
            args.add (config.get_string_member("uuid"));
        }
        args.add ("-name");
        args.add (config.get_string_member("name"));

        if (machine.has_member ("bios")) {
            var bios = machine.get_string_member("bios");
            if (bios != null && bios != "") {
                args.add ("-bios");
                args.add (bios);
            }
        }

        // Build -boot order=... from device boot_order values
        var boot_str = build_boot_order();
        if (boot_str != "") {
            args.add ("-boot");
            args.add (@"order=$(boot_str)");
        }
    }

    /** Append -display (and -vnc if applicable). */
    private void append_display_args (ref GLib.GenericArray<string> args) {
        if (!config.has_member ("display")) return;

        var display = config.get_object_member("display");
        var display_type = display.get_string_member("type");
        var display_str = display_type;
        if (display.has_member ("scale_filter")) {
            display_str += @",filter=$(display.get_string_member ("scale_filter"))";
        }
        display_str += ",gl=on";
        args.add ("-display");
        args.add (display_str);

        if (display_type == "vnc") {
            args.add ("-vnc");
            args.add ("127.0.0.1:0");
        }
    }

    /** Append -audiodev when sb16 is enabled. */
    private void append_audio_args (ref GLib.GenericArray<string> args) {
        if (!config.has_member("audio")) return;

        var audio = config.get_object_member("audio");
        if (audio.get_boolean_member("sb16")) {
            var backend = audio.get_string_member("backend");
            args.add ("-audiodev");
            args.add (@"$(backend),id=audio0");
        }
    }

    /** Append -device / -vga for each entry in the devices array. */
    private void append_device_args (ref GLib.GenericArray<string> args) {
        if (!config.has_member("devices")) return;

        var devices = config.get_array_member("devices");
        for (var i = 0; i < devices.get_length(); i++) {
            var dev = devices.get_object_element(i);
            switch (dev.get_string_member("type")) {
                case "VGA":
                    args.add("-vga");
                    args.add("std");
                    break;

                case "voodoo3":
                    args.add("-device");
                    var vram = dev.has_member("vram_mb") ? dev.get_int_member("vram_mb").to_string() : "64";
                    args.add(@"voodoo3,vram=$(vram)");
                    break;

                case "hypback":
                    args.add("-device");
                    var hid = dev.has_member("id") ? dev.get_string_member("id") : "hbe0";
                    args.add(@"hypback,id=$(hid)");
                    break;

                case "sb16":
                    args.add("-device");
                    var sb_str = "sb16";
                    if (dev.has_member("irq"))
                        sb_str += @",irq=$(dev.get_int_member("irq"))";
                    if (dev.has_member("dma"))
                        sb_str += @",dma=$(dev.get_int_member("dma"))";
                    if (dev.has_member("dma16"))
                        sb_str += @",dma16=$(dev.get_int_member("dma16"))";
                    sb_str += ",audiodev=audio0";
                    args.add(sb_str);
                    break;

                case "ne2k_pci":
                    args.add("-device");
                    var netdev_id = dev.has_member ("netdev") ? dev.get_string_member("netdev") : "net0";
                    args.add(@"ne2k_pci,netdev=$(netdev_id)");
                    break;

                case "e1000":
                    args.add("-device");
                    var netdev_id2 = dev.has_member ("netdev") ? dev.get_string_member("netdev") : "net0";
                    args.add(@"e1000,netdev=$(netdev_id2)");
                    break;

                default:
                    warning("Unknown device type: %s", dev.get_string_member("type"));
                    break;
            }
        }
    }

    /**
     * Collect all storage devices with boot_order > 0, sort by
     * boot_order, and return a QEMU boot-order string (e.g. "cda").
     *
     * Mapping: hd → c, cdrom → d, floppy → a.
     * Returns empty string when no devices have a boot_order.
     */
    private string build_boot_order() {
        if (!config.has_member("storage")) return "";

        // Pair of (boot_order, qemu_letter)
        var entries = new GLib.GenericArray<BootEntry>();

        var storage = config.get_object_member("storage");

        // Controller devices
        if (storage.has_member("controllers")) {
            var controllers = storage.get_array_member("controllers");
            for (var i = 0; i < controllers.get_length(); i++) {
                var ctrl = controllers.get_object_element(i);
                if (!ctrl.has_member("devices")) continue;
                var devs = ctrl.get_array_member("devices");
                for (var j = 0; j < devs.get_length(); j++) {
                    var dev = devs.get_object_element(j);
                    if (!dev.has_member("boot_order")) continue;
                    var order = (int) dev.get_int_member("boot_order");
                    if (order <= 0) continue;
                    var dev_type = dev.has_member("type")
                        ? dev.get_string_member("type") : "hd";
                    var letter = dev_type_to_boot_letter(dev_type);
                    if (letter == '\0') continue;
                    entries.add(new BootEntry() { order = order, letter = letter });
                }
            }
        }

        // Floppy drives
        if (storage.has_member("floppy")) {
            var floppies = storage.get_array_member("floppy");
            for (var i = 0; i < floppies.get_length(); i++) {
                var flop = floppies.get_object_element(i);
                if (!flop.has_member("boot_order")) continue;
                var order = (int) flop.get_int_member("boot_order");
                if (order <= 0) continue;
                entries.add(new BootEntry() { order = order, letter = 'a' });
            }
        }

        if (entries.length == 0) return "";

        // Sort by boot_order ascending
        // Simple bubble sort since the list is tiny (≤4 entries).
        // Use get()/set() with explicit owned types so ref counts are
        // properly bumped during the swap.
        for (int i = 0; i < (int) entries.length - 1; i++) {
            for (int j = 0; j < (int) entries.length - 1 - i; j++) {
                if (entries.get(j).order > entries.get(j + 1).order) {
                    BootEntry a = entries.get(j);
                    BootEntry b = entries.get(j + 1);
                    entries.set(j, b);
                    entries.set(j + 1, a);
                }
            }
        }

        var sb = new GLib.StringBuilder();
        for (var i = 0; i < entries.length; i++) {
            sb.append_c(entries.get(i).letter);
        }
        return sb.str;
    }

    /** Map a storage device type string to a QEMU -boot letter. */
    private static char dev_type_to_boot_letter(string type) {
        switch (type) {
            case "hd":    return 'c';
            case "cdrom": return 'd';
            default:      return '\0';
        }
    }

    /** Lightweight class for a (boot_order, letter) pair. */
    private class BootEntry {
        public int order;
        public char letter;
    }

    /** Append -drive args for disk controllers and floppy drives. */
    private void append_storage_args (ref GLib.GenericArray<string> args) {
        if (!config.has_member("storage")) return;

        var storage = config.get_object_member("storage");

        // Disk controllers
        if (storage.has_member ("controllers")) {
            var controllers = storage.get_array_member("controllers");
            for (var i = 0; i < controllers.get_length(); i++) {
                var controller = controllers.get_object_element(i);
                var ctrl_type = controller.get_string_member("type");
                if (!controller.has_member ("devices")) continue;

                var ctrl_devices = controller.get_array_member("devices");
                for (var j = 0; j < ctrl_devices.get_length (); j++) {
                    var disk = ctrl_devices.get_object_element(j);
                    append_drive_arg (ref args, disk, ctrl_type);
                }
            }
        }

        // Floppy drives
        if (storage.has_member ("floppy")) {
            var floppyDrives = storage.get_array_member ("floppy");
            for (var i = 0; i < floppyDrives.get_length() && i < 2; i++) {
                var floppyDrive = floppyDrives.get_object_element(i);
                if (floppyDrive.has_member ("file")) {
                    var flop_id = floppyDrive.has_member ("id") ? floppyDrive.get_string_member("id") : @"fda$(i)";
                    args.add ("-drive");
                    args.add (@"file=$(floppyDrive.get_string_member("file")),format=raw,if=floppy,id=$(flop_id)");
                }
            }
        }
    }

    /** Append a single -drive argument for a disk device. */
    private void append_drive_arg(ref GLib.GenericArray<string> args, Json.Object disk, string ctrl_type) {
        var disk_file = disk.has_member("file") ? disk.get_string_member("file") : "";
        var disk_format = disk.has_member ("format") ? disk.get_string_member("format") : "raw";

        args.add("-drive");
        var drive_str = @"file=$(disk_file),format=$(disk_format)";

        if (ctrl_type == "ide") {
            var disk_id = disk.has_member("id") ? disk.get_string_member("id") : "drive0";
            drive_str += @",if=ide,id=$(disk_id)";
        } else if (ctrl_type == "scsi") {
            drive_str += ",if=scsi";
        } else {
            drive_str += @",if=$(ctrl_type)";
        }

        if (disk.has_member("type") && disk.get_string_member("type") == "cdrom") {
            drive_str += ",media=cdrom,readonly=on";
        }

        args.add (drive_str);
    }

    /** Append -netdev for networking. */
    private void append_network_args (ref GLib.GenericArray<string> args) {
        if (!config.has_member("networking")) return;

        var net = config.get_object_member("networking");
        var net_type = net.get_string_member("type");
        if (net_type == "none") return;

        args.add ("-netdev");
        var netdev_str = @"$(net_type),id=net0";

        if (net.has_member("hostfwd")) {
            var fwds = net.get_array_member("hostfwd");
            for (var i = 0; i < fwds.get_length(); i++) {
                var fwd = fwds.get_object_element(i);
                netdev_str += @",hostfwd=$(fwd.get_string_member ("proto"))::";
                netdev_str += @"$(fwd.get_int_member ("host_port"))-:";
                netdev_str += fwd.get_int_member ("guest_port").to_string();
            }
        }
        args.add (netdev_str);
    }

    /** Append QMP socket, monitor, and PID file control args. */
    private void append_control_args(ref GLib.GenericArray<string> args) {
        args.add ("-qmp");
        args.add (@"unix:$(qmp_socket_path),server=on,wait=off");

        args.add ("-monitor");
        args.add ("none");

        pidfile_path = GLib.Path.build_filename(GLib.Environment.get_user_cache_dir(), "qemu98", @"pid-$(config.get_string_member ("uuid")).pid");
        args.add ("-pidfile");
        args.add (pidfile_path);
    }

    // ---- Process lifecycle ----

    /** Spawn the QEMU process and begin monitoring. */
    public bool start() throws GLib.Error {
        if (running) {
            warning ("ProcessManager: already running");
            return false;
        }

        var argv = build_arguments();

        // Build the log line before we append the null sentinel
        var command_line = string.joinv(" ", argv);
        message("Launching QEMU: %s", command_line);

        // GPtrArray.steal() does not guarantee a null-terminated array,
        // but g_subprocess_newv() requires one. Append the sentinel.
        argv += null;

        process = new GLib.Subprocess.newv(argv, GLib.SubprocessFlags.NONE);
        if (process == null) {
            throw new GLib.IOError.FAILED("Failed to spawn QEMU process");
        }

        pid = int.parse(process.get_identifier() ?? "0");
        running = true;

        // Monitor child exit
        process.wait_async.begin(null, on_process_exited);

        message("QEMU started (PID %d), QMP socket: %s", pid, qmp_socket_path);
        debug("QEMU command: %s", command_line);

        return true;
    }

    /** Callback when the QEMU process exits. */
    private void on_process_exited(GLib.Object? source, GLib.AsyncResult result) {
        try {
            process.wait_async.end(result); // returns bool (wait succeeded)
            running = false;
            var exit_code = process.get_exit_status ();

            message("QEMU process exited with status %d", exit_code);
            exited(exit_code);
        } catch (GLib.Error e) {
            running = false;
            warning ("QEMU process wait failed: %s", e.message);
            exited (-1);
        }
    }

    /** Graceful shutdown: send SIGTERM, wait, then SIGKILL if needed. */
    public void stop() {
        if (!running || process == null) {
            return;
        }

        message("Sending SIGTERM to QEMU (PID %d)...", pid);
        process.send_signal(15); // SIGTERM

        // Start a timeout for forced kill
        GLib.Timeout.add_seconds(10, () => {
            if (running) {
                warning ("QEMU did not exit after SIGTERM, sending SIGKILL");
                process.send_signal(9); // SIGKILL
            }
            return false; // stop the timeout
        });
    }

    /** Force-kill the QEMU process immediately. */
    public void force_kill() {
        if (!running || process == null) {
            return;
        }

        warning("Force-killing QEMU (PID %d)", pid);
        process.send_signal(9); // SIGKILL
    }

    /** Clean up the QMP socket file. */
    public void cleanup_socket() {
        var file = GLib.File.new_for_path (qmp_socket_path);
        if (file.query_exists()) {
            try {
                file.delete ();
            }
            catch (GLib.Error e) {
                debug ("Failed to remove QMP socket: %s", e.message);
            }
        }
    }
}