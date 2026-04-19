# RunAnywhere v2 — C++20 core
#
# Produces two targets:
#   ra_core_abi     — the C ABI (extern "C" headers + .c glue). Frontends
#                     link only against this.
#   ra_core         — the full C++ runtime (graph, registry, router,
#                     voice_pipeline, model_registry, util). Engines and
#                     solutions link against this.

# --- L0: C ABI ---------------------------------------------------------------
add_library(ra_core_abi STATIC
    abi/ra_version.c
    abi/ra_status.c
    abi/ra_errors.c
    abi/ra_lifecycle.c
    abi/rac_compat.c
)
target_include_directories(ra_core_abi PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/abi>
    $<INSTALL_INTERFACE:include>
)
set_target_properties(ra_core_abi PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
)
target_link_libraries(ra_core_abi PUBLIC RunAnywhere::platform_flags)
add_library(RunAnywhere::core_abi ALIAS ra_core_abi)

# --- L4: graph + runtime -----------------------------------------------------
add_library(ra_core_graph STATIC
    graph/graph_scheduler.cpp
)
target_include_directories(ra_core_graph PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ra_core_graph
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)
set_target_properties(ra_core_graph PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_graph ALIAS ra_core_graph)

# --- Plugin registry + loader ------------------------------------------------
add_library(ra_core_registry STATIC
    registry/plugin_registry.cpp
)
target_include_directories(ra_core_registry PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ra_core_registry
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers $<$<NOT:$<BOOL:${RA_STATIC_PLUGINS}>>:${CMAKE_DL_LIBS}>
)
set_target_properties(ra_core_registry PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_registry ALIAS ra_core_registry)

# --- Engine router + hardware profile ----------------------------------------
add_library(ra_core_router STATIC
    router/hardware_profile.cpp
    router/engine_router.cpp
)
target_include_directories(ra_core_router PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ra_core_router
    PUBLIC  ra_core_abi ra_core_registry RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)
set_target_properties(ra_core_router PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_router ALIAS ra_core_router)

# --- VoiceAgent concrete pipeline (port of RCLI / FastVoice orchestrator) ----
add_library(ra_core_voice_pipeline STATIC
    voice_pipeline/sentence_detector.cpp
    voice_pipeline/text_sanitizer.cpp
    voice_pipeline/voice_pipeline.cpp
)
target_include_directories(ra_core_voice_pipeline PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ra_core_voice_pipeline
    PUBLIC  ra_core_graph ra_core_router ra_core_registry ra_core_abi
            RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)
set_target_properties(ra_core_voice_pipeline PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_voice_pipeline ALIAS ra_core_voice_pipeline)

# --- Model registry ----------------------------------------------------------
add_library(ra_core_model_registry STATIC
    model_registry/model_registry.cpp
    model_registry/model_downloader.cpp
    model_registry/lora_registry.cpp
    model_registry/model_compatibility.cpp
)
target_include_directories(ra_core_model_registry PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
# libcurl for the real downloader. System package on macOS / Linux; Android
# NDK has it; WASM-emscripten provides a curl shim over fetch().
find_package(CURL QUIET)
if(NOT CURL_FOUND)
    find_package(CURL CONFIG QUIET)
endif()
if(NOT CURL_FOUND)
    message(FATAL_ERROR
        "libcurl not found. Install libcurl-dev (Linux) or let vcpkg "
        "provide it — the real model downloader needs it.")
endif()
target_link_libraries(ra_core_model_registry
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers CURL::libcurl
)
if(APPLE)
    # CommonCrypto for SHA-256 (no extra dep).
    target_link_libraries(ra_core_model_registry PRIVATE "-framework CoreFoundation")
else()
    # Non-Apple hosts route SHA-256 through OpenSSL. libcurl already
    # links libssl transitively, but the linker needs an explicit dep on
    # libcrypto because model_downloader.cpp calls SHA256_Init/Update/Final.
    find_package(OpenSSL QUIET)
    if(OpenSSL_FOUND)
        target_link_libraries(ra_core_model_registry PRIVATE OpenSSL::Crypto)
    endif()
endif()
set_target_properties(ra_core_model_registry PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_model_registry ALIAS ra_core_model_registry)

# --- Network / auth layer ----------------------------------------------------
# Ports capability surface from sdk/runanywhere-commons/include/rac/
# infrastructure/network/{rac_http_client,rac_endpoints,rac_environment,
# rac_auth_manager}.h into a single libcurl-backed implementation.
add_library(ra_core_net STATIC
    net/http_client.cpp
    net/environment.cpp
    net/telemetry.cpp
)
target_include_directories(ra_core_net PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ra_core_net
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers CURL::libcurl
)
set_target_properties(ra_core_net PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_net ALIAS ra_core_net)

# --- Utilities (audio WAV encode/decode, image helpers) ----------------------
add_library(ra_core_util STATIC
    util/audio_utils.cpp
    util/extraction.cpp
    util/file_manager.cpp
    util/storage_analyzer.cpp
    util/tool_calling.cpp
)
target_include_directories(ra_core_util PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
# libarchive for ZIP / TAR / TAR.GZ / TAR.BZ2 / TAR.XZ extraction.
# macOS ships it at /usr/lib/libarchive; Linux via apt libarchive-dev.
find_path(LIBARCHIVE_INCLUDE_DIR NAMES archive.h
    PATHS /opt/homebrew/include /usr/include /usr/local/include
    /opt/homebrew/Cellar/libarchive/*/include)
find_library(LIBARCHIVE_LIBRARY NAMES archive libarchive
    PATHS /opt/homebrew/lib /usr/lib /usr/local/lib
    /opt/homebrew/Cellar/libarchive/*/lib)
if(NOT LIBARCHIVE_INCLUDE_DIR OR NOT LIBARCHIVE_LIBRARY)
    message(FATAL_ERROR
        "libarchive not found. Install via 'brew install libarchive' on "
        "macOS or 'apt install libarchive-dev' on Linux.")
endif()
target_include_directories(ra_core_util PRIVATE ${LIBARCHIVE_INCLUDE_DIR})
target_link_libraries(ra_core_util
    PUBLIC  ra_core_abi RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers ${LIBARCHIVE_LIBRARY}
)
set_target_properties(ra_core_util PROPERTIES POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_util ALIAS ra_core_util)

# --- Pipeline C ABI bridge ---------------------------------------------------
# Turns the `ra_pipeline_*` entry points in abi/ra_pipeline.h into a real
# bridge onto core/voice_pipeline + solutions/voice-agent. Uses plain C
# structs, not proto3 — frontends do not need a protobuf runtime at link
# time. The matching proto3 schemas in idl/*.proto remain the canonical IDL.
# Defined after voice_pipeline/router/registry so link dependencies resolve.
add_library(ra_core_pipeline_abi STATIC
    abi/ra_pipeline.cpp
)
target_include_directories(ra_core_pipeline_abi PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)
target_link_libraries(ra_core_pipeline_abi
    PUBLIC  ra_core_abi
            ra_core_voice_pipeline
            ra_core_router
            ra_core_registry
            RunAnywhere::platform_flags
    PRIVATE RunAnywhere::sanitizers
)
set_target_properties(ra_core_pipeline_abi PROPERTIES
    POSITION_INDEPENDENT_CODE ON)
add_library(RunAnywhere::core_pipeline_abi ALIAS ra_core_pipeline_abi)

# --- Umbrella target ---------------------------------------------------------
add_library(ra_core INTERFACE)
target_link_libraries(ra_core INTERFACE
    ra_core_abi
    ra_core_graph
    ra_core_registry
    ra_core_router
    ra_core_voice_pipeline
    ra_core_model_registry
    ra_core_net
    ra_core_util
    ra_core_pipeline_abi
)
add_library(RunAnywhere::core ALIAS ra_core)

# --- Single shared-library artifact ------------------------------------------
# Wraps the full core as one .dylib / .so / .dll for runtime linking from
# Dart FFI, JNI (Kotlin), Node.js N-API, etc. Re-exports every C ABI symbol
# from the static archives via whole-archive linkage so dlsym / FFI
# DynamicLibrary.open can find them.
#
# The JNI bridge (frontends/kotlin/src/main/cpp/jni_bridge.cpp) is bundled
# here too so a single System.loadLibrary("racommons_core") on Android / JVM
# reaches both the C ABI and the Java_... glue functions.
#
# Named `libracommons_core.dylib` on macOS to match the historical commons
# name — downstream FFI bindings default-search for that filename.
set(RA_SHARED_SOURCES abi/ra_shared_facade.c)
if(EXISTS ${CMAKE_SOURCE_DIR}/frontends/kotlin/src/main/cpp/jni_bridge.cpp
   AND NOT RA_DISABLE_JNI_BRIDGE)
    # JNI headers only needed on platforms where Kotlin host is expected
    # (Linux/macOS CI, Android). Guard behind an opt-out so iOS + WASM
    # builds skip the JNI extension.
    find_package(JNI QUIET)
    if(JNI_FOUND)
        list(APPEND RA_SHARED_SOURCES
            ${CMAKE_SOURCE_DIR}/frontends/kotlin/src/main/cpp/jni_bridge.cpp)
        set(RA_HAVE_JNI ON)
    endif()
endif()
add_library(racommons_core SHARED ${RA_SHARED_SOURCES})
if(RA_HAVE_JNI)
    target_include_directories(racommons_core PRIVATE ${JNI_INCLUDE_DIRS})
endif()
set_target_properties(racommons_core PROPERTIES
    OUTPUT_NAME "racommons_core"
    POSITION_INDEPENDENT_CODE ON)

if(APPLE)
    # -undefined dynamic_lookup defers resolution of the ra_llm_* /
    # ra_stt_* / ra_tts_* / ra_vad_* / ra_embed_* / ra_ww_* primitive
    # symbols to runtime. Those come from engine plugins (llamacpp,
    # sherpa, etc) which are loaded via dlopen or statically linked into
    # the host app — the core itself does not declare them.
    target_link_options(racommons_core PRIVATE
        -Wl,-undefined,dynamic_lookup)
    target_link_libraries(racommons_core PRIVATE
        -Wl,-force_load,$<TARGET_FILE:ra_core_abi>
        -Wl,-force_load,$<TARGET_FILE:ra_core_pipeline_abi>
        -Wl,-force_load,$<TARGET_FILE:ra_core_voice_pipeline>
        -Wl,-force_load,$<TARGET_FILE:ra_core_graph>
        -Wl,-force_load,$<TARGET_FILE:ra_core_registry>
        -Wl,-force_load,$<TARGET_FILE:ra_core_router>
        -Wl,-force_load,$<TARGET_FILE:ra_core_model_registry>
        -Wl,-force_load,$<TARGET_FILE:ra_core_net>
        -Wl,-force_load,$<TARGET_FILE:ra_core_util>
        ra_core_abi ra_core_pipeline_abi
        ra_core_voice_pipeline ra_core_graph ra_core_registry
        ra_core_router ra_core_model_registry ra_core_net ra_core_util
    )
elseif(UNIX)
    target_link_libraries(racommons_core PRIVATE
        -Wl,--whole-archive ra_core_abi ra_core_pipeline_abi
        ra_core_voice_pipeline ra_core_graph ra_core_registry
        ra_core_router ra_core_model_registry ra_core_net ra_core_util
        -Wl,--no-whole-archive
    )
else()
    target_link_libraries(racommons_core PRIVATE
        ra_core_abi ra_core_pipeline_abi
        ra_core_voice_pipeline ra_core_graph ra_core_registry
        ra_core_router ra_core_model_registry ra_core_net ra_core_util
    )
endif()
add_library(RunAnywhere::core_shared ALIAS racommons_core)

# --- Install -----------------------------------------------------------------
# Ship the full public header tree, not just abi/. Downstream consumers that
# do `find_package(RunAnywhere)` and link `RunAnywhere::core` need the
# graph/, registry/, router/, voice_pipeline/, model_registry/ headers too.
install(DIRECTORY
            abi/
            graph/
            registry/
            router/
            voice_pipeline/
            model_registry/
            net/
            util/
        DESTINATION include/runanywhere
        FILES_MATCHING
            PATTERN "*.h"
            PATTERN "*.inl"
)

install(TARGETS
            ra_core                       # the INTERFACE umbrella
            ra_core_abi
            ra_core_graph
            ra_core_registry
            ra_core_router
            ra_core_voice_pipeline
            ra_core_model_registry
            ra_core_net
            ra_core_util
            ra_core_pipeline_abi
        EXPORT RunAnywhereTargets
        ARCHIVE DESTINATION lib
        LIBRARY DESTINATION lib
        RUNTIME DESTINATION bin
)

install(EXPORT RunAnywhereTargets
        FILE        RunAnywhereTargets.cmake
        NAMESPACE   RunAnywhere::
        DESTINATION lib/cmake/RunAnywhere
)
