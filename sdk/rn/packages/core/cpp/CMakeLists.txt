cmake_minimum_required(VERSION 3.22)
project(RunAnywhereCoreRN)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Invoked by Android Gradle + iOS Pod cmake. References the v2 core
# headers from the monorepo.

set(RA_MONOREPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../..")
include_directories(
    "${RA_MONOREPO_ROOT}/core/abi"
    # Nitro provides its own include paths via the gradle/pod deps.
)

add_library(runanywhere_core_rn SHARED
    RunAnywhereTurboModule.cpp
)

# Android links the shared libracommons_core.so dropped under jniLibs;
# iOS consumes it via the RACommonsCore.xcframework vendored framework.
if(ANDROID)
    target_link_libraries(runanywhere_core_rn
        PRIVATE log android racommons_core)
endif()
