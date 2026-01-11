cmake_minimum_required(VERSION 3.22)

project(RunAnywhereNative VERSION 1.0.0 LANGUAGES CXX C)

# =============================================================================
# OPTIONS
# =============================================================================
# Commons is built separately from sdk/runanywhere-commons/
option(RA_BUILD_LLAMACPP "Build LlamaCpp backend" ON)
option(RA_BUILD_ONNX "Build ONNX backend" ON)
option(RA_BUILD_WHISPERCPP "Build WhisperCpp backend" OFF)
option(RA_BUILD_SHARED "Build shared libraries" OFF)
option(RAC_BUILD_JNI "Build JNI wrappers" OFF)

# =============================================================================
# CONFIGURATION
# =============================================================================
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# cmake modules are in parent directory (runanywhere-commons/cmake/)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../cmake")

# Load centralized versions from VERSIONS file
include(LoadVersions)

# =============================================================================
# PLATFORM DETECTION
# =============================================================================
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(RA_PLATFORM_IOS TRUE)
    set(RA_PLATFORM_NAME "iOS")
elseif(ANDROID)
    set(RA_PLATFORM_ANDROID TRUE)
    set(RA_PLATFORM_NAME "Android")
    set(RAC_BUILD_JNI ON CACHE BOOL "" FORCE)
elseif(APPLE)
    set(RA_PLATFORM_MACOS TRUE)
    set(RA_PLATFORM_NAME "macOS")
else()
    set(RA_PLATFORM_NAME "Unknown")
endif()

message(STATUS "Platform: ${RA_PLATFORM_NAME}")

# =============================================================================
# RAC COMMONS DEPENDENCY
# =============================================================================
# Backends are now inside runanywhere-commons/backends/
# Commons source is the parent directory
set(RAC_COMMONS_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/..)
set(RAC_INCLUDE_DIR ${RAC_COMMONS_SOURCE_DIR}/include)
set(RAC_BACKEND_INCLUDE_DIR ${RAC_INCLUDE_DIR}/backends)

if(NOT EXISTS "${RAC_INCLUDE_DIR}")
    message(FATAL_ERROR "Commons headers not found at: ${RAC_INCLUDE_DIR}")
endif()

message(STATUS "RAC Commons: ${RAC_COMMONS_SOURCE_DIR}")
include_directories(${RAC_INCLUDE_DIR})
include_directories(${RAC_BACKEND_INCLUDE_DIR})

# =============================================================================
# RAC COMMONS LIBRARY (Android shared builds only)
# =============================================================================
if(RA_PLATFORM_ANDROID AND RA_BUILD_SHARED)
    # Check for pre-built library first (REMOTE mode)
    set(RAC_PREBUILT_DIR "${CMAKE_SOURCE_DIR}/third_party/android-commons")
    set(RAC_PREBUILT_LIB "${RAC_PREBUILT_DIR}/jniLibs/${ANDROID_ABI}/librac_commons.so")
    
    if(EXISTS "${RAC_PREBUILT_LIB}")
        message(STATUS "Using pre-built rac_commons from: ${RAC_PREBUILT_DIR}")
        
        # Import pre-built library
        add_library(rac_commons SHARED IMPORTED)
        set_target_properties(rac_commons PROPERTIES
            IMPORTED_LOCATION "${RAC_PREBUILT_LIB}"
            INTERFACE_INCLUDE_DIRECTORIES "${RAC_PREBUILT_DIR}/include"
        )
        
        # Use prebuilt headers if they exist
        if(EXISTS "${RAC_PREBUILT_DIR}/include")
            set(RAC_INCLUDE_DIR "${RAC_PREBUILT_DIR}/include")
            include_directories(${RAC_INCLUDE_DIR})
        endif()
        
        set(RAC_COMMONS_LIBRARY_AVAILABLE TRUE)
        set(RAC_COMMONS_PREBUILT TRUE)
        
    elseif(RAC_COMMONS_SOURCE_DIR AND EXISTS "${RAC_COMMONS_SOURCE_DIR}/CMakeLists.txt")
        message(STATUS "Building rac_commons library for Android from: ${RAC_COMMONS_SOURCE_DIR}")

        # Configure commons build options
        set(RAC_BUILD_SHARED ON CACHE BOOL "" FORCE)
        set(RAC_BUILD_PLATFORM OFF CACHE BOOL "" FORCE)
        set(RAC_BUILD_JNI_COMMONS OFF CACHE BOOL "" FORCE)

        # Add commons as subdirectory
        add_subdirectory(${RAC_COMMONS_SOURCE_DIR} ${CMAKE_BINARY_DIR}/rac_commons EXCLUDE_FROM_ALL)

        set(RAC_COMMONS_LIBRARY_AVAILABLE TRUE)
        set(RAC_COMMONS_PREBUILT FALSE)
    else()
        message(WARNING "No rac_commons available for Android build")
        set(RAC_COMMONS_LIBRARY_AVAILABLE FALSE)
    endif()
else()
    set(RAC_COMMONS_LIBRARY_AVAILABLE FALSE)
endif()

# =============================================================================
# DEPENDENCIES
# =============================================================================
include(FetchContent)

# nlohmann/json
FetchContent_Declare(
    json
    URL https://github.com/nlohmann/json/releases/download/v${NLOHMANN_JSON_VERSION}/json.tar.xz
)
FetchContent_MakeAvailable(json)

# =============================================================================
# BUILD COMPONENTS
# =============================================================================

# Capabilities (header-only interface library) - must be added before backends
add_subdirectory(capabilities)

if(RA_BUILD_LLAMACPP)
    add_subdirectory(llamacpp)
endif()

if(RA_BUILD_ONNX)
    add_subdirectory(onnx)
endif()

if(RA_BUILD_WHISPERCPP)
    add_subdirectory(whispercpp)
endif()

# =============================================================================
# SUMMARY
# =============================================================================
message(STATUS "")
message(STATUS "====================================")
message(STATUS "RunAnywhere Backends v${PROJECT_VERSION}")
message(STATUS "====================================")
message(STATUS "Platform:       ${RA_PLATFORM_NAME}")
message(STATUS "Build type:     ${CMAKE_BUILD_TYPE}")
message(STATUS "Shared libs:    ${RA_BUILD_SHARED}")
message(STATUS "RAC headers:    ${RAC_INCLUDE_DIR}")
message(STATUS "RAC commons:    ${RAC_COMMONS_LIBRARY_AVAILABLE}")
message(STATUS "")
message(STATUS "Backends:")
message(STATUS "  LlamaCpp:     ${RA_BUILD_LLAMACPP}")
message(STATUS "  ONNX:         ${RA_BUILD_ONNX}")
message(STATUS "  WhisperCpp:   ${RA_BUILD_WHISPERCPP}")
message(STATUS "  JNI:          ${RAC_BUILD_JNI}")
message(STATUS "Commons:        sdk/runanywhere-commons/")
message(STATUS "====================================")

