/**
 * @file rac_speaker_diarization.cpp
 * @brief Speaker Diarization C ABI stub implementations (§8).
 *
 * All functions return RAC_ERROR_FEATURE_NOT_AVAILABLE until the diarization
 * model is integrated.  This prevents UnsatisfiedLinkError / undefined-symbol
 * crashes on all SDK frontends that link against runanywhere-commons.
 */

#include "rac/features/speaker_diarization/rac_speaker_diarization.h"

#include "rac/core/rac_logger.h"

extern "C" {

rac_result_t rac_speaker_diarization_init(const char* /*model_path*/,
                                          rac_speaker_diarization_t** out_handle) {
    RAC_LOG_WARNING("SpeakerDiarization",
                    "rac_speaker_diarization_init: feature not yet available");
    if (out_handle) *out_handle = nullptr;
    // TODO(diarization): integrate diarization model and replace this stub.
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

rac_result_t rac_speaker_diarization_process(rac_speaker_diarization_t* /*handle*/,
                                             const float* /*samples*/, size_t /*count*/,
                                             char** out_json) {
    RAC_LOG_WARNING("SpeakerDiarization",
                    "rac_speaker_diarization_process: feature not yet available");
    if (out_json) *out_json = nullptr;
    // TODO(diarization): implement when model is integrated.
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

void rac_speaker_diarization_destroy(rac_speaker_diarization_t* /*handle*/) {
    // No-op stub; nothing to free.
    // TODO(diarization): free session resources when implemented.
}

}  // extern "C"
