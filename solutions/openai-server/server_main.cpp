// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// `runanywhere-server` — standalone OpenAI-compatible HTTP binary.
//
// Usage:
//   runanywhere-server --model /path/model.gguf [--port 8080] [--host 0.0.0.0]
//                      [--api-key sk-...] [--model-id my-model]
//
// When --model is omitted (or the file doesn't exist), the server still
// starts and routes a `503 no llm session registered` for generation
// requests while serving `/health`, `/v1/models`, and `/`. This lets
// integration tests exercise the HTTP surface without a real model.

#include "ra_core_init.h"
#include "ra_primitives.h"
#include "ra_server.h"

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <thread>

extern "C" {
ra_status_t ra_solution_openai_server_register_session(const char*, ra_llm_session_t*);
void        ra_solution_openai_server_set_default_model(const char*);
void        ra_solution_openai_server_clear_sessions(void);
}

namespace {

struct Args {
    std::string host = "0.0.0.0";
    int         port = 8080;
    std::string api_key;
    std::string model_path;
    std::string model_id = "runanywhere-local";
};

void usage() {
    std::fprintf(stderr,
        "runanywhere-server — OpenAI-compatible local LLM gateway\n"
        "\n"
        "  --host <addr>      bind host (default 0.0.0.0)\n"
        "  --port <n>         bind port (default 8080)\n"
        "  --model <path>     GGUF model path (optional; without it the\n"
        "                      /v1/chat/completions returns 503)\n"
        "  --model-id <id>    public id to report (default runanywhere-local)\n"
        "  --api-key <token>  require Bearer auth (default none)\n"
        "\n");
}

bool parse(int argc, char** argv, Args& out) {
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto take = [&](std::string& dst) {
            if (i + 1 >= argc) return false;
            dst = argv[++i];
            return true;
        };
        if      (a == "--host")     { if (!take(out.host))      return false; }
        else if (a == "--port")     { if (i + 1 >= argc) return false;
                                       out.port = std::atoi(argv[++i]); }
        else if (a == "--model")    { if (!take(out.model_path)) return false; }
        else if (a == "--model-id") { if (!take(out.model_id))  return false; }
        else if (a == "--api-key")  { if (!take(out.api_key))   return false; }
        else if (a == "--help" || a == "-h") { usage(); std::exit(0); }
        else { std::fprintf(stderr, "unknown arg: %s\n", a.c_str()); return false; }
    }
    return true;
}

std::atomic<bool> g_quit{false};
extern "C" void on_signal(int) { g_quit.store(true); }

}  // namespace

int main(int argc, char** argv) {
    Args args;
    if (!parse(argc, argv, args)) { usage(); return 2; }

    ra_init_config_t opts{};
    opts.log_level = RA_LOG_LEVEL_INFO;
    ra_status_t rc = ra_init(&opts);
    if (rc != RA_OK) {
        std::fprintf(stderr, "ra_init failed: %d\n", rc);
        return 1;
    }

    // Optional: pre-load an LLM session when --model is supplied.
    ra_llm_session_t* session = nullptr;
    if (!args.model_path.empty()) {
        std::error_code ec;
        if (!std::filesystem::exists(args.model_path, ec) || ec) {
            std::fprintf(stderr, "model file not found: %s\n",
                         args.model_path.c_str());
            return 1;
        }
        ra_model_spec_t spec{};
        spec.model_id          = args.model_id.c_str();
        spec.model_path        = args.model_path.c_str();
        spec.format            = RA_FORMAT_GGUF;
        spec.preferred_runtime = RA_RUNTIME_SELF_CONTAINED;

        ra_session_config_t cfg{};
        cfg.context_size  = 2048;
        cfg.n_threads     = 0;
        cfg.n_gpu_layers  = -1;
        cfg.use_mmap      = 1;
        cfg.use_mlock     = 0;

        rc = ra_llm_create(&spec, &cfg, &session);
        if (rc != RA_OK) {
            std::fprintf(stderr, "ra_llm_create failed: %d\n", rc);
            return 1;
        }
        ra_solution_openai_server_register_session(args.model_id.c_str(), session);
        ra_solution_openai_server_set_default_model(args.model_id.c_str());
        std::fprintf(stdout, "loaded %s (%s)\n", args.model_id.c_str(),
                     args.model_path.c_str());
    } else {
        std::fprintf(stdout,
                     "no --model supplied — HTTP surface only (503 on gen)\n");
    }

    std::signal(SIGINT,  &on_signal);
    std::signal(SIGTERM, &on_signal);

    ra_server_config_t srv_cfg{};
    srv_cfg.host            = args.host.c_str();
    srv_cfg.port            = args.port;
    srv_cfg.max_connections = 0;
    srv_cfg.enable_cors     = 1;
    srv_cfg.api_key         = args.api_key.empty() ? nullptr : args.api_key.c_str();

    rc = ra_server_start(&srv_cfg);
    if (rc != RA_OK) {
        std::fprintf(stderr, "ra_server_start failed: %d\n", rc);
        if (session) ra_llm_destroy(session);
        return 1;
    }

    ra_server_status_t st{};
    ra_server_get_status(&st);
    std::fprintf(stdout, "runanywhere-server listening on %s:%d\n",
                 args.host.c_str(), st.port);
    std::fflush(stdout);

    while (!g_quit.load()) std::this_thread::sleep_for(std::chrono::milliseconds(200));

    std::fprintf(stdout, "shutting down…\n");
    ra_server_stop();
    ra_solution_openai_server_clear_sessions();
    if (session) ra_llm_destroy(session);
    ra_shutdown();
    return 0;
}
