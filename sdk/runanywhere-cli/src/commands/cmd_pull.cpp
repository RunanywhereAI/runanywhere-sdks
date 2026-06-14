/**
 * @file cmd_pull.cpp
 * @brief `rcli pull <model|hf.co/...|url>` — download via the commons
 *        orchestrator: plan → start → progress callback → terminal state.
 *
 * SIGINT cancels the task (partial bytes preserved → re-pull resumes via the
 * plan's can_resume path). Exit codes: 0 done, 1 failure, 130 user cancel.
 */

#include "commands/commands.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <csignal>
#include <mutex>
#include <string>

#include "download_service.pb.h"
#include "model_types.pb.h"
#include "rac/core/rac_core.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#include "catalog/model_ref.h"
#include "io/output.h"
#include "io/proto.h"
#include "progress/progress_bar.h"

namespace rcli::commands {

namespace {

namespace v1 = runanywhere::v1;

volatile std::sig_atomic_t g_interrupted = 0;

void on_sigint(int /*signum*/) { g_interrupted = 1; }

struct PullState {
  std::mutex mutex;
  std::condition_variable cv;
  v1::DownloadProgress last;
  bool terminal = false;
  bool got_progress = false;
  std::string model_id; // filter: only this model's updates
};

PullState *g_state = nullptr;

void progress_callback(const uint8_t *proto_bytes, size_t proto_size,
                       void * /*user_data*/) {
  if (!g_state) {
    return;
  }
  v1::DownloadProgress progress;
  if (!progress.ParseFromArray(proto_bytes, static_cast<int>(proto_size))) {
    return;
  }
  std::lock_guard<std::mutex> lock(g_state->mutex);
  if (!g_state->model_id.empty() && progress.model_id() != g_state->model_id) {
    return;
  }
  g_state->last = progress;
  g_state->got_progress = true;
  switch (progress.state()) {
  case v1::DOWNLOAD_STATE_COMPLETED:
  case v1::DOWNLOAD_STATE_FAILED:
  case v1::DOWNLOAD_STATE_CANCELLED:
    g_state->terminal = true;
    break;
  default:
    break;
  }
  g_state->cv.notify_all();
}

} // namespace

int pull_model_flow(const GlobalOptions &options, const std::string &model_id) {
  const model_ref::Resolved resolved{model_id, false};
  std::string error;

  // The orchestrator plans from embedded metadata (it does not consult the
  // registry), so fetch the saved ModelInfo first.
  v1::ModelInfo model_info;
  {
    rac_proto_buffer_t info_out;
    rac_proto_buffer_init(&info_out);
    const rac_result_t get_rc = rac_model_registry_get_proto_buffer(
        rac_get_model_registry(), resolved.model_id.c_str(), &info_out);
    // parse unconditionally: it interprets the {status,error_message}
    // envelope and frees the buffer on every path (no leak on get failure).
    if (!proto::parse_proto_buffer(&info_out, &model_info, &error) ||
        get_rc != RAC_SUCCESS) {
      out::error_line("model not found in registry: " + resolved.model_id +
                      (error.empty() ? "" : " (" + error + ")"));
      return 1;
    }
  }

  // Plan
  v1::DownloadPlanRequest plan_request;
  plan_request.set_model_id(resolved.model_id);
  *plan_request.mutable_model() = model_info;
  plan_request.set_resume_existing(true);
  const std::string plan_bytes = proto::serialize(plan_request);

  rac_proto_buffer_t plan_out;
  rac_proto_buffer_init(&plan_out);
  rac_result_t rc = rac_download_plan_proto(
      reinterpret_cast<const uint8_t *>(plan_bytes.data()), plan_bytes.size(),
      &plan_out);
  if (rc != RAC_SUCCESS) {
    rac_proto_buffer_free(&plan_out);
    out::error_line("download plan failed: " + out::describe_result(rc));
    return 1;
  }
  v1::DownloadPlanResult plan;
  if (!proto::parse_proto_buffer(&plan_out, &plan, &error)) {
    out::error_line("download plan failed: " + error);
    return 1;
  }
  if (!plan.can_start()) {
    const std::string reason =
        plan.error_message().empty() ? "plan rejected" : plan.error_message();
    out::error_line("cannot pull " + resolved.model_id + ": " + reason);
    return 1;
  }
  if (plan.total_bytes() == 0 && plan.can_resume()) {
    out::status_line("resuming partial download");
  }

  // Progress wiring before start so no early events are missed.
  PullState state;
  state.model_id = resolved.model_id;
  g_state = &state;
  rac_download_set_progress_proto_callback(progress_callback, nullptr);

  progress::ProgressRenderer renderer(!options.no_progress && !options.json);

  // Start
  v1::DownloadStartRequest start_request;
  start_request.set_model_id(resolved.model_id);
  *start_request.mutable_plan() = plan;
  start_request.set_resume(plan.can_resume());
  start_request.set_resume_token(plan.resume_token());
  start_request.set_update_registry_on_completion(true);
  const std::string start_bytes = proto::serialize(start_request);

  rac_proto_buffer_t start_out;
  rac_proto_buffer_init(&start_out);
  rc = rac_download_start_proto(
      reinterpret_cast<const uint8_t *>(start_bytes.data()), start_bytes.size(),
      &start_out);
  v1::DownloadStartResult start;
  if (rc != RAC_SUCCESS ||
      !proto::parse_proto_buffer(&start_out, &start, &error)) {
    rac_download_set_progress_proto_callback(nullptr, nullptr);
    g_state = nullptr;
    out::error_line("download start failed: " +
                    (rc != RAC_SUCCESS ? out::describe_result(rc) : error));
    return 1;
  }
  if (!start.accepted()) {
    rac_download_set_progress_proto_callback(nullptr, nullptr);
    g_state = nullptr;
    out::error_line("download rejected: " + start.error_message());
    return 1;
  }

  // Wait for terminal state; SIGINT cancels once (partial bytes preserved).
  g_interrupted = 0;
  auto *previous_handler = std::signal(SIGINT, on_sigint);
  bool cancel_sent = false;
  v1::DownloadProgress final_progress;
  {
    std::unique_lock<std::mutex> lock(state.mutex);
    while (!state.terminal) {
      state.cv.wait_for(lock, std::chrono::milliseconds(200));
      if (state.got_progress && !state.terminal) {
        renderer.update(state.last);
      }
      if (g_interrupted && !cancel_sent) {
        cancel_sent = true;
        lock.unlock();
        renderer.finish();
        out::status_line(
            "cancelling (partial bytes kept — re-pull resumes)...");
        v1::DownloadCancelRequest cancel_request;
        cancel_request.set_task_id(start.task_id());
        cancel_request.set_model_id(resolved.model_id);
        cancel_request.set_delete_partial_bytes(false);
        const std::string cancel_bytes = proto::serialize(cancel_request);
        rac_proto_buffer_t cancel_out;
        rac_proto_buffer_init(&cancel_out);
        rac_download_cancel_proto(
            reinterpret_cast<const uint8_t *>(cancel_bytes.data()),
            cancel_bytes.size(), &cancel_out);
        rac_proto_buffer_free(&cancel_out);
        lock.lock();
      }
    }
    final_progress = state.last;
    if (!cancel_sent) {
      renderer.update(final_progress);
    }
  }
  renderer.finish();
  std::signal(SIGINT, previous_handler);
  rac_download_set_progress_proto_callback(nullptr, nullptr);
  g_state = nullptr;

  switch (final_progress.state()) {
  case v1::DOWNLOAD_STATE_COMPLETED:
    break;
  case v1::DOWNLOAD_STATE_CANCELLED:
    out::error_line("pull cancelled");
    return 130;
  default:
    out::error_line("pull failed: " + (final_progress.error_message().empty()
                                           ? "download error"
                                           : final_progress.error_message()));
    return 1;
  }

  // Report the saved entry. parse runs unconditionally: it interprets the
  // {status,error_message} envelope and frees the buffer on every path.
  rac_proto_buffer_t model_out;
  rac_proto_buffer_init(&model_out);
  v1::ModelInfo model;
  const rac_result_t report_rc = rac_model_registry_get_proto_buffer(
      rac_get_model_registry(), resolved.model_id.c_str(), &model_out);
  const bool report_parsed =
      proto::parse_proto_buffer(&model_out, &model, nullptr);
  if (report_rc == RAC_SUCCESS && report_parsed) {
    if (options.json) {
      out::JsonWriter json;
      json.begin_object()
          .field("id", model.id())
          .field("name", model.name())
          .field("local_path", model.local_path())
          .field("bytes",
                 static_cast<int64_t>(final_progress.bytes_downloaded()))
          .end_object();
      out::result_line(json.str());
    } else {
      out::result_line(
          "pulled " + model.id() +
          (model.local_path().empty() ? "" : " → " + model.local_path()));
    }
  } else {
    out::result_line("pulled " + resolved.model_id);
  }
  return 0;
}

void register_pull(CLI::App &app, GlobalOptions &options) {
  CLI::App *cmd = app.add_subcommand(
      "pull", "Download a model (catalog id, hf.co/... or direct URL)");
  auto ref = std::make_shared<std::string>();
  cmd->add_option("model", *ref, "Model id, alias, hf.co/org/repo/file or URL")
      ->required();
  cmd->callback([&options, ref]() {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
      throw CLI::RuntimeError(1);
    }
    model_ref::Resolved resolved;
    std::string error;
    if (model_ref::resolve(*ref, &resolved, &error) != RAC_SUCCESS) {
      out::error_line(error);
      throw CLI::RuntimeError(1);
    }
    const int exit_code = pull_model_flow(options, resolved.model_id);
    if (exit_code != 0) {
      throw CLI::RuntimeError(exit_code);
    }
  });
}

} // namespace rcli::commands
