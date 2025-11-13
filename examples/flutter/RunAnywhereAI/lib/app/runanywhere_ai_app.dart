import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:runanywhere/runanywhere.dart';
import '../core/services/model_manager.dart';
import 'content_view.dart';

class RunAnywhereAIApp extends StatefulWidget {
  const RunAnywhereAIApp({super.key});

  @override
  State<RunAnywhereAIApp> createState() => _RunAnywhereAIAppState();
}

class _RunAnywhereAIAppState extends State<RunAnywhereAIApp> {
  bool _isSDKInitialized = false;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    _initializeSDK();
  }

  Future<void> _initializeSDK() async {
    try {
      // Determine environment based on build configuration
      const environment = SDKEnvironment.development; // TODO: Use kDebugMode

      // Initialize SDK
      await RunAnywhere.initialize(
        apiKey: 'dev',
        baseURL: 'http://localhost',
        environment: environment,
      );

      setState(() {
        _isSDKInitialized = true;
      });
    } catch (e) {
      setState(() {
        _initializationError = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ModelManager.shared,
      child: MaterialApp(
        title: 'RunAnywhere AI',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: _isSDKInitialized
            ? const ContentView()
            : _initializationError != null
                ? _buildErrorView()
                : _buildLoadingView(),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Initializing RunAnywhere AI...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Initialization Failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _initializationError.toString(),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeSDK,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

