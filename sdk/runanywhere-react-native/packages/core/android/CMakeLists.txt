project(runanywherecore)
cmake_minimum_required(VERSION 3.9.0)

set(PACKAGE_NAME runanywherecore)
set(CMAKE_VERBOSE_MAKEFILE ON)
set(CMAKE_CXX_STANDARD 17)

# Path to pre-built native libraries (downloaded from runanywhere-sdks)
set(JNILIB_DIR ${CMAKE_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI})

# Path to RAC headers (downloaded with native libraries)
set(RAC_INCLUDE_DIR ${CMAKE_SOURCE_DIR}/src/main/include)

# =============================================================================
# RACommons - Core SDK functionality (rac_* API)
# This is the ONLY native library in the core package
# =============================================================================
if(EXISTS "${JNILIB_DIR}/librac_commons.so")
    add_library(rac_commons SHARED IMPORTED)
    set_target_properties(rac_commons PROPERTIES
        IMPORTED_LOCATION "${JNILIB_DIR}/librac_commons.so"
        IMPORTED_NO_SONAME TRUE
    )
    set(HAS_RACOMMONS ON)
    message(STATUS "[RunAnywhereCore] Found RACommons at ${JNILIB_DIR}/librac_commons.so")
else()
    message(WARNING "[RunAnywhereCore] RACommons not found at ${JNILIB_DIR}/librac_commons.so")
    message(WARNING "Run: ./gradlew :core:downloadNativeLibs")
endif()

# =============================================================================
# Source files - Core bridges only (no LLM/STT/TTS/VAD)
# =============================================================================
# Collect core bridge source files
file(GLOB BRIDGE_SOURCES "../cpp/bridges/*.cpp")

add_library(${PACKAGE_NAME} SHARED
    src/main/cpp/cpp-adapter.cpp
    ../cpp/HybridRunAnywhereCore.cpp
    ${BRIDGE_SOURCES}
)

# Add Nitrogen specs (this handles all React Native linking)
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/runanywherecore+autolinking.cmake)

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

# NOTE: No LlamaCPP or ONNX linking here
# Those are in @runanywhere/llamacpp and @runanywhere/onnx packages respectively
