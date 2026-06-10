// This is a generated file - do not edit.
//
// Generated from chat.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'chat.pbenum.dart';
import 'llm_options.pb.dart' as $1;
import 'tool_calling.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'chat.pbenum.dart';

enum ChatAttachment_Source { data, uri, adapterHandle, notSet }

class ChatAttachment extends $pb.GeneratedMessage {
  factory ChatAttachment({
    $core.String? id,
    $core.String? mediaType,
    $core.List<$core.int>? data,
    $core.String? uri,
    $core.String? adapterHandle,
    $core.String? name,
    $fixnum.Int64? sizeBytes,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (mediaType != null) result.mediaType = mediaType;
    if (data != null) result.data = data;
    if (uri != null) result.uri = uri;
    if (adapterHandle != null) result.adapterHandle = adapterHandle;
    if (name != null) result.name = name;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  ChatAttachment._();

  factory ChatAttachment.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatAttachment.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ChatAttachment_Source>
      _ChatAttachment_SourceByTag = {
    3: ChatAttachment_Source.data,
    4: ChatAttachment_Source.uri,
    5: ChatAttachment_Source.adapterHandle,
    0: ChatAttachment_Source.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatAttachment',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [3, 4, 5])
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'mediaType')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aOS(4, _omitFieldNames ? '' : 'uri')
    ..aOS(5, _omitFieldNames ? '' : 'adapterHandle')
    ..aOS(6, _omitFieldNames ? '' : 'name')
    ..aInt64(7, _omitFieldNames ? '' : 'sizeBytes')
    ..m<$core.String, $core.String>(8, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'ChatAttachment.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatAttachment clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatAttachment copyWith(void Function(ChatAttachment) updates) =>
      super.copyWith((message) => updates(message as ChatAttachment))
          as ChatAttachment;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatAttachment create() => ChatAttachment._();
  @$core.override
  ChatAttachment createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatAttachment getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatAttachment>(create);
  static ChatAttachment? _defaultInstance;

  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  ChatAttachment_Source whichSource() =>
      _ChatAttachment_SourceByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  void clearSource() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mediaType => $_getSZ(1);
  @$pb.TagNumber(2)
  set mediaType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMediaType() => $_has(1);
  @$pb.TagNumber(2)
  void clearMediaType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get data => $_getN(2);
  @$pb.TagNumber(3)
  set data($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasData() => $_has(2);
  @$pb.TagNumber(3)
  void clearData() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get uri => $_getSZ(3);
  @$pb.TagNumber(4)
  set uri($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUri() => $_has(3);
  @$pb.TagNumber(4)
  void clearUri() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get adapterHandle => $_getSZ(4);
  @$pb.TagNumber(5)
  set adapterHandle($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAdapterHandle() => $_has(4);
  @$pb.TagNumber(5)
  void clearAdapterHandle() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get name => $_getSZ(5);
  @$pb.TagNumber(6)
  set name($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasName() => $_has(5);
  @$pb.TagNumber(6)
  void clearName() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get sizeBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSizeBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearSizeBytes() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(7);
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
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.Iterable<ChatAttachment>? attachments,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (role != null) result.role = role;
    if (content != null) result.content = content;
    if (timestampUs != null) result.timestampUs = timestampUs;
    if (name != null) result.name = name;
    if (toolCallId != null) result.toolCallId = toolCallId;
    if (toolCalls != null) result.toolCalls.addAll(toolCalls);
    if (toolResult != null) result.toolResult = toolResult;
    if (parentId != null) result.parentId = parentId;
    if (status != null) result.status = status;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (metadata != null) result.metadata.addEntries(metadata);
    if (attachments != null) result.attachments.addAll(attachments);
    return result;
  }

  ChatMessage._();

  factory ChatMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aE<MessageRole>(2, _omitFieldNames ? '' : 'role',
        enumValues: MessageRole.values)
    ..aOS(3, _omitFieldNames ? '' : 'content')
    ..aInt64(4, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(5, _omitFieldNames ? '' : 'name')
    ..aOS(7, _omitFieldNames ? '' : 'toolCallId')
    ..pPM<$0.ToolCall>(8, _omitFieldNames ? '' : 'toolCalls',
        subBuilder: $0.ToolCall.create)
    ..aOM<$0.ToolResult>(9, _omitFieldNames ? '' : 'toolResult',
        subBuilder: $0.ToolResult.create)
    ..aOS(10, _omitFieldNames ? '' : 'parentId')
    ..aE<ChatMessageStatus>(11, _omitFieldNames ? '' : 'status',
        enumValues: ChatMessageStatus.values)
    ..aOS(12, _omitFieldNames ? '' : 'errorMessage')
    ..m<$core.String, $core.String>(13, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'ChatMessage.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..pPM<ChatAttachment>(14, _omitFieldNames ? '' : 'attachments',
        subBuilder: ChatAttachment.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatMessage copyWith(void Function(ChatMessage) updates) =>
      super.copyWith((message) => updates(message as ChatMessage))
          as ChatMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatMessage create() => ChatMessage._();
  @$core.override
  ChatMessage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatMessage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatMessage>(create);
  static ChatMessage? _defaultInstance;

  /// Unique identifier for the message (caller-supplied or generated).
  /// Empty = unset (proto3 scalar default).
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  /// Role (user / assistant / system / tool).
  @$pb.TagNumber(2)
  MessageRole get role => $_getN(1);
  @$pb.TagNumber(2)
  set role(MessageRole value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRole() => $_has(1);
  @$pb.TagNumber(2)
  void clearRole() => $_clearField(2);

  /// Message text content. May be empty for messages that only carry tool
  /// calls (assistant role) or tool results (tool role).
  @$pb.TagNumber(3)
  $core.String get content => $_getSZ(2);
  @$pb.TagNumber(3)
  set content($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContent() => $_has(2);
  @$pb.TagNumber(3)
  void clearContent() => $_clearField(3);

  /// Wall-clock timestamp the message was authored, in microseconds since
  /// Unix epoch. 0 = unset; consumers may stamp at receive-time.
  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampUs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampUs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTimestampUs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimestampUs() => $_clearField(4);

  /// Optional human-readable display name. Used by some chat UIs to
  /// distinguish multiple users in a multi-party conversation.
  @$pb.TagNumber(5)
  $core.String get name => $_getSZ(4);
  @$pb.TagNumber(5)
  set name($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasName() => $_has(4);
  @$pb.TagNumber(5)
  void clearName() => $_clearField(5);

  /// Optional tool-call ID this message is responding to (only set when
  /// role == MESSAGE_ROLE_TOOL).
  @$pb.TagNumber(7)
  $core.String get toolCallId => $_getSZ(5);
  @$pb.TagNumber(7)
  set toolCallId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(7)
  $core.bool hasToolCallId() => $_has(5);
  @$pb.TagNumber(7)
  void clearToolCallId() => $_clearField(7);

  /// Typed tool calls embedded in this assistant message.
  @$pb.TagNumber(8)
  $pb.PbList<$0.ToolCall> get toolCalls => $_getList(6);

  /// Typed tool result carried by role == MESSAGE_ROLE_TOOL messages.
  @$pb.TagNumber(9)
  $0.ToolResult get toolResult => $_getN(7);
  @$pb.TagNumber(9)
  set toolResult($0.ToolResult value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasToolResult() => $_has(7);
  @$pb.TagNumber(9)
  void clearToolResult() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.ToolResult ensureToolResult() => $_ensure(7);

  /// Optional threading and delivery metadata.
  @$pb.TagNumber(10)
  $core.String get parentId => $_getSZ(8);
  @$pb.TagNumber(10)
  set parentId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(10)
  $core.bool hasParentId() => $_has(8);
  @$pb.TagNumber(10)
  void clearParentId() => $_clearField(10);

  @$pb.TagNumber(11)
  ChatMessageStatus get status => $_getN(9);
  @$pb.TagNumber(11)
  set status(ChatMessageStatus value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasStatus() => $_has(9);
  @$pb.TagNumber(11)
  void clearStatus() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get errorMessage => $_getSZ(10);
  @$pb.TagNumber(12)
  set errorMessage($core.String value) => $_setString(10, value);
  @$pb.TagNumber(12)
  $core.bool hasErrorMessage() => $_has(10);
  @$pb.TagNumber(12)
  void clearErrorMessage() => $_clearField(12);

  @$pb.TagNumber(13)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(11);

  /// Opaque attachments normalized by platform adapters. Capture, picker,
  /// and permission flows remain native/Web-owned.
  @$pb.TagNumber(14)
  $pb.PbList<ChatAttachment> get attachments => $_getList(12);
}

class ChatGenerationRequest extends $pb.GeneratedMessage {
  factory ChatGenerationRequest({
    $core.String? requestId,
    $core.String? conversationId,
    $core.Iterable<ChatMessage>? messages,
    $1.LLMGenerationOptions? options,
    $0.ToolCallingOptions? toolCalling,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (conversationId != null) result.conversationId = conversationId;
    if (messages != null) result.messages.addAll(messages);
    if (options != null) result.options = options;
    if (toolCalling != null) result.toolCalling = toolCalling;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  ChatGenerationRequest._();

  factory ChatGenerationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatGenerationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatGenerationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'conversationId')
    ..pPM<ChatMessage>(3, _omitFieldNames ? '' : 'messages',
        subBuilder: ChatMessage.create)
    ..aOM<$1.LLMGenerationOptions>(4, _omitFieldNames ? '' : 'options',
        subBuilder: $1.LLMGenerationOptions.create)
    ..aOM<$0.ToolCallingOptions>(5, _omitFieldNames ? '' : 'toolCalling',
        subBuilder: $0.ToolCallingOptions.create)
    ..m<$core.String, $core.String>(6, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'ChatGenerationRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatGenerationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatGenerationRequest copyWith(
          void Function(ChatGenerationRequest) updates) =>
      super.copyWith((message) => updates(message as ChatGenerationRequest))
          as ChatGenerationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatGenerationRequest create() => ChatGenerationRequest._();
  @$core.override
  ChatGenerationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatGenerationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatGenerationRequest>(create);
  static ChatGenerationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get conversationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set conversationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasConversationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearConversationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<ChatMessage> get messages => $_getList(2);

  @$pb.TagNumber(4)
  $1.LLMGenerationOptions get options => $_getN(3);
  @$pb.TagNumber(4)
  set options($1.LLMGenerationOptions value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(4)
  void clearOptions() => $_clearField(4);
  @$pb.TagNumber(4)
  $1.LLMGenerationOptions ensureOptions() => $_ensure(3);

  @$pb.TagNumber(5)
  $0.ToolCallingOptions get toolCalling => $_getN(4);
  @$pb.TagNumber(5)
  set toolCalling($0.ToolCallingOptions value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasToolCalling() => $_has(4);
  @$pb.TagNumber(5)
  void clearToolCalling() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.ToolCallingOptions ensureToolCalling() => $_ensure(4);

  @$pb.TagNumber(6)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(5);
}

class ChatGenerationResult extends $pb.GeneratedMessage {
  factory ChatGenerationResult({
    $core.String? conversationId,
    ChatMessage? message,
    $1.LLMGenerationResult? generation,
    $core.Iterable<$0.ToolCall>? toolCalls,
    $core.Iterable<$0.ToolResult>? toolResults,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (conversationId != null) result.conversationId = conversationId;
    if (message != null) result.message = message;
    if (generation != null) result.generation = generation;
    if (toolCalls != null) result.toolCalls.addAll(toolCalls);
    if (toolResults != null) result.toolResults.addAll(toolResults);
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  ChatGenerationResult._();

  factory ChatGenerationResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatGenerationResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatGenerationResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..aOM<ChatMessage>(2, _omitFieldNames ? '' : 'message',
        subBuilder: ChatMessage.create)
    ..aOM<$1.LLMGenerationResult>(3, _omitFieldNames ? '' : 'generation',
        subBuilder: $1.LLMGenerationResult.create)
    ..pPM<$0.ToolCall>(4, _omitFieldNames ? '' : 'toolCalls',
        subBuilder: $0.ToolCall.create)
    ..pPM<$0.ToolResult>(5, _omitFieldNames ? '' : 'toolResults',
        subBuilder: $0.ToolResult.create)
    ..aOS(6, _omitFieldNames ? '' : 'errorMessage')
    ..aI(7, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatGenerationResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatGenerationResult copyWith(void Function(ChatGenerationResult) updates) =>
      super.copyWith((message) => updates(message as ChatGenerationResult))
          as ChatGenerationResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatGenerationResult create() => ChatGenerationResult._();
  @$core.override
  ChatGenerationResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatGenerationResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatGenerationResult>(create);
  static ChatGenerationResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => $_clearField(1);

  @$pb.TagNumber(2)
  ChatMessage get message => $_getN(1);
  @$pb.TagNumber(2)
  set message(ChatMessage value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);
  @$pb.TagNumber(2)
  ChatMessage ensureMessage() => $_ensure(1);

  @$pb.TagNumber(3)
  $1.LLMGenerationResult get generation => $_getN(2);
  @$pb.TagNumber(3)
  set generation($1.LLMGenerationResult value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasGeneration() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeneration() => $_clearField(3);
  @$pb.TagNumber(3)
  $1.LLMGenerationResult ensureGeneration() => $_ensure(2);

  @$pb.TagNumber(4)
  $pb.PbList<$0.ToolCall> get toolCalls => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<$0.ToolResult> get toolResults => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get errorMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set errorMessage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasErrorMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearErrorMessage() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get errorCode => $_getIZ(6);
  @$pb.TagNumber(7)
  set errorCode($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasErrorCode() => $_has(6);
  @$pb.TagNumber(7)
  void clearErrorCode() => $_clearField(7);
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
    $1.LLMGenerationResult? finalResult,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (seq != null) result.seq = seq;
    if (timestampUs != null) result.timestampUs = timestampUs;
    if (requestId != null) result.requestId = requestId;
    if (conversationId != null) result.conversationId = conversationId;
    if (kind != null) result.kind = kind;
    if (token != null) result.token = token;
    if (message != null) result.message = message;
    if (toolCall != null) result.toolCall = toolCall;
    if (toolResult != null) result.toolResult = toolResult;
    if (finalResult != null) result.finalResult = finalResult;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  ChatStreamEvent._();

  factory ChatStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'requestId')
    ..aOS(4, _omitFieldNames ? '' : 'conversationId')
    ..aE<ChatStreamEventKind>(5, _omitFieldNames ? '' : 'kind',
        enumValues: ChatStreamEventKind.values)
    ..aOS(6, _omitFieldNames ? '' : 'token')
    ..aOM<ChatMessage>(7, _omitFieldNames ? '' : 'message',
        subBuilder: ChatMessage.create)
    ..aOM<$0.ToolCall>(8, _omitFieldNames ? '' : 'toolCall',
        subBuilder: $0.ToolCall.create)
    ..aOM<$0.ToolResult>(9, _omitFieldNames ? '' : 'toolResult',
        subBuilder: $0.ToolResult.create)
    ..aOM<$1.LLMGenerationResult>(10, _omitFieldNames ? '' : 'finalResult',
        subBuilder: $1.LLMGenerationResult.create)
    ..aOS(11, _omitFieldNames ? '' : 'errorMessage')
    ..aI(12, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatStreamEvent copyWith(void Function(ChatStreamEvent) updates) =>
      super.copyWith((message) => updates(message as ChatStreamEvent))
          as ChatStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatStreamEvent create() => ChatStreamEvent._();
  @$core.override
  ChatStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatStreamEvent>(create);
  static ChatStreamEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(3)
  set requestId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRequestId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get conversationId => $_getSZ(3);
  @$pb.TagNumber(4)
  set conversationId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConversationId() => $_has(3);
  @$pb.TagNumber(4)
  void clearConversationId() => $_clearField(4);

  @$pb.TagNumber(5)
  ChatStreamEventKind get kind => $_getN(4);
  @$pb.TagNumber(5)
  set kind(ChatStreamEventKind value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasKind() => $_has(4);
  @$pb.TagNumber(5)
  void clearKind() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get token => $_getSZ(5);
  @$pb.TagNumber(6)
  set token($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasToken() => $_has(5);
  @$pb.TagNumber(6)
  void clearToken() => $_clearField(6);

  @$pb.TagNumber(7)
  ChatMessage get message => $_getN(6);
  @$pb.TagNumber(7)
  set message(ChatMessage value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearMessage() => $_clearField(7);
  @$pb.TagNumber(7)
  ChatMessage ensureMessage() => $_ensure(6);

  @$pb.TagNumber(8)
  $0.ToolCall get toolCall => $_getN(7);
  @$pb.TagNumber(8)
  set toolCall($0.ToolCall value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasToolCall() => $_has(7);
  @$pb.TagNumber(8)
  void clearToolCall() => $_clearField(8);
  @$pb.TagNumber(8)
  $0.ToolCall ensureToolCall() => $_ensure(7);

  @$pb.TagNumber(9)
  $0.ToolResult get toolResult => $_getN(8);
  @$pb.TagNumber(9)
  set toolResult($0.ToolResult value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasToolResult() => $_has(8);
  @$pb.TagNumber(9)
  void clearToolResult() => $_clearField(9);
  @$pb.TagNumber(9)
  $0.ToolResult ensureToolResult() => $_ensure(8);

  @$pb.TagNumber(10)
  $1.LLMGenerationResult get finalResult => $_getN(9);
  @$pb.TagNumber(10)
  set finalResult($1.LLMGenerationResult value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasFinalResult() => $_has(9);
  @$pb.TagNumber(10)
  void clearFinalResult() => $_clearField(10);
  @$pb.TagNumber(10)
  $1.LLMGenerationResult ensureFinalResult() => $_ensure(9);

  @$pb.TagNumber(11)
  $core.String get errorMessage => $_getSZ(10);
  @$pb.TagNumber(11)
  set errorMessage($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasErrorMessage() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorMessage() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get errorCode => $_getIZ(11);
  @$pb.TagNumber(12)
  set errorCode($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasErrorCode() => $_has(11);
  @$pb.TagNumber(12)
  void clearErrorCode() => $_clearField(12);
}

class ChatConversationState extends $pb.GeneratedMessage {
  factory ChatConversationState({
    $core.String? conversationId,
    $core.Iterable<ChatMessage>? messages,
    $fixnum.Int64? createdAtMs,
    $fixnum.Int64? updatedAtMs,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
  }) {
    final result = create();
    if (conversationId != null) result.conversationId = conversationId;
    if (messages != null) result.messages.addAll(messages);
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (updatedAtMs != null) result.updatedAtMs = updatedAtMs;
    if (metadata != null) result.metadata.addEntries(metadata);
    return result;
  }

  ChatConversationState._();

  factory ChatConversationState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChatConversationState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChatConversationState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'conversationId')
    ..pPM<ChatMessage>(2, _omitFieldNames ? '' : 'messages',
        subBuilder: ChatMessage.create)
    ..aInt64(3, _omitFieldNames ? '' : 'createdAtMs')
    ..aInt64(4, _omitFieldNames ? '' : 'updatedAtMs')
    ..m<$core.String, $core.String>(5, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'ChatConversationState.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatConversationState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChatConversationState copyWith(
          void Function(ChatConversationState) updates) =>
      super.copyWith((message) => updates(message as ChatConversationState))
          as ChatConversationState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChatConversationState create() => ChatConversationState._();
  @$core.override
  ChatConversationState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChatConversationState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChatConversationState>(create);
  static ChatConversationState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get conversationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set conversationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasConversationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearConversationId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ChatMessage> get messages => $_getList(1);

  @$pb.TagNumber(3)
  $fixnum.Int64 get createdAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCreatedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreatedAtMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get updatedAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set updatedAtMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUpdatedAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearUpdatedAtMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(4);
}

/// Logical chat service contract. Host conversation state, UI rendering, and
/// backend execution remain adapter-owned; this service describes only the
/// portable Generate / Stream entry points over generated messages.
class ChatApi {
  final $pb.RpcClient _client;

  ChatApi(this._client);

  /// Non-streaming generation: returns the completed assistant message and
  /// optional LLMGenerationResult/ToolCall aggregates in one response.
  $async.Future<ChatGenerationResult> generate(
          $pb.ClientContext? ctx, ChatGenerationRequest request) =>
      _client.invoke<ChatGenerationResult>(
          ctx, 'Chat', 'Generate', request, ChatGenerationResult());

  /// Server-streaming generation: emits per-token, tool-call, tool-result,
  /// and completion events until the turn terminates.
  $async.Future<ChatStreamEvent> stream(
          $pb.ClientContext? ctx, ChatGenerationRequest request) =>
      _client.invoke<ChatStreamEvent>(
          ctx, 'Chat', 'Stream', request, ChatStreamEvent());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
