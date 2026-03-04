import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/core/services/permission_service.dart';

/// VLMViewModel - State management for VLM camera view
///
/// Mirrors iOS VLMViewModel.swift exactly:
/// - Camera management (authorization, initialization, disposal)
/// - Model status tracking (loaded state, model name)
/// - Single capture mode (camera frame → description)
/// - Gallery photo mode (picked image → detailed description)
/// - Auto-streaming mode (live 2.5s interval captures)
/// - Token-by-token streaming display
/// - Error handling and cancellation
class VLMViewModel extends ChangeNotifier {
  // MARK: - State Properties

  bool _isModelLoaded = false;
  String? _loadedModelName;
  bool _isProcessing = false;
  String _currentDescription = '';
  String? _error;
  bool _isCameraAuthorized = false;
  bool _isCameraInitialized = false;
  bool _isAutoStreamingEnabled = false;

  // Getters
  bool get isModelLoaded => _isModelLoaded;
  String? get loadedModelName => _loadedModelName;
  bool get isProcessing => _isProcessing;
  String get currentDescription => _currentDescription;
  String? get error => _error;
  bool get isCameraAuthorized => _isCameraAuthorized;
  bool get isCameraInitialized => _isCameraInitialized;
  bool get isAutoStreamingEnabled => _isAutoStreamingEnabled;

  // MARK: - Camera Management

  CameraController? _cameraController;
  CameraController? get cameraController => _cameraController;

  Timer? _autoStreamTimer;
  static const autoStreamInterval = Duration(seconds: 2, milliseconds: 500);

  // MARK: - Camera Initialization

  /// Initialize camera with back camera (or first available)
  /// Request BGRA format (preferred for iOS, Android may fallback to YUV)
  Future<void> initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('❌ No cameras available');
        return;
      }

      // Select back camera (or first available)
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Create controller with BGRA format request (iOS preferred, Android fallback to YUV)
      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      _isCameraInitialized = true;
      notifyListeners();

      debugPrint('✅ Camera initialized: ${camera.lensDirection}');
    } catch (e) {
      debugPrint('❌ Camera initialization failed: $e');
      _error = 'Failed to initialize camera: $e';
      notifyListeners();
    }
  }

  /// Dispose camera controller
  void disposeCamera() {
    unawaited(_cameraController?.dispose());
    _cameraController = null;
    _isCameraInitialized = false;
    notifyListeners();
  }

  /// Check and request camera permission
  Future<void> checkCameraAuthorization(BuildContext context) async {
    _isCameraAuthorized =
        await PermissionService.shared.requestCameraPermission(context);
    notifyListeners();
  }

  // MARK: - Model Management

  /// Check if VLM model is loaded
  Future<void> checkModelStatus() async {
    _isModelLoaded = sdk.RunAnywhere.isVLMModelLoaded;
    if (_isModelLoaded) {
      _loadedModelName = sdk.RunAnywhere.currentVLMModelId;
    } else {
      _loadedModelName = null;
    }
    notifyListeners();
  }

  /// Handle model selection from sheet
  /// Takes the app's ModelInfo and loads the SDK model by ID
  Future<void> onModelSelected(
      String modelId, String modelName, BuildContext context) async {
    try {
      debugPrint('🎯 Loading VLM model: $modelId');
      await sdk.RunAnywhere.loadVLMModel(modelId);
      _isModelLoaded = true;
      _loadedModelName = modelName;
      notifyListeners();
      debugPrint('✅ VLM model loaded: $modelName');
    } catch (e) {
      debugPrint('❌ Failed to load VLM model: $e');
      _error = 'Failed to load model: $e';
      notifyListeners();
      if (context.mounted) {
        unawaited(
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load model: $e')),
          ).closed.then((_) => null),
        );
      }
    }
  }

  // MARK: - Image Processing - Single Capture

  /// Describe the current camera frame (single capture mode)
  /// Matches iOS describeCurrentFrame()
  Future<void> describeCurrentFrame() async {
    if (_isProcessing || !_isCameraInitialized || _cameraController == null) {
      return;
    }

    _isProcessing = true;
    _error = null;
    _currentDescription = '';
    notifyListeners();

    try {
      // Capture image from camera
      final xFile = await _cameraController!.takePicture();

      // Create VLMImage from file path
      final image = sdk.VLMImage.filePath(xFile.path);

      // Process image with streaming
      final result = await sdk.RunAnywhere.processImageStream(
        image,
        prompt: 'Describe what you see briefly.',
        maxTokens: 200,
      );

      // Listen to stream and append tokens
      final buffer = StringBuffer(_currentDescription);
      await for (final token in result.stream) {
        buffer.write(token);
        _currentDescription = buffer.toString();
        notifyListeners();
      }

      debugPrint('✅ Single capture complete: ${_currentDescription.length} chars');
    } catch (e) {
      debugPrint('❌ Single capture error: $e');
      _error = e.toString();
      notifyListeners();
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  // MARK: - Image Processing - Gallery Photo

  /// Describe a picked image from gallery
  /// Matches iOS describeImage(_:)
  Future<void> describePickedImage(String imagePath) async {
    _isProcessing = true;
    _error = null;
    _currentDescription = '';
    notifyListeners();

    try {
      // Create VLMImage from file path
      final image = sdk.VLMImage.filePath(imagePath);

      // Process image with streaming (more detailed prompt)
      final result = await sdk.RunAnywhere.processImageStream(
        image,
        prompt: 'Describe this image in detail.',
        maxTokens: 300,
      );

      // Listen to stream and append tokens
      final buffer = StringBuffer(_currentDescription);
      await for (final token in result.stream) {
        buffer.write(token);
        _currentDescription = buffer.toString();
        notifyListeners();
      }

      debugPrint('✅ Gallery photo described: ${_currentDescription.length} chars');
    } catch (e) {
      debugPrint('❌ Gallery photo error: $e');
      _error = e.toString();
      notifyListeners();
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  // MARK: - Auto-Streaming (Live Mode)

  /// Toggle auto-streaming mode
  /// Matches iOS toggleAutoStreaming()
  void toggleAutoStreaming() {
    _isAutoStreamingEnabled = !_isAutoStreamingEnabled;
    notifyListeners();

    if (_isAutoStreamingEnabled) {
      _startAutoStreaming();
    } else {
      stopAutoStreaming();
    }
  }

  /// Start auto-streaming with periodic timer
  void _startAutoStreaming() {
    _autoStreamTimer?.cancel();
    _autoStreamTimer = Timer.periodic(autoStreamInterval, (timer) {
      if (!_isProcessing) {
        unawaited(_describeCurrentFrameForAutoStream());
      }
    });
    debugPrint('🔴 Auto-streaming started (${autoStreamInterval.inMilliseconds}ms interval)');
  }

  /// Stop auto-streaming
  void stopAutoStreaming() {
    _autoStreamTimer?.cancel();
    _autoStreamTimer = null;
    _isAutoStreamingEnabled = false;
    notifyListeners();
    debugPrint('⏹️ Auto-streaming stopped');
  }

  /// Describe current frame for auto-stream (live mode)
  /// Matches iOS describeCurrentFrameForAutoStream()
  /// - Shorter prompt for quick responses
  /// - Don't clear description (smooth transition)
  /// - Errors only logged, not shown to user
  Future<void> _describeCurrentFrameForAutoStream() async {
    if (_isProcessing || !_isCameraInitialized || _cameraController == null) {
      return;
    }

    _isProcessing = true;
    notifyListeners();

    // Build new description in local var (per iOS pattern)
    String newDescription = '';

    try {
      // Capture image from camera
      final xFile = await _cameraController!.takePicture();

      // Create VLMImage from file path
      final image = sdk.VLMImage.filePath(xFile.path);

      // Process image with streaming (shorter prompt for live mode)
      final result = await sdk.RunAnywhere.processImageStream(
        image,
        prompt: 'Describe what you see in one sentence.',
        maxTokens: 100,
      );

      // Listen to stream and build description
      final buffer = StringBuffer(newDescription);
      await for (final token in result.stream) {
        buffer.write(token);
        newDescription = buffer.toString();
        _currentDescription = newDescription;
        notifyListeners();
      }

      debugPrint('🔴 Auto-stream capture complete: ${newDescription.length} chars');
    } catch (e) {
      // Only log errors in auto-stream mode (per iOS pattern)
      debugPrint('⚠️ Auto-stream error (non-critical): $e');
      // Don't set _error in auto-stream mode
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  // MARK: - Cancellation

  /// Cancel ongoing VLM generation
  Future<void> cancelGeneration() async {
    unawaited(sdk.RunAnywhere.cancelVLMGeneration());
    debugPrint('🛑 VLM generation cancelled');
  }

  // MARK: - Cleanup

  @override
  void dispose() {
    _autoStreamTimer?.cancel();
    unawaited(_cameraController?.dispose());
    super.dispose();
  }
}
