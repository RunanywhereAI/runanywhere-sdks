/**
 * AudioPlaybackManager.ts
 *
 * Internal audio playback used by `RunAnywhere.speak()` and
 * `RunAnywhere.stopSpeaking()`. Bridges the JS-only TTS PCM bytes through
 * platform audio (AVAudioPlayer on iOS, react-native-sound on Android).
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift`,
 * scaled down to just the playback verbs needed by the TTS extension.
 */

import { Platform, NativeModules } from 'react-native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('AudioPlaybackManager');

const NativeAudioModule = Platform.OS === 'ios' ? NativeModules.NativeAudioModule : null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let Sound: any = null;

function getSound() {
  if (Platform.OS === 'ios') return null;
  if (!Sound) {
    try {
      Sound = require('react-native-sound').default;
      Sound.setCategory('Playback');
    } catch {
      logger.warning('react-native-sound not available');
      return null;
    }
  }
  return Sound;
}

type PlaybackState = 'idle' | 'loading' | 'playing' | 'paused' | 'stopped' | 'error';

export class AudioPlaybackManager {
  private state: PlaybackState = 'idle';
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private currentSound: any = null;

  /**
   * Play raw PCM float32 audio (the format emitted by TTS) at the given
   * sample rate. Encodes to a 16-bit WAV on disk so platform audio can
   * decode it directly.
   */
  async play(audioData: ArrayBuffer | string, sampleRate = 22050): Promise<void> {
    if (this.state === 'playing') {
      this.stop();
    }

    this.state = 'loading';
    logger.info('Loading audio for playback...');

    try {
      const base64 =
        typeof audioData === 'string' ? audioData : arrayBufferToBase64(audioData);
      const wavPath = await createWavFromPCMFloat32(base64, sampleRate);
      await this.playFile(wavPath);
    } catch (error) {
      this.state = 'error';
      logger.error(
        `Playback failed: ${error instanceof Error ? error.message : String(error)}`
      );
      throw error;
    }
  }

  async playFile(filePath: string): Promise<void> {
    this.state = 'playing';
    logger.info(`Playing audio file: ${filePath}`);

    if (Platform.OS === 'ios') {
      await this.playFileIOS(filePath);
    } else {
      await this.playFileAndroid(filePath);
    }
  }

  stop(): void {
    if (this.state === 'idle' || this.state === 'stopped') return;

    logger.info('Stopping playback');
    this.state = 'stopped';

    if (Platform.OS === 'ios' && NativeAudioModule) {
      NativeAudioModule.stopPlayback().catch(() => {});
    } else if (this.currentSound) {
      this.currentSound.stop();
      this.currentSound.release();
      this.currentSound = null;
    }
  }

  private async playFileIOS(filePath: string): Promise<void> {
    if (!NativeAudioModule) {
      throw new Error('NativeAudioModule not available');
    }

    return new Promise((resolve, reject) => {
      NativeAudioModule.playAudio(filePath)
        .then(() => {
          const checkInterval = setInterval(async () => {
            if (this.state !== 'playing') {
              clearInterval(checkInterval);
              resolve();
              return;
            }
            try {
              const status = await NativeAudioModule.getPlaybackStatus();
              if (!status.isPlaying) {
                clearInterval(checkInterval);
                this.state = 'idle';
                resolve();
              }
            } catch {
              clearInterval(checkInterval);
              this.state = 'idle';
              resolve();
            }
          }, 100);
        })
        .catch((error: Error) => {
          this.state = 'error';
          reject(error);
        });
    });
  }

  private async playFileAndroid(filePath: string): Promise<void> {
    const SoundClass = getSound();
    if (!SoundClass) {
      throw new Error('react-native-sound not available');
    }

    return new Promise((resolve, reject) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      this.currentSound = new SoundClass(filePath, '', (error: any) => {
        if (error) {
          this.state = 'error';
          reject(error);
          return;
        }

        this.currentSound.play((success: boolean) => {
          if (this.currentSound) {
            this.currentSound.release();
            this.currentSound = null;
          }

          if (success) {
            this.state = 'idle';
            resolve();
          } else {
            this.state = 'error';
            reject(new Error('Playback failed'));
          }
        });
      });
    });
  }
}

async function createWavFromPCMFloat32(
  audioBase64: string,
  sampleRate: number
): Promise<string> {
  const RNFS = require('react-native-fs');

  const binaryString = atob(audioBase64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }

  const floatView = new Float32Array(bytes.buffer);
  const numSamples = floatView.length;
  const int16Samples = new Int16Array(numSamples);
  for (let i = 0; i < numSamples; i++) {
    const floatSample = floatView[i] ?? 0;
    const sample = Math.max(-1, Math.min(1, floatSample));
    int16Samples[i] = sample < 0 ? sample * 0x8000 : sample * 0x7fff;
  }

  const wavDataSize = int16Samples.length * 2;
  const wavBuffer = new ArrayBuffer(44 + wavDataSize);
  const wavView = new DataView(wavBuffer);

  writeString(wavView, 0, 'RIFF');
  wavView.setUint32(4, 36 + wavDataSize, true);
  writeString(wavView, 8, 'WAVE');

  writeString(wavView, 12, 'fmt ');
  wavView.setUint32(16, 16, true);
  wavView.setUint16(20, 1, true);
  wavView.setUint16(22, 1, true);
  wavView.setUint32(24, sampleRate, true);
  wavView.setUint32(28, sampleRate * 2, true);
  wavView.setUint16(32, 2, true);
  wavView.setUint16(34, 16, true);

  writeString(wavView, 36, 'data');
  wavView.setUint32(40, wavDataSize, true);

  const wavBytes = new Uint8Array(wavBuffer);
  const int16Bytes = new Uint8Array(int16Samples.buffer);
  for (let i = 0; i < int16Bytes.length; i++) {
    wavBytes[44 + i] = int16Bytes[i]!;
  }

  const fileName = `tts_${Date.now()}.wav`;
  const filePath = `${RNFS.CachesDirectoryPath}/${fileName}`;
  await RNFS.writeFile(filePath, arrayBufferToBase64(wavBuffer), 'base64');
  return filePath;
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
