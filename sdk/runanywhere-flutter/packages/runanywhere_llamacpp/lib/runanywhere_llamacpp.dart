/// LlamaCpp backend for RunAnywhere Flutter SDK.
///
/// This package provides LLM (Language Model) capabilities via llama.cpp.
/// It is a **thin wrapper** that registers the C++ backend with the service registry.
///
/// ## Architecture (matches Swift/Kotlin exactly)
///
/// The C++ backend (RABackendLlamaCPP) handles all business logic:
/// - Service provider registration
/// - Model loading and inference
/// - Streaming generation
///
/// This Dart module just:
/// 1. Calls `rac_backend_llamacpp_register()` to register the backend
/// 2. The core SDK handles all LLM operations via `rac_llm_component_*`
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
/// // Register LlamaCpp module (matches Swift: LlamaCPP.register())
/// await LlamaCpp.register();
/// ```
///
/// ## Capabilities
///
/// - **LLM (Language Model)**: Text generation using GGUF models
/// - **Streaming**: Token-by-token streaming generation
///
/// ## Supported Quantizations
///
/// Q2_K, Q3_K_S/M/L, Q4_0/1, Q4_K_S/M, Q5_0/1, Q5_K_S/M, Q6_K, Q8_0, etc.
library runanywhere_llamacpp;

export 'llamacpp.dart';
export 'llamacpp_error.dart';
