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

# Emscripten link options: export the C ABI symbols so JS can call them,
# enable asyncify so ra_pipeline_run can await callbacks, and produce ES modules.
set_target_properties(runanywhere_v2_wasm PROPERTIES
    LINK_FLAGS "\
        -sMODULARIZE=1 \
        -sEXPORT_ES6=1 \
        -sEXPORT_NAME=createRunAnywhereModule \
        -sASYNCIFY=1 \
        -sALLOW_MEMORY_GROWTH=1 \
        -sEXPORTED_RUNTIME_METHODS=['ccall','cwrap','HEAPU8','lengthBytesUTF8','stringToUTF8'] \
        -sEXPORTED_FUNCTIONS=['_ra_pipeline_create','_ra_pipeline_run','_ra_pipeline_cancel','_ra_pipeline_destroy','_ra_abi_version','_malloc','_free']"
)
