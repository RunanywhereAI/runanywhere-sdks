import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';

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

  static Future<void> registerAll() async {
    if (_modulesRegistered) {
      debugPrint('📦 Catalog already registered — skipping');
      return;
    }
    debugPrint('📦 Registering modules with their models...');

    // --- LLM models (LlamaCpp backend) ------------------------------------
    await _registerLLM(
      id: 'smollm2-360m-q8_0',
      name: 'SmolLM2 360M Q8_0',
      url:
          'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 386404416,
    );
    await _registerLLM(
      id: 'llama-2-7b-chat-q4_k_m',
      name: 'Llama 2 7B Chat Q4_K_M',
      url:
          'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 4000000000,
    );
    await _registerLLM(
      id: 'mistral-7b-instruct-q4_k_m',
      name: 'Mistral 7B Instruct Q4_K_M',
      url:
          'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 4000000000,
    );
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
      id: 'lfm2-350m-q4_k_m',
      name: 'LiquidAI LFM2 350M Q4_K_M',
      url:
          'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 250000000,
    );
    await _registerLLM(
      id: 'lfm2-350m-q8_0',
      name: 'LiquidAI LFM2 350M Q8_0',
      url:
          'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 400000000,
    );
    await _registerLLM(
      id: 'lfm2.5-1.2b-instruct-q4_k_m',
      name: 'LiquidAI LFM2.5 1.2B Instruct Q4_K_M',
      url:
          'https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 900000000,
    );
    await _registerLLM(
      id: 'lfm2-1.2b-tool-q4_k_m',
      name: 'LiquidAI LFM2 1.2B Tool Q4_K_M',
      url:
          'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 800000000,
    );
    await _registerLLM(
      id: 'lfm2-1.2b-tool-q8_0',
      name: 'LiquidAI LFM2 1.2B Tool Q8_0',
      url:
          'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 1400000000,
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
    await _registerLLM(
      id: 'llama-3.2-3b-instruct-q4_k_m',
      name: 'Llama 3.2 3B Instruct Q4_K_M (Tool Calling)',
      url:
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 2000000000,
    );
    debugPrint('✅ LLM models registered');

    // --- VLM models (multi-modal, multi-file) -----------------------------
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
    debugPrint('✅ VLM models registered');

    // --- STT models (Sherpa-ONNX) -----------------------------------------
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
    await _registerLLM(
      id: 'silero-vad',
      name: 'Silero VAD',
      url:
          'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      modality: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
      // Actual silero_vad.onnx artifact size (verified Content-Length).
      // memoryRequirement doubles as downloadSizeBytes, which feeds the
      // post-finalize download size guard. An over-stated 5 MB tripped the
      // guard on a valid ~2.3 MB download.
      memoryRequirement: 2327524,
    );
    debugPrint('✅ Sherpa STT/TTS + Silero VAD models registered');

    // --- ONNX Embedding (RAG) ---------------------------------------------
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
    debugPrint('✅ ONNX Embedding models registered');

    // --- LoRA adapters ------------------------------------------------------
    // Mirrors iOS `registerLoraAdapters` / Android `ModelBootstrap.seedLora`.
    await _registerLoraAdapters();
    debugPrint('✅ LoRA adapters registered');

    debugPrint('🎉 All modules and models registered');
    _modulesRegistered = true;
  }

  /// Seed the curated LoRA adapter catalog. `registerArtifact` registers the
  /// catalog entry plus its downloadable artifact record (no bytes fetched);
  /// safe to re-run on every cold launch.
  static Future<void> _registerLoraAdapters() async {
    final adapter = LoraAdapterCatalogEntry(
      id: 'abliterated-lora',
      name: 'Abliterated LoRA (F16)',
      description:
          'Removes refusal behavior — model answers directly without disclaimers',
      url:
          'https://huggingface.co/Void2377/qwen-lora-gguf/resolve/main/qwen2.5-0.5b-abliterated-lora-f16.gguf',
      filename: 'qwen2.5-0.5b-abliterated-lora-f16.gguf',
      compatibleModels: ['qwen2.5-0.5b-instruct-q6_k'],
      sizeBytes: Int64(17620224),
      defaultScale: 1.0,
    );
    try {
      await RunAnywhere.lora.registerArtifact(adapter);
    } catch (e) {
      debugPrint('⚠️ Failed to register LoRA adapter: $e');
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
        id: id,
        name: name,
        url: url,
        framework: framework,
        modality: modality,
        memoryRequirement: memoryRequirement,
        supportsThinking: supportsThinking,
        supportsLora: supportsLora,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to register model $id: $e');
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
      await RunAnywhere.models.registerArchiveModel(
        id: id,
        name: name,
        archiveUrl: url,
        archiveType: archive,
        structure: structure,
        framework: framework,
        modality: modality,
        memoryRequirement: memoryRequirement,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to register archive model $id: $e');
    }
  }

  static Future<void> _registerMultiFile({
    required String id,
    required String name,
    required List<({String url, String filename})> files,
    required InferenceFramework framework,
    required ModelCategory modality,
    required int memoryRequirement,
  }) async {
    final descriptors = files
        .map(
          (file) => ModelFileDescriptor(
            filename: file.filename,
            url: file.url,
            isRequired: true,
            // Shared commons classifier — keeps the SDK and the C++
            // model-paths resolver agreeing on primary vs mmproj/vocab roles.
            role: RunAnywhere.models.inferModelFileRole(
              filename: file.filename,
              modality: modality,
            ),
          ),
        )
        .toList();
    try {
      await RunAnywhere.models.registerMultiFile(
        id: id,
        name: name,
        files: descriptors,
        framework: framework,
        modality: modality,
        memoryRequirement: memoryRequirement,
      );
    } catch (e) {
      debugPrint('⚠️ Failed to register multi-file model $id: $e');
    }
  }
}
