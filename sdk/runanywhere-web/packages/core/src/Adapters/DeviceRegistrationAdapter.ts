/**
 * Browser device-registration bridge for the commons device manager.
 *
 * The native manager owns registration ordering and JSON construction, but it
 * requires five platform callbacks for browser metadata, persistent identity,
 * registration state, and the control-plane POST. This adapter owns the WASM
 * function-table entries and their backing C structs for exactly one commons
 * module lifetime.
 */

import {
  RAC_ERROR_HTTP_ERROR,
  RAC_ERROR_INVALID_CONFIGURATION,
  RAC_ERROR_INVALID_ARGUMENT,
  RAC_ERROR_NETWORK_ERROR,
  RAC_ERROR_NOT_INITIALIZED,
  RAC_OK,
} from '../Foundation/RACErrors.js';
import { SDKLogger } from '../Foundation/SDKLogger.js';
import type { EmscriptenRunanywhereModule } from '../runtime/EmscriptenModule.js';
import type { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

const logger = new SDKLogger('DeviceRegistrationAdapter');
const DEFAULT_REQUEST_TIMEOUT_MS = 30_000;
const DEFAULT_DEVICE_MEMORY_GIB = 4;
const BYTES_PER_GIB = 1024 * 1024 * 1024;
const MAX_OS_VERSION_LENGTH = 32;
const LEGACY_REGISTRATION_STORAGE_PREFIX = 'rac_sdk_plaintext_device_registered_';

export interface DeviceRegistrationConfiguration {
  /** Control-plane origin (or same-origin proxy base) selected by the host. */
  baseURL?: string;
  /** Browser-visible client credential. Never logged or persisted here. */
  apiKey?: string;
  sdkVersion: string;
  environment: SDKEnvironment;
  requestTimeoutMs?: number;
}

interface BrowserNavigator extends Navigator {
  deviceMemory?: number;
  userAgentData?: {
    mobile?: boolean;
    platform?: string;
  };
}

interface BrowserPerformance extends Performance {
  memory?: {
    usedJSHeapSize?: number;
    jsHeapSizeLimit?: number;
  };
}

export interface DeviceRegistrationModule extends EmscriptenRunanywhereModule {
  _rac_device_manager_set_callbacks?(callbacksPtr: number): number;
  _rac_device_manager_clear_callbacks?(): void;
  _rac_state_get_device_id?(): number;
  _rac_state_is_device_registered?(): number;
  _rac_state_set_device_registered?(registered: number): void;
  _rac_auth_get_access_token?(): number;
  _rac_wasm_dev_config_get_supabase_url?(): number;
  _rac_wasm_dev_config_get_supabase_key?(): number;
  _rac_wasm_dev_config_is_available?(): number;

  _rac_wasm_sizeof_device_callbacks?(): number;
  _rac_wasm_offsetof_device_callbacks_get_device_info?(): number;
  _rac_wasm_offsetof_device_callbacks_get_device_id?(): number;
  _rac_wasm_offsetof_device_callbacks_is_registered?(): number;
  _rac_wasm_offsetof_device_callbacks_set_registered?(): number;
  _rac_wasm_offsetof_device_callbacks_http_post?(): number;
  _rac_wasm_offsetof_device_callbacks_user_data?(): number;

  _rac_wasm_sizeof_device_registration_info?(): number;
  _rac_wasm_offsetof_device_registration_info_device_id?(): number;
  _rac_wasm_offsetof_device_registration_info_device_model?(): number;
  _rac_wasm_offsetof_device_registration_info_device_name?(): number;
  _rac_wasm_offsetof_device_registration_info_platform?(): number;
  _rac_wasm_offsetof_device_registration_info_os_version?(): number;
  _rac_wasm_offsetof_device_registration_info_form_factor?(): number;
  _rac_wasm_offsetof_device_registration_info_architecture?(): number;
  _rac_wasm_offsetof_device_registration_info_chip_name?(): number;
  _rac_wasm_offsetof_device_registration_info_total_memory?(): number;
  _rac_wasm_offsetof_device_registration_info_available_memory?(): number;
  _rac_wasm_offsetof_device_registration_info_has_neural_engine?(): number;
  _rac_wasm_offsetof_device_registration_info_neural_engine_cores?(): number;
  _rac_wasm_offsetof_device_registration_info_gpu_family?(): number;
  _rac_wasm_offsetof_device_registration_info_battery_level?(): number;
  _rac_wasm_offsetof_device_registration_info_battery_state?(): number;
  _rac_wasm_offsetof_device_registration_info_is_low_power_mode?(): number;
  _rac_wasm_offsetof_device_registration_info_core_count?(): number;
  _rac_wasm_offsetof_device_registration_info_performance_cores?(): number;
  _rac_wasm_offsetof_device_registration_info_efficiency_cores?(): number;
  _rac_wasm_offsetof_device_registration_info_device_fingerprint?(): number;

  _rac_wasm_sizeof_device_http_response?(): number;
  _rac_wasm_offsetof_device_http_response_result?(): number;
  _rac_wasm_offsetof_device_http_response_status_code?(): number;
  _rac_wasm_offsetof_device_http_response_response_body?(): number;
  _rac_wasm_offsetof_device_http_response_error_message?(): number;
}

interface CallbackPointers {
  getDeviceInfo: number;
  getDeviceId: number;
  isRegistered: number;
  setRegistered: number;
  httpPost: number;
}

interface CallbackLayout {
  size: number;
  getDeviceInfo: number;
  getDeviceId: number;
  isRegistered: number;
  setRegistered: number;
  httpPost: number;
  userData: number;
}

interface DeviceInfoLayout {
  size: number;
  deviceId: number;
  deviceModel: number;
  deviceName: number;
  platform: number;
  osVersion: number;
  formFactor: number;
  architecture: number;
  chipName: number;
  totalMemory: number;
  availableMemory: number;
  hasNeuralEngine: number;
  neuralEngineCores: number;
  gpuFamily: number;
  batteryLevel: number;
  batteryState: number;
  isLowPowerMode: number;
  coreCount: number;
  performanceCores: number;
  efficiencyCores: number;
  deviceFingerprint: number;
}

interface HTTPResponseLayout {
  size: number;
  result: number;
  statusCode: number;
  responseBody: number;
  errorMessage: number;
}

interface DeviceProfile {
  deviceModel: string;
  deviceName: string;
  osVersion: string;
  formFactor: 'desktop' | 'phone';
  /** Backend-safe architecture value; browsers do not expose the host ISA reliably. */
  architecture: 'unknown';
  chipName: string;
  totalMemory: number;
  availableMemory: number;
  gpuFamily: string | null;
  coreCount: number;
}

interface ResolvedControlPlaneConfiguration {
  baseURL: string;
  apiKey: string;
}

interface PreparedHTTPRequest {
  key: string;
  result: number;
  statusCode: number;
  errorMessage: string | null;
}

function requiredLayoutHelper(
  helper: (() => number) | undefined,
  name: string,
): number {
  if (typeof helper !== 'function') {
    throw new Error(`WASM module missing ${name}; rebuild the core Web artifact.`);
  }
  return helper();
}

function resolveControlPlaneURL(baseURL: string, endpoint: string): string | null {
  const normalizedBase = baseURL.trim().replace(/\/+$/, '');
  if (!normalizedBase || !endpoint.startsWith('/') || endpoint.startsWith('//')) return null;
  try {
    const base = new URL(normalizedBase);
    if (
      (base.protocol !== 'https:' && base.protocol !== 'http:')
      || base.username.length > 0
      || base.password.length > 0
      || base.search.length > 0
      || base.hash.length > 0
    ) {
      return null;
    }
    return `${normalizedBase}/${endpoint.replace(/^\/+/, '')}`;
  } catch {
    return null;
  }
}

/**
 * Convert a browser user agent into the short OS value expected by the device
 * API. A complete user agent is not an OS version and can exceed the backing
 * datastore column even when it passes the public request schema.
 */
function browserOSVersion(userAgent: string, platform: string): string {
  const candidates: ReadonlyArray<readonly [RegExp, string]> = [
    [/Windows NT ([0-9.]+)/i, 'Windows'],
    [/Android ([0-9.]+)/i, 'Android'],
    [/(?:iPhone|CPU) OS ([0-9_]+)/i, 'iOS'],
    [/Mac OS X ([0-9_]+)/i, 'macOS'],
    [/CrOS [^ )]+ ([0-9.]+)/i, 'ChromeOS'],
  ];
  for (const [pattern, label] of candidates) {
    const match = pattern.exec(userAgent);
    const version = match?.[1]?.replaceAll('_', '.');
    if (version) return `${label} ${version}`.slice(0, MAX_OS_VERSION_LENGTH);
  }
  if (/Linux/i.test(userAgent)) return 'Linux';

  const normalizedPlatform = platform.trim().replace(/\s+/g, ' ');
  return (normalizedPlatform || 'unknown').slice(0, MAX_OS_VERSION_LENGTH);
}

function browserDeviceProfile(): DeviceProfile {
  const nav = navigator as BrowserNavigator;
  const perf = performance as BrowserPerformance;
  const platform = nav.userAgentData?.platform?.trim()
    || nav.platform?.trim()
    || 'Web Browser';
  const coreCount = Math.max(1, Math.trunc(nav.hardwareConcurrency || 1));
  const totalMemory = Math.max(
    BYTES_PER_GIB,
    Math.trunc((nav.deviceMemory || DEFAULT_DEVICE_MEMORY_GIB) * BYTES_PER_GIB),
  );
  const heapLimit = perf.memory?.jsHeapSizeLimit;
  const heapUsed = perf.memory?.usedJSHeapSize ?? 0;
  const availableMemory = typeof heapLimit === 'number' && Number.isFinite(heapLimit)
    ? Math.min(totalMemory, Math.max(0, Math.trunc(heapLimit - heapUsed)))
    : totalMemory;
  const mobile = nav.userAgentData?.mobile
    ?? /Android|iPhone|iPad|Mobile/i.test(nav.userAgent);

  return {
    deviceModel: platform,
    deviceName: document.title.trim() || 'RunAnywhere Web',
    osVersion: browserOSVersion(nav.userAgent, platform),
    formFactor: mobile ? 'phone' : 'desktop',
    architecture: 'unknown',
    chipName: platform,
    totalMemory,
    availableMemory,
    gpuFamily: 'gpu' in nav ? 'webgpu' : null,
    coreCount,
  };
}

function setI64(module: DeviceRegistrationModule, ptr: number, value: number): void {
  const safeValue = Math.max(0, Math.trunc(value));
  module.setValue(ptr, safeValue >>> 0, 'i32');
  module.setValue(ptr + 4, Math.floor(safeValue / 0x100000000) >>> 0, 'i32');
}

export class DeviceRegistrationAdapter {
  private static readonly installedAdapters = new WeakMap<
    DeviceRegistrationModule,
    DeviceRegistrationAdapter
  >();

  private callbackPointers: CallbackPointers | null = null;
  private callbacksPtr = 0;
  private deviceInfoStrings: number[] = [];
  private responseStrings: number[] = [];
  private readonly callbackLayout: CallbackLayout;
  private readonly deviceInfoLayout: DeviceInfoLayout;
  private readonly responseLayout: HTTPResponseLayout;
  private readonly configuredBaseURL: string;
  private readonly configuredApiKey: string;
  private readonly requestTimeoutMs: number;
  private pendingRequest: Promise<void> | null = null;
  private preparedRequest: PreparedHTTPRequest | null = null;
  private nativeRetryRequired = false;
  private activeRequestController: AbortController | null = null;
  private disposed = false;

  private constructor(
    private readonly module: DeviceRegistrationModule,
    private readonly configuration: DeviceRegistrationConfiguration,
  ) {
    this.configuredBaseURL = configuration.baseURL?.trim() ?? '';
    this.configuredApiKey = configuration.apiKey?.trim() ?? '';
    this.requestTimeoutMs = Math.max(
      1,
      Math.trunc(configuration.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS),
    );
    this.callbackLayout = this.readCallbackLayout();
    this.deviceInfoLayout = this.readDeviceInfoLayout();
    this.responseLayout = this.readResponseLayout();
  }

  static install(
    module: DeviceRegistrationModule,
    configuration: DeviceRegistrationConfiguration,
  ): DeviceRegistrationAdapter {
    const adapter = new DeviceRegistrationAdapter(module, configuration);
    adapter.register();
    DeviceRegistrationAdapter.installedAdapters.set(module, adapter);
    return adapter;
  }

  /**
   * Wait for a browser registration request that the synchronous native
   * callback started on the event loop. The caller must then invoke
   * `rac_device_manager_register_if_needed` once more so native state is only
   * committed after the bounded fetch has actually completed.
   */
  static async waitForPendingRegistration(
    module: DeviceRegistrationModule,
  ): Promise<boolean> {
    const adapter = DeviceRegistrationAdapter.installedAdapters.get(module);
    if (!adapter || !adapter.nativeRetryRequired || adapter.disposed) return false;
    const pending = adapter.pendingRequest;
    if (pending) await pending;
    return adapter.nativeRetryRequired && !adapter.disposed;
  }

  cleanup(): void {
    this.disposed = true;
    this.activeRequestController?.abort();
    this.activeRequestController = null;
    this.pendingRequest = null;
    this.preparedRequest = null;
    this.nativeRetryRequired = false;
    if (DeviceRegistrationAdapter.installedAdapters.get(this.module) === this) {
      DeviceRegistrationAdapter.installedAdapters.delete(this.module);
    }
    try {
      this.module._rac_device_manager_clear_callbacks?.();
    } catch {
      logger.warning('Failed to clear native device callbacks during shutdown.');
    }

    if (this.callbackPointers) {
      for (const ptr of Object.values(this.callbackPointers)) {
        if (ptr === 0) continue;
        try {
          this.module.removeFunction(ptr);
        } catch {
          // Continue releasing the remaining owned resources.
        }
      }
      this.callbackPointers = null;
    }
    this.freeStrings(this.deviceInfoStrings);
    this.freeStrings(this.responseStrings);
    if (this.callbacksPtr !== 0) {
      this.module._free(this.callbacksPtr);
      this.callbacksPtr = 0;
    }
  }

  private register(): void {
    const registerCallbacks = this.module._rac_device_manager_set_callbacks;
    const clearCallbacks = this.module._rac_device_manager_clear_callbacks;
    if (typeof registerCallbacks !== 'function' || typeof clearCallbacks !== 'function') {
      throw new Error('WASM module missing device-manager callback lifecycle exports.');
    }

    this.callbacksPtr = this.module._malloc(this.callbackLayout.size);
    if (!this.callbacksPtr) throw new Error('Failed to allocate device callback table.');
    this.zeroMemory(this.callbacksPtr, this.callbackLayout.size);

    // Older Web builds persisted a host/environment-scoped registration bit.
    // It was not credential- or organization-scoped, so reusing it after an
    // API-key switch could skip device registration for the new organization.
    // Registration is idempotent server-side; scrub the legacy bit and keep
    // this state native/in-memory for one runtime lifetime only.
    this.scrubLegacyPersistedRegistration();

    try {
      this.callbackPointers = {
        getDeviceInfo: this.module.addFunction(
          (outInfoPtr: number) => { this.writeDeviceInfoSafely(outInfoPtr); },
          'vii',
        ),
        getDeviceId: this.module.addFunction(
          () => this.readDeviceIdPointer(),
          'ii',
        ),
        isRegistered: this.module.addFunction(
          () => this.readRegistrationState(),
          'ii',
        ),
        setRegistered: this.module.addFunction(
          (registered: number) => { this.writeRegistrationState(registered); },
          'vii',
        ),
        httpPost: this.module.addFunction(
          (
            endpointPtr: number,
            jsonBodyPtr: number,
            requiresAuth: number,
            outResponsePtr: number,
          ) => this.runHTTPPost(endpointPtr, jsonBodyPtr, requiresAuth, outResponsePtr),
          'iiiiii',
        ),
      };

      this.module.setValue(
        this.callbacksPtr + this.callbackLayout.getDeviceInfo,
        this.callbackPointers.getDeviceInfo,
        '*',
      );
      this.module.setValue(
        this.callbacksPtr + this.callbackLayout.getDeviceId,
        this.callbackPointers.getDeviceId,
        '*',
      );
      this.module.setValue(
        this.callbacksPtr + this.callbackLayout.isRegistered,
        this.callbackPointers.isRegistered,
        '*',
      );
      this.module.setValue(
        this.callbacksPtr + this.callbackLayout.setRegistered,
        this.callbackPointers.setRegistered,
        '*',
      );
      this.module.setValue(
        this.callbacksPtr + this.callbackLayout.httpPost,
        this.callbackPointers.httpPost,
        '*',
      );
      this.module.setValue(this.callbacksPtr + this.callbackLayout.userData, 0, '*');

      const result = registerCallbacks.call(this.module, this.callbacksPtr);
      if (result !== RAC_OK) {
        throw new Error(`rac_device_manager_set_callbacks failed with code ${result}.`);
      }
    } catch (error) {
      this.cleanup();
      throw error;
    }
  }

  private writeDeviceInfoSafely(outInfoPtr: number): void {
    if (!outInfoPtr) return;
    try {
      this.writeDeviceInfo(outInfoPtr);
    } catch {
      this.zeroMemory(outInfoPtr, this.deviceInfoLayout.size);
      logger.warning('Browser device metadata could not be marshalled.');
    }
  }

  private writeDeviceInfo(outInfoPtr: number): void {
    const profile = browserDeviceProfile();
    const deviceIdPtr = this.readDeviceIdPointer();
    this.zeroMemory(outInfoPtr, this.deviceInfoLayout.size);
    this.freeStrings(this.deviceInfoStrings);

    const writeString = (offset: number, value: string | null): void => {
      const ptr = value ? this.allocateCString(value, this.deviceInfoStrings) : 0;
      this.module.setValue(outInfoPtr + offset, ptr, '*');
    };

    this.module.setValue(outInfoPtr + this.deviceInfoLayout.deviceId, deviceIdPtr, '*');
    writeString(this.deviceInfoLayout.deviceModel, profile.deviceModel);
    writeString(this.deviceInfoLayout.deviceName, profile.deviceName);
    writeString(this.deviceInfoLayout.platform, 'web');
    writeString(this.deviceInfoLayout.osVersion, profile.osVersion);
    writeString(this.deviceInfoLayout.formFactor, profile.formFactor);
    writeString(this.deviceInfoLayout.architecture, profile.architecture);
    writeString(this.deviceInfoLayout.chipName, profile.chipName);
    setI64(this.module, outInfoPtr + this.deviceInfoLayout.totalMemory, profile.totalMemory);
    setI64(this.module, outInfoPtr + this.deviceInfoLayout.availableMemory, profile.availableMemory);
    this.module.setValue(outInfoPtr + this.deviceInfoLayout.hasNeuralEngine, 0, 'i32');
    this.module.setValue(outInfoPtr + this.deviceInfoLayout.neuralEngineCores, 0, 'i32');
    writeString(this.deviceInfoLayout.gpuFamily, profile.gpuFamily);
    this.module.setValue(outInfoPtr + this.deviceInfoLayout.batteryLevel, -1, 'double');
    this.module.setValue(outInfoPtr + this.deviceInfoLayout.batteryState, 0, '*');
    this.module.setValue(outInfoPtr + this.deviceInfoLayout.isLowPowerMode, 0, 'i32');
    this.module.setValue(outInfoPtr + this.deviceInfoLayout.coreCount, profile.coreCount, 'i32');
    this.module.setValue(
      outInfoPtr + this.deviceInfoLayout.performanceCores,
      0,
      'i32',
    );
    this.module.setValue(outInfoPtr + this.deviceInfoLayout.efficiencyCores, 0, 'i32');
    this.module.setValue(
      outInfoPtr + this.deviceInfoLayout.deviceFingerprint,
      deviceIdPtr,
      '*',
    );
  }

  private readDeviceIdPointer(): number {
    try {
      return this.module._rac_state_get_device_id?.() ?? 0;
    } catch {
      return 0;
    }
  }

  private readRegistrationState(): number {
    try {
      return this.module._rac_state_is_device_registered?.() ? 1 : 0;
    } catch {
      return 0;
    }
  }

  private writeRegistrationState(registered: number): void {
    const isRegistered = registered !== 0;
    try {
      this.module._rac_state_set_device_registered?.(isRegistered ? 1 : 0);
    } catch {
      logger.warning('Native device registration state could not be updated.');
    }
  }

  private runHTTPPost(
    endpointPtr: number,
    jsonBodyPtr: number,
    requiresAuth: number,
    outResponsePtr: number,
  ): number {
    if (!endpointPtr || !jsonBodyPtr || !outResponsePtr) return RAC_ERROR_INVALID_ARGUMENT;
    this.zeroMemory(outResponsePtr, this.responseLayout.size);
    this.freeStrings(this.responseStrings);

    try {
      const endpoint = this.module.UTF8ToString(endpointPtr);
      const jsonBody = this.module.UTF8ToString(jsonBodyPtr);
      const isDevelopmentRegistration = endpoint.startsWith('/rest/v1/');
      const controlPlane = this.currentControlPlaneConfiguration();
      if (!controlPlane) {
        return this.writeHTTPFailure(
          outResponsePtr,
          RAC_ERROR_INVALID_CONFIGURATION,
          0,
          'Device registration requires a matching base URL and API key.',
        );
      }
      const { baseURL, apiKey } = controlPlane;
      const resolvedURL = resolveControlPlaneURL(baseURL, endpoint);
      if (!resolvedURL) {
        return this.writeHTTPFailure(
          outResponsePtr,
          RAC_ERROR_INVALID_CONFIGURATION,
          0,
          'Device registration URL is unavailable.',
        );
      }

      const accessToken = requiresAuth !== 0
        ? this.currentAccessToken()
        : isDevelopmentRegistration
          ? apiKey
          : '';
      if (requiresAuth !== 0 && (!apiKey || !accessToken)) {
        return this.writeHTTPFailure(
          outResponsePtr,
          RAC_ERROR_INVALID_CONFIGURATION,
          0,
          'Device registration authentication is unavailable.',
        );
      }

      const url = isDevelopmentRegistration
        ? `${resolvedURL}?on_conflict=device_id`
        : resolvedURL;
      // Native reconstructs the registration payload for the retry and refreshes
      // volatile fields such as last_seen_at_ms. Correlate the prepared response
      // with the only operation this callback serves (route + auth mode), rather
      // than requiring byte-identical JSON across the two native invocations.
      const requestKey = `${requiresAuth}:${url}`;
      if (this.preparedRequest?.key === requestKey) {
        const prepared = this.preparedRequest;
        this.preparedRequest = null;
        this.nativeRetryRequired = false;
        if (prepared.result !== RAC_OK) {
          return this.writeHTTPFailure(
            outResponsePtr,
            prepared.result,
            prepared.statusCode,
            prepared.errorMessage ?? 'Device registration request failed.',
          );
        }
        this.module.setValue(outResponsePtr + this.responseLayout.result, RAC_OK, 'i32');
        this.module.setValue(
          outResponsePtr + this.responseLayout.statusCode,
          prepared.statusCode,
          'i32',
        );
        return RAC_OK;
      }

      if (!this.pendingRequest) {
        this.nativeRetryRequired = true;
        const pending = this.prepareHTTPRequest({
          key: requestKey,
          url,
          jsonBody,
          apiKey,
          accessToken,
          isDevelopmentRegistration,
        });
        this.pendingRequest = pending;
        void pending.finally(() => {
          if (this.pendingRequest === pending) this.pendingRequest = null;
        });
      }
      return this.writeHTTPFailure(
        outResponsePtr,
        RAC_ERROR_NOT_INITIALIZED,
        0,
        'Device registration request is pending.',
      );
    } catch {
      return this.writeHTTPFailure(
        outResponsePtr,
        RAC_ERROR_NETWORK_ERROR,
        0,
        'Device registration request failed.',
      );
    }
  }

  private writeHTTPFailure(
    outResponsePtr: number,
    result: number,
    statusCode: number,
    message: string,
  ): number {
    const messagePtr = this.allocateCString(message, this.responseStrings);
    this.module.setValue(outResponsePtr + this.responseLayout.result, result, 'i32');
    this.module.setValue(outResponsePtr + this.responseLayout.statusCode, statusCode, 'i32');
    this.module.setValue(outResponsePtr + this.responseLayout.responseBody, 0, '*');
    this.module.setValue(outResponsePtr + this.responseLayout.errorMessage, messagePtr, '*');
    return result;
  }

  private currentAccessToken(): string {
    return this.readNativeString(this.module._rac_auth_get_access_token);
  }

  /** Resolve URL + credential atomically so embedded secrets never cross origins. */
  private currentControlPlaneConfiguration(): ResolvedControlPlaneConfiguration | null {
    if (this.configuredBaseURL || this.configuredApiKey) {
      return this.configuredBaseURL && this.configuredApiKey
        ? { baseURL: this.configuredBaseURL, apiKey: this.configuredApiKey }
        : null;
    }
    try {
      if (this.module._rac_wasm_dev_config_is_available?.() !== 1) return null;
      const baseURL = this.readNativeString(this.module._rac_wasm_dev_config_get_supabase_url);
      const apiKey = this.readNativeString(this.module._rac_wasm_dev_config_get_supabase_key);
      return baseURL && apiKey ? { baseURL, apiKey } : null;
    } catch {
      return null;
    }
  }

  private async prepareHTTPRequest(options: {
    key: string;
    url: string;
    jsonBody: string;
    apiKey: string;
    accessToken: string;
    isDevelopmentRegistration: boolean;
  }): Promise<void> {
    const controller = new AbortController();
    this.activeRequestController = controller;
    const timeout = setTimeout(() => controller.abort(), this.requestTimeoutMs);
    try {
      const headers = new Headers({
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-SDK-Client': 'RunAnywhereSDK',
        'X-SDK-Version': this.configuration.sdkVersion,
        'X-Platform': 'web',
      });
      if (options.apiKey) headers.set('apikey', options.apiKey);
      if (options.accessToken) headers.set('Authorization', `Bearer ${options.accessToken}`);
      if (options.isDevelopmentRegistration) {
        headers.set('Prefer', 'resolution=merge-duplicates,return=representation');
      }
      const response = await fetch(options.url, {
        method: 'POST',
        headers,
        body: options.jsonBody,
        signal: controller.signal,
      });
      const accepted = response.ok || response.status === 409;
      if (!this.disposed) {
        this.preparedRequest = {
          key: options.key,
          result: accepted ? RAC_OK : RAC_ERROR_HTTP_ERROR,
          statusCode: response.status | 0,
          errorMessage: accepted ? null : 'Device registration request was rejected.',
        };
      }
    } catch {
      if (!this.disposed) {
        this.preparedRequest = {
          key: options.key,
          result: RAC_ERROR_NETWORK_ERROR,
          statusCode: 0,
          errorMessage: controller.signal.aborted
            ? 'Device registration request timed out.'
            : 'Device registration request failed.',
        };
      }
    } finally {
      clearTimeout(timeout);
      if (this.activeRequestController === controller) this.activeRequestController = null;
    }
  }

  private scrubLegacyPersistedRegistration(): void {
    try {
      for (let index = localStorage.length - 1; index >= 0; index -= 1) {
        const key = localStorage.key(index);
        if (key?.startsWith(LEGACY_REGISTRATION_STORAGE_PREFIX)) {
          localStorage.removeItem(key);
        }
      }
    } catch {
      // Storage may be disabled; registration remains correct in native state.
    }
  }

  private readNativeString(getter: (() => number) | undefined): string {
    if (typeof getter !== 'function') return '';
    try {
      const ptr = getter.call(this.module);
      return ptr ? this.module.UTF8ToString(ptr) : '';
    } catch {
      return '';
    }
  }

  private allocateCString(value: string, ownedPointers: number[]): number {
    const size = this.module.lengthBytesUTF8(value) + 1;
    const ptr = this.module._malloc(size);
    if (!ptr) throw new Error('Failed to allocate a device registration string.');
    this.module.stringToUTF8(value, ptr, size);
    ownedPointers.push(ptr);
    return ptr;
  }

  private freeStrings(ownedPointers: number[]): void {
    for (const ptr of ownedPointers.splice(0)) {
      try {
        this.module._free(ptr);
      } catch {
        // Continue releasing later allocations.
      }
    }
  }

  private zeroMemory(ptr: number, size: number): void {
    for (let index = 0; index < size; index += 1) {
      this.module.setValue(ptr + index, 0, 'i8');
    }
  }

  private readCallbackLayout(): CallbackLayout {
    const m = this.module;
    return {
      size: requiredLayoutHelper(m._rac_wasm_sizeof_device_callbacks, 'rac_wasm_sizeof_device_callbacks'),
      getDeviceInfo: requiredLayoutHelper(m._rac_wasm_offsetof_device_callbacks_get_device_info, 'rac_wasm_offsetof_device_callbacks_get_device_info'),
      getDeviceId: requiredLayoutHelper(m._rac_wasm_offsetof_device_callbacks_get_device_id, 'rac_wasm_offsetof_device_callbacks_get_device_id'),
      isRegistered: requiredLayoutHelper(m._rac_wasm_offsetof_device_callbacks_is_registered, 'rac_wasm_offsetof_device_callbacks_is_registered'),
      setRegistered: requiredLayoutHelper(m._rac_wasm_offsetof_device_callbacks_set_registered, 'rac_wasm_offsetof_device_callbacks_set_registered'),
      httpPost: requiredLayoutHelper(m._rac_wasm_offsetof_device_callbacks_http_post, 'rac_wasm_offsetof_device_callbacks_http_post'),
      userData: requiredLayoutHelper(m._rac_wasm_offsetof_device_callbacks_user_data, 'rac_wasm_offsetof_device_callbacks_user_data'),
    };
  }

  private readDeviceInfoLayout(): DeviceInfoLayout {
    const m = this.module;
    return {
      size: requiredLayoutHelper(m._rac_wasm_sizeof_device_registration_info, 'rac_wasm_sizeof_device_registration_info'),
      deviceId: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_device_id, 'rac_wasm_offsetof_device_registration_info_device_id'),
      deviceModel: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_device_model, 'rac_wasm_offsetof_device_registration_info_device_model'),
      deviceName: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_device_name, 'rac_wasm_offsetof_device_registration_info_device_name'),
      platform: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_platform, 'rac_wasm_offsetof_device_registration_info_platform'),
      osVersion: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_os_version, 'rac_wasm_offsetof_device_registration_info_os_version'),
      formFactor: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_form_factor, 'rac_wasm_offsetof_device_registration_info_form_factor'),
      architecture: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_architecture, 'rac_wasm_offsetof_device_registration_info_architecture'),
      chipName: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_chip_name, 'rac_wasm_offsetof_device_registration_info_chip_name'),
      totalMemory: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_total_memory, 'rac_wasm_offsetof_device_registration_info_total_memory'),
      availableMemory: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_available_memory, 'rac_wasm_offsetof_device_registration_info_available_memory'),
      hasNeuralEngine: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_has_neural_engine, 'rac_wasm_offsetof_device_registration_info_has_neural_engine'),
      neuralEngineCores: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_neural_engine_cores, 'rac_wasm_offsetof_device_registration_info_neural_engine_cores'),
      gpuFamily: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_gpu_family, 'rac_wasm_offsetof_device_registration_info_gpu_family'),
      batteryLevel: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_battery_level, 'rac_wasm_offsetof_device_registration_info_battery_level'),
      batteryState: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_battery_state, 'rac_wasm_offsetof_device_registration_info_battery_state'),
      isLowPowerMode: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_is_low_power_mode, 'rac_wasm_offsetof_device_registration_info_is_low_power_mode'),
      coreCount: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_core_count, 'rac_wasm_offsetof_device_registration_info_core_count'),
      performanceCores: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_performance_cores, 'rac_wasm_offsetof_device_registration_info_performance_cores'),
      efficiencyCores: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_efficiency_cores, 'rac_wasm_offsetof_device_registration_info_efficiency_cores'),
      deviceFingerprint: requiredLayoutHelper(m._rac_wasm_offsetof_device_registration_info_device_fingerprint, 'rac_wasm_offsetof_device_registration_info_device_fingerprint'),
    };
  }

  private readResponseLayout(): HTTPResponseLayout {
    const m = this.module;
    return {
      size: requiredLayoutHelper(m._rac_wasm_sizeof_device_http_response, 'rac_wasm_sizeof_device_http_response'),
      result: requiredLayoutHelper(m._rac_wasm_offsetof_device_http_response_result, 'rac_wasm_offsetof_device_http_response_result'),
      statusCode: requiredLayoutHelper(m._rac_wasm_offsetof_device_http_response_status_code, 'rac_wasm_offsetof_device_http_response_status_code'),
      responseBody: requiredLayoutHelper(m._rac_wasm_offsetof_device_http_response_response_body, 'rac_wasm_offsetof_device_http_response_response_body'),
      errorMessage: requiredLayoutHelper(m._rac_wasm_offsetof_device_http_response_error_message, 'rac_wasm_offsetof_device_http_response_error_message'),
    };
  }
}
