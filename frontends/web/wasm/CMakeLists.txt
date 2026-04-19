# WASM build for RunAnywhere v2 — invoked by `cmake --preset wasm-release`
# from the repo root. All engines compile in statically because Emscripten
# doesn't support dlopen.

if(NOT EMSCRIPTEN)
    message(STATUS "Skipping frontends/web/wasm — Emscripten toolchain not active")
    return()
endif()

add_executable(runanywhere_v2_wasm
    runanywhere_wasm_main.cpp
)

target_link_libraries(runanywhere_v2_wasm PRIVATE
    RunAnywhere::core
    llamacpp_engine
    sherpa_engine
    wakeword_engine
    ra_solution_voice_agent
    ra_solution_rag
)

# Emscripten link options: export every public C ABI symbol so JS can call
# them (otherwise emcc dead-strips unused externs), enable asyncify so
# `ra_pipeline_run` can `await` its callbacks from JavaScript, and produce
# ES modules. `target_link_options` is the modern CMake spelling and avoids
# the shell-quoting traps of LINK_FLAGS.
target_link_options(runanywhere_v2_wasm PRIVATE
    "-sMODULARIZE=1"
    "-sEXPORT_ES6=1"
    "-sEXPORT_NAME=createRunAnywhereModule"
    "-sASYNCIFY=1"
    "-sALLOW_MEMORY_GROWTH=1"
    "SHELL:-sEXPORTED_RUNTIME_METHODS=['ccall','cwrap','HEAPU8','lengthBytesUTF8','stringToUTF8']"
    "SHELL:-sEXPORTED_FUNCTIONS=['_ra_pipeline_create','_ra_pipeline_create_from_solution','_ra_pipeline_run','_ra_pipeline_cancel','_ra_pipeline_destroy','_ra_pipeline_set_event_callback','_ra_pipeline_set_completion_callback','_ra_pipeline_feed_audio','_ra_pipeline_inject_event','_ra_pipeline_validate','_ra_abi_version','_ra_plugin_api_version','_ra_status_str','_ra_build_info','_malloc','_free']"
)
