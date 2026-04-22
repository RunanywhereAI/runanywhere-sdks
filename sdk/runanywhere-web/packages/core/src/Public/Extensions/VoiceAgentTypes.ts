/** RunAnywhere Web SDK - VoiceAgent Types */

export enum PipelineState {
  Idle = 'idle',
  Listening = 'listening',
  ProcessingSTT = 'processingSTT',
  GeneratingResponse = 'generatingResponse',
  PlayingTTS = 'playingTTS',
  Cooldown = 'cooldown',
  Error = 'error',
}

export interface VoiceAgentModels {
  stt?: { path: string; id: string; name?: string };
  llm?: { path: string; id: string; name?: string };
  tts?: { path: string; id: string; name?: string };
}

export interface VoiceTurnResult {
  speechDetected: boolean;
  transcription?: string;
  response?: string;
  synthesizedAudio?: Float32Array;
}

/**
 * Ad-hoc voice agent event data used by the Web SDK's callback-based
 * voice agent surface.
 *
 * **v2.1-1 note (GAP 09 #6)**: The Web SDK never had a hand-written
 * `VoiceSessionEvent` parallel to the other 4 SDKs — the criterion
 * "zero hand-written VoiceSessionEvent types" is trivially satisfied
 * here. This `VoiceAgentEventData` is a *different* shape (5-variant
 * discriminated union with optional-field bags) that predates GAP 09.
 *
 * New code should use the canonical `VoiceEvent` proto via the Web
 * `VoiceAgentStreamAdapter.stream()` (ts-proto codegen from
 * `idl/voice_events.proto`). See `docs/migrations/VoiceSessionEvent.md`
 * for the cross-SDK migration context.
 *
 * @deprecated v2.1-1: Use the codegen'd `VoiceEvent` proto via
 *   `VoiceAgentStreamAdapter.stream()`.
 */
export interface VoiceAgentEventData {
  type: 'transcription' | 'response' | 'audioSynthesized' | 'vadTriggered' | 'error';
  text?: string;
  audioData?: Float32Array;
  speechActive?: boolean;
  errorCode?: number;
}

export type VoiceAgentEventCallback = (event: VoiceAgentEventData) => void;
