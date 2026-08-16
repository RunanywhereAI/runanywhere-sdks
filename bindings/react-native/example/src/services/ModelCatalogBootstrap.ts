/**
 * ModelCatalogBootstrap - curated model catalog seeding.
 *
 * Mirrors iOS `ModelCatalogBootstrap.swift` (and Android
 * `ModelBootstrap.seedCuratedCatalog`). Uses the canonical SDK methods
 * (`RunAnywhere.models.register(...)` / `RunAnywhere.lora.catalog.register(...)`
 * + `registerLoraArtifact` — the RN SDK has no `lora.catalog.registerArtifact`
 * convenience the way Swift/Kotlin do, see `utils/loraArtifacts.ts`).
 * Safe to re-run on every cold
 * launch — commons merges runtime fields on re-registration.
 *
 * Layout convention (mirrors the iOS catalog): top-level sections are
 * framework x modality, and inside a section rows are grouped by MODEL FAMILY,
 * smallest to largest parameter count. ONE quantization per model.
 */

import { Platform } from 'react-native';
import { RunAnywhere } from '@runanywhere/core';
import { QHexRT } from '@runanywhere/qhexrt';
import {
  ModelCategory,
  InferenceFramework,
} from '@runanywhere/proto-ts/model_types';
import { LoraAdapterCatalogEntry } from '@runanywhere/proto-ts/lora_options';
import { logDiagnostic } from '../utils/diagnostics';
import { registerLoraArtifact } from '../utils/loraArtifacts';
import {
  NPU_BUNDLES,
  publishNpuCatalogAcceptance,
  toNpuRegistrationRequest,
} from './NpuModelCatalog';
import { PORTABLE_NVIDIA_EMBEDDING_MODELS } from './EmbeddingCatalogPolicy';

// One registration builder covers url, archive, and multi-file catalog rows.
const registerModel = RunAnywhere.models.register;

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
  // LLM (llama.cpp) — grouped by model family, small → large inside a family
  // =========================================================================
  if (llamaRegistered) {
    await Promise.all([
      // SmolLM (HuggingFace)
      registerModel({
        id: 'smollm2-360m-q8_0',
        name: 'SmolLM2 360M Q8_0',
        url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 386_404_416,
      }),
      // Qwen 2.5 (Alibaba)
      registerModel({
        id: 'qwen2.5-0.5b-instruct-q6_k',
        name: 'Qwen 2.5 0.5B Instruct Q6_K',
        url: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 650_379_104,
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
        memoryRequirementBytes: 1_117_320_736,
      }),
      // Qwen3 (Alibaba) — thinking-capable
      registerModel({
        id: 'qwen3-0.6b-q4_k_m',
        name: 'Qwen3 0.6B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // Actual Qwen3-0.6B-Q4_K_M.gguf Content-Length for catalog display.
        memoryRequirementBytes: 396_705_472,
        supportsThinking: true,
      }),
      registerModel({
        id: 'qwen3-1.7b-q4_k_m',
        name: 'Qwen3 1.7B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 1_107_409_472,
        supportsThinking: true,
      }),
      registerModel({
        id: 'qwen3-4b-q4_k_m',
        name: 'Qwen3 4B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 2_497_281_312,
        supportsThinking: true,
      }),
      // LFM2 / LFM2.5 (Liquid AI)
      // LFM2.5-230M on the CPU. Q4_K_M, not the fractionally smaller Q4_0
      // (153 MB vs 149 MB): 4 MB buys K-quant mixed precision on the
      // attention/embedding tensors, and Q4_K_M is the quantization every other
      // GGUF row in this catalog uses.
      registerModel({
        id: 'lfm2.5-230m-q4_k_m',
        name: 'LiquidAI LFM2.5 230M Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // 153,406,304 B of weights (the exact artifact Content-Length) — KV
        // cache and runtime overhead sit on top of this at load time. Every
        // other llama.cpp row here states exact artifact bytes rather than the
        // rounded weights+overhead estimate the iOS catalog uses, so this row
        // follows the local convention.
        memoryRequirementBytes: 153_406_304,
      }),
      // ONE quantization per model. The Q8_0 sibling of this row was removed
      // deliberately: two quants of the same 350M model differ only in bytes
      // (229 MB vs 379 MB), so the second row costs a catalog slot and a
      // "which one do I pick?" decision without adding a capability.
      registerModel({
        id: 'lfm2-350m-q4_k_m',
        name: 'LiquidAI LFM2 350M Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 229_309_376,
      }),
      registerModel({
        id: 'lfm2.5-1.2b-instruct-q4_k_m',
        name: 'LiquidAI LFM2.5 1.2B Instruct Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 730_895_168,
      }),
      // Same ONE-quantization-per-model rule as the 350M row above: the Q8_0
      // sibling (1.25 GB against this row's 731 MB) was the same model at a
      // different size, so it was dropped rather than kept as a second pick.
      registerModel({
        id: 'lfm2-1.2b-tool-q4_k_m',
        name: 'LiquidAI LFM2 1.2B Tool Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 730_894_048,
      }),
      // Llama (Meta)
      registerModel({
        id: 'llama-3.2-3b-instruct-q4_k_m',
        name: 'Llama 3.2 3B Instruct Q4_K_M (Tool Calling)',
        url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 2_019_377_696,
      }),
      registerModel({
        id: 'llama-2-7b-chat-q4_k_m',
        name: 'Llama 2 7B Chat Q4_K_M',
        url: 'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // Exact artifact Content-Length for catalog display/storage planning.
        memoryRequirementBytes: 4_081_004_224,
      }),
      // Mistral
      registerModel({
        id: 'mistral-7b-instruct-q4_k_m',
        name: 'Mistral 7B Instruct Q4_K_M',
        url: 'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 4_368_438_944,
      }),
      // Bonsai (PrismML)
      // PrismML Bonsai-27B at 1.125-bit (Q1_0, qwen3_5 GatedDeltaNet). The
      // canonical-first RunAnywhere llama.cpp fork preserves this support beside
      // its Maple compatibility delta.
      registerModel({
        id: 'bonsai-27b-q1_0',
        name: 'Bonsai-27B 1-bit Q1_0 (CPU)',
        url: 'https://huggingface.co/prism-ml/Bonsai-27B-gguf/resolve/main/Bonsai-27B-Q1_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 3_803_452_480,
        supportsThinking: true,
      }),
      // Nemotron (NVIDIA) — portable llama.cpp GGUFs shared with the other
      // example apps. These three rows are EMBEDDING-modality (see
      // EmbeddingCatalogPolicy.ts); they stay with the llama.cpp rows to mirror
      // the iOS catalog, which registers them in its llama.cpp section too.
      ...PORTABLE_NVIDIA_EMBEDDING_MODELS.map((model) => registerModel(model)),
    ]);
  } else {
    logDiagnostic('[App] Skipping LlamaCPP models - backend not available');
  }

  // =========================================================================
  // MLX (Apple Metal) — representative Apple catalog aligned with the iOS
  // example, grouped by model family
  // =========================================================================
  if (mlxRegistered) {
    await Promise.all([
      // Qwen (Alibaba) — Qwen2-VL vision, then the Qwen3 0.6B trio
      // (LLM / ASR / embedding)
      registerModel({
        id: 'mlx-qwen2-vl-2b-instruct-4bit',
        name: 'MLX Qwen2-VL 2B Instruct 4bit',
        url: 'https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        memoryRequirementBytes: 2_200_000_000,
      }),
      registerModel({
        id: 'mlx-qwen3-0.6b-4bit',
        name: 'MLX Qwen3 0.6B 4bit',
        url: 'https://huggingface.co/mlx-community/Qwen3-0.6B-4bit',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        memoryRequirementBytes: 650_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'mlx-qwen3-asr-0.6b-8bit',
        name: 'MLX Qwen3-ASR 0.6B 8bit',
        files: [
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/chat_template.json',
            filename: 'chat_template.json',
            required: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/config.json',
            filename: 'config.json',
            required: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/generation_config.json',
            filename: 'generation_config.json',
            required: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/merges.txt',
            filename: 'merges.txt',
            required: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors',
            filename: 'model.safetensors',
            required: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors.index.json',
            filename: 'model.safetensors.index.json',
            required: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/preprocessor_config.json',
            filename: 'preprocessor_config.json',
            required: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/tokenizer_config.json',
            filename: 'tokenizer_config.json',
            required: true,
          },
          {
            url: 'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/vocab.json',
            filename: 'vocab.json',
            required: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        memoryRequirementBytes: 1_010_773_761,
      }),
      registerModel({
        id: 'mlx-qwen3-embedding-0.6b-4bit-dwq',
        name: 'MLX Qwen3 Embedding 0.6B 4bit DWQ',
        url: 'https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
        memoryRequirementBytes: 350_000_000,
      }),
      // LFM2.5 (Liquid AI)
      // A PLAIN REPO ref, not a `/4bit` subfolder ref like
      // `hf.co/LiquidAI/LFM2.5-2.6B-MLX/4bit`. LiquidAI publishes one precision
      // per repo here — the 4-bit weights sit at the repo ROOT alongside
      // config.json and tokenizer.json — so appending a precision segment would
      // 404.
      registerModel({
        id: 'mlx-lfm2.5-230m-4bit',
        name: 'MLX LFM2.5 230M 4bit',
        url: 'https://huggingface.co/LiquidAI/LFM2.5-230M-MLX-4bit',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        // 150,867,598 B for the whole repo (146 MB of that is
        // model.safetensors) plus KV cache and Metal runtime overhead.
        memoryRequirementBytes: 200_000_000,
      }),
      // Bonsai (PrismML)
      // PrismML Bonsai-27B 1-bit MLX (~5.1 GB). Experimental due to its size;
      // requires the paired RunAnywhere MLX/MLX Swift tags.
      registerModel({
        id: 'mlx-bonsai-27b-1bit',
        name: 'MLX Bonsai-27B 1-bit',
        url: 'https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        memoryRequirementBytes: 5_129_115_752,
        supportsThinking: true,
      }),
      // Kokoro (hexgrad) — TTS
      registerModel({
        id: 'mlx-kokoro-82m-6bit',
        name: 'MLX Kokoro 82M 6bit',
        url: 'https://huggingface.co/mlx-community/Kokoro-82M-6bit',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
        category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        memoryRequirementBytes: 309_640_166,
      }),
    ]);
  } else {
    logDiagnostic('[App] Skipping MLX models - backend not available');
  }

  // =========================================================================
  // VLM (multimodal, llama.cpp) — grouped by model family
  // =========================================================================
  if (llamaRegistered) {
    await Promise.all([
      // SmolVLM (HuggingFace)
      // SmolVLM 500M - Ultra-lightweight VLM for mobile (~500MB total)
      registerModel({
        id: 'smolvlm-500m-instruct-q8_0',
        name: 'SmolVLM 500M Instruct',
        archiveUrl: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        memoryRequirementBytes: 600_000_000,
      }),
      // Qwen (Alibaba)
      // Qwen2-VL 2B - Small but capable VLM (~1.6GB total)
      // Uses multi-file download: main model (986MB) + mmproj (710MB)
      registerModel({
        id: 'qwen2-vl-2b-instruct-q4_k_m',
        name: 'Qwen2-VL 2B Instruct',
        files: [
          {
            url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
            filename: 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
            required: true,
          },
          {
            url: 'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
            filename: 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
            required: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        // Sum of file Content-Lengths: main (986 MB) + mmproj (710 MB).
        memoryRequirementBytes: 1_695_930_304,
      }),
      // LFM2-VL (Liquid AI)
      // LFM2-VL 450M - LiquidAI's compact VLM, ideal for mobile (~600MB total)
      registerModel({
        id: 'lfm2-vl-450m-q8_0',
        name: 'LFM2-VL 450M',
        files: [
          {
            url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
            filename: 'LFM2-VL-450M-Q8_0.gguf',
            required: true,
          },
          {
            url: 'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf',
            filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf',
            required: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        // Sum of file Content-Lengths: main (379 MB) + mmproj (104 MB).
        memoryRequirementBytes: 483_105_280,
      }),
      // Fara (Microsoft)
      // Fara1.5-4B - Microsoft Qwen3.5-VL computer-use agent VLM (~3300MB total)
      // Uses multi-file download: main model + mmproj vision projector.
      registerModel({
        id: 'fara1.5-4b-q4_k_m',
        name: 'Fara1.5 4B Computer-Use Agent Q4_K_M',
        files: [
          {
            url: 'https://huggingface.co/runanywhere/Fara1.5-4B-GGUF/resolve/main/Fara1.5-4B-Q4_K_M.gguf',
            filename: 'Fara1.5-4B-Q4_K_M.gguf',
            required: true,
          },
          {
            url: 'https://huggingface.co/runanywhere/Fara1.5-4B-GGUF/resolve/main/mmproj-Fara1.5-4B-f16.gguf',
            filename: 'mmproj-Fara1.5-4B-f16.gguf',
            required: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        // Approximate total: primary Q4_K_M text model + f16 mmproj projector.
        memoryRequirementBytes: 3_300_000_000,
        // Declares the model drivable through `RunAnywhere.cua`.
        cuaProfile: RunAnywhere.cua.faraProfile,
      }),
    ]);
  }

  // =========================================================================
  // STT (Sherpa-ONNX)
  // =========================================================================
  if (onnxRegistered) {
    await Promise.all([
      // Whisper (OpenAI)
      // Sherpa-ONNX speech models — served by the Sherpa engine plugin
      registerModel({
        id: 'sherpa-onnx-whisper-tiny.en',
        name: 'Sherpa Whisper Tiny (ONNX)',
        archiveUrl: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
        category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        memoryRequirementBytes: 75_000_000,
      }),
    ]);
  }

  // =========================================================================
  // TTS (Sherpa-ONNX Piper VITS)
  // =========================================================================
  if (onnxRegistered) {
    await Promise.all([
      // Piper VITS (rhasspy)
      registerModel({
        id: 'vits-piper-en_US-lessac-medium',
        name: 'Piper TTS (US English - Medium)',
        archiveUrl: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
        category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        memoryRequirementBytes: 65_000_000,
      }),
      registerModel({
        id: 'vits-piper-en_GB-alba-medium',
        name: 'Piper TTS (British English)',
        archiveUrl: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
        category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        memoryRequirementBytes: 65_000_000,
      }),
    ]);
  }

  // =========================================================================
  // VAD (Silero, ONNX)
  // =========================================================================
  if (onnxRegistered) {
    // Silero VAD — one-per-modality minimum for voice-agent parity with
    // iOS. Small .onnx file served directly from the upstream repo.
    await registerModel({
      id: 'silero-vad',
      name: 'Silero VAD',
      url: 'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
      // Actual silero_vad.onnx Content-Length for catalog display/storage
      // planning; the SDK keeps downloadSizeBytes separate.
      memoryRequirementBytes: 2_327_524,
    });
  }

  // =========================================================================
  // Embeddings (ONNX)
  // =========================================================================
  if (onnxRegistered) {
    // MiniLM (sentence-transformers)
    // Embedding model for RAG (multi-file: model.onnx + vocab.txt co-located)
    // Identical to iOS: RunAnywhere.registerMultiFileModel(id:name:files:framework:modality:memoryRequirement:)
    await registerModel({
      id: 'all-minilm-l6-v2',
      name: 'All MiniLM L6 v2 (Embedding)',
      files: [
        {
          url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
          filename: 'model.onnx',
          required: true,
        },
        {
          url: 'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt',
          filename: 'vocab.txt',
          required: true,
        },
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      // Sum of file Content-Lengths: model.onnx (90 MB) + vocab.txt (232 KB).
      memoryRequirementBytes: 90_619_114,
    });
  }

  // =========================================================================
  // LoRA adapters — mirrors iOS registerLoraAdapters() / Android seedLora.
  // =========================================================================
  if (llamaRegistered) {
    await registerLoraAdapters();
  }

  // =========================================================================
  // Diffusion (CoreML / Apple platform backend) — image generation
  // Apple-only: the DIFFUSION primitive is served exclusively by the CoreML
  // Stable-Diffusion backend, so register only on iOS/macOS. Mirrors the
  // built-in commons diffusion registry entry
  // (diffusion_model_registry.cpp MODEL_SD15_COREML). registerModel is safe to
  // re-run — commons merges runtime fields on re-registration. Wrapped so a
  // registration hiccup never blocks the rest of catalog bootstrap.
  // =========================================================================
  if (Platform.OS === 'ios' || Platform.OS === 'macos') {
    try {
      await registerModel({
        id: 'stable-diffusion-v1-5-coreml',
        name: 'Stable Diffusion 1.5',
        url: 'https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_COREML,
        category: ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
        memoryRequirementBytes: 1_200_000_000,
      });
    } catch (error) {
      logDiagnostic(
        `[App] Skipping CoreML diffusion model registration: ${String(error)}`
      );
    }
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
  const id = 'abliterated-lora';
  const name = 'Abliterated LoRA (F16)';
  try {
    // `LoraAdapterCatalogEntry` no longer carries url/filename/size/
    // description metadata (idl/lora_options.proto: "everything generic
    // about the artifact ... lives on the ModelInfo record for this
    // adapter") — register the catalog entry (compatibility/scale only)
    // and the downloadable artifact (url/size) separately.
    await RunAnywhere.lora.catalog.register(
      LoraAdapterCatalogEntry.fromPartial({
        id,
        name,
        compatibleModels: ['qwen2.5-0.5b-instruct-q6_k'],
        defaultScale: 1.0,
      })
    );
    await registerLoraArtifact({
      catalogEntryId: id,
      name,
      url: 'https://huggingface.co/Void2377/qwen-lora-gguf/resolve/main/qwen2.5-0.5b-abliterated-lora-f16.gguf',
      sizeBytes: 17_620_224,
    });
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
    return registered && capability.supported;
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
 * Re-seed QHexRT rows after token/config changes. Re-seeding is only meaningful
 * when native QHexRT is still registered on a supported device; the rows land in
 * the native registry directly, so `models.list()` sees them without a refresh.
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
  // Publish after re-seeding so retained pickers reload a completed catalog
  // snapshot rather than observing an intermediate registration pass.
  publishNpuCatalogAcceptance(result.registeredIds);
  logDiagnostic(
    `[App] QHexRT catalog refresh completed: rows=${result.registered}`
  );
  return result.registered > 0;
}
