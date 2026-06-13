// SPDX-License-Identifier: Apache-2.0
//
// model_category_extensions.dart — model-category convenience helpers.
// Mirrors Swift `RAModelCategory+DefaultFramework.swift` and
// `ModelTypes.swift` (`requiresContextLength`) — both delegate to commons
// so every SDK shares one source of truth.

import 'package:runanywhere/core/native/rac_native.dart' show RacNative;
import 'package:runanywhere/generated/model_types.pbenum.dart';
import 'package:runanywhere/native/type_conversions/model_types_cpp_bridge.dart'
    show ProtoModelCategoryCppBridge, inferenceFrameworkFromC;

extension ModelCategoryDefaults on ModelCategory {
  /// Framework the SDK falls back to when a category has no explicit model
  /// framework resolved (e.g. a pending UI selection that has not yet matched
  /// a catalogued model). Delegates to commons'
  /// `rac_model_category_default_framework` — mirrors Swift
  /// `RAModelCategory.defaultFramework`
  /// (RAModelCategory+DefaultFramework.swift:22-24).
  InferenceFramework get defaultFramework {
    final fn = RacNative.bindings.rac_model_category_default_framework;
    if (fn == null) {
      return InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
    }
    return inferenceFrameworkFromC(fn(toC()));
  }

  /// Whether this category typically requires a context length. Delegates to
  /// commons' `rac_model_category_requires_context_length` — mirrors Swift
  /// `RAModelCategory.requiresContextLength` (ModelTypes.swift:147-149).
  bool get requiresContextLength {
    final fn = RacNative.bindings.rac_model_category_requires_context_length;
    if (fn == null) {
      // Fallback mirrors the commons table: text-generation categories only.
      return this == ModelCategory.MODEL_CATEGORY_LANGUAGE ||
          this == ModelCategory.MODEL_CATEGORY_VISION ||
          this == ModelCategory.MODEL_CATEGORY_MULTIMODAL;
    }
    return fn(toC()) != 0;
  }
}
