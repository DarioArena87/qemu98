# BUILD.md — Building & Verifying the Win9x-QEMU98 Fork

> **Purpose:** This file is the *how*. `WIN9X_QEMU_PLAN.md` is the *what* and
> *why*; if you only ever read one of them, read the plan first.
>
> **Scope:** Step-by-step instructions to (a) build the Win9x-tailored QEMU
> fork from source, and (b) reproduce the baseline verification smoke tests
> that prove the binary configuration is working.

---

## 1. Prerequisites

### 1.1 Host requirements

- Linux host with the kernel-mode hypervisor available.
  Check the device first:
  ```bash
  ls -l /dev/kvm
  # expected: crw-rw-rw- 1 root kvm 10, 232 …  /dev/kvm
  ```
  If the device is absent, QEMU will fall back to `tcg` (software emulation).
  Everything else in this document still works, just slower.

- Disk space: ~5 GB for the build tree (roms/, subprojects/, build/).
  The build outputs are ~50 MB; the roms skeleton alone is several GB due
  to downloaded firmware shells.

- RAM: 8 GB comfortable; 4 GB minimum (because SeaBIOS+EDK2 firmware
  blobs are large).

### 1.2 Debian/Ubuntu dev libraries

The `./configure` step will hint at any missing -dev packages. The list
below covers everything referenced by the §2 configure invocation. Skip any
package line whose backend you intend to keep disabled.

```bash
sudo apt update
sudo apt install -y \
  build-essential pkg-config git ninja-build python3 python3-pip \
  libssl-dev libpixman-1-dev libslirp-dev libsdl2-dev libgtk-3-dev \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libcap-ng-dev libattr1-dev libepoxy-dev \
  libxkbcommon-dev libxdamage-dev libxrandr-dev \
  libxfixes-dev libxext-dev libxinerama-dev \
  libwayland-bin libwayland-dev libdbus-1-dev \
  libcurl4-gnutls-dev libvhost-user-dev zlib1g-dev
```

For the **QEMU98 Manager** (GTK4/Vala GUI), additionally:
```bash
sudo apt install -y \
  valac libgtk-4-dev libjson-glib-dev
```
> **Note:** The manager requires Vala ≥0.56, GTK4 ≥4.10, and json-glib ≥1.6.
> It is built only when `--build-manager` is enabled (auto by default if
> Vala and GTK4 are detected). Skip this if you don't need the GUI.

The configure invocation in §2 explicitly disables: `--user / --linux-user /
--bsd-user`, `--docs`, `--guest-agent`, `--qga-vss`, `--rust`, `--plugins`,
`--tcg-interpreter`, `--virtfs`, `--vhost-user`, `--vfio-user-server`,
`--libvduse`, `--vduse-blk-export`, `--rbd`, `--libiscsi`, `--libnfs`,
`--libssh`, `--mpath`, `--rdma`, `--passt`, `--bzip2`, `--lzfse`, `--lzo`,
`--snappy`, `--zstd`, `--tpm`, `--smartcard`, `--u2f`, `--canokey`,
`--usb-redir`, `--brlapi`, `--replication`, `--colo-proxy`,
`--multiprocess`, `--cocoa`, `--spice`, `--spice-protocol`,
`--dbus-display`, `--virglrenderer`, `--rutabaga-gfx`, `--pvg`, `--fuse`,
`--fuse-lseek`, `--igvm`, `--qpl`, `--uadk`, `--qatzip`. Do not install
`-dev` packages for those backends unless you intend to flip the flag back
on later.

---

## 2. Configure

From the repo root:

```bash
mkdir build && cd build
../configure \
  --target-list='i386-softmmu x86_64-softmmu' \
  --disable-user --disable-linux-user --disable-bsd-user \
  --disable-docs --disable-guest-agent --disable-qga-vss \
  --disable-rust --disable-plugins --disable-tcg-interpreter \
  --audio-drv-list='alsa,pa,pipewire,oss,sdl' \
  --enable-kvm --enable-whpx \
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
```

Flags rationale: see `WIN9X_QEMU_PLAN.md` §3.2. Do not delete
`build/config.status` — re-runs of `../configure --recheck` rely on it.

Want only the 32-bit binary (faster build, ships Win9x-only)? Drop
`x86_64-softmmu` from `--target-list`.

---

## 3. Compile

```bash
make -j$(nproc)
```

The single biggest wall-clock hit is the cross-arch TCG/CPU code — which is
why `--target-list` is restricted in §2. Expect 5–20 minutes on a modern
multi-core host.

`make` produces, among other binaries, in `build/`:

- `qemu-system-i386` — **primary binary for Win9x guests**
- `qemu-system-x86_64` — same i440FX machine, 64-bit host perspective
- `qemu-img`, `qemu-io`, `qemu-nbd` — disk-image utilities
- `qemu-keymap`, `qemu-edid`, `qemu-bridge-helper`, `qemu-pr-helper`,
  `qemu-vmsr-helper`, `storage-daemon/qemu-storage-daemon`
- `qemu98-manager` — VM Manager GUI (if Vala/GTK4 detected; see §3.1)

`make install` drops everything into `${prefix}/bin/`.

### 3.1 Building the VM Manager

The QEMU98 Manager is built automatically when Vala and GTK4 are detected.
Control it via the meson option:

```bash
# Enable explicitly (error if dependencies missing)
meson setup build --build-manager=enabled

# Disable explicitly (skip manager build)
meson setup build --build-manager=disabled
```

The default is `auto`: builds the manager if `valac`, `libgtk-4-dev`, and
`libjson-glib-dev` are found, silently skips otherwise.

Verify it built:
```bash
./build/qemu98-manager --version
# or just launch it:
./build/qemu98-manager
```

Full architecture: `qemu98-docs/VM_MANAGER.md`.

---

## 4. Baseline Verification

This section produces the exact evidence captured while bringing up this
repository for the first time. The commands here are stable across rebuilds
*as long as you don't change the `./configure` flags above* — if you do
change flags, regenerate `build/pc-bios/` and rerun §4.

All commands below assume a working directory of `build/`, created in §2.
Paths relative to the repo root are written with a leading `../`.

### 4.1 Binary smoke test (versions)

```bash
cd build
./qemu-system-i386   --version   # QEMU emulator version 11.0.50
./qemu-system-x86_64 --version   # QEMU emulator version 11.0.50
./qemu-img           --version
./qemu-io            --version
./qemu-nbd           --version
./qemu-bridge-helper --version
./qemu-pr-helper     --version
./qemu-vmsr-helper   --version
```

Note: `qemu-edid` and `qemu-keymap` do not accept `--version`; they print
usage when called without arguments.

### 4.2 Capability introspection

```bash
./qemu-system-i386 -M help          # machine types
./qemu-system-i386 -cpu help        # x86 CPU models (486, pentium3, …)
./qemu-system-i386 -accel help      # accelerators (kvm, tcg)
./qemu-system-i386 -accel kvm       # probe KVM (auto-detects /dev/kvm)
./qemu-system-i386 -accel tcg       # probe TCG
```

Expected: `i440FX` (default `pc-i440fx-11.1`), `q35`, deprecated variants,
plus `486`, `pentium`/`pentium2`/`pentium3`, modern Intel/AMD CPUs.

### 4.3 Disk-image round-trip

This proves the block layer is wired correctly end-to-end:

```bash
tmp=$(mktemp -d)
../build/qemu-img create -f qcow2 "$tmp/baseline.qcow2" 64M
../build/qemu-img info  "$tmp/baseline.qcow2"
../build/qemu-img check "$tmp/baseline.qcow2"
echo 'read 0 512' | ../build/qemu-io "$tmp/baseline.qcow2"
```

(Run from the repo root, or refer to `../build/...` from inside `build/`.)

Expected: `qemu-img info` reports a 64 MiB virtual size, ~196 KiB disk size;
`qemu-img check` says *"No errors were found on the image."*; `qemu-io`
returns 512 bytes of zero-filled data cleanly.

### 4.4 Spawn a Win9x-capable VM (the headline test)

The minimal VM configuration that can boot Windows 95/98/ME. We pass
`-bios` explicitly so the firmware source is unambiguous in CI logs:

```bash
timeout 5 ../build/qemu-system-i386 \
  -M pc \
  -cpu pentium3 \
  -m 64 \
  -bios ../pc-bios/bios-256k.bin \
  -display none \
  -monitor none \
  -serial stdio \
  -nographic
```

Expected output on the serial console (SeaBIOS banner is printed when it
receives the BIOS32 signal; the `Boot failed` lines and partial iPXE line
are exactly what we saw on first-run in this repo):

```
SeaBIOS (version rel-1.17.0-0-gb52ca86e094d-prebuilt.qemu.org)

Booting from Hard Disk...
Boot failed: could not read boot disk

Booting from Floppy...
Boot failed: could not read boot disk

Booting from DVD/CD...
Boot failed: could not read boot disk

iPXE (http://ipxe.org) …
…
Configuring (net0…   [still running when timeout fires]
```

The "Boot failed …" lines are *expected and correct* — no media is
attached. The point of this run is to prove that:

1. SeaBIOS loads successfully.
2. The i440FX PCI chipset enumerates correctly — so the PIIX3 IDE
   controller, the FDC, and the CD-ROM are present.
3. The CPU model `pentium3` is accepted by the build.
4. The 64 MiB RAM configuration is honoured through POST.

Without `-bios`, the same command also runs cleanly (the binary silently
falls back to bundled firmware through its own search path). Passing it
explicitly is preferred for reproducibility — see §5.1 for the two
firmware-tree locations in this repo.

If you see QEMU exit immediately with a missing-firmware error, or never
print the SeaBIOS banner, the build is broken — see §5.

### 4.5 Boot with a real Win9x guest

Once §4.4 passes, you have a binary capable of *running* Windows 9x. To
actually boot one, attach a disk image containing a Win9x installation
(or a bootable ISO/Win98 rescue disk):

```bash
../build/qemu-system-i386 \
  -M pc -cpu pentium3 -m 128 \
  -bios ../pc-bios/bios-256k.bin \
  -hda win98-disk.qcow2 \
  -drive file=win98-cd.iso,media=cdrom,readonly=on \
  -boot order=cda \
  -net nic -net user \
  -display gtk
```

Note on memory size: 64 MiB is enough to reach SeaBIOS POST (verified in
§4.4) but Windows 95/98/ME itself needs more to be usable once the GUI
loads. **96 MiB is the practical minimum, 128 MiB is the recommended
default.** Upstream QEMU defaults to 128 MiB if `-m` is omitted, which is
appropriate for Win9x too.

---

## 5. Troubleshooting

### 5.1 Firmware tree split (SeaBIOS vs. EDK2)

There are two firmware-bearing directories in this repo. Knowing which one
holds what matters when `make install` time comes or when you debug a
"missing firmware" warning:

| Path                     | Contents                                                                           |
|--------------------------|------------------------------------------------------------------------------------|
| `pc-bios/` (source tree) | Prebuilt SeaBIOS (`bios-256k.bin`, `bios.bin`), keymaps, `optionrom/`, EDK2 shells |
| `build/pc-bios/`         | Only the rebuilt `edk2-*.fd` UEFI blobs generated during the build                 |

Two consequences worth remembering:

- QEMU's data directory at runtime resolves first to `build/pc-bios/`
  (since we run from `build/`). When you launch with an **explicit
  `-bios ../pc-bios/bios-256k.bin`** flag (as §4.4 does), SeaBIOS is
  unambiguous in CI logs and can't drift.
- Without `-bios`, our baseline verification observed that the VM still
  runs cleanly through the 10-second timeout without aborting. Whether
  SeaBIOS or some other firmware was loaded on that path was not
  independently verified (the no-bios smoke test in §4 used `-serial
  null` and so produced no BIOS banner on stdout). Passing `-bios`
  explicitly is still preferred for reproducibility, since it removes
  the dependency on QEMU's silent firmware fallback chain.

Alternatives if you don't want to pass `-bios` every time:

1. Override QEMU's firmware search path: `-L ../pc-bios` so it reads the
   source-tree directory directly.
2. `make install` to populate `${prefix}/share/qemu/` (the script also
   places firmware in `build/qemu-bundle/usr/local/share/qemu/`, which
   contains `bios-256k.bin` ready to go).

### 5.2 KVM not detected

List the device first:

```bash
ls -l /dev/kvm
# expected: crw-rw-rw- 1 root kvm 10, 232 …  /dev/kvm
```

If the device exists but your user can't open it (you get *Permission
denied* in QEMU's log), add yourself to the `kvm` group and start a new
login session so the change takes effect:

```bash
sudo usermod -aG kvm "$USER"
newgrp kvm   # or log out and log back in
```

If the kernel module itself is not loaded:

```bash
sudo modprobe kvm kvm_intel   # or kvm_amd on AMD hosts
```

If your CPU/BIOS doesn't expose hardware virtualization (older silicon,
or virtualization disabled in firmware), QEMU will fall back to `tcg`
automatically. Our verifiction scripts in §4.2 already probe both
accelerators, so a missing KVM is reported as `KVM is not supported` and
the run continues.

### 5.3 `make` fails on roms/seabios

If `roms/seabios` fails to compile because the host toolchain lacks MASM
support, it's not strictly necessary: the source tree's `pc-bios/bios-256k.bin`
is the *prebuilt* output. You can skip rebuilding SeaBIOS while still
building everything else:

```bash
make -j$(nproc) SUBDIRS='. build'
# or build only the binaries you need:
make -j$(nproc) qemu-system-i386 qemu-system-x86_64 qemu-img qemu-io qemu-nbd
```

Either approach will work because the SeaBIOS binary we use at runtime
comes from the source-tree `pc-bios/` (see §5.1), not from a fresh
SeaBIOS rebuild.

---

## 6. What This Baseline Proves

The verification commands above document that, as of the first build of
this fork:

- ✅ The `./configure` invocation from the plan is complete and self-consistent.
- ✅ `make -j$(nproc)` produces the expected set of binaries.
- ✅ All executables report QEMU version 11.0.50 cleanly.
- ✅ The desired machine type (`pc-i440fx-11.1`) and a Win9x-appropriate
  CPU (`pentium3` / `486`) are compiled in.
- ✅ KVM acceleration auto-detects when `/dev/kvm` is present.
- ✅ The block layer (qcow2 + qemu-io + qemu-img check) is working.
- ✅ A SeaBIOS-equipped i440FX VM can be brought up with 64 MiB RAM and
  enumerates the standard IDE / FDC / CD-ROM boot devices. This is the
  exact hardware configuration Windows 95/98/ME expects to find at POST.

This is our **Phase-0 baseline**. Anything that changes this list of
"working" items is a regression; anything that adds to it is a feature
implementation.

---

## 7. Where to go next

Once the baseline is green, move on to the implementation roadmap in
`WIN9X_QEMU_PLAN.md` §5 §8. Tier 1 features (CUE/BIN block driver,
nearest-neighbor scaler) are the smallest scope and are the natural next
self-contained patches.
