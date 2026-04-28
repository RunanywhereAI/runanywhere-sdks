///
//  Generated code. Do not modify.
//  source: vad_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use speechActivityKindDescriptor instead')
const SpeechActivityKind$json = const {
  '1': 'SpeechActivityKind',
  '2': const [
    const {'1': 'SPEECH_ACTIVITY_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'SPEECH_ACTIVITY_KIND_SPEECH_STARTED', '2': 1},
    const {'1': 'SPEECH_ACTIVITY_KIND_SPEECH_ENDED', '2': 2},
    const {'1': 'SPEECH_ACTIVITY_KIND_ONGOING', '2': 3},
  ],
};

/// Descriptor for `SpeechActivityKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List speechActivityKindDescriptor = $convert.base64Decode('ChJTcGVlY2hBY3Rpdml0eUtpbmQSJAogU1BFRUNIX0FDVElWSVRZX0tJTkRfVU5TUEVDSUZJRUQQABInCiNTUEVFQ0hfQUNUSVZJVFlfS0lORF9TUEVFQ0hfU1RBUlRFRBABEiUKIVNQRUVDSF9BQ1RJVklUWV9LSU5EX1NQRUVDSF9FTkRFRBACEiAKHFNQRUVDSF9BQ1RJVklUWV9LSU5EX09OR09JTkcQAw==');
@$core.Deprecated('Use vADConfigurationDescriptor instead')
const VADConfiguration$json = const {
  '1': 'VADConfiguration',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'sample_rate', '3': 2, '4': 1, '5': 5, '10': 'sampleRate'},
    const {'1': 'frame_length_ms', '3': 3, '4': 1, '5': 5, '10': 'frameLengthMs'},
    const {'1': 'threshold', '3': 4, '4': 1, '5': 2, '10': 'threshold'},
    const {'1': 'enable_auto_calibration', '3': 5, '4': 1, '5': 8, '10': 'enableAutoCalibration'},
  ],
};

/// Descriptor for `VADConfiguration`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADConfigurationDescriptor = $convert.base64Decode('ChBWQURDb25maWd1cmF0aW9uEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEh8KC3NhbXBsZV9yYXRlGAIgASgFUgpzYW1wbGVSYXRlEiYKD2ZyYW1lX2xlbmd0aF9tcxgDIAEoBVINZnJhbWVMZW5ndGhNcxIcCgl0aHJlc2hvbGQYBCABKAJSCXRocmVzaG9sZBI2ChdlbmFibGVfYXV0b19jYWxpYnJhdGlvbhgFIAEoCFIVZW5hYmxlQXV0b0NhbGlicmF0aW9u');
@$core.Deprecated('Use vADOptionsDescriptor instead')
const VADOptions$json = const {
  '1': 'VADOptions',
  '2': const [
    const {'1': 'threshold', '3': 1, '4': 1, '5': 2, '10': 'threshold'},
    const {'1': 'min_speech_duration_ms', '3': 2, '4': 1, '5': 5, '10': 'minSpeechDurationMs'},
    const {'1': 'min_silence_duration_ms', '3': 3, '4': 1, '5': 5, '10': 'minSilenceDurationMs'},
  ],
};

/// Descriptor for `VADOptions`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADOptionsDescriptor = $convert.base64Decode('CgpWQURPcHRpb25zEhwKCXRocmVzaG9sZBgBIAEoAlIJdGhyZXNob2xkEjMKFm1pbl9zcGVlY2hfZHVyYXRpb25fbXMYAiABKAVSE21pblNwZWVjaER1cmF0aW9uTXMSNQoXbWluX3NpbGVuY2VfZHVyYXRpb25fbXMYAyABKAVSFG1pblNpbGVuY2VEdXJhdGlvbk1z');
@$core.Deprecated('Use vADResultDescriptor instead')
const VADResult$json = const {
  '1': 'VADResult',
  '2': const [
    const {'1': 'is_speech', '3': 1, '4': 1, '5': 8, '10': 'isSpeech'},
    const {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
    const {'1': 'energy', '3': 3, '4': 1, '5': 2, '10': 'energy'},
    const {'1': 'duration_ms', '3': 4, '4': 1, '5': 5, '10': 'durationMs'},
  ],
};

/// Descriptor for `VADResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADResultDescriptor = $convert.base64Decode('CglWQURSZXN1bHQSGwoJaXNfc3BlZWNoGAEgASgIUghpc1NwZWVjaBIeCgpjb25maWRlbmNlGAIgASgCUgpjb25maWRlbmNlEhYKBmVuZXJneRgDIAEoAlIGZW5lcmd5Eh8KC2R1cmF0aW9uX21zGAQgASgFUgpkdXJhdGlvbk1z');
@$core.Deprecated('Use vADStatisticsDescriptor instead')
const VADStatistics$json = const {
  '1': 'VADStatistics',
  '2': const [
    const {'1': 'current_energy', '3': 1, '4': 1, '5': 2, '10': 'currentEnergy'},
    const {'1': 'current_threshold', '3': 2, '4': 1, '5': 2, '10': 'currentThreshold'},
    const {'1': 'ambient_level', '3': 3, '4': 1, '5': 2, '10': 'ambientLevel'},
    const {'1': 'recent_avg', '3': 4, '4': 1, '5': 2, '10': 'recentAvg'},
    const {'1': 'recent_max', '3': 5, '4': 1, '5': 2, '10': 'recentMax'},
  ],
};

/// Descriptor for `VADStatistics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADStatisticsDescriptor = $convert.base64Decode('Cg1WQURTdGF0aXN0aWNzEiUKDmN1cnJlbnRfZW5lcmd5GAEgASgCUg1jdXJyZW50RW5lcmd5EisKEWN1cnJlbnRfdGhyZXNob2xkGAIgASgCUhBjdXJyZW50VGhyZXNob2xkEiMKDWFtYmllbnRfbGV2ZWwYAyABKAJSDGFtYmllbnRMZXZlbBIdCgpyZWNlbnRfYXZnGAQgASgCUglyZWNlbnRBdmcSHQoKcmVjZW50X21heBgFIAEoAlIJcmVjZW50TWF4');
@$core.Deprecated('Use speechActivityEventDescriptor instead')
const SpeechActivityEvent$json = const {
  '1': 'SpeechActivityEvent',
  '2': const [
    const {'1': 'event_type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.SpeechActivityKind', '10': 'eventType'},
    const {'1': 'timestamp_ms', '3': 2, '4': 1, '5': 3, '10': 'timestampMs'},
    const {'1': 'duration_ms', '3': 3, '4': 1, '5': 5, '10': 'durationMs'},
  ],
};

/// Descriptor for `SpeechActivityEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List speechActivityEventDescriptor = $convert.base64Decode('ChNTcGVlY2hBY3Rpdml0eUV2ZW50EkEKCmV2ZW50X3R5cGUYASABKA4yIi5ydW5hbnl3aGVyZS52MS5TcGVlY2hBY3Rpdml0eUtpbmRSCWV2ZW50VHlwZRIhCgx0aW1lc3RhbXBfbXMYAiABKANSC3RpbWVzdGFtcE1zEh8KC2R1cmF0aW9uX21zGAMgASgFUgpkdXJhdGlvbk1z');
