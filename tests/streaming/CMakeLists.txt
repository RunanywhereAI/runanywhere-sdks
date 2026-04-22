# =============================================================================
# tests/streaming/ — GAP 09 / v2 close-out parity test harness
#
# Phase 4 of v2 close-out. The C++ binary is the GOLDEN PRODUCER: it runs
# the deterministic event script, emits the proto-byte stream into
# fixtures/golden_events.txt (or asserts against it via --check).
#
# Per-language tests (parity_test.swift, .kt, .dart, .ts) read the same
# fixture and assert their captured stream matches.
# =============================================================================

if(NOT RAC_BUILD_TESTS)
    return()
endif()

add_executable(parity_test_cpp parity_test.cpp)
target_include_directories(parity_test_cpp PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)
target_link_libraries(parity_test_cpp PRIVATE rac_commons)
target_compile_features(parity_test_cpp PRIVATE cxx_std_17)

# Two CTest cases:
#   - parity_test_cpp_produce  : runs every CTest invocation, refreshes the
#                                fixtures file (idempotent if the schedule
#                                hasn't drifted).
#   - parity_test_cpp_check    : runs after produce, asserts produce vs the
#                                committed fixture. Fails if the C-side
#                                schedule drifts vs fixtures/golden_events.txt
#                                without a deliberate update.
set(_GOLDEN_PATH "${CMAKE_SOURCE_DIR}/tests/streaming/fixtures/golden_events.txt")
file(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/tests/streaming/fixtures")

add_test(NAME parity_test_cpp_check
         COMMAND parity_test_cpp --check "${_GOLDEN_PATH}")

# =============================================================================
# perf_bench/ — GAP 09 #8 latency measurement harness (v2.1 quick-wins Item 3)
#
# perf_producer.cpp emits N=10000 timestamped VoiceEvent frames to a binary
# input file that per-SDK consumers (perf_bench.{swift,kt,dart,ts}) read,
# decode, and record per-event latency for. compute_percentiles.py
# aggregates the per-SDK logs into p50/p95/p99 and asserts p50 < 1ms.
#
# Today this just builds the producer; per-SDK runner integration is the
# v2.1-2 follow-up (XCTest, JUnit, flutter test, Jest, Vitest with native
# library loading).
# =============================================================================

add_executable(perf_producer perf_bench/perf_producer.cpp)
target_include_directories(perf_producer PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)
target_link_libraries(perf_producer PRIVATE rac_commons)
target_compile_features(perf_producer PRIVATE cxx_std_17)
set_target_properties(perf_producer PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests/streaming/perf_bench")

# =============================================================================
# cancel_parity/ — GAP 09 #7 cancellation-parity harness (v3.1 Phase 5.1)
#
# cancel_producer.cpp emits N=1000 VoiceEvent frames with an
# InterruptedEvent (reason=APP_STOP) injected at index 500. Per-SDK
# consumers subscribe, count events received up to the interrupted
# marker, call their cancel path, and verify the stream stops within
# 50ms. compare_cancel_traces.py aggregates per-SDK traces and asserts
# wire-level parity (all 5 SDKs observe the cancel at the same ordinal).
# =============================================================================

add_executable(cancel_producer cancel_parity/cancel_producer.cpp)
target_include_directories(cancel_producer PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)
target_link_libraries(cancel_producer PRIVATE rac_commons)
target_compile_features(cancel_producer PRIVATE cxx_std_17)
set_target_properties(cancel_producer PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests/streaming/cancel_parity")
