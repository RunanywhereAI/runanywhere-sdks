# =============================================================================
# tests/streaming/ — GAP 09 / v2 close-out parity test harness
#
# The C++ binary parity_test_cpp is the GOLDEN PRODUCER: it runs the
# deterministic event script and asserts against the committed
# fixtures/golden_events.txt fixture. Per-language tests
# (parity_test.{swift,kt,dart,ts}) live alongside and read the same
# fixture from their own SDK CI runners.
# =============================================================================

if(NOT RAC_BUILD_TESTS)
    return()
endif()

# MF-3 (AG-V3): rac_commons no longer propagates RAC_HAVE_PROTOBUF=1 via
# its PUBLIC interface (the define and `src/generated/proto/` include path
# are now PRIVATE so they do not leak through to L5 consumers). The proto-
# byte producer / parity tests under this directory are intentional internal
# consumers of that same proto path, so we re-define the macro here gated
# on the same `Protobuf_FOUND` predicate the library uses.
find_package(Protobuf QUIET)
set(_RAC_TESTS_HAVE_PROTOBUF 0)
if(Protobuf_FOUND AND EXISTS ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src/generated/proto/voice_events.pb.cc)
    set(_RAC_TESTS_HAVE_PROTOBUF 1)
endif()

# Helper: apply RAC_HAVE_PROTOBUF + include path for the now-PRIVATE proto
# headers in rac_commons. Mirrors the same predicate the library uses.
function(rac_streaming_test_define_have_protobuf target)
    if(_RAC_TESTS_HAVE_PROTOBUF)
        target_compile_definitions(${target} PRIVATE RAC_HAVE_PROTOBUF=1)
        target_include_directories(${target} PRIVATE
            ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src/generated/proto
            ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src/generated
            ${Protobuf_INCLUDE_DIRS}
        )
    endif()
endfunction()

add_executable(parity_test_cpp parity_test.cpp)
target_include_directories(parity_test_cpp PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)
target_link_libraries(parity_test_cpp PRIVATE rac_commons)
target_compile_features(parity_test_cpp PRIVATE cxx_std_17)
rac_streaming_test_define_have_protobuf(parity_test_cpp)

set(_GOLDEN_PATH "${CMAKE_SOURCE_DIR}/tests/streaming/fixtures/golden_events.txt")
file(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/tests/streaming/fixtures")

# parity_test_cpp_check: asserts the runtime-emitted event sequence matches
# the committed golden fixture. Drift in the C-side schedule fails the test.
add_test(NAME parity_test_cpp_check
         COMMAND parity_test_cpp --check "${_GOLDEN_PATH}")

# =============================================================================
# v2 close-out Phase G-2: LLM token streaming parity. Mirrors the voice
# agent pattern above — C++ binary is the golden producer; per-SDK
# consumers (scaffolded under this phase) read the same fixture.
# =============================================================================

add_executable(llm_parity_test_cpp llm_parity_test.cpp)
target_include_directories(llm_parity_test_cpp PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)
target_link_libraries(llm_parity_test_cpp PRIVATE rac_commons)
target_compile_features(llm_parity_test_cpp PRIVATE cxx_std_17)
rac_streaming_test_define_have_protobuf(llm_parity_test_cpp)

set(_LLM_GOLDEN_PATH "${CMAKE_SOURCE_DIR}/tests/streaming/fixtures/llm_golden_events.txt")

add_test(NAME llm_parity_test_cpp_check
         COMMAND llm_parity_test_cpp --check "${_LLM_GOLDEN_PATH}")

# =============================================================================
# perf_bench/ — GAP 09 #8 latency measurement harness
#
# perf_producer.cpp emits N=10000 timestamped VoiceEvent frames into a
# binary input file. Per-SDK runners (perf_bench.{swift,kt,dart,ts,rn,web})
# read it, decode, record per-event latency, then compute_percentiles.py
# aggregates the per-SDK logs into p50/p95/p99 and asserts p50 < 1ms.
# =============================================================================

set(_PERF_OUTPUT_DIR "${CMAKE_BINARY_DIR}/tests/streaming/perf_bench")

add_executable(perf_producer perf_bench/perf_producer.cpp)
target_include_directories(perf_producer PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)
target_link_libraries(perf_producer PRIVATE rac_commons)
target_compile_features(perf_producer PRIVATE cxx_std_17)
rac_streaming_test_define_have_protobuf(perf_producer)
set_target_properties(perf_producer PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${_PERF_OUTPUT_DIR}")

# Run perf_producer as a CTest case so the binary input fixture is built
# alongside the rest of the test suite. Per-SDK perf runners pick this up
# from their own CI (they're not wired here because they require the
# language toolchains, which CMake cannot assume).
add_test(NAME perf_producer_cpp
         COMMAND perf_producer
         WORKING_DIRECTORY "${_PERF_OUTPUT_DIR}")

# Optional: aggregator step when Python is available. Reports p50/p95/p99
# across whichever per-SDK perf logs are present in the perf-bench output
# directory; useful as a final-stage check in a workflow that has already
# run the per-SDK runners.
find_package(Python3 COMPONENTS Interpreter QUIET)
if(Python3_FOUND)
    add_test(NAME perf_aggregate
             COMMAND ${Python3_EXECUTABLE}
                     ${CMAKE_CURRENT_SOURCE_DIR}/perf_bench/compute_percentiles.py
                     "${_PERF_OUTPUT_DIR}"
             WORKING_DIRECTORY "${_PERF_OUTPUT_DIR}")
    set_tests_properties(perf_aggregate PROPERTIES DEPENDS perf_producer_cpp)
endif()

# =============================================================================
# cancel_parity/ — GAP 09 #7 cancellation-parity harness
#
# cancel_producer.cpp emits N=1000 VoiceEvent frames with an InterruptedEvent
# (reason=APP_STOP) injected at index 500. Per-SDK consumers subscribe,
# count events received up to the interrupted marker, call their cancel
# path, and verify the stream stops within 50ms. compare_cancel_traces.py
# aggregates per-SDK traces and asserts wire-level parity (all 5 SDKs
# observe the cancel at the same ordinal).
# =============================================================================

set(_CANCEL_OUTPUT_DIR "${CMAKE_BINARY_DIR}/tests/streaming/cancel_parity")

add_executable(cancel_producer cancel_parity/cancel_producer.cpp)
target_include_directories(cancel_producer PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)
target_link_libraries(cancel_producer PRIVATE rac_commons)
target_compile_features(cancel_producer PRIVATE cxx_std_17)
rac_streaming_test_define_have_protobuf(cancel_producer)
set_target_properties(cancel_producer PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${_CANCEL_OUTPUT_DIR}")

add_test(NAME cancel_producer_cpp
         COMMAND cancel_producer
         WORKING_DIRECTORY "${_CANCEL_OUTPUT_DIR}")

if(Python3_FOUND)
    add_test(NAME cancel_aggregate
             COMMAND ${Python3_EXECUTABLE}
                     ${CMAKE_CURRENT_SOURCE_DIR}/cancel_parity/compare_cancel_traces.py
                     "${_CANCEL_OUTPUT_DIR}"
             WORKING_DIRECTORY "${_CANCEL_OUTPUT_DIR}")
    set_tests_properties(cancel_aggregate PROPERTIES DEPENDS cancel_producer_cpp)
endif()
