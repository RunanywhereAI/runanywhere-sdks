/// ModelTypes + CppBridge
///
/// Conversion extensions for Dart model types to C++ model types.
/// Used by DartBridgeModelRegistry to convert between Dart and C++ types.
///
/// Mirrors Swift's ModelTypes+CppBridge.swift exactly. Enum mappers
/// (proto integer ↔ C integer) delegate to commons' `rac_*_from_proto` /
/// `rac_*_to_proto` ABIs so the conversion logic stays
/// single-sourced in C++.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:runanywhere/core/native/rac_native.dart' show RacNative;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart' as model_pb;
import 'package:runanywhere/generated/model_types.pbenum.dart' as pb;
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';

// =============================================================================
// C++ Constants (from rac_model_types.h)
// =============================================================================

/// Artifact kind constants (rac_artifact_type_kind_t).
/// Values mirror commons' `rac_artifact_type_kind_t` enum:
///   SINGLE_FILE = 0, ARCHIVE = 1, MULTI_FILE = 2, CUSTOM = 3, BUILT_IN = 4.
abstract class RacArtifactKind {
  static const int singleFile = 0;
  static const int archive = 1;
  static const int multiFile = 2;
  static const int custom = 3;
  static const int builtIn = 4;
}

// =============================================================================
// FFI bindings for commons enum mappers
//
// Each pair maps a Dart proto enum integer (e.g.
// `pb.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP.value`) to/from the
// platform-native `rac_*_t` integer. Signature for every ABI:
//   `rac_result_t rac_*_from_proto(int32_t proto_value, int32_t* out);`
//   `rac_result_t rac_*_to_proto  (int32_t value,       int32_t* out);`
// (The C enums are `int` so they pass through Dart FFI as `Int32`.)
// =============================================================================

typedef _RacEnumMapperNative = Int32 Function(Int32, Pointer<Int32>);
typedef _RacEnumMapperDart = int Function(int, Pointer<Int32>);

final SDKLogger _mapperLogger = SDKLogger('ModelTypesCppBridge');

class _EnumMapperCache {
  _EnumMapperCache._();
  static final _EnumMapperCache instance = _EnumMapperCache._();

  final Map<String, _RacEnumMapperDart?> _cache =
      <String, _RacEnumMapperDart?>{};

  _RacEnumMapperDart? lookup(String symbol) {
    if (_cache.containsKey(symbol)) return _cache[symbol];
    try {
      final lib = PlatformLoader.loadCommons();
      final fn =
          lib.lookupFunction<_RacEnumMapperNative, _RacEnumMapperDart>(symbol);
      _cache[symbol] = fn;
      return fn;
    } catch (e) {
      _mapperLogger.debug('FFI mapper $symbol not available: $e');
      _cache[symbol] = null;
      return null;
    }
  }
}

/// Invoke a `rac_*_from_proto` / `rac_*_to_proto` mapper. Returns the mapped
/// integer on success, or `fallback` when the symbol is missing or the C
/// call rejects the input (preserves prior hand-written fallback behavior).
int _invokeEnumMapper(String symbol, int input, int fallback) {
  final fn = _EnumMapperCache.instance.lookup(symbol);
  if (fn == null) return fallback;
  final outPtr = calloc<Int32>();
  try {
    final result = fn(input, outPtr);
    if (result == RacResultCode.success) {
      return outPtr.value;
    }
    return fallback;
  } finally {
    calloc.free(outPtr);
  }
}

pb.ModelCategory _categoryProtoFromC(int cCategory) {
  final protoValue = _invokeEnumMapper(
    'rac_model_category_to_proto',
    cCategory,
    pb.ModelCategory.MODEL_CATEGORY_UNSPECIFIED.value,
  );
  return pb.ModelCategory.valueOf(protoValue) ??
      pb.ModelCategory.MODEL_CATEGORY_UNSPECIFIED;
}

pb.ModelFormat _formatProtoFromC(int cFormat) {
  final protoValue = _invokeEnumMapper(
    'rac_model_format_to_proto',
    cFormat,
    pb.ModelFormat.MODEL_FORMAT_UNKNOWN.value,
  );
  return pb.ModelFormat.valueOf(protoValue) ??
      pb.ModelFormat.MODEL_FORMAT_UNKNOWN;
}

pb.InferenceFramework _frameworkProtoFromC(int cFramework) {
  final protoValue = _invokeEnumMapper(
    'rac_inference_framework_to_proto',
    cFramework,
    pb.InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN.value,
  );
  return pb.InferenceFramework.valueOf(protoValue) ??
      pb.InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
}

/// Public C → proto inference-framework mapper. Mirrors Swift
/// `RAInferenceFramework.fromCFramework(_:)` — delegates to commons'
/// `rac_inference_framework_to_proto`.
pb.InferenceFramework inferenceFrameworkFromC(int cFramework) =>
    _frameworkProtoFromC(cFramework);

// =============================================================================
// Generated proto <-> C++ conversion helpers
// =============================================================================

extension ProtoModelCategoryCppBridge on pb.ModelCategory {
  /// Convert a generated model category enum to C++ rac_model_category_t.
  /// Delegates to commons' `rac_model_category_from_proto`.
  int toC() => _invokeEnumMapper(
        'rac_model_category_from_proto',
        value,
        99, // RAC_MODEL_CATEGORY_UNKNOWN
      );

  String get displayName {
    switch (this) {
      case pb.ModelCategory.MODEL_CATEGORY_LANGUAGE:
        return 'Language Model';
      case pb.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
        return 'Speech Recognition';
      case pb.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
        return 'Text-to-Speech';
      case pb.ModelCategory.MODEL_CATEGORY_VISION:
        return 'Vision Model';
      case pb.ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:
        return 'Image Generation';
      case pb.ModelCategory.MODEL_CATEGORY_MULTIMODAL:
        return 'Multimodal';
      case pb.ModelCategory.MODEL_CATEGORY_AUDIO:
        return 'Audio Processing';
      case pb.ModelCategory.MODEL_CATEGORY_EMBEDDING:
        return 'Embedding Model';
      case pb.ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
        return 'Voice Activity Detection';
      case pb.ModelCategory.MODEL_CATEGORY_UNSPECIFIED:
      default:
        return 'Unknown';
    }
  }
}

extension ProtoModelFormatCppBridge on pb.ModelFormat {
  /// Convert a generated model format enum to C++ rac_model_format_t.
  /// Delegates to commons' `rac_model_format_from_proto`.
  int toC() => _invokeEnumMapper(
        'rac_model_format_from_proto',
        value,
        99, // RAC_MODEL_FORMAT_UNKNOWN
      );

  String get rawValue {
    switch (this) {
      case pb.ModelFormat.MODEL_FORMAT_GGUF:
        return 'gguf';
      case pb.ModelFormat.MODEL_FORMAT_GGML:
        return 'ggml';
      case pb.ModelFormat.MODEL_FORMAT_ONNX:
        return 'onnx';
      case pb.ModelFormat.MODEL_FORMAT_ORT:
        return 'ort';
      case pb.ModelFormat.MODEL_FORMAT_BIN:
        return 'bin';
      case pb.ModelFormat.MODEL_FORMAT_COREML:
        return 'coreml';
      case pb.ModelFormat.MODEL_FORMAT_TFLITE:
        return 'tflite';
      default:
        return 'unknown';
    }
  }
}

extension ProtoInferenceFrameworkCppBridge on pb.InferenceFramework {
  /// Convert a generated inference framework enum to C++ rac_inference_framework_t.
  /// Delegates to commons' `rac_inference_framework_from_proto`.
  int toC() => _invokeEnumMapper(
        'rac_inference_framework_from_proto',
        value,
        99, // RAC_FRAMEWORK_UNKNOWN
      );

  /// Snake_case key for analytics/telemetry. Delegates to commons'
  /// `rac_inference_framework_analytics_key` so the table lives in one
  /// place across every SDK — mirrors Swift
  /// `RAInferenceFramework.analyticsKey` (ModelTypes.swift:195-199).
  String get analyticsKey {
    final fn = RacNative.bindings.rac_inference_framework_analytics_key;
    if (fn == null) return 'unknown';
    final out = calloc<Pointer<Utf8>>();
    try {
      final rc = fn(toC(), out);
      if (rc != RacResultCode.success || out.value == nullptr) {
        return 'unknown';
      }
      // Static literal owned by commons — read, never free.
      return out.value.toDartString();
    } finally {
      calloc.free(out);
    }
  }

  String get displayName {
    switch (this) {
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_ONNX:
        return 'ONNX Runtime';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_SHERPA:
        return 'Sherpa-ONNX';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP:
        return 'llama.cpp';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
        return 'Foundation Models';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS:
        return 'System TTS';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO:
        return 'FluidAudio';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_GENIE:
        return 'Qualcomm Genie';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_COREML:
        return 'Core ML';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_MLX:
        return 'MLX';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_METALRT:
        return 'MetalRT';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN:
        return 'Built-in';
      case pb.InferenceFramework.INFERENCE_FRAMEWORK_NONE:
        return 'None';
      default:
        return 'Unknown';
    }
  }
}

extension ProtoModelSourceCppBridge on pb.ModelSource {
  /// Convert a generated model source enum to C++ rac_model_source_t.
  /// Delegates to commons' `rac_model_source_from_proto`.
  int toC() => _invokeEnumMapper(
        'rac_model_source_from_proto',
        value,
        0, // RAC_MODEL_SOURCE_REMOTE
      );
}

extension ProtoModelInfoHelpers on model_pb.ModelInfo {
  Uri? get downloadUri => hasDownloadUrl() && downloadUrl.isNotEmpty
      ? Uri.tryParse(downloadUrl)
      : null;

  String? get localFilePath =>
      hasLocalPath() && localPath.isNotEmpty ? localPath : null;

  int? get downloadSize =>
      hasDownloadSizeBytes() ? downloadSizeBytes.toInt() : null;

  int? get nullableContextLength =>
      hasContextLength() && contextLength > 0 ? contextLength : null;

  bool get isBuiltIn {
    if (hasBuiltIn() && builtIn) return true;
    if (localPath.startsWith('builtin:')) return true;
    return framework ==
            pb.InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
        framework == pb.InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS ||
        framework == pb.InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN;
  }

  bool get isDownloaded {
    if (isBuiltIn) return true;
    final path = localFilePath;
    if (path == null) return false;
    return File(path).existsSync() || Directory(path).existsSync();
  }

  bool get isAvailable => isDownloaded;
}

model_pb.ModelInfo protoModelInfoFromCFields({
  required String id,
  required String name,
  required int category,
  required int format,
  required int framework,
  required int source,
  required int downloadSizeBytes,
  required int contextLength,
  String? downloadUrl,
  String? localPath,
  int supportsThinking = 0,
  int supportsLora = 0,
  String? description,
  int createdAtUnixMs = 0,
  int updatedAtUnixMs = 0,
}) {
  return model_pb.ModelInfo(
    id: id,
    name: name,
    category: _categoryProtoFromC(category),
    format: _formatProtoFromC(format),
    framework: _frameworkProtoFromC(framework),
    source: _sourceProtoFromC(source),
    downloadUrl: downloadUrl ?? '',
    localPath: localPath ?? '',
    downloadSizeBytes: fixnum.Int64(downloadSizeBytes),
    contextLength: contextLength,
    supportsThinking: supportsThinking != 0,
    supportsLora: supportsLora != 0,
    description: description ?? '',
    createdAtUnixMs: fixnum.Int64(createdAtUnixMs),
    updatedAtUnixMs: fixnum.Int64(updatedAtUnixMs),
  );
}

pb.ModelSource _sourceProtoFromC(int cSource) {
  final protoValue = _invokeEnumMapper(
    'rac_model_source_to_proto',
    cSource,
    pb.ModelSource.MODEL_SOURCE_UNSPECIFIED.value,
  );
  return pb.ModelSource.valueOf(protoValue) ??
      pb.ModelSource.MODEL_SOURCE_UNSPECIFIED;
}

extension ProtoArchiveTypeCppBridge on pb.ArchiveType {
  /// Convert a generated archive type enum to C++ rac_archive_type_t.
  /// Delegates to commons' `rac_archive_type_from_proto`. Returns
  /// `RAC_ARCHIVE_TYPE_NONE` (-1) on UNSPECIFIED / unrecognized inputs.
  int toC() => _invokeEnumMapper(
        'rac_archive_type_from_proto',
        value,
        -1, // RAC_ARCHIVE_TYPE_NONE
      );
}

extension ProtoArchiveStructureCppBridge on pb.ArchiveStructure {
  /// Convert a generated archive structure enum to C++
  /// rac_archive_structure_t. Delegates to commons'
  /// `rac_archive_structure_from_proto`. Falls back to
  /// `RAC_ARCHIVE_STRUCTURE_UNKNOWN` (99) on UNSPECIFIED / unrecognized.
  int toC() => _invokeEnumMapper(
        'rac_archive_structure_from_proto',
        value,
        99, // RAC_ARCHIVE_STRUCTURE_UNKNOWN
      );
}
