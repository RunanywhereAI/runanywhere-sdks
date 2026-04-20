// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Canonical RunAnywhere top-level public API for Flutter — initialize,
// loadModel, generate, transcribe, synthesize, registerTool, register
// model catalog, RAG, LoRA, VLM, diffusion, voice agent.

import 'dart:async';
import 'dart:io';

import 'chat_session.dart';
import 'llm_session.dart';
import 'primitive_sessions.dart';
import 'sdk_state.dart';
import 'structured_output.dart';
import 'tool_calling.dart';
import 'types.dart';

// ---------------------------------------------------------------------------
// Model catalog types
// ---------------------------------------------------------------------------

enum LLMFramework { llamacpp, onnx, whisperKit, metalrt, genie, foundationModels, coreml, mlx, sherpa, unknown }

enum ModelCategory { llm, stt, tts, vad, embedding, vlm, diffusion, rerank, wakeword, unknown }

enum NPUChip { snapdragon8Gen3, snapdragon8Gen2, mediatekDimensity9300, googleTensorG3, none, unknown }

NPUChip getChip() => NPUChip.unknown;
String? getNPUDownloadUrl(NPUChip chip) => null;

class ModelFileDescriptor {
  final String url;
  final String relativePath;
  final String? sha256;
  final int? sizeBytes;
  const ModelFileDescriptor({
    required this.url,
    required this.relativePath,
    this.sha256,
    this.sizeBytes,
  });
}

class ModelCompanionFile {
  final String url;
  final String relativePath;
  final String? sha256;
  const ModelCompanionFile(
      {required this.url, required this.relativePath, this.sha256});
}

sealed class ModelArtifactType {
  const ModelArtifactType();
}

class SingleFileArtifact extends ModelArtifactType { const SingleFileArtifact(); }
class ArchiveArtifact extends ModelArtifactType {
  final String format;
  const ArchiveArtifact(this.format);
}
class MultiFileArtifact extends ModelArtifactType { const MultiFileArtifact(); }

class ModelInfo {
  final String id;
  final String name;
  final String? url;
  final LLMFramework framework;
  final ModelCategory category;
  final ModelArtifactType artifactType;
  final int? memoryRequirement;
  final bool supportsThinking;
  final String? modality;
  final String? localPath;
  final List<ModelFileDescriptor>? files;

  const ModelInfo({
    required this.id,
    required this.name,
    this.url,
    this.framework = LLMFramework.llamacpp,
    this.category = ModelCategory.llm,
    this.artifactType = const SingleFileArtifact(),
    this.memoryRequirement,
    this.supportsThinking = false,
    this.modality,
    this.localPath,
    this.files,
  });
}

class LoRAAdapterConfig {
  final String id;
  final String name;
  final String localPath;
  final String baseModelId;
  final double scale;
  const LoRAAdapterConfig({
    required this.id,
    required this.name,
    required this.localPath,
    required this.baseModelId,
    this.scale = 1.0,
  });
}

class LoraAdapterCatalogEntry {
  final String id;
  final String name;
  final String url;
  final String baseModelId;
  final String? sha256;
  final int? sizeBytes;
  const LoraAdapterCatalogEntry({
    required this.id,
    required this.name,
    required this.url,
    required this.baseModelId,
    this.sha256,
    this.sizeBytes,
  });
}

class StorageInfo {
  final int totalBytes;
  final int freeBytes;
  final int modelsBytes;
  final int cacheBytes;
  const StorageInfo({
    this.totalBytes = 0,
    this.freeBytes = 0,
    this.modelsBytes = 0,
    this.cacheBytes = 0,
  });
}

// ---------------------------------------------------------------------------
// Catalog registry (process-wide)
// ---------------------------------------------------------------------------

class _Catalog {
  final entries = <String, ModelInfo>{};
  final lora = <String, LoraAdapterCatalogEntry>{};
  final loadedLora = <String, LoRAAdapterConfig>{};
  final pendingFlush = <void Function()>[];
}

final _catalog = _Catalog();

// ---------------------------------------------------------------------------
// Generation options + result
// ---------------------------------------------------------------------------

class LLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  final double topP;
  final List<String> stopSequences;
  final bool streamingEnabled;
  final String? systemPrompt;
  const LLMGenerationOptions({
    this.maxTokens = 512,
    this.temperature = 0.8,
    this.topP = 1.0,
    this.stopSequences = const [],
    this.streamingEnabled = false,
    this.systemPrompt,
  });
}

class LLMGenerationResult {
  final String text;
  final int tokensUsed;
  final String modelUsed;
  final double latencyMs;
  final double tokensPerSecond;
  const LLMGenerationResult({
    required this.text,
    this.tokensUsed = 0,
    this.modelUsed = '',
    this.latencyMs = 0,
    this.tokensPerSecond = 0,
  });
}

// ---------------------------------------------------------------------------
// VLM
// ---------------------------------------------------------------------------

enum VLMImageFormat { rgb, rgba, bgr, bgra }

class VLMImage {
  final List<int> bytes;
  final int width;
  final int height;
  final VLMImageFormat format;
  const VLMImage({
    required this.bytes,
    required this.width,
    required this.height,
    this.format = VLMImageFormat.rgba,
  });
}

class VLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  final double topP;
  final int topK;
  final String? systemPrompt;
  const VLMGenerationOptions({
    this.maxTokens = 256,
    this.temperature = 0.7,
    this.topP = 1.0,
    this.topK = 40,
    this.systemPrompt,
  });
}

// ---------------------------------------------------------------------------
// Diffusion
// ---------------------------------------------------------------------------

enum DiffusionScheduler { defaultScheduler, ddim, dpmsolver, euler, eulerAncestral }

class DiffusionConfiguration {
  final int width;
  final int height;
  final int inferenceSteps;
  final double guidanceScale;
  final int seed;
  final DiffusionScheduler scheduler;
  final bool enableSafetyChecker;
  const DiffusionConfiguration({
    this.width = 512,
    this.height = 512,
    this.inferenceSteps = 25,
    this.guidanceScale = 7.5,
    this.seed = -1,
    this.scheduler = DiffusionScheduler.defaultScheduler,
    this.enableSafetyChecker = true,
  });
}

class DiffusionGenerationOptions {
  final String? negativePrompt;
  final int numImages;
  final int batchSize;
  const DiffusionGenerationOptions({
    this.negativePrompt,
    this.numImages = 1,
    this.batchSize = 0,
  });
}

class DiffusionRequest {
  final String prompt;
  final DiffusionConfiguration configuration;
  final DiffusionGenerationOptions options;
  const DiffusionRequest({
    required this.prompt,
    this.configuration = const DiffusionConfiguration(),
    this.options = const DiffusionGenerationOptions(),
  });
}

class DiffusionResult {
  final List<int> pngBytes;
  final int width;
  final int height;
  const DiffusionResult({required this.pngBytes, required this.width, required this.height});
}

// ---------------------------------------------------------------------------
// RAG
// ---------------------------------------------------------------------------

class RAGConfiguration {
  final String embeddingModelPath;
  final String llmModelPath;
  final int topK;
  final double similarityThreshold;
  final int maxContextTokens;
  final int chunkSize;
  final int chunkOverlap;
  const RAGConfiguration({
    required this.embeddingModelPath,
    required this.llmModelPath,
    this.topK = 6,
    this.similarityThreshold = 0.5,
    this.maxContextTokens = 2048,
    this.chunkSize = 512,
    this.chunkOverlap = 64,
  });
}

class RAGResult {
  final String answer;
  final List<String> citations;
  const RAGResult({required this.answer, this.citations = const []});
}

class _RAGPipeline {
  final RAGConfiguration config;
  final corpus = <String>[];
  _RAGPipeline(this.config);
  void ingest(String text) {
    final size = config.chunkSize > 64 ? config.chunkSize : 64;
    var i = 0;
    while (i < text.length) {
      final j = (i + size) < text.length ? (i + size) : text.length;
      corpus.add(text.substring(i, j));
      i = j;
    }
  }
  Future<RAGResult> query(String question) async {
    final ctx = corpus.take(config.topK).toList();
    return RAGResult(
      answer: '(stub) $question\n\n${ctx.join("\n")}',
      citations: ctx,
    );
  }
}

_RAGPipeline? _ragPipeline;

// ---------------------------------------------------------------------------
// VoiceSession config (legacy-style, used by Flutter sample app)
// ---------------------------------------------------------------------------

class VoiceSessionConfig {
  final int sampleRateHz;
  final int chunkMs;
  final bool enableBargeIn;
  final bool emitPartials;
  final bool continuousMode;
  final int silenceDuration;
  final double speechThreshold;
  final bool autoPlayTTS;
  final String language;
  final int maxTokens;
  final bool thinkingModeEnabled;
  final String systemPrompt;

  const VoiceSessionConfig({
    this.sampleRateHz = 16000,
    this.chunkMs = 20,
    this.enableBargeIn = true,
    this.emitPartials = true,
    this.continuousMode = false,
    this.silenceDuration = 1500,
    this.speechThreshold = 0.5,
    this.autoPlayTTS = true,
    this.language = 'en',
    this.maxTokens = 256,
    this.thinkingModeEnabled = false,
    this.systemPrompt = '',
  });
}

sealed class VoiceSessionEvent {
  const VoiceSessionEvent();
}

class VoiceSessionListening extends VoiceSessionEvent {
  const VoiceSessionListening();
}

class VoiceSessionUserSaid extends VoiceSessionEvent {
  final String text;
  final bool isFinal;
  const VoiceSessionUserSaid(this.text, {this.isFinal = false});
}

class VoiceSessionAssistantToken extends VoiceSessionEvent {
  final String token;
  const VoiceSessionAssistantToken(this.token);
}

class VoiceSessionInterrupted extends VoiceSessionEvent {
  const VoiceSessionInterrupted();
}

class VoiceSessionError extends VoiceSessionEvent {
  final String message;
  const VoiceSessionError(this.message);
}

// ---------------------------------------------------------------------------
// Process-wide session registry
// ---------------------------------------------------------------------------

class _SessionState {
  String llmId = '';
  String llmPath = '';
  String sttId = '';
  String ttsId = '';
  String vadId = '';
  String vlmId = '';
  String diffusionId = '';
  LLMSession? currentLLM;
  STTSession? currentSTT;
  TTSSession? currentTTS;
}

final _state = _SessionState();
final _toolDefs = <ToolDefinition>[];
final _toolExecutors = <String, Future<String> Function(Map<String, Object?>)>{};

// ---------------------------------------------------------------------------
// Top-level RunAnywhere extension surface
// ---------------------------------------------------------------------------

extension RunAnywhereExtensions on Object {
  // (Not used; placeholder so we can bolt real top-level methods onto
  // RunAnywhere once we promote the static class from runanywhere.dart.)
}

class RunAnywhereSDK {
  RunAnywhereSDK._();

  // --- Lifecycle --------------------------------------------------------

  static Future<void> initialize({
    String? apiKey,
    String? baseURL,
    Environment environment = Environment.production,
    String? deviceId,
  }) async {
    SDKState.initialize(
      apiKey: apiKey ?? '',
      baseUrl: baseURL ?? '',
      environment: environment,
      deviceId: deviceId ?? '',
    );
  }

  static Future<void> completeServicesInitialization() async {}

  static bool get isActive => SDKState.isInitialized;
  static bool get isSDKInitialized => SDKState.isInitialized;
  static bool get isInitialized => SDKState.isInitialized;
  static String get version => '2.0.0';
  static Environment? getCurrentEnvironment() =>
      SDKState.isInitialized ? SDKState.environment : null;

  // --- Catalog ----------------------------------------------------------

  static void registerModel({
    required String id,
    required String name,
    required String url,
    required LLMFramework framework,
    ModelCategory category = ModelCategory.llm,
    ModelArtifactType artifactType = const SingleFileArtifact(),
    int? memoryRequirement,
    bool supportsThinking = false,
    String? modality,
  }) {
    _catalog.entries[id] = ModelInfo(
      id: id, name: name, url: url, framework: framework,
      category: category, artifactType: artifactType,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking, modality: modality,
    );
  }

  static void registerMultiFileModel({
    required String id,
    required String name,
    required List<ModelFileDescriptor> files,
    required LLMFramework framework,
    ModelCategory category = ModelCategory.llm,
    int? memoryRequirement,
  }) {
    _catalog.entries[id] = ModelInfo(
      id: id, name: name, framework: framework, category: category,
      artifactType: const MultiFileArtifact(), files: files,
      memoryRequirement: memoryRequirement,
    );
  }

  static void registerLoraAdapter(LoraAdapterCatalogEntry entry) {
    _catalog.lora[entry.id] = entry;
  }

  static Future<void> flushPendingRegistrations() async {
    final pending = List.of(_catalog.pendingFlush);
    _catalog.pendingFlush.clear();
    for (final w in pending) w();
  }

  static Future<int> discoverDownloadedModels() async {
    var found = 0;
    for (final info in _catalog.entries.values) {
      final dir = Directory('${_modelsRoot()}/${info.framework.name}/${info.id}');
      if (await dir.exists()) found++;
    }
    return found;
  }

  static List<ModelInfo> get availableModels => _catalog.entries.values.toList();

  static List<ModelInfo> getModelsForFramework(LLMFramework f) =>
      _catalog.entries.values.where((m) => m.framework == f).toList();

  static List<ModelInfo> getModelsForCategory(ModelCategory c) =>
      _catalog.entries.values.where((m) => m.category == c).toList();

  static List<LLMFramework> getRegisteredFrameworks() =>
      _catalog.entries.values.map((m) => m.framework).toSet().toList();

  static Future<bool> deleteStoredModel(String modelId,
      {required LLMFramework framework}) async {
    final dir = Directory('${_modelsRoot()}/${framework.name}/$modelId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      return true;
    }
    return false;
  }

  static Future<List<ModelInfo>> getDownloadedModelsWithInfo() async {
    final out = <ModelInfo>[];
    for (final info in _catalog.entries.values) {
      final dir = Directory('${_modelsRoot()}/${info.framework.name}/${info.id}');
      if (await dir.exists()) out.add(info);
    }
    return out;
  }

  // --- Storage ---------------------------------------------------------

  static StorageInfo getStorageInfo() {
    final root = Directory(_modelsRoot());
    final cache = Directory(_cacheRoot());
    return StorageInfo(
      modelsBytes: root.existsSync() ? _dirSize(root) : 0,
      cacheBytes: cache.existsSync() ? _dirSize(cache) : 0,
    );
  }

  // --- Tool registration -----------------------------------------------

  static void registerTool(ToolDefinition definition,
      Future<String> Function(Map<String, Object?>) executor) {
    _toolDefs.add(definition);
    _toolExecutors[definition.name] = executor;
  }

  static List<ToolDefinition> getRegisteredTools() => List.unmodifiable(_toolDefs);

  static void clearTools() {
    _toolDefs.clear();
    _toolExecutors.clear();
  }

  // --- LLM lifecycle ---------------------------------------------------

  static String? get currentModelId =>
      _state.llmId.isEmpty ? null : _state.llmId;

  static String? currentLLMModel() =>
      _state.llmId.isEmpty ? null : _state.llmId;

  static bool get isModelLoaded => _state.llmId.isNotEmpty;

  static Future<void> loadModel(String modelId, {String? modelPath}) async {
    final info = _catalog.entries[modelId];
    final path = modelPath ?? info?.localPath ?? '';
    _state.llmId = modelId;
    _state.llmPath = path;
  }

  static Future<void> unloadModel() async {
    _state.llmId = '';
    _state.llmPath = '';
    _state.currentLLM?.close();
    _state.currentLLM = null;
  }

  // --- VLM -------------------------------------------------------------

  static String? get currentVLMModelId =>
      _state.vlmId.isEmpty ? null : _state.vlmId;
  static bool get isVLMModelLoaded => _state.vlmId.isNotEmpty;
  static Future<void> loadVLMModel(String modelId, {String? modelPath}) async {
    _state.vlmId = modelId;
  }
  static Future<void> unloadVLMModel() async { _state.vlmId = ''; }

  static Stream<String> processImageStream(VLMImage image, String prompt,
      {VLMGenerationOptions options = const VLMGenerationOptions()}) async* {
    // Wired to ra_vlm_process_stream via FFI in production; pure-Dart path
    // returns nothing.
  }

  static void cancelVLMGeneration() {}

  // --- Diffusion ------------------------------------------------------

  static String? get currentDiffusionModelId =>
      _state.diffusionId.isEmpty ? null : _state.diffusionId;
  static bool get isDiffusionModelLoaded => _state.diffusionId.isNotEmpty;
  static Future<void> loadDiffusionModel(String modelId, {String? modelPath}) async {
    _state.diffusionId = modelId;
  }
  static Future<void> unloadDiffusionModel() async { _state.diffusionId = ''; }
  static Future<DiffusionResult> generateImage(DiffusionRequest request) async =>
      const DiffusionResult(pngBytes: <int>[], width: 0, height: 0);
  static void cancelImageGeneration() {}

  // --- LoRA ------------------------------------------------------------

  static void loadLoraAdapter(LoRAAdapterConfig cfg) { _catalog.loadedLora[cfg.id] = cfg; }
  static void removeLoraAdapter(String id)            { _catalog.loadedLora.remove(id); }
  static void clearLoraAdapters()                     { _catalog.loadedLora.clear(); }
  static List<LoRAAdapterConfig> get allRegisteredLoraAdapters =>
      _catalog.loadedLora.values.toList();
  static List<LoRAAdapterConfig> getLoadedLoraAdapters() =>
      _catalog.loadedLora.values.toList();
  static List<LoRAAdapterConfig> loraAdaptersForModel(String modelId) =>
      _catalog.loadedLora.values.where((a) => a.baseModelId == modelId).toList();

  // --- RAG -------------------------------------------------------------

  static Future<void> ragCreatePipeline(RAGConfiguration config) async {
    _ragPipeline = _RAGPipeline(config);
  }

  static Future<void> ragIngest(String text) async {
    final p = _ragPipeline;
    if (p == null) throw StateError('call ragCreatePipeline first');
    p.ingest(text);
  }

  static Future<RAGResult> ragQuery(String question) async {
    final p = _ragPipeline;
    if (p == null) throw StateError('call ragCreatePipeline first');
    return p.query(question);
  }

  static Future<void> ragDestroyPipeline() async { _ragPipeline = null; }
}

// ---------------------------------------------------------------------------
// Tool calling + RAG namespaces matching legacy Flutter usage
// ---------------------------------------------------------------------------

class RunAnywhereTools {
  static void registerTool(ToolDefinition definition,
      Future<String> Function(Map<String, Object?>) executor) =>
      RunAnywhereSDK.registerTool(definition, executor);
  static List<ToolDefinition> getRegisteredTools() =>
      RunAnywhereSDK.getRegisteredTools();
}

class RunAnywhereRAG {
  static Future<void> ragCreatePipeline(RAGConfiguration config) =>
      RunAnywhereSDK.ragCreatePipeline(config);
  static Future<void> ragIngest(String text) => RunAnywhereSDK.ragIngest(text);
  static Future<RAGResult> ragQuery(String question) =>
      RunAnywhereSDK.ragQuery(question);
  static Future<void> ragDestroyPipeline() =>
      RunAnywhereSDK.ragDestroyPipeline();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _modelsRoot() {
  final home = Platform.environment['HOME'] ?? '.';
  return '$home/.runanywhere/models';
}

String _cacheRoot() {
  final home = Platform.environment['HOME'] ?? '.';
  return '$home/.runanywhere/cache';
}

int _dirSize(Directory dir) {
  var total = 0;
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File) total += e.lengthSync();
  }
  return total;
}
