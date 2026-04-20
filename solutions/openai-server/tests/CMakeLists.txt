add_executable(ra_solution_openai_server_tests
    http_server_smoke_test.cpp
    openai_routes_test.cpp
    openai_llm_e2e_test.cpp
)

# Let the live test locate the llamacpp plugin dylib relative to the build
# tree so `ra_server_start` + `ra_llm_create` can exercise real generation
# when RA_TEST_GGUF is set.
target_compile_definitions(ra_solution_openai_server_tests PRIVATE
    RA_ENGINE_PLUGIN_DIR="${CMAKE_BINARY_DIR}/engines")

target_link_libraries(ra_solution_openai_server_tests
    PRIVATE
        ra_solution_openai_server
        ra_core_abi_ext
        ra_core_llm_dispatch
        ra_core_registry
        ra_core_router
        httplib::httplib
        nlohmann_json::nlohmann_json
        GTest::gtest
        GTest::gtest_main
)

# Ensure the solution library's weak-linked entry points are force-loaded
# so `ra_server_start` in the test host resolves against them.
if(APPLE)
    target_link_options(ra_solution_openai_server_tests PRIVATE
        -Wl,-force_load,$<TARGET_FILE:ra_solution_openai_server>)
elseif(UNIX)
    target_link_options(ra_solution_openai_server_tests PRIVATE
        -Wl,--whole-archive
        "$<TARGET_FILE:ra_solution_openai_server>"
        -Wl,--no-whole-archive)
endif()

include(GoogleTest)
gtest_discover_tests(ra_solution_openai_server_tests)
