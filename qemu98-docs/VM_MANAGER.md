# QEMU98 Manager — Architecture Reference

> **Status:** Design document. Implementation deferred to post Tier-2 QEMU features.
> 
> **Audience:** Contributors building or extending the VM management GUI.
> 
> **Scope:** This file describes the architecture, component tree, data model, 
> QMP interaction protocol, and build integration of the QEMU98 Manager — 
> a standalone GTK4/Vala desktop application for creating and managing 
> Win9x virtual machines.

---

## 0. TL;DR

We are building a **lightweight, VirtualBox-style desktop GUI** that wraps our 
Win9x-tailored `qemu-system-i386` binary. It stores VM configurations as JSON 
files, spawns QEMU processes with QMP control sockets, and provides an 
interactive interface for disk image creation, snapshot management, device 
configuration, and live media swapping (ISO / CUE/BIN hot-swap).

The manager is a **separate process** written in **Vala** (compiling to C via 
`valac`, linking against GTK4 and json-glib). It is built alongside QEMU using 
the existing Meson infrastructure and installed into `${prefix}/bin/` together 
with the QEMU binaries.

---

## 1. Design Principles

### 1.1 Separation of concerns

The manager **never links against QEMU libraries**. It communicates with each 
VM exclusively through:

- **Process spawning:** `GLib.Subprocess` to launch `qemu-system-i386` with 
  the correct CLI arguments.
- **QMP (QEMU Machine Protocol):** JSON-RPC over a per-VM Unix domain socket 
  for all runtime operations (device hotplug, snapshot, media change, shutdown).
- **Signal handling:** Standard POSIX signals (`SIGTERM` for graceful shutdown, 
  `SIGCHLD`/`waitpid` for crash/exit detection).

This means the manager and QEMU can evolve independently; the only coupling is 
the CLI flag set and the QMP command vocabulary, both of which are versioned 
and backward-compatible.

### 1.2 Single binary, multiple VMs

The manager is a single GTK application with a tabbed or tree-view interface 
showing all configured VMs. Each VM runs as a separate `qemu-system-i386` 
process. The manager tracks process lifecycle, QMP socket health, and display 
window state for each VM independently.

### 1.3 No libvirt dependency

We deliberately avoid libvirt. Reasons:

- Our custom PCI devices (Voodoo3, hypback) and CUE/BIN block driver have no 
  libvirt XML representation.
- libvirt's domain XML schema adds an unnecessary abstraction layer between the 
  user and the QEMU CLI.
- The manager's configuration format is simpler (JSON) and maps 1:1 to QEMU 
  command-line flags our fork supports.

### 1.4 Low-latency priority

The manager itself introduces zero runtime overhead to VM execution:
- QMP is asynchronous and non-blocking.
- The GUI runs in its own process and does not sit in the rendering hot path.
- Display is handled by QEMU's built-in GTK/SDL/VNC frontends, not proxied 
  through the manager.

---

## 2. Technology Stack

| Layer                     | Choice             | Rationale                                                          |
|---------------------------|--------------------|--------------------------------------------------------------------|
| **Language**              | Vala (≥0.56)       | Compiles to C, native GObject/GTK4 bindings, zero runtime overhead |
| **GUI Toolkit**           | GTK4 (≥4.10)       | Already a QEMU dependency (`--enable-gtk`); mature, cross-platform |
| **JSON**                  | json-glib-1.0      | Standard GObject JSON; maps naturally to Vala                      |
| **Process management**    | GLib.Subprocess    | Modern, async, safe fork/exec replacement                          |
| **QMP transport**         | GIO UnixSocket     | Async socket I/O for JSON-RPC over Unix domain sockets             |
| **Build system**          | Meson (≥1.5)       | Same as QEMU; first-class Vala support via `add_languages('vala')` |
| **Configuration storage** | JSON files on disk | `~/.local/share/qemu98/machines/*.json`                            |
| **Disk image management** | Calls `qemu-img`   | Same binary, same format support (raw, qcow2, VHD, cue)            |

### 2.1 Why Vala?

- **Zero runtime cost:** Vala compiles to C, then to native code. No GC pauses, 
  no JIT warmup, no FFI overhead. This matters for a tool that launches 
  latency-sensitive VMs.
- **Native GTK4 bindings:** Vala's GTK4 bindings are first-party maintained by 
  the GNOME project. No binding layer, no `gobject-introspection` overhead at 
  runtime.
- **GObject integration:** JSON parsing, subprocess management, and socket I/O 
  all use GLib/GIO APIs that Vala wraps idiomatically (async/await, signals, 
  properties).
- **Meson-native:** Meson's Vala support is production-grade. A single 
  `add_languages('vala')` and `dependency('gtk4')` gets a working build.
- **Low learning curve for C developers:** Vala syntax is familiar to anyone 
  who knows C, Java, or C#.

---

## 3. Component Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    QEMU98 Manager (GTK4/Vala)            │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ VM List      │  │ VM Config    │  │ Disk Image     │  │
│  │ (GtkListView)│  │ Editor       │  │ Wizard         │  │
│  │              │  │ (GtkNotebook)│  │ (GtkAssistant) │  │
│  └──────┬───────┘  └──────┬───────┘  └───────┬────────┘  │
│         │                 │                  │           │
│         └─────────────────┼──────────────────┘           │
│                           │                              │
│                  ┌────────┴────────┐                     │
│                  │   VM Controller │                     │
│                  │  (per-VM state) │                     │
│                  └────────┬────────┘                     │
│                           │                              │
│         ┌─────────────────┼─────────────────┐            │
│         │                 │                 │            │
│  ┌──────┴──────┐  ┌───────┴──────┐  ┌───────┴──────┐     │
│  │ QMP Client  │  │ Process Mgr  │  │ Snapshot     │     │
│  │ (Unix sock) │  │ (Subprocess) │  │ Manager      │     │
│  └──────┬──────┘  └──────┬───────┘  └───────┬──────┘     │
│         │                │                  │            │
└─────────┼────────────────┼──────────────────┼────────────┘
          │                │                  │
    ┌─────┴─────┐    ┌─────┴─────┐     ┌──────┴──────┐
    │  QMP      │    │ qemu-     │     │  qemu-img   │
    │  Socket   │    │ system-   │     │  (snapshot, │
    │ /tmp/     │    │ i386      │     │   create,   │
    │ q98-*.sock│    │ (spawned) │     │   info)     │
    └───────────┘    └───────────┘     └─────────────┘
```

### 3.1 Core modules

#### `ConfigStore` — Configuration persistence
- Reads/writes VM definitions as JSON files in `~/.local/share/qemu98/machines/`.
- Each file is a self-contained VM definition.
- Watches the directory for external changes (inotify).
- Schema versioned for forward compatibility.

#### `VmController` — Per-VM lifecycle
- Owns all state for a single VM: configuration, process handle, QMP connection.
- Exposes GObject properties: `state` (stopped/running/paused/suspended), 
  `qmp-connected`, `pid`.
- Emits signals: `state-changed`, `qmp-event`, `error`.

#### `QmpClient` — QMP transport
- Async GIO Unix socket client.
- Maintains a pending-command queue with monotonic `id` counter.
- Dispatches QMP events to registered handlers.
- Handles reconnection and greeting negotiation (`qmp_capabilities`).

#### `ProcessManager` — QEMU process lifecycle
- Builds CLI argument list from VM configuration.
- Spawns `qemu-system-i386` via `GLib.Subprocess`.
- Monitors process health (SIGCHLD).
- Graceful shutdown: sends `system_powerdown` via QMP, then SIGTERM after 
  timeout, then SIGKILL.

#### `SnapshotManager` — Disk snapshot operations
- Wraps `qemu-img snapshot` commands for offline operations.
- Wraps QMP `blockdev-snapshot-*` commands for live snapshots.
- Presents a tree view of snapshot chains.

---

## 4. Data Model

### 4.1 VM Configuration (JSON)

```jsonc
{
  "schema_version": 1,
  "name": "Windows 98 SE — Gaming Rig",
  "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "machine": {
    "type": "pc-i440fx-11.1",
    "cpu": "pentium3",
    "ram_mb": 256,
    "bios": "bios-256k.bin",       // or null for default
    "accelerator": "kvm"            // "kvm", "whpx", "tcg"
  },
  "display": {
    "type": "gtk",                  // "gtk", "sdl", "vnc"
    "fullscreen": false,
    "scale_filter": "nearest"       // "nearest" (default), "linear"
  },
  "audio": {
    "backend": "pa",                // "pa", "alsa", "pipewire", "oss", "sdl"
    "sb16": true,
    "opl3": true,
    "midi_soundfont": "/path/to/soundfont.sf2"  // null for none
  },
  "devices": [
    {
      "type": "VGA",
      "vram_mb": 16
    },
    {
      "type": "voodoo3",            // Paravirtual Voodoo3
      "renderer": "vulkan",         // "vulkan", "opengl"
      "vram_mb": 64
    },
    {
      "type": "hypback",            // Hypercall backdoor
      "id": "hbe0"
    },
    {
      "type": "sb16",
      "irq": 5,
      "dma": 1,
      "dma16": 5,
      "port": "0x220"
    },
    {
      "type": "ne2k_pci",           // Network
      "netdev": "net0"
    }
  ],
  "storage": {
    "controllers": [
      {
        "type": "ide",
        "bus": "ide.0",
        "devices": [
          {
            "id": "hda",
            "type": "hd",
            "file": "win98-disk.qcow2",
            "format": "qcow2",
            "boot_index": 1
          },
          {
            "id": "cd0",
            "type": "cdrom",
            "file": "win98-cd.iso",      // or "game.cue"
            "format": "raw",             // or "cue"
            "boot_index": 2
          }
        ]
      }
    ],
    "floppy": [
      {
        "id": "fda",
        "file": null                   // null = no disk inserted
      }
    ]
  },
  "networking": {
    "type": "user",                    // "user", "tap", "none"
    "hostfwd": [
      { "proto": "tcp", "host_port": 2222, "guest_port": 22 }
    ]
  },
  "shared_folders": [
    {
      "host_path": "/home/user/win98-share",
      "label": "Shared",
      "readonly": false
    }
  ],
  "snapshots": {
    "current": "clean-install",
    "chain": []
  }
}
```

### 4.2 CLI mapping

The `ProcessManager` translates the JSON into QEMU CLI flags:

```bash
qemu-system-i386 \
  -name "Windows 98 SE — Gaming Rig",debug-threads=on \
  -uuid a1b2c3d4-e5f6-7890-abcd-ef1234567890 \
  -machine pc-i440fx-11.1,accel=kvm \
  -cpu pentium3 \
  -m 256 \
  -bios /usr/local/share/qemu/bios-256k.bin \
  -vga std -device voodoo3,vram=64,renderer=vulkan \
  -device hypback,id=hbe0 \
  -device sb16,irq=5,dma=1,dma16=5,port=0x220 \
  -device ne2k_pci,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -drive file=win98-disk.qcow2,format=qcow2,if=ide,index=0,boot-index=1 \
  -drive file=win98-cd.iso,format=raw,if=ide,index=2,media=cdrom,boot-index=2 \
  -audiodev pa,id=audio0 -device sb16,audiodev=audio0 \
  -display gtk,scale-filter=nearest \
  -qmp unix:/tmp/qemu98-a1b2c3d4.sock,server=on,wait=off \
  -monitor none \
  -pidfile /tmp/qemu98-a1b2c3d4.pid
```

---

## 5. GUI Layout

```
┌─────────────────────────────────────────────────────────────┐
│  [Machine]  [View]  [Help]                                  │
├─────────────────────────────────────────────────────────────┤
│ ┌──────────────┐ ┌─────────────────────────────────────────┐│
│ │ VM List      │ │  Windows 98 SE — Gaming Rig  [Running]  ││
│ │              │ │                                         ││
│ │ ● Win98 SE   │ │ ┌─────────────────────────────────────┐ ││
│ │ ○ Win95 OSR2 │ │ │  General │ Devices │ Storage │ Net  │ ││
│ │ ○ DOS 6.22   │ │ ├─────────────────────────────────────┤ ││
│ │              │ │ │                                     │ ││
│ │              │ │ │  VM Name: [Windows 98 SE — Games___]│ ││
│ │              │ │ │  CPU:     [pentium3          ▾    ] │ ││
│ │              │ │ │  RAM:     [256 MB            ▾    ] │ ││
│ │              │ │ │  Machine: [i440FX            ▾    ] │ ││
│ │              │ │ │  Accel:   [KVM               ▾    ] │ ││
│ │              │ │ │  Display: [GTK               ▾    ] │ ││
│ │              │ │ │  GPU:     [☑ Voodoo3 (Vulkan)     ] │ ││
│ │              │ │ │                                     │ ││
│ │              │ │ │         [Start VM]  [Save Config]   │ ││
│ │              │ │ └─────────────────────────────────────┘ ││
│ │              │ │                                         ││
│ │  [+ New VM]  │ │  Snapshot: [clean-install ▾]            ││
│ │              │ │  [Take Snapshot] [Restore] [Delete]     ││
│ │              │ │                                         ││
│ │              │ │  CD-ROM: [game.cue           ▾]         ││
│ │              │ │  [Eject] [Browse...]   Status: Mounted  ││
│ └──────────────┘ └─────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 5.1 Interaction flows

#### Creating a new VM
1. User clicks `+ New VM`
2. Multi-page wizard (GtkAssistant):
   - Page 1: VM name, OS type (Win95 / Win98 / WinME / DOS / Other)
   - Page 2: CPU, RAM, accelerator
   - Page 3: Create or select disk image (opens image creation sub-wizard)
   - Page 4: Attach CD-ROM / floppy images
   - Page 5: Configure display, audio, network
   - Page 6: Review summary, create
3. JSON config written to `~/.local/share/qemu98/machines/<name>.json`
4. VM appears in the list

#### Starting a VM
1. User selects VM in list, clicks `Start VM`
2. Manager builds CLI, spawns `qemu-system-i386`
3. QMP socket connects; manager sends `qmp_capabilities`
4. VM state transitions to "Running" (green dot)
5. QEMU's GTK/SDL window opens independently

#### Live CD/ISO swap
1. User selects the CD-ROM device row
2. Clicks `Browse...` or picks from recent images
3. Manager sends QMP:
   ```json
   {"execute":"blockdev-change-medium","arguments":{"device":"cd0","filename":"/path/to/game.cue","format":"cue"}}
   ```
4. Status updates to "Mounted: game.cue"

#### Taking a snapshot
1. User clicks `Take Snapshot`, enters a name
2. Manager sends QMP:
   ```json
   {"execute":"blockdev-snapshot-sync","arguments":{"device":"hda","snapshot-file":"/path/to/snap.qcow2","format":"qcow2"}}
   ```
3. Snapshot appears in the chain

#### Graceful shutdown
1. User clicks `Stop VM` or closes the QEMU window
2. Manager sends `system_powerdown` via QMP
3. Waits up to 30 seconds for QEMU to exit
4. If QEMU hasn't exited, sends SIGTERM
5. If still running after 5 more seconds, sends SIGKILL

---

## 6. QMP Protocol Interaction

### 6.1 Connection lifecycle

```
Manager                           QEMU
   │                                │
   │──── spawn qemu-system-i386 ───→│
   │                                │
   │←─── QMP greeting (JSON) ───────│  {"QMP": {"version": {...}, "capabilities": [...]}}
   │                                │
   │──── {execute:qmp_capabilities}→│
   │←──── {"return": {}} ───────────│
   │                                │
   │  [Ready for commands]          │
   │                                │
   │←──── QMP events (stream) ──────│  {"event": "SHUTDOWN", ...}
   │                                │  {"event": "BLOCK_IMAGE_CORRUPTED", ...}
```

### 6.2 Key QMP commands used

| Operation           | QMP Command                | Usage                     |
|---------------------|----------------------------|---------------------------|
| Query status        | `query-status`             | Running/paused state      |
| Query block devices | `query-block`              | List all drives and media |
| Hot-swap media      | `blockdev-change-medium`   | Swap CD-ROM ISO/CUE       |
| Live snapshot       | `blockdev-snapshot-sync`   | Take disk snapshot        |
| Delete snapshot     | `blockdev-snapshot-delete` | Remove snapshot           |
| Hot-add device      | `device_add`               | Add PCI device at runtime |
| Hot-remove device   | `device_del`               | Remove PCI device         |
| Pause VM            | `stop`                     | Freeze execution          |
| Resume VM           | `cont`                     | Resume execution          |
| Graceful shutdown   | `system_powerdown`         | ACPI shutdown             |
| Force reset         | `system_reset`             | Hard reset                |
| Screenshot          | `screendump`               | Capture to PNG            |
| Query VNC           | `query-vnc`                | VNC connection info       |

### 6.3 QMP events monitored

| Event                                | Action                   |
|--------------------------------------|--------------------------|
| `SHUTDOWN`                           | VM stopped; update state |
| `RESET`                              | VM reset; log event      |
| `STOP`                               | VM paused; update state  |
| `RESUME`                             | VM resumed; update state |
| `BLOCK_IMAGE_CORRUPTED`              | Alert user               |
| `BLOCK_IO_ERROR`                     | Alert user               |
| `VNC_CONNECTED` / `VNC_DISCONNECTED` | Update client list       |
| `RTC_CHANGE`                         | Log time change          |

---

## 7. Build Integration

### 7.1 Meson setup

The manager lives in `manager/` at the repo root. QEMU's top-level 
`meson.build` adds it conditionally:

```python
# In meson.build, near the end of the file:

build_manager = get_option('build_manager') \
  .require(have_system, error_message: 'manager requires system emulator') \
  .require(gtk.found(), error_message: 'manager requires GTK') \
  .allowed()

if build_manager
  subdir('manager')
endif
```

A new meson option:
```python
# In meson_options.txt:
option('build_manager', type: 'feature', value: 'auto',
       description: 'Build the QEMU98 VM Manager GUI')
```

### 7.2 Manager meson.build

```python
# manager/meson.build

add_languages('vala', required: true)

valac = meson.get_compiler('vala')

manager_deps = [
  dependency('gtk4', version: '>=4.10'),
  dependency('json-glib-1.0', version: '>=1.6'),
  dependency('gio-unix-2.0'),
  dependency('glib-2.0', version: '>=2.72'),
]

manager_sources = files(
  'src/main.vala',
  'src/config-store.vala',
  'src/vm-controller.vala',
  'src/qmp-client.vala',
  'src/process-manager.vala',
  'src/snapshot-manager.vala',
  'src/ui/main-window.vala',
  'src/ui/vm-list.vala',
  'src/ui/vm-config-editor.vala',
  'src/ui/new-vm-wizard.vala',
  'src/ui/disk-image-wizard.vala',
  'src/ui/snapshot-panel.vala',
  'src/ui/media-panel.vala',
)

executable('qemu98-manager',
  manager_sources,
  dependencies: manager_deps,
  vala_args: [
    '--target-glib=2.72',
    '--pkg=gtk4',
    '--pkg=json-glib-1.0',
    '--pkg=gio-unix-2.0',
  ],
  install: true,
  install_dir: get_option('bindir'),
)
```

### 7.3 Installation

After `make install`:
```
${prefix}/bin/qemu-system-i386       # QEMU binary
${prefix}/bin/qemu-system-x86_64     # QEMU binary (64-bit)
${prefix}/bin/qemu-img               # Disk image tool
${prefix}/bin/qemu98-manager         # VM Manager GUI
${prefix}/share/applications/qemu98-manager.desktop  # .desktop entry
${prefix}/share/icons/hicolor/*/apps/qemu98-manager.png  # App icon
```

---

## 8. Source Tree Layout

```
manager/
├── meson.build                  # Meson build definition
├── README.md                    # Manager-specific docs
├── data/
│   ├── qemu98-manager.desktop.in  # .desktop file template
│   └── icons/                     # App icons
├── src/
│   ├── main.vala                  # Entry point, GtkApplication subclass
│   ├── config-store.vala          # JSON config read/write + schema
│   ├── vm-controller.vala         # Per-VM lifecycle state machine
│   ├── qmp-client.vala            # Async QMP Unix socket client
│   ├── process-manager.vala       # QEMU process spawn/monitor
│   ├── snapshot-manager.vala      # Snapshot CRUD via qemu-img + QMP
│   ├── ui/
│   │   ├── main-window.vala       # Top-level window, menu bar
│   │   ├── vm-list.vala           # Sidebar VM list (GtkListView)
│   │   ├── vm-config-editor.vala  # Tabbed config editor
│   │   ├── new-vm-wizard.vala     # Multi-page VM creation wizard
│   │   ├── disk-image-wizard.vala # Disk image creation helper
│   │   ├── snapshot-panel.vala    # Snapshot chain view/actions
│   │   └── media-panel.vala       # CD/floppy insert/eject panel
│   └── utils.vala                 # Shared helpers (path resolution, etc.)
└── tests/
    ├── meson.build
    ├── test-config-store.vala
    ├── test-qmp-client.vala
    └── test-process-manager.vala
```

---

## 9. Prerequisites (Host)

| Package         | Debian/Ubuntu      | Fedora            | Purpose          |
|-----------------|--------------------|-------------------|------------------|
| valac           | `valac`            | `vala`            | Vala compiler    |
| gtk4-devel      | `libgtk-4-dev`     | `gtk4-devel`      | GTK4 GUI toolkit |
| json-glib-devel | `libjson-glib-dev` | `json-glib-devel` | JSON parsing     |
| glib2-devel     | `libglib2.0-dev`   | `glib2-devel`     | Core GLib/GIO    |
| meson           | `meson`            | `meson`           | Build system     |

These are in addition to the QEMU build dependencies listed in `BUILD.md` §1.2.

Install on Debian/Ubuntu:
```bash
sudo apt install -y valac libgtk-4-dev libjson-glib-dev
```

---

## 10. Implementation Roadmap

### Phase 1 — Skeleton (Week 1)
- [ ] Meson build integration (meson option, subdir, `valac` detection)
- [ ] `main.vala`: GtkApplication, window, menu bar
- [ ] `config-store.vala`: JSON read/write with schema v1
- [ ] Manual test: builds, opens a window, creates/saves a dummy config

### Phase 2 — VM Lifecycle (Week 2–3)
- [ ] `process-manager.vala`: CLI builder, subprocess spawn, SIGCHLD monitor
- [ ] `qmp-client.vala`: Unix socket connect, greeting, command dispatch, events
- [ ] `vm-controller.vala`: State machine (stopped→running→paused→stopped)
- [ ] `ui/vm-list.vala`: Sidebar with VM entries and status indicators
- [ ] Manual test: start a real Win9x VM from a saved config, see it run, 
  stop it gracefully

### Phase 3 — Configuration UI (Week 3–5)
- [ ] `ui/vm-config-editor.vala`: Tabbed editor for an existing VM
- [ ] `ui/new-vm-wizard.vala`: Multi-page creation wizard
- [ ] `ui/disk-image-wizard.vala`: qemu-img wrapper with size/format picker
- [ ] Manual test: create two VMs with different configs, start both, verify 
  they don't interfere

### Phase 4 — Runtime Operations (Week 5–7)
- [ ] `ui/media-panel.vala`: CD-ROM / floppy insert/eject with CUE/BIN support
- [ ] `snapshot-manager.vala`: Live snapshots via QMP, offline via qemu-img
- [ ] `ui/snapshot-panel.vala`: Snapshot chain tree, take/restore/delete
- [ ] Manual test: live-swap CUE/BIN while VM runs, take and restore snapshot

### Phase 5 — Polish (Week 7–8)
- [ ] `.desktop` file, app icon
- [ ] Error handling and recovery (QEMU crash, QMP disconnect, invalid config)
- [ ] Keyboard shortcuts (Ctrl+N new VM, Ctrl+S save, etc.)
- [ ] Integration test suite

---

## 11. Configuration File Locations

| Path                               | Purpose                      |
|------------------------------------|------------------------------|
| `~/.local/share/qemu98/machines/`  | VM definition JSON files     |
| `~/.local/share/qemu98/images/`    | Default disk image directory |
| `~/.local/share/qemu98/snapshots/` | Snapshot chain storage       |
| `~/.cache/qemu98/`                 | QMP sockets, PID files, logs |
| `/tmp/qemu98-*.sock`               | Runtime QMP Unix sockets     |

---

## 12. Open Questions

| #  | Question                                                                                                                                                                                           | Resolution                                                                                                                                          |
|----|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|
| Q1 | GTK4 or GTK3? The QEMU built-in display uses GTK3. We use GTK4 for the manager because GTK3 is in maintenance mode and GTK4 has better ListView widgets. No conflict — they're separate processes. | **Use GTK4**                                                                                                                                        |
| Q2 | Should the manager embed the QEMU display window, or launch it separately?                                                                                                                         | **Launch separately.** Embedding adds complexity (GDK window reparenting) for zero latency benefit. The QEMU GTK/SDL window is already low-latency. |
| Q3 | VNC-only mode? If `-display vnc`, the manager can show connection info.                                                                                                                            | **Support VNC info display**, no embedded VNC client.                                                                                               |
| Q4 | Should we auto-generate Vala bindings for QMP?                                                                                                                                                     | **No.** QMP is JSON-RPC; json-glib handles it. No code generation needed.                                                                           |
| Q5 | What about i18n/l10n?                                                                                                                                                                              | **Deferred.** English-only for v1. GTK4 supports gettext when needed.                                                                               |

---

## 13. References

- [Vala Language Reference](https://vala.dev/)
- [GTK4 Documentation](https://docs.gtk.org/gtk4/)
- [json-glib Reference](https://gnome.pages.gitlab.gnome.org/json-glib/)
- [GLib Subprocess API](https://docs.gtk.org/glib/class.Subprocess.html)
- [GIO Unix Sockets](https://docs.gtk.org/gio/class.UnixSocketAddress.html)
- [QEMU QMP Reference](https://www.qemu.org/docs/master/interop/qmp-spec.html)
- `WIN9X_QEMU_PLAN.md` — Custom PCI devices and hypercall ABI
- `BUILD.md` — QEMU build instructions and dependencies
