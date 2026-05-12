/**
 * @runanywhere/onnx - ONNX Runtime Backend for RunAnywhere React Native SDK
 *
 * This package registers ONNX native providers. Public STT, TTS, VAD, and
 * voice-agent APIs live in @runanywhere/core.
 *
 * ## Usage
 *
 * ```typescript
 * import { RunAnywhere, ModelCategory, InferenceFramework, ModelArtifactType } from '@runanywhere/core';
 * import { ModelLoadRequest } from '@runanywhere/proto-ts/model_types';
 * import { ONNX } from '@runanywhere/onnx';
 *
 * // Initialize core SDK
 * await RunAnywhere.initialize({ apiKey: 'your-key' });
 *
 * // Register ONNX backend
 * await ONNX.register();
 *
 * // Register models via RunAnywhere (matching iOS pattern)
 * await RunAnywhere.registerModel({
 *   id: 'sherpa-onnx-whisper-tiny.en',
 *   name: 'Sherpa Whisper Tiny',
 *   url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
 *   framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
 *   modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
 *   artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE,
 *   memoryRequirement: 75_000_000
 * });
 *
 * // Download and use
 * const download = RunAnywhere.downloadModel('sherpa-onnx-whisper-tiny.en')[Symbol.asyncIterator]();
 * while (!(await download.next()).done) {}
 * await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
 *   modelId: 'sherpa-onnx-whisper-tiny.en',
 *   category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
 * }));
 * const result = await RunAnywhere.transcribeFile('/path/to/audio.wav');
 * ```
 *
 * @packageDocumentation
 */

// =============================================================================
// Main API
// =============================================================================

export { ONNX } from './ONNX';
export { ONNXProvider } from './ONNXProvider';

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereONNX } from './specs/RunAnywhereONNX.nitro';
