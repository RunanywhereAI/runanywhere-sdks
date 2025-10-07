cmake_minimum_required(VERSION 3.22.1)
project("runanywhere-jni")

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find JNI
find_package(JNI REQUIRED)
include_directories(${JNI_INCLUDE_DIRS})

# Add whisper.cpp as external project (would need to be downloaded/submoduled)
# add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/whisper.cpp)

# WebRTC VAD JNI wrapper
add_library(webrtc-vad-jni SHARED
        webrtc-vad-jni.cpp
)

target_link_libraries(webrtc-vad-jni
        ${JNI_LIBRARIES}
)

# Whisper JNI wrapper
add_library(whisper-jni SHARED
        whisper-jni.cpp
)

target_link_libraries(whisper-jni
        ${JNI_LIBRARIES}
        # whisper  # Link to whisper.cpp when available
)

# Set output directory for libraries
set_target_properties(webrtc-vad-jni whisper-jni
        PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../resources/native/${CMAKE_SYSTEM_NAME}"
)
