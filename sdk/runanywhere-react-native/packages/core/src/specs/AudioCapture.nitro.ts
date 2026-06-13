import { type HybridObject } from 'react-native-nitro-modules';

/**
 * In-SDK microphone capture for STT features.
 *
 * Mirrors the Swift SDK source of truth:
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift`
 * (AVAudioEngine input tap → AVAudioConverter → 16kHz mono Int16 chunks) and
 * the Kotlin port
 * `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/features/STT/Services/AudioCaptureManager.kt`
 * (AudioRecord 16kHz CHANNEL_IN_MONO PCM16 background read loop).
 */
export interface AudioCapture
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Request microphone permission.
   *
   * iOS: prompts via `AVAudioApplication.requestRecordPermission()`.
   * Android: permission CHECK only (`RECORD_AUDIO` granted?) — the actual
   * runtime prompt must be issued from JS via `PermissionsAndroid` because it
   * requires an Activity.
   */
  requestPermission(): Promise<boolean>;

  /**
   * Start recording from the microphone.
   *
   * Emits 16kHz mono Int16 little-endian PCM chunks through `onAudioData`.
   */
  startRecording(onAudioData: (chunk: ArrayBuffer) => void): Promise<void>;

  /**
   * Stop recording.
   *
   * @param deactivateSession when `true` the audio session is also
   *   deactivated (iOS) / audio focus abandoned (Android). Pass `false` to
   *   keep the session alive between listening segments.
   */
  stopRecording(deactivateSession: boolean): void;

  /**
   * Activate the audio session without starting the engine (iOS keepalive).
   * No-op on Android (audio focus is requested in `startRecording`).
   */
  activateAudioSession(): Promise<void>;

  /**
   * Deactivate the audio session. No-op on Android.
   */
  deactivateAudioSession(): void;

  /** Whether recording is currently active. */
  readonly isRecording: boolean;

  /**
   * Current input level normalized to 0..1
   * (RMS → dB, mapped from -60dB..0dB — Swift parity).
   */
  readonly audioLevel: number;
}
