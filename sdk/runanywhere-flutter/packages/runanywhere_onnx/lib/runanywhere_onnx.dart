/// ONNX Runtime backend for RunAnywhere Flutter SDK.
///
/// This package provides STT, TTS, and VAD capabilities via the native
/// runanywhere-core library using Dart FFI.
///
/// ## Installation
///
/// Add both the core SDK and this backend to your pubspec.yaml:
///
/// ```yaml
/// dependencies:
///   runanywhere: ^0.15.8
///   runanywhere_onnx: ^0.15.8
/// ```
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere/runanywhere.dart';
/// import 'package:runanywhere_onnx/runanywhere_onnx.dart';
///
/// // Initialize SDK
/// await RunAnywhere.initialize();
///
/// // Register ONNX module
/// await Onnx.register();
///
/// // Add STT model
/// Onnx.addModel(
///   name: 'Sherpa Whisper Tiny',
///   url: 'https://github.com/.../sherpa-onnx-whisper-tiny.en.tar.gz',
///   modality: ModelCategory.speechRecognition,
/// );
///
/// // Add TTS model
/// Onnx.addModel(
///   name: 'Piper TTS',
///   url: 'https://github.com/.../vits-piper-en_US-lessac-medium.tar.gz',
///   modality: ModelCategory.speechSynthesis,
/// );
/// ```
///
/// ## Capabilities
///
/// - **STT (Speech-to-Text)**: Streaming and batch transcription
/// - **TTS (Text-to-Speech)**: Neural voice synthesis
/// - **VAD (Voice Activity Detection)**: Real-time speech detection
library runanywhere_onnx;

export 'onnx.dart';
export 'onnx_download_strategy.dart';
export 'providers/onnx_stt_provider.dart';
export 'providers/onnx_tts_provider.dart';
export 'providers/onnx_vad_provider.dart';
export 'services/onnx_stt_service.dart';
export 'services/onnx_tts_service.dart';
export 'services/onnx_vad_service.dart';
