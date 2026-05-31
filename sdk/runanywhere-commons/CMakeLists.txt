# Must match VERSIONS::MIN_CMAKE_VERSION (3.30). Required for FetchContent's
# FIND_PACKAGE_ARGS and DOWNLOAD_EXTRACT_TIMESTAMP keywords (both added in 3.24)
# used by the protobuf and ONNX Runtime fetches below.
cmake_minimum_required(VERSION 3.24)

# Read version from VERSION file
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" VERSION_CONTENT)
string(STRIP "${VERSION_CONTENT}" RAC_VERSION)

project(RunAnywhereCommons
    VERSION ${RAC_VERSION}
    LANGUAGES CXX C
    DESCRIPTION "RunAnywhere Commons - Standalone infrastructure library for ML inference SDKs"
)

# =============================================================================
# ABOUT THIS LIBRARY
# =============================================================================
#
# rac_commons is a STANDALONE library that provides:
#   - Logging, error handling, and event tracking
#   - Service registry and provider infrastructure
#   - Model management (download strategies, storage)
#   - Platform backend (Apple Foundation Models, System TTS) on Apple platforms
# =============================================================================

# =============================================================================
# OPTIONS
# =============================================================================

option(RAC_BUILD_JNI "Build JNI bridge for Android/JVM" OFF)
option(RAC_BUILD_TESTS "Build unit tests" OFF)
option(RAC_BUILD_SHARED "Build shared libraries" OFF)
option(RAC_BUILD_PLATFORM "Build platform backend (Apple Foundation Models, System TTS)" ON)
option(RAC_BUILD_BACKENDS "Build ML backends (LlamaCPP, ONNX, WhisperCPP, RAG)" OFF)

# Ensure EMSCRIPTEN is always defined so
# generator-expression references like $<BOOL:${EMSCRIPTEN}> below do not trip
# CMake's --warn-uninitialized check on native (non-Emscripten) builds. The
# Emscripten toolchain file sets EMSCRIPTEN=1 itself; we only paper over the
# native case where the variable is otherwise unset.
if(NOT DEFINED EMSCRIPTEN)
    set(EMSCRIPTEN "")
endif()

# Per-engine RAC_BACKEND_<name> options now live in engines/<name>/CMakeLists.txt.
# Only commons-local backends (RAG pipeline) declare their option here.
option(RAC_BACKEND_RAG "Build RAG pipeline (USearch vector search)" ON)

# Emscripten: RAG itself only depends on USearch + nlohmann_json (header-only)
# and the rac_embeddings_service vtable — it does NOT directly include
# onnxruntime headers. The ONNX embedding provider lives in engines/onnx/ and
# is folded into rac_backend_onnx when that engine is enabled. On WASM the
# matched-set ORT + Sherpa archives ship under third_party/onnxruntime-wasm/
# and third_party/sherpa-onnx-wasm/ (via @runanywhere/web-onnx), so RAG can
# safely default ON whenever the ONNX backend is requested for the same
# build.
#
# RAC_WASM_RAG_STANDALONE: the Web Docs/RAG tab
# ships against the auto-loaded llamacpp WASM bundle, which is built with
# RAC_BACKEND_ONNX=OFF. Forcing RAC_BACKEND_RAG=OFF on that artifact strips
# the `rac_rag_*_proto` exports from the JS glue, so the TS bridge can't
# even reach the runtime backend-availability check. Allow the build script
# to opt the llamacpp WASM target into shipping the RAG proto-byte symbols
# (their bodies live entirely inside librac_commons via the OBJECT-library
# fold-in below); the runtime layer surfaces a clear
# RAC_ERROR_FEATURE_NOT_AVAILABLE when the embeddings provider is missing,
# which matches the non-WASM platform contract.
option(RAC_WASM_RAG_STANDALONE "Emit rac_rag_* exports on Emscripten even without RAC_BACKEND_ONNX (runtime fails fast if no embeddings provider is registered)" OFF)
if(EMSCRIPTEN AND NOT RAC_BACKEND_ONNX AND NOT RAC_WASM_RAG_STANDALONE)
    set(RAC_BACKEND_RAG OFF CACHE BOOL "RAG requires ONNX embeddings on Emscripten; force off when RAC_BACKEND_ONNX is not enabled" FORCE)
endif()
option(RAC_BUILD_SERVER "Build OpenAI-compatible HTTP server (runanywhere-server)" OFF)

# Opt-in proto regeneration.
#
# The 23 `*.pb.cc` / `*.pb.h` pairs under `src/generated/proto/` are committed
# so CI / release builds never need a working protoc on-path. However, the
# canonical `.proto` sources live at repo-root `idl/*.proto`, and drift
# between the two is a recurring problem.
#
# With RAC_REGENERATE_PROTO=ON, the build reruns `idl/codegen/generate_cpp.sh`
# whenever any `idl/*.proto` file is newer than `src/generated/proto/.gen-stamp`,
# writing fresh `.pb.{cc,h}` back into the committed tree. Dev loop only —
# CI stays OFF so it compiles exactly what is in git.
option(RAC_REGENERATE_PROTO "Regenerate C++ proto sources from idl/*.proto when out of date (dev only)" OFF)

# =============================================================================
# C++ CONFIGURATION
# =============================================================================

# C++20 is required because MSVC does not implement C++17 designated initializers
# (e.g. `struct S s = {.field = value};`) — the codebase uses them in several
# places (service vtable registration, config structs). All supported compilers
# (GCC 10+, Clang 11+, MSVC 19.28+ / VS 2019 16.8+) support C++20.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Workaround for React Native 0.83 std::format incompatibility on Android NDK 26
# Add a define to suppress the issue in React Native's graphicsConversions.h
if(ANDROID)
    add_compile_definitions(YG_ENABLE_STANDARD_LIBRARY_SUPPORT=0)
    # Suppress std::format usage by adding this flag
    add_compile_options(-fno-strict-aliasing)
endif()

# Export compile commands for clang-tidy
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Add cmake modules path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Load versions from VERSIONS file (single source of truth)
include(LoadVersions)

# Make project version available to subdirectories
set(RAC_PROJECT_VERSION "${RAC_VERSION}" CACHE STRING "Project version" FORCE)

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

if(EMSCRIPTEN)
    set(RAC_PLATFORM_WASM TRUE)
    set(RAC_PLATFORM_NAME "Emscripten")
elseif(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(RAC_PLATFORM_IOS TRUE)
    set(RAC_PLATFORM_NAME "iOS")
elseif(ANDROID)
    set(RAC_PLATFORM_ANDROID TRUE)
    set(RAC_PLATFORM_NAME "Android")
elseif(APPLE)
    set(RAC_PLATFORM_MACOS TRUE)
    set(RAC_PLATFORM_NAME "macOS")
elseif(UNIX)
    set(RAC_PLATFORM_LINUX TRUE)
    set(RAC_PLATFORM_NAME "Linux")
elseif(WIN32)
    set(RAC_PLATFORM_WINDOWS TRUE)
    set(RAC_PLATFORM_NAME "Windows")
else()
    set(RAC_PLATFORM_NAME "Unknown")
endif()

message(STATUS "Platform: ${RAC_PLATFORM_NAME}")

# =============================================================================
# SHARED DEPENDENCIES (FetchContent)
# =============================================================================

include(FetchContent)

# Cross-compilation targets that bundle zlib/BZip2 need a stable archive
# output directory so downstream FetchContent projects can consume concrete
# file paths instead of unresolved logical library names.
# iOS is added here too because we now
# force-bundle zlib for iOS slices (see comment below); libarchive's internal
# find_package(ZLIB) needs a concrete archive path on cross-compile targets
# the same way Android/Emscripten do.
if(MSVC OR ANDROID OR EMSCRIPTEN OR IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(RAC_BUNDLED_LIB_DIR "${CMAKE_BINARY_DIR}/_bundled_libs")
endif()

# nlohmann/json - header-only JSON library (used by JNI, backends, server)
if(NOT DEFINED NLOHMANN_JSON_VERSION)
    set(NLOHMANN_JSON_VERSION "3.11.3")
endif()
FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG v${NLOHMANN_JSON_VERSION}
    GIT_SHALLOW TRUE
)
set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(nlohmann_json)

# Make nlohmann_json headers available project-wide for IDE indexing
# (nlohmann_json_SOURCE_DIR is set by FetchContent_MakeAvailable)
include_directories(SYSTEM ${nlohmann_json_SOURCE_DIR}/include)

# libarchive - streaming archive extraction (ZIP, TAR.GZ, TAR.BZ2)
# Used for native model archive extraction across all platforms
if(NOT DEFINED LIBARCHIVE_VERSION)
    set(LIBARCHIVE_VERSION "3.8.1")
endif()

# -----------------------------------------------------------------------------
# Zlib: Bundle from source when system zlib is not available.
# Windows (MSVC) and some cross-compilation targets don't ship zlib.
# We try system first; if not found, build from source so libarchive gets it.
#
# Also force bundled zlib for iOS and
# Android cross-compilation. Without this, libarchive's own
# `FIND_PACKAGE(ZLIB 1.2.1)` inside its FetchContent CMake project occasionally
# fails when cross-compiling for iOS / iOS-simulator slices (the host toolchain
# discovery doesn't reach the iOS SDK's libz.tbd reliably under every Xcode +
# CMake combo). When that find fails, libarchive compiles with HAVE_ZLIB_H
# UNDEFINED, which silently drops the built-in inflate path and falls back to
# `program("gzip -d")` — a fork+exec of /usr/bin/gzip that is blocked by the
# iOS app sandbox. The result is that every .tar.gz model extraction (Sherpa
# Whisper Tiny, SmolVLM, Piper TTS) fails on Swift iOS + Flutter iOS with an
# obscure "child process" error. Forcing bundled zlib guarantees a known-good
# static zlib is on the libarchive include + link path, so its config.h
# defines HAVE_ZLIB_H and the in-process inflate filter wins the bidder
# competition before the program() fallback can register.
# -----------------------------------------------------------------------------
set(_RAC_FORCE_BUNDLED_ZLIB OFF)
if(EMSCRIPTEN OR ANDROID OR IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(_RAC_FORCE_BUNDLED_ZLIB ON)
endif()

# Defense-in-depth normalization of the
# ZLIB_VERSION cache. LoadVersions.cmake now strips a leading 'v' from
# ZLIB_VERSION specifically (so engines that re-`include(LoadVersions)` don't
# restore the raw form). Re-assert the strip here in case a future caller
# passes `-DZLIB_VERSION=v1.3.2` on the command line. Also set
# ZLIB_VERSION_STRING (the legacy alias CMake's FindZLIB sometimes consults)
# so both stay in lockstep.
#
# RAC_ZLIB_VERSION (with prefix) holds the original GIT_TAG-form ('v1.3.2')
# for FetchContent_Declare below; do not overwrite that one.
if(DEFINED ZLIB_VERSION AND ZLIB_VERSION MATCHES "^v")
    string(REGEX REPLACE "^v" "" _RAC_ZLIB_VERSION_NUMERIC "${ZLIB_VERSION}")
    set(ZLIB_VERSION "${_RAC_ZLIB_VERSION_NUMERIC}" CACHE STRING "" FORCE)
    message(STATUS "Pre-normalized ZLIB_VERSION 'v${_RAC_ZLIB_VERSION_NUMERIC}' -> '${_RAC_ZLIB_VERSION_NUMERIC}' "
                   "(GIT_TAG '${RAC_ZLIB_VERSION}' preserved on RAC_ZLIB_VERSION for FetchContent) "
                   "so libarchive's find_package(ZLIB 1.2.1) accepts it.")
endif()
if(NOT DEFINED ZLIB_VERSION_STRING OR ZLIB_VERSION_STRING MATCHES "^v")
    if(DEFINED ZLIB_VERSION)
        set(ZLIB_VERSION_STRING "${ZLIB_VERSION}" CACHE STRING "" FORCE)
    endif()
endif()

if(_RAC_FORCE_BUNDLED_ZLIB)
    message(STATUS "${RAC_PLATFORM_NAME}: forcing bundled zlib (cross-compile target)")
    set(ZLIB_FOUND FALSE)
else()
    find_package(ZLIB QUIET)
endif()

if(NOT ZLIB_FOUND)
    message(STATUS "System zlib not found — bundling from source (GIT_TAG=${RAC_ZLIB_VERSION})...")
    FetchContent_Declare(
        zlib_src
        GIT_REPOSITORY https://github.com/madler/zlib.git
        GIT_TAG        ${RAC_ZLIB_VERSION}
        GIT_SHALLOW    TRUE
    )
    # Prevent zlib from installing or building examples
    set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_LIBRARIES ON CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_HEADERS ON CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_FILES ON CACHE BOOL "" FORCE)
    # Save and restore BUILD_SHARED_LIBS
    set(_SAVED_BSL_ZLIB ${BUILD_SHARED_LIBS})
    set(BUILD_SHARED_LIBS OFF)
    FetchContent_MakeAvailable(zlib_src)
    set(BUILD_SHARED_LIBS ${_SAVED_BSL_ZLIB})

    if((ANDROID OR EMSCRIPTEN OR IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS") AND TARGET zlibstatic)
        set_target_properties(zlibstatic PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY "${RAC_BUNDLED_LIB_DIR}"
        )
        set(_RAC_ZLIB_LIBRARY_PATH "${RAC_BUNDLED_LIB_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}z${CMAKE_STATIC_LIBRARY_SUFFIX}")
    endif()

    # Set cache variables so libarchive/curl's find_package(ZLIB) picks up our
    # build. Android/Emscripten/iOS need the concrete archive path here;
    # passing the logical target name through cache variables leaks raw
    # `zlibstatic` / `-lzlibstatic` entries into downstream link lines, and
    # libarchive's internal find_package(ZLIB 1.2.1) reject that.
    set(ZLIB_INCLUDE_DIR "${zlib_src_SOURCE_DIR};${zlib_src_BINARY_DIR}" CACHE PATH "" FORCE)
    set(ZLIB_INCLUDE_DIRS "${zlib_src_SOURCE_DIR};${zlib_src_BINARY_DIR}" CACHE PATH "" FORCE)
    if(ANDROID OR EMSCRIPTEN OR IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
        set(ZLIB_LIBRARY "${_RAC_ZLIB_LIBRARY_PATH}" CACHE FILEPATH "" FORCE)
        set(ZLIB_LIBRARY_RELEASE "${_RAC_ZLIB_LIBRARY_PATH}" CACHE FILEPATH "" FORCE)
        set(ZLIB_LIBRARIES "${_RAC_ZLIB_LIBRARY_PATH}" CACHE FILEPATH "" FORCE)
    else()
        set(ZLIB_LIBRARY zlibstatic CACHE STRING "" FORCE)
        set(ZLIB_LIBRARIES zlibstatic CACHE STRING "" FORCE)
    endif()
    set(ZLIB_FOUND TRUE CACHE BOOL "" FORCE)
    # VERSIONS file pins ZLIB_VERSION=v1.3.2 (the GIT_TAG
    # form madler/zlib uses). libarchive's bundled CMake module runs
    # `find_package(ZLIB 1.2.1)`, which dispatches to CMake's FindZLIB module
    # with `VERSION_VAR ZLIB_VERSION`. FindZLIB normally derives ZLIB_VERSION
    # from `${ZLIB_INCLUDE_DIR}/zlib.h`, but our ZLIB_INCLUDE_DIR above is a
    # semicolon-list (`src-dir;build-dir`) which fails its EXISTS check, so the
    # version-extraction branch is skipped and ZLIB_VERSION keeps the value
    # cached by LoadVersions.cmake from the VERSIONS file — the raw GIT_TAG
    # `v1.3.2`. CMake's numeric comparator then rejects that as unsuitable for
    # the `>= 1.2.1` requirement, HAVE_ZLIB_H is left undefined, and libarchive
    # falls back to archive_read_support_filter_program("gzip -d") — the very
    # fallback this whole block exists to prevent on iOS. Force a purely
    # numeric form into both the VERSION_VAR (ZLIB_VERSION) and the legacy
    # ZLIB_VERSION_STRING so FindZLIB hands libarchive an acceptable version.
    string(REGEX REPLACE "^v" "" _RAC_ZLIB_VERSION_NUMERIC "${ZLIB_VERSION}")
    set(ZLIB_VERSION "${_RAC_ZLIB_VERSION_NUMERIC}" CACHE STRING "" FORCE)
    set(ZLIB_VERSION_STRING "${_RAC_ZLIB_VERSION_NUMERIC}" CACHE STRING "" FORCE)
    # Create an imported ZLIB::ZLIB target that points to our zlibstatic
    if(NOT TARGET ZLIB::ZLIB)
        add_library(ZLIB::ZLIB ALIAS zlibstatic)
    endif()
    # On MSVC, set zlibstatic output to a known location so the linker can find it
    if(MSVC AND TARGET zlibstatic)
        set_target_properties(zlibstatic PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib"
            ARCHIVE_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/lib"
        )
    endif()
    message(STATUS "Bundled zlib ready (${ZLIB_VERSION})")
else()
    message(STATUS "Using system zlib: ${ZLIB_LIBRARIES}")
endif()

# -----------------------------------------------------------------------------
# BZip2: Bundle from source for cross-compilation targets
# Android NDK and Emscripten don't ship libbz2. macOS/iOS have it in the SDK.
# We try system first; if not found, build from source so libarchive gets it.
#
# Also force bundled BZip2 on iOS for the
# same reason as zlib above. The Apple iOS SDK does ship libbz2.dylib, but
# libarchive's `program("bzip2 -d")` fallback path (analogous to gzip) is
# similarly blocked by the iOS sandbox. Forcing the bundled in-process
# bzlib decoder guarantees `HAVE_BZLIB_H` is defined in libarchive's config.h,
# which keeps the bidder competition resolved to the in-process filter and
# never registers the program() fallback.
# -----------------------------------------------------------------------------
set(_RAC_FORCE_BUNDLED_BZIP2 OFF)
if(ANDROID OR EMSCRIPTEN OR IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(_RAC_FORCE_BUNDLED_BZIP2 ON)
endif()

if(_RAC_FORCE_BUNDLED_BZIP2)
    message(STATUS "${RAC_PLATFORM_NAME}: forcing bundled BZip2")
    set(BZIP2_FOUND FALSE)
else()
    find_package(BZip2 QUIET)
endif()

if(NOT BZIP2_FOUND)
    message(STATUS "System BZip2 not found — bundling from source for cross-compilation...")
    FetchContent_Declare(
        bzip2_src
        URL https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VERSION}.tar.gz
        URL_HASH SHA256=ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269
    )
    FetchContent_MakeAvailable(bzip2_src)

    add_library(bz2_bundled STATIC
        ${bzip2_src_SOURCE_DIR}/blocksort.c
        ${bzip2_src_SOURCE_DIR}/huffman.c
        ${bzip2_src_SOURCE_DIR}/crctable.c
        ${bzip2_src_SOURCE_DIR}/randtable.c
        ${bzip2_src_SOURCE_DIR}/compress.c
        ${bzip2_src_SOURCE_DIR}/decompress.c
        ${bzip2_src_SOURCE_DIR}/bzlib.c
    )
    target_include_directories(bz2_bundled PUBLIC ${bzip2_src_SOURCE_DIR})
    set_target_properties(bz2_bundled PROPERTIES POSITION_INDEPENDENT_CODE ON)

    if((ANDROID OR EMSCRIPTEN OR IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS") AND TARGET bz2_bundled)
        set_target_properties(bz2_bundled PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY "${RAC_BUNDLED_LIB_DIR}"
        )
        set(_RAC_BZIP2_LIBRARY_PATH "${RAC_BUNDLED_LIB_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}bz2_bundled${CMAKE_STATIC_LIBRARY_SUFFIX}")
    endif()

    # Set cache variables so libarchive's find_package(BZip2) picks up our
    # build. Android/Emscripten/iOS again need the concrete archive path.
    set(BZIP2_INCLUDE_DIR "${bzip2_src_SOURCE_DIR}" CACHE PATH "" FORCE)
    if(ANDROID OR EMSCRIPTEN OR IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
        set(BZIP2_LIBRARY "${_RAC_BZIP2_LIBRARY_PATH}" CACHE FILEPATH "" FORCE)
        set(BZIP2_LIBRARY_RELEASE "${_RAC_BZIP2_LIBRARY_PATH}" CACHE FILEPATH "" FORCE)
        set(BZIP2_LIBRARIES "${_RAC_BZIP2_LIBRARY_PATH}" CACHE FILEPATH "" FORCE)
    else()
        set(BZIP2_LIBRARIES bz2_bundled CACHE STRING "" FORCE)
    endif()
    set(BZIP2_FOUND TRUE CACHE BOOL "" FORCE)
    # On MSVC, set output to a known location so the linker can find it
    if(MSVC AND TARGET bz2_bundled)
        set_target_properties(bz2_bundled PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib"
            ARCHIVE_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/lib"
        )
    endif()
    message(STATUS "Bundled BZip2 ready (v${BZIP2_VERSION})")
else()
    message(STATUS "Using system BZip2: ${BZIP2_LIBRARIES}")
endif()

FetchContent_Declare(
    libarchive
    GIT_REPOSITORY https://github.com/libarchive/libarchive.git
    GIT_TAG v${LIBARCHIVE_VERSION}
    GIT_SHALLOW TRUE
)
# Disable everything except the static library and the formats we need
set(ENABLE_MBEDTLS OFF CACHE BOOL "" FORCE)
set(ENABLE_NETTLE OFF CACHE BOOL "" FORCE)
set(ENABLE_OPENSSL OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBB2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZ4 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZO OFF CACHE BOOL "" FORCE)
set(ENABLE_LZMA OFF CACHE BOOL "" FORCE)     # tar.xz not currently used by any model
set(ENABLE_ZSTD OFF CACHE BOOL "" FORCE)
set(ENABLE_ZLIB ON CACHE BOOL "" FORCE)      # Needed for tar.gz and zip
set(ENABLE_BZip2 ON CACHE BOOL "" FORCE)     # Needed for tar.bz2 (k2-fsa models)
set(ENABLE_LIBXML2 OFF CACHE BOOL "" FORCE)
set(ENABLE_EXPAT OFF CACHE BOOL "" FORCE)
set(ENABLE_PCREPOSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_PCRE2POSIX OFF CACHE BOOL "" FORCE)
# libarchive's ENABLE_LIBGCC gates a `find_library(GCC_LIBRARY gcc)` / `-lgcc`
# link. Needed on MSVC for the bundled runtime; a no-op on Apple/Clang (no
# libgcc); on Linux+GCC keep it OFF so we don't add an explicit -lgcc to the
# link line (it's pulled in implicitly and adding it can cause duplicate-symbol
# warnings in static configurations).
if(MSVC)
    set(ENABLE_LIBGCC ON CACHE BOOL "" FORCE)
else()
    set(ENABLE_LIBGCC OFF CACHE BOOL "" FORCE)
endif()
set(ENABLE_CNG OFF CACHE BOOL "" FORCE)
set(ENABLE_TAR OFF CACHE BOOL "" FORCE)      # Don't build bsdtar binary
set(ENABLE_CPIO OFF CACHE BOOL "" FORCE)     # Don't build bsdcpio binary
set(ENABLE_CAT OFF CACHE BOOL "" FORCE)      # Don't build bsdcat binary
set(ENABLE_UNZIP OFF CACHE BOOL "" FORCE)    # Don't build bsdunzip binary
set(ENABLE_TEST OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(ENABLE_ACL OFF CACHE BOOL "" FORCE)
set(ENABLE_XATTR OFF CACHE BOOL "" FORCE)
set(ENABLE_ICONV OFF CACHE BOOL "" FORCE)
# Save and restore BUILD_SHARED_LIBS since libarchive respects it
# Use DEFINED check to avoid uninitialized-variable warning when not set upstream.
if(DEFINED BUILD_SHARED_LIBS)
    set(_SAVED_BUILD_SHARED_LIBS "${BUILD_SHARED_LIBS}")
    set(_HAD_BUILD_SHARED_LIBS TRUE)
else()
    set(_HAD_BUILD_SHARED_LIBS FALSE)
endif()
set(BUILD_SHARED_LIBS OFF)
FetchContent_MakeAvailable(libarchive)
if(_HAD_BUILD_SHARED_LIBS)
    set(BUILD_SHARED_LIBS "${_SAVED_BUILD_SHARED_LIBS}")
else()
    unset(BUILD_SHARED_LIBS)
endif()

if(TARGET bz2_bundled AND TARGET archive_static)
    target_link_libraries(archive_static bz2_bundled)
endif()

# Link bundled zlib to libarchive if we built it from source
if(TARGET zlibstatic AND TARGET archive_static)
    target_link_libraries(archive_static zlibstatic)
    target_include_directories(archive_static PRIVATE ${zlib_src_SOURCE_DIR} ${zlib_src_BINARY_DIR})
endif()

# -----------------------------------------------------------------------------
# Configure-time assertion that libarchive's
# generated config.h has HAVE_ZLIB_H defined on every cross-compile target
# where the platform CANNOT fork+exec /usr/bin/gzip. Without this, an
# accidentally-undefined HAVE_ZLIB_H silently re-enables the
# archive_read_support_filter_program("gzip -d") fallback inside libarchive's
# filter_gzip.c — which iOS app sandboxes and Emscripten/WASM both block.
#
# This was fixed for iOS by:
#   (a) forcing bundled zlib for IOS|ANDROID|EMSCRIPTEN
#   (b) stripping the 'v' prefix from ZLIB_VERSION so libarchive's internal
#       find_package(ZLIB 1.2.1) version check succeeds
#
# But the cross-compile cache is order-sensitive (the web lane once shipped
# a build with HAVE_ZLIB_H still undefined because the libarchive subbuild
# already ran before the v-strip lines executed in a stale FetchContent
# state). Surface that class of regression here, while we still have a CMake
# error path, rather than after the .wasm has shipped and OPFS extraction
# fails inside the browser.
# -----------------------------------------------------------------------------
if(ANDROID OR EMSCRIPTEN OR IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(_RAC_LIBARCHIVE_CONFIG_H "${libarchive_BINARY_DIR}/config.h")
    if(EXISTS "${_RAC_LIBARCHIVE_CONFIG_H}")
        file(READ "${_RAC_LIBARCHIVE_CONFIG_H}" _RAC_LIBARCHIVE_CONFIG_CONTENTS)
        # Look for an active `#define HAVE_ZLIB_H 1` (NOT `/* #undef HAVE_ZLIB_H */`).
        if(NOT _RAC_LIBARCHIVE_CONFIG_CONTENTS MATCHES "#define HAVE_ZLIB_H[ \t]+1")
            message(FATAL_ERROR
                "libarchive's generated config.h "
                "is missing #define HAVE_ZLIB_H 1 on ${RAC_PLATFORM_NAME}. "
                "libarchive will fall back to archive_read_support_filter_program(\"gzip -d\"), "
                "which iOS sandbox and Emscripten/WASM both block, so every .tar.gz "
                "extraction will fail at runtime.\n"
                "  config.h path: ${_RAC_LIBARCHIVE_CONFIG_H}\n"
                "  ZLIB_VERSION cache: ${ZLIB_VERSION}\n"
                "  ZLIB_LIBRARY cache: ${ZLIB_LIBRARY}\n"
                "  ZLIB_INCLUDE_DIR cache: ${ZLIB_INCLUDE_DIR}\n"
                "Fix: ensure ZLIB_VERSION is a plain numeric string (e.g. 1.3.2, "
                "NOT v1.3.2) and re-configure from a clean build dir. See the "
                "v-strip block above for the canonical fix.")
        endif()
        # Same check for bzip2 — the iOS sandbox + Emscripten also block
        # program(\"bzip2 -d\"), and the same find_package(BZip2) version
        # quirks could leave HAVE_BZLIB_H undefined. Emscripten's iter-2
        # cache already shows this can fail independently.
        if(NOT _RAC_LIBARCHIVE_CONFIG_CONTENTS MATCHES "#define HAVE_BZLIB_H[ \t]+1")
            message(FATAL_ERROR
                "libarchive's generated config.h "
                "is missing #define HAVE_BZLIB_H 1 on ${RAC_PLATFORM_NAME}. "
                "libarchive will fall back to archive_read_support_filter_program(\"bzip2 -d\"), "
                "which iOS sandbox and Emscripten/WASM both block.\n"
                "  config.h path: ${_RAC_LIBARCHIVE_CONFIG_H}\n"
                "Fix: confirm bz2_bundled was built and BZIP2_* cache vars point at it.")
        endif()
        message(STATUS "libarchive config.h verified: HAVE_ZLIB_H + HAVE_BZLIB_H both defined (${RAC_PLATFORM_NAME})")
    else()
        message(WARNING
            "libarchive config.h not yet generated at ${_RAC_LIBARCHIVE_CONFIG_H} — "
            "skipping HAVE_ZLIB_H assertion. Re-configure once libarchive has materialized "
            "its build dir to enable the regression guard.")
    endif()
endif()

# On MSVC multi-config generators, libarchive references "zlibstatic.lib" and
# "bz2_bundled.lib" by bare filename. The linker can't find them because they
# are built into <config>/ subdirectories. Fix: redirect their output to a
# single known directory and add it to the global linker search path.
#
# The same issue surfaces under Android (NDK + Ninja + ld.lld) and Emscripten:
# libarchive's internal find_package(BZip2) stores BZIP2_LIBRARIES as the bare
# string "bz2_bundled", which its build then emits into the transitive link
# line as "-lbz2_bundled" rather than a full path to libbz2_bundled.a. Pin the
# archive to a known directory and add it to the linker search path so the
# `-l` lookup succeeds.
if(MSVC)
    foreach(_cfg Release Debug RelWithDebInfo MinSizeRel)
        string(TOUPPER "${_cfg}" _CFG)
        if(TARGET zlibstatic)
            set_target_properties(zlibstatic PROPERTIES
                ARCHIVE_OUTPUT_DIRECTORY_${_CFG} "${RAC_BUNDLED_LIB_DIR}")
        endif()
        if(TARGET bz2_bundled)
            set_target_properties(bz2_bundled PROPERTIES
                ARCHIVE_OUTPUT_DIRECTORY_${_CFG} "${RAC_BUNDLED_LIB_DIR}")
        endif()
    endforeach()
    link_directories("${RAC_BUNDLED_LIB_DIR}")
elseif(ANDROID OR EMSCRIPTEN OR IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    if(TARGET bz2_bundled)
        set_target_properties(bz2_bundled PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY "${RAC_BUNDLED_LIB_DIR}")
    endif()
    if(TARGET zlibstatic)
        set_target_properties(zlibstatic PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY "${RAC_BUNDLED_LIB_DIR}")
    endif()
    link_directories("${RAC_BUNDLED_LIB_DIR}")
endif()

message(STATUS "libarchive ready (v${LIBARCHIVE_VERSION})")

# =============================================================================
# HTTP transport (libcurl removed)
# =============================================================================
# The native `rac_http_client_*` C ABI no longer bundles libcurl or any
# TLS backend. Every SDK registers a platform HTTP transport adapter
# via `rac_http_transport_register` during init (OkHttp on Android,
# URLSession on Apple, dart:io on Flutter, emscripten_fetch / JS fetch
# on WASM, JSI fetch on RN). The default client implementation in
# `src/infrastructure/http/rac_http_client_default.cpp` dispatches
# every public call through the registered vtable.
#
# No CURL FetchContent. No mbedTLS. No CA bundle. TLS trust comes from
# whatever stack the adapter uses (the OS system store on every native
# target, the browser on WASM).

# =============================================================================
# SERVER DEPENDENCIES (FetchContent)
# =============================================================================

if(RAC_BUILD_SERVER)
    # cpp-httplib - header-only HTTP library (same as llama.cpp uses)
    FetchContent_Declare(
        cpp-httplib
        GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
        GIT_TAG ${CPPHTTPLIB_VERSION}
        GIT_SHALLOW TRUE
    )

    message(STATUS "Fetching server dependencies (cpp-httplib)...")
    FetchContent_MakeAvailable(cpp-httplib)
    message(STATUS "Server dependencies ready")
endif()

# =============================================================================
# COMPILER FLAGS
# =============================================================================

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    add_compile_options(-Wall -Wextra -Wpedantic -Wno-unused-parameter)
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        add_compile_options(-O3 -DNDEBUG)
        add_compile_options(-fvisibility=hidden)
        add_compile_options(-ffunction-sections -fdata-sections)
    endif()
elseif(MSVC)
    # /W3 = reasonable warning level, /utf-8 = source/execution charset
    # /Zc:__cplusplus = report correct __cplusplus value
    # /EHsc = standard C++ exception handling
    add_compile_options(/W3 /utf-8 /Zc:__cplusplus /EHsc)
    # Suppress common harmless warnings in third-party code
    add_compile_options(/wd4244 /wd4267 /wd4996)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS NOMINMAX WIN32_LEAN_AND_MEAN)
    # Use generator expressions instead of CMAKE_BUILD_TYPE so Release flags
    # apply correctly with multi-config generators (Visual Studio), where
    # CMAKE_BUILD_TYPE is empty at configure time and the config is selected
    # at build time via --config Release.
    add_compile_options(
        $<$<CONFIG:Release>:/O2>
        $<$<CONFIG:Release>:/DNDEBUG>
    )
endif()

# =============================================================================
# 16KB Page Alignment for Android 15+ (API 35) Compliance
# Required starting November 1, 2025 for Google Play submissions
# All shared libraries must have PT_LOAD segments aligned to 16KB
# =============================================================================
if(ANDROID)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384")
    message(STATUS "Enabled 16KB page alignment for Android (Google Play requirement)")
endif()

# =============================================================================
# AUTO-GENERATE DEVELOPMENT CONFIG IF MISSING
# =============================================================================
# development_config.cpp is git-ignored because it can contain secrets.
# For CI builds or fresh checkouts, we auto-generate a stub from the template.

set(DEV_CONFIG_FILE "${CMAKE_CURRENT_SOURCE_DIR}/src/infrastructure/network/development_config.cpp")
set(DEV_CONFIG_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/src/infrastructure/network/development_config.cpp.template")

if(NOT EXISTS "${DEV_CONFIG_FILE}")
    if(EXISTS "${DEV_CONFIG_TEMPLATE}")
        message(STATUS "development_config.cpp not found, generating stub from template...")
        file(READ "${DEV_CONFIG_TEMPLATE}" DEV_CONFIG_CONTENT)
        file(WRITE "${DEV_CONFIG_FILE}" "${DEV_CONFIG_CONTENT}")
        message(STATUS "Generated: ${DEV_CONFIG_FILE}")
    else()
        message(FATAL_ERROR "Neither development_config.cpp nor .template found!")
    endif()
endif()

# =============================================================================
# SOURCE FILES
# =============================================================================

# Core sources - logging, errors, time, memory, events
set(RAC_CORE_SOURCES
    src/core/rac_core.cpp
    src/core/rac_error.cpp
    src/core/rac_time.cpp
    src/core/rac_benchmark.cpp
    src/core/rac_benchmark_metrics.cpp
    src/core/rac_benchmark_log.cpp
    src/core/rac_benchmark_stats.cpp
    src/core/rac_memory.cpp
    src/core/rac_logger.cpp
    src/infrastructure/logging/log_redact.cpp
    src/core/rac_audio_utils.cpp
    src/core/component_types.cpp
    src/core/events.cpp
    src/core/sdk_state.cpp
    src/core/rac_structured_error.cpp
    src/core/capabilities/lifecycle_manager.cpp
    # model_lifecycle.cpp was split per SRP into
    # five TUs (proto<->C translation, artifact resolution, auto-download,
    # per-modality accessors, and the C ABI entry points). All five share
    # the internal layout declared in `model_lifecycle_internal.h`.
    src/core/model_lifecycle.cpp
    src/core/model_lifecycle_translation.cpp
    src/core/model_lifecycle_resolve.cpp
    src/core/model_lifecycle_download.cpp
    src/core/model_lifecycle_accessors.cpp
    src/core/rac_error_model.cpp
    src/core/rac_error_proto.cpp
    src/foundation/rac_proto_buffer.cpp
    # Canonical two-phase SDK init ABI. Wraps existing rac_state /
    # rac_auth / rac_device_manager / rac_model_assignment internals behind
    # one rac_sdk_init_phase{1,2}_proto + rac_sdk_retry_http_proto surface so
    # platform SDKs collapse their duplicated step list.
    src/lifecycle/sdk_init.cpp
)

# Infrastructure sources - registry, model management, network, telemetry
set(RAC_INFRASTRUCTURE_SOURCES
    src/infrastructure/events/event_publisher.cpp
    src/infrastructure/registry/module_registry.cpp
    # Legacy service_registry.cpp DELETED. Plugin registration
    # now flows exclusively through rac_plugin_registry.cpp below.
    src/plugin/rac_plugin_registry.cpp
    # Dynamic plugin loader (dlopen path; gated by RAC_PLUGIN_MODE_SHARED).
    src/plugin/plugin_loader.cpp
    # L1 runtime-plugin registry (CPU / Metal / CoreML / CUDA / …). The
    # built-in CPU runtime plugin lives under runtimes/cpu/ and is folded into
    # rac_commons by the root CMakeLists so the registry is never empty.
    src/plugin/rac_runtime_registry.cpp
    # HardwareProfile + EngineRouter (hardware-aware plugin scoring).
    src/router/rac_hardware_profile.cpp
    src/router/rac_engine_router.cpp
    # C ABI wrapper around EngineRouter (rac_plugin_route).
    src/router/rac_route.cpp
    # Proto-serialised hardware profile C ABI for all 5 frontends.
    src/router/rac_hardware_abi.cpp
    # Proto-serialised SDKComponent → [InferenceFramework] query.
    src/router/rac_router_capabilities.cpp
    src/infrastructure/download/download_manager.cpp
    src/infrastructure/download/download_orchestrator.cpp
    src/infrastructure/model_management/model_registry.cpp
    src/infrastructure/model_management/lora_registry.cpp
    src/infrastructure/model_management/model_types.cpp
    src/infrastructure/model_management/model_types_mappers.cpp
    src/infrastructure/model_management/model_paths.cpp
    src/infrastructure/model_management/model_strategy.cpp
    src/infrastructure/model_management/model_assignment.cpp
    src/infrastructure/model_management/model_compatibility.cpp
    src/infrastructure/model_management/model_compatibility_proto.cpp
    src/infrastructure/model_management/model_registry_fetch_assignments_proto.cpp
    src/infrastructure/model_management/model_format_infer_proto.cpp
    src/infrastructure/model_management/model_info_make_proto.cpp
    src/infrastructure/model_management/register_model_from_url.cpp
    src/infrastructure/model_management/artifact_expected_files_proto.cpp
    src/infrastructure/storage/storage_analyzer.cpp
    src/infrastructure/file_management/file_manager.cpp
    src/infrastructure/network/environment.cpp
    src/infrastructure/network/endpoints.cpp
    src/infrastructure/network/api_types.cpp
    src/infrastructure/network/auth_manager.cpp
    src/infrastructure/network/development_config.cpp
    # Native HTTP transport.
    # - Native targets (macOS/iOS/Android/Windows/Linux): the default
    #   client in rac_http_client_default.cpp dispatches every request
    #   through the platform transport vtable registered by the owning
    #   SDK (OkHttp, URLSession, dart:io, ...). libcurl + mbedTLS were
    #   deleted; every SDK MUST register an adapter during init.
    # - Emscripten/WASM: the emscripten_fetch shim provides both the
    #   `rac_http_transport_register_emscripten` / `_from_js` entry
    #   points AND direct implementations of the public C ABI (it's
    #   the only HTTP surface in the WASM build — no library-level
    #   adapter yet needs to handle the "no adapter registered" case).
    $<$<NOT:$<BOOL:${EMSCRIPTEN}>>:src/infrastructure/http/rac_http_client_default.cpp>
    $<$<BOOL:${EMSCRIPTEN}>:src/infrastructure/http/rac_http_client_emscripten.cpp>
    # Single `rac_http_response_free` TU shared
    # by the default + emscripten clients (was duplicated before).
    src/infrastructure/http/rac_http_response.cpp
    src/infrastructure/http/rac_http_download.cpp
    # Platform HTTP transport vtable / registry.
    # Platform SDKs register a native-stack adapter here (Swift URLSession,
    # Kotlin OkHttp, Web fetch, Flutter dart:io, RN fetch/JSI); when no
    # adapter is registered, native public HTTP calls fail with
    # RAC_ERROR_FEATURE_NOT_AVAILABLE. Emscripten uses its Web fetch adapter.
    src/infrastructure/http/rac_http_transport.cpp
    # Internal C++ HTTP facade.
    # Every commons component that needs HTTP funnels through
    # rac::http::execute / execute_stream. The facade routes through the
    # platform transport vtable above and has no portable HTTP fallback.
    src/infrastructure/http/rac_http_internal.cpp
    # Supabase-style upsert request flag. Lets platform SDKs
    # arm a request via `rac_http_request_set_upsert_mode`; the dispatch
    # sites in rac_http_client_default.cpp / rac_http_client_emscripten.cpp
    # consume it and apply the on_conflict URL rewrite + Prefer header.
    src/infrastructure/http/rac_http_upsert_mode.cpp
    # Single canonical default-header list shared across SDKs
    # (RunAnywhereSDK / commons VERSION / application-json). Lets every
    # platform's `defaultHeaders` block resolve through one C entry point
    # so they stay in lockstep with the commons VERSION file.
    src/infrastructure/http/http_default_headers.cpp
    src/infrastructure/telemetry/telemetry_types.cpp
    src/infrastructure/telemetry/telemetry_json.cpp
    src/infrastructure/telemetry/telemetry_manager.cpp
    src/infrastructure/device/rac_device_manager.cpp
    # Persistent device-id resolution chain
    # (Keychain -> identifierForVendor -> generate UUID) collapsed from each
    # platform SDK into a single C entry point.
    src/infrastructure/device/device_identity.cpp
    src/infrastructure/extraction/rac_extraction.cpp
    # DAG streaming runtime. The primitives
    # under include/rac/graph/ (CancelToken / StreamEdge / RingBuffer /
    # MemoryPool / PipelineNode) are header-only templates; only the
    # non-templated GraphScheduler has a .cpp to compile here.
    src/graph/graph_scheduler.cpp
)

# Built-in CPU runtime. The runtime registry explicitly calls
# rac_runtime_entry_cpu() during bootstrap. Standalone commons builds compile
# the TU directly; root monorepo builds fold in the runtimes/cpu OBJECT target
# after add_subdirectory(runtimes), so compiling it here as well duplicates
# rac_runtime_entry_cpu and the CPU provider symbols.
set(RAC_CPU_RUNTIME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../runtimes/cpu")
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR
   AND EXISTS "${RAC_CPU_RUNTIME_DIR}/rac_runtime_cpu.cpp")
    list(APPEND RAC_INFRASTRUCTURE_SOURCES
        "${RAC_CPU_RUNTIME_DIR}/rac_runtime_cpu.cpp"
    )
endif()

# Feature sources - LLM, STT, TTS, VAD, Wake Word, VLM, Diffusion (iOS/Apple only)
set(RAC_FEATURES_SOURCES
    # LLM
    src/features/llm/llm_component.cpp
    src/features/llm/rac_llm_service.cpp
    src/features/llm/rac_llm_proto_service.cpp
    src/features/llm/streaming_metrics.cpp
    src/features/llm/llm_analytics.cpp
    src/features/llm/structured_output.cpp
    # JSONSchema-proto -> JSON Schema text canonical writer (replaces
    # Swift JSONSchemaWriter / per-SDK serializers).
    src/features/llm/schema_to_json.cpp
    # Thinking-content split (replaces Swift
    # ThinkingContentParser; rac_llm_split_thinking_tokens C ABI)
    src/features/llm/rac_llm_thinking.cpp
    src/features/llm/tool_calling.cpp
    # Commons-owned heuristics derived from
    # RAModelInfo (tool-call format + parameterCountB + isSmallModel). Replaces
    # the duplicated detectToolCallFormat / isLikelySmallModel helpers that
    # examples-flutter, -ios, -android, -react-native were each hand-rolling.
    src/features/llm/rac_model_heuristics.cpp
    # ToolValue <-> JSON proto-byte ABI (replaces per-SDK ~80 LOC walks).
    src/features/llm/rac_tool_value_json.cpp
    # Tool-calling session state machine (collapses per-SDK
    # 200-400 LOC orchestration loop into one native session).
    src/features/llm/tool_calling_session.cpp
    # Synchronous single-call tool-calling loop (parse -> validate ->
    # execute -> follow-up). Collapses Swift's ~100 LOC generateWithTools
    # to ~10 LOC; same loop will benefit Kotlin/RN over the same ABI.
    src/features/llm/tool_calling_run_loop.cpp
    # Proto-byte LLM stream ABI (mirrors
    # voice_agent/rac_voice_event_abi.cpp; replaces per-SDK hand-rolled
    # AsyncThrowingStream / callbackFlow / tokenQueue shims).
    src/features/llm/rac_llm_stream.cpp
    # STT
    src/features/stt/stt_component.cpp
    src/features/stt/rac_stt_service.cpp
    src/features/stt/stt_analytics.cpp
    # Lifecycle-owned proto-byte STTStreamEvent ABI
    src/features/stt/rac_stt_stream.cpp
    # Canonical STTConfiguration defaults helper
    src/features/stt/rac_stt_config_defaults.cpp
    # TTS
    src/features/tts/tts_component.cpp
    src/features/tts/rac_tts_service.cpp
    src/features/tts/tts_analytics.cpp
    # Lifecycle-owned proto-byte TTSStreamEvent ABI
    src/features/tts/rac_tts_stream.cpp
    # Canonical TTSConfiguration defaults helper
    src/features/tts/rac_tts_config_defaults.cpp
    # VAD
    src/features/vad/vad_component.cpp
    src/features/vad/energy_vad.cpp
    src/features/vad/vad_analytics.cpp
    # Lifecycle-owned proto-byte VADStreamEvent ABI
    src/features/vad/rac_vad_stream.cpp
    # Shared per-handle threshold-mutex registry.
    src/features/vad/vad_threshold_registry.cpp
    # Wake Word — high-level service scaffold was removed. All real
    # consumers call the speech backend's rac_wakeword_onnx_* compatibility
    # API directly. The shared types in
    # include/rac/features/wakeword/rac_wakeword_types.h remain.
    # VLM (Vision Language Model)
    src/features/vlm/vlm_component.cpp
    src/features/vlm/rac_vlm_service.cpp
    src/features/vlm/rac_vlm_proto_abi.cpp
    # Diffusion
    src/features/diffusion/diffusion_component.cpp
    src/features/diffusion/rac_diffusion_service.cpp
    src/features/diffusion/rac_diffusion_proto_abi.cpp
    src/features/diffusion/diffusion_model_registry.cpp
    src/features/diffusion/rac_diffusion_tokenizer.cpp
    # Lifecycle-owned proto-byte DiffusionStreamEvent ABI
    src/features/diffusion/rac_diffusion_stream.cpp
    # Embeddings
    src/features/embeddings/rac_embeddings_service.cpp
    src/features/embeddings/rac_embeddings_proto_abi.cpp
    src/features/embeddings/embeddings_component.cpp
    # Lifecycle-owned generated-proto ABI for non-LLM one-shot operations
    src/features/rac_nonllm_lifecycle_proto_abi.cpp
    # Platform service availability callback registry (always built; platform
    # implementations remain Apple-gated below).
    src/features/platform/rac_platform_services.cpp
    # LoRA
    src/features/lora/rac_lora_service.cpp
    # Voice Agent — SRP split:
    #   voice_agent.cpp                       — lifecycle (create/destroy/init)
    #   voice_agent_legacy_abi.cpp            — legacy non-proto C ABI
    #   voice_agent_proto_abi.cpp             — synchronous proto C ABI
    #   voice_agent_d7_abi.cpp                — full-session proto ABI
    #   voice_agent_audio_pipeline_state.cpp  — audio pipeline state helpers
    #   voice_agent_internal_helpers.cpp      — shared emit/state helpers
    src/features/voice_agent/voice_agent.cpp
    src/features/voice_agent/voice_agent_internal_helpers.cpp
    src/features/voice_agent/voice_agent_legacy_abi.cpp
    src/features/voice_agent/voice_agent_proto_abi.cpp
    src/features/voice_agent/voice_agent_d7_abi.cpp
    src/features/voice_agent/voice_agent_audio_pipeline_state.cpp
    # Proto-byte event ABI (coexists with struct callback).
    src/features/voice_agent/rac_voice_event_abi.cpp
    # GraphScheduler-driven VAD→STT→LLM→TTS pipeline.
    # First DAG consumer; replaces the in-line process_stream
    # orchestration with typed PipelineNodes + bounded StreamEdge
    # backpressure + hierarchical CancelToken propagation.
    src/features/voice_agent/voice_agent_pipeline.cpp
    # Result memory management (weak symbol fallbacks)
    # On MSVC, each service .cpp already provides strong definitions,
    # so result_free.cpp (which uses __attribute__((weak)) on GCC/Clang)
    # must be excluded to avoid LNK2005 duplicate symbol errors.
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:src/features/result_free.cpp>
)

# Platform services (Apple Foundation Models + System TTS + CoreML Diffusion)
if(APPLE AND RAC_BUILD_PLATFORM)
    set(RAC_PLATFORM_SOURCES
        src/features/platform/rac_llm_platform.cpp
        src/features/platform/rac_tts_platform.cpp
        src/features/platform/rac_diffusion_platform.cpp
        src/features/platform/rac_backend_platform_register.cpp
        src/features/platform/rac_plugin_entry_platform.cpp
    )
    message(STATUS "Building platform services: Apple Foundation Models, System TTS, CoreML Diffusion")
else()
    set(RAC_PLATFORM_SOURCES "")
endif()

# WhisperKit CoreML sources are owned by engines/whisperkit_coreml/
# which declares its own rac_backend_whisperkit_coreml target (via
# rac_add_engine_plugin). Commons no longer compiles those TUs directly.

# Solutions C ABI — always-built fallback.
#
# The full SolutionRunner implementation (rac_solution.cpp + companions)
# requires the Solutions runtime and is added to rac_commons only when
# RAC_ENABLE_SOLUTIONS=ON. Artifacts may still ship the core protobuf ABI
# without Solutions, so without this stub TU every downstream binding (Swift
# facade, JNI thunks, RN HybridRunAnywhereCore, Flutter FFI, Web exports) would
# fail to link against the rac_solution_* symbols.
#
# rac_solution_stub.cpp is gated on `#ifndef RAC_HAVE_SOLUTIONS`, so protobuf
# can be enabled for the core proto ABI without accidentally dropping the
# solution fallback symbols when RAC_ENABLE_SOLUTIONS=OFF.
set(RAC_SOLUTIONS_STUB_SOURCES
    src/solutions/rac_solution_stub.cpp
)

# Combine all sources
set(RAC_COMMONS_SOURCES
    ${RAC_CORE_SOURCES}
    ${RAC_INFRASTRUCTURE_SOURCES}
    ${RAC_FEATURES_SOURCES}
    ${RAC_PLATFORM_SOURCES}
    ${RAC_SOLUTIONS_STUB_SOURCES}
)

# =============================================================================
# RAC COMMONS LIBRARY
# =============================================================================

if(RAC_BUILD_SHARED)
    add_library(rac_commons SHARED ${RAC_COMMONS_SOURCES})
else()
    add_library(rac_commons STATIC ${RAC_COMMONS_SOURCES})
endif()

# Public headers
target_include_directories(rac_commons PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Private includes for implementation
target_include_directories(rac_commons PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)
if(EXISTS "${RAC_CPU_RUNTIME_DIR}/rac_runtime_entry_cpu.h")
    target_include_directories(rac_commons PRIVATE
        "${RAC_CPU_RUNTIME_DIR}"
    )
endif()

# Mark every commons translation unit as an "internal" build so legacy event
# headers (rac_analytics_events.h, rac_events.h, rac_*_events.h) compile
# without their public-API #warning. SDK code outside commons does NOT see
# this define, so accidental SDK-side inclusion still triggers the warning.
target_compile_definitions(rac_commons PRIVATE RAC_BUILDING_COMMONS=1)

# Canonical SDK version string (from the VERSION file) injected as a compile
# define so rac_get_version()/rac_sdk_get_version() return the real release
# version. Single source of truth: sdk/runanywhere-commons/VERSION -> RAC_VERSION
# (read at the top of this file). Every platform SDK delegates its public
# version constant to this value instead of hand-maintaining a copy.
target_compile_definitions(rac_commons PRIVATE RAC_VERSION_STRING="${RAC_VERSION}")

# Symbol visibility for shared builds
if(RAC_BUILD_SHARED)
    target_compile_definitions(rac_commons PRIVATE RAC_BUILDING_SHARED=1)
    set_target_properties(rac_commons PROPERTIES
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
    )
endif()

# Android: override the hidden-visibility preset for rac_commons. The JNI
# shared library librunanywhere_jni.so dynamic-links against librac_commons.so
# and needs every rac_* C ABI function resolvable at link time. Several
# functions in the public C headers are still missing the `RAC_API`
# visibility attribute (rac_plugin_list, rac_llm_{extract,strip}_thinking,
# rac_llm_split_thinking_tokens, rac_voice_agent_set_proto_callback,
# rac_llm_{,un}set_stream_proto_callback); hiding them breaks the JNI link
# with `undefined symbol` errors. Forcing default visibility on this target
# matches the macOS/iOS xcframework behaviour, where commons is a static
# archive and every symbol is visible to downstream consumers. The override
# is target-scoped so engine backends keep their hidden-visibility hardening.
# TODO(v0.21): annotate all remaining legacy C ABI functions with RAC_API
# and drop this Android-specific override. Also flip the same override on
# Linux: the test executables (test_voice_agent_pipeline,
# test_graph_scheduler, test_pipeline_executor) link directly against
# internal C++ classes (`rac::voice_agent::VoiceAgentPipeline`,
# `rac::graph::GraphScheduler`, etc.) that don't yet carry RAC_API. With
# the default hidden visibility on Linux SHARED builds the test linker
# fails with `undefined reference to <class>::<class>()`. Apple builds
# already use a curated exports list so they're unaffected by this; macOS
# CMake builds use RAC_BUILD_SHARED=OFF so the symbols live inside the
# static archive.
if(ANDROID OR (CMAKE_SYSTEM_NAME STREQUAL "Linux" AND RAC_BUILD_SHARED))
    set_target_properties(rac_commons PROPERTIES
        C_VISIBILITY_PRESET   default
        CXX_VISIBILITY_PRESET default
        VISIBILITY_INLINES_HIDDEN OFF
    )
    target_compile_options(rac_commons PRIVATE -fvisibility=default)
endif()

# Apple: wire the curated export list (exports/RACommons.exports) into the
# linker so the xcframework shipped via SPM only exposes the 465 curated
# _rac_* symbols currently called by the 5 SDKs (Swift / Kotlin / Flutter /
# React Native / Web). Matters for App Store symbol analysis; Android keeps
# the default-visibility workaround above until RAC_API annotations are
# complete (TODO v0.21). Note: target_link_options only takes effect
# when the target is linked as a dynamic library — static-archive builds
# ignore it, which is fine because symbol visibility only matters at final
# link time. Use scripts/validation/commons/check_rac_api_exports.sh to verify the
# list stays in sync; update the count here when it changes materially.
#
# This block is additionally gated on
# RAC_BUILD_SHARED. `-exported_symbols_list` is a no-op for STATIC
# archives (which is the default for every Apple preset in
# CMakePresets.json — macos-{debug,release}, ios-{device,simulator}),
# so materializing the merged file + setting target_link_options is
# pure overhead in the common case. Skipping the entire block also
# sidesteps the latent macOS-SHARED-with-engine-symbols hazard: when
# RAC_BUILD_SHARED=OFF the merged list is never consulted, so the
# current sibling-files-only-defined-in-commons invariant cannot fail
# even if RAC_STATIC_PLUGINS=OFF. The only sibling concatenated below
# (RACommons.rag.exports) lists `rac_backend_rag_{register,unregister}`
# whose definitions live in src/features/rag/ — i.e. inside commons —
# so a future SHARED Apple build with any plugin-link mode is safe.
if(APPLE AND RAC_BUILD_SHARED)
    # Backend-conditional exports live in sibling files and
    # are concatenated into a single per-build merged list under
    # ${CMAKE_CURRENT_BINARY_DIR}. The Apple linker takes exactly one
    # `-exported_symbols_list` argument, so we cannot list the conditional
    # files separately; we have to materialize the merged list at configure
    # time so the path passed to the linker is stable across reconfigures.
    set(_rac_exports_core "${CMAKE_CURRENT_SOURCE_DIR}/exports/RACommons.exports")
    set(_rac_exports_merged_inputs "${_rac_exports_core}")
    if(RAC_BACKEND_RAG)
        list(APPEND _rac_exports_merged_inputs
            "${CMAKE_CURRENT_SOURCE_DIR}/exports/RACommons.rag.exports")
    endif()
    # The onnx_embeddings and whisperkit_coreml sibling
    # exports siblings were dropped here — those `_rac_backend_*_register`
    # symbols are defined in the engine targets (engines/onnx,
    # engines/whisperkit_coreml), not in librac_commons. Listing them in
    # librac_commons' `-exported_symbols_list` would either be a no-op
    # (symbol absent from the archive) or a hard link error on shared
    # builds. Each engine target publishes its own exports list — see
    # engines/<name>/CMakeLists.txt for the per-backend symbol contract.
    set(_rac_exports_merged "${CMAKE_CURRENT_BINARY_DIR}/RACommons.merged.exports")
    # Materialize once at configure time so the path is valid even before
    # the build-time merge fires (Xcode dependency resolution, downstream
    # codegen, etc. may inspect the file pre-build).
    file(WRITE "${_rac_exports_merged}"
        "# Auto-generated at configure time by sdk/runanywhere-commons/CMakeLists.txt.\n"
        "# Concatenates RACommons.exports with the backend-conditional sibling\n"
        "# exports files for whichever RAC_BACKEND_* flags are ON. DO NOT EDIT;\n"
        "# edit the source files under exports/ instead.\n")
    foreach(_rac_exports_part IN LISTS _rac_exports_merged_inputs)
        file(READ "${_rac_exports_part}" _rac_exports_part_contents)
        file(APPEND "${_rac_exports_merged}" "${_rac_exports_part_contents}\n")
    endforeach()
    unset(_rac_exports_part_contents)
    # Also register a build-time custom command with a
    # DEPENDS edge on the source .exports files. `file(WRITE/APPEND)`
    # above runs only at *configure* time and is not tracked by the
    # Ninja/Make/Xcode dependency graph; without this custom command,
    # edits to RACommons.exports or RACommons.rag.exports would require
    # a manual `cmake .` reconfigure to propagate into the linker
    # invocation. We materialize a tiny CMake -P helper script in the
    # build dir so the custom command can re-run the concatenation
    # using only portable cmake -E primitives (no shell, no awk, no
    # need to add a sibling .cmake file under sdk/runanywhere-commons/).
    set(_rac_exports_merge_script
        "${CMAKE_CURRENT_BINARY_DIR}/_RACommons_MergeExports.cmake")
    file(WRITE "${_rac_exports_merge_script}"
"# Auto-generated by sdk/runanywhere-commons/CMakeLists.txt for the\n"
"# build-time merge of RACommons exports siblings.\n"
"# Invoked via: cmake -DRAC_EXPORTS_OUT=<path> -DRAC_EXPORTS_IN=<list> -P\n"
"file(WRITE \"\${RAC_EXPORTS_OUT}\"\n"
"    \"# Auto-generated by RACommons exports merge step. DO NOT EDIT.\\n\")\n"
"foreach(_part IN LISTS RAC_EXPORTS_IN)\n"
"    file(READ \"\${_part}\" _part_contents)\n"
"    file(APPEND \"\${RAC_EXPORTS_OUT}\" \"\${_part_contents}\\n\")\n"
"endforeach()\n")
    add_custom_command(
        OUTPUT "${_rac_exports_merged}"
        COMMAND ${CMAKE_COMMAND}
            -DRAC_EXPORTS_OUT=${_rac_exports_merged}
            "-DRAC_EXPORTS_IN=${_rac_exports_merged_inputs}"
            -P "${_rac_exports_merge_script}"
        DEPENDS ${_rac_exports_merged_inputs} "${_rac_exports_merge_script}"
        COMMENT "Merging Apple exports list -> ${_rac_exports_merged}"
        VERBATIM
    )
    # Hook the custom-command output into rac_commons so the merge runs
    # before the target links. Without this dependency, the custom
    # command's OUTPUT is never requested by any build target.
    add_custom_target(rac_commons_exports_merge
        DEPENDS "${_rac_exports_merged}")
    add_dependencies(rac_commons rac_commons_exports_merge)
    set_target_properties(rac_commons PROPERTIES
        XCODE_ATTRIBUTE_EXPORTED_SYMBOLS_FILE "${_rac_exports_merged}")
    target_link_options(rac_commons PRIVATE
        "LINKER:-exported_symbols_list,${_rac_exports_merged}")
endif()

# libarchive - native archive extraction
# PUBLIC on Windows because MSVC static libs don't propagate transitive deps
if(WIN32)
    target_link_libraries(rac_commons PUBLIC archive_static)
    # Tell libarchive headers we're using the static library (not DLL)
    target_compile_definitions(rac_commons PRIVATE LIBARCHIVE_STATIC)
    if(TARGET zlibstatic)
        target_link_libraries(rac_commons PUBLIC zlibstatic)
    endif()
    if(TARGET bz2_bundled)
        target_link_libraries(rac_commons PUBLIC bz2_bundled)
    endif()
else()
    target_link_libraries(rac_commons PRIVATE archive_static)
endif()
target_include_directories(rac_commons PRIVATE ${libarchive_SOURCE_DIR}/libarchive ${libarchive_BINARY_DIR})

# HTTP transport — libcurl deleted. On Emscripten we still link
# the `-sFETCH=1` runtime glue so emscripten_fetch is available inside
# `rac_http_client_emscripten.cpp`. On every other target the default
# client dispatches through the platform transport vtable and needs
# no extra link dependencies here.
if(EMSCRIPTEN)
    # -sFETCH=1 links `emscripten_fetch()` + its JS glue into the
    # final .wasm bundle. Needs to be both a compile and a link flag so
    # the header is visible and the runtime function is exported.
    target_compile_options(rac_commons PUBLIC "-sFETCH=1")
    target_link_options(rac_commons PUBLIC "-sFETCH=1")
    # libarchive gzip filter reads tar.gz without spawning `gzip -d` (unavailable in WASM).
    target_compile_options(rac_commons PUBLIC "-sUSE_ZLIB=1")
    target_link_options(rac_commons PUBLIC "-sUSE_ZLIB=1")
endif()

# =============================================================================
# Reproducible proto C++ codegen
# =============================================================================
# Committed `.pb.{cc,h}` pairs in `src/generated/proto/` must stay in sync with
# `idl/*.proto`. When RAC_REGENERATE_PROTO=ON AND `protoc` is on-path, rerun
# `idl/codegen/generate_cpp.sh` whenever any `.proto` is newer than the
# `.gen-stamp` marker. CI / release builds leave RAC_REGENERATE_PROTO=OFF
# (default) and use the committed files as-is — no protoc dependency.
# =============================================================================

if(RAC_REGENERATE_PROTO)
    find_program(RAC_PROTOC_EXE protoc)
    find_program(RAC_BASH_EXE bash)
    if(NOT RAC_PROTOC_EXE)
        message(WARNING "RAC_REGENERATE_PROTO=ON but protoc not found on PATH — skipping regen. Install protobuf (brew install protobuf) or unset RAC_REGENERATE_PROTO.")
    elseif(NOT RAC_BASH_EXE)
        message(WARNING "RAC_REGENERATE_PROTO=ON but bash not found on PATH — skipping regen.")
    else()
        # repo root = two levels up from sdk/runanywhere-commons/
        get_filename_component(_RAC_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
        set(_RAC_IDL_DIR "${_RAC_REPO_ROOT}/idl")
        set(_RAC_IDL_CODEGEN "${_RAC_IDL_DIR}/codegen/generate_cpp.sh")
        set(_RAC_PROTO_OUT "${CMAKE_CURRENT_SOURCE_DIR}/src/generated/proto")
        set(_RAC_PROTO_STAMP "${_RAC_PROTO_OUT}/.gen-stamp")

        file(GLOB _RAC_PROTO_SOURCES CONFIGURE_DEPENDS "${_RAC_IDL_DIR}/*.proto")

        if(EXISTS "${_RAC_IDL_CODEGEN}" AND _RAC_PROTO_SOURCES)
            add_custom_command(
                OUTPUT "${_RAC_PROTO_STAMP}"
                COMMAND "${CMAKE_COMMAND}" -E make_directory "${_RAC_PROTO_OUT}"
                COMMAND "${RAC_BASH_EXE}" "${_RAC_IDL_CODEGEN}"
                COMMAND "${CMAKE_COMMAND}" -E touch "${_RAC_PROTO_STAMP}"
                DEPENDS ${_RAC_PROTO_SOURCES} "${_RAC_IDL_CODEGEN}"
                WORKING_DIRECTORY "${_RAC_REPO_ROOT}"
                COMMENT "[rac_proto_gen] Regenerating C++ proto sources from idl/*.proto"
                VERBATIM
            )
            add_custom_target(rac_proto_gen DEPENDS "${_RAC_PROTO_STAMP}")
            add_dependencies(rac_commons rac_proto_gen)
            message(STATUS "rac_proto_gen wired (idl/*.proto → ${_RAC_PROTO_OUT}); rac_commons depends on it")
        else()
            message(WARNING "RAC_REGENERATE_PROTO=ON but ${_RAC_IDL_CODEGEN} or idl/*.proto missing — skipping regen target")
        endif()
    endif()
endif()

# =============================================================================
# Protobuf runtime — gates RAC_HAVE_PROTOBUF
#
# Protobuf-backed native ABIs are used directly by Swift/Flutter/Kotlin/RN/Web
# bindings for registry, storage, downloads, lifecycle, LLM, speech, vision, and
# other serialized-byte calls. Keep this independent from the Solutions API:
# Solutions consume protobuf too, but disabling Solutions must not silently turn
# every exported proto ABI symbol into a RAC_ERROR_FEATURE_NOT_AVAILABLE stub.
# =============================================================================

if(EMSCRIPTEN)
    set(RAC_ENABLE_PROTOBUF_DEFAULT OFF)
else()
    set(RAC_ENABLE_PROTOBUF_DEFAULT ON)
endif()
option(RAC_ENABLE_PROTOBUF "Build protobuf-backed native ABI implementations" ${RAC_ENABLE_PROTOBUF_DEFAULT})
option(RAC_VENDOR_PROTOBUF "Fetch/build protobuf when RAC_ENABLE_PROTOBUF=ON and find_package(Protobuf) fails" ON)

if(EMSCRIPTEN)
    set(RAC_ENABLE_SOLUTIONS_DEFAULT OFF)
else()
    set(RAC_ENABLE_SOLUTIONS_DEFAULT ${RAC_ENABLE_PROTOBUF})
endif()
option(RAC_ENABLE_SOLUTIONS "Build Solutions API (requires protobuf+absl)" ${RAC_ENABLE_SOLUTIONS_DEFAULT})

set(RAC_PROTOBUF_RUNTIME_ENABLED OFF CACHE INTERNAL "rac_commons protobuf runtime enabled" FORCE)
set(RAC_SOLUTIONS_RUNTIME_ENABLED OFF CACHE INTERNAL "rac_commons Solutions runtime enabled" FORCE)
set(_RAC_PROTO_GEN_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src/generated/proto)
set(_RAC_PROTO_GENERATED_SOURCES
    ${_RAC_PROTO_GEN_DIR}/voice_events.pb.cc
    ${_RAC_PROTO_GEN_DIR}/sdk_events.pb.cc
    ${_RAC_PROTO_GEN_DIR}/download_service.pb.cc
    ${_RAC_PROTO_GEN_DIR}/model_types.pb.cc
    ${_RAC_PROTO_GEN_DIR}/pipeline.pb.cc
    ${_RAC_PROTO_GEN_DIR}/solutions.pb.cc
    ${_RAC_PROTO_GEN_DIR}/hardware_profile.pb.cc
    ${_RAC_PROTO_GEN_DIR}/llm_service.pb.cc
    ${_RAC_PROTO_GEN_DIR}/llm_options.pb.cc
    ${_RAC_PROTO_GEN_DIR}/chat.pb.cc
    ${_RAC_PROTO_GEN_DIR}/tool_calling.pb.cc
    ${_RAC_PROTO_GEN_DIR}/structured_output.pb.cc
    ${_RAC_PROTO_GEN_DIR}/stt_options.pb.cc
    ${_RAC_PROTO_GEN_DIR}/tts_options.pb.cc
    ${_RAC_PROTO_GEN_DIR}/vad_options.pb.cc
    ${_RAC_PROTO_GEN_DIR}/vlm_options.pb.cc
    ${_RAC_PROTO_GEN_DIR}/diffusion_options.pb.cc
    ${_RAC_PROTO_GEN_DIR}/embeddings_options.pb.cc
    ${_RAC_PROTO_GEN_DIR}/rag.pb.cc
    ${_RAC_PROTO_GEN_DIR}/storage_types.pb.cc
    ${_RAC_PROTO_GEN_DIR}/lora_options.pb.cc
    ${_RAC_PROTO_GEN_DIR}/voice_agent_service.pb.cc
    ${_RAC_PROTO_GEN_DIR}/errors.pb.cc
    ${_RAC_PROTO_GEN_DIR}/router.pb.cc
    ${_RAC_PROTO_GEN_DIR}/thinking_tag_pattern.pb.cc
    ${_RAC_PROTO_GEN_DIR}/component_types.pb.cc
    ${_RAC_PROTO_GEN_DIR}/lifecycle_service.pb.cc
    # Two-phase SDK init request/result envelope.
    ${_RAC_PROTO_GEN_DIR}/sdk_init.pb.cc
    # rac_options.proto — custom FieldOptions / EnumValueOptions extensions
    # imported by codegen post-processors and several option protos. Required
    # at link time by every .pb.cc that imports rac_options.proto.
    ${_RAC_PROTO_GEN_DIR}/rac_options.pb.cc
)
set(RAC_PROTOBUF_COMPILE_OPTIONS "")
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    list(APPEND RAC_PROTOBUF_COMPILE_OPTIONS -Wno-nullability-extension)
endif()

if(RAC_ENABLE_PROTOBUF)
    message(STATUS "RAC_ENABLE_PROTOBUF=ON — building generated-proto native ABI implementations")
    if(RAC_VENDOR_PROTOBUF)
        find_package(Protobuf ${PROTOBUF_VERSION} EXACT CONFIG QUIET)
    else()
        find_package(Protobuf ${PROTOBUF_VERSION} EXACT QUIET)
    endif()
    # Fallback for homebrew/system protobuf 34.x: the upstream config file
    # reports PACKAGE_VERSION_MAJOR==7 (runtime ABI major) and rejects
    # `Protobuf <X> EXACT`. Module mode finds the same install with a
    # synthesized version string. Accept either so local dev on macOS works
    # without requiring a vendored FetchContent build.
    #
    # Require Protobuf >= 5.0 in the fallback so a system protobuf 3.x
    # install (Ubuntu 22.04 ships 3.12, 24.04 ships 3.21) is rejected and
    # FetchContent fetches the centralized PROTOBUF_VERSION below. The
    # checked-in generated headers under src/generated/proto/ are Protobuf
    # C++ Version 7.34.1 and include `google/protobuf/runtime_version.h`,
    # which only exists in the libprotobuf 4.x+ runtime. Linking against
    # 3.x produces `fatal error: google/protobuf/runtime_version.h: No such
    # file or directory`.
    if(NOT Protobuf_FOUND)
        find_package(Protobuf 5.0 QUIET)
    endif()

    if(NOT Protobuf_FOUND AND RAC_VENDOR_PROTOBUF)
        include(FetchContent)
        set(protobuf_BUILD_TESTS           OFF CACHE BOOL "" FORCE)
        set(protobuf_BUILD_PROTOC_BINARIES OFF CACHE BOOL "" FORCE)
        set(protobuf_BUILD_EXAMPLES        OFF CACHE BOOL "" FORCE)
        set(protobuf_INSTALL               OFF CACHE BOOL "" FORCE)
        set(protobuf_BUILD_SHARED_LIBS     OFF CACHE BOOL "" FORCE)
        set(protobuf_WITH_ZLIB             OFF CACHE BOOL "" FORCE)
        # Skip building upb (Universal Protocol Buffers) entirely. Upstream
        # protobuf v34 builds protoc-gen-upb / protoc-gen-upbdefs /
        # protoc-gen-upb_minitable executables even with PROTOC_BINARIES=OFF,
        # which Xcode then rejects on iOS with `error: Bundle identifier is
        # missing. protoc-gen-upb doesn't have a bundle identifier`. We
        # never link the upb runtime — every generated header in
        # src/generated/proto/ uses the classic libprotobuf C++ surface.
        set(protobuf_BUILD_LIBUPB           OFF CACHE BOOL "" FORCE)
        # protobuf v28+ depends on abseil. Force FetchContent dependencies so
        # Apple static packages do not capture host/Homebrew absl dylibs.
        set(protobuf_ABSL_PROVIDER         "module" CACHE STRING "" FORCE)
        set(protobuf_FORCE_FETCH_DEPENDENCIES ON CACHE BOOL "" FORCE)
        set(ABSL_PROPAGATE_CXX_STD         ON CACHE BOOL "" FORCE)
        # FIND_PACKAGE_ARGS was removed because on Ubuntu CI
        # the internal find_package(Protobuf ... NAMES Protobuf) call silently
        # registered `protobuf::libprotobuf-lite` as an IMPORTED target from
        # a config file even when the EXACT version check failed. Protobuf
        # v34.1's own cmake/libprotobuf-lite.cmake then failed with
        # "add_library cannot create ALIAS target ... already exists" when
        # MakeAvailable processed the fetched source. Forcing a bare
        # FetchContent_Declare (always fetch + add_subdirectory) avoids that
        # IMPORTED-vs-fetched collision.
        FetchContent_Declare(
            protobuf_fetched
            GIT_REPOSITORY https://github.com/protocolbuffers/protobuf.git
            GIT_TAG        v${PROTOBUF_VERSION}
            GIT_SHALLOW    TRUE
        )
        FetchContent_MakeAvailable(protobuf_fetched)
        # Protobuf v34.x's libprotobuf-lite.cmake already creates
        # `protobuf::libprotobuf-lite` and `protobuf::libprotobuf` aliases.
        # Keep guards so older versions without those aliases still get them.
        if(TARGET libprotobuf AND NOT TARGET protobuf::libprotobuf)
            add_library(protobuf::libprotobuf ALIAS libprotobuf)
        endif()
        if(TARGET libprotobuf-lite AND NOT TARGET protobuf::libprotobuf-lite)
            add_library(protobuf::libprotobuf-lite ALIAS libprotobuf-lite)
        endif()
        if(TARGET protobuf::libprotobuf OR TARGET libprotobuf)
            set(Protobuf_FOUND TRUE)
            message(STATUS "RunAnywhere: vendored libprotobuf v${PROTOBUF_VERSION} via FetchContent (absl=module)")
        endif()
    endif()

    if(RAC_PROTOBUF_COMPILE_OPTIONS)
        foreach(_rac_pb_build_target libprotobuf libprotobuf-lite)
            if(TARGET ${_rac_pb_build_target})
                target_compile_options(${_rac_pb_build_target} PRIVATE
                    ${RAC_PROTOBUF_COMPILE_OPTIONS}
                )
            endif()
        endforeach()
    endif()

    if(NOT Protobuf_FOUND)
        message(FATAL_ERROR
            "RAC_ENABLE_PROTOBUF=ON but Protobuf is unavailable. "
            "Install Protobuf, leave RAC_VENDOR_PROTOBUF=ON, or configure with "
            "-DRAC_ENABLE_PROTOBUF=OFF to intentionally build unavailable proto stubs.")
    endif()

    foreach(_rac_proto_source IN LISTS _RAC_PROTO_GENERATED_SOURCES)
        if(NOT EXISTS "${_rac_proto_source}")
            message(FATAL_ERROR
                "RAC_ENABLE_PROTOBUF=ON but generated proto source is missing: "
                "${_rac_proto_source}. Run idl/codegen/generate_cpp.sh or disable "
                "RAC_ENABLE_PROTOBUF.")
        endif()
    endforeach()

    if(NOT Protobuf_INCLUDE_DIRS)
        foreach(_rac_pb_target protobuf::libprotobuf libprotobuf)
            if(TARGET ${_rac_pb_target})
                get_target_property(_rac_pb_inc ${_rac_pb_target} INTERFACE_INCLUDE_DIRECTORIES)
                if(_rac_pb_inc)
                    list(APPEND Protobuf_INCLUDE_DIRS ${_rac_pb_inc})
                endif()
            endif()
        endforeach()
    endif()
    if(NOT Protobuf_INCLUDE_DIRS AND DEFINED protobuf_fetched_SOURCE_DIR)
        set(Protobuf_INCLUDE_DIRS "${protobuf_fetched_SOURCE_DIR}/src")
    endif()

    target_sources(rac_commons PRIVATE
        ${_RAC_PROTO_GENERATED_SOURCES}
        src/foundation/rac_proto_adapters.cpp
    )
    if(RAC_PROTOBUF_COMPILE_OPTIONS)
        target_compile_options(rac_commons PRIVATE ${RAC_PROTOBUF_COMPILE_OPTIONS})
    endif()
    # Keep generated proto headers and protobuf includes PRIVATE. The C ABI
    # exposes byte buffers, not `runanywhere::v1::*` C++ types.
    target_include_directories(rac_commons PRIVATE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src/generated/proto>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src/generated>
        ${Protobuf_INCLUDE_DIRS}
    )
    if(TARGET protobuf::libprotobuf)
        target_link_libraries(rac_commons PRIVATE protobuf::libprotobuf)
    else()
        target_link_libraries(rac_commons PRIVATE ${Protobuf_LIBRARIES})
    endif()

    # Shared builds with some system protobuf packages still need explicit absl
    # link targets. Vendored protobuf normally propagates these transitively.
    #
    # Only collect absl components whose imported targets actually
    # exist. Ubuntu 22.04's libabsl-dev (20210324) is missing absl::log —
    # which lands in 20220623 — and `target_link_libraries` on a missing
    # target reports "Target ... links to absl::log but the target was not
    # found". The probe below keeps the link line correct on every host
    # (Homebrew absl, Ubuntu 24.04 libabsl-dev, vendored protobuf).
    if(NOT DEFINED RAC_ABSL_LIBS)
        find_package(absl QUIET CONFIG)
        set(RAC_ABSL_LIBS "")
        if(absl_FOUND)
            foreach(_rac_absl_component
                    absl::log
                    absl::log_internal_check_op
                    absl::hash
                    absl::strings
                    absl::status)
                if(TARGET ${_rac_absl_component})
                    list(APPEND RAC_ABSL_LIBS ${_rac_absl_component})
                endif()
            endforeach()
        endif()
    endif()
    if(RAC_ABSL_LIBS)
        target_link_libraries(rac_commons PUBLIC ${RAC_ABSL_LIBS})
    endif()

    target_compile_definitions(rac_commons PRIVATE RAC_HAVE_PROTOBUF=1)
    set(RAC_PROTOBUF_RUNTIME_ENABLED ON CACHE INTERNAL "rac_commons protobuf runtime enabled" FORCE)
    message(STATUS "Protobuf runtime: linked generated protos + RAC_HAVE_PROTOBUF=1")
else()
    message(STATUS "RAC_ENABLE_PROTOBUF=OFF — exported proto ABI functions use unavailable stubs")
endif()

if(RAC_ENABLE_SOLUTIONS)
    if(NOT RAC_PROTOBUF_RUNTIME_ENABLED)
        message(FATAL_ERROR
            "RAC_ENABLE_SOLUTIONS=ON requires RAC_ENABLE_PROTOBUF=ON and a working protobuf runtime.")
    endif()
    if(NOT RAC_BACKEND_RAG)
        message(WARNING
            "RAC_ENABLE_SOLUTIONS=ON with RAC_BACKEND_RAG=OFF: Solutions RetrieveNode RAG "
            "operations return RAC_ERROR_FEATURE_NOT_AVAILABLE at runtime.")
    endif()
    message(STATUS "RAC_ENABLE_SOLUTIONS=ON — building full Solutions API")
    target_sources(rac_commons PRIVATE
        src/solutions/operator_registry.cpp
        src/solutions/operators/op_engine_backed.cpp
        src/solutions/pipeline_executor.cpp
        src/solutions/solution_converter.cpp
        src/solutions/solution_runner.cpp
        src/solutions/config_loader.cpp
        src/solutions/rac_solution.cpp
    )
    target_compile_definitions(rac_commons PRIVATE RAC_HAVE_SOLUTIONS=1)
    set(RAC_SOLUTIONS_RUNTIME_ENABLED ON CACHE INTERNAL "rac_commons Solutions runtime enabled" FORCE)
    message(STATUS "SolutionRunner + PipelineExecutor compiled into rac_commons")
else()
    message(STATUS "RAC_ENABLE_SOLUTIONS=OFF — rac_solution_* symbols served by rac_solution_stub.cpp (RAC_ERROR_FEATURE_NOT_AVAILABLE)")
endif()

# Platform-specific linking
if(APPLE)
    target_link_libraries(rac_commons PUBLIC
        "-framework Foundation"
    )
    if(RAC_BUILD_PLATFORM)
        target_link_libraries(rac_commons PUBLIC
            "-framework AVFoundation"
        )
    endif()
endif()

if(RAC_PLATFORM_ANDROID)
    target_compile_definitions(rac_commons PRIVATE RAC_PLATFORM_ANDROID=1)
    target_link_libraries(rac_commons PUBLIC log)
endif()

if(RAC_PLATFORM_WINDOWS)
    target_compile_definitions(rac_commons PRIVATE RAC_PLATFORM_WINDOWS=1)
    # ws2_32 = Winsock, shlwapi = path utilities
    target_link_libraries(rac_commons PUBLIC ws2_32 shlwapi)
endif()

# =============================================================================
# Plugin Loading Mode (static vs. dynamic)
# =============================================================================
# Two paths share one plugin entry-point convention:
#   - STATIC: plugin TUs compiled directly into rac_commons; registration
#     happens at process start via RAC_STATIC_PLUGIN_REGISTER(<name>).
#     iOS App Store + WebAssembly forbid dlopen, so they MUST use this path.
#   - SHARED: plugin TUs build standalone *.so / *.dylib / *.dll loaded at
#     runtime via rac_registry_load_plugin(path) (dlopen + dlsym).
#
# RAC_STATIC_PLUGINS:
#   ON  → STATIC mode (default on iOS / Emscripten / forced)
#   OFF → SHARED mode (default on Android / Linux / macOS / Windows)
if(RAC_PLATFORM_IOS OR EMSCRIPTEN)
    set(RAC_STATIC_PLUGINS ON CACHE BOOL
        "Link engine plugins statically into rac_commons (forced ON on iOS/WASM)" FORCE)
else()
    option(RAC_STATIC_PLUGINS
        "Link engine plugins statically into rac_commons (default OFF: use dlopen)" OFF)
endif()

if(RAC_STATIC_PLUGINS)
    target_compile_definitions(rac_commons PUBLIC RAC_PLUGIN_MODE_STATIC=1)
    message(STATUS "Plugin mode: STATIC (engine plugins linked into rac_commons)")
else()
    target_compile_definitions(rac_commons PUBLIC RAC_PLUGIN_MODE_SHARED=1)
    message(STATUS "Plugin mode: SHARED (engine plugins loaded via rac_registry_load_plugin)")
    # ${CMAKE_DL_LIBS} expands to -ldl on Linux/Android, empty on macOS/Win.
    target_link_libraries(rac_commons PUBLIC ${CMAKE_DL_LIBS})
endif()

set_target_properties(rac_commons PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

# =============================================================================
# JNI BRIDGE (Android/JVM)
# =============================================================================

if(RAC_BUILD_JNI)
    # Make JNI headers available project-wide so CLion can resolve jni.h
    # in ALL source files (including backend JNI files not in the current build)
    if(NOT ANDROID)
        # Auto-detect JAVA_HOME if not set or invalid
        if(NOT DEFINED ENV{JAVA_HOME} OR "$ENV{JAVA_HOME}" STREQUAL ""
           OR NOT EXISTS "$ENV{JAVA_HOME}/include/jni.h")
            find_program(_JAVA_EXEC java)
            if(_JAVA_EXEC)
                get_filename_component(_JAVA_EXEC_REAL "${_JAVA_EXEC}" REALPATH)
                get_filename_component(_JAVA_BIN_DIR "${_JAVA_EXEC_REAL}" DIRECTORY)
                get_filename_component(_JAVA_HOME_DETECTED "${_JAVA_BIN_DIR}" DIRECTORY)
                set(ENV{JAVA_HOME} "${_JAVA_HOME_DETECTED}")
                message(STATUS "Auto-detected JAVA_HOME: ${_JAVA_HOME_DETECTED}")
            endif()
        endif()
        find_package(JNI QUIET)
        if(JNI_FOUND)
            # Project-wide include so IDE resolves jni.h in all files
            include_directories(SYSTEM ${JNI_INCLUDE_DIRS})
            message(STATUS "JNI include dirs: ${JNI_INCLUDE_DIRS}")
        else()
            message(WARNING "JNI not found. Set JAVA_HOME for IDE indexing.")
        endif()
    endif()

    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/jni/CMakeLists.txt")
        message(STATUS "Building JNI bridge for Android/JVM")
        add_subdirectory(src/jni)
    endif()
endif()

# =============================================================================
# COMMONS-LOCAL BACKENDS (RAG)
#
# Engine plugins (LlamaCPP, ONNX, WhisperCPP, WhisperKit CoreML, MetalRT)
# are wired exclusively from engines/<name>/CMakeLists.txt via the root
# add_subdirectory(engines) path. Commons no longer instantiates or forwards
# engine targets — only commons-local OBJECT libraries (RAG) are folded into
# rac_commons below.
# =============================================================================

# Decouple RAG from RAC_BUILD_BACKENDS so the proto C ABI symbols
# (`rac_rag_query_proto` etc.) referenced from src/solutions/operators/
# op_engine_backed.cpp are always resolvable inside librac_commons. RAG
# only depends on USearch + nlohmann_json (header-only) — no llama.cpp /
# ONNX runtime pull-in — so it is safe to enable on every host preset
# even when the heavier engines are gated behind RAC_BUILD_BACKENDS.
if(RAC_BACKEND_RAG
   AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/features/rag/CMakeLists.txt")
    message(STATUS "Building RAG pipeline (USearch) — folded into rac_commons")
    add_subdirectory(src/features/rag)

    # RAG is an OBJECT library. Fold its compiled objects into rac_commons
    # so there is no separate librac_backend_rag binary to distribute.
    target_sources(rac_commons PRIVATE $<TARGET_OBJECTS:rac_backend_rag>)

    # Propagate RAG's non-cyclic dependencies manually.
    # We intentionally do NOT use target_link_libraries(rac_commons PRIVATE rac_backend_rag)
    # because that would transitively pull in rac_backend_onnx (via the ONNX embedding
    # provider) and create a shared-library cycle:
    #   rac_commons -> rac_backend_rag -> rac_backend_onnx -> rac_commons
    # nlohmann_json is already linked project-wide.
    # Apple frameworks used by RAG (Accelerate) need explicit propagation.
    if(APPLE)
        target_link_libraries(rac_commons PUBLIC "-framework Accelerate")
    endif()
    target_compile_definitions(rac_commons PRIVATE RAC_HAVE_RAG=1)
endif()

# =============================================================================
# SERVER (OpenAI-compatible HTTP Server)
# =============================================================================

if(RAC_BUILD_SERVER)
    message(STATUS "Building OpenAI-compatible HTTP server...")
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/server/CMakeLists.txt")
        add_subdirectory(src/server)
    else()
        message(WARNING "Server source directory not found: src/server/")
    endif()

    # Also build the standalone server binary
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/CMakeLists.txt")
        add_subdirectory(tools)
    endif()
endif()

# =============================================================================
# TESTS
# =============================================================================

if(RAC_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# =============================================================================
# INSTALLATION
# =============================================================================

install(TARGETS rac_commons
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/
    DESTINATION include
    FILES_MATCHING PATTERN "*.h"
)

# =============================================================================
# CONFIGURATION SUMMARY
# =============================================================================

message(STATUS "")
message(STATUS "====================================")
message(STATUS "RunAnywhere Commons v${RAC_VERSION}")
message(STATUS "====================================")
message(STATUS "Platform:       ${RAC_PLATFORM_NAME}")
message(STATUS "Build type:     ${CMAKE_BUILD_TYPE}")
message(STATUS "Compiler:       ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "Shared libs:    ${RAC_BUILD_SHARED}")
message(STATUS "")
message(STATUS "Components:")
message(STATUS "  Core:         Logging, errors, events, memory")
message(STATUS "  Registry:     Service & module registration")
message(STATUS "  Models:       Download strategies, storage")
message(STATUS "  Services:     LLM, STT, TTS, VAD interfaces")
if(APPLE AND RAC_BUILD_PLATFORM)
    message(STATUS "  Platform:     Apple Foundation Models, System TTS")
endif()
if(RAC_PLATFORM_WINDOWS)
    message(STATUS "  Platform:     Windows (MSVC)")
endif()
# RAG is folded into rac_commons regardless of RAC_BUILD_BACKENDS (see the
# decoupled add_subdirectory above); print its status unconditionally.
if(RAC_BACKEND_RAG)
    message(STATUS "  RAG pipeline: Enabled (folded into rac_commons)")
endif()
if(RAC_BUILD_SERVER)
    message(STATUS "  Server:       OpenAI-compatible HTTP server (runanywhere-server)")
endif()
message(STATUS "")
message(STATUS "JNI bridge:     ${RAC_BUILD_JNI}")
message(STATUS "HTTP Server:    ${RAC_BUILD_SERVER}")
message(STATUS "Protobuf ABI:   ${RAC_PROTOBUF_RUNTIME_ENABLED}")
message(STATUS "Solutions API:  ${RAC_SOLUTIONS_RUNTIME_ENABLED}")
message(STATUS "====================================")
message(STATUS "")
