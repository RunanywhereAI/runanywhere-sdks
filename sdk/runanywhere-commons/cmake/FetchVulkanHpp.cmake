# =============================================================================
# Fetch Vulkan-Hpp (C++ bindings for Vulkan)
# =============================================================================
# The Android NDK provides vulkan.h (C API) but not vulkan.hpp (C++ bindings).
# llama.cpp's Vulkan backend requires the C++ bindings, so we fetch them here.
#
# OPTIMIZATION: We download only the essential header files instead of the
# entire repository (which includes tests, samples, etc.)
# =============================================================================

message(STATUS "Setting up Vulkan-Hpp (C++ bindings for Vulkan)...")

# Vulkan-Hpp version should match the Vulkan version in the NDK
# NDK 29 uses Vulkan 1.3.275
set(VULKAN_HPP_VERSION "1.3.275" CACHE STRING "Vulkan-Hpp version")
set(VULKAN_HPP_DIR "${CMAKE_BINARY_DIR}/_deps/vulkan_hpp")
set(VULKAN_HPP_FILE "${VULKAN_HPP_DIR}/vulkan/vulkan.hpp")
set(VULKAN_HPP_MACROS "${VULKAN_HPP_DIR}/vulkan/vulkan_hpp_macros.hpp")

# Create directory if it doesn't exist
file(MAKE_DIRECTORY "${VULKAN_HPP_DIR}/vulkan")

# Download required header files if not already present
set(VULKAN_HEADERS
    "vulkan.hpp"
    "vulkan_hpp_macros.hpp"
    "vulkan_enums.hpp"
    "vulkan_handles.hpp"
    "vulkan_structs.hpp"
    "vulkan_funcs.hpp"
    "vulkan_raii.hpp"
    "vulkan_format_traits.hpp"
    "vulkan_hash.hpp"
    "vulkan_to_string.hpp"
)

set(ALL_PRESENT TRUE)
foreach(HEADER ${VULKAN_HEADERS})
    if(NOT EXISTS "${VULKAN_HPP_DIR}/vulkan/${HEADER}")
        set(ALL_PRESENT FALSE)
        break()
    endif()
endforeach()

if(NOT ALL_PRESENT)
    message(STATUS "Downloading Vulkan-Hpp headers v${VULKAN_HPP_VERSION} (~2MB)...")
    foreach(HEADER ${VULKAN_HEADERS})
        set(HEADER_FILE "${VULKAN_HPP_DIR}/vulkan/${HEADER}")
        if(NOT EXISTS "${HEADER_FILE}")
            message(STATUS "  Downloading ${HEADER}...")
            file(DOWNLOAD
                "https://raw.githubusercontent.com/KhronosGroup/Vulkan-Hpp/v${VULKAN_HPP_VERSION}/vulkan/${HEADER}"
                "${HEADER_FILE}"
                STATUS DOWNLOAD_STATUS
                TIMEOUT 300
                INACTIVITY_TIMEOUT 60
            )
            
            list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
            if(NOT STATUS_CODE EQUAL 0)
                list(GET DOWNLOAD_STATUS 1 ERROR_MESSAGE)
                message(WARNING "Failed to download ${HEADER}: ${ERROR_MESSAGE}")
                message(WARNING "Retrying ${HEADER} with longer timeout...")
                file(DOWNLOAD
                    "https://raw.githubusercontent.com/KhronosGroup/Vulkan-Hpp/v${VULKAN_HPP_VERSION}/vulkan/${HEADER}"
                    "${HEADER_FILE}"
                    STATUS RETRY_STATUS
                    TIMEOUT 600
                    INACTIVITY_TIMEOUT 120
                )
                list(GET RETRY_STATUS 0 RETRY_CODE)
                if(NOT RETRY_CODE EQUAL 0)
                    list(GET RETRY_STATUS 1 RETRY_ERROR)
                    message(FATAL_ERROR "Failed to download ${HEADER} after retry: ${RETRY_ERROR}")
                endif()
            endif()
        endif()
    endforeach()
    message(STATUS "✓ Downloaded Vulkan-Hpp headers successfully")
else()
    message(STATUS "✓ Vulkan-Hpp headers already present, skipping download")
endif()

# Create an interface library for Vulkan-Hpp
if(NOT TARGET vulkan_hpp_headers)
    add_library(vulkan_hpp_headers INTERFACE)
    target_include_directories(vulkan_hpp_headers INTERFACE
        ${VULKAN_HPP_DIR}
    )
    
    # Also ensure the NDK Vulkan C headers are available
    if(ANDROID_NDK)
        if(WIN32)
            set(NDK_VULKAN_INCLUDE "${ANDROID_NDK}/toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/include")
        else()
            set(NDK_VULKAN_INCLUDE "${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include")
        endif()
        target_include_directories(vulkan_hpp_headers INTERFACE ${NDK_VULKAN_INCLUDE})
        message(STATUS "NDK Vulkan C headers: ${NDK_VULKAN_INCLUDE}/vulkan")
    endif()
endif()

message(STATUS "Vulkan-Hpp configured successfully")
