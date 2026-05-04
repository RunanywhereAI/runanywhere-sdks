//
//  Generated code. Do not modify.
//  source: model_types.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Audio format — union of all cases currently defined across SDKs.
/// Sources pre-IDL:
///   Kotlin  AudioTypes.kt:12          (pcm, wav, mp3, opus, aac, flac, ogg, pcm_16bit)
///   Kotlin  ComponentTypes.kt:39      (pcm, wav, mp3, aac, ogg, opus, flac)  ← duplicate
///   Swift   AudioTypes.swift:17       (pcm, wav, mp3, opus, aac, flac)
///   Dart    audio_format.dart:3       (wav, mp3, m4a, flac, pcm, opus)
///   RN      TTSTypes.ts:36            ('pcm' | 'wav' | 'mp3')
/// ---------------------------------------------------------------------------
class AudioFormat extends $pb.ProtobufEnum {
  static const AudioFormat AUDIO_FORMAT_UNSPECIFIED = AudioFormat._(0, _omitEnumNames ? '' : 'AUDIO_FORMAT_UNSPECIFIED');
  static const AudioFormat AUDIO_FORMAT_PCM = AudioFormat._(1, _omitEnumNames ? '' : 'AUDIO_FORMAT_PCM');
  static const AudioFormat AUDIO_FORMAT_WAV = AudioFormat._(2, _omitEnumNames ? '' : 'AUDIO_FORMAT_WAV');
  static const AudioFormat AUDIO_FORMAT_MP3 = AudioFormat._(3, _omitEnumNames ? '' : 'AUDIO_FORMAT_MP3');
  static const AudioFormat AUDIO_FORMAT_OPUS = AudioFormat._(4, _omitEnumNames ? '' : 'AUDIO_FORMAT_OPUS');
  static const AudioFormat AUDIO_FORMAT_AAC = AudioFormat._(5, _omitEnumNames ? '' : 'AUDIO_FORMAT_AAC');
  static const AudioFormat AUDIO_FORMAT_FLAC = AudioFormat._(6, _omitEnumNames ? '' : 'AUDIO_FORMAT_FLAC');
  static const AudioFormat AUDIO_FORMAT_OGG = AudioFormat._(7, _omitEnumNames ? '' : 'AUDIO_FORMAT_OGG');
  static const AudioFormat AUDIO_FORMAT_M4A = AudioFormat._(8, _omitEnumNames ? '' : 'AUDIO_FORMAT_M4A');
  static const AudioFormat AUDIO_FORMAT_PCM_S16LE = AudioFormat._(9, _omitEnumNames ? '' : 'AUDIO_FORMAT_PCM_S16LE');

  static const $core.List<AudioFormat> values = <AudioFormat> [
    AUDIO_FORMAT_UNSPECIFIED,
    AUDIO_FORMAT_PCM,
    AUDIO_FORMAT_WAV,
    AUDIO_FORMAT_MP3,
    AUDIO_FORMAT_OPUS,
    AUDIO_FORMAT_AAC,
    AUDIO_FORMAT_FLAC,
    AUDIO_FORMAT_OGG,
    AUDIO_FORMAT_M4A,
    AUDIO_FORMAT_PCM_S16LE,
  ];

  static final $core.Map<$core.int, AudioFormat> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AudioFormat? valueOf($core.int value) => _byValue[value];

  const AudioFormat._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Model file format — union across all SDKs.
/// Sources pre-IDL:
///   Swift  ModelTypes.swift:27        (onnx, ort, gguf, bin, coreml, unknown)
///   Kotlin ModelTypes.kt:41           (ONNX, ORT, GGUF, BIN, QNN_CONTEXT, UNKNOWN)
///   Dart   model_types.dart:34        (onnx, ort, gguf, bin, unknown)
///   RN     enums.ts:115               (12-case superset incl. MLModel, MLPackage, TFLite,
///                                       SafeTensors, Zip, Folder, Proprietary)
///   Web    enums.ts:56                (copy of RN)
/// ---------------------------------------------------------------------------
class ModelFormat extends $pb.ProtobufEnum {
  static const ModelFormat MODEL_FORMAT_UNSPECIFIED = ModelFormat._(0, _omitEnumNames ? '' : 'MODEL_FORMAT_UNSPECIFIED');
  static const ModelFormat MODEL_FORMAT_GGUF = ModelFormat._(1, _omitEnumNames ? '' : 'MODEL_FORMAT_GGUF');
  static const ModelFormat MODEL_FORMAT_GGML = ModelFormat._(2, _omitEnumNames ? '' : 'MODEL_FORMAT_GGML');
  static const ModelFormat MODEL_FORMAT_ONNX = ModelFormat._(3, _omitEnumNames ? '' : 'MODEL_FORMAT_ONNX');
  static const ModelFormat MODEL_FORMAT_ORT = ModelFormat._(4, _omitEnumNames ? '' : 'MODEL_FORMAT_ORT');
  static const ModelFormat MODEL_FORMAT_BIN = ModelFormat._(5, _omitEnumNames ? '' : 'MODEL_FORMAT_BIN');
  static const ModelFormat MODEL_FORMAT_COREML = ModelFormat._(6, _omitEnumNames ? '' : 'MODEL_FORMAT_COREML');
  static const ModelFormat MODEL_FORMAT_MLMODEL = ModelFormat._(7, _omitEnumNames ? '' : 'MODEL_FORMAT_MLMODEL');
  static const ModelFormat MODEL_FORMAT_MLPACKAGE = ModelFormat._(8, _omitEnumNames ? '' : 'MODEL_FORMAT_MLPACKAGE');
  static const ModelFormat MODEL_FORMAT_TFLITE = ModelFormat._(9, _omitEnumNames ? '' : 'MODEL_FORMAT_TFLITE');
  static const ModelFormat MODEL_FORMAT_SAFETENSORS = ModelFormat._(10, _omitEnumNames ? '' : 'MODEL_FORMAT_SAFETENSORS');
  static const ModelFormat MODEL_FORMAT_QNN_CONTEXT = ModelFormat._(11, _omitEnumNames ? '' : 'MODEL_FORMAT_QNN_CONTEXT');
  static const ModelFormat MODEL_FORMAT_ZIP = ModelFormat._(12, _omitEnumNames ? '' : 'MODEL_FORMAT_ZIP');
  static const ModelFormat MODEL_FORMAT_FOLDER = ModelFormat._(13, _omitEnumNames ? '' : 'MODEL_FORMAT_FOLDER');
  static const ModelFormat MODEL_FORMAT_PROPRIETARY = ModelFormat._(14, _omitEnumNames ? '' : 'MODEL_FORMAT_PROPRIETARY');
  static const ModelFormat MODEL_FORMAT_UNKNOWN = ModelFormat._(15, _omitEnumNames ? '' : 'MODEL_FORMAT_UNKNOWN');

  static const $core.List<ModelFormat> values = <ModelFormat> [
    MODEL_FORMAT_UNSPECIFIED,
    MODEL_FORMAT_GGUF,
    MODEL_FORMAT_GGML,
    MODEL_FORMAT_ONNX,
    MODEL_FORMAT_ORT,
    MODEL_FORMAT_BIN,
    MODEL_FORMAT_COREML,
    MODEL_FORMAT_MLMODEL,
    MODEL_FORMAT_MLPACKAGE,
    MODEL_FORMAT_TFLITE,
    MODEL_FORMAT_SAFETENSORS,
    MODEL_FORMAT_QNN_CONTEXT,
    MODEL_FORMAT_ZIP,
    MODEL_FORMAT_FOLDER,
    MODEL_FORMAT_PROPRIETARY,
    MODEL_FORMAT_UNKNOWN,
  ];

  static final $core.Map<$core.int, ModelFormat> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelFormat? valueOf($core.int value) => _byValue[value];

  const ModelFormat._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Inference framework / runtime. Same name used across all SDKs (RN names it
/// LLMFramework; we canonicalize on InferenceFramework).
/// Sources pre-IDL:
///   Swift  ModelTypes.swift:76        (12 cases incl. coreml, mlx, whisperKitCoreML,
///                                       metalrt)
///   Kotlin ComponentTypes.kt:122      (9 cases incl. GENIE; no coreml / mlx / whisperKit /
///                                       metalrt)
///   Dart   model_types.dart:106       (9 cases, matches Kotlin)
///   RN     enums.ts:30 (LLMFramework) (16 cases)
///   Web    enums.ts:21 (LLMFramework) (16 cases, copy of RN)
/// ---------------------------------------------------------------------------
class InferenceFramework extends $pb.ProtobufEnum {
  static const InferenceFramework INFERENCE_FRAMEWORK_UNSPECIFIED = InferenceFramework._(0, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_UNSPECIFIED');
  static const InferenceFramework INFERENCE_FRAMEWORK_ONNX = InferenceFramework._(1, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_ONNX');
  static const InferenceFramework INFERENCE_FRAMEWORK_LLAMA_CPP = InferenceFramework._(2, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_LLAMA_CPP');
  static const InferenceFramework INFERENCE_FRAMEWORK_FOUNDATION_MODELS = InferenceFramework._(3, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_FOUNDATION_MODELS');
  static const InferenceFramework INFERENCE_FRAMEWORK_SYSTEM_TTS = InferenceFramework._(4, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_SYSTEM_TTS');
  static const InferenceFramework INFERENCE_FRAMEWORK_FLUID_AUDIO = InferenceFramework._(5, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_FLUID_AUDIO');
  static const InferenceFramework INFERENCE_FRAMEWORK_COREML = InferenceFramework._(6, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_COREML');
  static const InferenceFramework INFERENCE_FRAMEWORK_MLX = InferenceFramework._(7, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_MLX');
  static const InferenceFramework INFERENCE_FRAMEWORK_WHISPERKIT_COREML = InferenceFramework._(8, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_WHISPERKIT_COREML');
  static const InferenceFramework INFERENCE_FRAMEWORK_METALRT = InferenceFramework._(9, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_METALRT');
  static const InferenceFramework INFERENCE_FRAMEWORK_GENIE = InferenceFramework._(10, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_GENIE');
  static const InferenceFramework INFERENCE_FRAMEWORK_TFLITE = InferenceFramework._(11, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_TFLITE');
  static const InferenceFramework INFERENCE_FRAMEWORK_EXECUTORCH = InferenceFramework._(12, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_EXECUTORCH');
  static const InferenceFramework INFERENCE_FRAMEWORK_MEDIAPIPE = InferenceFramework._(13, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_MEDIAPIPE');
  static const InferenceFramework INFERENCE_FRAMEWORK_MLC = InferenceFramework._(14, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_MLC');
  static const InferenceFramework INFERENCE_FRAMEWORK_PICO_LLM = InferenceFramework._(15, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_PICO_LLM');
  static const InferenceFramework INFERENCE_FRAMEWORK_PIPER_TTS = InferenceFramework._(16, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_PIPER_TTS');
  static const InferenceFramework INFERENCE_FRAMEWORK_WHISPERKIT = InferenceFramework._(17, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_WHISPERKIT');
  static const InferenceFramework INFERENCE_FRAMEWORK_OPENAI_WHISPER = InferenceFramework._(18, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_OPENAI_WHISPER');
  static const InferenceFramework INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS = InferenceFramework._(19, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS');
  static const InferenceFramework INFERENCE_FRAMEWORK_BUILT_IN = InferenceFramework._(20, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_BUILT_IN');
  static const InferenceFramework INFERENCE_FRAMEWORK_NONE = InferenceFramework._(21, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_NONE');
  static const InferenceFramework INFERENCE_FRAMEWORK_UNKNOWN = InferenceFramework._(22, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_UNKNOWN');
  static const InferenceFramework INFERENCE_FRAMEWORK_SHERPA = InferenceFramework._(23, _omitEnumNames ? '' : 'INFERENCE_FRAMEWORK_SHERPA');

  static const $core.List<InferenceFramework> values = <InferenceFramework> [
    INFERENCE_FRAMEWORK_UNSPECIFIED,
    INFERENCE_FRAMEWORK_ONNX,
    INFERENCE_FRAMEWORK_LLAMA_CPP,
    INFERENCE_FRAMEWORK_FOUNDATION_MODELS,
    INFERENCE_FRAMEWORK_SYSTEM_TTS,
    INFERENCE_FRAMEWORK_FLUID_AUDIO,
    INFERENCE_FRAMEWORK_COREML,
    INFERENCE_FRAMEWORK_MLX,
    INFERENCE_FRAMEWORK_WHISPERKIT_COREML,
    INFERENCE_FRAMEWORK_METALRT,
    INFERENCE_FRAMEWORK_GENIE,
    INFERENCE_FRAMEWORK_TFLITE,
    INFERENCE_FRAMEWORK_EXECUTORCH,
    INFERENCE_FRAMEWORK_MEDIAPIPE,
    INFERENCE_FRAMEWORK_MLC,
    INFERENCE_FRAMEWORK_PICO_LLM,
    INFERENCE_FRAMEWORK_PIPER_TTS,
    INFERENCE_FRAMEWORK_WHISPERKIT,
    INFERENCE_FRAMEWORK_OPENAI_WHISPER,
    INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS,
    INFERENCE_FRAMEWORK_BUILT_IN,
    INFERENCE_FRAMEWORK_NONE,
    INFERENCE_FRAMEWORK_UNKNOWN,
    INFERENCE_FRAMEWORK_SHERPA,
  ];

  static final $core.Map<$core.int, InferenceFramework> _byValue = $pb.ProtobufEnum.initByValue(values);
  static InferenceFramework? valueOf($core.int value) => _byValue[value];

  const InferenceFramework._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Model category / modality class. Sources pre-IDL:
///   Swift ModelTypes.swift:39         (9 cases incl. voiceActivityDetection + audio)
///   Kotlin ModelTypes.kt:147          (8 cases, no VAD)
///   Dart  model_types.dart:55         (8 cases, no VAD)
///   RN    enums.ts:75                 (8 cases, no VAD, Audio labeled as VAD)
///   Web   enums.ts:39                 (7 cases, Audio labeled as VAD)
/// ---------------------------------------------------------------------------
class ModelCategory extends $pb.ProtobufEnum {
  static const ModelCategory MODEL_CATEGORY_UNSPECIFIED = ModelCategory._(0, _omitEnumNames ? '' : 'MODEL_CATEGORY_UNSPECIFIED');
  static const ModelCategory MODEL_CATEGORY_LANGUAGE = ModelCategory._(1, _omitEnumNames ? '' : 'MODEL_CATEGORY_LANGUAGE');
  static const ModelCategory MODEL_CATEGORY_SPEECH_RECOGNITION = ModelCategory._(2, _omitEnumNames ? '' : 'MODEL_CATEGORY_SPEECH_RECOGNITION');
  static const ModelCategory MODEL_CATEGORY_SPEECH_SYNTHESIS = ModelCategory._(3, _omitEnumNames ? '' : 'MODEL_CATEGORY_SPEECH_SYNTHESIS');
  static const ModelCategory MODEL_CATEGORY_VISION = ModelCategory._(4, _omitEnumNames ? '' : 'MODEL_CATEGORY_VISION');
  static const ModelCategory MODEL_CATEGORY_IMAGE_GENERATION = ModelCategory._(5, _omitEnumNames ? '' : 'MODEL_CATEGORY_IMAGE_GENERATION');
  static const ModelCategory MODEL_CATEGORY_MULTIMODAL = ModelCategory._(6, _omitEnumNames ? '' : 'MODEL_CATEGORY_MULTIMODAL');
  static const ModelCategory MODEL_CATEGORY_AUDIO = ModelCategory._(7, _omitEnumNames ? '' : 'MODEL_CATEGORY_AUDIO');
  static const ModelCategory MODEL_CATEGORY_EMBEDDING = ModelCategory._(8, _omitEnumNames ? '' : 'MODEL_CATEGORY_EMBEDDING');
  static const ModelCategory MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION = ModelCategory._(9, _omitEnumNames ? '' : 'MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION');

  static const $core.List<ModelCategory> values = <ModelCategory> [
    MODEL_CATEGORY_UNSPECIFIED,
    MODEL_CATEGORY_LANGUAGE,
    MODEL_CATEGORY_SPEECH_RECOGNITION,
    MODEL_CATEGORY_SPEECH_SYNTHESIS,
    MODEL_CATEGORY_VISION,
    MODEL_CATEGORY_IMAGE_GENERATION,
    MODEL_CATEGORY_MULTIMODAL,
    MODEL_CATEGORY_AUDIO,
    MODEL_CATEGORY_EMBEDDING,
    MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
  ];

  static final $core.Map<$core.int, ModelCategory> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelCategory? valueOf($core.int value) => _byValue[value];

  const ModelCategory._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// SDK environment. Sources pre-IDL:
///   Swift  SDKEnvironment.swift:5     (development, staging, production)
///   Kotlin RunAnywhere.kt:47          (DEVELOPMENT, STAGING, PRODUCTION, cEnvironment)
///   Kotlin SDKLogger.kt:159           (DEVELOPMENT, STAGING, PRODUCTION) ← duplicate
///   Dart   sdk_environment.dart:5     (development, staging, production)
///   RN     enums.ts:11                (Development, Staging, Production)
///   Web    enums.ts:9                 (Development, Staging, Production)
/// ---------------------------------------------------------------------------
class SDKEnvironment extends $pb.ProtobufEnum {
  static const SDKEnvironment SDK_ENVIRONMENT_UNSPECIFIED = SDKEnvironment._(0, _omitEnumNames ? '' : 'SDK_ENVIRONMENT_UNSPECIFIED');
  static const SDKEnvironment SDK_ENVIRONMENT_DEVELOPMENT = SDKEnvironment._(1, _omitEnumNames ? '' : 'SDK_ENVIRONMENT_DEVELOPMENT');
  static const SDKEnvironment SDK_ENVIRONMENT_STAGING = SDKEnvironment._(2, _omitEnumNames ? '' : 'SDK_ENVIRONMENT_STAGING');
  static const SDKEnvironment SDK_ENVIRONMENT_PRODUCTION = SDKEnvironment._(3, _omitEnumNames ? '' : 'SDK_ENVIRONMENT_PRODUCTION');

  static const $core.List<SDKEnvironment> values = <SDKEnvironment> [
    SDK_ENVIRONMENT_UNSPECIFIED,
    SDK_ENVIRONMENT_DEVELOPMENT,
    SDK_ENVIRONMENT_STAGING,
    SDK_ENVIRONMENT_PRODUCTION,
  ];

  static final $core.Map<$core.int, SDKEnvironment> _byValue = $pb.ProtobufEnum.initByValue(values);
  static SDKEnvironment? valueOf($core.int value) => _byValue[value];

  const SDKEnvironment._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Model source — where the catalog entry came from.
/// ---------------------------------------------------------------------------
class ModelSource extends $pb.ProtobufEnum {
  static const ModelSource MODEL_SOURCE_UNSPECIFIED = ModelSource._(0, _omitEnumNames ? '' : 'MODEL_SOURCE_UNSPECIFIED');
  static const ModelSource MODEL_SOURCE_REMOTE = ModelSource._(1, _omitEnumNames ? '' : 'MODEL_SOURCE_REMOTE');
  static const ModelSource MODEL_SOURCE_LOCAL = ModelSource._(2, _omitEnumNames ? '' : 'MODEL_SOURCE_LOCAL');

  static const $core.List<ModelSource> values = <ModelSource> [
    MODEL_SOURCE_UNSPECIFIED,
    MODEL_SOURCE_REMOTE,
    MODEL_SOURCE_LOCAL,
  ];

  static final $core.Map<$core.int, ModelSource> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelSource? valueOf($core.int value) => _byValue[value];

  const ModelSource._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Archive types for multi-file model packages. Sources pre-IDL:
///   Swift  ModelTypes.swift:195       (zip, tarBz2, tarGz, tarXz)
///   Kotlin ModelTypes.kt:176          (ZIP, TAR_BZ2, TAR_GZ, TAR_XZ)
///   Dart   model_types.dart:141       (zip, tarBz2, tarGz, tarXz)
/// ---------------------------------------------------------------------------
class ArchiveType extends $pb.ProtobufEnum {
  static const ArchiveType ARCHIVE_TYPE_UNSPECIFIED = ArchiveType._(0, _omitEnumNames ? '' : 'ARCHIVE_TYPE_UNSPECIFIED');
  static const ArchiveType ARCHIVE_TYPE_ZIP = ArchiveType._(1, _omitEnumNames ? '' : 'ARCHIVE_TYPE_ZIP');
  static const ArchiveType ARCHIVE_TYPE_TAR_BZ2 = ArchiveType._(2, _omitEnumNames ? '' : 'ARCHIVE_TYPE_TAR_BZ2');
  static const ArchiveType ARCHIVE_TYPE_TAR_GZ = ArchiveType._(3, _omitEnumNames ? '' : 'ARCHIVE_TYPE_TAR_GZ');
  static const ArchiveType ARCHIVE_TYPE_TAR_XZ = ArchiveType._(4, _omitEnumNames ? '' : 'ARCHIVE_TYPE_TAR_XZ');

  static const $core.List<ArchiveType> values = <ArchiveType> [
    ARCHIVE_TYPE_UNSPECIFIED,
    ARCHIVE_TYPE_ZIP,
    ARCHIVE_TYPE_TAR_BZ2,
    ARCHIVE_TYPE_TAR_GZ,
    ARCHIVE_TYPE_TAR_XZ,
  ];

  static final $core.Map<$core.int, ArchiveType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ArchiveType? valueOf($core.int value) => _byValue[value];

  const ArchiveType._($core.int v, $core.String n) : super(v, n);
}

class ArchiveStructure extends $pb.ProtobufEnum {
  static const ArchiveStructure ARCHIVE_STRUCTURE_UNSPECIFIED = ArchiveStructure._(0, _omitEnumNames ? '' : 'ARCHIVE_STRUCTURE_UNSPECIFIED');
  static const ArchiveStructure ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED = ArchiveStructure._(1, _omitEnumNames ? '' : 'ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED');
  static const ArchiveStructure ARCHIVE_STRUCTURE_DIRECTORY_BASED = ArchiveStructure._(2, _omitEnumNames ? '' : 'ARCHIVE_STRUCTURE_DIRECTORY_BASED');
  static const ArchiveStructure ARCHIVE_STRUCTURE_NESTED_DIRECTORY = ArchiveStructure._(3, _omitEnumNames ? '' : 'ARCHIVE_STRUCTURE_NESTED_DIRECTORY');
  static const ArchiveStructure ARCHIVE_STRUCTURE_UNKNOWN = ArchiveStructure._(4, _omitEnumNames ? '' : 'ARCHIVE_STRUCTURE_UNKNOWN');

  static const $core.List<ArchiveStructure> values = <ArchiveStructure> [
    ARCHIVE_STRUCTURE_UNSPECIFIED,
    ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED,
    ARCHIVE_STRUCTURE_DIRECTORY_BASED,
    ARCHIVE_STRUCTURE_NESTED_DIRECTORY,
    ARCHIVE_STRUCTURE_UNKNOWN,
  ];

  static final $core.Map<$core.int, ArchiveStructure> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ArchiveStructure? valueOf($core.int value) => _byValue[value];

  const ArchiveStructure._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// High-level artifact classification — what KIND of bundle a model ships as.
/// Distinct from ModelFormat (the on-disk file format) and ArchiveType (the
/// compression flavor). Sources pre-IDL:
///   Swift  ModelTypes.swift:~200            (singleFile, archive, multiFile, custom)
///   Web    types.ts:149                     (SingleFile / Archive / MultiFile / Custom)
///   Kotlin sealed class ModelArtifactType   (SingleFile / Archive / MultiFile / Custom)
/// ---------------------------------------------------------------------------
class ModelArtifactType extends $pb.ProtobufEnum {
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_UNSPECIFIED = ModelArtifactType._(0, _omitEnumNames ? '' : 'MODEL_ARTIFACT_TYPE_UNSPECIFIED');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_SINGLE_FILE = ModelArtifactType._(1, _omitEnumNames ? '' : 'MODEL_ARTIFACT_TYPE_SINGLE_FILE');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE = ModelArtifactType._(2, _omitEnumNames ? '' : 'MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_DIRECTORY = ModelArtifactType._(3, _omitEnumNames ? '' : 'MODEL_ARTIFACT_TYPE_DIRECTORY');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE = ModelArtifactType._(4, _omitEnumNames ? '' : 'MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_CUSTOM = ModelArtifactType._(5, _omitEnumNames ? '' : 'MODEL_ARTIFACT_TYPE_CUSTOM');

  static const $core.List<ModelArtifactType> values = <ModelArtifactType> [
    MODEL_ARTIFACT_TYPE_UNSPECIFIED,
    MODEL_ARTIFACT_TYPE_SINGLE_FILE,
    MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
    MODEL_ARTIFACT_TYPE_DIRECTORY,
    MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE,
    MODEL_ARTIFACT_TYPE_CUSTOM,
  ];

  static final $core.Map<$core.int, ModelArtifactType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelArtifactType? valueOf($core.int value) => _byValue[value];

  const ModelArtifactType._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Model registry lifecycle state. This is durable/catalog state, not a live
/// transfer progress stream. Per-download byte counters and transient progress
/// events stay in download_service.proto.
/// Sources pre-IDL:
///   Web ModelRegistry.ts ManagedModel.status (registered/downloading/downloaded/loading/loaded/error)
///   RN  ModelInfo.isDownloaded/isAvailable and registry query criteria
/// ---------------------------------------------------------------------------
class ModelRegistryStatus extends $pb.ProtobufEnum {
  static const ModelRegistryStatus MODEL_REGISTRY_STATUS_UNSPECIFIED = ModelRegistryStatus._(0, _omitEnumNames ? '' : 'MODEL_REGISTRY_STATUS_UNSPECIFIED');
  static const ModelRegistryStatus MODEL_REGISTRY_STATUS_REGISTERED = ModelRegistryStatus._(1, _omitEnumNames ? '' : 'MODEL_REGISTRY_STATUS_REGISTERED');
  static const ModelRegistryStatus MODEL_REGISTRY_STATUS_DOWNLOADING = ModelRegistryStatus._(2, _omitEnumNames ? '' : 'MODEL_REGISTRY_STATUS_DOWNLOADING');
  static const ModelRegistryStatus MODEL_REGISTRY_STATUS_DOWNLOADED = ModelRegistryStatus._(3, _omitEnumNames ? '' : 'MODEL_REGISTRY_STATUS_DOWNLOADED');
  static const ModelRegistryStatus MODEL_REGISTRY_STATUS_LOADING = ModelRegistryStatus._(4, _omitEnumNames ? '' : 'MODEL_REGISTRY_STATUS_LOADING');
  static const ModelRegistryStatus MODEL_REGISTRY_STATUS_LOADED = ModelRegistryStatus._(5, _omitEnumNames ? '' : 'MODEL_REGISTRY_STATUS_LOADED');
  static const ModelRegistryStatus MODEL_REGISTRY_STATUS_ERROR = ModelRegistryStatus._(6, _omitEnumNames ? '' : 'MODEL_REGISTRY_STATUS_ERROR');

  static const $core.List<ModelRegistryStatus> values = <ModelRegistryStatus> [
    MODEL_REGISTRY_STATUS_UNSPECIFIED,
    MODEL_REGISTRY_STATUS_REGISTERED,
    MODEL_REGISTRY_STATUS_DOWNLOADING,
    MODEL_REGISTRY_STATUS_DOWNLOADED,
    MODEL_REGISTRY_STATUS_LOADING,
    MODEL_REGISTRY_STATUS_LOADED,
    MODEL_REGISTRY_STATUS_ERROR,
  ];

  static final $core.Map<$core.int, ModelRegistryStatus> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelRegistryStatus? valueOf($core.int value) => _byValue[value];

  const ModelRegistryStatus._($core.int v, $core.String n) : super(v, n);
}

class ModelQuerySortField extends $pb.ProtobufEnum {
  static const ModelQuerySortField MODEL_QUERY_SORT_FIELD_UNSPECIFIED = ModelQuerySortField._(0, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_FIELD_UNSPECIFIED');
  static const ModelQuerySortField MODEL_QUERY_SORT_FIELD_NAME = ModelQuerySortField._(1, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_FIELD_NAME');
  static const ModelQuerySortField MODEL_QUERY_SORT_FIELD_CREATED_AT_UNIX_MS = ModelQuerySortField._(2, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_FIELD_CREATED_AT_UNIX_MS');
  static const ModelQuerySortField MODEL_QUERY_SORT_FIELD_UPDATED_AT_UNIX_MS = ModelQuerySortField._(3, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_FIELD_UPDATED_AT_UNIX_MS');
  static const ModelQuerySortField MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES = ModelQuerySortField._(4, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES');
  static const ModelQuerySortField MODEL_QUERY_SORT_FIELD_LAST_USED_AT_UNIX_MS = ModelQuerySortField._(5, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_FIELD_LAST_USED_AT_UNIX_MS');
  static const ModelQuerySortField MODEL_QUERY_SORT_FIELD_USAGE_COUNT = ModelQuerySortField._(6, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_FIELD_USAGE_COUNT');

  static const $core.List<ModelQuerySortField> values = <ModelQuerySortField> [
    MODEL_QUERY_SORT_FIELD_UNSPECIFIED,
    MODEL_QUERY_SORT_FIELD_NAME,
    MODEL_QUERY_SORT_FIELD_CREATED_AT_UNIX_MS,
    MODEL_QUERY_SORT_FIELD_UPDATED_AT_UNIX_MS,
    MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES,
    MODEL_QUERY_SORT_FIELD_LAST_USED_AT_UNIX_MS,
    MODEL_QUERY_SORT_FIELD_USAGE_COUNT,
  ];

  static final $core.Map<$core.int, ModelQuerySortField> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelQuerySortField? valueOf($core.int value) => _byValue[value];

  const ModelQuerySortField._($core.int v, $core.String n) : super(v, n);
}

class ModelQuerySortOrder extends $pb.ProtobufEnum {
  static const ModelQuerySortOrder MODEL_QUERY_SORT_ORDER_UNSPECIFIED = ModelQuerySortOrder._(0, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_ORDER_UNSPECIFIED');
  static const ModelQuerySortOrder MODEL_QUERY_SORT_ORDER_ASCENDING = ModelQuerySortOrder._(1, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_ORDER_ASCENDING');
  static const ModelQuerySortOrder MODEL_QUERY_SORT_ORDER_DESCENDING = ModelQuerySortOrder._(2, _omitEnumNames ? '' : 'MODEL_QUERY_SORT_ORDER_DESCENDING');

  static const $core.List<ModelQuerySortOrder> values = <ModelQuerySortOrder> [
    MODEL_QUERY_SORT_ORDER_UNSPECIFIED,
    MODEL_QUERY_SORT_ORDER_ASCENDING,
    MODEL_QUERY_SORT_ORDER_DESCENDING,
  ];

  static final $core.Map<$core.int, ModelQuerySortOrder> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelQuerySortOrder? valueOf($core.int value) => _byValue[value];

  const ModelQuerySortOrder._($core.int v, $core.String n) : super(v, n);
}

/// Role of a file inside a single/multi-file artifact. The generic COMPANION
/// role covers arbitrary sidecars; specific roles document common public
/// catalog files such as VLM mmproj files and tokenizer/config assets.
class ModelFileRole extends $pb.ProtobufEnum {
  static const ModelFileRole MODEL_FILE_ROLE_UNSPECIFIED = ModelFileRole._(0, _omitEnumNames ? '' : 'MODEL_FILE_ROLE_UNSPECIFIED');
  static const ModelFileRole MODEL_FILE_ROLE_PRIMARY_MODEL = ModelFileRole._(1, _omitEnumNames ? '' : 'MODEL_FILE_ROLE_PRIMARY_MODEL');
  static const ModelFileRole MODEL_FILE_ROLE_COMPANION = ModelFileRole._(2, _omitEnumNames ? '' : 'MODEL_FILE_ROLE_COMPANION');
  static const ModelFileRole MODEL_FILE_ROLE_VISION_PROJECTOR = ModelFileRole._(3, _omitEnumNames ? '' : 'MODEL_FILE_ROLE_VISION_PROJECTOR');
  static const ModelFileRole MODEL_FILE_ROLE_TOKENIZER = ModelFileRole._(4, _omitEnumNames ? '' : 'MODEL_FILE_ROLE_TOKENIZER');
  static const ModelFileRole MODEL_FILE_ROLE_CONFIG = ModelFileRole._(5, _omitEnumNames ? '' : 'MODEL_FILE_ROLE_CONFIG');
  static const ModelFileRole MODEL_FILE_ROLE_VOCABULARY = ModelFileRole._(6, _omitEnumNames ? '' : 'MODEL_FILE_ROLE_VOCABULARY');
  static const ModelFileRole MODEL_FILE_ROLE_MERGES = ModelFileRole._(7, _omitEnumNames ? '' : 'MODEL_FILE_ROLE_MERGES');
  static const ModelFileRole MODEL_FILE_ROLE_LABELS = ModelFileRole._(8, _omitEnumNames ? '' : 'MODEL_FILE_ROLE_LABELS');

  static const $core.List<ModelFileRole> values = <ModelFileRole> [
    MODEL_FILE_ROLE_UNSPECIFIED,
    MODEL_FILE_ROLE_PRIMARY_MODEL,
    MODEL_FILE_ROLE_COMPANION,
    MODEL_FILE_ROLE_VISION_PROJECTOR,
    MODEL_FILE_ROLE_TOKENIZER,
    MODEL_FILE_ROLE_CONFIG,
    MODEL_FILE_ROLE_VOCABULARY,
    MODEL_FILE_ROLE_MERGES,
    MODEL_FILE_ROLE_LABELS,
  ];

  static final $core.Map<$core.int, ModelFileRole> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelFileRole? valueOf($core.int value) => _byValue[value];

  const ModelFileRole._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Hardware acceleration preference for inference. Sources pre-IDL:
///   Web    enums.ts:165   (Auto / WebGPU / CPU)
///   Swift  extensions     (CPU / GPU / NPU / Metal)
///   Kotlin enum           (CPU / GPU / NPU / Vulkan)
/// Canonicalized union below.
/// ---------------------------------------------------------------------------
class AccelerationPreference extends $pb.ProtobufEnum {
  static const AccelerationPreference ACCELERATION_PREFERENCE_UNSPECIFIED = AccelerationPreference._(0, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_UNSPECIFIED');
  static const AccelerationPreference ACCELERATION_PREFERENCE_AUTO = AccelerationPreference._(1, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_AUTO');
  static const AccelerationPreference ACCELERATION_PREFERENCE_CPU = AccelerationPreference._(2, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_CPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_GPU = AccelerationPreference._(3, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_GPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_NPU = AccelerationPreference._(4, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_NPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_WEBGPU = AccelerationPreference._(5, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_WEBGPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_METAL = AccelerationPreference._(6, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_METAL');
  static const AccelerationPreference ACCELERATION_PREFERENCE_VULKAN = AccelerationPreference._(7, _omitEnumNames ? '' : 'ACCELERATION_PREFERENCE_VULKAN');

  static const $core.List<AccelerationPreference> values = <AccelerationPreference> [
    ACCELERATION_PREFERENCE_UNSPECIFIED,
    ACCELERATION_PREFERENCE_AUTO,
    ACCELERATION_PREFERENCE_CPU,
    ACCELERATION_PREFERENCE_GPU,
    ACCELERATION_PREFERENCE_NPU,
    ACCELERATION_PREFERENCE_WEBGPU,
    ACCELERATION_PREFERENCE_METAL,
    ACCELERATION_PREFERENCE_VULKAN,
  ];

  static final $core.Map<$core.int, AccelerationPreference> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AccelerationPreference? valueOf($core.int value) => _byValue[value];

  const AccelerationPreference._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Routing policy for hybrid (on-device vs cloud) inference. Sources pre-IDL:
///   Web    enums.ts (RoutingPolicy)
///          OnDevicePreferred / CloudPreferred / OnDeviceOnly / CloudOnly /
///          Hybrid / CostOptimized / LatencyOptimized / PrivacyOptimized
///   Swift  extensions (RoutingPolicy)
/// Canonical short-form below; specific PreferLocal/PreferCloud cover the
/// "preferred" cases, MANUAL covers explicit user override.
/// ---------------------------------------------------------------------------
class RoutingPolicy extends $pb.ProtobufEnum {
  static const RoutingPolicy ROUTING_POLICY_UNSPECIFIED = RoutingPolicy._(0, _omitEnumNames ? '' : 'ROUTING_POLICY_UNSPECIFIED');
  static const RoutingPolicy ROUTING_POLICY_PREFER_LOCAL = RoutingPolicy._(1, _omitEnumNames ? '' : 'ROUTING_POLICY_PREFER_LOCAL');
  static const RoutingPolicy ROUTING_POLICY_PREFER_CLOUD = RoutingPolicy._(2, _omitEnumNames ? '' : 'ROUTING_POLICY_PREFER_CLOUD');
  static const RoutingPolicy ROUTING_POLICY_COST_OPTIMIZED = RoutingPolicy._(3, _omitEnumNames ? '' : 'ROUTING_POLICY_COST_OPTIMIZED');
  static const RoutingPolicy ROUTING_POLICY_LATENCY_OPTIMIZED = RoutingPolicy._(4, _omitEnumNames ? '' : 'ROUTING_POLICY_LATENCY_OPTIMIZED');
  static const RoutingPolicy ROUTING_POLICY_MANUAL = RoutingPolicy._(5, _omitEnumNames ? '' : 'ROUTING_POLICY_MANUAL');

  static const $core.List<RoutingPolicy> values = <RoutingPolicy> [
    ROUTING_POLICY_UNSPECIFIED,
    ROUTING_POLICY_PREFER_LOCAL,
    ROUTING_POLICY_PREFER_CLOUD,
    ROUTING_POLICY_COST_OPTIMIZED,
    ROUTING_POLICY_LATENCY_OPTIMIZED,
    ROUTING_POLICY_MANUAL,
  ];

  static final $core.Map<$core.int, RoutingPolicy> _byValue = $pb.ProtobufEnum.initByValue(values);
  static RoutingPolicy? valueOf($core.int value) => _byValue[value];

  const RoutingPolicy._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
