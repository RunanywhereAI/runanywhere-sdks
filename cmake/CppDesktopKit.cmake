# C++ desktop kit: a find_package(RunAnywhere) prefix RCLI can consume
# without compiling this monorepo. Included from the root CMakeLists after
# rac_commons and the engines exist.

if(NOT TARGET rac_commons)
    return()
endif()

if(NOT RAC_SOURCE_DIR)
    set(RAC_SOURCE_DIR "${RAC_ROOT_DIR}")
endif()

set(RAC_PACKAGE_CPP_DESKTOP OFF CACHE BOOL
    "Generate the package-cpp-desktop target (static commons + public headers + IDL)")

# Kit smoke: a tiny C program that only includes public headers. Always
# available when tests are on, so commons stays proven without rcli.
if(RAC_BUILD_TESTS AND EXISTS "${RAC_SOURCE_DIR}/tests/kit/test_cpp_desktop_kit.c")
    add_executable(test_cpp_desktop_kit "${RAC_SOURCE_DIR}/tests/kit/test_cpp_desktop_kit.c")
    target_link_libraries(test_cpp_desktop_kit PRIVATE rac_commons)
    target_compile_features(test_cpp_desktop_kit PRIVATE c_std_11)
    add_test(NAME cpp_desktop_kit_smoke COMMAND test_cpp_desktop_kit)
endif()

if(NOT RAC_PACKAGE_CPP_DESKTOP)
    return()
endif()

set(_kit_genex)
foreach(_t IN ITEMS
        rac_commons
        zlibstatic bz2_bundled
        llama llama-common llama-common-base ggml ggml-base ggml-cpu ggml-metal ggml-cuda ggml-vulkan ggml-blas
        rac_runtime_onnxrt rac_runtime_coreml
        rac_backend_llamacpp rac_backend_onnx rac_backend_sherpa
        rac_backend_mlx rac_backend_neurt rac_backend_cloud rac_backend_qhexrt
        rac_server)
    if(TARGET ${_t})
        get_target_property(_type ${_t} TYPE)
        if(_type STREQUAL "STATIC_LIBRARY" OR _type STREQUAL "SHARED_LIBRARY")
            string(APPEND _kit_genex "$<TARGET_FILE:${_t}>\n")
        endif()
    endif()
endforeach()
# SHARED IMPORTED onnxruntime: TARGET_FILE is the DLL (unusable for
# link.exe). Stage the import library instead.
if(WIN32 AND TARGET onnxruntime)
    get_target_property(_ort_type onnxruntime TYPE)
    if(_ort_type STREQUAL "SHARED_LIBRARY")
        string(APPEND _kit_genex "$<TARGET_LINKER_FILE:onnxruntime>\n")
    endif()
endif()
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/cpp-desktop-libs.txt" CONTENT "${_kit_genex}")

set(_kit_os "${CMAKE_SYSTEM_NAME}")
string(TOLOWER "${_kit_os}" _kit_os)
if(_kit_os STREQUAL "darwin")
    set(_kit_os "macos")
endif()
# Windows reports ARM64 / AMD64; MATCHES is case-sensitive, so a raw
# CMAKE_SYSTEM_PROCESSOR of ARM64 would otherwise keep that spelling and the
# tarball would be windows-ARM64 while release.yml asserts windows-arm64.
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _kit_arch)
if(_kit_arch MATCHES "arm64|aarch64")
    set(_kit_arch "arm64")
elseif(_kit_arch MATCHES "x86_64|amd64")
    set(_kit_arch "x64")
endif()
set(_kit_out "${RAC_SOURCE_DIR}/dist/cpp-desktop-${_kit_os}-${_kit_arch}")

# Values substituted into RunAnywhereConfig.cmake.in via PackageCppDesktop.cmake.
set(RUNANYWHERE_KIT_COMMONS_ARCHIVE "$<TARGET_FILE_NAME:rac_commons>")
set(RUNANYWHERE_KIT_HAS_LLAMACPP FALSE)
set(RUNANYWHERE_KIT_HAS_ONNX FALSE)
set(RUNANYWHERE_KIT_HAS_SHERPA FALSE)
set(RUNANYWHERE_KIT_HAS_MLX FALSE)
set(RUNANYWHERE_KIT_HAS_NEURT FALSE)
set(RUNANYWHERE_KIT_HAS_CLOUD FALSE)
set(RUNANYWHERE_KIT_HAS_QHEXRT FALSE)
set(RUNANYWHERE_KIT_HAS_RAG FALSE)
set(RUNANYWHERE_KIT_HAS_SERVER FALSE)
if(TARGET rac_backend_llamacpp)
    set(RUNANYWHERE_KIT_HAS_LLAMACPP TRUE)
endif()
if(TARGET rac_backend_onnx)
    set(RUNANYWHERE_KIT_HAS_ONNX TRUE)
endif()
if(TARGET rac_backend_sherpa AND RAC_SHERPA_ONNX_AVAILABLE)
    set(RUNANYWHERE_KIT_HAS_SHERPA TRUE)
endif()
if(TARGET rac_backend_mlx)
    set(RUNANYWHERE_KIT_HAS_MLX TRUE)
endif()
if(TARGET rac_backend_neurt)
    set(RUNANYWHERE_KIT_HAS_NEURT TRUE)
endif()
if(TARGET rac_backend_cloud)
    set(RUNANYWHERE_KIT_HAS_CLOUD TRUE)
endif()
if(TARGET rac_backend_qhexrt)
    set(RUNANYWHERE_KIT_HAS_QHEXRT TRUE)
endif()
if(RAC_BACKEND_RAG)
    set(RUNANYWHERE_KIT_HAS_RAG TRUE)
endif()
if(TARGET rac_server)
    set(RUNANYWHERE_KIT_HAS_SERVER TRUE)
endif()
set(RUNANYWHERE_KIT_HAS_DESKTOP_ADAPTER ${RAC_DESKTOP_ADAPTER})
set(RUNANYWHERE_KIT_EXTRA_LIBS "")
set(RUNANYWHERE_KIT_SYSTEM_LIBS "")
if(RAC_PROTOBUF_NAMESPACE_ISOLATED)
    set(RUNANYWHERE_KIT_PROTOBUF_ISOLATED TRUE)
else()
    set(RUNANYWHERE_KIT_PROTOBUF_ISOLATED FALSE)
endif()
if(DEFINED protobuf_fetched_SOURCE_DIR)
    set(RAC_PROTOBUF_INCLUDE_DIR "${protobuf_fetched_SOURCE_DIR}/src")
elseif(Protobuf_INCLUDE_DIRS)
    list(GET Protobuf_INCLUDE_DIRS 0 RAC_PROTOBUF_INCLUDE_DIR)
endif()
if(EXISTS "${CMAKE_BINARY_DIR}/_deps/absl-src/absl/strings/string_view.h")
    set(RAC_ABSL_INCLUDE_DIR "${CMAKE_BINARY_DIR}/_deps/absl-src")
endif()
if(EXISTS "${CMAKE_BINARY_DIR}/_deps/utf8_range-src/utf8_range.h")
    set(RAC_UTF8_RANGE_INCLUDE_DIR "${CMAKE_BINARY_DIR}/_deps/utf8_range-src")
elseif(DEFINED protobuf_fetched_SOURCE_DIR
       AND EXISTS "${protobuf_fetched_SOURCE_DIR}/third_party/utf8_range/utf8_range.h")
    set(RAC_UTF8_RANGE_INCLUDE_DIR "${protobuf_fetched_SOURCE_DIR}/third_party/utf8_range")
endif()

# Plugin ABI from the public header, not a stale comment.
set(_abi_header "${RAC_SOURCE_DIR}/core/include/rac/plugin/rac_plugin_entry.h")
file(STRINGS "${_abi_header}" _abi_line REGEX "#define[ \t]+RAC_PLUGIN_API_VERSION")
string(REGEX REPLACE ".*[^0-9]([0-9]+)u?.*" "\\1" RAC_PLUGIN_API_VERSION "${_abi_line}")
if(NOT RAC_PLUGIN_API_VERSION)
    set(RAC_PLUGIN_API_VERSION "9")
endif()

set(_kit_depends rac_commons)
foreach(_t IN ITEMS
        zlibstatic bz2_bundled
        llama llama-common llama-common-base ggml ggml-base ggml-cpu ggml-metal ggml-cuda ggml-vulkan ggml-blas
        rac_runtime_onnxrt rac_runtime_coreml
        rac_backend_llamacpp rac_backend_onnx rac_backend_sherpa
        rac_backend_mlx rac_backend_neurt rac_backend_cloud rac_backend_qhexrt
        rac_server archive_static)
    if(TARGET ${_t})
        list(APPEND _kit_depends ${_t})
    endif()
endforeach()

add_custom_target(package-cpp-desktop
    COMMAND ${CMAKE_COMMAND}
        -DRAC_SOURCE_DIR=${RAC_SOURCE_DIR}
        -DRAC_BINARY_DIR=${CMAKE_BINARY_DIR}
        -DRAC_VERSION=${RAC_VERSION}
        -DRAC_PLUGIN_API_VERSION=${RAC_PLUGIN_API_VERSION}
        -DRAC_COMMONS_FILE=$<TARGET_FILE:rac_commons>
        -DRAC_KIT_LIBS_FILE=${CMAKE_BINARY_DIR}/cpp-desktop-libs.txt
        -DRAC_KIT_OUT=${_kit_out}
        -DRAC_KIT_OS=${_kit_os}
        -DRAC_KIT_ARCH=${_kit_arch}
        -DRUNANYWHERE_KIT_COMMONS_ARCHIVE=$<TARGET_FILE_NAME:rac_commons>
        -DRUNANYWHERE_KIT_HAS_LLAMACPP=${RUNANYWHERE_KIT_HAS_LLAMACPP}
        -DRUNANYWHERE_KIT_HAS_ONNX=${RUNANYWHERE_KIT_HAS_ONNX}
        -DRUNANYWHERE_KIT_HAS_SHERPA=${RUNANYWHERE_KIT_HAS_SHERPA}
        -DRUNANYWHERE_KIT_HAS_MLX=${RUNANYWHERE_KIT_HAS_MLX}
        -DRUNANYWHERE_KIT_HAS_NEURT=${RUNANYWHERE_KIT_HAS_NEURT}
        -DRUNANYWHERE_KIT_HAS_CLOUD=${RUNANYWHERE_KIT_HAS_CLOUD}
        -DRUNANYWHERE_KIT_HAS_QHEXRT=${RUNANYWHERE_KIT_HAS_QHEXRT}
        -DRUNANYWHERE_KIT_HAS_RAG=${RUNANYWHERE_KIT_HAS_RAG}
        -DRUNANYWHERE_KIT_HAS_SERVER=${RUNANYWHERE_KIT_HAS_SERVER}
        -DRUNANYWHERE_KIT_HAS_DESKTOP_ADAPTER=${RUNANYWHERE_KIT_HAS_DESKTOP_ADAPTER}
        -DRUNANYWHERE_KIT_PROTOBUF_ISOLATED=${RUNANYWHERE_KIT_PROTOBUF_ISOLATED}
        -DRAC_PROTOBUF_INCLUDE_DIR=${RAC_PROTOBUF_INCLUDE_DIR}
        -DRAC_ABSL_INCLUDE_DIR=${RAC_ABSL_INCLUDE_DIR}
        -DRAC_UTF8_RANGE_INCLUDE_DIR=${RAC_UTF8_RANGE_INCLUDE_DIR}
        -P ${RAC_SOURCE_DIR}/cmake/PackageCppDesktop.cmake
    DEPENDS ${_kit_depends}
    VERBATIM
    COMMENT "Staging C++ desktop kit at ${_kit_out}"
)
if(_kit_depends)
    add_dependencies(package-cpp-desktop ${_kit_depends})
endif()

# Tarball next to the prefix for release.yml to pick up.
add_custom_target(package-cpp-desktop-tarball
    COMMAND ${CMAKE_COMMAND} -E make_directory "${RAC_SOURCE_DIR}/dist"
    COMMAND ${CMAKE_COMMAND} -E tar czf
        "${RAC_SOURCE_DIR}/dist/RunAnywhere-cpp-desktop-${_kit_os}-${_kit_arch}-v${RAC_VERSION}.tar.gz"
        --format=gnutar
        "cpp-desktop-${_kit_os}-${_kit_arch}"
    DEPENDS package-cpp-desktop
    WORKING_DIRECTORY "${RAC_SOURCE_DIR}/dist"
    COMMENT "Tarring C++ desktop kit"
)
add_dependencies(package-cpp-desktop-tarball package-cpp-desktop)
