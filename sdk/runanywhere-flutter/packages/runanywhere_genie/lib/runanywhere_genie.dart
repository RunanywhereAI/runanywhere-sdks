/// Qualcomm Genie NPU backend for RunAnywhere Flutter SDK.
///
/// This package provides LLM (Language Model) capabilities via Qualcomm Genie NPU.
/// It is a **thin wrapper** that registers the C++ backend with the service registry.
///
/// ## Architecture (matches Swift/Kotlin exactly)
///
/// The C++ backend (RABackendGenie) handles all business logic:
/// - Service provider registration
/// - Model loading and inference on Snapdragon NPU
/// - Streaming generation
///
/// This Dart module just:
/// 1. Calls `rac_backend_genie_register()` to register the backend
/// 2. The core SDK handles all LLM operations via `rac_llm_component_*`
///
/// ## Quick Start
///
/// ```dart
/// import 'package:runanywhere/runanywhere.dart';
/// import 'package:runanywhere_genie/runanywhere_genie.dart';
///
/// // Initialize SDK
/// await RunAnywhere.initialize();
///
/// // Register Genie module (Android/Snapdragon only)
/// await Genie.register();
/// ```
///
/// ## Capabilities
///
/// - **LLM (Language Model)**: Text generation on Snapdragon NPU
/// - **Streaming**: Token-by-token streaming generation
///
/// ## Platform Support
///
/// - **Android**: Snapdragon devices with NPU support
/// - **iOS**: Not supported (Genie is Android/Snapdragon only)
library runanywhere_genie;

export 'genie.dart';
export 'genie_error.dart';
