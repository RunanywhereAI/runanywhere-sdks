// SPDX-License-Identifier: Apache-2.0
//
// model_category_extensions.dart — model-category convenience helpers.
// Mirrors Swift `RAModelCategory+DefaultFramework.swift` and commons'
// `rac_model_category_default_framework`.

import 'package:runanywhere/generated/model_types.pbenum.dart';

extension ModelCategoryDefaults on ModelCategory {
  /// Framework the SDK falls back to when a category has no explicit model
  /// framework resolved (e.g. a pending UI selection that has not yet matched
  /// a catalogued model). Mirrors commons'
  /// `rac_model_category_default_framework`.
  InferenceFramework get defaultFramework {
    switch (this) {
      case ModelCategory.MODEL_CATEGORY_LANGUAGE:
      case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
        return InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP;
      case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
      case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
      case ModelCategory.MODEL_CATEGORY_EMBEDDING:
      case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return InferenceFramework.INFERENCE_FRAMEWORK_ONNX;
      default:
        return InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
    }
  }
}
