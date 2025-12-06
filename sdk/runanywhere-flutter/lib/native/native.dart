/// RunAnywhere Native FFI Module
///
/// This module provides Dart FFI bindings to the RunAnywhere native C API,
/// enabling on-device AI capabilities (STT, TTS, LLM, VAD, Embeddings).
///
/// ## Usage
///
/// ```dart
/// import 'package:runanywhere/native/native.dart';
///
/// // Create and initialize backend
/// final backend = NativeBackend();
/// backend.create('onnx');
///
/// // Load and use STT model
/// backend.loadSttModel('/path/to/whisper-model', modelType: 'whisper');
/// final result = backend.transcribe(audioSamples);
/// print('Transcription: ${result['text']}');
///
/// // Clean up
/// backend.dispose();
/// ```
///
/// ## Using Providers
///
/// For higher-level integration with the SDK's ModuleRegistry:
///
/// ```dart
/// import 'package:runanywhere/native/native.dart';
///
/// // Register native providers with the SDK
/// await NativeProviderRegistration.registerAll();
/// ```
library native;

// Core FFI types and constants
export 'ffi_types.dart';

// Platform-specific library loader
export 'platform_loader.dart';

// Main backend wrapper
export 'native_backend.dart';

// Native service providers
export 'providers/providers.dart';

// Provider registration helper
export 'native_provider_registration.dart';
