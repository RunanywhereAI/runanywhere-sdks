/**
 * Persisted app settings and their migration.
 *
 * Ported from the pre-TypeScript `store.js`. The migration exists because
 * persisted values override defaults: a user who ever pressed "Save settings"
 * on a superseded default would keep the old behaviour forever, with no way to
 * know why.
 */
import type { ThemePreference } from './ipc-contract';

/** Per-modality model choice. Keys match the catalog's `ModelType`. */
export type Modality = 'llm' | 'vlm' | 'embedder' | 'stt' | 'tts' | 'diarization' | 'segmentation';

export interface AppSettings {
  systemPrompt: string;
  temperature: number;
  maxTokens: number;
  /** Ask the model to expose its reasoning when it supports thinking. */
  reasoning: boolean;
  /** Let the model call the locally-registered demo tools. */
  tools: boolean;
  theme: ThemePreference;
  /**
   * Persist performance / analytics events on disk (Swift
   * `analyticsLogToLocal` / "Save Performance History").
   */
  analyticsLogToLocal: boolean;
  /**
   * Whether an HF token has been handed to the SDK secure store. The secret
   * itself is never written here — only this status bit for the Advanced pane.
   */
  hfTokenConfigured: boolean;
  /** Which model each modality uses. Absent means "the default for that modality". */
  models: Partial<Record<Modality, string>>;
}

export const DEFAULT_SETTINGS: Readonly<AppSettings> = Object.freeze({
  systemPrompt:
    'You are RunAnywhere, a helpful assistant running entirely on this device. ' +
    'Answer using what the user tells you. Be direct and concise.',
  temperature: 0.3,
  maxTokens: 1024,
  reasoning: false,
  tools: false,
  theme: 'system',
  analyticsLogToLocal: false,
  hfTokenConfigured: false,
  models: {},
});

/**
 * System prompts shipped by earlier builds. A saved copy of one of these is a
 * default the user never actually customised, so it is safe to upgrade.
 */
export const SUPERSEDED_SYSTEM_PROMPTS: readonly string[] = [
  'You are a concise, helpful assistant.',
];

/**
 * Merge persisted settings over the defaults, upgrading known-superseded values.
 *
 * Merging (rather than replacing) is what keeps per-modality model choices alive
 * when an unrelated setting is saved.
 */
export function migrateSettings(saved: unknown, defaults: AppSettings = DEFAULT_SETTINGS): AppSettings {
  if (saved === null || typeof saved !== 'object') return { ...defaults, models: { ...defaults.models } };

  const record = saved as Partial<AppSettings>;
  const out: AppSettings = {
    ...defaults,
    ...record,
    models: { ...defaults.models, ...(record.models ?? {}) },
  };

  if (SUPERSEDED_SYSTEM_PROMPTS.includes((record.systemPrompt ?? '').trim())) {
    out.systemPrompt = defaults.systemPrompt;
    // That prompt shipped alongside a temperature tuned for it.
    if (record.temperature === 0.7) out.temperature = defaults.temperature;
  }

  return out;
}
