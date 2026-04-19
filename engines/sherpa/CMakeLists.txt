# engines/sherpa/ — L2 plugin wrapping the sherpa-onnx C API.
#
# Real integration strategy: download a pre-built sherpa-onnx release
# tarball for the host platform, extract it, link our plugin against the
# shipped libsherpa-onnx-c-api.
#
# Why pre-built instead of FetchContent from source? Building sherpa-onnx
# from source pulls in openfst + kaldi-decoder, both of which ship pre-
# C++20 headers that fail to compile against newer libc++ / macOS SDK
# (std::shared_ptr::unique removed, allocator::rebind removed,
# directory_entry namespace scope bug). The upstream project ships
# already-linked release tarballs that sidestep all of that — the C API
# is a stable surface we can consume directly.

set(RA_SHERPA_TAG "v1.12.39" CACHE STRING "sherpa-onnx release tag")

# Host detection for the release tarball URL.
if(APPLE)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(_sherpa_triple "osx-arm64")
    else()
        set(_sherpa_triple "osx-x64")
    endif()
elseif(UNIX AND NOT ANDROID)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64")
        set(_sherpa_triple "linux-x64")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
        set(_sherpa_triple "linux-aarch64")
    endif()
elseif(WIN32)
    set(_sherpa_triple "win-x64")
endif()

if(NOT _sherpa_triple)
    message(FATAL_ERROR
        "engines/sherpa: no pre-built sherpa-onnx tarball for this host. "
        "Set RA_SHERPA_PREBUILT_DIR to a manually-extracted release.")
endif()

set(_sherpa_url
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/${RA_SHERPA_TAG}/sherpa-onnx-${RA_SHERPA_TAG}-${_sherpa_triple}-shared.tar.bz2")

include(FetchContent)
FetchContent_Declare(sherpa_prebuilt
    URL             "${_sherpa_url}"
    URL_MD5         ""  # release assets are tag-pinned; skip checksum
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)

# SOURCE_DIR + BINARY_DIR override — we just want the extracted tree.
FetchContent_MakeAvailable(sherpa_prebuilt)

# Discover the C-API header + shared library in the extracted tree.
find_path(RA_SHERPA_INCLUDE_DIR
    NAMES sherpa-onnx/c-api/c-api.h
    PATHS "${sherpa_prebuilt_SOURCE_DIR}/include"
    NO_DEFAULT_PATH
    REQUIRED
)
find_library(RA_SHERPA_C_API_LIB
    NAMES sherpa-onnx-c-api
    PATHS "${sherpa_prebuilt_SOURCE_DIR}/lib"
    NO_DEFAULT_PATH
    REQUIRED
)

# Pre-build ships a dynamic library with runtime deps; collect the
# companion .dylibs / .so's so the plugin's runpath can find them.
file(GLOB _sherpa_runtime_libs
    "${sherpa_prebuilt_SOURCE_DIR}/lib/*.dylib"
    "${sherpa_prebuilt_SOURCE_DIR}/lib/*.so*"
    "${sherpa_prebuilt_SOURCE_DIR}/lib/*.dll")

add_library(sherpa_onnx_c_api SHARED IMPORTED)
set_target_properties(sherpa_onnx_c_api PROPERTIES
    IMPORTED_LOCATION             "${RA_SHERPA_C_API_LIB}"
    INTERFACE_INCLUDE_DIRECTORIES "${RA_SHERPA_INCLUDE_DIR}"
)

ra_add_engine_plugin(sherpa_engine
    SOURCES
        sherpa_plugin.cpp
    DEPS
        sherpa_onnx_c_api
    ABI_VERSION 1
    OUTPUT_NAME runanywhere_sherpa
)

# Copy runtime dylibs next to the plugin so the frontend loader finds them.
set(_sherpa_plugin_out "$<TARGET_FILE_DIR:sherpa_engine>")
foreach(_lib IN LISTS _sherpa_runtime_libs)
    add_custom_command(TARGET sherpa_engine POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${_lib}" "${_sherpa_plugin_out}"
    )
endforeach()

# Bake the plugin dir into the rpath so dlopen finds the runtime libs.
if(APPLE)
    set_target_properties(sherpa_engine PROPERTIES
        BUILD_WITH_INSTALL_RPATH ON
        INSTALL_RPATH "@loader_path")
elseif(UNIX)
    set_target_properties(sherpa_engine PROPERTIES
        BUILD_WITH_INSTALL_RPATH ON
        INSTALL_RPATH "\$ORIGIN")
endif()

message(STATUS "engines/sherpa: linked against sherpa-onnx ${RA_SHERPA_TAG} (${_sherpa_triple})")
