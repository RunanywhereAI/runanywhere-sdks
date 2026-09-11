/**
 * @file test_diffusion_model_registry.cpp
 * @brief Verifies diffusion strategy failures cannot escape or be masked by the C registry API.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>
#include <stdexcept>

#include "rac/core/rac_error.h"
#include "rac/features/diffusion/rac_diffusion_model_registry.h"

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(condition, label)                                                                 \
    do {                                                                                        \
        ++test_count;                                                                           \
        if (!(condition)) {                                                                      \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__);           \
        }                                                                                       \
    } while (0)

constexpr const char* kFailingModelId = "failing-model";
constexpr const char* kThrowCanHandleInternal = "throw-can-handle-internal";
constexpr const char* kThrowCanHandleOutOfMemory = "throw-can-handle-out-of-memory";
constexpr const char* kThrowGetInternal = "throw-get-internal";
constexpr const char* kThrowGetOutOfMemory = "throw-get-out-of-memory";
constexpr const char* kThrowSelectInternal = "throw-select-internal";
constexpr const char* kThrowSelectOutOfMemory = "throw-select-out-of-memory";
constexpr const char* kThrowSelectCanHandle = "throw-select-can-handle";

enum class ListBehavior {
    kSuccess,
    kThrowInternal,
    kThrowOutOfMemory,
};

struct ThrowingStrategyState {
    ListBehavior list_behavior = ListBehavior::kSuccess;
    int select_can_handle_calls = 0;
};

rac_bool_t failing_can_handle(const char* model_id, void*) {
    return std::strcmp(model_id, kFailingModelId) == 0 ? RAC_TRUE : RAC_FALSE;
}

rac_result_t failing_get_model_def(const char*, rac_diffusion_model_def_t*, void*) {
    return RAC_ERROR_NOT_INITIALIZED;
}

rac_result_t failing_list_models(rac_diffusion_model_def_t**, size_t*, void*) {
    return RAC_ERROR_NOT_INITIALIZED;
}

rac_bool_t throwing_can_handle(const char* model_id, void* user_data) {
    auto* state = static_cast<ThrowingStrategyState*>(user_data);
    if (std::strcmp(model_id, kThrowCanHandleInternal) == 0) {
        throw std::runtime_error("can_handle failed");
    }
    if (std::strcmp(model_id, kThrowCanHandleOutOfMemory) == 0) {
        throw std::bad_alloc();
    }
    if (std::strcmp(model_id, kThrowSelectCanHandle) == 0 &&
        ++state->select_can_handle_calls == 2) {
        throw std::runtime_error("can_handle failed during backend selection");
    }
    return RAC_TRUE;
}

rac_result_t throwing_get_model_def(const char* model_id, rac_diffusion_model_def_t* out_def,
                                    void*) {
    if (std::strcmp(model_id, kThrowGetInternal) == 0) {
        throw std::runtime_error("get_model_def failed");
    }
    if (std::strcmp(model_id, kThrowGetOutOfMemory) == 0) {
        throw std::bad_alloc();
    }

    *out_def = {};
    out_def->model_id = model_id;
    out_def->backend = RAC_DIFFUSION_BACKEND_ONNX;
    out_def->platforms = RAC_DIFFUSION_PLATFORM_ALL;
    return RAC_SUCCESS;
}

rac_result_t throwing_list_models(rac_diffusion_model_def_t**, size_t*, void* user_data) {
    const auto* state = static_cast<const ThrowingStrategyState*>(user_data);
    if (state->list_behavior == ListBehavior::kThrowOutOfMemory) {
        throw std::bad_alloc();
    }
    if (state->list_behavior == ListBehavior::kThrowInternal) {
        throw std::runtime_error("list_models failed");
    }
    return RAC_ERROR_NOT_FOUND;
}

rac_diffusion_backend_t throwing_select_backend(const rac_diffusion_model_def_t* model, void*) {
    if (std::strcmp(model->model_id, kThrowSelectOutOfMemory) == 0) {
        throw std::bad_alloc();
    }
    if (std::strcmp(model->model_id, kThrowSelectInternal) == 0) {
        throw std::runtime_error("select_backend failed");
    }
    return RAC_DIFFUSION_BACKEND_ONNX;
}

void test_returned_strategy_error() {
    rac_diffusion_model_registry_cleanup();
    const rac_diffusion_model_strategy_t strategy = {
        .name = "Failing",
        .can_handle = failing_can_handle,
        .get_model_def = failing_get_model_def,
        .list_models = failing_list_models,
        .select_backend = nullptr,
        .load_model = nullptr,
        .user_data = nullptr,
    };
    CHECK(rac_diffusion_model_registry_register(&strategy) == RAC_SUCCESS,
          "failing strategy registers");

    rac_diffusion_model_def_t model{};
    CHECK(rac_diffusion_model_registry_get(kFailingModelId, &model) == RAC_ERROR_NOT_INITIALIZED,
          "get preserves a non-NOT_FOUND strategy error");

    auto* models = &model;
    size_t count = 1;
    CHECK(rac_diffusion_model_registry_list(&models, &count) == RAC_ERROR_NOT_INITIALIZED,
          "list preserves a non-NOT_FOUND strategy error");
    CHECK(models == nullptr && count == 0, "failed list leaves empty outputs");
    CHECK(rac_diffusion_model_registry_select_backend(kFailingModelId) ==
              RAC_DIFFUSION_BACKEND_COREML,
          "failed lookup keeps the CoreML backend fallback");
}

void test_throwing_strategy() {
    rac_diffusion_model_registry_cleanup();
    ThrowingStrategyState state;
    const rac_diffusion_model_strategy_t strategy = {
        .name = "Throwing",
        .can_handle = throwing_can_handle,
        .get_model_def = throwing_get_model_def,
        .list_models = throwing_list_models,
        .select_backend = throwing_select_backend,
        .load_model = nullptr,
        .user_data = &state,
    };
    CHECK(rac_diffusion_model_registry_register(&strategy) == RAC_SUCCESS,
          "throwing strategy registers");

    rac_diffusion_model_def_t model{};
    CHECK(rac_diffusion_model_registry_get(kThrowCanHandleOutOfMemory, &model) ==
              RAC_ERROR_OUT_OF_MEMORY,
          "get maps can_handle bad_alloc");
    CHECK(rac_diffusion_model_registry_get(kThrowCanHandleInternal, &model) == RAC_ERROR_INTERNAL,
          "get maps unexpected can_handle exception");
    CHECK(rac_diffusion_model_registry_get(kThrowGetOutOfMemory, &model) ==
              RAC_ERROR_OUT_OF_MEMORY,
          "get maps get_model_def bad_alloc");
    CHECK(rac_diffusion_model_registry_get(kThrowGetInternal, &model) == RAC_ERROR_INTERNAL,
          "get maps unexpected get_model_def exception");

    rac_diffusion_model_def_t* models = nullptr;
    size_t count = 0;
    state.list_behavior = ListBehavior::kThrowOutOfMemory;
    CHECK(rac_diffusion_model_registry_list(&models, &count) == RAC_ERROR_OUT_OF_MEMORY,
          "list maps list_models bad_alloc");
    CHECK(models == nullptr && count == 0, "bad_alloc list leaves empty outputs");
    state.list_behavior = ListBehavior::kThrowInternal;
    CHECK(rac_diffusion_model_registry_list(&models, &count) == RAC_ERROR_INTERNAL,
          "list maps unexpected list_models exception");
    CHECK(models == nullptr && count == 0, "unexpected list failure leaves empty outputs");

    CHECK(rac_diffusion_model_registry_select_backend(kThrowSelectOutOfMemory) ==
              RAC_DIFFUSION_BACKEND_COREML,
          "select_backend maps bad_alloc to the CoreML fallback");
    CHECK(rac_diffusion_model_registry_select_backend(kThrowSelectInternal) ==
              RAC_DIFFUSION_BACKEND_COREML,
          "select_backend maps unexpected exception to the CoreML fallback");
    state.select_can_handle_calls = 0;
    CHECK(rac_diffusion_model_registry_select_backend(kThrowSelectCanHandle) ==
              RAC_DIFFUSION_BACKEND_COREML,
          "select_backend contains a can_handle exception");
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_diffusion_model_registry\n");
    test_returned_strategy_error();
    test_throwing_strategy();
    rac_diffusion_model_registry_cleanup();

    std::fprintf(stdout, "\n%d checks, %d failed\n", test_count, fail_count);
    return fail_count == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
