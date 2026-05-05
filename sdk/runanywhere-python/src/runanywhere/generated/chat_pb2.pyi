import tool_calling_pb2 as _tool_calling_pb2
import llm_options_pb2 as _llm_options_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class MessageRole(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MESSAGE_ROLE_UNSPECIFIED: _ClassVar[MessageRole]
    MESSAGE_ROLE_USER: _ClassVar[MessageRole]
    MESSAGE_ROLE_ASSISTANT: _ClassVar[MessageRole]
    MESSAGE_ROLE_SYSTEM: _ClassVar[MessageRole]
    MESSAGE_ROLE_TOOL: _ClassVar[MessageRole]
    MESSAGE_ROLE_DEVELOPER: _ClassVar[MessageRole]

class ChatMessageStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CHAT_MESSAGE_STATUS_UNSPECIFIED: _ClassVar[ChatMessageStatus]
    CHAT_MESSAGE_STATUS_PENDING: _ClassVar[ChatMessageStatus]
    CHAT_MESSAGE_STATUS_STREAMING: _ClassVar[ChatMessageStatus]
    CHAT_MESSAGE_STATUS_COMPLETE: _ClassVar[ChatMessageStatus]
    CHAT_MESSAGE_STATUS_FAILED: _ClassVar[ChatMessageStatus]
    CHAT_MESSAGE_STATUS_CANCELLED: _ClassVar[ChatMessageStatus]

class ChatStreamEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CHAT_STREAM_EVENT_KIND_UNSPECIFIED: _ClassVar[ChatStreamEventKind]
    CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED: _ClassVar[ChatStreamEventKind]
    CHAT_STREAM_EVENT_KIND_TOKEN: _ClassVar[ChatStreamEventKind]
    CHAT_STREAM_EVENT_KIND_TOOL_CALL: _ClassVar[ChatStreamEventKind]
    CHAT_STREAM_EVENT_KIND_TOOL_RESULT: _ClassVar[ChatStreamEventKind]
    CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED: _ClassVar[ChatStreamEventKind]
    CHAT_STREAM_EVENT_KIND_ERROR: _ClassVar[ChatStreamEventKind]
MESSAGE_ROLE_UNSPECIFIED: MessageRole
MESSAGE_ROLE_USER: MessageRole
MESSAGE_ROLE_ASSISTANT: MessageRole
MESSAGE_ROLE_SYSTEM: MessageRole
MESSAGE_ROLE_TOOL: MessageRole
MESSAGE_ROLE_DEVELOPER: MessageRole
CHAT_MESSAGE_STATUS_UNSPECIFIED: ChatMessageStatus
CHAT_MESSAGE_STATUS_PENDING: ChatMessageStatus
CHAT_MESSAGE_STATUS_STREAMING: ChatMessageStatus
CHAT_MESSAGE_STATUS_COMPLETE: ChatMessageStatus
CHAT_MESSAGE_STATUS_FAILED: ChatMessageStatus
CHAT_MESSAGE_STATUS_CANCELLED: ChatMessageStatus
CHAT_STREAM_EVENT_KIND_UNSPECIFIED: ChatStreamEventKind
CHAT_STREAM_EVENT_KIND_MESSAGE_STARTED: ChatStreamEventKind
CHAT_STREAM_EVENT_KIND_TOKEN: ChatStreamEventKind
CHAT_STREAM_EVENT_KIND_TOOL_CALL: ChatStreamEventKind
CHAT_STREAM_EVENT_KIND_TOOL_RESULT: ChatStreamEventKind
CHAT_STREAM_EVENT_KIND_MESSAGE_COMPLETED: ChatStreamEventKind
CHAT_STREAM_EVENT_KIND_ERROR: ChatStreamEventKind

class ChatAttachment(_message.Message):
    __slots__ = ("id", "media_type", "data", "uri", "adapter_handle", "name", "size_bytes", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    ID_FIELD_NUMBER: _ClassVar[int]
    MEDIA_TYPE_FIELD_NUMBER: _ClassVar[int]
    DATA_FIELD_NUMBER: _ClassVar[int]
    URI_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_HANDLE_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    id: str
    media_type: str
    data: bytes
    uri: str
    adapter_handle: str
    name: str
    size_bytes: int
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, id: _Optional[str] = ..., media_type: _Optional[str] = ..., data: _Optional[bytes] = ..., uri: _Optional[str] = ..., adapter_handle: _Optional[str] = ..., name: _Optional[str] = ..., size_bytes: _Optional[int] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class ChatMessage(_message.Message):
    __slots__ = ("id", "role", "content", "timestamp_us", "name", "tool_calls_json", "tool_call_id", "tool_calls", "tool_result", "parent_id", "status", "error_message", "metadata", "attachments")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    ID_FIELD_NUMBER: _ClassVar[int]
    ROLE_FIELD_NUMBER: _ClassVar[int]
    CONTENT_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLS_JSON_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALL_ID_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLS_FIELD_NUMBER: _ClassVar[int]
    TOOL_RESULT_FIELD_NUMBER: _ClassVar[int]
    PARENT_ID_FIELD_NUMBER: _ClassVar[int]
    STATUS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    ATTACHMENTS_FIELD_NUMBER: _ClassVar[int]
    id: str
    role: MessageRole
    content: str
    timestamp_us: int
    name: str
    tool_calls_json: _containers.RepeatedScalarFieldContainer[str]
    tool_call_id: str
    tool_calls: _containers.RepeatedCompositeFieldContainer[_tool_calling_pb2.ToolCall]
    tool_result: _tool_calling_pb2.ToolResult
    parent_id: str
    status: ChatMessageStatus
    error_message: str
    metadata: _containers.ScalarMap[str, str]
    attachments: _containers.RepeatedCompositeFieldContainer[ChatAttachment]
    def __init__(self, id: _Optional[str] = ..., role: _Optional[_Union[MessageRole, str]] = ..., content: _Optional[str] = ..., timestamp_us: _Optional[int] = ..., name: _Optional[str] = ..., tool_calls_json: _Optional[_Iterable[str]] = ..., tool_call_id: _Optional[str] = ..., tool_calls: _Optional[_Iterable[_Union[_tool_calling_pb2.ToolCall, _Mapping]]] = ..., tool_result: _Optional[_Union[_tool_calling_pb2.ToolResult, _Mapping]] = ..., parent_id: _Optional[str] = ..., status: _Optional[_Union[ChatMessageStatus, str]] = ..., error_message: _Optional[str] = ..., metadata: _Optional[_Mapping[str, str]] = ..., attachments: _Optional[_Iterable[_Union[ChatAttachment, _Mapping]]] = ...) -> None: ...

class ChatGenerationRequest(_message.Message):
    __slots__ = ("request_id", "conversation_id", "messages", "options", "tool_calling", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    MESSAGES_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLING_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    conversation_id: str
    messages: _containers.RepeatedCompositeFieldContainer[ChatMessage]
    options: _llm_options_pb2.LLMGenerationOptions
    tool_calling: _tool_calling_pb2.ToolCallingOptions
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, request_id: _Optional[str] = ..., conversation_id: _Optional[str] = ..., messages: _Optional[_Iterable[_Union[ChatMessage, _Mapping]]] = ..., options: _Optional[_Union[_llm_options_pb2.LLMGenerationOptions, _Mapping]] = ..., tool_calling: _Optional[_Union[_tool_calling_pb2.ToolCallingOptions, _Mapping]] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class ChatGenerationResult(_message.Message):
    __slots__ = ("conversation_id", "message", "generation", "tool_calls", "tool_results", "error_message", "error_code")
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_FIELD_NUMBER: _ClassVar[int]
    GENERATION_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLS_FIELD_NUMBER: _ClassVar[int]
    TOOL_RESULTS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    conversation_id: str
    message: ChatMessage
    generation: _llm_options_pb2.LLMGenerationResult
    tool_calls: _containers.RepeatedCompositeFieldContainer[_tool_calling_pb2.ToolCall]
    tool_results: _containers.RepeatedCompositeFieldContainer[_tool_calling_pb2.ToolResult]
    error_message: str
    error_code: int
    def __init__(self, conversation_id: _Optional[str] = ..., message: _Optional[_Union[ChatMessage, _Mapping]] = ..., generation: _Optional[_Union[_llm_options_pb2.LLMGenerationResult, _Mapping]] = ..., tool_calls: _Optional[_Iterable[_Union[_tool_calling_pb2.ToolCall, _Mapping]]] = ..., tool_results: _Optional[_Iterable[_Union[_tool_calling_pb2.ToolResult, _Mapping]]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class ChatStreamEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "request_id", "conversation_id", "kind", "token", "message", "tool_call", "tool_result", "final_result", "error_message", "error_code")
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    TOKEN_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALL_FIELD_NUMBER: _ClassVar[int]
    TOOL_RESULT_FIELD_NUMBER: _ClassVar[int]
    FINAL_RESULT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    request_id: str
    conversation_id: str
    kind: ChatStreamEventKind
    token: str
    message: ChatMessage
    tool_call: _tool_calling_pb2.ToolCall
    tool_result: _tool_calling_pb2.ToolResult
    final_result: _llm_options_pb2.LLMGenerationResult
    error_message: str
    error_code: int
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., request_id: _Optional[str] = ..., conversation_id: _Optional[str] = ..., kind: _Optional[_Union[ChatStreamEventKind, str]] = ..., token: _Optional[str] = ..., message: _Optional[_Union[ChatMessage, _Mapping]] = ..., tool_call: _Optional[_Union[_tool_calling_pb2.ToolCall, _Mapping]] = ..., tool_result: _Optional[_Union[_tool_calling_pb2.ToolResult, _Mapping]] = ..., final_result: _Optional[_Union[_llm_options_pb2.LLMGenerationResult, _Mapping]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class ChatConversationState(_message.Message):
    __slots__ = ("conversation_id", "messages", "created_at_ms", "updated_at_ms", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    MESSAGES_FIELD_NUMBER: _ClassVar[int]
    CREATED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    UPDATED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    conversation_id: str
    messages: _containers.RepeatedCompositeFieldContainer[ChatMessage]
    created_at_ms: int
    updated_at_ms: int
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, conversation_id: _Optional[str] = ..., messages: _Optional[_Iterable[_Union[ChatMessage, _Mapping]]] = ..., created_at_ms: _Optional[int] = ..., updated_at_ms: _Optional[int] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...
