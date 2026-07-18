#include "bootstrap.h"

#include <cstring>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <vector>
#if !defined(_WIN32)
#include <unistd.h>
#endif

#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/device/rac_device_identity.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/lifecycle/rac_sdk_init.h"
#include "rac/foundation/rac_proto_buffer.h"

#include "sdk_init.pb.h"

#include "catalog/catalog.h"
#include "config/cli_paths.h"
#include "io/output.h"

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

// Owns the telemetry manager for the process lifetime so the terminal flush in
// rac_shutdown() can deliver through our HTTP callback before teardown.
rac_telemetry_manager_t *g_telemetry_manager = nullptr;

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

rac_environment_t environment_from_name(const std::string &name) {
  if (name == "production" || name == "prod")
    return RAC_ENV_PRODUCTION;
  if (name == "staging")
    return RAC_ENV_STAGING;
  return RAC_ENV_DEVELOPMENT;
}

::runanywhere::v1::SdkInitEnvironment
proto_environment_from_name(const std::string &name) {
  if (name == "production" || name == "prod")
    return ::runanywhere::v1::SDK_INIT_ENVIRONMENT_PRODUCTION;
  if (name == "staging")
    return ::runanywhere::v1::SDK_INIT_ENVIRONMENT_STAGING;
  return ::runanywhere::v1::SDK_INIT_ENVIRONMENT_DEVELOPMENT;
}

void initialize_sdk_metadata() {
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

  const std::string api_key =
      first_env_value("RUNANYWHERE_API_KEY", nullptr, nullptr);
  const std::string base_url =
      first_env_value("RUNANYWHERE_BASE_URL", nullptr, nullptr);
  const std::string environment_name =
      first_env_value("RUNANYWHERE_ENVIRONMENT", nullptr, nullptr);

  rac_sdk_config_t sdk_config = {};
  sdk_config.environment = environment_from_name(environment_name);
  sdk_config.api_key = api_key.c_str();
  sdk_config.base_url = base_url.c_str();
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

// Delivers a queued telemetry batch over the desktop HTTP transport. Wired via
// rac_telemetry_manager_set_http_callback (user_data = the manager) so the
// outcome is reported back through rac_telemetry_manager_http_complete. Mirrors
// the control-plane POST performed by commons' auth path.
void rcli_telemetry_http_callback(void *user_data, const char *endpoint,
                                  const char *json_body, size_t json_length,
                                  rac_bool_t requires_auth) {
  auto *manager = static_cast<rac_telemetry_manager_t *>(user_data);
  const char *base_url = rac_state_get_base_url();
  if (base_url == nullptr || base_url[0] == '\0' ||
      rac_http_transport_is_registered() != RAC_TRUE) {
    if (manager != nullptr) {
      rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
                                          "telemetry transport unavailable");
    }
    return;
  }

  char url[2048] = {};
  if (rac_build_url(base_url, endpoint, url, sizeof(url)) < 0) {
    if (manager != nullptr) {
      rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
                                          "telemetry URL build failed");
    }
    return;
  }

  std::vector<rac_http_header_kv_t> headers;
  const rac_http_header_kv_t *defaults = nullptr;
  size_t default_count = 0;
  if (rac_http_default_headers(&defaults, &default_count) == RAC_SUCCESS &&
      defaults != nullptr) {
    headers.assign(defaults, defaults + default_count);
  }
  std::string auth_value;
  if (requires_auth == RAC_TRUE) {
    const char *token = rac_auth_get_access_token();
    if (token != nullptr && token[0] != '\0') {
      auth_value = std::string("Bearer ") + token;
      headers.push_back({"Authorization", auth_value.c_str()});
    }
  }

  rac_http_client_t *client = nullptr;
  if (rac_http_client_create(&client) != RAC_SUCCESS) {
    if (manager != nullptr) {
      rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
                                          "telemetry client create failed");
    }
    return;
  }

  rac_http_request_t request = {};
  request.method = "POST";
  request.url = url;
  request.headers = headers.empty() ? nullptr : headers.data();
  request.header_count = headers.size();
  request.body_bytes = reinterpret_cast<const uint8_t *>(json_body);
  request.body_len = json_length;
  request.timeout_ms = rac_env_default_http_timeout_ms(rac_state_get_environment());
  request.follow_redirects = RAC_FALSE;

  rac_http_response_t response = {};
  const rac_result_t rc = rac_http_request_send(client, &request, &response);
  rac_http_client_destroy(client);

  const bool ok =
      rc == RAC_SUCCESS && response.status >= 200 && response.status < 300;
  std::string body;
  if (response.body_bytes != nullptr && response.body_len > 0) {
    body.assign(reinterpret_cast<const char *>(response.body_bytes),
                response.body_len);
  }
  if (!ok) {
    // Surface the exact backend rejection (status + response body) so schema
    // mismatches (e.g. strict extra_forbidden 422s) are diagnosable from rcli.
    out::status_line(std::string("telemetry POST ") + (endpoint ? endpoint : "?") +
                     " -> rc=" + out::describe_result(rc) +
                     " http=" + std::to_string(response.status) +
                     " body=" + (body.empty() ? "(empty)" : body));
    // DEBUG: dump the exact request JSON so a malformed offset can be inspected.
    if (const char *dump = std::getenv("RCLI_TELEMETRY_DUMP");
        dump != nullptr && dump[0] != '\0' && json_body != nullptr) {
      if (FILE *fp = std::fopen(dump, "ab")) {
        std::fwrite(json_body, 1, json_length, fp);
        std::fputc('\n', fp);
        std::fclose(fp);
      }
    }
  }
  if (manager != nullptr) {
    rac_telemetry_manager_http_complete(manager, ok ? RAC_TRUE : RAC_FALSE,
                                        body.empty() ? nullptr : body.c_str(),
                                        ok ? nullptr : "telemetry POST failed");
  }
  rac_http_response_free(&response);
}

// Runs the canonical two-phase SDK init so rcli authenticates and telemetry
// actually flushes. Phase 1 sets environment + credentials; Phase 2
// authenticates, registers the device, and enables the telemetry sink.
// Credentials come from the environment (RUNANYWHERE_API_KEY /
// RUNANYWHERE_BASE_URL / RUNANYWHERE_ENVIRONMENT) so no secrets live in source.
// When credentials are absent, rcli stays in local dev mode (no auth, no
// telemetry) exactly as before.
void initialize_telemetry_auth() {
  const std::string api_key =
      first_env_value("RUNANYWHERE_API_KEY", nullptr, nullptr);
  const std::string base_url =
      first_env_value("RUNANYWHERE_BASE_URL", nullptr, nullptr);
  const std::string environment_name =
      first_env_value("RUNANYWHERE_ENVIRONMENT", nullptr, nullptr);

  if (api_key.empty() || base_url.empty()) {
    return; // Local dev mode — telemetry not sent (staging/prod only).
  }

  // Enable the auth manager. NULL secure storage: tokens are not persisted
  // across runs (fine for a CLI session); authentication still runs per run.
  rac_auth_init(nullptr);

  char device_id[RAC_DEVICE_ID_BUFFER_MIN_SIZE] = {};
  if (rac_device_get_or_create_persistent_id(device_id, sizeof(device_id)) !=
      RAC_SUCCESS) {
    device_id[0] = '\0';
  }

  // Create + register the telemetry sink BEFORE Phase 2 so its flush has a sink
  // and events emitted during subsequent commands are tracked. Delivery runs
  // through rcli_telemetry_http_callback over the desktop HTTP transport; the
  // terminal batch flushes in rac_shutdown() during teardown.
  g_telemetry_manager = rac_telemetry_manager_create(
      environment_from_name(environment_name),
      device_id[0] != '\0' ? device_id : "", desktop_platform(), RCLI_VERSION);
  if (g_telemetry_manager != nullptr) {
    rac_telemetry_manager_set_http_callback(
        g_telemetry_manager, rcli_telemetry_http_callback, g_telemetry_manager);
    rac_events_set_telemetry_sink(g_telemetry_manager);
  }

  ::runanywhere::v1::SdkInitPhase1Request phase1;
  phase1.set_environment(proto_environment_from_name(environment_name));
  phase1.set_api_key(api_key);
  phase1.set_base_url(base_url);
  if (device_id[0] != '\0') {
    phase1.set_device_id(device_id);
  }
  phase1.set_platform(desktop_platform());
  phase1.set_sdk_version(RCLI_VERSION);

  std::string phase1_bytes;
  if (!phase1.SerializeToString(&phase1_bytes)) {
    out::status_line("warning: telemetry phase 1 serialize failed");
    return;
  }

  rac_proto_buffer_t phase1_out;
  rac_proto_buffer_init(&phase1_out);
  rac_result_t rc = rac_sdk_init_phase1_proto(
      reinterpret_cast<const uint8_t *>(phase1_bytes.data()),
      phase1_bytes.size(), &phase1_out);
  rac_proto_buffer_free(&phase1_out);
  if (rc != RAC_SUCCESS) {
    out::status_line("warning: telemetry phase 1 failed: " +
                     out::describe_result(rc));
    return;
  }

  ::runanywhere::v1::SdkInitPhase2Request phase2;
  phase2.set_flush_telemetry(true);
  phase2.set_discover_downloaded_models(true);
  phase2.set_rescan_local_models(true);

  std::string phase2_bytes;
  if (!phase2.SerializeToString(&phase2_bytes)) {
    out::status_line("warning: telemetry phase 2 serialize failed");
    return;
  }

  rac_proto_buffer_t phase2_out;
  rac_proto_buffer_init(&phase2_out);
  rc = rac_sdk_init_phase2_proto(
      reinterpret_cast<const uint8_t *>(phase2_bytes.data()),
      phase2_bytes.size(), &phase2_out);

  ::runanywhere::v1::SdkInitResult result;
  const bool parsed = phase2_out.status == RAC_SUCCESS &&
                      phase2_out.data != nullptr &&
                      result.ParseFromArray(phase2_out.data,
                                            static_cast<int>(phase2_out.size));
  rac_proto_buffer_free(&phase2_out);

  if (rc != RAC_SUCCESS) {
    out::status_line("warning: telemetry phase 2 failed: " +
                     out::describe_result(rc));
    return;
  }

  if (parsed) {
    std::string note = std::string("telemetry ready | http_configured=") +
                       (result.http_configured() ? "yes" : "no") +
                       " device_registered=" +
                       (result.device_registered() ? "yes" : "no");
    if (!result.warning().empty()) {
      note += " | " + result.warning();
    }
    out::status_line(note);
  }
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

    initialize_sdk_metadata();
    initialize_telemetry_auth();

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
    // rac_shutdown() flushes the terminal telemetry batch through the
    // registered sink (our HTTP callback) before clearing lifetime state.
    rac_shutdown();
    rac_events_set_telemetry_sink(nullptr);
    if (g_telemetry_manager != nullptr) {
      rac_telemetry_manager_destroy(g_telemetry_manager);
      g_telemetry_manager = nullptr;
    }
    g_bootstrapped = false;
  }
}

} // namespace rcli
