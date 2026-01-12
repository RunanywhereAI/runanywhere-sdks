# =============================================================================
# LoadVersions.cmake
# =============================================================================
# Reads version definitions from the VERSIONS file at the project root.
# This ensures CMake and shell scripts use the same version values.
#
# Usage:
#   include(LoadVersions)
#   # Then use: ${RAC_ONNX_VERSION_IOS}, ${RAC_SHERPA_ONNX_VERSION_IOS}, etc.
# =============================================================================

# Find VERSIONS file relative to this cmake module
set(_VERSIONS_FILE "${CMAKE_CURRENT_LIST_DIR}/../VERSIONS")

if(NOT EXISTS "${_VERSIONS_FILE}")
    message(FATAL_ERROR "VERSIONS file not found at ${_VERSIONS_FILE}")
endif()

# Read the file
file(READ "${_VERSIONS_FILE}" _VERSIONS_CONTENT)

# Convert to list of lines
string(REPLACE "\n" ";" _VERSIONS_LINES "${_VERSIONS_CONTENT}")

# Parse each line
foreach(_LINE IN LISTS _VERSIONS_LINES)
    # Skip empty lines and comments
    string(STRIP "${_LINE}" _LINE)
    if("${_LINE}" STREQUAL "" OR "${_LINE}" MATCHES "^#")
        continue()
    endif()

    # Parse KEY=VALUE
    string(REGEX MATCH "^([A-Za-z_][A-Za-z0-9_]*)=(.*)$" _MATCH "${_LINE}")
    if(_MATCH)
        set(_KEY "${CMAKE_MATCH_1}")
        set(_VALUE "${CMAKE_MATCH_2}")

        # Set as CMake variable with RAC_ prefix
        set(RAC_${_KEY} "${_VALUE}" CACHE STRING "Version from VERSIONS file" FORCE)

        # Also set without prefix for backward compatibility
        set(${_KEY} "${_VALUE}" CACHE STRING "Version from VERSIONS file" FORCE)
    endif()
endforeach()

# Log loaded versions
message(STATUS "Loaded versions from ${_VERSIONS_FILE}:")
message(STATUS "  Platform targets:")
message(STATUS "    IOS_DEPLOYMENT_TARGET: ${RAC_IOS_DEPLOYMENT_TARGET}")
message(STATUS "    ANDROID_MIN_SDK: ${RAC_ANDROID_MIN_SDK}")
message(STATUS "  Dependencies:")
message(STATUS "    ONNX_VERSION_IOS: ${RAC_ONNX_VERSION_IOS}")
message(STATUS "    ONNX_VERSION_MACOS: ${RAC_ONNX_VERSION_MACOS}")
message(STATUS "    SHERPA_ONNX_VERSION_IOS: ${RAC_SHERPA_ONNX_VERSION_IOS}")
