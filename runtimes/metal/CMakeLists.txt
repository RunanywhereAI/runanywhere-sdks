if(NOT APPLE)
    return()
endif()

option(RAC_RUNTIME_METAL "Build the Apple Metal L1 runtime adapter" ON)
if(NOT RAC_RUNTIME_METAL)
    return()
endif()

add_library(rac_runtime_metal STATIC
    rac_runtime_metal.mm
)

set_target_properties(rac_runtime_metal PROPERTIES
    CXX_STANDARD          17
    CXX_STANDARD_REQUIRED ON
    POSITION_INDEPENDENT_CODE ON
)

target_include_directories(rac_runtime_metal PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)

target_link_libraries(rac_runtime_metal PUBLIC
    "-framework Foundation"
    "-framework Metal"
)

set_property(GLOBAL APPEND PROPERTY RAC_REGISTERED_RUNTIMES metal)
set_property(GLOBAL APPEND PROPERTY RAC_RUNTIME_metal_DEVICE_CLASS GPU)
