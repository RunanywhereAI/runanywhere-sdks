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

class ModelArtifactType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MODEL_ARTIFACT_TYPE_UNSPECIFIED: _ClassVar[ModelArtifactType]
    MODEL_ARTIFACT_TYPE_SINGLE_FILE: _ClassVar[ModelArtifactType]
    MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE: _ClassVar[ModelArtifactType]
    MODEL_ARTIFACT_TYPE_DIRECTORY: _ClassVar[ModelArtifactType]
    MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE: _ClassVar[ModelArtifactType]
    MODEL_ARTIFACT_TYPE_CUSTOM: _ClassVar[ModelArtifactType]

class ModelRegistryStatus(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MODEL_REGISTRY_STATUS_UNSPECIFIED: _ClassVar[ModelRegistryStatus]
    MODEL_REGISTRY_STATUS_REGISTERED: _ClassVar[ModelRegistryStatus]
    MODEL_REGISTRY_STATUS_DOWNLOADING: _ClassVar[ModelRegistryStatus]
    MODEL_REGISTRY_STATUS_DOWNLOADED: _ClassVar[ModelRegistryStatus]
    MODEL_REGISTRY_STATUS_LOADING: _ClassVar[ModelRegistryStatus]
    MODEL_REGISTRY_STATUS_LOADED: _ClassVar[ModelRegistryStatus]
    MODEL_REGISTRY_STATUS_ERROR: _ClassVar[ModelRegistryStatus]

class ModelQuerySortField(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MODEL_QUERY_SORT_FIELD_UNSPECIFIED: _ClassVar[ModelQuerySortField]
    MODEL_QUERY_SORT_FIELD_NAME: _ClassVar[ModelQuerySortField]
    MODEL_QUERY_SORT_FIELD_CREATED_AT_UNIX_MS: _ClassVar[ModelQuerySortField]
    MODEL_QUERY_SORT_FIELD_UPDATED_AT_UNIX_MS: _ClassVar[ModelQuerySortField]
    MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES: _ClassVar[ModelQuerySortField]
    MODEL_QUERY_SORT_FIELD_LAST_USED_AT_UNIX_MS: _ClassVar[ModelQuerySortField]
    MODEL_QUERY_SORT_FIELD_USAGE_COUNT: _ClassVar[ModelQuerySortField]

class ModelQuerySortOrder(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MODEL_QUERY_SORT_ORDER_UNSPECIFIED: _ClassVar[ModelQuerySortOrder]
    MODEL_QUERY_SORT_ORDER_ASCENDING: _ClassVar[ModelQuerySortOrder]
    MODEL_QUERY_SORT_ORDER_DESCENDING: _ClassVar[ModelQuerySortOrder]

class ModelFileRole(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MODEL_FILE_ROLE_UNSPECIFIED: _ClassVar[ModelFileRole]
    MODEL_FILE_ROLE_PRIMARY_MODEL: _ClassVar[ModelFileRole]
    MODEL_FILE_ROLE_COMPANION: _ClassVar[ModelFileRole]
    MODEL_FILE_ROLE_VISION_PROJECTOR: _ClassVar[ModelFileRole]
    MODEL_FILE_ROLE_TOKENIZER: _ClassVar[ModelFileRole]
    MODEL_FILE_ROLE_CONFIG: _ClassVar[ModelFileRole]
    MODEL_FILE_ROLE_VOCABULARY: _ClassVar[ModelFileRole]
    MODEL_FILE_ROLE_MERGES: _ClassVar[ModelFileRole]
    MODEL_FILE_ROLE_LABELS: _ClassVar[ModelFileRole]

class AccelerationPreference(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ACCELERATION_PREFERENCE_UNSPECIFIED: _ClassVar[AccelerationPreference]
    ACCELERATION_PREFERENCE_AUTO: _ClassVar[AccelerationPreference]
    ACCELERATION_PREFERENCE_CPU: _ClassVar[AccelerationPreference]
    ACCELERATION_PREFERENCE_GPU: _ClassVar[AccelerationPreference]
    ACCELERATION_PREFERENCE_NPU: _ClassVar[AccelerationPreference]
    ACCELERATION_PREFERENCE_WEBGPU: _ClassVar[AccelerationPreference]
    ACCELERATION_PREFERENCE_METAL: _ClassVar[AccelerationPreference]
    ACCELERATION_PREFERENCE_VULKAN: _ClassVar[AccelerationPreference]

class RoutingPolicy(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ROUTING_POLICY_UNSPECIFIED: _ClassVar[RoutingPolicy]
    ROUTING_POLICY_PREFER_LOCAL: _ClassVar[RoutingPolicy]
    ROUTING_POLICY_PREFER_CLOUD: _ClassVar[RoutingPolicy]
    ROUTING_POLICY_COST_OPTIMIZED: _ClassVar[RoutingPolicy]
    ROUTING_POLICY_LATENCY_OPTIMIZED: _ClassVar[RoutingPolicy]
    ROUTING_POLICY_MANUAL: _ClassVar[RoutingPolicy]
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
MODEL_ARTIFACT_TYPE_UNSPECIFIED: ModelArtifactType
MODEL_ARTIFACT_TYPE_SINGLE_FILE: ModelArtifactType
MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE: ModelArtifactType
MODEL_ARTIFACT_TYPE_DIRECTORY: ModelArtifactType
MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE: ModelArtifactType
MODEL_ARTIFACT_TYPE_CUSTOM: ModelArtifactType
MODEL_REGISTRY_STATUS_UNSPECIFIED: ModelRegistryStatus
MODEL_REGISTRY_STATUS_REGISTERED: ModelRegistryStatus
MODEL_REGISTRY_STATUS_DOWNLOADING: ModelRegistryStatus
MODEL_REGISTRY_STATUS_DOWNLOADED: ModelRegistryStatus
MODEL_REGISTRY_STATUS_LOADING: ModelRegistryStatus
MODEL_REGISTRY_STATUS_LOADED: ModelRegistryStatus
MODEL_REGISTRY_STATUS_ERROR: ModelRegistryStatus
MODEL_QUERY_SORT_FIELD_UNSPECIFIED: ModelQuerySortField
MODEL_QUERY_SORT_FIELD_NAME: ModelQuerySortField
MODEL_QUERY_SORT_FIELD_CREATED_AT_UNIX_MS: ModelQuerySortField
MODEL_QUERY_SORT_FIELD_UPDATED_AT_UNIX_MS: ModelQuerySortField
MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES: ModelQuerySortField
MODEL_QUERY_SORT_FIELD_LAST_USED_AT_UNIX_MS: ModelQuerySortField
MODEL_QUERY_SORT_FIELD_USAGE_COUNT: ModelQuerySortField
MODEL_QUERY_SORT_ORDER_UNSPECIFIED: ModelQuerySortOrder
MODEL_QUERY_SORT_ORDER_ASCENDING: ModelQuerySortOrder
MODEL_QUERY_SORT_ORDER_DESCENDING: ModelQuerySortOrder
MODEL_FILE_ROLE_UNSPECIFIED: ModelFileRole
MODEL_FILE_ROLE_PRIMARY_MODEL: ModelFileRole
MODEL_FILE_ROLE_COMPANION: ModelFileRole
MODEL_FILE_ROLE_VISION_PROJECTOR: ModelFileRole
MODEL_FILE_ROLE_TOKENIZER: ModelFileRole
MODEL_FILE_ROLE_CONFIG: ModelFileRole
MODEL_FILE_ROLE_VOCABULARY: ModelFileRole
MODEL_FILE_ROLE_MERGES: ModelFileRole
MODEL_FILE_ROLE_LABELS: ModelFileRole
ACCELERATION_PREFERENCE_UNSPECIFIED: AccelerationPreference
ACCELERATION_PREFERENCE_AUTO: AccelerationPreference
ACCELERATION_PREFERENCE_CPU: AccelerationPreference
ACCELERATION_PREFERENCE_GPU: AccelerationPreference
ACCELERATION_PREFERENCE_NPU: AccelerationPreference
ACCELERATION_PREFERENCE_WEBGPU: AccelerationPreference
ACCELERATION_PREFERENCE_METAL: AccelerationPreference
ACCELERATION_PREFERENCE_VULKAN: AccelerationPreference
ROUTING_POLICY_UNSPECIFIED: RoutingPolicy
ROUTING_POLICY_PREFER_LOCAL: RoutingPolicy
ROUTING_POLICY_PREFER_CLOUD: RoutingPolicy
ROUTING_POLICY_COST_OPTIMIZED: RoutingPolicy
ROUTING_POLICY_LATENCY_OPTIMIZED: RoutingPolicy
ROUTING_POLICY_MANUAL: RoutingPolicy

class ModelThinkingTagPattern(_message.Message):
    __slots__ = ("open_tag", "close_tag")
    OPEN_TAG_FIELD_NUMBER: _ClassVar[int]
    CLOSE_TAG_FIELD_NUMBER: _ClassVar[int]
    open_tag: str
    close_tag: str
    def __init__(self, open_tag: _Optional[str] = ..., close_tag: _Optional[str] = ...) -> None: ...

class ModelInfoMetadata(_message.Message):
    __slots__ = ("description", "author", "license", "tags", "version")
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    AUTHOR_FIELD_NUMBER: _ClassVar[int]
    LICENSE_FIELD_NUMBER: _ClassVar[int]
    TAGS_FIELD_NUMBER: _ClassVar[int]
    VERSION_FIELD_NUMBER: _ClassVar[int]
    description: str
    author: str
    license: str
    tags: _containers.RepeatedScalarFieldContainer[str]
    version: str
    def __init__(self, description: _Optional[str] = ..., author: _Optional[str] = ..., license: _Optional[str] = ..., tags: _Optional[_Iterable[str]] = ..., version: _Optional[str] = ...) -> None: ...

class ModelRuntimeCompatibility(_message.Message):
    __slots__ = ("compatible_frameworks", "compatible_formats")
    COMPATIBLE_FRAMEWORKS_FIELD_NUMBER: _ClassVar[int]
    COMPATIBLE_FORMATS_FIELD_NUMBER: _ClassVar[int]
    compatible_frameworks: _containers.RepeatedScalarFieldContainer[InferenceFramework]
    compatible_formats: _containers.RepeatedScalarFieldContainer[ModelFormat]
    def __init__(self, compatible_frameworks: _Optional[_Iterable[_Union[InferenceFramework, str]]] = ..., compatible_formats: _Optional[_Iterable[_Union[ModelFormat, str]]] = ...) -> None: ...

class ModelInfo(_message.Message):
    __slots__ = ("id", "name", "category", "format", "framework", "download_url", "local_path", "download_size_bytes", "context_length", "supports_thinking", "supports_lora", "description", "source", "created_at_unix_ms", "updated_at_unix_ms", "memory_required_bytes", "checksum_sha256", "thinking_pattern", "metadata", "single_file", "archive", "multi_file", "custom_strategy_id", "built_in", "artifact_type", "expected_files", "acceleration_preference", "routing_policy", "compatibility", "preferred_framework", "registry_status", "is_downloaded", "is_available", "last_used_at_unix_ms", "usage_count", "sync_pending", "status_message")
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
    MEMORY_REQUIRED_BYTES_FIELD_NUMBER: _ClassVar[int]
    CHECKSUM_SHA256_FIELD_NUMBER: _ClassVar[int]
    THINKING_PATTERN_FIELD_NUMBER: _ClassVar[int]
    METADATA_FIELD_NUMBER: _ClassVar[int]
    SINGLE_FILE_FIELD_NUMBER: _ClassVar[int]
    ARCHIVE_FIELD_NUMBER: _ClassVar[int]
    MULTI_FILE_FIELD_NUMBER: _ClassVar[int]
    CUSTOM_STRATEGY_ID_FIELD_NUMBER: _ClassVar[int]
    BUILT_IN_FIELD_NUMBER: _ClassVar[int]
    ARTIFACT_TYPE_FIELD_NUMBER: _ClassVar[int]
    EXPECTED_FILES_FIELD_NUMBER: _ClassVar[int]
    ACCELERATION_PREFERENCE_FIELD_NUMBER: _ClassVar[int]
    ROUTING_POLICY_FIELD_NUMBER: _ClassVar[int]
    COMPATIBILITY_FIELD_NUMBER: _ClassVar[int]
    PREFERRED_FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    REGISTRY_STATUS_FIELD_NUMBER: _ClassVar[int]
    IS_DOWNLOADED_FIELD_NUMBER: _ClassVar[int]
    IS_AVAILABLE_FIELD_NUMBER: _ClassVar[int]
    LAST_USED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    USAGE_COUNT_FIELD_NUMBER: _ClassVar[int]
    SYNC_PENDING_FIELD_NUMBER: _ClassVar[int]
    STATUS_MESSAGE_FIELD_NUMBER: _ClassVar[int]
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
    memory_required_bytes: int
    checksum_sha256: str
    thinking_pattern: ModelThinkingTagPattern
    metadata: ModelInfoMetadata
    single_file: SingleFileArtifact
    archive: ArchiveArtifact
    multi_file: MultiFileArtifact
    custom_strategy_id: str
    built_in: bool
    artifact_type: ModelArtifactType
    expected_files: ExpectedModelFiles
    acceleration_preference: AccelerationPreference
    routing_policy: RoutingPolicy
    compatibility: ModelRuntimeCompatibility
    preferred_framework: InferenceFramework
    registry_status: ModelRegistryStatus
    is_downloaded: bool
    is_available: bool
    last_used_at_unix_ms: int
    usage_count: int
    sync_pending: bool
    status_message: str
    def __init__(self, id: _Optional[str] = ..., name: _Optional[str] = ..., category: _Optional[_Union[ModelCategory, str]] = ..., format: _Optional[_Union[ModelFormat, str]] = ..., framework: _Optional[_Union[InferenceFramework, str]] = ..., download_url: _Optional[str] = ..., local_path: _Optional[str] = ..., download_size_bytes: _Optional[int] = ..., context_length: _Optional[int] = ..., supports_thinking: _Optional[bool] = ..., supports_lora: _Optional[bool] = ..., description: _Optional[str] = ..., source: _Optional[_Union[ModelSource, str]] = ..., created_at_unix_ms: _Optional[int] = ..., updated_at_unix_ms: _Optional[int] = ..., memory_required_bytes: _Optional[int] = ..., checksum_sha256: _Optional[str] = ..., thinking_pattern: _Optional[_Union[ModelThinkingTagPattern, _Mapping]] = ..., metadata: _Optional[_Union[ModelInfoMetadata, _Mapping]] = ..., single_file: _Optional[_Union[SingleFileArtifact, _Mapping]] = ..., archive: _Optional[_Union[ArchiveArtifact, _Mapping]] = ..., multi_file: _Optional[_Union[MultiFileArtifact, _Mapping]] = ..., custom_strategy_id: _Optional[str] = ..., built_in: _Optional[bool] = ..., artifact_type: _Optional[_Union[ModelArtifactType, str]] = ..., expected_files: _Optional[_Union[ExpectedModelFiles, _Mapping]] = ..., acceleration_preference: _Optional[_Union[AccelerationPreference, str]] = ..., routing_policy: _Optional[_Union[RoutingPolicy, str]] = ..., compatibility: _Optional[_Union[ModelRuntimeCompatibility, _Mapping]] = ..., preferred_framework: _Optional[_Union[InferenceFramework, str]] = ..., registry_status: _Optional[_Union[ModelRegistryStatus, str]] = ..., is_downloaded: _Optional[bool] = ..., is_available: _Optional[bool] = ..., last_used_at_unix_ms: _Optional[int] = ..., usage_count: _Optional[int] = ..., sync_pending: _Optional[bool] = ..., status_message: _Optional[str] = ...) -> None: ...

class ModelInfoList(_message.Message):
    __slots__ = ("models",)
    MODELS_FIELD_NUMBER: _ClassVar[int]
    models: _containers.RepeatedCompositeFieldContainer[ModelInfo]
    def __init__(self, models: _Optional[_Iterable[_Union[ModelInfo, _Mapping]]] = ...) -> None: ...

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
    __slots__ = ("url", "filename", "is_required", "size_bytes", "checksum", "relative_path", "destination_path", "role", "local_path")
    URL_FIELD_NUMBER: _ClassVar[int]
    FILENAME_FIELD_NUMBER: _ClassVar[int]
    IS_REQUIRED_FIELD_NUMBER: _ClassVar[int]
    SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    CHECKSUM_FIELD_NUMBER: _ClassVar[int]
    RELATIVE_PATH_FIELD_NUMBER: _ClassVar[int]
    DESTINATION_PATH_FIELD_NUMBER: _ClassVar[int]
    ROLE_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    url: str
    filename: str
    is_required: bool
    size_bytes: int
    checksum: str
    relative_path: str
    destination_path: str
    role: ModelFileRole
    local_path: str
    def __init__(self, url: _Optional[str] = ..., filename: _Optional[str] = ..., is_required: _Optional[bool] = ..., size_bytes: _Optional[int] = ..., checksum: _Optional[str] = ..., relative_path: _Optional[str] = ..., destination_path: _Optional[str] = ..., role: _Optional[_Union[ModelFileRole, str]] = ..., local_path: _Optional[str] = ...) -> None: ...

class MultiFileArtifact(_message.Message):
    __slots__ = ("files",)
    FILES_FIELD_NUMBER: _ClassVar[int]
    files: _containers.RepeatedCompositeFieldContainer[ModelFileDescriptor]
    def __init__(self, files: _Optional[_Iterable[_Union[ModelFileDescriptor, _Mapping]]] = ...) -> None: ...

class ExpectedModelFiles(_message.Message):
    __slots__ = ("files", "root_directory", "required_patterns", "optional_patterns", "description")
    FILES_FIELD_NUMBER: _ClassVar[int]
    ROOT_DIRECTORY_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_PATTERNS_FIELD_NUMBER: _ClassVar[int]
    OPTIONAL_PATTERNS_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    files: _containers.RepeatedCompositeFieldContainer[ModelFileDescriptor]
    root_directory: str
    required_patterns: _containers.RepeatedScalarFieldContainer[str]
    optional_patterns: _containers.RepeatedScalarFieldContainer[str]
    description: str
    def __init__(self, files: _Optional[_Iterable[_Union[ModelFileDescriptor, _Mapping]]] = ..., root_directory: _Optional[str] = ..., required_patterns: _Optional[_Iterable[str]] = ..., optional_patterns: _Optional[_Iterable[str]] = ..., description: _Optional[str] = ...) -> None: ...

class ModelQuery(_message.Message):
    __slots__ = ("framework", "category", "format", "downloaded_only", "available_only", "max_size_bytes", "search_query", "source", "sort_field", "sort_order")
    FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    CATEGORY_FIELD_NUMBER: _ClassVar[int]
    FORMAT_FIELD_NUMBER: _ClassVar[int]
    DOWNLOADED_ONLY_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_ONLY_FIELD_NUMBER: _ClassVar[int]
    MAX_SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    SEARCH_QUERY_FIELD_NUMBER: _ClassVar[int]
    SOURCE_FIELD_NUMBER: _ClassVar[int]
    SORT_FIELD_FIELD_NUMBER: _ClassVar[int]
    SORT_ORDER_FIELD_NUMBER: _ClassVar[int]
    framework: InferenceFramework
    category: ModelCategory
    format: ModelFormat
    downloaded_only: bool
    available_only: bool
    max_size_bytes: int
    search_query: str
    source: ModelSource
    sort_field: ModelQuerySortField
    sort_order: ModelQuerySortOrder
    def __init__(self, framework: _Optional[_Union[InferenceFramework, str]] = ..., category: _Optional[_Union[ModelCategory, str]] = ..., format: _Optional[_Union[ModelFormat, str]] = ..., downloaded_only: _Optional[bool] = ..., available_only: _Optional[bool] = ..., max_size_bytes: _Optional[int] = ..., search_query: _Optional[str] = ..., source: _Optional[_Union[ModelSource, str]] = ..., sort_field: _Optional[_Union[ModelQuerySortField, str]] = ..., sort_order: _Optional[_Union[ModelQuerySortOrder, str]] = ...) -> None: ...

class ModelCompatibilityResult(_message.Message):
    __slots__ = ("is_compatible", "can_run", "can_fit", "required_memory_bytes", "available_memory_bytes", "required_storage_bytes", "available_storage_bytes", "reasons")
    IS_COMPATIBLE_FIELD_NUMBER: _ClassVar[int]
    CAN_RUN_FIELD_NUMBER: _ClassVar[int]
    CAN_FIT_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_MEMORY_BYTES_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_MEMORY_BYTES_FIELD_NUMBER: _ClassVar[int]
    REQUIRED_STORAGE_BYTES_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_STORAGE_BYTES_FIELD_NUMBER: _ClassVar[int]
    REASONS_FIELD_NUMBER: _ClassVar[int]
    is_compatible: bool
    can_run: bool
    can_fit: bool
    required_memory_bytes: int
    available_memory_bytes: int
    required_storage_bytes: int
    available_storage_bytes: int
    reasons: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, is_compatible: _Optional[bool] = ..., can_run: _Optional[bool] = ..., can_fit: _Optional[bool] = ..., required_memory_bytes: _Optional[int] = ..., available_memory_bytes: _Optional[int] = ..., required_storage_bytes: _Optional[int] = ..., available_storage_bytes: _Optional[int] = ..., reasons: _Optional[_Iterable[str]] = ...) -> None: ...

class ModelRegistryRefreshRequest(_message.Message):
    __slots__ = ("include_remote_catalog", "rescan_local", "prune_orphans", "query")
    INCLUDE_REMOTE_CATALOG_FIELD_NUMBER: _ClassVar[int]
    RESCAN_LOCAL_FIELD_NUMBER: _ClassVar[int]
    PRUNE_ORPHANS_FIELD_NUMBER: _ClassVar[int]
    QUERY_FIELD_NUMBER: _ClassVar[int]
    include_remote_catalog: bool
    rescan_local: bool
    prune_orphans: bool
    query: ModelQuery
    def __init__(self, include_remote_catalog: _Optional[bool] = ..., rescan_local: _Optional[bool] = ..., prune_orphans: _Optional[bool] = ..., query: _Optional[_Union[ModelQuery, _Mapping]] = ...) -> None: ...

class ModelRegistryRefreshResult(_message.Message):
    __slots__ = ("success", "models", "registered_count", "updated_count", "discovered_count", "pruned_count", "refreshed_at_unix_ms", "warnings", "error_message")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    MODELS_FIELD_NUMBER: _ClassVar[int]
    REGISTERED_COUNT_FIELD_NUMBER: _ClassVar[int]
    UPDATED_COUNT_FIELD_NUMBER: _ClassVar[int]
    DISCOVERED_COUNT_FIELD_NUMBER: _ClassVar[int]
    PRUNED_COUNT_FIELD_NUMBER: _ClassVar[int]
    REFRESHED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    success: bool
    models: ModelInfoList
    registered_count: int
    updated_count: int
    discovered_count: int
    pruned_count: int
    refreshed_at_unix_ms: int
    warnings: _containers.RepeatedScalarFieldContainer[str]
    error_message: str
    def __init__(self, success: _Optional[bool] = ..., models: _Optional[_Union[ModelInfoList, _Mapping]] = ..., registered_count: _Optional[int] = ..., updated_count: _Optional[int] = ..., discovered_count: _Optional[int] = ..., pruned_count: _Optional[int] = ..., refreshed_at_unix_ms: _Optional[int] = ..., warnings: _Optional[_Iterable[str]] = ..., error_message: _Optional[str] = ...) -> None: ...

class ModelListRequest(_message.Message):
    __slots__ = ("query",)
    QUERY_FIELD_NUMBER: _ClassVar[int]
    query: ModelQuery
    def __init__(self, query: _Optional[_Union[ModelQuery, _Mapping]] = ...) -> None: ...

class ModelListResult(_message.Message):
    __slots__ = ("success", "models", "error_message")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    MODELS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    success: bool
    models: ModelInfoList
    error_message: str
    def __init__(self, success: _Optional[bool] = ..., models: _Optional[_Union[ModelInfoList, _Mapping]] = ..., error_message: _Optional[str] = ...) -> None: ...

class ModelGetRequest(_message.Message):
    __slots__ = ("model_id",)
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    def __init__(self, model_id: _Optional[str] = ...) -> None: ...

class ModelGetResult(_message.Message):
    __slots__ = ("found", "model", "error_message")
    FOUND_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    found: bool
    model: ModelInfo
    error_message: str
    def __init__(self, found: _Optional[bool] = ..., model: _Optional[_Union[ModelInfo, _Mapping]] = ..., error_message: _Optional[str] = ...) -> None: ...

class ModelImportRequest(_message.Message):
    __slots__ = ("model", "source_path", "copy_into_managed_storage", "overwrite_existing", "files")
    MODEL_FIELD_NUMBER: _ClassVar[int]
    SOURCE_PATH_FIELD_NUMBER: _ClassVar[int]
    COPY_INTO_MANAGED_STORAGE_FIELD_NUMBER: _ClassVar[int]
    OVERWRITE_EXISTING_FIELD_NUMBER: _ClassVar[int]
    FILES_FIELD_NUMBER: _ClassVar[int]
    model: ModelInfo
    source_path: str
    copy_into_managed_storage: bool
    overwrite_existing: bool
    files: _containers.RepeatedCompositeFieldContainer[ModelFileDescriptor]
    def __init__(self, model: _Optional[_Union[ModelInfo, _Mapping]] = ..., source_path: _Optional[str] = ..., copy_into_managed_storage: _Optional[bool] = ..., overwrite_existing: _Optional[bool] = ..., files: _Optional[_Iterable[_Union[ModelFileDescriptor, _Mapping]]] = ...) -> None: ...

class ModelImportResult(_message.Message):
    __slots__ = ("success", "model", "local_path", "imported_bytes", "warnings", "error_message")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    IMPORTED_BYTES_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    success: bool
    model: ModelInfo
    local_path: str
    imported_bytes: int
    warnings: _containers.RepeatedScalarFieldContainer[str]
    error_message: str
    def __init__(self, success: _Optional[bool] = ..., model: _Optional[_Union[ModelInfo, _Mapping]] = ..., local_path: _Optional[str] = ..., imported_bytes: _Optional[int] = ..., warnings: _Optional[_Iterable[str]] = ..., error_message: _Optional[str] = ...) -> None: ...

class ModelDiscoveryRequest(_message.Message):
    __slots__ = ("search_roots", "recursive", "link_downloaded", "purge_invalid", "query")
    SEARCH_ROOTS_FIELD_NUMBER: _ClassVar[int]
    RECURSIVE_FIELD_NUMBER: _ClassVar[int]
    LINK_DOWNLOADED_FIELD_NUMBER: _ClassVar[int]
    PURGE_INVALID_FIELD_NUMBER: _ClassVar[int]
    QUERY_FIELD_NUMBER: _ClassVar[int]
    search_roots: _containers.RepeatedScalarFieldContainer[str]
    recursive: bool
    link_downloaded: bool
    purge_invalid: bool
    query: ModelQuery
    def __init__(self, search_roots: _Optional[_Iterable[str]] = ..., recursive: _Optional[bool] = ..., link_downloaded: _Optional[bool] = ..., purge_invalid: _Optional[bool] = ..., query: _Optional[_Union[ModelQuery, _Mapping]] = ...) -> None: ...

class DiscoveredModel(_message.Message):
    __slots__ = ("model_id", "local_path", "matched_registry", "model", "size_bytes", "warnings")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    MATCHED_REGISTRY_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    local_path: str
    matched_registry: bool
    model: ModelInfo
    size_bytes: int
    warnings: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, model_id: _Optional[str] = ..., local_path: _Optional[str] = ..., matched_registry: _Optional[bool] = ..., model: _Optional[_Union[ModelInfo, _Mapping]] = ..., size_bytes: _Optional[int] = ..., warnings: _Optional[_Iterable[str]] = ...) -> None: ...

class ModelDiscoveryResult(_message.Message):
    __slots__ = ("success", "discovered_models", "linked_count", "purged_count", "warnings", "error_message")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    DISCOVERED_MODELS_FIELD_NUMBER: _ClassVar[int]
    LINKED_COUNT_FIELD_NUMBER: _ClassVar[int]
    PURGED_COUNT_FIELD_NUMBER: _ClassVar[int]
    WARNINGS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    success: bool
    discovered_models: _containers.RepeatedCompositeFieldContainer[DiscoveredModel]
    linked_count: int
    purged_count: int
    warnings: _containers.RepeatedScalarFieldContainer[str]
    error_message: str
    def __init__(self, success: _Optional[bool] = ..., discovered_models: _Optional[_Iterable[_Union[DiscoveredModel, _Mapping]]] = ..., linked_count: _Optional[int] = ..., purged_count: _Optional[int] = ..., warnings: _Optional[_Iterable[str]] = ..., error_message: _Optional[str] = ...) -> None: ...

class ModelLoadRequest(_message.Message):
    __slots__ = ("model_id", "category", "framework", "force_reload")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    CATEGORY_FIELD_NUMBER: _ClassVar[int]
    FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    FORCE_RELOAD_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    category: ModelCategory
    framework: InferenceFramework
    force_reload: bool
    def __init__(self, model_id: _Optional[str] = ..., category: _Optional[_Union[ModelCategory, str]] = ..., framework: _Optional[_Union[InferenceFramework, str]] = ..., force_reload: _Optional[bool] = ...) -> None: ...

class ModelLoadResult(_message.Message):
    __slots__ = ("success", "model_id", "category", "framework", "resolved_path", "loaded_at_unix_ms", "error_message")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    CATEGORY_FIELD_NUMBER: _ClassVar[int]
    FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    RESOLVED_PATH_FIELD_NUMBER: _ClassVar[int]
    LOADED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    success: bool
    model_id: str
    category: ModelCategory
    framework: InferenceFramework
    resolved_path: str
    loaded_at_unix_ms: int
    error_message: str
    def __init__(self, success: _Optional[bool] = ..., model_id: _Optional[str] = ..., category: _Optional[_Union[ModelCategory, str]] = ..., framework: _Optional[_Union[InferenceFramework, str]] = ..., resolved_path: _Optional[str] = ..., loaded_at_unix_ms: _Optional[int] = ..., error_message: _Optional[str] = ...) -> None: ...

class ModelUnloadRequest(_message.Message):
    __slots__ = ("model_id", "category", "unload_all")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    CATEGORY_FIELD_NUMBER: _ClassVar[int]
    UNLOAD_ALL_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    category: ModelCategory
    unload_all: bool
    def __init__(self, model_id: _Optional[str] = ..., category: _Optional[_Union[ModelCategory, str]] = ..., unload_all: _Optional[bool] = ...) -> None: ...

class ModelUnloadResult(_message.Message):
    __slots__ = ("success", "unloaded_model_ids", "error_message")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    UNLOADED_MODEL_IDS_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    success: bool
    unloaded_model_ids: _containers.RepeatedScalarFieldContainer[str]
    error_message: str
    def __init__(self, success: _Optional[bool] = ..., unloaded_model_ids: _Optional[_Iterable[str]] = ..., error_message: _Optional[str] = ...) -> None: ...

class CurrentModelRequest(_message.Message):
    __slots__ = ("category", "framework")
    CATEGORY_FIELD_NUMBER: _ClassVar[int]
    FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    category: ModelCategory
    framework: InferenceFramework
    def __init__(self, category: _Optional[_Union[ModelCategory, str]] = ..., framework: _Optional[_Union[InferenceFramework, str]] = ...) -> None: ...

class CurrentModelResult(_message.Message):
    __slots__ = ("model_id", "model", "loaded_at_unix_ms")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    LOADED_AT_UNIX_MS_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    model: ModelInfo
    loaded_at_unix_ms: int
    def __init__(self, model_id: _Optional[str] = ..., model: _Optional[_Union[ModelInfo, _Mapping]] = ..., loaded_at_unix_ms: _Optional[int] = ...) -> None: ...

class ModelDeleteRequest(_message.Message):
    __slots__ = ("model_id", "delete_files", "unregister", "unload_if_loaded")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    DELETE_FILES_FIELD_NUMBER: _ClassVar[int]
    UNREGISTER_FIELD_NUMBER: _ClassVar[int]
    UNLOAD_IF_LOADED_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    delete_files: bool
    unregister: bool
    unload_if_loaded: bool
    def __init__(self, model_id: _Optional[str] = ..., delete_files: _Optional[bool] = ..., unregister: _Optional[bool] = ..., unload_if_loaded: _Optional[bool] = ...) -> None: ...

class ModelDeleteResult(_message.Message):
    __slots__ = ("success", "model_id", "deleted_bytes", "files_deleted", "registry_updated", "was_loaded", "error_message")
    SUCCESS_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    DELETED_BYTES_FIELD_NUMBER: _ClassVar[int]
    FILES_DELETED_FIELD_NUMBER: _ClassVar[int]
    REGISTRY_UPDATED_FIELD_NUMBER: _ClassVar[int]
    WAS_LOADED_FIELD_NUMBER: _ClassVar[int]
    ERROR_MESSAGE_FIELD_NUMBER: _ClassVar[int]
    success: bool
    model_id: str
    deleted_bytes: int
    files_deleted: bool
    registry_updated: bool
    was_loaded: bool
    error_message: str
    def __init__(self, success: _Optional[bool] = ..., model_id: _Optional[str] = ..., deleted_bytes: _Optional[int] = ..., files_deleted: _Optional[bool] = ..., registry_updated: _Optional[bool] = ..., was_loaded: _Optional[bool] = ..., error_message: _Optional[str] = ...) -> None: ...
