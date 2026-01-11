/**
 * VoiceSession Feature Module
 *
 * Provides high-level voice session management for voice assistant integration.
 */

export { AudioCaptureManager } from './AudioCaptureManager';
export type { AudioDataCallback, AudioLevelCallback, AudioCaptureConfig, AudioCaptureState } from './AudioCaptureManager';

export { AudioPlaybackManager } from './AudioPlaybackManager';
export type { PlaybackState, PlaybackCompletionCallback, PlaybackErrorCallback, PlaybackConfig } from './AudioPlaybackManager';

export { VoiceSessionHandle, DEFAULT_VOICE_SESSION_CONFIG } from './VoiceSessionHandle';
export type {
  VoiceSessionConfig,
  VoiceSessionEvent,
  VoiceSessionEventType,
  VoiceSessionEventCallback,
  VoiceSessionState,
} from './VoiceSessionHandle';
