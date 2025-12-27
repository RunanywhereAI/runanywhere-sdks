/**
 * ResourceTypes.ts
 *
 * Resource types for capabilities.
 * Lifecycle events are tracked directly via EventPublisher in ManagedLifecycle.
 *
 * Matches iOS: Core/Capabilities/Analytics/ResourceTypes.swift
 */

// ============================================================================
// Resource Types
// ============================================================================

/**
 * Types of resources that can be loaded by capabilities.
 * Matches iOS CapabilityResourceType enum.
 */
export enum CapabilityResourceType {
  LLMModel = 'llm_model',
  STTModel = 'stt_model',
  TTSVoice = 'tts_voice',
  VADModel = 'vad_model',
  DiarizationModel = 'diarization_model',
}

/**
 * Get the display name for a resource type
 */
export function getResourceTypeDisplayName(
  type: CapabilityResourceType
): string {
  switch (type) {
    case CapabilityResourceType.LLMModel:
      return 'LLM Model';
    case CapabilityResourceType.STTModel:
      return 'STT Model';
    case CapabilityResourceType.TTSVoice:
      return 'TTS Voice';
    case CapabilityResourceType.VADModel:
      return 'VAD Model';
    case CapabilityResourceType.DiarizationModel:
      return 'Diarization Model';
    default:
      return 'Unknown Resource';
  }
}
