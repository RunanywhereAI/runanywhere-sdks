add_executable(ra_bench benchmark.cpp)
target_link_libraries(ra_bench
    PRIVATE
        RunAnywhere::core
        RunAnywhere::platform_flags
        RunAnywhere::sanitizers
        Threads::Threads
)
target_include_directories(ra_bench PRIVATE ${CMAKE_SOURCE_DIR})

find_package(Threads REQUIRED)

install(TARGETS ra_bench RUNTIME DESTINATION bin)
