from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
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

class VLMErrorCode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VLM_ERROR_CODE_UNSPECIFIED: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_INVALID_IMAGE: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_MODEL_NOT_LOADED: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_UNSUPPORTED_FORMAT: _ClassVar[VLMErrorCode]
    VLM_ERROR_CODE_IMAGE_TOO_LARGE: _ClassVar[VLMErrorCode]
VLM_IMAGE_FORMAT_UNSPECIFIED: VLMImageFormat
VLM_IMAGE_FORMAT_JPEG: VLMImageFormat
VLM_IMAGE_FORMAT_PNG: VLMImageFormat
VLM_IMAGE_FORMAT_WEBP: VLMImageFormat
VLM_IMAGE_FORMAT_RAW_RGB: VLMImageFormat
VLM_IMAGE_FORMAT_RAW_RGBA: VLMImageFormat
VLM_IMAGE_FORMAT_BASE64: VLMImageFormat
VLM_IMAGE_FORMAT_FILE_PATH: VLMImageFormat
VLM_ERROR_CODE_UNSPECIFIED: VLMErrorCode
VLM_ERROR_CODE_INVALID_IMAGE: VLMErrorCode
VLM_ERROR_CODE_MODEL_NOT_LOADED: VLMErrorCode
VLM_ERROR_CODE_UNSUPPORTED_FORMAT: VLMErrorCode
VLM_ERROR_CODE_IMAGE_TOO_LARGE: VLMErrorCode

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
    __slots__ = ("model_id", "max_image_size_px", "max_tokens")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    MAX_IMAGE_SIZE_PX_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    max_image_size_px: int
    max_tokens: int
    def __init__(self, model_id: _Optional[str] = ..., max_image_size_px: _Optional[int] = ..., max_tokens: _Optional[int] = ...) -> None: ...

class VLMGenerationOptions(_message.Message):
    __slots__ = ("prompt", "max_tokens", "temperature", "top_p", "top_k")
    PROMPT_FIELD_NUMBER: _ClassVar[int]
    MAX_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TEMPERATURE_FIELD_NUMBER: _ClassVar[int]
    TOP_P_FIELD_NUMBER: _ClassVar[int]
    TOP_K_FIELD_NUMBER: _ClassVar[int]
    prompt: str
    max_tokens: int
    temperature: float
    top_p: float
    top_k: int
    def __init__(self, prompt: _Optional[str] = ..., max_tokens: _Optional[int] = ..., temperature: _Optional[float] = ..., top_p: _Optional[float] = ..., top_k: _Optional[int] = ...) -> None: ...

class VLMResult(_message.Message):
    __slots__ = ("text", "prompt_tokens", "completion_tokens", "total_tokens", "processing_time_ms", "tokens_per_second")
    TEXT_FIELD_NUMBER: _ClassVar[int]
    PROMPT_TOKENS_FIELD_NUMBER: _ClassVar[int]
    COMPLETION_TOKENS_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TOKENS_FIELD_NUMBER: _ClassVar[int]
    PROCESSING_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_PER_SECOND_FIELD_NUMBER: _ClassVar[int]
    text: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    processing_time_ms: int
    tokens_per_second: float
    def __init__(self, text: _Optional[str] = ..., prompt_tokens: _Optional[int] = ..., completion_tokens: _Optional[int] = ..., total_tokens: _Optional[int] = ..., processing_time_ms: _Optional[int] = ..., tokens_per_second: _Optional[float] = ...) -> None: ...
