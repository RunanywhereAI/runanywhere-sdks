# =============================================================================
# Diffusion CoreML Backend — Apple-only Stable Diffusion via CoreML MLModel
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

# Mirrors the llamacpp pattern (engines/llamacpp/CMakeLists.txt):
#
#   * `rac_backend_diffusion_coreml` — engine implementation + plugin entry
#     symbol (`rac_plugin_entry_diffusion_coreml`). SHARED_ONLY so tests and
#     the xcframework packaging can link this target directly by name.
#
#   * `runanywhere_diffusion_coreml` — thin self-registration carrier built
#     from `rac_static_register_diffusion_coreml.cpp`.
#       - RAC_STATIC_PLUGINS=ON  → ctor added to rac_commons so iOS / WASM
#         hosts schedule RAC_STATIC_PLUGIN_REGISTER(diffusion_coreml) before
#         main().
#       - RAC_STATIC_PLUGINS=OFF → SHARED carrier whose filename matches the
#         `rac_plugin_entry_diffusion_coreml` symbol the dlopen loader
#         derives (see plugin_loader.cpp::entry_symbol_from_path), so
#         `rac_registry_load_plugin(librunanywhere_diffusion_coreml.*)`
#         actually installs the vtable into the registry.
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

# Self-registration carrier — installs the diffusion-coreml vtable into the
# unified plugin registry. Without this, neither static iOS hosts nor dynamic
# dlopen hosts can route RAC_PRIMITIVE_DIFFUSION to diffusion-coreml because
# the engine library above does not auto-register.
if(RAC_STATIC_PLUGINS)
    # Ctor lands inside rac_commons so it runs before main() on iOS / WASM.
    # The host (xcframework / app target) is expected to link both rac_commons
    # and rac_backend_diffusion_coreml together; the unresolved
    # `rac_plugin_entry_diffusion_coreml` reference is satisfied at the final
    # link site, exactly like the llamacpp static path above.
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_diffusion_coreml.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include
    )
else()
    add_library(runanywhere_diffusion_coreml SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_diffusion_coreml.cpp
    )
    set_target_properties(runanywhere_diffusion_coreml PROPERTIES
        OUTPUT_NAME           runanywhere_diffusion_coreml
        C_VISIBILITY_PRESET   hidden
        CXX_VISIBILITY_PRESET hidden
    )
    target_include_directories(runanywhere_diffusion_coreml PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
    )
    target_link_libraries(runanywhere_diffusion_coreml PUBLIC
        rac_backend_diffusion_coreml
        rac_commons
    )
    install(TARGETS runanywhere_diffusion_coreml LIBRARY DESTINATION lib)
endif()

message(STATUS "Diffusion CoreML Backend Configuration:")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
