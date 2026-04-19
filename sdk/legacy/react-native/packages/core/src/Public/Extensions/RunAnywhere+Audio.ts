/**
 * RunAnywhere+Audio.ts
 *
 * Audio recording and playback utilities for the SDK.
 * Provides a simple static API for common audio operations.
 *
 * Platform support:
 * - iOS: NativeAudioModule (AVFoundation)
 * - Android: react-native-live-audio-stream + react-native-sound
 */

import { Platform, PermissionsAndroid, NativeModules } from 'react-native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('Audio');

// Native iOS Audio Module
const NativeAudioModule = Platform.OS === 'ios' ? NativeModules.NativeAudioModule : null;

// Lazy load Android dependencies
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let LiveAudioStream: any = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let Sound: any = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let RNFS: any = null;

function getLiveAudioStream() {
  if (Platform.OS !== 'android') return null;
  if (!LiveAudioStream) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      LiveAudioStream = require('react-native-live-audio-stream').default;
    } catch {
      logger.warning('react-native-live-audio-stream not available');
      return null;
    }
  }
  return LiveAudioStream;
}

function getSound() {
  if (Platform.OS === 'ios') return null;
  if (!Sound) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      Sound = require('react-native-sound').default;
      Sound.setCategory('Playback');
    } catch {
      logger.warning('react-native-sound not available');
      return null;
    }
  }
  return Sound;
}

function getRNFS() {
  if (!RNFS) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      RNFS = require('react-native-fs');
    } catch {
      logger.warning('react-native-fs not available');
      return null;
    }
  }
  return RNFS;
}

// ============================================================================
// Constants
// ============================================================================

/** Default sample rate for speech recognition (Whisper models) */
export const AUDIO_SAMPLE_RATE = 16000;

/** TTS default sample rate */
export const TTS_SAMPLE_RATE = 22050;

// ============================================================================
// Internal State
// ============================================================================

let isRecording = false;
let recordingStartTime = 0;
let currentRecordPath: string | null = null;
let audioChunks: string[] = [];
let progressCallback: ((currentPositionMs: number, metering?: number) => void) | null = null;
let audioLevelInterval: ReturnType<typeof setInterval> | null = null;

let isPlaying = false;
let playbackProgressInterval: ReturnType<typeof setInterval> | null = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let currentSound: any = null;

// ============================================================================
// Types
// ============================================================================

export interface RecordingCallbacks {
  /** Progress callback with current position (ms) and audio level (dB: -60 to 0) */
  onProgress?: (currentPositionMs: number, metering?: number) => void;
}

export interface PlaybackCallbacks {
  /** Progress callback with current position and total duration */
  onProgress?: (currentPositionMs: number, durationMs: number) => void;
  /** Called when playback completes */
  onComplete?: () => void;
}

export interface RecordingResult {
  /** Path to the recorded audio file */
  uri: string;
  /** Duration of the recording in milliseconds */
  durationMs: number;
}

// ============================================================================
// Permission
// ============================================================================

/**
 * Request microphone permission
 * @returns true if permission granted
 */
export async function requestAudioPermission(): Promise<boolean> {
  if (Platform.OS === 'android') {
    try {
      const grants = await PermissionsAndroid.requestMultiple([
        PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
      ]);
      const granted = grants[PermissionsAndroid.PERMISSIONS.RECORD_AUDIO] === PermissionsAndroid.RESULTS.GRANTED;
      logger.info(`Android microphone permission: ${granted ? 'granted' : 'denied'}`);
      return granted;
    } catch (err) {
      logger.error(`Permission request error: ${err}`);
      return false;
    }
  }

  // iOS: Permissions are requested automatically when starting recording
  return true;
}

// ============================================================================
// Recording
// ============================================================================

/**
 * Start recording audio
 * @param callbacks Optional callbacks for progress updates
 * @returns Promise with the path where audio will be saved
 */
export async function startRecording(callbacks?: RecordingCallbacks): Promise<string> {
  if (isRecording) {
    throw new Error('Recording already in progress');
  }

  const fs = getRNFS();
  if (!fs) {
    throw new Error('react-native-fs not available');
  }

  // iOS: Use native audio module
  if (Platform.OS === 'ios') {
    if (!NativeAudioModule) {
      throw new Error('NativeAudioModule not available on iOS');
    }

    const result = await NativeAudioModule.startRecording();
    logger.info(`iOS recording started: ${result.path}`);

    isRecording = true;
    recordingStartTime = Date.now();
    currentRecordPath = result.path;
    progressCallback = callbacks?.onProgress ?? null;

    // Poll for audio levels on iOS
    if (progressCallback) {
      audioLevelInterval = setInterval(async () => {
        if (isRecording && NativeAudioModule) {
          try {
            const levelResult = await NativeAudioModule.getAudioLevel();
            const elapsed = Date.now() - recordingStartTime;
            // Convert linear level (0-1) to dB (-60 to 0)
            const db = levelResult.level > 0 ? 20 * Math.log10(levelResult.level) : -60;
            progressCallback?.(elapsed, db);
          } catch {
            // Ignore errors
          }
        }
      }, 100);
    }

    return result.path;
  }

  // Android: Use LiveAudioStream for raw PCM
  const audioStream = getLiveAudioStream();
  if (!audioStream) {
    throw new Error('LiveAudioStream not available on Android');
  }

  const fileName = `recording_${Date.now()}.wav`;
  const filePath = `${fs.CachesDirectoryPath}/${fileName}`;
  currentRecordPath = filePath;
  audioChunks = [];
  progressCallback = callbacks?.onProgress ?? null;

  audioStream.init({
    sampleRate: AUDIO_SAMPLE_RATE,
    channels: 1,
    bitsPerSample: 16,
    audioSource: 6, // VOICE_RECOGNITION
    bufferSize: 4096,
  });

  audioStream.on('data', (data: string) => {
    audioChunks.push(data);

    if (progressCallback) {
      const elapsed = Date.now() - recordingStartTime;
      const audioLevel = calculateAudioLevelFromBase64(data);
      progressCallback(elapsed, audioLevel);
    }
  });

  audioStream.start();
  isRecording = true;
  recordingStartTime = Date.now();

  logger.info(`Android recording started: ${filePath}`);
  return filePath;
}

/**
 * Stop recording and return the audio file path
 * @returns Recording result with path and duration
 */
export async function stopRecording(): Promise<RecordingResult> {
  if (!isRecording) {
    throw new Error('No recording in progress');
  }

  // Clear audio level polling
  if (audioLevelInterval) {
    clearInterval(audioLevelInterval);
    audioLevelInterval = null;
  }

  const durationMs = Date.now() - recordingStartTime;

  // iOS: Use native audio module
  if (Platform.OS === 'ios' && NativeAudioModule) {
    const result = await NativeAudioModule.stopRecording();
    isRecording = false;
    progressCallback = null;
    logger.info(`iOS recording stopped: ${result.path}`);
    return { uri: result.path, durationMs };
  }

  // Android: Stop LiveAudioStream and create WAV file
  const audioStream = getLiveAudioStream();
  if (audioStream) {
    audioStream.stop();
  }
  isRecording = false;

  const uri = currentRecordPath || '';
  logger.info(`Android recording stopped, processing ${audioChunks.length} chunks`);

  // Create WAV file from chunks
  await createWavFileFromChunks(uri, audioChunks);

  // Clean up
  audioChunks = [];
  currentRecordPath = null;
  progressCallback = null;

  return { uri, durationMs };
}

/**
 * Cancel recording without saving
 */
export async function cancelRecording(): Promise<void> {
  if (audioLevelInterval) {
    clearInterval(audioLevelInterval);
    audioLevelInterval = null;
  }

  if (!isRecording) return;

  if (Platform.OS === 'ios' && NativeAudioModule) {
    try {
      await NativeAudioModule.cancelRecording();
    } catch {
      // Ignore
    }
  } else {
    const audioStream = getLiveAudioStream();
    if (audioStream) {
      audioStream.stop();
    }

    // Delete partial file
    if (currentRecordPath) {
      const fs = getRNFS();
      try {
        await fs?.unlink(currentRecordPath);
      } catch {
        // File may not exist
      }
    }
  }

  isRecording = false;
  audioChunks = [];
  currentRecordPath = null;
  progressCallback = null;
}

// ============================================================================
// Playback
// ============================================================================

/**
 * Play audio from a file path
 * @param uri Path to the audio file
 * @param callbacks Optional callbacks for progress and completion
 */
export async function playAudio(uri: string, callbacks?: PlaybackCallbacks): Promise<void> {
  logger.info(`Playing audio: ${uri}`);

  // iOS: Use native audio module
  if (Platform.OS === 'ios' && NativeAudioModule) {
    const result = await NativeAudioModule.playAudio(uri);
    isPlaying = true;
    const durationMs = (result.duration || 0) * 1000;

    if (callbacks?.onProgress || callbacks?.onComplete) {
      playbackProgressInterval = setInterval(async () => {
        if (!isPlaying) {
          if (playbackProgressInterval) {
            clearInterval(playbackProgressInterval);
            playbackProgressInterval = null;
          }
          return;
        }

        try {
          const status = await NativeAudioModule.getPlaybackStatus();
          const currentTimeMs = (status.currentTime || 0) * 1000;
          const totalDurationMs = (status.duration || 0) * 1000;

          callbacks?.onProgress?.(currentTimeMs, totalDurationMs);

          if (!status.isPlaying && currentTimeMs >= totalDurationMs - 100) {
            isPlaying = false;
            if (playbackProgressInterval) {
              clearInterval(playbackProgressInterval);
              playbackProgressInterval = null;
            }
            callbacks?.onComplete?.();
          }
        } catch {
          // Ignore
        }
      }, 100);
    }

    logger.info(`iOS playback started, duration: ${durationMs}ms`);
    return;
  }

  // Android: Use react-native-sound
  const SoundClass = getSound();
  if (!SoundClass) {
    throw new Error('react-native-sound not available');
  }

  return new Promise((resolve, reject) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    currentSound = new SoundClass(uri, '', (error: any) => {
      if (error) {
        logger.error(`Failed to load sound: ${error}`);
        reject(error);
        return;
      }

      const durationMs = currentSound.getDuration() * 1000;
      isPlaying = true;

      if (callbacks?.onProgress) {
        playbackProgressInterval = setInterval(() => {
          currentSound?.getCurrentTime((seconds: number) => {
            callbacks?.onProgress?.(seconds * 1000, durationMs);
          });
        }, 100);
      }

      currentSound.play((success: boolean) => {
        isPlaying = false;
        if (playbackProgressInterval) {
          clearInterval(playbackProgressInterval);
          playbackProgressInterval = null;
        }

        if (currentSound) {
          currentSound.release();
          currentSound = null;
        }

        if (success) {
          callbacks?.onComplete?.();
          resolve();
        } else {
          reject(new Error('Playback failed'));
        }
      });
    });
  });
}

/**
 * Stop audio playback
 */
export async function stopPlayback(): Promise<void> {
  if (playbackProgressInterval) {
    clearInterval(playbackProgressInterval);
    playbackProgressInterval = null;
  }

  isPlaying = false;

  if (Platform.OS === 'ios' && NativeAudioModule) {
    try {
      await NativeAudioModule.stopPlayback();
    } catch {
      // Ignore
    }
  } else if (currentSound) {
    currentSound.stop();
    currentSound.release();
    currentSound = null;
  }
}

/**
 * Pause audio playback
 */
export async function pausePlayback(): Promise<void> {
  if (Platform.OS === 'ios' && NativeAudioModule) {
    try {
      await NativeAudioModule.pausePlayback();
    } catch {
      // Ignore
    }
  } else if (currentSound) {
    currentSound.pause();
  }
}

/**
 * Resume audio playback
 */
export async function resumePlayback(): Promise<void> {
  if (Platform.OS === 'ios' && NativeAudioModule) {
    try {
      await NativeAudioModule.resumePlayback();
    } catch {
      // Ignore
    }
  } else if (currentSound) {
    currentSound.play();
  }
}

// ============================================================================
// TTS Audio Utilities
// ============================================================================

/**
 * Convert base64 PCM float32 audio to WAV file
 * Used for TTS output which returns base64-encoded float32 PCM samples
 *
 * @param audioBase64 Base64 encoded float32 PCM audio data
 * @param sampleRate Sample rate of the audio (default: 22050)
 * @returns Path to the created WAV file
 */
export async function createWavFromPCMFloat32(
  audioBase64: string,
  sampleRate: number = TTS_SAMPLE_RATE
): Promise<string> {
  const fs = getRNFS();
  if (!fs) {
    throw new Error('react-native-fs not available');
  }

  // Decode base64 to get raw bytes
  const binaryString = atob(audioBase64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }

  // Convert float32 samples to int16 (WAV compatible)
  const floatView = new Float32Array(bytes.buffer);
  const numSamples = floatView.length;
  const int16Samples = new Int16Array(numSamples);

  for (let i = 0; i < numSamples; i++) {
    const floatSample = floatView[i] ?? 0;
    const sample = Math.max(-1, Math.min(1, floatSample));
    int16Samples[i] = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
  }

  // Create WAV file
  const wavDataSize = int16Samples.length * 2;
  const wavBuffer = new ArrayBuffer(44 + wavDataSize);
  const wavView = new DataView(wavBuffer);

  // RIFF header
  writeString(wavView, 0, 'RIFF');
  wavView.setUint32(4, 36 + wavDataSize, true);
  writeString(wavView, 8, 'WAVE');

  // fmt chunk
  writeString(wavView, 12, 'fmt ');
  wavView.setUint32(16, 16, true);
  wavView.setUint16(20, 1, true); // PCM
  wavView.setUint16(22, 1, true); // mono
  wavView.setUint32(24, sampleRate, true);
  wavView.setUint32(28, sampleRate * 2, true);
  wavView.setUint16(32, 2, true);
  wavView.setUint16(34, 16, true);

  // data chunk
  writeString(wavView, 36, 'data');
  wavView.setUint32(40, wavDataSize, true);

  // Copy audio data
  const wavBytes = new Uint8Array(wavBuffer);
  const int16Bytes = new Uint8Array(int16Samples.buffer);
  for (let i = 0; i < int16Bytes.length; i++) {
    wavBytes[44 + i] = int16Bytes[i]!;
  }

  // Write to file
  const fileName = `tts_${Date.now()}.wav`;
  const filePath = `${fs.CachesDirectoryPath}/${fileName}`;
  const wavBase64 = arrayBufferToBase64(wavBuffer);
  await fs.writeFile(filePath, wavBase64, 'base64');

  logger.info(`WAV file created: ${filePath}`);
  return filePath;
}

// ============================================================================
// Cleanup
// ============================================================================

/**
 * Cleanup all audio resources
 */
export async function cleanup(): Promise<void> {
  if (isRecording) {
    await cancelRecording();
  }
  await stopPlayback();
}

// ============================================================================
// Utilities
// ============================================================================

/**
 * Format milliseconds to MM:SS string
 */
export function formatDuration(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

// ============================================================================
// Private Helpers
// ============================================================================

function calculateAudioLevelFromBase64(base64Data: string): number {
  try {
    const bytes = Uint8Array.from(atob(base64Data), c => c.charCodeAt(0));
    const samples = new Int16Array(bytes.buffer);

    if (samples.length === 0) return -60;

    let sumSquares = 0;
    for (let i = 0; i < samples.length; i++) {
      const normalized = samples[i]! / 32768.0;
      sumSquares += normalized * normalized;
    }
    const rms = Math.sqrt(sumSquares / samples.length);
    const db = rms > 0 ? 20 * Math.log10(rms) : -60;
    return Math.max(-60, Math.min(0, db));
  } catch {
    return -60;
  }
}

async function createWavFileFromChunks(filePath: string, chunks: string[]): Promise<void> {
  const fs = getRNFS();
  if (!fs) {
    throw new Error('react-native-fs not available');
  }

  // Combine all audio chunks into PCM data
  let totalLength = 0;
  const decodedChunks: Uint8Array[] = [];

  for (const chunk of chunks) {
    const decoded = Uint8Array.from(atob(chunk), c => c.charCodeAt(0));
    decodedChunks.push(decoded);
    totalLength += decoded.length;
  }

  // Create combined PCM buffer
  const pcmData = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of decodedChunks) {
    pcmData.set(chunk, offset);
    offset += chunk.length;
  }

  // Create WAV header
  const wavHeader = createWavHeader(totalLength);
  const headerBytes = new Uint8Array(wavHeader);

  // Combine header and PCM data
  const wavData = new Uint8Array(headerBytes.length + pcmData.length);
  wavData.set(headerBytes, 0);
  wavData.set(pcmData, headerBytes.length);

  // Write to file
  const wavBase64 = arrayBufferToBase64(wavData.buffer);
  await fs.writeFile(filePath, wavBase64, 'base64');

  logger.info(`WAV file written: ${filePath}, size: ${wavData.length} bytes`);
}

function createWavHeader(dataLength: number): ArrayBuffer {
  const buffer = new ArrayBuffer(44);
  const view = new DataView(buffer);
  const sampleRate = AUDIO_SAMPLE_RATE;
  const byteRate = sampleRate * 2;

  writeString(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataLength, true);
  writeString(view, 8, 'WAVE');
  writeString(view, 12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeString(view, 36, 'data');
  view.setUint32(40, dataLength, true);

  return buffer;
}

function writeString(view: DataView, offset: number, str: string): void {
  for (let i = 0; i < str.length; i++) {
    view.setUint8(offset + i, str.charCodeAt(i));
  }
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary);
}
