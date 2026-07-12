/**
 * @file rac_plugin_entry.h
 * @brief Plugin entry-point declaration + registration macros.
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
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/plugin/rac_engine_vtable.h"

// NOLINTBEGIN(modernize-redundant-void-arg,modernize-use-nullptr)
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
 *   1u — initial release. 8 primitive slots + 10 reserved slots.
 *                 Metadata = abi_version, name, display_name, engine_version,
 *                 priority, capability_flags, reserved_0, reserved_1.
 *   2u — replaced metadata.reserved_0/_1 (8 bytes total) with the
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
 *                 `rac_service_{can_handle,create}_fn`).
 *                 Plugins built against v2 will be rejected at register
 *                 time with RAC_ERROR_ABI_VERSION_MISMATCH because the
 *                 new `create` slot is unreachable otherwise.
 *                 The associated *types* / *fn typedefs /
 *                 `rac_service_create` / `rac_service_list_providers` are
 *                 gone for good; new code MUST use `rac_plugin_register` /
 *                 `rac_plugin_unregister`.
 *   4u — removed the never-implemented rerank_ops vtable slot and the
 *                 RAC_PRIMITIVE_RERANK primitive (wire value 6 retired). All
 *                 engines rebuild against v4; v3 plugins are rejected at
 *                 register time with RAC_ERROR_ABI_VERSION_MISMATCH.
 *   5u — rac_llm_options_t grew across the engine service boundary. Engines
 *                 compiled against v4 may read a shorter options layout, so
 *                 they are rejected at register time until rebuilt.
 */
#define RAC_PLUGIN_API_VERSION 5u

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
 * The entry symbol is annotated with `RAC_API` (= default ELF/Mach-O
 * visibility, dllexport on Windows). dlsym/static-lookup MUST be able to
 * find this symbol regardless of how the host engine library was linked —
 * notably, even when a SHARED carrier sets visibility=hidden globally and
 * the real definition lives in a sibling static archive (e.g. the
 * runanywhere_llamacpp_vlm shared carrier whose only effective contents come
 * from rac_backend_llamacpp). Without an explicit annotation at declaration
 * time, loadability depended on transitive default visibility of the host
 * plugin target — a brittle invariant that a future visibility tightening
 * would silently break.
 *
 * Example:
 * @code
 *   // sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry_llamacpp.h
 *   #include "rac/plugin/rac_plugin_entry.h"
 *   RAC_PLUGIN_ENTRY_DECL(llamacpp);
 * @endcode
 */
#define RAC_PLUGIN_ENTRY_DECL(name) RAC_API const rac_engine_vtable_t* rac_plugin_entry_##name(void)

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
#define RAC_PLUGIN_ENTRY_DEF(name) RAC_PLUGIN_ENTRY_DECL(name)

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
 *      `cmake/plugins.cmake` wraps these into a single
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

#if defined(__GNUC__) || defined(__clang__)
#define RAC_STATIC_REGISTRAR_USED_ATTR __attribute__((used))
#else
#define RAC_STATIC_REGISTRAR_USED_ATTR /* unsupported */
#endif

/* The `Registrar()` ctor below is marked `noexcept` because it runs during
 * pre-main() static initialization — an escaping exception would call
 * std::terminate before any logger / crash reporter is wired up. This is safe
 * by construction: `rac_plugin_register` itself is declared noexcept (see
 * RAC_PLUGIN_REGISTRY_NOEXCEPT below) and internally coerces std::bad_alloc /
 * throwing capability_check callbacks into structured rac_result_t codes. */
#define RAC_STATIC_PLUGIN_REGISTER(name)                                                          \
    namespace rac_plugin_autoreg_##name {                                                         \
        struct Registrar {                                                                        \
            Registrar() noexcept {                                                                \
                (void)::rac_plugin_register(::rac_plugin_entry_##name());                         \
            }                                                                                     \
        };                                                                                        \
        /* `used` keeps the symbol after compiler dead-code analysis; the host                    \
         * still has to ask the linker not to drop the .o file (see header                        \
         * docs above for the per-platform link flag). */                                         \
        RAC_STATIC_REGISTRAR_USED_ATTR static Registrar g_registrar;                              \
    }                                                                                             \
    /* Force at least one externally-visible symbol per plugin so the linker                      \
     * can be asked to keep the TU by name without `-force_load`. */                              \
    extern "C" RAC_STATIC_REGISTRAR_USED_ATTR const char* const rac_plugin_static_marker_##name = \
        #name

/**
 * @brief Variant of RAC_STATIC_PLUGIN_REGISTER that routes through a backend's
 *        explicit `rac_backend_<name>_register()` entry point.
 *
 * Some backends need more than the bare
 * `rac_plugin_register(rac_plugin_entry_<name>())` that RAC_STATIC_PLUGIN_REGISTER
 * performs — e.g. llamacpp also hooks up its CPU-runtime provider.
 * Those backends expose a hand-written `rac_backend_<name>_register()` that does
 * the unified plugin registration *plus* the engine-specific bring-up, and is
 * idempotent on repeat calls (so the dynamic-link path — where the SDK bridge
 * calls it directly — and this static-init path agree).
 *
 * This macro emits the SAME static-init scaffold and the SAME externally-visible
 * marker symbol (`rac_plugin_static_marker_<name>`) as RAC_STATIC_PLUGIN_REGISTER,
 * so the `-force_load` / `--whole-archive` / MSVC `/INCLUDE:` keep-alive in
 * `cmake/plugins.cmake` is unchanged. The only difference is that the Registrar
 * ctor calls `::rac_backend_##name##_register()` instead of
 * `rac_plugin_register(rac_plugin_entry_##name())`. See RAC_STATIC_PLUGIN_REGISTER
 * above for the full rationale on `used`, init ordering, and noexcept.
 *
 * Usage (one line in a dedicated C++ shim TU named explicitly in CMake so it is
 * retained by `-force_load`):
 * @code
 *   RAC_STATIC_REGISTER_BACKEND(llamacpp);
 * @endcode
 */
#define RAC_STATIC_REGISTER_BACKEND(name)                                                         \
    extern "C" rac_result_t rac_backend_##name##_register(void);                                  \
    namespace rac_plugin_autoreg_##name {                                                         \
        struct Registrar {                                                                        \
            Registrar() noexcept {                                                                \
                (void)::rac_backend_##name##_register();                                          \
            }                                                                                     \
        };                                                                                        \
        /* `used` keeps the symbol after compiler dead-code analysis; the host                    \
         * still has to ask the linker not to drop the .o file (see header                        \
         * docs above for the per-platform link flag). */                                         \
        RAC_STATIC_REGISTRAR_USED_ATTR static Registrar g_registrar;                              \
    }                                                                                             \
    /* Force at least one externally-visible symbol per plugin so the linker                      \
     * can be asked to keep the TU by name without `-force_load`. */                              \
    extern "C" RAC_STATIC_REGISTRAR_USED_ATTR const char* const rac_plugin_static_marker_##name = \
        #name

#else
#define RAC_STATIC_PLUGIN_REGISTER(name)
/* Static registration requires C++ linkage — put a one-line C++ shim TU \
 * in your plugin that calls RAC_STATIC_PLUGIN_REGISTER(<name>). */
#define RAC_STATIC_REGISTER_BACKEND(name)
#endif

/* ===========================================================================
 * Boilerplate "create" adapter helper
 *
 * Most backends' per-primitive `create` op is a 7-line forward onto the
 * engine's native `rac_<primitive>_<name>_create(model_id, nullptr, &handle)`
 * entry point. This macro generates that scaffold so each backend doesn't
 * hand-copy it.
 *
 * Scope: sherpa STT / TTS / VAD today. Backends with richer create flows
 * (llamacpp LLM — CPU-runtime session wrapping; onnx embeddings — try/catch
 * + unique_ptr; llamacpp VLM — mmproj path plumbing) hand-write their
 * adapter and are NOT expected to use this macro.
 *
 * Requirements at expansion site:
 *   - a file-scope `const char* LOG_CAT` (or similar) visible to RAC_LOG_INFO;
 *   - `rac_<primitive>_<name>_create(const char*, const <cfg>*, rac_handle_t*)`
 *     declared (i.e. the backend header is already included).
 *
 * The generated function has the ABI-v3 `create` signature:
 *   rac_result_t <name>_<primitive>_create_impl(const char* model_id,
 *                                               const char* config_json,
 *                                               void** out_impl);
 * `config_json` is currently ignored (passed as nullptr to the engine create);
 * bring-your-own-adapter if you need to thread config through.
 * =========================================================================== */

#ifdef __cplusplus
#define RAC_DEFINE_CREATE_ADAPTER(primitive, name)                                                 \
    static ::rac_result_t name##_##primitive##_create_impl(                                        \
        const char* model_id, const char* /*config_json*/, void** out_impl) {                      \
        if (!out_impl)                                                                             \
            return RAC_ERROR_NULL_POINTER;                                                         \
        *out_impl = nullptr;                                                                       \
        RAC_LOG_INFO(LOG_CAT, #name "_" #primitive "_create_impl: model=%s",                       \
                     model_id ? model_id : "(default)");                                           \
        ::rac_handle_t backend_handle = nullptr;                                                   \
        ::rac_result_t rc = rac_##primitive##_##name##_create(model_id, nullptr, &backend_handle); \
        if (rc != RAC_SUCCESS)                                                                     \
            return rc;                                                                             \
        *out_impl = backend_handle;                                                                \
        return RAC_SUCCESS;                                                                        \
    }
#else
#define RAC_DEFINE_CREATE_ADAPTER(primitive, name)                                            \
    static rac_result_t name##_##primitive##_create_impl(                                     \
        const char* model_id, const char* /*config_json*/, void** out_impl) {                 \
        if (!out_impl)                                                                        \
            return RAC_ERROR_NULL_POINTER;                                                    \
        *out_impl = NULL;                                                                     \
        RAC_LOG_INFO(LOG_CAT, #name "_" #primitive "_create_impl: model=%s",                  \
                     model_id ? model_id : "(default)");                                      \
        rac_handle_t backend_handle = NULL;                                                   \
        rac_result_t rc = rac_##primitive##_##name##_create(model_id, NULL, &backend_handle); \
        if (rc != RAC_SUCCESS)                                                                \
            return rc;                                                                        \
        *out_impl = backend_handle;                                                           \
        return RAC_SUCCESS;                                                                   \
    }
#endif

/* ===========================================================================
 * Registry operations (implemented in src/plugin/rac_plugin_registry.cpp)
 * =========================================================================== */

/* All registry functions below are noexcept under C++ linkage: they cross
 * the C ABI into Swift / Kotlin (JNI) / Dart (FFI) / Hermes (NitroModules)
 * / WASM. Propagating a C++ exception out of an extern "C" function is
 * undefined behavior per ISO C++ [except.handle]/9. Internally each
 * implementation wraps allocator-throwing operations + third-party
 * callbacks in try/catch and coerces failures to RAC_ERROR_OUT_OF_MEMORY /
 * RAC_ERROR_PLUGIN_LOAD_FAILED / RAC_ERROR_INTERNAL. The noexcept
 * specifier is conditionally compiled so plain C consumers see the C
 * signatures unchanged. */
#ifdef __cplusplus
#define RAC_PLUGIN_REGISTRY_NOEXCEPT noexcept
#else
#define RAC_PLUGIN_REGISTRY_NOEXCEPT
#endif

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
RAC_API rac_result_t
rac_plugin_register(const rac_engine_vtable_t* vtable) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/**
 * @brief Unregister a plugin by name. No-op if the name is not registered.
 */
RAC_API rac_result_t rac_plugin_unregister(const char* name) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/**
 * @brief Look up the highest-priority plugin that serves `primitive`, or NULL
 *        if none are registered.
 *
 * Thread-safe. The returned pointer is valid for the remaining lifetime of
 * the registry (i.e. until `rac_plugin_unregister` is called for this name).
 */
RAC_API const rac_engine_vtable_t*
rac_plugin_find(rac_primitive_t primitive) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/**
 * @brief Look up the plugin registered under `engine_name` IFF it serves
 *        `primitive`, else NULL. Used to pin a specific engine (e.g. the hybrid
 *        STT router's offline "sherpa" vs online "cloud") where simple priority
 *        order cannot distinguish two plugins that serve the same primitive.
 *
 * Thread-safe.
 */
RAC_API const rac_engine_vtable_t*
rac_plugin_find_for_engine(rac_primitive_t primitive,
                           const char* engine_name) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/**
 * @brief Iterate all plugins registered for `primitive`, in descending
 *        priority order. `out_count` receives the number of writes.
 *
 * Callers pass an array of `max` `const rac_engine_vtable_t*` pointers; the
 * registry fills it in-place. Values >= `max` are truncated.
 */
RAC_API rac_result_t rac_plugin_list(rac_primitive_t primitive,
                                     const rac_engine_vtable_t** out_plugins, size_t max,
                                     size_t* out_count) RAC_PLUGIN_REGISTRY_NOEXCEPT;

/**
 * @brief Total number of registered plugins (across all primitives,
 *        counting each plugin once).
 */
RAC_API size_t rac_plugin_count(void) RAC_PLUGIN_REGISTRY_NOEXCEPT;

#ifdef __cplusplus
}
#endif
// NOLINTEND(modernize-redundant-void-arg,modernize-use-nullptr)

#endif /* RAC_PLUGIN_ENTRY_H */
