import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere_ai/features/vision/services/vision_camera_backend.dart';
import 'package:runanywhere_ai/features/vision/services/vision_permission_gateway.dart';
import 'package:runanywhere_ai/features/vision/services/vision_vlm_service.dart';
import 'package:runanywhere_ai/features/vision/vlm_view_model.dart';

class _FakePermissionGateway implements VisionPermissionGateway {
  _FakePermissionGateway(this.result);

  final bool result;

  @override
  Future<bool> requestCameraPermission(BuildContext context) async => result;
}

class _FakeCameraSession implements VisionCameraSession {
  _FakeCameraSession({
    required this.capturePath,
    this.preview = const SizedBox(key: Key('fake-preview')),
  });

  final String capturePath;
  final Widget preview;
  bool initialized = false;
  bool disposed = false;

  @override
  Widget buildPreview() => preview;

  @override
  Future<String> captureStill() async => capturePath;

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  bool get isInitialized => initialized;
}

class _FakeCameraBackend implements VisionCameraBackend {
  _FakeCameraBackend({
    required this.devices,
    this.session,
  });

  final List<VisionCameraDevice> devices;
  final VisionCameraSession? session;

  @override
  VisionCameraSession createSession(VisionCameraDevice device) {
    return session ?? _FakeCameraSession(capturePath: 'unused.jpg');
  }

  @override
  Future<List<VisionCameraDevice>> listDevices() async => devices;
}

class _FakeVlmService implements VisionVlmService {
  bool loaded = false;
  String? loadedModelId;
  final List<String> processedPaths = [];
  final List<String> prompts = [];
  Stream<String> nextStream = const Stream<String>.empty();

  @override
  Future<void> cancelGeneration() async {}

  @override
  Future<void> loadModel(String modelId) async {
    loaded = true;
    loadedModelId = modelId;
  }

  @override
  Stream<String> processImageStream(
    String imagePath, {
    required String prompt,
    required int maxTokens,
  }) {
    processedPaths.add(imagePath);
    prompts.add(prompt);
    return nextStream;
  }

  @override
  String? get currentModelId => loadedModelId;

  @override
  bool get isModelLoaded => loaded;
}

void main() {
  testWidgets('initializeCamera reports friendly error when no devices are available',
      (tester) async {
    final viewModel = VLMViewModel(
      cameraBackend: _FakeCameraBackend(devices: const []),
      permissionGateway: _FakePermissionGateway(true),
      vlmService: _FakeVlmService(),
    );

    await viewModel.initializeCamera();

    expect(viewModel.isCameraInitialized, isFalse);
    expect(viewModel.error, 'No cameras available on this device.');
  });

  testWidgets('onModelSelected updates loaded state through the injected VLM service',
      (tester) async {
    final fakeVlm = _FakeVlmService();
    final viewModel = VLMViewModel(
      cameraBackend: _FakeCameraBackend(devices: const []),
      permissionGateway: _FakePermissionGateway(true),
      vlmService: fakeVlm,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            unawaited(viewModel.onModelSelected('smolvlm', 'SmolVLM', context));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();

    expect(viewModel.isModelLoaded, isTrue);
    expect(viewModel.loadedModelName, 'SmolVLM');
    expect(fakeVlm.loadedModelId, 'smolvlm');
  });

  testWidgets('describeCurrentFrame captures and streams description tokens',
      (tester) async {
    final fakeSession = _FakeCameraSession(capturePath: 'frame.jpg');
    final fakeVlm = _FakeVlmService()
      ..loaded = true
      ..loadedModelId = 'smolvlm'
      ..nextStream = Stream<String>.fromIterable(['hello ', 'windows']);
    final backend = _FakeCameraBackend(
      devices: const [
        VisionCameraDevice(
          id: 'rear',
          name: 'Rear Camera',
          lensDirection: VisionCameraLensDirection.back,
        ),
      ],
      session: fakeSession,
    );
    final viewModel = VLMViewModel(
      cameraBackend: backend,
      permissionGateway: _FakePermissionGateway(true),
      vlmService: fakeVlm,
    );

    await viewModel.initializeCamera();
    await viewModel.describeCurrentFrame();

    expect(fakeVlm.processedPaths, ['frame.jpg']);
    expect(viewModel.currentDescription, 'hello windows');
    expect(viewModel.isProcessing, isFalse);
  });
}
