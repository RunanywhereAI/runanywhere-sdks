# solutions/rag/tests — unit tests for bm25_index + hybrid_retriever.
#
# ra_core_tests owns gtest discovery for the core primitives. This file adds
# a second executable because the RAG solution lives in its own library and
# we want tests to ride alongside the code, not be drawn into the core
# test target.

add_executable(ra_solutions_rag_tests
    bm25_index_test.cpp
    hybrid_retriever_test.cpp
)

target_link_libraries(ra_solutions_rag_tests
    PRIVATE
        ra_solution_rag
        RunAnywhere::platform_flags
        RunAnywhere::sanitizers
        GTest::gtest
        GTest::gtest_main
)

include(GoogleTest)
gtest_discover_tests(ra_solutions_rag_tests
    PROPERTIES
        TIMEOUT 30
        ENVIRONMENT "ASAN_OPTIONS=halt_on_error=1;UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"
)
