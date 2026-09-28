// SPDX-License-Identifier: Apache-2.0
//
// Focused coverage for issue #914: attaching a live RAG session handle to
// SolutionRunner before PipelineExecutor materializes retrieve nodes.

#include <cstdint>
#include <iostream>
#include <string>

#include "pipeline.pb.h"
#include "rac/core/rac_error.h"
#include "rac/solutions/solution_runner.hpp"

using rac::solutions::SolutionRunner;
using runanywhere::v1::PipelineSpec;

namespace {

int failures = 0;

#define CHECK(expr)                                                                         \
    do {                                                                                    \
        if (!(expr)) {                                                                      \
            std::cerr << __FILE__ << ':' << __LINE__ << ": CHECK failed: " #expr << '\n'; \
            ++failures;                                                                     \
        }                                                                                   \
    } while (0)

rac_handle_t fake_session(std::uintptr_t value) {
    return reinterpret_cast<rac_handle_t>(value);
}

PipelineSpec make_retrieve_spec(int retrieve_count = 1) {
    PipelineSpec spec;
    spec.set_name("rag_attach_test");

    for (int i = 0; i < retrieve_count; ++i) {
        auto* op = spec.add_operators();
        op->set_name("retrieve_" + std::to_string(i));
        op->set_type("retrieve");
    }

    return spec;
}

void test_attach_stamps_retrieve_operator() {
    SolutionRunner runner(make_retrieve_spec());
    const auto session = fake_session(0x1234);

    CHECK(runner.attach_rag_session(session) == RAC_SUCCESS);

    const auto& spec = runner.spec();
    CHECK(spec.operators_size() == 1);
    const auto& params = spec.operators(0).params();
    const auto it = params.find("session_handle_id");
    CHECK(it != params.end());
    if (it != params.end()) {
        CHECK(it->second == std::to_string(reinterpret_cast<std::uintptr_t>(session)));
    }
}

void test_attach_stamps_all_retrieve_operators_only() {
    PipelineSpec spec = make_retrieve_spec(2);
    auto* llm = spec.add_operators();
    llm->set_name("llm");
    llm->set_type("generate_text");

    SolutionRunner runner(std::move(spec));
    const auto session = fake_session(0x5678);
    const std::string expected =
        std::to_string(reinterpret_cast<std::uintptr_t>(session));

    CHECK(runner.attach_rag_session(session) == RAC_SUCCESS);

    int stamped = 0;
    for (const auto& op : runner.spec().operators()) {
        const auto it = op.params().find("session_handle_id");
        if (op.type() == "retrieve") {
            CHECK(it != op.params().end());
            if (it != op.params().end())
                CHECK(it->second == expected);
            ++stamped;
        } else {
            CHECK(it == op.params().end());
        }
    }
    CHECK(stamped == 2);
}

void test_attach_rejects_null_session() {
    SolutionRunner runner(make_retrieve_spec());
    CHECK(runner.attach_rag_session(nullptr) == RAC_ERROR_INVALID_HANDLE);
}

void test_attach_rejects_pipeline_without_retrieve() {
    PipelineSpec spec;
    spec.set_name("no_retrieve");
    auto* op = spec.add_operators();
    op->set_name("source");
    op->set_type("source");

    SolutionRunner runner(std::move(spec));
    CHECK(runner.attach_rag_session(fake_session(0x9abc)) ==
          RAC_ERROR_INVALID_CONFIGURATION);
}

}  // namespace

int main() {
    test_attach_stamps_retrieve_operator();
    test_attach_stamps_all_retrieve_operators_only();
    test_attach_rejects_null_session();
    test_attach_rejects_pipeline_without_retrieve();

    if (failures != 0) {
        std::cerr << failures << " solution RAG attach test(s) failed\n";
        return 1;
    }

    std::cout << "solution RAG attach tests passed\n";
    return 0;
}
