/**
 * @file test_provider_registry.cpp
 * @brief Unit tests for the shared ProviderRegistry<T> template.
 *
 * Mirrors test_runtime_registry.cpp style: pure C++ with no backend deps,
 * links only rac_commons, runs on every preset.
 *
 * Scenarios:
 *   1. register_provider + find_by_desc round-trip; non-null result, correct count.
 *   2. NULL provider / NULL name / NULL fn pointers → RAC_ERROR_INVALID_PARAMETER.
 *   3. Out-of-range primitive → RAC_ERROR_NOT_SUPPORTED.
 *   4. Duplicate name → replace (verify old snapshot gone, new one found).
 *   5. find_by_desc returns a by-value snapshot (registry can be mutated after).
 *   6. unregister_provider removes entry; find_by_desc then fails.
 *   7. Concurrent register + find_by_desc from 8 threads × 1000 iters (mutex).
 *   8. rac_runtime_primitive_in_range boundary checks.
 *   9. ONNX provider type exercises the same template path.
 */

#include <atomic>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <thread>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_cpu_runtime_provider.h"
#include "rac/plugin/rac_onnxrt_runtime_provider.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_vtable.h"
#include "rac/runtime/rac_runtime_provider_registry.h"

namespace {

int g_test_count = 0;
int g_fail_count = 0;

#define CHECK(cond, label)                                                                        \
    do {                                                                                          \
        ++g_test_count;                                                                           \
        if (cond) {                                                                               \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        } else {                                                                                  \
            ++g_fail_count;                                                                       \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) — %s\n", label, __FILE__, __LINE__, #cond); \
        }                                                                                         \
    } while (0)

/* Minimal no-op session callbacks. */
rac_result_t noop_create(const rac_runtime_session_desc_t*, rac_runtime_session_t**) {
    return RAC_SUCCESS;
}
rac_result_t noop_run(rac_runtime_session_t*, const rac_runtime_io_t*, size_t,
                      rac_runtime_io_t*, size_t) {
    return RAC_SUCCESS;
}
void noop_destroy(rac_runtime_session_t*) {}

/* Build a minimal valid CPU provider. */
rac_cpu_runtime_provider_t make_cpu(const char* name, rac_primitive_t primitive) {
    rac_cpu_runtime_provider_t p{};
    p.name = name;
    p.primitive = primitive;
    p.formats = nullptr;
    p.formats_count = 0;
    p.create_session = noop_create;
    p.run_session = noop_run;
    p.destroy_session = noop_destroy;
    return p;
}

/* Build a minimal valid ONNX provider. */
rac_onnxrt_runtime_provider_t make_onnx(const char* name, rac_primitive_t primitive) {
    rac_onnxrt_runtime_provider_t p{};
    p.name = name;
    p.primitive = primitive;
    p.formats = nullptr;
    p.formats_count = 0;
    p.create_session = noop_create;
    p.run_session = noop_run;
    p.destroy_session = noop_destroy;
    return p;
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_provider_registry\n");

    /* --- (1) register + find_by_desc round-trip; count via for_each -------- */
    {
        rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t> reg;
        auto p = make_cpu("llamacpp", RAC_PRIMITIVE_GENERATE_TEXT);

        CHECK(reg.register_provider(&p) == RAC_SUCCESS, "(1) register returns RAC_SUCCESS");

        rac_runtime_session_desc_t desc{};
        desc.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        desc.model_format = 0;
        rac_cpu_runtime_provider_t out{};
        CHECK(reg.find_by_desc(&desc, &out), "(1) find_by_desc succeeds");
        CHECK(std::strcmp(out.name, "llamacpp") == 0, "(1) found provider has correct name");

        int count = 0;
        reg.for_each([&](const rac_cpu_runtime_provider_t&) { ++count; });
        CHECK(count == 1, "(1) for_each yields one entry");
    }

    /* --- (2) NULL / missing fn pointer rejections -------------------------- */
    {
        rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t> reg;

        CHECK(reg.register_provider(nullptr) == RAC_ERROR_INVALID_PARAMETER,
              "(2) NULL provider → RAC_ERROR_INVALID_PARAMETER");

        auto no_name = make_cpu(nullptr, RAC_PRIMITIVE_GENERATE_TEXT);
        CHECK(reg.register_provider(&no_name) == RAC_ERROR_INVALID_PARAMETER,
              "(2) NULL name → RAC_ERROR_INVALID_PARAMETER");

        auto no_create = make_cpu("x", RAC_PRIMITIVE_GENERATE_TEXT);
        no_create.create_session = nullptr;
        CHECK(reg.register_provider(&no_create) == RAC_ERROR_INVALID_PARAMETER,
              "(2) NULL create_session → RAC_ERROR_INVALID_PARAMETER");

        auto no_run = make_cpu("x", RAC_PRIMITIVE_GENERATE_TEXT);
        no_run.run_session = nullptr;
        CHECK(reg.register_provider(&no_run) == RAC_ERROR_INVALID_PARAMETER,
              "(2) NULL run_session → RAC_ERROR_INVALID_PARAMETER");

        auto no_destroy = make_cpu("x", RAC_PRIMITIVE_GENERATE_TEXT);
        no_destroy.destroy_session = nullptr;
        CHECK(reg.register_provider(&no_destroy) == RAC_ERROR_INVALID_PARAMETER,
              "(2) NULL destroy_session → RAC_ERROR_INVALID_PARAMETER");
    }

    /* --- (3) out-of-range primitive ---------------------------------------- */
    {
        rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t> reg;

        auto unspec = make_cpu("bad", RAC_PRIMITIVE_UNSPECIFIED);
        CHECK(reg.register_provider(&unspec) == RAC_ERROR_NOT_SUPPORTED,
              "(3) RAC_PRIMITIVE_UNSPECIFIED → RAC_ERROR_NOT_SUPPORTED");

        auto oob = make_cpu("bad2", RAC_PRIMITIVE_COUNT);
        CHECK(reg.register_provider(&oob) == RAC_ERROR_NOT_SUPPORTED,
              "(3) RAC_PRIMITIVE_COUNT → RAC_ERROR_NOT_SUPPORTED");
    }

    /* --- (4) duplicate name → replace -------------------------------------- */
    {
        rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t> reg;

        auto first = make_cpu("myengine", RAC_PRIMITIVE_GENERATE_TEXT);
        auto second = make_cpu("myengine", RAC_PRIMITIVE_TRANSCRIBE);

        reg.register_provider(&first);
        CHECK(reg.register_provider(&second) == RAC_SUCCESS,
              "(4) re-register same name returns RAC_SUCCESS (replace)");

        rac_runtime_session_desc_t desc{};
        desc.primitive = RAC_PRIMITIVE_TRANSCRIBE;
        desc.model_format = 0;
        rac_cpu_runtime_provider_t out{};
        CHECK(reg.find_by_desc(&desc, &out), "(4) replacement is findable by new primitive");

        desc.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        rac_cpu_runtime_provider_t old_out{};
        CHECK(!reg.find_by_desc(&desc, &old_out), "(4) old primitive slot is gone after replace");

        int count = 0;
        reg.for_each([&](const rac_cpu_runtime_provider_t&) { ++count; });
        CHECK(count == 1, "(4) registry still holds exactly one entry after replace");
    }

    /* --- (5) find_by_desc returns by-value snapshot ----------------------- */
    {
        rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t> reg;
        auto p = make_cpu("snap_engine", RAC_PRIMITIVE_EMBED);
        reg.register_provider(&p);

        rac_runtime_session_desc_t desc{};
        desc.primitive = RAC_PRIMITIVE_EMBED;
        rac_cpu_runtime_provider_t snapshot{};
        reg.find_by_desc(&desc, &snapshot);

        /* Mutate registry after find; snapshot must be independent. */
        reg.unregister_provider("snap_engine");

        CHECK(snapshot.create_session == noop_create,
              "(5) snapshot fn pointers survive after unregister");
        CHECK(std::strcmp(snapshot.name, "snap_engine") == 0,
              "(5) snapshot name survives after unregister");
    }

    /* --- (6) unregister_provider removes entry ----------------------------- */
    {
        rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t> reg;
        auto p = make_cpu("remove_me", RAC_PRIMITIVE_SYNTHESIZE);
        reg.register_provider(&p);

        reg.unregister_provider("remove_me");

        rac_runtime_session_desc_t desc{};
        desc.primitive = RAC_PRIMITIVE_SYNTHESIZE;
        rac_cpu_runtime_provider_t out{};
        CHECK(!reg.find_by_desc(&desc, &out), "(6) find_by_desc fails after unregister");

        /* NULL name is a no-op — must not crash. */
        reg.unregister_provider(nullptr);
        CHECK(true, "(6) unregister_provider(nullptr) does not crash");
    }

    /* --- (7) concurrent register + find_by_desc (mutex) ------------------- */
    {
        rac::runtime::ProviderRegistry<rac_cpu_runtime_provider_t> reg;
        std::atomic<int> errors{0};

        /* 4 writer threads and 4 reader threads run concurrently. */
        auto writer = [&]() {
            for (int i = 0; i < 1000; ++i) {
                auto p = make_cpu("concurrent_prov", RAC_PRIMITIVE_GENERATE_TEXT);
                rac_result_t r = reg.register_provider(&p);
                if (r != RAC_SUCCESS)
                    ++errors;
            }
        };
        auto reader = [&]() {
            rac_runtime_session_desc_t desc{};
            desc.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
            for (int i = 0; i < 1000; ++i) {
                rac_cpu_runtime_provider_t out{};
                reg.find_by_desc(&desc, &out);  /* result may be true or false; no crash */
            }
        };

        std::vector<std::thread> threads;
        for (int i = 0; i < 4; ++i)
            threads.emplace_back(writer);
        for (int i = 0; i < 4; ++i)
            threads.emplace_back(reader);
        for (auto& t : threads)
            t.join();

        CHECK(errors.load() == 0, "(7) no register errors under 8-thread concurrency");
    }

    /* --- (8) rac_runtime_primitive_in_range boundaries -------------------- */
    {
        CHECK(!rac::runtime::rac_runtime_primitive_in_range(RAC_PRIMITIVE_UNSPECIFIED),
              "(8) UNSPECIFIED is out of range");
        CHECK(rac::runtime::rac_runtime_primitive_in_range(RAC_PRIMITIVE_GENERATE_TEXT),
              "(8) GENERATE_TEXT is in range");
        CHECK(rac::runtime::rac_runtime_primitive_in_range(
                  static_cast<rac_primitive_t>(RAC_PRIMITIVE_COUNT - 1)),
              "(8) COUNT-1 is in range");
        CHECK(!rac::runtime::rac_runtime_primitive_in_range(RAC_PRIMITIVE_COUNT),
              "(8) COUNT is out of range");
    }

    /* --- (9) ONNX provider type exercises the same template path ----------- */
    {
        rac::runtime::ProviderRegistry<rac_onnxrt_runtime_provider_t> reg;
        auto p = make_onnx("onnx-embed", RAC_PRIMITIVE_EMBED);

        CHECK(reg.register_provider(&p) == RAC_SUCCESS, "(9) ONNX provider registers ok");

        rac_runtime_session_desc_t desc{};
        desc.primitive = RAC_PRIMITIVE_EMBED;
        rac_onnxrt_runtime_provider_t out{};
        CHECK(reg.find_by_desc(&desc, &out), "(9) ONNX find_by_desc succeeds");
        CHECK(std::strcmp(out.name, "onnx-embed") == 0, "(9) ONNX found provider correct name");
    }

    std::fprintf(stdout, "\n%d checks, %d failed\n", g_test_count, g_fail_count);
    return g_fail_count == 0 ? 0 : 1;
}
