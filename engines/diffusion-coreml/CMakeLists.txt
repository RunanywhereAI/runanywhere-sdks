# =============================================================================
# Diffusion CoreML Backend — Apple-only Stable Diffusion via CoreML MLModel
#
# GAP 06 T5.3 — see v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md.
#
# Wraps Apple's compiled Stable Diffusion MLModel bundles (.mlmodelc /
# .mlpackage) behind the rac_diffusion_service_ops_t vtable.
# =============================================================================

if(APPLE)
    option(RAC_BACKEND_DIFFUSION_COREML
        "Build CoreML Diffusion backend (Apple only, Stable Diffusion via MLModel)" ON)
else()
    set(RAC_BACKEND_DIFFUSION_COREML OFF CACHE BOOL "" FORCE)
endif()

if(NOT RAC_BACKEND_DIFFUSION_COREML)
    return()
endif()

message(STATUS "Configuring CoreML Diffusion backend...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)
if(NOT TARGET rac_runtime_coreml)
    message(FATAL_ERROR "RAC_BACKEND_DIFFUSION_COREML requires rac_runtime_coreml.")
endif()

# Objective-C++ language is enabled at root level (CMakeLists.txt) so
# CMAKE_OBJCXX_COMPILE_OBJECT is populated when this subdirectory runs.

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

set(DIFFUSION_COREML_SOURCES
    diffusion_coreml_backend.mm
    rac_plugin_entry_diffusion_coreml.cpp
)

rac_add_engine_plugin(diffusion_coreml
    TARGET_NAME         rac_backend_diffusion_coreml
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             ${DIFFUSION_COREML_SOURCES}
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
    COMPILE_DEFINITIONS RAC_DIFFUSION_COREML_GENERATE_AVAILABLE=1
    LINK_LIBRARIES      "-framework Foundation"
                        "-framework CoreML"
                        "-framework Accelerate"
                        rac_runtime_coreml
    RUNTIMES            CORE_ML ANE
    FORMATS             COREML
)

message(STATUS "Diffusion CoreML Backend Configuration:")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
