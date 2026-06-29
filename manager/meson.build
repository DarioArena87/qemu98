# manager/meson.build — QEMU98 VM Manager GUI
#
# A standalone GTK4/Vala desktop application for creating and managing
# Win9x virtual machines. Communicates with QEMU via QMP over Unix
# sockets — never links against QEMU libraries.
#
# Built conditionally when --enable-vm-manager is passed to configure.

add_languages('vala', required: true)

valac = meson.get_compiler('vala')

# ---- Dependencies ----
# GTK4 >= 4.10 for ListView and modern widget APIs
# json-glib-1.0 >= 1.6 for JSON parsing (VM config files, QMP)
# gio-unix-2.0 for Unix domain socket transport (QMP)
# glib-2.0 >= 2.72 for async operations, Subprocess, etc.

gtk4_dep = dependency('gtk4', version: '>=4.10')
json_glib_dep = dependency('json-glib-1.0', version: '>=1.6')
gio_unix_dep = dependency('gio-unix-2.0')
glib_dep = dependency('glib-2.0', version: '>=2.72')

manager_deps = [
  gtk4_dep,
  json_glib_dep,
  gio_unix_dep,
  glib_dep,
]

# ---- Source files ----
# Phase 1: main entry point + config store
# Phase 2: process manager, QMP client, VM controller, UI sidebar
# Future phases will add: snapshot-manager, and more UI modules.

manager_sources = files(
  'src/main.vala',
  'src/config-store.vala',
  'src/process-manager.vala',
  'src/qmp-client.vala',
  'src/vm-controller.vala',
  'src/ui/vm-list.vala',
)

# ---- Vala compiler flags ----
vala_args = [
  '--target-glib=2.72',
  '--pkg=gtk4',
  '--pkg=json-glib-1.0',
  '--pkg=gio-unix-2.0',
]

# ---- C compiler warnings ----
# Vala-generated C code can trigger warnings that QEMU's -Werror turns
# into hard errors. These are not fixable in Vala source — they're
# artifacts of how Vala translates to C (const-correctness mismatches,
# unused generated variables, etc.). Suppress them for the manager only.
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
  dependencies: manager_deps,
  vala_args: vala_args,
  c_args: manager_c_args,
  install: true,
  install_dir: get_option('bindir'),
)

# ---- Data files ----
# .desktop file for application launcher integration
manager_desktopdir = get_option('prefix') / get_option('datadir') / 'applications'
install_data('data/qemu98-manager.desktop',
             install_dir: manager_desktopdir)

# App icons (hicolor theme)
manager_icondir = get_option('prefix') / get_option('datadir') / 'icons'
install_data('data/icons/qemu98-manager.svg',
             install_dir: manager_icondir / 'hicolor' / 'scalable' / 'apps')

summary('QEMU98 Manager', 'enabled', bool_yn: true, section: 'Win9x')
