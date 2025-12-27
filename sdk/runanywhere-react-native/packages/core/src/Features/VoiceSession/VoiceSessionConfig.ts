/**
 * VoiceSessionConfig.ts
 * RunAnywhere SDK
 *
 * Configuration for voice session behavior.
 * Matches iOS: Public/Extensions/RunAnywhere+VoiceSession.swift
 */

/**
 * Configuration for voice session behavior
 */
export interface VoiceSessionConfig {
  /**
   * Silence duration (seconds) before processing speech
   * @default 1.5
   */
  silenceDuration: number;

  /**
   * Minimum audio level to detect speech (0.0 - 1.0)
   * @default 0.1
   */
  speechThreshold: number;

  /**
   * Whether to auto-play TTS response
   * @default true
   */
  autoPlayTTS: boolean;

  /**
   * Whether to auto-resume listening after TTS playback
   * @default true
   */
  continuousMode: boolean;
}

/**
 * Default voice session configuration
 */
export const DEFAULT_VOICE_SESSION_CONFIG: VoiceSessionConfig = {
  silenceDuration: 1.5,
  speechThreshold: 0.1,
  autoPlayTTS: true,
  continuousMode: true,
};

/**
 * Create a voice session config with optional overrides
 */
export function createVoiceSessionConfig(
  overrides?: Partial<VoiceSessionConfig>
): VoiceSessionConfig {
  return {
    ...DEFAULT_VOICE_SESSION_CONFIG,
    ...overrides,
  };
}

/**
 * Voice session config presets
 */
export const VoiceSessionConfigPresets = {
  /**
   * Default configuration for general use
   */
  default: DEFAULT_VOICE_SESSION_CONFIG,

  /**
   * Push-to-talk mode (no automatic speech detection)
   */
  pushToTalk: {
    silenceDuration: 0,
    speechThreshold: 0,
    autoPlayTTS: true,
    continuousMode: false,
  } as VoiceSessionConfig,

  /**
   * Quick response mode with shorter silence detection
   */
  quickResponse: {
    silenceDuration: 0.8,
    speechThreshold: 0.15,
    autoPlayTTS: true,
    continuousMode: true,
  } as VoiceSessionConfig,

  /**
   * High sensitivity mode for quiet environments
   */
  highSensitivity: {
    silenceDuration: 2.0,
    speechThreshold: 0.05,
    autoPlayTTS: true,
    continuousMode: true,
  } as VoiceSessionConfig,
};
