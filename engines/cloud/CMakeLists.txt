# =============================================================================
# cloud backend — generic HTTP engine (STT today; Sarvam first provider)
#
# A real engine plugin (mirrors engines/sherpa): publishes a `"cloud"` engine in
# the plugin registry. Its NAME is modality-agnostic — it serves
# RAC_PRIMITIVE_TRANSCRIBE (STT) today via its STT-modality op-table, and future
# modalities (TTS / LLM / embeddings) attach by filling more vtable op-tables.
# Routable via `rac_plugin_find_for_engine(RAC_PRIMITIVE_TRANSCRIBE, "cloud")`.
# The concrete provider is chosen per-service from the create config
# (`{"provider":"sarvam"}`). Cloud engine: no local runtime / model file — the
# manifest declares zero runtimes + zero formats (see rac_plugin_entry_cloud.cpp),
# so the router treats it as always-eligible.
#
# CROSS-PLATFORM BUILDABILITY:
#   The engine is lightweight — its only deps are the commons HTTP client ABI +
#   nlohmann_json (header-only). It must build on EVERY platform, including the
#   static-plugin hosts (iOS / macOS-xcframework / WASM), so the Swift binding's
#   `rac_backend_cloud_register` symbol LINKS. To achieve that:
#     * RAC_STATIC_PLUGINS=ON (iOS / WASM): the backend SOURCES FOLD INTO
#       rac_commons (no SHARED_ONLY), so the register fn + ops + provider table
#       are part of rac_commons and resolve at the final link with zero extra
#       wiring.
#     * Dynamic hosts (Android / Linux / macOS dev): built as a standalone
#       SHARED_ONLY library (rac_backend_cloud) with default visibility so
#       its register + entry symbols stay resolvable from the commons JNI .so /
#       sibling loader, exactly like the other in-tree engines.
# =============================================================================

option(RAC_BACKEND_CLOUD "Build cloud HTTP backend (STT today)" ON)
if(NOT RAC_BACKEND_CLOUD)
    return()
endif()

message(STATUS "Configuring cloud backend...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

# NOTE: rac_static_register_cloud.cpp is intentionally NOT in this list — it
# is the self-registration carrier (see the bottom of this file) and is compiled
# either into rac_commons (RAC_STATIC_PLUGINS=ON) or into the runanywhere_cloud
# SHARED shim, exactly like sherpa. Listing it here too would double-expand
# RAC_STATIC_REGISTER_BACKEND(cloud) and collide the registrar symbols.
#
# rac_stt_cloud.cpp + providers/sarvam.cpp keep their `stt` naming: they are the
# cloud engine's STT MODALITY (its op-table + provider adapter), not the engine
# identity.
set(CLOUD_BACKEND_SOURCES
    rac_stt_cloud.cpp
    providers/sarvam.cpp
    rac_plugin_entry_cloud.cpp
    rac_backend_cloud_register.cpp
)

# SHARED_ONLY only on dynamic-plugin hosts. On RAC_STATIC_PLUGINS=ON hosts we
# DROP it so the SOURCES fold into rac_commons (see banner above), which is what
# lets the iOS / WASM Swift binding link rac_backend_cloud_register directly.
if(RAC_STATIC_PLUGINS)
    set(_CLOUD_SHARED_ONLY_ARG "")
else()
    set(_CLOUD_SHARED_ONLY_ARG SHARED_ONLY)
endif()

rac_add_engine_plugin(cloud
    TARGET_NAME         rac_backend_cloud
    CXX_STANDARD        17
    ${_CLOUD_SHARED_ONLY_ARG}
    SOURCES             ${CLOUD_BACKEND_SOURCES}
    LINK_LIBRARIES      nlohmann_json::nlohmann_json
    INCLUDE_DIRECTORIES ${CMAKE_CURRENT_SOURCE_DIR}
                        ${CMAKE_CURRENT_SOURCE_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include
                        ${CMAKE_CURRENT_SOURCE_DIR}/..  # engines/ — for engines/common/*.h
)

# Platform tweaks — Android log linkage + page alignment, matching the other
# in-tree engines. Hidden visibility is intentionally left default by
# rac_add_engine_plugin for SHARED_ONLY engines so the plugin entry + register
# symbols stay resolvable from the JNI .so. Guarded on the target existing
# because the RAC_STATIC_PLUGINS fold path produces no standalone target.
if(RAC_PLATFORM_ANDROID AND TARGET rac_backend_cloud)
    target_link_libraries(rac_backend_cloud PRIVATE log)
    target_compile_options(rac_backend_cloud PRIVATE -O3 -ffunction-sections -fdata-sections)
    rac_apply_android_page_alignment(rac_backend_cloud)
endif()

# =============================================================================
# JNI bridge attachment
# =============================================================================
# Attach the cloud JNI TU (plugin register quartet + STT-modality create/
# transcribe factory thunks) to the commons JNI .so. The commons JNI CMakeLists
# is processed before engines/ and cannot see RAC_BACKEND_CLOUD, so the wiring
# lives here. Guarantees the CloudBridge native symbols (nativeRegister /
# racSttCloud*) land in librunanywhere_jni.so whenever this engine is built.
# (Android is a dynamic-plugin host, so rac_backend_cloud exists here.)
if(TARGET runanywhere_commons_jni)
    target_sources(runanywhere_commons_jni PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/jni/rac_cloud_jni.cpp
    )
    if(TARGET rac_backend_cloud)
        target_link_libraries(runanywhere_commons_jni rac_backend_cloud)
    endif()
    target_include_directories(runanywhere_commons_jni PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${RAC_COMMONS_ROOT_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/..  # engines/ — for engines/common/*.h via ../../common
    )
endif()

# =============================================================================
# Self-registration carrier
# =============================================================================
# Mirrors the sherpa / onnx pattern: thin shim that wraps
# RAC_STATIC_REGISTER_BACKEND(cloud). On RAC_STATIC_PLUGINS=ON hosts
# (iOS / WASM) the ctor lands inside rac_commons and fires before main(),
# routing through rac_backend_cloud_register() — whose definition is also in
# rac_commons on those hosts (the SOURCES folded in above). On dynamic hosts the
# shim becomes a SHARED library whose only export is the entry symbol; the actual
# op functions + register fns live in rac_backend_cloud.
if(RAC_STATIC_PLUGINS)
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_cloud.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${RAC_COMMONS_ROOT_DIR}/include
    )
else()
    add_library(runanywhere_cloud SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_cloud.cpp
    )
    set_target_properties(runanywhere_cloud PROPERTIES
        OUTPUT_NAME           runanywhere_cloud
        C_VISIBILITY_PRESET   hidden
        CXX_VISIBILITY_PRESET hidden
    )
    target_include_directories(runanywhere_cloud PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${RAC_COMMONS_ROOT_DIR}/include
    )
    target_link_libraries(runanywhere_cloud PUBLIC
        rac_backend_cloud
        rac_commons
    )
    rac_apply_android_page_alignment(runanywhere_cloud)
    install(TARGETS runanywhere_cloud LIBRARY DESTINATION lib)
endif()

message(STATUS "Cloud Backend Configuration:")
message(STATUS "  Engine: cloud (HTTP; STT/TRANSCRIBE today; providers: sarvam)")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
