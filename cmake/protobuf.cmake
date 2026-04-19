# Protobuf integration for the C++ core.
#
# Frontend codegen (swift-protobuf, Wire, protobuf.dart, ts-proto) runs through
# idl/codegen/generate_<lang>.sh — NOT through this file. This file handles
# only the C++ side, which needs protoc --cpp_out= for the core ABI.

find_package(Protobuf QUIET CONFIG)
if(NOT Protobuf_FOUND)
    find_package(Protobuf QUIET)
endif()

if(NOT Protobuf_FOUND)
    message(STATUS "protobuf not found via find_package — expected when building without vcpkg. "
                   "Targets that depend on proto3 codegen will be disabled.")
    set(RA_HAVE_PROTOBUF OFF)
    return()
endif()

set(RA_HAVE_PROTOBUF ON)

# ra_protobuf_generate(TARGET <name> PROTOS <a.proto> <b.proto> ...)
#
# Invokes protoc --cpp_out= on each .proto file, produces <name>_pb STATIC
# library with the generated sources, and publicly links the protobuf runtime.
function(ra_protobuf_generate)
    set(options)
    set(one_value_args TARGET OUT_DIR)
    set(multi_value_args PROTOS)
    cmake_parse_arguments(ARG "${options}" "${one_value_args}"
        "${multi_value_args}" ${ARGN})

    if(NOT ARG_TARGET)
        message(FATAL_ERROR "ra_protobuf_generate: TARGET is required")
    endif()
    if(NOT ARG_PROTOS)
        message(FATAL_ERROR "ra_protobuf_generate: PROTOS is required")
    endif()
    if(NOT ARG_OUT_DIR)
        set(ARG_OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/${ARG_TARGET}_gen")
    endif()

    file(MAKE_DIRECTORY "${ARG_OUT_DIR}")

    set(_gen_sources)
    set(_gen_headers)
    foreach(_proto ${ARG_PROTOS})
        get_filename_component(_proto_abs "${_proto}" ABSOLUTE)
        get_filename_component(_proto_name "${_proto}" NAME_WE)
        get_filename_component(_proto_dir  "${_proto_abs}" DIRECTORY)

        set(_cc "${ARG_OUT_DIR}/${_proto_name}.pb.cc")
        set(_h  "${ARG_OUT_DIR}/${_proto_name}.pb.h")

        add_custom_command(
            OUTPUT "${_cc}" "${_h}"
            COMMAND protobuf::protoc
                    --proto_path=${_proto_dir}
                    --cpp_out=${ARG_OUT_DIR}
                    ${_proto_abs}
            DEPENDS "${_proto_abs}" protobuf::protoc
            COMMENT "protoc --cpp_out ${_proto_name}.proto"
            VERBATIM
        )

        list(APPEND _gen_sources "${_cc}")
        list(APPEND _gen_headers "${_h}")
    endforeach()

    add_library(${ARG_TARGET} STATIC ${_gen_sources})
    target_include_directories(${ARG_TARGET} PUBLIC "${ARG_OUT_DIR}")
    target_link_libraries(${ARG_TARGET} PUBLIC protobuf::libprotobuf)
    set_target_properties(${ARG_TARGET} PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        CXX_VISIBILITY_PRESET hidden
    )
endfunction()
