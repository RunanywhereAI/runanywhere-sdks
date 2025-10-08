cmake_minimum_required(VERSION 3.18)

project(llama-jni)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find JNI
find_package(JNI REQUIRED)
include_directories(${JNI_INCLUDE_DIRS})

# Find Java
find_package(Java REQUIRED)

# Set up llama.cpp
set(LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp")

# Add llama.cpp subdirectory
add_subdirectory(${LLAMA_CPP_DIR} EXCLUDE_FROM_ALL)

# Get llama.cpp include directories
target_include_directories(llama PUBLIC
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/common
    ${LLAMA_CPP_DIR}/src
)

# JNI source files
set(JNI_SOURCES
    src/llama_jni.cpp
    src/llama_jni_utils.cpp
)

# Create the JNI library
add_library(llama-jni SHARED ${JNI_SOURCES})

# Link with llama and JNI
target_link_libraries(llama-jni
    llama
    ${JNI_LIBRARIES}
)

# Include directories
target_include_directories(llama-jni PRIVATE
    ${JNI_INCLUDE_DIRS}
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/common
    ${LLAMA_CPP_DIR}/src
    src
)

# Platform-specific configurations
if(ANDROID)
    target_link_libraries(llama-jni log)
    set_target_properties(llama-jni PROPERTIES
        ANDROID_STL c++_shared
    )
elseif(APPLE)
    set_target_properties(llama-jni PROPERTIES
        MACOSX_RPATH ON
        INSTALL_RPATH "@loader_path"
    )
elseif(UNIX)
    set_target_properties(llama-jni PROPERTIES
        INSTALL_RPATH "$ORIGIN"
    )
endif()

# Compiler-specific optimizations
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(llama-jni PRIVATE
        -O3
        -ffast-math
        -funroll-loops
        -fno-finite-math-only
    )
endif()

# Output configuration
set_target_properties(llama-jni PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)

# Install configuration (optional)
install(TARGETS llama-jni
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)