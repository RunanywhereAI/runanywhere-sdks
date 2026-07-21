import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/app/content_view.dart';
import 'package:runanywhere_ai/core/design_system/app_colors.dart';
import 'package:runanywhere_ai/core/design_system/app_spacing.dart';
import 'package:runanywhere_ai/core/services/hf_token_store.dart';
import 'package:runanywhere_ai/core/services/model_catalog_bootstrap.dart';
import 'package:runanywhere_ai/core/utilities/constants.dart';
import 'package:runanywhere_ai/core/utilities/keychain_helper.dart';
import 'package:runanywhere_ai/core/utilities/url_utils.dart';
import 'package:runanywhere_llamacpp/runanywhere_llamacpp.dart';
import 'package:runanywhere_mlx/runanywhere_mlx.dart';
import 'package:runanywhere_onnx/runanywhere_onnx.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

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
  bool _isSDKInitialized = false;
  bool _isInitializing = true;
  String? _initializationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeSDK());
    });
  }

  Future<void> _initializeSDK() async {
    final stopwatch = Stopwatch()..start();

    if (mounted) {
      setState(() {
        _isInitializing = true;
        _initializationError = null;
      });
    }

    try {
      debugPrint('🎯 Initializing SDK...');

      await _registerBackends();

      final customApiKey =
          await KeychainHelper.loadString(KeychainKeys.apiKey) ??
          DefaultConfig.runanywhereApiKey;
      final customBaseURL =
          await KeychainHelper.loadString(KeychainKeys.baseURL) ??
          DefaultConfig.runanywhereBaseUrl;
      final hasCustomConfig =
          customApiKey.isNotEmpty &&
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
          // Staging (not Production) so the custom base URL is honored AND
          // local logging stays on — Production sets enableLocalLogging:false,
          // hiding all SDK/telemetry logs. Development would ignore baseURL.
          environment: SDKEnvironment.SDK_ENVIRONMENT_STAGING,
        );
        debugPrint('✅ SDK initialized with CUSTOM configuration (staging)');
      } else {
        // Staging test build: keyless staging — no API key, no URL; the SDK
        // resolves the baked staging backend URL and sends unauthenticated
        // telemetry (PUBLIC-org ingestion). Restore `RunAnywhere.initialize()`
        // to go back to development behavior.
        await RunAnywhere.initialize(
          environment: SDKEnvironment.SDK_ENVIRONMENT_STAGING,
        );
        debugPrint('✅ SDK initialized in STAGING mode (keyless)');
      }

      // Re-apply the persisted HuggingFace token (Settings screen) so private
      // HF model repos stay downloadable across app restarts.
      final hfToken = await HfTokenStore.load();
      if (hfToken.isNotEmpty) {
        RunAnywhere.setHfToken(hfToken);
        debugPrint('🔑 Applied persisted HuggingFace token');
      }

      // Model paths + registry must be ready before catalog registration.
      await RunAnywhere.completeServicesInitialization();
      await ModelCatalogBootstrap.registerAll(mlxRegistered: _mlxRegistered);
      await _registerRagBackend();
      await RunAnywhere.refreshModelRegistry();

      stopwatch.stop();
      debugPrint(
        '⚡ SDK initialization completed in ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint(
        '🎯 SDK Status: ${RunAnywhere.isActive ? "Active" : "Inactive"}',
      );
      debugPrint(
        '🔧 Environment: ${RunAnywhere.environment?.description ?? "Unknown"}',
      );

      debugPrint(
        '💡 Models registered, user can now download and select models',
      );
      debugPrint('App is ready to use');
      debugPrint('__RUNANYWHERE_AI_READY__');
      debugPrint('Services initialized for catalog refresh');
      if (mounted) {
        setState(() {
          _isSDKInitialized = true;
          _isInitializing = false;
          _initializationError = null;
        });
      }
    } catch (e) {
      stopwatch.stop();
      debugPrint(
        '❌ SDK initialization failed after ${stopwatch.elapsedMilliseconds}ms: $e',
      );
      if (mounted) {
        setState(() {
          _isSDKInitialized = false;
          _isInitializing = false;
          _initializationError = e.toString();
        });
      }
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
    return RegExp(
      r'YOUR_|<your|REPLACE_ME|PLACEHOLDER',
      caseSensitive: false,
    ).hasMatch(value);
  }

  static bool _backendsRegistered = false;
  static bool _mlxRegistered = false;

  Future<void> _registerBackends() async {
    if (_backendsRegistered) {
      debugPrint('📦 Backends already registered — skipping');
      return;
    }

    LlamaCpp.register();

    _mlxRegistered = await MLX.register();
    debugPrint(
      _mlxRegistered
          ? '✅ Apple MLX backend registered (LLM + VLM + Embeddings + STT + TTS)'
          : 'ℹ️ Apple MLX backend unavailable on this target',
    );

    try {
      await Onnx.register();
      debugPrint('✅ ONNX backend registered (STT + TTS + VAD + Embeddings)');
    } catch (e) {
      debugPrint('⚠️ ONNX backend not available: $e');
    }

    // QHexRT (Qualcomm Hexagon NPU). Safe no-op on non-Snapdragon / non-Android;
    // register() rejects internally on unsupported parts.
    if (QHexRT.isAvailable) {
      try {
        final registered = await QHexRT.register();
        debugPrint(
          registered
              ? '✅ QHexRT NPU backend registered (LLM + VLM + STT + TTS)'
              : 'ℹ️ QHexRT NPU backend registration was rejected',
        );
      } catch (e) {
        debugPrint('⚠️ QHexRT backend not available: $e');
      }
    } else {
      debugPrint('ℹ️ QHexRT NPU not available (non-Snapdragon device)');
    }

    _backendsRegistered = true;
  }

  /// RAG backend registration stays in the app next to `_registerBackends`
  /// (it is backend wiring, not catalog seeding — mirrors iOS keeping
  /// backends out of `ModelCatalogBootstrap`).
  Future<void> _registerRagBackend() async {
    try {
      await RAGModule.register();
      debugPrint('✅ RAG backend registered');
    } catch (e) {
      debugPrint('⚠️ RAG backend not available (RAG features disabled): $e');
    }
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
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
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
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      themeMode: ThemeMode.system,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_isSDKInitialized) {
      return const ContentView();
    }
    if (_isInitializing) {
      return const _InitializationLoadingView();
    }
    return _InitializationErrorView(
      message: _initializationError ?? 'SDK initialization failed',
      onRetry: () => unawaited(_initializeSDK()),
    );
  }
}

class _InitializationLoadingView extends StatelessWidget {
  const _InitializationLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.large),
            Text('Initializing SDK...'),
          ],
        ),
      ),
    );
  }
}

class _InitializationErrorView extends StatelessWidget {
  const _InitializationErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.large),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.primaryRed,
                size: AppSpacing.iconLarge,
              ),
              const SizedBox(height: AppSpacing.large),
              Text(
                'SDK Initialization Failed',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.smallMedium),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.large),
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
