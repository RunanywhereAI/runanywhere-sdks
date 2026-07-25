/**
 * Shared display helpers for model catalog rendering.
 *
 * Previously these label tables were inlined in both `components/model-selection.ts`
 * and `views/storage.ts`, and a third byte formatter lived in `components/dialogs.ts`.
 * Keeping a single canonical site avoids the picker, the storage tab, and the
 * eviction dialog drifting from each other when proto enums add new values.
 */

import { ModelCategory } from '@runanywhere/web';
import type { CatalogEntry } from './model-catalog';
export { formatFramework } from '@runanywhere/web';

/**
 * Returns the HTML entity for the emoji shown next to a model row. The
 * return value is an HTML-safe entity ("&#129302;") so it can be inlined
 * inside an innerHTML template without further escaping.
 */
export function modalityEmoji(category: ModelCategory): string {
  switch (category) {
    case ModelCategory.MODEL_CATEGORY_LANGUAGE:
      return '&#129302;';
    case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
      return '&#128065;';
    case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
      return '&#127908;';
    case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
      return '&#128266;';
    case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
      return '&#128483;';
    case ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:
      return '&#127912;';
    case ModelCategory.MODEL_CATEGORY_EMBEDDING:
      return '&#128279;';
    default:
      return '&#9881;&#65039;';
  }
}

/**
 * Decimal byte formatter ("GB" / "MB" / "KB"). Aligns with how model
 * catalogs advertise file sizes (1 GB = 10^9 bytes) and with the eviction
 * dialog's storage gauge, both of which run against model catalog byte inputs.
 */
export function formatBytes(bytes: number): string {
  if (bytes >= 1_000_000_000) return `${(bytes / 1_000_000_000).toFixed(1)} GB`;
  if (bytes >= 1_000_000) return `${Math.round(bytes / 1_000_000)} MB`;
  return `${Math.round(bytes / 1_000)} KB`;
}

export function modelDisplaySizeBytes(model: {
  downloadSizeBytes?: number;
  memoryRequiredBytes?: number;
}): number {
  return model.downloadSizeBytes && model.downloadSizeBytes > 0
    ? model.downloadSizeBytes
    : model.memoryRequiredBytes ?? 0;
}

const BACKEND_FORMAT_TOKENS = new Set(['(ONNX)', '(GGUF)', '(MLX)']);

/**
 * Consumer-facing model name with quantization/technical suffixes stripped
 * (e.g. "SmolLM2 360M Q8_0" → "SmolLM2 360M", "Qwen3 4B Q4_K_M" → "Qwen3 4B").
 * Pure string cleanup — never changes which model an id refers to.
 */
export function cleanModelName(name: string): string {
  return name
    .split(/\s+/)
    .filter((token) => !BACKEND_FORMAT_TOKENS.has(token.toUpperCase()))
    .join(' ')
    // Quant tokens: Q8_0, Q4_K_M, Q6_K, F16, BF16, DWQ, 4bit/8-bit, int8…
    .replace(/\b(?:Q\d+(?:_[A-Z0-9]+)*|BF16|F16|F32|DWQ|INT[48]|\d+\s?-?bits?)\b/gi, '')
    // Collapse leftover separators/whitespace from the removal.
    .replace(/\s{2,}/g, ' ')
    .replace(/[\s\-·(]+$/g, '')
    .trim();
}

// ---------------------------------------------------------------------------
// Consumer tags — minimal, plain-language pills. Deliberately hides all
// technical detail (quantization, context length, inference backend). A card
// shows AT MOST two pills: one intelligence/size "feel" and, only when notable,
// one capability. Kept pure so any view shares the same vocabulary.
// ---------------------------------------------------------------------------

/**
 * The visual family a tag belongs to. The picker maps each kind to a distinct
 * pill color so users can scan "how it feels" vs. "what it can do" at a glance.
 */
export type ConsumerTagKind = 'feel' | 'capability';

export interface ConsumerTag {
  label: string;
  kind: ConsumerTagKind;
}

/** Intelligence/size feel — exactly one per model. */
export type ModelFeel = 'Fast' | 'Balanced' | 'Smart';

/** Notable capability — at most one per model, only when it stands out. */
export type ModelCapability = 'Great for tools' | 'Thinks' | 'Vision' | 'Voice' | 'Documents';

const GB = 1_000_000_000;

/**
 * At most two consumer tags: the feel first, then one capability when notable.
 * Never surfaces size class, quant, or backend text.
 */
export function consumerTags(entry: CatalogEntry): ConsumerTag[] {
  const tags: ConsumerTag[] = [{ label: modelFeel(entry), kind: 'feel' }];
  const capability = modelCapability(entry);
  if (capability) tags.push({ label: capability, kind: 'capability' });
  return tags;
}

/**
 * Intelligence/size feel from the parameter count in the name (e.g. "0.6B",
 * "360M"), falling back to advertised bytes. <0.7B → Fast, <2B → Balanced,
 * otherwise Smart.
 */
export function modelFeel(entry: CatalogEntry): ModelFeel {
  const params = parseParamBillions(entry.name);
  const billions = params ?? bytesToApproxParams(modelDisplaySizeBytes(entry));
  if (billions < 0.7) return 'Fast';
  if (billions < 2) return 'Balanced';
  return 'Smart';
}

/**
 * The single most notable capability, or `null` when nothing stands out.
 * Tool-calling and thinking win over modality tags because they are the
 * differentiators a consumer cares about when picking a chat model.
 */
export function modelCapability(entry: CatalogEntry): ModelCapability | null {
  const haystack = `${entry.id} ${entry.name}`.toLowerCase();
  if (haystack.includes('tool')) return 'Great for tools';
  if (entry.supportsThinking) return 'Thinks';
  return categoryCapability(entry.category);
}

function categoryCapability(category: ModelCategory): ModelCapability | null {
  switch (category) {
    case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
      return 'Vision';
    case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
    case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
      return 'Voice';
    case ModelCategory.MODEL_CATEGORY_EMBEDDING:
      return 'Documents';
    default:
      return null;
  }
}

/** Extract a parameter count in billions from strings like "4B" / "360M". */
function parseParamBillions(name: string): number | null {
  const match = name.match(/(\d+(?:\.\d+)?)\s*([bm])\b/i);
  if (!match) return null;
  const value = Number.parseFloat(match[1]);
  if (!Number.isFinite(value)) return null;
  return match[2].toLowerCase() === 'b' ? value : value / 1000;
}

/** Very rough params-from-bytes estimate for entries lacking a name hint. */
function bytesToApproxParams(bytes: number): number {
  return bytes / GB;
}

// ---------------------------------------------------------------------------
// Model organisations — group catalog entries by publisher (NVIDIA, Meta, …)
// so the picker shows one card per org and reveals every model on tap.
// Matches Android ModelTaxonomy / iOS ModelOrgCatalog. Pure, name/id-driven.
// ---------------------------------------------------------------------------

export interface ModelOrg {
  /** Stable key (e.g. "nvidia"). Declaration order = picker order. */
  key: string;
  /** Consumer-facing display name (e.g. "NVIDIA"). */
  name: string;
}

/**
 * Ordered org matchers. Each tests the lowercased "id + name" haystack; the
 * first match wins. NVIDIA precedes llama so Nemotron stays NVIDIA; deepseek
 * precedes qwen so R1 distills stay DeepSeek.
 */
const ORG_MATCHERS: ReadonlyArray<{
  key: string;
  name: string;
  test: RegExp;
}> = [
  {
    key: 'nvidia',
    name: 'NVIDIA',
    test: /nemotron|nemoguard|cosmos|canary|parakeet|nv[_-]embed|nv_rerank|nvidia/,
  },
  { key: 'deepseek', name: 'DeepSeek', test: /deepseek/ },
  { key: 'prism', name: 'Prism', test: /bonsai|prismml|prism-?ml/ },
  { key: 'microsoft', name: 'Microsoft', test: /\bphi\b/ },
  { key: 'google', name: 'Google', test: /gemma|embeddinggemma|siglip/ },
  { key: 'meta', name: 'Meta', test: /llama/ },
  { key: 'alibaba', name: 'Alibaba', test: /qwen/ },
  { key: 'liquid', name: 'Liquid AI', test: /lfm2/ },
  { key: 'mistral', name: 'Mistral AI', test: /mistral/ },
  { key: 'hugging-face', name: 'Hugging Face', test: /smollm|smolvlm/ },
  { key: 'openai', name: 'OpenAI', test: /whisper/ },
  {
    key: 'open-source',
    name: 'Open source',
    test: /internvl|lama_dilated|moonshine|melo|kokoro|kitten|piper|vits|silero|vad|minilm|soprano|pocket-tts|glm-asr/,
  },
];

const FALLBACK_ORG: ModelOrg = {
  key: 'open-source',
  name: 'Open source',
};

/** Derive the publisher organisation for a catalog entry. Never throws. */
export function modelOrg(entry: CatalogEntry): ModelOrg {
  const haystack = `${entry.id} ${entry.name}`.toLowerCase();
  const match = ORG_MATCHERS.find((org) => org.test.test(haystack));
  return match ? { key: match.key, name: match.name } : FALLBACK_ORG;
}

/**
 * A friendly, quant-free size feel for a single variant, used when a family is
 * expanded so the user compares options by experience, not by quant string.
 */
export function variantSizeFeel(entry: CatalogEntry): string {
  const bytes = modelDisplaySizeBytes(entry);
  if (bytes < 0.35 * GB) return 'Smallest · fastest';
  if (bytes < 0.7 * GB) return 'Smaller · faster';
  if (bytes < 1.5 * GB) return 'Balanced';
  return 'Larger · smarter';
}
