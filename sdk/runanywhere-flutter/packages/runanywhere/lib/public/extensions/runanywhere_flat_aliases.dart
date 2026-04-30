// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_flat_aliases.dart — Round 2 canonical flat alias extension.
//
// Adds every missing flat method / getter to [RunAnywhereSDK] that the
// canonical spec (§3–§13) requires but that was only accessible under the
// namespaced sub-objects (`instance.llm.*`, `instance.rag.*`, etc.).
//
// All methods in this file are thin delegates — no business logic lives
// here. The sub-object implementations remain the canonical ones.

import 'dart:typed_data';

import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/generated/diffusion_options.pb.dart'
    show
        DiffusionConfiguration,
        DiffusionGenerationOptions,
        DiffusionResult,
        DiffusionCapabilities,
        DiffusionProgress;
import 'package:runanywhere/generated/download_service.pb.dart'
    show DownloadProgress;
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions;
import 'package:runanywhere/generated/rag.pb.dart'
    show RAGConfiguration, RAGQueryOptions, RAGResult, RAGStatistics;
import 'package:runanywhere/generated/stt_options.pb.dart' show STTOutput;
import 'package:runanywhere/generated/structured_output.pb.dart'
    show StructuredOutputResult, JSONSchema;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show ToolCallingOptions, ToolCallingResult, ToolResult;
import 'package:runanywhere/generated/vad_options.pb.dart'
    show VADResult, VADStatistics;
import 'package:runanywhere/generated/tts_options.pb.dart' show TTSOutput;
import 'package:runanywhere/generated/vlm_options.pb.dart' show VLMImage;
import 'package:runanywhere/generated/voice_events.pb.dart' as voice_proto
    show VoiceAgentComponentStates;
import 'package:runanywhere/generated/voice_events.pbenum.dart'
    show ComponentLoadState;
import 'package:runanywhere/public/capabilities/runanywhere_diffusion.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/capabilities/runanywhere_rag.dart';
import 'package:runanywhere/public/capabilities/runanywhere_stt.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tools.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tts.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vad.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vlm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_voice.dart';
import 'package:runanywhere/public/extensions/runanywhere_frameworks.dart';
import 'package:runanywhere/public/extensions/runanywhere_structured_output.dart';
import 'package:runanywhere/public/extensions/runanywhere_thinking_utils.dart';
import 'package:runanywhere/public/runanywhere_v4.dart';

/// Canonical flat aliases extension on [RunAnywhereSDK].
///
/// Every method here is a single-line delegate to the appropriate
/// namespaced sub-object. Callers using portable cross-SDK code should
/// prefer these flat names; Flutter-first callers may use either form.
extension RunAnywhereSDKFlatAliases on RunAnywhereSDK {
  // =========================================================================
  // §3 LLM — flat aliases
  // =========================================================================

  /// Flat alias — generate text with tool calling support.
  /// Delegates to `instance.tools.generateWithTools(prompt, options)`.
  Future<ToolCallingResult> generateWithTools(
    String prompt, {
    ToolCallingOptions? options,
  }) =>
      RunAnywhereTools.shared.generateWithTools(prompt, options: options);

  /// Flat alias — continue generation after manual tool execution.
  /// Delegates to `instance.tools.continueWithToolResult(...)`.
  ///
  /// Canonical signature: `continueWithToolResult(toolCallId, result)`.
  /// The Flutter tools implementation accepts `(originalPrompt, ToolResult)`
  /// internally; here we expose the canonical two-string form and bridge it.
  Future<ToolCallingResult> continueWithToolResult(
    String toolCallId,
    String result,
  ) {
    final toolResult = ToolResult(
      toolCallId: toolCallId,
      name: toolCallId,
      resultJson: result,
    );
    return RunAnywhereTools.shared
        .continueWithToolResult(toolCallId, toolResult);
  }

  /// Flat alias — generate text constrained by a JSON schema.
  /// Delegates to [RunAnywhereStructuredOutput.generate].
  Future<StructuredOutputResult> generateStructured(
    String prompt,
    JSONSchema schema, [
    LLMGenerationOptions? options,
  ]) =>
      RunAnywhereStructuredOutput.generate(
        prompt,
        jsonSchema: schema.toProto3Json().toString(),
        maxTokens: options != null && options.hasMaxTokens()
            ? options.maxTokens
            : 512,
        temperature: options != null && options.hasTemperature()
            ? options.temperature
            : 0.0,
      );

  /// Flat alias — streaming structured output.
  /// Emits the final [StructuredOutputResult] as a single-event stream
  /// (the underlying generate call is blocking; streaming per-token
  /// structured output is CPP-blocked until a proto streaming path lands).
  Stream<StructuredOutputResult> generateStructuredStream(
    String prompt,
    JSONSchema schema, [
    LLMGenerationOptions? options,
  ]) async* {
    final result = await generateStructured(prompt, schema, options);
    yield result;
  }

  /// Flat alias — extract structured output from raw text against a schema.
  /// Pure Dart implementation: parses JSON from the text and validates it.
  Future<StructuredOutputResult> extractStructuredOutput(
    String text,
    JSONSchema schema,
  ) =>
      RunAnywhereThinkingUtils.extractStructuredOutput(text, schema);

  /// Flat alias — extract `<think>…</think>` thinking tokens from text.
  /// Pure Dart implementation.
  ThinkingExtractionResult extractThinkingTokens(String text) =>
      RunAnywhereThinkingUtils.extractThinkingTokens(text);

  /// Flat alias — strip thinking tokens from text, returning only the
  /// visible response. Pure Dart implementation.
  String stripThinkingTokens(String text) =>
      RunAnywhereThinkingUtils.stripThinkingTokens(text);

  /// Flat alias — split text into its thinking portion and response portion.
  /// Returns a record `(thinking: String, response: String)`.
  /// Pure Dart implementation.
  ({String thinking, String response}) splitThinkingAndResponse(String text) =>
      RunAnywhereThinkingUtils.splitThinkingAndResponse(text);

  // =========================================================================
  // §4 STT — flat aliases
  // =========================================================================

  /// Flat alias — stop any active streaming transcription session.
  Future<void> stopStreamingTranscription() =>
      RunAnywhereSTT.shared.stopStreamingTranscription();

  /// True when a streaming STT session is active.
  bool get isStreamingSTT => RunAnywhereSTT.shared.isStreaming;

  // =========================================================================
  // §6 VAD — flat aliases
  // =========================================================================

  /// Flat alias — stream VAD results from an audio byte stream.
  Stream<VADResult> streamVAD(Stream<Uint8List> audio) =>
      RunAnywhereVAD.shared.streamVAD(audio);

  /// Flat alias — register a VAD statistics callback.
  void setVADStatisticsCallback(
    void Function(VADStatistics stats)? callback,
  ) =>
      RunAnywhereVAD.shared.setStatisticsCallback(callback);

  // =========================================================================
  // §7 VLM — flat aliases
  // =========================================================================

  /// Flat alias — describe an image. Canonical name for `vlm.describe()`.
  Future<String> describeImage(
    VLMImage image, {
    String? prompt,
  }) =>
      RunAnywhereVLM.shared.describe(
        image,
        prompt: prompt ?? "What's in this image?",
      );

  /// Flat alias — ask a question about an image.
  Future<String> askAboutImage(String question, VLMImage image) =>
      RunAnywhereVLM.shared.askAbout(question, image: image);

  /// Flat alias — cancel any in-flight VLM generation.
  Future<void> cancelVLMGeneration() => RunAnywhereVLM.shared.cancel();

  /// True when a VLM model is currently loaded.
  bool get isVLMModelLoaded => RunAnywhereVLM.shared.isLoaded;

  // =========================================================================
  // §8 Diffusion — flat aliases
  // =========================================================================

  /// Flat alias — generate an image from a text prompt.
  Future<DiffusionResult> generateImage(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) =>
      RunAnywhereDiffusion.shared.generate(prompt, options);

  /// Flat alias — stream image generation progress.
  Stream<DiffusionProgress> generateImageStream(
    String prompt, [
    DiffusionGenerationOptions? options,
  ]) =>
      RunAnywhereDiffusion.shared.generateStream(prompt, options);

  /// Flat alias — load a diffusion model.
  Future<void> loadDiffusionModel(
    String modelId, [
    DiffusionConfiguration? config,
  ]) =>
      RunAnywhereDiffusion.shared.load(modelId, config);

  /// Flat alias — unload the active diffusion model.
  Future<void> unloadDiffusionModel() => RunAnywhereDiffusion.shared.unload();

  /// True when a diffusion model is currently loaded.
  bool get isDiffusionModelLoaded => RunAnywhereDiffusion.shared.isLoaded;

  /// Flat alias — cancel any in-flight image generation.
  Future<void> cancelImageGeneration() => RunAnywhereDiffusion.shared.cancel();

  /// Flat alias — get diffusion backend capabilities.
  DiffusionCapabilities getDiffusionCapabilities() =>
      RunAnywhereDiffusion.shared.capabilities();

  // =========================================================================
  // §9 RAG — flat aliases with canonical `rag`-prefixed names
  // =========================================================================

  /// Flat alias — create the RAG pipeline.
  Future<void> ragCreatePipeline(RAGConfiguration config) =>
      RunAnywhereRAG.shared.createPipeline(config);

  /// Flat alias — destroy the RAG pipeline.
  Future<void> ragDestroyPipeline() => RunAnywhereRAG.shared.destroyPipeline();

  /// Flat alias — ingest a document into the RAG pipeline.
  Future<void> ragIngest(String text, {String? metadataJSON}) =>
      RunAnywhereRAG.shared.ingest(text, metadataJSON: metadataJSON);

  /// Flat alias — ingest multiple documents in batch.
  Future<void> ragAddDocumentsBatch(List<Map<String, String>> documents) =>
      RunAnywhereRAG.shared.addDocumentsBatch(documents);

  /// Flat alias — query the RAG pipeline.
  Future<RAGResult> ragQuery(
    String query, {
    RAGQueryOptions? options,
  }) =>
      RunAnywhereRAG.shared.query(query, options: options);

  /// Flat alias — clear all documents from the RAG pipeline.
  Future<void> ragClearDocuments() => RunAnywhereRAG.shared.clearDocuments();

  /// Flat alias — get the count of indexed document chunks.
  Future<int> ragGetDocumentCount() => RunAnywhereRAG.shared.documentCount();

  /// Flat alias — get RAG pipeline statistics.
  Future<RAGStatistics> ragGetStatistics() =>
      RunAnywhereRAG.shared.getStatistics();

  /// Flat alias — initialize the RAG pipeline (convenience wrapper for
  /// `ragCreatePipeline` with an optional config).
  Future<void> ragInitialize([RAGConfiguration? config]) =>
      RunAnywhereRAG.shared.createPipeline(config ?? RAGConfiguration());

  /// Flat alias — generate a response augmented by RAG retrieval.
  /// Queries the RAG pipeline and returns the answer string.
  Future<String> ragGenerateWithRAG(
    String prompt, {
    RAGQueryOptions? options,
  }) async {
    final result = await RunAnywhereRAG.shared.query(prompt, options: options);
    return result.answer;
  }

  // =========================================================================
  // §10 Voice Agent — flat aliases
  // =========================================================================

  /// Flat alias — initialize the voice agent from a configuration.
  Future<void> voiceAgentStart() =>
      RunAnywhereVoice.shared.initializeWithLoadedModels();

  /// Flat alias — cleanup voice agent native resources.
  void voiceAgentStop() => RunAnywhereVoice.shared.cleanup();

  /// Flat alias — transcribe audio via the voice agent.
  /// Returns a [STTOutput] wrapping the transcription.
  Future<STTOutput> voiceAgentTranscribe(Uint8List audio) async {
    final text = await RunAnywhereVoice.shared.transcribe(audio);
    return STTOutput(text: text);
  }

  /// Flat alias — synthesize speech via the voice agent.
  /// Returns a [TTSOutput] wrapping the raw audio bytes.
  Future<TTSOutput> voiceAgentSynthesizeSpeech(String text) async {
    final samples = await RunAnywhereVoice.shared.synthesizeSpeech(text);
    return TTSOutput(audioData: samples.buffer.asUint8List());
  }

  /// Flat alias — generate an LLM response via the voice agent pipeline.
  /// Delegates to `RunAnywhereVoice.shared.generateResponse(text)`.
  Future<String> voiceAgentGenerateResponse(String text) =>
      RunAnywhereVoice.shared.generateResponse(text);

  /// Flat alias — set the STT model used by the voice agent.
  Future<void> voiceAgentSetSTTModel(String modelId) =>
      RunAnywhereSTT.shared.load(modelId);

  /// Flat alias — set the LLM model used by the voice agent.
  Future<void> voiceAgentSetLLMModel(String modelId) =>
      RunAnywhereLLM.shared.load(modelId);

  /// Flat alias — set the TTS voice used by the voice agent.
  Future<void> voiceAgentSetTTSVoice(String voiceId) =>
      RunAnywhereTTS.shared.loadVoice(voiceId);

  /// Flat alias — initialize the voice agent with an explicit configuration.
  Future<void> initializeVoiceAgent(VoiceAgentConfiguration config) =>
      RunAnywhereVoice.shared.initializeVoiceAgent(config);

  /// Flat alias — initialize the voice agent against currently-loaded models.
  Future<void> initializeVoiceAgentWithLoadedModels() =>
      RunAnywhereVoice.shared.initializeWithLoadedModels();

  /// Flat alias — cleanup voice agent native resources.
  Future<void> cleanupVoiceAgent() async =>
      RunAnywhereVoice.shared.cleanup();

  /// Flat alias — get voice agent component readiness states.
  /// Returns the proto [voice_proto.VoiceAgentComponentStates] type.
  voice_proto.VoiceAgentComponentStates getVoiceAgentComponentStates() {
    final states = RunAnywhereVoice.shared.componentStates();
    ComponentLoadState _toLoadState(bool loaded) => loaded
        ? ComponentLoadState.COMPONENT_LOAD_STATE_LOADED
        : ComponentLoadState.COMPONENT_LOAD_STATE_NOT_LOADED;

    return voice_proto.VoiceAgentComponentStates(
      sttState: _toLoadState(states.sttLoaded),
      llmState: _toLoadState(states.llmLoaded),
      ttsState: _toLoadState(states.ttsLoaded),
      ready: states.isFullyReady,
    );
  }

  // =========================================================================
  // §13 Model Manager — flat aliases
  // =========================================================================

  /// Flat alias — list all available models.
  Future<List<ModelInfo>> availableModels() =>
      RunAnywhereModels.shared.available();

  /// Flat alias — generic model load. Routes to the LLM bridge by default;
  /// capability-specific loaders (`loadLLMModel`, `loadSTTModel`, etc.) are
  /// preferred when the caller knows the model type.
  Future<void> loadModel(String modelId) =>
      RunAnywhereLLM.shared.load(modelId);

  /// Flat alias — download a model and stream progress events.
  Stream<DownloadProgress> downloadModel(String modelId) =>
      RunAnywhereDownloads.shared.start(modelId);

  /// Flat alias — delete a stored model.
  Future<void> deleteModel(String modelId) =>
      RunAnywhereDownloads.shared.delete(modelId);

  /// Flat alias — register a single-file model.
  ModelInfo registerModel(ModelInfo model) {
    return RunAnywhereModels.shared.register(
      id: model.id,
      name: model.name,
      url: model.downloadURL!,
      framework: model.framework,
      modality: model.category,
      artifactType: model.artifactType,
      supportsThinking: model.supportsThinking,
    );
  }

  /// Flat alias — register a multi-file model.
  ModelInfo registerMultiFileModel(ModelInfo model) {
    final artifact = model.artifactType;
    if (artifact is MultiFileArtifact) {
      return RunAnywhereModels.shared.registerMultiFile(
        id: model.id,
        name: model.name,
        files: artifact.files,
        framework: model.framework,
        modality: model.category,
      );
    }
    // Fall back to single-file registration if the artifact is not multi-file.
    return registerModel(model);
  }

  /// Flat alias — get all registered inference frameworks.
  Future<List<InferenceFramework>> getRegisteredFrameworks() =>
      RunAnywhereFrameworks.getRegisteredFrameworks();

  /// Flat alias — get inference frameworks that support a given capability.
  Future<List<InferenceFramework>> getFrameworksForCapability(
    SDKComponent capability,
  ) =>
      RunAnywhereFrameworks.getFrameworks(capability);

  /// Flat alias — fetch model assignments from the backend catalog.
  /// Returns the current set of available models after refreshing the registry.
  Future<List<ModelInfo>> fetchModelAssignments() async {
    await RunAnywhereModels.shared.refreshModelRegistry();
    return RunAnywhereModels.shared.available();
  }
}
