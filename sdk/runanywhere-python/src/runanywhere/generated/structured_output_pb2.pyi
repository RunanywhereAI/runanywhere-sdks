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

class JSONSchemaProperty(_message.Message):
    __slots__ = ("type", "description", "enum_values", "format", "items_schema", "object_schema")
    TYPE_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    ENUM_VALUES_FIELD_NUMBER: _ClassVar[int]
    FORMAT_FIELD_NUMBER: _ClassVar[int]
    ITEMS_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    OBJECT_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    type: JSONSchemaType
    description: str
    enum_values: _containers.RepeatedScalarFieldContainer[str]
    format: str
    items_schema: JSONSchema
    object_schema: JSONSchema
    def __init__(self, type: _Optional[_Union[JSONSchemaType, str]] = ..., description: _Optional[str] = ..., enum_values: _Optional[_Iterable[str]] = ..., format: _Optional[str] = ..., items_schema: _Optional[_Union[JSONSchema, _Mapping]] = ..., object_schema: _Optional[_Union[JSONSchema, _Mapping]] = ...) -> None: ...

class JSONSchema(_message.Message):
    __slots__ = ("type", "properties", "required", "items", "additional_properties", "schema_uri", "id_uri", "title", "description", "definitions", "ref", "all_of", "any_of", "one_of", "not_schema")
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
    def __init__(self, type: _Optional[_Union[JSONSchemaType, str]] = ..., properties: _Optional[_Mapping[str, JSONSchemaProperty]] = ..., required: _Optional[_Iterable[str]] = ..., items: _Optional[_Union[JSONSchemaProperty, _Mapping]] = ..., additional_properties: _Optional[bool] = ..., schema_uri: _Optional[str] = ..., id_uri: _Optional[str] = ..., title: _Optional[str] = ..., description: _Optional[str] = ..., definitions: _Optional[_Mapping[str, JSONSchema]] = ..., ref: _Optional[str] = ..., all_of: _Optional[_Iterable[_Union[JSONSchema, _Mapping]]] = ..., any_of: _Optional[_Iterable[_Union[JSONSchema, _Mapping]]] = ..., one_of: _Optional[_Iterable[_Union[JSONSchema, _Mapping]]] = ..., not_schema: _Optional[_Union[JSONSchema, _Mapping]] = ...) -> None: ...

class StructuredOutputOptions(_message.Message):
    __slots__ = ("schema", "include_schema_in_prompt", "strict_mode", "json_schema", "type_name", "name")
    SCHEMA_FIELD_NUMBER: _ClassVar[int]
    INCLUDE_SCHEMA_IN_PROMPT_FIELD_NUMBER: _ClassVar[int]
    STRICT_MODE_FIELD_NUMBER: _ClassVar[int]
    JSON_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    TYPE_NAME_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    schema: JSONSchema
    include_schema_in_prompt: bool
    strict_mode: bool
    json_schema: str
    type_name: str
    name: str
    def __init__(self, schema: _Optional[_Union[JSONSchema, _Mapping]] = ..., include_schema_in_prompt: _Optional[bool] = ..., strict_mode: _Optional[bool] = ..., json_schema: _Optional[str] = ..., type_name: _Optional[str] = ..., name: _Optional[str] = ...) -> None: ...

class StructuredOutputValidation(_message.Message):
    __slots__ = ("is_valid", "contains_json", "error_message", "raw_output", "extracted_json")
    IS_VALID_FIELD_NUMBER: _ClassVar[int]
    CONTAINS_JSON_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    RAW_OUTPUT_FIELD_NUMBER: _ClassVar[int]
    EXTRACTED_JSON_FIELD_NUMBER: _ClassVar[int]
    is_valid: bool
    contains_json: bool
    error_message: str
    raw_output: str
    extracted_json: str
    def __init__(self, is_valid: _Optional[bool] = ..., contains_json: _Optional[bool] = ..., error_message: _Optional[str] = ..., raw_output: _Optional[str] = ..., extracted_json: _Optional[str] = ...) -> None: ...

class StructuredOutputResult(_message.Message):
    __slots__ = ("parsed_json", "validation", "raw_text")
    PARSED_JSON_FIELD_NUMBER: _ClassVar[int]
    VALIDATION_FIELD_NUMBER: _ClassVar[int]
    RAW_TEXT_FIELD_NUMBER: _ClassVar[int]
    parsed_json: bytes
    validation: StructuredOutputValidation
    raw_text: str
    def __init__(self, parsed_json: _Optional[bytes] = ..., validation: _Optional[_Union[StructuredOutputValidation, _Mapping]] = ..., raw_text: _Optional[str] = ...) -> None: ...

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
