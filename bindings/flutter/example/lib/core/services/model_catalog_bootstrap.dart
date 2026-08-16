import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/runanywhere_protos.dart' as proto;
import 'package:runanywhere_ai/core/services/hf_token_store.dart';
import 'package:runanywhere_ai/core/services/qhexrt_model_catalog.dart';

@visibleForTesting
const portableNvidiaEmbeddingCatalog = [
  (
    id: 'nemotron-3-embed-1b-q4_k_m',
    name: 'NVIDIA Nemotron 3 Embed 1B Q4_K_M',
    url:
        'https://huggingface.co/zenmagnets/Nemotron-3-Embed-1B-Q4_K_M-GGUF/resolve/06df1fde6f7009c91f6cc3cd520081921929a678/nemotron-3-embed-1b-q4_k_m.gguf',
    memoryRequirement: 749352096,
  ),
  (
    id: 'llama-nemotron-embed-1b-v2-q4_k_m',
    name: 'NVIDIA Llama Nemotron Embed 1B v2 Q4_K_M',
    url:
        'https://huggingface.co/mykor/llama-nemotron-embed-1b-v2-GGUF/resolve/bf7c9832b1d76f86777379e58b7b74805ee58006/llama-nemotron-embed-1B-v2-Q4_K_M.gguf',
    memoryRequirement: 807690624,
  ),
  (
    // Only NVIDIA embedder whose portable GGUF was previously HNPU-only.
    // 4.63 GB Q4_K_M — Web-excluded (exceeds the WASM 4 GiB heap).
    id: 'llama-embed-nemotron-8b-q4_k_m',
    name: 'NVIDIA Llama Embed Nemotron 8B Q4_K_M',
    url:
        'https://huggingface.co/mradermacher/llama-embed-nemotron-8b-GGUF/resolve/e7ae3cbae4f7693bbd75ec959bf293f39e1f2e25/llama-embed-nemotron-8b.Q4_K_M.gguf',
    memoryRequirement: 4625233184,
  ),
];

/// ModelCatalogBootstrap
///
/// Mirrors iOS `Core/Services/ModelCatalogBootstrap.swift` (the canonical
/// source of truth) and Android `ModelBootstrap.seedCuratedCatalog`: the
/// curated model catalog lives in one dedicated service, not in the app
/// widget. Uses the canonical `RunAnywhere.models.*` registration APIs,
/// including multi-file and archive-with-structure overloads. Safe to re-run
/// on every cold launch — commons merges runtime fields on re-registration.
abstract final class ModelCatalogBootstrap {
  /// True once the catalog has been registered. Without this guard,
  /// hot-reload (or any second call) re-runs the entire registration block.
  static bool _modulesRegistered = false;

  static Future<void> registerAll({bool mlxRegistered = false}) async {
    if (_modulesRegistered) {
      debugPrint('Catalog already registered — skipping');
      return;
    }
    debugPrint('Registering modules with their models...');

    await _applyPersistedHfToken();

    // --- LLM models (LlamaCpp backend) ------------------------------------
    // Grouped by model family; every family ordered small → large.

    // SmolLM2 (HuggingFace)
    await _registerLLM(
      id: 'smollm2-360m-q8_0',
      name: 'SmolLM2 360M Q8_0',
      url:
          'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 386404416,
    );

    // Qwen — 2.5 first, then 3, small → large inside each generation.
    await _registerLLM(
      id: 'qwen2.5-0.5b-instruct-q6_k',
      name: 'Qwen 2.5 0.5B Instruct Q6_K',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 600000000,
      // Base model of the seeded abliterated adapter
      // (qwen2.5-0.5b-abliterated-lora-f16.gguf) — matches iOS/Android.
      supportsLora: true,
    );
    await _registerLLM(
      id: 'qwen2.5-1.5b-instruct-q4_k_m',
      name: 'Qwen 2.5 1.5B Instruct Q4_K_M',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 2500000000,
    );
    await _registerLLM(
      id: 'qwen3-0.6b-q4_k_m',
      name: 'Qwen3 0.6B Q4_K_M',
      url:
          'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 500000000,
      supportsThinking: true,
    );
    await _registerLLM(
      id: 'qwen3-1.7b-q4_k_m',
      name: 'Qwen3 1.7B Q4_K_M',
      url:
          'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 1200000000,
      supportsThinking: true,
    );
    await _registerLLM(
      id: 'qwen3-4b-q4_k_m',
      name: 'Qwen3 4B Q4_K_M',
      url:
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 2800000000,
      supportsThinking: true,
    );

    // LFM2 / LFM2.5 (Liquid AI)
    // LFM2.5-230M on the CPU. Q4_K_M, not the fractionally smaller Q4_0
    // (149 MB vs 153 MB): 4 MB buys K-quant mixed precision on the
    // attention/embedding tensors, and Q4_K_M is the quantization every
    // other GGUF row in this catalog uses.
    await _registerLLM(
      id: 'lfm2.5-230m-q4_k_m',
      name: 'LiquidAI LFM2.5 230M Q4_K_M',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      // 153,406,304 B of weights plus KV cache and runtime overhead.
      memoryRequirement: 190000000,
    );
    // ONE quantization per model. The Q8_0 sibling of this row was removed
    // deliberately: two quants of the same 350M model differ only in bytes
    // (229 MB vs 379 MB), so the second row costs a catalog slot and a
    // "which one do I pick?" decision without adding a capability.
    await _registerLLM(
      id: 'lfm2-350m-q4_k_m',
      name: 'LiquidAI LFM2 350M Q4_K_M',
      url:
          'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 250000000,
    );
    await _registerLLM(
      id: 'lfm2.5-1.2b-instruct-q4_k_m',
      name: 'LiquidAI LFM2.5 1.2B Instruct Q4_K_M',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 900000000,
    );
    // Same one-quant-per-model rule: the Q8_0 sibling of this row was removed
    // (1.4 GB vs 800 MB for identical capability).
    await _registerLLM(
      id: 'lfm2-1.2b-tool-q4_k_m',
      name: 'LiquidAI LFM2 1.2B Tool Q4_K_M',
      url:
          'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 800000000,
    );

    // Llama (Meta)
    await _registerLLM(
      id: 'llama-3.2-3b-instruct-q4_k_m',
      name: 'Llama 3.2 3B Instruct Q4_K_M (Tool Calling)',
      url:
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 2000000000,
    );
    await _registerLLM(
      id: 'llama-2-7b-chat-q4_k_m',
      name: 'Llama 2 7B Chat Q4_K_M',
      url:
          'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 4000000000,
    );

    // Mistral
    await _registerLLM(
      id: 'mistral-7b-instruct-q4_k_m',
      name: 'Mistral 7B Instruct Q4_K_M',
      url:
          'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 4000000000,
    );

    // Nemotron (NVIDIA) — portable embedding GGUFs on the llama.cpp backend.
    for (final model in portableNvidiaEmbeddingCatalog) {
      await _registerLLM(
        id: model.id,
        name: model.name,
        url: model.url,
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
        memoryRequirement: model.memoryRequirement,
      );
    }

    // Bonsai (PrismML)
    // PrismML Bonsai-27B at 1.125-bit (Q1_0, qwen3_5 GatedDeltaNet). The
    // canonical-first RunAnywhere llama.cpp fork preserves this support beside
    // its Maple compatibility delta.
    await _registerLLM(
      id: 'bonsai-27b-q1_0',
      name: 'Bonsai-27B 1-bit Q1_0 (CPU)',
      url:
          'https://huggingface.co/prism-ml/Bonsai-27B-gguf/resolve/main/Bonsai-27B-Q1_0.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 3803452480,
      supportsThinking: true,
    );
    debugPrint('LLM models registered');

    if (mlxRegistered) {
      await _registerAppleMlxModels();
    } else {
      debugPrint('Skipping Apple MLX models — backend unavailable');
    }

    // --- VLM models (multi-modal, multi-file) -----------------------------
    // Grouped by model family; every family ordered small → large.

    // SmolVLM (HuggingFace)
    await _registerArchive(
      id: 'smolvlm-500m-instruct-q8_0',
      name: 'SmolVLM 500M Instruct',
      url:
          'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      archive: ArchiveType.ARCHIVE_TYPE_TAR_GZ,
      structure: ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
      memoryRequirement: 600000000,
    );
    // Qwen2-VL
    await _registerMultiFile(
      id: 'qwen2-vl-2b-instruct-q4_k_m',
      name: 'Qwen2-VL 2B Instruct',
      files: [
        (
          url:
              'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
          filename: 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
        ),
        (
          url:
              'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
          filename: 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
        ),
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      memoryRequirement: 1800000000,
    );
    // LFM2-VL (Liquid AI)
    await _registerMultiFile(
      id: 'lfm2-vl-450m-q8_0',
      name: 'LFM2-VL 450M',
      files: [
        (
          url:
              'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
          filename: 'LFM2-VL-450M-Q8_0.gguf',
        ),
        (
          url:
              'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf',
          filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf',
        ),
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      memoryRequirement: 600000000,
    );
    // Fara (Microsoft)
    // Fara1.5 — Computer-Use Agent profile model, mirrors the Android/iOS/RN
    // catalog rows so `RunAnywhere.cua` has a drivable model on every
    // platform. `cuaProfile` lands on `ModelInfo.cuaProfile`
    // (PR #605 review issue 9).
    await _registerMultiFile(
      id: 'fara1.5-4b-q4_k_m',
      name: 'Fara1.5 4B Computer-Use Agent Q4_K_M',
      files: [
        (
          url:
              'https://huggingface.co/runanywhere/Fara1.5-4B-GGUF/resolve/main/Fara1.5-4B-Q4_K_M.gguf',
          filename: 'Fara1.5-4B-Q4_K_M.gguf',
        ),
        (
          url:
              'https://huggingface.co/runanywhere/Fara1.5-4B-GGUF/resolve/main/mmproj-Fara1.5-4B-f16.gguf',
          filename: 'mmproj-Fara1.5-4B-f16.gguf',
        ),
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      memoryRequirement: 3300000000,
      cuaProfile: RunAnywhereCUA.faraProfile,
    );
    debugPrint('VLM models registered');

    // --- STT models (Sherpa-ONNX) -----------------------------------------
    // Whisper (OpenAI)
    await _registerArchive(
      id: 'sherpa-onnx-whisper-tiny.en',
      name: 'Sherpa Whisper Tiny (ONNX)',
      url:
          'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      archive: ArchiveType.ARCHIVE_TYPE_TAR_GZ,
      structure: ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
      memoryRequirement: 75000000,
    );

    // --- TTS models (Sherpa-ONNX Piper VITS) ------------------------------
    // Piper VITS
    await _registerArchive(
      id: 'vits-piper-en_US-lessac-medium',
      name: 'Piper TTS (US English - Medium)',
      url:
          'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      archive: ArchiveType.ARCHIVE_TYPE_TAR_GZ,
      structure: ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
      memoryRequirement: 65000000,
    );
    await _registerArchive(
      id: 'vits-piper-en_GB-alba-medium',
      name: 'Piper TTS (British English)',
      url:
          'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      archive: ArchiveType.ARCHIVE_TYPE_TAR_GZ,
      structure: ArchiveStructure.ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
      memoryRequirement: 65000000,
    );

    // --- VAD (Silero, ONNX) -------------------------------------------------
    // Silero
    await _registerLLM(
      id: 'silero-vad',
      name: 'Silero VAD',
      url:
          'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      modality: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
      // Actual silero_vad.onnx Content-Length for catalog display/storage
      // planning; the SDK keeps downloadSizeBytes separate.
      memoryRequirement: 2327524,
    );
    debugPrint('Sherpa STT/TTS + Silero VAD models registered');

    // --- Embeddings (ONNX, RAG) -------------------------------------------
    // All MiniLM (sentence-transformers)
    // MiniLM needs model.onnx + vocab.txt in the same folder for the C++
    // RAG pipeline to find its vocab next to the model.
    await _registerMultiFile(
      id: 'all-minilm-l6-v2',
      name: 'All MiniLM L6 v2 (Embedding)',
      files: [
        (
          url:
              'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
          filename: 'model.onnx',
        ),
        (
          url:
              'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt',
          filename: 'vocab.txt',
        ),
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      memoryRequirement: 25500000,
    );
    debugPrint('ONNX Embedding models registered');

    // --- Diffusion (image generation, Apple CoreML-only) -------------------
    // The Swift facade + CoreML Stable-Diffusion backend landed in 0.20.10.
    // There is no Android/CoreML diffusion backend, so the row is registered
    // only on Apple platforms and never appears on Android.
    if (Platform.isIOS || Platform.isMacOS) {
      // Stable Diffusion (Stability AI, Apple CoreML conversion)
      await _registerDiffusion(
        id: 'stable-diffusion-v1-5-coreml',
        name: 'Stable Diffusion 1.5 (CoreML)',
        url:
            'https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized',
        memoryRequirement: 1200000000,
      );
      debugPrint('Diffusion (CoreML) models registered');
    }

    // --- LoRA adapters ------------------------------------------------------
    // Mirrors iOS `registerLoraAdapters` / Android `ModelBootstrap.seedLora`.
    await _registerLoraAdapters();
    debugPrint('LoRA adapters registered');

    // --- QHexRT (Hexagon NPU) bundles ---------------------------------------
    // Native QHexRT probes the device, chooses the exact Hexagon bundle, and
    // returns the registered architecture-specific model ID.
    await _registerNpuBundles();

    debugPrint('All modules and models registered');
    _modulesRegistered = true;
  }

  /// A compact Apple MLX catalog aligned with the canonical iOS example.
  /// One proven model per supported modality keeps the Flutter example useful
  /// without duplicating the full iOS catalog.
  static Future<void> _registerAppleMlxModels() async {
    // --- MLX LLM (Apple Metal) --------------------------------------------
    // Qwen
    await _registerLLM(
      id: 'mlx-qwen3-0.6b-4bit',
      name: 'MLX Qwen3 0.6B 4bit',
      url: 'https://huggingface.co/mlx-community/Qwen3-0.6B-4bit',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
      memoryRequirement: 650000000,
      supportsThinking: true,
    );
    // LFM2.5 (Liquid AI)
    // A PLAIN REPO ref, not a `/4bit` subfolder ref like LFM2.5-2.6B-MLX.
    // LiquidAI publishes one precision per repo here — the 4-bit weights sit
    // at the repo ROOT alongside config.json and tokenizer.json — so
    // appending a precision segment would 404.
    await _registerLLM(
      id: 'mlx-lfm2.5-230m-4bit',
      name: 'MLX LFM2.5 230M 4bit',
      url: 'https://huggingface.co/LiquidAI/LFM2.5-230M-MLX-4bit',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
      memoryRequirement: 200000000,
    );
    // Bonsai (PrismML)
    // PrismML Bonsai-27B 1-bit MLX (~5.1 GB). Experimental due to its size;
    // requires the paired RunAnywhere MLX/MLX Swift tags.
    await _registerLLM(
      id: 'mlx-bonsai-27b-1bit',
      name: 'MLX Bonsai-27B 1-bit',
      url: 'https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
      memoryRequirement: 5129115752,
      supportsThinking: true,
    );

    // --- MLX VLM (multimodal) ---------------------------------------------
    // Qwen2-VL
    await _registerLLM(
      id: 'mlx-qwen2-vl-2b-instruct-4bit',
      name: 'MLX Qwen2-VL 2B Instruct 4bit',
      url: 'https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      memoryRequirement: 2200000000,
    );

    // --- MLX STT ----------------------------------------------------------
    // Qwen3-ASR
    await _registerMultiFile(
      id: 'mlx-qwen3-asr-0.6b-8bit',
      name: 'MLX Qwen3-ASR 0.6B 8bit',
      files: [
        (
          url:
              'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/chat_template.json',
          filename: 'chat_template.json',
        ),
        (
          url:
              'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/config.json',
          filename: 'config.json',
        ),
        (
          url:
              'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/generation_config.json',
          filename: 'generation_config.json',
        ),
        (
          url:
              'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/merges.txt',
          filename: 'merges.txt',
        ),
        (
          url:
              'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors',
          filename: 'model.safetensors',
        ),
        (
          url:
              'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors.index.json',
          filename: 'model.safetensors.index.json',
        ),
        (
          url:
              'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/preprocessor_config.json',
          filename: 'preprocessor_config.json',
        ),
        (
          url:
              'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/tokenizer_config.json',
          filename: 'tokenizer_config.json',
        ),
        (
          url:
              'https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/vocab.json',
          filename: 'vocab.json',
        ),
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      memoryRequirement: 1010773761,
    );

    // --- MLX TTS ----------------------------------------------------------
    // Kokoro
    await _registerLLM(
      id: 'mlx-kokoro-82m-6bit',
      name: 'MLX Kokoro 82M 6bit',
      url: 'https://huggingface.co/mlx-community/Kokoro-82M-6bit',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      memoryRequirement: 309640166,
    );

    // --- MLX Embeddings ---------------------------------------------------
    // Qwen3 Embedding
    await _registerLLM(
      id: 'mlx-qwen3-embedding-0.6b-4bit-dwq',
      name: 'MLX Qwen3 Embedding 0.6B 4bit DWQ',
      url: 'https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
      modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      memoryRequirement: 350000000,
    );
    debugPrint('Apple MLX models registered');
  }

  /// Register logical HNPU rows. QHexRT's native bundle resolver chooses the
  /// current device arch; unsupported devices or missing HF child dirs fail
  /// registration and never appear as runnable models.
  static Future<void> _registerNpuBundles() async {
    final result = await QHexRTModelCatalog.registerForCurrentDevice();
    debugPrint(
      'QHexRT catalog registered: ok=${result.registered} '
      'failed=${result.failed} skippedNative=${result.skippedNative}',
    );
  }

  static Future<void> refreshNpuCatalog() async {
    await _applyPersistedHfToken();
    await _registerNpuBundles();
    // models.list() reconciles the registry against disk after registration.
    await RunAnywhere.models.list();
  }

  static Future<void> _applyPersistedHfToken() async {
    final token = await HfTokenStore.load();
    if (token.isEmpty) {
      RunAnywhere.setHfToken('');
      return;
    }
    RunAnywhere.setHfToken(token);
  }

  /// Seed the curated LoRA adapter catalog. `LoraAdapterCatalogEntry` no
  /// longer carries url/filename/size/description (idl/lora_options.proto:
  /// "everything generic about the artifact ... lives on the ModelInfo
  /// record for this adapter"), so those fields move onto a companion
  /// [ModelInfo] artifact passed to `RunAnywhere.lora.register` alongside the
  /// catalog entry. Mirrors iOS `RunAnywhere+LoRADownload.swift`/Web
  /// `RunAnywhere+LoRA.ts`'s `toLoraArtifactModelInfo`. Does not fetch bytes;
  /// safe to re-run on every cold launch.
  static Future<void> _registerLoraAdapters() async {
    const adapterId = 'abliterated-lora';
    const artifactUrl =
        'https://huggingface.co/Void2377/qwen-lora-gguf/resolve/main/qwen2.5-0.5b-abliterated-lora-f16.gguf';
    const artifactFilename = 'qwen2.5-0.5b-abliterated-lora-f16.gguf';
    const artifactSizeBytes = 17620224;

    final adapter = LoraAdapterCatalogEntry(
      id: adapterId,
      name: 'Abliterated LoRA (F16)',
      compatibleModels: ['qwen2.5-0.5b-instruct-q6_k'],
      defaultScale: 1.0,
    );
    final artifact = proto.ModelInfo(
      id: 'lora-adapter:$adapterId',
      name: adapter.name,
      category: ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
      format: ModelFormat.MODEL_FORMAT_GGUF,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
      downloadUrl: artifactUrl,
      downloadSizeBytes: Int64(artifactSizeBytes),
      source: ModelSource.MODEL_SOURCE_REMOTE,
      singleFile: proto.SingleFileArtifact(
        expectedFiles: proto.ExpectedModelFiles(
          files: [
            ModelFileDescriptor(
              url: artifactUrl,
              filename: artifactFilename,
              sizeBytes: Int64(artifactSizeBytes),
              role: proto.ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
            ),
          ],
          requiredPatterns: [artifactFilename],
          description: 'LoRA adapter artifact',
        ),
      ),
      metadata: proto.ModelInfoMetadata(
        description:
            'Removes refusal behavior — model answers directly without disclaimers',
      ),
    );
    try {
      await RunAnywhere.lora.register(adapter, artifact);
    } catch (e) {
      debugPrint('Failed to register LoRA adapter: $e');
    }
  }

  // --- Registration helpers (mirror iOS registerLLM/registerArchive/
  // registerMultiFile shape, including per-model swallow-and-warn) ----------

  static Future<void> _registerLLM({
    required String id,
    required String name,
    required String url,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.MODEL_CATEGORY_LANGUAGE,
    required int memoryRequirement,
    bool supportsThinking = false,
    bool supportsLora = false,
  }) async {
    try {
      await RunAnywhere.models.register(
        ModelRegistration.url(
          id: id,
          name: name,
          url: url,
          framework: framework,
          category: modality,
          memoryRequirementBytes: memoryRequirement,
          supportsThinking: supportsThinking,
          supportsLora: supportsLora,
        ),
      );
    } catch (e) {
      debugPrint('Failed to register model $id: $e');
    }
  }

  /// Register the Apple CoreML Stable-Diffusion catalog row (image generation).
  /// Framework is CoreML and modality is image-generation so the SDK routes it
  /// to the diffusion component. Swallow-and-warn like the other helpers.
  static Future<void> _registerDiffusion({
    required String id,
    required String name,
    required String url,
    required int memoryRequirement,
  }) async {
    try {
      await RunAnywhere.models.register(
        ModelRegistration.url(
          id: id,
          name: name,
          url: url,
          framework: InferenceFramework.INFERENCE_FRAMEWORK_COREML,
          category: ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
          memoryRequirementBytes: memoryRequirement,
        ),
      );
    } catch (e) {
      debugPrint('Failed to register diffusion model $id: $e');
    }
  }

  static Future<void> _registerArchive({
    required String id,
    required String name,
    required String url,
    required InferenceFramework framework,
    required ModelCategory modality,
    required ArchiveType archive,
    required ArchiveStructure structure,
    required int memoryRequirement,
  }) async {
    try {
      await RunAnywhere.models.register(
        ModelRegistration.archive(
          id: id,
          name: name,
          url: url,
          archiveType: archive,
          structure: structure,
          framework: framework,
          category: modality,
          memoryRequirementBytes: memoryRequirement,
        ),
      );
    } catch (e) {
      debugPrint('Failed to register archive model $id: $e');
    }
  }

  static Future<void> _registerMultiFile({
    required String id,
    required String name,
    required List<({String url, String filename})> files,
    required InferenceFramework framework,
    required ModelCategory modality,
    required int memoryRequirement,
    String? cuaProfile,
  }) async {
    // File roles are left unset: the SDK fills them from the shared commons
    // classifier so the app never mirrors its filename conventions.
    // `isRequired` was deleted; `ModelFileDescriptor.isOptional` is the
    // renamed/inverted field, and every file here is required (isOptional:
    // false, which is also the default when left unset).
    final descriptors = files
        .map(
          (file) => ModelFileDescriptor(
            filename: file.filename,
            url: file.url,
            isOptional: false,
          ),
        )
        .toList();
    try {
      await RunAnywhere.models.register(
        ModelRegistration.multiFile(
          id: id,
          name: name,
          files: descriptors,
          framework: framework,
          category: modality,
          memoryRequirementBytes: memoryRequirement,
          cuaProfile: cuaProfile,
        ),
      );
    } catch (e) {
      debugPrint('Failed to register multi-file model $id: $e');
    }
  }
}
