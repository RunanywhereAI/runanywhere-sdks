project(runanywherellama)
cmake_minimum_required(VERSION 3.9.0)

set(PACKAGE_NAME runanywherellama)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 17)

# Path to pre-built native libraries (downloaded from runanywhere-binaries)
set(JNILIB_DIR ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI})

# =============================================================================
# RABackendLlamaCPP - Llama LLM backend
# =============================================================================
if(EXISTS "${JNILIB_DIR}/librunanywhere_llamacpp.so")
    add_library(runanywhere_llamacpp SHARED IMPORTED)
    set_target_properties(runanywhere_llamacpp PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librunanywhere_llamacpp.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_LLAMACPP ON)
    message(STATUS "[RunAnywhereLlama] Found RABackendLlamaCPP at ${JNILIB_DIR}/librunanywhere_llamacpp.so")
else()
    message(WARNING "[RunAnywhereLlama] RABackendLlamaCPP not found at ${JNILIB_DIR}/librunanywhere_llamacpp.so")
    message(WARNING "Run: ./gradlew :llamacpp:downloadNativeLibs")
endif()

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

# Link LlamaCPP backend if available
if(HAS_LLAMACPP)
    target_link_libraries(${PACKAGE_NAME} runanywhere_llamacpp)
    target_compile_definitions(${PACKAGE_NAME} PRIVATE HAS_LLAMACPP=1)
endif()
