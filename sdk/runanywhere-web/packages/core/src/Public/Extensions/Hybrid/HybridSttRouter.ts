/**
 * HybridSttRouter.ts
 *
 * THIN Web binding over the commons STT hybrid router (rac_stt_hybrid_router +
 * its proto-byte ABI). Per-request dispatch between an on-device (offline,
 * sherpa) STT service and a cloud (online, cloud) STT service.
 *
 * Mirrors Swift's `HybridSTTRouter` and Kotlin's `RACRouter.SttRouter`. As in
 * both, commons owns ALL routing — filter phase, rank/sort, confidence
 * cascade, and primary→secondary fallback all live in
 * rac_stt_hybrid_router.cpp; NONE of that logic is reimplemented here. This
 * binding only:
 *   1. creates the router handle,
 *   2. creates the two STT services through the registry-routed creation path
 *      (engine hint "sherpa" / "cloud") and attaches them with their
 *      proto descriptors,
 *   3. registers any custom-filter predicates + installs the policy bytes,
 *   4. drives the router's transcribe and decodes the response.
 *
 * The router does NOT own the underlying services; this class keeps each
 * service pointer for the router's lifetime, clears the router slots before
 * destroying the services (avoiding the use-after-free called out in
 * rac_stt_hybrid_router.h), and tears everything down in `close()`.
 *
 * The WASM single-threaded model makes the actor/lock machinery the Swift and
 * Kotlin bindings need unnecessary here — there is no concurrent transcribe.
 *
 * NOTE: requires the hybrid-router proto-byte exports + cloud engine, which
 * the current Web WASM targets do NOT ship. See HybridWasmModule.ts BUILD
 * DELTA. Until that lands, construction succeeds but `setPair`/`transcribe`
 * raise a clear `backendNotAvailable` (never faked behaviour).
 */

import { SDKException } from '../../../Foundation/SDKException';
import { SDKLogger } from '../../../Foundation/SDKLogger';
import { RAC_OK } from '../../../Foundation/RACErrors';
import {
  getModuleForCapability,
} from '../../../runtime/EmscriptenModule';
import { ProtoWasmBridge } from '../../../runtime/ProtoWasm';
import {
  customFiltersOf,
  decodeTranscribeResponse,
  encodeModelDescriptor,
  encodeRoutingPolicy,
  encodeTranscribeRequest,
  HybridBackendKind,
  type HybridModelSpec,
  type HybridRoutingPolicySpec,
  type HybridTranscribeOptions,
  type HybridTranscribeResult,
} from './HybridTypes';
import {
  hasHybridRouterExports,
  hybridRouterRequirementMessage,
  missingHybridRouterExports,
  type HybridWasmModule,
} from './HybridWasmModule';
import { CloudSTT } from './CloudSTT';
import {
  registerHybridCustomFilter,
  unregisterHybridCustomFilter,
} from './HybridDeviceState';

const logger = new SDKLogger('Hybrid.STTRouter');

/** One attached STT service: the opaque `rac_stt_service_t*` the router holds
 * plus the descriptor bytes it was attached with. */
interface AttachedService {
  servicePtr: number;
}

/** Map a backend kind to the engine hint `rac_plugin_route` pins on. */
function pinnedEngineName(backend: HybridBackendKind): string {
  switch (backend) {
    case HybridBackendKind.HYBRID_BACKEND_SHERPA:
      return 'sherpa';
    case HybridBackendKind.HYBRID_BACKEND_CLOUD:
      return 'cloud';
    case HybridBackendKind.HYBRID_BACKEND_LLAMACPP:
      return 'llamacpp';
    case HybridBackendKind.HYBRID_BACKEND_OPENROUTER:
      return 'openrouter';
    default:
      return '';
  }
}

/**
 * A hybrid STT router pairing one offline + one online speech service.
 *
 * Usage:
 * ```ts
 * CloudSTT.registerBackend();
 * CloudSTT.register({ id: 'saaras', provider: 'sarvam', model: 'saaras:v2.5', apiKey: '…' });
 * setHybridDeviceStateProvider(browserDeviceStateProvider());  // optional
 *
 * const router = await HybridSttRouter.create();
 * router.setPair(
 *   offlineSherpa('sherpa-onnx-whisper-tiny.en'),
 *   onlineCloud('saaras'),
 *   { hardFilters: [networkFilter()], cascade: confidenceCascade(0.5),
 *     rank: HybridRank.HYBRID_RANK_PREFER_LOCAL_FIRST },
 * );
 * const result = router.transcribe(audioBytes, { audioFormat: 1 });
 * router.close();
 * ```
 */
export class HybridSttRouter {
  private handle = 0;
  private offline: AttachedService | null = null;
  private online: AttachedService | null = null;
  /** Names of custom-filter predicates registered for the current policy, so
   * `close()`/re-pair can unregister exactly those. */
  private customFilterNames: string[] = [];

  private constructor(
    private readonly module: HybridWasmModule,
    handle: number,
  ) {
    this.handle = handle;
  }

  /** True iff the loaded WASM exports the hybrid-router ABI. */
  static isSupported(): boolean {
    return hasHybridRouterExports(HybridSttRouter.resolveModule());
  }

  /** Allocate the native router handle. Throws `backendNotAvailable` when the
   * WASM build lacks the hybrid-router exports (see HybridWasmModule.ts). */
  static async create(): Promise<HybridSttRouter> {
    const module = HybridSttRouter.resolveModule();
    const missing = missingHybridRouterExports(module);
    if (!module || missing.length > 0) {
      throw SDKException.backendNotAvailable(
        'hybrid.stt',
        hybridRouterRequirementMessage(missing),
      );
    }
    const bridge = new ProtoWasmBridge(module, logger);
    const outHandlePtr = bridge.allocOutPtr();
    if (!outHandlePtr) {
      throw SDKException.componentNotReady('hybrid.stt', 'failed to allocate router handle slot');
    }
    try {
      const rc = module._rac_stt_hybrid_router_create!(outHandlePtr);
      const handle = bridge.readU32(outHandlePtr);
      if (rc !== RAC_OK || !handle) {
        throw SDKException.componentNotReady(
          'hybrid.stt',
          `rac_stt_hybrid_router_create failed (rc=${rc})`,
        );
      }
      return new HybridSttRouter(module, handle);
    } finally {
      bridge.free(outHandlePtr);
    }
  }

  private static resolveModule(): HybridWasmModule | null {
    // The router lives wherever the STT engines are linked (the ONNX-sherpa
    // target owns both the offline sherpa side and — per the build delta — the
    // cloud online side); fall back to commons for inspection.
    return (getModuleForCapability('stt') ??
      getModuleForCapability('commons')) as HybridWasmModule | null;
  }

  // ── Pair + policy ─────────────────────────────────────────────────────────

  /**
   * Bind the offline + online models, install the policy, and register any
   * custom-filter predicates. Replaces any previous pairing. The order of the
   * two models is fixed: `offline` is bound to the offline slot, `online` to
   * the online slot.
   */
  setPair(
    offline: HybridModelSpec,
    online: HybridModelSpec,
    policy: HybridRoutingPolicySpec = {},
  ): void {
    this.ensureOpen();
    const mod = this.module;
    const bridge = new ProtoWasmBridge(mod, logger);

    // Build both services up-front so a failure on the online side doesn't
    // leave a half-attached router.
    const offlineService = this.createService(offline);
    let onlineService: AttachedService;
    try {
      onlineService = this.createService(online);
    } catch (error) {
      this.destroyService(offlineService);
      throw error;
    }

    // Detach + destroy any previously attached services (clear slots first —
    // header UAF note) and retire the previous policy's custom filters.
    this.clearAndDestroyServices();
    this.retireCustomFilters();

    const offDescriptor = encodeModelDescriptor(offline);
    const onDescriptor = encodeModelDescriptor(online);

    const rcOff = bridge.withHeapBytes(offDescriptor, (ptr, size) =>
      mod._rac_stt_hybrid_router_set_offline_service_proto!(
        this.handle, offlineService.servicePtr, ptr, size,
      ),
    );
    if (rcOff !== RAC_OK) {
      this.destroyService(offlineService);
      this.destroyService(onlineService);
      throw SDKException.componentNotReady('hybrid.stt', `set_offline_service_proto failed (rc=${rcOff})`);
    }

    const rcOn = bridge.withHeapBytes(onDescriptor, (ptr, size) =>
      mod._rac_stt_hybrid_router_set_online_service_proto!(
        this.handle, onlineService.servicePtr, ptr, size,
      ),
    );
    if (rcOn !== RAC_OK) {
      mod._rac_stt_hybrid_router_set_offline_service_proto!(this.handle, 0, 0, 0);
      this.destroyService(offlineService);
      this.destroyService(onlineService);
      throw SDKException.componentNotReady('hybrid.stt', `set_online_service_proto failed (rc=${rcOn})`);
    }

    // Register custom-filter predicates with commons BEFORE installing the
    // policy bytes so the router can resolve each name during filtering. The
    // router owns the eval — TS only supplies the named predicate.
    const customs = customFiltersOf(policy);
    for (const filter of customs) {
      registerHybridCustomFilter(filter.name, filter.check);
    }
    const customNames = customs.map((f) => f.name);

    const policyBytes = encodeRoutingPolicy(policy);
    const rcPolicy = bridge.withHeapBytes(policyBytes, (ptr, size) =>
      mod._rac_stt_hybrid_router_set_policy_proto!(this.handle, ptr, size),
    );
    if (rcPolicy !== RAC_OK) {
      for (const name of customNames) unregisterHybridCustomFilter(name);
      mod._rac_stt_hybrid_router_set_offline_service_proto!(this.handle, 0, 0, 0);
      mod._rac_stt_hybrid_router_set_online_service_proto!(this.handle, 0, 0, 0);
      this.destroyService(offlineService);
      this.destroyService(onlineService);
      throw SDKException.componentNotReady('hybrid.stt', `set_policy_proto failed (rc=${rcPolicy})`);
    }

    this.offline = offlineService;
    this.online = onlineService;
    this.customFilterNames = customNames;
  }

  // ── Transcribe ────────────────────────────────────────────────────────────

  /**
   * Run one transcribe request through the router. The router applies the
   * installed policy (filters → rank → invoke → fallback) in commons and
   * returns the chosen backend's result plus the routing decision. Raises the
   * native rc as an `SDKException` when non-zero.
   */
  transcribe(
    audio: Uint8Array,
    options: HybridTranscribeOptions = {},
  ): HybridTranscribeResult {
    this.ensureOpen();
    if (!this.offline || !this.online) {
      throw SDKException.componentNotReady('hybrid.stt', 'setPair() must be called before transcribe()');
    }
    const mod = this.module;
    const bridge = new ProtoWasmBridge(mod, logger);

    const requestBytes = encodeTranscribeRequest(audio, options);
    const outBytesPtr = bridge.allocOutPtr();
    const outSizePtr = bridge.allocOutPtr();
    if (!outBytesPtr || !outSizePtr) {
      if (outBytesPtr) bridge.free(outBytesPtr);
      if (outSizePtr) bridge.free(outSizePtr);
      throw SDKException.componentNotReady('hybrid.stt', 'failed to allocate transcribe out-pointers');
    }

    let responsePtr = 0;
    try {
      const rc = bridge.withHeapBytes(requestBytes, (reqPtr, reqSize) =>
        mod._rac_stt_hybrid_router_transcribe_proto!(
          this.handle, reqPtr, reqSize, outBytesPtr, outSizePtr,
        ),
      );
      responsePtr = bridge.readU32(outBytesPtr);
      const responseSize = bridge.readU32(outSizePtr);
      if (rc !== RAC_OK || !responsePtr || responseSize === 0) {
        throw SDKException.componentNotReady(
          'hybrid.stt',
          `rac_stt_hybrid_router_transcribe_proto failed (rc=${rc})`,
        );
      }
      const responseBytes = mod.HEAPU8.slice(responsePtr, responsePtr + responseSize);
      const decoded = decodeTranscribeResponse(responseBytes);
      if (decoded.rc !== 0) {
        const message = decoded.errorMessage || `Hybrid STT transcribe failed (rc=${decoded.rc})`;
        throw SDKException.componentNotReady('hybrid.stt', message);
      }
      return decoded.result;
    } finally {
      if (responsePtr) mod._rac_stt_hybrid_router_proto_buffer_free!(responsePtr);
      bridge.free(outBytesPtr);
      bridge.free(outSizePtr);
    }
  }

  /** Cancel an in-flight transcribe, if any. Best-effort: no STT engine
   * exposes a cancel op today, so commons treats this as a no-op until one
   * does (see rac_stt_hybrid_router_cancel). */
  cancel(): void {
    if (!this.handle) return;
    this.module._rac_stt_hybrid_router_cancel?.(this.handle);
  }

  // ── Teardown ──────────────────────────────────────────────────────────────

  /** Detach + destroy both services, unregister custom filters, and destroy
   * the router handle. Idempotent. */
  close(): void {
    if (this.handle) {
      this.clearAndDestroyServices();
      this.module._rac_stt_hybrid_router_destroy!(this.handle);
      this.handle = 0;
    }
    this.retireCustomFilters();
  }

  // ── Registry-routed service creation ──────────────────────────────────────

  /**
   * Create an STT service for `model` via the registry route (engine hint
   * "sherpa"/"cloud"), returning the opaque `rac_stt_service_t*` the router
   * holds. cloud needs provider + api_key + model from the credential
   * registry; sherpa resolves its model from the C model registry, so it gets
   * the model id with no extra config — exactly the Swift/Kotlin split.
   */
  private createService(model: HybridModelSpec): AttachedService {
    const mod = this.module;
    const engineName = pinnedEngineName(model.backend);

    // cloud config JSON (provider/api_key/model/...); sherpa = no config.
    const configJSON = model.backend === HybridBackendKind.HYBRID_BACKEND_CLOUD
      ? CloudSTT.configJSON(model.id)
      : null;
    // cloud takes everything via config_json; no model path. sherpa resolves
    // its model from the registry by id.
    const modelIdOrPath = model.backend === HybridBackendKind.HYBRID_BACKEND_CLOUD ? '' : model.id;

    const enginePtr = allocCString(mod, engineName);
    const modelPtr = allocCString(mod, modelIdOrPath);
    const configPtr = configJSON !== null ? allocCString(mod, configJSON) : 0;
    try {
      const servicePtr = mod._rac_stt_hybrid_router_create_service!(enginePtr, modelPtr, configPtr);
      if (!servicePtr) {
        throw SDKException.backendNotAvailable(
          'hybrid.stt',
          `No '${engineName}' STT plugin registered, or create failed for model ` +
            `'${model.id}'. Register the backend first ` +
            `(load the ONNX/sherpa backend for sherpa; CloudSTT.registerBackend() for cloud).`,
        );
      }
      return { servicePtr };
    } finally {
      mod._free?.(enginePtr);
      mod._free?.(modelPtr);
      if (configPtr) mod._free?.(configPtr);
    }
  }

  /** Clear both router slots, then destroy whatever services were attached.
   * Slot-clearing must precede service destruction (router holds raw
   * pointers — see rac_stt_hybrid_router.h UAF note). */
  private clearAndDestroyServices(): void {
    const mod = this.module;
    if (this.handle) {
      mod._rac_stt_hybrid_router_set_offline_service_proto?.(this.handle, 0, 0, 0);
      mod._rac_stt_hybrid_router_set_online_service_proto?.(this.handle, 0, 0, 0);
    }
    if (this.offline) {
      this.destroyService(this.offline);
      this.offline = null;
    }
    if (this.online) {
      this.destroyService(this.online);
      this.online = null;
    }
  }

  private destroyService(service: AttachedService): void {
    this.module._rac_stt_hybrid_router_destroy_service?.(service.servicePtr);
  }

  private retireCustomFilters(): void {
    for (const name of this.customFilterNames) unregisterHybridCustomFilter(name);
    this.customFilterNames = [];
  }

  private ensureOpen(): void {
    if (!this.handle) {
      throw SDKException.componentNotReady('hybrid.stt', 'HybridSttRouter is closed');
    }
  }
}

function allocCString(mod: HybridWasmModule, value: string): number {
  const len = mod.lengthBytesUTF8!(value) + 1;
  const ptr = mod._malloc!(len);
  mod.stringToUTF8!(value, ptr, len);
  return ptr;
}
