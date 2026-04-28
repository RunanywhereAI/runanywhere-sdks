///
//  Generated code. Do not modify.
//  source: stt_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use sTTLanguageDescriptor instead')
const STTLanguage$json = const {
  '1': 'STTLanguage',
  '2': const [
    const {'1': 'STT_LANGUAGE_UNSPECIFIED', '2': 0},
    const {'1': 'STT_LANGUAGE_AUTO', '2': 1},
    const {'1': 'STT_LANGUAGE_EN', '2': 2},
    const {'1': 'STT_LANGUAGE_ES', '2': 3},
    const {'1': 'STT_LANGUAGE_FR', '2': 4},
    const {'1': 'STT_LANGUAGE_DE', '2': 5},
    const {'1': 'STT_LANGUAGE_ZH', '2': 6},
    const {'1': 'STT_LANGUAGE_JA', '2': 7},
    const {'1': 'STT_LANGUAGE_KO', '2': 8},
    const {'1': 'STT_LANGUAGE_IT', '2': 9},
    const {'1': 'STT_LANGUAGE_PT', '2': 10},
    const {'1': 'STT_LANGUAGE_AR', '2': 11},
    const {'1': 'STT_LANGUAGE_RU', '2': 12},
    const {'1': 'STT_LANGUAGE_HI', '2': 13},
  ],
};

/// Descriptor for `STTLanguage`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sTTLanguageDescriptor = $convert.base64Decode('CgtTVFRMYW5ndWFnZRIcChhTVFRfTEFOR1VBR0VfVU5TUEVDSUZJRUQQABIVChFTVFRfTEFOR1VBR0VfQVVUTxABEhMKD1NUVF9MQU5HVUFHRV9FThACEhMKD1NUVF9MQU5HVUFHRV9FUxADEhMKD1NUVF9MQU5HVUFHRV9GUhAEEhMKD1NUVF9MQU5HVUFHRV9ERRAFEhMKD1NUVF9MQU5HVUFHRV9aSBAGEhMKD1NUVF9MQU5HVUFHRV9KQRAHEhMKD1NUVF9MQU5HVUFHRV9LTxAIEhMKD1NUVF9MQU5HVUFHRV9JVBAJEhMKD1NUVF9MQU5HVUFHRV9QVBAKEhMKD1NUVF9MQU5HVUFHRV9BUhALEhMKD1NUVF9MQU5HVUFHRV9SVRAMEhMKD1NUVF9MQU5HVUFHRV9ISRAN');
@$core.Deprecated('Use sTTConfigurationDescriptor instead')
const STTConfiguration$json = const {
  '1': 'STTConfiguration',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'language', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.STTLanguage', '10': 'language'},
    const {'1': 'sample_rate', '3': 3, '4': 1, '5': 5, '10': 'sampleRate'},
    const {'1': 'enable_vad', '3': 4, '4': 1, '5': 8, '10': 'enableVad'},
    const {'1': 'audio_format', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
  ],
};

/// Descriptor for `STTConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTConfigurationDescriptor = $convert.base64Decode('ChBTVFRDb25maWd1cmF0aW9uEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEjcKCGxhbmd1YWdlGAIgASgOMhsucnVuYW55d2hlcmUudjEuU1RUTGFuZ3VhZ2VSCGxhbmd1YWdlEh8KC3NhbXBsZV9yYXRlGAMgASgFUgpzYW1wbGVSYXRlEh0KCmVuYWJsZV92YWQYBCABKAhSCWVuYWJsZVZhZBI+CgxhdWRpb19mb3JtYXQYBSABKA4yGy5ydW5hbnl3aGVyZS52MS5BdWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQ=');
@$core.Deprecated('Use sTTOptionsDescriptor instead')
const STTOptions$json = const {
  '1': 'STTOptions',
  '2': const [
    const {'1': 'language', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.STTLanguage', '10': 'language'},
    const {'1': 'enable_punctuation', '3': 2, '4': 1, '5': 8, '10': 'enablePunctuation'},
    const {'1': 'enable_diarization', '3': 3, '4': 1, '5': 8, '10': 'enableDiarization'},
    const {'1': 'max_speakers', '3': 4, '4': 1, '5': 5, '10': 'maxSpeakers'},
    const {'1': 'vocabulary_list', '3': 5, '4': 3, '5': 9, '10': 'vocabularyList'},
    const {'1': 'enable_word_timestamps', '3': 6, '4': 1, '5': 8, '10': 'enableWordTimestamps'},
    const {'1': 'beam_size', '3': 7, '4': 1, '5': 5, '10': 'beamSize'},
  ],
};

/// Descriptor for `STTOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTOptionsDescriptor = $convert.base64Decode('CgpTVFRPcHRpb25zEjcKCGxhbmd1YWdlGAEgASgOMhsucnVuYW55d2hlcmUudjEuU1RUTGFuZ3VhZ2VSCGxhbmd1YWdlEi0KEmVuYWJsZV9wdW5jdHVhdGlvbhgCIAEoCFIRZW5hYmxlUHVuY3R1YXRpb24SLQoSZW5hYmxlX2RpYXJpemF0aW9uGAMgASgIUhFlbmFibGVEaWFyaXphdGlvbhIhCgxtYXhfc3BlYWtlcnMYBCABKAVSC21heFNwZWFrZXJzEicKD3ZvY2FidWxhcnlfbGlzdBgFIAMoCVIOdm9jYWJ1bGFyeUxpc3QSNAoWZW5hYmxlX3dvcmRfdGltZXN0YW1wcxgGIAEoCFIUZW5hYmxlV29yZFRpbWVzdGFtcHMSGwoJYmVhbV9zaXplGAcgASgFUghiZWFtU2l6ZQ==');
@$core.Deprecated('Use wordTimestampDescriptor instead')
const WordTimestamp$json = const {
  '1': 'WordTimestamp',
  '2': const [
    const {'1': 'word', '3': 1, '4': 1, '5': 9, '10': 'word'},
    const {'1': 'start_ms', '3': 2, '4': 1, '5': 3, '10': 'startMs'},
    const {'1': 'end_ms', '3': 3, '4': 1, '5': 3, '10': 'endMs'},
    const {'1': 'confidence', '3': 4, '4': 1, '5': 2, '10': 'confidence'},
  ],
};

/// Descriptor for `WordTimestamp`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wordTimestampDescriptor = $convert.base64Decode('Cg1Xb3JkVGltZXN0YW1wEhIKBHdvcmQYASABKAlSBHdvcmQSGQoIc3RhcnRfbXMYAiABKANSB3N0YXJ0TXMSFQoGZW5kX21zGAMgASgDUgVlbmRNcxIeCgpjb25maWRlbmNlGAQgASgCUgpjb25maWRlbmNl');
@$core.Deprecated('Use transcriptionAlternativeDescriptor instead')
const TranscriptionAlternative$json = const {
  '1': 'TranscriptionAlternative',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
    const {'1': 'words', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.WordTimestamp', '10': 'words'},
  ],
};

/// Descriptor for `TranscriptionAlternative`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transcriptionAlternativeDescriptor = $convert.base64Decode('ChhUcmFuc2NyaXB0aW9uQWx0ZXJuYXRpdmUSEgoEdGV4dBgBIAEoCVIEdGV4dBIeCgpjb25maWRlbmNlGAIgASgCUgpjb25maWRlbmNlEjMKBXdvcmRzGAMgAygLMh0ucnVuYW55d2hlcmUudjEuV29yZFRpbWVzdGFtcFIFd29yZHM=');
@$core.Deprecated('Use transcriptionMetadataDescriptor instead')
const TranscriptionMetadata$json = const {
  '1': 'TranscriptionMetadata',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'processing_time_ms', '3': 2, '4': 1, '5': 3, '10': 'processingTimeMs'},
    const {'1': 'audio_length_ms', '3': 3, '4': 1, '5': 3, '10': 'audioLengthMs'},
    const {'1': 'real_time_factor', '3': 4, '4': 1, '5': 2, '10': 'realTimeFactor'},
  ],
};

/// Descriptor for `TranscriptionMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transcriptionMetadataDescriptor = $convert.base64Decode('ChVUcmFuc2NyaXB0aW9uTWV0YWRhdGESGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQSLAoScHJvY2Vzc2luZ190aW1lX21zGAIgASgDUhBwcm9jZXNzaW5nVGltZU1zEiYKD2F1ZGlvX2xlbmd0aF9tcxgDIAEoA1INYXVkaW9MZW5ndGhNcxIoChByZWFsX3RpbWVfZmFjdG9yGAQgASgCUg5yZWFsVGltZUZhY3Rvcg==');
@$core.Deprecated('Use sTTOutputDescriptor instead')
const STTOutput$json = const {
  '1': 'STTOutput',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'language', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.STTLanguage', '10': 'language'},
    const {'1': 'confidence', '3': 3, '4': 1, '5': 2, '10': 'confidence'},
    const {'1': 'words', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.WordTimestamp', '10': 'words'},
    const {'1': 'alternatives', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.TranscriptionAlternative', '10': 'alternatives'},
    const {'1': 'metadata', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.TranscriptionMetadata', '10': 'metadata'},
  ],
};

/// Descriptor for `STTOutput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTOutputDescriptor = $convert.base64Decode('CglTVFRPdXRwdXQSEgoEdGV4dBgBIAEoCVIEdGV4dBI3CghsYW5ndWFnZRgCIAEoDjIbLnJ1bmFueXdoZXJlLnYxLlNUVExhbmd1YWdlUghsYW5ndWFnZRIeCgpjb25maWRlbmNlGAMgASgCUgpjb25maWRlbmNlEjMKBXdvcmRzGAQgAygLMh0ucnVuYW55d2hlcmUudjEuV29yZFRpbWVzdGFtcFIFd29yZHMSTAoMYWx0ZXJuYXRpdmVzGAUgAygLMigucnVuYW55d2hlcmUudjEuVHJhbnNjcmlwdGlvbkFsdGVybmF0aXZlUgxhbHRlcm5hdGl2ZXMSQQoIbWV0YWRhdGEYBiABKAsyJS5ydW5hbnl3aGVyZS52MS5UcmFuc2NyaXB0aW9uTWV0YWRhdGFSCG1ldGFkYXRh');
@$core.Deprecated('Use sTTPartialResultDescriptor instead')
const STTPartialResult$json = const {
  '1': 'STTPartialResult',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'is_final', '3': 2, '4': 1, '5': 8, '10': 'isFinal'},
    const {'1': 'stability', '3': 3, '4': 1, '5': 2, '10': 'stability'},
  ],
};

/// Descriptor for `STTPartialResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTPartialResultDescriptor = $convert.base64Decode('ChBTVFRQYXJ0aWFsUmVzdWx0EhIKBHRleHQYASABKAlSBHRleHQSGQoIaXNfZmluYWwYAiABKAhSB2lzRmluYWwSHAoJc3RhYmlsaXR5GAMgASgCUglzdGFiaWxpdHk=');
