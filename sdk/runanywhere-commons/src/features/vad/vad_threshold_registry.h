/**
 * @file vad_threshold_registry.h
 * @brief Internal per-handle mutex registry serializing VAD energy-threshold
 *        get/set/process/restore windows.
 *
 * NOT part of the public C ABI; only `vad_component.cpp` and
 * `rac_vad_stream.cpp` may include this header.
 *
 * Rationale (commons-features-voice-001 / pass3-syn-088): both the one-shot
 * `rac_vad_component_process_proto` path and the streaming
 * `rac_vad_stream_feed_audio_proto` path implement a get→set(override)→
 * process→restore sequence on the same VAD component handle. Without a
 * shared per-handle mutex, two threads on the same handle (one one-shot,
 * one streaming, or two of either) can interleave their set/restore calls,
 * leaving the persistent energy-threshold drifted to a stale value.
 *
 * The mutex is owned via shared_ptr so callers can release the registry
 * mutex before locking the per-handle mutex (we must not call into the VAD
 * component while holding the registry mutex, which is also taken by the
 * dispatch path); shared_ptr keeps the mutex alive across that gap even
 * if a teardown thread erases the map entry concurrently.
 *
 * commons-features-voice-006: `erase_threshold_mutex` is called from
 * `rac_vad_component_destroy` so the map does not grow unbounded across the
 * lifetime of the process.
 */

#ifndef RAC_FEATURES_VAD_VAD_THRESHOLD_REGISTRY_H
#define RAC_FEATURES_VAD_VAD_THRESHOLD_REGISTRY_H

#include <memory>
#include <mutex>

#include "rac/core/rac_types.h"

namespace rac::vad {

/**
 * @brief Return a shared per-handle mutex, creating one on first call.
 *
 * Thread-safe; safe to call concurrently with `erase_threshold_mutex`.
 */
std::shared_ptr<std::mutex> get_or_create_threshold_mutex(rac_handle_t handle);

/**
 * @brief Drop the registry's reference to the per-handle mutex for @p handle.
 *
 * Any threads still holding a shared_ptr keep the mutex alive until they
 * release it. Idempotent; no-op when no mutex was registered.
 */
void erase_threshold_mutex(rac_handle_t handle);

}  // namespace rac::vad

#endif  // RAC_FEATURES_VAD_VAD_THRESHOLD_REGISTRY_H
