# =============================================================================
# RunAnywhere Server Module
# =============================================================================
# OpenAI-compatible HTTP server for LLM inference
#
# This module provides:
#   - GET  /v1/models           - List available models
#   - POST /v1/chat/completions - Chat completion (streaming & non-streaming)
#   - GET  /health              - Health check
#
# Dependencies (fetched by parent CMakeLists.txt):
#   - cpp-httplib (header-only HTTP library)
#   - nlohmann_json (header-only JSON library)
# =============================================================================

# Server implementation sources
set(RAC_SERVER_SOURCES
    http_server.cpp
    openai_handler.cpp
    json_utils.cpp
)

set(RAC_SERVER_HEADERS
    http_server.h
    openai_handler.h
    json_utils.h
)

# Create the server library
add_library(rac_server STATIC ${RAC_SERVER_SOURCES} ${RAC_SERVER_HEADERS})

# Include directories
target_include_directories(rac_server PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../include>
    $<INSTALL_INTERFACE:include>
)

target_include_directories(rac_server PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

# Link dependencies
target_link_libraries(rac_server PUBLIC
    rac_commons
    httplib::httplib
    nlohmann_json::nlohmann_json
)

# If backends are built, link them
if(TARGET rac_backend_llamacpp)
    target_link_libraries(rac_server PUBLIC rac_backend_llamacpp)
    target_compile_definitions(rac_server PRIVATE RAC_HAS_LLAMACPP=1)
endif()

# Threading support
find_package(Threads REQUIRED)
target_link_libraries(rac_server PUBLIC Threads::Threads)

# Platform-specific libraries
if(UNIX AND NOT APPLE)
    # Linux needs explicit pthread
    target_link_libraries(rac_server PUBLIC pthread)
endif()

# Compiler options
target_compile_features(rac_server PUBLIC cxx_std_17)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(rac_server PRIVATE -Wall -Wextra -Wpedantic)
endif()

# Symbol visibility
set_target_properties(rac_server PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

# Install
install(TARGETS rac_server
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

message(STATUS "  Server module configured")
