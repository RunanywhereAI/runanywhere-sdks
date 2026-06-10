/**
 * @file model_format_infer_proto.cpp
 * @brief Proto-byte C ABI for URL → ModelFormat / ArtifactType inference.
 *
 * Canonical commons-owned heuristic that replaces the per-SDK helpers:
 *   - Dart  : packages/runanywhere/lib/native/type_conversions/model_types_cpp_bridge.dart
 *             (protoModelFormatFromPath + withInferredArtifact)
 *   - Kotlin: public/extensions/RunAnywhere+ModelManagement.kt
 *             (detectFormatFromUrl + inferArtifactFields)
 *
 * Only the trailing file-suffix of the URL is inspected. No network or
 * filesystem access. This file intentionally stays free of allocations
 * outside the serialized proto result buffer.
 */

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <ranges>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

#define LOG_CAT "ModelFormatInferProto"

namespace {

#if defined(RAC_HAVE_PROTOBUF)

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return size == 0 || bytes != nullptr;
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    static const char kEmpty[] = "";
    return size == 0 ? static_cast<const void*>(kEmpty) : static_cast<const void*>(bytes);
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

// Strip any query-string / fragment from the URL so the trailing suffix
// check is not confused by "?auth=..." or "#frag".
std::string strip_url_suffix_noise(const std::string& url) {
    size_t cut = url.find_first_of("?#");
    return cut == std::string::npos ? url : url.substr(0, cut);
}

std::string to_lower(const std::string& s) {
    std::string out(s);
    std::ranges::transform(out, out.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
}

bool ends_with(const std::string& s, const char* suffix) {
    const size_t suffix_len = std::strlen(suffix);
    if (s.size() < suffix_len)
        return false;
    return s.compare(s.size() - suffix_len, suffix_len, suffix) == 0;
}

runanywhere::v1::ModelFormat format_from_suffix(const std::string& lower_url) {
    // Archives first so ".gguf.zip" → ZIP (wrapper), not GGUF.
    if (ends_with(lower_url, ".zip"))
        return runanywhere::v1::MODEL_FORMAT_ZIP;
    if (ends_with(lower_url, ".gguf"))
        return runanywhere::v1::MODEL_FORMAT_GGUF;
    if (ends_with(lower_url, ".ggml"))
        return runanywhere::v1::MODEL_FORMAT_GGML;
    if (ends_with(lower_url, ".onnx"))
        return runanywhere::v1::MODEL_FORMAT_ONNX;
    if (ends_with(lower_url, ".ort"))
        return runanywhere::v1::MODEL_FORMAT_ORT;
    if (ends_with(lower_url, ".bin"))
        return runanywhere::v1::MODEL_FORMAT_BIN;
    if (ends_with(lower_url, ".tflite"))
        return runanywhere::v1::MODEL_FORMAT_TFLITE;
    if (ends_with(lower_url, ".safetensors"))
        return runanywhere::v1::MODEL_FORMAT_SAFETENSORS;
    if (ends_with(lower_url, ".mlmodelc"))
        return runanywhere::v1::MODEL_FORMAT_COREML;
    if (ends_with(lower_url, ".mlmodel"))
        return runanywhere::v1::MODEL_FORMAT_MLMODEL;
    if (ends_with(lower_url, ".mlpackage"))
        return runanywhere::v1::MODEL_FORMAT_MLPACKAGE;
    return runanywhere::v1::MODEL_FORMAT_UNSPECIFIED;
}

struct ArchiveMatch {
    bool is_archive;
    runanywhere::v1::ArchiveType archive_type;
    runanywhere::v1::ModelArtifactType artifact_type;
};

ArchiveMatch archive_from_suffix(const std::string& lower_url) {
    using runanywhere::v1::ArchiveType;
    using runanywhere::v1::ModelArtifactType;
    if (ends_with(lower_url, ".tar.gz") || ends_with(lower_url, ".tgz")) {
        return {.is_archive = true,
                .archive_type = ArchiveType::ARCHIVE_TYPE_TAR_GZ,
                .artifact_type = ModelArtifactType::MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE};
    }
    if (ends_with(lower_url, ".tar.bz2") || ends_with(lower_url, ".tbz2")) {
        return {.is_archive = true,
                .archive_type = ArchiveType::ARCHIVE_TYPE_TAR_BZ2,
                .artifact_type = ModelArtifactType::MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE};
    }
    if (ends_with(lower_url, ".tar.xz") || ends_with(lower_url, ".txz")) {
        return {.is_archive = true,
                .archive_type = ArchiveType::ARCHIVE_TYPE_TAR_XZ,
                .artifact_type = ModelArtifactType::MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE};
    }
    if (ends_with(lower_url, ".zip")) {
        return {.is_archive = true,
                .archive_type = ArchiveType::ARCHIVE_TYPE_ZIP,
                .artifact_type = ModelArtifactType::MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE};
    }
    return {.is_archive = false,
            .archive_type = ArchiveType::ARCHIVE_TYPE_UNSPECIFIED,
            .artifact_type = ModelArtifactType::MODEL_ARTIFACT_TYPE_SINGLE_FILE};
}

// Some public catalog archives follow well-known naming patterns that let us
// infer the primary file inside. Keep this conservative — unknown archives
// simply return an empty relpath and MODEL_FORMAT_UNSPECIFIED.
runanywhere::v1::ModelFormat inner_format_from_archive_url(const std::string& lower_url) {
    // Sherpa-ONNX / Whisper public catalogs ship .tar.bz2 / .tar.gz bundles
    // containing ONNX files. The SDKs currently treat these as ONNX inner
    // archives; mirror that heuristic.
    if (lower_url.find("whisper") != std::string::npos ||
        lower_url.find("sherpa") != std::string::npos ||
        lower_url.find("zipformer") != std::string::npos ||
        lower_url.find("paraformer") != std::string::npos ||
        lower_url.find("piper") != std::string::npos ||
        lower_url.find("silero") != std::string::npos ||
        lower_url.find("onnx") != std::string::npos) {
        return runanywhere::v1::MODEL_FORMAT_ONNX;
    }
    // LlamaCPP public catalogs occasionally ship .zip bundles around .gguf
    // shards (multi-part models). Treat URLs with "gguf" anywhere in the
    // path as GGUF-containing archives.
    if (lower_url.find("gguf") != std::string::npos ||
        lower_url.find("llama") != std::string::npos) {
        return runanywhere::v1::MODEL_FORMAT_GGUF;
    }
    return runanywhere::v1::MODEL_FORMAT_UNSPECIFIED;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

extern "C" rac_result_t rac_model_format_from_url_proto(const uint8_t* request_bytes,
                                                        size_t request_size,
                                                        rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!valid_bytes(request_bytes, request_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "ModelFormatFromUrlRequest bytes are invalid");
    }

    runanywhere::v1::ModelFormatFromUrlRequest request;
    if (request_size > 0 && !request.ParseFromArray(parse_data(request_bytes, request_size),
                                                    static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse ModelFormatFromUrlRequest");
    }

    runanywhere::v1::ModelFormatFromUrlResult result;
    result.set_format(runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
    result.set_inner_format(runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);

    const std::string lower_url = to_lower(strip_url_suffix_noise(request.url()));
    if (!lower_url.empty()) {
        const ArchiveMatch archive = archive_from_suffix(lower_url);
        if (archive.is_archive) {
            // For archive suffixes, the primary "format" field reports the
            // archive wrapper (e.g. ZIP for .zip) while inner_format carries
            // the inferred payload format when we can guess it from the URL.
            if (archive.archive_type == runanywhere::v1::ArchiveType::ARCHIVE_TYPE_ZIP) {
                result.set_format(runanywhere::v1::MODEL_FORMAT_ZIP);
            } else {
                result.set_format(runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);
            }
            result.set_inner_format(inner_format_from_archive_url(lower_url));
        } else {
            result.set_format(format_from_suffix(lower_url));
        }
    }

    RAC_LOG_DEBUG(LOG_CAT, "format_from_url: url=%s format=%d inner=%d", request.url().c_str(),
                  static_cast<int>(result.format()), static_cast<int>(result.inner_format()));
    return copy_proto(result, out_result);
#endif
}

extern "C" rac_result_t rac_artifact_infer_from_url_proto(const uint8_t* request_bytes,
                                                          size_t request_size,
                                                          rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!valid_bytes(request_bytes, request_size)) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "ArtifactInferFromUrlRequest bytes are invalid");
    }

    runanywhere::v1::ArtifactInferFromUrlRequest request;
    if (request_size > 0 && !request.ParseFromArray(parse_data(request_bytes, request_size),
                                                    static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse ArtifactInferFromUrlRequest");
    }

    runanywhere::v1::ArtifactInferFromUrlResult result;
    result.set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    result.set_archive_type(runanywhere::v1::ARCHIVE_TYPE_UNSPECIFIED);
    result.set_archive_structure(runanywhere::v1::ARCHIVE_STRUCTURE_UNSPECIFIED);
    result.set_inner_format(runanywhere::v1::MODEL_FORMAT_UNSPECIFIED);

    const std::string lower_url = to_lower(strip_url_suffix_noise(request.url()));
    if (lower_url.empty()) {
        // No URL → SINGLE_FILE default, empty relpath.
        return copy_proto(result, out_result);
    }

    const ArchiveMatch archive = archive_from_suffix(lower_url);
    if (archive.is_archive) {
        result.set_artifact_type(archive.artifact_type);
        result.set_archive_type(archive.archive_type);
        result.set_archive_structure(runanywhere::v1::ARCHIVE_STRUCTURE_UNKNOWN);
        result.set_inner_format(inner_format_from_archive_url(lower_url));
    } else {
        result.set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_SINGLE_FILE);
    }

    RAC_LOG_DEBUG(LOG_CAT, "artifact_from_url: model_id=%s url=%s artifact=%d archive=%d inner=%d",
                  request.model_id().c_str(), request.url().c_str(),
                  static_cast<int>(result.artifact_type()), static_cast<int>(result.archive_type()),
                  static_cast<int>(result.inner_format()));
    return copy_proto(result, out_result);
#endif
}
