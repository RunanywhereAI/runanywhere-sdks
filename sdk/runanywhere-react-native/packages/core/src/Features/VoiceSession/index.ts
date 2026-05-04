/**
 * VoiceSession Feature Module
 *
 * Provides high-level voice session management for voice assistant integration.
 */

export { AudioCaptureManager } from './AudioCaptureManager';
export type { AudioDataCallback, AudioLevelCallback, AudioCaptureConfig, AudioCaptureState } from './AudioCaptureManager';

export { AudioPlaybackManager } from './AudioPlaybackManager';
export type { PlaybackState, PlaybackCompletionCallback, PlaybackErrorCallback, PlaybackConfig } from './AudioPlaybackManager';

// v3.1: VoiceSessionHandle + related types DELETED. Use
// VoiceAgentStreamAdapter (exported at package root) instead.
