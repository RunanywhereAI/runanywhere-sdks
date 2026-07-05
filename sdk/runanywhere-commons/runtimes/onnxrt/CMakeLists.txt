set(_rac_runtime_onnxrt_default ON)
if(DEFINED RAC_BACKEND_ONNX AND NOT RAC_BACKEND_ONNX)
    set(_rac_runtime_onnxrt_default OFF)
endif()
# EXISTS-gated disable under Emscripten: only force OFF when no vendored
# ONNX Runtime WASM static archive is available. Mirrors engines/onnx gate.
if(EMSCRIPTEN)
    set(_rac_onnxrt_wasm_dir
        "${CMAKE_SOURCE_DIR}/third_party/onnxruntime-wasm")
    if(NOT EXISTS "${_rac_onnxrt_wasm_dir}/lib/libonnxruntime.a")
        set(_rac_runtime_onnxrt_default OFF)
    endif()
endif()

option(RAC_RUNTIME_ONNXRT "Build the ONNX Runtime L1 runtime adapter" ${_rac_runtime_onnxrt_default})
if(NOT RAC_RUNTIME_ONNXRT)
    return()
endif()

include(FetchONNXRuntime)

add_library(rac_runtime_onnxrt STATIC
    rac_runtime_onnxrt.cpp
)

set_target_properties(rac_runtime_onnxrt PROPERTIES
    CXX_STANDARD          20
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
)

target_include_directories(rac_runtime_onnxrt PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)

target_include_directories(rac_runtime_onnxrt PRIVATE
    ${CMAKE_SOURCE_DIR}/src
)

target_link_libraries(rac_runtime_onnxrt PUBLIC
    onnxruntime
)

target_compile_definitions(rac_runtime_onnxrt PUBLIC RAC_HAS_ONNX)

if(ANDROID OR RAC_PLATFORM_ANDROID)
    target_compile_definitions(rac_runtime_onnxrt PUBLIC ORT_API_VERSION=17)
endif()

# Execution-provider compile-time switches. Enable an EP only when
# the vendored ORT build actually ships its append function + provider-factory
# header; otherwise the EP stays a stub that returns CAPABILITY_UNSUPPORTED to
# callers. Keeping this granular lets us ship the CoreML EP on Apple today and
# land CUDA / DirectML / NNAPI / QNN in follow-up rows without ABI churn.
if(APPLE)
    # `coreml_provider_factory.h` + `OrtSessionOptionsAppendExecutionProvider_
    # CoreML` are in every ORT Apple binary we ship via FetchONNXRuntime.
    target_compile_definitions(rac_runtime_onnxrt PRIVATE RAC_ONNXRT_EP_COREML_ENABLED)
endif()
