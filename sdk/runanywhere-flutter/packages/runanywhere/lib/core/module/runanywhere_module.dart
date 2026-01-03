/// RunAnywhere Module Protocol
///
/// Protocol for SDK modules that provide AI capabilities.
/// Matches Swift RunAnywhereModule from Sources/RunAnywhere/Core/Module/RunAnywhereModule.swift
///
/// Note: Registration is now handled by the C++ platform backend via FFI.
/// Modules only need to provide metadata and call the C++ registration function.
library runanywhere_module;

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/sdk_component.dart';

/// Protocol for SDK modules that provide AI capabilities.
///
/// Modules encapsulate backend-specific functionality for the SDK.
/// Each module typically provides one or more capabilities (LLM, STT, TTS, VAD).
///
/// Registration with the C++ service registry is handled via FFI by calling
/// `rac_backend_*_register()` functions during module initialization.
///
/// ## Implementing a Module (matches Swift pattern)
///
/// ```dart
/// class LlamaCpp implements RunAnywhereModule {
///   @override
///   String get moduleId => 'llamacpp';
///
///   @override
///   String get moduleName => 'LlamaCpp';
///
///   @override
///   Set<SDKComponent> get capabilities => {SDKComponent.llm};
///
///   @override
///   int get defaultPriority => 100;
///
///   @override
///   InferenceFramework get inferenceFramework => InferenceFramework.llamaCpp;
///
///   static Future<void> register({int priority = 100}) async {
///     // Call C++ registration via FFI
///     final result = _lib.lookupFunction<...>('rac_backend_llamacpp_register')();
///     // ...
///   }
/// }
/// ```
abstract class RunAnywhereModule {
  /// Unique identifier for this module (e.g., "llamacpp", "onnx")
  String get moduleId;

  /// Human-readable name for the module
  String get moduleName;

  /// Set of capabilities this module provides
  Set<SDKComponent> get capabilities;

  /// Default priority for service registration (higher = preferred)
  int get defaultPriority;

  /// The inference framework this module uses
  InferenceFramework get inferenceFramework;
}
