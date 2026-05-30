# =============================================================================
# cmake/protobuf.cmake — protobuf detection + helper macros
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

# Protobuf 5.x is required for runtime_version.h + absl::log linkage.
#
# Checked-in generated headers under sdk/runanywhere-commons/src/generated/proto
# (Protobuf C++ Version 7.34.1) include `google/protobuf/runtime_version.h`,
# which only exists from libprotobuf 4.x onward and is paired with the
# renumbered absl-using runtime (source v22+). Anything older than 5.0 is
# the legacy protobuf 3.x line and must be rejected — otherwise both this
# helper and idl/CMakeLists.txt latch onto a system protobuf 3.x install
# (Ubuntu 22.04/24.04 ship 3.12/3.21) and the build fails with either
# "runtime_version.h: No such file or directory" or a missing absl::log
# target. On Linux CI install protobuf 5.x + libabsl-dev; on macOS use
# `brew install protobuf`. The commons CMakeLists provides a vendored
# FetchContent fallback to v34.1 when no acceptable system package exists.
set(RAC_PROTOBUF_MIN_VERSION "5.0" CACHE STRING
    "Minimum acceptable Protobuf source version. Generated .pb.h files require >= 5.0.")

find_package(Protobuf ${RAC_PROTOBUF_MIN_VERSION} QUIET)

# SHARED-build consumers of proto-generated .pb.cc.o files
# (rac_voice_event_abi.cpp, pipeline.pb.cc, etc.) need absl symbols at
# link time (absl::log_internal::Check*, absl::hash_internal::*).
# Modern Homebrew protobuf 22+ ships with absl as a separate package;
# module-mode FindProtobuf.cmake doesn't propagate the absl deps. Find
# absl independently and expose only the components whose imported targets
# actually exist — older absl (Ubuntu 22.04 ships 20210324) is missing
# absl::log, so linking it unconditionally produces "Target ... links to
# absl::log but the target was not found".
find_package(absl QUIET CONFIG)
set(RAC_ABSL_LIBS "")
if(absl_FOUND)
    foreach(_rac_absl_component
            absl::log
            absl::log_internal_check_op
            absl::hash
            absl::strings
            absl::status)
        if(TARGET ${_rac_absl_component})
            list(APPEND RAC_ABSL_LIBS ${_rac_absl_component})
        endif()
    endforeach()
    message(STATUS "absl: found via CONFIG (${absl_VERSION}); usable targets: ${RAC_ABSL_LIBS}")
endif()

if(Protobuf_FOUND)
    set(RAC_HAVE_PROTOBUF TRUE)
    message(STATUS "Protobuf: found ${Protobuf_VERSION} (${Protobuf_LIBRARIES})")
else()
    set(RAC_HAVE_PROTOBUF FALSE)
    message(STATUS "Protobuf: no install >= ${RAC_PROTOBUF_MIN_VERSION} found via find_package — "
                   "rac_idl target will be skipped. "
                   "Install via 'brew install protobuf' (macOS) or "
                   "'apt-get install libprotobuf-dev libabsl-dev protobuf-compiler' (Ubuntu, "
                   "requires libprotobuf-dev >= 5.0).")
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
