import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/app/content_view.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
import 'package:runanywhere_ai/core/utilities/url_utils.dart';
import 'package:runanywhere_genie/runanywhere_genie.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

/// RunAnywhereAIApp
///
/// Main application entry point with SDK initialization.
class RunAnywhereAIApp extends StatefulWidget {
  const RunAnywhereAIApp({super.key});

  @override
  State<RunAnywhereAIApp> createState() => _RunAnywhereAIAppState();
}

class _RunAnywhereAIAppState extends State<RunAnywhereAIApp> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeSDK());
    });
  }

  Future<void> _initializeSDK() async {
    final stopwatch = Stopwatch()..start();

    try {
      debugPrint('🎯 Initializing SDK...');

      final customApiKey = await KeychainHelper.loadString(KeychainKeys.apiKey);
      final customBaseURL =
          await KeychainHelper.loadString(KeychainKeys.baseURL);
      final hasCustomConfig = customApiKey != null &&
          customApiKey.isNotEmpty &&
          customBaseURL != null &&
          customBaseURL.isNotEmpty &&
          !_looksLikePlaceholder(customApiKey) &&
          !_looksLikePlaceholder(customBaseURL);

      if (hasCustomConfig) {
        final normalizedURL = normalizeBaseURL(customBaseURL);
        debugPrint('🔧 Found custom API configuration');
        debugPrint('   Base URL: $normalizedURL');

        await RunAnywhere.initialize(
          apiKey: customApiKey,
          baseURL: normalizedURL,
          environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
        );
        debugPrint('✅ SDK initialized with CUSTOM configuration (production)');
        await RunAnywhere.completeServicesInitialization();
      } else {
        await RunAnywhere.initialize();
        debugPrint('✅ SDK initialized in DEVELOPMENT mode');
      }

      // Model paths + registry must be ready before catalog registration.
      await RunAnywhere.completeServicesInitialization();
      await _registerModulesAndModels();

      stopwatch.stop();
      debugPrint(
          '⚡ SDK initialization completed in ${stopwatch.elapsedMilliseconds}ms');
      debugPrint(
          '🎯 SDK Status: ${RunAnywhere.isActive ? "Active" : "Inactive"}');
      debugPrint(
          '🔧 Environment: ${RunAnywhere.environment?.description ?? "Unknown"}');

      debugPrint(
          '💡 Models registered, user can now download and select models');
      debugPrint('App is ready to use');
      debugPrint('__RUNANYWHERE_AI_READY__');
      debugPrint('Services initialized for catalog refresh');
    } catch (e) {
      stopwatch.stop();
      debugPrint(
          '❌ SDK initialization failed after ${stopwatch.elapsedMilliseconds}ms: $e');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('SDK init error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  bool _looksLikePlaceholder(String value) {
    return RegExp(r'YOUR_|<your|REPLACE_ME|PLACEHOLDER', caseSensitive: false)
        .hasMatch(value);
  }

  /// True once we've registered modules + models once. Without
  /// this guard, hot-reload (or any second call) re-runs the entire
  /// LLM catalog registration block, which is wasteful (B-FL-3-002).
  static bool _modulesRegistered = false;

  Future<void> _registerLanguageModel({
    required String id,
    required String name,
    required String url,
    required InferenceFramework framework,
    required int memoryRequirement,
    bool supportsThinking = false,
  }) => RunAnywhere.models.register(
    id: id,
    name: name,
    url: url,
    framework: framework,
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    memoryRequirement: memoryRequirement,
    supportsThinking: supportsThinking,
  );

  /// Register modules with their associated models
  /// Each module explicitly owns its models - the framework is determined by the module
  Future<void> _registerModulesAndModels() async {
    if (_modulesRegistered) {
      debugPrint('📦 Modules already registered — skipping (B-FL-3-002)');
      return;
    }
    debugPrint('📦 Registering modules with their models...');

    // --- LLAMACPP MODULE ---
    await LlamaCpp.register();
    await Future<void>.delayed(Duration.zero);

    await _registerLanguageModel(
      id: 'smollm2-360m-q8_0',
      name: 'SmolLM2 360M Q8_0',
      url:
          'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 386404416,
    );
    await _registerLanguageModel(
      id: 'llama-2-7b-chat-q4_k_m',
      name: 'Llama 2 7B Chat Q4_K_M',
      url:
          'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 4000000000,
    );
    await _registerLanguageModel(
      id: 'mistral-7b-instruct-q4_k_m',
      name: 'Mistral 7B Instruct Q4_K_M',
      url:
          'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 4000000000,
    );
    await _registerLanguageModel(
      id: 'qwen2.5-0.5b-instruct-q6_k',
      name: 'Qwen 2.5 0.5B Instruct Q6_K',
      url:
          'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 600000000,
    );
    await _registerLanguageModel(
      id: 'qwen2.5-1.5b-instruct-q4_k_m',
      name: 'Qwen 2.5 1.5B Instruct Q4_K_M',
      url:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 2500000000,
    );
    await _registerLanguageModel(
      id: 'qwen3-0.6b-q4_k_m',
      name: 'Qwen3 0.6B Q4_K_M',
      url:
          'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 477000000,
      supportsThinking: true,
    );
    await _registerLanguageModel(
      id: 'qwen3-1.7b-q4_k_m',
      name: 'Qwen3 1.7B Q4_K_M',
      url:
          'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 1200000000,
      supportsThinking: true,
    );
    await _registerLanguageModel(
      id: 'qwen3-4b-q4_k_m',
      name: 'Qwen3 4B Q4_K_M',
      url:
          'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 2800000000,
      supportsThinking: true,
    );
    await _registerLanguageModel(
      id: 'lfm2-350m-q4_k_m',
      name: 'LiquidAI LFM2 350M Q4_K_M',
      url:
          'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 250000000,
    );
    await _registerLanguageModel(
      id: 'lfm2-350m-q8_0',
      name: 'LiquidAI LFM2 350M Q8_0',
      url:
          'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 400000000,
    );

    await _registerLanguageModel(
      id: 'lfm2-1.2b-tool-q4_k_m',
      name: 'LiquidAI LFM2 1.2B Tool Q4_K_M',
      url:
          'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 800000000,
    );
    await _registerLanguageModel(
      id: 'lfm2-1.2b-tool-q8_0',
      name: 'LiquidAI LFM2 1.2B Tool Q8_0',
      url:
          'https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      memoryRequirement: 1400000000,
    );
    debugPrint('✅ LlamaCPP module registered');
    await Future<void>.delayed(Duration.zero);

    // --- GENIE NPU MODULE (Android/Snapdragon only) ---
    if (Genie.isAvailable) {
      await Genie.register(priority: 200);
      debugPrint(
          '✅ Genie backend registered; NPU model catalog is pending generated registry/catalog support');
    } else {
      debugPrint('ℹ️ Genie NPU not available (non-Snapdragon device)');
    }
    await Future<void>.delayed(Duration.zero);

    // --- VLM MODULE ---
    await RunAnywhere.models.registerArchiveModel(
      id: 'smolvlm-500m-instruct-q8_0',
      name: 'SmolVLM 500M Instruct',
      archiveUrl:
          'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz',
      structure: ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      archiveType: ArchiveType.ARCHIVE_TYPE_TAR_GZ,
      memoryRequirement: 600000000,
    );
    // Qwen2-VL 2B — multi-file (main GGUF + mmproj companion).
    await RunAnywhere.models.registerMultiFile(
      id: 'qwen2-vl-2b-instruct-q4_k_m',
      name: 'Qwen2-VL 2B Instruct',
      files: [
        ModelFileDescriptor(
          filename: 'Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
          url:
              'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
          isRequired: true,
        ),
        ModelFileDescriptor(
          filename: 'mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
          url:
              'https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf',
          isRequired: true,
        ),
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      memoryRequirement: 1800000000,
    );
    // LFM2-VL 450M — multi-file (LiquidAI compact VLM).
    await RunAnywhere.models.registerMultiFile(
      id: 'lfm2-vl-450m-q8_0',
      name: 'LFM2-VL 450M',
      files: [
        ModelFileDescriptor(
          filename: 'LFM2-VL-450M-Q8_0.gguf',
          url:
              'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf',
          isRequired: true,
        ),
        ModelFileDescriptor(
          filename: 'mmproj-LFM2-VL-450M-Q8_0.gguf',
          url:
              'https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf',
          isRequired: true,
        ),
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      memoryRequirement: 600000000,
    );
    debugPrint('✅ VLM models registered');
    await Future<void>.delayed(Duration.zero);

    // --- SHERPA-ONNX MODULE (STT/TTS via Core SDK) ---
    // STT Models (Sherpa-ONNX Whisper) — served by the Sherpa-ONNX engine plugin
    await RunAnywhere.models.register(
      id: 'sherpa-onnx-whisper-tiny.en',
      name: 'Sherpa Whisper Tiny (ONNX)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      memoryRequirement: 75000000,
    );

    await RunAnywhere.models.register(
      id: 'sherpa-onnx-whisper-small.en',
      name: 'Sherpa Whisper Small (ONNX)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-small.en.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      memoryRequirement: 250000000,
    );

    // TTS Models (Piper VITS) — served by the Sherpa-ONNX engine plugin
    await RunAnywhere.models.register(
      id: 'vits-piper-en_US-lessac-medium',
      name: 'Piper TTS (US English - Medium)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      memoryRequirement: 65000000,
    );

    await RunAnywhere.models.register(
      id: 'vits-piper-en_GB-alba-medium',
      name: 'Piper TTS (British English)',
      url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      memoryRequirement: 65000000,
    );

    // System TTS pseudo-model — Apple-only. The commons `platform` engine
    // plugin (AVSpeechSynthesizer-backed) is gated behind
    // `if(APPLE AND RAC_BUILD_PLATFORM)` in
    // sdk/runanywhere-commons/CMakeLists.txt:732, so on Android there is
    // no native route for `framework=platform`. Mirrors the Swift SDK and
    // the Kotlin SDK (which only registers SystemTTSModule on Apple via
    // the platform plugin path).
    if (Platform.isIOS || Platform.isMacOS) {
      await RunAnywhere.models.register(
        id: 'system-tts',
        name: 'System TTS',
        url: 'about:blank',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS,
        modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        memoryRequirement: 0,
      );
    }
    // VAD (Silero) — registered here so the voice-agent pipeline has a
    // default detector available alongside STT/TTS.
    await RunAnywhere.models.register(
      id: 'silero-vad',
      name: 'Silero VAD',
      url: 'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      modality: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
      memoryRequirement: 5000000,
    );
    debugPrint(
        '✅ STT/TTS/VAD models registered via Core SDK (incl. system-tts)');
    await Future<void>.delayed(Duration.zero);

    // --- RAG EMBEDDINGS ---
    await RunAnywhere.models.registerMultiFile(
      id: 'all-minilm-l6-v2',
      name: 'All MiniLM L6 v2 (Embedding)',
      files: [
        ModelFileDescriptor(
          filename: 'model.onnx',
          url:
              'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx',
          isRequired: true,
        ),
        ModelFileDescriptor(
          filename: 'vocab.txt',
          url:
              'https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt',
          isRequired: true,
        ),
      ],
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      memoryRequirement: 25500000,
    );
    debugPrint('✅ ONNX Embedding models registered');
    await Future<void>.delayed(Duration.zero);

    // --- ONNX BACKEND (required for embeddings used by RAG) ---
    try {
      await Onnx.register();
      debugPrint('✅ ONNX backend registered (STT + TTS + VAD + Embeddings)');
    } catch (e) {
      debugPrint('⚠️ ONNX backend not available: $e');
    }

    // --- RAG BACKEND ---
    try {
      await RAGModule.register();
      debugPrint('✅ RAG backend registered');
    } catch (e) {
      debugPrint('⚠️ RAG backend not available (RAG features disabled): $e');
    }

    debugPrint('🎉 All modules and models registered');
    _modulesRegistered = true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      title: 'RunAnywhere AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryBlue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: AppColors.primaryBlue.withValues(alpha: 0.2),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryBlue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    return const ContentView();
  }
}
