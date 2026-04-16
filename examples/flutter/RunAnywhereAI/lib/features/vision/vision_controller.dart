import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/public/types/vlm_types.dart';
import 'package:runanywhere_ai/features/vision/vision_state.dart';

final cameraControllerProvider =
    StateProvider<CameraController?>((ref) => null);

final visionControllerProvider =
    NotifierProvider<VisionController, VisionState>(VisionController.new);

class VisionController extends Notifier<VisionState> {
  Timer? _streamTimer;

  @override
  VisionState build() {
    ref.onDispose(_cleanup);
    Future.microtask(_syncModelState);
    return const VisionState();
  }

  void _syncModelState() {
    final loaded = sdk.RunAnywhere.isVLMModelLoaded;
    state = state.copyWith(isModelLoaded: loaded);
  }

  void refreshModelState() => _syncModelState();

  Future<void> initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(back, ResolutionPreset.medium);
    await controller.initialize();
    ref.read(cameraControllerProvider.notifier).state = controller;
    state = state.copyWith(isCameraReady: true);
  }

  Future<void> captureAndDescribe() async {
    final cam = ref.read(cameraControllerProvider);
    if (cam == null || !cam.value.isInitialized || state.isProcessing) return;

    state = state.copyWith(
      mode: VisionMode.processing,
      description: '',
      clearError: true,
    );

    try {
      final file = await cam.takePicture();
      await _processImage(file.path, 'Describe this image in detail.');
    } on Exception catch (e) {
      state = state.copyWith(
        mode: VisionMode.idle,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> pickFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    state = state.copyWith(
      mode: VisionMode.processing,
      description: '',
      clearError: true,
    );

    try {
      await _processImage(picked.path, 'Describe this image in detail.');
    } on Exception catch (e) {
      state = state.copyWith(
        mode: VisionMode.idle,
        errorMessage: e.toString(),
      );
    }
  }

  void toggleAutoStreaming() {
    if (state.isAutoStreaming) {
      _stopAutoStreaming();
    } else {
      _startAutoStreaming();
    }
  }

  void _startAutoStreaming() {
    state = state.copyWith(isAutoStreaming: true);
    _streamTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      captureAndDescribe();
    });
  }

  void _stopAutoStreaming() {
    _streamTimer?.cancel();
    _streamTimer = null;
    state = state.copyWith(isAutoStreaming: false, mode: VisionMode.idle);
  }

  Future<void> _processImage(String path, String prompt) async {
    state = state.copyWith(mode: VisionMode.streaming);

    final buffer = StringBuffer();
    final streamResult = await sdk.RunAnywhere.processImageStream(
      VLMImage.filePath(path),
      prompt: prompt,
    );

    await for (final token in streamResult.stream) {
      buffer.write(token);
      state = state.copyWith(description: buffer.toString());
    }

    if (!File(path).path.contains('image_picker')) {
      File(path).deleteSync();
    }

    state = state.copyWith(mode: VisionMode.idle);
  }

  void _cleanup() {
    _streamTimer?.cancel();
    ref.read(cameraControllerProvider)?.dispose();
  }
}
