// SPDX-License-Identifier: Apache-2.0
//
// dart_bridge_model_format.dart — thin proto-byte bridge for
// URL → ModelFormat / ModelArtifactType inference. Delegates to the
// commons Wave D-3 APIs (`rac_model_format_from_url_proto`,
// `rac_artifact_infer_from_url_proto`).
//
// Flutter no longer owns any URL-suffix heuristics.
library dart_bridge_model_format;

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pb.dart'
    show
        ArchiveArtifact,
        ArtifactInferFromUrlRequest,
        ArtifactInferFromUrlResult,
        ModelFormatFromUrlRequest,
        ModelFormatFromUrlResult,
        ModelInfo,
        MultiFileArtifact,
        SingleFileArtifact;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show ArchiveType, InferenceFramework, ModelArtifactType, ModelFormat;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

class DartBridgeModelFormat {
  DartBridgeModelFormat._();

  static final DartBridgeModelFormat shared = DartBridgeModelFormat._();

  static final _logger = SDKLogger('DartBridge.ModelFormat');

  /// URL → ModelFormat via commons. Returns [ModelFormat.MODEL_FORMAT_UNKNOWN]
  /// when the native proto ABI is unavailable (e.g. pre-init, unit tests).
  ModelFormat formatFromUrl(String url) {
    final fn = RacNative.bindings.rac_model_format_from_url_proto;
    if (fn == null) {
      _logger.warning(
          'rac_model_format_from_url_proto unavailable; returning UNKNOWN');
      return ModelFormat.MODEL_FORMAT_UNKNOWN;
    }
    final result = DartBridgeProtoUtils.callRequest<ModelFormatFromUrlResult>(
      request: ModelFormatFromUrlRequest(url: url),
      invoke: fn,
      decode: ModelFormatFromUrlResult.fromBuffer,
      symbol: 'rac_model_format_from_url_proto',
    );
    // Commons returns the archive-wrapper format for archive URLs; the inner
    // format (e.g. ONNX inside .tar.gz) is in result.inner_format. For the
    // "what format is this model?" question the SDK asks, the inner format is
    // the authoritative answer when non-unspecified.
    if (result.innerFormat != ModelFormat.MODEL_FORMAT_UNSPECIFIED &&
        result.innerFormat != ModelFormat.MODEL_FORMAT_UNKNOWN) {
      return result.innerFormat;
    }
    return result.format;
  }

  /// URL → ArtifactInferFromUrlResult via commons. Returns `null` when the
  /// native proto ABI is unavailable.
  ArtifactInferFromUrlResult? inferArtifact(String url,
      {String modelId = ''}) {
    final fn = RacNative.bindings.rac_artifact_infer_from_url_proto;
    if (fn == null) {
      _logger.warning(
          'rac_artifact_infer_from_url_proto unavailable; returning null');
      return null;
    }
    return DartBridgeProtoUtils.callRequest<ArtifactInferFromUrlResult>(
      request: ArtifactInferFromUrlRequest(url: url, modelId: modelId),
      invoke: fn,
      decode: ArtifactInferFromUrlResult.fromBuffer,
      symbol: 'rac_artifact_infer_from_url_proto',
    );
  }

  /// Populate the artifact-classification fields on a copy of [model] based on
  /// its `downloadUrl` via commons. Preserves caller-supplied artifact fields
  /// when already set, handles the built-in short-circuit (DIRECTORY), and
  /// falls back to [ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE] when
  /// the native ABI is unavailable. Mirrors Kotlin
  /// `CppBridgeModelFormat.applyInferredArtifact`.
  ModelInfo applyInferredArtifact(ModelInfo model, [String? url]) {
    if (model.hasArtifactType() ||
        model.hasSingleFile() ||
        model.hasArchive() ||
        model.hasMultiFile() ||
        model.hasBuiltIn() ||
        model.hasCustomStrategyId()) {
      return model;
    }

    if (_isBuiltIn(model)) {
      return model.deepCopy()
        ..artifactType = ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY
        ..builtIn = true;
    }

    final effectiveUrl = url ?? model.downloadUrl;
    if (effectiveUrl.isEmpty) return _asSingleFile(model);

    final inference = inferArtifact(effectiveUrl, modelId: model.id);
    if (inference == null) return _asSingleFile(model);

    final copy = model.deepCopy()..artifactType = inference.artifactType;
    switch (inference.artifactType) {
      case ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE:
      case ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE:
        copy.archive = ArchiveArtifact(
          type: inference.archiveType == ArchiveType.ARCHIVE_TYPE_UNSPECIFIED
              ? (inference.artifactType ==
                      ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE
                  ? ArchiveType.ARCHIVE_TYPE_TAR_GZ
                  : ArchiveType.ARCHIVE_TYPE_ZIP)
              : inference.archiveType,
          structure: inference.archiveStructure,
        );
        break;
      case ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY:
        copy.multiFile = MultiFileArtifact();
        break;
      case ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE:
      default:
        copy.singleFile = SingleFileArtifact();
    }
    return copy;
  }

  ModelInfo _asSingleFile(ModelInfo model) {
    return model.deepCopy()
      ..artifactType = ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE
      ..singleFile = SingleFileArtifact();
  }

  /// Mirrors the `ProtoModelInfoHelpers.isBuiltIn` extension in
  /// `model_types_cpp_bridge.dart` without introducing a circular import.
  static bool _isBuiltIn(ModelInfo model) {
    if (model.hasBuiltIn() && model.builtIn) return true;
    if (model.localPath.startsWith('builtin:')) return true;
    return model.framework ==
            InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
        model.framework ==
            InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS ||
        model.framework == InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN;
  }
}
