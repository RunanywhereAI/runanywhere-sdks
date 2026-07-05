# Sherpa-ONNX Backend — STT / TTS / VAD via Sherpa-ONNX prebuilts
#
# Split out of engines/onnx/. This directory now owns:
#   1. Per-platform Sherpa-ONNX prebuilt discovery (previously sprawled across
#      engines/onnx/CMakeLists.txt lines 52-205).
#   2. A standalone `rac_backend_sherpa` plugin artifact that exposes a
#      `"sherpa"` engine in the plugin registry, distinct from
#      `"onnx"`.
#   3. An IMPORTED `sherpa_onnx` GLOBAL target so this engine can link
#      Sherpa-ONNX without re-implementing prebuilt discovery.
#
# The runtime source for STT/TTS/VAD and wakeword compatibility lives here;
# engines/onnx keeps only generic ONNX Runtime services and embeddings.

# TODO: WASM Sherpa unblock — exact remaining work
#
# Sherpa-ONNX does NOT publish a prebuilt static archive for WASM.
# scripts/build/wasm/vendor-sherpa-onnx.sh currently builds a
# STANDALONE Emscripten module (sherpa-onnx-wasm-nodejs.wasm, 12 MB) which is
# shipped separately at packages/onnx/wasm/sherpa/sherpa-onnx.wasm. That
# standalone module CANNOT be linked into racommons-llamacpp.wasm — it is a
# complete Emscripten executable, not a static library.
#
# To flip this engine on for EMSCRIPTEN the following vendored artifacts are
# required:
#
#   sdk/runanywhere-commons/third_party/sherpa-onnx-wasm/
#       lib/
#           libsherpa-onnx-c-api.a       (sherpa public C API)
#           libsherpa-onnx-core.a        (core kernels)
#           libkaldi-native-fbank-core.a
#           libkaldi-decoder-core.a
#           libsherpa-onnx-fst.a
#           libsherpa-onnx-fstfar.a
#           libsherpa-onnx-kaldifst-core.a
#           libpiper_phonemize.a         (TTS only)
#           libespeak-ng.a               (TTS only)
#           libucd.a                     (TTS only)
#           libkissfft-float.a
#       include/
#           sherpa-onnx/c-api/c-api.h    (published by sherpa upstream)
#
# Build recipe:
#   cd sdk/runanywhere-web-next/wasm/third_party/sherpa-onnx
#   # Modify CMakeLists to build static archive targets instead of the
#   # standalone sherpa-onnx-wasm-nodejs executable. Currently the WASM build
#   # recipes in build-wasm-simd-{asr,tts,vad,nodejs}.sh all produce a final
#   # linked module.
#   cmake -B build-wasm-static -DBUILD_SHARED_LIBS=OFF \
#         -DSHERPA_ONNX_ENABLE_WASM=ON \
#         -DSHERPA_ONNX_ENABLE_BINARY=OFF \
#         -DSHERPA_ONNX_ENABLE_C_API=ON \
#         -DCMAKE_TOOLCHAIN_FILE=$EMSCRIPTEN/cmake/Modules/Platform/Emscripten.cmake
#   cmake --build build-wasm-static --target sherpa-onnx-c-api
#   # Collect every produced libsherpa-onnx-*.a into third_party/sherpa-onnx-wasm/lib/
#
# Sherpa-ONNX transitively depends on onnxruntime (also as a static archive).
# Its own CMake pulls onnxruntime via SHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME
# OR builds its own. For WASM the pre-installed path is required — point it at
# the onnxruntime-wasm static lib vendored for engines/onnx (see sibling TODO).
#
# Emscripten-specific considerations:
#   - Static plugin registration: WASM forces RAC_STATIC_PLUGINS=ON, so
#     rac_plugin_entry_sherpa.cpp → RAC_STATIC_PLUGIN_REGISTER(sherpa) is
#     the only registration path. No dlopen. Export symbol
#     _rac_backend_sherpa_register must be kept live — add to
#     RAC_EXPORTED_FUNCTIONS in sdk/runanywhere-web-next/wasm/CMakeLists.txt.
#   - Piper TTS uses espeak-ng which has static initialization side-effects.
#     Verify the C++ static constructors survive --whole-archive equivalent
#     (Emscripten lacks -Wl,--whole-archive; use -sEXPORT_ALL=0 +
#     EXPORTED_FUNCTIONS+= the relevant symbols).
#
# Gate recipe (replace the current force-OFF):
#   set(RAC_SHERPA_WASM_RUNTIME_DIR
#       "${CMAKE_SOURCE_DIR}/third_party/sherpa-onnx-wasm")
#   if(EMSCRIPTEN AND NOT EXISTS "${RAC_SHERPA_WASM_RUNTIME_DIR}/lib/libsherpa-onnx-c-api.a")
#       set(RAC_BACKEND_SHERPA OFF CACHE BOOL "" FORCE)
#   endif()
#
# Prebuilt discovery section (lines 68-219 below) needs a new
# `elseif(RAC_PLATFORM_WASM)` branch that creates the IMPORTED targets from
# the vendored static archives above (mirroring the LINUX/MACOS branches).
option(RAC_BACKEND_SHERPA "Build Sherpa-ONNX backend (STT/TTS/VAD via Sherpa-ONNX)" ON)
# EXISTS-gated disable under Emscripten: only force OFF when vendored
# Sherpa-ONNX WASM static archives are missing. Drop
# libsherpa-onnx-c-api.a + deps under
# sdk/runanywhere-commons/third_party/sherpa-onnx-wasm/lib/ to enable.
if(EMSCRIPTEN)
    set(RAC_SHERPA_WASM_RUNTIME_DIR
        "${CMAKE_SOURCE_DIR}/third_party/sherpa-onnx-wasm")
    if(NOT EXISTS "${RAC_SHERPA_WASM_RUNTIME_DIR}/lib/libsherpa-onnx-c-api.a")
        message(STATUS "RAC_BACKEND_SHERPA: no WASM Sherpa archive at "
                       "${RAC_SHERPA_WASM_RUNTIME_DIR}/lib/libsherpa-onnx-c-api.a; "
                       "disabling Sherpa backend")
        set(RAC_BACKEND_SHERPA OFF CACHE BOOL "" FORCE)
    else()
        message(STATUS "RAC_BACKEND_SHERPA: found vendored WASM Sherpa archives; "
                       "building Sherpa backend for Emscripten")
    endif()
endif()
if(NOT RAC_BACKEND_SHERPA)
    return()
endif()

message(STATUS "Configuring Sherpa-ONNX backend...")

include(FetchContent)
include(LoadVersions)

if(NOT DEFINED NLOHMANN_JSON_VERSION)
    set(NLOHMANN_JSON_VERSION "3.11.3")
endif()

FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v${NLOHMANN_JSON_VERSION}
    GIT_SHALLOW    TRUE
)
set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
set(JSON_Install OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(nlohmann_json)

if(TARGET nlohmann_json AND RAC_PLATFORM_IOS)
    set_target_properties(nlohmann_json PROPERTIES
        CXX_STANDARD 11
        CXX_STANDARD_REQUIRED YES
        CXX_EXTENSIONS NO
    )
endif()

include(FetchONNXRuntime)

# Sherpa-ONNX prebuilt discovery (moved from engines/onnx/CMakeLists.txt)
# Declared GLOBAL so any later sibling engine can consume the imported target
# without re-running discovery logic.

set(SHERPA_ONNX_AVAILABLE OFF)
get_filename_component(RUNANYWHERE_COMMONS_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)

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
        message(STATUS "Sherpa-ONNX not found. Run: scripts/build/deps/download-sherpa-onnx.sh linux")
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

elseif(EMSCRIPTEN)
    # WASM / Emscripten: sherpa-onnx static archives vendored under
    # sdk/runanywhere-commons/third_party/sherpa-onnx-wasm/.
    # Build recipe lives in the banner at the top of this file. The guard at the
    # engine gate above short-circuits this engine when the archives are absent,
    # so reaching here implies `libsherpa-onnx-c-api.a` exists.
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_COMMONS_ROOT}/third_party/sherpa-onnx-wasm")

    if(EXISTS "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.a")
        set(SHERPA_ONNX_AVAILABLE ON)
        set(SHERPA_LIB_PATH "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.a")
        set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/include")

        add_library(sherpa_onnx STATIC IMPORTED GLOBAL)
        set_target_properties(sherpa_onnx PROPERTIES
            IMPORTED_LOCATION "${SHERPA_LIB_PATH}"
            INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}"
        )

        # STT-mandatory core. Piper/TTS deps (piper_phonemize, espeak-ng, ucd)
        # are OPTIONAL for STT-only variants — skip silently if absent.
        set(SHERPA_ONNX_DEPS
            "sherpa-onnx-core" "sherpa-onnx-fst" "sherpa-onnx-fstfar"
            "sherpa-onnx-kaldifst-core" "kaldi-decoder-core" "kaldi-native-fbank-core"
            "kissfft-float" "ssentencepiece_core"
            # Optional TTS deps (may be absent):
            "piper_phonemize" "espeak-ng" "ucd"
        )

        foreach(dep ${SHERPA_ONNX_DEPS})
            if(EXISTS "${SHERPA_ONNX_ROOT}/lib/lib${dep}.a")
                add_library(sherpa_${dep} STATIC IMPORTED GLOBAL)
                set_target_properties(sherpa_${dep} PROPERTIES
                    IMPORTED_LOCATION "${SHERPA_ONNX_ROOT}/lib/lib${dep}.a")
                target_link_libraries(sherpa_onnx INTERFACE sherpa_${dep})
            endif()
        endforeach()

        message(STATUS "Found Sherpa-ONNX WASM static archives: ${SHERPA_LIB_PATH}")
    else()
        message(STATUS "Sherpa-ONNX WASM archives not found at ${SHERPA_ONNX_ROOT}")
    endif()
endif()

# Sherpa Plugin Library
# The target ships as a peer of librac_backend_onnx and owns the
# Sherpa-backed speech primitives.
#   - librac_backend_sherpa.so ships as its own artifact on every platform
#     (Android / Linux / macOS / iOS / Windows);
#   - staging scripts (scripts/build/android.sh, scripts/build/ios-xcframework.sh)
#     and downstream SDK gradle/swift packaging can pick it up as a peer
#     of librac_backend_onnx.so;
#   - the plugin registry gains a "sherpa" engine name that future
#     router hints can target.

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)

set(SHERPA_BACKEND_SOURCES
    sherpa_backend.cpp
    rac_stt_sherpa.cpp
    rac_tts_sherpa.cpp
    rac_vad_sherpa.cpp
    rac_backend_sherpa_register.cpp
    rac_plugin_entry_sherpa.cpp
)

set(SHERPA_LINK_LIBS onnxruntime nlohmann_json::nlohmann_json)
set(SHERPA_COMPILE_DEFS RAC_ONNX_BUILDING RAC_HAS_ONNX RAC_SHERPA_SPEECH_OPS_AVAILABLE=1)
if(SHERPA_ONNX_AVAILABLE)
    list(APPEND SHERPA_LINK_LIBS sherpa_onnx)
    list(APPEND SHERPA_COMPILE_DEFS SHERPA_ONNX_AVAILABLE=1)
else()
    list(APPEND SHERPA_COMPILE_DEFS SHERPA_ONNX_AVAILABLE=0)
endif()

# Per-token confidence (ys_log_probs) is only present in the confidence-patched
# sherpa-onnx fork the Android prebuilt is built from (SHERPA_ONNX_REPO_ANDROID).
# The stock upstream prebuilt the iOS/macOS pod-archive ships (and any platform
# pinned to an unpatched release — see SHERPA_ONNX_VERSION_IOS in VERSIONS) has
# no such field on SherpaOnnxOfflineRecognizerResult. Probe the actual header so
# sherpa_backend.cpp computes the confidence cascade signal where the field
# exists and degrades to NaN ("no quality signal", which the hybrid router
# already treats as accept-primary) where it does not — keeping one source tree
# buildable against both forks.
set(SHERPA_HAS_YS_LOG_PROBS 0)
if(SHERPA_ONNX_AVAILABLE AND DEFINED SHERPA_HEADER_PATH)
    include(CheckStructHasMember)
    set(CMAKE_REQUIRED_INCLUDES "${SHERPA_HEADER_PATH}")
    check_struct_has_member(
        "struct SherpaOnnxOfflineRecognizerResult"
        ys_log_probs
        "sherpa-onnx/c-api/c-api.h"
        SHERPA_RESULT_HAS_YS_LOG_PROBS
        LANGUAGE CXX
    )
    unset(CMAKE_REQUIRED_INCLUDES)
    if(SHERPA_RESULT_HAS_YS_LOG_PROBS)
        set(SHERPA_HAS_YS_LOG_PROBS 1)
    endif()
endif()
list(APPEND SHERPA_COMPILE_DEFS SHERPA_HAS_YS_LOG_PROBS=${SHERPA_HAS_YS_LOG_PROBS})

rac_add_engine_plugin(sherpa
    TARGET_NAME         rac_backend_sherpa
    CXX_STANDARD        20
    SHARED_ONLY
    SOURCES             ${SHERPA_BACKEND_SOURCES}
    LINK_LIBRARIES      ${SHERPA_LINK_LIBS}
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
                        ${RAC_COMMONS_ROOT_DIR}/src
                        ${CMAKE_CURRENT_SOURCE_DIR}/..  # engines/ — for engines/common/*.h
    COMPILE_DEFINITIONS ${SHERPA_COMPILE_DEFS}
)

# Platform tweaks — hidden visibility handled by rac_add_engine_plugin when
# truly SHARED. Add log linkage + page alignment for Android per project
# convention (matches the other in-tree engines).
if(RAC_PLATFORM_ANDROID)
    target_link_libraries(rac_backend_sherpa PRIVATE log)
    target_compile_options(rac_backend_sherpa PRIVATE -O3 -ffunction-sections -fdata-sections)
    rac_apply_android_page_alignment(rac_backend_sherpa)
endif()

# Self-registration carrier
# Matches the llamacpp pattern: thin shim that wraps
# RAC_STATIC_PLUGIN_REGISTER(sherpa). On RAC_STATIC_PLUGINS=ON hosts
# (iOS / WASM) the ctor lands inside rac_commons and fires before main().
# On dynamic hosts the shim becomes a SHARED library whose only export is
# the entry symbol; the actual op functions live in rac_backend_sherpa.
if(RAC_STATIC_PLUGINS)
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_sherpa.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include
    )
else()
    add_library(runanywhere_sherpa SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_sherpa.cpp
    )
    set_target_properties(runanywhere_sherpa PROPERTIES
        OUTPUT_NAME           runanywhere_sherpa
        C_VISIBILITY_PRESET   hidden
        CXX_VISIBILITY_PRESET hidden
    )
    target_link_libraries(runanywhere_sherpa PUBLIC
        rac_backend_sherpa
        rac_commons
    )
    rac_apply_android_page_alignment(runanywhere_sherpa)
    install(TARGETS runanywhere_sherpa LIBRARY DESTINATION lib)
endif()

message(STATUS "Sherpa Backend Configuration:")
message(STATUS "  Sherpa-ONNX:  ${SHERPA_ONNX_AVAILABLE}")
message(STATUS "  Platform:     ${RAC_PLATFORM_NAME}")

rac_add_plugin_entry_test(test_plugin_entry_sherpa
    TEST_NAME plugin_entry_sherpa_tests
    SOURCE ${CMAKE_SOURCE_DIR}/tests/test_plugin_entry_sherpa.cpp
    LINK rac_backend_sherpa
)
