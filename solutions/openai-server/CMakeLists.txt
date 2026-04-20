option(RA_BUILD_SERVER "Build the OpenAI-compatible HTTP server solution" OFF)

if(NOT RA_BUILD_SERVER)
    return()
endif()

include(FetchContent)

# httplib — header-only HTTP/1.1 server + SSE support. The v0.15.3 tag is
# the last known-good one that doesn't pull in OpenSSL transitively; we
# toggle TLS off because the OpenAI-compatible solution serves plain HTTP
# behind the host's reverse proxy.
FetchContent_Declare(
    httplib
    GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
    GIT_TAG        v0.15.3
    GIT_SHALLOW    TRUE
)
set(HTTPLIB_REQUIRE_OPENSSL OFF CACHE BOOL "" FORCE)
set(HTTPLIB_COMPILE         OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(httplib)

# nlohmann/json — single-header JSON. v3.11.3.
FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v3.11.3
    GIT_SHALLOW    TRUE
)
set(JSON_BuildTests OFF CACHE INTERNAL "")
set(JSON_Install    OFF CACHE INTERNAL "")
FetchContent_MakeAvailable(nlohmann_json)

add_library(ra_solution_openai_server STATIC
    openai_handler.cpp
    openai_server.cpp
    server_session_registry.cpp
)

target_include_directories(ra_solution_openai_server PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/core>
)

target_link_libraries(ra_solution_openai_server
    PUBLIC  RunAnywhere::core_abi
            RunAnywhere::core_abi_ext
            RunAnywhere::core_util
            RunAnywhere::platform_flags
            httplib::httplib
            nlohmann_json::nlohmann_json
    PRIVATE RunAnywhere::sanitizers
)

set_target_properties(ra_solution_openai_server PROPERTIES
    POSITION_INDEPENDENT_CODE ON)

add_library(RunAnywhere::solution_openai_server ALIAS ra_solution_openai_server)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/
        DESTINATION include/runanywhere/solutions/openai-server
        FILES_MATCHING PATTERN "*.h")

# NB: not added to the `RunAnywhereTargets` export set — the optional
# httplib + nlohmann_json transitive deps aren't part of the public
# package export, and the solution library is only ever linked into the
# server binary or a specific host.
install(TARGETS ra_solution_openai_server
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib)

# --- runanywhere-server CLI -------------------------------------------------
# Standalone OpenAI-compatible server binary — loads a GGUF model (optional)
# and serves /v1/chat/completions. Always built alongside the library so the
# Docker image ships it without extra flags.
add_executable(runanywhere-server server_main.cpp)

target_link_libraries(runanywhere-server
    PRIVATE RunAnywhere::solution_openai_server
            RunAnywhere::core_abi
            RunAnywhere::core_abi_ext
            RunAnywhere::core_llm_dispatch
            RunAnywhere::core_registry
            RunAnywhere::core_router
            RunAnywhere::platform_flags
)

# Force-load so the weak-linked `ra_solution_openai_server_*` entry points
# resolve against this static library. macOS needs -force_load; ELF
# platforms use --whole-archive.
if(APPLE)
    target_link_options(runanywhere-server PRIVATE
        -Wl,-force_load,$<TARGET_FILE:ra_solution_openai_server>)
elseif(UNIX)
    target_link_options(runanywhere-server PRIVATE
        -Wl,--whole-archive
        "$<TARGET_FILE:ra_solution_openai_server>"
        -Wl,--no-whole-archive)
endif()

# Engine plugins on non-iOS builds are dlopen'd at runtime — make sure the
# llamacpp plugin is linked in statically so `runanywhere-server --model …`
# can resolve `llm_create` without a plugins/ search path.
if(TARGET llamacpp_engine)
    if(APPLE)
        target_link_options(runanywhere-server PRIVATE
            -Wl,-force_load,$<TARGET_FILE:llamacpp_engine>)
    elseif(UNIX)
        target_link_options(runanywhere-server PRIVATE
            -Wl,--whole-archive
            "$<TARGET_FILE:llamacpp_engine>"
            -Wl,--no-whole-archive)
    endif()
    target_link_libraries(runanywhere-server PRIVATE llamacpp_engine)
endif()

install(TARGETS runanywhere-server RUNTIME DESTINATION bin)

if(RA_BUILD_TESTS)
    add_subdirectory(tests)
endif()

message(STATUS "solutions/openai-server: built (httplib + LLM-real)")
