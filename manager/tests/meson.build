# manager/tests/meson.build — Unit tests for the QEMU98 Manager
#
# Tests are compiled as separate executables that link against the
# manager source files they exercise. No GTK4 dependency needed for
# pure data/logic tests (only glib + json-glib).

# ---- test-config-store ----
# Round-trip test: save a config, reload, verify identity.

test_config_store = executable('test-config-store',
  [
    # Test source
    'test-config-store.vala',
    # Module under test
    meson.project_source_root() / 'manager' / 'src' / 'config-store.vala',
  ],
  dependencies: [
    dependency('json-glib-1.0', version: '>=1.6'),
    dependency('glib-2.0', version: '>=2.72'),
    dependency('gio-unix-2.0'),
  ],
  vala_args: vala_args,
  c_args: manager_c_args,
  install: false,
)

test('config-store-roundtrip',
     test_config_store,
     suite: ['manager'],
     is_parallel: true,
     protocol: 'exitcode')
