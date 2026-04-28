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
    singleFile?: SingleFileArtifact | undefined;
    archive?: ArchiveArtifact | undefined;
    multiFile?: MultiFileArtifact | undefined;
    customStrategyId?: string | undefined;
    builtIn?: boolean | undefined;
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
}
export interface MultiFileArtifact {
    files: ModelFileDescriptor[];
}
export declare const ModelInfo: {
    encode(message: ModelInfo, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelInfo;
    fromJSON(object: any): ModelInfo;
    toJSON(message: ModelInfo): unknown;
    create<I extends Exact<DeepPartial<ModelInfo>, I>>(base?: I): ModelInfo;
    fromPartial<I extends Exact<DeepPartial<ModelInfo>, I>>(object: I): ModelInfo;
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