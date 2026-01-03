/**
 * @runanywhere/onnx - ONNX Providers
 *
 * ONNX Runtime service providers for React Native SDK.
 * Handles STT (Speech-to-Text) and TTS (Text-to-Speech) models via Sherpa-ONNX.
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXServiceProvider.swift
 */

import {
  type ModelInfo,
  LLMFramework,
  ModelCategory,
  ServiceRegistry,
  type STTServiceProvider,
  type TTSServiceProvider,
  type STTService,
  type TTSService,
  type STTConfiguration,
  type TTSConfig as TTSConfiguration,
  SDKError,
  SDKErrorCode,
} from '@runanywhere/core';

// Simple logger for this package
const DEBUG = typeof __DEV__ !== 'undefined' ? __DEV__ : false;
const log = {
  stt: {
    info: (msg: string) => DEBUG && console.log(`[ONNXSTTProvider] ${msg}`),
    debug: (msg: string) => DEBUG && console.log(`[ONNXSTTProvider] ${msg}`),
  },
  tts: {
    info: (msg: string) => DEBUG && console.log(`[ONNXTTSProvider] ${msg}`),
    debug: (msg: string) => DEBUG && console.log(`[ONNXTTSProvider] ${msg}`),
  },
  main: {
    info: (msg: string) => DEBUG && console.log(`[ONNXProvider] ${msg}`),
  },
};

/**
 * ONNX STT Service Provider
 *
 * This provider handles Speech-to-Text models through the Sherpa-ONNX backend.
 * Mirrors Swift SDK's ONNXSTTServiceProvider pattern.
 */
export class ONNXSTTProvider implements STTServiceProvider {
  readonly name = 'ONNX Runtime STT';
  readonly version = '1.23.2';

  private static _instance: ONNXSTTProvider | null = null;

  static get shared(): ONNXSTTProvider {
    if (!ONNXSTTProvider._instance) {
      ONNXSTTProvider._instance = new ONNXSTTProvider();
    }
    return ONNXSTTProvider._instance;
  }

  /**
   * Register the ONNX STT provider with ServiceRegistry
   */
  static register(): void {
    log.stt.info('Registering ONNX STT service provider');

    // Register with priority 90 (slightly lower than LlamaCpp)
    ServiceRegistry.shared.registerSTTProvider(ONNXSTTProvider.shared, 90);

    log.stt.info('ONNX STT service provider registered successfully');
  }

  /**
   * Create an STT service for the given configuration
   */
  async createSTTService(_configuration: STTConfiguration): Promise<STTService> {
    throw new SDKError(
      SDKErrorCode.NotImplemented,
      'ONNX STT service creation not yet implemented. Use RunAnywhere.loadSTTModel() instead.'
    );
  }

  /**
   * Check if this provider can handle the given model
   */
  canHandle(modelId: string | null | undefined): boolean {
    if (!modelId) {
      return false;
    }

    const lowercased = modelId.toLowerCase();

    // Whisper models (ONNX format)
    if (lowercased.includes('whisper') && !lowercased.includes('whisperkit')) {
      return true;
    }

    // Sherpa-ONNX models
    if (
      lowercased.includes('sherpa-onnx') ||
      lowercased.includes('sherpa_onnx')
    ) {
      return true;
    }

    // ONNX format explicitly
    if (lowercased.includes('.onnx') || lowercased.includes('onnx')) {
      const speechKeywords = [
        'whisper',
        'stt',
        'asr',
        'speech',
        'transcription',
      ];
      if (speechKeywords.some((kw) => lowercased.includes(kw))) {
        return true;
      }
    }

    return false;
  }

  /**
   * Get models provided by this provider
   */
  getProvidedModels(): ModelInfo[] {
    // For now, return empty array - models are registered via ONNX.addModel()
    log.stt.debug('Providing registered STT models');
    return [];
  }

  /**
   * Lifecycle hook called when provider is registered
   */
  onRegistration(): void {
    log.stt.debug('onRegistration() called');
    const models = this.getProvidedModels();
    log.stt.info(`Registered ${models.length} STT models through provider`);
  }
}

/**
 * ONNX TTS Service Provider
 *
 * This provider handles Text-to-Speech models through the Sherpa-ONNX backend.
 * Mirrors Swift SDK's ONNXTTSServiceProvider pattern.
 */
export class ONNXTTSProvider implements TTSServiceProvider {
  readonly name = 'ONNX Runtime TTS';
  readonly version = '1.23.2';

  private static _instance: ONNXTTSProvider | null = null;

  static get shared(): ONNXTTSProvider {
    if (!ONNXTTSProvider._instance) {
      ONNXTTSProvider._instance = new ONNXTTSProvider();
    }
    return ONNXTTSProvider._instance;
  }

  /**
   * Register the ONNX TTS provider with ServiceRegistry
   */
  static register(): void {
    log.tts.info('Registering ONNX TTS service provider');

    // Register with priority 90 (slightly lower than system TTS)
    ServiceRegistry.shared.registerTTSProvider(ONNXTTSProvider.shared, 90);

    log.tts.info('ONNX TTS service provider registered successfully');
  }

  /**
   * Create a TTS service for the given configuration
   */
  async createTTSService(_configuration: TTSConfiguration): Promise<TTSService> {
    throw new SDKError(
      SDKErrorCode.NotImplemented,
      'ONNX TTS service creation not yet implemented. Use RunAnywhere.loadTTSModel() instead.'
    );
  }

  /**
   * Check if this provider can handle the given model
   */
  canHandle(modelId: string | null | undefined): boolean {
    if (!modelId) {
      return false;
    }

    const lowercased = modelId.toLowerCase();

    // Piper TTS models
    if (lowercased.includes('piper') || lowercased.includes('vits')) {
      return true;
    }

    // Sherpa-ONNX TTS models
    if (
      lowercased.includes('sherpa-onnx') ||
      lowercased.includes('sherpa_onnx')
    ) {
      return true;
    }

    // ONNX format explicitly for TTS
    if (lowercased.includes('.onnx') || lowercased.includes('onnx')) {
      const ttsKeywords = ['tts', 'speech', 'synthesis', 'voice'];
      if (ttsKeywords.some((kw) => lowercased.includes(kw))) {
        return true;
      }
    }

    return false;
  }

  /**
   * Get models provided by this provider
   */
  getProvidedModels(): ModelInfo[] {
    // For now, return empty array - models are registered via ONNX.addModel()
    log.tts.debug('Providing registered TTS models');
    return [];
  }

  /**
   * Lifecycle hook called when provider is registered
   */
  onRegistration(): void {
    log.tts.debug('onRegistration() called');
    const models = this.getProvidedModels();
    log.tts.info(`Registered ${models.length} TTS models through provider`);
  }
}

/**
 * Register all ONNX providers
 * Called during SDK initialization to register both STT and TTS providers.
 *
 * Mirrors Swift SDK's ONNXAdapter.register() pattern.
 */
export function registerONNXProviders(): void {
  log.main.info('Registering all ONNX providers...');
  ONNXSTTProvider.register();
  ONNXTTSProvider.register();
  log.main.info('All ONNX providers registered');
}
