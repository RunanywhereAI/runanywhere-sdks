/**
 * @file rac_diarization_stream.h
 * @brief Persistent proto-byte speaker-diarization stream sessions.
 *
 * Mirrors the STT lifetime contract: one callback registration per component
 * handle, start returns an opaque session id, feed accepts raw PCM chunks,
 * stop drains/finalizes, and cancel suppresses later events before teardown.
 */

#ifndef RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_STREAM_H
#define RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_STREAM_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*rac_diarization_stream_proto_callback_fn)(const uint8_t* event_bytes,
                                                         size_t event_size, void* user_data);

RAC_API rac_result_t rac_diarization_set_stream_proto_callback(
    rac_handle_t handle, rac_diarization_stream_proto_callback_fn callback, void* user_data);
RAC_API rac_result_t rac_diarization_unset_stream_proto_callback(rac_handle_t handle);

/**
 * Wait until callback invocations already admitted on other threads return.
 * An external caller drains the admission epoch visible on entry. A callback
 * may call this re-entrantly; re-entrant drains wait only for earlier epochs
 * on other threads so two callbacks cannot deadlock by quiescing each other.
 */
RAC_API void rac_diarization_proto_quiesce(void);

RAC_API rac_result_t rac_diarization_stream_start_proto(
    rac_handle_t handle, const uint8_t* options_proto_bytes, size_t options_proto_size,
    uint64_t* out_session_id);
RAC_API rac_result_t rac_diarization_stream_feed_audio_proto(uint64_t session_id,
                                                             const uint8_t* audio_bytes,
                                                             size_t audio_size);
RAC_API rac_result_t rac_diarization_stream_stop_proto(uint64_t session_id);
RAC_API rac_result_t rac_diarization_stream_cancel_proto(uint64_t session_id);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_STREAM_H */
