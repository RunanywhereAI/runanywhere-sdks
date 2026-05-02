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

# Android NDK doesn't ship libprotobuf and find_package(Protobuf) returns
# nothing on a stock NDK sysroot. Fall back to FetchContent — same pattern
# as the curl/mbedtls bundle in sdk/runanywhere-commons/CMakeLists.txt.
# Without this, RAC_HAVE_PROTOBUF stays undefined on Android, the real
# rac_solution.cpp + companions are skipped, and rac_solution_create_from_yaml
# returns RAC_ERROR_FEATURE_NOT_AVAILABLE at runtime.
#
# Pinned to v34.1 because the committed src/generated/proto/*.pb.{h,cc}
# files declare `#if PROTOBUF_VERSION != 7034001` (C++ runtime 7.34.1).
if(NOT Protobuf_FOUND AND ANDROID)
    message(STATUS "Android: bundling Protobuf v34.1 via FetchContent (NDK sysroot has no libprotobuf)")
    include(FetchContent)
    if(NOT DEFINED PROTOBUF_FETCH_VERSION)
        set(PROTOBUF_FETCH_VERSION "v34.1")
    endif()
    FetchContent_Declare(
        protobuf_fetched
        GIT_REPOSITORY https://github.com/protocolbuffers/protobuf.git
        GIT_TAG        ${PROTOBUF_FETCH_VERSION}
        GIT_SHALLOW    TRUE
    )
    # Trim everything not needed at runtime. protoc is the host code generator
    # (.proto -> .pb.cc) — we already ship pre-generated files under
    # src/generated/proto, so cross-compiling protoc for the device is wrong.
    set(protobuf_BUILD_TESTS         OFF CACHE BOOL "" FORCE)
    set(protobuf_BUILD_CONFORMANCE   OFF CACHE BOOL "" FORCE)
    set(protobuf_BUILD_EXAMPLES      OFF CACHE BOOL "" FORCE)
    set(protobuf_BUILD_PROTOC_BINARIES OFF CACHE BOOL "" FORCE)
    set(protobuf_BUILD_LIBPROTOC     OFF CACHE BOOL "" FORCE)
    set(protobuf_BUILD_LIBUPB        OFF CACHE BOOL "" FORCE)
    set(protobuf_BUILD_SHARED_LIBS   OFF CACHE BOOL "" FORCE)
    set(protobuf_DISABLE_RTTI        OFF CACHE BOOL "" FORCE)
    set(protobuf_INSTALL             OFF CACHE BOOL "" FORCE)
    set(protobuf_WITH_ZLIB           OFF CACHE BOOL "" FORCE)
    # Abseil is fetched transitively by protobuf when no system absl is
    # present. Tell it to propagate our C++20 standard so its hash_internal
    # / log_internal symbols match the ones the .pb.cc files emit.
    set(ABSL_PROPAGATE_CXX_STD       ON  CACHE BOOL "" FORCE)
    set(ABSL_ENABLE_INSTALL          OFF CACHE BOOL "" FORCE)
    set(ABSL_BUILD_TESTING           OFF CACHE BOOL "" FORCE)
    set(BUILD_TESTING                OFF CACHE BOOL "" FORCE)
    # utf8_range is vendored under third_party/utf8_range and pulled in by
    # protobuf's CMake; nothing extra needed.
    FetchContent_MakeAvailable(protobuf_fetched)

    # Module-mode FindProtobuf.cmake (used by `find_package(Protobuf)` when
    # CONFIG isn't found) returns Protobuf_FOUND=FALSE on Android. Fake the
    # variables so the rest of the tree (sdk/runanywhere-commons/CMakeLists.txt
    # and any future consumer) sees the bundled build as a valid match. Set
    # both the normal variable (this scope's later if(Protobuf_FOUND) check)
    # and the cache variable (downstream subdirectories / re-configures).
    set(Protobuf_FOUND        TRUE)
    set(Protobuf_VERSION      "34.1")
    set(Protobuf_INCLUDE_DIR  "${protobuf_fetched_SOURCE_DIR}/src")
    set(Protobuf_INCLUDE_DIRS "${protobuf_fetched_SOURCE_DIR}/src")
    set(Protobuf_FOUND        TRUE                                CACHE BOOL   "" FORCE)
    set(Protobuf_VERSION      "34.1"                              CACHE STRING "" FORCE)
    set(Protobuf_INCLUDE_DIR  "${protobuf_fetched_SOURCE_DIR}/src" CACHE PATH   "" FORCE)
    set(Protobuf_INCLUDE_DIRS "${protobuf_fetched_SOURCE_DIR}/src" CACHE PATH   "" FORCE)
    if(TARGET libprotobuf AND NOT TARGET protobuf::libprotobuf)
        add_library(protobuf::libprotobuf ALIAS libprotobuf)
    endif()
    set(Protobuf_LIBRARIES protobuf::libprotobuf)
endif()

# v2 close-out: SHARED-build consumers of proto-generated .pb.cc.o files
# (rac_voice_event_abi.cpp, pipeline.pb.cc, etc.) need absl symbols at
# link time (absl::log_internal::Check*, absl::hash_internal::*).
# Modern Homebrew protobuf 22+ ships with absl as a separate package;
# module-mode FindProtobuf.cmake doesn't propagate the absl deps. Find
# absl independently and expose its components via the RAC_ABSL_LIBS
# variable that consumers append to their link line.
#
# On Android, FetchContent has already created the absl::* targets as
# regular CMake targets (not via find_package CONFIG), so the find_package
# call below would miss them. Bind RAC_ABSL_LIBS to the targets directly
# in that case.
if(ANDROID AND TARGET absl::log)
    set(RAC_ABSL_LIBS absl::log absl::log_internal_check_op absl::hash absl::strings absl::status)
    message(STATUS "absl: using FetchContent-bundled targets (Android)")
else()
    find_package(absl QUIET CONFIG)
    if(absl_FOUND)
        set(RAC_ABSL_LIBS absl::log absl::log_internal_check_op absl::hash absl::strings absl::status)
        message(STATUS "absl: found via CONFIG (${absl_VERSION})")
    else()
        set(RAC_ABSL_LIBS "")
    endif()
endif()

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
