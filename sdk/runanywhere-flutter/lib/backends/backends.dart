/// Backend modules for RunAnywhere Flutter SDK.
///
/// This library exports all available backend modules. Each backend provides
/// specific AI capabilities through the native runanywhere-core library.
///
/// ## Available Backends
///
/// - **ONNX Runtime**: STT, TTS, VAD capabilities via Sherpa-ONNX
/// - **LlamaCpp**: LLM capabilities via llama.cpp
///
/// ## Usage (iOS-style API)
///
/// Import and register the specific backend you need:
///
/// ```dart
/// // For ONNX capabilities (STT, TTS, VAD)
/// import 'package:runanywhere/backends/onnx/onnx.dart';
/// await Onnx.register();
///
/// // For LLM capabilities
/// import 'package:runanywhere/backends/llamacpp/llamacpp.dart';
/// await LlamaCpp.register();
/// ```
///
/// Or import all backends:
///
/// ```dart
/// import 'package:runanywhere/backends/backends.dart';
///
/// // Register all backends
/// await Onnx.register(priority: 100);  // STT, TTS, VAD
/// await LlamaCpp.register(priority: 100);  // LLM
/// ```
library runanywhere_backends;

// LlamaCpp backend (LLM)
export 'llamacpp/llamacpp.dart';
// ONNX Runtime backend (STT, TTS, VAD)
export 'onnx/onnx.dart';

// Native utilities (for advanced usage)
// Note: Native backend is in lib/native/, import via:
// import 'package:runanywhere/native/native.dart';
