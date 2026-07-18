# =============================================================================
# rcli — RunAnywhere desktop CLI
# =============================================================================
# Built from the root CMakeLists via -DRAC_BUILD_CLI=ON (see the rcli-* presets).
# Links rac_commons + statically-folded backends; the reusable desktop platform
# adapter lives in commons (RAC_DESKTOP_ADAPTER) per the repo layering rule.
#
# Targets:
#   rcli_core  — OBJECT library with every TU except main.cpp (shared with tests)
#   rcli       — the CLI binary
# =============================================================================

if(NOT TARGET rac_commons)
    message(FATAL_ERROR "rcli must be built from the repository root CMakeLists (rac_commons target missing)")
endif()
if(NOT RAC_DESKTOP_ADAPTER)
    message(FATAL_ERROR "rcli requires -DRAC_DESKTOP_ADAPTER=ON (desktop platform adapter + curl transport)")
endif()

set(RCLI_SOURCES
    src/app.cpp
    src/bootstrap.cpp
    src/catalog/catalog.cpp
    src/catalog/model_ref.cpp
    src/commands/cmd_version.cpp
    src/commands/cmd_info.cpp
    src/commands/cmd_backends.cpp
    src/commands/cmd_list.cpp
    src/commands/cmd_lora.cpp
    src/commands/cmd_pull.cpp
    src/commands/cmd_rm.cpp
    src/commands/cmd_run.cpp
    src/commands/cmd_image.cpp
    src/commands/cmd_serve.cpp
    src/commands/cmd_show.cpp
    src/commands/cmd_stt.cpp
    src/commands/cmd_embed.cpp
    src/commands/cmd_tts.cpp
    src/commands/cmd_vad.cpp
    src/commands/cmd_voice.cpp
    src/commands/cmd_rag.cpp
    src/commands/engine_options.cpp
    src/commands/model_setup.cpp
    src/config/cli_paths.cpp
    src/io/wav_io.cpp
    src/io/image_io.cpp
    src/io/output.cpp
    src/progress/progress_bar.cpp
    src/repl/repl.cpp
    src/util/term.cpp
)

# Vendored single-file deps. linenoise is C; compiled into the core object lib.
set(RCLI_THIRD_PARTY_SOURCES
    third_party/linenoise/linenoise.c
)

add_library(rcli_core OBJECT ${RCLI_SOURCES} ${RCLI_THIRD_PARTY_SOURCES})

target_include_directories(rcli_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/CLI11
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/linenoise
)

target_link_libraries(rcli_core PUBLIC rac_commons)
target_compile_features(rcli_core PUBLIC cxx_std_20)

# Version string: single source of truth is sdk/runanywhere-commons/VERSION,
# already read into PROJECT_VERSION by the root CMakeLists.
target_compile_definitions(rcli_core PUBLIC
    RCLI_VERSION="${PROJECT_VERSION}"
    # CLI11's current C++20 default still selects std::wstring_convert /
    # <codecvt>, which the standard library deprecated in C++17. Use CLI11's
    # maintained locale-conversion path instead.
    CLI11_HAS_CODECVT=0)

# Proto-byte ABI access (DownloadProgress, ModelInfo, Register* requests).
# Same internal-consumer pattern as commons tests' rac_test_define_have_protobuf:
# rac_commons keeps RAC_HAVE_PROTOBUF/include paths PRIVATE, so re-attach here.
set(_RCLI_COMMONS_DIR ${CMAKE_SOURCE_DIR}/sdk/runanywhere-commons)
if(NOT RAC_PROTOBUF_RUNTIME_ENABLED
   OR NOT EXISTS ${_RCLI_COMMONS_DIR}/src/generated/proto/model_types.pb.cc)
    message(FATAL_ERROR "rcli requires the commons protobuf runtime (RAC_PROTOBUF_RUNTIME_ENABLED) "
                        "for the model-lifecycle proto ABI")
endif()
target_compile_definitions(rcli_core PUBLIC RAC_HAVE_PROTOBUF=1)
if(RAC_PROTOBUF_NAMESPACE_ISOLATED)
    # Generated messages and the statically bundled runtime must use the same
    # private namespace token rewrite. rac_commons keeps this definition
    # private, so attach it explicitly to the CLI and its test consumers.
    target_compile_definitions(rcli_core PUBLIC google=runanywhere_internal)
endif()
target_include_directories(rcli_core PUBLIC
    ${_RCLI_COMMONS_DIR}/src/generated/proto
    ${_RCLI_COMMONS_DIR}/src/generated
    ${Protobuf_INCLUDE_DIRS}
)
if(TARGET protobuf::libprotobuf)
    target_link_libraries(rcli_core PUBLIC protobuf::libprotobuf)
elseif(Protobuf_LIBRARIES)
    target_link_libraries(rcli_core PUBLIC ${Protobuf_LIBRARIES})
endif()
if(RAC_ABSL_LIBS)
    target_link_libraries(rcli_core PUBLIC ${RAC_ABSL_LIBS})
endif()
if(RAC_PROTOBUF_COMPILE_OPTIONS)
    target_compile_options(rcli_core PRIVATE ${RAC_PROTOBUF_COMPILE_OPTIONS})
endif()

# Per-backend availability defines, mirroring tools/CMakeLists.txt's
# if(TARGET ...) pattern so the CLI builds with any backend subset.
# coreml is Apple-only (serves DIFFUSION); its target only exists on Apple, so
# the if(TARGET ...) guard keeps this list cross-platform. Unlike the others it
# has no rac_backend_coreml_register() fn — bootstrap.cpp registers its plugin
# entry directly under RCLI_HAS_COREML.
foreach(_rcli_backend llamacpp onnx sherpa mlx coreml)
    if(TARGET rac_backend_${_rcli_backend})
        string(TOUPPER ${_rcli_backend} _rcli_backend_upper)
        target_compile_definitions(rcli_core PUBLIC RCLI_HAS_${_rcli_backend_upper}=1)
        target_link_libraries(rcli_core PUBLIC rac_backend_${_rcli_backend})
    endif()
endforeach()

# Optional OpenAI-compatible server behind `rcli serve` (RAC_BUILD_SERVER=ON).
# On rcli_core (PUBLIC) so every consumer — the binary and the test
# executable — links rac_server whenever cmd_serve was compiled with it.
if(TARGET rac_server)
    target_link_libraries(rcli_core PUBLIC rac_server)
    target_compile_definitions(rcli_core PUBLIC RCLI_HAS_SERVER=1)
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(rcli_core PRIVATE -Wall -Wextra)
    # Vendored C/C++ compiles with the repo's warning set; CLI11/linenoise
    # are not ours to fix.
    set_source_files_properties(third_party/linenoise/linenoise.c
        PROPERTIES COMPILE_OPTIONS "-w")
endif()

# =============================================================================
# rcli binary
# =============================================================================

add_executable(rcli src/main.cpp)
target_link_libraries(rcli PRIVATE rcli_core)

find_package(Threads REQUIRED)
target_link_libraries(rcli PRIVATE Threads::Threads)


# Relocatable layout: tarballs ship bin/rcli + lib/*.{so,dylib}.
if(APPLE)
    set_target_properties(rcli PROPERTIES
        BUILD_RPATH "${CMAKE_BINARY_DIR}"
        INSTALL_RPATH "@loader_path/../lib")
else()
    set_target_properties(rcli PROPERTIES
        BUILD_RPATH "${CMAKE_BINARY_DIR}"
        INSTALL_RPATH "$ORIGIN/../lib")
endif()

install(TARGETS rcli RUNTIME DESTINATION bin)

# =============================================================================
# Tests
# =============================================================================

if(RAC_BUILD_TESTS)
    add_subdirectory(tests)
endif()

message(STATUS "  rcli configured (version ${PROJECT_VERSION})")
