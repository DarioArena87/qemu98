# manager/meson.build — QEMU98 VM Manager GUI
#
# Standalone GTK4/Vala desktop application for creating and managing Win9x
# virtual machines. Built independently from the parent qemu98 repo so the
# Vala tooling isn't subject to the parent's meson subproject machinery:
#
#   cd manager
#   meson setup build
#   ninja -C build
#   ./build/qemu98-manager
#
# Communicates with QEMU exclusively via QMP over Unix sockets; never
# links against QEMU libraries.

project('qemu98-manager',
        ['c', 'vala'],
        version : '0.3.0',
        meson_version : '>=1.5.0',
        default_options : [
          'warning_level=1',
          'c_std=gnu11',
          'b_colorout=auto',
          'b_pie=true',
          'optimization=2',
        ])

# Retrieve the Vala compiler instance (project() above already declared
# vala as a language, so this resolves cleanly; meson >= 1.5 otherwise
# would emit a "missing native:" deprecation warning on add_languages).
valac = meson.get_compiler('vala')

# ---- Dependencies ----
# GTK4 >= 4.10 for ListView and modern widget APIs
# json-glib-1.0 >= 1.6 for JSON parsing (VM config files, QMP)
# gio-unix-2.0 for Unix domain socket transport (QMP)
# glib-2.0 >= 2.72 for async operations, Subprocess, etc.

gtk4_dep = dependency('gtk4', version : '>=4.10')
json_glib_dep = dependency('json-glib-1.0', version : '>=1.6')
gio_unix_dep = dependency('gio-unix-2.0')
glib_dep = dependency('glib-2.0', version : '>=2.72')

manager_deps = [
  gtk4_dep,
  json_glib_dep,
  gio_unix_dep,
  glib_dep,
]

# ---- Source files ----
# Phase 1: main entry point + config store
# Phase 2: process manager, QMP client, VM controller, UI sidebar
# Phase 3: wizard, config editor, disk image wizard
# Phase 4: snapshot manager, snapshot panel, media panel

manager_sources = files(
  'src/main.vala',
  'src/config-store.vala',
  'src/process-manager.vala',
  'src/qmp-client.vala',
  'src/vm-controller.vala',
  'src/snapshot-manager.vala',
  'src/ui/vm-list.vala',
  'src/ui/new-vm-wizard.vala',
  'src/ui/vm-config-editor.vala',
  'src/ui/disk-image-wizard.vala',
  'src/ui/snapshot-panel.vala',
  'src/ui/media-panel.vala',
)

# ---- Vala compiler flags ----
vala_args = [
  '--target-glib=2.72',
  '--pkg=gtk4',
  '--pkg=json-glib-1.0',
  '--pkg=gio-unix-2.0',
]

# ---- C compiler warnings ----
# Vala-generated C code triggers warnings that the parent QEMU build's
# -Werror would promote to hard errors. These are artifacts of Vala-to-C
# translation (const-correctness mismatches, unused generated variables,
# pointer-to-int casts), not fixable in Vala source. Suppressed here for
# the manager regardless of host build flags.
manager_c_args = [
  '-Wno-unused-variable',
  '-Wno-unused-function',
  '-Wno-unused-but-set-variable',
  '-Wno-incompatible-pointer-types',
  '-Wno-deprecated-declarations',
  '-Wno-discarded-qualifiers',
  '-Wno-pointer-to-int-cast',
]

# ---- Executable ----
executable('qemu98-manager',
  manager_sources,
  dependencies : manager_deps,
  vala_args : vala_args,
  c_args : manager_c_args,
  install : true,
  install_dir : get_option('bindir'),
)

# ---- Data files ----
manager_desktopdir = get_option('prefix') / get_option('datadir') / 'applications'
install_data('data/qemu98-manager.desktop',
             install_dir : manager_desktopdir)

manager_icondir = get_option('prefix') / get_option('datadir') / 'icons'
install_data('data/icons/qemu98-manager.svg',
             install_dir : manager_icondir / 'hicolor' / 'scalable' / 'apps')
