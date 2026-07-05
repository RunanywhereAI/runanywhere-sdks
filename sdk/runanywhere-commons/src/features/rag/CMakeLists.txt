# RAG Pipeline — Orchestrates LLM + Embeddings services for RAG
#
# This is a pipeline (like Voice Agent), NOT a standalone backend.
# It calls through the LLM and Embeddings service vtables — it does NOT
# link llama.cpp or ONNX Runtime directly.

message(STATUS "Configuring RAG pipeline...")

if(POLICY CMP0135)
    cmake_policy(SET CMP0135 NEW)
endif()

# Dependencies (RAG-specific only — USearch for vector search)

include(FetchContent)

set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE INTERNAL "")

set(USEARCH_USE_FP16LIB OFF CACHE BOOL "" FORCE)
set(USEARCH_USE_SIMSIMD OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    usearch
    GIT_REPOSITORY https://github.com/unum-cloud/usearch.git
    GIT_TAG        ${USEARCH_VERSION}
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
        GIT_TAG        v${NLOHMANN_JSON_VERSION}
        GIT_SHALLOW    TRUE
    )
    set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(nlohmann_json)
endif()

# RAG Pipeline Library (OBJECT — folded into rac_commons at link time)
#
# Built as OBJECT so all RAG symbols end up inside librac_commons.{a,so}.
# There is no separate librac_backend_rag binary to distribute.

set(RAG_PIPELINE_SOURCES
    rag_backend.cpp
    rag_pipeline_graph.cpp
    rag_rerank.cpp
    rag_fusion.cpp
    vector_store_usearch.cpp
    rag_chunker.cpp
    bm25_index.cpp
    rac_rag_register.cpp
    rac_rag_proto_abi.cpp
)

# ONNX embedding provider is owned by the ONNX engine plugin
# (engines/onnx/onnx_embedding_provider.{h,cpp} +
# engines/onnx/rac_onnx_embeddings_register.cpp). It compiles into
# rac_backend_onnx so the engine fully owns its embedding primitive.
# The RAG pipeline routes through rac_embeddings_service at runtime.

set(RAG_PIPELINE_HEADERS
    rag_backend.h
    rag_pipeline_graph.h
    rag_rerank.h
    vector_store_usearch.h
    rag_chunker.h
    bm25_index.h
)

add_library(rac_backend_rag OBJECT ${RAG_PIPELINE_SOURCES} ${RAG_PIPELINE_HEADERS})

target_include_directories(rac_backend_rag PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    # Walk up from src/features/rag/ to commons/, then into include/. Uses
    # CMAKE_CURRENT_SOURCE_DIR (not CMAKE_SOURCE_DIR) so the path is correct
    # whether commons is the top-level CMake project or pulled in via
    # add_subdirectory() from another project (e.g., the Web/WASM build).
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../include
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../include/rac/backends
    ${usearch_SOURCE_DIR}/include
)

if(Protobuf_FOUND AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/generated/proto/rag.pb.h")
    target_compile_definitions(rac_backend_rag PRIVATE RAC_HAVE_PROTOBUF=1)
    target_include_directories(rac_backend_rag PRIVATE
        # commons src/ root — rac_backend_rag is folded into rac_commons via
        # $<TARGET_OBJECTS>, so it shares commons-internal headers (e.g.
        # foundation/rac_proto_marshal_internal.h). Mirrors rac_commons' own src/ path.
        ${CMAKE_CURRENT_SOURCE_DIR}/../../../src
        ${CMAKE_CURRENT_SOURCE_DIR}/../../../src/generated/proto
        ${CMAKE_CURRENT_SOURCE_DIR}/../../../src/generated
        ${Protobuf_INCLUDE_DIRS}
    )
    if(TARGET protobuf::libprotobuf)
        target_link_libraries(rac_backend_rag PRIVATE protobuf::libprotobuf)
    elseif(Protobuf_LIBRARIES)
        target_link_libraries(rac_backend_rag PRIVATE ${Protobuf_LIBRARIES})
    endif()
    if(RAC_ABSL_LIBS)
        target_link_libraries(rac_backend_rag PRIVATE ${RAC_ABSL_LIBS})
    endif()
endif()

# nlohmann_json is used by RAG for config parsing.
# It's header-only (INTERFACE lib) so no link-time cost.
target_link_libraries(rac_backend_rag PUBLIC
    nlohmann_json::nlohmann_json
)

target_compile_definitions(rac_backend_rag PRIVATE RAC_RAG_BUILDING)

set_target_properties(rac_backend_rag PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

target_compile_options(rac_backend_rag PRIVATE
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wno-unused-parameter>
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wno-missing-field-initializers>
    $<$<CXX_COMPILER_ID:MSVC>:/wd4244;/wd4267;/wd4996>
)

target_compile_definitions(rac_backend_rag PRIVATE
    USEARCH_USE_FP16LIB=0
    USEARCH_USE_SIMSIMD=0
)

# Platform-specific configuration

if(RAC_PLATFORM_IOS)
    message(STATUS "Configuring RAG pipeline for iOS")
    target_link_libraries(rac_backend_rag PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
    )

elseif(RAC_PLATFORM_ANDROID)
    message(STATUS "Configuring RAG pipeline for Android")
    target_compile_definitions(rac_backend_rag PRIVATE ORT_API_VERSION=17)
    target_compile_options(rac_backend_rag PRIVATE -O3 -ffunction-sections -fdata-sections)

elseif(RAC_PLATFORM_MACOS)
    message(STATUS "Configuring RAG pipeline for macOS")
    target_link_libraries(rac_backend_rag PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
    )
endif()

# Summary

message(STATUS "RAG Pipeline Configuration:")
message(STATUS "  USearch: ${USEARCH_VERSION} (HNSW vector search)")
message(STATUS "  Architecture: Pipeline (calls LLM + Embeddings via vtables)")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")

# RAG has no dedicated Android JNI library. Kotlin uses the proto-byte
# `rac_rag_*_proto` surface, served by the main `librunanywhere_jni.so` via
# `racRag*Proto` methods in `runanywhere_commons_jni.cpp`.
