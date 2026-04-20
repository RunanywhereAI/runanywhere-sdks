# engines/metalrt/ — Apple-only MetalRT runtime plugin.
#
# MetalRT is an Apple closed-source SDK. When `RA_METALRT_SDK_DIR` is
# set at configure time, we compile against it; otherwise the Swift-
# side callback bridge (`ra_metalrt_set_callbacks`) is the only path.

option(RA_BUILD_METALRT "Link the MetalRT runtime (Apple only)" OFF)
set(RA_METALRT_SDK_DIR "" CACHE PATH "Path to MetalRT SDK checkout (closed-source)")

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
    if(RA_METALRT_SDK_DIR)
        target_include_directories(metalrt_engine PRIVATE "${RA_METALRT_SDK_DIR}/include")
        target_link_directories(metalrt_engine PRIVATE   "${RA_METALRT_SDK_DIR}/lib")
        target_link_libraries(metalrt_engine PRIVATE MetalRT)
        target_compile_definitions(metalrt_engine PRIVATE RA_METALRT_SDK_AVAILABLE=1)
    endif()
endif()

message(STATUS "engines/metalrt: built (MetalRT linked: ${RA_BUILD_METALRT}, SDK dir: '${RA_METALRT_SDK_DIR}')")
