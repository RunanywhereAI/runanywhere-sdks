/**
 * Model Catalog — example-app catalog seeded through the SDK's
 * `RunAnywhere.registerModel*` facades.
 *
 * Mirrors the iOS / Android / Flutter / RN example apps, which all delegate
 * proto-message assembly (full `ModelInfo`, `MultiFileArtifact`,
 * `ExpectedModelFiles`) to the SDK facade. Per AGENTS.md, example apps must
 * not hand-construct cross-cutting proto types — that is SDK business logic.
 *
 * Catalog seeding is best-effort. If the proto registry adapter is not
 * installed yet (e.g. backend WASM still loading) the SDK facade throws
 * `SDKException(BackendNotAvailable)`; we log and continue so the app shell
 * still renders.
 */

import {
  RunAnywhere,
  type ModelInfo,
} from '@runanywhere/web';
import {
  InferenceFramework,
  ModelArtifactType,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
} from '@runanywhere/proto-ts/model_types';
import { formatError } from './format-error';

/**
 * Declarative description of a single catalog entry. Promoted to a full
 * `ModelInfo` proto by the SDK's `RunAnywhere.registerModel*` facades — never
 * by this file. Kept as a flat shape so the catalog list reads as data.
 */
export interface CatalogEntry {
  id: string;
  name: string;
  description: string;
  category: ModelCategory;
  framework: InferenceFramework;
  format: ModelFormat;
  downloadUrl: string;
  downloadSizeBytes: number;
  memoryRequiredBytes: number;
  artifactType?: ModelArtifactType;
  contextLength?: number;
  supportsThinking?: boolean;
  files?: readonly CatalogFileEntry[];
}

export interface CatalogFileEntry {
  url: string;
  filename: string;
  role: ModelFileRole;
  sizeBytes: number;
  isRequired?: boolean;
}

const CATALOG: readonly CatalogEntry[] = [
  // ---------- Language (LLM) ----------
  {
    id: 'smollm2-360m-q8_0',
    name: 'SmolLM2 360M Q8_0',
    description: 'Small instruction-tuned LLM that runs in the WASM build.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
    downloadSizeBytes: 386_404_416,
    memoryRequiredBytes: 500_000_000,
    contextLength: 2048,
  },
  {
    id: 'qwen2.5-0.5b-instruct-q8_0',
    name: 'Qwen2.5 0.5B Instruct Q8_0',
    description: 'Compact instruction LLM, ~500 MB on disk.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q8_0.gguf',
    downloadSizeBytes: 530_000_000,
    memoryRequiredBytes: 700_000_000,
    contextLength: 4096,
  },
  {
    id: 'tinyllama-1.1b-chat-q4_k_m',
    name: 'TinyLlama 1.1B Chat Q4_K_M',
    description: 'Small chat model with light 4-bit quantization.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
    downloadSizeBytes: 670_000_000,
    memoryRequiredBytes: 1_100_000_000,
    contextLength: 2048,
  },
  {
    id: 'lfm2-350m-q4_k_m',
    name: 'LiquidAI LFM2 350M Q4_K_M',
    description: 'LiquidAI compact LLM tuned for fast on-device chat.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
    downloadSizeBytes: 250_000_000,
    memoryRequiredBytes: 250_000_000,
    contextLength: 2048,
  },
  {
    id: 'qwen3-0.6b-q4_k_m',
    name: 'Qwen3 0.6B Q4_K_M',
    description: 'Qwen3 series compact LLM with thinking-mode support.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
    downloadSizeBytes: 477_000_000,
    memoryRequiredBytes: 500_000_000,
    contextLength: 4096,
    supportsThinking: true,
  },
  {
    // Parity with Android/iOS/Flutter/RN catalogs.
    id: 'qwen3-4b-q4_k_m',
    name: 'Qwen3 4B Q4_K_M',
    description: 'Qwen3 series larger LLM with thinking-mode support.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
    downloadSizeBytes: 2_500_000_000,
    memoryRequiredBytes: 3_000_000_000,
    contextLength: 4096,
    supportsThinking: true,
  },

  // ---------- Multimodal (VLM) ----------
  {
    id: 'smolvlm2-256m-video-instruct-q8_0',
    name: 'SmolVLM2 256M Video Instruct Q8_0',
    description: 'Small vision-language model with primary GGUF and mmproj sidecar.',
    category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
    downloadSizeBytes: 278_828_032,
    memoryRequiredBytes: 420_000_000,
    contextLength: 2048,
    files: [
      {
        url: 'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
        filename: 'SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
        role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
        sizeBytes: 175_056_352,
      },
      {
        url: 'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
        filename: 'mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
        role: ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
        sizeBytes: 103_771_680,
      },
    ],
  },

  // ---------- Speech Recognition (STT) ----------
  {
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Whisper Tiny English',
    description: 'English speech-to-text via sherpa-onnx.',
    category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://huggingface.co/runanywhere/sherpa-onnx-whisper-tiny.en/resolve/main/sherpa-onnx-whisper-tiny.en.tar.gz',
    downloadSizeBytes: 74_000_000,
    memoryRequiredBytes: 105_000_000,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
  },

  // ---------- Speech Synthesis (TTS) ----------
  {
    id: 'vits-piper-en_US-lessac-medium',
    name: 'Piper TTS US English (Lessac)',
    description: 'Piper VITS text-to-speech, medium quality.',
    category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://huggingface.co/runanywhere/vits-piper-en_US-lessac-medium/resolve/main/vits-piper-en_US-lessac-medium.tar.gz',
    downloadSizeBytes: 60_000_000,
    memoryRequiredBytes: 65_000_000,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
  },

  // ---------- VAD ----------
  {
    id: 'silero-vad',
    name: 'Silero VAD',
    description: 'Lightweight voice activity detector.',
    category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://raw.githubusercontent.com/snakers4/silero-vad/master/src/silero_vad/data/silero_vad.onnx',
    // Actual silero_vad.onnx artifact size (verified Content-Length). Feeds the
    // post-finalize download size guard.
    downloadSizeBytes: 2_327_524,
    memoryRequiredBytes: 5_000_000,
  },

  // ---------- Embeddings / RAG ----------
  {
    id: 'all-minilm-l6-v2',
    name: 'All MiniLM L6 v2',
    description: 'Small ONNX embedding model used by the native RAG pipeline.',
    category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
    downloadSizeBytes: 25_500_000,
    memoryRequiredBytes: 25_500_000,
    files: [
      {
        url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
        filename: 'model.onnx',
        role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
        sizeBytes: 22_700_000,
      },
      {
        url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt',
        filename: 'vocab.txt',
        role: ModelFileRole.MODEL_FILE_ROLE_VOCABULARY,
        sizeBytes: 232_000,
      },
    ],
  },
];

// ---------------------------------------------------------------------------
// Registration — delegated to the SDK's `RunAnywhere.registerModel*` facades.
// ---------------------------------------------------------------------------

/**
 * Seed the catalog through the SDK facade. Multi-file entries go to
 * `registerModelMultiFile`, archive entries to `registerModelArchive`, and
 * single-file entries to `registerModel`. Returns the count successfully
 * registered. `0` means the registry adapter is not installed yet (typically
 * because no backend WASM has loaded).
 */
export function registerModelCatalog(): number {
  let registered = 0;
  for (const entry of CATALOG) {
    if (tryRegister(entry)) {
      registered += 1;
    }
  }

  if (registered !== CATALOG.length) {
    console.warn(
      `[model-catalog] registered ${registered} / ${CATALOG.length} entries`,
    );
  }
  return registered;
}

/** Get the declarative catalog. Safe to call before SDK initialization. */
export function getCatalog(): readonly CatalogEntry[] {
  return CATALOG;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function tryRegister(entry: CatalogEntry): boolean {
  try {
    const result = registerViaFacade(entry);
    return result !== null;
  } catch (err) {
    console.warn(
      `[model-catalog] register(${entry.id}) threw:`,
      formatError(err),
    );
    return false;
  }
}

function registerViaFacade(entry: CatalogEntry): ModelInfo | null {
  if (entry.files && entry.files.length > 0) {
    return RunAnywhere.registerModelMultiFile({
      id: entry.id,
      name: entry.name,
      framework: entry.framework,
      files: entry.files,
      description: entry.description,
      format: entry.format,
      modality: entry.category,
      memoryRequirement: entry.memoryRequiredBytes,
      downloadSizeBytes: entry.downloadSizeBytes,
      contextLength: entry.contextLength,
      supportsThinking: entry.supportsThinking,
    });
  }

  const options = {
    id: entry.id,
    description: entry.description,
    format: entry.format,
    modality: entry.category,
    memoryRequirement: entry.memoryRequiredBytes,
    downloadSizeBytes: entry.downloadSizeBytes,
    contextLength: entry.contextLength,
    supportsThinking: entry.supportsThinking,
  };

  if (entry.artifactType && entry.artifactType !== ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE) {
    return RunAnywhere.registerModelArchive(
      entry.downloadUrl,
      entry.name,
      entry.framework,
      entry.artifactType,
      options,
    );
  }

  return RunAnywhere.registerModel(
    entry.downloadUrl,
    entry.name,
    entry.framework,
    options,
  );
}
