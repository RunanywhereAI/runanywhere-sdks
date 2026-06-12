/**
 * ModelTypes+Artifacts.ts
 *
 * Model-category capability helpers backed by the C ABI — Swift parity:
 * `RAModelCategory.requiresContextLength` / `.supportsThinking`
 * (ModelTypes.swift:144-156) delegate to
 * `rac_model_category_requires_context_length` /
 * `rac_model_category_supports_thinking` so the capability table lives in
 * commons, not in each SDK. The WASM build exposes proto-int wrappers
 * (`_rac_model_category_*_proto`) because the proto enum and the C
 * `rac_model_category_t` use different numeric values.
 *
 * Also home to the Web ports of the Swift model-type helpers:
 * - wireString round-trips for ModelFormat / InferenceFramework
 *   (ModelTypes.swift:92-253). ModelCategory / ModelSource /
 *   ArchiveStructure wire strings are NOT duplicated here — the codegen'd
 *   `@runanywhere/proto-ts/convenience/model_types_convenience` helpers
 *   (`modelCategoryWireString`, …) are the canonical source.
 * - `modelInfoMake(...)` factory + artifact / expected-files / on-disk
 *   helpers (ModelTypes+Artifacts.swift:34-426), routed through the same
 *   commons ABIs Swift uses (`rac_model_info_make_proto`,
 *   `rac_artifact_expected_files_proto`).
 */

import {
  ArchiveStructure,
  ArchiveType,
  InferenceFramework,
  ModelArtifactType,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
  ModelInfo,
  ModelInfoMakeRequest,
  ModelSource,
  ExpectedModelFiles,
  archiveTypeToJSON,
  inferenceFrameworkToJSON,
  modelFormatToJSON,
  type ArchiveArtifact,
  type CurrentModelResult,
  type ModelFileDescriptor,
  type ModelLoadResult,
  type MultiFileArtifact,
  type SingleFileArtifact,
} from '@runanywhere/proto-ts/model_types';
import type { ThinkingTagPattern } from '@runanywhere/proto-ts/thinking_tag_pattern';
import { SDKException } from '../Foundation/SDKException';
import { SDKLogger } from '../Foundation/SDKLogger';
import { ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../runtime/EmscriptenModule';
import { formatFramework } from '../Public/Helpers/formatFramework';

const logger = new SDKLogger('ModelTypes');

interface CategoryCapabilityModule extends EmscriptenRunanywhereModule {
  /** Proto-int wrappers (wasm_exports.cpp) — take/return proto enum values. */
  _rac_model_category_requires_context_length_proto?(protoCategory: number): number;
  _rac_model_category_supports_thinking_proto?(protoCategory: number): number;
  /**
   * Canonical commons RAModelInfo factory — same proto-request ABI Swift
   * invokes via `NativeProtoABI` (ModelTypes+Artifacts.swift:19-27).
   * Request: `ModelInfoMakeRequest` bytes; result: `ModelInfo` bytes.
   */
  _rac_model_info_make_proto?(requestPtr: number, requestSize: number, outResult: number): number;
  /**
   * Expected-files derivation. Request: `ModelInfo` bytes; result:
   * `ExpectedModelFiles` bytes (ModelTypes+Artifacts.swift:23-27).
   */
  _rac_artifact_expected_files_proto?(requestPtr: number, requestSize: number, outResult: number): number;
  /**
   * Legacy short extension for a model format (`rac_model_format_extension`).
   * `rac_model_format_t` is value-aligned with the proto enum
   * (RAC_MODEL_FORMAT_ID_*), so the proto int passes through directly —
   * the same alignment Swift relies on in ModelTypes.swift:97-103.
   * Returns a pointer to a static C string (or 0).
   */
  _rac_model_format_extension?(protoFormat: number): number;
}

function requireCapabilityModule(feature: string): CategoryCapabilityModule {
  const module = getModuleForCapability('commons') as CategoryCapabilityModule | null;
  if (!module) {
    throw SDKException.backendNotAvailable(
      feature,
      'No WASM backend is registered. Call LlamaCPP.register() (or another backend) first.',
    );
  }
  return module;
}

function tryCapabilityModule(): CategoryCapabilityModule | null {
  return getModuleForCapability('commons') as CategoryCapabilityModule | null;
}

/**
 * Whether this category typically requires a context length.
 * Swift parity: `RAModelCategory.requiresContextLength` (ModelTypes.swift:147).
 */
export function categoryRequiresContextLength(category: ModelCategory): boolean {
  const module = requireCapabilityModule('modelCategory.requiresContextLength');
  if (typeof module._rac_model_category_requires_context_length_proto !== 'function') {
    throw SDKException.backendNotAvailable(
      'modelCategory.requiresContextLength',
      'Loaded WASM module does not export _rac_model_category_requires_context_length_proto.',
    );
  }
  return module._rac_model_category_requires_context_length_proto(category) !== 0;
}

/**
 * Whether this category typically supports thinking/reasoning.
 * Swift parity: `RAModelCategory.supportsThinking` (ModelTypes.swift:154).
 */
export function categorySupportsThinking(category: ModelCategory): boolean {
  const module = requireCapabilityModule('modelCategory.supportsThinking');
  if (typeof module._rac_model_category_supports_thinking_proto !== 'function') {
    throw SDKException.backendNotAvailable(
      'modelCategory.supportsThinking',
      'Loaded WASM module does not export _rac_model_category_supports_thinking_proto.',
    );
  }
  return module._rac_model_category_supports_thinking_proto(category) !== 0;
}

// ---------------------------------------------------------------------------
// ModelFormat wire strings — Swift parity: ModelTypes.swift:92-124
// ---------------------------------------------------------------------------

function knownModelFormats(): ModelFormat[] {
  return Object.values(ModelFormat)
    .filter((value): value is ModelFormat => typeof value === 'number' && value >= 0);
}

function knownInferenceFrameworkValues(): InferenceFramework[] {
  return Object.values(InferenceFramework)
    .filter((value): value is InferenceFramework => typeof value === 'number' && value >= 0);
}

/**
 * Legacy short extension string for a model format (e.g. `gguf`, `mlmodelc`).
 * Sourced from the commons table via the `_rac_model_format_extension` WASM
 * export so the extension table lives in C, not TS. Returns null when no
 * WASM module is active or the format has no extension.
 */
function modelFormatLegacyExtension(format: ModelFormat): string | null {
  const module = tryCapabilityModule();
  if (!module
    || typeof module._rac_model_format_extension !== 'function'
    || typeof module.UTF8ToString !== 'function') {
    return null;
  }
  const ptr = module._rac_model_format_extension(format);
  if (!ptr) return null;
  return module.UTF8ToString(ptr);
}

/**
 * Canonical wire string — the proto enum name (e.g. `MODEL_FORMAT_GGUF`).
 * Swift parity: `RAModelFormat.wireString` (ModelTypes.swift:100), which
 * delegates to `rac_model_format_wire_string`; the proto-ts
 * `modelFormatToJSON` table emits the identical proto enum names, so no
 * bridge call is needed.
 */
export function modelFormatWireString(format: ModelFormat): string {
  const wire = modelFormatToJSON(format);
  return wire === 'UNRECOGNIZED' ? 'MODEL_FORMAT_UNKNOWN' : wire;
}

/**
 * Parse a `ModelFormat` from a wire string. Matches case-insensitively
 * against the proto-name wire string (e.g. `MODEL_FORMAT_GGUF`) AND the
 * legacy short extension from `rac_model_format_extension` (e.g. `gguf`,
 * `onnx`, `mlmodel`) when a commons WASM module is active.
 * Swift parity: `RAModelFormat.fromWireString` (ModelTypes.swift:113).
 */
export function modelFormatFromWireString(raw: string): ModelFormat | undefined {
  const lowered = raw.toLowerCase();
  for (const format of knownModelFormats()) {
    if (modelFormatWireString(format).toLowerCase() === lowered) return format;
    const extension = modelFormatLegacyExtension(format);
    if (extension && extension.toLowerCase() === lowered) return format;
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// InferenceFramework wire strings — Swift parity: ModelTypes.swift:176-229
// ---------------------------------------------------------------------------

/**
 * Canonical wire string — the proto enum name
 * (e.g. `INFERENCE_FRAMEWORK_LLAMA_CPP`). Swift parity:
 * `RAInferenceFramework.wireString` (ModelTypes.swift:180), which delegates
 * to `rac_inference_framework_wire_string`; `inferenceFrameworkToJSON`
 * emits the identical proto enum names.
 */
export function inferenceFrameworkWireString(framework: InferenceFramework): string {
  const wire = inferenceFrameworkToJSON(framework);
  return wire === 'UNRECOGNIZED' ? 'INFERENCE_FRAMEWORK_UNKNOWN' : wire;
}

/**
 * Parse an `InferenceFramework` from a string, matching case-insensitively
 * against wire names and display names. Swift parity:
 * `RAInferenceFramework.init?(caseInsensitive:)` (ModelTypes.swift:225),
 * which delegates to `rac_inference_framework_from_string`. That C matcher
 * also accepts snake_case analytics keys; the analytics-key aliases are not
 * supported on Web until a `_rac_inference_framework_from_string` WASM
 * export exists. Display names come from `formatFramework`, the existing
 * mirror of `rac_framework_display_name`.
 */
export function inferenceFrameworkFromWireString(raw: string): InferenceFramework | undefined {
  const lowered = raw.toLowerCase();
  for (const framework of knownInferenceFrameworkValues()) {
    if (inferenceFrameworkWireString(framework).toLowerCase() === lowered) return framework;
  }
  for (const framework of knownInferenceFrameworkValues()) {
    const display = formatFramework(framework);
    if (display !== 'Unknown' && display.toLowerCase() === lowered) return framework;
  }
  if (lowered === 'unknown') return InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
  return undefined;
}

// ---------------------------------------------------------------------------
// ExpectedModelFiles helpers — Swift parity: ModelTypes+Artifacts.swift:33-43
// ---------------------------------------------------------------------------

/** Swift parity: `RAExpectedModelFiles.none` (ModelTypes+Artifacts.swift:34). */
export function expectedModelFilesNone(): ExpectedModelFiles {
  return ExpectedModelFiles.fromPartial({});
}

/** Swift parity: `RAExpectedModelFiles.isEmptyManifest` (ModelTypes+Artifacts.swift:36). */
export function isEmptyExpectedFilesManifest(manifest: ExpectedModelFiles): boolean {
  return manifest.files.length === 0
    && !manifest.rootDirectory
    && manifest.requiredPatterns.length === 0
    && manifest.optionalPatterns.length === 0
    && !manifest.description;
}

// ---------------------------------------------------------------------------
// ModelFileDescriptor helpers — Swift parity: ModelTypes+Artifacts.swift:45-96
// ---------------------------------------------------------------------------

function lastPathComponent(url: string): string {
  let path = url;
  try {
    path = new URL(url).pathname;
  } catch {
    // Not an absolute URL — treat the raw string as a path.
  }
  const segments = path.split('/').filter((segment) => segment.length > 0);
  return segments.length > 0 ? segments[segments.length - 1]! : url;
}

/**
 * Build a descriptor from a URL + destination filename.
 * Swift parity: `RAModelFileDescriptor.init(url:filename:isRequired:)`
 * (ModelTypes+Artifacts.swift:46).
 */
export function makeModelFileDescriptor(
  url: string,
  filename: string,
  isRequired = true,
): ModelFileDescriptor {
  return {
    url,
    filename,
    isRequired,
    relativePath: lastPathComponent(url),
    destinationPath: filename,
  };
}

/** Swift parity: `RAModelFileDescriptor.destinationFilename` (ModelTypes+Artifacts.swift:60). */
export function modelFileDescriptorDestinationFilename(descriptor: ModelFileDescriptor): string {
  if (descriptor.destinationPath) return descriptor.destinationPath;
  if (descriptor.filename) return descriptor.filename;
  return descriptor.relativePath ?? '';
}

/** Swift parity: `RAModelFileDescriptor.resolvedLocalPath` (ModelTypes+Artifacts.swift:66). */
export function modelFileDescriptorResolvedLocalPath(descriptor: ModelFileDescriptor): string | null {
  return descriptor.localPath ? descriptor.localPath : null;
}

// ---------------------------------------------------------------------------
// Model-file role resolvers — Swift parity: ModelTypes+Artifacts.swift:72-156.
// Swift declares the same accessors twice (RAModelLoadResult and
// RACurrentModelResult); both carry `resolvedArtifacts`, so the Web port
// exposes one set over `ModelFileDescriptor[]` plus a union-typed
// `lifecyclePrimaryArtifactPath`.
// ---------------------------------------------------------------------------

/** Swift parity: `Collection.resolvedModelFilePath(role:)` (ModelTypes+Artifacts.swift:73). */
export function resolvedModelFilePath(
  artifacts: ModelFileDescriptor[],
  role: ModelFileRole,
): string | null {
  const match = artifacts.find((descriptor) => descriptor.role === role);
  return match ? modelFileDescriptorResolvedLocalPath(match) : null;
}

/** Swift parity: `resolvedPrimaryModelPath` (ModelTypes+Artifacts.swift:77). */
export function resolvedPrimaryModelPath(artifacts: ModelFileDescriptor[]): string | null {
  return resolvedModelFilePath(artifacts, ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL);
}

/** Swift parity: `resolvedVisionProjectorPath` (ModelTypes+Artifacts.swift:81). */
export function resolvedVisionProjectorPath(artifacts: ModelFileDescriptor[]): string | null {
  return resolvedModelFilePath(artifacts, ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR);
}

/** Swift parity: `resolvedTokenizerPath` (ModelTypes+Artifacts.swift:85). */
export function resolvedTokenizerPath(artifacts: ModelFileDescriptor[]): string | null {
  return resolvedModelFilePath(artifacts, ModelFileRole.MODEL_FILE_ROLE_TOKENIZER);
}

/** Swift parity: `resolvedConfigPath` (ModelTypes+Artifacts.swift:89). */
export function resolvedConfigPath(artifacts: ModelFileDescriptor[]): string | null {
  return resolvedModelFilePath(artifacts, ModelFileRole.MODEL_FILE_ROLE_CONFIG);
}

/** Swift parity: `resolvedVocabularyPath` (ModelTypes+Artifacts.swift:93). */
export function resolvedVocabularyPath(artifacts: ModelFileDescriptor[]): string | null {
  return resolvedModelFilePath(artifacts, ModelFileRole.MODEL_FILE_ROLE_VOCABULARY);
}

/**
 * Primary lifecycle artifact path: the role-tagged primary model entry,
 * falling back to the top-level resolved path.
 * Swift parity: `lifecyclePrimaryArtifactPath` (ModelTypes+Artifacts.swift:123/:153).
 */
export function lifecyclePrimaryArtifactPath(
  result: ModelLoadResult | CurrentModelResult,
): string | null {
  return resolvedPrimaryModelPath(result.resolvedArtifacts)
    ?? (result.resolvedPath ? result.resolvedPath : null);
}

// ---------------------------------------------------------------------------
// ModelArtifactType helpers — Swift parity: ModelTypes+Artifacts.swift:164-193
// ---------------------------------------------------------------------------

/** Swift parity: `RAModelArtifactType.requiresExtraction` (ModelTypes+Artifacts.swift:165). */
export function artifactTypeRequiresExtraction(type: ModelArtifactType): boolean {
  switch (type) {
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE:
      return true;
    default:
      return false;
  }
}

/** Swift parity: `RAModelArtifactType.requiresDownload` (ModelTypes+Artifacts.swift:174). */
export function artifactTypeRequiresDownload(type: ModelArtifactType): boolean {
  return type !== ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN;
}

/** Swift parity: `RAModelArtifactType.displayName` (ModelTypes+Artifacts.swift:178). */
export function artifactTypeDisplayName(type: ModelArtifactType): string {
  switch (type) {
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE: return 'Single File';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE: return 'Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE: return 'ZIP Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE: return 'TAR.GZ Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE: return 'TAR.BZ2 Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE: return 'TAR.XZ Archive';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY: return 'Directory';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE: return 'Multi-File';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_CUSTOM: return 'Custom';
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN: return 'Built-in';
    default: return 'Unspecified';
  }
}

// ---------------------------------------------------------------------------
// Artifact oneof view — Swift parity: ModelTypes+Artifacts.swift:195-240.
// ts-proto flattens the `artifact` oneof into optional fields on ModelInfo;
// this discriminated union restores Swift's `RAModelInfo.OneOf_Artifact`.
// ---------------------------------------------------------------------------

export type ModelInfoArtifact =
  | { case: 'singleFile'; value: SingleFileArtifact }
  | { case: 'archive'; value: ArchiveArtifact }
  | { case: 'multiFile'; value: MultiFileArtifact }
  | { case: 'customStrategyId'; value: string }
  | { case: 'builtIn'; value: boolean };

/** Returns the active artifact oneof case, or null when unset. */
export function modelInfoArtifact(model: ModelInfo): ModelInfoArtifact | null {
  if (model.singleFile !== undefined) return { case: 'singleFile', value: model.singleFile };
  if (model.archive !== undefined) return { case: 'archive', value: model.archive };
  if (model.multiFile !== undefined) return { case: 'multiFile', value: model.multiFile };
  if (model.customStrategyId !== undefined) {
    return { case: 'customStrategyId', value: model.customStrategyId };
  }
  if (model.builtIn !== undefined) return { case: 'builtIn', value: model.builtIn };
  return null;
}

/**
 * Display label for an archive type, derived from the proto wire name
 * (`ARCHIVE_TYPE_TAR_BZ2` → `TAR.BZ2`). Matches Swift's
 * `RAArchiveType.displayName` (= `rac_archive_type_extension` uppercased,
 * ModelTypes.swift:340) for every defined case without needing a WASM
 * export for the C extension table.
 */
function archiveTypeDisplayName(type: ArchiveType): string {
  const wire = archiveTypeToJSON(type);
  if (wire === 'UNRECOGNIZED' || wire === 'ARCHIVE_TYPE_UNSPECIFIED') return '';
  return wire.replace('ARCHIVE_TYPE_', '').replace(/_/g, '.');
}

/** Swift parity: `RAArchiveType.artifactType` (ModelTypes+Artifacts.swift:445-455). */
function archiveTypeToArtifactType(type: ArchiveType): ModelArtifactType {
  switch (type) {
    case ArchiveType.ARCHIVE_TYPE_ZIP: return ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE;
    case ArchiveType.ARCHIVE_TYPE_TAR_GZ: return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE;
    case ArchiveType.ARCHIVE_TYPE_TAR_BZ2: return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE;
    case ArchiveType.ARCHIVE_TYPE_TAR_XZ: return ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE;
    default: return ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE;
  }
}

/** Swift parity: `RAModelArtifactType.legacyArchiveType` (ModelTypes+Artifacts.swift:431-443). */
function legacyArchiveType(type: ModelArtifactType): ArchiveType | null {
  switch (type) {
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE:
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
      return ArchiveType.ARCHIVE_TYPE_ZIP;
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
      return ArchiveType.ARCHIVE_TYPE_TAR_GZ;
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE:
      return ArchiveType.ARCHIVE_TYPE_TAR_BZ2;
    case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE:
      return ArchiveType.ARCHIVE_TYPE_TAR_XZ;
    default:
      return null;
  }
}

/** Swift parity: `OneOf_Artifact.artifactType` (ModelTypes+Artifacts.swift:196). */
export function artifactCaseType(artifact: ModelInfoArtifact): ModelArtifactType {
  switch (artifact.case) {
    case 'singleFile':
      return ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE;
    case 'archive':
      return archiveTypeToArtifactType(artifact.value.type);
    case 'multiFile':
      return ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE;
    case 'customStrategyId':
      return ModelArtifactType.MODEL_ARTIFACT_TYPE_CUSTOM;
    case 'builtIn':
      return artifact.value
        ? ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN
        : ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED;
  }
}

/** Swift parity: `OneOf_Artifact.requiresExtraction` (ModelTypes+Artifacts.swift:206). */
function artifactCaseRequiresExtraction(artifact: ModelInfoArtifact): boolean {
  if (artifact.case === 'archive') return true;
  return artifactTypeRequiresExtraction(artifactCaseType(artifact));
}

/** Swift parity: `OneOf_Artifact.requiresDownload` (ModelTypes+Artifacts.swift:211). */
function artifactCaseRequiresDownload(artifact: ModelInfoArtifact): boolean {
  if (artifact.case === 'builtIn' && artifact.value) return false;
  return artifactTypeRequiresDownload(artifactCaseType(artifact));
}

/** Swift parity: `OneOf_Artifact.displayName` (ModelTypes+Artifacts.swift:216). */
function artifactCaseDisplayName(artifact: ModelInfoArtifact): string {
  switch (artifact.case) {
    case 'singleFile':
      return artifactTypeDisplayName(ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    case 'archive':
      return `${archiveTypeDisplayName(artifact.value.type)} Archive`;
    case 'multiFile':
      return `Multi-File (${artifact.value.files.length} files)`;
    case 'customStrategyId':
      return artifact.value ? `Custom (${artifact.value})` : 'Custom';
    case 'builtIn':
      return artifactTypeDisplayName(ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN);
  }
}

// ---------------------------------------------------------------------------
// ModelInfo artifact helpers — Swift parity: ModelTypes+Artifacts.swift:242-426
// ---------------------------------------------------------------------------

/** Swift parity: `RAModelInfo.isBuiltIn` (ModelTypes+Artifacts.swift:326). */
export function modelInfoIsBuiltIn(model: ModelInfo): boolean {
  if (model.builtIn === true) return true;
  if (model.artifactType === ModelArtifactType.MODEL_ARTIFACT_TYPE_BUILT_IN) return true;
  if (model.localPath.startsWith('builtin:')) return true;
  return model.framework === InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS
    || model.framework === InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS;
}

/** Minimal Emscripten MEMFS surface needed for the on-disk probe. */
interface MemfsLike {
  stat(path: string): { mode: number };
  analyzePath?(path: string): { exists: boolean };
  readdir?(path: string): string[];
  isDir?(mode: number): boolean;
}

/** Emscripten POSIX-style file-mode bit for "is directory" (S_IFDIR). */
const S_IFDIR = 0o040000;

function memfsOf(module: object): MemfsLike | null {
  const candidate = (module as { FS?: unknown }).FS;
  if (candidate && typeof candidate === 'object'
    && typeof (candidate as MemfsLike).stat === 'function') {
    return candidate as MemfsLike;
  }
  return null;
}

function memfsHasEntries(fs: MemfsLike, path: string): boolean {
  if (typeof fs.readdir !== 'function') return false;
  try {
    return fs.readdir(path).some((name) => name !== '.' && name !== '..');
  } catch {
    return false;
  }
}

/**
 * Disk probe for a registry localPath.
 * Swift parity: `RAModelInfo.isDownloadedOnDisk` (ModelTypes+Artifacts.swift:335)
 * — FileManager existence check + `rac_path_is_non_empty_directory` for
 * directories. The Web equivalent of FileManager is the active WASM module's
 * MEMFS (mirrored from OPFS): an existence `stat` plus a non-empty `readdir`
 * for directories, which is the same check the C helper performs.
 */
export function modelInfoIsDownloadedOnDisk(model: ModelInfo): boolean {
  if (modelInfoIsBuiltIn(model)) return true;
  if (!model.localPath) return false;
  const module = tryCapabilityModule();
  const fs = module ? memfsOf(module) : null;
  if (!fs) return false;
  try {
    if (fs.analyzePath && !fs.analyzePath(model.localPath)?.exists) return false;
    const mode = fs.stat(model.localPath).mode;
    const isDirectory = typeof fs.isDir === 'function'
      ? fs.isDir(mode)
      : (mode & S_IFDIR) === S_IFDIR;
    if (isDirectory) return memfsHasEntries(fs, model.localPath);
    return true;
  } catch {
    return false;
  }
}

/** Swift parity: `RAModelInfo.isAvailableForUse` (ModelTypes+Artifacts.swift:345). */
export function modelInfoIsAvailableForUse(model: ModelInfo): boolean {
  return modelInfoIsBuiltIn(model)
    || modelInfoIsDownloadedOnDisk(model)
    || model.isAvailable === true;
}

/** Swift parity: `RAModelInfo.requiresExtraction` (ModelTypes+Artifacts.swift:349). */
export function modelInfoRequiresExtraction(model: ModelInfo): boolean {
  const artifact = modelInfoArtifact(model);
  if (artifact) return artifactCaseRequiresExtraction(artifact);
  return artifactTypeRequiresExtraction(
    model.artifactType ?? ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED,
  );
}

/** Swift parity: `RAModelInfo.requiresDownload` (ModelTypes+Artifacts.swift:353). */
export function modelInfoRequiresDownload(model: ModelInfo): boolean {
  if (modelInfoIsBuiltIn(model)) return false;
  const artifact = modelInfoArtifact(model);
  if (artifact) return artifactCaseRequiresDownload(artifact);
  return artifactTypeRequiresDownload(
    model.artifactType ?? ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED,
  );
}

/** Swift parity: `RAModelInfo.artifactDisplayName` (ModelTypes+Artifacts.swift:358). */
export function modelInfoArtifactDisplayName(model: ModelInfo): string {
  const artifact = modelInfoArtifact(model);
  if (artifact) return artifactCaseDisplayName(artifact);
  return artifactTypeDisplayName(
    model.artifactType ?? ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED,
  );
}

/** Swift parity: `RAModelInfo.archiveArtifact` (ModelTypes+Artifacts.swift:362). */
export function modelInfoArchiveArtifact(model: ModelInfo): ArchiveArtifact | null {
  const artifact = modelInfoArtifact(model);
  if (artifact?.case === 'archive') return artifact.value;
  const archiveType = legacyArchiveType(
    model.artifactType ?? ModelArtifactType.MODEL_ARTIFACT_TYPE_UNSPECIFIED,
  );
  if (archiveType === null) return null;
  return {
    type: archiveType,
    structure: ArchiveStructure.ARCHIVE_STRUCTURE_UNKNOWN,
    requiredPatterns: [],
    optionalPatterns: [],
    expectedFiles: undefined,
  };
}

/** Swift parity: `RAModelInfo.multiFileDescriptors` (ModelTypes+Artifacts.swift:371). */
export function modelInfoMultiFileDescriptors(model: ModelInfo): ModelFileDescriptor[] {
  const artifact = modelInfoArtifact(model);
  if (artifact?.case === 'multiFile') return artifact.value.files;
  return model.multiFile?.files ?? [];
}

/**
 * Canonical expected-files manifest. Routes through
 * `rac_artifact_expected_files_proto` which mirrors the legacy Swift
 * fall-through (top-level manifest → artifact-attached manifest → pattern
 * shorthand → multi-file descriptor seed).
 * Swift parity: `RAModelInfo.expectedArtifactFiles`
 * (ModelTypes+Artifacts.swift:379). Like Swift's `try? ... ?? .none`, this
 * degrades to the empty manifest when the ABI is unavailable or fails.
 */
export function modelInfoExpectedArtifactFiles(model: ModelInfo): ExpectedModelFiles {
  if (model.expectedFiles !== undefined) return model.expectedFiles;
  const module = tryCapabilityModule();
  if (!module || typeof module._rac_artifact_expected_files_proto !== 'function') {
    return expectedModelFilesNone();
  }
  const result = new ProtoWasmBridge(module, logger).withEncodedRequest(
    ModelInfo.fromPartial(model),
    ModelInfo,
    ExpectedModelFiles,
    (requestPtr, requestSize, outResult) => (
      module._rac_artifact_expected_files_proto!(requestPtr, requestSize, outResult)
    ),
    'rac_artifact_expected_files_proto',
  );
  return result ?? expectedModelFilesNone();
}

/** Swift parity: `RAModelInfo.setDownloadURL` (ModelTypes+Artifacts.swift:389). Pure update. */
export function modelInfoSettingDownloadUrl(model: ModelInfo, url: string | null): ModelInfo {
  return { ...model, downloadUrl: url ?? '' };
}

/**
 * Swift parity: `RAModelInfo.setLocalPath` (ModelTypes+Artifacts.swift:393) —
 * stamps the registry path and re-runs the on-disk probe. Pure update
 * (returns a new ModelInfo) instead of Swift's `mutating func`.
 */
export function modelInfoSettingLocalPath(model: ModelInfo, localPath: string | null): ModelInfo {
  const next: ModelInfo = { ...model, localPath: localPath ?? '' };
  next.isDownloaded = modelInfoIsDownloadedOnDisk(next);
  next.isAvailable = modelInfoIsAvailableForUse(next);
  return next;
}

/**
 * Swift parity: `RAModelInfo.setArtifact` (ModelTypes+Artifacts.swift:399) —
 * installs the artifact oneof, syncs `artifactType`, and re-derives the
 * expected-files manifest strictly from the new artifact (restoring the
 * prior manifest when derivation yields nothing).
 */
export function modelInfoSettingArtifact(model: ModelInfo, artifact: ModelInfoArtifact): ModelInfo {
  let next: ModelInfo = {
    ...model,
    singleFile: undefined,
    archive: undefined,
    multiFile: undefined,
    customStrategyId: undefined,
    builtIn: undefined,
    artifactType: artifactCaseType(artifact),
  };
  switch (artifact.case) {
    case 'singleFile': next.singleFile = artifact.value; break;
    case 'archive': next.archive = artifact.value; break;
    case 'multiFile': next.multiFile = artifact.value; break;
    case 'customStrategyId': next.customStrategyId = artifact.value; break;
    case 'builtIn': next.builtIn = artifact.value; break;
  }
  const prior = model.expectedFiles;
  next = { ...next, expectedFiles: undefined };
  const derived = modelInfoExpectedArtifactFiles(next);
  if (!isEmptyExpectedFilesManifest(derived)) {
    next.expectedFiles = derived;
  } else if (prior !== undefined) {
    next.expectedFiles = prior;
  }
  return next;
}

// ---------------------------------------------------------------------------
// modelInfoMake — Swift parity: `RAModelInfo.make` (ModelTypes+Artifacts.swift:248)
// ---------------------------------------------------------------------------

/**
 * Default thinking tag pattern. Swift parity:
 * `RAThinkingTagPattern.defaultPattern` (RALLMTypes+CppBridge.swift:99).
 */
function defaultThinkingTagPattern(): ThinkingTagPattern {
  return { openTag: '<think>', closeTag: '</think>' };
}

/** Clamp into int32 — Swift parity: `Int32(clamping:)` (ModelTypes+Artifacts.swift:291). */
function clampToInt32(value: number): number {
  const truncated = Math.trunc(value);
  if (truncated > 2147483647) return 2147483647;
  if (truncated < -2147483648) return -2147483648;
  return truncated;
}

/** Caller inputs for [modelInfoMake] — mirrors the Swift `make` parameter list. */
export interface ModelInfoMakeParams {
  id: string;
  name: string;
  category: ModelCategory;
  format: ModelFormat;
  framework: InferenceFramework;
  downloadURL?: string;
  localPath?: string;
  artifact?: ModelInfoArtifact;
  downloadSizeBytes?: number;
  contextLength?: number;
  supportsThinking?: boolean;
  thinkingPattern?: ThinkingTagPattern;
  description?: string;
  source?: ModelSource;
  createdAtUnixMs?: number;
  updatedAtUnixMs?: number;
}

/**
 * Build a fully-populated `ModelInfo`. Defaults (id/name/format/framework/
 * category/source/context-length/thinking-pattern/artifact/artifact_type)
 * come from the canonical commons factory (`rac_model_info_make_proto`);
 * caller-supplied non-request fields are layered on top.
 * Swift parity: `RAModelInfo.make(...)` (ModelTypes+Artifacts.swift:248-311).
 */
export function modelInfoMake(params: ModelInfoMakeParams): ModelInfo {
  const module = requireCapabilityModule('modelInfo.make');
  if (typeof module._rac_model_info_make_proto !== 'function') {
    throw SDKException.backendNotAvailable(
      'modelInfo.make',
      'Loaded WASM module does not export _rac_model_info_make_proto.',
    );
  }

  const request = ModelInfoMakeRequest.fromPartial({
    url: params.downloadURL ?? '',
    name: params.name,
    framework: params.framework,
    category: params.category,
    source: params.source ?? ModelSource.MODEL_SOURCE_REMOTE,
  });

  // Swift parity: `(try? NativeProtoABI.invoke(...)) ?? RAModelInfo()` —
  // a failed factory call degrades to an empty ModelInfo so the
  // caller-supplied fields below still apply.
  const made = new ProtoWasmBridge(module, logger).withEncodedRequest(
    request,
    ModelInfoMakeRequest,
    ModelInfo,
    (requestPtr, requestSize, outResult) => (
      module._rac_model_info_make_proto!(requestPtr, requestSize, outResult)
    ),
    'rac_model_info_make_proto',
  );
  let model: ModelInfo = made ?? ModelInfo.fromPartial({});

  // Caller-supplied id always wins (matches the legacy Swift contract);
  // commons would otherwise derive it from the URL via rac_model_generate_id.
  model.id = params.id;
  // Caller-supplied scalar fields not part of the make request.
  model.format = params.format;
  model.downloadSizeBytes = params.downloadSizeBytes ?? 0;
  if (params.contextLength !== undefined) {
    model.contextLength = clampToInt32(params.contextLength);
  }
  // Thinking is gated by category; the commons factory leaves the per-call
  // flag false, so honor the caller override here. Match the legacy
  // contract: when thinking is enabled and the caller did not supply a
  // pattern, fall back to the default pattern.
  model.supportsThinking = categorySupportsThinking(params.category)
    ? (params.supportsThinking ?? false)
    : false;
  if (model.supportsThinking) {
    model.thinkingPattern = params.thinkingPattern ?? defaultThinkingTagPattern();
  }
  model.description = params.description ?? '';
  model.createdAtUnixMs = params.createdAtUnixMs ?? Date.now();
  model.updatedAtUnixMs = params.updatedAtUnixMs ?? Date.now();
  // Caller-supplied artifact override re-runs the artifact-type sync.
  if (params.artifact) {
    model = modelInfoSettingArtifact(model, params.artifact);
  }
  // Caller-supplied local path runs the disk probe via setLocalPath.
  model = modelInfoSettingLocalPath(model, params.localPath ?? null);
  return model;
}
