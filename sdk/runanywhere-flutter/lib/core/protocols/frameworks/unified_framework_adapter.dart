import 'dart:async';

import '../../models/framework/llm_framework.dart';
import '../../models/framework/framework_modality.dart';
import '../../models/framework/model_format.dart';
import '../../models/hardware/hardware_configuration.dart';
import '../../models/model/model_info.dart';
import '../component/component_configuration.dart';
import '../downloading/download_strategy.dart';

export '../downloading/download_strategy.dart';

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
  Object? createService(FrameworkModality modality);

  /// Load a model using this adapter
  /// - Parameters:
  ///   - model: The model to load
  ///   - modality: The modality to use
  /// - Returns: A service instance with the loaded model
  Future<Object> loadModel(ModelInfo model, FrameworkModality modality);

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
  Future<Object?> initializeComponent(
    ComponentInitParameters parameters,
    FrameworkModality modality,
  );
}

/// Mixin providing default implementations for UnifiedFrameworkAdapter
/// Use this with `with` keyword on concrete adapter classes
mixin UnifiedFrameworkAdapterDefaults on UnifiedFrameworkAdapter {
  /// Default implementation that returns the framework's supported modalities
  @override
  Set<FrameworkModality> get supportedModalities =>
      framework.supportedModalities;

  /// Default implementation - does nothing
  @override
  void onRegistration() {
    // Default: no-op - adapters should override to register their service providers
  }

  /// Default implementation - returns empty list
  @override
  List<ModelInfo> getProvidedModels() => [];

  /// Default implementation - returns null
  @override
  DownloadStrategy? getDownloadStrategy() => null;
}
