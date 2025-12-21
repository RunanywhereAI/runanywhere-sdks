import 'dart:async';

import 'package:runanywhere/core/models/framework/llm_framework.dart';
import 'package:runanywhere/core/module/module.dart';
// SpeakerInfo types for diarization service return type
import 'package:runanywhere/features/speaker_diarization/models/speaker_diarization_speaker_info.dart';
// STT types are imported from centralized location to avoid duplication
import 'package:runanywhere/features/stt/stt_types.dart';
// TTS types imported from canonical locations
import 'package:runanywhere/features/tts/protocol/tts_service.dart';
// VADService is imported for use in VADServiceProvider return type
import 'package:runanywhere/features/vad/vad_service.dart' show VADService;

// Export speaker diarization types
export '../features/speaker_diarization/models/speaker_diarization_speaker_info.dart';
// Export STT types for external consumers
export '../features/stt/stt_types.dart';
// Export TTS types for external consumers
export '../features/tts/models/tts_options.dart';
export '../features/tts/protocol/tts_service.dart';
// Export all VAD types for external consumers
export '../features/vad/vad_service.dart'
    show VADService, VADResult, SpeechActivityEvent;
// Export module types for external consumers
export 'module/module.dart';

/// Central registry for external AI module implementations.
///
/// This allows optional dependencies to register their implementations
/// at runtime, enabling a plugin-based architecture where modules like
/// WhisperKit, llama.cpp, and FluidAudioDiarization can be added as needed.
///
/// ## Module Registration (iOS Parity)
///
/// Modules can be registered using the formal [RunAnywhereModule] protocol:
///
/// ```dart
/// ModuleRegistry.shared.registerModule(ONNXModule());
/// ```
///
/// ## Provider Registration (Legacy)
///
/// Individual service providers can also be registered directly:
///
/// ```dart
/// ModuleRegistry.shared.registerSTT(mySTTProvider, priority: 150);
/// ```
class ModuleRegistry {
  /// Singleton instance
  static final ModuleRegistry shared = ModuleRegistry._();

  ModuleRegistry._();

  // Module-level tracking (iOS parity)
  final Map<String, ModuleMetadata> _registeredModules = {};
  final Map<InferenceFramework, ModelStorageStrategy> _storageStrategies = {};
  final Map<InferenceFramework, DownloadStrategy> _downloadStrategies = {};

  // Provider-level tracking (existing functionality)
  final List<_PrioritizedProvider<STTServiceProvider>> _sttProviders = [];
  final List<_PrioritizedProvider<LLMServiceProvider>> _llmProviders = [];
  final List<_PrioritizedProvider<TTSServiceProvider>> _ttsProviders = [];
  final List<_PrioritizedProvider<VADServiceProvider>> _vadProviders = [];
  final List<SpeakerDiarizationServiceProvider> _speakerDiarizationProviders =
      [];

  /// Register a Speech-to-Text provider with optional priority
  /// Higher priority providers are preferred (default: 100)
  void registerSTT(STTServiceProvider provider, {int priority = 100}) {
    final prioritizedProvider = _PrioritizedProvider(
      provider: provider,
      priority: priority,
    );
    _sttProviders.add(prioritizedProvider);
    _sttProviders.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Register a Language Model provider with optional priority
  /// Higher priority providers are preferred (default: 100)
  void registerLLM(LLMServiceProvider provider, {int priority = 100}) {
    final prioritizedProvider = _PrioritizedProvider(
      provider: provider,
      priority: priority,
    );
    _llmProviders.add(prioritizedProvider);
    _llmProviders.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Register a Text-to-Speech provider with optional priority
  /// Higher priority providers are preferred (default: 100)
  void registerTTS(TTSServiceProvider provider, {int priority = 100}) {
    final prioritizedProvider = _PrioritizedProvider(
      provider: provider,
      priority: priority,
    );
    _ttsProviders.add(prioritizedProvider);
    _ttsProviders.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Register a Voice Activity Detection provider with optional priority
  /// Higher priority providers are preferred (default: 100)
  void registerVAD(VADServiceProvider provider, {int priority = 100}) {
    final prioritizedProvider = _PrioritizedProvider(
      provider: provider,
      priority: priority,
    );
    _vadProviders.add(prioritizedProvider);
    _vadProviders.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Register a Speaker Diarization provider
  void registerSpeakerDiarization(SpeakerDiarizationServiceProvider provider) {
    _speakerDiarizationProviders.add(provider);
  }

  // ============================================================================
  // Module Registration (iOS Parity)
  // ============================================================================

  /// Register a module with the SDK.
  ///
  /// [module] - The module to register.
  /// [priority] - Override the default priority (optional).
  ///
  /// The module's [RunAnywhereModule.register] method will be called to register
  /// its service providers with the registry.
  void registerModule(RunAnywhereModule module, {int? priority}) {
    final effectivePriority = priority ?? module.defaultPriority;

    // Check for duplicate registration
    if (_registeredModules.containsKey(module.moduleId)) {
      // Already registered, skip
      return;
    }

    // Call the module's register method to register its services
    module.register(priority: effectivePriority);

    // Store metadata
    final metadata = ModuleMetadata(
      moduleId: module.moduleId,
      moduleName: module.moduleName,
      inferenceFramework: module.inferenceFramework,
      capabilities: module.capabilities,
      priority: effectivePriority,
      registeredAt: DateTime.now(),
    );
    _registeredModules[module.moduleId] = metadata;

    // Store storage strategy if provided
    final storageStrategy = module.storageStrategy;
    if (storageStrategy != null) {
      _storageStrategies[module.inferenceFramework] = storageStrategy;
    }

    // Store download strategy if provided
    final downloadStrategy = module.downloadStrategy;
    if (downloadStrategy != null) {
      _downloadStrategies[module.inferenceFramework] = downloadStrategy;
    }
  }

  /// Check if a module is registered.
  bool isModuleRegistered(String moduleId) {
    return _registeredModules.containsKey(moduleId);
  }

  /// Get metadata for a registered module.
  ModuleMetadata? moduleMetadata(String moduleId) {
    return _registeredModules[moduleId];
  }

  /// Get all registered module IDs.
  List<String> get moduleIds => _registeredModules.keys.toList()..sort();

  /// Get all registered module metadata.
  List<ModuleMetadata> get allModules {
    final modules = _registeredModules.values.toList();
    modules.sort((a, b) => a.moduleId.compareTo(b.moduleId));
    return modules;
  }

  /// Get modules that provide a specific capability.
  List<ModuleMetadata> modulesForCapability(CapabilityType capability) {
    return _registeredModules.values
        .where((m) => m.capabilities.contains(capability))
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Check if any module provides a specific capability.
  bool hasCapabilityFromModule(CapabilityType capability) {
    return _registeredModules.values
        .any((m) => m.capabilities.contains(capability));
  }

  /// Get the storage strategy for a framework.
  ModelStorageStrategy? storageStrategy(InferenceFramework framework) {
    return _storageStrategies[framework];
  }

  /// Check if a storage strategy is registered for a framework.
  bool hasStorageStrategy(InferenceFramework framework) {
    return _storageStrategies.containsKey(framework);
  }

  /// Get the download strategy for a framework.
  DownloadStrategy? downloadStrategyForFramework(InferenceFramework framework) {
    return _downloadStrategies[framework];
  }

  /// Check if a download strategy is registered for a framework.
  bool hasDownloadStrategy(InferenceFramework framework) {
    return _downloadStrategies.containsKey(framework);
  }

  /// Reset all module registrations (useful for testing).
  void reset() {
    _registeredModules.clear();
    _storageStrategies.clear();
    _downloadStrategies.clear();
    _sttProviders.clear();
    _llmProviders.clear();
    _ttsProviders.clear();
    _vadProviders.clear();
    _speakerDiarizationProviders.clear();
  }

  // ============================================================================
  // Provider Queries (existing functionality)
  // ============================================================================

  /// Get an STT provider for the specified model (returns highest priority match)
  STTServiceProvider? sttProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _sttProviders
            .firstWhere(
              (p) => p.provider.canHandle(modelId: modelId),
            )
            .provider;
      } catch (e) {
        return _sttProviders.isNotEmpty ? _sttProviders.first.provider : null;
      }
    }
    return _sttProviders.isNotEmpty ? _sttProviders.first.provider : null;
  }

  /// Get an LLM provider for the specified model (returns highest priority match)
  LLMServiceProvider? llmProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _llmProviders
            .firstWhere(
              (p) => p.provider.canHandle(modelId: modelId),
            )
            .provider;
      } catch (e) {
        return _llmProviders.isNotEmpty ? _llmProviders.first.provider : null;
      }
    }
    return _llmProviders.isNotEmpty ? _llmProviders.first.provider : null;
  }

  /// Get a TTS provider for the specified model (returns highest priority match)
  TTSServiceProvider? ttsProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _ttsProviders
            .firstWhere(
              (p) => p.provider.canHandle(modelId: modelId),
            )
            .provider;
      } catch (e) {
        return _ttsProviders.isNotEmpty ? _ttsProviders.first.provider : null;
      }
    }
    return _ttsProviders.isNotEmpty ? _ttsProviders.first.provider : null;
  }

  /// Get ALL TTS providers that can handle the specified model (sorted by priority)
  List<TTSServiceProvider> allTTSProviders({String? modelId}) {
    if (modelId != null) {
      return _ttsProviders
          .where((p) => p.provider.canHandle(modelId: modelId))
          .map((p) => p.provider)
          .toList();
    }
    return _ttsProviders.map((p) => p.provider).toList();
  }

  /// Get a VAD provider for the specified model (returns highest priority match)
  VADServiceProvider? vadProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _vadProviders
            .firstWhere(
              (p) => p.provider.canHandle(modelId: modelId),
            )
            .provider;
      } catch (e) {
        return _vadProviders.isNotEmpty ? _vadProviders.first.provider : null;
      }
    }
    return _vadProviders.isNotEmpty ? _vadProviders.first.provider : null;
  }

  /// Get ALL VAD providers that can handle the specified model (sorted by priority)
  List<VADServiceProvider> allVADProviders({String? modelId}) {
    if (modelId != null) {
      return _vadProviders
          .where((p) => p.provider.canHandle(modelId: modelId))
          .map((p) => p.provider)
          .toList();
    }
    return _vadProviders.map((p) => p.provider).toList();
  }

  /// Get a Speaker Diarization provider
  SpeakerDiarizationServiceProvider? speakerDiarizationProvider(
      {String? modelId}) {
    if (modelId != null) {
      try {
        return _speakerDiarizationProviders.firstWhere(
          (p) => p.canHandle(modelId: modelId),
        );
      } catch (e) {
        return _speakerDiarizationProviders.isNotEmpty
            ? _speakerDiarizationProviders.first
            : null;
      }
    }
    return _speakerDiarizationProviders.isNotEmpty
        ? _speakerDiarizationProviders.first
        : null;
  }

  /// Check if STT is available
  bool get hasSTT => _sttProviders.isNotEmpty;

  /// Check if LLM is available
  bool get hasLLM => _llmProviders.isNotEmpty;

  /// Check if TTS is available
  bool get hasTTS => _ttsProviders.isNotEmpty;

  /// Check if VAD is available
  bool get hasVAD => _vadProviders.isNotEmpty;

  /// Check if Speaker Diarization is available
  bool get hasSpeakerDiarization => _speakerDiarizationProviders.isNotEmpty;

  /// Get list of all registered modules
  List<String> get registeredModules {
    final modules = <String>[];
    if (hasSTT) modules.add('STT');
    if (hasLLM) modules.add('LLM');
    if (hasTTS) modules.add('TTS');
    if (hasVAD) modules.add('VAD');
    if (hasSpeakerDiarization) modules.add('SpeakerDiarization');
    return modules;
  }

  // ============================================================================
  // Module Discovery (iOS Parity)
  // ============================================================================

  /// Register all modules that have been discovered.
  /// This should be called at app startup after all imports.
  /// Matches iOS ModuleRegistry.registerDiscoveredModules().
  void registerDiscoveredModules() {
    final discovered = ModuleDiscovery.discoveredModules;

    for (final module in discovered) {
      if (!_registeredModules.containsKey(module.moduleId)) {
        registerModule(module);
      }
    }
  }
}

/// Internal structure to track providers with their priorities
class _PrioritizedProvider<T> {
  final T provider;
  final int priority;

  _PrioritizedProvider({required this.provider, required this.priority});
}

// Service provider interfaces (to be implemented by external modules)
abstract class STTServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<STTService> createSTTService(dynamic configuration);
}

abstract class LLMServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<LLMService> createLLMService(dynamic configuration);
}

/// Provider for Text-to-Speech services
abstract class TTSServiceProvider {
  String get name;
  String get version;
  bool canHandle({String? modelId});
  Future<TTSService> createTTSService(dynamic configuration);
}

/// Provider for Voice Activity Detection services
abstract class VADServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<VADService> createVADService(dynamic configuration);
}

abstract class SpeakerDiarizationServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<SpeakerDiarizationService> createSpeakerDiarizationService(
    dynamic configuration,
  );
}

// Service interfaces (to be implemented by providers)
abstract class STTService {
  Future<void> initialize({String? modelPath});
  Future<STTTranscriptionResult> transcribe({
    required List<int> audioData,
    required STTOptions options,
  });
  bool get isReady;
  String? get currentModel;
  bool get supportsStreaming;

  /// The inference framework used by this service.
  /// Required for analytics and performance tracking.
  /// Matches iOS STTService.inferenceFramework property.
  String? get inferenceFramework;

  Future<void> cleanup();
}

abstract class LLMService {
  Future<void> initialize({String? modelPath});
  Future<LLMGenerationResult> generate({
    required String prompt,
    required LLMGenerationOptions options,
  });
  Stream<String> generateStream({
    required String prompt,
    required LLMGenerationOptions options,
  });
  bool get isReady;

  /// Whether this service supports true streaming generation.
  /// Matches iOS LLMService.supportsStreaming property.
  bool get supportsStreaming;

  /// Cancel the current generation operation.
  /// Note: Best-effort; some backends may not support mid-generation cancellation.
  /// Matches iOS LLMService.cancel() method.
  Future<void> cancel();

  Future<void> cleanup();
}

// TTSService is imported from features/tts/protocol/tts_service.dart (see top of file)

// VADService is exported from features/vad/vad_service.dart (see top of file)

abstract class SpeakerDiarizationService {
  Future<void> initialize({String? modelPath});
  Future<SpeakerDiarizationResult> process(List<int> audioData);

  /// Get all identified speakers
  Future<List<SpeakerDiarizationSpeakerInfo>> getAllSpeakers();

  /// Update a speaker's display name
  /// [speakerId] - The speaker ID to update
  /// [name] - The new display name
  void updateSpeakerName({required String speakerId, required String name});

  /// Reset speaker diarization state (clears all speaker data)
  Future<void> reset();

  bool get isReady;
  Future<void> cleanup();
}

// STTOptions, STTTranscriptionResult, TimestampInfo, and AlternativeTranscription
// are imported from ../features/stt/stt_types.dart (see imports above)

/// LLM Generation Options
/// Matches iOS RunAnywhereGenerationOptions from GenerationOptions.swift
class LLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  final double topP;
  final bool enableRealTimeTracking;
  final List<String> stopSequences;
  final bool streamingEnabled;
  final String? systemPrompt;
  final LLMFramework? preferredFramework;

  LLMGenerationOptions({
    this.maxTokens = 100,
    this.temperature = 0.7,
    this.topP = 1.0,
    this.enableRealTimeTracking = true,
    this.stopSequences = const [],
    this.streamingEnabled = false,
    this.systemPrompt,
    this.preferredFramework,
  });
}

/// Result of a text generation request.
/// Matches iOS LLMGenerationResult from Features/LLM/Models/LLMGenerationResult.swift
class LLMGenerationResult {
  /// Generated text (with thinking content removed if extracted)
  final String text;

  /// Thinking/reasoning content extracted from the response (for reasoning models)
  /// Matches iOS LLMGenerationResult.thinkingContent
  final String? thinkingContent;

  /// Number of input/prompt tokens
  final int inputTokens;

  /// Number of output tokens used
  final int tokensUsed;

  /// Model used for generation
  final String modelUsed;

  /// Total latency in milliseconds (from start to completion)
  final double latencyMs;

  /// Framework used for generation
  final String? framework;

  /// Tokens generated per second
  final double tokensPerSecond;

  /// Time to first token in milliseconds (only available for streaming generations).
  /// This is null for non-streaming generate() calls since the entire response
  /// is returned at once. Use generateStream() to get TTFT metrics.
  /// Matches iOS LLMGenerationResult.timeToFirstTokenMs
  final double? timeToFirstTokenMs;

  /// Number of tokens used for thinking/reasoning
  final int thinkingTokens;

  /// Number of response tokens (excluding thinking tokens)
  final int responseTokens;

  LLMGenerationResult({
    required this.text,
    this.thinkingContent,
    this.inputTokens = 0,
    this.tokensUsed = 0,
    this.modelUsed = 'unknown',
    this.latencyMs = 0,
    this.framework,
    this.tokensPerSecond = 0,
    this.timeToFirstTokenMs,
    this.thinkingTokens = 0,
    this.responseTokens = 0,
  });

  /// Total tokens (prompt + completion)
  int get totalTokens => inputTokens + tokensUsed;

  /// Whether this result includes thinking content
  bool get hasThinkingContent =>
      thinkingContent != null && thinkingContent!.isNotEmpty;
}

class SpeakerDiarizationResult {}

// ============================================================================
// Module Discovery (iOS Parity)
// ============================================================================

/// Central registry for module auto-discovery.
///
/// Matches iOS ModuleDiscovery class for enabling auto-registration of modules.
///
/// ## Usage
///
/// Modules can register themselves for auto-discovery:
///
/// ```dart
/// // In your module's initialization:
/// ModuleDiscovery.register(MyModule());
///
/// // At app startup:
/// ModuleRegistry.shared.registerDiscoveredModules();
/// ```
class ModuleDiscovery {
  /// Private constructor - singleton pattern.
  ModuleDiscovery._();

  /// Discovered module instances.
  static final List<RunAnywhereModule> _discoveredModules = [];

  /// Get all discovered modules.
  static List<RunAnywhereModule> get discoveredModules =>
      List.unmodifiable(_discoveredModules);

  /// Register a module for auto-discovery.
  ///
  /// Call this from your module's initialization to enable auto-registration.
  ///
  /// ```dart
  /// // In your module file:
  /// class MyModule implements RunAnywhereModule {
  ///   static void autoRegister() {
  ///     ModuleDiscovery.register(MyModule());
  ///   }
  ///   // ... module implementation ...
  /// }
  /// ```
  ///
  /// [module] - The module instance to register for discovery.
  static void register(RunAnywhereModule module) {
    // Only add if not already registered
    if (!_discoveredModules.any((m) => m.moduleId == module.moduleId)) {
      _discoveredModules.add(module);
    }
  }

  /// Clear all discovered modules (for testing).
  static void reset() {
    _discoveredModules.clear();
  }
}
