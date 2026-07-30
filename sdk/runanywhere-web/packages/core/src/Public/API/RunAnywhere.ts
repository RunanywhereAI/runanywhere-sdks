/**
 * The RunAnywhere Web SDK public API.
 *
 * One namespace per capability, one verb per action, and one `initialize` call.
 * Everything under `Public/Extensions` and `Public/SDKCore.ts` is internal.
 */

import { EventCategory } from '@runanywhere/proto-ts/component_types';
import { SDKEnvironment, ModelCategory } from '@runanywhere/proto-ts/model_types';
import { EventBus } from '../../Foundation/EventBus.js';
import { Runtime, type RuntimeAccelerationMode } from '../../Foundation/RuntimeConfig.js';
import { SDKCore } from '../SDKCore.js';
import { solutions } from '../Extensions/RunAnywhere+Solutions.js';
import { setHfToken } from '../Extensions/RunAnywhere+HuggingFace.js';
import { AudioInput, ImageInput, RagDocument } from './Inputs.js';
import type { SdkEvent } from './Events.js';
import { llm } from './Namespaces/llm.js';
import { vlm } from './Namespaces/vlm.js';
import { stt } from './Namespaces/stt.js';
import { tts } from './Namespaces/tts.js';
import { vad } from './Namespaces/vad.js';
import { embeddings } from './Namespaces/embeddings.js';
import { rerank } from './Namespaces/rerank.js';
import { images } from './Namespaces/images.js';
import { diarization } from './Namespaces/diarization.js';
import { segmentation } from './Namespaces/segmentation.js';
import { voice } from './Namespaces/voice.js';
import { rag } from './Namespaces/rag.js';
import { models } from './Namespaces/models.js';
import { lora } from './Namespaces/lora.js';

/** Which control plane the SDK talks to. */
export type Environment = 'production' | 'development';

/** Arguments of the single [RunAnywhere.initialize] call. */
export interface InitializeOptions {
  /** Unset runs in keyless local mode. */
  apiKey?: string;
  /** Unset uses the default control plane for the environment. */
  baseUrl?: string;
  environment?: Environment;
  /** Reverse-DNS identifier reported with telemetry. */
  appIdentifier?: string;
  appName?: string;
  appVersion?: string;
}

const ENVIRONMENTS: Record<Environment, SDKEnvironment> = {
  production: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
  development: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
};

/** Translate an internal event-bus envelope into the public breadcrumb grammar. */
function toSdkEvent(type: string, data: unknown): SdkEvent | null {
  const payload = (data ?? {}) as Record<string, unknown>;
  switch (type) {
    case 'sdk.initialized':
      return { type: 'ready' };
    case 'model.loaded':
      return {
        type: 'modelLoaded',
        id: String(payload.modelId ?? payload.id ?? ''),
        category: Number(payload.category ?? ModelCategory.MODEL_CATEGORY_UNSPECIFIED),
      };
    case 'model.unloaded':
      return { type: 'modelUnloaded', id: String(payload.modelId ?? payload.id ?? '') };
    case 'sdk.initializationFailed':
    case 'model.loadFailed':
      return {
        type: 'error',
        message: String(payload.error ?? payload.message ?? 'Unknown SDK error'),
        recoverable: type !== 'sdk.initializationFailed',
      };
    default:
      return null;
  }
}

/** Lifecycle, download, and error breadcrumbs of the whole SDK. */
function sdkEvents(): AsyncIterable<SdkEvent> {
  return {
    [Symbol.asyncIterator](): AsyncIterator<SdkEvent> {
      const pending: SdkEvent[] = [];
      let waiter: ((result: IteratorResult<SdkEvent>) => void) | null = null;
      const unsubscribe = EventBus.shared.onAny((envelope) => {
        const event = toSdkEvent(envelope.type, envelope.data);
        if (!event) return;
        if (waiter) {
          const resolve = waiter;
          waiter = null;
          resolve({ value: event, done: false });
          return;
        }
        pending.push(event);
      });
      return {
        next(): Promise<IteratorResult<SdkEvent>> {
          const next = pending.shift();
          if (next) return Promise.resolve({ value: next, done: false });
          return new Promise((resolve) => { waiter = resolve; });
        },
        return(): Promise<IteratorResult<SdkEvent>> {
          unsubscribe();
          waiter?.({ value: undefined, done: true });
          waiter = null;
          return Promise.resolve({ value: undefined, done: true });
        },
      };
    },
  };
}

/**
 * Browser-only persistent-storage control. Not part of the cross-SDK spec: the
 * browser is the only platform where the host must ask the user for a
 * persistent directory before large models can be kept across reloads.
 */
const storage = {
  /** Whether the File System Access API can grant a real directory. */
  get isSupported(): boolean {
    return SDKCore.storage.isLocalStorageSupported;
  },
  /** Whether a granted directory is currently writable. */
  get isReady(): boolean {
    return SDKCore.storage.isLocalStorageReady;
  },
  /** Name of the granted directory, or `null` when running on OPFS. */
  get directoryName(): string | null {
    return SDKCore.storage.localStorageDirectoryName;
  },
  /** Which persistence layer downloads land in right now. */
  get backend(): 'fsAccess' | 'opfs' | 'memory' {
    return SDKCore.storage.backend;
  },
  /** Ask the user to grant a directory. Requires a user gesture. */
  chooseDirectory(): Promise<boolean> {
    return SDKCore.storage.chooseLocalStorageDirectory();
  },
  /** Re-acquire a previously granted directory after a reload. */
  restore(): Promise<boolean> {
    return SDKCore.storage.restoreLocalStorage();
  },
  /** Re-prompt for a stored directory whose permission lapsed. */
  requestAccess(): Promise<boolean> {
    return SDKCore.storage.requestLocalStorageAccess();
  },
  /** Reconcile the catalog against the bytes actually on disk. */
  refresh(): Promise<number> {
    return SDKCore.hydrateModelRegistry();
  },
  /** Clear the SDK's scratch directories. */
  async clearCaches(): Promise<void> {
    await SDKCore.clearCache();
    await SDKCore.cleanTempFiles();
  },
};

/**
 * Browser-only acceleration control. Not part of the cross-SDK spec: on Web the
 * execution mode selects an entirely different WASM artifact, so it is a
 * runtime switch rather than a per-load flag.
 */
const runtime = {
  /** Acceleration the SDK will prefer for the next model load. */
  get preferred(): RuntimeAccelerationMode {
    return Runtime.preferred;
  },
  /** Acceleration actually in use, or `null` before a backend registers. */
  get active(): 'cpu' | 'webgpu' | null {
    return Runtime.active;
  },
  /** Where inference runs, and why it was downgraded when it was. */
  get execution(): { context: 'main' | 'worker'; degradedReason: string | null } {
    return { context: Runtime.executionContext, degradedReason: Runtime.degradedReason };
  },
  /** Acceleration and threading of the speech backends. */
  get speech(): ReturnType<() => typeof Runtime.speech> {
    return Runtime.speech;
  },
  /** Per-modality backend, status, and acceleration. */
  get modalities(): typeof Runtime.modalities {
    return Runtime.modalities;
  },
  /** Switch acceleration, reloading the affected WASM artifact. */
  async setAcceleration(mode: RuntimeAccelerationMode): Promise<void> {
    if (mode === 'auto') {
      Runtime.preferred = 'auto';
      return;
    }
    await Runtime.setAcceleration(mode);
  },
};

/** The RunAnywhere on-device AI SDK. */
export const RunAnywhere = {
  /**
   * Bring the SDK up: platform adapters, native load, auth, device
   * registration, model catalog, and telemetry.
   *
   * Network work continues in the background and retries; the call returns as
   * soon as local inference is usable. There is no second phase.
   *
   * @throws SDKException when the browser lacks a required capability or the
   *   commons WASM cannot load.
   */
  async initialize(options: InitializeOptions = {}): Promise<void> {
    await SDKCore.initialize({
      apiKey: options.apiKey,
      baseURL: options.baseUrl,
      environment: ENVIRONMENTS[options.environment ?? 'production'],
      appIdentifier: options.appIdentifier,
      appName: options.appName,
      appVersion: options.appVersion,
    });
  },

  /** Tear everything down: unload models, close sessions, clear state. */
  reset(): Promise<void> {
    return SDKCore.reset();
  },

  /** Whether local inference is usable. */
  get isReady(): boolean {
    return SDKCore.isInitialized;
  },

  /** SDK version. */
  get version(): string {
    return SDKCore.version;
  },

  /** Stable per-browser device identifier. */
  get deviceId(): string {
    return SDKCore.deviceId;
  },

  /** Lifecycle, download, and error breadcrumbs. */
  get events(): AsyncIterable<SdkEvent> {
    return sdkEvents();
  },

  llm,
  vlm,
  stt,
  tts,
  vad,
  embeddings,
  rerank,
  images,
  diarization,
  segmentation,
  voice,
  rag,
  models,
  lora,

  /** Audio payload constructors. */
  AudioInput,
  /** Image payload constructors. */
  ImageInput,
  /** RAG document constructors. */
  RagDocument,

  storage,
  runtime,

  /**
   * Prebuilt multi-step pipelines. Not part of the cross-SDK v3 spec; retained
   * because the Web SDK ships the Solutions catalog.
   */
  solutions,

  /** Set the Hugging Face token used for gated downloads, or clear it with `null`. */
  setHuggingFaceToken: setHfToken,
};

export { EventCategory };
