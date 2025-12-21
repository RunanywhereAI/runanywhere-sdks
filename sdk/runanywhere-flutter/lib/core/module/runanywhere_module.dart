//
// runanywhere_module.dart
// RunAnywhere Flutter SDK
//
// Protocol for external modules that extend SDK capabilities.
// Matches iOS RunAnywhereModule from Core/Module/RunAnywhereModule.swift
//

import 'package:runanywhere/core/module/capability_type.dart';
import 'package:runanywhere/core/module/inference_framework.dart';
import 'package:runanywhere/core/module/model_storage_strategy.dart';
import 'package:runanywhere/core/protocols/downloading/download_strategy.dart';

/// Protocol for RunAnywhere modules that provide AI services.
///
/// External modules (ONNX, LlamaCPP, WhisperKit, etc.) implement this abstract class
/// to register their services with the SDK in a standardized way.
///
/// ## Implementing a Module
///
/// ```dart
/// class ONNXModule extends RunAnywhereModule {
///   @override
///   String get moduleId => 'onnx';
///
///   @override
///   String get moduleName => 'ONNX Runtime';
///
///   @override
///   InferenceFramework get inferenceFramework => InferenceFramework.onnx;
///
///   @override
///   Set<CapabilityType> get capabilities => {
///     CapabilityType.stt,
///     CapabilityType.tts,
///     CapabilityType.llm,
///   };
///
///   @override
///   void register({int? priority}) {
///     // Register services with ModuleRegistry
///   }
/// }
/// ```
abstract class RunAnywhereModule {
  /// Unique identifier for this module (e.g., "onnx", "llamacpp", "whisperkit")
  String get moduleId;

  /// Human-readable display name (e.g., "ONNX Runtime", "LlamaCPP")
  String get moduleName;

  /// The inference framework this module provides (required)
  InferenceFramework get inferenceFramework;

  /// Set of capabilities this module provides
  Set<CapabilityType> get capabilities;

  /// Default priority for service registration (higher = preferred).
  /// Override to customize priority. Default is 100.
  int get defaultPriority => 100;

  /// Optional storage strategy for detecting downloaded models.
  /// Modules with directory-based models (like ONNX) should provide this.
  ModelStorageStrategy? get storageStrategy => null;

  /// Optional download strategy for custom download handling.
  /// Modules with special download requirements (like WhisperKit) should provide this.
  DownloadStrategy? get downloadStrategy => null;

  /// Register all services provided by this module with the ModuleRegistry.
  ///
  /// [priority] - Registration priority (higher values are preferred).
  ///              If null, uses [defaultPriority].
  void register({int? priority});
}

/// Metadata about a registered module.
///
/// This is a read-only snapshot of module information stored in the registry.
class ModuleMetadata {
  /// Module identifier
  final String moduleId;

  /// Display name
  final String moduleName;

  /// The inference framework
  final InferenceFramework inferenceFramework;

  /// Capabilities provided
  final Set<CapabilityType> capabilities;

  /// Registration priority used
  final int priority;

  /// When the module was registered
  final DateTime registeredAt;

  const ModuleMetadata({
    required this.moduleId,
    required this.moduleName,
    required this.inferenceFramework,
    required this.capabilities,
    required this.priority,
    required this.registeredAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModuleMetadata &&
          runtimeType == other.runtimeType &&
          moduleId == other.moduleId;

  @override
  int get hashCode => moduleId.hashCode;

  @override
  String toString() =>
      'ModuleMetadata(moduleId: $moduleId, moduleName: $moduleName, '
      'capabilities: ${capabilities.map((c) => c.rawValue).join(", ")})';
}
