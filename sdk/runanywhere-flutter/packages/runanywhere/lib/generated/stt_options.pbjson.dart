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

@$core.Deprecated('Use sTTAudioEncodingDescriptor instead')
const STTAudioEncoding$json = {
  '1': 'STTAudioEncoding',
  '2': [
    {'1': 'STT_AUDIO_ENCODING_UNSPECIFIED', '2': 0},
    {'1': 'STT_AUDIO_ENCODING_PCM_S16_LE', '2': 1},
    {'1': 'STT_AUDIO_ENCODING_PCM_F32_LE', '2': 2},
    {'1': 'STT_AUDIO_ENCODING_CONTAINER', '2': 3},
  ],
};

/// Descriptor for `STTAudioEncoding`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sTTAudioEncodingDescriptor = $convert.base64Decode(
    'ChBTVFRBdWRpb0VuY29kaW5nEiIKHlNUVF9BVURJT19FTkNPRElOR19VTlNQRUNJRklFRBAAEi'
    'EKHVNUVF9BVURJT19FTkNPRElOR19QQ01fUzE2X0xFEAESIQodU1RUX0FVRElPX0VOQ09ESU5H'
    'X1BDTV9GMzJfTEUQAhIgChxTVFRfQVVESU9fRU5DT0RJTkdfQ09OVEFJTkVSEAM=');

@$core.Deprecated('Use sTTStreamEventKindDescriptor instead')
const STTStreamEventKind$json = {
  '1': 'STTStreamEventKind',
  '2': [
    {'1': 'STT_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'STT_STREAM_EVENT_KIND_STARTED', '2': 1},
    {'1': 'STT_STREAM_EVENT_KIND_PARTIAL', '2': 2},
    {'1': 'STT_STREAM_EVENT_KIND_FINAL', '2': 3},
    {'1': 'STT_STREAM_EVENT_KIND_ENDPOINT', '2': 4},
    {'1': 'STT_STREAM_EVENT_KIND_ERROR', '2': 5},
  ],
};

/// Descriptor for `STTStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sTTStreamEventKindDescriptor = $convert.base64Decode(
    'ChJTVFRTdHJlYW1FdmVudEtpbmQSJQohU1RUX1NUUkVBTV9FVkVOVF9LSU5EX1VOU1BFQ0lGSU'
    'VEEAASIQodU1RUX1NUUkVBTV9FVkVOVF9LSU5EX1NUQVJURUQQARIhCh1TVFRfU1RSRUFNX0VW'
    'RU5UX0tJTkRfUEFSVElBTBACEh8KG1NUVF9TVFJFQU1fRVZFTlRfS0lORF9GSU5BTBADEiIKHl'
    'NUVF9TVFJFQU1fRVZFTlRfS0lORF9FTkRQT0lOVBAEEh8KG1NUVF9TVFJFQU1fRVZFTlRfS0lO'
    'RF9FUlJPUhAF');

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
    {'1': 'chunk_duration_ms', '3': 13, '4': 1, '5': 5, '10': 'chunkDurationMs'},
    {'1': 'endpoint_silence_ms', '3': 14, '4': 1, '5': 5, '10': 'endpointSilenceMs'},
    {'1': 'suppress_blank', '3': 15, '4': 1, '5': 8, '10': 'suppressBlank'},
    {'1': 'translate_to_english', '3': 16, '4': 1, '5': 8, '10': 'translateToEnglish'},
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
    'F0ZRIpChBtYXhfYWx0ZXJuYXRpdmVzGAwgASgFUg9tYXhBbHRlcm5hdGl2ZXMSKgoRY2h1bmtf'
    'ZHVyYXRpb25fbXMYDSABKAVSD2NodW5rRHVyYXRpb25NcxIuChNlbmRwb2ludF9zaWxlbmNlX2'
    '1zGA4gASgFUhFlbmRwb2ludFNpbGVuY2VNcxIlCg5zdXBwcmVzc19ibGFuaxgPIAEoCFINc3Vw'
    'cHJlc3NCbGFuaxIwChR0cmFuc2xhdGVfdG9fZW5nbGlzaBgQIAEoCFISdHJhbnNsYXRlVG9Fbm'
    'dsaXNoQhAKDl9sYW5ndWFnZV9jb2Rl');

@$core.Deprecated('Use sTTAudioSourceDescriptor instead')
const STTAudioSource$json = {
  '1': 'STTAudioSource',
  '2': [
    {'1': 'audio_data', '3': 1, '4': 1, '5': 12, '9': 0, '10': 'audioData'},
    {'1': 'file_uri', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'fileUri'},
    {'1': 'adapter_handle', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'adapterHandle'},
    {'1': 'encoding', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.STTAudioEncoding', '10': 'encoding'},
    {'1': 'audio_format', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    {'1': 'sample_rate', '3': 6, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'channels', '3': 7, '4': 1, '5': 5, '10': 'channels'},
    {'1': 'bits_per_sample', '3': 8, '4': 1, '5': 5, '10': 'bitsPerSample'},
    {'1': 'duration_ms', '3': 9, '4': 1, '5': 3, '10': 'durationMs'},
  ],
  '8': [
    {'1': 'source'},
  ],
};

/// Descriptor for `STTAudioSource`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTAudioSourceDescriptor = $convert.base64Decode(
    'Cg5TVFRBdWRpb1NvdXJjZRIfCgphdWRpb19kYXRhGAEgASgMSABSCWF1ZGlvRGF0YRIbCghmaW'
    'xlX3VyaRgCIAEoCUgAUgdmaWxlVXJpEicKDmFkYXB0ZXJfaGFuZGxlGAMgASgJSABSDWFkYXB0'
    'ZXJIYW5kbGUSPAoIZW5jb2RpbmcYBCABKA4yIC5ydW5hbnl3aGVyZS52MS5TVFRBdWRpb0VuY2'
    '9kaW5nUghlbmNvZGluZxI+CgxhdWRpb19mb3JtYXQYBSABKA4yGy5ydW5hbnl3aGVyZS52MS5B'
    'dWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQSHwoLc2FtcGxlX3JhdGUYBiABKAVSCnNhbXBsZVJhdG'
    'USGgoIY2hhbm5lbHMYByABKAVSCGNoYW5uZWxzEiYKD2JpdHNfcGVyX3NhbXBsZRgIIAEoBVIN'
    'Yml0c1BlclNhbXBsZRIfCgtkdXJhdGlvbl9tcxgJIAEoA1IKZHVyYXRpb25Nc0IICgZzb3VyY2'
    'U=');

@$core.Deprecated('Use sTTTranscriptionRequestDescriptor instead')
const STTTranscriptionRequest$json = {
  '1': 'STTTranscriptionRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'audio', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.STTAudioSource', '9': 0, '10': 'audio', '17': true},
    {'1': 'options', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.STTOptions', '9': 1, '10': 'options', '17': true},
    {'1': 'metadata', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.STTTranscriptionRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [STTTranscriptionRequest_MetadataEntry$json],
  '8': [
    {'1': '_audio'},
    {'1': '_options'},
  ],
};

@$core.Deprecated('Use sTTTranscriptionRequestDescriptor instead')
const STTTranscriptionRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `STTTranscriptionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTTranscriptionRequestDescriptor = $convert.base64Decode(
    'ChdTVFRUcmFuc2NyaXB0aW9uUmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZXN0SW'
    'QSOQoFYXVkaW8YAiABKAsyHi5ydW5hbnl3aGVyZS52MS5TVFRBdWRpb1NvdXJjZUgAUgVhdWRp'
    'b4gBARI5CgdvcHRpb25zGAMgASgLMhoucnVuYW55d2hlcmUudjEuU1RUT3B0aW9uc0gBUgdvcH'
    'Rpb25ziAEBElEKCG1ldGFkYXRhGAQgAygLMjUucnVuYW55d2hlcmUudjEuU1RUVHJhbnNjcmlw'
    'dGlvblJlcXVlc3QuTWV0YWRhdGFFbnRyeVIIbWV0YWRhdGEaOwoNTWV0YWRhdGFFbnRyeRIQCg'
    'NrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWU6AjgBQggKBl9hdWRpb0IKCghf'
    'b3B0aW9ucw==');

@$core.Deprecated('Use wordTimestampDescriptor instead')
const WordTimestamp$json = {
  '1': 'WordTimestamp',
  '2': [
    {'1': 'word', '3': 1, '4': 1, '5': 9, '10': 'word'},
    {'1': 'start_ms', '3': 2, '4': 1, '5': 3, '10': 'startMs'},
    {'1': 'end_ms', '3': 3, '4': 1, '5': 3, '10': 'endMs'},
    {'1': 'confidence', '3': 4, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'speaker_id', '3': 5, '4': 1, '5': 9, '9': 0, '10': 'speakerId', '17': true},
  ],
  '8': [
    {'1': '_speaker_id'},
  ],
};

/// Descriptor for `WordTimestamp`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wordTimestampDescriptor = $convert.base64Decode(
    'Cg1Xb3JkVGltZXN0YW1wEhIKBHdvcmQYASABKAlSBHdvcmQSGQoIc3RhcnRfbXMYAiABKANSB3'
    'N0YXJ0TXMSFQoGZW5kX21zGAMgASgDUgVlbmRNcxIeCgpjb25maWRlbmNlGAQgASgCUgpjb25m'
    'aWRlbmNlEiIKCnNwZWFrZXJfaWQYBSABKAlIAFIJc3BlYWtlcklkiAEBQg0KC19zcGVha2VyX2'
    'lk');

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
    {'1': 'speaker_ids', '3': 10, '4': 3, '5': 9, '10': 'speakerIds'},
    {'1': 'error_message', '3': 11, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 12, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'segment_index', '3': 13, '4': 1, '5': 5, '10': 'segmentIndex'},
  ],
  '8': [
    {'1': '_language_code'},
    {'1': '_error_message'},
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
    'N0YW1wTXMSHwoLZHVyYXRpb25fbXMYCSABKANSCmR1cmF0aW9uTXMSHwoLc3BlYWtlcl9pZHMY'
    'CiADKAlSCnNwZWFrZXJJZHMSKAoNZXJyb3JfbWVzc2FnZRgLIAEoCUgBUgxlcnJvck1lc3NhZ2'
    'WIAQESHQoKZXJyb3JfY29kZRgMIAEoBVIJZXJyb3JDb2RlEiMKDXNlZ21lbnRfaW5kZXgYDSAB'
    'KAVSDHNlZ21lbnRJbmRleEIQCg5fbGFuZ3VhZ2VfY29kZUIQCg5fZXJyb3JfbWVzc2FnZQ==');

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
    {'1': 'request_id', '3': 9, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'segment_index', '3': 10, '4': 1, '5': 5, '10': 'segmentIndex'},
    {'1': 'audio_start_ms', '3': 11, '4': 1, '5': 3, '10': 'audioStartMs'},
    {'1': 'audio_end_ms', '3': 12, '4': 1, '5': 3, '10': 'audioEndMs'},
    {'1': 'final_output', '3': 13, '4': 1, '5': 11, '6': '.runanywhere.v1.STTOutput', '9': 1, '10': 'finalOutput', '17': true},
  ],
  '8': [
    {'1': '_language_code'},
    {'1': '_final_output'},
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
    'b2RliAEBEh0KCnJlcXVlc3RfaWQYCSABKAlSCXJlcXVlc3RJZBIjCg1zZWdtZW50X2luZGV4GA'
    'ogASgFUgxzZWdtZW50SW5kZXgSJAoOYXVkaW9fc3RhcnRfbXMYCyABKANSDGF1ZGlvU3RhcnRN'
    'cxIgCgxhdWRpb19lbmRfbXMYDCABKANSCmF1ZGlvRW5kTXMSQQoMZmluYWxfb3V0cHV0GA0gAS'
    'gLMhkucnVuYW55d2hlcmUudjEuU1RUT3V0cHV0SAFSC2ZpbmFsT3V0cHV0iAEBQhAKDl9sYW5n'
    'dWFnZV9jb2RlQg8KDV9maW5hbF9vdXRwdXQ=');

@$core.Deprecated('Use sTTStreamEventDescriptor instead')
const STTStreamEvent$json = {
  '1': 'STTStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'kind', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.STTStreamEventKind', '10': 'kind'},
    {'1': 'partial', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.STTPartialResult', '9': 0, '10': 'partial', '17': true},
    {'1': 'final_output', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.STTOutput', '9': 1, '10': 'finalOutput', '17': true},
    {'1': 'error_message', '3': 7, '4': 1, '5': 9, '9': 2, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 8, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_partial'},
    {'1': '_final_output'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `STTStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTStreamEventDescriptor = $convert.base64Decode(
    'Cg5TVFRTdHJlYW1FdmVudBIQCgNzZXEYASABKARSA3NlcRIhCgx0aW1lc3RhbXBfdXMYAiABKA'
    'NSC3RpbWVzdGFtcFVzEh0KCnJlcXVlc3RfaWQYAyABKAlSCXJlcXVlc3RJZBI2CgRraW5kGAQg'
    'ASgOMiIucnVuYW55d2hlcmUudjEuU1RUU3RyZWFtRXZlbnRLaW5kUgRraW5kEj8KB3BhcnRpYW'
    'wYBSABKAsyIC5ydW5hbnl3aGVyZS52MS5TVFRQYXJ0aWFsUmVzdWx0SABSB3BhcnRpYWyIAQES'
    'QQoMZmluYWxfb3V0cHV0GAYgASgLMhkucnVuYW55d2hlcmUudjEuU1RUT3V0cHV0SAFSC2Zpbm'
    'FsT3V0cHV0iAEBEigKDWVycm9yX21lc3NhZ2UYByABKAlIAlIMZXJyb3JNZXNzYWdliAEBEh0K'
    'CmVycm9yX2NvZGUYCCABKAVSCWVycm9yQ29kZUIKCghfcGFydGlhbEIPCg1fZmluYWxfb3V0cH'
    'V0QhAKDl9lcnJvcl9tZXNzYWdl');

@$core.Deprecated('Use sTTServiceStateDescriptor instead')
const STTServiceState$json = {
  '1': 'STTServiceState',
  '2': [
    {'1': 'is_ready', '3': 1, '4': 1, '5': 8, '10': 'isReady'},
    {'1': 'current_model', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'currentModel', '17': true},
    {'1': 'supports_streaming', '3': 3, '4': 1, '5': 8, '10': 'supportsStreaming'},
    {'1': 'supported_language_codes', '3': 4, '4': 3, '5': 9, '10': 'supportedLanguageCodes'},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 6, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_current_model'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `STTServiceState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTServiceStateDescriptor = $convert.base64Decode(
    'Cg9TVFRTZXJ2aWNlU3RhdGUSGQoIaXNfcmVhZHkYASABKAhSB2lzUmVhZHkSKAoNY3VycmVudF'
    '9tb2RlbBgCIAEoCUgAUgxjdXJyZW50TW9kZWyIAQESLQoSc3VwcG9ydHNfc3RyZWFtaW5nGAMg'
    'ASgIUhFzdXBwb3J0c1N0cmVhbWluZxI4ChhzdXBwb3J0ZWRfbGFuZ3VhZ2VfY29kZXMYBCADKA'
    'lSFnN1cHBvcnRlZExhbmd1YWdlQ29kZXMSKAoNZXJyb3JfbWVzc2FnZRgFIAEoCUgBUgxlcnJv'
    'ck1lc3NhZ2WIAQESHQoKZXJyb3JfY29kZRgGIAEoBVIJZXJyb3JDb2RlQhAKDl9jdXJyZW50X2'
    '1vZGVsQhAKDl9lcnJvcl9tZXNzYWdl');

@$core.Deprecated('Use sTTLanguageDetectionResultDescriptor instead')
const STTLanguageDetectionResult$json = {
  '1': 'STTLanguageDetectionResult',
  '2': [
    {'1': 'language', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.STTLanguage', '10': 'language'},
    {'1': 'language_code', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'languageCode', '17': true},
    {'1': 'confidence', '3': 3, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'alternatives', '3': 4, '4': 3, '5': 9, '10': 'alternatives'},
  ],
  '8': [
    {'1': '_language_code'},
  ],
};

/// Descriptor for `STTLanguageDetectionResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sTTLanguageDetectionResultDescriptor = $convert.base64Decode(
    'ChpTVFRMYW5ndWFnZURldGVjdGlvblJlc3VsdBI3CghsYW5ndWFnZRgBIAEoDjIbLnJ1bmFueX'
    'doZXJlLnYxLlNUVExhbmd1YWdlUghsYW5ndWFnZRIoCg1sYW5ndWFnZV9jb2RlGAIgASgJSABS'
    'DGxhbmd1YWdlQ29kZYgBARIeCgpjb25maWRlbmNlGAMgASgCUgpjb25maWRlbmNlEiIKDGFsdG'
    'VybmF0aXZlcxgEIAMoCVIMYWx0ZXJuYXRpdmVzQhAKDl9sYW5ndWFnZV9jb2Rl');

const $core.Map<$core.String, $core.dynamic> STTServiceBase$json = {
  '1': 'STT',
  '2': [
    {'1': 'Transcribe', '2': '.runanywhere.v1.STTTranscriptionRequest', '3': '.runanywhere.v1.STTOutput'},
    {'1': 'Stream', '2': '.runanywhere.v1.STTTranscriptionRequest', '3': '.runanywhere.v1.STTStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use sTTServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> STTServiceBase$messageJson = {
  '.runanywhere.v1.STTTranscriptionRequest': STTTranscriptionRequest$json,
  '.runanywhere.v1.STTAudioSource': STTAudioSource$json,
  '.runanywhere.v1.STTOptions': STTOptions$json,
  '.runanywhere.v1.STTTranscriptionRequest.MetadataEntry': STTTranscriptionRequest_MetadataEntry$json,
  '.runanywhere.v1.STTOutput': STTOutput$json,
  '.runanywhere.v1.WordTimestamp': WordTimestamp$json,
  '.runanywhere.v1.TranscriptionAlternative': TranscriptionAlternative$json,
  '.runanywhere.v1.TranscriptionMetadata': TranscriptionMetadata$json,
  '.runanywhere.v1.STTStreamEvent': STTStreamEvent$json,
  '.runanywhere.v1.STTPartialResult': STTPartialResult$json,
};

/// Descriptor for `STT`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List sTTServiceDescriptor = $convert.base64Decode(
    'CgNTVFQSUAoKVHJhbnNjcmliZRInLnJ1bmFueXdoZXJlLnYxLlNUVFRyYW5zY3JpcHRpb25SZX'
    'F1ZXN0GhkucnVuYW55d2hlcmUudjEuU1RUT3V0cHV0ElMKBlN0cmVhbRInLnJ1bmFueXdoZXJl'
    'LnYxLlNUVFRyYW5zY3JpcHRpb25SZXF1ZXN0Gh4ucnVuYW55d2hlcmUudjEuU1RUU3RyZWFtRX'
    'ZlbnQwAQ==');

