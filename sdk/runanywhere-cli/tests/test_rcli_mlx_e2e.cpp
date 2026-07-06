/**
 * @file test_rcli_mlx_e2e.cpp
 * @brief In-process rcli E2E coverage for the MLX backend contract.
 *
 * The production MLX runtime is Swift/MLX. This test installs the same C
 * callback table that the Swift runtime installs, then invokes the actual rcli
 * command stack against a local MLX-style folder. That keeps the test offline
 * and fast while exercising rcli parsing, bootstrap, backend registration,
 * commons lifecycle loading, MLX callback dispatch, and streaming output.
 */

#include "test_common.h"

#include <CLI11.hpp>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include <unistd.h>

#include "app.h"
#include "bootstrap.h"
#include "llm_service.pb.h"
#include "model_types.pb.h"
#include "rac/backends/rac_mlx.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

namespace {

namespace v1 = runanywhere::v1;

struct FakeMlxSession {
  rac_mlx_session_kind_t kind = RAC_MLX_SESSION_KIND_LLM;
  std::string model_id;
  std::string model_path;
};

struct FakeMlxState {
  int create_count = 0;
  int initialize_count = 0;
  int stream_count = 0;
  rac_mlx_session_kind_t last_kind = RAC_MLX_SESSION_KIND_LLM;
  std::string last_model_path;
};

FakeMlxState g_mlx_state;

std::filesystem::path make_temp_dir(const std::string &name) {
  const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
  std::filesystem::path dir =
      std::filesystem::temp_directory_path() / (name + "-" + std::to_string(stamp));
  std::filesystem::create_directories(dir);
  return dir;
}

bool write_file(const std::filesystem::path &path, const std::string &contents) {
  std::ofstream out(path, std::ios::binary);
  if (!out.is_open()) {
    return false;
  }
  out << contents;
  return out.good();
}

bool serialize(const google::protobuf::MessageLite &message, std::vector<uint8_t> *out) {
  out->resize(message.ByteSizeLong());
  if (out->empty()) {
    return true;
  }
  return message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

rac_result_t fake_create(rac_mlx_session_kind_t kind, const char *model_id,
                         const char *, rac_handle_t *out_handle, void *) {
  if (!out_handle) {
    return RAC_ERROR_NULL_POINTER;
  }
  auto *session = new FakeMlxSession();
  session->kind = kind;
  session->model_id = model_id ? model_id : "";
  *out_handle = session;
  g_mlx_state.create_count++;
  g_mlx_state.last_kind = kind;
  return RAC_SUCCESS;
}

rac_result_t fake_initialize(rac_handle_t handle, const char *model_path, void *) {
  if (!handle || !model_path) {
    return RAC_ERROR_NULL_POINTER;
  }
  auto *session = static_cast<FakeMlxSession *>(handle);
  session->model_path = model_path;
  g_mlx_state.initialize_count++;
  g_mlx_state.last_model_path = model_path;
  return RAC_SUCCESS;
}

rac_result_t fake_llm_generate(rac_handle_t, const char *prompt,
                               const rac_llm_options_t *,
                               rac_llm_result_t *out_result, void *) {
  if (!prompt || !out_result) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_result, 0, sizeof(*out_result));
  const std::string text = "mlx-stub: " + std::string(prompt);
  out_result->text = strdup(text.c_str());
  out_result->prompt_tokens = 2;
  out_result->completion_tokens = 3;
  out_result->total_tokens = 5;
  out_result->total_time_ms = 7;
  out_result->tokens_per_second = 100.0f;
  return out_result->text ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t fake_llm_generate_stream(rac_handle_t, const char *prompt,
                                      const rac_llm_options_t *,
                                      rac_llm_stream_callback_fn callback,
                                      void *callback_user_data, void *) {
  if (!prompt || !callback) {
    return RAC_ERROR_NULL_POINTER;
  }
  g_mlx_state.stream_count++;
  const std::string token = "mlx-stub: " + std::string(prompt);
  return callback(token.c_str(), callback_user_data) == RAC_TRUE ? RAC_SUCCESS
                                                                 : RAC_ERROR_STREAM_CANCELLED;
}

rac_result_t fake_vlm_process(rac_handle_t, const rac_vlm_image_t *, const char *prompt,
                              const rac_vlm_options_t *, rac_vlm_result_t *out_result,
                              void *) {
  if (!prompt || !out_result) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_result, 0, sizeof(*out_result));
  const std::string text = "mlx-vlm-stub: " + std::string(prompt);
  out_result->text = strdup(text.c_str());
  out_result->completion_tokens = 3;
  out_result->total_tokens = 8;
  out_result->tokens_per_second = 50.0f;
  return out_result->text ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t fake_vlm_process_stream(rac_handle_t, const rac_vlm_image_t *,
                                     const char *prompt, const rac_vlm_options_t *,
                                     rac_vlm_stream_callback_fn callback,
                                     void *callback_user_data, void *) {
  if (!prompt || !callback) {
    return RAC_ERROR_NULL_POINTER;
  }
  return callback(prompt, callback_user_data) == RAC_TRUE ? RAC_SUCCESS : RAC_ERROR_CANCELLED;
}

rac_result_t fake_embed_batch(rac_handle_t, const char *const *texts, size_t num_texts,
                              const rac_embeddings_options_t *,
                              rac_embeddings_result_t *out_result, void *) {
  if (!texts || !out_result) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_result, 0, sizeof(*out_result));
  out_result->num_embeddings = num_texts;
  out_result->dimension = 2;
  out_result->embeddings = static_cast<rac_embedding_vector_t *>(
      std::calloc(num_texts, sizeof(rac_embedding_vector_t)));
  if (!out_result->embeddings) {
    return RAC_ERROR_OUT_OF_MEMORY;
  }
  for (size_t i = 0; i < num_texts; ++i) {
    out_result->embeddings[i].dimension = 2;
    out_result->embeddings[i].data = static_cast<float *>(std::calloc(2, sizeof(float)));
    if (!out_result->embeddings[i].data) {
      return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->embeddings[i].data[0] = texts[i] && texts[i][0] ? 1.0f : 0.0f;
    out_result->embeddings[i].data[1] = 0.5f;
  }
  out_result->total_tokens = static_cast<int32_t>(num_texts);
  return RAC_SUCCESS;
}

rac_result_t fake_embedding_info(rac_handle_t, rac_embeddings_info_t *out_info, void *) {
  if (!out_info) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_info, 0, sizeof(*out_info));
  out_info->is_ready = RAC_TRUE;
  out_info->dimension = 2;
  out_info->max_tokens = 512;
  return RAC_SUCCESS;
}

rac_result_t fake_cancel(rac_handle_t, void *) { return RAC_SUCCESS; }
rac_result_t fake_cleanup(rac_handle_t, void *) { return RAC_SUCCESS; }
void fake_destroy(rac_handle_t handle, void *) { delete static_cast<FakeMlxSession *>(handle); }

bool install_fake_mlx_callbacks() {
  rac_mlx_callbacks_t callbacks{};
  callbacks.struct_size = sizeof(callbacks);
  callbacks.create = fake_create;
  callbacks.initialize = fake_initialize;
  callbacks.llm_generate = fake_llm_generate;
  callbacks.llm_generate_stream = fake_llm_generate_stream;
  callbacks.vlm_process = fake_vlm_process;
  callbacks.vlm_process_stream = fake_vlm_process_stream;
  callbacks.embed_batch = fake_embed_batch;
  callbacks.embedding_info = fake_embedding_info;
  callbacks.cancel = fake_cancel;
  callbacks.cleanup = fake_cleanup;
  callbacks.destroy = fake_destroy;
  return rac_mlx_set_callbacks(&callbacks) == RAC_SUCCESS;
}

bool register_local_mlx_model(const std::filesystem::path &model_dir) {
  v1::ModelInfo model;
  model.set_id("mlx.fake.llm");
  model.set_name("Fake MLX LLM");
  model.set_category(v1::MODEL_CATEGORY_LANGUAGE);
  model.set_format(v1::MODEL_FORMAT_SAFETENSORS);
  model.set_framework(v1::INFERENCE_FRAMEWORK_MLX);
  model.set_local_path(model_dir.string());
  model.set_is_downloaded(true);
  model.set_is_available(true);
  model.set_registry_status(v1::MODEL_REGISTRY_STATUS_DOWNLOADED);

  auto *config = model.mutable_multi_file()->add_files();
  config->set_filename("config.json");
  config->set_destination_path("config.json");
  config->set_is_required(true);
  config->set_role(v1::MODEL_FILE_ROLE_COMPANION);

  auto *weights = model.mutable_multi_file()->add_files();
  weights->set_filename("model.safetensors");
  weights->set_destination_path("model.safetensors");
  weights->set_is_required(true);
  weights->set_role(v1::MODEL_FILE_ROLE_PRIMARY_MODEL);

  auto *tokenizer = model.mutable_multi_file()->add_files();
  tokenizer->set_filename("tokenizer.json");
  tokenizer->set_destination_path("tokenizer.json");
  tokenizer->set_is_required(true);
  tokenizer->set_role(v1::MODEL_FILE_ROLE_TOKENIZER);

  std::vector<uint8_t> bytes;
  return serialize(model, &bytes) &&
         rac_model_registry_register_proto(rac_get_model_registry(), bytes.data(), bytes.size()) ==
             RAC_SUCCESS;
}

class StdoutCapture {
public:
  bool start() {
    if (pipe(pipe_fds_) != 0) {
      return false;
    }
    saved_stdout_ = dup(STDOUT_FILENO);
    if (saved_stdout_ < 0) {
      return false;
    }
    return dup2(pipe_fds_[1], STDOUT_FILENO) >= 0;
  }

  std::string finish() {
    std::fflush(stdout);
    dup2(saved_stdout_, STDOUT_FILENO);
    close(saved_stdout_);
    saved_stdout_ = -1;
    close(pipe_fds_[1]);
    pipe_fds_[1] = -1;

    std::string output;
    char buffer[4096];
    ssize_t n = 0;
    while ((n = read(pipe_fds_[0], buffer, sizeof(buffer))) > 0) {
      output.append(buffer, static_cast<size_t>(n));
    }
    close(pipe_fds_[0]);
    pipe_fds_[0] = -1;
    return output;
  }

private:
  int pipe_fds_[2] = {-1, -1};
  int saved_stdout_ = -1;
};

int run_cli_capture(const std::vector<std::string> &args, std::string *stdout_text) {
  rcli::GlobalOptions options;
  CLI::App app{"RunAnywhere on-device AI CLI — run, manage and serve local models"};
  rcli::configure_app(app, options);

  std::vector<std::string> mutable_args = args;
  std::vector<char *> argv;
  argv.reserve(mutable_args.size());
  for (std::string &arg : mutable_args) {
    argv.push_back(arg.data());
  }

  StdoutCapture capture;
  if (!capture.start()) {
    return 1;
  }

  int exit_code = 0;
  try {
    app.parse(static_cast<int>(argv.size()), argv.data());
  } catch (const CLI::RuntimeError &e) {
    exit_code = e.get_exit_code() != 0 ? e.get_exit_code() : 1;
  } catch (const CLI::ParseError &e) {
    exit_code = app.exit(e);
  } catch (const std::exception &) {
    exit_code = 1;
  }
  *stdout_text = capture.finish();
  return exit_code;
}

TestResult test_rcli_mlx_run_end_to_end() {
  TestResult result;
  result.test_name = "rcli_mlx_run_end_to_end";

  g_mlx_state = {};
  if (!install_fake_mlx_callbacks()) {
    result.details = "failed to install MLX callbacks";
    return result;
  }

  const std::filesystem::path home = make_temp_dir("rcli-mlx-home");
  const std::filesystem::path model_dir = make_temp_dir("rcli-mlx-model");
  if (!write_file(model_dir / "config.json", R"({"model_type":"qwen3"})") ||
      !write_file(model_dir / "model.safetensors", "fake-weights") ||
      !write_file(model_dir / "tokenizer.json", "{}")) {
    result.details = "failed to create local MLX model folder";
    return result;
  }

  rcli::GlobalOptions options;
  options.home_override = home.string();
  options.json = true;
  options.no_progress = true;
  rcli::Bootstrapped bootstrapped;
  if (rcli::bootstrap(options, &bootstrapped) != RAC_SUCCESS) {
    result.details = "bootstrap failed";
    return result;
  }
  if (!register_local_mlx_model(model_dir)) {
    result.details = "failed to register local MLX model";
    rcli::shutdown();
    return result;
  }

  std::string backends_json;
  int code = run_cli_capture({"rcli", "--json", "--no-progress", "--home", home.string(),
                              "backends"},
                             &backends_json);
  if (code != 0 || backends_json.find("\"name\":\"mlx\"") == std::string::npos ||
      backends_json.find("\"name\":\"generate_text\"") == std::string::npos ||
      backends_json.find("\"name\":\"vlm\"") == std::string::npos ||
      backends_json.find("\"name\":\"embed\"") == std::string::npos) {
    result.expected = "mlx backend with generate_text/vlm/embed primitives";
    result.actual = backends_json;
    rcli::shutdown();
    return result;
  }

  std::string run_json;
  code = run_cli_capture({"rcli", "--json", "--no-progress", "--home", home.string(), "run",
                          "mlx.fake.llm", "Hello MLX", "--engine", "mlx", "--max-tokens", "4"},
                         &run_json);
  rcli::shutdown();

  if (code != 0) {
    result.expected = "exit 0";
    result.actual = "exit " + std::to_string(code);
    result.details = run_json;
    return result;
  }
  if (run_json.find("\"model\":\"mlx.fake.llm\"") == std::string::npos ||
      run_json.find("\"response\":\"mlx-stub: Hello MLX\"") == std::string::npos) {
    result.expected = "JSON response from MLX stream callback";
    result.actual = run_json;
    return result;
  }
  if (g_mlx_state.create_count != 1 || g_mlx_state.initialize_count != 1 ||
      g_mlx_state.stream_count != 1 || g_mlx_state.last_kind != RAC_MLX_SESSION_KIND_LLM) {
    result.details = "MLX callback counts/kind were not exercised as expected";
    return result;
  }
  if (g_mlx_state.last_model_path != model_dir.string()) {
    result.expected = model_dir.string();
    result.actual = g_mlx_state.last_model_path;
    result.details = "MLX runtime should receive the model folder, not model.safetensors";
    return result;
  }

  result.passed = true;
  return result;
}

}  // namespace

int main(int argc, char **argv) {
  TestSuite suite("rcli_mlx_e2e");
  suite.add("rcli_mlx_run_end_to_end", test_rcli_mlx_run_end_to_end);
  return suite.run(argc, argv);
}
