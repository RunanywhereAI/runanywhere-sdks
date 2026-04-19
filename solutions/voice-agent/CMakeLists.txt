add_library(ra_solution_voice_agent STATIC
    voice_agent_solution.cpp
)

target_include_directories(ra_solution_voice_agent PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/core>
)

target_link_libraries(ra_solution_voice_agent
    PUBLIC  RunAnywhere::core_voice_pipeline RunAnywhere::core_registry
            RunAnywhere::core_router RunAnywhere::core_abi
            RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)

set_target_properties(ra_solution_voice_agent PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::solution_voice_agent ALIAS ra_solution_voice_agent)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION include/runanywhere/solutions/voice-agent
        FILES_MATCHING PATTERN "*.h")

install(TARGETS ra_solution_voice_agent
        EXPORT RunAnywhereTargets
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib)
