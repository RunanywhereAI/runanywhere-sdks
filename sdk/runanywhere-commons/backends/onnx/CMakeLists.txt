# =============================================================================
# ONNX Backend - Capability-based implementation
# =============================================================================
#
# This backend provides:
# - TEXT_GENERATION: Via ONNX Runtime GenAI
# - EMBEDDINGS: Via ONNX embedding models
# - STT: Via Whisper (batch) + Sherpa-ONNX (streaming)
# - TTS: Via Sherpa-ONNX Piper/VITS models
# - VAD: Via Sherpa-ONNX Silero VAD
# - DIARIZATION: Via Sherpa-ONNX speaker models
# =============================================================================

message(STATUS "Configuring ONNX backend...")

# =============================================================================
# ONNX Runtime
# =============================================================================

include(FetchONNXRuntime)

# =============================================================================
# Sherpa-ONNX (iOS and Android)
# =============================================================================

set(SHERPA_ONNX_AVAILABLE OFF)

# Get the native root directory (monorepo structure: native/backends/onnx/)
get_filename_component(RUNANYWHERE_CORE_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)

if(RA_PLATFORM_IOS)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_CORE_ROOT}/third_party/sherpa-onnx-ios")

    if(EXISTS "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework")
        message(STATUS "Found Sherpa-ONNX xcframework at: ${SHERPA_ONNX_ROOT}")
        set(SHERPA_ONNX_AVAILABLE ON)

        # Determine architecture
        if(CMAKE_OSX_SYSROOT MATCHES "simulator")
            set(SHERPA_ARCH "ios-arm64_x86_64-simulator")
        else()
            set(SHERPA_ARCH "ios-arm64")
        endif()

        # Find the static library
        if(EXISTS "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework/${SHERPA_ARCH}/libsherpa-onnx.a")
            set(SHERPA_LIB_PATH "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework/${SHERPA_ARCH}/libsherpa-onnx.a")
        else()
            # Try alternative path within framework
            file(GLOB SHERPA_LIB_CANDIDATES "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework/${SHERPA_ARCH}/*.a")
            if(SHERPA_LIB_CANDIDATES)
                list(GET SHERPA_LIB_CANDIDATES 0 SHERPA_LIB_PATH)
            else()
                message(STATUS "Sherpa-ONNX library not found for ${SHERPA_ARCH}")
                set(SHERPA_ONNX_AVAILABLE OFF)
            endif()
        endif()
        set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/sherpa-onnx.xcframework/${SHERPA_ARCH}/Headers")

        message(STATUS "Sherpa-ONNX library: ${SHERPA_LIB_PATH}")
        message(STATUS "Sherpa-ONNX headers: ${SHERPA_HEADER_PATH}")

        # Create imported library only if we found it
        if(SHERPA_ONNX_AVAILABLE AND SHERPA_LIB_PATH)
            add_library(sherpa_onnx STATIC IMPORTED GLOBAL)
            set_target_properties(sherpa_onnx PROPERTIES
                IMPORTED_LOCATION "${SHERPA_LIB_PATH}"
                INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}"
            )
        endif()
    else()
        message(STATUS "Sherpa-ONNX not found - streaming STT/TTS/VAD disabled")
    endif()

elseif(RA_PLATFORM_ANDROID)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_CORE_ROOT}/third_party/sherpa-onnx-android")

    if(EXISTS "${SHERPA_ONNX_ROOT}/jniLibs")
        message(STATUS "Found Sherpa-ONNX Android libraries at: ${SHERPA_ONNX_ROOT}")

        # Find the library for current ABI
        set(SHERPA_ABI_DIR "${SHERPA_ONNX_ROOT}/jniLibs/${ANDROID_ABI}")

        # Use the C API library (not the JNI wrapper)
        if(EXISTS "${SHERPA_ABI_DIR}/libsherpa-onnx-c-api.so")
            set(SHERPA_ONNX_AVAILABLE ON)
            set(SHERPA_LIB_PATH "${SHERPA_ABI_DIR}/libsherpa-onnx-c-api.so")

            add_library(sherpa_onnx SHARED IMPORTED GLOBAL)
            set_target_properties(sherpa_onnx PROPERTIES
                IMPORTED_LOCATION "${SHERPA_LIB_PATH}"
            )

            # Include headers if available
            if(EXISTS "${SHERPA_ONNX_ROOT}/include")
                set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/include")
                set_target_properties(sherpa_onnx PROPERTIES
                    INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}"
                )
            endif()

            message(STATUS "Sherpa-ONNX library: ${SHERPA_LIB_PATH}")
        else()
            message(STATUS "Sherpa-ONNX library not found for ${ANDROID_ABI}")
            set(SHERPA_ONNX_AVAILABLE OFF)
        endif()
    else()
        message(STATUS "Sherpa-ONNX not found - streaming STT/TTS/VAD disabled on Android")
        message(STATUS "Run: ./scripts/android/download-sherpa-onnx.sh to download")
    endif()

elseif(RA_PLATFORM_MACOS)
    set(SHERPA_ONNX_ROOT "${RUNANYWHERE_CORE_ROOT}/third_party/sherpa-onnx-macos")

    if(EXISTS "${SHERPA_ONNX_ROOT}/lib")
        message(STATUS "Found Sherpa-ONNX macOS libraries at: ${SHERPA_ONNX_ROOT}")

        # Find the C API static library (universal binary: arm64 + x86_64)
        if(EXISTS "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.a")
            set(SHERPA_ONNX_AVAILABLE ON)
            set(SHERPA_LIB_PATH "${SHERPA_ONNX_ROOT}/lib/libsherpa-onnx-c-api.a")
            set(SHERPA_HEADER_PATH "${SHERPA_ONNX_ROOT}/include")

            message(STATUS "Sherpa-ONNX library: ${SHERPA_LIB_PATH}")
            message(STATUS "Sherpa-ONNX headers: ${SHERPA_HEADER_PATH}")

            # Create imported library
            add_library(sherpa_onnx STATIC IMPORTED GLOBAL)
            set_target_properties(sherpa_onnx PROPERTIES
                IMPORTED_LOCATION "${SHERPA_LIB_PATH}"
                INTERFACE_INCLUDE_DIRECTORIES "${SHERPA_HEADER_PATH}"
            )

            # Sherpa-ONNX has dependencies that need to be linked
            # These are bundled in the official release as separate static libs
            set(SHERPA_ONNX_DEPS
                "sherpa-onnx-core"
                "sherpa-onnx-fst"
                "sherpa-onnx-fstfar"
                "sherpa-onnx-kaldifst-core"
                "kaldi-decoder-core"
                "kaldi-native-fbank-core"
                "piper_phonemize"
                "espeak-ng"
                "ucd"
                "cppinyin_core"
                "ssentencepiece_core"
                "kissfft-float"
            )

            foreach(dep ${SHERPA_ONNX_DEPS})
                if(EXISTS "${SHERPA_ONNX_ROOT}/lib/lib${dep}.a")
                    add_library(sherpa_${dep} STATIC IMPORTED GLOBAL)
                    set_target_properties(sherpa_${dep} PROPERTIES
                        IMPORTED_LOCATION "${SHERPA_ONNX_ROOT}/lib/lib${dep}.a"
                    )
                    target_link_libraries(sherpa_onnx INTERFACE sherpa_${dep})
                    message(STATUS "  Added dependency: ${dep}")
                endif()
            endforeach()

        else()
            message(STATUS "Sherpa-ONNX C API library not found")
            set(SHERPA_ONNX_AVAILABLE OFF)
        endif()
    else()
        message(STATUS "Sherpa-ONNX not found - streaming STT/TTS/VAD disabled on macOS")
        message(STATUS "Run: ./scripts/macos/download-sherpa-onnx.sh to download")
    endif()
endif()

# =============================================================================
# ONNX Backend Library
# =============================================================================

set(ONNX_BACKEND_SOURCES
    onnx_backend.cpp
)

set(ONNX_BACKEND_HEADERS
    onnx_backend.h
)

# Choose library type based on parent's RA_BUILD_SHARED option
if(RA_BUILD_SHARED)
    add_library(runanywhere_onnx SHARED
        ${ONNX_BACKEND_SOURCES}
        ${ONNX_BACKEND_HEADERS}
    )
else()
    add_library(runanywhere_onnx STATIC
        ${ONNX_BACKEND_SOURCES}
        ${ONNX_BACKEND_HEADERS}
    )
endif()

target_include_directories(runanywhere_onnx PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/capabilities                 # Capabilities headers
    ${CMAKE_SOURCE_DIR}                              # Backend source root
    ${CMAKE_SOURCE_DIR}/../include                   # Public headers
    ${CMAKE_SOURCE_DIR}/../include/backends          # Backend public headers
    ${RAC_INCLUDE_DIR}                               # Commons headers (rac/core/*)
)

# Link ONNX Runtime
target_link_libraries(runanywhere_onnx PUBLIC
    runanywhere_capabilities
    onnxruntime
)

# =============================================================================
# RAC API LIBRARY (directly exports rac_* C APIs)
# =============================================================================

set(RAC_ONNX_SOURCES
    rac_onnx.cpp
)

# Registration code - included for all platforms
# For Android, we link against rac_commons to get the real implementations
list(APPEND RAC_ONNX_SOURCES rac_backend_onnx_register.cpp)

add_library(rac_backend_onnx STATIC ${RAC_ONNX_SOURCES})

target_include_directories(rac_backend_onnx
    PUBLIC
        ${CMAKE_SOURCE_DIR}/../include             # Public RAC headers (rac_stt_onnx.h, etc.)
        ${CMAKE_SOURCE_DIR}/../include/backends    # Backend public headers
        ${RAC_INCLUDE_DIR}                         # Commons RAC type headers
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}                # Internal headers
        ${CMAKE_SOURCE_DIR}/capabilities           # Capabilities headers
)

target_link_libraries(rac_backend_onnx
    PRIVATE
        runanywhere_onnx
)

target_compile_features(rac_backend_onnx PUBLIC cxx_std_17)

# =============================================================================
# JNI TARGET (Android)
# =============================================================================

if(RA_PLATFORM_ANDROID AND RA_BUILD_SHARED)
    find_package(JNI QUIET)

    if(JNI_FOUND OR ANDROID)
        message(STATUS "Building ONNX JNI bridge for Android")

        add_library(rac_backend_onnx_jni SHARED
            jni/rac_backend_onnx_jni.cpp
        )

        target_include_directories(rac_backend_onnx_jni PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_SOURCE_DIR}/../include
            ${CMAKE_SOURCE_DIR}/../include/backends
            ${RAC_INCLUDE_DIR}                     # Commons headers
        )

        target_link_libraries(rac_backend_onnx_jni
            PRIVATE
                rac_backend_onnx
                runanywhere_onnx
                log
        )

        target_compile_options(rac_backend_onnx_jni PRIVATE
            -O3
            -fvisibility=hidden
            -ffunction-sections
            -fdata-sections
        )

        target_link_options(rac_backend_onnx_jni PRIVATE
            -Wl,--gc-sections
        )

        install(TARGETS rac_backend_onnx_jni
            LIBRARY DESTINATION lib/${ANDROID_ABI}
            ARCHIVE DESTINATION lib/${ANDROID_ABI}
        )
    endif()
endif()

# Link Sherpa-ONNX if available
if(SHERPA_ONNX_AVAILABLE)
    target_link_libraries(runanywhere_onnx PUBLIC sherpa_onnx)
    target_compile_definitions(runanywhere_onnx PUBLIC SHERPA_ONNX_AVAILABLE=1)
    target_include_directories(runanywhere_onnx PUBLIC ${SHERPA_HEADER_PATH})
else()
    target_compile_definitions(runanywhere_onnx PUBLIC SHERPA_ONNX_AVAILABLE=0)
endif()

target_compile_features(runanywhere_onnx PUBLIC cxx_std_17)

# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RA_PLATFORM_IOS)
    message(STATUS "Configuring ONNX backend for iOS")

    # Link iOS frameworks
    target_link_libraries(runanywhere_onnx PUBLIC
        "-framework Foundation"
        "-framework CoreML"
        "-framework Accelerate"
    )

elseif(RA_PLATFORM_ANDROID)
    message(STATUS "Configuring ONNX backend for Android")
    target_link_libraries(runanywhere_onnx PRIVATE log)

    # Link rac_backend_onnx against rac_commons for error handling, logging, events
    if(RAC_COMMONS_LIBRARY_AVAILABLE)
        target_link_libraries(rac_backend_onnx PUBLIC rac_commons)
        message(STATUS "  Linked rac_backend_onnx against rac_commons")
    endif()

elseif(RA_PLATFORM_MACOS)
    message(STATUS "Configuring ONNX backend for macOS")
    target_link_libraries(runanywhere_onnx PUBLIC
        "-framework Foundation"
        "-framework CoreML"
        "-framework Accelerate"
    )
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "ONNX Backend Configuration:")
message(STATUS "  ONNX Runtime: Enabled")
message(STATUS "  Sherpa-ONNX:  ${SHERPA_ONNX_AVAILABLE}")
