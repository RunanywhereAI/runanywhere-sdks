# =============================================================================
# WhisperKit CoreML Backend - STT via Apple Neural Engine
#
# Unlike other backends, WhisperKit CoreML has no C++ inference engine.
# The C++ side provides callback storage, vtable dispatch, and registration.
# Actual inference happens in Swift via registered callbacks to CoreML.
#
# v3.1.2: target declaration migrated to rac_add_engine_plugin().
# =============================================================================

message(STATUS "Configuring WhisperKit CoreML backend...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

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
    RUNTIMES            ANE
    FORMATS             COREML
)

message(STATUS "WhisperKit CoreML Backend Configuration:")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
message(STATUS "  Note: Actual inference runs in Swift via CoreML callbacks")
