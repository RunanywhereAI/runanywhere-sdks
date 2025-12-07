cmake_minimum_required(VERSION 3.22.1)
project(runanywhere)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_VERBOSE_MAKEFILE ON)

# Find React Native packages
find_package(ReactAndroid REQUIRED CONFIG)
find_package(fbjni REQUIRED CONFIG)

# Path to pre-built native libraries
set(JNILIB_DIR ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI})

# ============================================================================
# Pre-built RunAnywhere Libraries
# ============================================================================

# C++ shared library
add_library(cpp_shared SHARED IMPORTED)
set_target_properties(cpp_shared PROPERTIES
  IMPORTED_LOCATION ${JNILIB_DIR}/libc++_shared.so)

# RunAnywhere LlamaCpp backend
add_library(runanywhere_llamacpp SHARED IMPORTED)
set_target_properties(runanywhere_llamacpp PROPERTIES
  IMPORTED_LOCATION ${JNILIB_DIR}/librunanywhere_llamacpp.so)

# ONNX Runtime (optional - for STT/TTS)
if(EXISTS ${JNILIB_DIR}/libonnxruntime.so)
  add_library(onnxruntime SHARED IMPORTED)
  set_target_properties(onnxruntime PROPERTIES
    IMPORTED_LOCATION ${JNILIB_DIR}/libonnxruntime.so)
  
  add_library(runanywhere_onnx SHARED IMPORTED)
  set_target_properties(runanywhere_onnx PROPERTIES
    IMPORTED_LOCATION ${JNILIB_DIR}/librunanywhere_onnx.so)
  
  set(HAS_ONNX ON)
endif()

# ============================================================================
# Include Nitrogen-generated autolinking
# ============================================================================
include(${CMAKE_SOURCE_DIR}/nitrogen/generated/android/runanywhere+autolinking.cmake)

# ============================================================================
# RunAnywhere Native Module
# ============================================================================

add_library(
  runanywhere
  SHARED
  # JNI adapter
  src/main/cpp/cpp-adapter.cpp
  # HybridRunAnywhere C++ implementation
  ../cpp/HybridRunAnywhere.cpp
)

# Include directories
target_include_directories(
  runanywhere
  PRIVATE
  ../cpp
  ${CMAKE_SOURCE_DIR}/nitrogen/generated/android/c++
  ${CMAKE_SOURCE_DIR}/nitrogen/generated/shared/c++
)

# Compiler definitions
target_compile_definitions(
  runanywhere
  PRIVATE
  ANDROID
)

# Link against React Native JSI and fbjni
target_link_libraries(
  runanywhere
  ReactAndroid::jsi
  ReactAndroid::react_nativemodule_core
  fbjni::fbjni
  android
  log
)

# Link against RunAnywhere backend libraries
target_link_libraries(runanywhere runanywhere_llamacpp)

# Optionally link ONNX if available
if(HAS_ONNX)
  target_link_libraries(runanywhere runanywhere_onnx onnxruntime)
  target_compile_definitions(runanywhere PRIVATE HAS_ONNX_RUNTIME=1)
endif()
