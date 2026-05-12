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

import 'thinking_tag_pattern.pbjson.dart' as $2;

@$core.Deprecated('Use audioFormatDescriptor instead')
const AudioFormat$json = {
  '1': 'AudioFormat',
  '2': [
    {'1': 'AUDIO_FORMAT_UNSPECIFIED', '2': 0, '3': {}},
    {'1': 'AUDIO_FORMAT_PCM', '2': 1, '3': {}},
    {'1': 'AUDIO_FORMAT_WAV', '2': 2, '3': {}},
    {'1': 'AUDIO_FORMAT_MP3', '2': 3, '3': {}},
    {'1': 'AUDIO_FORMAT_OPUS', '2': 4, '3': {}},
    {'1': 'AUDIO_FORMAT_AAC', '2': 5, '3': {}},
    {'1': 'AUDIO_FORMAT_FLAC', '2': 6, '3': {}},
    {'1': 'AUDIO_FORMAT_OGG', '2': 7, '3': {}},
    {'1': 'AUDIO_FORMAT_M4A', '2': 8, '3': {}},
    {'1': 'AUDIO_FORMAT_PCM_S16LE', '2': 9, '3': {}},
  ],
};

/// Descriptor for `AudioFormat`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List audioFormatDescriptor = $convert.base64Decode(
    'CgtBdWRpb0Zvcm1hdBItChhBVURJT19GT1JNQVRfVU5TUEVDSUZJRUQQABoP4rUYC3Vuc3BlY2'
    'lmaWVkEh0KEEFVRElPX0ZPUk1BVF9QQ00QARoH4rUYA3BjbRIdChBBVURJT19GT1JNQVRfV0FW'
    'EAIaB+K1GAN3YXYSHQoQQVVESU9fRk9STUFUX01QMxADGgfitRgDbXAzEh8KEUFVRElPX0ZPUk'
    '1BVF9PUFVTEAQaCOK1GARvcHVzEh0KEEFVRElPX0ZPUk1BVF9BQUMQBRoH4rUYA2FhYxIfChFB'
    'VURJT19GT1JNQVRfRkxBQxAGGgjitRgEZmxhYxIdChBBVURJT19GT1JNQVRfT0dHEAcaB+K1GA'
    'NvZ2cSHQoQQVVESU9fRk9STUFUX000QRAIGgfitRgDbTRhEikKFkFVRElPX0ZPUk1BVF9QQ01f'
    'UzE2TEUQCRoN4rUYCXBjbV9zMTZsZQ==');

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
    {'1': 'MODEL_CATEGORY_UNSPECIFIED', '2': 0, '3': {}},
    {'1': 'MODEL_CATEGORY_LANGUAGE', '2': 1, '3': {}},
    {'1': 'MODEL_CATEGORY_SPEECH_RECOGNITION', '2': 2, '3': {}},
    {'1': 'MODEL_CATEGORY_SPEECH_SYNTHESIS', '2': 3, '3': {}},
    {'1': 'MODEL_CATEGORY_VISION', '2': 4, '3': {}},
    {'1': 'MODEL_CATEGORY_IMAGE_GENERATION', '2': 5, '3': {}},
    {'1': 'MODEL_CATEGORY_MULTIMODAL', '2': 6, '3': {}},
    {'1': 'MODEL_CATEGORY_AUDIO', '2': 7, '3': {}},
    {'1': 'MODEL_CATEGORY_EMBEDDING', '2': 8, '3': {}},
    {'1': 'MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION', '2': 9, '3': {}},
  ],
};

/// Descriptor for `ModelCategory`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelCategoryDescriptor = $convert.base64Decode(
    'Cg1Nb2RlbENhdGVnb3J5Ei8KGk1PREVMX0NBVEVHT1JZX1VOU1BFQ0lGSUVEEAAaD+K1GAt1bn'
    'NwZWNpZmllZBIpChdNT0RFTF9DQVRFR09SWV9MQU5HVUFHRRABGgzitRgIbGFuZ3VhZ2USPQoh'
    'TU9ERUxfQ0FURUdPUllfU1BFRUNIX1JFQ09HTklUSU9OEAIaFuK1GBJzcGVlY2gtcmVjb2duaX'
    'Rpb24SOQofTU9ERUxfQ0FURUdPUllfU1BFRUNIX1NZTlRIRVNJUxADGhTitRgQc3BlZWNoLXN5'
    'bnRoZXNpcxIlChVNT0RFTF9DQVRFR09SWV9WSVNJT04QBBoK4rUYBnZpc2lvbhI5Ch9NT0RFTF'
    '9DQVRFR09SWV9JTUFHRV9HRU5FUkFUSU9OEAUaFOK1GBBpbWFnZS1nZW5lcmF0aW9uEi0KGU1P'
    'REVMX0NBVEVHT1JZX01VTFRJTU9EQUwQBhoO4rUYCm11bHRpbW9kYWwSIwoUTU9ERUxfQ0FURU'
    'dPUllfQVVESU8QBxoJ4rUYBWF1ZGlvEisKGE1PREVMX0NBVEVHT1JZX0VNQkVERElORxAIGg3i'
    'tRgJZW1iZWRkaW5nEkkKJ01PREVMX0NBVEVHT1JZX1ZPSUNFX0FDVElWSVRZX0RFVEVDVElPTh'
    'AJGhzitRgYdm9pY2UtYWN0aXZpdHktZGV0ZWN0aW9u');

@$core.Deprecated('Use sDKEnvironmentDescriptor instead')
const SDKEnvironment$json = {
  '1': 'SDKEnvironment',
  '2': [
    {'1': 'SDK_ENVIRONMENT_UNSPECIFIED', '2': 0, '3': {}},
    {'1': 'SDK_ENVIRONMENT_DEVELOPMENT', '2': 1, '3': {}},
    {'1': 'SDK_ENVIRONMENT_STAGING', '2': 2, '3': {}},
    {'1': 'SDK_ENVIRONMENT_PRODUCTION', '2': 3, '3': {}},
  ],
};

/// Descriptor for `SDKEnvironment`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sDKEnvironmentDescriptor = $convert.base64Decode(
    'Cg5TREtFbnZpcm9ubWVudBIwChtTREtfRU5WSVJPTk1FTlRfVU5TUEVDSUZJRUQQABoP4rUYC3'
    'Vuc3BlY2lmaWVkEjAKG1NES19FTlZJUk9OTUVOVF9ERVZFTE9QTUVOVBABGg/itRgLZGV2ZWxv'
    'cG1lbnQSKAoXU0RLX0VOVklST05NRU5UX1NUQUdJTkcQAhoL4rUYB3N0YWdpbmcSLgoaU0RLX0'
    'VOVklST05NRU5UX1BST0RVQ1RJT04QAxoO4rUYCnByb2R1Y3Rpb24=');

@$core.Deprecated('Use modelSourceDescriptor instead')
const ModelSource$json = {
  '1': 'ModelSource',
  '2': [
    {'1': 'MODEL_SOURCE_UNSPECIFIED', '2': 0, '3': {}},
    {'1': 'MODEL_SOURCE_REMOTE', '2': 1, '3': {}},
    {'1': 'MODEL_SOURCE_LOCAL', '2': 2, '3': {}},
    {'1': 'MODEL_SOURCE_BUILT_IN', '2': 3, '3': {}},
  ],
};

/// Descriptor for `ModelSource`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelSourceDescriptor = $convert.base64Decode(
    'CgtNb2RlbFNvdXJjZRItChhNT0RFTF9TT1VSQ0VfVU5TUEVDSUZJRUQQABoP4rUYC3Vuc3BlY2'
    'lmaWVkEiMKE01PREVMX1NPVVJDRV9SRU1PVEUQARoK4rUYBnJlbW90ZRIhChJNT0RFTF9TT1VS'
    'Q0VfTE9DQUwQAhoJ4rUYBWxvY2FsEicKFU1PREVMX1NPVVJDRV9CVUlMVF9JThADGgzitRgIYn'
    'VpbHQtaW4=');

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
    {'1': 'ARCHIVE_STRUCTURE_UNSPECIFIED', '2': 0, '3': {}},
    {'1': 'ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED', '2': 1, '3': {}},
    {'1': 'ARCHIVE_STRUCTURE_DIRECTORY_BASED', '2': 2, '3': {}},
    {'1': 'ARCHIVE_STRUCTURE_NESTED_DIRECTORY', '2': 3, '3': {}},
    {'1': 'ARCHIVE_STRUCTURE_UNKNOWN', '2': 4, '3': {}},
  ],
};

/// Descriptor for `ArchiveStructure`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List archiveStructureDescriptor = $convert.base64Decode(
    'ChBBcmNoaXZlU3RydWN0dXJlEjIKHUFSQ0hJVkVfU1RSVUNUVVJFX1VOU1BFQ0lGSUVEEAAaD+'
    'K1GAt1bnNwZWNpZmllZBI+CiRBUkNISVZFX1NUUlVDVFVSRV9TSU5HTEVfRklMRV9ORVNURUQQ'
    'ARoU4rUYEHNpbmdsZUZpbGVOZXN0ZWQSOQohQVJDSElWRV9TVFJVQ1RVUkVfRElSRUNUT1JZX0'
    'JBU0VEEAIaEuK1GA5kaXJlY3RvcnlCYXNlZBI7CiJBUkNISVZFX1NUUlVDVFVSRV9ORVNURURf'
    'RElSRUNUT1JZEAMaE+K1GA9uZXN0ZWREaXJlY3RvcnkSKgoZQVJDSElWRV9TVFJVQ1RVUkVfVU'
    '5LTk9XThAEGgvitRgHdW5rbm93bg==');

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
    {'1': 'MODEL_ARTIFACT_TYPE_ARCHIVE', '2': 6},
    {'1': 'MODEL_ARTIFACT_TYPE_MULTI_FILE', '2': 7},
    {'1': 'MODEL_ARTIFACT_TYPE_BUILT_IN', '2': 8},
    {'1': 'MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE', '2': 9},
    {'1': 'MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE', '2': 10},
  ],
};

/// Descriptor for `ModelArtifactType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelArtifactTypeDescriptor = $convert.base64Decode(
    'ChFNb2RlbEFydGlmYWN0VHlwZRIjCh9NT0RFTF9BUlRJRkFDVF9UWVBFX1VOU1BFQ0lGSUVEEA'
    'ASIwofTU9ERUxfQVJUSUZBQ1RfVFlQRV9TSU5HTEVfRklMRRABEiYKIk1PREVMX0FSVElGQUNU'
    'X1RZUEVfVEFSX0daX0FSQ0hJVkUQAhIhCh1NT0RFTF9BUlRJRkFDVF9UWVBFX0RJUkVDVE9SWR'
    'ADEiMKH01PREVMX0FSVElGQUNUX1RZUEVfWklQX0FSQ0hJVkUQBBIeChpNT0RFTF9BUlRJRkFD'
    'VF9UWVBFX0NVU1RPTRAFEh8KG01PREVMX0FSVElGQUNUX1RZUEVfQVJDSElWRRAGEiIKHk1PRE'
    'VMX0FSVElGQUNUX1RZUEVfTVVMVElfRklMRRAHEiAKHE1PREVMX0FSVElGQUNUX1RZUEVfQlVJ'
    'TFRfSU4QCBInCiNNT0RFTF9BUlRJRkFDVF9UWVBFX1RBUl9CWjJfQVJDSElWRRAJEiYKIk1PRE'
    'VMX0FSVElGQUNUX1RZUEVfVEFSX1haX0FSQ0hJVkUQCg==');

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
    {'1': 'thinking_pattern', '3': 18, '4': 1, '5': 11, '6': '.runanywhere.v1.ThinkingTagPattern', '9': 3, '10': 'thinkingPattern', '17': true},
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
    'IOY2hlY2tzdW1TaGEyNTaIAQESUgoQdGhpbmtpbmdfcGF0dGVybhgSIAEoCzIiLnJ1bmFueXdo'
    'ZXJlLnYxLlRoaW5raW5nVGFnUGF0dGVybkgDUg90aGlua2luZ1BhdHRlcm6IAQESQgoIbWV0YW'
    'RhdGEYEyABKAsyIS5ydW5hbnl3aGVyZS52MS5Nb2RlbEluZm9NZXRhZGF0YUgEUghtZXRhZGF0'
    'YYgBARJFCgtzaW5nbGVfZmlsZRgUIAEoCzIiLnJ1bmFueXdoZXJlLnYxLlNpbmdsZUZpbGVBcn'
    'RpZmFjdEgAUgpzaW5nbGVGaWxlEjsKB2FyY2hpdmUYFSABKAsyHy5ydW5hbnl3aGVyZS52MS5B'
    'cmNoaXZlQXJ0aWZhY3RIAFIHYXJjaGl2ZRJCCgptdWx0aV9maWxlGBYgASgLMiEucnVuYW55d2'
    'hlcmUudjEuTXVsdGlGaWxlQXJ0aWZhY3RIAFIJbXVsdGlGaWxlEi4KEmN1c3RvbV9zdHJhdGVn'
    'eV9pZBgXIAEoCUgAUhBjdXN0b21TdHJhdGVneUlkEhsKCGJ1aWx0X2luGBggASgISABSB2J1aW'
    'x0SW4SSwoNYXJ0aWZhY3RfdHlwZRgZIAEoDjIhLnJ1bmFueXdoZXJlLnYxLk1vZGVsQXJ0aWZh'
    'Y3RUeXBlSAVSDGFydGlmYWN0VHlwZYgBARJOCg5leHBlY3RlZF9maWxlcxgaIAEoCzIiLnJ1bm'
    'FueXdoZXJlLnYxLkV4cGVjdGVkTW9kZWxGaWxlc0gGUg1leHBlY3RlZEZpbGVziAEBEmQKF2Fj'
    'Y2VsZXJhdGlvbl9wcmVmZXJlbmNlGBsgASgOMiYucnVuYW55d2hlcmUudjEuQWNjZWxlcmF0aW'
    '9uUHJlZmVyZW5jZUgHUhZhY2NlbGVyYXRpb25QcmVmZXJlbmNliAEBEkkKDnJvdXRpbmdfcG9s'
    'aWN5GBwgASgOMh0ucnVuYW55d2hlcmUudjEuUm91dGluZ1BvbGljeUgIUg1yb3V0aW5nUG9saW'
    'N5iAEBElQKDWNvbXBhdGliaWxpdHkYHSABKAsyKS5ydW5hbnl3aGVyZS52MS5Nb2RlbFJ1bnRp'
    'bWVDb21wYXRpYmlsaXR5SAlSDWNvbXBhdGliaWxpdHmIAQESWAoTcHJlZmVycmVkX2ZyYW1ld2'
    '9yaxgeIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW5jZUZyYW1ld29ya0gKUhJwcmVmZXJy'
    'ZWRGcmFtZXdvcmuIAQESUQoPcmVnaXN0cnlfc3RhdHVzGB8gASgOMiMucnVuYW55d2hlcmUudj'
    'EuTW9kZWxSZWdpc3RyeVN0YXR1c0gLUg5yZWdpc3RyeVN0YXR1c4gBARIoCg1pc19kb3dubG9h'
    'ZGVkGCAgASgISAxSDGlzRG93bmxvYWRlZIgBARImCgxpc19hdmFpbGFibGUYISABKAhIDVILaX'
    'NBdmFpbGFibGWIAQESMwoUbGFzdF91c2VkX2F0X3VuaXhfbXMYIiABKANIDlIQbGFzdFVzZWRB'
    'dFVuaXhNc4gBARIkCgt1c2FnZV9jb3VudBgjIAEoBUgPUgp1c2FnZUNvdW50iAEBEiYKDHN5bm'
    'NfcGVuZGluZxgkIAEoCEgQUgtzeW5jUGVuZGluZ4gBARIqCg5zdGF0dXNfbWVzc2FnZRglIAEo'
    'CUgRUg1zdGF0dXNNZXNzYWdliAEBQgoKCGFydGlmYWN0QhgKFl9tZW1vcnlfcmVxdWlyZWRfYn'
    'l0ZXNCEgoQX2NoZWNrc3VtX3NoYTI1NkITChFfdGhpbmtpbmdfcGF0dGVybkILCglfbWV0YWRh'
    'dGFCEAoOX2FydGlmYWN0X3R5cGVCEQoPX2V4cGVjdGVkX2ZpbGVzQhoKGF9hY2NlbGVyYXRpb2'
    '5fcHJlZmVyZW5jZUIRCg9fcm91dGluZ19wb2xpY3lCEAoOX2NvbXBhdGliaWxpdHlCFgoUX3By'
    'ZWZlcnJlZF9mcmFtZXdvcmtCEgoQX3JlZ2lzdHJ5X3N0YXR1c0IQCg5faXNfZG93bmxvYWRlZE'
    'IPCg1faXNfYXZhaWxhYmxlQhcKFV9sYXN0X3VzZWRfYXRfdW5peF9tc0IOCgxfdXNhZ2VfY291'
    'bnRCDwoNX3N5bmNfcGVuZGluZ0IRCg9fc3RhdHVzX21lc3NhZ2U=');

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
    {'1': 'expected_files', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.ExpectedModelFiles', '9': 0, '10': 'expectedFiles', '17': true},
  ],
  '8': [
    {'1': '_expected_files'},
  ],
};

/// Descriptor for `SingleFileArtifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List singleFileArtifactDescriptor = $convert.base64Decode(
    'ChJTaW5nbGVGaWxlQXJ0aWZhY3QSKwoRcmVxdWlyZWRfcGF0dGVybnMYASADKAlSEHJlcXVpcm'
    'VkUGF0dGVybnMSKwoRb3B0aW9uYWxfcGF0dGVybnMYAiADKAlSEG9wdGlvbmFsUGF0dGVybnMS'
    'TgoOZXhwZWN0ZWRfZmlsZXMYAyABKAsyIi5ydW5hbnl3aGVyZS52MS5FeHBlY3RlZE1vZGVsRm'
    'lsZXNIAFINZXhwZWN0ZWRGaWxlc4gBAUIRCg9fZXhwZWN0ZWRfZmlsZXM=');

@$core.Deprecated('Use archiveArtifactDescriptor instead')
const ArchiveArtifact$json = {
  '1': 'ArchiveArtifact',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ArchiveType', '10': 'type'},
    {'1': 'structure', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ArchiveStructure', '10': 'structure'},
    {'1': 'required_patterns', '3': 3, '4': 3, '5': 9, '10': 'requiredPatterns'},
    {'1': 'optional_patterns', '3': 4, '4': 3, '5': 9, '10': 'optionalPatterns'},
    {'1': 'expected_files', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.ExpectedModelFiles', '9': 0, '10': 'expectedFiles', '17': true},
  ],
  '8': [
    {'1': '_expected_files'},
  ],
};

/// Descriptor for `ArchiveArtifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List archiveArtifactDescriptor = $convert.base64Decode(
    'Cg9BcmNoaXZlQXJ0aWZhY3QSLwoEdHlwZRgBIAEoDjIbLnJ1bmFueXdoZXJlLnYxLkFyY2hpdm'
    'VUeXBlUgR0eXBlEj4KCXN0cnVjdHVyZRgCIAEoDjIgLnJ1bmFueXdoZXJlLnYxLkFyY2hpdmVT'
    'dHJ1Y3R1cmVSCXN0cnVjdHVyZRIrChFyZXF1aXJlZF9wYXR0ZXJucxgDIAMoCVIQcmVxdWlyZW'
    'RQYXR0ZXJucxIrChFvcHRpb25hbF9wYXR0ZXJucxgEIAMoCVIQb3B0aW9uYWxQYXR0ZXJucxJO'
    'Cg5leHBlY3RlZF9maWxlcxgFIAEoCzIiLnJ1bmFueXdoZXJlLnYxLkV4cGVjdGVkTW9kZWxGaW'
    'xlc0gAUg1leHBlY3RlZEZpbGVziAEBQhEKD19leHBlY3RlZF9maWxlcw==');

@$core.Deprecated('Use modelFileDescriptorDescriptor instead')
const ModelFileDescriptor$json = {
  '1': 'ModelFileDescriptor',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'filename', '3': 2, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'is_required', '3': 3, '4': 1, '5': 8, '10': 'isRequired'},
    {'1': 'size_bytes', '3': 4, '4': 1, '5': 3, '9': 0, '10': 'sizeBytes', '17': true},
    {'1': 'relative_path', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'relativePath', '17': true},
    {'1': 'destination_path', '3': 7, '4': 1, '5': 9, '9': 2, '10': 'destinationPath', '17': true},
    {'1': 'role', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelFileRole', '9': 3, '10': 'role', '17': true},
    {'1': 'local_path', '3': 9, '4': 1, '5': 9, '9': 4, '10': 'localPath', '17': true},
    {'1': 'checksum_sha256', '3': 10, '4': 1, '5': 9, '9': 5, '10': 'checksumSha256', '17': true},
  ],
  '8': [
    {'1': '_size_bytes'},
    {'1': '_relative_path'},
    {'1': '_destination_path'},
    {'1': '_role'},
    {'1': '_local_path'},
    {'1': '_checksum_sha256'},
  ],
  '9': [
    {'1': 5, '2': 6},
  ],
  '10': ['checksum'],
};

/// Descriptor for `ModelFileDescriptor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelFileDescriptorDescriptor = $convert.base64Decode(
    'ChNNb2RlbEZpbGVEZXNjcmlwdG9yEhAKA3VybBgBIAEoCVIDdXJsEhoKCGZpbGVuYW1lGAIgAS'
    'gJUghmaWxlbmFtZRIfCgtpc19yZXF1aXJlZBgDIAEoCFIKaXNSZXF1aXJlZBIiCgpzaXplX2J5'
    'dGVzGAQgASgDSABSCXNpemVCeXRlc4gBARIoCg1yZWxhdGl2ZV9wYXRoGAYgASgJSAFSDHJlbG'
    'F0aXZlUGF0aIgBARIuChBkZXN0aW5hdGlvbl9wYXRoGAcgASgJSAJSD2Rlc3RpbmF0aW9uUGF0'
    'aIgBARI2CgRyb2xlGAggASgOMh0ucnVuYW55d2hlcmUudjEuTW9kZWxGaWxlUm9sZUgDUgRyb2'
    'xliAEBEiIKCmxvY2FsX3BhdGgYCSABKAlIBFIJbG9jYWxQYXRoiAEBEiwKD2NoZWNrc3VtX3No'
    'YTI1NhgKIAEoCUgFUg5jaGVja3N1bVNoYTI1NogBAUINCgtfc2l6ZV9ieXRlc0IQCg5fcmVsYX'
    'RpdmVfcGF0aEITChFfZGVzdGluYXRpb25fcGF0aEIHCgVfcm9sZUINCgtfbG9jYWxfcGF0aEIS'
    'ChBfY2hlY2tzdW1fc2hhMjU2SgQIBRAGUghjaGVja3N1bQ==');

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
    {'1': 'registry_status', '3': 11, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelRegistryStatus', '9': 9, '10': 'registryStatus', '17': true},
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
    {'1': '_registry_status'},
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
    'dE9yZGVySAhSCXNvcnRPcmRlcogBARJRCg9yZWdpc3RyeV9zdGF0dXMYCyABKA4yIy5ydW5hbn'
    'l3aGVyZS52MS5Nb2RlbFJlZ2lzdHJ5U3RhdHVzSAlSDnJlZ2lzdHJ5U3RhdHVziAEBQgwKCl9m'
    'cmFtZXdvcmtCCwoJX2NhdGVnb3J5QgkKB19mb3JtYXRCEgoQX2Rvd25sb2FkZWRfb25seUIRCg'
    '9fYXZhaWxhYmxlX29ubHlCEQoPX21heF9zaXplX2J5dGVzQgkKB19zb3VyY2VCDQoLX3NvcnRf'
    'ZmllbGRCDQoLX3NvcnRfb3JkZXJCEgoQX3JlZ2lzdHJ5X3N0YXR1cw==');

@$core.Deprecated('Use modelRegistryRefreshRequestDescriptor instead')
const ModelRegistryRefreshRequest$json = {
  '1': 'ModelRegistryRefreshRequest',
  '2': [
    {'1': 'include_remote_catalog', '3': 1, '4': 1, '5': 8, '10': 'includeRemoteCatalog'},
    {'1': 'rescan_local', '3': 2, '4': 1, '5': 8, '10': 'rescanLocal'},
    {'1': 'prune_orphans', '3': 3, '4': 1, '5': 8, '10': 'pruneOrphans'},
    {'1': 'query', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelQuery', '9': 0, '10': 'query', '17': true},
    {'1': 'catalog_uri', '3': 5, '4': 1, '5': 9, '10': 'catalogUri'},
    {'1': 'force_refresh', '3': 6, '4': 1, '5': 8, '10': 'forceRefresh'},
    {'1': 'include_downloaded_state', '3': 7, '4': 1, '5': 8, '10': 'includeDownloadedState'},
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
    'ABKAsyGi5ydW5hbnl3aGVyZS52MS5Nb2RlbFF1ZXJ5SABSBXF1ZXJ5iAEBEh8KC2NhdGFsb2df'
    'dXJpGAUgASgJUgpjYXRhbG9nVXJpEiMKDWZvcmNlX3JlZnJlc2gYBiABKAhSDGZvcmNlUmVmcm'
    'VzaBI4ChhpbmNsdWRlX2Rvd25sb2FkZWRfc3RhdGUYByABKAhSFmluY2x1ZGVEb3dubG9hZGVk'
    'U3RhdGVCCAoGX3F1ZXJ5');

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
    {'1': 'downloaded_count', '3': 10, '4': 1, '5': 5, '10': 'downloadedCount'},
    {'1': 'available_count', '3': 11, '4': 1, '5': 5, '10': 'availableCount'},
    {'1': 'error_count', '3': 12, '4': 1, '5': 5, '10': 'errorCount'},
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
    'CVIId2FybmluZ3MSIwoNZXJyb3JfbWVzc2FnZRgJIAEoCVIMZXJyb3JNZXNzYWdlEikKEGRvd2'
    '5sb2FkZWRfY291bnQYCiABKAVSD2Rvd25sb2FkZWRDb3VudBInCg9hdmFpbGFibGVfY291bnQY'
    'CyABKAVSDmF2YWlsYWJsZUNvdW50Eh8KC2Vycm9yX2NvdW50GAwgASgFUgplcnJvckNvdW50');

@$core.Deprecated('Use modelListRequestDescriptor instead')
const ModelListRequest$json = {
  '1': 'ModelListRequest',
  '2': [
    {'1': 'query', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelQuery', '9': 0, '10': 'query', '17': true},
    {'1': 'include_counts', '3': 2, '4': 1, '5': 8, '10': 'includeCounts'},
  ],
  '8': [
    {'1': '_query'},
  ],
};

/// Descriptor for `ModelListRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelListRequestDescriptor = $convert.base64Decode(
    'ChBNb2RlbExpc3RSZXF1ZXN0EjUKBXF1ZXJ5GAEgASgLMhoucnVuYW55d2hlcmUudjEuTW9kZW'
    'xRdWVyeUgAUgVxdWVyeYgBARIlCg5pbmNsdWRlX2NvdW50cxgCIAEoCFINaW5jbHVkZUNvdW50'
    'c0IICgZfcXVlcnk=');

@$core.Deprecated('Use modelListResultDescriptor instead')
const ModelListResult$json = {
  '1': 'ModelListResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'models', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfoList', '10': 'models'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '10': 'errorMessage'},
    {'1': 'total_count', '3': 4, '4': 1, '5': 5, '10': 'totalCount'},
    {'1': 'downloaded_count', '3': 5, '4': 1, '5': 5, '10': 'downloadedCount'},
    {'1': 'available_count', '3': 6, '4': 1, '5': 5, '10': 'availableCount'},
    {'1': 'filtered_count', '3': 7, '4': 1, '5': 5, '10': 'filteredCount'},
  ],
};

/// Descriptor for `ModelListResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelListResultDescriptor = $convert.base64Decode(
    'Cg9Nb2RlbExpc3RSZXN1bHQSGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2VzcxI1CgZtb2RlbHMYAi'
    'ABKAsyHS5ydW5hbnl3aGVyZS52MS5Nb2RlbEluZm9MaXN0UgZtb2RlbHMSIwoNZXJyb3JfbWVz'
    'c2FnZRgDIAEoCVIMZXJyb3JNZXNzYWdlEh8KC3RvdGFsX2NvdW50GAQgASgFUgp0b3RhbENvdW'
    '50EikKEGRvd25sb2FkZWRfY291bnQYBSABKAVSD2Rvd25sb2FkZWRDb3VudBInCg9hdmFpbGFi'
    'bGVfY291bnQYBiABKAVSDmF2YWlsYWJsZUNvdW50EiUKDmZpbHRlcmVkX2NvdW50GAcgASgFUg'
    '1maWx0ZXJlZENvdW50');

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
    {'1': 'validate_before_register', '3': 6, '4': 1, '5': 8, '10': 'validateBeforeRegister'},
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
    'GAUgAygLMiMucnVuYW55d2hlcmUudjEuTW9kZWxGaWxlRGVzY3JpcHRvclIFZmlsZXMSOAoYdm'
    'FsaWRhdGVfYmVmb3JlX3JlZ2lzdGVyGAYgASgIUhZ2YWxpZGF0ZUJlZm9yZVJlZ2lzdGVyQggK'
    'Bl9tb2RlbA==');

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
    {'1': 'registered', '3': 7, '4': 1, '5': 8, '10': 'registered'},
    {'1': 'copied_into_managed_storage', '3': 8, '4': 1, '5': 8, '10': 'copiedIntoManagedStorage'},
  ],
};

/// Descriptor for `ModelImportResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelImportResultDescriptor = $convert.base64Decode(
    'ChFNb2RlbEltcG9ydFJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEi8KBW1vZGVsGA'
    'IgASgLMhkucnVuYW55d2hlcmUudjEuTW9kZWxJbmZvUgVtb2RlbBIdCgpsb2NhbF9wYXRoGAMg'
    'ASgJUglsb2NhbFBhdGgSJQoOaW1wb3J0ZWRfYnl0ZXMYBCABKANSDWltcG9ydGVkQnl0ZXMSGg'
    'oId2FybmluZ3MYBSADKAlSCHdhcm5pbmdzEiMKDWVycm9yX21lc3NhZ2UYBiABKAlSDGVycm9y'
    'TWVzc2FnZRIeCgpyZWdpc3RlcmVkGAcgASgIUgpyZWdpc3RlcmVkEj0KG2NvcGllZF9pbnRvX2'
    '1hbmFnZWRfc3RvcmFnZRgIIAEoCFIYY29waWVkSW50b01hbmFnZWRTdG9yYWdl');

@$core.Deprecated('Use modelDiscoveryRequestDescriptor instead')
const ModelDiscoveryRequest$json = {
  '1': 'ModelDiscoveryRequest',
  '2': [
    {'1': 'search_roots', '3': 1, '4': 3, '5': 9, '10': 'searchRoots'},
    {'1': 'recursive', '3': 2, '4': 1, '5': 8, '10': 'recursive'},
    {'1': 'link_downloaded', '3': 3, '4': 1, '5': 8, '10': 'linkDownloaded'},
    {'1': 'purge_invalid', '3': 4, '4': 1, '5': 8, '10': 'purgeInvalid'},
    {'1': 'query', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelQuery', '9': 0, '10': 'query', '17': true},
    {'1': 'include_built_in', '3': 6, '4': 1, '5': 8, '10': 'includeBuiltIn'},
    {'1': 'include_user_imports', '3': 7, '4': 1, '5': 8, '10': 'includeUserImports'},
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
    'I1CgVxdWVyeRgFIAEoCzIaLnJ1bmFueXdoZXJlLnYxLk1vZGVsUXVlcnlIAFIFcXVlcnmIAQES'
    'KAoQaW5jbHVkZV9idWlsdF9pbhgGIAEoCFIOaW5jbHVkZUJ1aWx0SW4SMAoUaW5jbHVkZV91c2'
    'VyX2ltcG9ydHMYByABKAhSEmluY2x1ZGVVc2VySW1wb3J0c0IICgZfcXVlcnk=');

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
    {'1': 'scanned_count', '3': 7, '4': 1, '5': 5, '10': 'scannedCount'},
    {'1': 'imported_count', '3': 8, '4': 1, '5': 5, '10': 'importedCount'},
  ],
};

/// Descriptor for `ModelDiscoveryResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelDiscoveryResultDescriptor = $convert.base64Decode(
    'ChRNb2RlbERpc2NvdmVyeVJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEkwKEWRpc2'
    'NvdmVyZWRfbW9kZWxzGAIgAygLMh8ucnVuYW55d2hlcmUudjEuRGlzY292ZXJlZE1vZGVsUhBk'
    'aXNjb3ZlcmVkTW9kZWxzEiEKDGxpbmtlZF9jb3VudBgDIAEoBVILbGlua2VkQ291bnQSIQoMcH'
    'VyZ2VkX2NvdW50GAQgASgFUgtwdXJnZWRDb3VudBIaCgh3YXJuaW5ncxgFIAMoCVIId2Fybmlu'
    'Z3MSIwoNZXJyb3JfbWVzc2FnZRgGIAEoCVIMZXJyb3JNZXNzYWdlEiMKDXNjYW5uZWRfY291bn'
    'QYByABKAVSDHNjYW5uZWRDb3VudBIlCg5pbXBvcnRlZF9jb3VudBgIIAEoBVINaW1wb3J0ZWRD'
    'b3VudA==');

@$core.Deprecated('Use modelLoadRequestDescriptor instead')
const ModelLoadRequest$json = {
  '1': 'ModelLoadRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'category', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '9': 0, '10': 'category', '17': true},
    {'1': 'framework', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 1, '10': 'framework', '17': true},
    {'1': 'force_reload', '3': 4, '4': 1, '5': 8, '10': 'forceReload'},
    {'1': 'validate_availability', '3': 5, '4': 1, '5': 8, '10': 'validateAvailability'},
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
    'IJZnJhbWV3b3JriAEBEiEKDGZvcmNlX3JlbG9hZBgEIAEoCFILZm9yY2VSZWxvYWQSMwoVdmFs'
    'aWRhdGVfYXZhaWxhYmlsaXR5GAUgASgIUhR2YWxpZGF0ZUF2YWlsYWJpbGl0eUILCglfY2F0ZW'
    'dvcnlCDAoKX2ZyYW1ld29yaw==');

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
    {'1': 'warnings', '3': 8, '4': 3, '5': 9, '10': 'warnings'},
    {'1': 'already_loaded', '3': 9, '4': 1, '5': 8, '10': 'alreadyLoaded'},
    {'1': 'resolved_artifacts', '3': 10, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelFileDescriptor', '10': 'resolvedArtifacts'},
  ],
};

/// Descriptor for `ModelLoadResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelLoadResultDescriptor = $convert.base64Decode(
    'Cg9Nb2RlbExvYWRSZXN1bHQSGAoHc3VjY2VzcxgBIAEoCFIHc3VjY2VzcxIZCghtb2RlbF9pZB'
    'gCIAEoCVIHbW9kZWxJZBI5CghjYXRlZ29yeRgDIAEoDjIdLnJ1bmFueXdoZXJlLnYxLk1vZGVs'
    'Q2F0ZWdvcnlSCGNhdGVnb3J5EkAKCWZyYW1ld29yaxgEIAEoDjIiLnJ1bmFueXdoZXJlLnYxLk'
    'luZmVyZW5jZUZyYW1ld29ya1IJZnJhbWV3b3JrEiMKDXJlc29sdmVkX3BhdGgYBSABKAlSDHJl'
    'c29sdmVkUGF0aBIpChFsb2FkZWRfYXRfdW5peF9tcxgGIAEoA1IObG9hZGVkQXRVbml4TXMSIw'
    'oNZXJyb3JfbWVzc2FnZRgHIAEoCVIMZXJyb3JNZXNzYWdlEhoKCHdhcm5pbmdzGAggAygJUgh3'
    'YXJuaW5ncxIlCg5hbHJlYWR5X2xvYWRlZBgJIAEoCFINYWxyZWFkeUxvYWRlZBJSChJyZXNvbH'
    'ZlZF9hcnRpZmFjdHMYCiADKAsyIy5ydW5hbnl3aGVyZS52MS5Nb2RlbEZpbGVEZXNjcmlwdG9y'
    'UhFyZXNvbHZlZEFydGlmYWN0cw==');

@$core.Deprecated('Use modelUnloadRequestDescriptor instead')
const ModelUnloadRequest$json = {
  '1': 'ModelUnloadRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'category', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '9': 0, '10': 'category', '17': true},
    {'1': 'unload_all', '3': 3, '4': 1, '5': 8, '10': 'unloadAll'},
    {'1': 'framework', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 1, '10': 'framework', '17': true},
  ],
  '8': [
    {'1': '_category'},
    {'1': '_framework'},
  ],
};

/// Descriptor for `ModelUnloadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelUnloadRequestDescriptor = $convert.base64Decode(
    'ChJNb2RlbFVubG9hZFJlcXVlc3QSGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQSPgoIY2F0ZW'
    'dvcnkYAiABKA4yHS5ydW5hbnl3aGVyZS52MS5Nb2RlbENhdGVnb3J5SABSCGNhdGVnb3J5iAEB'
    'Eh0KCnVubG9hZF9hbGwYAyABKAhSCXVubG9hZEFsbBJFCglmcmFtZXdvcmsYBCABKA4yIi5ydW'
    '5hbnl3aGVyZS52MS5JbmZlcmVuY2VGcmFtZXdvcmtIAVIJZnJhbWV3b3JriAEBQgsKCV9jYXRl'
    'Z29yeUIMCgpfZnJhbWV3b3Jr');

@$core.Deprecated('Use modelUnloadResultDescriptor instead')
const ModelUnloadResult$json = {
  '1': 'ModelUnloadResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'unloaded_model_ids', '3': 2, '4': 3, '5': 9, '10': 'unloadedModelIds'},
    {'1': 'error_message', '3': 3, '4': 1, '5': 9, '10': 'errorMessage'},
    {'1': 'unloaded_at_unix_ms', '3': 4, '4': 1, '5': 3, '10': 'unloadedAtUnixMs'},
    {'1': 'warnings', '3': 5, '4': 3, '5': 9, '10': 'warnings'},
  ],
};

/// Descriptor for `ModelUnloadResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelUnloadResultDescriptor = $convert.base64Decode(
    'ChFNb2RlbFVubG9hZFJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEiwKEnVubG9hZG'
    'VkX21vZGVsX2lkcxgCIAMoCVIQdW5sb2FkZWRNb2RlbElkcxIjCg1lcnJvcl9tZXNzYWdlGAMg'
    'ASgJUgxlcnJvck1lc3NhZ2USLQoTdW5sb2FkZWRfYXRfdW5peF9tcxgEIAEoA1IQdW5sb2FkZW'
    'RBdFVuaXhNcxIaCgh3YXJuaW5ncxgFIAMoCVIId2FybmluZ3M=');

@$core.Deprecated('Use currentModelRequestDescriptor instead')
const CurrentModelRequest$json = {
  '1': 'CurrentModelRequest',
  '2': [
    {'1': 'category', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '9': 0, '10': 'category', '17': true},
    {'1': 'framework', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 1, '10': 'framework', '17': true},
    {'1': 'include_model_metadata', '3': 3, '4': 1, '5': 8, '10': 'includeModelMetadata'},
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
    'bnl3aGVyZS52MS5JbmZlcmVuY2VGcmFtZXdvcmtIAVIJZnJhbWV3b3JriAEBEjQKFmluY2x1ZG'
    'VfbW9kZWxfbWV0YWRhdGEYAyABKAhSFGluY2x1ZGVNb2RlbE1ldGFkYXRhQgsKCV9jYXRlZ29y'
    'eUIMCgpfZnJhbWV3b3Jr');

@$core.Deprecated('Use currentModelResultDescriptor instead')
const CurrentModelResult$json = {
  '1': 'CurrentModelResult',
  '2': [
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'model', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfo', '10': 'model'},
    {'1': 'loaded_at_unix_ms', '3': 4, '4': 1, '5': 3, '10': 'loadedAtUnixMs'},
    {'1': 'found', '3': 5, '4': 1, '5': 8, '10': 'found'},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '10': 'errorMessage'},
    {'1': 'category', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '10': 'category'},
    {'1': 'framework', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '10': 'framework'},
    {'1': 'resolved_path', '3': 9, '4': 1, '5': 9, '10': 'resolvedPath'},
    {'1': 'resolved_artifacts', '3': 10, '4': 3, '5': 11, '6': '.runanywhere.v1.ModelFileDescriptor', '10': 'resolvedArtifacts'},
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
    'bml4X21zGAQgASgDUg5sb2FkZWRBdFVuaXhNcxIUCgVmb3VuZBgFIAEoCFIFZm91bmQSIwoNZX'
    'Jyb3JfbWVzc2FnZRgGIAEoCVIMZXJyb3JNZXNzYWdlEjkKCGNhdGVnb3J5GAcgASgOMh0ucnVu'
    'YW55d2hlcmUudjEuTW9kZWxDYXRlZ29yeVIIY2F0ZWdvcnkSQAoJZnJhbWV3b3JrGAggASgOMi'
    'IucnVuYW55d2hlcmUudjEuSW5mZXJlbmNlRnJhbWV3b3JrUglmcmFtZXdvcmsSIwoNcmVzb2x2'
    'ZWRfcGF0aBgJIAEoCVIMcmVzb2x2ZWRQYXRoElIKEnJlc29sdmVkX2FydGlmYWN0cxgKIAMoCz'
    'IjLnJ1bmFueXdoZXJlLnYxLk1vZGVsRmlsZURlc2NyaXB0b3JSEXJlc29sdmVkQXJ0aWZhY3Rz'
    'SgQIARACUgloYXNfbW9kZWw=');

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
    {'1': 'warnings', '3': 8, '4': 3, '5': 9, '10': 'warnings'},
  ],
};

/// Descriptor for `ModelDeleteResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelDeleteResultDescriptor = $convert.base64Decode(
    'ChFNb2RlbERlbGV0ZVJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEhkKCG1vZGVsX2'
    'lkGAIgASgJUgdtb2RlbElkEiMKDWRlbGV0ZWRfYnl0ZXMYAyABKANSDGRlbGV0ZWRCeXRlcxIj'
    'Cg1maWxlc19kZWxldGVkGAQgASgIUgxmaWxlc0RlbGV0ZWQSKQoQcmVnaXN0cnlfdXBkYXRlZB'
    'gFIAEoCFIPcmVnaXN0cnlVcGRhdGVkEh0KCndhc19sb2FkZWQYBiABKAhSCXdhc0xvYWRlZBIj'
    'Cg1lcnJvcl9tZXNzYWdlGAcgASgJUgxlcnJvck1lc3NhZ2USGgoId2FybmluZ3MYCCADKAlSCH'
    'dhcm5pbmdz');

@$core.Deprecated('Use modelCompatibilityRequestDescriptor instead')
const ModelCompatibilityRequest$json = {
  '1': 'ModelCompatibilityRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'hardware_profile', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.HardwareProfile', '9': 0, '10': 'hardwareProfile', '17': true},
    {'1': 'available_ram_bytes', '3': 3, '4': 1, '5': 3, '10': 'availableRamBytes'},
    {'1': 'available_storage_bytes', '3': 4, '4': 1, '5': 3, '10': 'availableStorageBytes'},
    {'1': 'accelerator_preference', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.AccelerationPreference', '9': 1, '10': 'acceleratorPreference', '17': true},
    {'1': 'preferred_framework', '3': 6, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 2, '10': 'preferredFramework', '17': true},
  ],
  '8': [
    {'1': '_hardware_profile'},
    {'1': '_accelerator_preference'},
    {'1': '_preferred_framework'},
  ],
};

/// Descriptor for `ModelCompatibilityRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelCompatibilityRequestDescriptor = $convert.base64Decode(
    'ChlNb2RlbENvbXBhdGliaWxpdHlSZXF1ZXN0EhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEk'
    '8KEGhhcmR3YXJlX3Byb2ZpbGUYAiABKAsyHy5ydW5hbnl3aGVyZS52MS5IYXJkd2FyZVByb2Zp'
    'bGVIAFIPaGFyZHdhcmVQcm9maWxliAEBEi4KE2F2YWlsYWJsZV9yYW1fYnl0ZXMYAyABKANSEW'
    'F2YWlsYWJsZVJhbUJ5dGVzEjYKF2F2YWlsYWJsZV9zdG9yYWdlX2J5dGVzGAQgASgDUhVhdmFp'
    'bGFibGVTdG9yYWdlQnl0ZXMSYgoWYWNjZWxlcmF0b3JfcHJlZmVyZW5jZRgFIAEoDjImLnJ1bm'
    'FueXdoZXJlLnYxLkFjY2VsZXJhdGlvblByZWZlcmVuY2VIAVIVYWNjZWxlcmF0b3JQcmVmZXJl'
    'bmNliAEBElgKE3ByZWZlcnJlZF9mcmFtZXdvcmsYBiABKA4yIi5ydW5hbnl3aGVyZS52MS5Jbm'
    'ZlcmVuY2VGcmFtZXdvcmtIAlIScHJlZmVycmVkRnJhbWV3b3JriAEBQhMKEV9oYXJkd2FyZV9w'
    'cm9maWxlQhkKF19hY2NlbGVyYXRvcl9wcmVmZXJlbmNlQhYKFF9wcmVmZXJyZWRfZnJhbWV3b3'
    'Jr');

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
    {'1': 'suggested_alternatives', '3': 9, '4': 3, '5': 9, '10': 'suggestedAlternatives'},
    {'1': 'model_id', '3': 10, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'error_code', '3': 11, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'error_message', '3': 12, '4': 1, '5': 9, '10': 'errorMessage'},
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
    'cmVhc29ucxgIIAMoCVIHcmVhc29ucxI1ChZzdWdnZXN0ZWRfYWx0ZXJuYXRpdmVzGAkgAygJUh'
    'VzdWdnZXN0ZWRBbHRlcm5hdGl2ZXMSGQoIbW9kZWxfaWQYCiABKAlSB21vZGVsSWQSHQoKZXJy'
    'b3JfY29kZRgLIAEoBVIJZXJyb3JDb2RlEiMKDWVycm9yX21lc3NhZ2UYDCABKAlSDGVycm9yTW'
    'Vzc2FnZQ==');

@$core.Deprecated('Use modelFormatFromUrlRequestDescriptor instead')
const ModelFormatFromUrlRequest$json = {
  '1': 'ModelFormatFromUrlRequest',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
  ],
};

/// Descriptor for `ModelFormatFromUrlRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelFormatFromUrlRequestDescriptor = $convert.base64Decode(
    'ChlNb2RlbEZvcm1hdEZyb21VcmxSZXF1ZXN0EhAKA3VybBgBIAEoCVIDdXJs');

@$core.Deprecated('Use modelFormatFromUrlResultDescriptor instead')
const ModelFormatFromUrlResult$json = {
  '1': 'ModelFormatFromUrlResult',
  '2': [
    {'1': 'format', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelFormat', '10': 'format'},
    {'1': 'inner_format', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelFormat', '10': 'innerFormat'},
  ],
};

/// Descriptor for `ModelFormatFromUrlResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelFormatFromUrlResultDescriptor = $convert.base64Decode(
    'ChhNb2RlbEZvcm1hdEZyb21VcmxSZXN1bHQSMwoGZm9ybWF0GAEgASgOMhsucnVuYW55d2hlcm'
    'UudjEuTW9kZWxGb3JtYXRSBmZvcm1hdBI+Cgxpbm5lcl9mb3JtYXQYAiABKA4yGy5ydW5hbnl3'
    'aGVyZS52MS5Nb2RlbEZvcm1hdFILaW5uZXJGb3JtYXQ=');

@$core.Deprecated('Use artifactInferFromUrlRequestDescriptor instead')
const ArtifactInferFromUrlRequest$json = {
  '1': 'ArtifactInferFromUrlRequest',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
  ],
};

/// Descriptor for `ArtifactInferFromUrlRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List artifactInferFromUrlRequestDescriptor = $convert.base64Decode(
    'ChtBcnRpZmFjdEluZmVyRnJvbVVybFJlcXVlc3QSEAoDdXJsGAEgASgJUgN1cmwSGQoIbW9kZW'
    'xfaWQYAiABKAlSB21vZGVsSWQ=');

@$core.Deprecated('Use artifactInferFromUrlResultDescriptor instead')
const ArtifactInferFromUrlResult$json = {
  '1': 'ArtifactInferFromUrlResult',
  '2': [
    {'1': 'artifact_type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelArtifactType', '10': 'artifactType'},
    {'1': 'archive_type', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ArchiveType', '10': 'archiveType'},
    {'1': 'archive_structure', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.ArchiveStructure', '10': 'archiveStructure'},
    {'1': 'primary_relpath', '3': 4, '4': 1, '5': 9, '10': 'primaryRelpath'},
    {'1': 'inner_format', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelFormat', '10': 'innerFormat'},
  ],
};

/// Descriptor for `ArtifactInferFromUrlResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List artifactInferFromUrlResultDescriptor = $convert.base64Decode(
    'ChpBcnRpZmFjdEluZmVyRnJvbVVybFJlc3VsdBJGCg1hcnRpZmFjdF90eXBlGAEgASgOMiEucn'
    'VuYW55d2hlcmUudjEuTW9kZWxBcnRpZmFjdFR5cGVSDGFydGlmYWN0VHlwZRI+CgxhcmNoaXZl'
    'X3R5cGUYAiABKA4yGy5ydW5hbnl3aGVyZS52MS5BcmNoaXZlVHlwZVILYXJjaGl2ZVR5cGUSTQ'
    'oRYXJjaGl2ZV9zdHJ1Y3R1cmUYAyABKA4yIC5ydW5hbnl3aGVyZS52MS5BcmNoaXZlU3RydWN0'
    'dXJlUhBhcmNoaXZlU3RydWN0dXJlEicKD3ByaW1hcnlfcmVscGF0aBgEIAEoCVIOcHJpbWFyeV'
    'JlbHBhdGgSPgoMaW5uZXJfZm9ybWF0GAUgASgOMhsucnVuYW55d2hlcmUudjEuTW9kZWxGb3Jt'
    'YXRSC2lubmVyRm9ybWF0');

@$core.Deprecated('Use modelRegistryFetchAssignmentsRequestDescriptor instead')
const ModelRegistryFetchAssignmentsRequest$json = {
  '1': 'ModelRegistryFetchAssignmentsRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {'1': 'environment', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.SDKEnvironment', '9': 0, '10': 'environment', '17': true},
    {'1': 'force_refresh', '3': 3, '4': 1, '5': 8, '10': 'forceRefresh'},
  ],
  '8': [
    {'1': '_environment'},
  ],
};

/// Descriptor for `ModelRegistryFetchAssignmentsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelRegistryFetchAssignmentsRequestDescriptor = $convert.base64Decode(
    'CiRNb2RlbFJlZ2lzdHJ5RmV0Y2hBc3NpZ25tZW50c1JlcXVlc3QSGwoJZGV2aWNlX2lkGAEgAS'
    'gJUghkZXZpY2VJZBJFCgtlbnZpcm9ubWVudBgCIAEoDjIeLnJ1bmFueXdoZXJlLnYxLlNES0Vu'
    'dmlyb25tZW50SABSC2Vudmlyb25tZW50iAEBEiMKDWZvcmNlX3JlZnJlc2gYAyABKAhSDGZvcm'
    'NlUmVmcmVzaEIOCgxfZW52aXJvbm1lbnQ=');

@$core.Deprecated('Use modelRegistryFetchAssignmentsResultDescriptor instead')
const ModelRegistryFetchAssignmentsResult$json = {
  '1': 'ModelRegistryFetchAssignmentsResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'models', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfoList', '10': 'models'},
    {'1': 'model_count', '3': 3, '4': 1, '5': 5, '10': 'modelCount'},
    {'1': 'fetched_at_unix_ms', '3': 4, '4': 1, '5': 3, '10': 'fetchedAtUnixMs'},
    {'1': 'error_code', '3': 5, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'error_message', '3': 6, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `ModelRegistryFetchAssignmentsResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelRegistryFetchAssignmentsResultDescriptor = $convert.base64Decode(
    'CiNNb2RlbFJlZ2lzdHJ5RmV0Y2hBc3NpZ25tZW50c1Jlc3VsdBIYCgdzdWNjZXNzGAEgASgIUg'
    'dzdWNjZXNzEjUKBm1vZGVscxgCIAEoCzIdLnJ1bmFueXdoZXJlLnYxLk1vZGVsSW5mb0xpc3RS'
    'Bm1vZGVscxIfCgttb2RlbF9jb3VudBgDIAEoBVIKbW9kZWxDb3VudBIrChJmZXRjaGVkX2F0X3'
    'VuaXhfbXMYBCABKANSD2ZldGNoZWRBdFVuaXhNcxIdCgplcnJvcl9jb2RlGAUgASgFUgllcnJv'
    'ckNvZGUSIwoNZXJyb3JfbWVzc2FnZRgGIAEoCVIMZXJyb3JNZXNzYWdl');

@$core.Deprecated('Use modelInfoMakeRequestDescriptor instead')
const ModelInfoMakeRequest$json = {
  '1': 'ModelInfoMakeRequest',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'framework', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 0, '10': 'framework', '17': true},
    {'1': 'category', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '9': 1, '10': 'category', '17': true},
    {'1': 'source', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelSource', '9': 2, '10': 'source', '17': true},
  ],
  '8': [
    {'1': '_framework'},
    {'1': '_category'},
    {'1': '_source'},
  ],
};

/// Descriptor for `ModelInfoMakeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelInfoMakeRequestDescriptor = $convert.base64Decode(
    'ChRNb2RlbEluZm9NYWtlUmVxdWVzdBIQCgN1cmwYASABKAlSA3VybBISCgRuYW1lGAIgASgJUg'
    'RuYW1lEkUKCWZyYW1ld29yaxgDIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW5jZUZyYW1l'
    'd29ya0gAUglmcmFtZXdvcmuIAQESPgoIY2F0ZWdvcnkYBCABKA4yHS5ydW5hbnl3aGVyZS52MS'
    '5Nb2RlbENhdGVnb3J5SAFSCGNhdGVnb3J5iAEBEjgKBnNvdXJjZRgFIAEoDjIbLnJ1bmFueXdo'
    'ZXJlLnYxLk1vZGVsU291cmNlSAJSBnNvdXJjZYgBAUIMCgpfZnJhbWV3b3JrQgsKCV9jYXRlZ2'
    '9yeUIJCgdfc291cmNl');

@$core.Deprecated('Use registerModelFromUrlRequestDescriptor instead')
const RegisterModelFromUrlRequest$json = {
  '1': 'RegisterModelFromUrlRequest',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'framework', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 0, '10': 'framework', '17': true},
    {'1': 'category', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelCategory', '9': 1, '10': 'category', '17': true},
    {'1': 'source', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelSource', '9': 2, '10': 'source', '17': true},
  ],
  '8': [
    {'1': '_framework'},
    {'1': '_category'},
    {'1': '_source'},
  ],
};

/// Descriptor for `RegisterModelFromUrlRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List registerModelFromUrlRequestDescriptor = $convert.base64Decode(
    'ChtSZWdpc3Rlck1vZGVsRnJvbVVybFJlcXVlc3QSEAoDdXJsGAEgASgJUgN1cmwSEgoEbmFtZR'
    'gCIAEoCVIEbmFtZRJFCglmcmFtZXdvcmsYAyABKA4yIi5ydW5hbnl3aGVyZS52MS5JbmZlcmVu'
    'Y2VGcmFtZXdvcmtIAFIJZnJhbWV3b3JriAEBEj4KCGNhdGVnb3J5GAQgASgOMh0ucnVuYW55d2'
    'hlcmUudjEuTW9kZWxDYXRlZ29yeUgBUghjYXRlZ29yeYgBARI4CgZzb3VyY2UYBSABKA4yGy5y'
    'dW5hbnl3aGVyZS52MS5Nb2RlbFNvdXJjZUgCUgZzb3VyY2WIAQFCDAoKX2ZyYW1ld29ya0ILCg'
    'lfY2F0ZWdvcnlCCQoHX3NvdXJjZQ==');

const $core.Map<$core.String, $core.dynamic> ModelRegistryServiceBase$json = {
  '1': 'ModelRegistry',
  '2': [
    {'1': 'Register', '2': '.runanywhere.v1.ModelInfo', '3': '.runanywhere.v1.ModelInfo'},
    {'1': 'Update', '2': '.runanywhere.v1.ModelInfo', '3': '.runanywhere.v1.ModelInfo'},
    {'1': 'Get', '2': '.runanywhere.v1.ModelGetRequest', '3': '.runanywhere.v1.ModelGetResult'},
    {'1': 'List', '2': '.runanywhere.v1.ModelListRequest', '3': '.runanywhere.v1.ModelListResult'},
    {'1': 'Remove', '2': '.runanywhere.v1.ModelDeleteRequest', '3': '.runanywhere.v1.ModelDeleteResult'},
    {'1': 'Import', '2': '.runanywhere.v1.ModelImportRequest', '3': '.runanywhere.v1.ModelImportResult'},
    {'1': 'Discover', '2': '.runanywhere.v1.ModelDiscoveryRequest', '3': '.runanywhere.v1.ModelDiscoveryResult'},
    {'1': 'Refresh', '2': '.runanywhere.v1.ModelRegistryRefreshRequest', '3': '.runanywhere.v1.ModelRegistryRefreshResult'},
  ],
};

@$core.Deprecated('Use modelRegistryServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> ModelRegistryServiceBase$messageJson = {
  '.runanywhere.v1.ModelInfo': ModelInfo$json,
  '.runanywhere.v1.ThinkingTagPattern': $2.ThinkingTagPattern$json,
  '.runanywhere.v1.ModelInfoMetadata': ModelInfoMetadata$json,
  '.runanywhere.v1.SingleFileArtifact': SingleFileArtifact$json,
  '.runanywhere.v1.ExpectedModelFiles': ExpectedModelFiles$json,
  '.runanywhere.v1.ModelFileDescriptor': ModelFileDescriptor$json,
  '.runanywhere.v1.ArchiveArtifact': ArchiveArtifact$json,
  '.runanywhere.v1.MultiFileArtifact': MultiFileArtifact$json,
  '.runanywhere.v1.ModelRuntimeCompatibility': ModelRuntimeCompatibility$json,
  '.runanywhere.v1.ModelGetRequest': ModelGetRequest$json,
  '.runanywhere.v1.ModelGetResult': ModelGetResult$json,
  '.runanywhere.v1.ModelListRequest': ModelListRequest$json,
  '.runanywhere.v1.ModelQuery': ModelQuery$json,
  '.runanywhere.v1.ModelListResult': ModelListResult$json,
  '.runanywhere.v1.ModelInfoList': ModelInfoList$json,
  '.runanywhere.v1.ModelDeleteRequest': ModelDeleteRequest$json,
  '.runanywhere.v1.ModelDeleteResult': ModelDeleteResult$json,
  '.runanywhere.v1.ModelImportRequest': ModelImportRequest$json,
  '.runanywhere.v1.ModelImportResult': ModelImportResult$json,
  '.runanywhere.v1.ModelDiscoveryRequest': ModelDiscoveryRequest$json,
  '.runanywhere.v1.ModelDiscoveryResult': ModelDiscoveryResult$json,
  '.runanywhere.v1.DiscoveredModel': DiscoveredModel$json,
  '.runanywhere.v1.ModelRegistryRefreshRequest': ModelRegistryRefreshRequest$json,
  '.runanywhere.v1.ModelRegistryRefreshResult': ModelRegistryRefreshResult$json,
};

/// Descriptor for `ModelRegistry`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List modelRegistryServiceDescriptor = $convert.base64Decode(
    'Cg1Nb2RlbFJlZ2lzdHJ5EkAKCFJlZ2lzdGVyEhkucnVuYW55d2hlcmUudjEuTW9kZWxJbmZvGh'
    'kucnVuYW55d2hlcmUudjEuTW9kZWxJbmZvEj4KBlVwZGF0ZRIZLnJ1bmFueXdoZXJlLnYxLk1v'
    'ZGVsSW5mbxoZLnJ1bmFueXdoZXJlLnYxLk1vZGVsSW5mbxJGCgNHZXQSHy5ydW5hbnl3aGVyZS'
    '52MS5Nb2RlbEdldFJlcXVlc3QaHi5ydW5hbnl3aGVyZS52MS5Nb2RlbEdldFJlc3VsdBJJCgRM'
    'aXN0EiAucnVuYW55d2hlcmUudjEuTW9kZWxMaXN0UmVxdWVzdBofLnJ1bmFueXdoZXJlLnYxLk'
    '1vZGVsTGlzdFJlc3VsdBJPCgZSZW1vdmUSIi5ydW5hbnl3aGVyZS52MS5Nb2RlbERlbGV0ZVJl'
    'cXVlc3QaIS5ydW5hbnl3aGVyZS52MS5Nb2RlbERlbGV0ZVJlc3VsdBJPCgZJbXBvcnQSIi5ydW'
    '5hbnl3aGVyZS52MS5Nb2RlbEltcG9ydFJlcXVlc3QaIS5ydW5hbnl3aGVyZS52MS5Nb2RlbElt'
    'cG9ydFJlc3VsdBJXCghEaXNjb3ZlchIlLnJ1bmFueXdoZXJlLnYxLk1vZGVsRGlzY292ZXJ5Um'
    'VxdWVzdBokLnJ1bmFueXdoZXJlLnYxLk1vZGVsRGlzY292ZXJ5UmVzdWx0EmIKB1JlZnJlc2gS'
    'Ky5ydW5hbnl3aGVyZS52MS5Nb2RlbFJlZ2lzdHJ5UmVmcmVzaFJlcXVlc3QaKi5ydW5hbnl3aG'
    'VyZS52MS5Nb2RlbFJlZ2lzdHJ5UmVmcmVzaFJlc3VsdA==');

