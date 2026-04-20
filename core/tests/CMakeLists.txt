# gtest discovery is hoisted to the root CMakeLists so every subdir under
# `RA_BUILD_TESTS` can link GTest::gtest without repeating find_package.

set(_ra_core_test_sources
    abi_test.cpp
    ring_buffer_test.cpp
    memory_pool_test.cpp
    cancel_token_test.cpp
    stream_edge_test.cpp
    stream_edge_stress_test.cpp
    sentence_detector_test.cpp
    text_sanitizer_test.cpp
    plugin_registry_test.cpp
    plugin_registry_lifecycle_test.cpp
    plugin_loader_dynamic_test.cpp
    llamacpp_live_test.cpp
    sherpa_live_test.cpp
    net_util_errors_test.cpp
    engine_router_test.cpp
    hardware_profile_test.cpp
    voice_pipeline_integration_test.cpp
    tool_calling_test.cpp
    structured_output_test.cpp
    energy_vad_test.cpp
    llm_metrics_test.cpp
    auth_manager_test.cpp
    plugin_registry_abi_test.cpp
    abi_extensions_test.cpp
)

# Only include the proto round-trip when ra_idl exists (RA_HAVE_PROTOBUF).
# Otherwise the test target would fail to link against the generated types.
if(TARGET RunAnywhere::idl)
    list(APPEND _ra_core_test_sources proto_roundtrip_test.cpp)
endif()

add_executable(ra_core_tests ${_ra_core_test_sources})

target_link_libraries(ra_core_tests
    PRIVATE
        RunAnywhere::core
        RunAnywhere::core_voice_pipeline
        RunAnywhere::core_abi_ext
        RunAnywhere::platform_flags
        RunAnywhere::sanitizers
        GTest::gtest
        GTest::gtest_main
)
if(TARGET RunAnywhere::idl)
    target_link_libraries(ra_core_tests PRIVATE RunAnywhere::idl)
endif()

# Pass the built-plugins directory into the dynamic loader smoke test so
# it can dlopen the engine dylibs without hunting through the build tree.
target_compile_definitions(ra_core_tests PRIVATE
    RA_ENGINE_PLUGIN_DIR="${CMAKE_BINARY_DIR}/engines"
)

# The engine dylibs are built as MODULE libraries with their own custom
# output path; ensure they're built before the test runs so the discovery
# path is populated. They don't need to be linked in.
if(TARGET llamacpp_engine)
    add_dependencies(ra_core_tests llamacpp_engine)
endif()
if(TARGET sherpa_engine)
    add_dependencies(ra_core_tests sherpa_engine)
endif()
if(TARGET wakeword_engine)
    add_dependencies(ra_core_tests wakeword_engine)
endif()

include(GoogleTest)
# detect_leaks is a Linux-only ASan feature; on macOS we rely on scope-based
# RAII. halt_on_error stays on so any real bug fails the suite immediately.
gtest_discover_tests(ra_core_tests
    PROPERTIES
        TIMEOUT 60
        ENVIRONMENT "ASAN_OPTIONS=halt_on_error=1;UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1"
)
