# =============================================================================
# mlx engine — Apple-only plugin backed by Swift mlx-swift-lm callbacks.
# =============================================================================

if(APPLE)
    option(RAC_BACKEND_MLX "Build the MLX engine bridge (Apple only)" ON)
else()
    set(RAC_BACKEND_MLX OFF CACHE BOOL "" FORCE)
endif()

if(NOT RAC_BACKEND_MLX)
    return()
endif()

message(STATUS "Configuring mlx engine...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

get_filename_component(RAC_COMMONS_ROOT_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

set(MLX_SOURCES
    rac_mlx_engine.cpp
    rac_backend_mlx_register.cpp
    rac_static_register_mlx.cpp
)

rac_add_engine_plugin(mlx
    TARGET_NAME         rac_backend_mlx
    CXX_STANDARD        20
    SHARED_ONLY
    SOURCES             ${MLX_SOURCES}
    INCLUDE_DIRECTORIES
        ${RAC_COMMONS_ROOT_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/..
)

if(RAC_BUILD_TESTS)
    find_package(Threads REQUIRED)
    add_executable(test_mlx_cancellation tests/test_mlx_cancellation.cpp)
    target_link_libraries(test_mlx_cancellation PRIVATE rac_backend_mlx Threads::Threads)
endif()

message(STATUS "mlx engine Configuration:")
message(STATUS "  Engine: mlx (Swift mlx-swift-lm callback bridge)")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
