/**
 * AudioService - Audio recording and playback utilities
 *
 * Provides a unified interface for audio operations needed by:
 * - STTScreen: Record audio for transcription
 * - TTSScreen: Play synthesized audio
 * - VoiceAssistantScreen: Full pipeline with record + play
 *
 * NOTE: react-native-audio-recorder-player is deprecated and incompatible with RN 0.81.
 * This is a mock implementation. Replace with a compatible library.
 */

import { Platform, PermissionsAndroid } from 'react-native';

// TODO: Replace with RN 0.81 compatible audio library
// import AudioRecorderPlayer, {
//   AudioEncoderAndroidType,
//   AudioSourceAndroidType,
//   AVEncoderAudioQualityIOSType,
//   AVEncodingOption,
// } from 'react-native-audio-recorder-player';

// Audio configuration for speech recognition
export const SAMPLE_RATE = 16000; // Required by Whisper models

/**
 * Request microphone permission
 */
export async function requestAudioPermission(): Promise<boolean> {
  if (Platform.OS === 'android') {
    try {
      const granted = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
        {
          title: 'Microphone Permission',
          message: 'RunAnywhere needs access to your microphone for speech recognition.',
          buttonNeutral: 'Ask Me Later',
          buttonNegative: 'Cancel',
          buttonPositive: 'OK',
        }
      );
      return granted === PermissionsAndroid.RESULTS.GRANTED;
    } catch (err) {
      console.error('[AudioService] Permission request error:', err);
      return false;
    }
  }
  // iOS handles permissions automatically via Info.plist
  return true;
}

export interface RecordingCallbacks {
  onProgress?: (currentPositionMs: number, metering?: number) => void;
}

let currentRecordUri: string | null = null;
let recordingStartTime: number = 0;

/**
 * Start recording audio
 * Returns the URI where the audio will be saved
 * 
 * NOTE: This is a mock implementation. Audio recording is not functional.
 */
export async function startRecording(callbacks?: RecordingCallbacks): Promise<string> {
  console.warn('[AudioService] Audio recording is not available - react-native-audio-recorder-player is deprecated');
  
  // Return a mock path
  const mockPath = Platform.OS === 'ios' 
    ? `/tmp/mock_recording_${Date.now()}.wav`
    : `/data/user/0/com.runanywhereaI/cache/mock_recording_${Date.now()}.wav`;
  
  currentRecordUri = mockPath;
  recordingStartTime = Date.now();
  
  return mockPath;
}

/**
 * Stop recording and return the audio URI and duration
 * 
 * NOTE: This is a mock implementation.
 */
export async function stopRecording(): Promise<{ uri: string; durationMs: number }> {
  const durationMs = Date.now() - recordingStartTime;
  console.warn('[AudioService] Stopping mock recording');
  
  return {
    uri: currentRecordUri || '',
    durationMs,
  };
}

/**
 * Cancel recording
 */
export async function cancelRecording(): Promise<void> {
  currentRecordUri = null;
  console.warn('[AudioService] Cancelling mock recording');
}

export interface PlaybackCallbacks {
  onProgress?: (currentPositionMs: number, durationMs: number) => void;
  onComplete?: () => void;
}

/**
 * Play audio from URI
 * 
 * NOTE: This is a mock implementation. Audio playback is not functional.
 */
export async function playAudio(uri: string, callbacks?: PlaybackCallbacks): Promise<void> {
  console.warn('[AudioService] Audio playback is not available - react-native-audio-recorder-player is deprecated');
  console.log('[AudioService] Would play:', uri);
  
  // Simulate playback completion after a short delay
  setTimeout(() => {
    callbacks?.onComplete?.();
  }, 100);
}

/**
 * Stop playback
 */
export async function stopPlayback(): Promise<void> {
  console.warn('[AudioService] Stopping mock playback');
}

/**
 * Pause playback
 */
export async function pausePlayback(): Promise<void> {
  console.warn('[AudioService] Pausing mock playback');
}

/**
 * Resume playback
 */
export async function resumePlayback(): Promise<void> {
  console.warn('[AudioService] Resuming mock playback');
}

/**
 * Cleanup resources
 */
export async function cleanup(): Promise<void> {
  currentRecordUri = null;
}

/**
 * Format milliseconds to MM:SS
 */
export function formatDuration(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

export default {
  requestAudioPermission,
  startRecording,
  stopRecording,
  cancelRecording,
  playAudio,
  stopPlayback,
  pausePlayback,
  resumePlayback,
  cleanup,
  formatDuration,
  SAMPLE_RATE,
};
