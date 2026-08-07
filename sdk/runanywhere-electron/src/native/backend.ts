// The in-process RaBackend: it owns the addon and the opaque id maps for
// multi-instance handles (RAG sessions, live STT streams). Model lifecycle is
// tracked inside commons (one model per component), so loads and inference are
// plain pass-throughs with no handle bookkeeping here. Every native integer
// handle stays inside this class; only proto bytes and string ids leave it.

import * as os from 'node:os';
import * as path from 'node:path';

import type { ControlPlaneRequest, ProtoBytes, ProtoSink, RaBackend, ToolExecutor } from '../backend.js';
import { SDKException } from '../errors.js';
import type { NativeAddon } from './addon-api.js';

export class NativeBackend implements RaBackend {
  private ragSessions = new Map<string, number>();
  private sttStreams = new Map<string, number>();
  private counter = 0;

  constructor(private readonly addon: NativeAddon) {}

  // lifecycle + control plane
  async version(): Promise<string> {
    return this.addon.version;
  }
  async initialize(opts: { baseDir?: string; secureDir?: string } = {}): Promise<void> {
    const base = opts.baseDir ?? path.join(os.homedir(), '.runanywhere');
    const secure = opts.secureDir ?? path.join(base, 'secure');
    this.addon.initialize(secure, base);
  }
  async configureControlPlane(req: ControlPlaneRequest): Promise<ProtoBytes> {
    if (!this.addon.configureControlPlane) {
      throw SDKException.of(
        SDKException.notImplemented().code,
        'control plane unavailable: addon built without RAC_DESKTOP_ADAPTER'
      );
    }
    return this.addon.configureControlPlane(
      req.environment,
      req.apiKey,
      req.baseUrl,
      req.deviceId,
      req.platform,
      req.sdkVersion,
      req.sdkBinding,
      req.appIdentifier,
      req.appName,
      req.appVersion,
      req.phase1Bytes,
      req.phase2Bytes
    );
  }
  async shutdown(): Promise<void> {
    this.ragSessions.clear();
    this.sttStreams.clear();
    this.addon.shutdown();
  }
  async hasControlPlane(): Promise<boolean> {
    return this.addon.hasControlPlane === true;
  }
  async devicePersistentId(): Promise<string> {
    return this.addon.devicePersistentId();
  }
  async devStagingBaseUrl(): Promise<string> {
    return this.addon.devStagingBaseUrl();
  }

  // capabilities + registry
  async frameworksForCapability(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.frameworksForCapability(request);
  }
  async deviceType(): Promise<string> {
    return this.addon.deviceType();
  }
  async registerModel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.registerModel(request);
  }
  async registerModelFromUrl(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.registerModelFromUrl(request);
  }
  async modelRegistryList(request?: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.modelRegistryList(request);
  }
  async modelRegistryQuery(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.modelRegistryQuery(request);
  }
  async registerMultiFile(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.registerMultiFile(request);
  }
  async modelList(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.modelList(request);
  }
  async modelGet(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.modelGet(request);
  }
  async deleteModel(modelId: string): Promise<void> {
    this.addon.deleteModel(modelId);
  }

  // model lifecycle
  async loadModel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.loadModel(request);
  }
  async resolveModelPaths(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.resolveModelPaths(request);
  }
  async unloadModel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.unloadModel(request);
  }
  async currentModel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.currentModel(request);
  }

  // download
  async downloadPlan(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.downloadPlan(request);
  }
  async downloadStart(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.downloadStart(request);
  }
  async downloadCancel(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.downloadCancel(request);
  }
  async downloadResume(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.downloadResume(request);
  }
  async downloadProgressPoll(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.downloadProgressPoll(request);
  }

  // llm
  async llmGenerate(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.llmGenerate(request);
  }
  llmGenerateStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.addon.llmGenerateStream(request, onEvent);
  }
  async llmCancel(): Promise<void> {
    this.addon.llmCancel();
  }
  async structuredPreparePrompt(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.structuredPreparePrompt(request);
  }
  async structuredParse(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.structuredParse(request);
  }
  toolRunLoop(request: ProtoBytes, onExecute: ToolExecutor): Promise<ProtoBytes> {
    return this.addon.toolRunLoop(request, onExecute);
  }
  async toolCancel(): Promise<void> {
    this.addon.toolCancel();
  }

  // vlm
  async vlmGenerate(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.vlmGenerate(request);
  }
  vlmGenerateStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.addon.vlmGenerateStream(request, onEvent);
  }
  async vlmCancel(): Promise<void> {
    this.addon.vlmCancel();
  }

  // stt
  async sttTranscribe(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.sttTranscribe(request);
  }
  sttTranscribeStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.addon.sttTranscribeStream(request, onEvent);
  }
  async sttStreamStart(request: ProtoBytes): Promise<string> {
    const handle = this.addon.sttStreamStart(request);
    this.counter += 1;
    const id = `stt_${this.counter}`;
    this.sttStreams.set(id, handle);
    return id;
  }
  async sttStreamFeed(session: string, pcm: ProtoBytes): Promise<void> {
    this.addon.sttStreamFeed(this.sttHandle(session), pcm);
  }
  async sttStreamStop(session: string): Promise<void> {
    const handle = this.sttStreams.get(session);
    if (handle == null) return;
    this.addon.sttStreamStop(handle);
  }
  async sttStreamCancel(session: string): Promise<void> {
    const handle = this.sttStreams.get(session);
    if (handle == null) return;
    this.addon.sttStreamCancel(handle);
  }
  sttStreamEvents(session: string, onEvent: ProtoSink): Promise<void> {
    return this.addon.sttStreamSubscribe(this.sttHandle(session), onEvent).finally(() => {
      this.sttStreams.delete(session);
    });
  }
  async sttState(): Promise<ProtoBytes> {
    return this.addon.sttState();
  }

  // tts
  async ttsSynthesize(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.ttsSynthesize(request);
  }
  ttsSynthesizeStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.addon.ttsSynthesizeStream(request, onEvent);
  }
  async ttsStop(): Promise<ProtoBytes> {
    return this.addon.ttsStop();
  }
  async ttsListVoices(): Promise<ProtoBytes> {
    return this.addon.ttsListVoices();
  }

  // vad
  async vadConfigure(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.vadConfigure(request);
  }
  async vadProcess(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.vadProcess(request);
  }
  async vadStart(): Promise<ProtoBytes> {
    return this.addon.vadStart();
  }
  async vadStop(): Promise<ProtoBytes> {
    return this.addon.vadStop();
  }
  async vadReset(): Promise<ProtoBytes> {
    return this.addon.vadReset();
  }

  // embeddings + rerank
  async embed(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.embed(request);
  }
  async rerank(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.rerank(request);
  }

  // diarization + segmentation
  async diarize(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.diarize(request);
  }
  async segment(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.segment(request);
  }

  // lora + image generation
  async loraApply(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.loraApply(request);
  }
  async loraRemove(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.loraRemove(request);
  }
  async loraList(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.loraList(request);
  }
  async loraState(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.loraState(request);
  }
  imageGenerate(request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.imageGenerate(request);
  }

  // rag
  async ragOpen(config: ProtoBytes): Promise<string> {
    const handle = await this.addon.ragCreateSession(config);
    this.counter += 1;
    const id = `rag_${this.counter}`;
    this.ragSessions.set(id, handle);
    return id;
  }
  async ragIngest(session: string, document: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.ragIngest(this.ragHandle(session), document);
  }
  async ragQuery(session: string, query: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.ragQuery(this.ragHandle(session), query);
  }
  ragQueryStream(session: string, query: ProtoBytes, onEvent: ProtoSink): Promise<void> {
    return this.addon.ragQueryStream(this.ragHandle(session), query, onEvent);
  }
  async ragSearch(session: string, request: ProtoBytes): Promise<ProtoBytes> {
    return this.addon.ragSearch(this.ragHandle(session), request);
  }
  async ragStats(session: string): Promise<ProtoBytes> {
    return this.addon.ragStats(this.ragHandle(session));
  }
  async ragClear(session: string): Promise<ProtoBytes> {
    return this.addon.ragClear(this.ragHandle(session));
  }
  async ragCancel(session: string): Promise<void> {
    this.addon.ragCancel(this.ragHandle(session));
  }
  async ragClose(session: string): Promise<void> {
    const handle = this.ragSessions.get(session);
    if (handle == null) return;
    this.ragSessions.delete(session);
    this.addon.ragDestroySession(handle);
  }

  // secure store
  async secureSet(key: string, value: string): Promise<void> {
    this.addon.secureSet(key, value);
  }
  async secureGet(key: string): Promise<string | null> {
    return this.addon.secureGet(key);
  }
  async secureDelete(key: string): Promise<void> {
    this.addon.secureDelete(key);
  }

  // internals
  private ragHandle(session: string): number {
    const handle = this.ragSessions.get(session);
    if (handle == null) throw SDKException.invalidState(`RAG session ${session} is closed`);
    return handle;
  }
  private sttHandle(session: string): number {
    const handle = this.sttStreams.get(session);
    if (handle == null) throw SDKException.invalidState(`STT stream ${session} is closed`);
    return handle;
  }
}
