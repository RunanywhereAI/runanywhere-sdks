/**
 * LifecycleEvents.ts
 *
 * Capability-specific lifecycle events (load/unload) for LLM, STT, TTS.
 * These are tracked by ManagedLifecycle for automatic event emission.
 *
 * Matches iOS:
 * - Features/LLM/Analytics/LLMEvent.swift
 * - Features/STT/Analytics/STTEvent.swift
 * - Features/TTS/Analytics/TTSEvent.swift
 */

import type { SDKEvent } from '../../Infrastructure/Events/SDKEvent';
import {
  EventCategory,
  createSDKEvent,
} from '../../Infrastructure/Events/SDKEvent';

// ============================================================================
// LLM Lifecycle Events
// ============================================================================

/**
 * LLM lifecycle event types
 */
export type LLMLifecycleEventType =
  | 'llm_model_load_started'
  | 'llm_model_load_completed'
  | 'llm_model_load_failed'
  | 'llm_model_unloaded';

/**
 * Create LLM model load started event.
 */
export function createLLMModelLoadStartedEvent(modelId: string): SDKEvent {
  return createSDKEvent('llm_model_load_started', EventCategory.LLM, {
    model_id: modelId,
  });
}

/**
 * Create LLM model load completed event.
 */
export function createLLMModelLoadCompletedEvent(
  modelId: string,
  durationMs: number
): SDKEvent {
  return createSDKEvent('llm_model_load_completed', EventCategory.LLM, {
    model_id: modelId,
    duration_ms: durationMs.toFixed(1),
  });
}

/**
 * Create LLM model load failed event.
 */
export function createLLMModelLoadFailedEvent(
  modelId: string,
  error: string
): SDKEvent {
  return createSDKEvent('llm_model_load_failed', EventCategory.LLM, {
    model_id: modelId,
    error,
  });
}

/**
 * Create LLM model unloaded event.
 */
export function createLLMModelUnloadedEvent(modelId: string): SDKEvent {
  return createSDKEvent('llm_model_unloaded', EventCategory.LLM, {
    model_id: modelId,
  });
}

// ============================================================================
// STT Lifecycle Events
// ============================================================================

/**
 * STT lifecycle event types
 */
export type STTLifecycleEventType =
  | 'stt_model_load_started'
  | 'stt_model_load_completed'
  | 'stt_model_load_failed'
  | 'stt_model_unloaded';

/**
 * Create STT model load started event.
 */
export function createSTTModelLoadStartedEvent(modelId: string): SDKEvent {
  return createSDKEvent('stt_model_load_started', EventCategory.STT, {
    model_id: modelId,
  });
}

/**
 * Create STT model load completed event.
 */
export function createSTTModelLoadCompletedEvent(
  modelId: string,
  durationMs: number
): SDKEvent {
  return createSDKEvent('stt_model_load_completed', EventCategory.STT, {
    model_id: modelId,
    duration_ms: durationMs.toFixed(1),
  });
}

/**
 * Create STT model load failed event.
 */
export function createSTTModelLoadFailedEvent(
  modelId: string,
  error: string
): SDKEvent {
  return createSDKEvent('stt_model_load_failed', EventCategory.STT, {
    model_id: modelId,
    error,
  });
}

/**
 * Create STT model unloaded event.
 */
export function createSTTModelUnloadedEvent(modelId: string): SDKEvent {
  return createSDKEvent('stt_model_unloaded', EventCategory.STT, {
    model_id: modelId,
  });
}

// ============================================================================
// TTS Lifecycle Events
// ============================================================================

/**
 * TTS lifecycle event types
 */
export type TTSLifecycleEventType =
  | 'tts_model_load_started'
  | 'tts_model_load_completed'
  | 'tts_model_load_failed'
  | 'tts_model_unloaded';

/**
 * Create TTS model load started event.
 */
export function createTTSModelLoadStartedEvent(voiceId: string): SDKEvent {
  return createSDKEvent('tts_model_load_started', EventCategory.TTS, {
    voice_id: voiceId,
  });
}

/**
 * Create TTS model load completed event.
 */
export function createTTSModelLoadCompletedEvent(
  voiceId: string,
  durationMs: number
): SDKEvent {
  return createSDKEvent('tts_model_load_completed', EventCategory.TTS, {
    voice_id: voiceId,
    duration_ms: durationMs.toFixed(1),
  });
}

/**
 * Create TTS model load failed event.
 */
export function createTTSModelLoadFailedEvent(
  voiceId: string,
  error: string
): SDKEvent {
  return createSDKEvent('tts_model_load_failed', EventCategory.TTS, {
    voice_id: voiceId,
    error,
  });
}

/**
 * Create TTS model unloaded event.
 */
export function createTTSModelUnloadedEvent(voiceId: string): SDKEvent {
  return createSDKEvent('tts_model_unloaded', EventCategory.TTS, {
    voice_id: voiceId,
  });
}

// ============================================================================
// VAD Lifecycle Events
// ============================================================================

/**
 * VAD lifecycle event types
 */
export type VADLifecycleEventType =
  | 'vad_model_load_started'
  | 'vad_model_load_completed'
  | 'vad_model_load_failed'
  | 'vad_model_unloaded';

/**
 * Create VAD model load started event.
 */
export function createVADModelLoadStartedEvent(modelId: string): SDKEvent {
  return createSDKEvent('vad_model_load_started', EventCategory.Voice, {
    model_id: modelId,
  });
}

/**
 * Create VAD model load completed event.
 */
export function createVADModelLoadCompletedEvent(
  modelId: string,
  durationMs: number
): SDKEvent {
  return createSDKEvent('vad_model_load_completed', EventCategory.Voice, {
    model_id: modelId,
    duration_ms: durationMs.toFixed(1),
  });
}

/**
 * Create VAD model load failed event.
 */
export function createVADModelLoadFailedEvent(
  modelId: string,
  error: string
): SDKEvent {
  return createSDKEvent('vad_model_load_failed', EventCategory.Voice, {
    model_id: modelId,
    error,
  });
}

/**
 * Create VAD model unloaded event.
 */
export function createVADModelUnloadedEvent(modelId: string): SDKEvent {
  return createSDKEvent('vad_model_unloaded', EventCategory.Voice, {
    model_id: modelId,
  });
}

// ============================================================================
// SpeakerDiarization Lifecycle Events
// ============================================================================

/**
 * SpeakerDiarization lifecycle event types
 */
export type SpeakerDiarizationLifecycleEventType =
  | 'speaker_diarization_model_load_started'
  | 'speaker_diarization_model_load_completed'
  | 'speaker_diarization_model_load_failed'
  | 'speaker_diarization_model_unloaded';

/**
 * Create SpeakerDiarization model load started event.
 */
export function createSpeakerDiarizationModelLoadStartedEvent(
  modelId: string
): SDKEvent {
  return createSDKEvent(
    'speaker_diarization_model_load_started',
    EventCategory.Voice,
    {
      model_id: modelId,
    }
  );
}

/**
 * Create SpeakerDiarization model load completed event.
 */
export function createSpeakerDiarizationModelLoadCompletedEvent(
  modelId: string,
  durationMs: number
): SDKEvent {
  return createSDKEvent(
    'speaker_diarization_model_load_completed',
    EventCategory.Voice,
    {
      model_id: modelId,
      duration_ms: durationMs.toFixed(1),
    }
  );
}

/**
 * Create SpeakerDiarization model load failed event.
 */
export function createSpeakerDiarizationModelLoadFailedEvent(
  modelId: string,
  error: string
): SDKEvent {
  return createSDKEvent(
    'speaker_diarization_model_load_failed',
    EventCategory.Voice,
    {
      model_id: modelId,
      error,
    }
  );
}

/**
 * Create SpeakerDiarization model unloaded event.
 */
export function createSpeakerDiarizationModelUnloadedEvent(
  modelId: string
): SDKEvent {
  return createSDKEvent(
    'speaker_diarization_model_unloaded',
    EventCategory.Voice,
    {
      model_id: modelId,
    }
  );
}

// ============================================================================
// Combined Lifecycle Event Types
// ============================================================================

/**
 * All lifecycle event types.
 */
export type LifecycleEventType =
  | LLMLifecycleEventType
  | STTLifecycleEventType
  | TTSLifecycleEventType
  | VADLifecycleEventType
  | SpeakerDiarizationLifecycleEventType;
