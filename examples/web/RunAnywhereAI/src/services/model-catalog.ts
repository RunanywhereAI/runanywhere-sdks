/**
 * Model Catalog — example-app catalog seeded through the SDK's
 * `RunAnywhere.registerModel*` facades.
 *
 * Mirrors iOS `ModelCatalogBootstrap.registerAll()`
 * (examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/ModelCatalogBootstrap.swift)
 * — same IDs, quantizations, and artifact hosts. Proto-message assembly (full
 * `ModelInfo`, `MultiFileArtifact`, `ExpectedModelFiles`) is delegated to the
 * SDK facade. Per AGENTS.md, example apps must not hand-construct
 * cross-cutting proto types — that is SDK business logic.
 *
 * Catalog seeding is best-effort. If the proto registry adapter is not
 * installed yet (e.g. backend WASM still loading) the SDK facade throws
 * `SDKException(BackendNotAvailable)`; we log and continue so the app shell
 * still renders.
 *
 * iOS entries deliberately OMITTED from the Web catalog (WASM 32-bit heap is
 * capped at 4 GB and a single ArrayBuffer download must fit in memory, so
 * multi-GB GGUFs are not practical in the browser):
 *   - llama-2-7b-chat-q4_k_m        (~4.0 GB memory)
 *   - mistral-7b-instruct-q4_k_m    (~4.0 GB memory)
 *   - qwen2.5-1.5b-instruct-q4_k_m  (~2.5 GB memory)
 *   - lfm2-350m-q8_0                (near-duplicate of lfm2-350m-q4_k_m; list kept small)
 *   - lfm2.5-1.2b-instruct-q4_k_m   (~0.9 GB memory; list kept small)
 *   - lfm2-1.2b-tool-q4_k_m / -q8_0 (~0.8-1.4 GB memory)
 *   - qwen3-1.7b-q4_k_m             (~1.2 GB memory; qwen3-0.6b covers thinking demo)
 *   - llama-3.2-3b-instruct-q4_k_m  (~2.0 GB memory)
 *   - qwen2-vl-2b-instruct-q4_k_m   (VLM, ~1.8 GB memory; Qwen2-VL also needs
 *     the CPU-WASM fallback on WebGPU — see AGENTS.md "Web Qwen2-VL WebGPU
 *     workaround")
 */

import {
  RunAnywhere,
  type LoraAdapterCatalogEntry,
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
  supportsLora?: boolean;
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
    // iOS parity: ModelCatalogBootstrap.swift:29-35
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
    // iOS parity: ModelCatalogBootstrap.swift:50-59 — Q6_K quant, base model
    // of the seeded abliterated LoRA adapter, hence supportsLora.
    id: 'qwen2.5-0.5b-instruct-q6_k',
    name: 'Qwen 2.5 0.5B Instruct Q6_K',
    description: 'Compact instruction LLM; base model of the abliterated LoRA adapter.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
    downloadSizeBytes: 505_000_000,
    memoryRequiredBytes: 600_000_000,
    contextLength: 4096,
    supportsLora: true,
  },
  {
    // iOS parity: ModelCatalogBootstrap.swift:67-73
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
    // iOS parity: ModelCatalogBootstrap.swift:102-109
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
    // iOS parity: ModelCatalogBootstrap.swift:118-125
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
    // Web-only entry (not in the iOS catalog): smallest available VLM, kept
    // for WASM memory headroom on low-RAM devices and quick demo turnaround.
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
  {
    // iOS parity: ModelCatalogBootstrap.swift:136-145 (archive, tar.gz)
    id: 'smolvlm-500m-instruct-q8_0',
    name: 'SmolVLM 500M Instruct',
    description: 'SmolVLM 500M vision-language model packaged as a tar.gz archive.',
    category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz',
    downloadSizeBytes: 600_000_000,
    memoryRequiredBytes: 600_000_000,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
    contextLength: 2048,
  },
  {
    // iOS parity: ModelCatalogBootstrap.swift:159-171 (multi-file)
    id: 'lfm2-vl-450m-q8_0',
    name: 'LFM2-VL 450M',
    description: 'LiquidAI LFM2-VL vision-language model (primary GGUF + mmproj sidecar).',
    category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
    downloadSizeBytes: 460_000_000,
    memoryRequiredBytes: 600_000_000,
    contextLength: 2048,
    files: [
      {
        url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
        filename: 'LFM2-VL-450M-Q8_0.gguf',
        role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
        // Approximate; iOS registers the same artifact without per-file sizes.
        sizeBytes: 370_000_000,
      },
      {
        url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf',
        filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf',
        role: ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
        // Approximate; iOS registers the same artifact without per-file sizes.
        sizeBytes: 90_000_000,
      },
    ],
  },

  // ---------- Speech Recognition (STT) ----------
  {
    // iOS parity: ModelCatalogBootstrap.swift:175-184 — same GitHub releases host.
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Sherpa Whisper Tiny (ONNX)',
    description: 'English speech-to-text via sherpa-onnx.',
    category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
    downloadSizeBytes: 74_000_000,
    memoryRequiredBytes: 75_000_000,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
  },

  // ---------- Speech Synthesis (TTS) ----------
  {
    // iOS parity: ModelCatalogBootstrap.swift:187-196 — same GitHub releases host.
    id: 'vits-piper-en_US-lessac-medium',
    name: 'Piper TTS (US English - Medium)',
    description: 'Piper VITS text-to-speech, medium quality.',
    category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
    downloadSizeBytes: 60_000_000,
    memoryRequiredBytes: 65_000_000,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
  },
  {
    // iOS parity: ModelCatalogBootstrap.swift:197-206
    id: 'vits-piper-en_GB-alba-medium',
    name: 'Piper TTS (British English)',
    description: 'Piper VITS text-to-speech, British English voice.',
    category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
    downloadSizeBytes: 60_000_000,
    memoryRequiredBytes: 65_000_000,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
  },

  // ---------- VAD ----------
  {
    // iOS parity: ModelCatalogBootstrap.swift:209-221
    id: 'silero-vad',
    name: 'Silero VAD',
    description: 'Lightweight voice activity detector.',
    category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
    // Actual silero_vad.onnx artifact size (verified Content-Length). Feeds the
    // post-finalize download size guard.
    downloadSizeBytes: 2_327_524,
    memoryRequiredBytes: 5_000_000,
  },

  // ---------- Embeddings / RAG ----------
  {
    // iOS parity: ModelCatalogBootstrap.swift:227-237
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
// LoRA adapters — iOS parity: ModelCatalogBootstrap.swift:254-272
// (registerLoraAdapters). `registerArtifact` registers the catalog entry plus
// its downloadable artifact record (no bytes fetched); safe to re-run on
// every cold launch.
// ---------------------------------------------------------------------------

const LORA_ADAPTERS: readonly LoraAdapterCatalogEntry[] = [
  {
    id: 'abliterated-lora',
    name: 'Abliterated LoRA (F16)',
    description: 'Removes refusal behavior — model answers directly without disclaimers',
    url: 'https://huggingface.co/Void2377/qwen-lora-gguf/resolve/main/qwen2.5-0.5b-abliterated-lora-f16.gguf',
    filename: 'qwen2.5-0.5b-abliterated-lora-f16.gguf',
    compatibleModels: ['qwen2.5-0.5b-instruct-q6_k'],
    sizeBytes: 17_620_224,
    defaultScale: 1.0,
    tags: [],
    metadata: {},
  },
];

// ---------------------------------------------------------------------------
// Registration — delegated to the SDK's `RunAnywhere.registerModel*` facades.
// ---------------------------------------------------------------------------

/**
 * Register the full example catalog (models + LoRA adapters) once after SDK
 * initialization — iOS parity: `ModelCatalogBootstrap.registerAll()`
 * (ModelCatalogBootstrap.swift:25-249). Returns the number of model entries
 * successfully registered.
 */
export async function registerAll(): Promise<number> {
  const registered = registerModelCatalog();
  await registerLoraAdapters();
  return registered;
}

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

async function registerLoraAdapters(): Promise<void> {
  for (const adapter of LORA_ADAPTERS) {
    try {
      await RunAnywhere.lora.registerArtifact(adapter);
    } catch (err) {
      console.warn(
        `[model-catalog] registerLoraArtifact(${adapter.id}) failed:`,
        formatError(err),
      );
    }
  }
}

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
      supportsLora: entry.supportsLora,
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
    supportsLora: entry.supportsLora,
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
