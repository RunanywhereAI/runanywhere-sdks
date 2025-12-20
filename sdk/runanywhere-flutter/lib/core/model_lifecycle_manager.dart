import 'dart:async';
import 'package:flutter/foundation.dart';

import 'models/framework/llm_framework.dart';
import '../foundation/logging/sdk_logger.dart';
import '../core/module_registry.dart' show LLMService;

/// Represents the current state of a model
/// Matches iOS ModelLoadState from Core/ModelLifecycleManager.swift
enum ModelLoadState {
  notLoaded,
  loading,
  loaded,
  unloading,
  error;

  bool get isLoaded => this == ModelLoadState.loaded;
  bool get isLoading => this == ModelLoadState.loading;
}

/// Represents a model load state with progress
class ModelLoadStateWithProgress {
  final ModelLoadState state;
  final double? progress;
  final String? errorMessage;

  const ModelLoadStateWithProgress({
    required this.state,
    this.progress,
    this.errorMessage,
  });

  factory ModelLoadStateWithProgress.notLoaded() =>
      const ModelLoadStateWithProgress(
        state: ModelLoadState.notLoaded,
      );

  factory ModelLoadStateWithProgress.loading({double progress = 0.0}) =>
      ModelLoadStateWithProgress(
        state: ModelLoadState.loading,
        progress: progress,
      );

  factory ModelLoadStateWithProgress.loaded() =>
      const ModelLoadStateWithProgress(
        state: ModelLoadState.loaded,
      );

  factory ModelLoadStateWithProgress.unloading() =>
      const ModelLoadStateWithProgress(
        state: ModelLoadState.unloading,
      );

  factory ModelLoadStateWithProgress.error(String message) =>
      ModelLoadStateWithProgress(
        state: ModelLoadState.error,
        errorMessage: message,
      );

  bool get isLoaded => state.isLoaded;
  bool get isLoading => state.isLoading;
}

/// Supported modalities for model lifecycle tracking
/// Matches iOS Modality from Core/ModelLifecycleManager.swift
enum Modality {
  llm('llm', 'Language Model'),
  stt('stt', 'Speech Recognition'),
  tts('tts', 'Text to Speech'),
  vlm('vlm', 'Vision Model'),
  speakerDiarization('speaker_diarization', 'Speaker Diarization');

  final String rawValue;
  final String displayName;

  const Modality(this.rawValue, this.displayName);
}

/// Information about a currently loaded model
/// Matches iOS LoadedModelState from Core/ModelLifecycleManager.swift
class LoadedModelState {
  final String modelId;
  final String modelName;
  final LLMFramework framework;
  final Modality modality;
  final ModelLoadStateWithProgress state;
  final DateTime? loadedAt;
  final int? memoryUsage;

  // Service instances - stored alongside state for unified lifecycle management
  final LLMService? llmService;
  final dynamic sttService;
  final dynamic ttsService;

  LoadedModelState({
    required this.modelId,
    required this.modelName,
    required this.framework,
    required this.modality,
    required this.state,
    this.loadedAt,
    this.memoryUsage,
    this.llmService,
    this.sttService,
    this.ttsService,
  });

  LoadedModelState copyWith({
    ModelLoadStateWithProgress? state,
    DateTime? loadedAt,
    int? memoryUsage,
    LLMService? llmService,
    dynamic sttService,
    dynamic ttsService,
  }) {
    return LoadedModelState(
      modelId: modelId,
      modelName: modelName,
      framework: framework,
      modality: modality,
      state: state ?? this.state,
      loadedAt: loadedAt ?? this.loadedAt,
      memoryUsage: memoryUsage ?? this.memoryUsage,
      llmService: llmService ?? this.llmService,
      sttService: sttService ?? this.sttService,
      ttsService: ttsService ?? this.ttsService,
    );
  }
}

/// Events published when model lifecycle changes
/// Matches iOS ModelLifecycleEvent from Core/ModelLifecycleManager.swift
abstract class ModelLifecycleEvent {
  const ModelLifecycleEvent();
}

class ModelWillLoad extends ModelLifecycleEvent {
  final String modelId;
  final Modality modality;

  const ModelWillLoad({required this.modelId, required this.modality});
}

class ModelLoadProgress extends ModelLifecycleEvent {
  final String modelId;
  final Modality modality;
  final double progress;

  const ModelLoadProgress({
    required this.modelId,
    required this.modality,
    required this.progress,
  });
}

class ModelDidLoad extends ModelLifecycleEvent {
  final String modelId;
  final Modality modality;
  final LLMFramework framework;

  const ModelDidLoad({
    required this.modelId,
    required this.modality,
    required this.framework,
  });
}

class ModelWillUnload extends ModelLifecycleEvent {
  final String modelId;
  final Modality modality;

  const ModelWillUnload({required this.modelId, required this.modality});
}

class ModelDidUnload extends ModelLifecycleEvent {
  final String modelId;
  final Modality modality;

  const ModelDidUnload({required this.modelId, required this.modality});
}

class ModelLoadFailed extends ModelLifecycleEvent {
  final String modelId;
  final Modality modality;
  final String error;

  const ModelLoadFailed({
    required this.modelId,
    required this.modality,
    required this.error,
  });
}

/// Centralized tracker for model lifecycle across all modalities
/// Thread-safe class that provides real-time state updates
/// Matches iOS ModelLifecycleTracker from Core/ModelLifecycleManager.swift
class ModelLifecycleTracker extends ChangeNotifier {
  // Singleton
  static final ModelLifecycleTracker shared = ModelLifecycleTracker._();

  ModelLifecycleTracker._() {
    _logger.info('ModelLifecycleManager initialized');
  }

  final SDKLogger _logger = SDKLogger(category: 'ModelLifecycleManager');

  /// Current state of all models, keyed by modality
  final Map<Modality, LoadedModelState> _modelsByModality = {};

  /// Event controller for lifecycle changes
  final StreamController<ModelLifecycleEvent> _lifecycleEventsController =
      StreamController<ModelLifecycleEvent>.broadcast();

  /// Stream of lifecycle events
  Stream<ModelLifecycleEvent> get lifecycleEvents =>
      _lifecycleEventsController.stream;

  /// Get current state of all models
  Map<Modality, LoadedModelState> get modelsByModality =>
      Map.unmodifiable(_modelsByModality);

  /// Get currently loaded model for a specific modality
  LoadedModelState? loadedModel(Modality modality) {
    return _modelsByModality[modality];
  }

  /// Check if a model is loaded for a specific modality
  bool isModelLoaded(Modality modality) {
    return _modelsByModality[modality]?.state.isLoaded ?? false;
  }

  /// Get all currently loaded models
  List<LoadedModelState> allLoadedModels() {
    return _modelsByModality.values
        .where((state) => state.state.isLoaded)
        .toList();
  }

  /// Check if a specific model is loaded
  bool isModelLoadedById(String modelId) {
    return _modelsByModality.values.any(
      (state) => state.modelId == modelId && state.state.isLoaded,
    );
  }

  /// Called when a model starts loading
  void modelWillLoad({
    required String modelId,
    required String modelName,
    required LLMFramework framework,
    required Modality modality,
  }) {
    _logger.info('Model will load: $modelName [${modality.rawValue}]');

    final state = LoadedModelState(
      modelId: modelId,
      modelName: modelName,
      framework: framework,
      modality: modality,
      state: ModelLoadStateWithProgress.loading(progress: 0),
    );

    _modelsByModality[modality] = state;
    _lifecycleEventsController
        .add(ModelWillLoad(modelId: modelId, modality: modality));
    notifyListeners();
  }

  /// Update loading progress
  void updateLoadProgress({
    required String modelId,
    required Modality modality,
    required double progress,
  }) {
    final currentState = _modelsByModality[modality];
    if (currentState == null || currentState.modelId != modelId) return;

    _modelsByModality[modality] = currentState.copyWith(
      state: ModelLoadStateWithProgress.loading(progress: progress),
    );

    _lifecycleEventsController.add(ModelLoadProgress(
      modelId: modelId,
      modality: modality,
      progress: progress,
    ));
    notifyListeners();
  }

  /// Called when a model finishes loading successfully
  void modelDidLoad({
    required String modelId,
    required String modelName,
    required LLMFramework framework,
    required Modality modality,
    int? memoryUsage,
    LLMService? llmService,
    dynamic sttService,
    dynamic ttsService,
  }) {
    _logger.info(
        'Model loaded: $modelName [${modality.rawValue}] with ${framework.rawValue}');

    final state = LoadedModelState(
      modelId: modelId,
      modelName: modelName,
      framework: framework,
      modality: modality,
      state: ModelLoadStateWithProgress.loaded(),
      loadedAt: DateTime.now(),
      memoryUsage: memoryUsage,
      llmService: llmService,
      sttService: sttService,
      ttsService: ttsService,
    );

    _modelsByModality[modality] = state;
    _lifecycleEventsController.add(ModelDidLoad(
      modelId: modelId,
      modality: modality,
      framework: framework,
    ));
    notifyListeners();
  }

  /// Get cached LLM service for a model ID
  LLMService? llmService(String modelId) {
    final state = _modelsByModality[Modality.llm];
    if (state == null || state.modelId != modelId || !state.state.isLoaded) {
      return null;
    }
    if (state.llmService != null) {
      _logger.info('✅ Found cached LLM service for model: $modelId');
    }
    return state.llmService;
  }

  /// Get cached STT service for a model ID
  dynamic sttService(String modelId) {
    final state = _modelsByModality[Modality.stt];
    if (state == null || state.modelId != modelId || !state.state.isLoaded) {
      return null;
    }
    if (state.sttService != null) {
      _logger.info('✅ Found cached STT service for model: $modelId');
    }
    return state.sttService;
  }

  /// Get cached TTS service for a model ID
  dynamic ttsService(String modelId) {
    final state = _modelsByModality[Modality.tts];
    if (state == null || state.modelId != modelId || !state.state.isLoaded) {
      return null;
    }
    if (state.ttsService != null) {
      _logger.info('✅ Found cached TTS service for model: $modelId');
    }
    return state.ttsService;
  }

  /// Called when a model fails to load
  void modelLoadFailed({
    required String modelId,
    required Modality modality,
    required String error,
  }) {
    _logger
        .error('Model load failed: $modelId [${modality.rawValue}] - $error');

    final currentState = _modelsByModality[modality];
    if (currentState != null) {
      _modelsByModality[modality] = currentState.copyWith(
        state: ModelLoadStateWithProgress.error(error),
      );
    }

    _lifecycleEventsController.add(ModelLoadFailed(
      modelId: modelId,
      modality: modality,
      error: error,
    ));
    notifyListeners();
  }

  /// Called when a model starts unloading
  void modelWillUnload({required String modelId, required Modality modality}) {
    _logger.info('Model will unload: $modelId [${modality.rawValue}]');

    final currentState = _modelsByModality[modality];
    if (currentState != null && currentState.modelId == modelId) {
      _modelsByModality[modality] = currentState.copyWith(
        state: ModelLoadStateWithProgress.unloading(),
      );
    }

    _lifecycleEventsController
        .add(ModelWillUnload(modelId: modelId, modality: modality));
    notifyListeners();
  }

  /// Called when a model finishes unloading
  void modelDidUnload({required String modelId, required Modality modality}) {
    _logger.info('Model unloaded: $modelId [${modality.rawValue}]');

    _modelsByModality.remove(modality);
    _lifecycleEventsController
        .add(ModelDidUnload(modelId: modelId, modality: modality));
    notifyListeners();
  }

  /// Clear all loaded models (for cleanup)
  void clearAll() {
    _logger.info('Clearing all loaded models');
    _modelsByModality.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _lifecycleEventsController.close();
    super.dispose();
  }
}
