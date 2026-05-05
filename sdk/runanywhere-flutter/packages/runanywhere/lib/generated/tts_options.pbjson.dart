//
//  Generated code. Do not modify.
//  source: tts_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use tTSVoiceGenderDescriptor instead')
const TTSVoiceGender$json = {
  '1': 'TTSVoiceGender',
  '2': [
    {'1': 'TTS_VOICE_GENDER_UNSPECIFIED', '2': 0},
    {'1': 'TTS_VOICE_GENDER_MALE', '2': 1},
    {'1': 'TTS_VOICE_GENDER_FEMALE', '2': 2},
    {'1': 'TTS_VOICE_GENDER_NEUTRAL', '2': 3},
  ],
};

/// Descriptor for `TTSVoiceGender`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List tTSVoiceGenderDescriptor = $convert.base64Decode(
    'Cg5UVFNWb2ljZUdlbmRlchIgChxUVFNfVk9JQ0VfR0VOREVSX1VOU1BFQ0lGSUVEEAASGQoVVF'
    'RTX1ZPSUNFX0dFTkRFUl9NQUxFEAESGwoXVFRTX1ZPSUNFX0dFTkRFUl9GRU1BTEUQAhIcChhU'
    'VFNfVk9JQ0VfR0VOREVSX05FVVRSQUwQAw==');

@$core.Deprecated('Use tTSStreamEventKindDescriptor instead')
const TTSStreamEventKind$json = {
  '1': 'TTSStreamEventKind',
  '2': [
    {'1': 'TTS_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'TTS_STREAM_EVENT_KIND_STARTED', '2': 1},
    {'1': 'TTS_STREAM_EVENT_KIND_AUDIO_CHUNK', '2': 2},
    {'1': 'TTS_STREAM_EVENT_KIND_PHONEME', '2': 3},
    {'1': 'TTS_STREAM_EVENT_KIND_COMPLETED', '2': 4},
    {'1': 'TTS_STREAM_EVENT_KIND_ERROR', '2': 5},
    {'1': 'TTS_STREAM_EVENT_KIND_PROGRESS', '2': 6},
  ],
};

/// Descriptor for `TTSStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List tTSStreamEventKindDescriptor = $convert.base64Decode(
    'ChJUVFNTdHJlYW1FdmVudEtpbmQSJQohVFRTX1NUUkVBTV9FVkVOVF9LSU5EX1VOU1BFQ0lGSU'
    'VEEAASIQodVFRTX1NUUkVBTV9FVkVOVF9LSU5EX1NUQVJURUQQARIlCiFUVFNfU1RSRUFNX0VW'
    'RU5UX0tJTkRfQVVESU9fQ0hVTksQAhIhCh1UVFNfU1RSRUFNX0VWRU5UX0tJTkRfUEhPTkVNRR'
    'ADEiMKH1RUU19TVFJFQU1fRVZFTlRfS0lORF9DT01QTEVURUQQBBIfChtUVFNfU1RSRUFNX0VW'
    'RU5UX0tJTkRfRVJST1IQBRIiCh5UVFNfU1RSRUFNX0VWRU5UX0tJTkRfUFJPR1JFU1MQBg==');

@$core.Deprecated('Use tTSConfigurationDescriptor instead')
const TTSConfiguration$json = {
  '1': 'TTSConfiguration',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'voice', '3': 2, '4': 1, '5': 9, '10': 'voice'},
    {'1': 'language_code', '3': 3, '4': 1, '5': 9, '10': 'languageCode'},
    {'1': 'speaking_rate', '3': 4, '4': 1, '5': 2, '10': 'speakingRate'},
    {'1': 'pitch', '3': 5, '4': 1, '5': 2, '10': 'pitch'},
    {'1': 'volume', '3': 6, '4': 1, '5': 2, '10': 'volume'},
    {'1': 'audio_format', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    {'1': 'sample_rate', '3': 8, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'enable_neural_voice', '3': 9, '4': 1, '5': 8, '10': 'enableNeuralVoice'},
    {'1': 'enable_ssml', '3': 10, '4': 1, '5': 8, '10': 'enableSsml'},
    {'1': 'preferred_framework', '3': 11, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 0, '10': 'preferredFramework', '17': true},
  ],
  '8': [
    {'1': '_preferred_framework'},
  ],
};

/// Descriptor for `TTSConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSConfigurationDescriptor = $convert.base64Decode(
    'ChBUVFNDb25maWd1cmF0aW9uEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEhQKBXZvaWNlGA'
    'IgASgJUgV2b2ljZRIjCg1sYW5ndWFnZV9jb2RlGAMgASgJUgxsYW5ndWFnZUNvZGUSIwoNc3Bl'
    'YWtpbmdfcmF0ZRgEIAEoAlIMc3BlYWtpbmdSYXRlEhQKBXBpdGNoGAUgASgCUgVwaXRjaBIWCg'
    'Z2b2x1bWUYBiABKAJSBnZvbHVtZRI+CgxhdWRpb19mb3JtYXQYByABKA4yGy5ydW5hbnl3aGVy'
    'ZS52MS5BdWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQSHwoLc2FtcGxlX3JhdGUYCCABKAVSCnNhbX'
    'BsZVJhdGUSLgoTZW5hYmxlX25ldXJhbF92b2ljZRgJIAEoCFIRZW5hYmxlTmV1cmFsVm9pY2US'
    'HwoLZW5hYmxlX3NzbWwYCiABKAhSCmVuYWJsZVNzbWwSWAoTcHJlZmVycmVkX2ZyYW1ld29yax'
    'gLIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkluZmVyZW5jZUZyYW1ld29ya0gAUhJwcmVmZXJyZWRG'
    'cmFtZXdvcmuIAQFCFgoUX3ByZWZlcnJlZF9mcmFtZXdvcms=');

@$core.Deprecated('Use tTSOptionsDescriptor instead')
const TTSOptions$json = {
  '1': 'TTSOptions',
  '2': [
    {'1': 'voice', '3': 1, '4': 1, '5': 9, '10': 'voice'},
    {'1': 'language_code', '3': 2, '4': 1, '5': 9, '10': 'languageCode'},
    {'1': 'speaking_rate', '3': 3, '4': 1, '5': 2, '10': 'speakingRate'},
    {'1': 'pitch', '3': 4, '4': 1, '5': 2, '10': 'pitch'},
    {'1': 'volume', '3': 5, '4': 1, '5': 2, '10': 'volume'},
    {'1': 'enable_ssml', '3': 6, '4': 1, '5': 8, '10': 'enableSsml'},
    {'1': 'audio_format', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    {'1': 'sample_rate', '3': 8, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'speaker_id', '3': 9, '4': 1, '5': 5, '10': 'speakerId'},
    {'1': 'speed', '3': 10, '4': 1, '5': 2, '10': 'speed'},
    {'1': 'style', '3': 11, '4': 1, '5': 9, '9': 0, '10': 'style', '17': true},
  ],
  '8': [
    {'1': '_style'},
  ],
};

/// Descriptor for `TTSOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSOptionsDescriptor = $convert.base64Decode(
    'CgpUVFNPcHRpb25zEhQKBXZvaWNlGAEgASgJUgV2b2ljZRIjCg1sYW5ndWFnZV9jb2RlGAIgAS'
    'gJUgxsYW5ndWFnZUNvZGUSIwoNc3BlYWtpbmdfcmF0ZRgDIAEoAlIMc3BlYWtpbmdSYXRlEhQK'
    'BXBpdGNoGAQgASgCUgVwaXRjaBIWCgZ2b2x1bWUYBSABKAJSBnZvbHVtZRIfCgtlbmFibGVfc3'
    'NtbBgGIAEoCFIKZW5hYmxlU3NtbBI+CgxhdWRpb19mb3JtYXQYByABKA4yGy5ydW5hbnl3aGVy'
    'ZS52MS5BdWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQSHwoLc2FtcGxlX3JhdGUYCCABKAVSCnNhbX'
    'BsZVJhdGUSHQoKc3BlYWtlcl9pZBgJIAEoBVIJc3BlYWtlcklkEhQKBXNwZWVkGAogASgCUgVz'
    'cGVlZBIZCgVzdHlsZRgLIAEoCUgAUgVzdHlsZYgBAUIICgZfc3R5bGU=');

@$core.Deprecated('Use tTSSynthesisRequestDescriptor instead')
const TTSSynthesisRequest$json = {
  '1': 'TTSSynthesisRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'ssml', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'ssml', '17': true},
    {'1': 'options', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.TTSOptions', '9': 1, '10': 'options', '17': true},
    {'1': 'metadata', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.TTSSynthesisRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [TTSSynthesisRequest_MetadataEntry$json],
  '8': [
    {'1': '_ssml'},
    {'1': '_options'},
  ],
};

@$core.Deprecated('Use tTSSynthesisRequestDescriptor instead')
const TTSSynthesisRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `TTSSynthesisRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSSynthesisRequestDescriptor = $convert.base64Decode(
    'ChNUVFNTeW50aGVzaXNSZXF1ZXN0Eh0KCnJlcXVlc3RfaWQYASABKAlSCXJlcXVlc3RJZBISCg'
    'R0ZXh0GAIgASgJUgR0ZXh0EhcKBHNzbWwYAyABKAlIAFIEc3NtbIgBARI5CgdvcHRpb25zGAQg'
    'ASgLMhoucnVuYW55d2hlcmUudjEuVFRTT3B0aW9uc0gBUgdvcHRpb25ziAEBEk0KCG1ldGFkYX'
    'RhGAUgAygLMjEucnVuYW55d2hlcmUudjEuVFRTU3ludGhlc2lzUmVxdWVzdC5NZXRhZGF0YUVu'
    'dHJ5UghtZXRhZGF0YRo7Cg1NZXRhZGF0YUVudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbH'
    'VlGAIgASgJUgV2YWx1ZToCOAFCBwoFX3NzbWxCCgoIX29wdGlvbnM=');

@$core.Deprecated('Use tTSPhonemeTimestampDescriptor instead')
const TTSPhonemeTimestamp$json = {
  '1': 'TTSPhonemeTimestamp',
  '2': [
    {'1': 'phoneme', '3': 1, '4': 1, '5': 9, '10': 'phoneme'},
    {'1': 'start_ms', '3': 2, '4': 1, '5': 3, '10': 'startMs'},
    {'1': 'end_ms', '3': 3, '4': 1, '5': 3, '10': 'endMs'},
  ],
};

/// Descriptor for `TTSPhonemeTimestamp`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSPhonemeTimestampDescriptor = $convert.base64Decode(
    'ChNUVFNQaG9uZW1lVGltZXN0YW1wEhgKB3Bob25lbWUYASABKAlSB3Bob25lbWUSGQoIc3Rhcn'
    'RfbXMYAiABKANSB3N0YXJ0TXMSFQoGZW5kX21zGAMgASgDUgVlbmRNcw==');

@$core.Deprecated('Use tTSSynthesisMetadataDescriptor instead')
const TTSSynthesisMetadata$json = {
  '1': 'TTSSynthesisMetadata',
  '2': [
    {'1': 'voice_id', '3': 1, '4': 1, '5': 9, '10': 'voiceId'},
    {'1': 'language_code', '3': 2, '4': 1, '5': 9, '10': 'languageCode'},
    {'1': 'processing_time_ms', '3': 3, '4': 1, '5': 3, '10': 'processingTimeMs'},
    {'1': 'character_count', '3': 4, '4': 1, '5': 5, '10': 'characterCount'},
    {'1': 'audio_duration_ms', '3': 5, '4': 1, '5': 3, '10': 'audioDurationMs'},
    {'1': 'characters_per_second', '3': 6, '4': 1, '5': 2, '10': 'charactersPerSecond'},
  ],
};

/// Descriptor for `TTSSynthesisMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSSynthesisMetadataDescriptor = $convert.base64Decode(
    'ChRUVFNTeW50aGVzaXNNZXRhZGF0YRIZCgh2b2ljZV9pZBgBIAEoCVIHdm9pY2VJZBIjCg1sYW'
    '5ndWFnZV9jb2RlGAIgASgJUgxsYW5ndWFnZUNvZGUSLAoScHJvY2Vzc2luZ190aW1lX21zGAMg'
    'ASgDUhBwcm9jZXNzaW5nVGltZU1zEicKD2NoYXJhY3Rlcl9jb3VudBgEIAEoBVIOY2hhcmFjdG'
    'VyQ291bnQSKgoRYXVkaW9fZHVyYXRpb25fbXMYBSABKANSD2F1ZGlvRHVyYXRpb25NcxIyChVj'
    'aGFyYWN0ZXJzX3Blcl9zZWNvbmQYBiABKAJSE2NoYXJhY3RlcnNQZXJTZWNvbmQ=');

@$core.Deprecated('Use tTSOutputDescriptor instead')
const TTSOutput$json = {
  '1': 'TTSOutput',
  '2': [
    {'1': 'audio_data', '3': 1, '4': 1, '5': 12, '10': 'audioData'},
    {'1': 'audio_format', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    {'1': 'sample_rate', '3': 3, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'duration_ms', '3': 4, '4': 1, '5': 3, '10': 'durationMs'},
    {'1': 'phoneme_timestamps', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.TTSPhonemeTimestamp', '10': 'phonemeTimestamps'},
    {'1': 'metadata', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.TTSSynthesisMetadata', '10': 'metadata'},
    {'1': 'timestamp_ms', '3': 7, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'chunk_index', '3': 8, '4': 1, '5': 5, '10': 'chunkIndex'},
    {'1': 'is_final', '3': 9, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'audio_size_bytes', '3': 10, '4': 1, '5': 3, '10': 'audioSizeBytes'},
    {'1': 'error_message', '3': 11, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 12, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_error_message'},
  ],
};

/// Descriptor for `TTSOutput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSOutputDescriptor = $convert.base64Decode(
    'CglUVFNPdXRwdXQSHQoKYXVkaW9fZGF0YRgBIAEoDFIJYXVkaW9EYXRhEj4KDGF1ZGlvX2Zvcm'
    '1hdBgCIAEoDjIbLnJ1bmFueXdoZXJlLnYxLkF1ZGlvRm9ybWF0UgthdWRpb0Zvcm1hdBIfCgtz'
    'YW1wbGVfcmF0ZRgDIAEoBVIKc2FtcGxlUmF0ZRIfCgtkdXJhdGlvbl9tcxgEIAEoA1IKZHVyYX'
    'Rpb25NcxJSChJwaG9uZW1lX3RpbWVzdGFtcHMYBSADKAsyIy5ydW5hbnl3aGVyZS52MS5UVFNQ'
    'aG9uZW1lVGltZXN0YW1wUhFwaG9uZW1lVGltZXN0YW1wcxJACghtZXRhZGF0YRgGIAEoCzIkLn'
    'J1bmFueXdoZXJlLnYxLlRUU1N5bnRoZXNpc01ldGFkYXRhUghtZXRhZGF0YRIhCgx0aW1lc3Rh'
    'bXBfbXMYByABKANSC3RpbWVzdGFtcE1zEh8KC2NodW5rX2luZGV4GAggASgFUgpjaHVua0luZG'
    'V4EhkKCGlzX2ZpbmFsGAkgASgIUgdpc0ZpbmFsEigKEGF1ZGlvX3NpemVfYnl0ZXMYCiABKANS'
    'DmF1ZGlvU2l6ZUJ5dGVzEigKDWVycm9yX21lc3NhZ2UYCyABKAlIAFIMZXJyb3JNZXNzYWdliA'
    'EBEh0KCmVycm9yX2NvZGUYDCABKAVSCWVycm9yQ29kZUIQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use tTSSpeakResultDescriptor instead')
const TTSSpeakResult$json = {
  '1': 'TTSSpeakResult',
  '2': [
    {'1': 'audio_format', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    {'1': 'sample_rate', '3': 2, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'duration_ms', '3': 3, '4': 1, '5': 3, '10': 'durationMs'},
    {'1': 'audio_size_bytes', '3': 4, '4': 1, '5': 3, '10': 'audioSizeBytes'},
    {'1': 'metadata', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.TTSSynthesisMetadata', '10': 'metadata'},
    {'1': 'timestamp_ms', '3': 6, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'error_message', '3': 7, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 8, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_error_message'},
  ],
};

/// Descriptor for `TTSSpeakResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSSpeakResultDescriptor = $convert.base64Decode(
    'Cg5UVFNTcGVha1Jlc3VsdBI+CgxhdWRpb19mb3JtYXQYASABKA4yGy5ydW5hbnl3aGVyZS52MS'
    '5BdWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQSHwoLc2FtcGxlX3JhdGUYAiABKAVSCnNhbXBsZVJh'
    'dGUSHwoLZHVyYXRpb25fbXMYAyABKANSCmR1cmF0aW9uTXMSKAoQYXVkaW9fc2l6ZV9ieXRlcx'
    'gEIAEoA1IOYXVkaW9TaXplQnl0ZXMSQAoIbWV0YWRhdGEYBSABKAsyJC5ydW5hbnl3aGVyZS52'
    'MS5UVFNTeW50aGVzaXNNZXRhZGF0YVIIbWV0YWRhdGESIQoMdGltZXN0YW1wX21zGAYgASgDUg'
    't0aW1lc3RhbXBNcxIoCg1lcnJvcl9tZXNzYWdlGAcgASgJSABSDGVycm9yTWVzc2FnZYgBARId'
    'CgplcnJvcl9jb2RlGAggASgFUgllcnJvckNvZGVCEAoOX2Vycm9yX21lc3NhZ2U=');

@$core.Deprecated('Use tTSVoiceInfoDescriptor instead')
const TTSVoiceInfo$json = {
  '1': 'TTSVoiceInfo',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'language_code', '3': 3, '4': 1, '5': 9, '10': 'languageCode'},
    {'1': 'gender', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.TTSVoiceGender', '10': 'gender'},
    {'1': 'description', '3': 5, '4': 1, '5': 9, '10': 'description'},
    {'1': 'is_neural', '3': 6, '4': 1, '5': 8, '10': 'isNeural'},
    {'1': 'is_system', '3': 7, '4': 1, '5': 8, '10': 'isSystem'},
    {'1': 'sample_rate', '3': 8, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'supported_styles', '3': 9, '4': 3, '5': 9, '10': 'supportedStyles'},
  ],
};

/// Descriptor for `TTSVoiceInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSVoiceInfoDescriptor = $convert.base64Decode(
    'CgxUVFNWb2ljZUluZm8SDgoCaWQYASABKAlSAmlkEiEKDGRpc3BsYXlfbmFtZRgCIAEoCVILZG'
    'lzcGxheU5hbWUSIwoNbGFuZ3VhZ2VfY29kZRgDIAEoCVIMbGFuZ3VhZ2VDb2RlEjYKBmdlbmRl'
    'chgEIAEoDjIeLnJ1bmFueXdoZXJlLnYxLlRUU1ZvaWNlR2VuZGVyUgZnZW5kZXISIAoLZGVzY3'
    'JpcHRpb24YBSABKAlSC2Rlc2NyaXB0aW9uEhsKCWlzX25ldXJhbBgGIAEoCFIIaXNOZXVyYWwS'
    'GwoJaXNfc3lzdGVtGAcgASgIUghpc1N5c3RlbRIfCgtzYW1wbGVfcmF0ZRgIIAEoBVIKc2FtcG'
    'xlUmF0ZRIpChBzdXBwb3J0ZWRfc3R5bGVzGAkgAygJUg9zdXBwb3J0ZWRTdHlsZXM=');

@$core.Deprecated('Use tTSStreamEventDescriptor instead')
const TTSStreamEvent$json = {
  '1': 'TTSStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'kind', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.TTSStreamEventKind', '10': 'kind'},
    {'1': 'output', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.TTSOutput', '9': 0, '10': 'output', '17': true},
    {'1': 'phoneme', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.TTSPhonemeTimestamp', '9': 1, '10': 'phoneme', '17': true},
    {'1': 'speak_result', '3': 7, '4': 1, '5': 11, '6': '.runanywhere.v1.TTSSpeakResult', '9': 2, '10': 'speakResult', '17': true},
    {'1': 'error_message', '3': 8, '4': 1, '5': 9, '9': 3, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 9, '4': 1, '5': 5, '10': 'errorCode'},
    {'1': 'progress', '3': 10, '4': 1, '5': 2, '10': 'progress'},
    {'1': 'chunk_index', '3': 11, '4': 1, '5': 5, '10': 'chunkIndex'},
    {'1': 'total_chunks', '3': 12, '4': 1, '5': 5, '10': 'totalChunks'},
    {'1': 'elapsed_ms', '3': 13, '4': 1, '5': 3, '10': 'elapsedMs'},
    {'1': 'status_message', '3': 14, '4': 1, '5': 9, '10': 'statusMessage'},
  ],
  '8': [
    {'1': '_output'},
    {'1': '_phoneme'},
    {'1': '_speak_result'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `TTSStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSStreamEventDescriptor = $convert.base64Decode(
    'Cg5UVFNTdHJlYW1FdmVudBIQCgNzZXEYASABKARSA3NlcRIhCgx0aW1lc3RhbXBfdXMYAiABKA'
    'NSC3RpbWVzdGFtcFVzEh0KCnJlcXVlc3RfaWQYAyABKAlSCXJlcXVlc3RJZBI2CgRraW5kGAQg'
    'ASgOMiIucnVuYW55d2hlcmUudjEuVFRTU3RyZWFtRXZlbnRLaW5kUgRraW5kEjYKBm91dHB1dB'
    'gFIAEoCzIZLnJ1bmFueXdoZXJlLnYxLlRUU091dHB1dEgAUgZvdXRwdXSIAQESQgoHcGhvbmVt'
    'ZRgGIAEoCzIjLnJ1bmFueXdoZXJlLnYxLlRUU1Bob25lbWVUaW1lc3RhbXBIAVIHcGhvbmVtZY'
    'gBARJGCgxzcGVha19yZXN1bHQYByABKAsyHi5ydW5hbnl3aGVyZS52MS5UVFNTcGVha1Jlc3Vs'
    'dEgCUgtzcGVha1Jlc3VsdIgBARIoCg1lcnJvcl9tZXNzYWdlGAggASgJSANSDGVycm9yTWVzc2'
    'FnZYgBARIdCgplcnJvcl9jb2RlGAkgASgFUgllcnJvckNvZGUSGgoIcHJvZ3Jlc3MYCiABKAJS'
    'CHByb2dyZXNzEh8KC2NodW5rX2luZGV4GAsgASgFUgpjaHVua0luZGV4EiEKDHRvdGFsX2NodW'
    '5rcxgMIAEoBVILdG90YWxDaHVua3MSHQoKZWxhcHNlZF9tcxgNIAEoA1IJZWxhcHNlZE1zEiUK'
    'DnN0YXR1c19tZXNzYWdlGA4gASgJUg1zdGF0dXNNZXNzYWdlQgkKB19vdXRwdXRCCgoIX3Bob2'
    '5lbWVCDwoNX3NwZWFrX3Jlc3VsdEIQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use tTSServiceStateDescriptor instead')
const TTSServiceState$json = {
  '1': 'TTSServiceState',
  '2': [
    {'1': 'is_ready', '3': 1, '4': 1, '5': 8, '10': 'isReady'},
    {'1': 'current_voice', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'currentVoice', '17': true},
    {'1': 'voices', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.TTSVoiceInfo', '10': 'voices'},
    {'1': 'supported_language_codes', '3': 4, '4': 3, '5': 9, '10': 'supportedLanguageCodes'},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 6, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_current_voice'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `TTSServiceState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSServiceStateDescriptor = $convert.base64Decode(
    'Cg9UVFNTZXJ2aWNlU3RhdGUSGQoIaXNfcmVhZHkYASABKAhSB2lzUmVhZHkSKAoNY3VycmVudF'
    '92b2ljZRgCIAEoCUgAUgxjdXJyZW50Vm9pY2WIAQESNAoGdm9pY2VzGAMgAygLMhwucnVuYW55'
    'd2hlcmUudjEuVFRTVm9pY2VJbmZvUgZ2b2ljZXMSOAoYc3VwcG9ydGVkX2xhbmd1YWdlX2NvZG'
    'VzGAQgAygJUhZzdXBwb3J0ZWRMYW5ndWFnZUNvZGVzEigKDWVycm9yX21lc3NhZ2UYBSABKAlI'
    'AVIMZXJyb3JNZXNzYWdliAEBEh0KCmVycm9yX2NvZGUYBiABKAVSCWVycm9yQ29kZUIQCg5fY3'
    'VycmVudF92b2ljZUIQCg5fZXJyb3JfbWVzc2FnZQ==');

const $core.Map<$core.String, $core.dynamic> TTSServiceBase$json = {
  '1': 'TTS',
  '2': [
    {'1': 'Synthesize', '2': '.runanywhere.v1.TTSSynthesisRequest', '3': '.runanywhere.v1.TTSOutput'},
    {'1': 'Stream', '2': '.runanywhere.v1.TTSSynthesisRequest', '3': '.runanywhere.v1.TTSStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use tTSServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> TTSServiceBase$messageJson = {
  '.runanywhere.v1.TTSSynthesisRequest': TTSSynthesisRequest$json,
  '.runanywhere.v1.TTSOptions': TTSOptions$json,
  '.runanywhere.v1.TTSSynthesisRequest.MetadataEntry': TTSSynthesisRequest_MetadataEntry$json,
  '.runanywhere.v1.TTSOutput': TTSOutput$json,
  '.runanywhere.v1.TTSPhonemeTimestamp': TTSPhonemeTimestamp$json,
  '.runanywhere.v1.TTSSynthesisMetadata': TTSSynthesisMetadata$json,
  '.runanywhere.v1.TTSStreamEvent': TTSStreamEvent$json,
  '.runanywhere.v1.TTSSpeakResult': TTSSpeakResult$json,
};

/// Descriptor for `TTS`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List tTSServiceDescriptor = $convert.base64Decode(
    'CgNUVFMSTAoKU3ludGhlc2l6ZRIjLnJ1bmFueXdoZXJlLnYxLlRUU1N5bnRoZXNpc1JlcXVlc3'
    'QaGS5ydW5hbnl3aGVyZS52MS5UVFNPdXRwdXQSTwoGU3RyZWFtEiMucnVuYW55d2hlcmUudjEu'
    'VFRTU3ludGhlc2lzUmVxdWVzdBoeLnJ1bmFueXdoZXJlLnYxLlRUU1N0cmVhbUV2ZW50MAE=');

