/// LlamaCpp backend for RunAnywhere Flutter SDK.
///
/// This package provides LLM (Language Model) capabilities via llama.cpp
/// through the native runanywhere-core library using Dart FFI.
///
/// ## Installation
///
/// Add both the core SDK and this backend to your pubspec.yaml:
///
/// ```yaml
/// dependencies:
///   runanywhere: ^0.15.8
///   runanywhere_llamacpp: ^0.15.8
/// ```
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere/runanywhere.dart';
/// import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
///
/// // Initialize SDK
/// await RunAnywhere.initialize();
///
/// // Register LlamaCpp module
/// await LlamaCpp.register();
///
/// // Add models
/// LlamaCpp.addModel(
///   name: 'SmolLM2 360M Q8_0',
///   url: 'https://huggingface.co/.../model.gguf',
///   memoryRequirement: 500000000,
/// );
/// ```
///
/// ## Capabilities
///
/// - **LLM (Language Model)**: Text generation using GGUF/GGML models
/// - **Streaming**: Token-by-token streaming generation
/// - **Template Support**: Auto-detection of model templates
///
/// ## Supported Quantizations
///
/// - Q2_K, Q3_K_S/M/L, Q4_0/1, Q4_K_S/M
/// - Q5_0/1, Q5_K_S/M, Q6_K, Q8_0
/// - IQ2_XXS/XS, IQ3_S/XXS, IQ4_NL/XS
library runanywhere_llamacpp;

export 'llamacpp.dart';
export 'llamacpp_error.dart';
export 'llamacpp_template_resolver.dart';
export 'providers/llamacpp_llm_provider.dart';
export 'services/llamacpp_llm_service.dart';
