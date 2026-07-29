// m0_harness.cpp — RunAnywhere-Electron M0 gate.
//
// Proves the rac_* C ABI + the llama.cpp engine actually RUN on Windows (not just
// link): installs the Win32 platform adapter, rac_init(), registers the llamacpp
// backend, loads a local GGUF via the low-level LLM component API, and streams a
// completion to stdout. This is the addon core minus N-API — the same bootstrap
// the utility-process host will run.
//
// Usage: electron_m0_harness <model.gguf> [prompt]

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>

#include "win32_platform_adapter.h"

#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace fs = std::filesystem;

static rac_bool_t on_token(const char* token, void*) {
    if (token) {
        fputs(token, stdout);
        fflush(stdout);
    }
    return RAC_TRUE;  // keep going
}

static void on_complete(const rac_llm_result_t*, void*) { fputs("\n\n[complete]\n", stdout); }

static void on_error(rac_result_t code, const char* msg, void*) {
    fprintf(stderr, "\n[error %d] %s\n", static_cast<int>(code), msg ? msg : "");
}

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <model.gguf> [prompt]\n", argv[0]);
        return 2;
    }
    const char* model_path = argv[1];
    const char* prompt =
        (argc >= 3) ? argv[2] : "What is the capital of France? Answer in one word.";

    // Base dir under %LOCALAPPDATA% (survives app updates in the real app; here it
    // just holds the M0 secure store + model-paths root).
    const char* local = std::getenv("LOCALAPPDATA");
    std::string base = (local ? std::string(local) : std::string(".")) + "\\RunAnywhereM0";
    std::string secure = base + "\\secure";
    std::error_code ec;
    fs::create_directories(secure, ec);

    rac_platform_adapter_t adapter;
    rac_electron_fill_win32_adapter(&adapter, secure.c_str());

    rac_config_t cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.platform_adapter = &adapter;
    cfg.log_level = RAC_LOG_INFO;
    cfg.log_tag = "electron-m0";

    rac_model_paths_set_base_dir(base.c_str());

    rac_result_t rc = rac_init(&cfg);
    if (rc != RAC_SUCCESS) {
        fprintf(stderr, "[m0] rac_init failed: %d\n", static_cast<int>(rc));
        return 1;
    }
    fprintf(stderr, "[m0] rac_init OK (commons %s)\n", rac_sdk_get_version());

    rc = rac_backend_llamacpp_register();
    if (rc != RAC_SUCCESS) {
        fprintf(stderr, "[m0] rac_backend_llamacpp_register failed: %d\n", static_cast<int>(rc));
        rac_shutdown();
        return 1;
    }
    fprintf(stderr, "[m0] llamacpp backend registered\n");

    rac_handle_t h = nullptr;
    rc = rac_llm_component_create(&h);
    if (rc != RAC_SUCCESS) {
        fprintf(stderr, "[m0] llm_component_create failed: %d\n", static_cast<int>(rc));
        rac_shutdown();
        return 1;
    }

    fprintf(stderr, "[m0] loading model: %s\n", model_path);
    rc = rac_llm_component_load_model(h, model_path, "m0-model", "M0 Model");
    if (rc != RAC_SUCCESS) {
        fprintf(stderr, "[m0] load_model failed: %d\n", static_cast<int>(rc));
        rac_llm_component_destroy(h);
        rac_shutdown();
        return 1;
    }
    fprintf(stderr, "[m0] model loaded; generating...\n\nPROMPT: %s\nOUTPUT: ", prompt);

    rc = rac_llm_component_generate_stream(h, prompt, nullptr, on_token, on_complete, on_error,
                                           nullptr);
    if (rc != RAC_SUCCESS) {
        fprintf(stderr, "[m0] generate_stream failed: %d\n", static_cast<int>(rc));
    }

    rac_llm_component_destroy(h);
    rac_shutdown();
    fprintf(stderr, "[m0] done.\n");
    return (rc == RAC_SUCCESS) ? 0 : 1;
}
