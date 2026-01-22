import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/app/content_view.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/services/model_manager.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
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
  bool _isSDKInitialized = false;
  Object? _initializationError;
  String _initializationStatus = 'Initializing...';

  @override
  void initState() {
    super.initState();
    // Defer SDK initialization until after the first frame renders
    // This prevents blocking the main thread during app startup
    // and allows the loading screen to display smoothly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeSDK());
    });
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
      setState(() {
        _initializationStatus = 'Initializing SDK...';
      });

      debugPrint('🎯 Initializing SDK...');

      // Yield to allow UI to render before heavy work
      await Future<void>.delayed(Duration.zero);

      // Check for custom API configuration (stored via Settings screen)
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

        // Custom configuration mode - use stored API key and base URL
        await RunAnywhere.initialize(
          apiKey: customApiKey,
          baseURL: normalizedURL,
          environment: SDKEnvironment.production,
        );
        debugPrint('✅ SDK initialized with CUSTOM configuration (production)');
      } else {
        // Initialize SDK in development mode (default)
        await RunAnywhere.initialize();
        debugPrint('✅ SDK initialized in DEVELOPMENT mode');
      }

      // Yield to allow UI to update between heavy operations
      await Future<void>.delayed(Duration.zero);

      setState(() {
        _initializationStatus = 'Registering modules...';
      });

      // Register modules and models (matching iOS pattern)
      await _registerModulesAndModels();

      // Yield before model discovery
      await Future<void>.delayed(Duration.zero);

      setState(() {
        _initializationStatus = 'Discovering models...';
      });

      stopwatch.stop();
      debugPrint(
          '⚡ SDK initialization completed in ${stopwatch.elapsedMilliseconds}ms');
      debugPrint(
          '🎯 SDK Status: ${RunAnywhere.isActive ? "Active" : "Inactive"}');
      debugPrint(
          '🔧 Environment: ${RunAnywhere.getCurrentEnvironment()?.description ?? "Unknown"}');
      debugPrint('📱 Services will initialize on first API call');

      // Refresh model manager state (runs model discovery)
      await ModelManager.shared.refresh();

      setState(() {
        _isSDKInitialized = true;
      });

      debugPrint(
          '💡 Models registered, user can now download and select models');
    } catch (e) {
      stopwatch.stop();
      debugPrint(
          '❌ SDK initialization failed after ${stopwatch.elapsedMilliseconds}ms: $e');
      setState(() {
        _initializationError = e;
      });
    }
  }

  /// Register modules with their associated models
  /// Each module explicitly owns its models - the framework is determined by the module
  /// Matches iOS registerModulesAndModels pattern exactly
  Future<void> _registerModulesAndModels() async {
    debugPrint('📦 Registering modules with their models...');

    // LlamaCPP module with LLM models
    // Using explicit IDs ensures models are recognized after download across app restarts
    await LlamaCpp.register();

    // Yield after heavy backend registration
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
    debugPrint('✅ LlamaCPP module registered with LLM models');

    // Yield between module registrations
    await Future<void>.delayed(Duration.zero);

    // ONNX module with STT and TTS models
    // Using tar.gz format hosted on RunanywhereAI/sherpa-onnx for fast native extraction
    // Using explicit IDs ensures models are recognized after download across app restarts
    await Onnx.register();

    // Yield after heavy backend registration
    await Future<void>.delayed(Duration.zero);

    // STT Models (Sherpa-ONNX Whisper)
    Onnx.addModel(
      id: 'sherpa-onnx-whisper-tiny.en',
      name: 'Sherpa Whisper Tiny (ONNX)',
      url:
          'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
      modality: ModelCategory.speechRecognition,
      memoryRequirement: 75000000,
    );
    Onnx.addModel(
      id: 'sherpa-onnx-whisper-small.en',
      name: 'Sherpa Whisper Small (ONNX)',
      url:
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2',
      modality: ModelCategory.speechRecognition,
      memoryRequirement: 250000000,
    );

    // TTS Models (Piper VITS)
    Onnx.addModel(
      id: 'vits-piper-en_US-lessac-medium',
      name: 'Piper TTS (US English - Medium)',
      url:
          'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
      modality: ModelCategory.speechSynthesis,
      memoryRequirement: 65000000,
    );
    Onnx.addModel(
      id: 'vits-piper-en_GB-alba-medium',
      name: 'Piper TTS (British English)',
      url:
          'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
      modality: ModelCategory.speechSynthesis,
      memoryRequirement: 65000000,
    );
    debugPrint('✅ ONNX module registered with STT/TTS models');

    debugPrint('🎉 All modules and models registered');
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: ModelManager.shared),
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
        onRetry: () => unawaited(_initializeSDK()),
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
    );
    unawaited(_controller.repeat(reverse: true));

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
