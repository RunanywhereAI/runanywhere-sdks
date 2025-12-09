/**
 * Native Audio Module for iOS
 * Uses AVFoundation directly for audio recording and playback
 * Compatible with React Native New Architecture + Nitrogen
 */

import { NativeModules, Platform } from 'react-native';

interface RecordingResult {
  status: string;
  path?: string;
  fileSize?: number;
}

interface PlaybackResult {
  status: string;
  duration?: number;
}

interface PlaybackStatus {
  isPlaying: boolean;
  currentTime: number;
  duration: number;
}

interface AudioLevelResult {
  level: number;
}

interface NativeAudioModuleType {
  // Recording
  startRecording(): Promise<RecordingResult>;
  stopRecording(): Promise<RecordingResult>;
  cancelRecording(): Promise<RecordingResult>;
  getAudioLevel(): Promise<AudioLevelResult>;
  
  // Playback
  playAudio(filePath: string): Promise<PlaybackResult>;
  stopPlayback(): Promise<PlaybackResult>;
  pausePlayback(): Promise<PlaybackResult>;
  resumePlayback(): Promise<PlaybackResult>;
  getPlaybackStatus(): Promise<PlaybackStatus>;
  setVolume(volume: number): Promise<{ volume: number }>;
}

// Only available on iOS
const NativeAudio: NativeAudioModuleType | null = 
  Platform.OS === 'ios' ? NativeModules.NativeAudioModule : null;

export const isNativeAudioAvailable = (): boolean => {
  return Platform.OS === 'ios' && NativeAudio !== null;
};

// Recording functions
export const startNativeRecording = async (): Promise<RecordingResult> => {
  if (!NativeAudio) {
    throw new Error('Native audio not available on this platform');
  }
  return NativeAudio.startRecording();
};

export const stopNativeRecording = async (): Promise<RecordingResult> => {
  if (!NativeAudio) {
    throw new Error('Native audio not available on this platform');
  }
  return NativeAudio.stopRecording();
};

export const cancelNativeRecording = async (): Promise<RecordingResult> => {
  if (!NativeAudio) {
    throw new Error('Native audio not available on this platform');
  }
  return NativeAudio.cancelRecording();
};

export const getNativeAudioLevel = async (): Promise<number> => {
  if (!NativeAudio) {
    return 0;
  }
  const result = await NativeAudio.getAudioLevel();
  return result.level;
};

// Playback functions
export const playNativeAudio = async (filePath: string): Promise<PlaybackResult> => {
  if (!NativeAudio) {
    throw new Error('Native audio not available on this platform');
  }
  return NativeAudio.playAudio(filePath);
};

export const stopNativePlayback = async (): Promise<void> => {
  if (!NativeAudio) {
    return;
  }
  await NativeAudio.stopPlayback();
};

export const pauseNativePlayback = async (): Promise<void> => {
  if (!NativeAudio) {
    return;
  }
  await NativeAudio.pausePlayback();
};

export const resumeNativePlayback = async (): Promise<void> => {
  if (!NativeAudio) {
    return;
  }
  await NativeAudio.resumePlayback();
};

export const getNativePlaybackStatus = async (): Promise<PlaybackStatus> => {
  if (!NativeAudio) {
    return { isPlaying: false, currentTime: 0, duration: 0 };
  }
  return NativeAudio.getPlaybackStatus();
};

export const setNativeVolume = async (volume: number): Promise<void> => {
  if (!NativeAudio) {
    return;
  }
  await NativeAudio.setVolume(volume);
};

export default {
  isAvailable: isNativeAudioAvailable,
  startRecording: startNativeRecording,
  stopRecording: stopNativeRecording,
  cancelRecording: cancelNativeRecording,
  getAudioLevel: getNativeAudioLevel,
  playAudio: playNativeAudio,
  stopPlayback: stopNativePlayback,
  pausePlayback: pauseNativePlayback,
  resumePlayback: resumeNativePlayback,
  getPlaybackStatus: getNativePlaybackStatus,
  setVolume: setNativeVolume,
};

