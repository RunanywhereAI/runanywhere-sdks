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
import {
  ModelCategory,
  InferenceFramework,
  ModelArtifactType,
} from '@runanywhere/proto-ts/model_types';
import { LoraAdapterCatalogEntry } from '@runanywhere/proto-ts/lora_options';
import { logDiagnostic } from '../utils/diagnostics';

// Canonical SDK methods (Swift parity).
const { registerModel, registerMultiFileModel } = RunAnywhere;

export type BackendRegistrationState = {
  llamaRegistered: boolean;
  onnxRegistered: boolean;
  qhexrtRegistered: boolean;
};

/**
 * Register the curated model catalog for every successfully-registered
 * backend. Matches iOS `ModelCatalogBootstrap.registerAll()`.
 */
export async function registerAll(
  backendState: BackendRegistrationState
): Promise<void> {
  const { llamaRegistered, onnxRegistered, qhexrtRegistered } = backendState;
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
        // memoryRequirement doubles as downloadSizeBytes for the post-finalize
        // size guard — set to the exact artifact Content-Length.
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
        // Q4_K_M artifact is ~1.1 GB; the prior 2.5 GB estimate tripped the
        // 80% download size guard (actual was only 45% of declared).
        memoryRequirement: 1_117_320_736,
      }),
      registerModel({
        id: 'qwen3-0.6b-q4_k_m',
        name: 'Qwen3 0.6B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // Actual Qwen3-0.6B-Q4_K_M.gguf artifact size (verified Content-Length).
        // memoryRequirement doubles as downloadSizeBytes, which feeds the
        // post-finalize download size guard. The prior 500 MB estimate tripped
        // the 80% guard on the valid ~378 MB download.
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
  // ONNX backend + STT/TTS models
  // =========================================================================
  if (!onnxRegistered) {
    return;
  }

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
      // Actual silero_vad.onnx artifact size (verified Content-Length).
      // memoryRequirement doubles as downloadSizeBytes, which feeds the
      // post-finalize download size guard. An over-stated 5 MB
      // tripped the guard on a valid ~2.3 MB download.
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

  // =========================================================================
  // QHexRT (Hexagon NPU) bundles — logical URLs resolved natively
  // =========================================================================
  if (qhexrtRegistered) {
    await registerNpuBundles();
  }

  logDiagnostic('[App] All models registered');
}

/**
 * Seed the curated LoRA adapter catalog. `registerArtifact` registers the
 * catalog entry plus its downloadable artifact record (no bytes fetched);
 * safe to re-run on every cold launch. Mirrors iOS
 * `ModelCatalogBootstrap.registerLoraAdapters()`.
 */
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

/**
 * Register logical HNPU rows. QHexRT's native bundle resolver chooses the
 * current device arch; unsupported devices or missing HF child dirs fail
 * registration and never appear as runnable models.
 */
async function registerNpuBundles(): Promise<void> {
  await Promise.all([
    registerModel({
      id: 'lfm2_5_230m',
      name: 'LFM2.5 230M (HNPU)',
      url: 'https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/lfm2-5-230m.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle lfm2_5_230m: ${String(error)}`
      )
    ),
    registerModel({
      id: 'lfm2_5_350m',
      name: 'LFM2.5 350M (HNPU)',
      url: 'https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/lfm2-5-350m-2048.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle lfm2_5_350m: ${String(error)}`
      )
    ),
    registerModel({
      id: 'qwen3_5_0_8b',
      name: 'Qwen3.5 0.8B (HNPU)',
      url: 'https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/qwen3.5-0.8b-1024.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle qwen3_5_0_8b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'qwen3_5_2b',
      name: 'Qwen3.5 2B (HNPU)',
      url: 'https://huggingface.co/runanywhere/qwen3_5_2b_HNPU/qwen3.5-2b-1024.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle qwen3_5_2b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'qwen3_5_4b',
      name: 'Qwen3.5 4B (HNPU)',
      url: 'https://huggingface.co/runanywhere/qwen3_5_4b_HNPU/qwen3.5-4b-1024.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle qwen3_5_4b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'qwen3_0_6b',
      name: 'Qwen3 0.6B (HNPU)',
      url: 'https://huggingface.co/runanywhere/qwen3_0_6b_HNPU/qwen3-0.6b-1024final.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle qwen3_0_6b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'llama3_2_1b',
      name: 'Llama 3.2 1B (HNPU)',
      url: 'https://huggingface.co/runanywhere/llama3_2_1b_HNPU/llama-3.2-1b.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle llama3_2_1b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'ternary_bonsai_1_7b',
      name: 'Ternary Bonsai 1.7B (HNPU)',
      url: 'https://huggingface.co/runanywhere/ternary_bonsai_1_7b_HNPU/ternary-bonsai-1.7b-1024.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle ternary_bonsai_1_7b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'phi_tiny_moe',
      name: 'Phi Tiny MoE (HNPU)',
      url: 'https://huggingface.co/runanywhere/phi_tiny_moe_HNPU/phimoe.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle phi_tiny_moe: ${String(error)}`
      )
    ),
    registerModel({
      id: 'gemma3n_e4b',
      name: 'Gemma 3n E4B (HNPU)',
      url: 'https://huggingface.co/runanywhere/gemma3n_e4b_HNPU/gemma-3n-E4B-it.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle gemma3n_e4b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'gemma4_e2b',
      name: 'Gemma 4 E2B (HNPU)',
      url: 'https://huggingface.co/runanywhere/gemma4_e2b_HNPU/gemma4-e2b.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle gemma4_e2b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'gemma4_e4b',
      name: 'Gemma 4 E4B (HNPU)',
      url: 'https://huggingface.co/runanywhere/gemma4_e4b_HNPU/gemma-4-E4B.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle gemma4_e4b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'deepseek_r1_distill_qwen_1_5b',
      name: 'DeepSeek R1 Distill Qwen 1.5B (HNPU)',
      url: 'https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_1_5b_HNPU/DeepSeek-R1-Distill-Qwen-1.5B.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle deepseek_r1_distill_qwen_1_5b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'deepseek_r1_distill_qwen_7b',
      name: 'DeepSeek R1 Distill Qwen 7B (HNPU)',
      url: 'https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_7b_HNPU/DeepSeek-R1-Distill-Qwen-7B.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle deepseek_r1_distill_qwen_7b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'nemotron_nano_8b',
      name: 'Llama 3.1 Nemotron Nano 8B (HNPU)',
      url: 'https://huggingface.co/runanywhere/nemotron_nano_8b_HNPU/nemotron-nano-8b.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle nemotron_nano_8b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'nemoguard_content_8b',
      name: 'NemoGuard 8B Content Safety (HNPU)',
      url: 'https://huggingface.co/runanywhere/nemoguard_8b_content_safety_HNPU/nemoguard-content-8b.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle nemoguard_content_8b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'nemoguard_topic_8b',
      name: 'NemoGuard 8B Topic Control (HNPU)',
      url: 'https://huggingface.co/runanywhere/nemoguard_8b_topic_control_HNPU/nemoguard-topic-8b.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle nemoguard_topic_8b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'qwen3_vl_2b_text',
      name: 'Qwen3-VL 2B Text (HNPU)',
      url: 'https://huggingface.co/runanywhere/qwen3_vl_HNPU/qwen3vl-2b-text-512.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle qwen3_vl_2b_text: ${String(error)}`
      )
    ),
    registerModel({
      id: 'qwen3_vl',
      name: 'Qwen3-VL 2B (HNPU)',
      url: 'https://huggingface.co/runanywhere/qwen3_vl_HNPU/qwen3vl-2b-vlm-512.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle qwen3_vl: ${String(error)}`
      )
    ),
    registerModel({
      id: 'internvl3_5_1b',
      name: 'InternVL3.5 1B (HNPU)',
      url: 'https://huggingface.co/runanywhere/internvl3_5_1b_HNPU',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle internvl3_5_1b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'gemma4_e2b_vlm',
      name: 'Gemma 4 E2B Image (HNPU)',
      url: 'https://huggingface.co/runanywhere/gemma4_e2b_HNPU/gemma4-e2b-vlm.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle gemma4_e2b_vlm: ${String(error)}`
      )
    ),
    registerModel({
      id: 'nemotron_nano_vl_8b',
      name: 'Llama 3.1 Nemotron Nano VL 8B (HNPU)',
      url: 'https://huggingface.co/runanywhere/nemotron_nano_vl_8b_HNPU/nemotron-vl-8b-vlm.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle nemotron_nano_vl_8b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'whisper_base',
      name: 'Whisper Base (HNPU)',
      url: 'https://huggingface.co/runanywhere/whisper_base_HNPU/whisper-base.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle whisper_base: ${String(error)}`
      )
    ),
    registerModel({
      id: 'whisper_small',
      name: 'Whisper Small (HNPU)',
      url: 'https://huggingface.co/runanywhere/whisper_small_HNPU/whisper-small.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle whisper_small: ${String(error)}`
      )
    ),
    registerModel({
      id: 'moonshine_tiny',
      name: 'Moonshine Tiny (HNPU)',
      url: 'https://huggingface.co/runanywhere/moonshine_tiny_HNPU/moonshine-tiny.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle moonshine_tiny: ${String(error)}`
      )
    ),
    registerModel({
      id: 'moonshine_base',
      name: 'Moonshine Base (HNPU)',
      url: 'https://huggingface.co/runanywhere/moonshine_base_HNPU/moonshine-base.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle moonshine_base: ${String(error)}`
      )
    ),
    registerModel({
      id: 'parakeet_tdt_0_6b_v2',
      name: 'Parakeet TDT 0.6B v2 (HNPU)',
      url: 'https://huggingface.co/runanywhere/parakeet_tdt_0.6b_v2_HNPU/parakeet-tdt-0.6b-v2.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle parakeet_tdt_0_6b_v2: ${String(error)}`
      )
    ),
    registerModel({
      id: 'parakeet_tdt_0_6b_v3',
      name: 'Parakeet TDT 0.6B v3 (HNPU)',
      url: 'https://huggingface.co/runanywhere/parakeet_tdt_0.6b_v3_HNPU/parakeet-tdt-0.6b.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle parakeet_tdt_0_6b_v3: ${String(error)}`
      )
    ),
    registerModel({
      id: 'parakeet_rnnt_1_1b',
      name: 'Parakeet RNNT 1.1B (HNPU)',
      url: 'https://huggingface.co/runanywhere/parakeet_rnnt_1.1b_HNPU/parakeet-rnnt-1.1b.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle parakeet_rnnt_1_1b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'canary_qwen_2_5b',
      name: 'Canary Qwen 2.5B (HNPU)',
      url: 'https://huggingface.co/runanywhere/canary_qwen_2.5b_HNPU/canary-qwen-2.5b.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle canary_qwen_2_5b: ${String(error)}`
      )
    ),
    registerModel({
      id: 'canary_1b_flash',
      name: 'Canary-1B-flash (HNPU)',
      url: 'https://huggingface.co/runanywhere/canary_1b_flash_HNPU/canary-1b-flash.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle canary_1b_flash: ${String(error)}`
      )
    ),
    registerModel({
      id: 'nemotron_asr_streaming',
      name: 'Nemotron ASR Streaming 0.6B (HNPU)',
      url: 'https://huggingface.co/runanywhere/nemotron_asr_streaming_HNPU/nemotron-3.5-asr-streaming-0.6b.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle nemotron_asr_streaming: ${String(error)}`
      )
    ),
    registerModel({
      id: 'melotts_en',
      name: 'MeloTTS EN (HNPU)',
      url: 'https://huggingface.co/runanywhere/melotts_en_HNPU/melotts-en.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle melotts_en: ${String(error)}`
      )
    ),
    registerModel({
      id: 'kokoro_en',
      name: 'Kokoro-82M EN (HNPU)',
      url: 'https://huggingface.co/runanywhere/kokoro_en_HNPU/kokoro-en.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle kokoro_en: ${String(error)}`
      )
    ),
    registerModel({
      id: 'kitten_nano_0_8',
      name: 'Kitten-nano-0.8-fp32 (HNPU)',
      url: 'https://huggingface.co/runanywhere/kitten_nano_0_8_HNPU/kitten_nano08_v81.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle kitten_nano_0_8: ${String(error)}`
      )
    ),
    registerModel({
      id: 'kitten_mini_0_1',
      name: 'Kitten-mini-0.1 (HNPU)',
      url: 'https://huggingface.co/runanywhere/kitten_mini_0_1_HNPU/kitten_mini01_v81.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle kitten_mini_0_1: ${String(error)}`
      )
    ),
    registerModel({
      id: 'kitten_mini_0_8',
      name: 'Kitten-mini-0.8 (HNPU)',
      url: 'https://huggingface.co/runanywhere/kitten_mini_0_8_HNPU/kitten_mini08_v81.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle kitten_mini_0_8: ${String(error)}`
      )
    ),
    registerModel({
      id: 'kitten_micro_0_8',
      name: 'Kitten-micro-0.8 (HNPU)',
      url: 'https://huggingface.co/runanywhere/kitten_micro_0_8_HNPU/kitten_micro08_v81.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle kitten_micro_0_8: ${String(error)}`
      )
    ),
    registerModel({
      id: 'kitten_nano_0_2',
      name: 'Kitten-nano-0.2 (HNPU)',
      url: 'https://huggingface.co/runanywhere/kitten_nano_0_2_HNPU/kitten_nano02_v81.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle kitten_nano_0_2: ${String(error)}`
      )
    ),
    registerModel({
      id: 'kitten_nano_0_1',
      name: 'Kitten-nano-0.1 (HNPU)',
      url: 'https://huggingface.co/runanywhere/kitten_nano_0_1_HNPU/kitten_nano01_v81.json',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    }).catch((error: unknown) =>
      logDiagnostic(
        `[App] Failed to register NPU bundle kitten_nano_0_1: ${String(error)}`
      )
    ),
  ]);
  logDiagnostic('[App] QHexRT logical NPU bundles registered: 40');
}

export async function refreshNpuCatalog(): Promise<void> {
  await registerNpuBundles();
  await RunAnywhere.refreshModelRegistry();
}
