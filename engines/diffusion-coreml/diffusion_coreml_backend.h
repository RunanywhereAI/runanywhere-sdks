#ifndef RUNANYWHERE_DIFFUSION_COREML_BACKEND_H
#define RUNANYWHERE_DIFFUSION_COREML_BACKEND_H

/**
 * @file diffusion_coreml_backend.h
 * @brief C-callable surface for the CoreML diffusion engine.
 *
 * GAP 06 T5.3. Implementation lives in `diffusion_coreml_backend.mm`
 * (Objective-C++). The plugin entry (`rac_plugin_entry_diffusion_coreml.cpp`)
 * is pure C++ and fills the rac_diffusion_service_ops_t vtable with
 * thin forwarders over the functions declared here.
 */

#include "rac/core/rac_error.h"
#include "rac/features/diffusion/rac_diffusion_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque handle to an initialised CoreML diffusion instance.
 *
 * Internally (inside the .mm TU) this aliases to a struct that holds
 * strong Obj-C references to the four CoreML MLModel instances a
 * Stable Diffusion pipeline needs (TextEncoder, Unet, VAEDecoder,
 * SafetyChecker) plus cached config.
 */
typedef struct rac_diffusion_coreml_impl rac_diffusion_coreml_impl_t;

/**
 * @brief Allocate a new CoreML diffusion impl.
 *
 * The returned handle has NO MLModel loaded yet — call
 * `rac_diffusion_coreml_initialize` to point it at a model directory.
 *
 * @param model_id    Optional model identifier (logged, not required).
 * @param config_json Optional backend-specific JSON (ignored in T5.3).
 * @param out_impl    Receives the impl pointer.
 * @return RAC_SUCCESS on success.
 */
rac_result_t rac_diffusion_coreml_create(const char* model_id,
                                         const char* config_json,
                                         rac_diffusion_coreml_impl_t** out_impl);

/**
 * @brief Initialize by loading the MLModel bundles under `model_path`.
 *
 * `model_path` must be a directory containing compiled Stable Diffusion
 * MLModel assets (Apple's ml-stable-diffusion layout):
 *   - TextEncoder.mlmodelc
 *   - Unet.mlmodelc (or UnetChunk1.mlmodelc + UnetChunk2.mlmodelc for SDXL)
 *   - VAEDecoder.mlmodelc
 *   - SafetyChecker.mlmodelc (optional)
 *
 * @return RAC_SUCCESS when every required MLModel loaded.
 */
rac_result_t rac_diffusion_coreml_initialize(rac_diffusion_coreml_impl_t* impl,
                                             const char* model_path,
                                             const rac_diffusion_config_t* config);

/**
 * @brief Run text-to-image denoising.
 *
 * T5.3 ships the engine shell: the CoreML MLModel handles are loaded but
 * the full SD denoising loop (tokenizer → text embeddings → unet sample
 * → VAE decode → RGBA) is a phase 2 deliverable. Until then this
 * returns `RAC_ERROR_NOT_SUPPORTED` with a clear diagnostic.
 */
rac_result_t rac_diffusion_coreml_generate(rac_diffusion_coreml_impl_t* impl,
                                           const rac_diffusion_options_t* options,
                                           rac_diffusion_result_t* out_result);

/**
 * @brief Generate with progress callback. Same status as generate().
 */
rac_result_t rac_diffusion_coreml_generate_with_progress(
    rac_diffusion_coreml_impl_t* impl,
    const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_cb,
    void* user_data,
    rac_diffusion_result_t* out_result);

rac_result_t rac_diffusion_coreml_get_info(const rac_diffusion_coreml_impl_t* impl,
                                           rac_diffusion_info_t* out_info);

uint32_t     rac_diffusion_coreml_get_capabilities(const rac_diffusion_coreml_impl_t* impl);

rac_result_t rac_diffusion_coreml_cancel(rac_diffusion_coreml_impl_t* impl);

rac_result_t rac_diffusion_coreml_cleanup(rac_diffusion_coreml_impl_t* impl);

void         rac_diffusion_coreml_destroy(rac_diffusion_coreml_impl_t* impl);

#ifdef __cplusplus
}
#endif

#endif  // RUNANYWHERE_DIFFUSION_COREML_BACKEND_H
