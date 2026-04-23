// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_stt.dart — v4.0 STT capability instance API.
// See docs/migrations/v3_to_v4_flutter.md for the migration table.

// ignore_for_file: deprecated_member_use_from_same_package
import 'dart:typed_data';
import 'package:runanywhere/public/runanywhere.dart' as legacy;
import 'package:runanywhere/public/types/types.dart';

/// STT (speech-to-text) capability surface.
///
/// Access via `RunAnywhere.instance.stt`.
class RunAnywhereSTT {
  RunAnywhereSTT._();
  static final RunAnywhereSTT _instance = RunAnywhereSTT._();
  static RunAnywhereSTT get shared => _instance;

  /// True when an STT model is currently loaded.
  bool get isLoaded => legacy.RunAnywhere.isSTTModelLoaded;

  /// Currently-loaded STT model ID, or null.
  String? get currentModelId => legacy.RunAnywhere.currentSTTModelId;

  /// Currently-loaded STT model as `ModelInfo`, or null.
  Future<ModelInfo?> currentModel() => legacy.RunAnywhere.currentSTTModel();

  /// Load an STT model by ID.
  Future<void> load(String modelId) => legacy.RunAnywhere.loadSTTModel(modelId);

  /// Unload the currently-loaded STT model.
  Future<void> unload() => legacy.RunAnywhere.unloadSTTModel();

  /// Transcribe audio data to text.
  Future<String> transcribe(Uint8List audioData) =>
      legacy.RunAnywhere.transcribe(audioData);

  /// Transcribe audio data with full result metadata.
  Future<STTResult> transcribeWithResult(Uint8List audioData) =>
      legacy.RunAnywhere.transcribeWithResult(audioData);
}
