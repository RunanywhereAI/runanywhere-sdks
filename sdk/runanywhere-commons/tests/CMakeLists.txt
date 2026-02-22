# =============================================================================
# RunAnywhere Commons - Benchmark Unit Tests
# =============================================================================

include(FetchContent)

FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.14.0
)

# Prevent GoogleTest from overriding compiler/linker options
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(googletest)

# =============================================================================
# TEST EXECUTABLE
# =============================================================================

add_executable(rac_benchmark_tests
    benchmark/test_monotonic_clock.cpp
    benchmark/test_timing_struct.cpp
    benchmark/test_benchmark_log.cpp
    benchmark/test_benchmark_stats.cpp
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

# =============================================================================
# TEST DISCOVERY
# =============================================================================

include(GoogleTest)
gtest_discover_tests(rac_benchmark_tests)
