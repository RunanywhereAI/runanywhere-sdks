import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import { EventBus } from '../Foundation/EventBus';
import { Logging, SDKLogger } from '../Foundation/SDKLogger';
import { installSDKEventTransport } from '../Adapters/SDKEventStreamAdapter';
import { SdkInitAdapter, ensureDeviceId } from '../Adapters/SdkInitAdapter';
import { SDK_PLATFORM, SDK_VERSION } from '../Foundation/Version';
import { clientFor, registerHost, unregisterHost } from '../runtime/HostRegistry';
import { WasmWorkerHost } from '../runtime/WasmWorkerHost';
import type { TelemetryInit } from '../runtime/TelemetryBridge';

const logger = new SDKLogger('RunAnywhere');

/** Short device label for telemetry (backend caps `device` at 100 chars). */
function webDeviceLabel(): string {
  if (typeof navigator === 'undefined') return 'web';
  const platform = navigator.platform || '';
  return (platform ? `Web (${platform})` : 'web').slice(0, 100);
}

/** Map the proto SDKEnvironment onto the rac_environment_t integer (0/1/2). */
function racEnvironmentInt(env: SDKEnvironment): number {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return 2;
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return 1;
    default:
      return 0;
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function errMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

export interface InitializeConfig {
  apiKey?: string;
  environment?: SDKEnvironment;
  baseUrl?: string;
  commonsWasmUrl?: string;
}

export class RunAnywhereSDK {
  private _initialized = false;
  private _environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
  private commonsHost: WasmWorkerHost | null = null;
  private sdkInit: SdkInitAdapter | null = null;

  get isInitialized(): boolean {
    return this._initialized;
  }

  get environment(): SDKEnvironment {
    return this._environment;
  }

  /** True once Phase 2 (auth/device/telemetry) has completed. */
  get areServicesReady(): boolean {
    return this.sdkInit?.areServicesReady ?? false;
  }

  /** Commons-worker telemetry-manager pointer (0 if telemetry is not wired).
   * Used by SDK-side telemetry emitters (e.g. LLM generation) to track events
   * on the manager via rac_telemetry_manager_track_proto. */
  get telemetryManagerPtr(): number {
    return this.commonsHost?.telemetryManagerPtr ?? 0;
  }

  async initialize(config: InitializeConfig = {}): Promise<void> {
    if (this._initialized) return;

    this._environment = config.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    Logging.applyEnvironmentConfiguration(this._environment);

    const wasmJsUrl = config.commonsWasmUrl ?? new URL('../../wasm/racommons.js', import.meta.url).href;
    // Telemetry is commons-owned but needs a platform HTTP delivery + event sink
    // wired in the worker (mirrors iOS CppBridge.Telemetry / Android JNI). Supply
    // the values commons cannot derive; the worker creates the manager, attaches
    // the fetch-based HTTP callback, and registers it as the event router sink.
    const telemetry: TelemetryInit = {
      environment: racEnvironmentInt(this._environment),
      deviceId: ensureDeviceId(),
      platform: SDK_PLATFORM,
      version: SDK_VERSION,
      // Telemetry `device` is capped at 100 chars backend-side; the full UA
      // (120-160+ chars) trips 422 string_too_long. navigator.platform is a
      // short, meaningful label (e.g. "Linux x86_64", "MacIntel", "Win32").
      deviceModel: webDeviceLabel(),
      osVersion: '',
      baseUrl: config.baseUrl ?? '',
      apiKey: config.apiKey ?? '',
    };
    const host = new WasmWorkerHost(
      () => new Worker(new URL('../worker.js', import.meta.url), { type: 'module' }),
      { moduleId: 'commons', wasmJsUrl, telemetry },
    );
    await host.ensureReady();
    this.commonsHost = host;
    registerHost(['commons'], host);

    installSDKEventTransport();
    EventBus.shared.start();

    this._initialized = true;
    logger.info('RunAnywhere initialized');

    // Auth / device-registration / telemetry are commons-owned. Phase 1
    // (synchronous, no network) is awaited so credentials + environment are
    // resident before any API call. Phase 2 (auth handshake, device
    // registration, telemetry flush) is best-effort and backgrounded so
    // initialize() resolves without blocking on the network — the engine must
    // still boot offline. Failures are logged, never thrown out of initialize.
    const commonsClient = clientFor('commons');
    if (commonsClient) {
      const sdkInit = new SdkInitAdapter(commonsClient);
      this.sdkInit = sdkInit;
      try {
        await sdkInit.completePhase1({
          environment: this._environment,
          apiKey: config.apiKey,
          baseUrl: config.baseUrl,
        });
      } catch (err) {
        logger.warning(`SDK Phase 1 failed (non-fatal): ${errMessage(err)}`);
      }
      void this.runServicesInitialization(sdkInit).catch((err) => {
        logger.warning(`SDK Phase 2 failed (non-fatal): ${errMessage(err)}`);
      });
    } else {
      logger.warning('commons worker client unavailable; SDK auth/telemetry init skipped');
    }
  }

  /**
   * Phase 2 + a bounded retry-http poll loop. Kept off the critical path:
   * telemetry is best-effort. Commons drives the actual auth/device/telemetry
   * HTTP through the worker's emscripten_fetch transport; we poll retry-http
   * until HTTP setup latches complete or the attempts are exhausted.
   */
  private async runServicesInitialization(sdkInit: SdkInitAdapter): Promise<void> {
    await sdkInit.completePhase2({ environment: this._environment });
    if (sdkInit.hasCompletedHttpSetup) return;

    const maxAttempts = 5;
    const delayMs = 1000;
    for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
      await delay(delayMs);
      if (await sdkInit.retryHttp()) return;
    }
    logger.debug('HTTP/auth setup still incomplete after retries; will proceed offline');
  }

  /** True when commons holds a non-expired access token. */
  async isAuthenticated(): Promise<boolean> {
    return this.sdkInit ? this.sdkInit.isAuthenticated() : false;
  }

  /** True when the device has been registered with the backend. */
  async isDeviceRegistered(): Promise<boolean> {
    return this.sdkInit ? this.sdkInit.isDeviceRegistered() : false;
  }

  async shutdown(): Promise<void> {
    EventBus.shared.stop();
    if (this.commonsHost) {
      unregisterHost(this.commonsHost);
      this.commonsHost.shutdown();
      this.commonsHost = null;
    }
    this.sdkInit = null;
    this._initialized = false;
  }

  ensureInitialized(): void {
    if (!this._initialized) {
      throw new Error('RunAnywhere is not initialized. Call RunAnywhere.initialize() first.');
    }
  }
}

export const RunAnywhere = new RunAnywhereSDK();
