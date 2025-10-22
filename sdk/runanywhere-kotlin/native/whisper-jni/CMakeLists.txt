cmake_minimum_required(VERSION 3.18)
project(whisper-jni)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find JNI
find_package(JNI REQUIRED)

# Add whisper.cpp
add_subdirectory(whisper.cpp)

# Add our JNI wrapper
add_library(whisper-jni SHARED
    src/whisper_jni.cpp
)

# Include directories
target_include_directories(whisper-jni PRIVATE
    ${JNI_INCLUDE_DIRS}
    whisper.cpp
    jni
)

# Link libraries
target_link_libraries(whisper-jni
    whisper
    ${JNI_LIBRARIES}
)

# Android specific settings
if(ANDROID)
    target_link_libraries(whisper-jni
        android
        log
    )
endif()

# Compiler flags
target_compile_options(whisper-jni PRIVATE
    -O3
    -fPIC
)

if(ANDROID)
    target_compile_definitions(whisper-jni PRIVATE
        ANDROID=1
    )
endif()

# Set output directory
set_target_properties(whisper-jni PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../src/jvmAndroidMain/resources/native
)
