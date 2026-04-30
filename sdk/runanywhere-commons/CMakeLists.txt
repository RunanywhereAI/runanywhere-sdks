cmake_minimum_required(VERSION 3.22)

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

# T5.4: per-engine RAC_BACKEND_<name> options now live in engines/<name>/CMakeLists.txt.
# Only commons-local backends (RAG pipeline) declare their option here.
option(RAC_BACKEND_RAG "Build RAG pipeline (USearch vector search)" ON)

# Emscripten: force the RAG backend OFF. FetchONNXRuntime.cmake has no WASM
# binary distribution (it expects headers under third_party/onnxruntime-wasm/
# which are not vendored in this tree), so the RAG ONNX embedding TUs fail
# to compile with `onnxruntime_c_api.h: file not found`. The ONNX WASM story
# is delivered by `onnxruntime-web` (JavaScript package) from the frontend;
# commons does not need an in-module ONNX runtime on WASM.
# TODO(v0.21): wire a real ONNX Runtime WASM binary and flip this back to
# default ON when the onnxruntime-wasm third_party package lands.
if(EMSCRIPTEN)
    set(RAC_BACKEND_RAG OFF CACHE BOOL "" FORCE)
endif()
option(RAC_BUILD_SERVER "Build OpenAI-compatible HTTP server (runanywhere-server)" OFF)

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
if(MSVC OR ANDROID OR EMSCRIPTEN)
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
# -----------------------------------------------------------------------------
set(_RAC_FORCE_BUNDLED_ZLIB OFF)
if(EMSCRIPTEN)
    set(_RAC_FORCE_BUNDLED_ZLIB ON)
endif()

if(_RAC_FORCE_BUNDLED_ZLIB)
    message(STATUS "Emscripten build: forcing bundled zlib")
    set(ZLIB_FOUND FALSE)
else()
    find_package(ZLIB QUIET)
endif()

if(NOT ZLIB_FOUND)
    message(STATUS "System zlib not found — bundling from source...")
    FetchContent_Declare(
        zlib_src
        GIT_REPOSITORY https://github.com/madler/zlib.git
        GIT_TAG        v1.3.1
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

    if((ANDROID OR EMSCRIPTEN) AND TARGET zlibstatic)
        set_target_properties(zlibstatic PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY "${RAC_BUNDLED_LIB_DIR}"
        )
        set(_RAC_ZLIB_LIBRARY_PATH "${RAC_BUNDLED_LIB_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}z${CMAKE_STATIC_LIBRARY_SUFFIX}")
    endif()

    # Set cache variables so libarchive/curl's find_package(ZLIB) picks up our
    # build. Android/Emscripten need the concrete archive path here; passing
    # the logical target name through cache variables leaks raw `zlibstatic`
    # / `-lzlibstatic` entries into downstream link lines.
    set(ZLIB_INCLUDE_DIR "${zlib_src_SOURCE_DIR};${zlib_src_BINARY_DIR}" CACHE PATH "" FORCE)
    set(ZLIB_INCLUDE_DIRS "${zlib_src_SOURCE_DIR};${zlib_src_BINARY_DIR}" CACHE PATH "" FORCE)
    if(ANDROID OR EMSCRIPTEN)
        set(ZLIB_LIBRARY "${_RAC_ZLIB_LIBRARY_PATH}" CACHE FILEPATH "" FORCE)
        set(ZLIB_LIBRARY_RELEASE "${_RAC_ZLIB_LIBRARY_PATH}" CACHE FILEPATH "" FORCE)
        set(ZLIB_LIBRARIES "${_RAC_ZLIB_LIBRARY_PATH}" CACHE FILEPATH "" FORCE)
    else()
        set(ZLIB_LIBRARY zlibstatic CACHE STRING "" FORCE)
        set(ZLIB_LIBRARIES zlibstatic CACHE STRING "" FORCE)
    endif()
    set(ZLIB_FOUND TRUE CACHE BOOL "" FORCE)
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
    message(STATUS "Bundled zlib ready (v1.3.1)")
else()
    message(STATUS "Using system zlib: ${ZLIB_LIBRARIES}")
endif()

# -----------------------------------------------------------------------------
# BZip2: Bundle from source for cross-compilation targets
# Android NDK and Emscripten don't ship libbz2. macOS/iOS have it in the SDK.
# We try system first; if not found, build from source so libarchive gets it.
# -----------------------------------------------------------------------------
set(_RAC_FORCE_BUNDLED_BZIP2 OFF)
if(ANDROID OR EMSCRIPTEN)
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
        URL https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
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

    if((ANDROID OR EMSCRIPTEN) AND TARGET bz2_bundled)
        set_target_properties(bz2_bundled PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY "${RAC_BUNDLED_LIB_DIR}"
        )
        set(_RAC_BZIP2_LIBRARY_PATH "${RAC_BUNDLED_LIB_DIR}/${CMAKE_STATIC_LIBRARY_PREFIX}bz2_bundled${CMAKE_STATIC_LIBRARY_SUFFIX}")
    endif()

    # Set cache variables so libarchive's find_package(BZip2) picks up our
    # build. Android/Emscripten again need the concrete archive path.
    set(BZIP2_INCLUDE_DIR "${bzip2_src_SOURCE_DIR}" CACHE PATH "" FORCE)
    if(ANDROID OR EMSCRIPTEN)
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
    message(STATUS "Bundled BZip2 ready (v1.0.8)")
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
set(_SAVED_BUILD_SHARED_LIBS ${BUILD_SHARED_LIBS})
set(BUILD_SHARED_LIBS OFF)
FetchContent_MakeAvailable(libarchive)
set(BUILD_SHARED_LIBS ${_SAVED_BUILD_SHARED_LIBS})

if(TARGET bz2_bundled AND TARGET archive_static)
    target_link_libraries(archive_static bz2_bundled)
endif()

# Link bundled zlib to libarchive if we built it from source
if(TARGET zlibstatic AND TARGET archive_static)
    target_link_libraries(archive_static zlibstatic)
    target_include_directories(archive_static PRIVATE ${zlib_src_SOURCE_DIR} ${zlib_src_BINARY_DIR})
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
elseif(ANDROID OR EMSCRIPTEN)
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
# libcurl (v2 close-out Phase H — HTTP transport into commons)
# =============================================================================
# Used by src/infrastructure/http/rac_http_client_curl.cpp. Prefer the
# system package (brew/apt/NDK/Xcode SDK); only fall back to
# FetchContent on targets where libcurl isn't reliably on the
# CMAKE_PREFIX_PATH (Windows MSVC, some CI runners).
find_package(CURL QUIET)
if(NOT CURL_FOUND)
    message(STATUS "System libcurl not found — bundling curl-7_88_1 via FetchContent...")
    if(NOT DEFINED CURL_FETCH_VERSION)
        set(CURL_FETCH_VERSION "curl-7_88_1")
    endif()
    FetchContent_Declare(
        curl_fetched
        GIT_REPOSITORY https://github.com/curl/curl.git
        GIT_TAG        ${CURL_FETCH_VERSION}
        GIT_SHALLOW    TRUE
    )
    set(BUILD_CURL_EXE      OFF CACHE BOOL "" FORCE)
    set(BUILD_SHARED_LIBS   OFF CACHE BOOL "" FORCE)
    set(CURL_ENABLE_EXPORT_TARGET OFF CACHE BOOL "" FORCE)
    set(CURL_STATICLIB      ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_LDAP   ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_LDAPS  ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_RTSP   ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_DICT   ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_FILE   ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_FTP    ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_GOPHER ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_IMAP   ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_MQTT   ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_POP3   ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_SMB    ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_SMTP   ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_TELNET ON  CACHE BOOL "" FORCE)
    set(CURL_DISABLE_TFTP   ON  CACHE BOOL "" FORCE)
    set(BUILD_TESTING       OFF CACHE BOOL "" FORCE)
    # Pick a TLS backend sensibly per platform when bundling. Apple/Windows
    # use the native provider so we don't pull OpenSSL into the iOS
    # xcframework or the Windows DLL. `CURL_USE_SECTRANSP` / `CURL_USE_SCHANNEL`
    # are the curl 7.86+ variable names; the pre-7.86 `CMAKE_USE_*` names
    # are no longer honoured by curl 7.88.1. Explicitly disable OpenSSL so
    # curl's CMake doesn't fall through to `find_package(OpenSSL REQUIRED)`
    # which has no valid target on the iOS sysroot.
    if(APPLE)
        set(CURL_USE_SECTRANSP ON  CACHE BOOL "" FORCE)
        set(CURL_USE_OPENSSL   OFF CACHE BOOL "" FORCE)
    elseif(WIN32)
        set(CURL_USE_SCHANNEL ON  CACHE BOOL "" FORCE)
        set(CURL_USE_OPENSSL  OFF CACHE BOOL "" FORCE)
    elseif(EMSCRIPTEN)
        # WASM runtime: HTTPS flows through the browser's fetch() API via
        # Emscripten FETCH, not libcurl. Compile curl without TLS.
        set(CURL_USE_OPENSSL   OFF CACHE BOOL "" FORCE)
        set(CURL_DISABLE_HTTPS ON  CACHE BOOL "" FORCE)
    elseif(ANDROID)
        # Android: bundle mbedTLS via FetchContent so curl has a working TLS
        # backend baked into the static library. The Android NDK does NOT ship
        # OpenSSL (it was removed in NDK r19+), and the comment block in the
        # earlier round-1 attempt that claimed "use Android system SSL via
        # find_package(OpenSSL)" was wrong: find_package(OpenSSL) returns
        # nothing on a stock NDK sysroot, so curl fell through to compiling
        # WITHOUT TLS, which silently disables HTTPS at the protocol-check
        # stage (CURLE_UNSUPPORTED_PROTOCOL = 1, exactly what AG-DV1/2/3
        # observed in Phase 8 device testing).
        #
        # mbedTLS is small (~1MB), self-contained, and curl supports it via
        # CURL_USE_MBEDTLS=ON. We FetchContent it before curl so its targets
        # exist at curl's `find_package(MbedTLS)` lookup.
        FetchContent_Declare(
            mbedtls_fetched
            GIT_REPOSITORY https://github.com/Mbed-TLS/mbedtls.git
            GIT_TAG        v3.6.2
            GIT_SHALLOW    TRUE
        )
        set(ENABLE_PROGRAMS    OFF CACHE BOOL "" FORCE)
        set(ENABLE_TESTING     OFF CACHE BOOL "" FORCE)
        set(USE_SHARED_MBEDTLS_LIBRARY OFF CACHE BOOL "" FORCE)
        set(USE_STATIC_MBEDTLS_LIBRARY ON  CACHE BOOL "" FORCE)
        set(MBEDTLS_AS_SUBPROJECT      ON  CACHE BOOL "" FORCE)
        FetchContent_MakeAvailable(mbedtls_fetched)
        # Tell curl to use mbedTLS. Curl 7.88.1's CMake looks for `MBEDTLS::*`
        # imported targets and `MBEDTLS_INCLUDE_DIRS` / `MBEDTLS_LIBRARIES`.
        # mbedTLS 3.6.x exports `MbedTLS::mbedtls`, `MbedTLS::mbedx509`,
        # `MbedTLS::mbedcrypto` — translate those into the variable names curl
        # expects.
        set(CURL_USE_OPENSSL  OFF CACHE BOOL "" FORCE)
        set(CURL_USE_MBEDTLS  ON  CACHE BOOL "" FORCE)
        if(TARGET MbedTLS::mbedtls)
            get_target_property(_rac_mbedtls_inc MbedTLS::mbedtls INTERFACE_INCLUDE_DIRECTORIES)
            set(MBEDTLS_INCLUDE_DIRS "${_rac_mbedtls_inc}" CACHE PATH "" FORCE)
            set(MBEDTLS_LIBRARY      $<TARGET_FILE:MbedTLS::mbedtls>     CACHE FILEPATH "" FORCE)
            set(MBEDX509_LIBRARY     $<TARGET_FILE:MbedTLS::mbedx509>    CACHE FILEPATH "" FORCE)
            set(MBEDCRYPTO_LIBRARY   $<TARGET_FILE:MbedTLS::mbedcrypto>  CACHE FILEPATH "" FORCE)
        endif()
        # Explicitly DO NOT disable HTTPS — that's the old bug.
    endif()
    FetchContent_MakeAvailable(curl_fetched)
    # The target built by curl's CMake is `libcurl` (static).
    if(TARGET libcurl AND NOT TARGET CURL::libcurl)
        add_library(CURL::libcurl ALIAS libcurl)
    elseif(TARGET libcurl_static AND NOT TARGET CURL::libcurl)
        add_library(CURL::libcurl ALIAS libcurl_static)
    endif()
    set(CURL_FOUND TRUE CACHE BOOL "" FORCE)
    message(STATUS "Bundled libcurl ready (${CURL_FETCH_VERSION})")
else()
    message(STATUS "Using system libcurl: ${CURL_LIBRARIES}")
endif()

# =============================================================================
# SERVER DEPENDENCIES (FetchContent)
# =============================================================================

if(RAC_BUILD_SERVER)
    # cpp-httplib - header-only HTTP library (same as llama.cpp uses)
    FetchContent_Declare(
        cpp-httplib
        GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
        GIT_TAG v0.15.3
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
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
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
    src/core/rac_audio_utils.cpp
    src/core/component_types.cpp
    src/core/events.cpp
    src/core/sdk_state.cpp
    src/core/rac_structured_error.cpp
    src/core/capabilities/lifecycle_manager.cpp
    src/core/rac_error_model.cpp
)

# Infrastructure sources - registry, model management, network, telemetry
set(RAC_INFRASTRUCTURE_SOURCES
    src/infrastructure/events/event_publisher.cpp
    src/infrastructure/registry/module_registry.cpp
    # v3.0.0 (C1): legacy service_registry.cpp DELETED. Plugin registration
    # now flows exclusively through rac_plugin_registry.cpp below.
    src/plugin/rac_plugin_registry.cpp
    # GAP 03 Phase 1: dynamic plugin loader (dlopen path; gated by RAC_PLUGIN_MODE_SHARED).
    src/plugin/plugin_loader.cpp
    # T4.1: L1 runtime-plugin registry (CPU / Metal / CoreML / CUDA / …). The
    # built-in CPU runtime plugin lives under runtimes/cpu/ and is folded into
    # rac_commons by the root CMakeLists so the registry is never empty.
    src/plugin/rac_runtime_registry.cpp
    # GAP 04 Phase 9-10: HardwareProfile + EngineRouter (hardware-aware plugin scoring).
    src/router/rac_hardware_profile.cpp
    src/router/rac_engine_router.cpp
    # GAP 04 Phase 12: C ABI wrapper around EngineRouter (rac_plugin_route).
    src/router/rac_route.cpp
    # Round-1 CPP fix (G-C6): proto-serialised hardware profile C ABI for all 5 frontends.
    src/router/rac_hardware_abi.cpp
    src/infrastructure/download/download_manager.cpp
    src/infrastructure/download/download_orchestrator.cpp
    src/infrastructure/model_management/model_registry.cpp
    src/infrastructure/model_management/lora_registry.cpp
    src/infrastructure/model_management/model_types.cpp
    src/infrastructure/model_management/model_paths.cpp
    src/infrastructure/model_management/model_strategy.cpp
    src/infrastructure/model_management/model_assignment.cpp
    src/infrastructure/model_management/model_compatibility.cpp
    src/infrastructure/storage/storage_analyzer.cpp
    src/infrastructure/file_management/file_manager.cpp
    src/infrastructure/network/environment.cpp
    src/infrastructure/network/endpoints.cpp
    src/infrastructure/network/api_types.cpp
    src/infrastructure/network/auth_manager.cpp
    src/infrastructure/network/development_config.cpp
    # v2 close-out Phase H — native HTTP transport (libcurl-backed).
    # Replaces the HttpURLConnection path in CppBridgeDownload.kt.
    src/infrastructure/http/rac_http_client_curl.cpp
    src/infrastructure/http/rac_http_download.cpp
    src/infrastructure/telemetry/telemetry_types.cpp
    src/infrastructure/telemetry/telemetry_json.cpp
    src/infrastructure/telemetry/telemetry_manager.cpp
    src/infrastructure/device/rac_device_manager.cpp
    src/infrastructure/extraction/rac_extraction.cpp
    # v3.1 Phase 9: DAG streaming runtime (GAP 05 Phase 2). The primitives
    # under include/rac/graph/ (CancelToken / StreamEdge / RingBuffer /
    # MemoryPool / PipelineNode) are header-only templates; only the
    # non-templated GraphScheduler has a .cpp to compile here.
    src/graph/graph_scheduler.cpp
)

# Feature sources - LLM, STT, TTS, VAD, Wake Word, VLM, Diffusion (iOS/Apple only)
set(RAC_FEATURES_SOURCES
    # LLM
    src/features/llm/llm_component.cpp
    src/features/llm/rac_llm_service.cpp
    src/features/llm/streaming_metrics.cpp
    src/features/llm/llm_analytics.cpp
    src/features/llm/structured_output.cpp
    # v2 close-out Phase 5: thinking-content split (replaces Swift
    # ThinkingContentParser; rac_llm_split_thinking_tokens C ABI)
    src/features/llm/rac_llm_thinking.cpp
    src/features/llm/tool_calling.cpp
    # v2 close-out Phase G-2: proto-byte LLM stream ABI (mirrors
    # voice_agent/rac_voice_event_abi.cpp; replaces per-SDK hand-rolled
    # AsyncThrowingStream / callbackFlow / tokenQueue shims).
    src/features/llm/rac_llm_stream.cpp
    # STT
    src/features/stt/stt_component.cpp
    src/features/stt/rac_stt_service.cpp
    src/features/stt/stt_analytics.cpp
    # TTS
    src/features/tts/tts_component.cpp
    src/features/tts/rac_tts_service.cpp
    src/features/tts/tts_analytics.cpp
    # VAD
    src/features/vad/vad_component.cpp
    src/features/vad/energy_vad.cpp
    src/features/vad/vad_analytics.cpp
    # Wake Word — high-level service scaffold was removed in Phase F of the
    # v2 close-out (see docs/v2_closeout_engine_decisions.md). All real
    # consumers call the speech backend's rac_wakeword_onnx_* compatibility
    # API directly. The shared types in
    # include/rac/features/wakeword/rac_wakeword_types.h remain.
    # Round-1 CPP fix (§9): Wake Word C ABI stubs so frontends link without crashing.
    src/features/wakeword/rac_wake_word.cpp
    # Round-1 CPP fix (§8): Speaker Diarization C ABI stubs.
    src/features/speaker_diarization/rac_speaker_diarization.cpp
    # VLM (Vision Language Model)
    src/features/vlm/vlm_component.cpp
    src/features/vlm/rac_vlm_service.cpp
    # Diffusion
    src/features/diffusion/diffusion_component.cpp
    src/features/diffusion/rac_diffusion_service.cpp
    src/features/diffusion/diffusion_model_registry.cpp
    src/features/diffusion/diffusion_json.cpp
    src/features/diffusion/rac_diffusion_tokenizer.cpp
    # Embeddings
    src/features/embeddings/rac_embeddings_service.cpp
    src/features/embeddings/embeddings_component.cpp
    # Voice Agent
    src/features/voice_agent/voice_agent.cpp
    # GAP 09 Phase 15: proto-byte event ABI (coexists with struct callback).
    src/features/voice_agent/rac_voice_event_abi.cpp
    # GAP 05 Phase 2: GraphScheduler-driven VAD→STT→LLM→TTS pipeline.
    # First v3.1 Phase 9 DAG consumer; replaces the in-line process_stream
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

# T5.4: WhisperKit CoreML sources are owned by engines/whisperkit_coreml/
# which declares its own rac_backend_whisperkit_coreml target (via
# rac_add_engine_plugin). Commons no longer compiles those TUs directly.

# T4.7 Solutions C ABI — always-built fallback.
#
# The full SolutionRunner implementation (rac_solution.cpp + companions)
# requires Protobuf and is added to rac_commons inside the Protobuf_FOUND
# block below. On cross-compilation targets (iOS / Android / WASM) Protobuf
# is typically not discoverable, so without this stub TU every downstream
# binding (Swift facade, JNI thunks, RN HybridRunAnywhereCore, Flutter FFI,
# Web exports) would fail to link against the rac_solution_* symbols.
#
# rac_solution_stub.cpp is gated on `#ifndef RAC_HAVE_PROTOBUF`, so when the
# Protobuf branch defines RAC_HAVE_PROTOBUF=1 the stub TU compiles to an
# empty object and the real symbols from rac_solution.cpp win at link time.
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
# and drop this Android-specific override.
if(ANDROID)
    set_target_properties(rac_commons PROPERTIES
        C_VISIBILITY_PRESET   default
        CXX_VISIBILITY_PRESET default
        VISIBILITY_INLINES_HIDDEN OFF
    )
    target_compile_options(rac_commons PRIVATE -fvisibility=default)
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

# libcurl — PUBLIC so tests and SDK adapters (rac_commons_jni) pick it
# up transitively.
if(TARGET CURL::libcurl)
    target_link_libraries(rac_commons PUBLIC CURL::libcurl)
else()
    target_link_libraries(rac_commons PUBLIC ${CURL_LIBRARIES})
    target_include_directories(rac_commons PUBLIC ${CURL_INCLUDE_DIRS})
endif()

# =============================================================================
# Protobuf — optional, gates RAC_HAVE_PROTOBUF
#
# v2 close-out Phase 2: when Protobuf is available, link the generated
# voice_events / model_types / pipeline / solutions C++ classes into
# rac_commons + define RAC_HAVE_PROTOBUF so rac_voice_event_abi.cpp can
# serialize VoiceEvent and dispatch the proto-byte callback wired up by
# the GAP 09 Phase 15 ABI. When Protobuf is missing, the same source files
# fall back to the FEATURE_NOT_AVAILABLE path declared in the header.
# =============================================================================

find_package(Protobuf QUIET)

# v2 close-out: SHARED builds need absl symbols (see cmake/protobuf.cmake).
# Find absl independently here too for standalone-commons builds that
# bypass the root CMake.
if(NOT DEFINED RAC_ABSL_LIBS)
    find_package(absl QUIET CONFIG)
    if(absl_FOUND)
        set(RAC_ABSL_LIBS absl::log absl::log_internal_check_op absl::hash absl::strings absl::status)
    else()
        set(RAC_ABSL_LIBS "")
    endif()
endif()
if(Protobuf_FOUND)
    set(_RAC_PROTO_GEN_DIR ${CMAKE_CURRENT_SOURCE_DIR}/src/generated/proto)
    if(EXISTS ${_RAC_PROTO_GEN_DIR}/voice_events.pb.cc)
        target_sources(rac_commons PRIVATE
            ${_RAC_PROTO_GEN_DIR}/voice_events.pb.cc
            ${_RAC_PROTO_GEN_DIR}/model_types.pb.cc
            ${_RAC_PROTO_GEN_DIR}/pipeline.pb.cc
            ${_RAC_PROTO_GEN_DIR}/solutions.pb.cc
            # v2 close-out Phase G-2: LLMStreamEvent for the proto-byte
            # LLM stream ABI (rac_llm_stream.cpp).
            ${_RAC_PROTO_GEN_DIR}/llm_service.pb.cc
            # Phase C6: per-modality option / event protos consumed by the
            # foundation/rac_proto_adapters layer.
            ${_RAC_PROTO_GEN_DIR}/stt_options.pb.cc
            ${_RAC_PROTO_GEN_DIR}/tts_options.pb.cc
            ${_RAC_PROTO_GEN_DIR}/vad_options.pb.cc
            ${_RAC_PROTO_GEN_DIR}/vlm_options.pb.cc
            ${_RAC_PROTO_GEN_DIR}/diffusion_options.pb.cc
            ${_RAC_PROTO_GEN_DIR}/embeddings_options.pb.cc
            ${_RAC_PROTO_GEN_DIR}/rag.pb.cc
            ${_RAC_PROTO_GEN_DIR}/storage_types.pb.cc
            ${_RAC_PROTO_GEN_DIR}/lora_options.pb.cc
            ${_RAC_PROTO_GEN_DIR}/errors.pb.cc
            # Phase C6: proto <-> C ABI adapter functions (foundation layer).
            src/foundation/rac_proto_adapters.cpp
        )
        # MF-3 (AG-V3): the generated proto headers and the protobuf
        # include path must stay PRIVATE — they are an implementation
        # detail of rac_commons (consumed only by rac_proto_adapters.cpp
        # and the Solutions T4.7 sources below). Exposing them via
        # PUBLIC leaks `runanywhere::v1::*` proto types and the entire
        # google::protobuf / absl transitive include set into every L5
        # consumer (Swift CRACommons, Kotlin JNI, Web/Flutter/RN).
        target_include_directories(rac_commons PRIVATE
            $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src/generated/proto>
            $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src/generated>
            ${Protobuf_INCLUDE_DIRS}
        )
        # Prefer the modern imported target when available so transitive deps
        # (absl, etc.) flow through without us listing them by hand.
        # PRIVATE: protobuf is an implementation detail of rac_commons
        # (Wave 5 Step 5.1 / RC-12 — solution headers forward-decl proto
        # types; consumers must not be forced to link libprotobuf).
        if(TARGET protobuf::libprotobuf)
            target_link_libraries(rac_commons PRIVATE protobuf::libprotobuf)
        else()
            target_link_libraries(rac_commons PRIVATE ${Protobuf_LIBRARIES})
        endif()
        # v2 close-out: when SHARED, absl symbols must resolve at link
        # time. RAC_ABSL_LIBS comes from cmake/protobuf.cmake (or the
        # block above for standalone-commons). PUBLIC so consumers
        # (engine plugins built as SHARED) inherit the deps.
        if(RAC_ABSL_LIBS)
            target_link_libraries(rac_commons PUBLIC ${RAC_ABSL_LIBS})
        endif()
        # MF-3 (AG-V3): RAC_HAVE_PROTOBUF must stay PRIVATE so the proto
        # `#ifdef` guard inside rac/foundation/rac_proto_adapters.h does
        # not activate for L5 consumers. Only rac_commons internal TUs
        # (rac_proto_adapters.cpp, the Solutions/Pipeline sources, the
        # rac_llm_stream proto-byte ABI) need the definition.
        target_compile_definitions(rac_commons PRIVATE RAC_HAVE_PROTOBUF=1)
        message(STATUS "Protobuf: linked voice_events.pb + RAC_HAVE_PROTOBUF=1 (Phase 2)")

        # T4.7: SolutionRunner + PipelineExecutor + C ABI. Gated on
        # Protobuf because the implementation walks PipelineSpec /
        # SolutionConfig messages directly. The neutral operator
        # registry keeps the subsystem engine-agnostic; real backends
        # register their factories at startup.
        target_sources(rac_commons PRIVATE
            src/solutions/operator_registry.cpp
            src/solutions/pipeline_executor.cpp
            src/solutions/solution_converter.cpp
            src/solutions/solution_runner.cpp
            src/solutions/config_loader.cpp
            src/solutions/rac_solution.cpp
        )
        message(STATUS "T4.7: SolutionRunner + PipelineExecutor compiled into rac_commons")
    else()
        message(STATUS "Protobuf found but src/generated/proto/*.pb.cc absent — proto event ABI inactive")
    endif()
else()
    message(STATUS "Protobuf not found — rac_voice_agent_set_proto_callback / rac_llm_set_stream_proto_callback fall back to hand-encoded wire format (no libprotobuf dependency)")
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
# GAP 03: Plugin Loading Mode (static vs. dynamic)
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
# T5.4: engine plugins (LlamaCPP, ONNX, WhisperCPP, WhisperKit CoreML, MetalRT)
# are wired exclusively from engines/<name>/CMakeLists.txt via the root
# add_subdirectory(engines) path. Commons no longer instantiates or forwards
# engine targets — only commons-local OBJECT libraries (RAG) are folded into
# rac_commons below.
# =============================================================================

if(RAC_BUILD_BACKENDS AND RAC_BACKEND_RAG
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
if(RAC_BUILD_BACKENDS)
    # T5.4: per-engine RAC_BACKEND_<name> status is printed by each
    # engines/<name>/CMakeLists.txt; commons only reports its RAG flag.
    if(RAC_BACKEND_RAG)
        message(STATUS "  RAG pipeline: Enabled (folded into rac_commons)")
    endif()
endif()
if(RAC_BUILD_SERVER)
    message(STATUS "  Server:       OpenAI-compatible HTTP server (runanywhere-server)")
endif()
message(STATUS "")
message(STATUS "JNI bridge:     ${RAC_BUILD_JNI}")
message(STATUS "HTTP Server:    ${RAC_BUILD_SERVER}")
message(STATUS "====================================")
message(STATUS "")
