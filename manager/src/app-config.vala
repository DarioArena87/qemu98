/*
 * app-config.vala — Application-level configuration
 *
 * Persisted in ~/.config/qemu98/manager.json. Holds two settings that the
 * user can change from the Preferences dialog:
 *
 *   - qemu_binary_path: optional absolute path to qemu-system-i386;
 *     when null, the manager falls back to PATH lookup at runtime.
 *   - base_dir: optional base directory for VM data (per-VM subdirs
 *     hold the VM JSON config and (default) disk image); when null,
 *     defaults to $HOME/qemu98.
 *
 * Provides:
 *   - load() / save()
 *   - get_effective_qemu_binary() — resolves user path or PATH lookup
 *   - get_effective_base_dir()    — resolved base dir (never null)
 *   - get_vm_dir(name)            — <base>/<vm_name>
 *   - get_default_disk_path(name) — <base>/<vm_name>/<kebab-name>.qcow2
 *   - static kebab_case(), expand_path()
 */    public class AppConfig : GLib.Object {

    // ---- Backing storage ----

    private Json.Object root;
    private const string SCHEMA_VERSION = "1";

    // Read PATH from the environment. Uses GLib's own binding rather
    // than an extern C declaration, which would trigger a double-free
    // because Vala assumes ownership of every string returned from an
    // extern function — but getenv() returns a static libc buffer.
    private static string? get_path_env() {
        return GLib.Environment.get_variable("PATH");
    }

    // ---- Public properties ----

    /**
     * User-configured absolute path to qemu-system-i386.
     * Empty string and missing-key both mean "use PATH lookup".
     */
    public string qemu_binary_path {
        get {
            if (!root.has_member("qemu_binary_path")) return "";
            return root.get_string_member("qemu_binary_path") ?? "";
        }
        set {
            if (value == null || value.strip() == "") {
                if (root.has_member("qemu_binary_path"))
                    root.remove_member("qemu_binary_path");
            } else {
                root.set_string_member("qemu_binary_path", value);
            }
        }
    }

    /**
     * User-configured base directory for VM data.
     * Empty string and missing-key both mean "use default (~/qemu98)".
     */
    public string base_dir {
        get {
            if (!root.has_member("base_dir")) return "";
            return root.get_string_member("base_dir") ?? "";
        }
        set {
            if (value == null || value.strip() == "") {
                if (root.has_member("base_dir"))
                    root.remove_member("base_dir");
            } else {
                root.set_string_member("base_dir", value);
            }
        }
    }

    /** True when qemu_binary_path is explicitly set and non-empty. */
    public bool has_qemu_binary_path {
        get { return qemu_binary_path.strip() != ""; }
    }

    /** True when base_dir is explicitly set and non-empty. */
    public bool has_base_dir {
        get { return base_dir.strip() != ""; }
    }

    // ---- Signals ----

    /** Emitted whenever the config is saved with mutated values. */
    public signal void changed();

    // ---- Construction ----

    public AppConfig() {
        this.root = new Json.Object();
    }

    /**
     * Load the app config from disk, returning a default instance
     * if the file does not exist or is malformed.
     */
    public static AppConfig load() {
        var cfg = new AppConfig();
        var path = get_config_file_path();

        var file = GLib.File.new_for_path(path);
        if (!file.query_exists()) {
            debug("AppConfig: no config file at %s — using defaults", path);
            return cfg;
        }

        try {
            uint8[] contents;
            string etag_out;
            file.load_contents(null, out contents, out etag_out);

            var parser = new Json.Parser();
            parser.load_from_data((string) contents);

            var node = parser.get_root();
            if (node == null || node.get_node_type() != Json.NodeType.OBJECT) {
                warning("AppConfig: %s is not a JSON object — using defaults", path);
                return new AppConfig();
            }

            return new AppConfig.from_json(node.get_object());
        }
        catch (GLib.Error e) {
            warning("AppConfig: failed to load %s: %s — using defaults",
                    path, e.message);
            return new AppConfig();
        }
    }

    private AppConfig.from_json(Json.Object obj) {
        this.root = new Json.Object();
        if (obj.has_member("qemu_binary_path")) {
            var v = obj.get_string_member("qemu_binary_path");
            if (v != null && v.strip() != "") {
                this.root.set_string_member("qemu_binary_path", v);
            }
        }
        if (obj.has_member("base_dir")) {
            var v = obj.get_string_member("base_dir");
            if (v != null && v.strip() != "") {
                this.root.set_string_member("base_dir", v);
            }
        }
    }

    // ---- Persistence ----

    /**
     * Save the config to disk. Creates the parent directory if needed.
     */
    public bool save() {
        var path = get_config_file_path();
        var parent = GLib.File.new_for_path(
            GLib.Path.get_dirname(path));
        try {
            if (!parent.query_exists())
                parent.make_directory_with_parents();
        }
        catch (GLib.Error e) {
            critical("AppConfig: cannot create parent dir %s: %s",
                     parent.get_path(), e.message);
            return false;
        }

        var generator = new Json.Generator();
        var node = new Json.Node.alloc().init_object(this.root);
        generator.root = node;
        generator.pretty = true;
        var json_str = generator.to_data(null);
        if (json_str == null) {
            warning("AppConfig: failed to serialize config");
            return false;
        }

        try {
            GLib.FileUtils.set_contents(path, json_str);
            message("AppConfig: saved to %s", path);
            changed();
            return true;
        }
        catch (GLib.FileError e) {
            critical("AppConfig: failed to write %s: %s", path, e.message);
            return false;
        }
    }

    // ---- Resolution helpers ----

    /**
     * Resolve the qemu binary to use. Returns null if the configured
     * path is invalid AND the binary cannot be found on PATH.
     *
     * Order of resolution:
     *   1. If qemu_binary_path is set, validate it (exists + executable).
     *   2. Else, look up "qemu-system-i386" on PATH.
     *   3. Else, return null.
     */
    public string? get_effective_qemu_binary() {
        if (has_qemu_binary_path) {
            var expanded = AppConfig.expand_path(qemu_binary_path);
            if (path_is_executable(expanded)) {
                return expanded;
            }
            // Configured path invalid — also try PATH as a fallback.
        }

        var on_path = AppConfig.find_program_in_path("qemu-system-i386");
        return on_path;  // may still be null
    }

    /**
     * True when the effective qemu binary is resolvable.
     */
    public bool qemu_binary_available {
        get { return get_effective_qemu_binary() != null; }
    }

    /** Reason why qemu is unavailable, suitable for an error message. */
    public string qemu_binary_diagnostic {
        owned get {
            if (has_qemu_binary_path) {
                var expanded = AppConfig.expand_path(qemu_binary_path);
                if (expanded == "" || !GLib.FileUtils.test(expanded, GLib.FileTest.EXISTS))
                    return @"'$(qemu_binary_path)' does not exist";
                if (!path_is_executable(expanded))
                    return @"'$(expanded)' is not an executable file";
            }
            return "'qemu-system-i386' was not found on the system PATH";
        }
    }

    /**
     * Return the effective base directory (always non-empty).
     * Default is $HOME/qemu98.
     */
    public string get_effective_base_dir() {
        if (has_base_dir) {
            return AppConfig.expand_path(base_dir);
        }
        return AppConfig.default_base_dir();
    }

    /** Return the per-VM directory: <base>/<vm_name>. */
    public string get_vm_dir(string vm_name) {
        return GLib.Path.build_filename(
            get_effective_base_dir(), vm_name);
    }

    /** Return the default disk image path: <base>/<vm>/<kebab>.qcow2. */
    public string get_default_disk_path(string vm_name) {
        var kebab = AppConfig.kebab_case(vm_name);
        if (kebab == "") kebab = "disk";
        return GLib.Path.build_filename(
            get_vm_dir(vm_name), @"$(kebab).qcow2");
    }

    // ---- Static helpers ----

    /** Path of the on-disk config file. */
    public static string get_config_file_path() {
        return GLib.Path.build_filename(
            GLib.Environment.get_user_config_dir(),
            "qemu98", "manager.json");
    }

    /** Default base dir: $HOME/qemu98. */
    public static string default_base_dir() {
        return GLib.Path.build_filename(
            GLib.Environment.get_home_dir(), "qemu98");
    }

    /**
     * Convert a VM name into a kebab-case filename slug.
     * Rules: lowercase, non-alphanumeric codepoints collapse runs to
     * a single '-', trim leading/trailing '-'. Empty result on empty
     * input. ASCII-friendly byte iteration: ASCII letters/digits are
     * kept (lowercased), anything else is treated as a separator. For
     * the purposes of VM filenames this is exactly the right contract.
     */
    public static string kebab_case(string name) {
        if (name == null) return "";
        var sb = new GLib.StringBuilder();
        bool pending_sep = true;  // start true so leading runs are dropped
        int len = name.length;
        for (int i = 0; i < len; i++) {
            unichar cp = name.get_char(i);
            char low;
            if (cp >= 'A' && cp <= 'Z') {
                low = (char) (cp + 32);
            } else {
                low = (char) cp;
            }
            bool is_alnum = ((low >= 'a' && low <= 'z')
                             || (low >= '0' && low <= '9'));
            if (is_alnum) {
                sb.append_c(low);
                pending_sep = false;
            }
            else if (!pending_sep) {
                sb.append_c('-');
                pending_sep = true;
            }
        }
        var s = sb.str;
        if (s.has_suffix("-")) {
            s = s.substring(0, s.length - 1);
        }
        return s;
    }

    /**
     * Expand a leading ~/ to $HOME. Other forms pass through unchanged.
     */
    public static string expand_path(string path) {
        if (path == null || path == "") return "";
        if (path == "~")
            return GLib.Environment.get_home_dir();
        if (path.has_prefix("~/")) {
            return GLib.Path.build_filename(
                GLib.Environment.get_home_dir(),
                path.substring(2));
        }
        return path;
    }

    /**
     * Find an executable on PATH. Returns null if not found.
     *
     * Implemented locally rather than relying on GLib.find_program_in_path
     * because that binding is not consistently available across Vala
     * versions and is no easier than parsing PATH ourselves.
     */
    public static string ? find_program_in_path(string program) {
        if (program == null || program == "") return null;
        // Absolute paths are checked directly without consulting PATH.
        if (program.has_prefix("/")) {
            return path_is_executable(program) ? program : null;
        }
        var path = get_path_env() ?? "";
        foreach (var dir in path.split(":")) {
            if (dir == "") continue;
            var candidate = GLib.Path.build_filename(dir, program);
            if (path_is_executable(candidate)) return candidate;
        }
        return null;
    }

    /**
     * True if path looks like a launchable executable for this user.
     * We probe the file's mode bits via FileInfo so non-executable
     * files are rejected (GLib.FileTest has no EXEC bit). If the
     * probe fails for any reason (e.g. a permissions oddity), we
     * fall back to "regular file exists" — the spawner will surface
     * a clearer error to the user.
     */
    private static bool path_is_executable(string path) {
        if (path == "") return false;
        var f = GLib.File.new_for_path(path);
        try {
            var info = f.query_info(
                GLib.FileAttribute.STANDARD_NAME + ","
                + GLib.FileAttribute.STANDARD_TYPE + ","
                + GLib.FileAttribute.UNIX_MODE,
                GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
            if (info.get_file_type() != GLib.FileType.REGULAR
                && info.get_file_type() != GLib.FileType.SYMBOLIC_LINK)
                return false;
            var mode = info.get_attribute_uint32(GLib.FileAttribute.UNIX_MODE);
            if (mode == 0) return true;  // non-UNIX fs, accept regular file
            // Any executable bit set (owner / group / other) is enough
            // for the user to be able to launch it from the GUI.
            const uint32 EXEC_BITS = 0x49; // 0111 << 0 = owner+group+other
            return (mode & EXEC_BITS) != 0;
        }
        catch (GLib.Error e) {
            // Fallback: existence + not-a-directory check.
            return GLib.FileUtils.test(path, GLib.FileTest.EXISTS)
                && !GLib.FileUtils.test(path, GLib.FileTest.IS_DIR);
        }
    }
}
