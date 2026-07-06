# =============================================================================
# engines/ — top-level engine plugin directory
#
# Each subdirectory is a standalone engine plugin built via the
# rac_add_engine_plugin() helper from cmake/plugins.cmake. Compiled either
# statically into rac_commons (RAC_STATIC_PLUGINS=ON; iOS / WASM force this)
# or as a SHARED librunanywhere_<name>.so loaded via rac_registry_load_plugin()
# at runtime (default on Android / Linux / macOS / Windows).
#
# Per-engine RAC_BACKEND_<name> options are owned by each engine's own
# CMakeLists.txt (option() + self-gating `return()` guard). This directory
# simply descends into each engine unconditionally; the engine's own CMake
# decides whether to proceed. `if(EXISTS ...)` guards tolerate partial trees.
#
# Adding a new in-tree engine:
#   1. Create engines/<name>/{CMakeLists.txt, *.cpp}.
#   2. Add `add_subdirectory(<name>)` below.
#   3. Per-engine CMakeLists declares its own
#        option(RAC_BACKEND_<NAME> "..." <default>)
#        if(NOT RAC_BACKEND_<NAME>) return() endif()
#      before calling rac_add_engine_plugin(...).
# Out-of-tree engines: no edit here required — they live in their own repo
# and are dlopen'd by the host or static-linked via the user's build.
# =============================================================================

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/llamacpp/CMakeLists.txt")
    add_subdirectory(llamacpp)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cloud/CMakeLists.txt")
    add_subdirectory(cloud)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/sherpa/CMakeLists.txt")
    add_subdirectory(sherpa)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/onnx/CMakeLists.txt")
    add_subdirectory(onnx)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/mlx/CMakeLists.txt")
    add_subdirectory(mlx)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/metalrt/CMakeLists.txt")
    add_subdirectory(metalrt)
endif()

# Qualcomm Genie / NPU LLM engine. OFF by default — requires the
# Genie SDK headers which are not in-tree. Compiles a shell plugin that
# surfaces RAC_ERROR_BACKEND_UNAVAILABLE when the SDK isn't linked in.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/genie/CMakeLists.txt")
    add_subdirectory(genie)
endif()

# QHexRT — RunAnywhere's PRIVATE Qualcomm Hexagon NPU runtime. OFF by default —
# consumed as a prebuilt static archive under QHEXRT_ROOT (gitignored); compiles
# a not-routable shell when the archive is absent (public repo builds clean),
# and a routable LLM (GENERATE_TEXT) engine when -DRAC_BACKEND_QHEXRT=ON and the
# archive is present on an Android build.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/qhexrt/CMakeLists.txt")
    add_subdirectory(qhexrt)
endif()

# coreml engine — Apple-only engine that runs ON Apple CoreML (serves the
# DIFFUSION modality today via MLModel). Named by the FRAMEWORK, not the
# modality, mirroring the `cloud` engine. Self-gates to return() on non-Apple
# platforms. Coexists with the runtime `coreml` (runtimes/coreml) — separate
# registry/dir/symbols.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/coreml/CMakeLists.txt")
    add_subdirectory(coreml)
endif()
