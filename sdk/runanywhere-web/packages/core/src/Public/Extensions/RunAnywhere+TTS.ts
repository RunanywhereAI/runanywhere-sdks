/**
 * RunAnywhere Web SDK - Text-to-Speech Extension
 *
 * Adds TTS (speech synthesis) capabilities via RACommons WASM.
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/TTS/
 *
 * Usage:
 *   import { TTS } from '@runanywhere/web';
 *
 *   await TTS.loadVoice('/models/piper-en.onnx', 'piper-en');
 *   const result = await TTS.synthesize('Hello, world!');
 *   // result.audioData is Float32Array of PCM samples
 */

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';

const logger = new SDKLogger('TTS');

let _ttsComponentHandle = 0;

function requireBridge(): WASMBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return WASMBridge.shared;
}

function ensureTTSComponent(): number {
  if (_ttsComponentHandle !== 0) return _ttsComponentHandle;

  const bridge = requireBridge();
  const m = bridge.module;
  const handlePtr = m._malloc(4);
  const result = m.ccall('rac_tts_component_create', 'number', ['number'], [handlePtr]) as number;

  if (result !== 0) {
    m._free(handlePtr);
    bridge.checkResult(result, 'rac_tts_component_create');
  }

  _ttsComponentHandle = m.getValue(handlePtr, 'i32');
  m._free(handlePtr);
  logger.debug('TTS component created');
  return _ttsComponentHandle;
}

// ---------------------------------------------------------------------------
// TTS Types
// ---------------------------------------------------------------------------

export interface TTSSynthesisResult {
  /** Raw PCM audio data */
  audioData: Float32Array;
  /** Audio sample rate */
  sampleRate: number;
  /** Duration in milliseconds */
  durationMs: number;
  /** Processing time in milliseconds */
  processingTimeMs: number;
}

export interface TTSSynthesizeOptions {
  voice?: string;
  language?: string;
  rate?: number;
  pitch?: number;
  volume?: number;
  sampleRate?: number;
}

// ---------------------------------------------------------------------------
// TTS Extension
// ---------------------------------------------------------------------------

export const TTS = {
  /**
   * Load a TTS voice model (Piper ONNX or similar).
   */
  async loadVoice(voicePath: string, voiceId: string, voiceName?: string): Promise<void> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureTTSComponent();

    logger.info(`Loading TTS voice: ${voiceId} from ${voicePath}`);
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId: voiceId, component: 'tts' });

    const pathPtr = bridge.allocString(voicePath);
    const idPtr = bridge.allocString(voiceId);
    const namePtr = bridge.allocString(voiceName ?? voiceId);

    try {
      const result = m.ccall(
        'rac_tts_component_load_voice', 'number',
        ['number', 'number', 'number', 'number'],
        [handle, pathPtr, idPtr, namePtr],
      ) as number;
      bridge.checkResult(result, 'rac_tts_component_load_voice');
      logger.info(`TTS voice loaded: ${voiceId}`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId: voiceId, component: 'tts' });
    } finally {
      bridge.free(pathPtr);
      bridge.free(idPtr);
      bridge.free(namePtr);
    }
  },

  /** Unload the TTS voice. */
  async unloadVoice(): Promise<void> {
    if (_ttsComponentHandle === 0) return;
    const bridge = requireBridge();
    const result = bridge.module.ccall(
      'rac_tts_component_unload', 'number', ['number'], [_ttsComponentHandle],
    ) as number;
    bridge.checkResult(result, 'rac_tts_component_unload');
    logger.info('TTS voice unloaded');
  },

  /** Check if a TTS voice is loaded. */
  get isVoiceLoaded(): boolean {
    if (_ttsComponentHandle === 0) return false;
    try {
      return (WASMBridge.shared.module.ccall(
        'rac_tts_component_is_loaded', 'number', ['number'], [_ttsComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  },

  /**
   * Synthesize speech from text.
   *
   * @param text - Text to synthesize
   * @param options - Synthesis options
   * @returns Synthesis result with PCM audio data
   */
  async synthesize(text: string, options: TTSSynthesizeOptions = {}): Promise<TTSSynthesisResult> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureTTSComponent();

    if (!TTS.isVoiceLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No TTS voice loaded. Call loadVoice() first.');
    }

    logger.debug(`Synthesizing: "${text.substring(0, 50)}..."`);

    const textPtr = bridge.allocString(text);

    // Build rac_tts_options_t
    const optionsSize = 32;
    const optionsPtr = m._malloc(optionsSize);
    for (let i = 0; i < optionsSize; i++) m.setValue(optionsPtr + i, 0, 'i8');

    // Set options fields
    let voicePtr = 0;
    if (options.voice) {
      voicePtr = bridge.allocString(options.voice);
      m.setValue(optionsPtr, voicePtr, '*'); // voice at offset 0
    }
    // rate at offset 8 (float)
    m.setValue(optionsPtr + 8, options.rate ?? 1.0, 'float');
    // pitch at offset 12 (float)
    m.setValue(optionsPtr + 12, options.pitch ?? 1.0, 'float');
    // volume at offset 16 (float)
    m.setValue(optionsPtr + 16, options.volume ?? 1.0, 'float');
    // sample_rate at offset 24 (i32)
    m.setValue(optionsPtr + 24, options.sampleRate ?? 22050, 'i32');

    // Allocate result struct (rac_tts_result_t)
    const resultSize = 32;
    const resultPtr = m._malloc(resultSize);

    try {
      const result = m.ccall(
        'rac_tts_component_synthesize', 'number',
        ['number', 'number', 'number', 'number'],
        [handle, textPtr, optionsPtr, resultPtr],
      ) as number;
      bridge.checkResult(result, 'rac_tts_component_synthesize');

      // Read result: { audio_data (ptr), audio_size (size_t), audio_format (i32), sample_rate (i32), duration_ms (i64), processing_time_ms (i64) }
      const audioDataPtr = m.getValue(resultPtr, '*');
      const audioSize = m.getValue(resultPtr + 4, 'i32');
      const sampleRate = m.getValue(resultPtr + 12, 'i32');
      const durationMs = m.getValue(resultPtr + 16, 'i32');
      const processingTimeMs = m.getValue(resultPtr + 20, 'i32');

      // Copy audio data to Float32Array
      const numSamples = audioSize / 4; // float32
      const audioData = new Float32Array(numSamples);
      if (audioDataPtr && audioSize > 0) {
        audioData.set(new Float32Array(m.HEAPU8.buffer, audioDataPtr, numSamples));
      }

      // Free C result
      m.ccall('rac_tts_result_free', null, ['number'], [resultPtr]);

      EventBus.shared.emit('tts.synthesized', SDKEventType.Voice, {
        durationMs,
        sampleRate,
        textLength: text.length,
      });

      return { audioData, sampleRate, durationMs, processingTimeMs };
    } finally {
      bridge.free(textPtr);
      m._free(optionsPtr);
      if (voicePtr) bridge.free(voicePtr);
    }
  },

  /** Stop any in-progress synthesis. */
  stop(): void {
    if (_ttsComponentHandle === 0) return;
    try {
      WASMBridge.shared.module.ccall(
        'rac_tts_component_stop', 'number', ['number'], [_ttsComponentHandle],
      );
    } catch { /* ignore */ }
  },

  /** Clean up the TTS component. */
  cleanup(): void {
    if (_ttsComponentHandle !== 0) {
      try {
        WASMBridge.shared.module.ccall(
          'rac_tts_component_destroy', null, ['number'], [_ttsComponentHandle],
        );
      } catch { /* ignore */ }
      _ttsComponentHandle = 0;
    }
  },
};
