/**
 * @file voice_agent.cpp
 * @brief RunAnywhere Commons - Voice Agent core lifecycle entry points.
 *
 * C++ port of Swift's VoiceAgentCapability.swift from
 * Sources/RunAnywhere/Features/VoiceAgent/VoiceAgentCapability.swift.
 *
 * CRITICAL: This is a direct port of the Swift implementation - do NOT add
 * custom logic.
 *
 * SRP split: the legacy 2,291-LoC monolith was
 * decomposed into per-ABI translation units:
 *   - voice_agent.cpp                          — lifecycle (create/destroy)
 *                                                + synchronous initialize +
 *                                                cleanup
 *   - voice_agent_legacy_abi.cpp               — legacy non-proto C ABI
 *                                                (model loading + voice
 *                                                turn/stream + individual
 *                                                helpers + result-free)
 *   - voice_agent_proto_abi.cpp                — synchronous proto C ABI
 *   - voice_agent_d7_abi.cpp                   — full-session
 *                                                proto ABI
 *   - voice_agent_audio_pipeline_state.cpp     — audio pipeline state
 *                                                machine helpers
 *   - voice_agent_internal_helpers.{h,cpp}     — shared emit / state /
 *                                                proto-byte helpers
 *   - voice_agent_pipeline.cpp / .hpp          — graph
 *                                                pipeline
 *
 * Public C ABI is unchanged across the split. The `rac_voice_agent` struct
 * definition lives in `voice_agent_internal.h`.
 *
 * Lifecycle-acquire pattern:
 *
 *   All proto-byte entry points (`rac_voice_agent_*_proto`) MUST resolve
 *   modality state via `acquire_lifecycle_{stt,tts,vad,llm}` instead of
 *   dereferencing `handle->{stt,llm,tts,vad}_handle`. The per-component
 *   handles stored on the agent are owned by the Swift bridge actor and
 *   are NOT the same as the level-1 (impl + ops) entries that
 *   `rac_model_lifecycle_load_proto` populates. Mirrors the precedent
 *   established in `rac_vlm_process_proto` where the
 *   component-handle pointer arithmetic produced an EXC_BAD_ACCESS on
 *   iPhone 17 Pro Max.
 *
 *   Legacy non-proto entry points (`rac_voice_agent_process_voice_turn`,
 *   `rac_voice_agent_process_stream`, individual `transcribe`/
 *   `generate_response`/`synthesize_speech`/`detect_speech` helpers) keep
 *   using `handle->*_handle` for backward compatibility — those entry
 *   points live in voice_agent_legacy_abi.cpp and are marked
 *   `[[deprecated]]` via `RAC_VOICE_AGENT_LEGACY_DEPRECATED` so external
 *   callers (Playground/linux-voice, commons tests) surface as
 *   `-Wdeprecated-declarations` warnings.
 */

#include "voice_agent_internal.h"

#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <thread>

#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"
#include "voice_agent_pipeline.hpp"

// =============================================================================
// LIFECYCLE API
// =============================================================================

rac_result_t rac_voice_agent_create_standalone(rac_voice_agent_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    RAC_LOG_INFO("VoiceAgent", "Creating standalone voice agent");

    rac_voice_agent* agent = new (std::nothrow) rac_voice_agent();
    if (!agent) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    agent->owns_components = true;

    rac_result_t result = rac_llm_component_create(&agent->llm_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Failed to create LLM component");
        delete agent;
        return result;
    }

    result = rac_stt_component_create(&agent->stt_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Failed to create STT component");
        rac_llm_component_destroy(agent->llm_handle);
        delete agent;
        return result;
    }

    result = rac_tts_component_create(&agent->tts_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Failed to create TTS component");
        rac_stt_component_destroy(agent->stt_handle);
        rac_llm_component_destroy(agent->llm_handle);
        delete agent;
        return result;
    }

    result = rac_vad_component_create(&agent->vad_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "Failed to create VAD component");
        rac_tts_component_destroy(agent->tts_handle);
        rac_stt_component_destroy(agent->stt_handle);
        rac_llm_component_destroy(agent->llm_handle);
        delete agent;
        return result;
    }

    RAC_LOG_INFO("VoiceAgent", "Standalone voice agent created with all components");

    *out_handle = agent;
    return RAC_SUCCESS;
}

// DEPRECATED. Prefer `rac_voice_agent_create_standalone()` plus
// `rac_model_lifecycle_load_proto(...)` for each modality. The 4-handle
// API is retained for the iOS Swift bridge, which still constructs its
// per-modality component handles inside actors and threads them through
// here. Proto entry points
// dispatch through the global lifecycle and ignore these stored handles
// entirely; only the legacy non-proto entry points still dereference
// them for backward compatibility. Removal is gated on the Swift
// migration.
rac_result_t rac_voice_agent_create(rac_handle_t llm_component_handle,
                                    rac_handle_t stt_component_handle,
                                    rac_handle_t tts_component_handle,
                                    rac_handle_t vad_component_handle,
                                    rac_voice_agent_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // All component handles are required (mirrors Swift's init)
    if (!llm_component_handle || !stt_component_handle || !tts_component_handle ||
        !vad_component_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    rac_voice_agent* agent = new (std::nothrow) rac_voice_agent();
    if (!agent) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    agent->owns_components = false;  // External handles, don't destroy them
    // Stored for legacy non-proto entry points only. Proto path resolves
    // ops via `acquire_lifecycle_*` and never touches these fields.
    agent->llm_handle = llm_component_handle;
    agent->stt_handle = stt_component_handle;
    agent->tts_handle = tts_component_handle;
    agent->vad_handle = vad_component_handle;

    RAC_LOG_INFO("VoiceAgent", "Voice agent created with external handles (legacy compose API)");

    *out_handle = agent;
    return RAC_SUCCESS;
}

void rac_voice_agent_destroy(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return;
    }

    // Signal shutdown and wait for all in-flight operations (including lock-free ones)
    handle->is_shutting_down.store(true, std::memory_order_release);
    handle->is_configured.store(false, std::memory_order_release);

    // Propagate cancel to any GraphScheduler-driven
    // pipeline run currently in flight.
    // Snapshot the shared_ptr under handle->pipeline_mutex (held only
    // while copying the control block) so we never race the
    // process_stream store/reset, then call cancel() OUTSIDE the lock.
    // The pipeline's cancel_all() is non-blocking and idempotent, so
    // racing destroy() against an in-flight run is safe once the
    // shared_ptr copy is established without UB.
    //
    // A second "late_snapshot" re-cancel
    // pass once we acquire the outer mutex would only fire if a
    // concurrent process_stream stored a fresh pipeline AFTER our pre-
    // mutex snapshot ran. process_stream holds handle->mutex from the
    // moment it stores `handle->pipeline = pipeline` through `reset()`
    // on the way out, so by the time we acquire the outer mutex below
    // any such concurrent run has already drained and reset the
    // pipeline back to null. The previously-emitted late-snapshot
    // branch was unreachable; removed to keep the teardown path
    // straightforward.
    std::shared_ptr<rac::voice_agent::VoiceAgentPipeline> pipeline_snapshot;
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        pipeline_snapshot = handle->pipeline;
    }
    if (pipeline_snapshot) {
        pipeline_snapshot->cancel();
    }

    // Wait for in-flight lock-free ops (e.g. detect_speech)
    // to drain. Sleep 1ms between checks rather than yield-spinning: on a
    // multi-second LLM call holding the counter the yield form burns 100%
    // CPU on the destroying thread (measurable battery/thermal hit on
    // mobile), and on QoS-scheduled iOS threads the yielder can starve
    // the worker holding the counter.
    while (handle->in_flight.load(std::memory_order_acquire) > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    // Invoke cleanup() before tearing down components so the
    // VAD's worker thread and the per-component lifecycle state are
    // explicitly stopped/reset (symmetric with rac_voice_agent_cleanup).
    // Done OUTSIDE handle->mutex because cleanup() acquires the same
    // non-recursive mutex; the component_destroy calls below run under
    // the mutex as before. is_shutting_down is already true, so any
    // future entry-point call that races us will fail-fast.
    (void)rac_voice_agent_cleanup(handle);

    {
        std::lock_guard<std::mutex> lock(handle->mutex);

        // Drop the pipeline before component handles so its nodes (which
        // call into stt/llm/tts/vad) cannot outlive the handles they use.
        {
            std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
            handle->pipeline.reset();
        }

        if (handle->owns_components) {
            RAC_LOG_DEBUG("VoiceAgent", "Destroying owned component handles");
            if (handle->vad_handle)
                rac_vad_component_destroy(handle->vad_handle);
            if (handle->tts_handle)
                rac_tts_component_destroy(handle->tts_handle);
            if (handle->stt_handle)
                rac_stt_component_destroy(handle->stt_handle);
            if (handle->llm_handle)
                rac_llm_component_destroy(handle->llm_handle);
        }
    }

    // Clear any lingering proto-stream
    // callback registration keyed by this voice-agent handle BEFORE freeing
    // the memory. Without this, heap-pointer reuse on the next
    // rac_voice_agent_create() inherits a stale CallbackSlot { fn, user_data,
    // seq } from the previous session, corrupting the wire-seq sequence on
    // the very first VoiceEvent dispatch.
    rac_voice_agent_set_proto_callback(handle, nullptr, nullptr);
    // Spin-wait until every in-flight
    // dispatch_proto_event/dispatch_proto_voice_event invocation on another
    // thread has returned before freeing the handle memory. Without this,
    // a thread that copied the CallbackSlot before the unset above can
    // still be inside slot.fn() with a now-stale `handle`-derived
    // user_data pointer when the caller frees it.
    rac_voice_agent_proto_quiesce();

    // All threads that held/waited on mutex have now exited
    delete handle;
    RAC_LOG_DEBUG("VoiceAgent", "Voice agent destroyed");
}

rac_result_t rac_voice_agent_initialize(rac_voice_agent_handle_t handle,
                                        const rac_voice_agent_config_t* config) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Initializing Voice Agent");

    const rac_voice_agent_config_t* cfg = config ? config : &RAC_VOICE_AGENT_CONFIG_DEFAULT;

    // Step 1: Initialize VAD (mirrors Swift's initializeVAD)
    rac_result_t result = rac_vad_component_initialize(handle->vad_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "VAD component failed to initialize");
        return result;
    }

    // Step 2: Initialize STT model (mirrors Swift's initializeSTTModel)
    if (cfg->stt_config.model_path && strlen(cfg->stt_config.model_path) > 0) {
        RAC_LOG_INFO("VoiceAgent", "Loading STT model");
        result = rac_stt_component_load_model(handle->stt_handle, cfg->stt_config.model_path,
                                              cfg->stt_config.model_id, cfg->stt_config.model_name);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "STT component failed to initialize");
            return result;
        }
    }

    // Step 3: Initialize LLM model (mirrors Swift's initializeLLMModel)
    if (cfg->llm_config.model_path && strlen(cfg->llm_config.model_path) > 0) {
        RAC_LOG_INFO("VoiceAgent", "Loading LLM model");
        result = rac_llm_component_load_model(handle->llm_handle, cfg->llm_config.model_path,
                                              cfg->llm_config.model_id, cfg->llm_config.model_name);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "LLM component failed to initialize");
            return result;
        }
    }

    // Step 4: Initialize TTS (mirrors Swift's initializeTTSVoice)
    if (cfg->tts_config.voice_path && strlen(cfg->tts_config.voice_path) > 0) {
        RAC_LOG_INFO("VoiceAgent", "Initializing TTS");
        result = rac_tts_component_load_voice(handle->tts_handle, cfg->tts_config.voice_path,
                                              cfg->tts_config.voice_id, cfg->tts_config.voice_name);
        if (result != RAC_SUCCESS) {
            RAC_LOG_ERROR("VoiceAgent", "TTS component failed to initialize");
            return result;
        }
    }

    handle->is_configured.store(true, std::memory_order_release);
    RAC_LOG_INFO("VoiceAgent", "Voice Agent initialized successfully");

    return RAC_SUCCESS;
}

rac_result_t rac_voice_agent_cleanup(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Cancel any in-flight pipeline BEFORE taking the
    // outer mutex; the pipeline run holds the same mutex while it drains
    // and cancel_all() is the only way out of a stalled stage.
    // Snapshot under pipeline_mutex so the
    // shared_ptr copy is synchronized with process_stream's store/reset.
    //
    // process_stream holds handle->mutex for
    // the entire store->run->reset window. By the time we acquire the
    // outer mutex below, any concurrent run has drained and reset
    // handle->pipeline to null, so the previously-emitted late-snapshot
    // re-cancel branch was unreachable; removed for clarity.
    std::shared_ptr<rac::voice_agent::VoiceAgentPipeline> pipeline_snapshot;
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        pipeline_snapshot = handle->pipeline;
    }
    if (pipeline_snapshot) {
        pipeline_snapshot->cancel();
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Cleaning up Voice Agent");

    // Tear the pipeline down before the underlying components so its
    // worker threads cannot dispatch into stt/llm/tts/vad after cleanup.
    {
        std::lock_guard<std::mutex> pipeline_lock(handle->pipeline_mutex);
        handle->pipeline.reset();
    }

    // Cleanup all components (mirrors Swift's cleanup)
    rac_llm_component_cleanup(handle->llm_handle);
    rac_stt_component_cleanup(handle->stt_handle);
    rac_tts_component_cleanup(handle->tts_handle);
    // VAD uses stop + reset instead of cleanup
    rac_vad_component_stop(handle->vad_handle);
    rac_vad_component_reset(handle->vad_handle);

    handle->is_configured.store(false, std::memory_order_release);

    return RAC_SUCCESS;
}
