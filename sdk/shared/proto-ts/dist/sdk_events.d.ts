import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { ComponentLifecycleState, EventCategory } from "./component_types";
import { DownloadCancelResult, DownloadPlanResult, DownloadProgress, DownloadResumeResult, DownloadStartResult } from "./download_service";
import { ErrorSeverity, SDKError } from "./errors";
import { HardwareProfileResult } from "./hardware_profile";
import { CurrentModelResult, InferenceFramework, ModelCategory, ModelCompatibilityResult, ModelDeleteResult, ModelDiscoveryResult, ModelGetResult, ModelImportResult, ModelInfo, ModelListResult, ModelLoadResult, ModelRegistryRefreshResult, ModelUnloadResult } from "./model_types";
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
    SDK_COMPONENT_SEMANTIC_SEGMENTATION = 12,
    SDK_COMPONENT_RERANK = 13,
    UNRECOGNIZED = -1
}
export declare function sDKComponentFromJSON(object: any): SDKComponent;
export declare function sDKComponentToJSON(object: SDKComponent): string;
/**
 * ---------------------------------------------------------------------------
 * Where an event should be routed. Mirrors Swift `EventDestination` /
 * Kotlin `EventDestination` / Dart `EventDestination`.
 * Sources pre-IDL:
 *   Swift  SDKEvent.swift:15-22       — publicOnly / analyticsOnly / all
 *   Kotlin SDKEvent.kt:24-33          — PUBLIC_ONLY / ANALYTICS_ONLY / ALL
 *   Dart   sdk_event.dart:20-29       — all / publicOnly / analyticsOnly
 * ---------------------------------------------------------------------------
 * Bitmask routing destination. Values are powers of two so they can be OR'd
 * together; proto3 enums are open ints, so combinations round-trip on the wire
 * without named constants. The C++ destination router reads this as a bitmask.
 *   PUBLIC    — app-facing canonical SDKEvent proto stream
 *   TELEMETRY — telemetry_manager / server analytics
 *   LOG       — structured local log sink (opt-in)
 *   ALL       — PUBLIC | TELEMETRY (legacy "all" parity; the publish() default)
 */
export declare enum EventDestination {
    EVENT_DESTINATION_UNSPECIFIED = 0,
    EVENT_DESTINATION_PUBLIC = 1,
    EVENT_DESTINATION_TELEMETRY = 2,
    /** EVENT_DESTINATION_ALL - PUBLIC | TELEMETRY */
    EVENT_DESTINATION_ALL = 3,
    EVENT_DESTINATION_LOG = 4,
    UNRECOGNIZED = -1
}
export declare function eventDestinationFromJSON(object: any): EventDestination;
export declare function eventDestinationToJSON(object: EventDestination): string;
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
    /** VOICE_EVENT_KIND_VAD_PAUSED - VAD pause/resume (telemetry-only metrics). */
    VOICE_EVENT_KIND_VAD_PAUSED = 48,
    VOICE_EVENT_KIND_VAD_RESUMED = 49,
    UNRECOGNIZED = -1
}
export declare function voiceEventKindFromJSON(object: any): VoiceEventKind;
export declare function voiceEventKindToJSON(object: VoiceEventKind): string;
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
    MODEL_EVENT_KIND_EXTRACTION_STARTED = 22,
    MODEL_EVENT_KIND_EXTRACTION_PROGRESS = 23,
    MODEL_EVENT_KIND_EXTRACTION_COMPLETED = 24,
    MODEL_EVENT_KIND_EXTRACTION_FAILED = 25,
    UNRECOGNIZED = -1
}
export declare function modelEventKindFromJSON(object: any): ModelEventKind;
export declare function modelEventKindToJSON(object: ModelEventKind): string;
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
    MODEL_REGISTRY_EVENT_KIND_LIST_STARTED = 14,
    MODEL_REGISTRY_EVENT_KIND_LIST_COMPLETED = 15,
    MODEL_REGISTRY_EVENT_KIND_LIST_FAILED = 16,
    MODEL_REGISTRY_EVENT_KIND_GET_STARTED = 17,
    MODEL_REGISTRY_EVENT_KIND_GET_COMPLETED = 18,
    MODEL_REGISTRY_EVENT_KIND_GET_FAILED = 19,
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
    DOWNLOAD_EVENT_KIND_PAUSED = 12,
    DOWNLOAD_EVENT_KIND_PARTIAL_BYTES_DELETED = 13,
    UNRECOGNIZED = -1
}
export declare function downloadEventKindFromJSON(object: any): DownloadEventKind;
export declare function downloadEventKindToJSON(object: DownloadEventKind): string;
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
    STORAGE_LIFECYCLE_EVENT_KIND_AVAILABILITY_FAILED = 11,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_PLAN_FAILED = 12,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_DRY_RUN_COMPLETED = 13,
    UNRECOGNIZED = -1
}
export declare function storageLifecycleEventKindFromJSON(object: any): StorageLifecycleEventKind;
export declare function storageLifecycleEventKindToJSON(object: StorageLifecycleEventKind): string;
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
    category: ModelCategory;
    framework: InferenceFramework;
    resolvedPath: string;
    loadedAtUnixMs: number;
    model?: ModelInfo | undefined;
}
export interface ComponentLifecycleSnapshotRequest {
    component: SDKComponent;
    includeModel: boolean;
}
export interface ComponentLifecycleSnapshotResult {
    success: boolean;
    snapshots: ComponentLifecycleSnapshot[];
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
    snapshot?: ComponentLifecycleSnapshot | undefined;
    snapshotResult?: ComponentLifecycleSnapshotResult | undefined;
    storageDeletePlan?: StorageDeletePlan | undefined;
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
    /**
     * For COMPLETED — prompt-token count (mirrors RALLMGenerationResult.inputTokens).
     * Enables totalTokens = input_tokens + tokens_used analytics
     * from the event stream alone.
     */
    inputTokens: number;
    /**
     * Telemetry metrics carried on the canonical event stream so the C++
     * destination router can derive the full telemetry payload from the
     * proto SDKEvent alone (no parallel struct path). `framework` is the
     * InferenceFramework enum stored as int32 (matches FrameworkEvent.framework).
     */
    tokensPerSecond: number;
    /** completion TTFT (FIRST_TOKEN uses first_token_latency_ms) */
    timeToFirstTokenMs: number;
    isStreaming: boolean;
    temperature: number;
    maxTokens: number;
    contextLength: number;
    modelName: string;
    /** wall-clock generation duration */
    durationMs: number;
    /** InferenceFramework enum int */
    framework: number;
    /** prompt eval (prefill) duration */
    promptEvalTimeMs: number;
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
    /**
     * -----------------------------------------------------------------------
     * Telemetry metrics (STT transcription + TTS synthesis + model load) so
     * the C++ destination router derives the full telemetry payload from the
     * proto SDKEvent alone. Populated per-component (component on the SDKEvent
     * envelope selects which subset applies). `framework` is the
     * InferenceFramework enum stored as int32.
     * -----------------------------------------------------------------------
     */
    modelId: string;
    modelName: string;
    /** STT input audio length */
    audioLengthMs: number;
    audioSizeBytes: number;
    /** STT */
    wordCount: number;
    /** STT */
    realTimeFactor: number;
    /** STT */
    language: string;
    /** STT + TTS */
    sampleRate: number;
    /** STT */
    isStreaming: boolean;
    /** InferenceFramework enum int */
    framework: number;
    /** TTS synthesis metrics. */
    characterCount: number;
    /** distinct from duration_ms(7); telemetry output_duration_ms */
    audioDurationMs: number;
    audioSizeBytesTts: number;
    /** telemetry processing_time_ms */
    processingDurationMs: number;
    charactersPerSecond: number;
}
/**
 * ===========================================================================
 * SECTION 6 — EMBEDDINGS / SECTION 7 — DIFFUSION / SECTION 8 — RAG /
 * SECTION 9 — LORA / SECTION 2b — VLM (capability operations)
 * ===========================================================================
 * Embeddings, Diffusion, RAG, LoRA, and VLM capability-operation lifecycle is
 * consolidated into a single `CapabilityOperationEvent` message discriminated
 * by `CapabilityOperationEventKind` (VLM_* / DIFFUSION_* / EMBEDDINGS_* /
 * RAG_* / LORA_*). One flat struct keeps these analytics-only operation events
 * uniform across the five capability components.
 * ---------------------------------------------------------------------------
 */
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
    /**
     * Model-load + download/extraction telemetry metrics so the C++
     * destination router derives the telemetry payload from the proto
     * SDKEvent alone. `framework` is the InferenceFramework enum stored as
     * int32 (matches FrameworkEvent.framework).
     */
    modelName: string;
    modelSizeBytes: number;
    /** load / download / extraction duration */
    durationMs: number;
    /** InferenceFramework enum int */
    framework: number;
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
    /** For CLEAR_CACHE_COMPLETED / CLEAN_TEMP_COMPLETED — bytes reclaimed. */
    freedBytes: number;
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
export interface AuthEvent {
    kind: AuthEventKind;
    provider: string;
    subjectId: string;
    scope: string;
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
    severity: ErrorSeverity;
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
    /**
     * Logical operation identifier for this event, e.g. "download.start",
     * "model.load", or "llm.generate". This is separate from the event UUID
     * so retry/cancel/progress/failure events can share one operation id.
     */
    operationId: string;
    /**
     * Cross-service correlation key supplied by the SDK/app or generated by
     * the portable layer. Native/Web adapters may propagate it through HTTP
     * headers or OS task metadata, but C++ owns the canonical event field.
     */
    correlationId: string;
    /**
     * Source that emitted the event: "cpp", "swift", "kotlin", "flutter",
     * "react_native", "web", or a backend/plugin key. This disambiguates
     * platform adapter facts from portable orchestration events.
     */
    source: string;
    /**
     * Optional tracing identifier for diagnostics. Empty when tracing is not
     * enabled; do not use it as a business key.
     */
    traceId: string;
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
/**
 * Subscription-side filter for the canonical SDKEvent stream. Empty fields are
 * wildcards; implementations match populated fields against the envelope fields
 * above without interpreting payload-specific data.
 */
export interface SDKEventFilter {
    categories: EventCategory[];
    components: SDKComponent[];
    destinations: EventDestination[];
    minimumSeverity: ErrorSeverity;
    sessionId: string;
    operationId: string;
    correlationId: string;
    source: string;
    traceId: string;
}
export interface SDKEventPublishRequest {
    event?: SDKEvent | undefined;
    /**
     * When true, the portable event layer fills missing envelope metadata such
     * as id, timestamp, destination, category/component defaults, source, and
     * correlation fields before routing the event.
     */
    normalizeEnvelope: boolean;
}
export interface SDKEventPublishResult {
    accepted: boolean;
    eventId: string;
    /**
     * The event as accepted by the portable layer after optional envelope
     * normalization. This is the same typed payload that serialized-proto
     * bridges publish to subscribers.
     */
    normalizedEvent?: SDKEvent | undefined;
    errorMessage: string;
    error?: SDKError | undefined;
}
export interface SDKEventSubscribeRequest {
    filter?: SDKEventFilter | undefined;
    /**
     * Replays queued events before following live events when the backing
     * bridge has a poll queue. Implementations without retention may ignore it
     * and continue with live events only.
     */
    replayQueuedEvents: boolean;
}
export declare const InitializationEvent: MessageFns<InitializationEvent>;
export declare const ConfigurationEvent: MessageFns<ConfigurationEvent>;
export declare const ComponentInitializationEvent: MessageFns<ComponentInitializationEvent>;
export declare const ComponentLifecycleSnapshot: MessageFns<ComponentLifecycleSnapshot>;
export declare const ComponentLifecycleSnapshotRequest: MessageFns<ComponentLifecycleSnapshotRequest>;
export declare const ComponentLifecycleSnapshotResult: MessageFns<ComponentLifecycleSnapshotResult>;
export declare const ComponentLifecycleEvent: MessageFns<ComponentLifecycleEvent>;
export declare const SessionEvent: MessageFns<SessionEvent>;
export declare const GenerationEvent: MessageFns<GenerationEvent>;
export declare const VoiceLifecycleEvent: MessageFns<VoiceLifecycleEvent>;
export declare const CapabilityOperationEvent: MessageFns<CapabilityOperationEvent>;
export declare const ModelEvent: MessageFns<ModelEvent>;
export declare const ModelRegistryEvent: MessageFns<ModelRegistryEvent>;
export declare const DownloadEvent: MessageFns<DownloadEvent>;
export declare const StorageEvent: MessageFns<StorageEvent>;
export declare const StorageLifecycleEvent: MessageFns<StorageLifecycleEvent>;
export declare const AuthEvent: MessageFns<AuthEvent>;
export declare const DeviceEvent: MessageFns<DeviceEvent>;
export declare const NetworkEvent: MessageFns<NetworkEvent>;
export declare const FrameworkEvent: MessageFns<FrameworkEvent>;
export declare const HardwareRoutingEvent: MessageFns<HardwareRoutingEvent>;
export declare const PerformanceEvent: MessageFns<PerformanceEvent>;
export declare const TelemetryEvent: MessageFns<TelemetryEvent>;
export declare const TelemetryEvent_AttributesEntry: MessageFns<TelemetryEvent_AttributesEntry>;
export declare const CancellationEvent: MessageFns<CancellationEvent>;
export declare const FailureEvent: MessageFns<FailureEvent>;
export declare const SDKEvent: MessageFns<SDKEvent>;
export declare const SDKEvent_PropertiesEntry: MessageFns<SDKEvent_PropertiesEntry>;
export declare const SDKEventFilter: MessageFns<SDKEventFilter>;
export declare const SDKEventPublishRequest: MessageFns<SDKEventPublishRequest>;
export declare const SDKEventPublishResult: MessageFns<SDKEventPublishResult>;
export declare const SDKEventSubscribeRequest: MessageFns<SDKEventSubscribeRequest>;
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
export interface MessageFns<T> {
    encode(message: T, writer?: BinaryWriter): BinaryWriter;
    decode(input: BinaryReader | Uint8Array, length?: number): T;
    fromJSON(object: any): T;
    toJSON(message: T): unknown;
    create<I extends Exact<DeepPartial<T>, I>>(base?: I): T;
    fromPartial<I extends Exact<DeepPartial<T>, I>>(object: I): T;
}
export {};
