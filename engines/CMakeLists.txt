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
# T5.4: per-engine RAC_BACKEND_<name> options are owned by each engine's own
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

# T5.1: sherpa must come BEFORE onnx. engines/sherpa owns Sherpa-ONNX
# prebuilt discovery and publishes the GLOBAL IMPORTED target `sherpa_onnx`
# + CACHE INTERNAL flag `RAC_SHERPA_ONNX_AVAILABLE` that engines/onnx
# consumes while its Sherpa-backed STT/TTS/VAD migration (T5.1 phase 2)
# is in flight.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/sherpa/CMakeLists.txt")
    add_subdirectory(sherpa)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/onnx/CMakeLists.txt")
    add_subdirectory(onnx)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/whispercpp/CMakeLists.txt")
    add_subdirectory(whispercpp)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/whisperkit_coreml/CMakeLists.txt")
    add_subdirectory(whisperkit_coreml)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/metalrt/CMakeLists.txt")
    add_subdirectory(metalrt)
endif()

# T5.2: Qualcomm Genie / NPU LLM engine. OFF by default — requires the
# Genie SDK headers which are not in-tree. Compiles a shell plugin that
# surfaces RAC_ERROR_BACKEND_UNAVAILABLE when the SDK isn't linked in.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/genie/CMakeLists.txt")
    add_subdirectory(genie)
endif()

# T5.3: Apple CoreML diffusion engine (Stable Diffusion via MLModel).
# Apple-only — self-gates to return() on non-Apple platforms.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/diffusion-coreml/CMakeLists.txt")
    add_subdirectory(diffusion-coreml)
endif()

