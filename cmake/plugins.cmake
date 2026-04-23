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
#                       [TARGET_NAME <override>]      # v3.1.2: e.g. rac_backend_onnx
#                       [CXX_STANDARD <17|20>]        # v3.1.2: default 17
#                       [SHARED_ONLY]                  # v3.1.2: never link into rac_commons
#                       [LINK_LIBRARIES <lib1> <lib2> ...]
#                       [INCLUDE_DIRECTORIES <dir1> ...]
#                       [COMPILE_DEFINITIONS <def1> ...]
#                       [COMPILE_OPTIONS <opt1> ...]   # v3.1.2: e.g. -O3 -fvisibility=hidden
#                       [LINK_OPTIONS <opt1> ...]      # v3.1.2: e.g. -Wl,--gc-sections
#                       [RUNTIMES <CPU|METAL|...>]
#                       [FORMATS <GGUF|ONNX|...>])
#
# Branches:
#   - RAC_STATIC_PLUGINS=ON AND NOT SHARED_ONLY → SOURCES become rac_commons
#       private sources; the plugin auto-registers via RAC_STATIC_PLUGIN_REGISTER.
#   - Otherwise → SOURCES build into a STATIC library by default, or SHARED
#       when RAC_BUILD_SHARED=ON (or SHARED_ONLY is set). Target name is
#       TARGET_NAME if provided, else `runanywhere_<name>`. Hidden visibility
#       applies for SHARED dlopen-able plugins; SHARED_ONLY engines (which
#       expose JNI bridges or test-link surfaces) keep default visibility.
#
# v3.1.2 additions to support migrating the 4 hand-rolled engines (onnx,
# whispercpp, whisperkit_coreml, metalrt) without renaming their existing
# CMake target names — the macro now supports TARGET_NAME override + non-17
# C++ standards + SHARED_ONLY (skip the static-fold-into-rac_commons path).
#
# RUNTIMES + FORMATS are recorded as GLOBAL properties for tooling
# (cmake -t graphviz / json), independent of build mode.
# -----------------------------------------------------------------------------
function(rac_add_engine_plugin name)
    set(_options "")
    # v3.1.2: TARGET_NAME lets engines opt into the macro while preserving
    # their existing CMake target name (e.g. rac_backend_onnx). Default is
    # `runanywhere_<name>` for SHARED builds (matches the dlopen loader's
    # `entry_symbol_from_path()` heuristic).
    # CXX_STANDARD lets engines override the default 17 (e.g. ONNX needs 20).
    # SHARED_ONLY skips the static-build short-circuit when the engine MUST
    # produce a separate library (e.g. tests link directly against it).
    set(_oneval  TARGET_NAME CXX_STANDARD)
    set(_multival SOURCES LINK_LIBRARIES INCLUDE_DIRECTORIES COMPILE_DEFINITIONS
                  RUNTIMES FORMATS COMPILE_OPTIONS LINK_OPTIONS)
    cmake_parse_arguments(P "SHARED_ONLY" "${_oneval}" "${_multival}" ${ARGN})

    if(NOT P_SOURCES)
        message(FATAL_ERROR "rac_add_engine_plugin(${name}): SOURCES is required")
    endif()

    if(NOT P_TARGET_NAME)
        set(P_TARGET_NAME "runanywhere_${name}")
    endif()
    if(NOT P_CXX_STANDARD)
        set(P_CXX_STANDARD 17)
    endif()

    if(RAC_STATIC_PLUGINS AND NOT P_SHARED_ONLY)
        # ── STATIC PATH ─────────────────────────────────────────────────────
        # Append to rac_commons; rac_commons must already exist.
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
        # ── SHARED / STANDALONE PATH ────────────────────────────────────────
        # When SHARED_ONLY is set, we always produce a standalone library
        # regardless of RAC_STATIC_PLUGINS (e.g. tests link to it directly).
        if(RAC_BUILD_SHARED OR P_SHARED_ONLY)
            add_library(${P_TARGET_NAME} SHARED ${P_SOURCES})
        else()
            add_library(${P_TARGET_NAME} STATIC ${P_SOURCES})
        endif()
        set_target_properties(${P_TARGET_NAME} PROPERTIES
            OUTPUT_NAME            "${P_TARGET_NAME}"
            CXX_STANDARD           ${P_CXX_STANDARD}
            CXX_STANDARD_REQUIRED  ON
            CXX_EXTENSIONS         OFF
        )
        # Hidden visibility ONLY for the SHARED-via-dlopen layout
        # (preserves the existing rac_force_load contract — the entry
        # symbol must be the only default-visibility export). For STATIC
        # targets, leave default visibility so cross-TU symbol resolution
        # at the final link site (test exe / xcframework / Android JNI .so)
        # can find the engine's vtable + register functions. Same applies
        # to SHARED_ONLY engines (which expose JNI bridges or test-link
        # surfaces).
        get_target_property(_kind ${P_TARGET_NAME} TYPE)
        if(_kind STREQUAL "SHARED_LIBRARY" AND NOT P_SHARED_ONLY)
            set_target_properties(${P_TARGET_NAME} PROPERTIES
                C_VISIBILITY_PRESET    hidden
                CXX_VISIBILITY_PRESET  hidden
                VISIBILITY_INLINES_HIDDEN ON
            )
        endif()
        target_include_directories(${P_TARGET_NAME} PUBLIC
            ${CMAKE_CURRENT_SOURCE_DIR}
        )
        if(P_INCLUDE_DIRECTORIES)
            target_include_directories(${P_TARGET_NAME} PUBLIC ${P_INCLUDE_DIRECTORIES})
        endif()
        if(P_COMPILE_DEFINITIONS)
            target_compile_definitions(${P_TARGET_NAME} PRIVATE ${P_COMPILE_DEFINITIONS})
        endif()
        if(P_COMPILE_OPTIONS)
            target_compile_options(${P_TARGET_NAME} PRIVATE ${P_COMPILE_OPTIONS})
        endif()
        if(P_LINK_OPTIONS)
            target_link_options(${P_TARGET_NAME} PRIVATE ${P_LINK_OPTIONS})
        endif()
        target_link_libraries(${P_TARGET_NAME} PUBLIC rac_commons)
        if(P_LINK_LIBRARIES)
            target_link_libraries(${P_TARGET_NAME} PUBLIC ${P_LINK_LIBRARIES})
        endif()
        install(TARGETS ${P_TARGET_NAME} LIBRARY DESTINATION lib ARCHIVE DESTINATION lib)
        message(STATUS "  Engine plugin '${name}' (target ${P_TARGET_NAME}): "
                       "${RAC_BUILD_SHARED}-shared / SHARED_ONLY=${P_SHARED_ONLY} / "
                       "C++${P_CXX_STANDARD}")
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
