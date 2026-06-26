# guest-tools/meson.build — Build Win9x Guest Tools ISO
#
# Detects optional build tools (JWasm, MinGW cross-compiler, ISO creator)
# and produces guest-tools.iso containing all available artifacts.
#
# The guest tools are cross-compiled Windows binaries — they don't link
# against QEMU or any host libraries. Build succeeds even with no tools
# found (produces empty ISO or skipped).

# ---- guest_tools option ----
have_guest_tools = get_option('guest_tools') \
  .disable_auto_if(not have_system) \
  .allowed()

if not have_guest_tools
  subdir_done()
endif

# ---- Probe for build tools ----
jwasm = find_program('jwasm', required: false)
mingw_cc = find_program('i686-w64-mingw32-gcc', required: false)

# Try multiple ISO creation tools
iso_tool_name = 'genisoimage'
iso_tool = find_program('genisoimage', required: false)
if not iso_tool.found()
  iso_tool = find_program('xorriso', required: false)
  if iso_tool.found()
    iso_tool_name = 'xorriso'
  endif
endif
if not iso_tool.found()
  iso_tool = find_program('mkisofs', required: false)
  if iso_tool.found()
    iso_tool_name = 'mkisofs'
  endif
endif

# ---- Summary message ----
guest_tools_summary = 'Guest tools ISO build'
if not jwasm.found() and not mingw_cc.found() and not iso_tool.found()
  summary_info = 'No build tools found (jwasm, mingw, iso tool). Install JWasm and MinGW.'
elif not jwasm.found()
  summary_info = 'JWasm not found — VxD will not be built. Install JWasm for HYPBACK.VXD.'
elif not mingw_cc.found()
  summary_info = 'MinGW cross-compiler not found — test harness will not be built.'
else
  summary_info = 'Building guest tools ISO'
endif
summary(guest_tools_summary, summary_info, bool_yn: have_guest_tools)

# ---- Build the guest tools ISO ----
# Use a shell script that handles all the tool detection and building.
# This is cleaner than trying to model cross-compilation in meson directly.

guest_tools_iso = custom_target('guest-tools.iso',
  output: 'guest-tools.iso',
  input: files(
    'vxd/hypback.asm',
    'vxd/hypback.def',
    'test/test_hypercall.c',
  ),
  command: [
    find_program('sh'),
    meson.current_source_dir() / 'build-guest-tools.sh',
    meson.current_source_dir(),
    meson.current_build_dir(),
    jwasm.found() ? jwasm.full_path() : 'jwasm',
    mingw_cc.found() ? mingw_cc.full_path() : 'i686-w64-mingw32-gcc',
    iso_tool.found() ? iso_tool.full_path() : 'genisoimage',
  ],
  build_by_default: have_guest_tools,
  console: true,
)

# Tell the user where to find the ISO
message('Guest tools ISO will be built as: ' + meson.current_build_dir() / 'guest-tools.iso')

# ---- Aliases ----
alias_target('guest-tools-iso', guest_tools_iso)
