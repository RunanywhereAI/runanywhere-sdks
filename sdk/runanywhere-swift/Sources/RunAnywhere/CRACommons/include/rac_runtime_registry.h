/**
 * @file rac_runtime_registry.h
 * @brief Registry for L1 runtime plugins.
 *
 * Task T4.1.
 *
 * Mirrors the engine-plugin registry (`rac_plugin_entry.h`) but keyed by
 * `rac_runtime_id_t` instead of `rac_primitive_t`. Every runtime plugin
 * (CPU, Metal, CoreML, ONNX Runtime, CUDA, …) registers here exactly once
 * per process.
 *
 * Thread-safety: all functions are safe to call concurrently. Returned
 * vtable pointers remain valid until the matching
 * `rac_runtime_unregister(id)` completes.
 */

#ifndef RAC_PLUGIN_RUNTIME_REGISTRY_H
#define RAC_PLUGIN_RUNTIME_REGISTRY_H

#include <stddef.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_primitive.h"        /* rac_runtime_id_t */
#include "rac_runtime_vtable.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Register a runtime plugin.
 *
 * Validation steps, in order:
 *   1. NULL checks on vtable + `metadata.name` + required op slots
 *      (`init`, `destroy`).
 *   2. `metadata.abi_version == RAC_RUNTIME_ABI_VERSION`.
 *   3. `init()` returns 0 (non-zero → silent reject).
 *   4. Dedup by `metadata.id`: a new vtable replaces an existing one iff its
 *      priority is `>=` the existing priority; otherwise
 *      `RAC_ERROR_PLUGIN_DUPLICATE` is returned and the incoming vtable's
 *      `destroy()` is called to unwind its `init()`.
 *
 * On success the registry owns the dispatch mapping but NOT the vtable
 * storage — the plugin is responsible for keeping the pointer alive until
 * `rac_runtime_unregister(id)` returns.
 */
RAC_API rac_result_t rac_runtime_register(const rac_runtime_vtable_t* vtable);

/**
 * @brief Unregister the runtime with the given id.
 *
 * Calls the vtable's `destroy()` before removing the entry. Returns
 * `RAC_ERROR_NOT_FOUND` when no runtime is registered under `id`.
 */
RAC_API rac_result_t rac_runtime_unregister(rac_runtime_id_t id);

/**
 * @brief Look up a runtime vtable by id.
 *
 * Returns NULL when no runtime is registered for `id`.
 */
RAC_API const rac_runtime_vtable_t* rac_runtime_get_by_id(rac_runtime_id_t id);

/**
 * @brief Snapshot the registered runtimes, descending priority.
 *
 * Callers pass an array of `max` vtable pointers; the registry writes up to
 * `max` entries and sets `*out_count` to the number of writes. Returns
 * `RAC_SUCCESS` with `*out_count = 0` when empty.
 */
RAC_API rac_result_t rac_runtime_list(const rac_runtime_vtable_t** out_runtimes,
                                      size_t max,
                                      size_t* out_count);

/**
 * @brief Total number of registered runtimes.
 */
RAC_API size_t rac_runtime_count(void);

/**
 * @brief True iff a runtime with `id` is currently registered. Convenience
 *        wrapper around `rac_runtime_get_by_id(id) != NULL`, exposed as a
 *        separate symbol so the engine router can test runtime presence
 *        without pulling in the vtable struct layout.
 */
RAC_API int rac_runtime_is_available(rac_runtime_id_t id);

/**
 * @brief True iff a runtime with `id` is currently registered.
 *
 * Routing-oriented alias for `rac_runtime_is_available`, named after the
 * registry verb. The engine router uses this to filter engines whose
 * declared runtimes are not present on the current host (e.g. CoreML on
 * Android, Metal on Web, QNN on a non-Snapdragon device). Returns 0/1.
 *
 * Behaviorally identical to `rac_runtime_is_available`; provided as a
 * clearer name for the routing pre-flight check so callers don't have to
 * read it as "is the runtime *available* (= registered)".
 */
RAC_API int rac_runtime_is_registered(rac_runtime_id_t id);

/**
 * @brief Runtime ABI version this build of `rac_commons` supports.
 */
RAC_API uint32_t rac_runtime_abi_version(void);

/**
 * @brief Load a runtime shared library, resolve `rac_runtime_entry_<stem>`,
 *        and register the returned vtable.
 *
 * The loader strips directory, optional `lib` prefix, extension, and optional
 * `runanywhere_` prefix from `path`, then looks up `rac_runtime_entry_<stem>`.
 * It mirrors the engine plugin loader while keeping runtime loading separate
 * from generic engine plugin loading.
 *
 * @return RAC_SUCCESS on accept, or RAC_ERROR_NULL_POINTER,
 *         RAC_ERROR_PLUGIN_LOAD_FAILED, RAC_ERROR_ABI_VERSION_MISMATCH,
 *         RAC_ERROR_CAPABILITY_UNSUPPORTED, RAC_ERROR_PLUGIN_DUPLICATE, or
 *         RAC_ERROR_FEATURE_NOT_AVAILABLE when the host is built static-only.
 */
RAC_API rac_result_t rac_runtime_load(const char* path);

/**
 * @brief Unregister a runtime by id and close its dynamic-library handle when
 *        it was loaded through `rac_runtime_load`.
 */
RAC_API rac_result_t rac_runtime_unload(rac_runtime_id_t id);

/* ===========================================================================
 * Static registration helper (parallel to RAC_STATIC_PLUGIN_REGISTER).
 *
 * Use at namespace scope in a runtime plugin's .cpp:
 *   RAC_STATIC_RUNTIME_REGISTER(cpu);
 * Expects `rac_runtime_entry_<name>()` to be defined in the same TU (via
 * `RAC_RUNTIME_ENTRY_DEF(<name>)`).
 * =========================================================================== */

#ifdef __cplusplus

#  if defined(__GNUC__) || defined(__clang__)
#    define RAC_STATIC_RUNTIME_USED_ATTR __attribute__((used))
#  else
#    define RAC_STATIC_RUNTIME_USED_ATTR /* unsupported */
#  endif

#define RAC_STATIC_RUNTIME_REGISTER(name)                                      \
    namespace rac_runtime_autoreg_##name {                                     \
        struct Registrar {                                                     \
            Registrar() noexcept {                                             \
                (void)::rac_runtime_register(::rac_runtime_entry_##name());    \
            }                                                                  \
        };                                                                     \
        RAC_STATIC_RUNTIME_USED_ATTR static Registrar g_registrar;             \
    }                                                                          \
    extern "C" RAC_STATIC_RUNTIME_USED_ATTR                                    \
    const char* const rac_runtime_static_marker_##name = #name

#endif

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_RUNTIME_REGISTRY_H */
