/// LlamaCpp backend for RunAnywhere Flutter SDK.
///
/// This module provides LLM (Language Model) capabilities via llama.cpp
/// through the native runanywhere-core library using Dart FFI.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere/backends/llamacpp/llamacpp.dart';
///
/// // Initialize the LlamaCpp backend
/// await LlamaCppBackend.initialize();
///
/// // Now use LLM through the standard RunAnywhere API
/// final llm = ModuleRegistry.shared.llmProvider()!;
/// final service = await llm.createLLMService(LLMConfiguration(modelId: 'model.gguf'));
/// final result = await service.generate(
///   prompt: 'Hello!',
///   options: LLMGenerationOptions(maxTokens: 100),
/// );
/// ```
///
/// ## What This Provides
///
/// - **LLM (Language Model)**: Text generation using GGUF/GGML models
/// - **Streaming**: Token-by-token streaming generation
/// - **Template Support**: Auto-detection of model templates (ChatML, Llama, etc.)
///
/// ## Supported Model Formats
///
/// - `.gguf` - GGUF format (recommended)
/// - `.ggml` - GGML format (legacy)
/// - `.bin` - Binary format
///
/// ## Quantization Support
///
/// Supports all common quantization levels:
/// - Q2_K, Q3_K_S/M/L, Q4_0/1, Q4_K_S/M
/// - Q5_0/1, Q5_K_S/M, Q6_K, Q8_0
/// - IQ2_XXS/XS, IQ3_S/XXS, IQ4_NL/XS
library runanywhere_llamacpp;

// Backend entry point
export 'llamacpp_backend.dart';

// Adapter
export 'llamacpp_adapter.dart';

// Services
export 'services/llamacpp_llm_service.dart';

// Providers
export 'providers/llamacpp_llm_provider.dart';

// Utilities
export 'llamacpp_template_resolver.dart';
export 'llamacpp_error.dart';
