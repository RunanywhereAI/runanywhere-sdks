///
//  Generated code. Do not modify.
//  source: download_service.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use downloadStageDescriptor instead')
const DownloadStage$json = const {
  '1': 'DownloadStage',
  '2': const [
    const {'1': 'DOWNLOAD_STAGE_UNSPECIFIED', '2': 0},
    const {'1': 'DOWNLOAD_STAGE_DOWNLOADING', '2': 1},
    const {'1': 'DOWNLOAD_STAGE_EXTRACTING', '2': 2},
    const {'1': 'DOWNLOAD_STAGE_VALIDATING', '2': 3},
    const {'1': 'DOWNLOAD_STAGE_COMPLETED', '2': 4},
  ],
};

/// Descriptor for `DownloadStage`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List downloadStageDescriptor = $convert.base64Decode('Cg1Eb3dubG9hZFN0YWdlEh4KGkRPV05MT0FEX1NUQUdFX1VOU1BFQ0lGSUVEEAASHgoaRE9XTkxPQURfU1RBR0VfRE9XTkxPQURJTkcQARIdChlET1dOTE9BRF9TVEFHRV9FWFRSQUNUSU5HEAISHQoZRE9XTkxPQURfU1RBR0VfVkFMSURBVElORxADEhwKGERPV05MT0FEX1NUQUdFX0NPTVBMRVRFRBAE');
@$core.Deprecated('Use downloadStateDescriptor instead')
const DownloadState$json = const {
  '1': 'DownloadState',
  '2': const [
    const {'1': 'DOWNLOAD_STATE_UNSPECIFIED', '2': 0},
    const {'1': 'DOWNLOAD_STATE_PENDING', '2': 1},
    const {'1': 'DOWNLOAD_STATE_DOWNLOADING', '2': 2},
    const {'1': 'DOWNLOAD_STATE_EXTRACTING', '2': 3},
    const {'1': 'DOWNLOAD_STATE_RETRYING', '2': 4},
    const {'1': 'DOWNLOAD_STATE_COMPLETED', '2': 5},
    const {'1': 'DOWNLOAD_STATE_FAILED', '2': 6},
    const {'1': 'DOWNLOAD_STATE_CANCELLED', '2': 7},
  ],
};

/// Descriptor for `DownloadState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List downloadStateDescriptor = $convert.base64Decode('Cg1Eb3dubG9hZFN0YXRlEh4KGkRPV05MT0FEX1NUQVRFX1VOU1BFQ0lGSUVEEAASGgoWRE9XTkxPQURfU1RBVEVfUEVORElORxABEh4KGkRPV05MT0FEX1NUQVRFX0RPV05MT0FESU5HEAISHQoZRE9XTkxPQURfU1RBVEVfRVhUUkFDVElORxADEhsKF0RPV05MT0FEX1NUQVRFX1JFVFJZSU5HEAQSHAoYRE9XTkxPQURfU1RBVEVfQ09NUExFVEVEEAUSGQoVRE9XTkxPQURfU1RBVEVfRkFJTEVEEAYSHAoYRE9XTkxPQURfU1RBVEVfQ0FOQ0VMTEVEEAc=');
@$core.Deprecated('Use downloadSubscribeRequestDescriptor instead')
const DownloadSubscribeRequest$json = const {
  '1': 'DownloadSubscribeRequest',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
  ],
};

/// Descriptor for `DownloadSubscribeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadSubscribeRequestDescriptor = $convert.base64Decode('ChhEb3dubG9hZFN1YnNjcmliZVJlcXVlc3QSGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQ=');
@$core.Deprecated('Use downloadProgressDescriptor instead')
const DownloadProgress$json = const {
  '1': 'DownloadProgress',
  '2': const [
    const {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'stage', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.DownloadStage', '10': 'stage'},
    const {'1': 'bytes_downloaded', '3': 3, '4': 1, '5': 3, '10': 'bytesDownloaded'},
    const {'1': 'total_bytes', '3': 4, '4': 1, '5': 3, '10': 'totalBytes'},
    const {'1': 'stage_progress', '3': 5, '4': 1, '5': 2, '10': 'stageProgress'},
    const {'1': 'overall_speed_bps', '3': 6, '4': 1, '5': 2, '10': 'overallSpeedBps'},
    const {'1': 'eta_seconds', '3': 7, '4': 1, '5': 3, '10': 'etaSeconds'},
    const {'1': 'state', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.DownloadState', '10': 'state'},
    const {'1': 'retry_attempt', '3': 9, '4': 1, '5': 5, '10': 'retryAttempt'},
    const {'1': 'error_message', '3': 10, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `DownloadProgress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadProgressDescriptor = $convert.base64Decode('ChBEb3dubG9hZFByb2dyZXNzEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEjMKBXN0YWdlGAIgASgOMh0ucnVuYW55d2hlcmUudjEuRG93bmxvYWRTdGFnZVIFc3RhZ2USKQoQYnl0ZXNfZG93bmxvYWRlZBgDIAEoA1IPYnl0ZXNEb3dubG9hZGVkEh8KC3RvdGFsX2J5dGVzGAQgASgDUgp0b3RhbEJ5dGVzEiUKDnN0YWdlX3Byb2dyZXNzGAUgASgCUg1zdGFnZVByb2dyZXNzEioKEW92ZXJhbGxfc3BlZWRfYnBzGAYgASgCUg9vdmVyYWxsU3BlZWRCcHMSHwoLZXRhX3NlY29uZHMYByABKANSCmV0YVNlY29uZHMSMwoFc3RhdGUYCCABKA4yHS5ydW5hbnl3aGVyZS52MS5Eb3dubG9hZFN0YXRlUgVzdGF0ZRIjCg1yZXRyeV9hdHRlbXB0GAkgASgFUgxyZXRyeUF0dGVtcHQSIwoNZXJyb3JfbWVzc2FnZRgKIAEoCVIMZXJyb3JNZXNzYWdl');
const $core.Map<$core.String, $core.dynamic> DownloadServiceBase$json = const {
  '1': 'Download',
  '2': const [
    const {'1': 'Subscribe', '2': '.runanywhere.v1.DownloadSubscribeRequest', '3': '.runanywhere.v1.DownloadProgress', '6': true},
  ],
};

@$core.Deprecated('Use downloadServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> DownloadServiceBase$messageJson = const {
  '.runanywhere.v1.DownloadSubscribeRequest': DownloadSubscribeRequest$json,
  '.runanywhere.v1.DownloadProgress': DownloadProgress$json,
};

/// Descriptor for `Download`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List downloadServiceDescriptor = $convert.base64Decode('CghEb3dubG9hZBJZCglTdWJzY3JpYmUSKC5ydW5hbnl3aGVyZS52MS5Eb3dubG9hZFN1YnNjcmliZVJlcXVlc3QaIC5ydW5hbnl3aGVyZS52MS5Eb3dubG9hZFByb2dyZXNzMAE=');
