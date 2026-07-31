# =============================================================================
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
# =============================================================================

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

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

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
# ---------------------------------------------------------------------------
# NeuRT — the Apple Neural Engine LLM modality of the coreml engine.
#
# NeuRT lives in the sibling `neurun` repo and is linked here as a STATIC library
# (`neurt_core`). It supplies `g_neurt_llm_ops`, which rac_plugin_entry_coreml.cpp
# wires into the vtable's llm_ops slot. NeuRT runs PREBUILT Core ML graphs on the
# ANE; it never compiles a model, and it pulls in no vendor SDK — `neurt_core`
# depends only on NeuRT/include/neurt/backend.h plus the shared runtime, which is
# what lets it build on a Mac with no QAIRT licence.
#
# Discovery is by PATH, not by a hardcoded sibling: set -DNEURT_ROOT=<neurun> (or
# export NEURT_ROOT). When it is absent the engine builds EXACTLY as before with
# llm_ops = nullptr, so a checkout without neurun is not broken by this — it just
# does not get the ANE LLM path. That degradation is deliberate and is checked by
# RAC_COREML_HAVE_NEURT below.
# ---------------------------------------------------------------------------
if(NOT DEFINED NEURT_ROOT AND DEFINED ENV{NEURT_ROOT})
    set(NEURT_ROOT "$ENV{NEURT_ROOT}")
endif()
if(NOT DEFINED NEURT_ROOT)
    # Walk to the sibling checkout by MARKER (Makefile + CMakeLists.txt), never by
    # counting `../` hops — a hop count silently resolves to the wrong directory the
    # moment a level is inserted (neurun KB: depth-1-globs-break-on-reorg).
    get_filename_component(_rac_parent "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
    if(EXISTS "${_rac_parent}/neurun/CMakeLists.txt" AND EXISTS "${_rac_parent}/neurun/Makefile")
        set(NEURT_ROOT "${_rac_parent}/neurun")
    endif()
endif()

set(RAC_COREML_HAVE_NEURT OFF)
if(APPLE AND NEURT_ROOT AND EXISTS "${NEURT_ROOT}/NeuRT/src/sdk/rac_llm_ops_neurt.cpp")
    set(RAC_COREML_HAVE_NEURT ON)
    add_library(rac_neurt_llm_ops STATIC
        ${NEURT_ROOT}/NeuRT/src/sdk/rac_llm_ops_neurt.cpp
    )
    target_include_directories(rac_neurt_llm_ops PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
        ${NEURT_ROOT}/NeuRT/include
        ${NEURT_ROOT}/QHexRT/include
    )
    target_compile_features(rac_neurt_llm_ops PRIVATE cxx_std_17)
    set_target_properties(rac_neurt_llm_ops PROPERTIES POSITION_INDEPENDENT_CODE ON)
endif()

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

if(RAC_COREML_HAVE_NEURT)
    target_link_libraries(rac_backend_coreml PRIVATE rac_neurt_llm_ops)
    target_compile_definitions(rac_backend_coreml PRIVATE RAC_COREML_HAVE_NEURT=1)
endif()

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
message(STATUS "  Engine: coreml (DIFFUSION via MLModel; LLM via NeuRT/ANE when present)")
message(STATUS "  NeuRT (ANE LLM):  ${RAC_COREML_HAVE_NEURT}  [NEURT_ROOT=${NEURT_ROOT}]")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
