# idl/ — standalone protoc --cpp_out target.
#
# Runs `protoc --cpp_out` over every .proto schema and exposes the generated
# C++ types as the `rac_idl` static library for the commons C ABI shim layer
# and for C++ tests that need to round-trip messages across the wire.
#
# Frontend codegen (Swift / Kotlin / Dart / TS / Python) runs OUT OF CMake —
# each uses its own protoc plugin invocation under idl/codegen/*.sh so CI
# reuses identical commands for PR drift detection.

# Require Protobuf >= 5.0 — the renumbered runtime that emits
# .pb.h files including `google/protobuf/runtime_version.h`. System
# protobuf 3.x (Ubuntu 22.04/24.04 apt) is rejected so we don't build
# rac_idl against a header set incompatible with the commons checked-in
# generated code. CI must install libprotobuf-dev >= 5.0 + libabsl-dev,
# or skip rac_idl entirely.
find_package(Protobuf 5.0 QUIET)

if(NOT Protobuf_FOUND)
    message(STATUS "idl/: Protobuf >= 5.0 not found via find_package — skipping rac_idl target. "
                   "Install with 'brew install protobuf' or 'apt-get install libprotobuf-dev libabsl-dev protobuf-compiler' "
                   "(requires libprotobuf-dev >= 5.0).")
    return()
endif()

set(_RAC_IDL_PROTO_FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/model_types.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/voice_events.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/pipeline.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/solutions.proto
    # Streaming service definitions (gRPC-style).
    ${CMAKE_CURRENT_SOURCE_DIR}/voice_agent_service.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/llm_service.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/download_service.proto
    # IDL exhaustiveness — duplicated data shapes across SDKs.
    ${CMAKE_CURRENT_SOURCE_DIR}/llm_options.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/chat.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/tool_calling.proto
    # Additional duplicated data shapes (per-modality options + shared types).
    ${CMAKE_CURRENT_SOURCE_DIR}/diffusion_options.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/embeddings_options.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/errors.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/lora_options.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/rag.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/sdk_events.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/storage_types.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/structured_output.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/stt_options.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/tts_options.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/vad_options.proto
    ${CMAKE_CURRENT_SOURCE_DIR}/vlm_options.proto
    # Hardware profile types for hardware namespace.
    ${CMAKE_CURRENT_SOURCE_DIR}/hardware_profile.proto
    # Model lifecycle service stub mirroring rac_model_lifecycle.h.
    ${CMAKE_CURRENT_SOURCE_DIR}/lifecycle_service.proto
    # Canonical ThinkingTagPattern shared by llm_options and model_types.
    ${CMAKE_CURRENT_SOURCE_DIR}/thinking_tag_pattern.proto
    # Shared ComponentLifecycleState + EventCategory (import-cycle break).
    ${CMAKE_CURRENT_SOURCE_DIR}/component_types.proto
    # Engine-router capability query types.
    ${CMAKE_CURRENT_SOURCE_DIR}/router.proto
    # Custom FieldOptions / EnumValueOptions extensions consumed by
    # SDK codegen post-processors (defaults(), validate(), wire-string).
    ${CMAKE_CURRENT_SOURCE_DIR}/rac_options.proto
    # Canonical two-phase SDK init request/result messages
    # (SdkInitPhase1Request / SdkInitPhase2Request / SdkInitResult). The
    # other 28 protos above keep parity with idl/codegen/generate_*.sh
    # which emit sdk_init for every other language target; this entry
    # ensures the generated sdk_init.pb.{cc,h} also link into rac_idl
    # for the C++ commons consumer.
    ${CMAKE_CURRENT_SOURCE_DIR}/sdk_init.proto
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
# SHARED consumers need explicit absl deps; see cmake/protobuf.cmake.
#
# cmake/protobuf.cmake now probes each absl::* target before adding it
# to RAC_ABSL_LIBS so this link line stays valid even when the system absl
# install is missing newer components (e.g. absl::log on Ubuntu 22.04's
# libabsl-dev). Filter once more as defense-in-depth in case a consumer
# overrides RAC_ABSL_LIBS via cache before this subdir runs.
if(RAC_ABSL_LIBS)
    set(_RAC_IDL_ABSL_LIBS "")
    foreach(_rac_idl_absl_lib ${RAC_ABSL_LIBS})
        if(TARGET ${_rac_idl_absl_lib})
            list(APPEND _RAC_IDL_ABSL_LIBS ${_rac_idl_absl_lib})
        endif()
    endforeach()
    if(_RAC_IDL_ABSL_LIBS)
        target_link_libraries(rac_idl PUBLIC ${_RAC_IDL_ABSL_LIBS})
    endif()
    unset(_RAC_IDL_ABSL_LIBS)
endif()

# Mirror the header tree into the usual install target so CMake consumers can
# `#include "runanywhere/idl/model_types.pb.h"`.
target_include_directories(rac_idl PUBLIC
    $<BUILD_INTERFACE:${_RAC_IDL_GEN_DIR}>
)

add_library(RunAnywhere::idl ALIAS rac_idl)
