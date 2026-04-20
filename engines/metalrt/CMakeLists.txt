# engines/metalrt/ — Apple-only MetalRT runtime plugin (stub).
option(RA_BUILD_METALRT "Link the MetalRT runtime (Apple only)" OFF)

if(NOT APPLE AND RA_BUILD_METALRT)
    set(RA_BUILD_METALRT OFF CACHE BOOL "" FORCE)
endif()

ra_add_engine_plugin(metalrt_engine
    SOURCES metalrt_plugin.cpp
    ABI_VERSION 1
    OUTPUT_NAME runanywhere_metalrt
)

if(APPLE AND RA_BUILD_METALRT)
    target_compile_definitions(metalrt_engine PRIVATE RA_HAVE_METALRT=1)
    target_link_libraries(metalrt_engine PRIVATE
        "-framework Metal" "-framework MetalPerformanceShaders")
endif()

message(STATUS "engines/metalrt: built (real MetalRT linked: ${RA_BUILD_METALRT})")
