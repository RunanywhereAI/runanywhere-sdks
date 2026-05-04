/// ModelTypes + CppBridge
///
/// Conversion extensions for Dart model types to C++ model types.
/// Used by DartBridgeModelRegistry to convert between Dart and C++ types.
///
/// Mirrors Swift's ModelTypes+CppBridge.swift exactly.
library model_types_cpp_bridge;

import 'dart:io';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pbenum.dart' as pb;

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
  static const int embedding = 7;
  static const int voiceActivityDetection = 8;
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
  static const int mlx = 7;
  static const int coreml = 8;
  static const int whisperkitCoreml = 9;
  static const int metalrt = 10; // RAC_FRAMEWORK_METALRT
  static const int genie = 11; // RAC_FRAMEWORK_GENIE
  static const int sherpa = 12; // RAC_FRAMEWORK_SHERPA
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
    switch (toProto()) {
      case pb.ModelCategory.MODEL_CATEGORY_LANGUAGE:
        return RacModelCategory.language;
      case pb.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
        return RacModelCategory.speechRecognition;
      case pb.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
        return RacModelCategory.speechSynthesis;
      case pb.ModelCategory.MODEL_CATEGORY_VISION:
        return RacModelCategory.vision;
      case pb.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:
        return RacModelCategory.imageGeneration;
      case pb.ModelCategory.MODEL_CATEGORY_MULTIMODAL:
        return RacModelCategory.multimodal;
      case pb.ModelCategory.MODEL_CATEGORY_AUDIO:
        return RacModelCategory.audio;
      case pb.ModelCategory.MODEL_CATEGORY_EMBEDDING:
        return RacModelCategory.embedding;
      case pb.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return RacModelCategory.voiceActivityDetection;
      case pb.ModelCategory.MODEL_CATEGORY_UNSPECIFIED:
      default:
        return RacModelCategory.unknown;
    }
  }

  /// Create from C++ model category type
  static ModelCategory fromC(int cCategory) {
    return ModelCategory.fromProto(_categoryProtoFromC(cCategory));
  }
}

pb.ModelCategory _categoryProtoFromC(int cCategory) {
  switch (cCategory) {
    case RacModelCategory.language:
      return pb.ModelCategory.MODEL_CATEGORY_LANGUAGE;
    case RacModelCategory.speechRecognition:
      return pb.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;
    case RacModelCategory.speechSynthesis:
      return pb.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;
    case RacModelCategory.vision:
      return pb.ModelCategory.MODEL_CATEGORY_VISION;
    case RacModelCategory.imageGeneration:
      return pb.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION;
    case RacModelCategory.multimodal:
      return pb.ModelCategory.MODEL_CATEGORY_MULTIMODAL;
    case RacModelCategory.audio:
      return pb.ModelCategory.MODEL_CATEGORY_AUDIO;
    case RacModelCategory.embedding:
      return pb.ModelCategory.MODEL_CATEGORY_EMBEDDING;
    case RacModelCategory.voiceActivityDetection:
      return pb.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
    default:
      return pb.ModelCategory.MODEL_CATEGORY_UNSPECIFIED;
  }
}

// =============================================================================
// ModelFormat C++ Conversion
// =============================================================================

extension ModelFormatCppBridge on ModelFormat {
  /// Convert to C++ model format type
  int toC() {
    switch (toProto()) {
      case pb.ModelFormat.MODEL_FORMAT_ONNX:
        return RacModelFormat.onnx;
      case pb.ModelFormat.MODEL_FORMAT_ORT:
        return RacModelFormat.ort;
      case pb.ModelFormat.MODEL_FORMAT_GGUF:
        return RacModelFormat.gguf;
      case pb.ModelFormat.MODEL_FORMAT_BIN:
        return RacModelFormat.bin;
      case pb.ModelFormat.MODEL_FORMAT_UNKNOWN:
      case pb.ModelFormat.MODEL_FORMAT_UNSPECIFIED:
      default:
        return RacModelFormat.unknown;
    }
  }

  /// Create from C++ model format type
  static ModelFormat fromC(int cFormat) {
    return ModelFormat.fromProto(_formatProtoFromC(cFormat));
  }
}

pb.ModelFormat _formatProtoFromC(int cFormat) {
  switch (cFormat) {
    case RacModelFormat.onnx:
      return pb.ModelFormat.MODEL_FORMAT_ONNX;
    case RacModelFormat.ort:
      return pb.ModelFormat.MODEL_FORMAT_ORT;
    case RacModelFormat.gguf:
      return pb.ModelFormat.MODEL_FORMAT_GGUF;
    case RacModelFormat.bin:
      return pb.ModelFormat.MODEL_FORMAT_BIN;
    default:
      return pb.ModelFormat.MODEL_FORMAT_UNKNOWN;
  }
}

// =============================================================================
// InferenceFramework C++ Conversion
// =============================================================================

extension InferenceFrameworkCppBridge on InferenceFramework {
  /// Convert to C++ inference framework type
  int toC() {
    switch (toProto()) {
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
        return RacInferenceFramework.onnx;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return RacInferenceFramework.llamaCpp;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return RacInferenceFramework.foundationModels;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
        return RacInferenceFramework.systemTts;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO:
        return RacInferenceFramework.fluidAudio;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN:
        return RacInferenceFramework.builtIn;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_NONE:
        return RacInferenceFramework.none;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_GENIE:
        return RacInferenceFramework.genie;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
        return RacInferenceFramework.sherpa;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN:
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED:
      default:
        return RacInferenceFramework.unknown;
    }
  }

  /// Create from C++ inference framework type
  static InferenceFramework fromC(int cFramework) {
    return InferenceFramework.fromProto(_frameworkProtoFromC(cFramework));
  }
}

pb.InferenceFramework _frameworkProtoFromC(int cFramework) {
  switch (cFramework) {
    case RacInferenceFramework.onnx:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_ONNX;
    case RacInferenceFramework.llamaCpp:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP;
    case RacInferenceFramework.foundationModels:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
    case RacInferenceFramework.systemTts:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS;
    case RacInferenceFramework.fluidAudio:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO;
    case RacInferenceFramework.builtIn:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN;
    case RacInferenceFramework.none:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_NONE;
    case RacInferenceFramework.genie:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_GENIE;
    case RacInferenceFramework.sherpa:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA;
    default:
      return pb.InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
  }
}

// =============================================================================
// ModelSource C++ Conversion
// =============================================================================

extension ModelSourceCppBridge on ModelSource {
  /// Convert to C++ model source type
  int toC() {
    switch (toProto()) {
      case pb.ModelSource.MODEL_SOURCE_REMOTE:
        return RacModelSource.remote;
      case pb.ModelSource.MODEL_SOURCE_LOCAL:
        return RacModelSource.local;
      case pb.ModelSource.MODEL_SOURCE_UNSPECIFIED:
      default:
        return RacModelSource.remote;
    }
  }

  /// Create from C++ model source type
  static ModelSource fromC(int cSource) {
    return ModelSource.fromProto(_sourceProtoFromC(cSource));
  }
}

// =============================================================================
// Generated proto <-> C++ conversion helpers
// =============================================================================

extension ProtoModelCategoryCppBridge on pb.ModelCategory {
  /// Convert a generated model category enum to C++ rac_model_category_t.
  int toC() {
    switch (this) {
      case pb.ModelCategory.MODEL_CATEGORY_LANGUAGE:
        return RacModelCategory.language;
      case pb.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
        return RacModelCategory.speechRecognition;
      case pb.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
        return RacModelCategory.speechSynthesis;
      case pb.ModelCategory.MODEL_CATEGORY_VISION:
        return RacModelCategory.vision;
      case pb.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:
        return RacModelCategory.imageGeneration;
      case pb.ModelCategory.MODEL_CATEGORY_MULTIMODAL:
        return RacModelCategory.multimodal;
      case pb.ModelCategory.MODEL_CATEGORY_AUDIO:
        return RacModelCategory.audio;
      case pb.ModelCategory.MODEL_CATEGORY_EMBEDDING:
        return RacModelCategory.embedding;
      case pb.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return RacModelCategory.voiceActivityDetection;
      case pb.ModelCategory.MODEL_CATEGORY_UNSPECIFIED:
      default:
        return RacModelCategory.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case pb.ModelCategory.MODEL_CATEGORY_LANGUAGE:
        return 'Language Model';
      case pb.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
        return 'Speech Recognition';
      case pb.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
        return 'Text-to-Speech';
      case pb.ModelCategory.MODEL_CATEGORY_VISION:
        return 'Vision Model';
      case pb.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:
        return 'Image Generation';
      case pb.ModelCategory.MODEL_CATEGORY_MULTIMODAL:
        return 'Multimodal';
      case pb.ModelCategory.MODEL_CATEGORY_AUDIO:
        return 'Audio Processing';
      case pb.ModelCategory.MODEL_CATEGORY_EMBEDDING:
        return 'Embedding Model';
      case pb.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return 'Voice Activity Detection';
      case pb.ModelCategory.MODEL_CATEGORY_UNSPECIFIED:
      default:
        return 'Unknown';
    }
  }
}

extension ProtoModelFormatCppBridge on pb.ModelFormat {
  /// Convert a generated model format enum to C++ rac_model_format_t.
  int toC() {
    switch (this) {
      case pb.ModelFormat.MODEL_FORMAT_ONNX:
        return RacModelFormat.onnx;
      case pb.ModelFormat.MODEL_FORMAT_ORT:
        return RacModelFormat.ort;
      case pb.ModelFormat.MODEL_FORMAT_GGUF:
        return RacModelFormat.gguf;
      case pb.ModelFormat.MODEL_FORMAT_BIN:
        return RacModelFormat.bin;
      case pb.ModelFormat.MODEL_FORMAT_UNKNOWN:
      case pb.ModelFormat.MODEL_FORMAT_UNSPECIFIED:
      default:
        return RacModelFormat.unknown;
    }
  }

  String get rawValue {
    switch (this) {
      case pb.ModelFormat.MODEL_FORMAT_GGUF:
        return 'gguf';
      case pb.ModelFormat.MODEL_FORMAT_GGML:
        return 'ggml';
      case pb.ModelFormat.MODEL_FORMAT_ONNX:
        return 'onnx';
      case pb.ModelFormat.MODEL_FORMAT_ORT:
        return 'ort';
      case pb.ModelFormat.MODEL_FORMAT_BIN:
        return 'bin';
      case pb.ModelFormat.MODEL_FORMAT_COREML:
        return 'coreml';
      case pb.ModelFormat.MODEL_FORMAT_TFLITE:
        return 'tflite';
      default:
        return 'unknown';
    }
  }
}

extension ProtoInferenceFrameworkCppBridge on pb.InferenceFramework {
  /// Convert a generated inference framework enum to C++ rac_inference_framework_t.
  int toC() {
    switch (this) {
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
        return RacInferenceFramework.onnx;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return RacInferenceFramework.llamaCpp;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return RacInferenceFramework.foundationModels;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
        return RacInferenceFramework.systemTts;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO:
        return RacInferenceFramework.fluidAudio;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN:
        return RacInferenceFramework.builtIn;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_NONE:
        return RacInferenceFramework.none;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_GENIE:
        return RacInferenceFramework.genie;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
        return RacInferenceFramework.sherpa;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_COREML:
        return RacInferenceFramework.coreml;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_MLX:
        return RacInferenceFramework.mlx;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT_COREML:
        return RacInferenceFramework.whisperkitCoreml;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_METALRT:
        return RacInferenceFramework.metalrt;
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN:
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED:
      default:
        return RacInferenceFramework.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
        return 'ONNX Runtime';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
        return 'Sherpa-ONNX';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return 'llama.cpp';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return 'Foundation Models';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
        return 'System TTS';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO:
        return 'FluidAudio';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_GENIE:
        return 'Qualcomm Genie';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_COREML:
        return 'Core ML';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_MLX:
        return 'MLX';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT_COREML:
        return 'WhisperKit Core ML';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_METALRT:
        return 'MetalRT';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN:
        return 'Built-in';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_NONE:
        return 'None';
      default:
        return 'Unknown';
    }
  }
}

extension ProtoModelSourceCppBridge on pb.ModelSource {
  int toC() {
    switch (this) {
      case pb.ModelSource.MODEL_SOURCE_LOCAL:
        return RacModelSource.local;
      case pb.ModelSource.MODEL_SOURCE_REMOTE:
      case pb.ModelSource.MODEL_SOURCE_UNSPECIFIED:
      default:
        return RacModelSource.remote;
    }
  }
}

extension ProtoModelInfoHelpers on model_pb.ModelInfo {
  Uri? get downloadUri => hasDownloadUrl() && downloadUrl.isNotEmpty
      ? Uri.tryParse(downloadUrl)
      : null;

  String? get localFilePath =>
      hasLocalPath() && localPath.isNotEmpty ? localPath : null;

  int? get downloadSize =>
      hasDownloadSizeBytes() ? downloadSizeBytes.toInt() : null;

  int? get nullableContextLength =>
      hasContextLength() && contextLength > 0 ? contextLength : null;

  bool get isBuiltIn {
    if (hasBuiltIn() && builtIn) return true;
    if (localPath.startsWith('builtin:')) return true;
    return framework ==
            pb.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
        framework == pb.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS ||
        framework == pb.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN;
  }

  bool get isDownloaded {
    if (isBuiltIn) return true;
    final path = localFilePath;
    if (path == null) return false;
    return File(path).existsSync() || Directory(path).existsSync();
  }

  bool get isAvailable => isDownloaded;
}

model_pb.ModelInfo protoModelInfoFromCFields({
  required String id,
  required String name,
  required int category,
  required int format,
  required int framework,
  required int source,
  required int downloadSizeBytes,
  required int contextLength,
  String? downloadUrl,
  String? localPath,
  int supportsThinking = 0,
  int supportsLora = 0,
  String? description,
  int createdAtUnixMs = 0,
  int updatedAtUnixMs = 0,
}) {
  return model_pb.ModelInfo(
    id: id,
    name: name,
    category: _categoryProtoFromC(category),
    format: _formatProtoFromC(format),
    framework: _frameworkProtoFromC(framework),
    source: _sourceProtoFromC(source),
    downloadUrl: downloadUrl ?? '',
    localPath: localPath ?? '',
    downloadSizeBytes: fixnum.Int64(downloadSizeBytes),
    contextLength: contextLength,
    supportsThinking: supportsThinking != 0,
    supportsLora: supportsLora != 0,
    description: description ?? '',
    createdAtUnixMs: fixnum.Int64(createdAtUnixMs),
    updatedAtUnixMs: fixnum.Int64(updatedAtUnixMs),
  );
}

pb.ModelFormat protoModelFormatFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.gguf')) return pb.ModelFormat.MODEL_FORMAT_GGUF;
  if (lower.endsWith('.ggml')) return pb.ModelFormat.MODEL_FORMAT_GGML;
  if (lower.endsWith('.onnx')) return pb.ModelFormat.MODEL_FORMAT_ONNX;
  if (lower.endsWith('.ort')) return pb.ModelFormat.MODEL_FORMAT_ORT;
  if (lower.endsWith('.bin')) return pb.ModelFormat.MODEL_FORMAT_BIN;
  if (lower.endsWith('.tflite')) return pb.ModelFormat.MODEL_FORMAT_TFLITE;
  return pb.ModelFormat.MODEL_FORMAT_UNKNOWN;
}

model_pb.ModelInfo withInferredArtifact(model_pb.ModelInfo model) {
  if (model.hasArtifactType() ||
      model.hasSingleFile() ||
      model.hasArchive() ||
      model.hasMultiFile() ||
      model.hasBuiltIn() ||
      model.hasCustomStrategyId()) {
    return model;
  }

  if (model.isBuiltIn) {
    return model.deepCopy()
      ..artifactType = pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY
      ..builtIn = true;
  }

  final url = model.downloadUrl.toLowerCase();
  if (url.endsWith('.tar.gz') || url.endsWith('.tgz')) {
    return model.deepCopy()
      ..artifactType = pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE
      ..archive = model_pb.ArchiveArtifact(
        type: pb.ArchiveType.ARCHIVE_TYPE_TAR_GZ,
        structure: pb.ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN,
      );
  }
  if (url.endsWith('.zip')) {
    return model.deepCopy()
      ..artifactType = pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE
      ..archive = model_pb.ArchiveArtifact(
        type: pb.ArchiveType.ARCHIVE_TYPE_ZIP,
        structure: pb.ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN,
      );
  }

  return model.deepCopy()
    ..artifactType = pb.ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE
    ..singleFile = model_pb.SingleFileArtifact();
}

pb.ModelSource _sourceProtoFromC(int cSource) {
  switch (cSource) {
    case RacModelSource.remote:
      return pb.ModelSource.MODEL_SOURCE_REMOTE;
    case RacModelSource.local:
      return pb.ModelSource.MODEL_SOURCE_LOCAL;
    default:
      return pb.ModelSource.MODEL_SOURCE_UNSPECIFIED;
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
