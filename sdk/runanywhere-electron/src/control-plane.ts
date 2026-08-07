// Desktop control plane (telemetry + auth): the two-phase init, run best-effort
// so an HTTP/auth failure never blocks local inference. Mirrors the Swift flow.
import {
  SdkInitEnvironment,
  SdkInitPhase1Request,
  SdkInitPhase2Request,
} from '@runanywhere/proto-ts/sdk_init';

import type { RaBackend } from './backend.js';
import { Environment } from './types.js';

export interface ControlPlaneOptions {
  apiKey?: string;
  baseUrl?: string;
  environment: Environment;
}

/** The host OS as the backend's platform enum. The binding ("electron") is
 * reported separately as sdk_binding. Guarded for the renderer, where `process`
 * may be absent. */
function osPlatform(): string {
  const p = typeof process !== 'undefined' ? process.platform : '';
  if (p === 'darwin') return 'macos';
  if (p === 'win32') return 'windows';
  if (p === 'linux') return 'linux';
  return 'unknown';
}

/**
 * Run the desktop two-phase init when credentials allow. Returns the persistent
 * device id when the control plane ran, else null. Never throws for a config or
 * transport problem — local inference must stay usable offline.
 */
export async function runControlPlane(
  backend: RaBackend,
  options: ControlPlaneOptions,
  version: string
): Promise<string | null> {
  const apiKey = (options.apiKey ?? '').trim();
  let baseUrl = (options.baseUrl ?? '').trim();
  if (!apiKey && !baseUrl) return null;

  if (!(await backend.hasControlPlane())) {
    // eslint-disable-next-line no-console
    console.warn(
      'RunAnywhere.initialize: apiKey/baseUrl supplied but this build has no desktop control ' +
        'plane (RAC_DESKTOP_ADAPTER=OFF) — no auth or telemetry'
    );
    return null;
  }

  const isProd = options.environment === Environment.PRODUCTION;
  if (!baseUrl && !isProd) baseUrl = await backend.devStagingBaseUrl();
  if (!baseUrl) return null;
  if (isProd && !apiKey) return null;

  const deviceId = await backend.devicePersistentId();
  const platform = osPlatform();
  const protoEnv = isProd
    ? SdkInitEnvironment.SDK_INIT_ENVIRONMENT_PRODUCTION
    : SdkInitEnvironment.SDK_INIT_ENVIRONMENT_DEVELOPMENT;

  const phase1Bytes = SdkInitPhase1Request.encode(
    SdkInitPhase1Request.fromPartial({
      environment: protoEnv,
      apiKey,
      baseUrl,
      deviceId,
      platform,
      sdkVersion: version,
    })
  ).finish();
  const phase2Bytes = SdkInitPhase2Request.encode(
    SdkInitPhase2Request.fromPartial({
      buildToken: '',
      forceRefreshAssignments: false,
      flushTelemetry: true,
      discoverDownloadedModels: true,
      rescanLocalModels: true,
    })
  ).finish();

  await backend.configureControlPlane({
    environment: isProd ? 2 : 0,
    apiKey,
    baseUrl,
    deviceId,
    platform,
    sdkVersion: version,
    sdkBinding: 'electron',
    appIdentifier: 'ai.runanywhere.electron',
    appName: 'RunAnywhere Electron',
    appVersion: version,
    phase1Bytes,
    phase2Bytes,
  });
  return deviceId || null;
}
