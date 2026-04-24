# =============================================================================
# runtimes/ — top-level L1 runtime plugin directory
#
# Task T4.1 — see sdk/runanywhere-commons/docs/RUNTIME_VTABLE_DESIGN.md.
#
# A "runtime" is the compute target an engine executes on (CPU, Apple Metal,
# Core ML, CUDA, Vulkan, QNN, …). Runtime plugins are separate from engine
# plugins (engines/) and register via the `rac_runtime_register` surface
# declared in include/rac/plugin/rac_runtime_registry.h.
#
# Today only the built-in CPU runtime is wired. ORT/CoreML/Metal extraction
# from their host engines is the follow-up work described in §7 of the
# design doc; until that lands, the existing engine plugins keep their
# internal ORT/CoreML/Metal calls unchanged.
#
# Adding a new in-tree runtime:
#   1. Create runtimes/<name>/{CMakeLists.txt, rac_runtime_<name>.cpp}.
#   2. Call RAC_RUNTIME_ENTRY_DEF(<name>) + RAC_STATIC_RUNTIME_REGISTER(<name>)
#      in the .cpp.
#   3. Append the subdirectory below.
# =============================================================================

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cpu/CMakeLists.txt")
    add_subdirectory(cpu)
endif()
