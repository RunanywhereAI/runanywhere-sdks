//
//  Generated code. Do not modify.
//  source: voice_agent_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Empty request type — the voice agent already has its config set via
/// `rac_voice_agent_init()` at handle creation time. The Stream rpc just
/// opens a new event subscription on an existing handle.
class VoiceAgentRequest extends $pb.GeneratedMessage {
  factory VoiceAgentRequest({
    $core.String? eventFilter,
  }) {
    final $result = create();
    if (eventFilter != null) {
      $result.eventFilter = eventFilter;
    }
    return $result;
  }
  VoiceAgentRequest._() : super();
  factory VoiceAgentRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceAgentRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'eventFilter')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentRequest clone() => VoiceAgentRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentRequest copyWith(void Function(VoiceAgentRequest) updates) => super.copyWith((message) => updates(message as VoiceAgentRequest)) as VoiceAgentRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentRequest create() => VoiceAgentRequest._();
  VoiceAgentRequest createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentRequest> createRepeated() => $pb.PbList<VoiceAgentRequest>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentRequest>(create);
  static VoiceAgentRequest? _defaultInstance;

  /// Optional: filter the stream to only certain VoiceEvent.payload arms
  /// (e.g. "user_said,assistant_token"). Empty = all events.
  @$pb.TagNumber(1)
  $core.String get eventFilter => $_getSZ(0);
  @$pb.TagNumber(1)
  set eventFilter($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEventFilter() => $_has(0);
  @$pb.TagNumber(1)
  void clearEventFilter() => clearField(1);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
