# =============================================================================
# COUPLING NOTE: This file references librac_commons.so + RAC headers from the
# sibling @runanywhere/core npm package via a hard-coded relative path:
#   ../../core/android/src/main/jniLibs/${ANDROID_ABI}/librac_commons.so
#   ../../core/android/src/main/jniLibs/include/
# (computed via RN_NODE_MODULES -> @runanywhere/core/android/src/main/jniLibs/).
#
# The QHexRT backend itself (librac_backend_qhexrt.so) is PRIVATE and bundled
# directly in this package's src/main/jniLibs/${ANDROID_ABI} — it is never
# downloaded from a GitHub release.
# =============================================================================
project(runanywhereqhexrt)
# Must match sdk/runanywhere-commons/VERSIONS::MIN_CMAKE_VERSION (3.24).
cmake_minimum_required(VERSION 3.24)

set(PACKAGE_NAME runanywhereqhexrt)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 20)

# =============================================================================
# 16KB Page Alignment for Android 15+ (API 35) Compliance
# =============================================================================
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384")

# Path to bundled native libraries (private QHexRT backend, arm64-v8a only)
set(JNILIB_DIR ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI})

# =============================================================================
# RABackendQHexRT - Qualcomm Hexagon NPU backend (PRIVATE, bundled, REQUIRED)
# =============================================================================
if(NOT EXISTS "${JNILIB_DIR}/librac_backend_qhexrt.so")
    message(FATAL_ERROR "[RunAnywhereQHexRT] librac_backend_qhexrt.so not found for ${ANDROID_ABI} at ${JNILIB_DIR}.\n"
                        "QHexRT ships arm64-v8a only; set reactNativeArchitectures=arm64-v8a.")
endif()

add_library(rac_backend_qhexrt SHARED IMPORTED)
set_target_properties(rac_backend_qhexrt PROPERTIES
    IMPORTED_LOCATION "${JNILIB_DIR}/librac_backend_qhexrt.so"
    IMPORTED_NO_SONAME TRUE
)
message(STATUS "[RunAnywhereQHexRT] Found RABackendQHexRT at ${JNILIB_DIR}/librac_backend_qhexrt.so")

add_library(${PACKAGE_NAME} SHARED
    src/main/cpp/cpp-adapter.cpp
    ../cpp/HybridRunAnywhereQHexRT.cpp
)

# =============================================================================
# Fix NitroModules prefab path for library modules
# =============================================================================
if(DEFINED REACT_NATIVE_NITRO_BUILD_DIR)
    set(NITRO_LIBS_DIR "${REACT_NATIVE_NITRO_BUILD_DIR}/intermediates/merged_native_libs/debug/mergeDebugNativeLibs/out/lib/${ANDROID_ABI}")
    if(EXISTS "${NITRO_LIBS_DIR}/libNitroModules.so")
        message(STATUS "[RunAnywhereQHexRT] Using NitroModules from app build: ${NITRO_LIBS_DIR}")
        add_library(react-native-nitro-modules::NitroModules SHARED IMPORTED)
        set_target_properties(react-native-nitro-modules::NitroModules PROPERTIES
            IMPORTED_LOCATION "${NITRO_LIBS_DIR}/libNitroModules.so"
        )
    endif()
endif()

# Add Nitrogen specs (this handles all React Native linking)
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/runanywhereqhexrt+autolinking.cmake)

# =============================================================================
# Include directories - RAC headers from sibling @runanywhere/core package
# =============================================================================
get_filename_component(RN_NODE_MODULES "${CMAKE_SOURCE_DIR}/../../.." ABSOLUTE)
set(CORE_INCLUDE_DIR "${RN_NODE_MODULES}/@runanywhere/core/android/src/main/jniLibs/include")
set(CORE_JNILIB_DIR "${RN_NODE_MODULES}/@runanywhere/core/android/src/main/jniLibs/${ANDROID_ABI}")

include_directories(
    "src/main/cpp"
    # Package-local hybrid headers (HybridRunAnywhereQHexRT.hpp)
    "../cpp"
    # nlohmann/json (header-only) vendored by sibling @runanywhere/core package.
    "${CMAKE_SOURCE_DIR}/../../core/cpp/third_party"
    # RAC API headers from core package
    "${CORE_INCLUDE_DIR}"
    "${CORE_INCLUDE_DIR}/rac"
    "${CORE_INCLUDE_DIR}/rac/core"
    "${CORE_INCLUDE_DIR}/rac/core/capabilities"
    "${CORE_INCLUDE_DIR}/rac/features"
    "${CORE_INCLUDE_DIR}/rac/features/llm"
    "${CORE_INCLUDE_DIR}/rac/features/stt"
    "${CORE_INCLUDE_DIR}/rac/features/tts"
    "${CORE_INCLUDE_DIR}/rac/features/vad"
    "${CORE_INCLUDE_DIR}/rac/features/vlm"
    "${CORE_INCLUDE_DIR}/rac/features/voice_agent"
    "${CORE_INCLUDE_DIR}/rac/features/platform"
    "${CORE_INCLUDE_DIR}/rac/backends"
    "${CORE_INCLUDE_DIR}/rac/infrastructure"
    "${CORE_INCLUDE_DIR}/rac/infrastructure/device"
    "${CORE_INCLUDE_DIR}/rac/infrastructure/download"
    "${CORE_INCLUDE_DIR}/rac/infrastructure/events"
    "${CORE_INCLUDE_DIR}/rac/infrastructure/model_management"
    "${CORE_INCLUDE_DIR}/rac/infrastructure/network"
    "${CORE_INCLUDE_DIR}/rac/infrastructure/storage"
    "${CORE_INCLUDE_DIR}/rac/infrastructure/telemetry"
)

# =============================================================================
# RACommons - Core SDK functionality (from @runanywhere/core package)
# =============================================================================
if(NOT EXISTS "${CORE_JNILIB_DIR}/librac_commons.so")
    message(FATAL_ERROR "[RunAnywhereQHexRT] RACommons not found at ${CORE_JNILIB_DIR}/librac_commons.so\n"
                        "Run: ./gradlew :runanywhere_core:downloadNativeLibs")
endif()

add_library(rac_commons SHARED IMPORTED)
set_target_properties(rac_commons PROPERTIES
    IMPORTED_LOCATION "${CORE_JNILIB_DIR}/librac_commons.so"
    IMPORTED_NO_SONAME TRUE
)
message(STATUS "[RunAnywhereQHexRT] Found RACommons at ${CORE_JNILIB_DIR}/librac_commons.so")

# =============================================================================
# Linking - QHexRT backend and RACommons are REQUIRED
# =============================================================================
find_library(LOG_LIB log)

target_link_libraries(
    ${PACKAGE_NAME}
    ${LOG_LIB}
    android
    c++_shared
    rac_commons
    rac_backend_qhexrt
)

# 16KB page alignment - MUST be on target for Android 15+ compliance
target_link_options(${PACKAGE_NAME} PRIVATE
    -Wl,-z,max-page-size=16384
    -Wl,-z,common-page-size=16384)
