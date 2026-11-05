# =============================================================================
# LiteRT-LM engine: LLM over the LiteRT-LM C API (.litertlm bundles)
#
# Two modes, as in engines/qhexrt:
#
#   1) Library absent (default): only the shell compiles. It publishes a
#      not-routable vtable and rejects registration with
#      RAC_ERROR_BACKEND_UNAVAILABLE. No LiteRT-LM header or library is needed.
#
#   2) Library present under LITERTLM_ROOT (default engines/litertlm/prebuilt/current):
#        $LITERTLM_ROOT/include/c/{api_export,conversation,engine,error_reporter}.h
#        $LITERTLM_ROOT/lib/<platform>/<library>
#      <platform>/<library> is arm64-v8a/liblitert-lm.so on Android and
#      macos/libCLiteRTLM_mac.dylib on macOS.
#      scripts/build/build-litertlm-android.sh produces the Android tree.
# =============================================================================

option(RAC_BACKEND_LITERTLM "Build the LiteRT-LM engine plugin" OFF)
if(NOT RAC_BACKEND_LITERTLM)
    return()
endif()

message(STATUS "Configuring LiteRT-LM backend...")

include(${RAC_ROOT_DIR}/cmake/plugins.cmake)

set(LITERTLM_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/current" CACHE PATH
    "LiteRT-LM C API tree: include/c/*.h and lib/<platform>/")

set(_litertlm_library "")
if(RAC_PLATFORM_ANDROID)
    set(_litertlm_library "${LITERTLM_ROOT}/lib/${ANDROID_ABI}/liblitert-lm.so")
elseif(APPLE AND NOT IOS)
    set(_litertlm_library "${LITERTLM_ROOT}/lib/macos/libCLiteRTLM_mac.dylib")
endif()

set(RAC_LITERTLM_ENGINE_AVAILABLE 0)
if(_litertlm_library AND EXISTS "${_litertlm_library}"
   AND EXISTS "${LITERTLM_ROOT}/include/c/engine.h")
    set(RAC_LITERTLM_ENGINE_AVAILABLE 1)
endif()

set(LITERTLM_SOURCES
    rac_plugin_entry_litertlm.cpp
    rac_backend_litertlm_register.cpp
)
set(LITERTLM_LINK_LIBS "")
set(LITERTLM_INCLUDE_DIRS
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)
if(RAC_LITERTLM_ENGINE_AVAILABLE)
    add_library(litertlm_capi SHARED IMPORTED GLOBAL)
    set_target_properties(litertlm_capi PROPERTIES
        IMPORTED_LOCATION "${_litertlm_library}"
        INTERFACE_INCLUDE_DIRECTORIES "${LITERTLM_ROOT}/include"
    )
    list(APPEND LITERTLM_SOURCES litertlm_llm_ops.cpp)
    list(APPEND LITERTLM_LINK_LIBS litertlm_capi nlohmann_json::nlohmann_json)
endif()

rac_add_engine_plugin(litertlm
    TARGET_NAME         rac_backend_litertlm
    CXX_STANDARD        17
    SHARED_ONLY
    SOURCES             ${LITERTLM_SOURCES}
    LINK_LIBRARIES      ${LITERTLM_LINK_LIBS}
    INCLUDE_DIRECTORIES ${LITERTLM_INCLUDE_DIRS}
    COMPILE_DEFINITIONS RAC_LITERTLM_ENGINE_AVAILABLE=${RAC_LITERTLM_ENGINE_AVAILABLE}
    AVAILABILITY        PUBLIC
    PACKAGE_OWNER       runanywhere
    PACKAGE_NAME        runanywhere_litertlm
)

if(RAC_STATIC_PLUGINS)
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_litertlm.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${RAC_COMMONS_ROOT_DIR}/include
    )
elseif(RAC_BUILD_SHARED AND NOT RAC_PLATFORM_ANDROID)
    # rac_registry_load_plugin() derives the entry symbol from the file name. Android
    # loads the target by name through the JNI bridge, so only other hosts rename it.
    set_target_properties(rac_backend_litertlm PROPERTIES OUTPUT_NAME runanywhere_litertlm)
endif()

rac_apply_android_page_alignment(rac_backend_litertlm)
if(RAC_PLATFORM_ANDROID)
    target_link_libraries(rac_backend_litertlm PRIVATE log)
endif()

# JNI bridge (Android): librac_backend_litertlm_jni.so, loaded by the Kotlin
# runanywhere-core-litertlm module. Builds in both modes.
if(RAC_PLATFORM_ANDROID AND RAC_BUILD_SHARED AND RAC_BUILD_JNI)
    add_library(rac_backend_litertlm_jni SHARED jni/rac_backend_litertlm_jni.cpp)
    target_include_directories(rac_backend_litertlm_jni PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include)
    target_compile_definitions(rac_backend_litertlm_jni PRIVATE
        RAC_LITERTLM_VERSION="${RAC_VERSION}")
    target_compile_options(rac_backend_litertlm_jni PRIVATE -fvisibility=hidden)
    target_link_libraries(rac_backend_litertlm_jni PRIVATE rac_backend_litertlm log)
    rac_apply_android_page_alignment(rac_backend_litertlm_jni)
endif()

message(STATUS "LiteRT-LM Backend Configuration:")
message(STATUS "  Engine available: ${RAC_LITERTLM_ENGINE_AVAILABLE}")
message(STATUS "  Library:          ${_litertlm_library}")
