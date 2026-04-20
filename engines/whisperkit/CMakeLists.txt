# engines/whisperkit/ — Apple-only WhisperKit STT plugin (stub).
#
# Real integration: link the WhisperKit Swift package via an Objective-C++
# shim and route stt_create through `WhisperKit.transcribeAsync`.
# Activate with -DRA_BUILD_WHISPERKIT=ON on Apple platforms.

option(RA_BUILD_WHISPERKIT "Link the WhisperKit Swift package (Apple only)" OFF)

if(NOT APPLE AND RA_BUILD_WHISPERKIT)
    message(WARNING "engines/whisperkit: RA_BUILD_WHISPERKIT requires Apple host; ignoring")
    set(RA_BUILD_WHISPERKIT OFF CACHE BOOL "" FORCE)
endif()

ra_add_engine_plugin(whisperkit_engine
    SOURCES whisperkit_plugin.cpp
    ABI_VERSION 1
    OUTPUT_NAME runanywhere_whisperkit
)

if(APPLE AND RA_BUILD_WHISPERKIT)
    target_compile_definitions(whisperkit_engine PRIVATE RA_HAVE_WHISPERKIT=1)
    target_link_libraries(whisperkit_engine PRIVATE
        "-framework Foundation" "-framework CoreML")
endif()

message(STATUS "engines/whisperkit: built (real WhisperKit linked: ${RA_BUILD_WHISPERKIT})")
