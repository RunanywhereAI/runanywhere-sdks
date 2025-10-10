# Based on official llama.cpp Android example
# See: llama.cpp/examples/llama.android/llama/src/main/cpp/CMakeLists.txt

cmake_minimum_required(VERSION 3.22.1)

project("llama-jni")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Set up llama.cpp path
set(LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp")

# Add llama.cpp subdirectory (provides llama and common targets)
add_subdirectory(${LLAMA_CPP_DIR} build-llama)

# JNI source files
set(JNI_SOURCES
    src/llama_jni.cpp
    src/llama_jni_utils.cpp
)

# Create the JNI shared library
add_library(llama-jni SHARED ${JNI_SOURCES})

# Link with llama.cpp libraries (following official Android example)
target_link_libraries(llama-jni
    llama
    common
    android
    log)

# Include directories
target_include_directories(llama-jni PRIVATE
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/common
    ${LLAMA_CPP_DIR}/src
    ${LLAMA_CPP_DIR}
    src
)
