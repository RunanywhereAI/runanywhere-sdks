# =============================================================================
# WhisperKit CoreML Backend - STT via Apple Neural Engine
#
# Unlike other backends, WhisperKit CoreML has no C++ inference engine.
# The C++ side provides callback storage, vtable dispatch, and registration.
# Actual inference happens in Swift via registered callbacks to CoreML.
#
# Target declaration migrated to rac_add_engine_plugin().
# =============================================================================

# Per-engine build toggle owned locally. Apple-only — force OFF
# elsewhere so non-Apple builds don't accidentally enable it from a cached
# value.
if(APPLE)
    option(RAC_BACKEND_WHISPERKIT_COREML "Build WhisperKit CoreML backend (Apple Neural Engine STT)" ON)
else()
    set(RAC_BACKEND_WHISPERKIT_COREML OFF CACHE BOOL "" FORCE)
endif()
if(NOT RAC_BACKEND_WHISPERKIT_COREML)
    return()
endif()

message(STATUS "Configuring WhisperKit CoreML backend...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)
if(NOT TARGET rac_runtime_coreml)
    message(FATAL_ERROR "RAC_BACKEND_WHISPERKIT_COREML requires rac_runtime_coreml.")
endif()

# pass3-syn-134: canonical include path lives under sdk/runanywhere-commons/include.
# The repo root has no top-level include/ directory; references to
# ${CMAKE_SOURCE_DIR}/include were silently inert because rac_commons already
# PUBLIC-exposes its own include via $<BUILD_INTERFACE:...>. Aligned with the
# engines/metalrt and engines/diffusion-coreml convention.
get_filename_component(RAC_COMMONS_ROOT_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

set(WHISPERKIT_COREML_BACKEND_SOURCES
    rac_stt_whisperkit_coreml.cpp
    rac_backend_whisperkit_coreml_register.cpp
    rac_plugin_entry_whisperkit_coreml.cpp
)

# TARGET_NAME=rac_backend_whisperkit_coreml preserves the
# historical CMake target name (referenced by the Swift xcframework
# build + tests). CXX_STANDARD=20 matches the original.
rac_add_engine_plugin(whisperkit_coreml
    TARGET_NAME         rac_backend_whisperkit_coreml
    CXX_STANDARD        20
    SOURCES             ${WHISPERKIT_COREML_BACKEND_SOURCES}
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
    LINK_LIBRARIES      rac_runtime_coreml
    RUNTIMES            CORE_ML ANE
    FORMATS             COREML
)

# Self-registration carrier — installs the WhisperKit CoreML vtable into the
# unified plugin registry. Without this, `rac_backend_whisperkit_coreml_register()`
# has zero call sites in the monorepo and STT loads pinned to
# RAC_FRAMEWORK_WHISPERKIT_COREML cannot route. Mirrors the two-mode carrier
# pattern used by llamacpp / diffusion-coreml (see pass2-syn-015 and
# pass3-syn-133 for context).
#
#   * RAC_STATIC_PLUGINS=ON  → ctor lands inside rac_commons so iOS / WASM
#     hosts schedule the register call before main(). The Swift WhisperKit
#     bootstrap typically installs the Swift-side callbacks AFTER this
#     ctor runs; the register function tolerates the inverse order by
#     short-circuiting with RAC_ERROR_BACKEND_UNAVAILABLE — which is fine
#     because no callers depend on this entry until the Swift callbacks land.
#
#   * RAC_STATIC_PLUGINS=OFF → SHARED carrier whose filename matches the
#     `rac_plugin_entry_whisperkit_coreml` symbol the dlopen loader derives
#     (see plugin_loader.cpp::entry_symbol_from_path), so
#     `rac_registry_load_plugin(librunanywhere_whisperkit_coreml.*)` actually
#     installs the vtable into the registry on macOS dev hosts.
if(RAC_STATIC_PLUGINS)
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_whisperkit_coreml.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include
    )
else()
    add_library(runanywhere_whisperkit_coreml SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_whisperkit_coreml.cpp
    )
    set_target_properties(runanywhere_whisperkit_coreml PROPERTIES
        OUTPUT_NAME           runanywhere_whisperkit_coreml
        C_VISIBILITY_PRESET   hidden
        CXX_VISIBILITY_PRESET hidden
    )
    target_include_directories(runanywhere_whisperkit_coreml PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
    )
    target_link_libraries(runanywhere_whisperkit_coreml PUBLIC
        rac_backend_whisperkit_coreml
        rac_commons
    )
    install(TARGETS runanywhere_whisperkit_coreml LIBRARY DESTINATION lib)
endif()

message(STATUS "WhisperKit CoreML Backend Configuration:")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
message(STATUS "  Note: Actual inference runs in Swift via CoreML callbacks")
