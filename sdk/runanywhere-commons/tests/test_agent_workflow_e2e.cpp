// SPDX-License-Identifier: Apache-2.0
//
// test_agent_workflow_e2e.cpp — runs real workflows against real files.
//
// The other agent test covers pure functions. This one installs the desktop
// platform adapter, points the model-paths base at a temp directory, and drives
// the public C ABI end to end: save, load, list, validate, run, and read the
// persisted record back.
//
// Only nodes that need no model or network are exercised, so the suite stays
// hermetic. That still covers the parts most likely to be wrong: per-port input
// gathering, Condition and Filter branch routing, expression resolution against
// real upstream output, loop iteration, and run-record persistence.

#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#if defined(RAC_HAVE_PROTOBUF)
#include "agent_workflow.pb.h"

#include "rac/agent/rac_agent_workflow.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace {

int g_failed = 0;
int g_passed = 0;

#define CHECK(cond)                                                               \
    do {                                                                          \
        if (!(cond)) {                                                            \
            std::fprintf(stderr, "[FAIL] %s:%d %s\n", __FILE__, __LINE__, #cond); \
            g_failed++;                                                           \
            return;                                                               \
        }                                                                         \
    } while (0)

#define TEST(name)                                      \
    static void test_##name();                          \
    static void run_test_##name() {                     \
        std::fprintf(stderr, "[RUN ] %s\n", #name);     \
        int before_failed = g_failed;                   \
        test_##name();                                  \
        if (g_failed == before_failed) {                \
            std::fprintf(stderr, "[  OK] %s\n", #name); \
            g_passed++;                                 \
        }                                               \
    }                                                   \
    static void test_##name()

using runanywhere::v1::NodeRunState;
using runanywhere::v1::WorkflowDocument;
using runanywhere::v1::WorkflowNode;
using runanywhere::v1::WorkflowRunRecord;
using runanywhere::v1::WorkflowRunState;

WorkflowNode* add_trigger(WorkflowDocument* document, const std::string& id,
                          const std::string& name, const std::string& items_json) {
    WorkflowNode* node = document->add_nodes();
    node->set_id(id);
    node->set_name(name);
    node->mutable_manual_trigger()->set_initial_items_json(items_json);
    return node;
}

WorkflowNode* add_transform(WorkflowDocument* document, const std::string& id,
                            const std::string& name, const std::string& field,
                            const std::string& value) {
    WorkflowNode* node = document->add_nodes();
    node->set_id(id);
    node->set_name(name);
    auto* assignment = node->mutable_set_transform()->add_assignments();
    assignment->set_field(field);
    assignment->set_value(value);
    return node;
}

void connect(WorkflowDocument* document, const std::string& from, const std::string& from_port,
             const std::string& to, const std::string& to_port) {
    auto* edge = document->add_edges();
    edge->set_from_node(from);
    edge->set_from_port(from_port);
    edge->set_to_node(to);
    edge->set_to_port(to_port);
}

rac_result_t save(const WorkflowDocument& document) {
    const std::string encoded = document.SerializeAsString();
    return rac_agent_workflow_save_proto(reinterpret_cast<const uint8_t*>(encoded.data()),
                                         encoded.size());
}

/// Start a run and block until it settles. The runner is asynchronous, so the
/// poll is on the record's own terminal state rather than a fixed sleep.
bool run_to_completion(const std::string& workflow_id, WorkflowRunRecord* out_record) {
    runanywhere::v1::WorkflowRunRequest request;
    request.set_workflow_id(workflow_id);
    const std::string encoded = request.SerializeAsString();

    rac_handle_t run = nullptr;
    if (rac_agent_run_create_proto(reinterpret_cast<const uint8_t*>(encoded.data()), encoded.size(),
                                   nullptr, nullptr, &run) != RAC_SUCCESS) {
        return false;
    }
    if (rac_agent_run_start(run) != RAC_SUCCESS) {
        rac_agent_run_destroy(run);
        return false;
    }

    for (int attempt = 0; attempt < 400; ++attempt) {
        rac_proto_buffer_t buffer;
        rac_proto_buffer_init(&buffer);
        const rac_result_t result = rac_agent_run_record_proto(run, &buffer);
        if (result == RAC_SUCCESS && buffer.data != nullptr) {
            out_record->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
        }
        rac_proto_buffer_free(&buffer);

        const WorkflowRunState state = out_record->state();
        if (state == WorkflowRunState::WORKFLOW_RUN_STATE_SUCCEEDED
            || state == WorkflowRunState::WORKFLOW_RUN_STATE_FAILED
            || state == WorkflowRunState::WORKFLOW_RUN_STATE_CANCELLED) {
            rac_agent_run_destroy(run);
            return true;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
    }

    rac_agent_run_destroy(run);
    return false;
}

const runanywhere::v1::NodeRun* node_run(const WorkflowRunRecord& record, const std::string& id) {
    for (const auto& entry : record.node_runs()) {
        if (entry.node_id() == id)
            return &entry;
    }
    return nullptr;
}

TEST(save_load_and_list_round_trip) {
    WorkflowDocument document;
    document.set_id("e2e-roundtrip");
    document.set_name("Round trip");
    add_trigger(&document, "n1", "Start", R"([{"value": 1}])");
    add_transform(&document, "n2", "Label", "label", "hello");
    connect(&document, "n1", "out", "n2", "in");

    CHECK(save(document) == RAC_SUCCESS);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    CHECK(rac_agent_workflow_load_proto("e2e-roundtrip", &buffer) == RAC_SUCCESS);

    WorkflowDocument loaded;
    CHECK(loaded.ParseFromArray(buffer.data, static_cast<int>(buffer.size)));
    rac_proto_buffer_free(&buffer);

    CHECK(loaded.id() == "e2e-roundtrip");
    CHECK(loaded.nodes_size() == 2);
    CHECK(loaded.edges_size() == 1);
    // The store stamps the schema version on write, so a document that never
    // set it comes back carrying one.
    CHECK(loaded.schema_version() == 1);

    rac_proto_buffer_init(&buffer);
    CHECK(rac_agent_workflow_list_proto(&buffer) == RAC_SUCCESS);
    runanywhere::v1::WorkflowList list;
    CHECK(list.ParseFromArray(buffer.data, static_cast<int>(buffer.size)));
    rac_proto_buffer_free(&buffer);

    bool found = false;
    for (const auto& summary : list.workflows()) {
        if (summary.id() == "e2e-roundtrip") {
            found = true;
            CHECK(summary.node_count() == 2);
        }
    }
    CHECK(found);
}

TEST(a_linear_workflow_runs_and_resolves_expressions) {
    WorkflowDocument document;
    document.set_id("e2e-linear");
    document.set_name("Linear");
    add_trigger(&document, "n1", "Start", R"([{"name": "world"}])");
    add_transform(&document, "n2", "Greet", "greeting", "hello {{ Start.name }}");
    connect(&document, "n1", "out", "n2", "in");
    CHECK(save(document) == RAC_SUCCESS);

    WorkflowRunRecord record;
    CHECK(run_to_completion("e2e-linear", &record));
    CHECK(record.state() == WorkflowRunState::WORKFLOW_RUN_STATE_SUCCEEDED);

    const auto* greet = node_run(record, "n2");
    CHECK(greet != nullptr);
    CHECK(greet->state() == NodeRunState::NODE_RUN_STATE_SUCCEEDED);
    CHECK(greet->output_size() == 1);
    // The expression read the trigger's output, so the upstream value reached
    // the downstream node through the real runner rather than a stub.
    CHECK(greet->output(0).json().find("hello world") != std::string::npos);
}

TEST(a_condition_skips_the_branch_it_did_not_take) {
    WorkflowDocument document;
    document.set_id("e2e-condition");
    document.set_name("Condition");
    add_trigger(&document, "n1", "Start", R"([{"count": 5}])");

    WorkflowNode* check = document.add_nodes();
    check->set_id("n2");
    check->set_name("Check");
    check->mutable_condition()->set_left("{{ Start.count }}");
    check->mutable_condition()->set_operator_(
        runanywhere::v1::COMPARISON_OPERATOR_GREATER_THAN);
    check->mutable_condition()->set_right("3");

    add_transform(&document, "n3", "High", "band", "high");
    add_transform(&document, "n4", "Low", "band", "low");
    connect(&document, "n1", "out", "n2", "in");
    connect(&document, "n2", "true", "n3", "in");
    connect(&document, "n2", "false", "n4", "in");
    CHECK(save(document) == RAC_SUCCESS);

    WorkflowRunRecord record;
    CHECK(run_to_completion("e2e-condition", &record));
    CHECK(record.state() == WorkflowRunState::WORKFLOW_RUN_STATE_SUCCEEDED);

    const auto* high = node_run(record, "n3");
    const auto* low = node_run(record, "n4");
    CHECK(high != nullptr && low != nullptr);
    CHECK(high->state() == NodeRunState::NODE_RUN_STATE_SUCCEEDED);
    // The untaken branch is skipped, which is not a failure and must not stop
    // the run.
    CHECK(low->state() == NodeRunState::NODE_RUN_STATE_SKIPPED);
}

TEST(a_filter_feeds_both_of_its_ports) {
    WorkflowDocument document;
    document.set_id("e2e-filter");
    document.set_name("Filter");
    add_trigger(&document, "n1", "Start",
                R"([{"n": 1}, {"n": 9}, {"n": 2}, {"n": 7}])");

    WorkflowNode* filter = document.add_nodes();
    filter->set_id("n2");
    filter->set_name("Big");
    filter->mutable_filter()->set_left("{{ item.n }}");
    filter->mutable_filter()->set_operator_(runanywhere::v1::COMPARISON_OPERATOR_GREATER_THAN);
    filter->mutable_filter()->set_right("5");

    add_transform(&document, "n3", "Kept", "side", "kept");
    add_transform(&document, "n4", "Dropped", "side", "dropped");
    connect(&document, "n1", "out", "n2", "in");
    connect(&document, "n2", "true", "n3", "in");
    connect(&document, "n2", "false", "n4", "in");
    CHECK(save(document) == RAC_SUCCESS);

    WorkflowRunRecord record;
    CHECK(run_to_completion("e2e-filter", &record));
    CHECK(record.state() == WorkflowRunState::WORKFLOW_RUN_STATE_SUCCEEDED);

    // Both sides ran from one execution, which is the thing per-port output
    // storage exists for.
    const auto* kept = node_run(record, "n3");
    const auto* dropped = node_run(record, "n4");
    CHECK(kept != nullptr && dropped != nullptr);
    CHECK(kept->state() == NodeRunState::NODE_RUN_STATE_SUCCEEDED);
    CHECK(dropped->state() == NodeRunState::NODE_RUN_STATE_SUCCEEDED);
    CHECK(kept->output_size() == 2);
    CHECK(dropped->output_size() == 2);
}

TEST(split_out_and_aggregate_are_inverses) {
    WorkflowDocument document;
    document.set_id("e2e-splitagg");
    document.set_name("Split and aggregate");
    add_trigger(&document, "n1", "Start", R"([{"rows": ["a", "b", "c"]}])");

    WorkflowNode* split = document.add_nodes();
    split->set_id("n2");
    split->set_name("Split");
    split->mutable_split_out()->set_field("{{ Start.rows }}");

    WorkflowNode* aggregate = document.add_nodes();
    aggregate->set_id("n3");
    aggregate->set_name("Collect");
    aggregate->mutable_aggregate()->set_field("all");

    connect(&document, "n1", "out", "n2", "in");
    connect(&document, "n2", "out", "n3", "in");
    CHECK(save(document) == RAC_SUCCESS);

    WorkflowRunRecord record;
    CHECK(run_to_completion("e2e-splitagg", &record));
    CHECK(record.state() == WorkflowRunState::WORKFLOW_RUN_STATE_SUCCEEDED);

    const auto* split_run = node_run(record, "n2");
    const auto* collect = node_run(record, "n3");
    CHECK(split_run != nullptr && collect != nullptr);
    CHECK(split_run->output_size() == 3);
    CHECK(collect->output_size() == 1);
}

TEST(a_failing_node_fails_the_run_without_stopping_the_others) {
    WorkflowDocument document;
    document.set_id("e2e-failure");
    document.set_name("Failure");
    add_trigger(&document, "n1", "Start", R"([{"value": 1}])");
    // Reads a field that does not exist. An unresolvable reference is an error
    // rather than an empty substitution, so this node must fail.
    add_transform(&document, "n2", "Broken", "x", "{{ Start.absent }}");
    add_transform(&document, "n3", "Fine", "y", "ok");
    connect(&document, "n1", "out", "n2", "in");
    connect(&document, "n1", "out", "n3", "in");
    CHECK(save(document) == RAC_SUCCESS);

    WorkflowRunRecord record;
    CHECK(run_to_completion("e2e-failure", &record));
    CHECK(record.state() == WorkflowRunState::WORKFLOW_RUN_STATE_FAILED);

    const auto* broken = node_run(record, "n2");
    const auto* fine = node_run(record, "n3");
    CHECK(broken != nullptr && fine != nullptr);
    CHECK(broken->state() == NodeRunState::NODE_RUN_STATE_FAILED);
    CHECK(broken->has_error());
    // A sibling branch is independent of the failure.
    CHECK(fine->state() == NodeRunState::NODE_RUN_STATE_SUCCEEDED);
}

TEST(the_run_record_persists_and_reloads) {
    WorkflowDocument document;
    document.set_id("e2e-record");
    document.set_name("Record");
    add_trigger(&document, "n1", "Start", R"([{"value": 1}])");
    add_transform(&document, "n2", "Mark", "marked", "yes");
    connect(&document, "n1", "out", "n2", "in");
    CHECK(save(document) == RAC_SUCCESS);

    WorkflowRunRecord record;
    CHECK(run_to_completion("e2e-record", &record));
    CHECK(record.state() == WorkflowRunState::WORKFLOW_RUN_STATE_SUCCEEDED);
    CHECK(!record.run_id().empty());

    // Destroying the handle persists first, so the finished run is readable
    // from disk afterwards.
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t result =
        rac_agent_run_record_load_proto("e2e-record", record.run_id().c_str(), &buffer);
    CHECK(result == RAC_SUCCESS);

    WorkflowRunRecord reloaded;
    CHECK(reloaded.ParseFromArray(buffer.data, static_cast<int>(buffer.size)));
    rac_proto_buffer_free(&buffer);

    CHECK(reloaded.run_id() == record.run_id());
    CHECK(reloaded.state() == WorkflowRunState::WORKFLOW_RUN_STATE_SUCCEEDED);
    CHECK(reloaded.node_runs_size() == record.node_runs_size());
}

TEST(deleting_a_workflow_removes_it_from_the_listing) {
    WorkflowDocument document;
    document.set_id("e2e-delete");
    document.set_name("Delete me");
    add_trigger(&document, "n1", "Start", "");
    CHECK(save(document) == RAC_SUCCESS);
    CHECK(rac_agent_workflow_delete("e2e-delete") == RAC_SUCCESS);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    CHECK(rac_agent_workflow_list_proto(&buffer) == RAC_SUCCESS);
    runanywhere::v1::WorkflowList list;
    CHECK(list.ParseFromArray(buffer.data, static_cast<int>(buffer.size)));
    rac_proto_buffer_free(&buffer);

    for (const auto& summary : list.workflows())
        CHECK(summary.id() != "e2e-delete");

    // Deleting again is a success, so callers never have to check first.
    CHECK(rac_agent_workflow_delete("e2e-delete") == RAC_SUCCESS);
}

TEST(an_invalid_document_is_refused_by_save) {
    WorkflowDocument document;
    document.set_id("e2e-invalid");
    document.set_name("Invalid");
    // No trigger, so the graph can never start.
    add_transform(&document, "n1", "Orphan", "x", "1");

    CHECK(save(document) != RAC_SUCCESS);

    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    CHECK(rac_agent_workflow_load_proto("e2e-invalid", &buffer) == RAC_ERROR_NOT_FOUND);
    rac_proto_buffer_free(&buffer);
}

}  // namespace

int main() {
    char temp_template[] = "/tmp/rac-agent-e2e-XXXXXX";
    const char* base = mkdtemp(temp_template);
    if (base == nullptr) {
        std::fprintf(stderr, "could not create a temp directory\n");
        return 1;
    }

    static rac_platform_adapter_t adapter;
    if (rac_desktop_adapter_init(nullptr, &adapter) != RAC_SUCCESS) {
        std::fprintf(stderr, "could not initialize the desktop adapter\n");
        return 1;
    }
    if (rac_set_platform_adapter(&adapter) != RAC_SUCCESS) {
        std::fprintf(stderr, "could not install the platform adapter\n");
        return 1;
    }
    if (rac_model_paths_set_base_dir(base) != RAC_SUCCESS) {
        std::fprintf(stderr, "could not set the model paths base directory\n");
        return 1;
    }

    std::fprintf(stderr, "base directory: %s\n\n", base);

    run_test_save_load_and_list_round_trip();
    run_test_a_linear_workflow_runs_and_resolves_expressions();
    run_test_a_condition_skips_the_branch_it_did_not_take();
    run_test_a_filter_feeds_both_of_its_ports();
    run_test_split_out_and_aggregate_are_inverses();
    run_test_a_failing_node_fails_the_run_without_stopping_the_others();
    run_test_the_run_record_persists_and_reloads();
    run_test_deleting_a_workflow_removes_it_from_the_listing();
    run_test_an_invalid_document_is_refused_by_save();

    std::fprintf(stderr, "\n%d passed / %d failed\n", g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}

#else  // !RAC_HAVE_PROTOBUF

int main() {
    std::fprintf(stderr, "[SKIP] RAC_HAVE_PROTOBUF not defined\n");
    return 0;
}

#endif
