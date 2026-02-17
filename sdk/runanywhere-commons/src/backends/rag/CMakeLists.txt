# =============================================================================
# RAG Backend - Retrieval-Augmented Generation
# =============================================================================

message(STATUS "Configuring RAG backend...")

# Set policy for USearch compatibility
if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

# =============================================================================
# Dependencies
# =============================================================================

include(FetchContent)

# Fetch USearch (header-only vector database)
set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)

# Workaround for USearch's old CMake minimum version requirement
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE INTERNAL "")

# Disable FP16 and SIMD support before fetching USearch
set(USEARCH_USE_FP16LIB OFF CACHE BOOL "" FORCE)
set(USEARCH_USE_SIMSIMD OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    usearch
    GIT_REPOSITORY https://github.com/unum-cloud/usearch.git
    GIT_TAG        v2.15.2
    GIT_SHALLOW    TRUE
)
set(USEARCH_BUILD_TEST_C OFF CACHE BOOL "" FORCE)
set(USEARCH_BUILD_TEST_CPP OFF CACHE BOOL "" FORCE)
set(USEARCH_BUILD_BENCHMARK OFF CACHE BOOL "" FORCE)
set(USEARCH_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(usearch)

# Force disable FP16 in USearch (header-only needs compile defs)
add_compile_definitions(USEARCH_USE_FP16LIB=0 USEARCH_USE_SIMSIMD=0)

# nlohmann_json (should already be available from other backends)
if(NOT TARGET nlohmann_json::nlohmann_json)
    FetchContent_Declare(
        nlohmann_json
        GIT_REPOSITORY https://github.com/nlohmann/json.git
        GIT_TAG        v3.11.3
        GIT_SHALLOW    TRUE
    )
    set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(nlohmann_json)
endif()

# =============================================================================
# RAG Backend Library
# =============================================================================

# Core RAG components (always built)
set(RAG_BACKEND_SOURCES
    rag_backend.cpp
    vector_store_usearch.cpp
    rag_chunker.cpp
    rac_backend_rag_register.cpp
    rac_rag_pipeline.cpp
)

set(RAG_BACKEND_HEADERS
    rag_backend.h
    vector_store_usearch.h
    rag_chunker.h
    inference_provider.h
)

# Provider implementations are conditionally added when backends are available
# These files include backend headers so they require the backends to be built
if(TARGET rac_backend_onnx)
    list(APPEND RAG_BACKEND_SOURCES onnx_embedding_provider.cpp)
    list(APPEND RAG_BACKEND_HEADERS onnx_embedding_provider.h)
    
    # ONNX can also provide text generation
    list(APPEND RAG_BACKEND_SOURCES onnx_generator.cpp)
    list(APPEND RAG_BACKEND_HEADERS onnx_generator.h)
endif()

if(TARGET rac_backend_llamacpp)
    list(APPEND RAG_BACKEND_SOURCES llamacpp_generator.cpp)
    list(APPEND RAG_BACKEND_HEADERS llamacpp_generator.h)
endif()

if(RAC_BUILD_SHARED)
    add_library(rac_backend_rag SHARED ${RAG_BACKEND_SOURCES} ${RAG_BACKEND_HEADERS})
else()
    add_library(rac_backend_rag STATIC ${RAG_BACKEND_SOURCES} ${RAG_BACKEND_HEADERS})
endif()

target_include_directories(rac_backend_rag PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/include/rac/backends
    ${usearch_SOURCE_DIR}/include
)

target_link_libraries(rac_backend_rag PUBLIC
    rac_commons
    nlohmann_json::nlohmann_json
)

# RAG providers link to backends conditionally (maintains separation of concerns)
# Providers use forward declarations - can build without backends
if(TARGET rac_backend_onnx)
    target_link_libraries(rac_backend_rag PUBLIC rac_backend_onnx)
    target_compile_definitions(rac_backend_rag PRIVATE RAG_HAS_ONNX_PROVIDER=1)
endif()

if(TARGET rac_backend_llamacpp)
    target_link_libraries(rac_backend_rag PUBLIC rac_backend_llamacpp)
    target_compile_definitions(rac_backend_rag PRIVATE RAG_HAS_LLAMACPP_PROVIDER=1)
endif()

# Define RAC_RAG_BUILDING to export symbols
target_compile_definitions(rac_backend_rag PRIVATE RAC_RAG_BUILDING)

# USearch requires C++17 - set via properties for better Xcode compatibility
set_target_properties(rac_backend_rag PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

target_compile_options(rac_backend_rag PRIVATE
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wno-unused-parameter>
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wno-missing-field-initializers>
)

# Disable FP16 support to avoid compilation issues
target_compile_definitions(rac_backend_rag PRIVATE
    USEARCH_USE_FP16LIB=0
    USEARCH_USE_SIMSIMD=0
)

# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RAC_PLATFORM_IOS)
    message(STATUS "Configuring RAG backend for iOS")
    target_link_libraries(rac_backend_rag PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
    )

elseif(RAC_PLATFORM_ANDROID)
    message(STATUS "Configuring RAG backend for Android")
    target_link_libraries(rac_backend_rag PRIVATE log)
    # Ensure ORT_API_VERSION matches bundled libonnxruntime (1.17.x -> API 17)
    target_compile_definitions(rac_backend_rag PRIVATE ORT_API_VERSION=17)
    target_compile_options(rac_backend_rag PRIVATE -O3 -ffunction-sections -fdata-sections)
    # 16KB page alignment for Android 15+ (API 35) compliance
    target_link_options(rac_backend_rag PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)

elseif(RAC_PLATFORM_MACOS)
    message(STATUS "Configuring RAG backend for macOS")
    target_link_libraries(rac_backend_rag PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
    )
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "RAG Backend Configuration:")
message(STATUS "  USearch: v2.15.2 (HNSW vector search)")
message(STATUS "  Vector dimension: Configurable (default 384)")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
