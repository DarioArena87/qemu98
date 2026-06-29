# Win9x-Tailored QEMU Fork — Architectural Reference

> **Status:** Living design document. Update decisions inline as they evolve.
> 
> **Audience:** Future-us coming back to this project after a break, and any
> new contributor trying to understand why things are the way they are.
> 
> **Scope:** This file describes *what we are building, why, and how each
> piece fits together.* It is not a step-by-step how-to-build manual — see
> `BUILD.md` (Also a living design document) or the upstream QEMU docs for that. The focus is on the
> architecture of Win9x add-ons.

---

## 0. TL;DR

We are forking QEMU to virtualize **Windows 95 / 98 / ME (Win9x)** PCs of the
1995–2001 era with full host-side acceleration for graphics (3dfx Glide and
Direct3D 5/6/7), audio, CD-ROM mounting (CUE/BIN), host integration, and
pixel-perfect scaling.

This fork should add a `guest-tools/` tree containing the Win9x-side DLLs/VxD installer,
and a **`manager/`** tree containing the QEMU98 Manager — a standalone GTK4/Vala
desktop GUI for creating and managing Win9x virtual machines (see `VM_MANAGER.md`).
**Three of the most expensive customizations** (CUE/BIN block driver, a
nearest-neighbor scaler, and a hypercall backdoor PCI device). 
**Three of the most guest-specific customizations** (Glide/D3D
shims, Win9x VxD, installer) live entirely inside `guest-tools/`.

---

## 1. Project Goals (verbatim from the original brief)

### Core Virtualization
- Hardware-accelerated CPU via **KVM** (Linux) and **WHPX** (Windows).
- Pluggable device model — `-device` flags for arbitrary hardware.
- BIOS/Firmware: SeaBIOS, OVMF, real BIOS ROM dumps.
- Hybrid PC platform (i440FX-based) with full user customization.

### Graphics & Display
- Accelerated 2D/3D via DDraw/D3D 5/6/7 → host Vulkan/OpenGL.
- 3dfx Glide API support.
- Nearest-neighbor (pixel-perfect) upscaling, 4:3 aspect preserved
  (e.g., 640×480 → 1920×1080 host).
- VGA/SVGA/VESA emulation with full video BIOS.

### Audio
- Sound Blaster 16 / SB Pro / ESS, OPL3 FM synthesis.
- MIDI via user-selectable SoundFonts.
- Low-latency audio via OpenAL.

### Storage & Media
- CD/DVD images: ISO, **CUE/BIN**, ZIP, RAR, with hot-swap.
- Floppy: IMG, hot-swap.
- Shared folders exposed as removable drives.
- Disk images: raw, QCOW2, VHD.

### Host–Guest Integration
- Bidirectional clipboard over serial.
- Configurable mouse grab/release.

### Cross-Platform
- Linux: KVM, fully functional.
- Windows: WHPX (planned, FFMA bindings).

### VM Management
- **QEMU98 Manager** — standalone GTK4/Vala desktop GUI (see `VM_MANAGER.md`).
- VirtualBox-style VM list, creation wizard, device configurator.
- Live media swap (ISO/CUE/BIN hot-swap from the GUI).
- Snapshot management (take, restore, delete) with chain visualization.
- Disk image creation (raw, qcow2, VHD) via integrated `qemu-img` wrapper.
- Per-VM JSON configuration stored in `~/.local/share/qemu98/machines/`.
- Full QMP-based runtime control — no libvirt dependency.

---

## 2. The Conversation Arc

This document is the consolidated outcome of separate discussion turns.
Recording the arc makes future-me understand *why* certain decisions were
made, not just what was decided.

### Turn 1 — Build configuration
> "I ran the upstream build commands; the full build takes forever."

Outcome: ruled out-of-scope cross-arch TCG, BSD-user, docs, guest agent,
and most block-format backends. Settled on a focused `./configure` for **only
`i386-softmmu` and `x86_64-softmmu`** plus a curated set of feature flags.

### Turn 2 — Submodule vs in-tree
> "Can I make `qemu/` a git submodule and add features externally?"

Outcome: technically yes for a single feature, but at the scope of Glide+DDraw
shims plus the host-side Vulkan renderer it stops being viable. **We chose to
fork** — the qemu code should remain mergeable with upstream (no fundamental 
architectural changes), our deltas are versioned alongside.

### Turn 3 — Paravirt hypercalls (vmdisp9x-style)
> "What if I implement Glide and D3D as guest-side DLLs that issue
> hypercalls to a QEMU PCI BAR?"

Outcome: validated. The control flow is `ring-3 DLL → ring-0 VxD → MMIO
poke → QEMU`. This matches the proven vmdisp9x/SoftGPU/Mesa9x blueprint.
Confirmed Danaozhong/3dfx-Glide-API is the **Glide SDK**, not a hypercall shim
(**the shim is something we must write ourselves** — that is what
nGlide / dgVoodoo / qemu-3dfx do). Confirmed `d7vk` is Win32-only and won't
work on Win9x.

### Turn 4 — VM Manager (virt-manager vs custom)
> "Can we use virt-manager or Cockpit for managing VMs, or should we
> build something custom?"

Outcome: **Build a custom GTK4/Vala desktop manager.** libvirt adds an 
unnecessary abstraction layer that doesn't support our custom devices
(Voodoo3, hypback, CUE/BIN block driver). The manager is a separate process 
that communicates with QEMU exclusively via QMP over Unix sockets — it never 
links against QEMU libraries. This keeps the QEMU fork mergeable with 
upstream and the manager independently versioned.

Architecture documented in full in `VM_MANAGER.md`.

---

## 3. Build Configuration

### 3.1 Recommended `./configure` invocation

```bash
mkdir build && cd build
../configure \
  --target-list='i386-softmmu x86_64-softmmu' \
  --disable-user --disable-linux-user --disable-bsd-user \
  --disable-docs --disable-guest-agent --disable-qga-vss \
  --disable-rust --disable-plugins --disable-tcg-interpreter \
  --audio-drv-list='alsa,pa,pipewire,oss,sdl' \
  --enable-kvm --enable-whpx \
  --enable-guest-tools --enable-vm-manager \
  --disable-virtfs --disable-vhost-user \
  --disable-vfio-user-server --disable-libvduse --disable-vduse-blk-export \
  --disable-rbd --disable-libiscsi --disable-libnfs --disable-libssh \
  --disable-mpath --disable-rdma --disable-passt \
  --disable-bzip2 --disable-lzfse --disable-lzo --disable-snappy --disable-zstd \
  --disable-tpm --disable-smartcard --disable-u2f --disable-canokey \
  --disable-usb-redir --disable-brlapi \
  --disable-replication --disable-colo-proxy \
  --disable-multiprocess \
  --disable-cocoa \
  --disable-spice --disable-spice-protocol --disable-dbus-display \
  --enable-vnc --enable-gtk --enable-sdl --enable-slirp --enable-pixman \
  --disable-virglrenderer --disable-rutabaga-gfx --disable-pvg \
  --disable-fuse --disable-fuse-lseek --disable-igvm \
  --disable-qpl --disable-uadk --disable-qatzip \
  --enable-pie
make -j$(nproc)
```

For the absolute fastest build, drop `x86_64-softmmu` from `--target-list` to
get only the 32-bit system emulator.

### 3.2 Why each flag

#### Targets (single biggest win)
- `--target-list='i386-softmmu x86_64-softmmu'` — the i440FX machine type
  (`hw/i386/pc_piix.c`) is compiled into both binaries; we get both ABIs
  without crossing arch lines.
- `--disable-user --disable-linux-user --disable-bsd-user` — removes ~10
  user-mode emulators and their cross-compiled runtimes.

The upstream default builds **every `*-softmmu`** (≈28 architectures) plus
all user-mode emulators. ~80% of wall-clock time is in cross-arch TCG/CPU
code we will never need.

#### Cross-platform accelerators
The accelerators should be auto-detected from the `configure` script but they can be specified if needed:

- `--enable-kvm` — Linux in-kernel hypervisor. Auto-detected when `/dev/kvm` exists. Works only on Linux hosts.
- `--enable-whpx` — Windows Hypervisor Platform. Auto-detected on Windows hosts. Works only on Windows hosts.

#### Audio (low-latency, host-side accelerators)
- `--audio-drv-list='alsa,pa,pipewire,oss,sdl'` — host backends only.
  We do *not* need `--enable-opengl` for audio; that's only for display GL
  shader scaler which is a separate decision in §6.2.

#### Graphics stacks (host-side UI)
- `--enable-sdl` — SDL2 host windowing (the default candidate).
- `--enable-gtk` — alternative host windowing, supports GTK3.
- `--enable-vnc` — VNC server for remote access.
- `--enable-slirp` — usermode networking stack.
- `--enable-pixman` — image scaling primitive.
- **Skipped:** `--disable-virglrenderer --disable-rutabaga-gfx --disable-pvg` —
  virtio-gpu 3D acceleration paths are *not* what we need for Win9x guest
  games (see §6.2 and §7.4). Keep these disabled.

#### Things we explicitly do NOT need
- TPM, smartcard, canokey, U2F (no modern Win9x applicability).
- USB redirection, Braille APIs (no target usage).
- Replication / colo proxy / multi-process QEMU (single-VM scope).
- SPICE / DBus display.
- VirtFS (we use 9pfs or shared-folder remap, not Plan 9 file system pass-through).
- All the "expensive" compression backends (`bzip2`, `lzfse`, `lzo`,
  `snappy`, `zstd`) — we don't need them for Win9x disk images.
- FUSE, RBD, iSCSI, NFS, SSH block backends.
- `/dev/qemu-vduse` style vduse paths (PostmarketOS phone targets, etc.).
- Crypto accelerator plugins (`qpl`, `uadk`, `qatzip`).

### 3.3 Build outputs

`make` builds:

- `qemu-system-i386` — the 32-bit host binary. **Primary target for Win9x.**
  Win9x is x86-only. Don't bother with x86_64 unless you want to test
  64-bit OSes in the same binary.
- `qemu-system-x86_64` — the 64-bit host binary. Same i440FX machine, but
  with 64-bit host perspective. Useful for PCIe-passthrough experiments.
- `qemu-img`, `qemu-io`, `qemu-nbd` — disk-image utilities.
- `qemu98-manager` — the standalone VM Manager GUI (GTK4/Vala). Built when
  `--build-manager` meson option is enabled (auto by default if Vala and
  GTK4 are available).

`make install` drops all binaries into `${prefix}/bin/`.

### 3.4 Persistence

`./configure` writes `build/config.status`. Re-running with `--recheck`
reproduces the exact same configuration. **Don't delete `config.status`.**

### 3.5 Validation step

Before pressing `make -j$(nproc)`, run `./configure` alone — it prints a
summary of detected libraries and any missing ones. Most failures at this
step are missing `-dev` packages (e.g., `libasound2-dev`, `libpulse-dev`,
`libpipewire-0.3-dev`, `libslirp-dev`, `libpixman-1-dev`, `libsdl2-dev`,
`libgtk-3-dev` on Debian/Ubuntu).

---

## 4. Architecture

### 4.1 Decision

**Decision: Keep `qemu` existing code as unmodified as possible, add new file and config options as needed
and eventually add external projects in the `subprojects/` directory.

### 4.2 Component Map

The project now comprises three self-contained trees:

| Tree           | Language    | Purpose                                    | Location                |
|----------------|-------------|--------------------------------------------|-------------------------|
| QEMU core      | C           | Modified QEMU with Win9x patches           | Repo root (in-tree)     |
| `guest-tools/` | C/MASM/NSIS | Win9x guest-side DLL shims, VxD, installer | Repo root (out-of-tree) |
| `manager/`     | Vala → C    | QEMU98 Manager GTK4 desktop GUI            | Repo root (out-of-tree) |

Each tree has its own build system (meson for QEMU + manager, custom Makefile 
or MinGW cross for guest-tools), its own versioning, and its own test suite.
The coupling points are:

- **Manager ↔ QEMU:** QMP over Unix sockets (JSON-RPC, versioned protocol).
- **Manager ↔ guest-tools:** Indirect — the manager spawns the QEMU binary 
  that the guest tools talk to. No direct ABI.
- **QEMU ↔ guest-tools:** The hypercall ABI (ring-3 DLL → VxD → MMIO → QEMU).
  Versioned via `HYP_ABI_VERSION`.

Full architecture of the manager is documented in `VM_MANAGER.md`.

---

## 5. Feature Implementation Roadmap

### 5.0 Tier 0 — VM Manager (parallel track, can start anytime after Tier 1)

The QEMU98 Manager is a standalone GTK4/Vala application. It depends only on
the QEMU CLI and QMP protocol, both of which are stable. It can be developed
in parallel with the QEMU-side features.

Full architecture: `VM_MANAGER.md`.

#### 5.0.1 Manager Phase 1 — Skeleton
- Meson build integration, GtkApplication, main window, menu bar.
- ConfigStore: JSON config read/write with schema v1.

#### 5.0.2 Manager Phase 2 — VM Lifecycle
- ProcessManager: CLI builder, `GLib.Subprocess` spawn, SIGCHLD monitor.
- QmpClient: Unix socket connect, greeting, command dispatch, event stream.
- VmController: State machine (stopped→running→paused→stopped).

#### 5.0.3 Manager Phase 3 — Configuration UI
- VM creation wizard (GtkAssistant).
- Tabbed VM config editor (General, Devices, Storage, Network tabs).
- Disk image creation wizard (wraps `qemu-img`).

#### 5.0.4 Manager Phase 4 — Runtime Operations
- Live CD/floppy media panel with CUE/BIN support.
- Snapshot manager (take/restore/delete, chain visualization).

#### 5.0.5 Manager Phase 5 — Polish
- `.desktop` file, app icon, keyboard shortcuts.
- Error handling, integration tests.

### 5.1 Tier 1 — Easy, do first

#### 5.1.1 CUE/BIN block driver  ✅ IMPLEMENTED

> **Status:** Complete — available as of first build.

A read-only block format driver (`block/cue.c`) that parses `.cue` sheet
files and exposes the referenced `.bin` file as 2048-byte CD data sectors.

**Supported modes:**
| CUE Mode       | Raw sector size | Data offset | Description                                |
|----------------|-----------------|-------------|--------------------------------------------|
| `MODE1/2352`   | 2352 bytes      | 16          | Standard CD-ROM data (sync+hdr+data+ECC)   |
| `MODE2/2352`   | 2352 bytes      | 24          | CD-ROM XA Form 1 (sync+hdr+subhdr+data)    |
| `MODE1/2048`   | 2048 bytes      | 0           | Sectors already 2048 bytes, no extra bytes |

**Features:**
- INDEX 00 (pregap) support — virtual image starts at pregap, not track start
- Multi-track CUE files — first data track is used, audio tracks skipped
- Validation: invalid timestamps, INDEX 00 > INDEX 01, and missing INDEX 01
  all produce clear error messages
- `.cue` extension auto-detection via `bdrv_probe` — `-f cue` is optional

**Usage — mount a CUE/BIN image as CD-ROM:**
```bash
qemu-system-i386 -cdrom game.cue
# or:
qemu-system-i386 -drive file=game.cue,format=cue,media=cdrom,readonly=on
```

**qemu-img / qemu-io support:**
```bash
qemu-img info -f cue game.cue
qemu-img convert -f cue -O raw game.cue game.iso
qemu-io -r -f cue -c "read 0 2048" game.cue
```

**Files modified:**
| File                           | Change                                     |
|--------------------------------|--------------------------------------------|
| `block/cue.c`                  | New file — CUE/BIN block driver (~330 LOC) |
| `block/meson.build`            | Added `cue.c` to `block_ss` sources        |
| `tests/qemu-iotests/315`       | New test — 9 test cases covering all modes |
| `tests/qemu-iotests/315.out`   | Expected output for test 315               |
| `tests/qemu-iotests/check`     | Added `'cue'` to `format_list`             |

#### 5.1.2 Nearest-neighbor scaler ✅ IMPLEMENTED

> **Status:** Complete — available as of second build.

A user-controllable texture scaling filter that, by default, uses
nearest-neighbor pixel-perfect scaling for low-resolution Win9x guests.
The scaling runs entirely on the host GPU via OpenGL, freeing up CPU
resources for the actual virtualization work. Aspect ratio is enforced
via integer scaling (largest whole-number multiplier that fits the host
window) with letterboxing/pillarboxing for the remainder.

**Why:** Win9x guests run at 4:3 resolutions like 640×480 or 320×240. On
modern 16:9 displays (1920×1080, 2560×1440) we want crisp, pixel-perfect
scaling rather than bilinear blur. This is critical for retro games that
use small sprites and require sharp pixel edges.

**Features:**
- **Nearest-neighbor as default** — sharp pixels, integer multipliers.
- **Bilinear opt-in** — smooth interpolation at fractional scales, useful
  for modern high-resolution guests (or any case where smooth scaling is
  preferred).
- **Integer-pixel viewport** — each host pixel maps to exactly N×N guest
  pixels (N integer), preventing "pixel swimming" artifacts at fractional
  scales.
- **Aspect-ratio preserving** — fullscreen mode letterboxes/pillarboxes the
  remainder using `MIN(scale_x, scale_y)` so 4:3 guests display correctly
  on 16:9 hosts.
- **GPU accelerated** — runs on the host GPU via the OpenGL texture
  filter and viewport sizing.
- **Two independent orthogonal options**:
  - `scale=fractional|integer` — controls whether fullscreen fills the
    window exactly (fractional, default) or uses whole-number multipliers
    with letterboxing (integer).
  - `filter=nearest|linear` — controls the GL texture filter: crisp pixel
    edges (nearest, default) or smooth bilinear interpolation (linear).
- **User toggleable at CLI** — no recompile needed.
- **Runtime toggles**:
  - `Ctrl+Alt+S` — toggle scaling mode (integer ↔ fractional)
  - `Ctrl+Alt+N` — toggle filtering mode (nearest ↔ linear)
  - GTK View menu: "Integer Scaling" and "Nearest-Neighbor Filtering"
    checkboxes.

**Files modified:**

| File                               | Change                                                                                                                                                                                                                                                                                                                                                                                               |
|------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `qapi/ui.json`                     | New `ScaleMode` enum (`fractional`/`integer`) and `FilterMode` enum (`nearest`/`linear`); `*scale-mode` and `*filter` fields on `DisplayGTK` and `DisplaySDL`                                                                                                                                                                                                                                        |
| `include/ui/console.h`             | Updated prototypes of `surface_gl_create_texture()`, `surface_gl_setup_viewport()`, and `surface_gl_update_texture_filter()`                                                                                                                                                                                                                                                                         |                                                                                                                                                                                                                                                                             |
| `include/ui/gtk.h`                 | Added `bool scale_integer` and `bool filter_nearest` to `VirtualGfxConsole`; added `scale_mode_item` and `filter_mode_item` to `GtkDisplayState` for independent runtime menus                                                                                                                                                                                                                       |
| `include/ui/sdl2.h`                | Added `bool scale_integer` and `bool filter_nearest` to `struct sdl2_console`                                                                                                                                                                                                                                                                                                                        |
| `ui/console-gl.c`                  | `surface_gl_create_texture()` now takes `bool nearest` filter parameter; `surface_gl_setup_viewport()` now takes `bool integer_scale` and selects integer-ratio or float-ratio sizing accordingly; new `surface_gl_update_texture_filter()` updates GL texture filter on existing texture at runtime (GL_NEAREST ↔ GL_LINEAR)                                                                        |
| `include/ui/egl-helpers.h`         | Added `bool nearest` parameter to `egl_fb_blit()` for scanout/dmabuf filter control                                                                                                                                                                                                                                                                                                                  |
| `ui/egl-helpers.c`                 | `egl_fb_blit()` now uses `nearest ? GL_NEAREST : GL_LINEAR` instead of hardcoded `GL_LINEAR` (fixes DMABUF scanout path ignoring filter mode)                                                                                                                                                                                                                                                        |
| `ui/gtk.c`                         | `gd_vc_gfx_init()` parses `scale-mode` and `filter` options independently; `gd_update_scale()` floors scale when `scale_integer` is true; `gd_menu_scale_mode()` / `gd_accel_scale_mode()` (`Ctrl+Alt+S`) and `gd_menu_filter_mode()` / `gd_accel_filter_mode()` (`Ctrl+Alt+N`) provide independent runtime toggles via checkable menu items; `gd_change_page()` disables both items on non-GFX tabs |
| `ui/gtk-gl-area.c`, `ui/gtk-egl.c` | `surface_gl_setup_viewport()` uses `scale_integer`; `surface_gl_create_texture()`, `surface_gl_update_texture_filter()`, and `glBlitFramebuffer` use `filter_nearest`; `gd_egl_scanout_flush()` passes `vc->gfx.filter_nearest` to `egl_fb_blit()`                                                                                                                                                   |
| `ui/sdl2.c`                        | Parses `scale-mode` and `filter` independently in `sdl2_display_init()`; `handle_keydown()` catches `SDL_SCANCODE_S` (toggle `scale_integer`) and `SDL_SCANCODE_N` (toggle `filter_nearest`) at runtime, each triggering `sdl2_redraw()`                                                                                                                                                             |
| `ui/egl-headless.c`                | Passes `false` to `egl_fb_blit()` (headless EGL has no filter concept, backward compatible — preserves GL_LINEAR behavior)                                                                                                                                                                                                                                                                           |
| `ui/spice-display.c`               | Passes `false` to `egl_fb_blit()` (SPICE has no filter concept, backward compatible — preserves GL_LINEAR behavior)                                                                                                                                                                                                                                                                                  |

**Why integer scale + nearest-neighbor?** Using nearest-neighbor
filtering at fractional scales (e.g. 2.25x) looks visibly bad because
some output columns are 2 pixels wide while others are 3 pixels wide,
producing uneven, "wavy" pixel borders. Forcing integer scales via
`floor(MIN(ww/fbw, wh/fbh))` guarantees every guest pixel maps to
exactly the same number of host pixels, producing crisp grid-aligned
edges.

**Usage — independent scale and filter options:**
```bash
# Default: fractional scaling + nearest-neighbor filter
qemu-system-i386 -display sdl,gl=on

# Integer scaling with crisp pixel edges (classic retro look)
qemu-system-i386 -display sdl,scale-mode=integer,filter=nearest,gl=on

# Fill window with smooth bilinear interpolation
qemu-system-i386 -display sdl,scale-mode=fractional,filter=linear,gl=on

# Same options work for the GTK backend
qemu-system-i386 -display gtk,scale-mode=integer,filter=nearest,gl=on
qemu-system-i386 -display gtk,scale-mode=fractional,filter=linear,gl=on

# Runtime shortcuts:
#   Ctrl+Alt+S  → toggle scale mode (integer ↔ fractional)
#   Ctrl+Alt+N  → toggle filter mode (nearest ↔ linear)

# Defaults applied:
#   - Caps amplified with 3:2 letterboxing/pillarboxing
#   - 640×480 → 1280×960 stretches with hard pixel edges (4:3 preserved)
#   - 320×240 → 1920×1440 (single big pixel up-scaled 6×)
#   - On 1920×1080 host: 4:3 guest centers as 1280×960 (scaled X-only to integer 2)
```

**Verification:**
```bash
cd build
./qemu-system-i386 --version                                         # QEMU 11.0.50
./qemu-system-i386 -display help                                     # lists 'gtk' and 'sdl' w/ options
./qemu-system-i386 -display gtk,scale-mode=integer,filter=linear,gl=on ... # mixed modes
./qemu-system-i386 -display gtk,scale-mode=integer,filter=nearest,gl=on ...  # classic retro

# At runtime (both backends):
#   Ctrl+Alt+S  → toggle scale mode (integer ↔ fractional)
#   Ctrl+Alt+N  → toggle filter mode (nearest ↔ linear)
#   GTK: View → "Integer Scaling" and "Nearest-Neighbor Filtering" checkboxes
```

- The SDL backend supports these option only with gl=on
- The GTK backend supports the nearest neighbor filter only when gl=on but scaling works regardless of the gl option being on or absent

### 5.2 Tier 2 — Medium scope

#### 5.2.1 Hypercall backdoor PCI device ✅ IMPLEMENTED

> **Status:** Complete — available as of T2.1 build. MSI interrupt support added in T2.2.

A PCI device that provides a 64K MMIO BAR through which a Win9x guest VxD
can issue hypercalls to the QEMU host. The guest populates arguments in
BAR0 and writes the doorbell (offset 0x0004) to trigger dispatch to
registered QEMU-side handlers.

**PCI identity:** vendor 0x1234 (QEMU), device 0xbeef, class `PCI_CLASS_OTHERS`

**BAR0 layout (64 KiB):**

| Offset   | Size       | Register       | Access | Description                                                  |
|----------|------------|----------------|--------|--------------------------------------------------------------|
| `0x0000` | 4 bytes    | `DW0`          | RW     | op[15:0] \| len[31:16]                                       |
| `0x0004` | 4 bytes    | `DW1`          | RW     | arg_count \| flags \| abi_version — **write rings doorbell** |
| `0x0008` | 256 bytes  | `args[0..31]`  | RW     | 32 × 64-bit hypercall arguments                              |
| `0x0108` | 4 bytes    | `guest_signal` | RW     | Guest→host signal mask                                       |
| `0x010C` | 4 bytes    | `host_signal`  | RO     | Host→guest signal mask                                       |
| `0x0200` | 8 bytes    | `fence`        | RO     | 64-bit monotonic completion counter                          |
| `0x0208` | 3072 bytes | `log_ring[96]` | —      | Reserved for future (96×32B entries)                         |
| `0x1000` | 48 KiB     | DMA heap       | —      | Guest-controlled (not managed by dev)                        |

**Features:**
- **Two-step doorbell:** guest writes DW0 (op + len), then DW1 (args + flags) to ring
- **Handler registry:** QEMU modules register for op code ranges via `hypback_register_handler()`
- **Fence completion:** 64-bit atomic counter incremented by handlers; guest polls via MMIO read
- **Sub-8-byte access:** argument region supports 4-byte and 8-byte read/write with proper masking
- **Signal masks:** bidirectional signaling between guest and future host-side services
- **ABI versioning:** DW1 byte 0 carries `HYP_ABI_VERSION` (currently 1)
- **MSI interrupt support:** device fires MSI after handler completion for event-based guest notification (T2.2); falls back to fence polling if MSI unavailable
- **PCI_INTERRUPT_PIN = 1** for INTx fallback when MSI not available on machine type

**Usage:**
```bash
qemu-system-i386 -device hypback,id=hbe0
# Inside guest: lspci -nn shows 1234:beef "Class 00ff: 1234:beef"
# Guest VxD maps BAR0 (64K MMIO), writes hypercall packets, polls fence
```

**Handler registration API (for QEMU-side consumers):**
```c
#include "hw/misc/hypback.h"

/* Handler: called when guest writes doorbell with op in [start, end] */
void my_handler(void *opaque, uint32_t op, uint32_t arg_count,
                const uint64_t *args, uint64_t *fence);

/* Register during module init */
hypback_register_handler(HYP_GLIDE_TEX_UPLOAD, HYP_GLIDE_BUFFER_SWAP,
                         my_handler, my_state);
```

**Files modified:**

| File                         | Change                                                                     |
|------------------------------|----------------------------------------------------------------------------|
| `include/hw/misc/hypback.h`  | New file — hypercall ABI, op codes, handler registration API               |
| `hw/misc/hypback.c`          | New file — PCI device, MMIO BAR, doorbell dispatch, MSI support (~280 LOC) |
| `hw/misc/meson.build`        | Added `hypback.c` under `CONFIG_HYPBACK`                                   |
| `hw/misc/Kconfig`            | Added `HYPBACK` config entry (`default y if PCI_DEVICES`)                  |
| `tests/qtest/hypback-test.c` | New file — qtest for MMIO read/write verification                          |
| `tests/qtest/meson.build`    | Added `hypback-test` to i386/x86_64 test suites                            |

**Pattern reference:** `hw/misc/edu.c` (single BAR MMIO doorbell)

**Future consumers of this device:**
- §5.2.2 (Voodoo3): registers for `HYP_GLIDE_*` op codes (0x1001–0x1004) to receive 3D commands
- §5.3.1 (guest-tools/vxd/): guest-side VxD is the *sole writer* of the doorbell
- §5.4 (renderer): registers for `HYP_GLIDE_*` / `HYP_D3D_*` to do host-side GPU rendering
- §5.6.1 (clipboard): registers for `HYP_CLIPBOARD_*` (0x4001–0x4002)
- §5.6.2 (shared folders): registers for `HYP_FS_*` (0x3001–0x3005)
- Audio: registers for `HYP_AUDIO_*` (0x5001–0x5002)

Full reference: `qemu98-docs/HYPBACK.md`

##### 5.2.1a Guest tools ISO build system ✅ IMPLEMENTED

> **Status:** Complete — available as of T2.2 build.

A cross-compilation build script (`guest-tools/build-guest-tools.sh`) that
produces a distributable ISO (`guest-tools.iso`) containing Win9x guest-side
components. The ISO is attached via `-cdrom` and autoruns the VxD build on
the guest.

**Host-side build requirements:**
- `i686-w64-mingw32-gcc` or llvm-mingw clang — cross-compiles the Win32 test
  harness (`TEST_HYP.EXE`)
- `xorriso` or `genisoimage` — ISO creation

**ISO contents:**

| Component         | Path                         | Description                                  |
|-------------------|------------------------------|----------------------------------------------|
| Test harness      | `/TEST_HYP.EXE`              | Pre-built Win32 smoke test (PE32 executable) |
| Autorun           | `/AUTORUN.INF`               | Launches `BUILD_VXD.BAT` on disc insertion   |
| VxD source        | `/VXD/hypback.asm`           | Ring-0 VxD driver (~1050 LOC MASM)           |
| VxD linker defs   | `/VXD/hypback.def`           | LE executable exports                        |
| VxD build script  | `/VXD/BUILD_VXD.BAT`         | Guest-side auto-detect, compile, install     |
| VxD instructions  | `/VXD/README_VXD.TXT`        | Detailed guest-side build docs               |
| Bundled assembler | `/VXD/tools/uasm/UASM32.EXE` | UASM 2.57 (JWasm successor, MASM-compatible) |

**Guest-side VxD compilation workflow:**
1. Attach ISO as CD-ROM → autoruns `BUILD_VXD.BAT`
2. Script detects bundled UASM (or system DDK/MASM/Visual Studio)
3. Compiles `HYPBACK.VXD` using real DDK headers on guest
4. Copies to `C:\WINDOWS\SYSTEM\VMM32\`
5. User adds `device=HYPBACK.VXD` to `SYSTEM.INI [386Enh]`
6. Reboot guest → run `TEST_HYP.EXE` to verify

**Why guest-side compilation:** The Microsoft DDK segment model requires
MASM 6.11+ with real `vmm.inc`/`vpicd.inc`/`shell.inc` headers. JWasm on
Linux cannot handle the DDK-specific segment macros, so the VxD must be
compiled on a real Windows host or inside the Win9x guest. The ISO bundles
UASM (open-source MASM-compatible assembler) so the guest only needs DDK
headers — not a full assembler toolchain.

**Integration tests:**

| Test                                        | What it verifies                                                                          |
|---------------------------------------------|-------------------------------------------------------------------------------------------|
| `tests/guest-tools/test-guest-tools-iso.sh` | ISO content: file listing, volume label, xorriso verification                             |
| `tests/guest-tools/test-vm-cdrom.sh`        | VM boot: QEMU starts with ISO as CD-ROM, SeaBIOS detects DVD/CD, qemu-img validates image |

**Files:**

| File                                        | Purpose                                      |
|---------------------------------------------|----------------------------------------------|
| `guest-tools/build-guest-tools.sh`          | Cross-build script producing guest-tools.iso |
| `guest-tools/vxd/BUILD_VXD.BAT`             | Guest-side VxD build & install script        |
| `guest-tools/vxd/README_VXD.TXT`            | Guest-side compilation instructions          |
| `guest-tools/vxd/tools/uasm/`               | Bundled UASM assembler (JWasm successor)     |
| `tests/guest-tools/test-guest-tools-iso.sh` | Integration test for ISO build               |
| `tests/guest-tools/test-vm-cdrom.sh`        | VM-level test: boots QEMU with ISO as CD-ROM |
| `tests/guest-tools/meson.build`             | Meson wiring for guest-tools test suite      |
| `guest-tools/README.md`                     | Guest tools overview & install guide         |
| `qemu98-docs/HYPBACK.md`                    | Full hypback device documentation            |
| `qemu98-docs/BUILD.md`                      | §3.1, §4.9–4.10 — build & verify guest tools |

#### 5.2.2 Voodoo3 PCI device (register-level)

Pattern reference: `hw/display/vmware_vga.c` (12k LOC, register-level PCI
VGA-ish device) and the historical `qemu-3dfx` patch series by kjliew.

This is essentially a re-implementation of the 3dfx Banshee/Voodoo3 PCI
config space + MMIO registers + AGP/PCI DMA tag list (for texture upload
commands). ~1500 LOC target. The register layout already lives in the
public spec; the upstream Mesa3D `xf86-video-glide` source has the
reference register list.

```c
/* hw/display/voodoo3.c — register envelope sketch */
#define VOODOO3_VENDOR_ID  0x121a
#define VOODOO3_DEVICE_ID_BANSHEE 0x3d07  /* actually 0x121a+0x0003 in spec */
#define VOODOO3_DEVICE_ID_VOODOO3 0x3d09

#define VOODOO3_REG_STATUS     0x0000
#define VOODOO3_REG_FB_BASE    0x0010
#define VOODOO3_REG_AGP_CMD    0x0040
#define VOODOO3_REG_2D_DST     0x0200
#define VOODOO3_REG_3D_DST     0x0300
/* …all ~600 regs… */

static uint64_t voodoo3_mmio_read(void *opaque, hwaddr addr, unsigned size);
static void     voodoo3_mmio_write(void *opaque, hwaddr addr,
                                    uint64_t data, unsigned size);
```

Registration lives in `hw/display/Kconfig` (new `config VOODOO3` entry)
and `hw/display/meson.build` (one-line `system_ss.add(...)`).

Note: this device only exists if you actually need register-level
compatibility (running real Win9x 3dfx drivers unmodified). For the
paravirt hypercall path (§5.2.1 alone is enough; the guest DLL/VDD just
talks to the backdoor device instead).

### 5.3 Tier 3a — Guest tools stack (paravirt side)

#### 5.3.1 Component layout

`guest-tools/` tree (see §4.2):

| Component       | Reality check                                                                                                                                                                                                                                                                                                                                                                                                               |
|-----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `vxd/`          | ~1050 LOC MASM source. Owns the BAR0 mapping, sets up MMU pages, dispatches IRQ-style completion events. Detects MSI via PCI capability walk for event-based completion; falls back to fence polling. **Critical path**, everything else depends on this. Compilation is guest-side (DDK headers required — not cross-compilable on Linux). The ISO bundles UASM 2.57 at `vxd/tools/uasm/` for guests without an assembler. |
| `glide3x-shim/` | Replacement `glide3x.dll` and `glide2x.dll` that intercepts API calls and forwards them to the VxD. Reference implementations: `nGlide`, `dgVoodoo`, `qemu-3dfx`. Build with MinGW cross-compiler.                                                                                                                                                                                                                          |
| `ddraw-shim/`   | Replacement `ddraw.dll` for DDraw-only games that don't use D3D. Smaller scope than D3D-shim.                                                                                                                                                                                                                                                                                                                               |
| `d3d-shim/`     | **Deferred.** See §7.5 — direct port of `d7vk` is not viable on Win9x. We will likely partner with Mesa9x instead.                                                                                                                                                                                                                                                                                                          |
| `lib9p/`        | Win9x client for the 9P protocol (used by `-virtfs` or `-fsdev local`). Replacement for plan9port FUSE shims. Reference: 9p-for-win32 / 9p-virtio existing partial implementations.                                                                                                                                                                                                                                         |
| `installer/`    | NSIS or Inno Setup script that bundles everything for end users. Registers the DLL shims in SYSTEM.INI or via the registry (90s style).                                                                                                                                                                                                                                                                                     |

#### 5.3.2 The hypercall protocol

The MMIO BAR write layout: a single ABI queue with shared doorbell.
MSI interrupts are supported for event-based completion notification;
fence polling remains as fallback when MSI is unavailable.

```
+----------------+ 0x0000 : header.dw0 (op | len)
| HYP_DOORBELL   | 0x0004 : header.dw1 (arg_count | flags)
+----------------+ 0x0008 : arg[0].lo
| HYP_ARG_REGION | 0x000C : arg[0].hi
| (32 args × 8B) | 0x0010 : arg[1].lo  … etc …
+----------------+ 0x0108 : guest_signal_mask (in)
| HYP_STATUS     | 0x010C : host_signal_mask (out)
+----------------+ 0x0200 : completion.fence_lo
| (fence / log)  | 0x0204 : completion.fence_hi
|                | 0x0208 : log_ring[256] (32-byte entries)
+----------------+ 0x1000 : start of guest-controlled DMA heap
```

Where `op` covers the union:

```
HYP_GLIDE_TEX_UPLOAD       0x1001
HYP_GLIDE_TEX_SETPALETTE   0x1002
HYP_GLIDE_BUFFER_SWAP      0x1003
HYP_GLIDE_VERTEX_SUBMIT    0x1004
HYP_D3D_TEX_UPLOAD         0x2001
HYP_D3D_DRAW_PRIM          0x2002
HYP_D3D_PRESENT            0x2003
HYP_FS_OPEN                0x3001
HYP_FS_READ                0x3002
HYP_FS_WRITE               0x3003
HYP_FS_CLOSE               0x3004
HYP_FS_READDIR             0x3005
HYP_CLIPBOARD_OUT          0x4001
HYP_CLIPBOARD_IN           0x4002
HYP_AUDIO_PLAY             0x5001
HYP_AUDIO_MIDI             0x5002
```

Each guest subsystem picks a `op` range and registers its own QEMU host
handler. The VxD on the guest side is the *single* writer of `HYP_DOORBELL`;
DLLs in ring-3 go through the VxD via standard IOCTL, not by direct MMIO.

### 5.4 Tier 3b — Host-side renderer (Glide → Vulkan/OpenGL)

Lives in patches `0005-glide-host-renderer-vulkan` and `0006-glide-host-renderer-opengl-fallback`.

**Architecture:** A new optional module emitted at QEMU build time called
`hw/display/voodoo_renderer.c` (or similar). The QEMU-emulated Voodoo3
device, instead of writing into a host RAM framebuffer, calls into the
renderer to produce a Vulkan texture / OpenGL texture corresponding to
the current Glide front buffer.

When vulkan renderer chosen:
```c
static void voodoo3_present(Voodoo3State *s) {
    VkCommandBuffer cmd = renderer_acquire_cmd_buffer(s->renderer);
    /* upload s->texture_handle to a host VkImage */
    renderer_submit_present(s->renderer, cmd, s->vk_image);
}
```

OpenGL fallback does the same with a single texture upload + present.

The Vulkan path is the production target; OpenGL is for hosts without a
Vulkan ICD (rare on x86 desktops; common on Asahi/Apple).

### 5.5 Tier 3c — D3D paravirt (deferred)

D3D 5/6/7 → host Vulkan. **Realistically deferred** because:

- `d7vk` is Win32-only — its entire ABI assumes NT `PE`-format sections,
  NT-process threading, Win32k syscall surfaces for DDI. Win9x has none
  of that. We can't just `wine`-port it; we'd fork it.
- Realistic alternative: **partial integration with Mesa9x**. Mesa9x is
  the upstream Mesa fork that builds natively on Win9x. If we get it to
  call into the VxD from its WGL/D3D wrappers, we get D3D5/6 coverage
  "for free." D3D7 still requires hand-written translation.

**Plan:** partner with Mesa9x upstream when stable enough. Until then,
ship DDraw-only games and the Glide path. D3D7 is a v2 feature.

### 5.6 Tier 4 (optional, deferred) — Shared clipboard & 9P shared folders

#### 5.6.1 Clipboard

Upstream QEMU's `-serial` tunneling gives us bidirectional text already
for free if the Win9x side just runs `intercept.com` or `win95term`
against a null modem. The hypercall path (HYP_CLIPBOARD_OUT / IN) is
useful if you want it without the null-modem workaround, but it is
**not required** for v1.

Decision for v1: **use `-serial` tunnel, ship HYP_CLIPBOARD as v2.**

#### 5.6.2 Shared folders (9P)

Win9x's lack of virtio means we either:
- (a) write a Win9x 9P client (`lib9p` in `guest-tools/`), or
- (b) write a custom server (NBD or custom MMIO) and a Win9x client that
  speaks that.

(a) is more standard but harder (Win9x has limited TCP/IP stack diversity
in 1995 era; later Win98SE installable networking helps). (b) is smaller
scope.

Decision: **punt to v2**, focus on floppy/CD only for v1 storage. Win9x
games' shared-folder use cases are rare in 1995–2001 releases.

---

## 6. Components We Reuse from Upstream

These are *not* customization targets — QEMU already provides them and
they work. The Win9x-side driver (when needed) is the only new code.

### 6.1 Already-working-for-free

| Win9x feature                  | Upstream path                            | Patch needed on QEMU? |
|--------------------------------|------------------------------------------|-----------------------|
| Hypervisor (Linux)             | `--enable-kvm`                           | A: no                 |
| Hypervisor (Windows)           | `--enable-whpx`                          | A: no                 |
| i440FX PC                      | `hw/i386/pc_piix.c`                      | A: no                 |
| SeaBIOS / OVMF                 | `pc-bios/`                               | A: no                 |
| VGA / SVGA / VESA              | `hw/display/vga.c`                       | A: no                 |
| SB16 / SB Pro / ESS            | `hw/audio/sb16.c`, `es1370.c`            | A: no                 |
| AC97 / Intel HDA               | `hw/audio/ac97.c`, `intel-hda.c`         | A: no                 |
| OPL3 FM synthesis              | `hw/audio/adlib.c`, `fmopl.c`            | A: no                 |
| MIDI via SoundFonts            | room of `fluidsynth` external linkage    | A: no (build only)    |
| CD/DVD via IDE/SCSI            | `hw/ide/`, `hw/scsi/`, `block/cdrom.c`   | A: no                 |
| Floppy via FDC                 | `hw/block/fdc.c`, `hw/isa/isa-superio.c` | A: no                 |
| Hard disk (raw/QCOW2/VHD)      | `block/qcow2.c`, `block/vdi.c`           | A: no                 |
| Serial-port tunnel / clipboard | `-serial` mechanism                      | A: no                 |
| Mouse grab/release             | `-display` GTK/SDL                       | A: no                 |
| Host networking (slirp)        | `--enable-slirp`                         | A: no                 |

### 6.2 Things we'd customize QEMU-side for, considered and rejected

| Candidate                                                     | Reason rejected                                                                                                                                                                                                                                                                    |
|---------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **virtio-gpu 3D for Glide/D3D**                               | Win9x has zero virtio support. Even with `d7vk`-style rehost, the kernel driver layer is missing. We need a real PCI device, not virtio.                                                                                                                                           |
| **virtio-snd for audio**                                      | SB16 is already supported by real Win9x drivers (PAS16, CT1350). Has 25 years of game compatibility. Reinventing this with virtio-snd risks regressions for hundreds of games.                                                                                                     |
| **virglrenderer / rutabaga-gfx**                              | These accelerate *Linux* DRM renderers (mesa virgl, fuchsia, virtgpu). Win9x games won't go through this path.                                                                                                                                                                     |
| **Custom Voodoo3 register-level emulator** (without paravirt) | Workable (kjliew's qemu-3dfx proves it), but allocated-chat-no-stdio approach loses quality for the small additional effort of going through our paravirt hypercall. The in-tree register-level version is still planned (§5.2.2) for guests that *don't* install our guest tools. |
| **QEMU's existing nearest-scaler "integer mode"**             | Already exposed via `vc->gfx.scale_x/y`. Patch in §5.1.2 just changes the *default* from GL_LINEAR to GL_NEAREST.                                                                                                                                                                  |

### 6.3 What we add to QEMU

Patches:

```
0001-cue-bin-block-driver                — block/cue.c (T1)  ✅ IMPLEMENTED
0002-nearest-scaler                      — ui/console-gl.c (T1/T2) ✅ IMPLEMENTED
0003-hypercall-backdoor-pci              — hw/misc/hypback.c (T2.1) ✅ IMPLEMENTED
0003a-hypback-msi-support                — MSI interrupt support (T2.2) ✅ IMPLEMENTED
0003b-guest-tools-iso-build              — guest-tools.iso + VxD build kit (T2.2) ✅ IMPLEMENTED
0004-voodoo3-pci-device                  — hw/display/voodoo3.c (T2)
0005-glide-host-renderer-vulkan          — hw/display/voodoo_renderer.c (T3)
0006-glide-host-renderer-opengl-fallback — same file, fallback path (T3)
`manager/`                               — QEMU98 Manager GTK4/Vala GUI (T0)
```

`guest-tools/` and `manager/` are independent of QEMU versions and have their
own release cadence.

---

## 7. Win9x Guest Stack — Detailed Plan

### 7.1 Why DLL shims not kernel-only

Win9x games from 1995–2001 use one of:

| API surface            | Where it lives                                                      | Shim scheme                                                                              |
|------------------------|---------------------------------------------------------------------|------------------------------------------------------------------------------------------|
| Glide3x                | `glide3x.dll`, `glide2x.dll`                                        | Replace these files in `C:\WINDOWS\SYSTEM\` (or in the game's folder with search order). |
| DirectDraw             | `ddraw.dll`                                                         | Same. Game loads `ddraw.dll`, gets our shim, our shim forwards to VxD for hypercalls.    |
| Direct3D 5/6/7         | `d3d.dll`, `d3dim.dll` (D3D5), `d3d6.dll` (D3D6), `d3d7.dll` (D3D7) | Same.                                                                                    |
| VBE linear framebuffer | Game's own VESA wrapper                                             | No shim needed; game writes to VGA MMIO/VRAM directly. QEMU's VGA device catches it.     |
| WinG                   | `wing32.dll`                                                        | Tiny, just forwards to GDI; skip for v1.                                                 |

The DLL shim pattern is identical to what **dgVoodoo** and **nGlide** have shipped since 2002, so the prior art is solid.

### 7.2 Why a VxD

Win9x ring-0 architecture is VxD (Virtual xDevice). The VxD:

- Owns the MMIO mapping for the HYP_DOORBELL BAR.
- Provides an exported interface (named service) for ring-3 DLLs.
- Sets up DMA-shared pages (the guest-controlled DMA heap at 0x1000
  offset in the BAR) and tells QEMU via HYP_SETUP.
- Handles the IRQ completion path from QEMU's side (currently simulated;
  QEMU doesn't actually raise an IRQ — it just anoints the doorbell,
  ring-3 polls for completion, or the VxD schedules an event).

VxD for Windows 9x **only**: works on 95, 95 OSR2, 98, 98SE, ME. We do not
target WinME (last version) for stable VxD support; we don't target
WinNT4 or Win2k (different VM, different driver format).

> Important: a Win98 SE VxD ≥ version 4.10.2222 ≥ 1999 ¾ ; that's the
> bar. Anything older than 95 OSR2 lacks the relevant protection model.

### 7.3 Hypcall ABI Versioning

To keep QEMU and Win9x tools decoupled:

```
#define HYP_ABI_VERSION  1
```

First feature byte in the doorbell header is the ABI version. Mismatch
yields a VxD-side error + ring-3 fallback to upstream sine qua non
behaviour (the game doesn't crash, it just loses hardware acceleration).

Once we ship v1, never bump without a graceful fallback path.

### 7.4 Win9x-specific risks

- **Cache coherence:** Win9x is *not* NT. There is no `KeFlushIoBuffers`
  equivalent. The ring-3 → ring-0 transition itself triggers cache flush
  on older x86. Count on it, don't try to be clever.
- **No preemption at ring-0:** A buggy VxD will hang the kernel. Be
  defensive in VxD code.
- **VxD load order:** Explicitly declare `VxD = "StaticVxD"` in
  `SYSTEM.INI` so we load before Microsoft's `*PNP0410` chain and can
  grab ports early. (Pattern: similar to `MTRR` VxD ordering.)
- **Installer privilege:** Standard users from 1995 era didn't have
  admin. The NSIS installer must request admin elevation on Win98SE+
  via the LUA shim.

### 7.5 D3D: the unfinished road

We do not have a v1 plan for D3D5/6/7 paravirt beyond:

> "We ship glide3x + ddraw-only for v1. We attempt Mesa9x partnership
> for v2 D3D5/6. D3D7 remains an open R&D line."

Documenting this as "deferred" is honest and avoids committing to
something that won't happen.

---

## 8. Action Items (Prioritized)

In rough order of when to tackle them. Each item has a tier (§5) and
an estimate of self-contained scope.

### Now
- [x] **Set up repo skeleton** (1 hour)
- [x] **Clone QEMU source** to a specific upstream tag (whichever is convenient — pick recent stable; not a 130k-behind master). (15 min)
- [x] **Run `./configure`** (§3.1) to confirm dev libs are present on host. (30 min)
- [x] **Make and run** `qemu-system-i386 -M pc -cdrom ...` to confirm baseline build works. (1 hour)

### Week 1–2 — Tier 1
- [x] **T1.1**: implement CUE/BIN block driver (§5.1.1). Add test under `tests/qemu-iotests/`. (1–2 days)
- [x] **T1.2**: implement nearest-neighbor scaler patch (§5.1.2) (½ day)
  - Independent runtime toggles for scale mode (`-display gtk,scale-mode=fractional|integer,filter=nearest|linear`) and filter mode. 
  - At runtime `Ctrl+Alt+S` toggles integer ↔ fractional scaling; `Ctrl+Alt+N` toggles nearest ↔ linear filtering. Both backends supported.

### Week 2–4 — Tier 2
- [x] **T2.1**: hypback PCI device in QEMU (§5.2.1). (2 days) ✅
- [x] **T2.2a**: hypback MSI interrupt support + VxD MSI detection (§5.2.1). (1 day) ✅
- [x] **T2.2b**: Win9x VxD guest driver written in MASM (~1050 LOC, §5.3.1) ✅
- [x] **T2.2c**: Guest-tools ISO build system + integration tests (§5.2.1a) ✅
- [ ] **T2.2d**: VxD guest-side compilation verified on real Win9x guest (requires DDK) ⚠  blocked by DDK availability
  - **Planned resolution:** Boot a minimal Win98 VM with DDK installed, run an automated build script to compile `HYPBACK.VXD`, then extract the binary back to the host for inclusion in the ISO as a pre-built artifact. This eliminates the guest-side compilation requirement for end users.
- [ ] **T2.3**: Voodoo3 PCI register-level emulation (optional — only needed if shipping it without guest tools). (1 week)

### Week 4–8 — Tier 3
- [ ] **T3.1**: glide3x-shim DLL replacement in `guest-tools/glide3x-shim/`. (2 weeks)
- [ ] **T3.2**: ddraw-shim DLL replacement. (3 days)
- [ ] **T3.3**: glide3x-shim smoke test against `qemu-3dfx` (already branches of a real-World GLQuake test). Use as reference for regression. (1 week)
- [ ] **T3.4**: Vulkan host renderer. (2 weeks)

### Post-launch (v2)
- [ ] **P1**: pre-built guest tools installer (NSIS). Auto-update channel tied to ABI version.
- [ ] **P2**: shared folders via lib9p + Win9x client.
- [ ] **P3**: clipboard hypercall channel.
- [ ] **P4**: D3D5/6 path via Mesa9x.
- [ ] **P5**: 9p shared-folder client.

### Stretch goals
- [ ] **S1**: Wine-on-Win9x allowlist (games known to work).
- [ ] **S2**: Linux distro (Gentoo 9x, FreeDOS, WinME) install scripts.
- [ ] **S3**: docker-compose-style orchestration for multi-VM test runners.

### VM Manager (parallel track — see `VM_MANAGER.md` §10)
- [x] **M1**: Skeleton — meson build, GtkApplication, window, ConfigStore. (1 week) ✅
- [x] **M2**: VM Lifecycle — ProcessManager, QmpClient, VmController. (1–2 weeks) ✅
- [x] **M3**: Configuration UI — Wizard, editor, disk image helper. (2 weeks) ✅
- [ ] **M4**: Runtime Operations — Media panel, snapshot manager. (2 weeks)
- [ ] **M5**: Polish — .desktop, icons, error handling, tests. (1 week)

---

## 9. Open Questions / Deferred Decisions

These came up during discussion but we don't have a definitive answer yet.
Each should be re-visited at the indicated milestone.

| #   | Question                                                                                         | Resolution point  | Default if undecided                                     |
|-----|--------------------------------------------------------------------------------------------------|-------------------|----------------------------------------------------------|
| Q1  | Should the host renderer be Vulkan-only with OpenGL as fallback, or a runtime choice?            | T3.4              | Vulkan tier-one, OpenGL fallback.                        |
| Q2  | Should the parent repo expose `qemu-system-i386` as a Docker image?                              | Post-launch       | Build scripts yes, container story no.                   |
| Q3  | WinME support — does it work like Win98SE or has weird breakage?                                 | T2.2              | Treat as 98SE; revisit if user reports install failures. |
| Q4  | SoundFonts: static file at build time or hot-loadable?                                           | T2.2              | Hot-loadable via FluidSynth `--soundfont`.               |
| Q5  | i386-only vs i386+x86_64 binaries?                                                               | Now               | Build both; ship i386-primary.                           |
| Q6  | Should we sign guest DLLs at install time?                                                       | Post-launch       | Yes, code-signing for Win98SE+ LUA.                      |
| Q7  | Hypercall ABI level bumps backward-compatibly?                                                   | After v1 freeze   | Strictly backward compat until v3.                       |
| Q8  | Should Win9x's VESA framebuffer still go through QEMU's `vga.c`, or pass through to voodoo3 too? | T2.3              | Default yes (vga.c upstream).                            |
| Q9  | Do we need to ship our own SeaBIOS patch, e.g., for early USB?                                   | Now               | No, unless USB sticks fail to enumerate.                 |
| Q10 | What to do about `d7vk` retries of Win9x compatibility?                                          | Strictly deferred | Don't try; go Mesa9x route.                              |
| Q11 | Should the Manager embed the QEMU display window or launch it separately?                        | M1                | Launch separately (no GDK reparenting complexity).       |
| Q12 | GTK4 or GTK3 for the Manager? QEMU's built-in display uses GTK3.                                 | M1                | GTK4 — separate process, no conflict.                    |
| Q13 | Should we generate Vala bindings for QMP?                                                        | M1                | No — QMP is JSON-RPC; json-glib handles it natively.     |

---

## 10. References & Prior Art

### Upstream QEMU references
- `README.rst` — overall build.
- `configure` — flag inventory (this file's source of truth).
- `meson_options.txt` — fine-grained knobs.
- `hw/Kconfig`, `hw/display/Kconfig`, `hw/audio/Kconfig` — device selection mechanism.
- `hw/i386/pc_piix.c` — the i440FX machine.
- `block/vvfat.c`, `block/dmg.c` — block driver patterns.
- `hw/audio/sb16.c`, `hw/audio/es1370.c`, `hw/audio/adlib.c` — sound.
- `hw/display/vmware_vga.c` — register-level PCI VGA. Template for Voodoo3 (§5.2.2).
- `hw/misc/edu.c`, `hw/misc/ivshmem-pci.c` — backdoor-pci patterns.
- `ui/console-gl.c`, `ui/gtk-egl.c` — display scaler / GL surface.

### Historical forks / patches we are standing on
- **kjliew/qemu** — original "qemu-3dfx" patch, register-level Voodoo3. Reference for the §5.2.2 register-level emulator.
- **qemu-3dfx / qemu-voodoo-3** — fork branches based on kjliew's work.

### Glide / D3D / Win9x guest tooling
- **3dfx Interactive Glide3x SDK** — official public spec source.
- **Danaozhong/3dfx-Glide-API** — clean-room rehost of the Glide3 SDK headers & source. Confirmed via web research: this is the *SDK* (the C-callable glue), not a hypercall shim. We use these headers for our shim. Available at <https://github.com/Danaozhong/3dfx-Glide-API>.
- **nGlide** — small, proprietary. Glide→D3D9 wrapper. Architecturally identical to our hypercall wrapper but renders locally instead of forwarding to host. Useful pattern reference for shim design.
- **dgVoodoo** — Glide + DDraw → D3D wrapper. Open-source. **Best** open reference for what our shim's control-flow should look like.
- **OpenGlide9X** — Glide → OpenGL. Useful for OpenGL fallback paths.

### Direct3D translation
- **d7vk** — D3D7 → Vulkan. Ring-3 only, Windows (≥XP). Cannot port to Win9x directly. Mentioned in §5.5, NOT a v1 dependency.
- **Mesa9x** — Mesa3D fork that builds natively on Win9x. Most likely path to D3D5/6 coverage in our v2.

### Shared folders / 9P
- QEMU `hw/9pfs/`, `hw/virtio/virtio-9p-pci.c`, `hw/virtio/virtio-9p-device.c`.
- kernel.org 9P docs (`Documentation/filesystems/9p.rst`).
- lib9p / 9pfs libraries.

### Win9x kernel/driver-level references
- **vmdisp9x** — closest prior-art blueprint: kernel-mode video driver on Win9x exposing new surfaces into the GDI/Display apis. The architectural shape of `guest-tools/vxd/` mirrors it.
- **SoftGPU** — software-only Win9x GDI/D3D replacement; no hypercalls but instructive VxD loading patterns.
- **Mesa9x** — see above.
- Walter Oney's "Windows 95 System Programming Secrets" — VxD reference.
- Microsoft MSDN VxD DDK documentation (archived).

### VM Manager
- `VM_MANAGER.md` — Full architecture, data model, QMP protocol, build integration.
- [Vala Language Reference](https://vala.dev/)
- [GTK4 Documentation](https://docs.gtk.org/gtk4/)
- [json-glib Reference](https://gnome.pages.gitlab.gnome.org/json-glib/)
- [QEMU QMP Reference](https://www.qemu.org/docs/master/interop/qmp-spec.html)

---

## 11. Glossary

| Term                                       | Definition                                                                                                                                                                                 |
|--------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Paravirtual**                            | OS-level cooperation with the hypervisor. We expose a special device that the *guest OS knows about* and talks to deliberately, replacing an existing (but working slowly) emulation path. |
| **Hypercalls (our definition)**            | A guest-to-host control-flow that works as: DLL → VxD → MMIO poke → QEMU trap. On VMX/SVM it's a real "hypercall" instruction; on TCG it's a memory-mapped I/O exit. We use the latter.    |
| **VxD**                                    | Win9x ring-0 driver format (.VXD). Wins on Win95/98/ME only. Lost to .SYS / WDM on NT and later.                                                                                           |
| **Shim**                                   | In our parlance: a ring-3 Win9x DLL that *replaces* the system DLL of the same name and forwards calls into the VxD. e.g., `glide3x-shim.dll` registered as the system's `glide3x.dll`.    |
| **i440FX**                                 | Intel 440FX PCI chipset. Emulated by `hw/i386/pc_piix.c`. The default QEMU x86 PC machine type. Pairs with PIIX3/PIIX4 southbridge for IDE, USB, ACPI.                                     |
| **HDA**                                    | Intel High Definition Audio. Emulated by `hw/audio/intel-hda.c`. Newer-Win9x audio option. Most Win9x-era games are SB16-targeted.                                                         |
| **DMA heap**                               | A sub-region of guest physical memory and/or BAR space that both QEMU and the guest can read/write directly without VM exits.                                                              |
| **Doorbell**                               | A single MMIO register in the BAR that rings whenever the guest wants QEMU attention.                                                                                                      |
| **Fence**                                  | A 64-bit monotonic counter incremented on every host-side completion. Guest ring-0 polls it to detect when a hypercall returns.                                                            |
| **KVM**                                    | Linux kernel-mode hypervisor. QEMU talks to it via `/dev/kvm`. Auto-detected.                                                                                                              |
| **WHPX**                                   | Windows Hypervisor Platform. QEMU auto-detects on Win10/11 hosts.                                                                                                                          |
| **TCG**                                    | QEMU's "Tiny Code Generator": pure-software dynamic translation mode. Used when KVM is unavailable. Less performant than KVM/WHPX; sufficient for Win9x but slower.                        |
| **sm501**, **vmware-svga**, **virtio-gpu** | Other QEMU VGA-ish devices. We do not use any of these for our guest acceleration path; they're listed here only to disambiguate.                                                          |

---

## 12. Document Lifecycle

This file should be revisited:

- After each Tier is finished (update §8 with dates, fill in real PR links).
- When a new architectural decision is made (replace the consensus in-place
  with the new answer; mark old text with ~~strike~~ when it's instructive).
- Before each major release (audit §5.5 / §9 for stale items).

It does **not** auto-regenerate. We own it.
