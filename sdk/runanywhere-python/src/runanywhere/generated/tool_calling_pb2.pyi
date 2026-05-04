from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class ToolParameterType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    TOOL_PARAMETER_TYPE_UNSPECIFIED: _ClassVar[ToolParameterType]
    TOOL_PARAMETER_TYPE_STRING: _ClassVar[ToolParameterType]
    TOOL_PARAMETER_TYPE_NUMBER: _ClassVar[ToolParameterType]
    TOOL_PARAMETER_TYPE_BOOLEAN: _ClassVar[ToolParameterType]
    TOOL_PARAMETER_TYPE_OBJECT: _ClassVar[ToolParameterType]
    TOOL_PARAMETER_TYPE_ARRAY: _ClassVar[ToolParameterType]

class ToolCallFormatName(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    TOOL_CALL_FORMAT_NAME_UNSPECIFIED: _ClassVar[ToolCallFormatName]
    TOOL_CALL_FORMAT_NAME_JSON: _ClassVar[ToolCallFormatName]
    TOOL_CALL_FORMAT_NAME_XML: _ClassVar[ToolCallFormatName]
    TOOL_CALL_FORMAT_NAME_NATIVE: _ClassVar[ToolCallFormatName]
    TOOL_CALL_FORMAT_NAME_PYTHONIC: _ClassVar[ToolCallFormatName]
    TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS: _ClassVar[ToolCallFormatName]
    TOOL_CALL_FORMAT_NAME_HERMES: _ClassVar[ToolCallFormatName]
TOOL_PARAMETER_TYPE_UNSPECIFIED: ToolParameterType
TOOL_PARAMETER_TYPE_STRING: ToolParameterType
TOOL_PARAMETER_TYPE_NUMBER: ToolParameterType
TOOL_PARAMETER_TYPE_BOOLEAN: ToolParameterType
TOOL_PARAMETER_TYPE_OBJECT: ToolParameterType
TOOL_PARAMETER_TYPE_ARRAY: ToolParameterType
TOOL_CALL_FORMAT_NAME_UNSPECIFIED: ToolCallFormatName
TOOL_CALL_FORMAT_NAME_JSON: ToolCallFormatName
TOOL_CALL_FORMAT_NAME_XML: ToolCallFormatName
TOOL_CALL_FORMAT_NAME_NATIVE: ToolCallFormatName
TOOL_CALL_FORMAT_NAME_PYTHONIC: ToolCallFormatName
TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS: ToolCallFormatName
TOOL_CALL_FORMAT_NAME_HERMES: ToolCallFormatName

class ToolValue(_message.Message):
    __slots__ = ("string_value", "number_value", "bool_value", "array_value", "object_value", "null_value")
    STRING_VALUE_FIELD_NUMBER: _ClassVar[int]
    NUMBER_VALUE_FIELD_NUMBER: _ClassVar[int]
    BOOL_VALUE_FIELD_NUMBER: _ClassVar[int]
    ARRAY_VALUE_FIELD_NUMBER: _ClassVar[int]
    OBJECT_VALUE_FIELD_NUMBER: _ClassVar[int]
    NULL_VALUE_FIELD_NUMBER: _ClassVar[int]
    string_value: str
    number_value: float
    bool_value: bool
    array_value: ToolValueArray
    object_value: ToolValueObject
    null_value: bool
    def __init__(self, string_value: _Optional[str] = ..., number_value: _Optional[float] = ..., bool_value: _Optional[bool] = ..., array_value: _Optional[_Union[ToolValueArray, _Mapping]] = ..., object_value: _Optional[_Union[ToolValueObject, _Mapping]] = ..., null_value: _Optional[bool] = ...) -> None: ...

class ToolValueArray(_message.Message):
    __slots__ = ("values",)
    VALUES_FIELD_NUMBER: _ClassVar[int]
    values: _containers.RepeatedCompositeFieldContainer[ToolValue]
    def __init__(self, values: _Optional[_Iterable[_Union[ToolValue, _Mapping]]] = ...) -> None: ...

class ToolValueObject(_message.Message):
    __slots__ = ("fields",)
    class FieldsEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: ToolValue
        def __init__(self, key: _Optional[str] = ..., value: _Optional[_Union[ToolValue, _Mapping]] = ...) -> None: ...
    FIELDS_FIELD_NUMBER: _ClassVar[int]
    fields: _containers.MessageMap[str, ToolValue]
    def __init__(self, fields: _Optional[_Mapping[str, ToolValue]] = ...) -> None: ...

class ToolParameter(_message.Message):
    __slots__ = ("name", "type", "description", "required", "enum_values")
    NAME_FIELD_NUMBER: _ClassVar[int]
    TYPE_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_FIELD_NUMBER: _ClassVar[int]
    ENUM_VALUES_FIELD_NUMBER: _ClassVar[int]
    name: str
    type: ToolParameterType
    description: str
    required: bool
    enum_values: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, name: _Optional[str] = ..., type: _Optional[_Union[ToolParameterType, str]] = ..., description: _Optional[str] = ..., required: _Optional[bool] = ..., enum_values: _Optional[_Iterable[str]] = ...) -> None: ...

class ToolDefinition(_message.Message):
    __slots__ = ("name", "description", "parameters", "category")
    NAME_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    PARAMETERS_FIELD_NUMBER: _ClassVar[int]
    CATEGORY_FIELD_NUMBER: _ClassVar[int]
    name: str
    description: str
    parameters: _containers.RepeatedCompositeFieldContainer[ToolParameter]
    category: str
    def __init__(self, name: _Optional[str] = ..., description: _Optional[str] = ..., parameters: _Optional[_Iterable[_Union[ToolParameter, _Mapping]]] = ..., category: _Optional[str] = ...) -> None: ...

class ToolCall(_message.Message):
    __slots__ = ("id", "name", "arguments_json", "type", "arguments", "call_id")
    class ArgumentsEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: ToolValue
        def __init__(self, key: _Optional[str] = ..., value: _Optional[_Union[ToolValue, _Mapping]] = ...) -> None: ...
    ID_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    ARGUMENTS_JSON_FIELD_NUMBER: _ClassVar[int]
    TYPE_FIELD_NUMBER: _ClassVar[int]
    ARGUMENTS_FIELD_NUMBER: _ClassVar[int]
    CALL_ID_FIELD_NUMBER: _ClassVar[int]
    id: str
    name: str
    arguments_json: str
    type: str
    arguments: _containers.MessageMap[str, ToolValue]
    call_id: str
    def __init__(self, id: _Optional[str] = ..., name: _Optional[str] = ..., arguments_json: _Optional[str] = ..., type: _Optional[str] = ..., arguments: _Optional[_Mapping[str, ToolValue]] = ..., call_id: _Optional[str] = ...) -> None: ...

class ToolResult(_message.Message):
    __slots__ = ("tool_call_id", "name", "result_json", "error", "success", "result", "call_id")
    class ResultEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: ToolValue
        def __init__(self, key: _Optional[str] = ..., value: _Optional[_Union[ToolValue, _Mapping]] = ...) -> None: ...
    TOOL_CALL_ID_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    RESULT_JSON_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    CALL_ID_FIELD_NUMBER: _ClassVar[int]
    tool_call_id: str
    name: str
    result_json: str
    error: str
    success: bool
    result: _containers.MessageMap[str, ToolValue]
    call_id: str
    def __init__(self, tool_call_id: _Optional[str] = ..., name: _Optional[str] = ..., result_json: _Optional[str] = ..., error: _Optional[str] = ..., success: _Optional[bool] = ..., result: _Optional[_Mapping[str, ToolValue]] = ..., call_id: _Optional[str] = ...) -> None: ...

class ToolCallingOptions(_message.Message):
    __slots__ = ("tools", "max_iterations", "auto_execute", "temperature", "max_tokens", "system_prompt", "replace_system_prompt", "keep_tools_available", "format_hint", "format", "custom_system_prompt", "max_tool_calls")
    TOOLS_FIELD_NUMBER: _ClassVar[int]
    MAX_ITERATIONS_FIELD_NUMBER: _ClassVar[int]
    AUTO_EXECUTE_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    REPLACE_SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    KEEP_TOOLS_AVAILABLE_FIELD_NUMBER: _ClassVar[int]
    FORMAT_HINT_FIELD_NUMBER: _ClassVar[int]
    FORMAT_FIELD_NUMBER: _ClassVar[int]
    CUSTOM_SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    MAX_TOOL_CALLS_FIELD_NUMBER: _ClassVar[int]
    tools: _containers.RepeatedCompositeFieldContainer[ToolDefinition]
    max_iterations: int
    auto_execute: bool
    temperature: float
    max_tokens: int
    system_prompt: str
    replace_system_prompt: bool
    keep_tools_available: bool
    format_hint: str
    format: ToolCallFormatName
    custom_system_prompt: str
    max_tool_calls: int
    def __init__(self, tools: _Optional[_Iterable[_Union[ToolDefinition, _Mapping]]] = ..., max_iterations: _Optional[int] = ..., auto_execute: _Optional[bool] = ..., temperature: _Optional[float] = ..., max_tokens: _Optional[int] = ..., system_prompt: _Optional[str] = ..., replace_system_prompt: _Optional[bool] = ..., keep_tools_available: _Optional[bool] = ..., format_hint: _Optional[str] = ..., format: _Optional[_Union[ToolCallFormatName, str]] = ..., custom_system_prompt: _Optional[str] = ..., max_tool_calls: _Optional[int] = ...) -> None: ...

class ToolCallingResult(_message.Message):
    __slots__ = ("text", "tool_calls", "tool_results", "is_complete", "conversation_id", "iterations_used")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLS_FIELD_NUMBER: _ClassVar[int]
    TOOL_RESULTS_FIELD_NUMBER: _ClassVar[int]
    IS_COMPLETE_FIELD_NUMBER: _ClassVar[int]
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    ITERATIONS_USED_FIELD_NUMBER: _ClassVar[int]
    text: str
    tool_calls: _containers.RepeatedCompositeFieldContainer[ToolCall]
    tool_results: _containers.RepeatedCompositeFieldContainer[ToolResult]
    is_complete: bool
    conversation_id: str
    iterations_used: int
    def __init__(self, text: _Optional[str] = ..., tool_calls: _Optional[_Iterable[_Union[ToolCall, _Mapping]]] = ..., tool_results: _Optional[_Iterable[_Union[ToolResult, _Mapping]]] = ..., is_complete: _Optional[bool] = ..., conversation_id: _Optional[str] = ..., iterations_used: _Optional[int] = ...) -> None: ...
