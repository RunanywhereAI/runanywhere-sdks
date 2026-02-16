# sd.cpp Diffusion Backend
# Cross-platform diffusion inference using stable-diffusion.cpp (ggml)
#
# On iOS: Uses Metal backend for GPU acceleration
# On Android: Uses CPU (default), Vulkan, or OpenCL (Adreno) for GPU
#
# Usage:
#   cmake -DRAC_BACKEND_SDCPP=ON ..

set(SDCPP_BACKEND_SOURCES
    sdcpp_diffusion_backend.cpp
    rac_diffusion_sdcpp.cpp
    rac_backend_sdcpp_register.cpp
)

# Fetch stable-diffusion.cpp via FetchContent
include(FetchContent)

# Load version from centralized VERSIONS file if available
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

# Platform-specific GPU backend selection
if(APPLE)
    set(SD_METAL ON CACHE BOOL "Use Metal backend for Apple platforms" FORCE)
    message(STATUS "sd.cpp: Metal backend enabled (Apple)")
elseif(ANDROID)
    # Default to CPU on Android; Vulkan/OpenCL can be enabled per-device
    set(SD_VULKAN OFF CACHE BOOL "Vulkan backend (experimental on Android)" FORCE)
    set(SD_OPENCL OFF CACHE BOOL "OpenCL backend for Adreno GPUs" FORCE)
    message(STATUS "sd.cpp: CPU backend (Android)")
endif()

FetchContent_MakeAvailable(stable_diffusion_cpp)

# Create the backend library
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

target_compile_features(rac_backend_sdcpp PRIVATE cxx_std_17)

# JNI bridge for Android
if(RAC_BUILD_JNI AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/jni")
    add_library(rac_backend_sdcpp_jni SHARED
        jni/rac_backend_sdcpp_jni.cpp
    )
    target_link_libraries(rac_backend_sdcpp_jni PRIVATE
        rac_backend_sdcpp
        rac_commons
    )
    target_include_directories(rac_backend_sdcpp_jni PRIVATE
        ${CMAKE_SOURCE_DIR}/include
    )
endif()
