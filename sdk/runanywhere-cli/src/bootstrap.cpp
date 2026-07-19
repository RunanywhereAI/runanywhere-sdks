#include "bootstrap.h"

#include <cstring>
#include <cstdlib>
#include <string>
#if !defined(_WIN32)
#include <unistd.h>
#endif

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/device/rac_device_identity.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/network/rac_environment.h"

#include "catalog/catalog.h"
#include "config/cli_paths.h"
#include "io/output.h"
#include "net/control_plane.h"

#if defined(RCLI_HAS_LLAMACPP)
#include "rac/backends/rac_llm_llamacpp.h"
#endif
#if defined(RCLI_HAS_ONNX)
#include "rac/plugin/rac_plugin_entry_onnx.h"
#endif
#if defined(RCLI_HAS_SHERPA)
#include "rac/plugin/rac_plugin_entry_sherpa.h"
#endif
#if defined(RCLI_HAS_MLX)
#include "rac/backends/rac_mlx.h"
#endif
#if defined(RCLI_HAS_COREML)
// The coreml engine (Apple-only, serves DIFFUSION) has no dedicated
// rac_backend_coreml_register() fn; register its plugin entry directly. This
// call also keeps the static rac_backend_coreml archive linked (references
// rac_plugin_entry_coreml), mirroring how the other backends stay alive.
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_coreml.h"
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

std::string first_env_value(const char *first, const char *second,
                            const char *third) {
  const char *keys[] = {first, second, third};
  for (const char *key : keys) {
    if (!key) {
      continue;
    }
    const char *value = std::getenv(key);
    if (value && value[0] != '\0') {
      return value;
    }
  }
  return {};
}

std::string normalize_locale(std::string locale) {
  const std::size_t encoding = locale.find('.');
  if (encoding != std::string::npos) {
    locale.resize(encoding);
  }
  const std::size_t modifier = locale.find('@');
  if (modifier != std::string::npos) {
    locale.resize(modifier);
  }
  if (locale.empty() || locale == "C" || locale == "POSIX") {
    return {};
  }
  for (char &ch : locale) {
    if (ch == '_') {
      ch = '-';
    }
  }
  return locale;
}

std::string detect_locale() {
  return normalize_locale(first_env_value("LC_ALL", "LC_MESSAGES", "LANG"));
}

std::string strip_timezone_prefix(const std::string &path) {
  const char *prefixes[] = {"/usr/share/zoneinfo/",
                            "/var/db/timezone/zoneinfo/",
                            "/usr/share/lib/zoneinfo/"};
  for (const char *prefix : prefixes) {
    const std::size_t len = std::strlen(prefix);
    if (path.compare(0, len, prefix) == 0) {
      return path.substr(len);
    }
  }

  const std::string marker = "zoneinfo/";
  const std::size_t marker_pos = path.find(marker);
  if (marker_pos != std::string::npos) {
    return path.substr(marker_pos + marker.size());
  }

  return {};
}

std::string detect_timezone() {
  std::string tz = first_env_value("TZ", nullptr, nullptr);
  if (!tz.empty()) {
    if (tz[0] == ':') {
      tz.erase(0, 1);
    }
    return tz;
  }

#if !defined(_WIN32)
  char link_target[1024] = {};
  const ssize_t len =
      readlink("/etc/localtime", link_target, sizeof(link_target) - 1);
  if (len > 0) {
    link_target[len] = '\0';
    return strip_timezone_prefix(link_target);
  }
#endif

  return {};
}

const char *desktop_platform() {
#if defined(__APPLE__)
  return "macos";
#elif defined(__linux__)
  return "linux";
#elif defined(_WIN32)
  return "windows";
#else
  return "desktop";
#endif
}

void initialize_sdk_metadata(const Connection &connection) {
  char device_id[RAC_DEVICE_ID_BUFFER_MIN_SIZE] = {};
  const rac_result_t device_rc =
      rac_device_get_or_create_persistent_id(device_id, sizeof(device_id));
  if (device_rc != RAC_SUCCESS) {
    out::status_line("warning: device identity unavailable: " +
                     out::describe_result(device_rc));
    device_id[0] = '\0';
  }

  const std::string locale = detect_locale();
  const std::string timezone = detect_timezone();

  // Mirror rac_sdk_init_phase1_proto's step order: runtime state first (the
  // auth / device-registration / telemetry paths read env + credentials from
  // rac_state), then the copied SDK configuration + client info.
  const rac_result_t state_rc = rac_state_initialize(
      connection.environment, connection.api_key.c_str(),
      connection.base_url.c_str(), device_id[0] != '\0' ? device_id : "");
  if (state_rc != RAC_SUCCESS) {
    out::status_line("warning: SDK state init failed: " +
                     out::describe_result(state_rc));
  }

  rac_sdk_config_t sdk_config = {};
  sdk_config.environment = connection.environment;
  sdk_config.api_key = connection.api_key.c_str();
  sdk_config.base_url = connection.base_url.c_str();
  sdk_config.device_id = device_id[0] != '\0' ? device_id : "";
  sdk_config.platform = desktop_platform();
  sdk_config.sdk_version = RCLI_VERSION;
  sdk_config.client_info.sdk_binding = "rcli";
  sdk_config.client_info.app_identifier = "ai.runanywhere.rcli";
  sdk_config.client_info.app_name = "RunAnywhere CLI";
  sdk_config.client_info.app_version = RCLI_VERSION;
  sdk_config.client_info.app_build = nullptr;
  sdk_config.client_info.locale = locale.empty() ? nullptr : locale.c_str();
  sdk_config.client_info.timezone = timezone.empty() ? nullptr : timezone.c_str();

  const rac_validation_result_t config_rc = rac_sdk_init(&sdk_config);
  if (config_rc != RAC_VALIDATION_OK) {
    out::status_line(std::string("warning: SDK metadata init failed: ") +
                     rac_validation_error_message(config_rc));
  }
}

bool parse_environment_name(const std::string &name, rac_environment_t *out) {
  if (name.empty() || name == "dev" || name == "development") {
    *out = RAC_ENV_DEVELOPMENT;
    return true;
  }
  if (name == "staging") {
    *out = RAC_ENV_STAGING;
    return true;
  }
  if (name == "prod" || name == "production") {
    *out = RAC_ENV_PRODUCTION;
    return true;
  }
  return false;
}

} // namespace

rac_result_t resolve_connection(const GlobalOptions &options, Connection *out,
                                std::string *error) {
  Connection connection;
  if (!parse_environment_name(options.environment, &connection.environment)) {
    if (error) {
      *error = "invalid --environment '" + options.environment +
               "' (expected dev, staging or prod)";
    }
    return RAC_ERROR_INVALID_CONFIGURATION;
  }
  connection.base_url = options.base_url;
  connection.api_key = options.api_key;

  if (connection.environment == RAC_ENV_DEVELOPMENT) {
    if (!connection.api_key.empty() || !connection.base_url.empty()) {
      if (error) {
        *error = "development mode (the default) has no control plane; pass "
                 "--environment staging (or prod) together with --base-url "
                 "and --api-key";
      }
      return RAC_ERROR_INVALID_CONFIGURATION;
    }
    if (out) {
      *out = connection;
    }
    return RAC_SUCCESS;
  }

  const rac_validation_result_t key_rc = rac_validate_api_key(
      connection.api_key.empty() ? nullptr : connection.api_key.c_str(),
      connection.environment);
  if (key_rc != RAC_VALIDATION_OK) {
    if (error) {
      *error = std::string(rac_validation_error_message(key_rc)) +
               " (--api-key / RUNANYWHERE_API_KEY)";
    }
    return RAC_ERROR_INVALID_CONFIGURATION;
  }
  const rac_validation_result_t url_rc = rac_validate_base_url(
      connection.base_url.empty() ? nullptr : connection.base_url.c_str(),
      connection.environment);
  if (url_rc != RAC_VALIDATION_OK) {
    if (error) {
      *error = std::string(rac_validation_error_message(url_rc)) +
               " (--base-url / RUNANYWHERE_BASE_URL)";
    }
    return RAC_ERROR_INVALID_CONFIGURATION;
  }

  if (out) {
    *out = connection;
  }
  return RAC_SUCCESS;
}

rac_result_t bootstrap(const GlobalOptions &options, Bootstrapped *out) {
  const std::string home = paths::resolve_home(options.home_override);
  if (home.empty()) {
    out::error_line("cannot resolve RunAnywhere home ($HOME unset?)");
    return RAC_ERROR_NOT_INITIALIZED;
  }

  Connection connection;
  std::string connection_error;
  if (resolve_connection(options, &connection, &connection_error) !=
      RAC_SUCCESS) {
    out::error_line(connection_error);
    return RAC_ERROR_INVALID_CONFIGURATION;
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

    initialize_sdk_metadata(connection);

    // Platform wiring for the control-plane flows (`rcli auth login`,
    // `rcli telemetry ...`): device-manager callbacks route registration
    // POSTs through the registered curl transport. Same role the per-SDK
    // bridges play; a no-op for commands that never touch the network.
    net::register_device_callbacks();

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
#if defined(RCLI_HAS_MLX)
    if (rac_mlx_is_available() != RAC_TRUE) {
      out::status_line(
          "warning: mlx backend requires MLX runtime callbacks; skipping registration");
    } else if (rac_backend_mlx_register() != RAC_SUCCESS) {
      out::status_line(
          "warning: mlx backend requires MLX runtime callbacks; backend failed to register");
    }
#endif
#if defined(RCLI_HAS_COREML)
    if (rac_plugin_register(rac_plugin_entry_coreml()) != RAC_SUCCESS) {
      out::status_line("warning: coreml diffusion backend failed to register");
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
