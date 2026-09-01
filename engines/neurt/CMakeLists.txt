# =============================================================================
# neurt engine — the Apple engine, implemented by NeuRT.
#
# Engine identity is the RUNTIME THAT IMPLEMENTS IT (`neurt`), not the modality
# and not the vendor framework. It serves DIFFUSION, GENERATE_TEXT and TRANSCRIBE.
#
# NeuRT is closed-source and reaches this repo as PREBUILT ARCHIVES, pinned by
# tag + SHA-256 in core/VERSIONS and fetched by scripts/build/download-neurt.sh.
# No NeuRT source enters this repo.
#
# NOTE: the engine `neurt` still USES the runtime `coreml` (runtimes/coreml) and
# declares the COREML model FORMAT. Those name the Apple FRAMEWORK, not this
# engine — deliberately NOT renamed.
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

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../core" ABSOLUTE)

# macOS-arm64 and the iOS simulator are both arm64 but carry different platform
# load commands; the linker rejects a mismatch, so they stay separate slices.
set(_neurt_slice "")
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
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
    set(_candidate "${RAC_COMMONS_ROOT_DIR}/third_party/neurt/${_neurt_slice}")
    if(EXISTS "${_candidate}/RECEIPT.json")
        set(NEURT_PREBUILT_ROOT "${_candidate}")
    endif()
endif()

set(_neurt_available FALSE)
if(NEURT_PREBUILT_ROOT)
    set(_neurt_available TRUE)
    foreach(_probe
            "${NEURT_PREBUILT_ROOT}/RECEIPT.json"
            "${NEURT_PREBUILT_ROOT}/include/rac_diffusion_coreml.h"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_core.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_llm_ops.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_stt_ops.a"
            # Required, not optional: the vtable below references &g_neurt_embeddings_ops under
            # RAC_NEURT_ROUTABLE, so a prebuilt without this archive fails at link with an
            # undefined symbol rather than merely lacking a capability. It ships from the same
            # neurun release as the other four — this list and core/VERSIONS move together.
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_embedding_ops.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_rerank_ops.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_vlm_ops.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_image_embedding_ops.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_tts_ops.a"
            "${NEURT_PREBUILT_ROOT}/lib/libneurt_rac_diffusion.a")
        if(NOT EXISTS "${_probe}")
            message(FATAL_ERROR
                "NEURT_PREBUILT_ROOT=${NEURT_PREBUILT_ROOT} is incomplete: ${_probe} is missing. "
                "Re-run scripts/build/download-neurt.sh --slice ${_neurt_slice} --force.")
        endif()
    endforeach()

    # The receipt check is the safety argument for linking binaries built
    # elsewhere: a vtable-layout change relinks cleanly and corrupts dispatch at
    # runtime, and a static archive resolves no symbols, so nothing else catches it.
    # CMAKE_MATCH_1 is GLOBAL and STALE on a failed match: it keeps the previous
    # match's capture. Reading it without checking the match variable would let a
    # failed second regex silently reuse the first one's value -- and since both
    # patterns capture the same ABI number, that produces a FALSE PASS rather than
    # an error. Check each match before using its capture.
    file(READ "${NEURT_PREBUILT_ROOT}/RECEIPT.json" _neurt_receipt)
    string(REGEX MATCH "\"rac_plugin_api_version\"[ \t]*:[ \t]*([0-9]+)" _m "${_neurt_receipt}")
    if(_m STREQUAL "")
        message(FATAL_ERROR "NeuRT receipt has no rac_plugin_api_version: ${NEURT_PREBUILT_ROOT}/RECEIPT.json")
    endif()
    set(_neurt_receipt_abi "${CMAKE_MATCH_1}")
    file(READ "${RAC_COMMONS_ROOT_DIR}/include/rac/plugin/rac_plugin_entry.h" _rac_entry_hdr)
    string(REGEX MATCH "#define[ \t]+RAC_PLUGIN_API_VERSION[ \t]+([0-9]+)" _m2 "${_rac_entry_hdr}")
    if(_m2 STREQUAL "")
        message(FATAL_ERROR "Could not find RAC_PLUGIN_API_VERSION in rac_plugin_entry.h")
    endif()
    set(_neurt_local_abi "${CMAKE_MATCH_1}")
    if(NOT _neurt_receipt_abi OR NOT _neurt_local_abi)
        message(FATAL_ERROR "Could not read the plugin ABI version from the NeuRT receipt "
                            "(${_neurt_receipt_abi}) or rac_plugin_entry.h (${_neurt_local_abi}).")
    endif()
    if(NOT _neurt_receipt_abi STREQUAL _neurt_local_abi)
        message(FATAL_ERROR
            "NeuRT prebuilt was built against RAC_PLUGIN_API_VERSION=${_neurt_receipt_abi}, "
            "but this repo is at ${_neurt_local_abi}. Re-pin core/VERSIONS::NEURT_RELEASE_TAG.")
    endif()
endif()

# Exported so consumers outside this directory can tell "the target exists" from
# "the engine is routable" — core/tests gates a diffusion test on it.
set(RAC_NEURT_ENGINE_AVAILABLE ${_neurt_available}
    CACHE INTERNAL "neurt engine is routable (a prebuilt slice was found)")

option(RAC_REQUIRE_NEURT_ENGINE
    "Fail configure unless a real NeuRT prebuilt is present (desktop overlay CI)"
    OFF)
if(RAC_REQUIRE_NEURT_ENGINE AND NOT _neurt_available)
    message(FATAL_ERROR
        "RAC_REQUIRE_NEURT_ENGINE=ON but no NeuRT prebuilt was found for '${_neurt_slice}'. "
        "Run: NEURUN_TOKEN=... scripts/build/download-neurt.sh --slice ${_neurt_slice}")
endif()

if(NOT _neurt_available)
    message(STATUS "  neurt: no prebuilt slice — building the non-routable shell "
                   "(registration refused with RAC_ERROR_BACKEND_UNAVAILABLE).")
    message(STATUS "  neurt: run scripts/build/download-neurt.sh --slice ${_neurt_slice} "
                   "(needs NEURUN_TOKEN) for the real engine.")
endif()

# No prefix-maps here: they are applied when the archives are built, and the
# publisher refuses to ship one that leaks a host path. That matters because
# build-core-xcframework.sh rejects any archive containing a `/Users/` marker.
if(_neurt_available)
    add_library(rac_neurt_core STATIC IMPORTED GLOBAL)
    set_target_properties(rac_neurt_core PROPERTIES
        IMPORTED_LOCATION "${NEURT_PREBUILT_ROOT}/lib/libneurt_core.a"
        INTERFACE_COMPILE_DEFINITIONS "QHEXRT_HAVE_COREML=1")
    target_link_libraries(rac_neurt_core INTERFACE "-framework CoreML" "-framework Foundation")

    foreach(_pair "rac_neurt_llm_ops:libneurt_rac_llm_ops.a"
                  "rac_neurt_stt_ops:libneurt_rac_stt_ops.a"
                  "rac_neurt_embedding_ops:libneurt_rac_embedding_ops.a"
                  "rac_neurt_rerank_ops:libneurt_rac_rerank_ops.a"
                  "rac_neurt_vlm_ops:libneurt_rac_vlm_ops.a"
                  "rac_neurt_image_embedding_ops:libneurt_rac_image_embedding_ops.a"
                  "rac_neurt_tts_ops:libneurt_rac_tts_ops.a"
                  "rac_neurt_diffusion:libneurt_rac_diffusion.a")
        string(REPLACE ":" ";" _parts "${_pair}")
        list(GET _parts 0 _tgt)
        list(GET _parts 1 _archive)
        add_library(${_tgt} STATIC IMPORTED GLOBAL)
        set_target_properties(${_tgt} PROPERTIES
            IMPORTED_LOCATION "${NEURT_PREBUILT_ROOT}/lib/${_archive}")
        target_link_libraries(${_tgt} INTERFACE rac_neurt_core)
    endforeach()

    set(_neurt_extra_includes ${NEURT_PREBUILT_ROOT}/include)
    set(_neurt_generate_available 1)
    set(_neurt_extra_links rac_neurt_llm_ops rac_neurt_stt_ops rac_neurt_embedding_ops
                           rac_neurt_rerank_ops rac_neurt_vlm_ops
                           rac_neurt_image_embedding_ops rac_neurt_tts_ops
                           rac_neurt_diffusion)
else()
    set(_neurt_extra_includes "")
    set(_neurt_generate_available 0)
    set(_neurt_extra_links "")
endif()

#   * `rac_backend_neurt` — plugin entry symbol (`rac_plugin_entry_neurt`).
#     SHARED_ONLY so tests and xcframework packaging can link it by name.
#   * `runanywhere_neurt` — self-registration carrier. Its FILENAME must match
#     the entry symbol the dlopen loader derives, or the vtable is never
#     installed (plugin_loader.cpp::entry_symbol_from_path).
rac_add_engine_plugin(neurt
    TARGET_NAME         rac_backend_neurt
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             rac_plugin_entry_neurt.cpp
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

if(RAC_STATIC_PLUGINS)
    # Ctor lands inside rac_commons so it runs before main() on iOS / WASM; the
    # unresolved entry reference is satisfied at the final link site.
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_neurt.cpp)
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include)
else()
    add_library(runanywhere_neurt SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_neurt.cpp)
    set_target_properties(runanywhere_neurt PROPERTIES
        OUTPUT_NAME           runanywhere_neurt
        C_VISIBILITY_PRESET   hidden
        CXX_VISIBILITY_PRESET hidden)
    target_include_directories(runanywhere_neurt PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include)
    target_link_libraries(runanywhere_neurt PUBLIC rac_backend_neurt rac_commons)
    install(TARGETS runanywhere_neurt LIBRARY DESTINATION lib)
endif()

message(STATUS "neurt engine Configuration:")
if(_neurt_available)
    message(STATUS "  Mode:     PREBUILT (${_neurt_slice}, ABI ${_neurt_receipt_abi})")
else()
    message(STATUS "  Mode:     SHELL (not routable)")
endif()
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
