/// Module Registry
///
/// Central registry for external AI module implementations.
/// Matches Swift ModuleRegistry from Core/Module/.
library module_registry;

import 'dart:async';

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/sdk_component.dart';

// Re-export types for consumers
export 'package:runanywhere/core/types/model_types.dart';
export 'package:runanywhere/core/types/sdk_component.dart';
export 'package:runanywhere/core/types/storage_types.dart';

/// Central registry for external AI module implementations.
///
/// This allows optional dependencies to register their implementations
/// at runtime, enabling a plugin-based architecture where modules like
/// LlamaCPP, ONNX, etc. can be added as needed.
///
/// ## Module Registration
///
/// Modules register themselves via their static `register()` method:
///
/// ```dart
/// LlamaCpp.register();
/// Onnx.register();
/// ```
class ModuleRegistry {
  /// Singleton instance
  static final ModuleRegistry shared = ModuleRegistry._();

  ModuleRegistry._();

  // Module-level tracking
  final Map<String, ModuleMetadata> _registeredModules = {};

  // Provider-level tracking
  final List<_PrioritizedProvider<STTServiceProvider>> _sttProviders = [];
  final List<_PrioritizedProvider<LLMServiceProvider>> _llmProviders = [];
  final List<_PrioritizedProvider<TTSServiceProvider>> _ttsProviders = [];
  final List<_PrioritizedProvider<VADServiceProvider>> _vadProviders = [];

  // ============================================================================
  // Provider Registration
  // ============================================================================

  /// Register a Speech-to-Text provider with optional priority
  void registerSTT(STTServiceProvider provider, {int priority = 100}) {
    final prioritizedProvider = _PrioritizedProvider(
      provider: provider,
      priority: priority,
    );
    _sttProviders.add(prioritizedProvider);
    _sttProviders.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Register a Language Model provider with optional priority
  void registerLLM(LLMServiceProvider provider, {int priority = 100}) {
    final prioritizedProvider = _PrioritizedProvider(
      provider: provider,
      priority: priority,
    );
    _llmProviders.add(prioritizedProvider);
    _llmProviders.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Register a Text-to-Speech provider with optional priority
  void registerTTS(TTSServiceProvider provider, {int priority = 100}) {
    final prioritizedProvider = _PrioritizedProvider(
      provider: provider,
      priority: priority,
    );
    _ttsProviders.add(prioritizedProvider);
    _ttsProviders.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Register a Voice Activity Detection provider with optional priority
  void registerVAD(VADServiceProvider provider, {int priority = 100}) {
    final prioritizedProvider = _PrioritizedProvider(
      provider: provider,
      priority: priority,
    );
    _vadProviders.add(prioritizedProvider);
    _vadProviders.sort((a, b) => b.priority.compareTo(a.priority));
  }

  // ============================================================================
  // Module Registration
  // ============================================================================

  /// Register module metadata.
  void registerModuleMetadata(ModuleMetadata metadata) {
    if (_registeredModules.containsKey(metadata.moduleId)) {
      return; // Already registered
    }
    _registeredModules[metadata.moduleId] = metadata;
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
  List<ModuleMetadata> modulesForCapability(SDKComponent capability) {
    return _registeredModules.values
        .where((m) => m.capabilities.contains(capability))
        .toList()
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  // ============================================================================
  // Provider Queries
  // ============================================================================

  /// Get an STT provider for the specified model
  STTServiceProvider? sttProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _sttProviders
            .firstWhere((p) => p.provider.canHandle(modelId: modelId))
            .provider;
      } catch (e) {
        return _sttProviders.isNotEmpty ? _sttProviders.first.provider : null;
      }
    }
    return _sttProviders.isNotEmpty ? _sttProviders.first.provider : null;
  }

  /// Get an LLM provider for the specified model
  LLMServiceProvider? llmProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _llmProviders
            .firstWhere((p) => p.provider.canHandle(modelId: modelId))
            .provider;
      } catch (e) {
        return _llmProviders.isNotEmpty ? _llmProviders.first.provider : null;
      }
    }
    return _llmProviders.isNotEmpty ? _llmProviders.first.provider : null;
  }

  /// Get a TTS provider for the specified model
  TTSServiceProvider? ttsProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _ttsProviders
            .firstWhere((p) => p.provider.canHandle(modelId: modelId))
            .provider;
      } catch (e) {
        return _ttsProviders.isNotEmpty ? _ttsProviders.first.provider : null;
      }
    }
    return _ttsProviders.isNotEmpty ? _ttsProviders.first.provider : null;
  }

  /// Get a VAD provider for the specified model
  VADServiceProvider? vadProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _vadProviders
            .firstWhere((p) => p.provider.canHandle(modelId: modelId))
            .provider;
      } catch (e) {
        return _vadProviders.isNotEmpty ? _vadProviders.first.provider : null;
      }
    }
    return _vadProviders.isNotEmpty ? _vadProviders.first.provider : null;
  }

  // ============================================================================
  // Availability Checks
  // ============================================================================

  bool get hasSTT => _sttProviders.isNotEmpty;
  bool get hasLLM => _llmProviders.isNotEmpty;
  bool get hasTTS => _ttsProviders.isNotEmpty;
  bool get hasVAD => _vadProviders.isNotEmpty;

  /// Get list of available capabilities
  List<String> get registeredCapabilities {
    final capabilities = <String>[];
    if (hasSTT) capabilities.add('STT');
    if (hasLLM) capabilities.add('LLM');
    if (hasTTS) capabilities.add('TTS');
    if (hasVAD) capabilities.add('VAD');
    return capabilities;
  }

  /// Reset all registrations (useful for testing)
  void reset() {
    _registeredModules.clear();
    _sttProviders.clear();
    _llmProviders.clear();
    _ttsProviders.clear();
    _vadProviders.clear();
  }
}

// ============================================================================
// Internal Types
// ============================================================================

/// Internal structure to track providers with their priorities
class _PrioritizedProvider<T> {
  final T provider;
  final int priority;

  _PrioritizedProvider({required this.provider, required this.priority});
}

// ============================================================================
// Module Metadata
// ============================================================================

/// Metadata about a registered module.
/// Matches Swift ModuleMetadata pattern.
class ModuleMetadata {
  final String moduleId;
  final String moduleName;
  final InferenceFramework inferenceFramework;
  final Set<SDKComponent> capabilities;
  final int priority;
  final DateTime registeredAt;

  const ModuleMetadata({
    required this.moduleId,
    required this.moduleName,
    required this.inferenceFramework,
    required this.capabilities,
    required this.priority,
    required this.registeredAt,
  });
}

// ============================================================================
// Service Provider Interfaces
// ============================================================================

/// Provider interface for Speech-to-Text services
abstract class STTServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<STTService> createSTTService(dynamic configuration);
}

/// Provider interface for Language Model services
abstract class LLMServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<LLMService> createLLMService(dynamic configuration);
}

/// Provider interface for Text-to-Speech services
abstract class TTSServiceProvider {
  String get name;
  String get version;
  bool canHandle({String? modelId});
  Future<TTSService> createTTSService(dynamic configuration);
}

/// Provider interface for Voice Activity Detection services
abstract class VADServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<VADService> createVADService(dynamic configuration);
}

// ============================================================================
// Service Interfaces
// ============================================================================

/// Interface for Speech-to-Text services
abstract class STTService {
  Future<void> initialize({String? modelPath});
  Future<STTTranscriptionResult> transcribe({
    required List<int> audioData,
    required STTOptions options,
  });
  bool get isReady;
  String? get currentModel;
  bool get supportsStreaming;
  String? get inferenceFramework;
  Future<void> cleanup();
}

/// Interface for Language Model services
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
  bool get supportsStreaming;
  Future<void> cancel();
  Future<void> cleanup();
}

/// Interface for Text-to-Speech services
abstract class TTSService {
  Future<void> initialize({String? modelPath});
  Future<TTSOutput> synthesize(TTSInput input);
  bool get isReady;
  Future<void> cleanup();
}

/// Interface for Voice Activity Detection services
abstract class VADService {
  Future<void> initialize({String? modelPath});
  Future<VADResult> process(List<int> audioData);
  bool get isReady;
  Future<void> cleanup();
}

// ============================================================================
// STT Types
// ============================================================================

/// Options for Speech-to-Text transcription
class STTOptions {
  final String language;
  final bool detectLanguage;
  final bool enablePunctuation;
  final bool enableDiarization;
  final int? maxSpeakers;
  final bool enableTimestamps;
  final int sampleRate;

  const STTOptions({
    this.language = 'en',
    this.detectLanguage = false,
    this.enablePunctuation = true,
    this.enableDiarization = false,
    this.maxSpeakers,
    this.enableTimestamps = true,
    this.sampleRate = 16000,
  });

  static const STTOptions defaultOptions = STTOptions();
}

/// Result of Speech-to-Text transcription
class STTTranscriptionResult {
  final String transcript;
  final double? confidence;
  final String? language;

  const STTTranscriptionResult({
    required this.transcript,
    this.confidence,
    this.language,
  });
}

// ============================================================================
// LLM Types
// ============================================================================

/// Options for LLM text generation
/// Matches Swift LLMGenerationOptions
class LLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  final double topP;
  final bool enableRealTimeTracking;
  final List<String> stopSequences;
  final bool streamingEnabled;
  final String? systemPrompt;
  final InferenceFramework? preferredFramework;

  const LLMGenerationOptions({
    this.maxTokens = 100,
    this.temperature = 0.7,
    this.topP = 1.0,
    this.enableRealTimeTracking = true,
    this.stopSequences = const [],
    this.streamingEnabled = false,
    this.systemPrompt,
    this.preferredFramework,
  });

  static const LLMGenerationOptions defaultOptions = LLMGenerationOptions();
}

/// Result of LLM text generation
/// Matches Swift LLMGenerationResult
class LLMGenerationResult {
  final String text;
  final String? thinkingContent;
  final int inputTokens;
  final int tokensUsed;
  final String modelUsed;
  final double latencyMs;
  final String? framework;
  final double tokensPerSecond;
  final double? timeToFirstTokenMs;
  final int thinkingTokens;
  final int responseTokens;

  const LLMGenerationResult({
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

  int get totalTokens => inputTokens + tokensUsed;
  bool get hasThinkingContent =>
      thinkingContent != null && thinkingContent!.isNotEmpty;
}

// ============================================================================
// TTS Types
// ============================================================================

/// Input for Text-to-Speech synthesis
class TTSInput {
  final String text;
  final String? voiceId;
  final double rate;
  final double pitch;

  const TTSInput({
    required this.text,
    this.voiceId,
    this.rate = 1.0,
    this.pitch = 1.0,
  });
}

/// Output from Text-to-Speech synthesis
class TTSOutput {
  final List<int> audioData;
  final String format;
  final int sampleRate;

  const TTSOutput({
    required this.audioData,
    this.format = 'pcm',
    this.sampleRate = 22050,
  });
}

// ============================================================================
// VAD Types
// ============================================================================

/// Result of Voice Activity Detection
class VADResult {
  final bool isSpeech;
  final double confidence;
  final double startTime;
  final double endTime;

  const VADResult({
    required this.isSpeech,
    required this.confidence,
    this.startTime = 0,
    this.endTime = 0,
  });
}
