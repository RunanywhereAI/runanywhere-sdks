/// Experimental Qualcomm Genie NPU backend shell for RunAnywhere Flutter SDK.
///
/// Functional LLM routing is Android/Snapdragon-only and requires native
/// binaries built with the Qualcomm Genie SDK. Without those binaries, the
/// backend remains unavailable and is not selected by the native router.
/// It is a **thin wrapper** around the native plugin shell. The package stays
/// non-routable unless native registration succeeds with SDK-backed ops.
///
/// ## Architecture (matches Swift/Kotlin exactly)
///
/// The C++ backend shell handles registration. Model loading, inference, and
/// streaming require a future SDK-backed implementation built with the
/// Qualcomm Genie SDK; the public shell returns backend-unavailable.
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
/// // Register Genie module (experimental Android/Snapdragon only; requires Genie SDK binaries)
/// await Genie.register();
/// ```
///
/// ## Capabilities
///
/// - **LLM (Language Model)**: Disabled by default; enabled only after
///   SDK-backed native registration succeeds on Android/Snapdragon.
/// - **Streaming**: Not provided by the public shell.
///
/// ## Platform Support
///
/// - **Android**: Snapdragon devices with Qualcomm Genie SDK-built native binaries
/// - **iOS**: Not supported (Genie is Android/Snapdragon only)
library runanywhere_genie;

export 'genie.dart';
export 'genie_error.dart';
