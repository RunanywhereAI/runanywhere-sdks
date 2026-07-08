/**
 * Hardware-aware recommendation engine.
 *
 * Pure and side-effect free: given a detected {@link HardwareTier} and the
 * declarative catalog, it selects a best-fit default LLM plus a spread of
 * recommended models across modalities. It never touches the DOM, the SDK, or
 * download state — the picker layers real download/load status on top.
 *
 * Selection rules (all bounded by the tier's memory budget):
 *   - `defaultModel`: the single best LLM that fits the budget.
 *   - `recommendedLLMs`: 3–5 LLMs spread across fast / balanced / thinking;
 *     the 4B model is only offered on the `high` tier.
 *   - one ASR, one TTS, one VLM, and one embedding companion.
 *
 * Every lookup is by catalog id and degrades gracefully when an id is absent
 * or over budget, so a trimmed catalog can never crash the picker.
 */

import type { CatalogEntry } from './model-catalog';
import type { HardwareTier } from './device-capabilities';
import { ModelCategory } from '@runanywhere/web';

export interface RecommendedSelection {
  /** Best-fit LLM to preselect. `null` when no LLM fits the budget. */
  defaultModel: CatalogEntry | null;
  /** 3–5 LLMs spread across fast / balanced / thinking (includes default). */
  recommendedLLMs: CatalogEntry[];
  /** One companion per modality, when a fitting entry exists. */
  companions: {
    asr: CatalogEntry | null;
    tts: CatalogEntry | null;
    vlm: CatalogEntry | null;
    embedding: CatalogEntry | null;
  };
}

/**
 * Preferred LLM id order per tier (most preferred first). The engine walks the
 * list and keeps the first entries that exist and fit the memory budget.
 */
const LLM_PREFERENCE_BY_TIER: Record<HardwareTier, readonly string[]> = {
  high: ['qwen3-4b-q4_k_m', 'qwen3-0.6b-q4_k_m', 'qwen2.5-0.5b-instruct-q6_k', 'lfm2-350m-q4_k_m'],
  mid: ['qwen2.5-0.5b-instruct-q6_k', 'qwen3-0.6b-q4_k_m', 'lfm2-350m-q4_k_m', 'smollm2-360m-q8_0'],
  low: ['lfm2-350m-q4_k_m', 'qwen3-0.6b-q4_k_m', 'smollm2-360m-q8_0'],
};

/** VLM companion preference per tier (smallest first on low-RAM devices). */
const VLM_PREFERENCE_BY_TIER: Record<HardwareTier, readonly string[]> = {
  high: ['lfm2-vl-450m-q8_0', 'smolvlm2-256m-video-instruct-q8_0'],
  mid: ['lfm2-vl-450m-q8_0', 'smolvlm2-256m-video-instruct-q8_0'],
  low: ['smolvlm2-256m-video-instruct-q8_0', 'lfm2-vl-450m-q8_0'],
};

const ASR_PREFERENCE: readonly string[] = ['sherpa-onnx-whisper-tiny.en'];
const TTS_PREFERENCE: readonly string[] = ['vits-piper-en_US-lessac-medium'];
const EMBEDDING_PREFERENCE: readonly string[] = ['all-minilm-l6-v2'];
const VAD_PREFERENCE: readonly string[] = ['silero-vad'];

const MIN_RECOMMENDED_LLMS = 3;
const MAX_RECOMMENDED_LLMS = 5;

/**
 * Build a tier-appropriate recommendation set from the catalog. Never throws.
 */
export function recommendModels(
  tier: HardwareTier,
  memoryBudgetBytes: number,
  catalog: readonly CatalogEntry[],
): RecommendedSelection {
  const byId = new Map(catalog.map((entry) => [entry.id, entry]));
  const fits = (entry: CatalogEntry | undefined): entry is CatalogEntry =>
    entry != null && entry.memoryRequiredBytes <= memoryBudgetBytes;

  const pick = (ids: readonly string[]): CatalogEntry | null => {
    for (const id of ids) {
      const entry = byId.get(id);
      if (fits(entry)) return entry;
    }
    return null;
  };

  const recommendedLLMs = selectLLMs(
    LLM_PREFERENCE_BY_TIER[tier],
    byId,
    memoryBudgetBytes,
    catalog,
  );

  return {
    defaultModel: recommendedLLMs[0] ?? null,
    recommendedLLMs,
    companions: {
      asr: pick(ASR_PREFERENCE),
      tts: pick(TTS_PREFERENCE),
      vlm: pick(VLM_PREFERENCE_BY_TIER[tier]),
      embedding: pick(EMBEDDING_PREFERENCE),
    },
  };
}

/**
 * Pick 3–5 fitting LLMs following the tier preference order, then top up from
 * any remaining in-budget LLM so the section is never uncomfortably short.
 */
function selectLLMs(
  preference: readonly string[],
  byId: Map<string, CatalogEntry>,
  memoryBudgetBytes: number,
  catalog: readonly CatalogEntry[],
): CatalogEntry[] {
  const selected: CatalogEntry[] = [];
  const seen = new Set<string>();

  const consider = (entry: CatalogEntry | undefined): void => {
    if (
      entry &&
      !seen.has(entry.id) &&
      entry.category === ModelCategory.MODEL_CATEGORY_LANGUAGE &&
      entry.memoryRequiredBytes <= memoryBudgetBytes &&
      selected.length < MAX_RECOMMENDED_LLMS
    ) {
      seen.add(entry.id);
      selected.push(entry);
    }
  };

  for (const id of preference) consider(byId.get(id));

  if (selected.length < MIN_RECOMMENDED_LLMS) {
    for (const entry of catalog) consider(entry);
  }

  return selected;
}

// ---------------------------------------------------------------------------
// Voice AI pipeline — STT + LLM + TTS (+ VAD). A single best-for-device trio
// so the Voice experience can pre-select everything and download/load it in
// one tap. Pure: reuses the same tier preferences as the picker.
// ---------------------------------------------------------------------------

export interface VoicePipelineSelection {
  /** Speech-to-text model (Whisper family). */
  stt: CatalogEntry | null;
  /** Chat model that generates the spoken reply. */
  llm: CatalogEntry | null;
  /** Text-to-speech voice (Piper family). */
  tts: CatalogEntry | null;
  /** Voice-activity detector; optional — the SDK auto-loads it when present. */
  vad: CatalogEntry | null;
}

/**
 * Select the best-for-device voice trio (+ VAD). The LLM reuses the picker's
 * LLM recommendation so Chat and Voice agree on the default chat model; STT,
 * TTS, and VAD come from their single-best preference lists. Every pick is
 * budget-fitted and degrades to `null` when no entry fits.
 */
export function recommendVoicePipeline(
  tier: HardwareTier,
  memoryBudgetBytes: number,
  catalog: readonly CatalogEntry[],
): VoicePipelineSelection {
  const byId = new Map(catalog.map((entry) => [entry.id, entry]));
  const pick = (ids: readonly string[]): CatalogEntry | null => {
    for (const id of ids) {
      const entry = byId.get(id);
      if (entry && entry.memoryRequiredBytes <= memoryBudgetBytes) return entry;
    }
    return null;
  };

  const llms = selectLLMs(LLM_PREFERENCE_BY_TIER[tier], byId, memoryBudgetBytes, catalog);

  return {
    stt: pick(ASR_PREFERENCE),
    llm: llms[0] ?? null,
    tts: pick(TTS_PREFERENCE),
    vad: pick(VAD_PREFERENCE),
  };
}
