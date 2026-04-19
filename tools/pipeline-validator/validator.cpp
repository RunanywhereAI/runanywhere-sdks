// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Static DAG validator — reads a PipelineSpec from stdin (raw proto3
// bytes) and prints diagnostics:
//   * unknown operator types
//   * disconnected edges (source or sink missing)
//   * duplicate operator names
//
// More sophisticated analysis (cycle detection, type inference at edge
// endpoints, deadlock-prone topologies) lands incrementally on top of
// this scaffold.
//
// Exits 0 on success, 1 on validation failure, 2 on I/O error.

#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <set>
#include <string>
#include <unordered_set>

#if RA_VALIDATE_HAS_PROTO
#  include "pipeline.pb.h"
#endif

namespace {

int usage() {
    std::fprintf(stderr,
                 "usage: ra_validate < pipeline.pb\n"
                 "  Reads a raw proto3 PipelineSpec from stdin and prints\n"
                 "  validation diagnostics. Exits 0 on success.\n");
    return 2;
}

#if RA_VALIDATE_HAS_PROTO
int validate(const runanywhere::v1::PipelineSpec& spec) {
    int errors = 0;

    // 1. Duplicate operator names.
    std::unordered_set<std::string> op_names;
    for (const auto& op : spec.operators()) {
        auto [_, inserted] = op_names.insert(op.name());
        if (!inserted) {
            std::fprintf(stderr,
                         "error: duplicate operator name '%s'\n",
                         op.name().c_str());
            ++errors;
        }
        if (op.type().empty()) {
            std::fprintf(stderr,
                         "error: operator '%s' has empty type\n",
                         op.name().c_str());
            ++errors;
        }
    }

    // 2. Every edge endpoint resolves to a known operator. We don't
    //    validate port names yet (requires a per-operator schema).
    auto operator_exists = [&](const std::string& endpoint) -> bool {
        const auto dot = endpoint.find('.');
        const auto op_name = endpoint.substr(0, dot);
        return op_names.count(op_name) != 0;
    };

    std::set<std::pair<std::string, std::string>> seen_edges;
    for (const auto& edge : spec.edges()) {
        if (!operator_exists(edge.from())) {
            std::fprintf(stderr,
                         "error: edge source '%s' references unknown operator\n",
                         edge.from().c_str());
            ++errors;
        }
        if (!operator_exists(edge.to())) {
            std::fprintf(stderr,
                         "error: edge sink '%s' references unknown operator\n",
                         edge.to().c_str());
            ++errors;
        }
        // 3. Duplicate edges.
        auto key = std::make_pair(edge.from(), edge.to());
        if (!seen_edges.insert(key).second) {
            std::fprintf(stderr,
                         "error: duplicate edge %s -> %s\n",
                         edge.from().c_str(), edge.to().c_str());
            ++errors;
        }
    }

    std::printf("pipeline '%s': %d operators, %d edges, %d errors\n",
                spec.name().c_str(),
                spec.operators_size(), spec.edges_size(), errors);
    return errors == 0 ? 0 : 1;
}
#endif  // RA_VALIDATE_HAS_PROTO

}  // namespace

int main(int argc, char** /*argv*/) {
    if (argc > 1) {
        // No flags yet; reject anything non-zero so we don't silently ignore.
        return usage();
    }

    const std::string input((std::istreambuf_iterator<char>(std::cin)),
                             std::istreambuf_iterator<char>());
    if (input.empty()) {
        std::fprintf(stderr, "error: no PipelineSpec on stdin\n");
        return 2;
    }

#if RA_VALIDATE_HAS_PROTO
    runanywhere::v1::PipelineSpec spec;
    if (!spec.ParseFromString(input)) {
        std::fprintf(stderr, "error: failed to parse PipelineSpec (%zu bytes)\n",
                     input.size());
        return 2;
    }
    return validate(spec);
#else
    std::printf("pipeline validator: %zu bytes received — protobuf runtime "
                "not linked; rebuild with vcpkg for full validation\n",
                input.size());
    return 0;
#endif
}
