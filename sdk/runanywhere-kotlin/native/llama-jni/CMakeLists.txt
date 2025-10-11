cmake_minimum_required(VERSION 3.22.1)

project("llama-android")

# Calculate path to llama.cpp from EXTERNAL directory
# We're at: sdk/runanywhere-kotlin/native/llama-jni/CMakeLists.txt
# We need:  EXTERNAL/llama.cpp (4 levels up)
get_filename_component(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../.." ABSOLUTE)
set(LLAMA_CPP_DIR "${PROJECT_ROOT}/EXTERNAL/llama.cpp")

# Debug: Print paths to verify
message(STATUS "CMAKE_CURRENT_SOURCE_DIR: ${CMAKE_CURRENT_SOURCE_DIR}")
message(STATUS "PROJECT_ROOT: ${PROJECT_ROOT}")
message(STATUS "LLAMA_CPP_DIR: ${LLAMA_CPP_DIR}")

# Verify llama.cpp directory exists
if(NOT EXISTS "${LLAMA_CPP_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "llama.cpp not found at ${LLAMA_CPP_DIR}. Please ensure it's cloned to EXTERNAL/llama.cpp")
endif()

# Add llama.cpp as subdirectory
add_subdirectory(${LLAMA_CPP_DIR} build-llama)

# Create the JNI wrapper library
add_library(${CMAKE_PROJECT_NAME} SHARED
    src/llama-android.cpp
)

# Link llama.cpp libraries
target_link_libraries(${CMAKE_PROJECT_NAME}
    llama      # Core llama.cpp library
    common     # Common utilities (tokenization, etc.)
    android    # Android system library
    log        # Android logging
)

# Include directories
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/common
    ${LLAMA_CPP_DIR}/src
    ${LLAMA_CPP_DIR}
)
