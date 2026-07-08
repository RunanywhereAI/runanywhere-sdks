/**
 * RunAnywhere+FlatFacade.ts
 *
 * Swift-shaped flat facade delegates — one-liner forwarding methods that mirror
 * Swift's extension-per-capability split. Each method here calls a single
 * capability namespace with no additional logic; methods that add real
 * orchestration (loadModel/unloadModel VLM sync, downloadModel poll loop,
 * generate/processImage AbortSignal wiring, speak audio playback,
 * *Stream async generator wrapping) remain in RunAnywhere.ts.
 *
 * Exported as `flatFacade` and spread onto the `RunAnywhere` singleton so the
 * public API surface is unchanged. Mirrors the Swift pattern of
 * RunAnywhere+*.swift extension files augmenting the same RunAnywhere enum.
 */

import type {
  ModelImportRequest,
  ModelImportResult,
  ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import type { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import { WebModelLifecycle as ModelLifecycleCapability } from './RunAnywhere+ModelLifecycle';
import {
  ModelRegistry as ModelRegistryCapability,
} from './RunAnywhere+ModelRegistry';
import type { RefreshOptions } from '../../Adapters/ModelRegistryAdapter';
import {
  registerModelArchive as registerModelArchiveImpl,
  registerModelFromUrl,
  registerModelMultiFile as registerModelMultiFileImpl,
  type RegisterModelOptions,
  type RegisterMultiFileOptions,
} from './RunAnywhere+Storage';
import { TextGeneration as TextGenerationCapability } from './RunAnywhere+TextGeneration';
import {
  generateStructured as generateStructuredImpl,
  generateWithStructuredOutput as generateWithStructuredOutputImpl,
} from './RunAnywhere+StructuredOutput';
import { ToolCalling as ToolCallingCapability } from './RunAnywhere+ToolCalling';
import { STT as STTCapability } from './RunAnywhere+STT';
import { TTS as TTSCapability, stopTTSPlayback as stopTTSPlaybackImpl } from './RunAnywhere+TTS';
import { VAD as VADCapability } from './RunAnywhere+VAD';
import {
  ragAddDocumentsBatch as ragAddDocumentsBatchImpl,
  ragClearDocuments as ragClearDocumentsImpl,
  ragCreatePipeline as ragCreatePipelineImpl,
  ragDestroyPipeline as ragDestroyPipelineImpl,
  ragGetDocumentCount as ragGetDocumentCountImpl,
  ragGetStatistics as ragGetStatisticsImpl,
  ragIngest as ragIngestImpl,
  ragQuery as ragQueryImpl,
  ragResolvedConfiguration as ragResolvedConfigurationImpl,
} from './RunAnywhere+RAG';
import {
  cleanupVoiceAgent as cleanupVoiceAgentImpl,
  defaultVADModelID as defaultVADModelIDImpl,
  ensureDefaultVAD as ensureDefaultVADImpl,
  getVoiceAgentComponentStates as getVoiceAgentComponentStatesImpl,
  initializeVoiceAgent as initializeVoiceAgentImpl,
  initializeVoiceAgentWithLoadedModels as initializeVoiceAgentWithLoadedModelsImpl,
  processVoiceTurn as processVoiceTurnImpl,
  streamVoiceAgent as streamVoiceAgentImpl,
} from './RunAnywhere+VoiceAgent';
import { VisionLanguage as VisionLanguageCapability } from './RunAnywhere+VisionLanguage';
import { Logging as LoggingCapability } from './RunAnywhere+Logging';
import {
  pcm16ToFloat32 as pcm16ToFloat32Impl,
  pcm16ToFloat32Samples as pcm16ToFloat32SamplesImpl,
  pcm16ToWav as pcm16ToWavImpl,
} from './RunAnywhere+AudioConvert';
import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException';
import type { CancellableCall } from '../RunAnywhere';

function throwIfAborted(signal: AbortSignal | undefined, verb: string): void {
  if (signal?.aborted) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_GENERATION_CANCELLED,
      `${verb} cancelled`,
      'AbortSignal was already aborted before the call was invoked',
    );
  }
}

export const flatFacade = {
  // -------------------------------------------------------------------------
  // Lifecycle — pure delegates (VLM sync logic stays in RunAnywhere.ts)
  // -------------------------------------------------------------------------

  currentModel(
    request?: Parameters<typeof ModelLifecycleCapability.currentModel>[0],
  ): ReturnType<typeof ModelLifecycleCapability.currentModel> {
    return ModelLifecycleCapability.currentModel(request);
  },

  modelInfoForCategory(
    category: Parameters<typeof ModelLifecycleCapability.modelInfoForCategory>[0],
  ): ReturnType<typeof ModelLifecycleCapability.modelInfoForCategory> {
    return ModelLifecycleCapability.modelInfoForCategory(category);
  },

  componentLifecycleSnapshot(
    component: Parameters<typeof ModelLifecycleCapability.componentLifecycleSnapshot>[0],
  ): ReturnType<typeof ModelLifecycleCapability.componentLifecycleSnapshot> {
    return ModelLifecycleCapability.componentLifecycleSnapshot(component);
  },

  // -------------------------------------------------------------------------
  // Model registry — pure delegates
  // -------------------------------------------------------------------------

  listModels(): ReturnType<typeof ModelRegistryCapability.listModels> {
    return ModelRegistryCapability.listModels();
  },

  queryModels(
    query: Parameters<typeof ModelRegistryCapability.queryModels>[0],
  ): ReturnType<typeof ModelRegistryCapability.queryModels> {
    return ModelRegistryCapability.queryModels(query);
  },

  getModel(
    modelId: Parameters<typeof ModelRegistryCapability.getModel>[0],
  ): ReturnType<typeof ModelRegistryCapability.getModel> {
    return ModelRegistryCapability.getModel(modelId);
  },

  downloadedModels(): ReturnType<typeof ModelRegistryCapability.downloadedModels> {
    return ModelRegistryCapability.downloadedModels();
  },

  getDefaultFramework(
    category: Parameters<typeof ModelRegistryCapability.defaultFramework>[0],
  ): ReturnType<typeof ModelRegistryCapability.defaultFramework> {
    return ModelRegistryCapability.defaultFramework(category);
  },

  /**
   * Mirrors Swift `RunAnywhere.refreshModelRegistry(rescanLocal:includeRemoteCatalog:pruneOrphans:)`.
   * Delegates to the internal `ModelRegistry` proto bridge.
   */
  refreshModelRegistry(options?: RefreshOptions): boolean {
    return ModelRegistryCapability.refresh(options);
  },

  /**
   * Import a model through the commons import path. Swift parity:
   * `RunAnywhere.importModel(_ request: RAModelImportRequest)`
   * (RunAnywhere+Storage.swift:286-291) — C++ owns import semantics
   * (merge, overwrite, validation), not a registerModel alias.
   */
  importModel(request: ModelImportRequest): ModelImportResult {
    const result = ModelRegistryCapability.importModel(request);
    if (!result) {
      throw SDKException.backendNotAvailable(
        'importModel',
        'rac_model_registry_import_proto returned no ModelImportResult bytes.',
      );
    }
    return result;
  },

  /**
   * Register a single-file remote model by URL. Mirrors Swift's
   * `RunAnywhere.registerModel(id:name:url:framework:...)` so example
   * catalogs read as declarative entries — the SDK assembles the
   * `ModelInfo` proto.
   */
  registerModel(
    url: string,
    name: string,
    framework: InferenceFramework,
    options?: RegisterModelOptions,
  ): ModelInfo {
    return registerModelFromUrl(url, name, framework, options);
  },

  /**
   * Register an archive-packaged model. The SDK stamps the canonical
   * `artifactType` (`MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE`, etc.) onto the
   * resulting `ModelInfo` and routes the download orchestrator through
   * extraction.
   */
  registerModelArchive(
    url: string,
    name: string,
    framework: InferenceFramework,
    archiveType: Parameters<typeof registerModelArchiveImpl>[3],
    options?: RegisterModelOptions,
  ): ModelInfo {
    return registerModelArchiveImpl(url, name, framework, archiveType, options);
  },

  /**
   * Register a multi-file model (VLM = primary GGUF + mmproj sidecar,
   * embedding = `model.onnx` + `vocab.txt`). The SDK builds the
   * `MultiFileArtifact` proto + `ExpectedModelFiles` manifest from the
   * provided file list.
   */
  registerModelMultiFile(options: RegisterMultiFileOptions): ModelInfo {
    return registerModelMultiFileImpl(options);
  },

  // -------------------------------------------------------------------------
  // Text generation — pure delegates (AbortSignal wiring stays in RunAnywhere.ts)
  // -------------------------------------------------------------------------

  cancelGeneration(): void {
    TextGenerationCapability.cancelGeneration();
  },

  // Direct reference (not a wrapper) so the `<T>` generic of the schema's
  // `parse` override survives on the flat surface; `Parameters<typeof fn>`
  // would collapse `T` to `unknown`. Mirrors Swift
  // `generateStructured(prompt:schema:options:)` (RunAnywhere+StructuredOutput.swift:25).
  generateStructured: generateStructuredImpl,

  // Mirrors Swift's flat
  // `generateWithStructuredOutput(prompt:structuredOutput:options:)`
  // (RunAnywhere+StructuredOutput.swift:139-156).
  generateWithStructuredOutput: generateWithStructuredOutputImpl,

  generateStructuredStream(
    ...args: Parameters<typeof TextGenerationCapability.generateStructuredStream>
  ): ReturnType<typeof TextGenerationCapability.generateStructuredStream> {
    return TextGenerationCapability.generateStructuredStream(...args);
  },

  extractStructuredOutput(
    ...args: Parameters<typeof TextGenerationCapability.extractStructuredOutput>
  ): ReturnType<typeof TextGenerationCapability.extractStructuredOutput> {
    return TextGenerationCapability.extractStructuredOutput(...args);
  },

  // Swift parity: generateWithTools(prompt:options:toolOptions:toolChoice:
  // forcedToolName:validateCalls:) — the Web third argument carries the
  // LLM-options channel + validateCalls (and the AbortSignal that stands in
  // for Swift Task cancellation). Executors are registry-only (registerTool);
  // there is no executor parameter, matching Swift.
  generateWithTools(
    prompt: Parameters<typeof ToolCallingCapability.generateWithTools>[0],
    options?: Parameters<typeof ToolCallingCapability.generateWithTools>[1],
    extra?: Parameters<typeof ToolCallingCapability.generateWithTools>[2],
  ): ReturnType<typeof ToolCallingCapability.generateWithTools> {
    return ToolCallingCapability.generateWithTools(prompt, options, extra);
  },

  // -------------------------------------------------------------------------
  // STT — entry-guard delegates
  // -------------------------------------------------------------------------

  transcribe(
    audio: Parameters<typeof STTCapability.transcribeAuto>[0],
    options?: Parameters<typeof STTCapability.transcribeAuto>[1],
    extra: CancellableCall = {},
  ): ReturnType<typeof STTCapability.transcribeAuto> {
    throwIfAborted(extra.signal, 'transcribe');
    return STTCapability.transcribeAuto(audio, options);
  },

  // -------------------------------------------------------------------------
  // TTS — entry-guard delegates
  // -------------------------------------------------------------------------

  synthesize(
    text: Parameters<typeof TTSCapability.synthesizeAuto>[0],
    options?: Parameters<typeof TTSCapability.synthesizeAuto>[1],
    extra: CancellableCall = {},
  ): ReturnType<typeof TTSCapability.synthesizeAuto> {
    throwIfAborted(extra.signal, 'synthesize');
    return TTSCapability.synthesizeAuto(text, options);
  },

  stopSynthesis(
    handle: Parameters<typeof TTSCapability.stop>[0],
  ): ReturnType<typeof TTSCapability.stop> {
    return TTSCapability.stop(handle);
  },

  /**
   * Stop current speech playback. Swift parity
   * (RunAnywhere+TTS.swift:133-136): stops the shared `speak()` browser
   * playback first, then stops in-flight synthesis. The handle is optional —
   * pass it only when using the handle-owning `RunAnywhere.tts.*` namespace.
   */
  stopSpeaking(
    handle?: Parameters<typeof TTSCapability.stop>[0],
  ): boolean {
    stopTTSPlaybackImpl();
    return handle !== undefined ? TTSCapability.stop(handle) : true;
  },

  // -------------------------------------------------------------------------
  // VAD — pure delegates
  // -------------------------------------------------------------------------

  detectVoiceActivity(
    ...args: Parameters<typeof VADCapability.detectVoiceAuto>
  ): ReturnType<typeof VADCapability.detectVoiceAuto> {
    return VADCapability.detectVoiceAuto(...args);
  },

  resetVAD(
    handle: Parameters<typeof VADCapability.reset>[0],
  ): ReturnType<typeof VADCapability.reset> {
    return VADCapability.reset(handle);
  },

  // -------------------------------------------------------------------------
  // RAG — pure delegates
  // -------------------------------------------------------------------------

  // Direct references (not wrappers) because object-literal methods cannot
  // restate overloads and `Parameters<typeof fn>` collapses an overloaded
  // function to its last signature, which would narrow the flat surface.
  // Mirrors Swift's two ragCreatePipeline entry points
  // (RunAnywhere+RAG.swift:39-50 / :58) and the text + document ragIngest
  // overloads (RunAnywhere+RAG.swift:86-100).
  ragCreatePipeline: ragCreatePipelineImpl,

  // Mirrors Swift `ragResolvedConfiguration(embeddingModel:llmModel:baseConfiguration:)`
  // (RunAnywhere+RAG.swift:19-35).
  ragResolvedConfiguration(
    ...args: Parameters<typeof ragResolvedConfigurationImpl>
  ): ReturnType<typeof ragResolvedConfigurationImpl> {
    return ragResolvedConfigurationImpl(...args);
  },

  ragDestroyPipeline(): ReturnType<typeof ragDestroyPipelineImpl> {
    return ragDestroyPipelineImpl();
  },

  ragIngest: ragIngestImpl,

  ragAddDocumentsBatch(
    ...args: Parameters<typeof ragAddDocumentsBatchImpl>
  ): ReturnType<typeof ragAddDocumentsBatchImpl> {
    return ragAddDocumentsBatchImpl(...args);
  },

  ragGetDocumentCount(): ReturnType<typeof ragGetDocumentCountImpl> {
    return ragGetDocumentCountImpl();
  },

  ragGetStatistics(): ReturnType<typeof ragGetStatisticsImpl> {
    return ragGetStatisticsImpl();
  },

  ragClearDocuments(): ReturnType<typeof ragClearDocumentsImpl> {
    return ragClearDocumentsImpl();
  },

  ragQuery(
    ...args: Parameters<typeof ragQueryImpl>
  ): ReturnType<typeof ragQueryImpl> {
    return ragQueryImpl(...args);
  },

  // -------------------------------------------------------------------------
  // Voice agent — pure delegates (Swift RunAnywhere+VoiceAgent.swift flat
  // statics: initializeVoiceAgent / initializeVoiceAgentWithLoadedModels /
  // ensureDefaultVAD / defaultVADModelID / getVoiceAgentComponentStates /
  // processVoiceTurn / streamVoiceAgent / cleanupVoiceAgent)
  // -------------------------------------------------------------------------

  /** Mirrors Swift `RunAnywhere.defaultVADModelID` (RunAnywhere+VoiceAgent.swift:37). */
  defaultVADModelID: defaultVADModelIDImpl,

  initializeVoiceAgent(
    ...args: Parameters<typeof initializeVoiceAgentImpl>
  ): ReturnType<typeof initializeVoiceAgentImpl> {
    return initializeVoiceAgentImpl(...args);
  },

  initializeVoiceAgentWithLoadedModels(
    ...args: Parameters<typeof initializeVoiceAgentWithLoadedModelsImpl>
  ): ReturnType<typeof initializeVoiceAgentWithLoadedModelsImpl> {
    return initializeVoiceAgentWithLoadedModelsImpl(...args);
  },

  /** Mirrors Swift `RunAnywhere.ensureDefaultVAD(modelID:)` (RunAnywhere+VoiceAgent.swift:57). */
  ensureDefaultVAD(
    ...args: Parameters<typeof ensureDefaultVADImpl>
  ): ReturnType<typeof ensureDefaultVADImpl> {
    return ensureDefaultVADImpl(...args);
  },

  getVoiceAgentComponentStates(): ReturnType<typeof getVoiceAgentComponentStatesImpl> {
    return getVoiceAgentComponentStatesImpl();
  },

  processVoiceTurn(
    ...args: Parameters<typeof processVoiceTurnImpl>
  ): ReturnType<typeof processVoiceTurnImpl> {
    return processVoiceTurnImpl(...args);
  },

  streamVoiceAgent(
    ...args: Parameters<typeof streamVoiceAgentImpl>
  ): ReturnType<typeof streamVoiceAgentImpl> {
    return streamVoiceAgentImpl(...args);
  },

  cleanupVoiceAgent(): ReturnType<typeof cleanupVoiceAgentImpl> {
    return cleanupVoiceAgentImpl();
  },

  // -------------------------------------------------------------------------
  // VLM — pure delegate (auto-load + AbortSignal stays in RunAnywhere.ts)
  // -------------------------------------------------------------------------

  cancelVLMGeneration(): ReturnType<typeof VisionLanguageCapability.cancelVLMGeneration> {
    return VisionLanguageCapability.cancelVLMGeneration();
  },

  // -------------------------------------------------------------------------
  // Audio conversion — pure delegates. Exactly Swift RAAudioConvert.swift's
  // flat statics (`RunAnywhere.pcm16ToFloat32` / `pcm16ToFloat32Samples` /
  // `pcm16ToWav`); Swift exposes no audio-convert namespace.
  // -------------------------------------------------------------------------

  pcm16ToFloat32(
    ...args: Parameters<typeof pcm16ToFloat32Impl>
  ): ReturnType<typeof pcm16ToFloat32Impl> {
    return pcm16ToFloat32Impl(...args);
  },

  pcm16ToFloat32Samples(
    ...args: Parameters<typeof pcm16ToFloat32SamplesImpl>
  ): ReturnType<typeof pcm16ToFloat32SamplesImpl> {
    return pcm16ToFloat32SamplesImpl(...args);
  },

  pcm16ToWav(
    ...args: Parameters<typeof pcm16ToWavImpl>
  ): ReturnType<typeof pcm16ToWavImpl> {
    return pcm16ToWavImpl(...args);
  },

  // -------------------------------------------------------------------------
  // Logging — pure delegates. Exactly Swift RunAnywhere+Logging.swift's flat
  // statics (`RunAnywhere.configureLogging` / `setLocalLoggingEnabled` /
  // `setLogLevel` / `addLogDestination` / `setDebugMode` / `flushLogs`).
  // -------------------------------------------------------------------------

  configureLogging(
    ...args: Parameters<typeof LoggingCapability.configureLogging>
  ): ReturnType<typeof LoggingCapability.configureLogging> {
    return LoggingCapability.configureLogging(...args);
  },

  setLocalLoggingEnabled(
    ...args: Parameters<typeof LoggingCapability.setLocalLoggingEnabled>
  ): ReturnType<typeof LoggingCapability.setLocalLoggingEnabled> {
    return LoggingCapability.setLocalLoggingEnabled(...args);
  },

  setLogLevel(
    ...args: Parameters<typeof LoggingCapability.setLogLevel>
  ): ReturnType<typeof LoggingCapability.setLogLevel> {
    return LoggingCapability.setLogLevel(...args);
  },

  addLogDestination(
    ...args: Parameters<typeof LoggingCapability.addLogDestination>
  ): ReturnType<typeof LoggingCapability.addLogDestination> {
    return LoggingCapability.addLogDestination(...args);
  },

  setDebugMode(
    ...args: Parameters<typeof LoggingCapability.setDebugMode>
  ): ReturnType<typeof LoggingCapability.setDebugMode> {
    return LoggingCapability.setDebugMode(...args);
  },

  flushLogs(
    ...args: Parameters<typeof LoggingCapability.flushLogs>
  ): ReturnType<typeof LoggingCapability.flushLogs> {
    return LoggingCapability.flushLogs(...args);
  },
};
