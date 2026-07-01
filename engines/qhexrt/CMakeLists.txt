# =============================================================================
# QHexRT Backend — RunAnywhere's PRIVATE Qualcomm Hexagon NPU runtime
#
# QHexRT runs prebuilt QNN context binaries on Snapdragon Hexagon NPUs (HTP).
# It is a closed-source, RunAnywhere-owned dependency consumed as a PREBUILT
# static archive — its source never enters this repo. This mirrors the
# engines/metalrt private-binary pattern (libmetalrt_engine.a) and the
# genie routable/shell split.
#
# Two modes:
#
#   1) Engine NOT available (default in the public repo):
#      - The prebuilt archive / header under QHEXRT_ROOT is absent, so
#        RAC_QHEXRT_ENGINE_AVAILABLE stays 0.
#      - Only the shell (rac_plugin_entry_qhexrt.cpp) compiles; it publishes a
#        not-routable, all-NULL vtable and rejects registration with
#        RAC_ERROR_BACKEND_UNAVAILABLE. No QHexRT header/lib needed. The public
#        repo links cleanly.
#
#   2) Engine IS available (internal / authorized Android builds):
#      - QHEXRT_ROOT points at the prebuilt tree:
#            $QHEXRT_ROOT/include/qhexrt/qhexrt_c.h
#            $QHEXRT_ROOT/lib/<abi>/libqhexrt_core.a
#            $QHEXRT_ROOT/lib/<abi>/libqhexrt_host.a
#        (defaults to engines/qhexrt/prebuilt/, which is gitignored).
#      - RAC_QHEXRT_ENGINE_AVAILABLE=1; qhexrt_llm_ops.cpp compiles against the
#        private header and the archive links INTO the plugin .so (no separately
#        shippable QHexRT binary; runtime symbols stay internal to the carrier).
#      - Publishes a routable vtable exposing RAC_PRIMITIVE_GENERATE_TEXT.
#
# OFF by default: the QNN runtime + NPU firmware are Android/Snapdragon-only and
# absent on CI hosts. Downstream Android builds set -DRAC_BACKEND_QHEXRT=ON
# (+ optionally -DQHEXRT_ROOT=<path>).
# =============================================================================

option(RAC_BACKEND_QHEXRT "Build QHexRT (Qualcomm Hexagon NPU) engine plugin" OFF)
if(NOT RAC_BACKEND_QHEXRT)
    return()
endif()

message(STATUS "Configuring QHexRT (Qualcomm Hexagon NPU) backend...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

get_filename_component(RAC_COMMONS_ROOT_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

# Prebuilt QHexRT tree. Default to the gitignored in-tree staging dir so an
# authorized checkout that dropped the archive there "just works".
if(NOT DEFINED QHEXRT_ROOT)
    set(QHEXRT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt")
endif()

# ABI subdir under QHEXRT_ROOT/lib (arm64-v8a is the shipped Snapdragon target).
set(_qhexrt_abi "${ANDROID_ABI}")
if(NOT _qhexrt_abi)
    set(_qhexrt_abi "arm64-v8a")
endif()

set(QHEXRT_SOURCES
    rac_plugin_entry_qhexrt.cpp
    rac_backend_qhexrt_register.cpp)
set(QHEXRT_LINK_LIBS "")
set(QHEXRT_COMPILE_DEFS RAC_QHEXRT_BUILDING)
set(QHEXRT_INCLUDE_DIRS
    ${RAC_COMMONS_ROOT_DIR}/include
    ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
    ${CMAKE_CURRENT_SOURCE_DIR}/..)  # engines/ — for engines/common/rac_engine_unavailable.h

# Discover the prebuilt archive + private header. All three must be present to
# claim the engine available; a partial tree falls back to the stub. Explicit
# paths (not find_library): the Android NDK toolchain re-roots find_library
# PATHS under the sysroot (CMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY), which would
# never see this out-of-sysroot prebuilt tree.
set(QHEXRT_CORE_LIB "${QHEXRT_ROOT}/lib/${_qhexrt_abi}/libqhexrt_core.a")
set(QHEXRT_HOST_LIB "${QHEXRT_ROOT}/lib/${_qhexrt_abi}/libqhexrt_host.a")

if(EXISTS "${QHEXRT_CORE_LIB}" AND EXISTS "${QHEXRT_HOST_LIB}" AND
   EXISTS "${QHEXRT_ROOT}/include/qhexrt/qhexrt_c.h")
    set(RAC_QHEXRT_ENGINE_AVAILABLE 1)
    message(STATUS "  QHexRT engine discovered:")
    message(STATUS "    header: ${QHEXRT_ROOT}/include/qhexrt/qhexrt_c.h")
    message(STATUS "    core:   ${QHEXRT_CORE_LIB}")
    message(STATUS "    host:   ${QHEXRT_HOST_LIB}")

    list(APPEND QHEXRT_SOURCES
        qhexrt_session.cpp
        qhexrt_llm_ops.cpp
        qhexrt_vlm_ops.cpp
        qhexrt_stt_ops.cpp
        qhexrt_tts_ops.cpp)
    list(APPEND QHEXRT_INCLUDE_DIRS "${QHEXRT_ROOT}/include")
    list(APPEND QHEXRT_COMPILE_DEFS RAC_QHEXRT_ENGINE_AVAILABLE=1)

    # core references host symbols; wrap both archives in a link group so static
    # resolution is order-independent. dl + pthread are QHexRT's own deps.
    list(APPEND QHEXRT_LINK_LIBS
        -Wl,--start-group "${QHEXRT_CORE_LIB}" "${QHEXRT_HOST_LIB}" -Wl,--end-group
        ${CMAKE_DL_LIBS})
    find_package(Threads REQUIRED)
    list(APPEND QHEXRT_LINK_LIBS Threads::Threads)
else()
    set(RAC_QHEXRT_ENGINE_AVAILABLE 0)
    list(APPEND QHEXRT_COMPILE_DEFS RAC_QHEXRT_ENGINE_AVAILABLE=0)
    message(STATUS "  QHexRT engine archive absent under QHEXRT_ROOT=${QHEXRT_ROOT}")
    message(STATUS "  -> building not-routable shell (rejects with RAC_ERROR_BACKEND_UNAVAILABLE)")
endif()

rac_add_engine_plugin(qhexrt
    TARGET_NAME         rac_backend_qhexrt
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             ${QHEXRT_SOURCES}
    LINK_LIBRARIES      ${QHEXRT_LINK_LIBS}
    INCLUDE_DIRECTORIES ${QHEXRT_INCLUDE_DIRS}
    COMPILE_DEFINITIONS ${QHEXRT_COMPILE_DEFS}
)

if(RAC_STATIC_PLUGINS)
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_qhexrt.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
    )
endif()

if(RAC_PLATFORM_ANDROID)
    target_link_libraries(rac_backend_qhexrt PRIVATE log)
    target_compile_options(rac_backend_qhexrt PRIVATE -O3 -ffunction-sections -fdata-sections)
    target_link_options(rac_backend_qhexrt PRIVATE
        -Wl,--gc-sections
        -Wl,-z,max-page-size=16384
        -Wl,-z,common-page-size=16384)
endif()

# =============================================================================
# JNI bridge (Android) — librac_backend_qhexrt_jni.so
#
# Standalone JNI carrier the Kotlin runanywhere-core-qhexrt module loads. Owns
# JNI_OnLoad; nativeRegister calls rac_backend_qhexrt_register(); nativeProbeNpu
# calls rac_npu_probe() (resolved at runtime from librac_commons.so). Builds in
# both stub and linked modes; in stub mode register reports BACKEND_UNAVAILABLE.
# =============================================================================
if(RAC_PLATFORM_ANDROID AND RAC_BUILD_SHARED AND RAC_BUILD_JNI)
    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
        set(_QHEXRT_NDK_HOST_TAG "darwin-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
        set(_QHEXRT_NDK_HOST_TAG "linux-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
        set(_QHEXRT_NDK_HOST_TAG "windows-x86_64")
    else()
        message(FATAL_ERROR "Unsupported host for QHexRT JNI bridge: ${CMAKE_HOST_SYSTEM_NAME}")
    endif()

    set(_QHEXRT_NDK_SYSROOT_INCLUDE
        "${CMAKE_ANDROID_NDK}/toolchains/llvm/prebuilt/${_QHEXRT_NDK_HOST_TAG}/sysroot/usr/include")
    if(NOT EXISTS "${_QHEXRT_NDK_SYSROOT_INCLUDE}/jni.h")
        message(FATAL_ERROR "Could not locate Android NDK JNI headers at ${_QHEXRT_NDK_SYSROOT_INCLUDE}")
    endif()

    add_library(rac_backend_qhexrt_jni SHARED jni/rac_backend_qhexrt_jni.cpp)
    target_include_directories(rac_backend_qhexrt_jni PRIVATE
        ${_QHEXRT_NDK_SYSROOT_INCLUDE}
        ${_QHEXRT_NDK_SYSROOT_INCLUDE}/android
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include)
    target_link_libraries(rac_backend_qhexrt_jni PRIVATE rac_backend_qhexrt log)
    target_compile_options(rac_backend_qhexrt_jni PRIVATE
        -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
    target_link_options(rac_backend_qhexrt_jni PRIVATE
        -Wl,--gc-sections
        -Wl,-z,max-page-size=16384
        -Wl,-z,common-page-size=16384)
endif()

message(STATUS "QHexRT Backend Configuration:")
message(STATUS "  Engine available: ${RAC_QHEXRT_ENGINE_AVAILABLE}")
message(STATUS "  Platform:         ${RAC_PLATFORM_NAME}")
