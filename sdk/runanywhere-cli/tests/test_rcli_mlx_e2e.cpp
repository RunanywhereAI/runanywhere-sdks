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
#include <initializer_list>
#include <set>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>
#include <unistd.h>

#include "app.h"
#include "bootstrap.h"
#include "io/wav_io.h"
#include "llm_service.pb.h"
#include "model_types.pb.h"
#include "rac/backends/rac_mlx.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/plugin/rac_plugin_entry.h"

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
  int llm_generate_count = 0;
  int stream_count = 0;
  int vlm_process_count = 0;
  int vlm_stream_count = 0;
  int embed_batch_count = 0;
  int embedding_info_count = 0;
  int stt_transcribe_count = 0;
  int stt_stream_count = 0;
  int stt_info_count = 0;
  int tts_synthesize_count = 0;
  int tts_stream_count = 0;
  int tts_stop_count = 0;
  int tts_info_count = 0;
  rac_mlx_session_kind_t last_kind = RAC_MLX_SESSION_KIND_LLM;
  std::string last_model_path;
  size_t last_embed_batch_size = 0;
  size_t last_audio_size = 0;
  std::string last_tts_text;
};

FakeMlxState g_mlx_state;

std::filesystem::path make_temp_dir(const std::string &name) {
  const auto stamp =
      std::chrono::steady_clock::now().time_since_epoch().count();
  std::filesystem::path dir = std::filesystem::temp_directory_path() /
                              (name + "-" + std::to_string(stamp));
  std::filesystem::create_directories(dir);
  return dir;
}

bool write_file(const std::filesystem::path &path,
                const std::string &contents) {
  std::ofstream out(path, std::ios::binary);
  if (!out.is_open()) {
    return false;
  }
  out << contents;
  return out.good();
}

bool serialize(const google::protobuf::MessageLite &message,
               std::vector<uint8_t> *out) {
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

rac_result_t fake_initialize(rac_handle_t handle, const char *model_path,
                             void *) {
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
  g_mlx_state.llm_generate_count++;
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
  return callback(token.c_str(), callback_user_data) == RAC_TRUE
             ? RAC_SUCCESS
             : RAC_ERROR_STREAM_CANCELLED;
}

rac_result_t fake_vlm_process(rac_handle_t, const rac_vlm_image_t *,
                              const char *prompt, const rac_vlm_options_t *,
                              rac_vlm_result_t *out_result, void *) {
  if (!prompt || !out_result) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_result, 0, sizeof(*out_result));
  const std::string text = "mlx-vlm-stub: " + std::string(prompt);
  out_result->text = strdup(text.c_str());
  out_result->completion_tokens = 3;
  out_result->total_tokens = 8;
  out_result->tokens_per_second = 50.0f;
  g_mlx_state.vlm_process_count++;
  return out_result->text ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t fake_vlm_process_stream(rac_handle_t, const rac_vlm_image_t *,
                                     const char *prompt,
                                     const rac_vlm_options_t *,
                                     rac_vlm_stream_callback_fn callback,
                                     void *callback_user_data, void *) {
  if (!prompt || !callback) {
    return RAC_ERROR_NULL_POINTER;
  }
  g_mlx_state.vlm_stream_count++;
  return callback(prompt, callback_user_data) == RAC_TRUE ? RAC_SUCCESS
                                                          : RAC_ERROR_CANCELLED;
}

rac_result_t fake_embed_batch(rac_handle_t, const char *const *texts,
                              size_t num_texts,
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
    out_result->embeddings[i].data =
        static_cast<float *>(std::calloc(2, sizeof(float)));
    if (!out_result->embeddings[i].data) {
      rac_embeddings_result_free(out_result);
      return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->embeddings[i].data[0] = texts[i] && texts[i][0] ? 1.0f : 0.0f;
    out_result->embeddings[i].data[1] = 0.5f;
  }
  out_result->total_tokens = static_cast<int32_t>(num_texts);
  g_mlx_state.embed_batch_count++;
  g_mlx_state.last_embed_batch_size = num_texts;
  return RAC_SUCCESS;
}

rac_result_t fake_embedding_info(rac_handle_t, rac_embeddings_info_t *out_info,
                                 void *) {
  if (!out_info) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_info, 0, sizeof(*out_info));
  out_info->is_ready = RAC_TRUE;
  out_info->dimension = 2;
  out_info->max_tokens = 512;
  g_mlx_state.embedding_info_count++;
  return RAC_SUCCESS;
}

rac_result_t fake_stt_transcribe(rac_handle_t, const void *audio_data,
                                 size_t audio_size, const rac_stt_options_t *,
                                 rac_stt_result_t *out_result, void *) {
  if (!audio_data || audio_size == 0 || !out_result) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_result, 0, sizeof(*out_result));
  const std::string text =
      "mlx-stt-stub: " + std::to_string(audio_size) + " bytes";
  out_result->text = strdup(text.c_str());
  out_result->detected_language = strdup("en");
  out_result->confidence = 0.95f;
  out_result->processing_time_ms = 11;
  g_mlx_state.stt_transcribe_count++;
  g_mlx_state.last_audio_size = audio_size;
  if (!out_result->text || !out_result->detected_language) {
    return RAC_ERROR_OUT_OF_MEMORY;
  }
  return RAC_SUCCESS;
}

rac_result_t fake_stt_transcribe_stream(rac_handle_t, const void *audio_data,
                                        size_t audio_size,
                                        const rac_stt_options_t *,
                                        rac_stt_stream_callback_t callback,
                                        void *callback_user_data, void *) {
  if (!audio_data || audio_size == 0 || !callback) {
    return RAC_ERROR_NULL_POINTER;
  }
  g_mlx_state.stt_stream_count++;
  callback("mlx-stt-partial", RAC_FALSE, callback_user_data);
  callback("mlx-stt-final", RAC_TRUE, callback_user_data);
  return RAC_SUCCESS;
}

rac_result_t fake_stt_info(rac_handle_t, rac_stt_info_t *out_info, void *) {
  if (!out_info) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_info, 0, sizeof(*out_info));
  out_info->is_ready = RAC_TRUE;
  out_info->current_model = "mlx.fake.stt";
  out_info->supports_streaming = RAC_TRUE;
  g_mlx_state.stt_info_count++;
  return RAC_SUCCESS;
}

rac_result_t fake_tts_synthesize(rac_handle_t, const char *text,
                                 const rac_tts_options_t *,
                                 rac_tts_result_t *out_result, void *) {
  if (!text || !out_result) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_result, 0, sizeof(*out_result));
  constexpr size_t kSampleCount = 8;
  auto *samples =
      static_cast<float *>(std::calloc(kSampleCount, sizeof(float)));
  if (!samples) {
    return RAC_ERROR_OUT_OF_MEMORY;
  }
  for (size_t i = 0; i < kSampleCount; ++i) {
    samples[i] = (i % 2 == 0) ? 0.25f : -0.25f;
  }
  out_result->audio_data = samples;
  out_result->audio_size = kSampleCount * sizeof(float);
  out_result->audio_format = RAC_AUDIO_FORMAT_PCM;
  out_result->sample_rate = 22050;
  out_result->duration_ms = 1;
  out_result->processing_time_ms = 13;
  g_mlx_state.tts_synthesize_count++;
  g_mlx_state.last_tts_text = text;
  return RAC_SUCCESS;
}

rac_result_t fake_tts_synthesize_stream(rac_handle_t, const char *text,
                                        const rac_tts_options_t *,
                                        rac_tts_stream_callback_t callback,
                                        void *callback_user_data, void *) {
  if (!text || !callback) {
    return RAC_ERROR_NULL_POINTER;
  }
  g_mlx_state.tts_stream_count++;
  const float samples[2] = {0.1f, -0.1f};
  callback(samples, sizeof(samples), callback_user_data);
  return RAC_SUCCESS;
}

rac_result_t fake_tts_stop(rac_handle_t, void *) {
  g_mlx_state.tts_stop_count++;
  return RAC_SUCCESS;
}

rac_result_t fake_tts_info(rac_handle_t, rac_tts_info_t *out_info, void *) {
  if (!out_info) {
    return RAC_ERROR_NULL_POINTER;
  }
  std::memset(out_info, 0, sizeof(*out_info));
  out_info->is_ready = RAC_TRUE;
  out_info->is_synthesizing = RAC_FALSE;
  g_mlx_state.tts_info_count++;
  return RAC_SUCCESS;
}

rac_result_t fake_cancel(rac_handle_t, void *) { return RAC_SUCCESS; }
rac_result_t fake_cleanup(rac_handle_t, void *) { return RAC_SUCCESS; }
void fake_destroy(rac_handle_t handle, void *) {
  delete static_cast<FakeMlxSession *>(handle);
}

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
  callbacks.stt_transcribe = fake_stt_transcribe;
  callbacks.stt_transcribe_stream = fake_stt_transcribe_stream;
  callbacks.stt_info = fake_stt_info;
  callbacks.tts_synthesize = fake_tts_synthesize;
  callbacks.tts_synthesize_stream = fake_tts_synthesize_stream;
  callbacks.tts_stop = fake_tts_stop;
  callbacks.tts_info = fake_tts_info;
  callbacks.cancel = fake_cancel;
  callbacks.cleanup = fake_cleanup;
  callbacks.destroy = fake_destroy;
  return rac_mlx_set_callbacks(&callbacks) == RAC_SUCCESS;
}

bool register_local_mlx_model(const std::filesystem::path &model_dir,
                              const char *id, const char *name,
                              v1::ModelCategory category) {
  v1::ModelInfo model;
  model.set_id(id);
  model.set_name(name);
  model.set_category(category);
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
  return serialize(model, &bytes) && rac_model_registry_register_proto(
                                         rac_get_model_registry(), bytes.data(),
                                         bytes.size()) == RAC_SUCCESS;
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

int run_cli_capture(const std::vector<std::string> &args,
                    std::string *stdout_text) {
  rcli::GlobalOptions options;
  CLI::App app{
      "RunAnywhere on-device AI CLI — run, manage and serve local models"};
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

bool backend_has_primitives(const std::string &json_text, const std::string &backend_name,
                            std::initializer_list<std::string> expected,
                            std::string *error) {
  try {
    const auto document = nlohmann::json::parse(json_text);
    for (const auto &backend : document.value("backends", nlohmann::json::array())) {
      if (backend.value("name", "") != backend_name) {
        continue;
      }
      std::set<std::string> primitives;
      for (const auto &primitive : backend.value("primitives", nlohmann::json::array())) {
        primitives.insert(primitive.value("name", ""));
      }
      for (const auto &name : expected) {
        if (!primitives.contains(name)) {
          if (error) {
            *error = "missing primitive " + name;
          }
          return false;
        }
      }
      return true;
    }
    if (error) {
      *error = "backend not found: " + backend_name;
    }
    return false;
  } catch (const std::exception &ex) {
    if (error) {
      *error = ex.what();
    }
    return false;
  }
}

bool run_cli_or_fail(const std::vector<std::string> &args,
                     const std::string &expected_label,
                     std::string *stdout_text, TestResult *result) {
  const int code = run_cli_capture(args, stdout_text);
  if (code == 0) {
    return true;
  }
  result->expected = expected_label + " exit 0";
  result->actual = "exit " + std::to_string(code);
  result->details = *stdout_text;
  return false;
}

bool register_mlx_backend_or_fail(TestResult *result) {
  const rac_result_t rc = rac_backend_mlx_register();
  if (rc == RAC_SUCCESS || rc == RAC_ERROR_MODULE_ALREADY_REGISTERED) {
    return true;
  }
  result->expected = "rac_backend_mlx_register success";
  result->actual = std::to_string(rc);
  return false;
}

rac_bool_t append_token_callback(const char *token, void *user_data) {
  auto *out = static_cast<std::string *>(user_data);
  if (token && out) {
    out->append(token);
  }
  return RAC_TRUE;
}

void append_stt_callback(const char *text, rac_bool_t is_final,
                         void *user_data) {
  auto *out = static_cast<std::string *>(user_data);
  if (text && out) {
    if (!out->empty()) {
      out->append("|");
    }
    out->append(is_final == RAC_TRUE ? "final:" : "partial:");
    out->append(text);
  }
}

void count_tts_chunk_callback(const void *, size_t audio_size,
                              void *user_data) {
  auto *total = static_cast<size_t *>(user_data);
  if (total) {
    *total += audio_size;
  }
}

TestResult test_mlx_callback_bridge_all_slots() {
  TestResult result;
  result.test_name = "mlx_callback_bridge_all_slots";

  g_mlx_state = {};
  if (!install_fake_mlx_callbacks() || !register_mlx_backend_or_fail(&result)) {
    if (result.details.empty()) {
      result.details = "failed to install/register MLX callbacks";
    }
    return result;
  }

  const rac_engine_vtable_t *llm_vt =
      rac_plugin_find_for_engine(RAC_PRIMITIVE_GENERATE_TEXT, "mlx");
  const rac_engine_vtable_t *vlm_vt =
      rac_plugin_find_for_engine(RAC_PRIMITIVE_VLM, "mlx");
  const rac_engine_vtable_t *embed_vt =
      rac_plugin_find_for_engine(RAC_PRIMITIVE_EMBED, "mlx");
  const rac_engine_vtable_t *stt_vt =
      rac_plugin_find_for_engine(RAC_PRIMITIVE_TRANSCRIBE, "mlx");
  const rac_engine_vtable_t *tts_vt =
      rac_plugin_find_for_engine(RAC_PRIMITIVE_SYNTHESIZE, "mlx");
  if (!llm_vt || !vlm_vt || !embed_vt || !stt_vt || !tts_vt ||
      !llm_vt->llm_ops || !vlm_vt->vlm_ops || !embed_vt->embedding_ops ||
      !stt_vt->stt_ops || !tts_vt->tts_ops) {
    result.expected = "registered MLX vtable with all modality op slots";
    result.actual = "one or more MLX op slots missing";
    rac_backend_mlx_unregister();
    return result;
  }

  void *llm = nullptr;
  rac_llm_result_t llm_result{};
  std::string llm_stream;
  rac_llm_info_t llm_info{};
  if (llm_vt->llm_ops->create("mlx.direct.llm", nullptr, &llm) != RAC_SUCCESS ||
      llm_vt->llm_ops->initialize(llm, "/tmp/mlx-direct-llm") != RAC_SUCCESS ||
      llm_vt->llm_ops->generate(llm, "direct", nullptr, &llm_result) != RAC_SUCCESS ||
      llm_vt->llm_ops->generate_stream(llm, "stream", nullptr, append_token_callback,
                                       &llm_stream) != RAC_SUCCESS ||
      llm_vt->llm_ops->get_info(llm, &llm_info) != RAC_SUCCESS ||
      llm_vt->llm_ops->cancel(llm) != RAC_SUCCESS ||
      llm_vt->llm_ops->cleanup(llm) != RAC_SUCCESS) {
    result.details = "MLX LLM direct ops failed";
    if (llm_result.text) {
      rac_llm_result_free(&llm_result);
    }
    if (llm) {
      llm_vt->llm_ops->destroy(llm);
    }
    rac_backend_mlx_unregister();
    return result;
  }
  const bool llm_ok = llm_result.text &&
                      std::string(llm_result.text) == "mlx-stub: direct" &&
                      llm_stream == "mlx-stub: stream" &&
                      llm_info.is_ready == RAC_TRUE &&
                      g_mlx_state.llm_generate_count == 1 &&
                      g_mlx_state.stream_count == 1 &&
                      g_mlx_state.last_kind == RAC_MLX_SESSION_KIND_LLM;
  rac_llm_result_free(&llm_result);
  llm_vt->llm_ops->destroy(llm);
  if (!llm_ok) {
    result.details = "MLX LLM direct callbacks were not all exercised";
    rac_backend_mlx_unregister();
    return result;
  }

  void *vlm = nullptr;
  rac_vlm_result_t vlm_result{};
  std::string vlm_stream;
  rac_vlm_info_t vlm_info{};
  rac_vlm_image_t image{};
  image.format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
  image.file_path = "/tmp/mlx-direct-image.jpg";
  if (vlm_vt->vlm_ops->create("mlx.direct.vlm", nullptr, &vlm) != RAC_SUCCESS ||
      vlm_vt->vlm_ops->initialize(vlm, "/tmp/mlx-direct-vlm", nullptr) != RAC_SUCCESS ||
      vlm_vt->vlm_ops->process(vlm, &image, "look", nullptr, &vlm_result) != RAC_SUCCESS ||
      vlm_vt->vlm_ops->process_stream(vlm, &image, "watch", nullptr, append_token_callback,
                                      &vlm_stream) != RAC_SUCCESS ||
      vlm_vt->vlm_ops->get_info(vlm, &vlm_info) != RAC_SUCCESS ||
      vlm_vt->vlm_ops->cancel(vlm) != RAC_SUCCESS ||
      vlm_vt->vlm_ops->cleanup(vlm) != RAC_SUCCESS) {
    result.details = "MLX VLM direct ops failed";
    if (vlm_result.text) {
      rac_vlm_result_free(&vlm_result);
    }
    if (vlm) {
      vlm_vt->vlm_ops->destroy(vlm);
    }
    rac_backend_mlx_unregister();
    return result;
  }
  const bool vlm_ok = vlm_result.text &&
                      std::string(vlm_result.text) == "mlx-vlm-stub: look" &&
                      vlm_stream == "watch" &&
                      vlm_info.is_ready == RAC_TRUE &&
                      g_mlx_state.vlm_process_count == 1 &&
                      g_mlx_state.vlm_stream_count == 1 &&
                      g_mlx_state.last_kind == RAC_MLX_SESSION_KIND_VLM;
  rac_vlm_result_free(&vlm_result);
  vlm_vt->vlm_ops->destroy(vlm);
  if (!vlm_ok) {
    result.details = "MLX VLM direct callbacks were not all exercised";
    rac_backend_mlx_unregister();
    return result;
  }

  void *embed = nullptr;
  rac_embeddings_result_t embed_result{};
  rac_embeddings_info_t embed_info{};
  const char *embed_texts[] = {"one", "two"};
  if (embed_vt->embedding_ops->create("mlx.direct.embed", nullptr, &embed) !=
          RAC_SUCCESS ||
      embed_vt->embedding_ops->initialize(embed, "/tmp/mlx-direct-embed") !=
          RAC_SUCCESS ||
      embed_vt->embedding_ops->embed(embed, "single", nullptr, &embed_result) !=
          RAC_SUCCESS ||
      embed_vt->embedding_ops->get_info(embed, &embed_info) != RAC_SUCCESS) {
    result.details = "MLX embedding direct single ops failed";
    rac_embeddings_result_free(&embed_result);
    if (embed) {
      embed_vt->embedding_ops->destroy(embed);
    }
    rac_backend_mlx_unregister();
    return result;
  }
  rac_embeddings_result_free(&embed_result);
  if (embed_vt->embedding_ops->embed_batch(embed, embed_texts, 2, nullptr,
                                           &embed_result) != RAC_SUCCESS ||
      embed_vt->embedding_ops->cleanup(embed) != RAC_SUCCESS) {
    result.details = "MLX embedding direct batch ops failed";
    rac_embeddings_result_free(&embed_result);
    embed_vt->embedding_ops->destroy(embed);
    rac_backend_mlx_unregister();
    return result;
  }
  const bool embed_ok = embed_result.num_embeddings == 2 &&
                        embed_info.is_ready == RAC_TRUE &&
                        g_mlx_state.embed_batch_count == 2 &&
                        g_mlx_state.embedding_info_count == 1 &&
                        g_mlx_state.last_kind ==
                            RAC_MLX_SESSION_KIND_EMBEDDINGS;
  rac_embeddings_result_free(&embed_result);
  embed_vt->embedding_ops->destroy(embed);
  if (!embed_ok) {
    result.details = "MLX embedding direct callbacks were not all exercised";
    rac_backend_mlx_unregister();
    return result;
  }

  void *stt = nullptr;
  const int16_t samples[] = {0, 128, -128, 256};
  rac_stt_result_t stt_result{};
  std::string stt_stream;
  rac_stt_info_t stt_info{};
  if (stt_vt->stt_ops->create("mlx.direct.stt", nullptr, &stt) != RAC_SUCCESS ||
      stt_vt->stt_ops->initialize(stt, "/tmp/mlx-direct-stt") != RAC_SUCCESS ||
      stt_vt->stt_ops->transcribe(stt, samples, sizeof(samples), nullptr,
                                  &stt_result) != RAC_SUCCESS ||
      stt_vt->stt_ops->transcribe_stream(stt, samples, sizeof(samples), nullptr,
                                         append_stt_callback,
                                         &stt_stream) != RAC_SUCCESS ||
      stt_vt->stt_ops->get_info(stt, &stt_info) != RAC_SUCCESS ||
      stt_vt->stt_ops->cleanup(stt) != RAC_SUCCESS) {
    result.details = "MLX STT direct ops failed";
    if (stt_result.text) {
      rac_stt_result_free(&stt_result);
    }
    if (stt) {
      stt_vt->stt_ops->destroy(stt);
    }
    rac_backend_mlx_unregister();
    return result;
  }
  const bool stt_ok = stt_result.text &&
                      std::string(stt_result.text).find("mlx-stt-stub") !=
                          std::string::npos &&
                      stt_stream == "partial:mlx-stt-partial|final:mlx-stt-final" &&
                      stt_info.is_ready == RAC_TRUE &&
                      g_mlx_state.stt_transcribe_count == 1 &&
                      g_mlx_state.stt_stream_count == 1 &&
                      g_mlx_state.stt_info_count == 1 &&
                      g_mlx_state.last_kind == RAC_MLX_SESSION_KIND_STT;
  rac_stt_result_free(&stt_result);
  stt_vt->stt_ops->destroy(stt);
  if (!stt_ok) {
    result.details = "MLX STT direct callbacks were not all exercised";
    rac_backend_mlx_unregister();
    return result;
  }

  void *tts = nullptr;
  rac_tts_result_t tts_result{};
  size_t streamed_tts_bytes = 0;
  rac_tts_info_t tts_info{};
  if (tts_vt->tts_ops->create("/tmp/mlx-direct-tts", nullptr, &tts) != RAC_SUCCESS ||
      tts_vt->tts_ops->initialize(tts) != RAC_SUCCESS ||
      tts_vt->tts_ops->synthesize(tts, "say it", nullptr, &tts_result) !=
          RAC_SUCCESS ||
      tts_vt->tts_ops->synthesize_stream(tts, "stream it", nullptr,
                                         count_tts_chunk_callback,
                                         &streamed_tts_bytes) != RAC_SUCCESS ||
      tts_vt->tts_ops->stop(tts) != RAC_SUCCESS ||
      tts_vt->tts_ops->get_info(tts, &tts_info) != RAC_SUCCESS ||
      tts_vt->tts_ops->cleanup(tts) != RAC_SUCCESS) {
    result.details = "MLX TTS direct ops failed";
    rac_tts_result_free(&tts_result);
    if (tts) {
      tts_vt->tts_ops->destroy(tts);
    }
    rac_backend_mlx_unregister();
    return result;
  }
  const bool tts_ok = tts_result.audio_data &&
                      tts_result.audio_size == 8 * sizeof(float) &&
                      streamed_tts_bytes == 2 * sizeof(float) &&
                      tts_info.is_ready == RAC_TRUE &&
                      g_mlx_state.tts_synthesize_count == 1 &&
                      g_mlx_state.tts_stream_count == 1 &&
                      g_mlx_state.tts_stop_count == 1 &&
                      g_mlx_state.tts_info_count == 1 &&
                      g_mlx_state.last_kind == RAC_MLX_SESSION_KIND_TTS;
  rac_tts_result_free(&tts_result);
  tts_vt->tts_ops->destroy(tts);
  if (!tts_ok) {
    result.details = "MLX TTS direct callbacks were not all exercised";
    rac_backend_mlx_unregister();
    return result;
  }

  if (g_mlx_state.create_count != 5 || g_mlx_state.initialize_count != 5) {
    result.details =
        "MLX direct bridge should create/initialize one session per modality";
    rac_backend_mlx_unregister();
    return result;
  }

  rac_backend_mlx_unregister();
  result.passed = true;
  return result;
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
  const std::filesystem::path llm_dir = make_temp_dir("rcli-mlx-llm");
  const std::filesystem::path vlm_dir = make_temp_dir("rcli-mlx-vlm");
  const std::filesystem::path embedding_dir = make_temp_dir("rcli-mlx-embed");
  const std::filesystem::path stt_dir = make_temp_dir("rcli-mlx-stt");
  const std::filesystem::path tts_dir = make_temp_dir("rcli-mlx-tts");
  for (const auto &dir : {llm_dir, vlm_dir, embedding_dir, stt_dir, tts_dir}) {
    if (!write_file(dir / "config.json", R"({"model_type":"qwen3"})") ||
        !write_file(dir / "model.safetensors", "fake-weights") ||
        !write_file(dir / "tokenizer.json", "{}")) {
      result.details = "failed to create local MLX model folder";
      return result;
    }
  }

  const std::filesystem::path input_wav = home / "input.wav";
  const std::filesystem::path output_wav = home / "output.wav";
  const std::filesystem::path input_image = home / "image.rgb";
  if (!write_file(input_image, "fake image")) {
    result.details = "failed to create fake VLM image";
    return result;
  }
  const std::vector<int16_t> pcm_samples = {0,     1024, -1024, 2048,
                                            -2048, 1024, -1024, 0};
  std::string wav_error;
  if (!rcli::wav::write_wav(input_wav.string(), pcm_samples.data(),
                            pcm_samples.size(), 16000, &wav_error)) {
    result.details = wav_error;
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
  if (!register_local_mlx_model(llm_dir, "mlx.fake.llm", "Fake MLX LLM",
                                v1::MODEL_CATEGORY_LANGUAGE) ||
      !register_local_mlx_model(vlm_dir, "mlx.fake.vlm", "Fake MLX VLM",
                                v1::MODEL_CATEGORY_MULTIMODAL) ||
      !register_local_mlx_model(embedding_dir, "mlx.fake.embed",
                                "Fake MLX Embeddings",
                                v1::MODEL_CATEGORY_EMBEDDING) ||
      !register_local_mlx_model(stt_dir, "mlx.fake.stt", "Fake MLX STT",
                                v1::MODEL_CATEGORY_SPEECH_RECOGNITION) ||
      !register_local_mlx_model(tts_dir, "mlx.fake.tts", "Fake MLX TTS",
                                v1::MODEL_CATEGORY_SPEECH_SYNTHESIS)) {
    result.details = "failed to register local MLX model";
    rcli::shutdown();
    return result;
  }

  std::string backends_json;
  if (!run_cli_or_fail({"rcli", "--json", "--no-progress", "--home",
                        home.string(), "backends"},
                       "backends", &backends_json, &result)) {
    rcli::shutdown();
    return result;
  }
  std::string backend_error;
  if (!backend_has_primitives(backends_json, "mlx",
                              {"generate_text", "vlm", "embed", "transcribe",
                               "synthesize"},
                              &backend_error)) {
    result.expected =
        "mlx backend with generate_text/vlm/embed/transcribe/synthesize "
        "primitives";
    result.actual = backend_error.empty() ? backends_json : backend_error + ": " + backends_json;
    rcli::shutdown();
    return result;
  }

  std::string list_json;
  if (!run_cli_or_fail({"rcli", "--json", "--no-progress", "--home",
                        home.string(), "list", "--all"},
                       "list", &list_json, &result)) {
    rcli::shutdown();
    return result;
  }
  if (list_json.find("\"id\":\"mlx.fake.vlm\"") == std::string::npos ||
      list_json.find("\"modality\":\"vlm\"") == std::string::npos ||
      list_json.find("\"id\":\"mlx.fake.embed\"") == std::string::npos ||
      list_json.find("\"modality\":\"embedding\"") == std::string::npos ||
      list_json.find("\"id\":\"mlx.fake.stt\"") == std::string::npos ||
      list_json.find("\"modality\":\"stt\"") == std::string::npos ||
      list_json.find("\"backend\":\"MLX\"") == std::string::npos ||
      list_json.find("\"id\":\"mlx.fake.tts\"") == std::string::npos ||
      list_json.find("\"modality\":\"tts\"") == std::string::npos) {
    result.expected = "MLX VLM/embedding/STT/TTS rows from rcli list --all";
    result.actual = list_json;
    rcli::shutdown();
    return result;
  }

  std::string run_json;
  if (!run_cli_or_fail({"rcli", "--json", "--no-progress", "--home",
                        home.string(), "run", "mlx.fake.llm", "Hello MLX",
                        "--engine", "mlx", "--max-tokens", "4"},
                       "LLM", &run_json, &result)) {
    rcli::shutdown();
    return result;
  }
  if (run_json.find("\"model\":\"mlx.fake.llm\"") == std::string::npos ||
      run_json.find("\"response\":\"mlx-stub: Hello MLX\"") ==
          std::string::npos) {
    result.expected = "JSON response from MLX stream callback";
    result.actual = run_json;
    rcli::shutdown();
    return result;
  }
  if (g_mlx_state.create_count != 1 || g_mlx_state.initialize_count != 1 ||
      g_mlx_state.stream_count != 1 ||
      g_mlx_state.last_kind != RAC_MLX_SESSION_KIND_LLM) {
    result.details =
        "MLX LLM callback counts/kind were not exercised as expected";
    rcli::shutdown();
    return result;
  }
  if (g_mlx_state.last_model_path != llm_dir.string()) {
    result.expected = llm_dir.string();
    result.actual = g_mlx_state.last_model_path;
    result.details = "MLX LLM runtime should receive the model folder, not "
                     "model.safetensors";
    rcli::shutdown();
    return result;
  }

  std::string vlm_json;
  if (!run_cli_or_fail({"rcli", "--json", "--no-progress", "--home",
                        home.string(), "run", "mlx.fake.vlm",
                        "What is in the image?", "--image",
                        input_image.string(), "--engine", "mlx", "--max-tokens",
                        "4"},
                       "VLM", &vlm_json, &result)) {
    rcli::shutdown();
    return result;
  }
  if (vlm_json.find("\"model\":\"mlx.fake.vlm\"") == std::string::npos ||
      vlm_json.find("\"response\":\"mlx-vlm-stub: What is in the image?\"") ==
          std::string::npos) {
    result.expected = "JSON VLM response from MLX callback";
    result.actual = vlm_json;
    rcli::shutdown();
    return result;
  }
  if (g_mlx_state.vlm_process_count != 1 ||
      g_mlx_state.last_kind != RAC_MLX_SESSION_KIND_VLM) {
    result.details =
        "MLX VLM callback count/kind was not exercised as expected";
    rcli::shutdown();
    return result;
  }
  if (g_mlx_state.last_model_path != vlm_dir.string()) {
    result.expected = vlm_dir.string();
    result.actual = g_mlx_state.last_model_path;
    result.details = "MLX VLM runtime should receive the model folder, not "
                     "model.safetensors";
    rcli::shutdown();
    return result;
  }

  std::string embed_json;
  if (!run_cli_or_fail({"rcli", "--json", "--no-progress", "--home",
                        home.string(), "embed", "Hello MLX embeddings",
                        "--model", "mlx.fake.embed", "--text", "Batch item"},
                       "embedding", &embed_json, &result)) {
    rcli::shutdown();
    return result;
  }
  if (embed_json.find("\"model\":\"mlx.fake.embed\"") == std::string::npos ||
      embed_json.find("\"dimension\":2") == std::string::npos ||
      embed_json.find("\"count\":2") == std::string::npos ||
      embed_json.find("\"values\":[1,0.5]") == std::string::npos) {
    result.expected = "JSON embedding vectors from MLX callback";
    result.actual = embed_json;
    rcli::shutdown();
    return result;
  }
  if (g_mlx_state.embed_batch_count != 1 ||
      g_mlx_state.last_kind != RAC_MLX_SESSION_KIND_EMBEDDINGS ||
      g_mlx_state.last_embed_batch_size != 2) {
    result.details =
        "MLX embedding callback count/kind/batch size was not exercised as expected";
    rcli::shutdown();
    return result;
  }
  if (g_mlx_state.last_model_path != embedding_dir.string()) {
    result.expected = embedding_dir.string();
    result.actual = g_mlx_state.last_model_path;
    result.details = "MLX embedding runtime should receive the model folder, not "
                     "model.safetensors";
    rcli::shutdown();
    return result;
  }

  std::string stt_json;
  if (!run_cli_or_fail({"rcli", "--json", "--no-progress", "--home",
                        home.string(), "stt", "mlx.fake.stt", "--input",
                        input_wav.string()},
                       "STT", &stt_json, &result)) {
    rcli::shutdown();
    return result;
  }
  if (stt_json.find("\"model\":\"mlx.fake.stt\"") == std::string::npos ||
      stt_json.find("\"text\":\"mlx-stt-stub: ") == std::string::npos) {
    result.expected = "JSON STT response from MLX callback";
    result.actual = stt_json;
    rcli::shutdown();
    return result;
  }
  if (g_mlx_state.stt_transcribe_count != 1 ||
      g_mlx_state.last_kind != RAC_MLX_SESSION_KIND_STT ||
      g_mlx_state.last_audio_size != pcm_samples.size() * sizeof(int16_t)) {
    result.details = "MLX STT callback counts/kind/audio size were not "
                     "exercised as expected";
    rcli::shutdown();
    return result;
  }
  if (g_mlx_state.last_model_path != stt_dir.string()) {
    result.expected = stt_dir.string();
    result.actual = g_mlx_state.last_model_path;
    result.details = "MLX STT runtime should receive the model folder, not "
                     "model.safetensors";
    rcli::shutdown();
    return result;
  }

  std::string tts_json;
  const bool tts_ok = run_cli_or_fail(
      {"rcli", "--json", "--no-progress", "--home", home.string(), "tts",
       "mlx.fake.tts", "--text", "Hello MLX audio", "--output",
       output_wav.string()},
      "TTS", &tts_json, &result);
  rcli::shutdown();
  if (!tts_ok) {
    return result;
  }
  if (tts_json.find("\"voice\":\"mlx.fake.tts\"") == std::string::npos ||
      tts_json.find("\"sample_rate\":22050") == std::string::npos ||
      !std::filesystem::exists(output_wav) ||
      std::filesystem::file_size(output_wav) <= 44) {
    result.expected = "JSON TTS response and written WAV from MLX callback";
    result.actual = tts_json;
    return result;
  }
  if (g_mlx_state.tts_synthesize_count != 1 ||
      g_mlx_state.last_kind != RAC_MLX_SESSION_KIND_TTS ||
      g_mlx_state.last_tts_text != "Hello MLX audio") {
    result.details =
        "MLX TTS callback counts/kind/text were not exercised as expected";
    return result;
  }
  if (g_mlx_state.last_model_path != tts_dir.string()) {
    result.expected = tts_dir.string();
    result.actual = g_mlx_state.last_model_path;
    result.details = "MLX TTS runtime should receive the model folder, not "
                     "model.safetensors";
    return result;
  }
  if (g_mlx_state.create_count != 5 || g_mlx_state.initialize_count != 5) {
    result.details =
        "MLX create/initialize should run once per LLM/VLM/embedding/STT/TTS model";
    return result;
  }

  result.passed = true;
  return result;
}

} // namespace

int main(int argc, char **argv) {
  TestSuite suite("rcli_mlx_e2e");
  suite.add("mlx_callback_bridge_all_slots", test_mlx_callback_bridge_all_slots);
  suite.add("rcli_mlx_run_end_to_end", test_rcli_mlx_run_end_to_end);
  return suite.run(argc, argv);
}
