import { EventEmitter } from 'eventemitter3';
import { Result, logger, AudioError } from '@runanywhere/core';
import type {
  TTSConfig,
  TTSOptions,
  SynthesisResult,
  SynthesisChunk,
  VoiceInfo,
  TTSEvents,
  StreamingOptions
} from '../types';

export class TTSService extends EventEmitter<TTSEvents> {
  private synthesizer?: SpeechSynthesis;
  private audioContext?: AudioContext;
  private config: Required<TTSConfig>;
  private isReady = false;
  private availableVoices: VoiceInfo[] = [];
  private currentUtterance?: SpeechSynthesisUtterance;

  constructor(config: Partial<TTSConfig> = {}) {
    super();
    this.config = {
      engine: 'web-speech',
      voice: 'default',
      rate: 1.0,
      pitch: 1.0,
      volume: 1.0,
      language: 'en-US',
      modelUrl: '',
      enableSSML: false,
      timeout: 30000,
      ...config
    };
  }

  async initialize(): Promise<Result<void, Error>> {
    try {
      this.emit('loading');

      // Check for Web Speech API support
      if (!('speechSynthesis' in window)) {
        throw new AudioError('Web Speech API not supported in this browser');
      }

      this.synthesizer = window.speechSynthesis;

      // Initialize audio context for advanced audio processing
      this.audioContext = new AudioContext({
        sampleRate: 44100,
        latencyHint: 'interactive'
      });

      // Load available voices
      await this.loadVoices();

      this.isReady = true;
      this.emit('ready');

      logger.info('TTS service initialized', 'TTS', {
        engine: this.config.engine,
        voiceCount: this.availableVoices.length
      });

      return Result.ok(undefined);

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Failed to initialize TTS service: ${err.message}`, 'TTS');
      this.emit('error', err);
      return Result.err(err);
    }
  }

  private async loadVoices(): Promise<void> {
    return new Promise((resolve) => {
      const loadVoicesInternal = () => {
        if (!this.synthesizer) {
          resolve();
          return;
        }

        const voices = this.synthesizer.getVoices();
        this.availableVoices = voices.map(voice => ({
          name: voice.name,
          language: voice.lang,
          gender: this.detectGender(voice.name),
          quality: voice.localService ? 'high' : 'medium',
          isDefault: voice.default,
          isLocal: voice.localService
        }));

        if (this.availableVoices.length > 0) {
          this.emit('voicesChanged', this.availableVoices);
          resolve();
        } else {
          // Retry after a short delay
          setTimeout(loadVoicesInternal, 100);
        }
      };

      // Listen for voices changed event
      if (this.synthesizer) {
        this.synthesizer.onvoiceschanged = loadVoicesInternal;
      }

      // Initial load
      loadVoicesInternal();
    });
  }

  private detectGender(voiceName: string): 'male' | 'female' | 'neutral' {
    const name = voiceName.toLowerCase();

    // Common patterns for gender detection
    if (name.includes('female') || name.includes('woman') ||
        name.includes('alice') || name.includes('samantha') ||
        name.includes('victoria') || name.includes('karen')) {
      return 'female';
    }

    if (name.includes('male') || name.includes('man') ||
        name.includes('tom') || name.includes('alex') ||
        name.includes('daniel') || name.includes('fred')) {
      return 'male';
    }

    return 'neutral';
  }

  async synthesize(
    text: string,
    options: TTSOptions = {}
  ): Promise<Result<SynthesisResult, Error>> {
    if (!this.isReady || !this.synthesizer || !this.audioContext) {
      return Result.err(new AudioError('TTS service not initialized'));
    }

    const startTime = performance.now();
    const config = { ...this.config, ...options };

    try {
      logger.debug('Starting TTS synthesis', 'TTS', {
        textLength: text.length,
        voice: config.voice,
        rate: config.rate
      });

      this.emit('synthesisStart', { text });

      // Create utterance
      const utterance = new SpeechSynthesisUtterance(text);
      this.currentUtterance = utterance;

      // Configure utterance
      if (config.voice !== 'default') {
        const voice = this.synthesizer.getVoices().find(v =>
          v.name === config.voice || v.name.includes(config.voice)
        );
        if (voice) {
          utterance.voice = voice;
        }
      }

      utterance.rate = config.rate;
      utterance.pitch = config.pitch;
      utterance.volume = config.volume;
      utterance.lang = config.language;

      // Create audio buffer for the result
      const audioBuffer = await this.synthesizeToBuffer(utterance);
      const processingTime = performance.now() - startTime;

      const result: SynthesisResult = {
        audioBuffer,
        duration: audioBuffer.duration,
        processingTime,
        voice: utterance.voice?.name || 'default',
        text
      };

      logger.info('TTS synthesis completed', 'TTS', {
        duration: `${result.duration.toFixed(2)}s`,
        processingTime: `${processingTime.toFixed(0)}ms`,
        textLength: text.length
      });

      this.emit('synthesisComplete', result);
      return Result.ok(result);

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`TTS synthesis failed: ${err.message}`, 'TTS');
      this.emit('error', err);
      return Result.err(err);
    } finally {
      this.currentUtterance = undefined;
    }
  }

  private async synthesizeToBuffer(utterance: SpeechSynthesisUtterance): Promise<AudioBuffer> {
    if (!this.synthesizer || !this.audioContext) {
      throw new Error('TTS service not properly initialized');
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('TTS synthesis timeout'));
      }, this.config.timeout);

      utterance.onend = () => {
        clearTimeout(timeout);
        // Since Web Speech API doesn't provide direct audio buffer access,
        // we create a simple audio buffer representation
        const sampleRate = this.audioContext!.sampleRate;
        const duration = this.estimateDuration(utterance.text);
        const buffer = this.audioContext!.createBuffer(1, duration * sampleRate, sampleRate);

        // Fill with silence - in a real implementation, you'd capture the audio
        const channelData = buffer.getChannelData(0);
        channelData.fill(0);

        resolve(buffer);
      };

      utterance.onerror = (event) => {
        clearTimeout(timeout);
        reject(new Error(`Speech synthesis error: ${event.error}`));
      };

      this.synthesizer!.speak(utterance);
    });
  }

  private estimateDuration(text: string): number {
    // Rough estimation: average speaking rate is ~150 words per minute
    const words = text.split(' ').length;
    const wordsPerSecond = 150 / 60;
    return Math.max(1, words / wordsPerSecond);
  }

  async synthesizeStream(
    text: string,
    options: StreamingOptions = {}
  ): Promise<Result<void, Error>> {
    if (!this.isReady || !this.synthesizer) {
      return Result.err(new AudioError('TTS service not initialized'));
    }

    try {
      // For streaming, we'll split text into sentences
      const sentences = this.splitIntoSentences(text);
      let sequence = 0;

      for (const sentence of sentences) {
        if (sentence.trim()) {
          const result = await this.synthesize(sentence, options);
          if (result.success) {
            const chunk: SynthesisChunk = {
              audioData: this.audioBufferToFloat32Array(result.value.audioBuffer),
              sequence: sequence++,
              isComplete: sequence === sentences.length,
              timestamp: Date.now()
            };
            this.emit('synthesisChunk', chunk);
          }
        }
      }

      return Result.ok(undefined);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      return Result.err(err);
    }
  }

  private splitIntoSentences(text: string): string[] {
    return text.split(/[.!?]+/).filter(s => s.trim().length > 0);
  }

  private audioBufferToFloat32Array(buffer: AudioBuffer): Float32Array {
    const length = buffer.length;
    const result = new Float32Array(length);
    const channelData = buffer.getChannelData(0);

    for (let i = 0; i < length; i++) {
      result[i] = channelData[i];
    }

    return result;
  }

  async play(audioBuffer: AudioBuffer): Promise<void> {
    if (!this.audioContext) {
      throw new Error('Audio context not initialized');
    }

    const source = this.audioContext.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(this.audioContext.destination);

    this.emit('playbackStart');

    return new Promise((resolve) => {
      source.onended = () => {
        this.emit('playbackEnd');
        resolve();
      };
      source.start();
    });
  }

  getAvailableVoices(): VoiceInfo[] {
    return [...this.availableVoices];
  }

  getPreferredVoice(language?: string): VoiceInfo | null {
    const lang = language || this.config.language;

    // Try to find a local voice first
    let voice = this.availableVoices.find(v =>
      v.language.startsWith(lang) && v.isLocal
    );

    // Fallback to any voice for the language
    if (!voice) {
      voice = this.availableVoices.find(v =>
        v.language.startsWith(lang)
      );
    }

    // Fallback to default voice
    if (!voice) {
      voice = this.availableVoices.find(v => v.isDefault);
    }

    return voice || null;
  }

  cancel(): void {
    if (this.synthesizer) {
      this.synthesizer.cancel();
    }

    if (this.currentUtterance) {
      this.currentUtterance = undefined;
    }
  }

  pause(): void {
    if (this.synthesizer) {
      this.synthesizer.pause();
    }
  }

  resume(): void {
    if (this.synthesizer) {
      this.synthesizer.resume();
    }
  }

  isHealthy(): boolean {
    return this.isReady && !!this.synthesizer && !!this.audioContext;
  }

  destroy(): void {
    this.cancel();

    if (this.audioContext && this.audioContext.state !== 'closed') {
      this.audioContext.close();
    }

    this.audioContext = undefined;
    this.synthesizer = undefined;
    this.isReady = false;
    this.removeAllListeners();

    logger.info('TTS service destroyed', 'TTS');
  }
}
