// rpc-backend.ts — the {@link RaBackend} a renderer uses.
//
// Every operation is a forward over the MessagePort to the utility host, which
// runs the real `NativeBackend`. Because the shapes on both sides are identical,
// the namespaces built on top are the same code as in the main process.

import type { DownloadProgress, ResolvedModel } from '../download';
import type {
  NativeDiarizationOptions,
  NativeEmbedOptions,
  NativeGenerateOptions,
  NativeSttOptions,
  NativeTtsOptions,
  NativeVadConfig,
} from './options';
import { rpcMethodFor } from './backend';
import type {
  BackendLoadOptions,
  LoadSlot,
  LoadedModel,
  NativeAudio,
  NativeAudioChunk,
  NativeDiarization,
  NativeImagePayload,
  NativeLoraEntry,
  NativeRanked,
  NativeSegmentation,
  NativeSttInfo,
  NativeSttPartial,
  NativeStreamResult,
  NativeTranscription,
  NativeTtsInfo,
  RaBackend,
  StorageReport,
} from './backend';

/** Sends one RPC and resolves its reply; `onChunk` receives streamed items. */
export type RpcSend = (
  method: string,
  args: unknown[],
  onChunk?: (chunk: unknown) => void
) => Promise<unknown>;

/** Renderer-side backend that forwards every operation to the utility host. */
export class RpcBackend implements RaBackend {
  constructor(private readonly send: RpcSend) {}

  private call<T>(op: string, args: unknown[], onChunk?: (chunk: unknown) => void): Promise<T> {
    return this.send(rpcMethodFor(op), args, onChunk) as Promise<T>;
  }

  // ---- lifecycle ----
  version(): Promise<string> {
    return this.call('version', []);
  }
  initialize(opts: { secureDir?: string; baseDir?: string }): Promise<void> {
    return this.call('initialize', [opts]);
  }
  shutdown(): Promise<void> {
    return this.call('shutdown', []);
  }

  // ---- model store ----
  resolveModel(
    source: string,
    onProgress?: (p: DownloadProgress) => void
  ): Promise<ResolvedModel> {
    return this.call('resolveModel', [source], onProgress as (c: unknown) => void);
  }
  modelStatus(): Promise<Record<string, { downloaded: boolean; sizeBytes: number }>> {
    return this.call('modelStatus', []);
  }
  pathExists(path: string): Promise<boolean> {
    return this.call('pathExists', [path]);
  }
  storage(): Promise<StorageReport> {
    return this.call('storage', []);
  }
  deleteModel(id: string): Promise<void> {
    return this.call('deleteModel', [id]);
  }
  registerModel(
    id: string,
    localPath: string,
    category: number,
    framework: number
  ): Promise<void> {
    return this.call('registerModel', [id, localPath, category, framework]);
  }
  ensure(slot: LoadSlot, source: string, options?: BackendLoadOptions): Promise<LoadedModel> {
    return this.call('ensure', [slot, source, options]);
  }
  loaded(slot: LoadSlot): Promise<LoadedModel | null> {
    return this.call('loaded', [slot]);
  }
  unload(slot?: LoadSlot): Promise<void> {
    return this.call('unload', [slot]);
  }

  // ---- llm ----
  llmGenerate(
    prompt: string,
    options: NativeGenerateOptions,
    onToken: (token: string) => void
  ): Promise<NativeStreamResult> {
    return this.call('llmGenerate', [prompt, options], onToken as (c: unknown) => void);
  }
  llmCancel(): Promise<void> {
    return this.call('llmCancel', []);
  }
  loraApply(adapterPath: string, scale: number): Promise<void> {
    return this.call('loraApply', [adapterPath, scale]);
  }
  loraRemove(adapterPath?: string): Promise<void> {
    return this.call('loraRemove', [adapterPath]);
  }
  loraList(): Promise<NativeLoraEntry[]> {
    return this.call('loraList', []);
  }

  // ---- vlm ----
  vlmGenerate(
    image: NativeImagePayload,
    prompt: string,
    options: NativeGenerateOptions,
    onToken: (token: string) => void
  ): Promise<NativeStreamResult> {
    return this.call('vlmGenerate', [image, prompt, options], onToken as (c: unknown) => void);
  }
  vlmCancel(): Promise<void> {
    return this.call('vlmCancel', []);
  }

  // ---- stt ----
  sttTranscribe(pcm16: Uint8Array, options: NativeSttOptions): Promise<NativeTranscription> {
    return this.call('sttTranscribe', [pcm16, options]);
  }
  sttTranscribeStream(
    pcm16: Uint8Array,
    options: NativeSttOptions,
    onPartial: (p: NativeSttPartial) => void
  ): Promise<void> {
    return this.call(
      'sttTranscribeStream',
      [pcm16, options],
      onPartial as (c: unknown) => void
    );
  }
  sttInfo(): Promise<NativeSttInfo> {
    return this.call('sttInfo', []);
  }

  // ---- tts ----
  ttsSynthesize(text: string, options: NativeTtsOptions): Promise<NativeAudio> {
    return this.call('ttsSynthesize', [text, options]);
  }
  ttsSynthesizeStream(
    text: string,
    options: NativeTtsOptions,
    onChunk: (c: NativeAudioChunk) => void
  ): Promise<void> {
    return this.call('ttsSynthesizeStream', [text, options], onChunk as (c: unknown) => void);
  }
  ttsStop(): Promise<void> {
    return this.call('ttsStop', []);
  }
  ttsInfo(): Promise<NativeTtsInfo> {
    return this.call('ttsInfo', []);
  }

  // ---- vad ----
  vadOpen(config: NativeVadConfig): Promise<void> {
    return this.call('vadOpen', [config]);
  }
  vadProcess(samples: Float32Array): Promise<boolean> {
    return this.call('vadProcess', [samples]);
  }
  vadReset(): Promise<void> {
    return this.call('vadReset', []);
  }
  vadClose(): Promise<void> {
    return this.call('vadClose', []);
  }

  // ---- embeddings and rerank ----
  embed(texts: string[], options: NativeEmbedOptions): Promise<Float32Array[]> {
    return this.call('embed', [texts, options]);
  }
  rerank(query: string, documents: string[], topN?: number): Promise<NativeRanked[]> {
    return this.call('rerank', [query, documents, topN]);
  }

  // ---- diarization and segmentation ----
  diarize(
    samples: Float32Array,
    options: NativeDiarizationOptions
  ): Promise<NativeDiarization> {
    return this.call('diarize', [samples, options]);
  }
  segment(
    image: { data: Uint8Array; width: number; height: number; pixelFormat?: number },
    options: { includeDiagnosticImage?: boolean }
  ): Promise<NativeSegmentation> {
    return this.call('segment', [image, options]);
  }

  // ---- rag ----
  ragOpen(configBytes: Uint8Array): Promise<string> {
    return this.call('ragOpen', [configBytes]);
  }
  ragIngest(session: string, documentBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('ragIngest', [session, documentBytes]);
  }
  ragQuery(session: string, queryBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('ragQuery', [session, queryBytes]);
  }
  ragQueryStream(
    session: string,
    queryBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.call('ragQueryStream', [session, queryBytes], onEvent as (c: unknown) => void);
  }
  ragStats(session: string): Promise<Uint8Array> {
    return this.call('ragStats', [session]);
  }
  ragClear(session: string): Promise<Uint8Array> {
    return this.call('ragClear', [session]);
  }
  ragCancel(session: string): Promise<void> {
    return this.call('ragCancel', [session]);
  }
  ragClose(session: string): Promise<void> {
    return this.call('ragClose', [session]);
  }

  // ---- secure store ----
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
