#include "catalog/model_ref.h"

#include <string>
#include <vector>

#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "catalog/catalog.h"
#include "io/output.h"
#include "io/proto.h"

namespace rcli::model_ref {

namespace {

bool is_http_url(const std::string &ref) {
  return ref.starts_with("http://") || ref.starts_with("https://");
}

// Thin gate only — the full HF ref grammar (repo refs, quant tags, explicit
// file paths, shard/mmproj resolution) is owned by commons inside
// rac_register_model_from_url_proto; the CLI just decides whether `ref` is
// worth handing over versus reporting "unknown model".
bool looks_like_hf_ref(const std::string &ref) {
  for (const char *prefix : {"hf://", "hf.co/", "huggingface.co/"}) {
    if (ref.starts_with(prefix)) {
      return true;
    }
  }
  return false;
}

// Registers a URL or Hugging Face ref through the commons factory and returns
// the saved id. Durable persistence is commons-owned: once the model
// downloads, the model-folder manifest sidecar restores the entry on the next
// launch (no CLI-side registry needed).
rac_result_t register_url(const std::string &url, const ResolveOptions *options,
                          std::string *out_id, std::string *error) {
  runanywhere::v1::RegisterModelFromUrlRequest request;
  request.set_url(url);
  if (options && options->has_framework) {
    request.set_framework(options->framework);
  }
  if (options && options->has_category) {
    request.set_category(options->category);
  }

  const std::string bytes = proto::serialize(request);
  rac_proto_buffer_t out;
  rac_proto_buffer_init(&out);
  const rac_result_t rc = rac_register_model_from_url_proto(
      reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size(), &out);
  if (rc != RAC_SUCCESS) {
    std::string detail =
        out.error_message ? out.error_message : out::describe_result(rc);
    rac_proto_buffer_free(&out);
    if (error) {
      *error = "failed to register " + url + ": " + detail;
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
  return RAC_SUCCESS;
}

} // namespace

rac_result_t resolve(const std::string &ref, Resolved *out, std::string *error,
                     const ResolveOptions *options) {
  if (ref.empty()) {
    if (error) {
      *error = "empty model reference";
    }
    return RAC_ERROR_INVALID_ARGUMENT;
  }

  if (const catalog::CatalogEntry *entry = catalog::find(ref)) {
    out->model_id = entry->id;
    out->from_catalog = true;
    return RAC_SUCCESS;
  }

  // Registered but non-catalog ids: manifest-restored URL/HF pulls,
  // discovered models.
  if (!is_http_url(ref)) {
    rac_proto_buffer_t found;
    rac_proto_buffer_init(&found);
    if (rac_model_registry_get_proto_buffer(
            rac_get_model_registry(), ref.c_str(), &found) == RAC_SUCCESS &&
        found.status == RAC_SUCCESS) {
      rac_proto_buffer_free(&found);
      out->model_id = ref;
      out->from_catalog = false;
      return RAC_SUCCESS;
    }
    rac_proto_buffer_free(&found);
  }

  if (is_http_url(ref) || looks_like_hf_ref(ref)) {
    out->from_catalog = false;
    return register_url(ref, options, &out->model_id, error);
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
      *error += " (try `rcli list --all`, an hf.co/org/repo[:quant] ref, or a "
                "direct URL)";
    }
  }
  return RAC_ERROR_NOT_FOUND;
}

} // namespace rcli::model_ref
