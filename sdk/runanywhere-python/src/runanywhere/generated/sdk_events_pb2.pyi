import voice_events_pb2 as _voice_events_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class SDKComponent(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    SDK_COMPONENT_UNSPECIFIED: _ClassVar[SDKComponent]
    SDK_COMPONENT_STT: _ClassVar[SDKComponent]
    SDK_COMPONENT_TTS: _ClassVar[SDKComponent]
    SDK_COMPONENT_VAD: _ClassVar[SDKComponent]
    SDK_COMPONENT_LLM: _ClassVar[SDKComponent]
    SDK_COMPONENT_VLM: _ClassVar[SDKComponent]
    SDK_COMPONENT_DIFFUSION: _ClassVar[SDKComponent]
    SDK_COMPONENT_RAG: _ClassVar[SDKComponent]
    SDK_COMPONENT_EMBEDDINGS: _ClassVar[SDKComponent]
    SDK_COMPONENT_VOICE_AGENT: _ClassVar[SDKComponent]
    SDK_COMPONENT_WAKEWORD: _ClassVar[SDKComponent]
    SDK_COMPONENT_SPEAKER_DIARIZATION: _ClassVar[SDKComponent]

class EventSeverity(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    EVENT_SEVERITY_DEBUG: _ClassVar[EventSeverity]
    EVENT_SEVERITY_INFO: _ClassVar[EventSeverity]
    EVENT_SEVERITY_WARNING: _ClassVar[EventSeverity]
    EVENT_SEVERITY_ERROR: _ClassVar[EventSeverity]
    EVENT_SEVERITY_CRITICAL: _ClassVar[EventSeverity]

class EventDestination(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    EVENT_DESTINATION_UNSPECIFIED: _ClassVar[EventDestination]
    EVENT_DESTINATION_ALL: _ClassVar[EventDestination]
    EVENT_DESTINATION_PUBLIC_ONLY: _ClassVar[EventDestination]
    EVENT_DESTINATION_ANALYTICS_ONLY: _ClassVar[EventDestination]

class InitializationStage(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    INITIALIZATION_STAGE_UNSPECIFIED: _ClassVar[InitializationStage]
    INITIALIZATION_STAGE_STARTED: _ClassVar[InitializationStage]
    INITIALIZATION_STAGE_CONFIGURATION_LOADED: _ClassVar[InitializationStage]
    INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED: _ClassVar[InitializationStage]
    INITIALIZATION_STAGE_COMPLETED: _ClassVar[InitializationStage]
    INITIALIZATION_STAGE_FAILED: _ClassVar[InitializationStage]
    INITIALIZATION_STAGE_SHUTDOWN: _ClassVar[InitializationStage]

class ConfigurationEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    CONFIGURATION_EVENT_KIND_UNSPECIFIED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_FETCH_STARTED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_FETCH_COMPLETED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_FETCH_FAILED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_LOADED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_UPDATED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_SYNC_STARTED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_SYNC_COMPLETED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_SYNC_FAILED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_SYNC_REQUESTED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_SETTINGS_RETRIEVED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_ROUTING_POLICY_REQUESTED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_ROUTING_POLICY_RETRIEVED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_PRIVACY_MODE_REQUESTED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_PRIVACY_MODE_RETRIEVED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_REQUESTED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_RETRIEVED: _ClassVar[ConfigurationEventKind]
    CONFIGURATION_EVENT_KIND_CHANGED: _ClassVar[ConfigurationEventKind]

class GenerationEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    GENERATION_EVENT_KIND_UNSPECIFIED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_SESSION_STARTED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_SESSION_ENDED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_STARTED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_TOKEN_GENERATED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_STREAMING_UPDATE: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_COMPLETED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_FAILED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_MODEL_LOADED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_MODEL_UNLOADED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_COST_CALCULATED: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_ROUTING_DECISION: _ClassVar[GenerationEventKind]
    GENERATION_EVENT_KIND_STREAM_COMPLETED: _ClassVar[GenerationEventKind]

class ModelEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MODEL_EVENT_KIND_UNSPECIFIED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_LOAD_STARTED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_LOAD_PROGRESS: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_LOAD_COMPLETED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_LOAD_FAILED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_UNLOAD_STARTED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_UNLOAD_COMPLETED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_UNLOAD_FAILED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_DOWNLOAD_STARTED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_DOWNLOAD_PROGRESS: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_DOWNLOAD_COMPLETED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_DOWNLOAD_FAILED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_DOWNLOAD_CANCELLED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_LIST_REQUESTED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_LIST_COMPLETED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_LIST_FAILED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_CATALOG_LOADED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_DELETE_STARTED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_DELETE_COMPLETED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_DELETE_FAILED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_CUSTOM_MODEL_ADDED: _ClassVar[ModelEventKind]
    MODEL_EVENT_KIND_BUILT_IN_REGISTERED: _ClassVar[ModelEventKind]

class VoiceEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VOICE_EVENT_KIND_UNSPECIFIED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_LISTENING_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_LISTENING_ENDED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_SPEECH_DETECTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_TRANSCRIPTION_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_TRANSCRIPTION_FINAL: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_RESPONSE_GENERATED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_SYNTHESIS_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_AUDIO_GENERATED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_SYNTHESIS_COMPLETED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_SYNTHESIS_FAILED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_PIPELINE_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_PIPELINE_COMPLETED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_PIPELINE_ERROR: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VAD_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VAD_DETECTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VAD_ENDED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VAD_INITIALIZED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VAD_STOPPED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VAD_CLEANED_UP: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_SPEECH_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_SPEECH_ENDED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_STT_PROCESSING: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_STT_PARTIAL_RESULT: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_STT_COMPLETED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_STT_FAILED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_LLM_PROCESSING: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_TTS_PROCESSING: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_RECORDING_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_RECORDING_STOPPED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_PLAYBACK_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_PLAYBACK_COMPLETED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_PLAYBACK_STOPPED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_PLAYBACK_PAUSED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_PLAYBACK_RESUMED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_PLAYBACK_FAILED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_LISTENING: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_STARTED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_ENDED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_PROCESSING: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_TRANSCRIBED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_RESPONDED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_SPEAKING: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_STOPPED: _ClassVar[VoiceEventKind]
    VOICE_EVENT_KIND_VOICE_SESSION_ERROR: _ClassVar[VoiceEventKind]

class PerformanceEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    PERFORMANCE_EVENT_KIND_UNSPECIFIED: _ClassVar[PerformanceEventKind]
    PERFORMANCE_EVENT_KIND_MEMORY_WARNING: _ClassVar[PerformanceEventKind]
    PERFORMANCE_EVENT_KIND_THERMAL_STATE_CHANGED: _ClassVar[PerformanceEventKind]
    PERFORMANCE_EVENT_KIND_LATENCY_MEASURED: _ClassVar[PerformanceEventKind]
    PERFORMANCE_EVENT_KIND_THROUGHPUT_MEASURED: _ClassVar[PerformanceEventKind]

class NetworkEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    NETWORK_EVENT_KIND_UNSPECIFIED: _ClassVar[NetworkEventKind]
    NETWORK_EVENT_KIND_REQUEST_STARTED: _ClassVar[NetworkEventKind]
    NETWORK_EVENT_KIND_REQUEST_COMPLETED: _ClassVar[NetworkEventKind]
    NETWORK_EVENT_KIND_REQUEST_FAILED: _ClassVar[NetworkEventKind]
    NETWORK_EVENT_KIND_REQUEST_TIMEOUT: _ClassVar[NetworkEventKind]
    NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED: _ClassVar[NetworkEventKind]

class StorageEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    STORAGE_EVENT_KIND_UNSPECIFIED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_INFO_REQUESTED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_INFO_RETRIEVED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_MODELS_REQUESTED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_MODELS_RETRIEVED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_CLEAR_CACHE_STARTED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_CLEAN_TEMP_FAILED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_DELETE_MODEL_STARTED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_DELETE_MODEL_COMPLETED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_DELETE_MODEL_FAILED: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_CACHE_HIT: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_CACHE_MISS: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_EVICTION: _ClassVar[StorageEventKind]
    STORAGE_EVENT_KIND_DISK_FULL: _ClassVar[StorageEventKind]

class FrameworkEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    FRAMEWORK_EVENT_KIND_UNSPECIFIED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_ADAPTER_REGISTERED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_ADAPTER_UNREGISTERED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_ADAPTERS_RETRIEVED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_REQUESTED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_RETRIEVED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_AVAILABILITY_REQUESTED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_AVAILABILITY_RETRIEVED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_REQUESTED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_RETRIEVED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_REQUESTED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_RETRIEVED: _ClassVar[FrameworkEventKind]
    FRAMEWORK_EVENT_KIND_ERROR: _ClassVar[FrameworkEventKind]

class DeviceEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DEVICE_EVENT_KIND_UNSPECIFIED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTION_FAILED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_DEVICE_INFO_REFRESHED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_STARTED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_COMPLETED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_FAILED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_BATTERY_CHANGED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_THERMAL_CHANGED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_CONNECTIVITY_CHANGED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_DEVICE_REGISTERED: _ClassVar[DeviceEventKind]
    DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED: _ClassVar[DeviceEventKind]

class ComponentInitializationEventKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    COMPONENT_INIT_EVENT_KIND_UNSPECIFIED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_INITIALIZATION_STARTED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_INITIALIZATION_COMPLETED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_COMPONENT_CHECKING: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_STARTED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_PROGRESS: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_COMPLETED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_COMPONENT_INITIALIZING: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_COMPONENT_READY: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_COMPONENT_FAILED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_PARALLEL_INIT_STARTED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_SEQUENTIAL_INIT_STARTED: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY: _ClassVar[ComponentInitializationEventKind]
    COMPONENT_INIT_EVENT_KIND_SOME_COMPONENTS_READY: _ClassVar[ComponentInitializationEventKind]
SDK_COMPONENT_UNSPECIFIED: SDKComponent
SDK_COMPONENT_STT: SDKComponent
SDK_COMPONENT_TTS: SDKComponent
SDK_COMPONENT_VAD: SDKComponent
SDK_COMPONENT_LLM: SDKComponent
SDK_COMPONENT_VLM: SDKComponent
SDK_COMPONENT_DIFFUSION: SDKComponent
SDK_COMPONENT_RAG: SDKComponent
SDK_COMPONENT_EMBEDDINGS: SDKComponent
SDK_COMPONENT_VOICE_AGENT: SDKComponent
SDK_COMPONENT_WAKEWORD: SDKComponent
SDK_COMPONENT_SPEAKER_DIARIZATION: SDKComponent
EVENT_SEVERITY_DEBUG: EventSeverity
EVENT_SEVERITY_INFO: EventSeverity
EVENT_SEVERITY_WARNING: EventSeverity
EVENT_SEVERITY_ERROR: EventSeverity
EVENT_SEVERITY_CRITICAL: EventSeverity
EVENT_DESTINATION_UNSPECIFIED: EventDestination
EVENT_DESTINATION_ALL: EventDestination
EVENT_DESTINATION_PUBLIC_ONLY: EventDestination
EVENT_DESTINATION_ANALYTICS_ONLY: EventDestination
INITIALIZATION_STAGE_UNSPECIFIED: InitializationStage
INITIALIZATION_STAGE_STARTED: InitializationStage
INITIALIZATION_STAGE_CONFIGURATION_LOADED: InitializationStage
INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED: InitializationStage
INITIALIZATION_STAGE_COMPLETED: InitializationStage
INITIALIZATION_STAGE_FAILED: InitializationStage
INITIALIZATION_STAGE_SHUTDOWN: InitializationStage
CONFIGURATION_EVENT_KIND_UNSPECIFIED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_FETCH_STARTED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_FETCH_COMPLETED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_FETCH_FAILED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_LOADED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_UPDATED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_SYNC_STARTED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_SYNC_COMPLETED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_SYNC_FAILED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_SYNC_REQUESTED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_SETTINGS_RETRIEVED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_ROUTING_POLICY_REQUESTED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_ROUTING_POLICY_RETRIEVED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_PRIVACY_MODE_REQUESTED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_PRIVACY_MODE_RETRIEVED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_REQUESTED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_RETRIEVED: ConfigurationEventKind
CONFIGURATION_EVENT_KIND_CHANGED: ConfigurationEventKind
GENERATION_EVENT_KIND_UNSPECIFIED: GenerationEventKind
GENERATION_EVENT_KIND_SESSION_STARTED: GenerationEventKind
GENERATION_EVENT_KIND_SESSION_ENDED: GenerationEventKind
GENERATION_EVENT_KIND_STARTED: GenerationEventKind
GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED: GenerationEventKind
GENERATION_EVENT_KIND_TOKEN_GENERATED: GenerationEventKind
GENERATION_EVENT_KIND_STREAMING_UPDATE: GenerationEventKind
GENERATION_EVENT_KIND_COMPLETED: GenerationEventKind
GENERATION_EVENT_KIND_FAILED: GenerationEventKind
GENERATION_EVENT_KIND_MODEL_LOADED: GenerationEventKind
GENERATION_EVENT_KIND_MODEL_UNLOADED: GenerationEventKind
GENERATION_EVENT_KIND_COST_CALCULATED: GenerationEventKind
GENERATION_EVENT_KIND_ROUTING_DECISION: GenerationEventKind
GENERATION_EVENT_KIND_STREAM_COMPLETED: GenerationEventKind
MODEL_EVENT_KIND_UNSPECIFIED: ModelEventKind
MODEL_EVENT_KIND_LOAD_STARTED: ModelEventKind
MODEL_EVENT_KIND_LOAD_PROGRESS: ModelEventKind
MODEL_EVENT_KIND_LOAD_COMPLETED: ModelEventKind
MODEL_EVENT_KIND_LOAD_FAILED: ModelEventKind
MODEL_EVENT_KIND_UNLOAD_STARTED: ModelEventKind
MODEL_EVENT_KIND_UNLOAD_COMPLETED: ModelEventKind
MODEL_EVENT_KIND_UNLOAD_FAILED: ModelEventKind
MODEL_EVENT_KIND_DOWNLOAD_STARTED: ModelEventKind
MODEL_EVENT_KIND_DOWNLOAD_PROGRESS: ModelEventKind
MODEL_EVENT_KIND_DOWNLOAD_COMPLETED: ModelEventKind
MODEL_EVENT_KIND_DOWNLOAD_FAILED: ModelEventKind
MODEL_EVENT_KIND_DOWNLOAD_CANCELLED: ModelEventKind
MODEL_EVENT_KIND_LIST_REQUESTED: ModelEventKind
MODEL_EVENT_KIND_LIST_COMPLETED: ModelEventKind
MODEL_EVENT_KIND_LIST_FAILED: ModelEventKind
MODEL_EVENT_KIND_CATALOG_LOADED: ModelEventKind
MODEL_EVENT_KIND_DELETE_STARTED: ModelEventKind
MODEL_EVENT_KIND_DELETE_COMPLETED: ModelEventKind
MODEL_EVENT_KIND_DELETE_FAILED: ModelEventKind
MODEL_EVENT_KIND_CUSTOM_MODEL_ADDED: ModelEventKind
MODEL_EVENT_KIND_BUILT_IN_REGISTERED: ModelEventKind
VOICE_EVENT_KIND_UNSPECIFIED: VoiceEventKind
VOICE_EVENT_KIND_LISTENING_STARTED: VoiceEventKind
VOICE_EVENT_KIND_LISTENING_ENDED: VoiceEventKind
VOICE_EVENT_KIND_SPEECH_DETECTED: VoiceEventKind
VOICE_EVENT_KIND_TRANSCRIPTION_STARTED: VoiceEventKind
VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL: VoiceEventKind
VOICE_EVENT_KIND_TRANSCRIPTION_FINAL: VoiceEventKind
VOICE_EVENT_KIND_RESPONSE_GENERATED: VoiceEventKind
VOICE_EVENT_KIND_SYNTHESIS_STARTED: VoiceEventKind
VOICE_EVENT_KIND_AUDIO_GENERATED: VoiceEventKind
VOICE_EVENT_KIND_SYNTHESIS_COMPLETED: VoiceEventKind
VOICE_EVENT_KIND_SYNTHESIS_FAILED: VoiceEventKind
VOICE_EVENT_KIND_PIPELINE_STARTED: VoiceEventKind
VOICE_EVENT_KIND_PIPELINE_COMPLETED: VoiceEventKind
VOICE_EVENT_KIND_PIPELINE_ERROR: VoiceEventKind
VOICE_EVENT_KIND_VAD_STARTED: VoiceEventKind
VOICE_EVENT_KIND_VAD_DETECTED: VoiceEventKind
VOICE_EVENT_KIND_VAD_ENDED: VoiceEventKind
VOICE_EVENT_KIND_VAD_INITIALIZED: VoiceEventKind
VOICE_EVENT_KIND_VAD_STOPPED: VoiceEventKind
VOICE_EVENT_KIND_VAD_CLEANED_UP: VoiceEventKind
VOICE_EVENT_KIND_SPEECH_STARTED: VoiceEventKind
VOICE_EVENT_KIND_SPEECH_ENDED: VoiceEventKind
VOICE_EVENT_KIND_STT_PROCESSING: VoiceEventKind
VOICE_EVENT_KIND_STT_PARTIAL_RESULT: VoiceEventKind
VOICE_EVENT_KIND_STT_COMPLETED: VoiceEventKind
VOICE_EVENT_KIND_STT_FAILED: VoiceEventKind
VOICE_EVENT_KIND_LLM_PROCESSING: VoiceEventKind
VOICE_EVENT_KIND_TTS_PROCESSING: VoiceEventKind
VOICE_EVENT_KIND_RECORDING_STARTED: VoiceEventKind
VOICE_EVENT_KIND_RECORDING_STOPPED: VoiceEventKind
VOICE_EVENT_KIND_PLAYBACK_STARTED: VoiceEventKind
VOICE_EVENT_KIND_PLAYBACK_COMPLETED: VoiceEventKind
VOICE_EVENT_KIND_PLAYBACK_STOPPED: VoiceEventKind
VOICE_EVENT_KIND_PLAYBACK_PAUSED: VoiceEventKind
VOICE_EVENT_KIND_PLAYBACK_RESUMED: VoiceEventKind
VOICE_EVENT_KIND_PLAYBACK_FAILED: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_STARTED: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_LISTENING: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_STARTED: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_ENDED: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_PROCESSING: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_TRANSCRIBED: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_RESPONDED: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_SPEAKING: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_STOPPED: VoiceEventKind
VOICE_EVENT_KIND_VOICE_SESSION_ERROR: VoiceEventKind
PERFORMANCE_EVENT_KIND_UNSPECIFIED: PerformanceEventKind
PERFORMANCE_EVENT_KIND_MEMORY_WARNING: PerformanceEventKind
PERFORMANCE_EVENT_KIND_THERMAL_STATE_CHANGED: PerformanceEventKind
PERFORMANCE_EVENT_KIND_LATENCY_MEASURED: PerformanceEventKind
PERFORMANCE_EVENT_KIND_THROUGHPUT_MEASURED: PerformanceEventKind
NETWORK_EVENT_KIND_UNSPECIFIED: NetworkEventKind
NETWORK_EVENT_KIND_REQUEST_STARTED: NetworkEventKind
NETWORK_EVENT_KIND_REQUEST_COMPLETED: NetworkEventKind
NETWORK_EVENT_KIND_REQUEST_FAILED: NetworkEventKind
NETWORK_EVENT_KIND_REQUEST_TIMEOUT: NetworkEventKind
NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED: NetworkEventKind
STORAGE_EVENT_KIND_UNSPECIFIED: StorageEventKind
STORAGE_EVENT_KIND_INFO_REQUESTED: StorageEventKind
STORAGE_EVENT_KIND_INFO_RETRIEVED: StorageEventKind
STORAGE_EVENT_KIND_MODELS_REQUESTED: StorageEventKind
STORAGE_EVENT_KIND_MODELS_RETRIEVED: StorageEventKind
STORAGE_EVENT_KIND_CLEAR_CACHE_STARTED: StorageEventKind
STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED: StorageEventKind
STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED: StorageEventKind
STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED: StorageEventKind
STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED: StorageEventKind
STORAGE_EVENT_KIND_CLEAN_TEMP_FAILED: StorageEventKind
STORAGE_EVENT_KIND_DELETE_MODEL_STARTED: StorageEventKind
STORAGE_EVENT_KIND_DELETE_MODEL_COMPLETED: StorageEventKind
STORAGE_EVENT_KIND_DELETE_MODEL_FAILED: StorageEventKind
STORAGE_EVENT_KIND_CACHE_HIT: StorageEventKind
STORAGE_EVENT_KIND_CACHE_MISS: StorageEventKind
STORAGE_EVENT_KIND_EVICTION: StorageEventKind
STORAGE_EVENT_KIND_DISK_FULL: StorageEventKind
FRAMEWORK_EVENT_KIND_UNSPECIFIED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_ADAPTER_REGISTERED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_ADAPTER_UNREGISTERED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_ADAPTERS_RETRIEVED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_FRAMEWORKS_REQUESTED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_FRAMEWORKS_RETRIEVED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_AVAILABILITY_REQUESTED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_AVAILABILITY_RETRIEVED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_REQUESTED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_RETRIEVED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_REQUESTED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_RETRIEVED: FrameworkEventKind
FRAMEWORK_EVENT_KIND_ERROR: FrameworkEventKind
DEVICE_EVENT_KIND_UNSPECIFIED: DeviceEventKind
DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTED: DeviceEventKind
DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTION_FAILED: DeviceEventKind
DEVICE_EVENT_KIND_DEVICE_INFO_REFRESHED: DeviceEventKind
DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_STARTED: DeviceEventKind
DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_COMPLETED: DeviceEventKind
DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_FAILED: DeviceEventKind
DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED: DeviceEventKind
DEVICE_EVENT_KIND_BATTERY_CHANGED: DeviceEventKind
DEVICE_EVENT_KIND_THERMAL_CHANGED: DeviceEventKind
DEVICE_EVENT_KIND_CONNECTIVITY_CHANGED: DeviceEventKind
DEVICE_EVENT_KIND_DEVICE_REGISTERED: DeviceEventKind
DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED: DeviceEventKind
COMPONENT_INIT_EVENT_KIND_UNSPECIFIED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_INITIALIZATION_STARTED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_INITIALIZATION_COMPLETED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_COMPONENT_CHECKING: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_STARTED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_PROGRESS: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_COMPLETED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_COMPONENT_INITIALIZING: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_COMPONENT_READY: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_COMPONENT_FAILED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_PARALLEL_INIT_STARTED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_SEQUENTIAL_INIT_STARTED: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY: ComponentInitializationEventKind
COMPONENT_INIT_EVENT_KIND_SOME_COMPONENTS_READY: ComponentInitializationEventKind

class InitializationEvent(_message.Message):
    __slots__ = ("stage", "source", "error", "version")
    STAGE_FIELD_NUMBER: _ClassVar[int]
    SOURCE_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    VERSION_FIELD_NUMBER: _ClassVar[int]
    stage: InitializationStage
    source: str
    error: str
    version: str
    def __init__(self, stage: _Optional[_Union[InitializationStage, str]] = ..., source: _Optional[str] = ..., error: _Optional[str] = ..., version: _Optional[str] = ...) -> None: ...

class ConfigurationEvent(_message.Message):
    __slots__ = ("kind", "source", "error", "changed_keys", "settings_json", "routing_policy", "privacy_mode", "analytics_enabled", "old_value_json", "new_value_json")
    KIND_FIELD_NUMBER: _ClassVar[int]
    SOURCE_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    CHANGED_KEYS_FIELD_NUMBER: _ClassVar[int]
    SETTINGS_JSON_FIELD_NUMBER: _ClassVar[int]
    ROUTING_POLICY_FIELD_NUMBER: _ClassVar[int]
    PRIVACY_MODE_FIELD_NUMBER: _ClassVar[int]
    ANALYTICS_ENABLED_FIELD_NUMBER: _ClassVar[int]
    OLD_VALUE_JSON_FIELD_NUMBER: _ClassVar[int]
    NEW_VALUE_JSON_FIELD_NUMBER: _ClassVar[int]
    kind: ConfigurationEventKind
    source: str
    error: str
    changed_keys: _containers.RepeatedScalarFieldContainer[str]
    settings_json: str
    routing_policy: str
    privacy_mode: str
    analytics_enabled: bool
    old_value_json: str
    new_value_json: str
    def __init__(self, kind: _Optional[_Union[ConfigurationEventKind, str]] = ..., source: _Optional[str] = ..., error: _Optional[str] = ..., changed_keys: _Optional[_Iterable[str]] = ..., settings_json: _Optional[str] = ..., routing_policy: _Optional[str] = ..., privacy_mode: _Optional[str] = ..., analytics_enabled: _Optional[bool] = ..., old_value_json: _Optional[str] = ..., new_value_json: _Optional[str] = ...) -> None: ...

class GenerationEvent(_message.Message):
    __slots__ = ("kind", "session_id", "prompt", "token", "streaming_text", "tokens_count", "response", "tokens_used", "latency_ms", "first_token_latency_ms", "error", "model_id", "cost_amount", "cost_saved_amount", "routing_target", "routing_reason")
    KIND_FIELD_NUMBER: _ClassVar[int]
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    PROMPT_FIELD_NUMBER: _ClassVar[int]
    TOKEN_FIELD_NUMBER: _ClassVar[int]
    STREAMING_TEXT_FIELD_NUMBER: _ClassVar[int]
    TOKENS_COUNT_FIELD_NUMBER: _ClassVar[int]
    RESPONSE_FIELD_NUMBER: _ClassVar[int]
    TOKENS_USED_FIELD_NUMBER: _ClassVar[int]
    LATENCY_MS_FIELD_NUMBER: _ClassVar[int]
    FIRST_TOKEN_LATENCY_MS_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    COST_AMOUNT_FIELD_NUMBER: _ClassVar[int]
    COST_SAVED_AMOUNT_FIELD_NUMBER: _ClassVar[int]
    ROUTING_TARGET_FIELD_NUMBER: _ClassVar[int]
    ROUTING_REASON_FIELD_NUMBER: _ClassVar[int]
    kind: GenerationEventKind
    session_id: str
    prompt: str
    token: str
    streaming_text: str
    tokens_count: int
    response: str
    tokens_used: int
    latency_ms: int
    first_token_latency_ms: int
    error: str
    model_id: str
    cost_amount: float
    cost_saved_amount: float
    routing_target: str
    routing_reason: str
    def __init__(self, kind: _Optional[_Union[GenerationEventKind, str]] = ..., session_id: _Optional[str] = ..., prompt: _Optional[str] = ..., token: _Optional[str] = ..., streaming_text: _Optional[str] = ..., tokens_count: _Optional[int] = ..., response: _Optional[str] = ..., tokens_used: _Optional[int] = ..., latency_ms: _Optional[int] = ..., first_token_latency_ms: _Optional[int] = ..., error: _Optional[str] = ..., model_id: _Optional[str] = ..., cost_amount: _Optional[float] = ..., cost_saved_amount: _Optional[float] = ..., routing_target: _Optional[str] = ..., routing_reason: _Optional[str] = ...) -> None: ...

class ModelEvent(_message.Message):
    __slots__ = ("kind", "model_id", "task_id", "progress", "bytes_downloaded", "total_bytes", "download_state", "local_path", "error", "model_count", "custom_model_name", "custom_model_url")
    KIND_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    PROGRESS_FIELD_NUMBER: _ClassVar[int]
    BYTES_DOWNLOADED_FIELD_NUMBER: _ClassVar[int]
    TOTAL_BYTES_FIELD_NUMBER: _ClassVar[int]
    DOWNLOAD_STATE_FIELD_NUMBER: _ClassVar[int]
    LOCAL_PATH_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    MODEL_COUNT_FIELD_NUMBER: _ClassVar[int]
    CUSTOM_MODEL_NAME_FIELD_NUMBER: _ClassVar[int]
    CUSTOM_MODEL_URL_FIELD_NUMBER: _ClassVar[int]
    kind: ModelEventKind
    model_id: str
    task_id: str
    progress: float
    bytes_downloaded: int
    total_bytes: int
    download_state: str
    local_path: str
    error: str
    model_count: int
    custom_model_name: str
    custom_model_url: str
    def __init__(self, kind: _Optional[_Union[ModelEventKind, str]] = ..., model_id: _Optional[str] = ..., task_id: _Optional[str] = ..., progress: _Optional[float] = ..., bytes_downloaded: _Optional[int] = ..., total_bytes: _Optional[int] = ..., download_state: _Optional[str] = ..., local_path: _Optional[str] = ..., error: _Optional[str] = ..., model_count: _Optional[int] = ..., custom_model_name: _Optional[str] = ..., custom_model_url: _Optional[str] = ...) -> None: ...

class VoiceLifecycleEvent(_message.Message):
    __slots__ = ("kind", "session_id", "text", "confidence", "response_text", "audio_base64", "duration_ms", "audio_level", "transcription", "turn_response", "turn_audio_base64", "error")
    KIND_FIELD_NUMBER: _ClassVar[int]
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    TEXT_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    RESPONSE_TEXT_FIELD_NUMBER: _ClassVar[int]
    AUDIO_BASE64_FIELD_NUMBER: _ClassVar[int]
    DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    AUDIO_LEVEL_FIELD_NUMBER: _ClassVar[int]
    TRANSCRIPTION_FIELD_NUMBER: _ClassVar[int]
    TURN_RESPONSE_FIELD_NUMBER: _ClassVar[int]
    TURN_AUDIO_BASE64_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    kind: VoiceEventKind
    session_id: str
    text: str
    confidence: float
    response_text: str
    audio_base64: str
    duration_ms: int
    audio_level: float
    transcription: str
    turn_response: str
    turn_audio_base64: str
    error: str
    def __init__(self, kind: _Optional[_Union[VoiceEventKind, str]] = ..., session_id: _Optional[str] = ..., text: _Optional[str] = ..., confidence: _Optional[float] = ..., response_text: _Optional[str] = ..., audio_base64: _Optional[str] = ..., duration_ms: _Optional[int] = ..., audio_level: _Optional[float] = ..., transcription: _Optional[str] = ..., turn_response: _Optional[str] = ..., turn_audio_base64: _Optional[str] = ..., error: _Optional[str] = ...) -> None: ...

class PerformanceEvent(_message.Message):
    __slots__ = ("kind", "memory_bytes", "thermal_state", "operation", "milliseconds", "tokens_per_second")
    KIND_FIELD_NUMBER: _ClassVar[int]
    MEMORY_BYTES_FIELD_NUMBER: _ClassVar[int]
    THERMAL_STATE_FIELD_NUMBER: _ClassVar[int]
    OPERATION_FIELD_NUMBER: _ClassVar[int]
    MILLISECONDS_FIELD_NUMBER: _ClassVar[int]
    TOKENS_PER_SECOND_FIELD_NUMBER: _ClassVar[int]
    kind: PerformanceEventKind
    memory_bytes: int
    thermal_state: str
    operation: str
    milliseconds: int
    tokens_per_second: float
    def __init__(self, kind: _Optional[_Union[PerformanceEventKind, str]] = ..., memory_bytes: _Optional[int] = ..., thermal_state: _Optional[str] = ..., operation: _Optional[str] = ..., milliseconds: _Optional[int] = ..., tokens_per_second: _Optional[float] = ...) -> None: ...

class NetworkEvent(_message.Message):
    __slots__ = ("kind", "url", "status_code", "is_online", "error", "latency_ms")
    KIND_FIELD_NUMBER: _ClassVar[int]
    URL_FIELD_NUMBER: _ClassVar[int]
    STATUS_CODE_FIELD_NUMBER: _ClassVar[int]
    IS_ONLINE_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    LATENCY_MS_FIELD_NUMBER: _ClassVar[int]
    kind: NetworkEventKind
    url: str
    status_code: int
    is_online: bool
    error: str
    latency_ms: int
    def __init__(self, kind: _Optional[_Union[NetworkEventKind, str]] = ..., url: _Optional[str] = ..., status_code: _Optional[int] = ..., is_online: _Optional[bool] = ..., error: _Optional[str] = ..., latency_ms: _Optional[int] = ...) -> None: ...

class StorageEvent(_message.Message):
    __slots__ = ("kind", "model_id", "error", "total_bytes", "available_bytes", "used_bytes", "stored_model_count", "cache_key", "evicted_bytes")
    KIND_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    TOTAL_BYTES_FIELD_NUMBER: _ClassVar[int]
    AVAILABLE_BYTES_FIELD_NUMBER: _ClassVar[int]
    USED_BYTES_FIELD_NUMBER: _ClassVar[int]
    STORED_MODEL_COUNT_FIELD_NUMBER: _ClassVar[int]
    CACHE_KEY_FIELD_NUMBER: _ClassVar[int]
    EVICTED_BYTES_FIELD_NUMBER: _ClassVar[int]
    kind: StorageEventKind
    model_id: str
    error: str
    total_bytes: int
    available_bytes: int
    used_bytes: int
    stored_model_count: int
    cache_key: str
    evicted_bytes: int
    def __init__(self, kind: _Optional[_Union[StorageEventKind, str]] = ..., model_id: _Optional[str] = ..., error: _Optional[str] = ..., total_bytes: _Optional[int] = ..., available_bytes: _Optional[int] = ..., used_bytes: _Optional[int] = ..., stored_model_count: _Optional[int] = ..., cache_key: _Optional[str] = ..., evicted_bytes: _Optional[int] = ...) -> None: ...

class FrameworkEvent(_message.Message):
    __slots__ = ("kind", "framework", "adapter_name", "adapter_count", "framework_count", "model_count", "modality", "error")
    KIND_FIELD_NUMBER: _ClassVar[int]
    FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_NAME_FIELD_NUMBER: _ClassVar[int]
    ADAPTER_COUNT_FIELD_NUMBER: _ClassVar[int]
    FRAMEWORK_COUNT_FIELD_NUMBER: _ClassVar[int]
    MODEL_COUNT_FIELD_NUMBER: _ClassVar[int]
    MODALITY_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    kind: FrameworkEventKind
    framework: int
    adapter_name: str
    adapter_count: int
    framework_count: int
    model_count: int
    modality: str
    error: str
    def __init__(self, kind: _Optional[_Union[FrameworkEventKind, str]] = ..., framework: _Optional[int] = ..., adapter_name: _Optional[str] = ..., adapter_count: _Optional[int] = ..., framework_count: _Optional[int] = ..., model_count: _Optional[int] = ..., modality: _Optional[str] = ..., error: _Optional[str] = ...) -> None: ...

class DeviceEvent(_message.Message):
    __slots__ = ("kind", "device_id", "os_name", "os_version", "model", "error", "property", "new_value", "old_value", "battery_level", "is_charging", "thermal_state", "is_connected", "connection_type")
    KIND_FIELD_NUMBER: _ClassVar[int]
    DEVICE_ID_FIELD_NUMBER: _ClassVar[int]
    OS_NAME_FIELD_NUMBER: _ClassVar[int]
    OS_VERSION_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    PROPERTY_FIELD_NUMBER: _ClassVar[int]
    NEW_VALUE_FIELD_NUMBER: _ClassVar[int]
    OLD_VALUE_FIELD_NUMBER: _ClassVar[int]
    BATTERY_LEVEL_FIELD_NUMBER: _ClassVar[int]
    IS_CHARGING_FIELD_NUMBER: _ClassVar[int]
    THERMAL_STATE_FIELD_NUMBER: _ClassVar[int]
    IS_CONNECTED_FIELD_NUMBER: _ClassVar[int]
    CONNECTION_TYPE_FIELD_NUMBER: _ClassVar[int]
    kind: DeviceEventKind
    device_id: str
    os_name: str
    os_version: str
    model: str
    error: str
    property: str
    new_value: str
    old_value: str
    battery_level: float
    is_charging: bool
    thermal_state: str
    is_connected: bool
    connection_type: str
    def __init__(self, kind: _Optional[_Union[DeviceEventKind, str]] = ..., device_id: _Optional[str] = ..., os_name: _Optional[str] = ..., os_version: _Optional[str] = ..., model: _Optional[str] = ..., error: _Optional[str] = ..., property: _Optional[str] = ..., new_value: _Optional[str] = ..., old_value: _Optional[str] = ..., battery_level: _Optional[float] = ..., is_charging: _Optional[bool] = ..., thermal_state: _Optional[str] = ..., is_connected: _Optional[bool] = ..., connection_type: _Optional[str] = ...) -> None: ...

class ComponentInitializationEvent(_message.Message):
    __slots__ = ("kind", "component", "model_id", "size_bytes", "progress", "error", "old_state", "new_state", "components", "ready_components", "pending_components", "init_success", "ready_count", "failed_count")
    KIND_FIELD_NUMBER: _ClassVar[int]
    COMPONENT_FIELD_NUMBER: _ClassVar[int]
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    SIZE_BYTES_FIELD_NUMBER: _ClassVar[int]
    PROGRESS_FIELD_NUMBER: _ClassVar[int]
    ERROR_FIELD_NUMBER: _ClassVar[int]
    OLD_STATE_FIELD_NUMBER: _ClassVar[int]
    NEW_STATE_FIELD_NUMBER: _ClassVar[int]
    COMPONENTS_FIELD_NUMBER: _ClassVar[int]
    READY_COMPONENTS_FIELD_NUMBER: _ClassVar[int]
    PENDING_COMPONENTS_FIELD_NUMBER: _ClassVar[int]
    INIT_SUCCESS_FIELD_NUMBER: _ClassVar[int]
    READY_COUNT_FIELD_NUMBER: _ClassVar[int]
    FAILED_COUNT_FIELD_NUMBER: _ClassVar[int]
    kind: ComponentInitializationEventKind
    component: SDKComponent
    model_id: str
    size_bytes: int
    progress: float
    error: str
    old_state: str
    new_state: str
    components: _containers.RepeatedScalarFieldContainer[SDKComponent]
    ready_components: _containers.RepeatedScalarFieldContainer[SDKComponent]
    pending_components: _containers.RepeatedScalarFieldContainer[SDKComponent]
    init_success: bool
    ready_count: int
    failed_count: int
    def __init__(self, kind: _Optional[_Union[ComponentInitializationEventKind, str]] = ..., component: _Optional[_Union[SDKComponent, str]] = ..., model_id: _Optional[str] = ..., size_bytes: _Optional[int] = ..., progress: _Optional[float] = ..., error: _Optional[str] = ..., old_state: _Optional[str] = ..., new_state: _Optional[str] = ..., components: _Optional[_Iterable[_Union[SDKComponent, str]]] = ..., ready_components: _Optional[_Iterable[_Union[SDKComponent, str]]] = ..., pending_components: _Optional[_Iterable[_Union[SDKComponent, str]]] = ..., init_success: _Optional[bool] = ..., ready_count: _Optional[int] = ..., failed_count: _Optional[int] = ...) -> None: ...

class SDKEvent(_message.Message):
    __slots__ = ("timestamp_ms", "severity", "id", "session_id", "destination", "properties", "initialization", "configuration", "generation", "model", "performance", "network", "storage", "framework", "device", "component_init", "voice", "voice_pipeline")
    class PropertiesEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    TIMESTAMP_MS_FIELD_NUMBER: _ClassVar[int]
    SEVERITY_FIELD_NUMBER: _ClassVar[int]
    ID_FIELD_NUMBER: _ClassVar[int]
    SESSION_ID_FIELD_NUMBER: _ClassVar[int]
    DESTINATION_FIELD_NUMBER: _ClassVar[int]
    PROPERTIES_FIELD_NUMBER: _ClassVar[int]
    INITIALIZATION_FIELD_NUMBER: _ClassVar[int]
    CONFIGURATION_FIELD_NUMBER: _ClassVar[int]
    GENERATION_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    PERFORMANCE_FIELD_NUMBER: _ClassVar[int]
    NETWORK_FIELD_NUMBER: _ClassVar[int]
    STORAGE_FIELD_NUMBER: _ClassVar[int]
    FRAMEWORK_FIELD_NUMBER: _ClassVar[int]
    DEVICE_FIELD_NUMBER: _ClassVar[int]
    COMPONENT_INIT_FIELD_NUMBER: _ClassVar[int]
    VOICE_FIELD_NUMBER: _ClassVar[int]
    VOICE_PIPELINE_FIELD_NUMBER: _ClassVar[int]
    timestamp_ms: int
    severity: EventSeverity
    id: str
    session_id: str
    destination: EventDestination
    properties: _containers.ScalarMap[str, str]
    initialization: InitializationEvent
    configuration: ConfigurationEvent
    generation: GenerationEvent
    model: ModelEvent
    performance: PerformanceEvent
    network: NetworkEvent
    storage: StorageEvent
    framework: FrameworkEvent
    device: DeviceEvent
    component_init: ComponentInitializationEvent
    voice: VoiceLifecycleEvent
    voice_pipeline: _voice_events_pb2.VoiceEvent
    def __init__(self, timestamp_ms: _Optional[int] = ..., severity: _Optional[_Union[EventSeverity, str]] = ..., id: _Optional[str] = ..., session_id: _Optional[str] = ..., destination: _Optional[_Union[EventDestination, str]] = ..., properties: _Optional[_Mapping[str, str]] = ..., initialization: _Optional[_Union[InitializationEvent, _Mapping]] = ..., configuration: _Optional[_Union[ConfigurationEvent, _Mapping]] = ..., generation: _Optional[_Union[GenerationEvent, _Mapping]] = ..., model: _Optional[_Union[ModelEvent, _Mapping]] = ..., performance: _Optional[_Union[PerformanceEvent, _Mapping]] = ..., network: _Optional[_Union[NetworkEvent, _Mapping]] = ..., storage: _Optional[_Union[StorageEvent, _Mapping]] = ..., framework: _Optional[_Union[FrameworkEvent, _Mapping]] = ..., device: _Optional[_Union[DeviceEvent, _Mapping]] = ..., component_init: _Optional[_Union[ComponentInitializationEvent, _Mapping]] = ..., voice: _Optional[_Union[VoiceLifecycleEvent, _Mapping]] = ..., voice_pipeline: _Optional[_Union[_voice_events_pb2.VoiceEvent, _Mapping]] = ...) -> None: ...
