import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

export type EnvKey = 'development' | 'staging' | 'production';

const STORAGE_KEY = 'runanywhere.settings.v2';

const ENV_ENUM: Record<EnvKey, SDKEnvironment> = {
  development: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
  staging: SDKEnvironment.SDK_ENVIRONMENT_STAGING,
  production: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
};

interface Persisted {
  environment: EnvKey;
  apiKey: string;
  baseUrl: string;
}

function load(): Persisted {
  // Defaults come from build-time env (.env.local — same creds as the android
  // example's local.properties), so telemetry works out of the box. A user
  // override saved to localStorage takes precedence.
  // STAGING (not development) so the railway backend + telemetry are honored —
  // commons gates off auth/backend-sync/telemetry entirely in development. This
  // matches the android & flutter examples (RunAnywhereApplication.kt).
  const fallback: Persisted = {
    environment: 'staging',
    apiKey: import.meta.env.VITE_RUNANYWHERE_API_KEY ?? '',
    baseUrl: import.meta.env.VITE_RUNANYWHERE_BASE_URL ?? '',
  };
  try {
    const raw = typeof localStorage !== 'undefined' ? localStorage.getItem(STORAGE_KEY) : null;
    if (!raw) return fallback;
    const p = JSON.parse(raw) as Partial<Persisted>;
    return {
      environment: p.environment ?? fallback.environment,
      apiKey: p.apiKey ?? fallback.apiKey,
      baseUrl: p.baseUrl ?? fallback.baseUrl,
    };
  } catch {
    return fallback;
  }
}

// SDK connection settings, persisted to localStorage. Consumed by sdk.boot()
// when it calls RunAnywhere.initialize(); changes take effect on the next
// engine boot (reload), mirroring the other SDKs' credential flow.
class SettingsStore {
  environment = $state<EnvKey>('staging');
  apiKey = $state('');
  baseUrl = $state('');

  constructor() {
    const p = load();
    this.environment = p.environment;
    this.apiKey = p.apiKey;
    this.baseUrl = p.baseUrl;
  }

  get environmentEnum(): SDKEnvironment {
    return ENV_ENUM[this.environment];
  }

  save(next: Partial<Persisted>): void {
    if (next.environment !== undefined) this.environment = next.environment;
    if (next.apiKey !== undefined) this.apiKey = next.apiKey;
    if (next.baseUrl !== undefined) this.baseUrl = next.baseUrl;
    try {
      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({ environment: this.environment, apiKey: this.apiKey, baseUrl: this.baseUrl }),
      );
    } catch {
      // storage unavailable (private mode) — settings just won't persist
    }
  }
}

export const settings = new SettingsStore();
