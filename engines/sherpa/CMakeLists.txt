# =============================================================================
# Sherpa-ONNX Backend — STT / TTS / VAD via Sherpa-ONNX prebuilts
#
# GAP 06 T5.1 — split out of engines/onnx/. This directory now owns:
#   1. Per-platform Sherpa-ONNX prebuilt discovery (previously sprawled across
#      engines/onnx/CMakeLists.txt lines 52-205).
#   2. A standalone `rac_backend_sherpa` plugin artifact that exposes a
#      `"sherpa"` engine in the GAP 02 plugin registry, distinct from
#      `"onnx"`.
#   3. An IMPORTED `sherpa_onnx` GLOBAL target so `engines/onnx/` (and any
#      future consumer) can `target_link_libraries(... sherpa_onnx)` without
#      re-implementing prebuilt discovery.
#
# This CMakeLists.txt MUST be added BEFORE engines/onnx so the imported
# `sherpa_onnx` target exists when onnx's CMake runs (see engines/CMakeLists.txt).
#
# T5.1 Phase 2 follow-up: the STT/TTS/VAD implementation source still lives
# in engines/onnx/onnx_backend.cpp — the plan is to migrate those classes
# (ONNXSTT / ONNXTTS / ONNXVAD → SherpaSTT / SherpaTTS / SherpaVAD) into
# this directory and expose them as stt_ops/tts_ops/vad_ops on the
# `"sherpa"` engine vtable. Until that migration lands, the sherpa engine
# plugin registers with NULL primitive slots; the onnx engine continues
# to serve Sherpa-backed STT/TTS/VAD under its legacy name. See
# v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md for the source-migration
# plan.
# =============================================================================

option(RAC_BACKEND_SHERPA "Build Sherpa-ONNX backend (STT/TTS/VAD via Sherpa-ONNX)" ON)
if(EMSCRIPTEN)
    # WASM has no Sherpa-ONNX prebuilt. Force off.
    set(RAC_BACKEND_SHERPA OFF CACHE BOOL "" FORCE)
endif()
if(NOT RAC_BACKEND_SHERPA)
    return()
endif()

message(STATUS "Configuring Sherpa-ONNX backend...")

# =============================================================================
# Sherpa-ONNX prebuilt discovery (moved from engines/onnx/CMakeLists.txt)
# =============================================================================
# Declared GLOBAL so engines/onnx and other sibling engines can consume the
# imported target without re-running discovery logic.

set(SHERPA_ONNX_AVAILABLE OFF)
get_filename_component(RUNANYWHERE_COMMONS_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

if(RAC_PLATFORM_IOS)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_COMMONS_ROOT}/third_party/sherpa-onnx-ios")

    if(EXISTS "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework")
        message(STATUS "Found Sherpa-ONNX xcframework at: ${SHERPA_ONNX_ROOT}")
        set(SHERPA_ONNX_AVAILABLE ON)

        string(TOLOWER "${CMAKE_OSX_SYSROOT}" _sherpa_sysroot_lower)
        if(_sherpa_sysroot_lower MATCHES "simulator" OR (DEFINED IOS_PLATFORM AND IOS_PLATFORM MATCHES "SIMULATOR"))
            set(SHERPA_ARCH "ios-arm64_x86_64-simulator")
        else()
            set(SHERPA_ARCH "ios-arm64")
        endif()

        if(EXISTS "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework/${SHERPA_ARCH}/libsherpa-onnx.a")
            set(SHERPA_LIB_PATH "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework/${SHERPA_ARCH}/libsherpa-onnx.a")
        else()
            file(GLOB SHERPA_LIB_CANDIDATES "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework/${SHERPA_ARCH}/*.a")
            if(SHERPA_LIB_CANDIDATES)
                list(GET SHERPA_LIB_CANDIDATES 0 SHERPA_LIB_PATH)
            else()
                set(SHERPA_ONNX_AVAILABLE OFF)
            endif()
        endif()
        set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework/${SHERPA_ARCH}/Headers")

        if(SHERPA_ONNX_AVAILABLE AND SHERPA_LIB_PATH)
            add_library(sherpa_onnx STATIC IMPORTED GLOBAL)
            set_target_properties(sherpa_onnx PROPERTIES
                IMPORTED_LOCATION "${SHERPA_LIB_PATH}"
                INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}"
            )
        endif()
    endif()

elseif(RAC_PLATFORM_ANDROID)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_COMMONS_ROOT}/third_party/sherpa-onnx-android")

    if(EXISTS "${SHERPA_ONNX_ROOT}/jniLibs")
        set(SHERPA_ABI_DIR "${SHERPA_ONNX_ROOT}/jniLibs/${ANDROID_ABI}")

        if(EXISTS "${SHERPA_ABI_DIR}/libsherpa-onnx-c-api.so")
            set(SHERPA_ONNX_AVAILABLE ON)
            set(SHERPA_LIB_PATH "${SHERPA_ABI_DIR}/libsherpa-onnx-c-api.so")

            add_library(sherpa_onnx SHARED IMPORTED GLOBAL)
            set_target_properties(sherpa_onnx PROPERTIES IMPORTED_LOCATION "${SHERPA_LIB_PATH}")

            if(EXISTS "${SHERPA_ONNX_ROOT}/include")
                set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/include")
                set_target_properties(sherpa_onnx PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}")
            endif()
        endif()
    endif()

elseif(RAC_PLATFORM_MACOS)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_COMMONS_ROOT}/third_party/sherpa-onnx-macos")

    if(EXISTS "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.a")
        set(SHERPA_ONNX_AVAILABLE ON)
        set(SHERPA_LIB_PATH "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.a")
        set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/include")

        add_library(sherpa_onnx STATIC IMPORTED GLOBAL)
        set_target_properties(sherpa_onnx PROPERTIES
            IMPORTED_LOCATION "${SHERPA_LIB_PATH}"
            INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}"
        )

        set(SHERPA_ONNX_DEPS
            "sherpa-onnx-core" "sherpa-onnx-fst" "sherpa-onnx-fstfar"
            "sherpa-onnx-kaldifst-core" "kaldi-decoder-core" "kaldi-native-fbank-core"
            "piper_phonemize" "espeak-ng" "ucd" "cppinyin_core" "ssentencepiece_core" "kissfft-float"
        )

        foreach(dep ${SHERPA_ONNX_DEPS})
            if(EXISTS "${SHERPA_ONNX_ROOT}/lib/lib${dep}.a")
                add_library(sherpa_${dep} STATIC IMPORTED GLOBAL)
                set_target_properties(sherpa_${dep} PROPERTIES IMPORTED_LOCATION "${SHERPA_ONNX_ROOT}/lib/lib${dep}.a")
                target_link_libraries(sherpa_onnx INTERFACE sherpa_${dep})
            endif()
        endforeach()
    endif()

elseif(RAC_PLATFORM_LINUX)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_COMMONS_ROOT}/third_party/sherpa-onnx-linux")

    if(EXISTS "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.so")
        set(SHERPA_ONNX_AVAILABLE ON)
        set(SHERPA_LIB_PATH "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.so")
        set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/include")

        add_library(sherpa_onnx SHARED IMPORTED GLOBAL)
        set_target_properties(sherpa_onnx PROPERTIES
            IMPORTED_LOCATION "${SHERPA_LIB_PATH}"
            INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}"
        )

        set(SHERPA_ONNX_DEPS
            "sherpa-onnx-core" "sherpa-onnx-fst" "sherpa-onnx-fstfar"
            "sherpa-onnx-kaldifst-core" "kaldi-decoder-core" "kaldi-native-fbank-core"
            "piper_phonemize" "espeak-ng" "ucd"
        )

        foreach(dep ${SHERPA_ONNX_DEPS})
            if(EXISTS "${SHERPA_ONNX_ROOT}/lib/lib${dep}.so")
                add_library(sherpa_${dep} SHARED IMPORTED GLOBAL)
                set_target_properties(sherpa_${dep} PROPERTIES IMPORTED_LOCATION "${SHERPA_ONNX_ROOT}/lib/lib${dep}.so")
                target_link_libraries(sherpa_onnx INTERFACE sherpa_${dep})
            endif()
        endforeach()

        message(STATUS "Found Sherpa-ONNX Linux: ${SHERPA_LIB_PATH}")
    else()
        message(STATUS "Sherpa-ONNX not found. Run: ./scripts/linux/download-sherpa-onnx.sh")
    endif()

elseif(RAC_PLATFORM_WINDOWS)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_COMMONS_ROOT}/third_party/sherpa-onnx-windows")

    if(EXISTS "${SHERPA_ONNX_ROOT}/lib/sherpa-onnx-c-api.lib")
        set(SHERPA_ONNX_AVAILABLE ON)
        set(SHERPA_LIB_PATH "${SHERPA_ONNX_ROOT}/lib/sherpa-onnx-c-api.lib")
        set(SHERPA_DLL_PATH "${SHERPA_ONNX_ROOT}/bin/sherpa-onnx-c-api.dll")
        set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/include")

        add_library(sherpa_onnx SHARED IMPORTED GLOBAL)
        set_target_properties(sherpa_onnx PROPERTIES
            IMPORTED_IMPLIB "${SHERPA_LIB_PATH}"
            IMPORTED_LOCATION "${SHERPA_DLL_PATH}"
            INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}"
        )

        set(SHERPA_ONNX_DEPS
            "sherpa-onnx-core" "sherpa-onnx-fst" "sherpa-onnx-fstfar"
            "sherpa-onnx-kaldifst-core" "kaldi-decoder-core" "kaldi-native-fbank-core"
            "piper_phonemize" "espeak-ng" "ucd"
        )

        foreach(dep ${SHERPA_ONNX_DEPS})
            if(EXISTS "${SHERPA_ONNX_ROOT}/lib/${dep}.lib")
                add_library(sherpa_${dep} STATIC IMPORTED GLOBAL)
                set_target_properties(sherpa_${dep} PROPERTIES IMPORTED_LOCATION "${SHERPA_ONNX_ROOT}/lib/${dep}.lib")
                target_link_libraries(sherpa_onnx INTERFACE sherpa_${dep})
            endif()
        endforeach()

        message(STATUS "Found Sherpa-ONNX Windows: ${SHERPA_LIB_PATH}")
    else()
        message(STATUS "Sherpa-ONNX not found for Windows at ${SHERPA_ONNX_ROOT}")
    endif()
endif()

# Expose availability to sibling engines (notably engines/onnx).
set(RAC_SHERPA_ONNX_AVAILABLE ${SHERPA_ONNX_AVAILABLE} CACHE INTERNAL
    "Sherpa-ONNX prebuilt discovered (set by engines/sherpa)")
if(SHERPA_ONNX_AVAILABLE)
    set(RAC_SHERPA_ONNX_HEADER_PATH "${SHERPA_HEADER_PATH}" CACHE INTERNAL
        "Sherpa-ONNX include directory (set by engines/sherpa)")
endif()

# =============================================================================
# Sherpa Plugin Library
# =============================================================================
# Shell plugin entry. Primitive ops (stt/tts/vad) are NULL in this phase;
# phase 2 migrates the existing Sherpa-backed implementations from
# engines/onnx/onnx_backend.cpp here. The target exists so:
#   - librac_backend_sherpa.so ships as its own artifact on every platform
#     (Android / Linux / macOS / iOS / Windows);
#   - staging scripts (build-core-android.sh, build-core-xcframework.sh)
#     and downstream SDK gradle/swift packaging can pick it up as a peer
#     of librac_backend_onnx.so;
#   - the GAP 02 plugin registry gains a "sherpa" engine name that future
#     router hints can target.

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

set(SHERPA_BACKEND_SOURCES
    sherpa_backend.cpp
    rac_plugin_entry_sherpa.cpp
)

set(SHERPA_LINK_LIBS "")
set(SHERPA_COMPILE_DEFS RAC_SHERPA_BUILDING)
if(SHERPA_ONNX_AVAILABLE)
    list(APPEND SHERPA_LINK_LIBS sherpa_onnx)
    list(APPEND SHERPA_COMPILE_DEFS SHERPA_ONNX_AVAILABLE=1)
else()
    list(APPEND SHERPA_COMPILE_DEFS SHERPA_ONNX_AVAILABLE=0)
endif()

rac_add_engine_plugin(sherpa
    TARGET_NAME         rac_backend_sherpa
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             ${SHERPA_BACKEND_SOURCES}
    LINK_LIBRARIES      ${SHERPA_LINK_LIBS}
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
    COMPILE_DEFINITIONS ${SHERPA_COMPILE_DEFS}
    RUNTIMES            CPU
    FORMATS             ONNX
)

# Platform tweaks — hidden visibility handled by rac_add_engine_plugin when
# truly SHARED. Add log linkage + page alignment for Android per project
# convention (mirrors engines/whispercpp).
if(RAC_PLATFORM_ANDROID)
    target_link_libraries(rac_backend_sherpa PRIVATE log)
    target_compile_options(rac_backend_sherpa PRIVATE -O3 -ffunction-sections -fdata-sections)
    target_link_options(rac_backend_sherpa PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
endif()

message(STATUS "Sherpa Backend Configuration:")
message(STATUS "  Sherpa-ONNX:  ${SHERPA_ONNX_AVAILABLE}")
message(STATUS "  Platform:     ${RAC_PLATFORM_NAME}")
