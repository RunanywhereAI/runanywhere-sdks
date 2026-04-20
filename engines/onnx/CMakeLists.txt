# engines/onnx/ — ONNX Runtime plugin (LLM + embed + STT).
#
# This is a metadata-only stub today. To activate real inference set
# RA_BUILD_ONNX_RUNTIME=ON and provide a libonnxruntime build via
# RA_ONNXRUNTIME_DIR; the plugin will FetchContent ORT and rebuild.

option(RA_BUILD_ONNX_RUNTIME "Link the ONNX Runtime engine plugin against libonnxruntime" OFF)

ra_add_engine_plugin(onnx_engine
    SOURCES
        onnx_plugin.cpp
    ABI_VERSION 1
    OUTPUT_NAME runanywhere_onnx
)

if(RA_BUILD_ONNX_RUNTIME)
    if(NOT RA_ONNXRUNTIME_DIR)
        message(FATAL_ERROR
            "engines/onnx: RA_BUILD_ONNX_RUNTIME=ON requires RA_ONNXRUNTIME_DIR "
            "pointing at a pre-built ONNX Runtime install with include/ + lib/.")
    endif()
    target_include_directories(onnx_engine PRIVATE ${RA_ONNXRUNTIME_DIR}/include)
    find_library(RA_ONNXRUNTIME_LIB NAMES onnxruntime PATHS ${RA_ONNXRUNTIME_DIR}/lib REQUIRED)
    target_link_libraries(onnx_engine PRIVATE ${RA_ONNXRUNTIME_LIB})
    target_compile_definitions(onnx_engine PRIVATE RA_HAVE_ONNXRUNTIME=1)
endif()

message(STATUS "engines/onnx: built (real ORT linked: ${RA_BUILD_ONNX_RUNTIME})")
