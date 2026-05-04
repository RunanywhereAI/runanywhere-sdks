# =============================================================================
# cmake/platform.cmake — host/target platform detection
#
# GAP 07 Phase 3 — see v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md.
#
# Hoists the if(EMSCRIPTEN) ... elseif(IOS) ... cascade currently duplicated
# inside `sdk/runanywhere-commons/CMakeLists.txt` into one shared function.
# Subdirectories call `rac_detect_platform()` and read the resulting
# RAC_PLATFORM_* variables.
#
# Sets, in the calling scope:
#   RAC_PLATFORM_WASM     - TRUE/unset
#   RAC_PLATFORM_IOS      - TRUE/unset
#   RAC_PLATFORM_ANDROID  - TRUE/unset
#   RAC_PLATFORM_MACOS    - TRUE/unset
#   RAC_PLATFORM_LINUX    - TRUE/unset
#   RAC_PLATFORM_WINDOWS  - TRUE/unset
#   RAC_PLATFORM_NAME     - human-readable string ("iOS", "Android", ...)
# =============================================================================

function(rac_detect_platform)
    if(EMSCRIPTEN)
        set(RAC_PLATFORM_WASM TRUE PARENT_SCOPE)
        set(RAC_PLATFORM_NAME "Emscripten" PARENT_SCOPE)
    elseif(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
        set(RAC_PLATFORM_IOS TRUE PARENT_SCOPE)
        set(RAC_PLATFORM_NAME "iOS" PARENT_SCOPE)
    elseif(ANDROID)
        set(RAC_PLATFORM_ANDROID TRUE PARENT_SCOPE)
        set(RAC_PLATFORM_NAME "Android" PARENT_SCOPE)
    elseif(APPLE)
        set(RAC_PLATFORM_MACOS TRUE PARENT_SCOPE)
        set(RAC_PLATFORM_NAME "macOS" PARENT_SCOPE)
    elseif(WIN32)
        set(RAC_PLATFORM_WINDOWS TRUE PARENT_SCOPE)
        set(RAC_PLATFORM_NAME "Windows" PARENT_SCOPE)
    elseif(UNIX)
        set(RAC_PLATFORM_LINUX TRUE PARENT_SCOPE)
        set(RAC_PLATFORM_NAME "Linux" PARENT_SCOPE)
    else()
        set(RAC_PLATFORM_NAME "Unknown" PARENT_SCOPE)
    endif()
endfunction()
