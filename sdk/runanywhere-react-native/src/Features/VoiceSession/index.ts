/**
 * VoiceSession Module
 * RunAnywhere SDK
 *
 * High-level voice session API for simplified voice assistant integration.
 * Handles audio capture, VAD, and processing internally.
 *
 * Matches iOS: Public/Extensions/RunAnywhere+VoiceSession.swift
 */

export {
  VoiceSessionEvent,
  VoiceSessionEventType,
  VoiceSessionEventFactory,
} from './VoiceSessionEvent';

export {
  VoiceSessionConfig,
  DEFAULT_VOICE_SESSION_CONFIG,
  createVoiceSessionConfig,
  VoiceSessionConfigPresets,
} from './VoiceSessionConfig';

export {
  VoiceSessionError,
  VoiceSessionErrorCode,
  isVoiceSessionError,
} from './VoiceSessionError';

export {
  VoiceSessionHandle,
  type VoiceSessionEventListener,
} from './VoiceSessionHandle';
