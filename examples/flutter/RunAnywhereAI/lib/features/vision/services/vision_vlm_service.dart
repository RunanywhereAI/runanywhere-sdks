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
