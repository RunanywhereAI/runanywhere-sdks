# =============================================================================
# cmake/plugins.cmake — engine plugin authoring helpers
#
# GAP 07 Phase 4 — see v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md.
#
# Hides the static-vs-shared decision and the per-platform
# linker-keep-alive incantations (-Wl,-force_load on Apple, --whole-archive on
# GNU, /INCLUDE: on MSVC) behind two functions. Engine authors call ONE
# function from their CMakeLists.txt — no copy-pasted CMake per backend.
#
# This is the helper that
# `sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry.h` already
# documents as "introduced in GAP 07" (~line 126).
#
# Usage in engines/<name>/CMakeLists.txt:
#
#   rac_add_engine_plugin(llamacpp
#       SOURCES
#           llamacpp_backend.cpp
#           rac_llm_llamacpp.cpp
#           rac_plugin_entry_llamacpp.cpp
#           rac_static_register_llamacpp.cpp
#       LINK_LIBRARIES llama common
#       RUNTIMES CPU METAL CUDA
#       FORMATS GGUF GGML BIN
#   )
#
# Then in the consuming app's CMakeLists.txt:
#   rac_force_load(my_app PLUGINS llamacpp onnx whispercpp)
# =============================================================================

include_guard(GLOBAL)

# -----------------------------------------------------------------------------
# rac_add_engine_plugin(name
#                       SOURCES <s1> <s2> ...
#                       [LINK_LIBRARIES <lib1> <lib2> ...]
#                       [INCLUDE_DIRECTORIES <dir1> ...]
#                       [COMPILE_DEFINITIONS <def1> ...]
#                       [RUNTIMES <CPU|METAL|...>]
#                       [FORMATS <GGUF|ONNX|...>])
#
# Branches on RAC_STATIC_PLUGINS:
#   - ON  → SOURCES become rac_commons private sources; the plugin auto-
#           registers via the RAC_STATIC_PLUGIN_REGISTER macro that the
#           plugin's own TU calls (gated on RAC_PLUGIN_MODE_STATIC).
#   - OFF → SOURCES build into a SHARED library named runanywhere_<name>
#           (so the loader's `entry_symbol_from_path()` heuristic resolves
#           `rac_plugin_entry_<name>`). PUBLIC-links rac_commons so the
#           registry symbols resolve via the dlopen RTLD_LOCAL semantics.
#           Default-hidden visibility everywhere except the entry symbol.
#
# RUNTIMES + FORMATS are recorded as compile definitions for the plugin TU
# only — they don't affect the build itself, but allow tooling to grep for
# "which engines declare CUDA?" by looking at the cmake-recorded definitions.
# Authoritative list lives in the plugin's `rac_plugin_entry_*.cpp` runtimes[]
# array; this is documentation-by-cmake.
# -----------------------------------------------------------------------------
function(rac_add_engine_plugin name)
    set(_options "")
    set(_oneval  "")
    set(_multival SOURCES LINK_LIBRARIES INCLUDE_DIRECTORIES COMPILE_DEFINITIONS RUNTIMES FORMATS)
    cmake_parse_arguments(P "${_options}" "${_oneval}" "${_multival}" ${ARGN})

    if(NOT P_SOURCES)
        message(FATAL_ERROR "rac_add_engine_plugin(${name}): SOURCES is required")
    endif()

    if(RAC_STATIC_PLUGINS)
        # ── STATIC PATH ─────────────────────────────────────────────────────
        # Append to rac_commons; rac_commons must already exist (commons
        # subdirectory is added before engines/ in the root CMakeLists).
        if(NOT TARGET rac_commons)
            message(FATAL_ERROR "rac_add_engine_plugin(${name}): rac_commons target not found. "
                                "Did you call this before add_subdirectory(sdk/runanywhere-commons)?")
        endif()
        target_sources(rac_commons PRIVATE ${P_SOURCES})
        if(P_INCLUDE_DIRECTORIES)
            target_include_directories(rac_commons PRIVATE ${P_INCLUDE_DIRECTORIES})
        endif()
        if(P_COMPILE_DEFINITIONS)
            target_compile_definitions(rac_commons PRIVATE ${P_COMPILE_DEFINITIONS})
        endif()
        if(P_LINK_LIBRARIES)
            target_link_libraries(rac_commons PUBLIC ${P_LINK_LIBRARIES})
        endif()
        message(STATUS "  Engine plugin '${name}': STATIC (linked into rac_commons)")
    else()
        # ── SHARED PATH ─────────────────────────────────────────────────────
        set(_libname "runanywhere_${name}")
        add_library(${_libname} SHARED ${P_SOURCES})
        set_target_properties(${_libname} PROPERTIES
            OUTPUT_NAME            "runanywhere_${name}"
            C_VISIBILITY_PRESET    hidden
            CXX_VISIBILITY_PRESET  hidden
            VISIBILITY_INLINES_HIDDEN ON
        )
        if(P_INCLUDE_DIRECTORIES)
            target_include_directories(${_libname} PRIVATE ${P_INCLUDE_DIRECTORIES})
        endif()
        if(P_COMPILE_DEFINITIONS)
            target_compile_definitions(${_libname} PRIVATE ${P_COMPILE_DEFINITIONS})
        endif()
        target_link_libraries(${_libname} PUBLIC rac_commons)
        if(P_LINK_LIBRARIES)
            target_link_libraries(${_libname} PUBLIC ${P_LINK_LIBRARIES})
        endif()
        install(TARGETS ${_libname} LIBRARY DESTINATION lib)
        message(STATUS "  Engine plugin '${name}': SHARED (libruntime_${name})")
    endif()

    # Tooling-only metadata — never read by code, only by cmake -t graphviz/json.
    if(P_RUNTIMES)
        set_property(GLOBAL APPEND PROPERTY RAC_ENGINE_${name}_RUNTIMES ${P_RUNTIMES})
    endif()
    if(P_FORMATS)
        set_property(GLOBAL APPEND PROPERTY RAC_ENGINE_${name}_FORMATS ${P_FORMATS})
    endif()
    set_property(GLOBAL APPEND PROPERTY RAC_REGISTERED_ENGINES ${name})
endfunction()

# -----------------------------------------------------------------------------
# rac_force_load(target PLUGINS <name1> <name2> ...)
#
# Tells the linker not to drop the static-archive object file even when no
# call site references its symbols (the static-init Registrar is the only
# referrer). Call from the host binary's CMakeLists.
#
# Per-platform incantation:
#   - macOS / iOS:   -Wl,-force_load,<full-path-to-libruntime_name.a>
#   - GNU / Android: -Wl,--whole-archive <path> -Wl,--no-whole-archive
#   - MSVC:          /INCLUDE:_g_rac_plugin_autoreg_<name>
#
# No-op when RAC_STATIC_PLUGINS is OFF (shared plugins resolve dynamically).
# -----------------------------------------------------------------------------
function(rac_force_load target)
    cmake_parse_arguments(F "" "" "PLUGINS" ${ARGN})
    if(NOT F_PLUGINS OR NOT RAC_STATIC_PLUGINS)
        return()
    endif()

    foreach(plugin ${F_PLUGINS})
        set(_lib "runanywhere_${plugin}")
        if(NOT TARGET ${_lib})
            message(WARNING "rac_force_load(${target}): plugin '${plugin}' (target ${_lib}) not registered; skipping")
            continue()
        endif()

        if(APPLE)
            target_link_options(${target} PRIVATE
                "LINKER:-force_load,$<TARGET_FILE:${_lib}>")
        elseif(MSVC)
            # The marker symbol emitted by RAC_STATIC_PLUGIN_REGISTER is
            # `rac_plugin_static_marker_<name>`.
            target_link_options(${target} PRIVATE
                "/INCLUDE:rac_plugin_static_marker_${plugin}")
            target_link_libraries(${target} PRIVATE ${_lib})
        else()
            # GCC/Clang on Linux/Android — --whole-archive needs the path
            # between the two flags.
            target_link_options(${target} PRIVATE
                "LINKER:--whole-archive"
                "LINKER:$<TARGET_FILE:${_lib}>"
                "LINKER:--no-whole-archive")
        endif()
    endforeach()
endfunction()
