# =============================================================================
# neurt engine — the Apple engine, implemented by NeuRT (the Apple half of the
# sibling `neurun` repo).
#
# Engine identity is the RUNTIME THAT IMPLEMENTS IT (`neurt`), not the modality
# and not the vendor framework — exactly like the `cloud` engine is named by its
# transport, not by STT. It serves TWO modalities:
#
#   * DIFFUSION — a Stable-Diffusion pipeline over Apple's compiled MLModel
#     bundles (.mlmodelc / .mlpackage), behind rac_diffusion_service_ops_t.
#   * GENERATE_TEXT — prebuilt Core ML LLM graphs executed on the Apple Neural
#     Engine, behind rac_llm_service_ops_t.
#
# Both implementations live in the neurun checkout under `NeuRT/src/sdk/`, so
# ALL Apple inference code sits in one place and this directory holds only the
# plugin entry + the registration carrier.
#
# NOTE: the engine `neurt` still USES the runtime `coreml` (runtimes/coreml,
# target rac_runtime_coreml) and still declares the COREML model FORMAT and the
# COREML/ANE runtimes. Those name the Apple FRAMEWORK, not this engine — they
# are deliberately NOT renamed.
# =============================================================================

if(APPLE)
    option(RAC_BACKEND_NEURT
        "Build the neurt engine (Apple only; ANE LLM + CoreML diffusion via NeuRT)" ON)
else()
    set(RAC_BACKEND_NEURT OFF CACHE BOOL "" FORCE)
endif()

if(NOT RAC_BACKEND_NEURT)
    return()
endif()

message(STATUS "Configuring neurt engine...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)
if(NOT TARGET rac_runtime_coreml)
    message(FATAL_ERROR "RAC_BACKEND_NEURT requires rac_runtime_coreml.")
endif()

# Objective-C++ language is enabled at root level (CMakeLists.txt) so
# CMAKE_OBJCXX_COMPILE_OBJECT is populated when this subdirectory runs.

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

# ---------------------------------------------------------------------------
# NEURT_ROOT — the sibling `neurun` checkout that implements this engine.
#
# Discovery is by PATH, not by a hardcoded sibling: set -DNEURT_ROOT=<neurun>
# (or export NEURT_ROOT). Walk to it by MARKER (Makefile + CMakeLists.txt),
# never by counting `../` hops — a hop count silently resolves to the wrong
# directory the moment a level is inserted (neurun KB:
# depth-1-globs-break-on-reorg).
#
# Unlike the previous `coreml` engine, a MISSING neurun is now a hard error
# rather than a silent degrade. It has to be: BOTH of this engine's modalities
# are implemented over there now, so without it there is no engine left to
# build — and a silent degrade would produce an engine that registers, claims
# Apple availability, and then serves nothing. Build without the Apple engine
# explicitly (-DRAC_BACKEND_NEURT=OFF) if you do not have the checkout.
# ---------------------------------------------------------------------------
if(NOT DEFINED NEURT_ROOT AND DEFINED ENV{NEURT_ROOT})
    set(NEURT_ROOT "$ENV{NEURT_ROOT}")
endif()
if(NOT DEFINED NEURT_ROOT)
    get_filename_component(_rac_parent "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
    # Prefer `neurun` (canonical checkout name); also accept `QHexRT` (monorepo layout).
    if(EXISTS "${_rac_parent}/neurun/CMakeLists.txt" AND EXISTS "${_rac_parent}/neurun/Makefile")
        set(NEURT_ROOT "${_rac_parent}/neurun")
    elseif(EXISTS "${_rac_parent}/QHexRT/CMakeLists.txt" AND
           EXISTS "${_rac_parent}/QHexRT/NeuRT/src/sdk/rac_llm_ops_neurt.cpp")
        set(NEURT_ROOT "${_rac_parent}/QHexRT")
    endif()
endif()

set(_neurt_sdk_dir "${NEURT_ROOT}/NeuRT/src/sdk")
if(NOT NEURT_ROOT OR NOT EXISTS "${_neurt_sdk_dir}/rac_llm_ops_neurt.cpp")
    message(FATAL_ERROR
        "RAC_BACKEND_NEURT=ON but the neurun checkout was not found.\n"
        "  looked for: ${_neurt_sdk_dir}/rac_llm_ops_neurt.cpp\n"
        "  NEURT_ROOT: '${NEURT_ROOT}'\n"
        "Pass -DNEURT_ROOT=/path/to/neurun (or export NEURT_ROOT), or build "
        "without the Apple engine using -DRAC_BACKEND_NEURT=OFF.")
endif()

# ---------------------------------------------------------------------------
# rac_neurt_core — NeuRT's runtime, compiled from neurun's own source list.
#
# The list is DERIVED from neurun's root CMakeLists.txt rather than copied, so
# the two cannot drift: neurun owns `neurt_core` (its `add_library(neurt_core
# STATIC ...)` plus the Apple-only `target_sources(neurt_core PRIVATE ...)`
# block), and a source added there is picked up here automatically. That is the
# same block neurun's own shared/forge/tests/test_backend_boundaries.py parses,
# so the shape is already load-bearing and tested on that side.
#
# The target is named `rac_neurt_core`, never `neurt_core`, so it cannot collide
# with neurun's own target if a build ever add_subdirectory()s that repo.
# ---------------------------------------------------------------------------
file(READ "${NEURT_ROOT}/CMakeLists.txt" _neurt_cmake)

# Delimit the region by the two statements that bracket every neurt_core source
# declaration — the add_library and the `qhexrt_core PUBLIC neurt_core` link that
# closes the block. Do NOT try to match a single `add_library(... )` with `[^)]*`:
# the comment inside that block contains a literal `)`, which truncates the match
# and silently drops `NeuRT/src/neurt_c.cpp`. (neurun's own
# shared/forge/tests/test_backend_boundaries.py had the same truncation; it passed
# only because the two sources it did see happened to satisfy the assertion.)
string(FIND "${_neurt_cmake}" "add_library(neurt_core STATIC" _neurt_beg)
string(FIND "${_neurt_cmake}" "target_link_libraries(qhexrt_core PUBLIC neurt_core" _neurt_end)
if(_neurt_beg EQUAL -1 OR _neurt_end EQUAL -1 OR NOT _neurt_end GREATER _neurt_beg)
    message(FATAL_ERROR
        "Could not locate the neurt_core source region in ${NEURT_ROOT}/CMakeLists.txt "
        "(add_library(neurt_core STATIC ... up to target_link_libraries(qhexrt_core PUBLIC "
        "neurt_core). The block moved or changed shape; update this parse.")
endif()
math(EXPR _neurt_len "${_neurt_end} - ${_neurt_beg}")
string(SUBSTRING "${_neurt_cmake}" ${_neurt_beg} ${_neurt_len} _neurt_region)

string(REGEX MATCHALL "NeuRT/[A-Za-z0-9_/]+\\.(cpp|mm|c)" _neurt_core_sources "${_neurt_region}")
list(REMOVE_DUPLICATES _neurt_core_sources)
# backend_stub.cpp is the NON-Apple arm of neurun's if(QHEXRT_ENABLE_COREML); it
# defines the same make_coreml_backend() as backend.mm. This engine is Apple-only,
# so compiling both would be a duplicate-symbol error.
list(REMOVE_ITEM _neurt_core_sources "NeuRT/src/coreml/backend_stub.cpp")

# Assert discovery is non-empty. A regex that silently matches nothing is the
# exact failure mode the depth-1-globs KB finding is about, and it would show up
# here as an inscrutable "undefined symbol neurt::Generator::load" at link time.
if(NOT _neurt_core_sources)
    message(FATAL_ERROR
        "Could not derive neurt_core's sources from ${NEURT_ROOT}/CMakeLists.txt. "
        "The add_library(neurt_core STATIC ...) / target_sources(neurt_core PRIVATE ...) "
        "blocks moved or changed shape; update this parse.")
endif()

set(_neurt_core_abs "")
set(_neurt_core_objcxx "")
foreach(_src ${_neurt_core_sources})
    list(APPEND _neurt_core_abs "${NEURT_ROOT}/${_src}")
    if(_src MATCHES "\\.mm$")
        list(APPEND _neurt_core_objcxx "${NEURT_ROOT}/${_src}")
    endif()
endforeach()

add_library(rac_neurt_core STATIC ${_neurt_core_abs})
target_include_directories(rac_neurt_core
    PUBLIC  ${NEURT_ROOT}/NeuRT/include
    PRIVATE ${NEURT_ROOT}/NeuRT/src)
target_compile_features(rac_neurt_core PRIVATE cxx_std_17)
target_compile_definitions(rac_neurt_core PUBLIC QHEXRT_HAVE_COREML=1)
set_target_properties(rac_neurt_core PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(rac_neurt_core PUBLIC "-framework CoreML" "-framework Foundation")
# ARC in every .mm — manual retain/release across a C++/ObjC boundary is exactly
# the kind of thing that leaks once per token. neurun's own build does the same.
if(_neurt_core_objcxx)
    set_source_files_properties(${_neurt_core_objcxx} PROPERTIES COMPILE_FLAGS "-fobjc-arc")
endif()

# ---------------------------------------------------------------------------
# rac_neurt_llm_ops — the LLM modality's op-table adapter.
#
# Supplies `g_neurt_llm_ops`, which rac_plugin_entry_neurt.cpp wires into the
# vtable's llm_ops slot. Compiled against the REAL SDK headers
# (NEURT_WITH_RAC_HEADERS=1) rather than the standalone struct mirror that file
# also carries, so a layout drift between the two is a compile error here rather
# than silent UB at dispatch time.
# ---------------------------------------------------------------------------
add_library(rac_neurt_llm_ops STATIC ${_neurt_sdk_dir}/rac_llm_ops_neurt.cpp)
target_include_directories(rac_neurt_llm_ops PRIVATE
    ${RAC_COMMONS_ROOT_DIR}/include
    ${NEURT_ROOT}/NeuRT/include)
target_compile_definitions(rac_neurt_llm_ops PRIVATE NEURT_WITH_RAC_HEADERS=1)
target_compile_features(rac_neurt_llm_ops PRIVATE cxx_std_17)
set_target_properties(rac_neurt_llm_ops PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(rac_neurt_llm_ops PUBLIC rac_neurt_core)

# ---------------------------------------------------------------------------
# rac_neurt_stt_ops — Parakeet TDT/RNNT ANE STT op-table.
# ---------------------------------------------------------------------------
add_library(rac_neurt_stt_ops STATIC ${_neurt_sdk_dir}/rac_stt_ops_neurt.cpp)
target_include_directories(rac_neurt_stt_ops PRIVATE
    ${RAC_COMMONS_ROOT_DIR}/include
    ${NEURT_ROOT}/NeuRT/include
    ${NEURT_ROOT}/NeuRT/src)
target_compile_definitions(rac_neurt_stt_ops PRIVATE NEURT_WITH_RAC_HEADERS=1)
target_compile_features(rac_neurt_stt_ops PRIVATE cxx_std_17)
set_target_properties(rac_neurt_stt_ops PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(rac_neurt_stt_ops PUBLIC rac_neurt_core)

# ---------------------------------------------------------------------------
# The engine plugin itself.
#
# rac_diffusion_coreml.mm keeps `coreml` in its name: it is the DIFFUSION
# modality's Apple-FRAMEWORK implementation (a Stable-Diffusion pipeline over
# CoreML MLModel), not the engine identity — parallel to the cloud engine's
# rac_stt_cloud.cpp. It lives in neurun with the rest of the Apple code.
#
#   * `rac_backend_neurt` — engine implementation + plugin entry symbol
#     (`rac_plugin_entry_neurt`). SHARED_ONLY so tests and the xcframework
#     packaging can link this target directly by name.
#
#   * `runanywhere_neurt` — thin self-registration carrier built from
#     `rac_static_register_neurt.cpp`.
#       - RAC_STATIC_PLUGINS=ON  → ctor added to rac_commons so iOS / WASM
#         hosts schedule RAC_STATIC_PLUGIN_REGISTER(neurt) before main().
#       - RAC_STATIC_PLUGINS=OFF → SHARED carrier whose filename matches the
#         `rac_plugin_entry_neurt` symbol the dlopen loader derives (see
#         plugin_loader.cpp::entry_symbol_from_path), so
#         `rac_registry_load_plugin(librunanywhere_neurt.*)` actually installs
#         the vtable into the registry.
# ---------------------------------------------------------------------------
set(NEURT_SOURCES
    ${_neurt_sdk_dir}/rac_diffusion_coreml.mm
    rac_plugin_entry_neurt.cpp
)

rac_add_engine_plugin(neurt
    TARGET_NAME         rac_backend_neurt
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             ${NEURT_SOURCES}
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
                        ${_neurt_sdk_dir}
    COMPILE_DEFINITIONS RAC_NEURT_GENERATE_AVAILABLE=1
    LINK_LIBRARIES      "-framework Foundation"
                        "-framework CoreML"
                        "-framework Accelerate"
                        rac_runtime_coreml
                        rac_neurt_llm_ops
                        rac_neurt_stt_ops
)

# Self-registration carrier — installs the neurt engine vtable into the unified
# plugin registry. Without this, neither static iOS hosts nor dynamic dlopen
# hosts can route to this engine, because the engine library above does not
# auto-register.
if(RAC_STATIC_PLUGINS)
    # Ctor lands inside rac_commons so it runs before main() on iOS / WASM.
    # The host (xcframework / app target) is expected to link both rac_commons
    # and rac_backend_neurt together; the unresolved `rac_plugin_entry_neurt`
    # reference is satisfied at the final link site, exactly like llamacpp.
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_neurt.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include
    )
else()
    add_library(runanywhere_neurt SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_neurt.cpp
    )
    set_target_properties(runanywhere_neurt PROPERTIES
        OUTPUT_NAME           runanywhere_neurt
        C_VISIBILITY_PRESET   hidden
        CXX_VISIBILITY_PRESET hidden
    )
    target_include_directories(runanywhere_neurt PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
    )
    target_link_libraries(runanywhere_neurt PUBLIC
        rac_backend_neurt
        rac_commons
    )
    install(TARGETS runanywhere_neurt LIBRARY DESTINATION lib)
endif()

message(STATUS "neurt engine Configuration:")
message(STATUS "  Engine: neurt (ANE LLM + CoreML diffusion, both implemented in NeuRT)")
message(STATUS "  NEURT_ROOT:   ${NEURT_ROOT}")
message(STATUS "  NeuRT core:   ${_neurt_core_sources}")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
