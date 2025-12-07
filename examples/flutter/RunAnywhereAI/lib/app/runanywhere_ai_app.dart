import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere/backends/llamacpp/llamacpp.dart';
import 'package:runanywhere/backends/onnx/onnx.dart';

import '../core/design_system/app_colors.dart';
import '../core/design_system/app_spacing.dart';
import '../core/services/model_manager.dart';
import 'content_view.dart';

/// RunAnywhereAIApp (mirroring iOS RunAnywhereAIApp.swift)
///
/// Main application entry point with SDK initialization.
class RunAnywhereAIApp extends StatefulWidget {
  const RunAnywhereAIApp({super.key});

  @override
  State<RunAnywhereAIApp> createState() => _RunAnywhereAIAppState();
}

class _RunAnywhereAIAppState extends State<RunAnywhereAIApp> {
  bool _isSDKInitialized = false;
  Object? _initializationError;
  String _initializationStatus = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeSDK();
  }

  Future<void> _initializeSDK() async {
    final stopwatch = Stopwatch()..start();

    try {
      setState(() {
        _initializationStatus = 'Initializing SDK...';
      });

      debugPrint('🎯 Initializing SDK...');

      // Determine environment based on build configuration
      const environment =
          kDebugMode ? SDKEnvironment.development : SDKEnvironment.production;

      if (kDebugMode) {
        debugPrint('🛠️ Using DEVELOPMENT mode - No API key required!');

        // Development mode initialization
        await RunAnywhere.initialize(
          apiKey: 'dev',
          baseURL: 'http://localhost',
          environment: environment,
        );

        debugPrint('✅ SDK initialized in DEVELOPMENT mode');

        // Register adapters with models for development
        await _registerAdaptersForDevelopment();
      } else {
        debugPrint('🚀 Using PRODUCTION mode');

        // Production mode initialization
        // TODO: Load actual API key from secure storage
        await RunAnywhere.initialize(
          apiKey: 'production_key',
          baseURL: 'https://api.runanywhere.ai',
          environment: environment,
        );

        debugPrint('✅ SDK initialized in PRODUCTION mode');

        // Register adapters with models for production
        await _registerAdaptersForProduction();
      }

      stopwatch.stop();
      debugPrint(
          '⚡ SDK initialization completed in ${stopwatch.elapsedMilliseconds}ms');
      debugPrint(
          '🎯 SDK Status: ${RunAnywhere.isActive() ? "Active" : "Inactive"}');
      debugPrint(
          '🔧 Environment: ${RunAnywhere.getCurrentEnvironment()?.description ?? "Unknown"}');

      // Refresh model manager state
      await ModelManager.shared.refresh();

      setState(() {
        _isSDKInitialized = true;
      });
    } catch (e) {
      stopwatch.stop();
      debugPrint(
          '❌ SDK initialization failed after ${stopwatch.elapsedMilliseconds}ms: $e');
      setState(() {
        _initializationError = e;
      });
    }
  }

  /// Register adapters with custom models for development mode
  /// Matches iOS registerAdaptersForDevelopment pattern exactly
  Future<void> _registerAdaptersForDevelopment() async {
    debugPrint(
        '📦 Registering adapters with custom models for DEVELOPMENT mode');

    // Register LlamaCPP adapter with LLM models
    // Matches iOS registerAdaptersForDevelopment pattern
    await RunAnywhere.registerFramework(
      LlamaCppAdapter(),
      models: [
        // LLM Models (matching iOS exactly)
        ModelRegistration(
          url:
              'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'smollm2-360m-q8-0',
          name: 'SmolLM2 360M Q8_0',
          memoryRequirement: 500000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'llama2-7b-q4-k-m',
          name: 'Llama 2 7B Chat Q4_K_M',
          memoryRequirement: 4000000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'mistral-7b-q4-k-m',
          name: 'Mistral 7B Instruct Q4_K_M',
          memoryRequirement: 4000000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'qwen-2.5-0.5b-instruct-q6-k',
          name: 'Qwen 2.5 0.5B Instruct Q6_K',
          memoryRequirement: 600000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'lfm2-350m-q4-k-m',
          name: 'LiquidAI LFM2 350M Q4_K_M',
          memoryRequirement: 250000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'lfm2-350m-q8-0',
          name: 'LiquidAI LFM2 350M Q8_0',
          memoryRequirement: 400000000,
        ),
      ],
    );
    debugPrint('✅ LlamaCPP adapter registered with LLM models');

    // Register ONNX Runtime adapter with STT and TTS models
    // Matches iOS registerAdaptersForDevelopment pattern
    await RunAnywhere.registerFramework(
      OnnxAdapter(),
      models: [
        // STT Models (matching iOS exactly)
        ModelRegistration(
          url:
              'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2',
          framework: LLMFramework.onnx,
          modality: FrameworkModality.voiceToText,
          id: 'sherpa-whisper-tiny-onnx',
          name: 'Sherpa Whisper Tiny (ONNX)',
          format: ModelFormat.onnx,
          memoryRequirement: 75000000,
        ),
        ModelRegistration(
          url:
              'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2',
          framework: LLMFramework.onnx,
          modality: FrameworkModality.voiceToText,
          id: 'sherpa-whisper-small-onnx',
          name: 'Sherpa Whisper Small (ONNX)',
          format: ModelFormat.onnx,
          memoryRequirement: 250000000,
        ),
        // TTS Models (matching iOS exactly)
        ModelRegistration(
          url:
              'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2',
          framework: LLMFramework.onnx,
          modality: FrameworkModality.textToVoice,
          id: 'piper-en-us-lessac-medium',
          name: 'Piper TTS (US English - Medium)',
          format: ModelFormat.onnx,
          memoryRequirement: 65000000,
        ),
        ModelRegistration(
          url:
              'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2',
          framework: LLMFramework.onnx,
          modality: FrameworkModality.textToVoice,
          id: 'piper-en-gb-alba-medium',
          name: 'Piper TTS (British English)',
          format: ModelFormat.onnx,
          memoryRequirement: 65000000,
        ),
      ],
    );
    debugPrint('✅ ONNX Runtime adapter registered with STT and TTS models');

    debugPrint('🎉 All adapters registered for development');

    // Refresh all models to detect downloaded files from previous sessions
    await RunAnywhere.serviceContainer.modelRegistry.refreshDownloadedModels();
    debugPrint('✅ Refreshed model download status');
  }

  /// Register adapters with custom models for production mode
  /// Matches iOS registerAdaptersForProduction pattern exactly
  Future<void> _registerAdaptersForProduction() async {
    debugPrint(
        '📦 Registering adapters with custom models for PRODUCTION mode');
    debugPrint(
        '💡 Hardcoded models provide immediate user access, backend can add more dynamically');

    // Register LlamaCPP adapter with LLM models (same as development)
    await RunAnywhere.registerFramework(
      LlamaCppAdapter(),
      models: [
        ModelRegistration(
          url:
              'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'smollm2-360m-q8-0',
          name: 'SmolLM2 360M Q8_0',
          memoryRequirement: 500000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'llama2-7b-q4-k-m',
          name: 'Llama 2 7B Chat Q4_K_M',
          memoryRequirement: 4000000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'mistral-7b-q4-k-m',
          name: 'Mistral 7B Instruct Q4_K_M',
          memoryRequirement: 4000000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'qwen-2.5-0.5b-instruct-q6-k',
          name: 'Qwen 2.5 0.5B Instruct Q6_K',
          memoryRequirement: 600000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'lfm2-350m-q4-k-m',
          name: 'LiquidAI LFM2 350M Q4_K_M',
          memoryRequirement: 250000000,
        ),
        ModelRegistration(
          url:
              'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
          framework: LLMFramework.llamaCpp,
          modality: FrameworkModality.textToText,
          id: 'lfm2-350m-q8-0',
          name: 'LiquidAI LFM2 350M Q8_0',
          memoryRequirement: 400000000,
        ),
      ],
    );
    debugPrint('✅ LlamaCPP adapter registered with hardcoded LLM models');

    // Register ONNX Runtime adapter with STT and TTS models
    await RunAnywhere.registerFramework(
      OnnxAdapter(),
      models: [
        ModelRegistration(
          url:
              'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2',
          framework: LLMFramework.onnx,
          modality: FrameworkModality.voiceToText,
          id: 'sherpa-whisper-tiny-onnx',
          name: 'Sherpa Whisper Tiny (ONNX)',
          format: ModelFormat.onnx,
          memoryRequirement: 75000000,
        ),
        ModelRegistration(
          url:
              'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2',
          framework: LLMFramework.onnx,
          modality: FrameworkModality.voiceToText,
          id: 'sherpa-whisper-small-onnx',
          name: 'Sherpa Whisper Small (ONNX)',
          format: ModelFormat.onnx,
          memoryRequirement: 250000000,
        ),
        ModelRegistration(
          url:
              'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2',
          framework: LLMFramework.onnx,
          modality: FrameworkModality.textToVoice,
          id: 'piper-en-us-lessac-medium',
          name: 'Piper TTS (US English - Medium)',
          format: ModelFormat.onnx,
          memoryRequirement: 65000000,
        ),
        ModelRegistration(
          url:
              'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2',
          framework: LLMFramework.onnx,
          modality: FrameworkModality.textToVoice,
          id: 'piper-en-gb-alba-medium',
          name: 'Piper TTS (British English)',
          format: ModelFormat.onnx,
          memoryRequirement: 65000000,
        ),
      ],
    );
    debugPrint(
        '✅ ONNX Runtime adapter registered with hardcoded STT and TTS models');

    debugPrint(
        '🎉 All adapters registered for production with hardcoded models');
    debugPrint('📡 Backend can dynamically add more models via console API');

    // Refresh all models to detect downloaded files from previous sessions
    await RunAnywhere.serviceContainer.modelRegistry.refreshDownloadedModels();
    debugPrint('✅ Refreshed model download status');
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ModelManager.shared),
        // Provide ModelLifecycleTracker for UI updates
        ChangeNotifierProvider.value(value: ModelLifecycleTracker.shared),
      ],
      child: MaterialApp(
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
    if (_isSDKInitialized) {
      return const ContentView();
    } else if (_initializationError != null) {
      return _InitializationErrorView(
        error: _initializationError!,
        onRetry: _initializeSDK,
      );
    } else {
      return _InitializationLoadingView(status: _initializationStatus);
    }
  }
}

/// Loading view shown during SDK initialization
class _InitializationLoadingView extends StatefulWidget {
  final String status;

  const _InitializationLoadingView({required this.status});

  @override
  State<_InitializationLoadingView> createState() =>
      _InitializationLoadingViewState();
}

class _InitializationLoadingViewState extends State<_InitializationLoadingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated brain icon (matching iOS)
            ScaleTransition(
              scale: _scaleAnimation,
              child: const Icon(
                Icons.psychology,
                size: AppSpacing.iconHuge,
                color: AppColors.primaryPurple,
              ),
            ),
            const SizedBox(height: AppSpacing.xLarge),
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.large),
            Text(
              widget.status,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.smallMedium),
            Text(
              'RunAnywhere AI',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error view shown when SDK initialization fails
class _InitializationErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _InitializationErrorView({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: AppSpacing.iconXLarge,
                color: AppColors.primaryRed,
              ),
              const SizedBox(height: AppSpacing.large),
              Text(
                'Initialization Failed',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.smallMedium),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xLarge),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
