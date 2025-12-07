/**
 * AudioService - Audio recording and playback utilities
 *
 * Provides a unified interface for audio operations needed by:
 * - STTScreen: Record audio for transcription
 * - TTSScreen: Play synthesized audio
 * - VoiceAssistantScreen: Full pipeline with record + play
 *
 * Uses expo-av for cross-platform audio support (RN 0.81+ compatible)
 */

import { Platform, PermissionsAndroid } from 'react-native';
import { Audio } from 'expo-av';

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
  
  // iOS: Request permission via expo-av
  try {
    const { status } = await Audio.requestPermissionsAsync();
    return status === 'granted';
  } catch (err) {
    console.error('[AudioService] iOS permission request error:', err);
    return false;
  }
}

export interface RecordingCallbacks {
  onProgress?: (currentPositionMs: number, metering?: number) => void;
}

let currentRecording: Audio.Recording | null = null;
let recordingStartTime: number = 0;

/**
 * Start recording audio
 * Returns the URI where the audio will be saved
 */
export async function startRecording(callbacks?: RecordingCallbacks): Promise<string> {
  try {
    // Set audio mode for recording
    await Audio.setAudioModeAsync({
      allowsRecordingIOS: true,
      playsInSilentModeIOS: true,
    });

    // Create recording with WAV format for compatibility with Whisper
    const recording = new Audio.Recording();
    await recording.prepareToRecordAsync({
      android: {
        extension: '.wav',
        outputFormat: Audio.AndroidOutputFormat.DEFAULT,
        audioEncoder: Audio.AndroidAudioEncoder.DEFAULT,
        sampleRate: SAMPLE_RATE,
        numberOfChannels: 1,
        bitRate: 128000,
      },
      ios: {
        extension: '.wav',
        audioQuality: Audio.IOSAudioQuality.HIGH,
        sampleRate: SAMPLE_RATE,
        numberOfChannels: 1,
        bitRate: 128000,
        linearPCMBitDepth: 16,
        linearPCMIsBigEndian: false,
        linearPCMIsFloat: false,
      },
      web: {
        mimeType: 'audio/webm',
        bitsPerSecond: 128000,
      },
    });

    await recording.startAsync();
    currentRecording = recording;
    recordingStartTime = Date.now();

    // Get the URI
    const uri = recording.getURI() || '';
    console.log('[AudioService] Recording started:', uri);
    
    // Set up progress monitoring if callback provided
    if (callbacks?.onProgress) {
      recording.setOnRecordingStatusUpdate((status) => {
        if (status.isRecording) {
          callbacks.onProgress?.(status.durationMillis, status.metering);
        }
      });
      recording.setProgressUpdateInterval(100);
    }

    return uri;
  } catch (error) {
    console.error('[AudioService] Failed to start recording:', error);
    throw error;
  }
}

/**
 * Stop recording and return the audio URI and duration
 */
export async function stopRecording(): Promise<{ uri: string; durationMs: number }> {
  if (!currentRecording) {
    throw new Error('No recording in progress');
  }

  try {
    await currentRecording.stopAndUnloadAsync();
    const uri = currentRecording.getURI() || '';
    const durationMs = Date.now() - recordingStartTime;
    
    console.log('[AudioService] Recording stopped:', uri, durationMs);
    
    // Reset audio mode
    await Audio.setAudioModeAsync({
      allowsRecordingIOS: false,
    });

    currentRecording = null;
    return { uri, durationMs };
  } catch (error) {
    console.error('[AudioService] Failed to stop recording:', error);
    currentRecording = null;
    throw error;
  }
}

/**
 * Cancel recording
 */
export async function cancelRecording(): Promise<void> {
  if (currentRecording) {
    try {
      await currentRecording.stopAndUnloadAsync();
      await Audio.setAudioModeAsync({
        allowsRecordingIOS: false,
      });
    } catch (error) {
      console.error('[AudioService] Failed to cancel recording:', error);
    }
    currentRecording = null;
  }
}

export interface PlaybackCallbacks {
  onProgress?: (currentPositionMs: number, durationMs: number) => void;
  onComplete?: () => void;
}

let currentSound: Audio.Sound | null = null;

/**
 * Play audio from URI
 */
export async function playAudio(uri: string, callbacks?: PlaybackCallbacks): Promise<void> {
  try {
    // Stop any existing playback
    if (currentSound) {
      await currentSound.unloadAsync();
      currentSound = null;
    }

    // Set audio mode for playback
    await Audio.setAudioModeAsync({
      allowsRecordingIOS: false,
      playsInSilentModeIOS: true,
      shouldDuckAndroid: true,
      staysActiveInBackground: false,
    });

    // Create and load sound
    const { sound } = await Audio.Sound.createAsync(
      { uri },
      { shouldPlay: true },
      (status) => {
        if (status.isLoaded) {
          callbacks?.onProgress?.(status.positionMillis, status.durationMillis || 0);
          if (status.didJustFinish) {
            callbacks?.onComplete?.();
            sound.unloadAsync();
            currentSound = null;
          }
        }
      }
    );

    currentSound = sound;
    console.log('[AudioService] Playing audio:', uri);
  } catch (error) {
    console.error('[AudioService] Failed to play audio:', error);
    throw error;
  }
}

/**
 * Stop playback
 */
export async function stopPlayback(): Promise<void> {
  if (currentSound) {
    try {
      await currentSound.stopAsync();
      await currentSound.unloadAsync();
    } catch (error) {
      console.error('[AudioService] Failed to stop playback:', error);
    }
    currentSound = null;
  }
}

/**
 * Pause playback
 */
export async function pausePlayback(): Promise<void> {
  if (currentSound) {
    try {
      await currentSound.pauseAsync();
    } catch (error) {
      console.error('[AudioService] Failed to pause playback:', error);
    }
  }
}

/**
 * Resume playback
 */
export async function resumePlayback(): Promise<void> {
  if (currentSound) {
    try {
      await currentSound.playAsync();
    } catch (error) {
      console.error('[AudioService] Failed to resume playback:', error);
    }
  }
}

/**
 * Cleanup resources
 */
export async function cleanup(): Promise<void> {
  if (currentRecording) {
    await cancelRecording();
  }
  if (currentSound) {
    await stopPlayback();
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
