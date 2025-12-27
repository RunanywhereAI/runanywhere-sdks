import 'dart:async';

import 'package:runanywhere/core/models/framework/framework_modality.dart';
import 'package:runanywhere/core/models/framework/llm_framework.dart';
import 'package:runanywhere/core/models/framework/model_format.dart';
import 'package:runanywhere/core/models/hardware/hardware_configuration.dart';
import 'package:runanywhere/core/models/model/model_info.dart';
import 'package:runanywhere/core/protocols/downloading/download_strategy.dart';

/// Unified protocol for all framework adapters (LLM, Voice, Image, etc.)
/// Matches iOS UnifiedFrameworkAdapter from Core/Protocols/Frameworks/UnifiedFrameworkAdapter.swift
abstract class UnifiedFrameworkAdapter {
  /// The framework this adapter handles
  LLMFramework get framework;

  /// The modalities this adapter supports
  Set<FrameworkModality> get supportedModalities;

  /// Supported model formats
  List<ModelFormat> get supportedFormats;

  /// Check if this adapter can handle a specific model
  /// - Parameter model: The model information
  /// - Returns: Whether this adapter can handle the model
  bool canHandle(ModelInfo model);

  /// Create a service instance based on the modality
  /// - Parameter modality: The modality to create a service for
  /// - Returns: A service instance (LLMService, VoiceService, etc.)
  dynamic createService(FrameworkModality modality);

  /// Load a model using this adapter
  /// - Parameters:
  ///   - model: The model to load
  ///   - modality: The modality to use
  /// - Returns: A service instance with the loaded model
  Future<dynamic> loadModel(ModelInfo model, FrameworkModality modality);

  /// Configure the adapter with hardware settings
  /// - Parameter hardware: Hardware configuration
  Future<void> configure(HardwareConfiguration hardware);

  /// Estimate memory usage for a model
  /// - Parameter model: The model to estimate
  /// - Returns: Estimated memory in bytes
  int estimateMemoryUsage(ModelInfo model);

  /// Get optimal hardware configuration for a model
  /// - Parameter model: The model to configure for
  /// - Returns: Optimal hardware configuration
  HardwareConfiguration optimalConfiguration(ModelInfo model);

  /// Called when the adapter is registered with the SDK
  /// Adapters should register their service providers with ModuleRegistry here
  void onRegistration();

  /// Get models provided by this adapter
  /// - Returns: Array of models this adapter provides
  List<ModelInfo> getProvidedModels();

  /// Get download strategy provided by this adapter (if any)
  /// - Returns: Download strategy or null if none
  DownloadStrategy? getDownloadStrategy();

  /// Initialize adapter with component parameters
  /// - Parameters:
  ///   - parameters: Component initialization parameters
  ///   - modality: The modality to initialize for
  /// - Returns: Initialized service ready for use
  Future<dynamic> initializeComponent({
    required AdapterInitParameters parameters,
    required FrameworkModality modality,
  });
}

/// Mixin providing default implementations for UnifiedFrameworkAdapter
/// Adapters can use this to get sensible defaults
mixin UnifiedFrameworkAdapterDefaults implements UnifiedFrameworkAdapter {
  @override
  Set<FrameworkModality> get supportedModalities =>
      framework.supportedModalities;

  @override
  void onRegistration() {
    // Default: no-op - adapters should override to register their service providers
  }

  @override
  List<ModelInfo> getProvidedModels() {
    return [];
  }

  @override
  DownloadStrategy? getDownloadStrategy() {
    return null;
  }

  @override
  Future<void> configure(HardwareConfiguration hardware) async {
    // Default: no-op - adapters should override if they need hardware configuration
  }

  @override
  HardwareConfiguration optimalConfiguration(ModelInfo model) {
    // Default: return default configuration
    return HardwareConfiguration.defaultConfig;
  }

  @override
  Future<dynamic> initializeComponent({
    required AdapterInitParameters parameters,
    required FrameworkModality modality,
  }) async {
    // Default implementation: create service and initialize if model is specified
    final service = createService(modality);
    if (service == null) {
      return null;
    }

    // If there's a model ID, try to load it
    if (parameters.modelId != null) {
      // Note: Model lookup would be done by caller
      return service;
    }

    return service;
  }
}

/// Parameters for adapter component initialization
/// Named AdapterInitParameters to avoid conflict with ComponentInitParameters
class AdapterInitParameters {
  final String? modelId;
  final Map<String, dynamic>? configuration;

  AdapterInitParameters({
    this.modelId,
    this.configuration,
  });
}
