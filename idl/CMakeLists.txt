# idl/ — invokes protoc --cpp_out on every .proto schema in this directory
# and exposes the generated C++ types as the `ra_idl` static library.
#
# Consumed by:
#   * core/abi/ra_voice_event_abi.* (future — the C ABI proto3 serializer)
#   * C++ tests that need to round-trip messages across the wire.
#   * Frontend codegen (Swift / Kotlin / Dart / TS) runs OUT OF CMake — each
#     uses its own protoc plugin invocation under idl/codegen/*.sh.

if(NOT RA_HAVE_PROTOBUF)
    message(STATUS "idl/: protobuf runtime unavailable — skipping ra_idl target")
    return()
endif()

ra_protobuf_generate(
    TARGET  ra_idl
    PROTOS
        ${CMAKE_CURRENT_SOURCE_DIR}/voice_events.proto
        ${CMAKE_CURRENT_SOURCE_DIR}/pipeline.proto
        ${CMAKE_CURRENT_SOURCE_DIR}/solutions.proto
)

add_library(RunAnywhere::idl ALIAS ra_idl)
