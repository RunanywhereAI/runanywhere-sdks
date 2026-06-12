/**
 * @file rac_cpu_runtime_provider.h
 * @brief Provider hook for CPU runtime session dispatch.
 *
 * The built-in CPU runtime lives in rac_commons, while concrete CPU engines
 * such as llama.cpp live in engine plugins. This small provider API lets those
 * plugins attach primitive-specific session handlers without making the CPU
 * runtime link against any engine.
 */

#ifndef RAC_PLUGIN_CPU_RUNTIME_PROVIDER_H
#define RAC_PLUGIN_CPU_RUNTIME_PROVIDER_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_vtable.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_cpu_runtime_provider {
    /** Stable provider name, e.g. "llamacpp". MUST NOT be NULL. */
    const char* name;

    /** Primitive served by this provider. */
    rac_primitive_t primitive;

    /** Supported model formats. Empty means format-agnostic. */
    const uint32_t* formats;
    size_t formats_count;

    rac_result_t (*create_session)(const rac_runtime_session_desc_t* desc,
                                   rac_runtime_session_t** out);
    rac_result_t (*run_session)(rac_runtime_session_t* session, const rac_runtime_io_t* inputs,
                                size_t n_in, rac_runtime_io_t* outputs, size_t n_out);
    void (*destroy_session)(rac_runtime_session_t* session);

    /**
     * Optional V2-native execution op.
     *
     * When non-NULL the CPU runtime dispatches `run_session_v2` directly to
     * this callback, passing V2 tensors through untouched. Providers that
     * implement this slot see real `rac_runtime_tensor_t` values — buffers,
     * ownership flags, capacity fields, and memory-space tags are preserved
     * and can be mutated back on owned outputs. The CPU runtime then
     * advertises `RAC_RUNTIME_CAP_OWNED_OUTPUTS` because outputs can flow
     * back through a live V2 path.
     *
     * When NULL the CPU runtime falls back to the legacy V1 shim: tensors
     * are flattened into `rac_runtime_io_t` for `run_session`, then dtype /
     * rank / byte counts are copied back. Ownership transfer and capacity
     * tracking are only reachable via the V2 op.
     *
     * MAY be NULL. Added after the initial ABI so existing providers keep
     * working — the struct is zero-initialised by callers.
     */
    rac_result_t (*run_session_v2)(rac_runtime_session_t* session,
                                   const rac_runtime_tensor_t* inputs, size_t n_in,
                                   rac_runtime_tensor_t* outputs, size_t n_out);
} rac_cpu_runtime_provider_t;

/**
 * Register or replace a CPU runtime provider.
 *
 * Providers are copied by value; string / format-array storage must outlive the
 * provider registration, mirroring the rest of the plugin metadata ABI.
 */
RAC_API rac_result_t rac_cpu_runtime_register_provider(const rac_cpu_runtime_provider_t* provider);

/** Unregister a provider by name. NULL is ignored. */
RAC_API void rac_cpu_runtime_unregister_provider(const char* name);

/**
 * Return the provider-owned session behind a CPU runtime session.
 *
 * This exists for staged migrations where legacy streaming / LoRA APIs still
 * need the engine-native handle while blocking generate moves through
 * rac_runtime_vtable_t::run_session.
 */
RAC_API rac_result_t
rac_cpu_runtime_get_provider_session(rac_runtime_session_t* session, const char** out_provider_name,
                                     rac_runtime_session_t** out_provider_session);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_CPU_RUNTIME_PROVIDER_H */
