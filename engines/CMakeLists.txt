# =============================================================================
# engines/ — top-level engine plugin directory
#
# GAP 06 Phase 9 — see v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md.
#
# Each subdirectory is a standalone engine plugin built via the
# rac_add_engine_plugin() helper from cmake/plugins.cmake. Compiled either
# statically into rac_commons (RAC_STATIC_PLUGINS=ON; iOS / WASM force this)
# or as a SHARED librunanywhere_<name>.so loaded via rac_registry_load_plugin()
# at runtime (default on Android / Linux / macOS / Windows).
#
# Adding a new in-tree engine:
#   1. Create engines/<name>/{CMakeLists.txt, *.cpp}.
#   2. Add `add_subdirectory(<name>)` below.
#   3. Per-engine CMakeLists is a one-liner (or two) calling
#      `rac_add_engine_plugin(<name> SOURCES ... LINK_LIBRARIES ... RUNTIMES
#      ... FORMATS ...)`.
# Out-of-tree engines: no edit here required — they live in their own repo
# and are dlopen'd by the host or static-linked via the user's build.
# =============================================================================

# Per-engine RAC_BACKEND_* options are still owned by sdk/runanywhere-commons
# until the post-Wave-B cleanup hoists them here. Today they gate which
# subdirectories we descend into.

if(RAC_BACKEND_LLAMACPP AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/llamacpp/CMakeLists.txt")
    add_subdirectory(llamacpp)
endif()

if(RAC_BACKEND_ONNX AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/onnx/CMakeLists.txt")
    add_subdirectory(onnx)
endif()

if(RAC_BACKEND_WHISPERCPP AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/whispercpp/CMakeLists.txt")
    add_subdirectory(whispercpp)
endif()

if(APPLE AND RAC_BACKEND_WHISPERKIT_COREML AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/whisperkit_coreml/CMakeLists.txt")
    add_subdirectory(whisperkit_coreml)
endif()

if(APPLE AND RAC_BACKEND_METALRT AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/metalrt/CMakeLists.txt")
    add_subdirectory(metalrt)
endif()
