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
    show ArchiveType, ModelArtifactType, ModelFormat;
import 'package:runanywhere/native/dart_bridge_proto_utils.dart';

class DartBridgeModelFormat {
  DartBridgeModelFormat._();

  static final DartBridgeModelFormat shared = DartBridgeModelFormat._();

  /// URL → ModelFormat via commons.
  ModelFormat formatFromUrl(String url) {
    final fn = RacNative.bindings.rac_model_format_from_url_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_model_format_from_url_proto is unavailable');
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

  /// URL → ArtifactInferFromUrlResult via commons.
  ArtifactInferFromUrlResult inferArtifact(String url, {String modelId = ''}) {
    final fn = RacNative.bindings.rac_artifact_infer_from_url_proto;
    if (fn == null) {
      throw UnsupportedError(
          'rac_artifact_infer_from_url_proto is unavailable');
    }
    return DartBridgeProtoUtils.callRequest<ArtifactInferFromUrlResult>(
      request: ArtifactInferFromUrlRequest(url: url, modelId: modelId),
      invoke: fn,
      decode: ArtifactInferFromUrlResult.fromBuffer,
      symbol: 'rac_artifact_infer_from_url_proto',
    );
  }

  /// Apply the commons-inferred artifact fields onto a copy of [model].
  ModelInfo applyInferredArtifact(ModelInfo model, String url) {
    if (url.isEmpty) return _asSingleFile(model);
    final inference = inferArtifact(url, modelId: model.id);
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
}
