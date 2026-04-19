# engines/llamacpp/ — L2 plugin wrapping the llama.cpp C API.
#
# Real integration: FetchContent pulls llama.cpp, compiles it, links the
# plugin against libllama. The plugin's llm_generate / embed_text
# function pointers run real inference against a GGUF model.

set(RA_LLAMACPP_TAG "b4393" CACHE STRING "llama.cpp git tag / ref")

include(FetchContent)
set(LLAMA_BUILD_TESTS     OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES  OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER    OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL            OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS     OFF CACHE BOOL "" FORCE)

# GPU backends — CPU-only is the portable default, and the tag we pin
# may not compile cleanly against newer SDK headers on every host. GPU
# acceleration is provided by the MetalRT plugin on Apple and by ONNX
# Runtime on other hosts; llama.cpp's internal Metal/CUDA backends are
# redundant for us.
set(GGML_METAL            OFF CACHE BOOL "" FORCE)
set(GGML_CUDA             OFF CACHE BOOL "" FORCE)
set(GGML_HIPBLAS          OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN           OFF CACHE BOOL "" FORCE)
set(GGML_SYCL             OFF CACHE BOOL "" FORCE)
set(GGML_BLAS             OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP           OFF CACHE BOOL "" FORCE)

# Quiet the third-party tree — it emits a lot of -W... we don't own.
set(GGML_NATIVE           ON  CACHE BOOL "" FORCE)

FetchContent_Declare(llamacpp
    GIT_REPOSITORY https://github.com/ggerganov/llama.cpp.git
    GIT_TAG        ${RA_LLAMACPP_TAG}
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(llamacpp)

ra_add_engine_plugin(llamacpp_engine
    SOURCES
        llamacpp_plugin.cpp
    DEPS
        llama
    ABI_VERSION 1
    OUTPUT_NAME runanywhere_llamacpp
)

message(STATUS "engines/llamacpp: linked against llama.cpp @ ${RA_LLAMACPP_TAG}")
