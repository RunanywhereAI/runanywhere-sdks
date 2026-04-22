# =============================================================================
# cmake/sanitizers.cmake — RAC_SANITIZER switch
#
# GAP 07 Phase 3 — see v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md.
#
# RAC_SANITIZER ∈ { "" | "asan" | "tsan" | "ubsan" } — set at the root
# CMakeLists.txt and read here. Apply via `rac_apply_sanitizer(<target>)`.
#
# Notes:
#   - asan + tsan are mutually exclusive on the same binary.
#   - msan needs a stdlib build with msan-instrumented libc++; not supported
#     by default. ubsan + asan can be combined; we keep them separate to keep
#     the option matrix small.
# =============================================================================

function(rac_apply_sanitizer target)
    if(NOT RAC_SANITIZER OR RAC_SANITIZER STREQUAL "")
        return()
    endif()

    if(NOT (CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU"))
        message(WARNING "RAC_SANITIZER=${RAC_SANITIZER} requires Clang or GCC; ignored on ${CMAKE_CXX_COMPILER_ID}")
        return()
    endif()

    set(_flags "")
    if(RAC_SANITIZER STREQUAL "asan")
        list(APPEND _flags -fsanitize=address -fno-omit-frame-pointer)
    elseif(RAC_SANITIZER STREQUAL "tsan")
        list(APPEND _flags -fsanitize=thread -fno-omit-frame-pointer)
    elseif(RAC_SANITIZER STREQUAL "ubsan")
        list(APPEND _flags -fsanitize=undefined -fno-sanitize-recover=undefined)
    else()
        message(FATAL_ERROR "RAC_SANITIZER='${RAC_SANITIZER}' is not one of: asan tsan ubsan")
    endif()

    target_compile_options(${target} PRIVATE ${_flags})
    target_link_options(${target} PRIVATE ${_flags})
endfunction()
