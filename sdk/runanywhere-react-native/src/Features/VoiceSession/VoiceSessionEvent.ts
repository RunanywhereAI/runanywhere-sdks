/**
 * VoiceSessionEvent.ts
 * RunAnywhere SDK
 *
 * Events emitted during a voice session.
 * Matches iOS: Public/Extensions/RunAnywhere+VoiceSession.swift
 */

/**
 * Events emitted during a voice session
 */
export type VoiceSessionEvent =
  | { type: 'started' }
  | { type: 'listening'; audioLevel: number }
  | { type: 'speechStarted' }
  | { type: 'processing' }
  | { type: 'transcribed'; text: string }
  | { type: 'responded'; text: string }
  | { type: 'speaking' }
  | {
      type: 'turnCompleted';
      transcript: string;
      response: string;
      audio?: ArrayBuffer;
    }
  | { type: 'stopped' }
  | { type: 'error'; message: string };

/**
 * Voice session event types enum for type checking
 */
export enum VoiceSessionEventType {
  /** Session started and ready */
  Started = 'started',
  /** Listening for speech with current audio level (0.0 - 1.0) */
  Listening = 'listening',
  /** Speech detected, started accumulating audio */
  SpeechStarted = 'speechStarted',
  /** Speech ended, processing audio */
  Processing = 'processing',
  /** Got transcription from STT */
  Transcribed = 'transcribed',
  /** Got response from LLM */
  Responded = 'responded',
  /** Playing TTS audio */
  Speaking = 'speaking',
  /** Complete turn result */
  TurnCompleted = 'turnCompleted',
  /** Session stopped */
  Stopped = 'stopped',
  /** Error occurred */
  Error = 'error',
}

/**
 * Helper functions for creating voice session events
 */
export const VoiceSessionEventFactory = {
  started: (): VoiceSessionEvent => ({ type: 'started' }),
  listening: (audioLevel: number): VoiceSessionEvent => ({
    type: 'listening',
    audioLevel,
  }),
  speechStarted: (): VoiceSessionEvent => ({ type: 'speechStarted' }),
  processing: (): VoiceSessionEvent => ({ type: 'processing' }),
  transcribed: (text: string): VoiceSessionEvent => ({
    type: 'transcribed',
    text,
  }),
  responded: (text: string): VoiceSessionEvent => ({ type: 'responded', text }),
  speaking: (): VoiceSessionEvent => ({ type: 'speaking' }),
  turnCompleted: (
    transcript: string,
    response: string,
    audio?: ArrayBuffer
  ): VoiceSessionEvent => ({
    type: 'turnCompleted',
    transcript,
    response,
    audio,
  }),
  stopped: (): VoiceSessionEvent => ({ type: 'stopped' }),
  error: (message: string): VoiceSessionEvent => ({ type: 'error', message }),
};
