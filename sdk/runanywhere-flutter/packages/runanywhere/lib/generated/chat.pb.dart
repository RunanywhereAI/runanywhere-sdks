//
//  Generated code. Do not modify.
//  source: chat.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'chat.pbenum.dart';
import 'tool_calling.pb.dart' as $2;

export 'chat.pbenum.dart';

/// ---------------------------------------------------------------------------
/// A single message in a chat conversation.
/// ---------------------------------------------------------------------------
class ChatMessage extends $pb.GeneratedMessage {
  factory ChatMessage({
    $core.String? id,
    MessageRole? role,
    $core.String? content,
    $fixnum.Int64? timestampUs,
    $core.String? name,
    $core.Iterable<$core.String>? toolCallsJson,
    $core.String? toolCallId,
    $core.Iterable<$2.ToolCall>? toolCalls,
    $2.ToolResult? toolResult,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (role != null) {
      $result.role = role;
    }
    if (content != null) {
      $result.content = content;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
    }
    if (name != null) {
      $result.name = name;
    }
    if (toolCallsJson != null) {
      $result.toolCallsJson.addAll(toolCallsJson);
    }
    if (toolCallId != null) {
      $result.toolCallId = toolCallId;
    }
    if (toolCalls != null) {
      $result.toolCalls.addAll(toolCalls);
    }
    if (toolResult != null) {
      $result.toolResult = toolResult;
    }
    return $result;
  }
  ChatMessage._() : super();
  factory ChatMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..e<MessageRole>(2, _omitFieldNames ? '' : 'role', $pb.PbFieldType.OE, defaultOrMaker: MessageRole.MESSAGE_ROLE_UNSPECIFIED, valueOf: MessageRole.valueOf, enumValues: MessageRole.values)
    ..aOS(3, _omitFieldNames ? '' : 'content')
    ..aInt64(4, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(5, _omitFieldNames ? '' : 'name')
    ..pPS(6, _omitFieldNames ? '' : 'toolCallsJson')
    ..aOS(7, _omitFieldNames ? '' : 'toolCallId')
    ..pc<$2.ToolCall>(8, _omitFieldNames ? '' : 'toolCalls', $pb.PbFieldType.PM, subBuilder: $2.ToolCall.create)
    ..aOM<$2.ToolResult>(9, _omitFieldNames ? '' : 'toolResult', subBuilder: $2.ToolResult.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatMessage clone() => ChatMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatMessage copyWith(void Function(ChatMessage) updates) => super.copyWith((message) => updates(message as ChatMessage)) as ChatMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatMessage create() => ChatMessage._();
  ChatMessage createEmptyInstance() => create();
  static $pb.PbList<ChatMessage> createRepeated() => $pb.PbList<ChatMessage>();
  @$core.pragma('dart2js:noInline')
  static ChatMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatMessage>(create);
  static ChatMessage? _defaultInstance;

  /// Unique identifier for the message (caller-supplied or generated).
  /// Empty = unset (proto3 scalar default).
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  /// Role (user / assistant / system / tool).
  @$pb.TagNumber(2)
  MessageRole get role => $_getN(1);
  @$pb.TagNumber(2)
  set role(MessageRole v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasRole() => $_has(1);
  @$pb.TagNumber(2)
  void clearRole() => clearField(2);

  /// Message text content. May be empty for messages that only carry tool
  /// calls (assistant role) or tool results (tool role).
  @$pb.TagNumber(3)
  $core.String get content => $_getSZ(2);
  @$pb.TagNumber(3)
  set content($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasContent() => $_has(2);
  @$pb.TagNumber(3)
  void clearContent() => clearField(3);

  /// Wall-clock timestamp the message was authored, in microseconds since
  /// Unix epoch. 0 = unset; consumers may stamp at receive-time.
  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampUs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampUs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTimestampUs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimestampUs() => clearField(4);

  /// Optional human-readable display name. Used by some chat UIs to
  /// distinguish multiple users in a multi-party conversation.
  @$pb.TagNumber(5)
  $core.String get name => $_getSZ(4);
  @$pb.TagNumber(5)
  set name($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasName() => $_has(4);
  @$pb.TagNumber(5)
  void clearName() => clearField(5);

  /// Optional tool calls embedded in this assistant message. Each entry is
  /// a JSON-encoded ToolCall (see tool_calling.proto) — kept as a string
  /// here to avoid a circular import; consumers parse on demand.
  @$pb.TagNumber(6)
  $core.List<$core.String> get toolCallsJson => $_getList(5);

  /// Optional tool-call ID this message is responding to (only set when
  /// role == MESSAGE_ROLE_TOOL).
  @$pb.TagNumber(7)
  $core.String get toolCallId => $_getSZ(6);
  @$pb.TagNumber(7)
  set toolCallId($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasToolCallId() => $_has(6);
  @$pb.TagNumber(7)
  void clearToolCallId() => clearField(7);

  /// Typed tool calls embedded in this assistant message. Supersedes
  /// tool_calls_json for generated-proto callers while keeping the legacy
  /// JSON string list available.
  @$pb.TagNumber(8)
  $core.List<$2.ToolCall> get toolCalls => $_getList(7);

  /// Typed tool result carried by role == MESSAGE_ROLE_TOOL messages.
  @$pb.TagNumber(9)
  $2.ToolResult get toolResult => $_getN(8);
  @$pb.TagNumber(9)
  set toolResult($2.ToolResult v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasToolResult() => $_has(8);
  @$pb.TagNumber(9)
  void clearToolResult() => clearField(9);
  @$pb.TagNumber(9)
  $2.ToolResult ensureToolResult() => $_ensure(8);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
