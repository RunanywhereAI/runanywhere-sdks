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
    abi/ra_errors.c
    abi/ra_lifecycle.c
    abi/rac_compat.c
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
    $<INSTALL_INTERFACE:include>
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
    $<INSTALL_INTERFACE:include>
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
    $<INSTALL_INTERFACE:include>
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
    $<INSTALL_INTERFACE:include>
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
    $<INSTALL_INTERFACE:include>
)
# libcurl for the real downloader. System package on macOS / Linux; Android
# NDK has it; WASM-emscripten provides a curl shim over fetch().
find_package(CURL QUIET)
if(NOT CURL_FOUND)
    find_package(CURL CONFIG QUIET)
endif()
if(NOT CURL_FOUND)
    message(FATAL_ERROR
        "libcurl not found. Install libcurl-dev (Linux) or let vcpkg "
        "provide it — the real model downloader needs it.")
endif()
target_link_libraries(ra_core_model_registry
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers CURL::libcurl
)
if(APPLE)
    # CommonCrypto for SHA-256 (no extra dep).
    target_link_libraries(ra_core_model_registry PRIVATE "-framework CoreFoundation")
else()
    # Non-Apple hosts route SHA-256 through OpenSSL. libcurl already
    # links libssl transitively, but the linker needs an explicit dep on
    # libcrypto because model_downloader.cpp calls SHA256_Init/Update/Final.
    find_package(OpenSSL QUIET)
    if(OpenSSL_FOUND)
        target_link_libraries(ra_core_model_registry PRIVATE OpenSSL::Crypto)
    endif()
endif()
set_target_properties(ra_core_model_registry PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_model_registry ALIAS ra_core_model_registry)

# --- Network / auth layer ----------------------------------------------------
# Ports capability surface from sdk/runanywhere-commons/include/rac/
# infrastructure/network/{rac_http_client,rac_endpoints,rac_environment,
# rac_auth_manager}.h into a single libcurl-backed implementation.
add_library(ra_core_net STATIC
    net/http_client.cpp
    net/environment.cpp
    net/telemetry.cpp
)
target_include_directories(ra_core_net PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ra_core_net
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers CURL::libcurl
)
set_target_properties(ra_core_net PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_net ALIAS ra_core_net)

# --- Utilities (audio WAV encode/decode, image helpers) ----------------------
add_library(ra_core_util STATIC
    util/audio_utils.cpp
)
target_include_directories(ra_core_util PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ra_core_util
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)
set_target_properties(ra_core_util PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_util ALIAS ra_core_util)

# --- Umbrella target ---------------------------------------------------------
add_library(ra_core INTERFACE)
target_link_libraries(ra_core INTERFACE
    ra_core_abi
    ra_core_graph
    ra_core_registry
    ra_core_router
    ra_core_voice_pipeline
    ra_core_model_registry
    ra_core_net
    ra_core_util
)
add_library(RunAnywhere::core ALIAS ra_core)

# --- Install -----------------------------------------------------------------
# Ship the full public header tree, not just abi/. Downstream consumers that
# do `find_package(RunAnywhere)` and link `RunAnywhere::core` need the
# graph/, registry/, router/, voice_pipeline/, model_registry/ headers too.
install(DIRECTORY
            abi/
            graph/
            registry/
            router/
            voice_pipeline/
            model_registry/
            net/
            util/
        DESTINATION include/runanywhere
        FILES_MATCHING
            PATTERN "*.h"
            PATTERN "*.inl"
)

install(TARGETS
            ra_core                       # the INTERFACE umbrella
            ra_core_abi
            ra_core_graph
            ra_core_registry
            ra_core_router
            ra_core_voice_pipeline
            ra_core_model_registry
            ra_core_net
            ra_core_util
        EXPORT RunAnywhereTargets
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        RUNTIME DESTINATION bin
)

install(EXPORT RunAnywhereTargets
        FILE        RunAnywhereTargets.cmake
        NAMESPACE   RunAnywhere::
        DESTINATION lib/cmake/RunAnywhere
)
