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
      registerModel({
        id: 'qwen3.5-0.8b-q4_k_m',
        name: 'Qwen3.5 0.8B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 900_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'qwen3.5-2b-q4_k_m',
        name: 'Qwen3.5 2B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 1_800_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'qwen3.5-4b-q4_k_m',
        name: 'Qwen3.5 4B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 3_200_000_000,
        supportsThinking: true,
      }),
      // Added from the verified model list
      registerModel({
        id: 'lfm2.5-1.2b-thinking-q4_k_m',
        name: 'LFM2.5 1.2B Thinking Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Thinking-GGUF/resolve/main/LFM2.5-1.2B-Thinking-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 900_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'lfm2.5-2.6b-q4_k_m',
        name: 'LFM2.5 2.6B Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/resolve/main/LFM2.5-2.6B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 2_050_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'granite-4.1-8b-q4_k_m',
        name: 'IBM Granite 4.1 8B Q4_K_M',
        url: 'https://huggingface.co/unsloth/granite-4.1-8b-GGUF/resolve/main/granite-4.1-8b-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 6_500_000_000,
      }),
      registerModel({
        id: 'qwen3.5-9b-q4_k_m',
        name: 'Qwen3.5 9B Q4_K_M',
        url: 'https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 6_950_000_000,
        supportsThinking: true,
      }),
      registerModel({
        id: 'bonsai-1.7b-q1_0',
        name: 'PrismML Bonsai 1.7B (1-bit)',
        url: 'https://huggingface.co/prism-ml/Bonsai-1.7B-gguf/resolve/main/Bonsai-1.7B-Q1_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 300_000_000,
      }),
      registerModel({
        id: 'bonsai-4b-q1_0',
        name: 'PrismML Bonsai 4B (1-bit)',
        url: 'https://huggingface.co/prism-ml/Bonsai-4B-gguf/resolve/main/Bonsai-4B-Q1_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 700_000_000,
      }),
      registerModel({
        id: 'bonsai-8b-q1_0',
        name: 'PrismML Bonsai 8B (1-bit)',
        url: 'https://huggingface.co/prism-ml/Bonsai-8B-gguf/resolve/main/Bonsai-8B-Q1_0.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 1_400_000_000,
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
      registerModel({
        id: 'lfm2.5-1.2b-instruct-q4_k_m',
        name: 'LiquidAI LFM2.5 1.2B Instruct Q4_K_M',
        url: 'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        memoryRequirementBytes: 730_895_168,
      }),
      // Gemma (Google)
      // Gemma 4 is Apache 2.0. Preserve the license and applicable attribution
      // notices if downloaded artifacts are redistributed. Phone-scale rows
      // only (E2B/E4B); larger Gemma 4 variants are desktop-scale.
      registerModel({
        id: 'gemma-4-e2b-it-q4_k_m',
        name: 'Gemma 4 E2B IT Q4_K_M',
        url: 'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // 3,106,738,272 B of weights plus a 4K-context KV/runtime allowance.
        memoryRequirementBytes: 3_400_000_000,
      }),
      registerModel({
        id: 'gemma-4-e4b-it-q4_k_m',
        name: 'Gemma 4 E4B IT Q4_K_M',
        url: 'https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // 4,977,171,584 B of weights plus a 4K-context KV/runtime allowance.
        memoryRequirementBytes: 5_700_000_000,
      }),
      // Granite (IBM)
      // Apache 2.0. Phone-scale row only (3B) — the 8B/30B Granite 4.1 rows are
      // desktop-scale and this app has no desktop RN target.
      registerModel({
        id: 'granite-4.1-3b-q4_k_m',
        name: 'IBM Granite 4.1 3B Q4_K_M',
        url: 'https://huggingface.co/unsloth/granite-4.1-3b-GGUF/resolve/main/granite-4.1-3b-Q4_K_M.gguf',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        // 2,099,502,400 B of weights plus a 4K-context KV/runtime allowance.
        memoryRequirementBytes: 2_400_000_000,
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
      // NOTE: NVIDIA Nemotron-3.5-ASR-Streaming 0.6B is intentionally NOT registered
      // here. It needs sherpa-onnx >=1.13.4/1.13.5; this app's vendored sherpa-onnx
      // for both iOS and Android (core/VERSIONS: SHERPA_ONNX_VERSION_IOS /
      // SHERPA_ONNX_VERSION_ANDROID) is still pinned to 1.13.2. Revisit once either
      // platform's pin is bumped.
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
      // Supertone (Supertonic TTS)
      // Supertone/supertonic-3 ships fp32 ONNX weights that sherpa-onnx's Supertonic
      // provider cannot load directly — it expects INT8-quantized *.int8.onnx weights
      // plus a converted voice.bin/unicode_indexer.bin. This row points at
      // csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11, the pre-converted
      // export sherpa-onnx's own examples use, pinned to its exact commit. sherpa-onnx
      // added Supertonic 3 support in v1.13.2; this app's vendored sherpa-onnx (both
      // iOS and Android, core/VERSIONS) is pinned to exactly 1.13.2, which is enough.
      registerModel({
        id: 'sherpa-supertonic-3-tts-int8',
        name: 'Supertonic 3 TTS INT8 (Sherpa-ONNX)',
        files: [
          {
            url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/duration_predictor.int8.onnx',
            filename: 'duration_predictor.int8.onnx',
            required: true,
          },
          {
            url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/text_encoder.int8.onnx',
            filename: 'text_encoder.int8.onnx',
            required: true,
          },
          {
            url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/vector_estimator.int8.onnx',
            filename: 'vector_estimator.int8.onnx',
            required: true,
          },
          {
            url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/vocoder.int8.onnx',
            filename: 'vocoder.int8.onnx',
            required: true,
          },
          {
            url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/tts.json',
            filename: 'tts.json',
            required: true,
          },
          {
            url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/unicode_indexer.bin',
            filename: 'unicode_indexer.bin',
            required: true,
          },
          {
            url: 'https://huggingface.co/csukuangfj2/sherpa-onnx-supertonic-3-tts-int8-2026-05-11/resolve/cca5a0e6c96e1d2c720986bf7e75fcc81dee3ae4/voice.bin',
            filename: 'voice.bin',
            required: true,
          },
        ],
        framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
        category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        // Sum of file Content-Lengths.
        memoryRequirementBytes: 145_295_768,
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
  // Not registered: the only adapter shipped is trained for qwen2.5-0.5b, which
  // this catalog no longer carries. Re-add both together.

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
