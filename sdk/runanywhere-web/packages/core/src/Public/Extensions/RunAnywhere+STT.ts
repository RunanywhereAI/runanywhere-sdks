/**
 * RunAnywhere Web SDK - Speech-to-Text Extension
 *
 * Adds STT (speech recognition) capabilities via RACommons WASM.
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/STT/
 *
 * Usage:
 *   import { STT } from '@runanywhere/web';
 *
 *   await STT.loadModel('/models/whisper-base.bin', 'whisper-base');
 *   const result = await STT.transcribe(audioFloat32Array);
 *   console.log(result.text);
 */

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';

const logger = new SDKLogger('STT');

// Internal state
let _sttComponentHandle = 0;

function requireBridge(): WASMBridge {
  if (!RunAnywhere.isInitialized) {
    throw SDKError.notInitialized();
  }
  return WASMBridge.shared;
}

function ensureSTTComponent(): number {
  if (_sttComponentHandle !== 0) return _sttComponentHandle;

  const bridge = requireBridge();
  const m = bridge.module;
  const handlePtr = m._malloc(4);
  const result = m.ccall('rac_stt_component_create', 'number', ['number'], [handlePtr]) as number;

  if (result !== 0) {
    m._free(handlePtr);
    bridge.checkResult(result, 'rac_stt_component_create');
  }

  _sttComponentHandle = m.getValue(handlePtr, 'i32');
  m._free(handlePtr);
  logger.debug('STT component created');
  return _sttComponentHandle;
}

// ---------------------------------------------------------------------------
// STT Types
// ---------------------------------------------------------------------------

export interface STTTranscriptionResult {
  text: string;
  confidence: number;
  detectedLanguage?: string;
  processingTimeMs: number;
  words?: STTWord[];
}

export interface STTWord {
  text: string;
  startMs: number;
  endMs: number;
  confidence: number;
}

export interface STTTranscribeOptions {
  language?: string;
  detectLanguage?: boolean;
  enablePunctuation?: boolean;
  enableTimestamps?: boolean;
  sampleRate?: number;
}

/** Callback for streaming STT partial results */
export type STTStreamCallback = (text: string, isFinal: boolean) => void;

// ---------------------------------------------------------------------------
// STT Extension
// ---------------------------------------------------------------------------

export const STT = {
  /**
   * Load an STT model (whisper.cpp GGML or sherpa-onnx).
   */
  async loadModel(modelPath: string, modelId: string, modelName?: string): Promise<void> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureSTTComponent();

    logger.info(`Loading STT model: ${modelId} from ${modelPath}`);
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId, component: 'stt' });

    const pathPtr = bridge.allocString(modelPath);
    const idPtr = bridge.allocString(modelId);
    const namePtr = bridge.allocString(modelName ?? modelId);

    try {
      const result = m.ccall(
        'rac_stt_component_load_model', 'number',
        ['number', 'number', 'number', 'number'],
        [handle, pathPtr, idPtr, namePtr],
      ) as number;
      bridge.checkResult(result, 'rac_stt_component_load_model');
      logger.info(`STT model loaded: ${modelId}`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId, component: 'stt' });
    } finally {
      bridge.free(pathPtr);
      bridge.free(idPtr);
      bridge.free(namePtr);
    }
  },

  /** Unload the STT model. */
  async unloadModel(): Promise<void> {
    if (_sttComponentHandle === 0) return;
    const bridge = requireBridge();
    const result = bridge.module.ccall(
      'rac_stt_component_unload', 'number', ['number'], [_sttComponentHandle],
    ) as number;
    bridge.checkResult(result, 'rac_stt_component_unload');
    logger.info('STT model unloaded');
  },

  /** Check if an STT model is loaded. */
  get isModelLoaded(): boolean {
    if (_sttComponentHandle === 0) return false;
    try {
      return (WASMBridge.shared.module.ccall(
        'rac_stt_component_is_loaded', 'number', ['number'], [_sttComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  },

  /**
   * Transcribe audio data (Float32Array of PCM samples at 16kHz mono).
   *
   * @param audioSamples - Float32Array of PCM audio samples
   * @param options - Transcription options
   * @returns Transcription result with text, confidence, timing
   */
  async transcribe(
    audioSamples: Float32Array,
    options: STTTranscribeOptions = {},
  ): Promise<STTTranscriptionResult> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureSTTComponent();

    if (!STT.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No STT model loaded. Call loadModel() first.');
    }

    logger.debug(`Transcribing ${audioSamples.length} samples`);

    // Copy audio samples to WASM memory
    const audioBytes = audioSamples.length * 4; // float32 = 4 bytes
    const audioPtr = m._malloc(audioBytes);
    new Float32Array(m.HEAPU8.buffer, audioPtr, audioSamples.length).set(audioSamples);

    // Build rac_stt_options_t (simplified -- pass as raw audio data)
    // The component will use its configured options
    const optionsSize = 32; // approximate size of rac_stt_options_t
    const optionsPtr = m._malloc(optionsSize);
    for (let i = 0; i < optionsSize; i++) m.setValue(optionsPtr + i, 0, 'i8');

    // Set language if provided
    let langPtr = 0;
    if (options.language) {
      langPtr = bridge.allocString(options.language);
      m.setValue(optionsPtr, langPtr, '*'); // language field at offset 0
    }
    // detect_language at offset 4
    m.setValue(optionsPtr + 4, options.detectLanguage ? 1 : 0, 'i32');
    // enable_punctuation at offset 8
    m.setValue(optionsPtr + 8, options.enablePunctuation !== false ? 1 : 0, 'i32');
    // sample_rate at offset 28
    m.setValue(optionsPtr + 28, options.sampleRate ?? 16000, 'i32');

    // Allocate result struct
    const resultSize = 48; // approximate size of rac_stt_result_t
    const resultPtr = m._malloc(resultSize);

    try {
      const result = m.ccall(
        'rac_stt_component_transcribe', 'number',
        ['number', 'number', 'number', 'number', 'number'],
        [handle, audioPtr, audioBytes, optionsPtr, resultPtr],
      ) as number;
      bridge.checkResult(result, 'rac_stt_component_transcribe');

      // Read result: { text (ptr), detected_language (ptr), words (ptr), num_words, confidence (float), processing_time_ms (i64) }
      const textPtr = m.getValue(resultPtr, '*');
      const detectedLangPtr = m.getValue(resultPtr + 4, '*');
      const confidence = m.getValue(resultPtr + 16, 'float');
      const processingTimeMs = m.getValue(resultPtr + 20, 'i32');

      const transcriptionResult: STTTranscriptionResult = {
        text: bridge.readString(textPtr),
        confidence,
        detectedLanguage: detectedLangPtr ? bridge.readString(detectedLangPtr) : undefined,
        processingTimeMs,
      };

      // Free the C result
      m.ccall('rac_stt_result_free', null, ['number'], [resultPtr]);

      EventBus.shared.emit('stt.transcribed', SDKEventType.Voice, {
        text: transcriptionResult.text,
        confidence: transcriptionResult.confidence,
      });

      return transcriptionResult;
    } finally {
      m._free(audioPtr);
      m._free(optionsPtr);
      if (langPtr) bridge.free(langPtr);
    }
  },

  /** Clean up the STT component. */
  cleanup(): void {
    if (_sttComponentHandle !== 0) {
      try {
        WASMBridge.shared.module.ccall(
          'rac_stt_component_destroy', null, ['number'], [_sttComponentHandle],
        );
      } catch { /* ignore */ }
      _sttComponentHandle = 0;
    }
  },
};
