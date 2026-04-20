add_executable(ra_solution_openai_server_tests
    http_server_smoke_test.cpp
)

target_link_libraries(ra_solution_openai_server_tests
    PRIVATE
        ra_solution_openai_server
        GTest::gtest
        GTest::gtest_main
)

include(GoogleTest)
gtest_discover_tests(ra_solution_openai_server_tests)
