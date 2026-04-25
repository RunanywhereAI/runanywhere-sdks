/**
 * RunAnywhere Web SDK — VoicePipeline state machine enum.
 *
 * App-level pipeline phase used by the TS-side `VoicePipeline`
 * orchestrator (STT -> LLM -> TTS). For the proto-stream
 * `VoiceAgentStreamAdapter` path, consumers should match on the proto
 * `PipelineState` exported from `@runanywhere/proto-ts/voice_events` (re-exported
 * from the package root as `VoiceEventPipelineState`).
 */

export enum PipelineState {
  Idle = 'idle',
  Listening = 'listening',
  ProcessingSTT = 'processingSTT',
  GeneratingResponse = 'generatingResponse',
  PlayingTTS = 'playingTTS',
  Cooldown = 'cooldown',
  Error = 'error',
}
