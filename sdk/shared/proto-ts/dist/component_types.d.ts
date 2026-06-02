export declare const protobufPackage = "runanywhere.v1";
/**
 * Component runtime lifecycle state for model-backed SDK components. Platform
 * adapters own native component handles; this enum carries the C++ lifecycle
 * state every SDK can expose uniformly. Previously lived in sdk_events.proto
 * (also used by voice_events.proto's VoiceAgentComponentStates after the
 * former hand-rolled `ComponentLoadState` was consolidated into this single
 * richer taxonomy).
 */
export declare enum ComponentLifecycleState {
    COMPONENT_LIFECYCLE_STATE_UNSPECIFIED = 0,
    COMPONENT_LIFECYCLE_STATE_NOT_LOADED = 1,
    COMPONENT_LIFECYCLE_STATE_LOADING = 2,
    COMPONENT_LIFECYCLE_STATE_READY = 3,
    COMPONENT_LIFECYCLE_STATE_UNLOADING = 4,
    COMPONENT_LIFECYCLE_STATE_ERROR = 5,
    COMPONENT_LIFECYCLE_STATE_SHUTDOWN = 6,
    COMPONENT_LIFECYCLE_STATE_DOWNLOADING = 7,
    COMPONENT_LIFECYCLE_STATE_DELETING = 8,
    COMPONENT_LIFECYCLE_STATE_PAUSED = 9,
    COMPONENT_LIFECYCLE_STATE_UPDATING = 10,
    UNRECOGNIZED = -1
}
export declare function componentLifecycleStateFromJSON(object: any): ComponentLifecycleState;
export declare function componentLifecycleStateToJSON(object: ComponentLifecycleState): string;
/**
 * Canonical event category carried by every SDKEvent envelope. Lives here
 * (instead of sdk_events.proto) so voice_events.proto and voice_agent_service
 * .proto can reference it without importing sdk_events.proto (which itself
 * imports voice_events.proto — cycle resolution).
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
    /**
     * EVENT_CATEGORY_AUDIO - Absorbed from former VoiceEventCategory (voice_events.proto).
     * AUDIO and METRICS had no EventCategory counterpart; WAKEWORD was
     * previously only on the voice-pipeline side.
     */
    EVENT_CATEGORY_AUDIO = 36,
    EVENT_CATEGORY_METRICS = 37,
    EVENT_CATEGORY_WAKEWORD = 38,
    UNRECOGNIZED = -1
}
export declare function eventCategoryFromJSON(object: any): EventCategory;
export declare function eventCategoryToJSON(object: EventCategory): string;
