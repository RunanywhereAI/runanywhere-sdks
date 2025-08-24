/**
 * Web Speech TTS Adapter Implementation
 * Uses the browser's built-in Web Speech API for text-to-speech
 */

import type {
  TTSAdapter,
  TTSConfig,
  TTSEvents,
  SynthesizeOptions,
  VoiceInfo,
  TTSMetrics
} from '../../interfaces/tts.interface';
import { Result } from '../../types/result';
import { BaseAdapter } from '../base.adapter';

export class WebSpeechTTSAdapter extends BaseAdapter<TTSEvents> implements TTSAdapter {
  readonly id = 'webspeech';
  readonly name = 'Web Speech API';
  readonly version = '1.0.0';

  private synth?: SpeechSynthesis;
  private currentUtterance?: SpeechSynthesisUtterance;
  private config?: TTSConfig;
  private metrics: TTSMetrics = {
    totalSyntheses: 0,
    avgProcessingTime: 0,
    totalCharacters: 0,
    lastSynthesisTime: undefined,
    totalSynthesisTime: 0,
    totalPlaybackTime: 0,
    synthesisCount: 0,
  };
  private isInitialized = false;
  private voices: SpeechSynthesisVoice[] = [];

  get supportedVoices(): VoiceInfo[] {
    return this.voices.map(voice => ({
      id: voice.voiceURI,
      name: voice.name,
      language: voice.lang,
      gender: this.inferGender(voice.name),
      localService: voice.localService,
    }));
  }

  async initialize(config?: TTSConfig): Promise<Result<void, Error>> {
    try {
      if (!('speechSynthesis' in window)) {
        return Result.err(new Error('Web Speech API not supported in this browser'));
      }

      this.synth = window.speechSynthesis;
      this.config = config;

      // Load available voices
      await this.loadVoices();

      this.isInitialized = true;
      return Result.ok(undefined);
    } catch (error) {
      return Result.err(error as Error);
    }
  }

  private async loadVoices(): Promise<void> {
    return new Promise((resolve) => {
      const loadVoicesList = () => {
        this.voices = this.synth?.getVoices() || [];
        if (this.voices.length > 0) {
          resolve();
        }
      };

      loadVoicesList();

      // Some browsers load voices asynchronously
      if (this.synth && this.voices.length === 0) {
        this.synth.onvoiceschanged = () => {
          loadVoicesList();
          resolve();
        };

        // Timeout fallback
        setTimeout(resolve, 1000);
      }
    });
  }

  private inferGender(voiceName: string): 'male' | 'female' | 'neutral' {
    const nameLower = voiceName.toLowerCase();
    if (nameLower.includes('female') || nameLower.includes('woman')) {
      return 'female';
    }
    if (nameLower.includes('male') || nameLower.includes('man')) {
      return 'male';
    }
    return 'neutral';
  }

  async synthesize(
    text: string,
    options?: SynthesizeOptions
  ): Promise<Result<AudioBuffer, Error>> {
    if (!this.isInitialized || !this.synth) {
      return Result.err(new Error('Adapter not initialized'));
    }

    try {
      const startTime = Date.now();
      this.emit('synthesis_start');

      // Create utterance
      const utterance = new SpeechSynthesisUtterance(text);

      // Configure voice
      if (options?.voice) {
        const voice = this.voices.find(v =>
          v.voiceURI === options.voice ||
          v.name === options.voice
        );
        if (voice) {
          utterance.voice = voice;
        }
      } else if (this.config?.defaultVoice) {
        const voice = this.voices.find(v =>
          v.voiceURI === this.config?.defaultVoice ||
          v.name === this.config?.defaultVoice
        );
        if (voice) {
          utterance.voice = voice;
        }
      }

      // Configure speech parameters
      utterance.rate = options?.rate ?? this.config?.rate ?? 1.0;
      utterance.pitch = options?.pitch ?? this.config?.pitch ?? 1.0;
      utterance.volume = options?.volume ?? this.config?.volume ?? 1.0;

      // Set language if specified
      if (options?.language) {
        utterance.lang = options.language;
      }

      // Web Speech API doesn't provide direct access to audio buffer
      // We'll simulate it by returning a placeholder
      // In a real implementation, you might use MediaRecorder to capture the audio

      this.currentUtterance = utterance;

      // Update metrics
      const synthesisTime = Date.now() - startTime;
      this.metrics.totalCharacters += text.length;
      this.metrics.totalSyntheses++;
      if (this.metrics.totalSynthesisTime !== undefined) {
        this.metrics.totalSynthesisTime += synthesisTime;
      }
      if (this.metrics.synthesisCount !== undefined) {
        this.metrics.synthesisCount++;
      }
      this.metrics.avgProcessingTime =
        (this.metrics.avgProcessingTime * (this.metrics.totalSyntheses - 1) + synthesisTime) /
        this.metrics.totalSyntheses;
      this.metrics.lastSynthesisTime = Date.now();

      this.emit('synthesis_progress', 100);
      this.emit('synthesis_end');

      // Return a mock AudioBuffer (Web Speech API doesn't provide actual audio data)
      // In production, you'd need to use a different approach or adapter for audio access
      const audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();
      const duration = text.length * 0.06; // Rough estimate: 60ms per character
      const sampleRate = audioContext.sampleRate;
      const buffer = audioContext.createBuffer(1, sampleRate * duration, sampleRate);

      return Result.ok(buffer);
    } catch (error) {
      this.emit('error', error as Error);
      return Result.err(error as Error);
    }
  }

  async play(audioBuffer?: AudioBuffer): Promise<Result<void, Error>> {
    if (!this.isInitialized || !this.synth) {
      return Result.err(new Error('Adapter not initialized'));
    }

    // With Web Speech API, we use the utterance directly
    if (!this.currentUtterance) {
      return Result.err(new Error('No utterance to play'));
    }

    return new Promise((resolve) => {
      const utterance = this.currentUtterance!;
      const startTime = Date.now();

      utterance.onstart = () => {
        this.emit('playback_start');
      };

      utterance.onend = () => {
        const playbackTime = Date.now() - startTime;
        if (this.metrics.totalPlaybackTime !== undefined) {
          this.metrics.totalPlaybackTime += playbackTime;
        }
        this.emit('playback_end');
        resolve(Result.ok(undefined));
      };

      utterance.onerror = (event) => {
        this.emit('error', new Error(event.error));
        resolve(Result.err(new Error(event.error)));
      };

      // Cancel any ongoing speech
      this.synth?.cancel();

      // Speak the utterance
      this.synth?.speak(utterance);
    });
  }

  async synthesizeAndPlay(
    text: string,
    options?: SynthesizeOptions
  ): Promise<Result<void, Error>> {
    if (!this.isInitialized || !this.synth) {
      return Result.err(new Error('Adapter not initialized'));
    }

    try {
      const startTime = Date.now();

      // For Web Speech API, synthesis and playback are combined
      this.emit('synthesis_start');

      const utterance = new SpeechSynthesisUtterance(text);

      // Configure voice and parameters
      if (options?.voice) {
        const voice = this.voices.find(v =>
          v.voiceURI === options.voice ||
          v.name === options.voice
        );
        if (voice) {
          utterance.voice = voice;
        }
      }

      utterance.rate = options?.rate ?? this.config?.rate ?? 1.0;
      utterance.pitch = options?.pitch ?? this.config?.pitch ?? 1.0;
      utterance.volume = options?.volume ?? this.config?.volume ?? 1.0;

      if (options?.language) {
        utterance.lang = options.language;
      }

      return new Promise((resolve) => {
        utterance.onstart = () => {
          this.emit('synthesis_end');
          this.emit('playback_start');
        };

        utterance.onend = () => {
          const totalTime = Date.now() - startTime;
          this.metrics.totalCharacters += text.length;
          this.metrics.totalSyntheses++;
          if (this.metrics.totalSynthesisTime !== undefined) {
            this.metrics.totalSynthesisTime += totalTime;
          }
          if (this.metrics.totalPlaybackTime !== undefined) {
            this.metrics.totalPlaybackTime += totalTime;
          }
          if (this.metrics.synthesisCount !== undefined) {
            this.metrics.synthesisCount++;
          }
          this.metrics.avgProcessingTime =
            (this.metrics.avgProcessingTime * (this.metrics.totalSyntheses - 1) + totalTime) /
            this.metrics.totalSyntheses;
          this.metrics.lastSynthesisTime = Date.now();

          this.emit('playback_end');
          resolve(Result.ok(undefined));
        };

        utterance.onerror = (event) => {
          this.emit('error', new Error(event.error));
          resolve(Result.err(new Error(event.error)));
        };

        // Cancel any ongoing speech
        this.synth?.cancel();

        // Speak
        this.synth?.speak(utterance);
      });
    } catch (error) {
      this.emit('error', error as Error);
      return Result.err(error as Error);
    }
  }

  stop(): void {
    if (this.synth) {
      this.synth.cancel();
      this.currentUtterance = undefined;
    }
  }

  pause(): void {
    if (this.synth) {
      this.synth.pause();
    }
  }

  resume(): void {
    if (this.synth) {
      this.synth.resume();
    }
  }

  destroy(): void {
    this.stop();
    this.synth = undefined;
    this.voices = [];
    this.config = undefined;
    this.isInitialized = false;
    this.removeAllListeners();
  }

  isHealthy(): boolean {
    return this.isInitialized && !!this.synth && !this.synth.paused;
  }

  getMetrics(): TTSMetrics {
    return { ...this.metrics };
  }
}

// Metadata for registry
export const WebSpeechTTSAdapterMetadata = {
  id: 'webspeech',
  name: 'Web Speech API',
  version: '1.0.0',
  description: 'Browser built-in text-to-speech using Web Speech API',
  offline: true,
  requiresApiKey: false,
  features: {
    voices: 'Browser-dependent',
    languages: 'Browser-dependent',
    customizable: true,
    streaming: false,
    audioAccess: false,
  },
  browserSupport: {
    chrome: true,
    firefox: true,
    safari: true,
    edge: true,
  },
};
