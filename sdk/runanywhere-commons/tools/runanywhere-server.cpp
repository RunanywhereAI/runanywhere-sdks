/**
 * @file runanywhere-server.cpp
 * @brief RunAnywhere Server - OpenAI-compatible HTTP server for local LLM inference
 *
 * Usage:
 *   runanywhere-server --model /path/to/model.gguf [options]
 *
 * Options:
 *   --model, -m <path>     Path to GGUF model file (required)
 *   --host, -H <host>      Host to bind to (default: 127.0.0.1)
 *   --port, -p <port>      Port to listen on (default: 8080)
 *   --threads, -t <n>      Number of threads (default: 4)
 *   --context, -c <n>      Context window size (default: 8192)
 *   --gpu-layers, -ngl <n> GPU layers to offload (default: 0)
 *   --cors                 Enable CORS (default: enabled)
 *   --no-cors              Disable CORS
 *   --verbose, -v          Enable verbose logging
 *   --help, -h             Show this help message
 *
 * Environment Variables:
 *   RAC_MODEL_PATH         Model path (alternative to --model)
 *   RAC_SERVER_HOST        Server host
 *   RAC_SERVER_PORT        Server port
 *   RAC_SERVER_THREADS     Number of threads
 *   RAC_SERVER_CONTEXT     Context window size
 *
 * Example:
 *   runanywhere-server -m ~/.local/share/runanywhere/Models/llama-3.2-3b.gguf -p 8080
 *
 * @see https://platform.openai.com/docs/api-reference/chat
 */

#include "rac/server/rac_server.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"

// Backend registration
#ifdef RAC_HAS_LLAMACPP
#include "rac/backends/rac_llm_llamacpp.h"
#endif

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <csignal>
#include <string>

// =============================================================================
// SIGNAL HANDLING
// =============================================================================

static volatile sig_atomic_t g_shouldStop = 0;

static void signalHandler(int signum) {
    (void)signum;
    printf("\nReceived signal, shutting down...\n");
    g_shouldStop = 1;
    rac_server_stop();
}

// =============================================================================
// ARGUMENT PARSING
// =============================================================================

struct ServerOptions {
    std::string modelPath;
    std::string host = "127.0.0.1";
    uint16_t port = 8080;
    int32_t threads = 4;
    int32_t contextSize = 8192;
    int32_t gpuLayers = 0;
    bool enableCors = true;
    bool verbose = false;
    bool showHelp = false;
};

static void printUsage(const char* programName) {
    printf("RunAnywhere Server - OpenAI-compatible HTTP server for local LLM inference\n\n");
    printf("Usage: %s --model <path> [options]\n\n", programName);
    printf("Required:\n");
    printf("  --model, -m <path>     Path to GGUF model file\n\n");
    printf("Options:\n");
    printf("  --host, -H <host>      Host to bind to (default: 127.0.0.1)\n");
    printf("  --port, -p <port>      Port to listen on (default: 8080)\n");
    printf("  --threads, -t <n>      Number of threads (default: 4)\n");
    printf("  --context, -c <n>      Context window size (default: 8192)\n");
    printf("  --gpu-layers, -ngl <n> GPU layers to offload (default: 0)\n");
    printf("  --cors                 Enable CORS (default)\n");
    printf("  --no-cors              Disable CORS\n");
    printf("  --verbose, -v          Enable verbose logging\n");
    printf("  --help, -h             Show this help message\n\n");
    printf("Environment Variables:\n");
    printf("  RAC_MODEL_PATH         Model path (alternative to --model)\n");
    printf("  RAC_SERVER_HOST        Server host\n");
    printf("  RAC_SERVER_PORT        Server port\n");
    printf("  RAC_SERVER_THREADS     Number of threads\n");
    printf("  RAC_SERVER_CONTEXT     Context window size\n\n");
    printf("Example:\n");
    printf("  %s -m ~/models/llama-3.2-3b-q4.gguf -p 8080\n\n", programName);
    printf("Endpoints:\n");
    printf("  GET  /v1/models           List available models\n");
    printf("  POST /v1/chat/completions Chat completion (streaming & non-streaming)\n");
    printf("  GET  /health              Health check\n");
}

static ServerOptions parseArgs(int argc, char* argv[]) {
    ServerOptions opts;

    // Check environment variables first
    const char* envModel = std::getenv("RAC_MODEL_PATH");
    if (envModel) opts.modelPath = envModel;

    const char* envHost = std::getenv("RAC_SERVER_HOST");
    if (envHost) opts.host = envHost;

    const char* envPort = std::getenv("RAC_SERVER_PORT");
    if (envPort) opts.port = static_cast<uint16_t>(std::atoi(envPort));

    const char* envThreads = std::getenv("RAC_SERVER_THREADS");
    if (envThreads) opts.threads = std::atoi(envThreads);

    const char* envContext = std::getenv("RAC_SERVER_CONTEXT");
    if (envContext) opts.contextSize = std::atoi(envContext);

    // Parse command line arguments (override env vars)
    for (int i = 1; i < argc; ++i) {
        const char* arg = argv[i];

        if (std::strcmp(arg, "--help") == 0 || std::strcmp(arg, "-h") == 0) {
            opts.showHelp = true;
        }
        else if (std::strcmp(arg, "--verbose") == 0 || std::strcmp(arg, "-v") == 0) {
            opts.verbose = true;
        }
        else if (std::strcmp(arg, "--cors") == 0) {
            opts.enableCors = true;
        }
        else if (std::strcmp(arg, "--no-cors") == 0) {
            opts.enableCors = false;
        }
        else if ((std::strcmp(arg, "--model") == 0 || std::strcmp(arg, "-m") == 0) && i + 1 < argc) {
            opts.modelPath = argv[++i];
        }
        else if ((std::strcmp(arg, "--host") == 0 || std::strcmp(arg, "-H") == 0) && i + 1 < argc) {
            opts.host = argv[++i];
        }
        else if ((std::strcmp(arg, "--port") == 0 || std::strcmp(arg, "-p") == 0) && i + 1 < argc) {
            opts.port = static_cast<uint16_t>(std::atoi(argv[++i]));
        }
        else if ((std::strcmp(arg, "--threads") == 0 || std::strcmp(arg, "-t") == 0) && i + 1 < argc) {
            opts.threads = std::atoi(argv[++i]);
        }
        else if ((std::strcmp(arg, "--context") == 0 || std::strcmp(arg, "-c") == 0) && i + 1 < argc) {
            opts.contextSize = std::atoi(argv[++i]);
        }
        else if ((std::strcmp(arg, "--gpu-layers") == 0 || std::strcmp(arg, "-ngl") == 0) && i + 1 < argc) {
            opts.gpuLayers = std::atoi(argv[++i]);
        }
    }

    return opts;
}

// =============================================================================
// MAIN
// =============================================================================

int main(int argc, char* argv[]) {
    // Parse arguments
    ServerOptions opts = parseArgs(argc, argv);

    if (opts.showHelp) {
        printUsage(argv[0]);
        return 0;
    }

    if (opts.modelPath.empty()) {
        fprintf(stderr, "Error: Model path is required\n\n");
        printUsage(argv[0]);
        return 1;
    }

    // Setup signal handlers
    std::signal(SIGINT, signalHandler);
    std::signal(SIGTERM, signalHandler);
#ifndef _WIN32
    std::signal(SIGHUP, signalHandler);
#endif

    // Print banner
    printf("\n");
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║                    RunAnywhere Server                        ║\n");
    printf("║           OpenAI-Compatible Local LLM Inference              ║\n");
    printf("╚══════════════════════════════════════════════════════════════╝\n");
    printf("\n");

    // Initialize logging
    if (opts.verbose) {
        // TODO: Set log level to debug
    }

    // Register backends
#ifdef RAC_HAS_LLAMACPP
    printf("Registering LlamaCPP backend...\n");
    rac_backend_llamacpp_register();
#else
    fprintf(stderr, "Warning: LlamaCPP backend not available\n");
#endif

    // Configure server
    rac_server_config_t config = RAC_SERVER_CONFIG_DEFAULT;
    config.host = opts.host.c_str();
    config.port = opts.port;
    config.model_path = opts.modelPath.c_str();
    config.context_size = opts.contextSize;
    config.threads = opts.threads;
    config.gpu_layers = opts.gpuLayers;
    config.enable_cors = opts.enableCors ? RAC_TRUE : RAC_FALSE;
    config.verbose = opts.verbose ? RAC_TRUE : RAC_FALSE;

    printf("Configuration:\n");
    printf("  Model:   %s\n", opts.modelPath.c_str());
    printf("  Host:    %s\n", opts.host.c_str());
    printf("  Port:    %d\n", opts.port);
    printf("  Threads: %d\n", opts.threads);
    printf("  Context: %d\n", opts.contextSize);
    printf("  CORS:    %s\n", opts.enableCors ? "enabled" : "disabled");
    printf("\n");

    // Start server
    printf("Starting server...\n");
    rac_result_t result = rac_server_start(&config);

    if (RAC_FAILED(result)) {
        fprintf(stderr, "Error: Failed to start server (code: %d)\n", result);
        switch (result) {
            case RAC_ERROR_SERVER_MODEL_NOT_FOUND:
                fprintf(stderr, "  Model file not found: %s\n", opts.modelPath.c_str());
                break;
            case RAC_ERROR_SERVER_MODEL_LOAD_FAILED:
                fprintf(stderr, "  Failed to load model\n");
                break;
            case RAC_ERROR_SERVER_BIND_FAILED:
                fprintf(stderr, "  Failed to bind to %s:%d\n", opts.host.c_str(), opts.port);
                break;
            default:
                break;
        }
        return 1;
    }

    printf("\n");
    printf("Server is running!\n");
    printf("API endpoint: http://%s:%d/v1/chat/completions\n", opts.host.c_str(), opts.port);
    printf("Press Ctrl+C to stop\n");
    printf("\n");

    // Wait for server to stop
    int exitCode = rac_server_wait();

    // Print final stats
    rac_server_status_t status = {};
    if (RAC_SUCCEEDED(rac_server_get_status(&status))) {
        printf("\nServer Statistics:\n");
        printf("  Total requests:  %lld\n", (long long)status.total_requests);
        printf("  Tokens generated: %lld\n", (long long)status.total_tokens_generated);
        printf("  Uptime: %lld seconds\n", (long long)status.uptime_seconds);
    }

    printf("\nGoodbye!\n");

    return exitCode;
}
