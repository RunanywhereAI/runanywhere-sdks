//
//  Generated code. Do not modify.
//  source: lifecycle_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

import 'model_types.pbjson.dart' as $0;
import 'sdk_events.pbjson.dart' as $1;
import 'thinking_tag_pattern.pbjson.dart' as $2;

const $core.Map<$core.String, $core.dynamic> LifecycleServiceBase$json = {
  '1': 'Lifecycle',
  '2': [
    {'1': 'Load', '2': '.runanywhere.v1.ModelLoadRequest', '3': '.runanywhere.v1.ModelLoadResult'},
    {'1': 'Unload', '2': '.runanywhere.v1.ModelUnloadRequest', '3': '.runanywhere.v1.ModelUnloadResult'},
    {'1': 'Current', '2': '.runanywhere.v1.CurrentModelRequest', '3': '.runanywhere.v1.CurrentModelResult'},
    {'1': 'Snapshot', '2': '.runanywhere.v1.ComponentLifecycleSnapshotRequest', '3': '.runanywhere.v1.ComponentLifecycleSnapshotResult'},
  ],
};

@$core.Deprecated('Use lifecycleServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> LifecycleServiceBase$messageJson = {
  '.runanywhere.v1.ModelLoadRequest': $0.ModelLoadRequest$json,
  '.runanywhere.v1.ModelLoadResult': $0.ModelLoadResult$json,
  '.runanywhere.v1.ModelFileDescriptor': $0.ModelFileDescriptor$json,
  '.runanywhere.v1.ModelUnloadRequest': $0.ModelUnloadRequest$json,
  '.runanywhere.v1.ModelUnloadResult': $0.ModelUnloadResult$json,
  '.runanywhere.v1.CurrentModelRequest': $0.CurrentModelRequest$json,
  '.runanywhere.v1.CurrentModelResult': $0.CurrentModelResult$json,
  '.runanywhere.v1.ModelInfo': $0.ModelInfo$json,
  '.runanywhere.v1.ThinkingTagPattern': $2.ThinkingTagPattern$json,
  '.runanywhere.v1.ModelInfoMetadata': $0.ModelInfoMetadata$json,
  '.runanywhere.v1.SingleFileArtifact': $0.SingleFileArtifact$json,
  '.runanywhere.v1.ExpectedModelFiles': $0.ExpectedModelFiles$json,
  '.runanywhere.v1.ArchiveArtifact': $0.ArchiveArtifact$json,
  '.runanywhere.v1.MultiFileArtifact': $0.MultiFileArtifact$json,
  '.runanywhere.v1.ModelRuntimeCompatibility': $0.ModelRuntimeCompatibility$json,
  '.runanywhere.v1.ComponentLifecycleSnapshotRequest': $1.ComponentLifecycleSnapshotRequest$json,
  '.runanywhere.v1.ComponentLifecycleSnapshotResult': $1.ComponentLifecycleSnapshotResult$json,
  '.runanywhere.v1.ComponentLifecycleSnapshot': $1.ComponentLifecycleSnapshot$json,
};

/// Descriptor for `Lifecycle`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List lifecycleServiceDescriptor = $convert.base64Decode(
    'CglMaWZlY3ljbGUSSQoETG9hZBIgLnJ1bmFueXdoZXJlLnYxLk1vZGVsTG9hZFJlcXVlc3QaHy'
    '5ydW5hbnl3aGVyZS52MS5Nb2RlbExvYWRSZXN1bHQSTwoGVW5sb2FkEiIucnVuYW55d2hlcmUu'
    'djEuTW9kZWxVbmxvYWRSZXF1ZXN0GiEucnVuYW55d2hlcmUudjEuTW9kZWxVbmxvYWRSZXN1bH'
    'QSUgoHQ3VycmVudBIjLnJ1bmFueXdoZXJlLnYxLkN1cnJlbnRNb2RlbFJlcXVlc3QaIi5ydW5h'
    'bnl3aGVyZS52MS5DdXJyZW50TW9kZWxSZXN1bHQSbwoIU25hcHNob3QSMS5ydW5hbnl3aGVyZS'
    '52MS5Db21wb25lbnRMaWZlY3ljbGVTbmFwc2hvdFJlcXVlc3QaMC5ydW5hbnl3aGVyZS52MS5D'
    'b21wb25lbnRMaWZlY3ljbGVTbmFwc2hvdFJlc3VsdA==');

