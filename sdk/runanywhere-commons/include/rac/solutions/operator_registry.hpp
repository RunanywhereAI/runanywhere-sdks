// SPDX-License-Identifier: Apache-2.0
//
// rac/solutions/operator_registry.hpp — T4.7 pluggable operator table.
//
// The PipelineExecutor walks a `PipelineSpec` and asks the registry to
// materialize a concrete pipeline node for every `OperatorSpec`. Each
// operator type (e.g. "transcribe", "generate_text", "embed", "source",
// "sink", "echo") is represented by a factory registered by string name.
//
// Keeping operator construction behind this interface means:
//   * The scheduler-build logic is independent of specific engines; the
//     executor works the moment at least one factory is registered for
//     every type appearing in the spec.
//   * Downstream SDKs can inject real VAD/STT/LLM/TTS nodes by plugging
//     their factories in at startup; tests register light-weight echo /
//     source / sink stubs with zero engine dependencies.
//   * The registry ships with a small set of built-in neutral operators
//     ("source" — emits a seed item, "sink" — drains silently, "echo" —
//     identity) so unit tests and examples run out of the box.
//
// Thread-safety: factory (de)registration happens at static-init time or
// from the configuring thread before PipelineExecutor::build() runs.
// Concurrent mutation during build is not supported.
//
// SOLID:
//   * Open/closed: new operator types plug in via register_factory.
//   * Dependency inversion: executor depends on this abstraction, never
//     on concrete STT/LLM/TTS vtables.

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <unordered_map>

#include "pipeline.pb.h"
#include "rac/graph/pipeline_node.hpp"

namespace rac::solutions {

/// Neutral edge payload used by the executor. We deliberately pick a
/// single type (std::string) so the scheduler can wire any operator to
/// any other without per-edge type juggling. Real engines wrap their
/// domain payloads (audio frames / tokens / embeddings) as serialized
/// strings or pass them as opaque metadata via side channels. This is
/// the minimum surface area required to demonstrate that PipelineSpec
/// correctly drives a live GraphScheduler.
using Item = std::string;

using OperatorEdge  = rac::graph::StreamEdge<Item>;
using OperatorNode  = rac::graph::PipelineNode<Item, Item>;

/// Factory signature — called once per OperatorSpec. The factory owns
/// interpretation of `spec.params()` and `spec.model_id()` and returns
/// a fully constructed (but not yet started) pipeline node.
using OperatorFactory = std::function<std::shared_ptr<OperatorNode>(
    const runanywhere::v1::OperatorSpec& spec)>;

/// Process-wide operator factory table.
class OperatorRegistry {
public:
    static OperatorRegistry& instance();

    /// Register / replace the factory for an operator type. Returns
    /// true on first registration, false on replacement (mirrors
    /// std::unordered_map::insert_or_assign semantics and is surfaced
    /// so callers can detect duplicate-registration bugs in tests).
    bool register_factory(const std::string& type, OperatorFactory factory);

    /// Remove a factory. No-op if absent. Used by tests to reset state
    /// between scenarios.
    void unregister_factory(const std::string& type) noexcept;

    /// Build a node for `spec` using the factory registered for
    /// `spec.type()`. Returns nullptr when no factory is registered —
    /// the executor surfaces this as RAC_ERROR_NOT_FOUND / validation.
    std::shared_ptr<OperatorNode> create(
        const runanywhere::v1::OperatorSpec& spec) const;

    bool has_factory(const std::string& type) const noexcept;

    /// Wipe every factory. Intended for tests only.
    void clear() noexcept;

    OperatorRegistry(const OperatorRegistry&)            = delete;
    OperatorRegistry& operator=(const OperatorRegistry&) = delete;

private:
    OperatorRegistry();

    std::unordered_map<std::string, OperatorFactory> factories_;
};

/// Convenience: register the set of always-available neutral
/// operators ("echo", "source", "sink"). Called from
/// OperatorRegistry::instance() on first access — callers rarely need
/// to invoke this directly, but tests use it after clear() to restore
/// a known baseline.
void register_builtin_operators(OperatorRegistry& registry);

}  // namespace rac::solutions
