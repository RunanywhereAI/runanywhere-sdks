/**
 * @file register_model_from_url.cpp
 * @brief Canonical "register a model from a URL" entry point.
 *
 * Composes rac_model_info_make_proto with the existing registry
 * persistence path (rac_model_registry_register_proto_buffer) so SDKs replace
 * ~60 LOC of build-and-save glue (Swift's RunAnywhere.registerModel,
 * Kotlin/Flutter/RN/Web equivalents) with a single ABI call.
 *
 * Lives in a NEW source file (rather than appending to model_registry.cpp) to
 * stay merge-safe while concurrent agents edit model_registry.cpp.
 *
 * Field semantics — all defaulting and inference is delegated to
 * rac_model_info_make_proto. We only translate the inbound
 * RegisterModelFromUrlRequest → ModelInfoMakeRequest (1:1 field mapping) and
 * then forward to the registry register_proto_buffer save path on the global
 * registry handle.
 *
 * Re-registration semantics: when a model_id already exists in the registry,
 * rac_model_registry_register_proto preserves runtime fields the caller did
 * not set (local_path, is_downloaded, checksum_sha256, expected_files,
 * multi_file per-file local_path). Callers reseeding a curated catalog on app
 * launch therefore retain previous download progress; no example-app
 * workaround is needed to skip already-known IDs.
 */

#include "bundle_policy_registry_internal.h"
#include "hf_resolver.h"

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_bundle_policy.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#endif

#define LOG_CAT "RegisterModelFromUrl"

namespace {

#if defined(RAC_HAVE_PROTOBUF)

bool valid_bytes(const uint8_t* bytes, size_t size) {
    return size == 0 || bytes != nullptr;
}

// Forward declaration — shared by the multi-file ABI entry point and the
// Hugging Face repo-resolution branch of the from-url entry point.
rac_result_t
register_multi_file_model(const runanywhere::v1::RegisterMultiFileModelRequest& request,
                          rac_proto_buffer_t* out_proto);

// Resolve a repo-level Hugging Face ref into a multi-file registration:
// tree listing -> quant selection (+ mmproj pairing, shard expansion) ->
// RegisterMultiFileModelRequest with per-file sizes + SHA-256 checksums.
// Caller-supplied metadata fields on @p request win over derived ones.
rac_result_t register_from_hf_repo(const runanywhere::v1::RegisterModelFromUrlRequest& request,
                                   rac_proto_buffer_t* out_proto) {
    namespace hf = rac::infra::model_management::hf;

    hf::ResolvedModel resolved;
    std::string error;
    const rac_result_t resolve_rc = hf::resolve_repo(request.url(), &resolved, &error);
    if (resolve_rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_proto, resolve_rc, error.c_str());
    }

    runanywhere::v1::RegisterMultiFileModelRequest multi_file;
    multi_file.set_id(request.id().empty() ? resolved.model_id : request.id());
    multi_file.set_name(request.name().empty() ? resolved.display_name : request.name());
    multi_file.set_framework(request.has_framework()
                                 ? request.framework()
                                 : runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP);
    multi_file.set_format(runanywhere::v1::MODEL_FORMAT_GGUF);
    multi_file.set_category(request.has_category()
                                ? request.category()
                                : (resolved.has_vision_projector
                                       ? runanywhere::v1::MODEL_CATEGORY_MULTIMODAL
                                       : runanywhere::v1::MODEL_CATEGORY_LANGUAGE));
    if (request.has_source()) {
        multi_file.set_source(request.source());
    }
    multi_file.set_download_size_bytes(request.has_download_size_bytes()
                                           ? request.download_size_bytes()
                                           : resolved.total_size_bytes);
    if (request.has_memory_required_bytes()) {
        multi_file.set_memory_required_bytes(request.memory_required_bytes());
    }
    if (request.has_context_length()) {
        multi_file.set_context_length(request.context_length());
    }
    if (request.has_supports_thinking()) {
        multi_file.set_supports_thinking(request.supports_thinking());
    }
    if (request.has_supports_lora()) {
        multi_file.set_supports_lora(request.supports_lora());
    }
    if (request.has_description()) {
        multi_file.set_description(request.description());
    }

    bool first = true;
    for (const hf::ResolvedFile& resolved_file : resolved.files) {
        runanywhere::v1::ModelFileDescriptor* file = multi_file.add_files();
        file->set_url(resolved_file.url);
        file->set_filename(resolved_file.filename);
        file->set_is_required(true);
        if (resolved_file.size_bytes > 0) {
            file->set_size_bytes(resolved_file.size_bytes);
        }
        if (!resolved_file.sha256.empty()) {
            file->set_checksum_sha256(resolved_file.sha256);
        }
        if (resolved_file.is_vision_projector) {
            file->set_role(runanywhere::v1::MODEL_FILE_ROLE_VISION_PROJECTOR);
        } else if (first) {
            file->set_role(runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL);
            first = false;
        } else {
            // Additional shards of a split GGUF set.
            file->set_role(runanywhere::v1::MODEL_FILE_ROLE_COMPANION);
        }
    }

    RAC_LOG_INFO(LOG_CAT, "Registering Hugging Face model '%s' (%d files)", multi_file.id().c_str(),
                 multi_file.files_size());
    return register_multi_file_model(multi_file, out_proto);
}

// Looks up the registered bundle policy for an already-derived framework.
// RAC_FRAMEWORK_UNKNOWN covers missing/invalid request framework values.
const rac_bundle_policy_t* bundle_policy_for(rac_inference_framework_t framework) {
    if (framework == RAC_FRAMEWORK_UNKNOWN) {
        return nullptr;
    }
    return rac::infra::bundle_policy::find(framework);
}

// Convert the optional proto framework once so downstream helpers can stay on
// the structured C enum instead of re-parsing the request.
rac_inference_framework_t
framework_for(const runanywhere::v1::RegisterModelFromUrlRequest& request) {
    if (!request.has_framework()) {
        return RAC_FRAMEWORK_UNKNOWN;
    }
    rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
    if (rac_inference_framework_from_proto(static_cast<int32_t>(request.framework()), &framework) !=
        RAC_SUCCESS) {
        return RAC_FRAMEWORK_UNKNOWN;
    }
    return framework;
}

const char* manifest_leaf_ext_for(const rac_bundle_policy_t* policy) {
    return (policy != nullptr && policy->manifest_leaf_names_bundle == RAC_TRUE)
               ? policy->manifest_extension
               : nullptr;
}

// Let an engine-owned policy select a device/runtime-specific folder while
// commons remains responsible only for validating and inserting the returned
// path segment. Policies without a resolver keep the existing folder behavior.
rac_result_t maybe_resolve_logical_bundle_ref(const rac_bundle_policy_t* policy,
                                              runanywhere::v1::RegisterModelFromUrlRequest* request,
                                              rac_proto_buffer_t* out_proto) {
    if (policy == nullptr || policy->resolve_variant == nullptr || request == nullptr) {
        return RAC_SUCCESS;
    }

    namespace hf = rac::infra::model_management::hf;
    const char* manifest_leaf_ext = manifest_leaf_ext_for(policy);
    if (!hf::is_logical_variant_folder_ref(request->url(), manifest_leaf_ext)) {
        return RAC_SUCCESS;
    }

    char variant[64] = {};
    char error_message[256] = {};
    const rac_result_t resolve_rc =
        policy->resolve_variant(variant, sizeof(variant), error_message, sizeof(error_message));
    if (resolve_rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(
            out_proto, resolve_rc,
            error_message[0] != '\0' ? error_message : "bundle variant resolution failed");
    }

    std::string resolved_ref;
    if (!hf::make_variant_folder_ref(request->url(), variant, manifest_leaf_ext, &resolved_ref)) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_INVALID_ARGUMENT,
                                          "bundle policy returned an invalid variant folder");
    }

    RAC_LOG_INFO(LOG_CAT, "Resolved logical bundle with engine variant %s", variant);
    request->set_url(resolved_ref);
    return RAC_SUCCESS;
}

// Resolve a folder-level Hugging Face ref (hf.co/org/repo/<subdir>, or a
// manifest-leaf ref when the framework's bundle policy allows it) into a
// multi-file registration carrying EVERY file under the subfolder — the
// self-describing bundle path for directory-based engines, mirroring how
// archive registrations stay one-liners. Fully framework-agnostic: which file
// is the manifest and what format to stamp come from the engine-registered
// bundle policy; caller-supplied metadata wins.
rac_result_t register_from_hf_folder(const runanywhere::v1::RegisterModelFromUrlRequest& request,
                                     const rac_bundle_policy_t* policy,
                                     rac_proto_buffer_t* out_proto) {
    namespace hf = rac::infra::model_management::hf;

    hf::ResolvedModel resolved;
    std::string error;
    const rac_result_t resolve_rc = hf::resolve_repo_folder(
        request.url(), manifest_leaf_ext_for(policy),
        policy != nullptr ? policy->is_bundle_manifest : nullptr, &resolved, &error);
    if (resolve_rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_proto, resolve_rc, error.c_str());
    }

    runanywhere::v1::RegisterMultiFileModelRequest multi_file;
    multi_file.set_id(request.id().empty() ? resolved.model_id : request.id());
    multi_file.set_name(request.name().empty() ? resolved.display_name : request.name());
    if (request.has_framework()) {
        multi_file.set_framework(request.framework());
    }
    const rac_inference_framework_t framework = framework_for(request);
    if (policy != nullptr && policy->model_format != RAC_MODEL_FORMAT_UNSPECIFIED) {
        int32_t proto_format = 0;
        if (rac_model_format_to_proto(policy->model_format, &proto_format) == RAC_SUCCESS) {
            multi_file.set_format(static_cast<runanywhere::v1::ModelFormat>(proto_format));
        }
    }
    if (request.has_category()) {
        multi_file.set_category(request.category());
    } else if (framework == RAC_FRAMEWORK_MLX) {
        multi_file.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
    }
    if (request.has_source()) {
        multi_file.set_source(request.source());
    }
    // Prefer the resolver's live folder total over the caller's
    // download_size_bytes. The caller value is frequently a stale catalog
    // estimate copied from an older revision of the repo, whereas
    // resolved.total_size_bytes is summed from the tree listing we just
    // fetched. A stale (usually too-small) size under-reports the download and
    // can slip past the pre-flight storage gate; the fresh total is the ground
    // truth. Fall back to the caller's value only when the resolver could not
    // determine a total (e.g. the tree listing carried no per-file sizes).
    if (resolved.total_size_bytes > 0) {
        multi_file.set_download_size_bytes(resolved.total_size_bytes);
    } else if (request.has_download_size_bytes()) {
        multi_file.set_download_size_bytes(request.download_size_bytes());
    }
    if (request.has_memory_required_bytes()) {
        multi_file.set_memory_required_bytes(request.memory_required_bytes());
    }
    if (request.has_context_length()) {
        multi_file.set_context_length(request.context_length());
    }
    if (request.has_supports_thinking()) {
        multi_file.set_supports_thinking(request.supports_thinking());
    }
    if (request.has_supports_lora()) {
        multi_file.set_supports_lora(request.supports_lora());
    }
    if (request.has_description()) {
        multi_file.set_description(request.description());
    }

    bool first = true;
    for (const hf::ResolvedFile& resolved_file : resolved.files) {
        runanywhere::v1::ModelFileDescriptor* file = multi_file.add_files();
        file->set_url(resolved_file.url);
        file->set_filename(resolved_file.filename);
        file->set_is_required(true);
        if (resolved_file.size_bytes > 0) {
            file->set_size_bytes(resolved_file.size_bytes);
        }
        if (!resolved_file.sha256.empty()) {
            file->set_checksum_sha256(resolved_file.sha256);
        }
        file->set_role(first ? runanywhere::v1::MODEL_FILE_ROLE_PRIMARY_MODEL
                             : runanywhere::v1::MODEL_FILE_ROLE_COMPANION);
        first = false;
    }

    RAC_LOG_INFO(LOG_CAT, "Registering Hugging Face folder bundle '%s' (%d files)",
                 multi_file.id().c_str(), multi_file.files_size());
    return register_multi_file_model(multi_file, out_proto);
}

// Copy a MakeRequest field (RegisterModelFromUrlRequest is wire-compatible with
// ModelInfoMakeRequest by design — same field tags, same types — but we
// translate explicitly so the proto layer is decoupled and either schema can
// evolve independently).
void translate_to_make_request(const runanywhere::v1::RegisterModelFromUrlRequest& in,
                               runanywhere::v1::ModelInfoMakeRequest* out) {
    out->set_url(in.url());
    out->set_name(in.name());
    if (in.has_framework()) {
        out->set_framework(in.framework());
    }
    if (in.has_category()) {
        out->set_category(in.category());
    }
    if (in.has_source()) {
        out->set_source(in.source());
    }
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" rac_result_t rac_register_model_from_url_proto(const uint8_t* in_request_bytes,
                                                          size_t in_size,
                                                          rac_proto_buffer_t* out_proto) {
    if (!out_proto) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_request_bytes;
    (void)in_size;
    return rac_proto_buffer_set_error(out_proto, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!valid_bytes(in_request_bytes, in_size)) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_DECODING_ERROR,
                                          "RegisterModelFromUrlRequest bytes are invalid");
    }

    runanywhere::v1::RegisterModelFromUrlRequest request;
    if (in_size > 0 && !request.ParseFromArray(in_request_bytes, static_cast<int>(in_size))) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse RegisterModelFromUrlRequest");
    }

    // The url drives every derived field (id, name, format, artifact). An empty
    // url yields a model keyed by the empty-string id, which pollutes the
    // registry and breaks subsequent get(id) lookups. Reject it up front —
    // mirrors the non-empty-url precondition the SDK download path relies on.
    if (request.url().empty()) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_INVALID_ARGUMENT,
                                          "RegisterModelFromUrlRequest.url must not be empty");
    }

    // -------------------------------------------------------------------------
    // 0) Hugging Face references (hf.co/org/repo[:quant], hf://..., explicit
    //    in-repo file paths). Explicit-file refs normalize to a direct
    //    /resolve/ URL and continue through the standard single-file path;
    //    repo-level refs resolve to a multi-file registration (quant
    //    selection, mmproj pairing, shard expansion, checksums).
    // -------------------------------------------------------------------------
    {
        namespace hf = rac::infra::model_management::hf;
        if (hf::is_hf_ref(request.url())) {
            // Folder bundles: in-repo folder refs (no extension) for any
            // framework, plus manifest-leaf refs when the framework's
            // engine-registered bundle policy allows them. All framework
            // specifics live in the policy — none here.
            const rac_inference_framework_t framework = framework_for(request);
            const rac_bundle_policy_t* policy = bundle_policy_for(framework);
            const rac_result_t variant_rc =
                maybe_resolve_logical_bundle_ref(policy, &request, out_proto);
            if (variant_rc != RAC_SUCCESS) {
                return variant_rc;
            }
            const char* manifest_leaf_ext = manifest_leaf_ext_for(policy);
            if (hf::is_folder_ref(request.url(), manifest_leaf_ext)) {
                return register_from_hf_folder(request, policy, out_proto);
            }
            const std::string direct_url = hf::normalize_explicit_file_ref(request.url());
            if (!direct_url.empty()) {
                request.set_url(direct_url);
            } else if (policy != nullptr) {
                return register_from_hf_folder(request, policy, out_proto);
            } else {
                return register_from_hf_repo(request, out_proto);
            }
        }
    }

    // -------------------------------------------------------------------------
    // 1) Build a ModelInfo via the canonical factory.
    // -------------------------------------------------------------------------
    runanywhere::v1::ModelInfoMakeRequest make_request;
    translate_to_make_request(request, &make_request);

    std::vector<uint8_t> make_request_bytes;
    {
        const size_t mr_size = make_request.ByteSizeLong();
        make_request_bytes.resize(mr_size);
        if (mr_size > 0 &&
            !make_request.SerializeToArray(make_request_bytes.data(),
                                           static_cast<int>(make_request_bytes.size()))) {
            return rac_proto_buffer_set_error(out_proto, RAC_ERROR_ENCODING_ERROR,
                                              "failed to serialize ModelInfoMakeRequest");
        }
    }

    rac_proto_buffer_t make_buffer;
    rac_proto_buffer_init(&make_buffer);
    rac_result_t make_rc =
        rac_model_info_make_proto(make_request_bytes.empty() ? nullptr : make_request_bytes.data(),
                                  make_request_bytes.size(), &make_buffer);
    if (make_rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&make_buffer);
        return rac_proto_buffer_set_error(out_proto, make_rc, "rac_model_info_make_proto failed");
    }
    if (make_buffer.status != RAC_SUCCESS) {
        const rac_result_t status = make_buffer.status;
        const std::string msg =
            make_buffer.error_message ? make_buffer.error_message : "make() failed";
        rac_proto_buffer_free(&make_buffer);
        return rac_proto_buffer_set_error(out_proto, status, msg.c_str());
    }

    runanywhere::v1::ModelInfo made_model;
    if (!made_model.ParseFromArray(make_buffer.data, static_cast<int>(make_buffer.size))) {
        rac_proto_buffer_free(&make_buffer);
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse ModelInfo produced by make()");
    }
    rac_proto_buffer_free(&make_buffer);

    // -------------------------------------------------------------------------
    // 1a) Overlay caller-supplied capability fields onto the made ModelInfo.
    //     rac_model_info_make_proto infers these from the URL/name and stamps
    //     conservative defaults (supports_lora=false, download_size=0). When the
    //     caller supplied an explicit value we honor it, so SDKs no longer need
    //     a post-register "patch + resave" pass. Done BEFORE the id-keyed
    //     merge below so an explicit id override is respected.
    // -------------------------------------------------------------------------
    if (!request.id().empty()) {
        made_model.set_id(request.id());
    }
    if (request.has_memory_required_bytes()) {
        made_model.set_memory_required_bytes(request.memory_required_bytes());
    }
    if (request.has_supports_thinking()) {
        made_model.set_supports_thinking(request.supports_thinking());
    }
    if (request.has_supports_lora()) {
        made_model.set_supports_lora(request.supports_lora());
    }
    if (request.has_artifact_type()) {
        made_model.set_artifact_type(request.artifact_type());
    }
    if (request.has_context_length()) {
        made_model.set_context_length(request.context_length());
    }
    if (request.has_description()) {
        made_model.mutable_metadata()->set_description(request.description());
    }
    if (request.has_download_size_bytes()) {
        made_model.set_download_size_bytes(request.download_size_bytes());
    }

    // -------------------------------------------------------------------------
    // 2) Persist via the existing registry save path.
    //    rac_model_registry_register_proto_buffer accepts serialized ModelInfo
    //    bytes and returns the saved (normalized) ModelInfo bytes — exactly
    //    the shape we want to forward to the caller.
    // -------------------------------------------------------------------------
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_NOT_INITIALIZED,
                                          "global model registry is not available");
    }

    // 1b) Merge-not-replace on re-seed. rac_model_info_make_proto always stamps
    //     the factory defaults local_path="", is_downloaded=false,
    //     is_available=false and carries no checksum (this entry point never
    //     receives a localPath or download state from the caller). Registering
    //     a curated catalog on every app launch must NOT clobber the download
    //     progress a prior launch recorded, so when the model_id already exists
    //     we carry its runtime fields forward onto the freshly-made ModelInfo
    //     before saving. A genuine first registration finds no existing entry
    //     and normalises to the not-downloaded defaults. Callers that need an
    //     explicit reset use the lower-level rac_model_registry_register_proto
    //     path with the fields populated.
    {
        uint8_t* existing_bytes = nullptr;
        size_t existing_size = 0;
        if (rac_model_registry_get_proto(registry, made_model.id().c_str(), &existing_bytes,
                                         &existing_size) == RAC_SUCCESS) {
            runanywhere::v1::ModelInfo existing;
            if (existing.ParseFromArray(existing_bytes, static_cast<int>(existing_size))) {
                if (!existing.local_path().empty()) {
                    made_model.set_local_path(existing.local_path());
                }
                if (existing.has_is_downloaded()) {
                    made_model.set_is_downloaded(existing.is_downloaded());
                }
                if (existing.has_is_available()) {
                    made_model.set_is_available(existing.is_available());
                }
                if (existing.has_checksum_sha256()) {
                    made_model.set_checksum_sha256(existing.checksum_sha256());
                }
                if (existing.has_registry_status()) {
                    made_model.set_registry_status(existing.registry_status());
                }
            }
            rac_model_registry_proto_free(existing_bytes);
        }
    }

    std::string merged_bytes;
    if (!made_model.SerializeToString(&merged_bytes)) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_ENCODING_ERROR,
                                          "failed to re-serialize ModelInfo for registration");
    }

    rac_result_t save_rc = rac_model_registry_register_proto_buffer(
        registry, reinterpret_cast<const uint8_t*>(merged_bytes.data()), merged_bytes.size(),
        out_proto);

    if (save_rc != RAC_SUCCESS) {
        // out_proto already carries the canonical error envelope from the
        // register_proto_buffer call.
        return save_rc;
    }
    if (out_proto->status != RAC_SUCCESS) {
        return out_proto->status;
    }

    RAC_LOG_DEBUG(LOG_CAT, "registered model from url=%s (saved %zu bytes)", request.url().c_str(),
                  out_proto->size);
    return RAC_SUCCESS;
#endif
}

extern "C" rac_result_t rac_register_multi_file_model_proto(const uint8_t* in_request_bytes,
                                                            size_t in_size,
                                                            rac_proto_buffer_t* out_proto) {
    if (!out_proto) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_request_bytes;
    (void)in_size;
    return rac_proto_buffer_set_error(out_proto, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!valid_bytes(in_request_bytes, in_size)) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_DECODING_ERROR,
                                          "RegisterMultiFileModelRequest bytes are invalid");
    }

    runanywhere::v1::RegisterMultiFileModelRequest request;
    if (in_size > 0 && !request.ParseFromArray(in_request_bytes, static_cast<int>(in_size))) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse RegisterMultiFileModelRequest");
    }
    return register_multi_file_model(request, out_proto);
#endif
}

#if defined(RAC_HAVE_PROTOBUF)

namespace {

rac_result_t
register_multi_file_model(const runanywhere::v1::RegisterMultiFileModelRequest& request,
                          rac_proto_buffer_t* out_proto) {
    if (request.id().empty()) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_INVALID_ARGUMENT,
                                          "RegisterMultiFileModelRequest.id must not be empty");
    }
    if (request.files().empty()) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_INVALID_ARGUMENT,
                                          "RegisterMultiFileModelRequest.files must not be empty");
    }

    // Build the ModelInfo with a MultiFileArtifact directly — the file URLs make
    // the make()/inference path inapplicable.
    runanywhere::v1::ModelInfo model;
    model.set_id(request.id());
    model.set_name(request.name());
    model.set_framework(request.framework());
    if (request.has_category()) {
        model.set_category(request.category());
    }
    if (request.has_format()) {
        model.set_format(request.format());
    }
    if (request.has_source()) {
        model.set_source(request.source());
    }
    if (request.has_memory_required_bytes()) {
        model.set_memory_required_bytes(request.memory_required_bytes());
    }
    if (request.has_download_size_bytes()) {
        model.set_download_size_bytes(request.download_size_bytes());
    }
    if (request.has_context_length()) {
        model.set_context_length(request.context_length());
    }
    if (request.has_supports_thinking()) {
        model.set_supports_thinking(request.supports_thinking());
    }
    if (request.has_supports_lora()) {
        model.set_supports_lora(request.supports_lora());
    }
    if (request.has_description()) {
        model.mutable_metadata()->set_description(request.description());
    }
    *model.mutable_multi_file()->mutable_files() = request.files();
    model.set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_MULTI_FILE);

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_NOT_INITIALIZED,
                                          "global model registry is not available");
    }

    // Merge-not-replace on re-seed: carry an existing entry's runtime download
    // state forward so re-registering a curated catalog on launch doesn't
    // clobber recorded progress (mirrors the from-url path above).
    {
        uint8_t* existing_bytes = nullptr;
        size_t existing_size = 0;
        if (rac_model_registry_get_proto(registry, model.id().c_str(), &existing_bytes,
                                         &existing_size) == RAC_SUCCESS) {
            runanywhere::v1::ModelInfo existing;
            if (existing.ParseFromArray(existing_bytes, static_cast<int>(existing_size))) {
                if (!existing.local_path().empty()) {
                    model.set_local_path(existing.local_path());
                }
                if (existing.has_is_downloaded()) {
                    model.set_is_downloaded(existing.is_downloaded());
                }
                if (existing.has_is_available()) {
                    model.set_is_available(existing.is_available());
                }
                if (existing.has_checksum_sha256()) {
                    model.set_checksum_sha256(existing.checksum_sha256());
                }
                if (existing.has_registry_status()) {
                    model.set_registry_status(existing.registry_status());
                }
            }
            rac_model_registry_proto_free(existing_bytes);
        }
    }

    std::string model_bytes;
    if (!model.SerializeToString(&model_bytes)) {
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize multi-file ModelInfo");
    }

    rac_result_t save_rc = rac_model_registry_register_proto_buffer(
        registry, reinterpret_cast<const uint8_t*>(model_bytes.data()), model_bytes.size(),
        out_proto);
    if (save_rc != RAC_SUCCESS) {
        return save_rc;
    }
    if (out_proto->status != RAC_SUCCESS) {
        return out_proto->status;
    }

    RAC_LOG_DEBUG(LOG_CAT, "registered multi-file model id=%s (%d files, saved %zu bytes)",
                  request.id().c_str(), request.files_size(), out_proto->size);
    return RAC_SUCCESS;
}

}  // namespace

#endif  // RAC_HAVE_PROTOBUF
