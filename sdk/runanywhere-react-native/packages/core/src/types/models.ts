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

  /**
   * Supabase project URL (development mode)
   * When set, SDK makes calls directly to Supabase
   */
  supabaseURL?: string;

  /**
   * Supabase anon key (development mode)
   */
  supabaseKey?: string;

  /**
   * Build token for device registration.
   *
   * Resolution order (highest precedence first):
   *   1. This option.
   *   2. `RUNANYWHERE_BUILD_TOKEN` environment variable (build-time).
   *   3. Native development-mode fallback (development environment only).
   *
   * Production/staging apps must provide this via option or env var.
   */
  buildToken?: string;
}
