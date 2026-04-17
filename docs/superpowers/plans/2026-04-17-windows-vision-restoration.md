# Windows Vision Restoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the Flutter example Vision page on Windows with camera preview, single capture, live repeated capture, and gallery image analysis, while isolating Windows-specific camera integration from other platforms.

**Architecture:** Keep the shared RunAnywhere Flutter SDK untouched unless a proven Windows VLM issue appears. Add a Windows-only camera plugin dependency inside the Flutter example, wrap camera and VLM access behind small Vision-scoped services, and refactor `VLMViewModel` to depend on those services so Windows behavior is isolated and testable.

**Tech Stack:** Flutter example app, `camera`, `camera_windows`, `image_picker`, `permission_handler`, RunAnywhere Flutter VLM APIs, `flutter_test`, `fvm flutter`.

---

## File Map

- `examples/flutter/RunAnywhereAI/pubspec.yaml`
  Add the Windows-only camera plugin dependency compatible with the current FVM toolchain.
- `examples/flutter/RunAnywhereAI/lib/core/services/platform_capability_service.dart`
  Re-enable Vision on Windows while leaving other Windows capability decisions unchanged.
- `examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_camera_backend.dart`
  New thin adapter around the `camera` plugin so Windows camera integration stays local to Vision.
- `examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_permission_gateway.dart`
  New wrapper around `PermissionService` so Vision permission behavior is testable.
- `examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_vlm_service.dart`
  New wrapper around `RunAnywhere` VLM APIs so Vision inference flows are testable.
- `examples/flutter/RunAnywhereAI/lib/features/vision/vlm_view_model.dart`
  Refactor to inject the new services, surface safe Windows camera states, and keep existing UX behavior.
- `examples/flutter/RunAnywhereAI/lib/features/vision/vlm_camera_view.dart`
  Replace direct `CameraController` assumptions with the new camera session abstraction and improve Windows-safe error presentation.
- `examples/flutter/RunAnywhereAI/lib/features/vision/vision_hub_view.dart`
  Keep Vision entry enabled once Windows support is in place.
- `examples/flutter/RunAnywhereAI/test/features/vision/vlm_view_model_test.dart`
  Add unit tests for no-camera, model load, and capture/streaming flows using fake Vision services.
- `docs/building.md`
  Add a note that Windows Vision depends on `camera_windows` and is validated through the Flutter example build.

**Verification Strategy:** Use test-first refactoring around `VLMViewModel`, then run `fvm flutter test`, `fvm flutter analyze`, and `fvm flutter build windows`. Finish with manual Windows validation of preview, capture, live mode, and gallery mode.

---

### Task 1: Add Testable Vision Service Boundaries Around Camera, Permissions, and VLM

**Files:**
- Create: `examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_camera_backend.dart`
- Create: `examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_permission_gateway.dart`
- Create: `examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_vlm_service.dart`
- Create: `examples/flutter/RunAnywhereAI/test/features/vision/vlm_view_model_test.dart`
- Modify: `examples/flutter/RunAnywhereAI/lib/features/vision/vlm_view_model.dart`

- [ ] **Step 1: Write failing Vision view-model tests before refactoring**

Create `examples/flutter/RunAnywhereAI/test/features/vision/vlm_view_model_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the new test file and confirm it fails for the expected reasons**

Run:

```powershell
cd examples/flutter/RunAnywhereAI
fvm flutter test test/features/vision/vlm_view_model_test.dart
```

Expected:

- FAIL because `VisionCameraBackend`, `VisionPermissionGateway`, `VisionVlmService`, and the injected `VLMViewModel` constructor do not exist yet

- [ ] **Step 3: Add the camera backend abstraction**

Create `examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_camera_backend.dart`:

```dart
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

enum VisionCameraLensDirection { front, back, external, unknown }

class VisionCameraDevice {
  const VisionCameraDevice({
    required this.id,
    required this.name,
    required this.lensDirection,
    this.handle,
  });

  final String id;
  final String name;
  final VisionCameraLensDirection lensDirection;
  final Object? handle;
}

abstract class VisionCameraSession {
  Future<void> initialize();
  bool get isInitialized;
  Widget buildPreview();
  Future<String> captureStill();
  Future<void> dispose();
}

abstract class VisionCameraBackend {
  Future<List<VisionCameraDevice>> listDevices();
  VisionCameraSession createSession(VisionCameraDevice device);
}

class CameraPluginVisionCameraBackend implements VisionCameraBackend {
  @override
  VisionCameraSession createSession(VisionCameraDevice device) {
    final description = device.handle! as CameraDescription;
    return _CameraPluginVisionCameraSession(
      CameraController(
        description,
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      ),
    );
  }

  @override
  Future<List<VisionCameraDevice>> listDevices() async {
    final cameras = await availableCameras();
    return cameras
        .map(
          (camera) => VisionCameraDevice(
            id: camera.name,
            name: camera.name,
            lensDirection: switch (camera.lensDirection) {
              CameraLensDirection.front => VisionCameraLensDirection.front,
              CameraLensDirection.back => VisionCameraLensDirection.back,
              CameraLensDirection.external => VisionCameraLensDirection.external,
            },
            handle: camera,
          ),
        )
        .toList(growable: false);
  }
}

class _CameraPluginVisionCameraSession implements VisionCameraSession {
  _CameraPluginVisionCameraSession(this._controller);

  final CameraController _controller;

  @override
  Widget buildPreview() => CameraPreview(_controller);

  @override
  Future<String> captureStill() async => (await _controller.takePicture()).path;

  @override
  Future<void> dispose() => _controller.dispose();

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  bool get isInitialized => _controller.value.isInitialized;
}
```

- [ ] **Step 4: Add the permission gateway abstraction**

Create `examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_permission_gateway.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/services/permission_service.dart';

abstract class VisionPermissionGateway {
  Future<bool> requestCameraPermission(BuildContext context);
}

class AppVisionPermissionGateway implements VisionPermissionGateway {
  @override
  Future<bool> requestCameraPermission(BuildContext context) {
    return PermissionService.shared.requestCameraPermission(context);
  }
}
```

- [ ] **Step 5: Add the VLM service abstraction**

Create `examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_vlm_service.dart`:

```dart
import 'package:runanywhere/runanywhere.dart' as sdk;

abstract class VisionVlmService {
  bool get isModelLoaded;
  String? get currentModelId;
  Future<void> loadModel(String modelId);
  Stream<String> processImageStream(
    String imagePath, {
    required String prompt,
    required int maxTokens,
  });
  Future<void> cancelGeneration();
}

class RunAnywhereVisionVlmService implements VisionVlmService {
  @override
  Future<void> cancelGeneration() => sdk.RunAnywhere.cancelVLMGeneration();

  @override
  String? get currentModelId => sdk.RunAnywhere.currentVLMModelId;

  @override
  bool get isModelLoaded => sdk.RunAnywhere.isVLMModelLoaded;

  @override
  Future<void> loadModel(String modelId) => sdk.RunAnywhere.loadVLMModel(modelId);

  @override
  Stream<String> processImageStream(
    String imagePath, {
    required String prompt,
    required int maxTokens,
  }) async* {
    final result = await sdk.RunAnywhere.processImageStream(
      sdk.VLMImage.filePath(imagePath),
      prompt: prompt,
      options: sdk.VLMGenerationOptions(maxTokens: maxTokens),
    );
    yield* result.stream;
  }
}
```

- [ ] **Step 6: Refactor `VLMViewModel` to use injected services and the new camera session**

Replace `examples/flutter/RunAnywhereAI/lib/features/vision/vlm_view_model.dart` with:

```dart
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
```

- [ ] **Step 7: Re-run the unit tests and make sure they pass**

Run:

```powershell
cd examples/flutter/RunAnywhereAI
fvm flutter test test/features/vision/vlm_view_model_test.dart
```

Expected:

- PASS
- The three tests complete without requiring a real camera or loaded VLM model

- [ ] **Step 8: Commit the refactor and tests**

```bash
git add examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_camera_backend.dart examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_permission_gateway.dart examples/flutter/RunAnywhereAI/lib/features/vision/services/vision_vlm_service.dart examples/flutter/RunAnywhereAI/lib/features/vision/vlm_view_model.dart examples/flutter/RunAnywhereAI/test/features/vision/vlm_view_model_test.dart
git commit -m "refactor: isolate vision camera and vlm dependencies"
```

---

### Task 2: Add the Windows Camera Plugin Without Affecting Other Platforms

**Files:**
- Modify: `examples/flutter/RunAnywhereAI/pubspec.yaml`
- Modify: `examples/flutter/RunAnywhereAI/pubspec.lock`
- Modify: `examples/flutter/RunAnywhereAI/windows/flutter/generated_plugins.cmake`
- Modify: `examples/flutter/RunAnywhereAI/windows/flutter/generated_plugin_registrant.cc`
- Modify: `examples/flutter/RunAnywhereAI/windows/flutter/generated_plugin_registrant.h`

- [ ] **Step 1: Add the Windows camera plugin dependency with a Dart 3.3-compatible version**

Update the dependency block in `examples/flutter/RunAnywhereAI/pubspec.yaml`:

```yaml
  # Camera access for VLM
  camera: ^0.11.0
  # Windows implementation for camera; pin to a Dart 3.3 compatible release
  camera_windows: 0.2.6+1
  # Image picker for gallery photos
  image_picker: ^1.0.0
```

- [ ] **Step 2: Fetch dependencies and verify Windows plugin registration is generated**

Run:

```powershell
cd examples/flutter/RunAnywhereAI
fvm flutter pub get
```

Expected:

- PASS
- `pubspec.lock` updates
- `windows/flutter/generated_plugins.cmake` contains `camera_windows`

- [ ] **Step 3: Confirm the Windows generated plugin list includes the new camera plugin**

Expected excerpt in `examples/flutter/RunAnywhereAI/windows/flutter/generated_plugins.cmake`:

```cmake
list(APPEND FLUTTER_PLUGIN_LIST
  audioplayers_windows
  camera_windows
  file_selector_windows
  flutter_tts
  permission_handler_windows
  record_windows
  runanywhere
  runanywhere_llamacpp
  runanywhere_onnx
  url_launcher_windows
)
```

Also confirm the generated registrant includes:

```cpp
#include <camera_windows/camera_windows.h>
```

and:

```cpp
CameraWindowsRegisterWithRegistrar(
    registry->GetRegistrarForPlugin("CameraWindows"));
```

- [ ] **Step 4: Commit the Windows camera dependency wiring**

```bash
git add examples/flutter/RunAnywhereAI/pubspec.yaml examples/flutter/RunAnywhereAI/pubspec.lock examples/flutter/RunAnywhereAI/windows/flutter/generated_plugins.cmake examples/flutter/RunAnywhereAI/windows/flutter/generated_plugin_registrant.cc examples/flutter/RunAnywhereAI/windows/flutter/generated_plugin_registrant.h
git commit -m "feat: add Windows camera plugin for vision page"
```

---

### Task 3: Re-enable the Vision Page on Windows and Keep the UI Near-Mobile

**Files:**
- Modify: `examples/flutter/RunAnywhereAI/lib/core/services/platform_capability_service.dart`
- Modify: `examples/flutter/RunAnywhereAI/lib/features/vision/vision_hub_view.dart`
- Modify: `examples/flutter/RunAnywhereAI/lib/features/vision/vlm_camera_view.dart`
- Modify: `examples/flutter/RunAnywhereAI/test/features/vision/vlm_view_model_test.dart`

- [ ] **Step 1: Write a failing widget test for the Vision preview contract**

Append this test to `examples/flutter/RunAnywhereAI/test/features/vision/vlm_view_model_test.dart`:

```dart
testWidgets('cameraSession exposes a preview widget after initialization',
    (tester) async {
  final fakeSession = _FakeCameraSession(capturePath: 'frame.jpg');
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

  expect(viewModel.cameraSession, isNotNull);
  await tester.pumpWidget(
    MaterialApp(home: viewModel.cameraSession!.buildPreview()),
  );
  expect(find.byKey(const Key('fake-preview')), findsOneWidget);
});
```

- [ ] **Step 2: Run the updated test file and verify the new test fails if the preview contract is incomplete**

Run:

```powershell
cd examples/flutter/RunAnywhereAI
fvm flutter test test/features/vision/vlm_view_model_test.dart
```

Expected:

- FAIL if `cameraSession` is not exposed correctly or preview building still assumes `CameraController`

- [ ] **Step 3: Re-enable Vision in the platform capability service**

Update `examples/flutter/RunAnywhereAI/lib/core/services/platform_capability_service.dart`:

```dart
import 'dart:io';

class PlatformCapabilityService {
  static const PlatformCapabilityService shared = PlatformCapabilityService._();

  const PlatformCapabilityService._();

  bool get supportsChat => true;
  bool get supportsTools => true;
  bool get supportsStructuredOutput => true;

  bool get supportsVision => true;
  bool get supportsSpeechToText => true;
  bool get supportsTextToSpeech => true;
  bool get supportsVoiceAssistant => true;
  bool get supportsRag => !Platform.isWindows;

  String unsupportedMessage(String featureName) =>
      '$featureName is not enabled in the Windows vertical-slice build yet.';
}
```

- [ ] **Step 4: Update the Vision camera view to consume the abstract camera session**

In `examples/flutter/RunAnywhereAI/lib/features/vision/vlm_camera_view.dart`, replace the direct preview logic:

```dart
  Widget _buildCameraPreviewContent() {
    final session = _viewModel.cameraSession;
    if (!_viewModel.isCameraInitialized || session == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Container(
      color: Colors.black,
      child: session.buildPreview(),
    );
  }
```

Update the permission CTA so it works for both first-time permission and Windows settings fallback:

```dart
          ElevatedButton(
            onPressed: () {
              unawaited(
                _viewModel.checkCameraAuthorization(context).then((_) {
                  if (_viewModel.isCameraAuthorized) {
                    unawaited(_viewModel.initializeCamera());
                  }
                }),
              );
            },
            child: const Text('Grant Camera Access'),
          ),
```

Update the error section in the description panel so no-camera and capture errors are visible but non-fatal:

```dart
          if (_viewModel.error != null) ...[
            const SizedBox(height: AppSpacing.mediumLarge),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.smallMedium),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusRegular),
              ),
              child: Text(
                _viewModel.error!,
                style: AppTypography.caption(context).copyWith(
                  color: Colors.red,
                ),
              ),
            ),
          ],
```

- [ ] **Step 5: Keep the Vision hub behavior unchanged except that Windows now flows through**

Do not add new platform-specific branching in `examples/flutter/RunAnywhereAI/lib/features/vision/vision_hub_view.dart`.

The current unsupported branch should remain for future platforms, but after Step 3 it should no longer trigger on Windows.

- [ ] **Step 6: Re-run the Vision test file and verify the preview test now passes**

Run:

```powershell
cd examples/flutter/RunAnywhereAI
fvm flutter test test/features/vision/vlm_view_model_test.dart
```

Expected:

- PASS
- The preview contract test passes together with the earlier unit tests

- [ ] **Step 7: Commit the Vision UI enablement**

```bash
git add examples/flutter/RunAnywhereAI/lib/core/services/platform_capability_service.dart examples/flutter/RunAnywhereAI/lib/features/vision/vision_hub_view.dart examples/flutter/RunAnywhereAI/lib/features/vision/vlm_camera_view.dart examples/flutter/RunAnywhereAI/test/features/vision/vlm_view_model_test.dart
git commit -m "feat: enable Windows vision page with isolated camera session"
```

---

### Task 4: Validate Windows Build Output and Document the Vision Support Level

**Files:**
- Modify: `docs/building.md`

- [ ] **Step 1: Add a Windows Vision note to the build guide**

Append this section to `docs/building.md`:

```markdown
## Flutter Example Windows Vision

The Flutter example Vision page now supports Windows through the `camera_windows`
plugin while continuing to use the standard `camera` API in the app code.

Notes:

- The project pins `camera_windows` to a Dart 3.3-compatible version because the
  current repository workflow uses `fvm flutter` on the 3.19 line.
- Live mode still uses repeated still captures, matching the current Flutter
  Vision implementation rather than raw frame streaming.
- Mobile-specific camera controls such as torch, exposure point, and focus point
  may remain unavailable on Windows camera devices.
```

- [ ] **Step 2: Run focused Flutter analysis**

Run:

```powershell
cd examples/flutter/RunAnywhereAI
fvm flutter analyze lib/features/vision lib/core/services/platform_capability_service.dart
```

Expected:

- PASS
- No new analysis errors in Vision or capability files

- [ ] **Step 3: Run the example test suite**

Run:

```powershell
cd examples/flutter/RunAnywhereAI
fvm flutter test test/features/vision/vlm_view_model_test.dart test/widget_test.dart
```

Expected:

- PASS
- Vision unit tests and the app smoke test both pass

- [ ] **Step 4: Build the Windows example**

Run:

```powershell
cd examples/flutter/RunAnywhereAI
fvm flutter build windows
```

Expected:

- PASS
- `build/windows/x64/runner/Release/runanywhere_ai.exe` exists
- Windows plugin output includes `camera_windows` artifacts through Flutter plugin generation

- [ ] **Step 5: Perform Windows manual validation**

Manual verification checklist:

1. Launch the Windows app.
2. Open the `Vision` tab.
3. Load the `SmolVLM 500M Instruct` model.
4. Confirm camera preview is visible.
5. Tap the main action button and confirm a description is generated.
6. Pick a gallery image and confirm a description is generated.
7. Toggle `Live` and confirm repeated updates without crashing.
8. If no camera is attached, confirm the page stays open and shows a friendly error instead of crashing.

- [ ] **Step 6: Commit the documentation and final Windows Vision validation changes**

```bash
git add docs/building.md
git commit -m "docs: describe Windows vision support and validation"
```

---

## Self-Review

- Spec coverage:
  - Windows-only camera plugin choice and isolation: covered by Tasks 1 and 2.
  - Near-mobile Vision UX on Windows: covered by Task 3.
  - Explicit Windows differences and validation: covered by Task 4.
- Placeholder scan:
  - No deferred implementation markers remain in tasks.
- Type consistency:
  - `VisionCameraBackend`, `VisionCameraSession`, `VisionPermissionGateway`, and `VisionVlmService` are introduced first and reused consistently in later tasks.
