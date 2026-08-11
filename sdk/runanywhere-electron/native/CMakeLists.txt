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

    if(WIN32)
        # node-gyp-provided dev files (headers + node.lib). Overridable; defaults to
        # the node-gyp cache for the Node version on this machine. A real package
        # build resolves these via cmake-js (CMAKE_JS_INC / CMAKE_JS_LIB) instead.
        set(RAC_NODE_DEV_DIR "$ENV{LOCALAPPDATA}/node-gyp/Cache/24.15.0"
            CACHE PATH "node-gyp dev files dir (contains include/node + <arch>/node.lib)")
        # node-gyp keys the import library by target arch, so an ARM64 addon must
        # link arm64/node.lib — x64/node.lib fails the link with LNK1112.
        if(CMAKE_SYSTEM_PROCESSOR MATCHES "^([Aa][Rr][Mm]64|aarch64|AARCH64)$" OR
           CMAKE_GENERATOR_PLATFORM MATCHES "^([Aa][Rr][Mm]64)$")
            set(_ra_node_arch "arm64")
        else()
            set(_ra_node_arch "x64")
        endif()
        set(RAC_NODE_LIB "${RAC_NODE_DEV_DIR}/${_ra_node_arch}/node.lib"
            CACHE FILEPATH "Windows node import library (node.lib)")
        if(NOT EXISTS "${RAC_NODE_LIB}")
            message(FATAL_ERROR
                "runanywhere-electron: node.lib not found at ${RAC_NODE_LIB} — run "
                "`npx node-gyp install` or set -DRAC_NODE_DEV_DIR=<node-gyp cache ver dir>")
        endif()
        set(_ra_addon_platform_srcs
            win32_platform_adapter.cpp
            win_delay_load_hook.cc)  # vendored from cmake-js: redirect node imports to the host exe
    else()
        # POSIX: napi_* symbols resolve from the host executable (node/electron) at
        # load time — undefined symbols in a shared lib are fine on Linux; macOS
        # would need -undefined dynamic_lookup. Headers come from node-api-headers.
        set(_ra_addon_platform_srcs posix_platform_adapter.cpp)
    endif()

    add_library(runanywhere_native SHARED
        addon.cpp proto_bridge.cpp model_bridge.cpp llm_bridge.cpp tool_bridge.cpp vlm_bridge.cpp speech_bridge.cpp voice_bridge.cpp data_bridge.cpp lora_bridge.cpp download_bridge.cpp logging_bridge.cpp
        ${_ra_addon_platform_srcs})
    set_target_properties(runanywhere_native PROPERTIES PREFIX "" SUFFIX ".node")

    target_include_directories(runanywhere_native PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
        "${_ra_napi}/node-addon-api"
        "${_ra_napi}/node-api-headers/include")
    target_compile_definitions(runanywhere_native PRIVATE
        NAPI_VERSION=8 NODE_ADDON_API_DISABLE_DEPRECATED BUILDING_NODE_EXTENSION)
    target_compile_features(runanywhere_native PRIVATE cxx_std_20)
    target_link_libraries(runanywhere_native PRIVATE rac_commons)
    if(WIN32)
        target_include_directories(runanywhere_native PRIVATE "${RAC_NODE_DEV_DIR}/include/node")
        target_link_libraries(runanywhere_native PRIVATE Crypt32 "${RAC_NODE_LIB}")
    elseif(APPLE)
        target_link_options(runanywhere_native PRIVATE "-Wl,-undefined,dynamic_lookup")
        set_target_properties(runanywhere_native PROPERTIES
            BUILD_RPATH "@loader_path" INSTALL_RPATH "@loader_path")
    else()
        # Resolve sidecar .so files (onnxruntime, sherpa) beside the .node when it
        # is bundled into prebuilds/; the build-tree absolute RUNPATH still applies.
        set_target_properties(runanywhere_native PROPERTIES
            BUILD_RPATH "$ORIGIN" INSTALL_RPATH "$ORIGIN")
    endif()

    # Link whichever engine backends this build enabled, and tell addon.cpp which
    # are present via RAC_HAVE_BACKEND_<X>. Default CPU build provides llamacpp +
    # onnx + sherpa. QHexRT / MLX / CoreML / cloud self-link when their upstream
    # RAC_BACKEND_* flag builds the target — no wrapper source change required.
    # RAC_HAVE_BACKEND_QHEXRT only says the target exists: on Windows x64 (and any
    # non-ARM64 host) qhexrt links as the not-routable shell, and even on ARM64 it
    # is routable only with a win-arm64 prebuilt staged. Actually RUNNING a model
    # additionally needs the QAIRT DLLs + the v81 skel and its .cat staged flat
    # beside the addon — see engines/qhexrt/CMakeLists.txt.
    set(_ra_backends llamacpp onnx sherpa qhexrt mlx coreml cloud)
    set(_ra_linked_backends "")
    foreach(_ra_b IN LISTS _ra_backends)
        if(TARGET rac_backend_${_ra_b})
            target_link_libraries(runanywhere_native PRIVATE rac_backend_${_ra_b})
            string(TOUPPER "${_ra_b}" _ra_bU)
            target_compile_definitions(runanywhere_native PRIVATE RAC_HAVE_BACKEND_${_ra_bU})
            list(APPEND _ra_linked_backends ${_ra_b})
        endif()
    endforeach()
    message(STATUS "runanywhere-electron: engine backends -> ${_ra_linked_backends}")

    # RAG. Commons only defines the rac_rag_*_proto C ABI when RAC_BACKEND_RAG is
    # on, so without this the addon would fail to LINK (not merely lose a feature)
    # on any preset that turns RAG off — which windows-arm64-release does.
    if(RAC_BACKEND_RAG)
        target_compile_definitions(runanywhere_native PRIVATE RAC_ELECTRON_HAVE_RAG)
    else()
        message(STATUS "runanywhere-electron: RAG OFF — the rag* exports report FEATURE_NOT_AVAILABLE")
    endif()

    # Desktop control plane (telemetry + auth). When the desktop adapter is built
    # into commons (RAC_DESKTOP_ADAPTER=ON), it carries the libcurl HTTP transport
    # that auth/model-assignments/telemetry POST through; commons links CURL::libcurl
    # PUBLIC, so our link on rac_commons inherits it. Tell addon.cpp the
    # rac_desktop_* + two-phase-init surface is available.
    if(RAC_DESKTOP_ADAPTER)
        target_compile_definitions(runanywhere_native PRIVATE RAC_ELECTRON_HAVE_DESKTOP)
        message(STATUS "runanywhere-electron: desktop control plane enabled (telemetry + auth)")
    else()
        message(STATUS "runanywhere-electron: desktop control plane OFF "
                       "(pass -DRAC_DESKTOP_ADAPTER=ON to enable telemetry/auth)")
    endif()

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
