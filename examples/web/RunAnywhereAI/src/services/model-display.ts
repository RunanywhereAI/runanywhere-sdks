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
// Model families — group catalog entries into consumer-facing product lines
// (e.g. "Qwen3", "LFM2", "Whisper") so the picker can show one card per family
// and reveal individual variants on tap. Pure, name/id-driven.
// ---------------------------------------------------------------------------

export interface ModelFamily {
  /** Stable key derived from the model id/name (e.g. "qwen3"). */
  key: string;
  /** Consumer-facing display name (e.g. "Qwen3"). */
  name: string;
  /** Friendly one-liner describing what the family is good for. */
  tagline: string;
}

/**
 * Ordered family matchers. Each tests the lowercased "id + name" haystack; the
 * first match wins. Order matters — more specific ids (qwen3, qwen2.5) precede
 * generic ones. A trailing catch-all guarantees every entry lands somewhere.
 */
const FAMILY_MATCHERS: ReadonlyArray<{
  key: string;
  name: string;
  tagline: string;
  test: RegExp;
}> = [
  { key: 'qwen3', name: 'Qwen3', tagline: 'Latest Qwen chat models with a thinking mode.', test: /qwen3/ },
  { key: 'qwen2.5', name: 'Qwen2.5', tagline: 'Compact, capable all-round chat models.', test: /qwen2\.?5/ },
  { key: 'qwen2-vl', name: 'Qwen2-VL', tagline: 'Qwen models that can also see images.', test: /qwen2-?vl/ },
  { key: 'llama', name: 'Llama', tagline: "Meta's versatile open chat models.", test: /llama/ },
  { key: 'lfm2-vl', name: 'LFM2-VL', tagline: 'LiquidAI models that read images and text.', test: /lfm2-?vl/ },
  { key: 'lfm2', name: 'LFM2', tagline: 'LiquidAI models tuned for fast on-device chat.', test: /lfm2/ },
  { key: 'smolvlm', name: 'SmolVLM', tagline: 'Tiny vision-language models for quick demos.', test: /smolvlm/ },
  { key: 'smollm', name: 'SmolLM', tagline: 'Very small, speedy instruction models.', test: /smollm/ },
  { key: 'whisper', name: 'Whisper', tagline: 'Turns speech into text, on device.', test: /whisper/ },
  { key: 'piper', name: 'Piper', tagline: 'Natural-sounding text-to-speech voices.', test: /piper|vits/ },
  { key: 'silero', name: 'Silero', tagline: 'Detects when someone is speaking.', test: /silero|vad/ },
  { key: 'minilm', name: 'MiniLM', tagline: 'Powers document search and memory.', test: /minilm|embedding/ },
];

const FALLBACK_FAMILY: ModelFamily = {
  key: 'other',
  name: 'Other models',
  tagline: 'Additional on-device models.',
};

/** Derive the consumer-facing family for a catalog entry. Never throws. */
export function modelFamily(entry: CatalogEntry): ModelFamily {
  const haystack = `${entry.id} ${entry.name}`.toLowerCase();
  const match = FAMILY_MATCHERS.find((family) => family.test.test(haystack));
  if (!match) return FALLBACK_FAMILY;
  return { key: match.key, name: match.name, tagline: match.tagline };
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
