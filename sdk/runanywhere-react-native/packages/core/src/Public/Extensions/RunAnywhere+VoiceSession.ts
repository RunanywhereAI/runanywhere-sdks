/**
 * RunAnywhere+VoiceSession.ts
 *
 * High-level voice session API for simplified voice assistant integration.
 * Handles audio capture, VAD, and processing internally.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceSession.swift
 *
 * Usage:
 * ```typescript
 * // Start a voice session with async iterator
 * const session = await startVoiceSession();
 *
 * for await (const event of session.events()) {
 *   switch (event.type) {
 *     case 'listening':
 *       updateAudioMeter(event.audioLevel);
 *       break;
 *     case 'processing':
 *       showProcessingIndicator();
 *       break;
 *     case 'turnCompleted':
 *       updateUI(event.transcription, event.response);
 *       break;
 *   }
 * }
 *
 * // Or use callbacks
 * const session = await startVoiceSessionWithCallback({}, (event) => {
 *   // Handle event
 * });
 *
 * // Stop the session
 * session.stop();
 * ```
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import {
  VoiceSessionHandle,
  DEFAULT_VOICE_SESSION_CONFIG,
  type VoiceSessionConfig,
  type VoiceSessionEvent,
  type VoiceSessionEventCallback,
} from '../../Features/VoiceSession';

const logger = new SDKLogger('RunAnywhere.VoiceSession');

// Re-export types for convenience
export type {
  VoiceSessionConfig,
  VoiceSessionEvent,
  VoiceSessionEventCallback
};
export { DEFAULT_VOICE_SESSION_CONFIG };

/**
 * Start a voice session with async event iteration
 *
 * This is the simplest way to integrate voice assistant.
 * The session handles audio capture, VAD, and processing internally.
 *
 * Example:
 * ```typescript
 * const session = await startVoiceSession();
 *
 * // Consume events using async iteration
 * for await (const event of session.events()) {
 *   switch (event.type) {
 *     case 'listening':
 *       audioMeter = event.audioLevel ?? 0;
 *       break;
 *     case 'processing':
 *       status = 'Processing...';
 *       break;
 *     case 'turnCompleted':
 *       userText = event.transcription ?? '';
 *       assistantText = event.response ?? '';
 *       break;
 *     case 'stopped':
 *       // Session ended
 *       break;
 *   }
 * }
 * ```
 *
 * @param config Session configuration (optional)
 * @returns Session handle with events iterator
 */
export async function startVoiceSession(
  config: VoiceSessionConfig = {}
): Promise<VoiceSessionHandle> {
  logger.info('Starting voice session...');

  const session = new VoiceSessionHandle(config);
  await session.start();

  logger.info('Voice session started');
  return session;
}

/**
 * Start a voice session with callback-based event handling
 *
 * Alternative API using callbacks instead of async iterator.
 * You can also pass `onEvent` directly in the config.
 *
 * Example:
 * ```typescript
 * // Using onEvent in config (preferred)
 * const session = await startVoiceSession({
 *   onEvent: (event) => {
 *     switch (event.type) {
 *       case 'listening': setAudioLevel(event.audioLevel ?? 0); break;
 *       case 'transcribed': setUserText(event.transcription ?? ''); break;
 *       case 'responded': setAssistantText(event.response ?? ''); break;
 *     }
 *   }
 * });
 *
 * // Or using separate callback parameter
 * const session = await startVoiceSessionWithCallback({}, (event) => { ... });
 *
 * // Later...
 * session.stop();
 * ```
 *
 * @param config Session configuration
 * @param onEvent Callback for each event
 * @returns Session handle for control
 */
export async function startVoiceSessionWithCallback(
  config: VoiceSessionConfig = {},
  onEvent: VoiceSessionEventCallback
): Promise<VoiceSessionHandle> {
  logger.info('Starting voice session with callback...');

  // Merge the callback into config
  const configWithCallback = { ...config, onEvent };
  const session = new VoiceSessionHandle(configWithCallback);
  await session.start();

  logger.info('Voice session with callback started');
  return session;
}

/**
 * Create a voice session handle without starting it
 *
 * Useful when you want to configure the session before starting.
 *
 * @param config Session configuration
 * @returns Session handle (not started)
 */
export function createVoiceSession(
  config: VoiceSessionConfig = {}
): VoiceSessionHandle {
  return new VoiceSessionHandle(config);
}
