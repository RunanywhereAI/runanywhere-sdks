# rcli unit tests — reuse the commons TestSuite harness (tests/test_common.h).
add_executable(test_rcli_unit test_rcli_unit.cpp)
target_include_directories(test_rcli_unit PRIVATE
    ${CMAKE_SOURCE_DIR}/tests
)
target_link_libraries(test_rcli_unit PRIVATE rcli_core)
add_test(NAME rcli_unit_tests COMMAND test_rcli_unit --run-all)
