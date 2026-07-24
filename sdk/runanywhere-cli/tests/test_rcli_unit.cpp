/**
 * @file test_rcli_unit.cpp
 * @brief rcli unit tests — pure helpers, no models, no network.
 *
 * Uses the commons TestSuite harness so the Docker rig and ctest drive every
 * suite the same way (--run-all / --test-<name>).
 */

#include "test_common.h"

#include <CLI11.hpp>

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <initializer_list>
#include <string>
#include <system_error>
#include <vector>

#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "app.h"
#include "catalog/catalog.h"
#include "catalog/model_ref.h"
#include "commands/engine_options.h"
#include "config/cli_paths.h"
#include "io/image_io.h"
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
      {"llama-embed-nemotron-8b-q4_k_m", "llama-embed-nemotron",
       "e7ae3cbae4f7693bbd75ec959bf293f39e1f2e25", 4625233184LL},
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

  const rcli::catalog::CatalogEntry *parakeet_ctc =
      rcli::catalog::find("sherpa-nemo-parakeet-ctc-1.1b-int8");
  if (!parakeet_ctc || parakeet_ctc != rcli::catalog::find("parakeet-ctc") ||
      parakeet_ctc->category !=
          runanywhere::v1::MODEL_CATEGORY_SPEECH_RECOGNITION ||
      parakeet_ctc->framework != runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA ||
      parakeet_ctc->format != runanywhere::v1::MODEL_FORMAT_ONNX ||
      parakeet_ctc->url != nullptr || parakeet_ctc->files == nullptr ||
      parakeet_ctc->file_count != 2 ||
      parakeet_ctc->download_size_bytes != 1110024519LL ||
      parakeet_ctc->memory_required_bytes != 2147483648LL) {
    result.details = "Parakeet CTC should be an exact Sherpa-ONNX bundle";
    return result;
  }

  const std::string base_url = "https://huggingface.co/OpenVoiceOS/"
                               "nvidia-parakeet-ctc-1.1b-onnx/resolve/"
                               "3ca664a2f106622d599052b4e4ecee5fdfc7e2e5/";
  const rcli::catalog::CatalogFile &model = parakeet_ctc->files[0];
  const rcli::catalog::CatalogFile &tokens = parakeet_ctc->files[1];
  if (std::string(model.url) != base_url + "model.int8.onnx" ||
      std::string(model.filename) != "model.int8.onnx" || !model.required ||
      model.size_bytes != 1110014145LL || model.checksum_sha256 == nullptr ||
      std::string(model.checksum_sha256) !=
          "62f73c17a5301c048c7273cf24ef1cd0c3621d3625c5415fbafe5633d7bf2f98" ||
      model.append_bytes_transform == nullptr) {
    result.details = "Parakeet CTC final model descriptor is not exact";
    return result;
  }
  const rcli::catalog::CatalogAppendBytesTransform &transform =
      *model.append_bytes_transform;
  std::string payload_hex;
  constexpr char kHexDigits[] = "0123456789abcdef";
  for (size_t i = 0; i < transform.payload_size; ++i) {
    const auto byte = static_cast<unsigned char>(transform.payload[i]);
    payload_hex.push_back(kHexDigits[byte >> 4]);
    payload_hex.push_back(kHexDigits[byte & 0x0f]);
  }
  if (transform.source_size_bytes != 1110014069LL ||
      transform.source_checksum_sha256 == nullptr ||
      std::string(transform.source_checksum_sha256) !=
          "a16056c0a0d8df38c7b57cb019062df116e9e565203c6f25d6ea0c0c1122c84d" ||
      transform.payload_size != 76 ||
      payload_hex !=
          "72120a0a766f6361625f73697a6512043130323572170a1273756273616d706c"
          "696e675f666163746f72120138721d0a0e6e6f726d616c697a655f7479706512"
          "0b7065725f66656174757265") {
    result.details = "Parakeet CTC source transform is not exact";
    return result;
  }
  if (std::string(tokens.url) != base_url + "vocab.txt" ||
      std::string(tokens.filename) != "tokens.txt" || !tokens.required ||
      tokens.size_bytes != 10374LL || tokens.checksum_sha256 == nullptr ||
      std::string(tokens.checksum_sha256) !=
          "ed16e1a4e3a3aa379138c0b1888e5d49f993c9d512b2be4d46e90a87afd54921" ||
      tokens.append_bytes_transform != nullptr) {
    result.details = "Parakeet CTC vocabulary rename/checksum is not exact";
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
      "sherpa-nemo-parakeet-ctc-1.1b-int8",
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
      {"sherpa-nemo-parakeet-ctc-1.1b-int8", 2, 1110024519LL},
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

  runanywhere::v1::ModelInfo parakeet_ctc;
  if (!get_registered_model("sherpa-nemo-parakeet-ctc-1.1b-int8", &parakeet_ctc,
                            &error)) {
    result.details = "registered Parakeet CTC metadata is missing: " + error;
    return result;
  }
  const runanywhere::v1::ModelFileDescriptor *registered_model = nullptr;
  const runanywhere::v1::ModelFileDescriptor *registered_tokens = nullptr;
  for (const auto &file : parakeet_ctc.multi_file().files()) {
    if (file.filename() == "model.int8.onnx") {
      registered_model = &file;
    } else if (file.filename() == "tokens.txt") {
      registered_tokens = &file;
    }
  }
  if (registered_model == nullptr || registered_tokens == nullptr ||
      registered_model->url() !=
          "https://huggingface.co/OpenVoiceOS/"
          "nvidia-parakeet-ctc-1.1b-onnx/resolve/"
          "3ca664a2f106622d599052b4e4ecee5fdfc7e2e5/model.int8.onnx" ||
      !registered_model->has_size_bytes() ||
      registered_model->size_bytes() != 1110014145LL ||
      !registered_model->has_checksum_sha256() ||
      registered_model->checksum_sha256() !=
          "62f73c17a5301c048c7273cf24ef1cd0c3621d3625c5415fbafe5633d7bf2f98" ||
      !registered_model->has_post_download_transform() ||
      !parakeet_ctc.has_memory_required_bytes() ||
      parakeet_ctc.memory_required_bytes() != 2147483648LL) {
    result.details =
        "registered Parakeet CTC final descriptor tuple is incomplete";
    return result;
  }
  const auto &registered_transform =
      registered_model->post_download_transform();
  const rcli::catalog::CatalogEntry *catalog_entry =
      rcli::catalog::find("sherpa-nemo-parakeet-ctc-1.1b-int8");
  const auto *catalog_transform =
      catalog_entry == nullptr ? nullptr
                               : catalog_entry->files[0].append_bytes_transform;
  if (catalog_transform == nullptr ||
      registered_transform.source_size_bytes() != 1110014069LL ||
      registered_transform.source_checksum_sha256() !=
          "a16056c0a0d8df38c7b57cb019062df116e9e565203c6f25d6ea0c0c1122c84d" ||
      registered_transform.final_size_bytes() != 1110014145LL ||
      registered_transform.final_checksum_sha256() !=
          "62f73c17a5301c048c7273cf24ef1cd0c3621d3625c5415fbafe5633d7bf2f98" ||
      registered_transform.operations_size() != 1 ||
      !registered_transform.operations(0).has_append_bytes() ||
      registered_transform.operations(0).append_bytes().payload() !=
          std::string(catalog_transform->payload,
                      catalog_transform->payload_size)) {
    result.details =
        "registered Parakeet CTC source transform tuple is incomplete";
    return result;
  }
  if (registered_tokens->url() !=
          "https://huggingface.co/OpenVoiceOS/"
          "nvidia-parakeet-ctc-1.1b-onnx/resolve/"
          "3ca664a2f106622d599052b4e4ecee5fdfc7e2e5/vocab.txt" ||
      !registered_tokens->has_size_bytes() ||
      registered_tokens->size_bytes() != 10374LL ||
      !registered_tokens->has_checksum_sha256() ||
      registered_tokens->checksum_sha256() !=
          "ed16e1a4e3a3aa379138c0b1888e5d49f993c9d512b2be4d46e90a87afd54921" ||
      registered_tokens->has_post_download_transform()) {
    result.details =
        "registered Parakeet CTC token rename/checksum is incomplete";
    return result;
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

// ---------------------------------------------------------------------------
// diarize command coverage
//
// These tests exercise register_diarize()'s argv surface WITHOUT reaching the
// CLI11 callback (which would fire run_diarize -> bootstrap + a real ONNX
// Sortformer model). Two inference-free strategies are used:
//   1. Pure introspection: configure_app() then query the CLI11 App/Option
//      model -- never parse, never run a callback.
//   2. Parse-FAILURE paths via rcli::run(): a usage error makes CLI11 throw a
//      ParseError inside parse(), before any callback, and src/app.cpp maps
//      every ParseError to the production exit code 2 (0 ok, 1 runtime, 2
//      usage).
// The --json / table render path (print_result) has internal linkage and needs
// a real model, so it is intentionally not covered here.
// ---------------------------------------------------------------------------

// RAII zero-byte temp file. A zero-byte regular file satisfies
// CLI::ExistingFile (WAV validity is only checked later, inside run_diarize,
// which a parse-error path never reaches).
class TempWavFile {
public:
  TempWavFile() {
    namespace fs = std::filesystem;
    static int counter = 0;
    path_ = (fs::temp_directory_path() /
             ("rcli_diarize_test_" + std::to_string(++counter) + ".wav"))
                .string();
    std::ofstream(path_).close();
  }
  ~TempWavFile() {
    std::error_code ec;
    std::filesystem::remove(path_, ec);
  }
  const std::string &path() const { return path_; }

private:
  std::string path_;
};

// Drive the production entry point rcli::run() with an argv vector. run() builds
// its own App + GlobalOptions, so a usage error returns the true production exit
// code (2) without any bootstrap or inference.
int run_rcli(const std::vector<std::string> &args) {
  std::vector<std::string> mutable_args = args;
  std::vector<char *> argv;
  argv.reserve(mutable_args.size());
  for (std::string &arg : mutable_args) {
    argv.push_back(arg.data());
  }
  return rcli::run(static_cast<int>(argv.size()), argv.data());
}

TestResult test_diarize_arg_surface() {
  TestResult result;
  result.test_name = "diarize_arg_surface";

  rcli::GlobalOptions options;
  CLI::App app{"rcli test app"};
  rcli::configure_app(app, options);

  const CLI::App *cmd = app.get_subcommand_no_throw("diarize");
  if (cmd == nullptr) {
    result.details = "diarize subcommand not registered";
    return result;
  }
  if (cmd->get_description() !=
      "Speaker diarization of a WAV file (who spoke when)") {
    result.expected = "Speaker diarization of a WAV file (who spoke when)";
    result.actual = cmd->get_description();
    return result;
  }

  const CLI::Option *audio = cmd->get_option_no_throw("audio");
  if (audio == nullptr || !audio->get_required()) {
    result.details = "positional 'audio' must exist and be required";
    return result;
  }

  const CLI::Option *model = cmd->get_option_no_throw("--model");
  if (model == nullptr || !model->get_required() || !model->check_name("-m")) {
    result.details = "--model must exist, be required, and carry the -m alias";
    return result;
  }

  const char *optional_flags[] = {"--threshold", "--min-duration",
                                  "--merge-gap"};
  for (const char *name : optional_flags) {
    const CLI::Option *opt = cmd->get_option_no_throw(name);
    if (opt == nullptr) {
      result.details = std::string("missing option ") + name;
      return result;
    }
    if (opt->get_required()) {
      result.details = std::string(name) + " must not be required";
      return result;
    }
  }

  result.passed = true;
  return result;
}

TestResult test_diarize_missing_model_exit2() {
  TestResult result;
  result.test_name = "diarize_missing_model_exit2";

  // audio positional satisfied by an existing temp file -> the only failure is
  // the missing required --model (RequiredError -> ParseError -> exit 2).
  TempWavFile audio;
  const int code = run_rcli({"rcli", "diarize", audio.path()});
  if (code != 2) {
    result.expected = "2";
    result.actual = std::to_string(code);
    result.details = "missing required --model should be a usage error";
    return result;
  }
  result.passed = true;
  return result;
}

TestResult test_diarize_missing_audio_exit2() {
  TestResult result;
  result.test_name = "diarize_missing_audio_exit2";

  // --model consumes "x"; the required audio positional is left unsatisfied
  // (RequiredError -> ParseError -> exit 2).
  const int code = run_rcli({"rcli", "diarize", "--model", "x"});
  if (code != 2) {
    result.expected = "2";
    result.actual = std::to_string(code);
    result.details =
        "missing required audio positional should be a usage error";
    return result;
  }
  result.passed = true;
  return result;
}

TestResult test_diarize_audio_not_found_exit2() {
  TestResult result;
  result.test_name = "diarize_audio_not_found_exit2";

  // --model is supplied so the sole failure is the audio ->check(ExistingFile)
  // validator (ValidationError -> ParseError -> exit 2), a distinct path from a
  // plain RequiredError.
  const int code = run_rcli(
      {"rcli", "diarize", "/no/such/rcli-diarize-input.wav", "--model", "x"});
  if (code != 2) {
    result.expected = "2";
    result.actual = std::to_string(code);
    result.details =
        "non-existent audio should fail CLI::ExistingFile (usage error)";
    return result;
  }
  result.passed = true;
  return result;
}

TestResult test_diarize_numeric_option_typing_exit2() {
  TestResult result;
  result.test_name = "diarize_numeric_option_typing_exit2";

  // A non-numeric value for a typed numeric option raises CLI11 ConversionError
  // (a ParseError) during parse, before the callback -> exit 2. This is the
  // only inference-free way to prove --threshold binds to a float and
  // --min-duration/--merge-gap bind to integers (a *valid* value would run the
  // callback and load a model). Required args are satisfied so the conversion
  // is the only failure.
  TempWavFile audio;
  const char *numeric_flags[] = {"--threshold", "--min-duration",
                                 "--merge-gap"};
  for (const char *flag : numeric_flags) {
    const int code = run_rcli(
        {"rcli", "diarize", audio.path(), "--model", "x", flag, "notanumber"});
    if (code != 2) {
      result.expected = "2";
      result.actual = std::to_string(code);
      result.details =
          std::string("non-numeric ") + flag + " should be a usage error";
      return result;
    }
  }
  result.passed = true;
  return result;
}

TestResult test_diarize_unknown_flag_exit2() {
  TestResult result;
  result.test_name = "diarize_unknown_flag_exit2";

  // An unrecognized option is not consumed by the subcommand or (via
  // fallthrough) the parent, so parse ends with an ExtrasError (ParseError) ->
  // exit 2. Guards against silently-ignored typos.
  TempWavFile audio;
  const int code =
      run_rcli({"rcli", "diarize", audio.path(), "--model", "x", "--bogus"});
  if (code != 2) {
    result.expected = "2";
    result.actual = std::to_string(code);
    result.details = "unrecognized flag should be a usage error (ExtrasError)";
    return result;
  }
  result.passed = true;
  return result;
}

// ===========================================================================
// image_io helpers (write_png / read_ppm) — the segment command's PNG encoder
// and PPM decoder. Pure file-path helpers, exercised via temp files (write_png
// and read_ppm operate on paths via fopen, not injectable streams). Offline,
// model-free, deterministic. See src/io/image_io.{h,cpp}.
// ===========================================================================

// Unique path under the system temp dir; RAII removes it recursively on scope
// exit (recursive so it also covers the never-created parent dirs used by the
// unwritable-path case). Mirrors make_temp_dir() in test_rcli_mlx_e2e.cpp.
std::string unique_temp_path(const std::string &name) {
  static uint64_t counter = 0;
  const auto stamp =
      std::chrono::steady_clock::now().time_since_epoch().count();
  return (std::filesystem::temp_directory_path() /
          (name + "-" + std::to_string(stamp) + "-" +
           std::to_string(counter++)))
      .string();
}

class TempFile {
public:
  explicit TempFile(const std::string &name) : path_(unique_temp_path(name)) {}
  ~TempFile() {
    std::error_code ec;
    std::filesystem::remove_all(path_, ec);
  }
  TempFile(const TempFile &) = delete;
  TempFile &operator=(const TempFile &) = delete;
  const std::string &path() const { return path_; }

private:
  std::string path_;
};

std::vector<uint8_t> bytes_of(const std::string &s) {
  return std::vector<uint8_t>(s.begin(), s.end());
}

bool write_bytes(const std::string &path, const std::vector<uint8_t> &bytes) {
  std::ofstream out(path, std::ios::binary);
  if (!out.is_open()) {
    return false;
  }
  if (!bytes.empty()) {
    out.write(reinterpret_cast<const char *>(bytes.data()),
              static_cast<std::streamsize>(bytes.size()));
  }
  return out.good();
}

bool read_bytes(const std::string &path, std::vector<uint8_t> *bytes) {
  std::ifstream in(path, std::ios::binary);
  if (!in.is_open()) {
    return false;
  }
  in.seekg(0, std::ios::end);
  const std::streamoff size = in.tellg();
  if (size < 0) {
    return false;
  }
  in.seekg(0, std::ios::beg);
  bytes->resize(static_cast<size_t>(size));
  if (size > 0) {
    in.read(reinterpret_cast<char *>(bytes->data()),
            static_cast<std::streamsize>(size));
  }
  return in.good() || in.eof();
}

// Build a valid P6 header ("P6\n<w> <h>\n255\n") followed by the raw pixels.
std::vector<uint8_t> make_ppm(uint32_t w, uint32_t h,
                              const std::vector<uint8_t> &pixels) {
  const std::string header =
      "P6\n" + std::to_string(w) + " " + std::to_string(h) + "\n255\n";
  std::vector<uint8_t> v(header.begin(), header.end());
  v.insert(v.end(), pixels.begin(), pixels.end());
  return v;
}

uint32_t read_u32_be(const std::vector<uint8_t> &b, size_t off) {
  return (static_cast<uint32_t>(b[off]) << 24) |
         (static_cast<uint32_t>(b[off + 1]) << 16) |
         (static_cast<uint32_t>(b[off + 2]) << 8) |
         static_cast<uint32_t>(b[off + 3]);
}

// Independent CRC-32 (PNG polynomial) — deliberately separate from the encoder's
// own implementation so a regression there cannot mask a regression here.
uint32_t test_crc32(const uint8_t *data, size_t len) {
  static uint32_t table[256];
  static bool ready = false;
  if (!ready) {
    for (uint32_t n = 0; n < 256u; ++n) {
      uint32_t c = n;
      for (int k = 0; k < 8; ++k) {
        c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
      }
      table[n] = c;
    }
    ready = true;
  }
  uint32_t crc = 0xFFFFFFFFu;
  for (size_t i = 0; i < len; ++i) {
    crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFFu;
}

// Independent Adler-32 (per-byte modulo form).
uint32_t test_adler32(const uint8_t *data, size_t len) {
  uint32_t a = 1;
  uint32_t b = 0;
  for (size_t i = 0; i < len; ++i) {
    a = (a + data[i]) % 65521u;
    b = (b + a) % 65521u;
  }
  return (b << 16) | a;
}

// Reconstruct the PNG filtered scanlines the encoder feeds into DEFLATE: a 0x00
// filter byte per row followed by that row's RGBA bytes.
std::vector<uint8_t> filtered_raw(const std::vector<uint8_t> &rgba, int width,
                                  int height) {
  const size_t row_bytes = static_cast<size_t>(width) * 4;
  std::vector<uint8_t> raw;
  raw.reserve(static_cast<size_t>(height) * (1 + row_bytes));
  for (int y = 0; y < height; ++y) {
    raw.push_back(0);
    const uint8_t *row = rgba.data() + static_cast<size_t>(y) * row_bytes;
    raw.insert(raw.end(), row, row + row_bytes);
  }
  return raw;
}

struct PngChunk {
  std::string type;
  std::vector<uint8_t> data;
  uint32_t stored_crc = 0;
  uint32_t computed_crc = 0;
};

// Parse the 8-byte signature + length/type/data/CRC chunk stream. Records both
// the stored CRC and an independently computed CRC over type+data per chunk.
bool parse_png(const std::vector<uint8_t> &png, std::vector<PngChunk> *out) {
  static const uint8_t sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
  if (png.size() < 8u || std::memcmp(png.data(), sig, 8) != 0) {
    return false;
  }
  size_t pos = 8;
  while (pos + 8 <= png.size()) {
    const uint32_t len = read_u32_be(png, pos);
    const size_t data_off = pos + 8;
    if (data_off + len + 4 > png.size()) {
      return false;
    }
    PngChunk c;
    c.type.assign(png.begin() + pos + 4, png.begin() + pos + 8);
    c.data.assign(png.begin() + data_off, png.begin() + data_off + len);
    c.stored_crc = read_u32_be(png, data_off + len);
    const std::vector<uint8_t> crc_input(png.begin() + pos + 4,
                                         png.begin() + data_off + len);
    c.computed_crc = test_crc32(crc_input.data(), crc_input.size());
    out->push_back(c);
    pos = data_off + len + 4;
  }
  return pos == png.size();
}

const PngChunk *find_chunk(const std::vector<PngChunk> &chunks,
                           const std::string &type) {
  for (const PngChunk &c : chunks) {
    if (c.type == type) {
      return &c;
    }
  }
  return nullptr;
}

// Parse a zlib stream (0x78 0x01 + stored DEFLATE blocks + 4-byte Adler-32).
struct ZlibParse {
  bool ok = false;
  std::vector<uint8_t> payload;
  int block_count = 0;
  bool bfinal_ok = false;  // BFINAL set on exactly the last block, none earlier
  bool lennlen_ok = true;  // NLEN == ~LEN for every block
  uint32_t adler = 0;
};

ZlibParse parse_stored_zlib(const std::vector<uint8_t> &z) {
  ZlibParse r;
  if (z.size() < 6u || z[0] != 0x78 || z[1] != 0x01) {
    return r;
  }
  const size_t adler_off = z.size() - 4;
  size_t pos = 2;
  std::vector<bool> finals;
  while (pos < adler_off) {
    if (adler_off - pos < 5u) {  // 1 header byte + LEN + NLEN
      return r;
    }
    const uint8_t hdr = z[pos];
    const uint8_t btype = static_cast<uint8_t>((hdr >> 1) & 0x03);
    if (btype != 0) {  // only stored (uncompressed) blocks are emitted
      return r;
    }
    const uint16_t len = static_cast<uint16_t>(z[pos + 1] | (z[pos + 2] << 8));
    const uint16_t nlen = static_cast<uint16_t>(z[pos + 3] | (z[pos + 4] << 8));
    if (static_cast<uint16_t>(~len) != nlen) {
      r.lennlen_ok = false;
    }
    const size_t data_off = pos + 5;
    if (data_off + len > adler_off) {
      return r;
    }
    r.payload.insert(r.payload.end(), z.begin() + data_off,
                     z.begin() + data_off + len);
    finals.push_back((hdr & 0x01) != 0);
    pos = data_off + len;
    ++r.block_count;
  }
  if (pos != adler_off) {
    return r;
  }
  r.bfinal_ok = !finals.empty() && finals.back();
  for (size_t i = 0; i + 1 < finals.size(); ++i) {
    if (finals[i]) {
      r.bfinal_ok = false;
    }
  }
  r.adler = (static_cast<uint32_t>(z[adler_off]) << 24) |
            (static_cast<uint32_t>(z[adler_off + 1]) << 16) |
            (static_cast<uint32_t>(z[adler_off + 2]) << 8) |
            static_cast<uint32_t>(z[adler_off + 3]);
  r.ok = true;
  return r;
}

TestResult test_read_ppm_errors() {
  TestResult result;
  result.test_name = "read_ppm_errors";

  auto with_pixels = [](const std::string &header, size_t n) {
    std::vector<uint8_t> v(header.begin(), header.end());
    for (size_t i = 0; i < n; ++i) {
      v.push_back(static_cast<uint8_t>(i));
    }
    return v;
  };

  struct Case {
    const char *label;
    bool create;                 // write `bytes` to a temp file first
    std::vector<uint8_t> bytes;  // file contents when create == true
    const char *expect_substr;
  };

  const std::vector<Case> cases = {
      {"missing file", false, {}, "cannot open"},
      {"ascii P3 magic", true, with_pixels("P3\n2 1\n255\n", 6),
       "is not a binary PPM (P6)"},
      {"one byte file", true, bytes_of("P"), "is not a binary PPM (P6)"},
      {"non-numeric dimension", true, bytes_of("P6\nxx 1\n255\n"),
       "malformed PPM header"},
      {"eof before maxval", true, bytes_of("P6\n2 1\n"),
       "malformed PPM header"},
      {"zero width", true, bytes_of("P6\n0 1\n255\n"), "unsupported PPM"},
      {"zero height", true, bytes_of("P6\n2 0\n255\n"), "unsupported PPM"},
      {"maxval 254", true, with_pixels("P6\n2 1\n254\n", 6),
       "unsupported PPM"},
      {"maxval 65535", true, with_pixels("P6\n2 1\n65535\n", 6),
       "unsupported PPM"},
      {"truncated payload", true, with_pixels("P6\n2 2\n255\n", 6),
       "truncated PPM pixel data"},
  };

  for (const Case &c : cases) {
    TempFile tf("rcli-ppm-err");
    if (c.create && !write_bytes(tf.path(), c.bytes)) {
      result.details = std::string("setup failed for case: ") + c.label;
      return result;
    }

    // Seed `out` with sentinels: a failed read must leave it untouched.
    rcli::image::RgbImage out;
    out.width = 12345u;
    out.height = 67890u;
    out.rgb = {9, 9, 9};

    std::string error;
    const bool ok = rcli::image::read_ppm(tf.path(), &out, &error);
    if (ok) {
      result.details = std::string("expected failure for case: ") + c.label;
      return result;
    }
    if (error.find(c.expect_substr) == std::string::npos) {
      result.expected = c.expect_substr;
      result.actual = error;
      result.details = std::string("wrong error for case: ") + c.label;
      return result;
    }
    if (out.width != 12345u || out.height != 67890u || out.rgb.size() != 3u ||
        out.rgb[0] != 9 || out.rgb[1] != 9 || out.rgb[2] != 9) {
      result.details =
          std::string("out mutated on failure for case: ") + c.label;
      return result;
    }
  }

  result.passed = true;
  return result;
}

TestResult test_read_ppm_happy_path() {
  TestResult result;
  result.test_name = "read_ppm_happy_path";

  // Minimal 2x1 image: exact tight RGB8 packing (what cmd_segment feeds as
  // stride = width*3, RAC_SEGMENTATION_PIXEL_FORMAT_RGB8).
  const std::vector<uint8_t> pixels = {10, 20, 30, 200, 210, 220};
  {
    TempFile tf("rcli-ppm-2x1");
    if (!write_bytes(tf.path(), make_ppm(2, 1, pixels))) {
      result.details = "setup: cannot write 2x1 ppm";
      return result;
    }
    rcli::image::RgbImage out;
    std::string error;
    if (!rcli::image::read_ppm(tf.path(), &out, &error)) {
      result.details = "read_ppm failed on valid 2x1: " + error;
      return result;
    }
    if (out.width != 2u || out.height != 1u) {
      result.expected = "2x1";
      result.actual =
          std::to_string(out.width) + "x" + std::to_string(out.height);
      result.details = "wrong dimensions";
      return result;
    }
    if (out.rgb.size() != pixels.size() || out.rgb != pixels) {
      result.details = "pixel payload mismatch (tight RGB8 packing)";
      return result;
    }
  }

  // Larger buffer with a trailing byte beyond the declared payload: exactly
  // width*height*3 bytes are captured and the extra byte is ignored (no
  // off-by-one at the payload boundary).
  {
    const uint32_t w = 4;
    const uint32_t h = 3;
    std::vector<uint8_t> pixels2(static_cast<size_t>(w) * h * 3);
    for (size_t i = 0; i < pixels2.size(); ++i) {
      pixels2[i] = static_cast<uint8_t>(i * 7 + 1);
    }
    std::vector<uint8_t> file = make_ppm(w, h, pixels2);
    file.push_back(0xAB);  // trailing byte past the payload

    TempFile tf("rcli-ppm-4x3");
    if (!write_bytes(tf.path(), file)) {
      result.details = "setup: cannot write 4x3 ppm";
      return result;
    }
    rcli::image::RgbImage out;
    std::string error;
    if (!rcli::image::read_ppm(tf.path(), &out, &error)) {
      result.details = "read_ppm failed on valid 4x3: " + error;
      return result;
    }
    if (out.width != w || out.height != h ||
        out.rgb.size() != static_cast<size_t>(w) * h * 3 ||
        out.rgb != pixels2) {
      result.details = "4x3 payload/boundary mismatch";
      return result;
    }
  }

  result.passed = true;
  return result;
}

TestResult test_read_ppm_header_lexing() {
  TestResult result;
  result.test_name = "read_ppm_header_lexing";

  const std::vector<uint8_t> pixels = {1, 2, 3, 4, 5, 6};

  // (a) '#'-to-EOL comments are skipped and (b) arbitrary/mixed whitespace
  // (spaces, tabs, newlines) between the magic and the three integers is
  // tolerated.
  {
    const std::string header =
        "P6\n"
        "# a comment line\n"
        "\t 2 \t 1\n"
        "# another comment\n"
        "255\n";
    std::vector<uint8_t> file(header.begin(), header.end());
    file.insert(file.end(), pixels.begin(), pixels.end());

    TempFile tf("rcli-ppm-comments");
    if (!write_bytes(tf.path(), file)) {
      result.details = "setup: cannot write commented ppm";
      return result;
    }
    rcli::image::RgbImage out;
    std::string error;
    if (!rcli::image::read_ppm(tf.path(), &out, &error)) {
      result.details = "comments/whitespace not tolerated: " + error;
      return result;
    }
    if (out.width != 2u || out.height != 1u || out.rgb != pixels) {
      result.details = "commented header parsed to the wrong image";
      return result;
    }
  }

  // (c) exactly ONE whitespace byte is consumed between maxval and the pixel
  // payload (the `++pos` contract); a single space separator must work.
  {
    const std::string header = "P6\n2 1\n255 ";  // one space, then pixels
    std::vector<uint8_t> file(header.begin(), header.end());
    file.insert(file.end(), pixels.begin(), pixels.end());

    TempFile tf("rcli-ppm-space-sep");
    if (!write_bytes(tf.path(), file)) {
      result.details = "setup: cannot write space-separator ppm";
      return result;
    }
    rcli::image::RgbImage out;
    std::string error;
    if (!rcli::image::read_ppm(tf.path(), &out, &error)) {
      result.details = "single-space separator not accepted: " + error;
      return result;
    }
    if (out.width != 2u || out.height != 1u || out.rgb != pixels) {
      result.details = "space-separated header parsed to the wrong image";
      return result;
    }
  }

  // (d) uint overflow guard: a dimension token > 0xFFFFFFFF is malformed.
  {
    const std::string header = "P6\n4294967296 1\n255\n";  // 2^32 width
    std::vector<uint8_t> file(header.begin(), header.end());
    file.insert(file.end(), pixels.begin(), pixels.end());

    TempFile tf("rcli-ppm-overflow");
    if (!write_bytes(tf.path(), file)) {
      result.details = "setup: cannot write overflow ppm";
      return result;
    }
    rcli::image::RgbImage out;
    std::string error;
    if (rcli::image::read_ppm(tf.path(), &out, &error)) {
      result.details = "overflowing dimension should be rejected";
      return result;
    }
    if (error.find("malformed PPM header") == std::string::npos) {
      result.expected = "malformed PPM header";
      result.actual = error;
      return result;
    }
  }

  result.passed = true;
  return result;
}

TestResult test_write_png_invalid_args() {
  TestResult result;
  result.test_name = "write_png_invalid_args";

  const std::vector<uint8_t> px(2 * 2 * 4, 0x33);

  struct Case {
    const char *label;
    const uint8_t *data;
    int width;
    int height;
  };
  const Case cases[] = {
      {"null data", nullptr, 2, 2},
      {"zero width", px.data(), 0, 2},
      {"negative width", px.data(), -1, 2},
      {"zero height", px.data(), 2, 0},
      {"negative height", px.data(), 2, -3},
  };

  for (const Case &c : cases) {
    TempFile tf("rcli-png-badarg");
    std::string error;
    const bool ok =
        rcli::image::write_png(tf.path(), c.data, c.width, c.height, &error);
    if (ok) {
      result.details = std::string("expected failure for case: ") + c.label;
      return result;
    }
    if (error != "invalid image dimensions or data") {
      result.expected = "invalid image dimensions or data";
      result.actual = error;
      result.details = std::string("wrong error for case: ") + c.label;
      return result;
    }
    if (std::filesystem::exists(tf.path())) {
      result.details =
          std::string("no file should be created for case: ") + c.label;
      return result;
    }
  }

  result.passed = true;
  return result;
}

TestResult test_write_png_container() {
  TestResult result;
  result.test_name = "write_png_container";

  const int w = 2;
  const int h = 2;
  std::vector<uint8_t> rgba(static_cast<size_t>(w) * h * 4);
  for (size_t i = 0; i < rgba.size(); ++i) {
    rgba[i] = static_cast<uint8_t>(i * 11 + 3);
  }

  TempFile tf("rcli-png-container");
  std::string error;
  if (!rcli::image::write_png(tf.path(), rgba.data(), w, h, &error)) {
    result.details = "write_png failed: " + error;
    return result;
  }

  std::vector<uint8_t> png;
  if (!read_bytes(tf.path(), &png)) {
    result.details = "cannot read back written png";
    return result;
  }

  const uint8_t sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
  if (png.size() < 8u || std::memcmp(png.data(), sig, 8) != 0) {
    result.details = "missing/incorrect 8-byte PNG signature";
    return result;
  }

  std::vector<PngChunk> chunks;
  if (!parse_png(png, &chunks) || chunks.size() < 3u) {
    result.details = "PNG chunk structure did not parse";
    return result;
  }
  if (chunks.front().type != "IHDR") {
    result.actual = chunks.front().type;
    result.details = "first chunk must be IHDR";
    return result;
  }
  if (chunks.back().type != "IEND" || !chunks.back().data.empty()) {
    result.details = "final chunk must be a zero-length IEND";
    return result;
  }

  const PngChunk *ihdr = &chunks.front();
  if (ihdr->data.size() != 13u) {
    result.details = "IHDR must be 13 bytes";
    return result;
  }
  if (read_u32_be(ihdr->data, 0) != static_cast<uint32_t>(w) ||
      read_u32_be(ihdr->data, 4) != static_cast<uint32_t>(h)) {
    result.details = "IHDR width/height mismatch";
    return result;
  }
  if (ihdr->data[8] != 8 || ihdr->data[9] != 6) {
    result.expected = "8/6";
    result.actual = std::to_string(static_cast<int>(ihdr->data[8])) + "/" +
                    std::to_string(static_cast<int>(ihdr->data[9]));
    result.details = "IHDR bit-depth/color-type must be 8/6 (RGBA)";
    return result;
  }

  const PngChunk *idat = find_chunk(chunks, "IDAT");
  if (idat == nullptr) {
    result.details = "no IDAT chunk";
    return result;
  }
  if (idat->data.size() < 2u || idat->data[0] != 0x78 ||
      idat->data[1] != 0x01) {
    result.details = "IDAT zlib header must be 0x78 0x01";
    return result;
  }

  result.passed = true;
  return result;
}

TestResult test_write_png_byte_exact() {
  TestResult result;
  result.test_name = "write_png_byte_exact";

  const int w = 3;
  const int h = 2;
  std::vector<uint8_t> rgba(static_cast<size_t>(w) * h * 4);
  for (size_t i = 0; i < rgba.size(); ++i) {
    rgba[i] = static_cast<uint8_t>(i * 13 + 5);
  }

  TempFile tf("rcli-png-exact");
  std::string error;
  if (!rcli::image::write_png(tf.path(), rgba.data(), w, h, &error)) {
    result.details = "write_png failed: " + error;
    return result;
  }
  std::vector<uint8_t> png;
  if (!read_bytes(tf.path(), &png)) {
    result.details = "cannot read back written png";
    return result;
  }

  std::vector<PngChunk> chunks;
  if (!parse_png(png, &chunks)) {
    result.details = "PNG did not parse";
    return result;
  }

  // (c) every chunk's stored CRC-32 matches an independent computation.
  for (const PngChunk &c : chunks) {
    if (c.stored_crc != c.computed_crc) {
      result.details = "CRC-32 mismatch on chunk " + c.type;
      return result;
    }
  }

  const PngChunk *idat = find_chunk(chunks, "IDAT");
  if (idat == nullptr) {
    result.details = "no IDAT chunk";
    return result;
  }
  const ZlibParse z = parse_stored_zlib(idat->data);
  if (!z.ok) {
    result.details = "IDAT zlib stored-block stream did not parse";
    return result;
  }

  // (a) the stored block payload equals the independently reconstructed
  // filtered scanlines.
  const std::vector<uint8_t> raw = filtered_raw(rgba, w, h);
  if (z.payload != raw) {
    result.details = "stored DEFLATE payload != filtered scanlines";
    return result;
  }
  if (z.block_count != 1) {
    result.expected = "1";
    result.actual = std::to_string(z.block_count);
    result.details = "small image should be a single stored block";
    return result;
  }
  if (!z.bfinal_ok) {
    result.details = "single block must have BFINAL=1";
    return result;
  }
  if (!z.lennlen_ok) {
    result.details = "stored block LEN/NLEN are not one's-complement";
    return result;
  }

  // (b) trailing big-endian Adler-32 matches adler32(raw).
  if (z.adler != test_adler32(raw.data(), raw.size())) {
    result.details = "Adler-32 checksum mismatch";
    return result;
  }

  result.passed = true;
  return result;
}

TestResult test_write_png_multi_block() {
  TestResult result;
  result.test_name = "write_png_multi_block";

  // Filtered raw = height*(1 + width*4) must exceed 0xFFFF to force >1 stored
  // DEFLATE block. 200 * (1 + 400) = 80200 bytes => two blocks.
  const int w = 100;
  const int h = 200;
  std::vector<uint8_t> rgba(static_cast<size_t>(w) * h * 4);
  for (size_t i = 0; i < rgba.size(); ++i) {
    rgba[i] = static_cast<uint8_t>((i * 31 + 17) & 0xFF);
  }

  TempFile tf("rcli-png-multiblock");
  std::string error;
  if (!rcli::image::write_png(tf.path(), rgba.data(), w, h, &error)) {
    result.details = "write_png failed: " + error;
    return result;
  }
  std::vector<uint8_t> png;
  if (!read_bytes(tf.path(), &png)) {
    result.details = "cannot read back written png";
    return result;
  }

  std::vector<PngChunk> chunks;
  if (!parse_png(png, &chunks)) {
    result.details = "PNG did not parse";
    return result;
  }
  const PngChunk *idat = find_chunk(chunks, "IDAT");
  if (idat == nullptr) {
    result.details = "no IDAT chunk";
    return result;
  }
  const ZlibParse z = parse_stored_zlib(idat->data);
  if (!z.ok) {
    result.details = "IDAT zlib stored-block stream did not parse";
    return result;
  }
  if (z.block_count <= 1) {
    result.expected = ">1";
    result.actual = std::to_string(z.block_count);
    result.details = "expected more than one stored block";
    return result;
  }
  if (!z.bfinal_ok) {
    result.details = "only the final stored block may set BFINAL=1";
    return result;
  }
  if (!z.lennlen_ok) {
    result.details = "each block's LEN/NLEN must be one's-complement";
    return result;
  }

  const std::vector<uint8_t> raw = filtered_raw(rgba, w, h);
  if (z.payload != raw) {
    result.details = "reassembled multi-block payload != filtered scanlines";
    return result;
  }
  if (z.adler != test_adler32(raw.data(), raw.size())) {
    result.details = "Adler-32 checksum mismatch across blocks";
    return result;
  }

  result.passed = true;
  return result;
}

TestResult test_write_png_unwritable_path() {
  TestResult result;
  result.test_name = "write_png_unwritable_path";

  TempFile base("rcli-png-nodir");
  // A path under a directory that was never created -> fopen("wb") fails.
  const std::string path =
      (std::filesystem::path(base.path()) / "no_such_subdir" / "x.png")
          .string();

  const std::vector<uint8_t> rgba(2 * 2 * 4, 0x40);
  std::string error;
  const bool ok = rcli::image::write_png(path, rgba.data(), 2, 2, &error);
  if (ok) {
    result.details = "write_png should fail into a non-existent directory";
    return result;
  }
  if (error.find("cannot open") == std::string::npos ||
      error.find("for writing") == std::string::npos) {
    result.expected = "cannot open <path> for writing";
    result.actual = error;
    return result;
  }
  if (std::filesystem::exists(path)) {
    result.details = "no file should be produced on open failure";
    return result;
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
  suite.add("diarize_arg_surface", test_diarize_arg_surface);
  suite.add("diarize_missing_model_exit2", test_diarize_missing_model_exit2);
  suite.add("diarize_missing_audio_exit2", test_diarize_missing_audio_exit2);
  suite.add("diarize_audio_not_found_exit2", test_diarize_audio_not_found_exit2);
  suite.add("diarize_numeric_option_typing_exit2",
            test_diarize_numeric_option_typing_exit2);
  suite.add("diarize_unknown_flag_exit2", test_diarize_unknown_flag_exit2);
  suite.add("read_ppm_errors", test_read_ppm_errors);
  suite.add("read_ppm_happy_path", test_read_ppm_happy_path);
  suite.add("read_ppm_header_lexing", test_read_ppm_header_lexing);
  suite.add("write_png_invalid_args", test_write_png_invalid_args);
  suite.add("write_png_container", test_write_png_container);
  suite.add("write_png_byte_exact", test_write_png_byte_exact);
  suite.add("write_png_multi_block", test_write_png_multi_block);
  suite.add("write_png_unwritable_path", test_write_png_unwritable_path);
  return suite.run(argc, argv);
}
