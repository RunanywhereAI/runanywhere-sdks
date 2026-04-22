/**
 * @file rac_plugin_entry.h
 * @brief Plugin entry-point declaration + registration macros.
 *
 * GAP 02 Phase 7 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * A plugin is a collection of static or dynamic library symbols that, when
 * the host calls `rac_plugin_entry_<name>()`, returns a pointer to a filled
 * `rac_engine_vtable_t`. The registry takes ownership of the returned
 * pointer's *storage* but not the vtable contents — vtables are expected to
 * live in .rodata of the plugin library (i.e. no runtime allocation).
 *
 * Two registration modes:
 *   1. Static registration (recommended for iOS / statically-linked builds).
 *      Plugin authors use `RAC_STATIC_PLUGIN_REGISTER(name)` at file scope.
 *      The registry iterates the symbol table at init via the constructor
 *      helper emitted by the macro.
 *   2. Dynamic loading (dlsym) — the host calls `rac_plugin_entry_<name>()`
 *      by name via `dlsym` after `dlopen`-ing the plugin library. The plugin
 *      declares the symbol using `RAC_PLUGIN_ENTRY_DECL(name)` in its public
 *      header and defines it with `RAC_PLUGIN_ENTRY_DEF(name) { ... }`.
 */

#ifndef RAC_PLUGIN_ENTRY_H
#define RAC_PLUGIN_ENTRY_H

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Plugin API version.
 *
 * Bump when:
 *   - `rac_engine_vtable_t` field layout changes (e.g. a reserved slot is
 *     promoted).
 *   - `rac_engine_metadata_t` field layout changes.
 *   - A new primitive lands in `rac_primitive.h`.
 *   - Any existing per-domain ops struct (llm_service_ops etc.) grows or
 *     shrinks.
 *
 * Do NOT bump for additive metadata (new flags in `capability_flags`).
 *
 * Version history:
 *   1u (GAP 02) — initial release. 8 primitive slots + 10 reserved slots.
 *                 Metadata = abi_version, name, display_name, engine_version,
 *                 priority, capability_flags, reserved_0, reserved_1.
 *   2u (GAP 04) — replaced metadata.reserved_0/_1 (8 bytes total) with the
 *                 routing extension: runtimes[] + runtimes_count +
 *                 formats[] + formats_count (48 bytes total). Plugins built
 *                 against v1 will be rejected at register time with
 *                 RAC_ERROR_ABI_VERSION_MISMATCH (the safe outcome — the
 *                 router would otherwise read garbage for the new fields).
 *   3u (v3.0.0) — added `create(model_id, config_json, out_impl)` op to
 *                 all 7 per-primitive ops structs (LLM, STT, TTS, VAD,
 *                 VLM, embeddings, diffusion). Added `initialize(impl,
 *                 model_path)` to VAD for symmetry with other primitives.
 *                 Removed the legacy `rac_service_*` registry surface
 *                 (`rac_service_register_provider`, `rac_service_create`,
 *                 `rac_service_list_providers`, `rac_service_unregister_provider`,
 *                 `rac_service_request_t`, `rac_service_provider_t`,
 *                 `rac_service_{can_handle,create}_fn`, `RAC_DEPRECATED_LEGACY_SVC`).
 *                 Plugins built against v2 will be rejected at register
 *                 time with RAC_ERROR_ABI_VERSION_MISMATCH because the
 *                 new `create` slot is unreachable otherwise. `rac_capability_t`
 *                 is RETAINED for `rac_module_info_t.capabilities` and
 *                 `rac_modules_for_capability`.
 */
#define RAC_PLUGIN_API_VERSION 2u  /* bumped to 3u in v3.0.0 release (Phase C3) */

/* ===========================================================================
 * Plugin entry-point signature
 *
 * Every plugin MUST expose:
 *   const rac_engine_vtable_t* rac_plugin_entry_<name>(void);
 * The host looks up this symbol by name (static registration) or via dlsym
 * (dynamic loading).
 * =========================================================================== */

typedef const rac_engine_vtable_t* (*rac_plugin_entry_fn)(void);

/**
 * @brief Declare a plugin entry point in a public header.
 *
 * Example:
 * @code
 *   // sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry_llamacpp.h
 *   #include "rac/plugin/rac_plugin_entry.h"
 *   RAC_PLUGIN_ENTRY_DECL(llamacpp);
 * @endcode
 */
#define RAC_PLUGIN_ENTRY_DECL(name) \
    const rac_engine_vtable_t* rac_plugin_entry_##name(void)

/**
 * @brief Define a plugin entry point in the .cpp file.
 *
 * Body returns the address of the plugin's static `rac_engine_vtable_t`.
 * Example:
 * @code
 *   RAC_PLUGIN_ENTRY_DEF(llamacpp) {
 *       return &g_llamacpp_vtable;
 *   }
 * @endcode
 */
#define RAC_PLUGIN_ENTRY_DEF(name) \
    RAC_PLUGIN_ENTRY_DECL(name)

/* ===========================================================================
 * Static registration (iOS / Android / no-dlopen builds)
 * =========================================================================== */

/**
 * @brief Register a plugin's vtable with the registry at process start.
 *
 * Expands to a file-scope static initialization that calls
 * `rac_plugin_register(rac_plugin_entry_<name>())` before main().
 *
 * Prefer this over manual registration when a static-lib plugin is linked
 * into the host binary. For dynamic plugins (`dlopen`) the host calls
 * `rac_registry_load_plugin(path)` from `rac_plugin_loader.h` explicitly.
 *
 * ## Linker survival (the iOS / macOS gotcha)
 *
 * Apple's linker strips unreferenced TUs from a static archive (.a). The
 * `Registrar` global below is unreferenced from the host binary's perspective
 * — so without help, the entire plugin TU vanishes and registration never
 * runs. Two layers of defense:
 *
 *   1. The `[[gnu::used]]` / `__attribute__((used))` attribute on `g_registrar`
 *      tells the COMPILER to keep the symbol in the object file.
 *   2. The host binary must additionally tell the LINKER to keep the object
 *      file. Pick one:
 *        - macOS / iOS:   `-Wl,-force_load,libplugin.a`
 *        - GNU / Android: `-Wl,--whole-archive libplugin.a -Wl,--no-whole-archive`
 *        - MSVC:          add `/INCLUDE:_g_rac_plugin_autoreg_<name>` per plugin
 *      `cmake/plugins.cmake` (introduced in GAP 07) wraps these into a single
 *      `rac_force_load(plugin_target)` helper.
 *
 * ## Init ordering
 *
 * `g_registrar` is a namespace-scope object with non-trivial initialization,
 * so it runs in its TU's static-init phase before `main()`. `rac_plugin_register`
 * uses a Meyers singleton (function-local static) for the registry state, so
 * static-init order across TUs does not matter — the registry materializes
 * lazily on first use.
 *
 * ## C linkage
 *
 * Because the macro defines a C++ struct, only C++ TUs may use it. C plugin
 * authors should put a single C++ shim TU in their plugin (one line:
 * `RAC_STATIC_PLUGIN_REGISTER(myplugin);`) and keep the rest of the engine in C.
 */
#ifdef __cplusplus

#  if defined(__GNUC__) || defined(__clang__)
#    define RAC_STATIC_REGISTRAR_USED_ATTR __attribute__((used))
#  else
#    define RAC_STATIC_REGISTRAR_USED_ATTR /* unsupported */
#  endif

#define RAC_STATIC_PLUGIN_REGISTER(name)                                       \
    namespace rac_plugin_autoreg_##name {                                      \
        struct Registrar {                                                     \
            Registrar() noexcept {                                             \
                (void)::rac_plugin_register(::rac_plugin_entry_##name());      \
            }                                                                  \
        };                                                                     \
        /* `used` keeps the symbol after compiler dead-code analysis; the host \
         * still has to ask the linker not to drop the .o file (see header     \
         * docs above for the per-platform link flag). */                      \
        RAC_STATIC_REGISTRAR_USED_ATTR static Registrar g_registrar;           \
    }                                                                          \
    /* Force at least one externally-visible symbol per plugin so the linker  \
     * can be asked to keep the TU by name without `-force_load`. */          \
    extern "C" RAC_STATIC_REGISTRAR_USED_ATTR                                  \
    const char* const rac_plugin_static_marker_##name = #name

#else
#define RAC_STATIC_PLUGIN_REGISTER(name)                                       \
    /* Static registration requires C++ linkage — put a one-line C++ shim TU \
     * in your plugin that calls RAC_STATIC_PLUGIN_REGISTER(<name>). */
#endif

/* ===========================================================================
 * Registry operations (implemented in src/plugin/rac_plugin_registry.cpp)
 * =========================================================================== */

/**
 * @brief Register a plugin vtable. Performs ABI validation + capability check
 *        + dedup by `metadata.name`.
 *
 * Returns RAC_SUCCESS on accept, RAC_ERROR_ABI_VERSION_MISMATCH on version
 * skew, or the non-zero status returned by `capability_check()` on silent
 * reject.
 *
 * Thread-safe.
 */
rac_result_t rac_plugin_register(const rac_engine_vtable_t* vtable);

/**
 * @brief Unregister a plugin by name. No-op if the name is not registered.
 */
rac_result_t rac_plugin_unregister(const char* name);

/**
 * @brief Look up the highest-priority plugin that serves `primitive`, or NULL
 *        if none are registered.
 *
 * Thread-safe. The returned pointer is valid for the remaining lifetime of
 * the registry (i.e. until `rac_plugin_unregister` is called for this name).
 */
const rac_engine_vtable_t* rac_plugin_find(rac_primitive_t primitive);

/**
 * @brief Iterate all plugins registered for `primitive`, in descending
 *        priority order. `out_count` receives the number of writes.
 *
 * Callers pass an array of `max` `const rac_engine_vtable_t*` pointers; the
 * registry fills it in-place. Values >= `max` are truncated.
 */
rac_result_t rac_plugin_list(rac_primitive_t primitive,
                             const rac_engine_vtable_t** out_plugins,
                             size_t max,
                             size_t* out_count);

/**
 * @brief Total number of registered plugins (across all primitives,
 *        counting each plugin once).
 */
size_t rac_plugin_count(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENTRY_H */
