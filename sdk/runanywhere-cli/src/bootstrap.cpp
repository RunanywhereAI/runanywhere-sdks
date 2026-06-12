#include "bootstrap.h"

#include <string>

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

#include "catalog/catalog.h"
#include "config/cli_paths.h"
#include "io/output.h"

#if defined(RCLI_HAS_LLAMACPP)
#include "rac/backends/rac_llm_llamacpp.h"
#endif
#if defined(RCLI_HAS_ONNX)
#include "rac/backends/rac_vad_onnx.h"
#endif
#if defined(RCLI_HAS_SHERPA)
#include "rac/plugin/rac_plugin_entry_sherpa.h"
#endif

namespace rcli {

namespace {

// rac_init requires the adapter pointer to stay valid until rac_shutdown.
rac_platform_adapter_t g_adapter{};
bool g_bootstrapped = false;

rac_log_level_t log_level_for(const GlobalOptions &options) {
  if (options.verbose) {
    return RAC_LOG_DEBUG;
  }
  // Quiet by default (like ollama): SDK internals only surface at ERROR.
  // rcli prints its own user-facing status/progress lines on stderr.
  return RAC_LOG_ERROR;
}

} // namespace

rac_result_t bootstrap(const GlobalOptions &options, Bootstrapped *out) {
  const std::string home = paths::resolve_home(options.home_override);
  if (home.empty()) {
    out::error_line("cannot resolve RunAnywhere home ($HOME unset?)");
    return RAC_ERROR_NOT_INITIALIZED;
  }

  if (!g_bootstrapped) {
    rac_result_t rc = rac_desktop_adapter_init(nullptr, &g_adapter);
    if (rc != RAC_SUCCESS) {
      out::error_line("desktop adapter init failed: " +
                      out::describe_result(rc));
      return rc;
    }

    rc = rac_model_paths_set_base_dir(home.c_str());
    if (rc != RAC_SUCCESS) {
      out::error_line("model paths init failed: " + out::describe_result(rc));
      return rc;
    }

    // Configure the logger BEFORE rac_init so init-time logs obey the CLI
    // level too. Two distinct knobs: stderr_always off makes the adapter
    // the single sink (commons' own stderr mirror would double every
    // line); the logger min level is a separate gate from
    // rac_config_t.log_level.
    const rac_log_level_t log_level = log_level_for(options);
    rac_logger_set_stderr_always(RAC_FALSE);
    rac_logger_set_min_level(log_level);

    rac_config_t config = {};
    config.platform_adapter = &g_adapter;
    config.log_level = log_level;
    config.log_tag = "rcli";
    rc = rac_init(&config);
    if (rc != RAC_SUCCESS) {
      out::error_line("rac_init failed: " + out::describe_result(rc));
      return rc;
    }

    rc = rac_desktop_http_transport_register();
    if (rc != RAC_SUCCESS) {
      out::error_line("HTTP transport registration failed: " +
                      out::describe_result(rc));
      return rc;
    }

#if defined(RCLI_HAS_LLAMACPP)
    if (rac_backend_llamacpp_register() != RAC_SUCCESS) {
      out::status_line("warning: llamacpp backend failed to register");
    }
#endif
#if defined(RCLI_HAS_ONNX)
    if (rac_backend_onnx_register() != RAC_SUCCESS) {
      out::status_line("warning: onnx backend failed to register");
    }
#endif
#if defined(RCLI_HAS_SHERPA)
    if (rac_backend_sherpa_register() != RAC_SUCCESS) {
      out::status_line("warning: sherpa backend failed to register");
    }
#endif

    // Built-in catalog — same per-launch registration pattern as the
    // example apps (the registry is in-memory). Ad-hoc URL/HF pulls from
    // previous runs come back via the commons model-folder manifest
    // restore inside the registry refresh/discover paths.
    catalog::register_all();

    g_bootstrapped = true;
  }

  if (out) {
    out->home = home;
    char models[1024] = {};
    if (rac_model_paths_get_models_directory(models, sizeof(models)) ==
        RAC_SUCCESS) {
      out->models_dir = models;
    }
  }
  return RAC_SUCCESS;
}

void shutdown() {
  if (g_bootstrapped) {
    rac_shutdown();
    g_bootstrapped = false;
  }
}

} // namespace rcli
