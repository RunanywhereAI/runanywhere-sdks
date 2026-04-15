// =============================================================================
// rac_ort_env.cpp
// -----------------------------------------------------------------------------
// Implementation: one Ort::Env for the whole process, leaked on purpose.
// =============================================================================

#include "rac_ort_env.h"

#ifdef RAC_HAS_ONNX

#include <mutex>
#include <stdexcept>

#include "rac/core/rac_logger.h"

namespace rac::onnx {
namespace {

constexpr const char* LOG_TAG = "ONNX";
constexpr const char* ENV_NAME = "RunAnywhere";

std::once_flag g_init_flag;
const OrtApi* g_api = nullptr;
Ort::Env* g_cxx_env = nullptr;  // leaked — process-lifetime singleton

void init_once() {
    const OrtApiBase* api_base = OrtGetApiBase();
    if (!api_base) {
        RAC_LOG_ERROR(LOG_TAG, "OrtGetApiBase() returned null");
        return;
    }

    g_api = api_base->GetApi(ORT_API_VERSION);
    if (!g_api) {
        RAC_LOG_ERROR(LOG_TAG,
                      "OrtGetApiBase()->GetApi(%d) returned null (runtime=%s)",
                      ORT_API_VERSION,
                      api_base->GetVersionString());
        return;
    }

    try {
        g_cxx_env = new Ort::Env(ORT_LOGGING_LEVEL_WARNING, ENV_NAME);
        RAC_LOG_DEBUG(LOG_TAG, "Initialized shared Ort::Env (runtime=%s)",
                      api_base->GetVersionString());
    } catch (const Ort::Exception& e) {
        RAC_LOG_ERROR(LOG_TAG, "Failed to create shared Ort::Env: %s", e.what());
        g_cxx_env = nullptr;
    }
}

}  // namespace

const OrtApi* shared_ort_api() {
    std::call_once(g_init_flag, init_once);
    return g_api;
}

OrtEnv* shared_ort_env() {
    std::call_once(g_init_flag, init_once);
    return g_cxx_env ? static_cast<OrtEnv*>(*g_cxx_env) : nullptr;
}

Ort::Env& shared_cxx_env() {
    std::call_once(g_init_flag, init_once);
    if (!g_cxx_env) {
        throw std::runtime_error(
            "rac::onnx::shared_cxx_env() failed to initialize Ort::Env");
    }
    return *g_cxx_env;
}

}  // namespace rac::onnx

#endif  // RAC_HAS_ONNX
