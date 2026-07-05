# coreml engine — Apple-only engine that runs ON Apple CoreML.
#
# Engine identity is the FRAMEWORK it targets (`coreml`), not the modality —
# exactly like the `cloud` engine is named by its transport, not by STT. It
# serves the DIFFUSION modality today (a Stable-Diffusion pipeline wrapping
# Apple's compiled MLModel bundles — .mlmodelc / .mlpackage — behind the
# rac_diffusion_service_ops_t vtable). Future CoreML modalities (VLM /
# embeddings / LLM) attach by filling more vtable op-tables.
#
# NOTE: this engine `coreml` coexists with the runtime `coreml`
# (runtimes/coreml, target rac_runtime_coreml). Separate registries (plugin vs
# runtime), separate dirs, distinct symbols (rac_plugin_entry_coreml vs
# rac_runtime_entry_coreml). The engine USES the runtime via rac_runtime_coreml.

if(APPLE)
    option(RAC_BACKEND_COREML
        "Build the coreml engine (Apple only; Stable Diffusion via MLModel today)" ON)
else()
    set(RAC_BACKEND_COREML OFF CACHE BOOL "" FORCE)
endif()

if(NOT RAC_BACKEND_COREML)
    return()
endif()

message(STATUS "Configuring coreml engine...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)
if(NOT TARGET rac_runtime_coreml)
    message(FATAL_ERROR "RAC_BACKEND_COREML requires rac_runtime_coreml.")
endif()

# Objective-C++ language is enabled at root level (CMakeLists.txt) so
# CMAKE_OBJCXX_COMPILE_OBJECT is populated when this subdirectory runs.

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)

# rac_diffusion_coreml.mm keeps `diffusion` in its name: it is the coreml
# engine's DIFFUSION MODALITY (its pipeline + op-table), not the engine identity
# — parallel to the cloud engine's rac_stt_cloud.cpp.
set(COREML_SOURCES
    rac_diffusion_coreml.mm
    rac_plugin_entry_coreml.cpp
)

# Mirrors the llamacpp pattern (engines/llamacpp/CMakeLists.txt):
#
#   * `rac_backend_coreml` — engine implementation + plugin entry
#     symbol (`rac_plugin_entry_coreml`). SHARED_ONLY so tests and
#     the xcframework packaging can link this target directly by name.
#
#   * `runanywhere_coreml` — thin self-registration carrier built
#     from `rac_static_register_coreml.cpp`.
#       - RAC_STATIC_PLUGINS=ON  → ctor added to rac_commons so iOS / WASM
#         hosts schedule RAC_STATIC_PLUGIN_REGISTER(coreml) before
#         main().
#       - RAC_STATIC_PLUGINS=OFF → SHARED carrier whose filename matches the
#         `rac_plugin_entry_coreml` symbol the dlopen loader
#         derives (see plugin_loader.cpp::entry_symbol_from_path), so
#         `rac_registry_load_plugin(librunanywhere_coreml.*)`
#         actually installs the vtable into the registry.
rac_add_engine_plugin(coreml
    TARGET_NAME         rac_backend_coreml
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             ${COREML_SOURCES}
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
    COMPILE_DEFINITIONS RAC_COREML_GENERATE_AVAILABLE=1
    LINK_LIBRARIES      "-framework Foundation"
                        "-framework CoreML"
                        "-framework Accelerate"
                        rac_runtime_coreml
)

# Self-registration carrier — installs the coreml engine vtable into the
# unified plugin registry. Without this, neither static iOS hosts nor dynamic
# dlopen hosts can route RAC_PRIMITIVE_DIFFUSION to the coreml engine because
# the engine library above does not auto-register.
if(RAC_STATIC_PLUGINS)
    # Ctor lands inside rac_commons so it runs before main() on iOS / WASM.
    # The host (xcframework / app target) is expected to link both rac_commons
    # and rac_backend_coreml together; the unresolved
    # `rac_plugin_entry_coreml` reference is satisfied at the final
    # link site, exactly like the llamacpp static path above.
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_coreml.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include
    )
else()
    add_library(runanywhere_coreml SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_coreml.cpp
    )
    set_target_properties(runanywhere_coreml PROPERTIES
        OUTPUT_NAME           runanywhere_coreml
        C_VISIBILITY_PRESET   hidden
        CXX_VISIBILITY_PRESET hidden
    )
    target_include_directories(runanywhere_coreml PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
    )
    target_link_libraries(runanywhere_coreml PUBLIC
        rac_backend_coreml
        rac_commons
    )
    install(TARGETS runanywhere_coreml LIBRARY DESTINATION lib)
endif()

message(STATUS "coreml engine Configuration:")
message(STATUS "  Engine: coreml (serves DIFFUSION today via MLModel)")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")

if(APPLE AND TARGET rac_backend_coreml)
    rac_add_plugin_entry_test(test_diffusion_coreml_generate
        TEST_NAME diffusion_coreml_generate_tests
        SOURCE ${CMAKE_SOURCE_DIR}/tests/test_diffusion_coreml_generate.cpp
        LINK rac_backend_coreml
        INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}
    )
    rac_add_plugin_entry_test(test_plugin_entry_coreml
        TEST_NAME plugin_entry_coreml_tests
        SOURCE ${CMAKE_SOURCE_DIR}/tests/test_plugin_entry_coreml.cpp
        LINK rac_backend_coreml
    )
endif()
