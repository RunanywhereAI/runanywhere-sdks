# Platform detection and per-platform compiler flags.
#
# Sets the following cache/normal variables for downstream use:
#   RA_PLATFORM          — one of IOS, ANDROID, MACOS, LINUX, WINDOWS, WASM
#   RA_IS_APPLE          — ON on iOS or macOS
#   RA_IS_MOBILE         — ON on iOS or Android
#   RA_IS_POSIX          — ON everywhere except Windows and WASM
#   RA_USE_GCD           — ON on iOS only (Grand Central Dispatch, no std::thread)
#   RA_USE_ASIO          — ON on macOS/Android/Linux/Windows
#   RA_USE_ASYNCIFY      — ON on WASM
#   RA_STATIC_PLUGINS    — ON on iOS/WASM (dlopen prohibited)
#   RA_PLUGIN_MODE       — "static" or "dlopen"
#
# All downstream CMake files read these, never test CMAKE_SYSTEM_NAME directly.

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(RA_PLATFORM "IOS")
    set(RA_IS_APPLE ON)
    set(RA_IS_MOBILE ON)
    set(RA_IS_POSIX ON)
    set(RA_USE_GCD ON)
    set(RA_USE_ASIO OFF)
    set(RA_STATIC_PLUGINS ON)
elseif(ANDROID)
    set(RA_PLATFORM "ANDROID")
    set(RA_IS_APPLE OFF)
    set(RA_IS_MOBILE ON)
    set(RA_IS_POSIX ON)
    set(RA_USE_GCD OFF)
    set(RA_USE_ASIO ON)
    set(RA_STATIC_PLUGINS OFF)
elseif(EMSCRIPTEN)
    set(RA_PLATFORM "WASM")
    set(RA_IS_APPLE OFF)
    set(RA_IS_MOBILE OFF)
    set(RA_IS_POSIX OFF)
    set(RA_USE_GCD OFF)
    set(RA_USE_ASIO OFF)
    set(RA_USE_ASYNCIFY ON)
    set(RA_STATIC_PLUGINS ON)
elseif(APPLE)
    set(RA_PLATFORM "MACOS")
    set(RA_IS_APPLE ON)
    set(RA_IS_MOBILE OFF)
    set(RA_IS_POSIX ON)
    set(RA_USE_GCD OFF)
    set(RA_USE_ASIO ON)
    set(RA_STATIC_PLUGINS OFF)
elseif(WIN32)
    set(RA_PLATFORM "WINDOWS")
    set(RA_IS_APPLE OFF)
    set(RA_IS_MOBILE OFF)
    set(RA_IS_POSIX OFF)
    set(RA_USE_GCD OFF)
    set(RA_USE_ASIO ON)
    set(RA_STATIC_PLUGINS OFF)
else()
    set(RA_PLATFORM "LINUX")
    set(RA_IS_APPLE OFF)
    set(RA_IS_MOBILE OFF)
    set(RA_IS_POSIX ON)
    set(RA_USE_GCD OFF)
    set(RA_USE_ASIO ON)
    set(RA_STATIC_PLUGINS OFF)
endif()

if(RA_STATIC_PLUGINS)
    set(RA_PLUGIN_MODE "static")
else()
    set(RA_PLUGIN_MODE "dlopen")
endif()

# ---------------------------------------------------------------------------
# Compiler flags — applied as INTERFACE targets so downstream can link against
# them selectively instead of leaking into every target via add_compile_options.
# ---------------------------------------------------------------------------
add_library(ra_platform_flags INTERFACE)
add_library(RunAnywhere::platform_flags ALIAS ra_platform_flags)

target_compile_definitions(ra_platform_flags INTERFACE
    RA_PLATFORM_${RA_PLATFORM}=1
    $<$<BOOL:${RA_USE_GCD}>:RA_USE_GCD=1>
    $<$<BOOL:${RA_USE_ASIO}>:RA_USE_ASIO=1>
    $<$<BOOL:${RA_USE_ASYNCIFY}>:RA_USE_ASYNCIFY=1>
    $<$<BOOL:${RA_STATIC_PLUGINS}>:RA_STATIC_PLUGINS=1>
)

if(MSVC)
    target_compile_options(ra_platform_flags INTERFACE
        /W4
        /permissive-
        /Zc:__cplusplus
        $<$<CONFIG:Debug>:/Od /Zi>
        $<$<CONFIG:Release>:/O2>
    )
else()
    target_compile_options(ra_platform_flags INTERFACE
        -Wall -Wextra -Wpedantic
        -Wno-unused-parameter        # common in callback signatures
        -Wno-missing-field-initializers
        $<$<CONFIG:Debug>:-O0 -g>
        $<$<CONFIG:Release>:-O3>
    )
    # -Werror only in Release CI to avoid blocking local development.
    if(DEFINED ENV{CI} AND CMAKE_BUILD_TYPE STREQUAL "Release")
        target_compile_options(ra_platform_flags INTERFACE -Werror)
    endif()
endif()

# Apple-specific deployment targets.
if(RA_IS_APPLE)
    if(RA_PLATFORM STREQUAL "IOS")
        set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0" CACHE STRING "iOS deployment target" FORCE)
    else()
        set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "macOS deployment target" FORCE)
    endif()
endif()

# Link-time optimization.
if(RA_ENABLE_LTO AND CMAKE_BUILD_TYPE STREQUAL "Release")
    include(CheckIPOSupported)
    check_ipo_supported(RESULT ra_ipo_ok OUTPUT ra_ipo_error)
    if(ra_ipo_ok)
        set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON)
    else()
        message(WARNING "LTO requested but unsupported: ${ra_ipo_error}")
    endif()
endif()
