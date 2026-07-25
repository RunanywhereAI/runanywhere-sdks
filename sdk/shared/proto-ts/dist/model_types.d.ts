import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { AccelerationPreference, HardwareProfile } from "./hardware_profile";
import { ThinkingTagPattern } from "./thinking_tag_pattern";
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
    /** MODEL_FORMAT_QNN_CONTEXT - Qualcomm Hexagon NPU context */
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
 *   Swift  ModelTypes.swift:76        (12 cases incl. coreml, mlx, whisperKitCoreML)
 *   Kotlin ComponentTypes.kt:122      (9 cases; no coreml / mlx / whisperKit)
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
    INFERENCE_FRAMEWORK_TFLITE = 11,
    INFERENCE_FRAMEWORK_EXECUTORCH = 12,
    INFERENCE_FRAMEWORK_MEDIAPIPE = 13,
    INFERENCE_FRAMEWORK_MLC = 14,
    INFERENCE_FRAMEWORK_PICO_LLM = 15,
    INFERENCE_FRAMEWORK_PIPER_TTS = 16,
    INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS = 19,
    /** INFERENCE_FRAMEWORK_BUILT_IN - rule-based, no model */
    INFERENCE_FRAMEWORK_BUILT_IN = 20,
    INFERENCE_FRAMEWORK_NONE = 21,
    INFERENCE_FRAMEWORK_UNKNOWN = 22,
    /** INFERENCE_FRAMEWORK_SHERPA - Sherpa-ONNX speech engine (STT/TTS/VAD) */
    INFERENCE_FRAMEWORK_SHERPA = 23,
    /** INFERENCE_FRAMEWORK_QHEXRT - Qualcomm Hexagon NPU (QHexRT runtime) */
    INFERENCE_FRAMEWORK_QHEXRT = 24,
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
 * SDK environment — product surface is development + production only.
 * Number 2 was formerly SDK_ENVIRONMENT_STAGING; reserved so wire values
 * never shift PRODUCTION=3.
 * ---------------------------------------------------------------------------
 */
export declare enum SDKEnvironment {
    SDK_ENVIRONMENT_UNSPECIFIED = 0,
    SDK_ENVIRONMENT_DEVELOPMENT = 1,
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
    /** MODEL_SOURCE_BUILT_IN - Platform/system model with no portable download artifact */
    MODEL_SOURCE_BUILT_IN = 3,
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
    MODEL_ARTIFACT_TYPE_ARCHIVE = 6,
    MODEL_ARTIFACT_TYPE_MULTI_FILE = 7,
    MODEL_ARTIFACT_TYPE_BUILT_IN = 8,
    MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE = 9,
    MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE = 10,
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
    /**
     * Portable URL/URI string for catalog metadata and download planning.
     * SDK/platform adapters own native HTTP execution, authentication/session
     * state, browser fetch handles, URLSession/background-transfer objects,
     * and permission prompts.
     */
    downloadUrl: string;
    /**
     * Stable path or URI string after platform adapters have normalized native
     * file handles. Do not place Android SAF/content URI permissions, iOS
     * security-scoped bookmarks, browser FileSystemHandle objects, or other
     * OS-governed capabilities in this C++-owned metadata field.
     */
    localPath: string;
    downloadSizeBytes: number;
    contextLength: number;
    supportsThinking: boolean;
    supportsLora: boolean;
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
    thinkingPattern?: ThinkingTagPattern | undefined;
    /** Structured public catalog metadata, including the model description. */
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
    /**
     * Full manifest form for SDK-local wrappers that attach expected files to
     * a single-file artifact. The pattern fields above remain for existing
     * generated consumers.
     */
    expectedFiles?: ExpectedModelFiles | undefined;
}
export interface ArchiveArtifact {
    type: ArchiveType;
    structure: ArchiveStructure;
    requiredPatterns: string[];
    optionalPatterns: string[];
    /**
     * Full manifest form for archive artifacts after extraction. Archive
     * extraction policy is portable; native filesystem permissions and handles
     * remain adapter-owned.
     */
    expectedFiles?: ExpectedModelFiles | undefined;
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
    /**
     * Path fields used by SDK-local wrappers/catalogs. `filename` is the
     * storage name for simple cases; relative_path/destination_path preserve
     * directory layouts for archive and multi-file artifacts.
     */
    relativePath?: string | undefined;
    destinationPath?: string | undefined;
    role?: ModelFileRole | undefined;
    localPath?: string | undefined;
    checksumSha256?: string | undefined;
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
    registryStatus?: ModelRegistryStatus | undefined;
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
    /**
     * Portable catalog selector. Auth state, cookies, native HTTP clients, and
     * background transfer handles are supplied by platform adapters.
     */
    catalogUri: string;
    /** Ignore cached catalog metadata and force a fresh adapter-backed refresh. */
    forceRefresh: boolean;
    /** Include local downloaded/available state reconciliation in the refresh. */
    includeDownloadedState: boolean;
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
    downloadedCount: number;
    availableCount: number;
    errorCount: number;
}
export interface ModelListRequest {
    /** Set query.downloaded_only for downloaded-only lists. */
    query?: ModelQuery | undefined;
    /** Include denormalized counts in ModelListResult. */
    includeCounts: boolean;
}
export interface ModelListResult {
    success: boolean;
    models?: ModelInfoList | undefined;
    errorMessage: string;
    totalCount: number;
    downloadedCount: number;
    availableCount: number;
    filteredCount: number;
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
    /** Validate format, expected files, and checksums before registry mutation. */
    validateBeforeRegister: boolean;
}
export interface ModelImportResult {
    success: boolean;
    model?: ModelInfo | undefined;
    localPath: string;
    importedBytes: number;
    warnings: string[];
    errorMessage: string;
    registered: boolean;
    copiedIntoManagedStorage: boolean;
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
    includeBuiltIn: boolean;
    includeUserImports: boolean;
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
    scannedCount: number;
    importedCount: number;
}
export interface ModelLoadRequest {
    modelId: string;
    category?: ModelCategory | undefined;
    framework?: InferenceFramework | undefined;
    forceReload: boolean;
    validateAvailability: boolean;
}
export interface ModelLoadResult {
    success: boolean;
    modelId: string;
    category: ModelCategory;
    framework: InferenceFramework;
    resolvedPath: string;
    loadedAtUnixMs: number;
    errorMessage: string;
    warnings: string[];
    alreadyLoaded: boolean;
    /**
     * Concrete artifacts selected by C++ model path resolution. The primary
     * model entry mirrors resolved_path; companion entries carry explicit
     * ModelFileRole values such as MODEL_FILE_ROLE_VISION_PROJECTOR.
     */
    resolvedArtifacts: ModelFileDescriptor[];
}
export interface ModelUnloadRequest {
    modelId: string;
    category?: ModelCategory | undefined;
    unloadAll: boolean;
    framework?: InferenceFramework | undefined;
}
export interface ModelUnloadResult {
    success: boolean;
    unloadedModelIds: string[];
    errorMessage: string;
    unloadedAtUnixMs: number;
    warnings: string[];
}
export interface CurrentModelRequest {
    category?: ModelCategory | undefined;
    framework?: InferenceFramework | undefined;
    includeModelMetadata: boolean;
}
export interface CurrentModelResult {
    modelId: string;
    model?: ModelInfo | undefined;
    loadedAtUnixMs: number;
    found: boolean;
    errorMessage: string;
    category: ModelCategory;
    framework: InferenceFramework;
    resolvedPath: string;
    resolvedArtifacts: ModelFileDescriptor[];
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
    warnings: string[];
}
/**
 * ---------------------------------------------------------------------------
 * Compatibility check request/result. Mirrors the public SDK
 * `checkCompatibility(modelId)` calls (RN CompatibilityBridge,
 * Kotlin compat path, Web ModelManager). The platform adapter supplies
 * available_ram_bytes / available_storage_bytes; commons looks up the
 * registry entry, computes the compatibility verdict (canRun / canFit),
 * and returns reasons / suggested alternative model ids.
 * ---------------------------------------------------------------------------
 */
export interface ModelCompatibilityRequest {
    /** Required. Model identifier to evaluate. */
    modelId: string;
    /**
     * Optional cached hardware profile from the platform adapter. If
     * unset, commons will read whatever it has cached internally; the
     * RAM/storage values below remain authoritative for the verdict.
     */
    hardwareProfile?: HardwareProfile | undefined;
    /**
     * Available RAM in bytes (from device probe). 0 = unknown — commons
     * will treat the requirement as satisfied.
     */
    availableRamBytes: number;
    /** Available storage in bytes (from filesystem probe). 0 = unknown. */
    availableStorageBytes: number;
    /**
     * Optional caller preferences (acceleration, framework). Reserved for
     * future use; today's verdict is based on memory/storage alone.
     */
    acceleratorPreference?: AccelerationPreference | undefined;
    preferredFramework?: InferenceFramework | undefined;
}
export interface ModelCompatibilityResult {
    /**
     * Mirrors the existing struct fields so SDKs can keep using the same
     * field names; populated from rac_model_compatibility_result_t.
     */
    isCompatible: boolean;
    canRun: boolean;
    canFit: boolean;
    requiredMemoryBytes: number;
    availableMemoryBytes: number;
    requiredStorageBytes: number;
    availableStorageBytes: number;
    /**
     * Human-readable reasons populated when the verdict is negative
     * (e.g. "insufficient RAM: requires X, available Y").
     */
    reasons: string[];
    /**
     * Optional suggested alternative model ids that *would* be compatible.
     * The current implementation leaves this empty; reserved for future
     * compatibility-aware suggestions.
     */
    suggestedAlternatives: string[];
    /**
     * Echo of the looked-up model id so callers can correlate batched
     * checks with their request id.
     */
    modelId: string;
    /**
     * Negative on failure; mirrors rac_result_t. Empty error_message on
     * success.
     */
    errorCode: number;
    errorMessage: string;
}
/**
 * ---------------------------------------------------------------------------
 * URL → ModelFormat inference request/result. Moves the Dart/Kotlin-side
 * URL-suffix heuristic (".gguf" → GGUF, ".onnx" → ONNX, ".tar.gz" wrapping an
 * inner format, ...) into commons so every SDK uses one implementation.
 * ---------------------------------------------------------------------------
 */
export interface ModelFormatFromUrlRequest {
    /**
     * Portable URL or file path string. Only the trailing file-extension
     * suffix is inspected; query strings and fragments are ignored.
     */
    url: string;
}
export interface ModelFormatFromUrlResult {
    /**
     * Primary detected format. For archive URLs this is the archive-wrapper
     * format (for example MODEL_FORMAT_ZIP); the extracted model format is
     * in inner_format below.
     */
    format: ModelFormat;
    /**
     * For archive URLs, the format of the primary file inside the archive
     * when it can be inferred from the URL (for example
     * "whisper-base.en.tar.gz" → inner_format = MODEL_FORMAT_ONNX). When the
     * archive content is unknown this is MODEL_FORMAT_UNSPECIFIED.
     */
    innerFormat: ModelFormat;
}
/**
 * ---------------------------------------------------------------------------
 * URL → ModelArtifactType inference request/result. Replaces Dart
 * withInferredArtifact and Kotlin inferArtifactFields with a single commons
 * call.
 * ---------------------------------------------------------------------------
 */
export interface ArtifactInferFromUrlRequest {
    /** Portable URL or file path string. */
    url: string;
    /**
     * Optional model identifier. Commons does not consult the registry with
     * this value today; it is carried for logging and telemetry only.
     */
    modelId: string;
}
export interface ArtifactInferFromUrlResult {
    /** Inferred artifact-type classification. */
    artifactType: ModelArtifactType;
    /**
     * For archive artifacts, the concrete archive format (ZIP, TAR_GZ, ...).
     * For single-file or directory artifacts this is
     * ARCHIVE_TYPE_UNSPECIFIED.
     */
    archiveType: ArchiveType;
    /**
     * For archive artifacts the known or inferred internal structure after
     * extraction. Defaults to ARCHIVE_STRUCTURE_UNKNOWN.
     */
    archiveStructure: ArchiveStructure;
    /**
     * When the URL suggests an archive wrapping a known primary file (for
     * example a Whisper model bundle containing encoder.onnx), this field
     * carries the relative path inside the archive when it can be inferred.
     * Empty otherwise.
     */
    primaryRelpath: string;
    /**
     * Inner file format for archive artifacts. MODEL_FORMAT_UNSPECIFIED when
     * the archive contents are unknown.
     */
    innerFormat: ModelFormat;
}
/**
 * ---------------------------------------------------------------------------
 * FetchAssignments request/result. Replaces the JSON shim
 * racModelRegistryFetchAssignments and the Web SDK's offline-friendly
 * fetchModelAssignments() entry point. The platform adapter owns HTTP
 * transport; commons consumes the cached / fetched entries and returns a
 * canonical proto byte payload.
 * ---------------------------------------------------------------------------
 */
export interface ModelRegistryFetchAssignmentsRequest {
    /**
     * Optional device identifier (forwarded to the platform adapter for
     * any auth headers it needs). May be empty when callers rely on
     * adapter-side auth state alone.
     */
    deviceId: string;
    /**
     * Optional environment selector; commons does not branch on this
     * value today, but it is preserved for adapter routing and telemetry.
     */
    environment?: SDKEnvironment | undefined;
    /** Bypass the assignment cache and force a fresh fetch. */
    forceRefresh: boolean;
}
export interface ModelRegistryFetchAssignmentsResult {
    success: boolean;
    models?: ModelInfoList | undefined;
    modelCount: number;
    fetchedAtUnixMs: number;
    errorCode: number;
    errorMessage: string;
}
/**
 * ---------------------------------------------------------------------------
 * Inputs for the canonical RAModelInfo factory. Replaces Swift's
 * `RAModelInfo.make(...)` ~370 LOC of field-defaulting and artifact-inference
 * logic with a commons-owned implementation. Commons fills 18 ModelInfo fields
 * (id, name, category/format/framework defaults, context-length defaults,
 * thinking gating + default pattern, artifact inference, source mark,
 * timestamps, and is_downloaded probe).
 * ---------------------------------------------------------------------------
 */
export interface ModelInfoMakeRequest {
    /**
     * Required. Download URL or file path. Used both as the metadata field
     * and as input to artifact-type inference (zip/tar.gz/tgz/... → archive,
     * anything else → single_file).
     */
    url: string;
    /**
     * Optional human-readable name. When empty commons derives it from the
     * URL via rac_model_generate_name() (replaces underscores/dashes with
     * spaces).
     */
    name: string;
    /**
     * Optional inference framework. UNSPECIFIED triggers detection from the
     * URL extension; commons looks up the format and maps to a default
     * framework via rac_model_detect_framework_from_format().
     */
    framework?: InferenceFramework | undefined;
    /**
     * Optional category. UNSPECIFIED falls back to the framework default
     * (rac_model_category_from_framework()).
     */
    category?: ModelCategory | undefined;
    /** Optional source. UNSPECIFIED is treated as MODEL_SOURCE_REMOTE. */
    source?: ModelSource | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Inputs for the canonical "register a model from a URL" entry point.
 * Composes ModelInfoMakeRequest with the existing registry save path
 * so SDKs replace ~60 LOC of build-and-save glue with a single ABI call.
 * Produces the saved ModelInfo (matches rac_model_registry_register_proto_buffer
 * shape).
 * ---------------------------------------------------------------------------
 */
export interface RegisterModelFromUrlRequest {
    /**
     * Required. Download URL or file path. Routed straight into
     * ModelInfoMakeRequest.url; format/artifact inference and id/name
     * generation reuse the same factory semantics.
     */
    url: string;
    /** Optional human-readable name. Empty → derived from URL. */
    name: string;
    /**
     * Optional inference framework. UNSPECIFIED triggers detection from the
     * URL extension (rac_model_detect_framework_from_format).
     */
    framework?: InferenceFramework | undefined;
    /** Optional category. UNSPECIFIED falls back to the framework default. */
    category?: ModelCategory | undefined;
    /** Optional source. UNSPECIFIED is treated as MODEL_SOURCE_REMOTE. */
    source?: ModelSource | undefined;
    /**
     * Caller-supplied capability fields. When set, the register-from-url C++
     * path honors them on the saved ModelInfo instead of its inference
     * defaults (which hardcode supports_lora=false, download_size=0, infer
     * artifact_type from the URL). This lets every SDK drop the post-register
     * "patch + resave" pass. Tags 6-13 are free (1-5 stay wire-compatible with
     * ModelInfoMakeRequest).
     */
    memoryRequiredBytes?: number | undefined;
    supportsThinking?: boolean | undefined;
    supportsLora?: boolean | undefined;
    artifactType?: ModelArtifactType | undefined;
    contextLength?: number | undefined;
    description?: string | undefined;
    downloadSizeBytes?: number | undefined;
    /** Explicit id override. Empty -> derived from URL/name. */
    id?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Inputs for registering a multi-file model (each file carries its own URL,
 * so there is no model-level URL). Replaces the hand-built MultiFileArtifact
 * ModelInfo every SDK assembles today. Produces the saved ModelInfo.
 * ---------------------------------------------------------------------------
 */
export interface RegisterMultiFileModelRequest {
    id: string;
    name: string;
    framework: InferenceFramework;
    files: ModelFileDescriptor[];
    category?: ModelCategory | undefined;
    format?: ModelFormat | undefined;
    memoryRequiredBytes?: number | undefined;
    downloadSizeBytes?: number | undefined;
    contextLength?: number | undefined;
    supportsThinking?: boolean | undefined;
    supportsLora?: boolean | undefined;
    description?: string | undefined;
    source?: ModelSource | undefined;
}
export declare const ModelInfoMetadata: MessageFns<ModelInfoMetadata>;
export declare const ModelRuntimeCompatibility: MessageFns<ModelRuntimeCompatibility>;
export declare const ModelInfo: MessageFns<ModelInfo>;
export declare const ModelInfoList: MessageFns<ModelInfoList>;
export declare const SingleFileArtifact: MessageFns<SingleFileArtifact>;
export declare const ArchiveArtifact: MessageFns<ArchiveArtifact>;
export declare const ModelFileDescriptor: MessageFns<ModelFileDescriptor>;
export declare const MultiFileArtifact: MessageFns<MultiFileArtifact>;
export declare const ExpectedModelFiles: MessageFns<ExpectedModelFiles>;
export declare const ModelQuery: MessageFns<ModelQuery>;
export declare const ModelRegistryRefreshRequest: MessageFns<ModelRegistryRefreshRequest>;
export declare const ModelRegistryRefreshResult: MessageFns<ModelRegistryRefreshResult>;
export declare const ModelListRequest: MessageFns<ModelListRequest>;
export declare const ModelListResult: MessageFns<ModelListResult>;
export declare const ModelGetRequest: MessageFns<ModelGetRequest>;
export declare const ModelGetResult: MessageFns<ModelGetResult>;
export declare const ModelImportRequest: MessageFns<ModelImportRequest>;
export declare const ModelImportResult: MessageFns<ModelImportResult>;
export declare const ModelDiscoveryRequest: MessageFns<ModelDiscoveryRequest>;
export declare const DiscoveredModel: MessageFns<DiscoveredModel>;
export declare const ModelDiscoveryResult: MessageFns<ModelDiscoveryResult>;
export declare const ModelLoadRequest: MessageFns<ModelLoadRequest>;
export declare const ModelLoadResult: MessageFns<ModelLoadResult>;
export declare const ModelUnloadRequest: MessageFns<ModelUnloadRequest>;
export declare const ModelUnloadResult: MessageFns<ModelUnloadResult>;
export declare const CurrentModelRequest: MessageFns<CurrentModelRequest>;
export declare const CurrentModelResult: MessageFns<CurrentModelResult>;
export declare const ModelDeleteRequest: MessageFns<ModelDeleteRequest>;
export declare const ModelDeleteResult: MessageFns<ModelDeleteResult>;
export declare const ModelCompatibilityRequest: MessageFns<ModelCompatibilityRequest>;
export declare const ModelCompatibilityResult: MessageFns<ModelCompatibilityResult>;
export declare const ModelFormatFromUrlRequest: MessageFns<ModelFormatFromUrlRequest>;
export declare const ModelFormatFromUrlResult: MessageFns<ModelFormatFromUrlResult>;
export declare const ArtifactInferFromUrlRequest: MessageFns<ArtifactInferFromUrlRequest>;
export declare const ArtifactInferFromUrlResult: MessageFns<ArtifactInferFromUrlResult>;
export declare const ModelRegistryFetchAssignmentsRequest: MessageFns<ModelRegistryFetchAssignmentsRequest>;
export declare const ModelRegistryFetchAssignmentsResult: MessageFns<ModelRegistryFetchAssignmentsResult>;
export declare const ModelInfoMakeRequest: MessageFns<ModelInfoMakeRequest>;
export declare const RegisterModelFromUrlRequest: MessageFns<RegisterModelFromUrlRequest>;
export declare const RegisterMultiFileModelRequest: MessageFns<RegisterMultiFileModelRequest>;
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
