/**
 * @file test_rcli_unit.cpp
 * @brief rcli unit tests — pure helpers, no models, no network.
 *
 * Uses the commons TestSuite harness so the Docker rig and ctest drive every
 * suite the same way (--run-all / --test-<name>).
 */

#include "test_common.h"

#include <cstdlib>
#include <string>

#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "catalog/catalog.h"
#include "catalog/model_ref.h"
#include "commands/engine_options.h"
#include "config/cli_paths.h"
#include "io/output.h"
#include "io/proto.h"

namespace {

// setenv/unsetenv helper that restores prior state on scope exit.
class EnvVar {
public:
  EnvVar(const char *name, const char *value) : name_(name) {
    if (const char *prev = std::getenv(name)) {
      had_prev_ = true;
      prev_ = prev;
    }
    if (value) {
      setenv(name, value, 1);
    } else {
      unsetenv(name);
    }
  }
  ~EnvVar() {
    if (had_prev_) {
      setenv(name_.c_str(), prev_.c_str(), 1);
    } else {
      unsetenv(name_.c_str());
    }
  }

private:
  std::string name_;
  std::string prev_;
  bool had_prev_ = false;
};

TestResult test_json_escape() {
  TestResult result;
  result.test_name = "json_escape";

  struct Case {
    std::string in;
    std::string expected;
  };
  const Case cases[] = {
      {"plain", "plain"},
      {"quote\"backslash\\", "quote\\\"backslash\\\\"},
      {"line\nbreak\ttab", "line\\nbreak\\ttab"},
      {std::string("ctl\x01", 4), "ctl\\u0001"},
  };
  for (const Case &c : cases) {
    const std::string actual = rcli::out::json_escape(c.in);
    if (actual != c.expected) {
      result.expected = c.expected;
      result.actual = actual;
      return result;
    }
  }
  result.passed = true;
  return result;
}

TestResult test_json_writer_shape() {
  TestResult result;
  result.test_name = "json_writer_shape";

  rcli::out::JsonWriter json;
  json.begin_object()
      .field("name", "qwen3-0.6b")
      .field("size", static_cast<int64_t>(640))
      .field("downloaded", true);
  json.begin_array("files");
  json.begin_array_object().field("path", "a.gguf").end_object();
  json.begin_array_object().field("path", "b.gguf").end_object();
  json.end_array().end_object();

  const std::string expected =
      R"({"name":"qwen3-0.6b","size":640,"downloaded":true,)"
      R"("files":[{"path":"a.gguf"},{"path":"b.gguf"}]})";
  if (json.str() != expected) {
    result.expected = expected;
    result.actual = json.str();
    return result;
  }
  result.passed = true;
  return result;
}

TestResult test_human_bytes() {
  TestResult result;
  result.test_name = "human_bytes";

  struct Case {
    uint64_t in;
    std::string expected;
  };
  const Case cases[] = {
      {512, "512 B"},
      {2048, "2.0 KB"},
      {640ull * 1024 * 1024, "640.0 MB"},
      {3ull * 1024 * 1024 * 1024, "3.0 GB"},
  };
  for (const Case &c : cases) {
    const std::string actual = rcli::out::human_bytes(c.in);
    if (actual != c.expected) {
      result.expected = c.expected;
      result.actual = actual;
      return result;
    }
  }
  result.passed = true;
  return result;
}

TestResult test_normalize_dir() {
  TestResult result;
  result.test_name = "normalize_dir";

  if (rcli::paths::normalize_dir("/a/b/") != "/a/b" ||
      rcli::paths::normalize_dir("/a/b///") != "/a/b" ||
      rcli::paths::normalize_dir("/") != "/" ||
      !rcli::paths::normalize_dir("").empty()) {
    result.details = "trailing-slash handling broken";
    return result;
  }
  result.passed = true;
  return result;
}

TestResult test_resolve_home_precedence() {
  TestResult result;
  result.test_name = "resolve_home_precedence";

  {
    // Flag override wins over env.
    EnvVar env("RUNANYWHERE_HOME", "/from-env/runanywhere");
    if (rcli::paths::resolve_home("/from-flag/runanywhere/") !=
        "/from-flag/runanywhere") {
      result.details = "flag override should win and be normalized";
      return result;
    }
    if (rcli::paths::resolve_home("") != "/from-env/runanywhere") {
      result.details = "env should win when no flag given";
      return result;
    }
  }
  {
    // Default: XDG data dir under runanywhere.
    EnvVar env("RUNANYWHERE_HOME", nullptr);
    EnvVar xdg("XDG_DATA_HOME", "/xdg-data");
    const std::string home = rcli::paths::resolve_home("");
    if (home != "/xdg-data/runanywhere") {
      result.details = "expected /xdg-data/runanywhere, got " + home;
      return result;
    }
  }
  result.passed = true;
  return result;
}

TestResult test_state_dir() {
  TestResult result;
  result.test_name = "state_dir";

  EnvVar xdg("XDG_STATE_HOME", "/xdg-state");
  if (rcli::paths::state_dir() != "/xdg-state/runanywhere") {
    result.details = "XDG_STATE_HOME not honored";
    return result;
  }
  result.passed = true;
  return result;
}

TestResult test_catalog_lookup() {
  TestResult result;
  result.test_name = "catalog_lookup";

  size_t count = 0;
  const rcli::catalog::CatalogEntry *entries = rcli::catalog::all(&count);
  if (!entries || count < 10) {
    result.details = "catalog unexpectedly small";
    return result;
  }

  const rcli::catalog::CatalogEntry *by_id = rcli::catalog::find("qwen3-0.6b");
  const rcli::catalog::CatalogEntry *by_alias = rcli::catalog::find("qwen3");
  if (!by_id || by_id != by_alias) {
    result.details = "alias lookup should resolve to the same entry";
    return result;
  }
  if (rcli::catalog::find("definitely-not-a-model") != nullptr) {
    result.details = "unknown id should return nullptr";
    return result;
  }
  if (rcli::catalog::suggestions("qwen", 3).empty()) {
    result.details = "expected suggestions for 'qwen'";
    return result;
  }

  // Multi-file entries (VLM pairs, embeddings) must carry ≥2 required files.
  const rcli::catalog::CatalogEntry *vlm = rcli::catalog::find("smolvlm2");
  if (!vlm || vlm->files == nullptr || vlm->file_count != 2) {
    result.details = "smolvlm2 should be a two-file artifact";
    return result;
  }

  const rcli::catalog::CatalogEntry *mlx_llm =
      rcli::catalog::find("mlx-qwen3");
  if (!mlx_llm || mlx_llm->framework !=
                      runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      mlx_llm->format != runanywhere::v1::MODEL_FORMAT_SAFETENSORS ||
      mlx_llm->category != runanywhere::v1::MODEL_CATEGORY_LANGUAGE ||
      mlx_llm->files == nullptr || mlx_llm->file_count != 9 ||
      !mlx_llm->supports_thinking) {
    result.details = "mlx-qwen3 should be a complete MLX language bundle";
    return result;
  }

  const rcli::catalog::CatalogEntry *mlx_vlm =
      rcli::catalog::find("mlx-qwen2-vl");
  if (!mlx_vlm || mlx_vlm->category !=
                      runanywhere::v1::MODEL_CATEGORY_MULTIMODAL ||
      mlx_vlm->framework != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      mlx_vlm->files == nullptr || mlx_vlm->file_count != 11) {
    result.details = "mlx-qwen2-vl should be a complete MLX VLM bundle";
    return result;
  }
  bool has_preprocessor = false;
  for (size_t i = 0; i < mlx_vlm->file_count; ++i) {
    has_preprocessor =
        has_preprocessor ||
        std::string(mlx_vlm->files[i].filename) == "preprocessor_config.json";
  }
  if (!has_preprocessor) {
    result.details = "MLX VLM catalog entry must include preprocessor_config.json";
    return result;
  }

  const rcli::catalog::CatalogEntry *mlx_fastvlm =
      rcli::catalog::find("mlx-fastvlm");
  if (!mlx_fastvlm ||
      mlx_fastvlm->category != runanywhere::v1::MODEL_CATEGORY_MULTIMODAL ||
      mlx_fastvlm->framework != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      mlx_fastvlm->files == nullptr || mlx_fastvlm->file_count != 14) {
    result.details = "mlx-fastvlm should be a complete MLX VLM bundle";
    return result;
  }
  bool has_processor_config = false;
  bool has_fastvlm_companion = false;
  for (size_t i = 0; i < mlx_fastvlm->file_count; ++i) {
    const std::string filename = mlx_fastvlm->files[i].filename;
    has_processor_config =
        has_processor_config || filename == "processor_config.json";
    has_fastvlm_companion =
        has_fastvlm_companion ||
        (!mlx_fastvlm->files[i].required &&
         (filename == "processing_fastvlm.py" || filename == "llava_qwen.py"));
  }
  if (!has_processor_config || !has_fastvlm_companion) {
    result.details =
        "MLX FastVLM catalog entry must include processor config and companions";
    return result;
  }

  const rcli::catalog::CatalogEntry *mlx_embed =
      rcli::catalog::find("mlx-qwen3-embed");
  if (!mlx_embed || mlx_embed->category !=
                       runanywhere::v1::MODEL_CATEGORY_EMBEDDING ||
      mlx_embed->framework != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      mlx_embed->files == nullptr || mlx_embed->file_count != 11) {
    result.details = "mlx-qwen3-embed should be a complete MLX embedding bundle";
    return result;
  }

  result.passed = true;
  return result;
}

TestResult test_engine_hint_parsing() {
  TestResult result;
  result.test_name = "engine_hint_parsing";

  struct Case {
    std::string in;
    runanywhere::v1::InferenceFramework expected;
  };
  const Case cases[] = {
      {"", runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED},
      {"mlx", runanywhere::v1::INFERENCE_FRAMEWORK_MLX},
      {"llama.cpp", runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP},
      {"llama-cpp", runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP},
      {"onnx", runanywhere::v1::INFERENCE_FRAMEWORK_ONNX},
      {"sherpa", runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA},
  };
  for (const Case &c : cases) {
    runanywhere::v1::InferenceFramework actual =
        runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
    std::string error;
    if (!rcli::commands::parse_engine_hint(c.in, &actual, &error) ||
        actual != c.expected) {
      result.expected = std::to_string(static_cast<int>(c.expected));
      result.actual = std::to_string(static_cast<int>(actual));
      result.details = "input: " + c.in + " error: " + error;
      return result;
    }
  }

  runanywhere::v1::InferenceFramework actual =
      runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
  std::string error;
  if (rcli::commands::parse_engine_hint("banana", &actual, &error) ||
      error.find("unsupported engine") == std::string::npos) {
    result.details = "unsupported engine should fail with an actionable error";
    return result;
  }

  result.passed = true;
  return result;
}

void remove_registered_model(const std::string &id) {
  if (auto *registry = rac_get_model_registry()) {
    (void)rac_model_registry_remove_proto(registry, id.c_str());
  }
}

bool get_registered_model(const std::string &id, runanywhere::v1::ModelInfo *out,
                          std::string *error) {
  rac_proto_buffer_t found;
  rac_proto_buffer_init(&found);
  const rac_result_t rc = rac_model_registry_get_proto_buffer(
      rac_get_model_registry(), id.c_str(), &found);
  const bool parsed = rcli::proto::parse_proto_buffer(&found, out, error);
  if (!parsed && error && error->empty()) {
    *error = "registry get failed rc=" + std::to_string(rc);
  }
  return rc == RAC_SUCCESS && parsed;
}

TestResult test_mlx_catalog_registration() {
  TestResult result;
  result.test_name = "mlx_catalog_registration";

  const rac_result_t rc = rcli::catalog::register_all();
  if (rc != RAC_SUCCESS) {
    result.details = "catalog registration failed rc=" + std::to_string(rc);
    return result;
  }

  runanywhere::v1::ModelInfo qwen;
  std::string error;
  if (!get_registered_model("mlx-qwen3-0.6b-4bit", &qwen, &error)) {
    result.details = error;
    return result;
  }
  if (qwen.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      qwen.format() != runanywhere::v1::MODEL_FORMAT_SAFETENSORS ||
      qwen.category() != runanywhere::v1::MODEL_CATEGORY_LANGUAGE ||
      !qwen.has_multi_file() || qwen.multi_file().files_size() != 9 ||
      qwen.download_size_bytes() != 351383618 || !qwen.supports_thinking()) {
    result.details = "registered MLX Qwen3 metadata is incomplete";
    return result;
  }

  runanywhere::v1::ModelInfo vlm;
  if (!get_registered_model("mlx-qwen2-vl-2b-instruct-4bit", &vlm, &error)) {
    result.details = error;
    return result;
  }
  bool preprocessor_registered = false;
  for (const auto &file : vlm.multi_file().files()) {
    preprocessor_registered =
        preprocessor_registered || file.filename() == "preprocessor_config.json";
  }
  if (vlm.category() != runanywhere::v1::MODEL_CATEGORY_MULTIMODAL ||
      vlm.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      !vlm.has_multi_file() || vlm.multi_file().files_size() != 11 ||
      !preprocessor_registered) {
    result.details = "registered MLX VLM metadata is incomplete";
    return result;
  }

  runanywhere::v1::ModelInfo fastvlm;
  if (!get_registered_model("mlx-fastvlm-0.5b-bf16", &fastvlm, &error)) {
    result.details = error;
    return result;
  }
  bool processor_registered = false;
  bool companion_registered = false;
  for (const auto &file : fastvlm.multi_file().files()) {
    processor_registered =
        processor_registered || file.filename() == "processor_config.json";
    companion_registered =
        companion_registered ||
        (!file.is_required() &&
         (file.filename() == "processing_fastvlm.py" ||
          file.filename() == "llava_qwen.py"));
  }
  if (fastvlm.category() != runanywhere::v1::MODEL_CATEGORY_MULTIMODAL ||
      fastvlm.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      !fastvlm.has_multi_file() || fastvlm.multi_file().files_size() != 14 ||
      !processor_registered || !companion_registered) {
    result.details = "registered MLX FastVLM metadata is incomplete";
    return result;
  }

  runanywhere::v1::ModelInfo embedding;
  if (!get_registered_model("mlx-qwen3-embedding-0.6b-4bit-dwq", &embedding,
                            &error)) {
    result.details = error;
    return result;
  }
  if (embedding.category() != runanywhere::v1::MODEL_CATEGORY_EMBEDDING ||
      embedding.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      embedding.format() != runanywhere::v1::MODEL_FORMAT_SAFETENSORS ||
      !embedding.has_multi_file() || embedding.multi_file().files_size() != 11) {
    result.details = "registered MLX embedding metadata is incomplete";
    return result;
  }

  remove_registered_model("mlx-qwen3-0.6b-4bit");
  remove_registered_model("mlx-llama-3.2-1b-instruct-4bit");
  remove_registered_model("mlx-qwen2-vl-2b-instruct-4bit");
  remove_registered_model("mlx-fastvlm-0.5b-bf16");
  remove_registered_model("mlx-qwen3-embedding-0.6b-4bit-dwq");

  result.passed = true;
  return result;
}

// HF explicit-file refs normalize inside commons
// (rac_register_model_from_url_proto) now — verify through the production ABI
// that the saved entry carries the expected resolve/main download URL.
// Explicit-file refs never hit the network (only repo-level refs do, and none
// appear here).
TestResult test_hf_ref_registration() {
  TestResult result;
  result.test_name = "hf_ref_registration";

  struct Case {
    std::string in;
    std::string expected_download_url;
  };
  const Case cases[] = {
      {"hf.co/Qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q8_0.gguf",
       "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/"
       "Qwen3-0.6B-Q8_0.gguf"},
      {"huggingface.co/org/repo/sub/dir/file.gguf",
       "https://huggingface.co/org/repo/resolve/main/sub/dir/file.gguf"},
      {"https://huggingface.co/org/repo/resolve/main/f.gguf",
       "https://huggingface.co/org/repo/resolve/main/f.gguf"},
      {"https://example.com/m.gguf", "https://example.com/m.gguf"},
  };
  for (const Case &c : cases) {
    runanywhere::v1::RegisterModelFromUrlRequest request;
    request.set_url(c.in);
    const std::string bytes = rcli::proto::serialize(request);

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    const rac_result_t rc = rac_register_model_from_url_proto(
        reinterpret_cast<const uint8_t *>(bytes.data()), bytes.size(), &out);
    runanywhere::v1::ModelInfo saved;
    std::string parse_error;
    const bool parsed = rc == RAC_SUCCESS && rcli::proto::parse_proto_buffer(
                                                 &out, &saved, &parse_error);
    if (!parsed) {
      result.expected = c.expected_download_url;
      result.actual = "<registration failed rc=" + std::to_string(rc) + ">";
      result.details = "input: " + c.in + " " + parse_error;
      return result;
    }
    if (saved.download_url() != c.expected_download_url) {
      result.expected = c.expected_download_url;
      result.actual =
          saved.download_url().empty() ? "<empty>" : saved.download_url();
      result.details = "input: " + c.in;
      return result;
    }
  }
  result.passed = true;
  return result;
}

} // namespace

int main(int argc, char **argv) {
  TestSuite suite("rcli_unit");
  suite.add("json_escape", test_json_escape);
  suite.add("json_writer_shape", test_json_writer_shape);
  suite.add("human_bytes", test_human_bytes);
  suite.add("normalize_dir", test_normalize_dir);
  suite.add("resolve_home_precedence", test_resolve_home_precedence);
  suite.add("state_dir", test_state_dir);
  suite.add("catalog_lookup", test_catalog_lookup);
  suite.add("engine_hint_parsing", test_engine_hint_parsing);
  suite.add("mlx_catalog_registration", test_mlx_catalog_registration);
  suite.add("hf_ref_registration", test_hf_ref_registration);
  return suite.run(argc, argv);
}
