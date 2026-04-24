# =============================================================================
# Genie Backend — Qualcomm Genie / QNN NPU LLM engine
#
# GAP 06 T5.2 — see v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md.
#
# Qualcomm Genie is a closed-source SDK that exposes an LLM inference C API
# running on Snapdragon NPUs (Hexagon DSP + HTP). Its headers
# (GenieCommon.h, GenieDialog.h, GenieLog.h, …) are not vendored in this
# repo — they ship via the Qualcomm QAIRT / QNN SDK installer. This
# directory publishes a shell plugin that:
#
#   - Compiles cleanly with or without the Genie SDK present.
#   - Registers a "genie" engine in the GAP 02 plugin registry on Android
#     arm64 hosts, gated by RAC_BACKEND_GENIE.
#   - Exposes llm_ops whose every entry point returns
#     RAC_ERROR_BACKEND_UNAVAILABLE when the SDK is absent. Phase 2 fills in
#     the real C API wiring behind #if defined(RAC_GENIE_SDK_AVAILABLE).
#
# Defaulting OFF because the SDK + NPU firmware are not available on CI
# hosts — enabling the plugin on such hosts would only surface runtime
# failures. Downstream Android builds can set -DRAC_BACKEND_GENIE=ON plus
# RAC_GENIE_SDK_ROOT=<qnn-sdk-path> to wire the real engine.
# =============================================================================

option(RAC_BACKEND_GENIE "Build Qualcomm Genie (Snapdragon NPU) LLM backend shell" OFF)
if(NOT RAC_BACKEND_GENIE)
    return()
endif()

# Only meaningful on Android (arm64-v8a is the shipped Snapdragon target).
# Linux/macOS/iOS/Windows don't have a Genie runtime; the shell still
# compiles to aid local development but registers a capability_check that
# rejects the plugin at load time on those hosts.
if(NOT RAC_PLATFORM_ANDROID AND NOT DEFINED RAC_GENIE_FORCE_BUILD)
    message(STATUS "engines/genie: non-Android host — building shell only")
endif()

message(STATUS "Configuring Genie (Qualcomm NPU) backend shell...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

set(GENIE_BACKEND_SOURCES
    genie_backend.cpp
    rac_plugin_entry_genie.cpp
)

set(GENIE_LINK_LIBS "")
set(GENIE_COMPILE_DEFS RAC_GENIE_BUILDING)
set(GENIE_INCLUDE_DIRS
    ${RAC_COMMONS_ROOT_DIR}/include
    ${RAC_COMMONS_ROOT_DIR}/include/rac/backends)

# Optional real SDK integration: when the user provides RAC_GENIE_SDK_ROOT
# and it contains the expected headers/lib, define RAC_GENIE_SDK_AVAILABLE
# so genie_backend.cpp can replace its RAC_ERROR_BACKEND_UNAVAILABLE stubs
# with real Genie C API calls. Kept conditional so CI / public builds keep
# compiling without access to Qualcomm's distribution.
if(DEFINED RAC_GENIE_SDK_ROOT AND EXISTS "${RAC_GENIE_SDK_ROOT}/include/GenieCommon.h")
    message(STATUS "  Genie SDK discovered at: ${RAC_GENIE_SDK_ROOT}")
    list(APPEND GENIE_INCLUDE_DIRS "${RAC_GENIE_SDK_ROOT}/include")
    list(APPEND GENIE_COMPILE_DEFS RAC_GENIE_SDK_AVAILABLE=1)

    # Genie dialog + logging libraries. Names differ between QAIRT versions;
    # probe common candidates and only link ones that exist on disk.
    foreach(_genie_lib Genie GenieDialog GenieLog)
        find_library(GENIE_${_genie_lib}_LIB
            NAMES ${_genie_lib}
            PATHS "${RAC_GENIE_SDK_ROOT}/lib/aarch64-android"
                  "${RAC_GENIE_SDK_ROOT}/lib/arm64-v8a"
                  "${RAC_GENIE_SDK_ROOT}/lib"
            NO_DEFAULT_PATH)
        if(GENIE_${_genie_lib}_LIB)
            list(APPEND GENIE_LINK_LIBS "${GENIE_${_genie_lib}_LIB}")
        endif()
    endforeach()
else()
    list(APPEND GENIE_COMPILE_DEFS RAC_GENIE_SDK_AVAILABLE=0)
    message(STATUS "  Genie SDK absent — shell will return RAC_ERROR_BACKEND_UNAVAILABLE")
endif()

rac_add_engine_plugin(genie
    TARGET_NAME         rac_backend_genie
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             ${GENIE_BACKEND_SOURCES}
    LINK_LIBRARIES      ${GENIE_LINK_LIBS}
    INCLUDE_DIRECTORIES ${GENIE_INCLUDE_DIRS}
    COMPILE_DEFINITIONS ${GENIE_COMPILE_DEFS}
    RUNTIMES            QNN CPU
    FORMATS             ONNX
)

if(RAC_PLATFORM_ANDROID)
    target_link_libraries(rac_backend_genie PRIVATE log)
    target_compile_options(rac_backend_genie PRIVATE -O3 -ffunction-sections -fdata-sections)
    target_link_options(rac_backend_genie PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
endif()

message(STATUS "Genie Backend Configuration:")
message(STATUS "  SDK available: ${RAC_GENIE_SDK_AVAILABLE}")
message(STATUS "  Platform:      ${RAC_PLATFORM_NAME}")
