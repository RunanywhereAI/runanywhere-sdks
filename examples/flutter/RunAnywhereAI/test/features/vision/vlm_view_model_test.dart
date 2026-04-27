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
    this.disposeCompleter,
    this.captureCompleter,
    this.initializeCompleter,
    this.initializeError,
  });

  final String capturePath;
  final Widget preview;
  final Completer<void>? disposeCompleter;
  final Completer<void>? captureCompleter;
  final Completer<void>? initializeCompleter;
  final Object? initializeError;
  bool initialized = false;
  bool disposed = false;
  int disposeCount = 0;

  @override
  Widget buildPreview() => preview;

  @override
  Future<String> captureStill() async {
    if (captureCompleter != null) {
      await captureCompleter!.future;
    }
    return capturePath;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    if (disposeCompleter != null) {
      await disposeCompleter!.future;
    }
    disposed = true;
  }

  @override
  Future<void> initialize() async {
    if (initializeCompleter != null) {
      await initializeCompleter!.future;
    }
    if (initializeError != null) {
      throw initializeError!;
    }
    initialized = true;
  }

  @override
  bool get isInitialized => initialized;
}

class _FakeCameraBackend implements VisionCameraBackend {
  _FakeCameraBackend({
    required this.devices,
    this.session,
    this.sessionFactory,
  });

  final List<VisionCameraDevice> devices;
  final VisionCameraSession? session;
  final VisionCameraSession Function()? sessionFactory;
  int createSessionCount = 0;

  @override
  VisionCameraSession createSession(VisionCameraDevice device) {
    createSessionCount += 1;
    return sessionFactory?.call() ??
        session ??
        _FakeCameraSession(capturePath: 'unused.jpg');
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

class _DelayedListCameraBackend implements VisionCameraBackend {
  _DelayedListCameraBackend({
    required this.devices,
    required this.listCompleter,
    required this.sessionFactory,
  });

  final List<VisionCameraDevice> devices;
  final Completer<void> listCompleter;
  final VisionCameraSession Function() sessionFactory;
  int createSessionCount = 0;

  @override
  VisionCameraSession createSession(VisionCameraDevice device) {
    createSessionCount += 1;
    return sessionFactory();
  }

  @override
  Future<List<VisionCameraDevice>> listDevices() async {
    await listCompleter.future;
    return devices;
  }
}

void main() {
  testWidgets(
      'initializeCamera reports friendly error when no devices are available',
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

  testWidgets(
      'onModelSelected updates loaded state through the injected VLM service',
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

  testWidgets('initializeCamera exposes cameraSession preview contract',
      (tester) async {
    const previewKey = Key('preview-contract');
    final fakeSession = _FakeCameraSession(
      capturePath: 'frame.jpg',
      preview: const SizedBox(key: previewKey),
    );
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
      vlmService: _FakeVlmService(),
    );

    await viewModel.initializeCamera();
    final preview = viewModel.cameraSession!.buildPreview() as SizedBox;

    expect(viewModel.cameraSession, same(fakeSession));
    expect(preview.key, previewKey);
  });

  testWidgets('disposeCamera race does not double-dispose camera session',
      (tester) async {
    final disposeCompleter = Completer<void>();
    final fakeSession = _FakeCameraSession(
      capturePath: 'frame.jpg',
      disposeCompleter: disposeCompleter,
    );
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
      vlmService: _FakeVlmService(),
    );

    await viewModel.initializeCamera();

    viewModel.disposeCamera();
    viewModel.dispose();
    disposeCompleter.complete();
    await tester.pump();

    expect(fakeSession.disposeCount, 1);
  });

  testWidgets('describeCurrentFrame ignores async completion after dispose',
      (tester) async {
    final captureCompleter = Completer<void>();
    final tokenCompleter = Completer<void>();
    final fakeSession = _FakeCameraSession(
      capturePath: 'frame.jpg',
      captureCompleter: captureCompleter,
    );
    final fakeVlm = _FakeVlmService()
      ..nextStream = (() async* {
        await tokenCompleter.future;
        yield 'late';
      })();
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
    final inFlight = viewModel.describeCurrentFrame();
    viewModel.dispose();
    captureCompleter.complete();
    tokenCompleter.complete();

    await expectLater(inFlight, completes);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'initializeCamera dispose race does not create or initialize session after dispose',
      (tester) async {
    final listCompleter = Completer<void>();
    final session = _FakeCameraSession(capturePath: 'frame.jpg');
    final backend = _DelayedListCameraBackend(
      listCompleter: listCompleter,
      devices: const [
        VisionCameraDevice(
          id: 'rear',
          name: 'Rear Camera',
          lensDirection: VisionCameraLensDirection.back,
        ),
      ],
      sessionFactory: () => session,
    );
    final viewModel = VLMViewModel(
      cameraBackend: backend,
      permissionGateway: _FakePermissionGateway(true),
      vlmService: _FakeVlmService(),
    );

    final inFlight = viewModel.initializeCamera();
    viewModel.dispose();
    listCompleter.complete();
    await expectLater(inFlight, completes);

    expect(backend.createSessionCount, 0);
    expect(session.initialized, isFalse);
  });

  testWidgets(
      'describeCurrentFrame dispose during capture does not start processImageStream',
      (tester) async {
    final captureCompleter = Completer<void>();
    final fakeSession = _FakeCameraSession(
      capturePath: 'frame.jpg',
      captureCompleter: captureCompleter,
    );
    final fakeVlm = _FakeVlmService();
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
    final inFlight = viewModel.describeCurrentFrame();
    viewModel.dispose();
    captureCompleter.complete();
    await expectLater(inFlight, completes);

    expect(fakeVlm.processedPaths, isEmpty);
  });

  testWidgets('initializeCamera disposes failed session and does not retain it',
      (tester) async {
    final fakeSession = _FakeCameraSession(
      capturePath: 'frame.jpg',
      initializeError: StateError('init failed'),
    );
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
      vlmService: _FakeVlmService(),
    );

    await viewModel.initializeCamera();

    expect(fakeSession.disposeCount, 1);
    expect(viewModel.cameraSession, isNull);
    expect(viewModel.isCameraInitialized, isFalse);
    expect(viewModel.error, contains('init failed'));
  });

  testWidgets('initializeCamera reuses the in-flight initialization work',
      (tester) async {
    final initializeCompleter = Completer<void>();
    final sessions = <_FakeCameraSession>[];
    final backend = _FakeCameraBackend(
      devices: const [
        VisionCameraDevice(
          id: 'rear',
          name: 'Rear Camera',
          lensDirection: VisionCameraLensDirection.back,
        ),
      ],
      sessionFactory: () {
        final session = _FakeCameraSession(
          capturePath: 'frame.jpg',
          initializeCompleter: initializeCompleter,
        );
        sessions.add(session);
        return session;
      },
    );
    final viewModel = VLMViewModel(
      cameraBackend: backend,
      permissionGateway: _FakePermissionGateway(true),
      vlmService: _FakeVlmService(),
    );

    final first = viewModel.initializeCamera();
    final second = viewModel.initializeCamera();
    await tester.pump();

    expect(backend.createSessionCount, 1);
    expect(sessions, hasLength(1));

    initializeCompleter.complete();
    await Future.wait([first, second]);

    expect(viewModel.cameraSession, same(sessions.single));
    expect(viewModel.isCameraInitialized, isTrue);
  });

  testWidgets('auto-stream failure surfaces error and exits live mode',
      (tester) async {
    final fakeSession = _FakeCameraSession(capturePath: 'frame.jpg');
    final fakeVlm = _FakeVlmService()
      ..nextStream = Stream<String>.error(StateError('auto-stream failed'));
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
      autoStreamInterval: const Duration(milliseconds: 1),
    );

    await viewModel.initializeCamera();
    viewModel.toggleAutoStreaming();

    await tester.pump(const Duration(milliseconds: 5));
    await tester.pump();

    expect(viewModel.isAutoStreamingEnabled, isFalse);
    expect(viewModel.isProcessing, isFalse);
    expect(viewModel.error, contains('auto-stream failed'));
  });
}
