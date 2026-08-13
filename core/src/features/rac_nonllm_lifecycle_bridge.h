#ifndef RAC_FEATURES_RAC_NONLLM_LIFECYCLE_BRIDGE_H
#define RAC_FEATURES_RAC_NONLLM_LIFECYCLE_BRIDGE_H

#include "rac/core/rac_error.h"
#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"

namespace rac::lifecycle {

struct LifecycleSttRef {
    const rac_stt_service_ops_t* ops = nullptr;
    void* impl = nullptr;
    const char* model_id = nullptr;
    const char* framework_name = nullptr;
    void* opaque = nullptr;
};

struct LifecycleTtsRef {
    const rac_tts_service_ops_t* ops = nullptr;
    void* impl = nullptr;
    const char* model_id = nullptr;
    const char* framework_name = nullptr;
    void* opaque = nullptr;
};

struct LifecycleVadRef {
    const rac_vad_service_ops_t* ops = nullptr;
    void* impl = nullptr;
    const char* model_id = nullptr;
    const char* framework_name = nullptr;
    void* opaque = nullptr;
};

struct LifecycleEmbeddingsRef {
    const rac_embeddings_service_ops_t* ops = nullptr;
    void* impl = nullptr;
    const char* model_id = nullptr;
    const char* framework_name = nullptr;
    void* opaque = nullptr;
};

struct LifecycleDiffusionRef {
    const rac_diffusion_service_ops_t* ops = nullptr;
    void* impl = nullptr;
    const char* model_id = nullptr;
    const char* framework_name = nullptr;
    void* opaque = nullptr;
};

struct LifecycleDiarizationRef {
    const rac_diarization_service_ops_t* ops = nullptr;
    void* impl = nullptr;
    const char* model_id = nullptr;
    const char* framework_name = nullptr;
    void* opaque = nullptr;
};

struct LifecycleSegmentationRef {
    const rac_segmentation_service_ops_t* ops = nullptr;
    void* impl = nullptr;
    const char* model_id = nullptr;
    const char* framework_name = nullptr;
    void* opaque = nullptr;
};

rac_result_t acquire_lifecycle_stt(LifecycleSttRef* out_ref);
void release_lifecycle_stt(LifecycleSttRef* ref);

rac_result_t acquire_lifecycle_tts(LifecycleTtsRef* out_ref);
void release_lifecycle_tts(LifecycleTtsRef* ref);

rac_result_t acquire_lifecycle_vad(LifecycleVadRef* out_ref);
void release_lifecycle_vad(LifecycleVadRef* ref);

rac_result_t acquire_lifecycle_embeddings(LifecycleEmbeddingsRef* out_ref);
void release_lifecycle_embeddings(LifecycleEmbeddingsRef* ref);

rac_result_t acquire_lifecycle_diffusion(LifecycleDiffusionRef* out_ref);
void release_lifecycle_diffusion(LifecycleDiffusionRef* ref);

rac_result_t acquire_lifecycle_diarization(LifecycleDiarizationRef* out_ref);
void release_lifecycle_diarization(LifecycleDiarizationRef* ref);

rac_result_t acquire_lifecycle_segmentation(LifecycleSegmentationRef* out_ref);
void release_lifecycle_segmentation(LifecycleSegmentationRef* ref);


/**
 * @brief Whether commons currently holds @p model_id loaded on any component.
 *
 * Answers from the lifecycle store, so it is true wherever commons performed
 * the load regardless of what a host reports through
 * rac_storage_callbacks_t::is_model_loaded. Callers that must not act while a
 * model is open should treat `true` as authoritative; `false` only means
 * commons did not load it, and a host that loads outside commons may still
 * have it open.
 */
bool is_model_loaded(const char* model_id);

/**
 * @brief Unload @p model_id from the lifecycle store, if commons holds it.
 *
 * The companion to is_model_loaded(): a caller that must clear a model before
 * acting on its files can do so without a host callback, because commons is
 * what performed the load. Returns RAC_ERROR_MODEL_NOT_LOADED when no lifecycle
 * entry matched, so `is_model_loaded() == false` and this returning
 * MODEL_NOT_LOADED agree.
 *
 * That agreement holds only where RAC_HAVE_PROTOBUF is defined. Without it the
 * lifecycle store is unavailable, so is_model_loaded() still reports false but
 * this returns RAC_ERROR_FEATURE_NOT_AVAILABLE rather than
 * MODEL_NOT_LOADED. Callers that branch on the specific code must handle both.
 *
 * MUST NOT be called while holding the lifecycle mutex: the backend teardown it
 * drives reacquires that mutex to drain active refs, and it publishes component
 * lifecycle events whose subscribers may re-enter lifecycle APIs.
 */
rac_result_t unload_model(const char* model_id);

}  // namespace rac::lifecycle

#endif  // RAC_FEATURES_RAC_NONLLM_LIFECYCLE_BRIDGE_H
