# Memory layer test executable
add_executable(test_memory test_memory.cpp)
target_link_libraries(test_memory PRIVATE rac_commons rac_backend_memory)
target_include_directories(test_memory PRIVATE ${PROJECT_SOURCE_DIR}/include)
