import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import {
  SdkInitEnvironment,
  SdkInitPhase1Request,
  SdkInitPhase2Request,
  SdkInitResult,
  type SdkInitResult as ProtoSdkInitResult,
} from '@runanywhere/proto-ts/sdk_init';
import { SDK_PLATFORM, SDK_VERSION } from '../Foundation/Version';
import { SDKLogger } from '../Foundation/SDKLogger';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

const logger = new SDKLogger('SdkInit');

const DEVICE_ID_KEY = 'runanywhere.deviceId';

/**
 * Drives the commons two-phase SDK init (auth handshake -> device registration
 * -> telemetry) through the commons Web Worker.
 *
 * All three entry points are C ABI proto functions with the shape
 * `rac_sdk_*_proto(const uint8_t* req, size_t len, rac_proto_buffer_t* out)`
 * except the retry path which is `rac_sdk_retry_http_proto(rac_proto_buffer_t* out)`.
 * They marshal as:
 *   - request envelope  -> `Arg.bytes(reqBytes)`   (expands to ptr + size)
 *   - out `SdkInitResult` -> `Arg.outProto()`        (expands to the out buffer ptr)
 *
 * The commons worker already registered the emscripten_fetch HTTP transport at
 * WASM load, so Phase 2's auth/device/telemetry HTTP runs from inside the worker.
 */
export class SdkInitAdapter {
  private phase1Done = false;
  private servicesReady = false;
  private httpSetupDone = false;

  constructor(private readonly client: WorkerProtoClient) {}

  get areServicesReady(): boolean {
    return this.servicesReady;
  }

  get hasCompletedHttpSetup(): boolean {
    return this.httpSetupDone;
  }

  /**
   * Phase 1 — synchronous core init. Encodes the only values commons cannot
   * derive itself (environment, credentials, device id, platform identity) and
   * hands them to `rac_sdk_init_phase1_proto`. Returns true on success.
   */
  async completePhase1(config: {
    environment: SDKEnvironment;
    apiKey?: string;
    baseUrl?: string;
  }): Promise<boolean> {
    if (this.phase1Done) return true;

    const bytes = SdkInitPhase1Request.encode({
      environment: mapSdkInitEnvironment(config.environment),
      apiKey: config.apiKey ?? '',
      baseUrl: config.baseUrl ?? '',
      deviceId: ensureDeviceId(),
      platform: SDK_PLATFORM,
      sdkVersion: SDK_VERSION,
    }).finish();

    const result = await this.client.callProto(
      'rac_sdk_init_phase1_proto',
      [Arg.bytes(bytes), Arg.outProto()],
      SdkInitResult,
    );

    if (!isSuccess(result, 'SDK Phase 1')) return false;
    this.phase1Done = true;
    return true;
  }

  /**
   * Phase 2 — async services init (auth, device registration, telemetry flush,
   * downloaded-model discovery). Best-effort: never throws; offline just leaves
   * `httpSetupDone` false so a later retry can complete it.
   */
  async completePhase2(config: { environment: SDKEnvironment }): Promise<void> {
    if (this.servicesReady) return;
    if (!this.phase1Done) return;

    const bytes = SdkInitPhase2Request.encode({
      buildToken: '',
      forceRefreshAssignments: false,
      flushTelemetry: true,
      discoverDownloadedModels: true,
      rescanLocalModels: true,
    }).finish();

    const result = await this.client.callProto(
      'rac_sdk_init_phase2_proto',
      [Arg.bytes(bytes), Arg.outProto()],
      SdkInitResult,
    );

    if (!isSuccess(result, 'SDK Phase 2')) return;

    this.servicesReady = true;
    this.httpSetupDone = result?.hasCompletedHttpSetup ?? result?.httpConfigured ?? false;
    const linked = result?.linkedModelsCount ?? 0;
    if (linked > 0) logger.info(`Phase 2 linked ${linked} downloaded models`);
    if (this.httpSetupDone) {
      logger.debug('Services initialization complete (Phase 2)');
    } else {
      logger.debug('Services initialization complete (Phase 2, HTTP/auth deferred — will retry)');
    }

    void config;
  }

  /**
   * Retry HTTP/auth after an offline Phase 2. Commons owns the retry
   * orchestration (auth, device registration, telemetry flush). Returns true
   * once HTTP setup is latched complete.
   */
  async retryHttp(): Promise<boolean> {
    if (this.httpSetupDone) return true;

    const result = await this.client.callProto(
      'rac_sdk_retry_http_proto',
      [Arg.outProto()],
      SdkInitResult,
    );

    if (!isSuccess(result, 'SDK HTTP retry')) return false;
    this.httpSetupDone = result?.hasCompletedHttpSetup ?? result?.httpConfigured ?? false;
    if (this.httpSetupDone) logger.info('HTTP/Auth setup succeeded on retry');
    return this.httpSetupDone;
  }

  /** True when commons holds a non-expired access token. */
  async isAuthenticated(): Promise<boolean> {
    try {
      return (await this.client.callRc('rac_auth_is_authenticated', [])) !== 0;
    } catch {
      return false;
    }
  }

  /** True when the device has been registered with the backend. */
  async isDeviceRegistered(): Promise<boolean> {
    try {
      return (await this.client.callRc('rac_state_is_device_registered', [])) !== 0;
    } catch {
      return false;
    }
  }
}

function isSuccess(result: ProtoSdkInitResult | null, phase: string): boolean {
  if (!result) {
    logger.warning(`${phase} returned no sdk-init result.`);
    return false;
  }
  if (!result.success) {
    const detail = result.error?.message || result.warning || 'unknown error';
    logger.warning(`${phase} failed: ${detail}`);
    return false;
  }
  if (result.warning) logger.warning(`${phase} warning: ${result.warning}`);
  return true;
}

/**
 * Map the model_types `SDKEnvironment` enum onto the DISTINCT sdk_init
 * `SdkInitEnvironment` enum. Both share the 0/1/2 development/staging/production
 * wire layout but are separate generated types, so the values must be bridged.
 */
function mapSdkInitEnvironment(env: SDKEnvironment): SdkInitEnvironment {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_PRODUCTION;
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_STAGING;
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
    default:
      return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_DEVELOPMENT;
  }
}

/**
 * Stable device id, persisted in localStorage so it survives reloads. Mirrors
 * old web's fallback path (`rac_state_get_persistent_device_id` is not exported
 * by the web-next commons artifact, so the TS-persisted UUID is authoritative).
 */
export function ensureDeviceId(): string {
  try {
    if (typeof localStorage !== 'undefined') {
      const stored = localStorage.getItem(DEVICE_ID_KEY);
      if (stored) return stored;
    }
  } catch {
    /* ignore */
  }
  const id = generateUuid();
  try {
    if (typeof localStorage !== 'undefined') localStorage.setItem(DEVICE_ID_KEY, id);
  } catch {
    /* ignore */
  }
  return id;
}

function generateUuid(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}
