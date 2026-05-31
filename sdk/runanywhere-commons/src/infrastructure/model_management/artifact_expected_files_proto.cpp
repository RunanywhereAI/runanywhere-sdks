/**
 * @file artifact_expected_files_proto.cpp
 * @brief Canonical ExpectedModelFiles helper.
 *
 * Commons-owned port of Swift's RAModelInfo.expectedArtifactFiles and the
 * underlying RAModelInfo.OneOf_Artifact.expectedFiles computed property
 * (sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/Models/
 * ModelTypes+Artifacts.swift). Every field-set in this file mirrors the
 * Swift implementation 1:1 so the Swift extension can be deleted.
 *
 * Lives in a NEW source file (rather than appending to model_types.cpp or
 * model_registry.cpp) to stay merge-safe while concurrent agents edit
 * model_registry.cpp / download_orchestrator.cpp.
 *
 * Resolution order (Swift parity):
 *   1. Top-level model.expected_files when present.
 *   2. SINGLE_FILE  → artifact.expected_files OR patterns shorthand.
 *   3. ARCHIVE      → artifact.expected_files OR patterns shorthand.
 *   4. MULTI_FILE   → synthesise files-only manifest from descriptors.
 *   5. otherwise    → empty manifest (Swift's `.none` fallback).
 */

#include <cstdint>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#endif

#define LOG_CAT "ArtifactExpectedFilesProto"

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
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    const size_t size = message.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize ExpectedModelFiles result");
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

// Synthesise an ExpectedModelFiles whose required/optional_patterns mirror the
// inbound shorthand. Mirrors Swift's `RAExpectedModelFiles.patterns(...)` in
// ModelTypes+Artifacts.swift.
void copy_patterns_into(const google::protobuf::RepeatedPtrField<std::string>& required,
                        const google::protobuf::RepeatedPtrField<std::string>& optional,
                        runanywhere::v1::ExpectedModelFiles* out) {
    out->mutable_required_patterns()->CopyFrom(required);
    out->mutable_optional_patterns()->CopyFrom(optional);
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" rac_result_t rac_artifact_expected_files_proto(const uint8_t* in_model_bytes,
                                                          size_t in_model_size,
                                                          rac_proto_buffer_t* out_proto) {
    if (!out_proto) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_model_bytes;
    (void)in_model_size;
    return rac_proto_buffer_set_error(out_proto, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!valid_bytes(in_model_bytes, in_model_size)) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_DECODING_ERROR,
                                          "ModelInfo bytes are invalid");
    }

    runanywhere::v1::ModelInfo model;
    if (in_model_size > 0 && !model.ParseFromArray(parse_data(in_model_bytes, in_model_size),
                                                   static_cast<int>(in_model_size))) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse ModelInfo");
    }

    // -------------------------------------------------------------------------
    // Step 1: top-level model.expected_files short-circuit (Swift's
    // `if hasExpectedFiles { return expectedFiles }` in
    // RAModelInfo.expectedArtifactFiles).
    // -------------------------------------------------------------------------
    if (model.has_expected_files()) {
        return copy_proto(model.expected_files(), out_proto);
    }

    // -------------------------------------------------------------------------
    // Step 2: walk the artifact oneof. Mirrors Swift's
    // OneOf_Artifact.expectedFiles switch.
    // -------------------------------------------------------------------------
    runanywhere::v1::ExpectedModelFiles result;

    switch (model.artifact_case()) {
        case runanywhere::v1::ModelInfo::kSingleFile: {
            const runanywhere::v1::SingleFileArtifact& art = model.single_file();
            if (art.has_expected_files()) {
                return copy_proto(art.expected_files(), out_proto);
            }
            // Fallback: pattern shorthand → manifest.
            copy_patterns_into(art.required_patterns(), art.optional_patterns(), &result);
            break;
        }
        case runanywhere::v1::ModelInfo::kArchive: {
            const runanywhere::v1::ArchiveArtifact& art = model.archive();
            if (art.has_expected_files()) {
                return copy_proto(art.expected_files(), out_proto);
            }
            copy_patterns_into(art.required_patterns(), art.optional_patterns(), &result);
            break;
        }
        case runanywhere::v1::ModelInfo::kMultiFile: {
            // Swift parity: when the artifact is multi_file, seed the manifest
            // by copying the descriptor list into expected_files.files. The
            // commons download planner only walks `model.expected_files.files`
            // for per-descriptor downloads, so this seeding is what makes the
            // per-file loop fire (LLM + mmproj + tokenizer + ...).
            const runanywhere::v1::MultiFileArtifact& art = model.multi_file();
            if (art.files_size() > 0) {
                result.mutable_files()->CopyFrom(art.files());
            }
            break;
        }
        default:
            // custom_strategy_id, built_in, or no artifact set. Empty manifest
            // — matches Swift's `default: return .none`.
            break;
    }

    RAC_LOG_DEBUG(LOG_CAT, "expected_files: model_id=%s case=%d files=%d req=%d opt=%d",
                  model.id().c_str(), static_cast<int>(model.artifact_case()), result.files_size(),
                  result.required_patterns_size(), result.optional_patterns_size());

    return copy_proto(result, out_proto);
#endif
}
