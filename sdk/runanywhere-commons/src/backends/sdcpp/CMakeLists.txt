# =============================================================================
# sd.cpp Diffusion Backend
# =============================================================================
# Cross-platform diffusion inference using stable-diffusion.cpp (ggml).
#
# GPU Backends (selected automatically per platform):
#   iOS/macOS: Metal (Apple GPU / Neural Engine)
#   Android:   OpenCL (Adreno GPUs — ~3-5x faster than CPU)
#   Desktop:   Vulkan (NVIDIA, AMD, Intel) or CPU fallback
#
# Android GPU note:
#   OpenCL is the default and recommended GPU backend for Android.
#   Qualcomm contributes Adreno-optimized kernels to ggml-opencl.
#   Vulkan is available but crashes on some Adreno drivers (known ggml issue).
#
# Build options:
#   RAC_SDCPP_OPENCL  - Force OpenCL ON/OFF (default: ON on Android)
#   RAC_SDCPP_VULKAN  - Force Vulkan ON/OFF (default: OFF, unstable on Adreno)
#
# Usage:
#   cmake -DRAC_BACKEND_SDCPP=ON ..                       # Default (OpenCL on Android)
#   cmake -DRAC_BACKEND_SDCPP=ON -DRAC_SDCPP_OPENCL=OFF ..  # CPU-only (debug/testing)
#   cmake -DRAC_BACKEND_SDCPP=ON -DRAC_SDCPP_VULKAN=ON ..   # Vulkan (experimental)
# =============================================================================

set(SDCPP_BACKEND_SOURCES
    sdcpp_diffusion_backend.cpp
    rac_diffusion_sdcpp.cpp
    rac_backend_sdcpp_register.cpp
)

# =============================================================================
# Fetch stable-diffusion.cpp via FetchContent
# =============================================================================

include(FetchContent)

if(DEFINED SDCPP_VERSION)
    set(SDCPP_TAG "${SDCPP_VERSION}")
else()
    set(SDCPP_TAG "master")
endif()

FetchContent_Declare(
    stable_diffusion_cpp
    GIT_REPOSITORY https://github.com/leejet/stable-diffusion.cpp.git
    GIT_TAG        ${SDCPP_TAG}
    GIT_SHALLOW    TRUE
)

# Configure sd.cpp build options before fetching
set(SD_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SD_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

# =============================================================================
# Platform-specific GPU backend selection
# =============================================================================

# Allow user override via RAC_SDCPP_VULKAN
if(NOT DEFINED RAC_SDCPP_VULKAN)
    # Vulkan is OFF by default — crashes on Adreno GPUs (vkCmdBindPipeline driver bug).
    # Use OpenCL instead. Enable Vulkan explicitly for testing only.
    set(RAC_SDCPP_VULKAN OFF)
endif()

# Allow user override via RAC_SDCPP_OPENCL
if(NOT DEFINED RAC_SDCPP_OPENCL)
    if(ANDROID)
        # OpenCL GPU acceleration for Adreno GPUs (Qualcomm Snapdragon).
        # Uses dlopen shim (opencl_stub.c) to load vendor libOpenCL.so at runtime.
        # CLIP and VAE run on CPU; only UNet denoising uses GPU.
        set(RAC_SDCPP_OPENCL ON)
    else()
        set(RAC_SDCPP_OPENCL OFF)
    endif()
endif()

if(APPLE)
    # Apple: Metal for GPU (best performance, uses Apple GPU + Neural Engine)
    set(SD_METAL ON CACHE BOOL "Use Metal backend for Apple platforms" FORCE)
    set(SD_VULKAN OFF CACHE BOOL "" FORCE)
    set(SD_OPENCL OFF CACHE BOOL "" FORCE)
    message(STATUS "sd.cpp: Metal GPU backend (Apple)")

elseif(ANDROID)
    set(SD_VULKAN ${RAC_SDCPP_VULKAN} CACHE BOOL "Vulkan GPU backend for Android" FORCE)
    set(SD_OPENCL ${RAC_SDCPP_OPENCL} CACHE BOOL "OpenCL backend for Adreno GPUs" FORCE)

    if(RAC_SDCPP_OPENCL)
        # =================================================================
        # OpenCL dependency handling for Android cross-compilation
        # =================================================================
        # ggml-opencl requires OpenCL headers and a link-time library.
        # Android devices provide libOpenCL.so at runtime (from GPU vendor,
        # e.g. Qualcomm Adreno), but the NDK does not ship OpenCL headers
        # or link stubs.
        #
        # Strategy:
        #   1. Fetch Khronos OpenCL-Headers for compilation
        #   2. Build our dlopen-forwarding libOpenCL.so shim
        #   3. The shim IS shipped in the APK — at runtime it uses dlopen()
        #      to load the vendor's real OpenCL library and forwards all calls
        # =================================================================

        # 1. Fetch OpenCL headers (header-only, provides CL/cl.h)
        FetchContent_Declare(
            opencl_headers
            GIT_REPOSITORY https://github.com/KhronosGroup/OpenCL-Headers.git
            GIT_TAG        v2024.10.24
            GIT_SHALLOW    TRUE
        )
        FetchContent_MakeAvailable(opencl_headers)

        # 2. Build a minimal OpenCL stub library for link-time resolution.
        #    The Khronos ICD Loader's symbols get GC'd by Android's --gc-sections,
        #    so we use our own stub that just defines the CL API functions.
        add_library(opencl_stub SHARED ${CMAKE_CURRENT_SOURCE_DIR}/opencl_stub.c)
        target_include_directories(opencl_stub PRIVATE "${opencl_headers_SOURCE_DIR}")
        # Force all symbols to be exported so --gc-sections won't discard them.
        # Without this, -ffunction-sections + --gc-sections removes all unreferenced funcs.
        target_compile_options(opencl_stub PRIVATE -fvisibility=default -fno-function-sections)
        # Link Android log and dl for the dlopen-based shim
        target_link_libraries(opencl_stub PRIVATE log dl)
        set_target_properties(opencl_stub PROPERTIES
            OUTPUT_NAME "OpenCL"
        )

        # 3. Create a custom FindOpenCL.cmake so ggml's find_package(OpenCL) succeeds.
        #    Points to our headers and stub library.
        file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/FindOpenCL.cmake"
            "set(OpenCL_FOUND TRUE)\n"
            "set(OpenCL_INCLUDE_DIRS \"${opencl_headers_SOURCE_DIR}\")\n"
            "set(OpenCL_LIBRARIES opencl_stub)\n"
            "set(OpenCL_VERSION_STRING \"3.0\")\n"
        )
        list(INSERT CMAKE_MODULE_PATH 0 "${CMAKE_CURRENT_BINARY_DIR}")

        # 4. Enable Adreno-optimized OpenCL kernels (contributed by Qualcomm)
        set(GGML_OPENCL_USE_ADRENO_KERNELS ON CACHE BOOL "Use Adreno-optimized matmul kernels" FORCE)
        set(GGML_OPENCL_EMBED_KERNELS ON CACHE BOOL "Embed OpenCL kernels in binary" FORCE)

        message(STATUS "sd.cpp: OpenCL GPU backend enabled (Android, Adreno-optimized)")

    elseif(RAC_SDCPP_VULKAN)
        # =================================================================
        # Vulkan dependency handling (EXPERIMENTAL — known Adreno crashes)
        # =================================================================
        # ggml-vulkan requires vulkan.hpp (C++ bindings from Vulkan-Hpp).
        # The Android NDK provides vulkan.h (C) but NOT vulkan.hpp (C++).
        # =================================================================

        set(_VK_HPP_FOUND FALSE)
        set(_VK_HPP_SEARCH_PATHS
            "/opt/homebrew/include"
            "/usr/local/include"
            "$ENV{VULKAN_SDK}/include"
            "/usr/include"
        )

        foreach(_VK_PATH ${_VK_HPP_SEARCH_PATHS})
            if(EXISTS "${_VK_PATH}/vulkan/vulkan.hpp")
                include_directories(SYSTEM "${_VK_PATH}")
                set(_VK_HPP_FOUND TRUE)
                message(STATUS "sd.cpp: Found vulkan.hpp at ${_VK_PATH}")
                break()
            endif()
        endforeach()

        if(NOT _VK_HPP_FOUND)
            message(FATAL_ERROR
                "vulkan.hpp not found! Required for Vulkan GPU backend.\n"
                "Install with:\n"
                "  macOS:  brew install vulkan-headers\n"
                "  Linux:  apt install libvulkan-dev vulkan-headers\n"
                "  Any:    Download Vulkan SDK from https://vulkan.lunarg.com/sdk/home\n"
                "\n"
                "Or use OpenCL instead (recommended for Android):\n"
                "  cmake -DRAC_SDCPP_VULKAN=OFF -DRAC_SDCPP_OPENCL=ON .."
            )
        endif()

        if(ANDROID_NATIVE_API_LEVEL AND ANDROID_NATIVE_API_LEVEL LESS 26)
            message(WARNING "sd.cpp Vulkan requires Android API 26+. Current: ${ANDROID_NATIVE_API_LEVEL}")
        endif()

        message(STATUS "sd.cpp: Vulkan GPU backend enabled (Android, EXPERIMENTAL)")
    else()
        message(STATUS "sd.cpp: CPU-only backend (Android, no GPU acceleration)")
    endif()

else()
    # Desktop Linux/Windows: use Vulkan if available, else CPU
    set(SD_VULKAN ${RAC_SDCPP_VULKAN} CACHE BOOL "" FORCE)
    set(SD_OPENCL OFF CACHE BOOL "" FORCE)
    if(RAC_SDCPP_VULKAN)
        message(STATUS "sd.cpp: Vulkan GPU backend (Desktop)")
    else()
        message(STATUS "sd.cpp: CPU backend (Desktop)")
    endif()
endif()

# =============================================================================
# Fetch and build stable-diffusion.cpp
# =============================================================================

FetchContent_MakeAvailable(stable_diffusion_cpp)

# =============================================================================
# Backend library
# =============================================================================

add_library(rac_backend_sdcpp STATIC ${SDCPP_BACKEND_SOURCES})

target_include_directories(rac_backend_sdcpp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${stable_diffusion_cpp_SOURCE_DIR}/include
    ${stable_diffusion_cpp_SOURCE_DIR}
)

target_link_libraries(rac_backend_sdcpp PRIVATE
    rac_commons
    stable-diffusion
)

# Android: link log library for __android_log_print in sdcpp_diffusion_backend.cpp
if(ANDROID)
    target_link_libraries(rac_backend_sdcpp PRIVATE log)
endif()

target_compile_features(rac_backend_sdcpp PRIVATE cxx_std_17)

# =============================================================================
# JNI bridge for Android/JVM
# =============================================================================

if(RAC_BUILD_JNI AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/jni")
    add_library(rac_backend_sdcpp_jni SHARED
        jni/rac_backend_sdcpp_jni.cpp
    )
    target_link_libraries(rac_backend_sdcpp_jni PRIVATE
        rac_backend_sdcpp
        rac_commons
    )

    # OpenCL: Static libs don't propagate link deps, so explicitly link the stub.
    # At runtime the device's vendor libOpenCL.so (e.g. Qualcomm Adreno) is used.
    if(RAC_SDCPP_OPENCL AND TARGET opencl_stub)
        target_link_libraries(rac_backend_sdcpp_jni PRIVATE opencl_stub)
    endif()

    target_include_directories(rac_backend_sdcpp_jni PRIVATE
        ${CMAKE_SOURCE_DIR}/include
    )
endif()
