# Sarvam AI Backend - Cloud STT via Sarvam API

message(STATUS "Configuring Sarvam backend...")

# Dependencies: nlohmann_json for response parsing
include(FetchContent)

if(NOT TARGET nlohmann_json::nlohmann_json)
    if(NOT DEFINED NLOHMANN_JSON_VERSION)
        set(NLOHMANN_JSON_VERSION "3.11.3")
    endif()

    FetchContent_Declare(
        nlohmann_json
        GIT_REPOSITORY https://github.com/nlohmann/json.git
        GIT_TAG        v${NLOHMANN_JSON_VERSION}
        GIT_SHALLOW    TRUE
    )
    set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
    set(JSON_Install OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(nlohmann_json)
endif()

# Sources
set(SARVAM_BACKEND_SOURCES
    rac_stt_sarvam.cpp
    rac_backend_sarvam_register.cpp
)

if(RAC_BUILD_JNI)
    list(APPEND SARVAM_BACKEND_SOURCES jni/rac_backend_sarvam_jni.cpp)
endif()

if(RAC_BUILD_SHARED)
    add_library(rac_backend_sarvam SHARED ${SARVAM_BACKEND_SOURCES})
else()
    add_library(rac_backend_sarvam STATIC ${SARVAM_BACKEND_SOURCES})
endif()

get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

target_include_directories(rac_backend_sarvam PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${RAC_COMMONS_ROOT_DIR}/include
    ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
)

target_compile_definitions(rac_backend_sarvam PRIVATE RAC_SARVAM_BUILDING)

target_link_libraries(rac_backend_sarvam PUBLIC
    rac_commons
    nlohmann_json::nlohmann_json
)

set_target_properties(rac_backend_sarvam PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

# Platform-specific
if(RAC_PLATFORM_ANDROID)
    target_link_libraries(rac_backend_sarvam PRIVATE log)
    target_compile_options(rac_backend_sarvam PRIVATE -O3 -ffunction-sections -fdata-sections)
    target_link_options(rac_backend_sarvam PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
endif()

message(STATUS "Sarvam Backend: STT (cloud API)")
