from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class JSONSchemaType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    JSON_SCHEMA_TYPE_UNSPECIFIED: _ClassVar[JSONSchemaType]
    JSON_SCHEMA_TYPE_OBJECT: _ClassVar[JSONSchemaType]
    JSON_SCHEMA_TYPE_ARRAY: _ClassVar[JSONSchemaType]
    JSON_SCHEMA_TYPE_STRING: _ClassVar[JSONSchemaType]
    JSON_SCHEMA_TYPE_NUMBER: _ClassVar[JSONSchemaType]
    JSON_SCHEMA_TYPE_INTEGER: _ClassVar[JSONSchemaType]
    JSON_SCHEMA_TYPE_BOOLEAN: _ClassVar[JSONSchemaType]
    JSON_SCHEMA_TYPE_NULL: _ClassVar[JSONSchemaType]

class Sentiment(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SENTIMENT_UNSPECIFIED: _ClassVar[Sentiment]
    SENTIMENT_POSITIVE: _ClassVar[Sentiment]
    SENTIMENT_NEGATIVE: _ClassVar[Sentiment]
    SENTIMENT_NEUTRAL: _ClassVar[Sentiment]
    SENTIMENT_MIXED: _ClassVar[Sentiment]

class StructuredOutputMode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    STRUCTURED_OUTPUT_MODE_UNSPECIFIED: _ClassVar[StructuredOutputMode]
    STRUCTURED_OUTPUT_MODE_JSON_SCHEMA: _ClassVar[StructuredOutputMode]
    STRUCTURED_OUTPUT_MODE_JSON_OBJECT: _ClassVar[StructuredOutputMode]
    STRUCTURED_OUTPUT_MODE_REGEX: _ClassVar[StructuredOutputMode]
    STRUCTURED_OUTPUT_MODE_GRAMMAR: _ClassVar[StructuredOutputMode]

class StructuredOutputStreamEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_UNSPECIFIED: _ClassVar[StructuredOutputStreamEventKind]
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN: _ClassVar[StructuredOutputStreamEventKind]
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_PARTIAL_JSON: _ClassVar[StructuredOutputStreamEventKind]
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_VALIDATION: _ClassVar[StructuredOutputStreamEventKind]
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED: _ClassVar[StructuredOutputStreamEventKind]
    STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR: _ClassVar[StructuredOutputStreamEventKind]
JSON_SCHEMA_TYPE_UNSPECIFIED: JSONSchemaType
JSON_SCHEMA_TYPE_OBJECT: JSONSchemaType
JSON_SCHEMA_TYPE_ARRAY: JSONSchemaType
JSON_SCHEMA_TYPE_STRING: JSONSchemaType
JSON_SCHEMA_TYPE_NUMBER: JSONSchemaType
JSON_SCHEMA_TYPE_INTEGER: JSONSchemaType
JSON_SCHEMA_TYPE_BOOLEAN: JSONSchemaType
JSON_SCHEMA_TYPE_NULL: JSONSchemaType
SENTIMENT_UNSPECIFIED: Sentiment
SENTIMENT_POSITIVE: Sentiment
SENTIMENT_NEGATIVE: Sentiment
SENTIMENT_NEUTRAL: Sentiment
SENTIMENT_MIXED: Sentiment
STRUCTURED_OUTPUT_MODE_UNSPECIFIED: StructuredOutputMode
STRUCTURED_OUTPUT_MODE_JSON_SCHEMA: StructuredOutputMode
STRUCTURED_OUTPUT_MODE_JSON_OBJECT: StructuredOutputMode
STRUCTURED_OUTPUT_MODE_REGEX: StructuredOutputMode
STRUCTURED_OUTPUT_MODE_GRAMMAR: StructuredOutputMode
STRUCTURED_OUTPUT_STREAM_EVENT_KIND_UNSPECIFIED: StructuredOutputStreamEventKind
STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN: StructuredOutputStreamEventKind
STRUCTURED_OUTPUT_STREAM_EVENT_KIND_PARTIAL_JSON: StructuredOutputStreamEventKind
STRUCTURED_OUTPUT_STREAM_EVENT_KIND_VALIDATION: StructuredOutputStreamEventKind
STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED: StructuredOutputStreamEventKind
STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR: StructuredOutputStreamEventKind

class JSONSchemaProperty(_message.Message):
    __slots__ = ("type", "description", "enum_values", "format", "items_schema", "object_schema", "minimum", "maximum", "min_length", "max_length", "pattern", "min_items", "max_items", "default_json")
    TYPE_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    ENUM_VALUES_FIELD_NUMBER: _ClassVar[int]
    FORMAT_FIELD_NUMBER: _ClassVar[int]
    ITEMS_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    OBJECT_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    MINIMUM_FIELD_NUMBER: _ClassVar[int]
    MAXIMUM_FIELD_NUMBER: _ClassVar[int]
    MIN_LENGTH_FIELD_NUMBER: _ClassVar[int]
    MAX_LENGTH_FIELD_NUMBER: _ClassVar[int]
    PATTERN_FIELD_NUMBER: _ClassVar[int]
    MIN_ITEMS_FIELD_NUMBER: _ClassVar[int]
    MAX_ITEMS_FIELD_NUMBER: _ClassVar[int]
    DEFAULT_JSON_FIELD_NUMBER: _ClassVar[int]
    type: JSONSchemaType
    description: str
    enum_values: _containers.RepeatedScalarFieldContainer[str]
    format: str
    items_schema: JSONSchema
    object_schema: JSONSchema
    minimum: float
    maximum: float
    min_length: int
    max_length: int
    pattern: str
    min_items: int
    max_items: int
    default_json: str
    def __init__(self, type: _Optional[_Union[JSONSchemaType, str]] = ..., description: _Optional[str] = ..., enum_values: _Optional[_Iterable[str]] = ..., format: _Optional[str] = ..., items_schema: _Optional[_Union[JSONSchema, _Mapping]] = ..., object_schema: _Optional[_Union[JSONSchema, _Mapping]] = ..., minimum: _Optional[float] = ..., maximum: _Optional[float] = ..., min_length: _Optional[int] = ..., max_length: _Optional[int] = ..., pattern: _Optional[str] = ..., min_items: _Optional[int] = ..., max_items: _Optional[int] = ..., default_json: _Optional[str] = ...) -> None: ...

class JSONSchema(_message.Message):
    __slots__ = ("type", "properties", "required", "items", "additional_properties", "schema_uri", "id_uri", "title", "description", "definitions", "ref", "all_of", "any_of", "one_of", "not_schema", "raw_json")
    class PropertiesEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: JSONSchemaProperty
        def __init__(self, key: _Optional[str] = ..., value: _Optional[_Union[JSONSchemaProperty, _Mapping]] = ...) -> None: ...
    class DefinitionsEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: JSONSchema
        def __init__(self, key: _Optional[str] = ..., value: _Optional[_Union[JSONSchema, _Mapping]] = ...) -> None: ...
    TYPE_FIELD_NUMBER: _ClassVar[int]
    PROPERTIES_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_FIELD_NUMBER: _ClassVar[int]
    ITEMS_FIELD_NUMBER: _ClassVar[int]
    ADDITIONAL_PROPERTIES_FIELD_NUMBER: _ClassVar[int]
    SCHEMA_URI_FIELD_NUMBER: _ClassVar[int]
    ID_URI_FIELD_NUMBER: _ClassVar[int]
    TITLE_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    DEFINITIONS_FIELD_NUMBER: _ClassVar[int]
    REF_FIELD_NUMBER: _ClassVar[int]
    ALL_OF_FIELD_NUMBER: _ClassVar[int]
    ANY_OF_FIELD_NUMBER: _ClassVar[int]
    ONE_OF_FIELD_NUMBER: _ClassVar[int]
    NOT_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    RAW_JSON_FIELD_NUMBER: _ClassVar[int]
    type: JSONSchemaType
    properties: _containers.MessageMap[str, JSONSchemaProperty]
    required: _containers.RepeatedScalarFieldContainer[str]
    items: JSONSchemaProperty
    additional_properties: bool
    schema_uri: str
    id_uri: str
    title: str
    description: str
    definitions: _containers.MessageMap[str, JSONSchema]
    ref: str
    all_of: _containers.RepeatedCompositeFieldContainer[JSONSchema]
    any_of: _containers.RepeatedCompositeFieldContainer[JSONSchema]
    one_of: _containers.RepeatedCompositeFieldContainer[JSONSchema]
    not_schema: JSONSchema
    raw_json: str
    def __init__(self, type: _Optional[_Union[JSONSchemaType, str]] = ..., properties: _Optional[_Mapping[str, JSONSchemaProperty]] = ..., required: _Optional[_Iterable[str]] = ..., items: _Optional[_Union[JSONSchemaProperty, _Mapping]] = ..., additional_properties: _Optional[bool] = ..., schema_uri: _Optional[str] = ..., id_uri: _Optional[str] = ..., title: _Optional[str] = ..., description: _Optional[str] = ..., definitions: _Optional[_Mapping[str, JSONSchema]] = ..., ref: _Optional[str] = ..., all_of: _Optional[_Iterable[_Union[JSONSchema, _Mapping]]] = ..., any_of: _Optional[_Iterable[_Union[JSONSchema, _Mapping]]] = ..., one_of: _Optional[_Iterable[_Union[JSONSchema, _Mapping]]] = ..., not_schema: _Optional[_Union[JSONSchema, _Mapping]] = ..., raw_json: _Optional[str] = ...) -> None: ...

class StructuredOutputOptions(_message.Message):
    __slots__ = ("schema", "include_schema_in_prompt", "strict_mode", "json_schema", "type_name", "name", "mode", "regex_pattern", "grammar", "repair_json", "max_retries")
    SCHEMA_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_SCHEMA_IN_PROMPT_FIELD_NUMBER: _ClassVar[int]
    STRICT_MODE_FIELD_NUMBER: _ClassVar[int]
    JSON_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    TYPE_NAME_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    MODE_FIELD_NUMBER: _ClassVar[int]
    REGEX_PATTERN_FIELD_NUMBER: _ClassVar[int]
    GRAMMAR_FIELD_NUMBER: _ClassVar[int]
    REPAIR_JSON_FIELD_NUMBER: _ClassVar[int]
    MAX_RETRIES_FIELD_NUMBER: _ClassVar[int]
    schema: JSONSchema
    include_schema_in_prompt: bool
    strict_mode: bool
    json_schema: str
    type_name: str
    name: str
    mode: StructuredOutputMode
    regex_pattern: str
    grammar: str
    repair_json: bool
    max_retries: int
    def __init__(self, schema: _Optional[_Union[JSONSchema, _Mapping]] = ..., include_schema_in_prompt: _Optional[bool] = ..., strict_mode: _Optional[bool] = ..., json_schema: _Optional[str] = ..., type_name: _Optional[str] = ..., name: _Optional[str] = ..., mode: _Optional[_Union[StructuredOutputMode, str]] = ..., regex_pattern: _Optional[str] = ..., grammar: _Optional[str] = ..., repair_json: _Optional[bool] = ..., max_retries: _Optional[int] = ...) -> None: ...

class StructuredOutputValidation(_message.Message):
    __slots__ = ("is_valid", "contains_json", "error_message", "raw_output", "extracted_json", "validation_errors", "validation_time_ms")
    IS_VALID_FIELD_NUMBER: _ClassVar[int]
    CONTAINS_JSON_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    RAW_OUTPUT_FIELD_NUMBER: _ClassVar[int]
    EXTRACTED_JSON_FIELD_NUMBER: _ClassVar[int]
    VALIDATION_ERRORS_FIELD_NUMBER: _ClassVar[int]
    VALIDATION_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    is_valid: bool
    contains_json: bool
    error_message: str
    raw_output: str
    extracted_json: str
    validation_errors: _containers.RepeatedScalarFieldContainer[str]
    validation_time_ms: int
    def __init__(self, is_valid: _Optional[bool] = ..., contains_json: _Optional[bool] = ..., error_message: _Optional[str] = ..., raw_output: _Optional[str] = ..., extracted_json: _Optional[str] = ..., validation_errors: _Optional[_Iterable[str]] = ..., validation_time_ms: _Optional[int] = ...) -> None: ...

class StructuredOutputResult(_message.Message):
    __slots__ = ("parsed_json", "validation", "raw_text", "error_message", "error_code")
    PARSED_JSON_FIELD_NUMBER: _ClassVar[int]
    VALIDATION_FIELD_NUMBER: _ClassVar[int]
    RAW_TEXT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    parsed_json: bytes
    validation: StructuredOutputValidation
    raw_text: str
    error_message: str
    error_code: int
    def __init__(self, parsed_json: _Optional[bytes] = ..., validation: _Optional[_Union[StructuredOutputValidation, _Mapping]] = ..., raw_text: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class StructuredOutputParseRequest(_message.Message):
    __slots__ = ("request_id", "text", "options", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    TEXT_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    text: str
    options: StructuredOutputOptions
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, request_id: _Optional[str] = ..., text: _Optional[str] = ..., options: _Optional[_Union[StructuredOutputOptions, _Mapping]] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class StructuredOutputValidationRequest(_message.Message):
    __slots__ = ("text", "options")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    text: str
    options: StructuredOutputOptions
    def __init__(self, text: _Optional[str] = ..., options: _Optional[_Union[StructuredOutputOptions, _Mapping]] = ...) -> None: ...

class StructuredOutputPromptResult(_message.Message):
    __slots__ = ("prepared_prompt", "system_prompt", "json_schema", "regex_pattern", "grammar", "error_message", "error_code")
    PREPARED_PROMPT_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    JSON_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    REGEX_PATTERN_FIELD_NUMBER: _ClassVar[int]
    GRAMMAR_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    prepared_prompt: str
    system_prompt: str
    json_schema: str
    regex_pattern: str
    grammar: str
    error_message: str
    error_code: int
    def __init__(self, prepared_prompt: _Optional[str] = ..., system_prompt: _Optional[str] = ..., json_schema: _Optional[str] = ..., regex_pattern: _Optional[str] = ..., grammar: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class StructuredOutputRequest(_message.Message):
    __slots__ = ("request_id", "prompt", "options", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    PROMPT_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    prompt: str
    options: StructuredOutputOptions
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, request_id: _Optional[str] = ..., prompt: _Optional[str] = ..., options: _Optional[_Union[StructuredOutputOptions, _Mapping]] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class StructuredOutputStreamEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "request_id", "kind", "token", "partial_json", "validation", "result", "error_message", "error_code")
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    TOKEN_FIELD_NUMBER: _ClassVar[int]
    PARTIAL_JSON_FIELD_NUMBER: _ClassVar[int]
    VALIDATION_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    request_id: str
    kind: StructuredOutputStreamEventKind
    token: str
    partial_json: str
    validation: StructuredOutputValidation
    result: StructuredOutputResult
    error_message: str
    error_code: int
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., request_id: _Optional[str] = ..., kind: _Optional[_Union[StructuredOutputStreamEventKind, str]] = ..., token: _Optional[str] = ..., partial_json: _Optional[str] = ..., validation: _Optional[_Union[StructuredOutputValidation, _Mapping]] = ..., result: _Optional[_Union[StructuredOutputResult, _Mapping]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class NamedEntity(_message.Message):
    __slots__ = ("text", "entity_type", "start_offset", "end_offset", "confidence")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    ENTITY_TYPE_FIELD_NUMBER: _ClassVar[int]
    START_OFFSET_FIELD_NUMBER: _ClassVar[int]
    END_OFFSET_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    text: str
    entity_type: str
    start_offset: int
    end_offset: int
    confidence: float
    def __init__(self, text: _Optional[str] = ..., entity_type: _Optional[str] = ..., start_offset: _Optional[int] = ..., end_offset: _Optional[int] = ..., confidence: _Optional[float] = ...) -> None: ...

class EntityExtractionResult(_message.Message):
    __slots__ = ("entities",)
    ENTITIES_FIELD_NUMBER: _ClassVar[int]
    entities: _containers.RepeatedCompositeFieldContainer[NamedEntity]
    def __init__(self, entities: _Optional[_Iterable[_Union[NamedEntity, _Mapping]]] = ...) -> None: ...

class ClassificationCandidate(_message.Message):
    __slots__ = ("label", "confidence")
    LABEL_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    label: str
    confidence: float
    def __init__(self, label: _Optional[str] = ..., confidence: _Optional[float] = ...) -> None: ...

class ClassificationResult(_message.Message):
    __slots__ = ("label", "confidence", "alternatives")
    LABEL_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    ALTERNATIVES_FIELD_NUMBER: _ClassVar[int]
    label: str
    confidence: float
    alternatives: _containers.RepeatedCompositeFieldContainer[ClassificationCandidate]
    def __init__(self, label: _Optional[str] = ..., confidence: _Optional[float] = ..., alternatives: _Optional[_Iterable[_Union[ClassificationCandidate, _Mapping]]] = ...) -> None: ...

class SentimentResult(_message.Message):
    __slots__ = ("sentiment", "confidence", "positive_score", "negative_score", "neutral_score")
    SENTIMENT_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    POSITIVE_SCORE_FIELD_NUMBER: _ClassVar[int]
    NEGATIVE_SCORE_FIELD_NUMBER: _ClassVar[int]
    NEUTRAL_SCORE_FIELD_NUMBER: _ClassVar[int]
    sentiment: Sentiment
    confidence: float
    positive_score: float
    negative_score: float
    neutral_score: float
    def __init__(self, sentiment: _Optional[_Union[Sentiment, str]] = ..., confidence: _Optional[float] = ..., positive_score: _Optional[float] = ..., negative_score: _Optional[float] = ..., neutral_score: _Optional[float] = ...) -> None: ...

class NERResult(_message.Message):
    __slots__ = ("entities",)
    ENTITIES_FIELD_NUMBER: _ClassVar[int]
    entities: _containers.RepeatedCompositeFieldContainer[NamedEntity]
    def __init__(self, entities: _Optional[_Iterable[_Union[NamedEntity, _Mapping]]] = ...) -> None: ...
