# =============================================================================
# Sanitizers.cmake - AddressSanitizer / UndefinedBehaviorSanitizer / ThreadSanitizer / MemorySanitizer
# =============================================================================
#
# Enables compiler/runtime sanitizers via CMake options. Sanitizers are powerful
# debug tools that catch memory errors, undefined behavior, data races, and
# uninitialized reads at runtime - dramatically improving correctness in a
# complex C++ codebase with many FFI boundaries.
#
# Options:
#   ENABLE_ASAN  - AddressSanitizer   (heap, stack, global buffer overflows;
#                                      use-after-free; double-free; leak detection)
#   ENABLE_UBSAN - UndefinedBehaviorSanitizer  (signed overflow, shift overflow,
#                                               null-deref, alignment, bounds)
#   ENABLE_TSAN  - ThreadSanitizer    (data races, deadlocks)
#   ENABLE_MSAN  - MemorySanitizer    (uninitialized memory reads; Linux/Clang only)
#
# Mutual exclusion:
#   - ASan and TSan cannot be combined (instrument different runtime paths).
#   - MSan cannot combine with ASan or UBSan.
#   - ASan + UBSan is the most common, recommended development combo.
#
# Platform support:
#   - Apple/Clang: ASan + UBSan supported; TSan supported on Linux/macOS.
#   - GCC on Linux: ASan + UBSan + TSan supported.
#   - MSVC: ASan supported (since VS 2019 16.9) via /fsanitize=address; UBSan
#           and TSan not natively available - use /RTC1 + /W4 as substitutes.
#   - Emscripten/WASM: sanitizers work but impose large runtime cost; enable
#                      locally, never ship to prod.
#   - Android NDK: ASan supported via ANDROID_SANITIZE; requires ASan wrap.sh.
#
# Usage in CMakeLists.txt:
#   include(Sanitizers)
#   add_library(rac_commons ...)
#   target_enable_sanitizers(rac_commons)
#
# Usage from command line:
#   cmake -B build -DENABLE_ASAN=ON -DENABLE_UBSAN=ON
#   cmake --build build
#   ./build/tests/test_core  # runs with runtime sanitizer checks
#
# =============================================================================

option(ENABLE_ASAN  "Enable AddressSanitizer"              OFF)
option(ENABLE_UBSAN "Enable UndefinedBehaviorSanitizer"    OFF)
option(ENABLE_TSAN  "Enable ThreadSanitizer"               OFF)
option(ENABLE_MSAN  "Enable MemorySanitizer"               OFF)

# Mutual-exclusion guards
if(ENABLE_ASAN AND ENABLE_TSAN)
    message(FATAL_ERROR
        "AddressSanitizer and ThreadSanitizer are mutually exclusive. "
        "Pick one: -DENABLE_ASAN=ON OR -DENABLE_TSAN=ON.")
endif()

if(ENABLE_MSAN AND (ENABLE_ASAN OR ENABLE_UBSAN OR ENABLE_TSAN))
    message(FATAL_ERROR
        "MemorySanitizer is mutually exclusive with all other sanitizers. "
        "Also note MSan only works on Linux + Clang and requires all "
        "dependencies (libc++, ONNX Runtime, llama.cpp, etc.) to be built "
        "with MSan instrumentation - not practical in this repo.")
endif()

# -----------------------------------------------------------------------------
# target_enable_sanitizers(target)
# -----------------------------------------------------------------------------
# Applies whichever sanitizers are enabled as PRIVATE compile + link options
# to the given target. Called once per top-level target. No-op if no sanitizer
# is enabled (so it's safe to always call).
#
# Implementation notes:
#   - Compile and link flags must match (the runtime library must be linked).
#   - -fno-omit-frame-pointer gives readable stack traces in sanitizer reports.
#   - -g forces debug symbols even in RelWithDebInfo so stacks are named.
#   - ASan needs -fsanitize=address at BOTH compile and link time.
#   - MSVC ASan needs /fsanitize=address; no link flag (done via linker probe).
# -----------------------------------------------------------------------------
function(target_enable_sanitizers target)
    if(NOT TARGET ${target})
        message(WARNING "target_enable_sanitizers: '${target}' is not a target; skipping")
        return()
    endif()

    set(_san_cflags)
    set(_san_lflags)

    # ---- AddressSanitizer ---------------------------------------------------
    if(ENABLE_ASAN)
        if(MSVC)
            list(APPEND _san_cflags /fsanitize=address)
        else()
            list(APPEND _san_cflags -fsanitize=address -fno-omit-frame-pointer -g)
            list(APPEND _san_lflags -fsanitize=address)
        endif()
        message(STATUS "[${target}] AddressSanitizer: ENABLED")
    endif()

    # ---- UndefinedBehaviorSanitizer ----------------------------------------
    if(ENABLE_UBSAN)
        if(MSVC)
            message(STATUS "[${target}] UBSan: MSVC does not have native UBSan; "
                           "using /RTC1 /GS as a weaker substitute.")
            list(APPEND _san_cflags /RTC1 /GS)
        else()
            # -fno-sanitize-recover: turn UB into hard aborts (else warnings-only).
            # -fno-sanitize=vptr: vptr requires RTTI on all types; we have -fno-rtti
            # in some llama.cpp paths, so disable to avoid link errors.
            list(APPEND _san_cflags
                 -fsanitize=undefined
                 -fno-sanitize-recover=undefined
                 -fno-sanitize=vptr
                 -fno-omit-frame-pointer -g)
            list(APPEND _san_lflags -fsanitize=undefined -fno-sanitize=vptr)
        endif()
        message(STATUS "[${target}] UndefinedBehaviorSanitizer: ENABLED")
    endif()

    # ---- ThreadSanitizer ---------------------------------------------------
    if(ENABLE_TSAN)
        if(MSVC)
            message(FATAL_ERROR "ThreadSanitizer is not available on MSVC.")
        else()
            list(APPEND _san_cflags -fsanitize=thread -fno-omit-frame-pointer -g)
            list(APPEND _san_lflags -fsanitize=thread)
        endif()
        message(STATUS "[${target}] ThreadSanitizer: ENABLED")
    endif()

    # ---- MemorySanitizer ---------------------------------------------------
    if(ENABLE_MSAN)
        # MSan requires Clang + Linux and all linked libs to be MSan-built.
        if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
            message(FATAL_ERROR "MemorySanitizer requires Clang.")
        endif()
        list(APPEND _san_cflags
             -fsanitize=memory
             -fsanitize-memory-track-origins=2
             -fno-omit-frame-pointer -g)
        list(APPEND _san_lflags -fsanitize=memory)
        message(STATUS "[${target}] MemorySanitizer: ENABLED")
    endif()

    if(_san_cflags)
        target_compile_options(${target} PRIVATE ${_san_cflags})
    endif()
    if(_san_lflags)
        target_link_options(${target} PRIVATE ${_san_lflags})
    endif()
endfunction()

# -----------------------------------------------------------------------------
# Global summary message at configure time
# -----------------------------------------------------------------------------
if(ENABLE_ASAN OR ENABLE_UBSAN OR ENABLE_TSAN OR ENABLE_MSAN)
    message(STATUS "================================================")
    message(STATUS "Sanitizers enabled:")
    if(ENABLE_ASAN)
        message(STATUS "  - AddressSanitizer   (ASan)")
    endif()
    if(ENABLE_UBSAN)
        message(STATUS "  - UndefinedBehaviorSanitizer (UBSan)")
    endif()
    if(ENABLE_TSAN)
        message(STATUS "  - ThreadSanitizer    (TSan)")
    endif()
    if(ENABLE_MSAN)
        message(STATUS "  - MemorySanitizer    (MSan)")
    endif()
    message(STATUS "Tip: set env ASAN_OPTIONS=detect_leaks=1:abort_on_error=1")
    message(STATUS "     before running for stricter reporting.")
    message(STATUS "================================================")
endif()
