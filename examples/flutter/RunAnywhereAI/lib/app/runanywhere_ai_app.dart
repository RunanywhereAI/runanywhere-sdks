import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:runanywhere/runanywhere.dart';

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

      // Determine environment based on build configuration
      const environment =
          kDebugMode ? SDKEnvironment.development : SDKEnvironment.production;

      if (kDebugMode) {
        // Development mode initialization
        await RunAnywhere.initialize(
          apiKey: 'dev',
          baseURL: 'http://localhost',
          environment: environment,
        );

        // TODO: Register adapters for development
        // This would be done via the SDK's adapter registration system
        debugPrint('RunAnywhere SDK initialized in development mode');
      } else {
        // Production mode initialization
        // TODO: Load actual API key from secure storage
        await RunAnywhere.initialize(
          apiKey: 'production_key',
          baseURL: 'https://api.runanywhere.ai',
          environment: environment,
        );
        debugPrint('RunAnywhere SDK initialized in production mode');
      }

      stopwatch.stop();
      debugPrint(
          'SDK initialization completed in ${stopwatch.elapsedMilliseconds}ms');

      // Refresh model manager state
      await ModelManager.shared.refresh();

      setState(() {
        _isSDKInitialized = true;
      });
    } catch (e) {
      stopwatch.stop();
      debugPrint('SDK initialization failed after ${stopwatch.elapsedMilliseconds}ms: $e');
      setState(() {
        _initializationError = e;
      });
    }
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

class _InitializationLoadingViewState
    extends State<_InitializationLoadingView>
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
