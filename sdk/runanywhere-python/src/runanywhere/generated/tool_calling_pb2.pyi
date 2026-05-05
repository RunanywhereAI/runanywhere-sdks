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

class ToolChoiceMode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    TOOL_CHOICE_MODE_UNSPECIFIED: _ClassVar[ToolChoiceMode]
    TOOL_CHOICE_MODE_AUTO: _ClassVar[ToolChoiceMode]
    TOOL_CHOICE_MODE_NONE: _ClassVar[ToolChoiceMode]
    TOOL_CHOICE_MODE_REQUIRED: _ClassVar[ToolChoiceMode]
    TOOL_CHOICE_MODE_SPECIFIC: _ClassVar[ToolChoiceMode]

class ToolCallingStreamEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    TOOL_CALLING_STREAM_EVENT_KIND_UNSPECIFIED: _ClassVar[ToolCallingStreamEventKind]
    TOOL_CALLING_STREAM_EVENT_KIND_MODEL_TOKEN: _ClassVar[ToolCallingStreamEventKind]
    TOOL_CALLING_STREAM_EVENT_KIND_TOOL_CALL_PARSED: _ClassVar[ToolCallingStreamEventKind]
    TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_STARTED: _ClassVar[ToolCallingStreamEventKind]
    TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_COMPLETED: _ClassVar[ToolCallingStreamEventKind]
    TOOL_CALLING_STREAM_EVENT_KIND_COMPLETED: _ClassVar[ToolCallingStreamEventKind]
    TOOL_CALLING_STREAM_EVENT_KIND_ERROR: _ClassVar[ToolCallingStreamEventKind]
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
TOOL_CHOICE_MODE_UNSPECIFIED: ToolChoiceMode
TOOL_CHOICE_MODE_AUTO: ToolChoiceMode
TOOL_CHOICE_MODE_NONE: ToolChoiceMode
TOOL_CHOICE_MODE_REQUIRED: ToolChoiceMode
TOOL_CHOICE_MODE_SPECIFIC: ToolChoiceMode
TOOL_CALLING_STREAM_EVENT_KIND_UNSPECIFIED: ToolCallingStreamEventKind
TOOL_CALLING_STREAM_EVENT_KIND_MODEL_TOKEN: ToolCallingStreamEventKind
TOOL_CALLING_STREAM_EVENT_KIND_TOOL_CALL_PARSED: ToolCallingStreamEventKind
TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_STARTED: ToolCallingStreamEventKind
TOOL_CALLING_STREAM_EVENT_KIND_TOOL_EXECUTION_COMPLETED: ToolCallingStreamEventKind
TOOL_CALLING_STREAM_EVENT_KIND_COMPLETED: ToolCallingStreamEventKind
TOOL_CALLING_STREAM_EVENT_KIND_ERROR: ToolCallingStreamEventKind

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
    __slots__ = ("name", "type", "description", "required", "enum_values", "json_schema", "default_value")
    NAME_FIELD_NUMBER: _ClassVar[int]
    TYPE_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_FIELD_NUMBER: _ClassVar[int]
    ENUM_VALUES_FIELD_NUMBER: _ClassVar[int]
    JSON_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    DEFAULT_VALUE_FIELD_NUMBER: _ClassVar[int]
    name: str
    type: ToolParameterType
    description: str
    required: bool
    enum_values: _containers.RepeatedScalarFieldContainer[str]
    json_schema: str
    default_value: ToolValue
    def __init__(self, name: _Optional[str] = ..., type: _Optional[_Union[ToolParameterType, str]] = ..., description: _Optional[str] = ..., required: _Optional[bool] = ..., enum_values: _Optional[_Iterable[str]] = ..., json_schema: _Optional[str] = ..., default_value: _Optional[_Union[ToolValue, _Mapping]] = ...) -> None: ...

class ToolDefinition(_message.Message):
    __slots__ = ("name", "description", "parameters", "category", "json_schema", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    NAME_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    PARAMETERS_FIELD_NUMBER: _ClassVar[int]
    CATEGORY_FIELD_NUMBER: _ClassVar[int]
    JSON_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    name: str
    description: str
    parameters: _containers.RepeatedCompositeFieldContainer[ToolParameter]
    category: str
    json_schema: str
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, name: _Optional[str] = ..., description: _Optional[str] = ..., parameters: _Optional[_Iterable[_Union[ToolParameter, _Mapping]]] = ..., category: _Optional[str] = ..., json_schema: _Optional[str] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class ToolCall(_message.Message):
    __slots__ = ("id", "name", "arguments_json", "type", "arguments", "call_id", "created_at_ms", "raw_text")
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
    CREATED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    RAW_TEXT_FIELD_NUMBER: _ClassVar[int]
    id: str
    name: str
    arguments_json: str
    type: str
    arguments: _containers.MessageMap[str, ToolValue]
    call_id: str
    created_at_ms: int
    raw_text: str
    def __init__(self, id: _Optional[str] = ..., name: _Optional[str] = ..., arguments_json: _Optional[str] = ..., type: _Optional[str] = ..., arguments: _Optional[_Mapping[str, ToolValue]] = ..., call_id: _Optional[str] = ..., created_at_ms: _Optional[int] = ..., raw_text: _Optional[str] = ...) -> None: ...

class ToolResult(_message.Message):
    __slots__ = ("tool_call_id", "name", "result_json", "error", "success", "result", "call_id", "started_at_ms", "completed_at_ms")
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
    STARTED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    COMPLETED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    tool_call_id: str
    name: str
    result_json: str
    error: str
    success: bool
    result: _containers.MessageMap[str, ToolValue]
    call_id: str
    started_at_ms: int
    completed_at_ms: int
    def __init__(self, tool_call_id: _Optional[str] = ..., name: _Optional[str] = ..., result_json: _Optional[str] = ..., error: _Optional[str] = ..., success: _Optional[bool] = ..., result: _Optional[_Mapping[str, ToolValue]] = ..., call_id: _Optional[str] = ..., started_at_ms: _Optional[int] = ..., completed_at_ms: _Optional[int] = ...) -> None: ...

class ToolCallingOptions(_message.Message):
    __slots__ = ("tools", "max_iterations", "auto_execute", "temperature", "max_tokens", "system_prompt", "replace_system_prompt", "keep_tools_available", "format_hint", "format", "custom_system_prompt", "max_tool_calls", "tool_choice", "forced_tool_name", "parallel_tool_calls", "require_json_arguments")
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
    TOOL_CHOICE_FIELD_NUMBER: _ClassVar[int]
    FORCED_TOOL_NAME_FIELD_NUMBER: _ClassVar[int]
    PARALLEL_TOOL_CALLS_FIELD_NUMBER: _ClassVar[int]
    REQUIRE_JSON_ARGUMENTS_FIELD_NUMBER: _ClassVar[int]
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
    tool_choice: ToolChoiceMode
    forced_tool_name: str
    parallel_tool_calls: bool
    require_json_arguments: bool
    def __init__(self, tools: _Optional[_Iterable[_Union[ToolDefinition, _Mapping]]] = ..., max_iterations: _Optional[int] = ..., auto_execute: _Optional[bool] = ..., temperature: _Optional[float] = ..., max_tokens: _Optional[int] = ..., system_prompt: _Optional[str] = ..., replace_system_prompt: _Optional[bool] = ..., keep_tools_available: _Optional[bool] = ..., format_hint: _Optional[str] = ..., format: _Optional[_Union[ToolCallFormatName, str]] = ..., custom_system_prompt: _Optional[str] = ..., max_tool_calls: _Optional[int] = ..., tool_choice: _Optional[_Union[ToolChoiceMode, str]] = ..., forced_tool_name: _Optional[str] = ..., parallel_tool_calls: _Optional[bool] = ..., require_json_arguments: _Optional[bool] = ...) -> None: ...

class ToolCallingResult(_message.Message):
    __slots__ = ("text", "tool_calls", "tool_results", "is_complete", "conversation_id", "iterations_used", "error_message", "error_code", "raw_text")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLS_FIELD_NUMBER: _ClassVar[int]
    TOOL_RESULTS_FIELD_NUMBER: _ClassVar[int]
    IS_COMPLETE_FIELD_NUMBER: _ClassVar[int]
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    ITERATIONS_USED_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    RAW_TEXT_FIELD_NUMBER: _ClassVar[int]
    text: str
    tool_calls: _containers.RepeatedCompositeFieldContainer[ToolCall]
    tool_results: _containers.RepeatedCompositeFieldContainer[ToolResult]
    is_complete: bool
    conversation_id: str
    iterations_used: int
    error_message: str
    error_code: int
    raw_text: str
    def __init__(self, text: _Optional[str] = ..., tool_calls: _Optional[_Iterable[_Union[ToolCall, _Mapping]]] = ..., tool_results: _Optional[_Iterable[_Union[ToolResult, _Mapping]]] = ..., is_complete: _Optional[bool] = ..., conversation_id: _Optional[str] = ..., iterations_used: _Optional[int] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ..., raw_text: _Optional[str] = ...) -> None: ...

class ToolParseRequest(_message.Message):
    __slots__ = ("text", "options")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    text: str
    options: ToolCallingOptions
    def __init__(self, text: _Optional[str] = ..., options: _Optional[_Union[ToolCallingOptions, _Mapping]] = ...) -> None: ...

class ToolParseResult(_message.Message):
    __slots__ = ("has_tool_call", "tool_calls", "remaining_text", "error_message", "error_code")
    HAS_TOOL_CALL_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALLS_FIELD_NUMBER: _ClassVar[int]
    REMAINING_TEXT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    has_tool_call: bool
    tool_calls: _containers.RepeatedCompositeFieldContainer[ToolCall]
    remaining_text: str
    error_message: str
    error_code: int
    def __init__(self, has_tool_call: _Optional[bool] = ..., tool_calls: _Optional[_Iterable[_Union[ToolCall, _Mapping]]] = ..., remaining_text: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class ToolPromptFormatRequest(_message.Message):
    __slots__ = ("user_prompt", "options", "tool_results", "assistant_text")
    USER_PROMPT_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    TOOL_RESULTS_FIELD_NUMBER: _ClassVar[int]
    ASSISTANT_TEXT_FIELD_NUMBER: _ClassVar[int]
    user_prompt: str
    options: ToolCallingOptions
    tool_results: _containers.RepeatedCompositeFieldContainer[ToolResult]
    assistant_text: str
    def __init__(self, user_prompt: _Optional[str] = ..., options: _Optional[_Union[ToolCallingOptions, _Mapping]] = ..., tool_results: _Optional[_Iterable[_Union[ToolResult, _Mapping]]] = ..., assistant_text: _Optional[str] = ...) -> None: ...

class ToolPromptFormatResult(_message.Message):
    __slots__ = ("formatted_prompt", "format", "format_hint", "error_message", "error_code")
    FORMATTED_PROMPT_FIELD_NUMBER: _ClassVar[int]
    FORMAT_FIELD_NUMBER: _ClassVar[int]
    FORMAT_HINT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    formatted_prompt: str
    format: ToolCallFormatName
    format_hint: str
    error_message: str
    error_code: int
    def __init__(self, formatted_prompt: _Optional[str] = ..., format: _Optional[_Union[ToolCallFormatName, str]] = ..., format_hint: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class ToolCallValidationRequest(_message.Message):
    __slots__ = ("tool_call", "options")
    TOOL_CALL_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    tool_call: ToolCall
    options: ToolCallingOptions
    def __init__(self, tool_call: _Optional[_Union[ToolCall, _Mapping]] = ..., options: _Optional[_Union[ToolCallingOptions, _Mapping]] = ...) -> None: ...

class ToolCallValidationResult(_message.Message):
    __slots__ = ("is_valid", "validation_errors", "matched_tool", "normalized_arguments_json", "error_message", "error_code")
    IS_VALID_FIELD_NUMBER: _ClassVar[int]
    VALIDATION_ERRORS_FIELD_NUMBER: _ClassVar[int]
    MATCHED_TOOL_FIELD_NUMBER: _ClassVar[int]
    NORMALIZED_ARGUMENTS_JSON_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    is_valid: bool
    validation_errors: _containers.RepeatedScalarFieldContainer[str]
    matched_tool: ToolDefinition
    normalized_arguments_json: str
    error_message: str
    error_code: int
    def __init__(self, is_valid: _Optional[bool] = ..., validation_errors: _Optional[_Iterable[str]] = ..., matched_tool: _Optional[_Union[ToolDefinition, _Mapping]] = ..., normalized_arguments_json: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class ToolCallingStreamEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "conversation_id", "kind", "token", "tool_call", "tool_result", "result", "error_message", "error_code")
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    CONVERSATION_ID_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    TOKEN_FIELD_NUMBER: _ClassVar[int]
    TOOL_CALL_FIELD_NUMBER: _ClassVar[int]
    TOOL_RESULT_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    conversation_id: str
    kind: ToolCallingStreamEventKind
    token: str
    tool_call: ToolCall
    tool_result: ToolResult
    result: ToolCallingResult
    error_message: str
    error_code: int
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., conversation_id: _Optional[str] = ..., kind: _Optional[_Union[ToolCallingStreamEventKind, str]] = ..., token: _Optional[str] = ..., tool_call: _Optional[_Union[ToolCall, _Mapping]] = ..., tool_result: _Optional[_Union[ToolResult, _Mapping]] = ..., result: _Optional[_Union[ToolCallingResult, _Mapping]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class ToolRegistrySnapshot(_message.Message):
    __slots__ = ("tools", "updated_at_ms")
    TOOLS_FIELD_NUMBER: _ClassVar[int]
    UPDATED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    tools: _containers.RepeatedCompositeFieldContainer[ToolDefinition]
    updated_at_ms: int
    def __init__(self, tools: _Optional[_Iterable[_Union[ToolDefinition, _Mapping]]] = ..., updated_at_ms: _Optional[int] = ...) -> None: ...
