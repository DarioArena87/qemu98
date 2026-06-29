/*
 * config-store.vala — VM configuration persistence
 *
 * Reads/writes VM definitions as JSON files in ~/.local/share/qemu98/machines/.
 * Each file is a self-contained VM definition.
 *
 * Schema versioned for forward compatibility (schema_version: 1).
 */

public class ConfigStore : GLib.Object {

    private string machines_dir;
    private GLib.HashTable<string, Json.Object> cache;

    private const string SCHEMA_VERSION = "1";

    // ---- Signals ----

    /** Emitted when a VM configuration is added or updated. */
    public signal void config_changed (string vm_name);

    // ---- Construction ----

    public ConfigStore () {
        machines_dir = GLib.Path.build_filename (
            GLib.Environment.get_user_data_dir (),
            "qemu98",
            "machines"
        );
        cache = new GLib.HashTable<string, Json.Object> (
            GLib.str_hash, GLib.str_equal
        );

        ensure_directory ();
        reload ();
    }

    /** Create the machines directory if it doesn't exist. */
    private void ensure_directory () {
        var dir = GLib.File.new_for_path (machines_dir);
        if (!dir.query_exists ()) {
            try {
                dir.make_directory_with_parents ();
                message ("Created config directory: %s", machines_dir);
            } catch (GLib.Error e) {
                critical ("Failed to create config directory: %s", e.message);
            }
        }
    }

    /** Reload all VM configurations from disk. */
    public void reload () {
        cache.remove_all ();

        var dir = GLib.File.new_for_path (machines_dir);
        try {
            var enumerator = dir.enumerate_children (
                "standard::*",
                GLib.FileQueryInfoFlags.NONE
            );

            GLib.FileInfo info;
            while ((info = enumerator.next_file ()) != null) {
                if (info.get_file_type () == GLib.FileType.REGULAR &&
                    info.get_name ().has_suffix (".json")) {
                    var name = info.get_name ().substring (
                        0, info.get_name ().length - 5); // strip .json
                    load_config (name);
                }
            }
        } catch (GLib.Error e) {
            warning ("Failed to enumerate config directory: %s", e.message);
        }
    }

    /** Load a single VM configuration. Returns null on failure. */
    private Json.Object? load_config (string vm_name) {
        var path = get_config_path (vm_name);
        var file = GLib.File.new_for_path (path);

        if (!file.query_exists ()) {
            return null;
        }

        try {
            uint8[] contents;
            string etag_out;
            file.load_contents (null, out contents, out etag_out);

            var parser = new Json.Parser ();
            parser.load_from_data ((string) contents);

            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                warning ("Invalid JSON in config file: %s", path);
                return null;
            }

            var obj = root.get_object ();
            cache[vm_name] = obj;
            return obj;
        } catch (GLib.Error e) {
            warning ("Failed to load config '%s': %s", vm_name, e.message);
            return null;
        }
    }

    /** Save a VM configuration to disk. */
    public bool save_config (string vm_name, Json.Object config) {
        // Ensure schema version
        if (!config.has_member ("schema_version")) {
            config.set_string_member ("schema_version", SCHEMA_VERSION);
        }

        var path = get_config_path (vm_name);
        var generator = new Json.Generator ();
        generator.root = new Json.Node.alloc ().init_object (config);
        generator.pretty = true;

        var json_str = generator.to_data (null);
        if (json_str == null) {
            warning ("Failed to serialize config for '%s'", vm_name);
            return false;
        }

        try {
            GLib.FileUtils.set_contents (path, json_str);
            cache[vm_name] = config;
            config_changed (vm_name);
            message ("Saved config: %s", path);
            return true;
        } catch (GLib.FileError e) {
            warning ("Failed to write config '%s': %s", path, e.message);
            return false;
        }
    }

    /** Get a loaded VM configuration. Returns null if not found. */
    public unowned Json.Object? get_config (string vm_name) {
        return cache[vm_name];
    }

    /** Delete a VM configuration from disk and cache. */
    public bool delete_config (string vm_name) {
        var path = get_config_path (vm_name);
        var file = GLib.File.new_for_path (path);

        if (!file.query_exists ()) {
            return false;
        }

        try {
            file.delete ();
            cache.remove (vm_name);
            config_changed (vm_name);
            message ("Deleted config: %s", path);
            return true;
        } catch (GLib.Error e) {
            warning ("Failed to delete config '%s': %s", path, e.message);
            return false;
        }
    }

    /** List all known VM names from the cache. */
    public string[] list_vms () {
        var names = new string[cache.size ()];
        int i = 0;
        cache.for_each ((k, v) => {
            names[i++] = (string) k;
        });
        return names;
    }

    /** Create a minimal default VM configuration. */
    public static Json.Object create_default_config (string vm_name) {
        var config = new Json.Object ();

        config.set_string_member ("schema_version", SCHEMA_VERSION);
        config.set_string_member ("name", vm_name);
        config.set_string_member ("uuid", generate_uuid ());

        // Machine
        var machine = new Json.Object ();
        machine.set_string_member ("type", "pc-i440fx-11.1");
        machine.set_string_member ("cpu", "pentium3");
        machine.set_int_member ("ram_mb", 256);
        machine.set_string_member ("accelerator", "kvm");
        config.set_object_member ("machine", machine);

        // Display
        var display = new Json.Object ();
        display.set_string_member ("type", "gtk");
        display.set_boolean_member ("fullscreen", false);
        display.set_string_member ("scale_filter", "nearest");
        config.set_object_member ("display", display);

        // Audio
        var audio = new Json.Object ();
        audio.set_string_member ("backend", "pa");
        audio.set_boolean_member ("sb16", true);
        audio.set_boolean_member ("opl3", true);
        config.set_object_member ("audio", audio);

        // Devices
        var devices = new Json.Array ();
        var vga = new Json.Object ();
        vga.set_string_member ("type", "VGA");
        vga.set_int_member ("vram_mb", 16);
        devices.add_object_element (vga);
        config.set_array_member ("devices", devices);

        // Storage
        var storage = new Json.Object ();
        var controllers = new Json.Array ();
        storage.set_array_member ("controllers", controllers);
        var floppy = new Json.Array ();
        storage.set_array_member ("floppy", floppy);
        config.set_object_member ("storage", storage);

        // Networking
        var networking = new Json.Object ();
        networking.set_string_member ("type", "user");
        config.set_object_member ("networking", networking);

        return config;
    }

    /** Generate a random UUID string. */
    private static string generate_uuid () {
        return GLib.Uuid.string_random ();
    }

    /** Get the full path for a VM config file. */
    private string get_config_path (string vm_name) {
        return GLib.Path.build_filename (machines_dir, vm_name + ".json");
    }
}
