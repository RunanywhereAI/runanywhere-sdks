// SPDX-License-Identifier: Apache-2.0
//
// pipeline_executor.cpp — T4.7 spec compiler.

#include "rac/solutions/pipeline_executor.hpp"

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/graph/graph_scheduler.hpp"
#include "rac/graph/pipeline_node.hpp"

namespace rac::solutions {

namespace {

constexpr std::uint32_t kDefaultEdgeCapacity = 16;
constexpr std::uint32_t kMaxEdgeCapacity = 1u << 20;

struct EndpointRef {
    std::string op;
    std::string port;
};

struct ResolvedEdge {
    EndpointRef from;
    EndpointRef to;
    std::string payload_type;
    std::uint32_t capacity;
    rac::graph::OverflowPolicy policy;
};

class PayloadTypeGuardNode final : public rac::graph::IPipelineNode {
   public:
    PayloadTypeGuardNode(std::string name, std::string expected_type, std::string from_endpoint,
                         std::string to_endpoint, std::uint32_t capacity,
                         rac::graph::OverflowPolicy policy)
        : name_(std::move(name)),
          expected_type_(std::move(expected_type)),
          from_endpoint_(std::move(from_endpoint)),
          to_endpoint_(std::move(to_endpoint)),
          input_(std::make_shared<OperatorEdge>(capacity, policy)),
          output_(std::make_shared<OperatorEdge>(capacity, policy)) {}

    std::shared_ptr<OperatorEdge> input() const noexcept { return input_; }
    std::shared_ptr<OperatorEdge> output() const noexcept { return output_; }

    void set_input(std::shared_ptr<OperatorEdge> input) noexcept { input_ = std::move(input); }

    void start(std::shared_ptr<rac::graph::CancelToken> parent_cancel) override {
        bool expected = false;
        if (!started_.compare_exchange_strong(expected, true))
            return;
        root_cancel_ = std::move(parent_cancel);
        cancel_ = root_cancel_ ? root_cancel_->create_child()
                               : std::make_shared<rac::graph::CancelToken>();
        worker_ = std::thread([this] { run(); });
    }

    void stop() override {
        if (cancel_)
            cancel_->cancel();
        if (input_)
            input_->close();
    }

    void join() override {
        if (worker_.joinable())
            worker_.join();
        if (output_)
            output_->close();
    }

    const char* name() const noexcept override { return name_.c_str(); }

   private:
    void run() {
        while (cancel_ && !cancel_->is_cancelled()) {
            auto item = input_->pop(cancel_.get());
            if (!item)
                break;
            std::string body_err;
            if (!item->validate_body_contract(&body_err)) {
                report_body_violation(body_err);
                if (root_cancel_) {
                    root_cancel_->cancel();
                } else if (cancel_) {
                    cancel_->cancel();
                }
                break;
            }
            if (item->type_id != expected_type_) {
                report_violation(*item);
                if (root_cancel_) {
                    root_cancel_->cancel();
                } else if (cancel_) {
                    cancel_->cancel();
                }
                break;
            }
            if (!output_->push(std::move(*item), cancel_.get()))
                break;
        }
        if (output_)
            output_->close();
    }

    void report_body_violation(const std::string& detail) const {
        const std::string msg = "payload body contract violation on edge '" + from_endpoint_ +
                                " -> " + to_endpoint_ + "': " + detail;
        rac_error_set_details(msg.c_str());
    }

    void report_violation(const Item& item) const {
        const std::string actual = item.type_id.empty() ? std::string("<empty>") : item.type_id;
        const std::string msg = "payload type contract violation on edge '" + from_endpoint_ +
                                " -> " + to_endpoint_ + "': expected '" + expected_type_ +
                                "' but operator emitted '" + actual + "'";
        rac_error_set_details(msg.c_str());
    }

    std::string name_;
    std::string expected_type_;
    std::string from_endpoint_;
    std::string to_endpoint_;
    std::shared_ptr<OperatorEdge> input_;
    std::shared_ptr<OperatorEdge> output_;
    std::shared_ptr<rac::graph::CancelToken> root_cancel_;
    std::shared_ptr<rac::graph::CancelToken> cancel_;
    std::thread worker_;
    std::atomic<bool> started_{false};
};

void set_detail(const std::string& msg) {
    rac_error_set_details(msg.c_str());
}

bool parse_endpoint(const std::string& endpoint, const char* field_name, EndpointRef* out,
                    std::string* err) {
    if (endpoint.empty()) {
        if (err)
            *err = std::string("edge ") + field_name + " endpoint is empty";
        return false;
    }
    const auto dot = endpoint.find('.');
    if (dot == std::string::npos) {
        if (err) {
            *err = std::string("edge ") + field_name +
                   " endpoint must be '<operator>.<port>': " + endpoint;
        }
        return false;
    }
    if (dot == 0) {
        if (err) {
            *err = std::string("edge ") + field_name +
                   " endpoint has empty operator name: " + endpoint;
        }
        return false;
    }
    if (dot + 1 == endpoint.size()) {
        if (err) {
            *err = std::string("edge ") + field_name + " endpoint has empty port name: " + endpoint;
        }
        return false;
    }
    if (endpoint.find('.', dot + 1) != std::string::npos) {
        if (err) {
            *err = std::string("edge ") + field_name +
                   " endpoint must contain exactly one '.': " + endpoint;
        }
        return false;
    }
    out->op = endpoint.substr(0, dot);
    out->port = endpoint.substr(dot + 1);
    return true;
}

bool validate_edge_capacity(std::uint32_t capacity, const std::string& endpoint, std::string* err) {
    if (capacity > kMaxEdgeCapacity) {
        if (err) {
            *err = "edge capacity for '" + endpoint + "' exceeds maximum " +
                   std::to_string(kMaxEdgeCapacity);
        }
        return false;
    }
    return true;
}

bool validate_edge_policy(runanywhere::v1::EdgePolicy policy, const std::string& endpoint,
                          std::string* err) {
    if (!runanywhere::v1::EdgePolicy_IsValid(static_cast<int>(policy))) {
        if (err) {
            *err = "edge policy for '" + endpoint + "' is not a recognised EdgePolicy value";
        }
        return false;
    }
    return true;
}

bool validate_payload_type(const std::string& type, const std::string& endpoint, std::string* err) {
    if (type.empty()) {
        if (err)
            *err = "payload type for endpoint '" + endpoint + "' is empty";
        return false;
    }
    if (type == "opaque.bytes") {
        if (err) {
            *err = "payload type for endpoint '" + endpoint + "' uses legacy opaque.bytes metadata";
        }
        return false;
    }
    return true;
}

rac::graph::OverflowPolicy to_overflow_policy(runanywhere::v1::EdgePolicy policy) {
    switch (policy) {
        case runanywhere::v1::EDGE_POLICY_DROP_OLDEST:
            return rac::graph::OverflowPolicy::DropOldest;
        case runanywhere::v1::EDGE_POLICY_DROP_NEWEST:
            return rac::graph::OverflowPolicy::DropNewest;
        case runanywhere::v1::EDGE_POLICY_UNSPECIFIED:
        case runanywhere::v1::EDGE_POLICY_BLOCK:
            return rac::graph::OverflowPolicy::BlockProducer;
        default:
            return rac::graph::OverflowPolicy::BlockProducer;
    }
}

std::string endpoint_key(const EndpointRef& endpoint) {
    return endpoint.op + "." + endpoint.port;
}

bool is_known_engine_backed_solution_type(const std::string& type) {
    const char* const kTypes[] = {
        "agent_loop",    "anomaly_detect", "detect_voice", "embed",
        "generate_text", "retrieve",       "synthesize",   "transcribe",
    };
    for (const char* candidate : kTypes) {
        if (type == candidate)
            return true;
    }
    return false;
}

std::string unsupported_port_message(const std::string& op, const std::string& type,
                                     const char* direction, const std::string& port) {
    return "factory for operator '" + op + "' (type '" + type + "') does not expose " + direction +
           " port '" + port +
           "' as an independent edge; register an OperatorAdapterFactory "
           "for true multi-port operators or use a single active port with "
           "the OperatorFactory single-port adapter";
}

}  // namespace

PipelineExecutor::PipelineExecutor(runanywhere::v1::PipelineSpec spec) : spec_(std::move(spec)) {}

std::unique_ptr<rac::graph::GraphScheduler> PipelineExecutor::build(rac_result_t* out_error) {
    root_input_edge_.reset();
    root_output_edge_.reset();
    root_input_payload_type_.clear();
    root_output_payload_type_.clear();

    rac_result_t status = RAC_SUCCESS;
    auto set_error = [&](rac_result_t code, const std::string& msg) {
        status = code;
        set_detail(msg);
    };
    auto emit_null = [&](rac_result_t code,
                         const std::string& msg) -> std::unique_ptr<rac::graph::GraphScheduler> {
        set_error(code, msg);
        if (out_error)
            *out_error = status;
        return nullptr;
    };

    // ---- 1. Validate operator uniqueness + factory availability -----------
    std::unordered_map<std::string, std::string> op_types;
    op_types.reserve(spec_.operators_size());

    const auto& registry = OperatorRegistry::instance();
    for (const auto& op : spec_.operators()) {
        if (op.name().empty()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "operator with empty name in spec '" + spec_.name() + "'");
        }
        if (op.name().find('.') != std::string::npos) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "operator name must not contain '.': " + op.name());
        }
        if (op.type().empty()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "operator '" + op.name() + "' has empty type");
        }
        if (op_types.count(op.name())) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "duplicate operator name: " + op.name());
        }
        if (!registry.has_factory(op.type())) {
            if (is_known_engine_backed_solution_type(op.type())) {
                return emit_null(RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                 "solution operator type '" + op.type() +
                                     "' has no registered real operator factory "
                                     "(operator '" +
                                     op.name() +
                                     "'); tests must register an explicit stand-in factory");
            }
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "no factory registered for operator type '" + op.type() +
                                 "' (operator '" + op.name() + "')");
        }
        for (const auto& port : registry.input_ports(op.type())) {
            std::string err;
            if (!validate_payload_type(registry.input_port_type(op.type(), port),
                                       op.name() + "." + port, &err)) {
                return emit_null(RAC_ERROR_INVALID_CONFIGURATION, err);
            }
        }
        for (const auto& port : registry.output_ports(op.type())) {
            std::string err;
            if (!validate_payload_type(registry.output_port_type(op.type(), port),
                                       op.name() + "." + port, &err)) {
                return emit_null(RAC_ERROR_INVALID_CONFIGURATION, err);
            }
        }
        op_types.emplace(op.name(), op.type());
    }

    // ---- 2. Validate and resolve edge endpoints/options -------------------
    std::vector<ResolvedEdge> resolved_edges;
    resolved_edges.reserve(spec_.edges_size());

    std::unordered_set<std::string> edge_keys;
    std::unordered_map<std::string, std::vector<std::size_t>> outgoing_by_endpoint;
    std::unordered_map<std::string, std::vector<std::size_t>> incoming_by_endpoint;

    for (const auto& edge : spec_.edges()) {
        std::string err;
        EndpointRef from;
        EndpointRef to;
        if (!parse_endpoint(edge.from(), "from", &from, &err)) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION, err);
        }
        if (!parse_endpoint(edge.to(), "to", &to, &err)) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION, err);
        }
        auto src_type = op_types.find(from.op);
        auto dst_type = op_types.find(to.op);
        if (src_type == op_types.end()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "edge references unknown producer: " + edge.from());
        }
        if (dst_type == op_types.end()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "edge references unknown consumer: " + edge.to());
        }
        if (!registry.has_output_port(src_type->second, from.port)) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "edge references unknown output port '" + from.port +
                                 "' on operator '" + from.op + "'");
        }
        if (!registry.has_input_port(dst_type->second, to.port)) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "edge references unknown input port '" + to.port + "' on operator '" +
                                 to.op + "'");
        }
        const auto& output_type = registry.output_port_type(src_type->second, from.port);
        const auto& input_type = registry.input_port_type(dst_type->second, to.port);
        if (!validate_payload_type(output_type, edge.from(), &err)) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION, err);
        }
        if (!validate_payload_type(input_type, edge.to(), &err)) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION, err);
        }
        if (output_type != input_type) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "edge has incompatible payload types: '" + edge.from() +
                                 "' produces '" + output_type + "' but '" + edge.to() +
                                 "' expects '" + input_type + "'");
        }
        if (!validate_edge_capacity(edge.capacity(), edge.from(), &err)) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION, err);
        }
        if (!validate_edge_policy(edge.policy(), edge.from(), &err)) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION, err);
        }

        const std::string pair_key = endpoint_key(from) + "->" + endpoint_key(to);
        if (!edge_keys.insert(pair_key).second) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION, "duplicate edge: " + pair_key);
        }

        const std::uint32_t capacity =
            edge.capacity() == 0 ? kDefaultEdgeCapacity : edge.capacity();
        const std::size_t edge_index = resolved_edges.size();
        outgoing_by_endpoint[endpoint_key(from)].push_back(edge_index);
        incoming_by_endpoint[endpoint_key(to)].push_back(edge_index);
        resolved_edges.push_back({std::move(from), std::move(to), output_type, capacity,
                                  to_overflow_policy(edge.policy())});
    }

    // ---- 3. Materialize nodes ---------------------------------------------
    std::unordered_map<std::string, std::shared_ptr<OperatorAdapter>> nodes;
    nodes.reserve(spec_.operators_size());

    for (const auto& op : spec_.operators()) {
        auto node = registry.create_adapter(op);
        if (!node) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "factory returned null for operator '" + op.name() + "'");
        }
        nodes.emplace(op.name(), std::move(node));
    }

    // ---- 4. Build split/merge adapters ------------------------------------
    std::vector<std::size_t> split_output_index(resolved_edges.size(), 0);
    std::vector<std::size_t> merge_input_index(resolved_edges.size(), 0);

    std::unordered_map<std::string, std::shared_ptr<rac::graph::SplitNode<Item>>> split_nodes;
    std::unordered_map<std::string, std::shared_ptr<rac::graph::MergeNode<Item>>> merge_nodes;
    std::vector<std::shared_ptr<rac::graph::SplitNode<Item>>> split_order;
    std::vector<std::shared_ptr<rac::graph::MergeNode<Item>>> merge_order;

    for (const auto& [from_endpoint, edge_indices] : outgoing_by_endpoint) {
        if (edge_indices.size() <= 1)
            continue;

        const auto& first = resolved_edges[edge_indices.front()];
        for (std::size_t edge_index : edge_indices) {
            const auto& edge = resolved_edges[edge_index];
            if (edge.capacity != first.capacity || edge.policy != first.policy) {
                return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                                 "fan-out from endpoint '" + from_endpoint +
                                     "' uses different edge capacity/policy values; "
                                     "executor SplitNode fan-out requires uniform branch "
                                     "edge options");
            }
        }

        auto split = std::make_shared<rac::graph::SplitNode<Item>>(
            "__split_" + from_endpoint, edge_indices.size(), first.capacity, first.policy);
        auto internal_edge = std::make_shared<OperatorEdge>(first.capacity, first.policy);
        auto producer = nodes.find(first.from.op);
        if (producer == nodes.end()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "split adapter references missing producer '" + first.from.op + "'");
        }
        const auto producer_type = op_types.find(first.from.op);
        const std::string type =
            producer_type == op_types.end() ? std::string{} : producer_type->second;
        if (!producer->second->set_output(first.from.port, internal_edge)) {
            return emit_null(
                RAC_ERROR_INVALID_CONFIGURATION,
                unsupported_port_message(first.from.op, type, "output", first.from.port));
        }
        split->set_input(internal_edge);

        for (std::size_t i = 0; i < edge_indices.size(); ++i) {
            split_output_index[edge_indices[i]] = i;
        }
        split_nodes.emplace(from_endpoint, split);
        split_order.push_back(std::move(split));
    }

    for (const auto& [to_endpoint, edge_indices] : incoming_by_endpoint) {
        if (edge_indices.size() <= 1)
            continue;

        const auto& first = resolved_edges[edge_indices.front()];
        auto merge = std::make_shared<rac::graph::MergeNode<Item>>(
            "__merge_" + to_endpoint, edge_indices.size(), first.capacity, first.policy);
        auto consumer = nodes.find(first.to.op);
        if (consumer == nodes.end()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "merge adapter references missing consumer '" + first.to.op + "'");
        }
        const auto consumer_type = op_types.find(first.to.op);
        const std::string type =
            consumer_type == op_types.end() ? std::string{} : consumer_type->second;
        if (!consumer->second->set_input(first.to.port, merge->output())) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             unsupported_port_message(first.to.op, type, "input", first.to.port));
        }

        for (std::size_t i = 0; i < edge_indices.size(); ++i) {
            merge_input_index[edge_indices[i]] = i;
        }
        merge_nodes.emplace(to_endpoint, merge);
        merge_order.push_back(std::move(merge));
    }

    std::vector<std::shared_ptr<PayloadTypeGuardNode>> guard_order;
    guard_order.reserve(resolved_edges.size());
    for (std::size_t i = 0; i < resolved_edges.size(); ++i) {
        const auto& edge = resolved_edges[i];
        guard_order.push_back(std::make_shared<PayloadTypeGuardNode>(
            "__payload_type_guard_" + std::to_string(i) + "_" + endpoint_key(edge.from) + "_to_" +
                endpoint_key(edge.to),
            edge.payload_type, endpoint_key(edge.from), endpoint_key(edge.to), edge.capacity,
            edge.policy));
    }

    // ---- 5. Wire the graph -------------------------------------------------
    //
    // Track per-operator in/out degree so we can identify the root
    // input (the operator with zero inbound edges) and root output
    // (the operator with zero outbound edges). The first candidate
    // wins — pipelines with multiple sources/sinks are valid and the
    // caller uses the PipelineSpec itself to steer the extras (e.g.
    // via operator-specific params).
    std::unordered_map<std::string, int> in_degree;
    std::unordered_map<std::string, int> out_degree;
    for (const auto& [name, _] : nodes) {
        in_degree[name] = 0;
        out_degree[name] = 0;
    }

    for (std::size_t i = 0; i < resolved_edges.size(); ++i) {
        const auto& edge = resolved_edges[i];
        auto src = nodes.find(edge.from.op);
        auto dst = nodes.find(edge.to.op);
        if (src == nodes.end() || dst == nodes.end()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "resolved edge references missing operator");
        }

        std::shared_ptr<OperatorEdge> upstream_stream;
        auto split = split_nodes.find(endpoint_key(edge.from));
        if (split != split_nodes.end()) {
            upstream_stream = split->second->output(split_output_index[i]);
        } else {
            upstream_stream = std::make_shared<OperatorEdge>(edge.capacity, edge.policy);
            auto type = op_types.find(edge.from.op);
            const std::string type_name = type == op_types.end() ? std::string{} : type->second;
            if (!src->second->set_output(edge.from.port, upstream_stream)) {
                return emit_null(
                    RAC_ERROR_INVALID_CONFIGURATION,
                    unsupported_port_message(edge.from.op, type_name, "output", edge.from.port));
            }
        }

        auto guard = guard_order.at(i);
        guard->set_input(std::move(upstream_stream));
        auto stream = guard->output();

        auto merge = merge_nodes.find(endpoint_key(edge.to));
        if (merge != merge_nodes.end()) {
            merge->second->set_input(merge_input_index[i], stream);
        } else {
            auto type = op_types.find(edge.to.op);
            const std::string type_name = type == op_types.end() ? std::string{} : type->second;
            if (!dst->second->set_input(edge.to.port, stream)) {
                return emit_null(
                    RAC_ERROR_INVALID_CONFIGURATION,
                    unsupported_port_message(edge.to.op, type_name, "input", edge.to.port));
            }
        }

        ++out_degree[edge.from.op];
        ++in_degree[edge.to.op];
    }

    // ---- 6. Pick root input / root output ---------------------------------
    std::shared_ptr<OperatorAdapter> root_input_node;
    std::shared_ptr<OperatorAdapter> root_output_node;
    std::string root_input_type;
    std::string root_output_type;
    for (const auto& op : spec_.operators()) {
        auto it = nodes.find(op.name());
        if (it == nodes.end())
            continue;
        if (in_degree[op.name()] == 0 && !root_input_node) {
            root_input_node = it->second;
            root_input_type = op.type();
        }
        if (out_degree[op.name()] == 0 && !root_output_node) {
            root_output_node = it->second;
            root_output_type = op.type();
        }
    }

    // ---- 7. Strict validation: no orphaned / unreferenced operators -------
    if (spec_.options().strict_validation()) {
        for (const auto& op : spec_.operators()) {
            const bool is_source = in_degree[op.name()] == 0;
            const bool is_sink = out_degree[op.name()] == 0;
            if (is_source && is_sink && spec_.operators_size() > 1) {
                return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                                 "strict_validation: operator '" + op.name() +
                                     "' has no inbound or outbound edges");
            }
        }
    }

    struct ChosenPort {
        std::shared_ptr<OperatorEdge> edge;
        std::string payload_type;
    };

    auto choose_input = [&](const std::shared_ptr<OperatorAdapter>& node,
                            const std::string& type) -> ChosenPort {
        if (!node)
            return {};
        auto edge = node->input("in");
        if (edge)
            return {edge, registry.input_port_type(type, "in")};
        for (const auto& port : registry.input_ports(type)) {
            edge = node->input(port);
            if (edge)
                return {edge, registry.input_port_type(type, port)};
        }
        return {};
    };
    auto choose_output = [&](const std::shared_ptr<OperatorAdapter>& node,
                             const std::string& type) -> ChosenPort {
        if (!node)
            return {};
        auto edge = node->output("out");
        if (edge)
            return {edge, registry.output_port_type(type, "out")};
        for (const auto& port : registry.output_ports(type)) {
            edge = node->output(port);
            if (edge)
                return {edge, registry.output_port_type(type, port)};
        }
        return {};
    };

    if (root_input_node) {
        auto chosen = choose_input(root_input_node, root_input_type);
        root_input_edge_ = std::move(chosen.edge);
        root_input_payload_type_ = std::move(chosen.payload_type);
    }
    if (root_output_node) {
        auto chosen = choose_output(root_output_node, root_output_type);
        root_output_edge_ = std::move(chosen.edge);
        root_output_payload_type_ = std::move(chosen.payload_type);
    }

    auto scheduler = std::make_unique<rac::graph::GraphScheduler>(/*pool*/ 0);
    // SplitNode closes branch outputs from join(), so it must be joined before
    // any consumers waiting on those outputs. Payload guards sit between every
    // producer edge and consumer edge, so they are joined before operator
    // consumers and after split adapters.
    for (const auto& split : split_order) {
        scheduler->add_node(split);
    }
    for (const auto& guard : guard_order) {
        scheduler->add_node(guard);
    }
    for (const auto& op : spec_.operators()) {
        auto node = nodes.find(op.name());
        if (node == nodes.end()) {
            return emit_null(RAC_ERROR_INVALID_CONFIGURATION,
                             "materialized node missing for operator '" + op.name() + "'");
        }
        scheduler->add_node(node->second);
    }
    for (const auto& merge : merge_order) {
        scheduler->add_node(merge);
    }

    if (out_error)
        *out_error = RAC_SUCCESS;
    return scheduler;
}

}  // namespace rac::solutions
