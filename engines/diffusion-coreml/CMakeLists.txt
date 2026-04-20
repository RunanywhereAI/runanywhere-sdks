# engines/diffusion-coreml/ — Apple StableDiffusion plugin (stub).
option(RA_BUILD_DIFFUSION_COREML "Link the Apple StableDiffusion Swift package" OFF)

ra_add_engine_plugin(diffusion_coreml_engine
    SOURCES diffusion_plugin.cpp
    ABI_VERSION 1
    OUTPUT_NAME runanywhere_diffusion_coreml
)

target_link_libraries(diffusion_coreml_engine PRIVATE ra_core_abi_ext)

if(APPLE AND RA_BUILD_DIFFUSION_COREML)
    target_compile_definitions(diffusion_coreml_engine PRIVATE RA_HAVE_DIFFUSION_COREML=1)
    target_link_libraries(diffusion_coreml_engine PRIVATE
        "-framework CoreML" "-framework Accelerate")
endif()

message(STATUS "engines/diffusion-coreml: built (real linker: ${RA_BUILD_DIFFUSION_COREML})")
