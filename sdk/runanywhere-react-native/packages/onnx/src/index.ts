/**
 * @runanywhere/onnx - ONNX Runtime Backend for RunAnywhere React Native SDK
 *
 * This package provides the ONNX Runtime backend for Speech-to-Text (STT),
 * Text-to-Speech (TTS), and Voice Activity Detection (VAD) using ONNX Runtime.
 *
 * ## Usage
 *
 * ```typescript
 * import { RunAnywhere, ModelCategory } from '@runanywhere/core';
 * import { ONNX, ONNXProvider, ModelArtifactType } from '@runanywhere/onnx';
 *
 * // Initialize core SDK
 * await RunAnywhere.initialize({ apiKey: 'your-key' });
 *
 * // Register ONNX backend (calls native rac_backend_onnx_register)
 * await ONNXProvider.register();
 *
 * // Add STT model
 * ONNX.addModel({
 *   id: 'sherpa-onnx-whisper-tiny.en',
 *   name: 'Sherpa Whisper Tiny',
 *   url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
 *   modality: ModelCategory.SpeechRecognition,
 *   artifactType: ModelArtifactType.TarGzArchive,
 *   memoryRequirement: 75_000_000
 * });
 *
 * // Add TTS model
 * ONNX.addModel({
 *   id: 'vits-piper-en_US-lessac-medium',
 *   name: 'Piper TTS (US English)',
 *   url: 'https://github.com/.../vits-piper-en_US-lessac-medium.tar.gz',
 *   modality: ModelCategory.SpeechSynthesis,
 *   memoryRequirement: 65_000_000
 * });
 *
 * // Download and use
 * await RunAnywhere.downloadModel('sherpa-onnx-whisper-tiny.en');
 * await RunAnywhere.loadSTTModel('sherpa-onnx-whisper-tiny.en');
 * const result = await RunAnywhere.transcribeFile('/path/to/audio.wav');
 * ```
 *
 * @packageDocumentation
 */

// =============================================================================
// Main API
// =============================================================================

export { ONNX, ModelArtifactType, type ONNXModelOptions } from './ONNX';
export { ONNXProvider, autoRegister } from './ONNXProvider';

// =============================================================================
// Native Module
// =============================================================================

export {
  NativeRunAnywhereONNX,
  getNativeONNXModule,
  requireNativeONNXModule,
  isNativeONNXModuleAvailable,
} from './native/NativeRunAnywhereONNX';
export type { NativeRunAnywhereONNXModule } from './native/NativeRunAnywhereONNX';

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereONNX } from './specs/RunAnywhereONNX.nitro';
