# =============================================================================
# WhisperKit CoreML Backend - STT via Apple Neural Engine
#
# Unlike other backends, WhisperKit CoreML has no C++ inference engine.
# The C++ side provides callback storage, vtable dispatch, and registration.
# Actual inference happens in Swift via registered callbacks to CoreML.
# =============================================================================

message(STATUS "Configuring WhisperKit CoreML backend...")

# =============================================================================
# WhisperKit CoreML Backend Library
# =============================================================================

set(WHISPERKIT_COREML_BACKEND_SOURCES
    rac_stt_whisperkit_coreml.cpp
    rac_backend_whisperkit_coreml_register.cpp
)

if(RAC_BUILD_SHARED)
    add_library(rac_backend_whisperkit_coreml SHARED ${WHISPERKIT_COREML_BACKEND_SOURCES})
else()
    add_library(rac_backend_whisperkit_coreml STATIC ${WHISPERKIT_COREML_BACKEND_SOURCES})
endif()

target_include_directories(rac_backend_whisperkit_coreml PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)

target_link_libraries(rac_backend_whisperkit_coreml PUBLIC
    rac_commons
)

target_compile_features(rac_backend_whisperkit_coreml PUBLIC cxx_std_20)

# =============================================================================
# Summary
# =============================================================================

message(STATUS "WhisperKit CoreML Backend Configuration:")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME} (Apple-only)")
message(STATUS "  Note: Actual inference runs in Swift via CoreML callbacks")
