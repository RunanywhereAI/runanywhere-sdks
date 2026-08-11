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
    # When commons is a shared library, rac_types.h needs RAC_USING_SHARED so
    # Windows dllimports the C ABI (and Apple/ELF keep a single shared contract).
    # rac_commons INTERFACE already propagates this; keep an explicit PRIVATE
    # define so the addon stays correct even if link order/interface props change.
    if(RAC_BUILD_SHARED)
        target_compile_definitions(runanywhere_native PRIVATE RAC_USING_SHARED=1)
    endif()
    if(WIN32)
        target_include_directories(runanywhere_native PRIVATE "${RAC_NODE_DEV_DIR}/include/node")
        target_link_libraries(runanywhere_native PRIVATE Crypt32 "${RAC_NODE_LIB}")
    elseif(APPLE)
        target_link_options(runanywhere_native PRIVATE "-Wl,-undefined,dynamic_lookup")
        # APPEND @loader_path so shared-commons build-tree absolute RPATHs remain.
        set_property(TARGET runanywhere_native APPEND PROPERTY BUILD_RPATH "@loader_path")
        set_target_properties(runanywhere_native PROPERTIES INSTALL_RPATH "@loader_path")
    else()
        # Resolve sidecar .so files (onnxruntime, sherpa, librac_commons) beside
        # the .node when bundled into prebuilds/; APPEND keeps build-tree paths.
        set_property(TARGET runanywhere_native APPEND PROPERTY BUILD_RPATH "$ORIGIN")
        set_target_properties(runanywhere_native PROPERTIES INSTALL_RPATH "$ORIGIN")
    endif()

    # Dual packaging path:
    #   FAT (default)  — statically link every built rac_backend_* into the .node
    #                    and tell addon.cpp via RAC_HAVE_BACKEND_<X> (today's CI
    #                    windows-release / macos-release lanes).
    #   THIN           — link only rac_commons (+ N-API); backends arrive at runtime
    #                    through loadPlugin / RUNANYWHERE_PLUGIN_PATHS.
    #                    Prefer cmake presets `electron-macos` / `electron-windows`.
    #
    # Thin mode is opt-in via -DRAC_ELECTRON_THIN_ADDON=ON, or automatic when the
    # enclosing build already chose dynamic plugins (RAC_STATIC_PLUGINS=OFF). The
    # option lives here (not the root CMakeLists) so additive Electron presets can
    # set it without fighting fat CI overrides.
    option(RAC_ELECTRON_THIN_ADDON
           "Build runanywhere_native without statically linked backends (runtime plugin load)"
           OFF)
    if(RAC_ELECTRON_THIN_ADDON OR NOT RAC_STATIC_PLUGINS)
        set(_ra_electron_thin_addon ON)
    else()
        set(_ra_electron_thin_addon OFF)
    endif()

    if(_ra_electron_thin_addon)
        target_compile_definitions(runanywhere_native PRIVATE RAC_ELECTRON_THIN_ADDON=1)
        message(STATUS "runanywhere-electron: THIN addon — rac_commons only; "
                       "backends via rac_registry_load_plugin / loadPlugin()")
    else()
        # Link whichever engine backends this build enabled, and tell addon.cpp
        # which are present via RAC_HAVE_BACKEND_<X>. Default CPU build provides
        # llamacpp + onnx + sherpa. QHexRT / MLX / NeuRT / cloud self-link when
        # their upstream RAC_BACKEND_* flag builds the target.
        # RAC_HAVE_BACKEND_QHEXRT only says the target exists: on Windows x64
        # (and any non-ARM64 host) qhexrt links as the not-routable shell, and
        # even on ARM64 it is routable only with a win-arm64 prebuilt staged.
        # Actually RUNNING a model additionally needs the QAIRT DLLs + the v81
        # skel and its .cat staged flat beside the addon — see
        # engines/qhexrt/CMakeLists.txt.
        # Note: the real Apple Neural Engine target is rac_backend_neurt (not
        # "coreml"); the old list never defined RAC_HAVE_BACKEND_NEURT.
        set(_ra_backends llamacpp onnx sherpa qhexrt mlx neurt cloud)
        set(_ra_linked_backends "")
        foreach(_ra_b IN LISTS _ra_backends)
            if(TARGET rac_backend_${_ra_b})
                target_link_libraries(runanywhere_native PRIVATE rac_backend_${_ra_b})
                string(TOUPPER "${_ra_b}" _ra_bU)
                target_compile_definitions(runanywhere_native PRIVATE RAC_HAVE_BACKEND_${_ra_bU})
                list(APPEND _ra_linked_backends ${_ra_b})
            endif()
        endforeach()
        message(STATUS "runanywhere-electron: FAT addon — engine backends -> ${_ra_linked_backends}")
    endif()

    # RAG. Commons only defines the rac_rag_*_proto C ABI when RAC_BACKEND_RAG is
    # on, so without this the addon would fail to LINK (not merely lose a feature)
    # on any preset that turns RAG off — which windows-arm64-release does.
    if(RAC_BACKEND_RAG)
        target_compile_definitions(runanywhere_native PRIVATE RAC_ELECTRON_HAVE_RAG)
    else()
        message(STATUS "runanywhere-electron: RAG OFF — the rag* exports report FEATURE_NOT_AVAILABLE")
    endif()

    # Desktop HTTP transport + control plane. When the desktop adapter is built
    # into commons (RAC_DESKTOP_ADAPTER=ON), it carries the libcurl HTTP transport
    # that model downloads / auth / model-assignments / telemetry POST through;
    # commons links CURL::libcurl PUBLIC, so our link on rac_commons inherits it.
    # Tell addon.cpp the rac_desktop_* + two-phase-init surface is available.
    # Electron adapters leave platform_adapter.http_download NULL — downloads use
    # rac_desktop_http_transport_register() at initialize(), not that slot.
    if(RAC_DESKTOP_ADAPTER)
        target_compile_definitions(runanywhere_native PRIVATE RAC_ELECTRON_HAVE_DESKTOP)
        message(STATUS "runanywhere-electron: desktop HTTP transport + control plane enabled "
                       "(libcurl downloads / telemetry / auth)")
    else()
        message(STATUS "runanywhere-electron: desktop HTTP transport OFF "
                       "(pass -DRAC_DESKTOP_ADAPTER=ON — required for model downloads)")
    endif()

    if(MSVC)
        target_link_directories(runanywhere_native PRIVATE "${_ra_bundled_dir}")
        target_compile_definitions(runanywhere_native PRIVATE
            _CRT_SECURE_NO_WARNINGS NOMINMAX WIN32_LEAN_AND_MEAN)
        target_compile_options(runanywhere_native PRIVATE /EHsc /Zc:__cplusplus /utf-8 /bigobj)
        # napi_* symbols are exported by the host executable (node.exe / electron.exe),
        # not a DLL. Delay-load them; win_delay_load_hook.cc redirects the import to
        # the running host at first call (works for both Node and Electron).
        #
        # DELAYLOAD interaction risks (thin / shared-commons builds):
        # - /DELAYLOAD:node.exe applies ONLY to the node.exe import library — never
        #   delay-load rac_commons.dll or plugin DLLs through this hook. The hook
        #   only rewrites "node.exe" → GetModuleHandle(NULL)/node.dll; any other
        #   delay-loaded name would fail at first call.
        # - Thin addon still has a normal IAT import of rac_commons.dll. Stage
        #   rac_commons.dll (and its dependents) beside the .node or on PATH
        #   before process load — DELAYLOAD does not defer commons resolution.
        # - Plugin DLLs loaded via LoadLibrary (rac_registry_load_plugin) must
        #   likewise find rac_commons.dll in the same directory / PATH; they do
        #   not go through win_delay_load_hook.
        # - Do not /DELAYLOAD:rac_commons.dll — that would race with plugin
        #   LoadLibrary and bypass the intentional eager link of the C ABI.
        target_link_options(runanywhere_native PRIVATE /DELAYLOAD:node.exe)
        target_link_libraries(runanywhere_native PRIVATE delayimp)
    endif()
    message(STATUS "runanywhere-electron: N-API addon 'runanywhere_native' enabled")
endif()
