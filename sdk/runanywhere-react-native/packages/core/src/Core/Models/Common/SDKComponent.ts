/**
 * SDKComponent.ts
 *
 * Represents all initializable components in the SDK
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Types/ComponentTypes.swift
 */

// Re-export from the central types location to avoid duplicate definitions
export { SDKComponent } from '../../../types/enums';
import { SDKComponent } from '../../../types/enums';

/**
 * Human-readable display name for a component
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Types/ComponentTypes.swift
 */
export function getComponentDisplayName(component: SDKComponent): string {
  switch (component) {
    case SDKComponent.LLM:
      return 'LLM';
    case SDKComponent.STT:
      return 'Speech-to-Text';
    case SDKComponent.TTS:
      return 'Text-to-Speech';
    case SDKComponent.VAD:
      return 'Voice Activity Detection';
    case SDKComponent.Embedding:
      return 'Embedding';
    case SDKComponent.SpeakerDiarization:
      return 'Speaker Diarization';
    case SDKComponent.VoiceAgent:
      return 'Voice Agent';
  }
}

/**
 * Whether this component requires model download
 */
export function componentRequiresModel(component: SDKComponent): boolean {
  switch (component) {
    case SDKComponent.LLM:
    case SDKComponent.STT:
    case SDKComponent.Embedding:
      return true;
    case SDKComponent.TTS:
    case SDKComponent.VAD:
    case SDKComponent.SpeakerDiarization:
    case SDKComponent.VoiceAgent:
      return false;
  }
}

/**
 * Get all SDK components
 */
export function getAllSDKComponents(): SDKComponent[] {
  return Object.values(SDKComponent);
}
