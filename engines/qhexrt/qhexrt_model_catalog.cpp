/**
 * @file qhexrt_model_catalog.cpp
 * @brief QHexRT-owned chip selection and catalog registration facade.
 */

#include "qhexrt_bundle_policy.h"
#include "qhexrt_model_catalog_internal.h"

#include <algorithm>
#include <cctype>
#include <string>
#include <string_view>
#include <vector>

#include "rac/infrastructure/model_management/rac_bundle_policy.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/qhexrt/rac_qhexrt.h"

#if defined(RAC_QHEXRT_HAVE_PROTOBUF)
#include "model_types.pb.h"
#endif

namespace {

#if defined(RAC_QHEXRT_HAVE_PROTOBUF)

rac_result_t definition_error(rac_proto_buffer_t* out_model, const char* message) {
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_INVALID_ARGUMENT, message);
}

bool valid_supported_arches(const rac_qhexrt_hexagon_arch_t* supported_arches,
                            size_t supported_arch_count) {
    if (supported_arches == nullptr || supported_arch_count == 0) {
        return false;
    }
    for (size_t index = 0; index < supported_arch_count; ++index) {
        if (rac_qhexrt_arch_is_supported(supported_arches[index]) != RAC_TRUE) {
            return false;
        }
    }
    return true;
}

bool starts_with_case_insensitive(std::string_view value, std::string_view prefix) {
    if (value.size() < prefix.size()) {
        return false;
    }
    for (size_t index = 0; index < prefix.size(); ++index) {
        const auto lhs = static_cast<unsigned char>(value[index]);
        const auto rhs = static_cast<unsigned char>(prefix[index]);
        if (std::tolower(lhs) != std::tolower(rhs)) {
            return false;
        }
    }
    return true;
}

std::string trim_slashes(std::string value) {
    while (!value.empty() && value.front() == '/') {
        value.erase(value.begin());
    }
    while (!value.empty() && value.back() == '/') {
        value.pop_back();
    }
    return value;
}

bool is_arch_segment(std::string_view value) {
    return value == "v75" || value == "v79" || value == "v81";
}

std::vector<std::string> split_path(const std::string& path) {
    std::vector<std::string> segments;
    size_t start = 0;
    while (start < path.size()) {
        const size_t slash = path.find('/', start);
        const size_t end = slash == std::string::npos ? path.size() : slash;
        if (end > start) {
            segments.push_back(path.substr(start, end - start));
        }
        if (slash == std::string::npos) {
            break;
        }
        start = slash + 1;
    }
    return segments;
}

std::string query_manifest(const std::string& query) {
    size_t start = 0;
    while (start < query.size()) {
        const size_t amp = query.find('&', start);
        const size_t end = amp == std::string::npos ? query.size() : amp;
        const std::string_view field(query.data() + start, end - start);
        constexpr std::string_view prefix = "manifest=";
        if (field.size() >= prefix.size() && field.substr(0, prefix.size()) == prefix) {
            return std::string(field.substr(prefix.size()));
        }
        if (amp == std::string::npos) {
            break;
        }
        start = amp + 1;
    }
    return {};
}

// QHexRT catalog grammar. Commons remains unaware of chips/architectures; it
// receives a concrete HF folder ref after this function inserts v75/v79/v81.
rac_result_t pin_hf_ref_to_arch(const std::string& input, rac_qhexrt_hexagon_arch_t arch,
                                std::string* output, std::string* error) {
    if (output == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *output = input;

    static constexpr std::string_view prefixes[] = {"https://huggingface.co/", "https://hf.co/",
                                                    "huggingface.co/", "hf.co/", "hf://"};
    std::string rest;
    bool is_hf = false;
    for (const std::string_view prefix : prefixes) {
        if (starts_with_case_insensitive(input, prefix)) {
            rest = input.substr(prefix.size());
            is_hf = true;
            break;
        }
    }
    if (!is_hf) {
        return RAC_SUCCESS;
    }

    std::string query;
    const size_t query_pos = rest.find('?');
    if (query_pos != std::string::npos) {
        query = rest.substr(query_pos + 1);
        rest.resize(query_pos);
    }
    rest = trim_slashes(rest);
    std::vector<std::string> segments = split_path(rest);
    if (segments.size() < 2 || segments[0].empty() || segments[1].empty()) {
        if (error != nullptr) {
            *error = "QHexRT Hugging Face refs require an organization and repository";
        }
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Concrete file refs are intentionally not rewritten.
    if (segments.size() >= 3 && (segments[2] == "resolve" || segments[2] == "blob")) {
        return RAC_SUCCESS;
    }

    const std::string arch_name = rac_qhexrt_arch_name(arch);
    if (segments.size() >= 3 && is_arch_segment(segments[2])) {
        if (segments[2] != arch_name) {
            if (error != nullptr) {
                *error = "QHexRT catalog URL is pinned to " + segments[2] +
                         " but the detected device is " + arch_name;
            }
            return RAC_ERROR_INVALID_ARGUMENT;
        }
        return RAC_SUCCESS;
    }

    std::string manifest = query_manifest(query);
    if (!manifest.empty() &&
        (manifest.find('/') != std::string::npos || manifest.find("..") != std::string::npos)) {
        if (error != nullptr) {
            *error = "QHexRT manifest query must be a safe top-level filename";
        }
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (segments.size() == 2) {
        segments.push_back(arch_name);
        if (!manifest.empty()) {
            segments.push_back(manifest);
        }
    } else if (segments.size() == 3 && segments[2].size() >= 5 &&
               segments[2].compare(segments[2].size() - 5, 5, ".json") == 0) {
        segments.insert(segments.begin() + 2, arch_name);
    } else {
        // A nested path that is neither logical root/manifest nor already
        // arch-pinned is an explicit ref; leave it unchanged for commons.
        return RAC_SUCCESS;
    }

    *output = "https://huggingface.co/";
    for (size_t index = 0; index < segments.size(); ++index) {
        if (index != 0) {
            output->push_back('/');
        }
        output->append(segments[index]);
    }
    return RAC_SUCCESS;
}

#endif  // RAC_QHEXRT_HAVE_PROTOBUF

}  // namespace

namespace rac::qhexrt::catalog {

rac_result_t register_for_arch_proto(const uint8_t* request_bytes, size_t request_size,
                                     const rac_qhexrt_hexagon_arch_t* supported_arches,
                                     size_t supported_arch_count,
                                     rac_qhexrt_hexagon_arch_t detected_arch,
                                     rac_bool_t* out_registered, rac_proto_buffer_t* out_model) {
    if (out_registered == nullptr || out_model == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_registered = RAC_FALSE;

#if !defined(RAC_QHEXRT_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    (void)supported_arches;
    (void)supported_arch_count;
    (void)detected_arch;
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "QHexRT catalog registration requires protobuf support");
#else
    const rac_result_t bytes_rc = rac_proto_bytes_validate(request_bytes, request_size);
    if (bytes_rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_model, bytes_rc,
                                          "RegisterModelFromUrlRequest bytes are invalid");
    }
    if (!valid_supported_arches(supported_arches, supported_arch_count)) {
        return definition_error(out_model,
                                "supported_arches must contain only QHexRT v75, v79, and/or "
                                "v81 values");
    }

    runanywhere::v1::RegisterModelFromUrlRequest request;
    if (!request.ParseFromArray(rac_proto_bytes_data_or_empty(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_model, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse RegisterModelFromUrlRequest");
    }
    if (request.id().empty()) {
        return definition_error(out_model,
                                "QHexRT catalog definitions require an explicit stable model id");
    }
    if (!request.has_framework() ||
        request.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT) {
        return definition_error(out_model,
                                "QHexRT catalog definitions require the QHEXRT framework");
    }
    if (request.url().empty()) {
        return definition_error(out_model, "QHexRT catalog definitions require a URL");
    }

    if (rac_qhexrt_model_supports_arch(supported_arches, supported_arch_count, detected_arch) !=
        RAC_TRUE) {
        return rac_proto_buffer_copy(nullptr, 0, out_model);
    }

    std::string resolved_url;
    std::string resolve_error;
    const rac_result_t resolve_rc =
        pin_hf_ref_to_arch(request.url(), detected_arch, &resolved_url, &resolve_error);
    if (resolve_rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_model, resolve_rc, resolve_error.c_str());
    }
    request.set_url(resolved_url);

    std::string resolved_request_bytes;
    if (!request.SerializeToString(&resolved_request_bytes)) {
        return rac_proto_buffer_set_error(out_model, RAC_ERROR_ENCODING_ERROR,
                                          "failed to serialize resolved QHexRT catalog request");
    }

    // The policy is inert process-lifetime metadata and registration is
    // idempotent. Installing it here makes the facade safe before backend
    // registration while keeping all QHexRT knowledge in the engine.
    const rac_result_t policy_rc = rac_bundle_policy_register(qhexrt_bundle_policy());
    if (policy_rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_model, policy_rc,
                                          "failed to install QHexRT bundle policy");
    }

    const rac_result_t register_rc = rac_register_model_from_url_proto(
        reinterpret_cast<const uint8_t*>(resolved_request_bytes.data()),
        resolved_request_bytes.size(), out_model);
    if (register_rc == RAC_SUCCESS && out_model->status == RAC_SUCCESS) {
        *out_registered = RAC_TRUE;
    }
    return register_rc;
#endif
}

}  // namespace rac::qhexrt::catalog

extern "C" {

rac_bool_t rac_qhexrt_model_supports_arch(const rac_qhexrt_hexagon_arch_t* supported_arches,
                                          size_t supported_arch_count,
                                          rac_qhexrt_hexagon_arch_t arch) {
    if (supported_arches == nullptr || supported_arch_count == 0 ||
        rac_qhexrt_arch_is_supported(arch) != RAC_TRUE) {
        return RAC_FALSE;
    }
    for (size_t index = 0; index < supported_arch_count; ++index) {
        if (supported_arches[index] == arch) {
            return RAC_TRUE;
        }
    }
    return RAC_FALSE;
}

rac_result_t
rac_qhexrt_register_model_for_device_proto(const uint8_t* request_bytes, size_t request_size,
                                           const rac_qhexrt_hexagon_arch_t* supported_arches,
                                           size_t supported_arch_count, rac_bool_t* out_registered,
                                           rac_proto_buffer_t* out_model) {
    if (out_registered == nullptr || out_model == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_qhexrt_device_info_t capability{};
    const rac_result_t probe_rc = rac_qhexrt_probe(&capability);
    if (probe_rc != RAC_SUCCESS) {
        *out_registered = RAC_FALSE;
        return rac_proto_buffer_set_error(out_model, probe_rc, "QHexRT device probe failed");
    }
    return rac::qhexrt::catalog::register_for_arch_proto(
        request_bytes, request_size, supported_arches, supported_arch_count,
        capability.hexagon_arch, out_registered, out_model);
}

}  // extern "C"
