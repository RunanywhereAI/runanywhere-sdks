cmake_minimum_required(VERSION 3.16)

include(FetchContent)
find_package(Threads REQUIRED)

# GoogleTest (download on first configure)
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        release-1.12.1
    GIT_SHALLOW    TRUE
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

if(NOT TARGET rac_backend_rag)
    message(STATUS "RAG backend not enabled; skipping rag_backend_thread_safety_test")
    return()
endif()

add_executable(rac_rag_backend_thread_safety_test
    rag_backend_thread_safety_test.cpp
)

target_link_libraries(rac_rag_backend_thread_safety_test
    PRIVATE
    rac_backend_rag
    Threads::Threads
    GTest::gtest_main
)

target_compile_features(rac_rag_backend_thread_safety_test PRIVATE cxx_std_17)

include(GoogleTest)
gtest_discover_tests(rac_rag_backend_thread_safety_test
    DISCOVERY_MODE PRE_TEST
)
add_test(
    NAME rac_rag_backend_thread_safety_test
    COMMAND rac_rag_backend_thread_safety_test
)
