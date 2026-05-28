/**
 * @file register_model_from_url.cpp
 * @brief Canonical "register a model from a URL" entry point (P2-T6).
 *
 * Composes rac_model_info_make_proto (P2-T4) with the existing registry
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

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
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

    // -------------------------------------------------------------------------
    // 1) Build a ModelInfo via the canonical factory (P2-T4).
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

    // -------------------------------------------------------------------------
    // 2) Persist via the existing registry save path.
    //    rac_model_registry_register_proto_buffer accepts serialized ModelInfo
    //    bytes and returns the saved (normalized) ModelInfo bytes — exactly
    //    the shape we want to forward to the caller.
    // -------------------------------------------------------------------------
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        rac_proto_buffer_free(&make_buffer);
        return rac_proto_buffer_set_error(out_proto, RAC_ERROR_NOT_INITIALIZED,
                                          "global model registry is not available");
    }

    rac_result_t save_rc = rac_model_registry_register_proto_buffer(registry, make_buffer.data,
                                                                    make_buffer.size, out_proto);
    rac_proto_buffer_free(&make_buffer);

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
