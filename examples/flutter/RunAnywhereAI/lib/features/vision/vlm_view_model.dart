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
  bool _isDisposed = false;

  VisionCameraSession? _cameraSession;
  Timer? _autoStreamTimer;

  void _safeNotifyListeners() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }

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
      if (_isDisposed) {
        return;
      }
      if (devices.isEmpty) {
        _hasCameraDevice = false;
        _isCameraInitialized = false;
        _error = 'No cameras available on this device.';
        _safeNotifyListeners();
        return;
      }

      _hasCameraDevice = true;
      final device = devices.firstWhere(
        (camera) => camera.lensDirection == VisionCameraLensDirection.back,
        orElse: () => devices.first,
      );

      await _cameraSession?.dispose();
      if (_isDisposed) {
        return;
      }
      final nextSession = _cameraBackend.createSession(device);
      if (_isDisposed) {
        unawaited(nextSession.dispose());
        return;
      }
      _cameraSession = nextSession;
      await nextSession.initialize();
      if (_isDisposed) {
        if (identical(_cameraSession, nextSession)) {
          _cameraSession = null;
        }
        unawaited(nextSession.dispose());
        return;
      }

      _isCameraInitialized = true;
      _error = null;
      _safeNotifyListeners();
    } catch (e) {
      if (_isDisposed) {
        return;
      }
      _isCameraInitialized = false;
      _error = 'Failed to initialize camera: $e';
      _safeNotifyListeners();
    }
  }

  Future<void> checkCameraAuthorization(BuildContext context) async {
    _isCameraAuthorized =
        await _permissionGateway.requestCameraPermission(context);
    if (_isDisposed) {
      return;
    }
    _safeNotifyListeners();
  }

  Future<void> checkModelStatus() async {
    _isModelLoaded = _vlmService.isModelLoaded;
    _loadedModelName = _isModelLoaded ? _vlmService.currentModelId : null;
    _safeNotifyListeners();
  }

  Future<void> onModelSelected(
    String modelId,
    String modelName,
    BuildContext context,
  ) async {
    try {
      await _vlmService.loadModel(modelId);
      if (_isDisposed) {
        return;
      }
      _isModelLoaded = true;
      _loadedModelName = modelName;
      _error = null;
      _safeNotifyListeners();
    } catch (e) {
      if (_isDisposed) {
        return;
      }
      _error = 'Failed to load model: $e';
      _safeNotifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load model: $e')),
        );
      }
    }
  }

  Future<void> describeCurrentFrame() async {
    if (_isDisposed || _isProcessing || !_isCameraInitialized || _cameraSession == null) {
      return;
    }

    _isProcessing = true;
    _error = null;
    _currentDescription = '';
    _safeNotifyListeners();

    try {
      final imagePath = await _cameraSession!.captureStill();
      if (_isDisposed) {
        return;
      }
      final tokens = _vlmService.processImageStream(
        imagePath,
        prompt: 'Describe what you see briefly.',
        maxTokens: 200,
      );

      final buffer = StringBuffer();
      await for (final token in tokens) {
        if (_isDisposed) {
          return;
        }
        buffer.write(token);
        _currentDescription = buffer.toString();
        _safeNotifyListeners();
      }
    } catch (e) {
      if (_isDisposed) {
        return;
      }
      _error = e.toString();
      _safeNotifyListeners();
    } finally {
      _isProcessing = false;
      _safeNotifyListeners();
    }
  }

  Future<void> describePickedImage(String imagePath) async {
    if (_isDisposed) {
      return;
    }
    _isProcessing = true;
    _error = null;
    _currentDescription = '';
    _safeNotifyListeners();

    try {
      final tokens = _vlmService.processImageStream(
        imagePath,
        prompt: 'Describe this image in detail.',
        maxTokens: 300,
      );

      final buffer = StringBuffer();
      await for (final token in tokens) {
        if (_isDisposed) {
          return;
        }
        buffer.write(token);
        _currentDescription = buffer.toString();
        _safeNotifyListeners();
      }
    } catch (e) {
      if (_isDisposed) {
        return;
      }
      _error = e.toString();
      _safeNotifyListeners();
    } finally {
      _isProcessing = false;
      _safeNotifyListeners();
    }
  }

  void toggleAutoStreaming() {
    _isAutoStreamingEnabled = !_isAutoStreamingEnabled;
    _safeNotifyListeners();

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
    _safeNotifyListeners();
  }

  Future<void> _describeCurrentFrameForAutoStream() async {
    if (_isDisposed || _isProcessing || !_isCameraInitialized || _cameraSession == null) {
      return;
    }

    _isProcessing = true;
    _safeNotifyListeners();

    try {
      final imagePath = await _cameraSession!.captureStill();
      if (_isDisposed) {
        return;
      }
      final tokens = _vlmService.processImageStream(
        imagePath,
        prompt: 'Describe what you see in one sentence.',
        maxTokens: 100,
      );

      final buffer = StringBuffer();
      await for (final token in tokens) {
        if (_isDisposed) {
          return;
        }
        buffer.write(token);
        _currentDescription = buffer.toString();
        _safeNotifyListeners();
      }
    } catch (_) {
      // Auto-stream failures stay non-blocking.
    } finally {
      _isProcessing = false;
      _safeNotifyListeners();
    }
  }

  Future<void> cancelGeneration() => _vlmService.cancelGeneration();

  void disposeCamera() {
    final session = _cameraSession;
    _cameraSession = null;
    _isCameraInitialized = false;
    _safeNotifyListeners();
    unawaited(session?.dispose());
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoStreamTimer?.cancel();
    unawaited(_vlmService.cancelGeneration());
    final session = _cameraSession;
    _cameraSession = null;
    unawaited(session?.dispose());
    super.dispose();
  }
}
