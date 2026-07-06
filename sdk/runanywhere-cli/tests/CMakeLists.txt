# rcli unit tests — reuse the commons TestSuite harness (tests/test_common.h).
add_executable(test_rcli_unit test_rcli_unit.cpp)
target_include_directories(test_rcli_unit PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/tests
)
target_link_libraries(test_rcli_unit PRIVATE rcli_core)
add_test(NAME rcli_unit_tests COMMAND test_rcli_unit --run-all)

if(TARGET rac_backend_mlx)
    add_executable(test_rcli_mlx_e2e test_rcli_mlx_e2e.cpp)
    target_include_directories(test_rcli_mlx_e2e PRIVATE
        ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/tests
    )
    target_link_libraries(test_rcli_mlx_e2e PRIVATE rcli_core)
    if(TARGET nlohmann_json::nlohmann_json)
        target_link_libraries(test_rcli_mlx_e2e PRIVATE nlohmann_json::nlohmann_json)
    endif()
    add_test(NAME rcli_mlx_e2e_tests COMMAND test_rcli_mlx_e2e --run-all)
endif()
