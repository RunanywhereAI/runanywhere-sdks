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

import type { ModelInfo } from '@runanywhere/proto-ts/model_types';
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
import { StructuredOutput as StructuredOutputCapability } from './RunAnywhere+StructuredOutput';
import { ToolCalling as ToolCallingCapability } from './RunAnywhere+ToolCalling';
import { STT as STTCapability } from './RunAnywhere+STT';
import { TTS as TTSCapability } from './RunAnywhere+TTS';
import { VAD as VADCapability } from './RunAnywhere+VAD';
import { RAG as RAGCapability } from './RunAnywhere+RAG';
import { VoiceAgent as VoiceAgentCapability } from './RunAnywhere+VoiceAgent';
import { VisionLanguage as VisionLanguageCapability } from './RunAnywhere+VisionLanguage';
import { SDKErrorCode, SDKException } from '../../Foundation/SDKException';
import type { CancellableCall } from '../RunAnywhere';

function throwIfAborted(signal: AbortSignal | undefined, verb: string): void {
  if (signal?.aborted) {
    throw SDKException.fromCode(
      SDKErrorCode.GenerationCancelled,
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
   * Delegates to `modelRegistry.refresh(options)` on the Web flat facade.
   */
  refreshModelRegistry(options?: RefreshOptions): boolean {
    return ModelRegistryCapability.refresh(options);
  },

  importModel(model: ModelInfo): boolean {
    return ModelRegistryCapability.registerModel(model);
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

  generateStructured(
    ...args: Parameters<typeof StructuredOutputCapability.generate>
  ): ReturnType<typeof StructuredOutputCapability.generate> {
    return StructuredOutputCapability.generate(...args);
  },

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

  generateWithTools(
    prompt: Parameters<typeof ToolCallingCapability.generateWithTools>[0],
    options?: Parameters<typeof ToolCallingCapability.generateWithTools>[1],
  ): ReturnType<typeof ToolCallingCapability.generateWithTools> {
    return ToolCallingCapability.generateWithTools(prompt, options);
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

  stopSpeaking(
    handle: Parameters<typeof TTSCapability.stop>[0],
  ): ReturnType<typeof TTSCapability.stop> {
    return TTSCapability.stop(handle);
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

  ragCreatePipeline(
    ...args: Parameters<typeof RAGCapability.createPipeline>
  ): ReturnType<typeof RAGCapability.createPipeline> {
    return RAGCapability.createPipeline(...args);
  },

  ragDestroyPipeline(): ReturnType<typeof RAGCapability.destroyPipeline> {
    return RAGCapability.destroyPipeline();
  },

  ragIngest(
    ...args: Parameters<typeof RAGCapability.ingest>
  ): ReturnType<typeof RAGCapability.ingest> {
    return RAGCapability.ingest(...args);
  },

  ragAddDocumentsBatch(
    ...args: Parameters<typeof RAGCapability.addDocumentsBatch>
  ): ReturnType<typeof RAGCapability.addDocumentsBatch> {
    return RAGCapability.addDocumentsBatch(...args);
  },

  ragGetDocumentCount(): ReturnType<typeof RAGCapability.getDocumentCount> {
    return RAGCapability.getDocumentCount();
  },

  ragGetStatistics(): ReturnType<typeof RAGCapability.getStatistics> {
    return RAGCapability.getStatistics();
  },

  ragClearDocuments(): ReturnType<typeof RAGCapability.clearDocuments> {
    return RAGCapability.clearDocuments();
  },

  ragQuery(
    ...args: Parameters<typeof RAGCapability.query>
  ): ReturnType<typeof RAGCapability.query> {
    return RAGCapability.query(...args);
  },

  // -------------------------------------------------------------------------
  // Voice agent — pure delegates
  // -------------------------------------------------------------------------

  initializeVoiceAgent(
    ...args: Parameters<typeof VoiceAgentCapability.initialize>
  ): ReturnType<typeof VoiceAgentCapability.initialize> {
    return VoiceAgentCapability.initialize(...args);
  },

  initializeVoiceAgentWithLoadedModels(
    ...args: Parameters<typeof VoiceAgentCapability.initializeWithLoadedModels>
  ): ReturnType<typeof VoiceAgentCapability.initializeWithLoadedModels> {
    return VoiceAgentCapability.initializeWithLoadedModels(...args);
  },

  getVoiceAgentComponentStates(): ReturnType<typeof VoiceAgentCapability.getComponentStates> {
    return VoiceAgentCapability.getComponentStates();
  },

  processVoiceTurn(
    ...args: Parameters<typeof VoiceAgentCapability.processTurn>
  ): ReturnType<typeof VoiceAgentCapability.processTurn> {
    return VoiceAgentCapability.processTurn(...args);
  },

  streamVoiceAgent(
    ...args: Parameters<typeof VoiceAgentCapability.stream>
  ): ReturnType<typeof VoiceAgentCapability.stream> {
    return VoiceAgentCapability.stream(...args);
  },

  cleanupVoiceAgent(): ReturnType<typeof VoiceAgentCapability.cleanup> {
    return VoiceAgentCapability.cleanup();
  },

  // -------------------------------------------------------------------------
  // VLM — pure delegate (auto-load + AbortSignal stays in RunAnywhere.ts)
  // -------------------------------------------------------------------------

  cancelVLMGeneration(): ReturnType<typeof VisionLanguageCapability.cancelVLMGeneration> {
    return VisionLanguageCapability.cancelVLMGeneration();
  },
};
