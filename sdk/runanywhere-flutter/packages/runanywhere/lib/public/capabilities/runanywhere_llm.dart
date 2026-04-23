// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_llm.dart — v4.0 LLM capability instance API.
//
// One of 9 per-capability classes that the v4.0 RunAnywhere singleton
// exposes via lazy getters (`RunAnywhere.instance.llm`). Each method
// here forwards to the matching static `RunAnywhere.X()` method
// during the v4.0.x deprecation window; v4.1 will reverse the
// delegation (instance calls DartBridge directly) and delete the
// static surface.
//
// See `docs/migrations/v3_to_v4_flutter.md` for the full v3.x → v4.0
// migration table.

// ignore_for_file: deprecated_member_use_from_same_package
import 'package:runanywhere/public/runanywhere.dart' as legacy;
import 'package:runanywhere/public/types/types.dart';

/// LLM (text generation) capability surface.
///
/// Access via `RunAnywhere.instance.llm`.
class RunAnywhereLLM {
  RunAnywhereLLM._();
  static final RunAnywhereLLM _instance = RunAnywhereLLM._();
  static RunAnywhereLLM get shared => _instance;

  /// True when an LLM model is currently loaded in the C++ backend.
  bool get isLoaded => legacy.RunAnywhere.isModelLoaded;

  /// Currently-loaded LLM model ID, or null.
  String? get currentModelId => legacy.RunAnywhere.currentModelId;

  /// Currently-loaded LLM model as `ModelInfo`, or null.
  Future<ModelInfo?> currentModel() => legacy.RunAnywhere.currentLLMModel();

  /// Load an LLM model by ID.
  Future<void> load(String modelId) => legacy.RunAnywhere.loadModel(modelId);

  /// Unload the currently-loaded LLM model.
  Future<void> unload() => legacy.RunAnywhere.unloadModel();

  /// Simple text generation — returns just the generated text.
  Future<String> chat(String prompt) => legacy.RunAnywhere.chat(prompt);

  /// Full LLM generation with options + telemetry.
  Future<LLMGenerationResult> generate(
    String prompt, {
    LLMGenerationOptions? options,
  }) =>
      legacy.RunAnywhere.generate(prompt, options: options);

  /// Streaming LLM generation; returns a result with a `tokenStream`.
  Future<LLMStreamingResult> generateStream(
    String prompt, {
    LLMGenerationOptions? options,
  }) =>
      legacy.RunAnywhere.generateStream(prompt, options: options);

  /// Cancel any in-flight LLM generation.
  Future<void> cancel() => legacy.RunAnywhere.cancelGeneration();
}
