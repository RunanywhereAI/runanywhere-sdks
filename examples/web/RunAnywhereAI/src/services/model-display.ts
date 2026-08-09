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
// Type-only: the mapping below names glyphs, it does not draw them, so this
// service still has no runtime dependency on the component layer.
import type { IconName } from '../components/icons';
export { formatFramework } from '@runanywhere/web';

/**
 * The glyph that stands for a model's modality, everywhere a model is listed.
 *
 * WAS AN EMOJI. Every model row, family card, recommendation card and pipeline
 * slot carried one of 🤖 👁 🎤 🔊 🗣 🎨 🔗 ⚙️ — eight emoji rendered by the OS,
 * so the avatar column was a different typeface, weight, and colour on every
 * platform, ignored the theme entirely, and sat beside a UI drawn in 1.5px
 * outline strokes. Emoji also cannot inherit `currentColor`, so a row could not
 * dim its own avatar when the row was disabled.
 *
 * The mapping mirrors iOS `ModelCategory.consumerCapabilityIcon`
 * (Features/Models/ModelPresentation.swift) one-for-one, so the same model shows
 * the same idea on both platforms: message for chat, a picture for vision, a
 * waveform for speech-in, a speaker for speech-out, two people for diarization.
 *
 * Returns the name only — the caller renders it with `icon()` at the size its
 * slot wants, which is why this can live beside the other display helpers
 * instead of inside the glyph registry.
 */
export function modalityIcon(category: ModelCategory): IconName {
  switch (category) {
    case ModelCategory.MODEL_CATEGORY_LANGUAGE:
      return 'message';
    case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
    case ModelCategory.MODEL_CATEGORY_VISION:
      return 'image';
    case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
      return 'waveform';
    case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
      return 'speaker';
    case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
      return 'pulse';
    case ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION:
      return 'speakers';
    case ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION:
      return 'segments';
    case ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:
      return 'imageSparkle';
    // An embedding model exists to make a corpus searchable, which is the same
    // meaning `file` already carries ("files indexed for retrieval") — not a
    // second meaning borrowing the glyph.
    case ModelCategory.MODEL_CATEGORY_EMBEDDING:
      return 'file';
    default:
      return 'model';
  }
}

const KIB = 1024;
const MIB = KIB * 1024;
const GIB = MIB * 1024;

/**
 * A byte quantity the user is meant to compare against their disk — a model's
 * advertised size, the origin's quota, a free-space figure.
 *
 * WAS DECIMAL (1 GB = 10^9) on the argument that model catalogs advertise their
 * files that way. Both other apps read the very same catalog bytes with binary
 * prefixes — iOS `ByteCountFormatter(countStyle: .memory)`, Android
 * `formatModelSize` — so one model claimed "4.4 GB" here and "4.10 GB" there:
 * a third of a gigabyte of apparent disagreement about a single file. Which
 * convention wins matters far less than the four apps sharing one, and the two
 * that already agreed set it.
 *
 * Precision mirrors Android's explicit rule (two decimals once past a gigabyte,
 * none below) rather than being re-invented here.
 */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 KB';
  if (bytes >= GIB) return `${(bytes / GIB).toFixed(2)} GB`;
  if (bytes >= MIB) return `${Math.round(bytes / MIB)} MB`;
  return `${Math.round(bytes / KIB)} KB`;
}

/**
 * The size shown on a model row, including the case where there isn't one.
 *
 * A catalog entry can arrive with no advertised bytes (a gated Hugging Face
 * repo, a built-in). `formatBytes` would render that as "0 KB", which reads as
 * a free download rather than as an unknown one. Mirrors iOS
 * `RAModelInfo.consumerSizeLabel`.
 */
export function formatModelSize(bytes: number): string {
  return Number.isFinite(bytes) && bytes > 0 ? formatBytes(bytes) : 'Size unknown';
}

/**
 * A byte quantity inside a live transfer readout — the counter and the rate.
 *
 * Deliberately a second formatter rather than a reuse of `formatBytes`: this one
 * ticks several times a second, so it trades the advertised size's precision for
 * a number that does not jitter between renders. One decimal from a megabyte up,
 * none below, byte-for-byte the same rule as iOS `ModelDownloadProgress.formatBytes`
 * and Android `DownloadProgressInfo.formatBytes`.
 */
export function formatTransferBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  if (bytes >= GIB) return `${(bytes / GIB).toFixed(1)} GB`;
  if (bytes >= MIB) return `${(bytes / MIB).toFixed(1)} MB`;
  if (bytes >= KIB) return `${Math.round(bytes / KIB)} KB`;
  return `${Math.round(bytes)} B`;
}

/**
 * Coarse remaining time — "45s", "2m 15s", "1h 20m". Seconds are dropped past
 * an hour, where they are noise. Same rule as iOS/Android `formatDuration`.
 */
export function formatDuration(seconds: number): string {
  // A derived ETA can arrive as NaN or Infinity, and both survive the arithmetic
  // below to render as a label ("NaNs", "Infinityh NaNm"). Callers that cannot
  // measure a remaining time should omit the part entirely — this floor only
  // guarantees the helper never emits one of those.
  if (!Number.isFinite(seconds)) return '0s';
  const total = Math.max(0, Math.round(seconds));
  if (total >= 3600) return `${Math.floor(total / 3600)}h ${Math.floor((total % 3600) / 60)}m`;
  if (total >= 60) return `${Math.floor(total / 60)}m ${total % 60}s`;
  return `${total}s`;
}

/** What is known about a transfer right now. Every field is absent, not zero,
 * when it has not been measured — so the line omits a part instead of claiming
 * "0 B/s" while the connection is still opening. */
export interface TransferSnapshot {
  bytesDone?: number;
  bytesTotal?: number;
  bytesPerSecond?: number;
  etaSeconds?: number;
}

/**
 * The one line of detail under a progress bar: "1.2 GB of 4.1 GB · 3.4 MB/s ·
 * 2m 15s left", or as much of it as is actually known.
 *
 * Ordered by what a waiting user looks for first — how much is left, then how
 * fast, then when it will be done — identically to iOS `detailLine` and Android
 * `DownloadProgressInfo.detailLine`, so the same transfer reads the same
 * sentence on all three. Empty before the first byte lands, which is the
 * caller's cue to say "Starting…" rather than "0 B".
 */
export function transferDetailLine(transfer: TransferSnapshot): string {
  const parts: string[] = [];

  const { bytesDone, bytesTotal, bytesPerSecond, etaSeconds } = transfer;
  if (bytesTotal !== undefined && bytesTotal > 0 && bytesDone !== undefined) {
    parts.push(`${formatTransferBytes(bytesDone)} of ${formatTransferBytes(bytesTotal)}`);
  } else if (bytesDone !== undefined && bytesDone > 0) {
    // No total: report what has arrived rather than inventing a denominator.
    parts.push(formatTransferBytes(bytesDone));
  }

  if (bytesPerSecond !== undefined && bytesPerSecond > 0) {
    parts.push(`${formatTransferBytes(bytesPerSecond)}/s`);
  }
  // `>= 1` alone lets `Infinity` through — an unmeasurable ETA belongs in the
  // same bucket as an absent one, which this line drops rather than renders.
  if (etaSeconds !== undefined && Number.isFinite(etaSeconds) && etaSeconds >= 1) {
    parts.push(`${formatDuration(etaSeconds)} left`);
  }

  return parts.join(' · ');
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
