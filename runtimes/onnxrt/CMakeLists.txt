set(_rac_runtime_onnxrt_default ON)
if(DEFINED RAC_BACKEND_ONNX AND NOT RAC_BACKEND_ONNX)
    set(_rac_runtime_onnxrt_default OFF)
endif()
# EXISTS-gated disable under Emscripten: only force OFF when no vendored
# ONNX Runtime WASM static archive is available. Mirrors engines/onnx gate.
if(EMSCRIPTEN)
    set(_rac_onnxrt_wasm_dir
        "${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/third_party/onnxruntime-wasm")
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
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)

target_include_directories(rac_runtime_onnxrt PRIVATE
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/src
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
# callers. Keeping this granular lets us ship the CoreML EP where present and
# land CUDA / DirectML / NNAPI / QNN in follow-up rows without ABI churn.
if(APPLE)
    # The official iOS archive contains CoreML, but Sherpa's fully-static
    # macOS ONNX Runtime inventory may be CPU-only even though it includes the
    # provider-factory header. Probe the selected artifact itself so a header
    # cannot make us emit an undefined provider call into release consumers.
    get_target_property(_rac_onnxrt_location onnxruntime IMPORTED_LOCATION)
    if(_rac_onnxrt_location AND EXISTS "${_rac_onnxrt_location}" AND CMAKE_NM)
        execute_process(
            COMMAND "${CMAKE_NM}" -gU "${_rac_onnxrt_location}"
            RESULT_VARIABLE _rac_onnxrt_nm_result
            OUTPUT_VARIABLE _rac_onnxrt_symbols
            ERROR_QUIET
        )
        if(_rac_onnxrt_nm_result EQUAL 0 AND
           _rac_onnxrt_symbols MATCHES "_?OrtSessionOptionsAppendExecutionProvider_CoreML")
            target_compile_definitions(rac_runtime_onnxrt PRIVATE
                RAC_ONNXRT_EP_COREML_ENABLED)
            message(STATUS "ONNX Runtime CoreML EP: available in selected Apple artifact")
        else()
            message(STATUS "ONNX Runtime CoreML EP: unavailable in selected Apple artifact; CPU fallback only")
        endif()
        unset(_rac_onnxrt_symbols)
    else()
        message(STATUS "ONNX Runtime CoreML EP: artifact not inspectable; CPU fallback only")
    endif()
endif()
