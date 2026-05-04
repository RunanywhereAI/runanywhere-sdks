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
    __slots__ = ("file_path", "encoded", "raw_rgb", "base64", "width", "height", "format")
    FILE_PATH_FIELD_NUMBER: _ClassVar[int]
    ENCODED_FIELD_NUMBER: _ClassVar[int]
    RAW_RGB_FIELD_NUMBER: _ClassVar[int]
    BASE64_FIELD_NUMBER: _ClassVar[int]
    WIDTH_FIELD_NUMBER: _ClassVar[int]
    HEIGHT_FIELD_NUMBER: _ClassVar[int]
    FORMAT_FIELD_NUMBER: _ClassVar[int]
    file_path: str
    encoded: bytes
    raw_rgb: bytes
    base64: str
    width: int
    height: int
    format: VLMImageFormat
    def __init__(self, file_path: _Optional[str] = ..., encoded: _Optional[bytes] = ..., raw_rgb: _Optional[bytes] = ..., base64: _Optional[str] = ..., width: _Optional[int] = ..., height: _Optional[int] = ..., format: _Optional[_Union[VLMImageFormat, str]] = ...) -> None: ...

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
    __slots__ = ("prompt", "max_tokens", "temperature", "top_p", "top_k", "stop_sequences", "streaming_enabled", "system_prompt", "max_image_size", "n_threads", "use_gpu", "model_family", "custom_chat_template", "image_marker_override")
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
    def __init__(self, prompt: _Optional[str] = ..., max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ..., stop_sequences: _Optional[_Iterable[str]] = ..., streaming_enabled: _Optional[bool] = ..., system_prompt: _Optional[str] = ..., max_image_size: _Optional[int] = ..., n_threads: _Optional[int] = ..., use_gpu: _Optional[bool] = ..., model_family: _Optional[_Union[VLMModelFamily, str]] = ..., custom_chat_template: _Optional[_Union[VLMChatTemplate, _Mapping]] = ..., image_marker_override: _Optional[str] = ...) -> None: ...

class VLMResult(_message.Message):
    __slots__ = ("text", "prompt_tokens", "completion_tokens", "total_tokens", "processing_time_ms", "tokens_per_second", "image_tokens", "time_to_first_token_ms", "image_encode_time_ms", "hardware_used")
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
    def __init__(self, text: _Optional[str] = ..., prompt_tokens: _Optional[int] = ..., completion_tokens: _Optional[int] = ..., total_tokens: _Optional[int] = ..., processing_time_ms: _Optional[int] = ..., tokens_per_second: _Optional[float] = ..., image_tokens: _Optional[int] = ..., time_to_first_token_ms: _Optional[int] = ..., image_encode_time_ms: _Optional[int] = ..., hardware_used: _Optional[str] = ...) -> None: ...
