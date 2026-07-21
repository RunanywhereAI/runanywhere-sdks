# runanywhere-electron — native layer.
#
# Two root-project targets, each gated by its own option (both OFF by default so
# normal builds are unaffected). Built as ROOT targets so CMake's dependency graph
# supplies the full transitive static-lib set (the set the M0 harness first proved
# links cleanly on MSVC — rac_commons + rac_backend_llamacpp pull llama/ggml/
# protobuf/libarchive/zlib/... transitively):
#   - electron_m0_harness (RAC_BUILD_ELECTRON_HARNESS): standalone MSVC exe, the M0
#     gate proving commons + llama.cpp RUN on Windows via the Win32 adapter.
#   - runanywhere_native  (RAC_BUILD_ELECTRON_ADDON): the N-API .node addon.

# On MSVC, libarchive/find_package leak the bundled zlib/bz2 statics into the link
# line as bare names, resolved via a directory-scoped link_directories in the
# commons subdir that does NOT reach this sibling subdir. Re-add it for our targets.
set(_ra_bundled_dir "${CMAKE_BINARY_DIR}/_bundled_libs")

# ---------------------------------------------------------------------------
# M0 harness
# ---------------------------------------------------------------------------
if(RAC_BUILD_ELECTRON_HARNESS)
    add_executable(electron_m0_harness m0_harness.cpp win32_platform_adapter.cpp)
    target_include_directories(electron_m0_harness PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include)
    target_compile_features(electron_m0_harness PRIVATE cxx_std_20)
    target_link_libraries(electron_m0_harness PRIVATE rac_commons rac_backend_llamacpp Crypt32)
    if(MSVC)
        target_link_directories(electron_m0_harness PRIVATE "${_ra_bundled_dir}")
        target_compile_definitions(electron_m0_harness PRIVATE
            _CRT_SECURE_NO_WARNINGS NOMINMAX WIN32_LEAN_AND_MEAN)
        target_compile_options(electron_m0_harness PRIVATE /EHsc /Zc:__cplusplus /utf-8)
    endif()
    message(STATUS "runanywhere-electron: M0 harness 'electron_m0_harness' enabled")
endif()

# ---------------------------------------------------------------------------
# N-API .node addon
# ---------------------------------------------------------------------------
if(RAC_BUILD_ELECTRON_ADDON)
    set(_ra_napi "${CMAKE_CURRENT_SOURCE_DIR}/node_modules")
    if(NOT EXISTS "${_ra_napi}/node-addon-api/napi.h")
        message(FATAL_ERROR
            "runanywhere-electron: node deps missing — run `npm install` in "
            "sdk/runanywhere-electron/native (node-addon-api + node-api-headers)")
    endif()

    # node-gyp-provided dev files (headers + node.lib). Overridable; defaults to
    # the node-gyp cache for the Node version on this machine. A real package
    # build resolves these via cmake-js (CMAKE_JS_INC / CMAKE_JS_LIB) instead.
    set(RAC_NODE_DEV_DIR "$ENV{LOCALAPPDATA}/node-gyp/Cache/24.15.0"
        CACHE PATH "node-gyp dev files dir (contains include/node + <arch>/node.lib)")
    set(RAC_NODE_LIB "${RAC_NODE_DEV_DIR}/x64/node.lib"
        CACHE FILEPATH "Windows node import library (node.lib)")
    if(NOT EXISTS "${RAC_NODE_LIB}")
        message(FATAL_ERROR
            "runanywhere-electron: node.lib not found at ${RAC_NODE_LIB} — run "
            "`npx node-gyp install` or set -DRAC_NODE_DEV_DIR=<node-gyp cache ver dir>")
    endif()

    add_library(runanywhere_native SHARED
        addon.cpp
        win32_platform_adapter.cpp
        win_delay_load_hook.cc)  # vendored from cmake-js: redirect node imports to the host exe
    set_target_properties(runanywhere_native PROPERTIES PREFIX "" SUFFIX ".node")

    target_include_directories(runanywhere_native PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
        "${RAC_NODE_DEV_DIR}/include/node"
        "${_ra_napi}/node-addon-api"
        "${_ra_napi}/node-api-headers/include")
    target_compile_definitions(runanywhere_native PRIVATE
        NAPI_VERSION=8 NODE_ADDON_API_DISABLE_DEPRECATED BUILDING_NODE_EXTENSION)
    target_compile_features(runanywhere_native PRIVATE cxx_std_20)
    target_link_libraries(runanywhere_native PRIVATE
        rac_commons rac_backend_llamacpp rac_backend_onnx rac_backend_sherpa Crypt32 "${RAC_NODE_LIB}")

    if(MSVC)
        target_link_directories(runanywhere_native PRIVATE "${_ra_bundled_dir}")
        target_compile_definitions(runanywhere_native PRIVATE
            _CRT_SECURE_NO_WARNINGS NOMINMAX WIN32_LEAN_AND_MEAN)
        target_compile_options(runanywhere_native PRIVATE /EHsc /Zc:__cplusplus /utf-8 /bigobj)
        # napi_* symbols are exported by the host executable (node.exe / electron.exe),
        # not a DLL. Delay-load them; win_delay_load_hook.cc redirects the import to
        # the running host at first call (works for both Node and Electron).
        target_link_options(runanywhere_native PRIVATE /DELAYLOAD:node.exe)
        target_link_libraries(runanywhere_native PRIVATE delayimp)
    endif()
    message(STATUS "runanywhere-electron: N-API addon 'runanywhere_native' enabled")
endif()
