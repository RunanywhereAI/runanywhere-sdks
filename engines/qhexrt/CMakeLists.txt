# =============================================================================
# QHexRT Backend — RunAnywhere's PRIVATE Qualcomm Hexagon NPU runtime
#
# QHexRT runs prebuilt QNN context binaries on Snapdragon Hexagon NPUs (HTP).
# It is a closed-source, RunAnywhere-owned dependency consumed as a PREBUILT
# static archive — its source never enters this repo.
#
# Two modes:
#
#   1) Engine NOT available (default in the public repo):
#      - The prebuilt archive / header under QHEXRT_ROOT is absent, so
#        RAC_QHEXRT_ENGINE_AVAILABLE stays 0.
#      - Only the shell (rac_plugin_entry_qhexrt.cpp) compiles; it publishes a
#        not-routable, all-NULL vtable and rejects registration with
#        RAC_ERROR_BACKEND_UNAVAILABLE. No QHexRT header/lib needed. The public
#        repo links cleanly.
#
#   2) Engine IS available (internal / authorized Android builds):
#      - QHEXRT_ROOT points at the prebuilt tree:
#            $QHEXRT_ROOT/include/qhexrt/qhexrt_c.h
#            $QHEXRT_ROOT/lib/<abi>/libqhexrt_core.a
#            $QHEXRT_ROOT/lib/<abi>/libqhexrt_host.a
#        (defaults to the atomically selected engines/qhexrt/prebuilt/current,
#        whose immutable versions are gitignored).
#      - RAC_QHEXRT_ENGINE_AVAILABLE=1; qhexrt_llm_ops.cpp compiles against the
#        private header and the archive links INTO the plugin .so (no separately
#        shippable QHexRT binary; runtime symbols stay internal to the carrier).
#      - Publishes a routable vtable exposing RAC_PRIMITIVE_GENERATE_TEXT.
#
# OFF by default: the QNN runtime + NPU firmware are Android/Snapdragon-only and
# absent on CI hosts. Downstream Android builds set -DRAC_BACKEND_QHEXRT=ON
# (+ optionally -DQHEXRT_ROOT=<path>).
# =============================================================================

option(RAC_BACKEND_QHEXRT "Build QHexRT (Qualcomm Hexagon NPU) engine plugin" OFF)
if(NOT RAC_BACKEND_QHEXRT)
    return()
endif()

message(STATUS "Configuring QHexRT (Qualcomm Hexagon NPU) backend...")

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

function(_qhexrt_require_json_keys json_variable label expected_csv)
    set(_json "${${json_variable}}")
    string(JSON _count ERROR_VARIABLE _error LENGTH "${_json}" ${ARGN})
    if(NOT _error STREQUAL "NOTFOUND")
        message(FATAL_ERROR "Invalid QHexRT JSON object ${label}: ${_error}")
    endif()
    set(_actual "")
    if(_count GREATER 0)
        math(EXPR _last "${_count} - 1")
        foreach(_index RANGE 0 ${_last})
            string(JSON _key MEMBER "${_json}" ${ARGN} ${_index})
            list(APPEND _actual "${_key}")
        endforeach()
    endif()
    string(REPLACE "," ";" _expected "${expected_csv}")
    list(SORT _actual)
    list(SORT _expected)
    if(NOT "${_actual}" STREQUAL "${_expected}")
        message(FATAL_ERROR
            "QHexRT JSON object ${label} has wrong keys: actual=${_actual} expected=${_expected}")
    endif()
endfunction()

get_filename_component(RAC_COMMONS_ROOT_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

# Prebuilt QHexRT tree. Default to the gitignored in-tree staging dir so an
# authorized checkout that ran QHexRT's verified staging script "just works".
# The script publishes immutable versions and atomically switches `current`;
# resolving it here prevents a later switch from mixing inputs in one build.
set(_qhexrt_root_explicit FALSE)
if(NOT DEFINED QHEXRT_ROOT)
    set(QHEXRT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/current")
else()
    set(_qhexrt_root_explicit TRUE)
endif()
set(_qhexrt_root_selected FALSE)
if(_qhexrt_root_explicit OR EXISTS "${QHEXRT_ROOT}" OR IS_SYMLINK "${QHEXRT_ROOT}")
    set(_qhexrt_root_selected TRUE)
endif()
if(NOT _qhexrt_root_explicit AND EXISTS "${QHEXRT_ROOT}" AND NOT IS_SYMLINK "${QHEXRT_ROOT}")
    message(FATAL_ERROR "Default QHexRT prebuilt/current must be an atomic symlink")
endif()
if(NOT _qhexrt_root_explicit AND IS_SYMLINK "${QHEXRT_ROOT}")
    file(READ_SYMLINK "${QHEXRT_ROOT}" _qhexrt_current_target)
    get_filename_component(_qhexrt_current_name "${_qhexrt_current_target}" NAME)
    string(LENGTH "${_qhexrt_current_name}" _qhexrt_current_name_length)
    if(NOT _qhexrt_current_target MATCHES "^versions/[0-9a-f]+$" OR
       NOT _qhexrt_current_name_length EQUAL 64)
        message(FATAL_ERROR "QHexRT current must directly name versions/<64-hex-receipt>")
    endif()
    get_filename_component(_qhexrt_current_parent "${QHEXRT_ROOT}" DIRECTORY)
    set(_qhexrt_selected_entry "${_qhexrt_current_parent}/${_qhexrt_current_target}")
    if(IS_SYMLINK "${_qhexrt_selected_entry}" OR NOT IS_DIRECTORY "${_qhexrt_selected_entry}")
        message(FATAL_ERROR "QHexRT current target must be a real immutable version directory")
    endif()
endif()
if(IS_SYMLINK "${QHEXRT_ROOT}" AND NOT EXISTS "${QHEXRT_ROOT}")
    message(FATAL_ERROR "QHexRT current prebuilt symlink is broken: ${QHEXRT_ROOT}")
endif()
if(_qhexrt_root_explicit AND NOT EXISTS "${QHEXRT_ROOT}")
    message(FATAL_ERROR "Explicit QHEXRT_ROOT does not exist: ${QHEXRT_ROOT}")
endif()
if(NOT _qhexrt_root_explicit AND NOT _qhexrt_root_selected)
    get_filename_component(_qhexrt_prebuilt_parent "${QHEXRT_ROOT}" DIRECTORY)
    if(EXISTS "${_qhexrt_prebuilt_parent}/include" OR IS_SYMLINK "${_qhexrt_prebuilt_parent}/include" OR
       EXISTS "${_qhexrt_prebuilt_parent}/lib" OR IS_SYMLINK "${_qhexrt_prebuilt_parent}/lib" OR
       EXISTS "${_qhexrt_prebuilt_parent}/qhexrt-prebuilt.json" OR
       IS_SYMLINK "${_qhexrt_prebuilt_parent}/qhexrt-prebuilt.json")
        message(FATAL_ERROR
            "Legacy QHexRT prebuilt payload exists without current; rerun stage_prebuilt_for_sdk.sh")
    endif()
endif()
if(EXISTS "${QHEXRT_ROOT}")
    file(REAL_PATH "${QHEXRT_ROOT}" QHEXRT_ROOT)
endif()
if(NOT _qhexrt_root_explicit AND _qhexrt_root_selected)
    set(_qhexrt_versions "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/versions")
    if(IS_SYMLINK "${_qhexrt_versions}" OR NOT IS_DIRECTORY "${_qhexrt_versions}")
        message(FATAL_ERROR "QHexRT prebuilt/versions must be a real directory")
    endif()
    file(REAL_PATH "${_qhexrt_versions}" _qhexrt_versions_real)
    get_filename_component(_qhexrt_selected_parent "${QHEXRT_ROOT}" DIRECTORY)
    if(NOT _qhexrt_selected_parent STREQUAL _qhexrt_versions_real)
        message(FATAL_ERROR "QHexRT current must select a direct child of prebuilt/versions")
    endif()
endif()

# ABI subdir under QHEXRT_ROOT/lib (arm64-v8a is the shipped Snapdragon target).
set(_qhexrt_abi "${ANDROID_ABI}")
if(NOT _qhexrt_abi)
    set(_qhexrt_abi "arm64-v8a")
endif()

set(QHEXRT_SOURCES
    rac_plugin_entry_qhexrt.cpp
    rac_backend_qhexrt_register.cpp
    qhexrt_device_capability.cpp
    qhexrt_model_catalog.cpp)
set(QHEXRT_LINK_LIBS "")
set(QHEXRT_COMPILE_DEFS RAC_QHEXRT_BUILDING)
set(QHEXRT_INCLUDE_DIRS
    ${RAC_COMMONS_ROOT_DIR}/include
    ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/..)  # engines/ — for engines/common/rac_engine_unavailable.h

# QHexRT exposes existing generated messages only as serialized byte buffers.
# The C++ generated/runtime dependencies stay private to the engine build.
if(RAC_PROTOBUF_RUNTIME_ENABLED)
    list(APPEND QHEXRT_INCLUDE_DIRS
        ${RAC_COMMONS_ROOT_DIR}/src/generated/proto)
    list(APPEND QHEXRT_COMPILE_DEFS RAC_QHEXRT_HAVE_PROTOBUF=1)
    if(TARGET protobuf::libprotobuf)
        list(APPEND QHEXRT_LINK_LIBS protobuf::libprotobuf)
    elseif(Protobuf_LIBRARIES)
        list(APPEND QHEXRT_LINK_LIBS ${Protobuf_LIBRARIES})
        list(APPEND QHEXRT_INCLUDE_DIRS ${Protobuf_INCLUDE_DIRS})
    endif()
endif()

# Discover the prebuilt archive + private header. Once a current/explicit root
# is selected, all payloads must be present and valid; only a wholly absent
# default current selection builds the public stub. Explicit
# paths (not find_library): the Android NDK toolchain re-roots find_library
# PATHS under the sysroot (CMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY), which would
# never see this out-of-sysroot prebuilt tree.
set(QHEXRT_CORE_LIB "${QHEXRT_ROOT}/lib/${_qhexrt_abi}/libqhexrt_core.a")
set(QHEXRT_HOST_LIB "${QHEXRT_ROOT}/lib/${_qhexrt_abi}/libqhexrt_host.a")
set(QHEXRT_HEADER "${QHEXRT_ROOT}/include/qhexrt/qhexrt_c.h")
set(QHEXRT_IDENTITY_MANIFEST "${QHEXRT_ROOT}/qhexrt-prebuilt.json")
set(QHEXRT_BUILD_RECEIPT "${QHEXRT_ROOT}/qhexrt-build-receipt.json")
set(_qhexrt_prebuilt_valid FALSE)

if(RAC_PLATFORM_ANDROID AND _qhexrt_root_selected)
    if(NOT EXISTS "${QHEXRT_CORE_LIB}" OR NOT EXISTS "${QHEXRT_HOST_LIB}" OR
       NOT EXISTS "${QHEXRT_HEADER}" OR NOT EXISTS "${QHEXRT_IDENTITY_MANIFEST}" OR
       NOT EXISTS "${QHEXRT_BUILD_RECEIPT}")
        message(FATAL_ERROR "Partial QHexRT prebuilt under ${QHEXRT_ROOT}; refusing a mixed/unfinished payload")
    endif()
    foreach(_qhexrt_no_symlink IN ITEMS
        "${QHEXRT_ROOT}/include"
        "${QHEXRT_ROOT}/include/qhexrt"
        "${QHEXRT_HEADER}"
        "${QHEXRT_ROOT}/lib"
        "${QHEXRT_ROOT}/lib/${_qhexrt_abi}"
        "${QHEXRT_CORE_LIB}"
        "${QHEXRT_HOST_LIB}"
        "${QHEXRT_IDENTITY_MANIFEST}"
        "${QHEXRT_BUILD_RECEIPT}")
        if(IS_SYMLINK "${_qhexrt_no_symlink}")
            message(FATAL_ERROR "QHexRT selected prebuilt contains a symlink: ${_qhexrt_no_symlink}")
        endif()
    endforeach()
    file(READ "${QHEXRT_IDENTITY_MANIFEST}" _qhexrt_identity_json)
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest"
        "android_abi,build,build_receipt_sha256,c_abi,files,qhexrt_version,schema,source")
    string(JSON _qhexrt_identity_schema ERROR_VARIABLE _qhexrt_json_error
        GET "${_qhexrt_identity_json}" schema)
    if(NOT _qhexrt_json_error STREQUAL "NOTFOUND" OR
       NOT _qhexrt_identity_schema STREQUAL "qhexrt-prebuilt/v2")
        message(FATAL_ERROR "Invalid QHexRT identity manifest schema: ${_qhexrt_json_error}")
    endif()
    string(JSON _qhexrt_manifest_abi GET "${_qhexrt_identity_json}" android_abi)
    if(NOT _qhexrt_manifest_abi STREQUAL _qhexrt_abi)
        message(FATAL_ERROR
            "QHexRT prebuilt ABI mismatch: manifest=${_qhexrt_manifest_abi} build=${_qhexrt_abi}")
    endif()
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.c_abi" "major,minor" c_abi)
    string(JSON _qhexrt_abi_major_type TYPE "${_qhexrt_identity_json}" c_abi major)
    string(JSON _qhexrt_abi_minor_type TYPE "${_qhexrt_identity_json}" c_abi minor)
    string(JSON _qhexrt_abi_major GET "${_qhexrt_identity_json}" c_abi major)
    string(JSON _qhexrt_abi_minor GET "${_qhexrt_identity_json}" c_abi minor)
    if(NOT _qhexrt_abi_major_type STREQUAL "NUMBER" OR
       NOT _qhexrt_abi_minor_type STREQUAL "NUMBER" OR
       NOT _qhexrt_abi_major STREQUAL "1" OR
       NOT _qhexrt_abi_minor MATCHES "^[0-9]+$")
        message(FATAL_ERROR "QHexRT prebuilt has an incompatible C ABI object")
    endif()
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.source"
        "git_dirty,git_sha,state_sha256" source)
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.build"
        "android_abi,archive_evidence,build_type,cmake_cache_sha256,cmake_system,compiler,ndk,qnn_sdk" build)
    string(JSON _qhexrt_build_abi GET "${_qhexrt_identity_json}" build android_abi)
    if(NOT _qhexrt_build_abi STREQUAL _qhexrt_abi)
        message(FATAL_ERROR "QHexRT receipt build ABI does not match selected Android ABI")
    endif()
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.build.cmake_system"
        "crosscompiling,name,processor,state_file_sha256" build cmake_system)
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.build.compiler"
        "id,sha256,state_file_sha256,version,version_output_sha256" build compiler)
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.build.ndk"
        "metadata_file,metadata_sha256" build ndk)
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.build.qnn_sdk"
        "metadata_file,metadata_sha256" build qnn_sdk)
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.build.archive_evidence"
        "core,host,llvm_ar_sha256,llvm_readelf_sha256" build archive_evidence)
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.build.archive_evidence.core"
        "member_count" build archive_evidence core)
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.build.archive_evidence.host"
        "member_count" build archive_evidence host)
    _qhexrt_require_json_keys(_qhexrt_identity_json "manifest.files"
        "include/qhexrt/qhexrt_c.h,lib/${_qhexrt_abi}/libqhexrt_core.a,lib/${_qhexrt_abi}/libqhexrt_host.a" files)
    string(JSON _qhexrt_receipt_sha ERROR_VARIABLE _qhexrt_receipt_error
        GET "${_qhexrt_identity_json}" build_receipt_sha256)
    string(LENGTH "${_qhexrt_receipt_sha}" _qhexrt_receipt_sha_length)
    get_filename_component(_qhexrt_version_name "${QHEXRT_ROOT}" NAME)
    if(NOT _qhexrt_receipt_error STREQUAL "NOTFOUND" OR
       NOT _qhexrt_receipt_sha MATCHES "^[0-9a-f]+$" OR
       NOT _qhexrt_receipt_sha_length EQUAL 64 OR
       NOT _qhexrt_version_name STREQUAL _qhexrt_receipt_sha)
        message(FATAL_ERROR "QHexRT prebuilt version directory does not match its build receipt identity")
    endif()
    file(SHA256 "${QHEXRT_BUILD_RECEIPT}" _qhexrt_actual_receipt_sha)
    if(NOT _qhexrt_actual_receipt_sha STREQUAL _qhexrt_receipt_sha)
        message(FATAL_ERROR "QHexRT sanitized build receipt hash does not match the selected version")
    endif()
    file(READ "${QHEXRT_BUILD_RECEIPT}" _qhexrt_receipt_json)
    _qhexrt_require_json_keys(_qhexrt_receipt_json "sanitized receipt"
        "artifacts,build,c_abi,qhexrt_version,schema,source")
    string(JSON _qhexrt_receipt_schema ERROR_VARIABLE _qhexrt_receipt_schema_error
        GET "${_qhexrt_receipt_json}" schema)
    if(NOT _qhexrt_receipt_schema_error STREQUAL "NOTFOUND" OR
       NOT _qhexrt_receipt_schema STREQUAL "qhexrt-build-receipt/v1")
        message(FATAL_ERROR "Invalid QHexRT sanitized build receipt schema")
    endif()
    foreach(_qhexrt_receipt_field IN ITEMS qhexrt_version c_abi source build)
        string(JSON _qhexrt_from_receipt GET "${_qhexrt_receipt_json}" "${_qhexrt_receipt_field}")
        string(JSON _qhexrt_from_manifest GET "${_qhexrt_identity_json}" "${_qhexrt_receipt_field}")
        if(NOT _qhexrt_from_receipt STREQUAL _qhexrt_from_manifest)
            message(FATAL_ERROR
                "QHexRT manifest field ${_qhexrt_receipt_field} does not derive from sanitized receipt")
        endif()
    endforeach()
    string(JSON _qhexrt_from_receipt GET "${_qhexrt_receipt_json}" artifacts)
    string(JSON _qhexrt_from_manifest GET "${_qhexrt_identity_json}" files)
    if(NOT _qhexrt_from_receipt STREQUAL _qhexrt_from_manifest)
        message(FATAL_ERROR "QHexRT manifest file inventory does not derive from sanitized receipt")
    endif()
    foreach(_qhexrt_relative IN ITEMS
        "include/qhexrt/qhexrt_c.h"
        "lib/${_qhexrt_abi}/libqhexrt_core.a"
        "lib/${_qhexrt_abi}/libqhexrt_host.a")
        set(_qhexrt_path "${QHEXRT_ROOT}/${_qhexrt_relative}")
        _qhexrt_require_json_keys(_qhexrt_identity_json
            "manifest.files.${_qhexrt_relative}" "sha256,size_bytes" files "${_qhexrt_relative}")
        string(JSON _qhexrt_expected_sha ERROR_VARIABLE _qhexrt_sha_error
            GET "${_qhexrt_identity_json}" files "${_qhexrt_relative}" sha256)
        string(JSON _qhexrt_expected_size ERROR_VARIABLE _qhexrt_size_error
            GET "${_qhexrt_identity_json}" files "${_qhexrt_relative}" size_bytes)
        if(NOT _qhexrt_sha_error STREQUAL "NOTFOUND" OR
           NOT _qhexrt_size_error STREQUAL "NOTFOUND")
            message(FATAL_ERROR "QHexRT manifest omits identity for ${_qhexrt_relative}")
        endif()
        string(JSON _qhexrt_sha_type TYPE "${_qhexrt_identity_json}" files "${_qhexrt_relative}" sha256)
        string(JSON _qhexrt_size_type TYPE "${_qhexrt_identity_json}" files "${_qhexrt_relative}" size_bytes)
        string(LENGTH "${_qhexrt_expected_sha}" _qhexrt_expected_sha_length)
        if(NOT _qhexrt_sha_type STREQUAL "STRING" OR
           NOT _qhexrt_size_type STREQUAL "NUMBER" OR
           NOT _qhexrt_expected_sha MATCHES "^[0-9a-f]+$" OR
           NOT _qhexrt_expected_sha_length EQUAL 64 OR
           NOT _qhexrt_expected_size MATCHES "^[0-9]+$" OR
           _qhexrt_expected_size LESS_EQUAL 0)
            message(FATAL_ERROR "QHexRT manifest has invalid file identity for ${_qhexrt_relative}")
        endif()
        file(SHA256 "${_qhexrt_path}" _qhexrt_actual_sha)
        file(SIZE "${_qhexrt_path}" _qhexrt_actual_size)
        if(NOT _qhexrt_actual_sha STREQUAL _qhexrt_expected_sha OR
           NOT _qhexrt_actual_size EQUAL _qhexrt_expected_size)
            message(FATAL_ERROR "QHexRT prebuilt identity mismatch for ${_qhexrt_relative}")
        endif()
    endforeach()
    set(_qhexrt_prebuilt_valid TRUE)
endif()

if(RAC_PLATFORM_ANDROID AND _qhexrt_prebuilt_valid)
    set(RAC_QHEXRT_ENGINE_AVAILABLE 1)
    message(STATUS "  QHexRT engine discovered:")
    message(STATUS "    header: ${QHEXRT_HEADER}")
    message(STATUS "    core:   ${QHEXRT_CORE_LIB}")
    message(STATUS "    host:   ${QHEXRT_HOST_LIB}")

    list(APPEND QHEXRT_SOURCES
        qhexrt_session.cpp
        qhexrt_llm_ops.cpp
        qhexrt_vlm_ops.cpp
        qhexrt_stt_ops.cpp
        qhexrt_tts_ops.cpp
        qhexrt_embeddings_ops.cpp
        qhexrt_diffusion_ops.cpp)
    list(APPEND QHEXRT_INCLUDE_DIRS "${QHEXRT_ROOT}/include")
    list(APPEND QHEXRT_COMPILE_DEFS RAC_QHEXRT_ENGINE_AVAILABLE=1)

    # core references host symbols; wrap both archives in a link group so static
    # resolution is order-independent. dl + pthread are QHexRT's own deps.
    list(APPEND QHEXRT_LINK_LIBS
        -Wl,--start-group "${QHEXRT_CORE_LIB}" "${QHEXRT_HOST_LIB}" -Wl,--end-group
        ${CMAKE_DL_LIBS})
    find_package(Threads REQUIRED)
    list(APPEND QHEXRT_LINK_LIBS Threads::Threads)
else()
    set(RAC_QHEXRT_ENGINE_AVAILABLE 0)
    list(APPEND QHEXRT_COMPILE_DEFS RAC_QHEXRT_ENGINE_AVAILABLE=0)
    if(NOT RAC_PLATFORM_ANDROID)
        message(STATUS "  QHexRT engine is Android-only on Snapdragon; building shell for ${RAC_PLATFORM_NAME}")
    else()
        message(STATUS "  QHexRT engine archive absent under QHEXRT_ROOT=${QHEXRT_ROOT}")
    endif()
    message(STATUS "  -> building not-routable shell (rejects with RAC_ERROR_BACKEND_UNAVAILABLE)")
endif()

rac_add_engine_plugin(qhexrt
    TARGET_NAME         rac_backend_qhexrt
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             ${QHEXRT_SOURCES}
    LINK_LIBRARIES      ${QHEXRT_LINK_LIBS}
    INCLUDE_DIRECTORIES ${QHEXRT_INCLUDE_DIRS}
    COMPILE_DEFINITIONS ${QHEXRT_COMPILE_DEFS}
)

if(RAC_STATIC_PLUGINS)
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_qhexrt.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
    )
endif()

if(RAC_PLATFORM_ANDROID)
    target_link_libraries(rac_backend_qhexrt PRIVATE log)
    target_compile_options(rac_backend_qhexrt PRIVATE -O3 -ffunction-sections -fdata-sections)
    target_link_options(rac_backend_qhexrt PRIVATE
        -Wl,--gc-sections
        -Wl,-z,max-page-size=16384
        -Wl,-z,common-page-size=16384)
endif()

# =============================================================================
# JNI bridge (Android) — librac_backend_qhexrt_jni.so
#
# Standalone JNI carrier the Kotlin runanywhere-core-qhexrt module loads. Owns
# JNI_OnLoad; nativeRegister calls rac_backend_qhexrt_register(); nativeProbeNpu
# calls the engine-owned rac_qhexrt_probe_proto(). Builds in
# both stub and linked modes; in stub mode register reports BACKEND_UNAVAILABLE.
# =============================================================================
if(RAC_PLATFORM_ANDROID AND RAC_BUILD_SHARED AND RAC_BUILD_JNI)
    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
        set(_QHEXRT_NDK_HOST_TAG "darwin-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
        set(_QHEXRT_NDK_HOST_TAG "linux-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
        set(_QHEXRT_NDK_HOST_TAG "windows-x86_64")
    else()
        message(FATAL_ERROR "Unsupported host for QHexRT JNI bridge: ${CMAKE_HOST_SYSTEM_NAME}")
    endif()

    set(_QHEXRT_NDK_SYSROOT_INCLUDE
        "${CMAKE_ANDROID_NDK}/toolchains/llvm/prebuilt/${_QHEXRT_NDK_HOST_TAG}/sysroot/usr/include")
    if(NOT EXISTS "${_QHEXRT_NDK_SYSROOT_INCLUDE}/jni.h")
        message(FATAL_ERROR "Could not locate Android NDK JNI headers at ${_QHEXRT_NDK_SYSROOT_INCLUDE}")
    endif()

    add_library(rac_backend_qhexrt_jni SHARED jni/rac_backend_qhexrt_jni.cpp)
    target_include_directories(rac_backend_qhexrt_jni PRIVATE
        ${_QHEXRT_NDK_SYSROOT_INCLUDE}
        ${_QHEXRT_NDK_SYSROOT_INCLUDE}/android
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${RAC_COMMONS_ROOT_DIR}/include)
    target_compile_definitions(rac_backend_qhexrt_jni PRIVATE
        RAC_QHEXRT_VERSION="${RAC_VERSION}")
    target_link_libraries(rac_backend_qhexrt_jni PRIVATE rac_backend_qhexrt log)
    target_compile_options(rac_backend_qhexrt_jni PRIVATE
        -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
    target_link_options(rac_backend_qhexrt_jni PRIVATE
        -Wl,--gc-sections
        -Wl,-z,max-page-size=16384
        -Wl,-z,common-page-size=16384)
endif()

message(STATUS "QHexRT Backend Configuration:")
message(STATUS "  Engine available: ${RAC_QHEXRT_ENGINE_AVAILABLE}")
message(STATUS "  Platform:         ${RAC_PLATFORM_NAME}")
