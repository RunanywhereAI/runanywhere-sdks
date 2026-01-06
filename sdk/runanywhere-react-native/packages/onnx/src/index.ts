/**
 * @runanywhere/onnx - ONNX Runtime Backend for RunAnywhere React Native SDK
 *
 * This package provides the ONNX Runtime backend for Speech-to-Text (STT)
 * and Text-to-Speech (TTS) using Sherpa-ONNX.
 *
 * ## Usage
 *
 * ```typescript
 * import { RunAnywhere, ModelCategory } from '@runanywhere/core';
 * import { ONNX, ModelArtifactType } from '@runanywhere/onnx';
 *
 * // Initialize SDK
 * await RunAnywhere.initialize({ apiKey: 'your-key' });
 *
 * // Register ONNX module (STT + TTS)
 * ONNX.register();
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

export { ONNX, ModelArtifactType, type ONNXModelOptions } from './ONNX';
export { ONNXProvider, autoRegister } from './ONNXProvider';
