/**
 * RunAnywhere+AudioConvert.ts
 *
 * Public PCM conversion + level helpers — thin WASM wrappers over commons
 * `rac_audio_pcm16_to_float32` / `rac_audio_float32_to_pcm16` /
 * `rac_audio_int16_to_wav` / `rac_audio_float32_to_wav` /
 * `rac_audio_compute_rms` / `rac_audio_compute_level_db` /
 * `rac_audio_compute_level_normalized`.
 */

import { SDKException } from '../../Foundation/SDKException.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule.js';

/** Commons default dBFS floor for normalized meters (−60 dB → 0.0). */
export const AUDIO_LEVEL_FLOOR_DB = -60;

interface AudioUtilsModule extends EmscriptenRunanywhereModule {
  _rac_audio_pcm16_to_float32?(inPtr: number, nSamples: number, outPtr: number): number;
  _rac_audio_float32_to_pcm16?(inPtr: number, nSamples: number, outPtr: number): number;
  _rac_audio_int16_to_wav?(
    pcmPtr: number,
    pcmSize: number,
    sampleRate: number,
    outWavPtrPtr: number,
    outWavSizePtr: number,
  ): number;
  _rac_audio_float32_to_wav?(
    pcmPtr: number,
    pcmSize: number,
    sampleRate: number,
    outWavPtrPtr: number,
    outWavSizePtr: number,
  ): number;
  _rac_audio_compute_rms?(samplesPtr: number, count: number, outRmsPtr: number): number;
  _rac_audio_compute_level_db?(samplesPtr: number, count: number, outDbPtr: number): number;
  _rac_audio_compute_level_normalized?(
    samplesPtr: number,
    count: number,
    floorDb: number,
    outLevelPtr: number,
  ): number;
  _rac_free?(ptr: number): void;
}

function requireAudioModule(): AudioUtilsModule {
  const module = (getModuleForCapability('commons') ??
    getModuleForCapability('stt') ??
    getModuleForCapability('tts') ??
    getModuleForCapability('vad') ??
    getModuleForCapability('voice-agent')) as AudioUtilsModule | null;
  if (!module) {
    throw SDKException.backendNotAvailable(
      'audioConvert',
      'No WASM module exporting rac_audio_* is registered. Call RunAnywhere.initialize() first.',
    );
  }
  return module;
}

function allocCopy(module: AudioUtilsModule, bytes: Uint8Array): number {
  const ptr = module._malloc(bytes.byteLength || 1);
  if (!ptr) throw SDKException.processingFailed('Failed to allocate WASM audio buffer.');
  if (bytes.byteLength > 0) {
    module.HEAPU8.set(bytes, ptr);
  }
  return ptr;
}

/** Copy into a plain `ArrayBuffer` (never a `SharedArrayBuffer` view). */
function toOwnedBytes(source: ArrayBufferLike | Uint8Array): Uint8Array {
  if (source instanceof Uint8Array) {
    const owned = new Uint8Array(source.byteLength);
    owned.set(source);
    return owned;
  }
  return new Uint8Array(source.slice(0));
}

/**
 * Convert a buffer of Int16 PCM samples to Float32 samples in the range
 * `[-1.0, 1.0]` via `rac_audio_pcm16_to_float32`.
 */
export function pcm16ToFloat32(int16Bytes: ArrayBufferLike | Uint8Array): Float32Array {
  const inBytes = toOwnedBytes(int16Bytes);
  const int16Count = Math.floor(inBytes.byteLength / 2);
  if (int16Count === 0) return new Float32Array(0);
  const module = requireAudioModule();
  if (typeof module._rac_audio_pcm16_to_float32 !== 'function') {
    throw SDKException.backendNotAvailable(
      'audioConvert',
      'WASM build missing _rac_audio_pcm16_to_float32.',
    );
  }
  const inPtr = allocCopy(module, inBytes);
  const outPtr = module._malloc(int16Count * 4);
  try {
    if (!outPtr) throw SDKException.processingFailed('Failed to allocate float32 output.');
    const rc = module._rac_audio_pcm16_to_float32(inPtr, int16Count, outPtr);
    if (rc !== 0) {
      throw SDKException.processingFailed(`rac_audio_pcm16_to_float32 failed (${rc}).`);
    }
    const heap = new Float32Array(module.HEAPU8.buffer, outPtr, int16Count);
    return new Float32Array(heap);
  } finally {
    module._free(inPtr);
    if (outPtr) module._free(outPtr);
  }
}

/** Convenience alias for cross-SDK call-site parity with Swift. */
export function pcm16ToFloat32Samples(int16Bytes: ArrayBufferLike | Uint8Array): Float32Array {
  return pcm16ToFloat32(int16Bytes);
}

/**
 * Quantize Float32 samples to Int16 PCM via `rac_audio_float32_to_pcm16`.
 */
export function float32ToPcm16(samples: Float32Array): Uint8Array {
  if (samples.length === 0) return new Uint8Array(0);
  const module = requireAudioModule();
  if (typeof module._rac_audio_float32_to_pcm16 !== 'function') {
    throw SDKException.backendNotAvailable(
      'audioConvert',
      'WASM build missing _rac_audio_float32_to_pcm16.',
    );
  }
  // Copy out of a possibly shared WASM heap before crossing into rac_audio_*.
  const inBytes = toOwnedBytes(
    new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength),
  );
  const inPtr = allocCopy(module, inBytes);
  const outPtr = module._malloc(samples.length * 2);
  try {
    if (!outPtr) throw SDKException.processingFailed('Failed to allocate pcm16 output.');
    const rc = module._rac_audio_float32_to_pcm16(inPtr, samples.length, outPtr);
    if (rc !== 0) {
      throw SDKException.processingFailed(`rac_audio_float32_to_pcm16 failed (${rc}).`);
    }
    return new Uint8Array(module.HEAPU8.slice(outPtr, outPtr + samples.length * 2));
  } finally {
    module._free(inPtr);
    if (outPtr) module._free(outPtr);
  }
}

function toWav(
  fnName: '_rac_audio_int16_to_wav' | '_rac_audio_float32_to_wav',
  pcmBytes: Uint8Array,
  sampleRate: number,
): Uint8Array {
  const module = requireAudioModule();
  const fn = module[fnName];
  if (typeof fn !== 'function') {
    throw SDKException.backendNotAvailable('audioConvert', `WASM build missing ${fnName}.`);
  }
  if (typeof module._rac_free !== 'function') {
    throw SDKException.backendNotAvailable('audioConvert', 'WASM build missing _rac_free.');
  }
  const pcmPtr = allocCopy(module, pcmBytes);
  const outPtrPtr = module._malloc(4);
  const outSizePtr = module._malloc(4);
  try {
    module.setValue(outPtrPtr, 0, '*');
    module.setValue(outSizePtr, 0, 'i32');
    const rc = fn(pcmPtr, pcmBytes.byteLength, sampleRate, outPtrPtr, outSizePtr);
    if (rc !== 0) {
      throw SDKException.processingFailed(`${fnName.slice(1)} failed (${rc}).`);
    }
    const wavPtr = module.getValue(outPtrPtr, '*') >>> 0;
    const wavSize = module.getValue(outSizePtr, 'i32') >>> 0;
    if (!wavPtr || wavSize === 0) {
      throw SDKException.processingFailed(`${fnName.slice(1)} returned empty WAV.`);
    }
    const out = new Uint8Array(module.HEAPU8.slice(wavPtr, wavPtr + wavSize));
    module._rac_free(wavPtr);
    return out;
  } finally {
    module._free(pcmPtr);
    module._free(outPtrPtr);
    module._free(outSizePtr);
  }
}

/**
 * Wrap raw 16-bit mono PCM samples in a WAV container via `rac_audio_int16_to_wav`.
 */
export function pcm16ToWav(int16Bytes: ArrayBufferLike | Uint8Array, sampleRate: number): Uint8Array {
  const bytes = toOwnedBytes(int16Bytes);
  if (bytes.byteLength === 0) return new Uint8Array(0);
  return toWav('_rac_audio_int16_to_wav', bytes, sampleRate);
}

/**
 * Encode Float32 mono PCM as a WAV container via `rac_audio_float32_to_wav`.
 */
export function float32ToWav(samples: Float32Array, sampleRate: number): Uint8Array {
  if (samples.length === 0) return new Uint8Array(0);
  const bytes = toOwnedBytes(
    new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength),
  );
  return toWav('_rac_audio_float32_to_wav', bytes, sampleRate);
}

function withFloat32Samples<T>(
  samples: Float32Array,
  fn: (module: AudioUtilsModule, samplesPtr: number, count: number) => T,
): T {
  const module = requireAudioModule();
  const inBytes = toOwnedBytes(
    new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength),
  );
  const samplesPtr = allocCopy(module, inBytes);
  try {
    return fn(module, samplesPtr, samples.length);
  } finally {
    module._free(samplesPtr);
  }
}

function readFloatOut(
  module: AudioUtilsModule,
  fnName: string,
  invoke: (outPtr: number) => number,
): number {
  const outPtr = module._malloc(4);
  try {
    if (!outPtr) throw SDKException.processingFailed(`Failed to allocate ${fnName} output.`);
    const rc = invoke(outPtr);
    if (rc !== 0) {
      throw SDKException.processingFailed(`${fnName} failed (${rc}).`);
    }
    return module.getValue(outPtr, 'float');
  } finally {
    if (outPtr) module._free(outPtr);
  }
}

/**
 * Linear RMS of Float32 PCM via `rac_audio_compute_rms`.
 * Empty frames return 0 (commons contract).
 */
export function computeRms(samples: Float32Array): number {
  if (samples.length === 0) return 0;
  return withFloat32Samples(samples, (module, samplesPtr, count) => {
    if (typeof module._rac_audio_compute_rms !== 'function') {
      throw SDKException.backendNotAvailable(
        'audioConvert',
        'WASM build missing _rac_audio_compute_rms.',
      );
    }
    return readFloatOut(module, 'rac_audio_compute_rms', (outPtr) => (
      module._rac_audio_compute_rms!(samplesPtr, count, outPtr)
    ));
  });
}

/**
 * RMS level in dBFS via `rac_audio_compute_level_db`.
 * Empty frames return the commons silence floor (−100 dB).
 */
export function computeLevelDb(samples: Float32Array): number {
  if (samples.length === 0) return -100;
  return withFloat32Samples(samples, (module, samplesPtr, count) => {
    if (typeof module._rac_audio_compute_level_db !== 'function') {
      throw SDKException.backendNotAvailable(
        'audioConvert',
        'WASM build missing _rac_audio_compute_level_db.',
      );
    }
    return readFloatOut(module, 'rac_audio_compute_level_db', (outPtr) => (
      module._rac_audio_compute_level_db!(samplesPtr, count, outPtr)
    ));
  });
}

/**
 * Normalized meter level in [0, 1] via `rac_audio_compute_level_normalized`.
 * Defaults to the commons −60 dB floor. Empty frames return 0.
 */
export function computeLevelNormalized(
  samples: Float32Array,
  floorDb: number = AUDIO_LEVEL_FLOOR_DB,
): number {
  if (samples.length === 0) return 0;
  return withFloat32Samples(samples, (module, samplesPtr, count) => {
    if (typeof module._rac_audio_compute_level_normalized !== 'function') {
      throw SDKException.backendNotAvailable(
        'audioConvert',
        'WASM build missing _rac_audio_compute_level_normalized.',
      );
    }
    return readFloatOut(module, 'rac_audio_compute_level_normalized', (outPtr) => (
      module._rac_audio_compute_level_normalized!(samplesPtr, count, floorDb, outPtr)
    ));
  });
}
