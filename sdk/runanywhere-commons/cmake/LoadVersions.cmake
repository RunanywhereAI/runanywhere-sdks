# =============================================================================
# LoadVersions.cmake
# =============================================================================
# Reads version definitions from the VERSIONS file at the project root.
# This ensures CMake and shell scripts use the same version values.
#
# Usage:
#   include(LoadVersions)
#   # Then use: ${RAC_ONNX_VERSION_IOS}, ${RAC_SHERPA_ONNX_VERSION_IOS}, etc.
#
# All variables are also set without the RAC_ prefix for backward compatibility.
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

# =============================================================================
# Invariant: all ONNX_VERSION_* pins must match.
# Sherpa-ONNX is the sole consumer of ORT; a drift here silently breaks
# runtime symbol resolution when sherpa loads against the wrong ORT.
# =============================================================================
set(_ONNX_PINS
    "${RAC_ONNX_VERSION_IOS}"
    "${RAC_ONNX_VERSION_ANDROID}"
    "${RAC_ONNX_VERSION_MACOS}"
    "${RAC_ONNX_VERSION_LINUX}"
    "${RAC_ONNX_VERSION_WINDOWS}"
)
set(_ONNX_CANONICAL "${RAC_ONNX_VERSION_IOS}")
foreach(_pin IN LISTS _ONNX_PINS)
    if(NOT "${_pin}" STREQUAL "${_ONNX_CANONICAL}")
        message(FATAL_ERROR
            "ONNX_VERSION_* pins in VERSIONS must all match. "
            "Got: iOS=${RAC_ONNX_VERSION_IOS}, Android=${RAC_ONNX_VERSION_ANDROID}, "
            "macOS=${RAC_ONNX_VERSION_MACOS}, Linux=${RAC_ONNX_VERSION_LINUX}, "
            "Windows=${RAC_ONNX_VERSION_WINDOWS}. "
            "Sherpa-ONNX is the single ORT source of truth — bump in lock-step.")
    endif()
endforeach()
unset(_ONNX_PINS)
unset(_ONNX_CANONICAL)

# Log loaded versions
message(STATUS "Loaded versions from ${_VERSIONS_FILE}:")
message(STATUS "  Platform targets:")
message(STATUS "    IOS_DEPLOYMENT_TARGET: ${RAC_IOS_DEPLOYMENT_TARGET}")
message(STATUS "    ANDROID_MIN_SDK: ${RAC_ANDROID_MIN_SDK}")
message(STATUS "  ONNX Runtime:")
message(STATUS "    ONNX_VERSION_IOS: ${RAC_ONNX_VERSION_IOS}")
message(STATUS "    ONNX_VERSION_ANDROID: ${RAC_ONNX_VERSION_ANDROID}")
message(STATUS "    ONNX_VERSION_MACOS: ${RAC_ONNX_VERSION_MACOS}")
message(STATUS "    ONNX_VERSION_LINUX: ${RAC_ONNX_VERSION_LINUX}")
message(STATUS "    ONNX_VERSION_WINDOWS: ${RAC_ONNX_VERSION_WINDOWS}")
message(STATUS "  Sherpa-ONNX:")
message(STATUS "    SHERPA_ONNX_VERSION_IOS: ${RAC_SHERPA_ONNX_VERSION_IOS}")
message(STATUS "    SHERPA_ONNX_VERSION_ANDROID: ${RAC_SHERPA_ONNX_VERSION_ANDROID}")
message(STATUS "    SHERPA_ONNX_VERSION_MACOS: ${RAC_SHERPA_ONNX_VERSION_MACOS}")
message(STATUS "    SHERPA_ONNX_VERSION_LINUX: ${RAC_SHERPA_ONNX_VERSION_LINUX}")
message(STATUS "    SHERPA_ONNX_VERSION_WINDOWS: ${RAC_SHERPA_ONNX_VERSION_WINDOWS}")
message(STATUS "  Other:")
message(STATUS "    LLAMACPP_VERSION: ${RAC_LLAMACPP_VERSION}")
message(STATUS "    NLOHMANN_JSON_VERSION: ${RAC_NLOHMANN_JSON_VERSION}")
