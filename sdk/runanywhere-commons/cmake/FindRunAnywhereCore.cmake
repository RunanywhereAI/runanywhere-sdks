# FindRunAnywhereCore.cmake
# Finds and configures runanywhere-core for use by runanywhere-commons
#
# This module sets the following variables:
#   RUNANYWHERE_CORE_FOUND - True if runanywhere-core was found
#   RUNANYWHERE_CORE_DIR - Path to runanywhere-core root directory
#   RUNANYWHERE_CORE_INCLUDE_DIRS - Include directories
#
# Usage:
#   set(RUNANYWHERE_CORE_DIR "/path/to/runanywhere-core")
#   include(FindRunAnywhereCore)

# Use provided path or default
if(NOT DEFINED RUNANYWHERE_CORE_DIR)
    # Default path assumes commons is at sdks/sdk/runanywhere-commons
    set(RUNANYWHERE_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../runanywhere-core")
endif()

# Normalize path
get_filename_component(RUNANYWHERE_CORE_DIR "${RUNANYWHERE_CORE_DIR}" ABSOLUTE)

# Check if directory exists
if(NOT EXISTS "${RUNANYWHERE_CORE_DIR}/CMakeLists.txt")
    message(WARNING "runanywhere-core CMakeLists.txt not found at: ${RUNANYWHERE_CORE_DIR}")
    set(RUNANYWHERE_CORE_FOUND FALSE)
    return()
endif()

# Check for required files
set(_required_files
    "src/bridge/runanywhere_bridge.h"
    "src/capabilities/types.h"
    "src/capabilities/backend.h"
)

foreach(_file ${_required_files})
    if(NOT EXISTS "${RUNANYWHERE_CORE_DIR}/${_file}")
        message(WARNING "Required file not found: ${RUNANYWHERE_CORE_DIR}/${_file}")
        set(RUNANYWHERE_CORE_FOUND FALSE)
        return()
    endif()
endforeach()

# Set include directories
set(RUNANYWHERE_CORE_INCLUDE_DIRS
    "${RUNANYWHERE_CORE_DIR}/src"
    "${RUNANYWHERE_CORE_DIR}/src/bridge"
    "${RUNANYWHERE_CORE_DIR}/src/capabilities"
)

# Check for backend directories
if(EXISTS "${RUNANYWHERE_CORE_DIR}/src/backends/llamacpp")
    set(RUNANYWHERE_CORE_HAS_LLAMACPP TRUE)
    list(APPEND RUNANYWHERE_CORE_INCLUDE_DIRS "${RUNANYWHERE_CORE_DIR}/src/backends/llamacpp")
endif()

if(EXISTS "${RUNANYWHERE_CORE_DIR}/src/backends/onnx")
    set(RUNANYWHERE_CORE_HAS_ONNX TRUE)
    list(APPEND RUNANYWHERE_CORE_INCLUDE_DIRS "${RUNANYWHERE_CORE_DIR}/src/backends/onnx")
endif()

if(EXISTS "${RUNANYWHERE_CORE_DIR}/src/backends/whispercpp")
    set(RUNANYWHERE_CORE_HAS_WHISPERCPP TRUE)
    list(APPEND RUNANYWHERE_CORE_INCLUDE_DIRS "${RUNANYWHERE_CORE_DIR}/src/backends/whispercpp")
endif()

# Success
set(RUNANYWHERE_CORE_FOUND TRUE)

message(STATUS "FindRunAnywhereCore:")
message(STATUS "  RUNANYWHERE_CORE_DIR: ${RUNANYWHERE_CORE_DIR}")
message(STATUS "  Has LlamaCpp: ${RUNANYWHERE_CORE_HAS_LLAMACPP}")
message(STATUS "  Has ONNX: ${RUNANYWHERE_CORE_HAS_ONNX}")
message(STATUS "  Has WhisperCpp: ${RUNANYWHERE_CORE_HAS_WHISPERCPP}")
