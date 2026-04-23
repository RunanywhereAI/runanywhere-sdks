// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_vlm.dart — v4.0 VLM capability instance API.

// ignore_for_file: deprecated_member_use_from_same_package
import 'package:runanywhere/public/runanywhere.dart' as legacy;
import 'package:runanywhere/public/types/types.dart';

/// VLM (vision-language model) capability surface.
///
/// Access via `RunAnywhere.instance.vlm`.
class RunAnywhereVLM {
  RunAnywhereVLM._();
  static final RunAnywhereVLM _instance = RunAnywhereVLM._();
  static RunAnywhereVLM get shared => _instance;

  /// True when a VLM model is currently loaded.
  bool get isLoaded => legacy.RunAnywhere.isVLMModelLoaded;

  /// Currently-loaded VLM model ID, or null.
  String? get currentModelId => legacy.RunAnywhere.currentVLMModelId;

  /// Load a VLM model by ID (resolves model + mmproj from registry).
  Future<void> load(String modelId) =>
      legacy.RunAnywhere.loadVLMModel(modelId);

  /// Load a VLM model via C++ path resolution (advanced).
  Future<void> loadById(String modelId) =>
      legacy.RunAnywhere.loadVLMModelById(modelId);

  /// Load a VLM model from explicit file paths.
  Future<void> loadWithPath(
    String modelPath, {
    String? mmprojPath,
    required String modelId,
    required String modelName,
  }) =>
      legacy.RunAnywhere.loadVLMModelWithPath(
        modelPath,
        mmprojPath: mmprojPath,
        modelId: modelId,
        modelName: modelName,
      );

  /// Unload the currently-loaded VLM model.
  Future<void> unload() => legacy.RunAnywhere.unloadVLMModel();

  /// Cancel any in-flight VLM generation.
  Future<void> cancel() => legacy.RunAnywhere.cancelVLMGeneration();

  /// Describe an image with a default or custom prompt.
  Future<String> describe(
    VLMImage image, {
    String prompt = "What's in this image?",
    VLMGenerationOptions options = const VLMGenerationOptions(),
  }) =>
      legacy.RunAnywhere.describeImage(image, prompt: prompt, options: options);

  /// Ask a specific question about an image.
  Future<String> askAbout(
    String question, {
    required VLMImage image,
    VLMGenerationOptions options = const VLMGenerationOptions(),
  }) =>
      legacy.RunAnywhere.askAboutImage(question, image: image, options: options);

  /// Process an image with VLM (full result with metrics).
  Future<VLMResult> processImage(
    VLMImage image, {
    required String prompt,
    VLMGenerationOptions options = const VLMGenerationOptions(),
  }) =>
      legacy.RunAnywhere.processImage(image, prompt: prompt, options: options);

  /// Stream image processing with real-time tokens.
  Future<VLMStreamingResult> processImageStream(
    VLMImage image, {
    required String prompt,
    VLMGenerationOptions options = const VLMGenerationOptions(),
  }) =>
      legacy.RunAnywhere.processImageStream(
        image,
        prompt: prompt,
        options: options,
      );
}
