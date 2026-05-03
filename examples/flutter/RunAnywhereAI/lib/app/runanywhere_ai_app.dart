import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/app/content_view.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/services/model_manager.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
import 'package:runanywhere_genie/runanywhere_genie.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';

/// RunAnywhereAIApp (mirroring iOS RunAnywhereAIApp.swift)
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
      _eagerLoadNativeLibraries();
      unawaited(_initializeSDK());
    });
  }

  /// Force [DynamicLibrary.open] for every .so we ship in jniLibs.
  /// Failures are logged but do not abort startup — devices that can't
  /// load a particular backend still get a working SDK with that
  /// backend disabled.
  void _eagerLoadNativeLibraries() {
    if (!Platform.isAndroid) return;
    const libs = <String>[
      'librac_commons.so',
      'librac_backend_llamacpp.so',
      'librac_backend_genie.so',
      'librac_backend_genie_jni.so',
      'librunanywhere_genie.so',
      'librunanywhere_llamacpp.so',
    ];
    for (final lib in libs) {
      try {
        DynamicLibrary.open(lib);
        if (kDebugMode) debugPrint('🔗 Eager-loaded $lib');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Eager-load skipped for $lib: $e');
      }
    }
  }

  /// Normalize base URL by adding https:// if no scheme is present
  String _normalizeBaseURL(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
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
          customBaseURL.isNotEmpty;

      if (hasCustomConfig) {
        final normalizedURL = _normalizeBaseURL(customBaseURL);
        debugPrint('🔧 Found custom API configuration');
        debugPrint('   Base URL: $normalizedURL');

        await RunAnywhereSDK.instance.initialize(
          apiKey: customApiKey,
          baseURL: normalizedURL,
          environment: SDKEnvironment.production,
        );
        debugPrint('✅ SDK initialized with CUSTOM configuration (production)');
      } else {
        await RunAnywhereSDK.instance.initialize();
        debugPrint('✅ SDK initialized in DEVELOPMENT mode');
      }

      await _registerModulesAndModels();

      stopwatch.stop();
      debugPrint(
          '⚡ SDK initialization completed in ${stopwatch.elapsedMilliseconds}ms');
      debugPrint(
          '🎯 SDK Status: ${RunAnywhereSDK.instance.isActive ? "Active" : "Inactive"}');
      debugPrint(
          '🔧 Environment: ${RunAnywhereSDK.instance.environment?.description ?? "Unknown"}');

      await ModelManager.shared.refresh();

      debugPrint(
          '💡 Models registered, user can now download and select models');
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

  /// E2E auto-test: download → load → generate (non-streaming) → generateStream
  Future<void> _runE2EAutoTest() async {
    const testModelId = 'lfm2-350m-q4_k_m';
    debugPrint('');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('  E2E AUTO-TEST  (Flutter Android)');
    debugPrint('═══════════════════════════════════════════');

    try {
      // ── Step 1: Download ─────────────────────────────────────────
      debugPrint('▶ Step 1: downloading $testModelId …');
      final sw = Stopwatch()..start();
      final progressStream =
          RunAnywhereSDK.instance.downloads.start(testModelId);

      double lastPct = 0;
      await for (final p in progressStream) {
        final pct = (p.stageProgress * 100).clamp(0.0, 100.0);
        if (pct - lastPct >= 10 || pct >= 100) {
          debugPrint('   download: ${pct.toStringAsFixed(0)}%');
          lastPct = pct;
        }
        if (p.stage == DownloadStage.DOWNLOAD_STAGE_COMPLETED) break;
        if (p.stage == DownloadStage.DOWNLOAD_STAGE_UNSPECIFIED &&
            p.errorMessage.isNotEmpty) {
          throw Exception('download failed: ${p.errorMessage}');
        }
      }
      sw.stop();
      debugPrint('✅ Download done in ${sw.elapsedMilliseconds}ms');

      // Let the download adapter finalize (path update, registry sync)
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await ModelManager.shared.refresh();

      // Re-run discovery so the SDK sees the downloaded file
      final models = await RunAnywhereSDK.instance.models.available();
      final dlModel = models.where((m) => m.id == testModelId).firstOrNull;
      debugPrint('   model localPath after download: ${dlModel?.localPath}');

      // ── Step 2: Load ─────────────────────────────────────────────
      debugPrint('▶ Step 2: loading $testModelId …');
      sw
        ..reset()
        ..start();
      await RunAnywhereSDK.instance.llm.load(testModelId);
      sw.stop();
      debugPrint('✅ Model loaded in ${sw.elapsedMilliseconds}ms');

      // ── Step 3: Non-streaming generate ───────────────────────────
      debugPrint('▶ Step 3: non-streaming generate …');
      sw
        ..reset()
        ..start();
      final genOpts = LLMGenerationOptions(
        maxTokens: 64,
        temperature: 0.7,
        systemPrompt: 'You are a helpful assistant.',
      );
      final result =
          await RunAnywhereSDK.instance.llm.generate('Hello!', genOpts);
      sw.stop();
      debugPrint('✅ generate() => "${result.text.substring(0, result.text.length.clamp(0, 120))}"');
      debugPrint('   tokens=${result.tokensGenerated}  t/s=${result.tokensPerSecond.toStringAsFixed(1)}  time=${sw.elapsedMilliseconds}ms');

      // ── Step 4: Streaming generate ───────────────────────────────
      debugPrint('▶ Step 4: streaming generateStream …');
      sw
        ..reset()
        ..start();
      final streamOpts = LLMGenerationOptions(
        maxTokens: 64,
        temperature: 0.7,
        systemPrompt: 'You are a helpful assistant.',
      );
      final stream = RunAnywhereSDK.instance.llm
          .generateStream('What is 2+2?', streamOpts);
      final buf = StringBuffer();
      int tokenCount = 0;
      await for (final event in stream) {
        if (event.isFinal) {
          if (event.errorMessage.isNotEmpty) {
            throw Exception('stream error: ${event.errorMessage}');
          }
          break;
        }
        if (event.token.isNotEmpty) {
          buf.write(event.token);
          tokenCount++;
        }
      }
      sw.stop();
      debugPrint('✅ generateStream() => "$buf"');
      debugPrint('   tokens=$tokenCount  time=${sw.elapsedMilliseconds}ms');

      // ── Done ─────────────────────────────────────────────────────
      debugPrint('');
      debugPrint('═══════════════════════════════════════════');
      debugPrint('  ALL E2E TESTS PASSED  ✓');
      debugPrint('═══════════════════════════════════════════');
    } catch (e, st) {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════');
      debugPrint('  E2E TEST FAILED: $e');
      debugPrint('  $st');
      debugPrint('═══════════════════════════════════════════');
    }
  }

  /// True once we've registered modules + models exactly once. Without
  /// this guard, hot-reload (or any second call) re-runs the entire
  /// LlamaCpp.addModel block, which is wasteful (B-FL-3-002).
  static bool _modulesRegistered = false;

  /// Register modules with their associated models
  /// Each module explicitly owns its models - the framework is determined by the module
  /// Matches iOS registerModulesAndModels pattern exactly
  Future<void> _registerModulesAndModels() async {
    if (_modulesRegistered) {
      debugPrint('📦 Modules already registered — skipping (B-FL-3-002)');
      return;
    }
    debugPrint('📦 Registering modules with their models...');

    // --- LLAMACPP MODULE ---
    await LlamaCpp.register();
    await Future<void>.delayed(Duration.zero);

    LlamaCpp.addModel(
      id: 'smollm2-360m-q8_0',
      name: 'SmolLM2 360M Q8_0',
      url:
          'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
      memoryRequirement: 500000000,
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
      id: 'qwen2.5-0.5b-instruct-q6_k',
      name: 'Qwen 2.5 0.5B Instruct Q6_K',
      url:
          'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
      memoryRequirement: 600000000,
    );
    LlamaCpp.addModel(
      id: 'qwen3-0.6b-q4_k_m',
      name: 'Qwen3 0.6B Q4_K_M',
      url:
          'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
      memoryRequirement: 477000000,
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
    debugPrint('✅ LlamaCPP module registered');
    await Future<void>.delayed(Duration.zero);

    // --- GENIE NPU MODULE (Android/Snapdragon only) ---
    if (Genie.isAvailable) {
      await Genie.register(priority: 200);
      final chip = await RunAnywhereSDK.instance.hardware.getChipEnum();
      if (chip != null) {
        // Models with per-chip availability
        const genieModels = [
          // Qwen3 4B — Gen 5 only
          (slug: 'qwen3-4b', name: 'Qwen3 4B', mem: 2800000000, quant: 'w4a16', chips: {NPUChip.snapdragon8EliteGen5}),
          // Llama 3.2 1B Instruct — both chips
          (slug: 'llama3.2-1b-instruct', name: 'Llama 3.2 1B Instruct', mem: 1200000000, quant: 'w4a16', chips: {NPUChip.snapdragon8Elite, NPUChip.snapdragon8EliteGen5}),
          // SEA-LION v3.5 8B Instruct — both chips
          (slug: 'sea-lion3.5-8b-instruct', name: 'SEA-LION v3.5 8B Instruct', mem: 4800000000, quant: 'w4a16', chips: {NPUChip.snapdragon8Elite, NPUChip.snapdragon8EliteGen5}),
          // Qwen 2.5 7B Instruct — 8elite only, w8a16 quant
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
        debugPrint('✅ Genie NPU module registered (chip: ${chip.displayName})');
      } else {
        debugPrint('ℹ️ Genie available but no supported NPU chip detected');
      }
    } else {
      debugPrint('ℹ️ Genie NPU not available (non-Snapdragon device)');
    }
    await Future<void>.delayed(Duration.zero);

    // --- VLM MODULE ---
    RunAnywhereSDK.instance.models.register(
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
    debugPrint('✅ VLM models registered');
    await Future<void>.delayed(Duration.zero);

    // --- SHERPA-ONNX MODULE (STT/TTS via Core SDK) ---
    // STT Models (Sherpa-ONNX Whisper) — served by the Sherpa-ONNX engine plugin
    RunAnywhereSDK.instance.models.register(
      id: 'sherpa-onnx-whisper-tiny.en',
      name: 'Sherpa Whisper Tiny (ONNX)',
      url: Uri.parse('https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz'),
      framework: InferenceFramework.sherpa,
      modality: ModelCategory.speechRecognition,
      memoryRequirement: 75000000,
    );

    RunAnywhereSDK.instance.models.register(
      id: 'sherpa-onnx-whisper-small.en',
      name: 'Sherpa Whisper Small (ONNX)',
      url: Uri.parse('https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-small.en.tar.gz'),
      framework: InferenceFramework.sherpa,
      modality: ModelCategory.speechRecognition,
      memoryRequirement: 250000000,
    );

    // TTS Models (Piper VITS) — served by the Sherpa-ONNX engine plugin
    RunAnywhereSDK.instance.models.register(
      id: 'vits-piper-en_US-lessac-medium',
      name: 'Piper TTS (US English - Medium)',
      url: Uri.parse('https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz'),
      framework: InferenceFramework.sherpa,
      modality: ModelCategory.speechSynthesis,
      memoryRequirement: 65000000,
    );

    RunAnywhereSDK.instance.models.register(
      id: 'vits-piper-en_GB-alba-medium',
      name: 'Piper TTS (British English)',
      url: Uri.parse('https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz'),
      framework: InferenceFramework.sherpa,
      modality: ModelCategory.speechSynthesis,
      memoryRequirement: 65000000,
    );

    // System TTS pseudo-model (matches iOS / Android registration).
    // No download URL — the platform's built-in TTS engine (AVSpeechSynthesizer
    // on iOS, android.speech.tts.TextToSpeech on Android) is used at runtime.
    RunAnywhereSDK.instance.models.register(
      id: 'system-tts',
      name: 'System TTS',
      url: Uri.parse('about:blank'),
      framework: InferenceFramework.systemTTS,
      modality: ModelCategory.speechSynthesis,
      memoryRequirement: 0,
    );
    debugPrint('✅ STT/TTS models registered via Core SDK (incl. system-tts)');
    await Future<void>.delayed(Duration.zero);

    // --- RAG EMBEDDINGS ---
    RunAnywhereSDK.instance.models.registerMultiFile(
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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ModelManager.shared),
      ],
      child: MaterialApp(
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
      ),
    );
  }

  Widget _buildHome() {
    return const ContentView();
  }
}
