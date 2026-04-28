# idl/ — standalone protoc --cpp_out target.
#
# Runs `protoc --cpp_out` over every .proto schema and exposes the generated
# C++ types as the `rac_idl` static library for the commons C ABI shim layer
# and for C++ tests that need to round-trip messages across the wire.
#
# Frontend codegen (Swift / Kotlin / Dart / TS / Python) runs OUT OF CMake —
# each uses its own protoc plugin invocation under idl/codegen/*.sh so CI
# reuses identical commands for PR drift detection.

find_package(Protobuf QUIET)

if(NOT Protobuf_FOUND)
    message(STATUS "idl/: Protobuf not found via find_package — skipping rac_idl target. "
                   "Install with 'brew install protobuf' or 'apt-get install libprotobuf-dev protobuf-compiler'.")
    return()
endif()

set(_RAC_IDL_PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/model_types.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/voice_events.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/pipeline.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/solutions.proto
    # GAP 09 Phase 12 — streaming service definitions (gRPC-style).
    ${CMAKE_CURRENT_SOURCE_DIR}/voice_agent_service.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/llm_service.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/download_service.proto
    # Phase 3 IDL exhaustiveness — duplicated data shapes across SDKs.
    ${CMAKE_CURRENT_SOURCE_DIR}/llm_options.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/chat.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/tool_calling.proto
)

# Emit C++ source + headers into a dedicated build directory so CMake can track
# them through add_custom_command dependencies.
set(_RAC_IDL_GEN_DIR ${CMAKE_CURRENT_BINARY_DIR}/generated)
file(MAKE_DIRECTORY ${_RAC_IDL_GEN_DIR})

protobuf_generate_cpp(_RAC_IDL_SRCS _RAC_IDL_HDRS ${_RAC_IDL_PROTO_FILES})

add_library(rac_idl STATIC ${_RAC_IDL_SRCS} ${_RAC_IDL_HDRS})
target_include_directories(rac_idl PUBLIC
    ${CMAKE_CURRENT_BINARY_DIR}
)
if(TARGET protobuf::libprotobuf)
    target_link_libraries(rac_idl PUBLIC protobuf::libprotobuf)
else()
    target_link_libraries(rac_idl PUBLIC ${Protobuf_LIBRARIES})
endif()
# v2 close-out: SHARED consumers need explicit absl deps; see cmake/protobuf.cmake.
if(RAC_ABSL_LIBS)
    target_link_libraries(rac_idl PUBLIC ${RAC_ABSL_LIBS})
endif()

# Mirror the header tree into the usual install target so CMake consumers can
# `#include "runanywhere/idl/model_types.pb.h"`.
target_include_directories(rac_idl PUBLIC
    $<BUILD_INTERFACE:${_RAC_IDL_GEN_DIR}>
)

add_library(RunAnywhere::idl ALIAS rac_idl)
