#include "catalog/model_ref.h"

#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <dirent.h>
#include <string>
#include <sys/stat.h>
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

// A ref that names an existing directory or file on disk. Checked BEFORE the
// HF/URL branch but AFTER the catalog and the registry, so a local path can
// never shadow a real model id.
bool is_local_path(const std::string &ref) {
  if (ref.empty() || is_http_url(ref) || looks_like_hf_ref(ref)) {
    return false;
  }
  // Only treat something as a path when it looks like one. A bare word is a
  // model id; requiring a separator or an explicit `.`/`~` prefix keeps
  // `rcli run qwen3` from stat()ing the cwd and finding a stray directory.
  if (ref.find('/') == std::string::npos) {
    return false;
  }
  struct stat st {};
  return ::stat(ref.c_str(), &st) == 0;
}

// A trailing `/` carries no meaning but would break both the basename split
// and the `.mlpackage` suffix tests below, so strip it once, here.
std::string without_trailing_slashes(const std::string &path) {
  std::string out = path;
  while (out.size() > 1 && out.back() == '/') {
    out.pop_back();
  }
  return out;
}

// Derive a stable, collision-free registry id from a bundle path. Using one
// hardcoded id (as the diffusion path does) is fine for a single model and
// wrong the moment two bundles are registered in one process — the second
// silently overwrites the first, and every later load resolves to whichever
// won.
std::string id_for_local_path(const std::string &path) {
  std::string full = without_trailing_slashes(path);
  // Canonicalize first so the same bundle spelled differently (relative, `..`,
  // a symlink) keeps ONE id; the raw path is the fallback when it cannot be
  // resolved. `std::filesystem` rather than `realpath` because rcli builds on
  // Windows too and `realpath` is POSIX-only; `weakly_canonical` also tolerates
  // a path that does not fully exist instead of failing outright.
  std::error_code ec;
  const std::filesystem::path canonical = std::filesystem::weakly_canonical(full, ec);
  if (!ec && !canonical.empty()) {
    full = canonical.string();
  }

  // filename() handles BOTH separators; a manual find_last_of('/') would return
  // the whole path as the basename on a Windows-style path.
  std::string base = std::filesystem::path(full).filename().string();
  if (base.empty()) {
    base = full;
  }
  for (char &c : base) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (!std::isalnum(static_cast<unsigned char>(c)) && c != '-' && c != '.') {
      c = '-';
    }
  }

  // The basename alone collides — every `.../model.mlpackage` sanitizes to the
  // same string — so pin the id to the whole path with an FNV-1a digest.
  uint64_t hash = 1469598103934665603ULL;
  for (const unsigned char c : full) {
    hash ^= c;
    hash *= 1099511628211ULL;
  }
  static constexpr char kHex[] = "0123456789abcdef";
  std::string digest;
  for (int shift = 28; shift >= 0; shift -= 4) {
    digest.push_back(kHex[(hash >> shift) & 0xF]);
  }
  return "local-" + base + "-" + digest;
}

// Best-effort format/framework inference from the bundle layout. Only used when
// the caller did not pin one with --engine, and deliberately narrow: it answers
// "which of the shapes the CLI can actually load is this", not "what model is
// this". Unknown layouts are left UNSPECIFIED so commons falls back to its own
// resolution rather than acting on a CLI guess.
void infer_local_kind(const std::string &path,
                      runanywhere::v1::InferenceFramework *framework,
                      runanywhere::v1::ModelFormat *format) {
  *framework = runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
  *format = runanywhere::v1::MODEL_FORMAT_UNSPECIFIED;

  struct stat st {};
  if (::stat(path.c_str(), &st) != 0) {
    return;
  }
  if (!S_ISDIR(st.st_mode)) {
    if (path.ends_with(".gguf")) {
      *framework = runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
      *format = runanywhere::v1::MODEL_FORMAT_GGUF;
    }
    return;
  }
  // A Core ML package IS a directory, so a ref naming the package itself lands
  // here too — and its children (Manifest.json, Data/) match nothing in the
  // scan below. Check the path's own name before descending into it.
  const std::string self = without_trailing_slashes(path);
  if (self.ends_with(".mlpackage") || self.ends_with(".mlmodelc")) {
    *framework = runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
    *format = runanywhere::v1::MODEL_FORMAT_MLPACKAGE;
    return;
  }
  // A directory holding at least one .mlpackage is an Apple bundle — the shape
  // every runanywhere/*_ANE repo ships.
  if (DIR *dir = ::opendir(path.c_str())) {
    while (dirent *ent = ::readdir(dir)) {
      const std::string name = ent->d_name;
      if (name.ends_with(".mlpackage") || name.ends_with(".mlmodelc")) {
        *framework = runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
        *format = runanywhere::v1::MODEL_FORMAT_MLPACKAGE;
        break;
      }
    }
    ::closedir(dir);
  }
}

// Register an already-present local bundle so the lifecycle loader can resolve
// it by id, with no download. Mirrors what `rcli image` has always done for a
// local CoreML diffusion bundle (cmd_image.cpp::register_local_bundle) — this
// is that capability moved down to the shared resolver, so every command that
// takes a model ref gets it instead of just one.
rac_result_t register_local_path(const std::string &path,
                                 const ResolveOptions *options,
                                 std::string *out_id, std::string *error) {
  runanywhere::v1::InferenceFramework framework;
  runanywhere::v1::ModelFormat format;
  infer_local_kind(path, &framework, &format);
  // An explicit --engine always wins over inference.
  if (options && options->has_framework) {
    framework = options->framework;
  }

  runanywhere::v1::ModelInfo model;
  model.set_id(id_for_local_path(path));
  model.set_name(path);
  model.set_local_path(path);
  model.set_source(runanywhere::v1::MODEL_SOURCE_LOCAL);
  if (framework != runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED) {
    model.set_framework(framework);
  }
  if (format != runanywhere::v1::MODEL_FORMAT_UNSPECIFIED) {
    model.set_format(format);
  }
  if (options && options->has_category) {
    model.set_category(options->category);
  } else {
    model.set_category(runanywhere::v1::MODEL_CATEGORY_LANGUAGE);
  }

  const std::string bytes = proto::serialize(model);
  const rac_result_t rc = rac_model_registry_register_proto(
      rac_get_model_registry(),
      reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size());
  if (rc != RAC_SUCCESS) {
    if (error) {
      *error = "failed to register local bundle '" + path +
               "': " + out::describe_result(rc);
    }
    return rc;
  }
  *out_id = model.id();
  return RAC_SUCCESS;
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

  // A path on disk. Checked after the catalog + registry so it can never
  // shadow a real id, and before the "unknown model" arm so an ANE bundle
  // sitting in a directory is reachable at all — it previously was not, which
  // made every local Core ML LLM unloadable through the CLI.
  if (is_local_path(ref)) {
    out->from_catalog = false;
    return register_local_path(ref, options, &out->model_id, error);
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
      *error += " (try `rcli list --all`, an hf.co/org/repo[:quant] ref, a "
                "direct URL, or a path to a local bundle directory)";
    }
  }
  return RAC_ERROR_NOT_FOUND;
}

} // namespace rcli::model_ref
