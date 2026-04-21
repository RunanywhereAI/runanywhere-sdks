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
 *   - A new primitive lands in `rac_primitive.h`.
 *   - Any existing per-domain ops struct (llm_service_ops etc.) grows or
 *     shrinks.
 *
 * Do NOT bump for additive metadata (new flags in `capability_flags`).
 */
#define RAC_PLUGIN_API_VERSION 1u

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
 * `rac_plugin_register_by_symbol()` explicitly.
 *
 * Note: relies on function-local static init order (C++17). C callers
 * using `-std=c99` or `-std=c17` should fall back to calling
 * `rac_plugin_register(rac_plugin_entry_<name>())` from their existing
 * `rac_backend_<name>_register()` bootstrap for ordering control.
 */
#ifdef __cplusplus
#define RAC_STATIC_PLUGIN_REGISTER(name)                                       \
    namespace rac_plugin_autoreg_##name {                                      \
        /* Use the constructor/destructor pair so we join at shutdown too. */  \
        struct Registrar {                                                     \
            Registrar() noexcept {                                             \
                (void)::rac_plugin_register(::rac_plugin_entry_##name());      \
            }                                                                  \
        };                                                                     \
        static Registrar g_registrar;                                          \
    }
#else
#define RAC_STATIC_PLUGIN_REGISTER(name)                                       \
    /* Static registration requires C++ linkage — use the C bootstrap         \
     * helper in rac_backend_<name>_register.cpp instead. */
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
