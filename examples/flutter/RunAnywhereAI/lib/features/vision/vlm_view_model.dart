import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere_ai/features/vision/services/vision_camera_backend.dart';
import 'package:runanywhere_ai/features/vision/services/vision_permission_gateway.dart';
import 'package:runanywhere_ai/features/vision/services/vision_vlm_service.dart';

class VLMViewModel extends ChangeNotifier {
  VLMViewModel({
    VisionCameraBackend? cameraBackend,
    VisionPermissionGateway? permissionGateway,
    VisionVlmService? vlmService,
    Duration autoStreamInterval = const Duration(seconds: 2, milliseconds: 500),
  })  : _cameraBackend = cameraBackend ?? CameraPluginVisionCameraBackend(),
        _permissionGateway = permissionGateway ?? AppVisionPermissionGateway(),
        _vlmService = vlmService ?? RunAnywhereVisionVlmService(),
        _autoStreamInterval = autoStreamInterval;

  final VisionCameraBackend _cameraBackend;
  final VisionPermissionGateway _permissionGateway;
  final VisionVlmService _vlmService;
  final Duration _autoStreamInterval;

  bool _isModelLoaded = false;
  String? _loadedModelName;
  bool _isProcessing = false;
  String _currentDescription = '';
  String? _error;
  bool _isCameraAuthorized = false;
  bool _isCameraInitialized = false;
  bool _isAutoStreamingEnabled = false;
  bool _hasCameraDevice = true;

  VisionCameraSession? _cameraSession;
  Timer? _autoStreamTimer;

  bool get isModelLoaded => _isModelLoaded;
  String? get loadedModelName => _loadedModelName;
  bool get isProcessing => _isProcessing;
  String get currentDescription => _currentDescription;
  String? get error => _error;
  bool get isCameraAuthorized => _isCameraAuthorized;
  bool get isCameraInitialized => _isCameraInitialized;
  bool get isAutoStreamingEnabled => _isAutoStreamingEnabled;
  bool get hasCameraDevice => _hasCameraDevice;
  VisionCameraSession? get cameraSession => _cameraSession;

  Future<void> initializeCamera() async {
    try {
      final devices = await _cameraBackend.listDevices();
      if (devices.isEmpty) {
        _hasCameraDevice = false;
        _isCameraInitialized = false;
        _error = 'No cameras available on this device.';
        notifyListeners();
        return;
      }

      _hasCameraDevice = true;
      final device = devices.firstWhere(
        (camera) => camera.lensDirection == VisionCameraLensDirection.back,
        orElse: () => devices.first,
      );

      await _cameraSession?.dispose();
      _cameraSession = _cameraBackend.createSession(device);
      await _cameraSession!.initialize();

      _isCameraInitialized = true;
      _error = null;
      notifyListeners();
    } catch (e) {
      _isCameraInitialized = false;
      _error = 'Failed to initialize camera: $e';
      notifyListeners();
    }
  }

  Future<void> checkCameraAuthorization(BuildContext context) async {
    _isCameraAuthorized =
        await _permissionGateway.requestCameraPermission(context);
    notifyListeners();
  }

  Future<void> checkModelStatus() async {
    _isModelLoaded = _vlmService.isModelLoaded;
    _loadedModelName = _isModelLoaded ? _vlmService.currentModelId : null;
    notifyListeners();
  }

  Future<void> onModelSelected(
    String modelId,
    String modelName,
    BuildContext context,
  ) async {
    try {
      await _vlmService.loadModel(modelId);
      _isModelLoaded = true;
      _loadedModelName = modelName;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load model: $e';
      notifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load model: $e')),
        );
      }
    }
  }

  Future<void> describeCurrentFrame() async {
    if (_isProcessing || !_isCameraInitialized || _cameraSession == null) {
      return;
    }

    _isProcessing = true;
    _error = null;
    _currentDescription = '';
    notifyListeners();

    try {
      final imagePath = await _cameraSession!.captureStill();
      final tokens = _vlmService.processImageStream(
        imagePath,
        prompt: 'Describe what you see briefly.',
        maxTokens: 200,
      );

      final buffer = StringBuffer();
      await for (final token in tokens) {
        buffer.write(token);
        _currentDescription = buffer.toString();
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> describePickedImage(String imagePath) async {
    _isProcessing = true;
    _error = null;
    _currentDescription = '';
    notifyListeners();

    try {
      final tokens = _vlmService.processImageStream(
        imagePath,
        prompt: 'Describe this image in detail.',
        maxTokens: 300,
      );

      final buffer = StringBuffer();
      await for (final token in tokens) {
        buffer.write(token);
        _currentDescription = buffer.toString();
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void toggleAutoStreaming() {
    _isAutoStreamingEnabled = !_isAutoStreamingEnabled;
    notifyListeners();

    if (_isAutoStreamingEnabled) {
      _autoStreamTimer?.cancel();
      _autoStreamTimer = Timer.periodic(_autoStreamInterval, (_) {
        if (!_isProcessing) {
          unawaited(_describeCurrentFrameForAutoStream());
        }
      });
    } else {
      stopAutoStreaming();
    }
  }

  void stopAutoStreaming() {
    _autoStreamTimer?.cancel();
    _autoStreamTimer = null;
    _isAutoStreamingEnabled = false;
    notifyListeners();
  }

  Future<void> _describeCurrentFrameForAutoStream() async {
    if (_isProcessing || !_isCameraInitialized || _cameraSession == null) {
      return;
    }

    _isProcessing = true;
    notifyListeners();

    try {
      final imagePath = await _cameraSession!.captureStill();
      final tokens = _vlmService.processImageStream(
        imagePath,
        prompt: 'Describe what you see in one sentence.',
        maxTokens: 100,
      );

      final buffer = StringBuffer();
      await for (final token in tokens) {
        buffer.write(token);
        _currentDescription = buffer.toString();
        notifyListeners();
      }
    } catch (_) {
      // Auto-stream failures stay non-blocking.
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<void> cancelGeneration() => _vlmService.cancelGeneration();

  Future<void> disposeCamera() async {
    await _cameraSession?.dispose();
    _cameraSession = null;
    _isCameraInitialized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _autoStreamTimer?.cancel();
    unawaited(_cameraSession?.dispose());
    super.dispose();
  }
}
