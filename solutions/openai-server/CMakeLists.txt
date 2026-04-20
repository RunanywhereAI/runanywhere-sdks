option(RA_BUILD_SERVER "Build the OpenAI-compatible HTTP server solution" OFF)

if(NOT RA_BUILD_SERVER)
    return()
endif()

add_library(ra_solution_openai_server STATIC
    http_server.cpp
    openai_server.cpp
)

target_include_directories(ra_solution_openai_server PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/core>
)

target_link_libraries(ra_solution_openai_server
    PUBLIC  RunAnywhere::core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)

set_target_properties(ra_solution_openai_server PROPERTIES
    POSITION_INDEPENDENT_CODE ON)

add_library(RunAnywhere::solution_openai_server ALIAS ra_solution_openai_server)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION include/runanywhere/solutions/openai-server
        FILES_MATCHING PATTERN "*.h")

install(TARGETS ra_solution_openai_server
        EXPORT RunAnywhereTargets
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib)

if(RA_BUILD_TESTS)
    add_subdirectory(tests)
endif()

message(STATUS "solutions/openai-server: built (HTTP server on")
