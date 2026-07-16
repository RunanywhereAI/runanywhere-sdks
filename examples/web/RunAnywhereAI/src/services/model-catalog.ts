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
import { appLogger } from './app-logger';

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

/**
 * Browser-runtime compatibility is separate from model-format compatibility:
 * a GGUF may be valid for the PrismML llama.cpp backend while still being too
 * large for the WebAssembly 32-bit address space once runtime/KV overhead is
 * included. Keep this typed so every Web consumer renders the same reason.
 */
export enum WebModelCompatibilityCode {
  WASM32_ADDRESS_SPACE = 'wasm32-address-space',
}

export type WebModelCompatibility =
  | { supported: true }
  | {
      supported: false;
      code: WebModelCompatibilityCode;
      reason: string;
      reference?: {
        label: string;
        url: string;
      };
    };

const WASM32_ADDRESS_SPACE_BYTES = 2 ** 32;
const MINIMUM_WASM_RUNTIME_HEADROOM_BYTES = 512 * 1024 * 1024;

const CATALOG: readonly CatalogEntry[] = [
  // ---------- Language (LLM) ----------
  {
    // Preserve the cross-SDK model ID while using the model author's official
    // instruction-tuned artifact; the historical base-model URL cannot
    // reliably follow chat instructions.
    id: 'smollm2-360m-q8_0',
    name: 'SmolLM2 360M Q8_0',
    description: 'Small instruction-tuned LLM that runs in the WASM build.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf',
    downloadSizeBytes: 386_404_992,
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
    downloadSizeBytes: 650_379_104,
    memoryRequiredBytes: 750_000_000,
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
    downloadSizeBytes: 229_309_376,
    memoryRequiredBytes: 300_000_000,
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
    downloadSizeBytes: 396_705_472,
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
    downloadSizeBytes: 2_497_281_312,
    memoryRequiredBytes: 3_000_000_000,
    contextLength: 4096,
    supportsThinking: true,
  },
  {
    // PrismML Bonsai family at 1.125-bit (custom Q1_0 quant, qwen3_5
    // GatedDeltaNet arch). Needs the PrismML llama.cpp fork pinned in
    // sdk/runanywhere-commons/VERSIONS. Unlike the 27B sibling below, this
    // size comfortably clears the WASM 4 GB heap gate with runtime/KV
    // headroom to spare, so it's a normal, fully-usable in-browser entry.
    id: 'bonsai-1.7b-q1_0',
    name: 'Bonsai-1.7B 1-bit Q1_0',
    description: 'PrismML 1-bit 1.7B LLM. Small enough to run comfortably in-browser.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/prism-ml/Bonsai-1.7B-gguf/resolve/main/Bonsai-1.7B-Q1_0.gguf',
    downloadSizeBytes: 248_302_272,
    memoryRequiredBytes: 350_000_000,
    contextLength: 4096,
    supportsThinking: true,
  },
  {
    // PrismML Bonsai family at 1.125-bit — see the 1.7B entry above for the
    // fork/quant details. Also clears the WASM heap gate comfortably.
    id: 'bonsai-4b-q1_0',
    name: 'Bonsai-4B 1-bit Q1_0',
    description: 'PrismML 1-bit 4B LLM. Runs comfortably in-browser.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/prism-ml/Bonsai-4B-gguf/resolve/main/Bonsai-4B-Q1_0.gguf',
    downloadSizeBytes: 572_270_624,
    memoryRequiredBytes: 700_000_000,
    contextLength: 4096,
    supportsThinking: true,
  },
  {
    // PrismML Bonsai family at 1.125-bit — see the 1.7B entry above for the
    // fork/quant details. Also clears the WASM heap gate comfortably.
    id: 'bonsai-8b-q1_0',
    name: 'Bonsai-8B 1-bit Q1_0',
    description: 'PrismML 1-bit 8B LLM. Runs comfortably in-browser.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/prism-ml/Bonsai-8B-gguf/resolve/main/Bonsai-8B-Q1_0.gguf',
    downloadSizeBytes: 1_158_654_496,
    memoryRequiredBytes: 1_400_000_000,
    contextLength: 4096,
    supportsThinking: true,
  },
  {
    // EXPERIMENTAL: PrismML Bonsai-27B at 1.125-bit (custom Q1_0 quant,
    // qwen3_5 GatedDeltaNet arch). Needs the PrismML llama.cpp fork pinned in
    // sdk/runanywhere-commons/VERSIONS. At ~3.8 GB the artifact sits at the
    // WASM 4 GB heap ceiling and cannot leave the minimum runtime/KV-cache
    // headroom required by this llama.cpp path. The catalog keeps the entry
    // visible for cross-platform discovery, while `webModelCompatibility`
    // prevents Web download/load and points users to a native app. PrismML's own browser demo
    // ("Bonsai 27B WebGPU Kernels" HF Space) uses a separate custom kernel
    // stack, not this WASM llama.cpp path.
    id: 'bonsai-27b-q1_0',
    name: 'Bonsai-27B 1-bit Q1_0 (Experimental)',
    description:
      'PrismML 1-bit 27B LLM. ~3.8 GB download at the WASM heap limit — likely to run out of memory in-browser.',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/prism-ml/Bonsai-27B-gguf/resolve/main/Bonsai-27B-Q1_0.gguf',
    downloadSizeBytes: 3_803_452_480,
    memoryRequiredBytes: 4_000_000_000,
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
    // Preserve the iOS catalog ID while using the browser-CORS-compatible
    // RunAnywhere Hugging Face bundle. The Web artifact is represented as the
    // two native llama.cpp inputs instead of the GitHub tarball used by iOS.
    id: 'smolvlm-500m-instruct-q8_0',
    name: 'SmolVLM 500M Instruct',
    description: 'SmolVLM 500M vision-language model with primary GGUF and mmproj sidecar.',
    category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    downloadUrl:
      'https://huggingface.co/runanywhere/SmolVLM-500M-Instruct-GGUF/resolve/main/SmolVLM-500M-Instruct-Q8_0.gguf',
    downloadSizeBytes: 636_275_712,
    memoryRequiredBytes: 720_000_000,
    contextLength: 2048,
    files: [
      {
        url: 'https://huggingface.co/runanywhere/SmolVLM-500M-Instruct-GGUF/resolve/main/SmolVLM-500M-Instruct-Q8_0.gguf',
        filename: 'SmolVLM-500M-Instruct-Q8_0.gguf',
        role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
        sizeBytes: 436_806_912,
      },
      {
        url: 'https://huggingface.co/runanywhere/SmolVLM-500M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-500M-Instruct-f16.gguf',
        filename: 'mmproj-SmolVLM-500M-Instruct-f16.gguf',
        role: ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
        sizeBytes: 199_468_800,
      },
    ],
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
    downloadSizeBytes: 483_105_280,
    memoryRequiredBytes: 650_000_000,
    contextLength: 2048,
    files: [
      {
        url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
        filename: 'LFM2-VL-450M-Q8_0.gguf',
        role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
        sizeBytes: 379_215_264,
      },
      {
        url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf',
        filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf',
        role: ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
        sizeBytes: 103_890_016,
      },
    ],
  },

  // ---------- Speech Recognition (STT) ----------
  {
    // Preserve iOS catalog parity while using RunAnywhere's browser-CORS-
    // compatible Hugging Face mirror. Size is the exact LFS object length.
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Sherpa Whisper Tiny (ONNX)',
    description: 'English speech-to-text via sherpa-onnx.',
    category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://huggingface.co/runanywhere/sherpa-onnx-whisper-tiny.en/resolve/main/sherpa-onnx-whisper-tiny.en.tar.gz',
    downloadSizeBytes: 152_777_070,
    memoryRequiredBytes: 180_000_000,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
  },

  // ---------- Speech Synthesis (TTS) ----------
  {
    // Preserve iOS catalog parity while using RunAnywhere's browser-CORS-
    // compatible Hugging Face mirror. Size is the exact LFS object length.
    id: 'vits-piper-en_US-lessac-medium',
    name: 'Piper TTS (US English - Medium)',
    description: 'Piper VITS text-to-speech, medium quality.',
    category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://huggingface.co/runanywhere/vits-piper-en_US-lessac-medium/resolve/main/vits-piper-en_US-lessac-medium.tar.gz',
    downloadSizeBytes: 67_389_394,
    memoryRequiredBytes: 90_000_000,
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
      'https://huggingface.co/runanywhere/vits-piper-en_GB-alba-medium/resolve/main/vits-piper-en_GB-alba-medium.tar.gz',
    downloadSizeBytes: 67_386_227,
    memoryRequiredBytes: 90_000_000,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
  },

  // ---------- VAD ----------
  {
    // Preserve iOS catalog parity while sourcing RunAnywhere's immutable,
    // browser-CORS-compatible Hugging Face artifact.
    id: 'silero-vad',
    name: 'Silero VAD',
    description: 'Lightweight voice activity detector.',
    category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    format: ModelFormat.MODEL_FORMAT_ONNX,
    downloadUrl:
      'https://huggingface.co/runanywhere/silero-vad-v5/resolve/main/silero_vad.onnx',
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
    downloadSizeBytes: 90_619_114,
    memoryRequiredBytes: 120_000_000,
    files: [
      {
        url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
        filename: 'model.onnx',
        role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
        sizeBytes: 90_387_606,
      },
      {
        url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt',
        filename: 'vocab.txt',
        role: ModelFileRole.MODEL_FILE_ROLE_VOCABULARY,
        sizeBytes: 231_508,
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
    appLogger.warning(
      `[model-catalog] registered ${registered} / ${CATALOG.length} entries`,
    );
  }
  return registered;
}

/** Get the declarative catalog. Safe to call before SDK initialization. */
export function getCatalog(): readonly CatalogEntry[] {
  return CATALOG;
}

/**
 * Decide whether a catalog entry can complete the Web download/load path.
 *
 * Downloads currently pass through a WASM32 MEMFS before being persisted to
 * OPFS, and inference needs the same linear address space for runtime state
 * and KV cache. Reserve a conservative 512 MiB for that non-model state. The
 * 3.803 GB Bonsai artifact therefore exceeds the 4 GiB WASM32 ceiling before
 * inference can begin, even on a machine with abundant physical memory.
 */
export function webModelCompatibility(entry: CatalogEntry): WebModelCompatibility {
  const base = webSizeCompatibility(entry.downloadSizeBytes, entry.memoryRequiredBytes);
  if (base.supported) return base;
  if (entry.id === 'bonsai-27b-q1_0') {
    return {
      ...base,
      reference: {
        label: 'Experimental direct-WebGPU reference',
        url: 'https://huggingface.co/spaces/webml-community/bonsai-webgpu-kernels',
      },
    };
  }
  return base;
}

/**
 * Same 4 GiB WASM32 gate as `webModelCompatibility`, expressed over raw sizes so
 * ad-hoc models (e.g. an arbitrary Hugging Face GGUF added at runtime) can reuse
 * the identical check without first being promoted to a `CatalogEntry`.
 */
export function webSizeCompatibility(
  downloadSizeBytes: number,
  memoryRequiredBytes: number,
): WebModelCompatibility {
  const modelBytes = Math.max(downloadSizeBytes, memoryRequiredBytes);
  if (modelBytes + MINIMUM_WASM_RUNTIME_HEADROOM_BYTES <= WASM32_ADDRESS_SPACE_BYTES) {
    return { supported: true };
  }

  const remainingMiB = Math.max(
    0,
    Math.round((WASM32_ADDRESS_SPACE_BYTES - modelBytes) / (1024 * 1024)),
  );
  return {
    supported: false,
    code: WebModelCompatibilityCode.WASM32_ADDRESS_SPACE,
    reason:
      `RunAnywhere's current llama.cpp/WebGPU backend must stage this `
      + `${(downloadSizeBytes / 1_000_000_000).toFixed(3)} GB GGUF in a 4 GiB WASM32 heap `
      + `before GPU upload, leaving only ${remainingMiB} MiB for loader, runtime, and KV-cache state. `
      + 'This model is likely to run out of memory in-browser; use a native app instead.',
  };
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

async function registerLoraAdapters(): Promise<void> {
  for (const adapter of LORA_ADAPTERS) {
    try {
      await RunAnywhere.lora.registerArtifact(adapter);
    } catch (err) {
      appLogger.warning(
        `[model-catalog] registerLoraArtifact(${adapter.id}) failed:`,
        err,
      );
    }
  }
}

function tryRegister(entry: CatalogEntry): boolean {
  try {
    const result = registerViaFacade(entry);
    return result !== null;
  } catch (err) {
    appLogger.warning(
      `[model-catalog] register(${entry.id}) threw:`,
      err,
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
