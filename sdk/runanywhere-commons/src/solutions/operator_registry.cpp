// SPDX-License-Identifier: Apache-2.0
//
// operator_registry.cpp — T4.7 factory table + built-in neutral ops.

#include "rac/solutions/operator_registry.hpp"

#include <memory>
#include <mutex>
#include <string>
#include <utility>

#include "pipeline.pb.h"
#include "rac/graph/pipeline_node.hpp"

namespace rac::solutions {

namespace {

using rac::graph::OverflowPolicy;
using rac::graph::PipelineNode;
using rac::graph::StreamEdge;

// ---------------------------------------------------------------------------
// Built-in operator nodes. These handle the "glue" topology that every
// non-trivial pipeline needs — a source to inject items, a sink to
// silently drain them, and an echo that forwards whatever it receives.
// Real engines register richer operators ("transcribe", "generate_text",
// …) that replace or augment these defaults.
// ---------------------------------------------------------------------------

class EchoNode final : public OperatorNode {
public:
    explicit EchoNode(std::string name)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8,
                       OverflowPolicy::BlockProducer) {}

protected:
    void process(Item item, OutputEdge& out) override {
        // Identity forward. StreamEdge::push returns false on cancel;
        // we honour that by short-circuiting the loop upstream via the
        // cancel token wired into the node base class.
        out.push(std::move(item), this->cancel_token());
    }
};

/// Prepends a per-operator tag to every item before forwarding it.
/// Used as the default for real operator types (e.g. "transcribe",
/// "generate_text") when a frontend hasn't installed an engine-backed
/// factory yet. The tag makes it trivial for tests to verify that a
/// payload flowed through the expected chain of operators.
class TaggedEchoNode final : public OperatorNode {
public:
    TaggedEchoNode(std::string name, std::string tag)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 8,
                       OverflowPolicy::BlockProducer),
          tag_(std::move(tag)) {}

protected:
    void process(Item item, OutputEdge& out) override {
        Item annotated = tag_;
        annotated.push_back(':');
        annotated.append(std::move(item));
        out.push(std::move(annotated), this->cancel_token());
    }

private:
    std::string tag_;
};

/// Terminal drain — pops, discards, never forwards.
class SinkNode final : public OperatorNode {
public:
    explicit SinkNode(std::string name)
        : PipelineNode(std::move(name), /*input*/ 8, /*output*/ 1,
                       OverflowPolicy::BlockProducer) {}

protected:
    void process(Item /*item*/, OutputEdge& /*out*/) override {
        // Intentionally empty — the sink absorbs the item. We leave
        // the output edge in place (and it stays closed on drain) so
        // the scheduler's "every node has an output" invariant holds.
    }
};

OperatorFactory make_echo_factory() {
    return [](const runanywhere::v1::OperatorSpec& spec)
               -> std::shared_ptr<OperatorNode> {
        return std::make_shared<EchoNode>(spec.name());
    };
}

OperatorFactory make_sink_factory() {
    return [](const runanywhere::v1::OperatorSpec& spec)
               -> std::shared_ptr<OperatorNode> {
        return std::make_shared<SinkNode>(spec.name());
    };
}

OperatorFactory make_tagged_factory(std::string tag) {
    return [tag = std::move(tag)](const runanywhere::v1::OperatorSpec& spec)
               -> std::shared_ptr<OperatorNode> {
        return std::make_shared<TaggedEchoNode>(spec.name(), tag);
    };
}

// Source is identical to Echo at the operator level — the executor
// treats any operator reachable only via outbound edges as a root and
// wires the externally-accessible input edge to the first such node
// it sees.

}  // namespace

OperatorRegistry& OperatorRegistry::instance() {
    // Meyers singleton — thread-safe in C++11+.
    static OperatorRegistry* s = [] {
        auto* inst = new OperatorRegistry();
        register_builtin_operators(*inst);
        return inst;
    }();
    return *s;
}

OperatorRegistry::OperatorRegistry() = default;

bool OperatorRegistry::register_factory(const std::string& type,
                                        OperatorFactory    factory) {
    auto [it, inserted] = factories_.insert_or_assign(type, std::move(factory));
    (void)it;
    return inserted;
}

void OperatorRegistry::unregister_factory(const std::string& type) noexcept {
    factories_.erase(type);
}

std::shared_ptr<OperatorNode> OperatorRegistry::create(
    const runanywhere::v1::OperatorSpec& spec) const {
    auto it = factories_.find(spec.type());
    if (it == factories_.end()) return nullptr;
    return it->second(spec);
}

bool OperatorRegistry::has_factory(const std::string& type) const noexcept {
    return factories_.find(type) != factories_.end();
}

void OperatorRegistry::clear() noexcept {
    factories_.clear();
}

void register_builtin_operators(OperatorRegistry& registry) {
    // Neutral scaffolding types.
    registry.register_factory("source", make_echo_factory());
    registry.register_factory("echo",   make_echo_factory());
    registry.register_factory("sink",   make_sink_factory());

    // Default stand-ins for the engine-backed primitives. These let
    // PipelineSpecs that use the real operator names ("transcribe",
    // "generate_text", "synthesize", "detect_voice", "embed",
    // "rerank", "tokenize", "window") compile into a runnable DAG
    // before any engine plugin registers a replacement factory.
    // Frontends/engines override these at startup with real nodes.
    registry.register_factory("transcribe",     make_tagged_factory("stt"));
    registry.register_factory("generate_text",  make_tagged_factory("llm"));
    registry.register_factory("synthesize",     make_tagged_factory("tts"));
    registry.register_factory("detect_voice",   make_tagged_factory("vad"));
    registry.register_factory("embed",          make_tagged_factory("embed"));
    registry.register_factory("rerank",         make_tagged_factory("rerank"));
    registry.register_factory("tokenize",       make_tagged_factory("tok"));
    registry.register_factory("window",         make_tagged_factory("win"));
    registry.register_factory("retrieve",       make_tagged_factory("retrieve"));
    registry.register_factory("context_build",  make_tagged_factory("ctx"));
    registry.register_factory("anomaly_detect", make_tagged_factory("anomaly"));
}

}  // namespace rac::solutions
