import 'dart:async';

/// Central registry for external AI module implementations
///
/// This allows optional dependencies to register their implementations
/// at runtime, enabling a plugin-based architecture where modules like
/// WhisperKit, llama.cpp, and FluidAudioDiarization can be added as needed.
class ModuleRegistry {
  /// Singleton instance
  static final ModuleRegistry shared = ModuleRegistry._();

  ModuleRegistry._();

  final List<_PrioritizedProvider<STTServiceProvider>> _sttProviders = [];
  final List<_PrioritizedProvider<LLMServiceProvider>> _llmProviders = [];
  final List<_PrioritizedProvider<TTSServiceProvider>> _ttsProviders = [];
  final List<_PrioritizedProvider<VADServiceProvider>> _vadProviders = [];
  final List<SpeakerDiarizationServiceProvider> _speakerDiarizationProviders = [];
  final List<VLMServiceProvider> _vlmProviders = [];
  final List<WakeWordServiceProvider> _wakeWordProviders = [];

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

  /// Register a Vision Language Model provider
  void registerVLM(VLMServiceProvider provider) {
    _vlmProviders.add(provider);
  }

  /// Register a Wake Word Detection provider
  void registerWakeWord(WakeWordServiceProvider provider) {
    _wakeWordProviders.add(provider);
  }

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
  SpeakerDiarizationServiceProvider? speakerDiarizationProvider({String? modelId}) {
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

  /// Get a VLM provider for the specified model
  VLMServiceProvider? vlmProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _vlmProviders.firstWhere(
          (p) => p.canHandle(modelId: modelId),
        );
      } catch (e) {
        return _vlmProviders.isNotEmpty ? _vlmProviders.first : null;
      }
    }
    return _vlmProviders.isNotEmpty ? _vlmProviders.first : null;
  }

  /// Get a Wake Word provider
  WakeWordServiceProvider? wakeWordProvider({String? modelId}) {
    if (modelId != null) {
      try {
        return _wakeWordProviders.firstWhere(
          (p) => p.canHandle(modelId: modelId),
        );
      } catch (e) {
        return _wakeWordProviders.isNotEmpty ? _wakeWordProviders.first : null;
      }
    }
    return _wakeWordProviders.isNotEmpty ? _wakeWordProviders.first : null;
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

  /// Check if VLM is available
  bool get hasVLM => _vlmProviders.isNotEmpty;

  /// Check if Wake Word Detection is available
  bool get hasWakeWord => _wakeWordProviders.isNotEmpty;

  /// Get list of all registered modules
  List<String> get registeredModules {
    final modules = <String>[];
    if (hasSTT) modules.add('STT');
    if (hasLLM) modules.add('LLM');
    if (hasTTS) modules.add('TTS');
    if (hasVAD) modules.add('VAD');
    if (hasSpeakerDiarization) modules.add('SpeakerDiarization');
    if (hasVLM) modules.add('VLM');
    if (hasWakeWord) modules.add('WakeWord');
    return modules;
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
/// Note: Returns dynamic to avoid circular dependency with components/tts/tts_service.dart
/// Actual return type should be TTSService from components/tts/tts_service.dart
abstract class TTSServiceProvider {
  String get name;
  String get version;
  bool canHandle({String? modelId});
  Future<dynamic> createTTSService(dynamic configuration);
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

abstract class VLMServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<VLMService> createVLMService(dynamic configuration);
}

abstract class WakeWordServiceProvider {
  String get name;
  bool canHandle({String? modelId});
  Future<WakeWordService> createWakeWordService(dynamic configuration);
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
  Future<void> cleanup();
}

/// Protocol for text-to-speech services
abstract class TTSService {
  Future<void> initialize();
  Future<List<int>> synthesize({
    required String text,
    required TTSOptions options,
  });
  Future<void> synthesizeStream({
    required String text,
    required TTSOptions options,
    required void Function(List<int>) onChunk,
  });
  void stop();
  bool get isSynthesizing;
  List<String> get availableVoices;
  Future<void> cleanup();
}

/// Protocol for voice activity detection services
abstract class VADService {
  Future<void> initialize({String? modelPath});
  Future<VADResult> detect({required List<int> audioData});
  bool get isReady;
  Future<void> cleanup();
}

abstract class SpeakerDiarizationService {
  Future<void> initialize({String? modelPath});
  Future<SpeakerDiarizationResult> process(List<int> audioData);
  bool get isReady;
  Future<void> cleanup();
}

abstract class VLMService {
  Future<void> initialize({String? modelPath});
  Future<VLMResult> process({
    required String prompt,
    required List<int> imageData,
  });
  bool get isReady;
  Future<void> cleanup();
}

abstract class WakeWordService {
  Future<void> initialize({String? modelPath});
  Future<bool> detect(List<int> audioData);
  bool get isReady;
  Future<void> cleanup();
}

// Placeholder types (to be properly defined later)
class STTOptions {
  final String language;
  final bool detectLanguage;
  final bool enablePunctuation;
  final bool enableDiarization;
  final int? maxSpeakers;
  final bool enableTimestamps;
  final List<String> vocabularyFilter;
  final int sampleRate;

  STTOptions({
    this.language = 'en',
    this.detectLanguage = false,
    this.enablePunctuation = true,
    this.enableDiarization = false,
    this.maxSpeakers,
    this.enableTimestamps = true,
    this.vocabularyFilter = const [],
    this.sampleRate = 16000,
  });
}

class STTTranscriptionResult {
  final String transcript;
  final double? confidence;
  final List<TimestampInfo>? timestamps;
  final String? language;
  final List<AlternativeTranscription>? alternatives;

  STTTranscriptionResult({
    required this.transcript,
    this.confidence,
    this.timestamps,
    this.language,
    this.alternatives,
  });
}

class TimestampInfo {
  final String word;
  final double startTime;
  final double endTime;
  final double? confidence;

  TimestampInfo({
    required this.word,
    required this.startTime,
    required this.endTime,
    this.confidence,
  });
}

class AlternativeTranscription {
  final String transcript;
  final double confidence;

  AlternativeTranscription({
    required this.transcript,
    required this.confidence,
  });
}

class LLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  LLMGenerationOptions({required this.maxTokens, required this.temperature});
}

class LLMGenerationResult {
  final String text;
  LLMGenerationResult({required this.text});
}

/// Options for text-to-speech synthesis
class TTSOptions {
  final String? voice;
  final String language;
  final double rate;
  final double pitch;
  final double volume;
  final int sampleRate;
  final bool useSSML;

  TTSOptions({
    this.voice,
    this.language = 'en-US',
    this.rate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.sampleRate = 16000,
    this.useSSML = false,
  });
}

class VADResult {
  final bool hasSpeech;
  final double confidence;
  VADResult({required this.hasSpeech, required this.confidence});
}

class SpeakerDiarizationResult {}
class VLMResult {}
