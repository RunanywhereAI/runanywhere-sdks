import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { ComponentLifecycleState, EventCategory } from "./component_types";
import { DownloadCancelResult, DownloadPlanResult, DownloadProgress, DownloadStartResult } from "./download_service";
import { ErrorSeverity, SDKError } from "./errors";
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
 * The rac_wire_string values are the stable lowercase keys that SDKError.component
 * carries; producers stringify through them, never through the constant name.
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
    /** CONFIGURATION_EVENT_KIND_CHANGED - generic config_changed (Kotlin/Dart) */
    CONFIGURATION_EVENT_KIND_CHANGED = 18,
    UNRECOGNIZED = -1
}
export declare function configurationEventKindFromJSON(object: any): ConfigurationEventKind;
export declare function configurationEventKindToJSON(object: ConfigurationEventKind): string;
export declare enum ComponentLifecycleEventKind {
    COMPONENT_LIFECYCLE_EVENT_KIND_UNSPECIFIED = 0,
    /** COMPONENT_LIFECYCLE_EVENT_KIND_STATE_CHANGED - previous_state -> current_state carries this */
    COMPONENT_LIFECYCLE_EVENT_KIND_STATE_CHANGED = 1,
    COMPONENT_LIFECYCLE_EVENT_KIND_MODEL_LOAD_COMPLETED = 2,
    COMPONENT_LIFECYCLE_EVENT_KIND_MODEL_UNLOAD_COMPLETED = 3,
    COMPONENT_LIFECYCLE_EVENT_KIND_MODEL_DELETE_COMPLETED = 4,
    COMPONENT_LIFECYCLE_EVENT_KIND_DOWNLOAD_PROGRESS = 5,
    COMPONENT_LIFECYCLE_EVENT_KIND_STORAGE_AVAILABILITY = 6,
    COMPONENT_LIFECYCLE_EVENT_KIND_STORAGE_DELETE_COMPLETED = 7,
    COMPONENT_LIFECYCLE_EVENT_KIND_SNAPSHOT = 8,
    COMPONENT_LIFECYCLE_EVENT_KIND_SNAPSHOT_RESULT = 9,
    COMPONENT_LIFECYCLE_EVENT_KIND_STORAGE_DELETE_PLAN = 10,
    /** COMPONENT_LIFECYCLE_EVENT_KIND_INITIALIZATION_STARTED - Absorbed from ComponentInitializationEventKind. */
    COMPONENT_LIFECYCLE_EVENT_KIND_INITIALIZATION_STARTED = 11,
    COMPONENT_LIFECYCLE_EVENT_KIND_INITIALIZATION_COMPLETED = 12,
    COMPONENT_LIFECYCLE_EVENT_KIND_COMPONENT_CHECKING = 13,
    COMPONENT_LIFECYCLE_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED = 14,
    COMPONENT_LIFECYCLE_EVENT_KIND_COMPONENT_INITIALIZING = 17,
    COMPONENT_LIFECYCLE_EVENT_KIND_COMPONENT_READY = 18,
    COMPONENT_LIFECYCLE_EVENT_KIND_COMPONENT_FAILED = 19,
    COMPONENT_LIFECYCLE_EVENT_KIND_PARALLEL_INIT_STARTED = 20,
    COMPONENT_LIFECYCLE_EVENT_KIND_SEQUENTIAL_INIT_STARTED = 21,
    COMPONENT_LIFECYCLE_EVENT_KIND_ALL_COMPONENTS_READY = 22,
    COMPONENT_LIFECYCLE_EVENT_KIND_SOME_COMPONENTS_READY = 23,
    UNRECOGNIZED = -1
}
export declare function componentLifecycleEventKindFromJSON(object: any): ComponentLifecycleEventKind;
export declare function componentLifecycleEventKindToJSON(object: ComponentLifecycleEventKind): string;
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
    GENERATION_EVENT_KIND_STARTED = 3,
    GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED = 4,
    GENERATION_EVENT_KIND_TOKEN_GENERATED = 5,
    GENERATION_EVENT_KIND_STREAMING_UPDATE = 6,
    /** GENERATION_EVENT_KIND_COMPLETED - Exactly one success terminal, one failure terminal, one cancel terminal. */
    GENERATION_EVENT_KIND_COMPLETED = 7,
    GENERATION_EVENT_KIND_FAILED = 8,
    GENERATION_EVENT_KIND_ROUTING_DECISION = 12,
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
    /** MODEL_EVENT_KIND_REGISTRY_REFRESH_STARTED - Absorbed from ModelRegistryEventKind. */
    MODEL_EVENT_KIND_REGISTRY_REFRESH_STARTED = 26,
    MODEL_EVENT_KIND_REGISTRY_REFRESH_COMPLETED = 27,
    MODEL_EVENT_KIND_REGISTRY_REFRESH_FAILED = 28,
    MODEL_EVENT_KIND_ASSIGNMENT_STARTED = 29,
    MODEL_EVENT_KIND_ASSIGNMENT_COMPLETED = 30,
    MODEL_EVENT_KIND_ASSIGNMENT_FAILED = 31,
    MODEL_EVENT_KIND_IMPORT_STARTED = 32,
    MODEL_EVENT_KIND_IMPORT_COMPLETED = 33,
    MODEL_EVENT_KIND_IMPORT_FAILED = 34,
    MODEL_EVENT_KIND_DISCOVERY_STARTED = 35,
    MODEL_EVENT_KIND_DISCOVERY_COMPLETED = 36,
    MODEL_EVENT_KIND_DISCOVERY_FAILED = 37,
    MODEL_EVENT_KIND_CURRENT_MODEL_CHANGED = 38,
    MODEL_EVENT_KIND_REGISTRY_GET_COMPLETED = 40,
    MODEL_EVENT_KIND_REGISTRY_GET_FAILED = 41,
    MODEL_EVENT_KIND_REGISTRY_LIST_COMPLETED = 43,
    MODEL_EVENT_KIND_REGISTRY_LIST_FAILED = 44,
    /** MODEL_EVENT_KIND_DOWNLOAD_PLAN_STARTED - Absorbed from DownloadEventKind. */
    MODEL_EVENT_KIND_DOWNLOAD_PLAN_STARTED = 45,
    MODEL_EVENT_KIND_DOWNLOAD_PLAN_COMPLETED = 46,
    MODEL_EVENT_KIND_DOWNLOAD_PLAN_FAILED = 47,
    MODEL_EVENT_KIND_DOWNLOAD_CANCEL_REQUESTED = 48,
    MODEL_EVENT_KIND_DOWNLOAD_RESUME_REQUESTED = 49,
    MODEL_EVENT_KIND_DOWNLOAD_RESUMED = 50,
    MODEL_EVENT_KIND_DOWNLOAD_PAUSED = 51,
    MODEL_EVENT_KIND_DOWNLOAD_PARTIAL_BYTES_DELETED = 52,
    UNRECOGNIZED = -1
}
export declare function modelEventKindFromJSON(object: any): ModelEventKind;
export declare function modelEventKindToJSON(object: ModelEventKind): string;
export declare enum StorageEventKind {
    STORAGE_EVENT_KIND_UNSPECIFIED = 0,
    STORAGE_EVENT_KIND_INFO_RETRIEVED = 2,
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
    /** STORAGE_EVENT_KIND_AVAILABILITY_CHECKED - Absorbed from StorageLifecycleEventKind. */
    STORAGE_EVENT_KIND_AVAILABILITY_CHECKED = 18,
    STORAGE_EVENT_KIND_AVAILABILITY_FAILED = 19,
    STORAGE_EVENT_KIND_DELETE_PLAN_CREATED = 20,
    STORAGE_EVENT_KIND_DELETE_PLAN_FAILED = 21,
    STORAGE_EVENT_KIND_DELETE_DRY_RUN_COMPLETED = 22,
    STORAGE_EVENT_KIND_CACHE_CLEANUP_STARTED = 23,
    STORAGE_EVENT_KIND_CACHE_CLEANUP_COMPLETED = 24,
    STORAGE_EVENT_KIND_CACHE_CLEANUP_FAILED = 25,
    UNRECOGNIZED = -1
}
export declare function storageEventKindFromJSON(object: any): StorageEventKind;
export declare function storageEventKindToJSON(object: StorageEventKind): string;
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
/** Snapshot of a component's current model-backed lifecycle state. */
export interface ComponentLifecycleSnapshot {
    component: SDKComponent;
    state: ComponentLifecycleState;
    modelId: string;
    updatedAtMs: number;
    category: ModelCategory;
    framework: InferenceFramework;
    resolvedPath: string;
    loadedAtUnixMs: number;
    model?: ModelInfo | undefined;
    error?: SDKError | undefined;
}
export interface ComponentLifecycleSnapshotResult {
    snapshots: ComponentLifecycleSnapshot[];
    error?: SDKError | undefined;
}
/**
 * Operation-aware lifecycle event. The oneof arms intentionally reference the
 * operation result/progress protos from this contract slice instead of adding
 * another broad event taxonomy. Covers both component bring-up (absorbed from
 * ComponentInitializationEvent) and steady-state model lifecycle.
 */
export interface ComponentLifecycleEvent {
    kind: ComponentLifecycleEventKind;
    component: SDKComponent;
    previousState: ComponentLifecycleState;
    currentState: ComponentLifecycleState;
    modelId: string;
    timestampMs: number;
    /** Absorbed from ComponentInitializationEvent. */
    sizeBytes: number;
    /** COMPONENT_DOWNLOAD_PROGRESS */
    progress: number;
    /** multi-component events */
    components: SDKComponent[];
    readyComponents: SDKComponent[];
    pendingComponents: SDKComponent[];
    /** INITIALIZATION_COMPLETED summary */
    readyCount: number;
    failedCount: number;
    error?: SDKError | undefined;
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
    /** For STREAMING_UPDATE — the running response text. */
    streamingText: string;
    /** Output tokens so far on STREAMING_UPDATE; the final count on COMPLETED. */
    outputTokens: number;
    /** For COMPLETED — full response. */
    response: string;
    /** For FAILED. */
    error: string;
    /** For MODEL_LOADED / MODEL_UNLOADED — bound model. */
    modelId: string;
    /** For COST_CALCULATED — Dart SDKGenerationCostCalculated. */
    costAmount: number;
    costSavedAmount: number;
    /** For ROUTING_DECISION. */
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
    /** Prompt-token count on COMPLETED. Total = input_tokens + output_tokens. */
    inputTokens: number;
    /**
     * Telemetry metrics carried on the canonical event stream so the C++
     * destination router can derive the full telemetry payload from the
     * proto SDKEvent alone (no parallel struct path).
     */
    tokensPerSecond: number;
    /** Time to first token, whichever kind reports it. */
    timeToFirstTokenMs: number;
    isStreaming: boolean;
    temperature: number;
    maxTokens: number;
    contextLength: number;
    modelName: string;
    /** Whole-generation wall clock. */
    totalDurationMs: number;
    framework: InferenceFramework;
    /** Prefill (prompt eval) wall clock. */
    prefillDurationMs: number;
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
    /** For *_ERROR / *_FAILED. */
    error: string;
    /**
     * -----------------------------------------------------------------------
     * Telemetry metrics (STT transcription + TTS synthesis + model load) so
     * the C++ destination router derives the full telemetry payload from the
     * proto SDKEvent alone. Populated per-component (component on the SDKEvent
     * envelope selects which subset applies).
     * -----------------------------------------------------------------------
     */
    modelId: string;
    modelName: string;
    /** STT input audio */
    inputAudioDurationMs: number;
    inputAudioBytes: number;
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
    framework: InferenceFramework;
    /** TTS synthesis metrics. */
    characterCount: number;
    /** TTS output audio */
    outputAudioDurationMs: number;
    outputAudioBytes: number;
    /** telemetry processing_time_ms */
    processingDurationMs: number;
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
     * SDKEvent alone.
     */
    modelName: string;
    modelSizeBytes: number;
    /** load / download / extraction duration */
    durationMs: number;
    framework: InferenceFramework;
    /** Absorbed from ModelRegistryEvent: registry-specific identity + results. */
    assignmentId: string;
    assignedComponent: SDKComponent;
    sourcePath: string;
    refreshResult?: ModelRegistryRefreshResult | undefined;
    listResult?: ModelListResult | undefined;
    getResult?: ModelGetResult | undefined;
    importResult?: ModelImportResult | undefined;
    discoveryResult?: ModelDiscoveryResult | undefined;
    compatibilityResult?: ModelCompatibilityResult | undefined;
    currentModelResult?: CurrentModelResult | undefined;
    planResult?: DownloadPlanResult | undefined;
    startResult?: DownloadStartResult | undefined;
    downloadProgress?: DownloadProgress | undefined;
    cancelResult?: DownloadCancelResult | undefined;
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
    /** Absorbed from StorageLifecycleEvent. */
    bytes: number;
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
    /** For ADAPTER_REGISTERED / *_RETRIEVED — bound framework. */
    framework: InferenceFramework;
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
}
/**
 * PerformanceEvent was deleted (had zero producers and zero readers, per
 * review): a memory/thermal/latency/throughput reading is a named number with
 * a unit, which TelemetryEvent already models. `name` carries what
 * PerformanceEventKind used to (e.g. "memory_warning", "thermal_state"),
 * `value` + `unit` carry the number (bytes / celsius-state / ms /
 * tokens_per_second), and `attributes` carries operation/thermal_state text.
 */
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
     * Source that emitted the event: "cpp", "swift", "kotlin", "flutter",
     * "react_native", "web", or a backend/plugin key. This disambiguates
     * platform adapter facts from portable orchestration events.
     */
    source: string;
    /**
     * Monotonic, whole-stream ordering key, stamped by a single choke point in
     * commons at emission time. Detects drops and reordering; the only
     * correlation primitive a consumer needs beyond id / session_id /
     * operation_id above. (correlation_id and trace_id were deleted: neither
     * had a writer or a reader anywhere in the tree.)
     */
    seq: number;
    initialization?: InitializationEvent | undefined;
    configuration?: ConfigurationEvent | undefined;
    generation?: GenerationEvent | undefined;
    /** + model_registry, + download */
    model?: ModelEvent | undefined;
    network?: NetworkEvent | undefined;
    /** + storage_lifecycle */
    storage?: StorageEvent | undefined;
    framework?: FrameworkEvent | undefined;
    device?: DeviceEvent | undefined;
    voice?: VoiceLifecycleEvent | undefined;
    /** from voice_events.proto */
    voicePipeline?: VoiceEvent | undefined;
    /** + component_init */
    componentLifecycle?: ComponentLifecycleEvent | undefined;
    session?: SessionEvent | undefined;
    auth?: AuthEvent | undefined;
    hardwareRouting?: HardwareRoutingEvent | undefined;
    capability?: CapabilityOperationEvent | undefined;
    /** + performance */
    telemetry?: TelemetryEvent | undefined;
    cancellation?: CancellationEvent | undefined;
}
export interface SDKEvent_PropertiesEntry {
    key: string;
    value: string;
}
export declare const InitializationEvent: MessageFns<InitializationEvent>;
export declare const ConfigurationEvent: MessageFns<ConfigurationEvent>;
export declare const ComponentLifecycleSnapshot: MessageFns<ComponentLifecycleSnapshot>;
export declare const ComponentLifecycleSnapshotResult: MessageFns<ComponentLifecycleSnapshotResult>;
export declare const ComponentLifecycleEvent: MessageFns<ComponentLifecycleEvent>;
export declare const SessionEvent: MessageFns<SessionEvent>;
export declare const GenerationEvent: MessageFns<GenerationEvent>;
export declare const VoiceLifecycleEvent: MessageFns<VoiceLifecycleEvent>;
export declare const CapabilityOperationEvent: MessageFns<CapabilityOperationEvent>;
export declare const ModelEvent: MessageFns<ModelEvent>;
export declare const StorageEvent: MessageFns<StorageEvent>;
export declare const AuthEvent: MessageFns<AuthEvent>;
export declare const DeviceEvent: MessageFns<DeviceEvent>;
export declare const NetworkEvent: MessageFns<NetworkEvent>;
export declare const FrameworkEvent: MessageFns<FrameworkEvent>;
export declare const HardwareRoutingEvent: MessageFns<HardwareRoutingEvent>;
export declare const TelemetryEvent: MessageFns<TelemetryEvent>;
export declare const TelemetryEvent_AttributesEntry: MessageFns<TelemetryEvent_AttributesEntry>;
export declare const CancellationEvent: MessageFns<CancellationEvent>;
export declare const SDKEvent: MessageFns<SDKEvent>;
export declare const SDKEvent_PropertiesEntry: MessageFns<SDKEvent_PropertiesEntry>;
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
