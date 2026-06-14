/**
 * AudioCaptureManager.ts
 *
 * In-SDK microphone capture for STT features. Bridges through the SDK's own
 * Nitro `AudioCapture` HybridObject (AVAudioEngine on iOS, AudioRecord on
 * Android) — no host-app native module required. Emits 16kHz mono Int16
 * little-endian PCM chunks, the canonical input format for speech
 * recognition models like Whisper.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift`.
 *
 * ## Usage
 * ```ts
 * const capture = new AudioCaptureManager();
 * const granted = await capture.requestPermission();
 * if (granted) {
 *   await capture.startRecording((chunk) => {
 *     // Feed 16kHz mono Int16 PCM bytes to your STT service
 *   });
 * }
 * ```
 */

import { Platform, PermissionsAndroid } from 'react-native';
import { AudioCapture } from '../../Internal/Nitro/NitroAudioCaptureSpec';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('AudioCaptureManager');

export class AudioCaptureManager {
  /**
   * Request microphone permission.
   *
   * iOS: prompts via the native `AVAudioApplication.requestRecordPermission()`.
   * Android: prompts via `PermissionsAndroid` (the native side can only CHECK
   * the permission because the runtime prompt requires an Activity).
   */
  async requestPermission(): Promise<boolean> {
    if (Platform.OS === 'android') {
      // Already granted? (native check — avoids a redundant prompt)
      const alreadyGranted = await AudioCapture.requestPermission();
      if (alreadyGranted) return true;

      const status = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.RECORD_AUDIO
      );
      return status === PermissionsAndroid.RESULTS.GRANTED;
    }
    return AudioCapture.requestPermission();
  }

  /**
   * Start recording audio from the microphone.
   *
   * @param onAudioData receives 16kHz mono Int16 little-endian PCM chunks.
   */
  async startRecording(
    onAudioData: (chunk: Uint8Array) => void
  ): Promise<void> {
    await AudioCapture.startRecording((chunk: ArrayBuffer) => {
      onAudioData(new Uint8Array(chunk));
    });
    logger.info('Recording started');
  }

  /**
   * Stop recording.
   *
   * @param deactivateSession when `true` (default) the audio session is also
   *   deactivated. Pass `false` to keep the session alive for subsequent
   *   recordings (e.g. between listening segments in a flow session).
   */
  stopRecording(deactivateSession = true): void {
    AudioCapture.stopRecording(deactivateSession);
    logger.info(`Recording stopped (deactivateSession=${deactivateSession})`);
  }

  /**
   * Activate the audio session without starting capture (iOS background
   * keepalive — Swift parity). No-op on Android.
   */
  async activateAudioSession(): Promise<void> {
    await AudioCapture.activateAudioSession();
  }

  /** Deactivate the audio session. No-op on Android. */
  deactivateAudioSession(): void {
    AudioCapture.deactivateAudioSession();
  }

  /** Whether recording is currently active. */
  get isRecording(): boolean {
    return AudioCapture.isRecording;
  }

  /** Current input level normalized to 0..1 (RMS → dB, -60dB..0dB). */
  get audioLevel(): number {
    return AudioCapture.audioLevel;
  }
}
