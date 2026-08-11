/**
 * Curated catalog picks for the Models / Voice screens.
 *
 * Model-fit decisions consume SDK/commons `ModelCompatibilityResult.canRun`
 * when supplied; the app never invents a per-tier memory budget. Preference
 * id lists are presentation ordering only (KEEP_DISPLAY_ONLY).
 */

import { webModelCompatibility, type CatalogEntry } from './model-catalog';
import { ModelCategory } from '@runanywhere/web';

/**
 * A recommendation is a promise that the model works here. Prefer commons
 * `can_run` when the map has a verdict; when unknown, allow the catalog
 * entry through rather than inventing a byte budget. Still require the Web
 * engine/WASM gate (`webModelCompatibility`) so we do not advertise a model
 * the picker itself marks unavailable.
 */
function isRecommendable(
  entry: CatalogEntry | undefined,
  canRunByModelID: Readonly<Record<string, boolean>>,
): entry is CatalogEntry {
  if (entry == null) return false;
  if (!webModelCompatibility(entry).supported) return false;
  const verdict = canRunByModelID[entry.id];
  if (verdict === undefined) return true; // unknown — not a fabricated fit
  return verdict;
}

export interface RecommendedSelection {
  /** Best-fit LLM to preselect. `null` when no LLM clears the gates. */
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
 * Curated LLM id preference order (presentation). Fit is decided by can_run,
 * not by these lists.
 */
const LLM_PREFERENCE: readonly string[] = [
  'bonsai-1.7b-q1_0',
  'bonsai-4b-q1_0',
  'bonsai-8b-q1_0',
  'qwen2.5-0.5b-instruct-q6_k',
  'qwen3-0.6b-q4_k_m',
  'qwen3-4b-q4_k_m',
  'lfm2-350m-q4_k_m',
  'smollm2-360m-q8_0',
];

const VLM_PREFERENCE: readonly string[] = [
  'lfm2-vl-450m-q8_0',
  'smolvlm2-256m-video-instruct-q8_0',
];

const ASR_PREFERENCE: readonly string[] = ['sherpa-onnx-whisper-tiny.en'];
const TTS_PREFERENCE: readonly string[] = ['vits-piper-en_US-lessac-medium'];
const EMBEDDING_PREFERENCE: readonly string[] = ['all-minilm-l6-v2'];
const VAD_PREFERENCE: readonly string[] = ['silero-vad'];

const MIN_RECOMMENDED_LLMS = 3;
const MAX_RECOMMENDED_LLMS = 5;

/**
 * Build a recommendation set from the catalog + optional can_run map.
 * Never throws. When `canRunByModelID` is empty, every engine-compatible
 * catalog entry is treated as unknown/compatible (no app thresholds).
 */
export function recommendModels(
  catalog: readonly CatalogEntry[],
  canRunByModelID: Readonly<Record<string, boolean>> = {},
): RecommendedSelection {
  const byId = new Map(catalog.map((entry) => [entry.id, entry]));

  const pick = (ids: readonly string[]): CatalogEntry | null => {
    for (const id of ids) {
      const entry = byId.get(id);
      if (isRecommendable(entry, canRunByModelID)) return entry;
    }
    return null;
  };

  const recommendedLLMs = selectLLMs(LLM_PREFERENCE, byId, canRunByModelID, catalog);

  return {
    defaultModel: recommendedLLMs[0] ?? null,
    recommendedLLMs,
    companions: {
      asr: pick(ASR_PREFERENCE),
      tts: pick(TTS_PREFERENCE),
      vlm: pick(VLM_PREFERENCE),
      embedding: pick(EMBEDDING_PREFERENCE),
    },
  };
}

/**
 * Pick 3–5 LLMs following curated preference order, then top up from any
 * remaining engine-compatible LLM so the section is never uncomfortably short.
 */
function selectLLMs(
  preference: readonly string[],
  byId: Map<string, CatalogEntry>,
  canRunByModelID: Readonly<Record<string, boolean>>,
  catalog: readonly CatalogEntry[],
): CatalogEntry[] {
  const selected: CatalogEntry[] = [];
  const seen = new Set<string>();

  const consider = (entry: CatalogEntry | undefined): void => {
    if (
      entry &&
      !seen.has(entry.id) &&
      entry.category === ModelCategory.MODEL_CATEGORY_LANGUAGE &&
      isRecommendable(entry, canRunByModelID) &&
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
// Voice AI pipeline — STT + LLM + TTS (+ VAD). Pure: same can_run gate.
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
 * Select the voice trio (+ VAD). Fit uses can_run when known; preference
 * lists are presentation ordering only.
 */
export function recommendVoicePipeline(
  catalog: readonly CatalogEntry[],
  canRunByModelID: Readonly<Record<string, boolean>> = {},
): VoicePipelineSelection {
  const byId = new Map(catalog.map((entry) => [entry.id, entry]));
  const pick = (ids: readonly string[]): CatalogEntry | null => {
    for (const id of ids) {
      const entry = byId.get(id);
      if (isRecommendable(entry, canRunByModelID)) return entry;
    }
    return null;
  };

  const llms = selectLLMs(LLM_PREFERENCE, byId, canRunByModelID, catalog);

  return {
    stt: pick(ASR_PREFERENCE),
    llm: llms[0] ?? null,
    tts: pick(TTS_PREFERENCE),
    vad: pick(VAD_PREFERENCE),
  };
}
