/**
 * Model Catalog — registers a small fixed catalog of known models with the
 * SDK's proto-byte registry.
 *
 * After the V2 cleanup there is no app-side registration facade. Models are
 * registered directly via `RunAnywhere.modelRegistry.registerModel(...)`, which
 * speaks proto bytes to the commons C++ registry. The entries here are
 * purposefully minimal: canonical `ModelInfo` proto messages populated with
 * just enough fields to drive the model-selection UI and `RunAnywhere.loadModel()`.
 *
 * The catalog is registered best-effort — if the proto registry adapter is
 * not installed (e.g. the llamacpp WASM failed to load on a fresh dev
 * cold-start) the call returns `false` and the app shell still renders.
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
  ModelSource,
} from '@runanywhere/proto-ts/model_types';
import { formatError } from './format-error';

/**
 * A flat, app-local description of a catalog entry that gets promoted to a
 * full proto `ModelInfo` at registration time. Keeping this shape simple
 * means the catalog reads as a declarative list rather than a pile of
 * boilerplate proto messages.
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

/**
 * The fixed catalog registered at app startup. The set here is deliberately
 * a small, representative cross-section — one small LLM that runs in the
 * browser WASM build, one VLM, one STT/TTS/VAD each for when ONNX WASM
 * ships, and one embedding.
 *
 * Other example apps (iOS, Android, Flutter) use a similar shape via their
 * respective registerModel-equivalents; pick the smallest viable model in
 * each modality to keep the example app fast to cold-start.
 */
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
    // pass3-syn-097: parity with Android/iOS/Flutter/RN catalogs.
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
    downloadSizeBytes: 2_100_000,
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
// Registration
// ---------------------------------------------------------------------------

/**
 * Registers the catalog with the proto-byte model registry. Idempotent —
 * re-registration overwrites the previous entry without error, mirroring the
 * behavior in the other example apps.
 *
 * Returns the count of successfully registered entries. `0` means the
 * registry adapter is not installed (typically because no backend WASM has
 * loaded yet).
 */
export function registerModelCatalog(): number {
  const availability = RunAnywhere.modelRegistry.availability();
  if (availability.status !== 'available') {
    console.warn(
      '[model-catalog] proto registry unavailable, skipping registration:',
      availability,
    );
    return 0;
  }

  let registered = 0;
  for (const entry of CATALOG) {
    const info = toModelInfo(entry);
    try {
      if (RunAnywhere.modelRegistry.registerModel(info)) {
        registered += 1;
      } else {
        console.warn(`[model-catalog] register(${entry.id}) returned false`);
      }
    } catch (err) {
      console.warn(
        `[model-catalog] register(${entry.id}) threw:`,
        formatError(err),
      );
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

function toModelInfo(entry: CatalogEntry): ModelInfo {
  const now = Date.now();
  const files = entry.files?.map((file) => ({
    url: file.url,
    filename: file.filename,
    isRequired: file.isRequired ?? true,
    sizeBytes: file.sizeBytes,
    relativePath: file.filename,
    destinationPath: file.filename,
    role: file.role,
  }));
  return {
    id: entry.id,
    name: entry.name,
    category: entry.category,
    format: entry.format,
    framework: entry.framework,
    downloadUrl: entry.downloadUrl,
    localPath: '',
    downloadSizeBytes: entry.downloadSizeBytes,
    contextLength: entry.contextLength ?? 0,
    supportsThinking: entry.supportsThinking ?? false,
    supportsLora: false,
    description: entry.description,
    source: ModelSource.MODEL_SOURCE_REMOTE,
    createdAtUnixMs: now,
    updatedAtUnixMs: now,
    memoryRequiredBytes: entry.memoryRequiredBytes,
    ...(files
      ? {
        multiFile: { files },
        artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE,
        expectedFiles: {
          files,
          rootDirectory: entry.id,
          requiredPatterns: files.map((file) => file.filename),
          optionalPatterns: [],
          description: `${entry.name} primary model and companion artifacts`,
        },
      }
      : {
        artifactType: entry.artifactType ?? ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
      }),
  };
}
