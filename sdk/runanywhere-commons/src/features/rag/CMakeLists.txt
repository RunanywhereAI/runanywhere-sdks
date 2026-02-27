# =============================================================================
# RAG Pipeline — Orchestrates LLM + Embeddings services for RAG
#
# This is a pipeline (like Voice Agent), NOT a standalone backend.
# It calls through the LLM and Embeddings service vtables — it does NOT
# link llama.cpp or ONNX Runtime directly.
# =============================================================================

message(STATUS "Configuring RAG pipeline...")

if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

# =============================================================================
# Dependencies (RAG-specific only — USearch for vector search)
# =============================================================================

include(FetchContent)

set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE INTERNAL "")

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

add_compile_definitions(USEARCH_USE_FP16LIB=0 USEARCH_USE_SIMSIMD=0)

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
# RAG Pipeline Library (no direct backend dependencies)
# =============================================================================

set(RAG_PIPELINE_SOURCES
    rag_backend.cpp
    vector_store_usearch.cpp
    rag_chunker.cpp
    bm25_index.cpp
    rac_rag_register.cpp
    rac_rag_pipeline.cpp
)

# ONNX embedding provider — wraps as a proper embeddings service backend
if(TARGET rac_backend_onnx)
    list(APPEND RAG_PIPELINE_SOURCES
        onnx_embedding_provider.cpp
        rac_onnx_embeddings_register.cpp
    )
endif()

set(RAG_PIPELINE_HEADERS
    rag_backend.h
    vector_store_usearch.h
    rag_chunker.h
    bm25_index.h
)

if(RAC_BUILD_SHARED)
    add_library(rac_backend_rag SHARED ${RAG_PIPELINE_SOURCES} ${RAG_PIPELINE_HEADERS})
else()
    add_library(rac_backend_rag STATIC ${RAG_PIPELINE_SOURCES} ${RAG_PIPELINE_HEADERS})
endif()

target_include_directories(rac_backend_rag PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/include/rac/backends
    ${usearch_SOURCE_DIR}/include
)

# RAG links against rac_commons for vtable dispatch — NOT against backend libraries
target_link_libraries(rac_backend_rag PUBLIC
    rac_commons
    nlohmann_json::nlohmann_json
)

# ONNX embedding provider needs ONNX Runtime headers for inference
if(TARGET rac_backend_onnx)
    target_link_libraries(rac_backend_rag PUBLIC rac_backend_onnx)
    target_compile_definitions(rac_backend_rag PRIVATE RAG_HAS_ONNX_PROVIDER=1)
endif()

target_compile_definitions(rac_backend_rag PRIVATE RAC_RAG_BUILDING)

set_target_properties(rac_backend_rag PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

target_compile_options(rac_backend_rag PRIVATE
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wno-unused-parameter>
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wno-missing-field-initializers>
)

target_compile_definitions(rac_backend_rag PRIVATE
    USEARCH_USE_FP16LIB=0
    USEARCH_USE_SIMSIMD=0
)

# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RAC_PLATFORM_IOS)
    message(STATUS "Configuring RAG pipeline for iOS")
    target_link_libraries(rac_backend_rag PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
    )

elseif(RAC_PLATFORM_ANDROID)
    message(STATUS "Configuring RAG pipeline for Android")
    target_link_libraries(rac_backend_rag PRIVATE log)
    target_compile_definitions(rac_backend_rag PRIVATE ORT_API_VERSION=17)
    target_compile_options(rac_backend_rag PRIVATE -O3 -ffunction-sections -fdata-sections)
    target_link_options(rac_backend_rag PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)

elseif(RAC_PLATFORM_MACOS)
    message(STATUS "Configuring RAG pipeline for macOS")
    target_link_libraries(rac_backend_rag PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
    )
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "RAG Pipeline Configuration:")
message(STATUS "  USearch: v2.15.2 (HNSW vector search)")
message(STATUS "  Architecture: Pipeline (calls LLM + Embeddings via vtables)")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")

# =============================================================================
# JNI Bridge for Android
# =============================================================================

if(RAC_PLATFORM_ANDROID AND RAC_BUILD_SHARED)
    if(ANDROID)
        message(STATUS "Building RAG JNI bridge for Android")

        get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

        add_library(rac_backend_rag_jni SHARED jni/rac_rag_jni.cpp)

        target_include_directories(rac_backend_rag_jni PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${RAC_COMMONS_ROOT_DIR}/include
        )

        target_link_libraries(rac_backend_rag_jni PRIVATE
            rac_backend_rag
            log
        )

        target_compile_options(rac_backend_rag_jni PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
        target_link_options(rac_backend_rag_jni PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
    endif()
endif()
