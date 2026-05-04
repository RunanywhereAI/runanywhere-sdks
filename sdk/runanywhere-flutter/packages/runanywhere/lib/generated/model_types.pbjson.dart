//
//  Generated code. Do not modify.
//  source: model_types.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use audioFormatDescriptor instead')
const AudioFormat$json = {
  '1': 'AudioFormat',
  '2': [
    {'1': 'AUDIO_FORMAT_UNSPECIFIED', '2': 0},
    {'1': 'AUDIO_FORMAT_PCM', '2': 1},
    {'1': 'AUDIO_FORMAT_WAV', '2': 2},
    {'1': 'AUDIO_FORMAT_MP3', '2': 3},
    {'1': 'AUDIO_FORMAT_OPUS', '2': 4},
    {'1': 'AUDIO_FORMAT_AAC', '2': 5},
    {'1': 'AUDIO_FORMAT_FLAC', '2': 6},
    {'1': 'AUDIO_FORMAT_OGG', '2': 7},
    {'1': 'AUDIO_FORMAT_M4A', '2': 8},
    {'1': 'AUDIO_FORMAT_PCM_S16LE', '2': 9},
  ],
};

/// Descriptor for `AudioFormat`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List audioFormatDescriptor = $convert.base64Decode(
    'CgtBdWRpb0Zvcm1hdBIcChhBVURJT19GT1JNQVRfVU5TUEVDSUZJRUQQABIUChBBVURJT19GT1'
    'JNQVRfUENNEAESFAoQQVVESU9fRk9STUFUX1dBVhACEhQKEEFVRElPX0ZPUk1BVF9NUDMQAxIV'
    'ChFBVURJT19GT1JNQVRfT1BVUxAEEhQKEEFVRElPX0ZPUk1BVF9BQUMQBRIVChFBVURJT19GT1'
    'JNQVRfRkxBQxAGEhQKEEFVRElPX0ZPUk1BVF9PR0cQBxIUChBBVURJT19GT1JNQVRfTTRBEAgS'
    'GgoWQVVESU9fRk9STUFUX1BDTV9TMTZMRRAJ');

@$core.Deprecated('Use modelFormatDescriptor instead')
const ModelFormat$json = {
  '1': 'ModelFormat',
  '2': [
    {'1': 'MODEL_FORMAT_UNSPECIFIED', '2': 0},
    {'1': 'MODEL_FORMAT_GGUF', '2': 1},
    {'1': 'MODEL_FORMAT_GGML', '2': 2},
    {'1': 'MODEL_FORMAT_ONNX', '2': 3},
    {'1': 'MODEL_FORMAT_ORT', '2': 4},
    {'1': 'MODEL_FORMAT_BIN', '2': 5},
    {'1': 'MODEL_FORMAT_COREML', '2': 6},
    {'1': 'MODEL_FORMAT_MLMODEL', '2': 7},
    {'1': 'MODEL_FORMAT_MLPACKAGE', '2': 8},
    {'1': 'MODEL_FORMAT_TFLITE', '2': 9},
    {'1': 'MODEL_FORMAT_SAFETENSORS', '2': 10},
    {'1': 'MODEL_FORMAT_QNN_CONTEXT', '2': 11},
    {'1': 'MODEL_FORMAT_ZIP', '2': 12},
    {'1': 'MODEL_FORMAT_FOLDER', '2': 13},
    {'1': 'MODEL_FORMAT_PROPRIETARY', '2': 14},
    {'1': 'MODEL_FORMAT_UNKNOWN', '2': 15},
  ],
};

/// Descriptor for `ModelFormat`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelFormatDescriptor = $convert.base64Decode(
    'CgtNb2RlbEZvcm1hdBIcChhNT0RFTF9GT1JNQVRfVU5TUEVDSUZJRUQQABIVChFNT0RFTF9GT1'
    'JNQVRfR0dVRhABEhUKEU1PREVMX0ZPUk1BVF9HR01MEAISFQoRTU9ERUxfRk9STUFUX09OTlgQ'
    'AxIUChBNT0RFTF9GT1JNQVRfT1JUEAQSFAoQTU9ERUxfRk9STUFUX0JJThAFEhcKE01PREVMX0'
    'ZPUk1BVF9DT1JFTUwQBhIYChRNT0RFTF9GT1JNQVRfTUxNT0RFTBAHEhoKFk1PREVMX0ZPUk1B'
    'VF9NTFBBQ0tBR0UQCBIXChNNT0RFTF9GT1JNQVRfVEZMSVRFEAkSHAoYTU9ERUxfRk9STUFUX1'
    'NBRkVURU5TT1JTEAoSHAoYTU9ERUxfRk9STUFUX1FOTl9DT05URVhUEAsSFAoQTU9ERUxfRk9S'
    'TUFUX1pJUBAMEhcKE01PREVMX0ZPUk1BVF9GT0xERVIQDRIcChhNT0RFTF9GT1JNQVRfUFJPUF'
    'JJRVRBUlkQDhIYChRNT0RFTF9GT1JNQVRfVU5LTk9XThAP');

@$core.Deprecated('Use inferenceFrameworkDescriptor instead')
const InferenceFramework$json = {
  '1': 'InferenceFramework',
  '2': [
    {'1': 'INFERENCE_FRAMEWORK_UNSPECIFIED', '2': 0},
    {'1': 'INFERENCE_FRAMEWORK_ONNX', '2': 1},
    {'1': 'INFERENCE_FRAMEWORK_LLAMA_CPP', '2': 2},
    {'1': 'INFERENCE_FRAMEWORK_FOUNDATION_MODELS', '2': 3},
    {'1': 'INFERENCE_FRAMEWORK_SYSTEM_TTS', '2': 4},
    {'1': 'INFERENCE_FRAMEWORK_FLUID_AUDIO', '2': 5},
    {'1': 'INFERENCE_FRAMEWORK_COREML', '2': 6},
    {'1': 'INFERENCE_FRAMEWORK_MLX', '2': 7},
    {'1': 'INFERENCE_FRAMEWORK_WHISPERKIT_COREML', '2': 8},
    {'1': 'INFERENCE_FRAMEWORK_METALRT', '2': 9},
    {'1': 'INFERENCE_FRAMEWORK_GENIE', '2': 10},
    {'1': 'INFERENCE_FRAMEWORK_TFLITE', '2': 11},
    {'1': 'INFERENCE_FRAMEWORK_EXECUTORCH', '2': 12},
    {'1': 'INFERENCE_FRAMEWORK_MEDIAPIPE', '2': 13},
    {'1': 'INFERENCE_FRAMEWORK_MLC', '2': 14},
    {'1': 'INFERENCE_FRAMEWORK_PICO_LLM', '2': 15},
    {'1': 'INFERENCE_FRAMEWORK_PIPER_TTS', '2': 16},
    {'1': 'INFERENCE_FRAMEWORK_WHISPERKIT', '2': 17},
    {'1': 'INFERENCE_FRAMEWORK_OPENAI_WHISPER', '2': 18},
    {'1': 'INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS', '2': 19},
    {'1': 'INFERENCE_FRAMEWORK_BUILT_IN', '2': 20},
    {'1': 'INFERENCE_FRAMEWORK_NONE', '2': 21},
    {'1': 'INFERENCE_FRAMEWORK_UNKNOWN', '2': 22},
    {'1': 'INFERENCE_FRAMEWORK_SHERPA', '2': 23},
  ],
};

/// Descriptor for `InferenceFramework`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List inferenceFrameworkDescriptor = $convert.base64Decode(
    'ChJJbmZlcmVuY2VGcmFtZXdvcmsSIwofSU5GRVJFTkNFX0ZSQU1FV09SS19VTlNQRUNJRklFRB'
    'AAEhwKGElORkVSRU5DRV9GUkFNRVdPUktfT05OWBABEiEKHUlORkVSRU5DRV9GUkFNRVdPUktf'
    'TExBTUFfQ1BQEAISKQolSU5GRVJFTkNFX0ZSQU1FV09SS19GT1VOREFUSU9OX01PREVMUxADEi'
    'IKHklORkVSRU5DRV9GUkFNRVdPUktfU1lTVEVNX1RUUxAEEiMKH0lORkVSRU5DRV9GUkFNRVdP'
    'UktfRkxVSURfQVVESU8QBRIeChpJTkZFUkVOQ0VfRlJBTUVXT1JLX0NPUkVNTBAGEhsKF0lORk'
    'VSRU5DRV9GUkFNRVdPUktfTUxYEAcSKQolSU5GRVJFTkNFX0ZSQU1FV09SS19XSElTUEVSS0lU'
    'X0NPUkVNTBAIEh8KG0lORkVSRU5DRV9GUkFNRVdPUktfTUVUQUxSVBAJEh0KGUlORkVSRU5DRV'
    '9GUkFNRVdPUktfR0VOSUUQChIeChpJTkZFUkVOQ0VfRlJBTUVXT1JLX1RGTElURRALEiIKHklO'
    'RkVSRU5DRV9GUkFNRVdPUktfRVhFQ1VUT1JDSBAMEiEKHUlORkVSRU5DRV9GUkFNRVdPUktfTU'
    'VESUFQSVBFEA0SGwoXSU5GRVJFTkNFX0ZSQU1FV09SS19NTEMQDhIgChxJTkZFUkVOQ0VfRlJB'
    'TUVXT1JLX1BJQ09fTExNEA8SIQodSU5GRVJFTkNFX0ZSQU1FV09SS19QSVBFUl9UVFMQEBIiCh'
    '5JTkZFUkVOQ0VfRlJBTUVXT1JLX1dISVNQRVJLSVQQERImCiJJTkZFUkVOQ0VfRlJBTUVXT1JL'
    'X09QRU5BSV9XSElTUEVSEBISKgomSU5GRVJFTkNFX0ZSQU1FV09SS19TV0lGVF9UUkFOU0ZPUk'
    '1FUlMQExIgChxJTkZFUkVOQ0VfRlJBTUVXT1JLX0JVSUxUX0lOEBQSHAoYSU5GRVJFTkNFX0ZS'
    'QU1FV09SS19OT05FEBUSHwobSU5GRVJFTkNFX0ZSQU1FV09SS19VTktOT1dOEBYSHgoaSU5GRV'
    'JFTkNFX0ZSQU1FV09SS19TSEVSUEEQFw==');

@$core.Deprecated('Use modelCategoryDescriptor instead')
const ModelCategory$json = {
  '1': 'ModelCategory',
  '2': [
    {'1': 'MODEL_CATEGORY_UNSPECIFIED', '2': 0},
    {'1': 'MODEL_CATEGORY_LANGUAGE', '2': 1},
    {'1': 'MODEL_CATEGORY_SPEECH_RECOGNITION', '2': 2},
    {'1': 'MODEL_CATEGORY_SPEECH_SYNTHESIS', '2': 3},
    {'1': 'MODEL_CATEGORY_VISION', '2': 4},
    {'1': 'MODEL_CATEGORY_IMAGE_GENERATION', '2': 5},
    {'1': 'MODEL_CATEGORY_MULTIMODAL', '2': 6},
    {'1': 'MODEL_CATEGORY_AUDIO', '2': 7},
    {'1': 'MODEL_CATEGORY_EMBEDDING', '2': 8},
    {'1': 'MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION', '2': 9},
  ],
};

/// Descriptor for `ModelCategory`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelCategoryDescriptor = $convert.base64Decode(
    'Cg1Nb2RlbENhdGVnb3J5Eh4KGk1PREVMX0NBVEVHT1JZX1VOU1BFQ0lGSUVEEAASGwoXTU9ERU'
    'xfQ0FURUdPUllfTEFOR1VBR0UQARIlCiFNT0RFTF9DQVRFR09SWV9TUEVFQ0hfUkVDT0dOSVRJ'
    'T04QAhIjCh9NT0RFTF9DQVRFR09SWV9TUEVFQ0hfU1lOVEhFU0lTEAMSGQoVTU9ERUxfQ0FURU'
    'dPUllfVklTSU9OEAQSIwofTU9ERUxfQ0FURUdPUllfSU1BR0VfR0VORVJBVElPThAFEh0KGU1P'
    'REVMX0NBVEVHT1JZX01VTFRJTU9EQUwQBhIYChRNT0RFTF9DQVRFR09SWV9BVURJTxAHEhwKGE'
    '1PREVMX0NBVEVHT1JZX0VNQkVERElORxAIEisKJ01PREVMX0NBVEVHT1JZX1ZPSUNFX0FDVElW'
    'SVRZX0RFVEVDVElPThAJ');

@$core.Deprecated('Use sDKEnvironmentDescriptor instead')
const SDKEnvironment$json = {
  '1': 'SDKEnvironment',
  '2': [
    {'1': 'SDK_ENVIRONMENT_UNSPECIFIED', '2': 0},
    {'1': 'SDK_ENVIRONMENT_DEVELOPMENT', '2': 1},
    {'1': 'SDK_ENVIRONMENT_STAGING', '2': 2},
    {'1': 'SDK_ENVIRONMENT_PRODUCTION', '2': 3},
  ],
};

/// Descriptor for `SDKEnvironment`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sDKEnvironmentDescriptor = $convert.base64Decode(
    'Cg5TREtFbnZpcm9ubWVudBIfChtTREtfRU5WSVJPTk1FTlRfVU5TUEVDSUZJRUQQABIfChtTRE'
    'tfRU5WSVJPTk1FTlRfREVWRUxPUE1FTlQQARIbChdTREtfRU5WSVJPTk1FTlRfU1RBR0lORxAC'
    'Eh4KGlNES19FTlZJUk9OTUVOVF9QUk9EVUNUSU9OEAM=');

@$core.Deprecated('Use modelSourceDescriptor instead')
const ModelSource$json = {
  '1': 'ModelSource',
  '2': [
    {'1': 'MODEL_SOURCE_UNSPECIFIED', '2': 0},
    {'1': 'MODEL_SOURCE_REMOTE', '2': 1},
    {'1': 'MODEL_SOURCE_LOCAL', '2': 2},
  ],
};

/// Descriptor for `ModelSource`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelSourceDescriptor = $convert.base64Decode(
    'CgtNb2RlbFNvdXJjZRIcChhNT0RFTF9TT1VSQ0VfVU5TUEVDSUZJRUQQABIXChNNT0RFTF9TT1'
    'VSQ0VfUkVNT1RFEAESFgoSTU9ERUxfU09VUkNFX0xPQ0FMEAI=');

@$core.Deprecated('Use archiveTypeDescriptor instead')
const ArchiveType$json = {
  '1': 'ArchiveType',
  '2': [
    {'1': 'ARCHIVE_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'ARCHIVE_TYPE_ZIP', '2': 1},
    {'1': 'ARCHIVE_TYPE_TAR_BZ2', '2': 2},
    {'1': 'ARCHIVE_TYPE_TAR_GZ', '2': 3},
    {'1': 'ARCHIVE_TYPE_TAR_XZ', '2': 4},
  ],
};

/// Descriptor for `ArchiveType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List archiveTypeDescriptor = $convert.base64Decode(
    'CgtBcmNoaXZlVHlwZRIcChhBUkNISVZFX1RZUEVfVU5TUEVDSUZJRUQQABIUChBBUkNISVZFX1'
    'RZUEVfWklQEAESGAoUQVJDSElWRV9UWVBFX1RBUl9CWjIQAhIXChNBUkNISVZFX1RZUEVfVEFS'
    'X0daEAMSFwoTQVJDSElWRV9UWVBFX1RBUl9YWhAE');

@$core.Deprecated('Use archiveStructureDescriptor instead')
const ArchiveStructure$json = {
  '1': 'ArchiveStructure',
  '2': [
    {'1': 'ARCHIVE_STRUCTURE_UNSPECIFIED', '2': 0},
    {'1': 'ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED', '2': 1},
    {'1': 'ARCHIVE_STRUCTURE_DIRECTORY_BASED', '2': 2},
    {'1': 'ARCHIVE_STRUCTURE_NESTED_DIRECTORY', '2': 3},
    {'1': 'ARCHIVE_STRUCTURE_UNKNOWN', '2': 4},
  ],
};

/// Descriptor for `ArchiveStructure`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List archiveStructureDescriptor = $convert.base64Decode(
    'ChBBcmNoaXZlU3RydWN0dXJlEiEKHUFSQ0hJVkVfU1RSVUNUVVJFX1VOU1BFQ0lGSUVEEAASKA'
    'okQVJDSElWRV9TVFJVQ1RVUkVfU0lOR0xFX0ZJTEVfTkVTVEVEEAESJQohQVJDSElWRV9TVFJV'
    'Q1RVUkVfRElSRUNUT1JZX0JBU0VEEAISJgoiQVJDSElWRV9TVFJVQ1RVUkVfTkVTVEVEX0RJUk'
    'VDVE9SWRADEh0KGUFSQ0hJVkVfU1RSVUNUVVJFX1VOS05PV04QBA==');

@$core.Deprecated('Use modelArtifactTypeDescriptor instead')
const ModelArtifactType$json = {
  '1': 'ModelArtifactType',
  '2': [
    {'1': 'MODEL_ARTIFACT_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'MODEL_ARTIFACT_TYPE_SINGLE_FILE', '2': 1},
    {'1': 'MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE', '2': 2},
    {'1': 'MODEL_ARTIFACT_TYPE_DIRECTORY', '2': 3},
    {'1': 'MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE', '2': 4},
    {'1': 'MODEL_ARTIFACT_TYPE_CUSTOM', '2': 5},
  ],
};

/// Descriptor for `ModelArtifactType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelArtifactTypeDescriptor = $convert.base64Decode(
    'ChFNb2RlbEFydGlmYWN0VHlwZRIjCh9NT0RFTF9BUlRJRkFDVF9UWVBFX1VOU1BFQ0lGSUVEEA'
    'ASIwofTU9ERUxfQVJUSUZBQ1RfVFlQRV9TSU5HTEVfRklMRRABEiYKIk1PREVMX0FSVElGQUNU'
    'X1RZUEVfVEFSX0daX0FSQ0hJVkUQAhIhCh1NT0RFTF9BUlRJRkFDVF9UWVBFX0RJUkVDVE9SWR'
    'ADEiMKH01PREVMX0FSVElGQUNUX1RZUEVfWklQX0FSQ0hJVkUQBBIeChpNT0RFTF9BUlRJRkFD'
    'VF9UWVBFX0NVU1RPTRAF');

@$core.Deprecated('Use modelRegistryStatusDescriptor instead')
const ModelRegistryStatus$json = {
  '1': 'ModelRegistryStatus',
  '2': [
    {'1': 'MODEL_REGISTRY_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'MODEL_REGISTRY_STATUS_REGISTERED', '2': 1},
    {'1': 'MODEL_REGISTRY_STATUS_DOWNLOADING', '2': 2},
    {'1': 'MODEL_REGISTRY_STATUS_DOWNLOADED', '2': 3},
    {'1': 'MODEL_REGISTRY_STATUS_LOADING', '2': 4},
    {'1': 'MODEL_REGISTRY_STATUS_LOADED', '2': 5},
    {'1': 'MODEL_REGISTRY_STATUS_ERROR', '2': 6},
  ],
};

/// Descriptor for `ModelRegistryStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelRegistryStatusDescriptor = $convert.base64Decode(
    'ChNNb2RlbFJlZ2lzdHJ5U3RhdHVzEiUKIU1PREVMX1JFR0lTVFJZX1NUQVRVU19VTlNQRUNJRk'
    'lFRBAAEiQKIE1PREVMX1JFR0lTVFJZX1NUQVRVU19SRUdJU1RFUkVEEAESJQohTU9ERUxfUkVH'
    'SVNUUllfU1RBVFVTX0RPV05MT0FESU5HEAISJAogTU9ERUxfUkVHSVNUUllfU1RBVFVTX0RPV0'
    '5MT0FERUQQAxIhCh1NT0RFTF9SRUdJU1RSWV9TVEFUVVNfTE9BRElORxAEEiAKHE1PREVMX1JF'
    'R0lTVFJZX1NUQVRVU19MT0FERUQQBRIfChtNT0RFTF9SRUdJU1RSWV9TVEFUVVNfRVJST1IQBg'
    '==');

@$core.Deprecated('Use modelQuerySortFieldDescriptor instead')
const ModelQuerySortField$json = {
  '1': 'ModelQuerySortField',
  '2': [
    {'1': 'MODEL_QUERY_SORT_FIELD_UNSPECIFIED', '2': 0},
    {'1': 'MODEL_QUERY_SORT_FIELD_NAME', '2': 1},
    {'1': 'MODEL_QUERY_SORT_FIELD_CREATED_AT_UNIX_MS', '2': 2},
    {'1': 'MODEL_QUERY_SORT_FIELD_UPDATED_AT_UNIX_MS', '2': 3},
    {'1': 'MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES', '2': 4},
    {'1': 'MODEL_QUERY_SORT_FIELD_LAST_USED_AT_UNIX_MS', '2': 5},
    {'1': 'MODEL_QUERY_SORT_FIELD_USAGE_COUNT', '2': 6},
  ],
};

/// Descriptor for `ModelQuerySortField`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelQuerySortFieldDescriptor = $convert.base64Decode(
    'ChNNb2RlbFF1ZXJ5U29ydEZpZWxkEiYKIk1PREVMX1FVRVJZX1NPUlRfRklFTERfVU5TUEVDSU'
    'ZJRUQQABIfChtNT0RFTF9RVUVSWV9TT1JUX0ZJRUxEX05BTUUQARItCilNT0RFTF9RVUVSWV9T'
    'T1JUX0ZJRUxEX0NSRUFURURfQVRfVU5JWF9NUxACEi0KKU1PREVMX1FVRVJZX1NPUlRfRklFTE'
    'RfVVBEQVRFRF9BVF9VTklYX01TEAMSLgoqTU9ERUxfUVVFUllfU09SVF9GSUVMRF9ET1dOTE9B'
    'RF9TSVpFX0JZVEVTEAQSLworTU9ERUxfUVVFUllfU09SVF9GSUVMRF9MQVNUX1VTRURfQVRfVU'
    '5JWF9NUxAFEiYKIk1PREVMX1FVRVJZX1NPUlRfRklFTERfVVNBR0VfQ09VTlQQBg==');

@$core.Deprecated('Use modelQuerySortOrderDescriptor instead')
const ModelQuerySortOrder$json = {
  '1': 'ModelQuerySortOrder',
  '2': [
    {'1': 'MODEL_QUERY_SORT_ORDER_UNSPECIFIED', '2': 0},
    {'1': 'MODEL_QUERY_SORT_ORDER_ASCENDING', '2': 1},
    {'1': 'MODEL_QUERY_SORT_ORDER_DESCENDING', '2': 2},
  ],
};

/// Descriptor for `ModelQuerySortOrder`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelQuerySortOrderDescriptor = $convert.base64Decode(
    'ChNNb2RlbFF1ZXJ5U29ydE9yZGVyEiYKIk1PREVMX1FVRVJZX1NPUlRfT1JERVJfVU5TUEVDSU'
    'ZJRUQQABIkCiBNT0RFTF9RVUVSWV9TT1JUX09SREVSX0FTQ0VORElORxABEiUKIU1PREVMX1FV'
    'RVJZX1NPUlRfT1JERVJfREVTQ0VORElORxAC');

@$core.Deprecated('Use modelFileRoleDescriptor instead')
const ModelFileRole$json = {
  '1': 'ModelFileRole',
  '2': [
    {'1': 'MODEL_FILE_ROLE_UNSPECIFIED', '2': 0},
    {'1': 'MODEL_FILE_ROLE_PRIMARY_MODEL', '2': 1},
    {'1': 'MODEL_FILE_ROLE_COMPANION', '2': 2},
    {'1': 'MODEL_FILE_ROLE_VISION_PROJECTOR', '2': 3},
    {'1': 'MODEL_FILE_ROLE_TOKENIZER', '2': 4},
    {'1': 'MODEL_FILE_ROLE_CONFIG', '2': 5},
    {'1': 'MODEL_FILE_ROLE_VOCABULARY', '2': 6},
    {'1': 'MODEL_FILE_ROLE_MERGES', '2': 7},
    {'1': 'MODEL_FILE_ROLE_LABELS', '2': 8},
  ],
};

/// Descriptor for `ModelFileRole`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelFileRoleDescriptor = $convert.base64Decode(
    'Cg1Nb2RlbEZpbGVSb2xlEh8KG01PREVMX0ZJTEVfUk9MRV9VTlNQRUNJRklFRBAAEiEKHU1PRE'
    'VMX0ZJTEVfUk9MRV9QUklNQVJZX01PREVMEAESHQoZTU9ERUxfRklMRV9ST0xFX0NPTVBBTklP'
    'ThACEiQKIE1PREVMX0ZJTEVfUk9MRV9WSVNJT05fUFJPSkVDVE9SEAMSHQoZTU9ERUxfRklMRV'
    '9ST0xFX1RPS0VOSVpFUhAEEhoKFk1PREVMX0ZJTEVfUk9MRV9DT05GSUcQBRIeChpNT0RFTF9G'
    'SUxFX1JPTEVfVk9DQUJVTEFSWRAGEhoKFk1PREVMX0ZJTEVfUk9MRV9NRVJHRVMQBxIaChZNT0'
    'RFTF9GSUxFX1JPTEVfTEFCRUxTEAg=');

@$core.Deprecated('Use accelerationPreferenceDescriptor instead')
const AccelerationPreference$json = {
  '1': 'AccelerationPreference',
  '2': [
    {'1': 'ACCELERATION_PREFERENCE_UNSPECIFIED', '2': 0},
    {'1': 'ACCELERATION_PREFERENCE_AUTO', '2': 1},
    {'1': 'ACCELERATION_PREFERENCE_CPU', '2': 2},
    {'1': 'ACCELERATION_PREFERENCE_GPU', '2': 3},
    {'1': 'ACCELERATION_PREFERENCE_NPU', '2': 4},
    {'1': 'ACCELERATION_PREFERENCE_WEBGPU', '2': 5},
    {'1': 'ACCELERATION_PREFERENCE_METAL', '2': 6},
    {'1': 'ACCELERATION_PREFERENCE_VULKAN', '2': 7},
  ],
};

/// Descriptor for `AccelerationPreference`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List accelerationPreferenceDescriptor = $convert.base64Decode(
    'ChZBY2NlbGVyYXRpb25QcmVmZXJlbmNlEicKI0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX1VOU1'
    'BFQ0lGSUVEEAASIAocQUNDRUxFUkFUSU9OX1BSRUZFUkVOQ0VfQVVUTxABEh8KG0FDQ0VMRVJB'
    'VElPTl9QUkVGRVJFTkNFX0NQVRACEh8KG0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX0dQVRADEh'
    '8KG0FDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX05QVRAEEiIKHkFDQ0VMRVJBVElPTl9QUkVGRVJF'
    'TkNFX1dFQkdQVRAFEiEKHUFDQ0VMRVJBVElPTl9QUkVGRVJFTkNFX01FVEFMEAYSIgoeQUNDRU'
    'xFUkFUSU9OX1BSRUZFUkVOQ0VfVlVMS0FOEAc=');

@$core.Deprecated('Use routingPolicyDescriptor instead')
const RoutingPolicy$json = {
  '1': 'RoutingPolicy',
  '2': [
    {'1': 'ROUTING_POLICY_UNSPECIFIED', '2': 0},
    {'1': 'ROUTING_POLICY_PREFER_LOCAL', '2': 1},
    {'1': 'ROUTING_POLICY_PREFER_CLOUD', '2': 2},
    {'1': 'ROUTING_POLICY_COST_OPTIMIZED', '2': 3},
    {'1': 'ROUTING_POLICY_LATENCY_OPTIMIZED', '2': 4},
    {'1': 'ROUTING_POLICY_MANUAL', '2': 5},
  ],
};

/// Descriptor for `RoutingPolicy`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List routingPolicyDescriptor = $convert.base64Decode(
    'Cg1Sb3V0aW5nUG9saWN5Eh4KGlJPVVRJTkdfUE9MSUNZX1VOU1BFQ0lGSUVEEAASHwobUk9VVE'
    'lOR19QT0xJQ1lfUFJFRkVSX0xPQ0FMEAESHwobUk9VVElOR19QT0xJQ1lfUFJFRkVSX0NMT1VE'
    'EAISIQodUk9VVElOR19QT0xJQ1lfQ09TVF9PUFRJTUlaRUQQAxIkCiBST1VUSU5HX1BPTElDWV'
    '9MQVRFTkNZX09QVElNSVpFRBAEEhkKFVJPVVRJTkdfUE9MSUNZX01BTlVBTBAF');

@$core.Deprecated('Use modelThinkingTagPatternDescriptor instead')
const ModelThinkingTagPattern$json = {
  '1': 'ModelThinkingTagPattern',
  '2': [
    {'1': 'open_tag', '3': 1, '4': 1, '5': 9, '10': 'openTag'},
    {'1': 'close_tag', '3': 2, '4': 1, '5': 9, '10': 'closeTag'},
  ],
};

/// Descriptor for `ModelThinkingTagPattern`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelThinkingTagPatternDescriptor = $convert.base64Decode(
    'ChdNb2RlbFRoaW5raW5nVGFnUGF0dGVybhIZCghvcGVuX3RhZxgBIAEoCVIHb3BlblRhZxIbCg'
    'ljbG9zZV90YWcYAiABKAlSCGNsb3NlVGFn');

@$core.Deprecated('Use modelInfoMetadataDescriptor instead')
const ModelInfoMetadata$json = {
  '1': 'ModelInfoMetadata',
  '2': [
    {'1': 'description', '3': 1, '4': 1, '5': 9, '10': 'description'},
    {'1': 'author', '3': 2, '4': 1, '5': 9, '10': 'author'},
    {'1': 'license', '3': 3, '4': 1, '5': 9, '10': 'license'},
    {'1': 'tags', '3': 4, '4': 3, '5': 9, '10': 'tags'},
    {'1': 'version', '3': 5, '4': 1, '5': 9, '10': 'version'},
  ],
};

/// Descriptor for `ModelInfoMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelInfoMetadataDescriptor = $convert.base64Decode(
    'ChFNb2RlbEluZm9NZXRhZGF0YRIgCgtkZXNjcmlwdGlvbhgBIAEoCVILZGVzY3JpcHRpb24SFg'
    'oGYXV0aG9yGAIgASgJUgZhdXRob3ISGAoHbGljZW5zZRgDIAEoCVIHbGljZW5zZRISCgR0YWdz'
    'GAQgAygJUgR0YWdzEhgKB3ZlcnNpb24YBSABKAlSB3ZlcnNpb24=');

@$core.Deprecated('Use modelRuntimeCompatibilityDescriptor instead')
const ModelRuntimeCompatibility$json = {
  '1': 'ModelRuntimeCompatibility',
  '2': [
    {'1': 'compatible_frameworks', '3': 1, '4': 3, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '10': 'compatibleFrameworks'},
    {'1': 'compatible_formats', '3': 2, '4': 3, '5': 14, '6': '.runanywhere.v1.ModelFormat', '10': 'compatibleFormats'},
  ],
};

/// Descriptor for `ModelRuntimeCompatibility`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelRuntimeCompatibilityDescriptor = $convert.base64Decode(
    'ChlNb2RlbFJ1bnRpbWVDb21wYXRpYmlsaXR5ElcKFWNvbXBhdGlibGVfZnJhbWV3b3JrcxgBIA'
    'MoDjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW5jZUZyYW1ld29ya1IUY29tcGF0aWJsZUZyYW1l'
    'd29ya3MSSgoSY29tcGF0aWJsZV9mb3JtYXRzGAIgAygOMhsucnVuYW55d2hlcmUudjEuTW9kZW'
    'xGb3JtYXRSEWNvbXBhdGlibGVGb3JtYXRz');

@$core.Deprecated('Use modelInfoDescriptor instead')
const ModelInfo$json = {
  '1': 'ModelInfo',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'category', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '10': 'category'},
    {'1': 'format', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelFormat', '10': 'format'},
    {'1': 'framework', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '10': 'framework'},
    {'1': 'download_url', '3': 6, '4': 1, '5': 9, '10': 'downloadUrl'},
    {'1': 'local_path', '3': 7, '4': 1, '5': 9, '10': 'localPath'},
    {'1': 'download_size_bytes', '3': 8, '4': 1, '5': 3, '10': 'downloadSizeBytes'},
    {'1': 'context_length', '3': 9, '4': 1, '5': 5, '10': 'contextLength'},
    {'1': 'supports_thinking', '3': 10, '4': 1, '5': 8, '10': 'supportsThinking'},
    {'1': 'supports_lora', '3': 11, '4': 1, '5': 8, '10': 'supportsLora'},
    {'1': 'description', '3': 12, '4': 1, '5': 9, '10': 'description'},
    {'1': 'source', '3': 13, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelSource', '10': 'source'},
    {'1': 'created_at_unix_ms', '3': 14, '4': 1, '5': 3, '10': 'createdAtUnixMs'},
    {'1': 'updated_at_unix_ms', '3': 15, '4': 1, '5': 3, '10': 'updatedAtUnixMs'},
    {'1': 'memory_required_bytes', '3': 16, '4': 1, '5': 3, '9': 1, '10': 'memoryRequiredBytes', '17': true},
    {'1': 'checksum_sha256', '3': 17, '4': 1, '5': 9, '9': 2, '10': 'checksumSha256', '17': true},
    {'1': 'thinking_pattern', '3': 18, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelThinkingTagPattern', '9': 3, '10': 'thinkingPattern', '17': true},
    {'1': 'metadata', '3': 19, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfoMetadata', '9': 4, '10': 'metadata', '17': true},
    {'1': 'single_file', '3': 20, '4': 1, '5': 11, '6': '.runanywhere.v1.SingleFileArtifact', '9': 0, '10': 'singleFile'},
    {'1': 'archive', '3': 21, '4': 1, '5': 11, '6': '.runanywhere.v1.ArchiveArtifact', '9': 0, '10': 'archive'},
    {'1': 'multi_file', '3': 22, '4': 1, '5': 11, '6': '.runanywhere.v1.MultiFileArtifact', '9': 0, '10': 'multiFile'},
    {'1': 'custom_strategy_id', '3': 23, '4': 1, '5': 9, '9': 0, '10': 'customStrategyId'},
    {'1': 'built_in', '3': 24, '4': 1, '5': 8, '9': 0, '10': 'builtIn'},
    {'1': 'artifact_type', '3': 25, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelArtifactType', '9': 5, '10': 'artifactType', '17': true},
    {'1': 'expected_files', '3': 26, '4': 1, '5': 11, '6': '.runanywhere.v1.ExpectedModelFiles', '9': 6, '10': 'expectedFiles', '17': true},
    {'1': 'acceleration_preference', '3': 27, '4': 1, '5': 14, '6': '.runanywhere.v1.AccelerationPreference', '9': 7, '10': 'accelerationPreference', '17': true},
    {'1': 'routing_policy', '3': 28, '4': 1, '5': 14, '6': '.runanywhere.v1.RoutingPolicy', '9': 8, '10': 'routingPolicy', '17': true},
    {'1': 'compatibility', '3': 29, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelRuntimeCompatibility', '9': 9, '10': 'compatibility', '17': true},
    {'1': 'preferred_framework', '3': 30, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 10, '10': 'preferredFramework', '17': true},
    {'1': 'registry_status', '3': 31, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelRegistryStatus', '9': 11, '10': 'registryStatus', '17': true},
    {'1': 'is_downloaded', '3': 32, '4': 1, '5': 8, '9': 12, '10': 'isDownloaded', '17': true},
    {'1': 'is_available', '3': 33, '4': 1, '5': 8, '9': 13, '10': 'isAvailable', '17': true},
    {'1': 'last_used_at_unix_ms', '3': 34, '4': 1, '5': 3, '9': 14, '10': 'lastUsedAtUnixMs', '17': true},
    {'1': 'usage_count', '3': 35, '4': 1, '5': 5, '9': 15, '10': 'usageCount', '17': true},
    {'1': 'sync_pending', '3': 36, '4': 1, '5': 8, '9': 16, '10': 'syncPending', '17': true},
    {'1': 'status_message', '3': 37, '4': 1, '5': 9, '9': 17, '10': 'statusMessage', '17': true},
  ],
  '8': [
    {'1': 'artifact'},
    {'1': '_memory_required_bytes'},
    {'1': '_checksum_sha256'},
    {'1': '_thinking_pattern'},
    {'1': '_metadata'},
    {'1': '_artifact_type'},
    {'1': '_expected_files'},
    {'1': '_acceleration_preference'},
    {'1': '_routing_policy'},
    {'1': '_compatibility'},
    {'1': '_preferred_framework'},
    {'1': '_registry_status'},
    {'1': '_is_downloaded'},
    {'1': '_is_available'},
    {'1': '_last_used_at_unix_ms'},
    {'1': '_usage_count'},
    {'1': '_sync_pending'},
    {'1': '_status_message'},
  ],
};

/// Descriptor for `ModelInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelInfoDescriptor = $convert.base64Decode(
    'CglNb2RlbEluZm8SDgoCaWQYASABKAlSAmlkEhIKBG5hbWUYAiABKAlSBG5hbWUSOQoIY2F0ZW'
    'dvcnkYAyABKA4yHS5ydW5hbnl3aGVyZS52MS5Nb2RlbENhdGVnb3J5UghjYXRlZ29yeRIzCgZm'
    'b3JtYXQYBCABKA4yGy5ydW5hbnl3aGVyZS52MS5Nb2RlbEZvcm1hdFIGZm9ybWF0EkAKCWZyYW'
    '1ld29yaxgFIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW5jZUZyYW1ld29ya1IJZnJhbWV3'
    'b3JrEiEKDGRvd25sb2FkX3VybBgGIAEoCVILZG93bmxvYWRVcmwSHQoKbG9jYWxfcGF0aBgHIA'
    'EoCVIJbG9jYWxQYXRoEi4KE2Rvd25sb2FkX3NpemVfYnl0ZXMYCCABKANSEWRvd25sb2FkU2l6'
    'ZUJ5dGVzEiUKDmNvbnRleHRfbGVuZ3RoGAkgASgFUg1jb250ZXh0TGVuZ3RoEisKEXN1cHBvcn'
    'RzX3RoaW5raW5nGAogASgIUhBzdXBwb3J0c1RoaW5raW5nEiMKDXN1cHBvcnRzX2xvcmEYCyAB'
    'KAhSDHN1cHBvcnRzTG9yYRIgCgtkZXNjcmlwdGlvbhgMIAEoCVILZGVzY3JpcHRpb24SMwoGc2'
    '91cmNlGA0gASgOMhsucnVuYW55d2hlcmUudjEuTW9kZWxTb3VyY2VSBnNvdXJjZRIrChJjcmVh'
    'dGVkX2F0X3VuaXhfbXMYDiABKANSD2NyZWF0ZWRBdFVuaXhNcxIrChJ1cGRhdGVkX2F0X3VuaX'
    'hfbXMYDyABKANSD3VwZGF0ZWRBdFVuaXhNcxI3ChVtZW1vcnlfcmVxdWlyZWRfYnl0ZXMYECAB'
    'KANIAVITbWVtb3J5UmVxdWlyZWRCeXRlc4gBARIsCg9jaGVja3N1bV9zaGEyNTYYESABKAlIAl'
    'IOY2hlY2tzdW1TaGEyNTaIAQESVwoQdGhpbmtpbmdfcGF0dGVybhgSIAEoCzInLnJ1bmFueXdo'
    'ZXJlLnYxLk1vZGVsVGhpbmtpbmdUYWdQYXR0ZXJuSANSD3RoaW5raW5nUGF0dGVybogBARJCCg'
    'htZXRhZGF0YRgTIAEoCzIhLnJ1bmFueXdoZXJlLnYxLk1vZGVsSW5mb01ldGFkYXRhSARSCG1l'
    'dGFkYXRhiAEBEkUKC3NpbmdsZV9maWxlGBQgASgLMiIucnVuYW55d2hlcmUudjEuU2luZ2xlRm'
    'lsZUFydGlmYWN0SABSCnNpbmdsZUZpbGUSOwoHYXJjaGl2ZRgVIAEoCzIfLnJ1bmFueXdoZXJl'
    'LnYxLkFyY2hpdmVBcnRpZmFjdEgAUgdhcmNoaXZlEkIKCm11bHRpX2ZpbGUYFiABKAsyIS5ydW'
    '5hbnl3aGVyZS52MS5NdWx0aUZpbGVBcnRpZmFjdEgAUgltdWx0aUZpbGUSLgoSY3VzdG9tX3N0'
    'cmF0ZWd5X2lkGBcgASgJSABSEGN1c3RvbVN0cmF0ZWd5SWQSGwoIYnVpbHRfaW4YGCABKAhIAF'
    'IHYnVpbHRJbhJLCg1hcnRpZmFjdF90eXBlGBkgASgOMiEucnVuYW55d2hlcmUudjEuTW9kZWxB'
    'cnRpZmFjdFR5cGVIBVIMYXJ0aWZhY3RUeXBliAEBEk4KDmV4cGVjdGVkX2ZpbGVzGBogASgLMi'
    'IucnVuYW55d2hlcmUudjEuRXhwZWN0ZWRNb2RlbEZpbGVzSAZSDWV4cGVjdGVkRmlsZXOIAQES'
    'ZAoXYWNjZWxlcmF0aW9uX3ByZWZlcmVuY2UYGyABKA4yJi5ydW5hbnl3aGVyZS52MS5BY2NlbG'
    'VyYXRpb25QcmVmZXJlbmNlSAdSFmFjY2VsZXJhdGlvblByZWZlcmVuY2WIAQESSQoOcm91dGlu'
    'Z19wb2xpY3kYHCABKA4yHS5ydW5hbnl3aGVyZS52MS5Sb3V0aW5nUG9saWN5SAhSDXJvdXRpbm'
    'dQb2xpY3mIAQESVAoNY29tcGF0aWJpbGl0eRgdIAEoCzIpLnJ1bmFueXdoZXJlLnYxLk1vZGVs'
    'UnVudGltZUNvbXBhdGliaWxpdHlICVINY29tcGF0aWJpbGl0eYgBARJYChNwcmVmZXJyZWRfZn'
    'JhbWV3b3JrGB4gASgOMiIucnVuYW55d2hlcmUudjEuSW5mZXJlbmNlRnJhbWV3b3JrSApSEnBy'
    'ZWZlcnJlZEZyYW1ld29ya4gBARJRCg9yZWdpc3RyeV9zdGF0dXMYHyABKA4yIy5ydW5hbnl3aG'
    'VyZS52MS5Nb2RlbFJlZ2lzdHJ5U3RhdHVzSAtSDnJlZ2lzdHJ5U3RhdHVziAEBEigKDWlzX2Rv'
    'd25sb2FkZWQYICABKAhIDFIMaXNEb3dubG9hZGVkiAEBEiYKDGlzX2F2YWlsYWJsZRghIAEoCE'
    'gNUgtpc0F2YWlsYWJsZYgBARIzChRsYXN0X3VzZWRfYXRfdW5peF9tcxgiIAEoA0gOUhBsYXN0'
    'VXNlZEF0VW5peE1ziAEBEiQKC3VzYWdlX2NvdW50GCMgASgFSA9SCnVzYWdlQ291bnSIAQESJg'
    'oMc3luY19wZW5kaW5nGCQgASgISBBSC3N5bmNQZW5kaW5niAEBEioKDnN0YXR1c19tZXNzYWdl'
    'GCUgASgJSBFSDXN0YXR1c01lc3NhZ2WIAQFCCgoIYXJ0aWZhY3RCGAoWX21lbW9yeV9yZXF1aX'
    'JlZF9ieXRlc0ISChBfY2hlY2tzdW1fc2hhMjU2QhMKEV90aGlua2luZ19wYXR0ZXJuQgsKCV9t'
    'ZXRhZGF0YUIQCg5fYXJ0aWZhY3RfdHlwZUIRCg9fZXhwZWN0ZWRfZmlsZXNCGgoYX2FjY2VsZX'
    'JhdGlvbl9wcmVmZXJlbmNlQhEKD19yb3V0aW5nX3BvbGljeUIQCg5fY29tcGF0aWJpbGl0eUIW'
    'ChRfcHJlZmVycmVkX2ZyYW1ld29ya0ISChBfcmVnaXN0cnlfc3RhdHVzQhAKDl9pc19kb3dubG'
    '9hZGVkQg8KDV9pc19hdmFpbGFibGVCFwoVX2xhc3RfdXNlZF9hdF91bml4X21zQg4KDF91c2Fn'
    'ZV9jb3VudEIPCg1fc3luY19wZW5kaW5nQhEKD19zdGF0dXNfbWVzc2FnZQ==');

@$core.Deprecated('Use modelInfoListDescriptor instead')
const ModelInfoList$json = {
  '1': 'ModelInfoList',
  '2': [
    {'1': 'models', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelInfo', '10': 'models'},
  ],
};

/// Descriptor for `ModelInfoList`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelInfoListDescriptor = $convert.base64Decode(
    'Cg1Nb2RlbEluZm9MaXN0EjEKBm1vZGVscxgBIAMoCzIZLnJ1bmFueXdoZXJlLnYxLk1vZGVsSW'
    '5mb1IGbW9kZWxz');

@$core.Deprecated('Use singleFileArtifactDescriptor instead')
const SingleFileArtifact$json = {
  '1': 'SingleFileArtifact',
  '2': [
    {'1': 'required_patterns', '3': 1, '4': 3, '5': 9, '10': 'requiredPatterns'},
    {'1': 'optional_patterns', '3': 2, '4': 3, '5': 9, '10': 'optionalPatterns'},
  ],
};

/// Descriptor for `SingleFileArtifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List singleFileArtifactDescriptor = $convert.base64Decode(
    'ChJTaW5nbGVGaWxlQXJ0aWZhY3QSKwoRcmVxdWlyZWRfcGF0dGVybnMYASADKAlSEHJlcXVpcm'
    'VkUGF0dGVybnMSKwoRb3B0aW9uYWxfcGF0dGVybnMYAiADKAlSEG9wdGlvbmFsUGF0dGVybnM=');

@$core.Deprecated('Use archiveArtifactDescriptor instead')
const ArchiveArtifact$json = {
  '1': 'ArchiveArtifact',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ArchiveType', '10': 'type'},
    {'1': 'structure', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ArchiveStructure', '10': 'structure'},
    {'1': 'required_patterns', '3': 3, '4': 3, '5': 9, '10': 'requiredPatterns'},
    {'1': 'optional_patterns', '3': 4, '4': 3, '5': 9, '10': 'optionalPatterns'},
  ],
};

/// Descriptor for `ArchiveArtifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List archiveArtifactDescriptor = $convert.base64Decode(
    'Cg9BcmNoaXZlQXJ0aWZhY3QSLwoEdHlwZRgBIAEoDjIbLnJ1bmFueXdoZXJlLnYxLkFyY2hpdm'
    'VUeXBlUgR0eXBlEj4KCXN0cnVjdHVyZRgCIAEoDjIgLnJ1bmFueXdoZXJlLnYxLkFyY2hpdmVT'
    'dHJ1Y3R1cmVSCXN0cnVjdHVyZRIrChFyZXF1aXJlZF9wYXR0ZXJucxgDIAMoCVIQcmVxdWlyZW'
    'RQYXR0ZXJucxIrChFvcHRpb25hbF9wYXR0ZXJucxgEIAMoCVIQb3B0aW9uYWxQYXR0ZXJucw==');

@$core.Deprecated('Use modelFileDescriptorDescriptor instead')
const ModelFileDescriptor$json = {
  '1': 'ModelFileDescriptor',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'filename', '3': 2, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'is_required', '3': 3, '4': 1, '5': 8, '10': 'isRequired'},
    {'1': 'size_bytes', '3': 4, '4': 1, '5': 3, '9': 0, '10': 'sizeBytes', '17': true},
    {'1': 'checksum', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'checksum', '17': true},
    {'1': 'relative_path', '3': 6, '4': 1, '5': 9, '9': 2, '10': 'relativePath', '17': true},
    {'1': 'destination_path', '3': 7, '4': 1, '5': 9, '9': 3, '10': 'destinationPath', '17': true},
    {'1': 'role', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelFileRole', '9': 4, '10': 'role', '17': true},
    {'1': 'local_path', '3': 9, '4': 1, '5': 9, '9': 5, '10': 'localPath', '17': true},
  ],
  '8': [
    {'1': '_size_bytes'},
    {'1': '_checksum'},
    {'1': '_relative_path'},
    {'1': '_destination_path'},
    {'1': '_role'},
    {'1': '_local_path'},
  ],
};

/// Descriptor for `ModelFileDescriptor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelFileDescriptorDescriptor = $convert.base64Decode(
    'ChNNb2RlbEZpbGVEZXNjcmlwdG9yEhAKA3VybBgBIAEoCVIDdXJsEhoKCGZpbGVuYW1lGAIgAS'
    'gJUghmaWxlbmFtZRIfCgtpc19yZXF1aXJlZBgDIAEoCFIKaXNSZXF1aXJlZBIiCgpzaXplX2J5'
    'dGVzGAQgASgDSABSCXNpemVCeXRlc4gBARIfCghjaGVja3N1bRgFIAEoCUgBUghjaGVja3N1bY'
    'gBARIoCg1yZWxhdGl2ZV9wYXRoGAYgASgJSAJSDHJlbGF0aXZlUGF0aIgBARIuChBkZXN0aW5h'
    'dGlvbl9wYXRoGAcgASgJSANSD2Rlc3RpbmF0aW9uUGF0aIgBARI2CgRyb2xlGAggASgOMh0ucn'
    'VuYW55d2hlcmUudjEuTW9kZWxGaWxlUm9sZUgEUgRyb2xliAEBEiIKCmxvY2FsX3BhdGgYCSAB'
    'KAlIBVIJbG9jYWxQYXRoiAEBQg0KC19zaXplX2J5dGVzQgsKCV9jaGVja3N1bUIQCg5fcmVsYX'
    'RpdmVfcGF0aEITChFfZGVzdGluYXRpb25fcGF0aEIHCgVfcm9sZUINCgtfbG9jYWxfcGF0aA==');

@$core.Deprecated('Use multiFileArtifactDescriptor instead')
const MultiFileArtifact$json = {
  '1': 'MultiFileArtifact',
  '2': [
    {'1': 'files', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelFileDescriptor', '10': 'files'},
  ],
};

/// Descriptor for `MultiFileArtifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List multiFileArtifactDescriptor = $convert.base64Decode(
    'ChFNdWx0aUZpbGVBcnRpZmFjdBI5CgVmaWxlcxgBIAMoCzIjLnJ1bmFueXdoZXJlLnYxLk1vZG'
    'VsRmlsZURlc2NyaXB0b3JSBWZpbGVz');

@$core.Deprecated('Use expectedModelFilesDescriptor instead')
const ExpectedModelFiles$json = {
  '1': 'ExpectedModelFiles',
  '2': [
    {'1': 'files', '3': 1, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelFileDescriptor', '10': 'files'},
    {'1': 'root_directory', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'rootDirectory', '17': true},
    {'1': 'required_patterns', '3': 3, '4': 3, '5': 9, '10': 'requiredPatterns'},
    {'1': 'optional_patterns', '3': 4, '4': 3, '5': 9, '10': 'optionalPatterns'},
    {'1': 'description', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'description', '17': true},
  ],
  '8': [
    {'1': '_root_directory'},
    {'1': '_description'},
  ],
};

/// Descriptor for `ExpectedModelFiles`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List expectedModelFilesDescriptor = $convert.base64Decode(
    'ChJFeHBlY3RlZE1vZGVsRmlsZXMSOQoFZmlsZXMYASADKAsyIy5ydW5hbnl3aGVyZS52MS5Nb2'
    'RlbEZpbGVEZXNjcmlwdG9yUgVmaWxlcxIqCg5yb290X2RpcmVjdG9yeRgCIAEoCUgAUg1yb290'
    'RGlyZWN0b3J5iAEBEisKEXJlcXVpcmVkX3BhdHRlcm5zGAMgAygJUhByZXF1aXJlZFBhdHRlcm'
    '5zEisKEW9wdGlvbmFsX3BhdHRlcm5zGAQgAygJUhBvcHRpb25hbFBhdHRlcm5zEiUKC2Rlc2Ny'
    'aXB0aW9uGAUgASgJSAFSC2Rlc2NyaXB0aW9uiAEBQhEKD19yb290X2RpcmVjdG9yeUIOCgxfZG'
    'VzY3JpcHRpb24=');

@$core.Deprecated('Use modelQueryDescriptor instead')
const ModelQuery$json = {
  '1': 'ModelQuery',
  '2': [
    {'1': 'framework', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 0, '10': 'framework', '17': true},
    {'1': 'category', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '9': 1, '10': 'category', '17': true},
    {'1': 'format', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelFormat', '9': 2, '10': 'format', '17': true},
    {'1': 'downloaded_only', '3': 4, '4': 1, '5': 8, '9': 3, '10': 'downloadedOnly', '17': true},
    {'1': 'available_only', '3': 5, '4': 1, '5': 8, '9': 4, '10': 'availableOnly', '17': true},
    {'1': 'max_size_bytes', '3': 6, '4': 1, '5': 3, '9': 5, '10': 'maxSizeBytes', '17': true},
    {'1': 'search_query', '3': 7, '4': 1, '5': 9, '10': 'searchQuery'},
    {'1': 'source', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelSource', '9': 6, '10': 'source', '17': true},
    {'1': 'sort_field', '3': 9, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelQuerySortField', '9': 7, '10': 'sortField', '17': true},
    {'1': 'sort_order', '3': 10, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelQuerySortOrder', '9': 8, '10': 'sortOrder', '17': true},
  ],
  '8': [
    {'1': '_framework'},
    {'1': '_category'},
    {'1': '_format'},
    {'1': '_downloaded_only'},
    {'1': '_available_only'},
    {'1': '_max_size_bytes'},
    {'1': '_source'},
    {'1': '_sort_field'},
    {'1': '_sort_order'},
  ],
};

/// Descriptor for `ModelQuery`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelQueryDescriptor = $convert.base64Decode(
    'CgpNb2RlbFF1ZXJ5EkUKCWZyYW1ld29yaxgBIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW'
    '5jZUZyYW1ld29ya0gAUglmcmFtZXdvcmuIAQESPgoIY2F0ZWdvcnkYAiABKA4yHS5ydW5hbnl3'
    'aGVyZS52MS5Nb2RlbENhdGVnb3J5SAFSCGNhdGVnb3J5iAEBEjgKBmZvcm1hdBgDIAEoDjIbLn'
    'J1bmFueXdoZXJlLnYxLk1vZGVsRm9ybWF0SAJSBmZvcm1hdIgBARIsCg9kb3dubG9hZGVkX29u'
    'bHkYBCABKAhIA1IOZG93bmxvYWRlZE9ubHmIAQESKgoOYXZhaWxhYmxlX29ubHkYBSABKAhIBF'
    'INYXZhaWxhYmxlT25seYgBARIpCg5tYXhfc2l6ZV9ieXRlcxgGIAEoA0gFUgxtYXhTaXplQnl0'
    'ZXOIAQESIQoMc2VhcmNoX3F1ZXJ5GAcgASgJUgtzZWFyY2hRdWVyeRI4CgZzb3VyY2UYCCABKA'
    '4yGy5ydW5hbnl3aGVyZS52MS5Nb2RlbFNvdXJjZUgGUgZzb3VyY2WIAQESRwoKc29ydF9maWVs'
    'ZBgJIAEoDjIjLnJ1bmFueXdoZXJlLnYxLk1vZGVsUXVlcnlTb3J0RmllbGRIB1IJc29ydEZpZW'
    'xkiAEBEkcKCnNvcnRfb3JkZXIYCiABKA4yIy5ydW5hbnl3aGVyZS52MS5Nb2RlbFF1ZXJ5U29y'
    'dE9yZGVySAhSCXNvcnRPcmRlcogBAUIMCgpfZnJhbWV3b3JrQgsKCV9jYXRlZ29yeUIJCgdfZm'
    '9ybWF0QhIKEF9kb3dubG9hZGVkX29ubHlCEQoPX2F2YWlsYWJsZV9vbmx5QhEKD19tYXhfc2l6'
    'ZV9ieXRlc0IJCgdfc291cmNlQg0KC19zb3J0X2ZpZWxkQg0KC19zb3J0X29yZGVy');

@$core.Deprecated('Use modelCompatibilityResultDescriptor instead')
const ModelCompatibilityResult$json = {
  '1': 'ModelCompatibilityResult',
  '2': [
    {'1': 'is_compatible', '3': 1, '4': 1, '5': 8, '10': 'isCompatible'},
    {'1': 'can_run', '3': 2, '4': 1, '5': 8, '10': 'canRun'},
    {'1': 'can_fit', '3': 3, '4': 1, '5': 8, '10': 'canFit'},
    {'1': 'required_memory_bytes', '3': 4, '4': 1, '5': 3, '10': 'requiredMemoryBytes'},
    {'1': 'available_memory_bytes', '3': 5, '4': 1, '5': 3, '10': 'availableMemoryBytes'},
    {'1': 'required_storage_bytes', '3': 6, '4': 1, '5': 3, '10': 'requiredStorageBytes'},
    {'1': 'available_storage_bytes', '3': 7, '4': 1, '5': 3, '10': 'availableStorageBytes'},
    {'1': 'reasons', '3': 8, '4': 3, '5': 9, '10': 'reasons'},
  ],
};

/// Descriptor for `ModelCompatibilityResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelCompatibilityResultDescriptor = $convert.base64Decode(
    'ChhNb2RlbENvbXBhdGliaWxpdHlSZXN1bHQSIwoNaXNfY29tcGF0aWJsZRgBIAEoCFIMaXNDb2'
    '1wYXRpYmxlEhcKB2Nhbl9ydW4YAiABKAhSBmNhblJ1bhIXCgdjYW5fZml0GAMgASgIUgZjYW5G'
    'aXQSMgoVcmVxdWlyZWRfbWVtb3J5X2J5dGVzGAQgASgDUhNyZXF1aXJlZE1lbW9yeUJ5dGVzEj'
    'QKFmF2YWlsYWJsZV9tZW1vcnlfYnl0ZXMYBSABKANSFGF2YWlsYWJsZU1lbW9yeUJ5dGVzEjQK'
    'FnJlcXVpcmVkX3N0b3JhZ2VfYnl0ZXMYBiABKANSFHJlcXVpcmVkU3RvcmFnZUJ5dGVzEjYKF2'
    'F2YWlsYWJsZV9zdG9yYWdlX2J5dGVzGAcgASgDUhVhdmFpbGFibGVTdG9yYWdlQnl0ZXMSGAoH'
    'cmVhc29ucxgIIAMoCVIHcmVhc29ucw==');

@$core.Deprecated('Use modelRegistryRefreshRequestDescriptor instead')
const ModelRegistryRefreshRequest$json = {
  '1': 'ModelRegistryRefreshRequest',
  '2': [
    {'1': 'include_remote_catalog', '3': 1, '4': 1, '5': 8, '10': 'includeRemoteCatalog'},
    {'1': 'rescan_local', '3': 2, '4': 1, '5': 8, '10': 'rescanLocal'},
    {'1': 'prune_orphans', '3': 3, '4': 1, '5': 8, '10': 'pruneOrphans'},
    {'1': 'query', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelQuery', '9': 0, '10': 'query', '17': true},
  ],
  '8': [
    {'1': '_query'},
  ],
};

/// Descriptor for `ModelRegistryRefreshRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelRegistryRefreshRequestDescriptor = $convert.base64Decode(
    'ChtNb2RlbFJlZ2lzdHJ5UmVmcmVzaFJlcXVlc3QSNAoWaW5jbHVkZV9yZW1vdGVfY2F0YWxvZx'
    'gBIAEoCFIUaW5jbHVkZVJlbW90ZUNhdGFsb2cSIQoMcmVzY2FuX2xvY2FsGAIgASgIUgtyZXNj'
    'YW5Mb2NhbBIjCg1wcnVuZV9vcnBoYW5zGAMgASgIUgxwcnVuZU9ycGhhbnMSNQoFcXVlcnkYBC'
    'ABKAsyGi5ydW5hbnl3aGVyZS52MS5Nb2RlbFF1ZXJ5SABSBXF1ZXJ5iAEBQggKBl9xdWVyeQ==');

@$core.Deprecated('Use modelRegistryRefreshResultDescriptor instead')
const ModelRegistryRefreshResult$json = {
  '1': 'ModelRegistryRefreshResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'models', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfoList', '10': 'models'},
    {'1': 'registered_count', '3': 3, '4': 1, '5': 5, '10': 'registeredCount'},
    {'1': 'updated_count', '3': 4, '4': 1, '5': 5, '10': 'updatedCount'},
    {'1': 'discovered_count', '3': 5, '4': 1, '5': 5, '10': 'discoveredCount'},
    {'1': 'pruned_count', '3': 6, '4': 1, '5': 5, '10': 'prunedCount'},
    {'1': 'refreshed_at_unix_ms', '3': 7, '4': 1, '5': 3, '10': 'refreshedAtUnixMs'},
    {'1': 'warnings', '3': 8, '4': 3, '5': 9, '10': 'warnings'},
    {'1': 'error_message', '3': 9, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ModelRegistryRefreshResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelRegistryRefreshResultDescriptor = $convert.base64Decode(
    'ChpNb2RlbFJlZ2lzdHJ5UmVmcmVzaFJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEj'
    'UKBm1vZGVscxgCIAEoCzIdLnJ1bmFueXdoZXJlLnYxLk1vZGVsSW5mb0xpc3RSBm1vZGVscxIp'
    'ChByZWdpc3RlcmVkX2NvdW50GAMgASgFUg9yZWdpc3RlcmVkQ291bnQSIwoNdXBkYXRlZF9jb3'
    'VudBgEIAEoBVIMdXBkYXRlZENvdW50EikKEGRpc2NvdmVyZWRfY291bnQYBSABKAVSD2Rpc2Nv'
    'dmVyZWRDb3VudBIhCgxwcnVuZWRfY291bnQYBiABKAVSC3BydW5lZENvdW50Ei8KFHJlZnJlc2'
    'hlZF9hdF91bml4X21zGAcgASgDUhFyZWZyZXNoZWRBdFVuaXhNcxIaCgh3YXJuaW5ncxgIIAMo'
    'CVIId2FybmluZ3MSIwoNZXJyb3JfbWVzc2FnZRgJIAEoCVIMZXJyb3JNZXNzYWdl');

@$core.Deprecated('Use modelListRequestDescriptor instead')
const ModelListRequest$json = {
  '1': 'ModelListRequest',
  '2': [
    {'1': 'query', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelQuery', '9': 0, '10': 'query', '17': true},
  ],
  '8': [
    {'1': '_query'},
  ],
};

/// Descriptor for `ModelListRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelListRequestDescriptor = $convert.base64Decode(
    'ChBNb2RlbExpc3RSZXF1ZXN0EjUKBXF1ZXJ5GAEgASgLMhoucnVuYW55d2hlcmUudjEuTW9kZW'
    'xRdWVyeUgAUgVxdWVyeYgBAUIICgZfcXVlcnk=');

@$core.Deprecated('Use modelListResultDescriptor instead')
const ModelListResult$json = {
  '1': 'ModelListResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'models', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfoList', '10': 'models'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ModelListResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelListResultDescriptor = $convert.base64Decode(
    'Cg9Nb2RlbExpc3RSZXN1bHQSGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2VzcxI1CgZtb2RlbHMYAi'
    'ABKAsyHS5ydW5hbnl3aGVyZS52MS5Nb2RlbEluZm9MaXN0UgZtb2RlbHMSIwoNZXJyb3JfbWVz'
    'c2FnZRgDIAEoCVIMZXJyb3JNZXNzYWdl');

@$core.Deprecated('Use modelGetRequestDescriptor instead')
const ModelGetRequest$json = {
  '1': 'ModelGetRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
  ],
};

/// Descriptor for `ModelGetRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelGetRequestDescriptor = $convert.base64Decode(
    'Cg9Nb2RlbEdldFJlcXVlc3QSGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQ=');

@$core.Deprecated('Use modelGetResultDescriptor instead')
const ModelGetResult$json = {
  '1': 'ModelGetResult',
  '2': [
    {'1': 'found', '3': 1, '4': 1, '5': 8, '10': 'found'},
    {'1': 'model', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfo', '10': 'model'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ModelGetResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelGetResultDescriptor = $convert.base64Decode(
    'Cg5Nb2RlbEdldFJlc3VsdBIUCgVmb3VuZBgBIAEoCFIFZm91bmQSLwoFbW9kZWwYAiABKAsyGS'
    '5ydW5hbnl3aGVyZS52MS5Nb2RlbEluZm9SBW1vZGVsEiMKDWVycm9yX21lc3NhZ2UYAyABKAlS'
    'DGVycm9yTWVzc2FnZQ==');

@$core.Deprecated('Use modelImportRequestDescriptor instead')
const ModelImportRequest$json = {
  '1': 'ModelImportRequest',
  '2': [
    {'1': 'model', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfo', '9': 0, '10': 'model', '17': true},
    {'1': 'source_path', '3': 2, '4': 1, '5': 9, '10': 'sourcePath'},
    {'1': 'copy_into_managed_storage', '3': 3, '4': 1, '5': 8, '10': 'copyIntoManagedStorage'},
    {'1': 'overwrite_existing', '3': 4, '4': 1, '5': 8, '10': 'overwriteExisting'},
    {'1': 'files', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelFileDescriptor', '10': 'files'},
  ],
  '8': [
    {'1': '_model'},
  ],
};

/// Descriptor for `ModelImportRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelImportRequestDescriptor = $convert.base64Decode(
    'ChJNb2RlbEltcG9ydFJlcXVlc3QSNAoFbW9kZWwYASABKAsyGS5ydW5hbnl3aGVyZS52MS5Nb2'
    'RlbEluZm9IAFIFbW9kZWyIAQESHwoLc291cmNlX3BhdGgYAiABKAlSCnNvdXJjZVBhdGgSOQoZ'
    'Y29weV9pbnRvX21hbmFnZWRfc3RvcmFnZRgDIAEoCFIWY29weUludG9NYW5hZ2VkU3RvcmFnZR'
    'ItChJvdmVyd3JpdGVfZXhpc3RpbmcYBCABKAhSEW92ZXJ3cml0ZUV4aXN0aW5nEjkKBWZpbGVz'
    'GAUgAygLMiMucnVuYW55d2hlcmUudjEuTW9kZWxGaWxlRGVzY3JpcHRvclIFZmlsZXNCCAoGX2'
    '1vZGVs');

@$core.Deprecated('Use modelImportResultDescriptor instead')
const ModelImportResult$json = {
  '1': 'ModelImportResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'model', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfo', '10': 'model'},
    {'1': 'local_path', '3': 3, '4': 1, '5': 9, '10': 'localPath'},
    {'1': 'imported_bytes', '3': 4, '4': 1, '5': 3, '10': 'importedBytes'},
    {'1': 'warnings', '3': 5, '4': 3, '5': 9, '10': 'warnings'},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ModelImportResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelImportResultDescriptor = $convert.base64Decode(
    'ChFNb2RlbEltcG9ydFJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEi8KBW1vZGVsGA'
    'IgASgLMhkucnVuYW55d2hlcmUudjEuTW9kZWxJbmZvUgVtb2RlbBIdCgpsb2NhbF9wYXRoGAMg'
    'ASgJUglsb2NhbFBhdGgSJQoOaW1wb3J0ZWRfYnl0ZXMYBCABKANSDWltcG9ydGVkQnl0ZXMSGg'
    'oId2FybmluZ3MYBSADKAlSCHdhcm5pbmdzEiMKDWVycm9yX21lc3NhZ2UYBiABKAlSDGVycm9y'
    'TWVzc2FnZQ==');

@$core.Deprecated('Use modelDiscoveryRequestDescriptor instead')
const ModelDiscoveryRequest$json = {
  '1': 'ModelDiscoveryRequest',
  '2': [
    {'1': 'search_roots', '3': 1, '4': 3, '5': 9, '10': 'searchRoots'},
    {'1': 'recursive', '3': 2, '4': 1, '5': 8, '10': 'recursive'},
    {'1': 'link_downloaded', '3': 3, '4': 1, '5': 8, '10': 'linkDownloaded'},
    {'1': 'purge_invalid', '3': 4, '4': 1, '5': 8, '10': 'purgeInvalid'},
    {'1': 'query', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelQuery', '9': 0, '10': 'query', '17': true},
  ],
  '8': [
    {'1': '_query'},
  ],
};

/// Descriptor for `ModelDiscoveryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelDiscoveryRequestDescriptor = $convert.base64Decode(
    'ChVNb2RlbERpc2NvdmVyeVJlcXVlc3QSIQoMc2VhcmNoX3Jvb3RzGAEgAygJUgtzZWFyY2hSb2'
    '90cxIcCglyZWN1cnNpdmUYAiABKAhSCXJlY3Vyc2l2ZRInCg9saW5rX2Rvd25sb2FkZWQYAyAB'
    'KAhSDmxpbmtEb3dubG9hZGVkEiMKDXB1cmdlX2ludmFsaWQYBCABKAhSDHB1cmdlSW52YWxpZB'
    'I1CgVxdWVyeRgFIAEoCzIaLnJ1bmFueXdoZXJlLnYxLk1vZGVsUXVlcnlIAFIFcXVlcnmIAQFC'
    'CAoGX3F1ZXJ5');

@$core.Deprecated('Use discoveredModelDescriptor instead')
const DiscoveredModel$json = {
  '1': 'DiscoveredModel',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'local_path', '3': 2, '4': 1, '5': 9, '10': 'localPath'},
    {'1': 'matched_registry', '3': 3, '4': 1, '5': 8, '10': 'matchedRegistry'},
    {'1': 'model', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfo', '10': 'model'},
    {'1': 'size_bytes', '3': 5, '4': 1, '5': 3, '10': 'sizeBytes'},
    {'1': 'warnings', '3': 6, '4': 3, '5': 9, '10': 'warnings'},
  ],
};

/// Descriptor for `DiscoveredModel`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List discoveredModelDescriptor = $convert.base64Decode(
    'Cg9EaXNjb3ZlcmVkTW9kZWwSGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQSHQoKbG9jYWxfcG'
    'F0aBgCIAEoCVIJbG9jYWxQYXRoEikKEG1hdGNoZWRfcmVnaXN0cnkYAyABKAhSD21hdGNoZWRS'
    'ZWdpc3RyeRIvCgVtb2RlbBgEIAEoCzIZLnJ1bmFueXdoZXJlLnYxLk1vZGVsSW5mb1IFbW9kZW'
    'wSHQoKc2l6ZV9ieXRlcxgFIAEoA1IJc2l6ZUJ5dGVzEhoKCHdhcm5pbmdzGAYgAygJUgh3YXJu'
    'aW5ncw==');

@$core.Deprecated('Use modelDiscoveryResultDescriptor instead')
const ModelDiscoveryResult$json = {
  '1': 'ModelDiscoveryResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'discovered_models', '3': 2, '4': 3, '5': 11, '6': '.runanywhere.v1.DiscoveredModel', '10': 'discoveredModels'},
    {'1': 'linked_count', '3': 3, '4': 1, '5': 5, '10': 'linkedCount'},
    {'1': 'purged_count', '3': 4, '4': 1, '5': 5, '10': 'purgedCount'},
    {'1': 'warnings', '3': 5, '4': 3, '5': 9, '10': 'warnings'},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ModelDiscoveryResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelDiscoveryResultDescriptor = $convert.base64Decode(
    'ChRNb2RlbERpc2NvdmVyeVJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEkwKEWRpc2'
    'NvdmVyZWRfbW9kZWxzGAIgAygLMh8ucnVuYW55d2hlcmUudjEuRGlzY292ZXJlZE1vZGVsUhBk'
    'aXNjb3ZlcmVkTW9kZWxzEiEKDGxpbmtlZF9jb3VudBgDIAEoBVILbGlua2VkQ291bnQSIQoMcH'
    'VyZ2VkX2NvdW50GAQgASgFUgtwdXJnZWRDb3VudBIaCgh3YXJuaW5ncxgFIAMoCVIId2Fybmlu'
    'Z3MSIwoNZXJyb3JfbWVzc2FnZRgGIAEoCVIMZXJyb3JNZXNzYWdl');

@$core.Deprecated('Use modelLoadRequestDescriptor instead')
const ModelLoadRequest$json = {
  '1': 'ModelLoadRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'category', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '9': 0, '10': 'category', '17': true},
    {'1': 'framework', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 1, '10': 'framework', '17': true},
    {'1': 'force_reload', '3': 4, '4': 1, '5': 8, '10': 'forceReload'},
  ],
  '8': [
    {'1': '_category'},
    {'1': '_framework'},
  ],
};

/// Descriptor for `ModelLoadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelLoadRequestDescriptor = $convert.base64Decode(
    'ChBNb2RlbExvYWRSZXF1ZXN0EhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEj4KCGNhdGVnb3'
    'J5GAIgASgOMh0ucnVuYW55d2hlcmUudjEuTW9kZWxDYXRlZ29yeUgAUghjYXRlZ29yeYgBARJF'
    'CglmcmFtZXdvcmsYAyABKA4yIi5ydW5hbnl3aGVyZS52MS5JbmZlcmVuY2VGcmFtZXdvcmtIAV'
    'IJZnJhbWV3b3JriAEBEiEKDGZvcmNlX3JlbG9hZBgEIAEoCFILZm9yY2VSZWxvYWRCCwoJX2Nh'
    'dGVnb3J5QgwKCl9mcmFtZXdvcms=');

@$core.Deprecated('Use modelLoadResultDescriptor instead')
const ModelLoadResult$json = {
  '1': 'ModelLoadResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'category', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '10': 'category'},
    {'1': 'framework', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '10': 'framework'},
    {'1': 'resolved_path', '3': 5, '4': 1, '5': 9, '10': 'resolvedPath'},
    {'1': 'loaded_at_unix_ms', '3': 6, '4': 1, '5': 3, '10': 'loadedAtUnixMs'},
    {'1': 'error_message', '3': 7, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ModelLoadResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelLoadResultDescriptor = $convert.base64Decode(
    'Cg9Nb2RlbExvYWRSZXN1bHQSGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2VzcxIZCghtb2RlbF9pZB'
    'gCIAEoCVIHbW9kZWxJZBI5CghjYXRlZ29yeRgDIAEoDjIdLnJ1bmFueXdoZXJlLnYxLk1vZGVs'
    'Q2F0ZWdvcnlSCGNhdGVnb3J5EkAKCWZyYW1ld29yaxgEIAEoDjIiLnJ1bmFueXdoZXJlLnYxLk'
    'luZmVyZW5jZUZyYW1ld29ya1IJZnJhbWV3b3JrEiMKDXJlc29sdmVkX3BhdGgYBSABKAlSDHJl'
    'c29sdmVkUGF0aBIpChFsb2FkZWRfYXRfdW5peF9tcxgGIAEoA1IObG9hZGVkQXRVbml4TXMSIw'
    'oNZXJyb3JfbWVzc2FnZRgHIAEoCVIMZXJyb3JNZXNzYWdl');

@$core.Deprecated('Use modelUnloadRequestDescriptor instead')
const ModelUnloadRequest$json = {
  '1': 'ModelUnloadRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'category', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '9': 0, '10': 'category', '17': true},
    {'1': 'unload_all', '3': 3, '4': 1, '5': 8, '10': 'unloadAll'},
  ],
  '8': [
    {'1': '_category'},
  ],
};

/// Descriptor for `ModelUnloadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelUnloadRequestDescriptor = $convert.base64Decode(
    'ChJNb2RlbFVubG9hZFJlcXVlc3QSGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQSPgoIY2F0ZW'
    'dvcnkYAiABKA4yHS5ydW5hbnl3aGVyZS52MS5Nb2RlbENhdGVnb3J5SABSCGNhdGVnb3J5iAEB'
    'Eh0KCnVubG9hZF9hbGwYAyABKAhSCXVubG9hZEFsbEILCglfY2F0ZWdvcnk=');

@$core.Deprecated('Use modelUnloadResultDescriptor instead')
const ModelUnloadResult$json = {
  '1': 'ModelUnloadResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'unloaded_model_ids', '3': 2, '4': 3, '5': 9, '10': 'unloadedModelIds'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ModelUnloadResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelUnloadResultDescriptor = $convert.base64Decode(
    'ChFNb2RlbFVubG9hZFJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEiwKEnVubG9hZG'
    'VkX21vZGVsX2lkcxgCIAMoCVIQdW5sb2FkZWRNb2RlbElkcxIjCg1lcnJvcl9tZXNzYWdlGAMg'
    'ASgJUgxlcnJvck1lc3NhZ2U=');

@$core.Deprecated('Use currentModelRequestDescriptor instead')
const CurrentModelRequest$json = {
  '1': 'CurrentModelRequest',
  '2': [
    {'1': 'category', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '9': 0, '10': 'category', '17': true},
    {'1': 'framework', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 1, '10': 'framework', '17': true},
  ],
  '8': [
    {'1': '_category'},
    {'1': '_framework'},
  ],
};

/// Descriptor for `CurrentModelRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List currentModelRequestDescriptor = $convert.base64Decode(
    'ChNDdXJyZW50TW9kZWxSZXF1ZXN0Ej4KCGNhdGVnb3J5GAEgASgOMh0ucnVuYW55d2hlcmUudj'
    'EuTW9kZWxDYXRlZ29yeUgAUghjYXRlZ29yeYgBARJFCglmcmFtZXdvcmsYAiABKA4yIi5ydW5h'
    'bnl3aGVyZS52MS5JbmZlcmVuY2VGcmFtZXdvcmtIAVIJZnJhbWV3b3JriAEBQgsKCV9jYXRlZ2'
    '9yeUIMCgpfZnJhbWV3b3Jr');

@$core.Deprecated('Use currentModelResultDescriptor instead')
const CurrentModelResult$json = {
  '1': 'CurrentModelResult',
  '2': [
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'model', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfo', '10': 'model'},
    {'1': 'loaded_at_unix_ms', '3': 4, '4': 1, '5': 3, '10': 'loadedAtUnixMs'},
  ],
  '9': [
    {'1': 1, '2': 2},
  ],
  '10': ['has_model'],
};

/// Descriptor for `CurrentModelResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List currentModelResultDescriptor = $convert.base64Decode(
    'ChJDdXJyZW50TW9kZWxSZXN1bHQSGQoIbW9kZWxfaWQYAiABKAlSB21vZGVsSWQSLwoFbW9kZW'
    'wYAyABKAsyGS5ydW5hbnl3aGVyZS52MS5Nb2RlbEluZm9SBW1vZGVsEikKEWxvYWRlZF9hdF91'
    'bml4X21zGAQgASgDUg5sb2FkZWRBdFVuaXhNc0oECAEQAlIJaGFzX21vZGVs');

@$core.Deprecated('Use modelDeleteRequestDescriptor instead')
const ModelDeleteRequest$json = {
  '1': 'ModelDeleteRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'delete_files', '3': 2, '4': 1, '5': 8, '10': 'deleteFiles'},
    {'1': 'unregister', '3': 3, '4': 1, '5': 8, '10': 'unregister'},
    {'1': 'unload_if_loaded', '3': 4, '4': 1, '5': 8, '10': 'unloadIfLoaded'},
  ],
};

/// Descriptor for `ModelDeleteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelDeleteRequestDescriptor = $convert.base64Decode(
    'ChJNb2RlbERlbGV0ZVJlcXVlc3QSGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQSIQoMZGVsZX'
    'RlX2ZpbGVzGAIgASgIUgtkZWxldGVGaWxlcxIeCgp1bnJlZ2lzdGVyGAMgASgIUgp1bnJlZ2lz'
    'dGVyEigKEHVubG9hZF9pZl9sb2FkZWQYBCABKAhSDnVubG9hZElmTG9hZGVk');

@$core.Deprecated('Use modelDeleteResultDescriptor instead')
const ModelDeleteResult$json = {
  '1': 'ModelDeleteResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'deleted_bytes', '3': 3, '4': 1, '5': 3, '10': 'deletedBytes'},
    {'1': 'files_deleted', '3': 4, '4': 1, '5': 8, '10': 'filesDeleted'},
    {'1': 'registry_updated', '3': 5, '4': 1, '5': 8, '10': 'registryUpdated'},
    {'1': 'was_loaded', '3': 6, '4': 1, '5': 8, '10': 'wasLoaded'},
    {'1': 'error_message', '3': 7, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ModelDeleteResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelDeleteResultDescriptor = $convert.base64Decode(
    'ChFNb2RlbERlbGV0ZVJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEhkKCG1vZGVsX2'
    'lkGAIgASgJUgdtb2RlbElkEiMKDWRlbGV0ZWRfYnl0ZXMYAyABKANSDGRlbGV0ZWRCeXRlcxIj'
    'Cg1maWxlc19kZWxldGVkGAQgASgIUgxmaWxlc0RlbGV0ZWQSKQoQcmVnaXN0cnlfdXBkYXRlZB'
    'gFIAEoCFIPcmVnaXN0cnlVcGRhdGVkEh0KCndhc19sb2FkZWQYBiABKAhSCXdhc0xvYWRlZBIj'
    'Cg1lcnJvcl9tZXNzYWdlGAcgASgJUgxlcnJvck1lc3NhZ2U=');

