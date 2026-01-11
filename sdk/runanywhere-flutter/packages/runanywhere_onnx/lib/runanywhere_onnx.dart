/// ONNX Runtime backend for RunAnywhere Flutter SDK.
///
/// This package provides STT, TTS, and VAD capabilities.
/// It is a **thin wrapper** that registers the C++ backend with the service registry.
///
/// ## Architecture (matches Swift/Kotlin exactly)
///
/// The C++ backend (RABackendONNX) handles all business logic:
/// - Service provider registration
/// - Model loading and inference for STT/TTS/VAD
/// - Streaming transcription
///
/// This Dart module just:
/// 1. Calls `rac_backend_onnx_register()` to register the backend
/// 2. The core SDK handles all operations via component APIs
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
/// // Register ONNX module (matches Swift: ONNX.register())
/// await Onnx.register();
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
