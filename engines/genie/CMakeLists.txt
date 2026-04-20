# engines/genie/ — Android-only Qualcomm Genie LLM plugin (stub).
option(RA_BUILD_GENIE "Link the Qualcomm Genie SDK (Android only)" OFF)

ra_add_engine_plugin(genie_engine
    SOURCES genie_plugin.cpp
    ABI_VERSION 1
    OUTPUT_NAME runanywhere_genie
)

if(ANDROID AND RA_BUILD_GENIE)
    target_compile_definitions(genie_engine PRIVATE RA_HAVE_GENIE=1)
endif()

message(STATUS "engines/genie: built (real Genie linked: ${RA_BUILD_GENIE})")
