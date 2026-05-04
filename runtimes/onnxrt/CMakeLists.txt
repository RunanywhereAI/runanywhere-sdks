set(_rac_runtime_onnxrt_default ON)
if(DEFINED RAC_BACKEND_ONNX AND NOT RAC_BACKEND_ONNX)
    set(_rac_runtime_onnxrt_default OFF)
endif()
if(EMSCRIPTEN)
    set(_rac_runtime_onnxrt_default OFF)
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

set_property(GLOBAL APPEND PROPERTY RAC_REGISTERED_RUNTIMES onnxrt)
set_property(GLOBAL APPEND PROPERTY RAC_RUNTIME_onnxrt_DEVICE_CLASS CPU)
