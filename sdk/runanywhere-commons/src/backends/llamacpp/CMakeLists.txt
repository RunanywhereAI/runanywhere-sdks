# =============================================================================
# LlamaCPP Backend - Text Generation via llama.cpp
# =============================================================================

message(STATUS "Configuring LlamaCPP backend...")

# =============================================================================
# Fetch llama.cpp
# =============================================================================

include(FetchContent)
include(LoadVersions)

if(NOT DEFINED LLAMACPP_VERSION)
    set(LLAMACPP_VERSION "b7199")
endif()
set(LLAMA_CPP_VERSION "${LLAMACPP_VERSION}")

FetchContent_Declare(
    llamacpp
    GIT_REPOSITORY https://github.com/ggerganov/llama.cpp.git
    GIT_TAG        ${LLAMA_CPP_VERSION}
    GIT_SHALLOW    TRUE
    GIT_PROGRESS   TRUE
    UPDATE_COMMAND ${CMAKE_COMMAND} -DVULKAN_CMAKE=<SOURCE_DIR>/ggml/src/ggml-vulkan/CMakeLists.txt
                   -P ${CMAKE_CURRENT_SOURCE_DIR}/patch_vulkan.cmake
)

# Configure llama.cpp build options
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(LLAMA_HTTPLIB OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)

# Platform-specific optimizations
if(RAC_PLATFORM_IOS)
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    set(GGML_NEON ON CACHE BOOL "" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)  # Embed precompiled Metal shaders
elseif(RAC_PLATFORM_ANDROID)
    # =============================================================================
    # VULKAN GPU ACCELERATION FOR ANDROID
    # =============================================================================
    # Enable Vulkan for GPU-accelerated inference on Android devices
    # Provides 2-5x speedup on modern devices with Vulkan 1.1+ support
    set(GGML_VULKAN ON CACHE BOOL "" FORCE)
    
    # CRITICAL: Set host compilers for shader generation tool
    # The shader generator must be built for the host system, not Android
    set(HOST_C_COMPILER "/usr/bin/gcc" CACHE FILEPATH "Host C compiler" FORCE)
    set(HOST_CXX_COMPILER "/usr/bin/g++" CACHE FILEPATH "Host C++ compiler" FORCE)
    
    # Skip toolchain file - llama.cpp will use HOST_C/CXX_COMPILER variables
    set(GGML_VULKAN_SHADERS_GEN_TOOLCHAIN "" CACHE FILEPATH "Use host compiler" FORCE)
    
    # Use host glslc for shader compilation
    set(Vulkan_GLSLC_EXECUTABLE "glslc" CACHE STRING "" FORCE)
    
    # Fetch Vulkan-Hpp (C++ bindings) - NDK only provides C headers
    include(FetchVulkanHpp)
    
    # Vulkan SDK path from Android NDK (correct path for NDK 29+)
    if(ANDROID_NDK)
        # NDK 29+ has Vulkan headers in sysroot
        if(WIN32)
            set(Vulkan_INCLUDE_DIR "${ANDROID_NDK}/toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/include" CACHE PATH "" FORCE)
        else()
            set(Vulkan_INCLUDE_DIR "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include" CACHE PATH "" FORCE)
        endif()
        message(STATUS "Vulkan headers: ${Vulkan_INCLUDE_DIR}/vulkan")
    endif()
    
    # Disable other GPU backends (not available on Android)
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_CUDA OFF CACHE BOOL "" FORCE)
    set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
    set(GGML_HIPBLAS OFF CACHE BOOL "" FORCE)
    set(GGML_SYCL OFF CACHE BOOL "" FORCE)
    set(GGML_KOMPUTE OFF CACHE BOOL "" FORCE)
    set(GGML_RPC OFF CACHE BOOL "" FORCE)

    # CRITICAL: Disable native CPU detection (fails during cross-compilation)
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)

    # Enable ARM NEON for CPU fallback (when GPU unavailable)
    if(ANDROID_ABI MATCHES "arm64-v8a|armeabi-v7a")
        set(GGML_NEON ON CACHE BOOL "" FORCE)
        message(STATUS "Enabling NEON for ARM ABI: ${ANDROID_ABI}")
    else()
        set(GGML_NEON OFF CACHE BOOL "" FORCE)
        # x86/x86_64 will use SSE/AVX automatically
        message(STATUS "Disabling NEON for non-ARM ABI: ${ANDROID_ABI}")
    endif()

    # Android-specific settings
    set(ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES ON CACHE BOOL "" FORCE)
    set(GGML_CPU_HBM OFF CACHE BOOL "" FORCE)

    # Disable openmp to avoid Android threading issues
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
elseif(RAC_PLATFORM_MACOS)
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)  # Embed precompiled Metal shaders
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Force static libraries for llama.cpp" FORCE)

message(STATUS "========== VULKAN PATCH DEBUG START ==========")
message(STATUS "RAC_PLATFORM_ANDROID: ${RAC_PLATFORM_ANDROID}")
message(STATUS "GGML_VULKAN: ${GGML_VULKAN}")

# Manually populate llama.cpp to patch before configuration
FetchContent_GetProperties(llamacpp)
message(STATUS "llamacpp_POPULATED: ${llamacpp_POPULATED}")

if(NOT llamacpp_POPULATED)
    message(STATUS "Populating llama.cpp...")
    FetchContent_Populate(llamacpp)
    message(STATUS "llamacpp_SOURCE_DIR: ${llamacpp_SOURCE_DIR}")
    
    # Minimal patch for Vulkan cross-compilation
    if(RAC_PLATFORM_ANDROID AND GGML_VULKAN)
        set(VULKAN_CMAKE "${llamacpp_SOURCE_DIR}/ggml/src/ggml-vulkan/CMakeLists.txt")
        set(PATCH_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/patch_vulkan_minimal.py")
        set(SHADER_BUILD_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/build_vulkan_shaders.py")
        set(SHADER_DIR "${llamacpp_SOURCE_DIR}/ggml/src/ggml-vulkan/vulkan-shaders")
        set(SHADER_HEADER "${llamacpp_SOURCE_DIR}/ggml/src/ggml-vulkan/ggml-vulkan-shaders.hpp")
        
        message(STATUS "Building Vulkan shaders on host for cross-compilation...")
        
        # Build shader generator tool for host system
        set(SHADER_GEN_SOURCE "${SHADER_DIR}/vulkan-shaders-gen.cpp")
        set(SHADER_GEN_TOOL "${llamacpp_SOURCE_DIR}/ggml/src/ggml-vulkan/vulkan-shaders-gen-host")
        set(VULKAN_DIR "${llamacpp_SOURCE_DIR}/ggml/src/ggml-vulkan")
        set(SHADER_HPP "${llamacpp_SOURCE_DIR}/ggml/src/ggml-vulkan/ggml-vulkan-shaders.hpp")
        set(SHADER_CPP "${llamacpp_SOURCE_DIR}/ggml/src/ggml-vulkan/ggml-vulkan-shaders.cpp")
        
        # Check if shaders already compiled AND have correct size (>100MB)
        set(SHADERS_VALID FALSE)
        if(EXISTS "${SHADER_HPP}" AND EXISTS "${SHADER_CPP}")
            file(SIZE "${SHADER_CPP}" EXISTING_SHADER_SIZE)
            if(EXISTING_SHADER_SIZE GREATER 100000000)  # > 100MB
                message(STATUS ">>> ✓ Vulkan shaders already compiled (${EXISTING_SHADER_SIZE} bytes)")
                set(SHADERS_VALID TRUE)
            else()
                message(STATUS ">>> Shader files exist but are too small (${EXISTING_SHADER_SIZE} bytes), recompiling...")
            endif()
        endif()
        
        if(NOT SHADERS_VALID)
            message(STATUS ">>> Compiling Vulkan shaders...")
            
            # Compile shader generator tool
            if(NOT EXISTS "${SHADER_GEN_TOOL}")
                message(STATUS "Building shader generator tool...")
                execute_process(
                    COMMAND g++ -std=c++17 -O2 
                            -I"${llamacpp_SOURCE_DIR}/ggml/src"
                            "${SHADER_GEN_SOURCE}"
                            -o "${SHADER_GEN_TOOL}"
                    RESULT_VARIABLE TOOL_BUILD_RESULT
                    ERROR_VARIABLE TOOL_BUILD_ERROR
                )
                
                if(NOT TOOL_BUILD_RESULT EQUAL 0)
                    message(FATAL_ERROR "Failed to build shader generator tool: ${TOOL_BUILD_ERROR}")
                endif()
                message(STATUS "✓ Tool compiled")
            endif()
            
            # Find NDK glslc
            if(DEFINED ENV{ANDROID_NDK_HOME})
                set(NDK_GLSLC "$ENV{ANDROID_NDK_HOME}/shader-tools/linux-x86_64/glslc")
            elseif(ANDROID_NDK)
                set(NDK_GLSLC "${ANDROID_NDK}/shader-tools/linux-x86_64/glslc")
            else()
                message(FATAL_ERROR "ANDROID_NDK_HOME not set - cannot find glslc")
            endif()
            
            if(NOT EXISTS "${NDK_GLSLC}")
                message(FATAL_ERROR "glslc not found at: ${NDK_GLSLC}")
            endif()
            
            message(STATUS "Using glslc: ${NDK_GLSLC}")
            
            # Run tool to compile ALL shaders (parallel using bash script)
            message(STATUS "Compiling shaders in parallel (this may take 30-60 seconds)...")
            
            set(COMPILE_SCRIPT "${CMAKE_SOURCE_DIR}/scripts/compile-shaders-fast.sh")
            execute_process(
                COMMAND bash "${COMPILE_SCRIPT}" "${SHADER_GEN_TOOL}" "${NDK_GLSLC}" "${SHADER_DIR}" "${VULKAN_DIR}" "${SHADER_HPP}"
                RESULT_VARIABLE COMPILE_RESULT
                OUTPUT_VARIABLE SPV_COUNT
                ERROR_VARIABLE COMPILE_ERROR
                OUTPUT_STRIP_TRAILING_WHITESPACE
            )
            
            if(NOT COMPILE_RESULT EQUAL 0)
                message(FATAL_ERROR "Shader compilation failed: ${COMPILE_ERROR}")
            endif()
            
            message(STATUS ">>> Generated ${SPV_COUNT} .spv files")
            
            # Generate .cpp from .spv files using Python
            set(PYTHON_SCRIPT "${CMAKE_SOURCE_DIR}/scripts/generate-shader-cpp.py")
            if(EXISTS "${PYTHON_SCRIPT}" AND SPV_COUNT GREATER 0)
                message(STATUS ">>> Generating shader data file...")
                execute_process(
                    COMMAND python3 "${PYTHON_SCRIPT}" "${VULKAN_DIR}" "${SHADER_CPP}"
                    RESULT_VARIABLE PYTHON_RESULT
                    OUTPUT_VARIABLE PYTHON_OUTPUT
                    ERROR_VARIABLE PYTHON_ERROR
                )
                if(PYTHON_RESULT EQUAL 0)
                    message(STATUS ">>> ${PYTHON_OUTPUT}")
                else()
                    message(FATAL_ERROR "Failed to generate shader data: ${PYTHON_ERROR}")
                endif()
            else()
                message(FATAL_ERROR "Cannot generate shader data - no .spv files or script missing")
            endif()
        endif()
        
        # Verify files were created (outside the SHADERS_VALID check)
        if(EXISTS "${SHADER_HPP}" AND EXISTS "${SHADER_CPP}")
            file(SIZE "${SHADER_CPP}" SHADER_CPP_SIZE)
            message(STATUS ">>> ✓ Vulkan shaders compiled successfully")
            message(STATUS ">>> ✓ Generated: ggml-vulkan-shaders.hpp")
            message(STATUS ">>> ✓ Generated: ggml-vulkan-shaders.cpp (${SHADER_CPP_SIZE} bytes)")
        else()
            message(FATAL_ERROR "Shader files not generated!")
        endif()
        
        # CRITICAL: Disable CoopMat shader variants (not supported by NDK 27)
        set(VULKAN_CPP "${llamacpp_SOURCE_DIR}/ggml/src/ggml-vulkan/ggml-vulkan.cpp")
        if(EXISTS "${VULKAN_CPP}")
            message(STATUS ">>> Disabling CoopMat shader variants in ggml-vulkan.cpp...")
            file(READ "${VULKAN_CPP}" VULKAN_CPP_CONTENT)
            
            # Comment out CoopMat CREATE_FA calls (with flexible whitespace matching)
            string(REGEX REPLACE 
                "([[:space:]]*)CREATE_FA\\(GGML_TYPE_F32,[[:space:]]*f32,[[:space:]]*FA_COOPMAT1,[[:space:]]*_cm1\\)"
                "\\1// DISABLED: CREATE_FA(GGML_TYPE_F32, f32, FA_COOPMAT1, _cm1)"
                VULKAN_CPP_CONTENT "${VULKAN_CPP_CONTENT}")
            string(REGEX REPLACE 
                "([[:space:]]*)CREATE_FA\\(GGML_TYPE_F16,[[:space:]]*f16,[[:space:]]*FA_COOPMAT1,[[:space:]]*_cm1\\)"
                "\\1// DISABLED: CREATE_FA(GGML_TYPE_F16, f16, FA_COOPMAT1, _cm1)"
                VULKAN_CPP_CONTENT "${VULKAN_CPP_CONTENT}")
            string(REGEX REPLACE 
                "([[:space:]]*)CREATE_FA\\(GGML_TYPE_Q4_0,[[:space:]]*q4_0,[[:space:]]*FA_COOPMAT1,[[:space:]]*_cm1\\)"
                "\\1// DISABLED: CREATE_FA(GGML_TYPE_Q4_0, q4_0, FA_COOPMAT1, _cm1)"
                VULKAN_CPP_CONTENT "${VULKAN_CPP_CONTENT}")
            string(REGEX REPLACE 
                "([[:space:]]*)CREATE_FA\\(GGML_TYPE_Q8_0,[[:space:]]*q8_0,[[:space:]]*FA_COOPMAT1,[[:space:]]*_cm1\\)"
                "\\1// DISABLED: CREATE_FA(GGML_TYPE_Q8_0, q8_0, FA_COOPMAT1, _cm1)"
                VULKAN_CPP_CONTENT "${VULKAN_CPP_CONTENT}")
            
            file(WRITE "${VULKAN_CPP}" "${VULKAN_CPP_CONTENT}")
            message(STATUS ">>> ✓ CoopMat shader variants disabled")
        else()
            message(WARNING ">>> ggml-vulkan.cpp not found, skipping CoopMat patch")
        endif()
        
        message(STATUS "Patching Vulkan CMakeLists.txt for cross-compilation: ${VULKAN_CMAKE}")
        
        # Disable Vulkan validation and tests for cross-compilation
        set(GGML_VULKAN_RUN_TESTS OFF CACHE BOOL "" FORCE)
        set(GGML_VULKAN_VALIDATE OFF CACHE BOOL "" FORCE)
        
        execute_process(
            COMMAND python3 "${PATCH_SCRIPT}" "${VULKAN_CMAKE}"
            RESULT_VARIABLE PATCH_RESULT
            OUTPUT_VARIABLE PATCH_OUTPUT
            ERROR_VARIABLE PATCH_ERROR
            WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        )
        
        if(PATCH_RESULT EQUAL 0)
            message(STATUS ">>> ✓ Vulkan patched: ${PATCH_OUTPUT}")
        else()
            message(FATAL_ERROR ">>> ✗ Patch failed (exit code: ${PATCH_RESULT})\nOutput: ${PATCH_OUTPUT}\nError: ${PATCH_ERROR}")
        endif()
    endif()
    
    message(STATUS "Adding llama.cpp subdirectory...")
    add_subdirectory(${llamacpp_SOURCE_DIR} ${llamacpp_BINARY_DIR} EXCLUDE_FROM_ALL)
    
    # Force correct Vulkan library for Android API 26+
    if(RAC_PLATFORM_ANDROID AND GGML_VULKAN AND TARGET ggml-vulkan)
        # Remove the default Vulkan::Vulkan link (uses wrong API level)
        get_target_property(VULKAN_LIBS ggml-vulkan LINK_LIBRARIES)
        if(VULKAN_LIBS)
            list(REMOVE_ITEM VULKAN_LIBS "Vulkan::Vulkan")
            set_target_properties(ggml-vulkan PROPERTIES LINK_LIBRARIES "${VULKAN_LIBS}")
        endif()
        
        # Override Vulkan library to use API 26 version (has vkGetPhysicalDeviceFeatures2)
        set(VULKAN_LIB_PATH "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/aarch64-linux-android/${ANDROID_MIN_SDK}/libvulkan.so")
        if(EXISTS "${VULKAN_LIB_PATH}")
            message(STATUS ">>> Forcing Vulkan library: ${VULKAN_LIB_PATH}")
            target_link_libraries(ggml-vulkan PUBLIC "${VULKAN_LIB_PATH}")
        else()
            message(WARNING ">>> Vulkan library not found at: ${VULKAN_LIB_PATH}")
        endif()
    endif()
    
    # Add Vulkan-Hpp headers to llama.cpp's Vulkan backend
    if(RAC_PLATFORM_ANDROID AND GGML_VULKAN AND TARGET ggml-vulkan)
        target_link_libraries(ggml-vulkan PRIVATE vulkan_hpp_headers)
        message(STATUS "Added Vulkan-Hpp headers to ggml-vulkan target")
        
        # Compile Vulkan shaders
        set(VULKAN_SRC_DIR "${llamacpp_SOURCE_DIR}/ggml/src/ggml-vulkan")
        set(NDK_GLSLC "${ANDROID_NDK}/shader-tools/linux-x86_64/glslc")
        set(SHADER_SCRIPT "${CMAKE_SOURCE_DIR}/scripts/compile-shaders-during-build.sh")
        set(SHADER_CPP "${VULKAN_SRC_DIR}/ggml-vulkan-shaders.cpp")
        set(SHADER_HPP "${VULKAN_SRC_DIR}/ggml-vulkan-shaders.hpp")
        
        # Custom command to compile shaders
        add_custom_command(
            OUTPUT "${SHADER_CPP}" "${SHADER_HPP}"
            COMMAND bash "${SHADER_SCRIPT}" "${VULKAN_SRC_DIR}" "${NDK_GLSLC}"
            WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
            COMMENT "Compiling Vulkan shaders..."
            VERBATIM
        )
        
        # Add shader files to ggml-vulkan target
        target_sources(ggml-vulkan PRIVATE "${SHADER_CPP}" "${SHADER_HPP}")
        
        message(STATUS "Vulkan shader compilation configured")
    endif()
    
    message(STATUS "llama.cpp subdirectory added")
else()
    message(STATUS "llama.cpp already populated")
endif()

message(STATUS "========== VULKAN PATCH DEBUG END ==========")

# =============================================================================
# LlamaCPP Backend Library
# =============================================================================

set(LLAMACPP_BACKEND_SOURCES
    llamacpp_backend.cpp
    rac_llm_llamacpp.cpp
    rac_backend_llamacpp_register.cpp
)

set(LLAMACPP_BACKEND_HEADERS
    llamacpp_backend.h
)

if(RAC_BUILD_SHARED)
    add_library(rac_backend_llamacpp SHARED
        ${LLAMACPP_BACKEND_SOURCES}
        ${LLAMACPP_BACKEND_HEADERS}
    )
else()
    add_library(rac_backend_llamacpp STATIC
        ${LLAMACPP_BACKEND_SOURCES}
        ${LLAMACPP_BACKEND_HEADERS}
    )
endif()

target_include_directories(rac_backend_llamacpp PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/include/rac/backends
    ${llamacpp_SOURCE_DIR}/include
    ${llamacpp_SOURCE_DIR}/common
    ${llamacpp_SOURCE_DIR}/ggml/include
    ${llamacpp_SOURCE_DIR}/vendor               # nlohmann/json.hpp
)

target_compile_definitions(rac_backend_llamacpp PRIVATE RAC_LLAMACPP_BUILDING)

target_link_libraries(rac_backend_llamacpp PUBLIC
    rac_commons
    llama
    common
)

# Link Vulkan backend if enabled
if(RAC_PLATFORM_ANDROID AND GGML_VULKAN AND TARGET ggml-vulkan)
    target_link_libraries(rac_backend_llamacpp PUBLIC ggml-vulkan)
    message(STATUS "✅ Linked ggml-vulkan to rac_backend_llamacpp")
endif()

target_compile_features(rac_backend_llamacpp PUBLIC cxx_std_17)

# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RAC_PLATFORM_IOS)
    message(STATUS "Configuring LlamaCPP backend for iOS")
    target_link_libraries(rac_backend_llamacpp PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )
    target_compile_definitions(rac_backend_llamacpp PRIVATE GGML_USE_METAL=1)

elseif(RAC_PLATFORM_ANDROID)
    message(STATUS "Configuring LlamaCPP backend for Android with Vulkan GPU support")
    
    # Link Android system libraries
    target_link_libraries(rac_backend_llamacpp PRIVATE log)
    
    # Link Vulkan library for GPU acceleration
    target_link_libraries(rac_backend_llamacpp PRIVATE vulkan)
    
    # Vulkan compile definition
    target_compile_definitions(rac_backend_llamacpp PRIVATE GGML_USE_VULKAN=1)
    
    # Don't use -fvisibility=hidden here - JNI bridge needs these symbols
    target_compile_options(rac_backend_llamacpp PRIVATE -O3 -ffunction-sections -fdata-sections)
    # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
    target_link_options(rac_backend_llamacpp PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)

elseif(RAC_PLATFORM_MACOS)
    message(STATUS "Configuring LlamaCPP backend for macOS")
    target_link_libraries(rac_backend_llamacpp PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )
endif()

# =============================================================================
# JNI TARGET (Android)
# =============================================================================

if(RAC_PLATFORM_ANDROID AND RAC_BUILD_SHARED)
    if(ANDROID)
        message(STATUS "Building LlamaCPP JNI bridge for Android")

        add_library(rac_backend_llamacpp_jni SHARED
            jni/rac_backend_llamacpp_jni.cpp
        )

        target_include_directories(rac_backend_llamacpp_jni PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_SOURCE_DIR}/include
        )

        target_link_libraries(rac_backend_llamacpp_jni PRIVATE
            rac_backend_llamacpp
            log
        )

        target_compile_options(rac_backend_llamacpp_jni PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
        # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
        target_link_options(rac_backend_llamacpp_jni PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
    endif()
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "LlamaCPP Backend Configuration:")
message(STATUS "  llama.cpp version: ${LLAMA_CPP_VERSION}")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
