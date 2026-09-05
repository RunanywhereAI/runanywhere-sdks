/**
 * @file rac_image_embedding_service.h
 * @brief Image embedding (`RAC_PRIMITIVE_EMBED_IMAGE`) — pixels in, one vector out.
 *
 * A SEPARATE primitive from `RAC_PRIMITIVE_EMBED` rather than an overload of it, and that is
 * deliberate. The text ops take a `const char*`; a vision tower takes decoded pixels plus their
 * dimensions. Passing a file path or base64 through the text field would be a backend-specific wire
 * hack that breaks validation, batching, preprocessing ownership and telemetry — so the input gets
 * its own typed struct instead.
 *
 * Distinct from VLM too: VLM is image + prompt -> TEXT. This is image -> VECTOR, for retrieval and
 * similarity. SigLIP2 is the first model to serve it.
 *
 * The RESULT type is reused from text embeddings (`rac_embeddings_result_t`): an image embedding is
 * still a dense float vector with a dimension, and inventing a parallel result type would duplicate
 * the ownership contract for no benefit.
 */
#ifndef RAC_IMAGE_EMBEDDING_SERVICE_H
#define RAC_IMAGE_EMBEDDING_SERVICE_H

#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Pixel layout of an image handed to the embedder. */
typedef enum rac_image_embedding_format {
    /** Packed RGB8, HWC, tightly packed (RGBRGBRGB...). */
    RAC_IMAGE_EMBEDDING_FORMAT_RGB8 = 0
} rac_image_embedding_format_t;

/**
 * @brief One decoded image.
 *
 * DECODED pixels only, by design: decoding is a platform concern — the Swift SDK's `ImageInput`
 * already converts CGImage/UIImage/CVPixelBuffer to packed RGB before the C ABI — and linking an
 * image codec into every engine would be real weight for no benefit.
 */
typedef struct rac_image_embedding_input {
    rac_image_embedding_format_t format;
    /** Borrowed pixel buffer; must outlive the call. */
    const uint8_t* pixels;
    uint32_t width;
    uint32_t height;
} rac_image_embedding_input_t;

/**
 * @brief Backend operations for image embedding.
 */
typedef struct rac_image_embedding_service_ops {
    /** Initialize the service with a model path. */
    rac_result_t (*initialize)(void* impl, const char* model_path);

    /**
     * Embed one image. `out_result` carries a single vector and is released with
     * `rac_embeddings_result_free`, exactly as the text path's result is.
     */
    rac_result_t (*embed_image)(void* impl, const rac_image_embedding_input_t* image,
                                rac_embeddings_result_t* out_result);

    /** Service information. */
    rac_result_t (*get_info)(void* impl, rac_embeddings_info_t* out_info);

    /** Cleanup resources (keeps the service alive). */
    rac_result_t (*cleanup)(void* impl);

    /** Destroy the service. */
    void (*destroy)(void* impl);

    /** Allocate a backend-specific impl. See rac_llm_service_ops_t::create for the semantics. */
    rac_result_t (*create)(const char* model_id, const char* config_json, void** out_impl);
} rac_image_embedding_service_ops_t;

/**
 * @brief A created image-embedding service.
 *
 * Same shape as `rac_rerank_service_t`, and created the same way: a STANDALONE service factory,
 * not a lifecycle component. Rerank set that precedent for a reason -- a model that serves one
 * narrow primitive does not need a `LoadedModel` slot, a `ModelCategory` arm, or a component
 * enum; it needs a handle. Image embedding is the same shape.
 */
typedef struct rac_image_embedding_service {
    const rac_image_embedding_service_ops_t* ops;
    void* impl;
    const char* model_id;
} rac_image_embedding_service_t;

/** Resolve `model_id`, find a plugin serving `RAC_PRIMITIVE_EMBED_IMAGE`, and create a service. */
RAC_API rac_result_t rac_image_embedding_create(const char* model_id, rac_handle_t* out_handle);

/** Load the model at `model_path` into an already-created service. */
RAC_API rac_result_t rac_image_embedding_initialize(rac_handle_t handle, const char* model_path);

/**
 * Embed one decoded image.
 *
 * `out_result` is released with `rac_embeddings_result_free` -- the text path's function, because
 * this is the text path's result type.
 */
RAC_API rac_result_t rac_image_embedding_embed(rac_handle_t handle,
                                               const rac_image_embedding_input_t* image,
                                               rac_embeddings_result_t* out_result);

/** Report readiness, vector width and the loaded model id. */
RAC_API rac_result_t rac_image_embedding_get_info(rac_handle_t handle,
                                                  rac_embeddings_info_t* out_info);

/** Release backend resources but keep the handle usable for a later initialize(). */
RAC_API rac_result_t rac_image_embedding_cleanup(rac_handle_t handle);

/** Destroy the service and free the handle. */
RAC_API void rac_image_embedding_destroy(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_IMAGE_EMBEDDING_SERVICE_H */
