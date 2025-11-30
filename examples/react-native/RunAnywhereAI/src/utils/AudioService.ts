/**
 * AudioService - Audio recording and playback utilities
 *
 * Provides a unified interface for audio operations needed by:
 * - STTScreen: Record audio for transcription
 * - TTSScreen: Play synthesized audio
 * - VoiceAssistantScreen: Full pipeline with record + play
 */

import { Platform, PermissionsAndroid } from 'react-native';
import AudioRecorderPlayer, {
  AudioEncoderAndroidType,
  AudioSourceAndroidType,
  AVEncoderAudioQualityIOSType,
  AVEncodingOption,
} from 'react-native-audio-recorder-player';

// Audio configuration for speech recognition
export const SAMPLE_RATE = 16000; // Required by Whisper models

// Singleton audio recorder/player instance
let audioRecorderPlayer: AudioRecorderPlayer | null = null;

/**
 * Get or create the audio recorder/player instance
 */
function getRecorderPlayer(): AudioRecorderPlayer {
  if (!audioRecorderPlayer) {
    audioRecorderPlayer = new AudioRecorderPlayer();
  }
  return audioRecorderPlayer;
}

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
 */
export async function startRecording(callbacks?: RecordingCallbacks): Promise<string> {
  const player = getRecorderPlayer();

  try {
    // Use platform-appropriate path
    const uri = await player.startRecorder(
      undefined, // Use default path
      {
        AudioEncoderAndroid: AudioEncoderAndroidType.AAC,
        AudioSourceAndroid: AudioSourceAndroidType.MIC,
        AVEncoderAudioQualityKeyIOS: AVEncoderAudioQualityIOSType.high,
        AVNumberOfChannelsKeyIOS: 1,
        AVSampleRateKeyIOS: SAMPLE_RATE,
        AVFormatIDKeyIOS: AVEncodingOption.aac,
      },
      true // Enable metering
    );

    currentRecordUri = uri;
    recordingStartTime = Date.now();
    console.log('[AudioService] Recording started:', uri);

    // Set up progress listener
    if (callbacks?.onProgress) {
      player.addRecordBackListener((e) => {
        callbacks.onProgress?.(e.currentPosition, e.currentMetering);
      });
    }

    return uri;
  } catch (error) {
    console.error('[AudioService] Start recording error:', error);
    throw error;
  }
}

/**
 * Stop recording and return the audio URI and duration
 */
export async function stopRecording(): Promise<{ uri: string; durationMs: number }> {
  const player = getRecorderPlayer();

  try {
    const uri = await player.stopRecorder();
    player.removeRecordBackListener();

    const durationMs = Date.now() - recordingStartTime;
    console.log('[AudioService] Recording stopped:', uri, 'duration:', durationMs);

    return {
      uri: uri || currentRecordUri || '',
      durationMs,
    };
  } catch (error) {
    console.error('[AudioService] Stop recording error:', error);
    throw error;
  }
}

/**
 * Cancel recording
 */
export async function cancelRecording(): Promise<void> {
  const player = getRecorderPlayer();

  try {
    await player.stopRecorder();
    player.removeRecordBackListener();
    currentRecordUri = null;
  } catch (error) {
    console.error('[AudioService] Cancel recording error:', error);
  }
}

export interface PlaybackCallbacks {
  onProgress?: (currentPositionMs: number, durationMs: number) => void;
  onComplete?: () => void;
}

/**
 * Play audio from URI
 */
export async function playAudio(uri: string, callbacks?: PlaybackCallbacks): Promise<void> {
  const player = getRecorderPlayer();

  try {
    await player.startPlayer(uri);
    console.log('[AudioService] Playback started:', uri);

    player.addPlayBackListener((e) => {
      callbacks?.onProgress?.(e.currentPosition, e.duration);

      // Check if playback is complete
      if (e.currentPosition >= e.duration - 100) { // Small buffer for completion
        player.stopPlayer();
        player.removePlayBackListener();
        callbacks?.onComplete?.();
      }
    });
  } catch (error) {
    console.error('[AudioService] Playback error:', error);
    throw error;
  }
}

/**
 * Stop playback
 */
export async function stopPlayback(): Promise<void> {
  const player = getRecorderPlayer();

  try {
    await player.stopPlayer();
    player.removePlayBackListener();
  } catch (error) {
    console.error('[AudioService] Stop playback error:', error);
  }
}

/**
 * Pause playback
 */
export async function pausePlayback(): Promise<void> {
  const player = getRecorderPlayer();
  try {
    await player.pausePlayer();
  } catch (error) {
    console.error('[AudioService] Pause playback error:', error);
  }
}

/**
 * Resume playback
 */
export async function resumePlayback(): Promise<void> {
  const player = getRecorderPlayer();
  try {
    await player.resumePlayer();
  } catch (error) {
    console.error('[AudioService] Resume playback error:', error);
  }
}

/**
 * Cleanup resources
 */
export async function cleanup(): Promise<void> {
  const player = getRecorderPlayer();
  try {
    await player.stopRecorder().catch(() => {});
    await player.stopPlayer().catch(() => {});
    player.removeRecordBackListener();
    player.removePlayBackListener();
  } catch {
    // Ignore cleanup errors
  }
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
