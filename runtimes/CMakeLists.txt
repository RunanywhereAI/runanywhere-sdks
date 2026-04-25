# =============================================================================
# runtimes/ — top-level L1 runtime plugin directory
#
# Task T4.1.
#
# A "runtime" is the compute target an engine executes on (CPU, Apple Metal,
# Core ML, CUDA, Vulkan, QNN, …). Runtime plugins are separate from engine
# plugins (engines/) and register via the `rac_runtime_register` surface
# declared in include/rac/plugin/rac_runtime_registry.h.
#
# CPU is always built in. ORT/CoreML/Metal are adapter runtimes: they own
# shared lifecycle helpers while engines continue to own primitive-specific
# tensor marshaling.
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

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/onnxrt/CMakeLists.txt")
    add_subdirectory(onnxrt)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/coreml/CMakeLists.txt")
    add_subdirectory(coreml)
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/metal/CMakeLists.txt")
    add_subdirectory(metal)
endif()
