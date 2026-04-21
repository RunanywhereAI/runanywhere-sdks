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
    'QU1FV09SS19OT05FEBUSHwobSU5GRVJFTkNFX0ZSQU1FV09SS19VTktOT1dOEBY=');

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
    {'1': 'single_file', '3': 20, '4': 1, '5': 11, '6': '.runanywhere.v1.SingleFileArtifact', '9': 0, '10': 'singleFile'},
    {'1': 'archive', '3': 21, '4': 1, '5': 11, '6': '.runanywhere.v1.ArchiveArtifact', '9': 0, '10': 'archive'},
    {'1': 'multi_file', '3': 22, '4': 1, '5': 11, '6': '.runanywhere.v1.MultiFileArtifact', '9': 0, '10': 'multiFile'},
    {'1': 'custom_strategy_id', '3': 23, '4': 1, '5': 9, '9': 0, '10': 'customStrategyId'},
    {'1': 'built_in', '3': 24, '4': 1, '5': 8, '9': 0, '10': 'builtIn'},
  ],
  '8': [
    {'1': 'artifact'},
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
    'hfbXMYDyABKANSD3VwZGF0ZWRBdFVuaXhNcxJFCgtzaW5nbGVfZmlsZRgUIAEoCzIiLnJ1bmFu'
    'eXdoZXJlLnYxLlNpbmdsZUZpbGVBcnRpZmFjdEgAUgpzaW5nbGVGaWxlEjsKB2FyY2hpdmUYFS'
    'ABKAsyHy5ydW5hbnl3aGVyZS52MS5BcmNoaXZlQXJ0aWZhY3RIAFIHYXJjaGl2ZRJCCgptdWx0'
    'aV9maWxlGBYgASgLMiEucnVuYW55d2hlcmUudjEuTXVsdGlGaWxlQXJ0aWZhY3RIAFIJbXVsdG'
    'lGaWxlEi4KEmN1c3RvbV9zdHJhdGVneV9pZBgXIAEoCUgAUhBjdXN0b21TdHJhdGVneUlkEhsK'
    'CGJ1aWx0X2luGBggASgISABSB2J1aWx0SW5CCgoIYXJ0aWZhY3Q=');

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
  ],
};

/// Descriptor for `ModelFileDescriptor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelFileDescriptorDescriptor = $convert.base64Decode(
    'ChNNb2RlbEZpbGVEZXNjcmlwdG9yEhAKA3VybBgBIAEoCVIDdXJsEhoKCGZpbGVuYW1lGAIgAS'
    'gJUghmaWxlbmFtZRIfCgtpc19yZXF1aXJlZBgDIAEoCFIKaXNSZXF1aXJlZA==');

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

