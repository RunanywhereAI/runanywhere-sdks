# =============================================================================
# WhisperKit CoreML Backend - STT via Apple Neural Engine
#
# Unlike other backends, WhisperKit CoreML has no C++ inference engine.
# The C++ side provides callback storage, vtable dispatch, and registration.
# Actual inference happens in Swift via registered callbacks to CoreML.
#
# v3.1.2: target declaration migrated to rac_add_engine_plugin().
# =============================================================================

# T5.4: per-engine build toggle owned locally. Apple-only — force OFF
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

set(WHISPERKIT_COREML_BACKEND_SOURCES
    rac_stt_whisperkit_coreml.cpp
    rac_backend_whisperkit_coreml_register.cpp
    rac_plugin_entry_whisperkit_coreml.cpp
)

# v3.1.2: TARGET_NAME=rac_backend_whisperkit_coreml preserves the
# historical CMake target name (referenced by the Swift xcframework
# build + tests). CXX_STANDARD=20 matches the original.
rac_add_engine_plugin(whisperkit_coreml
    TARGET_NAME         rac_backend_whisperkit_coreml
    CXX_STANDARD        20
    SOURCES             ${WHISPERKIT_COREML_BACKEND_SOURCES}
    INCLUDE_DIRECTORIES ${CMAKE_SOURCE_DIR}/include
    LINK_LIBRARIES      rac_runtime_coreml
    RUNTIMES            CORE_ML ANE
    FORMATS             COREML
)

# Self-registration shim — installs the WhisperKit CoreML vtable into the
# unified plugin registry via a file-scope ctor. Without this,
# `rac_backend_whisperkit_coreml_register()` has zero call sites in the
# monorepo and STT loads pinned to RAC_FRAMEWORK_WHISPERKIT_COREML cannot
# route. Mirrors the carrier pattern used by llamacpp / diffusion-coreml
# (see pass2-syn-015 for context).
#
# Static path only: when RAC_STATIC_PLUGINS=ON (iOS / WASM hosts), the
# ctor lands inside rac_commons so it runs before main(). The Swift WhisperKit
# bootstrap will install the Swift-side callbacks first; the register
# function tolerates the inverse order by short-circuiting with
# RAC_ERROR_BACKEND_UNAVAILABLE — which is fine because no callers depend
# on this entry until the Swift callbacks land.
if(RAC_STATIC_PLUGINS)
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_whisperkit_coreml.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
endif()

message(STATUS "WhisperKit CoreML Backend Configuration:")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
message(STATUS "  Note: Actual inference runs in Swift via CoreML callbacks")
