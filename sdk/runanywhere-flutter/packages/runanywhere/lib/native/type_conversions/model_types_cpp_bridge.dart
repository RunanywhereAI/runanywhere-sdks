/// ModelTypes + CppBridge
///
/// Conversion extensions for Dart model types to C++ model types.
/// Used by DartBridgeModelRegistry to convert between Dart and C++ types.
///
/// Mirrors Swift's ModelTypes+CppBridge.swift exactly.
library model_types_cpp_bridge;

import 'package:runanywhere/core/types/model_types.dart';

// =============================================================================
// C++ Constants (from rac_model_types.h)
// =============================================================================

/// Model category constants (rac_model_category_t)
abstract class RacModelCategory {
  static const int language = 0;
  static const int speechRecognition = 1;
  static const int speechSynthesis = 2;
  static const int vision = 3;
  static const int imageGeneration = 4;
  static const int multimodal = 5;
  static const int audio = 6;
  static const int unknown = 99;
}

/// Model format constants (rac_model_format_t)
abstract class RacModelFormat {
  static const int onnx = 0;
  static const int ort = 1;
  static const int gguf = 2;
  static const int bin = 3;
  static const int unknown = 99;
}

/// Inference framework constants (rac_inference_framework_t)
abstract class RacInferenceFramework {
  static const int onnx = 0;
  static const int llamaCpp = 1;
  static const int foundationModels = 2;
  static const int systemTts = 3;
  static const int fluidAudio = 4;
  static const int builtIn = 5;
  static const int none = 6;
  static const int unknown = 99;
}

/// Model source constants (rac_model_source_t)
abstract class RacModelSource {
  static const int remote = 0;
  static const int local = 1;
}

/// Artifact kind constants (rac_artifact_type_kind_t)
abstract class RacArtifactKind {
  static const int singleFile = 0;
  static const int archive = 1;
  static const int multiFile = 2;
  static const int custom = 3;
  static const int builtIn = 4;
}

/// Archive type constants (rac_archive_type_t)
abstract class RacArchiveType {
  static const int none = 0;
  static const int zip = 1;
  static const int tarGz = 2;
  static const int tarBz2 = 3;
  static const int tarXz = 4;
  static const int tar = 5;
}

/// Archive structure constants (rac_archive_structure_t)
abstract class RacArchiveStructure {
  static const int unknown = 0;
  static const int flat = 1;
  static const int nested = 2;
  static const int rootFolder = 3;
}

// =============================================================================
// ModelCategory C++ Conversion
// =============================================================================

extension ModelCategoryCppBridge on ModelCategory {
  /// Convert to C++ model category type
  int toC() {
    switch (this) {
      case ModelCategory.language:
        return RacModelCategory.language;
      case ModelCategory.speechRecognition:
        return RacModelCategory.speechRecognition;
      case ModelCategory.speechSynthesis:
        return RacModelCategory.speechSynthesis;
      case ModelCategory.vision:
        return RacModelCategory.vision;
      case ModelCategory.imageGeneration:
        return RacModelCategory.imageGeneration;
      case ModelCategory.multimodal:
        return RacModelCategory.multimodal;
      case ModelCategory.audio:
        return RacModelCategory.audio;
    }
  }

  /// Create from C++ model category type
  static ModelCategory fromC(int cCategory) {
    switch (cCategory) {
      case RacModelCategory.language:
        return ModelCategory.language;
      case RacModelCategory.speechRecognition:
        return ModelCategory.speechRecognition;
      case RacModelCategory.speechSynthesis:
        return ModelCategory.speechSynthesis;
      case RacModelCategory.vision:
        return ModelCategory.vision;
      case RacModelCategory.imageGeneration:
        return ModelCategory.imageGeneration;
      case RacModelCategory.multimodal:
        return ModelCategory.multimodal;
      case RacModelCategory.audio:
        return ModelCategory.audio;
      default:
        return ModelCategory.audio; // Default fallback
    }
  }
}

// =============================================================================
// ModelFormat C++ Conversion
// =============================================================================

extension ModelFormatCppBridge on ModelFormat {
  /// Convert to C++ model format type
  int toC() {
    switch (this) {
      case ModelFormat.onnx:
        return RacModelFormat.onnx;
      case ModelFormat.ort:
        return RacModelFormat.ort;
      case ModelFormat.gguf:
        return RacModelFormat.gguf;
      case ModelFormat.bin:
        return RacModelFormat.bin;
      case ModelFormat.unknown:
        return RacModelFormat.unknown;
    }
  }

  /// Create from C++ model format type
  static ModelFormat fromC(int cFormat) {
    switch (cFormat) {
      case RacModelFormat.onnx:
        return ModelFormat.onnx;
      case RacModelFormat.ort:
        return ModelFormat.ort;
      case RacModelFormat.gguf:
        return ModelFormat.gguf;
      case RacModelFormat.bin:
        return ModelFormat.bin;
      default:
        return ModelFormat.unknown;
    }
  }
}

// =============================================================================
// InferenceFramework C++ Conversion
// =============================================================================

extension InferenceFrameworkCppBridge on InferenceFramework {
  /// Convert to C++ inference framework type
  int toC() {
    switch (this) {
      case InferenceFramework.onnx:
        return RacInferenceFramework.onnx;
      case InferenceFramework.llamaCpp:
        return RacInferenceFramework.llamaCpp;
      case InferenceFramework.foundationModels:
        return RacInferenceFramework.foundationModels;
      case InferenceFramework.systemTTS:
        return RacInferenceFramework.systemTts;
      case InferenceFramework.fluidAudio:
        return RacInferenceFramework.fluidAudio;
      case InferenceFramework.builtIn:
        return RacInferenceFramework.builtIn;
      case InferenceFramework.none:
        return RacInferenceFramework.none;
      case InferenceFramework.unknown:
        return RacInferenceFramework.unknown;
    }
  }

  /// Create from C++ inference framework type
  static InferenceFramework fromC(int cFramework) {
    switch (cFramework) {
      case RacInferenceFramework.onnx:
        return InferenceFramework.onnx;
      case RacInferenceFramework.llamaCpp:
        return InferenceFramework.llamaCpp;
      case RacInferenceFramework.foundationModels:
        return InferenceFramework.foundationModels;
      case RacInferenceFramework.systemTts:
        return InferenceFramework.systemTTS;
      case RacInferenceFramework.fluidAudio:
        return InferenceFramework.fluidAudio;
      case RacInferenceFramework.builtIn:
        return InferenceFramework.builtIn;
      case RacInferenceFramework.none:
        return InferenceFramework.none;
      default:
        return InferenceFramework.unknown;
    }
  }
}

// =============================================================================
// ModelSource C++ Conversion
// =============================================================================

extension ModelSourceCppBridge on ModelSource {
  /// Convert to C++ model source type
  int toC() {
    switch (this) {
      case ModelSource.remote:
        return RacModelSource.remote;
      case ModelSource.local:
        return RacModelSource.local;
    }
  }

  /// Create from C++ model source type
  static ModelSource fromC(int cSource) {
    switch (cSource) {
      case RacModelSource.remote:
        return ModelSource.remote;
      case RacModelSource.local:
        return ModelSource.local;
      default:
        return ModelSource.local;
    }
  }
}

// =============================================================================
// ModelArtifactType C++ Conversion
// =============================================================================

extension ModelArtifactTypeCppBridge on ModelArtifactType {
  /// Convert to C++ artifact kind type
  int toC() {
    return switch (this) {
      SingleFileArtifact() => RacArtifactKind.singleFile,
      ArchiveArtifact() => RacArtifactKind.archive,
      MultiFileArtifact() => RacArtifactKind.multiFile,
      CustomArtifact() => RacArtifactKind.custom,
      BuiltInArtifact() => RacArtifactKind.builtIn,
    };
  }

  /// Create from C++ artifact kind type
  static ModelArtifactType fromC(int cKind) {
    switch (cKind) {
      case RacArtifactKind.singleFile:
        return const SingleFileArtifact();
      case RacArtifactKind.archive:
        return const ArchiveArtifact(
          archiveType: ArchiveType.zip,
          structure: ArchiveStructure.unknown,
        );
      case RacArtifactKind.multiFile:
        return const MultiFileArtifact(files: []);
      case RacArtifactKind.custom:
        return const CustomArtifact(strategyId: '');
      case RacArtifactKind.builtIn:
        return const BuiltInArtifact();
      default:
        return const SingleFileArtifact();
    }
  }
}
