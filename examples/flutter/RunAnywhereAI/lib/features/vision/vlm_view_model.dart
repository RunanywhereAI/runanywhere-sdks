import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;

/// VLMViewModel - State management for the VLM screen.
///
/// Mirrors the Android Kotlin VisionViewModel: the user supplies an image from
/// the device gallery or the device camera app (no in-app camera preview),
/// then runs a streamed description over the loaded VLM model. Image picking
/// happens in the view via `image_picker`; this view model owns the selected
/// image path, the prompt, and the streamed inference state.
class VLMViewModel extends ChangeNotifier {
  // MARK: - State Properties

  bool _isModelLoaded = false;
  String? _loadedModelName;
  bool _isProcessing = false;
  String _currentDescription = '';
  String? _error;
  String? _selectedImagePath;
  String prompt = 'Describe this image in detail.';

  // Getters
  bool get isModelLoaded => _isModelLoaded;
  String? get loadedModelName => _loadedModelName;
  bool get isProcessing => _isProcessing;
  String get currentDescription => _currentDescription;
  String? get error => _error;
  String? get selectedImagePath => _selectedImagePath;
  // MARK: - Model Management

  /// Check if a VLM model is loaded.
  Future<void> checkModelStatus() async {
    final state = await sdk.RunAnywhere.models.state();
    final model =
        state.loaded[sdk.ModelCategory.MODEL_CATEGORY_MULTIMODAL] ??
        state.loaded[sdk.ModelCategory.MODEL_CATEGORY_VISION];
    _isModelLoaded = model != null;
    _loadedModelName = model?.name;
    notifyListeners();
  }

  /// Handle model selection from the model sheet — loads the SDK model by id.
  Future<void> onModelSelected(
      String modelId, String modelName, BuildContext context) async {
    try {
      debugPrint('Loading VLM model: $modelId');
      await sdk.RunAnywhere.models.load(modelId);
      _isModelLoaded = true;
      _loadedModelName = modelName;
      notifyListeners();
      debugPrint('VLM model loaded: $modelName');
    } catch (e) {
      debugPrint('Failed to load VLM model: $e');
      _error = 'Failed to load model: $e';
      notifyListeners();
      if (context.mounted) {
        unawaited(
          ScaffoldMessenger.of(context)
              .showSnackBar(
                SnackBar(content: Text('Failed to load model: $e')),
              )
              .closed
              .then((_) => null),
        );
      }
    }
  }

  // MARK: - Image Selection

  /// Set the image (gallery pick or camera capture) to describe. Clears any
  /// previous description so the preview and result stay in sync.
  void setSelectedImage(String path) {
    _selectedImagePath = path;
    _currentDescription = '';
    _error = null;
    notifyListeners();
  }

  // MARK: - Image Processing

  /// Describe the currently selected image with the current prompt, streaming
  /// tokens into [currentDescription] as they arrive.
  Future<void> describeSelectedImage() async {
    final path = _selectedImagePath;
    if (path == null || _isProcessing) {
      return;
    }
    final trimmedPrompt = prompt.trim();
    final promptText =
        trimmedPrompt.isEmpty ? 'Describe this image in detail.' : trimmedPrompt;

    _isProcessing = true;
    _error = null;
    _currentDescription = '';
    notifyListeners();

    try {
      final events = sdk.RunAnywhere.vlm.generateStream(
        sdk.ImageInput.file(path),
        promptText,
        options: sdk.LlmOptions(maxOutputTokens: 300),
      );

      final buffer = StringBuffer();
      await for (final event in events) {
        if (event is! sdk.GenerationToken || event.text.isEmpty) continue;
        buffer.write(event.text);
        _currentDescription = buffer.toString();
        notifyListeners();
      }

      debugPrint('VLM describe complete: ${_currentDescription.length} chars');
    } catch (e) {
      debugPrint('VLM describe error: $e');
      _error = e.toString();
      notifyListeners();
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  // MARK: - Cancellation

  /// Cancel an ongoing VLM generation.
  Future<void> cancelGeneration() async {
    sdk.RunAnywhere.vlm.cancel();
    debugPrint('VLM generation cancelled');
  }
}
