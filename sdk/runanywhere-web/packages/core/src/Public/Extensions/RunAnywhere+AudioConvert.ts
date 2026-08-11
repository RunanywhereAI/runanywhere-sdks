/**
 * RunAnywhere+AudioConvert.ts
 *
 * Public PCM conversion helpers — thin WASM wrappers over commons
 * `rac_audio_pcm16_to_float32` / `rac_audio_float32_to_pcm16` /
 * `rac_audio_int16_to_wav` / `rac_audio_float32_to_wav`.
 */

import { SDKException } from '../../Foundation/SDKException.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule.js';

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

/**
 * Convert a buffer of Int16 PCM samples to Float32 samples in the range
 * `[-1.0, 1.0]` via `rac_audio_pcm16_to_float32`.
 */
export function pcm16ToFloat32(int16Bytes: ArrayBuffer): Float32Array {
  const int16Count = Math.floor(int16Bytes.byteLength / 2);
  if (int16Count === 0) return new Float32Array(0);
  const module = requireAudioModule();
  if (typeof module._rac_audio_pcm16_to_float32 !== 'function') {
    throw SDKException.backendNotAvailable(
      'audioConvert',
      'WASM build missing _rac_audio_pcm16_to_float32.',
    );
  }
  const inBytes = new Uint8Array(int16Bytes);
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
export function pcm16ToFloat32Samples(int16Bytes: ArrayBuffer): Float32Array {
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
  const inBytes = new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength);
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
export function pcm16ToWav(int16Bytes: ArrayBuffer, sampleRate: number): Uint8Array {
  const bytes = new Uint8Array(int16Bytes);
  if (bytes.byteLength === 0) return new Uint8Array(0);
  return toWav('_rac_audio_int16_to_wav', bytes, sampleRate);
}

/**
 * Encode Float32 mono PCM as a WAV container via `rac_audio_float32_to_wav`.
 */
export function float32ToWav(samples: Float32Array, sampleRate: number): Uint8Array {
  if (samples.length === 0) return new Uint8Array(0);
  const bytes = new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength);
  return toWav('_rac_audio_float32_to_wav', bytes, sampleRate);
}
