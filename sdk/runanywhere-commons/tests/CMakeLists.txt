# Must match sdk/runanywhere-commons/VERSIONS::MIN_CMAKE_VERSION (3.30).
cmake_minimum_required(VERSION 3.24)

# =============================================================================
# Integration Test Suite for runanywhere-commons
# =============================================================================

# Helper: link bundled archive dependencies to test targets on MSVC.
# On MSVC, transitive static lib deps from archive_static don't propagate fully.
function(rac_link_archive_deps target)
    if(TARGET archive_static)
        target_link_libraries(${target} PRIVATE archive_static)
    endif()
    if(TARGET zlibstatic)
        target_link_libraries(${target} PRIVATE zlibstatic)
    endif()
    if(TARGET bz2_bundled)
        target_link_libraries(${target} PRIVATE bz2_bundled)
    endif()
endfunction()

# rac_commons does not propagate RAC_HAVE_PROTOBUF=1 via its
# PUBLIC interface (it is PRIVATE so it does not leak through the L5 ABI).
# Tests that intentionally exercise the proto-byte path are internal consumers,
# so re-define the macro here when the parent commons target actually enabled
# the protobuf runtime.
set(_RAC_COMMONS_TESTS_HAVE_PROTOBUF 0)
if(RAC_PROTOBUF_RUNTIME_ENABLED AND EXISTS ${CMAKE_CURRENT_LIST_DIR}/../src/generated/proto/voice_events.pb.cc)
    set(_RAC_COMMONS_TESTS_HAVE_PROTOBUF 1)
endif()

# Helper to apply the proto compile definition to test targets that need it.
# Also re-attaches the (now-PRIVATE) src/generated/proto include path so the
# test TU can resolve `*.pb.h` direct includes (same path the library uses).
function(rac_test_define_have_protobuf target)
    if(_RAC_COMMONS_TESTS_HAVE_PROTOBUF)
        target_compile_definitions(${target} PRIVATE RAC_HAVE_PROTOBUF=1)
        target_include_directories(${target} PRIVATE
            ${CMAKE_CURRENT_LIST_DIR}/../src/generated/proto
            ${CMAKE_CURRENT_LIST_DIR}/../src/generated
            ${Protobuf_INCLUDE_DIRS}
        )
        if(TARGET protobuf::libprotobuf)
            target_link_libraries(${target} PRIVATE protobuf::libprotobuf)
        elseif(Protobuf_LIBRARIES)
            target_link_libraries(${target} PRIVATE ${Protobuf_LIBRARIES})
        endif()
        if(RAC_ABSL_LIBS)
            target_link_libraries(${target} PRIVATE ${RAC_ABSL_LIBS})
        endif()
        if(RAC_PROTOBUF_COMPILE_OPTIONS)
            target_compile_options(${target} PRIVATE ${RAC_PROTOBUF_COMPILE_OPTIONS})
        endif()
    endif()
endfunction()

# SolutionRunner / PipelineExecutor tests currently use RAC_HAVE_PROTOBUF as
# their source-level guard, but the implementation objects are present only
# when the parent target enabled the full Solutions runtime.
function(rac_test_define_have_solutions target)
    if(RAC_SOLUTIONS_RUNTIME_ENABLED)
        rac_test_define_have_protobuf(${target})
    endif()
endfunction()

set(RAC_COMMONS_THIRD_PARTY_DIR "${CMAKE_CURRENT_LIST_DIR}/../third_party")

# Tests may need access to commons private headers (e.g. the internal
# platform-compat shim under src/core/internal/). Add the private src/ root so
# test sources can include e.g. "core/internal/platform_compat.h".
# Uses CMAKE_CURRENT_LIST_DIR (not CMAKE_SOURCE_DIR) so the path resolves to
# commons/src regardless of whether commons is built standalone or as a
# subdirectory of the top-level project.
include_directories(${CMAKE_CURRENT_LIST_DIR}/../src)

# --- Kotlin JNI request cancellation admission ----------------------
# Header-only relay used by request-scoped VLM/RAG JNI wrappers. Covers
# cancel-before-entry ownership, backend-publication retry, and the completion
# exclusion that prevents a stale pulse from reaching a successor request.
find_package(Threads REQUIRED)
add_executable(test_jni_request_cancellation_relay test_jni_request_cancellation_relay.cpp)
target_compile_features(test_jni_request_cancellation_relay PRIVATE cxx_std_20)
target_link_libraries(test_jni_request_cancellation_relay PRIVATE Threads::Threads)
add_test(NAME jni_request_cancellation_relay_tests COMMAND test_jni_request_cancellation_relay)

# --- DAG graph primitives unit tests --------------------------
# CancelToken + RingBuffer + StreamEdge. Header-only
# primitives; no backend dependency. Always built.
add_executable(test_graph_primitives test_graph_primitives.cpp)
target_include_directories(test_graph_primitives PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_graph_primitives PRIVATE rac_commons)
rac_link_archive_deps(test_graph_primitives)
target_compile_features(test_graph_primitives PRIVATE cxx_std_17)
add_test(NAME graph_primitives_tests COMMAND test_graph_primitives)

# --- Log redaction policy parity tests ------------------------------
# Validates rac_log_metadata_should_redact() against the same fixture set
# Swift's SDKLogger.swift honors. Pure-C++ helper, no backend dependency.
add_executable(test_log_redact test_log_redact.cpp)
target_include_directories(test_log_redact PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_log_redact PRIVATE rac_commons)
rac_link_archive_deps(test_log_redact)
target_compile_features(test_log_redact PRIVATE cxx_std_17)
add_test(NAME log_redact_tests COMMAND test_log_redact --run-all)

# --- Desktop platform adapter tests ---------------------------------
# POSIX adapter slots + 0600 secure store + curl transport registration +
# the model-paths base-dir dedup rule. Only meaningful when the desktop
# adapter TUs are compiled into rac_commons (RAC_DESKTOP_ADAPTER=ON).
if(RAC_DESKTOP_ADAPTER)
    add_executable(test_desktop_adapter test_desktop_adapter.cpp)
    target_include_directories(test_desktop_adapter PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_desktop_adapter PRIVATE rac_commons)
    rac_link_archive_deps(test_desktop_adapter)
    target_compile_features(test_desktop_adapter PRIVATE cxx_std_20)
    add_test(NAME desktop_adapter_tests COMMAND test_desktop_adapter --run-all)
endif()

# --- audio level-meter DSP parity tests ---------------------------------
# Validates rac_audio_compute_level_db() — the centralised RMS->dB DSP that
# replaces the hand-rolled level meters in Swift AudioCaptureManager.swift
# (and equivalents in Kotlin/Flutter/RN/Web). No backend dependency.
add_executable(test_audio_compute_level_db test_audio_compute_level_db.cpp)
target_include_directories(test_audio_compute_level_db PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_audio_compute_level_db PRIVATE rac_commons)
rac_link_archive_deps(test_audio_compute_level_db)
target_compile_features(test_audio_compute_level_db PRIVATE cxx_std_17)
add_test(NAME audio_compute_level_db_tests COMMAND test_audio_compute_level_db --run-all)

# --- Persistent device-id resolution chain --------------------------
# Validates rac_device_get_or_create_persistent_id() against a mocked
# rac_platform_adapter_t (secure_get / secure_set / get_vendor_id). Replaces
# the local Keychain -> identifierForVendor -> generate-UUID chain that each
# platform SDK previously reimplemented. No backend dependency.
add_executable(test_device_identity test_device_identity.cpp)
target_include_directories(test_device_identity PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_device_identity PRIVATE rac_commons)
rac_link_archive_deps(test_device_identity)
target_compile_features(test_device_identity PRIVATE cxx_std_17)
add_test(NAME device_identity_tests COMMAND test_device_identity --run-all)

# --- Model path layout tests ----------------------------------------
add_executable(test_model_paths test_model_paths.cpp)
target_include_directories(test_model_paths PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_paths PRIVATE rac_commons)
rac_link_archive_deps(test_model_paths)
target_compile_features(test_model_paths PRIVATE cxx_std_17)
add_test(NAME model_paths_tests COMMAND test_model_paths)

# --- VLM default generation options ---------------------------------
add_executable(test_vlm_options_defaults test_vlm_options_defaults.cpp)
target_include_directories(test_vlm_options_defaults PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_vlm_options_defaults PRIVATE rac_commons)
rac_link_archive_deps(test_vlm_options_defaults)
target_compile_features(test_vlm_options_defaults PRIVATE cxx_std_17)
add_test(NAME vlm_options_defaults_tests COMMAND test_vlm_options_defaults)

# --- MemoryPool<T> tests ------------------------------
# Header-only template; verifies acquire/release, blocking, cancel, and a
# concurrent stress test.
add_executable(test_memory_pool test_memory_pool.cpp)
target_include_directories(test_memory_pool PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_memory_pool PRIVATE rac_commons)
rac_link_archive_deps(test_memory_pool)
target_compile_features(test_memory_pool PRIVATE cxx_std_17)
add_test(NAME memory_pool_tests COMMAND test_memory_pool)

# --- PipelineNode family tests ------------------------
# Exercises PrimitiveNode, SplitNode, MergeNode, and the 3-node linear graph
# wiring that GraphScheduler::connect() relies on.
add_executable(test_pipeline_node test_pipeline_node.cpp)
target_include_directories(test_pipeline_node PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_pipeline_node PRIVATE rac_commons)
rac_link_archive_deps(test_pipeline_node)
target_compile_features(test_pipeline_node PRIVATE cxx_std_17)
add_test(NAME pipeline_node_tests COMMAND test_pipeline_node)

# --- GraphScheduler tests -----------------------------
# Streaming correctness + backpressure + cancellation + lifecycle.
add_executable(test_graph_scheduler test_graph_scheduler.cpp)
target_include_directories(test_graph_scheduler PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_graph_scheduler PRIVATE rac_commons)
rac_link_archive_deps(test_graph_scheduler)
target_compile_features(test_graph_scheduler PRIVATE cxx_std_17)
add_test(NAME graph_scheduler_tests COMMAND test_graph_scheduler)

# --- PipelineExecutor + SolutionRunner (Solutions-gated) ---------------
# The executor / runner / C ABI live behind RAC_ENABLE_SOLUTIONS. Each test
# TU compiles a SKIP-style stub when the symbol is undefined (e.g. CI
# builds with RAC_ENABLE_SOLUTIONS=OFF), so the test executables always link
# cleanly.
add_executable(test_pipeline_executor test_pipeline_executor.cpp)
target_include_directories(test_pipeline_executor PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_pipeline_executor PRIVATE rac_commons)
rac_link_archive_deps(test_pipeline_executor)
target_compile_features(test_pipeline_executor PRIVATE cxx_std_17)
rac_test_define_have_solutions(test_pipeline_executor)
add_test(NAME pipeline_executor_tests COMMAND test_pipeline_executor)

add_executable(test_solution_runner test_solution_runner.cpp)
target_include_directories(test_solution_runner PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_solution_runner PRIVATE rac_commons)
rac_link_archive_deps(test_solution_runner)
target_compile_features(test_solution_runner PRIVATE cxx_std_17)
rac_test_define_have_solutions(test_solution_runner)
add_test(NAME solution_runner_tests COMMAND test_solution_runner)

# --- Rac_llm_thinking C ABI test -----------------------
# Behavioral parity with Swift ThinkingContentParser. 10 scenarios covering
# extract / strip / split-tokens incl. malformed inputs.
add_executable(test_llm_thinking test_llm_thinking.cpp)
target_include_directories(test_llm_thinking PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_llm_thinking PRIVATE rac_commons)
rac_link_archive_deps(test_llm_thinking)
target_compile_features(test_llm_thinking PRIVATE cxx_std_17)
add_test(NAME llm_thinking_tests COMMAND test_llm_thinking)

# --- Voice-agent response policy tests ----------------------
# Host-only coverage for the deterministic no-thinking generation policy,
# reasoning removal, speakable-text sanitization, and the blank-answer gate
# that prevents an invalid TTS invocation.
add_executable(test_voice_agent_response_policy test_voice_agent_response_policy.cpp)
target_include_directories(test_voice_agent_response_policy PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_voice_agent_response_policy PRIVATE rac_commons)
rac_link_archive_deps(test_voice_agent_response_policy)
target_compile_features(test_voice_agent_response_policy PRIVATE cxx_std_17)
add_test(NAME voice_agent_response_policy_tests COMMAND test_voice_agent_response_policy)

# --- Rac_tool_call_* C ABI test ----------------------
# Behavioral tests for the single-source-of-truth tool-calling API shared by
# Swift, Kotlin, Flutter, Web, and React Native SDKs. Covers parse (default +
# LFM2), free-form, format_prompt, build_initial/followup_prompt, normalize_json,
# and free-function idempotence.
add_executable(test_tool_calling test_tool_calling.cpp)
target_include_directories(test_tool_calling PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_tool_calling PRIVATE rac_commons)
rac_link_archive_deps(test_tool_calling)
target_compile_features(test_tool_calling PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_tool_calling)
add_test(NAME tool_calling_tests COMMAND test_tool_calling)

# --- commons-owned RAModelInfo heuristics --------
# Exercises rac_tool_call_format_from_model_info_proto +
# rac_model_info_parameter_count_b_proto + rac_model_info_is_small_model_proto.
# Replaces example-side detectToolCallFormat / isLikelySmallModel duplication.
add_executable(test_model_heuristics test_model_heuristics.cpp)
target_include_directories(test_model_heuristics PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src/generated/proto
)
target_link_libraries(test_model_heuristics PRIVATE rac_commons)
rac_link_archive_deps(test_model_heuristics)
target_compile_features(test_model_heuristics PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_model_heuristics)
add_test(NAME model_heuristics_tests COMMAND test_model_heuristics)

# --- ToolValue <-> JSON proto-byte ABI parity tests --------------------
# Validates the 5 oneof branches (string/number/bool/array/object) that
# Swift/Kotlin/Dart/RN/Web previously hand-rolled. Single source of truth.
add_executable(test_tool_value_json test_tool_value_json.cpp)
target_include_directories(test_tool_value_json PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_tool_value_json PRIVATE rac_commons)
rac_link_archive_deps(test_tool_value_json)
target_compile_features(test_tool_value_json PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_tool_value_json)
add_test(NAME tool_value_json_tests COMMAND test_tool_value_json)

# --- Tool-calling session state machine ---------------------------
add_executable(test_tool_calling_session_proto test_tool_calling_session_proto.cpp)
target_include_directories(test_tool_calling_session_proto PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src/generated/proto
)
target_link_libraries(test_tool_calling_session_proto PRIVATE rac_commons)
rac_link_archive_deps(test_tool_calling_session_proto)
target_compile_features(test_tool_calling_session_proto PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_tool_calling_session_proto)
add_test(NAME tool_calling_session_proto_tests COMMAND test_tool_calling_session_proto)

# --- Synchronous tool-calling run loop --------------------------------
# Mirrors the session proto test setup but exercises the single-call API
# (rac_tool_calling_run_loop_proto). Verifies executor callback wiring,
# iteration cap, validation failure path, and no-tool-call completion.
add_executable(test_tool_calling_run_loop test_tool_calling_run_loop.cpp)
target_include_directories(test_tool_calling_run_loop PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src/generated/proto
)
target_link_libraries(test_tool_calling_run_loop PRIVATE rac_commons)
rac_link_archive_deps(test_tool_calling_run_loop)
target_compile_features(test_tool_calling_run_loop PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_tool_calling_run_loop)
add_test(NAME tool_calling_run_loop_tests COMMAND test_tool_calling_run_loop)

# --- tool-calling cancel ABI concurrency regression -----------
# Covers the run_loop_with_handle / run_loop_cancel / session_cancel C
# ABIs. Exercises:
#   1. cancel-during-publish: cancel fires while generate is blocked on
#      another thread; the cancel ABI returns RAC_SUCCESS concurrently and
#      the loop returns RAC_ERROR_CANCELLED in bounded time (no deadlock).
#   2. cancel-after-natural-completion: stale-handle cancel is idempotent
#      RAC_SUCCESS.
#   3. sticky cancel non-regression: step_with_result after
#      session_cancel returns RAC_ERROR_INVALID_STATE.
#   4. idempotent session cancel on stale/destroyed/zero handles.
# Designed to be TSAN-clean.
add_executable(test_tool_calling_cancel test_tool_calling_cancel.cpp)
target_include_directories(test_tool_calling_cancel PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src/generated/proto
)
target_link_libraries(test_tool_calling_cancel PRIVATE rac_commons)
rac_link_archive_deps(test_tool_calling_cancel)
target_compile_features(test_tool_calling_cancel PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_tool_calling_cancel)
add_test(NAME tool_calling_cancel_tests COMMAND test_tool_calling_cancel)

# --- Structured-output helper tests --------------------------------
add_executable(test_structured_output test_structured_output.cpp)
target_include_directories(test_structured_output PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_structured_output PRIVATE rac_commons)
rac_link_archive_deps(test_structured_output)
target_compile_features(test_structured_output PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_structured_output)
add_test(NAME structured_output_tests COMMAND test_structured_output)

# --- JSONSchema-proto -> JSON Schema text canonical-writer parity ----
# Verifies rac_structured_output_schema_to_json_proto produces byte-exact
# output matching Swift's JSONSchemaWriter
# (StructuredOutputProto+Helpers.swift) so Swift can drop its private writer.
add_executable(test_schema_to_json test_schema_to_json.cpp)
target_include_directories(test_schema_to_json PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src/generated/proto
)
target_link_libraries(test_schema_to_json PRIVATE rac_commons)
rac_link_archive_deps(test_schema_to_json)
target_compile_features(test_schema_to_json PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_schema_to_json)
add_test(NAME schema_to_json_tests COMMAND test_schema_to_json)

# --- LLM proto-byte stream dispatch test --------------
# Exercises rac::llm::dispatch_llm_stream_event() — the token → LLMStreamEvent
# → SerializeToArray → callback path that was declared. Tests synthetic
# token schedule, monotonic seq, terminal stop/error events, unregister-stops-
# dispatch. SKIP-style when RAC_HAVE_PROTOBUF is undefined.
add_executable(test_llm_stream_proto test_llm_stream_proto.cpp)
target_include_directories(test_llm_stream_proto PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_llm_stream_proto PRIVATE rac_commons)
rac_link_archive_deps(test_llm_stream_proto)
target_compile_features(test_llm_stream_proto PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_llm_stream_proto)
add_test(NAME llm_stream_proto_tests COMMAND test_llm_stream_proto)

# --- Lifecycle-owned generated-proto LLM service ABI tests ----------
add_executable(test_llm_proto_service test_llm_proto_service.cpp)
target_include_directories(test_llm_proto_service PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_llm_proto_service PRIVATE rac_commons)
rac_link_archive_deps(test_llm_proto_service)
target_compile_features(test_llm_proto_service PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_llm_proto_service)
add_test(NAME llm_proto_service_tests COMMAND test_llm_proto_service)

# --- Proto runtime activation smoke -----------------------------------------
# Catches exported proto ABI symbols that are linked but compiled into
# unavailable stubs because RAC_HAVE_PROTOBUF was not active for rac_commons.
add_executable(test_proto_runtime_smoke test_proto_runtime_smoke.cpp)
target_include_directories(test_proto_runtime_smoke PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_proto_runtime_smoke PRIVATE rac_commons)
rac_link_archive_deps(test_proto_runtime_smoke)
target_compile_features(test_proto_runtime_smoke PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_proto_runtime_smoke)
add_test(NAME proto_runtime_smoke_tests COMMAND test_proto_runtime_smoke)

# --- Unified engine plugin registry tests --------------------
# No backend dependency; all three link directly against rac_commons.
# test_engine_vtable.cpp includes the generated runanywhere.v1
# model_types.pb.h directly, which transitively pulls in
# google/protobuf/runtime_version.h. rac_commons keeps its protobuf
# include path PRIVATE (the public ABI exposes byte buffers, not
# `runanywhere::v1::*` C++ types), so the test target needs to inherit
# the include path explicitly to find the FetchContent-built headers
# on Linux runners that don't have a system protobuf installed.
add_executable(test_engine_vtable test_engine_vtable.cpp)
target_include_directories(test_engine_vtable PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${Protobuf_INCLUDE_DIRS}
)
target_link_libraries(test_engine_vtable PRIVATE rac_commons)
if(TARGET protobuf::libprotobuf)
    target_link_libraries(test_engine_vtable PRIVATE protobuf::libprotobuf)
endif()
rac_link_archive_deps(test_engine_vtable)
target_compile_features(test_engine_vtable PRIVATE cxx_std_17)
add_test(NAME engine_vtable_tests COMMAND test_engine_vtable)

add_executable(test_legacy_coexistence test_legacy_coexistence.cpp)
target_include_directories(test_legacy_coexistence PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_legacy_coexistence PRIVATE rac_commons)
rac_link_archive_deps(test_legacy_coexistence)
target_compile_features(test_legacy_coexistence PRIVATE cxx_std_17)
add_test(NAME legacy_coexistence_tests COMMAND test_legacy_coexistence)

# --- Shared C ABI proto-byte buffer ownership tests -------------------------
add_executable(test_proto_buffer test_proto_buffer.cpp)
target_include_directories(test_proto_buffer PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_proto_buffer PRIVATE rac_commons)
rac_link_archive_deps(test_proto_buffer)
target_compile_features(test_proto_buffer PRIVATE cxx_std_17)
add_test(NAME proto_buffer_tests COMMAND test_proto_buffer)

# --- rac_result_t -> RASDKError proto parity tests --------------------------
add_executable(test_result_to_proto_error test_result_to_proto_error.cpp)
target_include_directories(test_result_to_proto_error PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_result_to_proto_error PRIVATE rac_commons)
rac_link_archive_deps(test_result_to_proto_error)
target_compile_features(test_result_to_proto_error PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_result_to_proto_error)
add_test(NAME result_to_proto_error_tests COMMAND test_result_to_proto_error)

# --- Canonical SDKEvent proto-byte stream tests -----------------------------
add_executable(test_sdk_event_stream test_sdk_event_stream.cpp)
target_include_directories(test_sdk_event_stream PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_sdk_event_stream PRIVATE rac_commons)
rac_link_archive_deps(test_sdk_event_stream)
target_compile_features(test_sdk_event_stream PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_sdk_event_stream)
add_test(NAME sdk_event_stream_tests COMMAND test_sdk_event_stream)

# --- Auth manager canonical SDKEvent tests ----------------------------------
add_executable(test_auth_sdk_events test_auth_sdk_events.cpp)
target_include_directories(test_auth_sdk_events PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_auth_sdk_events PRIVATE rac_commons)
rac_link_archive_deps(test_auth_sdk_events)
target_compile_features(test_auth_sdk_events PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_auth_sdk_events)
add_test(NAME auth_sdk_event_tests COMMAND test_auth_sdk_events)

# --- Canonical two-phase SDK init ABI tests --------------------------
# Drives rac_sdk_init_phase{1,2}_proto + rac_sdk_retry_http_proto with hand
# built request bytes; verifies the SdkInitResult envelope mirrors Swift's
# Phase 1 / Phase 2 / retryHTTPSetup behaviour.
add_executable(test_sdk_init test_sdk_init.cpp)
target_include_directories(test_sdk_init PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_sdk_init PRIVATE rac_commons)
rac_link_archive_deps(test_sdk_init)
target_compile_features(test_sdk_init PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_sdk_init)
add_test(NAME sdk_init_tests COMMAND test_sdk_init)

# --- SDKEvents generated service descriptor test ----------------------------
add_executable(test_sdk_events_service_proto_abi test_sdk_events_service_proto_abi.cpp)
target_include_directories(test_sdk_events_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_sdk_events_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_sdk_events_service_proto_abi)
target_compile_features(test_sdk_events_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_sdk_events_service_proto_abi)
add_test(NAME sdk_events_service_proto_abi_tests COMMAND test_sdk_events_service_proto_abi)

# --- ToolCalling generated service descriptor test --------------------------
add_executable(test_tool_calling_service_proto_abi test_tool_calling_service_proto_abi.cpp)
target_include_directories(test_tool_calling_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_tool_calling_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_tool_calling_service_proto_abi)
target_compile_features(test_tool_calling_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_tool_calling_service_proto_abi)
add_test(NAME tool_calling_service_proto_abi_tests COMMAND test_tool_calling_service_proto_abi)

# --- StructuredOutput generated service descriptor test ---------------------
add_executable(test_structured_output_service_proto_abi test_structured_output_service_proto_abi.cpp)
target_include_directories(test_structured_output_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_structured_output_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_structured_output_service_proto_abi)
target_compile_features(test_structured_output_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_structured_output_service_proto_abi)
add_test(NAME structured_output_service_proto_abi_tests COMMAND test_structured_output_service_proto_abi)

# --- Model registry proto-byte ABI tests -------------------------------------
# Exercises register/update/get/list/remove using serialized ModelInfo and
# ModelInfoList bytes. SKIP-style fallback when Protobuf is unavailable.
add_executable(test_model_registry_proto test_model_registry_proto.cpp)
target_include_directories(test_model_registry_proto PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_registry_proto PRIVATE rac_commons)
rac_link_archive_deps(test_model_registry_proto)
target_compile_features(test_model_registry_proto PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_model_registry_proto)
add_test(NAME model_registry_proto_tests COMMAND test_model_registry_proto)

# --- ModelRegistry generated service descriptor test -------------------------
add_executable(test_model_registry_service_proto_abi test_model_registry_service_proto_abi.cpp)
target_include_directories(test_model_registry_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_registry_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_model_registry_service_proto_abi)
target_compile_features(test_model_registry_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_model_registry_service_proto_abi)
add_test(NAME model_registry_service_proto_abi_tests COMMAND test_model_registry_service_proto_abi)

# --- Model assignment proto-byte refresh/cache tests -------------------------
# Exercises ModelRegistryRefreshRequest/Result over the assignment transport
# callback boundary. SKIP-style fallback when Protobuf is unavailable.
add_executable(test_model_assignment_proto test_model_assignment_proto.cpp)
target_include_directories(test_model_assignment_proto PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_assignment_proto PRIVATE rac_commons)
rac_link_archive_deps(test_model_assignment_proto)
target_compile_features(test_model_assignment_proto PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_model_assignment_proto)
add_test(NAME model_assignment_proto_tests COMMAND test_model_assignment_proto)

# --- Model format/artifact inference proto ABI tests -------------------------
# Exercises URL → ModelFormat / ArtifactType inference via serialized generated
# proto bytes. Replaces the per-SDK Dart/Kotlin helpers.
add_executable(test_model_format_infer_proto test_model_format_infer_proto.cpp)
target_include_directories(test_model_format_infer_proto PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_format_infer_proto PRIVATE rac_commons)
rac_link_archive_deps(test_model_format_infer_proto)
target_compile_features(test_model_format_infer_proto PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_model_format_infer_proto)
add_test(NAME model_format_infer_proto_tests COMMAND test_model_format_infer_proto)

# --- Canonical RAModelInfo factory parity tests ----------------------
# Exercises rac_model_info_make_proto — the commons-owned factory that
# replaces Swift's ModelTypes+Artifacts.swift::RAModelInfo.make. Verifies
# the 18-field defaulting logic plus the rac_path_is_non_empty_directory
# probe (callback path + file_list_directory fallback).
add_executable(test_model_info_make_proto test_model_info_make_proto.cpp)
target_include_directories(test_model_info_make_proto PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_info_make_proto PRIVATE rac_commons)
rac_link_archive_deps(test_model_info_make_proto)
target_compile_features(test_model_info_make_proto PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_model_info_make_proto)
add_test(NAME model_info_make_proto_tests COMMAND test_model_info_make_proto)

# --- Register model from URL parity tests ----------------------------
# Exercises rac_register_model_from_url_proto — the canonical
# RegisterModelFromUrlRequest → save → ModelInfo entry point. Composes
# rac_model_info_make_proto with the existing registry persistence
# path. End-to-end test: call the new ABI; round-trip via
# rac_model_registry_get_proto for the returned id; verify equality.
add_executable(test_register_model_from_url test_register_model_from_url.cpp)
target_include_directories(test_register_model_from_url PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_register_model_from_url PRIVATE rac_commons)
rac_link_archive_deps(test_register_model_from_url)
target_compile_features(test_register_model_from_url PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_register_model_from_url)
add_test(NAME register_model_from_url_tests COMMAND test_register_model_from_url)

# --- Artifact ExpectedModelFiles parity tests ------------------------
# Exercises rac_artifact_expected_files_proto — the commons-owned port of
# Swift's RAModelInfo.expectedArtifactFiles + OneOf_Artifact.expectedFiles.
# Verifies every artifact subtype (single_file/archive/multi_file) plus the
# top-level expected_files short-circuit and the empty/built_in/custom_strategy
# fallback paths.
add_executable(test_artifact_helpers_proto test_artifact_helpers_proto.cpp)
target_include_directories(test_artifact_helpers_proto PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_artifact_helpers_proto PRIVATE rac_commons)
rac_link_archive_deps(test_artifact_helpers_proto)
target_compile_features(test_artifact_helpers_proto PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_artifact_helpers_proto)
add_test(NAME artifact_helpers_proto_tests COMMAND test_artifact_helpers_proto)

# --- STT/TTS configuration defaults parity tests --------------------
# Exercises rac_stt_configuration_defaults_proto / rac_tts_configuration_defaults_proto
# — the commons-owned ports of Swift's RA{STT,TTS}Configuration.defaults()
# helpers. Each test decodes the returned proto bytes and pins the canonical
# default values so any drift between commons and the Swift source-of-truth
# fails CI.
add_executable(test_stt_config_defaults test_stt_config_defaults.cpp)
target_include_directories(test_stt_config_defaults PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_stt_config_defaults PRIVATE rac_commons)
rac_link_archive_deps(test_stt_config_defaults)
target_compile_features(test_stt_config_defaults PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_stt_config_defaults)
add_test(NAME stt_config_defaults_tests COMMAND test_stt_config_defaults)

add_executable(test_tts_config_defaults test_tts_config_defaults.cpp)
target_include_directories(test_tts_config_defaults PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_tts_config_defaults PRIVATE rac_commons)
rac_link_archive_deps(test_tts_config_defaults)
target_compile_features(test_tts_config_defaults PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_tts_config_defaults)
add_test(NAME tts_config_defaults_tests COMMAND test_tts_config_defaults)

# Shared SHA-256 foundation util — known-answer + streaming parity.
add_executable(test_sha256 test_sha256.cpp)
target_include_directories(test_sha256 PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_sha256 PRIVATE rac_commons)
rac_link_archive_deps(test_sha256)
target_compile_features(test_sha256 PRIVATE cxx_std_17)
add_test(NAME sha256_tests COMMAND test_sha256)

# RAG symbols are folded into rac_commons only when the RAG OBJECT target is
# enabled, so guard these tests the same way as test_advanced_modality_proto_abi.
if(TARGET rac_backend_rag)
    # Direct ctest for the GraphScheduler-driven RAG pipeline
    # (rag_pipeline_graph.cpp). Exercises run_rag_query() input validation
    # and the RAGTokenSink cancel contract.
    add_executable(test_rag_pipeline_graph test_rag_pipeline_graph.cpp)
    target_include_directories(test_rag_pipeline_graph PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src
    )
    target_link_libraries(test_rag_pipeline_graph PRIVATE rac_commons)
    rac_link_archive_deps(test_rag_pipeline_graph)
    target_compile_features(test_rag_pipeline_graph PRIVATE cxx_std_17)
    rac_test_define_have_protobuf(test_rag_pipeline_graph)
    add_test(NAME rag_pipeline_graph_tests COMMAND test_rag_pipeline_graph)

    # Deterministic unit test for rerank score parsing + reordering (no LLM).
    add_executable(test_rag_rerank test_rag_rerank.cpp)
    target_include_directories(test_rag_rerank PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src
    )
    target_link_libraries(test_rag_rerank PRIVATE rac_commons)
    rac_link_archive_deps(test_rag_rerank)
    target_compile_features(test_rag_rerank PRIVATE cxx_std_17)
    rac_test_define_have_protobuf(test_rag_rerank)
    add_test(NAME rag_rerank_tests COMMAND test_rag_rerank)

    # Deterministic unit test for N-way RRF fusion + query-variant parsing.
    add_executable(test_rag_fusion test_rag_fusion.cpp)
    target_include_directories(test_rag_fusion PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src
    )
    target_link_libraries(test_rag_fusion PRIVATE rac_commons)
    rac_link_archive_deps(test_rag_fusion)
    target_compile_features(test_rag_fusion PRIVATE cxx_std_17)
    rac_test_define_have_protobuf(test_rag_fusion)
    add_test(NAME rag_fusion_tests COMMAND test_rag_fusion)
endif()

# End-to-end RAG test with real models (ONNX embeddings + GGUF LLM). SKIPs
# gracefully when the models are absent, so it is safe to register whenever the
# RAG, llamacpp and onnx backends are all built.
if(TARGET rac_backend_rag AND RAC_BACKEND_LLAMACPP AND RAC_BACKEND_ONNX)
    add_executable(test_rag_e2e test_rag_e2e.cpp)
    target_include_directories(test_rag_e2e PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src
    )
    target_link_libraries(test_rag_e2e PRIVATE rac_commons rac_backend_llamacpp rac_backend_onnx)
    rac_link_archive_deps(test_rag_e2e)
    target_compile_features(test_rag_e2e PRIVATE cxx_std_17)
    rac_test_define_have_protobuf(test_rag_e2e)
    target_compile_definitions(test_rag_e2e PRIVATE
        RAG_SAMPLE_DOC_PATH="${CMAKE_CURRENT_SOURCE_DIR}/data/rag_sample.md")
    add_test(NAME rag_e2e_tests COMMAND test_rag_e2e)
endif()

# --- Per-framework "is this file a model file?" parity tests -----------------
# Exercises rac_model_format_for_framework() — the canonical commons helper
# that replaced the per-SDK rac_discovery_callbacks_t.is_model_file callback
# (Swift's racIsModelFile). Pure C ABI test, no protobuf required.
add_executable(test_model_format_for_framework test_model_format_for_framework.cpp)
target_include_directories(test_model_format_for_framework PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_format_for_framework PRIVATE rac_commons)
rac_link_archive_deps(test_model_format_for_framework)
target_compile_features(test_model_format_for_framework PRIVATE cxx_std_17)
add_test(NAME model_format_for_framework_tests COMMAND test_model_format_for_framework)

# --- Canonical model-id-from-URL parity tests --------------------------------
# Exercises rac_model_id_from_url() — the commons-owned port of Swift's
# RunAnywhere.generateModelId(fromURL:) (Storage.swift). Each platform SDK's
# generateModelId helper now delegates to this function, so the parity test
# locks every SDK to the same byte-exact output. Pure C ABI test, no protobuf
# required.
add_executable(test_model_id_from_url test_model_id_from_url.cpp)
target_include_directories(test_model_id_from_url PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_id_from_url PRIVATE rac_commons)
rac_link_archive_deps(test_model_id_from_url)
target_compile_features(test_model_id_from_url PRIVATE cxx_std_17)
add_test(NAME model_id_from_url_tests COMMAND test_model_id_from_url)

# --- Canonical wire-string / display / analytics accessor parity tests -------
# Exercises rac_model_format_wire_string,
# rac_inference_framework_wire_string / display_name / analytics_key and the
# inverse rac_inference_framework_from_string. Replaces the ~400 LOC of Swift
# switch tables in ModelTypes.swift with a commons-owned source of truth.
# Pure C ABI test, no protobuf required.
add_executable(test_model_string_accessors test_model_string_accessors.cpp)
target_include_directories(test_model_string_accessors PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_string_accessors PRIVATE rac_commons)
rac_link_archive_deps(test_model_string_accessors)
target_compile_features(test_model_string_accessors PRIVATE cxx_std_17)
add_test(NAME model_string_accessors_tests COMMAND test_model_string_accessors)

# --- Proto enum ↔ C enum mapper parity tests --------------------------
# Exercises rac_inference_framework_from/to_proto, rac_model_category_*,
# rac_model_format_*, rac_model_source_* and rac_archive_type_*. Pure C ABI,
# no protobuf required.
add_executable(test_model_types_mappers test_model_types_mappers.cpp)
target_include_directories(test_model_types_mappers PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_types_mappers PRIVATE rac_commons)
rac_link_archive_deps(test_model_types_mappers)
target_compile_features(test_model_types_mappers PRIVATE cxx_std_17)
add_test(NAME model_types_mappers_tests COMMAND test_model_types_mappers)

# --- Model lifecycle proto-byte ABI tests ------------------------------------
# Exercises ModelLoad/Unload/CurrentModel and ComponentLifecycleSnapshot over
# serialized generated proto bytes. SKIP-style fallback when Protobuf is
# unavailable.
add_executable(test_model_lifecycle_proto test_model_lifecycle_proto.cpp)
target_include_directories(test_model_lifecycle_proto PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_model_lifecycle_proto PRIVATE rac_commons)
rac_link_archive_deps(test_model_lifecycle_proto)
target_compile_features(test_model_lifecycle_proto PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_model_lifecycle_proto)
add_test(NAME model_lifecycle_proto_tests COMMAND test_model_lifecycle_proto)

# --- Non-LLM lifecycle-owned generated-proto operation ABI tests -------------
add_executable(test_nonllm_lifecycle_proto_abi test_nonllm_lifecycle_proto_abi.cpp)
target_include_directories(test_nonllm_lifecycle_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_nonllm_lifecycle_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_nonllm_lifecycle_proto_abi)
target_compile_features(test_nonllm_lifecycle_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_nonllm_lifecycle_proto_abi)
add_test(NAME nonllm_lifecycle_proto_abi_tests COMMAND test_nonllm_lifecycle_proto_abi)

# --- Advanced modality proto-byte ABI tests ---------------------------------
# Exercises VLM, embeddings, RAG, LoRA, and diffusion service boundaries over
# serialized generated protos. RAG symbols are folded into rac_commons only when
# the RAG object target is enabled, so keep this focused test behind that gate.
if(TARGET rac_backend_rag)
    add_executable(test_advanced_modality_proto_abi test_advanced_modality_proto_abi.cpp)
    target_include_directories(test_advanced_modality_proto_abi PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_advanced_modality_proto_abi PRIVATE rac_commons)
    rac_link_archive_deps(test_advanced_modality_proto_abi)
    target_compile_features(test_advanced_modality_proto_abi PRIVATE cxx_std_17)
    rac_test_define_have_protobuf(test_advanced_modality_proto_abi)
    add_test(NAME advanced_modality_proto_abi_tests COMMAND test_advanced_modality_proto_abi)
endif()

# --- Diffusion generated service descriptor test ----------------------------
add_executable(test_diffusion_service_proto_abi test_diffusion_service_proto_abi.cpp)
target_include_directories(test_diffusion_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_diffusion_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_diffusion_service_proto_abi)
target_compile_features(test_diffusion_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_diffusion_service_proto_abi)
add_test(NAME diffusion_service_proto_abi_tests COMMAND test_diffusion_service_proto_abi)

# --- Embeddings generated service descriptor test ---------------------------
add_executable(test_embeddings_service_proto_abi test_embeddings_service_proto_abi.cpp)
target_include_directories(test_embeddings_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_embeddings_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_embeddings_service_proto_abi)
target_compile_features(test_embeddings_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_embeddings_service_proto_abi)
add_test(NAME embeddings_service_proto_abi_tests COMMAND test_embeddings_service_proto_abi)

# --- VLM generated service descriptor test ----------------------------------
add_executable(test_vlm_service_proto_abi test_vlm_service_proto_abi.cpp)
target_include_directories(test_vlm_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_vlm_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_vlm_service_proto_abi)
target_compile_features(test_vlm_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_vlm_service_proto_abi)
add_test(NAME vlm_service_proto_abi_tests COMMAND test_vlm_service_proto_abi)

# --- RAG generated service descriptor test ----------------------------------
add_executable(test_rag_service_proto_abi test_rag_service_proto_abi.cpp)
target_include_directories(test_rag_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_rag_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_rag_service_proto_abi)
target_compile_features(test_rag_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_rag_service_proto_abi)
add_test(NAME rag_service_proto_abi_tests COMMAND test_rag_service_proto_abi)

# --- LoRA generated service descriptor test ---------------------------------
add_executable(test_lora_service_proto_abi test_lora_service_proto_abi.cpp)
target_include_directories(test_lora_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_lora_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_lora_service_proto_abi)
target_compile_features(test_lora_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_lora_service_proto_abi)
add_test(NAME lora_service_proto_abi_tests COMMAND test_lora_service_proto_abi)

# --- Lifecycle-aware LoRA proto ABI tests -----------------------------
# Pins the v2 contract: each rac_lora_*_proto resolves its backend through
# the model-lifecycle service (no rac_handle_t llm_component arg). Covers the
# COMPONENT_NOT_READY guard plus apply/list/state/remove against a
# lifecycle-loaded mock backend, mirroring the JNI / Swift call sites the
# SDK bridges already use.
add_executable(test_lora_proto_abi test_lora_proto_abi.cpp)
target_include_directories(test_lora_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_lora_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_lora_proto_abi)
target_compile_features(test_lora_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_lora_proto_abi)
add_test(NAME lora_proto_abi_tests COMMAND test_lora_proto_abi)

# --- Storage generated service descriptor test ------------------------------
add_executable(test_storage_service_proto_abi test_storage_service_proto_abi.cpp)
target_include_directories(test_storage_service_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_storage_service_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_storage_service_proto_abi)
target_compile_features(test_storage_service_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_storage_service_proto_abi)
add_test(NAME storage_service_proto_abi_tests COMMAND test_storage_service_proto_abi)

# --- Speech/VAD/voice-agent proto-byte ABI tests -----------------------------
# Exercises STT transcribe/partials, TTS voices/synthesize/stream, VAD
# process/statistics/activity, and voice-agent turn events over serialized
# generated proto bytes. SKIP-style fallback when Protobuf is unavailable.
add_executable(test_speech_proto_abi test_speech_proto_abi.cpp)
target_include_directories(test_speech_proto_abi PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_speech_proto_abi PRIVATE rac_commons)
rac_link_archive_deps(test_speech_proto_abi)
target_compile_features(test_speech_proto_abi PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_speech_proto_abi)
add_test(NAME speech_proto_abi_tests COMMAND test_speech_proto_abi)

# --- generated STT/VAD stream-event payload tests -------
add_executable(test_stt_vad_stream_events test_stt_vad_stream_events.cpp)
target_include_directories(test_stt_vad_stream_events PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_stt_vad_stream_events PRIVATE rac_commons)
rac_link_archive_deps(test_stt_vad_stream_events)
target_compile_features(test_stt_vad_stream_events PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_stt_vad_stream_events)
add_test(NAME stt_vad_stream_event_tests COMMAND test_stt_vad_stream_events)

# --- Storage analyzer proto-byte ABI tests -----------------------------------
# Exercises StorageInfoResult, StorageAvailabilityResult, StorageDeletePlan, and
# StorageDeleteResult bytes. SKIP-style fallback when Protobuf is unavailable.
add_executable(test_storage_analyzer_proto test_storage_analyzer_proto.cpp)
target_include_directories(test_storage_analyzer_proto PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_storage_analyzer_proto PRIVATE rac_commons)
rac_link_archive_deps(test_storage_analyzer_proto)
target_compile_features(test_storage_analyzer_proto PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_storage_analyzer_proto)
add_test(NAME storage_analyzer_proto_tests COMMAND test_storage_analyzer_proto)

# ProviderRegistry<T> template unit tests (always built — no backend dep).
add_executable(test_provider_registry test_provider_registry.cpp)
target_include_directories(test_provider_registry PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_provider_registry PRIVATE rac_commons)
rac_link_archive_deps(test_provider_registry)
target_compile_features(test_provider_registry PRIVATE cxx_std_17)
add_test(NAME provider_registry_tests COMMAND test_provider_registry)

# L1 runtime-plugin registry tests (always built — no backend dep).
add_executable(test_runtime_registry test_runtime_registry.cpp)
target_include_directories(test_runtime_registry PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_runtime_registry PRIVATE rac_commons)
rac_link_archive_deps(test_runtime_registry)
target_compile_features(test_runtime_registry PRIVATE cxx_std_17)
add_test(NAME runtime_registry_tests COMMAND test_runtime_registry)

# Runtime loader smoke test — exercises the RAC_STATIC_RUNTIME_REGISTER
# path and the rac_runtime_entry_<name> symbol convention that the future
# dlopen loader will share with the engine-plugin loader.
add_executable(test_runtime_loader test_runtime_loader.cpp)
target_include_directories(test_runtime_loader PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_runtime_loader PRIVATE rac_commons)
rac_link_archive_deps(test_runtime_loader)
target_compile_features(test_runtime_loader PRIVATE cxx_std_17)
add_test(NAME runtime_loader_tests COMMAND test_runtime_loader)

# CPU runtime session dispatch. Tests the built-in CPU runtime's
# provider hook without depending on a real GGUF model or llama.cpp.
add_executable(test_runtime_cpu_session test_runtime_cpu_session.cpp)
target_include_directories(test_runtime_cpu_session PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_runtime_cpu_session PRIVATE rac_commons)
rac_link_archive_deps(test_runtime_cpu_session)
target_compile_features(test_runtime_cpu_session PRIVATE cxx_std_17)
add_test(NAME runtime_cpu_session_tests COMMAND test_runtime_cpu_session)

# Anti-regression that an engine create path can be wired to the
# runtime session vtable instead of allocating its own private session.
add_executable(test_engine_uses_runtime test_engine_uses_runtime.cpp)
target_include_directories(test_engine_uses_runtime PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_engine_uses_runtime PRIVATE rac_commons)
rac_link_archive_deps(test_engine_uses_runtime)
target_compile_features(test_engine_uses_runtime PRIVATE cxx_std_17)
add_test(NAME engine_uses_runtime_tests COMMAND test_engine_uses_runtime)

# Static registration test (always built — exercises the
# RAC_STATIC_PLUGIN_REGISTER macro independently of the dlopen path).
add_executable(test_static_registration test_static_registration.cpp)
target_include_directories(test_static_registration PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_static_registration PRIVATE rac_commons)
rac_link_archive_deps(test_static_registration)
target_compile_features(test_static_registration PRIVATE cxx_std_17)
add_test(NAME static_registration_tests COMMAND test_static_registration)

# Dynamic loader tests — only meaningful in SHARED-plugins
# mode. iOS / WASM / RAC_STATIC_PLUGINS=ON skip these targets entirely.
if(NOT RAC_STATIC_PLUGINS)
    # Two fixture libraries from one source — the BAD_ABI variant flips a
    # compile-time toggle so its metadata.abi_version equals host + 99.
    # Fixtures are minimal .so's that do NOT link rac_commons (they exercise
    # the dlopen / ABI-version paths in isolation), so the include path has
    # to be spelled out explicitly — ${CMAKE_SOURCE_DIR} refers to the repo
    # root when building via the top-level preset, not to commons.
    set(_RAC_TEST_PLUGIN_INCLUDE_DIR
        "${CMAKE_CURRENT_SOURCE_DIR}/../include")

    add_library(rac_test_plugin SHARED fixtures/rac_test_plugin.cpp)
    set_target_properties(rac_test_plugin PROPERTIES
        OUTPUT_NAME runanywhere_test_plugin
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden)
    target_include_directories(rac_test_plugin PRIVATE ${_RAC_TEST_PLUGIN_INCLUDE_DIR})
    target_compile_features(rac_test_plugin PRIVATE cxx_std_17)

    add_library(rac_test_plugin_bad_abi SHARED fixtures/rac_test_plugin.cpp)
    set_target_properties(rac_test_plugin_bad_abi PROPERTIES
        OUTPUT_NAME runanywhere_test_plugin_bad_abi
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden)
    target_include_directories(rac_test_plugin_bad_abi PRIVATE ${_RAC_TEST_PLUGIN_INCLUDE_DIR})
    target_compile_definitions(rac_test_plugin_bad_abi PRIVATE RAC_TEST_PLUGIN_FORCE_BAD_ABI=1)
    target_compile_features(rac_test_plugin_bad_abi PRIVATE cxx_std_17)

    # Path the test can dlopen at runtime — uses generator expression so it
    # works in single- and multi-config generators.
    set(_GAP03_FIXTURE_GOOD "$<TARGET_FILE:rac_test_plugin>")
    set(_GAP03_FIXTURE_BAD  "$<TARGET_FILE:rac_test_plugin_bad_abi>")

    add_executable(test_plugin_loader test_plugin_loader.cpp)
    target_include_directories(test_plugin_loader PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_loader PRIVATE rac_commons)
    rac_link_archive_deps(test_plugin_loader)
    target_compile_features(test_plugin_loader PRIVATE cxx_std_17)
    target_compile_definitions(test_plugin_loader PRIVATE
        "RAC_TEST_PLUGIN_PATH=\"${_GAP03_FIXTURE_GOOD}\"")
    add_dependencies(test_plugin_loader rac_test_plugin)
    add_test(NAME plugin_loader_tests COMMAND test_plugin_loader)

    add_executable(test_plugin_loader_abi_mismatch test_plugin_loader_abi_mismatch.cpp)
    target_include_directories(test_plugin_loader_abi_mismatch PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_loader_abi_mismatch PRIVATE rac_commons)
    rac_link_archive_deps(test_plugin_loader_abi_mismatch)
    target_compile_features(test_plugin_loader_abi_mismatch PRIVATE cxx_std_17)
    target_compile_definitions(test_plugin_loader_abi_mismatch PRIVATE
        "RAC_TEST_PLUGIN_BAD_ABI_PATH=\"${_GAP03_FIXTURE_BAD}\"")
    add_dependencies(test_plugin_loader_abi_mismatch rac_test_plugin_bad_abi)
    add_test(NAME plugin_loader_abi_mismatch_tests COMMAND test_plugin_loader_abi_mismatch)

    add_executable(test_plugin_loader_double_load test_plugin_loader_double_load.cpp)
    target_include_directories(test_plugin_loader_double_load PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_loader_double_load PRIVATE rac_commons)
    rac_link_archive_deps(test_plugin_loader_double_load)
    target_compile_features(test_plugin_loader_double_load PRIVATE cxx_std_17)
    target_compile_definitions(test_plugin_loader_double_load PRIVATE
        "RAC_TEST_PLUGIN_PATH=\"${_GAP03_FIXTURE_GOOD}\"")
    add_dependencies(test_plugin_loader_double_load rac_test_plugin)
    add_test(NAME plugin_loader_double_load_tests COMMAND test_plugin_loader_double_load)
endif()

# Per-backend plugin entry tests — only built when the respective backend is on.
if(RAC_BACKEND_LLAMACPP AND TARGET rac_backend_llamacpp)
    add_executable(test_plugin_entry_llamacpp test_plugin_entry_llamacpp.cpp)
    target_include_directories(test_plugin_entry_llamacpp PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_entry_llamacpp PRIVATE rac_commons rac_backend_llamacpp)
    rac_link_archive_deps(test_plugin_entry_llamacpp)
    target_compile_features(test_plugin_entry_llamacpp PRIVATE cxx_std_17)
    add_test(NAME plugin_entry_llamacpp_tests COMMAND test_plugin_entry_llamacpp)
endif()

if(RAC_BACKEND_ONNX AND TARGET rac_backend_onnx)
    add_executable(test_plugin_entry_onnx test_plugin_entry_onnx.cpp)
    target_include_directories(test_plugin_entry_onnx PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_entry_onnx PRIVATE rac_commons rac_backend_onnx)
    rac_link_archive_deps(test_plugin_entry_onnx)
    target_compile_features(test_plugin_entry_onnx PRIVATE cxx_std_17)
    add_test(NAME plugin_entry_onnx_tests COMMAND test_plugin_entry_onnx)
endif()

# Note: sherpa plugin-entry test is wired in the root CMakeLists.txt (alongside
# other engine tests) because rac_backend_sherpa is built by engines/ which is
# configured after sdk/runanywhere-commons/, so the target does not exist yet
# when this file runs in a root-level build.

if(APPLE AND RAC_BACKEND_COREML AND TARGET rac_backend_coreml)
    add_executable(test_diffusion_coreml_generate test_diffusion_coreml_generate.cpp)
    target_include_directories(test_diffusion_coreml_generate PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/engines/coreml
    )
    target_link_libraries(test_diffusion_coreml_generate PRIVATE
        rac_commons
        rac_backend_coreml
    )
    rac_link_archive_deps(test_diffusion_coreml_generate)
    target_compile_features(test_diffusion_coreml_generate PRIVATE cxx_std_17)
    add_test(NAME diffusion_coreml_generate_tests COMMAND test_diffusion_coreml_generate)
endif()

# --- test_core: Always built (no backend dependency) ---
add_executable(test_core test_core.cpp)
target_include_directories(test_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_core PRIVATE rac_commons)
rac_link_archive_deps(test_core)
target_compile_features(test_core PRIVATE cxx_std_20)
add_test(NAME core_tests COMMAND test_core --run-all)

# --- test_extraction: Always built (no backend dependency) ---
add_executable(test_extraction test_extraction.cpp)
target_include_directories(test_extraction PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_extraction PRIVATE rac_commons)
rac_link_archive_deps(test_extraction)
target_compile_features(test_extraction PRIVATE cxx_std_17)
add_test(NAME extraction_tests COMMAND test_extraction --run-all)

# --- program("gzip -d") fallback regression
# Verifies rac_extract_archive_native() works on tar.gz via the in-process
# zlib gzip filter ONLY — i.e. without ever fork/exec'ing /usr/bin/gzip.
# This is the iOS sandbox failure mode (the sandbox blocks fork+exec), so the
# test runs with PATH cleared on POSIX to mechanically prove no subprocess
# is invoked. See comments in test_extraction_no_program_fallback.cpp.
add_executable(test_extraction_no_program_fallback test_extraction_no_program_fallback.cpp)
target_include_directories(test_extraction_no_program_fallback PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_extraction_no_program_fallback PRIVATE rac_commons)
rac_link_archive_deps(test_extraction_no_program_fallback)
target_compile_features(test_extraction_no_program_fallback PRIVATE cxx_std_17)
add_test(NAME extraction_no_program_fallback_tests
         COMMAND test_extraction_no_program_fallback --run-all)

# --- libarchive zlib link assertion.
# An earlier fix corrected iOS slices but the Web lane
# shipped an Emscripten WASM that still had the libarchive `program("gzip -d")`
# fallback registered (HAVE_ZLIB_H undefined). This test asserts the in-process
# gzip/bzip2/xz filters succeed at registration time and that opening a canned
# tar.gz works — both surfaces fail when libarchive lost zlib at build time.
# Complements test_extraction_no_program_fallback by exercising libarchive's
# low-level filter API directly so a regression points at build-time
# misconfiguration rather than an ABI change.
add_executable(test_libarchive_zlib_linked test_libarchive_zlib_linked.cpp)
target_include_directories(test_libarchive_zlib_linked PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${libarchive_SOURCE_DIR}/libarchive
    ${libarchive_BINARY_DIR}
)
target_link_libraries(test_libarchive_zlib_linked PRIVATE rac_commons)
rac_link_archive_deps(test_libarchive_zlib_linked)
target_compile_features(test_libarchive_zlib_linked PRIVATE cxx_std_17)
add_test(NAME libarchive_zlib_linked_tests
         COMMAND test_libarchive_zlib_linked --run-all)

# --- rac_http_client C ABI tests ------------------
# These were written against the old libcurl-backed client — they drove a
# loopback HTTP/1.1 server and relied on libcurl to actually send the bytes.
# Libcurl was deleted. The C ABI now dispatches to whatever platform
# transport each SDK registers (OkHttp / URLSession / dart:io / fetch). To
# run these end-to-end the test harness has to register its own
# rac_http_transport_ops_t adapter. test_http_download does this and is
# registered with ctest; test_http_client still only compiles until its
# request/response adapter coverage is ported.
# Unix-only (the loopback server uses POSIX sockets); Windows coverage
# tracked as follow-up (winsock wrapper).
if(UNIX)
    add_executable(test_http_client test_http_client.cpp)
    target_include_directories(test_http_client PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_http_client PRIVATE rac_commons)
    rac_link_archive_deps(test_http_client)
    target_compile_features(test_http_client PRIVATE cxx_std_17)
    # Not registered with ctest — needs a test-side rac_http_transport
    # adapter (follow-up task). Uncomment add_test once ported.
    # add_test(NAME http_client_tests COMMAND test_http_client)

    # Higher-level runner that drives rac_http_download_execute —
    # happy path / checksum / cancel / resume / 404. Also Unix-only.
    add_executable(test_http_download test_http_download.cpp)
    target_include_directories(test_http_download PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_http_download PRIVATE rac_commons)
    rac_link_archive_deps(test_http_download)
    target_compile_features(test_http_download PRIVATE cxx_std_17)
    add_test(NAME http_download_tests COMMAND test_http_download)
endif()

# --- Rac_http_request_set_upsert_mode parity test ---------------
# Pure ABI / dispatch test — registers a stub rac_http_transport_ops_t,
# arms the upsert flag, and verifies the URL/header rewrite the SDKs rely
# on. No sockets, so it builds on every platform.
add_executable(test_http_upsert_mode test_http_upsert_mode.cpp)
target_include_directories(test_http_upsert_mode PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_http_upsert_mode PRIVATE rac_commons)
rac_link_archive_deps(test_http_upsert_mode)
target_compile_features(test_http_upsert_mode PRIVATE cxx_std_17)
add_test(NAME http_upsert_mode_tests COMMAND test_http_upsert_mode)

# --- Rac_http_default_headers parity test ----------------------
# Pure ABI test — verifies the canonical default-header list matches
# Swift's HTTPClientAdapter.defaultHeaders content (sans X-Platform),
# returns the same static-array pointer across calls, and rejects NULL
# out-pointers.
add_executable(test_http_default_headers test_http_default_headers.cpp)
target_include_directories(test_http_default_headers PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_http_default_headers PRIVATE rac_commons)
rac_link_archive_deps(test_http_default_headers)
target_compile_features(test_http_default_headers PRIVATE cxx_std_17)
add_test(NAME http_default_headers_tests COMMAND test_http_default_headers --run-all)

# --- test_download_orchestrator: Always built (no backend dependency) ---
add_executable(test_download_orchestrator test_download_orchestrator.cpp)
target_include_directories(test_download_orchestrator PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_download_orchestrator PRIVATE rac_commons)
rac_link_archive_deps(test_download_orchestrator)
target_compile_features(test_download_orchestrator PRIVATE cxx_std_17)
rac_test_define_have_protobuf(test_download_orchestrator)
add_test(NAME download_orchestrator_tests COMMAND test_download_orchestrator --run-all)

# --- Sherpa-ONNX speech tests (VAD, STT, TTS, WakeWord) ---
# Engine-independence refactor: tests link rac_backend_sherpa
# (which owns the speech ops) and depend on rac_backend_onnx only for the
# ONNX-named typedefs used in their config defaults. The engines/sherpa/
# include path exposes the public sherpa function declarations.
if(RAC_BACKEND_ONNX AND RAC_BACKEND_SHERPA AND RAC_SHERPA_ONNX_AVAILABLE)
    # VAD test
    add_executable(test_vad test_vad.cpp)
    target_include_directories(test_vad PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/engines/sherpa
    )
    target_link_libraries(test_vad PRIVATE rac_commons rac_backend_onnx rac_backend_sherpa)
    target_compile_features(test_vad PRIVATE cxx_std_20)
    add_test(NAME vad_tests COMMAND test_vad --run-all)

    # STT test
    add_executable(test_stt test_stt.cpp)
    target_include_directories(test_stt PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/engines/sherpa
    )
    target_link_libraries(test_stt PRIVATE rac_commons rac_backend_onnx rac_backend_sherpa)
    target_compile_features(test_stt PRIVATE cxx_std_20)
    add_test(NAME stt_tests COMMAND test_stt --run-all)

    # TTS test
    add_executable(test_tts test_tts.cpp)
    target_include_directories(test_tts PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/engines/sherpa
    )
    target_link_libraries(test_tts PRIVATE rac_commons rac_backend_onnx rac_backend_sherpa)
    target_compile_features(test_tts PRIVATE cxx_std_20)
    add_test(NAME tts_tests COMMAND test_tts --run-all)

    # WakeWord test is temporarily disabled: the legacy rac_wakeword_onnx.h API
    # was removed, and wake-word coverage needs to migrate to the current
    # voice-agent/VAD ingress APIs before it can be part of the required lane.
endif()

# --- LLM test: Requires LlamaCPP backend ---
if(RAC_BACKEND_LLAMACPP)
    add_executable(test_llm test_llm.cpp)
    target_include_directories(test_llm PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_llm PRIVATE rac_commons rac_backend_llamacpp)
    target_compile_features(test_llm PRIVATE cxx_std_20)
    add_test(NAME llm_tests COMMAND test_llm --run-all)
endif()

# --- Voice Agent real-inference test: Requires LlamaCPP + Sherpa/ONNX backends ---
if(RAC_BACKEND_LLAMACPP AND RAC_BACKEND_ONNX AND RAC_BACKEND_SHERPA AND RAC_SHERPA_ONNX_AVAILABLE)
    add_executable(test_voice_agent test_voice_agent.cpp)
    target_include_directories(test_voice_agent PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/engines/sherpa
    )
    target_link_libraries(test_voice_agent PRIVATE
        rac_commons
        rac_backend_llamacpp
        rac_backend_onnx
        rac_backend_sherpa
    )
    target_compile_features(test_voice_agent PRIVATE cxx_std_20)
    rac_test_define_have_protobuf(test_voice_agent)
    add_test(NAME voice_agent_real_inference_tests COMMAND test_voice_agent --run-all)
endif()

# --- macOS RPATH for ONNX Runtime dylib ---
if(APPLE)
    set(ONNX_MACOS_LIB_DIR "${RAC_COMMONS_THIRD_PARTY_DIR}/onnxruntime-macos/lib")
    foreach(test_target test_vad test_stt test_tts test_wakeword test_voice_agent)
        if(TARGET ${test_target})
            set_target_properties(${test_target} PROPERTIES
                BUILD_RPATH "${ONNX_MACOS_LIB_DIR}"
                INSTALL_RPATH "${ONNX_MACOS_LIB_DIR}"
            )
        endif()
    endforeach()
endif()

# --- Linux RPATH for Sherpa-ONNX shared libs ---
if(UNIX AND NOT APPLE)
    set(SHERPA_LINUX_LIB_DIR "${RAC_COMMONS_THIRD_PARTY_DIR}/sherpa-onnx-linux/lib")
    foreach(test_target test_vad test_stt test_tts test_wakeword test_voice_agent)
        if(TARGET ${test_target})
            set_target_properties(${test_target} PROPERTIES
                BUILD_RPATH "$ORIGIN;${SHERPA_LINUX_LIB_DIR}"
                INSTALL_RPATH "$ORIGIN;${SHERPA_LINUX_LIB_DIR}"
            )
        endif()
    endforeach()
endif()

# --- Windows: Copy DLLs to test output directory ---
# Only attempt DLL staging when the ONNX FetchContent variable is actually
# populated in this scope (set by FetchONNXRuntime.cmake when RAC_BACKEND_ONNX
# is ON). If it's unset the EXISTS check silently evaluates against
# "/lib/onnxruntime.dll" which is never what we want.
if(WIN32 AND DEFINED onnxruntime_SOURCE_DIR AND NOT "${onnxruntime_SOURCE_DIR}" STREQUAL "")
    foreach(test_target test_vad test_stt test_tts test_wakeword)
        if(TARGET ${test_target})
            if(EXISTS "${onnxruntime_SOURCE_DIR}/lib/onnxruntime.dll")
                add_custom_command(TARGET ${test_target} POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${onnxruntime_SOURCE_DIR}/lib/onnxruntime.dll"
                        $<TARGET_FILE_DIR:${test_target}>
                )
            endif()
        endif()
    endforeach()
endif()

# =============================================================================
# --- Hugging Face folder-bundle resolver (offline) ---------------------
# Pure-core resolution of HF tree-API responses into folder bundles, with
# the manifest heuristic injected as a predicate (in production it comes
# from an engine's registered bundle policy).
add_executable(test_hf_resolver_folder test_hf_resolver_folder.cpp)
target_include_directories(test_hf_resolver_folder PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)
target_link_libraries(test_hf_resolver_folder PRIVATE rac_commons)
rac_link_archive_deps(test_hf_resolver_folder)
target_compile_features(test_hf_resolver_folder PRIVATE cxx_std_20)
add_test(NAME hf_resolver_folder_tests COMMAND test_hf_resolver_folder)

# --- Bundle-policy registry + the QHexRT policy (offline) --------------
# Registry semantics plus the real QHexRT manifest predicate, included
# header-only from engines/qhexrt (public-repo source; no prebuilt engine
# needed) and driven through the generic folder resolver.
add_executable(test_bundle_policy
    test_bundle_policy.cpp
    ${CMAKE_SOURCE_DIR}/engines/qhexrt/qhexrt_device_capability.cpp
)
target_include_directories(test_bundle_policy PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
    ${CMAKE_SOURCE_DIR}/engines/qhexrt
    ${CMAKE_SOURCE_DIR}/engines/qhexrt/include
)
target_link_libraries(test_bundle_policy PRIVATE rac_commons)
rac_link_archive_deps(test_bundle_policy)
target_compile_features(test_bundle_policy PRIVATE cxx_std_20)
add_test(NAME bundle_policy_tests COMMAND test_bundle_policy)

# --- Hugging Face bearer auth (offline) --------------------------------
# Host matching + bearer composition for rac_http_hf_token_set; ports the
# retired per-platform (OkHttp) HF auth tests into commons.
add_executable(test_hf_auth test_hf_auth.cpp)
target_include_directories(test_hf_auth PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)
target_link_libraries(test_hf_auth PRIVATE rac_commons)
rac_link_archive_deps(test_hf_auth)
target_compile_features(test_hf_auth PRIVATE cxx_std_20)
add_test(NAME hf_auth_tests COMMAND test_hf_auth)

# =============================================================================
# RAG Pipeline Tests (GoogleTest)
# =============================================================================

if(RAC_BUILD_BACKENDS AND RAC_BACKEND_RAG AND NOT (WIN32 AND RAC_BUILD_SHARED))
    include(FetchContent)
    find_package(Threads REQUIRED)

    # GoogleTest pinned via sdk/runanywhere-commons/VERSIONS::GOOGLETEST_VERSION
    # so the RAG and benchmark suites below agree on a single tag (previously
    # this block requested release-1.12.1 while the benchmark block fetched
    # FetchContent dedupes by name and silently used whichever
    # declaration ran first, creating ABI-mismatch link errors).
    FetchContent_Declare(
        googletest
        GIT_REPOSITORY https://github.com/google/googletest.git
        GIT_TAG        ${GOOGLETEST_VERSION}
        GIT_SHALLOW    TRUE
    )
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(googletest)
    include(GoogleTest)

    # The rag/* tests depend on internal headers under src/features/rag/ that
    # aren't installed publicly. Resolve the path relative to this CMakeLists
    # (commons/tests) so it works whether commons is the top-level project or
    # a subdirectory of the multi-target build.
    set(_RAG_INTERNAL_INCLUDE_DIR
        "${CMAKE_CURRENT_LIST_DIR}/../src/features/rag")

    # NOTE: rag_backend_thread_safety_test.cpp targets a previous RAGBackend
    # API (`IEmbeddingProvider` + `set_embedding_provider`) that no longer
    # exists on main — the constructor now takes service handles directly.
    # The test is left in-tree but excluded from the build until it is
    # rewritten against the current API.

    # Chunker Unit Tests
    add_executable(rac_chunker_test
        chunker_test.cpp
    )
    target_include_directories(rac_chunker_test PRIVATE
        ${_RAG_INTERNAL_INCLUDE_DIR}
    )
    target_link_libraries(rac_chunker_test
        PRIVATE
        rac_commons
        Threads::Threads
        GTest::gtest_main
    )
    # Force the bundled (centralized GOOGLETEST_VERSION) gtest headers to win
    # over any system gtest (e.g. /opt/homebrew/include) — without this the
    # prebuilt libgtest_main.a (older `const char*` ABI) link-fails when the
    # test picks up the newer `std::string` header signatures. Same fix as
    # rac_benchmark_tests below.
    if(TARGET gtest)
        target_include_directories(rac_chunker_test BEFORE PRIVATE
            $<TARGET_PROPERTY:gtest,INTERFACE_INCLUDE_DIRECTORIES>
        )
    endif()
    target_compile_features(rac_chunker_test PRIVATE cxx_std_20)
    gtest_discover_tests(rac_chunker_test
        DISCOVERY_MODE PRE_TEST
    )
    add_test(
        NAME rac_chunker_test
        COMMAND rac_chunker_test
    )

    # Simple Tokenizer Unit Tests
    add_executable(rac_simple_tokenizer_test
        simple_tokenizer_test.cpp
    )
    target_link_libraries(rac_simple_tokenizer_test
        PRIVATE
        rac_commons
        Threads::Threads
        GTest::gtest_main
    )
    if(TARGET gtest)
        target_include_directories(rac_simple_tokenizer_test BEFORE PRIVATE
            $<TARGET_PROPERTY:gtest,INTERFACE_INCLUDE_DIRECTORIES>
        )
    endif()
    target_compile_features(rac_simple_tokenizer_test PRIVATE cxx_std_20)
    gtest_discover_tests(rac_simple_tokenizer_test
        DISCOVERY_MODE PRE_TEST
    )
    add_test(
        NAME rac_simple_tokenizer_test
        COMMAND rac_simple_tokenizer_test
    )
endif()
# =============================================================================
# RunAnywhere Commons - Benchmark Unit Tests (GoogleTest)
# =============================================================================

include(FetchContent)

# Pin via sdk/runanywhere-commons/VERSIONS::GOOGLETEST_VERSION so this and the
# RAG-test block above share a single FetchContent declaration. (FetchContent
# dedupes by content name; first declaration wins. Both must match.)
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG ${GOOGLETEST_VERSION}
)

# Prevent GoogleTest from overriding compiler/linker options
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(googletest)

add_executable(rac_benchmark_tests
    benchmark/test_monotonic_clock.cpp
)

target_link_libraries(rac_benchmark_tests
    PRIVATE
        rac_commons
        GTest::gtest_main
)

target_include_directories(rac_benchmark_tests
    PRIVATE
        ${CMAKE_SOURCE_DIR}/include
)

# Ensure the FetchContent-bundled gtest headers win over any system gtest
# (e.g. Homebrew's /opt/homebrew/include that protobuf/abseil drag in via
# -isystem). Without this the bundled libgtest.a (old `const char*` ABI)
# link-fails when the compile units picked up the newer `std::string`
# header signatures from the system gtest.
if(TARGET gtest)
    target_include_directories(rac_benchmark_tests BEFORE PRIVATE
        $<TARGET_PROPERTY:gtest,INTERFACE_INCLUDE_DIRECTORIES>
    )
endif()

include(GoogleTest)
gtest_discover_tests(rac_benchmark_tests)
