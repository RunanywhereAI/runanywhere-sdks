/**
 * RN-only public option bags.
 *
 * Model, storage, generation, voice, and compatibility DTOs are generated from
 * proto IDL and re-exported from `types/index.ts`. Do not add SDK-local copies
 * here.
 */

import type { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

/**
 * SDK initialization options.
 *
 * Native modules own HTTP, secure storage, device registration, and platform
 * lifecycle details. This shape only describes the JS call-site options for
 * `RunAnywhere.initialize(...)`.
 */
export interface SDKInitOptions {
  /** API key for authentication (production/staging) */
  apiKey?: string;

  /** Base URL for API requests */
  baseURL?: string;

  /** SDK environment */
  environment?: SDKEnvironment;

  /**
   * Optional development-mode device registration token.
   *
   * `SdkInitPhase2Request` collapsed to this field alone — the
   * `forceRefreshAssignments`/`flushTelemetry`/`discoverDownloadedModels`/
   * `rescanLocalModels` knobs it used to carry are deleted outright; commons
   * now decides those itself rather than taking per-call hints.
   */
  buildToken?: string;
}
