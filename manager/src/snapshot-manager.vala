/*
 * snapshot-manager.vala — Snapshot listing via qemu-img
 *
 * Wraps `qemu-img snapshot -l <disk_path>` to list snapshots on a
 * QCOW2 (or other format) disk image. Parses the human-readable
 * output into SnapshotInfo records.
 *
 * Phase 4: snapshot listing. QMP operations (savevm/loadvm/delvm)
 * are handled by VmController.
 */

/** Metadata for a single disk image snapshot. */
public struct SnapshotInfo {
/** Internal QCOW2 snapshot ID (empty string for unnamed). */
    public string id;
/** User-visible snapshot tag/name. */
    public string name;
/** Virtual machine size at snapshot time. */
    public string size_str;
/** Human-readable date string. */
    public string date;
/** VM clock value at snapshot time. */
    public string vm_clock;
}

public class SnapshotManager : GLib.Object {

    /** Path to the qemu-img binary. */
    private const string QEMU_IMG = "qemu-img";

    // ---- Construction ----

    public SnapshotManager () {
    }

    // ---- Snapshot listing ----

    /**
     * List all snapshots on a disk image.
     *
     * Spawns `qemu-img snapshot -l <disk_path>` synchronously and
     * parses the tabular output.
     *
     * @param disk_path  Full path to the disk image file.
     * @return           Array of snapshot info records, or null on error.
     */
    public SnapshotInfo[]? list_snapshots(string disk_path) throws GLib.Error {
        string[] argv = { QEMU_IMG, "snapshot", "-l", disk_path };
        int exit_code;
        string stdout_str;
        string stderr_str;

        try {
            GLib.Process.spawn_sync(
                    null, // working directory
                    argv, // argv
                    null, // envp (inherit)
                    GLib.SpawnFlags.SEARCH_PATH,
                    null, // child_setup
                    out stdout_str,
                    out stderr_str,
                    out exit_code
            );
        } catch (GLib.SpawnError e) {
            warning("SnapshotManager: failed to spawn qemu-img: %s", e.message);
            throw e;
        }

        if (exit_code != 0) {
            warning("SnapshotManager: qemu-img exited with %d: %s",
                    exit_code, stderr_str.strip());
            throw new GLib.FileError.FAILED (
                    @"qemu-img snapshot -l failed: $(stderr_str.strip ())"
            );
        }

        return parse_snapshot_output(stdout_str);
    }

    /**
     * Parse the tabular output of `qemu-img snapshot -l`.
     *
     * Expected format:
     *   Snapshot list:
     *   ID        TAG               VM SIZE                DATE       VM CLOCK
     *   --        Backup1           1.5G 2025-01-15 10:30:00   00:15:23.456
     *   1         fresh_install     200M 2025-01-15 09:00:00   00:02:01.123
     *
     * If there are no snapshots ("There is no snapshot available."),
     * returns an empty array.
     */
    private SnapshotInfo[] parse_snapshot_output(string output) {
        var snapshots = new SnapshotInfo[0];
        var lines = output.split("\n");

        bool in_table = false;
        foreach (var line in lines) {
            var trimmed = line.strip();

        // Detect table start
            if (trimmed.has_prefix("Snapshot list:")) {
                in_table = true;
                continue;
            }

            // Skip header line and empty lines
            if (trimmed == "" || trimmed.has_prefix("ID")) {
                continue;
            }

            // Detect "no snapshots" message
            if (trimmed.contains("no snapshot")) {
                return snapshots;
            }

            if (!in_table)
            continue;

            // Parse columns: ID, TAG, VM SIZE, DATE, VM CLOCK
            // The format uses variable-width columns.
            // ID is at pos 0-10, TAG at pos 10-30, SIZE at pos 30-45,
            // DATE at pos 45-65, VM CLOCK at pos 65+
            var columns = split_snapshot_line(trimmed);
            if (columns.length < 5)
            continue;

            var info = SnapshotInfo() {
                id = columns[0],
                name = columns[1],
                size_str = columns[2],
                date = columns[3],
                vm_clock = columns[4]
            };
            snapshots += info;
        }

        return snapshots;
    }

    /**
     * Split a snapshot line by fixed-width column positions.
     *
     * Col 0-10 : ID (right-aligned number or "--")
     * Col 10-30: TAG (space-padded name)
     * Col 30-45: VM SIZE (right-aligned, e.g. "1.5G")
     * Col 45-65: DATE
     * Col 65+  : VM CLOCK
     */
    private string[] split_snapshot_line(string line) {
        var result = new string[5];

    // ID: first non-space sequence, or "--"
        int pos = 0;
    // Skip leading spaces
        while (pos < line.length && line[pos] == ' ')
        pos++;

        if (pos + 2 <= line.length && line.substring(pos, 2) == "--") {
            result[0] = "";
            pos += 2;
        } else {
            int start = pos;
            while (pos < line.length && line[pos] != ' ')
            pos++;
            result[0] = line.substring(start, pos - start);
        }

        // Skip spaces to TAG
        while (pos < line.length && line[pos] == ' ')
        pos++;

        // TAG: until the next double-space or right-aligned number
        int tag_start = pos;
        // The TAG field is followed by enough spaces to reach column 30,
        // then a right-aligned size. Scan for a digit preceded by space(s).
        // We look for a sequence of spaces followed by a digit.
        while (pos < line.length) {
            if (line[pos] == ' ' && pos + 1 < line.length && line[pos + 1].isdigit()) {
            // Found the boundary: TAG ends here
                break;
            }
            pos++;
        }
        result[1] = line.substring(tag_start, pos - tag_start).strip();

        // Skip to the size digits
        while (pos < line.length && line[pos] == ' ')
        pos++;

        // SIZE: digits + optional dot + digits + optional unit suffix
        int size_start = pos;
        while (pos < line.length && !line[pos].isspace())
        pos++;
        result[2] = line.substring(size_start, pos - size_start);

        // Skip spaces to DATE
        while (pos < line.length && line[pos] == ' ')
        pos++;

        // DATE: fixed-width YYYY-MM-DD HH:MM:SS (19 chars)
        if (pos + 19 <= line.length) {
            result[3] = line.substring(pos, 19);
            pos += 19;
        } else {
            result[3] = "";
        }

        // Skip spaces to VM CLOCK
        while (pos < line.length && line[pos] == ' ')
        pos++;

        // VM CLOCK: HH:MM:SS.mmm
        int clock_start = pos;
        while (pos < line.length && !line[pos].isspace())
        pos++;
        result[4] = line.substring(clock_start, pos - clock_start);

        return result;
    }
}
