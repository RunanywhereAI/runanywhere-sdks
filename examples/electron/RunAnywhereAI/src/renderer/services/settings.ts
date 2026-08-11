/**
 * Settings persistence helpers for the preferences window and feature views.
 *
 * Saves always go through the preload as a merge patch — main merges into the
 * on-disk object so a single pane cannot wipe unrelated keys.
 */
import type { LlmOptions, ToolChoice } from '@runanywhere/electron';

import { DEFAULT_MODELS } from '@shared/model-catalog';
import { DEFAULT_SETTINGS, type AppSettings, type Modality } from '@shared/settings';

let cached: AppSettings | null = null;

export async function loadAppSettings(): Promise<AppSettings> {
  const raw = await window.appStore.loadSettings();
  cached = window.appStore.migrateSettings(raw, DEFAULT_SETTINGS);
  return cached;
}

export async function saveAppSettings(patch: Partial<AppSettings>): Promise<AppSettings> {
  const current = await loadAppSettings();
  const next: AppSettings = {
    ...current,
    ...patch,
    models: { ...current.models, ...(patch.models ?? {}) },
  };
  await window.appStore.saveSettings(next);
  cached = next;
  return next;
}

/** Last loaded settings, or defaults if nothing has been loaded yet. */
export function currentSettings(): AppSettings {
  return cached ?? { ...DEFAULT_SETTINGS, models: { ...DEFAULT_SETTINGS.models } };
}

/** The model id a modality should use — user choice, else catalog default. */
export function selectedModel(modality: Modality): string {
  return currentSettings().models[modality] ?? DEFAULT_MODELS[modality];
}

/** Sampling options every LLM/VLM/RAG screen passes through. */
export function generationOptions(extra: {
  readonly model?: string;
  readonly toolChoice?: ToolChoice;
} = {}): LlmOptions {
  const settings = currentSettings();
  return {
    model: extra.model ?? selectedModel('llm'),
    temperature: settings.temperature,
    maxOutputTokens: settings.maxTokens,
    ...(extra.toolChoice !== undefined ? { toolChoice: extra.toolChoice } : {}),
  };
}
