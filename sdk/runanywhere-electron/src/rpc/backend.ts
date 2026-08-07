// The renderer-side RaBackend: every operation is a forward over the MessagePort
// to the utility host, which runs the real NativeBackend. Because the contract is
// proto bytes plus scalars, each method is a mechanical `send`, and the
// namespaces built on top are the same code as in the main process.

import { rpcMethodFor } from '../backend.js';
import type { ControlPlaneRequest, ProtoBytes, ProtoSink, RaBackend, ToolExecutor } from '../backend.js';

/**
 * Sends one RPC and resolves its reply; `onChunk` receives streamed proto bytes,
 * and `onToolExec` runs a tool the host asked the renderer to execute (the reverse
 * leg of the tool-calling loop).
 */
export type RpcSend = (
  method: string,
  args: unknown[],
  onChunk?: (chunk: unknown) => void,
  onToolExec?: (toolCall: Uint8Array) => Uint8Array | Promise<Uint8Array>
) => Promise<unknown>;

export class RpcBackend implements RaBackend {
  constructor(private readonly send: RpcSend) {}

  private call<T>(op: string, args: unknown[], onChunk?: (chunk: unknown) => void): Promise<T> {
    return this.send(rpcMethodFor(op), args, onChunk) as Promise<T>;
  }

  // lifecycle + control plane
  version(): Promise<string> {
    return this.call('version', []);
  }
  initialize(opts: { baseDir?: string; secureDir?: string }): Promise<void> {
    return this.call('initialize', [opts]);
  }
  configureControlPlane(request: ControlPlaneRequest): Promise<ProtoBytes> {
    return this.call('configureControlPlane', [request]);
  }
  shutdown(): Promise<void> {
    return this.call('shutdown', []);
  }
  hasControlPlane(): Promise<boolean> {
    return this.call('hasControlPlane', []);
  }
  devicePersistentId(): Promise<string> {
    return this.call('devicePersistentId', []);
  }
  devStagingBaseUrl(): Promise<string> {
    return this.call('devStagingBaseUrl', []);
  }

  // capabilities + registry
  frameworksForCapability(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('frameworksForCapability', [request]);
  }
  deviceType(): Promise<string> {
    return this.call('deviceType', []);
  }
  registerModel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('registerModel', [request]);
  }
  registerModelFromUrl(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('registerModelFromUrl', [request]);
  }
  modelRegistryList(request?: ProtoBytes): Promise<ProtoBytes> {
    return this.call('modelRegistryList', [request]);
  }
  modelRegistryQuery(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('modelRegistryQuery', [request]);
  }
  registerMultiFile(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('registerMultiFile', [request]);
  }
  modelList(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('modelList', [request]);
  }
  modelGet(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('modelGet', [request]);
  }
  deleteModel(modelId: string): Promise<void> {
    return this.call('deleteModel', [modelId]);
  }

  // model lifecycle
  loadModel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('loadModel', [request]);
  }
  resolveModelPaths(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('resolveModelPaths', [request]);
  }
  unloadModel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('unloadModel', [request]);
  }
  currentModel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('currentModel', [request]);
  }

  // download
  downloadPlan(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('downloadPlan', [request]);
  }
  downloadStart(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('downloadStart', [request]);
  }
  downloadCancel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('downloadCancel', [request]);
  }
  downloadResume(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('downloadResume', [request]);
  }
  downloadProgressPoll(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('downloadProgressPoll', [request]);
  }

  // llm
  llmGenerate(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('llmGenerate', [request]);
  }
  llmGenerateStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.call('llmGenerateStream', [request], onEvent as (c: unknown) => void);
  }
  llmCancel(): Promise<void> {
    return this.call('llmCancel', []);
  }
  structuredPreparePrompt(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('structuredPreparePrompt', [request]);
  }
  structuredParse(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('structuredParse', [request]);
  }
  toolRunLoop(request: ProtoBytes, onExecute: ToolExecutor): Promise<ProtoBytes> {
    // commons drives the loop in the host; each tool executes back here via the
    // reverse channel (onToolExec), keyed to this request in the preload transport.
    return this.send(rpcMethodFor('toolRunLoop'), [request], undefined, onExecute) as Promise<ProtoBytes>;
  }
  toolCancel(): Promise<void> {
    return this.call('toolCancel', []);
  }

  // vlm
  vlmGenerate(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('vlmGenerate', [request]);
  }
  vlmGenerateStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.call('vlmGenerateStream', [request], onEvent as (c: unknown) => void);
  }
  vlmCancel(): Promise<void> {
    return this.call('vlmCancel', []);
  }

  // stt
  sttTranscribe(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('sttTranscribe', [request]);
  }
  sttTranscribeStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.call('sttTranscribeStream', [request], onEvent as (c: unknown) => void);
  }
  sttStreamStart(request: ProtoBytes): Promise<string> {
    return this.call('sttStreamStart', [request]);
  }
  sttStreamFeed(session: string, pcm: ProtoBytes): Promise<void> {
    return this.call('sttStreamFeed', [session, pcm]);
  }
  sttStreamStop(session: string): Promise<void> {
    return this.call('sttStreamStop', [session]);
  }
  sttStreamCancel(session: string): Promise<void> {
    return this.call('sttStreamCancel', [session]);
  }
  sttStreamEvents(session: string, onEvent: ProtoSink): Promise<void> {
    return this.call('sttStreamEvents', [session], onEvent as (c: unknown) => void);
  }
  sttState(): Promise<ProtoBytes> {
    return this.call('sttState', []);
  }

  // tts
  ttsSynthesize(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('ttsSynthesize', [request]);
  }
  ttsSynthesizeStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.call('ttsSynthesizeStream', [request], onEvent as (c: unknown) => void);
  }
  ttsStop(): Promise<ProtoBytes> {
    return this.call('ttsStop', []);
  }
  ttsListVoices(): Promise<ProtoBytes> {
    return this.call('ttsListVoices', []);
  }

  // vad
  vadConfigure(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('vadConfigure', [request]);
  }
  vadProcess(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('vadProcess', [request]);
  }
  vadStart(): Promise<ProtoBytes> {
    return this.call('vadStart', []);
  }
  vadStop(): Promise<ProtoBytes> {
    return this.call('vadStop', []);
  }
  vadReset(): Promise<ProtoBytes> {
    return this.call('vadReset', []);
  }

  // embeddings + rerank
  embed(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('embed', [request]);
  }
  rerank(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('rerank', [request]);
  }

  // diarization + segmentation
  diarize(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('diarize', [request]);
  }
  segment(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('segment', [request]);
  }

  // lora + image generation
  loraApply(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('loraApply', [request]);
  }
  loraRemove(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('loraRemove', [request]);
  }
  loraList(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('loraList', [request]);
  }
  loraState(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('loraState', [request]);
  }
  imageGenerate(request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('imageGenerate', [request]);
  }

  // rag
  ragOpen(config: ProtoBytes): Promise<string> {
    return this.call('ragOpen', [config]);
  }
  ragIngest(session: string, document: ProtoBytes): Promise<ProtoBytes> {
    return this.call('ragIngest', [session, document]);
  }
  ragQuery(session: string, query: ProtoBytes): Promise<ProtoBytes> {
    return this.call('ragQuery', [session, query]);
  }
  ragQueryStream(session: string, query: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.call('ragQueryStream', [session, query], onEvent as (c: unknown) => void);
  }
  ragSearch(session: string, request: ProtoBytes): Promise<ProtoBytes> {
    return this.call('ragSearch', [session, request]);
  }
  ragStats(session: string): Promise<ProtoBytes> {
    return this.call('ragStats', [session]);
  }
  ragClear(session: string): Promise<ProtoBytes> {
    return this.call('ragClear', [session]);
  }
  ragCancel(session: string): Promise<void> {
    return this.call('ragCancel', [session]);
  }
  ragClose(session: string): Promise<void> {
    return this.call('ragClose', [session]);
  }

  // secure store
  secureSet(key: string, value: string): Promise<void> {
    return this.call('secureSet', [key, value]);
  }
  secureGet(key: string): Promise<string | null> {
    return this.call('secureGet', [key]);
  }
  secureDelete(key: string): Promise<void> {
    return this.call('secureDelete', [key]);
  }
}
