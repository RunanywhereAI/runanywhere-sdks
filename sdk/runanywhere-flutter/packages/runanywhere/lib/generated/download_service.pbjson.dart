//
//  Generated code. Do not modify.
//  source: download_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use downloadStageDescriptor instead')
const DownloadStage$json = {
  '1': 'DownloadStage',
  '2': [
    {'1': 'DOWNLOAD_STAGE_UNSPECIFIED', '2': 0},
    {'1': 'DOWNLOAD_STAGE_DOWNLOADING', '2': 1},
    {'1': 'DOWNLOAD_STAGE_EXTRACTING', '2': 2},
    {'1': 'DOWNLOAD_STAGE_VALIDATING', '2': 3},
    {'1': 'DOWNLOAD_STAGE_COMPLETED', '2': 4},
  ],
};

/// Descriptor for `DownloadStage`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List downloadStageDescriptor = $convert.base64Decode(
    'Cg1Eb3dubG9hZFN0YWdlEh4KGkRPV05MT0FEX1NUQUdFX1VOU1BFQ0lGSUVEEAASHgoaRE9XTk'
    'xPQURfU1RBR0VfRE9XTkxPQURJTkcQARIdChlET1dOTE9BRF9TVEFHRV9FWFRSQUNUSU5HEAIS'
    'HQoZRE9XTkxPQURfU1RBR0VfVkFMSURBVElORxADEhwKGERPV05MT0FEX1NUQUdFX0NPTVBMRV'
    'RFRBAE');

@$core.Deprecated('Use downloadStateDescriptor instead')
const DownloadState$json = {
  '1': 'DownloadState',
  '2': [
    {'1': 'DOWNLOAD_STATE_UNSPECIFIED', '2': 0},
    {'1': 'DOWNLOAD_STATE_PENDING', '2': 1},
    {'1': 'DOWNLOAD_STATE_DOWNLOADING', '2': 2},
    {'1': 'DOWNLOAD_STATE_EXTRACTING', '2': 3},
    {'1': 'DOWNLOAD_STATE_RETRYING', '2': 4},
    {'1': 'DOWNLOAD_STATE_COMPLETED', '2': 5},
    {'1': 'DOWNLOAD_STATE_FAILED', '2': 6},
    {'1': 'DOWNLOAD_STATE_CANCELLED', '2': 7},
  ],
};

/// Descriptor for `DownloadState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List downloadStateDescriptor = $convert.base64Decode(
    'Cg1Eb3dubG9hZFN0YXRlEh4KGkRPV05MT0FEX1NUQVRFX1VOU1BFQ0lGSUVEEAASGgoWRE9XTk'
    'xPQURfU1RBVEVfUEVORElORxABEh4KGkRPV05MT0FEX1NUQVRFX0RPV05MT0FESU5HEAISHQoZ'
    'RE9XTkxPQURfU1RBVEVfRVhUUkFDVElORxADEhsKF0RPV05MT0FEX1NUQVRFX1JFVFJZSU5HEA'
    'QSHAoYRE9XTkxPQURfU1RBVEVfQ09NUExFVEVEEAUSGQoVRE9XTkxPQURfU1RBVEVfRkFJTEVE'
    'EAYSHAoYRE9XTkxPQURfU1RBVEVfQ0FOQ0VMTEVEEAc=');

@$core.Deprecated('Use downloadSubscribeRequestDescriptor instead')
const DownloadSubscribeRequest$json = {
  '1': 'DownloadSubscribeRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
  ],
};

/// Descriptor for `DownloadSubscribeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadSubscribeRequestDescriptor = $convert.base64Decode(
    'ChhEb3dubG9hZFN1YnNjcmliZVJlcXVlc3QSGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQ=');

@$core.Deprecated('Use downloadProgressDescriptor instead')
const DownloadProgress$json = {
  '1': 'DownloadProgress',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'stage', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.DownloadStage', '10': 'stage'},
    {'1': 'bytes_downloaded', '3': 3, '4': 1, '5': 3, '10': 'bytesDownloaded'},
    {'1': 'total_bytes', '3': 4, '4': 1, '5': 3, '10': 'totalBytes'},
    {'1': 'stage_progress', '3': 5, '4': 1, '5': 2, '10': 'stageProgress'},
    {'1': 'overall_speed_bps', '3': 6, '4': 1, '5': 2, '10': 'overallSpeedBps'},
    {'1': 'eta_seconds', '3': 7, '4': 1, '5': 3, '10': 'etaSeconds'},
    {'1': 'state', '3': 8, '4': 1, '5': 14, '6': '.runanywhere.v1.DownloadState', '10': 'state'},
    {'1': 'retry_attempt', '3': 9, '4': 1, '5': 5, '10': 'retryAttempt'},
    {'1': 'error_message', '3': 10, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `DownloadProgress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadProgressDescriptor = $convert.base64Decode(
    'ChBEb3dubG9hZFByb2dyZXNzEhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEjMKBXN0YWdlGA'
    'IgASgOMh0ucnVuYW55d2hlcmUudjEuRG93bmxvYWRTdGFnZVIFc3RhZ2USKQoQYnl0ZXNfZG93'
    'bmxvYWRlZBgDIAEoA1IPYnl0ZXNEb3dubG9hZGVkEh8KC3RvdGFsX2J5dGVzGAQgASgDUgp0b3'
    'RhbEJ5dGVzEiUKDnN0YWdlX3Byb2dyZXNzGAUgASgCUg1zdGFnZVByb2dyZXNzEioKEW92ZXJh'
    'bGxfc3BlZWRfYnBzGAYgASgCUg9vdmVyYWxsU3BlZWRCcHMSHwoLZXRhX3NlY29uZHMYByABKA'
    'NSCmV0YVNlY29uZHMSMwoFc3RhdGUYCCABKA4yHS5ydW5hbnl3aGVyZS52MS5Eb3dubG9hZFN0'
    'YXRlUgVzdGF0ZRIjCg1yZXRyeV9hdHRlbXB0GAkgASgFUgxyZXRyeUF0dGVtcHQSIwoNZXJyb3'
    'JfbWVzc2FnZRgKIAEoCVIMZXJyb3JNZXNzYWdl');

