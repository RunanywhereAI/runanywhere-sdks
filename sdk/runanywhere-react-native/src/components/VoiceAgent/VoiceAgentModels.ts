/**
 * VoiceAgentModels.ts
 *
 * Input/Output models for Voice Agent component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/VoiceAgent/VoiceAgentComponent.swift
 */

/**
 * Result from voice agent processing
 */
export interface VoiceAgentResult {
  speechDetected: boolean;
  transcription: string | null;
  response: string | null;
  synthesizedAudio: Buffer | Uint8Array | null;
}

/**
 * Events emitted by the voice agent
 */
export enum VoiceAgentEvent {
  Processed = 'processed',
  VADTriggered = 'vadTriggered',
  TranscriptionAvailable = 'transcriptionAvailable',
  ResponseGenerated = 'responseGenerated',
  AudioSynthesized = 'audioSynthesized',
  Error = 'error',
}

