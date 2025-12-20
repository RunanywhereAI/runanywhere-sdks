/**
 * ONNXProvider.ts
 *
 * ONNX Runtime service provider for React Native SDK.
 * Handles STT (Speech-to-Text) and TTS (Text-to-Speech) models via Sherpa-ONNX.
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXServiceProvider.swift
 *            sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXAdapter.swift
 */

import type { ModelInfo } from '../types';
import { LLMFramework, ModelCategory } from '../types';
import { getCatalogModelsByFramework } from '../Data/modelCatalog';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

const sttLogger = new SDKLogger('ONNXSTTProvider');
const ttsLogger = new SDKLogger('ONNXTTSProvider');
const providerLogger = new SDKLogger('ONNXProvider');

/**
 * ONNX STT Service Provider
 *
 * This provider handles Speech-to-Text models through the Sherpa-ONNX backend.
 * Mirrors Swift SDK's ONNXSTTServiceProvider pattern.
 */
export class ONNXSTTProvider {
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
    sttLogger.info('Registering ONNX STT service provider');

    const {
      ServiceRegistry,
    } = require('../Foundation/DependencyInjection/ServiceRegistry');

    // Register with priority 90 (slightly lower than LlamaCpp)
    ServiceRegistry.shared.registerSTTProvider(ONNXSTTProvider.shared, 90);

    sttLogger.info('ONNX STT service provider registered successfully');
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
      // Check if it's a speech recognition model
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
    // Get STT models that use ONNX framework
    const onnxModels = getCatalogModelsByFramework(LLMFramework.ONNX);
    const sttModels = onnxModels.filter(
      (m) => m.category === ModelCategory.SpeechRecognition
    );

    // Also get WhisperKit models (they can work with ONNX too in some cases)
    const whisperKitModels = getCatalogModelsByFramework(
      LLMFramework.WhisperKit
    );
    const sttWhisperKitModels = whisperKitModels.filter(
      (m) => m.category === ModelCategory.SpeechRecognition
    );

    // Combine and dedupe
    const allSTTModels = [...sttModels];
    for (const model of sttWhisperKitModels) {
      if (!allSTTModels.find((m) => m.id === model.id)) {
        allSTTModels.push(model);
      }
    }

    sttLogger.debug(`Providing ${allSTTModels.length} STT models`);

    return allSTTModels;
  }

  /**
   * Lifecycle hook called when provider is registered
   */
  onRegistration(): void {
    sttLogger.debug('onRegistration() called');
    const models = this.getProvidedModels();
    sttLogger.info(`Registered ${models.length} STT models through provider`);
  }
}

/**
 * ONNX TTS Service Provider
 *
 * This provider handles Text-to-Speech models through the Sherpa-ONNX backend.
 * Mirrors Swift SDK's ONNXTTSServiceProvider pattern.
 */
export class ONNXTTSProvider {
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
    ttsLogger.info('Registering ONNX TTS service provider');

    const {
      ServiceRegistry,
    } = require('../Foundation/DependencyInjection/ServiceRegistry');

    // Register with priority 90 (slightly lower than system TTS)
    ServiceRegistry.shared.registerTTSProvider(ONNXTTSProvider.shared, 90);

    ttsLogger.info('ONNX TTS service provider registered successfully');
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
    // Get TTS models that use ONNX framework
    const onnxModels = getCatalogModelsByFramework(LLMFramework.ONNX);
    const ttsModels = onnxModels.filter(
      (m) => m.category === ModelCategory.SpeechSynthesis
    );

    // Also get SystemTTS (built-in)
    const systemTTSModels = getCatalogModelsByFramework(LLMFramework.SystemTTS);

    // Also get PiperTTS models
    const piperTTSModels = getCatalogModelsByFramework(LLMFramework.PiperTTS);
    const piperTTSTTSModels = piperTTSModels.filter(
      (m) => m.category === ModelCategory.SpeechSynthesis
    );

    // Combine and dedupe
    const allTTSModels = [...ttsModels];
    for (const model of systemTTSModels) {
      if (!allTTSModels.find((m) => m.id === model.id)) {
        allTTSModels.push(model);
      }
    }
    for (const model of piperTTSTTSModels) {
      if (!allTTSModels.find((m) => m.id === model.id)) {
        allTTSModels.push(model);
      }
    }

    ttsLogger.debug(`Providing ${allTTSModels.length} TTS models`);

    return allTTSModels;
  }

  /**
   * Lifecycle hook called when provider is registered
   */
  onRegistration(): void {
    ttsLogger.debug('onRegistration() called');
    const models = this.getProvidedModels();
    ttsLogger.info(`Registered ${models.length} TTS models through provider`);
  }
}

/**
 * Register all ONNX providers
 * Called during SDK initialization to register both STT and TTS providers.
 *
 * Mirrors Swift SDK's ONNXAdapter.register() pattern.
 */
export function registerONNXProviders(): void {
  providerLogger.info('Registering all ONNX providers...');
  ONNXSTTProvider.register();
  ONNXTTSProvider.register();
  providerLogger.info('All ONNX providers registered');
}
