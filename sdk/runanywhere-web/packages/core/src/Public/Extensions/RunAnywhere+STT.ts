/**
 * RunAnywhere Web SDK - Speech-to-Text Extension
 *
 * Adds STT (speech recognition) capabilities via sherpa-onnx WASM.
 * Supports both offline (Whisper) and online (streaming Zipformer) models.
 *
 * Uses the sherpa-onnx C struct packing helpers from sherpa-onnx-asr.js
 * to properly allocate config structs in WASM memory (NOT JSON strings).
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/STT/
 *
 * Usage:
 *   import { STT } from '@runanywhere/web';
 *
 *   // Load model files (downloaded separately)
 *   await STT.loadModel({
 *     modelId: 'whisper-tiny-en',
 *     type: 'whisper',
 *     modelFiles: {
 *       encoder: '/models/whisper-tiny-en/encoder.onnx',
 *       decoder: '/models/whisper-tiny-en/decoder.onnx',
 *       tokens: '/models/whisper-tiny-en/tokens.txt',
 *     },
 *   });
 *
 *   const result = await STT.transcribe(audioFloat32Array);
 *   console.log(result.text);
 */

import { RunAnywhere } from '../RunAnywhere';
import { SherpaONNXBridge } from '../../Foundation/SherpaONNXBridge';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';
import { STTModelType } from './STTTypes';
import type { STTModelConfig, STTWhisperFiles, STTZipformerFiles, STTParaformerFiles, STTTranscriptionResult } from './STTTypes';

// Import sherpa-onnx C struct packing helpers.
// These functions properly allocate and fill C structs in WASM memory
// for passing to the sherpa-onnx C API.
// eslint-disable-next-line @typescript-eslint/ban-ts-comment
// @ts-ignore — JS helper file, no .d.ts available
import { initSherpaOnnxOfflineRecognizerConfig, initSherpaOnnxOnlineRecognizerConfig, freeConfig } from '../../../wasm/sherpa/sherpa-onnx-asr.js';

const logger = new SDKLogger('STT');

// ---------------------------------------------------------------------------
// Internal State
// ---------------------------------------------------------------------------

let _offlineRecognizerHandle = 0;
let _onlineRecognizerHandle = 0;
let _currentModelType: STTModelType = STTModelType.Whisper;
let _currentModelId = '';

/** Returns the currently loaded STT model type. */
export function getCurrentSTTModelType(): STTModelType {
  return _currentModelType;
}

// ---------------------------------------------------------------------------
// STT Types (re-exported from STTTypes.ts)
// ---------------------------------------------------------------------------

export { STTModelType } from './STTTypes';
export type { STTModelConfig, STTWhisperFiles, STTZipformerFiles, STTParaformerFiles, STTTranscriptionResult, STTWord } from './STTTypes';

export interface STTTranscribeOptions {
  language?: string;
  sampleRate?: number;
}

/** Callback for streaming STT partial results */
export type STTStreamCallback = (text: string, isFinal: boolean) => void;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireSherpa(): SherpaONNXBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return SherpaONNXBridge.shared;
}

/**
 * Build a sherpa-onnx offline recognizer config object suitable for
 * `initSherpaOnnxOfflineRecognizerConfig()` from sherpa-onnx-asr.js.
 *
 * This returns a plain JS config object that the helper function will
 * pack into a C struct in WASM memory.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function buildOfflineRecognizerConfig(config: STTModelConfig): Record<string, any> {
  const sampleRate = config.sampleRate ?? 16000;
  const files = config.modelFiles;

  // Base config with all model types empty (required for struct layout)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const modelConfig: Record<string, any> = {
    transducer: { encoder: '', decoder: '', joiner: '' },
    paraformer: { model: '' },
    nemoCtc: { model: '' },
    whisper: { encoder: '', decoder: '', language: '', task: '', tailPaddings: -1 },
    tdnn: { model: '' },
    senseVoice: { model: '', language: '', useInverseTextNormalization: 0 },
    moonshine: { preprocessor: '', encoder: '', uncachedDecoder: '', cachedDecoder: '' },
    fireRedAsr: { encoder: '', decoder: '' },
    dolphin: { model: '' },
    zipformerCtc: { model: '' },
    canary: { encoder: '', decoder: '', srcLang: '', tgtLang: '', usePnc: 1 },
    wenetCtc: { model: '' },
    omnilingual: { model: '' },
    tokens: '',
    numThreads: 1,
    provider: 'cpu',
    debug: 0,
    modelType: '',
    modelingUnit: '',
    bpeVocab: '',
    teleSpeechCtc: '',
  };

  if (config.type === STTModelType.Whisper) {
    const f = files as STTWhisperFiles;
    modelConfig.whisper = {
      encoder: f.encoder,
      decoder: f.decoder,
      language: config.language ?? 'en',
      task: 'transcribe',
      tailPaddings: -1,
    };
    modelConfig.tokens = f.tokens;
  } else if (config.type === STTModelType.Paraformer) {
    const f = files as STTParaformerFiles;
    modelConfig.paraformer = { model: f.model };
    modelConfig.tokens = f.tokens;
  }

  return {
    featConfig: { sampleRate, featureDim: 80 },
    modelConfig,
    lmConfig: { model: '', scale: 1.0 },
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
    hotwordsFile: '',
    hotwordsScore: 1.5,
    ruleFsts: '',
    ruleFars: '',
    blankPenalty: 0,
  };
}

/**
 * Build a sherpa-onnx online recognizer config object suitable for
 * `initSherpaOnnxOnlineRecognizerConfig()` from sherpa-onnx-asr.js.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function buildOnlineRecognizerConfig(config: STTModelConfig): Record<string, any> {
  const sampleRate = config.sampleRate ?? 16000;
  const files = config.modelFiles as STTZipformerFiles;

  return {
    featConfig: { sampleRate, featureDim: 80 },
    modelConfig: {
      transducer: {
        encoder: files.encoder,
        decoder: files.decoder,
        joiner: files.joiner,
      },
      paraformer: { encoder: '', decoder: '' },
      zipformer2Ctc: { model: '' },
      nemoCtc: { model: '' },
      toneCtc: { model: '' },
      tokens: files.tokens,
      numThreads: 1,
      provider: 'cpu',
      debug: 0,
      modelType: '',
      modelingUnit: '',
      bpeVocab: '',
    },
    decodingMethod: 'greedy_search',
    maxActivePaths: 4,
    enableEndpoint: 1,
    rule1MinTrailingSilence: 2.4,
    rule2MinTrailingSilence: 1.2,
    rule3MinUtteranceLength: 20,
    hotwordsFile: '',
    hotwordsScore: 1.5,
    ctcFstDecoderConfig: { graph: '', maxActive: 3000 },
    ruleFsts: '',
    ruleFars: '',
  };
}

// ---------------------------------------------------------------------------
// STT Extension
// ---------------------------------------------------------------------------

export const STT = {
  /**
   * Load an STT model via sherpa-onnx.
   * Model files must already be written to sherpa-onnx virtual FS
   * (use SherpaONNXBridge.shared.downloadAndWrite() or .writeFile()).
   */
  async loadModel(config: STTModelConfig): Promise<void> {
    const sherpa = requireSherpa();
    await sherpa.ensureLoaded();
    const m = sherpa.module;

    // Clean up previous model
    STT.cleanup();

    logger.info(`Loading STT model: ${config.modelId} (${config.type})`);
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, {
      modelId: config.modelId, component: 'stt',
    });

    const startMs = performance.now();

    try {
      if (config.type === STTModelType.Zipformer) {
        // Streaming model: use online recognizer
        const configObj = buildOnlineRecognizerConfig(config);
        const configStruct = initSherpaOnnxOnlineRecognizerConfig(configObj, m);

        _onlineRecognizerHandle = m._SherpaOnnxCreateOnlineRecognizer(configStruct.ptr);
        freeConfig(configStruct, m);

        if (_onlineRecognizerHandle === 0) {
          throw new SDKError(SDKErrorCode.ModelLoadFailed,
            `Failed to create online recognizer for ${config.modelId}`);
        }
      } else {
        // Non-streaming model (Whisper, Paraformer): use offline recognizer
        const configObj = buildOfflineRecognizerConfig(config);
        logger.debug(`Offline config: ${JSON.stringify(configObj.modelConfig.whisper)}`);
        const configStruct = initSherpaOnnxOfflineRecognizerConfig(configObj, m);

        _offlineRecognizerHandle = m._SherpaOnnxCreateOfflineRecognizer(configStruct.ptr);
        freeConfig(configStruct, m);

        if (_offlineRecognizerHandle === 0) {
          throw new SDKError(SDKErrorCode.ModelLoadFailed,
            `Failed to create offline recognizer for ${config.modelId}`);
        }
      }

      _currentModelType = config.type;
      _currentModelId = config.modelId;

      const loadTimeMs = Math.round(performance.now() - startMs);
      logger.info(`STT model loaded: ${config.modelId} in ${loadTimeMs}ms`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, {
        modelId: config.modelId, component: 'stt', loadTimeMs,
      });
    } catch (error) {
      STT.cleanup();
      throw error;
    }
  },

  /** Unload the STT model. */
  async unloadModel(): Promise<void> {
    STT.cleanup();
    logger.info('STT model unloaded');
  },

  /** Check if an STT model is loaded. */
  get isModelLoaded(): boolean {
    return _offlineRecognizerHandle !== 0 || _onlineRecognizerHandle !== 0;
  },

  /** Get the current model ID. */
  get modelId(): string {
    return _currentModelId;
  },

  /**
   * Transcribe audio data (offline / non-streaming).
   *
   * @param audioSamples - Float32Array of PCM audio samples (mono, 16kHz)
   * @param options - Transcription options
   * @returns Transcription result
   */
  async transcribe(
    audioSamples: Float32Array,
    options: STTTranscribeOptions = {},
  ): Promise<STTTranscriptionResult> {
    const sherpa = requireSherpa();
    const m = sherpa.module;

    if (_offlineRecognizerHandle === 0) {
      if (_onlineRecognizerHandle !== 0) {
        // Streaming model: process all at once via online recognizer
        return STT._transcribeViaOnline(audioSamples, options);
      }
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No STT model loaded. Call loadModel() first.');
    }

    const startMs = performance.now();
    const sampleRate = options.sampleRate ?? 16000;

    logger.debug(`Transcribing ${audioSamples.length} samples (${(audioSamples.length / sampleRate).toFixed(1)}s)`);

    // Create stream
    const stream = m._SherpaOnnxCreateOfflineStream(_offlineRecognizerHandle);
    if (stream === 0) {
      throw new SDKError(SDKErrorCode.GenerationFailed, 'Failed to create offline stream');
    }

    // Copy audio to WASM memory
    const audioPtr = m._malloc(audioSamples.length * 4);
    m.HEAPF32.set(audioSamples, audioPtr / 4);

    try {
      // Feed audio
      m._SherpaOnnxAcceptWaveformOffline(stream, sampleRate, audioPtr, audioSamples.length);

      // Decode
      m._SherpaOnnxDecodeOfflineStream(_offlineRecognizerHandle, stream);

      // Get result as JSON
      const jsonPtr = m._SherpaOnnxGetOfflineStreamResultAsJson(stream);
      const jsonStr = sherpa.readString(jsonPtr);
      m._SherpaOnnxDestroyOfflineStreamResultJson(jsonPtr);

      const result = JSON.parse(jsonStr || '{}');
      const processingTimeMs = Math.round(performance.now() - startMs);

      const transcription: STTTranscriptionResult = {
        text: (result.text ?? '').trim(),
        confidence: result.confidence ?? 0,
        detectedLanguage: result.lang,
        processingTimeMs,
      };

      EventBus.shared.emit('stt.transcribed', SDKEventType.Voice, {
        text: transcription.text,
        confidence: transcription.confidence,
      });

      return transcription;
    } finally {
      m._free(audioPtr);
      m._SherpaOnnxDestroyOfflineStream(stream);
    }
  },

  /** Internal: Transcribe via online recognizer (for streaming models used non-streaming) */
  async _transcribeViaOnline(
    audioSamples: Float32Array,
    options: STTTranscribeOptions = {},
  ): Promise<STTTranscriptionResult> {
    const m = SherpaONNXBridge.shared.module;
    const startMs = performance.now();
    const sampleRate = options.sampleRate ?? 16000;

    const stream = m._SherpaOnnxCreateOnlineStream(_onlineRecognizerHandle);
    if (stream === 0) {
      throw new SDKError(SDKErrorCode.GenerationFailed, 'Failed to create online stream');
    }

    const audioPtr = m._malloc(audioSamples.length * 4);
    m.HEAPF32.set(audioSamples, audioPtr / 4);

    try {
      m._SherpaOnnxOnlineStreamAcceptWaveform(stream, sampleRate, audioPtr, audioSamples.length);
      m._SherpaOnnxOnlineStreamInputFinished(stream);

      while (m._SherpaOnnxIsOnlineStreamReady(_onlineRecognizerHandle, stream)) {
        m._SherpaOnnxDecodeOnlineStream(_onlineRecognizerHandle, stream);
      }

      const jsonPtr = m._SherpaOnnxGetOnlineStreamResultAsJson(_onlineRecognizerHandle, stream);
      const jsonStr = SherpaONNXBridge.shared.readString(jsonPtr);
      m._SherpaOnnxDestroyOnlineStreamResultJson(jsonPtr);

      const result = JSON.parse(jsonStr || '{}');
      const processingTimeMs = Math.round(performance.now() - startMs);

      return {
        text: (result.text ?? '').trim(),
        confidence: result.confidence ?? 0,
        processingTimeMs,
      };
    } finally {
      m._free(audioPtr);
      m._SherpaOnnxDestroyOnlineStream(stream);
    }
  },

  /**
   * Create a streaming transcription session.
   * Returns an object to feed audio chunks and get results.
   */
  createStreamingSession(options: STTTranscribeOptions = {}): STTStreamingSession {
    if (_onlineRecognizerHandle === 0) {
      throw new SDKError(
        SDKErrorCode.ModelNotLoaded,
        'No streaming STT model loaded. Use a zipformer model.',
      );
    }

    return new STTStreamingSessionImpl(_onlineRecognizerHandle, options);
  },

  /** Clean up the STT resources. */
  cleanup(): void {
    const sherpa = SherpaONNXBridge.shared;
    if (!sherpa.isLoaded) return;

    const m = sherpa.module;

    if (_offlineRecognizerHandle !== 0) {
      try { m._SherpaOnnxDestroyOfflineRecognizer(_offlineRecognizerHandle); } catch { /* ignore */ }
      _offlineRecognizerHandle = 0;
    }

    if (_onlineRecognizerHandle !== 0) {
      try { m._SherpaOnnxDestroyOnlineRecognizer(_onlineRecognizerHandle); } catch { /* ignore */ }
      _onlineRecognizerHandle = 0;
    }

    _currentModelId = '';
  },
};

// ---------------------------------------------------------------------------
// Streaming Session
// ---------------------------------------------------------------------------

export interface STTStreamingSession {
  /** Feed audio samples to the recognizer */
  acceptWaveform(samples: Float32Array, sampleRate?: number): void;
  /** Signal end of audio input */
  inputFinished(): void;
  /** Get current partial/final result */
  getResult(): { text: string; isEndpoint: boolean };
  /** Reset after endpoint */
  reset(): void;
  /** Destroy the streaming session */
  destroy(): void;
}

class STTStreamingSessionImpl implements STTStreamingSession {
  private _stream: number;
  private readonly _recognizer: number;
  private readonly _sampleRate: number;

  constructor(recognizer: number, options: STTTranscribeOptions) {
    this._recognizer = recognizer;
    this._sampleRate = options.sampleRate ?? 16000;
    const m = SherpaONNXBridge.shared.module;
    this._stream = m._SherpaOnnxCreateOnlineStream(recognizer);
    if (this._stream === 0) {
      throw new SDKError(SDKErrorCode.GenerationFailed, 'Failed to create streaming session');
    }
  }

  acceptWaveform(samples: Float32Array, sampleRate?: number): void {
    const m = SherpaONNXBridge.shared.module;
    const audioPtr = m._malloc(samples.length * 4);
    m.HEAPF32.set(samples, audioPtr / 4);
    m._SherpaOnnxOnlineStreamAcceptWaveform(
      this._stream, sampleRate ?? this._sampleRate, audioPtr, samples.length,
    );
    m._free(audioPtr);

    // Decode available frames
    while (m._SherpaOnnxIsOnlineStreamReady(this._recognizer, this._stream)) {
      m._SherpaOnnxDecodeOnlineStream(this._recognizer, this._stream);
    }
  }

  inputFinished(): void {
    SherpaONNXBridge.shared.module._SherpaOnnxOnlineStreamInputFinished(this._stream);
  }

  getResult(): { text: string; isEndpoint: boolean } {
    const m = SherpaONNXBridge.shared.module;
    const jsonPtr = m._SherpaOnnxGetOnlineStreamResultAsJson(this._recognizer, this._stream);
    const jsonStr = SherpaONNXBridge.shared.readString(jsonPtr);
    m._SherpaOnnxDestroyOnlineStreamResultJson(jsonPtr);

    const result = JSON.parse(jsonStr || '{}');
    const isEndpoint = m._SherpaOnnxOnlineStreamIsEndpoint(this._recognizer, this._stream) !== 0;

    return {
      text: (result.text ?? '').trim(),
      isEndpoint,
    };
  }

  reset(): void {
    SherpaONNXBridge.shared.module._SherpaOnnxOnlineStreamReset(this._recognizer, this._stream);
  }

  destroy(): void {
    if (this._stream !== 0) {
      try {
        SherpaONNXBridge.shared.module._SherpaOnnxDestroyOnlineStream(this._stream);
      } catch { /* ignore */ }
      this._stream = 0;
    }
  }
}
