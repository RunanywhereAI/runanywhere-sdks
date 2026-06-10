/**
 * Voice Types - STT, TTS, and Voice Assistant
 *
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/
 */

export enum STTMode {
  Batch = 'batch',
  Live = 'live',
}

export enum VoicePipelineStatus {
  Idle = 'idle',
  Listening = 'listening',
  Processing = 'processing',
  Thinking = 'thinking',
  Speaking = 'speaking',
  Error = 'error',
}

export interface VoiceConversationEntry {
  id: string;
  speaker: 'user' | 'assistant';
  text: string;
  audioData?: string;
  timestamp: Date;
  duration?: number;
}
