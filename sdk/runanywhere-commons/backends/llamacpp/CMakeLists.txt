# =============================================================================
# RABackendLlamaCPP - LLM backend using llama.cpp
# =============================================================================
#
# This module wraps runanywhere-core's LlamaCPP backend for use with
# the runanywhere-commons module/service registry system.
#
# Capabilities: TEXT_GENERATION (LLM)
#

cmake_minimum_required(VERSION 3.16)

# Use version from parent project (loaded from VERSIONS file)
if(NOT DEFINED RAC_PROJECT_VERSION)
    set(RAC_PROJECT_VERSION "1.0.0")
endif()

project(RABackendLlamaCPP VERSION ${RAC_PROJECT_VERSION} LANGUAGES CXX)

# =============================================================================
# OPTIONS
# =============================================================================

option(RAC_LLAMACPP_BUILD_SHARED "Build as shared library" OFF)
option(RAC_LLAMACPP_ENABLE_METAL "Enable Metal GPU support (Apple)" ON)

# =============================================================================
# SOURCES
# =============================================================================

set(LLAMACPP_SOURCES
    src/rac_llm_llamacpp.cpp
    src/rac_backend_llamacpp_register.cpp
    src/rac_llm_service_impl.cpp
)

set(LLAMACPP_HEADERS
    include/rac_llm_llamacpp.h
)

# =============================================================================
# LIBRARY TARGET
# =============================================================================

if(RAC_LLAMACPP_BUILD_SHARED)
    add_library(rac_backend_llamacpp SHARED ${LLAMACPP_SOURCES})
else()
    add_library(rac_backend_llamacpp STATIC ${LLAMACPP_SOURCES})
endif()

# Public headers
target_include_directories(rac_backend_llamacpp
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# C++17 standard
target_compile_features(rac_backend_llamacpp PUBLIC cxx_std_17)

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Link against rac_commons (parent project provides this)
if(TARGET rac_commons)
    target_link_libraries(rac_backend_llamacpp PUBLIC rac_commons)
endif()

# Include runanywhere-commons public headers
target_include_directories(rac_backend_llamacpp PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

# Link against runanywhere-core's llamacpp backend
# Use pre-built library if available, otherwise use compiled target
if(DEFINED RUNANYWHERE_CORE_LLAMACPP_LIB)
    # Pre-built library mode (USE_PREBUILT_CORE=ON)
    target_link_libraries(rac_backend_llamacpp PRIVATE ${RUNANYWHERE_CORE_LLAMACPP_LIB})
    # Include directories are set globally via RUNANYWHERE_CORE_INCLUDE_DIRS
elseif(TARGET runanywhere_llamacpp)
    # Source compilation mode (legacy)
    target_link_libraries(rac_backend_llamacpp PRIVATE runanywhere_llamacpp)
    # Include runanywhere-core headers for backend APIs
    target_include_directories(rac_backend_llamacpp PRIVATE
        ${RUNANYWHERE_CORE_DIR}/src
        ${RUNANYWHERE_CORE_DIR}/src/capabilities
        ${RUNANYWHERE_CORE_DIR}/src/backends/llamacpp
    )
endif()

# =============================================================================
# PLATFORM-SPECIFIC
# =============================================================================

if(APPLE)
    # Metal framework for GPU acceleration
    if(RAC_LLAMACPP_ENABLE_METAL)
        find_library(METAL_FRAMEWORK Metal)
        find_library(METALKIT_FRAMEWORK MetalKit)
        find_library(METALPERFORMANCESHADERS_FRAMEWORK MetalPerformanceShaders)
        if(METAL_FRAMEWORK AND METALKIT_FRAMEWORK)
            target_link_libraries(rac_backend_llamacpp PRIVATE
                ${METAL_FRAMEWORK}
                ${METALKIT_FRAMEWORK}
                ${METALPERFORMANCESHADERS_FRAMEWORK}
            )
            target_compile_definitions(rac_backend_llamacpp PRIVATE GGML_USE_METAL=1)
        endif()
    endif()

    # Accelerate framework
    find_library(ACCELERATE_FRAMEWORK Accelerate)
    if(ACCELERATE_FRAMEWORK)
        target_link_libraries(rac_backend_llamacpp PRIVATE ${ACCELERATE_FRAMEWORK})
    endif()
endif()

# =============================================================================
# SYMBOL VISIBILITY
# =============================================================================

# Default to hidden visibility
set_target_properties(rac_backend_llamacpp PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)

# Export macro
target_compile_definitions(rac_backend_llamacpp PRIVATE RAC_LLAMACPP_BUILDING)

# =============================================================================
# JNI TARGET (Android/JVM)
# =============================================================================

# Only build JNI if we have JNI and building for Android
if(RAC_BUILD_JNI AND ANDROID)
    # Find JNI
    find_package(JNI)

    if(JNI_FOUND)
        set(LLAMACPP_JNI_SOURCES
            src/jni/rac_backend_llamacpp_jni.cpp
        )

        add_library(rac_backend_llamacpp_jni SHARED ${LLAMACPP_JNI_SOURCES})

        target_include_directories(rac_backend_llamacpp_jni PRIVATE
            ${JNI_INCLUDE_DIRS}
            ${CMAKE_CURRENT_SOURCE_DIR}/include
            ${CMAKE_SOURCE_DIR}/include
        )

        target_link_libraries(rac_backend_llamacpp_jni PRIVATE
            rac_backend_llamacpp
            rac_commons
            ${JNI_LIBRARIES}
        )

        # Android-specific logging
        if(ANDROID)
            target_link_libraries(rac_backend_llamacpp_jni PRIVATE log)
        endif()

        # Install JNI library
        install(TARGETS rac_backend_llamacpp_jni
            LIBRARY DESTINATION lib
            ARCHIVE DESTINATION lib
            RUNTIME DESTINATION bin
        )
    endif()
endif()

# =============================================================================
# INSTALLATION
# =============================================================================

install(TARGETS rac_backend_llamacpp
    EXPORT rac_backend_llamacppTargets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)

install(FILES ${LLAMACPP_HEADERS}
    DESTINATION include/rac
)
