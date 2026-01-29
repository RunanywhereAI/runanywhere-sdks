# =============================================================================
# Linux Voice Assistant
# =============================================================================
# A complete voice AI pipeline for Raspberry Pi 5 (and other Linux devices)
# using runanywhere-commons as the ML backend.
#
# Pipeline: VAD -> STT -> LLM -> TTS
#
# Build instructions:
#   1. Build runanywhere-commons for Linux first:
#      cd sdk/runanywhere-commons
#      ./scripts/linux/download-sherpa-onnx.sh
#      ./scripts/build-linux.sh --shared
#
#   2. Build this application:
#      cd playground/linux-voice-assistant
#      cmake -B build
#      cmake --build build
#
#   3. Download models:
#      ./scripts/download-models.sh
#
#   4. Run:
#      ./build/voice-assistant
# =============================================================================

cmake_minimum_required(VERSION 3.16)
project(linux-voice-assistant
    VERSION 1.0.0
    LANGUAGES CXX
    DESCRIPTION "Linux Voice Assistant using RunAnywhere Commons"
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# =============================================================================
# Configuration
# =============================================================================

# Path to runanywhere-commons
set(RAC_COMMONS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons")
set(RAC_COMMONS_DIST "${RAC_COMMONS_DIR}/dist/linux/${CMAKE_SYSTEM_PROCESSOR}")

# Check if runanywhere-commons is built
if(NOT EXISTS "${RAC_COMMONS_DIST}/librac_commons.so")
    message(WARNING "runanywhere-commons not built. Build it first:")
    message(WARNING "  cd ${RAC_COMMONS_DIR}")
    message(WARNING "  ./scripts/linux/download-sherpa-onnx.sh")
    message(WARNING "  ./scripts/build-linux.sh --shared")
endif()

# =============================================================================
# Find Dependencies
# =============================================================================

# ALSA for audio I/O
find_package(ALSA REQUIRED)
if(ALSA_FOUND)
    message(STATUS "Found ALSA: ${ALSA_INCLUDE_DIRS}")
else()
    message(FATAL_ERROR "ALSA not found. Install with: apt install libasound2-dev")
endif()

# PulseAudio (optional, for better audio routing)
find_package(PkgConfig)
if(PKG_CONFIG_FOUND)
    pkg_check_modules(PULSE libpulse libpulse-simple)
    if(PULSE_FOUND)
        message(STATUS "Found PulseAudio: ${PULSE_INCLUDE_DIRS}")
    endif()
endif()

# Threads
find_package(Threads REQUIRED)

# =============================================================================
# Source Files
# =============================================================================

set(SOURCES
    main.cpp
    voice_pipeline.cpp
    audio_capture.cpp
    audio_playback.cpp
)

set(HEADERS
    model_config.h
    voice_pipeline.h
    audio_capture.h
    audio_playback.h
)

# =============================================================================
# Executable
# =============================================================================

add_executable(voice-assistant ${SOURCES} ${HEADERS})

# Test pipeline binary (feeds WAV file through the full pipeline)
add_executable(test-pipeline test_pipeline.cpp)

# =============================================================================
# Include Directories
# =============================================================================

target_include_directories(voice-assistant PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${RAC_COMMONS_DIR}/include
    ${RAC_COMMONS_DIST}/include
    ${ALSA_INCLUDE_DIRS}
)

if(PULSE_FOUND)
    target_include_directories(voice-assistant PRIVATE ${PULSE_INCLUDE_DIRS})
    target_compile_definitions(voice-assistant PRIVATE USE_PULSEAUDIO=1)
endif()

# =============================================================================
# Link Libraries
# =============================================================================

# Link runanywhere-commons libraries
target_link_directories(voice-assistant PRIVATE
    ${RAC_COMMONS_DIST}
    ${RAC_COMMONS_DIR}/third_party/sherpa-onnx-linux/lib
)

target_link_libraries(voice-assistant PRIVATE
    # RunAnywhere Commons
    rac_commons
    rac_backend_onnx
    rac_backend_llamacpp

    # Sherpa-ONNX (for STT/TTS/VAD)
    sherpa-onnx-c-api

    # ONNX Runtime
    onnxruntime

    # System libraries
    ${ALSA_LIBRARIES}
    Threads::Threads
    dl
)

if(PULSE_FOUND)
    target_link_libraries(voice-assistant PRIVATE ${PULSE_LIBRARIES})
endif()

# =============================================================================
# RPATH Configuration
# =============================================================================

# Set RPATH so the executable can find libraries at runtime
set_target_properties(voice-assistant PROPERTIES
    BUILD_RPATH "${RAC_COMMONS_DIST};${RAC_COMMONS_DIR}/third_party/sherpa-onnx-linux/lib"
    INSTALL_RPATH "$ORIGIN/../lib;$ORIGIN/../../sdk/runanywhere-commons/dist/linux/${CMAKE_SYSTEM_PROCESSOR}"
)

# =============================================================================
# Compiler Options
# =============================================================================

target_compile_options(voice-assistant PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -O2
)

# =============================================================================
# Test Pipeline Configuration
# =============================================================================

target_include_directories(test-pipeline PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${RAC_COMMONS_DIR}/include
    ${RAC_COMMONS_DIST}/include
)

target_link_directories(test-pipeline PRIVATE
    ${RAC_COMMONS_DIST}
    ${RAC_COMMONS_DIR}/third_party/sherpa-onnx-linux/lib
)

target_link_libraries(test-pipeline PRIVATE
    rac_commons
    rac_backend_onnx
    rac_backend_llamacpp
    sherpa-onnx-c-api
    onnxruntime
    Threads::Threads
    dl
)

set_target_properties(test-pipeline PROPERTIES
    BUILD_RPATH "${RAC_COMMONS_DIST};${RAC_COMMONS_DIR}/third_party/sherpa-onnx-linux/lib"
)

target_compile_options(test-pipeline PRIVATE -Wall -O2)

# =============================================================================
# Installation
# =============================================================================

install(TARGETS voice-assistant
    RUNTIME DESTINATION bin
)

# Install run script
install(FILES scripts/download-models.sh
    DESTINATION bin
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                GROUP_READ GROUP_EXECUTE
                WORLD_READ WORLD_EXECUTE
)

# =============================================================================
# Summary
# =============================================================================

message(STATUS "")
message(STATUS "========================================")
message(STATUS "Linux Voice Assistant Configuration")
message(STATUS "========================================")
message(STATUS "")
message(STATUS "RunAnywhere Commons: ${RAC_COMMONS_DIR}")
message(STATUS "RAC Distribution: ${RAC_COMMONS_DIST}")
message(STATUS "")
message(STATUS "Dependencies:")
message(STATUS "  ALSA: ${ALSA_LIBRARIES}")
if(PULSE_FOUND)
    message(STATUS "  PulseAudio: ${PULSE_LIBRARIES}")
else()
    message(STATUS "  PulseAudio: Not found (optional)")
endif()
message(STATUS "")
message(STATUS "Build with:")
message(STATUS "  cmake -B build && cmake --build build")
message(STATUS "")
message(STATUS "Before running, download models:")
message(STATUS "  ./scripts/download-models.sh")
message(STATUS "")
message(STATUS "========================================")
