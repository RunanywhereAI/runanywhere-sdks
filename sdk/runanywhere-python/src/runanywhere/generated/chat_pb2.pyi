import tool_calling_pb2 as _tool_calling_pb2
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
MESSAGE_ROLE_UNSPECIFIED: MessageRole
MESSAGE_ROLE_USER: MessageRole
MESSAGE_ROLE_ASSISTANT: MessageRole
MESSAGE_ROLE_SYSTEM: MessageRole
MESSAGE_ROLE_TOOL: MessageRole

class ChatMessage(_message.Message):
    __slots__ = ("id", "role", "content", "timestamp_us", "name", "tool_calls_json", "tool_call_id", "tool_calls", "tool_result")
    ID_FIELD_NUMBER: _ClassVar[int]
    ROLE_FIELD_NUMBER: _ClassVar[int]
    CONTENT_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLS_JSON_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALL_ID_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLS_FIELD_NUMBER: _ClassVar[int]
    TOOL_RESULT_FIELD_NUMBER: _ClassVar[int]
    id: str
    role: MessageRole
    content: str
    timestamp_us: int
    name: str
    tool_calls_json: _containers.RepeatedScalarFieldContainer[str]
    tool_call_id: str
    tool_calls: _containers.RepeatedCompositeFieldContainer[_tool_calling_pb2.ToolCall]
    tool_result: _tool_calling_pb2.ToolResult
    def __init__(self, id: _Optional[str] = ..., role: _Optional[_Union[MessageRole, str]] = ..., content: _Optional[str] = ..., timestamp_us: _Optional[int] = ..., name: _Optional[str] = ..., tool_calls_json: _Optional[_Iterable[str]] = ..., tool_call_id: _Optional[str] = ..., tool_calls: _Optional[_Iterable[_Union[_tool_calling_pb2.ToolCall, _Mapping]]] = ..., tool_result: _Optional[_Union[_tool_calling_pb2.ToolResult, _Mapping]] = ...) -> None: ...
