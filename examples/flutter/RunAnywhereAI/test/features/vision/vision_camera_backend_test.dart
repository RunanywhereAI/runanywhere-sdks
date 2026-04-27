import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere_ai/features/vision/services/vision_camera_backend.dart';

void main() {
  test('createSession throws a clear error when the device handle is invalid',
      () {
    final backend = CameraPluginVisionCameraBackend();
    const device = VisionCameraDevice(
      id: 'fake-camera',
      name: 'Fake Camera',
      lensDirection: VisionCameraLensDirection.back,
      handle: 'not-a-camera-description',
    );

    expect(
      () => backend.createSession(device),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('CameraDescription'),
        ),
      ),
    );
  });
}
