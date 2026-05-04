//
//  Generated code. Do not modify.
//  source: stt_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use sTTLanguageDescriptor instead')
const STTLanguage$json = {
  '1': 'STTLanguage',
  '2': [
    {'1': 'STT_LANGUAGE_UNSPECIFIED', '2': 0},
    {'1': 'STT_LANGUAGE_AUTO', '2': 1},
    {'1': 'STT_LANGUAGE_EN', '2': 2},
    {'1': 'STT_LANGUAGE_ES', '2': 3},
    {'1': 'STT_LANGUAGE_FR', '2': 4},
    {'1': 'STT_LANGUAGE_DE', '2': 5},
    {'1': 'STT_LANGUAGE_ZH', '2': 6},
    {'1': 'STT_LANGUAGE_JA', '2': 7},
    {'1': 'STT_LANGUAGE_KO', '2': 8},
    {'1': 'STT_LANGUAGE_IT', '2': 9},
    {'1': 'STT_LANGUAGE_PT', '2': 10},
    {'1': 'STT_LANGUAGE_AR', '2': 11},
    {'1': 'STT_LANGUAGE_RU', '2': 12},
    {'1': 'STT_LANGUAGE_HI', '2': 13},
  ],
};

/// Descriptor for `STTLanguage`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sTTLanguageDescriptor = $convert.base64Decode(
    'CgtTVFRMYW5ndWFnZRIcChhTVFRfTEFOR1VBR0VfVU5TUEVDSUZJRUQQABIVChFTVFRfTEFOR1'
    'VBR0VfQVVUTxABEhMKD1NUVF9MQU5HVUFHRV9FThACEhMKD1NUVF9MQU5HVUFHRV9FUxADEhMK'
    'D1NUVF9MQU5HVUFHRV9GUhAEEhMKD1NUVF9MQU5HVUFHRV9ERRAFEhMKD1NUVF9MQU5HVUFHRV'
    '9aSBAGEhMKD1NUVF9MQU5HVUFHRV9KQRAHEhMKD1NUVF9MQU5HVUFHRV9LTxAIEhMKD1NUVF9M'
    'QU5HVUFHRV9JVBAJEhMKD1NUVF9MQU5HVUFHRV9QVBAKEhMKD1NUVF9MQU5HVUFHRV9BUhALEh'
    'MKD1NUVF9MQU5HVUFHRV9SVRAMEhMKD1NUVF9MQU5HVUFHRV9ISRAN');

@$core.Deprecated('Use sTTConfigurationDescriptor instead')
const STTConfiguration$json = {
  '1': 'STTConfiguration',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'language', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.STTLanguage', '10': 'language'},
    {'1': 'sample_rate', '3': 3, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'enable_vad', '3': 4, '4': 1, '5': 8, '10': 'enableVad'},
    {'1': 'audio_format', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    {'1': 'enable_punctuation', '3': 6, '4': 1, '5': 8, '10': 'enablePunctuation'},
    {'1': 'enable_diarization', '3': 7, '4': 1, '5': 8, '10': 'enableDiarization'},
    {'1': 'vocabulary_list', '3': 8, '4': 3, '5': 9, '10': 'vocabularyList'},
    {'1': 'max_alternatives', '3': 9, '4': 1, '5': 5, '10': 'maxAlternatives'},
    {'1': 'enable_word_timestamps', '3': 10, '4': 1, '5': 8, '10': 'enableWordTimestamps'},
    {'1': 'preferred_framework', '3': 11, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 0, '10': 'preferredFramework', '17': true},
    {'1': 'language_code', '3': 12, '4': 1, '5': 9, '9': 1, '10': 'languageCode', '17': true},
  ],
  '8': [
    {'1': '_preferred_framework'},
    {'1': '_language_code'},
  ],
};

/// Descriptor for `STTConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTConfigurationDescriptor = $convert.base64Decode(
    'ChBTVFRDb25maWd1cmF0aW9uEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEjcKCGxhbmd1YW'
    'dlGAIgASgOMhsucnVuYW55d2hlcmUudjEuU1RUTGFuZ3VhZ2VSCGxhbmd1YWdlEh8KC3NhbXBs'
    'ZV9yYXRlGAMgASgFUgpzYW1wbGVSYXRlEh0KCmVuYWJsZV92YWQYBCABKAhSCWVuYWJsZVZhZB'
    'I+CgxhdWRpb19mb3JtYXQYBSABKA4yGy5ydW5hbnl3aGVyZS52MS5BdWRpb0Zvcm1hdFILYXVk'
    'aW9Gb3JtYXQSLQoSZW5hYmxlX3B1bmN0dWF0aW9uGAYgASgIUhFlbmFibGVQdW5jdHVhdGlvbh'
    'ItChJlbmFibGVfZGlhcml6YXRpb24YByABKAhSEWVuYWJsZURpYXJpemF0aW9uEicKD3ZvY2Fi'
    'dWxhcnlfbGlzdBgIIAMoCVIOdm9jYWJ1bGFyeUxpc3QSKQoQbWF4X2FsdGVybmF0aXZlcxgJIA'
    'EoBVIPbWF4QWx0ZXJuYXRpdmVzEjQKFmVuYWJsZV93b3JkX3RpbWVzdGFtcHMYCiABKAhSFGVu'
    'YWJsZVdvcmRUaW1lc3RhbXBzElgKE3ByZWZlcnJlZF9mcmFtZXdvcmsYCyABKA4yIi5ydW5hbn'
    'l3aGVyZS52MS5JbmZlcmVuY2VGcmFtZXdvcmtIAFIScHJlZmVycmVkRnJhbWV3b3JriAEBEigK'
    'DWxhbmd1YWdlX2NvZGUYDCABKAlIAVIMbGFuZ3VhZ2VDb2RliAEBQhYKFF9wcmVmZXJyZWRfZn'
    'JhbWV3b3JrQhAKDl9sYW5ndWFnZV9jb2Rl');

@$core.Deprecated('Use sTTOptionsDescriptor instead')
const STTOptions$json = {
  '1': 'STTOptions',
  '2': [
    {'1': 'language', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.STTLanguage', '10': 'language'},
    {'1': 'enable_punctuation', '3': 2, '4': 1, '5': 8, '10': 'enablePunctuation'},
    {'1': 'enable_diarization', '3': 3, '4': 1, '5': 8, '10': 'enableDiarization'},
    {'1': 'max_speakers', '3': 4, '4': 1, '5': 5, '10': 'maxSpeakers'},
    {'1': 'vocabulary_list', '3': 5, '4': 3, '5': 9, '10': 'vocabularyList'},
    {'1': 'enable_word_timestamps', '3': 6, '4': 1, '5': 8, '10': 'enableWordTimestamps'},
    {'1': 'beam_size', '3': 7, '4': 1, '5': 5, '10': 'beamSize'},
    {'1': 'language_code', '3': 8, '4': 1, '5': 9, '9': 0, '10': 'languageCode', '17': true},
    {'1': 'detect_language', '3': 9, '4': 1, '5': 8, '10': 'detectLanguage'},
    {'1': 'audio_format', '3': 10, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    {'1': 'sample_rate', '3': 11, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'max_alternatives', '3': 12, '4': 1, '5': 5, '10': 'maxAlternatives'},
  ],
  '8': [
    {'1': '_language_code'},
  ],
};

/// Descriptor for `STTOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTOptionsDescriptor = $convert.base64Decode(
    'CgpTVFRPcHRpb25zEjcKCGxhbmd1YWdlGAEgASgOMhsucnVuYW55d2hlcmUudjEuU1RUTGFuZ3'
    'VhZ2VSCGxhbmd1YWdlEi0KEmVuYWJsZV9wdW5jdHVhdGlvbhgCIAEoCFIRZW5hYmxlUHVuY3R1'
    'YXRpb24SLQoSZW5hYmxlX2RpYXJpemF0aW9uGAMgASgIUhFlbmFibGVEaWFyaXphdGlvbhIhCg'
    'xtYXhfc3BlYWtlcnMYBCABKAVSC21heFNwZWFrZXJzEicKD3ZvY2FidWxhcnlfbGlzdBgFIAMo'
    'CVIOdm9jYWJ1bGFyeUxpc3QSNAoWZW5hYmxlX3dvcmRfdGltZXN0YW1wcxgGIAEoCFIUZW5hYm'
    'xlV29yZFRpbWVzdGFtcHMSGwoJYmVhbV9zaXplGAcgASgFUghiZWFtU2l6ZRIoCg1sYW5ndWFn'
    'ZV9jb2RlGAggASgJSABSDGxhbmd1YWdlQ29kZYgBARInCg9kZXRlY3RfbGFuZ3VhZ2UYCSABKA'
    'hSDmRldGVjdExhbmd1YWdlEj4KDGF1ZGlvX2Zvcm1hdBgKIAEoDjIbLnJ1bmFueXdoZXJlLnYx'
    'LkF1ZGlvRm9ybWF0UgthdWRpb0Zvcm1hdBIfCgtzYW1wbGVfcmF0ZRgLIAEoBVIKc2FtcGxlUm'
    'F0ZRIpChBtYXhfYWx0ZXJuYXRpdmVzGAwgASgFUg9tYXhBbHRlcm5hdGl2ZXNCEAoOX2xhbmd1'
    'YWdlX2NvZGU=');

@$core.Deprecated('Use wordTimestampDescriptor instead')
const WordTimestamp$json = {
  '1': 'WordTimestamp',
  '2': [
    {'1': 'word', '3': 1, '4': 1, '5': 9, '10': 'word'},
    {'1': 'start_ms', '3': 2, '4': 1, '5': 3, '10': 'startMs'},
    {'1': 'end_ms', '3': 3, '4': 1, '5': 3, '10': 'endMs'},
    {'1': 'confidence', '3': 4, '4': 1, '5': 2, '10': 'confidence'},
  ],
};

/// Descriptor for `WordTimestamp`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wordTimestampDescriptor = $convert.base64Decode(
    'Cg1Xb3JkVGltZXN0YW1wEhIKBHdvcmQYASABKAlSBHdvcmQSGQoIc3RhcnRfbXMYAiABKANSB3'
    'N0YXJ0TXMSFQoGZW5kX21zGAMgASgDUgVlbmRNcxIeCgpjb25maWRlbmNlGAQgASgCUgpjb25m'
    'aWRlbmNl');

@$core.Deprecated('Use transcriptionAlternativeDescriptor instead')
const TranscriptionAlternative$json = {
  '1': 'TranscriptionAlternative',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'words', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.WordTimestamp', '10': 'words'},
  ],
};

/// Descriptor for `TranscriptionAlternative`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transcriptionAlternativeDescriptor = $convert.base64Decode(
    'ChhUcmFuc2NyaXB0aW9uQWx0ZXJuYXRpdmUSEgoEdGV4dBgBIAEoCVIEdGV4dBIeCgpjb25maW'
    'RlbmNlGAIgASgCUgpjb25maWRlbmNlEjMKBXdvcmRzGAMgAygLMh0ucnVuYW55d2hlcmUudjEu'
    'V29yZFRpbWVzdGFtcFIFd29yZHM=');

@$core.Deprecated('Use transcriptionMetadataDescriptor instead')
const TranscriptionMetadata$json = {
  '1': 'TranscriptionMetadata',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'processing_time_ms', '3': 2, '4': 1, '5': 3, '10': 'processingTimeMs'},
    {'1': 'audio_length_ms', '3': 3, '4': 1, '5': 3, '10': 'audioLengthMs'},
    {'1': 'real_time_factor', '3': 4, '4': 1, '5': 2, '10': 'realTimeFactor'},
  ],
};

/// Descriptor for `TranscriptionMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List transcriptionMetadataDescriptor = $convert.base64Decode(
    'ChVUcmFuc2NyaXB0aW9uTWV0YWRhdGESGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQSLAoScH'
    'JvY2Vzc2luZ190aW1lX21zGAIgASgDUhBwcm9jZXNzaW5nVGltZU1zEiYKD2F1ZGlvX2xlbmd0'
    'aF9tcxgDIAEoA1INYXVkaW9MZW5ndGhNcxIoChByZWFsX3RpbWVfZmFjdG9yGAQgASgCUg5yZW'
    'FsVGltZUZhY3Rvcg==');

@$core.Deprecated('Use sTTOutputDescriptor instead')
const STTOutput$json = {
  '1': 'STTOutput',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'language', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.STTLanguage', '10': 'language'},
    {'1': 'confidence', '3': 3, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'words', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.WordTimestamp', '10': 'words'},
    {'1': 'alternatives', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.TranscriptionAlternative', '10': 'alternatives'},
    {'1': 'metadata', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.TranscriptionMetadata', '10': 'metadata'},
    {'1': 'language_code', '3': 7, '4': 1, '5': 9, '9': 0, '10': 'languageCode', '17': true},
    {'1': 'timestamp_ms', '3': 8, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'duration_ms', '3': 9, '4': 1, '5': 3, '10': 'durationMs'},
  ],
  '8': [
    {'1': '_language_code'},
  ],
};

/// Descriptor for `STTOutput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTOutputDescriptor = $convert.base64Decode(
    'CglTVFRPdXRwdXQSEgoEdGV4dBgBIAEoCVIEdGV4dBI3CghsYW5ndWFnZRgCIAEoDjIbLnJ1bm'
    'FueXdoZXJlLnYxLlNUVExhbmd1YWdlUghsYW5ndWFnZRIeCgpjb25maWRlbmNlGAMgASgCUgpj'
    'b25maWRlbmNlEjMKBXdvcmRzGAQgAygLMh0ucnVuYW55d2hlcmUudjEuV29yZFRpbWVzdGFtcF'
    'IFd29yZHMSTAoMYWx0ZXJuYXRpdmVzGAUgAygLMigucnVuYW55d2hlcmUudjEuVHJhbnNjcmlw'
    'dGlvbkFsdGVybmF0aXZlUgxhbHRlcm5hdGl2ZXMSQQoIbWV0YWRhdGEYBiABKAsyJS5ydW5hbn'
    'l3aGVyZS52MS5UcmFuc2NyaXB0aW9uTWV0YWRhdGFSCG1ldGFkYXRhEigKDWxhbmd1YWdlX2Nv'
    'ZGUYByABKAlIAFIMbGFuZ3VhZ2VDb2RliAEBEiEKDHRpbWVzdGFtcF9tcxgIIAEoA1ILdGltZX'
    'N0YW1wTXMSHwoLZHVyYXRpb25fbXMYCSABKANSCmR1cmF0aW9uTXNCEAoOX2xhbmd1YWdlX2Nv'
    'ZGU=');

@$core.Deprecated('Use sTTPartialResultDescriptor instead')
const STTPartialResult$json = {
  '1': 'STTPartialResult',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'is_final', '3': 2, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'stability', '3': 3, '4': 1, '5': 2, '10': 'stability'},
    {'1': 'confidence', '3': 4, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'language', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.STTLanguage', '10': 'language'},
    {'1': 'timestamp_ms', '3': 6, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'alternatives', '3': 7, '4': 3, '5': 11, '6': '.runanywhere.v1.TranscriptionAlternative', '10': 'alternatives'},
    {'1': 'language_code', '3': 8, '4': 1, '5': 9, '9': 0, '10': 'languageCode', '17': true},
  ],
  '8': [
    {'1': '_language_code'},
  ],
};

/// Descriptor for `STTPartialResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTPartialResultDescriptor = $convert.base64Decode(
    'ChBTVFRQYXJ0aWFsUmVzdWx0EhIKBHRleHQYASABKAlSBHRleHQSGQoIaXNfZmluYWwYAiABKA'
    'hSB2lzRmluYWwSHAoJc3RhYmlsaXR5GAMgASgCUglzdGFiaWxpdHkSHgoKY29uZmlkZW5jZRgE'
    'IAEoAlIKY29uZmlkZW5jZRI3CghsYW5ndWFnZRgFIAEoDjIbLnJ1bmFueXdoZXJlLnYxLlNUVE'
    'xhbmd1YWdlUghsYW5ndWFnZRIhCgx0aW1lc3RhbXBfbXMYBiABKANSC3RpbWVzdGFtcE1zEkwK'
    'DGFsdGVybmF0aXZlcxgHIAMoCzIoLnJ1bmFueXdoZXJlLnYxLlRyYW5zY3JpcHRpb25BbHRlcm'
    '5hdGl2ZVIMYWx0ZXJuYXRpdmVzEigKDWxhbmd1YWdlX2NvZGUYCCABKAlIAFIMbGFuZ3VhZ2VD'
    'b2RliAEBQhAKDl9sYW5ndWFnZV9jb2Rl');

