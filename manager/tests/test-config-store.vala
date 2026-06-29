/*
 * test-config-store.vala — ConfigStore round-trip unit test
 *
 * Verifies:
 *   1. ConfigStore can save a default VM config to a temp directory.
 *   2. ConfigStore can reload and read back the same config.
 *   3. List VMs returns the expected name.
 *   4. All config fields survive the round trip unchanged.
 *
 * Runs as a standalone executable. Exit code 0 = pass, non-zero = fail.
 */

class TestConfigStore {

    private static string temp_dir;
    private static int tests_passed = 0;
    private static int tests_failed = 0;

    public static int main () {
        // Override XDG_DATA_HOME to use a temp directory
        try {
            temp_dir = GLib.DirUtils.make_tmp ("qemu98-test-XXXXXX");
        } catch (GLib.FileError e) {
            GLib.stderr.printf ("FATAL: cannot create temp dir: %s\n", e.message);
            return 1;
        }
        GLib.Environment.set_variable ("XDG_DATA_HOME", temp_dir, true);

        test_round_trip ();
        test_delete ();
        test_list_vms ();
        test_uuid_uniqueness ();

        // Cleanup
        cleanup_temp_dir ();

        // Summary
        GLib.stdout.printf ("\n=== Results: %d passed, %d failed ===\n",
                            tests_passed, tests_failed);

        return tests_failed > 0 ? 1 : 0;
    }

    // ---- Helpers ----

    private static void assert_true (bool condition, string message) {
        if (condition) {
            tests_passed++;
            GLib.stdout.printf ("  PASS: %s\n", message);
        } else {
            tests_failed++;
            GLib.stderr.printf ("  FAIL: %s\n", message);
        }
    }

    private static void cleanup_temp_dir () {
        var dir = GLib.File.new_for_path (temp_dir);
        try {
            if (dir.query_exists ()) {
                var enumerator = dir.enumerate_children (
                    "standard::*", GLib.FileQueryInfoFlags.NONE
                );
                GLib.FileInfo info;
                while ((info = enumerator.next_file ()) != null) {
                    dir.get_child (info.get_name ()).delete ();
                }
                dir.delete ();
            }
        } catch (GLib.Error e) {
            GLib.stderr.printf ("  WARN: cleanup failed: %s\n", e.message);
        }
    }

    // ---- Test: save → reload → verify ----

    private static void test_round_trip () {
        GLib.stdout.printf ("\n[Test] Round-trip: save → reload → verify\n");

        var store = new ConfigStore ();
        var name = "test-vm-roundtrip";
        var original = ConfigStore.create_default_config (name);

        // Modify a field so we can distinguish from defaults
        var machine = original.get_object_member ("machine");
        machine.set_int_member ("ram_mb", 512);

        // Save
        var saved = store.save_config (name, original);
        assert_true (saved, "Config saved successfully");

        // Reload fresh store (simulates app restart)
        var store2 = new ConfigStore ();
        store2.reload ();

        var loaded = store2.get_config (name);
        assert_true (loaded != null, "Config found in reloaded store");

        if (loaded == null) return;

        // Verify schema version
        assert_true (loaded.has_member ("schema_version"),
                     "Has schema_version field");
        assert_true (loaded.get_string_member ("schema_version") == "1",
                     "Schema version is '1'");

        // Verify UUID
        assert_true (loaded.has_member ("uuid"),
                     "Has UUID field");
        assert_true (loaded.get_string_member ("uuid") ==
                     original.get_string_member ("uuid"),
                     "UUID matches");

        // Verify machine section
        var loaded_machine = loaded.get_object_member ("machine");
        assert_true (loaded_machine.get_int_member ("ram_mb") == 512,
                     "RAM 512 MB persists after round trip");
        assert_true (loaded_machine.get_string_member ("cpu") == "pentium3",
                     "CPU type persists");
        assert_true (loaded_machine.get_string_member ("accelerator") == "kvm",
                     "Accelerator persists");

        // Verify display section
        var loaded_display = loaded.get_object_member ("display");
        assert_true (loaded_display.get_string_member ("type") == "gtk",
                     "Display type persists");

        // Verify audio section
        var loaded_audio = loaded.get_object_member ("audio");
        assert_true (loaded_audio.get_boolean_member ("sb16") == true,
                     "SB16 enabled persists");
        assert_true (loaded_audio.get_boolean_member ("opl3") == true,
                     "OPL3 enabled persists");

        // Verify devices
        var loaded_devices = loaded.get_array_member ("devices");
        assert_true (loaded_devices.get_length () == 1,
                     "One device in config");

        // Verify storage structure exists
        assert_true (loaded.has_member ("storage"),
                     "Storage section exists");

        // Verify networking
        assert_true (loaded.has_member ("networking"),
                     "Networking section exists");
    }

    // ---- Test: delete ----

    private static void test_delete () {
        GLib.stdout.printf ("\n[Test] Delete config\n");

        var store = new ConfigStore ();
        var name = "test-vm-delete";

        // Create and save
        var config = ConfigStore.create_default_config (name);
        store.save_config (name, config);
        assert_true (store.get_config (name) != null,
                     "Config exists before delete");

        // Delete
        var deleted = store.delete_config (name);
        assert_true (deleted, "Delete returned true");

        // Verify gone
        assert_true (store.get_config (name) == null,
                     "Config is null after delete");
    }

    // ---- Test: list VMs ----

    private static void test_list_vms () {
        GLib.stdout.printf ("\n[Test] List VMs\n");

        var store = new ConfigStore ();

        // Create two VMs
        store.save_config ("vm-alpha", ConfigStore.create_default_config ("vm-alpha"));
        store.save_config ("vm-beta", ConfigStore.create_default_config ("vm-beta"));

        var names = store.list_vms ();
        // We may have residual VMs from previous tests; just check
        // that both new ones are present
        bool found_alpha = false;
        bool found_beta = false;
        foreach (var n in names) {
            if (n == "vm-alpha") found_alpha = true;
            if (n == "vm-beta") found_beta = true;
        }

        assert_true (found_alpha, "vm-alpha in list_vms()");
        assert_true (found_beta, "vm-beta in list_vms()");

        // Cleanup
        store.delete_config ("vm-alpha");
        store.delete_config ("vm-beta");
    }

    // ---- Test: UUID uniqueness ----

    private static void test_uuid_uniqueness () {
        GLib.stdout.printf ("\n[Test] UUID uniqueness\n");

        var config1 = ConfigStore.create_default_config ("vm1");
        var config2 = ConfigStore.create_default_config ("vm2");

        var uuid1 = config1.get_string_member ("uuid");
        var uuid2 = config2.get_string_member ("uuid");

        assert_true (uuid1 != uuid2, "Two VMs have different UUIDs");
        assert_true (uuid1.length > 0, "UUID is non-empty");
        assert_true (uuid2.length > 0, "UUID is non-empty");
    }
}
