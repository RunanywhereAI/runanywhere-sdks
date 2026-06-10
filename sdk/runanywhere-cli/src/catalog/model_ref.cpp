#include "catalog/model_ref.h"

#include <string>
#include <vector>

#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "catalog/catalog.h"
#include "catalog/url_registry.h"
#include "io/output.h"
#include "io/proto.h"

namespace rcli::model_ref {

namespace {

bool is_http_url(const std::string& ref) {
    return ref.starts_with("http://") || ref.starts_with("https://");
}

// Registers a URL-form ref through the commons factory and returns the saved id.
rac_result_t register_url(const std::string& url, std::string* out_id, std::string* error) {
    runanywhere::v1::RegisterModelFromUrlRequest request;
    request.set_url(url);

    const std::string bytes = proto::serialize(request);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_register_model_from_url_proto(
        reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), &out);
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&out);
        if (error) {
            *error = "failed to register " + url + ": " + out::describe_result(rc);
        }
        return rc;
    }

    runanywhere::v1::ModelInfo saved;
    std::string parse_error;
    if (!proto::parse_proto_buffer(&out, &saved, &parse_error)) {
        if (error) {
            *error = "failed to register " + url + ": " + parse_error;
        }
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_id = saved.id();
    // Non-catalog registration: persist so later invocations (list/run/rm)
    // still know this model — the in-memory registry forgets at exit.
    url_registry::persist(saved.id(), proto::serialize(saved));
    return RAC_SUCCESS;
}

}  // namespace

std::string normalize_hf_ref(const std::string& ref) {
    std::string rest;
    for (const char* prefix : {"hf.co/", "huggingface.co/", "https://hf.co/",
                               "http://hf.co/", "https://huggingface.co/"}) {
        if (ref.starts_with(prefix)) {
            rest = ref.substr(std::string(prefix).size());
            break;
        }
    }
    if (rest.empty()) {
        return {};
    }
    // Already a full resolve/blob URL → just re-host on huggingface.co.
    if (rest.find("/resolve/") != std::string::npos) {
        return "https://huggingface.co/" + rest;
    }
    // org/repo/path/to/file → org/repo/resolve/main/path/to/file
    const size_t org_end = rest.find('/');
    if (org_end == std::string::npos) {
        return {};
    }
    const size_t repo_end = rest.find('/', org_end + 1);
    if (repo_end == std::string::npos || repo_end + 1 >= rest.size()) {
        return {};  // need an explicit file path inside the repo
    }
    return "https://huggingface.co/" + rest.substr(0, repo_end) + "/resolve/main/" +
           rest.substr(repo_end + 1);
}

rac_result_t resolve(const std::string& ref, Resolved* out, std::string* error) {
    if (ref.empty()) {
        if (error) {
            *error = "empty model reference";
        }
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    if (const catalog::CatalogEntry* entry = catalog::find(ref)) {
        out->model_id = entry->id;
        out->from_catalog = true;
        return RAC_SUCCESS;
    }

    // Registered but non-catalog ids: persisted URL pulls, discovered models.
    if (!is_http_url(ref)) {
        rac_proto_buffer_t found;
        rac_proto_buffer_init(&found);
        if (rac_model_registry_get_proto_buffer(rac_get_model_registry(), ref.c_str(), &found) ==
                RAC_SUCCESS &&
            found.status == RAC_SUCCESS) {
            rac_proto_buffer_free(&found);
            out->model_id = ref;
            out->from_catalog = false;
            return RAC_SUCCESS;
        }
        rac_proto_buffer_free(&found);
    }

    const std::string hf_url = normalize_hf_ref(ref);
    if (!hf_url.empty()) {
        out->from_catalog = false;
        return register_url(hf_url, &out->model_id, error);
    }

    if (is_http_url(ref)) {
        out->from_catalog = false;
        return register_url(ref, &out->model_id, error);
    }

    if (error) {
        *error = "unknown model '" + ref + "'";
        const std::vector<std::string> close = catalog::suggestions(ref, 3);
        if (!close.empty()) {
            *error += " — did you mean: ";
            for (size_t i = 0; i < close.size(); ++i) {
                *error += (i ? ", " : "") + close[i];
            }
            *error += "?";
        } else {
            *error += " (try `rcli list --all`, an hf.co/org/repo/file ref, or a direct URL)";
        }
    }
    return RAC_ERROR_NOT_FOUND;
}

}  // namespace rcli::model_ref
