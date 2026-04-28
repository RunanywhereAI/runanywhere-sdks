///
//  Generated code. Do not modify.
//  source: tts_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use tTSVoiceGenderDescriptor instead')
const TTSVoiceGender$json = const {
  '1': 'TTSVoiceGender',
  '2': const [
    const {'1': 'TTS_VOICE_GENDER_UNSPECIFIED', '2': 0},
    const {'1': 'TTS_VOICE_GENDER_MALE', '2': 1},
    const {'1': 'TTS_VOICE_GENDER_FEMALE', '2': 2},
    const {'1': 'TTS_VOICE_GENDER_NEUTRAL', '2': 3},
  ],
};

/// Descriptor for `TTSVoiceGender`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List tTSVoiceGenderDescriptor = $convert.base64Decode('Cg5UVFNWb2ljZUdlbmRlchIgChxUVFNfVk9JQ0VfR0VOREVSX1VOU1BFQ0lGSUVEEAASGQoVVFRTX1ZPSUNFX0dFTkRFUl9NQUxFEAESGwoXVFRTX1ZPSUNFX0dFTkRFUl9GRU1BTEUQAhIcChhUVFNfVk9JQ0VfR0VOREVSX05FVVRSQUwQAw==');
@$core.Deprecated('Use tTSConfigurationDescriptor instead')
const TTSConfiguration$json = const {
  '1': 'TTSConfiguration',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'voice', '3': 2, '4': 1, '5': 9, '10': 'voice'},
    const {'1': 'language_code', '3': 3, '4': 1, '5': 9, '10': 'languageCode'},
    const {'1': 'speaking_rate', '3': 4, '4': 1, '5': 2, '10': 'speakingRate'},
    const {'1': 'pitch', '3': 5, '4': 1, '5': 2, '10': 'pitch'},
    const {'1': 'volume', '3': 6, '4': 1, '5': 2, '10': 'volume'},
    const {'1': 'audio_format', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    const {'1': 'sample_rate', '3': 8, '4': 1, '5': 5, '10': 'sampleRate'},
    const {'1': 'enable_neural_voice', '3': 9, '4': 1, '5': 8, '10': 'enableNeuralVoice'},
    const {'1': 'enable_ssml', '3': 10, '4': 1, '5': 8, '10': 'enableSsml'},
  ],
};

/// Descriptor for `TTSConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSConfigurationDescriptor = $convert.base64Decode('ChBUVFNDb25maWd1cmF0aW9uEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEhQKBXZvaWNlGAIgASgJUgV2b2ljZRIjCg1sYW5ndWFnZV9jb2RlGAMgASgJUgxsYW5ndWFnZUNvZGUSIwoNc3BlYWtpbmdfcmF0ZRgEIAEoAlIMc3BlYWtpbmdSYXRlEhQKBXBpdGNoGAUgASgCUgVwaXRjaBIWCgZ2b2x1bWUYBiABKAJSBnZvbHVtZRI+CgxhdWRpb19mb3JtYXQYByABKA4yGy5ydW5hbnl3aGVyZS52MS5BdWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQSHwoLc2FtcGxlX3JhdGUYCCABKAVSCnNhbXBsZVJhdGUSLgoTZW5hYmxlX25ldXJhbF92b2ljZRgJIAEoCFIRZW5hYmxlTmV1cmFsVm9pY2USHwoLZW5hYmxlX3NzbWwYCiABKAhSCmVuYWJsZVNzbWw=');
@$core.Deprecated('Use tTSOptionsDescriptor instead')
const TTSOptions$json = const {
  '1': 'TTSOptions',
  '2': const [
    const {'1': 'voice', '3': 1, '4': 1, '5': 9, '10': 'voice'},
    const {'1': 'language_code', '3': 2, '4': 1, '5': 9, '10': 'languageCode'},
    const {'1': 'speaking_rate', '3': 3, '4': 1, '5': 2, '10': 'speakingRate'},
    const {'1': 'pitch', '3': 4, '4': 1, '5': 2, '10': 'pitch'},
    const {'1': 'volume', '3': 5, '4': 1, '5': 2, '10': 'volume'},
    const {'1': 'enable_ssml', '3': 6, '4': 1, '5': 8, '10': 'enableSsml'},
    const {'1': 'audio_format', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
  ],
};

/// Descriptor for `TTSOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSOptionsDescriptor = $convert.base64Decode('CgpUVFNPcHRpb25zEhQKBXZvaWNlGAEgASgJUgV2b2ljZRIjCg1sYW5ndWFnZV9jb2RlGAIgASgJUgxsYW5ndWFnZUNvZGUSIwoNc3BlYWtpbmdfcmF0ZRgDIAEoAlIMc3BlYWtpbmdSYXRlEhQKBXBpdGNoGAQgASgCUgVwaXRjaBIWCgZ2b2x1bWUYBSABKAJSBnZvbHVtZRIfCgtlbmFibGVfc3NtbBgGIAEoCFIKZW5hYmxlU3NtbBI+CgxhdWRpb19mb3JtYXQYByABKA4yGy5ydW5hbnl3aGVyZS52MS5BdWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQ=');
@$core.Deprecated('Use tTSPhonemeTimestampDescriptor instead')
const TTSPhonemeTimestamp$json = const {
  '1': 'TTSPhonemeTimestamp',
  '2': const [
    const {'1': 'phoneme', '3': 1, '4': 1, '5': 9, '10': 'phoneme'},
    const {'1': 'start_ms', '3': 2, '4': 1, '5': 3, '10': 'startMs'},
    const {'1': 'end_ms', '3': 3, '4': 1, '5': 3, '10': 'endMs'},
  ],
};

/// Descriptor for `TTSPhonemeTimestamp`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSPhonemeTimestampDescriptor = $convert.base64Decode('ChNUVFNQaG9uZW1lVGltZXN0YW1wEhgKB3Bob25lbWUYASABKAlSB3Bob25lbWUSGQoIc3RhcnRfbXMYAiABKANSB3N0YXJ0TXMSFQoGZW5kX21zGAMgASgDUgVlbmRNcw==');
@$core.Deprecated('Use tTSSynthesisMetadataDescriptor instead')
const TTSSynthesisMetadata$json = const {
  '1': 'TTSSynthesisMetadata',
  '2': const [
    const {'1': 'voice_id', '3': 1, '4': 1, '5': 9, '10': 'voiceId'},
    const {'1': 'language_code', '3': 2, '4': 1, '5': 9, '10': 'languageCode'},
    const {'1': 'processing_time_ms', '3': 3, '4': 1, '5': 3, '10': 'processingTimeMs'},
    const {'1': 'character_count', '3': 4, '4': 1, '5': 5, '10': 'characterCount'},
    const {'1': 'audio_duration_ms', '3': 5, '4': 1, '5': 3, '10': 'audioDurationMs'},
  ],
};

/// Descriptor for `TTSSynthesisMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSSynthesisMetadataDescriptor = $convert.base64Decode('ChRUVFNTeW50aGVzaXNNZXRhZGF0YRIZCgh2b2ljZV9pZBgBIAEoCVIHdm9pY2VJZBIjCg1sYW5ndWFnZV9jb2RlGAIgASgJUgxsYW5ndWFnZUNvZGUSLAoScHJvY2Vzc2luZ190aW1lX21zGAMgASgDUhBwcm9jZXNzaW5nVGltZU1zEicKD2NoYXJhY3Rlcl9jb3VudBgEIAEoBVIOY2hhcmFjdGVyQ291bnQSKgoRYXVkaW9fZHVyYXRpb25fbXMYBSABKANSD2F1ZGlvRHVyYXRpb25Ncw==');
@$core.Deprecated('Use tTSOutputDescriptor instead')
const TTSOutput$json = const {
  '1': 'TTSOutput',
  '2': const [
    const {'1': 'audio_data', '3': 1, '4': 1, '5': 12, '10': 'audioData'},
    const {'1': 'audio_format', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    const {'1': 'sample_rate', '3': 3, '4': 1, '5': 5, '10': 'sampleRate'},
    const {'1': 'duration_ms', '3': 4, '4': 1, '5': 3, '10': 'durationMs'},
    const {'1': 'phoneme_timestamps', '3': 5, '4': 3, '5': 11, '6': '.runanywhere.v1.TTSPhonemeTimestamp', '10': 'phonemeTimestamps'},
    const {'1': 'metadata', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.TTSSynthesisMetadata', '10': 'metadata'},
    const {'1': 'timestamp_ms', '3': 7, '4': 1, '5': 3, '10': 'timestampMs'},
  ],
};

/// Descriptor for `TTSOutput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSOutputDescriptor = $convert.base64Decode('CglUVFNPdXRwdXQSHQoKYXVkaW9fZGF0YRgBIAEoDFIJYXVkaW9EYXRhEj4KDGF1ZGlvX2Zvcm1hdBgCIAEoDjIbLnJ1bmFueXdoZXJlLnYxLkF1ZGlvRm9ybWF0UgthdWRpb0Zvcm1hdBIfCgtzYW1wbGVfcmF0ZRgDIAEoBVIKc2FtcGxlUmF0ZRIfCgtkdXJhdGlvbl9tcxgEIAEoA1IKZHVyYXRpb25NcxJSChJwaG9uZW1lX3RpbWVzdGFtcHMYBSADKAsyIy5ydW5hbnl3aGVyZS52MS5UVFNQaG9uZW1lVGltZXN0YW1wUhFwaG9uZW1lVGltZXN0YW1wcxJACghtZXRhZGF0YRgGIAEoCzIkLnJ1bmFueXdoZXJlLnYxLlRUU1N5bnRoZXNpc01ldGFkYXRhUghtZXRhZGF0YRIhCgx0aW1lc3RhbXBfbXMYByABKANSC3RpbWVzdGFtcE1z');
@$core.Deprecated('Use tTSSpeakResultDescriptor instead')
const TTSSpeakResult$json = const {
  '1': 'TTSSpeakResult',
  '2': const [
    const {'1': 'audio_format', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioFormat', '10': 'audioFormat'},
    const {'1': 'sample_rate', '3': 2, '4': 1, '5': 5, '10': 'sampleRate'},
    const {'1': 'duration_ms', '3': 3, '4': 1, '5': 3, '10': 'durationMs'},
    const {'1': 'audio_size_bytes', '3': 4, '4': 1, '5': 3, '10': 'audioSizeBytes'},
    const {'1': 'metadata', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.TTSSynthesisMetadata', '10': 'metadata'},
    const {'1': 'timestamp_ms', '3': 6, '4': 1, '5': 3, '10': 'timestampMs'},
  ],
};

/// Descriptor for `TTSSpeakResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSSpeakResultDescriptor = $convert.base64Decode('Cg5UVFNTcGVha1Jlc3VsdBI+CgxhdWRpb19mb3JtYXQYASABKA4yGy5ydW5hbnl3aGVyZS52MS5BdWRpb0Zvcm1hdFILYXVkaW9Gb3JtYXQSHwoLc2FtcGxlX3JhdGUYAiABKAVSCnNhbXBsZVJhdGUSHwoLZHVyYXRpb25fbXMYAyABKANSCmR1cmF0aW9uTXMSKAoQYXVkaW9fc2l6ZV9ieXRlcxgEIAEoA1IOYXVkaW9TaXplQnl0ZXMSQAoIbWV0YWRhdGEYBSABKAsyJC5ydW5hbnl3aGVyZS52MS5UVFNTeW50aGVzaXNNZXRhZGF0YVIIbWV0YWRhdGESIQoMdGltZXN0YW1wX21zGAYgASgDUgt0aW1lc3RhbXBNcw==');
@$core.Deprecated('Use tTSVoiceInfoDescriptor instead')
const TTSVoiceInfo$json = const {
  '1': 'TTSVoiceInfo',
  '2': const [
    const {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    const {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    const {'1': 'language_code', '3': 3, '4': 1, '5': 9, '10': 'languageCode'},
    const {'1': 'gender', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.TTSVoiceGender', '10': 'gender'},
    const {'1': 'description', '3': 5, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `TTSVoiceInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tTSVoiceInfoDescriptor = $convert.base64Decode('CgxUVFNWb2ljZUluZm8SDgoCaWQYASABKAlSAmlkEiEKDGRpc3BsYXlfbmFtZRgCIAEoCVILZGlzcGxheU5hbWUSIwoNbGFuZ3VhZ2VfY29kZRgDIAEoCVIMbGFuZ3VhZ2VDb2RlEjYKBmdlbmRlchgEIAEoDjIeLnJ1bmFueXdoZXJlLnYxLlRUU1ZvaWNlR2VuZGVyUgZnZW5kZXISIAoLZGVzY3JpcHRpb24YBSABKAlSC2Rlc2NyaXB0aW9u');
