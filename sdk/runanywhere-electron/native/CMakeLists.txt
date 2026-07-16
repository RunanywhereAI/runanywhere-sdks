# runanywhere-electron — native layer.
#
# M0: a small MSVC executable ("electron_m0_harness") that drives the rac_* C ABI
# through the Win32 platform adapter to prove commons + llama.cpp RUN on Windows.
# This is the addon core minus N-API; the .node target will be added here later.
#
# Gated by RAC_BUILD_ELECTRON_HARNESS (OFF by default) so normal builds are
# unaffected. Requires rac_commons + rac_backend_llamacpp (built by the root
# project), which pull llama.cpp/ggml and the system libs transitively.

add_executable(electron_m0_harness
    m0_harness.cpp
    win32_platform_adapter.cpp
)

target_include_directories(electron_m0_harness PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons/include
)

target_link_libraries(electron_m0_harness PRIVATE
    rac_commons
    rac_backend_llamacpp
)

# rac_commons pulls the bundled zlib/bz2 statics; on MSVC libarchive/find_package
# leak them into the link line as bare names (zlibstatic.lib, bz2_bundled.lib),
# normally resolved by a directory-scoped link_directories in the commons subdir
# that does NOT reach this sibling subdir. Re-add the bundled-lib output dir.
if(MSVC)
    target_link_directories(electron_m0_harness PRIVATE "${CMAKE_BINARY_DIR}/_bundled_libs")
endif()

target_compile_features(electron_m0_harness PRIVATE cxx_std_20)

if(MSVC)
    target_compile_definitions(electron_m0_harness PRIVATE
        _CRT_SECURE_NO_WARNINGS NOMINMAX WIN32_LEAN_AND_MEAN)
    target_compile_options(electron_m0_harness PRIVATE /EHsc /Zc:__cplusplus /utf-8)
endif()

message(STATUS "runanywhere-electron: M0 harness 'electron_m0_harness' enabled")
