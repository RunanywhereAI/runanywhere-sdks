cmake_minimum_required(VERSION 3.22.1)
project("llama_jni")

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required libraries
find_library(log-lib log)

# Note: In a real implementation, you would add llama.cpp as a submodule
# For now, we'll create a simplified version

# Add the JNI library
add_library(llama-jni SHARED
    llama_jni.cpp
)

# Link libraries
target_link_libraries(llama-jni
    ${log-lib}
    android
)

# Include directories
target_include_directories(llama-jni PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# MLC-LLM JNI library
# Note: In a real implementation, you would integrate TVM runtime and MLC-LLM
add_library(mlc-llm-jni SHARED
    mlc_llm_jni.cpp
)

target_link_libraries(mlc-llm-jni
    ${log-lib}
    android
)

target_include_directories(mlc-llm-jni PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)