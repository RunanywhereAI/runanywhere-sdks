project(runanywhere)
cmake_minimum_required(VERSION 3.9.0)

set(PACKAGE_NAME runanywhere)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 20)

# Define C++ library and add all sources
add_library(${PACKAGE_NAME} SHARED
    src/main/cpp/cpp-adapter.cpp
    ../cpp/HybridRunAnywhere.cpp
)

# Path to pre-built native libraries (downloaded from runanywhere-binaries)
set(JNILIB_DIR ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI})

# RunAnywhere Bridge - contains all the C API functions (ra_text_*, ra_stt_*, ra_tts_*, etc.)
if(EXISTS "${JNILIB_DIR}/librunanywhere_bridge.so")
    add_library(runanywhere_bridge SHARED IMPORTED)
    set_target_properties(runanywhere_bridge PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librunanywhere_bridge.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_BRIDGE ON)
    message(STATUS "Found runanywhere_bridge at ${JNILIB_DIR}/librunanywhere_bridge.so")
else()
    message(WARNING "runanywhere_bridge not found at ${JNILIB_DIR}/librunanywhere_bridge.so")
    message(WARNING "Run: ./gradlew downloadNativeLibs")
endif()

# RunAnywhere Loader - handles dynamic library loading
if(EXISTS "${JNILIB_DIR}/librunanywhere_loader.so")
    add_library(runanywhere_loader SHARED IMPORTED)
    set_target_properties(runanywhere_loader PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librunanywhere_loader.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_LOADER ON)
endif()

# LlamaCPP backend
if(EXISTS "${JNILIB_DIR}/librunanywhere_llamacpp.so")
    add_library(runanywhere_llamacpp SHARED IMPORTED)
    set_target_properties(runanywhere_llamacpp PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librunanywhere_llamacpp.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_LLAMACPP ON)
endif()

# ONNX backend (for STT/TTS)
if(EXISTS "${JNILIB_DIR}/librunanywhere_onnx.so")
    add_library(runanywhere_onnx SHARED IMPORTED)
    set_target_properties(runanywhere_onnx PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librunanywhere_onnx.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_ONNX ON)
endif()

# ONNX Runtime
if(EXISTS "${JNILIB_DIR}/libonnxruntime.so")
    add_library(onnxruntime SHARED IMPORTED)
    set_target_properties(onnxruntime PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/libonnxruntime.so"
        IMPORTED_NO_SONAME TRUE
    )
endif()

# OpenMP (required by LlamaCPP)
if(EXISTS "${JNILIB_DIR}/libomp.so")
    add_library(omp SHARED IMPORTED)
    set_target_properties(omp PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/libomp.so"
        IMPORTED_NO_SONAME TRUE
    )
endif()

# Add Nitrogen specs (this handles all React Native linking)
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/runanywhere+autolinking.cmake)

# Set up local includes
include_directories(
    "src/main/cpp"
    "../cpp"
    "../cpp/include"
)

find_library(LOG_LIB log)

# Link all libraries together
target_link_libraries(
    ${PACKAGE_NAME}
    ${LOG_LIB}
    android
)

# Link native libraries if available
if(HAS_BRIDGE)
    target_link_libraries(${PACKAGE_NAME} runanywhere_bridge)
endif()

if(HAS_LOADER)
    target_link_libraries(${PACKAGE_NAME} runanywhere_loader)
endif()

if(HAS_LLAMACPP)
    target_link_libraries(${PACKAGE_NAME} runanywhere_llamacpp)
    target_compile_definitions(${PACKAGE_NAME} PRIVATE HAS_LLAMACPP=1)
endif()

if(HAS_ONNX)
    target_link_libraries(${PACKAGE_NAME} runanywhere_onnx onnxruntime)
    target_compile_definitions(${PACKAGE_NAME} PRIVATE HAS_ONNX_RUNTIME=1)
endif()
