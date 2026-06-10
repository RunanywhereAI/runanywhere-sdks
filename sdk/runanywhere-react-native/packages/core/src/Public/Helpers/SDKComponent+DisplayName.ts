/**
 * SDKComponent+DisplayName.ts
 *
 * Human-readable display name for the proto-generated `SDKComponent` enum.
 *
 * Mirrors Swift `RASDKComponent+DisplayName.swift`.
 */

import { SDKComponent } from '@runanywhere/proto-ts/sdk_events';

/**
 * Return the canonical display name for an `SDKComponent`.
 * Mirrors Swift `RASDKComponent.displayName`.
 */
export function sdkComponentDisplayName(component: SDKComponent): string {
  switch (component) {
    case SDKComponent.SDK_COMPONENT_LLM:
      return 'Language Model';
    case SDKComponent.SDK_COMPONENT_VLM:
      return 'Vision Language Model';
    case SDKComponent.SDK_COMPONENT_STT:
      return 'Speech to Text';
    case SDKComponent.SDK_COMPONENT_TTS:
      return 'Text to Speech';
    case SDKComponent.SDK_COMPONENT_VAD:
      return 'Voice Activity Detection';
    case SDKComponent.SDK_COMPONENT_VOICE_AGENT:
      return 'Voice Agent';
    case SDKComponent.SDK_COMPONENT_EMBEDDINGS:
      return 'Embedding';
    case SDKComponent.SDK_COMPONENT_DIFFUSION:
      return 'Image Generation';
    case SDKComponent.SDK_COMPONENT_RAG:
      return 'Retrieval-Augmented Generation';
    case SDKComponent.SDK_COMPONENT_WAKEWORD:
      return 'Wake Word';
    case SDKComponent.SDK_COMPONENT_SPEAKER_DIARIZATION:
      return 'Speaker Diarization';
    default:
      return 'Unknown';
  }
}
