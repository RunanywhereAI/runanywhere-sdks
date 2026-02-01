# =============================================================================
# ONNX Backend - STT, TTS, VAD via ONNX Runtime and Sherpa-ONNX
# =============================================================================

message(STATUS "Configuring ONNX backend...")

# =============================================================================
# Dependencies
# =============================================================================

include(FetchContent)
include(LoadVersions)

# Fetch nlohmann_json for JSON parsing
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
FetchContent_MakeAvailable(nlohmann_json)

# =============================================================================
# ONNX Runtime
# =============================================================================

include(FetchONNXRuntime)

# =============================================================================
# Sherpa-ONNX (iOS and Android)
# =============================================================================

set(SHERPA_ONNX_AVAILABLE OFF)
get_filename_component(RUNANYWHERE_COMMONS_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

if(RAC_PLATFORM_IOS)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_COMMONS_ROOT}/third_party/sherpa-onnx-ios")

    if(EXISTS "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework")
        message(STATUS "Found Sherpa-ONNX xcframework at: ${SHERPA_ONNX_ROOT}")
        set(SHERPA_ONNX_AVAILABLE ON)

        if(CMAKE_OSX_SYSROOT MATCHES "simulator")
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
endif()

# =============================================================================
# QNN Execution Provider Support (NPU Acceleration - Qualcomm Direct)
# =============================================================================
# QNN IS COMPLETELY DISABLED FOR NNAPI TESTING
# Use NNAPI instead for NPU acceleration (vendor-agnostic)

set(RAC_QNN_AVAILABLE OFF)
set(RAC_ENABLE_QNN OFF CACHE BOOL "QNN is DISABLED for NNAPI testing" FORCE)

# ALWAYS use stubs - QNN is DISABLED
# The qnn/ directory files are NOT compiled
set(QNN_SOURCES
    qnn_stubs.cpp
)
message(STATUS "  QNN EP DISABLED - using stub implementations (NNAPI testing mode)")
message(STATUS "  NOTE: qnn/ directory sources are NOT compiled")

# =============================================================================
# NNAPI Execution Provider Support (Android Neural Networks API)
# =============================================================================
# NNAPI is Android's vendor-agnostic API for NPU/GPU/DSP acceleration.
# It works on Qualcomm, Samsung Exynos, MediaTek, and other Android devices.
# Requirements: Android 8.1+ (API 27+), optimal with API 29+ for INT8/FP16.

set(RAC_NNAPI_AVAILABLE OFF)

if(RAC_ENABLE_NNAPI AND RAC_PLATFORM_ANDROID)
    message(STATUS "Configuring ONNX backend with NNAPI EP support...")
    set(RAC_NNAPI_AVAILABLE ON)

    # NNAPI source files
    set(NNAPI_SOURCES
        nnapi/nnapi_session_manager.cpp
    )

    message(STATUS "  NNAPI EP enabled for ONNX backend")
    message(STATUS "  - Supports: Qualcomm (Hexagon DSP), Samsung (Exynos NPU), MediaTek (APU)")
    message(STATUS "  - Min Android API: 27 (8.1), Recommended: 29+ (10+)")
else()
    set(NNAPI_SOURCES "")
    if(RAC_ENABLE_NNAPI AND NOT RAC_PLATFORM_ANDROID)
        message(STATUS "NNAPI EP not available on ${RAC_PLATFORM_NAME} - requires Android")
    endif()
endif()

# =============================================================================
# Kokoro TTS Support (Dedicated loader for Kokoro models)
# =============================================================================

message(STATUS "Configuring Kokoro TTS support...")

# Kokoro TTS loader - internal only, auto-detects and loads Kokoro models
# through the standard TTS API (rac_tts_onnx_create)
set(KOKORO_SOURCES
    kokoro/kokoro_tts_loader.cpp
)

message(STATUS "  Kokoro TTS loader enabled (internal, auto-detected)")

# =============================================================================
# ONNX Backend Library
# =============================================================================

set(ONNX_BACKEND_SOURCES
    onnx_backend.cpp
    rac_onnx.cpp
    rac_backend_onnx_register.cpp
    ${QNN_SOURCES}
    ${NNAPI_SOURCES}
    ${KOKORO_SOURCES}
)

set(ONNX_BACKEND_HEADERS
    onnx_backend.h
)

if(RAC_BUILD_SHARED)
    add_library(rac_backend_onnx SHARED ${ONNX_BACKEND_SOURCES} ${ONNX_BACKEND_HEADERS})
else()
    add_library(rac_backend_onnx STATIC ${ONNX_BACKEND_SOURCES} ${ONNX_BACKEND_HEADERS})
endif()

target_include_directories(rac_backend_onnx PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/kokoro
    ${CMAKE_CURRENT_SOURCE_DIR}/nnapi
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/include/rac/backends
)

# Define RAC_ONNX_BUILDING to export symbols with visibility("default")
target_compile_definitions(rac_backend_onnx PRIVATE RAC_ONNX_BUILDING)

# Ensure benchmark symbols are exported (prevent linker from stripping unreferenced symbols)
if(RAC_PLATFORM_ANDROID)
    target_link_options(rac_backend_onnx PRIVATE
        -Wl,--export-dynamic-symbol=rac_tts_kokoro_run_benchmark
        -Wl,--export-dynamic-symbol=rac_tts_is_kokoro
        -Wl,--export-dynamic-symbol=rac_tts_kokoro_is_npu_active
        -Wl,--export-dynamic-symbol=rac_tts_kokoro_run_standalone_benchmark
    )
endif()

target_link_libraries(rac_backend_onnx PUBLIC
    rac_commons
    onnxruntime
    nlohmann_json::nlohmann_json
)

if(SHERPA_ONNX_AVAILABLE)
    target_link_libraries(rac_backend_onnx PUBLIC sherpa_onnx)
    target_compile_definitions(rac_backend_onnx PUBLIC SHERPA_ONNX_AVAILABLE=1)
    target_include_directories(rac_backend_onnx PUBLIC ${SHERPA_HEADER_PATH})
else()
    target_compile_definitions(rac_backend_onnx PUBLIC SHERPA_ONNX_AVAILABLE=0)
endif()

# =============================================================================
# QNN Configuration - ALWAYS DISABLED
# =============================================================================

# QNN is COMPLETELY DISABLED for NNAPI testing
# Always set RAC_QNN_AVAILABLE=0
target_compile_definitions(rac_backend_onnx PUBLIC RAC_QNN_AVAILABLE=0)
message(STATUS "  QNN compile definition: RAC_QNN_AVAILABLE=0 (QNN DISABLED)")

# =============================================================================
# NNAPI Configuration
# =============================================================================

if(RAC_NNAPI_AVAILABLE)
    target_compile_definitions(rac_backend_onnx PUBLIC RAC_NNAPI_AVAILABLE=1)
    message(STATUS "  NNAPI compile definition: RAC_NNAPI_AVAILABLE=1")
else()
    target_compile_definitions(rac_backend_onnx PUBLIC RAC_NNAPI_AVAILABLE=0)
endif()

target_compile_features(rac_backend_onnx PUBLIC cxx_std_17)

# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RAC_PLATFORM_IOS)
    target_link_libraries(rac_backend_onnx PUBLIC
        "-framework Foundation"
        "-framework CoreML"
        "-framework Accelerate"
    )

elseif(RAC_PLATFORM_ANDROID)
    target_link_libraries(rac_backend_onnx PRIVATE log)
    # Don't use -fvisibility=hidden here - JNI bridge needs these symbols
    target_compile_options(rac_backend_onnx PRIVATE -O3 -ffunction-sections -fdata-sections)
    # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
    target_link_options(rac_backend_onnx PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)

elseif(RAC_PLATFORM_MACOS)
    target_link_libraries(rac_backend_onnx PUBLIC
        "-framework Foundation"
        "-framework CoreML"
        "-framework Accelerate"
    )
endif()

# =============================================================================
# JNI TARGET (Android)
# =============================================================================

if(RAC_PLATFORM_ANDROID AND RAC_BUILD_SHARED)
    if(ANDROID)
        message(STATUS "Building ONNX JNI bridge for Android")

        add_library(rac_backend_onnx_jni SHARED jni/rac_backend_onnx_jni.cpp)

        target_include_directories(rac_backend_onnx_jni PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_SOURCE_DIR}/include
        )

        target_link_libraries(rac_backend_onnx_jni PRIVATE
            rac_backend_onnx
            log
        )

        target_compile_options(rac_backend_onnx_jni PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
        # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
        target_link_options(rac_backend_onnx_jni PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
    endif()
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "ONNX Backend Configuration:")
message(STATUS "  ONNX Runtime: Enabled")
message(STATUS "  Sherpa-ONNX:  ${SHERPA_ONNX_AVAILABLE}")
message(STATUS "  QNN NPU EP:   OFF (DISABLED for NNAPI testing)")
message(STATUS "  NNAPI EP:     ${RAC_NNAPI_AVAILABLE}")
message(STATUS "  Platform:     ${RAC_PLATFORM_NAME}")
