import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class VLMImageFormat(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VLM_IMAGE_FORMAT_UNSPECIFIED: _ClassVar[VLMImageFormat]
    VLM_IMAGE_FORMAT_JPEG: _ClassVar[VLMImageFormat]
    VLM_IMAGE_FORMAT_PNG: _ClassVar[VLMImageFormat]
    VLM_IMAGE_FORMAT_WEBP: _ClassVar[VLMImageFormat]
    VLM_IMAGE_FORMAT_RAW_RGB: _ClassVar[VLMImageFormat]
    VLM_IMAGE_FORMAT_RAW_RGBA: _ClassVar[VLMImageFormat]
    VLM_IMAGE_FORMAT_BASE64: _ClassVar[VLMImageFormat]
    VLM_IMAGE_FORMAT_FILE_PATH: _ClassVar[VLMImageFormat]

class VLMModelFamily(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VLM_MODEL_FAMILY_UNSPECIFIED: _ClassVar[VLMModelFamily]
    VLM_MODEL_FAMILY_AUTO: _ClassVar[VLMModelFamily]
    VLM_MODEL_FAMILY_QWEN2_VL: _ClassVar[VLMModelFamily]
    VLM_MODEL_FAMILY_SMOLVLM: _ClassVar[VLMModelFamily]
    VLM_MODEL_FAMILY_LLAVA: _ClassVar[VLMModelFamily]
    VLM_MODEL_FAMILY_CUSTOM: _ClassVar[VLMModelFamily]

class VLMErrorCode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VLM_ERROR_CODE_UNSPECIFIED: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_INVALID_IMAGE: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_MODEL_NOT_LOADED: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_UNSUPPORTED_FORMAT: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_IMAGE_TOO_LARGE: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_NOT_INITIALIZED: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_MODEL_LOAD_FAILED: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_PROCESSING_FAILED: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_CANCELLED: _ClassVar[VLMErrorCode]

class VLMStreamEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VLM_STREAM_EVENT_KIND_UNSPECIFIED: _ClassVar[VLMStreamEventKind]
    VLM_STREAM_EVENT_KIND_STARTED: _ClassVar[VLMStreamEventKind]
    VLM_STREAM_EVENT_KIND_IMAGE_ENCODED: _ClassVar[VLMStreamEventKind]
    VLM_STREAM_EVENT_KIND_TOKEN: _ClassVar[VLMStreamEventKind]
    VLM_STREAM_EVENT_KIND_COMPLETED: _ClassVar[VLMStreamEventKind]
    VLM_STREAM_EVENT_KIND_ERROR: _ClassVar[VLMStreamEventKind]
VLM_IMAGE_FORMAT_UNSPECIFIED: VLMImageFormat
VLM_IMAGE_FORMAT_JPEG: VLMImageFormat
VLM_IMAGE_FORMAT_PNG: VLMImageFormat
VLM_IMAGE_FORMAT_WEBP: VLMImageFormat
VLM_IMAGE_FORMAT_RAW_RGB: VLMImageFormat
VLM_IMAGE_FORMAT_RAW_RGBA: VLMImageFormat
VLM_IMAGE_FORMAT_BASE64: VLMImageFormat
VLM_IMAGE_FORMAT_FILE_PATH: VLMImageFormat
VLM_MODEL_FAMILY_UNSPECIFIED: VLMModelFamily
VLM_MODEL_FAMILY_AUTO: VLMModelFamily
VLM_MODEL_FAMILY_QWEN2_VL: VLMModelFamily
VLM_MODEL_FAMILY_SMOLVLM: VLMModelFamily
VLM_MODEL_FAMILY_LLAVA: VLMModelFamily
VLM_MODEL_FAMILY_CUSTOM: VLMModelFamily
VLM_ERROR_CODE_UNSPECIFIED: VLMErrorCode
VLM_ERROR_CODE_INVALID_IMAGE: VLMErrorCode
VLM_ERROR_CODE_MODEL_NOT_LOADED: VLMErrorCode
VLM_ERROR_CODE_UNSUPPORTED_FORMAT: VLMErrorCode
VLM_ERROR_CODE_IMAGE_TOO_LARGE: VLMErrorCode
VLM_ERROR_CODE_NOT_INITIALIZED: VLMErrorCode
VLM_ERROR_CODE_MODEL_LOAD_FAILED: VLMErrorCode
VLM_ERROR_CODE_PROCESSING_FAILED: VLMErrorCode
VLM_ERROR_CODE_CANCELLED: VLMErrorCode
VLM_STREAM_EVENT_KIND_UNSPECIFIED: VLMStreamEventKind
VLM_STREAM_EVENT_KIND_STARTED: VLMStreamEventKind
VLM_STREAM_EVENT_KIND_IMAGE_ENCODED: VLMStreamEventKind
VLM_STREAM_EVENT_KIND_TOKEN: VLMStreamEventKind
VLM_STREAM_EVENT_KIND_COMPLETED: VLMStreamEventKind
VLM_STREAM_EVENT_KIND_ERROR: VLMStreamEventKind

class VLMChatTemplate(_message.Message):
    __slots__ = ("template_text", "image_marker", "default_system_prompt")
    TEMPLATE_TEXT_FIELD_NUMBER: _ClassVar[int]
    IMAGE_MARKER_FIELD_NUMBER: _ClassVar[int]
    DEFAULT_SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    template_text: str
    image_marker: str
    default_system_prompt: str
    def __init__(self, template_text: _Optional[str] = ..., image_marker: _Optional[str] = ..., default_system_prompt: _Optional[str] = ...) -> None: ...

class VLMImage(_message.Message):
    __slots__ = ("file_path", "encoded", "raw_rgb", "base64", "width", "height", "format", "media_type", "name", "size_bytes", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    FILE_PATH_FIELD_NUMBER: _ClassVar[int]
    ENCODED_FIELD_NUMBER: _ClassVar[int]
    RAW_RGB_FIELD_NUMBER: _ClassVar[int]
    BASE64_FIELD_NUMBER: _ClassVar[int]
    WIDTH_FIELD_NUMBER: _ClassVar[int]
    HEIGHT_FIELD_NUMBER: _ClassVar[int]
    FORMAT_FIELD_NUMBER: _ClassVar[int]
    MEDIA_TYPE_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    file_path: str
    encoded: bytes
    raw_rgb: bytes
    base64: str
    width: int
    height: int
    format: VLMImageFormat
    media_type: str
    name: str
    size_bytes: int
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, file_path: _Optional[str] = ..., encoded: _Optional[bytes] = ..., raw_rgb: _Optional[bytes] = ..., base64: _Optional[str] = ..., width: _Optional[int] = ..., height: _Optional[int] = ..., format: _Optional[_Union[VLMImageFormat, str]] = ..., media_type: _Optional[str] = ..., name: _Optional[str] = ..., size_bytes: _Optional[int] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class VLMConfiguration(_message.Message):
    __slots__ = ("model_id", "max_image_size_px", "max_tokens", "context_length", "temperature", "system_prompt", "streaming_enabled", "preferred_framework")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    MAX_IMAGE_SIZE_PX_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    CONTEXT_LENGTH_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    STREAMING_ENABLED_FIELD_NUMBER: _ClassVar[int]
    PREFERRED_FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    max_image_size_px: int
    max_tokens: int
    context_length: int
    temperature: float
    system_prompt: str
    streaming_enabled: bool
    preferred_framework: _model_types_pb2.InferenceFramework
    def __init__(self, model_id: _Optional[str] = ..., max_image_size_px: _Optional[int] = ..., max_tokens: _Optional[int] = ..., context_length: _Optional[int] = ..., temperature: _Optional[float] = ..., system_prompt: _Optional[str] = ..., streaming_enabled: _Optional[bool] = ..., preferred_framework: _Optional[_Union[_model_types_pb2.InferenceFramework, str]] = ...) -> None: ...

class VLMGenerationOptions(_message.Message):
    __slots__ = ("prompt", "max_tokens", "temperature", "top_p", "top_k", "stop_sequences", "streaming_enabled", "system_prompt", "max_image_size", "n_threads", "use_gpu", "model_family", "custom_chat_template", "image_marker_override", "seed", "repetition_penalty", "min_p", "emit_image_embeddings")
    PROMPT_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    TOP_P_FIELD_NUMBER: _ClassVar[int]
    TOP_K_FIELD_NUMBER: _ClassVar[int]
    STOP_SEQUENCES_FIELD_NUMBER: _ClassVar[int]
    STREAMING_ENABLED_FIELD_NUMBER: _ClassVar[int]
    SYSTEM_PROMPT_FIELD_NUMBER: _ClassVar[int]
    MAX_IMAGE_SIZE_FIELD_NUMBER: _ClassVar[int]
    N_THREADS_FIELD_NUMBER: _ClassVar[int]
    USE_GPU_FIELD_NUMBER: _ClassVar[int]
    MODEL_FAMILY_FIELD_NUMBER: _ClassVar[int]
    CUSTOM_CHAT_TEMPLATE_FIELD_NUMBER: _ClassVar[int]
    IMAGE_MARKER_OVERRIDE_FIELD_NUMBER: _ClassVar[int]
    SEED_FIELD_NUMBER: _ClassVar[int]
    REPETITION_PENALTY_FIELD_NUMBER: _ClassVar[int]
    MIN_P_FIELD_NUMBER: _ClassVar[int]
    EMIT_IMAGE_EMBEDDINGS_FIELD_NUMBER: _ClassVar[int]
    prompt: str
    max_tokens: int
    temperature: float
    top_p: float
    top_k: int
    stop_sequences: _containers.RepeatedScalarFieldContainer[str]
    streaming_enabled: bool
    system_prompt: str
    max_image_size: int
    n_threads: int
    use_gpu: bool
    model_family: VLMModelFamily
    custom_chat_template: VLMChatTemplate
    image_marker_override: str
    seed: int
    repetition_penalty: float
    min_p: float
    emit_image_embeddings: bool
    def __init__(self, prompt: _Optional[str] = ..., max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ..., stop_sequences: _Optional[_Iterable[str]] = ..., streaming_enabled: _Optional[bool] = ..., system_prompt: _Optional[str] = ..., max_image_size: _Optional[int] = ..., n_threads: _Optional[int] = ..., use_gpu: _Optional[bool] = ..., model_family: _Optional[_Union[VLMModelFamily, str]] = ..., custom_chat_template: _Optional[_Union[VLMChatTemplate, _Mapping]] = ..., image_marker_override: _Optional[str] = ..., seed: _Optional[int] = ..., repetition_penalty: _Optional[float] = ..., min_p: _Optional[float] = ..., emit_image_embeddings: _Optional[bool] = ...) -> None: ...

class VLMGenerationRequest(_message.Message):
    __slots__ = ("request_id", "images", "options", "model_id", "metadata")
    class MetadataEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    IMAGES_FIELD_NUMBER: _ClassVar[int]
    OPTIONS_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    request_id: str
    images: _containers.RepeatedCompositeFieldContainer[VLMImage]
    options: VLMGenerationOptions
    model_id: str
    metadata: _containers.ScalarMap[str, str]
    def __init__(self, request_id: _Optional[str] = ..., images: _Optional[_Iterable[_Union[VLMImage, _Mapping]]] = ..., options: _Optional[_Union[VLMGenerationOptions, _Mapping]] = ..., model_id: _Optional[str] = ..., metadata: _Optional[_Mapping[str, str]] = ...) -> None: ...

class VLMResult(_message.Message):
    __slots__ = ("text", "prompt_tokens", "completion_tokens", "total_tokens", "processing_time_ms", "tokens_per_second", "image_tokens", "time_to_first_token_ms", "image_encode_time_ms", "hardware_used", "error_message", "error_code", "finish_reason", "images_processed")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    COMPLETION_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TOKENS_FIELD_NUMBER: _ClassVar[int]
    PROCESSING_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_PER_SECOND_FIELD_NUMBER: _ClassVar[int]
    IMAGE_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TIME_TO_FIRST_TOKEN_MS_FIELD_NUMBER: _ClassVar[int]
    IMAGE_ENCODE_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    HARDWARE_USED_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    FINISH_REASON_FIELD_NUMBER: _ClassVar[int]
    IMAGES_PROCESSED_FIELD_NUMBER: _ClassVar[int]
    text: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    processing_time_ms: int
    tokens_per_second: float
    image_tokens: int
    time_to_first_token_ms: int
    image_encode_time_ms: int
    hardware_used: str
    error_message: str
    error_code: int
    finish_reason: str
    images_processed: int
    def __init__(self, text: _Optional[str] = ..., prompt_tokens: _Optional[int] = ..., completion_tokens: _Optional[int] = ..., total_tokens: _Optional[int] = ..., processing_time_ms: _Optional[int] = ..., tokens_per_second: _Optional[float] = ..., image_tokens: _Optional[int] = ..., time_to_first_token_ms: _Optional[int] = ..., image_encode_time_ms: _Optional[int] = ..., hardware_used: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ..., finish_reason: _Optional[str] = ..., images_processed: _Optional[int] = ...) -> None: ...

class VLMStreamEvent(_message.Message):
    __slots__ = ("seq", "timestamp_us", "request_id", "kind", "token", "token_index", "is_final", "tokens_per_second", "result", "error_message", "error_code")
    SEQ_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_US_FIELD_NUMBER: _ClassVar[int]
    REQUEST_ID_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    TOKEN_FIELD_NUMBER: _ClassVar[int]
    TOKEN_INDEX_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    TOKENS_PER_SECOND_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    seq: int
    timestamp_us: int
    request_id: str
    kind: VLMStreamEventKind
    token: str
    token_index: int
    is_final: bool
    tokens_per_second: float
    result: VLMResult
    error_message: str
    error_code: int
    def __init__(self, seq: _Optional[int] = ..., timestamp_us: _Optional[int] = ..., request_id: _Optional[str] = ..., kind: _Optional[_Union[VLMStreamEventKind, str]] = ..., token: _Optional[str] = ..., token_index: _Optional[int] = ..., is_final: _Optional[bool] = ..., tokens_per_second: _Optional[float] = ..., result: _Optional[_Union[VLMResult, _Mapping]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class VLMServiceState(_message.Message):
    __slots__ = ("is_ready", "current_model", "context_length", "supports_streaming", "supports_multiple_images", "vision_encoder_type", "error_message", "error_code")
    IS_READY_FIELD_NUMBER: _ClassVar[int]
    CURRENT_MODEL_FIELD_NUMBER: _ClassVar[int]
    CONTEXT_LENGTH_FIELD_NUMBER: _ClassVar[int]
    SUPPORTS_STREAMING_FIELD_NUMBER: _ClassVar[int]
    SUPPORTS_MULTIPLE_IMAGES_FIELD_NUMBER: _ClassVar[int]
    VISION_ENCODER_TYPE_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    is_ready: bool
    current_model: str
    context_length: int
    supports_streaming: bool
    supports_multiple_images: bool
    vision_encoder_type: str
    error_message: str
    error_code: int
    def __init__(self, is_ready: _Optional[bool] = ..., current_model: _Optional[str] = ..., context_length: _Optional[int] = ..., supports_streaming: _Optional[bool] = ..., supports_multiple_images: _Optional[bool] = ..., vision_encoder_type: _Optional[str] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...
