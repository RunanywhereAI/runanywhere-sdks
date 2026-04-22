# =============================================================================
# cmake/protobuf.cmake — protobuf detection + helper macros
#
# GAP 07 Phase 5 — see v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md.
#
# Wraps `find_package(Protobuf)` and exposes a single helper that the IDL
# subdirectory and any future C++ TU consuming proto-encoded buffers calls
# instead of running its own conditional skip-if-missing block.
#
# Outputs:
#   RAC_HAVE_PROTOBUF — TRUE/FALSE; consumers branch on this.
#   When TRUE: imported targets `protobuf::libprotobuf` available.
#
# Usage:
#   include(protobuf)
#   if(RAC_HAVE_PROTOBUF)
#       rac_protobuf_generate(
#           TARGET rac_idl
#           PROTOS ${CMAKE_CURRENT_SOURCE_DIR}/voice_events.proto
#                  ${CMAKE_CURRENT_SOURCE_DIR}/model_types.proto
#       )
#   endif()
# =============================================================================

include_guard(GLOBAL)

find_package(Protobuf QUIET)

if(Protobuf_FOUND)
    set(RAC_HAVE_PROTOBUF TRUE)
    message(STATUS "Protobuf: found ${Protobuf_VERSION} (${Protobuf_LIBRARIES})")
else()
    set(RAC_HAVE_PROTOBUF FALSE)
    message(STATUS "Protobuf: not found via find_package — rac_idl target will be skipped. "
                   "Install via 'brew install protobuf' (macOS) or "
                   "'apt-get install libprotobuf-dev protobuf-compiler' (Ubuntu).")
endif()

# -----------------------------------------------------------------------------
# rac_protobuf_generate(TARGET <name> PROTOS <p1> <p2> ...)
#
# Generates C++ sources from .proto files and exposes them as a STATIC library
# that PUBLIC-includes the generated header directory (via the build interface).
# Consumers link with `target_link_libraries(<lib> PUBLIC <name>)` and
# `#include "<basename>.pb.h"`.
# -----------------------------------------------------------------------------
function(rac_protobuf_generate)
    set(_options "")
    set(_oneval  TARGET)
    set(_multival PROTOS)
    cmake_parse_arguments(P "${_options}" "${_oneval}" "${_multival}" ${ARGN})

    if(NOT RAC_HAVE_PROTOBUF)
        message(FATAL_ERROR "rac_protobuf_generate: Protobuf not found")
    endif()
    if(NOT P_TARGET OR NOT P_PROTOS)
        message(FATAL_ERROR "rac_protobuf_generate: TARGET and PROTOS are required")
    endif()

    protobuf_generate_cpp(_GEN_SRCS _GEN_HDRS ${P_PROTOS})

    add_library(${P_TARGET} STATIC ${_GEN_SRCS} ${_GEN_HDRS})
    target_include_directories(${P_TARGET} PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}>
    )
    target_link_libraries(${P_TARGET} PUBLIC ${Protobuf_LIBRARIES})
endfunction()
