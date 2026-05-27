/**
 * @file voice_agent_audio_pipeline_state.cpp
 * @brief Audio pipeline state machine helpers ported from Swift's
 *        AudioPipelineState.swift. No dependency on a `rac_voice_agent`
 *        handle — pure utility functions invoked by frontends to decide
 *        whether the mic can be turned on or TTS can be played given the
 *        current pipeline phase.
 *
 * Split out of voice_agent.cpp under commons-features-voice-003.
 */

#include "rac/core/rac_platform_adapter.h"
#include "rac/features/voice_agent/rac_voice_agent.h"

const char* rac_audio_pipeline_state_name(rac_audio_pipeline_state_t state) {
    switch (state) {
        case RAC_AUDIO_PIPELINE_IDLE:
            return "idle";
        case RAC_AUDIO_PIPELINE_LISTENING:
            return "listening";
        case RAC_AUDIO_PIPELINE_PROCESSING_SPEECH:
            return "processingSpeech";
        case RAC_AUDIO_PIPELINE_GENERATING_RESPONSE:
            return "generatingResponse";
        case RAC_AUDIO_PIPELINE_PLAYING_TTS:
            return "playingTTS";
        case RAC_AUDIO_PIPELINE_COOLDOWN:
            return "cooldown";
        case RAC_AUDIO_PIPELINE_ERROR:
            return "error";
        default:
            return "unknown";
    }
}

rac_bool_t rac_audio_pipeline_can_activate_microphone(rac_audio_pipeline_state_t current_state,
                                                      int64_t last_tts_end_time_ms,
                                                      int64_t cooldown_duration_ms) {
    switch (current_state) {
        case RAC_AUDIO_PIPELINE_IDLE:
        case RAC_AUDIO_PIPELINE_LISTENING:
            if (last_tts_end_time_ms > 0) {
                int64_t now_ms = rac_get_current_time_ms();
                int64_t elapsed_ms = now_ms - last_tts_end_time_ms;
                if (elapsed_ms < cooldown_duration_ms) {
                    return RAC_FALSE;
                }
            }
            return RAC_TRUE;

        case RAC_AUDIO_PIPELINE_PROCESSING_SPEECH:
        case RAC_AUDIO_PIPELINE_GENERATING_RESPONSE:
        case RAC_AUDIO_PIPELINE_PLAYING_TTS:
        case RAC_AUDIO_PIPELINE_COOLDOWN:
        case RAC_AUDIO_PIPELINE_ERROR:
            return RAC_FALSE;

        default:
            return RAC_FALSE;
    }
}

rac_bool_t rac_audio_pipeline_can_play_tts(rac_audio_pipeline_state_t current_state) {
    return (current_state == RAC_AUDIO_PIPELINE_GENERATING_RESPONSE) ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t rac_audio_pipeline_is_valid_transition(rac_audio_pipeline_state_t from_state,
                                                  rac_audio_pipeline_state_t to_state) {
    if (to_state == RAC_AUDIO_PIPELINE_ERROR) {
        return RAC_TRUE;
    }

    switch (from_state) {
        case RAC_AUDIO_PIPELINE_IDLE:
            return (to_state == RAC_AUDIO_PIPELINE_LISTENING ||
                    to_state == RAC_AUDIO_PIPELINE_COOLDOWN)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_LISTENING:
            return (to_state == RAC_AUDIO_PIPELINE_IDLE ||
                    to_state == RAC_AUDIO_PIPELINE_PROCESSING_SPEECH)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_PROCESSING_SPEECH:
            return (to_state == RAC_AUDIO_PIPELINE_IDLE ||
                    to_state == RAC_AUDIO_PIPELINE_GENERATING_RESPONSE ||
                    to_state == RAC_AUDIO_PIPELINE_LISTENING)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_GENERATING_RESPONSE:
            return (to_state == RAC_AUDIO_PIPELINE_PLAYING_TTS ||
                    to_state == RAC_AUDIO_PIPELINE_IDLE || to_state == RAC_AUDIO_PIPELINE_COOLDOWN)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_PLAYING_TTS:
            return (to_state == RAC_AUDIO_PIPELINE_COOLDOWN || to_state == RAC_AUDIO_PIPELINE_IDLE)
                       ? RAC_TRUE
                       : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_COOLDOWN:
            return (to_state == RAC_AUDIO_PIPELINE_IDLE) ? RAC_TRUE : RAC_FALSE;

        case RAC_AUDIO_PIPELINE_ERROR:
            return (to_state == RAC_AUDIO_PIPELINE_IDLE) ? RAC_TRUE : RAC_FALSE;

        default:
            return RAC_FALSE;
    }
}
