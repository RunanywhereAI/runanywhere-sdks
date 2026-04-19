add_library(ra_solution_rag STATIC
    bm25_index.cpp
    hybrid_retriever.cpp
)

target_include_directories(ra_solution_rag PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/core>
)

target_link_libraries(ra_solution_rag
    PUBLIC  RunAnywhere::core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)

set_target_properties(ra_solution_rag PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::solution_rag ALIAS ra_solution_rag)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION include/runanywhere/solutions/rag
        FILES_MATCHING PATTERN "*.h")

install(TARGETS ra_solution_rag
        EXPORT RunAnywhereTargets
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib)

if(RA_BUILD_TESTS)
    add_subdirectory(tests)
endif()
