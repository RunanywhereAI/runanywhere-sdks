# Helpers for building L2 engine plugins and L5 solutions.
#
# The SAME plugin source compiles to:
#   - a shared library (.so/.dylib) with a dlopen entry point on Android/macOS/Linux
#   - a static archive (.a) with a register_static<E>() entry on iOS/WASM
#
# Usage from engines/<name>/CMakeLists.txt:
#   ra_add_engine_plugin(llamacpp_engine
#       SOURCES
#           llamacpp_engine.cpp
#           llamacpp_plugin.cpp
#       DEPS
#           llama
#       ABI_VERSION 1
#   )

function(ra_add_engine_plugin TARGET_NAME)
    set(options)
    set(one_value_args ABI_VERSION OUTPUT_NAME)
    set(multi_value_args SOURCES DEPS INCLUDES)
    cmake_parse_arguments(ARG "${options}" "${one_value_args}"
        "${multi_value_args}" ${ARGN})

    if(NOT ARG_SOURCES)
        message(FATAL_ERROR "ra_add_engine_plugin(${TARGET_NAME}): SOURCES is required")
    endif()
    if(NOT ARG_ABI_VERSION)
        set(ARG_ABI_VERSION 1)
    endif()
    if(NOT ARG_OUTPUT_NAME)
        set(ARG_OUTPUT_NAME "${TARGET_NAME}")
    endif()

    # Library type — SHARED on dlopen platforms, STATIC everywhere else.
    if(RA_STATIC_PLUGINS)
        set(_lib_type STATIC)
    else()
        set(_lib_type SHARED)
    endif()

    add_library(${TARGET_NAME} ${_lib_type} ${ARG_SOURCES})

    set_target_properties(${TARGET_NAME} PROPERTIES
        OUTPUT_NAME "${ARG_OUTPUT_NAME}"
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
    )

    target_include_directories(${TARGET_NAME}
        PUBLIC
            $<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/core/abi>
        PRIVATE
            $<BUILD_INTERFACE:${CMAKE_SOURCE_DIR}/core>
            ${ARG_INCLUDES}
    )

    target_compile_definitions(${TARGET_NAME} PRIVATE
        RA_PLUGIN_ABI_VERSION=${ARG_ABI_VERSION}
        RA_PLUGIN_NAME=\"${TARGET_NAME}\"
    )

    target_link_libraries(${TARGET_NAME}
        PRIVATE
            RunAnywhere::platform_flags
            RunAnywhere::sanitizers
            ra_core_abi
            ${ARG_DEPS}
    )

    # On dlopen platforms, keep the plugin's symbol set tight. macOS's `ld`
    # doesn't support `--exclude-libs`; GNU ld and LLVM lld do.
    if(NOT RA_STATIC_PLUGINS AND NOT MSVC AND NOT APPLE)
        target_link_options(${TARGET_NAME} PRIVATE
            "LINKER:--exclude-libs,ALL"
        )
    endif()

    # Install — shared libs go under lib/plugins/; static archives are
    # absorbed by the frontend linkers directly.
    if(NOT RA_STATIC_PLUGINS)
        install(TARGETS ${TARGET_NAME}
            LIBRARY DESTINATION lib/plugins
            RUNTIME DESTINATION bin/plugins
        )
    endif()
endfunction()

# Solution plugins follow the same packaging rules as engine plugins but link
# against the L4 graph runtime instead of any engine vtable.
function(ra_add_solution_plugin TARGET_NAME)
    set(options)
    set(one_value_args ABI_VERSION OUTPUT_NAME)
    set(multi_value_args SOURCES DEPS INCLUDES)
    cmake_parse_arguments(ARG "${options}" "${one_value_args}"
        "${multi_value_args}" ${ARGN})

    ra_add_engine_plugin(${TARGET_NAME}
        SOURCES      ${ARG_SOURCES}
        DEPS         ${ARG_DEPS} ra_core_graph
        INCLUDES     ${ARG_INCLUDES}
        ABI_VERSION  ${ARG_ABI_VERSION}
        OUTPUT_NAME  ${ARG_OUTPUT_NAME}
    )
endfunction()
