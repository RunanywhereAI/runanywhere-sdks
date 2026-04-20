# engines/whispercpp/ — whisper.cpp STT plugin.
#
# Mirror of main-branch commons/src/backends/whispercpp/. Real whisper.cpp
# link is gated behind RA_BUILD_WHISPERCPP=ON; when the flag is off (the
# default), the plugin still registers metadata so the router / Swift /
# Kotlin model catalog can reference the `whispercpp` framework without a
# runtime fallback path.

option(RA_BUILD_WHISPERCPP "Link the whisper.cpp library" OFF)

ra_add_engine_plugin(whispercpp_engine
    SOURCES whispercpp_plugin.cpp
    ABI_VERSION 1
    OUTPUT_NAME runanywhere_whispercpp
)

if(RA_BUILD_WHISPERCPP)
    # When the flag is on, FetchContent or vcpkg is expected to provide
    # `whisper` target; link it here.
    find_package(whisper QUIET)
    if(whisper_FOUND)
        target_compile_definitions(whispercpp_engine PRIVATE RA_HAVE_WHISPERCPP=1)
        target_link_libraries(whispercpp_engine PRIVATE whisper)
    else()
        message(WARNING
            "engines/whispercpp: RA_BUILD_WHISPERCPP=ON but whisper not found; "
            "plugin will register metadata but stt_create returns "
            "RA_ERR_CAPABILITY_UNSUPPORTED until whisper.cpp is linked.")
    endif()
endif()

message(STATUS "engines/whispercpp: built (whisper.cpp linked: ${RA_BUILD_WHISPERCPP})")
