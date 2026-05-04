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

import 'model_types.pbjson.dart' as $3;

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
    {'1': 'DOWNLOAD_STATE_PAUSED', '2': 8},
    {'1': 'DOWNLOAD_STATE_RESUMING', '2': 9},
  ],
};

/// Descriptor for `DownloadState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List downloadStateDescriptor = $convert.base64Decode(
    'Cg1Eb3dubG9hZFN0YXRlEh4KGkRPV05MT0FEX1NUQVRFX1VOU1BFQ0lGSUVEEAASGgoWRE9XTk'
    'xPQURfU1RBVEVfUEVORElORxABEh4KGkRPV05MT0FEX1NUQVRFX0RPV05MT0FESU5HEAISHQoZ'
    'RE9XTkxPQURfU1RBVEVfRVhUUkFDVElORxADEhsKF0RPV05MT0FEX1NUQVRFX1JFVFJZSU5HEA'
    'QSHAoYRE9XTkxPQURfU1RBVEVfQ09NUExFVEVEEAUSGQoVRE9XTkxPQURfU1RBVEVfRkFJTEVE'
    'EAYSHAoYRE9XTkxPQURfU1RBVEVfQ0FOQ0VMTEVEEAcSGQoVRE9XTkxPQURfU1RBVEVfUEFVU0'
    'VEEAgSGwoXRE9XTkxPQURfU1RBVEVfUkVTVU1JTkcQCQ==');

@$core.Deprecated('Use downloadSubscribeRequestDescriptor instead')
const DownloadSubscribeRequest$json = {
  '1': 'DownloadSubscribeRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'task_id', '3': 2, '4': 1, '5': 9, '10': 'taskId'},
  ],
};

/// Descriptor for `DownloadSubscribeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadSubscribeRequestDescriptor = $convert.base64Decode(
    'ChhEb3dubG9hZFN1YnNjcmliZVJlcXVlc3QSGQoIbW9kZWxfaWQYASABKAlSB21vZGVsSWQSFw'
    'oHdGFza19pZBgCIAEoCVIGdGFza0lk');

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
    {'1': 'task_id', '3': 11, '4': 1, '5': 9, '10': 'taskId'},
    {'1': 'current_file_index', '3': 12, '4': 1, '5': 5, '10': 'currentFileIndex'},
    {'1': 'total_files', '3': 13, '4': 1, '5': 5, '10': 'totalFiles'},
    {'1': 'storage_key', '3': 14, '4': 1, '5': 9, '10': 'storageKey'},
    {'1': 'local_path', '3': 15, '4': 1, '5': 9, '10': 'localPath'},
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
    'JfbWVzc2FnZRgKIAEoCVIMZXJyb3JNZXNzYWdlEhcKB3Rhc2tfaWQYCyABKAlSBnRhc2tJZBIs'
    'ChJjdXJyZW50X2ZpbGVfaW5kZXgYDCABKAVSEGN1cnJlbnRGaWxlSW5kZXgSHwoLdG90YWxfZm'
    'lsZXMYDSABKAVSCnRvdGFsRmlsZXMSHwoLc3RvcmFnZV9rZXkYDiABKAlSCnN0b3JhZ2VLZXkS'
    'HQoKbG9jYWxfcGF0aBgPIAEoCVIJbG9jYWxQYXRo');

@$core.Deprecated('Use downloadPlanRequestDescriptor instead')
const DownloadPlanRequest$json = {
  '1': 'DownloadPlanRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'model', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelInfo', '9': 0, '10': 'model', '17': true},
    {'1': 'resume_existing', '3': 3, '4': 1, '5': 8, '10': 'resumeExisting'},
    {'1': 'available_storage_bytes', '3': 4, '4': 1, '5': 3, '10': 'availableStorageBytes'},
    {'1': 'allow_metered_network', '3': 5, '4': 1, '5': 8, '10': 'allowMeteredNetwork'},
  ],
  '8': [
    {'1': '_model'},
  ],
};

/// Descriptor for `DownloadPlanRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadPlanRequestDescriptor = $convert.base64Decode(
    'ChNEb3dubG9hZFBsYW5SZXF1ZXN0EhkKCG1vZGVsX2lkGAEgASgJUgdtb2RlbElkEjQKBW1vZG'
    'VsGAIgASgLMhkucnVuYW55d2hlcmUudjEuTW9kZWxJbmZvSABSBW1vZGVsiAEBEicKD3Jlc3Vt'
    'ZV9leGlzdGluZxgDIAEoCFIOcmVzdW1lRXhpc3RpbmcSNgoXYXZhaWxhYmxlX3N0b3JhZ2VfYn'
    'l0ZXMYBCABKANSFWF2YWlsYWJsZVN0b3JhZ2VCeXRlcxIyChVhbGxvd19tZXRlcmVkX25ldHdv'
    'cmsYBSABKAhSE2FsbG93TWV0ZXJlZE5ldHdvcmtCCAoGX21vZGVs');

@$core.Deprecated('Use downloadFilePlanDescriptor instead')
const DownloadFilePlan$json = {
  '1': 'DownloadFilePlan',
  '2': [
    {'1': 'file', '3': 1, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelFileDescriptor', '10': 'file'},
    {'1': 'storage_key', '3': 2, '4': 1, '5': 9, '10': 'storageKey'},
    {'1': 'destination_path', '3': 3, '4': 1, '5': 9, '10': 'destinationPath'},
    {'1': 'expected_bytes', '3': 4, '4': 1, '5': 3, '10': 'expectedBytes'},
    {'1': 'requires_extraction', '3': 5, '4': 1, '5': 8, '10': 'requiresExtraction'},
    {'1': 'checksum_sha256', '3': 6, '4': 1, '5': 9, '10': 'checksumSha256'},
  ],
};

/// Descriptor for `DownloadFilePlan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadFilePlanDescriptor = $convert.base64Decode(
    'ChBEb3dubG9hZEZpbGVQbGFuEjcKBGZpbGUYASABKAsyIy5ydW5hbnl3aGVyZS52MS5Nb2RlbE'
    'ZpbGVEZXNjcmlwdG9yUgRmaWxlEh8KC3N0b3JhZ2Vfa2V5GAIgASgJUgpzdG9yYWdlS2V5EikK'
    'EGRlc3RpbmF0aW9uX3BhdGgYAyABKAlSD2Rlc3RpbmF0aW9uUGF0aBIlCg5leHBlY3RlZF9ieX'
    'RlcxgEIAEoA1INZXhwZWN0ZWRCeXRlcxIvChNyZXF1aXJlc19leHRyYWN0aW9uGAUgASgIUhJy'
    'ZXF1aXJlc0V4dHJhY3Rpb24SJwoPY2hlY2tzdW1fc2hhMjU2GAYgASgJUg5jaGVja3N1bVNoYT'
    'I1Ng==');

@$core.Deprecated('Use downloadPlanResultDescriptor instead')
const DownloadPlanResult$json = {
  '1': 'DownloadPlanResult',
  '2': [
    {'1': 'can_start', '3': 1, '4': 1, '5': 8, '10': 'canStart'},
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'files', '3': 3, '4': 3, '5': 11, '6': '.runanywhere.v1.DownloadFilePlan', '10': 'files'},
    {'1': 'total_bytes', '3': 4, '4': 1, '5': 3, '10': 'totalBytes'},
    {'1': 'requires_extraction', '3': 5, '4': 1, '5': 8, '10': 'requiresExtraction'},
    {'1': 'can_resume', '3': 6, '4': 1, '5': 8, '10': 'canResume'},
    {'1': 'resume_from_bytes', '3': 7, '4': 1, '5': 3, '10': 'resumeFromBytes'},
    {'1': 'warnings', '3': 8, '4': 3, '5': 9, '10': 'warnings'},
    {'1': 'error_message', '3': 9, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `DownloadPlanResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadPlanResultDescriptor = $convert.base64Decode(
    'ChJEb3dubG9hZFBsYW5SZXN1bHQSGwoJY2FuX3N0YXJ0GAEgASgIUghjYW5TdGFydBIZCghtb2'
    'RlbF9pZBgCIAEoCVIHbW9kZWxJZBI2CgVmaWxlcxgDIAMoCzIgLnJ1bmFueXdoZXJlLnYxLkRv'
    'd25sb2FkRmlsZVBsYW5SBWZpbGVzEh8KC3RvdGFsX2J5dGVzGAQgASgDUgp0b3RhbEJ5dGVzEi'
    '8KE3JlcXVpcmVzX2V4dHJhY3Rpb24YBSABKAhSEnJlcXVpcmVzRXh0cmFjdGlvbhIdCgpjYW5f'
    'cmVzdW1lGAYgASgIUgljYW5SZXN1bWUSKgoRcmVzdW1lX2Zyb21fYnl0ZXMYByABKANSD3Jlc3'
    'VtZUZyb21CeXRlcxIaCgh3YXJuaW5ncxgIIAMoCVIId2FybmluZ3MSIwoNZXJyb3JfbWVzc2Fn'
    'ZRgJIAEoCVIMZXJyb3JNZXNzYWdl');

@$core.Deprecated('Use downloadStartRequestDescriptor instead')
const DownloadStartRequest$json = {
  '1': 'DownloadStartRequest',
  '2': [
    {'1': 'model_id', '3': 1, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'plan', '3': 2, '4': 1, '5': 11, '6': '.runanywhere.v1.DownloadPlanResult', '10': 'plan'},
    {'1': 'resume', '3': 3, '4': 1, '5': 8, '10': 'resume'},
  ],
};

/// Descriptor for `DownloadStartRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadStartRequestDescriptor = $convert.base64Decode(
    'ChREb3dubG9hZFN0YXJ0UmVxdWVzdBIZCghtb2RlbF9pZBgBIAEoCVIHbW9kZWxJZBI2CgRwbG'
    'FuGAIgASgLMiIucnVuYW55d2hlcmUudjEuRG93bmxvYWRQbGFuUmVzdWx0UgRwbGFuEhYKBnJl'
    'c3VtZRgDIAEoCFIGcmVzdW1l');

@$core.Deprecated('Use downloadStartResultDescriptor instead')
const DownloadStartResult$json = {
  '1': 'DownloadStartResult',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'task_id', '3': 2, '4': 1, '5': 9, '10': 'taskId'},
    {'1': 'model_id', '3': 3, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'initial_progress', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.DownloadProgress', '10': 'initialProgress'},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `DownloadStartResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadStartResultDescriptor = $convert.base64Decode(
    'ChNEb3dubG9hZFN0YXJ0UmVzdWx0EhoKCGFjY2VwdGVkGAEgASgIUghhY2NlcHRlZBIXCgd0YX'
    'NrX2lkGAIgASgJUgZ0YXNrSWQSGQoIbW9kZWxfaWQYAyABKAlSB21vZGVsSWQSSwoQaW5pdGlh'
    'bF9wcm9ncmVzcxgEIAEoCzIgLnJ1bmFueXdoZXJlLnYxLkRvd25sb2FkUHJvZ3Jlc3NSD2luaX'
    'RpYWxQcm9ncmVzcxIjCg1lcnJvcl9tZXNzYWdlGAUgASgJUgxlcnJvck1lc3NhZ2U=');

@$core.Deprecated('Use downloadCancelRequestDescriptor instead')
const DownloadCancelRequest$json = {
  '1': 'DownloadCancelRequest',
  '2': [
    {'1': 'task_id', '3': 1, '4': 1, '5': 9, '10': 'taskId'},
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'delete_partial_bytes', '3': 3, '4': 1, '5': 8, '10': 'deletePartialBytes'},
  ],
};

/// Descriptor for `DownloadCancelRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadCancelRequestDescriptor = $convert.base64Decode(
    'ChVEb3dubG9hZENhbmNlbFJlcXVlc3QSFwoHdGFza19pZBgBIAEoCVIGdGFza0lkEhkKCG1vZG'
    'VsX2lkGAIgASgJUgdtb2RlbElkEjAKFGRlbGV0ZV9wYXJ0aWFsX2J5dGVzGAMgASgIUhJkZWxl'
    'dGVQYXJ0aWFsQnl0ZXM=');

@$core.Deprecated('Use downloadCancelResultDescriptor instead')
const DownloadCancelResult$json = {
  '1': 'DownloadCancelResult',
  '2': [
    {'1': 'success', '3': 1, '4': 1, '5': 8, '10': 'success'},
    {'1': 'task_id', '3': 2, '4': 1, '5': 9, '10': 'taskId'},
    {'1': 'model_id', '3': 3, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'partial_bytes_deleted', '3': 4, '4': 1, '5': 3, '10': 'partialBytesDeleted'},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `DownloadCancelResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadCancelResultDescriptor = $convert.base64Decode(
    'ChREb3dubG9hZENhbmNlbFJlc3VsdBIYCgdzdWNjZXNzGAEgASgIUgdzdWNjZXNzEhcKB3Rhc2'
    'tfaWQYAiABKAlSBnRhc2tJZBIZCghtb2RlbF9pZBgDIAEoCVIHbW9kZWxJZBIyChVwYXJ0aWFs'
    'X2J5dGVzX2RlbGV0ZWQYBCABKANSE3BhcnRpYWxCeXRlc0RlbGV0ZWQSIwoNZXJyb3JfbWVzc2'
    'FnZRgFIAEoCVIMZXJyb3JNZXNzYWdl');

@$core.Deprecated('Use downloadResumeRequestDescriptor instead')
const DownloadResumeRequest$json = {
  '1': 'DownloadResumeRequest',
  '2': [
    {'1': 'task_id', '3': 1, '4': 1, '5': 9, '10': 'taskId'},
    {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'resume_from_bytes', '3': 3, '4': 1, '5': 3, '10': 'resumeFromBytes'},
  ],
};

/// Descriptor for `DownloadResumeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadResumeRequestDescriptor = $convert.base64Decode(
    'ChVEb3dubG9hZFJlc3VtZVJlcXVlc3QSFwoHdGFza19pZBgBIAEoCVIGdGFza0lkEhkKCG1vZG'
    'VsX2lkGAIgASgJUgdtb2RlbElkEioKEXJlc3VtZV9mcm9tX2J5dGVzGAMgASgDUg9yZXN1bWVG'
    'cm9tQnl0ZXM=');

@$core.Deprecated('Use downloadResumeResultDescriptor instead')
const DownloadResumeResult$json = {
  '1': 'DownloadResumeResult',
  '2': [
    {'1': 'accepted', '3': 1, '4': 1, '5': 8, '10': 'accepted'},
    {'1': 'task_id', '3': 2, '4': 1, '5': 9, '10': 'taskId'},
    {'1': 'model_id', '3': 3, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'initial_progress', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.DownloadProgress', '10': 'initialProgress'},
    {'1': 'error_message', '3': 5, '4': 1, '5': 9, '10': 'errorMessage'},
  ],
};

/// Descriptor for `DownloadResumeResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List downloadResumeResultDescriptor = $convert.base64Decode(
    'ChREb3dubG9hZFJlc3VtZVJlc3VsdBIaCghhY2NlcHRlZBgBIAEoCFIIYWNjZXB0ZWQSFwoHdG'
    'Fza19pZBgCIAEoCVIGdGFza0lkEhkKCG1vZGVsX2lkGAMgASgJUgdtb2RlbElkEksKEGluaXRp'
    'YWxfcHJvZ3Jlc3MYBCABKAsyIC5ydW5hbnl3aGVyZS52MS5Eb3dubG9hZFByb2dyZXNzUg9pbm'
    'l0aWFsUHJvZ3Jlc3MSIwoNZXJyb3JfbWVzc2FnZRgFIAEoCVIMZXJyb3JNZXNzYWdl');

const $core.Map<$core.String, $core.dynamic> DownloadServiceBase$json = {
  '1': 'Download',
  '2': [
    {'1': 'Plan', '2': '.runanywhere.v1.DownloadPlanRequest', '3': '.runanywhere.v1.DownloadPlanResult'},
    {'1': 'Start', '2': '.runanywhere.v1.DownloadStartRequest', '3': '.runanywhere.v1.DownloadStartResult'},
    {'1': 'Subscribe', '2': '.runanywhere.v1.DownloadSubscribeRequest', '3': '.runanywhere.v1.DownloadProgress', '6': true},
    {'1': 'Cancel', '2': '.runanywhere.v1.DownloadCancelRequest', '3': '.runanywhere.v1.DownloadCancelResult'},
    {'1': 'Resume', '2': '.runanywhere.v1.DownloadResumeRequest', '3': '.runanywhere.v1.DownloadResumeResult'},
  ],
};

@$core.Deprecated('Use downloadServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> DownloadServiceBase$messageJson = {
  '.runanywhere.v1.DownloadPlanRequest': DownloadPlanRequest$json,
  '.runanywhere.v1.ModelInfo': $3.ModelInfo$json,
  '.runanywhere.v1.ModelThinkingTagPattern': $3.ModelThinkingTagPattern$json,
  '.runanywhere.v1.ModelInfoMetadata': $3.ModelInfoMetadata$json,
  '.runanywhere.v1.SingleFileArtifact': $3.SingleFileArtifact$json,
  '.runanywhere.v1.ArchiveArtifact': $3.ArchiveArtifact$json,
  '.runanywhere.v1.MultiFileArtifact': $3.MultiFileArtifact$json,
  '.runanywhere.v1.ModelFileDescriptor': $3.ModelFileDescriptor$json,
  '.runanywhere.v1.ExpectedModelFiles': $3.ExpectedModelFiles$json,
  '.runanywhere.v1.ModelRuntimeCompatibility': $3.ModelRuntimeCompatibility$json,
  '.runanywhere.v1.DownloadPlanResult': DownloadPlanResult$json,
  '.runanywhere.v1.DownloadFilePlan': DownloadFilePlan$json,
  '.runanywhere.v1.DownloadStartRequest': DownloadStartRequest$json,
  '.runanywhere.v1.DownloadStartResult': DownloadStartResult$json,
  '.runanywhere.v1.DownloadProgress': DownloadProgress$json,
  '.runanywhere.v1.DownloadSubscribeRequest': DownloadSubscribeRequest$json,
  '.runanywhere.v1.DownloadCancelRequest': DownloadCancelRequest$json,
  '.runanywhere.v1.DownloadCancelResult': DownloadCancelResult$json,
  '.runanywhere.v1.DownloadResumeRequest': DownloadResumeRequest$json,
  '.runanywhere.v1.DownloadResumeResult': DownloadResumeResult$json,
};

/// Descriptor for `Download`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List downloadServiceDescriptor = $convert.base64Decode(
    'CghEb3dubG9hZBJPCgRQbGFuEiMucnVuYW55d2hlcmUudjEuRG93bmxvYWRQbGFuUmVxdWVzdB'
    'oiLnJ1bmFueXdoZXJlLnYxLkRvd25sb2FkUGxhblJlc3VsdBJSCgVTdGFydBIkLnJ1bmFueXdo'
    'ZXJlLnYxLkRvd25sb2FkU3RhcnRSZXF1ZXN0GiMucnVuYW55d2hlcmUudjEuRG93bmxvYWRTdG'
    'FydFJlc3VsdBJZCglTdWJzY3JpYmUSKC5ydW5hbnl3aGVyZS52MS5Eb3dubG9hZFN1YnNjcmli'
    'ZVJlcXVlc3QaIC5ydW5hbnl3aGVyZS52MS5Eb3dubG9hZFByb2dyZXNzMAESVQoGQ2FuY2VsEi'
    'UucnVuYW55d2hlcmUudjEuRG93bmxvYWRDYW5jZWxSZXF1ZXN0GiQucnVuYW55d2hlcmUudjEu'
    'RG93bmxvYWRDYW5jZWxSZXN1bHQSVQoGUmVzdW1lEiUucnVuYW55d2hlcmUudjEuRG93bmxvYW'
    'RSZXN1bWVSZXF1ZXN0GiQucnVuYW55d2hlcmUudjEuRG93bmxvYWRSZXN1bWVSZXN1bHQ=');

