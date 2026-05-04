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
  ],
};

/// Descriptor for `TTSOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSOptionsDescriptor = $convert.base64Decode(
    'CgpUVFNPcHRpb25zEhQKBXZvaWNlGAEgASgJUgV2b2ljZRIjCg1sYW5ndWFnZV9jb2RlGAIgAS'
    'gJUgxsYW5ndWFnZUNvZGUSIwoNc3BlYWtpbmdfcmF0ZRgDIAEoAlIMc3BlYWtpbmdSYXRlEhQK'
    'BXBpdGNoGAQgASgCUgVwaXRjaBIWCgZ2b2x1bWUYBSABKAJSBnZvbHVtZRIfCgtlbmFibGVfc3'
    'NtbBgGIAEoCFIKZW5hYmxlU3NtbBI+CgxhdWRpb19mb3JtYXQYByABKA4yGy5ydW5hbnl3aGVy'
    'ZS52MS5BdWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQSHwoLc2FtcGxlX3JhdGUYCCABKAVSCnNhbX'
    'BsZVJhdGU=');

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
    'bXBfbXMYByABKANSC3RpbWVzdGFtcE1z');

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
  ],
};

/// Descriptor for `TTSSpeakResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSSpeakResultDescriptor = $convert.base64Decode(
    'Cg5UVFNTcGVha1Jlc3VsdBI+CgxhdWRpb19mb3JtYXQYASABKA4yGy5ydW5hbnl3aGVyZS52MS'
    '5BdWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQSHwoLc2FtcGxlX3JhdGUYAiABKAVSCnNhbXBsZVJh'
    'dGUSHwoLZHVyYXRpb25fbXMYAyABKANSCmR1cmF0aW9uTXMSKAoQYXVkaW9fc2l6ZV9ieXRlcx'
    'gEIAEoA1IOYXVkaW9TaXplQnl0ZXMSQAoIbWV0YWRhdGEYBSABKAsyJC5ydW5hbnl3aGVyZS52'
    'MS5UVFNTeW50aGVzaXNNZXRhZGF0YVIIbWV0YWRhdGESIQoMdGltZXN0YW1wX21zGAYgASgDUg'
    't0aW1lc3RhbXBNcw==');

@$core.Deprecated('Use tTSVoiceInfoDescriptor instead')
const TTSVoiceInfo$json = {
  '1': 'TTSVoiceInfo',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'language_code', '3': 3, '4': 1, '5': 9, '10': 'languageCode'},
    {'1': 'gender', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.TTSVoiceGender', '10': 'gender'},
    {'1': 'description', '3': 5, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `TTSVoiceInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSVoiceInfoDescriptor = $convert.base64Decode(
    'CgxUVFNWb2ljZUluZm8SDgoCaWQYASABKAlSAmlkEiEKDGRpc3BsYXlfbmFtZRgCIAEoCVILZG'
    'lzcGxheU5hbWUSIwoNbGFuZ3VhZ2VfY29kZRgDIAEoCVIMbGFuZ3VhZ2VDb2RlEjYKBmdlbmRl'
    'chgEIAEoDjIeLnJ1bmFueXdoZXJlLnYxLlRUU1ZvaWNlR2VuZGVyUgZnZW5kZXISIAoLZGVzY3'
    'JpcHRpb24YBSABKAlSC2Rlc2NyaXB0aW9u');

