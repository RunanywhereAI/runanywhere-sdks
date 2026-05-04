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

@$core.Deprecated('Use vADConfigurationDescriptor instead')
const VADConfiguration$json = {
  '1': 'VADConfiguration',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'sample_rate', '3': 2, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'frame_length_ms', '3': 3, '4': 1, '5': 5, '10': 'frameLengthMs'},
    {'1': 'threshold', '3': 4, '4': 1, '5': 2, '10': 'threshold'},
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
    'ChBWQURDb25maWd1cmF0aW9uEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEh8KC3NhbXBsZV'
    '9yYXRlGAIgASgFUgpzYW1wbGVSYXRlEiYKD2ZyYW1lX2xlbmd0aF9tcxgDIAEoBVINZnJhbWVM'
    'ZW5ndGhNcxIcCgl0aHJlc2hvbGQYBCABKAJSCXRocmVzaG9sZBI2ChdlbmFibGVfYXV0b19jYW'
    'xpYnJhdGlvbhgFIAEoCFIVZW5hYmxlQXV0b0NhbGlicmF0aW9uEjUKFmNhbGlicmF0aW9uX211'
    'bHRpcGxpZXIYBiABKAJSFWNhbGlicmF0aW9uTXVsdGlwbGllchJYChNwcmVmZXJyZWRfZnJhbW'
    'V3b3JrGAcgASgOMiIucnVuYW55d2hlcmUudjEuSW5mZXJlbmNlRnJhbWV3b3JrSABSEnByZWZl'
    'cnJlZEZyYW1ld29ya4gBARIiCgptb2RlbF9wYXRoGAggASgJSAFSCW1vZGVsUGF0aIgBARIuCh'
    'N3aW5kb3dfc2l6ZV9zYW1wbGVzGAkgASgFUhF3aW5kb3dTaXplU2FtcGxlcxIzChZtYXhfc3Bl'
    'ZWNoX2R1cmF0aW9uX21zGAogASgFUhNtYXhTcGVlY2hEdXJhdGlvbk1zQhYKFF9wcmVmZXJyZW'
    'RfZnJhbWV3b3JrQg0KC19tb2RlbF9wYXRo');

@$core.Deprecated('Use vADOptionsDescriptor instead')
const VADOptions$json = {
  '1': 'VADOptions',
  '2': [
    {'1': 'threshold', '3': 1, '4': 1, '5': 2, '10': 'threshold'},
    {'1': 'min_speech_duration_ms', '3': 2, '4': 1, '5': 5, '10': 'minSpeechDurationMs'},
    {'1': 'min_silence_duration_ms', '3': 3, '4': 1, '5': 5, '10': 'minSilenceDurationMs'},
    {'1': 'max_speech_duration_ms', '3': 4, '4': 1, '5': 5, '10': 'maxSpeechDurationMs'},
  ],
};

/// Descriptor for `VADOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADOptionsDescriptor = $convert.base64Decode(
    'CgpWQURPcHRpb25zEhwKCXRocmVzaG9sZBgBIAEoAlIJdGhyZXNob2xkEjMKFm1pbl9zcGVlY2'
    'hfZHVyYXRpb25fbXMYAiABKAVSE21pblNwZWVjaER1cmF0aW9uTXMSNQoXbWluX3NpbGVuY2Vf'
    'ZHVyYXRpb25fbXMYAyABKAVSFG1pblNpbGVuY2VEdXJhdGlvbk1zEjMKFm1heF9zcGVlY2hfZH'
    'VyYXRpb25fbXMYBCABKAVSE21heFNwZWVjaER1cmF0aW9uTXM=');

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
  ],
};

/// Descriptor for `VADResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADResultDescriptor = $convert.base64Decode(
    'CglWQURSZXN1bHQSGwoJaXNfc3BlZWNoGAEgASgIUghpc1NwZWVjaBIeCgpjb25maWRlbmNlGA'
    'IgASgCUgpjb25maWRlbmNlEhYKBmVuZXJneRgDIAEoAlIGZW5lcmd5Eh8KC2R1cmF0aW9uX21z'
    'GAQgASgFUgpkdXJhdGlvbk1zEiEKDHRpbWVzdGFtcF9tcxgFIAEoA1ILdGltZXN0YW1wTXMSIg'
    'oNc3RhcnRfdGltZV9tcxgGIAEoA1ILc3RhcnRUaW1lTXMSHgoLZW5kX3RpbWVfbXMYByABKANS'
    'CWVuZFRpbWVNcw==');

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
  ],
};

/// Descriptor for `SpeechActivityEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List speechActivityEventDescriptor = $convert.base64Decode(
    'ChNTcGVlY2hBY3Rpdml0eUV2ZW50EkEKCmV2ZW50X3R5cGUYASABKA4yIi5ydW5hbnl3aGVyZS'
    '52MS5TcGVlY2hBY3Rpdml0eUtpbmRSCWV2ZW50VHlwZRIhCgx0aW1lc3RhbXBfbXMYAiABKANS'
    'C3RpbWVzdGFtcE1zEh8KC2R1cmF0aW9uX21zGAMgASgFUgpkdXJhdGlvbk1z');

