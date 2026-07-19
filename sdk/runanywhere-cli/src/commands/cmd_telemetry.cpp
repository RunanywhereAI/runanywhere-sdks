/**
 * @file cmd_telemetry.cpp
 * @brief `rcli telemetry emit|blast` — model-free control-plane telemetry.
 *
 * Drives the real commons telemetry pipeline end-to-end: payloads are queued
 * with rac_telemetry_manager_track, batched + serialized by commons
 * (one POST per modality to /api/v2/sdk/telemetry/{modality}), and delivered
 * through the CLI's HTTP callback over the registered curl transport with the
 * JWT from the login handshake.
 *
 * Staging/production only (the V2 endpoints require a JWT); both commands run
 * the login handshake first, so one process does login + emit. Exits non-zero
 * when any POST fails or any tracked event never reached the backend.
 */

#include "commands/commands.h"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <iterator>
#include <map>
#include <memory>
#include <random>
#include <string>
#include <vector>

#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"

#include "io/output.h"
#include "net/control_plane.h"

#ifndef RCLI_VERSION
#define RCLI_VERSION "0.0.0-dev"
#endif

namespace rcli::commands {

namespace {

// The 12 modalities recognized by the V2 telemetry pipeline (one backend
// endpoint each), paired with a realistic terminal event type drawn from the
// canonical names the SDK emits (telemetry_manager.cpp / the backend's
// normalizer treats *.completed as terminal).
struct ModalitySpec {
    const char* name;
    const char* default_event_type;
};

constexpr ModalitySpec kModalities[] = {
    {"llm", "llm.generation.completed"},
    {"stt", "stt.transcription.completed"},
    {"tts", "tts.synthesis.completed"},
    {"vlm", "vlm.process.completed"},
    {"rag", "rag.query.completed"},
    {"imagegen", "imagegen.generate.completed"},
    {"embeddings", "embeddings.embed.completed"},
    {"vad", "vad.stopped"},
    {"voice", "voice.turn.metrics"},
    {"lora", "lora.attach.completed"},
    {"model", "model.download.completed"},
    {"system", "sdk.init.completed"},
};

const ModalitySpec* find_modality(const std::string& name) {
    for (const ModalitySpec& spec : kModalities) {
        if (name == spec.name) {
            return &spec;
        }
    }
    return nullptr;
}

std::vector<std::string> modality_names() {
    std::vector<std::string> names;
    for (const ModalitySpec& spec : kModalities) {
        names.emplace_back(spec.name);
    }
    return names;
}

std::string uuid4() {
    static thread_local std::mt19937_64 rng{std::random_device{}()};
    std::uniform_int_distribution<uint64_t> dist;
    uint64_t hi = dist(rng);
    uint64_t lo = dist(rng);
    hi = (hi & 0xFFFFFFFFFFFF0FFFull) | 0x0000000000004000ull;  // version 4
    lo = (lo & 0x3FFFFFFFFFFFFFFFull) | 0x8000000000000000ull;  // RFC-4122 variant
    char buffer[37] = {};
    std::snprintf(buffer, sizeof(buffer), "%08" PRIx64 "-%04" PRIx64 "-%04" PRIx64 "-%04" PRIx64
                                          "-%012" PRIx64,
                  hi >> 32, (hi >> 16) & 0xFFFFull, hi & 0xFFFFull, lo >> 48,
                  lo & 0xFFFFFFFFFFFFull);
    return buffer;
}

// Minimal field extraction from the backend's SDKTelemetryBatchResponse JSON
// ({"success":true,"events_received":N,"events_stored":N,"events_skipped":N,
// "storage_version":"V2"}). The CLI deliberately carries no JSON parser.
int extract_int_field(const std::string& json, const std::string& key) {
    const std::string needle = "\"" + key + "\":";
    const size_t pos = json.find(needle);
    if (pos == std::string::npos) {
        return -1;
    }
    return std::atoi(json.c_str() + pos + needle.size());
}

bool extract_bool_field(const std::string& json, const std::string& key) {
    const std::string needle = "\"" + key + "\":";
    const size_t pos = json.find(needle);
    return pos != std::string::npos && json.compare(pos + needle.size(), 4, "true") == 0;
}

// Per-endpoint accounting accumulated inside the telemetry HTTP callback.
struct EndpointStats {
    int posts = 0;
    int failures = 0;
    int last_status = 0;
    int received = 0;
    int stored = 0;
    int skipped = 0;
    std::string last_error;
};

struct TelemetryHttpContext {
    std::map<std::string, EndpointStats> endpoints;  // key: endpoint path
};

void telemetry_http_callback(void* user_data, const char* endpoint, const char* json_body,
                             size_t json_length, rac_bool_t requires_auth) {
    auto* context = static_cast<TelemetryHttpContext*>(user_data);
    if (context == nullptr || endpoint == nullptr) {
        return;
    }
    const net::HttpResult result = net::control_plane_post(
        endpoint, std::string(json_body != nullptr ? json_body : "", json_length),
        requires_auth == RAC_TRUE);

    EndpointStats& stats = context->endpoints[endpoint];
    stats.posts += 1;
    stats.last_status = result.status;
    if (!result.ok()) {
        stats.failures += 1;
        stats.last_error = result.describe();
        return;
    }
    if (!extract_bool_field(result.body, "success")) {
        stats.failures += 1;
        stats.last_error = "backend reported success=false: " + result.body;
    }
    const int received = extract_int_field(result.body, "events_received");
    const int stored = extract_int_field(result.body, "events_stored");
    const int skipped = extract_int_field(result.body, "events_skipped");
    stats.received += received > 0 ? received : 0;
    stats.stored += stored > 0 ? stored : 0;
    stats.skipped += skipped > 0 ? skipped : 0;
}

/** Optional metric flags shared by emit and blast. Negative = unset. */
struct MetricOptions {
    double processing_ms = -1.0;
    int32_t input_tokens = -1;
    int32_t output_tokens = -1;
    double audio_duration_ms = -1.0;
};

void track_events(rac_telemetry_manager_t* manager, const ModalitySpec& spec,
                  const std::string& event_type, const std::string& session_id, int count,
                  const MetricOptions& metrics) {
    for (int i = 0; i < count; ++i) {
        const std::string event_id = uuid4();
        rac_telemetry_payload_t payload = rac_telemetry_payload_default();
        payload.id = event_id.c_str();
        payload.event_type = event_type.c_str();
        payload.modality = spec.name;
        payload.session_id = session_id.c_str();
        const int64_t now_ms = rac_get_current_time_ms();
        payload.timestamp_ms = now_ms;
        payload.created_at_ms = now_ms;
        payload.success = RAC_TRUE;
        payload.has_success = RAC_TRUE;
        if (metrics.processing_ms >= 0) {
            payload.processing_time_ms = metrics.processing_ms;
            payload.has_processing_time_ms = RAC_TRUE;
        }
        if (metrics.input_tokens >= 0) {
            payload.input_tokens = metrics.input_tokens;
        }
        if (metrics.output_tokens >= 0) {
            payload.output_tokens = metrics.output_tokens;
            payload.total_tokens = (metrics.input_tokens > 0 ? metrics.input_tokens : 0) +
                                   metrics.output_tokens;
        }
        if (metrics.audio_duration_ms >= 0) {
            payload.audio_duration_ms = metrics.audio_duration_ms;
        }
        rac_telemetry_manager_track(manager, &payload);
    }
}

struct FlushReport {
    TelemetryHttpContext context;
    int tracked = 0;
};

/**
 * Login (JWT), create a manager wired to the real transport, run `track_fn`,
 * flush, and account per-endpoint results. Returns false on login failure.
 */
template <typename TrackFn>
bool run_telemetry_session(const GlobalOptions& options, FlushReport* report, TrackFn&& track_fn) {
    Bootstrapped env;
    if (bootstrap(options, &env) != RAC_SUCCESS) {
        return false;
    }

    // The V2 telemetry endpoints only accept a JWT, so emit implies login —
    // one process performs the handshake and the flush (in-process token).
    std::string error;
    if (net::login(nullptr, &error) != RAC_SUCCESS) {
        out::error_line(error);
        return false;
    }

    const char* device_id = rac_state_get_device_id();
    rac_telemetry_manager_t* manager = rac_telemetry_manager_create(
        rac_state_get_environment(), device_id != nullptr ? device_id : "", net::platform_name(),
        RCLI_VERSION);
    if (manager == nullptr) {
        out::error_line("telemetry manager creation failed");
        return false;
    }
    rac_telemetry_manager_set_device_info(manager, net::device_model().c_str(),
                                          net::os_version_string().c_str());
    rac_telemetry_manager_set_http_callback(manager, telemetry_http_callback, &report->context);

    report->tracked = track_fn(manager);
    rac_telemetry_manager_flush(manager);
    rac_telemetry_manager_set_http_callback(manager, nullptr, nullptr);
    rac_telemetry_manager_destroy(manager);
    return true;
}

int total_received(const FlushReport& report) {
    int received = 0;
    for (const auto& [endpoint, stats] : report.context.endpoints) {
        received += stats.received;
    }
    return received;
}

bool report_failed(const FlushReport& report) {
    if (report.context.endpoints.empty()) {
        return true;  // nothing was POSTed — flush deferred or dropped
    }
    for (const auto& [endpoint, stats] : report.context.endpoints) {
        if (stats.failures > 0) {
            return true;
        }
    }
    return total_received(report) != report.tracked;
}

void render_endpoint_results(const GlobalOptions& options, const FlushReport& report) {
    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("tracked", static_cast<int64_t>(report.tracked))
            .field("success", !report_failed(report))
            .begin_array("endpoints");
        for (const auto& [endpoint, stats] : report.context.endpoints) {
            json.begin_array_object()
                .field("endpoint", endpoint)
                .field("posts", static_cast<int64_t>(stats.posts))
                .field("http_status", static_cast<int64_t>(stats.last_status))
                .field("events_received", static_cast<int64_t>(stats.received))
                .field("events_stored", static_cast<int64_t>(stats.stored))
                .field("events_skipped", static_cast<int64_t>(stats.skipped));
            if (!stats.last_error.empty()) {
                json.field("error", stats.last_error);
            }
            json.end_object();
        }
        json.end_array().end_object();
        out::result_line(json.str());
        return;
    }

    if (report.context.endpoints.empty()) {
        out::error_line("no telemetry batch was sent (flush deferred?)");
        return;
    }
    for (const auto& [endpoint, stats] : report.context.endpoints) {
        std::string line = endpoint + "  HTTP " + std::to_string(stats.last_status) +
                           "  received=" + std::to_string(stats.received) +
                           " stored=" + std::to_string(stats.stored) +
                           " skipped=" + std::to_string(stats.skipped);
        if (!stats.last_error.empty()) {
            line += "  error: " + stats.last_error;
        }
        out::result_line(line);
    }
}

int run_telemetry_emit(const GlobalOptions& options, const std::string& modality,
                       const std::string& event_type, int count, const std::string& session_id,
                       const MetricOptions& metrics) {
    const ModalitySpec* spec = find_modality(modality);
    if (spec == nullptr) {
        out::error_line("unknown modality '" + modality + "'");
        return 2;
    }
    const std::string resolved_event_type =
        event_type.empty() ? spec->default_event_type : event_type;
    const std::string resolved_session = session_id.empty() ? uuid4() : session_id;

    FlushReport report;
    const bool session_ok = run_telemetry_session(
        options, &report, [&](rac_telemetry_manager_t* manager) {
            track_events(manager, *spec, resolved_event_type, resolved_session, count, metrics);
            return count;
        });
    if (!session_ok) {
        return 1;
    }

    if (!options.json) {
        out::status_line("emitted " + std::to_string(count) + " × " + resolved_event_type +
                         " (modality " + modality + ", session " + resolved_session + ")");
    }
    render_endpoint_results(options, report);
    return report_failed(report) ? 1 : 0;
}

int run_telemetry_blast(const GlobalOptions& options, int count, const std::string& session_id,
                        const MetricOptions& metrics) {
    const std::string resolved_session = session_id.empty() ? uuid4() : session_id;

    FlushReport report;
    const bool session_ok = run_telemetry_session(
        options, &report, [&](rac_telemetry_manager_t* manager) {
            for (const ModalitySpec& spec : kModalities) {
                track_events(manager, spec, spec.default_event_type, resolved_session, count,
                             metrics);
            }
            return count * static_cast<int>(std::size(kModalities));
        });
    if (!session_ok) {
        return 1;
    }

    bool all_ok = true;
    std::vector<std::vector<std::string>> rows;
    for (const ModalitySpec& spec : kModalities) {
        const std::string endpoint = std::string("/api/v2/sdk/telemetry/") + spec.name;
        const auto it = report.context.endpoints.find(endpoint);
        std::string status = "NO POST";
        int received = 0;
        int stored = 0;
        int skipped = 0;
        bool row_ok = false;
        if (it != report.context.endpoints.end()) {
            const EndpointStats& stats = it->second;
            received = stats.received;
            stored = stats.stored;
            skipped = stats.skipped;
            row_ok = stats.failures == 0 && stats.received == count;
            status = row_ok ? ("HTTP " + std::to_string(stats.last_status))
                            : (stats.last_error.empty()
                                   ? "HTTP " + std::to_string(stats.last_status)
                                   : stats.last_error);
        }
        all_ok = all_ok && row_ok;
        rows.push_back({spec.name, row_ok ? "ok" : "FAILED", status, std::to_string(received),
                        std::to_string(stored), std::to_string(skipped)});
    }

    if (options.json) {
        out::JsonWriter json;
        json.begin_object()
            .field("tracked", static_cast<int64_t>(report.tracked))
            .field("success", all_ok)
            .field("session_id", resolved_session)
            .begin_array("modalities");
        for (const auto& row : rows) {
            json.begin_array_object()
                .field("modality", row[0])
                .field("ok", row[1] == "ok")
                .field("status", row[2])
                .field("events_received", static_cast<int64_t>(std::atoi(row[3].c_str())))
                .field("events_stored", static_cast<int64_t>(std::atoi(row[4].c_str())))
                .field("events_skipped", static_cast<int64_t>(std::atoi(row[5].c_str())))
                .end_object();
        }
        json.end_array().end_object();
        out::result_line(json.str());
    } else {
        out::status_line("blast session " + resolved_session + " — " +
                         std::to_string(report.tracked) + " event(s) across " +
                         std::to_string(std::size(kModalities)) + " modalities");
        out::table({"MODALITY", "RESULT", "STATUS", "RECEIVED", "STORED", "SKIPPED"}, rows);
    }
    return all_ok ? 0 : 1;
}

}  // namespace

void register_telemetry(CLI::App& app, GlobalOptions& options) {
    CLI::App* cmd = app.add_subcommand(
        "telemetry", "Emit model-free telemetry through the real control-plane pipeline");
    cmd->require_subcommand(1);

    // ---- telemetry emit ----------------------------------------------------
    CLI::App* emit_cmd = cmd->add_subcommand(
        "emit",
        "Track N events of one modality, flush to /api/v2/sdk/telemetry/{modality} "
        "and report the backend's accounting. Runs the auth handshake first "
        "(staging/prod only). Exits non-zero when any POST fails.");
    auto modality = std::make_shared<std::string>();
    auto event_type = std::make_shared<std::string>();
    auto count = std::make_shared<int>(1);
    auto session_id = std::make_shared<std::string>();
    auto metrics = std::make_shared<MetricOptions>();
    emit_cmd->add_option("--modality", *modality, "Telemetry modality")
        ->required()
        ->check(CLI::IsMember(modality_names()));
    emit_cmd->add_option("--event-type", *event_type,
                         "Event type string (default: the modality's terminal event, e.g. "
                         "llm.generation.completed)");
    emit_cmd->add_option("--count", *count, "Number of events to emit (default 1)")
        ->check(CLI::PositiveNumber);
    emit_cmd->add_option("--session-id", *session_id,
                         "Session id attached to every event (default: fresh UUID)");
    emit_cmd->add_option("--processing-ms", metrics->processing_ms,
                         "processing_time_ms metric for every event");
    emit_cmd->add_option("--input-tokens", metrics->input_tokens,
                         "input_tokens metric (llm/vlm modalities)");
    emit_cmd->add_option("--output-tokens", metrics->output_tokens,
                         "output_tokens metric (llm/vlm modalities)");
    emit_cmd->add_option("--audio-duration-ms", metrics->audio_duration_ms,
                         "audio_duration_ms metric (stt modality)");
    emit_cmd->callback([&options, modality, event_type, count, session_id, metrics]() {
        const int exit_code = run_telemetry_emit(options, *modality, *event_type, *count,
                                                 *session_id, *metrics);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });

    // ---- telemetry blast ---------------------------------------------------
    CLI::App* blast_cmd = cmd->add_subcommand(
        "blast",
        "Emit --count events of EVERY modality (all 12) in one run, flush, and "
        "print a per-modality result table parsed from the backend's batch "
        "responses. The integration-suite workhorse.");
    auto blast_count = std::make_shared<int>(1);
    auto blast_session = std::make_shared<std::string>();
    auto blast_metrics = std::make_shared<MetricOptions>();
    blast_cmd->add_option("--count", *blast_count, "Events per modality (default 1)")
        ->check(CLI::PositiveNumber);
    blast_cmd->add_option("--session-id", *blast_session,
                          "Session id attached to every event (default: fresh UUID)");
    blast_cmd->add_option("--processing-ms", blast_metrics->processing_ms,
                          "processing_time_ms metric for every event");
    blast_cmd->callback([&options, blast_count, blast_session, blast_metrics]() {
        const int exit_code =
            run_telemetry_blast(options, *blast_count, *blast_session, *blast_metrics);
        if (exit_code != 0) {
            throw CLI::RuntimeError(exit_code);
        }
    });
}

}  // namespace rcli::commands
