import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
import 'package:runanywhere_genie/runanywhere_genie.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/npu_chip.dart';

typedef ProgressCallback = void Function(double progress, String status);

Future<void> initializeSDK(ProgressCallback onProgress) async {
  onProgress(0.05, 'Initializing core SDK...');
  await sdk.RunAnywhere.initialize();
  debugPrint('SDK initialized');

  onProgress(0.15, 'Registering LlamaCpp backend...');
  await LlamaCpp.register();
  await Future<void>.delayed(Duration.zero);

  onProgress(0.25, 'Adding LLM models...');
  _registerLlamaCppModels();

  onProgress(0.40, 'Checking NPU availability...');
  await _registerGenieModels();

  onProgress(0.50, 'Registering ONNX backend...');
  await Onnx.register();
  await Future<void>.delayed(Duration.zero);

  onProgress(0.55, 'Registering vision models...');
  _registerVLMModels();
  await Future<void>.delayed(Duration.zero);

  onProgress(0.65, 'Registering speech-to-text models...');
  _registerSTTModels();

  onProgress(0.75, 'Registering text-to-speech voices...');
  _registerTTSModels();

  onProgress(0.85, 'Registering embedding models...');
  _registerEmbeddingModels();
  await Future<void>.delayed(Duration.zero);

  onProgress(0.95, 'Finalizing setup...');
  await Future<void>.delayed(const Duration(milliseconds: 200));

  onProgress(1.0, 'Ready');
}

void _registerLlamaCppModels() {
  LlamaCpp.addModel(
    id: 'smollm2-360m-q8_0',
    name: 'SmolLM2 360M Q8_0',
    url:
        'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
    memoryRequirement: 500000000,
  );
  LlamaCpp.addModel(
    id: 'qwen2.5-0.5b-instruct-q6_k',
    name: 'Qwen 2.5 0.5B Instruct Q6_K',
    url:
        'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
    memoryRequirement: 600000000,
  );
  LlamaCpp.addModel(
    id: 'lfm2-350m-q4_k_m',
    name: 'LiquidAI LFM2 350M Q4_K_M',
    url:
        'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
    memoryRequirement: 250000000,
  );
  LlamaCpp.addModel(
    id: 'lfm2-350m-q8_0',
    name: 'LiquidAI LFM2 350M Q8_0',
    url:
        'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
    memoryRequirement: 400000000,
  );
  LlamaCpp.addModel(
    id: 'llama-2-7b-chat-q4_k_m',
    name: 'Llama 2 7B Chat Q4_K_M',
    url:
        'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
    memoryRequirement: 4000000000,
  );
  LlamaCpp.addModel(
    id: 'mistral-7b-instruct-q4_k_m',
    name: 'Mistral 7B Instruct Q4_K_M',
    url:
        'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
    memoryRequirement: 4000000000,
  );
  LlamaCpp.addModel(
    id: 'lfm2-1.2b-tool-q4_k_m',
    name: 'LiquidAI LFM2 1.2B Tool Q4_K_M',
    url:
        'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf',
    memoryRequirement: 800000000,
  );
  LlamaCpp.addModel(
    id: 'lfm2-1.2b-tool-q8_0',
    name: 'LiquidAI LFM2 1.2B Tool Q8_0',
    url:
        'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf',
    memoryRequirement: 1400000000,
  );
}

Future<void> _registerGenieModels() async {
  if (!Genie.isAvailable) {
    debugPrint('Genie NPU not available');
    return;
  }

  await Genie.register(priority: 200);
  final chip = await sdk.RunAnywhereDevice.getChip();
  if (chip == null) return;

  final genieModels = [
    (slug: 'qwen3-4b', name: 'Qwen3 4B', mem: 2800000000, quant: 'w4a16', chips: {NPUChip.snapdragon8EliteGen5}),
    (slug: 'llama3.2-1b-instruct', name: 'Llama 3.2 1B Instruct', mem: 1200000000, quant: 'w4a16', chips: {NPUChip.snapdragon8Elite, NPUChip.snapdragon8EliteGen5}),
    (slug: 'sea-lion3.5-8b-instruct', name: 'SEA-LION v3.5 8B Instruct', mem: 4800000000, quant: 'w4a16', chips: {NPUChip.snapdragon8Elite, NPUChip.snapdragon8EliteGen5}),
    (slug: 'qwen2.5-7b-instruct', name: 'Qwen 2.5 7B Instruct', mem: 4200000000, quant: 'w8a16', chips: {NPUChip.snapdragon8Elite}),
  ];
  for (final m in genieModels) {
    if (m.chips.contains(chip)) {
      Genie.addModel(
        id: '${m.slug}-npu-${chip.identifier}',
        name: '${m.name} (NPU - ${chip.displayName})',
        url: chip.downloadUrl(m.slug, quant: m.quant),
        memoryRequirement: m.mem,
      );
    }
  }
}

void _registerVLMModels() {
  sdk.RunAnywhere.registerModel(
    id: 'smolvlm-500m-instruct-q8_0',
    name: 'SmolVLM 500M Instruct',
    url: Uri.parse(
        'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz'),
    framework: InferenceFramework.llamaCpp,
    modality: ModelCategory.multimodal,
    artifactType: ModelArtifactType.tarGzArchive(
      structure: ArchiveStructure.directoryBased,
    ),
    memoryRequirement: 600000000,
  );
}

void _registerSTTModels() {
  sdk.RunAnywhere.registerModel(
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Sherpa Whisper Tiny (ONNX)',
    url: Uri.parse(
        'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz'),
    framework: InferenceFramework.onnx,
    modality: ModelCategory.speechRecognition,
    memoryRequirement: 75000000,
  );
  sdk.RunAnywhere.registerModel(
    id: 'sherpa-onnx-whisper-small.en',
    name: 'Sherpa Whisper Small (ONNX)',
    url: Uri.parse(
        'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-small.en.tar.gz'),
    framework: InferenceFramework.onnx,
    modality: ModelCategory.speechRecognition,
    memoryRequirement: 250000000,
  );
}

void _registerTTSModels() {
  sdk.RunAnywhere.registerModel(
    id: 'vits-piper-en_US-lessac-medium',
    name: 'Piper TTS (US English - Medium)',
    url: Uri.parse(
        'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz'),
    framework: InferenceFramework.onnx,
    modality: ModelCategory.speechSynthesis,
    memoryRequirement: 65000000,
  );
  sdk.RunAnywhere.registerModel(
    id: 'vits-piper-en_GB-alba-medium',
    name: 'Piper TTS (British English)',
    url: Uri.parse(
        'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz'),
    framework: InferenceFramework.onnx,
    modality: ModelCategory.speechSynthesis,
    memoryRequirement: 65000000,
  );
}

void _registerEmbeddingModels() {
  sdk.RunAnywhere.registerMultiFileModel(
    id: 'all-minilm-l6-v2',
    name: 'All MiniLM L6 v2 (Embedding)',
    files: [
      ModelFileDescriptor(
        relativePath: 'model.onnx',
        destinationPath: 'model.onnx',
        url: Uri.parse(
            'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx'),
      ),
      ModelFileDescriptor(
        relativePath: 'vocab.txt',
        destinationPath: 'vocab.txt',
        url: Uri.parse(
            'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt'),
      ),
    ],
    framework: InferenceFramework.onnx,
    modality: ModelCategory.embedding,
    memoryRequirement: 90000000,
  );
}
