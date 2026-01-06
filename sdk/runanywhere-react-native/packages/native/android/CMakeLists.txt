project(runanywhere)
cmake_minimum_required(VERSION 3.9.0)

set(PACKAGE_NAME runanywhere)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 17)

# Path to pre-built native libraries (downloaded from runanywhere-sdks/runanywhere-binaries)
set(JNILIB_DIR ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI})

# Path to RAC headers (downloaded with native libraries)
set(RAC_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/src/main/include)

# =============================================================================
# RACommons - Core SDK functionality (rac_* API)
# =============================================================================
if(EXISTS "${JNILIB_DIR}/librac_commons.so")
    add_library(rac_commons SHARED IMPORTED)
    set_target_properties(rac_commons PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librac_commons.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_RACOMMONS ON)
    message(STATUS "Found RACommons at ${JNILIB_DIR}/librac_commons.so")
else()
    message(WARNING "RACommons not found at ${JNILIB_DIR}/librac_commons.so")
    message(WARNING "Run: ./gradlew downloadNativeLibs")
endif()

# =============================================================================
# RABackendLlamaCPP - LLM backend
# Note: librunanywhere_llamacpp.so contains the LLM logic
#       librac_backend_llamacpp_jni.so contains the JNI bridge for Kotlin SDK
# =============================================================================
if(EXISTS "${JNILIB_DIR}/librunanywhere_llamacpp.so")
    add_library(runanywhere_llamacpp SHARED IMPORTED)
    set_target_properties(runanywhere_llamacpp PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librunanywhere_llamacpp.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_LLAMACPP ON)
    message(STATUS "Found RABackendLlamaCPP at ${JNILIB_DIR}/librunanywhere_llamacpp.so")
endif()

# =============================================================================
# RABackendONNX - STT/TTS/VAD backend
# Note: librunanywhere_onnx.so contains the STT/TTS/VAD logic
#       librac_backend_onnx_jni.so contains the JNI bridge for Kotlin SDK
# =============================================================================
if(EXISTS "${JNILIB_DIR}/librunanywhere_onnx.so")
    add_library(runanywhere_onnx SHARED IMPORTED)
    set_target_properties(runanywhere_onnx PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librunanywhere_onnx.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_ONNX ON)
    message(STATUS "Found RABackendONNX at ${JNILIB_DIR}/librunanywhere_onnx.so")
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
    message(STATUS "Found ONNX Runtime at ${JNILIB_DIR}/libonnxruntime.so")
endif()

# =============================================================================
# OpenMP (required by some backends)
# =============================================================================
if(EXISTS "${JNILIB_DIR}/libomp.so")
    add_library(omp SHARED IMPORTED)
    set_target_properties(omp PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/libomp.so"
        IMPORTED_NO_SONAME TRUE
    )
endif()

# =============================================================================
# Source files
# =============================================================================
# Collect all bridge source files
file(GLOB BRIDGE_SOURCES "../cpp/bridges/*.cpp")

add_library(${PACKAGE_NAME} SHARED
    src/main/cpp/cpp-adapter.cpp
    ../cpp/HybridRunAnywhere.cpp
    ${BRIDGE_SOURCES}
)

# Add Nitrogen specs (this handles all React Native linking)
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/runanywhere+autolinking.cmake)

# =============================================================================
# Include directories
# =============================================================================
include_directories(
    "src/main/cpp"
    "../cpp"
    "../cpp/bridges"
    "${CMAKE_SOURCE_DIR}/include"
    # RAC API headers from runanywhere-commons
    "${RAC_INCLUDE_DIR}"
    "${RAC_INCLUDE_DIR}/rac"
    "${RAC_INCLUDE_DIR}/rac/core"
    "${RAC_INCLUDE_DIR}/rac/features"
    "${RAC_INCLUDE_DIR}/rac/infrastructure"
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

# Link RACommons if available
if(HAS_RACOMMONS)
    target_link_libraries(${PACKAGE_NAME} rac_commons)
    target_compile_definitions(${PACKAGE_NAME} PRIVATE HAS_RACOMMONS=1)
endif()

# Link LlamaCPP backend if available
if(HAS_LLAMACPP)
    target_link_libraries(${PACKAGE_NAME} runanywhere_llamacpp)
    target_compile_definitions(${PACKAGE_NAME} PRIVATE HAS_LLAMACPP=1)
endif()

# Link ONNX backend if available
if(HAS_ONNX)
    target_link_libraries(${PACKAGE_NAME} runanywhere_onnx onnxruntime)
    target_compile_definitions(${PACKAGE_NAME} PRIVATE HAS_ONNX=1)
endif()
