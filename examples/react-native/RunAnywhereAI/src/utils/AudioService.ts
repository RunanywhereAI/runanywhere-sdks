/**
 * AudioService - Audio recording and playback utilities
 *
 * Provides a unified interface for audio operations needed by:
 * - STTScreen: Record audio for transcription
 * - TTSScreen: Play synthesized audio
 * - VoiceAssistantScreen: Full pipeline with record + play
 *
 * Platform-specific implementations:
 * - iOS: Native AVFoundation module (NativeAudioModule)
 * - Android: react-native-live-audio-stream for raw PCM recording
 */

import { Platform, PermissionsAndroid, NativeModules } from 'react-native';
import RNFS from 'react-native-fs';

// Native iOS Audio Module
const NativeAudioModule =
  Platform.OS === 'ios' ? NativeModules.NativeAudioModule : null;

// Lazy load LiveAudioStream (Android only)
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let LiveAudioStream: any = null;

function getLiveAudioStream() {
  if (Platform.OS !== 'android') {
    return null;
  }
  if (!LiveAudioStream) {
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      LiveAudioStream = require('react-native-live-audio-stream').default;
    } catch (e) {
      console.error('[AudioService] Failed to load LiveAudioStream:', e);
      return null;
    }
  }
  return LiveAudioStream;
}

// Audio configuration for speech recognition
export const SAMPLE_RATE = 16000; // Required by Whisper models
const CHANNELS = 1;
const BITS_PER_SAMPLE = 16;

let isRecording = false;
let recordingStartTime = 0;
let currentRecordPath: string | null = null;
let audioChunks: string[] = [];
let progressCallback:
  | ((currentPositionMs: number, metering?: number) => void)
  | null = null;
let audioLevelInterval: ReturnType<typeof setInterval> | null = null;

/**
 * Calculate RMS (Root Mean Square) audio level from PCM data
 * Returns a value in dB (typically -60 to 0)
 */
function calculateAudioLevel(base64Data: string): number {
  try {
    // Decode base64 to bytes
    const bytes = Uint8Array.from(atob(base64Data), (c) => c.charCodeAt(0));

    // Convert to 16-bit signed integers
    const samples = new Int16Array(bytes.buffer);

    if (samples.length === 0) return -60;

    // Calculate RMS
    let sumSquares = 0;
    for (let i = 0; i < samples.length; i++) {
      const normalized = samples[i] / 32768.0; // Normalize to -1 to 1
      sumSquares += normalized * normalized;
    }
    const rms = Math.sqrt(sumSquares / samples.length);

    // Convert to dB (with floor at -60 dB)
    const db = rms > 0 ? 20 * Math.log10(rms) : -60;
    return Math.max(-60, Math.min(0, db));
  } catch (e) {
    return -60;
  }
}

/**
 * Request microphone permission
 */
export async function requestAudioPermission(): Promise<boolean> {
  if (Platform.OS === 'android') {
    try {
      const grants = await PermissionsAndroid.requestMultiple([
        PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
        PermissionsAndroid.PERMISSIONS.WRITE_EXTERNAL_STORAGE,
        PermissionsAndroid.PERMISSIONS.READ_EXTERNAL_STORAGE,
      ]);

      const recordGranted =
        grants[PermissionsAndroid.PERMISSIONS.RECORD_AUDIO] ===
        PermissionsAndroid.RESULTS.GRANTED;
      console.warn('[AudioService] Android permission granted:', recordGranted);
      return recordGranted;
    } catch (err) {
      console.error('[AudioService] Permission request error:', err);
      return false;
    }
  }

  // iOS: Permissions are requested automatically when starting recording
  return true;
}

export interface RecordingCallbacks {
  onProgress?: (currentPositionMs: number, metering?: number) => void;
}

/**
 * Create WAV header for PCM data
 */
function createWavHeader(dataLength: number): ArrayBuffer {
  const buffer = new ArrayBuffer(44);
  const view = new DataView(buffer);

  const sampleRate = SAMPLE_RATE;
  const numChannels = CHANNELS;
  const bitsPerSample = BITS_PER_SAMPLE;
  const byteRate = sampleRate * numChannels * (bitsPerSample / 8);
  const blockAlign = numChannels * (bitsPerSample / 8);

  // "RIFF" chunk descriptor
  writeString(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataLength, true); // File size - 8
  writeString(view, 8, 'WAVE');

  // "fmt " sub-chunk
  writeString(view, 12, 'fmt ');
  view.setUint32(16, 16, true); // Subchunk1Size (16 for PCM)
  view.setUint16(20, 1, true); // AudioFormat (1 = PCM)
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);

  // "data" sub-chunk
  writeString(view, 36, 'data');
  view.setUint32(40, dataLength, true);

  return buffer;
}

function writeString(view: DataView, offset: number, string: string): void {
  for (let i = 0; i < string.length; i++) {
    view.setUint8(offset + i, string.charCodeAt(i));
  }
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/**
 * Start recording audio
 * Returns the URI where the audio will be saved
 *
 * Platform support:
 * - iOS: NativeAudioModule (AVFoundation)
 * - Android: react-native-live-audio-stream (raw PCM for STT WAV format)
 */
export async function startRecording(
  callbacks?: RecordingCallbacks
): Promise<string> {
  return new Promise(async (resolve, reject) => {
    try {
      // iOS: Use native audio module
      if (Platform.OS === 'ios') {
        console.warn('[AudioService] iOS: Starting native recording...');

        if (!NativeAudioModule) {
          console.error('[AudioService] iOS: NativeAudioModule not available');
          reject(new Error('Native audio module not available on iOS'));
          return;
        }

        try {
          const result = await NativeAudioModule.startRecording();
          console.warn('[AudioService] iOS: Recording started:', result);

          isRecording = true;
          recordingStartTime = Date.now();
          currentRecordPath = result.path;
          progressCallback = callbacks?.onProgress || null;

          // Poll for audio levels on iOS
          if (progressCallback) {
            audioLevelInterval = setInterval(async () => {
              if (isRecording && NativeAudioModule) {
                try {
                  const levelResult = await NativeAudioModule.getAudioLevel();
                  const elapsed = Date.now() - recordingStartTime;
                  // Convert linear level (0-1) to dB (-60 to 0)
                  const db =
                    levelResult.level > 0
                      ? 20 * Math.log10(levelResult.level)
                      : -60;
                  progressCallback?.(elapsed, db);
                } catch (e) {
                  // Ignore errors
                }
              }
            }, 100);
          }

          resolve(result.path);
        } catch (error: unknown) {
          console.error(
            '[AudioService] iOS: Failed to start recording:',
            error
          );
          reject(error);
        }
        return;
      }

      // Android: Use LiveAudioStream for raw PCM
      console.warn('[AudioService] Android: Starting live audio stream...');

      const fileName = `recording_${Date.now()}.wav`;
      const filePath = `${RNFS.CachesDirectoryPath}/${fileName}`;
      currentRecordPath = filePath;
      audioChunks = [];

      const audioStream = getLiveAudioStream();

      if (!audioStream) {
        reject(new Error('Audio stream not available'));
        return;
      }

      // Initialize live audio stream
      audioStream.init({
        sampleRate: SAMPLE_RATE,
        channels: CHANNELS,
        bitsPerSample: BITS_PER_SAMPLE,
        audioSource: 6, // VOICE_RECOGNITION
        bufferSize: 4096,
      });

      // Store callback for use in data handler
      progressCallback = callbacks?.onProgress || null;

      // Listen for audio data
      audioStream.on('data', (data: string) => {
        audioChunks.push(data);

        if (progressCallback) {
          const elapsed = Date.now() - recordingStartTime;
          const audioLevel = calculateAudioLevel(data);
          progressCallback(elapsed, audioLevel);
        }
      });

      // Start recording
      audioStream.start();
      isRecording = true;
      recordingStartTime = Date.now();

      console.warn('[AudioService] Android recording started:', filePath);
      resolve(filePath);
    } catch (error) {
      console.error('[AudioService] Failed to start recording:', error);
      reject(error);
    }
  });
}

/**
 * Stop recording and return the audio URI and duration
 */
export async function stopRecording(): Promise<{
  uri: string;
  durationMs: number;
}> {
  if (!isRecording) {
    throw new Error('No recording in progress');
  }

  try {
    // Clear iOS audio level polling
    if (audioLevelInterval) {
      clearInterval(audioLevelInterval);
      audioLevelInterval = null;
    }

    // iOS: Use native audio module
    if (Platform.OS === 'ios' && NativeAudioModule) {
      console.warn('[AudioService] iOS: Stopping native recording...');

      const result = await NativeAudioModule.stopRecording();
      const durationMs = Date.now() - recordingStartTime;

      isRecording = false;
      progressCallback = null;

      console.warn('[AudioService] iOS: Recording stopped:', result);
      return { uri: result.path, durationMs };
    }

    // Android: Stop LiveAudioStream
    const audioStream = getLiveAudioStream();
    if (audioStream) {
      audioStream.stop();
    }
    isRecording = false;

    const durationMs = Date.now() - recordingStartTime;
    const uri = currentRecordPath || '';

    console.warn(
      '[AudioService] Recording stopped, processing',
      audioChunks.length,
      'chunks'
    );

    // Combine all audio chunks into PCM data
    let totalLength = 0;
    const decodedChunks: Uint8Array[] = [];

    for (const chunk of audioChunks) {
      const decoded = Uint8Array.from(atob(chunk), (c) => c.charCodeAt(0));
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

    console.warn('[AudioService] Total PCM data:', totalLength, 'bytes');

    // Create WAV header
    const wavHeader = createWavHeader(totalLength);
    const headerBytes = new Uint8Array(wavHeader);

    // Combine header and PCM data
    const wavData = new Uint8Array(headerBytes.length + pcmData.length);
    wavData.set(headerBytes, 0);
    wavData.set(pcmData, headerBytes.length);

    // Convert to base64 and write to file
    const wavBase64 = arrayBufferToBase64(wavData.buffer);
    await RNFS.writeFile(uri, wavBase64, 'base64');

    console.warn(
      '[AudioService] WAV file written:',
      uri,
      'size:',
      wavData.length
    );

    // Clean up
    audioChunks = [];
    currentRecordPath = null;
    progressCallback = null;

    return { uri, durationMs };
  } catch (error) {
    console.error('[AudioService] Failed to stop recording:', error);
    isRecording = false;
    audioChunks = [];
    currentRecordPath = null;
    progressCallback = null;
    throw error;
  }
}

/**
 * Cancel recording
 */
export async function cancelRecording(): Promise<void> {
  // Clear iOS audio level polling
  if (audioLevelInterval) {
    clearInterval(audioLevelInterval);
    audioLevelInterval = null;
  }

  if (isRecording) {
    try {
      // iOS: Use native audio module
      if (Platform.OS === 'ios' && NativeAudioModule) {
        await NativeAudioModule.cancelRecording();
      } else {
        // Android: Stop LiveAudioStream
        const audioStream = getLiveAudioStream();
        if (audioStream) {
          audioStream.stop();
        }

        // Delete the partial recording file
        if (currentRecordPath) {
          try {
            await RNFS.unlink(currentRecordPath);
          } catch (e) {
            // File may not exist, ignore
          }
        }
      }
    } catch (error) {
      console.error('[AudioService] Failed to cancel recording:', error);
    }
    isRecording = false;
    audioChunks = [];
    currentRecordPath = null;
    progressCallback = null;
  }
}

export interface PlaybackCallbacks {
  onProgress?: (currentPositionMs: number, durationMs: number) => void;
  onComplete?: () => void;
}

// Track playback state
let isPlaying = false;
let playbackProgressInterval: ReturnType<typeof setInterval> | null = null;

/**
 * Play audio from URI
 *
 * Platform support:
 * - iOS: NativeAudioModule (AVAudioPlayer)
 * - Android: react-native-sound (if available)
 */
export async function playAudio(
  uri: string,
  callbacks?: PlaybackCallbacks
): Promise<void> {
  console.warn('[AudioService] Playing audio:', uri);

  // iOS: Use native audio module
  if (Platform.OS === 'ios' && NativeAudioModule) {
    try {
      const result = await NativeAudioModule.playAudio(uri);
      isPlaying = true;

      const duration = (result.duration || 0) * 1000; // Convert to ms

      // Poll for playback progress
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
            const durationMs = (status.duration || 0) * 1000;

            callbacks?.onProgress?.(currentTimeMs, durationMs);

            if (!status.isPlaying && currentTimeMs >= durationMs - 100) {
              isPlaying = false;
              if (playbackProgressInterval) {
                clearInterval(playbackProgressInterval);
                playbackProgressInterval = null;
              }
              callbacks?.onComplete?.();
            }
          } catch (e) {
            // Ignore errors
          }
        }, 100);
      }

      console.warn('[AudioService] iOS: Playback started, duration:', duration);
    } catch (error) {
      console.error('[AudioService] iOS: Failed to play audio:', error);
      throw error;
    }
    return;
  }

  // Android: Use react-native-sound if available
  console.warn('[AudioService] Android: Playback via react-native-sound');
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const Sound = require('react-native-sound').default;
    Sound.setCategory('Playback');

    return new Promise((resolve, reject) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const sound = new Sound(uri, '', (error: any) => {
        if (error) {
          console.error('[AudioService] Failed to load sound:', error);
          reject(error);
          return;
        }

        const duration = sound.getDuration() * 1000;
        isPlaying = true;

        // Progress polling
        if (callbacks?.onProgress) {
          playbackProgressInterval = setInterval(() => {
            sound.getCurrentTime((seconds: number) => {
              callbacks?.onProgress?.(seconds * 1000, duration);
            });
          }, 100);
        }

        sound.play((success: boolean) => {
          isPlaying = false;
          if (playbackProgressInterval) {
            clearInterval(playbackProgressInterval);
            playbackProgressInterval = null;
          }

          if (success) {
            callbacks?.onComplete?.();
            resolve();
          } else {
            reject(new Error('Playback failed'));
          }
          sound.release();
        });
      });
    });
  } catch (e) {
    console.warn('[AudioService] react-native-sound not available:', e);
    throw new Error('Audio playback not available');
  }
}

/**
 * Stop playback
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
    } catch (e) {
      // Ignore errors
    }
  }
}

/**
 * Pause playback
 */
export async function pausePlayback(): Promise<void> {
  if (Platform.OS === 'ios' && NativeAudioModule) {
    try {
      await NativeAudioModule.pausePlayback();
    } catch (e) {
      // Ignore errors
    }
  }
}

/**
 * Resume playback
 */
export async function resumePlayback(): Promise<void> {
  if (Platform.OS === 'ios' && NativeAudioModule) {
    try {
      await NativeAudioModule.resumePlayback();
    } catch (e) {
      // Ignore errors
    }
  }
}

/**
 * Cleanup resources
 */
export async function cleanup(): Promise<void> {
  if (isRecording) {
    await cancelRecording();
  }
  await stopPlayback();
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
