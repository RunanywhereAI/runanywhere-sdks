#ifndef RAC_FEATURES_LLM_THINKING_TAGS_INTERNAL_H
#define RAC_FEATURES_LLM_THINKING_TAGS_INTERNAL_H

#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#endif

namespace rac::llm {

inline bool model_thinking_tags_from_registry(const char* model_id, std::string* out_open_tag,
                                              std::string* out_close_tag) {
    if (out_open_tag) {
        out_open_tag->clear();
    }
    if (out_close_tag) {
        out_close_tag->clear();
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)model_id;
    return false;
#else
    if (model_id == nullptr || model_id[0] == '\0' || out_open_tag == nullptr ||
        out_close_tag == nullptr) {
        return false;
    }
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (registry == nullptr) {
        return false;
    }

    runanywhere::v1::ModelGetRequest request;
    request.set_model_id(model_id);
    std::string request_bytes;
    if (!request.SerializeToString(&request_bytes)) {
        return false;
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_model_registry_get_model_proto(
        registry, reinterpret_cast<const uint8_t*>(request_bytes.data()), request_bytes.size(),
        &out);
    if (rc != RAC_SUCCESS || out.data == nullptr || out.size == 0) {
        rac_proto_buffer_free(&out);
        return false;
    }

    runanywhere::v1::ModelGetResult result;
    const bool parsed = result.ParseFromArray(out.data, static_cast<int>(out.size));
    rac_proto_buffer_free(&out);
    if (!parsed || !result.found() || !result.has_model() ||
        !result.model().has_thinking_pattern()) {
        return false;
    }

    const auto& pattern = result.model().thinking_pattern();
    if (pattern.open_tag().empty() || pattern.close_tag().empty()) {
        return false;
    }
    *out_open_tag = pattern.open_tag();
    *out_close_tag = pattern.close_tag();
    return true;
#endif
}

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_THINKING_TAGS_INTERNAL_H
