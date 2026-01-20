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
# ONNX Backend Library
# =============================================================================

set(ONNX_BACKEND_SOURCES
    onnx_backend.cpp
    rac_onnx.cpp
    rac_backend_onnx_register.cpp
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
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/include/rac/backends
)

# Define RAC_ONNX_BUILDING to export symbols with visibility("default")
target_compile_definitions(rac_backend_onnx PRIVATE RAC_ONNX_BUILDING)

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
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
