# CMakeLists.txt for RunAnywhere Commons JNI Bridge
#
# This builds the JNI layer that wraps the runanywhere-commons C API
# for Android/JVM platforms.

cmake_minimum_required(VERSION 3.14)
project(runanywhere_commons_jni)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find JNI
find_package(JNI REQUIRED)
include_directories(${JNI_INCLUDE_DIRS})

# Include runanywhere-commons headers
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../../include)

# Source files
set(JNI_SOURCES
    runanywhere_commons_jni.cpp
)

# Create shared library
add_library(runanywhere_commons_jni SHARED ${JNI_SOURCES})

# Link against runanywhere-commons
target_link_libraries(runanywhere_commons_jni
    runanywhere_commons
    ${JNI_LIBRARIES}
)

# Android-specific settings
if(ANDROID)
    find_library(log-lib log)
    target_link_libraries(runanywhere_commons_jni ${log-lib})
endif()

# Set output name
set_target_properties(runanywhere_commons_jni PROPERTIES
    OUTPUT_NAME "runanywhere_jni"
    VERSION 1.0.0
    SOVERSION 1
)
