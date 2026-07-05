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
 * SRP split: the voice-agent feature is
 * decomposed into per-ABI translation units:
 *   - voice_agent.cpp                          — lifecycle (create/destroy)
 *                                                + synchronous initialize +
 *                                                cleanup
 *   - voice_agent_proto_abi.cpp                — synchronous proto C ABI
 *   - voice_agent_d7_abi.cpp                   — full-session
 *                                                proto ABI
 *   - voice_agent_audio_pipeline_state.cpp     — audio pipeline state
 *                                                machine helpers
 *   - voice_agent_internal_helpers.{h,cpp}     — shared emit / state /
 *                                                proto-byte helpers
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
 */

#include "voice_agent_internal.h"

#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <new>
#include <thread>

#include "rac/core/rac_logger.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"

// LIFECYCLE API

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
    // dispatch_proto_voice_event invocation on another
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

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("VoiceAgent", "Cleaning up Voice Agent");

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

// Initialize the agent against components that are already loaded on the handle
// (the SDK loads STT/LLM/TTS, then flips the agent to ready). Moved here from
// the now-removed legacy ABI because Kotlin (JNI) and React Native call it.
rac_result_t rac_voice_agent_initialize_with_loaded_models(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::unique_lock<std::mutex> lock(handle->mutex);

    if (!handle->vad_handle) {
        RAC_LOG_ERROR("VoiceAgent",
                      "Cannot initialize with loaded models: no VAD component on the handle");
        return RAC_ERROR_INVALID_STATE;
    }

    RAC_LOG_INFO("VoiceAgent", "Initializing Voice Agent with already-loaded models");

    rac_result_t result = rac_vad_component_initialize(handle->vad_handle);
    if (result != RAC_SUCCESS) {
        RAC_LOG_ERROR("VoiceAgent", "VAD component failed to initialize");
        return result;
    }

    handle->is_configured.store(true, std::memory_order_release);
    RAC_LOG_INFO("VoiceAgent", "Voice Agent initialized with pre-loaded models");

    return RAC_SUCCESS;
}

// Whether the agent has been configured/initialized. Moved here from the legacy
// ABI (Kotlin/RN call it); just reflects the handle's configured flag.
rac_result_t rac_voice_agent_is_ready(rac_voice_agent_handle_t handle, rac_bool_t* out_is_ready) {
    if (!handle || !out_is_ready) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_is_ready = handle->is_configured.load(std::memory_order_acquire) ? RAC_TRUE : RAC_FALSE;
    return RAC_SUCCESS;
}

// LLM-only text→text helper for the voice agent. Moved here from the legacy ABI
// because Flutter's `RunAnywhere.voice.generateResponse(_)` calls it; the
// composed handle's `llm_handle` is populated by create_standalone (the same
// handle the d7 full-session path generates against), so this is a thin wrapper
// over the LLM component — not part of the retired struct-event/pipeline surface.
rac_result_t rac_voice_agent_generate_response(rac_voice_agent_handle_t handle, const char* prompt,
                                               char** out_response) {
    if (!handle || !prompt || !out_response) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    if (!handle->is_configured.load(std::memory_order_acquire)) {
        return RAC_ERROR_NOT_INITIALIZED;
    }

    rac_llm_result_t llm_result = {};
    rac_result_t result =
        rac_llm_component_generate(handle->llm_handle, prompt, nullptr, &llm_result);

    if (result != RAC_SUCCESS) {
        return result;
    }

    *out_response = rac_strdup(llm_result.text);
    rac_llm_result_free(&llm_result);

    return RAC_SUCCESS;
}
