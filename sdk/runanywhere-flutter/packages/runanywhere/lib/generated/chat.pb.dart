//
//  Generated code. Do not modify.
//  source: chat.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'chat.pbenum.dart';
import 'llm_options.pb.dart' as $5;
import 'tool_calling.pb.dart' as $0;

export 'chat.pbenum.dart';

enum ChatAttachment_Source {
  data, 
  uri, 
  adapterHandle, 
  notSet
}

class ChatAttachment extends $pb.GeneratedMessage {
  factory ChatAttachment({
    $core.String? id,
    $core.String? mediaType,
    $core.List<$core.int>? data,
    $core.String? uri,
    $core.String? adapterHandle,
    $core.String? name,
    $fixnum.Int64? sizeBytes,
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (mediaType != null) {
      $result.mediaType = mediaType;
    }
    if (data != null) {
      $result.data = data;
    }
    if (uri != null) {
      $result.uri = uri;
    }
    if (adapterHandle != null) {
      $result.adapterHandle = adapterHandle;
    }
    if (name != null) {
      $result.name = name;
    }
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    return $result;
  }
  ChatAttachment._() : super();
  factory ChatAttachment.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatAttachment.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, ChatAttachment_Source> _ChatAttachment_SourceByTag = {
    3 : ChatAttachment_Source.data,
    4 : ChatAttachment_Source.uri,
    5 : ChatAttachment_Source.adapterHandle,
    0 : ChatAttachment_Source.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatAttachment', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [3, 4, 5])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'mediaType')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'uri')
    ..aOS(5, _omitFieldNames ? '' : 'adapterHandle')
    ..aOS(6, _omitFieldNames ? '' : 'name')
    ..aInt64(7, _omitFieldNames ? '' : 'sizeBytes')
    ..m<$core.String, $core.String>(8, _omitFieldNames ? '' : 'metadata', entryClassName: 'ChatAttachment.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatAttachment clone() => ChatAttachment()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatAttachment copyWith(void Function(ChatAttachment) updates) => super.copyWith((message) => updates(message as ChatAttachment)) as ChatAttachment;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatAttachment create() => ChatAttachment._();
  ChatAttachment createEmptyInstance() => create();
  static $pb.PbList<ChatAttachment> createRepeated() => $pb.PbList<ChatAttachment>();
  @$core.pragma('dart2js:noInline')
  static ChatAttachment getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatAttachment>(create);
  static ChatAttachment? _defaultInstance;

  ChatAttachment_Source whichSource() => _ChatAttachment_SourceByTag[$_whichOneof(0)]!;
  void clearSource() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get mediaType => $_getSZ(1);
  @$pb.TagNumber(2)
  set mediaType($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMediaType() => $_has(1);
  @$pb.TagNumber(2)
  void clearMediaType() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get data => $_getN(2);
  @$pb.TagNumber(3)
  set data($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasData() => $_has(2);
  @$pb.TagNumber(3)
  void clearData() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get uri => $_getSZ(3);
  @$pb.TagNumber(4)
  set uri($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasUri() => $_has(3);
  @$pb.TagNumber(4)
  void clearUri() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get adapterHandle => $_getSZ(4);
  @$pb.TagNumber(5)
  set adapterHandle($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAdapterHandle() => $_has(4);
  @$pb.TagNumber(5)
  void clearAdapterHandle() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get name => $_getSZ(5);
  @$pb.TagNumber(6)
  set name($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasName() => $_has(5);
  @$pb.TagNumber(6)
  void clearName() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get sizeBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSizeBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearSizeBytes() => clearField(7);

  @$pb.TagNumber(8)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(7);
}

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
    $core.String? toolCallId,
    $core.Iterable<$0.ToolCall>? toolCalls,
    $0.ToolResult? toolResult,
    $core.String? parentId,
    ChatMessageStatus? status,
    $core.String? errorMessage,
    $core.Map<$core.String, $core.String>? metadata,
    $core.Iterable<ChatAttachment>? attachments,
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
    if (toolCallId != null) {
      $result.toolCallId = toolCallId;
    }
    if (toolCalls != null) {
      $result.toolCalls.addAll(toolCalls);
    }
    if (toolResult != null) {
      $result.toolResult = toolResult;
    }
    if (parentId != null) {
      $result.parentId = parentId;
    }
    if (status != null) {
      $result.status = status;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    if (attachments != null) {
      $result.attachments.addAll(attachments);
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
    ..aOS(7, _omitFieldNames ? '' : 'toolCallId')
    ..pc<$0.ToolCall>(8, _omitFieldNames ? '' : 'toolCalls', $pb.PbFieldType.PM, subBuilder: $0.ToolCall.create)
    ..aOM<$0.ToolResult>(9, _omitFieldNames ? '' : 'toolResult', subBuilder: $0.ToolResult.create)
    ..aOS(10, _omitFieldNames ? '' : 'parentId')
    ..e<ChatMessageStatus>(11, _omitFieldNames ? '' : 'status', $pb.PbFieldType.OE, defaultOrMaker: ChatMessageStatus.CHAT_MESSAGE_STATUS_UNSPECIFIED, valueOf: ChatMessageStatus.valueOf, enumValues: ChatMessageStatus.values)
    ..aOS(12, _omitFieldNames ? '' : 'errorMessage')
    ..m<$core.String, $core.String>(13, _omitFieldNames ? '' : 'metadata', entryClassName: 'ChatMessage.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..pc<ChatAttachment>(14, _omitFieldNames ? '' : 'attachments', $pb.PbFieldType.PM, subBuilder: ChatAttachment.create)
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

  /// Optional tool-call ID this message is responding to (only set when
  /// role == MESSAGE_ROLE_TOOL).
  @$pb.TagNumber(7)
  $core.String get toolCallId => $_getSZ(5);
  @$pb.TagNumber(7)
  set toolCallId($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(7)
  $core.bool hasToolCallId() => $_has(5);
  @$pb.TagNumber(7)
  void clearToolCallId() => clearField(7);

  /// Typed tool calls embedded in this assistant message.
  @$pb.TagNumber(8)
  $core.List<$0.ToolCall> get toolCalls => $_getList(6);

  /// Typed tool result carried by role == MESSAGE_ROLE_TOOL messages.
  @$pb.TagNumber(9)
  $0.ToolResult get toolResult => $_getN(7);
  @$pb.TagNumber(9)
  set toolResult($0.ToolResult v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasToolResult() => $_has(7);
  @$pb.TagNumber(9)
  void clearToolResult() => clearField(9);
  @$pb.TagNumber(9)
  $0.ToolResult ensureToolResult() => $_ensure(7);

  /// Optional threading and delivery metadata.
  @$pb.TagNumber(10)
  $core.String get parentId => $_getSZ(8);
  @$pb.TagNumber(10)
  set parentId($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(10)
  $core.bool hasParentId() => $_has(8);
  @$pb.TagNumber(10)
  void clearParentId() => clearField(10);

  @$pb.TagNumber(11)
  ChatMessageStatus get status => $_getN(9);
  @$pb.TagNumber(11)
  set status(ChatMessageStatus v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasStatus() => $_has(9);
  @$pb.TagNumber(11)
  void clearStatus() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get errorMessage => $_getSZ(10);
  @$pb.TagNumber(12)
  set errorMessage($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(12)
  $core.bool hasErrorMessage() => $_has(10);
  @$pb.TagNumber(12)
  void clearErrorMessage() => clearField(12);

  @$pb.TagNumber(13)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(11);

  /// Opaque attachments normalized by platform adapters. Capture, picker,
  /// and permission flows remain native/Web-owned.
  @$pb.TagNumber(14)
  $core.List<ChatAttachment> get attachments => $_getList(12);
}

class ChatGenerationRequest extends $pb.GeneratedMessage {
  factory ChatGenerationRequest({
    $core.String? requestId,
    $core.String? conversationId,
    $core.Iterable<ChatMessage>? messages,
    $5.LLMGenerationOptions? options,
    $0.ToolCallingOptions? toolCalling,
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final $result = create();
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (conversationId != null) {
      $result.conversationId = conversationId;
    }
    if (messages != null) {
      $result.messages.addAll(messages);
    }
    if (options != null) {
      $result.options = options;
    }
    if (toolCalling != null) {
      $result.toolCalling = toolCalling;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    return $result;
  }
  ChatGenerationRequest._() : super();
  factory ChatGenerationRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatGenerationRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatGenerationRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'conversationId')
    ..pc<ChatMessage>(3, _omitFieldNames ? '' : 'messages', $pb.PbFieldType.PM, subBuilder: ChatMessage.create)
    ..aOM<$5.LLMGenerationOptions>(4, _omitFieldNames ? '' : 'options', subBuilder: $5.LLMGenerationOptions.create)
    ..aOM<$0.ToolCallingOptions>(5, _omitFieldNames ? '' : 'toolCalling', subBuilder: $0.ToolCallingOptions.create)
    ..m<$core.String, $core.String>(6, _omitFieldNames ? '' : 'metadata', entryClassName: 'ChatGenerationRequest.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatGenerationRequest clone() => ChatGenerationRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatGenerationRequest copyWith(void Function(ChatGenerationRequest) updates) => super.copyWith((message) => updates(message as ChatGenerationRequest)) as ChatGenerationRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatGenerationRequest create() => ChatGenerationRequest._();
  ChatGenerationRequest createEmptyInstance() => create();
  static $pb.PbList<ChatGenerationRequest> createRepeated() => $pb.PbList<ChatGenerationRequest>();
  @$core.pragma('dart2js:noInline')
  static ChatGenerationRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatGenerationRequest>(create);
  static ChatGenerationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get conversationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set conversationId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasConversationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearConversationId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<ChatMessage> get messages => $_getList(2);

  @$pb.TagNumber(4)
  $5.LLMGenerationOptions get options => $_getN(3);
  @$pb.TagNumber(4)
  set options($5.LLMGenerationOptions v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(4)
  void clearOptions() => clearField(4);
  @$pb.TagNumber(4)
  $5.LLMGenerationOptions ensureOptions() => $_ensure(3);

  @$pb.TagNumber(5)
  $0.ToolCallingOptions get toolCalling => $_getN(4);
  @$pb.TagNumber(5)
  set toolCalling($0.ToolCallingOptions v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasToolCalling() => $_has(4);
  @$pb.TagNumber(5)
  void clearToolCalling() => clearField(5);
  @$pb.TagNumber(5)
  $0.ToolCallingOptions ensureToolCalling() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(5);
}

class ChatGenerationResult extends $pb.GeneratedMessage {
  factory ChatGenerationResult({
    $core.String? conversationId,
    ChatMessage? message,
    $5.LLMGenerationResult? generation,
    $core.Iterable<$0.ToolCall>? toolCalls,
    $core.Iterable<$0.ToolResult>? toolResults,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (conversationId != null) {
      $result.conversationId = conversationId;
    }
    if (message != null) {
      $result.message = message;
    }
    if (generation != null) {
      $result.generation = generation;
    }
    if (toolCalls != null) {
      $result.toolCalls.addAll(toolCalls);
    }
    if (toolResults != null) {
      $result.toolResults.addAll(toolResults);
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  ChatGenerationResult._() : super();
  factory ChatGenerationResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatGenerationResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatGenerationResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..aOM<ChatMessage>(2, _omitFieldNames ? '' : 'message', subBuilder: ChatMessage.create)
    ..aOM<$5.LLMGenerationResult>(3, _omitFieldNames ? '' : 'generation', subBuilder: $5.LLMGenerationResult.create)
    ..pc<$0.ToolCall>(4, _omitFieldNames ? '' : 'toolCalls', $pb.PbFieldType.PM, subBuilder: $0.ToolCall.create)
    ..pc<$0.ToolResult>(5, _omitFieldNames ? '' : 'toolResults', $pb.PbFieldType.PM, subBuilder: $0.ToolResult.create)
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(7, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatGenerationResult clone() => ChatGenerationResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatGenerationResult copyWith(void Function(ChatGenerationResult) updates) => super.copyWith((message) => updates(message as ChatGenerationResult)) as ChatGenerationResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatGenerationResult create() => ChatGenerationResult._();
  ChatGenerationResult createEmptyInstance() => create();
  static $pb.PbList<ChatGenerationResult> createRepeated() => $pb.PbList<ChatGenerationResult>();
  @$core.pragma('dart2js:noInline')
  static ChatGenerationResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatGenerationResult>(create);
  static ChatGenerationResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => clearField(1);

  @$pb.TagNumber(2)
  ChatMessage get message => $_getN(1);
  @$pb.TagNumber(2)
  set message(ChatMessage v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => clearField(2);
  @$pb.TagNumber(2)
  ChatMessage ensureMessage() => $_ensure(1);

  @$pb.TagNumber(3)
  $5.LLMGenerationResult get generation => $_getN(2);
  @$pb.TagNumber(3)
  set generation($5.LLMGenerationResult v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasGeneration() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeneration() => clearField(3);
  @$pb.TagNumber(3)
  $5.LLMGenerationResult ensureGeneration() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.List<$0.ToolCall> get toolCalls => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<$0.ToolResult> get toolResults => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get errorCode => $_getIZ(6);
  @$pb.TagNumber(7)
  set errorCode($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasErrorCode() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorCode() => clearField(7);
}

class ChatStreamEvent extends $pb.GeneratedMessage {
  factory ChatStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? requestId,
    $core.String? conversationId,
    ChatStreamEventKind? kind,
    $core.String? token,
    ChatMessage? message,
    $0.ToolCall? toolCall,
    $0.ToolResult? toolResult,
    $5.LLMGenerationResult? finalResult,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (seq != null) {
      $result.seq = seq;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
    }
    if (requestId != null) {
      $result.requestId = requestId;
    }
    if (conversationId != null) {
      $result.conversationId = conversationId;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (token != null) {
      $result.token = token;
    }
    if (message != null) {
      $result.message = message;
    }
    if (toolCall != null) {
      $result.toolCall = toolCall;
    }
    if (toolResult != null) {
      $result.toolResult = toolResult;
    }
    if (finalResult != null) {
      $result.finalResult = finalResult;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  ChatStreamEvent._() : super();
  factory ChatStreamEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatStreamEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatStreamEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aOS(4, _omitFieldNames ? '' : 'conversationId')
    ..e<ChatStreamEventKind>(5, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: ChatStreamEventKind.CHAT_STREAM_EVENT_KIND_UNSPECIFIED, valueOf: ChatStreamEventKind.valueOf, enumValues: ChatStreamEventKind.values)
    ..aOS(6, _omitFieldNames ? '' : 'token')
    ..aOM<ChatMessage>(7, _omitFieldNames ? '' : 'message', subBuilder: ChatMessage.create)
    ..aOM<$0.ToolCall>(8, _omitFieldNames ? '' : 'toolCall', subBuilder: $0.ToolCall.create)
    ..aOM<$0.ToolResult>(9, _omitFieldNames ? '' : 'toolResult', subBuilder: $0.ToolResult.create)
    ..aOM<$5.LLMGenerationResult>(10, _omitFieldNames ? '' : 'finalResult', subBuilder: $5.LLMGenerationResult.create)
    ..aOS(11, _omitFieldNames ? '' : 'errorMessage')
    ..a<$core.int>(12, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatStreamEvent clone() => ChatStreamEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatStreamEvent copyWith(void Function(ChatStreamEvent) updates) => super.copyWith((message) => updates(message as ChatStreamEvent)) as ChatStreamEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatStreamEvent create() => ChatStreamEvent._();
  ChatStreamEvent createEmptyInstance() => create();
  static $pb.PbList<ChatStreamEvent> createRepeated() => $pb.PbList<ChatStreamEvent>();
  @$core.pragma('dart2js:noInline')
  static ChatStreamEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatStreamEvent>(create);
  static ChatStreamEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get conversationId => $_getSZ(3);
  @$pb.TagNumber(4)
  set conversationId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasConversationId() => $_has(3);
  @$pb.TagNumber(4)
  void clearConversationId() => clearField(4);

  @$pb.TagNumber(5)
  ChatStreamEventKind get kind => $_getN(4);
  @$pb.TagNumber(5)
  set kind(ChatStreamEventKind v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasKind() => $_has(4);
  @$pb.TagNumber(5)
  void clearKind() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get token => $_getSZ(5);
  @$pb.TagNumber(6)
  set token($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasToken() => $_has(5);
  @$pb.TagNumber(6)
  void clearToken() => clearField(6);

  @$pb.TagNumber(7)
  ChatMessage get message => $_getN(6);
  @$pb.TagNumber(7)
  set message(ChatMessage v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearMessage() => clearField(7);
  @$pb.TagNumber(7)
  ChatMessage ensureMessage() => $_ensure(6);

  @$pb.TagNumber(8)
  $0.ToolCall get toolCall => $_getN(7);
  @$pb.TagNumber(8)
  set toolCall($0.ToolCall v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasToolCall() => $_has(7);
  @$pb.TagNumber(8)
  void clearToolCall() => clearField(8);
  @$pb.TagNumber(8)
  $0.ToolCall ensureToolCall() => $_ensure(7);

  @$pb.TagNumber(9)
  $0.ToolResult get toolResult => $_getN(8);
  @$pb.TagNumber(9)
  set toolResult($0.ToolResult v) { setField(9, v); }
  @$pb.TagNumber(9)
  $core.bool hasToolResult() => $_has(8);
  @$pb.TagNumber(9)
  void clearToolResult() => clearField(9);
  @$pb.TagNumber(9)
  $0.ToolResult ensureToolResult() => $_ensure(8);

  @$pb.TagNumber(10)
  $5.LLMGenerationResult get finalResult => $_getN(9);
  @$pb.TagNumber(10)
  set finalResult($5.LLMGenerationResult v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasFinalResult() => $_has(9);
  @$pb.TagNumber(10)
  void clearFinalResult() => clearField(10);
  @$pb.TagNumber(10)
  $5.LLMGenerationResult ensureFinalResult() => $_ensure(9);

  @$pb.TagNumber(11)
  $core.String get errorMessage => $_getSZ(10);
  @$pb.TagNumber(11)
  set errorMessage($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasErrorMessage() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorMessage() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get errorCode => $_getIZ(11);
  @$pb.TagNumber(12)
  set errorCode($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasErrorCode() => $_has(11);
  @$pb.TagNumber(12)
  void clearErrorCode() => clearField(12);
}

class ChatConversationState extends $pb.GeneratedMessage {
  factory ChatConversationState({
    $core.String? conversationId,
    $core.Iterable<ChatMessage>? messages,
    $fixnum.Int64? createdAtMs,
    $fixnum.Int64? updatedAtMs,
    $core.Map<$core.String, $core.String>? metadata,
  }) {
    final $result = create();
    if (conversationId != null) {
      $result.conversationId = conversationId;
    }
    if (messages != null) {
      $result.messages.addAll(messages);
    }
    if (createdAtMs != null) {
      $result.createdAtMs = createdAtMs;
    }
    if (updatedAtMs != null) {
      $result.updatedAtMs = updatedAtMs;
    }
    if (metadata != null) {
      $result.metadata.addAll(metadata);
    }
    return $result;
  }
  ChatConversationState._() : super();
  factory ChatConversationState.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ChatConversationState.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ChatConversationState', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..pc<ChatMessage>(2, _omitFieldNames ? '' : 'messages', $pb.PbFieldType.PM, subBuilder: ChatMessage.create)
    ..aInt64(3, _omitFieldNames ? '' : 'createdAtMs')
    ..aInt64(4, _omitFieldNames ? '' : 'updatedAtMs')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata', entryClassName: 'ChatConversationState.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ChatConversationState clone() => ChatConversationState()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ChatConversationState copyWith(void Function(ChatConversationState) updates) => super.copyWith((message) => updates(message as ChatConversationState)) as ChatConversationState;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatConversationState create() => ChatConversationState._();
  ChatConversationState createEmptyInstance() => create();
  static $pb.PbList<ChatConversationState> createRepeated() => $pb.PbList<ChatConversationState>();
  @$core.pragma('dart2js:noInline')
  static ChatConversationState getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChatConversationState>(create);
  static ChatConversationState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<ChatMessage> get messages => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get createdAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set createdAtMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCreatedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreatedAtMs() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get updatedAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set updatedAtMs($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasUpdatedAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearUpdatedAtMs() => clearField(4);

  @$pb.TagNumber(5)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(4);
}

class ChatApi {
  $pb.RpcClient _client;
  ChatApi(this._client);

  $async.Future<ChatGenerationResult> generate($pb.ClientContext? ctx, ChatGenerationRequest request) =>
    _client.invoke<ChatGenerationResult>(ctx, 'Chat', 'Generate', request, ChatGenerationResult())
  ;
  $async.Future<ChatStreamEvent> stream($pb.ClientContext? ctx, ChatGenerationRequest request) =>
    _client.invoke<ChatStreamEvent>(ctx, 'Chat', 'Stream', request, ChatStreamEvent())
  ;
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
