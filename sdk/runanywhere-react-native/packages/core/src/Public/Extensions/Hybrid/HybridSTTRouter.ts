/**
 * HybridSTTRouter.ts
 *
 * THIN React Native binding over the commons STT hybrid router
 * (rac_stt_hybrid_router + its proto-byte ABI), reached through the Nitro
 * `RunAnywhereCore` hybrid object's `hybridSttRouter*` / `hybrid*` methods.
 * Per-request dispatch between an on-device (offline, sherpa) STT service and a
 * cloud (online, cloud) STT service.
 *
 * Division of labour — commons owns ALL routing: the filter phase, rank/sort,
 * confidence cascade, and primary->secondary fallback all live in
 * rac_stt_hybrid_router.cpp. NONE of that logic is reimplemented here. This
 * binding only:
 *   1. creates the router handle,
 *   2. creates the two STT services through the registry-routed creation path
 *      (hint "sherpa"/"cloud"; provider in the cloud config) and attaches
 *      them with their `HybridModelDescriptor` bytes,
 *   3. registers any custom-filter predicates (JS->native) and installs the
 *      `HybridRoutingPolicy` policy bytes,
 *   4. drives transcribe and decodes the `HybridSttTranscribeResponse`.
 *
 * Mirrors Swift `HybridSTTRouter` + Kotlin `RACRouter.SttRouter`. Lifetime: the
 * router does NOT own the underlying services. This class tracks each service
 * handle, clears the router slots before destroying the services (the
 * use-after-free guard called out in rac_stt_hybrid_router.h), unregisters its
 * custom filters, and tears everything down in `close()`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';
import {
  HybridModelDescriptor,
  HybridSttTranscribeRequest,
  HybridSttTranscribeResponse,
} from '@runanywhere/proto-ts/hybrid_router';
import {
  HybridBackendKind,
  pinnedEngineName,
  type HybridModel,
  type HybridTranscribeOptions,
  type HybridTranscribeResult,
} from './HybridModel';
import {
  encodeHybridRoutingPolicy,
  customFiltersOf,
  type HybridRoutingPolicy,
} from './HybridRoutingPolicy';
import { CloudSTT } from './CloudSTT';

const logger = new SDKLogger('Hybrid.STTRouter');

const RAC_SUCCESS = 0;

/** One attached service: the native handle plus the descriptor used to attach it. */
interface AttachedService {
  handle: number;
  model: HybridModel;
}

/**
 * A hybrid STT router pairing one offline + one online speech service.
 *
 * Usage:
 * ```typescript
 * await CloudSTT.register();
 * await CloudSTT.registerModel({ id: 'saaras', provider: 'sarvam',
 *   model: 'saaras:v2.5', apiKey: '…' });
 *
 * const router = await HybridSTTRouter.create();
 * await router.setPair(
 *   offlineSherpa('sherpa-onnx-whisper-tiny.en'),
 *   onlineCloud('saaras'),
 *   { hardFilters: [Filters.network()], cascade: Cascades.confidence(0.5),
 *     rank: HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST }
 * );
 * const result = await router.transcribe(audio, { audioFormat: 1 });
 * await router.close();
 * ```
 */
export class HybridSTTRouter {
  private handle: number;
  private offline: AttachedService | null = null;
  private online: AttachedService | null = null;
  private customFilterNames: string[] = [];

  private constructor(handle: number) {
    this.handle = handle;
  }

  /** Create the native router handle (`rac_stt_hybrid_router_create`). */
  static async create(): Promise<HybridSTTRouter> {
    if (!isNativeModuleAvailable()) {
      throw SDKException.nativeModuleUnavailable();
    }
    await ensureServicesReady();
    const handle = await requireNativeModule().hybridSttRouterCreate();
    if (!handle) {
      throw SDKException.componentNotReady('rac_stt_hybrid_router_create returned 0');
    }
    return new HybridSTTRouter(handle);
  }

  /**
   * Bind the offline + online models, install the policy, and register any
   * custom-filter predicates. Replaces any previous pairing.
   */
  async setPair(
    offline: HybridModel,
    online: HybridModel,
    policy: HybridRoutingPolicy = {}
  ): Promise<void> {
    this.ensureOpen();
    const native = requireNativeModule();

    // Build both services up-front so a failure on the online side doesn't
    // leave a half-attached router.
    const offlineHandle = await this.createService(offline);
    let onlineHandle: number;
    try {
      onlineHandle = await this.createService(online);
    } catch (error) {
      await native.hybridSttRouterDestroyService(offlineHandle);
      throw error;
    }

    // Detach + destroy any previously attached services before swapping in the
    // new pair (clear router slots first — header UAF note), and retire the
    // previous policy's custom-filter predicates.
    await this.clearAndDestroyServices();
    await this.unregisterCustomFilters();

    // Attach both sides with their descriptor bytes.
    const rcOff = await native.hybridSttRouterSetOfflineService(
      this.handle,
      offlineHandle,
      this.descriptorBytes(offline)
    );
    if (rcOff !== RAC_SUCCESS) {
      await native.hybridSttRouterDestroyService(offlineHandle);
      await native.hybridSttRouterDestroyService(onlineHandle);
      throw SDKException.componentNotReady(
        `hybridSttRouterSetOfflineService rc=${rcOff}`
      );
    }
    const rcOn = await native.hybridSttRouterSetOnlineService(
      this.handle,
      onlineHandle,
      this.descriptorBytes(online)
    );
    if (rcOn !== RAC_SUCCESS) {
      await native.hybridSttRouterSetOfflineService(this.handle, 0, this.emptyBytes());
      await native.hybridSttRouterDestroyService(offlineHandle);
      await native.hybridSttRouterDestroyService(onlineHandle);
      throw SDKException.componentNotReady(
        `hybridSttRouterSetOnlineService rc=${rcOn}`
      );
    }

    // Register each custom filter's predicate by NAME with the cross-SDK commons
    // callback table BEFORE installing the policy bytes, so the router can
    // resolve each name the first time it filters. Commons evaluates them —
    // this layer does NOT pre-filter candidates or toggle slots.
    const customs = customFiltersOf(policy);
    for (const custom of customs) {
      const rc = await native.hybridRegisterCustomFilter(
        custom.name,
        async (candidateModelId: string) =>
          Promise.resolve(custom.check(candidateModelId))
      );
      if (rc !== RAC_SUCCESS) {
        // Roll back: detach services + unregister the filters we just added.
        for (const c of customs) {
          if (c.name === custom.name) break;
          await native.hybridUnregisterCustomFilter(c.name);
        }
        await native.hybridSttRouterSetOfflineService(this.handle, 0, this.emptyBytes());
        await native.hybridSttRouterSetOnlineService(this.handle, 0, this.emptyBytes());
        await native.hybridSttRouterDestroyService(offlineHandle);
        await native.hybridSttRouterDestroyService(onlineHandle);
        throw SDKException.componentNotReady(
          `hybridRegisterCustomFilter('${custom.name}') rc=${rc}`
        );
      }
    }

    const rcPolicy = await native.hybridSttRouterSetPolicy(
      this.handle,
      encodeHybridRoutingPolicy(policy)
    );
    if (rcPolicy !== RAC_SUCCESS) {
      for (const c of customs) await native.hybridUnregisterCustomFilter(c.name);
      await native.hybridSttRouterSetOfflineService(this.handle, 0, this.emptyBytes());
      await native.hybridSttRouterSetOnlineService(this.handle, 0, this.emptyBytes());
      await native.hybridSttRouterDestroyService(offlineHandle);
      await native.hybridSttRouterDestroyService(onlineHandle);
      throw SDKException.componentNotReady(`hybridSttRouterSetPolicy rc=${rcPolicy}`);
    }

    this.offline = { handle: offlineHandle, model: offline };
    this.online = { handle: onlineHandle, model: online };
    this.customFilterNames = customs.map((c) => c.name);
  }

  /**
   * Run one transcribe request through the router. The router applies the
   * installed policy (filters -> rank -> invoke -> fallback) in commons and
   * returns the chosen backend's result plus the routing decision.
   *
   * @param audio   File-encoded audio (wav/mp3/flac/…) OR raw PCM bytes.
   * @param options Optional language / sampleRate / audioFormat hints.
   */
  async transcribe(
    audio: Uint8Array,
    options: HybridTranscribeOptions = {}
  ): Promise<HybridTranscribeResult> {
    this.ensureOpen();
    if (this.offline == null || this.online == null) {
      throw SDKException.componentNotReady('setPair() not called');
    }
    const native = requireNativeModule();

    const request = HybridSttTranscribeRequest.fromPartial({
      audioBytes: audio,
      context: {},
      options: {
        language: options.language ?? '',
        sampleRate: options.sampleRate ?? 0,
        audioFormat: options.audioFormat ?? 0,
      },
    });
    const responseBytes = await native.hybridSttRouterTranscribe(
      this.handle,
      encodeProtoMessage(request, HybridSttTranscribeRequest)
    );
    return this.decodeResponse(responseBytes);
  }

  /**
   * Best-effort cancel of an in-flight transcribe. No STT engine exposes a
   * cancel op today, so commons treats this as a no-op until one does.
   */
  async cancel(): Promise<void> {
    if (!this.handle) return;
    await requireNativeModule().hybridSttRouterCancel(this.handle);
  }

  /**
   * Detach + destroy both services, unregister custom filters, and destroy the
   * router handle. Idempotent.
   */
  async close(): Promise<void> {
    if (!this.handle) return;
    const native = requireNativeModule();
    await this.unregisterCustomFilters();
    await this.clearAndDestroyServices();
    await native.hybridSttRouterDestroy(this.handle);
    this.handle = 0;
  }

  // --- internals ------------------------------------------------------------

  private ensureOpen(): void {
    if (!this.handle) {
      throw SDKException.componentNotReady('HybridSTTRouter is closed');
    }
  }

  /**
   * Create one registry-routed STT service for `model`. cloud needs the
   * provider + api_key + model from the credential registry (resolved here via
   * CloudSTT.configJSON); sherpa resolves its model from the C model registry,
   * so it gets the model id with no extra config.
   */
  private async createService(model: HybridModel): Promise<number> {
    const native = requireNativeModule();
    const engineHint = pinnedEngineName(model.backend);
    const isCloud = model.backend === HybridBackendKind.HYBRID_BACKEND_CLOUD;
    const configJson = isCloud ? CloudSTT.configJSON(model.id) : '';
    const modelIdOrPath = isCloud ? '' : model.id;
    const handle = await native.hybridSttRouterCreateService(
      engineHint,
      modelIdOrPath,
      configJson
    );
    if (!handle) {
      throw SDKException.componentNotReady(
        `Failed to create '${engineHint}' STT service for model '${model.id}'. ` +
          'Register the backend first (ONNX.register() for sherpa, ' +
          'CloudSTT.register() for cloud).'
      );
    }
    return handle;
  }

  /** Encode a `HybridModelDescriptor` for the router setters. */
  private descriptorBytes(model: HybridModel): ArrayBuffer {
    const descriptor = HybridModelDescriptor.fromPartial({
      modelId: model.id,
      modelType: model.modelType,
      backend: model.backend,
      provider: model.provider,
    });
    return encodeProtoMessage(descriptor, HybridModelDescriptor);
  }

  private emptyBytes(): ArrayBuffer {
    return bytesToArrayBuffer(new Uint8Array(0));
  }

  /**
   * Clear both router slots, then destroy whatever services were attached.
   * Slot-clearing must precede service destruction (the router holds raw
   * pointers — see rac_stt_hybrid_router.h UAF note).
   */
  private async clearAndDestroyServices(): Promise<void> {
    const native = requireNativeModule();
    if (this.handle) {
      await native.hybridSttRouterSetOfflineService(this.handle, 0, this.emptyBytes());
      await native.hybridSttRouterSetOnlineService(this.handle, 0, this.emptyBytes());
    }
    const offline = this.offline;
    const online = this.online;
    this.offline = null;
    this.online = null;
    if (offline) await native.hybridSttRouterDestroyService(offline.handle);
    if (online) await native.hybridSttRouterDestroyService(online.handle);
  }

  /** Unregister every custom-filter predicate this router installed. Idempotent. */
  private async unregisterCustomFilters(): Promise<void> {
    const native = requireNativeModule();
    const names = this.customFilterNames;
    this.customFilterNames = [];
    for (const name of names) {
      await native.hybridUnregisterCustomFilter(name);
    }
  }

  /** Decode a `HybridSttTranscribeResponse`, raising the native rc as an exception. */
  private decodeResponse(buffer: ArrayBuffer): HybridTranscribeResult {
    const bytes = arrayBufferToBytes(buffer);
    if (bytes.byteLength === 0) {
      throw SDKException.generationFailedWith('Hybrid STT transcribe returned no response');
    }
    const message = HybridSttTranscribeResponse.decode(bytes);
    if (message.rc !== RAC_SUCCESS) {
      const reason = message.errorMsg || `Hybrid STT transcribe failed (rc=${message.rc})`;
      logger.warning(reason);
      throw SDKException.generationFailedWith(reason);
    }
    const routing = message.routing;
    return {
      text: message.text,
      detectedLanguage: message.detectedLanguage,
      routing: {
        chosenModelId: routing?.chosenModelId ?? '',
        wasFallback: routing?.wasFallback ?? false,
        attemptCount: routing?.attemptCount ?? 0,
        primaryErrorCode: routing?.primaryErrorCode ?? 0,
        primaryErrorMessage: routing?.primaryErrorMessage ?? '',
        confidence: routing?.confidence ?? Number.NaN,
        primaryConfidence: routing?.primaryConfidence ?? Number.NaN,
      },
    };
  }
}
