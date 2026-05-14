/**
 * @file rac_onnxrt_runtime_provider.h
 * @brief Provider hook for ONNX Runtime L1 adapter session dispatch.
 *
 * RT-ONNX-06: symmetric to `rac_cpu_runtime_provider.h`. The ONNX Runtime
 * adapter lives in `runtimes/onnxrt/` and publishes a generic ORT tensor
 * runner, while primitive-specific engines (embedding, STT, TTS, VAD) live
 * in engine plugins. This small provider API lets those plugins attach
 * primitive-specific session handlers without rediscovering the onnxrt
 * singleton or re-linking against ORT themselves.
 *
 * Semantics mirror the CPU provider surface exactly:
 *   - Providers are keyed by `(primitive, name)`; re-registering the same
 *     name replaces the existing entry.
 *   - `formats` / `formats_count` narrows matching to specific model
 *     formats (0 / empty → format-agnostic).
 *   - When a consumer calls `onnxrt_create_session` with a primitive that
 *     has a registered provider, the runtime routes create/run/destroy
 *     through the provider's callbacks. Otherwise the generic ORT tensor
 *     runner handles the request directly.
 *   - `run_session_v2` is optional; when non-NULL the runtime forwards V2
 *     tensors untouched so the provider can preserve buffer ownership and
 *     capacity semantics.
 */

#ifndef RAC_PLUGIN_ONNXRT_RUNTIME_PROVIDER_H
#define RAC_PLUGIN_ONNXRT_RUNTIME_PROVIDER_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_vtable.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_onnxrt_runtime_provider {
    /** Stable provider name, e.g. "onnx-embeddings". MUST NOT be NULL. */
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
     * When non-NULL the onnxrt runtime dispatches `run_session_v2` directly
     * to this callback, passing V2 tensors through untouched. Providers that
     * implement this slot see real `rac_runtime_tensor_t` values — buffers,
     * ownership flags, capacity fields, and memory-space tags are preserved
     * and can be mutated back on owned outputs.
     *
     * When NULL the onnxrt runtime falls back to the built-in V2 path that
     * runs through `Session::run` and copies outputs into caller-supplied
     * or runtime-allocated storage.
     *
     * MAY be NULL. Added after the initial ABI so existing providers keep
     * working — the struct is zero-initialised by callers.
     */
    rac_result_t (*run_session_v2)(rac_runtime_session_t* session,
                                   const rac_runtime_tensor_t* inputs, size_t n_in,
                                   rac_runtime_tensor_t* outputs, size_t n_out);
} rac_onnxrt_runtime_provider_t;

/**
 * Register or replace an ONNX Runtime provider.
 *
 * Providers are copied by value; string / format-array storage must outlive
 * the provider registration, mirroring the rest of the plugin metadata ABI.
 */
RAC_API rac_result_t
rac_onnxrt_runtime_register_provider(const rac_onnxrt_runtime_provider_t* provider);

/** Unregister a provider by name. NULL is ignored. */
RAC_API void rac_onnxrt_runtime_unregister_provider(const char* name);

/**
 * Return the provider-owned session behind an onnxrt runtime session.
 *
 * Mirrors `rac_cpu_runtime_get_provider_session`. When the session was
 * opened by a registered provider, the provider's name and native session
 * handle are returned so staged migrations (LoRA, streaming, engine-native
 * state) can still reach through to the provider. For sessions opened via
 * the built-in generic tensor runner, `*out_provider_name` is NULL and
 * `*out_provider_session` is set to the same `session` pointer so callers
 * can treat the generic path uniformly.
 */
RAC_API rac_result_t rac_onnxrt_runtime_get_provider_session(
    rac_runtime_session_t* session, const char** out_provider_name,
    rac_runtime_session_t** out_provider_session);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ONNXRT_RUNTIME_PROVIDER_H */
