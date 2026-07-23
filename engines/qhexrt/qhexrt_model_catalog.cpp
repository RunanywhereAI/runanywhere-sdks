/**
 * @file qhexrt_model_catalog.cpp
 * @brief QHexRT-owned chip selection and catalog registration facade.
 */

#include "qhexrt_bundle_policy.h"
#include "qhexrt_model_catalog_internal.h"

#include <algorithm>
#include <cctype>
#include <iterator>
#include <string>
#include <string_view>
#include <vector>

#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/model_management/rac_bundle_policy.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/qhexrt/rac_qhexrt.h"

#if defined(RAC_QHEXRT_HAVE_PROTOBUF)
#include "model_types.pb.h"
#endif

#ifndef RAC_QHEXRT_ENGINE_AVAILABLE
#define RAC_QHEXRT_ENGINE_AVAILABLE 0
#endif

extern "C" rac_bool_t rac_backend_qhexrt_is_registered(void);

namespace {

constexpr uint8_t kV75 = 1U << 0;
constexpr uint8_t kV79 = 1U << 1;
constexpr uint8_t kV81 = 1U << 2;
constexpr uint8_t kV75V79 = kV75 | kV79;
constexpr uint8_t kV75V81 = kV75 | kV81;
constexpr uint8_t kV79V81 = kV79 | kV81;
constexpr uint8_t kAllSupportedArches = kV75 | kV79 | kV81;

struct ModelPolicy {
    std::string_view id;
    uint8_t arch_mask;
    bool requires_hf_auth;
};

// Product URLs and presentation remain app-owned. Stable model identity,
// device applicability, and remote access class are QHexRT runtime policy so
// Kotlin, Flutter, and React Native cannot drift independently.
constexpr ModelPolicy kModelPolicies[] = {
    {"lfm2_5_230m", kAllSupportedArches, false},
    {"lfm2_5_350m", kAllSupportedArches, false},
    {"qwen3_5_0_8b", kAllSupportedArches, false},
    {"qwen3_5_2b", kAllSupportedArches, false},
    {"qwen3_5_4b", kV79V81, false},
    {"qwen3_0_6b", kV75V81, false},
    {"llama3_2_1b", kV79V81, false},
    {"ternary_bonsai_1_7b", kV75V81, false},
    {"bonsai_1_7b_1bit", kV81, false},
    {"bonsai_4b_1bit", kV75V81, false},
    {"bonsai_8b_1bit", kV75V81, false},
    {"bonsai_27b_1bit", kV81, false},
    {"phi_tiny_moe", kV79V81, false},
    {"embeddinggemma_300m", kAllSupportedArches, false},
    // The V79 bundle requires QAIRT 2.48; Android production currently ships 2.47.
    {"gemma3n_e4b", kV81, false},
    {"gemma4_e2b", kV79V81, false},
    {"gemma4_e4b", kV81, false},
    {"llama_embed_nemotron_8b", kV81, false},
    {"nv_embedcode_7b", kV81, false},
    {"nv_embedqa_1b", kV75V81, false},
    {"nv_rerankqa_1b", kV75V81, false},
    {"deepseek_r1_distill_qwen_1_5b", kV79V81, false},
    {"deepseek_r1_distill_qwen_7b", kV81, false},
    {"nemotron_nano_8b", kV75V81, false},
    {"nemoguard_content_8b", kV81, false},
    {"nemoguard_topic_8b", kV81, false},
    {"qwen3_vl_2b_text", kV81, false},
    {"qwen3_vl", kV75V79, false},
    {"cosmos3_edge_text", kV81, false},   // Cosmos3-Edge reasoning/text AR path (sharded fp16 decode, split_generate); v81 device-validated greedy-exact
    {"cosmos3_edge_vlm", kV81, false},    // Cosmos3-Edge image-understanding path (SigLIP vision + W8 decode via cosmos3vl_generate); v81 device-validated
    {"cosmos3_edge_diffusion", kV81, false},  // Cosmos3-Edge text->image (4-shard W8 DiT + UniPC denoise + tiled VAE via cosmos3_diffusion_generate); v81
    {"internvl3_5_1b", kAllSupportedArches, false},
    {"gemma4_e2b_vlm", kV79V81, false},
    {"gemma4_e4b_vlm", kV81, false},
    {"nemotron_nano_vl_8b", kV81, false},
    {"lama_dilated", kV79V81, false},
    {"nemotron_ocr", kV75V81, false},
    {"nemotron_ocr_v1", kV75V81, false},
    {"nemotron_parse", kV75V81, false},
    {"siglip2_base", kAllSupportedArches, false},
    {"whisper_base", kAllSupportedArches, false},
    {"whisper_small", kAllSupportedArches, false},
    {"moonshine_tiny", kAllSupportedArches, false},
    {"moonshine_base", kAllSupportedArches, false},
    {"parakeet_tdt_0_6b_v2", kV75V81, false},
    {"parakeet_tdt_0_6b_v3", kV75V81, false},
    {"parakeet_rnnt_1_1b", kV75V81, false},
    {"canary_qwen_2_5b", kV81, false},
    {"canary_1b_flash", kV75V81, false},
    {"nemotron_asr_streaming", kV75V81, false},
    {"melotts_en", kAllSupportedArches, false},
    // V79 requires model-downloaded executable .so files, which Play disallows.
    {"kokoro_en", kV75V81, false},
    {"kitten_nano_0_8", kV75V81, false},
    {"kitten_mini_0_8", kV81, false},
    {"kitten_micro_0_8", kV81, false},
};

const ModelPolicy* find_model_policy(std::string_view model_id) {
    const auto it =
        std::find_if(std::begin(kModelPolicies), std::end(kModelPolicies),
                     [model_id](const ModelPolicy& policy) { return policy.id == model_id; });
    return it == std::end(kModelPolicies) ? nullptr : &*it;
}

uint8_t arch_mask(rac_qhexrt_hexagon_arch_t arch) {
    switch (arch) {
        case RAC_QHEXRT_HEXAGON_ARCH_V75:
            return kV75;
        case RAC_QHEXRT_HEXAGON_ARCH_V79:
            return kV79;
        case RAC_QHEXRT_HEXAGON_ARCH_V81:
            return kV81;
        default:
            return 0;
    }
}

#if defined(RAC_QHEXRT_HAVE_PROTOBUF)

rac_result_t definition_error(rac_proto_buffer_t* out_model, const char* message) {
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_INVALID_ARGUMENT, message);
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
                                     rac_qhexrt_hexagon_arch_t detected_arch,
                                     rac_bool_t engine_available, rac_bool_t* out_registered,
                                     rac_proto_buffer_t* out_model) {
    if (out_registered == nullptr || out_model == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_registered = RAC_FALSE;

#if !defined(RAC_QHEXRT_HAVE_PROTOBUF)
    (void)request_bytes;
    (void)request_size;
    (void)detected_arch;
    (void)engine_available;
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "QHexRT catalog registration requires protobuf support");
#else
    const rac_result_t bytes_rc = rac_proto_bytes_validate(request_bytes, request_size);
    if (bytes_rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_model, bytes_rc,
                                          "RegisterModelFromUrlRequest bytes are invalid");
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

    const ModelPolicy* policy = find_model_policy(request.id());
    if (policy == nullptr) {
        return definition_error(out_model, "unknown QHexRT native catalog model id");
    }
    if (engine_available != RAC_TRUE) {
        return rac_proto_buffer_copy(nullptr, 0, out_model);
    }
    if ((policy->arch_mask & arch_mask(detected_arch)) == 0) {
        return rac_proto_buffer_copy(nullptr, 0, out_model);
    }
    if (policy->requires_hf_auth && rac_http_hf_token_is_configured() != RAC_TRUE) {
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
    // idempotent. Ensure it is installed before commons registration while
    // keeping all QHexRT knowledge in the engine.
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

rac_bool_t rac_qhexrt_catalog_model_is_known(const char* model_id) {
    return model_id != nullptr && find_model_policy(model_id) != nullptr ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t rac_qhexrt_catalog_model_supports_arch(const char* model_id,
                                                  rac_qhexrt_hexagon_arch_t arch) {
    if (model_id == nullptr) {
        return RAC_FALSE;
    }
    const ModelPolicy* policy = find_model_policy(model_id);
    return policy != nullptr && (policy->arch_mask & arch_mask(arch)) != 0 ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t rac_qhexrt_catalog_model_requires_hf_auth(const char* model_id) {
    if (model_id == nullptr) {
        return RAC_FALSE;
    }
    const ModelPolicy* policy = find_model_policy(model_id);
    return policy != nullptr && policy->requires_hf_auth ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_qhexrt_catalog_register_model_proto(const uint8_t* request_bytes,
                                                     size_t request_size,
                                                     rac_bool_t* out_registered,
                                                     rac_proto_buffer_t* out_model) {
    if (out_registered == nullptr || out_model == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_registered = RAC_FALSE;
    if (!RAC_QHEXRT_ENGINE_AVAILABLE || rac_backend_qhexrt_is_registered() != RAC_TRUE) {
        return rac_proto_buffer_copy(nullptr, 0, out_model);
    }

    rac_qhexrt_device_info_t capability{};
    const rac_result_t probe_rc = rac_qhexrt_probe(&capability);
    if (probe_rc != RAC_SUCCESS) {
        *out_registered = RAC_FALSE;
        return rac_proto_buffer_set_error(out_model, probe_rc, "QHexRT device probe failed");
    }
    return rac::qhexrt::catalog::register_for_arch_proto(
        request_bytes, request_size, capability.hexagon_arch, RAC_TRUE, out_registered, out_model);
}

}  // extern "C"
