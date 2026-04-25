if(NOT APPLE)
    return()
endif()

option(RAC_RUNTIME_COREML "Build the Apple CoreML L1 runtime adapter" ON)
if(NOT RAC_RUNTIME_COREML)
    return()
endif()

add_library(rac_runtime_coreml STATIC
    rac_runtime_coreml.mm
)

set_target_properties(rac_runtime_coreml PROPERTIES
    CXX_STANDARD          17
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
)

target_include_directories(rac_runtime_coreml PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)

target_link_libraries(rac_runtime_coreml PUBLIC
    "-framework Foundation"
    "-framework CoreML"
)

set_property(GLOBAL APPEND PROPERTY RAC_REGISTERED_RUNTIMES coreml)
set_property(GLOBAL APPEND PROPERTY RAC_RUNTIME_coreml_DEVICE_CLASS NPU)
