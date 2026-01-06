project(runanywherellama)
cmake_minimum_required(VERSION 3.9.0)

set(PACKAGE_NAME runanywherellama)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 20)

# Path to pre-built native libraries (downloaded from runanywhere-binaries)
set(JNILIB_DIR ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI})

# =============================================================================
# RABackendLlamaCPP - Llama LLM backend (REQUIRED)
# Downloaded via Gradle downloadNativeLibs task
# =============================================================================
if(NOT EXISTS "${JNILIB_DIR}/librunanywhere_llamacpp.so")
    message(FATAL_ERROR "[RunAnywhereLlama] RABackendLlamaCPP not found at ${JNILIB_DIR}/librunanywhere_llamacpp.so\n"
                        "Run: ./gradlew :runanywhere_llamacpp:downloadNativeLibs")
endif()

add_library(runanywhere_llamacpp SHARED IMPORTED)
set_target_properties(runanywhere_llamacpp PROPERTIES
    IMPORTED_LOCATION "${JNILIB_DIR}/librunanywhere_llamacpp.so"
    IMPORTED_NO_SONAME TRUE
)
message(STATUS "[RunAnywhereLlama] Found RABackendLlamaCPP at ${JNILIB_DIR}/librunanywhere_llamacpp.so")

# =============================================================================
# Source files - Llama bridges
# =============================================================================
file(GLOB BRIDGE_SOURCES "../cpp/bridges/*.cpp")

add_library(${PACKAGE_NAME} SHARED
    src/main/cpp/cpp-adapter.cpp
    ../cpp/HybridRunAnywhereLlama.cpp
    ${BRIDGE_SOURCES}
)

# Add Nitrogen specs (this handles all React Native linking)
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/runanywherellama+autolinking.cmake)

# =============================================================================
# Include directories
# =============================================================================
# Get core package include dir (for rac/*.h headers)
get_filename_component(RN_NODE_MODULES "${CMAKE_SOURCE_DIR}/../../.." ABSOLUTE)
set(CORE_INCLUDE_DIR "${RN_NODE_MODULES}/@runanywhere/core/android/src/main/include")
set(CORE_JNILIB_DIR "${RN_NODE_MODULES}/@runanywhere/core/android/src/main/jniLibs/${ANDROID_ABI}")

include_directories(
    "src/main/cpp"
    "../cpp"
    "../cpp/bridges"
    "${CMAKE_SOURCE_DIR}/include"
    "${CORE_INCLUDE_DIR}"
    "${CORE_INCLUDE_DIR}/rac"
    "${CORE_INCLUDE_DIR}/rac/core"
)

# =============================================================================
# RACommons - Core SDK functionality (from core package)
# =============================================================================
if(NOT EXISTS "${CORE_JNILIB_DIR}/librac_commons.so")
    message(FATAL_ERROR "[RunAnywhereLlama] RACommons not found at ${CORE_JNILIB_DIR}/librac_commons.so\n"
                        "Run: ./gradlew :runanywhere_core:downloadNativeLibs")
endif()

add_library(rac_commons SHARED IMPORTED)
set_target_properties(rac_commons PROPERTIES
    IMPORTED_LOCATION "${CORE_JNILIB_DIR}/librac_commons.so"
    IMPORTED_NO_SONAME TRUE
)
message(STATUS "[RunAnywhereLlama] Found RACommons at ${CORE_JNILIB_DIR}/librac_commons.so")

# =============================================================================
# Linking - LlamaCPP backend and RACommons are REQUIRED
# =============================================================================
find_library(LOG_LIB log)

target_link_libraries(
    ${PACKAGE_NAME}
    ${LOG_LIB}
    android
    rac_commons
    runanywhere_llamacpp
)

# HAS_LLAMACPP and HAS_RACOMMONS are always defined since backends are required
target_compile_definitions(${PACKAGE_NAME} PRIVATE HAS_LLAMACPP=1 HAS_RACOMMONS=1)
