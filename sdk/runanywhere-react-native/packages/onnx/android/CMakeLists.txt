project(runanywhereonnx)
cmake_minimum_required(VERSION 3.9.0)

set(PACKAGE_NAME runanywhereonnx)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 17)

# Path to pre-built native libraries (downloaded from runanywhere-binaries)
set(JNILIB_DIR ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI})

# =============================================================================
# RABackendONNX - STT/TTS/VAD backend
# =============================================================================
if(EXISTS "${JNILIB_DIR}/librunanywhere_onnx.so")
    add_library(runanywhere_onnx SHARED IMPORTED)
    set_target_properties(runanywhere_onnx PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librunanywhere_onnx.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_ONNX ON)
    message(STATUS "[RunAnywhereONNX] Found RABackendONNX at ${JNILIB_DIR}/librunanywhere_onnx.so")
else()
    message(WARNING "[RunAnywhereONNX] RABackendONNX not found at ${JNILIB_DIR}/librunanywhere_onnx.so")
    message(WARNING "Run: ./gradlew :onnx:downloadNativeLibs")
endif()

# =============================================================================
# ONNX Runtime
# =============================================================================
if(EXISTS "${JNILIB_DIR}/libonnxruntime.so")
    add_library(onnxruntime SHARED IMPORTED)
    set_target_properties(onnxruntime PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/libonnxruntime.so"
        IMPORTED_NO_SONAME TRUE
    )
    message(STATUS "[RunAnywhereONNX] Found ONNX Runtime at ${JNILIB_DIR}/libonnxruntime.so")
endif()

# =============================================================================
# Source files - ONNX bridges
# =============================================================================
file(GLOB BRIDGE_SOURCES "../cpp/bridges/*.cpp")

add_library(${PACKAGE_NAME} SHARED
    src/main/cpp/cpp-adapter.cpp
    ../cpp/HybridRunAnywhereONNX.cpp
    ${BRIDGE_SOURCES}
)

# Add Nitrogen specs (this handles all React Native linking)
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/runanywhereonnx+autolinking.cmake)

# =============================================================================
# Include directories
# =============================================================================
include_directories(
    "src/main/cpp"
    "../cpp"
    "../cpp/bridges"
    "${CMAKE_SOURCE_DIR}/include"
)

# =============================================================================
# Linking
# =============================================================================
find_library(LOG_LIB log)

target_link_libraries(
    ${PACKAGE_NAME}
    ${LOG_LIB}
    android
)

# Link ONNX backend if available
if(HAS_ONNX)
    target_link_libraries(${PACKAGE_NAME} runanywhere_onnx onnxruntime)
    target_compile_definitions(${PACKAGE_NAME} PRIVATE HAS_ONNX=1)
endif()
