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
message(STATUS "ANDROID_ABI: ${ANDROID_ABI}")

# Verify llama.cpp directory exists
if(NOT EXISTS "${LLAMA_CPP_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "llama.cpp not found at ${LLAMA_CPP_DIR}. Please ensure it's cloned to EXTERNAL/llama.cpp")
endif()

# Add llama.cpp as subdirectory
add_subdirectory(${LLAMA_CPP_DIR} build-llama)

# Common compile options following SmolChat's optimization pattern
add_compile_options("-ffile-prefix-map=${LLAMA_CPP_DIR}=.")
add_link_options("LINKER:--build-id=none")

# Function to build library variants with different optimizations
function(build_library_variant target_name cpu_flags)
    message(STATUS "Building ${target_name} with flags: ${cpu_flags}")

    add_library(${target_name} SHARED
        src/llama-android.cpp
        src/cpu_features.cpp
    )

    # Link llama.cpp libraries
    target_link_libraries(${target_name}
        llama      # Core llama.cpp library
        common     # Common utilities (tokenization, etc.)
        android    # Android system library
        log        # Android logging
    )

    # Include directories
    target_include_directories(${target_name} PRIVATE
        ${LLAMA_CPP_DIR}/include
        ${LLAMA_CPP_DIR}/common
        ${LLAMA_CPP_DIR}/src
        ${LLAMA_CPP_DIR}
    )

    # Optimization flags
    target_compile_options(${target_name} PUBLIC
        -O3 -DNDEBUG
        -ffast-math -funroll-loops
        -fvisibility=hidden -fvisibility-inlines-hidden
        -ffunction-sections -fdata-sections
        ${cpu_flags}
    )

    # Link-time optimization
    target_link_options(${target_name} PRIVATE
        -Wl,--gc-sections
        -Wl,--strip-all
        -flto
        -Wl,--exclude-libs,ALL
    )
endfunction()

# Build different variants for ARM64-v8a (following SmolChat's pattern)
if (${ANDROID_ABI} STREQUAL "arm64-v8a")
    # Baseline ARM64 (armv8-a)
    build_library_variant("llama-android" "-march=armv8-a")

    # ARMv8.2-a with FP16 support
    build_library_variant("llama-android-fp16" "-march=armv8.2-a+fp16")

    # ARMv8.2-a with FP16 + DotProd
    build_library_variant("llama-android-dotprod" "-march=armv8.2-a+fp16+dotprod")

    # ARMv8.4-a variants
    build_library_variant("llama-android-v8_4" "-march=armv8.4-a+fp16+dotprod")
    build_library_variant("llama-android-i8mm" "-march=armv8.4-a+fp16+dotprod+i8mm")
    build_library_variant("llama-android-sve" "-march=armv8.4-a+fp16+dotprod+sve")
    build_library_variant("llama-android-i8mm-sve" "-march=armv8.4-a+fp16+dotprod+i8mm+sve")

    message(STATUS "Building 7 ARM64 variants: baseline, fp16, dotprod, v8_4, i8mm, sve, i8mm-sve")
else()
    # For other architectures, build baseline only
    build_library_variant("llama-android" "")
    message(STATUS "Building baseline variant for ${ANDROID_ABI}")
endif()
