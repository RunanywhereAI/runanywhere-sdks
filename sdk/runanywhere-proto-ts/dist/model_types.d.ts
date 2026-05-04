import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Audio format — union of all cases currently defined across SDKs.
 * Sources pre-IDL:
 *   Kotlin  AudioTypes.kt:12          (pcm, wav, mp3, opus, aac, flac, ogg, pcm_16bit)
 *   Kotlin  ComponentTypes.kt:39      (pcm, wav, mp3, aac, ogg, opus, flac)  ← duplicate
 *   Swift   AudioTypes.swift:17       (pcm, wav, mp3, opus, aac, flac)
 *   Dart    audio_format.dart:3       (wav, mp3, m4a, flac, pcm, opus)
 *   RN      TTSTypes.ts:36            ('pcm' | 'wav' | 'mp3')
 * ---------------------------------------------------------------------------
 */
export declare enum AudioFormat {
    AUDIO_FORMAT_UNSPECIFIED = 0,
    AUDIO_FORMAT_PCM = 1,
    AUDIO_FORMAT_WAV = 2,
    AUDIO_FORMAT_MP3 = 3,
    AUDIO_FORMAT_OPUS = 4,
    AUDIO_FORMAT_AAC = 5,
    AUDIO_FORMAT_FLAC = 6,
    AUDIO_FORMAT_OGG = 7,
    /** AUDIO_FORMAT_M4A - iOS / Dart, container of AAC */
    AUDIO_FORMAT_M4A = 8,
    /** AUDIO_FORMAT_PCM_S16LE - Android "pcm_16bit" — signed 16-bit LE PCM */
    AUDIO_FORMAT_PCM_S16LE = 9,
    UNRECOGNIZED = -1
}
export declare function audioFormatFromJSON(object: any): AudioFormat;
export declare function audioFormatToJSON(object: AudioFormat): string;
/**
 * ---------------------------------------------------------------------------
 * Model file format — union across all SDKs.
 * Sources pre-IDL:
 *   Swift  ModelTypes.swift:27        (onnx, ort, gguf, bin, coreml, unknown)
 *   Kotlin ModelTypes.kt:41           (ONNX, ORT, GGUF, BIN, QNN_CONTEXT, UNKNOWN)
 *   Dart   model_types.dart:34        (onnx, ort, gguf, bin, unknown)
 *   RN     enums.ts:115               (12-case superset incl. MLModel, MLPackage, TFLite,
 *                                       SafeTensors, Zip, Folder, Proprietary)
 *   Web    enums.ts:56                (copy of RN)
 * ---------------------------------------------------------------------------
 */
export declare enum ModelFormat {
    MODEL_FORMAT_UNSPECIFIED = 0,
    MODEL_FORMAT_GGUF = 1,
    MODEL_FORMAT_GGML = 2,
    MODEL_FORMAT_ONNX = 3,
    MODEL_FORMAT_ORT = 4,
    MODEL_FORMAT_BIN = 5,
    /** MODEL_FORMAT_COREML - Apple platforms only */
    MODEL_FORMAT_COREML = 6,
    /** MODEL_FORMAT_MLMODEL - Apple platforms only */
    MODEL_FORMAT_MLMODEL = 7,
    /** MODEL_FORMAT_MLPACKAGE - Apple platforms only */
    MODEL_FORMAT_MLPACKAGE = 8,
    MODEL_FORMAT_TFLITE = 9,
    MODEL_FORMAT_SAFETENSORS = 10,
    /** MODEL_FORMAT_QNN_CONTEXT - Qualcomm Genie */
    MODEL_FORMAT_QNN_CONTEXT = 11,
    /** MODEL_FORMAT_ZIP - Archive wrapping one of the above */
    MODEL_FORMAT_ZIP = 12,
    MODEL_FORMAT_FOLDER = 13,
    /** MODEL_FORMAT_PROPRIETARY - Built-in system models */
    MODEL_FORMAT_PROPRIETARY = 14,
    MODEL_FORMAT_UNKNOWN = 15,
    UNRECOGNIZED = -1
}
export declare function modelFormatFromJSON(object: any): ModelFormat;
export declare function modelFormatToJSON(object: ModelFormat): string;
/**
 * ---------------------------------------------------------------------------
 * Inference framework / runtime. Same name used across all SDKs (RN names it
 * LLMFramework; we canonicalize on InferenceFramework).
 * Sources pre-IDL:
 *   Swift  ModelTypes.swift:76        (12 cases incl. coreml, mlx, whisperKitCoreML,
 *                                       metalrt)
 *   Kotlin ComponentTypes.kt:122      (9 cases incl. GENIE; no coreml / mlx / whisperKit /
 *                                       metalrt)
 *   Dart   model_types.dart:106       (9 cases, matches Kotlin)
 *   RN     enums.ts:30 (LLMFramework) (16 cases)
 *   Web    enums.ts:21 (LLMFramework) (16 cases, copy of RN)
 * ---------------------------------------------------------------------------
 */
export declare enum InferenceFramework {
    INFERENCE_FRAMEWORK_UNSPECIFIED = 0,
    INFERENCE_FRAMEWORK_ONNX = 1,
    INFERENCE_FRAMEWORK_LLAMA_CPP = 2,
    /** INFERENCE_FRAMEWORK_FOUNDATION_MODELS - Apple on-device LLM */
    INFERENCE_FRAMEWORK_FOUNDATION_MODELS = 3,
    INFERENCE_FRAMEWORK_SYSTEM_TTS = 4,
    INFERENCE_FRAMEWORK_FLUID_AUDIO = 5,
    /** INFERENCE_FRAMEWORK_COREML - Apple */
    INFERENCE_FRAMEWORK_COREML = 6,
    /** INFERENCE_FRAMEWORK_MLX - Apple Silicon */
    INFERENCE_FRAMEWORK_MLX = 7,
    /** INFERENCE_FRAMEWORK_WHISPERKIT_COREML - Apple */
    INFERENCE_FRAMEWORK_WHISPERKIT_COREML = 8,
    /** INFERENCE_FRAMEWORK_METALRT - Apple */
    INFERENCE_FRAMEWORK_METALRT = 9,
    /** INFERENCE_FRAMEWORK_GENIE - Qualcomm */
    INFERENCE_FRAMEWORK_GENIE = 10,
    INFERENCE_FRAMEWORK_TFLITE = 11,
    INFERENCE_FRAMEWORK_EXECUTORCH = 12,
    INFERENCE_FRAMEWORK_MEDIAPIPE = 13,
    INFERENCE_FRAMEWORK_MLC = 14,
    INFERENCE_FRAMEWORK_PICO_LLM = 15,
    INFERENCE_FRAMEWORK_PIPER_TTS = 16,
    INFERENCE_FRAMEWORK_WHISPERKIT = 17,
    INFERENCE_FRAMEWORK_OPENAI_WHISPER = 18,
    INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS = 19,
    /** INFERENCE_FRAMEWORK_BUILT_IN - rule-based, no model */
    INFERENCE_FRAMEWORK_BUILT_IN = 20,
    INFERENCE_FRAMEWORK_NONE = 21,
    INFERENCE_FRAMEWORK_UNKNOWN = 22,
    /** INFERENCE_FRAMEWORK_SHERPA - Sherpa-ONNX speech engine (STT/TTS/VAD/wakeword) */
    INFERENCE_FRAMEWORK_SHERPA = 23,
    UNRECOGNIZED = -1
}
export declare function inferenceFrameworkFromJSON(object: any): InferenceFramework;
export declare function inferenceFrameworkToJSON(object: InferenceFramework): string;
/**
 * ---------------------------------------------------------------------------
 * Model category / modality class. Sources pre-IDL:
 *   Swift ModelTypes.swift:39         (9 cases incl. voiceActivityDetection + audio)
 *   Kotlin ModelTypes.kt:147          (8 cases, no VAD)
 *   Dart  model_types.dart:55         (8 cases, no VAD)
 *   RN    enums.ts:75                 (8 cases, no VAD, Audio labeled as VAD)
 *   Web   enums.ts:39                 (7 cases, Audio labeled as VAD)
 * ---------------------------------------------------------------------------
 */
export declare enum ModelCategory {
    MODEL_CATEGORY_UNSPECIFIED = 0,
    MODEL_CATEGORY_LANGUAGE = 1,
    MODEL_CATEGORY_SPEECH_RECOGNITION = 2,
    MODEL_CATEGORY_SPEECH_SYNTHESIS = 3,
    MODEL_CATEGORY_VISION = 4,
    MODEL_CATEGORY_IMAGE_GENERATION = 5,
    MODEL_CATEGORY_MULTIMODAL = 6,
    MODEL_CATEGORY_AUDIO = 7,
    MODEL_CATEGORY_EMBEDDING = 8,
    /** MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION - present in Swift only pre-IDL */
    MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION = 9,
    UNRECOGNIZED = -1
}
export declare function modelCategoryFromJSON(object: any): ModelCategory;
export declare function modelCategoryToJSON(object: ModelCategory): string;
/**
 * ---------------------------------------------------------------------------
 * SDK environment. Sources pre-IDL:
 *   Swift  SDKEnvironment.swift:5     (development, staging, production)
 *   Kotlin RunAnywhere.kt:47          (DEVELOPMENT, STAGING, PRODUCTION, cEnvironment)
 *   Kotlin SDKLogger.kt:159           (DEVELOPMENT, STAGING, PRODUCTION) ← duplicate
 *   Dart   sdk_environment.dart:5     (development, staging, production)
 *   RN     enums.ts:11                (Development, Staging, Production)
 *   Web    enums.ts:9                 (Development, Staging, Production)
 * ---------------------------------------------------------------------------
 */
export declare enum SDKEnvironment {
    SDK_ENVIRONMENT_UNSPECIFIED = 0,
    SDK_ENVIRONMENT_DEVELOPMENT = 1,
    SDK_ENVIRONMENT_STAGING = 2,
    SDK_ENVIRONMENT_PRODUCTION = 3,
    UNRECOGNIZED = -1
}
export declare function sDKEnvironmentFromJSON(object: any): SDKEnvironment;
export declare function sDKEnvironmentToJSON(object: SDKEnvironment): string;
/**
 * ---------------------------------------------------------------------------
 * Model source — where the catalog entry came from.
 * ---------------------------------------------------------------------------
 */
export declare enum ModelSource {
    MODEL_SOURCE_UNSPECIFIED = 0,
    /** MODEL_SOURCE_REMOTE - Downloaded from a URL */
    MODEL_SOURCE_REMOTE = 1,
    /** MODEL_SOURCE_LOCAL - Bundled or user-imported */
    MODEL_SOURCE_LOCAL = 2,
    UNRECOGNIZED = -1
}
export declare function modelSourceFromJSON(object: any): ModelSource;
export declare function modelSourceToJSON(object: ModelSource): string;
/**
 * ---------------------------------------------------------------------------
 * Archive types for multi-file model packages. Sources pre-IDL:
 *   Swift  ModelTypes.swift:195       (zip, tarBz2, tarGz, tarXz)
 *   Kotlin ModelTypes.kt:176          (ZIP, TAR_BZ2, TAR_GZ, TAR_XZ)
 *   Dart   model_types.dart:141       (zip, tarBz2, tarGz, tarXz)
 * ---------------------------------------------------------------------------
 */
export declare enum ArchiveType {
    ARCHIVE_TYPE_UNSPECIFIED = 0,
    ARCHIVE_TYPE_ZIP = 1,
    ARCHIVE_TYPE_TAR_BZ2 = 2,
    ARCHIVE_TYPE_TAR_GZ = 3,
    ARCHIVE_TYPE_TAR_XZ = 4,
    UNRECOGNIZED = -1
}
export declare function archiveTypeFromJSON(object: any): ArchiveType;
export declare function archiveTypeToJSON(object: ArchiveType): string;
export declare enum ArchiveStructure {
    ARCHIVE_STRUCTURE_UNSPECIFIED = 0,
    ARCHIVE_STRUCTURE_SINGLE_FILE_NESTED = 1,
    ARCHIVE_STRUCTURE_DIRECTORY_BASED = 2,
    ARCHIVE_STRUCTURE_NESTED_DIRECTORY = 3,
    ARCHIVE_STRUCTURE_UNKNOWN = 4,
    UNRECOGNIZED = -1
}
export declare function archiveStructureFromJSON(object: any): ArchiveStructure;
export declare function archiveStructureToJSON(object: ArchiveStructure): string;
/**
 * ---------------------------------------------------------------------------
 * High-level artifact classification — what KIND of bundle a model ships as.
 * Distinct from ModelFormat (the on-disk file format) and ArchiveType (the
 * compression flavor). Sources pre-IDL:
 *   Swift  ModelTypes.swift:~200            (singleFile, archive, multiFile, custom)
 *   Web    types.ts:149                     (SingleFile / Archive / MultiFile / Custom)
 *   Kotlin sealed class ModelArtifactType   (SingleFile / Archive / MultiFile / Custom)
 * ---------------------------------------------------------------------------
 */
export declare enum ModelArtifactType {
    MODEL_ARTIFACT_TYPE_UNSPECIFIED = 0,
    MODEL_ARTIFACT_TYPE_SINGLE_FILE = 1,
    MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE = 2,
    MODEL_ARTIFACT_TYPE_DIRECTORY = 3,
    MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE = 4,
    MODEL_ARTIFACT_TYPE_CUSTOM = 5,
    UNRECOGNIZED = -1
}
export declare function modelArtifactTypeFromJSON(object: any): ModelArtifactType;
export declare function modelArtifactTypeToJSON(object: ModelArtifactType): string;
/**
 * ---------------------------------------------------------------------------
 * Model registry lifecycle state. This is durable/catalog state, not a live
 * transfer progress stream. Per-download byte counters and transient progress
 * events stay in download_service.proto.
 * Sources pre-IDL:
 *   Web ModelRegistry.ts ManagedModel.status (registered/downloading/downloaded/loading/loaded/error)
 *   RN  ModelInfo.isDownloaded/isAvailable and registry query criteria
 * ---------------------------------------------------------------------------
 */
export declare enum ModelRegistryStatus {
    MODEL_REGISTRY_STATUS_UNSPECIFIED = 0,
    MODEL_REGISTRY_STATUS_REGISTERED = 1,
    MODEL_REGISTRY_STATUS_DOWNLOADING = 2,
    MODEL_REGISTRY_STATUS_DOWNLOADED = 3,
    MODEL_REGISTRY_STATUS_LOADING = 4,
    MODEL_REGISTRY_STATUS_LOADED = 5,
    MODEL_REGISTRY_STATUS_ERROR = 6,
    UNRECOGNIZED = -1
}
export declare function modelRegistryStatusFromJSON(object: any): ModelRegistryStatus;
export declare function modelRegistryStatusToJSON(object: ModelRegistryStatus): string;
export declare enum ModelQuerySortField {
    MODEL_QUERY_SORT_FIELD_UNSPECIFIED = 0,
    MODEL_QUERY_SORT_FIELD_NAME = 1,
    MODEL_QUERY_SORT_FIELD_CREATED_AT_UNIX_MS = 2,
    MODEL_QUERY_SORT_FIELD_UPDATED_AT_UNIX_MS = 3,
    MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES = 4,
    MODEL_QUERY_SORT_FIELD_LAST_USED_AT_UNIX_MS = 5,
    MODEL_QUERY_SORT_FIELD_USAGE_COUNT = 6,
    UNRECOGNIZED = -1
}
export declare function modelQuerySortFieldFromJSON(object: any): ModelQuerySortField;
export declare function modelQuerySortFieldToJSON(object: ModelQuerySortField): string;
export declare enum ModelQuerySortOrder {
    MODEL_QUERY_SORT_ORDER_UNSPECIFIED = 0,
    MODEL_QUERY_SORT_ORDER_ASCENDING = 1,
    MODEL_QUERY_SORT_ORDER_DESCENDING = 2,
    UNRECOGNIZED = -1
}
export declare function modelQuerySortOrderFromJSON(object: any): ModelQuerySortOrder;
export declare function modelQuerySortOrderToJSON(object: ModelQuerySortOrder): string;
/**
 * Role of a file inside a single/multi-file artifact. The generic COMPANION
 * role covers arbitrary sidecars; specific roles document common public
 * catalog files such as VLM mmproj files and tokenizer/config assets.
 */
export declare enum ModelFileRole {
    MODEL_FILE_ROLE_UNSPECIFIED = 0,
    MODEL_FILE_ROLE_PRIMARY_MODEL = 1,
    MODEL_FILE_ROLE_COMPANION = 2,
    /** MODEL_FILE_ROLE_VISION_PROJECTOR - llama.cpp VLM mmproj*.gguf */
    MODEL_FILE_ROLE_VISION_PROJECTOR = 3,
    /** MODEL_FILE_ROLE_TOKENIZER - tokenizer model/data files */
    MODEL_FILE_ROLE_TOKENIZER = 4,
    /** MODEL_FILE_ROLE_CONFIG - config.json or framework config */
    MODEL_FILE_ROLE_CONFIG = 5,
    /** MODEL_FILE_ROLE_VOCABULARY - vocab.txt / vocab.json */
    MODEL_FILE_ROLE_VOCABULARY = 6,
    /** MODEL_FILE_ROLE_MERGES - merges.txt */
    MODEL_FILE_ROLE_MERGES = 7,
    MODEL_FILE_ROLE_LABELS = 8,
    UNRECOGNIZED = -1
}
export declare function modelFileRoleFromJSON(object: any): ModelFileRole;
export declare function modelFileRoleToJSON(object: ModelFileRole): string;
/**
 * ---------------------------------------------------------------------------
 * Hardware acceleration preference for inference. Sources pre-IDL:
 *   Web    enums.ts:165   (Auto / WebGPU / CPU)
 *   Swift  extensions     (CPU / GPU / NPU / Metal)
 *   Kotlin enum           (CPU / GPU / NPU / Vulkan)
 * Canonicalized union below.
 * ---------------------------------------------------------------------------
 */
export declare enum AccelerationPreference {
    ACCELERATION_PREFERENCE_UNSPECIFIED = 0,
    ACCELERATION_PREFERENCE_AUTO = 1,
    ACCELERATION_PREFERENCE_CPU = 2,
    ACCELERATION_PREFERENCE_GPU = 3,
    ACCELERATION_PREFERENCE_NPU = 4,
    ACCELERATION_PREFERENCE_WEBGPU = 5,
    ACCELERATION_PREFERENCE_METAL = 6,
    ACCELERATION_PREFERENCE_VULKAN = 7,
    UNRECOGNIZED = -1
}
export declare function accelerationPreferenceFromJSON(object: any): AccelerationPreference;
export declare function accelerationPreferenceToJSON(object: AccelerationPreference): string;
/**
 * ---------------------------------------------------------------------------
 * Routing policy for hybrid (on-device vs cloud) inference. Sources pre-IDL:
 *   Web    enums.ts (RoutingPolicy)
 *          OnDevicePreferred / CloudPreferred / OnDeviceOnly / CloudOnly /
 *          Hybrid / CostOptimized / LatencyOptimized / PrivacyOptimized
 *   Swift  extensions (RoutingPolicy)
 * Canonical short-form below; specific PreferLocal/PreferCloud cover the
 * "preferred" cases, MANUAL covers explicit user override.
 * ---------------------------------------------------------------------------
 */
export declare enum RoutingPolicy {
    ROUTING_POLICY_UNSPECIFIED = 0,
    ROUTING_POLICY_PREFER_LOCAL = 1,
    ROUTING_POLICY_PREFER_CLOUD = 2,
    ROUTING_POLICY_COST_OPTIMIZED = 3,
    ROUTING_POLICY_LATENCY_OPTIMIZED = 4,
    ROUTING_POLICY_MANUAL = 5,
    UNRECOGNIZED = -1
}
export declare function routingPolicyFromJSON(object: any): RoutingPolicy;
export declare function routingPolicyToJSON(object: RoutingPolicy): string;
/**
 * Model-level thinking tag metadata. This intentionally uses a model-specific
 * message name because llm_options.proto already owns the generation-options
 * ThinkingTagPattern message in this proto package.
 */
export interface ModelThinkingTagPattern {
    openTag: string;
    closeTag: string;
}
export interface ModelInfoMetadata {
    description: string;
    author: string;
    license: string;
    tags: string[];
    version: string;
}
export interface ModelRuntimeCompatibility {
    compatibleFrameworks: InferenceFramework[];
    compatibleFormats: ModelFormat[];
}
/**
 * ---------------------------------------------------------------------------
 * Core metadata for a model entry.
 * Sources pre-IDL:
 *   Swift  ModelTypes.swift:393       (16 fields)
 *   Kotlin ModelTypes.kt:332          (16 fields, Long vs Int drift on download size)
 *   Dart   model_types.dart:335       (similar shape, nullable divergences)
 *   RN     HybridRunAnywhereCore.cpp:995-1010 (13 fields, string-typed category/format)
 * ---------------------------------------------------------------------------
 */
export interface ModelInfo {
    id: string;
    name: string;
    category: ModelCategory;
    format: ModelFormat;
    framework: InferenceFramework;
    downloadUrl: string;
    localPath: string;
    downloadSizeBytes: number;
    contextLength: number;
    supportsThinking: boolean;
    supportsLora: boolean;
    description: string;
    source: ModelSource;
    createdAtUnixMs: number;
    updatedAtUnixMs: number;
    /**
     * Separate from download_size_bytes: this is the estimated runtime RAM
     * requirement used by compatibility checks and model selection UIs.
     */
    memoryRequiredBytes?: number | undefined;
    /**
     * Lowercase hex SHA-256 checksum for the primary artifact. Per-file
     * checksums for multi-file artifacts live on ModelFileDescriptor.
     */
    checksumSha256?: string | undefined;
    /**
     * Thinking/reasoning metadata. `supports_thinking` remains the boolean
     * capability flag; this optional pattern declares model-specific tags.
     */
    thinkingPattern?: ModelThinkingTagPattern | undefined;
    /**
     * Structured public catalog metadata. `description` (field 12) is kept for
     * backward compatibility and should mirror metadata.description when both
     * are populated.
     */
    metadata?: ModelInfoMetadata | undefined;
    singleFile?: SingleFileArtifact | undefined;
    archive?: ArchiveArtifact | undefined;
    multiFile?: MultiFileArtifact | undefined;
    customStrategyId?: string | undefined;
    builtIn?: boolean | undefined;
    /**
     * High-level artifact classification, complementary to the `artifact`
     * oneof above. Allows catalog entries to carry a coarse type tag without
     * resolving the full strategy variant.
     */
    artifactType?: ModelArtifactType | undefined;
    /** Manifest of files that are expected on disk after fetch/extraction. */
    expectedFiles?: ExpectedModelFiles | undefined;
    /** Preferred hardware acceleration backend for this model. */
    accelerationPreference?: AccelerationPreference | undefined;
    /** Hybrid (on-device vs cloud) routing policy for this entry. */
    routingPolicy?: RoutingPolicy | undefined;
    /**
     * Framework/format compatibility declarations. `framework` (field 5) is
     * the canonical/preferred runtime when no explicit preferred_framework is set.
     */
    compatibility?: ModelRuntimeCompatibility | undefined;
    preferredFramework?: InferenceFramework | undefined;
    /**
     * Durable registry state. Live byte progress belongs to
     * download_service.DownloadProgress, not ModelInfo.
     */
    registryStatus?: ModelRegistryStatus | undefined;
    isDownloaded?: boolean | undefined;
    isAvailable?: boolean | undefined;
    lastUsedAtUnixMs?: number | undefined;
    usageCount?: number | undefined;
    syncPending?: boolean | undefined;
    statusMessage?: string | undefined;
}
/**
 * Repeated model registry responses use this wrapper because protobuf cannot
 * serialize a bare repeated field as a top-level message.
 */
export interface ModelInfoList {
    models: ModelInfo[];
}
export interface SingleFileArtifact {
    requiredPatterns: string[];
    optionalPatterns: string[];
}
export interface ArchiveArtifact {
    type: ArchiveType;
    structure: ArchiveStructure;
    requiredPatterns: string[];
    optionalPatterns: string[];
}
export interface ModelFileDescriptor {
    url: string;
    filename: string;
    isRequired: boolean;
    /**
     * Extended descriptor fields (Flutter model_types.dart:~350,
     * Swift ModelTypes.swift:~350). `is_required` (field 3) remains the
     * canonical "required" flag — the documented `required` boolean from
     * newer SDK sources maps onto it (default true, mirrored in Swift).
     */
    sizeBytes?: number | undefined;
    checksum?: string | undefined;
    /**
     * Path fields used by SDK-local wrappers/catalogs. `filename` is the
     * storage name for simple cases; relative_path/destination_path preserve
     * directory layouts for archive and multi-file artifacts.
     */
    relativePath?: string | undefined;
    destinationPath?: string | undefined;
    role?: ModelFileRole | undefined;
    localPath?: string | undefined;
}
export interface MultiFileArtifact {
    files: ModelFileDescriptor[];
}
/**
 * ---------------------------------------------------------------------------
 * Declarative manifest of files a multi-file / directory model is expected
 * to contain on disk after download/extraction. Used for verification before
 * hand-off to the inference framework. Sources pre-IDL:
 *   Flutter core/types/model_types.dart:420
 *   Swift   ModelTypes.swift:~300
 * ---------------------------------------------------------------------------
 */
export interface ExpectedModelFiles {
    files: ModelFileDescriptor[];
    rootDirectory?: string | undefined;
    requiredPatterns: string[];
    optionalPatterns: string[];
    description?: string | undefined;
}
/**
 * Registry/query filters shared by SDK model-management APIs. UI-only
 * presentation state and platform filesystem handles are intentionally not
 * represented here.
 */
export interface ModelQuery {
    framework?: InferenceFramework | undefined;
    category?: ModelCategory | undefined;
    format?: ModelFormat | undefined;
    downloadedOnly?: boolean | undefined;
    availableOnly?: boolean | undefined;
    maxSizeBytes?: number | undefined;
    searchQuery: string;
    source?: ModelSource | undefined;
    sortField?: ModelQuerySortField | undefined;
    sortOrder?: ModelQuerySortOrder | undefined;
}
export interface ModelCompatibilityResult {
    isCompatible: boolean;
    canRun: boolean;
    canFit: boolean;
    requiredMemoryBytes: number;
    availableMemoryBytes: number;
    requiredStorageBytes: number;
    availableStorageBytes: number;
    reasons: string[];
}
export interface ModelRegistryRefreshRequest {
    /** Fetch or merge a remote catalog through the platform/network adapter. */
    includeRemoteCatalog: boolean;
    /** Scan managed model directories and link valid on-disk artifacts. */
    rescanLocal: boolean;
    /** Clear downloaded/available state for registry rows whose files vanished. */
    pruneOrphans: boolean;
    /** Optional post-refresh filter for the returned model list. */
    query?: ModelQuery | undefined;
}
export interface ModelRegistryRefreshResult {
    success: boolean;
    models?: ModelInfoList | undefined;
    registeredCount: number;
    updatedCount: number;
    discoveredCount: number;
    prunedCount: number;
    refreshedAtUnixMs: number;
    warnings: string[];
    errorMessage: string;
}
export interface ModelListRequest {
    /** Set query.downloaded_only for downloaded-only lists. */
    query?: ModelQuery | undefined;
}
export interface ModelListResult {
    success: boolean;
    models?: ModelInfoList | undefined;
    errorMessage: string;
}
export interface ModelGetRequest {
    modelId: string;
}
export interface ModelGetResult {
    found: boolean;
    model?: ModelInfo | undefined;
    errorMessage: string;
}
export interface ModelImportRequest {
    /**
     * Catalog metadata to register or merge. If absent, discovery may infer a
     * minimal ModelInfo from the file name and detected format.
     */
    model?: ModelInfo | undefined;
    /**
     * Normalized path under platform control. Do not place transient OS file
     * picker handles in this field; adapters should first copy/link/authorize
     * them and provide a stable path visible to the C++ workflow.
     */
    sourcePath: string;
    copyIntoManagedStorage: boolean;
    overwriteExisting: boolean;
    files: ModelFileDescriptor[];
}
export interface ModelImportResult {
    success: boolean;
    model?: ModelInfo | undefined;
    localPath: string;
    importedBytes: number;
    warnings: string[];
    errorMessage: string;
}
export interface ModelDiscoveryRequest {
    /**
     * Platform adapters own permission and sandbox traversal. These are stable
     * roots that C++ may inspect using registered filesystem callbacks.
     */
    searchRoots: string[];
    recursive: boolean;
    linkDownloaded: boolean;
    purgeInvalid: boolean;
    query?: ModelQuery | undefined;
}
export interface DiscoveredModel {
    modelId: string;
    localPath: string;
    matchedRegistry: boolean;
    model?: ModelInfo | undefined;
    sizeBytes: number;
    warnings: string[];
}
export interface ModelDiscoveryResult {
    success: boolean;
    discoveredModels: DiscoveredModel[];
    linkedCount: number;
    purgedCount: number;
    warnings: string[];
    errorMessage: string;
}
export interface ModelLoadRequest {
    modelId: string;
    category?: ModelCategory | undefined;
    framework?: InferenceFramework | undefined;
    forceReload: boolean;
}
export interface ModelLoadResult {
    success: boolean;
    modelId: string;
    category: ModelCategory;
    framework: InferenceFramework;
    resolvedPath: string;
    loadedAtUnixMs: number;
    errorMessage: string;
}
export interface ModelUnloadRequest {
    modelId: string;
    category?: ModelCategory | undefined;
    unloadAll: boolean;
}
export interface ModelUnloadResult {
    success: boolean;
    unloadedModelIds: string[];
    errorMessage: string;
}
export interface CurrentModelRequest {
    category?: ModelCategory | undefined;
    framework?: InferenceFramework | undefined;
}
export interface CurrentModelResult {
    modelId: string;
    model?: ModelInfo | undefined;
    loadedAtUnixMs: number;
}
export interface ModelDeleteRequest {
    modelId: string;
    deleteFiles: boolean;
    unregister: boolean;
    unloadIfLoaded: boolean;
}
export interface ModelDeleteResult {
    success: boolean;
    modelId: string;
    deletedBytes: number;
    filesDeleted: boolean;
    registryUpdated: boolean;
    wasLoaded: boolean;
    errorMessage: string;
}
export declare const ModelThinkingTagPattern: {
    encode(message: ModelThinkingTagPattern, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelThinkingTagPattern;
    fromJSON(object: any): ModelThinkingTagPattern;
    toJSON(message: ModelThinkingTagPattern): unknown;
    create<I extends Exact<DeepPartial<ModelThinkingTagPattern>, I>>(base?: I): ModelThinkingTagPattern;
    fromPartial<I extends Exact<DeepPartial<ModelThinkingTagPattern>, I>>(object: I): ModelThinkingTagPattern;
};
export declare const ModelInfoMetadata: {
    encode(message: ModelInfoMetadata, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelInfoMetadata;
    fromJSON(object: any): ModelInfoMetadata;
    toJSON(message: ModelInfoMetadata): unknown;
    create<I extends Exact<DeepPartial<ModelInfoMetadata>, I>>(base?: I): ModelInfoMetadata;
    fromPartial<I extends Exact<DeepPartial<ModelInfoMetadata>, I>>(object: I): ModelInfoMetadata;
};
export declare const ModelRuntimeCompatibility: {
    encode(message: ModelRuntimeCompatibility, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelRuntimeCompatibility;
    fromJSON(object: any): ModelRuntimeCompatibility;
    toJSON(message: ModelRuntimeCompatibility): unknown;
    create<I extends Exact<DeepPartial<ModelRuntimeCompatibility>, I>>(base?: I): ModelRuntimeCompatibility;
    fromPartial<I extends Exact<DeepPartial<ModelRuntimeCompatibility>, I>>(object: I): ModelRuntimeCompatibility;
};
export declare const ModelInfo: {
    encode(message: ModelInfo, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelInfo;
    fromJSON(object: any): ModelInfo;
    toJSON(message: ModelInfo): unknown;
    create<I extends Exact<DeepPartial<ModelInfo>, I>>(base?: I): ModelInfo;
    fromPartial<I extends Exact<DeepPartial<ModelInfo>, I>>(object: I): ModelInfo;
};
export declare const ModelInfoList: {
    encode(message: ModelInfoList, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelInfoList;
    fromJSON(object: any): ModelInfoList;
    toJSON(message: ModelInfoList): unknown;
    create<I extends Exact<DeepPartial<ModelInfoList>, I>>(base?: I): ModelInfoList;
    fromPartial<I extends Exact<DeepPartial<ModelInfoList>, I>>(object: I): ModelInfoList;
};
export declare const SingleFileArtifact: {
    encode(message: SingleFileArtifact, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): SingleFileArtifact;
    fromJSON(object: any): SingleFileArtifact;
    toJSON(message: SingleFileArtifact): unknown;
    create<I extends Exact<DeepPartial<SingleFileArtifact>, I>>(base?: I): SingleFileArtifact;
    fromPartial<I extends Exact<DeepPartial<SingleFileArtifact>, I>>(object: I): SingleFileArtifact;
};
export declare const ArchiveArtifact: {
    encode(message: ArchiveArtifact, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ArchiveArtifact;
    fromJSON(object: any): ArchiveArtifact;
    toJSON(message: ArchiveArtifact): unknown;
    create<I extends Exact<DeepPartial<ArchiveArtifact>, I>>(base?: I): ArchiveArtifact;
    fromPartial<I extends Exact<DeepPartial<ArchiveArtifact>, I>>(object: I): ArchiveArtifact;
};
export declare const ModelFileDescriptor: {
    encode(message: ModelFileDescriptor, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelFileDescriptor;
    fromJSON(object: any): ModelFileDescriptor;
    toJSON(message: ModelFileDescriptor): unknown;
    create<I extends Exact<DeepPartial<ModelFileDescriptor>, I>>(base?: I): ModelFileDescriptor;
    fromPartial<I extends Exact<DeepPartial<ModelFileDescriptor>, I>>(object: I): ModelFileDescriptor;
};
export declare const MultiFileArtifact: {
    encode(message: MultiFileArtifact, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): MultiFileArtifact;
    fromJSON(object: any): MultiFileArtifact;
    toJSON(message: MultiFileArtifact): unknown;
    create<I extends Exact<DeepPartial<MultiFileArtifact>, I>>(base?: I): MultiFileArtifact;
    fromPartial<I extends Exact<DeepPartial<MultiFileArtifact>, I>>(object: I): MultiFileArtifact;
};
export declare const ExpectedModelFiles: {
    encode(message: ExpectedModelFiles, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ExpectedModelFiles;
    fromJSON(object: any): ExpectedModelFiles;
    toJSON(message: ExpectedModelFiles): unknown;
    create<I extends Exact<DeepPartial<ExpectedModelFiles>, I>>(base?: I): ExpectedModelFiles;
    fromPartial<I extends Exact<DeepPartial<ExpectedModelFiles>, I>>(object: I): ExpectedModelFiles;
};
export declare const ModelQuery: {
    encode(message: ModelQuery, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelQuery;
    fromJSON(object: any): ModelQuery;
    toJSON(message: ModelQuery): unknown;
    create<I extends Exact<DeepPartial<ModelQuery>, I>>(base?: I): ModelQuery;
    fromPartial<I extends Exact<DeepPartial<ModelQuery>, I>>(object: I): ModelQuery;
};
export declare const ModelCompatibilityResult: {
    encode(message: ModelCompatibilityResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelCompatibilityResult;
    fromJSON(object: any): ModelCompatibilityResult;
    toJSON(message: ModelCompatibilityResult): unknown;
    create<I extends Exact<DeepPartial<ModelCompatibilityResult>, I>>(base?: I): ModelCompatibilityResult;
    fromPartial<I extends Exact<DeepPartial<ModelCompatibilityResult>, I>>(object: I): ModelCompatibilityResult;
};
export declare const ModelRegistryRefreshRequest: {
    encode(message: ModelRegistryRefreshRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelRegistryRefreshRequest;
    fromJSON(object: any): ModelRegistryRefreshRequest;
    toJSON(message: ModelRegistryRefreshRequest): unknown;
    create<I extends Exact<DeepPartial<ModelRegistryRefreshRequest>, I>>(base?: I): ModelRegistryRefreshRequest;
    fromPartial<I extends Exact<DeepPartial<ModelRegistryRefreshRequest>, I>>(object: I): ModelRegistryRefreshRequest;
};
export declare const ModelRegistryRefreshResult: {
    encode(message: ModelRegistryRefreshResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelRegistryRefreshResult;
    fromJSON(object: any): ModelRegistryRefreshResult;
    toJSON(message: ModelRegistryRefreshResult): unknown;
    create<I extends Exact<DeepPartial<ModelRegistryRefreshResult>, I>>(base?: I): ModelRegistryRefreshResult;
    fromPartial<I extends Exact<DeepPartial<ModelRegistryRefreshResult>, I>>(object: I): ModelRegistryRefreshResult;
};
export declare const ModelListRequest: {
    encode(message: ModelListRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelListRequest;
    fromJSON(object: any): ModelListRequest;
    toJSON(message: ModelListRequest): unknown;
    create<I extends Exact<DeepPartial<ModelListRequest>, I>>(base?: I): ModelListRequest;
    fromPartial<I extends Exact<DeepPartial<ModelListRequest>, I>>(object: I): ModelListRequest;
};
export declare const ModelListResult: {
    encode(message: ModelListResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelListResult;
    fromJSON(object: any): ModelListResult;
    toJSON(message: ModelListResult): unknown;
    create<I extends Exact<DeepPartial<ModelListResult>, I>>(base?: I): ModelListResult;
    fromPartial<I extends Exact<DeepPartial<ModelListResult>, I>>(object: I): ModelListResult;
};
export declare const ModelGetRequest: {
    encode(message: ModelGetRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelGetRequest;
    fromJSON(object: any): ModelGetRequest;
    toJSON(message: ModelGetRequest): unknown;
    create<I extends Exact<DeepPartial<ModelGetRequest>, I>>(base?: I): ModelGetRequest;
    fromPartial<I extends Exact<DeepPartial<ModelGetRequest>, I>>(object: I): ModelGetRequest;
};
export declare const ModelGetResult: {
    encode(message: ModelGetResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelGetResult;
    fromJSON(object: any): ModelGetResult;
    toJSON(message: ModelGetResult): unknown;
    create<I extends Exact<DeepPartial<ModelGetResult>, I>>(base?: I): ModelGetResult;
    fromPartial<I extends Exact<DeepPartial<ModelGetResult>, I>>(object: I): ModelGetResult;
};
export declare const ModelImportRequest: {
    encode(message: ModelImportRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelImportRequest;
    fromJSON(object: any): ModelImportRequest;
    toJSON(message: ModelImportRequest): unknown;
    create<I extends Exact<DeepPartial<ModelImportRequest>, I>>(base?: I): ModelImportRequest;
    fromPartial<I extends Exact<DeepPartial<ModelImportRequest>, I>>(object: I): ModelImportRequest;
};
export declare const ModelImportResult: {
    encode(message: ModelImportResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelImportResult;
    fromJSON(object: any): ModelImportResult;
    toJSON(message: ModelImportResult): unknown;
    create<I extends Exact<DeepPartial<ModelImportResult>, I>>(base?: I): ModelImportResult;
    fromPartial<I extends Exact<DeepPartial<ModelImportResult>, I>>(object: I): ModelImportResult;
};
export declare const ModelDiscoveryRequest: {
    encode(message: ModelDiscoveryRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelDiscoveryRequest;
    fromJSON(object: any): ModelDiscoveryRequest;
    toJSON(message: ModelDiscoveryRequest): unknown;
    create<I extends Exact<DeepPartial<ModelDiscoveryRequest>, I>>(base?: I): ModelDiscoveryRequest;
    fromPartial<I extends Exact<DeepPartial<ModelDiscoveryRequest>, I>>(object: I): ModelDiscoveryRequest;
};
export declare const DiscoveredModel: {
    encode(message: DiscoveredModel, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DiscoveredModel;
    fromJSON(object: any): DiscoveredModel;
    toJSON(message: DiscoveredModel): unknown;
    create<I extends Exact<DeepPartial<DiscoveredModel>, I>>(base?: I): DiscoveredModel;
    fromPartial<I extends Exact<DeepPartial<DiscoveredModel>, I>>(object: I): DiscoveredModel;
};
export declare const ModelDiscoveryResult: {
    encode(message: ModelDiscoveryResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelDiscoveryResult;
    fromJSON(object: any): ModelDiscoveryResult;
    toJSON(message: ModelDiscoveryResult): unknown;
    create<I extends Exact<DeepPartial<ModelDiscoveryResult>, I>>(base?: I): ModelDiscoveryResult;
    fromPartial<I extends Exact<DeepPartial<ModelDiscoveryResult>, I>>(object: I): ModelDiscoveryResult;
};
export declare const ModelLoadRequest: {
    encode(message: ModelLoadRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelLoadRequest;
    fromJSON(object: any): ModelLoadRequest;
    toJSON(message: ModelLoadRequest): unknown;
    create<I extends Exact<DeepPartial<ModelLoadRequest>, I>>(base?: I): ModelLoadRequest;
    fromPartial<I extends Exact<DeepPartial<ModelLoadRequest>, I>>(object: I): ModelLoadRequest;
};
export declare const ModelLoadResult: {
    encode(message: ModelLoadResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelLoadResult;
    fromJSON(object: any): ModelLoadResult;
    toJSON(message: ModelLoadResult): unknown;
    create<I extends Exact<DeepPartial<ModelLoadResult>, I>>(base?: I): ModelLoadResult;
    fromPartial<I extends Exact<DeepPartial<ModelLoadResult>, I>>(object: I): ModelLoadResult;
};
export declare const ModelUnloadRequest: {
    encode(message: ModelUnloadRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelUnloadRequest;
    fromJSON(object: any): ModelUnloadRequest;
    toJSON(message: ModelUnloadRequest): unknown;
    create<I extends Exact<DeepPartial<ModelUnloadRequest>, I>>(base?: I): ModelUnloadRequest;
    fromPartial<I extends Exact<DeepPartial<ModelUnloadRequest>, I>>(object: I): ModelUnloadRequest;
};
export declare const ModelUnloadResult: {
    encode(message: ModelUnloadResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelUnloadResult;
    fromJSON(object: any): ModelUnloadResult;
    toJSON(message: ModelUnloadResult): unknown;
    create<I extends Exact<DeepPartial<ModelUnloadResult>, I>>(base?: I): ModelUnloadResult;
    fromPartial<I extends Exact<DeepPartial<ModelUnloadResult>, I>>(object: I): ModelUnloadResult;
};
export declare const CurrentModelRequest: {
    encode(message: CurrentModelRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): CurrentModelRequest;
    fromJSON(object: any): CurrentModelRequest;
    toJSON(message: CurrentModelRequest): unknown;
    create<I extends Exact<DeepPartial<CurrentModelRequest>, I>>(base?: I): CurrentModelRequest;
    fromPartial<I extends Exact<DeepPartial<CurrentModelRequest>, I>>(object: I): CurrentModelRequest;
};
export declare const CurrentModelResult: {
    encode(message: CurrentModelResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): CurrentModelResult;
    fromJSON(object: any): CurrentModelResult;
    toJSON(message: CurrentModelResult): unknown;
    create<I extends Exact<DeepPartial<CurrentModelResult>, I>>(base?: I): CurrentModelResult;
    fromPartial<I extends Exact<DeepPartial<CurrentModelResult>, I>>(object: I): CurrentModelResult;
};
export declare const ModelDeleteRequest: {
    encode(message: ModelDeleteRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelDeleteRequest;
    fromJSON(object: any): ModelDeleteRequest;
    toJSON(message: ModelDeleteRequest): unknown;
    create<I extends Exact<DeepPartial<ModelDeleteRequest>, I>>(base?: I): ModelDeleteRequest;
    fromPartial<I extends Exact<DeepPartial<ModelDeleteRequest>, I>>(object: I): ModelDeleteRequest;
};
export declare const ModelDeleteResult: {
    encode(message: ModelDeleteResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelDeleteResult;
    fromJSON(object: any): ModelDeleteResult;
    toJSON(message: ModelDeleteResult): unknown;
    create<I extends Exact<DeepPartial<ModelDeleteResult>, I>>(base?: I): ModelDeleteResult;
    fromPartial<I extends Exact<DeepPartial<ModelDeleteResult>, I>>(object: I): ModelDeleteResult;
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
//# sourceMappingURL=model_types.d.ts.map