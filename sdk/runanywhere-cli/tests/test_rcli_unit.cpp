/**
 * @file test_rcli_unit.cpp
 * @brief rcli unit tests — pure helpers, no models, no network.
 *
 * Uses the commons TestSuite harness so the Docker rig and ctest drive every
 * suite the same way (--run-all / --test-<name>).
 */

#include "test_common.h"

#include <cstdlib>
#include <initializer_list>
#include <string>
#include <vector>

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
#if defined(_WIN32)
      _putenv_s(name, value);
#else
      setenv(name, value, 1);
#endif
    } else {
#if defined(_WIN32)
      _putenv_s(name, "");
#else
      unsetenv(name);
#endif
    }
  }
  ~EnvVar() {
    if (had_prev_) {
#if defined(_WIN32)
      _putenv_s(name_.c_str(), prev_.c_str());
#else
      setenv(name_.c_str(), prev_.c_str(), 1);
#endif
    } else {
#if defined(_WIN32)
      _putenv_s(name_.c_str(), "");
#else
      unsetenv(name_.c_str());
#endif
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
  json.end_array();
  json.begin_array("scores").value(1.0).value(0.5).end_array();
  json.end_object();

  const std::string expected =
      R"({"name":"qwen3-0.6b","size":640,"downloaded":true,)"
      R"("files":[{"path":"a.gguf"},{"path":"b.gguf"}],)"
      R"("scores":[1,0.5]})";
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
#if defined(_WIN32)
    EnvVar local("LOCALAPPDATA", "C:/rcli-local");
    const std::string home = rcli::paths::resolve_home("");
    if (home != "C:/rcli-local/RunAnywhere") {
      result.details = "expected C:/rcli-local/RunAnywhere, got " + home;
      return result;
    }
#else
    EnvVar xdg("XDG_DATA_HOME", "/xdg-data");
    const std::string home = rcli::paths::resolve_home("");
    if (home != "/xdg-data/runanywhere") {
      result.details = "expected /xdg-data/runanywhere, got " + home;
      return result;
    }
#endif
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

  const rcli::catalog::CatalogEntry *mlx_llm = rcli::catalog::find("mlx-qwen3");
  if (!mlx_llm ||
      mlx_llm->framework != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      mlx_llm->format != runanywhere::v1::MODEL_FORMAT_SAFETENSORS ||
      mlx_llm->category != runanywhere::v1::MODEL_CATEGORY_LANGUAGE ||
      mlx_llm->files == nullptr || mlx_llm->file_count != 9 ||
      !mlx_llm->supports_thinking) {
    result.details = "mlx-qwen3 should be a complete MLX language bundle";
    return result;
  }

  const rcli::catalog::CatalogEntry *mlx_vlm =
      rcli::catalog::find("mlx-qwen2-vl");
  if (!mlx_vlm ||
      mlx_vlm->category != runanywhere::v1::MODEL_CATEGORY_MULTIMODAL ||
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
    result.details =
        "MLX VLM catalog entry must include preprocessor_config.json";
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
    result.details = "MLX FastVLM catalog entry must include processor config "
                     "and companions";
    return result;
  }

  const rcli::catalog::CatalogEntry *mlx_embed =
      rcli::catalog::find("mlx-qwen3-embed");
  if (!mlx_embed ||
      mlx_embed->category != runanywhere::v1::MODEL_CATEGORY_EMBEDDING ||
      mlx_embed->framework != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      mlx_embed->files == nullptr || mlx_embed->file_count != 11) {
    result.details =
        "mlx-qwen3-embed should be a complete MLX embedding bundle";
    return result;
  }

  struct PortableNvidiaEmbeddingCase {
    const char *id;
    const char *alias;
    const char *revision;
    int64_t download_size_bytes;
  };
  const PortableNvidiaEmbeddingCase portable_nvidia_embeddings[] = {
      {"nemotron-3-embed-1b-q4_k_m", "nemotron-3-embed",
       "06df1fde6f7009c91f6cc3cd520081921929a678", 749352096LL},
      {"llama-nemotron-embed-1b-v2-q4_k_m", "llama-nemotron-embed",
       "bf7c9832b1d76f86777379e58b7b74805ee58006", 807690624LL},
  };
  for (const PortableNvidiaEmbeddingCase &test_case :
       portable_nvidia_embeddings) {
    const rcli::catalog::CatalogEntry *entry =
        rcli::catalog::find(test_case.id);
    if (!entry || entry != rcli::catalog::find(test_case.alias) ||
        entry->category != runanywhere::v1::MODEL_CATEGORY_EMBEDDING ||
        entry->framework != runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP ||
        entry->format != runanywhere::v1::MODEL_FORMAT_GGUF ||
        entry->files != nullptr || entry->url == nullptr ||
        entry->download_size_bytes != test_case.download_size_bytes ||
        std::string(entry->url).find(test_case.revision) == std::string::npos) {
      result.details = std::string(test_case.id) +
                       " should be an exact pinned llama.cpp embedding";
      return result;
    }
  }

  const rcli::catalog::CatalogEntry *nemotron_nano =
      rcli::catalog::find("mlx-nemotron-nano");
  if (!nemotron_nano ||
      nemotron_nano->category != runanywhere::v1::MODEL_CATEGORY_LANGUAGE ||
      nemotron_nano->framework != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      nemotron_nano->files == nullptr || nemotron_nano->file_count != 8 ||
      nemotron_nano->download_size_bytes != 4534806075LL ||
      nemotron_nano->context_length != 131072) {
    result.details = "mlx-nemotron-nano should be a complete pinned MLX bundle";
    return result;
  }

  const rcli::catalog::CatalogEntry *nemotron_mini =
      rcli::catalog::find("mlx-nemotron-mini");
  if (!nemotron_mini ||
      nemotron_mini->category != runanywhere::v1::MODEL_CATEGORY_LANGUAGE ||
      nemotron_mini->framework != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      nemotron_mini->format != runanywhere::v1::MODEL_FORMAT_SAFETENSORS ||
      nemotron_mini->files == nullptr || nemotron_mini->file_count != 6 ||
      nemotron_mini->download_size_bytes != 2392679103LL ||
      nemotron_mini->context_length != 4096) {
    result.details = "mlx-nemotron-mini should be a complete pinned MLX bundle";
    return result;
  }
  for (size_t i = 0; i < nemotron_mini->file_count; ++i) {
    if (std::string(nemotron_mini->files[i].url)
            .find("/resolve/b5784198153d2d71afcc97d4cc38c049abced8cd/") ==
        std::string::npos) {
      result.details = "mlx-nemotron-mini files must use the pinned revision";
      return result;
    }
  }

  struct NvidiaSpeechCase {
    const char *alias;
    int64_t download_size_bytes;
  };
  const NvidiaSpeechCase nvidia_speech_cases[] = {
      {"mlx-parakeet-ctc", 4250718357LL},
      {"mlx-parakeet-tdt-v2", 2471596080LL},
      {"mlx-parakeet-tdt-v3", 2508532829LL},
      {"mlx-parakeet-rnnt", 4282283914LL},
      {"mlx-nemotron-asr", 755758528LL},
  };
  for (const NvidiaSpeechCase &test_case : nvidia_speech_cases) {
    const rcli::catalog::CatalogEntry *entry =
        rcli::catalog::find(test_case.alias);
    if (!entry ||
        entry->category != runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION ||
        entry->framework != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
        entry->format != runanywhere::v1::MODEL_FORMAT_SAFETENSORS ||
        entry->files == nullptr || entry->file_count != 2 ||
        entry->download_size_bytes != test_case.download_size_bytes ||
        std::string(entry->files[0].url).find("/resolve/") ==
            std::string::npos) {
      result.details = std::string(test_case.alias) +
                       " should be a complete pinned MLX speech bundle";
      return result;
    }
  }

  result.passed = true;
  return result;
}

TestResult test_nvidia_sherpa_catalog() {
  TestResult result;
  result.test_name = "nvidia_sherpa_catalog";

  struct ExpectedFile {
    const char *filename;
    int64_t size_bytes;
  };
  constexpr ExpectedFile parakeet_v2_files[] = {
      {"encoder.int8.onnx", 652184296LL},
      {"decoder.int8.onnx", 7257753LL},
      {"joiner.int8.onnx", 1739080LL},
      {"tokens.txt", 9384LL},
  };
  constexpr ExpectedFile parakeet_v3_files[] = {
      {"encoder.int8.onnx", 652184281LL},
      {"decoder.int8.onnx", 11845275LL},
      {"joiner.int8.onnx", 6355277LL},
      {"tokens.txt", 93939LL},
  };
  constexpr ExpectedFile canary_files[] = {
      {"encoder.int8.onnx", 132678643LL},
      {"decoder.int8.onnx", 74437848LL},
      {"tokens.txt", 53555LL},
  };

  struct Case {
    const char *id;
    const char *alias;
    const char *repo;
    const char *revision;
    const ExpectedFile *files;
    size_t file_count;
    int64_t total_size_bytes;
  };
  const Case cases[] = {
      {"sherpa-nemo-parakeet-tdt-0.6b-v2-int8", "parakeet-tdt-v2",
       "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8",
       "1ab9323565ddb038682214b292f588070a538ce2", parakeet_v2_files, 4,
       661190513LL},
      {"sherpa-nemo-parakeet-tdt-0.6b-v3-int8", "parakeet-tdt-v3",
       "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
       "2bda32ec70b097a55adaa07d9a7173915b43cc78", parakeet_v3_files, 4,
       670478772LL},
      {"sherpa-nemo-canary-180m-flash-int8", "canary-180m",
       "csukuangfj/sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8",
       "9077164e0d3dd1d5353743e89ceaa1d3a770838c", canary_files, 3,
       207170046LL},
  };

  for (const Case &test_case : cases) {
    const rcli::catalog::CatalogEntry *entry =
        rcli::catalog::find(test_case.id);
    if (!entry || entry != rcli::catalog::find(test_case.alias)) {
      result.details =
          std::string(test_case.id) + " should resolve by exact id and alias";
      return result;
    }
    if (entry->category != runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION ||
        entry->framework != runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA ||
        entry->format != runanywhere::v1::MODEL_FORMAT_ONNX ||
        entry->url != nullptr || entry->files == nullptr ||
        entry->file_count != test_case.file_count ||
        entry->download_size_bytes != test_case.total_size_bytes) {
      result.details = std::string(test_case.id) +
                       " should be an exact Sherpa-ONNX STT bundle";
      return result;
    }

    const std::string base_url = std::string("https://huggingface.co/") +
                                 test_case.repo + "/resolve/" +
                                 test_case.revision + "/";
    int64_t manifest_total = 0;
    for (size_t i = 0; i < test_case.file_count; ++i) {
      const rcli::catalog::CatalogFile &actual = entry->files[i];
      const ExpectedFile &expected = test_case.files[i];
      const std::string expected_url = base_url + expected.filename;
      if (actual.url == nullptr || actual.filename == nullptr ||
          std::string(actual.url) != expected_url ||
          std::string(actual.filename) != expected.filename ||
          !actual.required || actual.size_bytes != expected.size_bytes) {
        result.details = std::string(test_case.id) +
                         " has a mismatched pinned file manifest at index " +
                         std::to_string(i);
        return result;
      }
      manifest_total += actual.size_bytes;
    }
    if (manifest_total != test_case.total_size_bytes) {
      result.details = std::string(test_case.id) +
                       " per-file sizes should sum to the exact bundle total";
      return result;
    }
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

class RegisteredModelCleanup {
public:
  RegisteredModelCleanup(std::initializer_list<const char *> ids) {
    ids_.reserve(ids.size());
    for (const char *id : ids) {
      ids_.emplace_back(id);
    }
  }

  ~RegisteredModelCleanup() {
    for (const auto &id : ids_) {
      remove_registered_model(id);
    }
  }

private:
  std::vector<std::string> ids_;
};

bool get_registered_model(const std::string &id,
                          runanywhere::v1::ModelInfo *out, std::string *error) {
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
  RegisteredModelCleanup cleanup({
      "mlx-qwen3-0.6b-4bit",
      "mlx-llama-3.2-1b-instruct-4bit",
      "mlx-qwen2-vl-2b-instruct-4bit",
      "mlx-fastvlm-0.5b-bf16",
      "mlx-qwen3-embedding-0.6b-4bit-dwq",
      "mlx-qwen3-asr-0.6b-8bit",
      "mlx-glm-asr-nano-2512-4bit",
      "mlx-llama-3.1-nemotron-nano-8b-v1-4bit",
      "mlx-nemotron-mini-4b-instruct-4bit",
      "mlx-parakeet-ctc-1.1b",
      "mlx-parakeet-tdt-0.6b-v2",
      "mlx-parakeet-tdt-0.6b-v3",
      "mlx-parakeet-rnnt-1.1b",
      "mlx-nemotron-3.5-asr-streaming-0.6b-8bit",
      "mlx-qwen3-tts-12hz-0.6b-base-8bit",
      "mlx-soprano-1.1-80m-5bit",
      "sherpa-nemo-parakeet-tdt-0.6b-v2-int8",
      "sherpa-nemo-parakeet-tdt-0.6b-v3-int8",
      "sherpa-nemo-canary-180m-flash-int8",
  });

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
    preprocessor_registered = preprocessor_registered ||
                              file.filename() == "preprocessor_config.json";
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
        (!file.is_required() && (file.filename() == "processing_fastvlm.py" ||
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
      !embedding.has_multi_file() ||
      embedding.multi_file().files_size() != 11) {
    result.details = "registered MLX embedding metadata is incomplete";
    return result;
  }

  runanywhere::v1::ModelInfo qwen_asr;
  if (!get_registered_model("mlx-qwen3-asr-0.6b-8bit", &qwen_asr, &error) ||
      qwen_asr.category() !=
          runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION ||
      qwen_asr.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      !qwen_asr.has_multi_file() || qwen_asr.multi_file().files_size() != 9) {
    result.details = "registered MLX Qwen3-ASR metadata is incomplete";
    return result;
  }

  runanywhere::v1::ModelInfo glm_asr;
  if (!get_registered_model("mlx-glm-asr-nano-2512-4bit", &glm_asr, &error) ||
      glm_asr.category() !=
          runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION ||
      glm_asr.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      !glm_asr.has_multi_file() || glm_asr.multi_file().files_size() != 9) {
    result.details = "registered MLX GLM-ASR metadata is incomplete";
    return result;
  }

  struct RegisteredNvidiaCase {
    const char *id;
    int expected_files;
    int64_t expected_size;
  };
  const RegisteredNvidiaCase registered_nvidia_cases[] = {
      {"mlx-llama-3.1-nemotron-nano-8b-v1-4bit", 8, 4534806075LL},
      {"mlx-nemotron-mini-4b-instruct-4bit", 6, 2392679103LL},
      {"mlx-parakeet-ctc-1.1b", 2, 4250718357LL},
      {"mlx-parakeet-tdt-0.6b-v2", 2, 2471596080LL},
      {"mlx-parakeet-tdt-0.6b-v3", 2, 2508532829LL},
      {"mlx-parakeet-rnnt-1.1b", 2, 4282283914LL},
      {"mlx-nemotron-3.5-asr-streaming-0.6b-8bit", 2, 755758528LL},
  };
  for (const RegisteredNvidiaCase &test_case : registered_nvidia_cases) {
    runanywhere::v1::ModelInfo model;
    if (!get_registered_model(test_case.id, &model, &error) ||
        model.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
        model.format() != runanywhere::v1::MODEL_FORMAT_SAFETENSORS ||
        !model.has_multi_file() ||
        model.multi_file().files_size() != test_case.expected_files ||
        model.download_size_bytes() != test_case.expected_size) {
      result.details =
          std::string("registered NVIDIA MLX metadata is incomplete: ") +
          test_case.id;
      return result;
    }
  }

  struct RegisteredSherpaCase {
    const char *id;
    int expected_files;
    int64_t expected_size;
  };
  const RegisteredSherpaCase registered_sherpa_cases[] = {
      {"sherpa-nemo-parakeet-tdt-0.6b-v2-int8", 4, 661190513LL},
      {"sherpa-nemo-parakeet-tdt-0.6b-v3-int8", 4, 670478772LL},
      {"sherpa-nemo-canary-180m-flash-int8", 3, 207170046LL},
  };
  for (const RegisteredSherpaCase &test_case : registered_sherpa_cases) {
    runanywhere::v1::ModelInfo model;
    if (!get_registered_model(test_case.id, &model, &error) ||
        model.category() !=
            runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION ||
        model.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA ||
        model.format() != runanywhere::v1::MODEL_FORMAT_ONNX ||
        !model.has_multi_file() ||
        model.multi_file().files_size() != test_case.expected_files ||
        model.download_size_bytes() != test_case.expected_size) {
      result.details =
          std::string("registered NVIDIA Sherpa metadata is incomplete: ") +
          test_case.id;
      return result;
    }
    int64_t registered_file_total = 0;
    for (const auto &file : model.multi_file().files()) {
      if (!file.has_size_bytes() || file.size_bytes() <= 0) {
        result.details =
            std::string("registered NVIDIA Sherpa file size is missing: ") +
            test_case.id;
        return result;
      }
      registered_file_total += file.size_bytes();
    }
    if (registered_file_total != test_case.expected_size) {
      result.details =
          std::string("registered NVIDIA Sherpa file sizes do not sum: ") +
          test_case.id;
      return result;
    }
  }

  runanywhere::v1::ModelInfo qwen_tts;
  if (!get_registered_model("mlx-qwen3-tts-12hz-0.6b-base-8bit", &qwen_tts,
                            &error) ||
      qwen_tts.category() != runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS ||
      qwen_tts.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      !qwen_tts.has_multi_file() || qwen_tts.multi_file().files_size() != 12) {
    result.details = "registered MLX Qwen3-TTS metadata is incomplete";
    return result;
  }

  runanywhere::v1::ModelInfo soprano;
  if (!get_registered_model("mlx-soprano-1.1-80m-5bit", &soprano, &error) ||
      soprano.category() != runanywhere::v1::MODEL_CATEGORY_SPEECH_SYNTHESIS ||
      soprano.framework() != runanywhere::v1::INFERENCE_FRAMEWORK_MLX ||
      !soprano.has_multi_file() || soprano.multi_file().files_size() != 7) {
    result.details = "registered MLX Soprano metadata is incomplete";
    return result;
  }

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
      {"https://huggingface.co/org/repo/blob/main/sub/f.gguf",
       "https://huggingface.co/org/repo/resolve/main/sub/f.gguf"},
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
  suite.add("nvidia_sherpa_catalog", test_nvidia_sherpa_catalog);
  suite.add("engine_hint_parsing", test_engine_hint_parsing);
  suite.add("mlx_catalog_registration", test_mlx_catalog_registration);
  suite.add("hf_ref_registration", test_hf_ref_registration);
  return suite.run(argc, argv);
}
