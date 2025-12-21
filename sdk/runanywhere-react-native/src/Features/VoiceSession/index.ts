/**
 * VoiceSession Module
 * RunAnywhere SDK
 *
 * High-level voice session API for simplified voice assistant integration.
 * Handles audio capture, VAD, and processing internally.
 *
 * Matches iOS: Public/Extensions/RunAnywhere+VoiceSession.swift
 */

// Type exports
export type { VoiceSessionEvent } from './VoiceSessionEvent';
export type { VoiceSessionConfig } from './VoiceSessionConfig';
export type { VoiceSessionEventListener } from './VoiceSessionHandle';

// Value exports
export {
  VoiceSessionEventType,
  VoiceSessionEventFactory,
} from './VoiceSessionEvent';

export {
  DEFAULT_VOICE_SESSION_CONFIG,
  createVoiceSessionConfig,
  VoiceSessionConfigPresets,
} from './VoiceSessionConfig';

export {
  VoiceSessionError,
  VoiceSessionErrorCode,
  isVoiceSessionError,
} from './VoiceSessionError';

export { VoiceSessionHandle } from './VoiceSessionHandle';
