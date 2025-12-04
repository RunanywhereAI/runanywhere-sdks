/**
 * SDKComponent.ts
 *
 * Represents all initializable components in the SDK
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/ComponentTypes.swift
 */

// Re-export from the central types location to avoid duplicate definitions
export { SDKComponent } from '../../../types/enums';
import { SDKComponent } from '../../../types/enums';

/**
 * Human-readable display name for a component
 */
export function getComponentDisplayName(component: SDKComponent): string {
  switch (component) {
    case SDKComponent.LLM:
      return 'Language Model';
    case SDKComponent.STT:
      return 'Speech-to-Text';
    case SDKComponent.TTS:
      return 'Text-to-Speech';
    case SDKComponent.VAD:
      return 'Voice Activity Detection';
    case SDKComponent.VLM:
      return 'Vision Language Model';
    case SDKComponent.Embedding:
      return 'Embeddings';
    case SDKComponent.SpeakerDiarization:
      return 'Speaker Diarization';
    case SDKComponent.VoiceAgent:
      return 'Voice Agent';
    case SDKComponent.WakeWord:
      return 'Wake Word Detection';
  }
}

/**
 * Whether this component requires model download
 */
export function componentRequiresModel(component: SDKComponent): boolean {
  switch (component) {
    case SDKComponent.LLM:
    case SDKComponent.STT:
    case SDKComponent.VLM:
    case SDKComponent.Embedding:
      return true;
    case SDKComponent.TTS:
    case SDKComponent.VAD:
    case SDKComponent.SpeakerDiarization:
    case SDKComponent.VoiceAgent:
    case SDKComponent.WakeWord:
      return false;
  }
}

/**
 * Get all SDK components
 */
export function getAllSDKComponents(): SDKComponent[] {
  return Object.values(SDKComponent);
}
