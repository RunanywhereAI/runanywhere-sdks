///
//  Generated code. Do not modify.
//  source: model_types.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use audioFormatDescriptor instead')
const AudioFormat$json = const {
  '1': 'AudioFormat',
  '2': const [
    const {'1': 'AUDIO_FORMAT_UNSPECIFIED', '2': 0},
    const {'1': 'AUDIO_FORMAT_PCM', '2': 1},
    const {'1': 'AUDIO_FORMAT_WAV', '2': 2},
    const {'1': 'AUDIO_FORMAT_MP3', '2': 3},
    const {'1': 'AUDIO_FORMAT_OPUS', '2': 4},
    const {'1': 'AUDIO_FORMAT_AAC', '2': 5},
    const {'1': 'AUDIO_FORMAT_FLAC', '2': 6},
    const {'1': 'AUDIO_FORMAT_OGG', '2': 7},
    const {'1': 'AUDIO_FORMAT_M4A', '2': 8},
    const {'1': 'AUDIO_FORMAT_PCM_S16LE', '2': 9},
  ],
};

/// Descriptor for `AudioFormat`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List audioFormatDescriptor = $convert.base64Decode('CgtBdWRpb0Zvcm1hdBIcChhBVURJT19GT1JNQVRfVU5TUEVDSUZJRUQQABIUChBBVURJT19GT1JNQVRfUENNEAESFAoQQVVESU9fRk9STUFUX1dBVhACEhQKEEFVRElPX0ZPUk1BVF9NUDMQAxIVChFBVURJT19GT1JNQVRfT1BVUxAEEhQKEEFVRElPX0ZPUk1BVF9BQUMQBRIVChFBVURJT19GT1JNQVRfRkxBQxAGEhQKEEFVRElPX0ZPUk1BVF9PR0cQBxIUChBBVURJT19GT1JNQVRfTTRBEAgSGgoWQVVESU9fRk9STUFUX1BDTV9TMTZMRRAJ');
@$core.Deprecated('Use modelFormatDescriptor instead')
const ModelFormat$json = const {
  '1': 'ModelFormat',
  '2': const [
    const {'1': 'MODEL_FORMAT_UNSPECIFIED', '2': 0},
    const {'1': 'MODEL_FORMAT_GGUF', '2': 1},
    const {'1': 'MODEL_FORMAT_GGML', '2': 2},
    const {'1': 'MODEL_FORMAT_ONNX', '2': 3},
    const {'1': 'MODEL_FORMAT_ORT', '2': 4},
    const {'1': 'MODEL_FORMAT_BIN', '2': 5},
    const {'1': 'MODEL_FORMAT_COREML', '2': 6},
    const {'1': 'MODEL_FORMAT_MLMODEL', '2': 7},
    const {'1': 'MODEL_FORMAT_MLPACKAGE', '2': 8},
    const {'1': 'MODEL_FORMAT_TFLITE', '2': 9},
    const {'1': 'MODEL_FORMAT_SAFETENSORS', '2': 10},
    const {'1': 'MODEL_FORMAT_QNN_CONTEXT', '2': 11},
    const {'1': 'MODEL_FORMAT_ZIP', '2': 12},
    const {'1': 'MODEL_FORMAT_FOLDER', '2': 13},
    const {'1': 'MODEL_FORMAT_PROPRIETARY', '2': 14},
    const {'1': 'MODEL_FORMAT_UNKNOWN', '2': 15},
  ],
};

/// Descriptor for `ModelFormat`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelFormatDescriptor = $convert.base64Decode('CgtNb2RlbEZvcm1hdBIcChhNT0RFTF9GT1JNQVRfVU5TUEVDSUZJRUQQABIVChFNT0RFTF9GT1JNQVRfR0dVRhABEhUKEU1PREVMX0ZPUk1BVF9HR01MEAISFQoRTU9ERUxfRk9STUFUX09OTlgQAxIUChBNT0RFTF9GT1JNQVRfT1JUEAQSFAoQTU9ERUxfRk9STUFUX0JJThAFEhcKE01PREVMX0ZPUk1BVF9DT1JFTUwQBhIYChRNT0RFTF9GT1JNQVRfTUxNT0RFTBAHEhoKFk1PREVMX0ZPUk1BVF9NTFBBQ0tBR0UQCBIXChNNT0RFTF9GT1JNQVRfVEZMSVRFEAkSHAoYTU9ERUxfRk9STUFUX1NBRkVURU5TT1JTEAoSHAoYTU9ERUxfRk9STUFUX1FOTl9DT05URVhUEAsSFAoQTU9ERUxfRk9STUFUX1pJUBAMEhcKE01PREVMX0ZPUk1BVF9GT0xERVIQDRIcChhNT0RFTF9GT1JNQVRfUFJPUFJJRVRBUlkQDhIYChRNT0RFTF9GT1JNQVRfVU5LTk9XThAP');
@$core.Deprecated('Use inferenceFrameworkDescriptor instead')
const InferenceFramework$json = const {
  '1': 'InferenceFramework',
  '2': const [
    const {'1': 'INFERENCE_FRAMEWORK_UNSPECIFIED', '2': 0},
    const {'1': 'INFERENCE_FRAMEWORK_ONNX', '2': 1},
    const {'1': 'INFERENCE_FRAMEWORK_LLAMA_CPP', '2': 2},
    const {'1': 'INFERENCE_FRAMEWORK_FOUNDATION_MODELS', '2': 3},
    const {'1': 'INFERENCE_FRAMEWORK_SYSTEM_TTS', '2': 4},
    const {'1': 'INFERENCE_FRAMEWORK_FLUID_AUDIO', '2': 5},
    const {'1': 'INFERENCE_FRAMEWORK_COREML', '2': 6},
    const {'1': 'INFERENCE_FRAMEWORK_MLX', '2': 7},
    const {'1': 'INFERENCE_FRAMEWORK_WHISPERKIT_COREML', '2': 8},
    const {'1': 'INFERENCE_FRAMEWORK_METALRT', '2': 9},
    const {'1': 'INFERENCE_FRAMEWORK_GENIE', '2': 10},
    const {'1': 'INFERENCE_FRAMEWORK_TFLITE', '2': 11},
    const {'1': 'INFERENCE_FRAMEWORK_EXECUTORCH', '2': 12},
    const {'1': 'INFERENCE_FRAMEWORK_MEDIAPIPE', '2': 13},
    const {'1': 'INFERENCE_FRAMEWORK_MLC', '2': 14},
    const {'1': 'INFERENCE_FRAMEWORK_PICO_LLM', '2': 15},
    const {'1': 'INFERENCE_FRAMEWORK_PIPER_TTS', '2': 16},
    const {'1': 'INFERENCE_FRAMEWORK_WHISPERKIT', '2': 17},
    const {'1': 'INFERENCE_FRAMEWORK_OPENAI_WHISPER', '2': 18},
    const {'1': 'INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS', '2': 19},
    const {'1': 'INFERENCE_FRAMEWORK_BUILT_IN', '2': 20},
    const {'1': 'INFERENCE_FRAMEWORK_NONE', '2': 21},
    const {'1': 'INFERENCE_FRAMEWORK_UNKNOWN', '2': 22},
    const {'1': 'INFERENCE_FRAMEWORK_SHERPA', '2': 23},
  ],
};

/// Descriptor for `InferenceFramework`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List inferenceFrameworkDescriptor = $convert.base64Decode('ChJJbmZlcmVuY2VGcmFtZXdvcmsSIwofSU5GRVJFTkNFX0ZSQU1FV09SS19VTlNQRUNJRklFRBAAEhwKGElORkVSRU5DRV9GUkFNRVdPUktfT05OWBABEiEKHUlORkVSRU5DRV9GUkFNRVdPUktfTExBTUFfQ1BQEAISKQolSU5GRVJFTkNFX0ZSQU1FV09SS19GT1VOREFUSU9OX01PREVMUxADEiIKHklORkVSRU5DRV9GUkFNRVdPUktfU1lTVEVNX1RUUxAEEiMKH0lORkVSRU5DRV9GUkFNRVdPUktfRkxVSURfQVVESU8QBRIeChpJTkZFUkVOQ0VfRlJBTUVXT1JLX0NPUkVNTBAGEhsKF0lORkVSRU5DRV9GUkFNRVdPUktfTUxYEAcSKQolSU5GRVJFTkNFX0ZSQU1FV09SS19XSElTUEVSS0lUX0NPUkVNTBAIEh8KG0lORkVSRU5DRV9GUkFNRVdPUktfTUVUQUxSVBAJEh0KGUlORkVSRU5DRV9GUkFNRVdPUktfR0VOSUUQChIeChpJTkZFUkVOQ0VfRlJBTUVXT1JLX1RGTElURRALEiIKHklORkVSRU5DRV9GUkFNRVdPUktfRVhFQ1VUT1JDSBAMEiEKHUlORkVSRU5DRV9GUkFNRVdPUktfTUVESUFQSVBFEA0SGwoXSU5GRVJFTkNFX0ZSQU1FV09SS19NTEMQDhIgChxJTkZFUkVOQ0VfRlJBTUVXT1JLX1BJQ09fTExNEA8SIQodSU5GRVJFTkNFX0ZSQU1FV09SS19QSVBFUl9UVFMQEBIiCh5JTkZFUkVOQ0VfRlJBTUVXT1JLX1dISVNQRVJLSVQQERImCiJJTkZFUkVOQ0VfRlJBTUVXT1JLX09QRU5BSV9XSElTUEVSEBISKgomSU5GRVJFTkNFX0ZSQU1FV09SS19TV0lGVF9UUkFOU0ZPUk1FUlMQExIgChxJTkZFUkVOQ0VfRlJBTUVXT1JLX0JVSUxUX0lOEBQSHAoYSU5GRVJFTkNFX0ZSQU1FV09SS19OT05FEBUSHwobSU5GRVJFTkNFX0ZSQU1FV09SS19VTktOT1dOEBYSHgoaSU5GRVJFTkNFX0ZSQU1FV09SS19TSEVSUEEQFw==');
@$core.Deprecated('Use modelCategoryDescriptor instead')
const ModelCategory$json = const {
  '1': 'ModelCategory',
  '2': const [
    const {'1': 'MODEL_CATEGORY_UNSPECIFIED', '2': 0},
    const {'1': 'MODEL_CATEGORY_LANGUAGE', '2': 1},
    const {'1': 'MODEL_CATEGORY_SPEECH_RECOGNITION', '2': 2},
    const {'1': 'MODEL_CATEGORY_SPEECH_SYNTHESIS', '2': 3},
    const {'1': 'MODEL_CATEGORY_VISION', '2': 4},
    const {'1': 'MODEL_CATEGORY_IMAGE_GENERATION', '2': 5},
    const {'1': 'MODEL_CATEGORY_MULTIMODAL', '2': 6},
    const {'1': 'MODEL_CATEGORY_AUDIO', '2': 7},
    const {'1': 'MODEL_CATEGORY_EMBEDDING', '2': 8},
    const {'1': 'MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION', '2': 9},
  ],
};

/// Descriptor for `ModelCategory`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelCategoryDescriptor = $convert.base64Decode('Cg1Nb2RlbENhdGVnb3J5Eh4KGk1PREVMX0NBVEVHT1JZX1VOU1BFQ0lGSUVEEAASGwoXTU9ERUxfQ0FURUdPUllfTEFOR1VBR0UQARIlCiFNT0RFTF9DQVRFR09SWV9TUEVFQ0hfUkVDT0dOSVRJT04QAhIjCh9NT0RFTF9DQVRFR09SWV9TUEVFQ0hfU1lOVEhFU0lTEAMSGQoVTU9ERUxfQ0FURUdPUllfVklTSU9OEAQSIwofTU9ERUxfQ0FURUdPUllfSU1BR0VfR0VORVJBVElPThAFEh0KGU1PREVMX0NBVEVHT1JZX01VTFRJTU9EQUwQBhIYChRNT0RFTF9DQVRFR09SWV9BVURJTxAHEhwKGE1PREVMX0NBVEVHT1JZX0VNQkVERElORxAIEisKJ01PREVMX0NBVEVHT1JZX1ZPSUNFX0FDVElWSVRZX0RFVEVDVElPThAJ');
@$core.Deprecated('Use sDKEnvironmentDescriptor instead')
const SDKEnvironment$json = const {
  '1': 'SDKEnvironment',
  '2': const [
    const {'1': 'SDK_ENVIRONMENT_UNSPECIFIED', '2': 0},
    const {'1': 'SDK_ENVIRONMENT_DEVELOPMENT', '2': 1},
    const {'1': 'SDK_ENVIRONMENT_STAGING', '2': 2},
    const {'1': 'SDK_ENVIRONMENT_PRODUCTION', '2': 3},
  ],
};

/// Descriptor for `SDKEnvironment`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sDKEnvironmentDescriptor = $convert.base64Decode('Cg5TREtFbnZpcm9ubWVudBIfChtTREtfRU5WSVJPTk1FTlRfVU5TUEVDSUZJRUQQABIfChtTREtfRU5WSVJPTk1FTlRfREVWRUxPUE1FTlQQARIbChdTREtfRU5WSVJPTk1FTlRfU1RBR0lORxACEh4KGlNES19FTlZJUk9OTUVOVF9QUk9EVUNUSU9OEAM=');
@$core.Deprecated('Use modelSourceDescriptor instead')
const ModelSource$json = const {
  '1': 'ModelSource',
  '2': const [
    const {'1': 'MODEL_SOURCE_UNSPECIFIED', '2': 0},
    const {'1': 'MODEL_SOURCE_REMOTE', '2': 1},
    const {'1': 'MODEL_SOURCE_LOCAL', '2': 2},
  ],
};

/// Descriptor for `ModelSource`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelSourceDescriptor = $convert.base64Decode('CgtNb2RlbFNvdXJjZRIcChhNT0RFTF9TT1VSQ0VfVU5TUEVDSUZJRUQQABIXChNNT0RFTF9TT1VSQ0VfUkVNT1RFEAESFgoSTU9ERUxfU09VUkNFX0xPQ0FMEAI=');
@$core.Deprecated('Use archiveTypeDescriptor instead')
const ArchiveType$json = const {
  '1': 'ArchiveType',
  '2': const [
    const {'1': 'ARCHIVE_TYPE_UNSPECIFIED', '2': 0},
    const {'1': 'ARCHIVE_TYPE_ZIP', '2': 1},
    const {'1': 'ARCHIVE_TYPE_TAR_BZ2', '2': 2},
    const {'1': 'ARCHIVE_TYPE_TAR_GZ', '2': 3},
    const {'1': 'ARCHIVE_TYPE_TAR_XZ', '2': 4},
  ],
};

/// Descriptor for `ArchiveType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List archiveTypeDescriptor = $convert.base64Decode('CgtBcmNoaXZlVHlwZRIcChhBUkNISVZFX1RZUEVfVU5TUEVDSUZJRUQQABIUChBBUkNISVZFX1RZUEVfWklQEAESGAoUQVJDSElWRV9UWVBFX1RBUl9CWjIQAhIXChNBUkNISVZFX1RZUEVfVEFSX0daEAMSFwoTQVJDSElWRV9UWVBFX1RBUl9YWhAE');
@$core.Deprecated('Use archiveStructureDescriptor instead')
const ArchiveStructure$json = const {
  '1': 'ArchiveStructure',
  '2': const [
    const {'1': 'ARCHIVE_STRUCTURE_UNSPECIFIED', '2': 0},
    const {'1': 'ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED', '2': 1},
    const {'1': 'ARCHIVE_STRUCTURE_DIRECTORY_BASED', '2': 2},
    const {'1': 'ARCHIVE_STRUCTURE_NESTED_DIRECTORY', '2': 3},
    const {'1': 'ARCHIVE_STRUCTURE_UNKNOWN', '2': 4},
  ],
};

/// Descriptor for `ArchiveStructure`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List archiveStructureDescriptor = $convert.base64Decode('ChBBcmNoaXZlU3RydWN0dXJlEiEKHUFSQ0hJVkVfU1RSVUNUVVJFX1VOU1BFQ0lGSUVEEAASKAokQVJDSElWRV9TVFJVQ1RVUkVfU0lOR0xFX0ZJTEVfTkVTVEVEEAESJQohQVJDSElWRV9TVFJVQ1RVUkVfRElSRUNUT1JZX0JBU0VEEAISJgoiQVJDSElWRV9TVFJVQ1RVUkVfTkVTVEVEX0RJUkVDVE9SWRADEh0KGUFSQ0hJVkVfU1RSVUNUVVJFX1VOS05PV04QBA==');
@$core.Deprecated('Use modelArtifactTypeDescriptor instead')
const ModelArtifactType$json = const {
  '1': 'ModelArtifactType',
  '2': const [
    const {'1': 'MODEL_ARTIFACT_TYPE_UNSPECIFIED', '2': 0},
    const {'1': 'MODEL_ARTIFACT_TYPE_SINGLE_FILE', '2': 1},
    const {'1': 'MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE', '2': 2},
    const {'1': 'MODEL_ARTIFACT_TYPE_DIRECTORY', '2': 3},
    const {'1': 'MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE', '2': 4},
    const {'1': 'MODEL_ARTIFACT_TYPE_CUSTOM', '2': 5},
  ],
};

/// Descriptor for `ModelArtifactType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelArtifactTypeDescriptor = $convert.base64Decode('ChFNb2RlbEFydGlmYWN0VHlwZRIjCh9NT0RFTF9BUlRJRkFDVF9UWVBFX1VOU1BFQ0lGSUVEEAASIwofTU9ERUxfQVJUSUZBQ1RfVFlQRV9TSU5HTEVfRklMRRABEiYKIk1PREVMX0FSVElGQUNUX1RZUEVfVEFSX0daX0FSQ0hJVkUQAhIhCh1NT0RFTF9BUlRJRkFDVF9UWVBFX0RJUkVDVE9SWRADEiMKH01PREVMX0FSVElGQUNUX1RZUEVfWklQX0FSQ0hJVkUQBBIeChpNT0RFTF9BUlRJRkFDVF9UWVBFX0NVU1RPTRAF');
@$core.Deprecated('Use accelerationPreferenceDescriptor instead')
const AccelerationPreference$json = const {
  '1': 'AccelerationPreference',
  '2': const [
    const {'1': 'ACCELERATION_PREFERENCE_UNSPECIFIED', '2': 0},
    const {'1': 'ACCELERATION_PREFERENCE_AUTO', '2': 1},
    const {'1': 'ACCELERATION_PREFERENCE_CPU', '2': 2},
    const {'1': 'ACCELERATION_PREFERENCE_GPU', '2': 3},
    const {'1': 'ACCELERATION_PREFERENCE_NPU', '2': 4},
    const {'1': 'ACCELERATION_PREFERENCE_WEBGPU', '2': 5},
    const {'1': 'ACCELERATION_PREFERENCE_METAL', '2': 6},
    const {'1': 'ACCELERATION_PREFERENCE_VULKAN', '2': 7},
  ],
};

/// Descriptor for `AccelerationPreference`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List accelerationPreferenceDescriptor = $convert.base64Decode('ChZBY2NlbGVyYXRpb25QcmVmZXJlbmNlEicKI0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX1VOU1BFQ0lGSUVEEAASIAocQUNDRUxFUkFUSU9OX1BSRUZFUkVOQ0VfQVVUTxABEh8KG0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX0NQVRACEh8KG0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX0dQVRADEh8KG0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX05QVRAEEiIKHkFDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX1dFQkdQVRAFEiEKHUFDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX01FVEFMEAYSIgoeQUNDRUxFUkFUSU9OX1BSRUZFUkVOQ0VfVlVMS0FOEAc=');
@$core.Deprecated('Use routingPolicyDescriptor instead')
const RoutingPolicy$json = const {
  '1': 'RoutingPolicy',
  '2': const [
    const {'1': 'ROUTING_POLICY_UNSPECIFIED', '2': 0},
    const {'1': 'ROUTING_POLICY_PREFER_LOCAL', '2': 1},
    const {'1': 'ROUTING_POLICY_PREFER_CLOUD', '2': 2},
    const {'1': 'ROUTING_POLICY_COST_OPTIMIZED', '2': 3},
    const {'1': 'ROUTING_POLICY_LATENCY_OPTIMIZED', '2': 4},
    const {'1': 'ROUTING_POLICY_MANUAL', '2': 5},
  ],
};

/// Descriptor for `RoutingPolicy`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List routingPolicyDescriptor = $convert.base64Decode('Cg1Sb3V0aW5nUG9saWN5Eh4KGlJPVVRJTkdfUE9MSUNZX1VOU1BFQ0lGSUVEEAASHwobUk9VVElOR19QT0xJQ1lfUFJFRkVSX0xPQ0FMEAESHwobUk9VVElOR19QT0xJQ1lfUFJFRkVSX0NMT1VEEAISIQodUk9VVElOR19QT0xJQ1lfQ09TVF9PUFRJTUlaRUQQAxIkCiBST1VUSU5HX1BPTElDWV9MQVRFTkNZX09QVElNSVpFRBAEEhkKFVJPVVRJTkdfUE9MSUNZX01BTlVBTBAF');
@$core.Deprecated('Use modelInfoDescriptor instead')
const ModelInfo$json = const {
  '1': 'ModelInfo',
  '2': const [
    const {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    const {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    const {'1': 'category', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '10': 'category'},
    const {'1': 'format', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelFormat', '10': 'format'},
    const {'1': 'framework', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '10': 'framework'},
    const {'1': 'download_url', '3': 6, '4': 1, '5': 9, '10': 'downloadUrl'},
    const {'1': 'local_path', '3': 7, '4': 1, '5': 9, '10': 'localPath'},
    const {'1': 'download_size_bytes', '3': 8, '4': 1, '5': 3, '10': 'downloadSizeBytes'},
    const {'1': 'context_length', '3': 9, '4': 1, '5': 5, '10': 'contextLength'},
    const {'1': 'supports_thinking', '3': 10, '4': 1, '5': 8, '10': 'supportsThinking'},
    const {'1': 'supports_lora', '3': 11, '4': 1, '5': 8, '10': 'supportsLora'},
    const {'1': 'description', '3': 12, '4': 1, '5': 9, '10': 'description'},
    const {'1': 'source', '3': 13, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelSource', '10': 'source'},
    const {'1': 'created_at_unix_ms', '3': 14, '4': 1, '5': 3, '10': 'createdAtUnixMs'},
    const {'1': 'updated_at_unix_ms', '3': 15, '4': 1, '5': 3, '10': 'updatedAtUnixMs'},
    const {'1': 'single_file', '3': 20, '4': 1, '5': 11, '6': '.runanywhere.v1.SingleFileArtifact', '9': 0, '10': 'singleFile'},
    const {'1': 'archive', '3': 21, '4': 1, '5': 11, '6': '.runanywhere.v1.ArchiveArtifact', '9': 0, '10': 'archive'},
    const {'1': 'multi_file', '3': 22, '4': 1, '5': 11, '6': '.runanywhere.v1.MultiFileArtifact', '9': 0, '10': 'multiFile'},
    const {'1': 'custom_strategy_id', '3': 23, '4': 1, '5': 9, '9': 0, '10': 'customStrategyId'},
    const {'1': 'built_in', '3': 24, '4': 1, '5': 8, '9': 0, '10': 'builtIn'},
    const {'1': 'artifact_type', '3': 25, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelArtifactType', '9': 1, '10': 'artifactType', '17': true},
    const {'1': 'expected_files', '3': 26, '4': 1, '5': 11, '6': '.runanywhere.v1.ExpectedModelFiles', '9': 2, '10': 'expectedFiles', '17': true},
    const {'1': 'acceleration_preference', '3': 27, '4': 1, '5': 14, '6': '.runanywhere.v1.AccelerationPreference', '9': 3, '10': 'accelerationPreference', '17': true},
    const {'1': 'routing_policy', '3': 28, '4': 1, '5': 14, '6': '.runanywhere.v1.RoutingPolicy', '9': 4, '10': 'routingPolicy', '17': true},
  ],
  '8': const [
    const {'1': 'artifact'},
    const {'1': '_artifact_type'},
    const {'1': '_expected_files'},
    const {'1': '_acceleration_preference'},
    const {'1': '_routing_policy'},
  ],
};

/// Descriptor for `ModelInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelInfoDescriptor = $convert.base64Decode('CglNb2RlbEluZm8SDgoCaWQYASABKAlSAmlkEhIKBG5hbWUYAiABKAlSBG5hbWUSOQoIY2F0ZWdvcnkYAyABKA4yHS5ydW5hbnl3aGVyZS52MS5Nb2RlbENhdGVnb3J5UghjYXRlZ29yeRIzCgZmb3JtYXQYBCABKA4yGy5ydW5hbnl3aGVyZS52MS5Nb2RlbEZvcm1hdFIGZm9ybWF0EkAKCWZyYW1ld29yaxgFIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW5jZUZyYW1ld29ya1IJZnJhbWV3b3JrEiEKDGRvd25sb2FkX3VybBgGIAEoCVILZG93bmxvYWRVcmwSHQoKbG9jYWxfcGF0aBgHIAEoCVIJbG9jYWxQYXRoEi4KE2Rvd25sb2FkX3NpemVfYnl0ZXMYCCABKANSEWRvd25sb2FkU2l6ZUJ5dGVzEiUKDmNvbnRleHRfbGVuZ3RoGAkgASgFUg1jb250ZXh0TGVuZ3RoEisKEXN1cHBvcnRzX3RoaW5raW5nGAogASgIUhBzdXBwb3J0c1RoaW5raW5nEiMKDXN1cHBvcnRzX2xvcmEYCyABKAhSDHN1cHBvcnRzTG9yYRIgCgtkZXNjcmlwdGlvbhgMIAEoCVILZGVzY3JpcHRpb24SMwoGc291cmNlGA0gASgOMhsucnVuYW55d2hlcmUudjEuTW9kZWxTb3VyY2VSBnNvdXJjZRIrChJjcmVhdGVkX2F0X3VuaXhfbXMYDiABKANSD2NyZWF0ZWRBdFVuaXhNcxIrChJ1cGRhdGVkX2F0X3VuaXhfbXMYDyABKANSD3VwZGF0ZWRBdFVuaXhNcxJFCgtzaW5nbGVfZmlsZRgUIAEoCzIiLnJ1bmFueXdoZXJlLnYxLlNpbmdsZUZpbGVBcnRpZmFjdEgAUgpzaW5nbGVGaWxlEjsKB2FyY2hpdmUYFSABKAsyHy5ydW5hbnl3aGVyZS52MS5BcmNoaXZlQXJ0aWZhY3RIAFIHYXJjaGl2ZRJCCgptdWx0aV9maWxlGBYgASgLMiEucnVuYW55d2hlcmUudjEuTXVsdGlGaWxlQXJ0aWZhY3RIAFIJbXVsdGlGaWxlEi4KEmN1c3RvbV9zdHJhdGVneV9pZBgXIAEoCUgAUhBjdXN0b21TdHJhdGVneUlkEhsKCGJ1aWx0X2luGBggASgISABSB2J1aWx0SW4SSwoNYXJ0aWZhY3RfdHlwZRgZIAEoDjIhLnJ1bmFueXdoZXJlLnYxLk1vZGVsQXJ0aWZhY3RUeXBlSAFSDGFydGlmYWN0VHlwZYgBARJOCg5leHBlY3RlZF9maWxlcxgaIAEoCzIiLnJ1bmFueXdoZXJlLnYxLkV4cGVjdGVkTW9kZWxGaWxlc0gCUg1leHBlY3RlZEZpbGVziAEBEmQKF2FjY2VsZXJhdGlvbl9wcmVmZXJlbmNlGBsgASgOMiYucnVuYW55d2hlcmUudjEuQWNjZWxlcmF0aW9uUHJlZmVyZW5jZUgDUhZhY2NlbGVyYXRpb25QcmVmZXJlbmNliAEBEkkKDnJvdXRpbmdfcG9saWN5GBwgASgOMh0ucnVuYW55d2hlcmUudjEuUm91dGluZ1BvbGljeUgEUg1yb3V0aW5nUG9saWN5iAEBQgoKCGFydGlmYWN0QhAKDl9hcnRpZmFjdF90eXBlQhEKD19leHBlY3RlZF9maWxlc0IaChhfYWNjZWxlcmF0aW9uX3ByZWZlcmVuY2VCEQoPX3JvdXRpbmdfcG9saWN5');
@$core.Deprecated('Use singleFileArtifactDescriptor instead')
const SingleFileArtifact$json = const {
  '1': 'SingleFileArtifact',
  '2': const [
    const {'1': 'required_patterns', '3': 1, '4': 3, '5': 9, '10': 'requiredPatterns'},
    const {'1': 'optional_patterns', '3': 2, '4': 3, '5': 9, '10': 'optionalPatterns'},
  ],
};

/// Descriptor for `SingleFileArtifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List singleFileArtifactDescriptor = $convert.base64Decode('ChJTaW5nbGVGaWxlQXJ0aWZhY3QSKwoRcmVxdWlyZWRfcGF0dGVybnMYASADKAlSEHJlcXVpcmVkUGF0dGVybnMSKwoRb3B0aW9uYWxfcGF0dGVybnMYAiADKAlSEG9wdGlvbmFsUGF0dGVybnM=');
@$core.Deprecated('Use archiveArtifactDescriptor instead')
const ArchiveArtifact$json = const {
  '1': 'ArchiveArtifact',
  '2': const [
    const {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ArchiveType', '10': 'type'},
    const {'1': 'structure', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ArchiveStructure', '10': 'structure'},
    const {'1': 'required_patterns', '3': 3, '4': 3, '5': 9, '10': 'requiredPatterns'},
    const {'1': 'optional_patterns', '3': 4, '4': 3, '5': 9, '10': 'optionalPatterns'},
  ],
};

/// Descriptor for `ArchiveArtifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List archiveArtifactDescriptor = $convert.base64Decode('Cg9BcmNoaXZlQXJ0aWZhY3QSLwoEdHlwZRgBIAEoDjIbLnJ1bmFueXdoZXJlLnYxLkFyY2hpdmVUeXBlUgR0eXBlEj4KCXN0cnVjdHVyZRgCIAEoDjIgLnJ1bmFueXdoZXJlLnYxLkFyY2hpdmVTdHJ1Y3R1cmVSCXN0cnVjdHVyZRIrChFyZXF1aXJlZF9wYXR0ZXJucxgDIAMoCVIQcmVxdWlyZWRQYXR0ZXJucxIrChFvcHRpb25hbF9wYXR0ZXJucxgEIAMoCVIQb3B0aW9uYWxQYXR0ZXJucw==');
@$core.Deprecated('Use modelFileDescriptorDescriptor instead')
const ModelFileDescriptor$json = const {
  '1': 'ModelFileDescriptor',
  '2': const [
    const {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    const {'1': 'filename', '3': 2, '4': 1, '5': 9, '10': 'filename'},
    const {'1': 'is_required', '3': 3, '4': 1, '5': 8, '10': 'isRequired'},
    const {'1': 'size_bytes', '3': 4, '4': 1, '5': 3, '9': 0, '10': 'sizeBytes', '17': true},
    const {'1': 'checksum', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'checksum', '17': true},
  ],
  '8': const [
    const {'1': '_size_bytes'},
    const {'1': '_checksum'},
  ],
};

/// Descriptor for `ModelFileDescriptor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelFileDescriptorDescriptor = $convert.base64Decode('ChNNb2RlbEZpbGVEZXNjcmlwdG9yEhAKA3VybBgBIAEoCVIDdXJsEhoKCGZpbGVuYW1lGAIgASgJUghmaWxlbmFtZRIfCgtpc19yZXF1aXJlZBgDIAEoCFIKaXNSZXF1aXJlZBIiCgpzaXplX2J5dGVzGAQgASgDSABSCXNpemVCeXRlc4gBARIfCghjaGVja3N1bRgFIAEoCUgBUghjaGVja3N1bYgBAUINCgtfc2l6ZV9ieXRlc0ILCglfY2hlY2tzdW0=');
@$core.Deprecated('Use multiFileArtifactDescriptor instead')
const MultiFileArtifact$json = const {
  '1': 'MultiFileArtifact',
  '2': const [
    const {'1': 'files', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelFileDescriptor', '10': 'files'},
  ],
};

/// Descriptor for `MultiFileArtifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List multiFileArtifactDescriptor = $convert.base64Decode('ChFNdWx0aUZpbGVBcnRpZmFjdBI5CgVmaWxlcxgBIAMoCzIjLnJ1bmFueXdoZXJlLnYxLk1vZGVsRmlsZURlc2NyaXB0b3JSBWZpbGVz');
@$core.Deprecated('Use expectedModelFilesDescriptor instead')
const ExpectedModelFiles$json = const {
  '1': 'ExpectedModelFiles',
  '2': const [
    const {'1': 'files', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelFileDescriptor', '10': 'files'},
    const {'1': 'root_directory', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'rootDirectory', '17': true},
  ],
  '8': const [
    const {'1': '_root_directory'},
  ],
};

/// Descriptor for `ExpectedModelFiles`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List expectedModelFilesDescriptor = $convert.base64Decode('ChJFeHBlY3RlZE1vZGVsRmlsZXMSOQoFZmlsZXMYASADKAsyIy5ydW5hbnl3aGVyZS52MS5Nb2RlbEZpbGVEZXNjcmlwdG9yUgVmaWxlcxIqCg5yb290X2RpcmVjdG9yeRgCIAEoCUgAUg1yb290RGlyZWN0b3J5iAEBQhEKD19yb290X2RpcmVjdG9yeQ==');
