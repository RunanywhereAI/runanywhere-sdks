set(_rac_runtime_onnxrt_default ON)
if(DEFINED RAC_BACKEND_ONNX AND NOT RAC_BACKEND_ONNX)
    set(_rac_runtime_onnxrt_default OFF)
endif()
# EXISTS-gated disable under Emscripten: only force OFF when no vendored
# ONNX Runtime WASM static archive is available. Mirrors engines/onnx gate.
if(EMSCRIPTEN)
    if(DEFINED RAC_ONNX_WASM_RUNTIME_DIR AND NOT RAC_ONNX_WASM_RUNTIME_DIR STREQUAL "")
        set(_rac_onnxrt_wasm_dir "${RAC_ONNX_WASM_RUNTIME_DIR}")
    else()
        set(_rac_onnxrt_wasm_dir
            "${RAC_ROOT_DIR}/core/third_party/onnxruntime-wasm")
    endif()
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
    ${RAC_ROOT_DIR}/core/include
)

target_include_directories(rac_runtime_onnxrt PRIVATE
    ${RAC_ROOT_DIR}/core/src
)

target_link_libraries(rac_runtime_onnxrt PUBLIC
    onnxruntime
    # The onnxrt registrar (RAC_STATIC_RUNTIME_REGISTER) calls
    # rac_runtime_register / rac_runtime_get_by_id, which are defined in
    # rac_commons. Declare that dependency so every consumer links rac_commons
    # AFTER this archive; GNU ld's strict left-to-right static resolution
    # otherwise leaves those symbols undefined when a target pulls onnxrt only
    # transitively (e.g. the rcli-linux release link of test_plugin_entry_onnx).
    rac_commons
)

# These C ABI symbols live in this static archive, which is linked into the
# runanywhere_onnx plugin DLL — not rac_commons.dll. Linking shared commons
# injects RAC_USING_SHARED, so RAC_API becomes dllimport and MSVC rejects
# defining those functions here (C2491). RAC_PLUGIN_API is dllexport only
# when RAC_BUILDING_PLUGIN is set, matching rac_plugin_entry.h.
if(WIN32 AND RAC_BUILD_SHARED)
    target_compile_definitions(rac_runtime_onnxrt PRIVATE RAC_BUILDING_PLUGIN=1)
endif()

target_compile_definitions(rac_runtime_onnxrt PUBLIC RAC_HAS_ONNX)

if(ANDROID OR RAC_PLATFORM_ANDROID)
    target_compile_definitions(rac_runtime_onnxrt PUBLIC ORT_API_VERSION=17)
endif()

# Execution-provider compile-time switches. Enable an EP only when
# the vendored ORT build actually ships its append function + provider-factory
# header; otherwise the EP stays a stub that returns CAPABILITY_UNSUPPORTED to
# callers. Keeping this granular lets us ship the CoreML EP where present and
# land CUDA / DirectML / NNAPI / QNN in follow-up rows without ABI churn.
#
# IMPORTANT: never define RAC_ONNXRT_EP_<NAME> as a compile macro — those
# identifiers are enum values in rac_onnxrt_runtime_ep.h. Use *_ENABLED flags
# (see RAC_ONNXRT_EP_COREML_ENABLED / RAC_ONNXRT_EP_WEBGPU_ENABLED).
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

# WebGPU EP (Emscripten): enable when the selected ORT archive contains the EP
# (onnxruntime-wasm-webgpu) or when the wasm twin flag is set. COMPILE_DEFS on
# the final .js/.wasm executable do NOT propagate into this static library —
# the define must land here so probe_webgpu_ep() is not compiled as a stub.
if(EMSCRIPTEN)
    set(_rac_onnxrt_webgpu_ep OFF)
    if(RAC_WASM_ONNX_WEBGPU)
        set(_rac_onnxrt_webgpu_ep ON)
    else()
        get_target_property(_rac_onnxrt_wg_location onnxruntime IMPORTED_LOCATION)
        if(_rac_onnxrt_wg_location AND EXISTS "${_rac_onnxrt_wg_location}" AND CMAKE_NM)
            execute_process(
                COMMAND "${CMAKE_NM}" -gU "${_rac_onnxrt_wg_location}"
                RESULT_VARIABLE _rac_onnxrt_wg_nm_result
                OUTPUT_VARIABLE _rac_onnxrt_wg_symbols
                ERROR_QUIET
            )
            if(_rac_onnxrt_wg_nm_result EQUAL 0 AND
               _rac_onnxrt_wg_symbols MATCHES "WebGpuExecutionProvider")
                set(_rac_onnxrt_webgpu_ep ON)
            endif()
            unset(_rac_onnxrt_wg_symbols)
        endif()
    endif()
    if(_rac_onnxrt_webgpu_ep)
        target_compile_definitions(rac_runtime_onnxrt PRIVATE
            RAC_ONNXRT_EP_WEBGPU_ENABLED)
        message(STATUS "ONNX Runtime WebGPU EP: enabled for Emscripten artifact")
    else()
        message(STATUS "ONNX Runtime WebGPU EP: unavailable in selected artifact; CPU fallback only")
    endif()
endif()
