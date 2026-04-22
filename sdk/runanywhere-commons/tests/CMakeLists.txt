cmake_minimum_required(VERSION 3.22)

# =============================================================================
# Integration Test Suite for runanywhere-commons
# =============================================================================

# Helper: link bundled archive dependencies to test targets on MSVC.
# On MSVC, transitive static lib deps from archive_static don't propagate fully.
function(rac_link_archive_deps target)
    if(TARGET archive_static)
        target_link_libraries(${target} PRIVATE archive_static)
    endif()
    if(TARGET zlibstatic)
        target_link_libraries(${target} PRIVATE zlibstatic)
    endif()
    if(TARGET bz2_bundled)
        target_link_libraries(${target} PRIVATE bz2_bundled)
    endif()
endfunction()

# --- v3.1 Phase 9: DAG graph primitives unit tests --------------------------
# CancelToken + RingBuffer + StreamEdge (GAP 05 skeleton). Header-only
# primitives; no backend dependency. Always built.
add_executable(test_graph_primitives test_graph_primitives.cpp)
target_include_directories(test_graph_primitives PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_graph_primitives PRIVATE rac_commons)
rac_link_archive_deps(test_graph_primitives)
target_compile_features(test_graph_primitives PRIVATE cxx_std_17)
add_test(NAME graph_primitives_tests COMMAND test_graph_primitives)

# --- v2 close-out Phase 5: rac_llm_thinking C ABI test -----------------------
# Behavioral parity with Swift ThinkingContentParser. 10 scenarios covering
# extract / strip / split-tokens incl. malformed inputs.
add_executable(test_llm_thinking test_llm_thinking.cpp)
target_include_directories(test_llm_thinking PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_llm_thinking PRIVATE rac_commons)
rac_link_archive_deps(test_llm_thinking)
target_compile_features(test_llm_thinking PRIVATE cxx_std_17)
add_test(NAME llm_thinking_tests COMMAND test_llm_thinking)

# --- v2 close-out Phase 2: proto-byte event dispatch test --------------------
# Exercises rac::voice_agent::dispatch_proto_event() — the C union → proto
# VoiceEvent → SerializeToArray → callback path that GAP 09 Phase 15 declared
# but left as a stub. Tests round-trip per oneof arm + monotonic seq +
# unregister-stops-dispatch. SKIP-style when RAC_HAVE_PROTOBUF is undefined.
add_executable(test_proto_event_dispatch test_proto_event_dispatch.cpp)
target_include_directories(test_proto_event_dispatch PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_proto_event_dispatch PRIVATE rac_commons)
rac_link_archive_deps(test_proto_event_dispatch)
target_compile_features(test_proto_event_dispatch PRIVATE cxx_std_17)
add_test(NAME proto_event_dispatch_tests COMMAND test_proto_event_dispatch)

# --- GAP 02 Phase 10: unified engine plugin registry tests --------------------
# No backend dependency; all three link directly against rac_commons.
add_executable(test_engine_vtable test_engine_vtable.cpp)
target_include_directories(test_engine_vtable PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_engine_vtable PRIVATE rac_commons)
rac_link_archive_deps(test_engine_vtable)
target_compile_features(test_engine_vtable PRIVATE cxx_std_17)
add_test(NAME engine_vtable_tests COMMAND test_engine_vtable)

add_executable(test_legacy_coexistence test_legacy_coexistence.cpp)
target_include_directories(test_legacy_coexistence PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_legacy_coexistence PRIVATE rac_commons)
rac_link_archive_deps(test_legacy_coexistence)
target_compile_features(test_legacy_coexistence PRIVATE cxx_std_17)
add_test(NAME legacy_coexistence_tests COMMAND test_legacy_coexistence)

# GAP 04 Phase 12: engine router + hardware profile tests (always built;
# pure C++, no backend dependency).
add_executable(test_engine_router test_engine_router.cpp)
target_include_directories(test_engine_router PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_engine_router PRIVATE rac_commons)
rac_link_archive_deps(test_engine_router)
target_compile_features(test_engine_router PRIVATE cxx_std_17)
add_test(NAME engine_router_tests COMMAND test_engine_router)

add_executable(test_hardware_profile test_hardware_profile.cpp)
target_include_directories(test_hardware_profile PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_hardware_profile PRIVATE rac_commons)
rac_link_archive_deps(test_hardware_profile)
target_compile_features(test_hardware_profile PRIVATE cxx_std_17)
add_test(NAME hardware_profile_tests COMMAND test_hardware_profile)

# GAP 03 Phase 6: static registration test (always built — exercises the
# RAC_STATIC_PLUGIN_REGISTER macro independently of the dlopen path).
add_executable(test_static_registration test_static_registration.cpp)
target_include_directories(test_static_registration PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_static_registration PRIVATE rac_commons)
rac_link_archive_deps(test_static_registration)
target_compile_features(test_static_registration PRIVATE cxx_std_17)
add_test(NAME static_registration_tests COMMAND test_static_registration)

# GAP 03 Phase 6: dynamic loader tests — only meaningful in SHARED-plugins
# mode. iOS / WASM / RAC_STATIC_PLUGINS=ON skip these targets entirely.
if(NOT RAC_STATIC_PLUGINS)
    # Two fixture libraries from one source — the BAD_ABI variant flips a
    # compile-time toggle so its metadata.abi_version equals host + 99.
    add_library(rac_test_plugin SHARED fixtures/rac_test_plugin.cpp)
    set_target_properties(rac_test_plugin PROPERTIES
        OUTPUT_NAME runanywhere_test_plugin
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden)
    target_include_directories(rac_test_plugin PRIVATE ${CMAKE_SOURCE_DIR}/include)
    target_compile_features(rac_test_plugin PRIVATE cxx_std_17)

    add_library(rac_test_plugin_bad_abi SHARED fixtures/rac_test_plugin.cpp)
    set_target_properties(rac_test_plugin_bad_abi PROPERTIES
        OUTPUT_NAME runanywhere_test_plugin_bad_abi
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden)
    target_include_directories(rac_test_plugin_bad_abi PRIVATE ${CMAKE_SOURCE_DIR}/include)
    target_compile_definitions(rac_test_plugin_bad_abi PRIVATE RAC_TEST_PLUGIN_FORCE_BAD_ABI=1)
    target_compile_features(rac_test_plugin_bad_abi PRIVATE cxx_std_17)

    # Path the test can dlopen at runtime — uses generator expression so it
    # works in single- and multi-config generators.
    set(_GAP03_FIXTURE_GOOD "$<TARGET_FILE:rac_test_plugin>")
    set(_GAP03_FIXTURE_BAD  "$<TARGET_FILE:rac_test_plugin_bad_abi>")

    add_executable(test_plugin_loader test_plugin_loader.cpp)
    target_include_directories(test_plugin_loader PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_loader PRIVATE rac_commons)
    rac_link_archive_deps(test_plugin_loader)
    target_compile_features(test_plugin_loader PRIVATE cxx_std_17)
    target_compile_definitions(test_plugin_loader PRIVATE
        "RAC_TEST_PLUGIN_PATH=\"${_GAP03_FIXTURE_GOOD}\"")
    add_dependencies(test_plugin_loader rac_test_plugin)
    add_test(NAME plugin_loader_tests COMMAND test_plugin_loader)

    add_executable(test_plugin_loader_abi_mismatch test_plugin_loader_abi_mismatch.cpp)
    target_include_directories(test_plugin_loader_abi_mismatch PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_loader_abi_mismatch PRIVATE rac_commons)
    rac_link_archive_deps(test_plugin_loader_abi_mismatch)
    target_compile_features(test_plugin_loader_abi_mismatch PRIVATE cxx_std_17)
    target_compile_definitions(test_plugin_loader_abi_mismatch PRIVATE
        "RAC_TEST_PLUGIN_BAD_ABI_PATH=\"${_GAP03_FIXTURE_BAD}\"")
    add_dependencies(test_plugin_loader_abi_mismatch rac_test_plugin_bad_abi)
    add_test(NAME plugin_loader_abi_mismatch_tests COMMAND test_plugin_loader_abi_mismatch)

    add_executable(test_plugin_loader_double_load test_plugin_loader_double_load.cpp)
    target_include_directories(test_plugin_loader_double_load PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_loader_double_load PRIVATE rac_commons)
    rac_link_archive_deps(test_plugin_loader_double_load)
    target_compile_features(test_plugin_loader_double_load PRIVATE cxx_std_17)
    target_compile_definitions(test_plugin_loader_double_load PRIVATE
        "RAC_TEST_PLUGIN_PATH=\"${_GAP03_FIXTURE_GOOD}\"")
    add_dependencies(test_plugin_loader_double_load rac_test_plugin)
    add_test(NAME plugin_loader_double_load_tests COMMAND test_plugin_loader_double_load)
endif()

# Per-backend plugin entry tests — only built when the respective backend is on.
if(RAC_BACKEND_LLAMACPP AND TARGET rac_backend_llamacpp)
    add_executable(test_plugin_entry_llamacpp test_plugin_entry_llamacpp.cpp)
    target_include_directories(test_plugin_entry_llamacpp PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_entry_llamacpp PRIVATE rac_commons rac_backend_llamacpp)
    rac_link_archive_deps(test_plugin_entry_llamacpp)
    target_compile_features(test_plugin_entry_llamacpp PRIVATE cxx_std_17)
    add_test(NAME plugin_entry_llamacpp_tests COMMAND test_plugin_entry_llamacpp)
endif()

if(RAC_BACKEND_ONNX AND TARGET rac_backend_onnx)
    add_executable(test_plugin_entry_onnx test_plugin_entry_onnx.cpp)
    target_include_directories(test_plugin_entry_onnx PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_plugin_entry_onnx PRIVATE rac_commons rac_backend_onnx)
    rac_link_archive_deps(test_plugin_entry_onnx)
    target_compile_features(test_plugin_entry_onnx PRIVATE cxx_std_17)
    add_test(NAME plugin_entry_onnx_tests COMMAND test_plugin_entry_onnx)
endif()

# --- test_core: Always built (no backend dependency) ---
add_executable(test_core test_core.cpp)
target_include_directories(test_core PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_core PRIVATE rac_commons)
rac_link_archive_deps(test_core)
target_compile_features(test_core PRIVATE cxx_std_20)
add_test(NAME core_tests COMMAND test_core --run-all)

# --- test_extraction: Always built (no backend dependency) ---
add_executable(test_extraction test_extraction.cpp)
target_include_directories(test_extraction PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_extraction PRIVATE rac_commons)
rac_link_archive_deps(test_extraction)
target_compile_features(test_extraction PRIVATE cxx_std_17)
add_test(NAME extraction_tests COMMAND test_extraction --run-all)

# --- test_download_orchestrator: Always built (no backend dependency) ---
add_executable(test_download_orchestrator test_download_orchestrator.cpp)
target_include_directories(test_download_orchestrator PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
)
target_link_libraries(test_download_orchestrator PRIVATE rac_commons)
rac_link_archive_deps(test_download_orchestrator)
target_compile_features(test_download_orchestrator PRIVATE cxx_std_17)
add_test(NAME download_orchestrator_tests COMMAND test_download_orchestrator --run-all)

# --- ONNX backend tests (VAD, STT, TTS, WakeWord) ---
if(RAC_BACKEND_ONNX AND TARGET rac_backend_onnx)
    # VAD test
    add_executable(test_vad test_vad.cpp)
    target_include_directories(test_vad PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_vad PRIVATE rac_commons rac_backend_onnx)
    target_compile_features(test_vad PRIVATE cxx_std_20)
    add_test(NAME vad_tests COMMAND test_vad --run-all)

    # STT test
    add_executable(test_stt test_stt.cpp)
    target_include_directories(test_stt PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_stt PRIVATE rac_commons rac_backend_onnx)
    target_compile_features(test_stt PRIVATE cxx_std_20)
    add_test(NAME stt_tests COMMAND test_stt --run-all)

    # TTS test
    add_executable(test_tts test_tts.cpp)
    target_include_directories(test_tts PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_tts PRIVATE rac_commons rac_backend_onnx)
    target_compile_features(test_tts PRIVATE cxx_std_20)
    add_test(NAME tts_tests COMMAND test_tts --run-all)

    # WakeWord test
    add_executable(test_wakeword test_wakeword.cpp)
    target_include_directories(test_wakeword PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_wakeword PRIVATE rac_commons rac_backend_onnx)
    target_compile_features(test_wakeword PRIVATE cxx_std_20)
    add_test(NAME wakeword_tests COMMAND test_wakeword --run-all)
endif()

# --- LLM test: Requires LlamaCPP backend ---
if(RAC_BACKEND_LLAMACPP AND TARGET rac_backend_llamacpp)
    add_executable(test_llm test_llm.cpp)
    target_include_directories(test_llm PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_llm PRIVATE rac_commons rac_backend_llamacpp)
    target_compile_features(test_llm PRIVATE cxx_std_20)
    add_test(NAME llm_tests COMMAND test_llm --run-all)
endif()

# --- Voice Agent test: Requires ONNX + LlamaCPP ---
if(RAC_BACKEND_ONNX AND RAC_BACKEND_LLAMACPP
   AND TARGET rac_backend_onnx AND TARGET rac_backend_llamacpp)
    add_executable(test_voice_agent test_voice_agent.cpp)
    target_include_directories(test_voice_agent PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
    )
    target_link_libraries(test_voice_agent PRIVATE
        rac_commons rac_backend_onnx rac_backend_llamacpp)
    target_compile_features(test_voice_agent PRIVATE cxx_std_20)
    add_test(NAME voice_agent_tests COMMAND test_voice_agent --run-all)
endif()

# --- macOS RPATH for ONNX Runtime dylib ---
if(APPLE)
    set(ONNX_MACOS_LIB_DIR "${CMAKE_SOURCE_DIR}/third_party/onnxruntime-macos/lib")
    foreach(test_target test_vad test_stt test_tts test_wakeword test_voice_agent)
        if(TARGET ${test_target})
            set_target_properties(${test_target} PROPERTIES
                BUILD_RPATH "${ONNX_MACOS_LIB_DIR}"
                INSTALL_RPATH "${ONNX_MACOS_LIB_DIR}"
            )
        endif()
    endforeach()
endif()

# --- Linux RPATH for Sherpa-ONNX shared libs ---
if(UNIX AND NOT APPLE)
    set(SHERPA_LINUX_LIB_DIR "${CMAKE_SOURCE_DIR}/third_party/sherpa-onnx-linux/lib")
    foreach(test_target test_vad test_stt test_tts test_wakeword test_voice_agent)
        if(TARGET ${test_target})
            set_target_properties(${test_target} PROPERTIES
                BUILD_RPATH "$ORIGIN;${SHERPA_LINUX_LIB_DIR}"
                INSTALL_RPATH "$ORIGIN;${SHERPA_LINUX_LIB_DIR}"
            )
        endif()
    endforeach()
endif()

# --- Windows: Copy DLLs to test output directory ---
# Only attempt DLL staging when the ONNX FetchContent variable is actually
# populated in this scope (set by FetchONNXRuntime.cmake when RAC_BACKEND_ONNX
# is ON). If it's unset the EXISTS check silently evaluates against
# "/lib/onnxruntime.dll" which is never what we want.
if(WIN32 AND DEFINED onnxruntime_SOURCE_DIR AND NOT "${onnxruntime_SOURCE_DIR}" STREQUAL "")
    foreach(test_target test_vad test_stt test_tts test_wakeword test_voice_agent)
        if(TARGET ${test_target})
            if(EXISTS "${onnxruntime_SOURCE_DIR}/lib/onnxruntime.dll")
                add_custom_command(TARGET ${test_target} POST_BUILD
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${onnxruntime_SOURCE_DIR}/lib/onnxruntime.dll"
                        $<TARGET_FILE_DIR:${test_target}>
                )
            endif()
        endif()
    endforeach()
endif()

# =============================================================================
# RAG Pipeline Tests (GoogleTest)
# =============================================================================

if(RAC_BUILD_BACKENDS AND RAC_BACKEND_RAG AND NOT (WIN32 AND RAC_BUILD_SHARED))
    include(FetchContent)
    find_package(Threads REQUIRED)

    # GoogleTest (download on first configure)
    FetchContent_Declare(
        googletest
        GIT_REPOSITORY https://github.com/google/googletest.git
        GIT_TAG        release-1.12.1
        GIT_SHALLOW    TRUE
    )
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(googletest)
    include(GoogleTest)

    # RAG pipeline thread safety test (disabled on Windows — needs IEmbeddingProvider internal header)
    if(NOT WIN32)
    add_executable(rac_rag_backend_thread_safety_test
        rag_backend_thread_safety_test.cpp
    )
    target_include_directories(rac_rag_backend_thread_safety_test PRIVATE
        ${CMAKE_SOURCE_DIR}/src/features/rag
    )
    target_link_libraries(rac_rag_backend_thread_safety_test
        PRIVATE
        rac_commons
        Threads::Threads
        GTest::gtest_main
    )
    target_compile_features(rac_rag_backend_thread_safety_test PRIVATE cxx_std_20)
    gtest_discover_tests(rac_rag_backend_thread_safety_test
        DISCOVERY_MODE PRE_TEST
    )
    add_test(
        NAME rac_rag_backend_thread_safety_test
        COMMAND rac_rag_backend_thread_safety_test
    )
    endif()

    # Chunker Unit Tests
    add_executable(rac_chunker_test
        chunker_test.cpp
    )
    target_include_directories(rac_chunker_test PRIVATE
        ${CMAKE_SOURCE_DIR}/src/features/rag
    )
    target_link_libraries(rac_chunker_test
        PRIVATE
        rac_commons
        Threads::Threads
        GTest::gtest_main
    )
    target_compile_features(rac_chunker_test PRIVATE cxx_std_20)
    gtest_discover_tests(rac_chunker_test
        DISCOVERY_MODE PRE_TEST
    )
    add_test(
        NAME rac_chunker_test
        COMMAND rac_chunker_test
    )

    # Simple Tokenizer Unit Tests
    add_executable(rac_simple_tokenizer_test
        simple_tokenizer_test.cpp
    )
    target_link_libraries(rac_simple_tokenizer_test
        PRIVATE
        rac_commons
        Threads::Threads
        GTest::gtest_main
    )
    target_compile_features(rac_simple_tokenizer_test PRIVATE cxx_std_20)
    gtest_discover_tests(rac_simple_tokenizer_test
        DISCOVERY_MODE PRE_TEST
    )
    add_test(
        NAME rac_simple_tokenizer_test
        COMMAND rac_simple_tokenizer_test
    )
endif()
# =============================================================================
# RunAnywhere Commons - Benchmark Unit Tests (GoogleTest)
# =============================================================================

include(FetchContent)

FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.14.0
)

# Prevent GoogleTest from overriding compiler/linker options
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(googletest)

add_executable(rac_benchmark_tests
    benchmark/test_monotonic_clock.cpp
    benchmark/test_timing_struct.cpp
    benchmark/test_benchmark_log.cpp
    benchmark/test_benchmark_stats.cpp
)

target_link_libraries(rac_benchmark_tests
    PRIVATE
        rac_commons
        GTest::gtest_main
)

target_include_directories(rac_benchmark_tests
    PRIVATE
        ${CMAKE_SOURCE_DIR}/include
)

include(GoogleTest)
gtest_discover_tests(rac_benchmark_tests)
