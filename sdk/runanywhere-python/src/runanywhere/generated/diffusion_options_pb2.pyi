import model_types_pb2 as _model_types_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class DiffusionMode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DIFFUSION_MODE_UNSPECIFIED: _ClassVar[DiffusionMode]
    DIFFUSION_MODE_TEXT_TO_IMAGE: _ClassVar[DiffusionMode]
    DIFFUSION_MODE_IMAGE_TO_IMAGE: _ClassVar[DiffusionMode]
    DIFFUSION_MODE_INPAINTING: _ClassVar[DiffusionMode]

class DiffusionScheduler(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DIFFUSION_SCHEDULER_UNSPECIFIED: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_DPMPP_2M: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_DDIM: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_DDPM: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_EULER: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_EULER_A: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_PNDM: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_LMS: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_LCM: _ClassVar[DiffusionScheduler]
    DIFFUSION_SCHEDULER_DPMPP_2M_SDE: _ClassVar[DiffusionScheduler]

class DiffusionModelVariant(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DIFFUSION_MODEL_VARIANT_UNSPECIFIED: _ClassVar[DiffusionModelVariant]
    DIFFUSION_MODEL_VARIANT_SD_1_5: _ClassVar[DiffusionModelVariant]
    DIFFUSION_MODEL_VARIANT_SD_2_1: _ClassVar[DiffusionModelVariant]
    DIFFUSION_MODEL_VARIANT_SDXL: _ClassVar[DiffusionModelVariant]
    DIFFUSION_MODEL_VARIANT_SDXL_TURBO: _ClassVar[DiffusionModelVariant]
    DIFFUSION_MODEL_VARIANT_SDXS: _ClassVar[DiffusionModelVariant]
    DIFFUSION_MODEL_VARIANT_LCM: _ClassVar[DiffusionModelVariant]

class DiffusionTokenizerSourceKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED: _ClassVar[DiffusionTokenizerSourceKind]
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15: _ClassVar[DiffusionTokenizerSourceKind]
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2: _ClassVar[DiffusionTokenizerSourceKind]
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL: _ClassVar[DiffusionTokenizerSourceKind]
    DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM: _ClassVar[DiffusionTokenizerSourceKind]
DIFFUSION_MODE_UNSPECIFIED: DiffusionMode
DIFFUSION_MODE_TEXT_TO_IMAGE: DiffusionMode
DIFFUSION_MODE_IMAGE_TO_IMAGE: DiffusionMode
DIFFUSION_MODE_INPAINTING: DiffusionMode
DIFFUSION_SCHEDULER_UNSPECIFIED: DiffusionScheduler
DIFFUSION_SCHEDULER_DPMPP_2M: DiffusionScheduler
DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS: DiffusionScheduler
DIFFUSION_SCHEDULER_DDIM: DiffusionScheduler
DIFFUSION_SCHEDULER_DDPM: DiffusionScheduler
DIFFUSION_SCHEDULER_EULER: DiffusionScheduler
DIFFUSION_SCHEDULER_EULER_A: DiffusionScheduler
DIFFUSION_SCHEDULER_PNDM: DiffusionScheduler
DIFFUSION_SCHEDULER_LMS: DiffusionScheduler
DIFFUSION_SCHEDULER_LCM: DiffusionScheduler
DIFFUSION_SCHEDULER_DPMPP_2M_SDE: DiffusionScheduler
DIFFUSION_MODEL_VARIANT_UNSPECIFIED: DiffusionModelVariant
DIFFUSION_MODEL_VARIANT_SD_1_5: DiffusionModelVariant
DIFFUSION_MODEL_VARIANT_SD_2_1: DiffusionModelVariant
DIFFUSION_MODEL_VARIANT_SDXL: DiffusionModelVariant
DIFFUSION_MODEL_VARIANT_SDXL_TURBO: DiffusionModelVariant
DIFFUSION_MODEL_VARIANT_SDXS: DiffusionModelVariant
DIFFUSION_MODEL_VARIANT_LCM: DiffusionModelVariant
DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED: DiffusionTokenizerSourceKind
DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15: DiffusionTokenizerSourceKind
DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2: DiffusionTokenizerSourceKind
DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL: DiffusionTokenizerSourceKind
DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM: DiffusionTokenizerSourceKind

class DiffusionTokenizerSource(_message.Message):
    __slots__ = ("kind", "custom_path", "auto_download")
    KIND_FIELD_NUMBER: _ClassVar[int]
    CUSTOM_PATH_FIELD_NUMBER: _ClassVar[int]
    AUTO_DOWNLOAD_FIELD_NUMBER: _ClassVar[int]
    kind: DiffusionTokenizerSourceKind
    custom_path: str
    auto_download: bool
    def __init__(self, kind: _Optional[_Union[DiffusionTokenizerSourceKind, str]] = ..., custom_path: _Optional[str] = ..., auto_download: _Optional[bool] = ...) -> None: ...

class DiffusionConfiguration(_message.Message):
    __slots__ = ("model_variant", "tokenizer_source", "enable_safety_checker", "max_memory_mb", "model_id", "preferred_framework", "reduce_memory")
    MODEL_VARIANT_FIELD_NUMBER: _ClassVar[int]
    TOKENIZER_SOURCE_FIELD_NUMBER: _ClassVar[int]
    ENABLE_SAFETY_CHECKER_FIELD_NUMBER: _ClassVar[int]
    MAX_MEMORY_MB_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    PREFERRED_FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    REDUCE_MEMORY_FIELD_NUMBER: _ClassVar[int]
    model_variant: DiffusionModelVariant
    tokenizer_source: DiffusionTokenizerSource
    enable_safety_checker: bool
    max_memory_mb: int
    model_id: str
    preferred_framework: _model_types_pb2.InferenceFramework
    reduce_memory: bool
    def __init__(self, model_variant: _Optional[_Union[DiffusionModelVariant, str]] = ..., tokenizer_source: _Optional[_Union[DiffusionTokenizerSource, _Mapping]] = ..., enable_safety_checker: _Optional[bool] = ..., max_memory_mb: _Optional[int] = ..., model_id: _Optional[str] = ..., preferred_framework: _Optional[_Union[_model_types_pb2.InferenceFramework, str]] = ..., reduce_memory: _Optional[bool] = ...) -> None: ...

class DiffusionConfig(_message.Message):
    __slots__ = ("model_path", "model_id", "model_name", "configuration")
    MODEL_PATH_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_NAME_FIELD_NUMBER: _ClassVar[int]
    CONFIGURATION_FIELD_NUMBER: _ClassVar[int]
    model_path: str
    model_id: str
    model_name: str
    configuration: DiffusionConfiguration
    def __init__(self, model_path: _Optional[str] = ..., model_id: _Optional[str] = ..., model_name: _Optional[str] = ..., configuration: _Optional[_Union[DiffusionConfiguration, _Mapping]] = ...) -> None: ...

class DiffusionGenerationOptions(_message.Message):
    __slots__ = ("prompt", "negative_prompt", "width", "height", "num_inference_steps", "guidance_scale", "seed", "scheduler", "mode", "input_image", "mask_image", "denoise_strength", "report_intermediate_images", "progress_stride", "input_image_width", "input_image_height")
    PROMPT_FIELD_NUMBER: _ClassVar[int]
    NEGATIVE_PROMPT_FIELD_NUMBER: _ClassVar[int]
    WIDTH_FIELD_NUMBER: _ClassVar[int]
    HEIGHT_FIELD_NUMBER: _ClassVar[int]
    NUM_INFERENCE_STEPS_FIELD_NUMBER: _ClassVar[int]
    GUIDANCE_SCALE_FIELD_NUMBER: _ClassVar[int]
    SEED_FIELD_NUMBER: _ClassVar[int]
    SCHEDULER_FIELD_NUMBER: _ClassVar[int]
    MODE_FIELD_NUMBER: _ClassVar[int]
    INPUT_IMAGE_FIELD_NUMBER: _ClassVar[int]
    MASK_IMAGE_FIELD_NUMBER: _ClassVar[int]
    DENOISE_STRENGTH_FIELD_NUMBER: _ClassVar[int]
    REPORT_INTERMEDIATE_IMAGES_FIELD_NUMBER: _ClassVar[int]
    PROGRESS_STRIDE_FIELD_NUMBER: _ClassVar[int]
    INPUT_IMAGE_WIDTH_FIELD_NUMBER: _ClassVar[int]
    INPUT_IMAGE_HEIGHT_FIELD_NUMBER: _ClassVar[int]
    prompt: str
    negative_prompt: str
    width: int
    height: int
    num_inference_steps: int
    guidance_scale: float
    seed: int
    scheduler: DiffusionScheduler
    mode: DiffusionMode
    input_image: bytes
    mask_image: bytes
    denoise_strength: float
    report_intermediate_images: bool
    progress_stride: int
    input_image_width: int
    input_image_height: int
    def __init__(self, prompt: _Optional[str] = ..., negative_prompt: _Optional[str] = ..., width: _Optional[int] = ..., height: _Optional[int] = ..., num_inference_steps: _Optional[int] = ..., guidance_scale: _Optional[float] = ..., seed: _Optional[int] = ..., scheduler: _Optional[_Union[DiffusionScheduler, str]] = ..., mode: _Optional[_Union[DiffusionMode, str]] = ..., input_image: _Optional[bytes] = ..., mask_image: _Optional[bytes] = ..., denoise_strength: _Optional[float] = ..., report_intermediate_images: _Optional[bool] = ..., progress_stride: _Optional[int] = ..., input_image_width: _Optional[int] = ..., input_image_height: _Optional[int] = ...) -> None: ...

class DiffusionProgress(_message.Message):
    __slots__ = ("progress_percent", "current_step", "total_steps", "stage", "intermediate_image_data", "intermediate_image_width", "intermediate_image_height")
    PROGRESS_PERCENT_FIELD_NUMBER: _ClassVar[int]
    CURRENT_STEP_FIELD_NUMBER: _ClassVar[int]
    TOTAL_STEPS_FIELD_NUMBER: _ClassVar[int]
    STAGE_FIELD_NUMBER: _ClassVar[int]
    INTERMEDIATE_IMAGE_DATA_FIELD_NUMBER: _ClassVar[int]
    INTERMEDIATE_IMAGE_WIDTH_FIELD_NUMBER: _ClassVar[int]
    INTERMEDIATE_IMAGE_HEIGHT_FIELD_NUMBER: _ClassVar[int]
    progress_percent: float
    current_step: int
    total_steps: int
    stage: str
    intermediate_image_data: bytes
    intermediate_image_width: int
    intermediate_image_height: int
    def __init__(self, progress_percent: _Optional[float] = ..., current_step: _Optional[int] = ..., total_steps: _Optional[int] = ..., stage: _Optional[str] = ..., intermediate_image_data: _Optional[bytes] = ..., intermediate_image_width: _Optional[int] = ..., intermediate_image_height: _Optional[int] = ...) -> None: ...

class DiffusionResult(_message.Message):
    __slots__ = ("image_data", "width", "height", "seed_used", "total_time_ms", "safety_flag", "used_scheduler", "error_message", "error_code")
    IMAGE_DATA_FIELD_NUMBER: _ClassVar[int]
    WIDTH_FIELD_NUMBER: _ClassVar[int]
    HEIGHT_FIELD_NUMBER: _ClassVar[int]
    SEED_USED_FIELD_NUMBER: _ClassVar[int]
    TOTAL_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    SAFETY_FLAG_FIELD_NUMBER: _ClassVar[int]
    USED_SCHEDULER_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    image_data: bytes
    width: int
    height: int
    seed_used: int
    total_time_ms: int
    safety_flag: bool
    used_scheduler: DiffusionScheduler
    error_message: str
    error_code: int
    def __init__(self, image_data: _Optional[bytes] = ..., width: _Optional[int] = ..., height: _Optional[int] = ..., seed_used: _Optional[int] = ..., total_time_ms: _Optional[int] = ..., safety_flag: _Optional[bool] = ..., used_scheduler: _Optional[_Union[DiffusionScheduler, str]] = ..., error_message: _Optional[str] = ..., error_code: _Optional[int] = ...) -> None: ...

class DiffusionCapabilities(_message.Message):
    __slots__ = ("supported_variants", "supported_schedulers", "max_resolution_px", "supported_modes", "max_width_px", "max_height_px", "supports_intermediate_images", "supports_safety_checker", "is_ready", "current_model", "safety_checker_enabled")
    SUPPORTED_VARIANTS_FIELD_NUMBER: _ClassVar[int]
    SUPPORTED_SCHEDULERS_FIELD_NUMBER: _ClassVar[int]
    MAX_RESOLUTION_PX_FIELD_NUMBER: _ClassVar[int]
    SUPPORTED_MODES_FIELD_NUMBER: _ClassVar[int]
    MAX_WIDTH_PX_FIELD_NUMBER: _ClassVar[int]
    MAX_HEIGHT_PX_FIELD_NUMBER: _ClassVar[int]
    SUPPORTS_INTERMEDIATE_IMAGES_FIELD_NUMBER: _ClassVar[int]
    SUPPORTS_SAFETY_CHECKER_FIELD_NUMBER: _ClassVar[int]
    IS_READY_FIELD_NUMBER: _ClassVar[int]
    CURRENT_MODEL_FIELD_NUMBER: _ClassVar[int]
    SAFETY_CHECKER_ENABLED_FIELD_NUMBER: _ClassVar[int]
    supported_variants: _containers.RepeatedScalarFieldContainer[DiffusionModelVariant]
    supported_schedulers: _containers.RepeatedScalarFieldContainer[DiffusionScheduler]
    max_resolution_px: int
    supported_modes: _containers.RepeatedScalarFieldContainer[DiffusionMode]
    max_width_px: int
    max_height_px: int
    supports_intermediate_images: bool
    supports_safety_checker: bool
    is_ready: bool
    current_model: str
    safety_checker_enabled: bool
    def __init__(self, supported_variants: _Optional[_Iterable[_Union[DiffusionModelVariant, str]]] = ..., supported_schedulers: _Optional[_Iterable[_Union[DiffusionScheduler, str]]] = ..., max_resolution_px: _Optional[int] = ..., supported_modes: _Optional[_Iterable[_Union[DiffusionMode, str]]] = ..., max_width_px: _Optional[int] = ..., max_height_px: _Optional[int] = ..., supports_intermediate_images: _Optional[bool] = ..., supports_safety_checker: _Optional[bool] = ..., is_ready: _Optional[bool] = ..., current_model: _Optional[str] = ..., safety_checker_enabled: _Optional[bool] = ...) -> None: ...
