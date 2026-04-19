# RunAnywhere v2 — C++20 core
#
# Produces two targets:
#   ra_core_abi     — the C ABI (extern "C" headers + .c glue). Frontends
#                     link only against this.
#   ra_core         — the full C++ runtime (graph, registry, router,
#                     voice_pipeline, model_registry, util). Engines and
#                     solutions link against this.

# --- L0: C ABI ---------------------------------------------------------------
add_library(ra_core_abi STATIC
    abi/ra_version.c
    abi/ra_status.c
)
target_include_directories(ra_core_abi PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/abi>
    $<INSTALL_INTERFACE:include>
)
set_target_properties(ra_core_abi PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)
target_link_libraries(ra_core_abi PUBLIC RunAnywhere::platform_flags)
add_library(RunAnywhere::core_abi ALIAS ra_core_abi)

# --- L4: graph + runtime -----------------------------------------------------
add_library(ra_core_graph STATIC
    graph/graph_scheduler.cpp
)
target_include_directories(ra_core_graph PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
)
target_link_libraries(ra_core_graph
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)
set_target_properties(ra_core_graph PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_graph ALIAS ra_core_graph)

# --- Plugin registry + loader ------------------------------------------------
add_library(ra_core_registry STATIC
    registry/plugin_registry.cpp
)
target_include_directories(ra_core_registry PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
)
target_link_libraries(ra_core_registry
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers $<$<NOT:$<BOOL:${RA_STATIC_PLUGINS}>>:${CMAKE_DL_LIBS}>
)
set_target_properties(ra_core_registry PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_registry ALIAS ra_core_registry)

# --- Engine router + hardware profile ----------------------------------------
add_library(ra_core_router STATIC
    router/hardware_profile.cpp
    router/engine_router.cpp
)
target_include_directories(ra_core_router PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
)
target_link_libraries(ra_core_router
    PUBLIC  ra_core_abi ra_core_registry RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)
set_target_properties(ra_core_router PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_router ALIAS ra_core_router)

# --- VoiceAgent concrete pipeline (port of RCLI / FastVoice orchestrator) ----
add_library(ra_core_voice_pipeline STATIC
    voice_pipeline/sentence_detector.cpp
    voice_pipeline/text_sanitizer.cpp
    voice_pipeline/voice_pipeline.cpp
)
target_include_directories(ra_core_voice_pipeline PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
)
target_link_libraries(ra_core_voice_pipeline
    PUBLIC  ra_core_graph ra_core_router ra_core_registry ra_core_abi
            RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)
set_target_properties(ra_core_voice_pipeline PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_voice_pipeline ALIAS ra_core_voice_pipeline)

# --- Model registry ----------------------------------------------------------
add_library(ra_core_model_registry STATIC
    model_registry/model_registry.cpp
    model_registry/model_downloader.cpp
)
target_include_directories(ra_core_model_registry PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
)
target_link_libraries(ra_core_model_registry
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)
set_target_properties(ra_core_model_registry PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_model_registry ALIAS ra_core_model_registry)

# --- Umbrella target ---------------------------------------------------------
add_library(ra_core INTERFACE)
target_link_libraries(ra_core INTERFACE
    ra_core_abi
    ra_core_graph
    ra_core_registry
    ra_core_router
    ra_core_voice_pipeline
    ra_core_model_registry
)
add_library(RunAnywhere::core ALIAS ra_core)

# --- Install -----------------------------------------------------------------
install(DIRECTORY abi/
        DESTINATION include/runanywhere
        FILES_MATCHING PATTERN "*.h")

install(TARGETS
            ra_core_abi
            ra_core_graph
            ra_core_registry
            ra_core_router
            ra_core_voice_pipeline
            ra_core_model_registry
        EXPORT RunAnywhereTargets
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        RUNTIME DESTINATION bin
)
