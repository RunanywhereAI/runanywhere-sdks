from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class AudioFormat(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    AUDIO_FORMAT_UNSPECIFIED: _ClassVar[AudioFormat]
    AUDIO_FORMAT_PCM: _ClassVar[AudioFormat]
    AUDIO_FORMAT_WAV: _ClassVar[AudioFormat]
    AUDIO_FORMAT_MP3: _ClassVar[AudioFormat]
    AUDIO_FORMAT_OPUS: _ClassVar[AudioFormat]
    AUDIO_FORMAT_AAC: _ClassVar[AudioFormat]
    AUDIO_FORMAT_FLAC: _ClassVar[AudioFormat]
    AUDIO_FORMAT_OGG: _ClassVar[AudioFormat]
    AUDIO_FORMAT_M4A: _ClassVar[AudioFormat]
    AUDIO_FORMAT_PCM_S16LE: _ClassVar[AudioFormat]

class ModelFormat(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MODEL_FORMAT_UNSPECIFIED: _ClassVar[ModelFormat]
    MODEL_FORMAT_GGUF: _ClassVar[ModelFormat]
    MODEL_FORMAT_GGML: _ClassVar[ModelFormat]
    MODEL_FORMAT_ONNX: _ClassVar[ModelFormat]
    MODEL_FORMAT_ORT: _ClassVar[ModelFormat]
    MODEL_FORMAT_BIN: _ClassVar[ModelFormat]
    MODEL_FORMAT_COREML: _ClassVar[ModelFormat]
    MODEL_FORMAT_MLMODEL: _ClassVar[ModelFormat]
    MODEL_FORMAT_MLPACKAGE: _ClassVar[ModelFormat]
    MODEL_FORMAT_TFLITE: _ClassVar[ModelFormat]
    MODEL_FORMAT_SAFETENSORS: _ClassVar[ModelFormat]
    MODEL_FORMAT_QNN_CONTEXT: _ClassVar[ModelFormat]
    MODEL_FORMAT_ZIP: _ClassVar[ModelFormat]
    MODEL_FORMAT_FOLDER: _ClassVar[ModelFormat]
    MODEL_FORMAT_PROPRIETARY: _ClassVar[ModelFormat]
    MODEL_FORMAT_UNKNOWN: _ClassVar[ModelFormat]

class InferenceFramework(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    INFERENCE_FRAMEWORK_UNSPECIFIED: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_ONNX: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_LLAMA_CPP: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_FOUNDATION_MODELS: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_SYSTEM_TTS: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_FLUID_AUDIO: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_COREML: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_MLX: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_WHISPERKIT_COREML: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_METALRT: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_GENIE: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_TFLITE: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_EXECUTORCH: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_MEDIAPIPE: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_MLC: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_PICO_LLM: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_PIPER_TTS: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_WHISPERKIT: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_OPENAI_WHISPER: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_BUILT_IN: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_NONE: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_UNKNOWN: _ClassVar[InferenceFramework]
    INFERENCE_FRAMEWORK_SHERPA: _ClassVar[InferenceFramework]

class ModelCategory(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MODEL_CATEGORY_UNSPECIFIED: _ClassVar[ModelCategory]
    MODEL_CATEGORY_LANGUAGE: _ClassVar[ModelCategory]
    MODEL_CATEGORY_SPEECH_RECOGNITION: _ClassVar[ModelCategory]
    MODEL_CATEGORY_SPEECH_SYNTHESIS: _ClassVar[ModelCategory]
    MODEL_CATEGORY_VISION: _ClassVar[ModelCategory]
    MODEL_CATEGORY_IMAGE_GENERATION: _ClassVar[ModelCategory]
    MODEL_CATEGORY_MULTIMODAL: _ClassVar[ModelCategory]
    MODEL_CATEGORY_AUDIO: _ClassVar[ModelCategory]
    MODEL_CATEGORY_EMBEDDING: _ClassVar[ModelCategory]
    MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION: _ClassVar[ModelCategory]

class SDKEnvironment(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SDK_ENVIRONMENT_UNSPECIFIED: _ClassVar[SDKEnvironment]
    SDK_ENVIRONMENT_DEVELOPMENT: _ClassVar[SDKEnvironment]
    SDK_ENVIRONMENT_STAGING: _ClassVar[SDKEnvironment]
    SDK_ENVIRONMENT_PRODUCTION: _ClassVar[SDKEnvironment]

class ModelSource(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MODEL_SOURCE_UNSPECIFIED: _ClassVar[ModelSource]
    MODEL_SOURCE_REMOTE: _ClassVar[ModelSource]
    MODEL_SOURCE_LOCAL: _ClassVar[ModelSource]

class ArchiveType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ARCHIVE_TYPE_UNSPECIFIED: _ClassVar[ArchiveType]
    ARCHIVE_TYPE_ZIP: _ClassVar[ArchiveType]
    ARCHIVE_TYPE_TAR_BZ2: _ClassVar[ArchiveType]
    ARCHIVE_TYPE_TAR_GZ: _ClassVar[ArchiveType]
    ARCHIVE_TYPE_TAR_XZ: _ClassVar[ArchiveType]

class ArchiveStructure(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ARCHIVE_STRUCTURE_UNSPECIFIED: _ClassVar[ArchiveStructure]
    ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED: _ClassVar[ArchiveStructure]
    ARCHIVE_STRUCTURE_DIRECTORY_BASED: _ClassVar[ArchiveStructure]
    ARCHIVE_STRUCTURE_NESTED_DIRECTORY: _ClassVar[ArchiveStructure]
    ARCHIVE_STRUCTURE_UNKNOWN: _ClassVar[ArchiveStructure]
AUDIO_FORMAT_UNSPECIFIED: AudioFormat
AUDIO_FORMAT_PCM: AudioFormat
AUDIO_FORMAT_WAV: AudioFormat
AUDIO_FORMAT_MP3: AudioFormat
AUDIO_FORMAT_OPUS: AudioFormat
AUDIO_FORMAT_AAC: AudioFormat
AUDIO_FORMAT_FLAC: AudioFormat
AUDIO_FORMAT_OGG: AudioFormat
AUDIO_FORMAT_M4A: AudioFormat
AUDIO_FORMAT_PCM_S16LE: AudioFormat
MODEL_FORMAT_UNSPECIFIED: ModelFormat
MODEL_FORMAT_GGUF: ModelFormat
MODEL_FORMAT_GGML: ModelFormat
MODEL_FORMAT_ONNX: ModelFormat
MODEL_FORMAT_ORT: ModelFormat
MODEL_FORMAT_BIN: ModelFormat
MODEL_FORMAT_COREML: ModelFormat
MODEL_FORMAT_MLMODEL: ModelFormat
MODEL_FORMAT_MLPACKAGE: ModelFormat
MODEL_FORMAT_TFLITE: ModelFormat
MODEL_FORMAT_SAFETENSORS: ModelFormat
MODEL_FORMAT_QNN_CONTEXT: ModelFormat
MODEL_FORMAT_ZIP: ModelFormat
MODEL_FORMAT_FOLDER: ModelFormat
MODEL_FORMAT_PROPRIETARY: ModelFormat
MODEL_FORMAT_UNKNOWN: ModelFormat
INFERENCE_FRAMEWORK_UNSPECIFIED: InferenceFramework
INFERENCE_FRAMEWORK_ONNX: InferenceFramework
INFERENCE_FRAMEWORK_LLAMA_CPP: InferenceFramework
INFERENCE_FRAMEWORK_FOUNDATION_MODELS: InferenceFramework
INFERENCE_FRAMEWORK_SYSTEM_TTS: InferenceFramework
INFERENCE_FRAMEWORK_FLUID_AUDIO: InferenceFramework
INFERENCE_FRAMEWORK_COREML: InferenceFramework
INFERENCE_FRAMEWORK_MLX: InferenceFramework
INFERENCE_FRAMEWORK_WHISPERKIT_COREML: InferenceFramework
INFERENCE_FRAMEWORK_METALRT: InferenceFramework
INFERENCE_FRAMEWORK_GENIE: InferenceFramework
INFERENCE_FRAMEWORK_TFLITE: InferenceFramework
INFERENCE_FRAMEWORK_EXECUTORCH: InferenceFramework
INFERENCE_FRAMEWORK_MEDIAPIPE: InferenceFramework
INFERENCE_FRAMEWORK_MLC: InferenceFramework
INFERENCE_FRAMEWORK_PICO_LLM: InferenceFramework
INFERENCE_FRAMEWORK_PIPER_TTS: InferenceFramework
INFERENCE_FRAMEWORK_WHISPERKIT: InferenceFramework
INFERENCE_FRAMEWORK_OPENAI_WHISPER: InferenceFramework
INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS: InferenceFramework
INFERENCE_FRAMEWORK_BUILT_IN: InferenceFramework
INFERENCE_FRAMEWORK_NONE: InferenceFramework
INFERENCE_FRAMEWORK_UNKNOWN: InferenceFramework
INFERENCE_FRAMEWORK_SHERPA: InferenceFramework
MODEL_CATEGORY_UNSPECIFIED: ModelCategory
MODEL_CATEGORY_LANGUAGE: ModelCategory
MODEL_CATEGORY_SPEECH_RECOGNITION: ModelCategory
MODEL_CATEGORY_SPEECH_SYNTHESIS: ModelCategory
MODEL_CATEGORY_VISION: ModelCategory
MODEL_CATEGORY_IMAGE_GENERATION: ModelCategory
MODEL_CATEGORY_MULTIMODAL: ModelCategory
MODEL_CATEGORY_AUDIO: ModelCategory
MODEL_CATEGORY_EMBEDDING: ModelCategory
MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION: ModelCategory
SDK_ENVIRONMENT_UNSPECIFIED: SDKEnvironment
SDK_ENVIRONMENT_DEVELOPMENT: SDKEnvironment
SDK_ENVIRONMENT_STAGING: SDKEnvironment
SDK_ENVIRONMENT_PRODUCTION: SDKEnvironment
MODEL_SOURCE_UNSPECIFIED: ModelSource
MODEL_SOURCE_REMOTE: ModelSource
MODEL_SOURCE_LOCAL: ModelSource
ARCHIVE_TYPE_UNSPECIFIED: ArchiveType
ARCHIVE_TYPE_ZIP: ArchiveType
ARCHIVE_TYPE_TAR_BZ2: ArchiveType
ARCHIVE_TYPE_TAR_GZ: ArchiveType
ARCHIVE_TYPE_TAR_XZ: ArchiveType
ARCHIVE_STRUCTURE_UNSPECIFIED: ArchiveStructure
ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED: ArchiveStructure
ARCHIVE_STRUCTURE_DIRECTORY_BASED: ArchiveStructure
ARCHIVE_STRUCTURE_NESTED_DIRECTORY: ArchiveStructure
ARCHIVE_STRUCTURE_UNKNOWN: ArchiveStructure

class ModelInfo(_message.Message):
    __slots__ = ("id", "name", "category", "format", "framework", "download_url", "local_path", "download_size_bytes", "context_length", "supports_thinking", "supports_lora", "description", "source", "created_at_unix_ms", "updated_at_unix_ms", "single_file", "archive", "multi_file", "custom_strategy_id", "built_in")
    ID_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    CATEGORY_FIELD_NUMBER: _ClassVar[int]
    FORMAT_FIELD_NUMBER: _ClassVar[int]
    FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    DOWNLOAD_URL_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    DOWNLOAD_SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    CONTEXT_LENGTH_FIELD_NUMBER: _ClassVar[int]
    SUPPORTS_THINKING_FIELD_NUMBER: _ClassVar[int]
    SUPPORTS_LORA_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    SOURCE_FIELD_NUMBER: _ClassVar[int]
    CREATED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    UPDATED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    SINGLE_FILE_FIELD_NUMBER: _ClassVar[int]
    ARCHIVE_FIELD_NUMBER: _ClassVar[int]
    MULTI_FILE_FIELD_NUMBER: _ClassVar[int]
    CUSTOM_STRATEGY_ID_FIELD_NUMBER: _ClassVar[int]
    BUILT_IN_FIELD_NUMBER: _ClassVar[int]
    id: str
    name: str
    category: ModelCategory
    format: ModelFormat
    framework: InferenceFramework
    download_url: str
    local_path: str
    download_size_bytes: int
    context_length: int
    supports_thinking: bool
    supports_lora: bool
    description: str
    source: ModelSource
    created_at_unix_ms: int
    updated_at_unix_ms: int
    single_file: SingleFileArtifact
    archive: ArchiveArtifact
    multi_file: MultiFileArtifact
    custom_strategy_id: str
    built_in: bool
    def __init__(self, id: _Optional[str] = ..., name: _Optional[str] = ..., category: _Optional[_Union[ModelCategory, str]] = ..., format: _Optional[_Union[ModelFormat, str]] = ..., framework: _Optional[_Union[InferenceFramework, str]] = ..., download_url: _Optional[str] = ..., local_path: _Optional[str] = ..., download_size_bytes: _Optional[int] = ..., context_length: _Optional[int] = ..., supports_thinking: _Optional[bool] = ..., supports_lora: _Optional[bool] = ..., description: _Optional[str] = ..., source: _Optional[_Union[ModelSource, str]] = ..., created_at_unix_ms: _Optional[int] = ..., updated_at_unix_ms: _Optional[int] = ..., single_file: _Optional[_Union[SingleFileArtifact, _Mapping]] = ..., archive: _Optional[_Union[ArchiveArtifact, _Mapping]] = ..., multi_file: _Optional[_Union[MultiFileArtifact, _Mapping]] = ..., custom_strategy_id: _Optional[str] = ..., built_in: _Optional[bool] = ...) -> None: ...

class SingleFileArtifact(_message.Message):
    __slots__ = ("required_patterns", "optional_patterns")
    REQUIRED_PATTERNS_FIELD_NUMBER: _ClassVar[int]
    OPTIONAL_PATTERNS_FIELD_NUMBER: _ClassVar[int]
    required_patterns: _containers.RepeatedScalarFieldContainer[str]
    optional_patterns: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, required_patterns: _Optional[_Iterable[str]] = ..., optional_patterns: _Optional[_Iterable[str]] = ...) -> None: ...

class ArchiveArtifact(_message.Message):
    __slots__ = ("type", "structure", "required_patterns", "optional_patterns")
    TYPE_FIELD_NUMBER: _ClassVar[int]
    STRUCTURE_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_PATTERNS_FIELD_NUMBER: _ClassVar[int]
    OPTIONAL_PATTERNS_FIELD_NUMBER: _ClassVar[int]
    type: ArchiveType
    structure: ArchiveStructure
    required_patterns: _containers.RepeatedScalarFieldContainer[str]
    optional_patterns: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, type: _Optional[_Union[ArchiveType, str]] = ..., structure: _Optional[_Union[ArchiveStructure, str]] = ..., required_patterns: _Optional[_Iterable[str]] = ..., optional_patterns: _Optional[_Iterable[str]] = ...) -> None: ...

class ModelFileDescriptor(_message.Message):
    __slots__ = ("url", "filename", "is_required")
    URL_FIELD_NUMBER: _ClassVar[int]
    FILENAME_FIELD_NUMBER: _ClassVar[int]
    IS_REQUIRED_FIELD_NUMBER: _ClassVar[int]
    url: str
    filename: str
    is_required: bool
    def __init__(self, url: _Optional[str] = ..., filename: _Optional[str] = ..., is_required: _Optional[bool] = ...) -> None: ...

class MultiFileArtifact(_message.Message):
    __slots__ = ("files",)
    FILES_FIELD_NUMBER: _ClassVar[int]
    files: _containers.RepeatedCompositeFieldContainer[ModelFileDescriptor]
    def __init__(self, files: _Optional[_Iterable[_Union[ModelFileDescriptor, _Mapping]]] = ...) -> None: ...
