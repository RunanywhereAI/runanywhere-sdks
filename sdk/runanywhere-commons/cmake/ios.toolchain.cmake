# ios.toolchain.cmake
# CMake toolchain file for iOS cross-compilation
#
# Usage:
#   cmake -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake \
#         -DIOS_PLATFORM=OS|SIMULATOR|SIMULATORARM64 \
#         ..

# Platform selection (must be set before project())
if(NOT DEFINED IOS_PLATFORM)
    set(IOS_PLATFORM "OS" CACHE STRING "iOS platform: OS, SIMULATOR, SIMULATORARM64")
endif()

# Read the deployment floor directly because toolchain files execute before
# the project can add LoadVersions.cmake to CMAKE_MODULE_PATH.
set(_RAC_VERSIONS_FILE "${CMAKE_CURRENT_LIST_DIR}/../VERSIONS")
file(STRINGS "${_RAC_VERSIONS_FILE}" _RAC_IOS_VERSION_LINE
     REGEX "^IOS_DEPLOYMENT_TARGET=[0-9]+\\.[0-9]+$")
if(NOT _RAC_IOS_VERSION_LINE)
    message(FATAL_ERROR "IOS_DEPLOYMENT_TARGET is missing from ${_RAC_VERSIONS_FILE}")
endif()
list(GET _RAC_IOS_VERSION_LINE 0 _RAC_IOS_VERSION_LINE)
string(REGEX REPLACE "^[^=]+=" "" RAC_IOS_DEPLOYMENT_TARGET "${_RAC_IOS_VERSION_LINE}")
set(CMAKE_OSX_DEPLOYMENT_TARGET "${RAC_IOS_DEPLOYMENT_TARGET}" CACHE STRING
    "Canonical iOS deployment target" FORCE)

# Configure based on platform
if(IOS_PLATFORM STREQUAL "OS")
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES "arm64")
    set(CMAKE_OSX_SYSROOT "iphoneos")
    set(IOS_PLATFORM_SUFFIX "iphoneos")
elseif(IOS_PLATFORM STREQUAL "SIMULATOR")
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES "x86_64")
    set(CMAKE_OSX_SYSROOT "iphonesimulator")
    set(IOS_PLATFORM_SUFFIX "iphonesimulator")
elseif(IOS_PLATFORM STREQUAL "SIMULATORARM64")
    set(CMAKE_SYSTEM_NAME iOS)
    set(CMAKE_OSX_ARCHITECTURES "arm64")
    set(CMAKE_OSX_SYSROOT "iphonesimulator")
    set(IOS_PLATFORM_SUFFIX "iphonesimulator")
elseif(IOS_PLATFORM STREQUAL "MACCATALYST")
    set(CMAKE_SYSTEM_NAME Darwin)
    set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
    set(IOS_PLATFORM_SUFFIX "maccatalyst")
else()
    message(FATAL_ERROR "Invalid IOS_PLATFORM: ${IOS_PLATFORM}")
endif()

# Find SDK path
execute_process(
    COMMAND xcrun --sdk ${CMAKE_OSX_SYSROOT} --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT_PATH
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(NOT CMAKE_OSX_SYSROOT_PATH)
    message(FATAL_ERROR "Could not find iOS SDK for ${CMAKE_OSX_SYSROOT}")
endif()

set(CMAKE_OSX_SYSROOT "${CMAKE_OSX_SYSROOT_PATH}")

# Compiler flags
set(CMAKE_C_FLAGS_INIT "")
set(CMAKE_CXX_FLAGS_INIT "")

# Skip RPATH handling (not applicable for static libraries)
set(CMAKE_MACOSX_RPATH OFF)
set(CMAKE_SKIP_RPATH TRUE)

# Use static libraries by default
set(BUILD_SHARED_LIBS OFF)

# Set compiler (use Clang from Xcode)
execute_process(
    COMMAND xcrun --find clang
    OUTPUT_VARIABLE CMAKE_C_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

execute_process(
    COMMAND xcrun --find clang++
    OUTPUT_VARIABLE CMAKE_CXX_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# AR and RANLIB
execute_process(
    COMMAND xcrun --find ar
    OUTPUT_VARIABLE CMAKE_AR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

execute_process(
    COMMAND xcrun --find ranlib
    OUTPUT_VARIABLE CMAKE_RANLIB
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Set minimum iOS version flag
if(IOS_PLATFORM STREQUAL "SIMULATOR" OR IOS_PLATFORM STREQUAL "SIMULATORARM64")
    set(IOS_MIN_VERSION_FLAG "-mios-simulator-version-min=${RAC_IOS_DEPLOYMENT_TARGET}")
else()
    set(IOS_MIN_VERSION_FLAG "-miphoneos-version-min=${RAC_IOS_DEPLOYMENT_TARGET}")
endif()

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS_INIT} ${IOS_MIN_VERSION_FLAG}" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS_INIT} ${IOS_MIN_VERSION_FLAG}" CACHE STRING "" FORCE)

# Don't search in system paths
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Disable code signing for Xcode builds (including compiler id checks)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")
set(CMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "")

# Output configuration
message(STATUS "iOS Toolchain Configuration:")
message(STATUS "  Platform: ${IOS_PLATFORM}")
message(STATUS "  Architectures: ${CMAKE_OSX_ARCHITECTURES}")
message(STATUS "  SDK: ${CMAKE_OSX_SYSROOT}")
message(STATUS "  Deployment Target: ${RAC_IOS_DEPLOYMENT_TARGET}")
