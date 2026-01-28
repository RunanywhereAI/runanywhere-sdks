# =============================================================================
# RunAnywhere Tools
# =============================================================================
# Standalone command-line tools built on runanywhere-commons
#
# Binaries:
#   - runanywhere-server: OpenAI-compatible HTTP server
# =============================================================================

# =============================================================================
# RunAnywhere Server Binary
# =============================================================================

add_executable(runanywhere-server
    runanywhere-server.cpp
)

target_include_directories(runanywhere-server PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../include
)

target_link_libraries(runanywhere-server PRIVATE
    rac_server
    rac_commons
)

# Link backends if available
if(TARGET rac_backend_llamacpp)
    target_link_libraries(runanywhere-server PRIVATE rac_backend_llamacpp)
endif()

if(TARGET rac_backend_onnx)
    target_link_libraries(runanywhere-server PRIVATE rac_backend_onnx)
endif()

# Threading
find_package(Threads REQUIRED)
target_link_libraries(runanywhere-server PRIVATE Threads::Threads)

# Compiler features
target_compile_features(runanywhere-server PRIVATE cxx_std_17)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(runanywhere-server PRIVATE -Wall -Wextra)
endif()

# Set RPATH for finding shared libraries at runtime
set_target_properties(runanywhere-server PROPERTIES
    BUILD_RPATH "${CMAKE_BINARY_DIR}"
    INSTALL_RPATH "$ORIGIN/../lib"
)

# Install
install(TARGETS runanywhere-server
    RUNTIME DESTINATION bin
)

message(STATUS "  runanywhere-server tool configured")
