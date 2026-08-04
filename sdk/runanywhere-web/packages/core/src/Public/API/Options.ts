/**
 * Option types of the v3 public API.
 *
 * Every field is optional. Defaults are read from the generated
 * `@runanywhere/proto-ts/convenience/*` helpers, which are produced from the
 * `(runanywhere.v1.rac_default)` annotations in `idl/`. Nothing here restates
 * a default literal.
 */

import type { InferenceFramework, ModelCategory, ModelFormat } from '@runanywhere/proto-ts/model_types';
import type { ToolDefinition } from '@runanywhere/proto-ts/tool_calling';
import { lLMGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/llm_options_convenience';
import { sTTOptionsDefaults } from '@runanywhere/proto-ts/convenience/stt_options_convenience';
import { tTSOptionsDefaults } from '@runanywhere/proto-ts/convenience/tts_options_convenience';
import { vADOptionsDefaults } from '@runanywhere/proto-ts/convenience/vad_options_convenience';
import { embeddingsOptionsDefaults } from '@runanywhere/proto-ts/convenience/embeddings_options_convenience';
import { diffusionGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/diffusion_options_convenience';
import { diarizationOptionsDefaults } from '@runanywhere/proto-ts/convenience/diarization_convenience';
import { rAGConfigurationDefaults } from '@runanywhere/proto-ts/convenience/rag_convenience';
import { storageDefaults } from '@runanywhere/proto-ts/defaults/pool';
import type { ImageInput } from './Inputs.js';

/** Whether the model may think before answering, and whether we surface it. */
export interface ReasoningOptions {
  /** `off` suppresses thinking entirely. */
  mode?: 'on' | 'off';
  /** `true` streams thought tokens to the caller. */
  includeInOutput?: boolean;
  /** Thinking-tag pattern; unset uses the model's own tags. */
  pattern?: string;
}

/** JSON Schema the model must satisfy. */
export interface JsonSchema {
  /** The schema, serialized as JSON. */
  json: string;
  /** Optional parser applied to the model's output. */
  parse?: (text: string) => unknown;
}

/** Force the model's output to satisfy a schema. */
export interface StructuredOutput {
  schema: JsonSchema;
  strict?: boolean;
}

/** How the model may use registered tools. */
export type ToolChoice =
  | { kind: 'auto' }
  | { kind: 'none' }
  | { kind: 'required' }
  | { kind: 'forced'; name: string };

/** Generation knobs shared by `llm`, `vlm`, and RAG answer generation. */
export interface LlmOptions {
  /** Model slug; an absent model auto-loads, downloading if needed. */
  model?: string;
  maxOutputTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  minP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
  repetitionPenalty?: number;
  seed?: number;
  stopSequences?: string[];
  systemPrompt?: string;
  reasoning?: ReasoningOptions;
  structuredOutput?: StructuredOutput;
  /** Empty uses the tool registry. */
  tools?: ToolDefinition[];
  toolChoice?: ToolChoice;
  maxToolCalls?: number;
  /**
   * Whether the SDK should run a requested tool call itself and feed the
   * result back into the loop. `false` returns the parsed call to the
   * caller instead of invoking it. Defaults to `true` -- same contract as
   * the direct `toolCalling.generateWithTools` API's `autoExecute`, just
   * reachable from `llm.generate`/`llm.generateStream` with inline `tools`.
   */
  autoExecute?: boolean;
  /** Stable conversation id for backends that keep a prompt cache. */
  conversationId?: string;
}

/** Transcription knobs. */
export interface SttOptions {
  /** BCP-47 tag; unset auto-detects. */
  language?: string;
  punctuation?: boolean;
  wordTimestamps?: boolean;
  diarization?: boolean;
  maxSpeakers?: number;
  translateToEnglish?: boolean;
}

/** Synthesis knobs. */
export interface TtsOptions {
  voice?: string;
  language?: string;
  speed?: number;
  pitch?: number;
  format?: 'pcm' | 'pcm16' | 'wav';
  sampleRate?: number;
}

/** Speech-detection knobs. */
export interface VadOptions {
  /** Unset uses the model's calibrated default. */
  activationThreshold?: number;
  minSpeechMs?: number;
  minSilenceMs?: number;
  prefixPaddingMs?: number;
}

/** Embedding knobs. */
export interface EmbedOptions {
  /** Model slug of the embedding model to use. */
  model?: string;
  normalize?: 'none' | 'l2';
  pooling?: 'mean' | 'cls' | 'max';
}

/** Whether to generate from scratch or repaint a masked region. */
export type ImageMode =
  | { kind: 'generate' }
  | { kind: 'inpaint'; input: Uint8Array; mask: Uint8Array };

/** Image-generation knobs. */
export interface ImageOptions {
  negativePrompt?: string;
  width?: number;
  height?: number;
  steps?: number;
  guidanceScale?: number;
  seed?: number;
  mode?: ImageMode;
  reportPartials?: boolean;
}

/** Speaker-diarization knobs. */
export interface DiarizationOptions {
  threshold?: number;
  minimumDurationMs?: number;
  mergeGapMs?: number;
}

/** Semantic-segmentation knobs. */
export interface SegmentationOptions {
  includeDiagnosticImage?: boolean;
}

/** Turn-taking knobs of a voice session. */
export interface TurnHandlingOptions {
  endpointing?: { minDelayMs?: number; maxDelayMs?: number };
  interruption?: { enabled?: boolean; minDurationMs?: number };
}

/** Retrieval and chunking knobs of a RAG session. */
export interface RagConfig {
  topK?: number;
  chunkSize?: number;
  chunkOverlap?: number;
  similarityThreshold?: number;
  /** Directory under the persistent storage root that holds the index. */
  persistPath?: string;
}

/** Placement knobs applied when a model is loaded. */
export interface LoadOptions {
  /** Engine pin, honored at load time only. */
  framework?: InferenceFramework;
  contextLength?: number;
  threads?: number;
  useGpu?: boolean;
  /** Reload even when the model is already resident. */
  forceReload?: boolean;
}

/** Narrow `models.list` to a subset of the catalog. */
export interface ModelFilter {
  category?: ModelCategory;
  framework?: InferenceFramework;
  format?: ModelFormat;
  downloadedOnly?: boolean;
  availableOnly?: boolean;
  maxSizeBytes?: number;
  search?: string;
}

/** One artifact of a multi-file model registration. */
export interface ModelFileRegistration {
  url: string;
  filename: string;
  /** Role hint; unset lets commons classify the filename. */
  role?:
    | 'primary'
    | 'companion'
    | 'projector'
    | 'tokenizer'
    | 'config'
    | 'vocabulary'
    | 'merges'
    | 'labels';
  sizeBytes?: number;
  /** Whether the download must fail when this file is missing. Defaults to `true`. */
  isRequired?: boolean;
}

/** Declarative description of a model to add to the catalog. */
export interface ModelRegistration {
  id?: string;
  name: string;
  framework: InferenceFramework;
  category?: ModelCategory;
  format?: ModelFormat;
  description?: string;
  /** Single-file or archive download source. */
  url?: string;
  /** Multi-file artifact list; mutually exclusive with `url`. */
  files?: readonly ModelFileRegistration[];
  /** Set when `url` points at a `.tar.gz` or `.zip`. */
  archive?: 'tarGz' | 'zip';
  sizeBytes?: number;
  /** Peak resident memory the model needs, used by compatibility gates. */
  memoryRequiredBytes?: number;
  contextLength?: number;
  supportsThinking?: boolean;
  supportsLora?: boolean;
  /**
   * Computer-Use-Agent profile id (e.g. `'fara'`) for a CUA-capable model.
   * Lands on `ModelInfo.cuaProfile` so callers can discover which registered
   * models are drivable through `RunAnywhere.cua`.
   */
  cuaProfile?: string;
}

/**
 * Default values of every option block, read from the IDL-generated
 * convenience helpers.
 */
export const optionDefaults = {
  llm: lLMGenerationOptionsDefaults,
  stt: sTTOptionsDefaults,
  tts: tTSOptionsDefaults,
  vad: vADOptionsDefaults,
  embed: embeddingsOptionsDefaults,
  image: diffusionGenerationOptionsDefaults,
  diarization: diarizationOptionsDefaults,
  rag: rAGConfigurationDefaults,
  contextLength: storageDefaults.contextLength,
} as const;

/** Options accepted by [ImageOptions.mode] inpainting, without the tag. */
export type InpaintSource = Extract<ImageMode, { kind: 'inpaint' }>;

/** Wrap a mask pair as an inpaint mode. */
export function inpaintMode(input: Uint8Array, mask: Uint8Array): ImageMode {
  return { kind: 'inpaint', input, mask };
}

/** Image payloads accepted by [segmentation.segment]. */
export type SegmentationInput = ImageInput;
