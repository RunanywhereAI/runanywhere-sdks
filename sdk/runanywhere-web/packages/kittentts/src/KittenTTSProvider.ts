/**
 * KittenTTS Provider — model loader and TTSProvider for the RunAnywhere SDK.
 *
 * Registers the KittenTTS engine with the RunAnywhere model management system.
 * Handles:
 *   - Model detection (canHandle) based on model ID prefix 'kitten-tts-'
 *   - Loading model files (ONNX, voices.npz, config.json) from storage
 *   - Registering as the active 'tts' provider via ExtensionPoint
 *   - Synthesis via the TTSProvider interface
 */

import {
  SDKLogger,
  ModelManager,
  ExtensionPoint,
  EventBus,
  SDKEventType,
} from '@runanywhere/web';

import type { KittenTTSModelLoader, ModelLoadContext } from '@runanywhere/web';
import type { ManagedModel } from '@runanywhere/web';

import { KittenTTSEngine } from './Foundation/KittenTTSEngine';
import type { KittenTTSVoice } from './Foundation/KittenTTSEngine';

const logger = new SDKLogger('KittenTTSProvider');

const KITTEN_TTS_ID_PREFIX = 'kitten-tts-';

// Singleton engine
const engine = new KittenTTSEngine();

// Current voice selection (can be changed per synthesis call)
let _currentVoice: KittenTTSVoice = 'Jasper';

// ---------------------------------------------------------------------------
// Model Loader (implements KittenTTSModelLoader)
// ---------------------------------------------------------------------------

const modelLoader: KittenTTSModelLoader = {
  canHandle(model: ManagedModel): boolean {
    return model.id.startsWith(KITTEN_TTS_ID_PREFIX);
  },

  async loadModelFromData(ctx: ModelLoadContext): Promise<void> {
    const { model, data } = ctx;
    const modelId = model.id;

    logger.info(`Loading KittenTTS model: ${modelId}`);
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, {
      modelId, component: 'kittentts',
    });

    const startMs = performance.now();

    // Primary file = ONNX model
    const modelData = data;

    // Load companion files: voices.npz and config.json
    const voicesData = await loadCompanionFile(ctx, 'voices.npz');
    const configData = await loadCompanionFile(ctx, 'config.json');

    if (!voicesData) throw new Error(`Missing companion file 'voices.npz' for model '${modelId}'`);
    if (!configData) throw new Error(`Missing companion file 'config.json' for model '${modelId}'`);

    // Initialize the engine
    await engine.load(modelData, voicesData, configData, modelId);

    // Register as the active TTS provider
    ExtensionPoint.registerProvider('tts', ttsProvider);

    const loadTimeMs = Math.round(performance.now() - startMs);
    logger.info(`KittenTTS model loaded: ${modelId} in ${loadTimeMs}ms`);
    EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, {
      modelId, component: 'kittentts', loadTimeMs,
    });
  },

  async unloadVoice(): Promise<void> {
    engine.cleanup();
    logger.info('KittenTTS voice unloaded');
  },
};

async function loadCompanionFile(ctx: ModelLoadContext, filename: string): Promise<Uint8Array | null> {
  const fileKey = ctx.additionalFileKey(ctx.model.id, filename);
  let data = await ctx.loadFile(fileKey);

  if (!data) {
    // Try downloading on demand
    const companion = ctx.model.additionalFiles?.find(f => f.filename === filename);
    if (companion?.url) {
      logger.debug(`Downloading companion file: ${filename}`);
      data = await ctx.downloadFile(companion.url);
      await ctx.storeFile(fileKey, data);
    }
  }

  return data;
}

// ---------------------------------------------------------------------------
// TTS Provider (implements TTSProvider from ProviderTypes)
// ---------------------------------------------------------------------------

const ttsProvider = {
  async synthesize(
    text: string,
    options?: { speed?: number; voice?: string },
  ): Promise<{
    audioData: Float32Array;
    sampleRate: number;
    durationMs: number;
    processingTimeMs: number;
  }> {
    if (!engine.isLoaded) {
      throw new Error('No KittenTTS model loaded.');
    }

    const voice = (options?.voice as KittenTTSVoice) ?? _currentVoice;
    const speed = options?.speed ?? 1.0;

    return engine.synthesize(text, voice, speed);
  },
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export const KittenTTSProvider = {
  /** Whether the provider is registered with the model manager. */
  get isRegistered(): boolean {
    return _isRegistered;
  },

  /** Whether a KittenTTS model is currently loaded. */
  get isLoaded(): boolean {
    return engine.isLoaded;
  },

  /** The currently loaded model ID. */
  get modelId(): string {
    return engine.modelId;
  },

  /** Available voice names. */
  get availableVoices(): KittenTTSVoice[] {
    return engine.availableVoices;
  },

  /** Get or set the default voice for synthesis. */
  get currentVoice(): KittenTTSVoice {
    return _currentVoice;
  },
  set currentVoice(voice: KittenTTSVoice) {
    _currentVoice = voice;
  },

  /**
   * Register the KittenTTS backend with the RunAnywhere SDK.
   * This plugs in the KittenTTS model loader so KittenTTS models
   * are recognized and loaded via the standard model management flow.
   */
  register(): void {
    if (_isRegistered) {
      logger.debug('KittenTTS provider already registered');
      return;
    }

    ModelManager.setKittenTTSLoader(modelLoader);
    _isRegistered = true;
    logger.info('KittenTTS provider registered');
  },

  /** Unregister the KittenTTS provider and clean up. */
  unregister(): void {
    engine.cleanup();
    _isRegistered = false;
    logger.info('KittenTTS provider unregistered');
  },

  /**
   * Set up espeak-ng phonemizer from the sherpa-onnx module.
   * Call this after the sherpa-onnx WASM is loaded for better TTS quality.
   */
  setupSherpaPhonemizer(sherpaModule: unknown): void {
    engine.trySetupSherpaPhonmizer(sherpaModule);
  },
};

let _isRegistered = false;
