# FindRunAnywhereCorePrebuilt.cmake
# Finds pre-built runanywhere-core static libraries for use by runanywhere-commons
#
# This module sets the following variables:
#   RUNANYWHERE_CORE_PREBUILT_FOUND - True if pre-built core libraries were found
#   RUNANYWHERE_CORE_PREBUILT_LIB_DIR - Directory containing pre-built .a files
#   RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS - Include directories
#   RUNANYWHERE_CORE_BRIDGE_LIB - Path to librunanywhere_bridge.a
#   RUNANYWHERE_CORE_LLAMACPP_LIB - Path to librunanywhere_llamacpp.a
#   RUNANYWHERE_CORE_ONNX_LIB - Path to librunanywhere_onnx.a
#
# Search order:
#   1. third_party/runanywhere-core-prebuilt/ (downloaded via download-core-prebuilt.sh)
#   2. RUNANYWHERE_CORE_PREBUILT_DIR (if provided via cmake -D)
#
# Usage:
#   include(FindRunAnywhereCorePrebuilt)
#   if(RUNANYWHERE_CORE_PREBUILT_FOUND)
#       target_link_libraries(my_target PRIVATE ${RUNANYWHERE_CORE_BRIDGE_LIB})
#   endif()

# Default search path
if(NOT DEFINED RUNANYWHERE_CORE_PREBUILT_DIR)
    set(RUNANYWHERE_CORE_PREBUILT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/runanywhere-core-prebuilt")
endif()

# Normalize path
get_filename_component(RUNANYWHERE_CORE_PREBUILT_DIR "${RUNANYWHERE_CORE_PREBUILT_DIR}" ABSOLUTE)

# Check if pre-built directory exists
if(NOT EXISTS "${RUNANYWHERE_CORE_PREBUILT_DIR}")
    message(STATUS "Pre-built core directory not found: ${RUNANYWHERE_CORE_PREBUILT_DIR}")
    set(RUNANYWHERE_CORE_PREBUILT_FOUND FALSE)
    return()
endif()

# Look for libraries in platform-specific subdirectories
# Structure: third_party/runanywhere-core-prebuilt/
#   ios-arm64/
#     librunanywhere_bridge.a
#     librunanywhere_llamacpp.a
#     librunanywhere_onnx.a
#   ios-arm64_x86_64-simulator/
#     ...

# For now, we'll look for libraries in the root or in a lib/ subdirectory
set(_LIB_DIRS
    "${RUNANYWHERE_CORE_PREBUILT_DIR}/lib"
    "${RUNANYWHERE_CORE_PREBUILT_DIR}"
)

# Find bridge library (required)
set(RUNANYWHERE_CORE_BRIDGE_LIB "")
foreach(_dir ${_LIB_DIRS})
    if(EXISTS "${_dir}/librunanywhere_bridge.a")
        set(RUNANYWHERE_CORE_BRIDGE_LIB "${_dir}/librunanywhere_bridge.a")
        set(RUNANYWHERE_CORE_PREBUILT_LIB_DIR "${_dir}")
        break()
    endif()
endforeach()

if(NOT RUNANYWHERE_CORE_BRIDGE_LIB)
    message(STATUS "Pre-built core bridge library not found in ${RUNANYWHERE_CORE_PREBUILT_DIR}")
    set(RUNANYWHERE_CORE_PREBUILT_FOUND FALSE)
    return()
endif()

# Find optional backend libraries
if(EXISTS "${RUNANYWHERE_CORE_PREBUILT_LIB_DIR}/librunanywhere_llamacpp.a")
    set(RUNANYWHERE_CORE_LLAMACPP_LIB "${RUNANYWHERE_CORE_PREBUILT_LIB_DIR}/librunanywhere_llamacpp.a")
    set(RUNANYWHERE_CORE_HAS_LLAMACPP TRUE)
else()
    set(RUNANYWHERE_CORE_HAS_LLAMACPP FALSE)
endif()

if(EXISTS "${RUNANYWHERE_CORE_PREBUILT_LIB_DIR}/librunanywhere_onnx.a")
    set(RUNANYWHERE_CORE_ONNX_LIB "${RUNANYWHERE_CORE_PREBUILT_LIB_DIR}/librunanywhere_onnx.a")
    set(RUNANYWHERE_CORE_HAS_ONNX TRUE)
else()
    set(RUNANYWHERE_CORE_HAS_ONNX FALSE)
endif()

# Find include directories
set(RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS "")
if(EXISTS "${RUNANYWHERE_CORE_PREBUILT_DIR}/include")
    list(APPEND RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS "${RUNANYWHERE_CORE_PREBUILT_DIR}/include")
endif()
if(EXISTS "${RUNANYWHERE_CORE_PREBUILT_DIR}/src")
    list(APPEND RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS "${RUNANYWHERE_CORE_PREBUILT_DIR}/src")
    list(APPEND RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS "${RUNANYWHERE_CORE_PREBUILT_DIR}/src/bridge")
    list(APPEND RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS "${RUNANYWHERE_CORE_PREBUILT_DIR}/src/capabilities")
endif()

if(NOT RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS)
    message(WARNING "No include directories found in ${RUNANYWHERE_CORE_PREBUILT_DIR}")
endif()

# Success
set(RUNANYWHERE_CORE_PREBUILT_FOUND TRUE)

message(STATUS "FindRunAnywhereCorePrebuilt:")
message(STATUS "  RUNANYWHERE_CORE_PREBUILT_DIR: ${RUNANYWHERE_CORE_PREBUILT_DIR}")
message(STATUS "  RUNANYWHERE_CORE_PREBUILT_LIB_DIR: ${RUNANYWHERE_CORE_PREBUILT_LIB_DIR}")
message(STATUS "  Bridge library: ${RUNANYWHERE_CORE_BRIDGE_LIB}")
if(RUNANYWHERE_CORE_HAS_LLAMACPP)
    message(STATUS "  LlamaCPP library: ${RUNANYWHERE_CORE_LLAMACPP_LIB}")
endif()
if(RUNANYWHERE_CORE_HAS_ONNX)
    message(STATUS "  ONNX library: ${RUNANYWHERE_CORE_ONNX_LIB}")
endif()

