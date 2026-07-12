/**
 * ModelCatalogBootstrap - curated model catalog seeding.
 *
 * Mirrors iOS `ModelCatalogBootstrap.swift` (and Android
 * `ModelBootstrap.seedCuratedCatalog`). Uses the canonical SDK methods
 * (`RunAnywhere.registerModel(...)` / `RunAnywhere.registerMultiFileModel(...)`
 * / `RunAnywhere.lora.registerArtifact(...)`). Safe to re-run on every cold
 * launch — commons merges runtime fields on re-registration.
 */

import { RunAnywhere } from '@runanywhere/core';
import { QHexRT } from '@runanywhere/qhexrt';
import {
  ModelCategory,
  InferenceFramework,
  ModelArtifactType,
} from '@runanywhere/proto-ts/model_types';
import { LoraAdapterCatalogEntry } from '@runanywhere/proto-ts/lora_options';
import { logDiagnostic } from '../utils/diagnostics';
import {
  NPU_BUNDLES,
  publishNpuCatalogAcceptance,
  toNpuRegistrationRequest,
} from './NpuModelCatalog';

// Canonical SDK methods (Swift parity).
const { registerModel, registerMultiFileModel } = RunAnywhere;

export type BackendRegistrationState = {
  llamaRegistered: boolean;
  onnxRegistered: boolean;
  mlxRegistered: boolean;
  qhexrtRegistered: boolean;
};

let qhexrtBackendRegistered = false;

/**
 * Register the curated model catalog for every successfully-registered
 * backend. Matches iOS `ModelCatalogBootstrap.registerAll()`.
 */
export async function registerAll(
  backendState: BackendRegistrationState
): Promise<void> {
  const { llamaRegistered, onnxRegistered, mlxRegistered, qhexrtRegistered } =
    backendState;
  // =========================================================================
  // LlamaCPP backend + LLM models
  // =========================================================================
  if (llamaRegistered) {
    await Promise.all([
      registerModel({
        id: 'smollm2-360m-q8_0',
        name: 'SmolLM2 360M Q8_0',
        url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 386_404_416,
      }),
      registerModel({
        id: 'llama-2-7b-chat-q4_k_m',
        name: 'Llama 2 7B Chat Q4_K_M',
        url: 'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // Exact artifact Content-Length for catalog display/storage planning.
        memoryRequirement: 4_081_004_224,
      }),
      registerModel({
        id: 'mistral-7b-instruct-q4_k_m',
        name: 'Mistral 7B Instruct Q4_K_M',
        url: 'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 4_368_438_944,
      }),
      registerModel({
        id: 'qwen2.5-0.5b-instruct-q6_k',
        name: 'Qwen 2.5 0.5B Instruct Q6_K',
        url: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 650_379_104,
        // Base model of the seeded abliterated adapter
        // (qwen2.5-0.5b-abliterated-lora-f16.gguf) — matches iOS/Android.
        supportsLora: true,
      }),
      registerModel({
        id: 'qwen2.5-1.5b-instruct-q4_k_m',
        name: 'Qwen 2.5 1.5B Instruct Q4_K_M',
        url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // Q4_K_M artifact is ~1.1 GB; keep the catalog estimate close to the
        // real transfer size for UI/storage planning.
        memoryRequirement: 1_117_320_736,
      }),
      registerModel({
        id: 'qwen3-0.6b-q4_k_m',
        name: 'Qwen3 0.6B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // Actual Qwen3-0.6B-Q4_K_M.gguf Content-Length for catalog display.
        memoryRequirement: 396_705_472,
        supportsThinking: true,
      }),
      registerModel({
        id: 'qwen3-1.7b-q4_k_m',
        name: 'Qwen3 1.7B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 1_107_409_472,
        supportsThinking: true,
      }),
      registerModel({
        id: 'qwen3-4b-q4_k_m',
        name: 'Qwen3 4B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 2_497_281_312,
        supportsThinking: true,
      }),
      registerModel({
        id: 'llama-3.2-3b-instruct-q4_k_m',
        name: 'Llama 3.2 3B Instruct Q4_K_M (Tool Calling)',
        url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 2_019_377_696,
      }),
      registerModel({
        id: 'lfm2-350m-q4_k_m',
        name: 'LiquidAI LFM2 350M Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 229_309_376,
      }),
      registerModel({
        id: 'lfm2-350m-q8_0',
        name: 'LiquidAI LFM2 350M Q8_0',
        url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 379_214_784,
      }),
      registerModel({
        id: 'lfm2.5-1.2b-instruct-q4_k_m',
        name: 'LiquidAI LFM2.5 1.2B Instruct Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 730_895_168,
      }),
      registerModel({
        id: 'lfm2-1.2b-tool-q4_k_m',
        name: 'LiquidAI LFM2 1.2B Tool Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 730_894_048,
      }),
      registerModel({
        id: 'lfm2-1.2b-tool-q8_0',
        name: 'LiquidAI LFM2 1.2B Tool Q8_0',
        url: 'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirement: 1_246_252_768,
      }),
    ]);
  } else {
    logDiagnostic('[App] Skipping LlamaCPP models - backend not available');
  }

  // =========================================================================
  // VLM (Vision Language) models
  // =========================================================================
  if (llamaRegistered) {
    await Promise.all([
      // SmolVLM 500M - Ultra-lightweight VLM for mobile (~500MB total)
      registerModel({
        id: 'smolvlm-500m-instruct-q8_0',
        name: 'SmolVLM 500M Instruct',
        url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
        memoryRequirement: 600_000_000,
      }),
      // Qwen2-VL 2B - Small but capable VLM (~1.6GB total)
      // Uses multi-file download: main model (986MB) + mmproj (710MB)
      registerMultiFileModel({
        id: 'qwen2-vl-2b-instruct-q4_k_m',
        name: 'Qwen2-VL 2B Instruct',
        files: [
          {
            url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
            filename: 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
            filename: 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
            isRequired: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        // Sum of file Content-Lengths: main (986 MB) + mmproj (710 MB).
        memoryRequirement: 1_695_930_304,
      }),
      // LFM2-VL 450M - LiquidAI's compact VLM, ideal for mobile (~600MB total)
      registerMultiFileModel({
        id: 'lfm2-vl-450m-q8_0',
        name: 'LFM2-VL 450M',
        files: [
          {
            url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
            filename: 'LFM2-VL-450M-Q8_0.gguf',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf',
            filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf',
            isRequired: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        // Sum of file Content-Lengths: main (379 MB) + mmproj (104 MB).
        memoryRequirement: 483_105_280,
      }),
    ]);
  }

  // =========================================================================
  // LoRA adapters — mirrors iOS registerLoraAdapters() / Android seedLora.
  // =========================================================================
  if (llamaRegistered) {
    await registerLoraAdapters();
  }

  // =========================================================================
  // MLX backend — representative Apple catalog aligned with the iOS example
  // =========================================================================
  if (mlxRegistered) {
    await Promise.all([
      registerModel({
        id: 'mlx-qwen3-0.6b-4bit',
        name: 'MLX Qwen3 0.6B 4bit',
        url: 'https://huggingface.co/mlx-community/Qwen3-0.6B-4bit',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        memoryRequirement: 650_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'mlx-qwen2-vl-2b-instruct-4bit',
        name: 'MLX Qwen2-VL 2B Instruct 4bit',
        url: 'https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        memoryRequirement: 2_200_000_000,
      }),
      registerMultiFileModel({
        id: 'mlx-qwen3-asr-0.6b-8bit',
        name: 'MLX Qwen3-ASR 0.6B 8bit',
        files: [
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/chat_template.json',
            filename: 'chat_template.json',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/config.json',
            filename: 'config.json',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/generation_config.json',
            filename: 'generation_config.json',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/merges.txt',
            filename: 'merges.txt',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors',
            filename: 'model.safetensors',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors.index.json',
            filename: 'model.safetensors.index.json',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/preprocessor_config.json',
            filename: 'preprocessor_config.json',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/tokenizer_config.json',
            filename: 'tokenizer_config.json',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/vocab.json',
            filename: 'vocab.json',
            isRequired: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        memoryRequirement: 1_010_773_761,
      }),
      registerModel({
        id: 'mlx-kokoro-82m-6bit',
        name: 'MLX Kokoro 82M 6bit',
        url: 'https://huggingface.co/mlx-community/Kokoro-82M-6bit',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        memoryRequirement: 309_640_166,
      }),
      registerModel({
        id: 'mlx-qwen3-embedding-0.6b-4bit-dwq',
        name: 'MLX Qwen3 Embedding 0.6B 4bit DWQ',
        url: 'https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
        memoryRequirement: 350_000_000,
      }),
    ]);
  } else {
    logDiagnostic('[App] Skipping MLX models - backend not available');
  }

  // =========================================================================
  // ONNX backend + STT/TTS models
  // =========================================================================
  if (onnxRegistered) {
    await Promise.all([
      // Sherpa-ONNX speech models — served by the Sherpa engine plugin
      registerModel({
        id: 'sherpa-onnx-whisper-tiny.en',
        name: 'Sherpa Whisper Tiny (ONNX)',
        url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
        memoryRequirement: 75_000_000,
      }),
      registerModel({
        id: 'vits-piper-en_US-lessac-medium',
        name: 'Piper TTS (US English - Medium)',
        url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
        memoryRequirement: 65_000_000,
      }),
      registerModel({
        id: 'vits-piper-en_GB-alba-medium',
        name: 'Piper TTS (British English)',
        url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
        memoryRequirement: 65_000_000,
      }),
      // Silero VAD — one-per-modality minimum for voice-agent parity with
      // iOS. Small .onnx file served directly from the upstream repo.
      registerModel({
        id: 'silero-vad',
        name: 'Silero VAD',
        url: 'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
        modality: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
        // Actual silero_vad.onnx Content-Length for catalog display/storage
        // planning; the SDK keeps downloadSizeBytes separate.
        memoryRequirement: 2_327_524,
      }),
      // Embedding model for RAG (multi-file: model.onnx + vocab.txt co-located)
      // Identical to iOS: RunAnywhere.registerMultiFileModel(id:name:files:framework:modality:memoryRequirement:)
      registerMultiFileModel({
        id: 'all-minilm-l6-v2',
        name: 'All MiniLM L6 v2 (Embedding)',
        files: [
          {
            url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
            filename: 'model.onnx',
            isRequired: true,
          },
          {
            url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt',
            filename: 'vocab.txt',
            isRequired: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
        modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
        // Sum of file Content-Lengths: model.onnx (90 MB) + vocab.txt (232 KB).
        memoryRequirement: 90_619_114,
      }),
    ]);
  }

  // =========================================================================
  // QHexRT (Hexagon NPU) bundles — logical URLs resolved natively
  // =========================================================================
  qhexrtBackendRegistered = qhexrtRegistered;
  if (await isNpuCatalogReady()) {
    const result = await registerNpuBundles();
    publishNpuCatalogAcceptance(result.registeredIds);
  } else {
    publishNpuCatalogAcceptance([]);
    logDiagnostic(
      '[App] Skipping QHexRT catalog - native backend/device unsupported'
    );
  }

  logDiagnostic('[App] All models registered');
}

async function registerLoraAdapters(): Promise<void> {
  try {
    await RunAnywhere.lora.registerArtifact(
      LoraAdapterCatalogEntry.fromPartial({
        id: 'abliterated-lora',
        name: 'Abliterated LoRA (F16)',
        description:
          'Removes refusal behavior — model answers directly without disclaimers',
        url: 'https://huggingface.co/Void2377/qwen-lora-gguf/resolve/main/qwen2.5-0.5b-abliterated-lora-f16.gguf',
        filename: 'qwen2.5-0.5b-abliterated-lora-f16.gguf',
        compatibleModels: ['qwen2.5-0.5b-instruct-q6_k'],
        sizeBytes: 17_620_224,
        defaultScale: 1.0,
      })
    );
  } catch (error) {
    logDiagnostic(`[App] Failed to register LoRA adapter: ${String(error)}`);
  }
}

type NpuSeedResult = Readonly<{
  registeredIds: ReadonlySet<string>;
  registered: number;
  failed: number;
  skippedNative: number;
}>;

async function isNpuCatalogReady(): Promise<boolean> {
  if (!qhexrtBackendRegistered) return false;

  try {
    const [registered, capability] = await Promise.all([
      QHexRT.isRegistered(),
      QHexRT.probeNpu(),
    ]);
    return registered && capability.qhexrtSupported;
  } catch (error) {
    logDiagnostic(`[App] QHexRT readiness check failed: ${String(error)}`);
    return false;
  }
}

/** Register only the logical HNPU rows accepted by native QHexRT. */
async function registerNpuBundles(): Promise<NpuSeedResult> {
  const registeredIds = new Set<string>();
  let registered = 0;
  let failed = 0;
  let skippedNative = 0;

  for (const bundle of NPU_BUNDLES) {
    try {
      const saved = await QHexRT.registerModelForDevice(
        toNpuRegistrationRequest(bundle)
      );
      if (saved) {
        registered += 1;
        registeredIds.add(saved.id);
      } else {
        skippedNative += 1;
      }
    } catch (error) {
      failed += 1;
      logDiagnostic(
        `[App] Failed to register NPU bundle ${bundle.id}: ${String(error)}`
      );
    }
  }

  logDiagnostic(
    `[App] QHexRT catalog seeded: ok=${registered} failed=${failed} ` +
      `skippedNative=${skippedNative}`
  );
  return {
    registeredIds,
    registered,
    failed,
    skippedNative,
  };
}

/**
 * Re-seed QHexRT rows after token/config changes. A generic registry refresh is
 * only meaningful when native QHexRT is still registered on a supported device.
 */
export async function refreshNpuCatalog(): Promise<boolean> {
  if (!(await isNpuCatalogReady())) {
    publishNpuCatalogAcceptance([]);
    logDiagnostic(
      '[App] Skipping QHexRT catalog refresh - native backend/device unsupported'
    );
    return false;
  }

  const result = await registerNpuBundles();
  let registryRefreshed = false;
  try {
    await RunAnywhere.refreshModelRegistry();
    registryRefreshed = true;
  } catch (error) {
    logDiagnostic(`[App] QHexRT registry refresh failed: ${String(error)}`);
  }

  // Publish after the registry operation so retained pickers reload a completed
  // catalog snapshot rather than observing an intermediate registration pass.
  publishNpuCatalogAcceptance(result.registeredIds);
  logDiagnostic(
    `[App] QHexRT catalog refresh completed: registryRefreshed=${registryRefreshed}`
  );
  return registryRefreshed;
}
