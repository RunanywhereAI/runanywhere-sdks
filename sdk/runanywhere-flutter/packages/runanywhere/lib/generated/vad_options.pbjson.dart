//
//  Generated code. Do not modify.
//  source: vad_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use speechActivityKindDescriptor instead')
const SpeechActivityKind$json = {
  '1': 'SpeechActivityKind',
  '2': [
    {'1': 'SPEECH_ACTIVITY_KIND_UNSPECIFIED', '2': 0},
    {'1': 'SPEECH_ACTIVITY_KIND_SPEECH_STARTED', '2': 1},
    {'1': 'SPEECH_ACTIVITY_KIND_SPEECH_ENDED', '2': 2},
    {'1': 'SPEECH_ACTIVITY_KIND_ONGOING', '2': 3},
  ],
};

/// Descriptor for `SpeechActivityKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List speechActivityKindDescriptor = $convert.base64Decode(
    'ChJTcGVlY2hBY3Rpdml0eUtpbmQSJAogU1BFRUNIX0FDVElWSVRZX0tJTkRfVU5TUEVDSUZJRU'
    'QQABInCiNTUEVFQ0hfQUNUSVZJVFlfS0lORF9TUEVFQ0hfU1RBUlRFRBABEiUKIVNQRUVDSF9B'
    'Q1RJVklUWV9LSU5EX1NQRUVDSF9FTkRFRBACEiAKHFNQRUVDSF9BQ1RJVklUWV9LSU5EX09OR0'
    '9JTkcQAw==');

@$core.Deprecated('Use vADAudioEncodingDescriptor instead')
const VADAudioEncoding$json = {
  '1': 'VADAudioEncoding',
  '2': [
    {'1': 'VAD_AUDIO_ENCODING_UNSPECIFIED', '2': 0},
    {'1': 'VAD_AUDIO_ENCODING_PCM_F32_LE', '2': 1},
    {'1': 'VAD_AUDIO_ENCODING_PCM_S16_LE', '2': 2},
  ],
};

/// Descriptor for `VADAudioEncoding`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vADAudioEncodingDescriptor = $convert.base64Decode(
    'ChBWQURBdWRpb0VuY29kaW5nEiIKHlZBRF9BVURJT19FTkNPRElOR19VTlNQRUNJRklFRBAAEi'
    'EKHVZBRF9BVURJT19FTkNPRElOR19QQ01fRjMyX0xFEAESIQodVkFEX0FVRElPX0VOQ09ESU5H'
    'X1BDTV9TMTZfTEUQAg==');

@$core.Deprecated('Use vADStreamEventKindDescriptor instead')
const VADStreamEventKind$json = {
  '1': 'VADStreamEventKind',
  '2': [
    {'1': 'VAD_STREAM_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'VAD_STREAM_EVENT_KIND_STARTED', '2': 1},
    {'1': 'VAD_STREAM_EVENT_KIND_FRAME', '2': 2},
    {'1': 'VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY', '2': 3},
    {'1': 'VAD_STREAM_EVENT_KIND_STATISTICS', '2': 4},
    {'1': 'VAD_STREAM_EVENT_KIND_STOPPED', '2': 5},
    {'1': 'VAD_STREAM_EVENT_KIND_ERROR', '2': 6},
    {'1': 'VAD_STREAM_EVENT_KIND_BARGE_IN', '2': 7},
  ],
};

/// Descriptor for `VADStreamEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vADStreamEventKindDescriptor = $convert.base64Decode(
    'ChJWQURTdHJlYW1FdmVudEtpbmQSJQohVkFEX1NUUkVBTV9FVkVOVF9LSU5EX1VOU1BFQ0lGSU'
    'VEEAASIQodVkFEX1NUUkVBTV9FVkVOVF9LSU5EX1NUQVJURUQQARIfChtWQURfU1RSRUFNX0VW'
    'RU5UX0tJTkRfRlJBTUUQAhIpCiVWQURfU1RSRUFNX0VWRU5UX0tJTkRfU1BFRUNIX0FDVElWSV'
    'RZEAMSJAogVkFEX1NUUkVBTV9FVkVOVF9LSU5EX1NUQVRJU1RJQ1MQBBIhCh1WQURfU1RSRUFN'
    'X0VWRU5UX0tJTkRfU1RPUFBFRBAFEh8KG1ZBRF9TVFJFQU1fRVZFTlRfS0lORF9FUlJPUhAGEi'
    'IKHlZBRF9TVFJFQU1fRVZFTlRfS0lORF9CQVJHRV9JThAH');

@$core.Deprecated('Use vADConfigurationDescriptor instead')
const VADConfiguration$json = {
  '1': 'VADConfiguration',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'sample_rate', '3': 2, '4': 1, '5': 5, '8': {}, '10': 'sampleRate'},
    {'1': 'frame_length_ms', '3': 3, '4': 1, '5': 5, '8': {}, '10': 'frameLengthMs'},
    {'1': 'threshold', '3': 4, '4': 1, '5': 2, '8': {}, '10': 'threshold'},
    {'1': 'enable_auto_calibration', '3': 5, '4': 1, '5': 8, '10': 'enableAutoCalibration'},
    {'1': 'calibration_multiplier', '3': 6, '4': 1, '5': 2, '10': 'calibrationMultiplier'},
    {'1': 'preferred_framework', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.InferenceFramework', '9': 0, '10': 'preferredFramework', '17': true},
    {'1': 'model_path', '3': 8, '4': 1, '5': 9, '9': 1, '10': 'modelPath', '17': true},
    {'1': 'window_size_samples', '3': 9, '4': 1, '5': 5, '10': 'windowSizeSamples'},
    {'1': 'max_speech_duration_ms', '3': 10, '4': 1, '5': 5, '10': 'maxSpeechDurationMs'},
  ],
  '8': [
    {'1': '_preferred_framework'},
    {'1': '_model_path'},
  ],
};

/// Descriptor for `VADConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADConfigurationDescriptor = $convert.base64Decode(
    'ChBWQURDb25maWd1cmF0aW9uEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEjQKC3NhbXBsZV'
    '9yYXRlGAIgASgFQhOKtRgFMTYwMDCgtRgBqLUYgPcCUgpzYW1wbGVSYXRlEjgKD2ZyYW1lX2xl'
    'bmd0aF9tcxgDIAEoBUIQirUYAzEwMKC1GAGotRjoB1INZnJhbWVMZW5ndGhNcxI9Cgl0aHJlc2'
    'hvbGQYBCABKAJCH4q1GAUwLjAxNbG1GAAAAAAAAAAAubUYAAAAAAAA8D9SCXRocmVzaG9sZBI2'
    'ChdlbmFibGVfYXV0b19jYWxpYnJhdGlvbhgFIAEoCFIVZW5hYmxlQXV0b0NhbGlicmF0aW9uEj'
    'UKFmNhbGlicmF0aW9uX211bHRpcGxpZXIYBiABKAJSFWNhbGlicmF0aW9uTXVsdGlwbGllchJY'
    'ChNwcmVmZXJyZWRfZnJhbWV3b3JrGAcgASgOMiIucnVuYW55d2hlcmUudjEuSW5mZXJlbmNlRn'
    'JhbWV3b3JrSABSEnByZWZlcnJlZEZyYW1ld29ya4gBARIiCgptb2RlbF9wYXRoGAggASgJSAFS'
    'CW1vZGVsUGF0aIgBARIuChN3aW5kb3dfc2l6ZV9zYW1wbGVzGAkgASgFUhF3aW5kb3dTaXplU2'
    'FtcGxlcxIzChZtYXhfc3BlZWNoX2R1cmF0aW9uX21zGAogASgFUhNtYXhTcGVlY2hEdXJhdGlv'
    'bk1zQhYKFF9wcmVmZXJyZWRfZnJhbWV3b3JrQg0KC19tb2RlbF9wYXRo');

@$core.Deprecated('Use vADOptionsDescriptor instead')
const VADOptions$json = {
  '1': 'VADOptions',
  '2': [
    {'1': 'threshold', '3': 1, '4': 1, '5': 2, '10': 'threshold'},
    {'1': 'min_speech_duration_ms', '3': 2, '4': 1, '5': 5, '10': 'minSpeechDurationMs'},
    {'1': 'min_silence_duration_ms', '3': 3, '4': 1, '5': 5, '10': 'minSilenceDurationMs'},
    {'1': 'max_speech_duration_ms', '3': 4, '4': 1, '5': 5, '10': 'maxSpeechDurationMs'},
    {'1': 'include_statistics', '3': 5, '4': 1, '5': 8, '10': 'includeStatistics'},
  ],
};

/// Descriptor for `VADOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADOptionsDescriptor = $convert.base64Decode(
    'CgpWQURPcHRpb25zEhwKCXRocmVzaG9sZBgBIAEoAlIJdGhyZXNob2xkEjMKFm1pbl9zcGVlY2'
    'hfZHVyYXRpb25fbXMYAiABKAVSE21pblNwZWVjaER1cmF0aW9uTXMSNQoXbWluX3NpbGVuY2Vf'
    'ZHVyYXRpb25fbXMYAyABKAVSFG1pblNpbGVuY2VEdXJhdGlvbk1zEjMKFm1heF9zcGVlY2hfZH'
    'VyYXRpb25fbXMYBCABKAVSE21heFNwZWVjaER1cmF0aW9uTXMSLQoSaW5jbHVkZV9zdGF0aXN0'
    'aWNzGAUgASgIUhFpbmNsdWRlU3RhdGlzdGljcw==');

@$core.Deprecated('Use vADAudioSourceDescriptor instead')
const VADAudioSource$json = {
  '1': 'VADAudioSource',
  '2': [
    {'1': 'audio_data', '3': 1, '4': 1, '5': 12, '9': 0, '10': 'audioData'},
    {'1': 'adapter_handle', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'adapterHandle'},
    {'1': 'encoding', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.VADAudioEncoding', '10': 'encoding'},
    {'1': 'sample_rate', '3': 4, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'channels', '3': 5, '4': 1, '5': 5, '10': 'channels'},
    {'1': 'frame_offset_ms', '3': 6, '4': 1, '5': 3, '10': 'frameOffsetMs'},
  ],
  '8': [
    {'1': 'source'},
  ],
};

/// Descriptor for `VADAudioSource`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADAudioSourceDescriptor = $convert.base64Decode(
    'Cg5WQURBdWRpb1NvdXJjZRIfCgphdWRpb19kYXRhGAEgASgMSABSCWF1ZGlvRGF0YRInCg5hZG'
    'FwdGVyX2hhbmRsZRgCIAEoCUgAUg1hZGFwdGVySGFuZGxlEjwKCGVuY29kaW5nGAMgASgOMiAu'
    'cnVuYW55d2hlcmUudjEuVkFEQXVkaW9FbmNvZGluZ1IIZW5jb2RpbmcSHwoLc2FtcGxlX3JhdG'
    'UYBCABKAVSCnNhbXBsZVJhdGUSGgoIY2hhbm5lbHMYBSABKAVSCGNoYW5uZWxzEiYKD2ZyYW1l'
    'X29mZnNldF9tcxgGIAEoA1INZnJhbWVPZmZzZXRNc0IICgZzb3VyY2U=');

@$core.Deprecated('Use vADProcessRequestDescriptor instead')
const VADProcessRequest$json = {
  '1': 'VADProcessRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'audio', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.VADAudioSource', '9': 0, '10': 'audio', '17': true},
    {'1': 'options', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.VADOptions', '9': 1, '10': 'options', '17': true},
    {'1': 'metadata', '3': 4, '4': 3, '5': 11, '6': '.runanywhere.v1.VADProcessRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [VADProcessRequest_MetadataEntry$json],
  '8': [
    {'1': '_audio'},
    {'1': '_options'},
  ],
};

@$core.Deprecated('Use vADProcessRequestDescriptor instead')
const VADProcessRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `VADProcessRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADProcessRequestDescriptor = $convert.base64Decode(
    'ChFWQURQcm9jZXNzUmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZXN0SWQSOQoFYX'
    'VkaW8YAiABKAsyHi5ydW5hbnl3aGVyZS52MS5WQURBdWRpb1NvdXJjZUgAUgVhdWRpb4gBARI5'
    'CgdvcHRpb25zGAMgASgLMhoucnVuYW55d2hlcmUudjEuVkFET3B0aW9uc0gBUgdvcHRpb25ziA'
    'EBEksKCG1ldGFkYXRhGAQgAygLMi8ucnVuYW55d2hlcmUudjEuVkFEUHJvY2Vzc1JlcXVlc3Qu'
    'TWV0YWRhdGFFbnRyeVIIbWV0YWRhdGEaOwoNTWV0YWRhdGFFbnRyeRIQCgNrZXkYASABKAlSA2'
    'tleRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWU6AjgBQggKBl9hdWRpb0IKCghfb3B0aW9ucw==');

@$core.Deprecated('Use vADResultDescriptor instead')
const VADResult$json = {
  '1': 'VADResult',
  '2': [
    {'1': 'is_speech', '3': 1, '4': 1, '5': 8, '10': 'isSpeech'},
    {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'energy', '3': 3, '4': 1, '5': 2, '10': 'energy'},
    {'1': 'duration_ms', '3': 4, '4': 1, '5': 5, '10': 'durationMs'},
    {'1': 'timestamp_ms', '3': 5, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'start_time_ms', '3': 6, '4': 1, '5': 3, '10': 'startTimeMs'},
    {'1': 'end_time_ms', '3': 7, '4': 1, '5': 3, '10': 'endTimeMs'},
    {'1': 'statistics', '3': 8, '4': 1, '5': 11, '6': '.runanywhere.v1.VADStatistics', '9': 0, '10': 'statistics', '17': true},
    {'1': 'error_message', '3': 9, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 10, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_statistics'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `VADResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADResultDescriptor = $convert.base64Decode(
    'CglWQURSZXN1bHQSGwoJaXNfc3BlZWNoGAEgASgIUghpc1NwZWVjaBIeCgpjb25maWRlbmNlGA'
    'IgASgCUgpjb25maWRlbmNlEhYKBmVuZXJneRgDIAEoAlIGZW5lcmd5Eh8KC2R1cmF0aW9uX21z'
    'GAQgASgFUgpkdXJhdGlvbk1zEiEKDHRpbWVzdGFtcF9tcxgFIAEoA1ILdGltZXN0YW1wTXMSIg'
    'oNc3RhcnRfdGltZV9tcxgGIAEoA1ILc3RhcnRUaW1lTXMSHgoLZW5kX3RpbWVfbXMYByABKANS'
    'CWVuZFRpbWVNcxJCCgpzdGF0aXN0aWNzGAggASgLMh0ucnVuYW55d2hlcmUudjEuVkFEU3RhdG'
    'lzdGljc0gAUgpzdGF0aXN0aWNziAEBEigKDWVycm9yX21lc3NhZ2UYCSABKAlIAVIMZXJyb3JN'
    'ZXNzYWdliAEBEh0KCmVycm9yX2NvZGUYCiABKAVSCWVycm9yQ29kZUINCgtfc3RhdGlzdGljc0'
    'IQCg5fZXJyb3JfbWVzc2FnZQ==');

@$core.Deprecated('Use vADStatisticsDescriptor instead')
const VADStatistics$json = {
  '1': 'VADStatistics',
  '2': [
    {'1': 'current_energy', '3': 1, '4': 1, '5': 2, '10': 'currentEnergy'},
    {'1': 'current_threshold', '3': 2, '4': 1, '5': 2, '10': 'currentThreshold'},
    {'1': 'ambient_level', '3': 3, '4': 1, '5': 2, '10': 'ambientLevel'},
    {'1': 'recent_avg', '3': 4, '4': 1, '5': 2, '10': 'recentAvg'},
    {'1': 'recent_max', '3': 5, '4': 1, '5': 2, '10': 'recentMax'},
    {'1': 'total_speech_segments', '3': 6, '4': 1, '5': 5, '10': 'totalSpeechSegments'},
    {'1': 'total_speech_duration_ms', '3': 7, '4': 1, '5': 3, '10': 'totalSpeechDurationMs'},
    {'1': 'average_energy', '3': 8, '4': 1, '5': 2, '10': 'averageEnergy'},
    {'1': 'peak_energy', '3': 9, '4': 1, '5': 2, '10': 'peakEnergy'},
  ],
};

/// Descriptor for `VADStatistics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADStatisticsDescriptor = $convert.base64Decode(
    'Cg1WQURTdGF0aXN0aWNzEiUKDmN1cnJlbnRfZW5lcmd5GAEgASgCUg1jdXJyZW50RW5lcmd5Ei'
    'sKEWN1cnJlbnRfdGhyZXNob2xkGAIgASgCUhBjdXJyZW50VGhyZXNob2xkEiMKDWFtYmllbnRf'
    'bGV2ZWwYAyABKAJSDGFtYmllbnRMZXZlbBIdCgpyZWNlbnRfYXZnGAQgASgCUglyZWNlbnRBdm'
    'cSHQoKcmVjZW50X21heBgFIAEoAlIJcmVjZW50TWF4EjIKFXRvdGFsX3NwZWVjaF9zZWdtZW50'
    'cxgGIAEoBVITdG90YWxTcGVlY2hTZWdtZW50cxI3Chh0b3RhbF9zcGVlY2hfZHVyYXRpb25fbX'
    'MYByABKANSFXRvdGFsU3BlZWNoRHVyYXRpb25NcxIlCg5hdmVyYWdlX2VuZXJneRgIIAEoAlIN'
    'YXZlcmFnZUVuZXJneRIfCgtwZWFrX2VuZXJneRgJIAEoAlIKcGVha0VuZXJneQ==');

@$core.Deprecated('Use speechActivityEventDescriptor instead')
const SpeechActivityEvent$json = {
  '1': 'SpeechActivityEvent',
  '2': [
    {'1': 'event_type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.SpeechActivityKind', '10': 'eventType'},
    {'1': 'timestamp_ms', '3': 2, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'duration_ms', '3': 3, '4': 1, '5': 5, '10': 'durationMs'},
    {'1': 'confidence', '3': 4, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'result', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.VADResult', '9': 0, '10': 'result', '17': true},
    {'1': 'segment_id', '3': 6, '4': 1, '5': 9, '9': 1, '10': 'segmentId', '17': true},
  ],
  '8': [
    {'1': '_result'},
    {'1': '_segment_id'},
  ],
};

/// Descriptor for `SpeechActivityEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List speechActivityEventDescriptor = $convert.base64Decode(
    'ChNTcGVlY2hBY3Rpdml0eUV2ZW50EkEKCmV2ZW50X3R5cGUYASABKA4yIi5ydW5hbnl3aGVyZS'
    '52MS5TcGVlY2hBY3Rpdml0eUtpbmRSCWV2ZW50VHlwZRIhCgx0aW1lc3RhbXBfbXMYAiABKANS'
    'C3RpbWVzdGFtcE1zEh8KC2R1cmF0aW9uX21zGAMgASgFUgpkdXJhdGlvbk1zEh4KCmNvbmZpZG'
    'VuY2UYBCABKAJSCmNvbmZpZGVuY2USNgoGcmVzdWx0GAUgASgLMhkucnVuYW55d2hlcmUudjEu'
    'VkFEUmVzdWx0SABSBnJlc3VsdIgBARIiCgpzZWdtZW50X2lkGAYgASgJSAFSCXNlZ21lbnRJZI'
    'gBAUIJCgdfcmVzdWx0Qg0KC19zZWdtZW50X2lk');

@$core.Deprecated('Use vADStreamEventDescriptor instead')
const VADStreamEvent$json = {
  '1': 'VADStreamEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'request_id', '3': 3, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'kind', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.VADStreamEventKind', '10': 'kind'},
    {'1': 'result', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.VADResult', '9': 0, '10': 'result', '17': true},
    {'1': 'activity', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.SpeechActivityEvent', '9': 1, '10': 'activity', '17': true},
    {'1': 'statistics', '3': 7, '4': 1, '5': 11, '6': '.runanywhere.v1.VADStatistics', '9': 2, '10': 'statistics', '17': true},
    {'1': 'error_message', '3': 8, '4': 1, '5': 9, '9': 3, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 9, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_result'},
    {'1': '_activity'},
    {'1': '_statistics'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `VADStreamEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADStreamEventDescriptor = $convert.base64Decode(
    'Cg5WQURTdHJlYW1FdmVudBIQCgNzZXEYASABKARSA3NlcRIhCgx0aW1lc3RhbXBfdXMYAiABKA'
    'NSC3RpbWVzdGFtcFVzEh0KCnJlcXVlc3RfaWQYAyABKAlSCXJlcXVlc3RJZBI2CgRraW5kGAQg'
    'ASgOMiIucnVuYW55d2hlcmUudjEuVkFEU3RyZWFtRXZlbnRLaW5kUgRraW5kEjYKBnJlc3VsdB'
    'gFIAEoCzIZLnJ1bmFueXdoZXJlLnYxLlZBRFJlc3VsdEgAUgZyZXN1bHSIAQESRAoIYWN0aXZp'
    'dHkYBiABKAsyIy5ydW5hbnl3aGVyZS52MS5TcGVlY2hBY3Rpdml0eUV2ZW50SAFSCGFjdGl2aX'
    'R5iAEBEkIKCnN0YXRpc3RpY3MYByABKAsyHS5ydW5hbnl3aGVyZS52MS5WQURTdGF0aXN0aWNz'
    'SAJSCnN0YXRpc3RpY3OIAQESKAoNZXJyb3JfbWVzc2FnZRgIIAEoCUgDUgxlcnJvck1lc3NhZ2'
    'WIAQESHQoKZXJyb3JfY29kZRgJIAEoBVIJZXJyb3JDb2RlQgkKB19yZXN1bHRCCwoJX2FjdGl2'
    'aXR5Qg0KC19zdGF0aXN0aWNzQhAKDl9lcnJvcl9tZXNzYWdl');

@$core.Deprecated('Use vADServiceStateDescriptor instead')
const VADServiceState$json = {
  '1': 'VADServiceState',
  '2': [
    {'1': 'is_ready', '3': 1, '4': 1, '5': 8, '10': 'isReady'},
    {'1': 'is_speech_active', '3': 2, '4': 1, '5': 8, '10': 'isSpeechActive'},
    {'1': 'energy_threshold', '3': 3, '4': 1, '5': 2, '10': 'energyThreshold'},
    {'1': 'sample_rate', '3': 4, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'frame_length_ms', '3': 5, '4': 1, '5': 5, '10': 'frameLengthMs'},
    {'1': 'current_model', '3': 6, '4': 1, '5': 9, '9': 0, '10': 'currentModel', '17': true},
    {'1': 'error_message', '3': 7, '4': 1, '5': 9, '9': 1, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 8, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_current_model'},
    {'1': '_error_message'},
  ],
};

/// Descriptor for `VADServiceState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADServiceStateDescriptor = $convert.base64Decode(
    'Cg9WQURTZXJ2aWNlU3RhdGUSGQoIaXNfcmVhZHkYASABKAhSB2lzUmVhZHkSKAoQaXNfc3BlZW'
    'NoX2FjdGl2ZRgCIAEoCFIOaXNTcGVlY2hBY3RpdmUSKQoQZW5lcmd5X3RocmVzaG9sZBgDIAEo'
    'AlIPZW5lcmd5VGhyZXNob2xkEh8KC3NhbXBsZV9yYXRlGAQgASgFUgpzYW1wbGVSYXRlEiYKD2'
    'ZyYW1lX2xlbmd0aF9tcxgFIAEoBVINZnJhbWVMZW5ndGhNcxIoCg1jdXJyZW50X21vZGVsGAYg'
    'ASgJSABSDGN1cnJlbnRNb2RlbIgBARIoCg1lcnJvcl9tZXNzYWdlGAcgASgJSAFSDGVycm9yTW'
    'Vzc2FnZYgBARIdCgplcnJvcl9jb2RlGAggASgFUgllcnJvckNvZGVCEAoOX2N1cnJlbnRfbW9k'
    'ZWxCEAoOX2Vycm9yX21lc3NhZ2U=');

const $core.Map<$core.String, $core.dynamic> VADServiceBase$json = {
  '1': 'VAD',
  '2': [
    {'1': 'ProcessFrame', '2': '.runanywhere.v1.VADProcessRequest', '3': '.runanywhere.v1.VADResult'},
    {'1': 'Stream', '2': '.runanywhere.v1.VADProcessRequest', '3': '.runanywhere.v1.VADStreamEvent', '6': true},
  ],
};

@$core.Deprecated('Use vADServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> VADServiceBase$messageJson = {
  '.runanywhere.v1.VADProcessRequest': VADProcessRequest$json,
  '.runanywhere.v1.VADAudioSource': VADAudioSource$json,
  '.runanywhere.v1.VADOptions': VADOptions$json,
  '.runanywhere.v1.VADProcessRequest.MetadataEntry': VADProcessRequest_MetadataEntry$json,
  '.runanywhere.v1.VADResult': VADResult$json,
  '.runanywhere.v1.VADStatistics': VADStatistics$json,
  '.runanywhere.v1.VADStreamEvent': VADStreamEvent$json,
  '.runanywhere.v1.SpeechActivityEvent': SpeechActivityEvent$json,
};

/// Descriptor for `VAD`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List vADServiceDescriptor = $convert.base64Decode(
    'CgNWQUQSTAoMUHJvY2Vzc0ZyYW1lEiEucnVuYW55d2hlcmUudjEuVkFEUHJvY2Vzc1JlcXVlc3'
    'QaGS5ydW5hbnl3aGVyZS52MS5WQURSZXN1bHQSTQoGU3RyZWFtEiEucnVuYW55d2hlcmUudjEu'
    'VkFEUHJvY2Vzc1JlcXVlc3QaHi5ydW5hbnl3aGVyZS52MS5WQURTdHJlYW1FdmVudDAB');

