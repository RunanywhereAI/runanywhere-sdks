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

  /** Base URL for API requests (production: Railway endpoint) */
  baseURL?: string;

  /** SDK environment */
  environment?: SDKEnvironment;

  /** Optional development-mode device registration token. */
  buildToken?: string;

  /** Bypass cached model assignments during Phase 2. */
  forceRefreshAssignments?: boolean;

  /** Flush queued telemetry during Phase 2. */
  flushTelemetry?: boolean;

  /** Reconcile registry rows with local model files during Phase 2. */
  discoverDownloadedModels?: boolean;

  /** Ask native discovery to rescan local model directories during Phase 2. */
  rescanLocalModels?: boolean;
}
