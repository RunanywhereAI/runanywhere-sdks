/**
 * Thin settings client for feature views.
 *
 * Main owns persistence; views only need the generation knobs and the
 * per-modality model choice when they call the SDK.
 */
import { DEFAULT_MODELS } from '@shared/model-catalog';
import { DEFAULT_SETTINGS, type AppSettings, type Modality } from '@shared/settings';

let cached: AppSettings | null = null;

/** Load (or re-load) settings from the store, merging over defaults. */
export async function loadAppSettings(): Promise<AppSettings> {
  try {
    cached = window.appStore.migrateSettings(await window.appStore.loadSettings(), DEFAULT_SETTINGS);
  } catch {
    cached = { ...DEFAULT_SETTINGS, models: { ...DEFAULT_SETTINGS.models } };
  }
  return cached;
}

/** Last loaded settings, falling back to defaults if nothing has been loaded yet. */
export function currentSettings(): AppSettings {
  return cached ?? { ...DEFAULT_SETTINGS, models: { ...DEFAULT_SETTINGS.models } };
}

/** Persist a settings object and refresh the cache. */
export async function saveAppSettings(next: AppSettings): Promise<void> {
  cached = next;
  await window.appStore.saveSettings(next);
}

/** The model id a modality should use — user choice, else catalog default. */
export function selectedModel(modality: Modality): string {
  const settings = currentSettings();
  return settings.models[modality] ?? DEFAULT_MODELS[modality];
}

/** Sampling options every LLM/VLM screen passes through. */
export function generationOptions(extra: {
  readonly model?: string;
  readonly toolChoice?: 'NONE' | 'AUTO' | 'REQUIRED';
} = {}): {
  model: string;
  temperature: number;
  maxOutputTokens: number;
  toolChoice?: 'NONE' | 'AUTO' | 'REQUIRED';
} {
  const settings = currentSettings();
  return {
    model: extra.model ?? selectedModel('llm'),
    temperature: settings.temperature,
    maxOutputTokens: settings.maxTokens,
    ...(extra.toolChoice !== undefined ? { toolChoice: extra.toolChoice } : {}),
  };
}
