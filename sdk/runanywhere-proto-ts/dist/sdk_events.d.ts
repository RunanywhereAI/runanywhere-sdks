import _m0 from "protobufjs/minimal";
import { DownloadCancelResult, DownloadPlanResult, DownloadProgress, DownloadResumeResult, DownloadStartResult } from "./download_service";
import { SDKError } from "./errors";
import { HardwareProfileResult } from "./hardware_profile";
import { CurrentModelResult, InferenceFramework, ModelCompatibilityResult, ModelDeleteResult, ModelDiscoveryResult, ModelGetResult, ModelImportResult, ModelListResult, ModelLoadResult, ModelRegistryRefreshResult, ModelUnloadResult } from "./model_types";
import { StorageAvailabilityResult, StorageDeletePlan, StorageDeleteResult, StorageInfoResult } from "./storage_types";
import { VoiceEvent } from "./voice_events";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Component identifier — every consumer / framework that the SDK orchestrates.
 * Sources pre-IDL:
 *   RN     enums.ts:168 (SDKComponent)             — 7 cases
 *   Swift  ComponentTypes.swift:SDKComponent       — 7 cases
 *   Kotlin ComponentTypes.kt:SDKComponent          — 7 cases
 *   Dart   sdk_component.dart                      — 7 cases
 * Canonical superset adds: VLM, DIFFUSION, RAG, WAKEWORD (referenced by
 * RN's ComponentInitializationEvent.components: SDKComponent[] but not yet
 * in any SDK's enum).
 * ---------------------------------------------------------------------------
 */
export declare enum SDKComponent {
    SDK_COMPONENT_UNSPECIFIED = 0,
    SDK_COMPONENT_STT = 1,
    SDK_COMPONENT_TTS = 2,
    SDK_COMPONENT_VAD = 3,
    SDK_COMPONENT_LLM = 4,
    SDK_COMPONENT_VLM = 5,
    SDK_COMPONENT_DIFFUSION = 6,
    SDK_COMPONENT_RAG = 7,
    SDK_COMPONENT_EMBEDDINGS = 8,
    SDK_COMPONENT_VOICE_AGENT = 9,
    SDK_COMPONENT_WAKEWORD = 10,
    SDK_COMPONENT_SPEAKER_DIARIZATION = 11,
    UNRECOGNIZED = -1
}
export declare function sDKComponentFromJSON(object: any): SDKComponent;
export declare function sDKComponentToJSON(object: SDKComponent): string;
/**
 * ---------------------------------------------------------------------------
 * Event severity. New unification — pre-IDL each SDK either implied severity
 * from event type ("failed" → ERROR) or had no notion. Canonicalizing now
 * enables analytics to filter without parsing event names.
 * ---------------------------------------------------------------------------
 */
export declare enum EventSeverity {
    EVENT_SEVERITY_DEBUG = 0,
    EVENT_SEVERITY_INFO = 1,
    EVENT_SEVERITY_WARNING = 2,
    EVENT_SEVERITY_ERROR = 3,
    EVENT_SEVERITY_CRITICAL = 4,
    UNRECOGNIZED = -1
}
export declare function eventSeverityFromJSON(object: any): EventSeverity;
export declare function eventSeverityToJSON(object: EventSeverity): string;
/**
 * ---------------------------------------------------------------------------
 * Where an event should be routed. Mirrors Swift `EventDestination` /
 * Kotlin `EventDestination` / Dart `EventDestination`.
 * Sources pre-IDL:
 *   Swift  SDKEvent.swift:15-22       — publicOnly / analyticsOnly / all
 *   Kotlin SDKEvent.kt:24-33          — PUBLIC_ONLY / ANALYTICS_ONLY / ALL
 *   Dart   sdk_event.dart:20-29       — all / publicOnly / analyticsOnly
 * ---------------------------------------------------------------------------
 */
export declare enum EventDestination {
    EVENT_DESTINATION_UNSPECIFIED = 0,
    /** EVENT_DESTINATION_ALL - EventBus + Analytics (default) */
    EVENT_DESTINATION_ALL = 1,
    /** EVENT_DESTINATION_PUBLIC_ONLY - EventBus only */
    EVENT_DESTINATION_PUBLIC_ONLY = 2,
    /** EVENT_DESTINATION_ANALYTICS_ONLY - Analytics/telemetry only */
    EVENT_DESTINATION_ANALYTICS_ONLY = 3,
    UNRECOGNIZED = -1
}
export declare function eventDestinationFromJSON(object: any): EventDestination;
export declare function eventDestinationToJSON(object: EventDestination): string;
/**
 * Canonical event category carried by every SDKEvent envelope. The oneof arm
 * identifies the concrete payload shape; this field preserves the stable bus /
 * analytics route used by Swift, Kotlin, Dart/Flutter, React Native, Web, and
 * C++ commons.
 */
export declare enum EventCategory {
    EVENT_CATEGORY_UNSPECIFIED = 0,
    EVENT_CATEGORY_SDK = 1,
    EVENT_CATEGORY_INITIALIZATION = 2,
    EVENT_CATEGORY_SHUTDOWN = 3,
    EVENT_CATEGORY_SESSION = 4,
    EVENT_CATEGORY_AUTH = 5,
    EVENT_CATEGORY_DEVICE = 6,
    EVENT_CATEGORY_REGISTRY = 7,
    EVENT_CATEGORY_ASSIGNMENT = 8,
    EVENT_CATEGORY_IMPORT = 9,
    EVENT_CATEGORY_DISCOVERY = 10,
    EVENT_CATEGORY_DOWNLOAD = 11,
    EVENT_CATEGORY_STORAGE = 12,
    EVENT_CATEGORY_HARDWARE = 13,
    EVENT_CATEGORY_ROUTING = 14,
    EVENT_CATEGORY_FRAMEWORK = 15,
    EVENT_CATEGORY_MODEL = 16,
    EVENT_CATEGORY_COMPONENT = 17,
    EVENT_CATEGORY_LLM = 18,
    EVENT_CATEGORY_STT = 19,
    EVENT_CATEGORY_ASR = 20,
    EVENT_CATEGORY_TTS = 21,
    EVENT_CATEGORY_VAD = 22,
    /** EVENT_CATEGORY_STD - speech-turn detection / diarization */
    EVENT_CATEGORY_STD = 23,
    EVENT_CATEGORY_VOICE_AGENT = 24,
    EVENT_CATEGORY_VLM = 25,
    EVENT_CATEGORY_DIFFUSION = 26,
    EVENT_CATEGORY_EMBEDDINGS = 27,
    EVENT_CATEGORY_RAG = 28,
    EVENT_CATEGORY_LORA = 29,
    EVENT_CATEGORY_TELEMETRY = 30,
    EVENT_CATEGORY_PERFORMANCE = 31,
    EVENT_CATEGORY_CANCELLATION = 32,
    EVENT_CATEGORY_FAILURE = 33,
    EVENT_CATEGORY_NETWORK = 34,
    EVENT_CATEGORY_ERROR = 35,
    UNRECOGNIZED = -1
}
export declare function eventCategoryFromJSON(object: any): EventCategory;
export declare function eventCategoryToJSON(object: EventCategory): string;
/**
 * Component runtime lifecycle state for model-backed SDK components. This is
 * distinct from voice_events.proto's ComponentLoadState, which is scoped to
 * the voice-agent sub-pipeline. Platform adapters own native component handles;
 * this enum carries the C++ lifecycle state every SDK can expose uniformly.
 */
export declare enum ComponentLifecycleState {
    COMPONENT_LIFECYCLE_STATE_UNSPECIFIED = 0,
    COMPONENT_LIFECYCLE_STATE_NOT_LOADED = 1,
    COMPONENT_LIFECYCLE_STATE_LOADING = 2,
    COMPONENT_LIFECYCLE_STATE_READY = 3,
    COMPONENT_LIFECYCLE_STATE_UNLOADING = 4,
    COMPONENT_LIFECYCLE_STATE_ERROR = 5,
    COMPONENT_LIFECYCLE_STATE_SHUTDOWN = 6,
    UNRECOGNIZED = -1
}
export declare function componentLifecycleStateFromJSON(object: any): ComponentLifecycleState;
export declare function componentLifecycleStateToJSON(object: ComponentLifecycleState): string;
export declare enum InitializationStage {
    INITIALIZATION_STAGE_UNSPECIFIED = 0,
    INITIALIZATION_STAGE_STARTED = 1,
    INITIALIZATION_STAGE_CONFIGURATION_LOADED = 2,
    INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED = 3,
    INITIALIZATION_STAGE_COMPLETED = 4,
    INITIALIZATION_STAGE_FAILED = 5,
    /** INITIALIZATION_STAGE_SHUTDOWN - Kotlin SDKLifecycleEvent.SHUTDOWN */
    INITIALIZATION_STAGE_SHUTDOWN = 6,
    UNRECOGNIZED = -1
}
export declare function initializationStageFromJSON(object: any): InitializationStage;
export declare function initializationStageToJSON(object: InitializationStage): string;
export declare enum ConfigurationEventKind {
    CONFIGURATION_EVENT_KIND_UNSPECIFIED = 0,
    CONFIGURATION_EVENT_KIND_FETCH_STARTED = 1,
    CONFIGURATION_EVENT_KIND_FETCH_COMPLETED = 2,
    CONFIGURATION_EVENT_KIND_FETCH_FAILED = 3,
    CONFIGURATION_EVENT_KIND_LOADED = 4,
    CONFIGURATION_EVENT_KIND_UPDATED = 5,
    CONFIGURATION_EVENT_KIND_SYNC_STARTED = 6,
    CONFIGURATION_EVENT_KIND_SYNC_COMPLETED = 7,
    CONFIGURATION_EVENT_KIND_SYNC_FAILED = 8,
    CONFIGURATION_EVENT_KIND_SYNC_REQUESTED = 9,
    CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED = 10,
    CONFIGURATION_EVENT_KIND_SETTINGS_RETRIEVED = 11,
    CONFIGURATION_EVENT_KIND_ROUTING_POLICY_REQUESTED = 12,
    CONFIGURATION_EVENT_KIND_ROUTING_POLICY_RETRIEVED = 13,
    CONFIGURATION_EVENT_KIND_PRIVACY_MODE_REQUESTED = 14,
    CONFIGURATION_EVENT_KIND_PRIVACY_MODE_RETRIEVED = 15,
    CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_REQUESTED = 16,
    CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_RETRIEVED = 17,
    /** CONFIGURATION_EVENT_KIND_CHANGED - generic config_changed (Kotlin/Dart) */
    CONFIGURATION_EVENT_KIND_CHANGED = 18,
    UNRECOGNIZED = -1
}
export declare function configurationEventKindFromJSON(object: any): ConfigurationEventKind;
export declare function configurationEventKindToJSON(object: ConfigurationEventKind): string;
export declare enum GenerationEventKind {
    GENERATION_EVENT_KIND_UNSPECIFIED = 0,
    GENERATION_EVENT_KIND_SESSION_STARTED = 1,
    GENERATION_EVENT_KIND_SESSION_ENDED = 2,
    GENERATION_EVENT_KIND_STARTED = 3,
    GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED = 4,
    GENERATION_EVENT_KIND_TOKEN_GENERATED = 5,
    GENERATION_EVENT_KIND_STREAMING_UPDATE = 6,
    GENERATION_EVENT_KIND_COMPLETED = 7,
    GENERATION_EVENT_KIND_FAILED = 8,
    GENERATION_EVENT_KIND_MODEL_LOADED = 9,
    GENERATION_EVENT_KIND_MODEL_UNLOADED = 10,
    GENERATION_EVENT_KIND_COST_CALCULATED = 11,
    GENERATION_EVENT_KIND_ROUTING_DECISION = 12,
    /** GENERATION_EVENT_KIND_STREAM_COMPLETED - Kotlin LLMEvent.STREAM_COMPLETED */
    GENERATION_EVENT_KIND_STREAM_COMPLETED = 13,
    GENERATION_EVENT_KIND_CANCEL_REQUESTED = 14,
    GENERATION_EVENT_KIND_CANCELLED = 15,
    GENERATION_EVENT_KIND_TOOL_CALL_STARTED = 16,
    GENERATION_EVENT_KIND_TOOL_CALL_COMPLETED = 17,
    GENERATION_EVENT_KIND_TOOL_CALL_FAILED = 18,
    GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_STARTED = 19,
    GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_COMPLETED = 20,
    GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_FAILED = 21,
    GENERATION_EVENT_KIND_THINKING_STARTED = 22,
    GENERATION_EVENT_KIND_THINKING_DELTA = 23,
    GENERATION_EVENT_KIND_THINKING_COMPLETED = 24,
    UNRECOGNIZED = -1
}
export declare function generationEventKindFromJSON(object: any): GenerationEventKind;
export declare function generationEventKindToJSON(object: GenerationEventKind): string;
export declare enum ModelEventKind {
    MODEL_EVENT_KIND_UNSPECIFIED = 0,
    MODEL_EVENT_KIND_LOAD_STARTED = 1,
    MODEL_EVENT_KIND_LOAD_PROGRESS = 2,
    MODEL_EVENT_KIND_LOAD_COMPLETED = 3,
    MODEL_EVENT_KIND_LOAD_FAILED = 4,
    MODEL_EVENT_KIND_UNLOAD_STARTED = 5,
    MODEL_EVENT_KIND_UNLOAD_COMPLETED = 6,
    MODEL_EVENT_KIND_UNLOAD_FAILED = 7,
    MODEL_EVENT_KIND_DOWNLOAD_STARTED = 8,
    MODEL_EVENT_KIND_DOWNLOAD_PROGRESS = 9,
    MODEL_EVENT_KIND_DOWNLOAD_COMPLETED = 10,
    MODEL_EVENT_KIND_DOWNLOAD_FAILED = 11,
    MODEL_EVENT_KIND_DOWNLOAD_CANCELLED = 12,
    MODEL_EVENT_KIND_LIST_REQUESTED = 13,
    MODEL_EVENT_KIND_LIST_COMPLETED = 14,
    MODEL_EVENT_KIND_LIST_FAILED = 15,
    MODEL_EVENT_KIND_CATALOG_LOADED = 16,
    MODEL_EVENT_KIND_DELETE_STARTED = 17,
    MODEL_EVENT_KIND_DELETE_COMPLETED = 18,
    MODEL_EVENT_KIND_DELETE_FAILED = 19,
    MODEL_EVENT_KIND_CUSTOM_MODEL_ADDED = 20,
    MODEL_EVENT_KIND_BUILT_IN_REGISTERED = 21,
    UNRECOGNIZED = -1
}
export declare function modelEventKindFromJSON(object: any): ModelEventKind;
export declare function modelEventKindToJSON(object: ModelEventKind): string;
export declare enum VoiceEventKind {
    VOICE_EVENT_KIND_UNSPECIFIED = 0,
    /** VOICE_EVENT_KIND_LISTENING_STARTED - Listening / detection. */
    VOICE_EVENT_KIND_LISTENING_STARTED = 1,
    VOICE_EVENT_KIND_LISTENING_ENDED = 2,
    VOICE_EVENT_KIND_SPEECH_DETECTED = 3,
    /** VOICE_EVENT_KIND_TRANSCRIPTION_STARTED - Transcription. */
    VOICE_EVENT_KIND_TRANSCRIPTION_STARTED = 4,
    VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL = 5,
    VOICE_EVENT_KIND_TRANSCRIPTION_FINAL = 6,
    /** VOICE_EVENT_KIND_RESPONSE_GENERATED - Response generation / synthesis. */
    VOICE_EVENT_KIND_RESPONSE_GENERATED = 7,
    VOICE_EVENT_KIND_SYNTHESIS_STARTED = 8,
    VOICE_EVENT_KIND_AUDIO_GENERATED = 9,
    VOICE_EVENT_KIND_SYNTHESIS_COMPLETED = 10,
    /** VOICE_EVENT_KIND_SYNTHESIS_FAILED - Kotlin TTSEvent.SYNTHESIS_FAILED */
    VOICE_EVENT_KIND_SYNTHESIS_FAILED = 11,
    /** VOICE_EVENT_KIND_PIPELINE_STARTED - Pipeline lifecycle (high-level orchestration). */
    VOICE_EVENT_KIND_PIPELINE_STARTED = 12,
    VOICE_EVENT_KIND_PIPELINE_COMPLETED = 13,
    VOICE_EVENT_KIND_PIPELINE_ERROR = 14,
    /** VOICE_EVENT_KIND_VAD_STARTED - VAD. */
    VOICE_EVENT_KIND_VAD_STARTED = 15,
    VOICE_EVENT_KIND_VAD_DETECTED = 16,
    VOICE_EVENT_KIND_VAD_ENDED = 17,
    VOICE_EVENT_KIND_VAD_INITIALIZED = 18,
    VOICE_EVENT_KIND_VAD_STOPPED = 19,
    VOICE_EVENT_KIND_VAD_CLEANED_UP = 20,
    VOICE_EVENT_KIND_SPEECH_STARTED = 21,
    VOICE_EVENT_KIND_SPEECH_ENDED = 22,
    /** VOICE_EVENT_KIND_STT_PROCESSING - Per-stage processing markers. */
    VOICE_EVENT_KIND_STT_PROCESSING = 23,
    VOICE_EVENT_KIND_STT_PARTIAL_RESULT = 24,
    VOICE_EVENT_KIND_STT_COMPLETED = 25,
    VOICE_EVENT_KIND_STT_FAILED = 26,
    VOICE_EVENT_KIND_LLM_PROCESSING = 27,
    VOICE_EVENT_KIND_TTS_PROCESSING = 28,
    /** VOICE_EVENT_KIND_RECORDING_STARTED - Recording. */
    VOICE_EVENT_KIND_RECORDING_STARTED = 29,
    VOICE_EVENT_KIND_RECORDING_STOPPED = 30,
    /** VOICE_EVENT_KIND_PLAYBACK_STARTED - Playback. */
    VOICE_EVENT_KIND_PLAYBACK_STARTED = 31,
    VOICE_EVENT_KIND_PLAYBACK_COMPLETED = 32,
    VOICE_EVENT_KIND_PLAYBACK_STOPPED = 33,
    VOICE_EVENT_KIND_PLAYBACK_PAUSED = 34,
    VOICE_EVENT_KIND_PLAYBACK_RESUMED = 35,
    VOICE_EVENT_KIND_PLAYBACK_FAILED = 36,
    /** VOICE_EVENT_KIND_VOICE_SESSION_STARTED - Voice session orchestration (RN events.ts:177-187). */
    VOICE_EVENT_KIND_VOICE_SESSION_STARTED = 37,
    VOICE_EVENT_KIND_VOICE_SESSION_LISTENING = 38,
    VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_STARTED = 39,
    VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_ENDED = 40,
    VOICE_EVENT_KIND_VOICE_SESSION_PROCESSING = 41,
    VOICE_EVENT_KIND_VOICE_SESSION_TRANSCRIBED = 42,
    VOICE_EVENT_KIND_VOICE_SESSION_RESPONDED = 43,
    VOICE_EVENT_KIND_VOICE_SESSION_SPEAKING = 44,
    VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED = 45,
    VOICE_EVENT_KIND_VOICE_SESSION_STOPPED = 46,
    VOICE_EVENT_KIND_VOICE_SESSION_ERROR = 47,
    UNRECOGNIZED = -1
}
export declare function voiceEventKindFromJSON(object: any): VoiceEventKind;
export declare function voiceEventKindToJSON(object: VoiceEventKind): string;
export declare enum PerformanceEventKind {
    PERFORMANCE_EVENT_KIND_UNSPECIFIED = 0,
    PERFORMANCE_EVENT_KIND_MEMORY_WARNING = 1,
    PERFORMANCE_EVENT_KIND_THERMAL_STATE_CHANGED = 2,
    PERFORMANCE_EVENT_KIND_LATENCY_MEASURED = 3,
    PERFORMANCE_EVENT_KIND_THROUGHPUT_MEASURED = 4,
    UNRECOGNIZED = -1
}
export declare function performanceEventKindFromJSON(object: any): PerformanceEventKind;
export declare function performanceEventKindToJSON(object: PerformanceEventKind): string;
export declare enum NetworkEventKind {
    NETWORK_EVENT_KIND_UNSPECIFIED = 0,
    NETWORK_EVENT_KIND_REQUEST_STARTED = 1,
    NETWORK_EVENT_KIND_REQUEST_COMPLETED = 2,
    NETWORK_EVENT_KIND_REQUEST_FAILED = 3,
    NETWORK_EVENT_KIND_REQUEST_TIMEOUT = 4,
    NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED = 5,
    UNRECOGNIZED = -1
}
export declare function networkEventKindFromJSON(object: any): NetworkEventKind;
export declare function networkEventKindToJSON(object: NetworkEventKind): string;
export declare enum StorageEventKind {
    STORAGE_EVENT_KIND_UNSPECIFIED = 0,
    STORAGE_EVENT_KIND_INFO_REQUESTED = 1,
    STORAGE_EVENT_KIND_INFO_RETRIEVED = 2,
    STORAGE_EVENT_KIND_MODELS_REQUESTED = 3,
    STORAGE_EVENT_KIND_MODELS_RETRIEVED = 4,
    STORAGE_EVENT_KIND_CLEAR_CACHE_STARTED = 5,
    STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED = 6,
    STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED = 7,
    STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED = 8,
    STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED = 9,
    STORAGE_EVENT_KIND_CLEAN_TEMP_FAILED = 10,
    STORAGE_EVENT_KIND_DELETE_MODEL_STARTED = 11,
    STORAGE_EVENT_KIND_DELETE_MODEL_COMPLETED = 12,
    STORAGE_EVENT_KIND_DELETE_MODEL_FAILED = 13,
    STORAGE_EVENT_KIND_CACHE_HIT = 14,
    STORAGE_EVENT_KIND_CACHE_MISS = 15,
    STORAGE_EVENT_KIND_EVICTION = 16,
    STORAGE_EVENT_KIND_DISK_FULL = 17,
    UNRECOGNIZED = -1
}
export declare function storageEventKindFromJSON(object: any): StorageEventKind;
export declare function storageEventKindToJSON(object: StorageEventKind): string;
export declare enum FrameworkEventKind {
    FRAMEWORK_EVENT_KIND_UNSPECIFIED = 0,
    FRAMEWORK_EVENT_KIND_ADAPTER_REGISTERED = 1,
    FRAMEWORK_EVENT_KIND_ADAPTER_UNREGISTERED = 2,
    FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED = 3,
    FRAMEWORK_EVENT_KIND_ADAPTERS_RETRIEVED = 4,
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_REQUESTED = 5,
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_RETRIEVED = 6,
    FRAMEWORK_EVENT_KIND_AVAILABILITY_REQUESTED = 7,
    FRAMEWORK_EVENT_KIND_AVAILABILITY_RETRIEVED = 8,
    FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_REQUESTED = 9,
    FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_RETRIEVED = 10,
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_REQUESTED = 11,
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_RETRIEVED = 12,
    FRAMEWORK_EVENT_KIND_ERROR = 13,
    UNRECOGNIZED = -1
}
export declare function frameworkEventKindFromJSON(object: any): FrameworkEventKind;
export declare function frameworkEventKindToJSON(object: FrameworkEventKind): string;
export declare enum DeviceEventKind {
    DEVICE_EVENT_KIND_UNSPECIFIED = 0,
    DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTED = 1,
    DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTION_FAILED = 2,
    DEVICE_EVENT_KIND_DEVICE_INFO_REFRESHED = 3,
    DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_STARTED = 4,
    DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_COMPLETED = 5,
    DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_FAILED = 6,
    DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED = 7,
    DEVICE_EVENT_KIND_BATTERY_CHANGED = 8,
    DEVICE_EVENT_KIND_THERMAL_CHANGED = 9,
    DEVICE_EVENT_KIND_CONNECTIVITY_CHANGED = 10,
    /** DEVICE_EVENT_KIND_DEVICE_REGISTERED - Dart DeviceRegistered */
    DEVICE_EVENT_KIND_DEVICE_REGISTERED = 11,
    /** DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED - Dart DeviceRegistrationFailed */
    DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED = 12,
    UNRECOGNIZED = -1
}
export declare function deviceEventKindFromJSON(object: any): DeviceEventKind;
export declare function deviceEventKindToJSON(object: DeviceEventKind): string;
export declare enum ComponentInitializationEventKind {
    COMPONENT_INIT_EVENT_KIND_UNSPECIFIED = 0,
    COMPONENT_INIT_EVENT_KIND_INITIALIZATION_STARTED = 1,
    COMPONENT_INIT_EVENT_KIND_INITIALIZATION_COMPLETED = 2,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED = 3,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_CHECKING = 4,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED = 5,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_STARTED = 6,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_PROGRESS = 7,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_COMPLETED = 8,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_INITIALIZING = 9,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_READY = 10,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_FAILED = 11,
    COMPONENT_INIT_EVENT_KIND_PARALLEL_INIT_STARTED = 12,
    COMPONENT_INIT_EVENT_KIND_SEQUENTIAL_INIT_STARTED = 13,
    COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY = 14,
    COMPONENT_INIT_EVENT_KIND_SOME_COMPONENTS_READY = 15,
    UNRECOGNIZED = -1
}
export declare function componentInitializationEventKindFromJSON(object: any): ComponentInitializationEventKind;
export declare function componentInitializationEventKindToJSON(object: ComponentInitializationEventKind): string;
export declare enum SessionEventKind {
    SESSION_EVENT_KIND_UNSPECIFIED = 0,
    SESSION_EVENT_KIND_CREATED = 1,
    SESSION_EVENT_KIND_STARTED = 2,
    SESSION_EVENT_KIND_RESUMED = 3,
    SESSION_EVENT_KIND_PAUSED = 4,
    SESSION_EVENT_KIND_ENDED = 5,
    SESSION_EVENT_KIND_EXPIRED = 6,
    SESSION_EVENT_KIND_FAILED = 7,
    UNRECOGNIZED = -1
}
export declare function sessionEventKindFromJSON(object: any): SessionEventKind;
export declare function sessionEventKindToJSON(object: SessionEventKind): string;
export declare enum AuthEventKind {
    AUTH_EVENT_KIND_UNSPECIFIED = 0,
    AUTH_EVENT_KIND_REQUESTED = 1,
    AUTH_EVENT_KIND_SUCCEEDED = 2,
    AUTH_EVENT_KIND_FAILED = 3,
    AUTH_EVENT_KIND_TOKEN_REFRESHED = 4,
    AUTH_EVENT_KIND_TOKEN_EXPIRED = 5,
    AUTH_EVENT_KIND_DEVICE_REGISTERED = 6,
    AUTH_EVENT_KIND_DEVICE_REGISTRATION_FAILED = 7,
    UNRECOGNIZED = -1
}
export declare function authEventKindFromJSON(object: any): AuthEventKind;
export declare function authEventKindToJSON(object: AuthEventKind): string;
export declare enum ModelRegistryEventKind {
    MODEL_REGISTRY_EVENT_KIND_UNSPECIFIED = 0,
    MODEL_REGISTRY_EVENT_KIND_REFRESH_STARTED = 1,
    MODEL_REGISTRY_EVENT_KIND_REFRESH_COMPLETED = 2,
    MODEL_REGISTRY_EVENT_KIND_REFRESH_FAILED = 3,
    MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_STARTED = 4,
    MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_COMPLETED = 5,
    MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_FAILED = 6,
    MODEL_REGISTRY_EVENT_KIND_IMPORT_STARTED = 7,
    MODEL_REGISTRY_EVENT_KIND_IMPORT_COMPLETED = 8,
    MODEL_REGISTRY_EVENT_KIND_IMPORT_FAILED = 9,
    MODEL_REGISTRY_EVENT_KIND_DISCOVERY_STARTED = 10,
    MODEL_REGISTRY_EVENT_KIND_DISCOVERY_COMPLETED = 11,
    MODEL_REGISTRY_EVENT_KIND_DISCOVERY_FAILED = 12,
    MODEL_REGISTRY_EVENT_KIND_CURRENT_MODEL_CHANGED = 13,
    UNRECOGNIZED = -1
}
export declare function modelRegistryEventKindFromJSON(object: any): ModelRegistryEventKind;
export declare function modelRegistryEventKindToJSON(object: ModelRegistryEventKind): string;
export declare enum DownloadEventKind {
    DOWNLOAD_EVENT_KIND_UNSPECIFIED = 0,
    DOWNLOAD_EVENT_KIND_PLAN_STARTED = 1,
    DOWNLOAD_EVENT_KIND_PLAN_COMPLETED = 2,
    DOWNLOAD_EVENT_KIND_PLAN_FAILED = 3,
    DOWNLOAD_EVENT_KIND_STARTED = 4,
    DOWNLOAD_EVENT_KIND_PROGRESS = 5,
    DOWNLOAD_EVENT_KIND_CANCEL_REQUESTED = 6,
    DOWNLOAD_EVENT_KIND_CANCELLED = 7,
    DOWNLOAD_EVENT_KIND_RESUME_REQUESTED = 8,
    DOWNLOAD_EVENT_KIND_RESUMED = 9,
    DOWNLOAD_EVENT_KIND_COMPLETED = 10,
    DOWNLOAD_EVENT_KIND_FAILED = 11,
    UNRECOGNIZED = -1
}
export declare function downloadEventKindFromJSON(object: any): DownloadEventKind;
export declare function downloadEventKindToJSON(object: DownloadEventKind): string;
export declare enum StorageLifecycleEventKind {
    STORAGE_LIFECYCLE_EVENT_KIND_UNSPECIFIED = 0,
    STORAGE_LIFECYCLE_EVENT_KIND_INFO_STARTED = 1,
    STORAGE_LIFECYCLE_EVENT_KIND_INFO_COMPLETED = 2,
    STORAGE_LIFECYCLE_EVENT_KIND_AVAILABILITY_CHECKED = 3,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_PLAN_CREATED = 4,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_STARTED = 5,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_COMPLETED = 6,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_FAILED = 7,
    STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_STARTED = 8,
    STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_COMPLETED = 9,
    STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_FAILED = 10,
    UNRECOGNIZED = -1
}
export declare function storageLifecycleEventKindFromJSON(object: any): StorageLifecycleEventKind;
export declare function storageLifecycleEventKindToJSON(object: StorageLifecycleEventKind): string;
export declare enum HardwareRoutingEventKind {
    HARDWARE_ROUTING_EVENT_KIND_UNSPECIFIED = 0,
    HARDWARE_ROUTING_EVENT_KIND_PROFILE_STARTED = 1,
    HARDWARE_ROUTING_EVENT_KIND_PROFILE_COMPLETED = 2,
    HARDWARE_ROUTING_EVENT_KIND_PROFILE_FAILED = 3,
    HARDWARE_ROUTING_EVENT_KIND_ROUTE_SELECTED = 4,
    HARDWARE_ROUTING_EVENT_KIND_ROUTE_CHANGED = 5,
    HARDWARE_ROUTING_EVENT_KIND_FRAMEWORK_CAPABILITY_DETECTED = 6,
    HARDWARE_ROUTING_EVENT_KIND_FRAMEWORK_CAPABILITY_MISSING = 7,
    UNRECOGNIZED = -1
}
export declare function hardwareRoutingEventKindFromJSON(object: any): HardwareRoutingEventKind;
export declare function hardwareRoutingEventKindToJSON(object: HardwareRoutingEventKind): string;
export declare enum CapabilityOperationEventKind {
    CAPABILITY_OPERATION_EVENT_KIND_UNSPECIFIED = 0,
    CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED = 1,
    CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED = 2,
    CAPABILITY_OPERATION_EVENT_KIND_VLM_FAILED = 3,
    CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED = 4,
    CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_PROGRESS = 5,
    CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED = 6,
    CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_FAILED = 7,
    CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_STARTED = 8,
    CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED = 9,
    CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_FAILED = 10,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_STARTED = 11,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED = 12,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_STARTED = 13,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED = 14,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_FAILED = 15,
    CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED = 16,
    CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED = 17,
    CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED = 18,
    UNRECOGNIZED = -1
}
export declare function capabilityOperationEventKindFromJSON(object: any): CapabilityOperationEventKind;
export declare function capabilityOperationEventKindToJSON(object: CapabilityOperationEventKind): string;
export declare enum TelemetryEventKind {
    TELEMETRY_EVENT_KIND_UNSPECIFIED = 0,
    TELEMETRY_EVENT_KIND_COUNTER = 1,
    TELEMETRY_EVENT_KIND_GAUGE = 2,
    TELEMETRY_EVENT_KIND_HISTOGRAM = 3,
    TELEMETRY_EVENT_KIND_TRACE = 4,
    UNRECOGNIZED = -1
}
export declare function telemetryEventKindFromJSON(object: any): TelemetryEventKind;
export declare function telemetryEventKindToJSON(object: TelemetryEventKind): string;
export declare enum CancellationEventKind {
    CANCELLATION_EVENT_KIND_UNSPECIFIED = 0,
    CANCELLATION_EVENT_KIND_REQUESTED = 1,
    CANCELLATION_EVENT_KIND_ACKNOWLEDGED = 2,
    CANCELLATION_EVENT_KIND_COMPLETED = 3,
    CANCELLATION_EVENT_KIND_FAILED = 4,
    UNRECOGNIZED = -1
}
export declare function cancellationEventKindFromJSON(object: any): CancellationEventKind;
export declare function cancellationEventKindToJSON(object: CancellationEventKind): string;
/**
 * ---------------------------------------------------------------------------
 * SDK lifecycle / initialization stage events. Mirrors
 *   RN  events.ts:38-43 (SDKInitializationEvent: 5 variants)
 * Plus integrated "configurationLoaded" source field. NOT to be confused
 * with `ComponentInitializationEvent` (per-component lifecycle).
 * ---------------------------------------------------------------------------
 */
export interface InitializationEvent {
    stage: InitializationStage;
    /** for `CONFIGURATION_LOADED` (e.g. "remote", "local", "builtin") */
    source: string;
    /** populated when stage == FAILED */
    error: string;
    /** SDK version (Kotlin SDKLifecycleEvent.version) */
    version: string;
}
/**
 * ---------------------------------------------------------------------------
 * Configuration events — fetch / load / sync / settings retrieval / privacy /
 * routing-policy / analytics-status changes. Mirrors RN
 *   events.ts:49-66 (SDKConfigurationEvent: 17 variants).
 * ---------------------------------------------------------------------------
 */
export interface ConfigurationEvent {
    kind: ConfigurationEventKind;
    /** Source of configuration (`fetchCompleted.source`, `loaded.source`, …). */
    source: string;
    /** Populated on FAILED variants (fetchFailed / syncFailed). */
    error: string;
    /**
     * List of changed top-level keys (configurationUpdated). Kept as
     * strings since each SDK uses different KV value types; analytics
     * only cares about which keys moved.
     */
    changedKeys: string[];
    /**
     * For settings_retrieved — the resulting settings serialized as JSON.
     * Avoids embedding DefaultGenerationSettings here (lives in llm_options
     * / config protos).
     */
    settingsJson: string;
    /** For routing_policy_retrieved (RN events.ts:62 — `policy: string`). */
    routingPolicy: string;
    /** For privacy_mode_retrieved (RN events.ts:64). */
    privacyMode: string;
    /** For analytics_status_retrieved (RN events.ts:66 — `enabled: boolean`). */
    analyticsEnabled: boolean;
    /**
     * Old / new value pairs for config_changed (canonical primitive
     * representation). Both stored as JSON-encoded strings to avoid
     * dragging a dynamic-typed `Value` into the schema.
     */
    oldValueJson: string;
    newValueJson: string;
}
/**
 * ---------------------------------------------------------------------------
 * LLM generation events. Mirrors RN
 *   events.ts:72-89 (SDKGenerationEvent: 12 variants).
 * Plus Kotlin LLMEvent (5 variants), Dart SDKGenerationEvent (4 factories).
 * ---------------------------------------------------------------------------
 */
export interface GenerationEvent {
    kind: GenerationEventKind;
    /** Optional session id (RN voiceSession_*, generationStarted.sessionId). */
    sessionId: string;
    /** For STARTED — the prompt text (RN events.ts:75). */
    prompt: string;
    /** For TOKEN_GENERATED / FIRST_TOKEN_GENERATED — single token text. */
    token: string;
    /** For STREAMING_UPDATE — the running response text and token count. */
    streamingText: string;
    tokensCount: number;
    /** For COMPLETED — full response, usage stats, latency. */
    response: string;
    tokensUsed: number;
    latencyMs: number;
    /** For FIRST_TOKEN_GENERATED — TTFT in ms (RN events.ts:76). */
    firstTokenLatencyMs: number;
    /** For FAILED. */
    error: string;
    /** For MODEL_LOADED / MODEL_UNLOADED — bound model. */
    modelId: string;
    /** For COST_CALCULATED — RN events.ts:88, Dart SDKGenerationCostCalculated. */
    costAmount: number;
    costSavedAmount: number;
    /** For ROUTING_DECISION — RN events.ts:89. */
    routingTarget: string;
    routingReason: string;
    /** For cancellation / tool / structured-output / thinking events. */
    cancelReason: string;
    toolCallId: string;
    toolName: string;
    toolPayloadJson: string;
    structuredSchemaJson: string;
    structuredOutputJson: string;
    thinkingText: string;
}
/**
 * ---------------------------------------------------------------------------
 * Model lifecycle events: load / unload / download / list / catalog / delete /
 * custom-model / built-in-registration. Mirrors RN
 *   events.ts:95-130 (SDKModelEvent: 24 variants).
 * Plus Kotlin ModelEvent (7 ModelEventType) and Dart SDKModelEvent (10
 * concrete classes).
 * ---------------------------------------------------------------------------
 */
export interface ModelEvent {
    kind: ModelEventKind;
    modelId: string;
    /** present on RN download events */
    taskId: string;
    /** For LOAD_PROGRESS / DOWNLOAD_PROGRESS — 0.0..1.0. */
    progress: number;
    /** For DOWNLOAD_PROGRESS — bytes counters. */
    bytesDownloaded: number;
    totalBytes: number;
    /** For DOWNLOAD_PROGRESS — engine-level state string (RN events.ts:111). */
    downloadState: string;
    /** For DOWNLOAD_COMPLETED — landed local path (RN events.ts:118). */
    localPath: string;
    /** For *_FAILED. */
    error: string;
    /**
     * For LIST_COMPLETED / CATALOG_LOADED — count only; the full
     * ModelInfo array travels via response RPCs, not via events.
     */
    modelCount: number;
    /** For CUSTOM_MODEL_ADDED — RN events.ts:129. */
    customModelName: string;
    customModelUrl: string;
}
/**
 * ---------------------------------------------------------------------------
 * Voice / audio higher-level events. Mirrors RN
 *   events.ts:136-187 (SDKVoiceEvent: 41 variants).
 * Plus Dart SDKVoiceEvent (~15 concrete classes), Kotlin STTEvent + TTSEvent.
 *
 * Renamed from `VoiceEvent` to `VoiceLifecycleEvent` to avoid colliding with
 * `runanywhere.v1.VoiceEvent` from voice_events.proto, which carries the
 * low-level streaming pipeline payloads (UserSaid / AssistantToken /
 * AudioFrame / VAD / Interrupted / StateChange / Error / Metrics). The
 * pipeline events are exposed via SDKEvent.voice_pipeline; this message
 * is exposed via SDKEvent.voice.
 * ---------------------------------------------------------------------------
 */
export interface VoiceLifecycleEvent {
    kind: VoiceEventKind;
    /** For listeningStarted / voiceSession_* — optional session id. */
    sessionId: string;
    /**
     * For TRANSCRIPTION_PARTIAL / TRANSCRIPTION_FINAL / STT_PARTIAL_RESULT /
     * STT_COMPLETED.
     */
    text: string;
    confidence: number;
    /** For RESPONSE_GENERATED. */
    responseText: string;
    /** For AUDIO_GENERATED — base64-encoded PCM (RN events.ts:145). */
    audioBase64: string;
    /**
     * For RECORDING_STOPPED / PLAYBACK_STARTED / PLAYBACK_COMPLETED —
     * duration in milliseconds (RN events.ts:158, 160-161).
     */
    durationMs: number;
    /** For VOICE_SESSION_LISTENING — current audio level (RN events.ts:178). */
    audioLevel: number;
    /**
     * For VOICE_SESSION_TRANSCRIBED / VOICE_SESSION_RESPONDED /
     * VOICE_SESSION_TURN_COMPLETED — RN events.ts:182-185.
     */
    transcription: string;
    turnResponse: string;
    turnAudioBase64: string;
    /** For *_ERROR / *_FAILED. */
    error: string;
}
/**
 * ---------------------------------------------------------------------------
 * Performance metrics events. Mirrors RN
 *   events.ts:193-197 (SDKPerformanceEvent: 4 variants).
 * ---------------------------------------------------------------------------
 */
export interface PerformanceEvent {
    kind: PerformanceEventKind;
    /** For MEMORY_WARNING — usage in bytes (RN typed as number). */
    memoryBytes: number;
    /**
     * For THERMAL_STATE_CHANGED — engine-defined state string
     * (e.g. "nominal", "fair", "serious", "critical"; Apple-specific
     * names preserved as strings to avoid platform-coupled enums).
     */
    thermalState: string;
    /** For LATENCY_MEASURED. */
    operation: string;
    milliseconds: number;
    /** For THROUGHPUT_MEASURED — RN events.ts:197. */
    tokensPerSecond: number;
}
/**
 * ---------------------------------------------------------------------------
 * Network events. Mirrors RN
 *   events.ts:203-207 (SDKNetworkEvent: 4 variants).
 * ---------------------------------------------------------------------------
 */
export interface NetworkEvent {
    kind: NetworkEventKind;
    url: string;
    /** For REQUEST_COMPLETED — HTTP status (RN events.ts:205). */
    statusCode: number;
    /** For CONNECTIVITY_CHANGED — RN events.ts:207. */
    isOnline: boolean;
    /** For REQUEST_FAILED / TIMEOUT. */
    error: string;
    /**
     * For REQUEST_COMPLETED — response time in ms (canonical addition,
     * implied by Kotlin/iOS request timing instrumentation).
     */
    latencyMs: number;
}
/**
 * ---------------------------------------------------------------------------
 * Storage events. Mirrors RN
 *   events.ts:213-226 (SDKStorageEvent: 13 variants).
 * Plus Dart SDKStorageEvent (cacheCleared, tempFilesCleaned).
 * ---------------------------------------------------------------------------
 */
export interface StorageEvent {
    kind: StorageEventKind;
    /** For DELETE_MODEL_* events. */
    modelId: string;
    /** For *_FAILED. */
    error: string;
    /** For INFO_RETRIEVED — total/available bytes (StorageInfo summary). */
    totalBytes: number;
    availableBytes: number;
    usedBytes: number;
    /** For MODELS_RETRIEVED. */
    storedModelCount: number;
    /**
     * For CACHE_HIT / CACHE_MISS / EVICTION (canonical superset additions
     * not in RN's events.ts but called out in Step 3 spec).
     */
    cacheKey: string;
    evictedBytes: number;
}
/**
 * ---------------------------------------------------------------------------
 * Framework registry events. Mirrors RN
 *   events.ts:232-251 (SDKFrameworkEvent: 11 variants).
 * ---------------------------------------------------------------------------
 */
export interface FrameworkEvent {
    kind: FrameworkEventKind;
    /**
     * For ADAPTER_REGISTERED / *_RETRIEVED — bound framework. Uses
     * canonical InferenceFramework from model_types.proto, but stored as
     * its enum int32 here to avoid cross-file message dependency just for
     * a single field. Frontends decode via the shared codegen.
     */
    framework: number;
    /** For ADAPTER_REGISTERED — adapter display name. */
    adapterName: string;
    /** For ADAPTERS_RETRIEVED / *_RETRIEVED — counts. */
    adapterCount: number;
    frameworkCount: number;
    /**
     * For MODELS_FOR_FRAMEWORK_RETRIEVED — model count (full ModelInfo[]
     * travels via RPCs, not events).
     */
    modelCount: number;
    /**
     * For *_FOR_MODALITY_* — modality identifier (string-keyed; canonical
     * FrameworkModality enum exists in model_types but we keep this loose
     * so plugins can register custom modalities).
     */
    modality: string;
    /** For ERROR / UNREGISTERED failures (canonical superset additions). */
    error: string;
}
/**
 * ---------------------------------------------------------------------------
 * Device events: device-info collection / sync, plus battery / thermal /
 * connectivity changes (canonical superset; Kotlin's analytics layer
 * already emits these as raw `BaseSDKEvent`s with category=device).
 * Mirrors RN events.ts:257-264 (SDKDeviceEvent: 7 variants).
 * ---------------------------------------------------------------------------
 */
export interface DeviceEvent {
    kind: DeviceEventKind;
    /**
     * For DEVICE_INFO_COLLECTED / REFRESHED — populated state-key/value
     * pairs (avoid embedding full DeviceInfoData; that lives in its own
     * proto). The summary fields below are the most-queried subset.
     */
    deviceId: string;
    osName: string;
    osVersion: string;
    model: string;
    /** For *_FAILED. */
    error: string;
    /** For DEVICE_STATE_CHANGED — RN events.ts:264. */
    property: string;
    newValue: string;
    oldValue: string;
    /** For BATTERY_CHANGED / THERMAL_CHANGED / CONNECTIVITY_CHANGED. */
    batteryLevel: number;
    isCharging: boolean;
    /** free-form (Apple-specific names) */
    thermalState: string;
    isConnected: boolean;
    /** "wifi", "cellular", "ethernet", ... */
    connectionType: string;
}
/**
 * ---------------------------------------------------------------------------
 * Per-component initialization lifecycle. Mirrors RN
 *   events.ts:270-312 (ComponentInitializationEvent: 16 variants).
 * Distinct from `InitializationEvent` (overall SDK lifecycle).
 * ---------------------------------------------------------------------------
 */
export interface ComponentInitializationEvent {
    kind: ComponentInitializationEventKind;
    /** Single-component events (componentChecking / componentReady / …). */
    component: SDKComponent;
    /**
     * For COMPONENT_CHECKING / COMPONENT_INITIALIZING / COMPONENT_READY /
     * download events.
     */
    modelId: string;
    /** For COMPONENT_DOWNLOAD_REQUIRED — RN events.ts:285. */
    sizeBytes: number;
    /** For COMPONENT_DOWNLOAD_PROGRESS — 0.0..1.0. */
    progress: number;
    /** For COMPONENT_FAILED / *_FAILED. */
    error: string;
    /** For COMPONENT_STATE_CHANGED — RN events.ts:274-278. */
    oldState: string;
    newState: string;
    /**
     * For multi-component events (initializationStarted / parallel/sequential /
     * someComponentsReady).
     */
    components: SDKComponent[];
    readyComponents: SDKComponent[];
    pendingComponents: SDKComponent[];
    /**
     * For INITIALIZATION_COMPLETED — InitializationResult summary
     * (success bool + count). Full result travels via dedicated RPC.
     */
    initSuccess: boolean;
    readyCount: number;
    failedCount: number;
    /**
     * Typed equivalents of old_state/new_state for SDKs that want generated
     * enum-backed component lifecycle state instead of parsing strings.
     */
    previousLifecycleState: ComponentLifecycleState;
    currentLifecycleState: ComponentLifecycleState;
}
/** Snapshot of a component's current model-backed lifecycle state. */
export interface ComponentLifecycleSnapshot {
    component: SDKComponent;
    state: ComponentLifecycleState;
    modelId: string;
    updatedAtMs: number;
    errorMessage: string;
}
/**
 * Operation-aware lifecycle event. The oneof arms intentionally reference the
 * operation result/progress protos from this contract slice instead of adding
 * another broad event taxonomy.
 */
export interface ComponentLifecycleEvent {
    component: SDKComponent;
    previousState: ComponentLifecycleState;
    currentState: ComponentLifecycleState;
    modelId: string;
    timestampMs: number;
    modelLoadResult?: ModelLoadResult | undefined;
    modelUnloadResult?: ModelUnloadResult | undefined;
    modelDeleteResult?: ModelDeleteResult | undefined;
    downloadProgress?: DownloadProgress | undefined;
    storageAvailability?: StorageAvailabilityResult | undefined;
    storageDeleteResult?: StorageDeleteResult | undefined;
}
/** SDK session lifecycle independent of voice-agent turn sessions. */
export interface SessionEvent {
    kind: SessionEventKind;
    sessionId: string;
    userId: string;
    reason: string;
    error: string;
    startedAtMs: number;
    endedAtMs: number;
}
export interface AuthEvent {
    kind: AuthEventKind;
    provider: string;
    subjectId: string;
    scope: string;
    error: string;
}
export interface ModelRegistryEvent {
    kind: ModelRegistryEventKind;
    modelId: string;
    assignmentId: string;
    assignedComponent: SDKComponent;
    framework: InferenceFramework;
    sourcePath: string;
    error: string;
    refreshResult?: ModelRegistryRefreshResult | undefined;
    listResult?: ModelListResult | undefined;
    getResult?: ModelGetResult | undefined;
    importResult?: ModelImportResult | undefined;
    discoveryResult?: ModelDiscoveryResult | undefined;
    compatibilityResult?: ModelCompatibilityResult | undefined;
    currentModelResult?: CurrentModelResult | undefined;
}
export interface DownloadEvent {
    kind: DownloadEventKind;
    modelId: string;
    taskId: string;
    error: string;
    planResult?: DownloadPlanResult | undefined;
    startResult?: DownloadStartResult | undefined;
    progress?: DownloadProgress | undefined;
    cancelResult?: DownloadCancelResult | undefined;
    resumeResult?: DownloadResumeResult | undefined;
}
export interface StorageLifecycleEvent {
    kind: StorageLifecycleEventKind;
    modelId: string;
    cacheKey: string;
    bytes: number;
    error: string;
    infoResult?: StorageInfoResult | undefined;
    availabilityResult?: StorageAvailabilityResult | undefined;
    deletePlan?: StorageDeletePlan | undefined;
    deleteResult?: StorageDeleteResult | undefined;
}
export interface HardwareRoutingEvent {
    kind: HardwareRoutingEventKind;
    component: SDKComponent;
    framework: InferenceFramework;
    capability: string;
    route: string;
    reason: string;
    error: string;
    hardwareProfile?: HardwareProfileResult | undefined;
}
export interface CapabilityOperationEvent {
    kind: CapabilityOperationEventKind;
    component: SDKComponent;
    modelId: string;
    operationId: string;
    operation: string;
    progress: number;
    inputCount: number;
    outputCount: number;
    resultJson: string;
    error: string;
}
export interface TelemetryEvent {
    kind: TelemetryEventKind;
    name: string;
    attributes: {
        [key: string]: string;
    };
    value: number;
    unit: string;
}
export interface TelemetryEvent_AttributesEntry {
    key: string;
    value: string;
}
export interface CancellationEvent {
    kind: CancellationEventKind;
    component: SDKComponent;
    operationId: string;
    reason: string;
    userInitiated: boolean;
}
export interface FailureEvent {
    component: SDKComponent;
    operation: string;
    error?: SDKError | undefined;
    recoverable: boolean;
}
/**
 * ---------------------------------------------------------------------------
 * Top-level event envelope. Every event published by every SDK is wrapped in
 * exactly one `SDKEvent` — analytics consumers, app developers, and
 * pipelines all decode the same bytes.
 *
 * `voice_pipeline` carries the streaming voice pipeline events from
 * `voice_events.proto` (UserSaid / AssistantToken / AudioFrame / VAD /
 * Interrupted / StateChange / Error / Metrics). Higher-level voice
 * lifecycle events live in this file's `voice` field.
 * ---------------------------------------------------------------------------
 */
export interface SDKEvent {
    /** Wall-clock time of event creation, milliseconds since Unix epoch. */
    timestampMs: number;
    severity: EventSeverity;
    category: EventCategory;
    component: SDKComponent;
    /**
     * Typed failure details for any failed event. When the event itself is
     * only an error notification, use the failure oneof arm below.
     */
    error?: SDKError | undefined;
    /**
     * Event identifier (UUID). Required by Swift SDKEvent.id /
     * Kotlin SDKEvent.id / Dart SDKEvent.id for de-duplication.
     */
    id: string;
    /**
     * Optional session id for grouping related events
     * (Swift sessionId / Kotlin sessionId / Dart sessionId).
     */
    sessionId: string;
    /**
     * Event routing destination (Swift EventDestination, Kotlin
     * EventDestination, Dart EventDestination).
     */
    destination: EventDestination;
    /**
     * Free-form metadata for properties not modeled above
     * (mirrors `properties: Map<String, String>` from each SDK).
     */
    properties: {
        [key: string]: string;
    };
    initialization?: InitializationEvent | undefined;
    configuration?: ConfigurationEvent | undefined;
    generation?: GenerationEvent | undefined;
    model?: ModelEvent | undefined;
    performance?: PerformanceEvent | undefined;
    network?: NetworkEvent | undefined;
    storage?: StorageEvent | undefined;
    framework?: FrameworkEvent | undefined;
    device?: DeviceEvent | undefined;
    componentInit?: ComponentInitializationEvent | undefined;
    voice?: VoiceLifecycleEvent | undefined;
    /** from voice_events.proto */
    voicePipeline?: VoiceEvent | undefined;
    componentLifecycle?: ComponentLifecycleEvent | undefined;
    session?: SessionEvent | undefined;
    auth?: AuthEvent | undefined;
    modelRegistry?: ModelRegistryEvent | undefined;
    download?: DownloadEvent | undefined;
    storageLifecycle?: StorageLifecycleEvent | undefined;
    hardwareRouting?: HardwareRoutingEvent | undefined;
    capability?: CapabilityOperationEvent | undefined;
    telemetry?: TelemetryEvent | undefined;
    cancellation?: CancellationEvent | undefined;
    failure?: FailureEvent | undefined;
}
export interface SDKEvent_PropertiesEntry {
    key: string;
    value: string;
}
export declare const InitializationEvent: {
    encode(message: InitializationEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): InitializationEvent;
    fromJSON(object: any): InitializationEvent;
    toJSON(message: InitializationEvent): unknown;
    create<I extends Exact<DeepPartial<InitializationEvent>, I>>(base?: I): InitializationEvent;
    fromPartial<I extends Exact<DeepPartial<InitializationEvent>, I>>(object: I): InitializationEvent;
};
export declare const ConfigurationEvent: {
    encode(message: ConfigurationEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ConfigurationEvent;
    fromJSON(object: any): ConfigurationEvent;
    toJSON(message: ConfigurationEvent): unknown;
    create<I extends Exact<DeepPartial<ConfigurationEvent>, I>>(base?: I): ConfigurationEvent;
    fromPartial<I extends Exact<DeepPartial<ConfigurationEvent>, I>>(object: I): ConfigurationEvent;
};
export declare const GenerationEvent: {
    encode(message: GenerationEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): GenerationEvent;
    fromJSON(object: any): GenerationEvent;
    toJSON(message: GenerationEvent): unknown;
    create<I extends Exact<DeepPartial<GenerationEvent>, I>>(base?: I): GenerationEvent;
    fromPartial<I extends Exact<DeepPartial<GenerationEvent>, I>>(object: I): GenerationEvent;
};
export declare const ModelEvent: {
    encode(message: ModelEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelEvent;
    fromJSON(object: any): ModelEvent;
    toJSON(message: ModelEvent): unknown;
    create<I extends Exact<DeepPartial<ModelEvent>, I>>(base?: I): ModelEvent;
    fromPartial<I extends Exact<DeepPartial<ModelEvent>, I>>(object: I): ModelEvent;
};
export declare const VoiceLifecycleEvent: {
    encode(message: VoiceLifecycleEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): VoiceLifecycleEvent;
    fromJSON(object: any): VoiceLifecycleEvent;
    toJSON(message: VoiceLifecycleEvent): unknown;
    create<I extends Exact<DeepPartial<VoiceLifecycleEvent>, I>>(base?: I): VoiceLifecycleEvent;
    fromPartial<I extends Exact<DeepPartial<VoiceLifecycleEvent>, I>>(object: I): VoiceLifecycleEvent;
};
export declare const PerformanceEvent: {
    encode(message: PerformanceEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): PerformanceEvent;
    fromJSON(object: any): PerformanceEvent;
    toJSON(message: PerformanceEvent): unknown;
    create<I extends Exact<DeepPartial<PerformanceEvent>, I>>(base?: I): PerformanceEvent;
    fromPartial<I extends Exact<DeepPartial<PerformanceEvent>, I>>(object: I): PerformanceEvent;
};
export declare const NetworkEvent: {
    encode(message: NetworkEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): NetworkEvent;
    fromJSON(object: any): NetworkEvent;
    toJSON(message: NetworkEvent): unknown;
    create<I extends Exact<DeepPartial<NetworkEvent>, I>>(base?: I): NetworkEvent;
    fromPartial<I extends Exact<DeepPartial<NetworkEvent>, I>>(object: I): NetworkEvent;
};
export declare const StorageEvent: {
    encode(message: StorageEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): StorageEvent;
    fromJSON(object: any): StorageEvent;
    toJSON(message: StorageEvent): unknown;
    create<I extends Exact<DeepPartial<StorageEvent>, I>>(base?: I): StorageEvent;
    fromPartial<I extends Exact<DeepPartial<StorageEvent>, I>>(object: I): StorageEvent;
};
export declare const FrameworkEvent: {
    encode(message: FrameworkEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): FrameworkEvent;
    fromJSON(object: any): FrameworkEvent;
    toJSON(message: FrameworkEvent): unknown;
    create<I extends Exact<DeepPartial<FrameworkEvent>, I>>(base?: I): FrameworkEvent;
    fromPartial<I extends Exact<DeepPartial<FrameworkEvent>, I>>(object: I): FrameworkEvent;
};
export declare const DeviceEvent: {
    encode(message: DeviceEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DeviceEvent;
    fromJSON(object: any): DeviceEvent;
    toJSON(message: DeviceEvent): unknown;
    create<I extends Exact<DeepPartial<DeviceEvent>, I>>(base?: I): DeviceEvent;
    fromPartial<I extends Exact<DeepPartial<DeviceEvent>, I>>(object: I): DeviceEvent;
};
export declare const ComponentInitializationEvent: {
    encode(message: ComponentInitializationEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ComponentInitializationEvent;
    fromJSON(object: any): ComponentInitializationEvent;
    toJSON(message: ComponentInitializationEvent): unknown;
    create<I extends Exact<DeepPartial<ComponentInitializationEvent>, I>>(base?: I): ComponentInitializationEvent;
    fromPartial<I extends Exact<DeepPartial<ComponentInitializationEvent>, I>>(object: I): ComponentInitializationEvent;
};
export declare const ComponentLifecycleSnapshot: {
    encode(message: ComponentLifecycleSnapshot, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ComponentLifecycleSnapshot;
    fromJSON(object: any): ComponentLifecycleSnapshot;
    toJSON(message: ComponentLifecycleSnapshot): unknown;
    create<I extends Exact<DeepPartial<ComponentLifecycleSnapshot>, I>>(base?: I): ComponentLifecycleSnapshot;
    fromPartial<I extends Exact<DeepPartial<ComponentLifecycleSnapshot>, I>>(object: I): ComponentLifecycleSnapshot;
};
export declare const ComponentLifecycleEvent: {
    encode(message: ComponentLifecycleEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ComponentLifecycleEvent;
    fromJSON(object: any): ComponentLifecycleEvent;
    toJSON(message: ComponentLifecycleEvent): unknown;
    create<I extends Exact<DeepPartial<ComponentLifecycleEvent>, I>>(base?: I): ComponentLifecycleEvent;
    fromPartial<I extends Exact<DeepPartial<ComponentLifecycleEvent>, I>>(object: I): ComponentLifecycleEvent;
};
export declare const SessionEvent: {
    encode(message: SessionEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): SessionEvent;
    fromJSON(object: any): SessionEvent;
    toJSON(message: SessionEvent): unknown;
    create<I extends Exact<DeepPartial<SessionEvent>, I>>(base?: I): SessionEvent;
    fromPartial<I extends Exact<DeepPartial<SessionEvent>, I>>(object: I): SessionEvent;
};
export declare const AuthEvent: {
    encode(message: AuthEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): AuthEvent;
    fromJSON(object: any): AuthEvent;
    toJSON(message: AuthEvent): unknown;
    create<I extends Exact<DeepPartial<AuthEvent>, I>>(base?: I): AuthEvent;
    fromPartial<I extends Exact<DeepPartial<AuthEvent>, I>>(object: I): AuthEvent;
};
export declare const ModelRegistryEvent: {
    encode(message: ModelRegistryEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelRegistryEvent;
    fromJSON(object: any): ModelRegistryEvent;
    toJSON(message: ModelRegistryEvent): unknown;
    create<I extends Exact<DeepPartial<ModelRegistryEvent>, I>>(base?: I): ModelRegistryEvent;
    fromPartial<I extends Exact<DeepPartial<ModelRegistryEvent>, I>>(object: I): ModelRegistryEvent;
};
export declare const DownloadEvent: {
    encode(message: DownloadEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DownloadEvent;
    fromJSON(object: any): DownloadEvent;
    toJSON(message: DownloadEvent): unknown;
    create<I extends Exact<DeepPartial<DownloadEvent>, I>>(base?: I): DownloadEvent;
    fromPartial<I extends Exact<DeepPartial<DownloadEvent>, I>>(object: I): DownloadEvent;
};
export declare const StorageLifecycleEvent: {
    encode(message: StorageLifecycleEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): StorageLifecycleEvent;
    fromJSON(object: any): StorageLifecycleEvent;
    toJSON(message: StorageLifecycleEvent): unknown;
    create<I extends Exact<DeepPartial<StorageLifecycleEvent>, I>>(base?: I): StorageLifecycleEvent;
    fromPartial<I extends Exact<DeepPartial<StorageLifecycleEvent>, I>>(object: I): StorageLifecycleEvent;
};
export declare const HardwareRoutingEvent: {
    encode(message: HardwareRoutingEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): HardwareRoutingEvent;
    fromJSON(object: any): HardwareRoutingEvent;
    toJSON(message: HardwareRoutingEvent): unknown;
    create<I extends Exact<DeepPartial<HardwareRoutingEvent>, I>>(base?: I): HardwareRoutingEvent;
    fromPartial<I extends Exact<DeepPartial<HardwareRoutingEvent>, I>>(object: I): HardwareRoutingEvent;
};
export declare const CapabilityOperationEvent: {
    encode(message: CapabilityOperationEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): CapabilityOperationEvent;
    fromJSON(object: any): CapabilityOperationEvent;
    toJSON(message: CapabilityOperationEvent): unknown;
    create<I extends Exact<DeepPartial<CapabilityOperationEvent>, I>>(base?: I): CapabilityOperationEvent;
    fromPartial<I extends Exact<DeepPartial<CapabilityOperationEvent>, I>>(object: I): CapabilityOperationEvent;
};
export declare const TelemetryEvent: {
    encode(message: TelemetryEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TelemetryEvent;
    fromJSON(object: any): TelemetryEvent;
    toJSON(message: TelemetryEvent): unknown;
    create<I extends Exact<DeepPartial<TelemetryEvent>, I>>(base?: I): TelemetryEvent;
    fromPartial<I extends Exact<DeepPartial<TelemetryEvent>, I>>(object: I): TelemetryEvent;
};
export declare const TelemetryEvent_AttributesEntry: {
    encode(message: TelemetryEvent_AttributesEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): TelemetryEvent_AttributesEntry;
    fromJSON(object: any): TelemetryEvent_AttributesEntry;
    toJSON(message: TelemetryEvent_AttributesEntry): unknown;
    create<I extends Exact<DeepPartial<TelemetryEvent_AttributesEntry>, I>>(base?: I): TelemetryEvent_AttributesEntry;
    fromPartial<I extends Exact<DeepPartial<TelemetryEvent_AttributesEntry>, I>>(object: I): TelemetryEvent_AttributesEntry;
};
export declare const CancellationEvent: {
    encode(message: CancellationEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): CancellationEvent;
    fromJSON(object: any): CancellationEvent;
    toJSON(message: CancellationEvent): unknown;
    create<I extends Exact<DeepPartial<CancellationEvent>, I>>(base?: I): CancellationEvent;
    fromPartial<I extends Exact<DeepPartial<CancellationEvent>, I>>(object: I): CancellationEvent;
};
export declare const FailureEvent: {
    encode(message: FailureEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): FailureEvent;
    fromJSON(object: any): FailureEvent;
    toJSON(message: FailureEvent): unknown;
    create<I extends Exact<DeepPartial<FailureEvent>, I>>(base?: I): FailureEvent;
    fromPartial<I extends Exact<DeepPartial<FailureEvent>, I>>(object: I): FailureEvent;
};
export declare const SDKEvent: {
    encode(message: SDKEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): SDKEvent;
    fromJSON(object: any): SDKEvent;
    toJSON(message: SDKEvent): unknown;
    create<I extends Exact<DeepPartial<SDKEvent>, I>>(base?: I): SDKEvent;
    fromPartial<I extends Exact<DeepPartial<SDKEvent>, I>>(object: I): SDKEvent;
};
export declare const SDKEvent_PropertiesEntry: {
    encode(message: SDKEvent_PropertiesEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): SDKEvent_PropertiesEntry;
    fromJSON(object: any): SDKEvent_PropertiesEntry;
    toJSON(message: SDKEvent_PropertiesEntry): unknown;
    create<I extends Exact<DeepPartial<SDKEvent_PropertiesEntry>, I>>(base?: I): SDKEvent_PropertiesEntry;
    fromPartial<I extends Exact<DeepPartial<SDKEvent_PropertiesEntry>, I>>(object: I): SDKEvent_PropertiesEntry;
};
type Builtin = Date | Function | Uint8Array | string | number | boolean | undefined;
export type DeepPartial<T> = T extends Builtin ? T : T extends globalThis.Array<infer U> ? globalThis.Array<DeepPartial<U>> : T extends ReadonlyArray<infer U> ? ReadonlyArray<DeepPartial<U>> : T extends {} ? {
    [K in keyof T]?: DeepPartial<T[K]>;
} : Partial<T>;
type KeysOfUnion<T> = T extends T ? keyof T : never;
export type Exact<P, I extends P> = P extends Builtin ? P : P & {
    [K in keyof P]: Exact<P[K], I[K]>;
} & {
    [K in Exclude<keyof I, KeysOfUnion<P>>]: never;
};
export {};
//# sourceMappingURL=sdk_events.d.ts.map