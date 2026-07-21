#ifndef RAC_FEATURES_RAC_NONLLM_LIFECYCLE_BRIDGE_H
#define RAC_FEATURES_RAC_NONLLM_LIFECYCLE_BRIDGE_H

#include "rac/core/rac_error.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
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

}  // namespace rac::lifecycle

#endif  // RAC_FEATURES_RAC_NONLLM_LIFECYCLE_BRIDGE_H
