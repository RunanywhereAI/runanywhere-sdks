# Try system gtest first — vcpkg / brew / apt / any find_package mechanism.
find_package(GTest CONFIG QUIET)
if(NOT GTest_FOUND)
    find_package(GTest QUIET)
endif()

# Fall back to FetchContent so `cmake --build` works on a fresh CI worker
# without any prior setup. Pinned to a recent release.
if(NOT GTest_FOUND)
    message(STATUS "gtest not found via find_package — fetching via FetchContent")
    include(FetchContent)
    set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
    set(BUILD_GMOCK   OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(googletest
        GIT_REPOSITORY https://github.com/google/googletest.git
        GIT_TAG        v1.14.0
        GIT_SHALLOW    TRUE
    )
    FetchContent_MakeAvailable(googletest)
endif()

add_executable(ra_core_tests
    ring_buffer_test.cpp
    memory_pool_test.cpp
    cancel_token_test.cpp
    stream_edge_test.cpp
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
