# MetalRT Backend — Apple-only (iOS/macOS)
# Requires pre-built libmetalrt_engine.a and metalrt_c_api.h

set(METALRT_SOURCES
    rac_llm_metalrt.cpp
    rac_stt_metalrt.cpp
    rac_tts_metalrt.cpp
    rac_vlm_metalrt.cpp
    rac_backend_metalrt_register.cpp
)

# MetalRT pre-built library location (set by parent or via -DMETALRT_ROOT=...)
if(NOT DEFINED METALRT_ROOT)
    # Default: assume MetalRT is sibling to runanywhere-sdks
    set(METALRT_ROOT "${CMAKE_SOURCE_DIR}/../../../MetalRT" CACHE PATH "Path to MetalRT project root")
endif()

set(METALRT_INCLUDE_DIR "${METALRT_ROOT}/src" CACHE PATH "Path to metalrt_c_api.h")

# Find the pre-built static library
if(DEFINED METALRT_LIB_DIR)
    set(_metalrt_lib_dir "${METALRT_LIB_DIR}")
else()
    set(_metalrt_lib_dir "${METALRT_ROOT}/build")
endif()

add_library(rac_backend_metalrt STATIC ${METALRT_SOURCES})

target_include_directories(rac_backend_metalrt PRIVATE
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${METALRT_INCLUDE_DIR}
)

target_compile_definitions(rac_backend_metalrt PRIVATE RAC_METALRT_BUILDING)

# Link MetalRT static library
find_library(METALRT_ENGINE_LIB
    NAMES metalrt_engine
    PATHS ${_metalrt_lib_dir}
    NO_DEFAULT_PATH
)

if(METALRT_ENGINE_LIB)
    target_link_libraries(rac_backend_metalrt PRIVATE ${METALRT_ENGINE_LIB})
    message(STATUS "MetalRT: Found libmetalrt_engine at ${METALRT_ENGINE_LIB}")
else()
    message(WARNING "MetalRT: libmetalrt_engine.a not found in ${_metalrt_lib_dir} — will need to be linked by the consuming app")
endif()

# Apple frameworks
target_link_libraries(rac_backend_metalrt PRIVATE
    "-framework Metal"
    "-framework Foundation"
    "-framework Accelerate"
)
