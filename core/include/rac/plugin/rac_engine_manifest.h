/**
 * @file rac_engine_manifest.h
 * @brief Declarative metadata manifest for engine plugins.
 *
 * The manifest is intentionally outside rac_engine_vtable_t so adding package
 * ownership and public/private availability does not change the plugin ABI.
 * Engines attach a manifest to their static vtable from the plugin entry
 * function; the registry publishes the manifest only after the vtable itself
 * is accepted.
 */

#ifndef RAC_PLUGIN_ENGINE_MANIFEST_H
#define RAC_PLUGIN_ENGINE_MANIFEST_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum rac_engine_availability {
    RAC_ENGINE_AVAILABILITY_UNSPECIFIED = 0,
    RAC_ENGINE_AVAILABILITY_PUBLIC = 1,
    RAC_ENGINE_AVAILABILITY_PRIVATE = 2,
} rac_engine_availability_t;

typedef struct rac_engine_manifest {
    const char* name;
    const char* display_name;
    const char* version;

    const char* package_owner;
    const char* package_name;
    rac_engine_availability_t availability;

    int32_t priority;
    uint64_t capability_flags;

    const rac_primitive_t* primitives;
    size_t primitives_count;

    const rac_runtime_id_t* runtimes;
    size_t runtimes_count;

    const uint32_t* formats;
    size_t formats_count;

    uint64_t reserved_0;
    uint64_t reserved_1;
} rac_engine_manifest_t;

#define RAC_ENGINE_METADATA_FROM_MANIFEST(manifest_)      \
    {                                                     \
        .abi_version = RAC_PLUGIN_API_VERSION,            \
        .name = (manifest_).name,                         \
        .display_name = (manifest_).display_name,         \
        .engine_version = (manifest_).version,            \
        .priority = (manifest_).priority,                 \
        .capability_flags = (manifest_).capability_flags, \
        .runtimes = (manifest_).runtimes,                 \
        .runtimes_count = (manifest_).runtimes_count,     \
        .formats = (manifest_).formats,                   \
        .formats_count = (manifest_).formats_count,       \
    }

RAC_API const char* rac_engine_availability_name(rac_engine_availability_t availability);

/* These cross the C ABI (Swift / Kotlin JNI / Dart FFI / RN Nitro / WASM)
 * — see rac_plugin_entry.h for the noexcept rationale. The
 * RAC_PLUGIN_REGISTRY_NOEXCEPT macro expands to `noexcept` under C++ and
 * nothing under plain C. */
RAC_API rac_result_t rac_engine_manifest_validate_vtable(const rac_engine_manifest_t* manifest,
                                                         const rac_engine_vtable_t* vtable);

RAC_API rac_result_t rac_engine_manifest_attach_vtable(const rac_engine_manifest_t* manifest,
                                                       const rac_engine_vtable_t* vtable)
    RAC_PLUGIN_REGISTRY_NOEXCEPT;

RAC_API rac_result_t rac_engine_manifest_detach_vtable(const rac_engine_vtable_t* vtable)
    RAC_PLUGIN_REGISTRY_NOEXCEPT;

RAC_API const rac_engine_manifest_t*
rac_engine_manifest_find(const char* name) RAC_PLUGIN_REGISTRY_NOEXCEPT;

RAC_API size_t rac_engine_manifest_count(void) RAC_PLUGIN_REGISTRY_NOEXCEPT;

static inline const rac_engine_vtable_t*
rac_engine_entry_with_manifest(const rac_engine_manifest_t* manifest,
                               const rac_engine_vtable_t* vtable) {
    return rac_engine_manifest_attach_vtable(manifest, vtable) == RAC_SUCCESS ? vtable : RAC_NULL;
}

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENGINE_MANIFEST_H */
