# gtest discovery is hoisted to the root CMakeLists so every subdir under
# `RA_BUILD_TESTS` can link GTest::gtest without repeating find_package.

add_executable(ra_core_tests
    ring_buffer_test.cpp
    memory_pool_test.cpp
    cancel_token_test.cpp
    stream_edge_test.cpp
    stream_edge_stress_test.cpp
    sentence_detector_test.cpp
    text_sanitizer_test.cpp
    plugin_registry_test.cpp
    engine_router_test.cpp
)

target_link_libraries(ra_core_tests
    PRIVATE
        RunAnywhere::core
        RunAnywhere::platform_flags
        RunAnywhere::sanitizers
        GTest::gtest
        GTest::gtest_main
)

include(GoogleTest)
# detect_leaks is a Linux-only ASan feature; on macOS we rely on scope-based
# RAII. halt_on_error stays on so any real bug fails the suite immediately.
gtest_discover_tests(ra_core_tests
    PROPERTIES
        TIMEOUT 60
        ENVIRONMENT "ASAN_OPTIONS=halt_on_error=1;UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"
)
