# FetchONNXRuntime.cmake
# Downloads and configures ONNX Runtime pre-built binaries

include(FetchContent)

# Load versions from centralized VERSIONS file (SINGLE SOURCE OF TRUTH)
# All versions are defined in VERSIONS file - no hardcoded fallbacks needed
include(LoadVersions)

# Validate required versions are loaded
if(NOT DEFINED ONNX_VERSION_IOS OR "${ONNX_VERSION_IOS}" STREQUAL "")
    message(FATAL_ERROR "ONNX_VERSION_IOS not defined in VERSIONS file")
endif()
if(NOT DEFINED ONNX_VERSION_MACOS OR "${ONNX_VERSION_MACOS}" STREQUAL "")
    message(FATAL_ERROR "ONNX_VERSION_MACOS not defined in VERSIONS file")
endif()
if(NOT DEFINED ONNX_VERSION_LINUX OR "${ONNX_VERSION_LINUX}" STREQUAL "")
    message(FATAL_ERROR "ONNX_VERSION_LINUX not defined in VERSIONS file")
endif()

message(STATUS "ONNX Runtime versions: iOS=${ONNX_VERSION_IOS}, Android=${ONNX_VERSION_ANDROID}, macOS=${ONNX_VERSION_MACOS}, Linux=${ONNX_VERSION_LINUX}")

if(EMSCRIPTEN)
    # ==========================================================================
    # Emscripten/WASM: Create an interface-only ONNX Runtime target.
    # When building for WASM, sherpa-onnx is built from source and bundles
    # ONNX Runtime internally.  We still need the onnxruntime headers so the
    # ONNX backend can compile.  If a local header copy exists in third_party,
    # use it; otherwise create a bare INTERFACE target (headers come from
    # sherpa-onnx's build tree).
    # ==========================================================================
    message(STATUS "ONNX Runtime: Creating INTERFACE target for Emscripten/WASM")

    add_library(onnxruntime INTERFACE)

    set(ONNX_WASM_HEADERS "${CMAKE_SOURCE_DIR}/third_party/onnxruntime-wasm/include")
    if(EXISTS "${ONNX_WASM_HEADERS}")
        target_include_directories(onnxruntime INTERFACE "${ONNX_WASM_HEADERS}")
        message(STATUS "ONNX Runtime WASM headers: ${ONNX_WASM_HEADERS}")
    else()
        # Headers will come from sherpa-onnx build tree
        message(STATUS "ONNX Runtime WASM: no local headers (expected from sherpa-onnx)")
    endif()

elseif(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # iOS: Use local ONNX Runtime xcframework from third_party
    # Downloaded by: ./scripts/ios/download-onnx.sh
    # NOTE: Version must match what sherpa-onnx was built against

    set(ONNX_IOS_VERSION "${ONNX_VERSION_IOS}")

    # third_party is inside runanywhere-commons
    set(ONNX_LOCAL_PATH "${CMAKE_SOURCE_DIR}/third_party/onnxruntime-ios")

    message(STATUS "Using local ONNX Runtime iOS xcframework v${ONNX_IOS_VERSION}")
    message(STATUS "ONNX Runtime path: ${ONNX_LOCAL_PATH}")

    # Verify the xcframework exists
    if(NOT EXISTS "${ONNX_LOCAL_PATH}/onnxruntime.xcframework")
        message(FATAL_ERROR "ONNX Runtime xcframework not found at ${ONNX_LOCAL_PATH}/onnxruntime.xcframework. "
                           "Please download it from https://download.onnxruntime.ai/pod-archive-onnxruntime-c-${ONNX_IOS_VERSION}.zip "
                           "and extract to ${ONNX_LOCAL_PATH}/")
    endif()

    # Set onnxruntime_SOURCE_DIR to point to our local copy
    set(onnxruntime_SOURCE_DIR "${ONNX_LOCAL_PATH}")

    # Create imported target for the static framework
    add_library(onnxruntime STATIC IMPORTED GLOBAL)

    # Determine architecture-specific library path
    # Check both CMAKE_OSX_SYSROOT (case-insensitive) and IOS_PLATFORM from ios.toolchain.cmake
    string(TOLOWER "${CMAKE_OSX_SYSROOT}" _sysroot_lower)
    if(_sysroot_lower MATCHES "simulator" OR (DEFINED IOS_PLATFORM AND IOS_PLATFORM MATCHES "SIMULATOR"))
        set(ONNX_FRAMEWORK_ARCH "ios-arm64_x86_64-simulator")
    else()
        set(ONNX_FRAMEWORK_ARCH "ios-arm64")
    endif()

    set(ONNX_XCFRAMEWORK_DIR "${onnxruntime_SOURCE_DIR}/onnxruntime.xcframework")
    set(ONNX_ARCH_DIR "${ONNX_XCFRAMEWORK_DIR}/${ONNX_FRAMEWORK_ARCH}")

    # The xcframework may have different structures:
    # 1. Static lib directly in arch folder: ios-arm64/libonnxruntime.a
    # 2. Inside framework folder: ios-arm64/onnxruntime.framework/onnxruntime
    if(EXISTS "${ONNX_ARCH_DIR}/libonnxruntime.a")
        set(ONNX_LIB_PATH "${ONNX_ARCH_DIR}/libonnxruntime.a")
    elseif(EXISTS "${ONNX_ARCH_DIR}/onnxruntime.a")
        set(ONNX_LIB_PATH "${ONNX_ARCH_DIR}/onnxruntime.a")
    elseif(EXISTS "${ONNX_ARCH_DIR}/onnxruntime.framework/onnxruntime")
        set(ONNX_LIB_PATH "${ONNX_ARCH_DIR}/onnxruntime.framework/onnxruntime")
    else()
        message(FATAL_ERROR "Could not find ONNX Runtime library in ${ONNX_ARCH_DIR}")
    endif()

    # Headers can be at xcframework root, arch folder, or in the local path
    set(ONNX_HEADER_DIRS "")
    if(EXISTS "${ONNX_XCFRAMEWORK_DIR}/Headers")
        list(APPEND ONNX_HEADER_DIRS "${ONNX_XCFRAMEWORK_DIR}/Headers")
    endif()
    if(EXISTS "${ONNX_LOCAL_PATH}/Headers")
        list(APPEND ONNX_HEADER_DIRS "${ONNX_LOCAL_PATH}/Headers")
    endif()

    set_target_properties(onnxruntime PROPERTIES
        IMPORTED_LOCATION "${ONNX_LIB_PATH}"
        INTERFACE_INCLUDE_DIRECTORIES "${ONNX_HEADER_DIRS}"
    )

    # Also set linker flags for the framework
    set_target_properties(onnxruntime PROPERTIES
        INTERFACE_LINK_LIBRARIES "-framework Foundation;-framework CoreML"
    )

    message(STATUS "ONNX Runtime iOS arch dir: ${ONNX_ARCH_DIR}")
    message(STATUS "ONNX Runtime static library: ${ONNX_LIB_PATH}")
    message(STATUS "ONNX Runtime headers: ${ONNX_HEADER_DIRS}")

elseif(ANDROID)
    # Android: Use ONNX Runtime from Sherpa-ONNX (16KB aligned in v1.12.20+)
    # Sherpa-ONNX version is defined in VERSIONS file: SHERPA_ONNX_VERSION_ANDROID
    # Sherpa-ONNX bundles a compatible version of ONNX Runtime
    # Downloaded by: ./scripts/android/download-sherpa-onnx.sh
    set(SHERPA_ONNX_DIR "${CMAKE_SOURCE_DIR}/third_party/sherpa-onnx-android")

    # Check if Sherpa-ONNX libraries exist
    if(EXISTS "${SHERPA_ONNX_DIR}/jniLibs/${ANDROID_ABI}/libonnxruntime.so")
        message(STATUS "Using ONNX Runtime from Sherpa-ONNX (16KB aligned)")

        set(ONNX_LIB_PATH "${SHERPA_ONNX_DIR}/jniLibs/${ANDROID_ABI}/libonnxruntime.so")
        set(ONNX_HEADER_PATH "${SHERPA_ONNX_DIR}/include")

        add_library(onnxruntime SHARED IMPORTED GLOBAL)
        set_target_properties(onnxruntime PROPERTIES
            IMPORTED_LOCATION "${ONNX_LIB_PATH}"
        )
        target_include_directories(onnxruntime INTERFACE "${ONNX_HEADER_PATH}")

        # Sherpa-ONNX Android prebuilts only ship the C API header.
        # The ONNX C++ API headers (onnxruntime_cxx_api.h etc.) are header-only
        # wrappers needed by wakeword_onnx.cpp.  Download them if missing.
        if(NOT EXISTS "${ONNX_HEADER_PATH}/onnxruntime_cxx_api.h")
            set(ONNX_CXX_HEADER_DIR "${CMAKE_BINARY_DIR}/_deps/onnxruntime-cxx-headers")
            file(MAKE_DIRECTORY "${ONNX_CXX_HEADER_DIR}")

            set(ONNX_HEADER_BASE_URL "https://raw.githubusercontent.com/microsoft/onnxruntime/v${ONNX_VERSION_ANDROID}/include/onnxruntime/core/session")
            set(ONNX_CXX_HEADERS
                onnxruntime_cxx_api.h
                onnxruntime_cxx_inline.h
                onnxruntime_float16.h
                onnxruntime_session_options_config_keys.h
                onnxruntime_run_options_config_keys.h
            )

            foreach(header ${ONNX_CXX_HEADERS})
                if(NOT EXISTS "${ONNX_CXX_HEADER_DIR}/${header}")
                    message(STATUS "Downloading ONNX C++ header: ${header}")
                    file(DOWNLOAD
                        "${ONNX_HEADER_BASE_URL}/${header}"
                        "${ONNX_CXX_HEADER_DIR}/${header}"
                        STATUS download_status
                    )
                    list(GET download_status 0 download_code)
                    if(NOT download_code EQUAL 0)
                        message(WARNING "Failed to download ${header} (status: ${download_status})")
                    endif()
                endif()
            endforeach()

            target_include_directories(onnxruntime INTERFACE "${ONNX_CXX_HEADER_DIR}")
            message(STATUS "ONNX Runtime C++ headers: ${ONNX_CXX_HEADER_DIR}")
        endif()

        message(STATUS "ONNX Runtime Android library: ${ONNX_LIB_PATH}")
        message(STATUS "ONNX Runtime Android headers: ${ONNX_HEADER_PATH}")
    else()
        message(FATAL_ERROR "Sherpa-ONNX not found. Please run: ./scripts/android/download-sherpa-onnx.sh")
    endif()

elseif(APPLE)
    # macOS: Use local ONNX Runtime from third_party if available, otherwise download
    # Downloaded by: ./scripts/macos/download-onnx.sh

    set(ONNX_MACOS_VERSION "${ONNX_VERSION_MACOS}")
    set(ONNX_MACOS_DIR "${CMAKE_SOURCE_DIR}/third_party/onnxruntime-macos")

    if(EXISTS "${ONNX_MACOS_DIR}/lib/libonnxruntime.dylib")
        # Use local ONNX Runtime
        message(STATUS "Using local ONNX Runtime macOS from ${ONNX_MACOS_DIR}")

        set(onnxruntime_SOURCE_DIR "${ONNX_MACOS_DIR}")

        add_library(onnxruntime SHARED IMPORTED GLOBAL)

        # Get the versioned dylib name for proper linking
        file(GLOB ONNX_DYLIB_FILES "${ONNX_MACOS_DIR}/lib/libonnxruntime*.dylib")
        list(GET ONNX_DYLIB_FILES 0 ONNX_DYLIB_PATH)

        set_target_properties(onnxruntime PROPERTIES
            IMPORTED_LOCATION "${ONNX_MACOS_DIR}/lib/libonnxruntime.dylib"
        )

        target_include_directories(onnxruntime INTERFACE
            "${ONNX_MACOS_DIR}/include"
        )

        # Add rpath for finding the dylib at runtime
        set_target_properties(onnxruntime PROPERTIES
            INTERFACE_LINK_LIBRARIES "-Wl,-rpath,@executable_path/../Frameworks"
        )

        message(STATUS "ONNX Runtime macOS library: ${ONNX_MACOS_DIR}/lib/libonnxruntime.dylib")
        message(STATUS "ONNX Runtime macOS headers: ${ONNX_MACOS_DIR}/include")
    else()
        # Download ONNX Runtime if not present
        message(STATUS "Local ONNX Runtime not found, downloading...")
        set(ONNX_URL "https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_MACOS_VERSION}/onnxruntime-osx-universal2-${ONNX_MACOS_VERSION}.tgz")

        FetchContent_Declare(
            onnxruntime
            URL ${ONNX_URL}
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
        )

        FetchContent_MakeAvailable(onnxruntime)

        add_library(onnxruntime SHARED IMPORTED GLOBAL)

        set_target_properties(onnxruntime PROPERTIES
            IMPORTED_LOCATION "${onnxruntime_SOURCE_DIR}/lib/libonnxruntime.dylib"
        )

        target_include_directories(onnxruntime INTERFACE
            "${onnxruntime_SOURCE_DIR}/include"
        )

        message(STATUS "ONNX Runtime macOS library: ${onnxruntime_SOURCE_DIR}/lib/libonnxruntime.dylib")
    endif()

elseif(UNIX)
    # Linux: Download Linux binaries
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
        set(ONNX_URL "https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION_LINUX}/onnxruntime-linux-aarch64-${ONNX_VERSION_LINUX}.tgz")
    else()
        set(ONNX_URL "https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION_LINUX}/onnxruntime-linux-x64-${ONNX_VERSION_LINUX}.tgz")
    endif()

    FetchContent_Declare(
        onnxruntime
        URL ${ONNX_URL}
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )

    FetchContent_MakeAvailable(onnxruntime)

    add_library(onnxruntime SHARED IMPORTED GLOBAL)

    set_target_properties(onnxruntime PROPERTIES
        IMPORTED_LOCATION "${onnxruntime_SOURCE_DIR}/lib/libonnxruntime.so"
    )

    target_include_directories(onnxruntime INTERFACE
        "${onnxruntime_SOURCE_DIR}/include"
    )

    message(STATUS "ONNX Runtime Linux library: ${onnxruntime_SOURCE_DIR}/lib/libonnxruntime.so")

else()
    message(FATAL_ERROR "Unsupported platform for ONNX Runtime")
endif()
