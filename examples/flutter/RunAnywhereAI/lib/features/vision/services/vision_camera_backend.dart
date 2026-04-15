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
