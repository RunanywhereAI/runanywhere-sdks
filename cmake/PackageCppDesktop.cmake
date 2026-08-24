# Script-mode packager for the C++ desktop kit.
# Invoked from the package-cpp-desktop custom target.
#
# Required -D (see cmake/CppDesktopKit.cmake):
#   RAC_SOURCE_DIR RAC_BINARY_DIR RAC_VERSION RAC_PLUGIN_API_VERSION
#   RAC_COMMONS_FILE RAC_KIT_LIBS_FILE RAC_KIT_OUT

if(NOT RAC_SOURCE_DIR OR NOT RAC_COMMONS_FILE OR NOT RAC_KIT_OUT)
    message(FATAL_ERROR "PackageCppDesktop: RAC_SOURCE_DIR, RAC_COMMONS_FILE, RAC_KIT_OUT required")
endif()

file(REMOVE_RECURSE "${RAC_KIT_OUT}")
file(MAKE_DIRECTORY "${RAC_KIT_OUT}/include")
file(MAKE_DIRECTORY "${RAC_KIT_OUT}/lib/cmake/RunAnywhere")
file(MAKE_DIRECTORY "${RAC_KIT_OUT}/share/runanywhere/idl")
file(MAKE_DIRECTORY "${RAC_KIT_OUT}/third_party")

file(COPY "${RAC_SOURCE_DIR}/core/include/rac" DESTINATION "${RAC_KIT_OUT}/include")

file(GLOB _protos "${RAC_SOURCE_DIR}/idl/*.proto")
if(_protos)
    file(COPY ${_protos} DESTINATION "${RAC_KIT_OUT}/share/runanywhere/idl")
endif()

# Generated C++ proto headers (same protoc that built commons). RCLI includes
# these; it must not run a second protoc. .pb.cc stays inside librac_commons.a.
set(_proto_gen "${RAC_SOURCE_DIR}/core/src/generated/proto")
if(NOT EXISTS "${_proto_gen}/model_types.pb.h")
    message(FATAL_ERROR
        "PackageCppDesktop: missing ${_proto_gen}/model_types.pb.h. "
        "Configure/build commons with protobuf before packaging the kit.")
endif()
file(MAKE_DIRECTORY "${RAC_KIT_OUT}/include/runanywhere/proto")
file(GLOB _pb_headers "${_proto_gen}/*.pb.h")
file(COPY ${_pb_headers} DESTINATION "${RAC_KIT_OUT}/include/runanywhere/proto")

# SCHEMA_LOCK is the cross-repo proto fingerprint. RCLI pins the SHA and
# refuses a kit whose lock does not match — neither side runs a second protoc.
set(_schema_lock "${RAC_SOURCE_DIR}/idl/SCHEMA_LOCK")
if(NOT EXISTS "${_schema_lock}")
    message(FATAL_ERROR "PackageCppDesktop: missing ${_schema_lock}")
endif()
file(COPY "${_schema_lock}" DESTINATION "${RAC_KIT_OUT}/share/runanywhere")
if(EXISTS "${RAC_SOURCE_DIR}/idl/VERSION")
    file(COPY "${RAC_SOURCE_DIR}/idl/VERSION" DESTINATION "${RAC_KIT_OUT}/share/runanywhere")
endif()

macro(_kit_lock_key key var)
    set(${var} "")
    file(STRINGS "${_schema_lock}" _hit REGEX "^${key}=")
    if(_hit)
        list(GET _hit 0 _line)
        string(REGEX REPLACE "^${key}=" "" ${var} "${_line}")
        string(STRIP "${${var}}" ${var})
    endif()
endmacro()
_kit_lock_key(IDL_VERSION RUNANYWHERE_KIT_IDL_VERSION)
_kit_lock_key(IDL_SCHEMA_SHA256 RUNANYWHERE_KIT_IDL_SCHEMA_SHA256)
_kit_lock_key(IDL_PROTOC_VERSION RUNANYWHERE_KIT_IDL_PROTOC_VERSION)
_kit_lock_key(IDL_PROTO_COUNT RUNANYWHERE_KIT_IDL_PROTO_COUNT)
if(NOT RUNANYWHERE_KIT_IDL_SCHEMA_SHA256 OR NOT RUNANYWHERE_KIT_IDL_VERSION)
    message(FATAL_ERROR "PackageCppDesktop: idl/SCHEMA_LOCK is missing IDL_SCHEMA_SHA256 or IDL_VERSION")
endif()
if(NOT RUNANYWHERE_KIT_IDL_PROTO_COUNT MATCHES "^[0-9]+$")
    message(FATAL_ERROR "PackageCppDesktop: idl/SCHEMA_LOCK is missing a numeric IDL_PROTO_COUNT")
endif()
file(WRITE "${RAC_KIT_OUT}/include/runanywhere/proto/schema_lock.h"
"#pragma once
// Generated from idl/SCHEMA_LOCK. Do not edit.
#define RUNANYWHERE_IDL_VERSION \"${RUNANYWHERE_KIT_IDL_VERSION}\"
#define RUNANYWHERE_IDL_SCHEMA_SHA256 \"${RUNANYWHERE_KIT_IDL_SCHEMA_SHA256}\"
#define RUNANYWHERE_IDL_PROTOC_VERSION \"${RUNANYWHERE_KIT_IDL_PROTOC_VERSION}\"
#define RUNANYWHERE_IDL_PROTO_COUNT ${RUNANYWHERE_KIT_IDL_PROTO_COUNT}
")

# Vendored protobuf + absl headers so PROTOBUF_VERSION in the generated
# gencode matches the runtime linked from the kit (not Homebrew).
if(NOT RAC_PROTOBUF_INCLUDE_DIR)
    set(RAC_PROTOBUF_INCLUDE_DIR "${RAC_BINARY_DIR}/_deps/protobuf_fetched-src/src")
endif()
if(NOT RAC_ABSL_INCLUDE_DIR)
    set(RAC_ABSL_INCLUDE_DIR "${RAC_BINARY_DIR}/_deps/absl-src")
endif()
if(NOT RAC_UTF8_RANGE_INCLUDE_DIR)
    if(EXISTS "${RAC_BINARY_DIR}/_deps/utf8_range-src/utf8_range.h")
        set(RAC_UTF8_RANGE_INCLUDE_DIR "${RAC_BINARY_DIR}/_deps/utf8_range-src")
    elseif(EXISTS "${RAC_PROTOBUF_INCLUDE_DIR}/../third_party/utf8_range/utf8_range.h")
        set(RAC_UTF8_RANGE_INCLUDE_DIR "${RAC_PROTOBUF_INCLUDE_DIR}/../third_party/utf8_range")
    endif()
endif()
if(RAC_PROTOBUF_INCLUDE_DIR AND EXISTS "${RAC_PROTOBUF_INCLUDE_DIR}/google/protobuf/message.h")
    file(COPY "${RAC_PROTOBUF_INCLUDE_DIR}/google" DESTINATION "${RAC_KIT_OUT}/include"
        FILES_MATCHING PATTERN "*.h" PATTERN "*.inc"
        PATTERN "compiler" EXCLUDE PATTERN "testdata" EXCLUDE)
endif()
if(RAC_ABSL_INCLUDE_DIR AND EXISTS "${RAC_ABSL_INCLUDE_DIR}/absl/strings/string_view.h")
    file(COPY "${RAC_ABSL_INCLUDE_DIR}/absl" DESTINATION "${RAC_KIT_OUT}/include"
        FILES_MATCHING PATTERN "*.h" PATTERN "*.inc"
        PATTERN "testdata" EXCLUDE)
endif()
if(RAC_UTF8_RANGE_INCLUDE_DIR AND EXISTS "${RAC_UTF8_RANGE_INCLUDE_DIR}/utf8_range.h")
    file(COPY "${RAC_UTF8_RANGE_INCLUDE_DIR}/utf8_range.h" DESTINATION "${RAC_KIT_OUT}/include")
    if(EXISTS "${RAC_UTF8_RANGE_INCLUDE_DIR}/utf8_validity.h")
        file(COPY "${RAC_UTF8_RANGE_INCLUDE_DIR}/utf8_validity.h" DESTINATION "${RAC_KIT_OUT}/include")
    endif()
endif()
if(RUNANYWHERE_KIT_PROTOBUF_ISOLATED AND NOT EXISTS "${RAC_KIT_OUT}/include/google/protobuf/message.h")
    message(FATAL_ERROR
        "PackageCppDesktop: isolated protobuf headers missing at "
        "${RAC_KIT_OUT}/include/google/protobuf/message.h "
        "(RAC_PROTOBUF_INCLUDE_DIR=${RAC_PROTOBUF_INCLUDE_DIR})")
endif()
if(RUNANYWHERE_KIT_PROTOBUF_ISOLATED AND NOT EXISTS "${RAC_KIT_OUT}/include/absl/strings/string_view.h")
    message(FATAL_ERROR
        "PackageCppDesktop: absl headers missing at "
        "${RAC_KIT_OUT}/include/absl/strings/string_view.h "
        "(RAC_ABSL_INCLUDE_DIR=${RAC_ABSL_INCLUDE_DIR})")
endif()

file(COPY "${RAC_COMMONS_FILE}" DESTINATION "${RAC_KIT_OUT}/lib")
get_filename_component(_commons_name "${RAC_COMMONS_FILE}" NAME)

set(_extra_link "")
if(EXISTS "${RAC_KIT_LIBS_FILE}")
    file(STRINGS "${RAC_KIT_LIBS_FILE}" _kit_libs)
    foreach(_lib IN LISTS _kit_libs)
        if(EXISTS "${_lib}" AND NOT "${_lib}" STREQUAL "${RAC_COMMONS_FILE}")
            file(COPY "${_lib}" DESTINATION "${RAC_KIT_OUT}/lib")
            get_filename_component(_n "${_lib}" NAME)
            # Backends are whole-archived from a GLOB in RunAnywhereConfig.cmake.
            # Listing them here as well would duplicate the archive as a lazy
            # extra and then REMOVE_DUPLICATES would strip --whole-archive flags.
            if(NOT _n MATCHES "^(lib)?rac_backend_")
                string(APPEND _extra_link "\${RunAnywhere_LIBRARY_DIR}/${_n};")
            endif()
        endif()
    endforeach()
endif()

if(RAC_BINARY_DIR)
    foreach(_pattern
            "libonnxruntime*" "onnxruntime*" "libsherpa-onnx*" "sherpa-onnx*"
            "libomp*" "libggml*" "ggml*")
        file(GLOB_RECURSE _hits
            "${RAC_BINARY_DIR}/${_pattern}.dylib"
            "${RAC_BINARY_DIR}/${_pattern}.so"
            "${RAC_BINARY_DIR}/${_pattern}.so.*"
            "${RAC_BINARY_DIR}/${_pattern}.dll")
        foreach(_hit IN LISTS _hits)
            # ONNX Runtime ships a versioned *dSYM companion* named
            # libonnxruntime.1.x.y.dylib (Mach-O type MH_DSYM). Copying it
            # and letting the real dylib's install name point at it makes
            # dyld abort with "unloadable mach-o file type 10".
            if(APPLE)
                execute_process(COMMAND file --brief "${_hit}" OUTPUT_VARIABLE _ft
                                OUTPUT_STRIP_TRAILING_WHITESPACE
                                RESULT_VARIABLE _ft_rc)
                if(NOT _ft_rc EQUAL 0 OR NOT _ft MATCHES "dynamically linked shared library")
                    continue()
                endif()
            endif()
            file(COPY "${_hit}" DESTINATION "${RAC_KIT_OUT}/third_party")
        endforeach()
    endforeach()
    if(APPLE AND EXISTS "${RAC_KIT_OUT}/third_party/libonnxruntime.dylib")
        # The real dylib advertises LC_ID_DYLIB @rpath/libonnxruntime.1.dylib.
        # There is no loadable file by that name in the kit, so rewrite the id
        # to the file we actually ship.
        execute_process(COMMAND install_name_tool -id
            "@rpath/libonnxruntime.dylib"
            "${RAC_KIT_OUT}/third_party/libonnxruntime.dylib")
    endif()
    # Transitive static runtimes the CLI must link: isolated protobuf, libarchive.
    file(GLOB_RECURSE _static_hits
        "${RAC_BINARY_DIR}/*.a"
        "${RAC_BINARY_DIR}/*.lib")
    foreach(_hit IN LISTS _static_hits)
        get_filename_component(_n "${_hit}" NAME)
        if(_n MATCHES "^(libprotobuf|libprotobuf-lite)\\.(a|lib)$")
            # Isolated commons protobuf (runanywhere_internal::). Rename so
            # find_package(Protobuf) in consumers cannot pick this archive as
            # vanilla google::protobuf.
            if(_n MATCHES "\\.lib$")
                set(_dst "rac_protobuf_isolated.lib")
                if(_n MATCHES "protobuf-lite")
                    set(_dst "rac_protobuf_lite_isolated.lib")
                endif()
            else()
                set(_dst "librac_protobuf_isolated.a")
                if(_n STREQUAL "libprotobuf-lite.a")
                    set(_dst "librac_protobuf_lite_isolated.a")
                endif()
            endif()
            file(COPY "${_hit}" DESTINATION "${RAC_KIT_OUT}/lib")
            file(RENAME "${RAC_KIT_OUT}/lib/${_n}" "${RAC_KIT_OUT}/lib/${_dst}")
            string(APPEND _extra_link "\${RunAnywhere_LIBRARY_DIR}/${_dst};")
        elseif(_n MATCHES "^(libarchive|archive|libutf8_range|utf8_range|libutf8_validity|utf8_validity|libllama-common.*|llama-common.*)\\.(a|lib)$"
           OR _n MATCHES "^libabsl_.*\\.a$"
           OR _n MATCHES "^absl_.*\\.lib$"
           OR _n MATCHES "^(lib)?(zlibstatic|bz2_bundled)\\.(a|lib)$"
           OR _n MATCHES "^onnxruntime\\.lib$")
            file(COPY "${_hit}" DESTINATION "${RAC_KIT_OUT}/lib")
            string(APPEND _extra_link "\${RunAnywhere_LIBRARY_DIR}/${_n};")
        endif()
    endforeach()
endif()

file(WRITE "${RAC_KIT_OUT}/share/runanywhere/VERSION" "${RAC_VERSION}\n")
file(WRITE "${RAC_KIT_OUT}/share/runanywhere/PLUGIN_API_VERSION" "${RAC_PLUGIN_API_VERSION}\n")

if(APPLE)
    set(RUNANYWHERE_KIT_SYSTEM_LIBS "Threads::Threads;ZLIB::ZLIB;CURL::libcurl;dl;bz2")
elseif(WIN32)
    # libcurl (static vcpkg) needs these plus the curl/zlib archives themselves.
    set(RUNANYWHERE_KIT_SYSTEM_LIBS "ws2_32;crypt32;bcrypt;secur32;wldap32;normaliz;advapi32")
    foreach(_root IN ITEMS "$ENV{VCPKG_INSTALLATION_ROOT}" "$ENV{VCPKG_ROOT}")
        if(_root AND EXISTS "${_root}/installed/x64-windows-static/lib")
            set(_vlib "${_root}/installed/x64-windows-static/lib")
            foreach(_n IN ITEMS libcurl.lib zlib.lib)
                if(EXISTS "${_vlib}/${_n}")
                    file(COPY "${_vlib}/${_n}" DESTINATION "${RAC_KIT_OUT}/lib")
                    string(APPEND _extra_link "\${RunAnywhere_LIBRARY_DIR}/${_n};")
                endif()
            endforeach()
            break()
        endif()
    endforeach()
    # rac_commons PUBLIC-links these by bare filename on MSVC. vcpkg zlib.lib
    # does not satisfy a zlibstatic.lib DEFAULTLIB / unresolved reference.
    foreach(_need IN ITEMS zlibstatic.lib bz2_bundled.lib)
        if(NOT EXISTS "${RAC_KIT_OUT}/lib/${_need}")
            set(_hits "")
            foreach(_cand IN ITEMS
                    "${RAC_BINARY_DIR}/${_need}"
                    "${RAC_BINARY_DIR}/lib/${_need}"
                    "${RAC_BINARY_DIR}/lib/Release/${_need}"
                    "${RAC_BINARY_DIR}/lib/Debug/${_need}")
                if(EXISTS "${_cand}")
                    list(APPEND _hits "${_cand}")
                endif()
            endforeach()
            if(NOT _hits)
                file(GLOB_RECURSE _hits "${RAC_BINARY_DIR}/*/${_need}")
            endif()
            if(_hits)
                list(GET _hits 0 _found)
                file(COPY "${_found}" DESTINATION "${RAC_KIT_OUT}/lib")
                string(APPEND _extra_link "\${RunAnywhere_LIBRARY_DIR}/${_need};")
            endif()
        endif()
        if(NOT EXISTS "${RAC_KIT_OUT}/lib/${_need}")
            message(FATAL_ERROR
                "PackageCppDesktop: Windows kit missing ${_need} "
                "(rac_commons PUBLIC-links zlibstatic and bz2_bundled). "
                "Searched ${RAC_BINARY_DIR}.")
        endif()
    endforeach()
else()
    set(RUNANYWHERE_KIT_SYSTEM_LIBS "Threads::Threads;ZLIB::ZLIB;CURL::libcurl;dl;m")
endif()
set(RUNANYWHERE_KIT_EXTRA_LIBS "${_extra_link}")
if(NOT RUNANYWHERE_KIT_COMMONS_ARCHIVE)
    set(RUNANYWHERE_KIT_COMMONS_ARCHIVE "${_commons_name}")
endif()

configure_file(
    "${RAC_SOURCE_DIR}/cmake/RunAnywhereConfig.cmake.in"
    "${RAC_KIT_OUT}/lib/cmake/RunAnywhere/RunAnywhereConfig.cmake"
    @ONLY)

file(WRITE "${RAC_KIT_OUT}/lib/cmake/RunAnywhere/RunAnywhereConfigVersion.cmake"
"set(PACKAGE_VERSION \"${RAC_VERSION}\")
set(PACKAGE_VERSION_COMPATIBLE FALSE)
set(PACKAGE_VERSION_EXACT FALSE)
if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_COMPATIBLE TRUE)
    set(PACKAGE_VERSION_EXACT TRUE)
endif()
")

message(STATUS "C++ desktop kit staged at ${RAC_KIT_OUT}")
