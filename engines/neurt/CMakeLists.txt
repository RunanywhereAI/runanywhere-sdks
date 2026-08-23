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

include(${RAC_ROOT_DIR}/cmake/plugins.cmake)
if(NOT TARGET rac_runtime_coreml)
    message(FATAL_ERROR "RAC_BACKEND_NEURT requires rac_runtime_coreml.")
endif()

# Objective-C++ language is enabled at root level (CMakeLists.txt) so
# CMAKE_OBJCXX_COMPILE_OBJECT is populated when this subdirectory runs.

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../core" ABSOLUTE)

# ---------------------------------------------------------------------------
# PREBUILT MODE — the normal path. Link archives published by the private
# `neurun` repo instead of compiling its source.
#
# This is the boundary described in core/VERSIONS::NEURT_*. neurun builds its own
# code and publishes per-slice archives to a private GitHub Release;
# scripts/build/download-neurt.sh fetches and verifies them into
# third_party/neurt/<slice>/. Nothing here needs neurun's source or its checkout.
#
# WHY THIS REPLACED SOURCE MODE. Source mode resolved a NEURT_ROOT checkout of a
# PRIVATE repo and then REGEX-PARSED neurun's root CMakeLists.txt to recover
# neurt_core's source list. Two consequences: only someone holding that private
# repo could build this repo's Apple release, and a stray `)` inside a comment
# over there silently dropped NeuRT/src/neurt_c.cpp from this build. Source mode
# is kept below for local engine development, but it is no longer how releases
# are built.
# ---------------------------------------------------------------------------
set(_neurt_slice "")
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # macOS-arm64 and the iOS simulator are BOTH arm64 but carry different
    # platform load commands; the linker rejects a mismatch. Never collapse them.
    if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
        set(_neurt_slice "ios-arm64-simulator")
    else()
        set(_neurt_slice "ios-arm64")
    endif()
elseif(APPLE)
    set(_neurt_slice "macos-arm64")
endif()

if(NOT DEFINED NEURT_PREBUILT_ROOT AND DEFINED ENV{NEURT_PREBUILT_ROOT})
    set(NEURT_PREBUILT_ROOT "$ENV{NEURT_PREBUILT_ROOT}")
endif()
if(NOT DEFINED NEURT_PREBUILT_ROOT AND _neurt_slice)
    # core/third_party/ — already gitignored, and where every other vendored download
    # lands (sherpa-onnx, onnxruntime). Kept in sync with download-neurt.sh's DEST_ROOT.
    set(_neurt_prebuilt_candidate "${RAC_COMMONS_ROOT_DIR}/third_party/neurt/${_neurt_slice}")
    if(EXISTS "${_neurt_prebuilt_candidate}/RECEIPT.json")
        set(NEURT_PREBUILT_ROOT "${_neurt_prebuilt_candidate}")
    endif()
endif()

set(_neurt_prebuilt FALSE)
if(NEURT_PREBUILT_ROOT)
    set(_neurt_prebuilt TRUE)
    foreach(_probe
            "${NEURT_PREBUILT_ROOT}/RECEIPT.json"
            "${NEURT_PREBUILT_ROOT}/include/rac_diffusion_coreml.h"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_core.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_llm_ops.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_stt_ops.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_diffusion.a")
        if(NOT EXISTS "${_probe}")
            message(FATAL_ERROR
                "NEURT_PREBUILT_ROOT=${NEURT_PREBUILT_ROOT} is incomplete: ${_probe} is missing. "
                "Re-run scripts/build/download-neurt.sh --slice ${_neurt_slice} --force.")
        endif()
    endforeach()

    # Re-check the ABI receipt HERE as well as in the downloader. The downloader is
    # the normal path, but a hand-placed or hand-edited tree never passed through it,
    # and this is the last point before the archives are linked. A vtable-layout
    # mismatch links cleanly and corrupts dispatch at runtime — a static archive
    # resolves no symbols, so nothing downstream would catch it.
    file(READ "${NEURT_PREBUILT_ROOT}/RECEIPT.json" _neurt_receipt)
    string(REGEX MATCH "\"rac_plugin_api_version\"[ \t]*:[ \t]*([0-9]+)" _m "${_neurt_receipt}")
    set(_neurt_receipt_abi "${CMAKE_MATCH_1}")
    file(READ "${RAC_COMMONS_ROOT_DIR}/include/rac/plugin/rac_plugin_entry.h" _rac_entry_hdr)
    string(REGEX MATCH "#define[ \t]+RAC_PLUGIN_API_VERSION[ \t]+([0-9]+)" _m2 "${_rac_entry_hdr}")
    set(_neurt_local_abi "${CMAKE_MATCH_1}")
    if(NOT _neurt_receipt_abi OR NOT _neurt_local_abi)
        message(FATAL_ERROR
            "Could not read the plugin ABI version from the NeuRT receipt "
            "(${_neurt_receipt_abi}) or rac_plugin_entry.h (${_neurt_local_abi}).")
    endif()
    if(NOT _neurt_receipt_abi STREQUAL _neurt_local_abi)
        message(FATAL_ERROR
            "NeuRT prebuilt was compiled against RAC_PLUGIN_API_VERSION=${_neurt_receipt_abi}, "
            "but this repo is at ${_neurt_local_abi}. Cut a new neurun release and re-pin "
            "core/VERSIONS::NEURT_RELEASE_TAG.")
    endif()

    message(STATUS "  neurt: PREBUILT ${_neurt_slice} (ABI ${_neurt_receipt_abi}) from ${NEURT_PREBUILT_ROOT}")
endif()

# ---------------------------------------------------------------------------
# NEURT_ROOT — the sibling `neurun` checkout that implements this engine.
#
# LOCAL ENGINE DEVELOPMENT ONLY. Releases use prebuilt mode above. This path is
# what you want when changing NeuRT itself and iterating without cutting a
# neurun release each time.
#
# Discovery is by PATH, not by a hardcoded sibling: set -DNEURT_ROOT=<neurun>
# (or export NEURT_ROOT). Walk to it by MARKER (Makefile + CMakeLists.txt),
# never by counting `../` hops — a hop count silently resolves to the wrong
# directory the moment a level is inserted (neurun KB:
# depth-1-globs-break-on-reorg).
# ---------------------------------------------------------------------------
if(NOT DEFINED NEURT_ROOT AND DEFINED ENV{NEURT_ROOT})
    set(NEURT_ROOT "$ENV{NEURT_ROOT}")
endif()
if(NOT DEFINED NEURT_ROOT)
    get_filename_component(_rac_parent "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
    if(EXISTS "${_rac_parent}/neurun/CMakeLists.txt" AND EXISTS "${_rac_parent}/neurun/Makefile")
        set(NEURT_ROOT "${_rac_parent}/neurun")
    endif()
endif()

set(_neurt_sdk_dir "${NEURT_ROOT}/NeuRT/src/sdk")
set(_neurt_required_paths
    "${NEURT_ROOT}/CMakeLists.txt"
    "${_neurt_sdk_dir}/rac_llm_ops_neurt.cpp"
    "${_neurt_sdk_dir}/rac_stt_ops_neurt.cpp"
    "${_neurt_sdk_dir}/rac_diffusion_coreml.mm")

# Source mode is only consulted when there is no prebuilt. Prebuilt WINS: it is the
# release path, and silently preferring a developer's local checkout over the pinned,
# checksum-verified archives would make a release depend on whatever happened to be on
# the build machine.
set(_neurt_from_source FALSE)
set(_neurt_missing_required_path "")
if(NOT _neurt_prebuilt AND NEURT_ROOT)
    set(_neurt_from_source TRUE)
    foreach(_neurt_required_path IN LISTS _neurt_required_paths)
        if(NOT EXISTS "${_neurt_required_path}")
            set(_neurt_from_source FALSE)
            set(_neurt_missing_required_path "${_neurt_required_path}")
            break()
        endif()
    endforeach()
endif()

set(_neurt_available FALSE)
if(_neurt_prebuilt OR _neurt_from_source)
    set(_neurt_available TRUE)
endif()

# Exported because consumers OUTSIDE this directory must distinguish "the engine target exists"
# from "the engine is routable" — in shell mode `TARGET rac_backend_neurt` is true but the neurun
# headers are not on any include path. core/tests gates
# test_diffusion_coreml_generate on this: it includes rac_diffusion_coreml.h, which arrives only
# through the routable build's include dirs.
set(RAC_NEURT_ENGINE_AVAILABLE ${_neurt_available}
    CACHE INTERNAL "neurt engine is routable (the neurun checkout was found)")

# ---------------------------------------------------------------------------
# TWO MODES, mirroring the QHexRT engine — the other closed-source, RunAnywhere-
# owned dependency whose source never enters this repo.
#
#   1) Engine NOT available (no neurun checkout — the case on every CI host):
#      only the shell (rac_plugin_entry_neurt.cpp) compiles. It publishes a
#      NOT-ROUTABLE, all-NULL vtable and its capability check returns
#      RAC_ERROR_BACKEND_UNAVAILABLE, so registration is REJECTED rather than
#      accepted-and-useless. Nothing references a neurun symbol, so it links.
#
#   2) Engine IS available (NEURT_ROOT resolves): the full engine, unchanged.
#
# This replaces a FATAL_ERROR. The error was defending against a real hazard —
# "an engine that registers, claims Apple availability, and then serves nothing"
# — but a hard stop is the wrong instrument for it, and it made every Apple job
# in CI unbuildable (macos-debug/release, ios-device, rcli-macos, swift-spm,
# python-macos all died at configure) because `neurun` is a separate PRIVATE
# repo that CI cannot clone. The stub closes the hazard directly instead: an
# unavailable engine refuses registration, which is strictly stronger than
# refusing to build. Same argument QHexRT already settled the same way.
# ---------------------------------------------------------------------------
if(NOT _neurt_available)
    message(STATUS
        "  neurt: neurun checkout NOT found or incomplete — building the non-routable shell "
        "(registration will be refused with RAC_ERROR_BACKEND_UNAVAILABLE).")
    if(_neurt_missing_required_path)
        message(STATUS "  neurt: missing required path: ${_neurt_missing_required_path}")
    endif()
    message(STATUS
        "  neurt: run scripts/build/download-neurt.sh --slice ${_neurt_slice} for the real "
        "engine (needs NEURUN_TOKEN), or pass -DNEURT_ROOT=/path/to/neurun to build it "
        "from source.")
endif()

if(_neurt_prebuilt)

# ---------------------------------------------------------------------------
# Prebuilt: import the published archives as IMPORTED targets.
#
# The target NAMES are identical to source mode's, so everything below this block
# — the plugin target, its link list, the packaging — is mode-agnostic and there
# is no second code path to keep in sync.
#
# No prefix-maps are needed: neurun applies them at compile time, and its
# packaging script refuses to publish an archive that leaks a host path. That is
# load-bearing for this repo, whose xcframework packaging runs
# sanitize_and_validate_archive_host_paths and rejects any `/Users/` marker.
# ---------------------------------------------------------------------------
add_library(rac_neurt_core STATIC IMPORTED GLOBAL)
set_target_properties(rac_neurt_core PROPERTIES
    IMPORTED_LOCATION "${NEURT_PREBUILT_ROOT}/lib/libneurt_core.a"
    INTERFACE_COMPILE_DEFINITIONS "QHEXRT_HAVE_COREML=1")
target_link_libraries(rac_neurt_core INTERFACE "-framework CoreML" "-framework Foundation")

foreach(_pair "rac_neurt_llm_ops:libneurt_rac_llm_ops.a"
              "rac_neurt_stt_ops:libneurt_rac_stt_ops.a"
              "rac_neurt_diffusion:libneurt_rac_diffusion.a")
    string(REPLACE ":" ";" _parts "${_pair}")
    list(GET _parts 0 _tgt)
    list(GET _parts 1 _archive)
    add_library(${_tgt} STATIC IMPORTED GLOBAL)
    set_target_properties(${_tgt} PROPERTIES
        IMPORTED_LOCATION "${NEURT_PREBUILT_ROOT}/lib/${_archive}")
    target_link_libraries(${_tgt} INTERFACE rac_neurt_core)
endforeach()

# Source mode compiles rac_diffusion_coreml.mm into rac_backend_neurt itself; in
# prebuilt mode it arrives as its own archive, so the plugin links it instead.
set(_neurt_prefix_maps "")

elseif(_neurt_from_source)

# ---------------------------------------------------------------------------
# rac_neurt_core — NeuRT's runtime, compiled from neurun's own source list.
#
# LOCAL DEVELOPMENT PATH. Releases take the prebuilt branch above. Everything in
# this branch — including the CMakeLists parse below — exists so a NeuRT change
# can be iterated on without cutting a neurun release first.
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
# Canonicalize NEURT_ROOT out of embedded paths.
#
# These sources compile from the SIBLING neurun checkout, which is OUTSIDE this
# repo — so the -ffile-prefix-map=${REPO_ROOT} that build-core-xcframework.sh
# applies globally via CMAKE_<LANG>_FLAGS cannot reach them, and the objects keep
# an absolute /Users/... string from __FILE__ / debug info. The packaging step's
# sanitize_and_validate_archive_host_paths then REFUSES the archive with
# "still contains unreviewed host path marker(s): /Users/", which fails the whole
# xcframework build at the very last step. Mapping NEURT_ROOT the same way the
# SDK maps its own root makes this slice byte-reproducible from any checkout
# location, rather than papering over it with a fixed-length string replacement
# in the packaging script (which would break the moment neurun moves).
# ---------------------------------------------------------------------------
set(_neurt_prefix_maps
    "-ffile-prefix-map=${NEURT_ROOT}=/neurun"
    "-fmacro-prefix-map=${NEURT_ROOT}=/neurun"
    "-fdebug-prefix-map=${NEURT_ROOT}=/neurun")
target_compile_options(rac_neurt_core PRIVATE ${_neurt_prefix_maps})

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
target_compile_options(rac_neurt_llm_ops PRIVATE ${_neurt_prefix_maps})
set_target_properties(rac_neurt_llm_ops PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(rac_neurt_llm_ops PUBLIC rac_neurt_core)

# rac_neurt_stt_ops — the SPEECH modality's op-table adapter, same shape and same reasoning.
#
# Supplies `g_neurt_stt_ops` for the vtable's stt_ops slot. Also compiled against the real headers:
# its standalone mirror had FOUR drifts on the first pass, including `sample_rate` at the wrong
# offset, and this lane is what caught them before anything linked.
add_library(rac_neurt_stt_ops STATIC ${_neurt_sdk_dir}/rac_stt_ops_neurt.cpp)
target_include_directories(rac_neurt_stt_ops PRIVATE
    ${RAC_COMMONS_ROOT_DIR}/include
    ${NEURT_ROOT}/NeuRT/include)
target_compile_definitions(rac_neurt_stt_ops PRIVATE NEURT_WITH_RAC_HEADERS=1)
target_compile_features(rac_neurt_stt_ops PRIVATE cxx_std_17)
target_compile_options(rac_neurt_stt_ops PRIVATE ${_neurt_prefix_maps})
set_target_properties(rac_neurt_stt_ops PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(rac_neurt_stt_ops PUBLIC rac_neurt_core)

else()
    # Shell mode: no neurun sources to derive, so no rac_neurt_core /
    # rac_neurt_llm_ops targets exist. `_neurt_prefix_maps` is still referenced
    # unconditionally below, so define it empty rather than leaving it unset.
    set(_neurt_prefix_maps "")
endif()  # _neurt_available

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
if(_neurt_prebuilt)
    # Only the public plugin entry compiles here. rac_diffusion_coreml.mm arrives
    # as an archive, and its header comes from the prebuilt include dir — the ONE
    # private header this repo needs, and it includes nothing but public SDK headers.
    set(NEURT_SOURCES rac_plugin_entry_neurt.cpp)
    set(_neurt_extra_includes ${NEURT_PREBUILT_ROOT}/include)
    set(_neurt_generate_available 1)
    set(_neurt_extra_links rac_neurt_llm_ops rac_neurt_stt_ops rac_neurt_diffusion)
elseif(_neurt_from_source)
    set(NEURT_SOURCES
        ${_neurt_sdk_dir}/rac_diffusion_coreml.mm
        rac_plugin_entry_neurt.cpp
    )
    set(_neurt_extra_includes ${_neurt_sdk_dir})
    set(_neurt_generate_available 1)
    set(_neurt_extra_links rac_neurt_llm_ops rac_neurt_stt_ops)
else()
    # Shell only. No neurun source, no private include dir, no rac_neurt_llm_ops
    # to link — RAC_NEURT_GENERATE_AVAILABLE=0 makes the entry file compile its
    # not-routable arm, which references none of those.
    set(NEURT_SOURCES rac_plugin_entry_neurt.cpp)
    set(_neurt_extra_includes "")
    set(_neurt_generate_available 0)
    set(_neurt_extra_links "")
endif()

rac_add_engine_plugin(neurt
    TARGET_NAME         rac_backend_neurt
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             ${NEURT_SOURCES}
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
                        ${_neurt_extra_includes}
    COMPILE_DEFINITIONS RAC_NEURT_GENERATE_AVAILABLE=${_neurt_generate_available}
    LINK_LIBRARIES      "-framework Foundation"
                        "-framework CoreML"
                        "-framework Accelerate"
                        rac_runtime_coreml
                        ${_neurt_extra_links}
)

# NEURT_SOURCES pulls rac_diffusion_coreml.mm straight out of NEURT_ROOT, so this
# target — not just the rac_neurt_* libs above — is the one whose objects carry an
# absolute host path. It is the object that actually lands in the packaged
# librac_backend_neurt.a, so without this the xcframework build fails its
# host-path audit at the final step. See the _neurt_prefix_maps comment above.
target_compile_options(rac_backend_neurt PRIVATE ${_neurt_prefix_maps})

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
if(_neurt_prebuilt)
    message(STATUS "  Mode:     PREBUILT (${_neurt_slice}, ABI ${_neurt_receipt_abi})")
    message(STATUS "  Archives: ${NEURT_PREBUILT_ROOT}/lib")
elseif(_neurt_from_source)
    message(STATUS "  Mode:       SOURCE (local development)")
    message(STATUS "  NEURT_ROOT: ${NEURT_ROOT}")
    message(STATUS "  NeuRT core: ${_neurt_core_sources}")
else()
    message(STATUS "  Mode:     SHELL (not routable)")
endif()
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
