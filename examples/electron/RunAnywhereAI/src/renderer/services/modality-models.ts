/**
 * Resolve the per-modality model the voice screens should use.
 *
 * The Models screen owns picking and downloading; these helpers only read the
 * persisted choice (or the catalog default) and ask the SDK to load it.
 */
import { DEFAULT_MODELS, type ModelType } from '@shared/model-catalog';
import { DEFAULT_SETTINGS, type Modality } from '@shared/settings';

export function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message.length > 0) return error.message;
  return String(error);
}

/** Friendly catalog label, falling back to the id. */
export function modelLabel(id: string): string {
  const catalog = window.runanywhere.catalog();
  if (!(id in catalog)) return id;
  return catalog[id].label ?? id;
}

export async function selectedModelId(modality: Modality): Promise<string> {
  const saved = await window.appStore.loadSettings();
  const settings = window.appStore.migrateSettings(saved, DEFAULT_SETTINGS);
  return settings.models[modality] ?? DEFAULT_MODELS[modality as ModelType];
}

/**
 * Make the modality's chosen model resident. No framework pin — residency and
 * routing stay in the SDK / commons.
 */
export async function ensureModelLoaded(modality: Modality): Promise<string> {
  const id = await selectedModelId(modality);
  await window.runanywhere.models.load(id);
  return id;
}
