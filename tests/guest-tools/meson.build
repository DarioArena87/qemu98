# tests/guest-tools/meson.build — Integration test for guest tools ISO build
#
# Verifies that when guest_tools build is enabled, the ISO is produced
# with the expected content.

if not get_option('guest_tools').allowed()
  subdir_done()
endif

# This test doesn't need to compile anything — it just verifies
# the output of the guest-tools build target exists.
# It's a soft test: skipped if tools aren't available.

test_iso = find_program('test-guest-tools-iso.sh', required: false)
test_vm = find_program('test-vm-cdrom.sh', required: false)

if test_iso.found()
  test('guest-tools-iso',
       test_iso,
       args: [
         meson.project_build_root() / 'guest-tools' / 'guest-tools.iso',
         meson.project_source_root() / 'guest-tools',
       ],
       suite: ['integration'],
       is_parallel: false,
       priority: 0,
       protocol: 'exitcode')
endif

if test_vm.found()
  test('guest-tools-vm-cdrom',
       test_vm,
       args: [
         meson.project_build_root() / 'guest-tools' / 'guest-tools.iso',
         # QEMU binary path: use the emulator from this build
         meson.project_build_root() / 'qemu-system-i386',
         '8',
       ],
       suite: ['integration', 'slow'],
       is_parallel: false,
       priority: 1,
       protocol: 'exitcode')
endif
