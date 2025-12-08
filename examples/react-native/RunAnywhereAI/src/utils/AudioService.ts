/**
 * AudioService - Audio recording and playback utilities
 *
 * Provides a unified interface for audio operations needed by:
 * - STTScreen: Record audio for transcription
 * - TTSScreen: Play synthesized audio
 * - VoiceAssistantScreen: Full pipeline with record + play
 *
 * Uses react-native-live-audio-stream for raw PCM recording
 * and creates WAV files for transcription compatibility
 */

import { Platform, PermissionsAndroid } from 'react-native';
import LiveAudioStream from 'react-native-live-audio-stream';
import RNFS from 'react-native-fs';

// Audio configuration for speech recognition
export const SAMPLE_RATE = 16000; // Required by Whisper models
const CHANNELS = 1;
const BITS_PER_SAMPLE = 16;

let isRecording = false;
let recordingStartTime = 0;
let currentRecordPath: string | null = null;
let audioChunks: string[] = [];
let progressCallback: ((currentPositionMs: number, metering?: number) => void) | null = null;

/**
 * Calculate RMS (Root Mean Square) audio level from PCM data
 * Returns a value in dB (typically -60 to 0)
 */
function calculateAudioLevel(base64Data: string): number {
  try {
    // Decode base64 to bytes
    const bytes = Uint8Array.from(atob(base64Data), c => c.charCodeAt(0));
    
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

      const recordGranted = grants[PermissionsAndroid.PERMISSIONS.RECORD_AUDIO] === PermissionsAndroid.RESULTS.GRANTED;
      console.log('[AudioService] Android permission granted:', recordGranted);
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
 */
export async function startRecording(callbacks?: RecordingCallbacks): Promise<string> {
  return new Promise((resolve, reject) => {
    try {
      console.log('[AudioService] Starting live audio stream...');
      
      // Generate file path
      const fileName = `recording_${Date.now()}.wav`;
      const filePath = Platform.select({
        ios: `${RNFS.DocumentDirectoryPath}/${fileName}`,
        android: `${RNFS.CachesDirectoryPath}/${fileName}`,
      })!;

      currentRecordPath = filePath;
      audioChunks = [];
      
      // Initialize live audio stream
      LiveAudioStream.init({
        sampleRate: SAMPLE_RATE,
        channels: CHANNELS,
        bitsPerSample: BITS_PER_SAMPLE,
        audioSource: 6, // VOICE_RECOGNITION
        bufferSize: 4096,
      });

      // Store callback for use in data handler
      progressCallback = callbacks?.onProgress || null;

      // Listen for audio data
      LiveAudioStream.on('data', (data: string) => {
        audioChunks.push(data);
        
        if (progressCallback) {
          const elapsed = Date.now() - recordingStartTime;
          const audioLevel = calculateAudioLevel(data);
          progressCallback(elapsed, audioLevel);
        }
      });

      // Start recording
      LiveAudioStream.start();
      isRecording = true;
      recordingStartTime = Date.now();

      console.log('[AudioService] Recording started:', filePath);
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
export async function stopRecording(): Promise<{ uri: string; durationMs: number }> {
  if (!isRecording) {
    throw new Error('No recording in progress');
  }

  try {
    // Stop the stream
    LiveAudioStream.stop();
    isRecording = false;
    
    const durationMs = Date.now() - recordingStartTime;
    const uri = currentRecordPath || '';

    console.log('[AudioService] Recording stopped, processing', audioChunks.length, 'chunks');

    // Combine all audio chunks into PCM data
    let totalLength = 0;
    const decodedChunks: Uint8Array[] = [];
    
    for (const chunk of audioChunks) {
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

    console.log('[AudioService] Total PCM data:', totalLength, 'bytes');

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

    console.log('[AudioService] WAV file written:', uri, 'size:', wavData.length);

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
  if (isRecording) {
    try {
      LiveAudioStream.stop();
      
      // Delete the partial recording file
      if (currentRecordPath) {
        try {
          await RNFS.unlink(currentRecordPath);
        } catch (e) {
          // File may not exist, ignore
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

/**
 * Play audio from URI
 * Note: For now, playback is not implemented - can be added with react-native-sound if needed
 */
export async function playAudio(uri: string, callbacks?: PlaybackCallbacks): Promise<void> {
  console.log('[AudioService] Playback not implemented yet:', uri);
  // TODO: Implement playback if needed using react-native-sound
}

/**
 * Stop playback
 */
export async function stopPlayback(): Promise<void> {
  // TODO: Implement if playback is added
}

/**
 * Pause playback
 */
export async function pausePlayback(): Promise<void> {
  // TODO: Implement if playback is added
}

/**
 * Resume playback
 */
export async function resumePlayback(): Promise<void> {
  // TODO: Implement if playback is added
}

/**
 * Cleanup resources
 */
export async function cleanup(): Promise<void> {
  if (isRecording) {
    await cancelRecording();
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
