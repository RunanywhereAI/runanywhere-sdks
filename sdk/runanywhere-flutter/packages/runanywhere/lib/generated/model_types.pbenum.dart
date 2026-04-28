///
//  Generated code. Do not modify.
//  source: model_types.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class AudioFormat extends $pb.ProtobufEnum {
  static const AudioFormat AUDIO_FORMAT_UNSPECIFIED = AudioFormat._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_UNSPECIFIED');
  static const AudioFormat AUDIO_FORMAT_PCM = AudioFormat._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_PCM');
  static const AudioFormat AUDIO_FORMAT_WAV = AudioFormat._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_WAV');
  static const AudioFormat AUDIO_FORMAT_MP3 = AudioFormat._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_MP3');
  static const AudioFormat AUDIO_FORMAT_OPUS = AudioFormat._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_OPUS');
  static const AudioFormat AUDIO_FORMAT_AAC = AudioFormat._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_AAC');
  static const AudioFormat AUDIO_FORMAT_FLAC = AudioFormat._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_FLAC');
  static const AudioFormat AUDIO_FORMAT_OGG = AudioFormat._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_OGG');
  static const AudioFormat AUDIO_FORMAT_M4A = AudioFormat._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_M4A');
  static const AudioFormat AUDIO_FORMAT_PCM_S16LE = AudioFormat._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'AUDIO_FORMAT_PCM_S16LE');

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

class ModelFormat extends $pb.ProtobufEnum {
  static const ModelFormat MODEL_FORMAT_UNSPECIFIED = ModelFormat._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_UNSPECIFIED');
  static const ModelFormat MODEL_FORMAT_GGUF = ModelFormat._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_GGUF');
  static const ModelFormat MODEL_FORMAT_GGML = ModelFormat._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_GGML');
  static const ModelFormat MODEL_FORMAT_ONNX = ModelFormat._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_ONNX');
  static const ModelFormat MODEL_FORMAT_ORT = ModelFormat._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_ORT');
  static const ModelFormat MODEL_FORMAT_BIN = ModelFormat._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_BIN');
  static const ModelFormat MODEL_FORMAT_COREML = ModelFormat._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_COREML');
  static const ModelFormat MODEL_FORMAT_MLMODEL = ModelFormat._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_MLMODEL');
  static const ModelFormat MODEL_FORMAT_MLPACKAGE = ModelFormat._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_MLPACKAGE');
  static const ModelFormat MODEL_FORMAT_TFLITE = ModelFormat._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_TFLITE');
  static const ModelFormat MODEL_FORMAT_SAFETENSORS = ModelFormat._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_SAFETENSORS');
  static const ModelFormat MODEL_FORMAT_QNN_CONTEXT = ModelFormat._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_QNN_CONTEXT');
  static const ModelFormat MODEL_FORMAT_ZIP = ModelFormat._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_ZIP');
  static const ModelFormat MODEL_FORMAT_FOLDER = ModelFormat._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_FOLDER');
  static const ModelFormat MODEL_FORMAT_PROPRIETARY = ModelFormat._(14, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_PROPRIETARY');
  static const ModelFormat MODEL_FORMAT_UNKNOWN = ModelFormat._(15, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_FORMAT_UNKNOWN');

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

class InferenceFramework extends $pb.ProtobufEnum {
  static const InferenceFramework INFERENCE_FRAMEWORK_UNSPECIFIED = InferenceFramework._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_UNSPECIFIED');
  static const InferenceFramework INFERENCE_FRAMEWORK_ONNX = InferenceFramework._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_ONNX');
  static const InferenceFramework INFERENCE_FRAMEWORK_LLAMA_CPP = InferenceFramework._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_LLAMA_CPP');
  static const InferenceFramework INFERENCE_FRAMEWORK_FOUNDATION_MODELS = InferenceFramework._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_FOUNDATION_MODELS');
  static const InferenceFramework INFERENCE_FRAMEWORK_SYSTEM_TTS = InferenceFramework._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_SYSTEM_TTS');
  static const InferenceFramework INFERENCE_FRAMEWORK_FLUID_AUDIO = InferenceFramework._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_FLUID_AUDIO');
  static const InferenceFramework INFERENCE_FRAMEWORK_COREML = InferenceFramework._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_COREML');
  static const InferenceFramework INFERENCE_FRAMEWORK_MLX = InferenceFramework._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_MLX');
  static const InferenceFramework INFERENCE_FRAMEWORK_WHISPERKIT_COREML = InferenceFramework._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_WHISPERKIT_COREML');
  static const InferenceFramework INFERENCE_FRAMEWORK_METALRT = InferenceFramework._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_METALRT');
  static const InferenceFramework INFERENCE_FRAMEWORK_GENIE = InferenceFramework._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_GENIE');
  static const InferenceFramework INFERENCE_FRAMEWORK_TFLITE = InferenceFramework._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_TFLITE');
  static const InferenceFramework INFERENCE_FRAMEWORK_EXECUTORCH = InferenceFramework._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_EXECUTORCH');
  static const InferenceFramework INFERENCE_FRAMEWORK_MEDIAPIPE = InferenceFramework._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_MEDIAPIPE');
  static const InferenceFramework INFERENCE_FRAMEWORK_MLC = InferenceFramework._(14, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_MLC');
  static const InferenceFramework INFERENCE_FRAMEWORK_PICO_LLM = InferenceFramework._(15, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_PICO_LLM');
  static const InferenceFramework INFERENCE_FRAMEWORK_PIPER_TTS = InferenceFramework._(16, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_PIPER_TTS');
  static const InferenceFramework INFERENCE_FRAMEWORK_WHISPERKIT = InferenceFramework._(17, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_WHISPERKIT');
  static const InferenceFramework INFERENCE_FRAMEWORK_OPENAI_WHISPER = InferenceFramework._(18, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_OPENAI_WHISPER');
  static const InferenceFramework INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS = InferenceFramework._(19, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS');
  static const InferenceFramework INFERENCE_FRAMEWORK_BUILT_IN = InferenceFramework._(20, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_BUILT_IN');
  static const InferenceFramework INFERENCE_FRAMEWORK_NONE = InferenceFramework._(21, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_NONE');
  static const InferenceFramework INFERENCE_FRAMEWORK_UNKNOWN = InferenceFramework._(22, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_UNKNOWN');
  static const InferenceFramework INFERENCE_FRAMEWORK_SHERPA = InferenceFramework._(23, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INFERENCE_FRAMEWORK_SHERPA');

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

class ModelCategory extends $pb.ProtobufEnum {
  static const ModelCategory MODEL_CATEGORY_UNSPECIFIED = ModelCategory._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_UNSPECIFIED');
  static const ModelCategory MODEL_CATEGORY_LANGUAGE = ModelCategory._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_LANGUAGE');
  static const ModelCategory MODEL_CATEGORY_SPEECH_RECOGNITION = ModelCategory._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_SPEECH_RECOGNITION');
  static const ModelCategory MODEL_CATEGORY_SPEECH_SYNTHESIS = ModelCategory._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_SPEECH_SYNTHESIS');
  static const ModelCategory MODEL_CATEGORY_VISION = ModelCategory._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_VISION');
  static const ModelCategory MODEL_CATEGORY_IMAGE_GENERATION = ModelCategory._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_IMAGE_GENERATION');
  static const ModelCategory MODEL_CATEGORY_MULTIMODAL = ModelCategory._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_MULTIMODAL');
  static const ModelCategory MODEL_CATEGORY_AUDIO = ModelCategory._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_AUDIO');
  static const ModelCategory MODEL_CATEGORY_EMBEDDING = ModelCategory._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_EMBEDDING');
  static const ModelCategory MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION = ModelCategory._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION');

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

class SDKEnvironment extends $pb.ProtobufEnum {
  static const SDKEnvironment SDK_ENVIRONMENT_UNSPECIFIED = SDKEnvironment._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_ENVIRONMENT_UNSPECIFIED');
  static const SDKEnvironment SDK_ENVIRONMENT_DEVELOPMENT = SDKEnvironment._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_ENVIRONMENT_DEVELOPMENT');
  static const SDKEnvironment SDK_ENVIRONMENT_STAGING = SDKEnvironment._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_ENVIRONMENT_STAGING');
  static const SDKEnvironment SDK_ENVIRONMENT_PRODUCTION = SDKEnvironment._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_ENVIRONMENT_PRODUCTION');

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

class ModelSource extends $pb.ProtobufEnum {
  static const ModelSource MODEL_SOURCE_UNSPECIFIED = ModelSource._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_SOURCE_UNSPECIFIED');
  static const ModelSource MODEL_SOURCE_REMOTE = ModelSource._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_SOURCE_REMOTE');
  static const ModelSource MODEL_SOURCE_LOCAL = ModelSource._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_SOURCE_LOCAL');

  static const $core.List<ModelSource> values = <ModelSource> [
    MODEL_SOURCE_UNSPECIFIED,
    MODEL_SOURCE_REMOTE,
    MODEL_SOURCE_LOCAL,
  ];

  static final $core.Map<$core.int, ModelSource> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelSource? valueOf($core.int value) => _byValue[value];

  const ModelSource._($core.int v, $core.String n) : super(v, n);
}

class ArchiveType extends $pb.ProtobufEnum {
  static const ArchiveType ARCHIVE_TYPE_UNSPECIFIED = ArchiveType._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_TYPE_UNSPECIFIED');
  static const ArchiveType ARCHIVE_TYPE_ZIP = ArchiveType._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_TYPE_ZIP');
  static const ArchiveType ARCHIVE_TYPE_TAR_BZ2 = ArchiveType._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_TYPE_TAR_BZ2');
  static const ArchiveType ARCHIVE_TYPE_TAR_GZ = ArchiveType._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_TYPE_TAR_GZ');
  static const ArchiveType ARCHIVE_TYPE_TAR_XZ = ArchiveType._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_TYPE_TAR_XZ');

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
  static const ArchiveStructure ARCHIVE_STRUCTURE_UNSPECIFIED = ArchiveStructure._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_STRUCTURE_UNSPECIFIED');
  static const ArchiveStructure ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED = ArchiveStructure._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED');
  static const ArchiveStructure ARCHIVE_STRUCTURE_DIRECTORY_BASED = ArchiveStructure._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_STRUCTURE_DIRECTORY_BASED');
  static const ArchiveStructure ARCHIVE_STRUCTURE_NESTED_DIRECTORY = ArchiveStructure._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_STRUCTURE_NESTED_DIRECTORY');
  static const ArchiveStructure ARCHIVE_STRUCTURE_UNKNOWN = ArchiveStructure._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ARCHIVE_STRUCTURE_UNKNOWN');

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

class ModelArtifactType extends $pb.ProtobufEnum {
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_UNSPECIFIED = ModelArtifactType._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_ARTIFACT_TYPE_UNSPECIFIED');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_SINGLE_FILE = ModelArtifactType._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_ARTIFACT_TYPE_SINGLE_FILE');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE = ModelArtifactType._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_DIRECTORY = ModelArtifactType._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_ARTIFACT_TYPE_DIRECTORY');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE = ModelArtifactType._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE');
  static const ModelArtifactType MODEL_ARTIFACT_TYPE_CUSTOM = ModelArtifactType._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_ARTIFACT_TYPE_CUSTOM');

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

class AccelerationPreference extends $pb.ProtobufEnum {
  static const AccelerationPreference ACCELERATION_PREFERENCE_UNSPECIFIED = AccelerationPreference._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATION_PREFERENCE_UNSPECIFIED');
  static const AccelerationPreference ACCELERATION_PREFERENCE_AUTO = AccelerationPreference._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATION_PREFERENCE_AUTO');
  static const AccelerationPreference ACCELERATION_PREFERENCE_CPU = AccelerationPreference._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATION_PREFERENCE_CPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_GPU = AccelerationPreference._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATION_PREFERENCE_GPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_NPU = AccelerationPreference._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATION_PREFERENCE_NPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_WEBGPU = AccelerationPreference._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATION_PREFERENCE_WEBGPU');
  static const AccelerationPreference ACCELERATION_PREFERENCE_METAL = AccelerationPreference._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATION_PREFERENCE_METAL');
  static const AccelerationPreference ACCELERATION_PREFERENCE_VULKAN = AccelerationPreference._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ACCELERATION_PREFERENCE_VULKAN');

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

class RoutingPolicy extends $pb.ProtobufEnum {
  static const RoutingPolicy ROUTING_POLICY_UNSPECIFIED = RoutingPolicy._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ROUTING_POLICY_UNSPECIFIED');
  static const RoutingPolicy ROUTING_POLICY_PREFER_LOCAL = RoutingPolicy._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ROUTING_POLICY_PREFER_LOCAL');
  static const RoutingPolicy ROUTING_POLICY_PREFER_CLOUD = RoutingPolicy._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ROUTING_POLICY_PREFER_CLOUD');
  static const RoutingPolicy ROUTING_POLICY_COST_OPTIMIZED = RoutingPolicy._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ROUTING_POLICY_COST_OPTIMIZED');
  static const RoutingPolicy ROUTING_POLICY_LATENCY_OPTIMIZED = RoutingPolicy._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ROUTING_POLICY_LATENCY_OPTIMIZED');
  static const RoutingPolicy ROUTING_POLICY_MANUAL = RoutingPolicy._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'ROUTING_POLICY_MANUAL');

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

