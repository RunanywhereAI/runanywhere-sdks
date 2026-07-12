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

        # CMake consumes only namespaced variables. Preserve the raw value,
        # including the GIT_TAG-style 'v' prefix some entries carry.
        set(RAC_${_KEY} "${_VALUE}" CACHE STRING "Version from VERSIONS file" FORCE)
    endif()
endforeach()

# Log loaded versions
message(STATUS "Loaded versions from ${_VERSIONS_FILE}:")
message(STATUS "  Platform targets:")
message(STATUS "    IOS_DEPLOYMENT_TARGET: ${RAC_IOS_DEPLOYMENT_TARGET}")
message(STATUS "    MACOS_DEPLOYMENT_TARGET: ${RAC_MACOS_DEPLOYMENT_TARGET}")
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
message(STATUS "  ML / inference engines:")
message(STATUS "    LLAMACPP_VERSION:    ${RAC_LLAMACPP_VERSION}")
message(STATUS "  Data / serialization:")
message(STATUS "    NLOHMANN_JSON_VERSION: ${RAC_NLOHMANN_JSON_VERSION}")
message(STATUS "    PROTOBUF_VERSION:      ${RAC_PROTOBUF_VERSION}")
message(STATUS "    ABSEIL_VERSION:        ${RAC_ABSEIL_VERSION}")
message(STATUS "  Retrieval / vector search:")
message(STATUS "    USEARCH_VERSION:     ${RAC_USEARCH_VERSION}")
message(STATUS "  Compression / archives:")
message(STATUS "    LIBARCHIVE_VERSION:  ${RAC_LIBARCHIVE_VERSION}")
message(STATUS "    ZLIB_VERSION:        ${RAC_ZLIB_VERSION}")
message(STATUS "    BZIP2_VERSION:       ${RAC_BZIP2_VERSION}")
message(STATUS "  Server / testing:")
message(STATUS "    CPPHTTPLIB_VERSION:  ${RAC_CPPHTTPLIB_VERSION}")
message(STATUS "    GOOGLETEST_VERSION:  ${RAC_GOOGLETEST_VERSION}")
message(STATUS "  Toolchain:")
message(STATUS "    NDK_VERSION:         ${RAC_NDK_VERSION}")
message(STATUS "    EMSCRIPTEN_VERSION:  ${RAC_EMSCRIPTEN_VERSION}")
message(STATUS "    NODE_VERSION:        ${RAC_NODE_VERSION}")
message(STATUS "    JAVA_VERSION:        ${RAC_JAVA_VERSION}")
message(STATUS "    CMAKE_VERSION:       ${RAC_CMAKE_VERSION}")
message(STATUS "    MIN_CMAKE_VERSION:   ${RAC_MIN_CMAKE_VERSION}")
