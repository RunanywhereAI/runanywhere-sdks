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
