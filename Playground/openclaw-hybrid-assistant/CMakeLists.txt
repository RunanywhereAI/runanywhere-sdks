cmake_minimum_required(VERSION 3.16)
project(openclaw-hybrid-assistant VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# =============================================================================
# Find Dependencies
# =============================================================================

# Find ALSA
find_package(ALSA REQUIRED)

# Find pthreads
find_package(Threads REQUIRED)

# =============================================================================
# runanywhere-commons paths
# =============================================================================

# Get architecture
execute_process(
    COMMAND uname -m
    OUTPUT_VARIABLE ARCH
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Set paths relative to this CMakeLists.txt
set(ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(RAC_COMMONS_DIR "${ROOT_DIR}/sdk/runanywhere-commons")
set(RAC_DIST_DIR "${RAC_COMMONS_DIR}/dist/linux/${ARCH}")
set(SHERPA_DIR "${RAC_COMMONS_DIR}/third_party/sherpa-onnx-linux")

# Verify directories exist
if(NOT EXISTS "${RAC_DIST_DIR}")
    message(FATAL_ERROR "runanywhere-commons not built. Run: cd ${RAC_COMMONS_DIR} && ./scripts/build-linux.sh --shared")
endif()

if(NOT EXISTS "${SHERPA_DIR}")
    message(FATAL_ERROR "Sherpa-ONNX not downloaded. Run: cd ${RAC_COMMONS_DIR} && ./scripts/linux/download-sherpa-onnx.sh")
endif()

# =============================================================================
# Include directories
# =============================================================================

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${RAC_DIST_DIR}/include
    ${SHERPA_DIR}/include
    ${ALSA_INCLUDE_DIRS}
)

# =============================================================================
# Library directories
# =============================================================================

link_directories(
    ${RAC_DIST_DIR}
    ${SHERPA_DIR}/lib
)

# =============================================================================
# Main executable: openclaw-assistant
# =============================================================================

add_executable(openclaw-assistant
    main.cpp
    voice_pipeline.cpp
    tts_queue.cpp
    openclaw_client.cpp
    audio_capture.cpp
    audio_playback.cpp
    waiting_chime.cpp
)

# Check if llamacpp backend is available (for filler LLM)
find_library(RAC_BACKEND_LLAMACPP_LIB rac_backend_llamacpp
    PATHS ${RAC_DIST_DIR} NO_DEFAULT_PATH)

target_link_libraries(openclaw-assistant PRIVATE
    # RunAnywhere Commons
    rac_commons
    rac_backend_onnx

    # Sherpa-ONNX (for STT/TTS/VAD)
    sherpa-onnx-c-api

    # ONNX Runtime
    onnxruntime

    # System libraries
    ${ALSA_LIBRARIES}
    Threads::Threads
    dl
)

# Conditionally link llamacpp backend for filler LLM
if(RAC_BACKEND_LLAMACPP_LIB)
    target_link_libraries(openclaw-assistant PRIVATE rac_backend_llamacpp)
    target_compile_definitions(openclaw-assistant PRIVATE RAC_HAS_LLAMACPP)
    message(STATUS "  Filler LLM: enabled (llamacpp backend found)")
else()
    message(STATUS "  Filler LLM: disabled (llamacpp backend not built)")
endif()

# Set RPATH for finding shared libraries at runtime
set_target_properties(openclaw-assistant PROPERTIES
    BUILD_RPATH "${RAC_DIST_DIR};${SHERPA_DIR}/lib"
    INSTALL_RPATH "${RAC_DIST_DIR};${SHERPA_DIR}/lib"
)

# =============================================================================
# Test executable: test-components
# =============================================================================
# Tests wake word, VAD, and ASR with WAV files

add_executable(test-components
    tests/test_components.cpp
    voice_pipeline.cpp
    tts_queue.cpp
)

target_link_libraries(test-components PRIVATE
    # RunAnywhere Commons
    rac_commons
    rac_backend_onnx

    # Sherpa-ONNX
    sherpa-onnx-c-api

    # ONNX Runtime
    onnxruntime

    # System libraries
    Threads::Threads
    dl
)

# Set RPATH for test binary
set_target_properties(test-components PROPERTIES
    BUILD_RPATH "${RAC_DIST_DIR};${SHERPA_DIR}/lib"
    INSTALL_RPATH "${RAC_DIST_DIR};${SHERPA_DIR}/lib"
)

# =============================================================================
# Integration test executable: test-integration
# =============================================================================
# End-to-end tests with fake OpenClaw WebSocket server.
# Run on Linux device (Pi) - ONNX runtime needs >8GB RAM.
#
# Tests:
# - Waiting chime timing and audio quality
# - Text sanitization for TTS
# - TTS synthesis on various inputs
# - Full flow: transcription → fake server → delayed response → TTS

add_executable(test-integration
    tests/test_integration.cpp
    voice_pipeline.cpp
    tts_queue.cpp
    openclaw_client.cpp
    waiting_chime.cpp
)

target_link_libraries(test-integration PRIVATE
    # RunAnywhere Commons
    rac_commons
    rac_backend_onnx

    # Sherpa-ONNX
    sherpa-onnx-c-api

    # ONNX Runtime
    onnxruntime

    # System libraries
    Threads::Threads
    dl
)

# Set RPATH for integration test binary
set_target_properties(test-integration PROPERTIES
    BUILD_RPATH "${RAC_DIST_DIR};${SHERPA_DIR}/lib"
    INSTALL_RPATH "${RAC_DIST_DIR};${SHERPA_DIR}/lib"
)

# =============================================================================
# Installation
# =============================================================================

install(TARGETS openclaw-assistant
    RUNTIME DESTINATION bin
)

# =============================================================================
# Summary
# =============================================================================

message(STATUS "")
message(STATUS "OpenClaw Hybrid Assistant Configuration:")
message(STATUS "  Architecture: ${ARCH}")
message(STATUS "  RAC Commons: ${RAC_DIST_DIR}")
message(STATUS "  Sherpa-ONNX: ${SHERPA_DIR}")
message(STATUS "  ALSA: ${ALSA_LIBRARIES}")
message(STATUS "")
message(STATUS "Note: NO LLM support - this is an OpenClaw channel only")
message(STATUS "")
