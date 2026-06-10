import { type HybridObject } from 'react-native-nitro-modules';

/**
 * In-SDK audio playback for TTS features.
 *
 * Mirrors the Swift SDK source of truth:
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift`
 * (AVAudioPlayer over in-memory WAV data, delegate-driven completion,
 * pause/resume, interruption handling) and the Kotlin port
 * `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/features/TTS/Services/AudioPlaybackManager.kt`
 * (AudioTrack MODE_STATIC, WAV header parsing, marker-listener completion).
 */
export interface AudioPlayback
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Play in-memory WAV audio data.
   *
   * The returned promise resolves when playback finishes and rejects if
   * playback fails or is interrupted — no JS-side polling required.
   */
  play(wavData: ArrayBuffer): Promise<void>;

  /**
   * Play an audio file from disk. Resolves when playback finishes.
   */
  playFile(path: string): Promise<void>;

  /** Stop current playback (rejects an in-flight `play()` promise). */
  stop(): void;

  /** Pause current playback. */
  pause(): void;

  /** Resume paused playback. */
  resume(): void;

  /** Whether audio is currently playing. */
  readonly isPlaying: boolean;

  /** Current playback position in seconds. */
  readonly currentTime: number;

  /** Total duration of the loaded audio in seconds. */
  readonly duration: number;
}
